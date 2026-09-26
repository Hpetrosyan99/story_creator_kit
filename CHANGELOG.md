## 0.2.0

- New design: dark palette (`#141414` / `#1F1F21` / `#2D2D30`, accent `#CF5835`), rounded canvas card, 44 px nav buttons, 20 px icon rails, new camera, gallery, editor, music list and waveform segment selector.
- `StoryCreatorTheme.isLiquidGlassEnabled`: frosted liquid-glass rendering of the translucent controls; plus `onSurfaceSecondary`, `pillBackground` tokens and new text styles.
- Camera: Video / Photo toggle, text-only story, red recording shutter; no loading spinner when the creator opens.
- Editor: gallery thumbnail replaces the media keeping edits; music chip; secondary tools behind "More".
- Music: tap a track to select it; `MusicCategory.showRanks` for leaderboard-style lists.
- Icons are bundled SVGs (new dependency: `flutter_svg`).
- Camera Video / Photo switcher is a sliding capsule (tap or drag).
- Editor tools sit on translucent circles so they stay visible on bright media; the "More" tools animate open and closed without moving the main tools.
- Text highlight backgrounds join into one shape across lines (no seams).
- Fix: two-finger scale / rotate grabs the overlay under the fingers even when neither finger starts on it.
- Fix: export could stall with liquid glass on (hidden glass surfaces now draw flat) and under heavy icon shadows (shadows are pre-rendered).

## 0.1.0

First release. Supports iOS 16+ and Android 8.0+ (API 26).

### Flow and API

- `StoryCreator.open(context, config:, services:)` returns a sealed
  `StoryOutcome`: `StoryCompleted`, `StoryCancelled` or `StoryFailed`.
  `StoryCreatorPage` is the same flow as a widget, for apps that manage their
  own routes.
- `StoryCreatorConfig` covers theme, strings, capture, constraints, editor,
  output, the music provider and an `onEvent` hook. Every value has a
  default.
- `StoryResult` carries the file path, type, MIME type, size, duration and
  poster frame, plus `StoryMetadata`: source, trim, audio volume, music,
  filter, texts, stickers, emoji and drawing.
- `StoryEvent`s report analytics and handled errors. Failures are typed as
  `StoryException` with a `StoryErrorCode`.
- `package:story_creator_kit/services.dart` exposes the service interfaces
  (capture, gallery, permissions, media inspection, playback, export,
  gallery saving), so you can replace them, e.g. with a simulated camera or
  test fakes.

### Camera and gallery

- Tap to take a photo, hold to record a video, with a progress ring and
  timer. Recording stops at `maxVideoDuration`, and clips shorter than
  `minVideoDuration` are discarded with a notice.
- Front/rear switch, flash (torch for video), pinch and drag-to-zoom, tap to
  focus. Controls stay hidden when the hardware lacks them.
- Lifecycle and interruption handling: a partial recording is kept or
  discarded, and the camera re-initialises when the app returns.
- Permission handling for camera, microphone and photos, including limited
  access and an "Open settings" path. Denying the microphone still allows
  silent videos.
- In-app gallery grid (album switching, duration badges, iCloud downloads)
  or the permission-free system picker (`GalleryMode.systemPicker`).
- Videos longer than the maximum open in the trimmer.

### Editor

- Text with host fonts (bundled or loaded at runtime), colours, three
  alignments and four background styles. Edit in place; move, pinch-resize
  and rotate; drag to the trash.
- Freehand drawing with pen, marker, neon and eraser.
- Stickers from any `ImageProvider`, and emoji.
- Eight built-in colour filters (`StoryFilter.defaults`) and custom 4×5
  matrix filters.
- Music from a host-implemented `StoryMusicProvider`: categories, search,
  cursor pagination, bookmarks, and file, asset or URL sources. The user
  picks the segment on a waveform and sets the volume.
- Video trim, mute and original-audio volume.
- Undo/redo across tools. Edits survive the round trip through export and
  preview.
- Accessibility: semantics labels, 48 pt targets, and an adjust panel for
  overlays that works without gestures.

### Export

- Native engines, with no FFmpeg: AVFoundation on iOS, Media3 Transformer
  1.10.1 on Android.
- Photos export as 1080×1920 JPEG. Videos and photo + music export as
  1080×1920 MP4 at 30 fps, H.264 High, AAC-LC 128 kbps 44.1 kHz stereo.
- Overlays, drawing and filters render with the same painters as the editor,
  so the export matches the preview.
- Progress reporting and cancellation; partial output is removed.
- Preview of the exported file and optional save to the device gallery
  (`SaveToGalleryMode.never`, `button` or `always`).
- Per-session temporary files are cleaned up on every exit path. Leftovers
  from crashed sessions are swept on the next start.

### Example

- The example app has a simulated camera for the iOS Simulator, an in-memory
  music provider with self-generated CC0 tracks, generated stickers and four
  SIL OFL fonts.
