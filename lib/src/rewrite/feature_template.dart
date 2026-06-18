import '../feature_names.dart';

/// Returns the scaffold for a new presentation-only feature package, keyed by
/// path relative to `packages/features/<name>/` (POSIX separators).
///
/// Pure and filesystem-free so it can be asserted directly in tests; the
/// command writes each entry under the feature directory.
Map<String, String> featureFiles(FeatureNames n) => {
      'pubspec.yaml': _pubspec(n),
      'lib/${n.package}.dart': _barrel(n),
      'lib/src/di.dart': _di(n),
      'lib/src/locator.dart': _locator(),
      'lib/src/presentation/bloc/${n.snake}_cubit.dart': _cubit(n),
      'lib/src/presentation/bloc/${n.snake}_state.dart': _state(n),
      'lib/src/presentation/screens/${n.snake}_screen.dart': _screen(n),
      'lib/src/presentation/${n.snake}_routes.dart': _routes(n),
      'test/presentation/${n.snake}_routes_test.dart': _routesTest(n),
    };

String _pubspec(FeatureNames n) => '''
name: ${n.package}
description: >-
  ${n.pascal} feature: a self-contained presentation-layer workspace package.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.12.0

resolution: workspace

dependencies:
  flutter:
    sdk: flutter

  # Third-party.
  flutter_bloc: ^9.1.1
  go_router: ^17.3.0
  injectable: ^3.0.0
  get_it: ^9.2.1

dev_dependencies:
  flutter_test:
    sdk: flutter

  build_runner: ^2.15.0
  injectable_generator: ^3.0.2
''';

String _barrel(FeatureNames n) => '''
/// ${n.pascal} feature: a self-contained presentation layer.
///
/// The host app wires `${n.packageModule}` via `externalPackageModulesBefore`
/// and mounts `${n.camel}Routes` through its `FeatureModule`. Internals stay
/// private.
library;

export 'src/di.module.dart' show ${n.packageModule};
export 'src/presentation/${n.snake}_routes.dart';
export 'src/presentation/screens/${n.snake}_screen.dart';
''';

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

String _state(FeatureNames n) => '''
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

String _cubit(FeatureNames n) => '''
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

String _screen(FeatureNames n) => '''
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
