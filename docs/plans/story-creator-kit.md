# Plan — `story_creator_kit` (Instagram-style story creator, pub.dev plugin)

Status: **awaiting approval** · 2026-09-25 · no formal ticket (prose brief + reference design, 4 screens)

## 0. Decisions already taken

| Topic | Decision |
|---|---|
| Repo shape | Repo root becomes the publishable Flutter plugin `story_creator_kit`. The boilerplate app (`lib/features`, `packages/api`, `packages/design_system`, MobX/GetIt/AutoRoute/Dio, Melos) is removed on branch `feat/story-creator-kit`, and stays in git history. |
| Platforms | iOS 16+, Android 8.0+ (API 26). compileSdk/targetSdk 36. |
| Formats | Input: anything the OS decodes (JPEG/PNG/HEIC/WebP, H.264/HEVC incl. HDR). Output: 1080×1920 H.264 High / AAC-LC 128 kbps 44.1 kHz stereo MP4, 30 fps; photos as JPEG 1080×1920. |
| Duration | `maxVideoDuration` configurable, default 60 s; `minVideoDuration` default 1 s. Longer gallery videos open in the trimmer. Photo + music → video of `photoWithMusicDuration` (default 15 s, ≤ max). |
| Music | Abstract `StoryMusicProvider` (categories, search, cursor pagination, bookmarks, resolve to file/URL). Example ships an in-memory provider with **self-generated** tracks (no licence risk). |
| Extras | Stickers + emoji, colour filters, save to device gallery. No Post/Story/Reel mode bar. |
| Export engine | **Own native code** inside the plugin: AVFoundation (iOS), Media3 Transformer (Android), via Pigeon. No FFmpeg, no third-party export plugin. |
| State | Plain Flutter (`ChangeNotifier` / `ValueNotifier` / `InheritedWidget`). No MobX, Provider, GetIt, hooks, easy_localization in the library. |
| Publishing | Target: clean `dart pub publish --dry-run` + high pana score. The actual `pub publish` is yours to run. |

## 1. Research summary and tradeoffs

Full reports (URLs, versions, licences, dates) go to `docs/research/` in Phase 0.

**Dependencies (all verified 2026-09-25)**

| Need | Package | Version | Licence | Why / tradeoff |
|---|---|---|---|---|
| Camera | `camera` (flutter.dev) | ^0.12.1 | BSD-3 | Photo + video from one controller, pause/resume, focus/exposure, zoom, torch, switch mid-recording. Gaps we cover ourselves: `maxDuration` ignored → own timer; iOS interruptions not surfaced to Dart → lifecycle handling + real duration via probe; front-camera mirroring inconsistent → normalised in the document. `camerawesome` rejected: stale, licence "pending", AGP issues. |
| Gallery grid | `photo_manager` + `photo_manager_image_provider` | ^3.12.0 / ^2.2.0 | Apache-2.0 | Needed for the reference "Recent" grid, limited access, album switching. **Play policy:** broad media permissions require a Play Console declaration from each host → library also offers a permission-free system-picker mode. |
| System picker fallback | `image_picker` | ^1.2.3 | Apache/BSD | Android Photo Picker / PHPicker, no permission. |
| Camera/mic permission | `permission_handler` | ^13.0.2 | MIT | Status, request, open settings. Photos permission is owned by `photo_manager`. |
| Save to gallery | `gal` | ^2.3.3 | BSD-3 | Add-only permission on iOS. |
| Video preview | `video_player` | ^2.14.0 | BSD-3 | Media3 ExoPlayer / AVPlayer; frame-exact seek. No range playback → trim loop by position watch (≤100 ms overshoot in preview only). |
| Music preview | `just_audio` + `audio_session` | ^0.10.6 / ^0.2.4 | MIT | `setClip`, loop, volume; runs beside video_player. iOS session interplay needs a device check. |
| Stroke geometry | `perfect_freehand` | ^2.5.2 | MIT | Pressure-like smooth outlines; everything else in drawing is ours. |
| Colour quantisation | `material_color_utilities` | (Flutter-pinned) | Apache-2.0 | Background gradient for non-9:16 media (`palette_generator` is discontinued). |
| Native bridge | `pigeon` (dev) | ^29 | BSD-3 | Typed channel code for Swift + Kotlin. |
| Tests | `integration_test` (SDK), `mocktail`, `alchemist` (goldens) | — | BSD/MIT | Patrol considered for OS dialogs; decide in Phase 4 (adds a native test runner; Maestro alternative). |

**Built, not adopted:** `pro_image_editor` (BSD-3, strong) would force its UI model, mode-switching editor and export, and has monthly majors plus a Material migration pushed onto hosts. Gesture, text, drawing and trim packages are stale or don't fit. Building our own gives one document model rendered by the same painter on screen and at export — the core guarantee that export matches preview.

**Export engine tradeoff (you chose native):** ~0 MB added, no LGPL/patent burden on hosts, full hardware decode/encode. Cost: most engineering, iOS 26/27 deprecations need `#available` branches, Media3 needs all audio inputs normalised to the same PCM format. Media3 pinned to **1.10.1** (1.11.x has an open Samsung A-series export regression, androidx/media#3399).

## 2. Architecture

```
Host app
  └─ StoryCreator.open(context, config) ──► Future<StoryOutcome>   (or StoryCreatorPage widget + onFinished)
        │
        ▼
  StoryFlowController (ChangeNotifier) — owns the session: temp dir, StoryDocument, step
        ├─ CameraScreen   ── CaptureService (camera pkg)   ── PermissionService
        │     └─ GallerySheet ── GallerySource (photo_manager | system picker)
        ├─ EditorScreen   ── EditorController(StoryDocument, History)
        │     ├─ StoryCanvasView  (media layer · filter · StoryOverlayPainter · drawing)
        │     ├─ tools: text · draw · stickers · filters · music · trim · audio mix
        │     └─ MusicSession (just_audio) + VideoSession (video_player)
        ├─ ExportScreen   ── StoryExporter ── OverlayRasterizer (same painters, 1080×1920)
        │                                  └─ NativeMediaApi (Pigeon) ─► Swift / Kotlin
        └─ PreviewScreen  ── plays the actual exported file → confirm / back to edit
```

**One document, two renderers.** `StoryDocument` (immutable, `copyWith`) holds: source media + placement (scale/offset in canvas units, mirror flag), filter id, overlays (text / sticker / emoji; each with transform = position, scale, rotation, z), drawing strokes (canvas units), trim range, original-audio volume, music selection (track, start, duration, volume). Canvas coordinates are fixed at **1080×1920**; the screen view scales that canvas to fit. Overlay painting code (`StoryOverlayPainter`, `StoryTextLayout`, `StrokeRenderer`) is shared by the live view and the export rasterizer, so export equals preview by construction. Text is laid out once in canvas units with OS text scaling disabled.

**Export pipeline**
- *Photo:* Dart composes the full frame at 1080×1920 (background, decoded photo with filter via `ColorFilter.matrix`, overlays) → RGBA → native JPEG encode. No native colour maths → pixel-identical to preview.
- *Video:* Dart rasterises one **frame overlay PNG**: background with a transparent hole where the video sits, plus all edits. Native decodes the video, applies trim, the same 4×5 colour matrix, scales/translates it into the canvas rect (honouring `preferredTransform` / rotation metadata and mirror flag), composites the PNG on top, mixes original audio (volume, or muted) with the music segment (volume, start offset, trimmed to video length), encodes H.264/AAC.
- *Photo + music:* Dart composes the still frame → native encodes a still-image video for the music segment length with that audio.
- Progress events stream through a Pigeon `FlutterApi`; `cancelExport(jobId)` stops the native job and deletes partial output. Failures map to `StoryExportException` codes.

**Native API contract (Pigeon, lands in Phase 1)**

```dart
@HostApi()
abstract class StoryNativeApi {
  @async ExportResultMsg exportVideo(VideoExportRequest request);          // jobId, sourcePath, trimStartMs, trimEndMs,
                                                                           // videoRect(x,y,w,h in canvas px), mirror,
                                                                           // colorMatrix(20 doubles)?, overlayPngPath,
                                                                           // originalVolume, music?(path,startMs,volume),
                                                                           // outputPath, width, height, fps, bitrate
  @async ExportResultMsg exportStillVideo(StillVideoExportRequest request); // jobId, framePngPath, durationMs, music, output
  @async ExportResultMsg encodeJpeg(JpegEncodeRequest request);            // rgbaPath or png path, quality, output
  void cancelExport(String jobId);
  @async MediaProbeMsg probe(String path);        // durationMs, width, height, rotation, hasAudio, codecs, fileSize
  @async List<double> waveform(String path, int buckets);
  @async List<String> thumbnails(String path, List<int> timesMs, int maxWidth, String outDir);
}
@FlutterApi()
abstract class StoryNativeEvents { void onExportProgress(String jobId, double progress); }
```

**Public API (sketch)**

```dart
final outcome = await StoryCreator.open(
  context,
  config: StoryCreatorConfig(
    theme: StoryCreatorTheme.dark(accent: Color(0xFFE4572E)),
    strings: const StoryCreatorStrings(),            // subclass/override for i18n
    capture: const CaptureOptions(galleryMode: GalleryMode.inApp, enableAudio: true),
    constraints: const MediaConstraints(maxVideoDuration: Duration(seconds: 60)),
    editor: EditorOptions(fonts: [...StoryFont], stickers: [...StorySticker], filters: StoryFilter.defaults),
    output: const OutputOptions(saveToGallery: SaveToGallery.button, jpegQuality: 90),
    musicProvider: MyMusicProvider(),                // optional; music tool hidden when null
    onEvent: (event) {},                             // analytics / issue tracking hook
  ),
);
switch (outcome) {
  case StoryCompleted(:final result): // result.file, .type, .mimeType, .width, .height, .duration,
                                      // .fileSize, .thumbnailPath, .savedToGallery, .metadata
  case StoryCancelled(:final reason):
  case StoryFailed(:final error):
}
```

`StoryMusicProvider`: `categories`, `fetchTracks(query, cursor) → MusicPage`, optional `setBookmarked`, `resolve(track) → MusicSource.file | MusicSource.url(headers)`. Tracks may carry precomputed waveform peaks; otherwise native `waveform()`. URL tracks are downloaded to the session cache (dart:io `HttpClient`) when selected, because export needs a local file.

## 3. File-level plan

### Phase 0 — Restructure (Agent 1 + lead)

| Path | Action |
|---|---|
| branch `feat/story-creator-kit` | create from `master` |
| `lib/**`, `packages/**`, `assets/translations/**`, `build.yaml`, `devtools_options.yaml`, `runConfigurations/`, `.maestro/flows/*` (boilerplate), `test/**`, melos config | delete (app-specific) |
| `docs/adr/*`, `docs/*.md` guides, `DESIGN.md`, `.claude/skills/*` (app playbooks), `.claude/commands/*`, app-specific `.github/workflows/*` | delete or replace; keep `.claude/agents/*` (flutter/ios/android/orchestrator teams) and generic review commands |
| `pubspec.yaml` | rewrite as plugin: `name: story_creator_kit`, `flutter.plugin.platforms.{ios,android}`, deps above, `repository`/`homepage` (open question), `topics` |
| `ios/story_creator_kit/Package.swift`, `ios/story_creator_kit.podspec`, `ios/story_creator_kit/Sources/story_creator_kit/` | create (SPM + CocoaPods) |
| `android/build.gradle.kts`, `android/settings.gradle.kts`, `android/src/main/AndroidManifest.xml`, `android/src/main/kotlin/com/mabrook/story_creator_kit/` | create; Media3 1.10.1 (`transformer`, `effect`, `common`) |
| `example/` | `flutter create --platforms=ios,android --org com.mabrook` + Info.plist keys, manifest permissions |
| `analysis_options.yaml` | keep strict lints, drop app-only rules |
| `AGENTS.md` (+ `tool/sync_agents.sh` output) | rewrite for the plugin (layout, rules, commands) |
| `.claude/settings.json`, `.claude/scripts/post_turn.sh` | adapt: no melos/codegen; `dart format`, `dart analyze`, pigeon regen when `pigeons/` changes |
| `.github/workflows/ci.yml` | analyze, format check, test, `pub publish --dry-run`, build example (ios no-codesign, apk) |
| `docs/research/*.md` | copy the four research reports |
| `LICENSE`, `CHANGELOG.md`, `README.md` | create (licence: open question) |

### Phase 1 — Contracts (lead + Agent 1; everything below lands before parallel work)

| File | Content |
|---|---|
| `lib/story_creator_kit.dart` | public barrel only |
| `lib/src/api/story_creator.dart` | `StoryCreator.open`, `StoryCreatorPage` |
| `lib/src/api/config/{story_creator_config,capture_options,media_constraints,editor_options,output_options}.dart` | immutable config |
| `lib/src/api/theme/story_creator_theme.dart`, `lib/src/api/strings/story_creator_strings.dart` | styling + overridable English strings |
| `lib/src/api/assets/{story_font,story_sticker,story_filter}.dart` | host-supplied fonts (optional async loader), stickers (`ImageProvider`), filters (4×5 matrix) + `StoryFilter.defaults` (8 filters) |
| `lib/src/api/music/{story_music_provider,music_track,music_category,music_page,music_source}.dart` | music contract |
| `lib/src/api/result/{story_outcome,story_result,story_metadata}.dart`, `lib/src/api/errors/story_exception.dart` | sealed outcome, result, typed errors |
| `lib/src/api/events/story_event.dart` | `onEvent` payloads |
| `lib/src/model/{story_document,story_media,media_placement,story_overlay,text_overlay_style,drawing_stroke,music_selection,trim_range,overlay_transform}.dart` | document model (immutable, `==`) |
| `lib/src/model/history.dart` | generic undo/redo over `StoryDocument` snapshots |
| `lib/src/core/{story_scope,story_canvas,session_files,story_logger}.dart` | InheritedWidget scope, canvas constants + transforms, temp-dir lifecycle, event dispatch |
| `lib/src/services/capture/capture_service.dart` | interface: init(camera), preview widget, takePhoto, start/stop/pause recording, flash, zoom, focus, events stream |
| `lib/src/services/gallery/gallery_source.dart` | interface: permission state, albums, paged assets, thumbnail, resolve file |
| `lib/src/services/permissions/permission_service.dart` | interface: camera, mic, photos (full/limited/denied/permanentlyDenied), openSettings |
| `lib/src/services/audio/music_session.dart`, `lib/src/services/video/video_session.dart` | playback interfaces |
| `lib/src/services/export/story_exporter.dart` | interface: export(document) → Stream<ExportProgress> + result, cancel |
| `pigeons/story_native_api.dart` → `lib/src/native/story_native_api.g.dart`, `ios/.../StoryNativeApi.g.swift`, `android/.../StoryNativeApi.g.kt` | contract above, generated |
| `lib/src/flow/story_flow_controller.dart`, `lib/src/flow/story_flow_navigator.dart` | step machine camera → editor → export → preview; cancel/back rules |
| `test/fakes/*.dart` | fake CaptureService, GallerySource, PermissionService, MusicSession, VideoSession, StoryExporter, MusicProvider |

### Phase 2 — Parallel implementation (disjoint directories)

**Agent 2 — Camera, gallery, permissions, media lifecycle** (`lib/src/camera/`, `lib/src/gallery/`, `lib/src/services/{capture,gallery,permissions}/*_impl.dart`)

| File | Content |
|---|---|
| `services/capture/camera_capture_service.dart` | `camera` impl; lifecycle (inactive → stop & keep partial clip, dispose; resumed → reinit), own max-duration timer, error mapping, mirror flag per platform/lens |
| `services/gallery/photo_manager_gallery_source.dart`, `services/gallery/system_picker_gallery_source.dart` | grid source + permission-free fallback; iCloud download progress; HEIC/HEVC pass-through |
| `services/permissions/permission_handler_service.dart` | permission_handler + photo_manager bridge |
| `camera/camera_screen.dart`, `camera/camera_controller.dart` | screen + ChangeNotifier |
| `camera/widgets/{shutter_button,recording_indicator,flash_toggle,camera_switch_button,zoom_indicator,focus_marker,gallery_shortcut,permission_prompt,camera_unavailable_view}.dart` | tap = photo, hold (or tap in video mode) = record with progress ring + timer; pinch & drag-up zoom; tap to focus; screen-flash for front camera |
| `gallery/gallery_sheet.dart`, `gallery/widgets/{album_selector,asset_grid,asset_tile,limited_access_banner,camera_tile}.dart` | reference screen 1: "Recent ›" album picker, camera tile, selection circles, video duration badges |
| `core/media_import.dart` | validate + normalise picked/captured file → `StoryMedia` (probe, orientation, too-long → trim required, unsupported → typed error) |

**Agent 3 — Editor UI, text, drawing, interactions** (`lib/src/editor/`, `lib/src/render/painters/`)

| File | Content |
|---|---|
| `editor/editor_screen.dart`, `editor/editor_controller.dart` | reference screen 2: close ✕, accent ✓, right-side tool rail (music, text, stickers, draw, filters, trim, audio), bottom tool panels; tool switches keep document; back/cancel confirm discard |
| `editor/canvas/{story_canvas_view,media_layer,overlay_layer,drawing_layer,gesture_layer,trash_zone,snap_guides}.dart` | single `ScaleGestureRecognizer` over canvas, own hit test, move/pinch/rotate, drag-to-trash, centre snapping + haptics, bring to front; pinch media when no overlay hit; horizontal swipe = filter change |
| `render/painters/{story_overlay_painter,story_text_layout,text_background_painter,stroke_renderer,sticker_painter}.dart` | **shared** with export: per-line rounded highlight, solid, translucent, none; perfect_freehand strokes, eraser via `saveLayer`+`BlendMode.clear`, cached finished-stroke picture |
| `editor/text/{text_edit_overlay,font_carousel,color_palette,alignment_toggle,background_style_toggle}.dart` | edit-in-place with keyboard; line breaks identical to painter |
| `editor/drawing/{drawing_toolbar,brush_size_slider}.dart` | colours, sizes, pen/marker/eraser, undo/redo |
| `editor/stickers/sticker_picker_sheet.dart` | host stickers + emoji grid |
| `editor/filters/filter_strip.dart` | named filters with live thumbnails |
| `editor/video/{video_layer,trim_bar,thumbnail_strip,playback_controls}.dart` | play/pause, trim handles (≤ max duration), loop in range, thumbnails via native API |
| `editor/audio/audio_mix_sheet.dart` | original audio volume / mute, music volume |
| `editor/accessibility/overlay_adjust_panel.dart` | semantics actions + non-gesture move/resize/rotate/delete |

**Agent 4 — Music, rendering/export, native, QA** (`lib/src/music/`, `lib/src/export/`, `lib/src/preview/`, `lib/src/services/{audio,video,export}/*_impl.dart`, `ios/`, `android/`, `example/integration_test/`)

| File | Content |
|---|---|
| `music/music_picker_sheet.dart`, `music/widgets/{music_search_field,category_chips,track_tile,bookmark_button}.dart`, `music/music_picker_controller.dart` | reference screen 3: search, All/Bookmarked/Leaderboard chips from provider, playing indicator, bookmarks, pagination, empty/error/offline states |
| `music/segment_selector.dart`, `music/waveform_painter.dart`, `music/music_cache.dart` | reference screen 4: waveform with accent window, drag to choose start, loop preview; download URL tracks to cache |
| `services/audio/just_audio_music_session.dart`, `services/video/video_player_session.dart` | playback impls + audio_session config |
| `render/overlay_rasterizer.dart`, `render/frame_composer.dart` | `PictureRecorder` at 1080×1920 using Agent 3's painters; photo full frame; video frame-overlay with hole; font-loaded guard |
| `export/native_story_exporter.dart`, `export/export_screen.dart` | progress ring, cancel, failure with retry / back to editor |
| `preview/preview_screen.dart` | plays the real exported file; confirm → `StoryCompleted`; back → editor with edits intact; save-to-gallery button |
| `ios/.../{StoryCreatorKitPlugin,VideoExporter,StillVideoExporter,JpegEncoder,MediaProbe,WaveformExtractor,ThumbnailGenerator,ColorMatrixFilter}.swift` | AVMutableComposition + audio mix + CIFilter compositor; async export with progress/cancel (`#available` for iOS 18/26/27 API); AVAssetWriter still video; AVAssetReader waveform; AVAssetImageGenerator thumbnails |
| `android/.../{StoryCreatorKitPlugin,VideoExporter,StillVideoExporter,JpegEncoder,MediaProbe,WaveformExtractor,ThumbnailGenerator}.kt` | Media3 Transformer: Composition with video sequence + music sequence, ClippingConfiguration, Presentation + MatrixTransformation, RgbMatrix, BitmapOverlay, volume + channel/sample-rate normalisation, image input with duration; progress polling; cancel |
| `example/integration_test/*` | export matrix + flow tests (Phase 4) |

### Phase 3 — Integration & example app (lead)

| File | Content |
|---|---|
| `lib/src/flow/*` | wire real impls; session cleanup on every exit path |
| `example/lib/{main,home_page,sample_music_provider,sample_fonts,sample_stickers,result_page}.dart` | launch flow, show result + metadata, re-open |
| `example/assets/music/*.m4a` | 4 tracks generated by `tool/generate_sample_music.dart` (synth → WAV) + `afconvert` → AAC; distinct loud/quiet sections for waveform tests |
| `example/assets/fonts/*` + `example/assets/fonts/OFL.txt` | 4 SIL OFL fonts downloaded from `github.com/google/fonts` (e.g. Inter, Playfair Display, Pacifico, Space Mono; ~1 MB total) |
| `example/assets/stickers/*.png` | stickers drawn by a script (no third-party art) |
| `example/ios/Runner/Info.plist`, `example/android/app/src/main/AndroidManifest.xml` | permission strings / media permissions |

### Phase 4 — Tests, device QA, fix loop (Agent 4 leads, all agents fix their areas)

### Phase 5 — Docs & publish readiness (Agent 1)

`README.md` (install, iOS/Android setup, permissions incl. Play policy note, configuration, API, music provider guide, fonts, theming, strings/i18n, known limitations), `doc/api.md` extras, dartdoc on every public symbol, `CHANGELOG.md` 0.1.0, `pana` run, `dart pub publish --dry-run`.

## 4. Agent responsibilities & coordination

| Agent | Owns (write access) | Consumes |
|---|---|---|
| 1 Architecture | Phase 0, Phase 1 `api/`, `model/`, `core/`, `pigeons/`, docs, CI, pubspec | — |
| 2 Camera | `camera/`, `gallery/`, capture/gallery/permission impls, `core/media_import.dart` | Phase 1 interfaces |
| 3 Editor | `editor/`, `render/painters/` | document model, `VideoSession`, `MusicSession` interfaces, native thumbnails |
| 4 Music/Export/QA | `music/`, `export/`, `preview/`, `render/{overlay_rasterizer,frame_composer}.dart`, audio/video/export impls, `ios/`, `android/`, `example/integration_test/` | painters from Agent 3, native contract |

Rules: contracts from Phase 1 change only through the lead (me), announced to all agents. `pubspec.yaml` is lead-only (all deps added in Phase 0). Each agent runs `dart analyze` + its tests before handing back. `ios-team` / `android-team` review the native code in Phase 4.

## 5. Acceptance criteria (verifiable) → proof

| AC | Outcome | Proof |
|---|---|---|
| AC1 | `StoryCreator.open` shows the camera; ✕ returns `StoryCancelled(userCancelled)` and deletes session temp files | widget test (fakes) + integration test |
| AC2 | Tap shutter captures a photo and opens the editor with it | widget (fake) · Android emulator device run |
| AC3 | Hold (or video mode) records; ring + timer show progress; recording stops at `maxVideoDuration`; editor opens with real clip duration | unit (timer) · widget · Android emulator |
| AC4 | Front/rear switch; flash off/auto/on for photo, torch for video; controls hidden when hardware lacks them | widget with capability fakes · emulator (switch only) |
| AC5 | Camera denied → explanation + "Open settings" + gallery still usable; mic denied → video records without audio, notice shown; photos denied → system picker used; limited → banner + manage selection | widget per state · iOS sim + Android emulator permission runs |
| AC6 | App backgrounded while recording → partial clip kept (≥ min duration) or discarded with notice; camera re-initialises on resume; camera unavailable → error view with retry | unit (controller with fake events) · emulator lifecycle run |
| AC7 | Gallery grid shows recent photos/videos with durations, album switch; picking a video longer than max opens trimmer at `[0,max]` | widget · iOS sim with seeded media |
| AC8 | Text: add, edit in place, move, pinch-resize, rotate, delete via trash; ≥ host fonts + colours + 3 alignments + 4 background styles | unit (model/history) · widget gesture tests · goldens per style |
| AC9 | Drawing: colours, sizes, eraser, undo/redo across all tools | unit (history) · golden |
| AC10 | Stickers + emoji behave like text overlays | widget |
| AC11 | Filters: swipe/strip changes filter; preview and export match | golden (photo) · integration frame check (video) |
| AC12 | Music: provider categories, search, pagination, bookmark, preview; segment chosen on waveform; volume; mixed with original audio | unit (controller, fake provider) · widget · integration (probe hasAudio, duration) |
| AC13 | Video: play/pause, trim (≤ max), original audio volume/mute | widget · integration (exported duration = trim length ±50 ms; mute → music-only audio) |
| AC14 | Edits survive switching tools and returning from preview | unit + widget |
| AC15 | Photo export = JPEG 1080×1920 with edits, pixel-matching preview render | integration + golden compare |
| AC16 | Video export = MP4 H.264/AAC 1080×1920 with overlay, trim, filter, audio mix in sync | integration probe (codec, size, duration, audio track) + frame thumbnail compare at t=0/mid/end |
| AC17 | Photo + music → MP4 of `photoWithMusicDuration` with audio | integration probe |
| AC18 | Export shows progress; cancel stops native job, removes partial file, returns to editor; failure shows error + retry, host gets `StoryFailed` only if user leaves | widget (fake exporter) · integration (cancel mid-export) |
| AC19 | Preview plays the exported file; confirm returns `StoryCompleted` with file + metadata; save-to-gallery works | widget · integration · sim/emulator Photos check |
| AC20 | Theme, strings, fonts, stickers, filters, constraints, music provider all configurable; no host backend assumed | unit on config · example app uses custom values |
| AC21 | Package passes `dart analyze`, tests, `pub publish --dry-run`, pana without platform warnings | CI + local run |
| AC22 | Accessibility: all controls have semantics labels, ≥48 pt targets, overlay adjust panel works with screen reader | widget semantics tests (`meetsGuideline`) |

## 6. Testing strategy

- **Unit** (`test/`): document model, history, canvas transforms, text layout line-break parity (TextField vs painter), trim/segment maths, flow controller, camera controller state machine, music picker controller, exporter request building, error mapping.
- **Widget**: every screen in each state with fakes; gesture tests for overlays; semantics guidelines.
- **Golden** (alchemist, CI-stable fonts): text background styles, drawing + eraser, filters, full frame composition.
- **Native**: XCTest / JUnit only where logic is non-trivial (audio format normalisation, rect maths); primary proof via integration tests.
- **Integration** (`example/integration_test/`, iOS Simulator + Android emulator): real native export matrix — photo, photo+music, video (trim, mute, music, filter, overlay, rotated source, HEVC source, source without audio, mono music), cancel, forced failure (bad path, full-disk simulation via invalid dir); verify via `probe()` and thumbnails.
- **Device runs** (driven by me via the simulator tools / adb): full journey on iOS Simulator (gallery path; camera via fake capture flag in example because the simulator has no camera) and Android emulator (real virtual camera: photo, video, switch, zoom).
- **Code review**: ios-team + android-team panels on native code, then `/code-review` on the whole diff.

**Will not be verifiable here (reported as such):** real iOS camera capture, physical flash/torch, phone-call interruptions, real-device HDR/Dolby Vision capture, Samsung A-series Media3 behaviour, performance on low-end devices. No physical device is connected.

## 7. Open questions (defaults chosen if you don't say otherwise)

1. **Licence** — default **MIT**.
2. **`repository` / `homepage` in pubspec** — remote is `github.com/NarekManukyan/flutter_boilerplate`. Default: leave that URL out until the repo is renamed; you fill it in before publishing.
3. **Android package / iOS module id** — default `com.mabrook.story_creator_kit`.
4. **Capture gesture** — default: tap = photo, hold = video (hands-free lock by sliding onto a lock icon while holding).
5. **Default accent** — `#E4572E` (taken from your mock), overridable.

## 8. Out of scope (0.1.0)

Multi-clip stories, boomerang/layout/hands-free timers, AR effects/face filters, mentions/links/polls stickers, GIF search, cloud upload, close-friends/audience settings, web/desktop, the Post/Story/Reel mode bar.
