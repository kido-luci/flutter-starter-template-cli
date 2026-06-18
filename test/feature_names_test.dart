import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
import 'package:test/test.dart';

void main() {
  group('FeatureNames', () {
    test('derives every casing from a single-word name', () {
      final names = FeatureNames('settings');
      expect(names.package, 'feature_settings');
      expect(names.pascal, 'Settings');
      expect(names.camel, 'settings');
      expect(names.kebab, 'settings');
      expect(names.packageModule, 'FeatureSettingsPackageModule');
    });

    test('derives every casing from a multi-word name', () {
      final names = FeatureNames('my_cool_feature');
      expect(names.package, 'feature_my_cool_feature');
      expect(names.pascal, 'MyCoolFeature');
      expect(names.camel, 'myCoolFeature');
      expect(names.kebab, 'my-cool-feature');
      expect(names.packageModule, 'FeatureMyCoolFeaturePackageModule');
    });
  });
}
