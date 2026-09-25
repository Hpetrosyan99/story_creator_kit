import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../api/errors/story_exception.dart';
import '../api/music/music_models.dart';
import '../core/session_files.dart';

/// Default overall time limit of one music download.
const Duration kMusicDownloadTimeout = Duration(seconds: 30);

/// Creates the [HttpClient] used for one download.
typedef MusicHttpClientFactory = HttpClient Function();

/// Receives download progress in 0–1.
typedef MusicProgressCallback = void Function(double progress);

/// Thrown when a [MusicCancelToken] cancels a download or preparation.
class MusicCancelledException implements Exception {
  /// Creates the exception.
  const MusicCancelledException();

  @override
  String toString() => 'MusicCancelledException';
}

/// Cancels a running [MusicFileCache.localPath] call (and the preparation
/// around it) when the user leaves.
class MusicCancelToken {
  bool _cancelled = false;
  final List<VoidCallback> _listeners = [];

  /// Whether [cancel] was called.
  bool get isCancelled => _cancelled;

  /// Cancels the work; later calls do nothing.
  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    final listeners = List.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  /// Throws [MusicCancelledException] once cancelled.
  void throwIfCancelled() {
    if (_cancelled) {
      throw const MusicCancelledException();
    }
  }

  void _addListener(VoidCallback listener) => _listeners.add(listener);

  void _removeListener(VoidCallback listener) => _listeners.remove(listener);
}

/// Turns a [MusicSource] into a local file the exporter can read, caching the
/// result by track id for the rest of the story session.
///
/// * [MusicFileSource]: the path is used as-is.
/// * [MusicAssetSource]: the asset is copied from the asset bundle into the
///   session directory (`packages/<package>/<assetKey>` for package assets).
/// * [MusicUrlSource]: the file is downloaded into the session directory with
///   the source's headers, within [timeout]. Only 2xx responses are accepted;
///   a partial file is deleted on failure or cancellation.
///
/// Failures throw `StoryException(StoryErrorCode.musicUnavailable)`;
/// cancellation throws [MusicCancelledException].
class MusicFileCache {
  /// Creates a cache writing into [session].
  MusicFileCache(
    this.session, {
    this._bundle,
    MusicHttpClientFactory? httpClientFactory,
    this.timeout = kMusicDownloadTimeout,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  /// The cache shared by every music picker of [session].
  factory MusicFileCache.forSession(SessionFiles session) =>
      _bySession[session] ??= MusicFileCache(session);

  static final Expando<MusicFileCache> _bySession = Expando('MusicFileCache');

  /// Session directory the files are written into.
  final SessionFiles session;

  /// Overall time limit of one download.
  final Duration timeout;

  final AssetBundle? _bundle;
  final MusicHttpClientFactory _httpClientFactory;
  final Map<String, String> _paths = {};

  static const Set<String> _audioExtensions = {
    'aac',
    'caf',
    'flac',
    'm4a',
    'mp3',
    'mp4',
    'oga',
    'ogg',
    'opus',
    'wav',
  };

  /// The cached local file of the track with [trackId], if it still exists.
  String? cachedPath(String trackId) {
    final path = _paths[trackId];
    if (path == null) {
      return null;
    }
    if (File(path).existsSync()) {
      return path;
    }
    _paths.remove(trackId);
    return null;
  }

  /// A local file with the audio of [track], read from [source].
  ///
  /// [onProgress] receives 0–1 while downloading and 1 when done.
  Future<String> localPath(
    MusicTrack track,
    MusicSource source, {
    MusicProgressCallback? onProgress,
    MusicCancelToken? cancel,
  }) async {
    final cached = cachedPath(track.id);
    if (cached != null) {
      onProgress?.call(1);
      return cached;
    }
    cancel?.throwIfCancelled();
    final path = switch (source) {
      MusicFileSource(:final path) => path,
      MusicAssetSource() => await _copyAsset(source, cancel),
      MusicUrlSource() => await _download(source, onProgress, cancel),
    };
    _paths[track.id] = path;
    onProgress?.call(1);
    return path;
  }

  Future<String> _copyAsset(
    MusicAssetSource source,
    MusicCancelToken? cancel,
  ) async {
    final package = source.package;
    final key = package == null
        ? source.assetKey
        : 'packages/$package/${source.assetKey}';
    final ByteData data;
    try {
      data = await (_bundle ?? rootBundle).load(key);
    } on Object catch (e, s) {
      throw StoryException(
        StoryErrorCode.musicUnavailable,
        'Music asset "$key" could not be loaded.',
        e,
        s,
      );
    }
    cancel?.throwIfCancelled();
    final path = session.newPath(
      _extensionOf(source.assetKey),
      prefix: 'music',
    );
    try {
      await File(path).writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    } on Object catch (e, s) {
      await _deleteQuietly(path);
      throw StoryException(
        StoryErrorCode.musicUnavailable,
        'Music asset "$key" could not be copied.',
        e,
        s,
      );
    }
    if (cancel?.isCancelled ?? false) {
      await _deleteQuietly(path);
      throw const MusicCancelledException();
    }
    return path;
  }

  Future<String> _download(
    MusicUrlSource source,
    MusicProgressCallback? onProgress,
    MusicCancelToken? cancel,
  ) async {
    final client = _httpClientFactory()..connectionTimeout = timeout;
    final abort = Completer<Never>();
    abort.future.ignore();
    Object? abortReason;
    void abortWith(Object reason) {
      if (abort.isCompleted) {
        return;
      }
      abortReason = reason;
      abort.completeError(reason);
      client.close(force: true);
    }

    void onCancel() => abortWith(const MusicCancelledException());
    cancel?._addListener(onCancel);
    final timer = Timer(
      timeout,
      () => abortWith(TimeoutException('Music download timed out.', timeout)),
    );
    String? path;
    IOSink? sink;
    StreamSubscription<List<int>>? subscription;
    try {
      cancel?.throwIfCancelled();
      final request = await Future.any([
        client.getUrl(source.uri),
        abort.future,
      ]);
      source.headers.forEach(request.headers.set);
      final response = await Future.any([request.close(), abort.future]);
      final status = response.statusCode;
      if (status < 200 || status >= 300) {
        throw HttpException('Unexpected status $status.', uri: source.uri);
      }
      final target = session.newPath(
        _extensionFor(source.uri, response.headers.contentType),
        prefix: 'music',
      );
      path = target;
      final output = File(target).openWrite();
      sink = output;
      final total = response.contentLength;
      var received = 0;
      final done = Completer<void>();
      subscription = response.listen(
        (chunk) {
          output.add(chunk);
          received += chunk.length;
          if (total > 0) {
            onProgress?.call((received / total).clamp(0, 1));
          }
        },
        onError: done.completeError,
        onDone: done.complete,
        cancelOnError: true,
      );
      await Future.any([done.future, abort.future]);
      await output.flush();
      await output.close();
      sink = null;
      return target;
    } on Object catch (e, s) {
      await subscription?.cancel();
      subscription = null;
      try {
        await sink?.close();
      } on Object {
        // The file is deleted below; a failed close changes nothing.
      }
      if (path != null) {
        await _deleteQuietly(path);
      }
      final reason = abortReason ?? e;
      if (reason is MusicCancelledException) {
        throw const MusicCancelledException();
      }
      throw StoryException(
        StoryErrorCode.musicUnavailable,
        'Downloading music from ${source.uri.host} failed.',
        reason,
        s,
      );
    } finally {
      timer.cancel();
      cancel?._removeListener(onCancel);
      await subscription?.cancel();
      client.close(force: true);
    }
  }

  static String _extensionFor(Uri uri, ContentType? type) {
    final name = uri.path.split('/').last;
    final dot = name.lastIndexOf('.');
    final fromPath = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    if (_audioExtensions.contains(fromPath)) {
      return fromPath;
    }
    return switch (type?.mimeType) {
      'audio/mpeg' || 'audio/mp3' => 'mp3',
      'audio/wav' || 'audio/x-wav' || 'audio/wave' => 'wav',
      'audio/aac' || 'audio/aacp' => 'aac',
      'audio/ogg' => 'ogg',
      'audio/flac' => 'flac',
      _ => 'm4a',
    };
  }

  static String _extensionOf(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) {
      return 'm4a';
    }
    return name.substring(dot + 1).toLowerCase();
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) {
        await file.delete();
      }
    } on FileSystemException {
      // Best effort: the session directory is deleted with the session.
      return;
    }
  }
}
