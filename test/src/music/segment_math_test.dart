import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/src/music/segment_math.dart';

void main() {
  const s = Duration(seconds: 1);

  MusicSegment clamp(int start, int length, int track) => clampMusicSegment(
    start: s * start,
    segmentLength: s * length,
    trackDuration: s * track,
  );

  group('clampMusicSegment', () {
    test('keeps a start that fits', () {
      expect(clamp(10, 15, 60), MusicSegment(start: s * 10, duration: s * 15));
    });

    test('clamps a negative start to zero', () {
      expect(
        clamp(-5, 15, 60),
        MusicSegment(start: Duration.zero, duration: s * 15),
      );
    });

    test('clamps the start so the segment ends at the track end', () {
      expect(clamp(50, 15, 60), MusicSegment(start: s * 45, duration: s * 15));
    });

    test('a segment as long as the track starts at zero', () {
      expect(
        clamp(3, 60, 60),
        MusicSegment(start: Duration.zero, duration: s * 60),
      );
    });

    test('a track shorter than the segment is used whole', () {
      expect(
        clamp(4, 15, 10),
        MusicSegment(start: Duration.zero, duration: s * 10),
      );
    });

    test('a non-positive segment length covers the whole track', () {
      expect(
        clamp(4, 0, 10),
        MusicSegment(start: Duration.zero, duration: s * 10),
      );
    });

    test('an unknown track length keeps the segment length from zero', () {
      expect(
        clamp(4, 15, 0),
        MusicSegment(start: Duration.zero, duration: s * 15),
      );
    });
  });

  group('helpers', () {
    test('fraction and position are inverse and clamped', () {
      expect(musicFractionOf(s * 30, s * 120), 0.25);
      expect(musicFractionOf(s * 300, s * 120), 1);
      expect(musicFractionOf(s * 3, Duration.zero), 0);
      expect(musicPositionAt(0.25, s * 120), s * 30);
      expect(musicPositionAt(-1, s * 120), Duration.zero);
      expect(musicPositionAt(2, s * 120), s * 120);
    });

    test('formatMusicTime prints m:ss', () {
      expect(formatMusicTime(Duration.zero), '0:00');
      expect(formatMusicTime(const Duration(seconds: 7)), '0:07');
      expect(formatMusicTime(const Duration(minutes: 3, seconds: 5)), '3:05');
      expect(
        formatMusicTime(const Duration(minutes: 12, milliseconds: 59990)),
        '12:59',
      );
      expect(formatMusicTime(-s), '0:00');
    });
  });
}
