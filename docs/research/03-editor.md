# Research 3 — Editor UI, text tools, drawing tools, interactions

Date: 2026-09-25. Target: Flutter 3.47.1 / Dart 3.13.1, Android + iOS.
Scope: gestures, text overlays, freehand drawing, video preview/trim UI, coordinate model, accessibility, overlay rasterization at export resolution.
Method: pub.dev pages, GitHub issues, api.flutter.dev, and Flutter/flutter-packages source read via `gh api` (no repo changes). Relative dates ("N months ago") are as displayed by pub.dev on 2026-09-25.

---

## 0. Executive recommendation

| Area | Recommendation | Confidence |
|---|---|---|
| Overlay transforms | **Build** on one canvas-level `ScaleGestureRecognizer` (via `GestureDetector.onScale*`) with our own hit testing and `Matrix4`/TRS model. Do not adopt `matrix_gesture_detector` (unmaintained, Dart-3 incompatible). | High |
| Text rendering | **Build** a `TextOverlayPainter` over `TextPainter` + `computeLineMetrics()`/`getBoxesForSelection()`. Use `rounded_background_text` (BSD-3) only as a reference for the per-line rounded path algorithm. Same painter draws on screen and at export. | High |
| Fonts | Host supplies font families (asset fonts or bytes → `FontLoader`). `google_fonts` optional, only with `allowRuntimeFetching = false` + bundled files. | High |
| Drawing | **Build** a small stroke engine; **adopt `perfect_freehand` (MIT, active)** for outline generation. Do not adopt scribble / flutter_drawing_board / signature as the tool. | High |
| Video preview | `video_player` 2.14.0 (flutter.dev, BSD-3; Android on Media3 ExoPlayer). Trim preview = position-listener + `seekTo(start)` (no native range API). Music on a separate `just_audio` player. | Medium-high (audio session interplay needs a spike) |
| Thumbnails strip | Native frame extraction through our own platform channel (AVAssetImageGenerator / MediaMetadataRetriever), or reuse `pro_video_editor` if the export agent adopts it. Avoid `video_thumbnail` (unverified, stale). | Medium |
| Trimmer widget | **Build** (a trim bar is ~300 lines). `video_editor` is 3 years stale; `video_trimmer` pulls deps we don't want. | High |
| Coordinate model | Canonical story canvas **1080×1920 logical units (9:16)**; all overlay/stroke geometry stored in canvas units (or normalized 0..1); media placed into the canvas with its own transform (default "contain + blurred/gradient fill"). | High |
| Overlay rasterization | Re-paint the model with `ui.PictureRecorder` + `Canvas` at 1080×1920 (or scale factor) on the **root isolate** → `Picture.toImage` (async, not `toImageSync`) → `toByteData` → hand PNG/RGBA to native compositor. `RepaintBoundary.toImage(pixelRatio)` as a fallback only. | High |

---

## 1. Gesture handling for overlay transforms

### Flutter built-in: `ScaleGestureRecognizer`
- API: https://api.flutter.dev/flutter/gestures/ScaleUpdateDetails-class.html — `focalPoint`, `localFocalPoint`, `focalPointDelta`, `scale`, `horizontalScale`, `verticalScale`, `rotation`, `pointerCount`, `sourceTimeStamp`.
- Source (flutter/flutter `packages/flutter/lib/src/gestures/scale.dart`, read 2026-09-25):
  - `scale` = `_currentSpan / _initialSpan`; `rotation` = angle between the *initial* line of the first two pointers and the *current* line → both are **cumulative since the last (re)start**, not per-frame deltas.
  - `_reconfigure()` runs whenever a pointer is added or removed: it resets initial span/line/focal point and, if a gesture was started, fires `onEnd` then a new `onStart`. Consequence: **snapshot the overlay transform in `onStart` and compose `start ∘ (translate(focalΔ) · rotate(r) · scale(s))` around the focal point**; never accumulate `scale`/`rotation` per update. Handles 1→2→1 finger transitions without jumps.
  - Single-finger drags come through the same recognizer (`pointerCount == 1`, `scale == 1`, `rotation == 0`), so one recognizer covers move + pinch + rotate. Do not stack a `PanGestureRecognizer` on the same widget (arena conflict; scale is a superset of pan).
  - `trackpadScrollCausesScale` (default false) — irrelevant on phones.

### Packages evaluated
| Package | Version / date | License | Verdict |
|---|---|---|---|
| `matrix_gesture_detector` https://pub.dev/packages/matrix_gesture_detector | 0.1.0, **7 years ago**; 0.2.0-nullsafety.1 prerelease only; pub.dev marks **"Dart 3 incompatible"**, 25 pub points, license "Unknown", unverified uploader | Unknown | **Reject.** Idea (compose TRS into `Matrix4`) is trivial to reimplement. |
| `flutter_box_transform` https://pub.dev/packages/flutter_box_transform | 0.4.7, 18 months ago | Apache-2.0 | Handle-based resize/drag boxes (desktop-style). No rotation documented. Wrong UX for IG-style pinch. **Reject.** |
| `pro_image_editor` https://pub.dev/packages/pro_image_editor (GitHub hm21/pro_image_editor) | 14.4.1, published 2026-09-24; very active (6 releases in Sept 2026), 4 open issues, 391 stars | BSD-3-Clause | Full editor (text, paint, layers, emoji, stickers, filters, crop) with its own UI and themes (Grounded, Frosted-Glass, WhatsApp). Good *reference implementation* (`lib/features/main_editor/services/layer_interaction_manager.dart`). Adopting wholesale means adopting its UI, state model and export pipeline — conflicts with a library that must own its model + MobX-free reusable API + our own export. **Use as reference, don't depend.** |

### Recommended design
- **One `GestureDetector` over the whole story canvas** (not one per overlay). Instagram lets the second finger land *anywhere* on screen once the first finger is on a text; per-overlay detectors only receive pointers that hit that overlay, so pinching a small text is impossible. At `onScaleStart` hit-test overlays top-down in z-order using the inverse of each overlay's matrix applied to `localFocalPoint` (for 1 finger) — pick the topmost hit; if none, the gesture goes to the media (pan/zoom background) or is ignored.
- Hit testing: transform the touch point into the overlay's local space (`Matrix4.tryInvert`) and test against its local bounds **inflated to a minimum ~48 logical px** so small texts/emoji remain grabbable.
- **Z-order:** list order = paint order; bring-to-front on gesture start (move to end of list). Store an explicit `z` int or just list index in the model.
- **Taps** (edit text on tap) use a `TapGestureRecognizer` on the same detector; tap wins only if the scale slop isn't exceeded — the arena handles this.
- **Snapping guides:** during update, if overlay center is within ~8 logical px of canvas vertical/horizontal center (or safe-area edges), snap and show a guide line; rotation snaps to 0/90/180/270 within ~5°. Emit haptic once on entering a snap (`HapticFeedback.selectionClick()`), not every frame.
- **Trash zone:** shows while dragging; when the finger (use the *first pointer* position, not the focal point) enters the zone, scale overlay down + `HapticFeedback.mediumImpact()`; delete on release inside. Hide other chrome while dragging (IG behaviour).
- **Clamp** scale (e.g. 0.2–10× of canonical size) and keep overlay center inside canvas bounds so items can't be lost.
- Haptics: `HapticFeedback` in `flutter/services` (no package needed). Respect host config flag to disable.
- iOS back-swipe / Android predictive back: editor route should disable edge-swipe pop while a gesture is active (`PopScope`).

---

## 2. Text rendering and editing

### Per-line rounded highlight (Instagram "background" styles)
- APIs: `TextPainter.computeLineMetrics()` https://api.flutter.dev/flutter/painting/TextPainter/computeLineMetrics.html (per line: `left`, `baseline`, `ascent`, `descent`, `width`, `height`, `lineNumber`), `TextPainter.getBoxesForSelection()` https://api.flutter.dev/flutter/painting/TextPainter/getBoxesForSelection.html (with `BoxHeightStyle`/`BoxWidthStyle`), `getLineBoundary`, `textScaler`, `strutStyle`, `textHeightBehavior`, and `dispose()` (must be called; TextPainter holds native paragraph).
- Reference package: `rounded_background_text` https://pub.dev/packages/rounded_background_text — 0.6.0, **18 months ago**, **BSD-3-Clause**, verified publisher, 150 pub points. Paints per-line rounded backgrounds from `computeLineMetrics`, supports `Text`, `TextField`, `SelectableText`, `innerRadius`/`outerRadius`. Stale-ish and screen-only; recommend porting the path algorithm (with attribution per BSD-3) into our own painter rather than depending.
- Algorithm (build):
  1. Layout text once in **canonical canvas units** (see §5) with fixed `maxWidth` (e.g. 0.85 × canvas width minus padding) and `TextScaler.noScaling` — overlay text is *content*, not UI chrome, so OS text scaling must not change it (otherwise export ≠ preview). Editor chrome keeps normal scaling.
  2. For each line metric → rect `[left - hPad, baseline - ascent - vPad, left + width + hPad, baseline + descent + vPad]`; skip empty lines (width 0) but keep their vertical gap.
  3. Build one merged `Path`: for adjacent lines, where widths differ, use outer convex corners on the wider line and concave "inner" fillets where a narrower line meets a wider one (IG look). Radius = min(r, lineHeight/2, |Δwidth|/2) to avoid self-intersection when adjacent line widths are nearly equal (snap widths within ~r to equal).
  4. Styles: `none` (text colour only, optional shadow for legibility), `solid` (bg = selected colour, text auto black/white by contrast), `semiTransparent` (bg at ~50–60% alpha), `roundedHighlight` (the per-line merged path). `pro_image_editor`'s `LayerBackgroundMode` (`background`, `backgroundAndColor`, `backgroundAndColorWithOpacity`, `onlyColor`) confirms the same set of modes in the market leader (source: `lib/core/models/layers/enums/layer_background_mode.dart`).
  5. Alignment left/center/right → `TextAlign`; path is built from line metrics so it follows alignment automatically.
- **Identical layout at export:** do *not* re-layout at a bigger font size (hinting/rounding can change line breaks). Layout once in canonical units, then paint through `canvas.scale(exportScale)` + overlay matrix. Same `TextPainter` config → same line breaks at every resolution. Vector glyphs are re-rasterised at the scaled size, so export is sharp.
- **Parity gotcha (verified in `rendering/editable.dart`):** `RenderEditable` lays out with `maxWidth - _caretMargin` where `_caretMargin = _kCaretGap + cursorWidth`. So a `TextField` at width W breaks lines at `W - (1 + cursorWidth)`. The display painter must use the same effective width (or the editor must give the TextField `W + caretMargin`) — otherwise lines re-wrap when the user taps "Done".
- Also match: `strutStyle` (use a fixed strut to stop line height jumping between fonts), `textHeightBehavior`, `locale`, `fontFeatures`, emoji fallback font (same on screen and export because same engine and same isolate).

### Inline editing UX
- Enter edit: full-screen dim scrim over the canvas, the text overlay's transform animates to identity at center; `EditableText`/`TextField` (multiline, `maxLines: null`, `textAlign` from model, no decoration, `TextScaler.noScaling`) with our highlight painter behind it (as `rounded_background_text` does for TextField — it follows scroll offset). On done, animate back to the saved transform.
- Keyboard-anchored toolbar (`MediaQuery.viewInsetsOf(context).bottom`): font carousel (horizontal `ListView` of chips rendering each font name in its own face), colour palette row (host-configurable list + eyedropper later), alignment toggle (cycles left→center→right), background-style toggle (cycles the 4 styles), size slider (vertical, left edge, IG-style).
- Empty text on "Done" → remove overlay. Undo of text edits: record the whole overlay snapshot before/after edit as one command.

### Font supply
- **Host-supplied families** via config: `StoryFont(id, displayName, family, {package})`. Asset fonts declared in the host's pubspec (or the library's own pubspec under `fonts:` with `package:` prefix) work everywhere including export.
- Runtime/downloaded fonts: `FontLoader(family)..addFont(Future<ByteData>)..load()` https://api.flutter.dev/flutter/services/FontLoader-class.html (or `dart:ui` `loadFontFromList`). Load before the font is shown in the carousel; loading a family is engine-global. Must be on the root isolate (see §7).
- `google_fonts` https://pub.dev/packages/google_fonts — **8.2.1, 54 days ago, BSD-3-Clause, flutter.dev**, Dart ≥3.10. Fetches over HTTP at runtime and caches to disk; bundled asset files take precedence. For a library: runtime fetching is a privacy/offline/export-determinism risk (a font that hasn't downloaded yet renders in fallback, then export uses the real font = mismatch). If offered, set `GoogleFonts.config.allowRuntimeFetching = false` and require bundled files; fonts themselves are mostly OFL → host must register licences with `LicenseRegistry`.
- Font availability must be "awaited" before export: keep a `FontRegistry` with `Future<void> ensureLoaded(fontId)` and block export until all fonts used by overlays are loaded.

---

## 3. Freehand drawing

### Packages
| Package | Version / date | License | Notes | Verdict |
|---|---|---|---|---|
| `perfect_freehand` https://pub.dev/packages/perfect_freehand (github.com/steveruizok/perfect-freehand-dart) | **2.5.2+1, 8 months ago**; releases 2.4.0→2.5.2 over the last 13 months | **MIT** | Pure Dart. `getStroke(points, options)` → outline polygon; `StrokeOptions` (size, thinning, smoothing, streamline, simulatePressure, start/end taper + caps); `getStrokePoints` / `getStrokeOutlinePoints` for staged use. No Flutter widget coupling. | **Adopt** as geometry engine. |
| `scribble` https://pub.dev/packages/scribble | 0.10.0+1, **2 years ago** | MIT | Uses perfect_freehand, undo/redo, line eraser, JSON, pressure. Depends on `freezed_annotation`, `value_notifier_tools`. Owns its own notifier/state and widget. | Stale; reference only. |
| `flutter_drawing_board` https://pub.dev/packages/flutter_drawing_board | 1.0.1+2, 8 months ago | MIT | fluttercandies; shapes, eraser, undo/redo, JSON, pan/zoom board, own toolbar. | Whiteboard-oriented, own board transform model; reject as dependency. |
| `signature` https://pub.dev/packages/signature | 6.4.0, 58 days ago | MIT | Signature pad; single colour, no eraser/undo stack depth, depends on `flutter_svg`. | Wrong tool. |

### Build plan
- **Model:** `Stroke { id, brush: {type: pen|marker|neon|eraser, color, widthCanvasUnits, opacity}, points: Float32List (x,y,pressure interleaved) in canvas units }`. Width stored in canvas units (not screen px) so export scales. Serialize as compact binary/JSON.
- **Capture:** `Listener`/`onPanUpdate` on the drawing layer only while the draw tool is active; convert `localPosition` → canvas units via inverse view transform. Drop points closer than ~0.5–1 canvas px to the previous (cuts point count heavily). Use `PointerEvent.pressure` when `kind == stylus`, else `simulatePressure`.
- **Smoothing:** perfect_freehand streamline/smoothing; fill the outline polygon as a `Path` (`addPolygon` or quadratic mid-point curves between outline points for smoother edges).
- **Eraser:** draw strokes into `canvas.saveLayer(bounds, Paint())`, eraser strokes with `Paint()..blendMode = BlendMode.clear`, then `restore()`. The layer must contain *only* drawing (not the media) or clear punches through to black. Known costs/risks: BlendMode.clear eraser reported "very slow" when redrawing everything each frame (https://github.com/flutter/flutter/issues/126789, open since 2023-05); backend differences for clear/srcOut/dstOut/xor (https://github.com/flutter/flutter/issues/118867, mostly CanvasKit/web). Mitigation = caching below. Alternative "object eraser" (delete whole strokes on touch) is cheaper and worth offering too (IG has pixel eraser).
- **Performance:** keep committed strokes in a cached raster: after each stroke ends, re-record committed strokes into a `ui.Picture` and rasterize once (`picture.toImage` at device pixel size) — paint that image + only the *live* stroke each frame. Wrap the drawing layer in its own `RepaintBoundary` and drive repaints with a `Listenable` passed to `CustomPainter(repaint:)` (no widget rebuilds per pointer event). `pro_image_editor` 14.2.0 (2026-09-11) moved to exactly this ("draw static paint layers from a cached raster"). Cap per-stroke point count (split very long strokes into segments).
- **Undo/redo:** command stack at editor level (not per tool) so undo works across tools: `AddStroke`, `ClearAll`, `AddOverlay`, `TransformOverlay(before, after)`, `EditText(before, after)`, `DeleteOverlay`. Redo stack cleared on new command. Drawing tool's own undo button can filter to stroke commands if UX requires (IG's draw undo is draw-only; decide in UX).
- **Export:** replay strokes into the export canvas under `canvas.scale(exportScale)` — vector, resolution independent. Eraser layer repeated identically.

---

## 4. Video playback, trim preview, music, thumbnails

### `video_player`
- https://pub.dev/packages/video_player — **2.14.0 (≈44 days ago, ~Aug 2026), BSD-3-Clause, flutter.dev**, Android SDK 24+, iOS 13+. Min Flutter 3.38 / Dart 3.10 since 2.11/2.12.
- Android impl `video_player_android` 2.12.2 (22 days ago): **already on Media3 ExoPlayer** (migrated in 2.5.0 to Media3 1.3.1; now `androidx.media3` 1.9.2 as of 2.9.4); 2.9.6 requires Flutter 3.44/Dart 3.12 and built-in Kotlin for AGP 9; platform-view mode exists but is **not recommended on Android** (https://github.com/flutter/flutter/issues/164899) → use the default texture view. 2.12.2 fixed anamorphic (non-square PAR) display size — relevant for correct aspect in the coordinate model.
- Recent API: `setLooping`, `seekTo`, `setVolume`, `setPlaybackSpeed`, `VideoPlayerOptions(mixWithOthers: true)`, audio/video track selection (2.11/2.14), `backBufferDurationMs`. Position updates every 100 ms (since 2.9.4).
- Seek precision (source, 2026-09-25): iOS `FVPVideoPlayer.m` seeks with `toleranceBefore/After = kCMTimeZero` (frame-exact, except at end). Android calls `exoPlayer.seekTo(position)` with default `SeekParameters` (exact). Frame-exact seeks are slow for scrubbing on long-GOP footage; keyframe-seek option request is still open/P3 (https://github.com/flutter/flutter/issues/72416). For scrubbing: throttle seeks (seek only after the previous completes, ~every 50–100 ms) and show the thumbnail-strip frame under the finger meanwhile.
- **No playback-range API.** Trim preview: listen to controller, when `position >= trimEnd` → `seekTo(trimStart)`; keep native `setLooping(false)`. With 100 ms position granularity expect up to ~100 ms overshoot past `trimEnd` (acceptable for preview; exact trim happens at export). Optionally a `Ticker` that predicts `position + elapsed` to pause earlier.
- **Music at independent volume:** `video_player.setVolume(v)` for original audio (0 = mute) + separate music player. Android: `mixWithOthers` toggles ExoPlayer audio focus handling (`setAudioAttributes(..., handleAudioFocus: !mixWithOthers)`) — must be `mixWithOthers: true` or ExoPlayer will pause when the music player takes focus. iOS: AVAudioSession is process-global; `just_audio` + `audio_session` also configure it → **spike needed** to confirm both play together (set session once, category playback + mixWithOthers, from the library).
- Music player: `just_audio` https://pub.dev/packages/just_audio — **0.10.6, ~2 months ago, verified ryanheise.com, Flutter Favorite**, supports clipping (`ClippingAudioSource`/`setClip`), looping, volume. License to confirm on page (historically MIT). Owned by the music agent; editor just needs a `MusicPreview` interface (play/pause/seek synced to video position).

### Thumbnail strip
| Option | Version / date | License | Notes |
|---|---|---|---|
| `video_thumbnail` https://pub.dev/packages/video_thumbnail | 0.5.6, 16 months ago (previous release 4 yrs earlier) | MIT | Unverified uploader; one frame per call (spawns retriever each time → slow for 10–20 frames); iOS WebP perf note. Avoid. |
| `get_thumbnail_video` https://pub.dev/packages/get_thumbnail_video | 0.7.3, 22 months ago | MIT | Fork of video_thumbnail; unverified. Avoid. |
| `fc_native_video_thumbnail` https://pub.dev/packages/fc_native_video_thumbnail | 3.0.1, 3 months ago | BSD-3-Clause | Verified publisher, native APIs, maintained; Android seek needs URI source; still one frame per call. Acceptable fallback. |
| `pro_video_editor` https://pub.dev/packages/pro_video_editor | 2.16.0, published 2026-09-25 | BSD-3-Clause | Native (AVFoundation / **Media3 Transformer**, no FFmpeg); trim, overlays with timing, thumbnails, waveform, audio. If the export agent picks it, reuse its thumbnail API for the strip. |
| Own platform channel | — | — | iOS `AVAssetImageGenerator` batch (`generateCGImagesAsynchronously(forTimes:)` / `images(for:)`), `maximumSize` ≈ strip cell × DPR, `appliesPreferredTrackTransform = true`; Android `MediaMetadataRetriever.getScaledFrameAtTime(t, OPTION_CLOSEST_SYNC, w, h)` (API 27+) on a background thread with one retriever instance. Fast, one call returns N frames. **Recommended** if not using pro_video_editor. |
- Don't use `video_player` for frames (no frame-grab API).

### Trimmer widgets
| Package | Version / date | License | Verdict |
|---|---|---|---|
| `video_editor` https://pub.dev/packages/video_editor | 3.0.0, **3 years ago** | MIT | TrimSlider/TrimTimeline/Crop/Cover; depends on `video_thumbnail` ^0.5.3 and old `video_player` ^2.6.1; FFmpeg removed in 3.0 (generates commands only). Stale → reject; reference for TrimSlider UX. |
| `video_trimmer` https://pub.dev/packages/video_trimmer | 5.0.0, 17 months ago | MIT | Uses `flutter_native_video_trimmer`, `get_thumbnail_video`, `image`, `intl`, `transparent_image`. Bundles export logic we'd duplicate. Reject. |
- **Build** the trim bar: thumbnails row + two handles (min duration, max = story limit, e.g. 15/60 s, host-configurable) + playhead; handles ≥48 dp hit area; drag handle → pause + throttled seek; release → loop within range.

---

## 5. Coordinate model

- **Canonical canvas:** 1080×1920 "canvas units" (9:16). Instagram's story spec is 1080×1920 (min 600×1067) — widely documented. All overlay transforms, text layout widths/font sizes, stroke points and widths are stored in canvas units (or normalized 0..1 with the 9:16 aspect fixed). Export at any resolution `W×H` with the same aspect = `canvas.scale(W / 1080)`.
- **View transform:** screen shows the canvas with `BoxFit.contain` inside the safe area (IG shows full 9:16 with rounded corners on tall phones; on 19.5:9+ phones there's spare space above/below for chrome). `viewScale = min(viewW/1080, viewH/1920)`, `viewOffset` centers it. Screen→canvas: `(p - viewOffset) / viewScale`. Never `BoxFit.cover` for the canvas itself, or export shows content the user never saw.
- **Media placement inside canvas:** media has its own transform (`MediaTransform { scale, rotation, translation }` in canvas units), default:
  - 9:16 (±~2%) media → `cover` (fills, tiny crop).
  - Other aspect → `contain` centered, background = **blurred scaled-up copy of the media** (cover + Gaussian blur, `ImageFilter.blur`) or **two-colour vertical gradient from the media's dominant colours** (IG's "share to story" gradient; tapping cycles options). User can pinch the media (IG allows).
  - Account for EXIF orientation (photos) and `preferredTransform`/rotation + pixel aspect ratio (video; see video_player_android 2.12.2 PAR fix) when computing intrinsic size.
- **Media pixels mapping (for export agent):** `canvasRect_of_media = mediaTransform.apply(Rect(0,0,mw,mh) * baseFitScale)`; overlay rasterized at `W×H` is composited over the media composed at `W×H` with the same transform → no per-pixel mapping needed as long as export composes the media into the story canvas (not burns overlay onto the source-resolution media). Decide jointly with export agent: output = canvas-sized story (recommended), not source-sized.
- **Dominant colours:** `palette_generator` https://pub.dev/packages/palette_generator — 0.3.3+7, 16 months ago, BSD-3, **Discontinued** (https://github.com/flutter/flutter/issues/162963, discontinuation tracked in #162960). Replacements: `material_color_utilities` https://pub.dev/packages/material_color_utilities (0.13.1, 45 days ago, Apache-2.0, material.io; QuantizerCelebi + Score) — already a transitive Flutter dependency; or `ColorScheme.fromImageProvider` (downscales to 112×112, Score-based) https://api.flutter.dev/flutter/material/ColorScheme/fromImageProvider.html. For a gradient: downscale to ~64×64, quantize the top third and bottom third separately → two colours. For video, use the first thumbnail frame.

---

## 6. Accessibility

- Targets: Flutter checklist requires ≥48×48 tappable targets (https://docs.flutter.dev/ui/accessibility-and-internationalization/accessibility); iOS HIG 44×44 pt. Use 48 everywhere; test with `meetsGuideline(androidTapTargetGuideline)`, `iOSTapTargetGuideline`, `labeledTapTargetGuideline`, `textContrastGuideline` in widget tests.
- Every tool button: `Semantics(button: true, label:, selected:/toggled:)` via `Tooltip`/`IconButton` semantics; the colour swatches expose colour names (localized) and selected state; font carousel items announce font name; sliders (`Slider` or custom with `Semantics(slider, value, increasedValue, onIncrease...)`).
- **Gesture-only features need alternatives:** each overlay is a semantics node (label = text content / "Drawing" / sticker name) with `CustomSemanticsAction`s (https://api.flutter.dev/flutter/semantics/CustomSemanticsAction-class.html — VoiceOver actions rotor / TalkBack actions menu): Move up/down/left/right (step 5% canvas), Bigger/Smaller, Rotate ±15°, Bring to front, Edit, Delete. Also `onTap` → edit. When `MediaQuery.accessibleNavigationOf(context)` is true, show a visible "Adjust" sheet with the same controls (also helps switch-control users). Drawing is inherently visual — provide undo/clear with labels; no alternative required beyond that.
- Trim: expose start/end handles as sliders with value "0:03.2" and adjustable increments (0.1 s / 1 s).
- Reduce motion: `MediaQuery.disableAnimationsOf(context)` → skip scale/fly-in animations for edit mode, trash-zone bounce, snapping animation. Haptics are separate (keep, but host can disable).
- Text content colour contrast: auto-pick black/white text over solid backgrounds by WCAG contrast; not enforceable for text over media.
- Overlay text uses `TextScaler.noScaling` (content must match export); editor chrome must respect text scaling up to 200% without clipping.

---

## 7. Rasterizing the overlay layer at export resolution

### Options
1. **`ui.PictureRecorder` + `Canvas` replay of the model (recommended).** `canvas.scale(W/1080)` then paint in z-order: text (same `TextOverlayPainter`), strokes (saveLayer + clear eraser), stickers (`drawImageRect` from original-resolution sticker asset, not the screen-decoded thumbnail). `picture.toImage(W, H)` → `ui.Image` → `toByteData(format: png)` or `rawRgba`. Pros: resolution independent, no widget tree, no dependency on on-screen size/DPR, deterministic, testable with golden files, can render off-screen after the editor is gone. Cons: every overlay type needs a paint implementation (which we need anyway for the on-screen `CustomPainter` — share it).
2. **`RepaintBoundary.toImage(pixelRatio: W / logicalCanvasWidth)`** https://api.flutter.dev/flutter/rendering/RenderRepaintBoundary/toImage.html — requires the boundary to be painted (`debugNeedsPaint == false`), i.e. mounted and laid out on screen at on-screen logical size; pixelRatio upscaling re-rasterizes vectors so it is sharp, but it captures whatever is in the tree (selection handles, guides, trash must be hidden first) and platform views/video textures are not the thing we want anyway. `pro_image_editor` uses this capture approach (`content_recorder_controller.dart`: pixelRatio from image info vs `MediaQuery.devicePixelRatioOf`, with an "output too large" check and isolate encoding). OK as fallback / for arbitrary host widgets (custom sticker widgets) only.

### Threading / isolates
- `dart:ui` drawing (`PictureRecorder`, `Canvas`, `Paragraph`/`TextPainter.layout`) is **root-isolate only** — "UI actions are only available on root isolate" (https://github.com/flutter/flutter/issues/92575 closed with no linked PR; https://github.com/flutter/flutter/issues/79353). Fonts registered via `FontLoader`/assets live in the engine and are available to the root isolate's painters. `BackgroundIsolateBinaryMessenger` (3.7+) only enables platform channels, not drawing.
- So: record + `toImage` on the root isolate (GPU raster thread does the heavy work; recording a few hundred strokes is milliseconds), then `toByteData(png)` (engine does encoding off the UI thread) or `rawRgba` → hand bytes to native / a background isolate for file writing.
- **Use `Picture.toImage` (async), not `toImageSync`:** open engine issue (2026-08-18, Flutter 3.44, iOS Impeller) — `toImageSync` rasterizes into a disabled GPU context after background/foreground and yields solid magenta; async `toImage` defers until GPU is available (https://github.com/flutter/flutter/issues/191255). Also gate export start on `AppLifecycleState.resumed`.
- Size limits: historical 4096 hard limit on `Picture.toImage` (https://github.com/flutter/flutter/issues/28705, Flutter 1.2 era) — no longer documented, but GPU max texture size still applies (commonly 4096–16384 on phones). 1080×1920 and even 2160×3840 are safe; add a guard that clamps to 4096 on the long side unless verified on device.
- Memory: 1080×1920 RGBA = 8.3 MB per `ui.Image`; 4K = 33 MB. Dispose `ui.Image`/`Picture` immediately after encoding.
- **Video:** render the overlay **once** as a transparent 1080×1920 PNG (static overlays) and let native composition burn it in (iOS `AVVideoCompositionCoreAnimationTool`/CIFilter compositor; Android Media3 Transformer `OverlayEffect` + `BitmapOverlay`) — owned by the export agent; `pro_video_editor` already does image-overlay layers natively. Per-frame Flutter rasterization for animated overlays would be ~250 MB/s at 30 fps and is out of scope for v1.

---

## 8. Cross-cutting: edits persist across tool switches

- Single `StoryEditorController` (plain `ChangeNotifier`/`ValueNotifier`s — no MobX dependency inside a reusable library) owning an immutable `StoryDocument { media, mediaTransform, background, overlays: List<Overlay>, strokes: List<Stroke>, trim, music }` + command stack. Tools are views over the document; switching tools never disposes document data. Document is serializable (JSON) so host can persist drafts and export can run from it.
- Paint layers: media → background fill → drawing layer (own RepaintBoundary) → overlays (own RepaintBoundary per overlay or one painter) → transient chrome (guides, trash, selection) — chrome never goes into the export painter.

---

## 9. Key risks

1. **Text layout parity** between TextField (caret margin), display painter and export painter — mitigate with one shared layout function + golden tests at 1× and 3×.
2. **iOS audio session** when video_player and just_audio play simultaneously — spike on device.
3. **Eraser cost** with saveLayer + BlendMode.clear on long drawings — raster cache committed strokes.
4. **Trim preview overshoot** (~100 ms) and slow frame-exact scrubbing on long-GOP video.
5. **Font loading before export** (runtime fonts) — `FontRegistry.ensureLoaded`.
6. **toImageSync magenta bug on iOS Impeller** — use async `toImage`, gate on lifecycle.
7. Canvas-level single gesture detector must coexist with draw mode (disable transform gestures while drawing) and with the text edit scrim.

## 10. Sources
- https://pub.dev/packages/video_player , https://pub.dev/packages/video_player/changelog
- https://pub.dev/packages/video_player_android , https://pub.dev/packages/video_player_android/changelog
- flutter/packages source: `video_player_avfoundation/.../FVPVideoPlayer.m` (seek tolerance), `video_player_android/.../VideoPlayer.java` (Media3, audio attributes, repeat mode)
- https://pub.dev/packages/matrix_gesture_detector
- https://pub.dev/packages/flutter_box_transform
- https://pub.dev/packages/pro_image_editor , https://github.com/hm21/pro_image_editor , https://github.com/hm21/pro_image_editor/releases
- https://pub.dev/packages/pro_video_editor
- https://pub.dev/packages/perfect_freehand , https://pub.dev/packages/perfect_freehand/versions
- https://pub.dev/packages/scribble , https://pub.dev/packages/flutter_drawing_board , https://pub.dev/packages/signature
- https://pub.dev/packages/rounded_background_text , https://github.com/bdlukaa/rounded_background_text
- https://pub.dev/packages/google_fonts , https://pub.dev/packages/google_fonts/versions
- https://api.flutter.dev/flutter/services/FontLoader-class.html
- https://api.flutter.dev/flutter/gestures/ScaleUpdateDetails-class.html ; flutter/flutter `gestures/scale.dart`, `rendering/editable.dart`
- https://api.flutter.dev/flutter/painting/TextPainter-class.html , .../computeLineMetrics.html , .../getBoxesForSelection.html
- https://pub.dev/packages/video_editor , https://pub.dev/packages/video_trimmer
- https://pub.dev/packages/video_thumbnail , https://pub.dev/packages/get_thumbnail_video , https://pub.dev/packages/fc_native_video_thumbnail
- https://pub.dev/packages/just_audio
- https://pub.dev/packages/palette_generator , https://github.com/flutter/flutter/issues/162963 , https://pub.dev/packages/material_color_utilities , https://api.flutter.dev/flutter/material/ColorScheme/fromImageProvider.html
- https://docs.flutter.dev/ui/accessibility-and-internationalization/accessibility , https://api.flutter.dev/flutter/semantics/CustomSemanticsAction-class.html
- https://api.flutter.dev/flutter/dart-ui/Picture/toImage.html , https://api.flutter.dev/flutter/rendering/RenderRepaintBoundary/toImage.html
- https://github.com/flutter/flutter/issues/191255 , /92575 , /79353 , /28705 , /126789 , /118867 , /72416 , /164899
