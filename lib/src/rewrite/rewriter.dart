import 'dart:io';

import 'package:path/path.dart' as p;

import '../project_config.dart';

const _templatePackage = 'flutter_starter_template';
const _templateBundleIdAndroid = 'com.lucistudio.flutter_starter_template';
const _templateBundleIdIos = 'com.luci-studio.flutterStarterTemplate';
const _templateDisplayName = 'Flutter Starter';
const _templateOrg = 'Luci Studio';

/// Top-level entry: rewrites all template identifiers in [projectDir].
Future<void> rewriteProject(String projectDir, ProjectConfig config) async {
  await _rewriteTextFiles(projectDir, config);
  await _moveMainActivityFile(projectDir, config);
}

/// Walks every text file under [dir] and substitutes template tokens.
Future<void> _rewriteTextFiles(String dir, ProjectConfig config) async {
  final root = Directory(dir);
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (_isBinaryExtension(entity.path)) continue;
    if (_isExcludedPath(entity.path)) continue;

    final String original;
    try {
      original = await entity.readAsString();
    } on FileSystemException {
      // Not UTF-8 text (e.g. a binary file with no recognised extension, such
      // as a stray .DS_Store). There is nothing to substitute — skip it.
      continue;
    }
    var patched = _applySubstitutions(original, config);
    if (p.extension(entity.path) == '.dart' &&
        patched.contains('package:${config.packageName}/')) {
      patched = sortDartImports(patched);
    }
    if (patched != original) {
      await entity.writeAsString(patched);
    }
  }
}

/// Sorts the leading Dart import section while preserving `fst:*` marker
/// regions as indivisible blocks.
///
/// Renaming `package:flutter_starter_template/...` can move a self-import to a
/// different alphabetical position (for example, `package:phase02_app/...`).
/// The template's imports are valid before the rename, but the generated file
/// would then fail `directives_ordering`. Marker blocks stay intact so later
/// auth/feature rewrites still remove exactly the imports they own.
String sortDartImports(String content) {
  final lines = content.split('\n');
  final importIndexes = <int>[
    for (var i = 0; i < lines.length; i++)
      if (_importUri(lines[i]) != null) i,
  ];
  if (importIndexes.length < 2) return content;

  var start = importIndexes.first;
  if (start > 0 && _isMarkerStart(lines[start - 1])) start--;
  var end = importIndexes.last;
  while (end + 1 < lines.length && !lines[end].trim().endsWith(';')) {
    end++;
  }
  if (end + 1 < lines.length && _isMarkerEnd(lines[end + 1])) end++;

  final blocks = <({List<String> lines, String uri, int index})>[];
  var index = start;
  while (index <= end) {
    final line = lines[index];
    if (line.trim().isEmpty) {
      index++;
      continue;
    }

    if (_isMarkerStart(line)) {
      final marker = RegExp(r'fst:[A-Za-z0-9:_-]+:start').firstMatch(line);
      if (marker == null) return content;
      final endNeedle = marker.group(0)!.replaceFirst(':start', ':end');
      final blockLines = <String>[];
      String? firstUri;
      var closed = false;
      while (index <= end) {
        final blockLine = lines[index++];
        blockLines.add(blockLine);
        firstUri ??= _importUri(blockLine);
        if (blockLine.contains(endNeedle)) {
          closed = true;
          break;
        }
      }
      if (!closed || firstUri == null) return content;
      blocks.add((lines: blockLines, uri: firstUri, index: blocks.length));
      continue;
    }

    final uri = _importUri(line);
    if (uri == null) return content;
    final importLines = <String>[line];
    while (index + 1 <= end && !importLines.last.trim().endsWith(';')) {
      index++;
      importLines.add(lines[index]);
    }
    blocks.add((lines: importLines, uri: uri, index: blocks.length));
    index++;
  }

  blocks.sort((a, b) {
    final category = _importCategory(a.uri).compareTo(_importCategory(b.uri));
    if (category != 0) return category;
    final uri = a.uri.compareTo(b.uri);
    return uri != 0 ? uri : a.index.compareTo(b.index);
  });

  final sorted = <String>[];
  int? previousCategory;
  for (final block in blocks) {
    final category = _importCategory(block.uri);
    if (previousCategory != null && previousCategory != category) {
      sorted.add('');
    }
    sorted.addAll(block.lines);
    previousCategory = category;
  }

  return [
    ...lines.take(start),
    ...sorted,
    ...lines.skip(end + 1),
  ].join('\n');
}

String? _importUri(String line) => RegExp(
      r'''^\s*import\s+['"]([^'"]+)['"]''',
    ).firstMatch(line)?.group(1);

bool _isMarkerStart(String line) =>
    RegExp(r'fst:[A-Za-z0-9:_-]+:start').hasMatch(line);

bool _isMarkerEnd(String line) =>
    RegExp(r'fst:[A-Za-z0-9:_-]+:end').hasMatch(line);

int _importCategory(String uri) {
  if (uri.startsWith('dart:')) return 0;
  if (uri.startsWith('package:')) return 1;
  return 2;
}

String _applySubstitutions(String src, ProjectConfig config) {
  // Order matters: longer / more-specific strings first to avoid
  // partial replacement collisions.
  return src
      // iOS bundle ID (camelCase form used in pbxproj)
      .replaceAll(_templateBundleIdIos, config.bundleId)
      // iOS RunnerTests suffix
      .replaceAll(
        '$_templateBundleIdIos.RunnerTests',
        '${config.bundleId}.RunnerTests',
      )
      // Android bundle ID
      .replaceAll(_templateBundleIdAndroid, config.bundleId)
      // Dart package name (import paths, pubspec name)
      .replaceAll(_templatePackage, config.packageName)
      // Display name variants
      .replaceAll('$_templateDisplayName (Dev)', '${config.displayName} (Dev)')
      .replaceAll(
        '$_templateDisplayName (Staging)',
        '${config.displayName} (Staging)',
      )
      .replaceAll(_templateDisplayName, config.displayName)
      // Org / author
      .replaceAll(_templateOrg, config.org);
}

/// Moves MainActivity.kt from the template package path to the new one.
Future<void> _moveMainActivityFile(
  String projectDir,
  ProjectConfig config,
) async {
  final oldRelative = p.joinAll([
    'android',
    'app',
    'src',
    'main',
    'kotlin',
    ..._templateBundleIdAndroid.split('.'),
    'MainActivity.kt',
  ]);
  final oldPath = p.join(projectDir, oldRelative);

  if (!File(oldPath).existsSync()) return;

  final newRelative = p.joinAll([
    'android',
    'app',
    'src',
    'main',
    'kotlin',
    ...config.bundleId.split('.'),
    'MainActivity.kt',
  ]);
  final newPath = p.join(projectDir, newRelative);

  await Directory(p.dirname(newPath)).create(recursive: true);
  await File(oldPath).copy(newPath);

  // Delete only the original file, then prune empty parent directories
  // up to (not including) the kotlin/ root — avoids clobbering segments
  // shared with the new bundle ID (e.g. both start with "com").
  await File(oldPath).delete();
  final kotlinRoot = p.join(
    projectDir,
    'android',
    'app',
    'src',
    'main',
    'kotlin',
  );
  var parent = Directory(p.dirname(oldPath));
  while (parent.path != kotlinRoot && parent.listSync().isEmpty) {
    final grandparent = parent.parent;
    await parent.delete();
    parent = grandparent;
  }
}

bool _isBinaryExtension(String path) {
  const binary = {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.ico',
    '.otf',
    '.ttf',
    '.woff',
    '.woff2',
    '.zip',
    '.jar',
    '.class',
    '.so',
    '.dylib',
    '.a',
    '.o',
  };
  return binary.contains(p.extension(path).toLowerCase());
}

bool _isExcludedPath(String path) {
  // Match directories only (surrounded by separators) so we don't accidentally
  // skip files like build.gradle.kts. `.git/` is excluded so the walk never
  // reads or rewrites git internals (a corruption risk, and tokens there are
  // never meaningful anyway).
  final p2 = path.replaceAll(r'\', '/');
  const skipDirs = [
    '/.git/',
    '/.dart_tool/',
    '/.fvm/',
    '/build/',
    '/.gradle/',
    '/Pods/',
  ];
  return skipDirs.any(p2.contains);
}
