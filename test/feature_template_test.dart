import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
import 'package:test/test.dart';

void main() {
  group('featureFiles', () {
    group('source: presentation (default)', () {
      final files = featureFiles(FeatureNames('settings'));

      test('produces the expected scaffold file set', () {
        expect(
          files.keys,
          containsAll(<String>[
            'pubspec.yaml',
            'lib/feature_settings.dart',
            'lib/src/di.dart',
            'lib/src/locator.dart',
            'lib/src/presentation/bloc/settings_cubit.dart',
            'lib/src/presentation/bloc/settings_state.dart',
            'lib/src/presentation/screens/settings_screen.dart',
            'lib/src/presentation/settings_routes.dart',
            'test/presentation/settings_routes_test.dart',
          ]),
        );
      });

      test('does not include domain or data files', () {
        expect(
          files.keys,
          isNot(
            anyOf(
              contains('lib/src/domain/entities/settings.dart'),
              contains(
                  'lib/src/data/repositories/settings_repository_impl.dart'),
            ),
          ),
        );
      });

      test('pubspec declares the feature package name', () {
        expect(files['pubspec.yaml'], contains('name: feature_settings'));
      });

      test('pubspec does not include architecture dependency', () {
        expect(files['pubspec.yaml'], isNot(contains('architecture:')));
      });

      test('barrel exports the generated package module', () {
        expect(
          files['lib/feature_settings.dart'],
          contains(
            "export 'src/di.module.dart' show FeatureSettingsPackageModule;",
          ),
        );
      });

      test('di anchor uses the feature-specific init function', () {
        expect(
            files['lib/src/di.dart'], contains('void initSettingsFeature()'));
      });

      test('routes file mounts the screen at the kebab path', () {
        final routes = files['lib/src/presentation/settings_routes.dart']!;
        expect(routes, contains("static const root = '/settings';"));
        expect(routes, contains('List<RouteBase> get settingsRoutes'));
      });

      test('cubit has no repository dependency', () {
        final cubit = files['lib/src/presentation/bloc/settings_cubit.dart']!;
        expect(cubit, isNot(contains('Repository')));
        expect(cubit, contains('void load()'));
      });
    });

    group('source: local', () {
      final files =
          featureFiles(FeatureNames('tasks'), source: FeatureSource.local);

      test('produces the expected scaffold file set', () {
        expect(
          files.keys,
          containsAll(<String>[
            'pubspec.yaml',
            'lib/feature_tasks.dart',
            'lib/src/di.dart',
            'lib/src/locator.dart',
            'lib/src/presentation/bloc/tasks_cubit.dart',
            'lib/src/presentation/bloc/tasks_state.dart',
            'lib/src/presentation/screens/tasks_screen.dart',
            'lib/src/presentation/tasks_routes.dart',
            'lib/src/domain/entities/tasks.dart',
            'lib/src/domain/repositories/tasks_repository.dart',
            'lib/src/data/local/tasks_local_data_source.dart',
            'lib/src/data/repositories/tasks_repository_impl.dart',
          ]),
        );
      });

      test('does not include API or sync files', () {
        expect(
          files.keys,
          isNot(
            anyOf(
              contains('lib/src/data/models/tasks_dto.dart'),
              contains(
                  'lib/src/data/datasources/tasks_remote_data_source.dart'),
              contains('lib/src/data/sync/tasks_sync_adapter.dart'),
              contains('SYNC_TODO.md'),
            ),
          ),
        );
      });

      test('pubspec includes architecture and uuid dependencies', () {
        final pubspec = files['pubspec.yaml']!;
        expect(pubspec, contains('architecture: ^0.1.0'));
        expect(pubspec, contains('uuid: ^4.5.3'));
      });

      test('pubspec does not include network or rev_sync', () {
        final pubspec = files['pubspec.yaml']!;
        expect(pubspec, isNot(contains('network:')));
        expect(pubspec, isNot(contains('rev_sync')));
      });

      test('entity file defines the Tasks class', () {
        expect(files['lib/src/domain/entities/tasks.dart'],
            contains('class Tasks'));
      });

      test('repository interface uses Result return types', () {
        final repo =
            files['lib/src/domain/repositories/tasks_repository.dart']!;
        expect(repo, contains('Future<Result<List<Tasks>>> list()'));
        expect(repo, contains('Future<Result<Tasks>> create(String title)'));
      });

      test('local data source is in-memory', () {
        final src = files['lib/src/data/local/tasks_local_data_source.dart']!;
        expect(src, contains('InMemory'));
        expect(src, contains('final List<Tasks> _store'));
      });

      test('barrel exports the entity', () {
        expect(
          files['lib/feature_tasks.dart'],
          contains("export 'src/domain/entities/tasks.dart'"),
        );
      });

      test('cubit depends on the repository', () {
        final cubit = files['lib/src/presentation/bloc/tasks_cubit.dart']!;
        expect(cubit, contains('TasksRepository'));
        expect(
            cubit, contains("import 'package:architecture/architecture.dart'"));
      });
    });

    group('source: api', () {
      final files =
          featureFiles(FeatureNames('products'), source: FeatureSource.api);

      test('produces the expected scaffold file set', () {
        expect(
          files.keys,
          containsAll(<String>[
            'pubspec.yaml',
            'lib/src/domain/entities/products.dart',
            'lib/src/domain/repositories/products_repository.dart',
            'lib/src/data/models/products_dto.dart',
            'lib/src/data/datasources/products_remote_data_source.dart',
            'lib/src/data/datasources/products_remote_module.dart',
            'lib/src/data/repositories/products_repository_impl.dart',
          ]),
        );
      });

      test('does not include local data source or sync files', () {
        expect(
          files.keys,
          isNot(
            anyOf(
              contains('lib/src/data/local/products_local_data_source.dart'),
              contains('lib/src/data/sync/products_sync_adapter.dart'),
              contains('SYNC_TODO.md'),
            ),
          ),
        );
      });

      test('pubspec includes network and json_annotation', () {
        final pubspec = files['pubspec.yaml']!;
        expect(pubspec, contains('network: ^0.1.0'));
        expect(pubspec, contains('json_annotation: ^4.12.0'));
        expect(pubspec, contains('retrofit_generator:'));
        expect(pubspec, contains('json_serializable:'));
      });

      test('pubspec does not include rev_sync', () {
        expect(files['pubspec.yaml'], isNot(contains('rev_sync')));
      });

      test('DTO uses json_annotation', () {
        final dto = files['lib/src/data/models/products_dto.dart']!;
        expect(dto,
            contains("import 'package:json_annotation/json_annotation.dart'"));
        expect(dto, contains('@JsonSerializable'));
        expect(dto, contains('class ProductsDto'));
      });

      test('remote data source uses Retrofit RestApi annotation', () {
        final src =
            files['lib/src/data/datasources/products_remote_data_source.dart']!;
        expect(src, contains('@RestApi()'));
        expect(src, contains("import 'package:network/network.dart'"));
      });

      test('remote module provides via Dio', () {
        final mod =
            files['lib/src/data/datasources/products_remote_module.dart']!;
        expect(mod, contains('@module'));
        expect(mod, contains('Dio dio'));
      });

      test('repository impl catches DioException', () {
        final impl =
            files['lib/src/data/repositories/products_repository_impl.dart']!;
        expect(impl, contains('on DioException'));
        expect(impl, contains('UnknownFailure'));
      });
    });

    group('source: sync', () {
      final files =
          featureFiles(FeatureNames('notes'), source: FeatureSource.sync);

      test('produces the expected scaffold file set', () {
        expect(
          files.keys,
          containsAll(<String>[
            'pubspec.yaml',
            'lib/src/domain/entities/notes.dart',
            'lib/src/domain/repositories/notes_repository.dart',
            'lib/src/data/models/notes_dto.dart',
            'lib/src/data/datasources/notes_remote_data_source.dart',
            'lib/src/data/datasources/notes_remote_module.dart',
            'lib/src/data/repositories/notes_repository_impl.dart',
            'lib/src/data/sync/notes_sync_adapter.dart',
            'lib/src/domain/services/notes_sync_controller.dart',
            'SYNC_TODO.md',
          ]),
        );
      });

      test('pubspec includes rev_sync', () {
        final pubspec = files['pubspec.yaml']!;
        expect(pubspec, contains('rev_sync:'));
        expect(pubspec, contains('published/rev_sync'));
      });

      test('sync adapter stub has a TODO and references SyncRemoteAdapter', () {
        final adapter = files['lib/src/data/sync/notes_sync_adapter.dart']!;
        expect(adapter, contains('TODO(sync)'));
        expect(adapter, contains('SyncRemoteAdapter'));
        // Exports the resource key constant so other stubs can reference it.
        expect(adapter, contains('notesSyncResource'));
      });

      test('sync controller stub defines the interface', () {
        final ctrl =
            files['lib/src/domain/services/notes_sync_controller.dart']!;
        expect(ctrl, contains('NotesSyncController'));
        expect(ctrl, contains('SyncStatus'));
        expect(ctrl, contains('TODO(sync)'));
      });

      test('SYNC_TODO.md documents the manual steps', () {
        final todo = files['SYNC_TODO.md']!;
        expect(todo, contains('ObjectBox'));
        expect(todo, contains('SyncAdapter'));
        expect(todo, contains('features.dart'));
      });

      test('barrel exports sync controller', () {
        expect(
          files['lib/feature_notes.dart'],
          contains("export 'src/domain/services/notes_sync_controller.dart'"),
        );
      });

      test('all four sources produce the route file', () {
        for (final source in FeatureSource.values) {
          final f = featureFiles(FeatureNames('demo'), source: source);
          expect(
            f.keys,
            contains('lib/src/presentation/demo_routes.dart'),
            reason: 'source=$source',
          );
        }
      });
    });

    group('idempotency — file set is deterministic', () {
      test(
          'calling featureFiles twice with the same args yields identical maps',
          () {
        for (final source in FeatureSource.values) {
          final a = featureFiles(FeatureNames('repeat'), source: source);
          final b = featureFiles(FeatureNames('repeat'), source: source);
          expect(a, equals(b), reason: 'source=$source');
        }
      });
    });
  });
}
