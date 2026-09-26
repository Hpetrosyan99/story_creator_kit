import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/src/music/waveform_painter.dart';

void main() {
  group('MusicWaveformPainter layout', () {
    test('bars alternate 3 px and 2 px with 5 px gaps', () {
      expect(MusicWaveformPainter.barLeft(0), 0);
      expect(MusicWaveformPainter.barLeft(1), 8);
      expect(MusicWaveformPainter.barLeft(2), 15);
      expect(MusicWaveformPainter.barLeft(3), 23);
    });

    test('counts only whole bars on the track', () {
      expect(MusicWaveformPainter.barCount(0), 0);
      expect(MusicWaveformPainter.barCount(3), 1);
      expect(MusicWaveformPainter.barCount(9), 1);
      expect(MusicWaveformPainter.barCount(10), 2);
      expect(MusicWaveformPainter.barCount(18), 3);
      expect(MusicWaveformPainter.barCount(120), 16);
    });

    test('repaints when the track scrolls', () {
      const a = MusicWaveformPainter(
        peaks: [0.5],
        originX: 0,
        trackWidth: 100,
        color: Color(0xFFFFFFFF),
      );
      const b = MusicWaveformPainter(
        peaks: [0.5],
        originX: -10,
        trackWidth: 100,
        color: Color(0xFFFFFFFF),
      );
      expect(b.shouldRepaint(a), isTrue);
      expect(a.shouldRepaint(a), isFalse);
    });
  });
}
