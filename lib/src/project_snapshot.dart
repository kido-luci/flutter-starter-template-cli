import 'dart:io';

import 'package:path/path.dart' as p;

/// Byte-for-byte project snapshot used by destructive CLI transactions.
///
/// Build products and tool caches are intentionally excluded. Source files,
/// generated Dart files, lockfiles, and pre-existing user edits are retained.
final class ProjectSnapshot {
  ProjectSnapshot._(this.root, this.files, this.directories);

  factory ProjectSnapshot.capture(String root) {
    final files = <String, List<int>>{};
    final directories = <String>{''};
    for (final entity in _entities(root)) {
      final relative = p.relative(entity.path, from: root);
      if (entity is File) {
        files[relative] = entity.readAsBytesSync();
      } else if (entity is Directory) {
        directories.add(relative);
      }
    }
    return ProjectSnapshot._(root, files, directories);
  }

  final String root;
  final Map<String, List<int>> files;
  final Set<String> directories;

  void restore() {
    final current = _entities(root).toList();
    for (final entity in current.whereType<File>()) {
      final relative = p.relative(entity.path, from: root);
      if (!files.containsKey(relative)) entity.deleteSync();
    }
    for (final entry in files.entries) {
      final file = File(p.join(root, entry.key));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(entry.value, flush: true);
    }
    final currentDirectories = _entities(root).whereType<Directory>().toList()
      ..sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final directory in currentDirectories) {
      final relative = p.relative(directory.path, from: root);
      if (!directories.contains(relative) &&
          directory.existsSync() &&
          directory.listSync().isEmpty) {
        directory.deleteSync();
      }
    }
  }

  static Iterable<FileSystemEntity> _entities(String root) sync* {
    final pending = <Directory>[Directory(root)];
    while (pending.isNotEmpty) {
      final directory = pending.removeLast();
      for (final entity in directory.listSync(followLinks: false)) {
        final name = p.basename(entity.path);
        if (entity is Directory &&
            (name == '.git' || name == '.dart_tool' || name == 'build')) {
          continue;
        }
        yield entity;
        if (entity is Directory) pending.add(entity);
      }
    }
  }
}
