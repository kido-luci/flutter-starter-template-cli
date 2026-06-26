import 'dart:io';

import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('removeAuthRegions', () {
    test('removes a Dart auth block inclusive of its markers', () {
      const src = "import 'a';\n"
          '// fst:auth:start\n'
          "import 'package:feature_auth/feature_auth.dart';\n"
          '// fst:auth:end\n'
          "import 'b';\n";
      expect(
        removeAuthRegions(src),
        equals("import 'a';\nimport 'b';\n"),
      );
    });

    test('removes a YAML auth block', () {
      const src = 'dependencies:\n'
          '  # fst:auth:start\n'
          '  feature_auth: ^0.1.0\n'
          '  # fst:auth:end\n'
          '  app_ui: ^0.1.0\n';
      expect(
        removeAuthRegions(src),
        equals('dependencies:\n  app_ui: ^0.1.0\n'),
      );
    });

    test('removes multiple auth blocks in the same file', () {
      const src = '// fst:auth:start\nA\n// fst:auth:end\n'
          'keep\n'
          '// fst:auth:start\nB\n// fst:auth:end\n';
      expect(removeAuthRegions(src), equals('keep\n'));
    });

    test('leaves unrelated lines untouched', () {
      const src = "import 'a';\n"
          '// fst:auth:start\n'
          "import 'feature_auth';\n"
          '// fst:auth:end\n'
          "import 'b';\n";
      final result = removeAuthRegions(src);
      expect(result, contains("import 'a'"));
      expect(result, contains("import 'b'"));
      expect(result, isNot(contains('feature_auth')));
    });

    test('is a no-op when no auth markers are present', () {
      const src = "import 'a';\nimport 'b';\n";
      expect(removeAuthRegions(src), equals(src));
    });

    test('is idempotent', () {
      const src = "import 'a';\n"
          '// fst:auth:start\n'
          "import 'feature_auth';\n"
          '// fst:auth:end\n'
          "import 'b';\n";
      final once = removeAuthRegions(src);
      expect(removeAuthRegions(once), equals(once));
    });

    test('throws on an unclosed start marker instead of dropping to EOF', () {
      const src = 'keep\n'
          '// fst:auth:start\n'
          'A\n'; // no matching :end
      expect(
        () => removeAuthRegions(src),
        throwsFormatException,
      );
    });
  });

  group('disableAuth', () {
    late Directory dir;

    void write(String relative, String content) {
      File(p.join(dir.path, p.joinAll(relative.split('/'))))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    String read(String relative) =>
        File(p.join(dir.path, p.joinAll(relative.split('/'))))
            .readAsStringSync();

    bool exists(String relative) =>
        File(p.join(dir.path, p.joinAll(relative.split('/')))).existsSync();

    setUp(() {
      dir = Directory.systemTemp.createTempSync('fst_auth_test_');

      // Root pubspec: auth workspace member + dep.
      write(
        'pubspec.yaml',
        'workspace:\n'
            '  # fst:auth:start\n'
            '  - packages/features/auth\n'
            '  # fst:auth:end\n'
            '  - packages/features/splash\n'
            'dependencies:\n'
            '  # fst:auth:start\n'
            '  feature_auth: ^0.1.0\n'
            '  # fst:auth:end\n'
            '  app_ui: ^0.1.0\n',
      );

      // app.dart: auth import.
      write(
        'lib/app/app.dart',
        '// fst:auth:start\n'
            "import 'package:feature_auth/feature_auth.dart';\n"
            '// fst:auth:end\n'
            "import 'package:flutter/material.dart';\n",
      );

      // router.dart: auth region.
      write(
        'lib/app/router.dart',
        '// fst:auth:start\n'
            "import 'package:feature_auth/feature_auth.dart';\n"
            '// fst:auth:end\n'
            "import 'package:go_router/go_router.dart';\n",
      );

      // injection.dart: auth import + module.
      write(
        'lib/app/di/injection.dart',
        '// fst:auth:start\n'
            "import 'package:feature_auth/feature_auth.dart';\n"
            '// fst:auth:end\n'
            "import 'package:get_it/get_it.dart';\n",
      );

      // splash pubspec.
      write(
        'packages/features/splash/pubspec.yaml',
        'dependencies:\n'
            '  # fst:auth:start\n'
            '  shared_ui: ^0.1.0\n'
            '  # fst:auth:end\n'
            '  app_ui: ^0.1.0\n',
      );

      // splash_screen.dart.
      write(
        'packages/features/splash/lib/src/presentation/screens/splash_screen.dart',
        '// fst:auth:start\n'
            "import 'package:shared_ui/shared_ui.dart';\n"
            '// fst:auth:end\n'
            "import 'package:flutter/material.dart';\n",
      );

      // profile pubspec.
      write(
        'packages/features/profile/pubspec.yaml',
        'dependencies:\n'
            '  # fst:auth:start\n'
            '  feature_auth: ^0.1.0\n'
            '  # fst:auth:end\n'
            '  app_ui: ^0.1.0\n',
      );

      // profile_screen.dart.
      write(
        'packages/features/profile/lib/src/presentation/screens/profile_screen.dart',
        '// fst:auth:start\n'
            "import 'package:feature_auth/feature_auth.dart';\n"
            '// fst:auth:end\n'
            "import 'package:flutter/material.dart';\n",
      );

      // profile_widgets.dart.
      write(
        'packages/features/profile/lib/src/presentation/widgets/profile_widgets.dart',
        '// fst:auth:start\n'
            "import 'package:feature_auth/feature_auth.dart';\n"
            '// fst:auth:end\n'
            "import 'package:app_ui/app_ui.dart';\n",
      );

      // profile_about.dart.
      write(
        'packages/features/profile/lib/src/presentation/widgets/profile_about.dart',
        "part of 'profile_widgets.dart';\n"
            '// fst:auth:start\n'
            'class _SignOut extends StatelessWidget {}\n'
            '// fst:auth:end\n',
      );

      // test/widget_test.dart.
      write(
        'test/widget_test.dart',
        '// fst:auth:start\n'
            "import 'package:feature_auth/src/presentation/bloc/auth_bloc.dart';\n"
            '// fst:auth:end\n'
            "import 'package:flutter_test/flutter_test.dart';\n",
      );

      // test/test_utils/mocks.dart.
      write(
        'test/test_utils/mocks.dart',
        '// fst:auth:start\n'
            "import 'package:feature_auth/src/domain/usecases/sign_in.dart';\n"
            '// fst:auth:end\n'
            "import 'package:test_utils/test_utils.dart';\n",
      );

      // test/architecture/package_layering_test.dart.
      write(
        'test/architecture/package_layering_test.dart',
        "const _layers = <String, int>{\n"
            "  // fst:auth:start\n"
            "  'feature_auth': 4,\n"
            "  // fst:auth:end\n"
            "  'feature_home': 4,\n"
            "};\n",
      );

      // test/architecture/feature_boundaries_test.dart.
      write(
        'test/architecture/feature_boundaries_test.dart',
        "const _allowed = <String, Set<String>>{\n"
            "  // fst:auth:start\n"
            "  'feature_profile': {'feature_auth'},\n"
            "  // fst:auth:end\n"
            "};\n",
      );

      // auth-only part files (to be deleted).
      write(
        'packages/features/profile/lib/src/presentation/widgets/profile_header.dart',
        "part of 'profile_widgets.dart';\n",
      );
      write(
        'packages/features/profile/lib/src/presentation/widgets/profile_account.dart',
        "part of 'profile_widgets.dart';\n",
      );

      // auth feature package directory.
      write('packages/features/auth/pubspec.yaml', 'name: feature_auth\n');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('strips auth regions from all wiring files', () async {
      await disableAuth(dir.path);

      final pubspec = read('pubspec.yaml');
      expect(pubspec, isNot(contains('feature_auth')));
      expect(pubspec, contains('app_ui'));

      final appDart = read('lib/app/app.dart');
      expect(appDart, isNot(contains('feature_auth')));
      expect(appDart, contains("import 'package:flutter/material.dart'"));

      final routerDart = read('lib/app/router.dart');
      expect(routerDart, isNot(contains('feature_auth')));
      expect(routerDart, contains('go_router'));

      final injectionDart = read('lib/app/di/injection.dart');
      expect(injectionDart, isNot(contains('feature_auth')));
      expect(injectionDart, contains('get_it'));
    });

    test('deletes auth-only part files', () async {
      await disableAuth(dir.path);

      expect(
        exists(
          'packages/features/profile/lib/src/presentation/widgets/profile_header.dart',
        ),
        isFalse,
      );
      expect(
        exists(
          'packages/features/profile/lib/src/presentation/widgets/profile_account.dart',
        ),
        isFalse,
      );
    });

    test('deletes the packages/features/auth directory', () async {
      await disableAuth(dir.path);
      expect(exists('packages/features/auth/pubspec.yaml'), isFalse);
    });

    test('is idempotent', () async {
      await disableAuth(dir.path);
      final pubspecAfterFirst = read('pubspec.yaml');

      // Run again — should be a no-op (no markers left to strip).
      await disableAuth(dir.path);
      expect(read('pubspec.yaml'), equals(pubspecAfterFirst));
    });
  });
}
