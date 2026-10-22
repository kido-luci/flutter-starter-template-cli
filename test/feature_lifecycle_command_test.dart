import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flutter_starter_template_cli/src/commands/add_feature_command.dart';
import 'package:flutter_starter_template_cli/src/commands/list_features_command.dart';
import 'package:flutter_starter_template_cli/src/commands/remove_feature_command.dart';
import 'package:flutter_starter_template_cli/src/commands/validate_features_command.dart';
import 'package:flutter_starter_template_cli/src/feature_discovery.dart';
import 'package:flutter_starter_template_cli/src/feature_manifest.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('feature lifecycle', () {
    for (final source in ['presentation', 'local', 'api', 'sync']) {
      test('discovers and removes a $source feature', () async {
        final project = _project();
        addTearDown(() => project.deleteSync(recursive: true));
        expect(await _add(project, 'reports_$source', source), 0);

        final inventory = discoverFeatures(project.path);
        final feature = inventory.find('reports_$source')!;
        expect(feature.source?.name, source);
        expect(feature.ownership, FeatureOwnership.manifest);
        expect(feature.registration.complete, isTrue);
        expect(feature.routePath, '/reports-$source');
        expect(feature.hasUserChanges, isFalse);

        expect(await _remove(project, 'reports_$source'), 0);
        expect(
          Directory(
            '${project.path}/packages/features/reports_$source',
          ).existsSync(),
          isFalse,
        );
        final allSource = _sourceText(project);
        expect(allSource, isNot(contains('feature_reports_$source')));
        expect(allSource, isNot(contains('_Reports${_pascal(source)}Module')));
      });
    }

    test('discovers an unmodified feature from a pre-manifest CLI', () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      expect(await _add(project, 'legacy', 'local'), 0);
      File(
        '${project.path}/packages/features/legacy/$featureManifestName',
      ).deleteSync();

      final feature = discoverFeatures(project.path).find('legacy')!;
      expect(feature.ownership, FeatureOwnership.legacy);
      expect(await _remove(project, 'legacy'), 0);
    });

    test('rejects a reverse dependency without writing', () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      expect(await _add(project, 'provider', 'local'), 0);
      expect(await _add(project, 'consumer', 'local'), 0);
      final consumer = File(
        '${project.path}/packages/features/consumer/pubspec.yaml',
      );
      consumer.writeAsStringSync(
        consumer.readAsStringSync().replaceFirst(
              'dependencies:\n',
              'dependencies:\n  feature_provider: ^0.1.0\n',
            ),
      );
      final before = _sourceFiles(project);
      expect(await _remove(project, 'provider'), 1);
      expect(_sourceFiles(project), before);
    });

    test('blocks modified and unknown files without explicit authorization',
        () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      expect(await _add(project, 'inventory', 'presentation'), 0);
      final screen = File(
        '${project.path}/packages/features/inventory/lib/src/presentation/'
        'screens/inventory_screen.dart',
      );
      screen.writeAsStringSync('${screen.readAsStringSync()}\n// user edit\n');
      File('${project.path}/packages/features/inventory/NOTES.md')
          .writeAsStringSync('user notes');
      final before = _sourceFiles(project);
      expect(await _remove(project, 'inventory'), 1);
      expect(_sourceFiles(project), before);
    });

    test('force-modified is separate explicit authorization', () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      expect(await _add(project, 'authorized', 'presentation'), 0);
      File('${project.path}/packages/features/authorized/NOTES.md')
          .writeAsStringSync('explicitly disposable');
      expect(
        await _remove(project, 'authorized', forceModified: true),
        0,
      );
      expect(
        Directory('${project.path}/packages/features/authorized').existsSync(),
        isFalse,
      );
    });

    test('dry-run performs no writes', () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      expect(await _add(project, 'inventory', 'presentation'), 0);
      final before = _sourceFiles(project);
      expect(await _remove(project, 'inventory', dryRun: true), 0);
      expect(_sourceFiles(project), before);
    });

    test('removal regenerates the whole workspace before analysis', () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      expect(await _add(project, 'generated', 'presentation'), 0);
      final calls = <(String, List<String>, String?)>[];

      expect(
        await _remove(
          project,
          'generated',
          processExecutor: (executable, arguments, {workingDirectory}) async {
            calls.add((executable, arguments, workingDirectory));
            return ProcessResult(1, 0, '', '');
          },
        ),
        0,
      );

      expect(calls, hasLength(4));
      expect(calls[1].$1, 'bash');
      expect(
        calls[1].$2,
        [p.join(project.path, 'tool', 'codegen.sh')],
      );
      expect(calls[1].$3, project.path);
    });

    test('non-interactive removal requires --yes', () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      expect(await _add(project, 'inventory', 'presentation'), 0);
      final before = _sourceFiles(project);
      expect(await _remove(project, 'inventory', confirmed: false), 1);
      expect(_sourceFiles(project), before);
    });

    for (final failure in ['pub get', 'codegen', 'analysis', 'tests']) {
      test('rolls back byte-for-byte after $failure failure', () async {
        final project = _project();
        addTearDown(() => project.deleteSync(recursive: true));
        expect(await _add(project, 'rollback', 'api'), 0);
        final before = _sourceFiles(project);
        final failureIndex = switch (failure) {
          'pub get' => 0,
          'codegen' => 1,
          'analysis' => 2,
          _ => 3,
        };
        var call = 0;
        final result = await _remove(
          project,
          'rollback',
          processExecutor: (executable, arguments, {workingDirectory}) async {
            final current = call++;
            if (current == failureIndex) {
              File('${project.path}/generated-during-failure')
                  .writeAsStringSync('must be removed');
            }
            return ProcessResult(
              1,
              current == failureIndex ? 1 : 0,
              '',
              'forced $failure failure',
            );
          },
        );
        expect(result, 1);
        expect(_sourceFiles(project), before);
      });
    }

    test('cleans registrations and permits safe re-addition', () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      expect(await _add(project, 'renewable', 'presentation'), 0);
      expect(await _remove(project, 'renewable'), 0);
      expect(await _add(project, 'renewable', 'sync'), 0);
      expect(discoverFeatures(project.path).find('renewable')?.source?.name,
          'sync');
    });

    test('list and repeated validation inspect generated output', () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      expect(await _add(project, 'listed', 'presentation'), 0);
      expect(
        await _runSimple(
          ListFeaturesCommand(Logger(), rootDirectory: project.path),
        ),
        0,
      );
      expect(
        await _runSimple(
          ValidateFeaturesCommand(Logger(), rootDirectory: project.path),
        ),
        0,
      );
      expect(
        await _runSimple(
          ValidateFeaturesCommand(Logger(), rootDirectory: project.path),
        ),
        0,
      );

      final injection = File('${project.path}/lib/app/di/injection.dart');
      injection.writeAsStringSync(
        injection.readAsStringSync().replaceAll(
            '    ExternalModule(FeatureListedPackageModule),\n', ''),
      );
      expect(
        await _runSimple(
          ValidateFeaturesCommand(Logger(), rootDirectory: project.path),
        ),
        1,
      );
    });

    test('does not claim a manually authored package', () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      _write(
        project,
        'packages/features/manual/pubspec.yaml',
        'name: feature_manual\nresolution: workspace\n',
      );
      final feature = discoverFeatures(project.path).find('manual')!;
      expect(feature.ownership, FeatureOwnership.unowned);
      expect(await _remove(project, 'manual'), 1);
      expect(Directory('${project.path}/packages/features/manual').existsSync(),
          isTrue);
    });

    test('validate-features rejects forbidden dependencies and boundary leaks',
        () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      expect(await _add(project, 'alpha', 'local'), 0);
      expect(await _add(project, 'beta', 'local'), 0);

      // 1. Forbidden feature-to-feature dependency + root shell dependency + test_utils in runtime deps
      final alphaPubspec = File(
        '${project.path}/packages/features/alpha/pubspec.yaml',
      );
      alphaPubspec.writeAsStringSync(
        alphaPubspec.readAsStringSync().replaceFirst(
              'dependencies:\n',
              'dependencies:\n  fixture: ^0.1.0\n  test_utils: ^0.1.0\n  feature_beta: ^0.1.0\n',
            ),
      );
      // 2. Cross-package private src/ import
      final alphaScreen = File(
        '${project.path}/packages/features/alpha/lib/src/presentation/screens/alpha_screen.dart',
      );
      alphaScreen.writeAsStringSync(
        "import 'package:feature_beta/src/di.dart';\n${alphaScreen.readAsStringSync()}",
      );
      // 3. Domain-layer UI import
      final alphaEntity = File(
        '${project.path}/packages/features/alpha/lib/src/domain/entities/alpha.dart',
      );
      alphaEntity.writeAsStringSync(
        "import 'package:flutter/material.dart';\n${alphaEntity.readAsStringSync()}",
      );
      // 4. Public barrel internal leak
      final alphaBarrel = File(
        '${project.path}/packages/features/alpha/lib/feature_alpha.dart',
      );
      alphaBarrel.writeAsStringSync(
        "${alphaBarrel.readAsStringSync()}export 'src/data/repositories/alpha_repository_impl.dart';\n",
      );

      final inventory = discoverFeatures(project.path);
      expect(
        inventory.issues,
        containsAll([
          contains('cannot depend on application shell package fixture'),
          contains('cannot depend on dev/test utility package test_utils'),
          contains(
            'feature_alpha has unapproved feature-to-feature dependency on feature_beta',
          ),
          contains('feature_alpha imports private src/ of feature_beta'),
          contains(
              'feature_alpha domain layer imports UI/presentation library'),
          contains('feature_alpha public barrel leaks internal implementation'),
        ]),
      );
      expect(
        await _runSimple(
          ValidateFeaturesCommand(Logger(), rootDirectory: project.path),
        ),
        1,
      );
    });
  });
}

Future<int?> _add(Directory project, String name, String source) => _runCommand(
      () => CommandRunner<int>('fst', 'test')
        ..addCommand(
          AddFeatureCommand(
            Logger(),
            processExecutor: _successfulProcess,
            rootDirectory: project.path,
          ),
        ),
      ['add-feature', name, '--source', source, '--no-codegen'],
    );

Future<int?> _remove(
  Directory project,
  String name, {
  bool dryRun = false,
  bool confirmed = true,
  bool forceModified = false,
  RemoveProcessExecutor processExecutor = _successfulProcess,
}) =>
    _runCommand(
      () => CommandRunner<int>('fst', 'test')
        ..addCommand(
          RemoveFeatureCommand(
            Logger(),
            processExecutor: processExecutor,
            confirmation: (_) => true,
            rootDirectory: project.path,
            interactive: false,
          ),
        ),
      [
        'remove-feature',
        name,
        if (dryRun) '--dry-run',
        if (forceModified) '--force-modified',
        if (confirmed && !dryRun) '--yes',
      ],
    );

Future<int?> _runSimple(Command<int> command) => _runCommand(
      () => CommandRunner<int>('fst', 'test')..addCommand(command),
      [command.name],
    );

Future<int?> _runCommand(
  CommandRunner<int> Function() runner,
  List<String> arguments,
) =>
    runner().run(arguments);

Future<ProcessResult> _successfulProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async =>
    ProcessResult(1, 0, '', '');

Directory _project() {
  final root = Directory.systemTemp.createTempSync('fst-feature-lifecycle-');
  _write(root, 'pubspec.yaml', '''
name: fixture
workspace:
  # fst:features
dependencies:
  # fst:feature-deps
''');
  _write(root, 'lib/app/di/injection.dart', '''
import 'package:get_it/get_it.dart';
const modules = [
  // fst:feature-modules
];
''');
  _write(root, 'lib/app/features.dart', '''
import 'package:go_router/go_router.dart';
const enabledFeatures = [
  // fst:enabled-features
];
// fst:feature-module-classes
''');
  _write(
      root, 'lib/app/feature_module.dart', 'abstract class FeatureModule {}');
  _write(root, 'test/architecture/package_layering_test.dart', '''
const layers = <String, int>{
  // fst:feature-layers
};
''');
  _write(root, 'packages/network/pubspec.yaml', 'name: network\n');
  _write(root, 'published/rev_sync/pubspec.yaml', 'name: rev_sync\n');
  return root;
}

void _write(Directory root, String relative, String content) {
  final file = File('${root.path}/$relative');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

Map<String, List<int>> _sourceFiles(Directory root) => {
      for (final entity in root.listSync(recursive: true).whereType<File>())
        entity.path.substring(root.path.length + 1): entity.readAsBytesSync(),
    };

String _sourceText(Directory root) => root
    .listSync(recursive: true)
    .whereType<File>()
    .map((file) => file.readAsStringSync())
    .join('\n');

String _pascal(String value) =>
    '${value[0].toUpperCase()}${value.substring(1)}';
