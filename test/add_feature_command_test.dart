import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flutter_starter_template_cli/src/commands/add_feature_command.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:test/test.dart';

void main() {
  group('add-feature command', () {
    for (final source in ['presentation', 'local', 'api', 'sync']) {
      test('creates and registers a $source feature', () async {
        final project = _project();
        addTearDown(() => project.deleteSync(recursive: true));

        final result = await _run(
          project,
          ['reports_$source', '--source', source, '--no-codegen'],
        );

        expect(result, 0);
        final feature = Directory(
          '${project.path}/packages/features/reports_$source',
        );
        expect(feature.existsSync(), isTrue);
        final routes = File(
          '${feature.path}/lib/src/presentation/reports_${source}_routes.dart',
        ).readAsStringSync();
        expect(routes, contains("name: Reports${_pascal(source)}Routes.name"));
        expect(routes, contains("static const root = '/reports-$source'"));
        expect(routes, contains("static const detailsSegment = 'details'"));

        final features =
            File('${project.path}/lib/app/features.dart').readAsStringSync();
        expect(features, contains('_Reports${_pascal(source)}Module()'));
        expect(features, contains('reports${_pascal(source)}Routes'));
      });
    }

    test('supports a validated nested route path', () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      final result = await _run(project, [
        'audit_log',
        '--source',
        'presentation',
        '--route-path',
        '/admin/audit-log',
        '--no-codegen',
      ]);
      expect(result, 0);
      final routes = File(
        '${project.path}/packages/features/audit_log/'
        'lib/src/presentation/audit_log_routes.dart',
      ).readAsStringSync();
      expect(routes, contains("static const root = '/admin/audit-log'"));
    });

    test('second run rejects the duplicate without changing wiring', () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      final args = ['settings', '--source', 'presentation', '--no-codegen'];
      expect(await _run(project, args), 0);
      final pubspec = File('${project.path}/pubspec.yaml');
      final before = pubspec.readAsStringSync();
      expect(await _run(project, args), 1);
      expect(pubspec.readAsStringSync(), before);
      expect(RegExp('feature_settings').allMatches(before), hasLength(1));
    });

    test('rejects a duplicate route path before touching the project',
        () async {
      final project = _project(existingRoute: '/settings');
      addTearDown(() => project.deleteSync(recursive: true));
      final before = File('${project.path}/pubspec.yaml').readAsStringSync();
      final result = await _run(project, [
        'preferences',
        '--source',
        'presentation',
        '--route-path',
        '/settings',
        '--no-codegen',
      ]);
      expect(result, 1);
      expect(File('${project.path}/pubspec.yaml').readAsStringSync(), before);
      expect(
        Directory('${project.path}/packages/features/preferences').existsSync(),
        isFalse,
      );
    });

    test('rejects API generation when the network workspace is absent',
        () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      Directory('${project.path}/packages/network').deleteSync(recursive: true);
      final before = _sourceFiles(project);
      final result = await _run(
        project,
        ['remote', '--source', 'api', '--no-codegen'],
      );
      expect(result, 1);
      expect(_sourceFiles(project), before);
    });

    test('rolls back every source edit when codegen fails', () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      final before = _sourceFiles(project);
      final result = await _run(
        project,
        ['broken', '--source', 'presentation'],
        processExecutor: (executable, arguments, {workingDirectory}) async {
          final isCodegen = arguments.contains('build_runner');
          if (isCodegen) {
            final cache = Directory(
              '${project.path}/packages/features/broken/.dart_tool',
            )..createSync(recursive: true);
            File('${cache.path}/generated-cache').writeAsStringSync('cache');
          }
          return ProcessResult(1, isCodegen ? 1 : 0, '', 'forced failure');
        },
      );
      expect(result, 1);
      expect(_sourceFiles(project), before);
      expect(
        Directory('${project.path}/packages/features/broken').existsSync(),
        isFalse,
      );
    });

    test('rolls back when a tool process cannot be started', () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      final before = _sourceFiles(project);
      final result = await _run(
        project,
        ['missing_tool', '--source', 'presentation'],
        processExecutor: (executable, arguments, {workingDirectory}) async {
          throw ProcessException(executable, arguments, 'not found');
        },
      );
      expect(result, 1);
      expect(_sourceFiles(project), before);
      expect(
        Directory('${project.path}/packages/features/missing_tool')
            .existsSync(),
        isFalse,
      );
    });

    test('runs pub get, codegen, analysis, and tests in order', () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      final calls = <String>[];
      final result = await _run(
        project,
        ['verified', '--source', 'presentation'],
        processExecutor: (executable, arguments, {workingDirectory}) async {
          calls.add('$executable ${arguments.join(' ')}');
          return ProcessResult(1, 0, '', '');
        },
      );
      expect(result, 0);
      expect(calls, [
        'flutter pub get',
        'dart run build_runner build --delete-conflicting-outputs',
        'dart run build_runner build --delete-conflicting-outputs',
        'flutter analyze',
        'flutter test',
      ]);
    });

    test('generates modules skipped by an earlier no-codegen run', () async {
      final project = _project();
      addTearDown(() => project.deleteSync(recursive: true));
      expect(
        await _run(project, [
          'first',
          '--source',
          'presentation',
          '--no-codegen',
        ]),
        0,
      );
      final calls = <String>[];
      final result = await _run(
        project,
        ['second', '--source', 'presentation'],
        processExecutor: (executable, arguments, {workingDirectory}) async {
          calls.add('$workingDirectory|$executable ${arguments.join(' ')}');
          return ProcessResult(1, 0, '', '');
        },
      );
      expect(result, 0);
      expect(
        calls.where((call) => call.contains('build_runner')),
        hasLength(3),
      );
      expect(calls.any((call) => call.contains('/features/first|')), isTrue);
      expect(calls.any((call) => call.contains('/features/second|')), isTrue);
    });
  });
}

Future<int?> _run(
  Directory project,
  List<String> arguments, {
  ProcessExecutor? processExecutor,
}) async {
  final previous = Directory.current;
  Directory.current = project;
  try {
    final runner = CommandRunner<int>('fst', 'test')
      ..addCommand(
        AddFeatureCommand(
          Logger(),
          processExecutor: processExecutor ?? _successfulProcess,
        ),
      );
    return await runner.run(['add-feature', ...arguments]);
  } finally {
    Directory.current = previous;
  }
}

Future<ProcessResult> _successfulProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async =>
    ProcessResult(1, 0, '', '');

Directory _project({String? existingRoute}) {
  final root = Directory.systemTemp.createTempSync('fst-add-feature-');
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
  _write(root, 'tool/codegen.sh', '#!/usr/bin/env bash\n');
  _write(root, 'packages/network/pubspec.yaml', 'name: network\n');
  _write(root, 'published/rev_sync/pubspec.yaml', 'name: rev_sync\n');
  if (existingRoute != null) {
    _write(root, 'lib/app/router.dart', '''
@TypedGoRoute<ExistingRoute>(path: '$existingRoute', name: 'existing')
class ExistingRoute {}
''');
  }
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

String _pascal(String value) =>
    '${value[0].toUpperCase()}${value.substring(1)}';
