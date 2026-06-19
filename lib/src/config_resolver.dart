import 'validators.dart';

/// Outcome of resolving non-interactive (`--yes`) inputs into the four project
/// identity fields, or the first problem encountered.
///
/// Pure and IO-free so the resolution rules can be unit-tested without a TTY.
/// `--output-dir` resolution and absolutising are left to the command, which
/// owns the filesystem and current-directory context.
sealed class ConfigResult {
  const ConfigResult();
}

/// A successful resolution carrying the four validated identity fields.
final class ConfigOk extends ConfigResult {
  const ConfigOk({
    required this.displayName,
    required this.packageName,
    required this.bundleId,
    required this.org,
  });

  /// Human-readable app name, e.g. "My Awesome App".
  final String displayName;

  /// Dart package name (snake_case), e.g. "my_awesome_app".
  final String packageName;

  /// Reverse-DNS bundle / application ID, e.g. "com.acme.myapp".
  final String bundleId;

  /// Organisation or author name, e.g. "Acme Inc".
  final String org;
}

/// A failed resolution carrying a user-facing [message] explaining what to fix.
final class ConfigError extends ConfigResult {
  const ConfigError(this.message);

  /// The problem, phrased for the CLI to print before exiting non-zero.
  final String message;
}

/// Resolves the four identity inputs for non-interactive `fst create --yes`.
///
/// `--name`, `--bundle-id`, and `--org` are required (their interactive
/// defaults are placeholders we must never scaffold). `--package-name` is
/// optional: when omitted it is derived from [name] via [toSnakeCase].
ConfigResult resolveProjectConfig({
  required String? name,
  required String? packageName,
  required String? bundleId,
  required String? org,
}) {
  final displayName = name?.trim() ?? '';
  if (displayName.isEmpty) {
    return const ConfigError('--name is required with --yes.');
  }

  final bundle = bundleId?.trim() ?? '';
  if (bundle.isEmpty) {
    return const ConfigError('--bundle-id is required with --yes.');
  }

  final organisation = org?.trim() ?? '';
  if (organisation.isEmpty) {
    return const ConfigError('--org is required with --yes.');
  }

  final explicitPackage = packageName?.trim() ?? '';
  final resolvedPackage =
      explicitPackage.isEmpty ? toSnakeCase(displayName) : explicitPackage;
  if (!isValidPackageName(resolvedPackage)) {
    return ConfigError(
      explicitPackage.isEmpty
          ? '--name "$displayName" does not yield a valid package name; '
              'pass --package-name explicitly (lowercase letters, digits, '
              'and underscores, no leading digit).'
          : 'Invalid --package-name "$explicitPackage": must be lowercase '
              'letters, digits, and underscores (no leading digit).',
    );
  }

  if (!isValidBundleId(bundle)) {
    return ConfigError(
      'Invalid --bundle-id "$bundle": must be a reverse-DNS identifier, '
      'e.g. com.acme.myapp.',
    );
  }

  return ConfigOk(
    displayName: displayName,
    packageName: resolvedPackage,
    bundleId: bundle,
    org: organisation,
  );
}
