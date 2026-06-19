# Changelog

## 0.5.0

- `fst create` can now scaffold without Firebase. A `--[no-]firebase` flag (and
  an interactive prompt) chooses; the default stays on, so existing behaviour is
  unchanged.
- `--no-firebase` produces a project that builds and runs with no Firebase
  project: it flips the `kFirebaseEnabled` platform flag, swaps the analytics and
  crash-reporting bindings to no-ops, removes the Firebase Android Gradle
  plugins, and deletes the template's native Firebase credential files.
- Requires the template's tracking-ports refactor (analytics/crash behind
  swappable bindings + a `kFirebaseEnabled` flag) to be present in the cloned
  template.

## 0.4.0

- `fst create` can now run non-interactively. Each input has a flag
  (`--name`/`-n`, `--package-name`, `--bundle-id`, `--org`), and `--yes`/`-y`
  skips all prompts and the confirmation for use in CI and scripts.
- `--yes` requires `--name`, `--bundle-id`, and `--org`; `--package-name` is
  derived from `--name` when omitted. A missing required flag, or any invalid
  flag value, exits non-zero with a clear message instead of prompting.
- The non-interactive input resolution is a pure, unit-tested function.

## 0.3.0

- `fst create` now produces a clean slate: it removes the vendored submodules
  (the demo backend and the CLI's own source) and the template's git history,
  then runs `git init` so the new project starts from its own first commit.
- The generated project gets a minimal, project-specific `README.md` instead of
  the template's documentation.
- The identifier rewriter no longer walks `.git/`.

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
