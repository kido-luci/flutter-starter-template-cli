import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../feature_discovery.dart';

final class ListFeaturesCommand extends Command<int> {
  ListFeaturesCommand(this._logger, {String? rootDirectory})
      : _rootDirectory = rootDirectory;

  final Logger _logger;
  final String? _rootDirectory;

  @override
  String get name => 'list-features';

  @override
  String get description =>
      'Discover feature packages, registrations, routes, and dependencies.';

  @override
  int run() {
    final inventory =
        discoverFeatures(_rootDirectory ?? Directory.current.path);
    if (inventory.features.isEmpty) {
      _logger.info('No feature packages found.');
      return 0;
    }
    for (final feature in inventory.features) {
      final reverse = inventory.reverseDependencies(feature.package);
      final safe = feature.owned &&
          feature.registration.complete &&
          !feature.hasUserChanges &&
          reverse.isEmpty;
      _logger.info(
        '${feature.id} | ${feature.package} | '
        'source=${feature.source?.name ?? 'unknown'} | '
        'route=${feature.routePath ?? '-'} | '
        'deps=${feature.dependencies.where((d) => d.startsWith('feature_')).join(',')} | '
        'registered=${feature.registration.complete} | removable=$safe | '
        'ownership=${feature.ownership.name}',
      );
    }
    for (final issue in inventory.issues) {
      _logger.warn(issue);
    }
    return inventory.issues.isEmpty ? 0 : 1;
  }
}
