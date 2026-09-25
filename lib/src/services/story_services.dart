import '../api/config/capture_options.dart';
import '../api/config/story_creator_config.dart';
import 'audio/just_audio_music_session.dart';
import 'audio/music_session.dart';
import 'capture/camera_capture_service.dart';
import 'capture/capture_service.dart';
import 'export/gal_gallery_saver.dart';
import 'export/gallery_saver.dart';
import 'export/native_story_exporter.dart';
import 'export/story_exporter.dart';
import 'gallery/gallery_source.dart';
import 'gallery/photo_manager_gallery_source.dart';
import 'gallery/system_picker_gallery_source.dart';
import 'media/media_inspector.dart';
import 'media/native_media_inspector.dart';
import 'permissions/permission_handler_service.dart';
import 'permissions/permission_service.dart';
import 'video/video_player_session.dart';
import 'video/video_session.dart';

/// Creates a [CaptureService]; called each time the camera screen opens.
typedef CaptureServiceFactory = CaptureService Function();

/// Creates a [MusicSession].
typedef MusicSessionFactory = MusicSession Function();

/// Creates a [VideoSession].
typedef VideoSessionFactory = VideoSession Function();

/// The platform services the story creator uses.
///
/// [StoryServices.platform] wires the real plugins. Replace individual
/// services with [copyWith], e.g. a simulated camera on the iOS Simulator or
/// fakes in tests.
class StoryServices {
  /// Creates a service set.
  const StoryServices({
    required this.createCapture,
    required this.gallery,
    required this.permissions,
    required this.inspector,
    required this.createMusicSession,
    required this.createVideoSession,
    required this.exporter,
    required this.gallerySaver,
  });

  /// Real implementations for [config].
  factory StoryServices.platform(StoryCreatorConfig config) {
    final inspector = NativeMediaInspector();
    return StoryServices(
      createCapture: CameraCaptureService.new,
      gallery: switch (config.capture.galleryMode) {
        GalleryMode.inApp => PhotoManagerGallerySource(),
        GalleryMode.systemPicker ||
        GalleryMode.disabled => SystemPickerGallerySource(),
      },
      permissions: PermissionHandlerService(),
      inspector: inspector,
      createMusicSession: JustAudioMusicSession.new,
      createVideoSession: VideoPlayerSession.new,
      exporter: NativeStoryExporter(inspector: inspector),
      gallerySaver: GalGallerySaver(),
    );
  }

  /// Camera factory.
  final CaptureServiceFactory createCapture;

  /// Photo library.
  final GallerySource gallery;

  /// Camera and microphone permissions.
  final PermissionService permissions;

  /// Native media inspection.
  final MediaInspector inspector;

  /// Music player factory.
  final MusicSessionFactory createMusicSession;

  /// Video player factory.
  final VideoSessionFactory createVideoSession;

  /// Export engine.
  final StoryExporter exporter;

  /// Gallery writer.
  final GallerySaver gallerySaver;

  /// Returns a copy with the given services replaced.
  StoryServices copyWith({
    CaptureServiceFactory? createCapture,
    GallerySource? gallery,
    PermissionService? permissions,
    MediaInspector? inspector,
    MusicSessionFactory? createMusicSession,
    VideoSessionFactory? createVideoSession,
    StoryExporter? exporter,
    GallerySaver? gallerySaver,
  }) => StoryServices(
    createCapture: createCapture ?? this.createCapture,
    gallery: gallery ?? this.gallery,
    permissions: permissions ?? this.permissions,
    inspector: inspector ?? this.inspector,
    createMusicSession: createMusicSession ?? this.createMusicSession,
    createVideoSession: createVideoSession ?? this.createVideoSession,
    exporter: exporter ?? this.exporter,
    gallerySaver: gallerySaver ?? this.gallerySaver,
  );
}
