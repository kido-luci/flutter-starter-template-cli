import 'dart:io';

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
      expect(addFeatureToPubspec(out, names), out);
    });
  });

  group('feature route contract', () {
    test('accepts absolute static nested paths', () {
      expect(validateFeatureRoutePath('/admin/audit-log'), '/admin/audit-log');
    });

    test('rejects parameters, relative paths, and malformed segments', () {
      for (final path in ['settings', '/settings/:id', '/Settings', '/a//b']) {
        expect(
          () => validateFeatureRoutePath(path),
          throwsA(isA<FeatureWiringException>()),
          reason: path,
        );
      }
    });

    test('rejects path and route-name collisions in actual route files', () {
      final root = Directory.systemTemp.createTempSync('fst-route-collision-');
      addTearDown(() => root.deleteSync(recursive: true));
      final routes = File('${root.path}/lib/app/router.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
@TypedGoRoute<FooRoute>(path: '/settings', name: 'feature-settings')
class FooRoute {}
''');
      expect(routes.existsSync(), isTrue);
      expect(
        () => validateFeatureRouteAvailability(
          root.path,
          names,
          '/settings',
        ),
        throwsA(isA<FeatureWiringException>()),
      );
      expect(
        () => validateFeatureRouteAvailability(
          root.path,
          names,
          '/preferences',
        ),
        throwsA(isA<FeatureWiringException>()),
      );
    });
  });

  group('addFeatureToInjection', () {
    test(
      'inserts a sorted import and the ExternalModule before the marker',
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
      },
    );
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
      expect(out, contains("String get id => 'settings';"));
      expect(
        out,
        contains('Iterable<RouteBase> get routes => settingsRoutes;'),
      );
      expect(removeFeatureFromFeatures(out, names),
          isNot(contains('_SettingsModule')));
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

    test('anchors the first package import before a relative import', () {
      const features = '''
import 'feature_module.dart';

const enabledFeatures = [
  // fst:enabled-features
];

// fst:feature-module-classes
''';
      final out = addFeatureToFeatures(features, names);
      expect(
        out,
        contains(
          "import 'package:feature_settings/feature_settings.dart';\n"
          "import 'package:go_router/go_router.dart';\n"
          "import 'feature_module.dart';",
        ),
      );
    });
  });

  test('addFeatureToLayeringTest registers a rank-four feature once', () {
    const layering = '''
const layers = <String, int>{
  'feature_home': 4,
  // fst:feature-layers
};
''';
    final once = addFeatureToLayeringTest(layering, names);
    expect(once, contains("  'feature_settings': 4,"));
    expect(addFeatureToLayeringTest(once, names), once);
  });
}
