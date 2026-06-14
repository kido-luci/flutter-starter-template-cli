final _packageNameRe = RegExp(r'^[a-z][a-z0-9_]*$');
final _bundleIdRe = RegExp(r'^[a-zA-Z][a-zA-Z0-9]*(\.[a-zA-Z][a-zA-Z0-9]*){1,}$');

bool isValidPackageName(String v) => _packageNameRe.hasMatch(v);

bool isValidBundleId(String v) => _bundleIdRe.hasMatch(v);

/// Converts a display name to a snake_case Dart package name.
/// "My Awesome App" → "my_awesome_app"
String toSnakeCase(String displayName) {
  return displayName
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}
