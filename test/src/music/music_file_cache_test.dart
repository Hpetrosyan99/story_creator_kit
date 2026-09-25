import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/src/api/errors/story_exception.dart';
import 'package:story_creator_kit/src/api/music/music_models.dart';
import 'package:story_creator_kit/src/core/session_files.dart';
import 'package:story_creator_kit/src/music/music_file_cache.dart';

class _MapAssetBundle extends CachingAssetBundle {
  _MapAssetBundle(this.assets);

  final Map<String, List<int>> assets;
  final List<String> requested = [];

  @override
  Future<ByteData> load(String key) async {
    requested.add(key);
    final bytes = assets[key];
    if (bytes == null) {
      throw FlutterError('Unable to load asset: $key');
    }
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

const _track = MusicTrack(
  id: 'song',
  title: 'Song',
  artist: 'Band',
  duration: Duration(minutes: 2),
);

void main() {
  late Directory tempDir;
  late SessionFiles session;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('music_cache_test');
    session = SessionFiles.at(tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  List<FileSystemEntity> sessionFiles() => tempDir.listSync();

  group('file source', () {
    test('uses the path as-is and caches it by track id', () async {
      final file = File('${tempDir.path}/local.m4a')..writeAsBytesSync([1]);
      final cache = MusicFileCache(session);
      final path = await cache.localPath(_track, MusicFileSource(file.path));
      expect(path, file.path);
      expect(cache.cachedPath('song'), file.path);
    });
  });

  group('asset source', () {
    test('copies an app asset into the session directory', () async {
      final bundle = _MapAssetBundle({
        'assets/music/song.mp3': [1, 2, 3],
      });
      final cache = MusicFileCache(session, bundle: bundle);
      final path = await cache.localPath(
        _track,
        const MusicAssetSource('assets/music/song.mp3'),
      );
      expect(path, startsWith(tempDir.path));
      expect(path, endsWith('.mp3'));
      expect(File(path).readAsBytesSync(), [1, 2, 3]);
    });

    test('reads package assets under packages/<package>/', () async {
      final bundle = _MapAssetBundle({
        'packages/tunes/audio/a.wav': [9],
      });
      final cache = MusicFileCache(session, bundle: bundle);
      final path = await cache.localPath(
        _track,
        const MusicAssetSource('audio/a.wav', package: 'tunes'),
      );
      expect(bundle.requested, ['packages/tunes/audio/a.wav']);
      expect(File(path).readAsBytesSync(), [9]);
    });

    test('a missing asset is musicUnavailable', () async {
      final cache = MusicFileCache(session, bundle: _MapAssetBundle({}));
      await expectLater(
        cache.localPath(_track, const MusicAssetSource('nope.mp3')),
        throwsA(
          isA<StoryException>().having(
            (e) => e.code,
            'code',
            StoryErrorCode.musicUnavailable,
          ),
        ),
      );
    });

    test('uses the root bundle by default', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            ..setMockMessageHandler('flutter/assets', (message) async {
              final key = const Utf8Codec().decode(
                message!.buffer.asUint8List(
                  message.offsetInBytes,
                  message.lengthInBytes,
                ),
              );
              if (key != 'assets/root.m4a') {
                return null;
              }
              return ByteData.sublistView(Uint8List.fromList([4, 5]));
            });
      addTearDown(
        () => messenger.setMockMessageHandler('flutter/assets', null),
      );
      final path = await MusicFileCache(session)
          .localPath(_track, const MusicAssetSource('assets/root.m4a'));
      expect(File(path).readAsBytesSync(), [4, 5]);
    });
  });

  group('url source', () {
    late HttpServer server;
    late List<HttpRequest> requests;
    late Completer<void> release;

    setUp(() async {
      // The Flutter test binding (initialised by the root bundle test) makes
      // every HttpClient answer 400; these tests talk to a real local server.
      HttpOverrides.global = null;
      requests = [];
      release = Completer<void>();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
        ..listen((request) async {
          requests.add(request);
          final response = request.response;
          try {
            switch (request.uri.path) {
              case '/song.mp3':
                final body = List.filled(10000, 7);
                response
                  ..contentLength = body.length
                  ..add(body.sublist(0, 5000));
                await response.flush();
                response.add(body.sublist(5000));
                await response.close();
              case '/audio':
                response.headers.contentType = ContentType('audio', 'mpeg');
                response.add([1, 2]);
                await response.close();
              case '/slow.m4a':
                response
                  ..contentLength = 100000
                  // Small writes stay buffered; 20 kB reaches the client.
                  ..add(List.filled(20000, 1));
                await response.flush();
                await release.future;
                await response.close();
              default:
                response.statusCode = HttpStatus.notFound;
                await response.close();
            }
          } on Object {
            // The client aborted the connection.
            return;
          }
        });
    });

    tearDown(() async {
      if (!release.isCompleted) {
        release.complete();
      }
      await server.close(force: true);
    });

    Uri url(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

    test(
      'downloads into the session directory with headers and progress',
      () async {
        final progress = <double>[];
        final cache = MusicFileCache(session);
        final path = await cache.localPath(
          _track,
          MusicUrlSource(
            url('/song.mp3'),
            headers: const {'Authorization': 'Bearer x'},
          ),
          onProgress: progress.add,
        );
        expect(path, startsWith(tempDir.path));
        expect(path, endsWith('.mp3'));
        expect(File(path).lengthSync(), 10000);
        expect(requests.single.headers.value('authorization'), 'Bearer x');
        expect(progress, isNotEmpty);
        expect(progress.last, 1);
        for (var i = 1; i < progress.length; i++) {
          expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
        }
      },
    );

    test('re-selecting the same track does not download again', () async {
      final cache = MusicFileCache(session);
      final source = MusicUrlSource(url('/song.mp3'));
      final first = await cache.localPath(_track, source);
      final second = await cache.localPath(_track, source);
      expect(second, first);
      expect(requests, hasLength(1));
    });

    test('the session cache is shared per session', () {
      expect(
        identical(
          MusicFileCache.forSession(session),
          MusicFileCache.forSession(session),
        ),
        isTrue,
      );
    });

    test('takes the extension from the content type', () async {
      final path = await MusicFileCache(session)
          .localPath(_track, MusicUrlSource(url('/audio')));
      expect(path, endsWith('.mp3'));
    });

    test('a non-2xx status is musicUnavailable and leaves no file', () async {
      await expectLater(
        MusicFileCache(session)
            .localPath(_track, MusicUrlSource(url('/missing'))),
        throwsA(
          isA<StoryException>()
              .having((e) => e.code, 'code', StoryErrorCode.musicUnavailable)
              .having((e) => e.cause, 'cause', isA<HttpException>()),
        ),
      );
      expect(sessionFiles(), isEmpty);
    });

    test('an unreachable host is musicUnavailable', () async {
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();
      await expectLater(
        MusicFileCache(session).localPath(
          _track,
          MusicUrlSource(Uri.parse('http://127.0.0.1:$port/x.mp3')),
        ),
        throwsA(
          isA<StoryException>().having(
            (e) => e.code,
            'code',
            StoryErrorCode.musicUnavailable,
          ),
        ),
      );
    });

    test('cancelling deletes the partial file', () async {
      final cancel = MusicCancelToken();
      final started = Completer<void>();
      final future = MusicFileCache(session).localPath(
        _track,
        MusicUrlSource(url('/slow.m4a')),
        cancel: cancel,
        onProgress: (value) {
          if (!started.isCompleted) {
            started.complete();
          }
        },
      );
      await started.future;
      expect(sessionFiles(), hasLength(1));
      cancel.cancel();
      await expectLater(future, throwsA(isA<MusicCancelledException>()));
      expect(sessionFiles(), isEmpty);
    });

    test('the overall timeout aborts and deletes the partial file', () async {
      await expectLater(
        MusicFileCache(
          session,
          timeout: const Duration(milliseconds: 300),
        ).localPath(_track, MusicUrlSource(url('/slow.m4a'))),
        throwsA(
          isA<StoryException>()
              .having((e) => e.code, 'code', StoryErrorCode.musicUnavailable)
              .having((e) => e.cause, 'cause', isA<TimeoutException>()),
        ),
      );
      expect(sessionFiles(), isEmpty);
    });

    test('uses the injected HttpClient factory', () async {
      var created = 0;
      final cache = MusicFileCache(
        session,
        httpClientFactory: () {
          created++;
          return HttpClient();
        },
      );
      await cache.localPath(_track, MusicUrlSource(url('/song.mp3')));
      expect(created, 1);
    });
  });
}
