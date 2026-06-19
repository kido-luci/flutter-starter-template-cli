import 'dart:io';

import 'package:path/path.dart' as p;

/// Whether [path] names a PNG file by its extension (case-insensitive).
///
/// `flutter_launcher_icons` consumes PNG source images, so the CLI accepts only
/// `.png` for `--icon`. Existence is checked separately by the command (IO).
bool isPngPath(String path) => path.toLowerCase().endsWith('.png');

/// Copies [iconPath] into the project's `tool/launcher_icons/` as both the icon
/// and its adaptive foreground, where `flutter_launcher_icons` (already
/// configured in `pubspec.yaml`) reads them.
///
/// The caller runs the generator afterwards (it needs resolved dependencies).
void installLauncherIcon(String projectDir, String iconPath) {
  final dest = Directory(p.join(projectDir, 'tool', 'launcher_icons'))
    ..createSync(recursive: true);
  for (final name in const ['app_icon.png', 'app_icon_foreground.png']) {
    File(iconPath).copySync(p.join(dest.path, name));
  }
}
