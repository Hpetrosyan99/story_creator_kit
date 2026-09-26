# story_creator_kit

<table>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/Hpetrosyan99/story_creator_kit/main/docs/demo/demo_1_capture_and_create.gif" width="240" alt="Capture a photo, add styled text, a sticker and a drawing, export"></td>
    <td align="center"><img src="https://raw.githubusercontent.com/Hpetrosyan99/story_creator_kit/main/docs/demo/demo_2_gallery_and_music.gif" width="240" alt="Pick from the gallery, apply filters, add music and choose a segment"></td>
    <td align="center"><img src="https://raw.githubusercontent.com/Hpetrosyan99/story_creator_kit/main/docs/demo/demo_3_video_trim_and_audio.gif" width="240" alt="Record a video, trim it, mute the audio, add an emoji"></td>
  </tr>
  <tr>
    <td align="center"><b>Capture &amp; create</b></td>
    <td align="center"><b>Gallery &amp; music</b></td>
    <td align="center"><b>Video: trim &amp; audio</b></td>
  </tr>
</table>

<sub>Recorded on the iOS Simulator with <code>isLiquidGlassEnabled: true</code>.</sub>

An Instagram-style story creator for Flutter apps on iOS and Android. It
covers the whole flow: camera, gallery, editor (text, drawing, stickers,
emoji, filters, music, trim), native export to JPEG or MP4, and a preview of
the exported file. Your app gets a file plus metadata back.

```dart
final outcome = await StoryCreator.open(context);
if (outcome case StoryCompleted(:final result)) {
  upload(result.path); // 1080×1920 JPEG or H.264/AAC MP4
}
```

The library never talks to a backend. You bring the music catalog, fonts and
stickers, and you decide what happens with the file.

## Contents

- [Features](#features)
- [Installation](#installation)
- [iOS setup](#ios-setup)
- [Android setup](#android-setup)
- [Quick start](#quick-start)
- [Configuration reference](#configuration-reference)
- [Music: `StoryMusicProvider`](#music-storymusicprovider)
- [Result and metadata](#result-and-metadata)
- [Replacing services](#replacing-services)
- [Errors and events](#errors-and-events)
- [Testing](#testing)
- [Known limitations](#known-limitations)
- [License](#license)

## Features

- **Camera**: tap to take a photo, hold to record a video, with a progress
  ring and timer. Recording stops at the configured maximum. You also get
  front/rear switch, flash (and torch for video), pinch and drag-to-zoom, and
  tap to focus. The camera handles backgrounding and interruptions.
- **Gallery**: an in-app "Recent" grid with album switching, video duration
  badges, limited-access handling and iCloud downloads. There is also a
  permission-free system-picker mode.
- **Editor**:
  - **Text** with host fonts, a colour palette, three alignments and four
    background styles (none, solid, translucent, per-line highlight). Edit
    in place; move, pinch, rotate, drag to the trash.
  - **Drawing** with pen, marker, neon and eraser, several sizes and colours.
  - **Stickers and emoji**. Stickers are any `ImageProvider`.
  - **Colour filters** (4×5 matrices), chosen from a strip or by swiping.
  - **Music** from your own catalog. The user picks the segment on a
    waveform and sets the volume. It mixes with the video's own audio.
  - **Video trim**, mute and original-audio volume.
  - **Undo/redo** across all tools. Edits survive a round trip through the
    preview.
  - **Accessibility**: semantics labels, 48 pt targets, and a non-gesture
    adjust panel for moving, resizing, rotating and deleting overlays.
- **Native export**: AVFoundation on iOS, Media3 Transformer on Android. No
  FFmpeg, no extra binary size, hardware encoding. Photos export as JPEG
  1080×1920. Videos and photo + music export as MP4 1080×1920, 30 fps,
  H.264 High and AAC-LC 128 kbps. Progress and cancel are built in.
- **Export equals preview**: one document model and the same painters render
  the editor and the exported frame.
- **Preview** plays the exported file and can save it to the device gallery.
- **Fully configurable**: theme, every string (for your own i18n), limits,
  tools, fonts, stickers, filters and output. Every platform service can be
  replaced, e.g. with a simulated camera.

## Installation

```yaml
dependencies:
  story_creator_kit: ^0.2.0
```

Requirements:

| | Minimum |
|---|---|
| Flutter | 3.47 |
| Dart | 3.13 |
| iOS | 16.0 |
| Android | 8.0 (API 26), compileSdk 36 |

Only iOS and Android are supported. Web and desktop are not.

## iOS setup

1. **Deployment target 16.0.** Set it in Xcode (Runner → General → Minimum
   Deployments). If you use CocoaPods, also set it in `ios/Podfile`:

   ```ruby
   platform :ios, '16.0'
   ```

2. **Info.plist usage descriptions.** iOS terminates the app when it asks for
   a permission that has no usage description. Add the keys you need to
   `ios/Runner/Info.plist`:

   ```xml
   <key>NSCameraUsageDescription</key>
   <string>The camera is used to capture photos and videos for your story.</string>
   <key>NSMicrophoneUsageDescription</key>
   <string>The microphone records sound for your story videos.</string>
   <!-- In-app gallery grid (GalleryMode.inApp) -->
   <key>NSPhotoLibraryUsageDescription</key>
   <string>Your photo library is used to pick photos and videos for your story.</string>
   <!-- Saving to the gallery (SaveToGalleryMode.button / always) -->
   <key>NSPhotoLibraryAddUsageDescription</key>
   <string>Finished stories can be saved to your photo library.</string>
   <!-- The creator shows its own "Manage selection" banner for limited access -->
   <key>PHPhotoLibraryPreventAutomaticLimitedAccessAlert</key>
   <true/>
   ```

   With `GalleryMode.systemPicker` you can leave out
   `NSPhotoLibraryUsageDescription`, because PHPicker needs no permission.

3. **Swift Package Manager or CocoaPods.** The plugin ships both a
   `Package.swift` and a podspec, and so do its dependencies.
   `permission_handler` only compiles in the permissions you enable:
   - With **Swift Package Manager**, it reads the usage keys in your
     Info.plist. Nothing else to do.
   - With **CocoaPods**, enable camera and microphone in the `post_install`
     hook of `ios/Podfile`. Photo access goes through `photo_manager` and
     `gal`, so you don't need `PERMISSION_PHOTOS`.

     ```ruby
     post_install do |installer|
       installer.pods_project.targets.each do |target|
         flutter_additional_ios_build_settings(target)
         target.build_configurations.each do |config|
           config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
             '$(inherited)',
             'PERMISSION_CAMERA=1',
             'PERMISSION_MICROPHONE=1',
           ]
         end
       end
     end
     ```

4. **Permission behaviour.** The creator checks camera and microphone access
   before it opens the camera. If camera access is denied, it explains why it
   needs the camera, offers **Open settings**, and keeps the gallery usable.
   If the microphone is denied, videos record without sound and the user is
   told so. If photo access is limited, a banner lets the user change the
   selection. iOS shows each system prompt only once; after that only the
   Settings app can change the answer.

The plugin ships a privacy manifest (`PrivacyInfo.xcprivacy`). The iOS
Simulator has no camera; see [Replacing services](#replacing-services).

## Android setup

1. **minSdk 26** in `android/app/build.gradle.kts`, and compileSdk 36:

   ```kotlin
   android {
       compileSdk = 37 // permission_handler 13 requires 37
       defaultConfig {
           minSdk = 26
       }
   }
   ```

2. **Manifest permissions** in `android/app/src/main/AndroidManifest.xml`.
   Declare only what your gallery mode needs. Add
   `xmlns:tools="http://schemas.android.com/tools"` to the `<manifest>` tag:
   it is needed for the `tools:replace` below.

   ```xml
   <!-- Always: camera and microphone -->
   <uses-permission android:name="android.permission.CAMERA" />
   <uses-permission android:name="android.permission.RECORD_AUDIO" />
   <uses-feature android:name="android.hardware.camera" android:required="false" />

   <!-- GalleryMode.inApp only: broad media access (see the Play policy below) -->
   <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
   <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
   <uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED" />
   <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
       android:maxSdkVersion="32" />

   <!-- Saving to the gallery on Android 10 and below (gal). The camera plugin
        declares this permission with maxSdkVersion 28; tools:replace keeps 29,
        otherwise the manifest merge fails. -->
   <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
       android:maxSdkVersion="29"
       tools:replace="android:maxSdkVersion" />

   <!-- Only if your music provider returns MusicUrlSource tracks -->
   <uses-permission android:name="android.permission.INTERNET" />
   ```

3. **Google Play photo and video permissions policy.** Google Play lets an app
   hold `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` only when its core function
   needs broad media access, and you must submit a declaration in the Play
   Console. An in-app picker does not qualify automatically. Every app that
   uses `GalleryMode.inApp` needs its own declaration, and Google may reject
   it. See [Google's policy page](https://support.google.com/googleplay/android-developer/answer/14115180).

   If your app does not qualify, use the system picker. It needs no media
   permission at all:

   ```dart
   const StoryCreatorConfig(
     capture: CaptureOptions(galleryMode: GalleryMode.systemPicker),
   );
   ```

   In that mode, leave out the `READ_MEDIA_*` permissions. `photo_manager`
   still merges `READ_EXTERNAL_STORAGE` (maxSdk 32) into your manifest. That
   permission is outside the Play media policy, but you can strip it:

   ```xml
   <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
       tools:node="remove" />
   ```

   (declare `xmlns:tools="http://schemas.android.com/tools"` on `<manifest>`).
   The system picker is the Android Photo Picker, backported to older
   versions through Google Play services.

4. **R8 / ProGuard.** The plugin needs no keep rules of its own. Media3 and
   the other plugins ship consumer rules. The plugin's own classes are
   reached only through the generated Pigeon channel. Test an export in a
   release build anyway (`flutter run --release`) before you ship.

5. **Media3 version.** The export engine uses Media3 Transformer **1.10.1**.
   1.11.0–1.11.1 have an export regression on some Samsung devices,
   [androidx/media#3399](https://github.com/androidx/media/issues/3399).
   Gradle resolves every `androidx.media3` module to the highest requested
   version. The older ExoPlayer that `video_player` and `just_audio` request
   is lifted to 1.10.1 automatically. If your app or another plugin asks for
   a *newer* Media3, our modules move up with it. Either verify video export
   on your target devices, or pin all `androidx.media3` modules to one
   version with a dependency constraint.

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

class NewStoryButton extends StatelessWidget {
  const NewStoryButton({super.key});

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: () => _create(context),
    child: const Text('New story'),
  );

  Future<void> _create(BuildContext context) async {
    final outcome = await StoryCreator.open(context);
    switch (outcome) {
      case StoryCompleted(:final result):
        debugPrint('Story at ${result.path} (${result.mimeType})');
      case StoryCancelled(:final reason):
        debugPrint('No story: ${reason.name}');
      case StoryFailed(:final error):
        debugPrint('Story creator failed: $error');
    }
  }
}
```

`StoryCreator.open` pushes a full-screen route and completes when it closes.
If you manage your own routes, push `StoryCreatorPage` yourself. Its
`onFinished` callback runs exactly once:

```dart
Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (context) => StoryCreatorPage(
      config: config,
      onFinished: (outcome) {
        Navigator.of(context).pop();
        handleOutcome(outcome);
      },
    ),
  ),
);
```

## Configuration reference

Every option has a default, so `const StoryCreatorConfig()` works. A fuller
setup:

```dart
final config = StoryCreatorConfig(
  theme: const StoryCreatorTheme(
    fontFamily: 'Onest',
    isLiquidGlassEnabled: true,
  ),
  strings: const StoryCreatorStrings(),
  capture: const CaptureOptions(
    initialLens: StoryCameraLens.back,
    galleryMode: GalleryMode.inApp,
    resolution: CaptureResolution.high,
  ),
  constraints: const MediaConstraints(
    maxVideoDuration: Duration(seconds: 60),
    minVideoDuration: Duration(seconds: 1),
    photoWithMusicDuration: Duration(seconds: 15),
  ),
  editor: EditorOptions(
    fonts: const [
      StoryFont(id: 'inter', label: 'Classic', family: 'Inter'),
      StoryFont(id: 'pacifico', label: 'Script', family: 'Pacifico', height: 1.4),
    ],
    stickers: const [
      StorySticker(
        id: 'star',
        label: 'Star',
        image: AssetImage('assets/stickers/star.png'),
      ),
    ],
    filters: StoryFilter.defaults,
  ),
  output: const OutputOptions(
    saveToGallery: SaveToGalleryMode.button,
    jpegQuality: 90,
  ),
  musicProvider: MyMusicProvider(),
  onEvent: (event) => debugPrint('$event'),
);
```

### Theme: `StoryCreatorTheme`

The creator never reads your app's `ThemeData`. Every colour and text style
comes from `StoryCreatorTheme`. The default is a dark UI with an orange
accent.

| Field | Default | Used for |
|---|---|---|
| `background` | `#141414` | page behind the canvas card |
| `surface`, `surfaceVariant` | `#1F1F21`, `#2D2D30` | panels, music chip, playing row; chips, camera tile |
| `onSurface`, `onSurfaceSecondary`, `onSurfaceMuted` | white, `#C2C2C2`, `#737373` | text and icons; unselected modes; artists, placeholders |
| `outline` | `#525257` | borders |
| `accent`, `onAccent` | `#CF5835`, white | primary actions, selection, progress |
| `error` | `#D92D20` | errors, the recording shutter |
| `controlBackground` | rgba(31,31,33,0.4) | 44 px round buttons on the canvas |
| `pillBackground` | rgba(20,20,20,0.5) | Video/Photo toggle, lens switch, save pill |
| `scrim` | black 40% | dialogs, export overlay, segment selector |
| `isLiquidGlassEnabled` | `false` | frosted "liquid glass" rendering of the translucent controls |
| `fontFamily`, `fontPackage` | platform font | the library's own UI text (the design uses Onest) |
| `cornerRadius`, `chipRadius` | 16, 999 | canvas card and thumbnails, pills |

**Liquid glass.** With `isLiquidGlassEnabled: true`, the close/confirm
buttons, the Video/Photo toggle, the lens switch and the music
chip render as frosted glass: a saturated backdrop blur with a light rim and
sheen. It uses `BackdropFilter.grouped` under one `BackdropGroup`, so all
glass controls share a single backdrop read. With `false` they use the flat
fills above.

**Fonts.** The library ships no UI font. Bundle one in your app and set
`fontFamily` (the design uses [Onest](https://fonts.google.com/specimen/Onest),
SIL OFL). Variable fonts work: text styles set the `wght` axis.

`copyWith` changes single values:
`const StoryCreatorTheme().copyWith(accent: brandColor)`.

### Strings and localisation: `StoryCreatorStrings`

Every user-visible string is a field, including semantics labels, with an
English default. The strings are grouped by screen: `common`, `camera`,
`editor`, `music` and `export`. To localise, build the strings from your own
localisation system and override what you need. Anything you leave out stays
English.

```dart
StoryCreatorStrings germanStrings() => const StoryCreatorStrings(
  common: CommonStrings(close: 'Schließen', done: 'Fertig', retry: 'Erneut versuchen'),
  camera: CameraStrings(takePhoto: 'Foto aufnehmen', recent: 'Neueste'),
  editor: EditorStrings(text: 'Text', draw: 'Zeichnen', export: 'Story teilen'),
  export: ExportStrings(useStory: 'Story verwenden'),
);
```

Canvas text is laid out in fixed canvas units with OS text scaling turned
off. That keeps line breaks the same on screen and in the export.

### Capture: `CaptureOptions`

| Field | Default | |
|---|---|---|
| `initialLens` | `StoryCameraLens.back` | lens when the camera opens |
| `enablePhoto` / `enableVideo` | `true` / `true` | tap for photo, hold for video |
| `enableAudio` | `true` | record sound (needs the microphone) |
| `enableFlash`, `enableLensSwitch`, `enableZoom` | `true` | controls stay hidden when the hardware lacks them |
| `galleryMode` | `GalleryMode.inApp` | `inApp` grid, `systemPicker` (no permission), or `disabled` |
| `resolution` | `CaptureResolution.high` | `medium` ≈ 720p, `high` ≈ 1080p, `max` |

### Limits: `MediaConstraints`

| Field | Default | |
|---|---|---|
| `maxVideoDuration` | 60 s | recording stops here; longer gallery videos open in the trimmer at `[0, max]` |
| `minVideoDuration` | 1 s | shorter recordings are discarded with a notice |
| `photoWithMusicDuration` | 15 s | length of a photo + music story, clamped to the maximum and the track |
| `allowPhotos` / `allowVideos` | `true` | limit the media types |
| `maxImportFileSizeBytes` | none | rejects larger picked files (`StoryErrorCode.mediaTooLarge`) |

### Editor: `EditorOptions`

| Field | Default | |
|---|---|---|
| `enableText`, `enableDrawing`, `enableStickers`, `enableFilters`, `enableMusic`, `enableTrim`, `enableAudioMix` | `true` | show or hide tools (music also needs a provider) |
| `fonts` | `[StoryFont.system]` | fonts in the text tool, first is the default; must not be empty |
| `textColors`, `brushColors` | 10 colours | palettes |
| `brushSizes` | `[8, 16, 28, 44]` | canvas units (the canvas is 1080 wide) |
| `stickers` | none | your stickers |
| `emojis` | 32 common emoji | emoji tab |
| `filters` | `StoryFilter.defaults` | first is the default |
| `maxOverlays` | 30 | text + sticker limit |
| `confirmDiscard` | `true` | ask before throwing edits away |

**Fonts.** The library refers to fonts by family name. Bundle them in your
app's `pubspec.yaml` as usual. A font from a package sets `package`. A font
you download at runtime supplies a `loader`, which the editor and the export
both await before they draw with it:

```dart
final fonts = [
  const StoryFont(id: 'inter', label: 'Classic', family: 'Inter'),
  const StoryFont(
    id: 'mono',
    label: 'Typewriter',
    family: 'SpaceMono',
    uppercase: true,
    letterSpacing: 2,
  ),
  StoryFont(
    id: 'brand',
    label: 'Brand',
    family: 'BrandSans',
    loader: () async {
      final loader = FontLoader('BrandSans')
        ..addFont(rootBundle.load('assets/fonts/BrandSans.ttf'));
      await loader.load();
    },
  ),
];
```

Keep `id` stable. It is reported in the result metadata.

**Stickers** can come from any `ImageProvider`: `AssetImage`, `FileImage`,
`NetworkImage`, `MemoryImage`. Transparent PNG or WebP works best. The
export draws stickers again, so network stickers must still be reachable
when the user exports.

**Filters** are 4×5 row-major colour matrices with the same semantics as
`ColorFilter.matrix` (the fifth column is an offset in 0–255). The native
video export applies the same matrix, so preview and export match.
`StoryFilter.defaults` holds eight filters, starting with
`StoryFilter.original`. To add your own:

```dart
const brand = StoryFilter(
  id: 'brand_warm',
  label: 'Brand',
  matrix: [
    1.08, 0, 0, 0, 12, //
    0, 1.0, 0, 0, 4,
    0, 0, 0.9, 0, -8,
    0, 0, 0, 1, 0,
  ],
);
final options = EditorOptions(filters: [StoryFilter.original, brand, ...StoryFilter.defaults.skip(1)]);
```

### Output: `OutputOptions`

| Field | Default | |
|---|---|---|
| `jpegQuality` | 90 | photo stories, 1–100 |
| `videoBitrate` | 8 Mbit/s | H.264 target bitrate |
| `frameRate` | 30 | output frame rate |
| `saveToGallery` | `SaveToGalleryMode.button` | `never`, `button` (a Save button in the preview) or `always` (save on confirm) |
| `galleryAlbum` | none | album name when saving |
| `showPreview` | `true` | show the exported file before returning it |
| `outputDirectory` | `<temp>/story_creator_exports` | where the result is written |

The result file is **yours**: the library never deletes it. The default
folder is inside the app's temporary directory, which the OS may clear. Move
the file if you need to keep it. Captures, overlays and cached music live in
a per-session temp folder, which is removed when the creator closes.
Leftovers from crashed sessions are swept on the next start.

When `SaveToGalleryMode.always` fails (for example, the user refused
add-only photo access), the story is still returned with
`savedToGallery == false`. An error event is reported.

## Music: `StoryMusicProvider`

The music tool appears when you pass a `musicProvider` and
`EditorOptions.enableMusic` is on. The library doesn't know where your music
comes from. You implement four members:

| Member | |
|---|---|
| `categories` | chips such as All / Bookmarked / Trending; the first is selected initially |
| `fetchTracks(MusicQuery)` | one page of tracks for a category, search text and cursor; throw to show the error state with retry |
| `resolve(MusicTrack)` | where the audio is: `MusicFileSource(path)`, `MusicAssetSource(key)` or `MusicUrlSource(uri, headers:)` |
| `supportsBookmarks` / `setBookmarked` | optional bookmark buttons |

URL tracks stream for preview and are downloaded into the session folder
before export. Export always needs a local file. Supported formats are
AAC/M4A, MP3 and WAV. If a track carries `waveform` peaks (0–1, evenly
spaced), the segment selector uses them. Otherwise it reads peaks from the
file.

An in-memory provider over bundled assets, with search, cursor pagination
and bookmarks:

```dart
class BundledMusicProvider extends StoryMusicProvider {
  BundledMusicProvider(this._tracks);

  final List<MusicTrack> _tracks;
  final Set<String> _bookmarks = {};

  @override
  List<MusicCategory> get categories => const [
    MusicCategory(id: 'all', label: 'All'),
    MusicCategory(id: 'bookmarked', label: 'Bookmarked'),
  ];

  @override
  bool get supportsBookmarks => true;

  @override
  Future<MusicPage> fetchTracks(MusicQuery query) async {
    final search = query.search.trim().toLowerCase();
    final matches = [
      for (final track in _tracks)
        if ((query.categoryId != 'bookmarked' || _bookmarks.contains(track.id)) &&
            (search.isEmpty ||
                track.title.toLowerCase().contains(search) ||
                track.artist.toLowerCase().contains(search)))
          track.copyWith(bookmarked: _bookmarks.contains(track.id)),
    ];
    final start = int.tryParse(query.cursor ?? '') ?? 0;
    final end = (start + query.pageSize).clamp(0, matches.length);
    return MusicPage(
      tracks: matches.sublist(start, end),
      nextCursor: end < matches.length ? '$end' : null,
    );
  }

  @override
  Future<MusicSource> resolve(MusicTrack track) async =>
      MusicAssetSource('assets/music/${track.id}.m4a');

  @override
  Future<void> setBookmarked(MusicTrack track, {required bool bookmarked}) async {
    if (bookmarked) {
      _bookmarks.add(track.id);
    } else {
      _bookmarks.remove(track.id);
    }
  }
}

final provider = BundledMusicProvider(const [
  MusicTrack(
    id: 'sunrise_drive',
    title: 'Sunrise Drive',
    artist: 'Example',
    duration: Duration(seconds: 66),
    extra: {'licence': 'CC0'},
  ),
]);
```

Anything in `MusicTrack.extra` (licence ids, analytics tags) comes back
untouched in the result metadata. **You are responsible for licensing the
music you offer.** The example app ships self-generated CC0 loops for this
reason.

## Result and metadata

`StoryCompleted.result` is a `StoryResult`:

| Field | |
|---|---|
| `path` | absolute path of the JPEG or MP4 |
| `type`, `mimeType` | `photo` / `image/jpeg` or `video` / `video/mp4` (a photo with music is a video) |
| `width`, `height` | 1080 × 1920 |
| `fileSizeBytes` | file size |
| `duration` | video length, `null` for photos |
| `thumbnailPath` | JPEG poster frame for videos |
| `savedToGallery` | whether it was saved to the device gallery |
| `metadata` | what went into the story (below) |

`StoryMetadata` describes the content, e.g. for analytics or moderation:

| Field | |
|---|---|
| `source`, `sourceType` | camera or gallery; photo or video source |
| `createdAt` | export time |
| `trimStart`, `trimEnd` | kept part of a source video |
| `originalAudioVolume` | 0–1 (0 = muted; 0 for photos) |
| `music` | `StoryMusicMetadata`: `trackId`, `title`, `artist`, `start`, `duration`, `volume`, `extra` |
| `filterId` | selected `StoryFilter.id` |
| `texts` | `StoryTextMetadata`: `text`, `fontId`, `colorValue`, bottom to top |
| `stickerIds`, `emojis` | used stickers and emoji, bottom to top |
| `hasDrawing` | whether there are freehand strokes |

```dart
void describe(StoryResult result) {
  final m = result.metadata;
  debugPrint('${result.type.name} ${result.width}×${result.height}, '
      '${result.fileSizeBytes} bytes, from ${m.source.name}');
  if (m.music case final music?) {
    debugPrint('music ${music.trackId} from ${music.start} for ${music.duration}');
  }
  for (final text in m.texts) {
    debugPrint('text "${text.text}" in ${text.fontId}');
  }
}
```

## Replacing services

The platform services live behind interfaces in a separate library:

```dart
import 'package:story_creator_kit/services.dart';
```

| Interface | Default implementation |
|---|---|
| `CaptureService` | `camera` plugin |
| `GallerySource` | `photo_manager` grid, or `image_picker` for the system picker |
| `PermissionService` | `permission_handler` |
| `MediaInspector` | native probe, waveform and thumbnails |
| `MusicSession`, `VideoSession` | `just_audio`, `video_player` |
| `StoryExporter`, `GallerySaver` | native export, `gal` |

Start from the platform set and replace single services. For example, you
can swap in a simulated camera on the iOS Simulator, which has no camera:

```dart
StoryServices storyServices(StoryCreatorConfig config) {
  final services = StoryServices.platform(config);
  return isIosSimulator
      ? services.copyWith(createCapture: SimulatedCaptureService.new)
      : services;
}

await StoryCreator.open(
  context,
  config: config,
  services: storyServices(config),
);
```

`createCapture` is a factory. It runs each time the camera screen opens. A
complete `SimulatedCaptureService` (animated preview, rendered photos, a
bundled clip as the "recording") is in
[`example/lib/simulated_capture_service.dart`](example/lib/simulated_capture_service.dart).
Implementations report failures as `StoryException`s with a matching
`StoryErrorCode`.

## Errors and events

`StoryFailed` is returned only when the flow cannot run at all, e.g. when the
session folder cannot be created. Errors the user can recover from stay in
the UI and don't end the flow. A failed export offers retry; a denied
permission offers settings. The host only hears about those errors through
`onEvent`.

`onEvent` receives a `StoryEvent` for analytics and issue tracking:
`opened`, `captured`, `mediaPicked`, `toolOpened`, `exportStarted`,
`exportCompleted`, `exportCancelled`, `savedToGallery`, `completed`,
`cancelled`, and `error`. Every handled error arrives as an `error` event
with `event.error` (a `StoryException`) and a stack trace. `properties` holds
only strings, numbers and booleans. The library catches and reports exceptions thrown by your callback, so
analytics can't break the flow.

```dart
void onStoryEvent(StoryEvent event) {
  if (event.type == StoryEventType.error) {
    crashReporter.recordError(event.error!, event.stackTrace);
    return;
  }
  analytics.log('story_${event.type.name}', event.properties);
}
```

`StoryErrorCode` values: `cameraUnavailable`, `cameraPermissionDenied`,
`microphonePermissionDenied`, `photosPermissionDenied`, `captureFailed`,
`captureInterrupted`, `mediaUnsupported`, `mediaUnavailable`,
`mediaTooLarge`, `musicUnavailable`, `exportFailed`, `insufficientStorage`,
`saveToGalleryFailed`, `unknown`. `StoryException.message` is meant for
developers. Show `StoryCreatorStrings` to users instead.

## Testing

- **In your app's widget tests**, pass `services:` with fakes of the
  interfaces in `package:story_creator_kit/services.dart`. Then
  `StoryCreatorPage` runs without platform channels.
  `StoryCreatorConfig.onEvent` is a convenient probe for what happened.
- **Keep your music provider testable** on its own. It is plain Dart, so
  test pagination, search and errors without the UI.
- **Device tests.** Export uses native encoders, so check it with
  `integration_test` on a simulator, emulator or device. The example app's
  `example/integration_test/` does this.
- **In this repository:** run `flutter test` for the unit and widget tests,
  and `cd example && flutter test integration_test` for the native export
  matrix (it needs a booted simulator or emulator).

## Known limitations

- **The iOS Simulator has no camera.** Use the gallery, or a simulated
  `CaptureService` as shown above. Test capture on a real device.
- **Front-camera mirroring differs by platform.** The preview is always
  mirrored. iOS saves front captures mirrored. Android (CameraX) saves them
  un-mirrored, and photo behaviour can vary by OEM. The creator flips media
  so the story matches what the user saw, but verify this on your target
  devices.
- **The lens cannot be switched while recording.** A clip that mixed
  mirrored and un-mirrored segments could not be corrected.
- **Media3 is pinned to 1.10.1 on Android** because of
  [androidx/media#3399](https://github.com/androidx/media/issues/3399) in
  1.11.x.
- **One clip per story.** Multi-clip stories, boomerang, layouts, AR effects
  and link/poll/mention stickers are not included.
- **Music licensing is the host's job.** The library only plays and mixes
  what your provider returns.
- **Fixed output format**: 1080×1920 MP4, H.264 High, AAC-LC 128 kbps
  44.1 kHz stereo. Photos are 1080×1920 JPEG. The frame rate is
  `OutputOptions.frameRate` (30 by default). Faster sources drop frames; on
  Android, slower sources keep their own rate.
- **Some Android encoders can't do 1080×1920.** On those devices the encoder
  may fall back to a lower resolution or bitrate. `StoryResult.width`,
  `height` and `fileSizeBytes` always report the real file.
- **Overlays are static.** Text, stickers and drawing are rendered once for
  the whole video, so animated stickers are not supported.
- **Music does not loop.** Music shorter than the video ends early.
- **Simulators and emulators encode in software.** Export there is much
  slower than on devices.
- **HDR is not preserved.** HDR sources (HLG, HDR10, Dolby Vision) export as
  SDR (BT.709). Colours can look slightly different from the HDR original.
  On Android this tone mapping needs Android 10+. On Android 8–9, HDR
  sources are not supported: colours may be wrong or the export may fail.
- **Preview trimming is approximate.** Trimmed looping in the editor can
  overshoot by up to about 100 ms. The export is cut exactly.
- iOS and Android only.

## License

MIT. See [LICENSE](LICENSE). The example app's generated music and stickers
are CC0, and its fonts are SIL OFL 1.1. See
[`example/assets/ASSETS_LICENSE.md`](example/assets/ASSETS_LICENSE.md).
