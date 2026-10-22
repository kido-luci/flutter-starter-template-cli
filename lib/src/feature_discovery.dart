import 'dart:io';

import 'package:path/path.dart' as p;

import 'feature_manifest.dart';
import 'feature_names.dart';
import 'rewrite/feature_template.dart';

enum FeatureOwnership { manifest, legacy, unowned }

final class FeatureRegistration {
  const FeatureRegistration({
    required this.workspace,
    required this.rootDependency,
    required this.di,
    required this.module,
    required this.layering,
  });

  final bool workspace;
  final bool rootDependency;
  final bool di;
  final bool module;
  final bool layering;

  bool get complete => workspace && rootDependency && di && module && layering;

  List<String> get missing => [
        if (!workspace) 'workspace',
        if (!rootDependency) 'root dependency',
        if (!di) 'DI module',
        if (!module) 'feature module',
        if (!layering) 'architecture layer',
      ];
}

final class DiscoveredFeature {
  const DiscoveredFeature({
    required this.id,
    required this.package,
    required this.directory,
    required this.source,
    required this.routePath,
    required this.routeNames,
    required this.dependencies,
    required this.ownership,
    required this.registration,
    required this.modifiedFiles,
    required this.unknownFiles,
    required this.manifestError,
  });

  final String id;
  final String package;
  final String directory;
  final FeatureSource? source;
  final String? routePath;
  final List<String> routeNames;
  final Set<String> dependencies;
  final FeatureOwnership ownership;
  final FeatureRegistration registration;
  final List<String> modifiedFiles;
  final List<String> unknownFiles;
  final String? manifestError;

  bool get owned => ownership != FeatureOwnership.unowned;
  bool get hasUserChanges =>
      modifiedFiles.isNotEmpty || unknownFiles.isNotEmpty;
}

final class FeatureInventory {
  const FeatureInventory(this.root, this.features, this.issues);

  final String root;
  final List<DiscoveredFeature> features;
  final List<String> issues;

  DiscoveredFeature? find(String name) {
    final normalized =
        name.startsWith('feature_') ? name.substring('feature_'.length) : name;
    for (final feature in features) {
      if (feature.id == normalized || feature.package == name) return feature;
    }
    return null;
  }

  List<DiscoveredFeature> reverseDependencies(String package) => features
      .where((feature) => feature.dependencies.contains(package))
      .toList()
    ..sort((a, b) => a.id.compareTo(b.id));
}

FeatureInventory discoverFeatures(String root) {
  final issues = <String>[];
  final features = <DiscoveredFeature>[];
  final rootPubspec = _read(root, 'pubspec.yaml');
  final injection = _read(root, 'lib/app/di/injection.dart');
  final modules = _read(root, 'lib/app/features.dart');
  final layering = _read(root, 'test/architecture/package_layering_test.dart');
  final featuresDirectory = Directory(p.join(root, 'packages', 'features'));

  if (featuresDirectory.existsSync()) {
    final directories = featuresDirectory
        .listSync(followLinks: false)
        .whereType<Directory>()
        .where((directory) =>
            File(p.join(directory.path, 'pubspec.yaml')).existsSync())
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final directory in directories) {
      final pubspec =
          File(p.join(directory.path, 'pubspec.yaml')).readAsStringSync();
      final package = _packageName(pubspec) ?? '';
      final basename = p.basename(directory.path);
      final id = package.startsWith('feature_')
          ? package.substring('feature_'.length)
          : basename;
      final names = FeatureNames(id);
      FeatureManifest? manifest;
      String? manifestError;
      try {
        manifest = readFeatureManifest(directory.path);
        if (manifest != null &&
            (manifest.id != id || manifest.package != package)) {
          throw const FormatException(
            'Manifest identity does not match its package directory.',
          );
        }
        if (manifest != null) {
          final expectedRouteNames = [names.routeName, names.detailsRouteName];
          final actualRoutePath = _routePath(directory, id);
          final expectedFiles = featureFiles(
            names,
            source: manifest.source,
            routePath: manifest.routePath,
          ).keys.toSet();
          if (manifest.routePath != actualRoutePath ||
              manifest.routeNames.join('\n') != expectedRouteNames.join('\n') ||
              manifest.generatedFiles.keys
                  .toSet()
                  .difference(expectedFiles)
                  .isNotEmpty ||
              expectedFiles
                  .difference(manifest.generatedFiles.keys.toSet())
                  .isNotEmpty) {
            throw const FormatException(
              'Feature manifest does not match the generated scaffold contract.',
            );
          }
        }
      } on Object catch (error) {
        manifestError = '$error';
        issues.add('$package has an invalid $featureManifestName: $error');
      }

      final routePath = manifest?.routePath ?? _routePath(directory, id);
      final source = manifest?.source ?? _inferSource(directory);
      final ownership = manifest != null
          ? FeatureOwnership.manifest
          : _matchesLegacyScaffold(directory, names, source, routePath)
              ? FeatureOwnership.legacy
              : FeatureOwnership.unowned;
      final changes = manifest != null
          ? _manifestChanges(directory, manifest)
          : ownership == FeatureOwnership.legacy
              ? (
                  <String>[],
                  _legacyUnknownFiles(
                    directory,
                    names,
                    source!,
                    routePath!,
                  ),
                )
              : const (<String>[], <String>[]);
      final declaredRequiredFeatures = _requiredFeaturesForModule(
        modules,
        names.pascal,
      );
      final runtimeDependencies = {
        ..._runtimeDependencies(pubspec),
        for (final req in declaredRequiredFeatures) 'feature_$req',
      };
      final registration = FeatureRegistration(
        workspace: rootPubspec.contains(
          '  - packages/features/${names.snake}\n',
        ),
        rootDependency: rootPubspec.contains('  ${names.package}: ^0.1.0\n'),
        di: injection.contains(
              "import 'package:${names.package}/${names.package}.dart';",
            ) &&
            injection.contains('ExternalModule(${names.packageModule})'),
        module: modules.contains(
              "import 'package:${names.package}/${names.package}.dart';",
            ) &&
            modules.contains('_${names.pascal}Module()') &&
            _moduleHasMatchingId(modules, names.pascal, names.snake),
        layering: layering.contains("'${names.package}': 4"),
      );
      final routes =
          manifest?.routeNames ?? [names.routeName, names.detailsRouteName];
      features.add(
        DiscoveredFeature(
          id: id,
          package: package,
          directory: p.relative(directory.path, from: root),
          source: source,
          routePath: routePath,
          routeNames: routes,
          dependencies: runtimeDependencies,
          ownership: ownership,
          registration: registration,
          modifiedFiles: changes.$1,
          unknownFiles: changes.$2,
          manifestError: manifestError,
        ),
      );
      _validateFeatureArchitecture(
        root: root,
        directory: directory,
        package: package,
        runtimeDependencies: runtimeDependencies,
        rootPackageName: _packageName(rootPubspec),
        issues: issues,
      );
    }
  }

  final packages = features.map((feature) => feature.package).toSet();
  for (final line in rootPubspec.split('\n')) {
    final workspace =
        RegExp(r'^  - packages/features/([^/\s]+)$').firstMatch(line)?.group(1);
    if (workspace != null &&
        !Directory(p.join(featuresDirectory.path, workspace)).existsSync()) {
      issues.add('Workspace references missing feature directory: $workspace');
    }
    final dependency =
        RegExp(r'^  (feature_[a-z0-9_]+):').firstMatch(line)?.group(1);
    if (dependency != null && !packages.contains(dependency)) {
      issues.add('Root dependency references missing feature: $dependency');
    }
  }

  for (final source in [injection, modules]) {
    for (final match
        in RegExp(r"package:(feature_[a-z0-9_]+)/").allMatches(source)) {
      final package = match.group(1)!;
      if (!packages.contains(package)) {
        issues.add('App wiring references missing feature: $package');
      }
    }
  }
  for (final match in RegExp(
    r"^\s*'(feature_[a-z0-9_]+)':\s*\d+",
    multiLine: true,
  ).allMatches(layering)) {
    final package = match.group(1)!;
    if (!packages.contains(package)) {
      issues.add('Architecture layering references missing feature: $package');
    }
  }

  final seenModuleIds = <String>{};
  for (final match in RegExp(
    r"String\s+get\s+id\s*=>\s*'([^']+)'\s*;",
  ).allMatches(modules)) {
    final moduleId = match.group(1)!;
    if (!seenModuleIds.add(moduleId)) {
      issues.add(
        'Duplicate FeatureModule id "$moduleId" in lib/app/features.dart',
      );
    }
  }

  final routeOwners = <String, String>{};
  for (final feature in features) {
    final route = feature.routePath;
    if (route != null) {
      final previous = routeOwners[route];
      if (previous != null) {
        issues.add('Duplicate route $route: $previous and ${feature.package}');
      } else {
        routeOwners[route] = feature.package;
      }
    }
    if (feature.owned && !feature.registration.complete) {
      issues.add(
        '${feature.package} is missing registrations: '
        '${feature.registration.missing.join(', ')}',
      );
    }
  }
  _detectCircularFeatureDependencies(features, issues);
  return FeatureInventory(root, features, issues);
}

const Map<String, Set<String>> _defaultAllowedFeatureDependencies = {
  'feature_bookmarks': {'feature_collections'},
  'feature_profile': {'feature_auth'},
};

const Set<String> _forbiddenDomainPackageImports = {
  'app_ui',
  'flutter_bloc',
  'go_router',
  'localization',
  'shared_ui',
  'theme',
};

const Set<String> _forbiddenDomainFlutterLibraries = {
  'package:flutter/cupertino.dart',
  'package:flutter/material.dart',
  'package:flutter/painting.dart',
  'package:flutter/rendering.dart',
  'package:flutter/widgets.dart',
};

bool _moduleHasMatchingId(String modules, String pascal, String snake) {
  final blockMatch = RegExp(
    'class\\s+_${pascal}Module\\s+extends\\s+[A-Za-z0-9_]+\\s*\\{([\\s\\S]*?)\\n\\}',
  ).firstMatch(modules);
  if (blockMatch == null) return false;
  final body = blockMatch.group(1)!;
  final idMatch =
      RegExp(r"String\s+get\s+id\s*=>\s*'([^']+)'\s*;").firstMatch(body);
  // Accept legacy scaffolds that have no `id` getter only when `FeatureModule`
  // itself is a minimal test stub without `id`, otherwise require matching `id`.
  if (idMatch == null) {
    return !modules.contains('String get id =>');
  }
  return idMatch.group(1) == snake;
}

Set<String> _requiredFeaturesForModule(String modules, String pascal) {
  final blockMatch = RegExp(
    'class\\s+_${pascal}Module\\s+extends\\s+[A-Za-z0-9_]+\\s*\\{([\\s\\S]*?)\\n\\}',
  ).firstMatch(modules);
  if (blockMatch == null) return const {};
  final body = blockMatch.group(1)!;
  final reqMatch = RegExp(
    r'requiredFeatures\s*=>\s*(?:const\s*)?\{([^}]*)\}',
  ).firstMatch(body);
  if (reqMatch == null) return const {};
  return {
    for (final m in RegExp(r"'([a-z0-9_]+)'").allMatches(reqMatch.group(1)!))
      m.group(1)!,
  };
}

void _validateFeatureArchitecture({
  required String root,
  required Directory directory,
  required String package,
  required Set<String> runtimeDependencies,
  required String? rootPackageName,
  required List<String> issues,
}) {
  if (rootPackageName != null &&
      rootPackageName.isNotEmpty &&
      runtimeDependencies.contains(rootPackageName)) {
    issues.add(
      '$package cannot depend on application shell package $rootPackageName',
    );
  }
  if (runtimeDependencies.contains('test_utils')) {
    issues.add(
      '$package cannot depend on dev/test utility package test_utils in runtime dependencies',
    );
  }
  final allowedFeatureDeps =
      _defaultAllowedFeatureDependencies[package] ?? const <String>{};
  for (final dep in runtimeDependencies.where(
    (name) => name.startsWith('feature_'),
  )) {
    if (dep == package) {
      issues.add('$package cannot depend on itself');
    } else if (!allowedFeatureDeps.contains(dep)) {
      issues.add(
        '$package has unapproved feature-to-feature dependency on $dep',
      );
    }
  }

  final libDir = Directory(p.join(directory.path, 'lib'));
  if (!libDir.existsSync()) return;

  final barrelFile = File(p.join(libDir.path, '$package.dart'));
  if (barrelFile.existsSync()) {
    final barrelContent = barrelFile.readAsStringSync();
    for (final match in _directiveRegex.allMatches(barrelContent)) {
      if (match.group(1) != 'export') continue;
      final uri = match.group(2)!;
      if (uri == 'src/di.dart' ||
          uri == 'src/locator.dart' ||
          uri.startsWith('src/data/') ||
          uri.startsWith('src/domain/repositories/') ||
          uri.startsWith('src/domain/usecases/')) {
        issues.add(
          '$package public barrel leaks internal implementation: $uri',
        );
      }
    }
  }

  for (final entity in libDir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final relativeToFeature = p.posix.joinAll(
      p.split(p.relative(entity.path, from: directory.path)),
    );
    final isDomainFile = relativeToFeature.startsWith('lib/src/domain/');
    final content = entity.readAsStringSync();

    for (final match in _directiveRegex.allMatches(content)) {
      final uri = match.group(2)!;
      if (uri.startsWith('package:')) {
        final slash = uri.indexOf('/');
        if (slash == -1) continue;
        final targetPkg = uri.substring('package:'.length, slash);
        final targetPath = uri.substring(slash + 1);
        if (targetPkg != package && targetPath.startsWith('src/')) {
          issues.add(
            '$package imports private src/ of $targetPkg in $relativeToFeature: $uri',
          );
        }
        if (isDomainFile &&
            (_forbiddenDomainPackageImports.contains(targetPkg) ||
                _forbiddenDomainFlutterLibraries.contains(uri))) {
          issues.add(
            '$package domain layer imports UI/presentation library in $relativeToFeature: $uri',
          );
        }
      } else if (!uri.startsWith('dart:')) {
        final resolved = p.normalize(
          p.join(p.dirname(entity.path), p.joinAll(uri.split('/'))),
        );
        if (!p.isWithin(libDir.path, resolved) && resolved != libDir.path) {
          issues.add(
            '$package has relative directive escaping lib/ in $relativeToFeature: $uri',
          );
        }
      }
    }
  }
}

void _detectCircularFeatureDependencies(
  List<DiscoveredFeature> features,
  List<String> issues,
) {
  final byPackage = {for (final f in features) f.package: f};
  final visited = <String>{};
  final active = <String>{};

  bool dfs(String pkg) {
    visited.add(pkg);
    active.add(pkg);
    final feature = byPackage[pkg];
    if (feature != null) {
      for (final dep in feature.dependencies.where(byPackage.containsKey)) {
        if (active.contains(dep)) {
          issues.add('Circular feature dependency detected: $pkg -> $dep');
          return true;
        }
        if (!visited.contains(dep) && dfs(dep)) {
          return true;
        }
      }
    }
    active.remove(pkg);
    return false;
  }

  for (final feature in features) {
    if (!visited.contains(feature.package)) {
      dfs(feature.package);
    }
  }
}

final RegExp _directiveRegex = RegExp(
  r'''^\s*(import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

String _read(String root, String relative) {
  final file = File(p.join(root, relative));
  return file.existsSync() ? file.readAsStringSync() : '';
}

String? _packageName(String pubspec) =>
    RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(pubspec)?.group(1);

Set<String> _runtimeDependencies(String pubspec) {
  final dependencies = <String>{};
  var inDependencies = false;
  for (final line in pubspec.split('\n')) {
    if (line == 'dependencies:') {
      inDependencies = true;
      continue;
    }
    if (inDependencies && line.isNotEmpty && !line.startsWith(' ')) break;
    if (!inDependencies) continue;
    final dependency = RegExp(r'^  ([a-zA-Z0-9_]+):').firstMatch(line);
    if (dependency != null) dependencies.add(dependency.group(1)!);
  }
  return dependencies;
}

String? _routePath(Directory directory, String id) {
  final file = File(
    p.join(directory.path, 'lib', 'src', 'presentation', '${id}_routes.dart'),
  );
  if (!file.existsSync()) return null;
  return RegExp(r"static const root = '([^']+)'\s*;")
      .firstMatch(file.readAsStringSync())
      ?.group(1);
}

FeatureSource? _inferSource(Directory directory) {
  if (File(p.join(directory.path, 'SYNC_TODO.md')).existsSync()) {
    return FeatureSource.sync;
  }
  final data = Directory(p.join(directory.path, 'lib', 'src', 'data'));
  if (Directory(p.join(data.path, 'datasources')).existsSync()) {
    return FeatureSource.api;
  }
  if (Directory(p.join(data.path, 'local')).existsSync()) {
    return FeatureSource.local;
  }
  if (File(p.join(directory.path, 'lib', 'src', 'di.dart')).existsSync()) {
    return FeatureSource.presentation;
  }
  return null;
}

bool _matchesLegacyScaffold(
  Directory directory,
  FeatureNames names,
  FeatureSource? source,
  String? routePath,
) {
  if (source == null || routePath == null) return false;
  final scaffold = featureFiles(names, source: source, routePath: routePath);
  for (final entry in scaffold.entries) {
    final file = File(p.join(directory.path, p.joinAll(entry.key.split('/'))));
    if (!file.existsSync() || file.readAsStringSync() != entry.value) {
      return false;
    }
  }
  return true;
}

List<String> _legacyUnknownFiles(
  Directory directory,
  FeatureNames names,
  FeatureSource source,
  String routePath,
) {
  final known = featureFiles(names, source: source, routePath: routePath).keys;
  final unknown = <String>[];
  for (final entity
      in directory.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = p.relative(entity.path, from: directory.path);
    if (!known.contains(relative) && !_isGeneratedArtifact(relative)) {
      unknown.add(relative);
    }
  }
  return unknown..sort();
}

(List<String>, List<String>) _manifestChanges(
  Directory directory,
  FeatureManifest manifest,
) {
  final modified = <String>[];
  for (final entry in manifest.generatedFiles.entries) {
    final file = File(p.join(directory.path, p.joinAll(entry.key.split('/'))));
    if (!file.existsSync() ||
        featureContentFingerprint(file.readAsBytesSync()) != entry.value) {
      modified.add(entry.key);
    }
  }
  final known = {...manifest.generatedFiles.keys, featureManifestName};
  final unknown = <String>[];
  for (final entity
      in directory.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = p.relative(entity.path, from: directory.path);
    if (!known.contains(relative) && !_isGeneratedArtifact(relative)) {
      unknown.add(relative);
    }
  }
  modified.sort();
  unknown.sort();
  return (modified, unknown);
}

bool _isGeneratedArtifact(String relative) {
  final basename = p.basename(relative);
  return relative.startsWith('.dart_tool${p.separator}') ||
      relative.startsWith('build${p.separator}') ||
      basename == 'pubspec.lock' ||
      basename == '.flutter-plugins' ||
      basename == '.flutter-plugins-dependencies' ||
      basename == 'di.module.dart' ||
      basename.endsWith('.g.dart') ||
      basename.endsWith('.freezed.dart');
}
