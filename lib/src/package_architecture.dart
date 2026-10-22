import 'dart:io';

import 'package:path/path.dart' as p;

import 'package_manifest.dart';
import 'package_spec.dart';

final class WorkspacePackage {
  const WorkspacePackage({
    required this.name,
    required this.directory,
    required this.dependencies,
    required this.devDependencies,
    required this.type,
    required this.manifest,
  });

  final String name;
  final String directory;
  final Set<String> dependencies;
  final Set<String> devDependencies;
  final ReusablePackageType? type;
  final PackageManifest? manifest;
}

final class PackageValidationResult {
  const PackageValidationResult(this.package, this.issues);

  final WorkspacePackage? package;
  final List<String> issues;
  bool get isValid => package != null && issues.isEmpty;
}

Map<String, WorkspacePackage> discoverWorkspacePackages(String root) {
  final packageDirs = <Directory>[];
  final packages = Directory(p.join(root, 'packages'));
  if (packages.existsSync()) {
    for (final entity
        in packages.listSync(recursive: true, followLinks: false)) {
      if (entity is File && p.basename(entity.path) == 'pubspec.yaml') {
        packageDirs.add(entity.parent);
      }
    }
  }
  final revSync = Directory(p.join(root, 'published', 'rev_sync'));
  if (File(p.join(revSync.path, 'pubspec.yaml')).existsSync()) {
    packageDirs.add(revSync);
  }

  final discovered = <String, WorkspacePackage>{};
  for (final directory in packageDirs) {
    final source =
        File(p.join(directory.path, 'pubspec.yaml')).readAsStringSync();
    final name = parsePubspecName(source);
    if (name == null) continue;
    PackageManifest? manifest;
    try {
      manifest = readPackageManifest(directory.path);
    } on Object {
      // The validator reports the actionable manifest error for its target.
    }
    discovered[name] = WorkspacePackage(
      name: name,
      directory: directory.path,
      dependencies: parsePubspecDependencies(source),
      devDependencies: parsePubspecDevDependencies(source),
      type: manifest?.type ?? knownWorkspacePackageTypes[name],
      manifest: manifest,
    );
  }
  return discovered;
}

PackageValidationResult validateWorkspacePackage(String root, String name) {
  final issues = <String>[];
  final packages = discoverWorkspacePackages(root);
  final package = packages[name];
  if (package == null) {
    return PackageValidationResult(null, ['Unknown workspace package: $name']);
  }

  PackageManifest? manifest;
  try {
    manifest = readPackageManifest(package.directory);
  } on Object catch (error) {
    issues.add('$name has invalid $packageManifestName: $error');
  }
  if (manifest != null) {
    if (manifest.name != name) {
      issues.add('$packageManifestName name does not match $name');
    }
    for (final relative in manifest.ownedFiles) {
      if (!File(p.join(package.directory, p.joinAll(relative.split('/'))))
          .existsSync()) {
        issues.add('$name is missing generated file $relative');
      }
    }
    final manifestDeps = manifest.dependencies.toSet();
    final actualWorkspaceDeps =
        package.dependencies.intersection(packages.keys.toSet());
    if (manifestDeps.difference(actualWorkspaceDeps).isNotEmpty) {
      issues.add('$name pubspec is missing manifest dependencies: '
          '${manifestDeps.difference(actualWorkspaceDeps).join(', ')}');
    }
  }

  final rootPubspec = File(p.join(root, 'pubspec.yaml')).readAsStringSync();
  final relative = p.posix.joinAll(
    p.split(p.relative(package.directory, from: root)),
  );
  if (!rootPubspec.split('\n').any((line) => line.trim() == '- $relative')) {
    issues.add('$name is not registered in the root Pub Workspace');
  }

  final barrel = File(p.join(package.directory, 'lib', '$name.dart'));
  if (!barrel.existsSync()) {
    issues.add('$name is missing public entrypoint lib/$name.dart');
  } else {
    _validateDirectives(package, barrel, issues, isBarrel: true);
  }
  final lib = Directory(p.join(package.directory, 'lib'));
  if (lib.existsSync()) {
    for (final entity in lib.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path != barrel.path) {
        final relativeLib = p.relative(entity.path, from: lib.path);
        if (!relativeLib.startsWith('src${p.separator}')) {
          issues.add('$name exposes non-entrypoint Dart file lib/$relativeLib');
        }
      }
      _validateDirectives(package, entity, issues,
          isBarrel: entity.path == barrel.path);
    }
  }

  final testDir = Directory(p.join(package.directory, 'test'));
  if (!testDir.existsSync() ||
      !testDir
          .listSync(recursive: true)
          .whereType<File>()
          .any((file) => file.path.endsWith('_test.dart'))) {
    issues.add('$name must contain at least one test/*_test.dart');
  }

  final rootName = parsePubspecName(rootPubspec);
  if (rootName != null && package.dependencies.contains(rootName)) {
    issues.add('$name cannot depend on application shell package $rootName');
  }
  if (package.type != ReusablePackageType.dev &&
      package.dependencies.contains('test_utils')) {
    issues.add('$name cannot use test_utils as a runtime dependency');
  }
  for (final dependency in package.dependencies) {
    final target = packages[dependency];
    if (target == null) continue;
    if (dependency.startsWith('feature_')) {
      issues.add('$name cannot depend on feature implementation $dependency');
      continue;
    }
    if (package.type != null &&
        target.type != null &&
        !isAllowedPackageDependency(package.type!, target.type!)) {
      issues.add('$name (${package.type!.name}) cannot depend on '
          '$dependency (${target.type!.name})');
    }
  }

  final cycles = detectWorkspaceDependencyCycles(packages);
  for (final cycle
      in cycles.where((cycle) => cycle.split(' -> ').contains(name))) {
    issues.add('Circular workspace dependency: $cycle');
  }
  return PackageValidationResult(package, issues.toSet().toList()..sort());
}

void _validateDirectives(
  WorkspacePackage package,
  File file,
  List<String> issues, {
  required bool isBarrel,
}) {
  final directive = RegExp(r'''^\s*(import|export)\s+['"]([^'"]+)['"]''');
  final lines = file.readAsLinesSync();
  for (var index = 0; index < lines.length; index++) {
    final match = directive.firstMatch(lines[index]);
    if (match == null) continue;
    final uri = match.group(2)!;
    final packageUri = RegExp(r'^package:([^/]+)/(.+)$').firstMatch(uri);
    if (packageUri != null &&
        packageUri.group(1) != package.name &&
        packageUri.group(2)!.startsWith('src/')) {
      issues.add('${package.name} imports private API at '
          '${p.relative(file.path, from: package.directory)}:${index + 1}: $uri');
    }
    if (isBarrel &&
        match.group(1) == 'export' &&
        (uri.startsWith('package:firebase_') ||
            uri.startsWith('package:shared_preferences/') ||
            uri.startsWith('package:flutter_secure_storage/'))) {
      issues
          .add('${package.name} public entrypoint leaks third-party SDK $uri');
    }
    if (package.type == ReusablePackageType.contracts &&
        (uri.startsWith('package:flutter/') ||
            uri.startsWith('package:app_ui/') ||
            uri.startsWith('package:localization/') ||
            uri.startsWith('package:go_router/') ||
            uri.startsWith('package:flutter_bloc/'))) {
      issues.add('${package.name} contracts package imports UI library $uri');
    }
  }
}

List<String> detectWorkspaceDependencyCycles(
  Map<String, WorkspacePackage> packages,
) {
  final cycles = <String>{};
  final visited = <String>{};
  final stack = <String>[];
  final active = <String>{};

  void visit(String name) {
    if (active.contains(name)) {
      final start = stack.indexOf(name);
      cycles.add([...stack.sublist(start), name].join(' -> '));
      return;
    }
    if (!visited.add(name)) return;
    active.add(name);
    stack.add(name);
    for (final dependency
        in packages[name]!.dependencies.where(packages.containsKey)) {
      visit(dependency);
    }
    stack.removeLast();
    active.remove(name);
  }

  for (final name in packages.keys) {
    visit(name);
  }
  return cycles.toList()..sort();
}

String? parsePubspecName(String source) => RegExp(
      r'^name:\s*([a-zA-Z0-9_]+)\s*$',
      multiLine: true,
    ).firstMatch(source)?.group(1);

Set<String> parsePubspecDependencies(String source) {
  return _parsePubspecDependencySection(source, 'dependencies');
}

Set<String> parsePubspecDevDependencies(String source) {
  return _parsePubspecDependencySection(source, 'dev_dependencies');
}

Set<String> _parsePubspecDependencySection(String source, String section) {
  final dependencies = <String>{};
  var inDependencies = false;
  for (final line in source.split('\n')) {
    if (line.trimRight() == '$section:') {
      inDependencies = true;
      continue;
    }
    if (inDependencies && line.isNotEmpty && !line.startsWith(' ')) break;
    if (!inDependencies) continue;
    final match = RegExp(r'^  ([a-zA-Z][a-zA-Z0-9_]*):').firstMatch(line);
    if (match != null) dependencies.add(match.group(1)!);
  }
  return dependencies;
}
