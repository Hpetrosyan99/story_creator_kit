import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../api/errors/story_exception.dart';
import '../api/result/story_result.dart';
import '../camera/widgets/notice_toast.dart';
import '../camera/widgets/permission_prompt.dart';
import '../camera/widgets/round_icon_button.dart';
import '../core/story_scope.dart';
import '../services/gallery/gallery_source.dart';
import 'gallery_keys.dart';
import 'widgets/album_selector.dart';
import 'widgets/asset_tile.dart';
import 'widgets/camera_tile.dart';
import 'widgets/limited_access_banner.dart';

/// Full-screen gallery over the camera: "Recent ›" album selector, a
/// 3-column grid with a camera tile first, video duration badges, a
/// limited-access banner and a permission prompt with a system-picker
/// fallback. Tapping an item resolves it to a local file and closes the
/// sheet with it.
class GallerySheet extends StatefulWidget {
  /// Creates the sheet. Use [open] to show it.
  const GallerySheet({super.key});

  /// Items loaded per page (the `GallerySource.assets` default).
  static const int pageSize = 60;

  /// Pushes the sheet and completes with the picked item, or `null` when
  /// the user went back to the camera.
  ///
  /// The route re-provides the [StoryScope] and the inherited themes of
  /// [context], because routes are built outside the creator's subtree.
  static Future<PickedMedia?> open(BuildContext context) {
    final scope = StoryScope.read(context);
    final animate = !MediaQuery.disableAnimationsOf(context);
    final sheet = InheritedTheme.captureAll(
      context,
      StoryScope(
        config: scope.config,
        services: scope.services,
        session: scope.session,
        resources: scope.resources,
        child: const GallerySheet(),
      ),
    );
    return Navigator.of(context).push<PickedMedia>(
      PageRouteBuilder<PickedMedia>(
        transitionDuration: animate
            ? const Duration(milliseconds: 260)
            : Duration.zero,
        reverseTransitionDuration: animate
            ? const Duration(milliseconds: 200)
            : Duration.zero,
        pageBuilder: (context, _, _) => sheet,
        transitionsBuilder: (context, animation, _, child) => SlideTransition(
          position: Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation),
          child: child,
        ),
      ),
    );
  }

  @override
  State<GallerySheet> createState() => _GallerySheetState();
}

class _GallerySheetState extends State<GallerySheet>
    with WidgetsBindingObserver {
  late final GallerySource _source;
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<double> _progress = ValueNotifier(0);
  StreamSubscription<void>? _changes;
  Timer? _noticeTimer;

  GalleryAccess? _access;
  bool _requested = false;
  List<GalleryAlbum> _albums = const [];
  GalleryAlbum? _album;
  final List<GalleryAsset> _assets = [];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _failed = false;
  bool _albumsOpen = false;
  int _loadGeneration = 0;
  String? _resolvingId;
  int _resolveToken = 0;
  String? _notice;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    _source = StoryScope.of(context).services.gallery;
    _changes = _source.changes.listen((_) => unawaited(_reload()));
    unawaited(_checkAccess(requestIfNeeded: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may come back from the settings app or the limited picker.
    if (state == AppLifecycleState.resumed && _access != null) {
      unawaited(_checkAccess(requestIfNeeded: false));
    }
  }

  bool get _hasAccess =>
      _access == GalleryAccess.granted || _access == GalleryAccess.limited;

  Future<void> _checkAccess({required bool requestIfNeeded}) async {
    final before = _access;
    GalleryAccess access;
    try {
      access = await _source.checkAccess();
      if (access == GalleryAccess.denied && requestIfNeeded && !_requested) {
        _requested = true;
        access = await _source.requestAccess();
      }
    } on StoryException catch (e) {
      _report(e);
      access = GalleryAccess.denied;
    }
    if (!mounted) {
      return;
    }
    setState(() => _access = access);
    final hadAccess =
        before == GalleryAccess.granted || before == GalleryAccess.limited;
    if (_hasAccess && (!hadAccess || before != access)) {
      await _reload();
    }
  }

  Future<void> _request() async {
    GalleryAccess access;
    try {
      access = await _source.requestAccess();
    } on StoryException catch (e) {
      _report(e);
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _access = access);
    if (_hasAccess) {
      await _reload();
    }
  }

  Future<void> _openSettings() async {
    try {
      await StoryScope.read(context).services.permissions.openSettings();
    } on StoryException catch (e) {
      _report(e);
    }
  }

  Future<void> _manage() async {
    try {
      await _source.manageLimitedSelection();
    } on StoryException catch (e) {
      _report(e);
      return;
    }
    await _checkAccess(requestIfNeeded: false);
    await _reload();
  }

  Future<void> _systemPick() async {
    final constraints = StoryScope.read(context).config.constraints;
    final PickedMedia? picked;
    try {
      picked = await _source.pickWithSystemPicker(
        photos: constraints.allowPhotos,
        videos: constraints.allowVideos,
      );
    } on StoryException catch (e) {
      _report(e);
      _showNotice(StoryScope.read(context).strings.camera.mediaUnavailable);
      return;
    }
    if (picked != null && mounted) {
      Navigator.of(context).pop(picked);
    }
  }

  /// Reloads albums (keeping the shown album when it still exists) and the
  /// first page.
  Future<void> _reload() async {
    if (!_hasAccess) {
      return;
    }
    final generation = ++_loadGeneration;
    final constraints = StoryScope.read(context).config.constraints;
    List<GalleryAlbum> albums;
    try {
      albums = await _source.albums(
        photos: constraints.allowPhotos,
        videos: constraints.allowVideos,
      );
    } on StoryException catch (e) {
      if (mounted && generation == _loadGeneration) {
        _report(e);
        setState(() => _failed = true);
      }
      return;
    }
    if (!mounted || generation != _loadGeneration) {
      return;
    }
    final previous = _album;
    GalleryAlbum? album;
    for (final a in albums) {
      if (a.id == previous?.id) {
        album = a;
      }
    }
    album ??= albums.isEmpty
        ? null
        : albums.firstWhere((a) => a.isAll, orElse: () => albums.first);
    setState(() {
      _albums = albums;
      _album = album;
      _assets.clear();
      _page = 0;
      _hasMore = album != null;
      _loading = false;
      _failed = false;
    });
    await _loadMore();
  }

  Future<void> _selectAlbum(GalleryAlbum album) async {
    setState(() {
      _albumsOpen = false;
      _album = album;
      _assets.clear();
      _page = 0;
      _hasMore = true;
      _loading = false;
      _failed = false;
    });
    _loadGeneration++;
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }
    await _loadMore();
  }

  Future<void> _loadMore() async {
    final album = _album;
    if (album == null || _loading || !_hasMore) {
      return;
    }
    final generation = _loadGeneration;
    setState(() => _loading = true);
    List<GalleryAsset> page;
    try {
      page = await _source.assets(album, page: _page);
    } on StoryException catch (e) {
      if (mounted && generation == _loadGeneration) {
        _report(e);
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
      return;
    }
    if (!mounted || generation != _loadGeneration) {
      return;
    }
    final constraints = StoryScope.read(context).config.constraints;
    setState(() {
      _assets.addAll(
        page.where(
          (a) => a.type == StoryMediaType.photo
              ? constraints.allowPhotos
              : constraints.allowVideos,
        ),
      );
      _page++;
      _hasMore = page.length >= GallerySheet.pageSize;
      _loading = false;
    });
    // Fill the viewport when the first page is short of it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  void _onScroll() {
    if (!mounted || !_scroll.hasClients) {
      return;
    }
    if (_scroll.position.extentAfter < 900) {
      unawaited(_loadMore());
    }
  }

  Future<void> _onAssetTap(GalleryAsset asset) async {
    if (_resolvingId == asset.id) {
      // Second tap cancels; the source cancels the download when the next
      // item is resolved, and a late result is ignored.
      setState(() {
        _resolveToken++;
        _resolvingId = null;
      });
      return;
    }
    final scope = StoryScope.read(context);
    final min = scope.config.constraints.minVideoDuration;
    final duration = asset.duration;
    if (asset.type == StoryMediaType.video &&
        duration != null &&
        duration < min) {
      _showNotice(scope.strings.camera.videoTooShort);
      return;
    }
    final token = ++_resolveToken;
    _progress.value = 0;
    setState(() => _resolvingId = asset.id);
    try {
      final picked = await _source.resolve(
        asset,
        onProgress: (value) {
          if (token == _resolveToken) {
            _progress.value = value;
          }
        },
      );
      if (!mounted || token != _resolveToken) {
        return;
      }
      Navigator.of(context).pop(picked);
    } on StoryException catch (e) {
      if (!mounted || token != _resolveToken) {
        return;
      }
      _report(e);
      _showNotice(scope.strings.camera.mediaUnavailable);
      setState(() => _resolvingId = null);
    }
  }

  void _showNotice(String message) {
    if (!mounted) {
      return;
    }
    _noticeTimer?.cancel();
    setState(() => _notice = message);
    _noticeTimer = Timer(const Duration(milliseconds: 2800), () {
      if (mounted) {
        setState(() => _notice = null);
      }
    });
  }

  void _report(StoryException e) {
    if (mounted) {
      StoryScope.read(context).reportError(e);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_changes?.cancel());
    _noticeTimer?.cancel();
    _scroll.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final strings = scope.strings;
    final album = _album;
    final notice = _notice;
    return ColoredBox(
      key: GalleryKeys.sheet,
      color: theme.background,
      child: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
                  child: Row(
                    children: [
                      RoundIconButton(
                        key: GalleryKeys.back,
                        icon: Icons.arrow_back_rounded,
                        label: strings.common.back,
                        background: false,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: AlbumSelector(
                          name: album == null
                              ? strings.camera.recent
                              : galleryAlbumName(context, album),
                          open: _albumsOpen,
                          onPressed: _hasAccess && _albums.length > 1
                              ? () => setState(() => _albumsOpen = !_albumsOpen)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_access == GalleryAccess.limited)
                  LimitedAccessBanner(onManage: _manage),
                Expanded(
                  child: _SheetBody(
                    access: _access,
                    albumsOpen: _albumsOpen,
                    albums: _albums,
                    album: _album,
                    failed: _failed && _assets.isEmpty,
                    grid: _AssetGrid(
                      assets: _assets,
                      scroll: _scroll,
                      source: _source,
                      resolvingId: _resolvingId,
                      progress: _progress,
                      showEmpty: !_loading && !_hasMore && _assets.isEmpty,
                      onCamera: () => Navigator.of(context).pop(),
                      onAsset: _onAssetTap,
                    ),
                    onRequest: _request,
                    onOpenSettings: _openSettings,
                    onSystemPick: _systemPick,
                    onSelectAlbum: _selectAlbum,
                    onRetry: _reload,
                  ),
                ),
              ],
            ),
            if (notice != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: Center(
                  child: NoticeToast(key: GalleryKeys.notice, message: notice),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Picks the body for the sheet's state: loading, permission prompt,
/// album list, load error or the grid.
class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.access,
    required this.albumsOpen,
    required this.albums,
    required this.album,
    required this.failed,
    required this.grid,
    required this.onRequest,
    required this.onOpenSettings,
    required this.onSystemPick,
    required this.onSelectAlbum,
    required this.onRetry,
  });

  final GalleryAccess? access;
  final bool albumsOpen;
  final List<GalleryAlbum> albums;
  final GalleryAlbum? album;
  final bool failed;
  final Widget grid;
  final VoidCallback onRequest;
  final VoidCallback onOpenSettings;
  final VoidCallback onSystemPick;
  final ValueChanged<GalleryAlbum> onSelectAlbum;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = StoryScope.of(context).strings;
    final access = this.access;
    if (access == null) {
      return const _Loading();
    }
    if (access == GalleryAccess.denied ||
        access == GalleryAccess.permanentlyDenied) {
      final blocked = access == GalleryAccess.permanentlyDenied;
      return PermissionPrompt(
        key: GalleryKeys.permissionPrompt,
        icon: Icons.photo_library_outlined,
        title: strings.camera.photosPermissionTitle,
        message: blocked
            ? strings.camera.photosPermissionBlockedMessage
            : strings.camera.photosPermissionMessage,
        actionLabel: blocked
            ? strings.common.openSettings
            : strings.camera.allowAccess,
        onAction: blocked ? onOpenSettings : onRequest,
        secondaryLabel: strings.camera.useSystemPicker,
        onSecondary: onSystemPick,
      );
    }
    if (albumsOpen) {
      return AlbumList(
        albums: albums,
        selected: album,
        onSelected: onSelectAlbum,
      );
    }
    if (failed) {
      return _LoadFailed(onRetry: onRetry);
    }
    return grid;
  }
}

class _AssetGrid extends StatelessWidget {
  const _AssetGrid({
    required this.assets,
    required this.scroll,
    required this.source,
    required this.resolvingId,
    required this.progress,
    required this.showEmpty,
    required this.onCamera,
    required this.onAsset,
  });

  final List<GalleryAsset> assets;
  final ScrollController scroll;
  final GallerySource source;
  final String? resolvingId;
  final ValueNotifier<double> progress;
  final bool showEmpty;
  final VoidCallback onCamera;
  final ValueChanged<GalleryAsset> onAsset;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    final width = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final thumbSize = (width / 3 * dpr).round().clamp(128, 512);
    return Stack(
      children: [
        GridView.builder(
          key: GalleryKeys.grid,
          controller: scroll,
          padding: EdgeInsets.zero,
          scrollCacheExtent: const ScrollCacheExtent.pixels(400),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
            childAspectRatio: 3 / 4,
          ),
          itemCount: assets.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return CameraTile(onPressed: onCamera);
            }
            final asset = assets[index - 1];
            return AssetTile(
              asset: asset,
              image: source.thumbnail(asset, size: thumbSize),
              progress: asset.id == resolvingId ? progress : null,
              onPressed: () => onAsset(asset),
            );
          },
        ),
        if (showEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                scope.strings.camera.galleryEmpty,
                textAlign: TextAlign.center,
                style: theme.bodyStyle.copyWith(color: theme.onSurfaceMuted),
              ),
            ),
          ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final theme = StoryScope.of(context).theme;
    return Center(
      child: SizedBox.square(
        dimension: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: theme.onSurfaceMuted,
        ),
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scope = StoryScope.of(context);
    final theme = scope.theme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              scope.strings.camera.galleryLoadFailed,
              textAlign: TextAlign.center,
              style: theme.bodyStyle,
            ),
            const SizedBox(height: 16),
            StoryActionButton(
              label: scope.strings.common.retry,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
