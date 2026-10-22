import 'dart:io';

import 'package:path/path.dart' as p;

import 'features.dart';

/// Files that compose the optional document packages into the application.
const _documentWiringFiles = [
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
];

/// Standalone source and test files that depend strictly on Document Engine and
/// are removed when the engine is excluded while keeping their parent feature.
const _engineDependentFiles = [
  'packages/features/bookmarks/lib/src/domain/services/bookmarks_import_delegate.dart',
  'packages/features/bookmarks/lib/src/domain/services/bookmarks_import_definition.dart',
  'packages/features/bookmarks/lib/src/domain/usecases/import_bookmarks.dart',
  'packages/features/bookmarks/lib/src/presentation/widgets/bookmarks_import_sheet.dart',
  'packages/features/bookmarks/test/domain/usecases/import_bookmarks_test.dart',
  'packages/features/bookmarks/test/presentation/widgets/bookmarks_import_sheet_test.dart',
  'packages/features/collections/lib/src/domain/services/collections_import_delegate.dart',
  'packages/features/collections/lib/src/domain/services/collections_import_definition.dart',
  'packages/features/collections/lib/src/domain/usecases/import_collections.dart',
  'packages/features/collections/lib/src/presentation/widgets/collections_import_sheet.dart',
  'packages/features/collections/test/domain/usecases/import_collections_test.dart',
  'packages/features/collections/test/presentation/widgets/collections_import_sheet_test.dart',
];

/// Removes all regions for [component], including their marker lines.
String removeDocumentRegions(String content, String component) {
  final startNeedle = 'fst:document:$component:start';
  final endNeedle = 'fst:document:$component:end';
  final kept = <String>[];
  var skipping = false;
  for (final line in content.split('\n')) {
    if (skipping) {
      if (line.contains(endNeedle)) skipping = false;
      continue;
    }
    if (line.contains(startNeedle)) {
      skipping = true;
      continue;
    }
    kept.add(line);
  }
  if (skipping) {
    throw FormatException(
      'Unclosed document marker block for "$component" '
      '(missing "$endNeedle"). Refusing to rewrite the project.',
    );
  }
  return kept.join('\n');
}

/// Applies the optional Document Engine / Document Center project shape.
///
/// Document Center is a consumer of Document Engine, so keeping the center
/// without the engine is rejected. All rewrites are computed before any file
/// is written or package directory is deleted.
Future<void> configureDocuments(
  String projectDir, {
  required bool includeEngine,
  required bool includeCenter,
}) async {
  if (includeCenter && !includeEngine) {
    throw const FormatException(
      'Document Center requires Document Engine.',
    );
  }
  if (includeEngine && includeCenter) return;

  final pending = <File, String>{};
  for (final relative in _documentWiringFiles) {
    final file = File(p.join(projectDir, p.joinAll(relative.split('/'))));
    if (!file.existsSync()) continue;
    final original = file.readAsStringSync();
    var rewritten = original;
    if (!includeCenter) {
      rewritten = removeDocumentRegions(rewritten, 'center');
      if (relative == 'lib/app/features.dart' &&
          !rewritten.contains('Module()')) {
        rewritten = removeFeatureRegions(rewritten, '_infra');
        rewritten = removeFeatureRegions(rewritten, '_router');
      }
    }
    if (!includeEngine) {
      rewritten = removeDocumentRegions(rewritten, 'engine');
    }
    if (rewritten != original) {
      pending[file] = '${rewritten.trimRight()}\n';
    }
  }

  pending.forEach((file, content) => file.writeAsStringSync(content));

  if (!includeCenter) {
    final center = Directory(
      p.join(projectDir, 'packages', 'features', 'document_center'),
    );
    if (center.existsSync()) center.deleteSync(recursive: true);
  }
  if (!includeEngine) {
    final engine = Directory(p.join(projectDir, 'packages', 'document_engine'));
    if (engine.existsSync()) engine.deleteSync(recursive: true);

    for (final relative in _engineDependentFiles) {
      final file = File(p.join(projectDir, p.joinAll(relative.split('/'))));
      if (file.existsSync()) file.deleteSync();
    }
  }
}
