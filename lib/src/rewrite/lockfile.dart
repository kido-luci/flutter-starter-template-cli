import 'dart:io';

import 'package:path/path.dart' as p;

typedef DependencyProcessExecutor = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

Future<ProcessResult> _defaultProcessExecutor(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) =>
    Process.run(executable, arguments, workingDirectory: workingDirectory);

/// Resolves the generated dependency graph, writes its application lockfile,
/// then proves that the resulting lockfile can be enforced unchanged.
Future<void> refreshGeneratedLockfile(
  String projectDir, {
  required bool useFvm,
  String? flutterExecutable,
  DependencyProcessExecutor processExecutor = _defaultProcessExecutor,
}) async {
  final executable =
      useFvm ? 'fvm' : flutterExecutable ?? findFlutterExecutable();
  final prefix = useFvm ? const ['flutter'] : const <String>[];
  for (final arguments in [
    [...prefix, 'pub', 'get'],
    [...prefix, 'pub', 'get', '--enforce-lockfile'],
  ]) {
    final result = await processExecutor(
      executable,
      arguments,
      workingDirectory: projectDir,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        '${result.stderr}\n${result.stdout}',
        result.exitCode,
      );
    }
  }
}

/// Finds the Flutter launcher associated with the running Dart SDK.
///
/// A globally activated CLI may be launched with Flutter's embedded Dart while
/// `flutter` itself is absent from `PATH`. In that case [Platform.resolvedExecutable]
/// lives below `<flutter>/bin/cache/dart-sdk/bin`, so walking its ancestors is
/// deterministic and avoids a machine-specific hard-coded path.
String findFlutterExecutable({
  String? resolvedExecutable,
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  final flutterRoot = env['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    final candidate = p.join(flutterRoot, 'bin', 'flutter');
    if (File(candidate).existsSync()) return candidate;
  }

  var directory = File(
    resolvedExecutable ?? Platform.resolvedExecutable,
  ).parent;
  for (var depth = 0; depth < 6; depth++) {
    final candidate = p.join(directory.path, 'flutter');
    if (File(candidate).existsSync()) return candidate;
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  return 'flutter';
}
