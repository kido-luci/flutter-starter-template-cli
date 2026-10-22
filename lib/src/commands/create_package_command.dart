import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import '../package_architecture.dart';
import '../package_manifest.dart';
import '../package_spec.dart';
import '../project_snapshot.dart';
import '../rewrite/package_template.dart';
import '../rewrite/package_wiring.dart';
import '../validators.dart';

typedef PackageProcessExecutor = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

Future<ProcessResult> _runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) =>
    Process.run(executable, arguments, workingDirectory: workingDirectory);

final class CreatePackageCommand extends Command<int> {
  CreatePackageCommand(
    this._logger, {
    String? rootDirectory,
    PackageProcessExecutor processExecutor = _runProcess,
  })  : _rootDirectory = rootDirectory,
        _processExecutor = processExecutor {
    argParser
      ..addOption(
        'type',
        abbr: 't',
        mandatory: true,
        allowed: ReusablePackageType.values.map((type) => type.name),
        help: 'Architectural package category.',
      )
      ..addMultiOption(
        'dependency',
        abbr: 'd',
        help: 'Existing workspace package dependency. Repeatable.',
        valueHelp: 'package',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Print the package and wiring plan without writing files.',
      )
      ..addFlag(
        'no-verify',
        negatable: false,
        help: 'Skip pub get, analysis, and package tests after generation.',
      );
  }

  final Logger _logger;
  final String? _rootDirectory;
  final PackageProcessExecutor _processExecutor;

  @override
  String get name => 'create-package';

  @override
  String get description =>
      'Create and register a reusable Dart or Flutter workspace package.';

  @override
  String get invocation => 'fst create-package <name> --type '
      'contracts|infrastructure|platform|ui|dev '
      '[--dependency <package>] [--dry-run] [--no-verify]';

  @override
  Future<int> run() async {
    final root = _rootDirectory ?? Directory.current.path;
    final rootPubspecFile = File(p.join(root, 'pubspec.yaml'));
    final layeringFile = File(
      p.join(root, 'test', 'architecture', 'package_layering_test.dart'),
    );
    if (!rootPubspecFile.existsSync() || !layeringFile.existsSync()) {
      _logger.err('Run this from an fst project root.');
      return 1;
    }

    final positional = argResults?.rest ?? const [];
    if (positional.length != 1) {
      _logger.err('Provide exactly one package name.');
      return 1;
    }
    final packageName = positional.single.trim();
    if (!isValidPackageName(packageName)) {
      _logger.err('Invalid package name "$packageName"; use snake_case.');
      return 1;
    }
    if (packageName.startsWith('feature_')) {
      _logger.err('Feature packages must be created with fst add-feature.');
      return 1;
    }

    final type = ReusablePackageType.parse(argResults!['type'] as String);
    final dependencies = (argResults!['dependency'] as List<String>)
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final packages = discoverWorkspacePackages(root);
    final packageDirectory = p.join(root, 'packages', packageName);
    if (packages.containsKey(packageName) ||
        Directory(packageDirectory).existsSync()) {
      _logger.err('Package already exists: $packageName');
      return 1;
    }

    final rootName = parsePubspecName(rootPubspecFile.readAsStringSync());
    for (final dependency in dependencies) {
      if (dependency == rootName) {
        _logger
            .err('$packageName cannot depend on application shell $rootName.');
        return 1;
      }
      final target = packages[dependency];
      if (target == null) {
        _logger.err('Unknown workspace dependency: $dependency');
        return 1;
      }
      if (dependency.startsWith('feature_')) {
        _logger.err('Reusable packages cannot depend on feature $dependency.');
        return 1;
      }
      if (target.type == null) {
        _logger.err('Cannot determine architectural category for $dependency.');
        return 1;
      }
      if (!isAllowedPackageDependency(type, target.type!)) {
        _logger.err('${type.name} package $packageName cannot depend on '
            '${target.type!.name} package $dependency.');
        return 1;
      }
      if (type != ReusablePackageType.dev && dependency == 'test_utils') {
        _logger.err('Runtime dependency on test_utils is forbidden.');
        return 1;
      }
    }
    if (_wouldCreateCycle(packages, packageName, dependencies.toSet())) {
      _logger.err('Dependencies would create a workspace package cycle.');
      return 1;
    }

    final layeringSource = layeringFile.readAsStringSync();
    final layers = parseArchitectureLayers(layeringSource);
    var layer = type.minimumLayer;
    for (final dependency in dependencies) {
      final dependencyLayer = layers[dependency];
      if (dependencyLayer != null && dependencyLayer >= layer) {
        layer = dependencyLayer + 1;
      }
    }

    final files = reusablePackageFiles(
      name: packageName,
      type: type,
      dependencies: dependencies,
    );
    final rootPubspec = registerWorkspacePackage(
      rootPubspecFile.readAsStringSync(),
      packageName,
    );
    final wiredLayering = registerPackageLayer(
      registerPackageCategory(layeringSource, packageName, type),
      packageName,
      layer,
    );

    _logger.info('Package plan for $packageName:');
    _logger.info('  TYPE ${type.name}');
    _logger.info('  CREATE packages/$packageName');
    for (final relative in files.keys) {
      _logger.info('  CREATE packages/$packageName/$relative');
    }
    _logger.info('  MODIFY pubspec.yaml (workspace)');
    _logger.info('  MODIFY test/architecture/package_layering_test.dart '
        '(category=${type.architectureCategory}, layer=$layer)');
    _logger.info('  DEPENDENCIES '
        '${dependencies.isEmpty ? 'none' : dependencies.join(', ')}');
    if (argResults!['dry-run'] as bool) return 0;

    final snapshot = ProjectSnapshot.capture(root);
    try {
      for (final entry in files.entries) {
        final file = File(
          p.join(packageDirectory, p.joinAll(entry.key.split('/'))),
        );
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(entry.value);
      }
      writePackageManifest(
        packageDirectory,
        PackageManifest(
          name: packageName,
          type: type,
          dependencies: dependencies,
          ownedFiles: files.keys.toList()..sort(),
        ),
      );
      rootPubspecFile.writeAsStringSync(rootPubspec);
      layeringFile.writeAsStringSync(wiredLayering);

      final validation = validateWorkspacePackage(root, packageName);
      if (!validation.isValid) {
        throw StateError(validation.issues.join('\n'));
      }
      if (!(argResults!['no-verify'] as bool) &&
          !await _verify(root, packageDirectory, type)) {
        throw StateError('Generated package verification failed.');
      }
    } on Object catch (error) {
      snapshot.restore();
      _logger.err('$error');
      _logger.info('Rolled back package generation.');
      return 1;
    }

    _logger.success('Created reusable package $packageName.');
    return 0;
  }

  Future<bool> _verify(
    String root,
    String packageDirectory,
    ReusablePackageType type,
  ) async {
    final commands = <(String, List<String>, String)>[
      ('flutter', const ['pub', 'get'], root),
      (
        type.usesFlutter ? 'flutter' : 'dart',
        const ['analyze'],
        packageDirectory
      ),
      (type.usesFlutter ? 'flutter' : 'dart', const ['test'], packageDirectory),
    ];
    for (final command in commands) {
      final result = await _processExecutor(
        command.$1,
        command.$2,
        workingDirectory: command.$3,
      );
      if (result.exitCode != 0) {
        _logger.err('${result.stderr}');
        return false;
      }
    }
    return true;
  }
}

bool _wouldCreateCycle(
  Map<String, WorkspacePackage> packages,
  String packageName,
  Set<String> dependencies,
) {
  bool reachesNewPackage(String current, Set<String> visited) {
    if (!visited.add(current)) return false;
    for (final dependency in packages[current]?.dependencies ?? const {}) {
      if (dependency == packageName ||
          (packages.containsKey(dependency) &&
              reachesNewPackage(dependency, visited))) {
        return true;
      }
    }
    return false;
  }

  return dependencies.any(
    (dependency) => reachesNewPackage(dependency, <String>{}),
  );
}
