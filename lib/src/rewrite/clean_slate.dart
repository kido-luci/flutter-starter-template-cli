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
/// project, so this removes the development-only submodules ([_submoduleDirs])
/// and `.gitmodules`, discards the cloned `.git`, and runs `git init` so the
/// project starts from its own first commit with no upstream baggage.
///
/// Submodules that a generated project *keeps* (e.g. `packages/rev_sync`, a
/// vendored workspace package) are folded in as plain source: their leftover
/// `.git` gitlink is stripped so `git init` tracks their files instead of
/// treating them as embedded repositories.
Future<void> prepareCleanSlate(String projectDir) async {
  for (final relative in _submoduleDirs) {
    final dir = Directory(p.join(projectDir, p.joinAll(relative.split('/'))));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  final gitmodules = File(p.join(projectDir, '.gitmodules'));
  if (gitmodules.existsSync()) gitmodules.deleteSync();

  final gitDir = Directory(p.join(projectDir, '.git'));
  if (gitDir.existsSync()) gitDir.deleteSync(recursive: true);

  // Kept submodules (cloned with --recurse-submodules) leave a `.git` gitlink
  // pointing into the now-deleted superproject git dir. Strip every remaining
  // nested `.git` so `git init` folds their source in as plain tracked files
  // rather than refusing them as embedded repositories.
  _removeNestedGitLinks(Directory(projectDir));

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

/// Deletes every nested `.git` (file or directory) under [root].
///
/// A kept submodule cloned with `--recurse-submodules` has a `.git` gitlink
/// file; removing it lets the freshly `git init`-ed project track the
/// submodule's files as its own plain source.
void _removeNestedGitLinks(Directory root) {
  final gitLinks = <FileSystemEntity>[
    for (final entity in root.listSync(recursive: true, followLinks: false))
      if (p.basename(entity.path) == '.git') entity,
  ];
  for (final entity in gitLinks) {
    if (entity is Directory) {
      entity.deleteSync(recursive: true);
    } else {
      entity.deleteSync();
    }
  }
}
