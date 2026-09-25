import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../api/assets/story_filter.dart';
import '../api/config/editor_options.dart';
import '../core/story_canvas.dart';
import '../model/drawing_stroke.dart';
import '../model/history.dart';
import '../model/media_placement.dart';
import '../model/music_selection.dart';
import '../model/overlay_transform.dart';
import '../model/story_document.dart';
import '../model/story_overlay.dart';
import '../model/trim_range.dart';

/// Editor tools. At most one is open at a time.
enum EditorTool {
  /// No tool: gestures move overlays and media.
  none,

  /// Text editing overlay.
  text,

  /// Freehand drawing.
  draw,

  /// Sticker and emoji picker.
  stickers,

  /// Filter strip.
  filters,

  /// Video trimmer.
  trim,

  /// Original-audio and music volumes.
  audio,

  /// Button-based overlay adjustments (accessibility).
  adjust,
}

/// State of the editor: the document with undo/redo, the open tool and the
/// selected overlay. Every edit goes through here.
///
/// Continuous interactions (drags, pinches, slider moves) are wrapped in
/// [beginGesture] / [endGesture]: changes in between replace the current
/// document and become one undo step when the gesture ends.
class EditorController extends ChangeNotifier {
  /// Creates a controller starting at [initialDocument].
  EditorController({
    required StoryDocument initialDocument,
    required this.options,
    int historyLimit = 100,
  }) : _history = History(initialDocument, limit: historyLimit),
       _baseline = initialDocument {
    _history.addListener(_onHistory);
  }

  /// Minimum overlay scale.
  static const double minOverlayScale = 0.2;

  /// Maximum overlay scale.
  static const double maxOverlayScale = 8;

  /// Minimum media scale (relative to contain).
  static const double minMediaScale = 0.4;

  /// Maximum media scale (relative to contain).
  static const double maxMediaScale = 8;

  /// Editor options (limits, palettes).
  final EditorOptions options;

  final History<StoryDocument> _history;
  StoryDocument _baseline;
  EditorTool _tool = EditorTool.none;
  String? _selectedId;
  StoryDocument? _gestureStart;
  int _idCounter = 0;

  /// The current document.
  StoryDocument get document => _history.current;

  /// Whether there is something to undo.
  bool get canUndo => _history.canUndo;

  /// Whether there is something to redo.
  bool get canRedo => _history.canRedo;

  /// Whether the document differs from the one the editor opened with.
  bool get isDirty => document != _baseline;

  /// The open tool.
  EditorTool get tool => _tool;

  /// Id of the selected overlay, if it still exists.
  String? get selectedId => _selectedId;

  /// The selected overlay, if any.
  StoryOverlay? get selectedOverlay => overlayById(_selectedId);

  /// Whether a gesture is in progress.
  bool get inGesture => _gestureStart != null;

  /// Whether another text or sticker can be added.
  bool get canAddOverlay => document.overlays.length < options.maxOverlays;

  /// The overlay with [id], if any.
  StoryOverlay? overlayById(String? id) {
    if (id == null) {
      return null;
    }
    for (final overlay in document.overlays) {
      if (overlay.id == id) {
        return overlay;
      }
    }
    return null;
  }

  void _onHistory() {
    if (_selectedId != null && overlayById(_selectedId) == null) {
      _selectedId = null;
    }
    notifyListeners();
  }

  void _apply(StoryDocument next) {
    if (_gestureStart != null) {
      _history.replace(next);
    } else {
      _history.push(next);
    }
  }

  /// Opens [tool] (or closes all tools with [EditorTool.none]).
  void setTool(EditorTool tool) {
    if (_tool == tool) {
      return;
    }
    _tool = tool;
    notifyListeners();
  }

  /// Selects the overlay with [id] (`null` clears the selection).
  void select(String? id) {
    if (_selectedId == id) {
      return;
    }
    _selectedId = id;
    notifyListeners();
  }

  /// Starts a continuous change.
  void beginGesture() => _gestureStart ??= document;

  /// Ends a continuous change, recording one undo step if anything changed.
  void endGesture() {
    final start = _gestureStart;
    _gestureStart = null;
    if (start != null) {
      _history.commitFrom(start);
    }
  }

  /// Steps back.
  void undo() {
    endGesture();
    _history.undo();
  }

  /// Steps forward.
  void redo() {
    endGesture();
    _history.redo();
  }

  /// Applies the computed background without recording an undo step and
  /// without making the document dirty.
  void applyBackground(StoryBackground background) {
    _baseline = _baseline.copyWith(background: background);
    final start = _gestureStart;
    if (start != null) {
      _gestureStart = start.copyWith(background: background);
    }
    _history.replace(document.copyWith(background: background));
  }

  String _newId(String prefix) {
    String id;
    do {
      _idCounter++;
      id = '$prefix$_idCounter';
    } while (overlayById(id) != null);
    return id;
  }

  /// Creates or updates a text overlay from the text editor. Empty text
  /// deletes an existing overlay. Returns the overlay, or `null` when it was
  /// deleted, empty, or the overlay limit is reached.
  TextOverlay? commitText({
    required String text,
    required TextOverlayStyle style,
    String? id,
  }) {
    final existing = overlayById(id);
    if (text.trim().isEmpty) {
      if (existing != null) {
        deleteOverlay(existing.id);
      }
      return null;
    }
    if (existing is TextOverlay) {
      final updated = existing.copyWith(text: text, style: style);
      _apply(
        document.copyWith(
          overlays: [
            for (final o in document.overlays)
              if (o.id == existing.id) updated else o,
          ],
        ),
      );
      _selectedId = updated.id;
      return updated;
    }
    if (!canAddOverlay) {
      return null;
    }
    final overlay = TextOverlay(
      id: _newId('text'),
      transform: const OverlayTransform(position: StoryCanvas.center),
      text: text,
      style: style,
    );
    _selectedId = overlay.id;
    _apply(document.copyWith(overlays: [...document.overlays, overlay]));
    return overlay;
  }

  /// Adds a host sticker at the canvas centre. Returns `false` when the
  /// overlay limit is reached.
  bool addSticker(String stickerId) {
    if (!canAddOverlay) {
      return false;
    }
    final overlay = StickerOverlay(
      id: _newId('sticker'),
      transform: const OverlayTransform(position: StoryCanvas.center),
      stickerId: stickerId,
    );
    _selectedId = overlay.id;
    _apply(document.copyWith(overlays: [...document.overlays, overlay]));
    return true;
  }

  /// Adds an emoji at the canvas centre. Returns `false` when the overlay
  /// limit is reached.
  bool addEmoji(String emoji) {
    if (!canAddOverlay) {
      return false;
    }
    final overlay = EmojiOverlay(
      id: _newId('emoji'),
      transform: const OverlayTransform(position: StoryCanvas.center),
      emoji: emoji,
    );
    _selectedId = overlay.id;
    _apply(document.copyWith(overlays: [...document.overlays, overlay]));
    return true;
  }

  /// Moves, scales or rotates the overlay with [id]. The scale is clamped
  /// and the centre is kept on the canvas.
  void transformOverlay(String id, OverlayTransform transform) {
    final overlay = overlayById(id);
    if (overlay == null) {
      return;
    }
    final clamped = OverlayTransform(
      position: Offset(
        transform.position.dx.clamp(0, StoryCanvas.width),
        transform.position.dy.clamp(0, StoryCanvas.height),
      ),
      scale: transform.scale.clamp(minOverlayScale, maxOverlayScale),
      rotation: transform.rotation,
    );
    _apply(
      document.copyWith(
        overlays: [
          for (final o in document.overlays)
            if (o.id == id) o.withTransform(clamped) else o,
        ],
      ),
    );
  }

  /// Removes the overlay with [id].
  void deleteOverlay(String id) {
    if (overlayById(id) == null) {
      return;
    }
    if (_selectedId == id) {
      _selectedId = null;
    }
    _apply(
      document.copyWith(
        overlays: [
          for (final o in document.overlays)
            if (o.id != id) o,
        ],
      ),
    );
  }

  /// Moves the overlay with [id] to the top.
  void bringToFront(String id) {
    final overlay = overlayById(id);
    if (overlay == null || document.overlays.last.id == id) {
      return;
    }
    _apply(
      document.copyWith(
        overlays: [
          for (final o in document.overlays)
            if (o.id != id) o,
          overlay,
        ],
      ),
    );
  }

  /// Appends a finished stroke.
  void addStroke(DrawingStroke stroke) {
    if (stroke.points.isEmpty) {
      return;
    }
    _apply(document.copyWith(strokes: [...document.strokes, stroke]));
  }

  /// Selects [filter]; identity filters clear the filter.
  void setFilter(StoryFilter filter) {
    _apply(
      filter.isIdentity
          ? document.copyWith(clearFilter: true)
          : document.copyWith(filterId: filter.id),
    );
  }

  /// Moves or scales the media.
  void setPlacement(MediaPlacement placement) {
    final scale = placement.scale.clamp(minMediaScale, maxMediaScale);
    const limit = Offset(StoryCanvas.width, StoryCanvas.height);
    _apply(
      document.copyWith(
        placement: MediaPlacement(
          scale: scale,
          offset: Offset(
            placement.offset.dx.clamp(-limit.dx, limit.dx),
            placement.offset.dy.clamp(-limit.dy, limit.dy),
          ),
        ),
      ),
    );
  }

  /// Sets the kept part of the video. A range covering the whole video
  /// (when it fits the maximum) is stored as "no trim". The music segment
  /// length follows the new length.
  void setTrim(TrimRange range, {Duration? videoDuration}) {
    final total = videoDuration ?? document.media.duration;
    final whole =
        total != null && range.start == Duration.zero && range.end >= total;
    final length = whole ? total : range.duration;
    final music = document.music;
    _apply(
      document.copyWith(
        trim: whole ? null : range,
        clearTrim: whole,
        music: music?.copyWith(duration: length),
      ),
    );
  }

  /// Sets the original audio volume (0–1).
  void setOriginalVolume(double volume) {
    _apply(document.copyWith(originalVolume: volume.clamp(0, 1)));
  }

  /// Sets or removes (`null`) the music.
  void setMusic(MusicSelection? music) {
    _apply(
      music == null
          ? document.copyWith(clearMusic: true)
          : document.copyWith(music: music),
    );
  }

  /// Sets the music volume (0–1).
  void setMusicVolume(double volume) {
    final music = document.music;
    if (music == null) {
      return;
    }
    _apply(
      document.copyWith(music: music.copyWith(volume: volume.clamp(0, 1))),
    );
  }

  /// Length the music must cover: the trimmed video, or [photoDuration]
  /// for photos (clamped to [maxDuration]).
  Duration musicSegmentLength({
    required Duration photoDuration,
    required Duration maxDuration,
  }) {
    if (document.media.isVideo) {
      final length = document.outputDuration ?? maxDuration;
      return length > maxDuration ? maxDuration : length;
    }
    return Duration(
      microseconds: math.min(
        photoDuration.inMicroseconds,
        maxDuration.inMicroseconds,
      ),
    );
  }

  @override
  void dispose() {
    _history
      ..removeListener(_onHistory)
      ..dispose();
    super.dispose();
  }
}
