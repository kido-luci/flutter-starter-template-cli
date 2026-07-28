import 'dart:io';

import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('pruneE2eSuite', () {
    late Directory dir;

    void write(String relative, String content) {
      File(p.join(dir.path, p.joinAll(relative.split('/'))))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    bool exists(String relative) =>
        File(p.join(dir.path, p.joinAll(relative.split('/')))).existsSync();

    bool dirExists(String relative) =>
        Directory(p.join(dir.path, p.joinAll(relative.split('/'))))
            .existsSync();

    setUp(() {
      dir = Directory.systemTemp.createTempSync('fst_e2e_test_');

      write('integration_test/e2e_test.dart', '// journey\n');
      write('integration_test/screenshots_test.dart', '// shots\n');
      write('integration_test/support/e2e_app.dart', '// harness\n');
      write('integration_test/README.md', '# e2e\n');
      write('test_driver/integration_test.dart', '// driver\n');
      write('tool/run_e2e.sh', '#!/bin/sh\n');
      // An unrelated file that must survive.
      write('tool/setup.sh', '#!/bin/sh\n');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('deletes every file of the demo suite', () async {
      await pruneE2eSuite(dir.path);

      expect(exists('integration_test/e2e_test.dart'), isFalse);
      expect(exists('integration_test/screenshots_test.dart'), isFalse);
      expect(exists('integration_test/support/e2e_app.dart'), isFalse);
      expect(exists('integration_test/README.md'), isFalse);
      expect(exists('test_driver/integration_test.dart'), isFalse);
      expect(exists('tool/run_e2e.sh'), isFalse);
    });

    test('leaves unrelated files alone', () async {
      await pruneE2eSuite(dir.path);

      expect(exists('tool/setup.sh'), isTrue);
      expect(dirExists('tool'), isTrue);
    });

    test('removes the directories once they are empty', () async {
      await pruneE2eSuite(dir.path);

      expect(dirExists('integration_test/support'), isFalse);
      expect(dirExists('integration_test'), isFalse);
      expect(dirExists('test_driver'), isFalse);
    });

    test('keeps a directory that still holds the user own tests', () async {
      write('integration_test/my_own_test.dart', '// mine\n');

      await pruneE2eSuite(dir.path);

      expect(dirExists('integration_test'), isTrue);
      expect(exists('integration_test/my_own_test.dart'), isTrue);
      expect(exists('integration_test/e2e_test.dart'), isFalse);
    });

    test('is idempotent', () async {
      await pruneE2eSuite(dir.path);
      await pruneE2eSuite(dir.path);

      expect(dirExists('integration_test'), isFalse);
      expect(exists('tool/setup.sh'), isTrue);
    });
  });
}
