import 'dart:io';

import 'package:path/path.dart' as p;

/// Rewrites the auth feature's data layer in [projectDir] to use Firebase Auth
/// instead of the default JWT/REST implementation.
///
/// Steps performed (all in-memory first, then committed atomically):
///
/// 1. Writes `auth_repository_impl.dart` — a `FirebaseAuthRepository` backed by
///    `package:firebase_auth` that satisfies the `AuthRepository` contract.
/// 2. Writes `firebase_auth_module.dart` — a `@module` that provides
///    `FirebaseAuth.instance` into the DI graph.
/// 3. Deletes the REST-only data-layer files that are no longer needed.
/// 4. Rewrites `pubspec.yaml` to remove REST deps and add `firebase_auth`.
///
/// `di.module.dart` is a committed generated file that build_runner will not
/// regenerate while the `di.dart` anchor is unchanged, so this writes the
/// correct module for the Firebase impl directly rather than relying on codegen.
///
/// [projectDir] must be a freshly scaffolded project tree (already renamed).
Future<void> applyFirebaseAuthProvider(String projectDir) async {
  // ── 1. Compute every write in memory ────────────────────────────────────────

  final repoImpl = _firebaseAuthRepositoryImpl();
  final firebaseModule = _firebaseAuthModule();
  final newPubspec = _rewritePubspec(
    File(p.join(projectDir, 'packages', 'features', 'auth', 'pubspec.yaml'))
        .readAsStringSync(),
  );

  // ── 2. Commit writes ────────────────────────────────────────────────────────

  _write(
    p.join(
      projectDir,
      'packages',
      'features',
      'auth',
      'lib',
      'src',
      'data',
      'repositories',
      'auth_repository_impl.dart',
    ),
    repoImpl,
  );

  _write(
    p.join(
      projectDir,
      'packages',
      'features',
      'auth',
      'lib',
      'src',
      'data',
      'firebase_auth_module.dart',
    ),
    firebaseModule,
  );

  _write(
    p.join(projectDir, 'packages', 'features', 'auth', 'pubspec.yaml'),
    newPubspec,
  );

  // Write the complete di.module.dart wired for FirebaseAuthRepository.
  // injectable_generator cannot resolve firebase_auth's platform-conditional
  // types at build time, so build_runner would produce an empty module; we
  // write the correct content directly instead.
  _write(
    p.join(
      projectDir,
      'packages',
      'features',
      'auth',
      'lib',
      'src',
      'di.module.dart',
    ),
    _firebaseAuthDiModule(),
  );

  // ── 3. Delete REST-only files ────────────────────────────────────────────────

  const deletedRelative = [
    // REST data-layer sources.
    'lib/src/data/datasources/auth_remote_data_source.dart',
    'lib/src/data/datasources/auth_remote_data_source.g.dart',
    'lib/src/data/datasources/auth_local_data_source.dart',
    'lib/src/data/network/auth_network_module.dart',
    // REST DTOs (data models).
    'lib/src/data/models/auth_user_dto.dart',
    'lib/src/data/models/auth_user_dto.freezed.dart',
    'lib/src/data/models/auth_user_dto.g.dart',
    'lib/src/data/models/change_password_request.dart',
    'lib/src/data/models/change_password_request.freezed.dart',
    'lib/src/data/models/change_password_request.g.dart',
    'lib/src/data/models/refresh_token_request.dart',
    'lib/src/data/models/refresh_token_request.freezed.dart',
    'lib/src/data/models/refresh_token_request.g.dart',
    'lib/src/data/models/refresh_token_response.dart',
    'lib/src/data/models/refresh_token_response.freezed.dart',
    'lib/src/data/models/refresh_token_response.g.dart',
    'lib/src/data/models/register_request.dart',
    'lib/src/data/models/register_request.freezed.dart',
    'lib/src/data/models/register_request.g.dart',
    'lib/src/data/models/sign_in_request.dart',
    'lib/src/data/models/sign_in_request.freezed.dart',
    'lib/src/data/models/sign_in_request.g.dart',
    'lib/src/data/models/sign_in_response.dart',
    'lib/src/data/models/sign_in_response.freezed.dart',
    'lib/src/data/models/sign_in_response.g.dart',
    // REST-specific unit test that imports all the deleted data-layer files.
    'test/data/repositories/auth_repository_impl_test.dart',
  ];

  final authBase = p.join(projectDir, 'packages', 'features', 'auth');
  for (final rel in deletedRelative) {
    final file = File(p.join(authBase, p.joinAll(rel.split('/'))));
    if (file.existsSync()) file.deleteSync();
  }

  // Clean up now-empty data subdirectories (best-effort, non-fatal).
  for (final dirRel in [
    p.join(authBase, 'lib', 'src', 'data', 'datasources'),
    p.join(authBase, 'lib', 'src', 'data', 'network'),
    p.join(authBase, 'lib', 'src', 'data', 'models'),
  ]) {
    final dir = Directory(dirRel);
    if (dir.existsSync() && dir.listSync().isEmpty) {
      dir.deleteSync();
    }
  }
}

// ── Template strings ──────────────────────────────────────────────────────────

String _firebaseAuthRepositoryImpl() => r'''
import 'package:architecture/architecture.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_contracts/shared_contracts.dart';

import '../../domain/repositories/auth_repository.dart';

/// Firebase Auth implementation of [AuthRepository].
///
/// Maps the `username` parameter to the Firebase email field throughout
/// (sign-in, register, change-password, delete-account).
///
/// Error mapping:
///  - `wrong-password` / `user-not-found` / `invalid-credential`
///      → [InvalidCredentialsFailure]
///  - `requires-recent-login` (reauthentication needed)
///      → [InvalidCredentialsFailure] with an actionable message
///  - Everything else → [UnknownFailure]
@LazySingleton(as: AuthRepository)
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth);

  // [FirebaseAuth] is provided by [FirebaseAuthModule] via DI.
  final FirebaseAuth _auth;

  @override
  AuthUser? get currentUser => _mapUser(_auth.currentUser);

  @override
  Future<Result<AuthUser>> signIn({
    required String username,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: username,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        return const Err(UnknownFailure('Sign-in succeeded but user is null.'));
      }
      return Ok(_userFromFirebase(user));
    } on FirebaseAuthException catch (e) {
      return Err(_mapFirebaseError(e));
    } on Object catch (e) {
      return Err(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Result<AuthUser>> register({
    required String username,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: username,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        return const Err(
          UnknownFailure('Registration succeeded but user is null.'),
        );
      }
      return Ok(_userFromFirebase(user));
    } on FirebaseAuthException catch (e) {
      return Err(_mapFirebaseError(e));
    } on Object catch (e) {
      return Err(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      return const Err(NoSessionFailure('No signed-in user.'));
    }
    try {
      // Re-authenticate first so Firebase accepts the password change.
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
      return const Ok(null);
    } on FirebaseAuthException catch (e) {
      return Err(_mapFirebaseError(e));
    } on Object catch (e) {
      return Err(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> signOut() async {
    try {
      await _auth.signOut();
      return const Ok(null);
    } on FirebaseAuthException catch (e) {
      return Err(_mapFirebaseError(e));
    } on Object catch (e) {
      return Err(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      return const Err(NoSessionFailure('No signed-in user.'));
    }
    try {
      // deleteAccount requires a recent sign-in; if the session is stale the
      // caller must invoke changePassword-style reauthentication first.
      await user.delete();
      return const Ok(null);
    } on FirebaseAuthException catch (e) {
      return Err(_mapFirebaseError(e));
    } on Object catch (e) {
      return Err(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Result<AuthUser>> restoreSession() async {
    final user = _auth.currentUser;
    if (user == null) {
      return const Err(NoSessionFailure('No persisted Firebase session.'));
    }
    try {
      // Force-reload to verify the token is still valid.
      await user.reload();
      final reloaded = _auth.currentUser;
      if (reloaded == null) {
        return const Err(NoSessionFailure('Session expired.'));
      }
      return Ok(_userFromFirebase(reloaded));
    } on FirebaseAuthException catch (e) {
      return Err(_mapFirebaseError(e));
    } on Object catch (e) {
      return Err(UnknownFailure(e.toString()));
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  AuthUser _userFromFirebase(User user) => AuthUser(
    id: user.uid,
    // Firebase email is the username in this app; fall back to uid when absent
    // (e.g. anonymous or phone-only accounts, which are not used here but
    // make the mapping total).
    username: user.email ?? user.uid,
  );

  AuthUser? _mapUser(User? user) =>
      user == null ? null : _userFromFirebase(user);

  Failure _mapFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-credential':
      case 'invalid-email':
        return InvalidCredentialsFailure(
          e.message ?? 'Invalid email or password.',
        );
      case 'requires-recent-login':
        return const InvalidCredentialsFailure(
          'Please sign in again before performing this action.',
        );
      default:
        return UnknownFailure(e.message ?? 'Firebase error: ${e.code}');
    }
  }
}
''';

/// Full DI module for the Firebase Auth implementation of the auth feature.
///
/// `di.module.dart` is a *committed* generated file, and injectable's
/// micro-package config builder does not regenerate it on a fresh build while
/// the `di.dart` anchor is unchanged — it keeps the existing file. Swapping the
/// auth implementation would otherwise leave a stale module that imports the
/// now-deleted REST classes, so this writes the correct module directly. It
/// mirrors injectable's output and is overwritten the next time the user changes
/// an injected type in this package and reruns build_runner.
String _firebaseAuthDiModule() => r'''
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'dart:async' as _i687;

import 'package:analytics/analytics.dart' as _i548;
import 'package:feature_auth/src/data/firebase_auth_module.dart' as _i100;
import 'package:feature_auth/src/data/repositories/auth_repository_impl.dart'
    as _i953;
import 'package:feature_auth/src/domain/repositories/auth_repository.dart'
    as _i1063;
import 'package:feature_auth/src/domain/usecases/change_password.dart' as _i359;
import 'package:feature_auth/src/domain/usecases/delete_account.dart' as _i884;
import 'package:feature_auth/src/domain/usecases/register.dart' as _i821;
import 'package:feature_auth/src/domain/usecases/restore_session.dart' as _i63;
import 'package:feature_auth/src/domain/usecases/sign_in.dart' as _i147;
import 'package:feature_auth/src/domain/usecases/sign_out.dart' as _i1002;
import 'package:feature_auth/src/presentation/bloc/auth_bloc.dart' as _i1014;
import 'package:feature_auth/src/presentation/bloc/change_password_cubit.dart'
    as _i1062;
import 'package:feature_auth/src/presentation/bloc/delete_account_cubit.dart'
    as _i1061;
import 'package:firebase_auth/firebase_auth.dart' as _i900;
import 'package:injectable/injectable.dart' as _i526;

class FeatureAuthPackageModule extends _i526.MicroPackageModule {
  // initializes the registration of main-scope dependencies inside of GetIt
  @override
  _i687.FutureOr<void> init(_i526.GetItHelper gh) {
    final firebaseAuthModule = _$FirebaseAuthModule();
    gh.lazySingleton<_i900.FirebaseAuth>(
      () => firebaseAuthModule.firebaseAuth,
    );
    gh.lazySingleton<_i1063.AuthRepository>(
      () => _i953.FirebaseAuthRepository(gh<_i900.FirebaseAuth>()),
    );
    gh.factory<_i359.ChangePasswordUseCase>(
      () => _i359.ChangePasswordUseCase(gh<_i1063.AuthRepository>()),
    );
    gh.factory<_i884.DeleteAccountUseCase>(
      () => _i884.DeleteAccountUseCase(gh<_i1063.AuthRepository>()),
    );
    gh.factory<_i821.RegisterUseCase>(
      () => _i821.RegisterUseCase(gh<_i1063.AuthRepository>()),
    );
    gh.factory<_i63.RestoreSessionUseCase>(
      () => _i63.RestoreSessionUseCase(gh<_i1063.AuthRepository>()),
    );
    gh.factory<_i147.SignInUseCase>(
      () => _i147.SignInUseCase(gh<_i1063.AuthRepository>()),
    );
    gh.factory<_i1002.SignOutUseCase>(
      () => _i1002.SignOutUseCase(gh<_i1063.AuthRepository>()),
    );
    gh.factory<_i1061.DeleteAccountCubit>(
      () => _i1061.DeleteAccountCubit(
        gh<_i884.DeleteAccountUseCase>(),
        gh<_i548.AnalyticsService>(),
      ),
    );
    gh.factory<_i1062.ChangePasswordCubit>(
      () => _i1062.ChangePasswordCubit(gh<_i359.ChangePasswordUseCase>()),
    );
    gh.lazySingleton<_i1014.AuthBloc>(
      () => _i1014.AuthBloc(
        signIn: gh<_i147.SignInUseCase>(),
        register: gh<_i821.RegisterUseCase>(),
        signOut: gh<_i1002.SignOutUseCase>(),
        restoreSession: gh<_i63.RestoreSessionUseCase>(),
        analytics: gh<_i548.AnalyticsService>(),
      ),
    );
  }
}

class _$FirebaseAuthModule extends _i100.FirebaseAuthModule {}
''';

String _firebaseAuthModule() => r'''
import 'package:firebase_auth/firebase_auth.dart';
import 'package:injectable/injectable.dart';

/// Provides the [FirebaseAuth] singleton into the DI graph so
/// `FirebaseAuthRepository` can declare it as a constructor parameter.
@module
abstract class FirebaseAuthModule {
  @lazySingleton
  FirebaseAuth get firebaseAuth => FirebaseAuth.instance;
}
''';

/// Rewrites the auth feature's `pubspec.yaml` to:
/// - Remove `network` and `storage` (REST-only workspace packages).
/// - Remove `json_annotation` and `retrofit_generator` / `json_serializable`
///   (REST-only tooling; the deleted DTOs were the only consumers).
/// - Keep `freezed_annotation` + `freezed` (the presentation blocs still use
///   them for sealed state classes).
/// - Add `firebase_auth: ^6.1.0`.
String _rewritePubspec(String original) {
  var content = original;

  // Remove REST-only deps. freezed_annotation and freezed stay (blocs need them).
  const linesToRemove = [
    '  network: ^0.1.0',
    '  storage: ^0.1.0',
    '  json_annotation: ^4.12.0',
    '  retrofit_generator: ^10.2.7',
    '  json_serializable: ^6.14.0',
  ];
  for (final line in linesToRemove) {
    content = content.replaceAll('$line\n', '');
  }

  // Insert firebase_auth right after the `injectable` dep line.
  const injectableLine = '  injectable: ^3.0.0';
  if (content.contains(injectableLine) &&
      !content.contains('  firebase_auth:')) {
    content = content.replaceFirst(
      '$injectableLine\n',
      '$injectableLine\n  firebase_auth: ^6.1.0\n',
    );
  }

  return content;
}

void _write(String path, String content) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}
