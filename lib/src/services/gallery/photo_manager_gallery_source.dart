import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart' as pm;
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../api/errors/story_exception.dart';
import '../../api/result/story_result.dart';
import 'gallery_source.dart';
import 'system_picker_gallery_source.dart';

/// [GallerySource] with an in-app grid backed by `photo_manager`.
///
/// * Access: `requestPermissionExtend` understands iOS limited access and
///   Android 14 partial access (`READ_MEDIA_VISUAL_USER_SELECTED`); limited
///   selections are changed with `presentLimited`.
/// * Files: never loaded into memory. On iOS the current rendition (with
///   the user's edits) is exported by Photos, downloading from iCloud with
///   progress when needed; starting a new [resolve] cancels the previous
///   download. On Android the original file is used as is (HEIC stays HEIC;
///   Flutter decodes it from API 28).
/// * [pickWithSystemPicker] delegates to [SystemPickerGallerySource] so the
///   grid can offer a permission-free fallback.
/// * [dispose] clears photo_manager's file cache.
class PhotoManagerGallerySource implements GallerySource {
  /// Creates the source.
  PhotoManagerGallerySource();

  final SystemPickerGallerySource _systemPicker = SystemPickerGallerySource();
  final Map<String, pm.AssetPathEntity> _paths = {};
  final Map<String, pm.AssetEntity> _entities = {};
  pm.RequestType _type = pm.RequestType.common;
  pm.PMCancelToken? _pending;
  int _androidDeniedRequests = 0;
  bool _listening = false;

  // A subscriber exists but the native observer is not registered yet:
  // registering a PHPhotoLibrary change observer before the user decided on
  // access shows the iOS permission prompt, so it waits for access.
  bool _wantsListening = false;

  StreamController<void>? _changeController;

  // Recreated after [dispose] so a host that reuses its services across
  // sessions keeps working.
  StreamController<void> get _changes {
    final existing = _changeController;
    if (existing != null && !existing.isClosed) {
      return existing;
    }
    return _changeController = StreamController<void>.broadcast(
      onListen: _startListening,
      onCancel: _stopListening,
    );
  }

  bool get _isDarwin =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  pm.PermissionRequestOption get _option => pm.PermissionRequestOption(
    androidPermission: pm.AndroidPermission(type: _type, mediaLocation: false),
  );

  @override
  bool get supportsGrid => true;

  @override
  Future<GalleryAccess> checkAccess() async {
    final pm.PermissionState state;
    try {
      state = await pm.PhotoManager.getPermissionState(requestOption: _option);
    } on PlatformException catch (e, s) {
      throw _permissionError(e, s);
    }
    await _listenIfAllowed(state);
    return _map(state);
  }

  @override
  Future<GalleryAccess> requestAccess() async {
    final pm.PermissionState state;
    try {
      state = await pm.PhotoManager.requestPermissionExtend(
        requestOption: _option,
      );
    } on PlatformException catch (e, s) {
      throw _permissionError(e, s);
    }
    if (!_isDarwin && state == pm.PermissionState.denied) {
      // Android shows the dialog at most twice; afterwards requests return
      // "denied" without a prompt and only the settings app helps.
      _androidDeniedRequests++;
    } else if (state.hasAccess) {
      _androidDeniedRequests = 0;
    }
    await _listenIfAllowed(state);
    return _map(state);
  }

  GalleryAccess _map(pm.PermissionState state) => switch (state) {
    pm.PermissionState.authorized => GalleryAccess.granted,
    pm.PermissionState.limited => GalleryAccess.limited,
    pm.PermissionState.notDetermined => GalleryAccess.denied,
    pm.PermissionState.restricted => GalleryAccess.permanentlyDenied,
    pm.PermissionState.denied =>
      _isDarwin || _androidDeniedRequests >= 2
          ? GalleryAccess.permanentlyDenied
          : GalleryAccess.denied,
  };

  @override
  Future<void> manageLimitedSelection() async {
    try {
      await pm.PhotoManager.presentLimited(type: _type);
    } on PlatformException catch (e, s) {
      throw _permissionError(e, s);
    }
    // iOS 14 completes immediately and Android does not always notify;
    // make listeners refresh either way.
    _changeController?.add(null);
  }

  @override
  Future<List<GalleryAlbum>> albums({
    required bool photos,
    required bool videos,
  }) async {
    _type = photos && videos
        ? pm.RequestType.common
        : videos
        ? pm.RequestType.video
        : pm.RequestType.image;
    final filter = pm.FilterOptionGroup(
      imageOption: const pm.FilterOption(
        sizeConstraint: pm.SizeConstraint(ignoreSize: true),
      ),
      videoOption: const pm.FilterOption(
        sizeConstraint: pm.SizeConstraint(ignoreSize: true),
      ),
      orders: const [pm.OrderOption()],
    );
    try {
      final paths = await pm.PhotoManager.getAssetPathList(
        type: _type,
        filterOption: filter,
      );
      _paths.clear();
      final result = <GalleryAlbum>[];
      for (final path in paths) {
        final count = await path.assetCountAsync;
        if (count == 0 && !path.isAll) {
          continue;
        }
        _paths[path.id] = path;
        result.add(
          GalleryAlbum(
            id: path.id,
            name: path.name,
            count: count,
            isAll: path.isAll,
          ),
        );
      }
      result.sort((a, b) => (b.isAll ? 1 : 0) - (a.isAll ? 1 : 0));
      return result;
    } on PlatformException catch (e, s) {
      throw StoryException(
        StoryErrorCode.mediaUnavailable,
        'Listing albums failed.',
        e,
        s,
      );
    }
  }

  @override
  Future<List<GalleryAsset>> assets(
    GalleryAlbum album, {
    required int page,
    int pageSize = 60,
  }) async {
    final path = _paths[album.id];
    if (path == null) {
      throw StoryException(
        StoryErrorCode.mediaUnavailable,
        'Unknown album ${album.id}; call albums() first.',
      );
    }
    final List<pm.AssetEntity> entities;
    try {
      entities = await path.getAssetListPaged(page: page, size: pageSize);
    } on PlatformException catch (e, s) {
      throw StoryException(
        StoryErrorCode.mediaUnavailable,
        'Listing assets failed.',
        e,
        s,
      );
    }
    final result = <GalleryAsset>[];
    for (final entity in entities) {
      final type = switch (entity.type) {
        pm.AssetType.image => StoryMediaType.photo,
        pm.AssetType.video => StoryMediaType.video,
        pm.AssetType.audio || pm.AssetType.other => null,
      };
      if (type == null) {
        continue;
      }
      _entities[entity.id] = entity;
      result.add(
        GalleryAsset(
          id: entity.id,
          type: type,
          width: entity.orientatedWidth,
          height: entity.orientatedHeight,
          duration: type == StoryMediaType.video ? entity.videoDuration : null,
        ),
      );
    }
    return result;
  }

  @override
  ImageProvider thumbnail(GalleryAsset asset, {int size = 256}) =>
      AssetEntityImageProvider(
        _entityFor(asset),
        isOriginal: false,
        thumbnailSize: pm.ThumbnailSize.square(size),
      );

  pm.AssetEntity _entityFor(GalleryAsset asset) =>
      _entities[asset.id] ??
      pm.AssetEntity(
        id: asset.id,
        typeInt: asset.type == StoryMediaType.photo
            ? pm.AssetType.image.index
            : pm.AssetType.video.index,
        width: asset.width,
        height: asset.height,
        duration: asset.duration?.inSeconds ?? 0,
      );

  @override
  Future<PickedMedia> resolve(
    GalleryAsset asset, {
    void Function(double progress)? onProgress,
  }) async {
    final previous = _pending;
    if (previous != null) {
      await _cancel(previous);
    }
    final token = pm.PMCancelToken(debugLabel: asset.id);
    _pending = token;
    final entity = _entityFor(asset);
    StreamSubscription<pm.PMProgressState>? progress;
    try {
      // iOS: the current rendition includes the user's edits (crop,
      // filters) and is what Photos shows. Android: the original file.
      final isOrigin = !_isDarwin;
      pm.PMProgressHandler? handler;
      if (_isDarwin && !await entity.isLocallyAvailable(isOrigin: isOrigin)) {
        handler = pm.PMProgressHandler();
        progress = handler.stream.listen(
          (state) => onProgress?.call(state.progress.clamp(0.0, 1.0)),
        );
      }
      final file = await entity.loadFile(
        isOrigin: isOrigin,
        progressHandler: handler,
        cancelToken: token,
      );
      if (file == null) {
        throw StoryException(
          StoryErrorCode.mediaUnavailable,
          identical(_pending, token)
              ? 'The asset has no local file (download failed).'
              : 'The download was cancelled.',
        );
      }
      onProgress?.call(1);
      String? mimeType;
      try {
        mimeType = await entity.mimeTypeAsync;
      } on PlatformException {
        // Optional; the importer derives it from the extension.
        mimeType = null;
      }
      return PickedMedia(path: file.path, type: asset.type, mimeType: mimeType);
    } on PlatformException catch (e, s) {
      throw StoryException(
        StoryErrorCode.mediaUnavailable,
        'Loading the asset failed.',
        e,
        s,
      );
    } finally {
      await progress?.cancel();
      if (identical(_pending, token)) {
        _pending = null;
      }
    }
  }

  @override
  Future<PickedMedia?> pickWithSystemPicker({
    required bool photos,
    required bool videos,
  }) => _systemPicker.pickWithSystemPicker(photos: photos, videos: videos);

  @override
  Stream<void> get changes => _changes.stream;

  void _onChange(MethodCall call) => _changeController?.add(null);

  Future<void> _startListening() async {
    _wantsListening = true;
    final pm.PermissionState state;
    try {
      state = await pm.PhotoManager.getPermissionState(requestOption: _option);
    } on PlatformException {
      return;
    }
    await _listenIfAllowed(state);
  }

  Future<void> _listenIfAllowed(pm.PermissionState state) async {
    if (_listening || !_wantsListening || !state.hasAccess) {
      return;
    }
    _listening = true;
    pm.PhotoManager.addChangeCallback(_onChange);
    try {
      await pm.PhotoManager.startChangeNotify();
    } on PlatformException {
      // Without notifications the grid refreshes when reopened.
      _listening = false;
      pm.PhotoManager.removeChangeCallback(_onChange);
    }
  }

  Future<void> _stopListening() async {
    _wantsListening = false;
    if (!_listening) {
      return;
    }
    _listening = false;
    pm.PhotoManager.removeChangeCallback(_onChange);
    try {
      await pm.PhotoManager.stopChangeNotify();
    } on PlatformException {
      // Already stopped natively.
      return;
    }
  }

  static Future<void> _cancel(pm.PMCancelToken token) async {
    try {
      await token.cancelRequest();
    } on PlatformException {
      // The request already finished.
      return;
    }
  }

  static StoryException _permissionError(PlatformException e, StackTrace s) =>
      StoryException(
        StoryErrorCode.photosPermissionDenied,
        'Photo library permission call failed.',
        e,
        s,
      );

  @override
  Future<void> dispose() async {
    final pending = _pending;
    _pending = null;
    if (pending != null) {
      await _cancel(pending);
    }
    await _stopListening();
    final changes = _changeController;
    _changeController = null;
    await changes?.close();
    _paths.clear();
    _entities.clear();
    try {
      await pm.PhotoManager.clearFileCache();
    } on PlatformException {
      // The cache lives in the app's temp/cache directory, which the OS
      // purges; a failed clear only delays that.
      return;
    }
  }
}
