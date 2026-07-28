import 'dart:io';

import 'package:path/path.dart' as p;

/// The demo end-to-end suite, its driver, and its runner script.
///
/// Every file here drives the bundled demo app against the real
/// `simple_backend_server`: it registers a user, creates and edits a bookmark,
/// creates a collection, reads the notifications feed, then signs out. That
/// journey only holds together when the backend, auth, and all three demo
/// features are present — strip any of them and the suite stops compiling,
/// let alone asserting anything meaningful.
const _e2eFiles = [
  'integration_test/e2e_test.dart',
  'integration_test/screenshots_test.dart',
  'integration_test/support/e2e_app.dart',
  'integration_test/README.md',
  'test_driver/integration_test.dart',
  'tool/run_e2e.sh',
];

/// Directories that exist only to hold [_e2eFiles], innermost first so an
/// emptied parent is reached after its child is gone.
const _e2eDirs = [
  'integration_test/support',
  'integration_test',
  'test_driver',
];

/// Deletes the demo end-to-end suite from [projectDir].
///
/// Call this whenever the scaffold drops a pillar the suite depends on — the
/// backend, auth, or any of the removable demo features. The
/// `integration_test` dev-dependency is deliberately left in `pubspec.yaml`:
/// it costs nothing (it ships with the Flutter SDK) and the project is
/// expected to grow its own integration tests.
///
/// Idempotent: absent files are skipped, and a directory is only removed once
/// it is empty — so anything the user added survives.
Future<void> pruneE2eSuite(String projectDir) async {
  for (final relative in _e2eFiles) {
    final file = File(p.join(projectDir, p.joinAll(relative.split('/'))));
    if (file.existsSync()) file.deleteSync();
  }

  for (final relative in _e2eDirs) {
    final dir = Directory(p.join(projectDir, p.joinAll(relative.split('/'))));
    if (dir.existsSync() && dir.listSync().isEmpty) dir.deleteSync();
  }
}
