/// Service interfaces behind the story creator, for replacing platform
/// services (simulated camera, test fakes). Pass a [StoryServices] to
/// `StoryCreator.open`.
library;

export 'src/core/session_files.dart' show SessionFiles;
export 'src/model/drawing_stroke.dart';
export 'src/model/media_placement.dart';
export 'src/model/music_selection.dart';
export 'src/model/overlay_transform.dart';
export 'src/model/story_document.dart';
export 'src/model/story_media.dart';
export 'src/model/story_overlay.dart';
export 'src/model/trim_range.dart';
export 'src/render/painters/story_paint_resources.dart';
export 'src/services/audio/music_session.dart';
export 'src/services/capture/capture_service.dart';
export 'src/services/export/gallery_saver.dart';
export 'src/services/export/story_exporter.dart'
    show
        ExportCancelledException,
        ExportContext,
        ExportJob,
        ExportedStory,
        StoryExporter;
export 'src/services/gallery/gallery_source.dart';
export 'src/services/media/media_inspector.dart';
export 'src/services/permissions/permission_service.dart';
export 'src/services/story_services.dart';
export 'src/services/video/video_session.dart';
