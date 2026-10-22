import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flutter_starter_template_cli/src/commands/create_package_command.dart';
import 'package:flutter_starter_template_cli/src/commands/validate_package_command.dart';
import 'package:flutter_starter_template_cli/src/package_architecture.dart';
import 'package:flutter_starter_template_cli/src/package_manifest.dart';
import 'package:flutter_starter_template_cli/src/package_spec.dart';
import 'package:flutter_starter_template_cli/src/rewrite/local_template.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:test/test.dart';

void main() {
  group('create-package', () {
    for (final type in ReusablePackageType.values) {
      test('creates, registers, and validates ${type.name} packages', () async {
        final project = _project();
        addTearDown(() => project.deleteSync(recursive: true));
        final name = 'sample_${type.name}';

        expect(await _create(project, name, type.name, noVerify: true), 0);
        final packageDir = Directory('${project.path}/packages/$name');
        expect(packageDir.existsSync(), isTrue);
        expect(File('${packageDir.path}/lib/$name.dart').existsSync(), isTrue);
        expect(File('${packageDir.path}/test/${name}_test.dart').existsSync(),
            isTrue);
        expect(readPackageManifest(packageDir.path)?.type, type);
        expect(
          File('${project.path}/pubspec.yaml').readAsStringSync(),
          contains('- packages/$name'),
        );
        expect(validateWorkspacePackage(project.path, name).issues, isEmpty);
        expect(await _validate(project, name), 0);
      });
    }

    test('rejects invalid and feature names before writing', () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));

      expect(await _create(project, 'Bad-Name', 'contracts'), 1);
      expect(await _create(project, 'feature_orders', 'contracts'), 1);
      expect(
          Directory('${project.path}/packages/Bad-Name').existsSync(), isFalse);
    });

    test('rejects repeated package creation and preserves the first package',
        () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));

      expect(
          await _create(project, 'shared_models', 'contracts', noVerify: true),
          0);
      final barrel =
          File('${project.path}/packages/shared_models/lib/shared_models.dart');
      barrel.writeAsStringSync(
          "export 'src/shared_models.dart';\n// user edit\n");
      expect(
          await _create(project, 'shared_models', 'contracts', noVerify: true),
          1);
      expect(barrel.readAsStringSync(), contains('// user edit'));
    });

    test('dry-run performs no writes', () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      final before = _tree(project);

      expect(
          await _create(project, 'dry_models', 'contracts', dryRun: true), 0);
      expect(_tree(project), before);
    });

    test('accepts permitted dependencies and rejects forbidden or unknown ones',
        () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      expect(
          await _create(project, 'inventory_contracts', 'contracts',
              noVerify: true),
          0);
      expect(
        await _create(
          project,
          'inventory_service',
          'infrastructure',
          dependencies: ['inventory_contracts'],
          noVerify: true,
        ),
        0,
      );
      expect(
        await _create(
          project,
          'bad_contracts',
          'contracts',
          dependencies: ['inventory_service'],
        ),
        1,
      );
      expect(
        await _create(
          project,
          'unknown_consumer',
          'ui',
          dependencies: ['missing_package'],
        ),
        1,
      );
    });

    test('rejects a dependency cycle already implied by a legacy package',
        () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      _writePackage(
        project,
        'legacy_bridge',
        dependencies: ['new_contracts'],
        manifestType: ReusablePackageType.contracts,
      );

      expect(
        await _create(
          project,
          'new_contracts',
          'contracts',
          dependencies: ['legacy_bridge'],
        ),
        1,
      );
    });

    test('rolls back byte-for-byte after verification process failure',
        () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      final before = _tree(project);

      expect(
        await _create(
          project,
          'rollback_service',
          'infrastructure',
          processExecutor: (_, __, {workingDirectory}) async =>
              ProcessResult(1, 1, '', 'forced failure'),
        ),
        1,
      );
      expect(_tree(project), before);
    });
  });

  group('validate-package', () {
    test('validates a compatible legacy package without claiming ownership',
        () {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      _writePackage(project, 'legacy_contracts');

      final result = validateWorkspacePackage(project.path, 'legacy_contracts');
      expect(result.isValid, isTrue);
      expect(result.package?.manifest, isNull);
    });

    test('rejects private imports, missing tests, and malformed manifests', () {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      _writePackage(project, 'broken_contracts', withTest: false);
      File('${project.path}/packages/broken_contracts/lib/src/broken_contracts.dart')
          .writeAsStringSync(
        "import 'package:architecture/src/result.dart';\n",
      );
      File('${project.path}/packages/broken_contracts/$packageManifestName')
          .writeAsStringSync('{"schemaVersion":99}');

      final issues =
          validateWorkspacePackage(project.path, 'broken_contracts').issues;
      expect(issues, contains(contains('invalid .fst-package.json')));
      expect(issues, contains(contains('imports private API')));
      expect(issues, contains(contains('at least one test')));
    });
  });

  group('local template compatibility', () {
    test('rejects a declared incompatible template version', () {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      File('${project.path}/.fst-template.json').writeAsStringSync('''
{"schemaVersion": 999, "templateKind": "application", "customizationPoints": []}
''');
      expect(
        () => validateLocalTemplateCompatibility(project.path),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts schema version 1 with required extension points', () {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      File('${project.path}/.fst-template.json').writeAsStringSync('''
{"schemaVersion": 1, "templateKind": "application", "customizationPoints": ["project-identifiers", "workspace-packages", "feature-registration"]}
''');
      expect(
        () => validateLocalTemplateCompatibility(project.path),
        returnsNormally,
      );
    });
  });
}

Future<int?> _create(
  Directory project,
  String name,
  String type, {
  List<String> dependencies = const [],
  bool dryRun = false,
  bool noVerify = false,
  PackageProcessExecutor? processExecutor,
}) {
  final runner = CommandRunner<int>('fst', 'test')
    ..addCommand(
      CreatePackageCommand(
        Logger(),
        rootDirectory: project.path,
        processExecutor: processExecutor ?? _successfulProcess,
      ),
    );
  return runner.run([
    'create-package',
    name,
    '--type',
    type,
    for (final dependency in dependencies) ...['--dependency', dependency],
    if (dryRun) '--dry-run',
    if (noVerify) '--no-verify',
  ]);
}

Future<int?> _validate(Directory project, String name) =>
    (CommandRunner<int>('fst', 'test')
          ..addCommand(
            ValidatePackageCommand(Logger(), rootDirectory: project.path),
          ))
        .run(['validate-package', name]);

Future<ProcessResult> _successfulProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async =>
    ProcessResult(1, 0, '', '');

Directory _project() {
  final root = Directory.systemTemp.createTempSync('fst-package-generator-');
  File('${root.path}/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
name: fixture
environment:
  sdk: ^3.12.0
workspace:
  # fst:packages
dependencies:
''');
  File('${root.path}/lib/app/features.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('// fixture\n');
  File('${root.path}/lib/app/di/injection.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('// fixture\n');
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

void _writePackage(
  Directory project,
  String name, {
  List<String> dependencies = const [],
  bool withTest = true,
  ReusablePackageType? manifestType,
}) {
  final dir = Directory('${project.path}/packages/$name')
    ..createSync(recursive: true);
  File('${dir.path}/pubspec.yaml').writeAsStringSync('''
name: $name
resolution: workspace
environment:
  sdk: ^3.12.0
dependencies:
${dependencies.map((dep) => '  $dep: ^0.1.0').join('\n')}
''');
  File('${dir.path}/lib/$name.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync("export 'src/$name.dart';\n");
  File('${dir.path}/lib/src/$name.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('const packageName = \'$name\';\n');
  if (withTest) {
    File('${dir.path}/test/${name}_test.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('// legacy test\n');
  }
  if (manifestType != null) {
    writePackageManifest(
      dir.path,
      PackageManifest(
        name: name,
        type: manifestType,
        dependencies: dependencies,
        ownedFiles: const [],
      ),
    );
  }
  final pubspec = File('${project.path}/pubspec.yaml');
  pubspec.writeAsStringSync(
    pubspec.readAsStringSync().replaceFirst(
          '  # fst:packages',
          '  - packages/$name\n  # fst:packages',
        ),
  );
}

Map<String, List<int>> _tree(Directory root) => {
      for (final file in root
          .listSync(recursive: true, followLinks: false)
          .whereType<File>())
        file.path.substring(root.path.length + 1): file.readAsBytesSync(),
    };
