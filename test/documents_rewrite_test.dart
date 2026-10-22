import 'dart:io';

import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('removeDocumentRegions', () {
    test('removes only the selected document component', () {
      const source = '// fst:document:engine:start\n'
          'engine\n'
          '// fst:document:engine:end\n'
          '// fst:document:center:start\n'
          'center\n'
          '// fst:document:center:end\n';

      final result = removeDocumentRegions(source, 'center');

      expect(result, contains('engine'));
      expect(result, isNot(contains('center')));
    });

    test('rejects an unclosed marker', () {
      expect(
        () => removeDocumentRegions(
          '// fst:document:engine:start\nengine\n',
          'engine',
        ),
        throwsFormatException,
      );
    });
  });

  group('configureDocuments', () {
    late Directory root;

    void write(String relative, String content) {
      File(p.join(root.path, p.joinAll(relative.split('/'))))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    String read(String relative) =>
        File(p.join(root.path, p.joinAll(relative.split('/'))))
            .readAsStringSync();

    setUp(() {
      root = Directory.systemTemp.createTempSync('fst-documents-');
      for (final relative in const [
        'pubspec.yaml',
        'lib/app/di/injection.dart',
        'lib/app/features.dart',
        'test/architecture/package_layering_test.dart',
        'packages/features/bookmarks/pubspec.yaml',
        'packages/features/bookmarks/lib/feature_bookmarks.dart',
        'packages/features/bookmarks/lib/src/di.module.dart',
        'packages/features/bookmarks/lib/src/presentation/widgets/bookmarks_list_widgets.dart',
        'packages/features/collections/pubspec.yaml',
        'packages/features/collections/lib/feature_collections.dart',
        'packages/features/collections/lib/src/di.module.dart',
        'packages/features/collections/lib/src/presentation/screens/collections_list_screen.dart',
      ]) {
        write(
          relative,
          'keep\n'
          '// fst:document:engine:start\nengine\n'
          '// fst:document:engine:end\n'
          '// fst:document:center:start\ncenter\n'
          '// fst:document:center:end\n',
        );
      }
      write('packages/document_engine/pubspec.yaml', 'name: document_engine\n');
      write(
        'packages/features/document_center/pubspec.yaml',
        'name: feature_document_center\n',
      );
      write(
        'packages/features/bookmarks/lib/src/domain/services/bookmarks_import_delegate.dart',
        'delegate\n',
      );
      write(
        'packages/features/collections/lib/src/domain/services/collections_import_delegate.dart',
        'delegate\n',
      );
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('keeps the engine while removing Document Center', () async {
      await configureDocuments(
        root.path,
        includeEngine: true,
        includeCenter: false,
      );

      expect(read('pubspec.yaml'), contains('engine'));
      expect(read('pubspec.yaml'), isNot(contains('center')));
      expect(
        Directory(p.join(root.path, 'packages/document_engine')).existsSync(),
        isTrue,
      );
      expect(
        Directory(
          p.join(root.path, 'packages/features/document_center'),
        ).existsSync(),
        isFalse,
      );
    });

    test('removes both packages and every wiring region', () async {
      await configureDocuments(
        root.path,
        includeEngine: false,
        includeCenter: false,
      );

      for (final relative in const [
        'pubspec.yaml',
        'lib/app/di/injection.dart',
        'lib/app/features.dart',
        'test/architecture/package_layering_test.dart',
        'packages/features/bookmarks/pubspec.yaml',
        'packages/features/bookmarks/lib/feature_bookmarks.dart',
        'packages/features/bookmarks/lib/src/di.module.dart',
        'packages/features/bookmarks/lib/src/presentation/widgets/bookmarks_list_widgets.dart',
        'packages/features/collections/pubspec.yaml',
        'packages/features/collections/lib/feature_collections.dart',
        'packages/features/collections/lib/src/di.module.dart',
        'packages/features/collections/lib/src/presentation/screens/collections_list_screen.dart',
      ]) {
        expect(read(relative), equals('keep\n'), reason: relative);
      }
      expect(
        Directory(p.join(root.path, 'packages/document_engine')).existsSync(),
        isFalse,
      );
      expect(
        Directory(
          p.join(root.path, 'packages/features/document_center'),
        ).existsSync(),
        isFalse,
      );
      expect(
        File(
          p.join(
            root.path,
            'packages/features/bookmarks/lib/src/domain/services/bookmarks_import_delegate.dart',
          ),
        ).existsSync(),
        isFalse,
      );
      expect(
        File(
          p.join(
            root.path,
            'packages/features/collections/lib/src/domain/services/collections_import_delegate.dart',
          ),
        ).existsSync(),
        isFalse,
      );
    });

    test('rejects Document Center without its engine before writing', () async {
      final before = read('pubspec.yaml');

      await expectLater(
        configureDocuments(
          root.path,
          includeEngine: false,
          includeCenter: true,
        ),
        throwsFormatException,
      );

      expect(read('pubspec.yaml'), before);
    });
  });
}
