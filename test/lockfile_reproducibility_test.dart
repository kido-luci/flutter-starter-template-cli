import 'dart:io';

import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
import 'package:test/test.dart';

void main() {
  test('refreshes then enforces the generated application lockfile', () async {
    final calls = <(String, List<String>, String?)>[];

    await refreshGeneratedLockfile(
      '/generated/app',
      useFvm: false,
      flutterExecutable: 'flutter',
      processExecutor: (
        executable,
        arguments, {
        workingDirectory,
      }) async {
        calls.add((executable, arguments, workingDirectory));
        return ProcessResult(1, 0, '', '');
      },
    );

    expect(calls, hasLength(2));
    expect(calls[0].$1, 'flutter');
    expect(calls[0].$2, ['pub', 'get']);
    expect(calls[0].$3, '/generated/app');
    expect(calls[1].$1, 'flutter');
    expect(calls[1].$2, ['pub', 'get', '--enforce-lockfile']);
    expect(calls[1].$3, '/generated/app');
  });

  test('uses the pinned FVM Flutter when available', () async {
    final calls = <(String, List<String>)>[];

    await refreshGeneratedLockfile(
      '/generated/app',
      useFvm: true,
      flutterExecutable: 'ignored-for-fvm',
      processExecutor: (
        executable,
        arguments, {
        workingDirectory,
      }) async {
        calls.add((executable, arguments));
        return ProcessResult(1, 0, '', '');
      },
    );

    expect(calls.first.$1, 'fvm');
    expect(calls.first.$2, ['flutter', 'pub', 'get']);
  });

  test('stops before enforcement when lockfile refresh fails', () async {
    var calls = 0;

    await expectLater(
      refreshGeneratedLockfile(
        '/generated/app',
        useFvm: false,
        flutterExecutable: 'flutter',
        processExecutor: (
          executable,
          arguments, {
          workingDirectory,
        }) async {
          calls++;
          return ProcessResult(1, 65, '', 'resolution failed');
        },
      ),
      throwsA(isA<ProcessException>()),
    );

    expect(calls, 1);
  });

  test('finds Flutter from FLUTTER_ROOT before falling back to PATH', () {
    final root = Directory.systemTemp.createTempSync('fst-flutter-root-');
    addTearDown(() => root.deleteSync(recursive: true));
    final launcher = File('${root.path}/bin/flutter')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('');

    expect(
      findFlutterExecutable(
        resolvedExecutable: '/unrelated/dart',
        environment: {'FLUTTER_ROOT': root.path},
      ),
      launcher.path,
    );
  });

  test('finds Flutter above the embedded Dart SDK', () {
    final root = Directory.systemTemp.createTempSync('fst-embedded-flutter-');
    addTearDown(() => root.deleteSync(recursive: true));
    final launcher = File('${root.path}/bin/flutter')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('');
    final dart = '${root.path}/bin/cache/dart-sdk/bin/dart';

    expect(
      findFlutterExecutable(resolvedExecutable: dart, environment: const {}),
      launcher.path,
    );
  });
}
