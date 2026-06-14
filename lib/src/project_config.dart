/// Collected configuration for a new project.
class ProjectConfig {
  const ProjectConfig({
    required this.displayName,
    required this.packageName,
    required this.bundleId,
    required this.org,
    required this.outputDir,
  });

  /// Human-readable app name shown on the device, e.g. "My Awesome App".
  final String displayName;

  /// Dart package name (snake_case), e.g. "my_awesome_app".
  final String packageName;

  /// Reverse-DNS bundle / application ID, e.g. "com.acme.myapp".
  final String bundleId;

  /// Organisation or author name, e.g. "Acme Inc".
  final String org;

  /// Absolute path of the directory where the project will be created.
  final String outputDir;
}
