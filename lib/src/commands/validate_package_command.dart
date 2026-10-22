import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../package_architecture.dart';
import '../package_lifecycle.dart';

final class ValidatePackageCommand extends Command<int> {
  ValidatePackageCommand(this._logger, {String? rootDirectory})
      : _rootDirectory = rootDirectory;

  final Logger _logger;
  final String? _rootDirectory;

  @override
  String get name => 'validate-package';

  @override
  String get description =>
      'Validate a reusable workspace package and its architecture contracts.';

  @override
  String get invocation => 'fst validate-package <package-name>';

  @override
  int run() {
    final positional = argResults?.rest ?? const [];
    if (positional.length != 1) {
      _logger.err('Provide exactly one package name.');
      return 1;
    }
    final name = positional.single.trim();
    final result = validateWorkspacePackage(
      _rootDirectory ?? Directory.current.path,
      name,
    );
    final inventory = discoverPackages(
      _rootDirectory ?? Directory.current.path,
    );
    final issues = {...result.issues, ...inventory.issues}.toList()..sort();
    if (!result.isValid || issues.isNotEmpty) {
      for (final issue in issues) {
        _logger.err(issue);
      }
      return 1;
    }
    _logger.success('Validated workspace package $name.');
    return 0;
  }
}
