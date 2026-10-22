import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:interact/interact.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import '../feature_discovery.dart';
import '../feature_names.dart';
import '../project_snapshot.dart';
import '../rewrite/feature_wiring.dart';

typedef RemoveProcessExecutor = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

typedef RemovalConfirmation = bool Function(String prompt);

Future<ProcessResult> _defaultProcessExecutor(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) =>
    Process.run(executable, arguments, workingDirectory: workingDirectory);

bool _defaultConfirmation(String prompt) =>
    Confirm(prompt: prompt, defaultValue: false).interact();

final class FeatureRemovalPlan {
  const FeatureRemovalPlan({
    required this.feature,
    required this.modifiedFiles,
    required this.deletedDirectories,
  });

  final DiscoveredFeature feature;
  final Map<String, String> modifiedFiles;
  final List<String> deletedDirectories;
}

FeatureRemovalPlan planFeatureRemoval(String root, DiscoveredFeature feature) {
  final names = FeatureNames(feature.id);
  final pubspec = p.join(root, 'pubspec.yaml');
  final injection = p.join(root, 'lib', 'app', 'di', 'injection.dart');
  final features = p.join(root, 'lib', 'app', 'features.dart');
  final layering = p.join(
    root,
    'test',
    'architecture',
    'package_layering_test.dart',
  );
  for (final path in [pubspec, injection, features, layering]) {
    if (!File(path).existsSync()) {
      throw FeatureWiringException(
        'Required project file is missing: ${p.relative(path, from: root)}',
      );
    }
  }
  return FeatureRemovalPlan(
    feature: feature,
    modifiedFiles: {
      pubspec: removeFeatureFromPubspec(
        File(pubspec).readAsStringSync(),
        names,
      ),
      injection: removeFeatureFromInjection(
        File(injection).readAsStringSync(),
        names,
      ),
      features: removeFeatureFromFeatures(
        File(features).readAsStringSync(),
        names,
      ),
      layering: removeFeatureFromLayeringTest(
        File(layering).readAsStringSync(),
        names,
      ),
    },
    deletedDirectories: [p.join(root, feature.directory)],
  );
}

final class RemoveFeatureCommand extends Command<int> {
  RemoveFeatureCommand(
    this._logger, {
    RemoveProcessExecutor processExecutor = _defaultProcessExecutor,
    RemovalConfirmation confirmation = _defaultConfirmation,
    String? rootDirectory,
    bool? interactive,
  })  : _processExecutor = processExecutor,
        _confirmation = confirmation,
        _rootDirectory = rootDirectory,
        _interactive = interactive {
    argParser
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Print the validated removal plan without writing any file.',
      )
      ..addFlag(
        'yes',
        abbr: 'y',
        negatable: false,
        help: 'Confirm removal in non-interactive mode.',
      )
      ..addFlag(
        'force-modified',
        negatable: false,
        help: 'Explicitly authorize deletion of changed files inside a '
            'manifest-owned feature.',
      );
  }

  final Logger _logger;
  final RemoveProcessExecutor _processExecutor;
  final RemovalConfirmation _confirmation;
  final String? _rootDirectory;
  final bool? _interactive;

  @override
  String get name => 'remove-feature';

  @override
  String get description =>
      'Safely remove a CLI-owned feature and validate the resulting project.';

  @override
  String get invocation =>
      'fst remove-feature <name> [--dry-run] [--yes] [--force-modified]';

  @override
  Future<int> run() async {
    final root = _rootDirectory ?? Directory.current.path;
    final positional = argResults?.rest ?? const [];
    if (positional.length != 1) {
      _logger.err('Provide exactly one feature name.');
      return 64;
    }
    final inventory = discoverFeatures(root);
    final feature = inventory.find(positional.single.trim());
    if (feature == null) {
      _logger.err('Feature not found: ${positional.single}');
      return 1;
    }
    if (!feature.owned) {
      _logger.err(
        '${feature.package} is not proven to be CLI-owned; no files were deleted.',
      );
      return 1;
    }
    final reverse = inventory.reverseDependencies(feature.package);
    if (reverse.isNotEmpty) {
      _logger.err(
        'Cannot remove ${feature.package}; required by '
        '${reverse.map((item) => item.package).join(', ')}.',
      );
      return 1;
    }
    final forceModified = argResults?['force-modified'] as bool? ?? false;
    if (feature.hasUserChanges && !forceModified) {
      _logger.err(
        '${feature.package} contains modified or unknown files. '
        'Review them and rerun with --force-modified to explicitly authorize '
        'their deletion.',
      );
      for (final path in feature.modifiedFiles) {
        _logger.warn('Modified: ${feature.directory}/$path');
      }
      for (final path in feature.unknownFiles) {
        _logger.warn('Unknown: ${feature.directory}/$path');
      }
      return 1;
    }

    final FeatureRemovalPlan plan;
    try {
      plan = planFeatureRemoval(root, feature);
    } on FeatureWiringException catch (error) {
      _logger.err(error.message);
      return 1;
    }
    _printPlan(plan, reverse);
    if (argResults?['dry-run'] as bool? ?? false) return 0;

    final confirmed = argResults?['yes'] as bool? ?? false;
    if (!confirmed) {
      if (!(_interactive ?? stdin.hasTerminal)) {
        _logger.err('Non-interactive removal requires --yes.');
        return 1;
      }
      if (!_confirmation('Remove ${feature.package}?')) {
        _logger.info('Removal cancelled.');
        return 0;
      }
    }

    final snapshot = ProjectSnapshot.capture(root);
    try {
      for (final entry in plan.modifiedFiles.entries) {
        File(entry.key).writeAsStringSync(entry.value, flush: true);
      }
      for (final path in plan.deletedDirectories) {
        Directory(path).deleteSync(recursive: true);
      }
      final postRemoval = discoverFeatures(root);
      if (postRemoval.issues.isNotEmpty) {
        throw FeatureWiringException(postRemoval.issues.join('\n'));
      }
      if (!await _regenerateAndVerify(root)) {
        throw FeatureWiringException('Generated project validation failed.');
      }
    } on Object catch (error) {
      final rollback = _logger.progress('Rolling back failed removal');
      snapshot.restore();
      rollback.complete('Restored the original project');
      _logger.err('$error');
      return 1;
    }
    _logger.success('Removed ${feature.package} and validated the project.');
    return 0;
  }

  void _printPlan(
    FeatureRemovalPlan plan,
    List<DiscoveredFeature> reverse,
  ) {
    _logger.info('Removal plan for ${plan.feature.package}:');
    for (final directory in plan.deletedDirectories) {
      _logger.info('  DELETE ${p.relative(directory)}');
    }
    for (final file in plan.modifiedFiles.keys) {
      _logger.info('  MODIFY ${p.relative(file)}');
    }
    _logger.info(
      '  ROUTES ${plan.feature.routePath ?? '-'}, '
      '${plan.feature.routeNames.join(', ')}',
    );
    _logger.info('  DI ${plan.feature.packageModuleName}');
    _logger.info(
      '  DEPENDENTS ${reverse.isEmpty ? 'none' : reverse.map((f) => f.package).join(', ')}',
    );
    if (plan.feature.hasUserChanges) {
      _logger.warn('  User changes explicitly authorized by --force-modified.');
    }
  }

  Future<bool> _regenerateAndVerify(String root) async {
    final useFvm = File(p.join(root, '.fvmrc')).existsSync() && _hasFvm();
    final commands = <(String, List<String>, String)>[
      (
        useFvm ? 'fvm' : 'flutter',
        [if (useFvm) 'flutter', 'pub', 'get'],
        'dependency resolution',
      ),
      (
        'bash',
        [p.join(root, 'tool', 'codegen.sh')],
        'workspace code generation',
      ),
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
    ];
    for (final command in commands) {
      final progress = _logger.progress('Running ${command.$3}');
      final result = await _processExecutor(
        command.$1,
        command.$2,
        workingDirectory: root,
      );
      if (result.exitCode != 0) {
        progress.fail('${command.$3} failed');
        _logger
          ..err(result.stderr as String)
          ..warn(result.stdout as String);
        return false;
      }
      progress.complete('${command.$3} passed');
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

extension on DiscoveredFeature {
  String get packageModuleName => FeatureNames(id).packageModule;
}
