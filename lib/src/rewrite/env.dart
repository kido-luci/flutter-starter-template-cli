import 'dart:io';

import 'package:path/path.dart' as p;

/// Whether [url] is a usable absolute http(s) base URL.
bool isValidHttpUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      uri.hasScheme &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

/// Replaces the `API_BASE_URL` value in an env JSON string with [url],
/// preserving the file's formatting and other keys.
///
/// Throws [FormatException] if no `API_BASE_URL` key is present.
String setApiBaseUrl(String jsonContent, String url) {
  final pattern = RegExp(r'("API_BASE_URL"\s*:\s*")[^"]*(")');
  if (!pattern.hasMatch(jsonContent)) {
    throw const FormatException('No "API_BASE_URL" key found in env file.');
  }
  return jsonContent.replaceAllMapped(
    pattern,
    (match) => '${match[1]}$url${match[2]}',
  );
}

/// Sets `API_BASE_URL` to [url] in the staging and prod env files under
/// [projectDir]. `dev` keeps its local default. No-op if a file is absent.
Future<void> applyApiBaseUrl(String projectDir, String url) async {
  for (final relative in const ['env/staging.json', 'env/prod.json']) {
    final file = File(p.join(projectDir, p.joinAll(relative.split('/'))));
    if (!file.existsSync()) continue;
    file.writeAsStringSync(setApiBaseUrl(file.readAsStringSync(), url));
  }
}
