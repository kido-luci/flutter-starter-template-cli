/// Derives every casing the scaffolder and wiring need from one snake_case
/// feature name.
///
/// `settings` → package `feature_settings`, class prefix `Settings`, route
/// getter `settingsRoutes`, path `/settings`. `my_feature` → `feature_my_feature`,
/// `MyFeature`, `myFeatureRoutes`, `/my-feature`.
class FeatureNames {
  FeatureNames(this.snake);

  /// The canonical snake_case name, e.g. `my_feature`.
  final String snake;

  /// Dart package name, e.g. `feature_my_feature`.
  String get package => 'feature_$snake';

  /// PascalCase prefix for class names, e.g. `MyFeature`.
  String get pascal => snake
      .split('_')
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join();

  /// camelCase prefix for identifiers, e.g. `myFeature`.
  String get camel {
    final p = pascal;
    return p.isEmpty ? p : '${p[0].toLowerCase()}${p.substring(1)}';
  }

  /// kebab-case form used in the route path, e.g. `my-feature`.
  String get kebab => snake.replaceAll('_', '-');

  /// The injectable micro-package module type, e.g. `FeatureMyFeaturePackageModule`.
  String get packageModule => 'Feature${pascal}PackageModule';
}
