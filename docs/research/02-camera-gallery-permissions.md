# Research 2 — Camera, gallery, permissions, media lifecycle

Agent 2 · observed 2026-09-25 · target Flutter 3.47.1 / Dart 3.13.1 · Android + iOS only.

Method: I read pub.dev pages (package, changelog, versions, API docs), GitHub repos and issues, and Android and Apple developer docs. I also sparse-cloned the plugin sources into scratchpad to confirm behaviour in code:
- `flutter/packages` at `7ab8ce1`, committed 2026-09-24
- `Baseflow/flutter-permission-handler`, last commit 2026-09-04
- `fluttercandies/flutter_photo_manager`, last commit 2026-08-27
- `Apparence-io/CamerAwesome`, last commit 2026-04-08

pub.dev shows relative dates ("21 days ago"). Absolute dates below are worked out from 2026-09-25 and are approximate (±1 day).

---

## 0. TL;DR recommendation

| Concern | Pick | Version (2026-09-25) | License | Publisher |
|---|---|---|---|---|
| Camera | `camera` (endorsed: `camera_android_camerax` + `camera_avfoundation`) | 0.12.1 (~2026-09-04); camerax 0.7.4+8 (~2026-09-11); avfoundation 0.10.3+1 (~2026-09-24); platform_interface 2.14.0 | BSD-3-Clause | flutter.dev (verified) |
| In-app gallery grid | `photo_manager` + `photo_manager_image_provider` | 3.12.0 (~2026-08-10) / 2.2.0 (~Oct 2024) | Apache-2.0 | fluttercandies (verified) |
| Fallback / "no permission" picker | `image_picker` (Android Photo Picker, iOS PHPicker) | 1.2.3 (~Jul 2026); image_picker_android 0.8.13+23 (~2026-09-12) | Apache-2.0 + BSD-3 | flutter.dev |
| Camera/mic pre-flight + open settings | `permission_handler` | 13.0.2 (~2026-09-05); android impl 14.1.0; apple impl 9.6.1 | MIT | Baseflow (verified) |
| Save to camera roll (export) | `gal` | 2.3.3 (publish date not captured) | BSD-3-Clause | midoridesign.studio (verified) |
| HEIC → JPEG normalisation (only if needed) | `flutter_image_compress` | 2.5.1 (~Jul 2026) | MIT | fluttercandies |

Rejected: `camerawesome`, because it is stale and blocked on AGP 9 (see §1.6). `wechat_assets_picker` is rejected as a dependency because we need our own design, but its `photo_manager` usage is a good reference.

---

## 1. Camera

### 1.1 Official `camera` — facts
- `camera` 0.12.1. The pubspec requires `sdk ^3.12.0`, `flutter >=3.44.0`. Android minSdk 24, iOS 13.0+. https://pub.dev/packages/camera
- Changelog: 0.12.1 adds `setJpegImageQuality`. 0.12.0+2 fixes a disposed controller updating its value after dispose. 0.12.0 adds video stabilization. 0.11.3 adds persistent recording on Android. 0.11.0 is a breaking change: the default Android implementation moved from `camera_android` (Camera2) to `camera_android_camerax`. https://pub.dev/packages/camera/changelog
- `camera_android_camerax` 0.7.4+8 uses CameraX 1.6.2. Recent entries: 0.7.4+5 fixes a leaked thread per capture, 0.7.4+4 fixes an NPE on dispose while recording, 0.7.2+1 moves to built-in Kotlin for AGP 9 (min Flutter 3.44), 0.7.1 removes the restrictions on concurrent use cases, 0.7.0 adds stabilization. https://pub.dev/packages/camera_android_camerax/changelog
- `camera_avfoundation` 0.10.3+1:
  - Swift migration is complete, and SwiftPM target exists (0.9.18+14).
  - 0.10.1 fixes an iPhone 17 crash with `ResolutionPreset.max`.
  - 0.9.23 moves the default output from Documents to the tmp directory.
  - 0.9.22+10 handles "video and audio interruptions and errors by pausing".

  https://pub.dev/packages/camera_avfoundation/changelog
- `camera_android` (Camera2, opt-in) 0.10.11+1 (~2026-08-29), BSD-3. Its README says "MediaRecorder does not work properly on emulators". https://pub.dev/packages/camera_android

### 1.2 Feature matrix (verified against `CameraController` source, camera 0.12.1)
| Need | API | Notes |
|---|---|---|
| Front/rear switch | `availableCameras()` + `setDescription(desc)` | **When not recording, `setDescription` = platform `dispose` + full re-init**, so the preview blacks out briefly (camera_controller.dart L448-462). **While recording** it calls `setDescriptionWhileRecording`. That works on iOS (swaps input, keeps the writer). On Android it needs `enablePersistentRecording: true`, which is the default, or the recording is cancelled. |
| Flash for photo | `setFlashMode(FlashMode.off/auto/always)` | iOS returns the error `setFlashModeFailed` "Device does not have flash capabilities" / "does not support this specific flash mode". **Hide the flash button** rather than catch the error. |
| Torch / flash during video | `FlashMode.torch` | iOS sets `captureDevice.torchMode = .on`. Android calls `CameraControl.enableTorch`. `always` does **not** light up video; the UI must map "flash on + video mode" → torch. Front cameras usually have no torch: plan a **screen-flash** (white overlay + max brightness) for selfies, as Instagram does. |
| Photo + video in one session | `takePicture()` / `startVideoRecording()` on the same controller | No re-init. Android binds `Preview+ImageCapture+ImageAnalysis` at init, and **binds `VideoCapture` lazily on first record**, unbinding ImageAnalysis when no stream callback is set. So the first record has extra latency. iOS: call `prepareForVideoRecording()` up front (adds the audio input; it is a no-op on Android) to remove the preview hiccup at record start. |
| Resolution | `ResolutionPreset.low/medium/high/veryHigh/ultraHigh/max` + `fps`, `videoBitrate`, `audioBitrate` | CameraX has no 240p and falls back to 480p. Recommend `veryHigh` (1080p) for stories. Avoid `max`: 4K means big files, and it caused the iPhone 17 crash history. |
| Max duration | **none** | `VideoCaptureOptions.maxDuration` is `@Deprecated('unused, ignored on all platforms')`. CameraX ignores `maxVideoDuration`. **We must run our own Dart timer and call `stopVideoRecording()`**. |
| Pause / resume recording | `pauseVideoRecording()` / `resumeVideoRecording()` | Both platforms. Enables "hold to record, release, hold again" segments without stitching. |
| Pinch zoom | `getMin/MaxZoomLevel()`, `setZoomLevel()` | **iOS min zoom is 1.0**. Virtual multi-lens devices (`.builtInDualWideCamera` etc.) are not discovered, so there is no smooth 0.5×. Open issue [#193230](https://github.com/flutter/flutter/issues/193230), opened 2026-09-23. On Android, CameraX can report min < 1.0. |
| Tap to focus / exposure | `setFocusPoint(Offset)`, `setExposurePoint(Offset)`, `setFocusMode`, `setExposureMode`, `setExposureOffset` | Coordinates are normalised 0..1. The front preview is mirrored, so flip x for front ([#108745](https://github.com/flutter/flutter/issues/108745)). CameraX 0.7.4+1 fixed a StateError when no AF points are available. |
| Stabilization | `getSupportedVideoStabilizationModes()`, `setVideoStabilizationMode(mode, allowFallback: true)` | Modes: `off`, `level1`..`level3` (more stabilisation = more latency). Supported on both since camera 0.12.0. |
| Orientation lock | `lockCaptureOrientation([DeviceOrientation])` / `unlock…` | Stories are portrait-only, so lock to `portraitUp`. |
| JPEG quality | `setJpegImageQuality(int)` | New in 0.12.1. |
| Photo format | always JPEG via `CameraController` | `setImageFileFormat` (HEIF) exists only on `CameraPlatform`, not the controller. So **our own captures are never HEIC**. |
| Audio | `enableAudio` (ctor) | If mic permission is denied, CameraX records without audio. iOS throws `AudioAccessDenied*`. |
| Image stream | `startImageStream`, `startVideoRecording(onAvailable:)` | Not needed for MVP. CameraX does not support `streamOptions`. |

### 1.3 Front-camera mirroring of saved files — inconsistent, verify on device
- iOS source (`DefaultCamera.swift` L157-159): the video data output connection sets `isVideoMirrored = true` for front cameras. **Recorded front videos are mirrored** (selfie view, matching the preview). The photo output keeps AVFoundation's default connection mirroring. Confirm on a device whether front photos come out mirrored.
- Android CameraX: the plugin never sets `MirrorMode` (grep for `MirrorMode` or `setMirror` found nothing). CameraX's `VideoCapture` default is `MIRROR_MODE_OFF`, so front videos are not mirrored. `ImageCapture` output depends on the device and OEM. [#72243](https://github.com/flutter/flutter/issues/72243) reports mirrored Android front photos. [#27650](https://github.com/flutter/flutter/issues/27650) ("Allow controlling the preview and output mirroring") is still **open, P3**.
- **Recommendation:** add a normalisation step in the library. Record `lensDirection` with each capture and apply a per-platform "flip needed" rule in the editor/export pipeline (the editor re-renders anyway), so saved output is consistent (Instagram saves front media un-mirrored). Build a device test matrix for this.

### 1.4 Lifecycle and interruptions
- README pattern (the plugin does not manage lifecycle since 0.5.0): on `AppLifecycleState.inactive` → `controller.dispose()`, on `resumed` → re-create. https://github.com/flutter/packages/blob/main/packages/camera/camera/README.md
  - Pitfall (commonly reported): on iOS, system permission dialogs, Control Center and notification pulls fire `inactive`. Guard re-init with an "initialising / permission request in flight" flag, and prefer disposing on `paused`/`hidden` rather than `inactive` on iOS. Stop and **finalise the recording before dispose**, so the clip is kept rather than lost.
- **Android camera loss**: CameraX `CameraState` errors are mapped to `CameraErrorEvent` strings (android_camera_camerax.dart L1459-1494):
  - `cameraInUse` ("already in use, possibly by a higher-priority camera client")
  - `maxCamerasInUse`
  - `otherRecoverableError` (CameraX retries)
  - `streamConfig`
  - `cameraDisabled` (device policy / background)
  - `cameraFatalError` (may need a reboot)
  - `doNotDisturbModeEnabled`
  - `unknown`

  A closing state emits `CameraClosingEvent`. On the app side these arrive as `CameraValue.errorDescription` (controller listener), not typed codes. **We must string-match or treat any error as "camera unavailable → retry button".**
- **iOS interruptions** (`DefaultCamera.swift` L237-262): the plugin observes `AVCaptureSession.wasInterruptedNotification` and **only sets `isRecordingDisconnected = true`**. The gap is cut out of the recording like a pause. `interruptionEndedNotification` is not observed, and **nothing is sent to Dart**. `runtimeErrorNotification` → `reportErrorMessage` → `onCameraError`.
  - Result: during a phone call, a FaceTime call, or iPad Split View (`videoDeviceNotAvailableWithMultipleForegroundApps`), the preview freezes or blacks out with no Dart signal. Our Dart timer also keeps running, so the UI duration drifts from the file duration.
  - Mitigation: combine lifecycle events, `onCameraError`, and a preview-frame watchdog if needed. Use the file's real duration after stop, not the timer.
  - Apple interruption reasons (JSON docs, 2026-09-25): `videoDeviceNotAvailableInBackground`, `audioDeviceInUseByAnotherClient` (phone call/alarm), `videoDeviceInUseByAnotherClient`, `videoDeviceNotAvailableWithMultipleForegroundApps`, `videoDeviceNotAvailableDueToSystemPressure` (thermal), `sensitiveContentMitigationActivated`. https://developer.apple.com/documentation/avfoundation/avcapturesession/interruptionreason
  - A related ecosystem report: mobile_scanner [#1771](https://github.com/juliansteenbakker/mobile_scanner/issues/1771) "Session interruptions are never observed … permanently blank viewfinder".
- **`CameraException` codes**: `camera_exception.dart` still has `// TODO: Document possible error codes`. The only documented codes are the permission ones: `CameraAccessDenied`, `CameraAccessDeniedWithoutPrompt`, `CameraAccessRestricted` (iOS), `AudioAccessDenied`, `AudioAccessDeniedWithoutPrompt`, `AudioAccessRestricted` (iOS). Others seen in source: `setFlashModeFailed`, `setDescriptionWhileRecordingFailed`, and state errors ("A video recording is already started", "Previous capture has not returned yet"). **The library must wrap everything into its own sealed `CaptureFailure` type.**
- Top open `p: camera` issues (by reactions):
  - #84957 slow takePicture on some devices
  - #57451 start/stopVideoRecording freezes UI
  - #114012 NPE in CameraCaptureSession.close
  - #92762 emulator CameraAccessException
  - #27650 mirroring

  https://github.com/flutter/flutter/issues?q=is%3Aissue+is%3Aopen+label%3A%22p%3A+camera%22

### 1.5 Output files
- iOS: `FileManager.default.temporaryDirectory/camera/...`. Video is **.mp4** via AVAssetWriter. Frames are rotated by `connection.videoOrientation`, so there is usually no rotation transform.
- Android: `context.getCacheDir()` temp files (`.jpg`, `.mp4`). CameraX `Recorder` writes **rotation metadata** into the MP4 rather than rotating pixels, so the editor/player must honour it.

### 1.6 `camerawesome` — compared and rejected
- 2.5.0, published **~15 months ago (~Jun 2025)**. Previous releases: 2.4.0 ~16 mo, 2.3.0 ~18 mo. https://pub.dev/packages/camerawesome/versions
- pub.dev shows **License: "Pending"** (unrecognised). The repo LICENSE is MIT text with "Copyright © Apparence.io". 1.2k stars, **193 open issues**. Last commit 2026-04-08 (a zoom bug merge). https://github.com/Apparence-io/CamerAwesome
- The build uses `apply plugin: 'kotlin-android'`, Kotlin 1.8.10, compileSdk 34. Open issue **#648 "Migrate plugin to built-in Kotlin" (2026-09-06)** means it is **not AGP-9 ready**, while Flutter 3.44+ and the endorsed camera plugins already moved.
- Open-issue themes in 2026: iOS crashes on iOS < 26 (#619), iPad preview broken (#625), no audio on subsequent recordings (#618), bitrate ignored (#642), aspect ratio no effect on iOS (#624).
- Features it has and `camera` lacks: built-in UI, live filters, multi-camera (beta), mirror option. None of these outweigh the maintenance risk for a reusable library.

**Camera verdict:** use `camera` with the endorsed implementations. Wrap it behind our own `CaptureController` interface, so we can later replace it with a thin native plugin for virtual-device zoom, interruption events and mirroring control if needed. Pin `camera: ^0.12.1`.

---

## 2. Gallery

### 2.1 Policy risk first (Android)
- Google Play Photo & Video Permissions policy (full compliance deadline 2025-05-28): apps may hold `READ_MEDIA_IMAGES`/`READ_MEDIA_VIDEO` only if "core functionality revolves around broad access". "Apps that have custom pickers are not automatically qualified … must still submit a declaration in Play Console". https://support.google.com/googleplay/android-developer/answer/14115180 · https://support.google.com/googleplay/android-developer/answer/15800983
- **Impact:** an in-app "Recent" grid requires broad media permission plus a Play declaration **for every host app that adopts our library**. Some host apps will be rejected, or will not want the permission. **The library must make the in-app grid optional and support a "system picker only" mode.**
- Android 14 partial access page (updated 2026-03-03): declare `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_VISUAL_USER_SELECTED`, and `READ_EXTERNAL_STORAGE maxSdk=32`. Request them together. Do not cache the grant. Provide reselection UI. Google's own recommendation is "Use the Photo Picker". https://developer.android.com/about/versions/14/changes/partial-photo-video-access
- Android **Embedded Photo Picker** (docs updated 2026-09-16): Android 14+ with SDK Ext 15, `androidx.photopicker:photopicker(-compose):1.0.0-alpha01`, SurfaceView-based, no permission needed. Flutter wrapper `embedded_photo_picker` (MIT, 0 stars, "experimental"): "Flutter content cannot reliably draw over the picker", needs compileSdk 37.1 / AGP 9.3.3. **Not production-ready. Watch it** as the future way to get an inline grid on Android without the permission. https://developer.android.com/training/data-storage/shared/photo-picker/embedded · https://github.com/abraham/embedded_photo_picker

### 2.2 `photo_manager` 3.12.0 (for the custom grid)
- Apache-2.0, fluttercandies (verified), published ~46 days before 2026-09-25. Last commit 2026-08-27. 770 stars, 47 open issues. SwiftPM `Package.swift` present (since 3.9.0). compileSdk 36, minSdk 16. Glide 4.16.0 is used for Android thumbnails. The Kotlin plugin is applied conditionally (`hasKotlinExtension`), so it works with built-in Kotlin. https://pub.dev/packages/photo_manager · https://github.com/fluttercandies/flutter_photo_manager
- Recent changelog:
  - 3.12.0 breaking: CoreLocation is no longer linked (location needs `photo_manager_location`). Good, no location key needed.
  - 3.11 Gradle 9.
  - 3.10 type filtering within albums.
  - 3.8.0 `cancelToken`, iOS 18 smart albums.
  - Android 14/15 partial-access fixes.
- Permissions:
  - `PhotoManager.requestPermissionExtend(requestOption: PermissionRequestOption(iosAccessLevel: IosAccessLevel.readWrite, androidPermission: AndroidPermission(type: RequestType.common, mediaLocation: false)))` → `PermissionState.authorized / limited / denied / restricted / notDetermined`. Use `RequestType.common` (image + video) so only needed media types are requested.
  - `PhotoManager.getPermissionState(...)` (3.4.0+) checks without prompting.
  - `PhotoManager.openSetting()`.
- Limited access: `PhotoManager.presentLimited(type:)` (iOS 14+ when state is limited, and Android 14 reselection). Set Info.plist `PHPhotoLibraryPreventAutomaticLimitedAccessAlert = YES` and show our own "Manage selection" banner.
  - README caveats: on Android a granted item cannot be revoked via `presentLimited`. A limited grant may contain only videos, so an image query legitimately returns 0.
- Albums: `getAssetPathList(hasAll: true, type: RequestType.common, filterOption: …)`. The root "Recent" / "All" path is first, which gives the "Recent >" album picker. Pagination with `getAssetListPaged(page:, size:)`. Sort via `FilterOptionGroup(orders: [OrderOption(type: OrderOptionType.createDate, asc: false)])`.
- Change notify: `PhotoManager.addChangeCallback`, `startChangeNotify`, `stopChangeNotify`. Refresh the grid after the user edits the limited selection or takes a photo elsewhere.
- Thumbnails: `thumbnailDataWithSize(ThumbnailSize(w,h), format: jpeg, quality:)`. For videos this returns a still image. In the grid use `AssetEntityImage(entity, isOriginal: false, thumbnailSize: ThumbnailSize.square(200), thumbnailFormat: ThumbnailFormat.jpeg)` from `photo_manager_image_provider` 2.2.0 (Apache-2.0, published ~23 months ago; stable, but note the age).
  - Performance: request at ~(cell px × devicePixelRatio). Cancel off-screen loads (`PMCancelToken`). Keep `cacheExtent` modest. On Android, Glide does the heavy lifting.
- Video fields: `type == AssetType.video`, `duration` (int seconds), `videoDuration` (Duration). Use these for the duration badge and the "longer than limit → trim" route. `FilterOptionGroup.durationConstraint` could hide long videos, but **don't hide them; route to the trimmer instead**.
- iCloud: `isLocallyAvailable(isOrigin:)`. Use `loadFile(isOrigin: true, progressHandler: PMProgressHandler(), cancelToken:)` to download with progress and a cancel option. Show a progress ring on the selection tile. `getMediaUrl()` gives a playable URL for preview without copying.
- `file` vs `originFile`:
  - `file` gives the "compressed" / system-rendered file (on iOS a JPEG rendition for HEIC, including user edits).
  - `originFile` gives the original with full EXIF. The docs warn that HEIC originals may not display on older Android (Android 10 example).
  - README: "We suggest you to upload the JPEG file (`.file` if the file is HEIC)".
  - `darwinFileType` (e.g. MOV → MP4 export) is available on `loadFile`.
- Cache: on iOS, `file`/`loadFile` copies assets into the plugin cache. Call `PhotoManager.clearFileCache()` when a story session ends.

### 2.3 `image_picker` 1.2.3 (system picker fallback)
- Android: on **Android 16+ gallery picks always use the Android Photo Picker** (`useAndroidPhotoPicker` has no effect). On ≤15, set `ImagePickerAndroid.useAndroidPhotoPicker = true`. No storage permission is needed, and the picker is backported through Google Play services. `limit` is reliable only on Android 13+. `retrieveLostData()` is required for Activity-death recovery. https://pub.dev/packages/image_picker_android
- iOS: PHPicker (iOS 14+) needs **no photo permission** when `requestFullMetadata: false`. HEIC cannot be picked on the simulator. https://pub.dev/packages/image_picker
- API: `pickMedia`, `pickMultipleMedia(limit:)`, `pickMultiImage(limit:)`, `pickMultiVideo(limit:, maxDuration:)`, `pickVideo(maxDuration:)`. `maxDuration` applies only to camera capture, so it is not a gallery filter. Handle long videos ourselves.

### 2.4 `wechat_assets_picker` 10.1.3
- Apache-2.0, fluttercandies, published ~2 months ago, Flutter ≥3.27. Built on `photo_manager ^3.5.0`, `extended_image`, `provider`, `video_player`. It provides a WeChat-style full UI with a custom delegate, a special item (camera tile), and a11y and RTL support. https://pub.dev/packages/wechat_assets_picker
- Rejected as a dependency: heavy, opinionated UI, and it would pull `provider`/`extended_image` into a reusable library. Use it as a **reference implementation** for delegate patterns, limited-access banners and iCloud progress.

### 2.5 Recommended gallery approach
1. Provide a `GallerySource` abstraction with two implementations:
   - **`InAppGallerySource` (photo_manager)**: our custom grid with "Recent >" album picker, selection circles and a camera tile.
   - **`SystemPickerSource` (image_picker)**.
2. The host app chooses the mode through config (`galleryMode: inApp | systemOnly | auto`). `auto` = in-app when permission is authorized or limited, system picker otherwise.
3. Flow:
   - `getPermissionState` → if `notDetermined`, show our rationale → `requestPermissionExtend`.
   - `authorized` → grid.
   - `limited` → grid plus a banner "You've given access to selected items · Manage" → `presentLimited` → change callback refresh.
   - `denied`/`restricted` → an empty-state card with "Open Settings" (`PhotoManager.openSetting`) **and** "Choose from library" (system picker, no permission).
4. On Android, a host that does not want `READ_MEDIA_*` in its manifest runs `systemOnly`. Document the manifest entries per mode.

---

## 3. Permissions

### 3.1 Who asks for what
| Permission | Who requests | Why |
|---|---|---|
| Camera | `permission_handler` (`Permission.camera`) **before** `CameraController.initialize()` | The camera plugin only requests implicitly at init and reports `CameraAccessDenied*` as an exception. It cannot pre-check, cannot tell "permanently denied", and cannot open settings. |
| Microphone | `permission_handler` (`Permission.microphone`) when the user first switches to video, or up front | If denied, allow photo-only, or video without audio (`enableAudio: false`). Note `enableAudio` is a ctor param, so switching needs a controller re-create. |
| Photos (read) | `photo_manager.requestPermissionExtend` | It understands limited access on both platforms and has `presentLimited`. **Don't double-request through permission_handler.** |
| Photos (add-only, save) | `gal.requestAccess()` or permission_handler `photosAddOnly` | Only at export. |

- `permission_handler` 13.0.2 (MIT, Baseflow, ~2026-09-05). 2.2k stars, 134 open issues. The 13.0.2 changelog says to **detect permanent denial on Android from the result of `request()`**, not `status`, and android 14.1.0 fixes a false "permanently denied" after "Ask every time". Source confirms that `checkPermissionStatus` never returns permanentlyDenied ("a status check cannot detect 'permanently denied'"). https://pub.dev/packages/permission_handler/changelog
  - So: call `request()`. If the result is `permanentlyDenied` (Android) or `denied`/`permanentlyDenied` after a previous prompt (iOS reports `permanentlyDenied` once the user has declined), show "Open Settings" → `openAppSettings()`. On return (`resumed`), re-check `status`.
- Android 14 partial media in permission_handler: source now maps `READ_MEDIA_VISUAL_USER_SELECTED` granted plus full denied → `PermissionStatus.limited` (PermissionManager.java L602-615). Older issue [#1243](https://github.com/Baseflow/flutter-permission-handler/issues/1243) (2023-12, still open) reported this as permanentlyDenied. This is another reason to use photo_manager for photos.

### 3.2 iOS Info.plist (host app; the library documents it)
- `NSCameraUsageDescription` (required)
- `NSMicrophoneUsageDescription` (required for video with audio)
- `NSPhotoLibraryUsageDescription` (in-app gallery)
- `NSPhotoLibraryAddUsageDescription` (save to camera roll)
- `PHPhotoLibraryPreventAutomaticLimitedAccessAlert` = `true` (we drive `presentLimited` ourselves)
- No location keys: photo_manager 3.12 dropped CoreLocation.

### 3.3 permission_handler iOS compile flags
- **SwiftPM is the default since Flutter 3.44**, and the CocoaPods trunk goes read-only on 2026-12-02. https://flutter.dev/blog/saying-goodbye-to-cocoapods-swift-package-manager-is-soon-the-default-in-flutter
  - With SwiftPM, permission_handler "automatically detects which permissions to enable by reading your app's Info.plist". A permission is compiled in when its usage key is present.
- CocoaPods fallback only: in the Podfile `post_install`, set `GCC_PREPROCESSOR_DEFINITIONS` with `'PERMISSION_CAMERA=1'`, `'PERMISSION_MICROPHONE=1'`, and (only if permission_handler is used for photos) `'PERMISSION_PHOTOS=1'`, `'PERMISSION_PHOTOS_ADD_ONLY=1'`. Unused permissions are 0 by default since v8.0.0. https://raw.githubusercontent.com/Baseflow/flutter-permission-handler/main/permission_handler/README.md
- All chosen iOS plugins have SwiftPM support: camera_avfoundation, photo_manager (`darwin/photo_manager/Package.swift`), permission_handler. CamerAwesome master has a Package.swift, but pub 2.5.0 is stale.

### 3.4 AndroidManifest (host app)
```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<!-- in-app gallery mode only (Play declaration required) -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>
<uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED"/>
<!-- saving via gal on API ≤29 -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29"/>
<!-- don't block installs on devices without a camera / front camera / flash -->
<uses-feature android:name="android.hardware.camera" android:required="false"/>
<uses-feature android:name="android.hardware.camera.front" android:required="false"/>
<uses-feature android:name="android.hardware.camera.flash" android:required="false"/>
```
- permission_handler requires compileSdk 35+ (v12.0.0).
- Leave out `READ_MEDIA_AUDIO`, even though the photo_manager README lists it for API 33. RequestType.common does not need it.
- Do not add `FOREGROUND_SERVICE_CAMERA`. It is only for background image streaming.

---

## 4. Media lifecycle

- **Temp files.** Camera output lands in iOS `tmp/camera/` and Android `cacheDir`. photo_manager copies into its own cache.
  - Library policy: create a per-session working dir (`getTemporaryDirectory()/story_creator/<sessionId>/`) and **move** captures into it right after `takePicture` / `stopVideoRecording`.
  - Delete the dir on publish, cancel or dispose.
  - On first use per app launch, sweep sessions older than N hours (crash leftovers).
  - Call `PhotoManager.clearFileCache()` at session end.
  - iOS may purge tmp when the app is not running, so never rely on tmp across launches (draft persistence belongs elsewhere).
- **Large videos.**
  - Never read into memory (`originBytes` warns "might be epic large"). Pass file paths or URIs.
  - Show iCloud download progress and let the user cancel.
  - Before import, check free disk space (a native call, or catch the write failure).
  - Cap capture at 1080p (`veryHigh`) with an explicit `videoBitrate` (for example ~8–10 Mbps) to keep files predictable.
- **HEIC/HEVC inputs.**
  - iPhone gallery photos are HEIC and videos are HEVC, often **HDR (HLG/Dolby Vision)**.
  - Flutter's Android HEIF decode fixes (flutter/flutter PR [#176860](https://github.com/flutter/flutter/pull/176860), merged 2025-10-18) cover the API 36 gain-map failure and the missing flip before API 36. They ship in Flutter 3.47.
  - For the editor canvas, prefer `AssetEntity.file` (JPEG rendition on iOS). Use `flutter_image_compress` only when a JPEG is needed from an Android HEIC (it needs API 28+ for HEIC, and `autoCorrectionAngle` bakes EXIF rotation).
  - Flag to the export agent: HDR HEVC sources need tone-mapping or SDR conversion during export, otherwise the output looks washed out. Low-end Android may lack HEVC decode. Test.
- **Orientation metadata.**
  - Photos: Flutter's image decoders apply EXIF orientation. Our camera JPEGs are upright via target rotation plus the portrait lock.
  - Videos: Android CameraX MP4s carry a **rotation matrix** (pixels not rotated). iOS camera MP4s are pixel-rotated. Gallery videos can be either.
  - The editor's video layer and the exporter must read and apply the track transform/rotation. `video_player` handles it for display. Use `orientatedWidth/Height` from photo_manager for layout before loading.
- **Too-long videos.** Don't reject. Use `videoDuration` from photo_manager (or from the file after a system pick) → if above the story limit (for example 60 s), open the **trimmer** with a default window [0, limit]. Trim natively (AVAssetExportSession `timeRange` / Media3 Transformer). Note that `ffmpeg_kit_flutter` was archived in Jan 2025 and its binaries were removed 2025-04-01, so avoid it.
- **Unavailable hardware.**
  - `availableCameras()` returns `[]` on the iOS Simulator and on camera-less devices, so show a "Camera unavailable" state with the gallery still usable.
  - Only one lens direction present: hide the flip button.
  - No flash (iPads, most front cameras): hide flash and offer screen-flash for the front camera.
  - Mic denied: photo-only, or silent video.
  - iPad Split View: capture interrupted, so show an overlay.
  - `CameraAccessRestricted` (MDM or Screen Time): no settings deep link helps, so show an explanatory message.

---

## 5. Testing

- **Unit and widget tests.**
  - `CameraPlatform` extends `PlatformInterface` with `verify(instance, _token)`, so a fake must `with MockPlatformInterfaceMixin` (from `plugin_platform_interface`) and be assigned to `CameraPlatform.instance` in `setUp`. The official `camera/test/camera_test.dart` does this.
  - Override `availableCameras`, `createCameraWithSettings`, `initializeCamera`, `onCameraInitialized` (emit a `CameraInitializedEvent`), `takePicture` (return an `XFile` of a fixture), `startVideoCapturing`/`stopVideoRecording`, `onCameraError`, and `buildPreview` (return a `Container`).
  - Better still, test against **our own `CaptureController` interface** and keep the `camera` adapter thin.
  - For photo_manager, use a fake behind our `GallerySource` interface. Its API is static, so it cannot be mocked directly.
  - permission_handler: use a wrapper service behind an interface, or mock the method channel `flutter.baseflow.com/permissions/methods`.
- **iOS Simulator.**
  - There is no camera, and `AVCaptureDevice` discovery returns nothing. Third-party virtual cameras exist (the CMIOExtension-based SimulatorCamera, and RocketSim) but are not reliable for CI.
  - Plan: in debug or E2E builds, a `FakeCaptureController` (injected by flavor or config) that returns fixture photos and videos and renders a static preview. Then Maestro can drive capture → editor → export on the simulator.
  - Real-device checklist: interruptions (phone or FaceTime call, Control Center, Split View on iPad), mirroring, torch, pause/resume, iCloud-only assets, limited access.
- **Android emulator** (docs updated 2026-03-06, https://developer.android.com/studio/run/emulator-use-camera).
  - AVD camera options: `Emulated`, `VirtualScene` (3D scene; import PNG/JPEG into the scene), `Webcam0` (host webcam passthrough).
  - Android 11+ emulators expose a Camera2 **LEVEL_3** device with logical camera, stabilization and concurrent cameras. Earlier versions are basic only.
  - CameraX needs an **API 30+ emulator**. `camera_android` (Camera2/MediaRecorder) records broken audio videos on emulators.
  - Photo, video, front/back switch and zoom can be exercised. Flash and torch are not meaningful. The emulator photo picker works.
  - `go_offline`-style Maestro subflows are irrelevant here. Use `adb push` to seed the MediaStore with fixture media (then `am broadcast` a media scan or `content` insert) for gallery flows.

---

## 6. Key risks (ranked)

1. **Play policy for the in-app grid.** Needs `READ_MEDIA_*` and a declaration per host app. Mitigation: optional grid, system-picker mode, watch the Android embedded picker.
2. **iOS interruptions are not surfaced to Dart.** A silent frozen preview and a drifting timer. Mitigation: lifecycle, `onCameraError` and a watchdog. Optionally upstream a PR or write a small native helper.
3. **No max-duration or segment timing in the plugin.** Our Dart timer drives stop. Use the file's real duration afterwards.
4. **Front-camera mirroring differs per platform and output type**, with no API to control it (#27650). Normalise in export and add a device matrix.
5. **Camera flip = session rebuild** (black flash) when not recording, and no smooth 0.5× on iOS (#193230). Mitigation: a snapshot or blur overlay during the switch.
6. **HDR/HEVC/HEIC gallery inputs and video rotation metadata** feed the editor/export pipeline. This is a cross-agent contract.
7. **The `CameraException` code surface is undocumented.** Wrap all errors in our own sealed failure types, and track them via the host's issue tracker.
8. The SwiftPM default plus CocoaPods sunset (2026-12-02). All chosen plugins support SwiftPM, but document the Podfile macros for CocoaPods holdouts.

## 7. Sources (accessed 2026-09-25)
- https://pub.dev/packages/camera · /changelog · https://pub.dev/documentation/camera/latest/camera/CameraController-class.html
- https://pub.dev/packages/camera_android_camerax · /changelog · https://pub.dev/packages/camera_avfoundation · /changelog · https://pub.dev/packages/camera_android
- https://github.com/flutter/packages (sources at 7ab8ce1, 2026-09-24), README: /packages/camera/camera/README.md
- https://github.com/flutter/flutter/issues/193230 · /27650 · /72243 · /108745
- https://pub.dev/packages/camerawesome · /versions · https://github.com/Apparence-io/CamerAwesome · /issues
- https://pub.dev/packages/photo_manager · /changelog · https://github.com/fluttercandies/flutter_photo_manager · https://pub.dev/packages/photo_manager_image_provider
- https://pub.dev/packages/image_picker · https://pub.dev/packages/image_picker_android · https://pub.dev/packages/wechat_assets_picker
- https://pub.dev/packages/permission_handler · /changelog · https://github.com/Baseflow/flutter-permission-handler · issue #1243
- https://pub.dev/packages/gal · https://pub.dev/packages/flutter_image_compress
- https://developer.android.com/about/versions/14/changes/partial-photo-video-access · https://developer.android.com/training/data-storage/shared/photo-picker/embedded · https://developer.android.com/studio/run/emulator-use-camera
- https://support.google.com/googleplay/android-developer/answer/14115180 · https://support.google.com/googleplay/android-developer/answer/15800983
- https://developer.apple.com/documentation/avfoundation/avcapturesession/interruptionreason · WWDC20 10641 "Handle the Limited Photos Library"
- https://flutter.dev/blog/saying-goodbye-to-cocoapods-swift-package-manager-is-soon-the-default-in-flutter
- https://github.com/flutter/flutter/pull/176860 (HEIF decode fix) · https://github.com/abraham/embedded_photo_picker
