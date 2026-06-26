import 'dart:io';

import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('removeBackendRegions', () {
    test('removes a Dart backend block inclusive of its markers', () {
      const src = "import 'a';\n"
          '// fst:backend:start\n'
          "import 'package:network/network.dart';\n"
          '// fst:backend:end\n'
          "import 'b';\n";
      expect(
        removeBackendRegions(src),
        equals("import 'a';\nimport 'b';\n"),
      );
    });

    test('removes a YAML backend block', () {
      const src = 'dependencies:\n'
          '  # fst:backend:start\n'
          '  network: ^0.1.0\n'
          '  # fst:backend:end\n'
          '  app_ui: ^0.1.0\n';
      expect(
        removeBackendRegions(src),
        equals('dependencies:\n  app_ui: ^0.1.0\n'),
      );
    });

    test('removes multiple backend blocks in the same file', () {
      const src = '// fst:backend:start\nA\n// fst:backend:end\n'
          'keep\n'
          '// fst:backend:start\nB\n// fst:backend:end\n';
      expect(removeBackendRegions(src), equals('keep\n'));
    });

    test('leaves unrelated lines untouched', () {
      const src = "import 'a';\n"
          '// fst:backend:start\n'
          "import 'package:network/network.dart';\n"
          '// fst:backend:end\n"'
          "import 'b';\n";
      final result = removeBackendRegions(src);
      expect(result, contains("import 'a'"));
      expect(result, isNot(contains('network')));
    });

    test('is a no-op when no backend markers are present', () {
      const src = "import 'a';\nimport 'b';\n";
      expect(removeBackendRegions(src), equals(src));
    });

    test('is idempotent', () {
      const src = "import 'a';\n"
          '// fst:backend:start\n'
          "import 'package:network/network.dart';\n"
          '// fst:backend:end\n'
          "import 'b';\n";
      final once = removeBackendRegions(src);
      expect(removeBackendRegions(once), equals(once));
    });

    test('throws on an unclosed start marker instead of dropping to EOF', () {
      const src = 'keep\n'
          '// fst:backend:start\n'
          'A\n'; // no matching :end
      expect(
        () => removeBackendRegions(src),
        throwsFormatException,
      );
    });
  });

  group('disableBackend', () {
    late Directory dir;

    void write(String relative, String content) {
      File(p.join(dir.path, p.joinAll(relative.split('/'))))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    String read(String relative) =>
        File(p.join(dir.path, p.joinAll(relative.split('/'))))
            .readAsStringSync();

    bool exists(String relative) =>
        File(p.join(dir.path, p.joinAll(relative.split('/')))).existsSync();

    setUp(() {
      dir = Directory.systemTemp.createTempSync('fst_backend_test_');

      // Root pubspec: network + sync workspace members and deps.
      write(
        'pubspec.yaml',
        'workspace:\n'
            '  # fst:backend:start\n'
            '  - packages/network\n'
            '  # fst:backend:end\n'
            '  - packages/app_platform\n'
            '  # fst:backend:start\n'
            '  - packages/sync_connectivity_plus\n'
            '  # fst:backend:end\n'
            'dependencies:\n'
            '  # fst:backend:start\n'
            '  network: ^0.1.0\n'
            '  # fst:backend:end\n'
            '  app_platform: ^0.1.0\n'
            '  # fst:backend:start\n'
            '  sync_connectivity_plus: ^0.1.0\n'
            '  # fst:backend:end\n'
            '  theme: ^0.1.0\n',
      );

      // injection.dart: network + sync imports and modules.
      write(
        'lib/app/di/injection.dart',
        '// fst:backend:start\n'
            "import 'package:network/network.dart';\n"
            '// fst:backend:end\n'
            "import 'package:storage/storage.dart';\n"
            '// fst:backend:start\n'
            "import 'package:sync_connectivity_plus/sync_connectivity_plus.dart';\n"
            '// fst:backend:end\n'
            '// fst:backend:start\n'
            '    ExternalModule(NetworkPackageModule),\n'
            '// fst:backend:end\n'
            '    ExternalModule(StoragePackageModule),\n'
            '// fst:backend:start\n'
            '    ExternalModule(SyncConnectivityPlusPackageModule),\n'
            '// fst:backend:end\n',
      );

      // package_layering_test.dart: network + sync layer entries.
      write(
        'test/architecture/package_layering_test.dart',
        "const _layers = <String, int>{\n"
            "  // fst:backend:start\n"
            "  'sync_connectivity_plus': 1,\n"
            "  // fst:backend:end\n"
            "  // fst:backend:start\n"
            "  'network': 2,\n"
            "  // fst:backend:end\n"
            "  'app_platform': 2,\n"
            "};\n",
      );

      // Backend-only files to be deleted.
      write(
        'lib/core/data/sync/objectbox_sync_cursor_store.dart',
        "import 'package:database/database.dart';\n",
      );
      write(
        'test/architecture/authenticated_dio_test.dart',
        "import 'dart:io';\nvoid main() {}\n",
      );

      // Package directories to be deleted.
      write('packages/network/pubspec.yaml', 'name: network\n');
      write(
        'packages/sync_connectivity_plus/pubspec.yaml',
        'name: sync_connectivity_plus\n',
      );
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('strips backend regions from all wiring files', () async {
      await disableBackend(dir.path);

      final pubspec = read('pubspec.yaml');
      expect(pubspec, isNot(contains('network:')));
      expect(pubspec, isNot(contains('sync_connectivity_plus:')));
      expect(pubspec, contains('app_platform'));
      expect(pubspec, contains('theme'));

      final injection = read('lib/app/di/injection.dart');
      expect(injection, isNot(contains('NetworkPackageModule')));
      expect(injection, isNot(contains('SyncConnectivityPlusPackageModule')));
      expect(injection, contains('StoragePackageModule'));

      final layering = read('test/architecture/package_layering_test.dart');
      expect(layering, isNot(contains('sync_connectivity_plus')));
      expect(layering, isNot(contains("'network'")));
      expect(layering, contains('app_platform'));
    });

    test('deletes the objectbox_sync_cursor_store.dart file', () async {
      await disableBackend(dir.path);
      expect(
        exists('lib/core/data/sync/objectbox_sync_cursor_store.dart'),
        isFalse,
      );
    });

    test('deletes the authenticated_dio_test.dart file', () async {
      await disableBackend(dir.path);
      expect(
        exists('test/architecture/authenticated_dio_test.dart'),
        isFalse,
      );
    });

    test('deletes the packages/network directory', () async {
      await disableBackend(dir.path);
      expect(exists('packages/network/pubspec.yaml'), isFalse);
    });

    test('deletes the packages/sync_connectivity_plus directory', () async {
      await disableBackend(dir.path);
      expect(exists('packages/sync_connectivity_plus/pubspec.yaml'), isFalse);
    });

    test('is idempotent', () async {
      await disableBackend(dir.path);
      final pubspecAfterFirst = read('pubspec.yaml');

      // Run again — no markers left, no-op.
      await disableBackend(dir.path);
      expect(read('pubspec.yaml'), equals(pubspecAfterFirst));
    });

    test('throws on an unclosed marker and leaves files untouched', () async {
      // Corrupt pubspec with an unclosed marker.
      write(
        'pubspec.yaml',
        'dependencies:\n'
            '  # fst:backend:start\n'
            '  network: ^0.1.0\n'
            '  # No closing end marker\n'
            '  theme: ^0.1.0\n',
      );
      final originalPubspec = read('pubspec.yaml');

      await expectLater(
        () => disableBackend(dir.path),
        throwsA(isA<FormatException>()),
      );

      // File must be untouched (phase 1 aborted before any write).
      expect(read('pubspec.yaml'), equals(originalPubspec));
    });
  });
}
