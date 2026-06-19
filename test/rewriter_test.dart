import 'dart:io';

import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('rewriteProject', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('fst_test_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('replaces package name in pubspec.yaml', () async {
      final pubspec = File(p.join(tempDir.path, 'pubspec.yaml'));
      await pubspec.writeAsString('name: flutter_starter_template\n');

      final config = ProjectConfig(
        displayName: 'My App',
        packageName: 'my_app',
        bundleId: 'com.acme.myapp',
        org: 'Acme',
        outputDir: tempDir.path,
      );

      await rewriteProject(tempDir.path, config);

      expect(await pubspec.readAsString(), contains('name: my_app'));
    });

    test('replaces Android bundle ID in build.gradle.kts', () async {
      final gradle = File(
        p.join(tempDir.path, 'android', 'app', 'build.gradle.kts'),
      );
      await gradle.parent.create(recursive: true);
      await gradle.writeAsString(
        'applicationId = "com.lucistudio.flutter_starter_template"\n',
      );

      final config = ProjectConfig(
        displayName: 'My App',
        packageName: 'my_app',
        bundleId: 'com.acme.myapp',
        org: 'Acme',
        outputDir: tempDir.path,
      );

      await rewriteProject(tempDir.path, config);

      expect(
        await gradle.readAsString(),
        contains('applicationId = "com.acme.myapp"'),
      );
    });

    test('replaces display name in build.gradle.kts', () async {
      final gradle = File(
        p.join(tempDir.path, 'android', 'app', 'build.gradle.kts'),
      );
      await gradle.parent.create(recursive: true);
      await gradle.writeAsString(
        'resValue("string", "app_name", "Flutter Starter")\n',
      );

      final config = ProjectConfig(
        displayName: 'Acme App',
        packageName: 'acme_app',
        bundleId: 'com.acme.app',
        org: 'Acme',
        outputDir: tempDir.path,
      );

      await rewriteProject(tempDir.path, config);

      expect(
        await gradle.readAsString(),
        contains('"Acme App"'),
      );
    });

    test('does not rewrite files under .git/', () async {
      final gitConfig = File(p.join(tempDir.path, '.git', 'config'));
      await gitConfig.parent.create(recursive: true);
      await gitConfig.writeAsString('url = flutter_starter_template');

      final config = ProjectConfig(
        displayName: 'My App',
        packageName: 'my_app',
        bundleId: 'com.acme.myapp',
        org: 'Acme',
        outputDir: tempDir.path,
      );

      await rewriteProject(tempDir.path, config);

      expect(
        await gitConfig.readAsString(),
        'url = flutter_starter_template',
        reason: '.git internals must be left untouched',
      );
    });

    test('moves MainActivity.kt to new package path', () async {
      final oldKotlinDir = Directory(
        p.join(
          tempDir.path,
          'android',
          'app',
          'src',
          'main',
          'kotlin',
          'com',
          'lucistudio',
          'flutter_starter_template',
        ),
      );
      await oldKotlinDir.create(recursive: true);

      final mainActivity = File(p.join(oldKotlinDir.path, 'MainActivity.kt'));
      await mainActivity.writeAsString(
        'package com.lucistudio.flutter_starter_template\n\nclass MainActivity',
      );

      final config = ProjectConfig(
        displayName: 'Acme App',
        packageName: 'acme_app',
        bundleId: 'com.acme.app',
        org: 'Acme',
        outputDir: tempDir.path,
      );

      await rewriteProject(tempDir.path, config);

      final newPath = p.join(
        tempDir.path,
        'android',
        'app',
        'src',
        'main',
        'kotlin',
        'com',
        'acme',
        'app',
        'MainActivity.kt',
      );
      expect(File(newPath).existsSync(), isTrue);
      expect(
        await File(newPath).readAsString(),
        contains('package com.acme.app'),
      );
      expect(File(mainActivity.path).existsSync(), isFalse);
    });
  });
}
