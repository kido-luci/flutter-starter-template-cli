import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:interact/interact.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import '../config_resolver.dart';
import '../project_config.dart';
import '../rewrite/auth.dart';
import '../rewrite/clean_slate.dart';
import '../rewrite/env.dart';
import '../rewrite/features.dart';
import '../rewrite/firebase.dart';
import '../rewrite/icon.dart';
import '../rewrite/local_template.dart';
import '../rewrite/rewriter.dart';
import '../validators.dart';

const _templateRepo =
    'https://github.com/kido-luci/flutter-starter-template.git';

class CreateCommand extends Command<int> {
  CreateCommand(this._logger) {
    argParser
      ..addOption(
        'name',
        abbr: 'n',
        help: 'App display name (skips the prompt).',
      )
      ..addOption(
        'package-name',
        help: 'Dart package name, snake_case (default: derived from --name).',
      )
      ..addOption(
        'bundle-id',
        help: 'Bundle / App ID, reverse-DNS (skips the prompt).',
      )
      ..addOption(
        'org',
        help: 'Organisation / author (skips the prompt).',
      )
      ..addOption(
        'output-dir',
        abbr: 'o',
        help: 'Directory to create the project in (default: <package-name>).',
      )
      ..addFlag(
        'firebase',
        defaultsTo: true,
        help: 'Wire Firebase (default). Use --no-firebase to scaffold without '
            'it: no Firebase project needed to build and run.',
      )
      ..addFlag(
        'auth',
        defaultsTo: true,
        help: 'Include the auth pillar (default). Use --no-auth to scaffold a '
            'user-less app: no login/register screens or session management.',
      )
      ..addMultiOption(
        'exclude-feature',
        help: 'Demo feature(s) to leave out: bookmarks, collections, '
            'notifications. Repeatable. Excluding collections also excludes '
            'bookmarks (it depends on collections).',
      )
      ..addOption(
        'api-url',
        help:
            'Base URL for the staging & prod env files (dev keeps localhost).',
      )
      ..addOption(
        'icon',
        help: 'Path to a square PNG used to generate the launcher icon.',
      )
      ..addFlag(
        'yes',
        abbr: 'y',
        negatable: false,
        help: 'Run non-interactively: no prompts, no confirmation. Requires '
            '--name, --bundle-id, and --org.',
      )
      ..addFlag(
        'no-setup',
        negatable: false,
        help: 'Skip running tool/setup.sh after scaffolding.',
      )
      ..addOption(
        'template-path',
        help: 'Scaffold from a local template checkout instead of cloning the '
            'remote (useful offline, for a fork, or to test an unpublished '
            'template).',
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

    final yes = argResults?['yes'] as bool? ?? false;

    final String displayName;
    final String packageName;
    final String bundleId;
    final String org;

    if (yes) {
      final result = resolveProjectConfig(
        name: argResults?['name'] as String?,
        packageName: argResults?['package-name'] as String?,
        bundleId: argResults?['bundle-id'] as String?,
        org: argResults?['org'] as String?,
      );
      switch (result) {
        case ConfigError(:final message):
          _logger.err(message);
          return 1;
        case ConfigOk():
          displayName = result.displayName;
          packageName = result.packageName;
          bundleId = result.bundleId;
          org = result.org;
      }
    } else {
      final resolved = _collectInteractively();
      if (resolved == null) return 1;
      (displayName, packageName, bundleId, org) = resolved;
    }

    final useFirebase = _resolveFirebase(yes: yes);

    final useAuth = _resolveAuth(yes: yes);

    final excludedFeatures = _resolveExcludedFeatures(yes: yes);
    if (excludedFeatures == null) return 1;

    final api = _resolveApiUrl(yes: yes);
    if (!api.ok) return 1;

    final icon = _resolveIcon(yes: yes);
    if (!icon.ok) return 1;

    final defaultOutput = argResults?['output-dir'] as String? ?? packageName;
    final outputDir = p.absolute(defaultOutput);

    // ── 2. Summary & confirm ─────────────────────────────────────────────────

    _logger.info('');
    _logger.info('  ${styleBold.wrap('Project summary')}');
    _logger.info('  Display name   ${lightCyan.wrap(displayName)}');
    _logger.info('  Package name   ${lightCyan.wrap(packageName)}');
    _logger.info('  Bundle ID      ${lightCyan.wrap(bundleId)}');
    _logger.info('  Organisation   ${lightCyan.wrap(org)}');
    _logger.info('  Output dir     ${lightCyan.wrap(outputDir)}');
    _logger.info(
      '  Firebase       ${lightCyan.wrap(useFirebase ? 'enabled' : 'disabled')}',
    );
    _logger.info(
      '  Auth           ${lightCyan.wrap(useAuth ? 'enabled' : 'disabled')}',
    );
    if (excludedFeatures.isNotEmpty) {
      _logger.info(
        '  Exclude        ${lightCyan.wrap(excludedFeatures.join(', '))}',
      );
    }
    if (api.url != null) {
      _logger.info('  API base URL   ${lightCyan.wrap(api.url!)}');
    }
    if (icon.path != null) {
      _logger.info('  App icon       ${lightCyan.wrap(icon.path!)}');
    }
    _logger.info('');

    if (!yes) {
      final confirmed = Confirm(
        prompt: 'Create project?',
        defaultValue: true,
      ).interact();

      if (!confirmed) {
        _logger.info('Aborted.');
        return 0;
      }
    }

    final config = ProjectConfig(
      displayName: displayName,
      packageName: packageName,
      bundleId: bundleId,
      org: org,
      outputDir: outputDir,
    );

    // ── 3. Acquire the template ──────────────────────────────────────────────
    // Either clone the remote (default) or copy a local checkout
    // (--template-path). The clean-slate + rewrite steps below run over the
    // result either way.

    if (Directory(outputDir).existsSync()) {
      _logger.err('Directory already exists: $outputDir');
      return 1;
    }

    final templatePath = argResults?['template-path'] as String?;
    if (templatePath != null) {
      final source = p.absolute(templatePath);
      final copyProgress = _logger.progress('Copying template from $source');
      try {
        await copyLocalTemplate(source, outputDir);
        copyProgress.complete('Template copied');
      } catch (e) {
        copyProgress.fail('Copy failed');
        _logger.err('$e');
        return 1;
      }
    } else {
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
    }

    // ── 4. Clean slate ───────────────────────────────────────────────────────
    // Drop the vendored submodules (demo backend + CLI source) and the
    // template's git history, then re-init a fresh repo so the new project
    // starts from its own first commit.
    final cleanProgress = _logger.progress('Resetting to a clean slate');
    try {
      await prepareCleanSlate(outputDir);
      cleanProgress.complete('Clean slate ready');
    } catch (e) {
      cleanProgress.fail('Clean slate failed');
      _logger.err('$e');
      return 1;
    }

    // ── 5. Rewrite ───────────────────────────────────────────────────────────

    final rewriteProgress = _logger.progress('Renaming template identifiers');
    try {
      await rewriteProject(outputDir, config);
      await _writeProjectReadme(outputDir, config,
          firebaseEnabled: useFirebase);
      rewriteProgress.complete('Identifiers renamed');
    } catch (e) {
      rewriteProgress.fail('Rewrite failed');
      _logger.err('$e');
      return 1;
    }

    // ── 5b. Disable Firebase ─────────────────────────────────────────────────
    // Runs before setup so codegen and the native build see the disabled tree.
    if (!useFirebase) {
      final firebaseProgress = _logger.progress('Disabling Firebase');
      try {
        await disableFirebase(outputDir);
        firebaseProgress.complete('Firebase disabled');
      } catch (e) {
        firebaseProgress.fail('Disabling Firebase failed');
        _logger.err('$e');
        return 1;
      }
    }

    // ── 5b2. Disable auth ────────────────────────────────────────────────────
    // Before setup so codegen (router.g.dart, DI) sees the auth-stripped tree.
    if (!useAuth) {
      final authProgress = _logger.progress('Removing auth pillar');
      try {
        await disableAuth(outputDir);
        authProgress.complete('Auth pillar removed');
      } catch (e) {
        authProgress.fail('Removing auth pillar failed');
        _logger.err('$e');
        return 1;
      }
    }

    // ── 5c. Exclude features + set API URL ───────────────────────────────────
    // Before setup so codegen (router.g.dart, DI) sees the trimmed tree.
    if (excludedFeatures.isNotEmpty) {
      final featureProgress = _logger.progress(
        'Removing features: ${excludedFeatures.join(', ')}',
      );
      try {
        await excludeFeatures(outputDir, excludedFeatures);
        featureProgress.complete('Features removed');
      } catch (e) {
        featureProgress.fail('Removing features failed');
        _logger.err('$e');
        return 1;
      }
    }

    if (api.url != null) {
      final envProgress = _logger.progress('Setting API base URL');
      try {
        await applyApiBaseUrl(outputDir, api.url!);
        envProgress.complete('API base URL set');
      } catch (e) {
        envProgress.fail('Setting API base URL failed');
        _logger.err('$e');
        return 1;
      }
    }

    // ── 6. Setup ─────────────────────────────────────────────────────────────

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

    // ── 6b. Launcher icon ────────────────────────────────────────────────────
    // After setup so `flutter_launcher_icons` has its dependencies resolved.
    if (icon.path != null) {
      installLauncherIcon(outputDir, icon.path!);
      if (skipSetup) {
        _logger.info(
          'Icon copied to tool/launcher_icons/. Run '
          '`dart run flutter_launcher_icons` after installing dependencies.',
        );
      } else {
        final iconProgress = _logger.progress('Generating launcher icon');
        final useFvm =
            File(p.join(outputDir, '.fvmrc')).existsSync() && _hasFvm();
        final result = await Process.run(
          useFvm ? 'fvm' : 'dart',
          [if (useFvm) 'dart', 'run', 'flutter_launcher_icons'],
          workingDirectory: outputDir,
        );
        if (result.exitCode != 0) {
          iconProgress.fail('Icon generation failed');
          _logger.warn(result.stdout as String);
          _logger.err(result.stderr as String);
        } else {
          iconProgress.complete('Launcher icon generated');
        }
      }
    }

    // ── 7. Done ──────────────────────────────────────────────────────────────

    _logger.info('');
    _logger.success('  Project created at $outputDir');
    _logger.info('');

    if (useFirebase) {
      _logger.warn(
        'Firebase is still wired to the template. lib/firebase_options.dart '
        'points at the template Firebase project, so the app will use it until '
        'you reconfigure it for your own project.',
      );
      _logger.info('');
      _logger.info('  Next steps:');
      _logger.info('    cd "$outputDir"');
      _logger.info('');
      _logger.info('    # Point Firebase at your own project:');
      _logger.info(
          '    dart pub global activate flutterfire_cli  # if not installed');
      _logger.info('    flutterfire configure');
    } else {
      _logger.info(
        'Firebase is disabled — the app builds and runs without a Firebase '
        'project. To add it later, set kFirebaseEnabled to true in '
        'lib/app/firebase.dart, restore the Firebase tracking bindings '
        '(// fst:analytics-impl, // fst:crash-impl), and run '
        'flutterfire configure.',
      );
      _logger.info('');
      _logger.info('  Next steps:');
      _logger.info('    cd "$outputDir"');
    }

    _logger.info('');
    _logger
        .info('    # Make your first commit (a fresh git repo was created):');
    _logger.info('    git add -A && git commit -m "Initial commit"');
    _logger.info('');
    _logger.info('    # Then run the app:');
    _logger.info('    fvm flutter run');
    _logger.info('');

    return 0;
  }

  /// Resolves whether to wire Firebase. An explicit `--firebase`/`--no-firebase`
  /// wins; otherwise non-interactive runs default to on (a safe default, unlike
  /// the identity inputs) and interactive runs prompt.
  bool _resolveFirebase({required bool yes}) {
    if (argResults?.wasParsed('firebase') ?? false) {
      return argResults?['firebase'] as bool? ?? true;
    }
    if (yes) return true;
    return Confirm(prompt: 'Use Firebase?', defaultValue: true).interact();
  }

  /// Resolves whether to include the auth pillar. An explicit
  /// `--auth`/`--no-auth` wins; otherwise non-interactive runs default to on
  /// and interactive runs prompt.
  bool _resolveAuth({required bool yes}) {
    if (argResults?.wasParsed('auth') ?? false) {
      return argResults?['auth'] as bool? ?? true;
    }
    if (yes) return true;
    return Confirm(prompt: 'Include auth (login / register)?', defaultValue: true)
        .interact();
  }

  /// Resolves the demo features to exclude. `--exclude-feature` (validated)
  /// wins; otherwise a multi-select prompt (interactive) or none (`--yes`).
  /// Returns `null` on an unknown feature name (logged). The result is expanded
  /// for dependencies (excluding collections also excludes bookmarks).
  Set<String>? _resolveExcludedFeatures({required bool yes}) {
    final flag = argResults?['exclude-feature'] as List<String>? ?? const [];
    if (flag.isNotEmpty) {
      final invalid =
          flag.where((f) => !removableFeatures.contains(f)).toList();
      if (invalid.isNotEmpty) {
        _logger.err(
          'Unknown --exclude-feature: ${invalid.join(', ')}. '
          'Valid: ${removableFeatures.join(', ')}.',
        );
        return null;
      }
      return _expandWithNotice(flag.toSet());
    }
    if (yes) return <String>{};

    final options = removableFeatures.toList();
    final selected = MultiSelect(
      prompt: 'Features to include (space toggles, enter confirms)',
      options: options,
      defaults: List<bool>.filled(options.length, true),
    ).interact();
    final kept = selected.map((i) => options[i]).toSet();
    return _expandWithNotice(removableFeatures.difference(kept));
  }

  Set<String> _expandWithNotice(Set<String> excluded) {
    final expanded = expandExcludedFeatures(excluded);
    final added = expanded.difference(excluded);
    if (added.isNotEmpty) {
      _logger.info(
        'Also excluding ${added.join(', ')} (a kept feature can\'t depend on '
        'a removed one).',
      );
    }
    return expanded;
  }

  /// Resolves the staging/prod API base URL. `--api-url` (validated) wins;
  /// otherwise a prompt (interactive) or keep-template (`--yes`). `url` is null
  /// to keep the template values; `ok` is false on an invalid `--api-url`.
  ({bool ok, String? url}) _resolveApiUrl({required bool yes}) {
    final flag = argResults?['api-url'] as String?;
    if (flag != null) {
      if (!isValidHttpUrl(flag)) {
        _logger.err('Invalid --api-url "$flag": must be an http(s) URL.');
        return (ok: false, url: null);
      }
      return (ok: true, url: flag);
    }
    if (yes) return (ok: true, url: null);

    final entered = Input(
      prompt: 'API base URL for staging & prod (blank to keep template)',
      validator: (v) {
        if (v.trim().isEmpty || isValidHttpUrl(v.trim())) return true;
        throw ValidationError(
            'Must be an http(s) URL, e.g. https://api.acme.com');
      },
    ).interact().trim();
    return (ok: true, url: entered.isEmpty ? null : entered);
  }

  /// Resolves the launcher-icon source. `--icon` (validated) wins; otherwise a
  /// prompt (interactive) or none (`--yes`). `path` is null to skip; `ok` is
  /// false on an invalid `--icon`.
  ({bool ok, String? path}) _resolveIcon({required bool yes}) {
    final flag = argResults?['icon'] as String?;
    if (flag != null) {
      final error = _iconError(flag);
      if (error != null) {
        _logger.err(error);
        return (ok: false, path: null);
      }
      return (ok: true, path: flag);
    }
    if (yes) return (ok: true, path: null);

    final entered = Input(
      prompt: 'Path to a square PNG launcher icon (blank to skip)',
      validator: (v) {
        if (v.trim().isEmpty) return true;
        final error = _iconError(v.trim());
        if (error != null) throw ValidationError(error);
        return true;
      },
    ).interact().trim();
    return (ok: true, path: entered.isEmpty ? null : entered);
  }

  String? _iconError(String path) {
    if (!isPngPath(path)) return 'Icon must be a .png file: $path';
    if (!File(path).existsSync()) return 'Icon file not found: $path';
    return null;
  }

  bool _hasFvm() {
    try {
      return Process.runSync('fvm', ['--version']).exitCode == 0;
    } on Object {
      return false;
    }
  }

  /// Resolves the four identity inputs interactively, honouring any supplied as
  /// flags. A flag that is present is validated and used as-is; an invalid flag
  /// logs an error and returns `null` (the command then exits non-zero) instead
  /// of silently dropping to a prompt. Returns the resolved
  /// `(displayName, packageName, bundleId, org)` tuple, or `null` on a bad flag.
  (String, String, String, String)? _collectInteractively() {
    final nameFlag = argResults?['name'] as String?;
    final packageFlag = argResults?['package-name'] as String?;
    final bundleFlag = argResults?['bundle-id'] as String?;
    final orgFlag = argResults?['org'] as String?;

    final String displayName;
    if (nameFlag != null) {
      if (nameFlag.trim().isEmpty) {
        _logger.err('--name cannot be empty.');
        return null;
      }
      displayName = nameFlag.trim();
    } else {
      displayName = Input(
        prompt: 'App display name',
        defaultValue: 'My App',
        validator: _notEmpty,
      ).interact();
    }

    final String packageName;
    if (packageFlag != null) {
      if (!isValidPackageName(packageFlag.trim())) {
        _logger.err(
          'Invalid --package-name "${packageFlag.trim()}": must be lowercase '
          'letters, digits, and underscores (no leading digit).',
        );
        return null;
      }
      packageName = packageFlag.trim();
    } else {
      packageName = Input(
        prompt: 'Dart package name (snake_case)',
        defaultValue: toSnakeCase(displayName),
        validator: _packageValidator,
      ).interact();
    }

    final String bundleId;
    if (bundleFlag != null) {
      if (!isValidBundleId(bundleFlag.trim())) {
        _logger.err(
          'Invalid --bundle-id "${bundleFlag.trim()}": must be a reverse-DNS '
          'identifier, e.g. com.acme.myapp.',
        );
        return null;
      }
      bundleId = bundleFlag.trim();
    } else {
      bundleId = Input(
        prompt: 'Bundle / App ID (reverse-DNS)',
        defaultValue: 'com.example.$packageName',
        validator: _bundleValidator,
      ).interact();
    }

    final String org;
    if (orgFlag != null) {
      if (orgFlag.trim().isEmpty) {
        _logger.err('--org cannot be empty.');
        return null;
      }
      org = orgFlag.trim();
    } else {
      org = Input(
        prompt: 'Organisation / author',
        defaultValue: 'My Organisation',
        validator: _notEmpty,
      ).interact();
    }

    return (displayName, packageName, bundleId, org);
  }

  static bool _notEmpty(String v) {
    if (v.trim().isEmpty) throw ValidationError('Cannot be empty.');
    return true;
  }

  static bool _packageValidator(String v) {
    if (!isValidPackageName(v)) {
      throw ValidationError(
        'Must be lowercase letters, digits, and underscores '
        '(no leading digit).',
      );
    }
    return true;
  }

  static bool _bundleValidator(String v) {
    if (!isValidBundleId(v)) {
      throw ValidationError(
        'Must be a valid reverse-DNS identifier, e.g. com.acme.myapp.',
      );
    }
    return true;
  }

  /// Replaces the template's large meta-README with a minimal, project-specific
  /// one so the new project documents itself rather than the template.
  Future<void> _writeProjectReadme(
    String dir,
    ProjectConfig config, {
    required bool firebaseEnabled,
  }) async {
    final firebaseNote = firebaseEnabled
        ? '\n> Firebase is not configured yet. Run `flutterfire configure` to '
            'point the app\n> at your own Firebase project before shipping.\n'
        : '';
    final readme = File(p.join(dir, 'README.md'));
    await readme.writeAsString('''
# ${config.displayName}

A Flutter application scaffolded from
[flutter-starter-template](https://github.com/kido-luci/flutter-starter-template)
with `fst create`.

## Getting started

```sh
fvm flutter pub get
fvm flutter run
```
$firebaseNote''');
  }
}
