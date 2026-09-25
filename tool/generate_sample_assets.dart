// Generates the example app's sample music and stickers.
//
// Everything is synthesised or drawn by this script, so the outputs carry no
// third-party rights (see example/assets/ASSETS_LICENSE.md).
//
// Usage, from the repository root:
//
//   dart run tool/generate_sample_assets.dart            # music + stickers
//   dart run tool/generate_sample_assets.dart music      # music only
//   dart run tool/generate_sample_assets.dart stickers   # stickers only
//
// Music is rendered to 44.1 kHz stereo WAV and encoded to AAC (.m4a) with
// macOS `afconvert` (or `ffmpeg` when afconvert is missing). Stickers are
// 512×512 transparent PNGs written by a small anti-aliased SDF rasteriser
// and PNG encoder below; no packages are needed.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _musicDir = 'example/assets/music';
const _stickerDir = 'example/assets/stickers';

Future<void> main(List<String> args) async {
  if (!File('pubspec.yaml').existsSync() ||
      !Directory('example').existsSync()) {
    stderr.writeln('Run this from the repository root.');
    exitCode = 64;
    return;
  }
  final all = args.isEmpty;
  if (all || args.contains('music')) {
    await _generateMusic();
  }
  if (all || args.contains('stickers')) {
    _generateStickers();
    _generateArtwork();
  }
}

// ---------------------------------------------------------------------------
// Music
// ---------------------------------------------------------------------------

const int _rate = 44100;

Future<void> _generateMusic() async {
  final out = Directory(_musicDir)..createSync(recursive: true);
  final work = Directory.systemTemp.createTempSync('story_music_');
  try {
    for (final spec in _tracks) {
      final watch = Stopwatch()..start();
      final mix = _Mix(spec.bars * 4 * 60 / spec.bpm + 2.5);
      _renderTrack(spec, mix);
      final wav = File('${work.path}/${spec.file}.wav');
      mix.writeWav(wav);
      final m4a = File('${out.path}/${spec.file}.m4a');
      await _encodeAac(wav, m4a);
      stdout.writeln(
        '${m4a.path}: ${spec.title}, ${spec.bpm} BPM, '
        '${mix.seconds.toStringAsFixed(1)} s, '
        '${(m4a.lengthSync() / 1024).round()} KiB '
        '(${watch.elapsedMilliseconds} ms)',
      );
    }
  } finally {
    work.deleteSync(recursive: true);
  }
}

Future<void> _encodeAac(File wav, File m4a) async {
  if (m4a.existsSync()) {
    m4a.deleteSync();
  }
  ProcessResult result;
  try {
    result = await Process.run('afconvert', [
      '-f',
      'm4af',
      '-d',
      'aac',
      '-b',
      '128000',
      wav.path,
      m4a.path,
    ]);
  } on ProcessException {
    result = await Process.run('ffmpeg', [
      '-y',
      '-loglevel',
      'error',
      '-i',
      wav.path,
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      m4a.path,
    ]);
  }
  if (result.exitCode != 0 || !m4a.existsSync()) {
    throw StateError('AAC encoding failed: ${result.stderr}');
  }
}

/// A section of a song: which parts play and how loud.
class _Section {
  const _Section(
    this.bars, {
    required this.gain,
    this.pad = false,
    this.bass = false,
    this.drums = 0,
    this.arp = false,
    this.lead = false,
    this.pluck = false,
  });

  final int bars;
  final double gain;
  final bool pad;
  final bool bass;

  /// 0 none, 1 light, 2 full.
  final int drums;
  final bool arp;
  final bool lead;
  final bool pluck;
}

enum _Groove { rock, halfTime, fourOnFloor, folk }

class _TrackSpec {
  const _TrackSpec({
    required this.file,
    required this.title,
    required this.bpm,
    required this.seed,
    required this.chords,
    required this.roots,
    required this.sections,
    required this.groove,
    this.padWave = _Wave.triangle,
    this.padCutoff = 1800,
  });

  final String file;
  final String title;
  final int bpm;
  final int seed;

  /// MIDI notes of each chord, one chord per bar, cycling.
  final List<List<int>> chords;

  /// Bass root (MIDI) per chord.
  final List<int> roots;
  final List<_Section> sections;
  final _Groove groove;
  final _Wave padWave;
  final double padCutoff;

  int get bars => sections.fold(0, (sum, s) => sum + s.bars);
}

const _tracks = [
  _TrackSpec(
    file: 'sunrise_drive',
    title: 'Sunrise Drive',
    bpm: 112,
    seed: 11,
    groove: _Groove.rock,
    padWave: _Wave.saw,
    chords: [
      [60, 64, 67],
      [55, 59, 62],
      [57, 60, 64],
      [53, 57, 60],
    ],
    roots: [36, 43, 45, 41],
    sections: [
      _Section(4, gain: 0.28, pad: true),
      _Section(8, gain: 0.6, pad: true, bass: true, drums: 1),
      _Section(8, gain: 1, pad: true, bass: true, drums: 2, arp: true),
      _Section(4, gain: 0.22, pad: true),
      _Section(6, gain: 1, pad: true, bass: true, drums: 2, arp: true),
    ],
  ),
  _TrackSpec(
    file: 'slow_coffee',
    title: 'Slow Coffee',
    bpm: 84,
    seed: 23,
    groove: _Groove.halfTime,
    padCutoff: 1100,
    chords: [
      [57, 60, 64],
      [53, 57, 60],
      [55, 60, 64],
      [55, 59, 62],
    ],
    roots: [45, 41, 48, 43],
    sections: [
      _Section(4, gain: 0.3, pad: true, pluck: true),
      _Section(8, gain: 0.65, pad: true, bass: true, drums: 1),
      _Section(6, gain: 0.95, pad: true, bass: true, drums: 2, lead: true),
      _Section(8, gain: 0.3, pad: true, pluck: true),
    ],
  ),
  _TrackSpec(
    file: 'midnight_pulse',
    title: 'Midnight Pulse',
    bpm: 128,
    seed: 37,
    groove: _Groove.fourOnFloor,
    padWave: _Wave.saw,
    padCutoff: 1400,
    chords: [
      [53, 56, 60],
      [49, 53, 56],
      [51, 56, 60],
      [51, 55, 58],
    ],
    roots: [41, 37, 44, 39],
    sections: [
      _Section(4, gain: 0.35, arp: true),
      _Section(4, gain: 0.55, arp: true, drums: 1),
      _Section(8, gain: 1, pad: true, bass: true, drums: 2, arp: true),
      _Section(4, gain: 0.25, pad: true),
      _Section(8, gain: 1, pad: true, bass: true, drums: 2, arp: true),
      _Section(4, gain: 0.3, arp: true),
    ],
  ),
  _TrackSpec(
    file: 'paper_planes',
    title: 'Paper Planes',
    bpm: 96,
    seed: 41,
    groove: _Groove.folk,
    padCutoff: 1300,
    chords: [
      [62, 66, 69],
      [59, 62, 66],
      [55, 59, 62],
      [57, 61, 64],
    ],
    roots: [38, 47, 43, 45],
    sections: [
      _Section(4, gain: 0.3, pluck: true),
      _Section(8, gain: 0.55, pluck: true, bass: true, drums: 1),
      _Section(8, gain: 0.9, pluck: true, pad: true, bass: true, drums: 2),
      _Section(4, gain: 0.2, pad: true),
      _Section(8, gain: 1, pluck: true, pad: true, bass: true, drums: 2),
      _Section(2, gain: 0.3, pluck: true),
    ],
  ),
];

void _renderTrack(_TrackSpec spec, _Mix mix) {
  final rng = math.Random(spec.seed);
  final beat = 60 / spec.bpm;
  final bar = beat * 4;
  var barIndex = 0;
  for (final section in spec.sections) {
    for (var b = 0; b < section.bars; b++, barIndex++) {
      final t0 = barIndex * bar;
      final chord = spec.chords[barIndex % spec.chords.length];
      final root = spec.roots[barIndex % spec.roots.length];
      final g = section.gain;
      if (section.pad) {
        mix.pad(chord, t0, bar, 0.16 * g, spec.padWave, spec.padCutoff);
      }
      if (section.bass) {
        _bassLine(mix, spec.groove, root, t0, beat, 0.5 * g);
      }
      if (section.drums > 0) {
        _drums(mix, spec.groove, section.drums, t0, beat, g, rng);
      }
      if (section.arp) {
        for (var i = 0; i < 16; i++) {
          final note = chord[i % chord.length] + 12 * ((i ~/ 3).isEven ? 1 : 0);
          mix.arp(
            note,
            t0 + i * beat / 4,
            beat / 4,
            0.1 * g,
            pan: i.isEven ? -0.3 : 0.3,
          );
        }
      }
      if (section.lead) {
        const pattern = [2, 1, 0, 1, 2, 2, 1, 0];
        for (var i = 0; i < 4; i++) {
          final step = pattern[(barIndex * 4 + i) % pattern.length];
          mix.lead(chord[step] + 12, t0 + i * beat, beat * 0.9, 0.16 * g);
        }
      }
      if (section.pluck) {
        for (var i = 0; i < 8; i++) {
          final note = chord[(i * 2) % chord.length] + (i >= 4 ? 12 : 0);
          final swing = i.isOdd ? beat * 0.06 : 0.0;
          mix.pluck(
            note,
            t0 + i * beat / 2 + swing,
            0.22 * g,
            rng,
            pan: i.isEven ? -0.4 : 0.4,
          );
        }
      }
    }
  }
  mix.finish(fadeIn: 0.4, fadeOut: 2.5);
}

void _bassLine(
  _Mix mix,
  _Groove groove,
  int root,
  double t0,
  double beat,
  double gain,
) {
  switch (groove) {
    case _Groove.rock:
      for (var i = 0; i < 8; i++) {
        mix.bass(root + (i == 7 ? 7 : 0), t0 + i * beat / 2, beat * 0.45, gain);
      }
    case _Groove.halfTime:
      mix
        ..bass(root, t0, beat * 1.8, gain)
        ..bass(root, t0 + beat * 2.5, beat * 0.4, gain * 0.8)
        ..bass(root + 7, t0 + beat * 3, beat * 0.9, gain * 0.9);
    case _Groove.fourOnFloor:
      for (var i = 0; i < 4; i++) {
        mix.bass(root, t0 + i * beat + beat / 2, beat * 0.45, gain);
      }
    case _Groove.folk:
      mix
        ..bass(root, t0, beat * 0.9, gain)
        ..bass(root + 7, t0 + beat, beat * 0.9, gain * 0.8)
        ..bass(root, t0 + beat * 2, beat * 0.9, gain)
        ..bass(root + 4, t0 + beat * 3, beat * 0.9, gain * 0.8);
  }
}

void _drums(
  _Mix mix,
  _Groove groove,
  int level,
  double t0,
  double beat,
  double gain,
  math.Random rng,
) {
  final full = level >= 2;
  switch (groove) {
    case _Groove.rock:
      mix
        ..kick(t0, 0.9 * gain)
        ..kick(t0 + beat * 2, 0.9 * gain);
      if (full) {
        mix
          ..kick(t0 + beat * 2.5, 0.6 * gain)
          ..snare(t0 + beat, 0.5 * gain, rng)
          ..snare(t0 + beat * 3, 0.5 * gain, rng);
      }
      for (var i = 0; i < (full ? 8 : 4); i++) {
        mix.hat(t0 + i * beat * (full ? 0.5 : 1), 0.16 * gain, rng);
      }
    case _Groove.halfTime:
      mix.kick(t0, 0.9 * gain);
      if (full) {
        mix
          ..kick(t0 + beat * 1.75, 0.5 * gain)
          ..snare(t0 + beat * 2, 0.55 * gain, rng);
      }
      for (var i = 0; i < 8; i++) {
        final swing = i.isOdd ? beat * 0.12 : 0.0;
        mix.hat(
          t0 + i * beat / 2 + swing,
          (i.isEven ? 0.14 : 0.08) * gain,
          rng,
        );
      }
    case _Groove.fourOnFloor:
      for (var i = 0; i < 4; i++) {
        mix
          ..kick(t0 + i * beat, 0.95 * gain)
          ..hat(t0 + i * beat + beat / 2, 0.2 * gain, rng, open: true);
      }
      if (full) {
        mix
          ..snare(t0 + beat, 0.45 * gain, rng)
          ..snare(t0 + beat * 3, 0.45 * gain, rng);
        for (var i = 0; i < 16; i++) {
          mix.hat(t0 + i * beat / 4, 0.06 * gain, rng);
        }
      }
    case _Groove.folk:
      mix
        ..kick(t0, 0.7 * gain)
        ..kick(t0 + beat * 2, 0.7 * gain);
      if (full) {
        mix
          ..snare(t0 + beat, 0.35 * gain, rng)
          ..snare(t0 + beat * 3, 0.35 * gain, rng);
      }
      for (var i = 0; i < 4; i++) {
        mix.hat(t0 + i * beat, 0.1 * gain, rng);
      }
  }
}

enum _Wave { triangle, saw }

double _freq(num midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();

/// A stereo mix buffer with a few simple instruments.
class _Mix {
  _Mix(double seconds)
    : left = Float64List((seconds * _rate).ceil()),
      right = Float64List((seconds * _rate).ceil());

  final Float64List left;
  final Float64List right;

  double get seconds => left.length / _rate;

  void _add(int i, double v, double pan) {
    if (i < 0 || i >= left.length) {
      return;
    }
    final angle = (pan + 1) * math.pi / 4;
    left[i] += v * math.cos(angle);
    right[i] += v * math.sin(angle);
  }

  /// Sustained chord with slow attack, two detuned voices per note.
  void pad(
    List<int> notes,
    double start,
    double length,
    double gain,
    _Wave wave,
    double cutoff,
  ) {
    const attack = 0.35;
    const release = 0.5;
    final n = ((length + release) * _rate).round();
    final s0 = (start * _rate).round();
    final a = 1 - math.exp(-2 * math.pi * cutoff / _rate);
    for (final note in notes) {
      for (final detune in const [-0.07, 0.07]) {
        final f = _freq(note + detune);
        var phase = 0.0;
        var lp = 0.0;
        final pan = detune < 0 ? -0.55 : 0.55;
        for (var i = 0; i < n; i++) {
          final t = i / _rate;
          phase += f / _rate;
          phase -= phase.floorToDouble();
          final osc = wave == _Wave.saw
              ? 2 * phase - 1
              : 4 * (phase - 0.5).abs() - 1;
          lp += a * (osc - lp);
          final env = t < attack
              ? t / attack
              : t < length
              ? 1.0
              : math.max(0, 1 - (t - length) / release).toDouble();
          _add(s0 + i, lp * env * gain / notes.length, pan);
        }
      }
    }
  }

  void bass(int note, double start, double length, double gain) {
    final f = _freq(note);
    final n = ((length + 0.05) * _rate).round();
    final s0 = (start * _rate).round();
    for (var i = 0; i < n; i++) {
      final t = i / _rate;
      final x = 2 * math.pi * f * t;
      final raw = math.sin(x) + 0.35 * math.sin(2 * x) + 0.12 * math.sin(3 * x);
      final env =
          math.min(1, t / 0.006) *
          (t < length
              ? 0.75 + 0.25 * math.exp(-t * 6)
              : math.max(0, 1 - (t - length) / 0.05));
      _add(s0 + i, _tanh(raw * 1.3) * env * gain, 0);
    }
  }

  void kick(double start, double gain) {
    final n = (0.4 * _rate).round();
    final s0 = (start * _rate).round();
    var phase = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / _rate;
      final f = 48 + 120 * math.exp(-t * 32);
      phase += 2 * math.pi * f / _rate;
      final v = math.sin(phase) * math.exp(-t * 7.5) + (t < 0.003 ? 0.4 : 0);
      _add(s0 + i, v * gain, 0);
    }
  }

  void snare(double start, double gain, math.Random rng) {
    final n = (0.22 * _rate).round();
    final s0 = (start * _rate).round();
    var lp = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / _rate;
      final noise = rng.nextDouble() * 2 - 1;
      lp += 0.25 * (noise - lp);
      final hp = noise - lp;
      final tone = math.sin(2 * math.pi * 185 * t) * math.exp(-t * 35);
      final v = hp * math.exp(-t * 18) * 0.9 + tone * 0.5;
      _add(s0 + i, v * gain, 0.1);
    }
  }

  void hat(double start, double gain, math.Random rng, {bool open = false}) {
    final n = ((open ? 0.25 : 0.06) * _rate).round();
    final decay = open ? 14.0 : 70.0;
    final s0 = (start * _rate).round();
    var prev = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / _rate;
      final noise = rng.nextDouble() * 2 - 1;
      final hp = noise - prev;
      prev = noise;
      _add(s0 + i, hp * 0.5 * math.exp(-t * decay) * gain, 0.35);
    }
  }

  void arp(
    int note,
    double start,
    double length,
    double gain, {
    double pan = 0,
  }) {
    final f = _freq(note);
    final n = ((length * 1.8) * _rate).round();
    final s0 = (start * _rate).round();
    var phase = 0.0;
    var lp = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / _rate;
      phase += f / _rate;
      phase -= phase.floorToDouble();
      final osc = phase < 0.3 ? 1.0 : -1.0;
      lp += 0.18 * (osc - lp);
      final env = math.min(1, t / 0.004) * math.exp(-t * 9);
      _add(s0 + i, lp * env * gain, pan);
    }
  }

  void lead(int note, double start, double length, double gain) {
    final f = _freq(note);
    final n = ((length + 0.15) * _rate).round();
    final s0 = (start * _rate).round();
    var phase = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / _rate;
      final vibrato =
          1 + 0.004 * math.sin(2 * math.pi * 5.5 * t) * math.min(1, t * 3);
      phase += f * vibrato / _rate;
      phase -= phase.floorToDouble();
      final osc = 4 * (phase - 0.5).abs() - 1;
      final env =
          math.min(1, t / 0.03) *
          (t < length ? 1 : math.max(0, 1 - (t - length) / 0.15));
      _add(s0 + i, osc * env * gain, -0.15);
    }
  }

  /// Karplus–Strong plucked string.
  void pluck(
    int note,
    double start,
    double gain,
    math.Random rng, {
    double pan = 0,
  }) {
    final period = (_rate / _freq(note)).round();
    final buffer = Float64List(period);
    for (var i = 0; i < period; i++) {
      buffer[i] = rng.nextDouble() * 2 - 1;
    }
    final n = (1.4 * _rate).round();
    final s0 = (start * _rate).round();
    var idx = 0;
    for (var i = 0; i < n; i++) {
      final next = (idx + 1) % period;
      final v = buffer[idx];
      buffer[idx] = 0.996 * 0.5 * (buffer[idx] + buffer[next]);
      idx = next;
      _add(s0 + i, v * gain, pan);
    }
  }

  /// Fades, soft-clips and normalises to -1 dBFS peak.
  void finish({required double fadeIn, required double fadeOut}) {
    final n = left.length;
    final inN = (fadeIn * _rate).round();
    final outN = (fadeOut * _rate).round();
    var peak = 1e-9;
    for (var i = 0; i < n; i++) {
      var g = 1.0;
      if (i < inN) {
        g = i / inN;
      }
      if (i > n - outN) {
        g *= (n - i) / outN;
      }
      left[i] *= g;
      right[i] *= g;
      peak = math.max(peak, math.max(left[i].abs(), right[i].abs()));
    }
    const drive = 1.4;
    final target = math.pow(10, -1 / 20).toDouble();
    final norm = _tanh(drive);
    for (var i = 0; i < n; i++) {
      left[i] = _tanh(left[i] / peak * drive) / norm * target;
      right[i] = _tanh(right[i] / peak * drive) / norm * target;
    }
  }

  void writeWav(File file) {
    final n = left.length;
    final data = ByteData(44 + n * 4)
      ..setUint32(0, 0x52494646) // RIFF
      ..setUint32(4, 36 + n * 4, Endian.little)
      ..setUint32(8, 0x57415645) // WAVE
      ..setUint32(12, 0x666d7420) // fmt
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little) // PCM
      ..setUint16(22, 2, Endian.little) // stereo
      ..setUint32(24, _rate, Endian.little)
      ..setUint32(28, _rate * 4, Endian.little)
      ..setUint16(32, 4, Endian.little)
      ..setUint16(34, 16, Endian.little)
      ..setUint32(36, 0x64617461) // data
      ..setUint32(40, n * 4, Endian.little);
    for (var i = 0; i < n; i++) {
      data
        ..setInt16(
          44 + i * 4,
          (left[i].clamp(-1, 1) * 32767).round(),
          Endian.little,
        )
        ..setInt16(
          46 + i * 4,
          (right[i].clamp(-1, 1) * 32767).round(),
          Endian.little,
        );
    }
    file.writeAsBytesSync(data.buffer.asUint8List());
  }
}

double _tanh(double x) {
  if (x > 20) {
    return 1;
  }
  if (x < -20) {
    return -1;
  }
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}

// ---------------------------------------------------------------------------
// Stickers
// ---------------------------------------------------------------------------

const int _size = 512;

/// Signed distance in pixels: negative inside, positive outside.
typedef _Sdf = double Function(double x, double y);

/// Straight (non-premultiplied) RGBA colour, components 0–1.
class _Rgba {
  const _Rgba(this.r, this.g, this.b, [this.a = 1]);

  factory _Rgba.hex(int argb) => _Rgba(
    ((argb >> 16) & 0xFF) / 255,
    ((argb >> 8) & 0xFF) / 255,
    (argb & 0xFF) / 255,
    ((argb >> 24) & 0xFF) / 255,
  );

  final double r;
  final double g;
  final double b;
  final double a;

  _Rgba lerp(_Rgba o, double t) => _Rgba(
    r + (o.r - r) * t,
    g + (o.g - g) * t,
    b + (o.b - b) * t,
    a + (o.a - a) * t,
  );
}

typedef _Paint = _Rgba Function(double x, double y);

_Paint _solid(int argb) {
  final c = _Rgba.hex(argb);
  return (_, _) => c;
}

_Paint _vertical(int top, int bottom, double y0, double y1) {
  final a = _Rgba.hex(top);
  final b = _Rgba.hex(bottom);
  return (_, y) => a.lerp(b, ((y - y0) / (y1 - y0)).clamp(0, 1).toDouble());
}

/// Premultiplied RGBA canvas.
class _Canvas {
  final Float64List _px = Float64List(_size * _size * 4);

  /// Draws [sdf] grown by [expand] px, edge softened over [soften] px.
  void fill(
    _Sdf sdf,
    _Paint paint, {
    double expand = 0,
    double soften = 1,
    double dx = 0,
    double dy = 0,
    double opacity = 1,
  }) {
    for (var y = 0; y < _size; y++) {
      for (var x = 0; x < _size; x++) {
        final px = x + 0.5 - dx;
        final py = y + 0.5 - dy;
        final d = sdf(px, py) - expand;
        final coverage = (0.5 - d / soften).clamp(0.0, 1.0);
        if (coverage <= 0) {
          continue;
        }
        final c = paint(px, py);
        final a = c.a * coverage * opacity;
        final i = (y * _size + x) * 4;
        final keep = 1 - a;
        _px[i] = c.r * a + _px[i] * keep;
        _px[i + 1] = c.g * a + _px[i + 1] * keep;
        _px[i + 2] = c.b * a + _px[i + 2] * keep;
        _px[i + 3] = a + _px[i + 3] * keep;
      }
    }
  }

  /// Sticker look: soft shadow, white die-cut border, then the fill.
  void sticker(_Sdf shape, _Paint paint, {double border = 16}) {
    final cached = _cache(shape);
    this
      ..fill(
        cached,
        _solid(0xFF000000),
        expand: border,
        soften: 18,
        dy: 9,
        opacity: 0.28,
      )
      ..fill(cached, _solid(0xFFFFFFFF), expand: border)
      ..fill(cached, paint);
  }

  Uint8List toRgba8() {
    final out = Uint8List(_size * _size * 4);
    for (var i = 0; i < _px.length; i += 4) {
      final a = _px[i + 3];
      if (a <= 0) {
        continue;
      }
      out[i] = (_px[i] / a * 255).round().clamp(0, 255);
      out[i + 1] = (_px[i + 1] / a * 255).round().clamp(0, 255);
      out[i + 2] = (_px[i + 2] / a * 255).round().clamp(0, 255);
      out[i + 3] = (a * 255).round().clamp(0, 255);
    }
    return out;
  }
}

/// Samples [sdf] once per pixel centre and interpolates bilinearly, so
/// expensive polygon SDFs are evaluated once for all layers.
_Sdf _cache(_Sdf sdf) {
  const n = _size + 1;
  final grid = Float64List(n * n);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      grid[y * n + x] = sdf(x - 0.0, y - 0.0);
    }
  }
  return (x, y) {
    final cx = x.clamp(0.0, _size - 1e-6);
    final cy = y.clamp(0.0, _size - 1e-6);
    final ix = cx.floor();
    final iy = cy.floor();
    final fx = cx - ix;
    final fy = cy - iy;
    final a = grid[iy * n + ix];
    final b = grid[iy * n + ix + 1];
    final c = grid[(iy + 1) * n + ix];
    final d = grid[(iy + 1) * n + ix + 1];
    final v = (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy;
    // Outside the grid, keep growing so shadows fade out.
    return v + (x - cx).abs() + (y - cy).abs();
  };
}

_Sdf _circle(double cx, double cy, double r) =>
    (x, y) => math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) - r;

_Sdf _roundBox(double cx, double cy, double hw, double hh, double r) => (x, y) {
  final qx = (x - cx).abs() - hw + r;
  final qy = (y - cy).abs() - hh + r;
  final ox = math.max<double>(qx, 0);
  final oy = math.max<double>(qy, 0);
  return math.sqrt(ox * ox + oy * oy) + math.min(math.max(qx, qy), 0) - r;
};

double _segment(
  double x,
  double y,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final pax = x - ax;
  final pay = y - ay;
  final bax = bx - ax;
  final bay = by - ay;
  final h = ((pax * bax + pay * bay) / (bax * bax + bay * bay)).clamp(0.0, 1.0);
  final dx = pax - bax * h;
  final dy = pay - bay * h;
  return math.sqrt(dx * dx + dy * dy);
}

/// A stroked polyline of half-width [half].
_Sdf _stroke(List<math.Point<double>> pts, double half) => (x, y) {
  var d = double.infinity;
  for (var i = 0; i + 1 < pts.length; i++) {
    d = math.min(
      d,
      _segment(x, y, pts[i].x, pts[i].y, pts[i + 1].x, pts[i + 1].y),
    );
  }
  return d - half;
};

/// Exact SDF of a closed polygon (even-odd sign).
_Sdf _polygon(List<math.Point<double>> pts) => (x, y) {
  var d = double.infinity;
  var inside = false;
  for (var i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    final a = pts[j];
    final b = pts[i];
    d = math.min(d, _segment(x, y, a.x, a.y, b.x, b.y));
    if ((b.y > y) != (a.y > y) &&
        x < (a.x - b.x) * (y - b.y) / (a.y - b.y) + b.x) {
      inside = !inside;
    }
  }
  return inside ? -d : d;
};

_Sdf _union(List<_Sdf> parts) => (x, y) {
  var d = double.infinity;
  for (final p in parts) {
    d = math.min(d, p(x, y));
  }
  return d;
};

_Sdf _round(_Sdf sdf, double r) =>
    (x, y) => sdf(x, y) - r;

math.Point<double> _p(double x, double y) => math.Point(x, y);

List<math.Point<double>> _curve(
  int steps,
  math.Point<double> Function(double t) at,
) => [for (var i = 0; i < steps; i++) at(2 * math.pi * i / steps)];

void _generateStickers() {
  final out = Directory(_stickerDir)..createSync(recursive: true);
  final stickers = <String, void Function(_Canvas)>{
    'star': _star,
    'heart': _heart,
    'sun': _sun,
    'wow': _wow,
    'lightning': _lightning,
    'crown': _crown,
    'sparkle': _sparkle,
    'flame': _flame,
  };
  for (final entry in stickers.entries) {
    final canvas = _Canvas();
    entry.value(canvas);
    final file = File('${out.path}/${entry.key}.png')
      ..writeAsBytesSync(_encodePng(_size, _size, canvas.toRgba8()));
    stdout.writeln('${file.path}: ${(file.lengthSync() / 1024).round()} KiB');
  }
}

void _star(_Canvas c) {
  final pts = [
    for (var i = 0; i < 10; i++)
      () {
        final r = i.isEven ? 188.0 : 78.0;
        final a = -math.pi / 2 + i * math.pi / 5;
        return _p(256 + r * math.cos(a), 272 + r * math.sin(a));
      }(),
  ];
  c.sticker(
    _round(_polygon(pts), 14),
    _vertical(0xFFFFE45C, 0xFFFF9F1C, 70, 450),
  );
}

void _heart(_Canvas c) {
  final pts = _curve(240, (t) {
    final s = math.sin(t);
    final x = 16 * s * s * s;
    final y =
        13 * math.cos(t) -
        5 * math.cos(2 * t) -
        2 * math.cos(3 * t) -
        math.cos(4 * t);
    return _p(256 + x * 11.5, 250 - y * 11.5);
  });
  c
    ..sticker(_polygon(pts), _vertical(0xFFFF6B9A, 0xFFE0115F, 90, 440))
    ..fill(_roundBox(180, 170, 34, 18, 18), _solid(0x66FFFFFF), soften: 6);
}

void _sun(_Canvas c) {
  final rays = <_Sdf>[
    for (var i = 0; i < 12; i++)
      () {
        final a = i * math.pi / 6;
        const base = 0.16;
        return _round(
          _polygon([
            _p(256 + 128 * math.cos(a - base), 256 + 128 * math.sin(a - base)),
            _p(256 + 212 * math.cos(a), 256 + 212 * math.sin(a)),
            _p(256 + 128 * math.cos(a + base), 256 + 128 * math.sin(a + base)),
          ]),
          6,
        );
      }(),
  ];
  final disc = _circle(256, 256, 132);
  const brown = 0xFF7A3E00;
  c
    ..sticker(_union([...rays, disc]), _solid(0xFFFF9F1C))
    ..fill(disc, _vertical(0xFFFFF176, 0xFFFFC107, 124, 388))
    ..fill(_circle(212, 232, 15), _solid(brown))
    ..fill(_circle(300, 232, 15), _solid(brown))
    ..fill(
      _stroke([
        for (var i = 0; i <= 20; i++)
          _p(
            256 + 64 * math.cos(math.pi * (0.15 + 0.7 * i / 20)),
            262 + 52 * math.sin(math.pi * (0.15 + 0.7 * i / 20)),
          ),
      ], 9),
      _solid(brown),
    )
    ..fill(_circle(186, 286, 18), _solid(0x55FF7043), soften: 8)
    ..fill(_circle(326, 286, 18), _solid(0x55FF7043), soften: 8);
}

void _wow(_Canvas c) {
  final bubble = _union([
    _roundBox(256, 226, 212, 142, 70),
    _round(_polygon([_p(150, 320), _p(238, 340), _p(118, 440)]), 8),
  ]);
  c.sticker(bubble, _vertical(0xFF9A7BFF, 0xFF5B34E6, 84, 440));

  const top = 176.0;
  const bottom = 282.0;
  List<math.Point<double>> w(double x0) {
    const width = 104.0;
    return [
      _p(x0, top),
      _p(x0 + width * 0.25, bottom),
      _p(x0 + width * 0.5, top + (bottom - top) * 0.38),
      _p(x0 + width * 0.75, bottom),
      _p(x0 + width, top),
    ];
  }

  _Sdf o(double cx) => (x, y) {
    final dx = x - cx;
    final dy = (y - (top + bottom) / 2) * 46 / 53;
    return (math.sqrt(dx * dx + dy * dy) - 46).abs() - 13;
  };

  final letters = _union([_stroke(w(78), 13), o(256), _stroke(w(330), 13)]);
  c
    ..fill(letters, _solid(0x66300A80), dx: 3, dy: 5, soften: 3)
    ..fill(letters, _solid(0xFFFFFFFF));
}

void _lightning(_Canvas c) {
  final bolt = _polygon([
    _p(288, 40),
    _p(146, 282),
    _p(246, 282),
    _p(200, 474),
    _p(372, 208),
    _p(268, 208),
    _p(334, 40),
  ]);
  c.sticker(_round(bolt, 8), _vertical(0xFFFFEA3D, 0xFFFFA000, 40, 474));
}

void _crown(_Canvas c) {
  final body = _round(
    _polygon([
      _p(92, 206),
      _p(172, 300),
      _p(256, 150),
      _p(340, 300),
      _p(420, 206),
      _p(396, 378),
      _p(116, 378),
    ]),
    10,
  );
  final tips = [
    _circle(92, 198, 24),
    _circle(256, 140, 28),
    _circle(420, 198, 24),
  ];
  final band = _roundBox(256, 372, 152, 30, 14);
  c
    ..sticker(
      _union([body, ...tips, band]),
      _vertical(0xFFFFE08A, 0xFFF4A300, 120, 400),
    )
    ..fill(band, _vertical(0xFFF7B733, 0xFFD98E04, 342, 402));
  for (final tip in tips) {
    c.fill(tip, _vertical(0xFFFFF3C4, 0xFFFFC53D, 110, 230));
  }
  c
    ..fill(_circle(256, 372, 17), _solid(0xFFE63946))
    ..fill(_circle(176, 372, 12), _solid(0xFF3A86FF))
    ..fill(_circle(336, 372, 12), _solid(0xFF3A86FF));
}

void _sparkle(_Canvas c) {
  List<math.Point<double>> astroid(double cx, double cy, double r) =>
      _curve(200, (t) {
        final co = math.cos(t);
        final si = math.sin(t);
        return _p(cx + r * co * co * co, cy + r * si * si * si);
      });
  final big = _round(_polygon(astroid(230, 282, 196)), 6);
  final small = _round(_polygon(astroid(398, 118, 74)), 4);
  c
    ..sticker(_union([big, small]), _vertical(0xFF8CFBFF, 0xFF3A86FF, 80, 480))
    ..fill(_circle(230, 282, 30), _solid(0xAAFFFFFF), soften: 22)
    ..fill(_circle(398, 118, 12), _solid(0xAAFFFFFF), soften: 10);
}

void _flame(_Canvas c) {
  List<math.Point<double>> flame(double cx, double cy, double w, double h) =>
      _curve(260, (t) {
        final half = math.sin(t / 2);
        final width = math.sin(t) * math.pow(half, 1.4);
        final lean = math.pow(math.max(0, math.cos(t)), 2) * 0.22;
        final wobble = 0.06 * math.sin(3 * t) * (1 - math.cos(t)) / 2;
        return _p(cx + w * (width + lean + wobble), cy - h * math.cos(t));
      });
  final outer = _polygon(flame(250, 278, 190, 206));
  final inner = _polygon(flame(252, 338, 100, 120));
  c
    ..sticker(outer, _vertical(0xFFFF8A00, 0xFFFF2E00, 70, 484))
    ..fill(inner, _vertical(0xFFFFF176, 0xFFFFB703, 220, 460), soften: 1.5);
}

/// Square cover art for the sample tracks, named `artwork_<track id>.png`
/// as the example's `SampleMusicProvider` expects.
void _generateArtwork() {
  final out = Directory(_musicDir)..createSync(recursive: true);
  _Sdf everywhere() =>
      (_, _) => -1000;
  final covers = <String, void Function(_Canvas)>{
    'sunrise': (c) => c
      ..fill(everywhere(), _vertical(0xFFFF9A5A, 0xFFE83E8C, 0, 512))
      ..fill(
        _circle(256, 300, 150),
        _vertical(0xFFFFF3A0, 0xFFFFB347, 150, 450),
      )
      ..fill(
        _polygon(
          _curve(120, (t) {
            final x = 512 * t / (2 * math.pi);
            return _p(x, 350 + 30 * math.sin(t * 2 + 1));
          })..addAll([_p(512, 512), _p(0, 512)]),
        ),
        _solid(0xFF5B2A86),
      ),
    'midnight': (c) {
      c.fill(everywhere(), _vertical(0xFF141A46, 0xFF3B1466, 0, 512));
      for (var i = 0; i < 4; i++) {
        final r = 70.0 + i * 44;
        c.fill(
          (x, y) => _circle(256, 256, r)(x, y).abs() - 6,
          _solid(i.isEven ? 0xFF00E5FF : 0xFFFF3DDB),
          opacity: 1 - i * 0.18,
        );
      }
    },
    'paper': (c) => c
      ..fill(everywhere(), _vertical(0xFF8FD3FF, 0xFFE6F6FF, 0, 512))
      ..fill(
        _round(_polygon([_p(84, 262), _p(428, 120), _p(300, 410)]), 6),
        _solid(0xFFFFFFFF),
      )
      ..fill(
        _round(_polygon([_p(428, 120), _p(236, 300), _p(300, 410)]), 6),
        _solid(0xFFD5E6F3),
      )
      ..fill(
        _stroke([_p(60, 430), _p(140, 380), _p(210, 400)], 5),
        _solid(0x99FFFFFF),
      ),
    'lofi': (c) => c
      ..fill(everywhere(), _vertical(0xFFE9D5B7, 0xFFB98B5E, 0, 512))
      ..fill(
        (x, y) => _circle(350, 300, 52)(x, y).abs() - 16,
        _solid(0xFF6B3E26),
      )
      ..fill(_roundBox(236, 310, 120, 110, 36), _solid(0xFF6B3E26))
      ..fill(_roundBox(236, 222, 104, 20, 18), _solid(0xFF3B2012))
      ..fill(
        _stroke([
          for (var i = 0; i <= 16; i++)
            _p(206 + 14 * math.sin(i / 16 * 2 * math.pi), 180 - i * 6.0),
        ], 7),
        _solid(0x88FFFFFF),
      )
      ..fill(
        _stroke([
          for (var i = 0; i <= 16; i++)
            _p(266 + 14 * math.sin(i / 16 * 2 * math.pi + 1), 186 - i * 6.0),
        ], 7),
        _solid(0x88FFFFFF),
      ),
  };
  for (final entry in covers.entries) {
    final canvas = _Canvas();
    entry.value(canvas);
    final file = File('${out.path}/artwork_${entry.key}.png')
      ..writeAsBytesSync(_encodePng(_size, _size, canvas.toRgba8()));
    stdout.writeln('${file.path}: ${(file.lengthSync() / 1024).round()} KiB');
  }
}

// ---------------------------------------------------------------------------
// PNG
// ---------------------------------------------------------------------------

Uint8List _encodePng(int width, int height, Uint8List rgba) {
  final stride = width * 4;
  final raw = Uint8List(height * (stride + 1));
  for (var y = 0; y < height; y++) {
    final row = y * (stride + 1);
    raw[row] = 1; // Sub filter
    for (var x = 0; x < stride; x++) {
      final cur = rgba[y * stride + x];
      final left = x >= 4 ? rgba[y * stride + x - 4] : 0;
      raw[row + 1 + x] = (cur - left) & 0xFF;
    }
  }
  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 6) // RGBA
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  final out = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(_chunk('IHDR', header.buffer.asUint8List()))
    ..add(_chunk('IDAT', ZLibEncoder(level: 9).convert(raw)))
    ..add(_chunk('IEND', const []));
  return out.toBytes();
}

Uint8List _chunk(String type, List<int> data) {
  final typeBytes = type.codeUnits;
  final crcInput = [...typeBytes, ...data];
  final b = ByteData(12 + data.length)..setUint32(0, data.length);
  for (var i = 0; i < 4; i++) {
    b.setUint8(4 + i, typeBytes[i]);
  }
  for (var i = 0; i < data.length; i++) {
    b.setUint8(8 + i, data[i]);
  }
  b.setUint32(8 + data.length, _crc32(crcInput));
  return b.buffer.asUint8List();
}

final List<int> _crcTable = List.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
