import 'dart:io';

import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('removeTemplateOnlyRegions', () {
    test('removes a YAML block inclusive of its markers', () {
      const src = 'jobs:\n'
          '  # fst:template-only:start\n'
          '  cli-smoke:\n'
          '    runs-on: ubuntu-latest\n'
          '  # fst:template-only:end\n'
          '  build:\n';
      expect(
        removeTemplateOnlyRegions(src),
        equals('jobs:\n  build:\n'),
      );
    });

    test('removes several blocks in one file', () {
      const src = '# fst:template-only:start\nA\n# fst:template-only:end\n'
          'keep\n'
          '# fst:template-only:start\nB\n# fst:template-only:end\n';
      expect(removeTemplateOnlyRegions(src), equals('keep\n'));
    });

    test('is a no-op without markers, and is idempotent', () {
      const src = 'jobs:\n  build:\n';
      final once = removeTemplateOnlyRegions(src);
      expect(once, equals(src));
      expect(removeTemplateOnlyRegions(once), equals(src));
    });

    test('throws on an unclosed marker rather than dropping to EOF', () {
      const src = 'keep\n# fst:template-only:start\nA\n';
      expect(() => removeTemplateOnlyRegions(src), throwsFormatException);
    });
  });

  group('stripTemplateOnly', () {
    late Directory dir;

    void write(String relative, String content) {
      File(p.join(dir.path, p.joinAll(relative.split('/'))))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    String read(String relative) =>
        File(p.join(dir.path, p.joinAll(relative.split('/'))))
            .readAsStringSync();

    setUp(() {
      dir = Directory.systemTemp.createTempSync('fst_template_only_test_');

      // The load-bearing case: a scaffold has no .gitmodules, so this step
      // exits 1 and takes its whole job down.
      write(
        '.github/workflows/ci.yml',
        'jobs:\n'
            '  analyze:\n'
            '    steps:\n'
            '      - name: Checkout\n'
            '      # fst:template-only:start\n'
            '      - name: Check out rev_sync submodule\n'
            '        run: git submodule update --init published/rev_sync\n'
            '      # fst:template-only:end\n'
            '      - name: Analyze\n'
            '  # fst:template-only:start\n'
            '  cli-smoke:\n'
            '    runs-on: ubuntu-latest\n'
            '  # fst:template-only:end\n'
            '  build:\n'
            '    runs-on: ubuntu-latest\n',
      );
      write(
        '.github/workflows/release.yml',
        'jobs:\n'
            '  ship:\n'
            '    steps:\n'
            '      # fst:template-only:start\n'
            '      - name: Check out rev_sync submodule\n'
            '        run: git submodule update --init published/rev_sync\n'
            '      # fst:template-only:end\n'
            '      - name: Build\n',
      );
      write(
        '.github/dependabot.yml',
        'updates:\n'
            '  - package-ecosystem: pub\n'
            '  # fst:template-only:start\n'
            '  - package-ecosystem: gitsubmodule\n'
            '    directory: "/"\n'
            '  # fst:template-only:end\n',
      );
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('drops the submodule checkouts from every workflow', () async {
      await stripTemplateOnly(dir.path);

      final ci = read('.github/workflows/ci.yml');
      expect(ci, isNot(contains('git submodule update')));
      expect(ci, contains('name: Analyze'));

      final release = read('.github/workflows/release.yml');
      expect(release, isNot(contains('git submodule update')));
      expect(release, contains('name: Build'));
    });

    test('drops the CLI-drift jobs, keeping the rest', () async {
      await stripTemplateOnly(dir.path);

      final ci = read('.github/workflows/ci.yml');
      expect(ci, isNot(contains('cli-smoke')));
      expect(ci, contains('analyze:'));
      expect(ci, contains('build:'));
    });

    test('drops the git-submodule Dependabot ecosystem', () async {
      await stripTemplateOnly(dir.path);

      final dependabot = read('.github/dependabot.yml');
      expect(dependabot, isNot(contains('gitsubmodule')));
      expect(dependabot, contains('package-ecosystem: pub'));
    });

    test('leaves no marker behind', () async {
      await stripTemplateOnly(dir.path);

      for (final f in const [
        '.github/workflows/ci.yml',
        '.github/workflows/release.yml',
        '.github/dependabot.yml',
      ]) {
        expect(read(f), isNot(contains('fst:template-only')), reason: f);
      }
    });

    test('is idempotent', () async {
      await stripTemplateOnly(dir.path);
      final after = read('.github/workflows/ci.yml');
      await stripTemplateOnly(dir.path);

      expect(read('.github/workflows/ci.yml'), equals(after));
    });

    test('leaves the tree untouched when a marker is unclosed', () async {
      write(
        '.github/workflows/ci.yml',
        'jobs:\n  # fst:template-only:start\n  cli-smoke:\n',
      );
      final before = read('.github/workflows/ci.yml');

      await expectLater(
        () => stripTemplateOnly(dir.path),
        throwsA(isA<FormatException>()),
      );

      expect(read('.github/workflows/ci.yml'), equals(before));
    });
  });
}
