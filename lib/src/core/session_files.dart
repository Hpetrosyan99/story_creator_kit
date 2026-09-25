import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';

/// Working directory of one story session.
///
/// Every intermediate file (captures, copies, overlays, thumbnails, cached
/// music) is created here and removed by [delete]. Only the exported result
/// is written elsewhere (see [exportDirectory]).
class SessionFiles {
  SessionFiles._(this.directory);

  /// Creates the session directory and removes leftovers of sessions older
  /// than [staleAfter] (e.g. after a crash).
  static Future<SessionFiles> create({
    Duration staleAfter = const Duration(hours: 12),
  }) async {
    final root = await _root();
    await _sweep(root, staleAfter);
    final id =
        '${DateTime.now().millisecondsSinceEpoch}_'
        '${math.Random().nextInt(1 << 32).toRadixString(16)}';
    final dir = Directory('${root.path}/$id');
    await dir.create(recursive: true);
    return SessionFiles._(dir);
  }

  /// Uses an existing directory (tests).
  factory SessionFiles.at(Directory directory) => SessionFiles._(directory);

  /// The session directory.
  final Directory directory;

  int _counter = 0;

  /// A new unique path inside the session with [extension] (no dot).
  String newPath(String extension, {String prefix = 'file'}) {
    _counter++;
    return '${directory.path}/${prefix}_${_counter}_'
        '${DateTime.now().microsecondsSinceEpoch}.$extension';
  }

  /// Moves [path] into the session directory unless it is already inside.
  Future<String> adopt(String path, {String? extension}) async {
    if (path.startsWith('${directory.path}/')) {
      return path;
    }
    final ext = extension ?? _extensionOf(path);
    final target = newPath(ext, prefix: 'src');
    try {
      await File(path).rename(target);
    } on FileSystemException {
      await File(path).copy(target);
    }
    return target;
  }

  /// Deletes the session directory and everything in it.
  Future<void> delete() async {
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }

  /// Directory for exported results; not deleted with the session.
  static Future<Directory> exportDirectory(String? configured) async {
    final dir = configured != null
        ? Directory(configured)
        : Directory(
            '${(await getTemporaryDirectory()).path}/story_creator_exports',
          );
    await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> _root() async {
    final tmp = await getTemporaryDirectory();
    return Directory('${tmp.path}/story_creator_sessions');
  }

  static Future<void> _sweep(Directory root, Duration staleAfter) async {
    if (!root.existsSync()) {
      return;
    }
    final cutoff = DateTime.now().subtract(staleAfter);
    await for (final entity in root.list()) {
      if (entity is! Directory) {
        continue;
      }
      try {
        if (entity.statSync().modified.isBefore(cutoff)) {
          await entity.delete(recursive: true);
        }
      } on FileSystemException {
        // Another isolate may be deleting it; skip.
        continue;
      }
    }
  }

  static String _extensionOf(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? 'bin' : name.substring(dot + 1).toLowerCase();
  }
}
