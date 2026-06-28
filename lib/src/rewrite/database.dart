import 'dart:io';

import 'package:path/path.dart' as p;

/// Removes every `fst:db:[markerName]:start` … `fst:db:[markerName]:end`
/// block (inclusive) from [content]. The stripped region and its markers are
/// discarded entirely. Throws [FormatException] on an unclosed block.
String _stripDbRegions(String content, String markerName) {
  final startNeedle = 'fst:db:$markerName:start';
  final endNeedle = 'fst:db:$markerName:end';
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
      'Unclosed db marker block "fst:db:$markerName" '
      '(missing "$endNeedle"). '
      'Refusing to rewrite to avoid corrupting the file.',
    );
  }
  return kept.join('\n');
}

/// Removes only the marker comment lines for `fst:db:[markerName]`, keeping
/// the content between them (the region is "activated / expanded").
String _expandDbRegions(String content, String markerName) {
  final startNeedle = 'fst:db:$markerName:start';
  final endNeedle = 'fst:db:$markerName:end';
  return content
      .split('\n')
      .where((l) => !l.contains(startNeedle) && !l.contains(endNeedle))
      .join('\n');
}

/// Files that carry both `fst:db:objectbox` and `fst:db:drift` marker regions.
///
/// Feature data-source files are NOT here — in the OB path they stay as-is
/// (OB-only, no markers); in the drift path they are overwritten wholesale by
/// [_activateDrift].
const _dbMarkedFiles = [
  'pubspec.yaml',
  'test/architecture/package_layering_test.dart',
];

/// Swaps the local database engine in [projectDir].
///
/// `objectbox` (default): strips `fst:db:drift` blocks, expands
/// `fst:db:objectbox` blocks, deletes the drift package directory.
///
/// `drift`: strips `fst:db:objectbox` blocks, expands `fst:db:drift` blocks,
/// renames `packages/database_drift` → `packages/database`, writes the Drift
/// DI module + sync cursor store, and overwrites the feature data-source files
/// with Drift-backed implementations.
///
/// [useBackend] controls whether the sync cursor store is generated (the sync
/// engine is stripped by `disableBackend` before this runs, so it must be
/// skipped here too when backend is off).
Future<void> swapDatabase(
  String projectDir, {
  required String choice,
  required bool useBackend,
}) async {
  if (choice == 'objectbox') {
    await _activateObjectBox(projectDir);
  } else {
    await _activateDrift(projectDir, useBackend: useBackend);
  }
}

Future<void> _activateObjectBox(String projectDir) async {
  // Phase 1: compute rewrites — strip drift regions, expand objectbox regions.
  final pending = <File, String>{};
  for (final relative in _dbMarkedFiles) {
    final file = File(p.join(projectDir, p.joinAll(relative.split('/'))));
    if (!file.existsSync()) continue;
    final original = file.readAsStringSync();
    var content = _stripDbRegions(original, 'drift');
    content = _expandDbRegions(content, 'objectbox');
    if (content == original) continue;
    pending[file] = '${content.trimRight()}\n';
  }

  // Phase 2: commit rewrites.
  pending.forEach((file, content) => file.writeAsStringSync(content));

  // Phase 3: delete the drift package directory.
  final driftDir = Directory(p.join(projectDir, 'packages', 'database_drift'));
  if (driftDir.existsSync()) driftDir.deleteSync(recursive: true);
}

Future<void> _activateDrift(
  String projectDir, {
  required bool useBackend,
}) async {
  // Phase 1: compute rewrites — strip objectbox regions, expand drift regions.
  final pending = <File, String>{};
  for (final relative in _dbMarkedFiles) {
    final file = File(p.join(projectDir, p.joinAll(relative.split('/'))));
    if (!file.existsSync()) continue;
    final original = file.readAsStringSync();
    var content = _stripDbRegions(original, 'objectbox');
    content = _expandDbRegions(content, 'drift');
    // After expanding drift regions, pubspec.yaml has `- packages/database_drift`
    // in the workspace; fix it to `- packages/database` (the post-rename path).
    if (relative == 'pubspec.yaml') {
      content = content.replaceAll(
        '  - packages/database_drift',
        '  - packages/database',
      );
    }
    if (content == original) continue;
    pending[file] = '${content.trimRight()}\n';
  }

  // Phase 2: commit rewrites.
  pending.forEach((file, content) => file.writeAsStringSync(content));

  // Phase 3: delete the objectbox package, rename drift → database, update name.
  final obDir = Directory(p.join(projectDir, 'packages', 'database'));
  if (obDir.existsSync()) obDir.deleteSync(recursive: true);

  final driftDir = Directory(p.join(projectDir, 'packages', 'database_drift'));
  final newDbDir = p.join(projectDir, 'packages', 'database');
  if (driftDir.existsSync()) driftDir.renameSync(newDbDir);

  final driftPubspec = File(p.join(newDbDir, 'pubspec.yaml'));
  if (driftPubspec.existsSync()) {
    driftPubspec.writeAsStringSync(
      driftPubspec
          .readAsStringSync()
          .replaceFirst('name: database_drift', 'name: database'),
    );
  }

  // Phase 4: delete objectbox-specific files from the root app.
  for (final relative in const [
    'lib/core/data/database/object_box_module.dart',
    'lib/core/data/sync/objectbox_sync_cursor_store.dart',
  ]) {
    final file = File(p.join(projectDir, p.joinAll(relative.split('/'))));
    if (file.existsSync()) file.deleteSync();
  }

  // Phase 5: write drift-specific root-app files.
  if (useBackend) _writeDriftSyncCursorStore(projectDir);
  _writeDriftModule(projectDir, useBackend: useBackend);

  // Phase 6: overwrite the feature data-source files with Drift implementations.
  _writeBookmarksDataSource(projectDir);
  _writeCollectionsDataSource(projectDir);
  _writeNotificationsDataSource(projectDir);
}

void _writeDriftSyncCursorStore(String projectDir) {
  File(
    p.join(
      projectDir,
      'lib',
      'core',
      'data',
      'sync',
      'drift_sync_cursor_store.dart',
    ),
  ).writeAsStringSync('''
import 'package:database/database.dart';
import 'package:rev_sync/rev_sync.dart';

/// Drift-backed [SyncCursorStore]. One row per sync resource in
/// [AppDatabase.syncCursors]; upserted atomically via
/// [insertOnConflictUpdate].
class DriftSyncCursorStore implements SyncCursorStore {
  DriftSyncCursorStore(this._db);

  final AppDatabase _db;

  @override
  Future<int> read(String resource) async {
    final row = await (_db.select(_db.syncCursors)
          ..where((c) => c.resource.equals(resource)))
        .getSingleOrNull();
    return row?.rev ?? 0;
  }

  @override
  Future<void> write(String resource, int rev) async {
    await _db.into(_db.syncCursors).insertOnConflictUpdate(
      SyncCursorsCompanion.insert(resource: resource, rev: rev),
    );
  }
}
''');
}

void _writeDriftModule(String projectDir, {required bool useBackend}) {
  final syncImports = useBackend
      ? "import 'package:rev_sync/rev_sync.dart';\n"
          "import '../sync/drift_sync_cursor_store.dart';\n"
      : '';

  final syncProvider = useBackend
      ? '''
  @lazySingleton
  SyncCursorStore provideSyncCursorStore(AppDatabase db) =>
      DriftSyncCursorStore(db);
'''
      : '';

  File(
    p.join(
      projectDir,
      'lib',
      'core',
      'data',
      'database',
      'drift_module.dart',
    ),
  ).writeAsStringSync('''
import 'package:database/database.dart';
import 'package:injectable/injectable.dart';
$syncImports// fst:feature:bookmarks:start
import 'package:feature_bookmarks/src/data/local/bookmarks_local_data_source.dart';
// fst:feature:bookmarks:end
// fst:feature:collections:start
import 'package:feature_collections/src/data/local/collections_local_data_source.dart';
// fst:feature:collections:end
// fst:feature:notifications:start
import 'package:feature_notifications/src/data/local/notifications_local_data_source.dart';
// fst:feature:notifications:end

/// Drift DI module: provides [AppDatabase] and the feature data sources backed
/// by Drift. Auto-discovered by injectable_generator via the [@module]
/// annotation — no explicit entry in [externalPackageModulesBefore] needed.
@module
abstract class DriftModule {
  @lazySingleton
  AppDatabase provideDatabase() => AppDatabase.open();

$syncProvider  // fst:feature:bookmarks:start
  @lazySingleton
  BookmarksLocalDataSource provideBookmarksLocalDataSource(
    AppDatabase db,
  ) =>
      DriftBookmarksDataSource(db);
  // fst:feature:bookmarks:end

  // fst:feature:collections:start
  @lazySingleton
  CollectionsLocalDataSource provideCollectionsLocalDataSource(
    AppDatabase db,
  ) =>
      DriftCollectionsDataSource(db);
  // fst:feature:collections:end

  // fst:feature:notifications:start
  @lazySingleton
  NotificationsLocalDataSource provideNotificationsLocalDataSource(
    AppDatabase db,
  ) =>
      DriftNotificationsDataSource(db);
  // fst:feature:notifications:end
}
''');
}

void _writeBookmarksDataSource(String projectDir) {
  File(
    p.join(
      projectDir,
      'packages',
      'features',
      'bookmarks',
      'lib',
      'src',
      'data',
      'local',
      'bookmarks_local_data_source.dart',
    ),
  ).writeAsStringSync('''
import 'package:database/database.dart';
import 'package:rev_sync/rev_sync.dart';

/// Drift-backed CRUD + sync helpers. All operations are async using Drift's
/// select/into API; wrapped in [Future] for a uniform contract.
///
/// Identity at this layer is the string [BookmarkEntity.uuid]. The integer
/// [BookmarkEntity.id] is the Drift auto-increment PK. Implements
/// [SyncLocalStore] so the generic sync engine can drive it.
abstract interface class BookmarksLocalDataSource
    implements SyncLocalStore<BookmarkEntity> {
  /// All non-tombstoned bookmarks, newest-first.
  Future<List<BookmarkEntity>> listVisible();

  /// Includes tombstoned (pendingDelete) rows.
  Future<List<BookmarkEntity>> listAll();

  /// Inserts a new row in [SyncState.pendingCreate].
  Future<BookmarkEntity> putNew(BookmarkEntity entity);
}

class DriftBookmarksDataSource implements BookmarksLocalDataSource {
  DriftBookmarksDataSource(AppDatabase db) : _db = db;

  final AppDatabase _db;

  @override
  Future<List<BookmarkEntity>> listVisible() async {
    final rows = await (_db.select(_db.bookmarks)
          ..where(
            (b) => b.syncStateCode.isNotValue(SyncState.pendingDelete.code),
          )
          ..orderBy([(b) => OrderingTerm.desc(b.createdAtUs)]))
        .get();
    return rows.map(_rowToEntity).toList();
  }

  @override
  Future<List<BookmarkEntity>> listAll() async {
    final rows = await (_db.select(_db.bookmarks)
          ..orderBy([(b) => OrderingTerm.desc(b.createdAtUs)]))
        .get();
    return rows.map(_rowToEntity).toList();
  }

  @override
  Future<BookmarkEntity?> getByUuid(String uuid) async {
    final row = await (_db.select(_db.bookmarks)
          ..where((b) => b.uuid.equals(uuid)))
        .getSingleOrNull();
    return row == null ? null : _rowToEntity(row);
  }

  @override
  Future<List<BookmarkEntity>> listPending() async {
    final codes = [
      SyncState.pendingCreate.code,
      SyncState.pendingUpdate.code,
      SyncState.pendingDelete.code,
    ];
    final rows = await (_db.select(_db.bookmarks)
          ..where((b) => b.syncStateCode.isIn(codes))
          ..orderBy([(b) => OrderingTerm.asc(b.updatedAtUs)]))
        .get();
    return rows.map(_rowToEntity).toList();
  }

  @override
  Future<BookmarkEntity> putNew(BookmarkEntity entity) async {
    entity.id = await _db.into(_db.bookmarks).insert(_toCompanion(entity));
    return entity;
  }

  @override
  Future<void> put(BookmarkEntity entity) async {
    await _db
        .into(_db.bookmarks)
        .insertOnConflictUpdate(_toCompanion(entity));
  }

  @override
  Future<void> hardDelete(BookmarkEntity entity) async {
    await (_db.delete(_db.bookmarks)
          ..where((b) => b.id.equals(entity.id)))
        .go();
  }

  BookmarkEntity _rowToEntity(BookmarkRow row) => BookmarkEntity(
        id: row.id,
        uuid: row.uuid,
        title: row.title,
        url: row.url,
        description: row.description,
        tags: (jsonDecode(row.tagsJson) as List<dynamic>).cast<String>(),
        imageUrls:
            (jsonDecode(row.imageUrlsJson) as List<dynamic>).cast<String>(),
        videoUrl: row.videoUrl,
        createdAt: DateTime.fromMicrosecondsSinceEpoch(
          row.createdAtUs,
          isUtc: true,
        ),
        updatedAt: DateTime.fromMicrosecondsSinceEpoch(
          row.updatedAtUs,
          isUtc: true,
        ),
        serverUpdatedAt: row.serverUpdatedAtUs == null
            ? null
            : DateTime.fromMicrosecondsSinceEpoch(
                row.serverUpdatedAtUs!,
                isUtc: true,
              ),
        rev: row.rev,
        syncStateCode: row.syncStateCode,
      );

  BookmarksCompanion _toCompanion(BookmarkEntity e) => BookmarksCompanion(
        id: e.id == 0 ? const Value.absent() : Value(e.id),
        uuid: Value(e.uuid),
        title: Value(e.title),
        url: Value(e.url),
        description: Value(e.description),
        tagsJson: Value(jsonEncode(e.tags)),
        imageUrlsJson: Value(jsonEncode(e.imageUrls)),
        videoUrl: Value(e.videoUrl),
        createdAtUs: Value(e.createdAt.microsecondsSinceEpoch),
        updatedAtUs: Value(e.updatedAt.microsecondsSinceEpoch),
        serverUpdatedAtUs: Value(e.serverUpdatedAt?.microsecondsSinceEpoch),
        rev: Value(e.rev),
        syncStateCode: Value(e.syncStateCode),
      );
}
''');
}

void _writeCollectionsDataSource(String projectDir) {
  File(
    p.join(
      projectDir,
      'packages',
      'features',
      'collections',
      'lib',
      'src',
      'data',
      'local',
      'collections_local_data_source.dart',
    ),
  ).writeAsStringSync('''
import 'package:database/database.dart';
import 'package:rev_sync/rev_sync.dart';

/// Drift-backed CRUD + sync helpers. All operations are async using Drift's
/// select/into API; wrapped in [Future] for a uniform contract.
///
/// Identity at this layer is the string [CollectionEntity.uuid]. The integer
/// [CollectionEntity.id] is the Drift auto-increment PK. Implements
/// [SyncLocalStore] so the generic sync engine can drive it.
abstract interface class CollectionsLocalDataSource
    implements SyncLocalStore<CollectionEntity> {
  /// All non-tombstoned collections, newest-first.
  Future<List<CollectionEntity>> listVisible();

  /// Includes tombstoned (pendingDelete) rows.
  Future<List<CollectionEntity>> listAll();

  /// Inserts a new row in [SyncState.pendingCreate].
  Future<CollectionEntity> putNew(CollectionEntity entity);
}

class DriftCollectionsDataSource implements CollectionsLocalDataSource {
  DriftCollectionsDataSource(AppDatabase db) : _db = db;

  final AppDatabase _db;

  @override
  Future<List<CollectionEntity>> listVisible() async {
    final rows = await (_db.select(_db.collections)
          ..where(
            (c) => c.syncStateCode.isNotValue(SyncState.pendingDelete.code),
          )
          ..orderBy([(c) => OrderingTerm.desc(c.createdAtUs)]))
        .get();
    return rows.map(_rowToEntity).toList();
  }

  @override
  Future<List<CollectionEntity>> listAll() async {
    final rows = await (_db.select(_db.collections)
          ..orderBy([(c) => OrderingTerm.desc(c.createdAtUs)]))
        .get();
    return rows.map(_rowToEntity).toList();
  }

  @override
  Future<CollectionEntity?> getByUuid(String uuid) async {
    final row = await (_db.select(_db.collections)
          ..where((c) => c.uuid.equals(uuid)))
        .getSingleOrNull();
    return row == null ? null : _rowToEntity(row);
  }

  @override
  Future<List<CollectionEntity>> listPending() async {
    final codes = [
      SyncState.pendingCreate.code,
      SyncState.pendingUpdate.code,
      SyncState.pendingDelete.code,
    ];
    final rows = await (_db.select(_db.collections)
          ..where((c) => c.syncStateCode.isIn(codes))
          ..orderBy([(c) => OrderingTerm.asc(c.updatedAtUs)]))
        .get();
    return rows.map(_rowToEntity).toList();
  }

  @override
  Future<CollectionEntity> putNew(CollectionEntity entity) async {
    entity.id =
        await _db.into(_db.collections).insert(_toCompanion(entity));
    return entity;
  }

  @override
  Future<void> put(CollectionEntity entity) async {
    await _db
        .into(_db.collections)
        .insertOnConflictUpdate(_toCompanion(entity));
  }

  @override
  Future<void> hardDelete(CollectionEntity entity) async {
    await (_db.delete(_db.collections)
          ..where((c) => c.id.equals(entity.id)))
        .go();
  }

  CollectionEntity _rowToEntity(CollectionRow row) => CollectionEntity(
        id: row.id,
        uuid: row.uuid,
        name: row.name,
        icon: row.icon,
        color: row.color,
        bookmarkIds: (jsonDecode(row.bookmarkIdsJson) as List<dynamic>)
            .cast<String>(),
        createdAt: DateTime.fromMicrosecondsSinceEpoch(
          row.createdAtUs,
          isUtc: true,
        ),
        updatedAt: DateTime.fromMicrosecondsSinceEpoch(
          row.updatedAtUs,
          isUtc: true,
        ),
        serverUpdatedAt: row.serverUpdatedAtUs == null
            ? null
            : DateTime.fromMicrosecondsSinceEpoch(
                row.serverUpdatedAtUs!,
                isUtc: true,
              ),
        rev: row.rev,
        syncStateCode: row.syncStateCode,
      );

  CollectionsCompanion _toCompanion(CollectionEntity e) =>
      CollectionsCompanion(
        id: e.id == 0 ? const Value.absent() : Value(e.id),
        uuid: Value(e.uuid),
        name: Value(e.name),
        icon: Value(e.icon),
        color: Value(e.color),
        bookmarkIdsJson: Value(jsonEncode(e.bookmarkIds)),
        createdAtUs: Value(e.createdAt.microsecondsSinceEpoch),
        updatedAtUs: Value(e.updatedAt.microsecondsSinceEpoch),
        serverUpdatedAtUs: Value(e.serverUpdatedAt?.microsecondsSinceEpoch),
        rev: Value(e.rev),
        syncStateCode: Value(e.syncStateCode),
      );
}
''');
}

void _writeNotificationsDataSource(String projectDir) {
  File(
    p.join(
      projectDir,
      'packages',
      'features',
      'notifications',
      'lib',
      'src',
      'data',
      'local',
      'notifications_local_data_source.dart',
    ),
  ).writeAsStringSync('''
import 'package:database/database.dart';

/// Drift-backed cache for the notifications feed. All operations are async
/// using Drift's select/into API.
///
/// Identity is the string [NotificationEntity.uuid] (the server id); the
/// integer [NotificationEntity.id] is the Drift auto-increment PK and is
/// only used for [removeNotification] / [removeActivity].
abstract interface class NotificationsLocalDataSource {
  /// Cached notifications, newest-first.
  Future<List<NotificationEntity>> notifications();

  /// Cached activity entries, newest-first.
  Future<List<ActivityEntity>> activities();

  /// Notifications whose local read-mark hasn't been pushed yet.
  Future<List<NotificationEntity>> pendingReads();

  Future<NotificationEntity?> getNotification(String uuid);

  Future<void> putNotification(NotificationEntity entity);

  Future<void> putActivity(ActivityEntity entity);

  /// Flags [uuid] as read locally and queues its read-mark for push. No-op if
  /// the row is unknown or already read.
  Future<void> markReadPending(String uuid);

  /// Hard-removes a notification by internal PK. Used by the pull reconciler.
  Future<void> removeNotification(int pk);

  /// Hard-removes an activity entry by internal PK. Used by the pull
  /// reconciler.
  Future<void> removeActivity(int pk);
}

class DriftNotificationsDataSource implements NotificationsLocalDataSource {
  DriftNotificationsDataSource(AppDatabase db) : _db = db;

  final AppDatabase _db;

  @override
  Future<List<NotificationEntity>> notifications() async {
    final rows = await (_db.select(_db.notifications)
          ..orderBy([(n) => OrderingTerm.desc(n.createdAtUs)]))
        .get();
    return rows.map(_notifToEntity).toList();
  }

  @override
  Future<List<ActivityEntity>> activities() async {
    final rows = await (_db.select(_db.activities)
          ..orderBy([(a) => OrderingTerm.desc(a.createdAtUs)]))
        .get();
    return rows.map(_activityToEntity).toList();
  }

  @override
  Future<List<NotificationEntity>> pendingReads() async {
    final rows = await (_db.select(_db.notifications)
          ..where((n) => n.pendingRead.equals(true)))
        .get();
    return rows.map(_notifToEntity).toList();
  }

  @override
  Future<NotificationEntity?> getNotification(String uuid) async {
    final row = await (_db.select(_db.notifications)
          ..where((n) => n.uuid.equals(uuid)))
        .getSingleOrNull();
    return row == null ? null : _notifToEntity(row);
  }

  @override
  Future<void> putNotification(NotificationEntity entity) async {
    await _db
        .into(_db.notifications)
        .insertOnConflictUpdate(_notifToCompanion(entity));
  }

  @override
  Future<void> putActivity(ActivityEntity entity) async {
    await _db
        .into(_db.activities)
        .insertOnConflictUpdate(_activityToCompanion(entity));
  }

  @override
  Future<void> markReadPending(String uuid) async {
    final row = await getNotification(uuid);
    if (row == null || row.isRead) return;
    row
      ..isRead = true
      ..pendingRead = true;
    await putNotification(row);
  }

  @override
  Future<void> removeNotification(int pk) async {
    await (_db.delete(_db.notifications)
          ..where((n) => n.id.equals(pk)))
        .go();
  }

  @override
  Future<void> removeActivity(int pk) async {
    await (_db.delete(_db.activities)..where((a) => a.id.equals(pk))).go();
  }

  NotificationEntity _notifToEntity(NotificationRow row) => NotificationEntity(
        id: row.id,
        uuid: row.uuid,
        title: row.title,
        body: row.body,
        type: row.type,
        isRead: row.isRead,
        createdAt: DateTime.fromMicrosecondsSinceEpoch(
          row.createdAtUs,
          isUtc: true,
        ),
        pendingRead: row.pendingRead,
      );

  NotificationsCompanion _notifToCompanion(NotificationEntity e) =>
      NotificationsCompanion(
        id: e.id == 0 ? const Value.absent() : Value(e.id),
        uuid: Value(e.uuid),
        title: Value(e.title),
        body: Value(e.body),
        type: Value(e.type),
        isRead: Value(e.isRead),
        createdAtUs: Value(e.createdAt.microsecondsSinceEpoch),
        pendingRead: Value(e.pendingRead),
      );

  ActivityEntity _activityToEntity(ActivityRow row) => ActivityEntity(
        id: row.id,
        uuid: row.uuid,
        description: row.description,
        type: row.type,
        createdAt: DateTime.fromMicrosecondsSinceEpoch(
          row.createdAtUs,
          isUtc: true,
        ),
      );

  ActivitiesCompanion _activityToCompanion(ActivityEntity e) =>
      ActivitiesCompanion(
        id: e.id == 0 ? const Value.absent() : Value(e.id),
        uuid: Value(e.uuid),
        description: Value(e.description),
        type: Value(e.type),
        createdAtUs: Value(e.createdAt.microsecondsSinceEpoch),
      );
}
''');
}
