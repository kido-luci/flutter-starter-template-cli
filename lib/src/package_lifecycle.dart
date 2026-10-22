import 'dart:io';

import 'package:path/path.dart' as p;

import 'feature_discovery.dart';
import 'package_architecture.dart';
import 'package_manifest.dart';
import 'package_spec.dart';
import 'rewrite/package_template.dart';

enum PackageOwnership { cli, legacy, manual, invalid }

final class DiscoveredPackage {
  const DiscoveredPackage({
    required this.package,
    required this.location,
    required this.ownership,
    required this.registered,
    required this.core,
    required this.modifiedFiles,
    required this.unknownFiles,
    required this.validationIssues,
    required this.manifestError,
  });

  final WorkspacePackage package;
  final String location;
  final PackageOwnership ownership;
  final bool registered;
  final bool core;
  final List<String> modifiedFiles;
  final List<String> unknownFiles;
  final List<String> validationIssues;
  final String? manifestError;

  bool get owned => ownership == PackageOwnership.cli;
  bool get hasUserChanges =>
      modifiedFiles.isNotEmpty || unknownFiles.isNotEmpty;
  bool get valid => validationIssues.isEmpty && manifestError == null;
}

final class PackageInventory {
  const PackageInventory({
    required this.root,
    required this.packages,
    required this.applicationName,
    required this.applicationDependencies,
    required this.issues,
  });

  final String root;
  final List<DiscoveredPackage> packages;
  final String? applicationName;
  final Set<String> applicationDependencies;
  final List<String> issues;

  DiscoveredPackage? find(String name) {
    for (final package in packages) {
      if (package.package.name == name) return package;
    }
    return null;
  }

  Map<String, Set<String>> get dependencyGraph => {
        for (final item in packages)
          item.package.name: {
            ...item.package.dependencies,
            ...item.package.devDependencies,
          },
        if (applicationName case final name?) name: applicationDependencies,
      };

  List<String> directConsumers(String target) {
    final consumers = <String>[
      for (final entry in dependencyGraph.entries)
        if (entry.key != target && entry.value.contains(target)) entry.key,
    ]..sort();
    return consumers;
  }

  List<String> transitiveConsumers(String target) {
    final direct = directConsumers(target).toSet();
    final result = <String>{};
    final pending = [...direct];
    while (pending.isNotEmpty) {
      final dependency = pending.removeLast();
      for (final entry in dependencyGraph.entries) {
        if (entry.key == target ||
            direct.contains(entry.key) ||
            result.contains(entry.key) ||
            !entry.value.contains(dependency)) {
          continue;
        }
        result.add(entry.key);
        pending.add(entry.key);
      }
    }
    return result.toList()..sort();
  }
}

PackageInventory discoverPackages(String root) {
  final rootPubspec = File(p.join(root, 'pubspec.yaml'));
  if (!rootPubspec.existsSync()) {
    return PackageInventory(
      root: root,
      packages: const [],
      applicationName: null,
      applicationDependencies: const {},
      issues: const ['Missing root pubspec.yaml.'],
    );
  }
  final rootSource = rootPubspec.readAsStringSync();
  final registrations = parseWorkspaceRegistrations(rootSource);
  final workspacePackages = discoverWorkspacePackages(root);
  final features = {
    for (final feature in discoverFeatures(root).features)
      feature.package: feature,
  };
  final items = <DiscoveredPackage>[];
  final issues = <String>[];

  for (final workspacePackage in workspacePackages.values) {
    final location = _posixRelative(workspacePackage.directory, root);
    PackageManifest? manifest;
    String? manifestError;
    try {
      manifest = readPackageManifest(workspacePackage.directory);
      if (manifest != null) {
        _validateOwnershipManifest(workspacePackage, manifest);
      }
    } on Object catch (error) {
      manifestError = '$error';
      issues.add(
        '${workspacePackage.name} has broken ownership manifest: $error',
      );
    }

    final feature = features[workspacePackage.name];
    if (feature?.manifestError != null) {
      manifestError = feature!.manifestError;
      issues.add('${workspacePackage.name} has broken feature ownership '
          'manifest: ${feature.manifestError}');
    }
    final ownership = manifestError != null
        ? PackageOwnership.invalid
        : manifest != null
            ? PackageOwnership.cli
            : feature != null
                ? switch (feature.ownership) {
                    FeatureOwnership.manifest => PackageOwnership.cli,
                    FeatureOwnership.legacy => PackageOwnership.legacy,
                    FeatureOwnership.unowned => PackageOwnership.manual,
                  }
                : _isLegacy(workspacePackage)
                    ? PackageOwnership.legacy
                    : PackageOwnership.manual;
    final changes = manifest == null || manifestError != null
        ? const (<String>[], <String>[])
        : _packageChanges(workspacePackage, manifest);
    final validation = validateWorkspacePackage(root, workspacePackage.name);
    items.add(
      DiscoveredPackage(
        package: workspacePackage,
        location: location,
        ownership: ownership,
        registered: registrations.contains(location),
        core: _isCore(workspacePackage.name, location),
        modifiedFiles: changes.$1,
        unknownFiles: changes.$2,
        validationIssues: validation.issues,
        manifestError: manifestError,
      ),
    );
  }
  items.sort((a, b) => a.package.name.compareTo(b.package.name));

  for (final registration in registrations) {
    final directory = Directory(
      p.join(root, p.joinAll(registration.split('/'))),
    );
    if (!File(p.join(directory.path, 'pubspec.yaml')).existsSync()) {
      issues.add('Workspace registration references missing package: '
          '$registration');
    }
  }
  final registeredNames = {
    for (final registration in registrations)
      _packageNameForRegistration(registration): registration,
  };
  final dependencyGraph = <String, Set<String>>{
    for (final item in items)
      item.package.name: {
        ...item.package.dependencies,
        ...item.package.devDependencies,
      },
    if (parsePubspecName(rootSource) case final rootName?)
      rootName: {
        ...parsePubspecDependencies(rootSource),
        ...parsePubspecDevDependencies(rootSource),
      },
  };
  for (final entry in dependencyGraph.entries) {
    for (final dependency in entry.value) {
      if (registeredNames.containsKey(dependency) &&
          !workspacePackages.containsKey(dependency)) {
        issues.add('${entry.key} has dangling workspace dependency '
            '$dependency (${registeredNames[dependency]})');
      }
    }
  }
  _validatePathDependencies(rootPubspec, rootSource, root, issues);
  for (final item in items) {
    final pubspec = File(p.join(item.package.directory, 'pubspec.yaml'));
    _validatePathDependencies(
      pubspec,
      pubspec.readAsStringSync(),
      root,
      issues,
    );
  }
  final locations = items.map((item) => item.location).toSet();
  for (final location in locations) {
    if (location.startsWith('packages/') && !registrations.contains(location)) {
      issues.add('Package directory is not registered in workspace: $location');
    }
  }
  final duplicates = _duplicatePackageNames(root);
  for (final entry in duplicates.entries) {
    issues
        .add('Duplicate package name ${entry.key}: ${entry.value.join(', ')}');
  }
  for (final cycle in detectWorkspaceDependencyCycles(workspacePackages)) {
    issues.add('Circular workspace dependency: $cycle');
  }

  return PackageInventory(
    root: root,
    packages: items,
    applicationName: parsePubspecName(rootSource),
    applicationDependencies: {
      ...parsePubspecDependencies(rootSource),
      ...parsePubspecDevDependencies(rootSource),
    },
    issues: issues.toSet().toList()..sort(),
  );
}

void _validateOwnershipManifest(
  WorkspacePackage package,
  PackageManifest manifest,
) {
  if (manifest.name != package.name) {
    throw const FormatException('Manifest name does not match pubspec name.');
  }
  final expected = reusablePackageFiles(
    name: manifest.name,
    type: manifest.type,
    dependencies: [...manifest.dependencies]..sort(),
  ).keys.toSet();
  final owned = manifest.ownedFiles.toSet();
  if (owned.length != manifest.ownedFiles.length ||
      owned.difference(expected).isNotEmpty ||
      expected.difference(owned).isNotEmpty) {
    throw const FormatException(
      'Owned file list does not match the generated package contract.',
    );
  }
  for (final relative in owned) {
    final normalized = p.posix.normalize(relative);
    if (normalized == '.' ||
        normalized.startsWith('../') ||
        p.posix.isAbsolute(normalized)) {
      throw const FormatException('Owned file path escapes package root.');
    }
  }
}

(List<String>, List<String>) _packageChanges(
  WorkspacePackage package,
  PackageManifest manifest,
) {
  final expected = reusablePackageFiles(
    name: manifest.name,
    type: manifest.type,
    dependencies: [...manifest.dependencies]..sort(),
  );
  final modified = <String>[];
  for (final entry in expected.entries) {
    final file = File(
      p.join(package.directory, p.joinAll(entry.key.split('/'))),
    );
    if (!file.existsSync() || file.readAsStringSync() != entry.value) {
      modified.add(entry.key);
    }
  }
  final known = {...expected.keys, packageManifestName};
  final unknown = <String>[];
  for (final entity in Directory(package.directory)
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()) {
    final relative = _posixRelative(entity.path, package.directory);
    final first = relative.split('/').first;
    if (first == '.dart_tool' ||
        first == 'build' ||
        relative == 'pubspec.lock') {
      continue;
    }
    if (!known.contains(relative)) unknown.add(relative);
  }
  modified.sort();
  unknown.sort();
  return (modified, unknown);
}

bool _isLegacy(WorkspacePackage package) =>
    knownWorkspacePackageTypes.containsKey(package.name);

bool _isCore(String name, String location) =>
    knownWorkspacePackageTypes.containsKey(name) ||
    location.startsWith('packages/features/') ||
    location.startsWith('published/');

String _posixRelative(String path, String root) =>
    p.posix.joinAll(p.split(p.relative(path, from: root)));

Set<String> parseWorkspaceRegistrations(String source) => {
      for (final match in RegExp(
        r'^\s*-\s+([^#\s]+)\s*(?:#.*)?$',
        multiLine: true,
      ).allMatches(_workspaceSection(source)))
        p.posix.normalize(match.group(1)!),
    };

String _workspaceSection(String source) {
  final lines = source.split('\n');
  final output = <String>[];
  var active = false;
  for (final line in lines) {
    if (line.trim() == 'workspace:') {
      active = true;
      continue;
    }
    if (active && line.isNotEmpty && !line.startsWith(' ')) break;
    if (active) output.add(line);
  }
  return output.join('\n');
}

String _packageNameForRegistration(String registration) {
  final basename = p.posix.basename(registration);
  return registration.startsWith('packages/features/')
      ? 'feature_$basename'
      : basename;
}

void _validatePathDependencies(
  File pubspec,
  String source,
  String root,
  List<String> issues,
) {
  String? dependency;
  var inDependencySection = false;
  for (final line in source.split('\n')) {
    final trimmed = line.trimRight();
    if (trimmed == 'dependencies:' || trimmed == 'dev_dependencies:') {
      inDependencySection = true;
      dependency = null;
      continue;
    }
    if (inDependencySection && line.isNotEmpty && !line.startsWith(' ')) {
      inDependencySection = false;
      dependency = null;
    }
    if (!inDependencySection) continue;
    final dependencyMatch =
        RegExp(r'^  ([a-zA-Z][a-zA-Z0-9_]*):').firstMatch(line);
    if (dependencyMatch != null) {
      dependency = dependencyMatch.group(1);
      continue;
    }
    final pathMatch = RegExp(r'^    path:\s*([^#\s]+)').firstMatch(line);
    if (dependency == null || pathMatch == null) continue;
    final target = Directory(
      p.normalize(p.join(pubspec.parent.path, pathMatch.group(1)!)),
    );
    if (!File(p.join(target.path, 'pubspec.yaml')).existsSync()) {
      issues.add('${p.relative(pubspec.path, from: root)} has dangling path '
          'dependency $dependency: ${pathMatch.group(1)}');
    }
  }
}

Map<String, List<String>> _duplicatePackageNames(String root) {
  final found = <String, List<String>>{};
  final searchRoots = [Directory(p.join(root, 'packages'))];
  final published = Directory(p.join(root, 'published'));
  if (published.existsSync()) {
    searchRoots.add(published);
  }
  for (final searchRoot in searchRoots.where((item) => item.existsSync())) {
    for (final entity
        in searchRoot.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || p.basename(entity.path) != 'pubspec.yaml') {
        continue;
      }
      final name = parsePubspecName(entity.readAsStringSync());
      if (name == null) {
        continue;
      }
      (found[name] ??= []).add(_posixRelative(entity.parent.path, root));
    }
  }
  return {
    for (final entry in found.entries)
      if (entry.value.length > 1) entry.key: entry.value..sort(),
  };
}
