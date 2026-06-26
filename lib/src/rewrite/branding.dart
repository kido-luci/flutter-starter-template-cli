import 'dart:io';

import 'package:path/path.dart' as p;

/// Thrown when a branding rewrite can't find an expected anchor, so the command
/// can report which file drifted instead of silently producing a mis-branded
/// project.
class BrandingRewriteException implements Exception {
  BrandingRewriteException(this.message);
  final String message;
  @override
  String toString() => 'BrandingRewriteException: $message';
}

/// The schemes exposed by the app's color picker.
///
/// Used to validate `--scheme` values.
const validFlexSchemes = {
  'material',
  'deepPurple',
  'indigo',
  'blue',
  'green',
  'red',
  'mango',
  'gold',
  'sakura',
  'hippieBlue',
  'aquaBlue',
  'jungle',
  'bahamaBlue',
};

/// The hex pattern for a brand color: `#` followed by exactly 6 hex digits.
final _hexRe = RegExp(r'^#[0-9A-Fa-f]{6}$');

/// Normalises a `--seed-color` value to `#RRGGBB` uppercase.
///
/// Accepts with or without a leading `#`. Returns `null` if the format is
/// invalid.
String? normaliseSeedColor(String raw) {
  final trimmed = raw.trim();
  final withHash = trimmed.startsWith('#') ? trimmed : '#$trimmed';
  if (!_hexRe.hasMatch(withHash)) return null;
  return '#${withHash.substring(1).toUpperCase()}';
}

/// Returns `true` if [name] is a valid lowerCamelCase Dart identifier.
///
/// Used to validate `--font` values (the google_fonts method prefix, e.g.
/// `roboto`, `openSans`).
bool isValidFontName(String name) =>
    RegExp(r'^[a-zA-Z][a-zA-Z0-9]*$').hasMatch(name) && name.isNotEmpty;

// ── Pure rewrite functions ───────────────────────────────────────────────────

/// Replaces the `FlexScheme.bahamaBlue` default-scheme anchor in
/// `packages/theme/lib/src/theme_state.dart` with `FlexScheme.<name>`.
///
/// Idempotent: if [name] is already the current value the content is returned
/// unchanged. Throws [BrandingRewriteException] if the anchor line is absent.
String setThemeScheme(String content, String name) {
  const anchor = 'static const FlexScheme defaultScheme = FlexScheme.';
  if (!content.contains(anchor)) {
    throw BrandingRewriteException(
      'Could not find the defaultScheme anchor in theme_state.dart. '
      'Expected a line starting with '
      '`static const FlexScheme defaultScheme = FlexScheme.`',
    );
  }
  // Replace the scheme name at the end of the anchor line.
  return content.replaceAllMapped(
    RegExp(r'(static const FlexScheme defaultScheme = FlexScheme\.)(\w+)(;)'),
    (m) => '${m[1]}$name${m[3]}',
  );
}

/// Replaces all three `#095D9E` brand-color occurrences in the root
/// `pubspec.yaml` (`adaptive_icon_background`, web `background_color`, web
/// `theme_color`) with [hex] (already normalised to `#RRGGBB` uppercase).
///
/// Idempotent: returns content unchanged when [hex] is already the active
/// value (original anchor is absent). Throws [BrandingRewriteException] if
/// neither the original anchor nor [hex] is present (the file has drifted).
String setBrandColor(String content, String hex) {
  const original = '#095D9E';
  if (!content.contains(original)) {
    // Either already applied (idempotent) or file has drifted.
    if (content.contains(hex)) return content;
    throw BrandingRewriteException(
      'Could not find the brand color anchor "$original" in pubspec.yaml. '
      'Expected three occurrences for adaptive_icon_background, '
      'background_color, and theme_color.',
    );
  }
  return content.replaceAll(original, hex);
}

/// Replaces both `GoogleFonts.interTextTheme()` calls in
/// `packages/app_ui/lib/src/theme/app_theme.dart` with
/// `GoogleFonts.<font>TextTheme()`.
///
/// Idempotent. Throws [BrandingRewriteException] if the anchor is absent.
String setAppFont(String content, String font) {
  const anchor = 'GoogleFonts.';
  const suffix = 'TextTheme()';
  final pattern = RegExp(r'GoogleFonts\.(\w+)TextTheme\(\)');
  if (!pattern.hasMatch(content)) {
    throw BrandingRewriteException(
      'Could not find a GoogleFonts.*TextTheme() call in app_theme.dart. '
      'Expected calls matching `GoogleFonts.<name>TextTheme()`.',
    );
  }
  // Suppress the unused-variable warnings: anchor/suffix are doc-only.
  assert(anchor.isNotEmpty && suffix.isNotEmpty);
  return content.replaceAllMapped(
    pattern,
    (_) => 'GoogleFonts.${font}TextTheme()',
  );
}

// ── Orchestrator ─────────────────────────────────────────────────────────────

/// Applies the requested branding rewrites to a scaffolded [projectDir].
///
/// Skips any rewrite whose flag is `null` (the template default is kept).
/// Throws [BrandingRewriteException] if an expected anchor is missing.
Future<void> applyBranding(
  String projectDir, {
  String? scheme,
  String? seedColor,
  String? font,
}) async {
  if (scheme != null) {
    _rewriteFile(
      p.join(
        projectDir,
        'packages',
        'theme',
        'lib',
        'src',
        'theme_state.dart',
      ),
      (content) => setThemeScheme(content, scheme),
    );
  }

  if (seedColor != null) {
    _rewriteFile(
      p.join(projectDir, 'pubspec.yaml'),
      (content) => setBrandColor(content, seedColor),
    );
  }

  if (font != null) {
    _rewriteFile(
      p.join(
        projectDir,
        'packages',
        'app_ui',
        'lib',
        'src',
        'theme',
        'app_theme.dart',
      ),
      (content) => setAppFont(content, font),
    );
  }
}

void _rewriteFile(String path, String Function(String) transform) {
  final file = File(path);
  if (!file.existsSync()) {
    throw BrandingRewriteException('Expected file not found: $path');
  }
  file.writeAsStringSync(transform(file.readAsStringSync()));
}
