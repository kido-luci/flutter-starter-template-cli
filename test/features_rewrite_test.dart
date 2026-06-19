import 'dart:io';

import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('expandExcludedFeatures', () {
    test('leaves an independent feature alone', () {
      expect(
          expandExcludedFeatures({'notifications'}), equals({'notifications'}));
    });

    test('excluding collections also excludes bookmarks', () {
      expect(
        expandExcludedFeatures({'collections'}),
        equals({'collections', 'bookmarks'}),
      );
    });

    test('excluding bookmarks alone does not pull collections', () {
      expect(expandExcludedFeatures({'bookmarks'}), equals({'bookmarks'}));
    });

    test('empty stays empty', () {
      expect(expandExcludedFeatures(<String>{}), isEmpty);
    });
  });

  group('removeFeatureRegions', () {
    test('removes a Dart block inclusive of its markers', () {
      const src = "import 'a';\n"
          '// fst:feature:notifications:start\n'
          "import 'package:feature_notifications/x.dart';\n"
          '// fst:feature:notifications:end\n'
          "import 'b';\n";
      expect(
        removeFeatureRegions(src, 'notifications'),
        equals("import 'a';\nimport 'b';\n"),
      );
    });

    test('removes a YAML block', () {
      const src = 'dependencies:\n'
          '  # fst:feature:bookmarks:start\n'
          '  feature_bookmarks: ^0.1.0\n'
          '  # fst:feature:bookmarks:end\n'
          '  feature_auth: ^0.1.0\n';
      expect(
        removeFeatureRegions(src, 'bookmarks'),
        equals('dependencies:\n  feature_auth: ^0.1.0\n'),
      );
    });

    test('removes multiple blocks of the same feature', () {
      const src =
          '// fst:feature:bookmarks:start\nA\n// fst:feature:bookmarks:end\n'
          'keep\n'
          '// fst:feature:bookmarks:start\nB\n// fst:feature:bookmarks:end\n';
      expect(removeFeatureRegions(src, 'bookmarks'), equals('keep\n'));
    });

    test('leaves other features untouched', () {
      const src =
          '// fst:feature:bookmarks:start\nA\n// fst:feature:bookmarks:end\n'
          '// fst:feature:collections:start\nC\n// fst:feature:collections:end\n';
      final result = removeFeatureRegions(src, 'bookmarks');
      expect(result, contains('fst:feature:collections:start'));
      expect(result, contains('C'));
      expect(result, isNot(contains('fst:feature:bookmarks')));
    });

    test('is a no-op when the feature is absent', () {
      const src = "import 'a';\nimport 'b';\n";
      expect(removeFeatureRegions(src, 'bookmarks'), equals(src));
    });
  });

  group('excludeFeatures', () {
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
      dir = Directory.systemTemp.createTempSync('fst_features_test_');
      write(
        'pubspec.yaml',
        'dependencies:\n'
            '  # fst:feature:notifications:start\n'
            '  feature_notifications: ^0.1.0\n'
            '  # fst:feature:notifications:end\n'
            '  # fst:feature:bookmarks:start\n'
            '  feature_bookmarks: ^0.1.0\n'
            '  # fst:feature:bookmarks:end\n'
            '  feature_auth: ^0.1.0\n',
      );
      write('packages/features/notifications/pubspec.yaml', 'name: x\n');
      write('packages/features/bookmarks/pubspec.yaml', 'name: x\n');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('strips the regions and deletes the package, keeping others',
        () async {
      await excludeFeatures(dir.path, {'notifications'});

      final pubspec = read('pubspec.yaml');
      expect(pubspec, isNot(contains('feature_notifications')));
      expect(pubspec, contains('feature_bookmarks'));
      expect(pubspec, contains('feature_auth'));
      expect(exists('packages/features/notifications/pubspec.yaml'), isFalse);
      expect(exists('packages/features/bookmarks/pubspec.yaml'), isTrue);
    });

    test('empty set is a no-op', () async {
      await excludeFeatures(dir.path, <String>{});
      expect(exists('packages/features/notifications/pubspec.yaml'), isTrue);
    });

    test('keeps _infra unless every removable feature is excluded', () async {
      write(
        'lib/app/features.dart',
        '// fst:feature:_infra:start\n'
            "import 'di/injection.dart';\n"
            '// fst:feature:_infra:end\n',
      );
      await excludeFeatures(dir.path, {'notifications'});
      expect(read('lib/app/features.dart'), contains('di/injection.dart'));
    });

    test('strips _infra when all removable features are excluded', () async {
      write(
        'lib/app/features.dart',
        '// fst:feature:_infra:start\n'
            "import 'di/injection.dart';\n"
            '// fst:feature:_infra:end\n',
      );
      await excludeFeatures(
        dir.path,
        {'bookmarks', 'collections', 'notifications'},
      );
      expect(read('lib/app/features.dart'), isNot(contains('injection.dart')));
    });
  });
}
