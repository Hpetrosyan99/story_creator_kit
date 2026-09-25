# Research 1: Architecture, dependencies, public API (story creator library)

Agent 1. Research only; no repo changes. All facts observed **2026-09-25** unless another date is given.
Toolchain assumed: Flutter 3.47.1 / Dart 3.13.1. Host repo: the original boilerplate monorepo
(Dart workspace + Melos 7.5.1, members `packages/api`, `packages/design_system`; the app uses MobX 2.6, Provider, GetIt/Injectable,
AutoRoute 11, easy_localization, flutter_hooks, `package:flutter/material.dart`).

---

## 0. TL;DR recommendations

1. **Build our own UI and canvas/layer model. Do not build on `pro_image_editor`.** Use **`pro_video_editor`** (BSD-3) as the
   first **video render engine**, behind our own `StoryRenderer` interface, so it can be swapped for our own Media3/AVFoundation code later.
   Photo export happens in pure Flutter: rasterise the overlays and composite them.
2. **Packaging: start as a plain Flutter *package*** (`packages/story_creator`, no `ios/`/`android/`) that depends on federated
   plugins. Add native code only when a gap is proven. If native code is needed, put it in a **separate, non-federated plugin package**
   (`packages/story_creator_native`, Android + iOS only), using **Pigeon 29.x over platform channels** (not the experimental FFI/JNI mode),
   **SwiftPM + CocoaPods both**, Kotlin built for AGP 9 built-in Kotlin.
3. **State management: plain Flutter primitives** (`ChangeNotifier` / `ValueNotifier` / `ValueListenableBuilder` / `InheritedNotifier`).
   No MobX, Provider, GetIt, AutoRoute, easy_localization, flutter_hooks or `design_system` inside the library.
4. **Public API:** a `Future`-returning `StoryCreator.open(context, config)` **plus** an embeddable `StoryCreatorPage` widget with an
   `onComplete` callback. The widget is what this host needs: ADR-0008 forbids `Navigator` in the app, so the host's `AppNavigator`/AutoRoute pushes it.
   The result is a **sealed `StoryOutcome`** (`StoryCompleted | StoryCancelled | StoryFailed`), not a nullable result.
   The host supplies a `StoryCreatorTheme`, a `StoryCreatorStrings` subclass, a `List<StoryFont>`, an optional `StoryMusicProvider` and `StoryMediaConstraints`.
5. **Min OS: iOS 15.0, Android minSdk 24** (compileSdk/targetSdk 36). The limit is Flutter 3.47 itself. No candidate dependency asks for more.
6. **Tests:** unit tests on models and controllers; widget tests with the camera, gallery, player and renderer faked behind internal interfaces;
   **alchemist** CI goldens for overlays and the burn-in rasteriser; `integration_test` in `example/` for render/export on a device;
   **patrol** only for OS permission dialogs; Pigeon: fake the generated Dart API (`dartTestOut` is deprecated), plus JUnit/XCTest on the native side.
7. **Housekeeping:** ADR-0014 says a third package needs **a new ADR**. The pub.dev name **`story_creator` is taken**. Make
   `packages/story_creator/example` a workspace member. The shared workspace lockfile means the library's dependency ranges must be compatible with the app's.

---

## 1. Existing libraries: reuse versus learn

### 1.1 Survey table (observed 2026-09-25)

| Package | Latest / published | License | pub.dev (likes / points / downloads) | GitHub signals | Video? | Verdict |
|---|---|---|---|---|---|---|
| [pro_image_editor](https://pub.dev/packages/pro_image_editor) | **14.4.1**, ~10 h before observation (2026-09-24/25) | BSD-3-Clause | 592 / 160 / 57k | [hm21/pro_image_editor](https://github.com/hm21/pro_image_editor): 391★, 4 open issues, pushed 2026-09-24, not archived, created 2024-01-02, branch `stable`, 1,282 commits | Yes: video/audio/clips editor configs inside, rendering through pro_video_editor | Most capable. **Adopting it brings heavy churn and forces its UI model on us** (see 1.2) |
| [pro_video_editor](https://pub.dev/packages/pro_video_editor) | **2.16.0**, ~7 h before observation | BSD-3-Clause | 92 / 160 / ~14.7k | [hm21/pro_video_editor](https://github.com/hm21/pro_video_editor): 95★, 1 open issue, pushed 2026-09-24, created 2025-03-20, 381 commits | It is the render engine | **Use as the render backend, behind our interface** |
| [video_editor](https://pub.dev/packages/video_editor) | 3.0.0, ~3 years ago | MIT | 599 / 150 | [LeGoffMael/video_editor](https://github.com/LeGoffMael/video_editor): 500★, 46 issues, last push 2025-04-12 | Trim/crop UI only. Export needs your own FFmpeg (removed in 3.0.0) | Learn from its trim UI. Stale |
| [stories_editor](https://pub.dev/packages/stories_editor) | 0.2.2, ~3 years ago | CC0-1.0 | 108 / 55 / 19 | camilo1498/stories_editor: last push 2024-01-14 | No (image export only; video "planned") | Dead. UX reference only |
| [vs_story_designer](https://pub.dev/packages/vs_story_designer) | 2.2.1, ~16 months ago | BSD-3 (GitHub: NOASSERTION) | 46 / 140 / 94 | last push 2025-05-23, 13 issues | No | Fork of stories_editor. Skip |
| [flutter_story_editor](https://pub.dev/packages/flutter_story_editor) | 0.0.2, ~2 years ago | MIT | 47 / 130 / 44 | last push 2024-07-23 | Trim only (video_trimmer) | Skip |
| [story_maker](https://pub.dev/packages/story_maker) | 1.2.0, ~10 months ago | MIT | 69 / 140 / 36 | NarekManukyan/story_maker: 7★, last push 2026-04-10 (**same owner as this boilerplate's repo URL**) | No (image, text, stickers, gradients, filters) | Internal prior art. Image only |
| [story_creator](https://pub.dev/packages/story_creator) | 1.0.2, ~3 years ago | MIT | 31 / 140 / 9 | tjcampanella/story_creator, last push 2022-06-11 | No | **Name taken on pub.dev** |
| [image_editor_plus](https://pub.dev/packages/image_editor_plus) | 1.0.8, ~12 months ago | MIT | 318 / 150 / 4.9k/wk | repo URL 404 | No | Skip |
| [easy_video_editor](https://pub.dev/packages/easy_video_editor) | 0.1.6, ~3 months ago | MIT | 53 / 160 / 7.9k | — | Trim/merge/speed/crop/compress, no FFmpeg, iOS 13+, SPM + CocoaPods | Operations only, **no overlay burn-in or music mix** found in docs. Fallback option |
| [lovoj_video_editor](https://pub.dev/packages/lovoj_video_editor) | 0.11.38, ~2 months ago | MIT | 3 / 125 / 56 | unverified uploader | Full recorder/editor with its own UI (Camera2/MediaCodec, AVFoundation) | Immature, fixed UI. Skip |
| [video_editor_sdk (IMG.LY)](https://pub.dev/packages/video_editor_sdk) | 3.3.0, ~11 months ago | **Commercial** | — | — | Full | Out: commercial licence, fixed UI |
| [ffmpeg_kit_flutter_new](https://pub.dev/packages/ffmpeg_kit_flutter_new) | 4.6.2, ~56 days ago | **LGPL-3.0 / GPL-3.0 variants** | 203 / 140 / 39k | sk3llo fork, pushed 2026-07-30 | Anything | **Avoid**: licence exposure, large binary. The original FFmpegKit retired 2025-01-06 and its binaries were pulled (Maven Central 2025-04-01) — [Taner Sener post](https://tanersener.medium.com/saying-goodbye-to-ffmpegkit-33ae939767e1) |

No new, maintained, Instagram-style *story creator with video + music* package appeared in a pub.dev search on 2026-09-25 ("story editor", sorted by updated).
The field is either abandoned image-only story editors or general editors (the pro_* family).

### 1.2 pro_image_editor in depth

Facts (README and source on branch `stable`, 2026-09-25):
- `environment: sdk >=3.12.0, flutter >=3.44.0`. Dependencies include `material_ui`, `cupertino_ui`, `http`, `shared_preferences`, `vector_math`.
- **v14.0.0 BREAKING**: "Migrate from `package:flutter/material.dart` … to the standalone `material_ui` and `cupertino_ui` packages … Apps must migrate their own imports as well
  … because types such as `ThemeData` are no longer interchangeable with the SDK ones." (CHANGELOG). This host app still uses `package:flutter/material.dart`.
- Release velocity: 14.4.1, 14.4.0, 14.3.1 all within ~13 hours; 14.0.0 was 16 days earlier; 13.x ended 17 days earlier. That is about 10 releases in 17 days and a major version roughly monthly ([versions](https://pub.dev/packages/pro_image_editor/versions)).
- Customisation: `ProImageEditorConfigs` has `theme`, `i18n (I18n)`, `mainEditor`, `paintEditor`, `textEditor`, `cropRotateEditor`, `filterEditor`, `tuneEditor`,
  `blurEditor`, `emojiEditor`, `stickerEditor`, `designMode`, `stateHistory`, `imageGeneration`, `dialogConfigs`, `progressIndicatorConfigs`, **`videoEditor`, `audioEditor`, `clipsEditor`**.
  `MainEditorWidgets` can replace `appBar`, `bottomBar`, `bodyItems`, `wrapBody`, `removeLayerArea`, `closeWarningDialog`
  (builders receive `ProImageEditorState` + a rebuild stream). Three prebuilt designs ship: Grounded, Frosted-Glass, WhatsApp.
- Video: `ProImageEditor.autoSource(videoController: ProVideoController)` plus `VideoEditorConfigs` (trim bar, `minTrimDuration`, `maxTrimDuration`, layer timeline).
  You bring your own player (video_player, media_kit and others) and render through pro_video_editor.
- Audio: `AudioEditorConfigs.audioTracks: List<AudioTrack>`, a **static list**. There is no search, pagination or category provider contract; we would build that picker ourselves anyway.
- Import/export of state history (JSON) exists (`shared/services/import_export`). That is useful for drafts.
- `features/main_editor/main_editor.dart` is **3,587 lines**, so the core is monolithic.

**Could we have an original UI on top of it?** Only partly. Chrome (bars, buttons, dialogs, icons, strings) is replaceable.
Its **interaction model is not**: sub-editors are separate screens or modes (paint editor, text editor, crop editor), and layer gestures, the remove area and helper-line behaviour are its own.
An Instagram-style flow means a camera-first capture screen, text typed straight onto the canvas with a font carousel, and draggable music and text stickers on one canvas.
Reproducing that means fighting the library's state machine through builder hooks. On top of that we would take on:
(a) the forced `material_ui` migration for every host;
(b) monthly majors on a workspace-shared lockfile;
(c) about six platforms of code we don't need.

**Adopt versus build**

| | Adopt pro_image_editor | Build own editor + pro_video_editor render engine | Build everything, including native render |
|---|---|---|---|
| Time to first demo | Fastest | Medium | Slowest |
| Original UX | Limited to its model | Full | Full |
| Host constraints | Forces `material_ui`, Dart ≥3.12, Flutter ≥3.44 | We control them | We control them |
| Churn exposure | High (UI + engine) | Medium (engine only, behind an interface) | None external |
| Native maintenance | None | None | Media3 Transformer + AVFoundation, SPM/CocoaPods, Pigeon |
| Licence | BSD-3 (forkable) | BSD-3 (forkable) | Own |

**Recommendation:** build our own editor UI and layer model (text layers, stroke layers, music sticker) in Flutter. Burn in overlays by
rasterising our own overlay widget tree into one transparent PNG at output resolution (or per-layer PNGs if animated later). Hand it to the renderer:
- **Photo:** pure Dart. Composite the base image and the overlay with `ui.PictureRecorder`/`Canvas`, then encode (JPEG through a small encoder, or PNG).
- **Video:** `pro_video_editor.renderVideoToFile(VideoRenderData)` with `VideoSegment(startTime,endTime)` for trim, `ImageLayer` for the overlay, and `VideoAudioTrack` for music plus the original-audio volume.
  Native side (verified in its build files): Android **Media3 1.10.1** (`media3-transformer`, `-effect`, `-muxer`), minSdk 24, compileSdk 36. iOS/macOS use **AVFoundation**, have a shared darwin source, and ship both
  **Package.swift** (iOS 13 / macOS 12, `FlutterFramework` dependency) and a **podspec** (iOS 13). Progress and cancel exist on Android and iOS.
- Keep it behind `abstract interface class StoryRenderer` so we can move to our own native pipeline (Media3 1.11.1 is current, released 2026-09-10) if its churn or single-maintainer risk bites.
  Pin it with a caret on the minor version, e.g. `^2.16.0`, and review each upgrade.

Learn from: pro_image_editor for layer transforms (normalised offsets, rescaling state when canvas size changes, per its 14.1.1 fix) and helper-line snapping; video_editor for the trim bar UX; stories_editor and story_maker for Instagram UX patterns.

### 1.3 Supporting plugins (capture, gallery, playback)

| Package | Latest / published | Publisher / licence | Min OS (as documented) | SPM | Notes |
|---|---|---|---|---|---|
| [camera](https://pub.dev/packages/camera) | 0.12.1, ~21 days ago | flutter.dev / BSD-3 | Android 24+, iOS 13+ | Yes (flutter/packages) | Android impl `camera_android_camerax` 0.7.4+8 (CameraX limits: 240p is unsupported and falls back to 480p; `streamOptions` is ignored while recording; `enablePersistentRecording` is needed to switch camera while recording). iOS `camera_avfoundation` 0.10.3+1 (~20 h ago). Custom UI: we draw everything |
| [camerawesome](https://pub.dev/packages/camerawesome) | 2.5.0, ~15 months ago | Apparence.io / MIT on GitHub ("pending" on pub) | Android 21+ | — | 1,216★, 207 open issues, last push 2026-04-08. Slower cadence. Keep as a fallback |
| [photo_manager](https://pub.dev/packages/photo_manager) | 3.12.0, ~46 days ago | fluttercandies / Apache-2.0 | iOS 9, Android 16 (plugin floor) | **Yes** (`darwin/photo_manager/Package.swift`) | Limited access on iOS 14+ and Android 14+ (`presentLimited`). 770★, 51 issues, pushed 2026-09-18. Recommended for our own gallery grid |
| [wechat_assets_picker](https://pub.dev/packages/wechat_assets_picker) / [wechat_camera_picker](https://pub.dev/packages/wechat_camera_picker) | 10.1.3 / 4.6.0, ~2 months ago | fluttercandies / Apache-2.0 | — | — | API reference (below). Its UI is WeChat-styled, so don't embed it |
| [image_picker](https://pub.dev/packages/image_picker) | 1.2.3, ~2 months ago | flutter.dev / BSD-3 | Android 24, iOS 13 | Yes | System picker only (Android Photo Picker 13+, PHPicker 14+). No custom grid. Good "system picker" fallback that needs no permission |
| [video_player](https://pub.dev/packages/video_player) | 2.14.0, ~44 days ago | flutter.dev / BSD-3 | Android 24, iOS 13 | Yes | ExoPlayer / AVPlayer. `mixWithOthers` option. Preview player |
| [just_audio](https://pub.dev/packages/just_audio) | 0.10.6, ~2 months ago | ryanheise / Apache-2.0 + MIT | — | **Yes** (`just_audio/darwin/just_audio/Package.swift`) | Clipping (start/end) suits music-snippet preview. 1,218★, **345 open issues**, last push 2026-06-29. Acceptable, but keep it behind an interface |
| [pigeon](https://pub.dev/packages/pigeon) | 29.0.2, ~8 days ago (29.0.3 on main needs Flutter 3.41/Dart 3.11) | flutter.dev / BSD-3 | — | — | See section 2 |

---

## 2. Packaging

### 2.1 Current Flutter platform facts
- **SwiftPM is the default since Flutter 3.44.** "Flutter continues to support CocoaPods in maintenance mode, however, the CocoaPods registry permanently becomes read-only on December 2, 2026."
  "**Flutter plugins should support both Swift Package Manager and CocoaPods until further notice.**" — [SPM for plugin authors](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors) (page updated 2026-06-08).
  - Layout: `ios/<plugin>/Package.swift` + `ios/<plugin>/Sources/<plugin>/…` (+ `PrivacyInfo.xcprivacy` as a processed resource). swift-tools-version 5.9.
    **New requirement: a `FlutterFramework` package dependency** (`.package(name: "FlutterFramework", path: "../FlutterFramework")`). The library product name uses `-` in place of `_`.
  - Test both: `flutter config --no-enable-swift-package-manager` / `--enable-swift-package-manager`, plus `pod lib lint`.
- Flutter 3.47 blog ([What's new in 3.47](https://flutter.dev/blog/whats-new-in-flutter-3-47), 2026-08-12): "92 of the top 100 iOS plugins now migrated". Unmigrated plugins get **lower pub.dev scores**.
  iOS minimum raised **13 → 15**, macOS 10.15 → 12 (for Xcode 27). Verified toolchain: Java 17, KGP 2.4.0, **AGP 9.1.0**, Gradle 9.3.1. Defaults: compileSdk 36 / targetSdk 36 / minSdk 24.
- **UIScene**: the iOS 27 SDK mandates the UIScene lifecycle. A plugin that needs lifecycle callbacks must conform to `FlutterSceneLifeCycleDelegate` (APIs since 3.38; default since 3.41) — [UIScene adoption](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate).
- **Android built-in Kotlin**: AGP 9 makes built-in Kotlin the default. Plugins applying `kotlin-android` must migrate. 3.44 added the `android.builtInKotlin=false` escape hatch; 3.47 supports `=true`. KGP support is going away — [migrate to built-in Kotlin](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin).
- Plugin templates default to Swift and Kotlin. Federated plugins (app-facing + platform interface + implementations) exist for multi-team or multi-platform work — [Developing packages](https://docs.flutter.dev/packages-and-plugins/developing-packages) (updated 2026-09-16).

### 2.2 Pigeon (29.0.2 on pub.dev, 2026-09-17)
- Generates Kotlin/Java, Swift/ObjC, C++, GObject. `@HostApi`, `@FlutterApi`, and `@EventChannelApi` (Swift/Kotlin/Dart only). `@async` gives Kotlin `suspend` and Swift `async` (default since 28.0.0), and `@TaskQueue` runs work off the main thread.
- 29.0.0 added **experimental Native Interop (FFI/JNI)**. Its README recommends platform channels for "simple data objects or … low-frequency communication". A render call with progress events is low-frequency, so **use platform channels**.
- "Using Pigeon-generated code in public APIs is **strongly discouraged**". Keep the generated files under `lib/src/`. `dartTestOut` is `@Deprecated('Mock/fake the generated Dart API instead.')`.

### 2.3 Options

| Option | Pros | Cons |
|---|---|---|
| **A. Pure Flutter package** depending on plugins (camera, photo_manager, video_player, just_audio, pro_video_editor) | No native code to own; no SPM/CocoaPods/AGP-9 upkeep; the fastest tests; transitive plugins register automatically in the host | Limited to what those plugins expose |
| B. Single plugin package (`--template=plugin --platforms=android,ios`) with Pigeon | One package; we can fix engine gaps | We own Swift + Kotlin, dual SPM/CocoaPods, UIScene, AGP-9 migrations, and the whole package becomes a plugin even for UI changes |
| C. Federated plugin | Right for multi-platform, multi-team | Three or more packages of overhead for two platforms and one team. **Not justified** |

**Recommend A now. If a gap appears, add B as a separate package** (`story_creator_native`) that A depends on.
Possible gaps: gallery save with album metadata, HEIC→JPEG, HDR→SDR tone-mapping, or replacing pro_video_editor.
Two packages keep the UI package testable with plain `flutter test`, and each native package can be swapped behind the `StoryRenderer` or `MediaLibrary` interface.
If B is created: `flutter create --template=plugin --platforms=android,ios -i swift -a kotlin`; Swift package with the `FlutterFramework` dependency **and** a podspec; iOS 15 in both; Kotlin with built-in Kotlin; Pigeon file in `pigeons/`; `sharedDarwinSource` isn't needed (iOS only).

### 2.4 Repo-specific notes
- **ADR-0014** says the workspace has *two* packages, and "If a real shared core appears, it becomes a third package … recorded in a new ADR". Adding `packages/story_creator` needs **a new ADR**.
  ADR-0014's dependency direction also applies: the library must **not** depend on `design_system`, `api` or the app. The app maps `GeistTheme` onto `StoryCreatorTheme` and `LocaleKeys` onto `StoryCreatorStrings`.
- Dart workspaces ([docs](https://dart.dev/tools/pub/workspaces), updated 2026-05-15): members need `resolution: workspace` and SDK ≥ 3.6. There is **one shared lockfile**:
  "Dart doesn't allow multiple versions of the same package", so the library's ranges must agree with the app's.
  This is another reason to avoid pro_image_editor, whose `material_ui` would enter the app's resolution.
  Add `packages/story_creator` **and** `packages/story_creator/example` to the root `workspace:` list. Melos 7 uses the workspace list.
- The house `analysis_options.yaml` (relative imports, trailing commas, etc.) can be reused, but a **publishable** package should use `package:` imports across its `lib/src` → `lib/` barrel boundary, per normal pub conventions. Choose one deliberately in the ADR.
- The name `story_creator` is taken on pub.dev. It's fine while `publish_to: none`. If it will ever be published, choose a unique name now (check `pub.dev/packages/<name>`).

---

## 3. State management inside the library

**Recommendation: `ChangeNotifier`/`ValueNotifier` + `ListenableBuilder`/`ValueListenableBuilder`, scoped with `InheritedNotifier`/`InheritedWidget`. No third-party state or DI packages.**

Reasons:
1. **Host independence** is a hard requirement. MobX (2.7.0, vyuh.tech, MIT) needs `mobx_codegen` + `build_runner`, so every consumer's build pipeline and lockfile would carry `mobx`/`flutter_mobx` versions.
   Hosts on Riverpod or Bloc would get a second reactive system.
2. **Shared-lockfile risk** (section 2.4) and the ADR-0014 reuse driver: fewer dependencies mean fewer conflicts.
3. `ChangeNotifier` lives in `flutter/foundation`, has no codegen, and is what Flutter's own controllers use (`TextEditingController`, `ScrollController`, `AnimationController`).
   A public `StoryEditorController extends ChangeNotifier` (if we expose one) works with *any* host state library.
4. Dependency injection: constructor parameters plus one internal `InheritedWidget` scope (`_StoryScope`) holding services (`CameraService`, `MediaLibrary`, `StoryRenderer`, `AudioPreviewer`, `StoryMusicProvider`).
   This scope is also the **test seam** (swap in fakes). `getIt` doesn't belong in a library.
5. **Navigation**: the library pushes its *internal* sub-screens with a nested `Navigator` inside its own root widget. It never uses the host's router (no AutoRoute dependency). This keeps it compatible with AutoRoute, go_router and plain Navigator.
6. The house rules (MobX stores, Provider at page root, HookWidget default, `LocaleKeys`, DS tokens) are **app rules**. The library's new ADR should say which carry over (widget construction discipline ADR-0018, error-handling spirit ADR-0020) and which don't (MobX, GetIt, AutoRoute, easy_localization, flutter_hooks).
   An optional hook: a host that wants MobX can wrap our controller's `Listenable` itself.

**Material dependency.** Flutter 3.47 made `material_ui`/`cupertino_ui` 1.0 opt-in. `material_ui` is at 1.4.0 (2026-09-23), and bundled Material is scheduled for formal deprecation in **November 2026** (3.47 blog).
The "migrate to standalone material_ui" breaking change is still listed as not yet on stable ([breaking changes](https://docs.flutter.dev/release/breaking-changes)).
Hosts will be split during the transition. pro_image_editor v14 shows the failure mode: mismatched `ThemeData` types, and "No MaterialLocalizations found" in hosts that haven't migrated.
**Recommendation:**
- Keep `ThemeData` and Material types **out of the public API**; `StoryCreatorTheme` holds plain `Color`/`TextStyle`/`double`/`Duration` values.
- Build the editor on the **widgets layer** (`EditableText`, `GestureDetector`, `CustomPaint`, own buttons and sheets). The story UI is custom anyway.
- If any Material widget is used internally, wrap the library root in its own `Localizations.override` supplying default Material/Widgets localizations so either host flavour works.
- Revisit when bundled Material is actually deprecated.

---

## 4. Public API design

### 4.1 How comparable libraries expose entry points
- **wechat_assets_picker 10.1.3**: `final List<AssetEntity>? result = await AssetPicker.pickAssets(context, pickerConfig: const AssetPickerConfig());`
  Null means cancelled. i18n through `textDelegate: AssetPickerTextDelegate` subclasses, picked by locale from `BuildContext`; theming through `pickerTheme: ThemeData` or `themeColor`.
- **wechat_camera_picker 4.6.0**: `final AssetEntity? entity = await CameraPicker.pickFromCamera(context, pickerConfig: CameraPickerConfig(enableRecording, maximumRecordingDuration, onlyEnableRecording, textDelegate, theme))`.
- **image_picker 1.2.3**: `final XFile? image = await picker.pickImage(source: ImageSource.gallery);` (instance, no context, system UI).
- **pro_image_editor 14.4.1**: widget constructors (`ProImageEditor.file/memory/network/asset/autoSource/blank`) with `callbacks: ProImageEditorCallbacks(onImageEditingComplete: (Uint8List bytes) async {...})`.
  The host pushes the route itself and pops in the callback. `I18n` class for strings; `configs:` tree for everything else.

Pattern: a static `Future`-returning helper for convenience, a widget for router-driven hosts, a text-delegate class for strings, and nested immutable config objects.

### 4.2 Proposed Dart API (sketch, not final)

```dart
// ---- Entry points --------------------------------------------------------
abstract final class StoryCreator {
  /// Pushes a full-screen route on the root navigator and completes with the
  /// outcome. It never throws for expected failures; those come back as
  /// StoryFailed.
  static Future<StoryOutcome> open(
    BuildContext context, {
    required StoryCreatorConfig config,
    StoryInitialMedia? initialMedia, // skip the camera: start from a file or asset
  });
}

/// Embeddable root, for hosts that route declaratively (AutoRoute/go_router).
/// This host's AppNavigator pushes a route whose page is this widget
/// (ADR-0008).
class StoryCreatorPage extends StatefulWidget {
  const StoryCreatorPage({
    super.key,
    required this.config,
    required this.onComplete, // void Function(StoryOutcome outcome)
    this.initialMedia,
  });
}

// ---- Configuration -------------------------------------------------------
@immutable
final class StoryCreatorConfig {
  const StoryCreatorConfig({
    this.theme = const StoryCreatorTheme(),
    this.strings = const StoryCreatorStrings(),        // English defaults
    this.fonts = const [],                              // host-supplied; the library falls back to its default font
    this.musicProvider,                                 // null hides the music tool
    this.constraints = const StoryMediaConstraints(),
    this.editor = const StoryEditorOptions(),
    this.capture = const StoryCaptureOptions(),
    this.output = const StoryOutputOptions(),
    this.onError,       // void Function(Object error, StackTrace st)? - host tracking (ADR-0020 trackSilentError)
    this.onEvent,       // void Function(StoryEvent e)? - optional analytics
    this.permissionHandler, // optional host override for rationale and settings UI
  });
}

@immutable
final class StoryCreatorTheme {
  const StoryCreatorTheme({
    this.background = const Color(0xFF000000),
    this.surface, this.onSurface, this.accent, this.destructive,
    this.iconColor, this.scrim,
    this.titleStyle, this.bodyStyle, this.captionStyle, // TextStyle? (merged with defaults)
    this.cornerRadius = 12, this.toolbarIconSize = 28,
    this.animationDuration = const Duration(milliseconds: 200),
    this.icons = const StoryCreatorIcons(),          // IconData or widget builders per tool
    this.brightness = Brightness.dark,
    this.drawingPalette = defaultPalette, this.textPalette = defaultPalette,
  });
  StoryCreatorTheme copyWith({...});
}

@immutable
final class StoryEditorOptions {
  const StoryEditorOptions({
    this.tools = const {StoryTool.text, StoryTool.draw, StoryTool.music, StoryTool.trim},
    this.maxTextLayers = 10,
    this.brushes = const [BrushType.pen, BrushType.marker, BrushType.neon, BrushType.eraser],
    this.brushWidthRange = const (min: 2.0, max: 40.0),
    this.enableUndo = true,
    this.enableSnapping = true,
    this.confirmDiscard = true,           // show "discard edits?" on close
    this.textBackgroundStyles = TextBackground.values,
    this.textAlignments = TextAlign.values,
  });
}

@immutable
final class StoryCaptureOptions {
  const StoryCaptureOptions({
    this.sources = const {StorySource.camera, StorySource.gallery},
    this.allowPhoto = true, this.allowVideo = true,
    this.initialLens = CameraLens.back,
    this.enableFlash = true, this.enableZoom = true,
    this.holdToRecord = true,              // tap = photo, hold = video
    this.galleryPicker = GalleryPicker.inApp, // inApp (photo_manager grid) | system (image_picker)
  });
}

@immutable
final class StoryMediaConstraints {
  const StoryMediaConstraints({
    this.maxVideoDuration = const Duration(seconds: 60),
    this.minVideoDuration = const Duration(seconds: 1),
    this.maxImportDuration,                // longer imports go to the trim step
    this.maxFileSizeBytes,                 // import rejection threshold
    this.allowedMimeTypes,                 // e.g. {'image/jpeg','image/heic','video/mp4','video/quicktime'}
    this.maxMusicClipDuration = const Duration(seconds: 30),
  });
}

@immutable
final class StoryOutputOptions {
  const StoryOutputOptions({
    this.size = const Size(1080, 1920),    // 9:16
    this.fit = StoryFit.cover,             // cover | contain (with background colour or blur)
    this.photoFormat = StoryImageFormat.jpeg, this.jpegQuality = 90,
    this.videoCodec = StoryVideoCodec.h264, // hevc is opt-in (device support varies)
    this.videoBitrate, this.frameRate = 30,
    this.generateThumbnail = true,
    this.outputDirectory,                  // default: temp dir; the host owns the file afterwards
  });
}

// ---- Fonts ---------------------------------------------------------------
@immutable
final class StoryFont {
  const StoryFont({
    required this.id,            // stable id, echoed in the result metadata
    required this.displayName,
    required this.fontFamily,    // Flutter family name
    this.package,                // if it comes from a package's pubspec fonts
    this.loader,                 // Future<void> Function()? - lazy FontLoader for downloaded fonts
    this.previewText = 'Aa',
    this.defaultSize = 32,
  });
}
// Overlays are rasterised by Flutter, so fonts only need to be available to
// Flutter. No native font registration is needed for burn-in.

// ---- Music provider ------------------------------------------------------
abstract interface class StoryMusicProvider {
  Future<List<MusicCategory>> categories();
  Future<MusicPage> tracks({
    String? query,               // null or empty = browse/featured
    String? categoryId,
    String? cursor,              // opaque pagination token from the previous page
    int pageSize = 20,
  });
  /// Resolves a playable and renderable source (may sign URLs or download).
  Future<MusicSource> resolve(MusicTrack track);
}

@immutable final class MusicCategory { final String id; final String title; final String? artworkUrl; }
@immutable final class MusicPage { final List<MusicTrack> items; final String? nextCursor; }
@immutable final class MusicTrack {
  final String id; final String title; final String? artist; final String? artworkUrl;
  final Duration duration; final Duration? suggestedStart; // song highlight
  final bool isExplicit; final Map<String, Object?> extra; // host passthrough
}
sealed class MusicSource {
  const factory MusicSource.file(String path) = FileMusicSource;
  const factory MusicSource.url(Uri uri, {Map<String, String> headers}) = UrlMusicSource;
}
// The library downloads a URL source to a temp file before export
// (renderers need local files). Headers support signed CDN URLs.

// ---- Strings -------------------------------------------------------------
/// English defaults. The host subclasses it and overrides getters, e.g. with
/// easy_localization: `@override String get discardTitle => LocaleKeys.story_discard_title.tr();`
class StoryCreatorStrings {
  const StoryCreatorStrings();
  String get discardTitle => 'Discard edits?';
  String get discardConfirm => 'Discard';
  String get cancel => 'Cancel';
  String get done => 'Done';
  String get addText => 'Tap to type';
  String get searchMusic => 'Search music';
  String get permissionCameraTitle => 'Allow camera access';
  String videoTooLong(Duration max) => 'Videos can be up to ${max.inSeconds}s';
  String recordingSeconds(int s) => '${s}s';
  // Every user-visible string plus Semantics labels. Parameterised strings are
  // methods.
}

// ---- Result --------------------------------------------------------------
sealed class StoryOutcome { const StoryOutcome(); }
final class StoryCompleted extends StoryOutcome { final StoryMedia media; }
final class StoryCancelled extends StoryOutcome { final StoryCancelReason reason; } // userClosed | systemBack | discardedEdits
final class StoryFailed extends StoryOutcome { final StoryCreatorError error; }

sealed class StoryCreatorError {
  Object? get cause; StackTrace? get stackTrace;
}
final class PermissionDeniedError extends StoryCreatorError { final StoryPermission permission; final bool permanently; }
final class CameraUnavailableError extends StoryCreatorError {}
final class UnsupportedMediaError extends StoryCreatorError { final String? mimeType; }
final class MediaImportError extends StoryCreatorError {}
final class ExportError extends StoryCreatorError {}
final class InsufficientStorageError extends StoryCreatorError {}
final class MusicProviderError extends StoryCreatorError {}
// Rule: failures the user can recover from inside the flow (music search
// failed, one import failed) are shown in-UI and only reported through
// onError. Only fatal ones end the flow with StoryFailed. A permission denial
// is shown in-UI with a Settings CTA first; the flow completes with
// StoryFailed(PermissionDeniedError) only if the user leaves from that screen.

@immutable
final class StoryMedia {
  final String path;                 // output file (temp dir unless outputDirectory is set); the host must move or delete it
  final StoryMediaType type;         // photo | video
  final String mimeType;             // image/jpeg | video/mp4
  final int width, height;
  final Duration? duration;          // video only
  final int fileSizeBytes;
  final String? thumbnailPath;       // JPEG poster frame (video) or downscaled photo
  final StoryMetadata metadata;
  Future<void> deleteFiles();        // convenience cleanup
}

@immutable
final class StoryMetadata {
  final StorySourceInfo source;               // camera | gallery (+ platform asset id), original dimensions and duration
  final List<TextOverlayInfo> textOverlays;   // text, fontId, colour, background, alignment, normalised centre (0..1), scale, rotation
  final bool hasDrawing;
  final MusicSelection? music;                // trackId, title, artist, clipStart, clipDuration, volume, originalAudioVolume
  final TrimRange? trim;                      // start and end within the source video
  final Map<String, Object?> toJson();
}
```

Design notes:
- `open` returns a non-nullable sealed `StoryOutcome`, so `switch` is exhaustive (Dart 3 sealed classes). The host can't confuse "cancelled" with "failed", and the cancel *reason* is kept for analytics.
  A thin `Future<StoryMedia?> pick(...)` convenience can wrap it if wanted.
- **Why a widget as well:** the host app forbids `Navigator.of(context)` (ADR-0008). Its `AppNavigator` pushes an AutoRoute page that renders `StoryCreatorPage(onComplete: state.onStoryOutcome)`, and the page *state* pops. `open()` exists for hosts without that rule.
- **Localisation:** a strings class with English defaults, overridden by subclassing. This follows the prior art (`AssetPickerTextDelegate`, pro_image_editor `I18n`) and bridges to any host i18n (easy_localization, gen_l10n, intl) without a dependency.
  Optionally also ship a `StoryCreatorLocalizations.delegate` built with gen_l10n in the package (`l10n.yaml` with `synthetic-package: false` and `output-dir` inside the package; the synthetic `package:flutter_gen` was removed as of 3.32 — [breaking change](https://docs.flutter.dev/release/breaking-changes/flutter-generate-i10n-source); [i18n docs](https://docs.flutter.dev/ui/internationalization), updated 2026-09-02).
  That can come later; v1 needs only the strings class. RTL: the library honours `Directionality` from the host.
- All config classes are immutable with `const` constructors and `copyWith`. Enums and value types stay in the public API; plugin types (`CameraController`, `AssetEntity`, pro_video_editor models) stay **out** of it, so dependencies can be swapped without a breaking change.
- File ownership and cleanup must be documented: outputs go to temp; intermediate files (downloaded music, overlay PNG, camera temp files) are deleted by the library on completion or cancel.

---

## 5. Minimum OS versions

| Source | iOS | Android |
|---|---|---|
| **Flutter 3.47** ([supported platforms](https://docs.flutter.dev/reference/supported-platforms), updated 2026-09-22) | **15 – 27** (CI 18, 26); ≤14 unsupported | **API 24 – 37** (CI 24–36); ≤23 unsupported |
| Flutter 3.47 template defaults (blog) | 15 | minSdk 24, compile/target 36 |
| camera 0.12.1 | 13.0+ | 24+ (CameraX) |
| video_player 2.14.0 | 13.0+ | 24+ |
| image_picker 1.2.3 | 13+ | 24+ |
| photo_manager 3.12.0 | 9.0 | 16 |
| pro_video_editor 2.16.0 | 13 (Package.swift + podspec) | minSdk 24, compileSdk 36, Media3 1.10.1 |
| Media3 (1.11.1, 2026-09-10) | — | **minSdk 23 since 1.9.0** |
| AVFoundation composition/export (`AVMutableComposition`, `AVVideoCompositionCoreAnimationTool`, `AVAssetExportSession`) | Long available; not a constraint at 15 | — |

**Result: iOS 15.0, Android minSdk 24**, compileSdk/targetSdk 36. Set these in the library's own Package.swift and podspec if it ever gets native code.
Runtime notes: Android 13+ granular `READ_MEDIA_IMAGES`/`READ_MEDIA_VIDEO` and Android 14+ `READ_MEDIA_VISUAL_USER_SELECTED` (photo_manager handles these; the host adds manifest entries).
iOS limited-library access. HEVC encode support varies on older Android, so default to H.264.
The iOS 27 SDK requires the UIScene lifecycle (Flutter handles it; plugins with lifecycle hooks need `FlutterSceneLifeCycleDelegate`).

---

## 6. Testing approach

Per [Testing plugins](https://docs.flutter.dev/testing/testing-plugins) (updated 2026-07-31): Dart unit tests need channels mocked; integration tests in `example/integration_test`
"are often the most important tests for a plugin", so have "at least one integration test of each platform channel call". Native unit tests use JUnit (`android/src/test`) and XCTest (`example/ios/RunnerTests`).
`integration_test` can't drive native UI: use **patrol**.

| Tier | Scope | Tooling |
|---|---|---|
| Unit (`test/`) | Layer model and transforms (normalised ↔ pixel, rotation/scale, canvas resize rescale); undo/redo; constraint validation (duration, size, MIME); trim maths; music pagination state machine with a fake `StoryMusicProvider`; result/metadata `toJson`; strings defaults; config `copyWith` | `flutter_test`, `mocktail` (already in the house dev deps) |
| Widget | Each screen (camera, gallery, editor, text tool, draw tool, music sheet, trim) with the internal services faked through the `_StoryScope` seam: fake camera preview, fake `MediaLibrary`, fake `StoryRenderer` returning a fixture file. Outcome paths: complete, cancel (each reason), fail (each error), permission-denied UI | `flutter_test`; `@visibleForTesting` constructor that takes the services |
| Golden | Overlay rendering (text styles, backgrounds, brushes); **the burn-in rasteriser output**, since what gets exported must match what was shown; theme variants; RTL | **[alchemist](https://pub.dev/packages/alchemist) 0.14.0** (Betterment/VGV, MIT, ~6 months ago): CI goldens (Ahem) for layout, plus platform goldens with real fonts loaded through `FontLoader` in tests for text fidelity |
| Integration (device) | `example/integration_test`: capture photo, record 3 s video, import from gallery fixture, add text and drawing and music, export. Assert the output file exists, MIME, dimensions 1080×1920, duration within tolerance, audio track present; sample frame pixels at an overlay location to prove burn-in | `integration_test`; runs on an Android emulator and an iOS simulator (camera is limited on simulators, so inject fixture media) |
| Native UI | Camera, microphone and photo permission dialogs; iOS limited-library picker | **[patrol](https://pub.dev/packages/patrol) 4.10.0** (LeanCode, Apache-2.0, ~9 days ago) |
| Platform channels (only if `story_creator_native` exists) | Dart: fake the generated Pigeon API class behind our own wrapper interface (Pigeon deprecated `dartTestOut`), or `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler`. Native: JUnit for the Media3 composition builder; XCTest for the AVFoundation composition builder. Plus one integration test per channel call | pigeon 29.x, JUnit, XCTest |
| Host E2E | The host app's Maestro flows (ADR-0015) cover open → complete/cancel through `Semantics(identifier:)` TestIds. **The library should accept or expose stable semantics identifiers** for its main controls, e.g. `StoryCreatorTestIds` constants | Maestro (host) |

CI: `flutter test` for unit, widget and CI goldens on Linux. Device integration runs nightly (or on renderer changes) on macOS runners with iOS simulators and Android emulators.
If native code exists, CI must test with both SwiftPM on and off.

---

## 7. Open decisions to settle in the library ADR
1. Relative versus `package:` imports inside the library (the house rule is relative-only; decide for publishability).
2. pro_video_editor as renderer v1: accept the single-maintainer and churn risk behind the interface, or spike our own Media3/AVFoundation renderer first. Audio mixing and overlay burn-in in pro_video_editor must be **spiked on real devices** before committing.
3. Whether to expose `StoryEditorController` (drafts, programmatic control) in v1, or keep the API to `open` and the widget.
4. Package name, if it will ever be published (`story_creator` is taken).
5. Material versus widgets-only internals, and when to move to `material_ui` (bundled Material deprecation is due November 2026).

## Sources (accessed 2026-09-25)
- https://pub.dev/packages/pro_image_editor · https://pub.dev/packages/pro_image_editor/versions · https://github.com/hm21/pro_image_editor (README, CHANGELOG, `lib/core/models/...` on `stable`)
- https://pub.dev/packages/pro_video_editor · https://github.com/hm21/pro_video_editor (`pubspec.yaml`, `android/build.gradle`, `darwin/pro_video_editor/Package.swift`, podspec)
- https://pub.dev/packages/video_editor · https://pub.dev/packages/stories_editor · https://pub.dev/packages/vs_story_designer · https://pub.dev/packages/flutter_story_editor · https://pub.dev/packages/story_maker · https://pub.dev/packages/story_creator · https://pub.dev/packages/image_editor_plus · https://pub.dev/packages/easy_video_editor · https://pub.dev/packages/lovoj_video_editor · https://pub.dev/packages/video_editor_sdk · https://pub.dev/packages/ffmpeg_kit_flutter_new
- https://pub.dev/packages/camera · https://pub.dev/packages/camera_avfoundation · https://pub.dev/packages/camera_android_camerax · https://pub.dev/packages/camerawesome · https://pub.dev/packages/photo_manager · https://pub.dev/packages/wechat_assets_picker · https://pub.dev/packages/wechat_camera_picker · https://pub.dev/packages/image_picker · https://pub.dev/packages/video_player · https://pub.dev/packages/just_audio · https://pub.dev/packages/pigeon · https://pub.dev/packages/mobx · https://pub.dev/packages/material_ui · https://pub.dev/packages/patrol · https://pub.dev/packages/alchemist
- GitHub API repo metadata for the repos above (stars, open issues, pushed_at, archived)
- https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors · https://docs.flutter.dev/reference/supported-platforms · https://flutter.dev/blog/whats-new-in-flutter-3-47 · https://docs.flutter.dev/release/breaking-changes · https://docs.flutter.dev/release/breaking-changes/uiscenedelegate · https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin · https://docs.flutter.dev/packages-and-plugins/developing-packages · https://docs.flutter.dev/testing/testing-plugins · https://docs.flutter.dev/ui/internationalization · https://docs.flutter.dev/release/breaking-changes/flutter-generate-i10n-source
- https://developer.android.com/jetpack/androidx/releases/media3 · https://dart.dev/tools/pub/workspaces · https://github.com/flutter/packages/blob/main/packages/pigeon/README.md · https://tanersener.medium.com/saying-goodbye-to-ffmpegkit-33ae939767e1
- Local: `docs/adr/0014-melos-package-split.md`, root `pubspec.yaml`, `packages/design_system/pubspec.yaml`
