import '../feature_names.dart';

/// The kind of data+domain layer to scaffold alongside the presentation layer.
enum FeatureSource {
  /// Presentation layer only — the default, identical to the original scaffold.
  presentation,

  /// Adds a domain layer (entity + repository interface) and a data layer
  /// backed by an in-memory store. Self-contained; no `network` or `database`
  /// dependencies.
  local,

  /// Adds a domain layer and a remote data layer using Retrofit + Dio, plus a
  /// generated DTO. Requires the `network` workspace package.
  api,

  /// Everything in `api`, plus compiling stubs for offline-first sync via
  /// `rev_sync`. Manual steps are documented in the generated `SYNC_TODO.md`.
  sync,
}

/// Returns the scaffold for a new feature package keyed by path relative to
/// `packages/features/<name>/` (POSIX separators).
///
/// [source] controls which additional layers are generated alongside the
/// presentation layer. Pure and filesystem-free so it can be asserted directly
/// in tests.
Map<String, String> featureFiles(
  FeatureNames n, {
  FeatureSource source = FeatureSource.presentation,
}) {
  final files = <String, String>{
    'pubspec.yaml': _pubspec(n, source),
    'lib/${n.package}.dart': _barrel(n, source),
    'lib/src/di.dart': _di(n),
    'lib/src/locator.dart': _locator(),
    'lib/src/presentation/bloc/${n.snake}_cubit.dart': _cubit(n, source),
    'lib/src/presentation/bloc/${n.snake}_state.dart': _state(n, source),
    'lib/src/presentation/screens/${n.snake}_screen.dart': _screen(n, source),
    'lib/src/presentation/${n.snake}_routes.dart': _routes(n),
    'test/presentation/${n.snake}_routes_test.dart': _routesTest(n),
  };

  if (source == FeatureSource.local ||
      source == FeatureSource.api ||
      source == FeatureSource.sync) {
    files['lib/src/domain/entities/${n.snake}.dart'] = _entity(n);
    files['lib/src/domain/repositories/${n.snake}_repository.dart'] =
        _repositoryInterface(n);
  }

  if (source == FeatureSource.local) {
    files['lib/src/data/local/${n.snake}_local_data_source.dart'] =
        _localDataSource(n);
    files['lib/src/data/repositories/${n.snake}_repository_impl.dart'] =
        _localRepositoryImpl(n);
  }

  if (source == FeatureSource.api || source == FeatureSource.sync) {
    files['lib/src/data/models/${n.snake}_dto.dart'] = _dto(n);
    files['lib/src/data/datasources/${n.snake}_remote_data_source.dart'] =
        _remoteDataSource(n);
    files['lib/src/data/datasources/${n.snake}_remote_module.dart'] =
        _remoteModule(n);
    files['lib/src/data/repositories/${n.snake}_repository_impl.dart'] =
        _apiRepositoryImpl(n);
  }

  if (source == FeatureSource.sync) {
    files['lib/src/data/sync/${n.snake}_sync_adapter.dart'] = _syncAdapter(n);
    files['lib/src/domain/services/${n.snake}_sync_controller.dart'] =
        _syncController(n);
    files['SYNC_TODO.md'] = _syncTodo(n);
  }

  return files;
}

// ── pubspec ──────────────────────────────────────────────────────────────────

String _pubspec(FeatureNames n, FeatureSource source) {
  final workspaceDeps = StringBuffer();
  if (source == FeatureSource.local ||
      source == FeatureSource.api ||
      source == FeatureSource.sync) {
    workspaceDeps.writeln('  architecture: ^0.1.0');
  }
  if (source == FeatureSource.api || source == FeatureSource.sync) {
    workspaceDeps.writeln('  network: ^0.1.0');
  }
  if (source == FeatureSource.sync) {
    workspaceDeps.writeln('  rev_sync:');
    workspaceDeps.writeln('    path: ../../../published/rev_sync');
  }

  // local needs uuid for ID generation; api/sync get it transitively via network.
  final localDeps = source == FeatureSource.local ? '\n  uuid: ^4.5.3' : '';

  final apiDeps = (source == FeatureSource.api || source == FeatureSource.sync)
      ? '\n  dio: ^5.9.2\n  retrofit: ^4.9.2\n  json_annotation: ^4.12.0'
      : '';

  final apiDevDeps =
      (source == FeatureSource.api || source == FeatureSource.sync)
          ? '\n  retrofit_generator: ^10.2.7\n  json_serializable: ^6.14.0'
          : '';

  final description = switch (source) {
    FeatureSource.presentation =>
      '${n.pascal} feature: a self-contained presentation-layer workspace package.',
    FeatureSource.local =>
      '${n.pascal} feature: presentation + domain + local in-memory data layer.',
    FeatureSource.api =>
      '${n.pascal} feature: presentation + domain + remote API data layer.',
    FeatureSource.sync =>
      '${n.pascal} feature: presentation + domain + remote API + offline-first sync stubs.',
  };

  final workspaceDepsBlock = workspaceDeps.isEmpty
      ? ''
      : '\n  # Workspace packages.\n${workspaceDeps.toString().trimRight()}\n';

  return '''
name: ${n.package}
description: >-
  $description
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.12.0

resolution: workspace

dependencies:
  flutter:
    sdk: flutter
$workspaceDepsBlock
  # Third-party.
  flutter_bloc: ^9.1.1
  go_router: ^17.3.0
  injectable: ^3.0.0
  get_it: ^9.2.1$localDeps$apiDeps

dev_dependencies:
  flutter_test:
    sdk: flutter

  build_runner: ^2.15.0
  injectable_generator: ^3.0.2$apiDevDeps
''';
}

// ── barrel ───────────────────────────────────────────────────────────────────

String _barrel(FeatureNames n, FeatureSource source) {
  // Collect all exports and sort them for directives_ordering compliance.
  final exports = <String>[
    "export 'src/di.module.dart' show ${n.packageModule};",
    if (source == FeatureSource.local ||
        source == FeatureSource.api ||
        source == FeatureSource.sync)
      "export 'src/domain/entities/${n.snake}.dart';",
    if (source == FeatureSource.sync)
      "export 'src/domain/services/${n.snake}_sync_controller.dart';",
    "export 'src/presentation/${n.snake}_routes.dart';",
    "export 'src/presentation/screens/${n.snake}_screen.dart';",
  ]..sort();

  return '''
/// ${n.pascal} feature.
///
/// The host app wires `${n.packageModule}` via `externalPackageModulesBefore`
/// and mounts `${n.camel}Routes` through its `FeatureModule`. Internals stay
/// private.
library;

${exports.join('\n')}
''';
}

// ── shared presentation files (identical for all sources) ────────────────────

String _di(FeatureNames n) => '''
import 'package:injectable/injectable.dart';

/// Code-generation anchor for the ${n.package} micro-package.
///
/// Running `build_runner` here generates `di.module.dart` containing
/// `${n.packageModule}`, which the host app wires via
/// `externalPackageModulesBefore`.
@InjectableInit.microPackage()
void init${n.pascal}Feature() {}
''';

String _locator() => '''
import 'package:get_it/get_it.dart';

/// The app-wide service locator (the shared `GetIt` singleton).
final GetIt getIt = GetIt.instance;
''';

// ── presentation ─────────────────────────────────────────────────────────────

String _state(FeatureNames n, FeatureSource source) {
  if (source == FeatureSource.presentation) {
    return '''
import 'package:flutter/foundation.dart';

/// Immutable UI state for the ${n.snake} screen.
@immutable
class ${n.pascal}State {
  const ${n.pascal}State({this.isReady = false});

  /// Whether the screen has finished its initial load.
  final bool isReady;

  ${n.pascal}State copyWith({bool? isReady}) =>
      ${n.pascal}State(isReady: isReady ?? this.isReady);

  @override
  bool operator ==(Object other) =>
      other is ${n.pascal}State && other.isReady == isReady;

  @override
  int get hashCode => isReady.hashCode;
}
''';
  }

  // local / api / sync — lists items
  return '''
import 'package:flutter/foundation.dart';

import '../../domain/entities/${n.snake}.dart';

/// Immutable UI state for the ${n.snake} screen.
@immutable
class ${n.pascal}State {
  const ${n.pascal}State({
    this.items = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  final List<${n.pascal}> items;
  final bool isLoading;

  /// Non-null when the last operation failed.
  final String? errorMessage;

  ${n.pascal}State copyWith({
    List<${n.pascal}>? items,
    bool? isLoading,
    String? errorMessage,
  }) => ${n.pascal}State(
    items: items ?? this.items,
    isLoading: isLoading ?? this.isLoading,
    errorMessage: errorMessage,
  );

  @override
  bool operator ==(Object other) =>
      other is ${n.pascal}State &&
      other.items == items &&
      other.isLoading == isLoading &&
      other.errorMessage == errorMessage;

  @override
  int get hashCode => Object.hash(items, isLoading, errorMessage);
}
''';
}

String _cubit(FeatureNames n, FeatureSource source) {
  if (source == FeatureSource.presentation) {
    return '''
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '${n.snake}_state.dart';

/// Manages the [${n.pascal}State] for the ${n.snake} screen.
///
/// Public methods return `void`; new state flows out only through `emit`.
@injectable
class ${n.pascal}Cubit extends Cubit<${n.pascal}State> {
  ${n.pascal}Cubit() : super(const ${n.pascal}State());

  /// Loads the screen's initial data.
  void load() => emit(state.copyWith(isReady: true));
}
''';
  }

  return '''
import 'package:architecture/architecture.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../domain/repositories/${n.snake}_repository.dart';
import '${n.snake}_state.dart';

/// Manages the [${n.pascal}State] for the ${n.snake} screen.
///
/// Public methods return `void`; new state flows out only through `emit`.
@injectable
class ${n.pascal}Cubit extends Cubit<${n.pascal}State> {
  ${n.pascal}Cubit(this._repository) : super(const ${n.pascal}State());

  final ${n.pascal}Repository _repository;

  /// Loads the initial list of ${n.snake} items.
  Future<void> load() async {
    emit(state.copyWith(isLoading: true));
    final result = await _repository.list();
    switch (result) {
      case Ok(:final value):
        emit(state.copyWith(items: value, isLoading: false));
      case Err(:final failure):
        emit(
          state.copyWith(isLoading: false, errorMessage: failure.toString()),
        );
    }
  }

  /// Creates a new ${n.snake} item with the given [title].
  Future<void> create(String title) async {
    final result = await _repository.create(title);
    switch (result) {
      case Ok():
        await load();
      case Err(:final failure):
        emit(state.copyWith(errorMessage: failure.toString()));
    }
  }
}
''';
}

String _screen(FeatureNames n, FeatureSource source) {
  if (source == FeatureSource.presentation) {
    return '''
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../locator.dart';
import '../bloc/${n.snake}_cubit.dart';
import '../bloc/${n.snake}_state.dart';

/// The ${n.snake} feature's screen.
class ${n.pascal}Screen extends StatelessWidget {
  const ${n.pascal}Screen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<${n.pascal}Cubit>()..load(),
      child: Scaffold(
        appBar: AppBar(title: const Text('${n.pascal}')),
        body: BlocBuilder<${n.pascal}Cubit, ${n.pascal}State>(
          builder: (context, state) => Center(
            child: Text(state.isReady ? '${n.pascal} ready' : 'Loading…'),
          ),
        ),
      ),
    );
  }
}
''';
  }

  return '''
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../locator.dart';
import '../bloc/${n.snake}_cubit.dart';
import '../bloc/${n.snake}_state.dart';

/// The ${n.snake} feature's screen.
class ${n.pascal}Screen extends StatelessWidget {
  const ${n.pascal}Screen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<${n.pascal}Cubit>()..load(),
      child: Scaffold(
        appBar: AppBar(title: const Text('${n.pascal}')),
        body: BlocBuilder<${n.pascal}Cubit, ${n.pascal}State>(
          builder: (context, state) {
            if (state.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.errorMessage != null) {
              return Center(child: Text(state.errorMessage!));
            }
            if (state.items.isEmpty) {
              return const Center(child: Text('No items yet.'));
            }
            return ListView.builder(
              itemCount: state.items.length,
              itemBuilder: (context, index) {
                final item = state.items[index];
                return ListTile(title: Text(item.title));
              },
            );
          },
        ),
      ),
    );
  }
}
''';
}

String _routes(FeatureNames n) => '''
import 'package:go_router/go_router.dart';

import 'screens/${n.snake}_screen.dart';

/// Canonical navigation paths owned by the ${n.snake} feature.
abstract final class ${n.pascal}Routes {
  /// The ${n.snake} screen.
  static const root = '/${n.kebab}';
}

/// The ${n.snake} feature's routes, mounted by the host app.
List<RouteBase> get ${n.camel}Routes => [
  GoRoute(
    path: ${n.pascal}Routes.root,
    builder: (context, state) => const ${n.pascal}Screen(),
  ),
];
''';

String _routesTest(FeatureNames n) => '''
import 'package:${n.package}/${n.package}.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  group('${n.camel}Routes', () {
    final paths = ${n.camel}Routes
        .whereType<GoRoute>()
        .map((route) => route.path)
        .toList();

    test('contributes the feature route', () {
      expect(paths, [${n.pascal}Routes.root]);
    });
  });
}
''';

// ── domain ───────────────────────────────────────────────────────────────────

String _entity(FeatureNames n) => '''
import 'package:flutter/foundation.dart';

/// A single ${n.snake} item.
@immutable
class ${n.pascal} {
  const ${n.pascal}({required this.id, required this.title});

  final String id;
  final String title;

  @override
  bool operator ==(Object other) =>
      other is ${n.pascal} && other.id == id && other.title == title;

  @override
  int get hashCode => Object.hash(id, title);
}
''';

String _repositoryInterface(FeatureNames n) => '''
import 'package:architecture/architecture.dart';

import '../entities/${n.snake}.dart';

/// Defines the data contract for the ${n.snake} feature.
///
/// Implementations may source data locally (in-memory or ObjectBox) or
/// remotely (REST API). The presentation layer always talks to this interface.
abstract interface class ${n.pascal}Repository {
  /// Returns all ${n.snake} items.
  Future<Result<List<${n.pascal}>>> list();

  /// Creates a new ${n.snake} item with the given [title].
  Future<Result<${n.pascal}>> create(String title);
}
''';

// ── data — local source ───────────────────────────────────────────────────────

String _localDataSource(FeatureNames n) => '''
import 'package:injectable/injectable.dart';

import '../../domain/entities/${n.snake}.dart';

/// In-memory store for ${n.snake} items.
///
/// This is a minimal development store — no persistence across restarts.
/// Swap for an ObjectBox-backed implementation using `package:database` when
/// you need durability; see `packages/features/bookmarks` for the pattern.
abstract interface class ${n.pascal}LocalDataSource {
  Future<List<${n.pascal}>> listAll();
  Future<${n.pascal}> insert(${n.pascal} item);
}

@LazySingleton(as: ${n.pascal}LocalDataSource)
class InMemory${n.pascal}DataSource implements ${n.pascal}LocalDataSource {
  final List<${n.pascal}> _store = [];

  @override
  Future<List<${n.pascal}>> listAll() async => List.unmodifiable(_store);

  @override
  Future<${n.pascal}> insert(${n.pascal} item) async {
    _store.add(item);
    return item;
  }
}
''';

String _localRepositoryImpl(FeatureNames n) => '''
import 'package:architecture/architecture.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/${n.snake}.dart';
import '../../domain/repositories/${n.snake}_repository.dart';
import '../local/${n.snake}_local_data_source.dart';

@LazySingleton(as: ${n.pascal}Repository)
class ${n.pascal}RepositoryImpl implements ${n.pascal}Repository {
  ${n.pascal}RepositoryImpl(this._local, this._uuid);

  final ${n.pascal}LocalDataSource _local;
  final Uuid _uuid;

  @override
  Future<Result<List<${n.pascal}>>> list() async {
    final rows = await _local.listAll();
    return Ok(rows);
  }

  @override
  Future<Result<${n.pascal}>> create(String title) async {
    final item = ${n.pascal}(id: _uuid.v4(), title: title.trim());
    final saved = await _local.insert(item);
    return Ok(saved);
  }
}
''';

// ── data — API source ─────────────────────────────────────────────────────────

String _dto(FeatureNames n) => '''
import 'package:json_annotation/json_annotation.dart';

part '${n.snake}_dto.g.dart';

/// Wire representation of a ${n.snake} item returned by the API.
@JsonSerializable(fieldRename: FieldRename.snake)
class ${n.pascal}Dto {
  const ${n.pascal}Dto({required this.id, required this.title});

  factory ${n.pascal}Dto.fromJson(Map<String, dynamic> json) =>
      _\$${n.pascal}DtoFromJson(json);

  final String id;
  final String title;

  Map<String, dynamic> toJson() => _\$${n.pascal}DtoToJson(this);
}
''';

String _remoteDataSource(FeatureNames n) => '''
import 'package:network/network.dart';

import '../models/${n.snake}_dto.dart';

part '${n.snake}_remote_data_source.g.dart';

/// Retrofit-generated HTTP client for the ${n.snake} API endpoint.
@RestApi()
abstract class ${n.pascal}RemoteDataSource {
  factory ${n.pascal}RemoteDataSource(Dio dio, {String baseUrl}) =
      _${n.pascal}RemoteDataSource;

  @GET('/api/${n.kebab}')
  Future<List<${n.pascal}Dto>> list();

  @POST('/api/${n.kebab}')
  Future<${n.pascal}Dto> create(@Body() Map<String, dynamic> body);
}
''';

String _remoteModule(FeatureNames n) => '''
import 'package:injectable/injectable.dart';
import 'package:network/network.dart';

import '${n.snake}_remote_data_source.dart';

/// Provides [${n.pascal}RemoteDataSource] using the app-wide authenticated [Dio].
///
/// The shared `Dio` instance (with auth interceptor) is injected by the
/// `NetworkPackageModule`; this `@module` wires it into the feature's DI graph.
@module
abstract class ${n.pascal}RemoteModule {
  @lazySingleton
  ${n.pascal}RemoteDataSource provide${n.pascal}RemoteDataSource(Dio dio) =>
      ${n.pascal}RemoteDataSource(dio);
}
''';

String _apiRepositoryImpl(FeatureNames n) => '''
import 'package:architecture/architecture.dart';
import 'package:injectable/injectable.dart';
import 'package:network/network.dart';

import '../../domain/entities/${n.snake}.dart';
import '../../domain/repositories/${n.snake}_repository.dart';
import '../datasources/${n.snake}_remote_data_source.dart';

@LazySingleton(as: ${n.pascal}Repository)
class ${n.pascal}RepositoryImpl implements ${n.pascal}Repository {
  ${n.pascal}RepositoryImpl(this._remote);

  final ${n.pascal}RemoteDataSource _remote;

  @override
  Future<Result<List<${n.pascal}>>> list() async {
    try {
      final dtos = await _remote.list();
      return Ok(dtos.map((d) => ${n.pascal}(id: d.id, title: d.title)).toList());
    } on DioException catch (e) {
      return Err(UnknownFailure(e.message ?? 'Network error'));
    }
  }

  @override
  Future<Result<${n.pascal}>> create(String title) async {
    try {
      final dto = await _remote.create({'title': title.trim()});
      return Ok(${n.pascal}(id: dto.id, title: dto.title));
    } on DioException catch (e) {
      return Err(UnknownFailure(e.message ?? 'Network error'));
    }
  }
}
''';

// ── data — sync stubs ─────────────────────────────────────────────────────────

String _syncAdapter(FeatureNames n) => '''
// TODO(sync): Implement [SyncRemoteAdapter] for ${n.pascal}.
//
// Steps:
//  1. Add an ObjectBox `@Entity` class for ${n.pascal} to `packages/database`
//     that implements [Syncable] (see BookmarkEntity for the pattern).
//     Run `dart run build_runner build` inside `packages/database` afterwards.
//  2. Replace this stub file with a concrete class:
//
//       class ${n.pascal}SyncAdapter
//           implements SyncRemoteAdapter<${n.pascal}Entity> {
//         @override
//         String get resource => '${n.kebab}';
//         // … create / update / delete / listSince …
//       }
//
//     Map your DTO to [RemoteRecord<${n.pascal}Entity>] and translate
//     `DioException` into [SyncTransientException] / [SyncTerminalException].
//     See bookmarks_sync_adapter.dart for the full pattern.
//  3. Wire the adapter and [OfflineCrudSync] in [${n.pascal}SyncController].
//  4. See SYNC_TODO.md in this package for the full checklist.

/// Resource key used when the sync cursor is stored.
///
/// This constant is the only thing the stub exports so other stubs can
/// reference it without importing unfinished code. Replace this file with the
/// real adapter implementation once the ObjectBox entity is in place.
const String ${n.camel}SyncResource = '${n.kebab}';
''';

String _syncController(FeatureNames n) => '''
import 'package:rev_sync/rev_sync.dart';

// TODO(sync): Implement [${n.pascal}SyncController].
//
// The controller owns the sync lifecycle (start / stop / trigger) and wraps
// an [OfflineCrudSync] instance configured with your adapter and local store.
// See `BookmarksSyncController` + its implementation in the bookmarks feature
// for the full pattern:
//   packages/features/bookmarks/lib/src/domain/services/bookmarks_sync_controller.dart
//
// After implementing, register it in DI and wire it in `lib/app/features.dart`
// inside the `_${n.pascal}Module`:
//
//   @override
//   Future<void> onSignIn(Session session) async =>
//       getIt<${n.pascal}SyncController>().start();
//
//   @override
//   Future<void> onSignOut(Session session) async =>
//       getIt<${n.pascal}SyncController>().stop();

/// Controls the ${n.snake} offline-first sync lifecycle.
///
/// This is a minimal stub. Implement the full contract once you have an
/// ObjectBox entity and a complete [SyncRemoteAdapter] (see SYNC_TODO.md).
abstract interface class ${n.pascal}SyncController {
  Stream<SyncStatus> get statusStream;
  SyncStatus get statusNow;
  Future<void> start();
  Future<void> stop();
  Future<void> sync();
}
''';

String _syncTodo(FeatureNames n) => '''
# ${n.pascal} — Sync TODO

The `--source sync` scaffold generated presentation + domain + data (API) layers
and compiling stubs for offline-first sync. Complete the following steps to make
it production-ready.

## 1. Add an ObjectBox entity to `packages/database`

Create an `@Entity` class for `${n.pascal}` in `packages/database/lib/src/`,
following the `BookmarkEntity` pattern. Then run codegen:

```sh
cd packages/database && dart run build_runner build --delete-conflicting-outputs
```

## 2. Implement `${n.pascal}LocalDataSource`

Currently the local layer goes through the remote only. Add a local data source
backed by the ObjectBox entity, implementing `SyncLocalStore<${n.pascal}Entity>`
(see `bookmarks_local_data_source.dart`).

## 3. Implement `${n.pascal}SyncAdapter`

Replace the stub in `lib/src/data/sync/${n.snake}_sync_adapter.dart` with a real
adapter that calls `${n.pascal}RemoteDataSource`, maps DTOs to `RemoteRecord`s,
and translates transport errors.

## 4. Implement `${n.pascal}SyncController`

Replace the stub in
`lib/src/domain/services/${n.snake}_sync_controller.dart` with a real
implementation wrapping `OfflineCrudSync` and `SyncScheduler` (see
`bookmarks_sync_service.dart`). Register it in DI with `@LazySingleton`.

## 5. Wire the controller in `lib/app/features.dart`

Add `onSignIn` / `onSignOut` hooks to `_${n.pascal}Module` to start and stop
the sync controller alongside the user session:

```dart
@override
Future<void> onSignIn(Session session) async =>
    getIt<${n.pascal}SyncController>().start();

@override
Future<void> onSignOut(Session session) async =>
    getIt<${n.pascal}SyncController>().stop();
```

## 6. Make `${n.pascal}RepositoryImpl` offline-first

Once the local store is in place, update `${n.snake}_repository_impl.dart` to
read from the local store (like `BookmarksRepositoryImpl`) and fire the sync
controller on mutations.
''';
