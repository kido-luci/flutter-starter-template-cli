import 'dart:io';

import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
import 'package:path/path.dart' as p;
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

  group('applyApiBaseUrl', () {
    late Directory dir;

    String env(String flavor, String url) => '{\n'
        '  "FLAVOR": "$flavor",\n'
        '  "API_BASE_URL": "$url",\n'
        '  "API_TIMEOUT_SECONDS": 20\n'
        '}\n';

    void write(String relative, String content) {
      File(p.join(dir.path, p.joinAll(relative.split('/'))))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    String read(String relative) =>
        File(p.join(dir.path, p.joinAll(relative.split('/'))))
            .readAsStringSync();

    setUp(() => dir = Directory.systemTemp.createTempSync('fst_env_test_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('updates staging and prod, leaves dev untouched', () async {
      write('env/dev.json', env('dev', 'http://localhost:8080'));
      write('env/staging.json', env('staging', 'https://staging.example.com'));
      write('env/prod.json', env('prod', 'https://api.example.com'));

      await applyApiBaseUrl(dir.path, 'https://api.acme.com');

      expect(read('env/staging.json'), contains('https://api.acme.com'));
      expect(read('env/prod.json'), contains('https://api.acme.com'));
      expect(read('env/dev.json'), contains('http://localhost:8080'));
    });

    test('is a no-op when env files are absent', () async {
      await expectLater(
          applyApiBaseUrl(dir.path, 'https://api.acme.com'), completes);
    });
  });
}
