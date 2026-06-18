import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:interact/interact.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import '../feature_names.dart';
import '../rewrite/feature_template.dart';
import '../rewrite/feature_wiring.dart';
import '../validators.dart';

/// Scaffolds a new presentation-only feature package and wires it into the app
/// (workspace, dependency, DI module, and `enabledFeatures`).
class AddFeatureCommand extends Command<int> {
  AddFeatureCommand(this._logger) {
    argParser.addFlag(
      'no-codegen',
      negatable: false,
      help: 'Skip `flutter pub get` + build_runner after scaffolding.',
    );
  }

  final Logger _logger;

  @override
  String get name => 'add-feature';

  @override
  String get description =>
      'Scaffold and wire a new presentation-only feature package.';

  @override
  String get invocation => 'fst add-feature <name> [--no-codegen]';

  @override
  Future<int> run() async {
    final root = Directory.current.path;
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

    final names = FeatureNames(rawName);
    final featureDir = p.join(root, 'packages', 'features', names.snake);
    if (Directory(featureDir).existsSync()) {
      _logger.err(
        'Feature already exists: ${p.relative(featureDir, from: root)}',
      );
      return 1;
    }

    final scaffold = _logger.progress('Scaffolding ${names.package}');
    try {
      featureFiles(names).forEach((relative, content) {
        final file = File(p.join(featureDir, p.joinAll(relative.split('/'))));
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(content);
      });
      scaffold.complete('Scaffolded ${names.package}');
    } on Object catch (error) {
      scaffold.fail('Scaffold failed');
      _logger.err('$error');
      return 1;
    }

    final wire = _logger.progress('Wiring into the app');
    try {
      _rewrite(
        p.join(root, 'pubspec.yaml'),
        (content) => addFeatureToPubspec(content, names),
      );
      _rewrite(
        p.join(root, 'lib', 'app', 'di', 'injection.dart'),
        (content) => addFeatureToInjection(content, names),
      );
      _rewrite(
        p.join(root, 'lib', 'app', 'features.dart'),
        (content) => addFeatureToFeatures(content, names),
      );
      wire.complete('Wired into the app');
    } on FeatureWiringException catch (error) {
      wire.fail('Wiring failed');
      _logger.err(error.message);
      _logger.warn(
        'Scaffolded files left at ${p.relative(featureDir, from: root)} for '
        'inspection.',
      );
      return 1;
    }

    if (argResults?['no-codegen'] as bool? ?? false) {
      _logger.info(
        'Skipped codegen (--no-codegen). Run `flutter pub get` then '
        '`dart run build_runner build --delete-conflicting-outputs` before '
        'building.',
      );
    } else if (!await _runCodegen(root)) {
      return 1;
    }

    _logger
      ..success('Feature ${names.package} created and wired.')
      ..info('  Screen route: /${names.kebab}')
      ..info('  Edit packages/features/${names.snake}/ to flesh it out.');
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

  bool _isProjectRoot(String root) =>
      File(p.join(root, 'pubspec.yaml')).existsSync() &&
      File(p.join(root, 'lib', 'app', 'features.dart')).existsSync();

  void _rewrite(String path, String Function(String) transform) {
    final file = File(path);
    file.writeAsStringSync(transform(file.readAsStringSync()));
  }

  Future<bool> _runCodegen(String root) async {
    final useFvm = File(p.join(root, '.fvmrc')).existsSync() && _hasFvm();

    final pubGet = _logger.progress('Resolving dependencies (pub get)');
    final pubResult = await Process.run(
      useFvm ? 'fvm' : 'flutter',
      [if (useFvm) 'flutter', 'pub', 'get'],
      workingDirectory: root,
    );
    if (pubResult.exitCode != 0) {
      pubGet.fail('pub get failed');
      _logger.err(pubResult.stderr as String);
      return false;
    }
    pubGet.complete('Dependencies resolved');

    // Delegate to the project's own codegen entrypoint: a feature's
    // di.module.dart is only generated by build_runner running *inside* its
    // package, which tool/codegen.sh does (each feature first, then the app
    // root). Run it under `fvm exec` so the pinned SDK is on PATH.
    final script = p.join('tool', 'codegen.sh');
    if (!File(p.join(root, script)).existsSync()) {
      _logger.warn(
        'tool/codegen.sh not found — generate code yourself before building.',
      );
      return true;
    }

    final codegen = _logger.progress('Generating code (tool/codegen.sh)');
    final codegenResult = await Process.run(
      useFvm ? 'fvm' : 'bash',
      [if (useFvm) 'exec', if (useFvm) 'bash', script],
      workingDirectory: root,
    );
    if (codegenResult.exitCode != 0) {
      codegen.fail('codegen failed');
      _logger
        ..err(codegenResult.stderr as String)
        ..warn(codegenResult.stdout as String);
      return false;
    }
    codegen.complete('Code generated');
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
