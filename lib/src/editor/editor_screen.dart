import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../api/assets/story_filter.dart';
import '../api/assets/story_sticker.dart';
import '../api/errors/story_exception.dart';
import '../api/events/story_event.dart';
import '../core/story_canvas.dart';
import '../core/story_scope.dart';
import '../model/drawing_stroke.dart';
import '../model/media_placement.dart';
import '../model/story_document.dart';
import '../model/story_overlay.dart';
import '../model/trim_range.dart';
import '../music/music_picker.dart';
import '../render/painters/story_paint_resources_loader.dart';
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
import 'filters/filter_strip.dart';
import 'stickers/sticker_picker_panel.dart';
import 'text/text_edit_overlay.dart';
import 'video/editor_playback.dart';
import 'video/trim_bar.dart';
import 'video/video_thumbnails.dart';
import 'widgets/discard_dialog.dart';
import 'widgets/editor_icon_button.dart';
import 'widgets/editor_panel.dart';

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
  late final VideoThumbnails _thumbnails;
  Timer? _noticeTimer;
  _TextEditing? _editing;
  TextOverlayStyle? _lastTextStyle;
  ImageProvider? _preview;
  double _lastOriginalVolume = 1;
  int _resourcesRevision = 0;
  bool _initialized = false;
  bool _appVisible = true;
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
    final media = widget.initialDocument.media;
    _thumbnails = VideoThumbnails(
      inspector: _scope.services.inspector,
      media: media,
      directory: _scope.session.directory.path,
    );
    _preview = media.isVideo
        ? null
        : ResizeImage(FileImage(File(media.path)), width: 120);
    if (media.isVideo || widget.initialDocument.music != null) {
      final playback = _playback = EditorPlayback(
        services: _scope.services,
        media: media,
        onError: _onPlaybackError,
      );
      unawaited(playback.setActive(active: widget.active));
      unawaited(playback.start(_document));
    }
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadResources());
    if (media.isVideo) {
      unawaited(_loadVideoPreview());
    }
    unawaited(_computeBackground());
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

  Future<void> _computeBackground() async {
    if (_document.background != const StoryBackground()) {
      return;
    }
    final media = _document.media;
    try {
      final path = media.isVideo ? await _thumbnails.firstFrame() : media.path;
      final bytes = await File(path).readAsBytes();
      final background = await MediaPalette.fromEncoded(bytes);
      if (!mounted) {
        return;
      }
      _controller.applyBackground(background);
    } on Object catch (e, s) {
      _report(e, s, StoryErrorCode.mediaUnavailable);
    }
  }

  Future<void> _loadVideoPreview() async {
    try {
      final path = await _thumbnails.firstFrame();
      if (mounted) {
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
    );
    if (!mounted) {
      return;
    }
    if (selection != current) {
      _controller.setMusic(selection?.copyWith(duration: length));
    }
    _syncActive();
  }

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

  Future<void> _confirmLeave() async {
    final options = _scope.config.editor;
    if (_controller.isDirty && options.confirmDiscard) {
      final discard = await DiscardDialog.show(
        context,
        theme: _scope.theme,
        strings: _scope.strings.common,
      );
      if (!discard || !mounted) {
        return;
      }
    }
    widget.onBack();
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
    final theme = _scope.theme;
    final active = widget.active;
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
              child: ColoredBox(
                color: theme.background,
                child: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final scale = StoryCanvas.viewScale(constraints.biggest);
                      return ListenableBuilder(
                        listenable: Listenable.merge([
                          _controller,
                          _interaction,
                          ?_playback,
                        ]),
                        builder: (context, _) => Stack(
                          fit: StackFit.expand,
                          children: [
                            Center(
                              child: SizedBox(
                                width: StoryCanvas.width * scale,
                                height: StoryCanvas.height * scale,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    theme.cornerRadius * 1.5,
                                  ),
                                  child: _EditorCard(state: this, scale: scale),
                                ),
                              ),
                            ),
                            if (_editing != null)
                              TextEditOverlay(
                                key: _textKey,
                                initialText: _editing!.text,
                                initialStyle: _editing!.style,
                                options: _scope.config.editor,
                                viewScale: scale,
                                onDone: _finishText,
                                onFontError: _onFontError,
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
                  : _MainChrome(state: state),
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

class _MainChrome extends StatelessWidget {
  const _MainChrome({required this.state});

  final _EditorScreenState state;

  @override
  Widget build(BuildContext context) {
    final controller = state._controller;
    final tool = controller.tool;
    final isVideo = controller.document.media.isVideo;
    return Stack(
      children: [
        Positioned(top: 12, left: 12, right: 12, child: _TopBar(state: state)),
        Positioned(top: 72, right: 12, child: _ToolRail(state: state)),
        if (isVideo && (tool == EditorTool.none || tool == EditorTool.trim))
          Positioned(
            left: 12,
            bottom: tool == EditorTool.trim ? 148 : 16,
            child: _PlayButton(state: state),
          ),
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

class _TopBar extends StatelessWidget {
  const _TopBar({required this.state});

  final _EditorScreenState state;

  @override
  Widget build(BuildContext context) {
    final strings = state._scope.strings;
    final controller = state._controller;
    return Row(
      children: [
        EditorIconButton(
          icon: Icons.close,
          label: strings.common.close,
          onPressed: () => unawaited(state._confirmLeave()),
        ),
        const Spacer(),
        EditorIconButton(
          icon: Icons.undo,
          label: strings.editor.undo,
          onPressed: controller.canUndo ? controller.undo : null,
        ),
        const SizedBox(width: 8),
        EditorIconButton(
          icon: Icons.redo,
          label: strings.editor.redo,
          onPressed: controller.canRedo ? controller.redo : null,
        ),
        const Spacer(),
        EditorIconButton(
          icon: Icons.check,
          label: strings.editor.export,
          filled: true,
          onPressed: state._export,
        ),
      ],
    );
  }
}

class _ToolRail extends StatelessWidget {
  const _ToolRail({required this.state});

  final _EditorScreenState state;

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
    final buttons = <Widget>[
      if (scope.config.musicEnabled)
        EditorIconButton(
          icon: Icons.music_note,
          label: strings.music,
          selected: document.music != null,
          onPressed: () => unawaited(state._openMusic()),
        ),
      if (options.enableText)
        EditorIconButton(
          icon: Icons.text_fields,
          label: strings.text,
          onPressed: () => state._startText(null),
        ),
      if (options.enableStickers &&
          (options.stickers.isNotEmpty || options.emojis.isNotEmpty))
        EditorIconButton(
          icon: Icons.emoji_emotions,
          label: strings.stickers,
          selected: tool == EditorTool.stickers,
          onPressed: () => state._toggleTool(EditorTool.stickers),
        ),
      if (options.enableDrawing)
        EditorIconButton(
          icon: Icons.brush,
          label: strings.draw,
          onPressed: () => state._toggleTool(EditorTool.draw),
        ),
      if (options.enableFilters && options.filters.length > 1)
        EditorIconButton(
          icon: Icons.filter_vintage,
          label: strings.filters,
          selected: tool == EditorTool.filters,
          onPressed: () => state._toggleTool(EditorTool.filters),
        ),
      if (media.isVideo &&
          options.enableTrim &&
          duration != null &&
          duration > minDuration)
        EditorIconButton(
          icon: Icons.content_cut,
          label: strings.trim,
          selected: tool == EditorTool.trim,
          onPressed: () => state._toggleTool(EditorTool.trim),
        ),
      if (options.enableAudioMix &&
          ((media.isVideo && media.hasAudio) || document.music != null))
        EditorIconButton(
          icon: Icons.graphic_eq,
          label: strings.audio,
          selected: tool == EditorTool.audio,
          onPressed: () => state._toggleTool(EditorTool.audio),
        ),
      if (document.overlays.isNotEmpty)
        EditorIconButton(
          icon: Icons.open_with,
          label: strings.adjust,
          selected: tool == EditorTool.adjust,
          onPressed: () => state._toggleTool(EditorTool.adjust),
        ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final button in buttons) ...[button, const SizedBox(height: 8)],
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
