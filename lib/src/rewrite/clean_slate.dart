import 'dart:io';

import 'package:path/path.dart' as p;

/// Vendored submodule directories that exist for template development and
/// should not ship inside a generated project: the demo backend and the CLI's
/// own source.
const _submoduleDirs = ['simple_backend_server', 'tool/cli'];

/// Strips template-development baggage from a freshly cloned [projectDir] and
/// re-initialises a fresh git repository.
///
/// `fst create` clones with `--recurse-submodules`, which drags in the demo
/// backend, the CLI's own source, a `.gitmodules` pointing at the template's
/// repos, and the template's commit history. None of that belongs in a new
/// project, so this removes the submodules and `.gitmodules`, discards the
/// cloned `.git`, and runs `git init` so the project starts from its own first
/// commit with no upstream baggage.
Future<void> prepareCleanSlate(String projectDir) async {
  for (final relative in _submoduleDirs) {
    final dir = Directory(p.join(projectDir, p.joinAll(relative.split('/'))));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  final gitmodules = File(p.join(projectDir, '.gitmodules'));
  if (gitmodules.existsSync()) gitmodules.deleteSync();

  final gitDir = Directory(p.join(projectDir, '.git'));
  if (gitDir.existsSync()) gitDir.deleteSync(recursive: true);

  final initResult = await Process.run(
    'git',
    ['init', '-q'],
    workingDirectory: projectDir,
  );
  if (initResult.exitCode != 0) {
    throw ProcessException(
      'git',
      ['init', '-q'],
      initResult.stderr.toString(),
      initResult.exitCode,
    );
  }
}
