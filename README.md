# flutter_starter_template_cli

A CLI tool to scaffold new Flutter projects from [flutter-starter-template](https://github.com/kido-luci/flutter-starter-template) — batteries-included with Firebase, BLoC, auto_route, ObjectBox, and more.

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
-o, --output-dir      Directory to create the project in (default: <package-name>)
-y, --yes             Run non-interactively: no prompts, no confirmation
    --no-setup        Skip running tool/setup.sh after scaffolding
```

Each input can be supplied as a flag instead of answering its prompt. When a
flag is given its value is validated and used as-is — an invalid value exits
with an error rather than falling back to a prompt.

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

The source lives at [`tool/cli/`](https://github.com/kido-luci/flutter-starter-template/tree/main/tool/cli) inside the main template repository, and is mirrored here as a standalone package for pub.dev.

1. Fork [`flutter-starter-template-cli`](https://github.com/kido-luci/flutter-starter-template-cli)
2. Make changes and run `dart test`
3. Open a pull request

## License

[MIT](LICENSE)
