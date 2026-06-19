import 'dart:io';

import 'package:path/path.dart' as p;

/// Thrown when a Firebase rewrite can't find an expected marker, so the command
/// can report which file drifted instead of silently producing a half-disabled
/// project.
class FirebaseRewriteException implements Exception {
  FirebaseRewriteException(this.message);
  final String message;
  @override
  String toString() => 'FirebaseRewriteException: $message';
}

/// Sets the `kFirebaseEnabled` platform flag in `lib/app/firebase.dart`.
///
/// Idempotent: flipping to the value it already holds is a no-op.
String setFirebaseEnabled(String content, {required bool enabled}) {
  final target = 'const bool kFirebaseEnabled = $enabled;';
  if (content.contains(target)) return content;
  final other = 'const bool kFirebaseEnabled = ${!enabled};';
  if (!content.contains(other)) {
    throw FirebaseRewriteException(
      'Could not find a `kFirebaseEnabled` declaration in lib/app/firebase.dart.',
    );
  }
  return content.replaceFirst(other, target);
}

/// Replaces the expression on the line tagged with `// <marker>` with
/// [replacement], preserving the line's indentation and the trailing marker.
///
/// Used to swap a tracking binding to its no-op (e.g. `fst:analytics-impl`).
/// Idempotent. Throws [FirebaseRewriteException] if the marker is absent.
String replaceMarkedExpression(
  String content, {
  required String marker,
  required String replacement,
}) {
  final lines = content.split('\n');
  // Skip doc comments that merely mention the marker; target the binding line.
  final index = lines.indexWhere(
    (line) => line.contains('// $marker') && !line.trimLeft().startsWith('///'),
  );
  if (index == -1) {
    throw FirebaseRewriteException(
      'Marker "$marker" not found on a code line. Add it back so the rewrite '
      'knows which binding to swap, then retry.',
    );
  }
  final line = lines[index];
  final beforeMarker = line.substring(0, line.indexOf('// $marker'));
  // Preserve an arrow-function prefix when the whole binding is on one line
  // (e.g. `Foo provideFoo() => bar(); // marker`); otherwise the marker line is
  // just the wrapped expression, so preserve only its indentation.
  final arrowIndex = beforeMarker.indexOf('=>');
  final prefix = arrowIndex == -1
      ? RegExp(r'^(\s*)').firstMatch(beforeMarker)!.group(1)!
      : '${beforeMarker.substring(0, arrowIndex + 2)} ';
  lines[index] = '$prefix$replacement // $marker';
  return lines.join('\n');
}

/// Removes the three Firebase Gradle plugin lines (`google-services`,
/// `firebase-perf`, `crashlytics`) from an Android `build.gradle.kts`.
///
/// Leaves every other plugin (notably the Flutter Gradle plugin) intact.
/// Idempotent.
String removeFirebaseGradlePlugins(String content) {
  const firebasePluginIds = [
    'com.google.gms.google-services',
    'com.google.firebase.firebase-perf',
    'com.google.firebase.crashlytics',
  ];
  final lines = content.split('\n')
    ..removeWhere(
      (line) => firebasePluginIds.any(line.contains),
    );
  return lines.join('\n');
}

/// Disables Firebase in a freshly scaffolded [projectDir]: flips
/// `kFirebaseEnabled`, swaps the analytics/crash bindings to their no-ops,
/// removes the Firebase Android Gradle plugins, and deletes the native
/// credential files so the project builds and runs without a Firebase project.
Future<void> disableFirebase(String projectDir) async {
  // 1. Flip the platform flag so main.dart skips Firebase init.
  _rewriteFile(
    p.join(projectDir, 'lib', 'app', 'firebase.dart'),
    (content) => setFirebaseEnabled(content, enabled: false),
  );

  // 2. Swap the tracking bindings to their no-ops.
  _rewriteFile(
    p.join(projectDir, 'packages', 'analytics', 'lib', 'src',
        'analytics_module.dart'),
    (content) => replaceMarkedExpression(
      content,
      marker: 'fst:analytics-impl',
      replacement: 'const NoOpAnalyticsService();',
    ),
  );
  _rewriteFile(
    p.join(projectDir, 'packages', 'app_platform', 'lib', 'src', 'crash',
        'crash_module.dart'),
    (content) => replaceMarkedExpression(
      content,
      marker: 'fst:crash-impl',
      replacement: 'const NoOpCrashReporter();',
    ),
  );

  // 3. Remove the Firebase Android Gradle plugins (google-services requires
  //    google-services.json at build time, which step 4 deletes).
  _rewriteFile(
    p.join(projectDir, 'android', 'app', 'build.gradle.kts'),
    removeFirebaseGradlePlugins,
  );

  // 4. Delete native credential files so no template credentials ship and the
  //    native SDKs don't auto-initialise the template project.
  for (final relative in const [
    'android/app/google-services.json',
    'ios/Runner/GoogleService-Info.plist',
    'firebase.json',
  ]) {
    final file = File(p.join(projectDir, p.joinAll(relative.split('/'))));
    if (file.existsSync()) file.deleteSync();
  }
}

void _rewriteFile(String path, String Function(String) transform) {
  final file = File(path);
  if (!file.existsSync()) {
    throw FirebaseRewriteException('Expected file not found: $path');
  }
  file.writeAsStringSync(transform(file.readAsStringSync()));
}
