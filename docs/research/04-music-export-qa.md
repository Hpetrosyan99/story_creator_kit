# Research 4: Music, rendering/export, integration testing, QA

Agent 4. Observed 2026-09-25. Toolchain assumed: Flutter 3.47.1 / Dart 3.13.1. Research only, no repo changes.
Every version and date below was read from a primary source today unless marked *(unverified)*.

---

## 0. Recommendation (TL;DR)

| Area | Recommendation |
|---|---|
| **Export engine** | **Build our own native plugin (a federated package inside the library): AVFoundation on iOS, Media3 Transformer 1.11.x on Android.** Keep `pro_video_editor` (BSD-3) as the fallback, or as a reference implementation to read. Do **not** ship FFmpeg. |
| Photo → JPEG | Native compositing in the same plugin: base photo + overlay PNG → JPEG, using `UIGraphicsImageRenderer`/`CGImageDestination` on iOS and `Bitmap` + `Canvas` + `compress(JPEG)` on Android, with EXIF orientation applied. `dart:ui` cannot encode JPEG. |
| Music preview | `just_audio` 0.10.6 (MIT) using `setClip(start,end)`, `LoopMode.one` and `setVolume`. Configure the session with `audio_session` 0.2.4 (MIT). |
| Music files for export | Download host URLs to the app cache with our own downloader, keyed by track id. Do **not** use `LockCachingAudioSource` for the export file. |
| Waveform | Let the host supply precomputed peaks in the catalog model (preferred). Fall back to native extraction in our plugin (AVAssetReader → PCM on iOS, MediaExtractor + MediaCodec on Android) that returns N normalized peaks. Draw the waveform with our own `CustomPainter` scrubber. `just_waveform` works but has had no release since 2025-03. |
| Sample music | Self-generated tones and loops (no licence risk) plus 3–4 verified CC0 tracks (Komiku on FMA, OpenGameArt CC0). Avoid Pixabay: its licence bans standalone redistribution. FreePD has closed. |
| Tests | `integration_test` (Flutter SDK) for the export pipeline, checked with a native **probe** method (duration, size, rotation, hasAudio, codec). Patrol 4.10.0 (Apache-2.0) for permission dialogs and the gallery picker. Maestro cli-2.10.0 for E2E, matching the repo's convention. |

---

## 1. FFmpeg route

### 1.1 Upstream `arthenica/ffmpeg-kit` — retired
- Retired **2025-01-06**. Binaries older than 6.0 were removed **2025-02-01** and v6.0 was removed **2025-04-01** from Maven Central and CocoaPods. The stated reason was patent and licensing risk after MPEG LA became Via-LA, on advice from an IP law firm.
  Sources: <https://tanersener.medium.com/saying-goodbye-to-ffmpegkit-33ae939767e1> (HTTP 403 to fetch; the content is quoted in search results and in <https://www.itpathsolutions.com/ffmpegkit-shutdown-what-to-do-next>), <https://github.com/devhyper/open-video-editor/issues/119>
- GitHub repo **archived 2026-07-02** (read-only). The README points to **FFmpegKitNext**. <https://github.com/arthenica/ffmpeg-kit>
- pub.dev `ffmpeg_kit_flutter` 6.0.3 (2023-09-18) and `ffmpeg_kit_flutter_min` are marked **isDiscontinued: true**.
- **FFmpegKitNext** (<https://github.com/arthenica/ffmpeg-kit-next>, LGPL-3.0, 141★, pushed 2026-09-14) is the official continuation, but its README says it *"does not publish ready-to-use packages to Maven Central, CocoaPods, pub.dev, or npm"*. It is **source-only**, so you build and host the binaries yourself. Latest release 9.0.0 (FFmpeg 9.0.1) on 2026-08-24. Its README also warns that FFmpeg, x264 and x265 may implement patented codecs, and tells you to consult counsel.

### 1.2 Community fork `ffmpeg_kit_flutter_new` (sk3llo / Anton Karpenko)
- pub.dev: <https://pub.dev/packages/ffmpeg_kit_flutter_new>. **4.6.2, published 2026-07-30**, verified publisher antonkarpenko.com, 203 likes, about 39.8k downloads in 30 days. Bundles FFmpeg **8.1.2**.
- Repo: <https://github.com/sk3llo/ffmpeg_kit_flutter>. Not archived, pushed 2026-07-30, 180★, 9 open issues, LGPL-3.0. Release cadence is bursty: 8 releases between 07-13 and 07-30, then nothing for about 8 weeks.
- Eight variants, all republished 2026-07-30:
  - GPL-free: `_min` 3.6.2, `_https` 2.6.2, `_audio` 2.5.2, `_video` 2.5.2, `_full` 2.5.2
  - GPL: `_min_gpl`, `_https_gpl`, and the base `ffmpeg_kit_flutter_new`, which is **full + GPL (x264/x265/xvid/vid.stab) and therefore effectively GPL-3.0**
  - Unrelated name clash: `ffmpeg_kit_flutter_new_gpl` 1.6.5 (2025-05-28) comes from a different fork (ganlong-2016) and looks stale.
- Hosting:
  - Android AARs are on **Maven Central** as `com.antonkarpenko:ffmpeg-kit-{variant}:2.2.1`.
  - iOS frameworks are downloaded at `pod install` from **GitHub Releases** (`github.com/sk3llo/ffmpeg_kit_flutter/releases/download/8.1.2-{variant}/…zip`) by `scripts/setup_ios.sh`. SPM is supported too. These are **dynamic** Mach-O frameworks (checked with `file`/`lipo`): x86_64, arm64 and arm64e.
  - Supply-chain risk: the iOS binaries sit on one person's GitHub release. `FFMPEG_KIT_IOS_URL` lets you point at a mirror.
- Minimums: Android API 24, iOS 14.0, Kotlin 1.8.22, AGP 8.7, compileSdk 35.
- **16 KB pages: compliant.** I parsed the ELF `PT_LOAD` p_align of every arm64 `.so` in `ffmpeg-kit-full-2.2.1.aar` and got 16384 for all of them, including `libc++_shared.so`.
- **Hardware encoding:**
  - Android: every variant contains `h264_mediacodec`, `hevc_mediacodec` and `aac_mediacodec` (found with `strings` on libavcodec). No variant bundles `libx264` except the GPL ones.
  - iOS: **VideoToolbox is enabled only in `_full` and `_full_gpl`** (per the README table). With `_min`, `_https`, `_audio` or `_video` an LGPL build has **no H.264 encoder on iOS**. So the smallest LGPL build that works for H.264 MP4 on iOS is `_full`.
- **Size**, measured from Maven and the release zips (numbers are for the whole AAR/zip unless a slice is named):

  | Variant | Android AAR | arm64-v8a .so (uncompressed / deflated) | armeabi-v7a (incl. neon) | x86_64 | iOS zip (fat) | iOS arm64 slice (uncompressed / zipped) |
  |---|---|---|---|---|---|---|
  | min (LGPL) | 38.5 MB | 14.7 / 7.3 MB | 27.9 MB | 16.0 MB | 23.2 MB | — |
  | **full (LGPL)** | 69.8 MB | **26.7 / 13.3 MB** | 48.7 MB | 29.3 MB | 49.3 MB | **29 / 15 MB** |
  | full-gpl | 108.9 MB | 42.1 / 20.6 MB | 78.2 MB | 48.4 MB | 58.7 MB | — |

  In practice, `_full` adds about **13 MB to the Play download and about 27 MB installed per ABI**, and about **15 MB to the App Store download and about 29 MB installed** on arm64.

### 1.3 Licence and store compliance (not legal advice)
- **GPL variants.** The whole app must be GPL-3.0 compatible, which means shipping source for the entire app. That is incompatible with closed-source host apps. GPL is also widely considered to conflict with App Store usage rules (the VLC removal in 2011 is the precedent). → **Unacceptable for a reusable library whose hosts are commercial apps.**
- **LGPL variants.** You must:
  - use dynamic linking (the fork's iOS frameworks and Android `.so` are dynamic ✓),
  - ship the LGPL text and notices,
  - offer the corresponding FFmpeg source and build recipe (a "source offer"),
  - allow relinking. On iOS that is contested because the user cannot swap a framework inside a signed IPA. Many apps ship LGPL FFmpeg anyway, but it stays a legal grey area.
- **Patents.** H.264, HEVC and AAC *software* implementations inside FFmpeg are the root cause of the retirement. Using `h264_videotoolbox` or `h264_mediacodec` with the OS-provided AAC encoder keeps you on OS-licensed codecs, but the FFmpeg decoders and parsers still ship in the binary. The native route ships **no codec code at all**.

### 1.4 FFmpeg verdict
Workable technically: filter_complex does overlay, atrim/volume/amix and `-loop 1` photo→video in one command, with statistics callbacks for progress and `FFmpegKit.cancel(sessionId)`. But you pay for it:
- +13–15 MB download per platform,
- LGPL obligations pushed onto every host app,
- patent exposure,
- a single community maintainer.

**Not recommended** as the primary engine.

---

## 2. Native route

### 2.1 iOS — AVFoundation
All platform data comes from Apple doc JSON (`developer.apple.com/tutorials/data/documentation/avfoundation/…`), read 2026-09-25.

| Need | API | Status |
|---|---|---|
| Trim, multi-track | `AVMutableComposition` + `insertTimeRange(_:of:at:)`: video track, original audio track, music track (music `timeRange` = the selected segment) | not deprecated |
| Per-track volume / mute | `AVMutableAudioMix` + `AVMutableAudioMixInputParameters.setVolume(_:at:)` (or `setVolumeRamp` for fades) | not deprecated |
| Overlay PNG | `AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer:in:)` with a `CALayer` whose `contents` is the overlay `CGImage` | the initializer is **deprecated in iOS 27.0**. Replacement: `init(configuration: AVVideoCompositionCoreAnimationTool.Configuration)` |
| Video composition | `AVMutableVideoComposition` + `AVMutableVideoCompositionLayerInstruction` (`setTransform` with `preferredTransform`) | **deprecated iOS 26.0**. Replacement: `AVVideoComposition(configuration:)` with `AVVideoComposition.Configuration` (iOS 26+) |
| CIFilter alternative | `AVMutableVideoComposition(asset:applyingCIFiltersWithHandler:)` composites the overlay `CIImage` over `request.sourceImage` | **deprecated iOS 18.0**. Use the async `videoComposition(with:applyingCIFiltersWithHandler:completionHandler:)` |
| Export | `AVAssetExportSession.export(to:as:isolation:)` (async; doc lists availability back to iOS 13) | current |
| Progress | `states(updateInterval:)` (**iOS 18+**). Before iOS 18, poll `progress` | `progress` is **deprecated iOS 27.0** ("Use progressStates(updateInterval:)") |
| Cancel | `Task.cancel()` on the task running `export(to:as:)`, which throws. Before iOS 18, `cancelExport()` | `cancelExport()` **deprecated iOS 27.0** |
| Photo + music → video | `AVAssetWriter` + `AVAssetWriterInputPixelBufferAdaptor` writes the composed still frame. Write a frame at t=0 and a few more (e.g. 1–30 fps) up to the segment duration, then mux the music with a second pass through `AVMutableComposition` + export, or with an `AVAssetWriter` audio input fed by `AVAssetReader` | the adaptor is **deprecated iOS 27.0**. Replacement: `AVAssetWriter.inputPixelBufferReceiver(for:pixelBufferAttributes:)`. `AVAssetWriter` itself is not deprecated |

Implementation notes:
- **Orientation.** Read `videoTrack.preferredTransform` (async `load(.preferredTransform)`). Compute `renderSize` from `naturalSize.applying(transform)` using absolute values. Apply the transform in the layer instruction. Lay out the overlay in *display* space: in the CA tool the parent-layer origin is bottom-left, so flip the geometry.
- **HEVC/HDR input** (iPhone HLG/Dolby Vision). For SDR story output, set `videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2`, `colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2`, `colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2`, and use the `AVAssetExportPresetHighestQuality` or 1920x1080 H.264 preset. To keep HDR, use the HEVC presets instead. HDR→SDR through a composition works, but verify the tone on devices.
- **Known pain.** `AVVideoCompositionCoreAnimationTool` has a long record of black frames, freezes and preview/simulator quirks (Apple forums threads 68702, 726146, 740103). It also cannot be used with `AVPlayer` preview. That doesn't matter here: the preview is Flutter-rendered and the overlay is a static PNG. A **CIFilter or custom `AVVideoCompositing`** overlay is the more robust choice and I recommend it.
- **Deployment.** The iOS min will likely be 15 or 16, so the plugin needs `if #available(iOS 18/26/27)` branches (old API vs new API). That adds roughly 1–2 days of care.

### 2.2 Android — Media3 Transformer
- Current stable **1.11.1 (2026-09-10)**. 1.11.0 shipped 2026-08-05. No alpha/beta is open. **minSdk 23** (since 1.9.0). The default muxer is `InAppMp4Muxer` (since 1.9.0). Pure Java/Kotlin, **no .so, so no 16 KB concern**. Sources: <https://developer.android.com/jetpack/androidx/releases/media3> and <https://raw.githubusercontent.com/androidx/media/release/RELEASENOTES.md>
- Artifacts: `androidx.media3:media3-transformer`, `media3-effect` and `media3-common`, all `1.11.1`. Most of the needed classes are **`@UnstableApi`**, so use an opt-in annotation and expect API drift between minors (e.g. 1.10 removed `ChannelMixingMatrix.create()` in favour of `createForConstantGain()`).

| Need | API (verified in source on the `release` branch) |
|---|---|
| Trim | `MediaItem.ClippingConfiguration.Builder().setStartPositionMs().setEndPositionMs()` (also used to pick the music segment) |
| Overlay PNG | `OverlayEffect(ImmutableList.of(BitmapOverlay.createStaticBitmapOverlay(bitmap, StaticOverlaySettings)))` in `Effects(audioProcessors, videoEffects)`. `StaticOverlaySettings.Builder` has `setScale`, `setRotationDegrees`, `setBackgroundFrameAnchor`, `setOverlayFrameAnchor`, `setAlphaScale` and `setHdrLuminanceMultiplier`. Simplest approach: render the overlay PNG at output resolution and make it full-frame |
| Background music | `Composition.Builder(videoSequence, audioSequence)` where `audioSequence = EditedMediaItemSequence.withAudioFrom(listOf(musicItem))`. `.setIsLooping(true)` loops it for the length of the video |
| Volume | `GainProcessor(DefaultGainProvider.Builder(gain).build())` (`@UnstableApi`), or `ChannelMixingAudioProcessor` with `ChannelMixingMatrix.createForConstantGain(in,out).scaleBy(volume)`. Mute the original with `EditedMediaItem.Builder.setRemoveAudio(true)` |
| **Mixing constraint** | From `Transformer.start(Composition)` javadoc: *all items with audio must output 16-bit PCM with the same channel count*. Add `ToInt16PcmAudioProcessor` + `ChannelMixingAudioProcessor` (mono music with a stereo video is a classic failure) |
| Photo → video | Image `MediaItem` (BitmapFactory formats) + `EditedMediaItem.Builder.setDurationUs(segmentUs).setFrameRate(30)` in sequence 1, music sequence 2, overlay via `OverlayEffect` (or pre-compose into one bitmap) |
| Progress | `transformer.getProgress(ProgressHolder)` polled on the application looper (~every 200–500 ms). Returns `PROGRESS_STATE_*` |
| Cancel | `transformer.cancel()` |
| Result / error | `Transformer.Listener.onCompleted(Composition, ExportResult)` and `onError(…, ExportException)` with `errorCode` |
| Threading | Access the Transformer from a single thread that has a Looper (the main thread is fine). One export at a time per instance |
| Encoders | `setVideoMimeType(MimeTypes.VIDEO_H264)`, `setAudioMimeType(AUDIO_AAC)`. `DefaultEncoderFactory` falls back automatically to supported resolution, bitrate and profile. Portrait input gets its dimensions swapped for encoder compatibility (`setPortraitEncodingEnabled`) |
| HDR | Keeping HDR needs API 33+ and encoder support (default `HDR_MODE_KEEP_HDR`, which falls back to GL tone-mapping). Tone-map to SDR with `HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL` (API 29+) or `…_USING_MEDIACODEC` (API 31+). **Recommend explicit tone-map to SDR for stories.** Old issue: OverlayShaderProgram had no HDR support (androidx/media#723) |

- **Known device issues:**
  - **androidx/media#3399** (opened 2026-08-31): a 1.11.0 regression where exports fail on decoders that report frame rate 0 (Samsung A-series, Android 15/16). Fixed on `main` but *not in 1.11.1* when observed. → pin **1.10.1** or test carefully on Samsung A-series.
  - #3357: stall and a "Muxer error" watchdog abort on VFR input with long sample gaps.
  - #2362: c2.qti.avc.encoder failure on a Samsung tablet.
  - Emulator GL (SwiftShader) is flaky for effects, so run export tests on a real device or a modern emulator with host GPU.

### 2.3 Effort estimate (one experienced dev per platform, inside our own plugin)
| Piece | iOS | Android |
|---|---|---|
| Channel/Pigeon contract + Dart API, progress stream, cancel, typed errors | 2 d (shared) | — |
| Video: trim + overlay + orig volume + music segment/volume + orientation | 4–5 d | 3–4 d |
| Photo+music → MP4 | 2 d | 1 d |
| Photo → JPEG with overlay | 0.5 d | 0.5 d |
| Waveform extraction + media probe | 1.5 d | 2 d |
| HDR/orientation/device matrix hardening + tests | 3 d | 4 d |
| **Total** | **~13 d** | **~12 d** → **~5 person-weeks** including the shared API |

FFmpeg alternative: about 1.5–2 weeks (one command builder in Dart plus tests), **plus** the licence and size costs, and ongoing risk from the fork. Adopting `pro_video_editor`: about 3–5 days of integration.

---

## 3. Flutter plugins that wrap native pipelines (pub.dev, 2026-09-25)

| Package | Version / date | Licence | Engine | Overlay | Music mix + volume | Orig vol | Photo→video | Progress / cancel | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| **pro_video_editor** (hm21) <https://pub.dev/packages/pro_video_editor> | **2.16.0 / 2026-09-24**. 159 versions since 2025-03-20, 4 releases on 09-24 alone. 92 likes, 14.3k dl/30d, 95★, 1 open issue | **BSD-3-Clause** | AVFoundation; **Media3 1.10.1** (minSdk 24); iOS 13 | ✅ `ImageLayer` (timed, rotation, size) | ✅ `VideoAudioTrack(path, volume, loop, audioStartTime, audioEndTime, startTime, endTime)` | ✅ `VideoSegment.volume` | ✅ "Stop-Motion" images→video (silent), then pass it back through `renderVideo` with `audioTracks` (2 passes) | ✅ `progressStream`, cancel (Android/iOS/macOS), `NativeFailureDetails` | **Best third-party fit**: covers every requirement. Risks: one maintainer, very high churn (pin exact versions), SDK constraint `>=3.12.0`, Flutter `>=3.44.0` ✓. Also does waveform, metadata and `hasAudioTrack`. Has `example/integration_test/` |
| easy_video_editor <https://pub.dev/packages/easy_video_editor> | 0.1.6 / 2026-06-01, 41★, 10 issues | MIT | native | ❌ | ❌ (only extract/remove) | — | ❌ | ✅/✅ | Insufficient |
| native_video_editor | 0.4.0 / 2026-08-10, 66 dl/30d | MIT | Media3 / AVFoundation | ❌ ("planned") | audio merge, image+audio | mute only | image+audio ✅ | ✅/✅ | Too immature |
| imgly_editor (CE.SDK) <https://pub.dev/packages/imgly_editor> | 1.82.1 / 2026-09-21 | **Commercial** (watermark in eval mode) | proprietary | ✅ | ✅ | ✅ | ✅ | ✅ | A complete product with its own UI; conflicts with building our own editor, and costs money |
| video_editor_sdk / imgly_sdk (legacy VE.SDK) | 3.3.0 / 2025-10-01 | Commercial | — | | | | | | Legacy |
| video_editor (LeGoffMael) | 3.0.0 / 2023-06-26 | MIT | UI only; export via ffmpeg_kit (retired) | | | | | | Stale |
| tapioca | 1.0.6+1 / 2022-09-14 | MIT | native | text/image | ❌ | | ❌ | | Dead |
| video_trimmer | 5.0.0 / 2025-04-27 | MIT | ffmpeg | | | | | | No |
| flutter_video_editor | — | — | — | | | | | | Not found on pub.dev |

### Recommendation and trade-offs
| | Own native plugin (AVF + Media3) | FFmpeg fork (`_full` LGPL) | pro_video_editor | IMG.LY |
|---|---|---|---|---|
| App size | ~0 (OS frameworks; Media3 Java ≈ 1–2 MB dex) | **+13 MB Play / +15 MB iOS download** | ~same as own | large SDK |
| Licence | ours | LGPL obligations and source offer for every host; GPL variants are a no-go | BSD-3 ✓ | commercial |
| Patents | OS-licensed codecs | FFmpeg codec code shipped | OS | vendor |
| Performance / HW accel | full HW decode + encode, GPU compositing | HW encode only in `_full` (VideoToolbox / MediaCodec); filters on CPU (overlay, scale) → slower, hotter | same as own | good |
| HDR / orientation | handled by the OS pipelines (tone-map flags) | manual (zscale/tonemap filters, rotation metadata) | depends on the library | good |
| Effort | ~5 person-weeks | ~2 weeks | ~1 week | ~1 week + UI conflict |
| Risk | our own bugs; Media3 `@UnstableApi` churn; Samsung regressions | single-maintainer fork, iOS binaries on GitHub releases, legal | single maintainer, API churn, less control over the error contract | vendor lock-in, cost |

**Decision.** Own the native plugin behind a narrow `StoryExporter` Dart interface: `exportPhoto`, `exportVideo` and `exportPhotoAsVideo`, returning `Stream<ExportProgress>`, a `cancel()` method and a typed `ExportFailure`. Optionally ship a `pro_video_editor`-backed implementation of the same interface first, so we get a working vertical slice early, then swap in our own. The interface keeps both options open.

---

## 4. Audio playback for music preview

- **just_audio** <https://pub.dev/packages/just_audio>: **0.10.6 (2026-06-29)**, **Flutter Favorite**, MIT (pub tags also show apache-2.0 for bundled parts), 4,149 likes, 1.2M dl/30d. SDK `^3.6.0`, Flutter `>=3.27.0`.
  - `setClip(start:, end:)` is the preferred way to play a segment. `ClippingAudioSource` still exists and is not deprecated.
  - `setLoopMode(LoopMode.one)` loops the selected segment in the editor. `LoopingAudioSource` is **deprecated** (use `List.filled`) and `ConcatenatingAudioSource` is **deprecated** (use `setAudioSources`).
  - `setVolume(0..1)`. Multiple players can play at once (documented).
  - `positionStream` drives the scrubber playhead.
  - `LockCachingAudioSource` is **@experimental**. It works through a localhost HTTP proxy, so it needs cleartext (`NSAllowsLocalNetworking` on iOS; cleartext for 127.0.0.1 on Android). That is good enough for streaming preview while caching, but don't rely on it for the export file.
- **audioplayers** 6.8.1 (2026-06-27), MIT, 1.29M dl/30d. Simpler API, no clip region. Not recommended for segment preview.
- **audio_session** 0.2.4 (2026-06-29), MIT (same author as just_audio). As of 0.2.x the microphone is excluded by default, so `AUDIO_SESSION_MICROPHONE=0` is no longer needed. Configure `AudioSessionConfiguration.music()` or a custom `avAudioSessionCategory: playback` (+ `mixWithOthers` if the host wants other apps' audio to keep playing) **after** the other plugins initialize, because plugins override each other's session settings (just_audio README).
- **video_player** 2.14.0 (2026-08-11), BSD-3. `VideoPlayerOptions(mixWithOthers: true)`, per-controller `setVolume` for previewing the original-audio volume.
  - **Known issue:** flutter/flutter#94328 (open, P2) — `mixWithOthers` is ignored on iOS and background music from *other apps* stops. Our own just_audio + video_player playing together *inside the app* is unaffected because they share the session. To be safe, apply the audio_session config after `VideoPlayerController.initialize()`.
- **Streaming vs local.** Preview can stream the host URL (`setUrl`). **Export needs a local file.** Download to `getApplicationCacheDirectory()/story_music/{trackId}.{ext}` with `http`/`dio`, with progress, cancellation, a checksum/size check, and LRU eviction. Start the download as soon as a track is selected so it overlaps with editing. Let the host provider return a local path directly (`MusicTrack.localFile`), or provide a `resolveForExport()` hook for signed or DRM URLs.
- **Licensing of host tracks** is the host's responsibility. The library should expose attribution fields (`artist`, `title`, `licenseUrl`).

## 5. Waveform
- **just_waveform** <https://pub.dev/packages/just_waveform>: 0.0.7 (**2025-03-30**; repo last pushed on the same day, 93★, 17 open issues), MIT, Android/iOS/macOS. `JustWaveform.extract(audioInFile, waveOutFile, zoom)` streams progress. It needs a **local file**. Maintenance is quiet but it is small.
- **audio_waveforms** (Simform) 2.0.2 (2026-01-09), MIT, 870 likes, repo pushed 2026-07-01, 59 open issues. `PlayerController.extractWaveformData(path, noOfSamples)`. It is a heavier recorder/player bundle.
- **waveform_extractor** 1.2.8: Android only. **flutter_audio_waveforms**: display only, stale since 2023.
- **pro_video_editor** also generates waveforms, with streaming.
- **Recommendation:**
  1. The `MusicTrack` model gets optional `List<double> peaks` (0..1, e.g. 100–200 buckets) — hosts often have server-side peaks (like the reference UI).
  2. Fallback: `extractPeaks(localPath, buckets)` in our own native plugin. On iOS, `AVAssetReader` + `AVAssetReaderTrackOutput` (LinearPCM, Int16) with max-abs per bucket. On Android, `MediaExtractor` + `MediaCodec` decode to PCM. About 1.5–2 days, reusing the export plugin's channel, with no extra dependency.
  3. Rendering: our own `CustomPainter` scrubber (bars, selected-window highlight, played-portion tint, drag to move the segment window) inside the design system with DS tokens.

  Use `just_waveform` only if we want to skip native extraction.

## 6. Sample music for the example app
- **Pixabay: avoid bundling.** Its Content License forbids distributing content *"on a Standalone basis"* (<https://pixabay.com/service/license-summary/>). Committing raw MP3s to an open repo or app assets is arguably standalone redistribution.
- **FreePD.com has closed** ("permanently closed as of 2025", <https://freepd.com/>).
- **Kevin MacLeod / incompetech**: Creative Commons with mandatory credit (<https://incompetech.com/music/royalty-free/licenses/>). Usable, but you must ship attribution. Second choice.
- **Verified CC0 candidates:**
  1. **Komiku – "It's time for adventure !"** (FMA). The album page states *CC0 1.0 Universal*, released 2016-07-21. Short tracks: "Fouler l'horizon" 1:47, "Le Grand Village" 1:44, "Champ de tournesol" 1:58. <https://freemusicarchive.org/music/Komiku/Its_time_for_adventure_>. Downloading may need an FMA login.
  2. **3xBlast – "Happy synths loop with slight christmas feeling"**: CC0, ~1:30, OGG, posted 2015-12-30. <https://opengameart.org/content/happy-synths-loop-with-slight-christmas-feeling>
  3. **SubspaceAudio (Juhani Junkala) – "5 Chiptunes (Action)"**: CC0, posted 2016-04-17, 49.6 MB WAV zip (transcode to AAC). <https://opengameart.org/content/5-chiptunes-action>
  4. OpenGameArt collection "CC0 – Upbeat / Electronic Music" (<https://opengameart.org/content/cc0-upbeat-electronic-music>). Check each entry's own licence field before use.
- **Preferred for the repo: self-generated tracks.** A committed Dart or Python script synthesizes 3–4 loops (e.g. a C-major arpeggio at 120 BPM, a pad chord progression, a kick/hat pattern, a sine sweep). Write 44.1 kHz stereo WAV, then convert to AAC `.m4a` (`afconvert -f m4af -d aac` on macOS; there is no FFmpeg dependency). Also useful for tests: loudness steps and silence gaps make **deterministic waveform assertions** possible, e.g. "bucket 10 is loud". Ship these in `example/assets/music/`, plus optionally 1–2 CC0 tracks with a `LICENSES.md` giving the source URL and the date checked.

## 7. Integration testing and QA
- **integration_test** now ships inside the Flutter SDK (`integration_test: sdk: flutter`). The pub.dev package 1.0.2+3 is discontinued. It runs on the iOS simulator and Android emulator with `flutter test integration_test/`. AVAssetExportSession works on the simulator, with software encode.
- **Patrol** <https://pub.dev/packages/patrol>: **4.10.0 (2026-09-15)**, Apache-2.0, 725 likes, 672k dl/30d, repo pushed 2026-09-24 (1,435★). `patrol_cli` 4.8.0 (2026-09-15). Needs SDK `>=3.8.0`, Flutter `>=3.32.0` ✓.
  - Native API: `$.platform.mobile.grantPermissionWhenInUse()`, `grantPermissionOnlyThisTime()`, `denyPermission()`, `isPermissionDialogVisible()`.
  - Platform-specific: `$.platform.android/ios.pickImageFromGallery()`, `pickMultipleImagesFromGallery()`, `takeCameraPhoto()` (verified in the `master` source).
  - Limitation: iOS permission handling only works with the device language set to English.
- **Maestro** cli-**2.10.0** (2026-08-31). The repo already mandates Maestro happy/failure/edge flows. Use it for the E2E editor journey (select music → move segment → export → success UI). It can't inspect output files, so assert the success-screen metadata that the probe exposes (e.g. a `TestId`-tagged "duration 15.0s" label in the example app).
- **Verifying exported media.** `video_player` gives only duration and size, with no audio-track info. Add a **`probe(path)`** method to our native plugin:
  - iOS: `AVURLAsset` `load(.duration)`, `loadTracks(withMediaType:)`, `naturalSize`, `preferredTransform`, `formatDescriptions` for the codec.
  - Android: `MediaMetadataRetriever` (`METADATA_KEY_DURATION`, `VIDEO_WIDTH/HEIGHT/ROTATION`, `HAS_AUDIO`) plus `MediaExtractor` for the codec, sample rate and channels.
  - `pro_video_editor` offers `getMetadata` / `hasAudioTrack` if it is adopted.
- **Assertions per test:**
  - photo → JPEG: dimensions, decodes, and the overlay pixel at a known point has the expected colour;
  - video: duration ≈ trim length ±1 frame, has audio, dimensions after rotation;
  - muted and no music: no audio track, or silence;
  - photo + music: duration ≈ segment length, has audio and video;
  - cancel: the future rejects with `ExportCancelled` and no partial file remains;
  - failure: a corrupt input yields a typed `ExportFailure`;
  - optional: extract peaks from the exported audio to check that music is present at the expected level (the self-generated loud/silent pattern makes this deterministic).
- **Fixtures.** Generate tiny H.264 portrait/landscape clips, a rotated clip, and a HEVC/HDR sample on the device or commit them (<1 MB each). Include a mono audio file to catch the Media3 PCM/channel-count constraint.
- **CI caveats.** Android emulator OpenGL (SwiftShader) is flaky for Transformer effects, so prefer real devices (Firebase Test Lab or a device farm) for the export suite and keep unit and widget tests on the emulator. Add a Samsung A-series device to the matrix because of androidx/media#3399.

---

## Sources (read 2026-09-25)
- pub.dev API `/api/packages/{name}` and `/score` for every package listed above
- <https://github.com/arthenica/ffmpeg-kit> (archived 2026-07-02), <https://github.com/arthenica/ffmpeg-kit-next>
- <https://github.com/sk3llo/ffmpeg_kit_flutter> (README, podspec, `scripts/setup_ios.sh`, android/build.gradle); Maven Central `com.antonkarpenko:ffmpeg-kit-*:2.2.1` (AARs downloaded and inspected)
- <https://developer.android.com/jetpack/androidx/releases/media3>, <https://developer.android.com/media/media3/transformer/getting-started>, `/transformations`, `/composition`, `/supported-formats`, `/troubleshooting`; androidx/media `release` branch sources (Transformer.java, EditedMediaItem(Sequence).java, BitmapOverlay.java, StaticOverlaySettings.java, GainProcessor.java, ChannelMixingMatrix.java)
- <https://github.com/androidx/media/issues/3399>, #3357, #2362, #723
- <https://developer.android.com/guide/practices/page-sizes> (the page as observed states that Play blocks non-16 KB updates targeting API 35+ from 2027-02-01)
- Apple doc JSON: AVAssetExportSession (`export(to:as:isolation:)`, `states(updateInterval:)`, `progress`, `cancelExport()`), AVMutableVideoComposition, AVVideoComposition.Configuration, AVVideoCompositionCoreAnimationTool, AVMutableAudioMix(InputParameters), AVAssetWriter(InputPixelBufferAdaptor)
- <https://github.com/hm21/pro_video_editor> (README, `audio_track_model.dart`, android/build.gradle, podspec)
- <https://github.com/ryanheise/just_audio> README (minor branch), `just_audio.dart`; <https://github.com/ryanheise/just_waveform>
- <https://github.com/flutter/flutter/issues/94328>, <https://github.com/flutter/flutter/issues/172430>
- <https://patrol.leancode.co/documentation/native/usage>; leancodepl/patrol master sources
- <https://pixabay.com/service/license-summary/>, <https://freepd.com/>, <https://incompetech.com/music/royalty-free/licenses/>, FMA and OpenGameArt pages listed in §6
