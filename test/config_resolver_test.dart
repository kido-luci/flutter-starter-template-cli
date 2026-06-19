import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
import 'package:test/test.dart';

void main() {
  group('resolveProjectConfig', () {
    test('resolves all four flags into a ConfigOk', () {
      final result = resolveProjectConfig(
        name: 'Acme App',
        packageName: 'acme_app',
        bundleId: 'com.acme.app',
        org: 'Acme Inc',
      );

      expect(result, isA<ConfigOk>());
      final ok = result as ConfigOk;
      expect(ok.displayName, equals('Acme App'));
      expect(ok.packageName, equals('acme_app'));
      expect(ok.bundleId, equals('com.acme.app'));
      expect(ok.org, equals('Acme Inc'));
    });

    test('derives package name from --name when --package-name is omitted', () {
      final result = resolveProjectConfig(
        name: 'My Awesome App',
        packageName: null,
        bundleId: 'com.acme.app',
        org: 'Acme Inc',
      );

      expect(result, isA<ConfigOk>());
      expect((result as ConfigOk).packageName, equals('my_awesome_app'));
    });

    test('errors when --name is missing', () {
      final result = resolveProjectConfig(
        name: null,
        packageName: null,
        bundleId: 'com.acme.app',
        org: 'Acme Inc',
      );

      expect(result, isA<ConfigError>());
      expect((result as ConfigError).message, contains('--name'));
    });

    test('errors when --name is blank', () {
      final result = resolveProjectConfig(
        name: '   ',
        packageName: null,
        bundleId: 'com.acme.app',
        org: 'Acme Inc',
      );

      expect(result, isA<ConfigError>());
      expect((result as ConfigError).message, contains('--name'));
    });

    test('errors when --bundle-id is missing', () {
      final result = resolveProjectConfig(
        name: 'Acme App',
        packageName: 'acme_app',
        bundleId: null,
        org: 'Acme Inc',
      );

      expect(result, isA<ConfigError>());
      expect((result as ConfigError).message, contains('--bundle-id'));
    });

    test('errors when --org is missing', () {
      final result = resolveProjectConfig(
        name: 'Acme App',
        packageName: 'acme_app',
        bundleId: 'com.acme.app',
        org: null,
      );

      expect(result, isA<ConfigError>());
      expect((result as ConfigError).message, contains('--org'));
    });

    test('errors when --bundle-id is blank', () {
      final result = resolveProjectConfig(
        name: 'Acme App',
        packageName: 'acme_app',
        bundleId: '   ',
        org: 'Acme Inc',
      );

      expect(result, isA<ConfigError>());
      expect((result as ConfigError).message, contains('--bundle-id'));
    });

    test('errors when --org is blank', () {
      final result = resolveProjectConfig(
        name: 'Acme App',
        packageName: 'acme_app',
        bundleId: 'com.acme.app',
        org: '   ',
      );

      expect(result, isA<ConfigError>());
      expect((result as ConfigError).message, contains('--org'));
    });

    test('errors when an explicit --package-name is invalid', () {
      final result = resolveProjectConfig(
        name: 'Acme App',
        packageName: 'Acme-App',
        bundleId: 'com.acme.app',
        org: 'Acme Inc',
      );

      expect(result, isA<ConfigError>());
      expect((result as ConfigError).message, contains('--package-name'));
    });

    test('errors when --bundle-id is invalid', () {
      final result = resolveProjectConfig(
        name: 'Acme App',
        packageName: 'acme_app',
        bundleId: 'com',
        org: 'Acme Inc',
      );

      expect(result, isA<ConfigError>());
      expect((result as ConfigError).message, contains('--bundle-id'));
    });

    test('errors when --name yields no valid package name', () {
      final result = resolveProjectConfig(
        name: '!!!',
        packageName: null,
        bundleId: 'com.acme.app',
        org: 'Acme Inc',
      );

      expect(result, isA<ConfigError>());
      expect((result as ConfigError).message, contains('--package-name'));
    });

    test('trims surrounding whitespace from accepted values', () {
      final result = resolveProjectConfig(
        name: '  Acme App  ',
        packageName: '  acme_app  ',
        bundleId: '  com.acme.app  ',
        org: '  Acme Inc  ',
      );

      expect(result, isA<ConfigOk>());
      final ok = result as ConfigOk;
      expect(ok.displayName, equals('Acme App'));
      expect(ok.packageName, equals('acme_app'));
      expect(ok.bundleId, equals('com.acme.app'));
      expect(ok.org, equals('Acme Inc'));
    });
  });
}
