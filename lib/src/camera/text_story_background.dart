import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../api/config/editor_options.dart';
import '../api/errors/story_exception.dart';
import '../api/theme/story_creator_theme.dart';
import '../core/story_canvas.dart';

/// The two colours of a text story's gradient: the text colours closest to
/// the theme's accent (top) and background (bottom). Falls back to the
/// theme colours when [options] has no text colours.
(Color, Color) textStoryColors(EditorOptions options, StoryCreatorTheme theme) {
  final colors = options.textColors;
  if (colors.isEmpty) {
    return (theme.accent, theme.background);
  }
  Color closest(Color target) {
    var best = colors.first;
    var bestDistance = double.infinity;
    for (final c in colors) {
      final dr = c.r - target.r;
      final dg = c.g - target.g;
      final db = c.b - target.b;
      final d = dr * dr + dg * dg + db * db;
      if (d < bestDistance) {
        best = c;
        bestDistance = d;
      }
    }
    return best;
  }

  return (closest(theme.accent), closest(theme.background));
}

/// Writes a PNG of the story canvas size filled with a vertical gradient
/// from [top] to [bottom] to [path].
///
/// Throws a [StoryException] with [StoryErrorCode.captureFailed] when the
/// image cannot be rendered or written.
Future<void> writeTextStoryBackground(
  String path, {
  required Color top,
  required Color bottom,
}) async {
  const size = StoryCanvas.size;
  final recorder = ui.PictureRecorder();
  Canvas(recorder, Offset.zero & size).drawRect(
    Offset.zero & size,
    Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), [
        top,
        bottom,
      ]),
  );
  final picture = recorder.endRecording();
  ui.Image? image;
  try {
    image = await picture.toImage(
      StoryCanvas.outputWidth,
      StoryCanvas.outputHeight,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw const StoryException(
        StoryErrorCode.captureFailed,
        'The text story background could not be encoded.',
      );
    }
    await File(path).writeAsBytes(data.buffer.asUint8List(), flush: true);
  } on StoryException {
    rethrow;
  } on Object catch (e, s) {
    throw StoryException(
      StoryErrorCode.captureFailed,
      'The text story background could not be created.',
      e,
      s,
    );
  } finally {
    image?.dispose();
    picture.dispose();
  }
}
