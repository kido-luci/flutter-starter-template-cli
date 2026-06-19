import 'dart:io';

import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('setFirebaseEnabled', () {
    const enabledSource = 'const bool kFirebaseEnabled = true;\n';
    const disabledSource = 'const bool kFirebaseEnabled = false;\n';

    test('flips the flag to false', () {
      expect(
        setFirebaseEnabled(enabledSource, enabled: false),
        equals(disabledSource),
      );
    });

    test('flips the flag to true', () {
      expect(
        setFirebaseEnabled(disabledSource, enabled: true),
        equals(enabledSource),
      );
    });

    test('is idempotent', () {
      expect(
        setFirebaseEnabled(disabledSource, enabled: false),
        equals(disabledSource),
      );
    });

    test('leaves surrounding content intact', () {
      const src = '// header\nconst bool kFirebaseEnabled = true;\n// footer\n';
      expect(
        setFirebaseEnabled(src, enabled: false),
        equals('// header\nconst bool kFirebaseEnabled = false;\n// footer\n'),
      );
    });
  });

  group('replaceMarkedExpression', () {
    // Mirrors the real module: the marker appears in BOTH the doc comment and
    // the (wrapped) binding line.
    const analyticsModule =
        '  /// Rewritten at the `// fst:analytics-impl` marker.\n'
        '  AnalyticsService provideAnalyticsService() =>\n'
        '      FirebaseAnalyticsService(FirebaseAnalytics.instance); '
        '// fst:analytics-impl\n';

    test('swaps the wrapped binding, keeping indentation and marker', () {
      final result = replaceMarkedExpression(
        analyticsModule,
        marker: 'fst:analytics-impl',
        replacement: 'const NoOpAnalyticsService();',
      );
      expect(
        result,
        equals('  /// Rewritten at the `// fst:analytics-impl` marker.\n'
            '  AnalyticsService provideAnalyticsService() =>\n'
            '      const NoOpAnalyticsService(); // fst:analytics-impl\n'),
      );
    });

    test('ignores the marker inside a doc comment', () {
      final result = replaceMarkedExpression(
        analyticsModule,
        marker: 'fst:analytics-impl',
        replacement: 'const NoOpAnalyticsService();',
      );
      // The doc line is untouched; only one binding line is rewritten.
      expect(result, contains('  /// Rewritten at the'));
      expect('NoOpAnalyticsService('.allMatches(result).length, equals(1));
    });

    test('preserves an arrow prefix on a single-line binding', () {
      const crashModule = '  /// Rewritten at the `// fst:crash-impl` marker.\n'
          '  CrashReporter provideCrashReporter() => '
          'FirebaseCrashReporter(); // fst:crash-impl\n';
      final result = replaceMarkedExpression(
        crashModule,
        marker: 'fst:crash-impl',
        replacement: 'const NoOpCrashReporter();',
      );
      expect(
        result,
        equals('  /// Rewritten at the `// fst:crash-impl` marker.\n'
            '  CrashReporter provideCrashReporter() => '
            'const NoOpCrashReporter(); // fst:crash-impl\n'),
      );
    });

    test('is idempotent', () {
      final once = replaceMarkedExpression(
        analyticsModule,
        marker: 'fst:analytics-impl',
        replacement: 'const NoOpAnalyticsService();',
      );
      final twice = replaceMarkedExpression(
        once,
        marker: 'fst:analytics-impl',
        replacement: 'const NoOpAnalyticsService();',
      );
      expect(twice, equals(once));
    });

    test('throws when the marker is absent from any code line', () {
      expect(
        () => replaceMarkedExpression(
          'no marker here\n',
          marker: 'fst:analytics-impl',
          replacement: 'const NoOpAnalyticsService();',
        ),
        throwsA(isA<FirebaseRewriteException>()),
      );
    });
  });

  group('removeFirebaseGradlePlugins', () {
    const gradle = 'plugins {\n'
        '    id("com.android.application")\n'
        '    id("kotlin-android")\n'
        '    id("com.google.gms.google-services")\n'
        '    id("com.google.firebase.firebase-perf")\n'
        '    id("com.google.firebase.crashlytics")\n'
        '    id("dev.flutter.flutter-gradle-plugin")\n'
        '}\n';

    test('removes the three Firebase plugins, keeps the rest', () {
      expect(
        removeFirebaseGradlePlugins(gradle),
        equals('plugins {\n'
            '    id("com.android.application")\n'
            '    id("kotlin-android")\n'
            '    id("dev.flutter.flutter-gradle-plugin")\n'
            '}\n'),
      );
    });

    test('is idempotent', () {
      final once = removeFirebaseGradlePlugins(gradle);
      expect(removeFirebaseGradlePlugins(once), equals(once));
    });

    test('keeps the Flutter Gradle plugin', () {
      expect(
        removeFirebaseGradlePlugins(gradle),
        contains('dev.flutter.flutter-gradle-plugin'),
      );
    });
  });

  group('disableFirebase', () {
    late Directory dir;

    void write(String relative, String content) {
      final file = File(p.join(dir.path, p.joinAll(relative.split('/'))))
        ..parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    String read(String relative) =>
        File(p.join(dir.path, p.joinAll(relative.split('/'))))
            .readAsStringSync();

    bool exists(String relative) =>
        File(p.join(dir.path, p.joinAll(relative.split('/')))).existsSync();

    setUp(() {
      dir = Directory.systemTemp.createTempSync('fst_firebase_test_');
      write('lib/app/firebase.dart', 'const bool kFirebaseEnabled = true;\n');
      write(
        'packages/analytics/lib/src/analytics_module.dart',
        '  /// Rewritten at the `// fst:analytics-impl` marker.\n'
            '  AnalyticsService provideAnalyticsService() =>\n'
            '      FirebaseAnalyticsService(FirebaseAnalytics.instance); '
            '// fst:analytics-impl\n',
      );
      write(
        'packages/app_platform/lib/src/crash/crash_module.dart',
        '  /// Rewritten at the `// fst:crash-impl` marker.\n'
            '  CrashReporter provideCrashReporter() => '
            'FirebaseCrashReporter(); // fst:crash-impl\n',
      );
      write(
        'android/app/build.gradle.kts',
        'plugins {\n'
            '    id("com.google.gms.google-services")\n'
            '    id("com.google.firebase.firebase-perf")\n'
            '    id("com.google.firebase.crashlytics")\n'
            '    id("dev.flutter.flutter-gradle-plugin")\n'
            '}\n',
      );
      write('android/app/google-services.json', '{}');
      write('ios/Runner/GoogleService-Info.plist', '<plist></plist>');
      write('firebase.json', '{}');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('flips the flag, swaps bindings, strips gradle, deletes native',
        () async {
      await disableFirebase(dir.path);

      expect(
          read('lib/app/firebase.dart'), contains('kFirebaseEnabled = false'));
      expect(read('packages/analytics/lib/src/analytics_module.dart'),
          contains('const NoOpAnalyticsService(); // fst:analytics-impl'));
      expect(read('packages/app_platform/lib/src/crash/crash_module.dart'),
          contains('const NoOpCrashReporter(); // fst:crash-impl'));

      final gradle = read('android/app/build.gradle.kts');
      expect(gradle, isNot(contains('google-services')));
      expect(gradle, isNot(contains('crashlytics')));
      expect(gradle, contains('dev.flutter.flutter-gradle-plugin'));

      expect(exists('android/app/google-services.json'), isFalse);
      expect(exists('ios/Runner/GoogleService-Info.plist'), isFalse);
      expect(exists('firebase.json'), isFalse);
    });
  });
}
