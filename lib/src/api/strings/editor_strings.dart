import 'package:flutter/foundation.dart';

/// Editor strings: tools, text, drawing, stickers, filters, trim and audio.
///
/// Owned by the editor area; add fields here as that area needs them.
@immutable
class EditorStrings {
  /// Creates the editor strings. Defaults are English.
  const EditorStrings({
    this.text = 'Text',
    this.draw = 'Draw',
    this.stickers = 'Stickers',
    this.filters = 'Filters',
    this.music = 'Music',
    this.trim = 'Trim',
    this.audio = 'Audio',
    this.export = 'Share story',
    this.saveToGallery = 'Save',
    this.typeSomething = 'Type something…',
    this.font = 'Font',
    this.color = 'Colour',
    this.alignment = 'Alignment',
    this.alignLeft = 'Align left',
    this.alignCenter = 'Align centre',
    this.alignRight = 'Align right',
    this.textBackground = 'Text background',
    this.backgroundNone = 'No background',
    this.backgroundSolid = 'Solid background',
    this.backgroundTranslucent = 'Translucent background',
    this.backgroundHighlight = 'Highlight',
    this.pen = 'Pen',
    this.marker = 'Marker',
    this.neon = 'Neon',
    this.eraser = 'Eraser',
    this.brushSize = 'Brush size',
    this.undo = 'Undo',
    this.redo = 'Redo',
    this.delete = 'Delete',
    this.dragToDelete = 'Drag here to delete',
    this.emoji = 'Emoji',
    this.play = 'Play',
    this.pause = 'Pause',
    this.trimStart = 'Trim start',
    this.trimEnd = 'Trim end',
    this.originalAudio = 'Original audio',
    this.musicVolume = 'Music volume',
    this.mute = 'Mute',
    this.unmute = 'Unmute',
    this.adjust = 'Adjust',
    this.moveUp = 'Move up',
    this.moveDown = 'Move down',
    this.moveLeft = 'Move left',
    this.moveRight = 'Move right',
    this.enlarge = 'Enlarge',
    this.shrink = 'Shrink',
    this.rotateLeft = 'Rotate left',
    this.rotateRight = 'Rotate right',
    this.bringToFront = 'Bring to front',
    this.edit = 'Edit',
    this.textOverlay = 'Text',
    this.stickerOverlay = 'Sticker',
    this.maxOverlaysReached = 'You have reached the maximum number of items.',
    this.canvas = 'Story canvas',
    this.canvasHint = 'Tap to add text',
    this.emojiOverlay = 'Emoji',
    this.previousItem = 'Previous item',
    this.nextItem = 'Next item',
    this.colorSwatch = _defaultColorSwatch,
    this.trimLength = 'Selected length',
    this.fontUnavailable = 'This font could not be loaded.',
    this.stickerUnavailable = 'This sticker could not be loaded.',
    this.videoUnavailable = 'The video could not be played.',
    this.musicUnavailable = 'The music could not be played.',
  });

  static String _defaultColorSwatch(int number) => 'Colour $number';

  /// Text tool label.
  final String text;

  /// Drawing tool label.
  final String draw;

  /// Sticker tool label.
  final String stickers;

  /// Filter tool label.
  final String filters;

  /// Music tool label.
  final String music;

  /// Trim tool label.
  final String trim;

  /// Audio mix tool label.
  final String audio;

  /// Primary export action label.
  final String export;

  /// Save-to-gallery action label.
  final String saveToGallery;

  /// Placeholder in the text editor.
  final String typeSomething;

  /// Font selector label.
  final String font;

  /// Colour palette label.
  final String color;

  /// Alignment toggle label.
  final String alignment;

  /// Left alignment label.
  final String alignLeft;

  /// Centre alignment label.
  final String alignCenter;

  /// Right alignment label.
  final String alignRight;

  /// Text background toggle label.
  final String textBackground;

  /// Background style: none.
  final String backgroundNone;

  /// Background style: solid.
  final String backgroundSolid;

  /// Background style: translucent.
  final String backgroundTranslucent;

  /// Background style: per-line rounded highlight.
  final String backgroundHighlight;

  /// Pen brush label.
  final String pen;

  /// Marker brush label.
  final String marker;

  /// Neon brush label.
  final String neon;

  /// Eraser label.
  final String eraser;

  /// Brush size slider label.
  final String brushSize;

  /// Undo label.
  final String undo;

  /// Redo label.
  final String redo;

  /// Delete label.
  final String delete;

  /// Trash zone hint.
  final String dragToDelete;

  /// Emoji tab label.
  final String emoji;

  /// Play label.
  final String play;

  /// Pause label.
  final String pause;

  /// Trim start handle label.
  final String trimStart;

  /// Trim end handle label.
  final String trimEnd;

  /// Original audio volume label.
  final String originalAudio;

  /// Music volume label.
  final String musicVolume;

  /// Mute label.
  final String mute;

  /// Unmute label.
  final String unmute;

  /// Accessible adjust panel label.
  final String adjust;

  /// Accessibility action: move up.
  final String moveUp;

  /// Accessibility action: move down.
  final String moveDown;

  /// Accessibility action: move left.
  final String moveLeft;

  /// Accessibility action: move right.
  final String moveRight;

  /// Accessibility action: enlarge.
  final String enlarge;

  /// Accessibility action: shrink.
  final String shrink;

  /// Accessibility action: rotate left.
  final String rotateLeft;

  /// Accessibility action: rotate right.
  final String rotateRight;

  /// Accessibility action: bring to front.
  final String bringToFront;

  /// Accessibility action: edit.
  final String edit;

  /// Semantics label of a text overlay.
  final String textOverlay;

  /// Semantics label of a sticker overlay.
  final String stickerOverlay;

  /// Notice when `EditorOptions.maxOverlays` is reached.
  final String maxOverlaysReached;

  /// Semantics label of the story canvas.
  final String canvas;

  /// Semantics hint of the story canvas.
  final String canvasHint;

  /// Semantics label of an emoji overlay (followed by the emoji).
  final String emojiOverlay;

  /// Adjust panel: select the previous overlay.
  final String previousItem;

  /// Adjust panel: select the next overlay.
  final String nextItem;

  /// Semantics label of the colour swatch with the 1-based [number].
  final String Function(int number) colorSwatch;

  /// Semantics label of the trimmed length readout.
  final String trimLength;

  /// Notice when a font loader fails.
  final String fontUnavailable;

  /// Notice when a sticker image cannot be decoded.
  final String stickerUnavailable;

  /// Notice when the video cannot be played in the editor.
  final String videoUnavailable;

  /// Notice when the selected music cannot be played in the editor.
  final String musicUnavailable;
}
