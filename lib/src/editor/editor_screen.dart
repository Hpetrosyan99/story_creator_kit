import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/assets/story_filter.dart';
import '../api/assets/story_sticker.dart';
import '../api/config/capture_options.dart';
import '../api/errors/story_exception.dart';
import '../api/events/story_event.dart';
import '../camera/widgets/gallery_shortcut.dart';
import '../core/media_import.dart';
import '../core/story_canvas.dart';
import '../core/story_scope.dart';
import '../gallery/gallery_sheet.dart';
import '../model/drawing_stroke.dart';
import '../model/media_placement.dart';
import '../model/story_document.dart';
import '../model/story_media.dart';
import '../model/story_overlay.dart';
import '../model/trim_range.dart';
import '../music/music_picker.dart';
import '../render/painters/story_paint_resources_loader.dart';
import '../services/gallery/gallery_source.dart';
import '../ui/story_icon.dart';
import '../ui/story_nav_button.dart';
import '../ui/story_stage.dart';
import 'accessibility/overlay_actions.dart';
import 'accessibility/overlay_adjust_panel.dart';
import 'audio/audio_mix_panel.dart';
import 'canvas/canvas_interaction.dart';
import 'canvas/media_palette.dart';
import 'canvas/overlay_semantics.dart';
import 'canvas/story_canvas_view.dart';
import 'drawing/drawing_brush.dart';
import 'drawing/drawing_toolbar.dart';
import 'editor_controller.dart';
import 'editor_keys.dart';
import 'filters/filter_strip.dart';
import 'stickers/sticker_picker_panel.dart';
import 'text/text_edit_overlay.dart';
import 'video/editor_playback.dart';
import 'video/trim_bar.dart';
import 'video/video_thumbnails.dart';
import 'widgets/discard_dialog.dart';
import 'widgets/editor_icon_button.dart';
import 'widgets/editor_panel.dart';
import 'widgets/editor_tool_column.dart';
import 'widgets/music_chip.dart';

/// The editor. Stays mounted underneath export and preview, so its state and
/// undo history survive a return from preview.
class EditorScreen extends StatefulWidget {
  /// Creates the editor.
  const EditorScreen({
    required this.initialDocument,
    required this.onExport,
    required this.onBack,
    this.active = true,
    super.key,
  });

  /// The document to start from (media placed, no edits).
  final StoryDocument initialDocument;

  /// Called with the current document when the user confirms.
  final ValueChanged<StoryDocument> onExport;

  /// Called when the user leaves the editor (after confirming discard).
  final VoidCallback onBack;

  /// `false` while export/preview cover the editor: pause playback and
  /// ignore input.
  final bool active;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _TextEditing {
  const _TextEditing({
    required this.overlayId,
    required this.text,
    required this.style,
  });

  final String? overlayId;
  final String text;
  final TextOverlayStyle style;
}

class _EditorScreenState extends State<EditorScreen>
    with WidgetsBindingObserver {
  late final StoryScope _scope;
  late final EditorController _controller;
  late DrawingBrush _brush;
  final CanvasInteraction _interaction = CanvasInteraction();
  final ValueNotifier<String?> _notice = ValueNotifier(null);
  EditorPlayback? _playback;
  late VideoThumbnails _thumbnails;
  StoryMedia? _media;
  Timer? _noticeTimer;
  _TextEditing? _editing;
  TextOverlayStyle? _lastTextStyle;
  ImageProvider? _preview;
  double _lastOriginalVolume = 1;
  int _resourcesRevision = 0;
  bool _initialized = false;
  bool _appVisible = true;
  bool _moreTools = false;
  bool _importing = false;
  double _viewScale = 1;
  StoryDocument? _synced;
  GlobalKey<TextEditOverlayState> _textKey = GlobalKey();

  static const Duration _noticeDuration = Duration(seconds: 2);
  static const Duration _filterLabelDuration = Duration(milliseconds: 900);

  StoryDocument get _document => _controller.document;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _initialized = true;
    _scope = StoryScope.read(context);
    final options = _scope.config.editor;
    _controller = EditorController(
      initialDocument: widget.initialDocument,
      options: options,
    )..addListener(_onDocumentChanged);
    _brush = DrawingBrush(
      tool: StrokeTool.pen,
      color: options.brushColors.isEmpty
          ? _scope.theme.onSurface
          : options.brushColors.first,
      size: options.brushSizes.isEmpty
          ? 16
          : options.brushSizes[options.brushSizes.length > 1 ? 1 : 0],
    );
    _lastOriginalVolume = widget.initialDocument.originalVolume > 0
        ? widget.initialDocument.originalVolume
        : 1;
    _synced = _document;
    WidgetsBinding.instance.addObserver(this);
    _mountMedia(_document);
    unawaited(_loadResources());
  }

  /// Sets up thumbnails, filter preview, playback and background for the
  /// document's media: at start, and whenever the media changes (replaced
  /// from the gallery, or by undo/redo of that).
  void _mountMedia(StoryDocument document) {
    final media = _media = document.media;
    _thumbnails = VideoThumbnails(
      inspector: _scope.services.inspector,
      media: media,
      directory: _scope.session.directory.path,
    );
    _preview = media.isVideo
        ? null
        : ResizeImage(FileImage(File(media.path)), width: 120);
    _playback?.dispose();
    _playback = null;
    if (media.isVideo || document.music != null) {
      final playback = _playback = EditorPlayback(
        services: _scope.services,
        media: media,
        onError: _onPlaybackError,
      );
      unawaited(playback.setActive(active: widget.active && _appVisible));
      unawaited(playback.start(document));
    }
    if (media.isVideo) {
      unawaited(_loadVideoPreview(media));
    }
    unawaited(_computeBackground(media));
  }

  @override
  void didUpdateWidget(EditorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _syncActive();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appVisible = state == AppLifecycleState.resumed;
    _syncActive();
  }

  void _syncActive() {
    final playback = _playback;
    if (playback != null) {
      unawaited(playback.setActive(active: widget.active && _appVisible));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _noticeTimer?.cancel();
    _controller
      ..removeListener(_onDocumentChanged)
      ..dispose();
    _playback?.dispose();
    _interaction.dispose();
    _notice.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- state

  void _onDocumentChanged() {
    final document = _document;
    if (identical(document, _synced)) {
      return;
    }
    _synced = document;
    if (document.media != _media) {
      setState(() => _mountMedia(document));
      return;
    }
    if (document.music != null && _playback == null) {
      final playback = _playback = EditorPlayback(
        services: _scope.services,
        media: document.media,
        onError: _onPlaybackError,
      );
      unawaited(playback.setActive(active: widget.active && _appVisible));
      unawaited(playback.start(document));
      setState(() {});
      return;
    }
    unawaited(_playback?.update(document));
  }

  void _report(Object error, StackTrace stackTrace, StoryErrorCode code) {
    _scope.reportError(
      error is StoryException
          ? error
          : StoryException(code, null, error, stackTrace),
      stackTrace,
    );
  }

  void _showNotice(String message) {
    _noticeTimer?.cancel();
    _notice.value = message;
    _noticeTimer = Timer(_noticeDuration, () => _notice.value = null);
  }

  void _onPlaybackError(
    PlaybackFailure failure,
    Object error,
    StackTrace stackTrace,
  ) {
    if (!mounted) {
      return;
    }
    final strings = _scope.strings.editor;
    _report(
      error,
      stackTrace,
      failure == PlaybackFailure.video
          ? StoryErrorCode.mediaUnsupported
          : StoryErrorCode.musicUnavailable,
    );
    _showNotice(
      failure == PlaybackFailure.video
          ? strings.videoUnavailable
          : strings.musicUnavailable,
    );
  }

  Future<void> _loadResources() async {
    try {
      await ensureStoryPaintResources(
        _scope.resources,
        _document,
        _scope.config.editor,
      );
    } on Object catch (e, s) {
      _report(e, s, StoryErrorCode.mediaUnavailable);
      return;
    }
    if (mounted) {
      setState(() => _resourcesRevision++);
    }
  }

  Future<void> _computeBackground(StoryMedia media) async {
    if (_document.background != const StoryBackground()) {
      return;
    }
    final thumbnails = _thumbnails;
    try {
      final path = media.isVideo ? await thumbnails.firstFrame() : media.path;
      final bytes = await File(path).readAsBytes();
      final background = await MediaPalette.fromEncoded(bytes);
      if (!mounted || _document.media != media) {
        return;
      }
      _controller.applyBackground(background);
    } on Object catch (e, s) {
      _report(e, s, StoryErrorCode.mediaUnavailable);
    }
  }

  Future<void> _loadVideoPreview(StoryMedia media) async {
    final thumbnails = _thumbnails;
    try {
      final path = await thumbnails.firstFrame();
      if (mounted && _media == media) {
        setState(
          () => _preview = ResizeImage(FileImage(File(path)), width: 120),
        );
      }
    } on Object catch (e, s) {
      _report(e, s, StoryErrorCode.mediaUnavailable);
    }
  }

  void _reportTool(String tool) => _scope.report(
    StoryEvent(StoryEventType.toolOpened, properties: {'tool': tool}),
  );

  void _toggleTool(EditorTool tool) {
    if (_controller.tool == tool) {
      _controller.setTool(EditorTool.none);
      return;
    }
    _controller.setTool(tool);
    _reportTool(tool.name);
    if (tool == EditorTool.adjust && _controller.selectedOverlay == null) {
      final overlays = _document.overlays;
      if (overlays.isNotEmpty) {
        _controller.select(overlays.last.id);
      }
    }
  }

  // ----------------------------------------------------------------- text

  TextOverlayStyle get _defaultTextStyle {
    final options = _scope.config.editor;
    return _lastTextStyle ??
        TextOverlayStyle(
          fontId: options.fonts.isEmpty ? 'system' : options.fonts.first.id,
          color: options.textColors.isEmpty
              ? _scope.theme.onSurface
              : options.textColors.first,
        );
  }

  void _startText(TextOverlay? existing) {
    if (!_scope.config.editor.enableText) {
      return;
    }
    if (existing == null && !_controller.canAddOverlay) {
      _showNotice(_scope.strings.editor.maxOverlaysReached);
      return;
    }
    _controller
      ..setTool(EditorTool.text)
      ..select(existing?.id);
    _reportTool(EditorTool.text.name);
    setState(() {
      _textKey = GlobalKey();
      _editing = _TextEditing(
        overlayId: existing?.id,
        text: existing?.text ?? '',
        style: existing?.style ?? _defaultTextStyle,
      );
    });
  }

  void _finishText(String text, TextOverlayStyle style) {
    final editing = _editing;
    if (editing == null) {
      return;
    }
    _lastTextStyle = style.copyWith(align: TextAlign.center);
    final result = _controller.commitText(
      text: text,
      style: style,
      id: editing.overlayId,
    );
    if (result == null &&
        editing.overlayId == null &&
        text.trim().isNotEmpty &&
        !_controller.canAddOverlay) {
      _showNotice(_scope.strings.editor.maxOverlaysReached);
    }
    _controller.setTool(EditorTool.none);
    setState(() => _editing = null);
  }

  void _onFontError(Object error, StackTrace stackTrace) {
    _report(error, stackTrace, StoryErrorCode.mediaUnavailable);
    _showNotice(_scope.strings.editor.fontUnavailable);
  }

  // --------------------------------------------------------------- canvas

  void _onCanvasTap(StoryOverlay? hit) {
    if (hit is TextOverlay) {
      _startText(hit);
      return;
    }
    if (hit != null) {
      _controller
        ..select(hit.id)
        ..bringToFront(hit.id);
      return;
    }
    _controller.select(null);
    if (_controller.tool != EditorTool.none) {
      _controller.setTool(EditorTool.none);
      return;
    }
    _startText(null);
  }

  List<StoryFilter> get _filters => _scope.config.editor.filters;

  int get _filterIndex {
    final filters = _filters;
    final id = _document.filterId;
    final index = filters.indexWhere((f) => f.id == id);
    if (index >= 0) {
      return index;
    }
    final identity = filters.indexWhere((f) => f.isIdentity);
    return identity >= 0 ? identity : 0;
  }

  void _selectFilter(StoryFilter filter, {bool showLabel = false}) {
    _controller.setFilter(filter);
    if (showLabel) {
      _interaction.showFilterLabel(filter.label, _filterLabelDuration);
    }
  }

  void _onFilterSwipe(int direction) {
    final filters = _filters;
    if (!_scope.config.editor.enableFilters || filters.length < 2) {
      return;
    }
    final next = (_filterIndex + direction).clamp(0, filters.length - 1);
    if (next == _filterIndex) {
      return;
    }
    _selectFilter(filters[next], showLabel: true);
  }

  void _onOverlayAction(StoryOverlay overlay, OverlayAction action) {
    OverlayActions.apply(_controller, overlay.id, action, onEdit: _startText);
  }

  void _onOverlayActivate(StoryOverlay overlay) {
    if (overlay is TextOverlay) {
      _startText(overlay);
    } else {
      _controller.select(overlay.id);
    }
  }

  void _selectRelative(int direction) {
    final overlays = _document.overlays;
    if (overlays.isEmpty) {
      return;
    }
    final current = overlays.indexWhere((o) => o.id == _controller.selectedId);
    final next = current < 0
        ? overlays.length - 1
        : (current + direction) % overlays.length;
    _controller.select(overlays[next].id);
  }

  // ------------------------------------------------------------- stickers

  void _addSticker(StorySticker sticker) {
    if (!_controller.addSticker(sticker.id)) {
      _showNotice(_scope.strings.editor.maxOverlaysReached);
      return;
    }
    _controller.setTool(EditorTool.none);
    loadStorySticker(
      _scope.resources,
      sticker,
      configuration: createLocalImageConfiguration(context),
    ).then(
      (_) {
        if (mounted) {
          setState(() => _resourcesRevision++);
        }
      },
      onError: (Object e, StackTrace s) {
        if (mounted) {
          _report(e, s, StoryErrorCode.mediaUnavailable);
          _showNotice(_scope.strings.editor.stickerUnavailable);
        }
      },
    );
  }

  void _addEmoji(String emoji) {
    if (!_controller.addEmoji(emoji)) {
      _showNotice(_scope.strings.editor.maxOverlaysReached);
      return;
    }
    _controller.setTool(EditorTool.none);
  }

  // ---------------------------------------------------------------- media

  Duration? get _videoDuration {
    final media = _document.media;
    if (!media.isVideo) {
      return null;
    }
    final known = media.duration;
    if (known != null && known > Duration.zero) {
      return known;
    }
    final state = _playback?.video?.state.value;
    return state != null && state.duration > Duration.zero
        ? state.duration
        : null;
  }

  Future<void> _openMusic() async {
    final constraints = _scope.config.constraints;
    final length = _controller.musicSegmentLength(
      photoDuration: constraints.photoWithMusicDuration,
      maxDuration: constraints.maxVideoDuration,
    );
    _reportTool('music');
    final playback = _playback;
    await playback?.setActive(active: false);
    if (!mounted) {
      return;
    }
    final current = _document.music;
    final selection = await showMusicPicker(
      context,
      segmentLength: length,
      current: current,
      canvas: (_) => _ReadOnlyCanvas(state: this),
    );
    if (!mounted) {
      return;
    }
    if (selection != current) {
      _controller.setMusic(selection?.copyWith(duration: length));
    }
    _syncActive();
  }

  bool get _galleryEnabled =>
      _scope.config.capture.galleryMode != GalleryMode.disabled;

  /// Picks new media from the gallery (in-app grid or system picker) and
  /// swaps it under the edits.
  Future<void> _replaceMedia() async {
    if (_importing || !_galleryEnabled) {
      return;
    }
    final gallery = _scope.services.gallery;
    final constraints = _scope.config.constraints;
    await _playback?.setActive(active: false);
    if (!mounted) {
      return;
    }
    final PickedMedia? picked;
    try {
      picked =
          _scope.config.capture.galleryMode == GalleryMode.inApp &&
              gallery.supportsGrid
          ? await GallerySheet.open(context)
          : await gallery.pickWithSystemPicker(
              photos: constraints.allowPhotos,
              videos: constraints.allowVideos,
            );
    } on StoryException catch (e, s) {
      _importFailed(e, s);
      return;
    }
    if (!mounted) {
      return;
    }
    if (picked == null) {
      _syncActive();
      return;
    }
    setState(() => _importing = true);
    try {
      final media = await MediaImporter(
        inspector: _scope.services.inspector,
        session: _scope.session,
        constraints: constraints,
      ).importPicked(picked);
      if (!mounted) {
        return;
      }
      _controller.replaceMedia(
        media,
        maxDuration: constraints.maxVideoDuration,
        photoDuration: constraints.photoWithMusicDuration,
      );
      _scope.report(
        StoryEvent(
          StoryEventType.mediaPicked,
          properties: {'type': media.type.name, 'replaced': true},
        ),
      );
    } on MediaTooShortException {
      _showNotice(_scope.strings.camera.videoTooShort);
    } on StoryException catch (e, s) {
      _importFailed(e, s);
    } finally {
      if (mounted) {
        setState(() => _importing = false);
        _syncActive();
      }
    }
  }

  void _importFailed(StoryException error, StackTrace stackTrace) {
    if (!mounted) {
      return;
    }
    _report(error, stackTrace, error.code);
    final strings = _scope.strings.camera;
    _showNotice(switch (error.code) {
      StoryErrorCode.mediaTooLarge => strings.mediaTooLarge,
      StoryErrorCode.mediaUnsupported => strings.mediaUnsupported,
      _ => strings.mediaUnavailable,
    });
    _syncActive();
  }

  void _toggleMoreTools() => setState(() => _moreTools = !_moreTools);

  void _setBrush(DrawingBrush brush) => setState(() => _brush = brush);

  void _toggleMute() {
    final volume = _document.originalVolume;
    if (volume > 0) {
      _lastOriginalVolume = volume;
      _controller.setOriginalVolume(0);
    } else {
      _controller.setOriginalVolume(_lastOriginalVolume);
    }
  }

  // ----------------------------------------------------------- navigation

  Future<void> _handleBack() async {
    if (!widget.active) {
      return;
    }
    if (_editing != null) {
      // Back while typing finishes the text, like Done.
      _textKey.currentState?.finish();
      return;
    }
    if (_controller.tool != EditorTool.none) {
      _controller.setTool(EditorTool.none);
      return;
    }
    await _confirmLeave();
  }

  /// Whether leaving may go ahead: asks when the document is dirty and
  /// `EditorOptions.confirmDiscard` is on.
  Future<bool> _confirmDiscard() async {
    if (!_controller.isDirty || !_scope.config.editor.confirmDiscard) {
      return true;
    }
    final discard = await DiscardDialog.show(
      context,
      theme: _scope.theme,
      strings: _scope.strings.common,
    );
    return discard && mounted;
  }

  Future<void> _confirmLeave() async {
    if (await _confirmDiscard()) {
      widget.onBack();
    }
  }

  void _export() {
    _controller
      ..endGesture()
      ..setTool(EditorTool.none);
    widget.onExport(_document);
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final editing = _editing;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_handleBack());
        }
      },
      child: TickerMode(
        enabled: active,
        child: ExcludeSemantics(
          excluding: !active,
          child: IgnorePointer(
            ignoring: !active,
            child: Material(
              type: MaterialType.transparency,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  StoryStage(
                    card: LayoutBuilder(
                      builder: (context, constraints) {
                        final scale = StoryCanvas.viewScale(
                          constraints.biggest,
                        );
                        _trackViewScale(scale);
                        return ListenableBuilder(
                          listenable: Listenable.merge([
                            _controller,
                            _interaction,
                            ?_playback,
                          ]),
                          builder: (context, _) => Center(
                            child: SizedBox(
                              width: StoryCanvas.width * scale,
                              height: StoryCanvas.height * scale,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  _scope.theme.cornerRadius,
                                ),
                                child: _EditorCard(state: this, scale: scale),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (editing != null)
                    TextEditOverlay(
                      key: _textKey,
                      initialText: editing.text,
                      initialStyle: editing.style,
                      options: _scope.config.editor,
                      viewScale: _viewScale,
                      onDone: _finishText,
                      onFontError: _onFontError,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Remembers the canvas scale for the text editor, which is laid out
  /// over the whole screen rather than inside the card.
  void _trackViewScale(double scale) {
    if (scale == _viewScale) {
      return;
    }
    _viewScale = scale;
    if (_editing != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }
}

/// The canvas card: canvas plus the chrome of the open tool.
class _EditorCard extends StatelessWidget {
  const _EditorCard({required this.state, required this.scale});

  final _EditorScreenState state;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final controller = state._controller;
    final document = controller.document;
    final scope = state._scope;
    final tool = controller.tool;
    final dragging = state._interaction.dragging;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final chromeDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 150);
    final drawing = tool == EditorTool.draw;
    final showChrome = !dragging && state._editing == null;
    return Stack(
      fit: StackFit.expand,
      children: [
        StoryCanvasView(
          document: document,
          controller: controller,
          interaction: state._interaction,
          resources: scope.resources,
          resourcesRevision: state._resourcesRevision,
          options: scope.config.editor,
          strings: scope.strings.editor,
          viewScale: scale,
          brush: state._brush,
          drawing: drawing,
          video: state._playback?.video?.buildView(),
          hiddenOverlayId: state._editing?.overlayId,
          onTap: state._onCanvasTap,
          onFilterSwipe: state._onFilterSwipe,
          onStroke: controller.addStroke,
          onOverlayAction: state._onOverlayAction,
          onOverlayActivate: state._onOverlayActivate,
          onCanvasActivate: scope.config.editor.enableText
              ? () => state._startText(null)
              : null,
        ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !showChrome,
            child: AnimatedOpacity(
              opacity: showChrome ? 1 : 0,
              duration: chromeDuration,
              child: drawing
                  ? _DrawingChrome(state: state)
                  : _MainChrome(state: state, scale: scale),
            ),
          ),
        ),
        Positioned(
          top: 72,
          left: 16,
          right: 16,
          child: IgnorePointer(
            child: Center(child: EditorNotice(message: state._notice)),
          ),
        ),
      ],
    );
  }
}

/// The story as the editor shows it, without input or chrome: the backdrop
/// of the music segment selector.
class _ReadOnlyCanvas extends StatelessWidget {
  const _ReadOnlyCanvas({required this.state});

  final _EditorScreenState state;

  @override
  Widget build(BuildContext context) {
    final scope = state._scope;
    final controller = state._controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = StoryCanvas.viewScale(constraints.biggest);
        return Center(
          child: SizedBox(
            width: StoryCanvas.width * scale,
            height: StoryCanvas.height * scale,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: StoryCanvasView(
                  document: controller.document,
                  controller: controller,
                  interaction: state._interaction,
                  resources: scope.resources,
                  resourcesRevision: state._resourcesRevision,
                  options: scope.config.editor,
                  strings: scope.strings.editor,
                  viewScale: scale,
                  brush: state._brush,
                  drawing: false,
                  video: state._playback?.video?.buildView(),
                  onTap: (_) {},
                  onFilterSwipe: (_) {},
                  onStroke: (_) {},
                  onOverlayAction: (_, _) {},
                  onOverlayActivate: (_) {},
                  onCanvasActivate: null,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MainChrome extends StatelessWidget {
  const _MainChrome({required this.state, required this.scale});

  final _EditorScreenState state;
  final double scale;

  /// Card padding of the design's controls.
  static const double inset = 16;

  @override
  Widget build(BuildContext context) {
    final controller = state._controller;
    final tool = controller.tool;
    final isVideo = controller.document.media.isVideo;
    // Tool panels open at the bottom and would cover the thumbnail row.
    final panelOpen = tool != EditorTool.none && tool != EditorTool.text;
    const navInset = inset - (48 - StoryNavButton.size) / 2;
    return Stack(
      children: [
        Positioned(
          top: 12 - (48 - StoryNavButton.size) / 2,
          left: navInset,
          right: navInset,
          child: _NavRow(state: state),
        ),
        _ToolRail(state: state, height: StoryCanvas.height * scale),
        if (!panelOpen)
          Positioned(
            left: inset,
            right: inset,
            bottom: inset,
            child: _BottomRow(state: state),
          ),
        if (isVideo && tool == EditorTool.trim)
          Positioned(left: 12, bottom: 148, child: _PlayButton(state: state)),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _ToolPanel(state: state),
        ),
      ],
    );
  }
}

/// Close on the left, confirm (export) on the right.
class _NavRow extends StatelessWidget {
  const _NavRow({required this.state});

  final _EditorScreenState state;

  @override
  Widget build(BuildContext context) {
    final strings = state._scope.strings;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        StoryNavButton(
          icon: StoryIcons.close,
          label: strings.common.close,
          onPressed: () => unawaited(state._confirmLeave()),
        ),
        StoryNavButton(
          icon: StoryIcons.check,
          label: strings.editor.export,
          style: StoryNavButtonStyle.accent,
          onPressed: state._export,
        ),
      ],
    );
  }
}

/// The right-hand tool column: music, text and stickers, then a chevron
/// that shows or hides the other tools.
class _ToolRail extends StatelessWidget {
  const _ToolRail({required this.state, required this.height});

  final _EditorScreenState state;

  /// Height of the canvas the rail sits on.
  final double height;

  /// Room kept free above (nav row) and below (thumbnail row).
  static const double _top = 68;
  static const double _bottom = 84;

  /// Open/close animation of the More tools.
  static const Duration _toggleDuration = Duration(milliseconds: 280);

  @override
  Widget build(BuildContext context) {
    final scope = state._scope;
    final options = scope.config.editor;
    final strings = scope.strings.editor;
    final controller = state._controller;
    final document = controller.document;
    final media = document.media;
    final tool = controller.tool;
    final duration = state._videoDuration;
    final minDuration = scope.config.constraints.minVideoDuration;
    final main = <Widget>[
      if (scope.config.musicEnabled)
        EditorToolButton(
          icon: StoryIcons.music,
          label: strings.music,
          selected: document.music != null,
          onPressed: () => unawaited(state._openMusic()),
        ),
      if (options.enableText)
        EditorToolButton(
          icon: StoryIcons.text,
          label: strings.text,
          onPressed: () => state._startText(null),
        ),
      if (options.enableStickers &&
          (options.stickers.isNotEmpty || options.emojis.isNotEmpty))
        EditorToolButton(
          icon: StoryIcons.layouts,
          label: strings.stickers,
          selected: tool == EditorTool.stickers,
          onPressed: () => state._toggleTool(EditorTool.stickers),
        ),
    ];
    final more = <Widget>[
      if (options.enableDrawing)
        EditorToolButton(
          glyph: Icons.brush_outlined,
          label: strings.draw,
          onPressed: () => state._toggleTool(EditorTool.draw),
        ),
      if (options.enableFilters && options.filters.length > 1)
        EditorToolButton(
          glyph: Icons.filter_vintage_outlined,
          label: strings.filters,
          selected: tool == EditorTool.filters,
          onPressed: () => state._toggleTool(EditorTool.filters),
        ),
      if (media.isVideo &&
          options.enableTrim &&
          duration != null &&
          duration > minDuration)
        EditorToolButton(
          glyph: Icons.content_cut,
          label: strings.trim,
          selected: tool == EditorTool.trim,
          onPressed: () => state._toggleTool(EditorTool.trim),
        ),
      if (options.enableAudioMix &&
          ((media.isVideo && media.hasAudio) || document.music != null))
        EditorToolButton(
          glyph: Icons.graphic_eq,
          label: strings.audio,
          selected: tool == EditorTool.audio,
          onPressed: () => state._toggleTool(EditorTool.audio),
        ),
      if (document.overlays.isNotEmpty)
        EditorToolButton(
          glyph: Icons.open_with,
          label: strings.adjust,
          selected: tool == EditorTool.adjust,
          onPressed: () => state._toggleTool(EditorTool.adjust),
        ),
      EditorToolButton(
        glyph: Icons.undo,
        label: strings.undo,
        onPressed: controller.canUndo ? controller.undo : null,
      ),
      EditorToolButton(
        glyph: Icons.redo,
        label: strings.redo,
        onPressed: controller.canRedo ? controller.redo : null,
      ),
    ];
    final expanded = state._moreTools;
    final chevron = EditorToolButton(
      key: EditorKeys.moreTools,
      // Rotated by the column: points down when collapsed, up when open.
      glyph: Icons.keyboard_arrow_down,
      label: expanded ? strings.fewerTools : strings.moreTools,
      onPressed: state._toggleMoreTools,
    );
    // The main icons are centred on the canvas and the More tools grow
    // downwards. The top is worked out once for the fully expanded column
    // (raised only if that would reach the thumbnail row), so the main
    // icons never move while the column opens or closes.
    final mainHeight = EditorToolColumn.heightFor(
      main.isEmpty ? 1 : main.length,
    );
    final centred = (height - mainHeight) / 2;
    final expandedHeight = AnimatedEditorToolColumn.heightFor(
      main.length,
      more.length,
      1,
    );
    final top = math.max(
      _top,
      math.min(centred, height - _bottom - expandedHeight),
    );
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: expanded ? 1 : 0),
      duration: reduceMotion ? Duration.zero : _toggleDuration,
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) {
        return Positioned(
          top: top,
          // The 20 px icons end 16 px from the card edge.
          right:
              _MainChrome.inset -
              (EditorToolButton.target - EditorToolButton.iconSize) / 2,
          child: AnimatedEditorToolColumn(
            main: main,
            more: more,
            chevron: chevron,
            progress: progress,
          ),
        );
      },
    );
  }
}

/// Gallery thumbnail (replace media), play/pause for videos and the music
/// chip.
class _BottomRow extends StatelessWidget {
  const _BottomRow({required this.state});

  final _EditorScreenState state;

  @override
  Widget build(BuildContext context) {
    final strings = state._scope.strings.editor;
    final document = state._controller.document;
    final music = document.music;
    final replace = state._importing
        ? null
        : () => unawaited(state._replaceMedia());
    return Row(
      spacing: 8,
      children: [
        if (state._galleryEnabled)
          Semantics(
            key: EditorKeys.replaceMedia,
            button: true,
            enabled: replace != null,
            label: strings.replaceMedia,
            excludeSemantics: true,
            onTap: replace,
            child: GalleryShortcut(onPressed: replace),
          ),
        if (document.media.isVideo) _PlayButton(state: state),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: music == null
                ? null
                : MusicChip(
                    key: EditorKeys.musicChip,
                    music: music,
                    onPressed: () => unawaited(state._openMusic()),
                  ),
          ),
        ),
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.state});

  final _EditorScreenState state;

  @override
  Widget build(BuildContext context) {
    final playback = state._playback;
    if (playback == null) {
      return const SizedBox.shrink();
    }
    final strings = state._scope.strings.editor;
    final paused = playback.userPaused;
    return EditorIconButton(
      icon: paused ? Icons.play_arrow : Icons.pause,
      label: paused ? strings.play : strings.pause,
      onPressed: () => unawaited(playback.togglePause()),
    );
  }
}

class _ToolPanel extends StatelessWidget {
  const _ToolPanel({required this.state});

  final _EditorScreenState state;

  @override
  Widget build(BuildContext context) {
    final scope = state._scope;
    final options = scope.config.editor;
    final controller = state._controller;
    final document = controller.document;
    switch (controller.tool) {
      case EditorTool.none:
      case EditorTool.text:
      case EditorTool.draw:
        return const SizedBox.shrink();
      case EditorTool.stickers:
        return StickerPickerPanel(
          stickers: options.stickers,
          emojis: options.emojis,
          onSticker: state._addSticker,
          onEmoji: state._addEmoji,
          onClose: () => controller.setTool(EditorTool.none),
        );
      case EditorTool.filters:
        return FilterStrip(
          filters: options.filters,
          selectedIndex: state._filterIndex,
          preview: state._preview,
          onSelected: state._selectFilter,
        );
      case EditorTool.trim:
        final total = state._videoDuration;
        if (total == null) {
          return const SizedBox.shrink();
        }
        final playback = state._playback;
        return TrimBar(
          total: total,
          range: document.trim ?? TrimRange(Duration.zero, total),
          minDuration: scope.config.constraints.minVideoDuration,
          maxDuration: scope.config.constraints.maxVideoDuration,
          thumbnails: state._thumbnails.strip(total),
          playback: playback?.video?.state,
          onChangeStart: controller.beginGesture,
          onChanged: (range, position) {
            controller.setTrim(range, videoDuration: total);
            if (playback != null) {
              unawaited(playback.scrub(position));
            }
          },
          onChangeEnd: () {
            controller.endGesture();
            if (playback != null) {
              unawaited(playback.endScrub(controller.document));
            }
          },
        );
      case EditorTool.audio:
        final media = document.media;
        return AudioMixPanel(
          showOriginal: media.isVideo && media.hasAudio,
          showMusic: document.music != null,
          originalVolume: document.originalVolume,
          musicVolume: document.music?.volume ?? 1,
          onChangeStart: controller.beginGesture,
          onOriginalChanged: controller.setOriginalVolume,
          onMusicChanged: controller.setMusicVolume,
          onChangeEnd: controller.endGesture,
          onToggleMute: state._toggleMute,
        );
      case EditorTool.adjust:
        final overlay = controller.selectedOverlay;
        if (overlay == null) {
          return const SizedBox.shrink();
        }
        final (label, value) = OverlaySemanticsLayer.describe(
          overlay,
          scope.strings.editor,
          options,
        );
        return OverlayAdjustPanel(
          overlay: overlay,
          description: value.isEmpty ? label : value,
          onAction: (action) => state._onOverlayAction(overlay, action),
          onSelect: state._selectRelative,
          onClose: () => controller.setTool(EditorTool.none),
        );
    }
  }
}

class _DrawingChrome extends StatelessWidget {
  const _DrawingChrome({required this.state});

  final _EditorScreenState state;

  @override
  Widget build(BuildContext context) {
    final controller = state._controller;
    final options = state._scope.config.editor;
    return Stack(
      children: [
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: DrawingTopBar(
            canUndo: controller.canUndo,
            canRedo: controller.canRedo,
            onUndo: controller.undo,
            onRedo: controller.redo,
            onDone: () => controller.setTool(EditorTool.none),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: DrawingToolbar(
            brush: state._brush,
            sizes: options.brushSizes,
            colors: options.brushColors,
            onChanged: state._setBrush,
          ),
        ),
      ],
    );
  }
}
