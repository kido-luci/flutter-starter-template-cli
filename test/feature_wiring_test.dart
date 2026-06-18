import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
import 'package:test/test.dart';

void main() {
  final names = FeatureNames('settings');

  group('addFeatureToPubspec', () {
    test('inserts the workspace entry and dependency before the markers', () {
      const pubspec = '''
workspace:
  - packages/features/profile
  # fst:features — inserts above

dependencies:
  feature_profile: ^0.1.0
  # fst:feature-deps — inserts above
''';
      final out = addFeatureToPubspec(pubspec, names);
      expect(out, contains('  - packages/features/settings\n  # fst:features'));
      expect(out, contains('  feature_settings: ^0.1.0\n  # fst:feature-deps'));
    });
  });

  group('addFeatureToInjection', () {
    test('inserts a sorted import and the ExternalModule before the marker',
        () {
      const injection = '''
import 'package:feature_profile/feature_profile.dart';
import 'package:get_it/get_it.dart';

@InjectableInit(
  externalPackageModulesBefore: [
    ExternalModule(FeatureProfilePackageModule),
    // fst:feature-modules — inserts above
  ],
)
''';
      final out = addFeatureToInjection(injection, names);
      expect(
        out,
        contains(
          "import 'package:feature_profile/feature_profile.dart';\n"
          "import 'package:feature_settings/feature_settings.dart';\n"
          "import 'package:get_it/get_it.dart';",
        ),
      );
      expect(
        out,
        contains(
          '    ExternalModule(FeatureSettingsPackageModule),\n'
          '    // fst:feature-modules',
        ),
      );
    });
  });

  group('addFeatureToFeatures', () {
    test('inserts the import, enabledFeatures entry, and module class', () {
      const features = '''
import 'package:feature_notifications/feature_notifications.dart';
import 'package:go_router/go_router.dart';

const List<FeatureModule> enabledFeatures = [
  _NotificationsModule(),
  // fst:enabled-features — inserts above
];

// fst:feature-module-classes — inserts above

final class _FeatureSync {}
''';
      final out = addFeatureToFeatures(features, names);
      expect(
        out,
        contains(
          "import 'package:feature_notifications/feature_notifications.dart';\n"
          "import 'package:feature_settings/feature_settings.dart';\n"
          "import 'package:go_router/go_router.dart';",
        ),
      );
      expect(out, contains('  _SettingsModule(),\n  // fst:enabled-features'));
      expect(
        out,
        contains('final class _SettingsModule extends FeatureModule {'),
      );
      expect(
        out,
        contains('Iterable<RouteBase> get routes => settingsRoutes;'),
      );
    });

    test('throws a clear error when a marker is missing', () {
      const features = '''
import 'package:go_router/go_router.dart';
const List<FeatureModule> enabledFeatures = <FeatureModule>[];
''';
      expect(
        () => addFeatureToFeatures(features, names),
        throwsA(isA<FeatureWiringException>()),
      );
    });
  });
}
