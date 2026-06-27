# Changelog

## Unreleased

- **Strip orphaned media permissions**: when the `bookmarks` feature is removed
  (`--exclude-feature bookmarks`/`collections`, or `--no-backend`/`--minimal`),
  `fst create` now also strips the camera / microphone / photo-library usage
  declarations from `ios/Runner/Info.plist` and `android/.../AndroidManifest.xml`.
  Those permissions exist only for the bookmarks media-capture flow, and Apple
  and Google both discourage declaring permissions an app never requests. Driven
  by the same `fst:feature:bookmarks` markers used for the Dart wiring.

## 1.2.0

Composable pillars + project-shape knobs, so one template serves many project
shapes.

- **Optional pillars (`fst create`)**: `--no-auth` (scaffold a user-less app;
  `profile` trims to a Settings screen), `--no-backend` (a fully local-only
  app — implies `--no-auth`, drops the server-backed demo features, strips
  `network`/`sync_connectivity_plus`; `rev_sync` stays), and `--minimal`
  (`--no-backend --no-firebase`).
- **Feature sources (`fst add-feature --source`)**: scaffold a data+domain layer
  — `local` (in-feature in-memory store), `api` (Retrofit over the shared
  `Dio`), or `sync` (the `api` layer plus guided offline-first `rev_sync` stubs
  and a `SYNC_TODO.md`). Default `presentation` is unchanged.
- **Branding (`fst create`)**: `--scheme` (in-app FlexColorScheme), `--seed-color`
  (launcher-icon + web brand hex), and `--font` (the Google Fonts text theme).
- **Auth provider (`fst create --auth-provider`)**: `jwt` (default, REST/JWT) or
  `firebase` (swaps the auth data layer for a Firebase Auth implementation).

## 1.1.0

- **`fst create --template-path <dir>`**: scaffold from a local template checkout
  instead of cloning the remote — useful offline, for a fork, or to smoke-test
  the CLI against an unpublished template. VCS and build caches are skipped.
- **Atomic wiring rewrites**: `fst create` feature exclusion and `fst add-feature`
  now compute every file rewrite in memory and validate all markers *before*
  writing anything. A misconfigured project (missing/unclosed marker) fails
  cleanly instead of leaving a half-stripped or half-wired tree. `add-feature`
  also rolls back the scaffolded package if wiring fails.
- Fixed a duplicated hardcoded template bundle ID in the `MainActivity.kt` move
  (now derived from the single template-identifier constant).

## 1.0.1

The template's published submodules were grouped under a top-level `published/`
directory. `fst create` now drops the CLI's own source from `published/cli`
(was `tool/cli`) when cleaning a generated project, and the kept `rev_sync`
submodule is now at `published/rev_sync` (was `packages/rev_sync`). No change to
the `fst` command surface.

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
