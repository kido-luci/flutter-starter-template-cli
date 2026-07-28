import 'dart:io';

import 'package:path/path.dart' as p;

/// Removes every `fst:template-only:start` … `fst:template-only:end` block
/// (inclusive) from [content].
///
/// Comment-style agnostic (`//` for Dart, `#` for YAML). Idempotent. Throws
/// [FormatException] on an unclosed marker block.
String removeTemplateOnlyRegions(String content) {
  const startNeedle = 'fst:template-only:start';
  const endNeedle = 'fst:template-only:end';
  final kept = <String>[];
  var skipping = false;
  for (final line in content.split('\n')) {
    if (skipping) {
      if (line.contains(endNeedle)) skipping = false;
      continue;
    }
    if (line.contains(startNeedle)) {
      skipping = true;
      continue;
    }
    kept.add(line);
  }
  if (skipping) {
    throw FormatException(
      'Unclosed template-only marker block (missing "$endNeedle"). '
      'Refusing to rewrite to avoid corrupting the file.',
    );
  }
  return kept.join('\n');
}

/// Files carrying `fst:template-only` regions.
///
/// These describe how *this repository* is developed and released, not how a
/// project built from it is. The clearest case is the submodule checkouts: the
/// template vendors `published/rev_sync` and `published/cli` as submodules, a
/// scaffold gets plain copied directories and no `.gitmodules` at all — so
/// `git submodule update --init published/rev_sync` exits 1 and takes the whole
/// job down with it. That step appears in four CI jobs and both release lanes,
/// which is every workflow a scaffolded project has.
const _markedFiles = [
  '.github/workflows/ci.yml',
  '.github/workflows/release.yml',
  '.github/dependabot.yml',
];

/// Strips template-development scaffolding from a freshly scaffolded
/// [projectDir]: the submodule checkouts, the CLI-drift smoke jobs that only
/// make sense against the template's own checkout, and the Dependabot
/// git-submodule ecosystem.
///
/// Always runs — none of this depends on which pillars were kept.
///
/// Computes every rewrite in memory before writing any, so a malformed marker
/// throws with the tree untouched. Idempotent.
Future<void> stripTemplateOnly(String projectDir) async {
  final pending = <File, String>{};
  for (final relative in _markedFiles) {
    final file = File(p.join(projectDir, p.joinAll(relative.split('/'))));
    if (!file.existsSync()) continue;
    final original = file.readAsStringSync();
    final rewritten = removeTemplateOnlyRegions(original);
    if (rewritten == original) continue;
    pending[file] = '${rewritten.trimRight()}\n';
  }

  pending.forEach((file, content) => file.writeAsStringSync(content));
}
