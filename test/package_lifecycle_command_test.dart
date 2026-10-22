import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flutter_starter_template_cli/src/commands/create_package_command.dart';
import 'package:flutter_starter_template_cli/src/commands/list_packages_command.dart';
import 'package:flutter_starter_template_cli/src/commands/remove_package_command.dart';
import 'package:flutter_starter_template_cli/src/package_lifecycle.dart';
import 'package:flutter_starter_template_cli/src/package_spec.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('package lifecycle', () {
    test('lists CLI-owned, legacy, and manually maintained packages', () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      await _create(project, 'owned_contracts', 'contracts');
      _writeManualPackage(project, 'architecture', layer: 0);
      _writeManualPackage(project, 'hand_written', layer: 1);

      final inventory = discoverPackages(project.path);
      expect(
          inventory.find('owned_contracts')?.ownership, PackageOwnership.cli);
      expect(
          inventory.find('architecture')?.ownership, PackageOwnership.legacy);
      expect(
          inventory.find('hand_written')?.ownership, PackageOwnership.manual);
      expect(await _list(project), 0);
    });

    for (final type in ReusablePackageType.values) {
      test('removes and permits recreation of a ${type.name} package',
          () async {
        final project = _project();
        addTearDown(() => project.deleteSync(recursive: true));
        final name = 'removable_${type.name}';
        expect(await _create(project, name, type.name), 0);

        expect(await _remove(project, name), 0);
        expect(
            Directory('${project.path}/packages/$name').existsSync(), isFalse);
        final pubspec = File('${project.path}/pubspec.yaml').readAsStringSync();
        final layering = File(
          '${project.path}/test/architecture/package_layering_test.dart',
        ).readAsStringSync();
        expect(pubspec, isNot(contains('packages/$name')));
        expect(layering, isNot(contains("'$name':")));
        expect(await _create(project, name, type.name), 0);
      });
    }

    test('rejects removal of protected core and manually owned packages',
        () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      expect(await _create(project, 'architecture', 'contracts'), 0);
      _writeManualPackage(project, 'hand_written', layer: 1);
      final before = _tree(project);

      expect(await _remove(project, 'architecture'), 1);
      expect(await _remove(project, 'hand_written'), 1);
      expect(_tree(project), before);
    });

    test('reports and rejects direct and transitive consumers', () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      await _create(project, 'base_contracts', 'contracts');
      await _create(
        project,
        'middle_contracts',
        'contracts',
        dependencies: ['base_contracts'],
      );
      await _create(
        project,
        'top_service',
        'infrastructure',
        dependencies: ['middle_contracts'],
      );

      final inventory = discoverPackages(project.path);
      expect(inventory.directConsumers('base_contracts'), ['middle_contracts']);
      expect(inventory.transitiveConsumers('base_contracts'), ['top_service']);
      final before = _tree(project);
      expect(await _remove(project, 'base_contracts', dryRun: true), 1);
      expect(_tree(project), before);
    });

    test('includes application and development dependencies as consumers',
        () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      await _create(project, 'used_contracts', 'contracts');
      final pubspec = File('${project.path}/pubspec.yaml');
      pubspec.writeAsStringSync(
        pubspec.readAsStringSync().replaceFirst(
              'dev_dependencies:',
              'dev_dependencies:\n  used_contracts: ^0.1.0',
            ),
      );

      expect(
        discoverPackages(project.path).directConsumers('used_contracts'),
        ['fixture'],
      );
      expect(await _remove(project, 'used_contracts'), 1);
    });

    test('blocks modified and unknown files unless explicitly authorized',
        () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      await _create(project, 'changed_contracts', 'contracts');
      File('${project.path}/packages/changed_contracts/lib/changed_contracts.dart')
          .writeAsStringSync("export 'src/changed_contracts.dart';\n// edit\n");
      File('${project.path}/packages/changed_contracts/NOTES.md')
          .writeAsStringSync('user file\n');
      final before = _tree(project);

      expect(await _remove(project, 'changed_contracts'), 1);
      expect(_tree(project), before);
      expect(
        await _remove(project, 'changed_contracts', forceModified: true),
        0,
      );
      expect(
        Directory('${project.path}/packages/changed_contracts').existsSync(),
        isFalse,
      );
    });

    test('dry-run preserves every file byte-for-byte', () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      await _create(project, 'dry_contracts', 'contracts');
      final before = _tree(project);

      expect(await _remove(project, 'dry_contracts', dryRun: true), 0);
      expect(_tree(project), before);
    });

    test('removal regenerates the whole workspace before analysis', () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      await _create(project, 'generated_contracts', 'contracts');
      final calls = <(String, List<String>, String?)>[];

      expect(
        await _remove(
          project,
          'generated_contracts',
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

    for (var failedStage = 1; failedStage <= 4; failedStage++) {
      test(
          'rolls back byte-for-byte after verification stage $failedStage fails',
          () async {
        final project = _project();
        addTearDown(() => project.deleteSync(recursive: true));
        await _create(project, 'rollback_contracts', 'contracts');
        final before = _tree(project);
        var invocation = 0;

        expect(
          await _remove(
            project,
            'rollback_contracts',
            processExecutor: (_, __, {workingDirectory}) async {
              invocation++;
              return ProcessResult(
                invocation,
                invocation == failedStage ? 1 : 0,
                '',
                invocation == failedStage ? 'forced failure' : '',
              );
            },
          ),
          1,
        );
        expect(_tree(project), before);
      });
    }
  });
}

Future<int?> _create(
  Directory project,
  String name,
  String type, {
  List<String> dependencies = const [],
}) =>
    (CommandRunner<int>('fst', 'test')
          ..addCommand(
            CreatePackageCommand(
              Logger(),
              rootDirectory: project.path,
              processExecutor: _successfulProcess,
            ),
          ))
        .run([
      'create-package',
      name,
      '--type',
      type,
      for (final dependency in dependencies) ...['--dependency', dependency],
      '--no-verify',
    ]);

Future<int?> _remove(
  Directory project,
  String name, {
  bool dryRun = false,
  bool forceModified = false,
  PackageProcessExecutor processExecutor = _successfulProcess,
}) =>
    (CommandRunner<int>('fst', 'test')
          ..addCommand(
            RemovePackageCommand(
              Logger(),
              rootDirectory: project.path,
              processExecutor: processExecutor,
              interactive: false,
            ),
          ))
        .run([
      'remove-package',
      name,
      if (dryRun) '--dry-run' else '--yes',
      if (forceModified) '--force-modified',
    ]);

Future<int?> _list(Directory project) => (CommandRunner<int>('fst', 'test')
      ..addCommand(
        ListPackagesCommand(Logger(), rootDirectory: project.path),
      ))
    .run(['list-packages']);

Future<ProcessResult> _successfulProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async =>
    ProcessResult(1, 0, '', '');

Directory _project() {
  final root = Directory.systemTemp.createTempSync('fst-package-lifecycle-');
  File('${root.path}/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
name: fixture
environment:
  sdk: ^3.12.0
workspace:
  # fst:packages
dependencies:
dev_dependencies:
''');
  File('${root.path}/test/architecture/package_layering_test.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
enum PackageCategory { sharedDomainContracts, infrastructureService, platformIntegration, uiDesignSystem, devTestUtilities }
const categories = {
  // fst:package-categories
};
const layers = <String, int>{
  // fst:package-layers
};
''');
  return root;
}

void _writeManualPackage(Directory project, String name, {required int layer}) {
  final directory = Directory('${project.path}/packages/$name')
    ..createSync(recursive: true);
  File('${directory.path}/pubspec.yaml').writeAsStringSync('''
name: $name
resolution: workspace
environment:
  sdk: ^3.12.0
dependencies:
dev_dependencies:
  test: any
''');
  File('${directory.path}/lib/$name.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync("export 'src/$name.dart';\n");
  File('${directory.path}/lib/src/$name.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('const packageName = \'$name\';\n');
  File('${directory.path}/test/${name}_test.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('// test\n');
  final pubspec = File('${project.path}/pubspec.yaml');
  pubspec.writeAsStringSync(
    pubspec.readAsStringSync().replaceFirst(
          '  # fst:packages',
          '  - packages/$name\n  # fst:packages',
        ),
  );
  final architecture = File(
    '${project.path}/test/architecture/package_layering_test.dart',
  );
  architecture.writeAsStringSync(
    architecture
        .readAsStringSync()
        .replaceFirst(
          '  // fst:package-categories',
          "  '$name': PackageCategory.sharedDomainContracts,\n"
              '  // fst:package-categories',
        )
        .replaceFirst(
          '  // fst:package-layers',
          "  '$name': $layer,\n  // fst:package-layers",
        ),
  );
}

Map<String, List<int>> _tree(Directory root) => {
      for (final file in root
          .listSync(recursive: true, followLinks: false)
          .whereType<File>())
        file.path.substring(root.path.length + 1): file.readAsBytesSync(),
    };
