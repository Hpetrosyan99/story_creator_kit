import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/src/core/session_files.dart';

/// `path_provider` falls back to its method channel in unit tests, so the
/// temporary directory is redirected there instead of through a platform
/// interface fake (which would need an undeclared dev dependency).
const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('session_files_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, (call) async {
          if (call.method == 'getTemporaryDirectory') {
            return tmp.path;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, null);
    if (tmp.existsSync()) {
      _makeWritable(tmp);
      tmp.deleteSync(recursive: true);
    }
  });

  Directory sessionsRoot() => Directory('${tmp.path}/story_creator_sessions');

  group('create', () {
    test('creates a unique directory under the sessions root', () async {
      final a = await SessionFiles.create();
      final b = await SessionFiles.create();

      expect(a.directory.existsSync(), isTrue);
      expect(b.directory.existsSync(), isTrue);
      expect(a.directory.parent.path, sessionsRoot().path);
      expect(a.directory.path, isNot(b.directory.path));
    });

    test('removes stale session directories and keeps fresh ones', () async {
      final root = sessionsRoot()..createSync(recursive: true);
      final stale = Directory('${root.path}/old_session')..createSync();
      File('${stale.path}/leftover.mp4').writeAsBytesSync(const [1, 2, 3]);
      final fresh = Directory('${root.path}/recent_session')..createSync();
      final strayFile = File('${root.path}/not_a_session.txt')
        ..writeAsStringSync('x');
      await _setModified(
        stale,
        DateTime.now().subtract(const Duration(days: 2)),
      );

      final session = await SessionFiles.create();

      expect(stale.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
      expect(strayFile.existsSync(), isTrue, reason: 'only directories swept');
      expect(session.directory.existsSync(), isTrue);
    });

    test('respects a custom staleAfter', () async {
      final root = sessionsRoot()..createSync(recursive: true);
      final hourOld = Directory('${root.path}/hour_old')..createSync();
      await _setModified(
        hourOld,
        DateTime.now().subtract(const Duration(hours: 1)),
      );

      await SessionFiles.create();
      expect(hourOld.existsSync(), isTrue, reason: 'default is 12 hours');

      await SessionFiles.create(staleAfter: const Duration(minutes: 30));
      expect(hourOld.existsSync(), isFalse);
    });
  });

  group('newPath', () {
    test('returns distinct paths inside the session with the extension', () {
      final session = SessionFiles.at(tmp);

      final paths = {for (var i = 0; i < 50; i++) session.newPath('png')};

      expect(paths, hasLength(50));
      for (final p in paths) {
        expect(p, startsWith('${tmp.path}/file_'));
        expect(p, endsWith('.png'));
      }
    });

    test('uses the prefix', () {
      final session = SessionFiles.at(tmp);

      expect(
        session.newPath('jpg', prefix: 'thumb'),
        startsWith('${tmp.path}/thumb_'),
      );
    });
  });

  group('adopt', () {
    late Directory sessionDir;
    late SessionFiles session;

    setUp(() {
      sessionDir = Directory('${tmp.path}/session')..createSync();
      session = SessionFiles.at(sessionDir);
    });

    test(
      'moves an outside file into the session, keeping the extension',
      () async {
        final source = File('${tmp.path}/IMG_0001.HEIC')
          ..writeAsBytesSync(const [7, 7, 7]);

        final adopted = await session.adopt(source.path);

        expect(adopted, startsWith('${sessionDir.path}/src_'));
        expect(adopted, endsWith('.heic'));
        expect(File(adopted).readAsBytesSync(), const [7, 7, 7]);
        expect(source.existsSync(), isFalse, reason: 'renamed, not copied');
      },
    );

    test('uses the given extension, or bin when the name has none', () async {
      final a = File('${tmp.path}/capture')..writeAsBytesSync(const [1]);
      final b = File('${tmp.path}/other')..writeAsBytesSync(const [2]);

      expect(await session.adopt(a.path), endsWith('.bin'));
      expect(await session.adopt(b.path, extension: 'mp4'), endsWith('.mp4'));
    });

    test('returns a path already inside the session unchanged', () async {
      final inside = File(session.newPath('jpg'))..writeAsBytesSync(const [1]);

      expect(await session.adopt(inside.path), inside.path);
      expect(inside.existsSync(), isTrue);
    });

    test(
      'copies when the file cannot be moved (read-only source folder)',
      () async {
        final readOnly = Directory('${tmp.path}/picker_cache')..createSync();
        final source = File('${readOnly.path}/picked.jpg')
          ..writeAsBytesSync(const [4, 5, 6]);
        await Process.run('chmod', ['555', readOnly.path]);
        addTearDown(() => Process.runSync('chmod', ['755', readOnly.path]));

        final adopted = await session.adopt(source.path);

        expect(adopted, startsWith(sessionDir.path));
        expect(File(adopted).readAsBytesSync(), const [4, 5, 6]);
        expect(source.existsSync(), isTrue, reason: 'the copy leaves it');
      },
      skip: Platform.isWindows ? 'needs POSIX permissions' : false,
    );

    test('moves a file from a sibling directory whose name starts with the '
        'session name', () async {
      final sibling = Directory('${sessionDir.path}_other')..createSync();
      final source = File('${sibling.path}/clip.mp4')
        ..writeAsBytesSync(const [9]);

      final adopted = await session.adopt(source.path);

      expect(adopted, startsWith('${sessionDir.path}/'));
    });
  });

  group('delete', () {
    test(
      'removes the directory and its contents; a second call is safe',
      () async {
        final session = await SessionFiles.create();
        File(session.newPath('txt')).writeAsStringSync('x');

        await session.delete();
        expect(session.directory.existsSync(), isFalse);

        await session.delete();
      },
    );
  });

  group('exportDirectory', () {
    test('defaults to story_creator_exports in the temp directory', () async {
      final dir = await SessionFiles.exportDirectory(null);

      expect(dir.path, '${tmp.path}/story_creator_exports');
      expect(dir.existsSync(), isTrue);
    });

    test('creates and returns a configured directory', () async {
      final configured = '${tmp.path}/custom/out';

      final dir = await SessionFiles.exportDirectory(configured);

      expect(dir.path, configured);
      expect(dir.existsSync(), isTrue);
    });

    test('is not removed by a session delete', () async {
      final session = await SessionFiles.create();
      final exports = await SessionFiles.exportDirectory(null);

      await session.delete();

      expect(exports.existsSync(), isTrue);
    });
  });
}

Future<void> _setModified(Directory dir, DateTime time) async {
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp =
      '${time.year}${two(time.month)}${two(time.day)}'
      '${two(time.hour)}${two(time.minute)}';
  final result = await Process.run('touch', ['-t', stamp, dir.path]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
}

void _makeWritable(Directory dir) {
  if (!Platform.isWindows) {
    Process.runSync('chmod', ['-R', 'u+w', dir.path]);
  }
}
