# flutter_starter_template_cli

A CLI tool to scaffold new Flutter projects from [flutter-starter-template](https://github.com/kido-luci/flutter-starter-template) — batteries-included with Firebase, BLoC, GoRouter, ObjectBox or Drift, and more.

## Installation

```bash
dart pub global activate flutter_starter_template_cli
```

Make sure `~/.pub-cache/bin` is on your `PATH`:

```bash
export PATH="$PATH:$HOME/.pub-cache/bin"
```

## Usage

```bash
fst create
```

The CLI will prompt you for:

| Prompt | Example |
|---|---|
| App display name | `My Awesome App` |
| Dart package name | `my_awesome_app` (auto-derived) |
| Bundle / App ID | `com.acme.myapp` |
| Organisation / author | `Acme Inc` |

After confirmation it will:

1. Clone the template (with submodules) into a new directory
2. Rename every identifier across `pubspec.yaml`, Gradle, Xcode, and `lib/`
3. Move `MainActivity.kt` to the correct package path
4. Run `tool/setup.sh` — installs dependencies and runs code generation

### Options

```
fst create [options]

-n, --name            App display name (skips the prompt)
    --package-name    Dart package name, snake_case (default: derived from --name)
    --bundle-id       Bundle / App ID, reverse-DNS (skips the prompt)
    --org             Organisation / author (skips the prompt)
-o, --output-dir       Directory to create the project in (default: <package-name>)
    --[no-]firebase    Wire Firebase (default on); --no-firebase scaffolds without it
    --[no-]auth        Include the auth pillar (default on); --no-auth removes login,
                       session management, and the auth package
    --[no-]backend     Include the backend pillar (default on); --no-backend removes
                       sync/demo features (auth defaults off; --auth retains JWT)
    --minimal          --no-backend + --no-firebase; the leanest scaffold (not negatable)
    --[no-]document-engine  Include the reusable document engine (default on)
    --[no-]document-center  Include Document Center (default on; requires engine)
    --auth-provider    Auth backend: jwt (default, REST/JWT) or firebase (Firebase Auth)
    --exclude-feature  Demo feature(s) to leave out (repeatable): bookmarks,
                       collections, notifications
    --api-url          Base URL for the staging & prod env files (dev keeps localhost)
    --icon             Path to a square PNG used to generate the launcher icon
    --scheme           In-app theme: a FlexColorScheme name (e.g. deepPurple, indigo)
    --seed-color       Brand color (hex) for the launcher icon + web
    --font             App font: a google_fonts method prefix (e.g. roboto, openSans)
-y, --yes              Run non-interactively: no prompts, no confirmation
    --no-setup         Skip code generation/setup after refreshing the lockfile
```

Each input can be supplied as a flag instead of answering its prompt. When a
flag is given its value is validated and used as-is — an invalid value exits
with an error rather than falling back to a prompt.

### Firebase

By default the project keeps Firebase wired (you then point it at your own
project with `flutterfire configure`). Pass `--no-firebase` (or answer the
prompt) to scaffold **without** Firebase: the app builds and runs with no
Firebase project at all. `--no-firebase` skips the platform initialisation,
swaps the analytics, crash-reporting, and performance bindings to no-ops,
removes the Firebase Android Gradle plugins, and deletes the template's native
Firebase credentials.

It's reversible: set `kFirebaseEnabled` back to `true` in `lib/app/firebase.dart`,
restore the tracking bindings at the `// fst:analytics-impl`,
`// fst:crash-impl`, and `// fst:performance-impl` markers, and run
`flutterfire configure`. Analytics, crash reporting, and performance monitoring
are independent ports — keep one on Firebase and the others no-op by editing
just that binding.

### Excluding demo features

The template ships three demo content features you can leave out:
`bookmarks`, `collections`, `notifications` (the `auth`, `home`, `profile`, and
`splash` core features are always kept). Pass `--exclude-feature` (repeatable) or
deselect them in the interactive multi-select; the CLI strips each feature's
`// fst:feature:<name>` regions from the app wiring and deletes its package.
Because `bookmarks` depends on `collections`, excluding `collections` also
excludes `bookmarks`.

### Optional document packages

Document Engine and Document Center are independently selectable at scaffold
time. The default keeps both. Use `--no-document-center` for an engine-only
project, or `--no-document-engine` for a project without either package.
Document Center cannot exist without Document Engine; an explicit
`--document-center --no-document-engine` combination is rejected. When Document
Engine is excluded, bookmarks and collections remain fully operational (local
storage, sync, and UI), while their optional document import delegates and sheets
are cleanly stripped.

Every generated application has its `pubspec.lock` refreshed and immediately
verified with `flutter pub get --enforce-lockfile`, including when `--no-setup`
is used. `--no-setup` skips code generation and the remaining bootstrap only.

### Optional pillars

Three flags let you strip major pillars at scaffold time so the generated
project compiles cleanly with no leftover stubs.

**`--no-auth`** — Removes the auth pillar. Deletes
`packages/features/auth`, strips auth-specific UI from `profile` (leaving a
Settings screen with theme toggle and about only — the user header,
change-password, delete-account, and sign-out actions are gone), and removes
auth wiring from the router and DI graph. The splash screen waits its minimum
display time then proceeds directly.

**`--no-backend`** — Removes sync and the three server-backed demo features
(`bookmarks`, `collections`, `notifications`). Auth defaults off, preserving
the existing local-only scaffold. Pass `--auth --auth-provider jwt` to retain
the JWT client and auth screens without the sync/demo backend; in that mode the
`network` package remains, but app startup does not require a reachable server.

**`--minimal`** — Equivalent to `--no-backend --no-firebase`. The leanest
possible scaffold: local-only, no Firebase, no accounts. `--minimal` is not
negatable.

Composition rules:
- `--no-backend` defaults to `--no-auth`; explicit `--auth` retains JWT auth.
- `--minimal` forces `--no-backend --no-firebase --no-auth`.

### Compatibility matrix

| Firebase | Backend | Auth | Provider | Supported |
|---:|---:|---:|---|---:|
| on | on | on | `jwt` or `firebase` | yes |
| off | on | on | `jwt` | yes |
| on/off | on | off | n/a | yes |
| on/off | off | off | n/a | yes |
| on/off | off | on | `jwt` | yes |

Both `objectbox` (default) and `drift` work with every supported row.
`--no-setup`, feature exclusions, and a schema-compatible `--template-path`
are orthogonal. Contradictory flags (for example `--minimal --firebase`), an
auth provider with auth disabled, Firebase Auth without all of its required
pillars, and an API URL with no backend or auth consumer are rejected before
the output directory is created. The complete policy and migration guidance
live in the template's `docs/compatibility.md`.

### Adding features

Run `fst add-feature` from a generated project root. It creates the package,
registers workspace dependencies and DI, mounts protected GoRouter routes, and
updates the architecture layer guard before running code generation, analysis,
and tests.

```bash
fst add-feature settings
fst add-feature audit_log --source api --route-path /admin/audit-log
```

Each feature owns a stable named root route and nested `details` route. Route
registration is independent from menu and bottom-navigation registration, so a
new feature is routable without becoming a tab. `--route-path` accepts absolute
lowercase kebab-case segments and rejects collisions before writing files.
`api` and `sync` sources are rejected when their workspace prerequisites were
removed from the generated project.

Every newly generated package contains `.fst-feature.json`, which records its
stable ID, generation mode, routes, and fingerprints of CLI-authored files.
The manifest describes ownership; registrations and dependencies are always
rediscovered from the current project rather than trusted from a cache.

### Listing, validating, and removing features

```bash
fst list-features
fst validate-features
fst remove-feature inventory --dry-run
fst remove-feature inventory --yes
```

`list-features` reports ownership, source mode, route, feature dependencies,
registration completeness, and removability. `validate-features` exits nonzero
for missing packages, dangling workspace dependencies, duplicate routes, or
incomplete CLI-owned registrations.

Removal is deliberately conservative. A reverse dependency blocks deletion;
the command never cascade-deletes. Manually authored packages are not removed.
Changed or additional files inside a manifest-owned package also block removal
unless `--force-modified` explicitly authorizes them. `--yes` confirms only the
destructive operation and does not override either ownership or modification
checks. Unmodified features from older CLI versions are removable only when
their complete scaffold exactly matches a known generator version.

Before writing, the CLI prints a plan covering directories, shared files,
routes, DI, and dependents. `--dry-run` performs no writes. A real removal takes
a byte-for-byte source snapshot, updates the four owned registration points,
regenerates DI, and runs analysis and tests. Any failure restores the snapshot.
The snapshot is in memory, so an operating-system kill or power loss cannot be
automatically recovered; commit or otherwise back up valuable work first.

### Reusable workspace packages

```bash
fst create-package inventory_contracts --type contracts
fst create-package inventory_storage --type infrastructure \
  --dependency inventory_contracts
fst create-package inventory_ui --type ui --dependency inventory_contracts
fst validate-package inventory_ui
```

Package types are `contracts`, `infrastructure`, `platform`, `ui`, and `dev`.
`--dependency` is repeatable, `--dry-run` is strictly no-write, and
`--no-verify` defers pub resolution, analysis, and package tests. Generated
packages receive `.fst-package.json`, a single public entrypoint, a focused
test, workspace/category/layer registration, and transactional rollback.

Dependencies on unknown packages, the application shell, feature
implementations, invalid categories, runtime test utilities, and cycles are
rejected. `validate-package` also detects private `lib/src/` imports, public SDK
leakage, missing tests/files, and invalid manifests. Local application
templates can declare the versioned `.fst-template.json` schema; incompatible
declared versions fail before copying.

### Listing and removing reusable packages

```bash
fst list-packages
fst remove-package inventory_contracts --dry-run
fst remove-package inventory_contracts --yes
```

`list-packages` discovers packages from their actual `pubspec.yaml` files and
reports type, workspace location, ownership, runtime/development dependencies,
direct and transitive consumers, validation state, and removal eligibility.
Ownership is never inferred from a name: a valid `.fst-package.json` is needed
for CLI ownership. Known packages from older templates are shown as `legacy`,
and other packages without a manifest are `manual`; neither category can be
removed by `remove-package`. Core template, feature, and published packages are
protected even if a manifest is present.

Removal is blocked while the application shell or any remaining workspace
package consumes the target. Dependents are reported but never modified or
cascade-deleted. The command also refuses malformed ownership manifests and
changed or additional files. `--force-modified` is a separate, explicit grant
to delete those changes inside an otherwise valid CLI-owned package; `--yes`
only answers the confirmation prompt.

Before writing, `remove-package` prints every generated path, workspace file,
direct/transitive consumer, and blocker. `--dry-run` invokes no generator or
verification process and leaves every byte unchanged. A real removal updates
the root workspace and architecture category/layer registrations, deletes the
verified package directory, resolves dependencies, regenerates code, analyzes,
and tests. Any ordinary process or validation failure restores source files,
generated files, lockfiles, and directories byte-for-byte from the in-memory
`ProjectSnapshot`. This is not crash-safe against `SIGKILL`, power loss, or
machine failure.

### API base URL & launcher icon

- `--api-url https://api.acme.com` rewrites `API_BASE_URL` in `env/staging.json`
  and `env/prod.json` (dev keeps `http://localhost:8080`). Blank/omitted keeps
  the template values.
- `--icon path/to/icon.png` copies a square PNG into `tool/launcher_icons/` and
  runs `flutter_launcher_icons` after setup. Omitted keeps the template icon.

### Non-interactive (CI / scripts)

Pass `--yes` to skip every prompt and the confirmation. It requires `--name`,
`--bundle-id`, and `--org`; `--package-name` defaults to the snake_case form of
`--name`. A missing required flag exits non-zero with a clear message.

```bash
fst create \
  --yes \
  --name "Acme App" \
  --bundle-id com.acme.app \
  --org "Acme Inc" \
  --output-dir ./acme_app
```

### Example

```
$ fst create

  Flutter Starter Template — project scaffold

  App display name: Acme App
  Dart package name (snake_case): acme_app
  Bundle / App ID (reverse-DNS): com.acme.app
  Organisation / author: Acme Inc

  Project summary
  Display name   Acme App
  Package name   acme_app
  Bundle ID      com.acme.app
  Organisation   Acme Inc
  Output dir     /Users/you/acme_app

  Create project? (Y/n) y

  ✓ Template cloned
  ✓ Identifiers renamed
  ✓ Dependencies installed & code generated

  Project created at /Users/you/acme_app

  ⚠ Firebase is still wired to the template. lib/firebase_options.dart points
    at the template Firebase project, so the app will use it until you
    reconfigure it for your own project.

  Next steps:
    cd acme_app

    # Point Firebase at your own project:
    dart pub global activate flutterfire_cli  # if not installed
    flutterfire configure

    # Then run the app:
    fvm flutter run
```

> **Firebase is not yours yet.** `fst create` only renames identifiers — it does
> not touch your Firebase credentials. The generated `lib/firebase_options.dart`
> (and any native config) still targets the template's Firebase project. Run
> [`flutterfire configure`](https://firebase.google.com/docs/flutter/setup) to
> point the app at your own project before shipping.

## Requirements

- Dart SDK `>=3.4.0`
- `git` on your `PATH` (for cloning the template)
- [FVM](https://fvm.app) (recommended) or a Flutter SDK on your `PATH`

## What the template includes

See the [flutter-starter-template README](https://github.com/kido-luci/flutter-starter-template) for the full feature list.

## Contributing

The source lives at [`published/cli/`](https://github.com/kido-luci/flutter-starter-template/tree/main/published/cli) inside the main template repository, and is mirrored here as a standalone package for pub.dev.

1. Fork [`flutter-starter-template-cli`](https://github.com/kido-luci/flutter-starter-template-cli)
2. Make changes and run `dart test`
3. Open a pull request

## License

[MIT](LICENSE)
