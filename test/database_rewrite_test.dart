import 'dart:io';

import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  void write(String relative, String content) {
    File(p.join(tempDir.path, p.joinAll(relative.split('/'))))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('fst_database_rewrite_');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('Drift invalidates every ObjectBox-dependent generated DI output',
      () async {
    write('pubspec.yaml', '''
# fst:db:objectbox:start
objectbox: true
# fst:db:objectbox:end
# fst:db:drift:start
  - packages/database_drift
# fst:db:drift:end
''');
    write('packages/database/pubspec.yaml', 'name: database\nobjectbox: any\n');
    write(
      'packages/database_drift/pubspec.yaml',
      'name: database_drift\ndrift: any\n',
    );
    write(
      'packages/database_drift/lib/src/app_database.dart',
      'class AppDatabase { static AppDatabase open() => AppDatabase(); }\n',
    );
    write(
      'packages/database_drift/lib/src/app_database.g.dart',
      '// stale generated tables\n',
    );
    write(
      'lib/app/di/injection.config.dart',
      'final store = ObjectBox();\n',
    );
    write('lib/core/data/sync/.keep', '');
    write('lib/core/data/database/.keep', '');
    for (final feature in ['bookmarks', 'collections', 'notifications']) {
      write(
        'packages/features/$feature/lib/src/di.module.dart',
        'final store = ObjectBox${feature}DataSource();\n',
      );
      write(
        'packages/features/$feature/lib/src/data/local/'
            '${feature}_local_data_source.dart',
        '// ObjectBox source\n',
      );
    }

    await swapDatabase(tempDir.path, choice: 'drift', useBackend: true);

    expect(
      File(p.join(tempDir.path, 'packages/database/pubspec.yaml'))
          .readAsStringSync(),
      contains('name: database\ndrift: any'),
    );
    for (final relative in [
      'lib/app/di/injection.config.dart',
      'packages/database/lib/src/app_database.g.dart',
      'packages/features/bookmarks/lib/src/di.module.dart',
      'packages/features/collections/lib/src/di.module.dart',
      'packages/features/notifications/lib/src/di.module.dart',
    ]) {
      expect(
        File(p.join(tempDir.path, relative)).existsSync(),
        isFalse,
        reason: relative,
      );
    }
    final module = File(
      p.join(tempDir.path, 'lib/core/data/database/drift_module.dart'),
    ).readAsStringSync();
    expect(module, contains('abstract class DriftModule'));
    expect(module, isNot(contains('ObjectBox')));
    expect(module, isNot(contains('feature_bookmarks')));
    expect(module, isNot(contains('feature_collections')));
    expect(module, isNot(contains('feature_notifications')));
    expect(
      module.indexOf("package:database/database.dart"),
      lessThan(module.indexOf("package:injectable/injectable.dart")),
    );
    expect(
      module.indexOf("package:injectable/injectable.dart"),
      lessThan(module.indexOf("package:rev_sync/rev_sync.dart")),
    );
    expect(
      module.indexOf("package:rev_sync/rev_sync.dart"),
      lessThan(module.indexOf("../sync/drift_sync_cursor_store.dart")),
    );
    final bookmarksDs = File(
      p.join(
        tempDir.path,
        'packages/features/bookmarks/lib/src/data/local/bookmarks_local_data_source.dart',
      ),
    ).readAsStringSync();
    expect(bookmarksDs, contains('@LazySingleton(as: BookmarksLocalDataSource)'));
  });

  test('ObjectBox removes stray Drift root bindings', () async {
    write('pubspec.yaml', '''
# fst:db:objectbox:start
objectbox: true
# fst:db:objectbox:end
# fst:db:drift:start
drift: true
# fst:db:drift:end
''');
    write(
      'packages/database_drift/lib/src/app_database.dart',
      'class AppDatabase {}\n',
    );
    write('lib/core/data/database/drift_module.dart', 'DriftModule\n');
    write(
      'lib/core/data/sync/drift_sync_cursor_store.dart',
      'DriftSyncCursorStore\n',
    );

    await swapDatabase(tempDir.path, choice: 'objectbox', useBackend: true);

    expect(
      Directory(p.join(tempDir.path, 'packages/database_drift')).existsSync(),
      isFalse,
    );
    expect(
      File(
        p.join(tempDir.path, 'lib/core/data/database/drift_module.dart'),
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        p.join(
          tempDir.path,
          'lib/core/data/sync/drift_sync_cursor_store.dart',
        ),
      ).existsSync(),
      isFalse,
    );
  });
}
