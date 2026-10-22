import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:interact/interact.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import '../package_lifecycle.dart';
import '../project_snapshot.dart';
import '../rewrite/package_wiring.dart';
import 'create_package_command.dart';

typedef PackageRemovalConfirmation = bool Function(String prompt);

bool _defaultConfirmation(String prompt) =>
    Confirm(prompt: prompt, defaultValue: false).interact();

final class PackageRemovalPlan {
  const PackageRemovalPlan({
    required this.package,
    required this.modifiedFiles,
    required this.deletedDirectory,
  });

  final DiscoveredPackage package;
  final Map<String, String> modifiedFiles;
  final String deletedDirectory;
}

PackageRemovalPlan planPackageRemoval(
  String root,
  DiscoveredPackage package,
) {
  final pubspec = p.join(root, 'pubspec.yaml');
  final layering = p.join(
    root,
    'test',
    'architecture',
    'package_layering_test.dart',
  );
  for (final path in [pubspec, layering]) {
    if (!File(path).existsSync()) {
      throw PackageWiringException(
        'Required project file is missing: ${p.relative(path, from: root)}',
      );
    }
  }
  final name = package.package.name;
  final layeringSource = File(layering).readAsStringSync();
  return PackageRemovalPlan(
    package: package,
    modifiedFiles: {
      pubspec: unregisterWorkspacePackage(
        File(pubspec).readAsStringSync(),
        name,
      ),
      layering: unregisterPackageLayer(
        unregisterPackageCategory(layeringSource, name),
        name,
      ),
    },
    deletedDirectory: package.package.directory,
  );
}

final class RemovePackageCommand extends Command<int> {
  RemovePackageCommand(
    this._logger, {
    String? rootDirectory,
    PackageProcessExecutor processExecutor = _defaultProcessExecutor,
    PackageRemovalConfirmation confirmation = _defaultConfirmation,
    bool? interactive,
  })  : _rootDirectory = rootDirectory,
        _processExecutor = processExecutor,
        _confirmation = confirmation,
        _interactive = interactive {
    argParser
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Print the complete removal plan without writing files.',
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
        help: 'Explicitly authorize deletion of modified or additional files '
            'inside the CLI-owned package.',
      );
  }

  final Logger _logger;
  final String? _rootDirectory;
  final PackageProcessExecutor _processExecutor;
  final PackageRemovalConfirmation _confirmation;
  final bool? _interactive;

  @override
  String get name => 'remove-package';

  @override
  String get description =>
      'Safely remove an unreferenced CLI-owned reusable package.';

  @override
  String get invocation =>
      'fst remove-package <name> [--dry-run] [--yes] [--force-modified]';

  @override
  Future<int> run() async {
    final root = _rootDirectory ?? Directory.current.path;
    final positional = argResults?.rest ?? const [];
    if (positional.length != 1) {
      _logger.err('Provide exactly one package name.');
      return 64;
    }
    final inventory = discoverPackages(root);
    final package = inventory.find(positional.single.trim());
    if (package == null) {
      _logger.err('Package not found: ${positional.single}');
      return 1;
    }
    final direct = inventory.directConsumers(package.package.name);
    final transitive = inventory.transitiveConsumers(package.package.name);
    final forceModified = argResults?['force-modified'] as bool? ?? false;
    final blockers = <String>[
      if (!package.owned)
        '${package.package.name} is not proven to be CLI-owned',
      if (package.core)
        '${package.package.name} is a protected core platform package',
      if (!package.valid)
        '${package.package.name} failed package or ownership validation',
      if (package.hasUserChanges && !forceModified)
        '${package.package.name} contains modified or unknown files; '
            'use --force-modified to explicitly authorize their deletion',
      if (direct.isNotEmpty || transitive.isNotEmpty)
        '${package.package.name} has remaining consumers',
    ];

    PackageRemovalPlan? plan;
    if (package.owned && !package.core && package.valid) {
      try {
        plan = planPackageRemoval(root, package);
      } on PackageWiringException catch (error) {
        blockers.add(error.message);
      }
    }
    _printImpact(
      root,
      package,
      plan,
      direct,
      transitive,
      blockers,
      forceModified,
    );
    if (blockers.isNotEmpty) return 1;
    if (argResults?['dry-run'] as bool? ?? false) return 0;

    final confirmed = argResults?['yes'] as bool? ?? false;
    if (!confirmed) {
      if (!(_interactive ?? stdin.hasTerminal)) {
        _logger.err('Non-interactive removal requires --yes.');
        return 1;
      }
      if (!_confirmation('Remove ${package.package.name}?')) {
        _logger.info('Removal cancelled.');
        return 0;
      }
    }

    final snapshot = ProjectSnapshot.capture(root);
    try {
      for (final entry in plan!.modifiedFiles.entries) {
        File(entry.key).writeAsStringSync(entry.value, flush: true);
      }
      Directory(plan.deletedDirectory).deleteSync(recursive: true);
      final postRemoval = discoverPackages(root);
      if (postRemoval.find(package.package.name) != null) {
        throw const PackageWiringException(
          'Removed package is still discoverable.',
        );
      }
      if (postRemoval.issues.isNotEmpty) {
        throw PackageWiringException(postRemoval.issues.join('\n'));
      }
      if (!await _regenerateAndVerify(root)) {
        throw const PackageWiringException(
          'Generated project validation failed.',
        );
      }
    } on Object catch (error) {
      final rollback = _logger.progress('Rolling back failed removal');
      snapshot.restore();
      rollback.complete('Restored the original project');
      _logger.err('$error');
      return 1;
    }
    _logger.success(
      'Removed ${package.package.name} and validated the project.',
    );
    return 0;
  }

  void _printImpact(
    String root,
    DiscoveredPackage package,
    PackageRemovalPlan? plan,
    List<String> direct,
    List<String> transitive,
    List<String> blockers,
    bool forceModified,
  ) {
    _logger.info('Removal plan for ${package.package.name}:');
    _logger.info('  LOCATION ${package.location}');
    _logger.info('  OWNERSHIP ${package.ownership.name}');
    if (plan != null) {
      final files = Directory(plan.deletedDirectory)
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .map((file) => p.relative(file.path, from: root))
          .toList()
        ..sort();
      for (final file in files) {
        _logger.info('  DELETE $file');
      }
      _logger.info('  DELETE DIRECTORY ${package.location}');
      for (final file in plan.modifiedFiles.keys) {
        _logger.info('  MODIFY ${p.relative(file, from: root)}');
      }
    }
    _logger.info('  DIRECT CONSUMERS '
        '${direct.isEmpty ? 'none' : direct.join(', ')}');
    _logger.info('  TRANSITIVE CONSUMERS '
        '${transitive.isEmpty ? 'none' : transitive.join(', ')}');
    for (final path in package.modifiedFiles) {
      _logger.warn('  MODIFIED ${package.location}/$path');
    }
    for (final path in package.unknownFiles) {
      _logger.warn('  UNKNOWN ${package.location}/$path');
    }
    if (package.hasUserChanges && forceModified) {
      _logger.warn('  User changes explicitly authorized by --force-modified.');
    }
    for (final blocker in blockers) {
      _logger.err('  BLOCKED $blocker');
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
          ..err('${result.stderr}')
          ..warn('${result.stdout}');
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

Future<ProcessResult> _defaultProcessExecutor(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) =>
    Process.run(executable, arguments, workingDirectory: workingDirectory);
