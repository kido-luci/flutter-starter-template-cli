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

/// Inserts the new feature into the root `pubspec.yaml`: its `workspace:` entry
/// and its `feature_<name>` dependency.
String addFeatureToPubspec(String content, FeatureNames n) {
  var out = _insertBeforeMarker(
    content,
    'fst:features',
    '  - packages/features/${n.snake}',
  );
  out = _insertBeforeMarker(
    out,
    'fst:feature-deps',
    '  ${n.package}: ^0.1.0',
  );
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
  var out = _insertPackageImport(content, n);
  out = _insertBeforeMarker(
    out,
    'fst:enabled-features',
    '  _${n.pascal}Module(),',
  );
  out =
      _insertBeforeMarker(out, 'fst:feature-module-classes', '${_module(n)}\n');
  return out;
}

String _module(FeatureNames n) => '''
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
  if (content.contains(line)) return content;

  final lines = content.split('\n');
  final importIndices = <int>[
    for (var i = 0; i < lines.length; i++)
      if (lines[i].startsWith("import 'package:")) i,
  ];
  if (importIndices.isEmpty) {
    throw FeatureWiringException('No package imports found to anchor against.');
  }
  final after = importIndices.firstWhere(
    (i) => lines[i].compareTo(line) > 0,
    orElse: () => -1,
  );
  final insertAt = after == -1 ? importIndices.last + 1 : after;
  lines.insert(insertAt, line);
  return lines.join('\n');
}

/// Inserts [text] (one or more lines, no trailing newline) immediately before
/// the line containing [markerToken].
String _insertBeforeMarker(String content, String markerToken, String text) {
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
