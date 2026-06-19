import 'dart:io';

import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('prepareCleanSlate', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('fst_clean_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('removes submodules + .gitmodules and re-inits a fresh git repo',
        () async {
      // Arrange: fake a freshly cloned template with submodule baggage.
      File(p.join(tempDir.path, 'simple_backend_server', 'main.go'))
        ..createSync(recursive: true)
        ..writeAsStringSync('package main');
      File(p.join(tempDir.path, 'tool', 'cli', 'bin', 'fst.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('void main() {}');
      // Non-cli tooling must survive.
      File(p.join(tempDir.path, 'tool', 'setup.sh'))
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/usr/bin/env bash');
      File(p.join(tempDir.path, '.gitmodules'))
          .writeAsStringSync('[submodule "tool/cli"]');
      File(p.join(tempDir.path, '.git', 'HISTORY_MARKER'))
        ..createSync(recursive: true)
        ..writeAsStringSync('template history');

      // Act.
      await prepareCleanSlate(tempDir.path);

      // Assert: baggage is gone.
      expect(
        Directory(p.join(tempDir.path, 'simple_backend_server')).existsSync(),
        isFalse,
      );
      expect(
        Directory(p.join(tempDir.path, 'tool', 'cli')).existsSync(),
        isFalse,
      );
      expect(File(p.join(tempDir.path, '.gitmodules')).existsSync(), isFalse);

      // Non-cli tooling is preserved.
      expect(
          File(p.join(tempDir.path, 'tool', 'setup.sh')).existsSync(), isTrue);

      // Git is a fresh repo: the template history is gone but .git/HEAD exists.
      expect(
        File(p.join(tempDir.path, '.git', 'HISTORY_MARKER')).existsSync(),
        isFalse,
      );
      expect(File(p.join(tempDir.path, '.git', 'HEAD')).existsSync(), isTrue);
    });
  });
}
