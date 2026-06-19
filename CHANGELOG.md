# Changelog

## 1.0.0

Initial release.

`fst create` scaffolds a new Flutter project from
[flutter-starter-template](https://github.com/kido-luci/flutter-starter-template):
it clones the template, drops the vendored submodules and git history (clean
slate), renames every identifier (Dart package, Android/iOS bundle IDs, display
name, organisation), moves `MainActivity.kt`, writes a minimal project README,
and runs `tool/setup.sh`.

Customisation at scaffold time:

- **Interactive or non-interactive.** Prompts by default; `--name`,
  `--package-name`, `--bundle-id`, `--org`, and `--yes` run it unattended in CI
  and scripts.
- **Optional Firebase.** `--[no-]firebase`; `--no-firebase` produces a project
  that builds and runs with no Firebase project (gates the platform init, swaps
  the analytics and crash-reporting bindings to no-ops, removes the Firebase
  Android Gradle plugins, deletes the native credentials).
- **Feature selection.** `--exclude-feature` (or an interactive multi-select)
  drops the demo features (`bookmarks`, `collections`, `notifications`) and
  excises their wiring; excluding `collections` also excludes `bookmarks`.
- **API base URL.** `--api-url` sets `API_BASE_URL` in the staging and prod env
  files (dev keeps its local default).
- **Launcher icon.** `--icon <path.png>` installs a launcher icon and runs
  `flutter_launcher_icons`.

`fst add-feature <name>` scaffolds and wires a presentation-only feature
package.
