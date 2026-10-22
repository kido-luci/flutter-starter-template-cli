import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flutter_starter_template_cli/src/commands/add_feature_command.dart';
import 'package:flutter_starter_template_cli/src/commands/create_command.dart';
import 'package:flutter_starter_template_cli/src/commands/create_package_command.dart';
import 'package:flutter_starter_template_cli/src/commands/list_features_command.dart';
import 'package:flutter_starter_template_cli/src/commands/list_packages_command.dart';
import 'package:flutter_starter_template_cli/src/commands/remove_feature_command.dart';
import 'package:flutter_starter_template_cli/src/commands/remove_package_command.dart';
import 'package:flutter_starter_template_cli/src/commands/validate_features_command.dart';
import 'package:flutter_starter_template_cli/src/commands/validate_package_command.dart';
import 'package:mason_logger/mason_logger.dart';

Future<void> main(List<String> args) async {
  final logger = Logger();
  final runner = CommandRunner<int>(
    'fst',
    'Flutter Starter Template CLI — scaffold a new Flutter project.',
  )
    ..addCommand(CreateCommand(logger))
    ..addCommand(CreatePackageCommand(logger))
    ..addCommand(AddFeatureCommand(logger))
    ..addCommand(ListFeaturesCommand(logger))
    ..addCommand(ListPackagesCommand(logger))
    ..addCommand(RemoveFeatureCommand(logger))
    ..addCommand(RemovePackageCommand(logger))
    ..addCommand(ValidateFeaturesCommand(logger))
    ..addCommand(ValidatePackageCommand(logger));

  try {
    final exitCode = await runner.run(args) ?? 0;
    exit(exitCode);
  } on UsageException catch (e) {
    logger.err(e.message);
    logger.info(e.usage);
    exit(64);
  } catch (e) {
    logger.err('$e');
    exit(1);
  }
}
