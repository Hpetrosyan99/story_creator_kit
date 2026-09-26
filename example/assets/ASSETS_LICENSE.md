# Example assets: origin and licences

## Music (`music/`) and stickers (`stickers/`): CC0 1.0

`tool/generate_sample_assets.dart` in this repository produced every file in
`music/` and `stickers/`. No samples, recordings, clip art or third-party
material went into them. The script synthesises the music (oscillators,
noise drums, plucked strings) and draws the stickers (vector shapes
rasterised by the script itself).

To the extent possible under law, the authors of story_creator_kit have
waived all copyright and related or neighbouring rights to these generated
files and dedicate them to the public domain under
[CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/).
You may use them for any purpose, including commercially, without
attribution.

Run this from the repository root to regenerate them (macOS `afconvert`, or
`ffmpeg`, encodes the AAC):

```sh
dart run tool/generate_sample_assets.dart
```

| File | Title | Tempo | Length |
|---|---|---|---|
| `music/sunrise_drive.m4a` | Sunrise Drive | 112 BPM | 66.8 s |
| `music/slow_coffee.m4a` | Slow Coffee | 84 BPM | 76.8 s |
| `music/midnight_pulse.m4a` | Midnight Pulse | 128 BPM | 62.5 s |
| `music/paper_planes.m4a` | Paper Planes | 96 BPM | 87.5 s |

Every track is AAC-LC, 128 kbps, 44.1 kHz stereo. Each one has clearly quiet
sections (intro, breakdown, outro) and loud sections, so its waveform has a
visible shape.

Cover art: `music/artwork_sunrise.png`, `artwork_midnight.png`,
`artwork_paper.png` and `artwork_lofi.png`, each a 512×512 PNG.

Stickers: `star`, `heart`, `sun`, `wow`, `lightning`, `crown`, `sparkle` and
`flame`, each a 512×512 transparent PNG.

## Fonts (`fonts/`): SIL Open Font License 1.1

These files are unmodified and come from
[github.com/google/fonts](https://github.com/google/fonts) (`ofl/<family>/`).
Only the file names changed. Each family's licence sits next to it:

| Family | Files | Licence |
|---|---|---|
| Onest (UI font of the design) | `Onest-Variable.ttf` (variable `wght`) | `Onest-OFL.txt` |
| Inter | `Inter-Variable.ttf` (variable `opsz`, `wght`) | `Inter-OFL.txt` |
| Playfair Display | `PlayfairDisplay-Variable.ttf` (variable `wght`) | `PlayfairDisplay-OFL.txt` |
| Pacifico | `Pacifico-Regular.ttf` | `Pacifico-OFL.txt` |
| Space Mono | `SpaceMono-Regular.ttf`, `SpaceMono-Bold.ttf` | `SpaceMono-OFL.txt` |

The OFL lets you bundle these fonts in an app. It forbids selling the fonts
on their own, and "Playfair Display" is a Reserved Font Name.
