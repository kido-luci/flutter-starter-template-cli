import 'dart:io';

import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('applyFirebaseAuthProvider', () {
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
      dir = Directory.systemTemp.createTempSync('fst_authprov_test_');

      // Minimal auth feature tree that applyFirebaseAuthProvider rewrites.
      write(
        'packages/features/auth/pubspec.yaml',
        'name: feature_auth\n'
            'description: auth\n'
            'version: 0.1.0\n'
            'publish_to: none\n'
            '\n'
            'environment:\n'
            '  sdk: ^3.12.0\n'
            '\n'
            'resolution: workspace\n'
            '\n'
            'dependencies:\n'
            '  flutter:\n'
            '    sdk: flutter\n'
            '\n'
            '  # Workspace packages.\n'
            '  architecture: ^0.1.0\n'
            '  network: ^0.1.0\n'
            '  storage: ^0.1.0\n'
            '  analytics: ^0.1.0\n'
            '  app_ui: ^0.1.0\n'
            '  shared_contracts: ^0.1.0\n'
            '  shared_ui: ^0.1.0\n'
            '  localization: ^0.1.0\n'
            '\n'
            '  # Third-party.\n'
            '  flutter_bloc: ^9.1.1\n'
            '  bloc_concurrency: ^0.3.0\n'
            '  injectable: ^3.0.0\n'
            '  get_it: ^9.2.1\n'
            '  go_router: ^17.3.0\n'
            '  font_awesome_flutter: ^11.0.0\n'
            '  freezed_annotation: ^3.1.0\n'
            '  json_annotation: ^4.12.0\n'
            '\n'
            'dev_dependencies:\n'
            '  flutter_test:\n'
            '    sdk: flutter\n'
            '\n'
            '  build_runner: ^2.15.0\n'
            '  freezed: ^3.2.5\n'
            '  json_serializable: ^6.14.0\n'
            '  retrofit_generator: ^10.2.7\n'
            '  injectable_generator: ^3.0.2\n',
      );

      // Files that should be deleted.
      write(
        'packages/features/auth/lib/src/data/datasources/auth_remote_data_source.dart',
        '// REST remote data source\n',
      );
      write(
        'packages/features/auth/lib/src/data/datasources/auth_local_data_source.dart',
        '// Local data source\n',
      );
      write(
        'packages/features/auth/lib/src/data/network/auth_network_module.dart',
        '// Auth network module\n',
      );
      write(
        'packages/features/auth/lib/src/data/models/auth_user_dto.dart',
        '// AuthUserDto\n',
      );
      write(
        'packages/features/auth/lib/src/data/models/sign_in_request.dart',
        '// SignInRequest\n',
      );
      write(
        'packages/features/auth/lib/src/data/models/sign_in_response.dart',
        '// SignInResponse\n',
      );
      write(
        'packages/features/auth/lib/src/data/models/register_request.dart',
        '// RegisterRequest\n',
      );
      write(
        'packages/features/auth/lib/src/data/models/refresh_token_request.dart',
        '// RefreshTokenRequest\n',
      );
      write(
        'packages/features/auth/lib/src/data/models/change_password_request.dart',
        '// ChangePasswordRequest\n',
      );

      // Existing repo impl (will be overwritten).
      write(
        'packages/features/auth/lib/src/data/repositories/auth_repository_impl.dart',
        '// JWT AuthRepositoryImpl (original)\n',
      );
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('writes FirebaseAuthRepository to auth_repository_impl.dart',
        () async {
      await applyFirebaseAuthProvider(dir.path);

      final impl = read(
        'packages/features/auth/lib/src/data/repositories/auth_repository_impl.dart',
      );
      expect(impl, contains('FirebaseAuthRepository'));
      expect(impl, contains('@LazySingleton(as: AuthRepository)'));
      expect(impl, contains('FirebaseAuth'));
      expect(impl, contains('signInWithEmailAndPassword'));
      expect(impl, contains('createUserWithEmailAndPassword'));
      expect(impl, contains('reauthenticateWithCredential'));
      expect(impl, contains('updatePassword'));
      expect(impl, contains('restoreSession'));
      expect(impl, contains('InvalidCredentialsFailure'));
      expect(impl, contains('NoSessionFailure'));
      expect(impl, contains('UnknownFailure'));
    });

    test('writes firebase_auth_module.dart with @module and @lazySingleton',
        () async {
      await applyFirebaseAuthProvider(dir.path);

      final module = read(
        'packages/features/auth/lib/src/data/firebase_auth_module.dart',
      );
      expect(module, contains('@module'));
      expect(module, contains('@lazySingleton'));
      expect(module, contains('FirebaseAuth.instance'));
    });

    test('deletes REST-only data-layer files', () async {
      await applyFirebaseAuthProvider(dir.path);

      expect(
        exists(
          'packages/features/auth/lib/src/data/datasources/auth_remote_data_source.dart',
        ),
        isFalse,
      );
      expect(
        exists(
          'packages/features/auth/lib/src/data/datasources/auth_local_data_source.dart',
        ),
        isFalse,
      );
      expect(
        exists(
          'packages/features/auth/lib/src/data/network/auth_network_module.dart',
        ),
        isFalse,
      );
      expect(
        exists(
          'packages/features/auth/lib/src/data/models/auth_user_dto.dart',
        ),
        isFalse,
      );
      expect(
        exists(
          'packages/features/auth/lib/src/data/models/sign_in_request.dart',
        ),
        isFalse,
      );
      expect(
        exists(
          'packages/features/auth/lib/src/data/models/sign_in_response.dart',
        ),
        isFalse,
      );
      expect(
        exists(
          'packages/features/auth/lib/src/data/models/register_request.dart',
        ),
        isFalse,
      );
      expect(
        exists(
          'packages/features/auth/lib/src/data/models/refresh_token_request.dart',
        ),
        isFalse,
      );
      expect(
        exists(
          'packages/features/auth/lib/src/data/models/change_password_request.dart',
        ),
        isFalse,
      );
    });

    test('rewrites pubspec.yaml: removes REST deps, adds firebase_auth',
        () async {
      await applyFirebaseAuthProvider(dir.path);

      final pubspec = read('packages/features/auth/pubspec.yaml');
      expect(pubspec, contains('firebase_auth: ^6.1.0'));
      // REST-only deps removed.
      expect(pubspec, isNot(contains('network: ^0.1.0')));
      expect(pubspec, isNot(contains('storage: ^0.1.0')));
      expect(pubspec, isNot(contains('retrofit_generator')));
      expect(pubspec, isNot(contains('json_serializable')));
      expect(pubspec, isNot(contains('json_annotation')));
      // freezed_annotation + freezed stay: presentation blocs use them.
      expect(pubspec, contains('freezed_annotation'));
      expect(pubspec, contains('freezed:'));
      // Other non-REST deps must survive.
      expect(pubspec, contains('injectable: ^3.0.0'));
      expect(pubspec, contains('flutter_bloc: ^9.1.1'));
      expect(pubspec, contains('build_runner: ^2.15.0'));
      expect(pubspec, contains('injectable_generator: ^3.0.2'));
    });

    test('is idempotent', () async {
      await applyFirebaseAuthProvider(dir.path);
      final impl1 = read(
        'packages/features/auth/lib/src/data/repositories/auth_repository_impl.dart',
      );
      final pubspec1 = read('packages/features/auth/pubspec.yaml');

      // Re-run — writes the same content; deleted files stay absent.
      await applyFirebaseAuthProvider(dir.path);
      expect(
        read(
          'packages/features/auth/lib/src/data/repositories/auth_repository_impl.dart',
        ),
        equals(impl1),
      );
      expect(read('packages/features/auth/pubspec.yaml'), equals(pubspec1));
    });
  });
}
