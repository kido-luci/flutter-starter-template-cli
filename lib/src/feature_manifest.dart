import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'feature_names.dart';
import 'rewrite/feature_template.dart';

const featureManifestName = '.fst-feature.json';

final class FeatureManifest {
  const FeatureManifest({
    required this.id,
    required this.package,
    required this.source,
    required this.routePath,
    required this.routeNames,
    required this.generatedFiles,
  });

  factory FeatureManifest.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported feature manifest version.');
    }
    return FeatureManifest(
      id: json['id']! as String,
      package: json['package']! as String,
      source: FeatureSource.values.byName(json['source']! as String),
      routePath: json['routePath']! as String,
      routeNames: (json['routeNames']! as List<Object?>).cast<String>(),
      generatedFiles: (json['generatedFiles']! as Map<String, Object?>)
          .map((key, value) => MapEntry(key, value! as String)),
    );
  }

  final String id;
  final String package;
  final FeatureSource source;
  final String routePath;
  final List<String> routeNames;
  final Map<String, String> generatedFiles;

  Map<String, Object?> toJson() => {
        'schemaVersion': 1,
        'id': id,
        'package': package,
        'source': source.name,
        'routePath': routePath,
        'routeNames': routeNames,
        'generatedFiles': generatedFiles,
      };
}

void writeFeatureManifest(
  String featureDirectory, {
  required FeatureNames names,
  required FeatureSource source,
  required String routePath,
}) {
  final scaffold = featureFiles(names, source: source, routePath: routePath);
  final manifest = FeatureManifest(
    id: names.snake,
    package: names.package,
    source: source,
    routePath: routePath,
    routeNames: [names.routeName, names.detailsRouteName],
    generatedFiles: {
      for (final entry in scaffold.entries)
        entry.key: featureContentFingerprint(utf8.encode(entry.value)),
    },
  );
  final encoder = const JsonEncoder.withIndent('  ');
  File(p.join(featureDirectory, featureManifestName)).writeAsStringSync(
    '${encoder.convert(manifest.toJson())}\n',
    flush: true,
  );
}

FeatureManifest? readFeatureManifest(String featureDirectory) {
  final file = File(p.join(featureDirectory, featureManifestName));
  if (!file.existsSync()) return null;
  final json = jsonDecode(file.readAsStringSync());
  if (json is! Map<String, Object?>) {
    throw const FormatException('Feature manifest must be a JSON object.');
  }
  return FeatureManifest.fromJson(json);
}

String featureContentFingerprint(List<int> bytes) {
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
