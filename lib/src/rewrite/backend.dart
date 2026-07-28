import 'dart:io';

import 'package:path/path.dart' as p;

import 'database.dart';

/// Removes every `fst:backend:start` … `fst:backend:end` block (inclusive)
/// from [content].
///
/// Comment-style agnostic (`//` for Dart, `#` for YAML). Idempotent, and
/// leaves unrelated lines untouched. Throws [FormatException] on an unclosed
/// marker block.
String removeBackendRegions(String content) {
  const startNeedle = 'fst:backend:start';
  const endNeedle = 'fst:backend:end';
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
      'Unclosed backend marker block (missing "$endNeedle"). '
      'Refusing to rewrite to avoid corrupting the file.',
    );
  }
  return kept.join('\n');
}

/// App-shell wiring + test files that carry `fst:backend` regions.
const _backendWiringFiles = [
  'pubspec.yaml',
  'lib/app/di/injection.dart',
  'test/architecture/package_layering_test.dart',
  // The Drift package, still under its pre-rename name: `swapDatabase` runs
  // after this. On the ObjectBox path these files are stripped and then the
  // whole directory is deleted, so touching them costs nothing.
  'packages/database_drift/lib/database.dart',
  'packages/database_drift/lib/src/app_database.dart',
];

/// Files that are wholly backend-only and must be deleted when the backend
/// pillar is stripped (no partial strip needed — the entire file is gone).
const _backendOnlyFiles = [
  'lib/core/data/sync/objectbox_sync_cursor_store.dart',
  'test/architecture/authenticated_dio_test.dart',
];

/// Backend-only persistence files in the Drift package, under its pre-rename
/// name for the same reason as [_backendWiringFiles].
///
/// The sync-cursor table and row exist only to track how far each resource
/// has been pulled from the server, so they mean nothing in a local-only app.
/// ObjectBox keeps its equivalents — see [driftPackageDir].
const _backendOnlyDriftFiles = [
  'packages/database_drift/lib/src/tables/sync_cursors_table.dart',
  'packages/database_drift/lib/src/entities/sync_cursor_entity.dart',
];

/// Disables the backend (network + sync) pillar in a freshly scaffolded
/// [projectDir]: strips every `fst:backend` region from the wiring files,
/// deletes the backend-only source files, and removes the `packages/network`
/// and `packages/sync_connectivity_plus` package directories.
///
/// Phase 1 computes every rewrite in memory (throwing on a malformed marker)
/// before any file is written, so a bad marker aborts cleanly.
///
/// Idempotent: re-running on an already-stripped tree is a no-op.
Future<void> disableBackend(String projectDir) async {
  // Phase 1: compute every rewrite in memory.
  final pending = <File, String>{};
  for (final relative in _backendWiringFiles) {
    final file = File(p.join(projectDir, p.joinAll(relative.split('/'))));
    if (!file.existsSync()) continue;
    final original = file.readAsStringSync();
    final rewritten = removeBackendRegions(original);
    if (rewritten == original) continue;
    // Normalise to exactly one trailing newline (matches the eol_at_end_of_file
    // lint and mirrors the same normalisation in auth.dart).
    pending[file] = '${rewritten.trimRight()}\n';
  }

  // Phase 2: all rewrites computed cleanly — commit them.
  pending.forEach((file, content) => file.writeAsStringSync(content));

  // Phase 3: delete backend-only files (the network package is gone so they
  // would cause compile errors if left behind).
  for (final relative in _backendOnlyFiles) {
    final file = File(p.join(projectDir, p.joinAll(relative.split('/'))));
    if (file.existsSync()) file.deleteSync();
  }

  for (final relative in _backendOnlyDriftFiles) {
    final file = File(p.join(projectDir, p.joinAll(relative.split('/'))));
    if (file.existsSync()) file.deleteSync();
  }

  // Phase 4: delete the network and sync package directories.
  for (final packageName in const ['network', 'sync_connectivity_plus']) {
    final dir = Directory(p.join(projectDir, 'packages', packageName));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

/// Removes every `fst:revsync:start` … `fst:revsync:end` block from [content].
String removeRevSyncRegions(String content) {
  const startNeedle = 'fst:revsync:start';
  const endNeedle = 'fst:revsync:end';
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
      'Unclosed rev_sync marker block (missing "$endNeedle"). '
      'Refusing to rewrite to avoid corrupting the file.',
    );
  }
  return kept.join('\n');
}

/// Drops the vendored `rev_sync` engine from [projectDir].
///
/// Separate from [disableBackend] because it can only run once the database
/// engine is settled: ObjectBox entities implement `Syncable`, so on that path
/// `rev_sync` has to stay even in a local-only app. Call this only for
/// `--database drift` with the backend off, and only after `swapDatabase` —
/// the Drift package answers to `packages/database` by then.
///
/// Computes every rewrite before committing any, like the other rewriters, so
/// a malformed marker throws with the tree untouched rather than half-stripped.
///
/// Idempotent.
Future<void> removeRevSync(String projectDir) async {
  final pending = <File, String>{};
  for (final relative in const [
    'pubspec.yaml',
    'packages/database/pubspec.yaml',
  ]) {
    final file = File(p.join(projectDir, p.joinAll(relative.split('/'))));
    if (!file.existsSync()) continue;
    final original = file.readAsStringSync();
    final rewritten = removeRevSyncRegions(original);
    if (rewritten == original) continue;
    pending[file] = '${rewritten.trimRight()}\n';
  }

  pending.forEach((file, content) => file.writeAsStringSync(content));

  final revSync = Directory(p.join(projectDir, 'published', 'rev_sync'));
  if (revSync.existsSync()) revSync.deleteSync(recursive: true);
  final published = Directory(p.join(projectDir, 'published'));
  if (published.existsSync() && published.listSync().isEmpty) {
    published.deleteSync();
  }
}
