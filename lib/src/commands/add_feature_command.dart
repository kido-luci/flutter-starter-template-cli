import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:interact/interact.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import '../feature_manifest.dart';
import '../feature_names.dart';
import '../project_snapshot.dart';
import '../rewrite/feature_template.dart';
import '../rewrite/feature_wiring.dart';
import '../validators.dart';

typedef ProcessExecutor = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

Future<ProcessResult> _defaultProcessExecutor(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) =>
    Process.run(executable, arguments, workingDirectory: workingDirectory);

/// Scaffolds a new feature package and wires it into the app (workspace,
/// dependency, DI module, and `enabledFeatures`).
///
/// Use `--source` to control which layers are generated:
/// - `presentation` (default) — UI layer only, identical to the original scaffold.
/// - `local` — adds domain (entity + repository interface) and a data layer
///   with an in-memory store. No network or database dependencies.
/// - `api` — adds domain and a remote data layer via Retrofit + Dio.
/// - `sync` — everything in `api` plus offline-first sync stubs (see
///   the generated `SYNC_TODO.md` for the manual steps).
class AddFeatureCommand extends Command<int> {
  AddFeatureCommand(
    this._logger, {
    ProcessExecutor processExecutor = _defaultProcessExecutor,
    String? rootDirectory,
  })  : _processExecutor = processExecutor,
        _rootDirectory = rootDirectory {
    argParser
      ..addFlag(
        'no-codegen',
        negatable: false,
        help: 'Skip `flutter pub get` + build_runner after scaffolding.',
      )
      ..addOption(
        'source',
        abbr: 's',
        allowed: ['presentation', 'local', 'api', 'sync'],
        allowedHelp: {
          'presentation': 'Presentation layer only (default).',
          'local':
              'Adds domain + in-memory data layer. No network/database deps.',
          'api': 'Adds domain + remote API data layer (Retrofit/Dio).',
          'sync':
              'Adds domain + remote API + offline-first sync stubs (rev_sync).',
        },
        help: 'The kind of data+domain layer to scaffold alongside the '
            'presentation layer.',
        valueHelp: 'kind',
      )
      ..addOption(
        'route-path',
        help: 'Absolute static route path. Defaults to /<feature-name>.',
        valueHelp: '/path',
      );
  }

  final Logger _logger;
  final ProcessExecutor _processExecutor;
  final String? _rootDirectory;

  @override
  String get name => 'add-feature';

  @override
  String get description => 'Scaffold and wire a new feature package. '
      'Use --source to add domain/data layers (local, api, sync).';

  @override
  String get invocation =>
      'fst add-feature <name> [--source presentation|local|api|sync] '
      '[--route-path /path] [--no-codegen]';

  @override
  Future<int> run() async {
    final root = _rootDirectory ?? Directory.current.path;
    if (!_isProjectRoot(root)) {
      _logger.err(
        'Run this from the project root (the directory with pubspec.yaml and '
        'lib/app/features.dart).',
      );
      return 1;
    }

    final rawName = _resolveName();
    if (!isValidPackageName(rawName)) {
      _logger.err(
        'Invalid feature name "$rawName" — use snake_case: lowercase letters, '
        'digits, and underscores, with no leading digit.',
      );
      return 1;
    }

    final source = _resolveSource();
    try {
      _validateSourcePrerequisites(root, source);
    } on FeatureWiringException catch (error) {
      _logger.err(error.message);
      return 1;
    }

    final names = FeatureNames(rawName);
    final featureDir = p.join(root, 'packages', 'features', names.snake);
    if (Directory(featureDir).existsSync()) {
      _logger.err(
        'Feature already exists: ${p.relative(featureDir, from: root)}',
      );
      return 1;
    }
    final String routePath;
    try {
      routePath = validateFeatureRoutePath(
        (argResults?['route-path'] as String?) ?? '/${names.kebab}',
      );
      validateFeatureRouteAvailability(root, names, routePath);
    } on FeatureWiringException catch (error) {
      _logger.err(error.message);
      return 1;
    }

    // Pre-compute the app wiring before touching disk. Each transform throws
    // FeatureWiringException if its marker is missing, so a misconfigured
    // project fails here — before anything is scaffolded or rewritten — instead
    // of leaving a half-wired tree.
    final Map<String, String> wiringEdits;
    try {
      wiringEdits = _planWiring(root, names);
    } on FeatureWiringException catch (error) {
      _logger.err(error.message);
      return 1;
    }

    final snapshot = ProjectSnapshot.capture(root);
    final scaffold = _logger.progress('Scaffolding ${names.package}');
    try {
      featureFiles(
        names,
        source: source,
        routePath: routePath,
      ).forEach((relative, content) {
        final file = File(p.join(featureDir, p.joinAll(relative.split('/'))));
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(content);
      });
      writeFeatureManifest(
        featureDir,
        names: names,
        source: source,
        routePath: routePath,
      );
      scaffold.complete('Scaffolded ${names.package}');
    } on Object catch (error) {
      scaffold.fail('Scaffold failed');
      snapshot.restore();
      _deleteFeatureDirectory(featureDir);
      _logger.err('$error');
      return 1;
    }

    final wire = _logger.progress('Wiring into the app');
    try {
      wiringEdits.forEach(
        (path, content) => File(path).writeAsStringSync(content),
      );
      wire.complete('Wired into the app');
    } on Object catch (error) {
      // Markers were validated above, so this is an unexpected I/O failure.
      // Roll back the scaffolded package so the run leaves no half-wired tree.
      wire.fail('Wiring failed');
      snapshot.restore();
      _deleteFeatureDirectory(featureDir);
      _logger.err('$error');
      return 1;
    }

    if (argResults?['no-codegen'] as bool? ?? false) {
      _logger.info(
        'Skipped codegen (--no-codegen). Run `flutter pub get` then '
        '`dart run build_runner build --delete-conflicting-outputs` before '
        'building.',
      );
    } else {
      var succeeded = false;
      try {
        succeeded =
            await _runCodegen(root, featureDir) && await _verifyProject(root);
      } on Object catch (error) {
        _logger.err('$error');
      }
      if (!succeeded) {
        final rollback = _logger.progress('Rolling back failed feature');
        snapshot.restore();
        _deleteFeatureDirectory(featureDir);
        rollback.complete('Restored the original project');
        return 1;
      }
    }

    _logger
      ..success(
        'Feature ${names.package} created and wired (source: ${source.name}).',
      )
      ..info('  Screen route: $routePath (${names.routeName})')
      ..info('  Edit packages/features/${names.snake}/ to flesh it out.');

    if (source == FeatureSource.sync) {
      _logger.info(
        '  See packages/features/${names.snake}/SYNC_TODO.md for the manual '
        'steps to complete offline-first sync.',
      );
    }

    return 0;
  }

  String _resolveName() {
    final positional = argResults?.rest ?? const [];
    if (positional.isNotEmpty) return positional.first.trim();
    return Input(
      prompt: 'Feature name (snake_case)',
      validator: (value) {
        if (!isValidPackageName(value)) {
          throw ValidationError(
            'lowercase letters, digits, underscores; no leading digit.',
          );
        }
        return true;
      },
    ).interact();
  }

  /// Resolves the `--source` option, prompting interactively when omitted.
  FeatureSource _resolveSource() {
    final raw = argResults?['source'] as String?;
    if (raw != null) return _parseSource(raw);
    final options = ['presentation', 'local', 'api', 'sync'];
    final index = Select(
      prompt: 'Data source',
      options: options,
      initialIndex: 0,
    ).interact();
    return _parseSource(options[index]);
  }

  FeatureSource _parseSource(String value) => switch (value) {
        'presentation' => FeatureSource.presentation,
        'local' => FeatureSource.local,
        'api' => FeatureSource.api,
        'sync' => FeatureSource.sync,
        _ => FeatureSource.presentation,
      };

  void _validateSourcePrerequisites(String root, FeatureSource source) {
    if ((source == FeatureSource.api || source == FeatureSource.sync) &&
        !File(p.join(root, 'packages', 'network', 'pubspec.yaml'))
            .existsSync()) {
      throw FeatureWiringException(
        'The ${source.name} source requires the workspace network package, '
        'but this project was generated without it.',
      );
    }
    if (source == FeatureSource.sync &&
        !File(p.join(root, 'published', 'rev_sync', 'pubspec.yaml'))
            .existsSync()) {
      throw FeatureWiringException(
        'The sync source requires published/rev_sync, but this project was '
        'generated without the sync engine.',
      );
    }
  }

  bool _isProjectRoot(String root) =>
      File(p.join(root, 'pubspec.yaml')).existsSync() &&
      File(p.join(root, 'lib', 'app', 'features.dart')).existsSync();

  /// Computes all app-wiring file rewrites in memory, keyed by path.
  ///
  /// Pure: it only reads and transforms, never writes. A missing marker makes
  /// the relevant transform throw [FeatureWiringException], which is how the
  /// caller validates the project before scaffolding.
  Map<String, String> _planWiring(String root, FeatureNames names) {
    final pubspec = p.join(root, 'pubspec.yaml');
    final injection = p.join(root, 'lib', 'app', 'di', 'injection.dart');
    final features = p.join(root, 'lib', 'app', 'features.dart');
    final layering = p.join(
      root,
      'test',
      'architecture',
      'package_layering_test.dart',
    );
    return {
      pubspec: addFeatureToPubspec(File(pubspec).readAsStringSync(), names),
      injection: addFeatureToInjection(
        File(injection).readAsStringSync(),
        names,
      ),
      features: addFeatureToFeatures(File(features).readAsStringSync(), names),
      layering: addFeatureToLayeringTest(
        File(layering).readAsStringSync(),
        names,
      ),
    };
  }

  Future<bool> _runCodegen(String root, String featureDir) async {
    final useFvm = File(p.join(root, '.fvmrc')).existsSync() && _hasFvm();

    final pubGet = _logger.progress('Resolving dependencies (pub get)');
    final pubResult = await _processExecutor(
        useFvm ? 'fvm' : 'flutter',
        [
          if (useFvm) 'flutter',
          'pub',
          'get',
        ],
        workingDirectory: root);
    if (pubResult.exitCode != 0) {
      pubGet.fail('pub get failed');
      _logger.err(pubResult.stderr as String);
      return false;
    }
    pubGet.complete('Dependencies resolved');

    // Build the new feature plus any feature left without a generated
    // micro-package module by an earlier --no-codegen run, then refresh the app
    // DI graph. Unrelated workspace packages are left untouched.
    final featureTargets = _pendingFeatureCodegenTargets(root, featureDir);
    for (final target in <(String, String)>[
      for (final path in featureTargets)
        (path, 'feature package ${p.basename(path)}'),
      (root, 'app DI graph'),
    ]) {
      final codegen = _logger.progress('Generating ${target.$2}');
      final codegenResult = await _processExecutor(
        useFvm ? 'fvm' : 'dart',
        [
          if (useFvm) 'dart',
          'run',
          'build_runner',
          'build',
          '--delete-conflicting-outputs',
        ],
        workingDirectory: target.$1,
      );
      if (codegenResult.exitCode != 0) {
        codegen.fail('${target.$2} generation failed');
        _logger
          ..err(codegenResult.stderr as String)
          ..warn(codegenResult.stdout as String);
        return false;
      }
      codegen.complete('${target.$2} generated');
    }
    return true;
  }

  List<String> _pendingFeatureCodegenTargets(
    String root,
    String featureDir,
  ) {
    final targets = <String>{featureDir};
    final features = Directory(p.join(root, 'packages', 'features'));
    if (features.existsSync()) {
      for (final entity in features.listSync(followLinks: false)) {
        if (entity is! Directory) continue;
        final anchor = File(p.join(entity.path, 'lib', 'src', 'di.dart'));
        final module =
            File(p.join(entity.path, 'lib', 'src', 'di.module.dart'));
        if (anchor.existsSync() && !module.existsSync()) {
          targets.add(entity.path);
        }
      }
    }
    return targets.toList()..sort();
  }

  void _deleteFeatureDirectory(String featureDir) {
    final directory = Directory(featureDir);
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }

  Future<bool> _verifyProject(String root) async {
    final useFvm = File(p.join(root, '.fvmrc')).existsSync() && _hasFvm();
    for (final check in <(String, List<String>, String)>[
      (
        useFvm ? 'fvm' : 'flutter',
        [if (useFvm) 'flutter', 'analyze'],
        'analysis',
      ),
      (
        useFvm ? 'fvm' : 'flutter',
        [if (useFvm) 'flutter', 'test'],
        'tests',
      ),
    ]) {
      final progress = _logger.progress('Verifying ${check.$3}');
      final result = await _processExecutor(
        check.$1,
        check.$2,
        workingDirectory: root,
      );
      if (result.exitCode != 0) {
        progress.fail('${check.$3} failed');
        _logger
          ..err(result.stderr as String)
          ..warn(result.stdout as String);
        return false;
      }
      progress.complete('${check.$3} passed');
    }
    return true;
  }

  bool _hasFvm() {
    try {
      return Process.runSync('fvm', ['--version']).exitCode == 0;
    } on Object {
      return false;
    }
  }
}
