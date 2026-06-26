import 'dart:io';

import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // ── normaliseSeedColor ─────────────────────────────────────────────────────

  group('normaliseSeedColor', () {
    test('accepts #RRGGBB and returns uppercase', () {
      expect(normaliseSeedColor('#ff5722'), equals('#FF5722'));
      expect(normaliseSeedColor('#FF5722'), equals('#FF5722'));
      expect(normaliseSeedColor('#095D9E'), equals('#095D9E'));
    });

    test('accepts RRGGBB without leading # and normalises', () {
      expect(normaliseSeedColor('ff5722'), equals('#FF5722'));
      expect(normaliseSeedColor('FF5722'), equals('#FF5722'));
    });

    test('rejects values with wrong digit count', () {
      expect(normaliseSeedColor('#FFF'), isNull);
      expect(normaliseSeedColor('#FFFFF'), isNull);
      expect(normaliseSeedColor('#FFFFFFF'), isNull);
      expect(normaliseSeedColor(''), isNull);
    });

    test('rejects non-hex characters', () {
      expect(normaliseSeedColor('#GGGGGG'), isNull);
      expect(normaliseSeedColor('not-hex'), isNull);
    });
  });

  // ── isValidFontName ────────────────────────────────────────────────────────

  group('isValidFontName', () {
    test('accepts lowerCamelCase and PascalCase identifiers', () {
      expect(isValidFontName('roboto'), isTrue);
      expect(isValidFontName('openSans'), isTrue);
      expect(isValidFontName('lato'), isTrue);
      expect(isValidFontName('Roboto'), isTrue);
    });

    test('rejects empty string', () {
      expect(isValidFontName(''), isFalse);
    });

    test('rejects names with non-identifier characters', () {
      expect(isValidFontName('open-sans'), isFalse);
      expect(isValidFontName('open sans'), isFalse);
      expect(isValidFontName('123font'), isFalse);
    });
  });

  // ── setThemeScheme ─────────────────────────────────────────────────────────

  group('setThemeScheme', () {
    const themeState = 'class ThemeState {\n'
        '  static const FlexScheme defaultScheme = FlexScheme.bahamaBlue;\n'
        '}\n';

    test('replaces the scheme name', () {
      expect(
        setThemeScheme(themeState, 'deepPurple'),
        equals('class ThemeState {\n'
            '  static const FlexScheme defaultScheme = FlexScheme.deepPurple;\n'
            '}\n'),
      );
    });

    test('is idempotent', () {
      final once = setThemeScheme(themeState, 'deepPurple');
      expect(setThemeScheme(once, 'deepPurple'), equals(once));
    });

    test('throws when anchor is absent', () {
      expect(
        () => setThemeScheme('class ThemeState {}', 'deepPurple'),
        throwsA(isA<BrandingRewriteException>()),
      );
    });
  });

  // ── setBrandColor ──────────────────────────────────────────────────────────

  group('setBrandColor', () {
    const pubspec = 'flutter_launcher_icons:\n'
        '  adaptive_icon_background: "#095D9E"\n'
        '  web:\n'
        '    background_color: "#095D9E"\n'
        '    theme_color: "#095D9E"\n';

    test('replaces all three occurrences', () {
      final result = setBrandColor(pubspec, '#FF5722');
      expect(
          result,
          equals('flutter_launcher_icons:\n'
              '  adaptive_icon_background: "#FF5722"\n'
              '  web:\n'
              '    background_color: "#FF5722"\n'
              '    theme_color: "#FF5722"\n'));
      expect('#095D9E'.allMatches(result).length, equals(0));
      expect('#FF5722'.allMatches(result).length, equals(3));
    });

    test('is idempotent', () {
      final once = setBrandColor(pubspec, '#FF5722');
      expect(setBrandColor(once, '#FF5722'), equals(once));
    });

    test('throws when anchor is absent', () {
      expect(
        () => setBrandColor('name: myapp\n', '#FF5722'),
        throwsA(isA<BrandingRewriteException>()),
      );
    });
  });

  // ── setAppFont ─────────────────────────────────────────────────────────────

  group('setAppFont', () {
    const appTheme = 'static ThemeData light() {\n'
        '  return FlexThemeData.light(\n'
        '    textTheme: GoogleFonts.interTextTheme(),\n'
        '  );\n'
        '}\n'
        'static ThemeData dark() {\n'
        '  return FlexThemeData.dark(\n'
        '    textTheme: GoogleFonts.interTextTheme(),\n'
        '  );\n'
        '}\n';

    test('replaces both TextTheme calls', () {
      final result = setAppFont(appTheme, 'roboto');
      expect(result, contains('GoogleFonts.robotoTextTheme()'));
      expect(
          'GoogleFonts.robotoTextTheme()'.allMatches(result).length, equals(2));
      expect(result, isNot(contains('GoogleFonts.interTextTheme()')));
    });

    test('is idempotent', () {
      final once = setAppFont(appTheme, 'roboto');
      expect(setAppFont(once, 'roboto'), equals(once));
    });

    test('throws when anchor is absent', () {
      expect(
        () => setAppFont('class AppTheme {}', 'roboto'),
        throwsA(isA<BrandingRewriteException>()),
      );
    });
  });

  // ── applyBranding (integration — writes real files) ────────────────────────

  group('applyBranding', () {
    late Directory dir;

    void write(String relative, String content) {
      File(p.join(dir.path, p.joinAll(relative.split('/'))))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    String read(String relative) =>
        File(p.join(dir.path, p.joinAll(relative.split('/'))))
            .readAsStringSync();

    setUp(
      () => dir = Directory.systemTemp.createTempSync('fst_branding_test_'),
    );
    tearDown(() => dir.deleteSync(recursive: true));

    test('applies all three rewrites', () async {
      write(
        'packages/theme/lib/src/theme_state.dart',
        'class ThemeState {\n'
            '  static const FlexScheme defaultScheme = FlexScheme.bahamaBlue;\n'
            '}\n',
      );
      write(
        'pubspec.yaml',
        'flutter_launcher_icons:\n'
            '  adaptive_icon_background: "#095D9E"\n'
            '  web:\n'
            '    background_color: "#095D9E"\n'
            '    theme_color: "#095D9E"\n',
      );
      write(
        'packages/app_ui/lib/src/theme/app_theme.dart',
        'textTheme: GoogleFonts.interTextTheme(),\n'
            'textTheme: GoogleFonts.interTextTheme(),\n',
      );

      await applyBranding(
        dir.path,
        scheme: 'deepPurple',
        seedColor: '#FF5722',
        font: 'roboto',
      );

      expect(
        read('packages/theme/lib/src/theme_state.dart'),
        contains('FlexScheme.deepPurple'),
      );
      expect(read('pubspec.yaml'), isNot(contains('#095D9E')));
      expect('#FF5722'.allMatches(read('pubspec.yaml')).length, equals(3));
      expect(
        read('packages/app_ui/lib/src/theme/app_theme.dart'),
        isNot(contains('GoogleFonts.interTextTheme()')),
      );
      expect(
        'GoogleFonts.robotoTextTheme()'
            .allMatches(
              read('packages/app_ui/lib/src/theme/app_theme.dart'),
            )
            .length,
        equals(2),
      );
    });

    test('is a no-op for null flags (skips all files)', () async {
      // No files written — applyBranding must not touch anything.
      await expectLater(applyBranding(dir.path), completes);
    });

    test('throws BrandingRewriteException when a target file is missing', () {
      // Only write pubspec, omit the others.
      write(
        'pubspec.yaml',
        'adaptive_icon_background: "#095D9E"\n'
            'background_color: "#095D9E"\n'
            'theme_color: "#095D9E"\n',
      );
      expect(
        () => applyBranding(dir.path, scheme: 'deepPurple'),
        throwsA(isA<BrandingRewriteException>()),
      );
    });
  });
}
