import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
import 'package:test/test.dart';

void main() {
  group('isValidPackageName', () {
    test('accepts valid names', () {
      expect(isValidPackageName('my_app'), isTrue);
      expect(isValidPackageName('myapp'), isTrue);
      expect(isValidPackageName('my_app_123'), isTrue);
    });

    test('rejects invalid names', () {
      expect(isValidPackageName(''), isFalse);
      expect(isValidPackageName('1app'), isFalse);
      expect(isValidPackageName('My App'), isFalse);
      expect(isValidPackageName('my-app'), isFalse);
    });
  });

  group('isValidBundleId', () {
    test('accepts valid bundle IDs', () {
      expect(isValidBundleId('com.example.app'), isTrue);
      expect(isValidBundleId('com.acme.myapp'), isTrue);
      expect(isValidBundleId('io.github.user.project'), isTrue);
    });

    test('rejects invalid bundle IDs', () {
      expect(isValidBundleId('com'), isFalse);
      expect(isValidBundleId('1com.example.app'), isFalse);
      expect(isValidBundleId('com.example.my-app'), isFalse);
      expect(isValidBundleId(''), isFalse);
    });
  });

  group('toSnakeCase', () {
    test('converts display name to snake_case', () {
      expect(toSnakeCase('My Awesome App'), equals('my_awesome_app'));
      expect(toSnakeCase('My App'), equals('my_app'));
      expect(toSnakeCase('App'), equals('app'));
      expect(toSnakeCase('My  App'), equals('my_app'));
    });
  });
}
