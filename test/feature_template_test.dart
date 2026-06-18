import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
import 'package:test/test.dart';

void main() {
  group('featureFiles', () {
    final files = featureFiles(FeatureNames('settings'));

    test('produces the expected scaffold file set', () {
      expect(
        files.keys,
        containsAll(<String>[
          'pubspec.yaml',
          'lib/feature_settings.dart',
          'lib/src/di.dart',
          'lib/src/locator.dart',
          'lib/src/presentation/bloc/settings_cubit.dart',
          'lib/src/presentation/bloc/settings_state.dart',
          'lib/src/presentation/screens/settings_screen.dart',
          'lib/src/presentation/settings_routes.dart',
          'test/presentation/settings_routes_test.dart',
        ]),
      );
    });

    test('pubspec declares the feature package name', () {
      expect(files['pubspec.yaml'], contains('name: feature_settings'));
    });

    test('barrel exports the generated package module', () {
      expect(
        files['lib/feature_settings.dart'],
        contains(
          "export 'src/di.module.dart' show FeatureSettingsPackageModule;",
        ),
      );
    });

    test('di anchor uses the feature-specific init function', () {
      expect(files['lib/src/di.dart'], contains('void initSettingsFeature()'));
    });

    test('routes file mounts the screen at the kebab path', () {
      final routes = files['lib/src/presentation/settings_routes.dart']!;
      expect(routes, contains("static const root = '/settings';"));
      expect(routes, contains('List<RouteBase> get settingsRoutes'));
    });
  });
}
