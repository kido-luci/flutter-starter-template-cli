import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../feature_discovery.dart';

final class ValidateFeaturesCommand extends Command<int> {
  ValidateFeaturesCommand(this._logger, {String? rootDirectory})
      : _rootDirectory = rootDirectory;

  final Logger _logger;
  final String? _rootDirectory;

  @override
  String get name => 'validate-features';

  @override
  String get description =>
      'Validate feature packages, routes, dependencies, and registrations.';

  @override
  int run() {
    final inventory =
        discoverFeatures(_rootDirectory ?? Directory.current.path);
    final issues = [...inventory.issues];
    final packages =
        inventory.features.map((feature) => feature.package).toSet();
    for (final feature in inventory.features) {
      for (final dependency in feature.dependencies
          .where((name) => name.startsWith('feature_'))) {
        if (!packages.contains(dependency)) {
          issues.add('${feature.package} depends on missing $dependency');
        }
      }
      if (feature.manifestError != null) {
        issues.add('${feature.package} has invalid ownership metadata');
      }
    }
    if (issues.isNotEmpty) {
      for (final issue in issues.toSet()) {
        _logger.err(issue);
      }
      return 1;
    }
    _logger.success(
      'Validated ${inventory.features.length} feature package(s).',
    );
    return 0;
  }
}
