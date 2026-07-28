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

  group('removeImportLine', () {
    test('removes the matching bare import', () {
      const src = "import 'package:firebase_analytics/firebase_analytics.dart';"
          '\n'
          "import 'package:injectable/injectable.dart';\n";
      expect(
        removeImportLine(
            src, 'package:firebase_analytics/firebase_analytics.dart'),
        equals("import 'package:injectable/injectable.dart';\n"),
      );
    });

    test('leaves a re-export or aliased import alone', () {
      const src =
          "export 'package:firebase_analytics/firebase_analytics.dart';\n"
          "import 'package:firebase_analytics/firebase_analytics.dart' as fa;\n";
      expect(
        removeImportLine(
            src, 'package:firebase_analytics/firebase_analytics.dart'),
        equals(src),
      );
    });

    test('is a no-op when the import is absent, and is idempotent', () {
      const src = "import 'package:injectable/injectable.dart';\n";
      final once = removeImportLine(src, 'package:firebase_analytics/x.dart');
      expect(once, equals(src));
      expect(removeImportLine(once, 'package:firebase_analytics/x.dart'),
          equals(src));
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
        "import 'package:firebase_analytics/firebase_analytics.dart';\n"
            "import 'package:injectable/injectable.dart';\n"
            '\n'
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
      write(
        'ios/Runner.xcodeproj/project.pbxproj',
        '\t\tAAA /* GoogleService-Info.plist in Resources */ = {};\n'
            '\t\tBBB /* Runner.app */ = {};\n',
      );
      write(
        '.github/workflows/ci.yml',
        'steps:\n'
            '      # fst:firebase:start\n'
            '      - name: Generate placeholder GoogleService-Info.plist\n'
            '      # fst:firebase:end\n'
            '      - name: Build\n',
      );
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('flips the flag, swaps bindings, strips gradle, deletes native',
        () async {
      await disableFirebase(dir.path);

      expect(
          read('lib/app/firebase.dart'), contains('kFirebaseEnabled = false'));
      final analyticsModule =
          read('packages/analytics/lib/src/analytics_module.dart');
      expect(analyticsModule,
          contains('const NoOpAnalyticsService(); // fst:analytics-impl'));
      // The swapped-in no-op leaves nothing referencing FirebaseAnalytics, so
      // the import must go too or the scaffold trips `unused_import`.
      expect(analyticsModule, isNot(contains('firebase_analytics')));
      expect(analyticsModule, contains('injectable'));
      expect(read('packages/app_platform/lib/src/crash/crash_module.dart'),
          contains('const NoOpCrashReporter(); // fst:crash-impl'));

      final gradle = read('android/app/build.gradle.kts');
      expect(gradle, isNot(contains('google-services')));
      expect(gradle, isNot(contains('crashlytics')));
      expect(gradle, contains('dev.flutter.flutter-gradle-plugin'));

      expect(exists('android/app/google-services.json'), isFalse);
      expect(exists('ios/Runner/GoogleService-Info.plist'), isFalse);

      // Deleting the plist is not enough: Xcode fails the build on a missing
      // input, so the project must stop referencing it too.
      final pbxproj = read('ios/Runner.xcodeproj/project.pbxproj');
      expect(pbxproj, isNot(contains('GoogleService-Info')));
      expect(pbxproj, contains('Runner.app'));

      // And the CI step that fabricated a placeholder for that reference goes
      // with it.
      final ci = read('.github/workflows/ci.yml');
      expect(ci, isNot(contains('Generate placeholder')));
      expect(ci, contains('- name: Build'));
      expect(exists('firebase.json'), isFalse);
    });
  });

  _iosBuildInputTests();
  _keepFirebaseTests();
}

void _iosBuildInputTests() {
  group('removeIosFirebaseResource', () {
    test('drops every line that names the plist', () {
      const pbxproj = '''
		AAA /* GoogleService-Info.plist in Resources */ = {isa = PBXBuildFile; };
		BBB /* Runner.app */ = {isa = PBXFileReference; };
		CCC /* GoogleService-Info.plist */ = {isa = PBXFileReference; };
			children = (
				CCC /* GoogleService-Info.plist */,
				DDD /* Assets.xcassets */,
			);
			files = (
				AAA /* GoogleService-Info.plist in Resources */,
			);
''';

      final result = removeIosFirebaseResource(pbxproj);

      expect(result, isNot(contains('GoogleService-Info')));
      expect(result, contains('Runner.app'));
      expect(result, contains('Assets.xcassets'));
    });

    test('leaves a project that never mentioned it untouched', () {
      const pbxproj =
          '\t\tBBB /* Runner.app */ = {isa = PBXFileReference; };\n';

      expect(removeIosFirebaseResource(pbxproj), equals(pbxproj));
    });
  });

  group('removeFirebaseRegions', () {
    test('removes a block inclusive of its markers', () {
      const src = 'steps:\n'
          '      # fst:firebase:start\n'
          '      - name: Generate placeholder\n'
          '      # fst:firebase:end\n'
          '      - name: Build\n';

      expect(
        removeFirebaseRegions(src),
        equals('steps:\n      - name: Build\n'),
      );
    });

    test('throws on an unclosed marker', () {
      expect(
        () => removeFirebaseRegions('a\n# fst:firebase:start\nb\n'),
        throwsFormatException,
      );
    });
  });
}

void _keepFirebaseTests() {
  group('keepFirebase', () {
    late Directory dir;

    String ciPath() => p.join(dir.path, '.github', 'workflows', 'ci.yml');

    setUp(
      () => dir = Directory.systemTemp.createTempSync('fst_keep_firebase_'),
    );
    tearDown(() => dir.deleteSync(recursive: true));

    test('clears the markers and keeps every step', () async {
      File(ciPath())
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          'steps:\n'
          '      # fst:firebase:start\n'
          '      - name: Generate placeholder google-services.json\n'
          '      # fst:firebase:end\n'
          '      - name: Build\n',
        );

      await keepFirebase(dir.path);

      final ci = File(ciPath()).readAsStringSync();
      expect(ci, isNot(contains('fst:firebase')));
      expect(ci, contains('Generate placeholder google-services.json'));
      expect(ci, contains('- name: Build'));
    });

    test('is a no-op when there is no workflow', () async {
      // A scaffold can legitimately have no CI file; that is not an error.
      await expectLater(keepFirebase(dir.path), completes);
      expect(File(ciPath()).existsSync(), isFalse);
    });

    test('is idempotent', () async {
      File(ciPath())
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          'steps:\n'
          '      # fst:firebase:start\n'
          '      - name: Build\n'
          '      # fst:firebase:end\n',
        );

      await keepFirebase(dir.path);
      final once = File(ciPath()).readAsStringSync();
      await keepFirebase(dir.path);

      expect(File(ciPath()).readAsStringSync(), equals(once));
    });
  });

  group('expandFirebaseRegions', () {
    test('keeps the content and drops only the markers', () {
      const src = 'steps:\n'
          '      # fst:firebase:start\n'
          '      - name: Generate placeholder\n'
          '      # fst:firebase:end\n';

      expect(
        expandFirebaseRegions(src),
        equals('steps:\n      - name: Generate placeholder\n'),
      );
    });
  });
}
