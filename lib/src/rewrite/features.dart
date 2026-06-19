import 'dart:io';

import 'package:path/path.dart' as p;

/// The demo content features `fst create` can exclude at scaffold time.
///
/// `auth`, `home`, `profile`, and `splash` are core (session, redirects, shell,
/// startup) and are never removable.
const removableFeatures = {'bookmarks', 'collections', 'notifications'};

/// Expands an excluded-feature set with forced dependencies.
///
/// `feature_bookmarks` imports `feature_collections`, so excluding
/// `collections` also excludes `bookmarks`.
Set<String> expandExcludedFeatures(Set<String> excluded) {
  final result = {...excluded};
  if (result.contains('collections')) result.add('bookmarks');
  return result;
}

/// Removes every `fst:feature:<feature>:start` … `fst:feature:<feature>:end`
/// block (inclusive) from [content].
///
/// Comment style agnostic (`//` for Dart, `#` for YAML). Idempotent, and leaves
/// other features' blocks and unrelated lines untouched.
String removeFeatureRegions(String content, String feature) {
  final startNeedle = 'fst:feature:$feature:start';
  final endNeedle = 'fst:feature:$feature:end';
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
  return kept.join('\n');
}

/// App-shell wiring + test files that carry `fst:feature:*` regions.
const _wiringFiles = [
  'pubspec.yaml',
  'lib/app/di/injection.dart',
  'lib/app/features.dart',
  'lib/app/router.dart',
  'lib/app/widgets/app_shell.dart',
  'lib/app/app.dart',
  'test/widget_test.dart',
  'test/test_utils/mocks.dart',
  'test/architecture/di_module_ordering_test.dart',
  'test/architecture/package_layering_test.dart',
  'test/architecture/feature_boundaries_test.dart',
];

/// Excises every [features] feature from [projectDir]: strips their
/// `fst:feature:*` regions from the wiring files and deletes their packages.
///
/// Dependencies are the caller's responsibility — pass an already-expanded set
/// (see [expandExcludedFeatures]).
Future<void> excludeFeatures(String projectDir, Set<String> features) async {
  if (features.isEmpty) return;

  // When every removable feature is gone, `enabledFeatures` is empty — also
  // strip the now-orphaned module infrastructure (marked `fst:feature:_infra`)
  // so the trimmed project has no unused imports/declarations.
  final stripInfra = removableFeatures.difference(features).isEmpty;

  for (final relative in _wiringFiles) {
    final file = File(p.join(projectDir, p.joinAll(relative.split('/'))));
    if (!file.existsSync()) continue;
    var content = file.readAsStringSync();
    for (final feature in features) {
      content = removeFeatureRegions(content, feature);
    }
    if (stripInfra) content = removeFeatureRegions(content, '_infra');
    file.writeAsStringSync(content);
  }

  for (final feature in features) {
    final dir = Directory(
      p.join(projectDir, 'packages', 'features', feature),
    );
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}
