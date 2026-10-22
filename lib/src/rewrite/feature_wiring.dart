import 'dart:io';

import 'package:path/path.dart' as p;

import '../feature_names.dart';

/// Thrown when a wiring file is missing a `// fst:` sentinel marker, so the
/// command can report which file to fix instead of silently producing a
/// half-wired project.
class FeatureWiringException implements Exception {
  FeatureWiringException(this.message);
  final String message;
  @override
  String toString() => 'FeatureWiringException: $message';
}

/// Validates an absolute, static feature route such as `/settings` or
/// `/admin/audit-log`.
String validateFeatureRoutePath(String value) {
  final path = value.trim();
  final valid = RegExp(
    r'^/[a-z0-9]+(?:-[a-z0-9]+)*(?:/[a-z0-9]+(?:-[a-z0-9]+)*)*$',
  );
  if (!valid.hasMatch(path)) {
    throw FeatureWiringException(
      'Invalid route path "$value". Use an absolute static path made of '
      'lowercase kebab-case segments, for example /admin/audit-log.',
    );
  }
  return path;
}

/// Rejects root-path and route-name collisions before any project file changes.
void validateFeatureRouteAvailability(
  String root,
  FeatureNames names,
  String routePath,
) {
  final values = <String, String>{};
  final sourceRoots = <Directory>[
    Directory(p.join(root, 'lib')),
    Directory(p.join(root, 'packages', 'features')),
  ];

  final declaration = RegExp(
    r'''(?:path|name)\s*:\s*['"]([^'"]+)['"]|'''
    r'''static\s+const\s+\w+\s*=\s*['"]([^'"]+)['"]''',
  );
  for (final sourceRoot in sourceRoots) {
    if (!sourceRoot.existsSync()) continue;
    for (final entity
        in sourceRoot.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final basename = p.basename(entity.path);
      if (!basename.contains('route') && !basename.contains('router')) continue;
      final content = entity.readAsStringSync();
      for (final match in declaration.allMatches(content)) {
        final value = match.group(1) ?? match.group(2)!;
        values.putIfAbsent(value, () => p.relative(entity.path, from: root));
      }
    }
  }

  for (final candidate in <String>[
    routePath,
    names.routeName,
    names.detailsRouteName
  ]) {
    final owner = values[candidate];
    if (owner != null) {
      throw FeatureWiringException(
        'Route collision: "$candidate" is already declared in $owner.',
      );
    }
  }
}

/// Inserts the new feature into the root `pubspec.yaml`: its `workspace:` entry
/// and its `feature_<name>` dependency.
String addFeatureToPubspec(String content, FeatureNames n) {
  var out = _insertBeforeMarker(
    content,
    'fst:features',
    '  - packages/features/${n.snake}',
  );
  out = _insertBeforeMarker(out, 'fst:feature-deps', '  ${n.package}: ^0.1.0');
  return out;
}

/// Inserts the feature's package import and its `ExternalModule(...)` entry into
/// `lib/app/di/injection.dart`. The module is appended after the existing
/// feature modules — i.e. after `FeatureAuthPackageModule`, preserving the
/// auth-before-other-features ordering the DI guard enforces.
String addFeatureToInjection(String content, FeatureNames n) {
  var out = _insertPackageImport(content, n);
  out = _insertBeforeMarker(
    out,
    'fst:feature-modules',
    '    ExternalModule(${n.packageModule}),',
  );
  return out;
}

/// Inserts the feature's package import, its `enabledFeatures` entry, and its
/// `_<Name>Module` class into `lib/app/features.dart`.
String addFeatureToFeatures(String content, FeatureNames n) {
  var out = _insertImport(
    content,
    "import 'package:go_router/go_router.dart';",
  );
  out = _insertPackageImport(out, n);
  out = _insertBeforeMarker(
    out,
    'fst:enabled-features',
    '  _${n.pascal}Module(),',
  );
  out = _insertBeforeMarker(
    out,
    'fst:feature-module-classes',
    '${_module(n)}\n',
  );
  return out;
}

/// Registers a generated feature in the workspace layering guardrail.
String addFeatureToLayeringTest(String content, FeatureNames n) =>
    _insertBeforeMarker(
      content,
      'fst:feature-layers',
      "  '${n.package}': 4,",
    );

/// Removes only the exact registration lines emitted by [addFeatureToPubspec].
String removeFeatureFromPubspec(String content, FeatureNames n) =>
    _removeExactLines(content, [
      '  - packages/features/${n.snake}',
      '  ${n.package}: ^0.1.0',
    ]);

/// Removes only the exact import and module registration emitted by the CLI.
String removeFeatureFromInjection(String content, FeatureNames n) =>
    _removeExactLines(content, [
      "import 'package:${n.package}/${n.package}.dart';",
      '    ExternalModule(${n.packageModule}),',
    ]);

/// Removes the generated import, enabled entry, and exact module class block.
String removeFeatureFromFeatures(String content, FeatureNames n) {
  final withoutLines = _removeExactLines(content, [
    "import 'package:${n.package}/${n.package}.dart';",
    '  _${n.pascal}Module(),',
  ]);
  final withoutCurrent = _removeExactBlock(withoutLines, _module(n));
  if (withoutCurrent != withoutLines) return withoutCurrent;
  return _removeExactBlock(withoutLines, _legacyModule(n));
}

/// Removes only the generated architecture-layer declaration.
String removeFeatureFromLayeringTest(String content, FeatureNames n) =>
    _removeExactLines(content, ["  '${n.package}': 4,"]);

String _module(FeatureNames n) => '''
final class _${n.pascal}Module extends FeatureModule {
  const _${n.pascal}Module();

  @override
  String get id => '${n.snake}';

  @override
  Iterable<RouteBase> get routes => ${n.camel}Routes;
}''';

String _legacyModule(FeatureNames n) => '''
final class _${n.pascal}Module extends FeatureModule {
  const _${n.pascal}Module();

  @override
  Iterable<RouteBase> get routes => ${n.camel}Routes;
}''';

/// Inserts `import 'package:<pkg>/<pkg>.dart';` in alphabetical position among
/// the existing `package:` imports, satisfying `directives_ordering`. No-op if
/// the import is already present.
String _insertPackageImport(String content, FeatureNames n) {
  final line = "import 'package:${n.package}/${n.package}.dart';";
  return _insertImport(content, line);
}

String _insertImport(String content, String line) {
  if (content.contains(line)) return content;

  final lines = content.split('\n');
  final importIndices = <int>[
    for (var i = 0; i < lines.length; i++)
      if (lines[i].startsWith("import 'package:")) i,
  ];
  if (importIndices.isEmpty) {
    final firstImport = lines.indexWhere((line) => line.startsWith('import '));
    final insertAt = firstImport == -1 ? 0 : firstImport;
    lines.insert(insertAt, line);
    return lines.join('\n');
  }
  final after = importIndices.firstWhere(
    (i) => lines[i].compareTo(line) > 0,
    orElse: () => -1,
  );
  final insertAt = after == -1 ? importIndices.last + 1 : after;
  lines.insert(insertAt, line);
  return lines.join('\n');
}

String _removeExactLines(String content, List<String> removed) {
  final targets = removed.toSet();
  return content
      .split('\n')
      .where((line) => !targets.contains(line))
      .join('\n');
}

String _removeExactBlock(String content, String block) {
  final lines = content.split('\n');
  final blockLines = block.split('\n');
  for (var start = 0; start <= lines.length - blockLines.length; start++) {
    var matches = true;
    for (var offset = 0; offset < blockLines.length; offset++) {
      if (lines[start + offset] != blockLines[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      lines.removeRange(start, start + blockLines.length);
      if (start < lines.length && lines[start].isEmpty) lines.removeAt(start);
      break;
    }
  }
  return lines.join('\n');
}

/// Inserts [text] (one or more lines, no trailing newline) immediately before
/// the line containing [markerToken].
String _insertBeforeMarker(String content, String markerToken, String text) {
  if (content.split('\n').join('\n').contains(text)) return content;
  final lines = content.split('\n');
  final markerIndex = lines.indexWhere((l) => l.contains(markerToken));
  if (markerIndex == -1) {
    throw FeatureWiringException(
      'Marker "$markerToken" not found. Add it back so `fst add-feature` '
      'knows where to insert, then retry.',
    );
  }
  lines.insertAll(markerIndex, text.split('\n'));
  return lines.join('\n');
}
