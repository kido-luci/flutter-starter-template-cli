import 'dart:io';

import 'package:path/path.dart' as p;

/// Removes every `fst:auth:start` … `fst:auth:end` block (inclusive) from
/// [content].
///
/// Comment-style agnostic (`//` for Dart, `#` for YAML). Idempotent, and
/// leaves unrelated lines untouched. Throws [FormatException] on an unclosed
/// marker block.
String removeAuthRegions(String content) {
  const startNeedle = 'fst:auth:start';
  const endNeedle = 'fst:auth:end';
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
      'Unclosed auth marker block (missing "$endNeedle"). '
      'Refusing to rewrite to avoid corrupting the file.',
    );
  }
  return kept.join('\n');
}

/// App-shell wiring + test files that carry `fst:auth` regions.
const _authWiringFiles = [
  'pubspec.yaml',
  'lib/app/app.dart',
  'lib/app/router.dart',
  'lib/app/di/injection.dart',
  'packages/features/splash/pubspec.yaml',
  'packages/features/splash/lib/src/presentation/screens/splash_screen.dart',
  'packages/features/profile/pubspec.yaml',
  'packages/features/profile/lib/src/presentation/screens/profile_screen.dart',
  'packages/features/profile/lib/src/presentation/widgets/profile_widgets.dart',
  'packages/features/profile/lib/src/presentation/widgets/profile_about.dart',
  'test/widget_test.dart',
  'test/test_utils/mocks.dart',
  'test/app/router_redirect_test.dart',
  'test/architecture/package_layering_test.dart',
  'test/architecture/feature_boundaries_test.dart',
];

/// Part-file widgets that are whole-file auth-only (their `part` directives
/// are in `profile_widgets.dart` and are removed by the region stripper).
const _authOnlyPartFiles = [
  'packages/features/profile/lib/src/presentation/widgets/profile_header.dart',
  'packages/features/profile/lib/src/presentation/widgets/profile_account.dart',
];

/// Disables auth in a freshly scaffolded [projectDir]: strips every
/// `fst:auth` region from the wiring files, deletes the auth-only part
/// widgets, and removes the `packages/features/auth` package directory.
///
/// Phase 1 computes every rewrite in memory (throwing on a malformed marker)
/// before any file is written, so a bad marker aborts cleanly.
///
/// Idempotent: re-running on an already-stripped tree is a no-op.
Future<void> disableAuth(String projectDir) async {
  // Phase 1: compute every rewrite in memory.
  final pending = <File, String>{};
  for (final relative in _authWiringFiles) {
    final file = File(p.join(projectDir, p.joinAll(relative.split('/'))));
    if (!file.existsSync()) continue;
    final original = file.readAsStringSync();
    final rewritten = removeAuthRegions(original);
    if (rewritten == original) continue;
    // Normalise to exactly one trailing newline (matches the eol_at_end_of_file
    // lint and mirrors the same normalisation in features.dart).
    pending[file] = '${rewritten.trimRight()}\n';
  }

  // Phase 2: all rewrites computed cleanly — commit them.
  pending.forEach((file, content) => file.writeAsStringSync(content));

  // Phase 3: delete auth-only part files (their part directives are now gone).
  for (final relative in _authOnlyPartFiles) {
    final file = File(p.join(projectDir, p.joinAll(relative.split('/'))));
    if (file.existsSync()) file.deleteSync();
  }

  // Phase 4: delete the auth feature package directory.
  final authDir = Directory(
    p.join(projectDir, 'packages', 'features', 'auth'),
  );
  if (authDir.existsSync()) authDir.deleteSync(recursive: true);
}
