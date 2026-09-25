// Test-only helpers: synthetic media and pixel reading.
// ignore_for_file: implementation_imports

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// Copies a bundled fixture (integration_test/assets/[name]) into [dir].
Future<String> copyFixture(String name, Directory dir) async {
  final data = await rootBundle.load('integration_test/assets/$name');
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
  return file.path;
}

/// A [width]×[height] PNG with quadrants red / green / blue / white.
Future<String> writeQuadrantPng(
  Directory dir, {
  int width = 1080,
  int height = 1440,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final w = width / 2;
  final h = height / 2;
  void fill(double x, double y, int color) => canvas.drawRect(
    ui.Rect.fromLTWH(x, y, w, h),
    ui.Paint()..color = ui.Color(color),
  );
  fill(0, 0, 0xFFFF0000);
  fill(w, 0, 0xFF00FF00);
  fill(0, h, 0xFF0000FF);
  fill(w, h, 0xFFFFFFFF);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  final file = File('${dir.path}/quadrants_${width}x$height.png');
  await file.writeAsBytes(png!.buffer.asUint8List(), flush: true);
  return file.path;
}

/// A 16-bit PCM WAV: a 440 Hz sine, loud (0.8) for the first half and quiet
/// (0.05) for the second half.
Future<String> writeToneWav(
  Directory dir, {
  required String name,
  Duration duration = const Duration(seconds: 4),
  int sampleRate = 44100,
  int channels = 2,
}) async {
  final frames = (duration.inMicroseconds * sampleRate / 1e6).round();
  final dataBytes = frames * channels * 2;
  final bytes = ByteData(44 + dataBytes);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, channels, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * channels * 2, Endian.little)
    ..setUint16(32, channels * 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, dataBytes, Endian.little);
  var offset = 44;
  for (var i = 0; i < frames; i++) {
    final amplitude = i < frames / 2 ? 0.8 : 0.05;
    final v = (math.sin(2 * math.pi * 440 * i / sampleRate) * amplitude * 32767)
        .round();
    for (var c = 0; c < channels; c++) {
      bytes.setInt16(offset, v, Endian.little);
      offset += 2;
    }
  }
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file.path;
}

/// Decoded RGBA pixels of an image file.
class Pixels {
  Pixels._(this.width, this.height, this._rgba);

  /// Decodes [path] (JPEG/PNG).
  static Future<Pixels> read(String path) async {
    final codec = await ui.instantiateImageCodec(
      await File(path).readAsBytes(),
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final pixels = Pixels._(image.width, image.height, data!);
    image.dispose();
    codec.dispose();
    return pixels;
  }

  final int width;
  final int height;
  final ByteData _rgba;

  /// Average colour of a 9×9 block around ([x], [y]) as (r, g, b).
  (int, int, int) at(int x, int y) {
    var r = 0;
    var g = 0;
    var b = 0;
    var n = 0;
    for (var dy = -4; dy <= 4; dy++) {
      for (var dx = -4; dx <= 4; dx++) {
        final px = (x + dx).clamp(0, width - 1);
        final py = (y + dy).clamp(0, height - 1);
        final o = (py * width + px) * 4;
        r += _rgba.getUint8(o);
        g += _rgba.getUint8(o + 1);
        b += _rgba.getUint8(o + 2);
        n++;
      }
    }
    return (r ~/ n, g ~/ n, b ~/ n);
  }
}

/// Whether [actual] is within [tolerance] of [expected] on every channel.
bool colorClose(
  (int, int, int) actual,
  (int, int, int) expected,
  int tolerance,
) =>
    (actual.$1 - expected.$1).abs() <= tolerance &&
    (actual.$2 - expected.$2).abs() <= tolerance &&
    (actual.$3 - expected.$3).abs() <= tolerance;
