import '../package_spec.dart';

final class PackageWiringException implements Exception {
  const PackageWiringException(this.message);
  final String message;
  @override
  String toString() => 'PackageWiringException: $message';
}

String registerWorkspacePackage(String content, String name) =>
    _insertBeforeMarker(
      content,
      'fst:packages',
      '  - packages/$name',
    );

String registerPackageCategory(
  String content,
  String name,
  ReusablePackageType type,
) =>
    _insertBeforeMarker(
      content,
      'fst:package-categories',
      "  '$name': PackageCategory.${type.architectureCategory},",
    );

String registerPackageLayer(String content, String name, int layer) =>
    _insertBeforeMarker(
      content,
      'fst:package-layers',
      "  '$name': $layer,",
    );

String unregisterWorkspacePackage(String content, String name) =>
    _removeExactLine(
      content,
      '  - packages/$name',
      marker: 'fst:packages',
    );

String unregisterPackageCategory(String content, String name) =>
    _removeMatchingLine(
      content,
      RegExp(
        "^\\s*'${RegExp.escape(name)}':"
        r'\s*PackageCategory\.[A-Za-z0-9_]+,\s*$',
      ),
      marker: 'fst:package-categories',
      description: 'package category for $name',
    );

String unregisterPackageLayer(String content, String name) =>
    _removeMatchingLine(
      content,
      RegExp("^\\s*'${RegExp.escape(name)}':" r'\s*\d+,\s*$'),
      marker: 'fst:package-layers',
      description: 'package layer for $name',
    );

Map<String, int> parseArchitectureLayers(String content) => {
      for (final match in RegExp(
        r"^\s*'([a-zA-Z0-9_]+)':\s*(\d+),",
        multiLine: true,
      ).allMatches(content))
        match.group(1)!: int.parse(match.group(2)!),
    };

String _insertBeforeMarker(String content, String marker, String line) {
  if (content.split('\n').contains(line)) return content;
  final lines = content.split('\n');
  final index = lines.indexWhere((candidate) => candidate.contains(marker));
  if (index == -1) {
    throw PackageWiringException(
      'Missing // $marker marker required for safe package registration.',
    );
  }
  lines.insert(index, line);
  return lines.join('\n');
}

String _removeExactLine(
  String content,
  String line, {
  required String marker,
}) =>
    _removeMatchingLine(
      content,
      RegExp('^${RegExp.escape(line)}' r'$'),
      marker: marker,
      description: line.trim(),
    );

String _removeMatchingLine(
  String content,
  RegExp pattern, {
  required String marker,
  required String description,
}) {
  final lines = content.split('\n');
  if (!lines.any((line) => line.contains(marker))) {
    throw PackageWiringException(
      'Missing // $marker marker required for safe package removal.',
    );
  }
  final matches = <int>[
    for (var index = 0; index < lines.length; index++)
      if (pattern.hasMatch(lines[index])) index,
  ];
  if (matches.length != 1) {
    throw PackageWiringException(
      'Expected exactly one $description registration; found ${matches.length}.',
    );
  }
  lines.removeAt(matches.single);
  return lines.join('\n');
}
