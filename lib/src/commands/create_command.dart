import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:interact/interact.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import '../project_config.dart';
import '../rewrite/rewriter.dart';
import '../validators.dart';

const _templateRepo =
    'https://github.com/kido-luci/flutter-starter-template.git';

class CreateCommand extends Command<int> {
  CreateCommand(this._logger) {
    argParser
      ..addOption(
        'output-dir',
        abbr: 'o',
        help: 'Directory to create the project in (default: <package-name>).',
      )
      ..addFlag(
        'no-setup',
        negatable: false,
        help: 'Skip running tool/setup.sh after scaffolding.',
      );
  }

  final Logger _logger;

  @override
  String get name => 'create';

  @override
  String get description =>
      'Clone the Flutter Starter Template and rename it for your project.';

  @override
  String get invocation => 'fst create [options]';

  @override
  Future<int> run() async {
    _logger.info('');
    _logger.info(
      '  ${lightCyan.wrap('Flutter Starter Template')} — project scaffold\n',
    );

    // ── 1. Collect inputs ────────────────────────────────────────────────────

    final displayName = Input(
      prompt: 'App display name',
      defaultValue: 'My App',
      validator: (v) {
        if (v.trim().isEmpty) throw ValidationError('Cannot be empty.');
        return true;
      },
    ).interact();

    final packageName = Input(
      prompt: 'Dart package name (snake_case)',
      defaultValue: toSnakeCase(displayName),
      validator: (v) {
        if (!isValidPackageName(v)) {
          throw ValidationError(
            'Must be lowercase letters, digits, and underscores '
            '(no leading digit).',
          );
        }
        return true;
      },
    ).interact();

    final bundleId = Input(
      prompt: 'Bundle / App ID (reverse-DNS)',
      defaultValue: 'com.example.$packageName',
      validator: (v) {
        if (!isValidBundleId(v)) {
          throw ValidationError(
            'Must be a valid reverse-DNS identifier, e.g. com.acme.myapp.',
          );
        }
        return true;
      },
    ).interact();

    final org = Input(
      prompt: 'Organisation / author',
      defaultValue: 'My Organisation',
      validator: (v) {
        if (v.trim().isEmpty) throw ValidationError('Cannot be empty.');
        return true;
      },
    ).interact();

    final defaultOutput = argResults?['output-dir'] as String? ?? packageName;
    final outputDir = p.absolute(defaultOutput);

    // ── 2. Confirm ───────────────────────────────────────────────────────────

    _logger.info('');
    _logger.info('  ${styleBold.wrap('Project summary')}');
    _logger.info('  Display name   ${lightCyan.wrap(displayName)}');
    _logger.info('  Package name   ${lightCyan.wrap(packageName)}');
    _logger.info('  Bundle ID      ${lightCyan.wrap(bundleId)}');
    _logger.info('  Organisation   ${lightCyan.wrap(org)}');
    _logger.info('  Output dir     ${lightCyan.wrap(outputDir)}');
    _logger.info('');

    final confirmed = Confirm(
      prompt: 'Create project?',
      defaultValue: true,
    ).interact();

    if (!confirmed) {
      _logger.info('Aborted.');
      return 0;
    }

    final config = ProjectConfig(
      displayName: displayName,
      packageName: packageName,
      bundleId: bundleId,
      org: org,
      outputDir: outputDir,
    );

    // ── 3. Clone ─────────────────────────────────────────────────────────────

    if (Directory(outputDir).existsSync()) {
      _logger.err('Directory already exists: $outputDir');
      return 1;
    }

    final cloneProgress = _logger.progress('Cloning template');
    final cloneResult = await Process.run(
      'git',
      [
        'clone',
        '--recurse-submodules',
        '--depth=1',
        _templateRepo,
        outputDir,
      ],
    );
    if (cloneResult.exitCode != 0) {
      cloneProgress.fail('Clone failed');
      _logger.err(cloneResult.stderr as String);
      return 1;
    }
    cloneProgress.complete('Template cloned');

    // Detach from the upstream remote so the new project has a clean slate.
    await Process.run('git', ['remote', 'remove', 'origin'],
        workingDirectory: outputDir);

    // ── 4. Rewrite ───────────────────────────────────────────────────────────

    final rewriteProgress = _logger.progress('Renaming template identifiers');
    try {
      await rewriteProject(outputDir, config);
      rewriteProgress.complete('Identifiers renamed');
    } catch (e) {
      rewriteProgress.fail('Rewrite failed');
      _logger.err('$e');
      return 1;
    }

    // ── 5. Setup ─────────────────────────────────────────────────────────────

    final skipSetup = argResults?['no-setup'] as bool? ?? false;
    if (!skipSetup) {
      final setupScript = p.join(outputDir, 'tool', 'setup.sh');
      if (File(setupScript).existsSync()) {
        final setupProgress = _logger.progress(
          'Running tool/setup.sh (pub get + codegen…)',
        );
        final result = await Process.run(
          'bash',
          [setupScript, '--no-hooks'],
          workingDirectory: outputDir,
        );
        if (result.exitCode != 0) {
          setupProgress.fail('setup.sh failed');
          _logger.warn(result.stdout as String);
          _logger.err(result.stderr as String);
        } else {
          setupProgress.complete('Dependencies installed & code generated');
        }
      }
    }

    // ── 6. Done ──────────────────────────────────────────────────────────────

    _logger.info('');
    _logger.success('  Project created at $outputDir');
    _logger.info('');
    _logger.info('  Next steps:');
    _logger.info('    cd $outputDir');
    _logger.info('    fvm flutter run');
    _logger.info('');

    return 0;
  }
}
