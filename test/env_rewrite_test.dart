import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
import 'package:test/test.dart';

void main() {
  group('isValidHttpUrl', () {
    test('accepts http and https absolute URLs', () {
      expect(isValidHttpUrl('https://api.acme.com'), isTrue);
      expect(isValidHttpUrl('http://localhost:8080'), isTrue);
      expect(isValidHttpUrl('https://api.acme.com/v1'), isTrue);
    });

    test('rejects non-http schemes, missing scheme, and junk', () {
      expect(isValidHttpUrl(''), isFalse);
      expect(isValidHttpUrl('api.acme.com'), isFalse);
      expect(isValidHttpUrl('ftp://api.acme.com'), isFalse);
      expect(isValidHttpUrl('not a url'), isFalse);
    });
  });

  group('setApiBaseUrl', () {
    const env = '{\n'
        '  "FLAVOR": "staging",\n'
        '  "API_BASE_URL": "https://staging-api.example.com",\n'
        '  "API_TIMEOUT_SECONDS": 20\n'
        '}\n';

    test('replaces the URL, preserving other keys and formatting', () {
      expect(
        setApiBaseUrl(env, 'https://api.acme.com'),
        equals('{\n'
            '  "FLAVOR": "staging",\n'
            '  "API_BASE_URL": "https://api.acme.com",\n'
            '  "API_TIMEOUT_SECONDS": 20\n'
            '}\n'),
      );
    });

    test('is idempotent', () {
      final once = setApiBaseUrl(env, 'https://api.acme.com');
      expect(setApiBaseUrl(once, 'https://api.acme.com'), equals(once));
    });

    test('throws when API_BASE_URL is absent', () {
      expect(
        () => setApiBaseUrl('{"FLAVOR": "dev"}', 'https://api.acme.com'),
        throwsFormatException,
      );
    });
  });
}
