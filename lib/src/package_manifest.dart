import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package_spec.dart';

const packageManifestName = '.fst-package.json';
const packageManifestVersion = 1;

final class PackageManifest {
  const PackageManifest({
    required this.name,
    required this.type,
    required this.dependencies,
    required this.ownedFiles,
  });

  final String name;
  final ReusablePackageType type;
  final List<String> dependencies;
  final List<String> ownedFiles;

  Map<String, Object> toJson() => {
        'schemaVersion': packageManifestVersion,
        'generator': 'fst',
        'name': name,
        'type': type.name,
        'dependencies': dependencies,
        'ownedFiles': ownedFiles,
      };

  static PackageManifest fromJson(Object? value) {
    if (value is! Map<String, Object?> ||
        value['schemaVersion'] != packageManifestVersion ||
        value['generator'] != 'fst' ||
        value['name'] is! String ||
        value['type'] is! String ||
        value['dependencies'] is! List ||
        value['ownedFiles'] is! List) {
      throw const FormatException('Unsupported or malformed package manifest.');
    }
    return PackageManifest(
      name: value['name']! as String,
      type: ReusablePackageType.parse(value['type']! as String),
      dependencies: List<String>.from(value['dependencies']! as List),
      ownedFiles: List<String>.from(value['ownedFiles']! as List),
    );
  }
}

PackageManifest? readPackageManifest(String packageDirectory) {
  final file = File(p.join(packageDirectory, packageManifestName));
  if (!file.existsSync()) return null;
  return PackageManifest.fromJson(jsonDecode(file.readAsStringSync()));
}

void writePackageManifest(String packageDirectory, PackageManifest manifest) {
  final file = File(p.join(packageDirectory, packageManifestName));
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(manifest.toJson())}\n',
  );
}
