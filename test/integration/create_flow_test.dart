import 'dart:io';

import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// End-to-end of the local-template scaffold pipeline: the same chain
/// `fst create --template-path` runs — copy a local checkout, reset to a clean
/// slate, rename identifiers, then drop an excluded feature — asserted on the
/// produced tree.
void main() {
  group('create flow (--template-path pipeline)', () {
    late Directory tempDir;
    late String template;
    late String output;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('fst_create_');
      template = p.join(tempDir.path, 'template');
      output = p.join(tempDir.path, 'out');
      _writeTemplateFixture(template);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('copies, cleans, renames and excludes into a coherent project',
        () async {
      final config = ProjectConfig(
        displayName: 'Smoke App',
        packageName: 'smoke_app',
        bundleId: 'com.example.smoke',
        org: 'Smoke Org',
        outputDir: output,
      );

      // The exact step order CreateCommand uses.
      await copyLocalTemplate(template, output);
      await prepareCleanSlate(output);
      await rewriteProject(output, config);
      await excludeFeatures(output, {'notifications'});

      String read(String rel) =>
          File(p.join(output, p.joinAll(rel.split('/')))).readAsStringSync();

      // Package identifier renamed in pubspec + Dart imports.
      expect(read('pubspec.yaml'), contains('name: smoke_app'));
      expect(read('lib/main.dart'), contains('package:smoke_app/'));

      // Excluded feature: marker blocks stripped, package deleted; kept ones
      // and the insertion marker survive.
      final features = read('lib/app/features.dart');
      expect(features, isNot(contains('feature_notifications')));
      expect(features, isNot(contains('_NotificationsModule')));
      expect(features, contains('fst:enabled-features'));
      expect(
        Directory(p.join(output, 'packages/features/notifications'))
            .existsSync(),
        isFalse,
      );
      expect(
        Directory(p.join(output, 'packages/features/bookmarks')).existsSync(),
        isTrue,
      );

      // MainActivity moved to the new bundle path; the template path is gone.
      expect(
        File(p.join(output,
                'android/app/src/main/kotlin/com/example/smoke/MainActivity.kt'))
            .existsSync(),
        isTrue,
      );
      expect(
        Directory(p.join(output, 'android/app/src/main/kotlin/com/lucistudio'))
            .existsSync(),
        isFalse,
      );

      // A fresh git repo was initialised.
      expect(Directory(p.join(output, '.git')).existsSync(), isTrue);

      // No template identifier leaks anywhere in the produced tree.
      final leaks = _filesContaining(
        Directory(output),
        ['flutter_starter_template', 'lucistudio', 'Luci Studio'],
      );
      expect(leaks, isEmpty, reason: 'template identifiers leaked: $leaks');
    });

    test('an unclosed marker block aborts before any file is written',
        () async {
      await copyLocalTemplate(template, output);
      await prepareCleanSlate(output);
      // Corrupt a wiring file: open a notifications block but never close it.
      final pubspec = File(p.join(output, 'pubspec.yaml'));
      pubspec.writeAsStringSync(
        '${pubspec.readAsStringSync()}\n  # fst:feature:notifications:start\n',
      );
      final before = pubspec.readAsStringSync();

      await expectLater(
        excludeFeatures(output, {'notifications'}),
        throwsA(isA<FormatException>()),
      );

      // The malformed file is untouched (compute-then-write, not partial).
      expect(pubspec.readAsStringSync(), before);
    });
  });
}

/// Files under [root] containing any of [needles] (skipping `.git`).
List<String> _filesContaining(Directory root, List<String> needles) {
  final hits = <String>[];
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (p.split(entity.path).contains('.git')) continue;
    final text = entity.readAsStringSync();
    if (needles.any(text.contains)) {
      hits.add(p.relative(entity.path, from: root.path));
    }
  }
  return hits;
}

/// Writes a minimal but representative template tree at [dir].
void _writeTemplateFixture(String dir) {
  void write(String rel, String content) {
    File(p.join(dir, p.joinAll(rel.split('/'))))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  write('pubspec.yaml', '''
name: flutter_starter_template
description: "Template."
publish_to: 'none'
version: 1.0.0+1
environment:
  sdk: ^3.12.0
workspace:
  - packages/features/auth
  # fst:feature:notifications:start
  - packages/features/notifications
  # fst:feature:notifications:end
  - packages/features/bookmarks
  # fst:features
dependencies:
  feature_auth:
    path: packages/features/auth
  # fst:feature:notifications:start
  feature_notifications:
    path: packages/features/notifications
  # fst:feature:notifications:end
  # fst:feature-deps
''');

  write('lib/main.dart', '''
import 'package:flutter_starter_template/app.dart';

void main() {}
''');

  write('lib/app/features.dart', '''
// fst:feature:notifications:start
import 'package:feature_notifications/feature_notifications.dart';
// fst:feature:notifications:end

const enabledFeatures = <FeatureModule>[
  // fst:feature:notifications:start
  _NotificationsModule(),
  // fst:feature:notifications:end
  // fst:enabled-features
];
''');

  write(
    'android/app/src/main/kotlin/com/lucistudio/flutter_starter_template/'
        'MainActivity.kt',
    'package com.lucistudio.flutter_starter_template\n',
  );

  for (final feature in ['auth', 'notifications', 'bookmarks', 'collections']) {
    write(
        'packages/features/$feature/pubspec.yaml', 'name: feature_$feature\n');
  }
}
