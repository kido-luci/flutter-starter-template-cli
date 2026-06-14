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

-o, --output-dir    Directory to create the project in (default: <package-name>)
    --no-setup      Skip running tool/setup.sh after scaffolding
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

  Next steps:
    cd acme_app
    fvm flutter run
```

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

MIT
