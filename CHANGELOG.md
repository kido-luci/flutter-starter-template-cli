# Changelog

## 0.2.0

- `fst create` now warns that the generated `lib/firebase_options.dart` still
  points at the template's Firebase project, and prints the
  `flutterfire configure` steps to reconfigure it for the new project.

## 0.1.0

- Initial release: `fst create` command scaffolds a new Flutter project from
  [flutter-starter-template](https://github.com/kido-luci/flutter-starter-template).
- Interactive prompts for display name, package name, bundle ID, and organisation.
- Renames all template identifiers across pubspec, Gradle, Xcode project, and `lib/`.
- Moves `MainActivity.kt` to the correct package directory.
- Optionally runs `tool/setup.sh` to install dependencies and generate code.
