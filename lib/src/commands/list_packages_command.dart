import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../package_lifecycle.dart';

final class ListPackagesCommand extends Command<int> {
  ListPackagesCommand(this._logger, {String? rootDirectory})
      : _rootDirectory = rootDirectory;

  final Logger _logger;
  final String? _rootDirectory;

  @override
  String get name => 'list-packages';

  @override
  String get description =>
      'List workspace packages, ownership, dependencies, and removability.';

  @override
  int run() {
    final inventory = discoverPackages(
      _rootDirectory ?? Directory.current.path,
    );
    if (inventory.packages.isEmpty) {
      _logger.info('No workspace packages found.');
    }
    for (final item in inventory.packages) {
      final direct = inventory.directConsumers(item.package.name);
      final transitive = inventory.transitiveConsumers(item.package.name);
      final dependencies = {
        ...item.package.dependencies,
        ...item.package.devDependencies,
      }.toList()
        ..sort();
      final blockers = <String>[
        if (!item.owned) 'not CLI-owned',
        if (item.core) 'core package',
        if (!item.valid) 'validation failed',
        if (item.hasUserChanges) 'modified/unknown files',
        if (direct.isNotEmpty || transitive.isNotEmpty) 'has consumers',
      ];
      _logger.info(item.package.name);
      _logger.info('  type: ${item.package.type?.name ?? 'unknown'}');
      _logger.info('  location: ${item.location}');
      _logger.info('  ownership: ${item.ownership.name}');
      _logger.info('  dependencies: '
          '${dependencies.isEmpty ? 'none' : dependencies.join(', ')}');
      _logger.info('  direct consumers: '
          '${direct.isEmpty ? 'none' : direct.join(', ')}');
      _logger.info('  transitive consumers: '
          '${transitive.isEmpty ? 'none' : transitive.join(', ')}');
      _logger.info('  validation: ${item.valid ? 'valid' : 'invalid'}');
      _logger.info('  removal: '
          '${blockers.isEmpty ? 'eligible' : 'blocked (${blockers.join(', ')})'}');
    }
    for (final issue in inventory.issues) {
      _logger.err(issue);
    }
    return inventory.issues.isEmpty ? 0 : 1;
  }
}
