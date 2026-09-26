import 'package:flutter/foundation.dart';

/// Camera, gallery and permission strings.
///
/// Owned by the camera/gallery area; add fields here as that area needs them.
@immutable
class CameraStrings {
  /// Creates the camera strings. Defaults are English.
  const CameraStrings({
    this.takePhoto = 'Take photo',
    this.shutterHint = 'Tap for photo, hold for video',
    this.startRecording = 'Start recording',
    this.stopRecording = 'Stop recording',
    this.recording = 'Recording',
    this.switchCamera = 'Switch camera',
    this.flashOff = 'Flash off',
    this.flashOn = 'Flash on',
    this.flashAuto = 'Flash auto',
    this.openGallery = 'Open gallery',
    this.recent = 'Recent',
    this.albums = 'Albums',
    this.galleryEmpty = 'No photos or videos yet.',
    this.cameraPermissionTitle = 'Allow camera access',
    this.cameraPermissionMessage =
        'Camera access lets you take photos and videos for your story.',
    this.microphonePermissionMessage =
        'Microphone access is off, so videos are recorded without sound.',
    this.photosPermissionTitle = 'Allow photo access',
    this.photosPermissionMessage =
        'Photo access lets you add photos and videos from your library.',
    this.limitedAccessMessage = 'You gave access to some photos only.',
    this.manageSelection = 'Manage',
    this.allowAccess = 'Allow access',
    this.cameraUnavailable = 'The camera is not available on this device.',
    this.cameraInterrupted = 'The camera was interrupted.',
    this.recordingTooShort = 'Hold longer to record a video.',
    this.mediaUnsupported = 'This file type is not supported.',
    this.mediaUnavailable = 'This item could not be loaded.',
    this.downloadingFromCloud = 'Downloading from iCloud…',
    this.camera = 'Camera',
    this.selectMedia = 'Select',
    this.videoItem = 'Video',
    this.photoItem = 'Photo',
    this.cameraPreview = 'Camera preview. Tap to focus, pinch to zoom.',
    this.cameraBlockedMessage =
        'Camera access is off. Turn it on in Settings to take photos and '
        'videos.',
    this.cameraStarting = 'Starting camera…',
    this.lockRecording = 'Lock recording',
    this.recordingLockedHint = 'Tap the shutter to stop recording.',
    this.recordingDiscarded =
        'The recording was interrupted and was too short to keep.',
    this.videoTooShort = 'This video is too short.',
    this.mediaTooLarge = 'This file is too large.',
    this.importing = 'Loading…',
    this.photosPermissionBlockedMessage =
        'Photo access is off. Turn it on in Settings, or choose items with '
        'the system picker.',
    this.useSystemPicker = 'Choose from library',
    this.cancelDownload = 'Cancel download',
    this.galleryLoadFailed = 'The photo library could not be loaded.',
    this.selectAlbum = 'Select album',
    this.zoomLevel = 'Zoom',
    this.videoMode = 'Video',
    this.photoMode = 'Photo',
    this.captureMode = 'Capture mode',
    this.videoModeHint = 'Tap to start or stop recording',
    this.textStory = 'Create a text story',
  });

  /// Shutter semantics label in photo mode.
  final String takePhoto;

  /// Hint shown near the shutter.
  final String shutterHint;

  /// Shutter semantics label to start recording.
  final String startRecording;

  /// Shutter semantics label to stop recording.
  final String stopRecording;

  /// Recording indicator label.
  final String recording;

  /// Lens switch label.
  final String switchCamera;

  /// Flash mode label: off.
  final String flashOff;

  /// Flash mode label: on.
  final String flashOn;

  /// Flash mode label: auto.
  final String flashAuto;

  /// Gallery shortcut label.
  final String openGallery;

  /// Name of the "all recent media" album.
  final String recent;

  /// Album selector label.
  final String albums;

  /// Empty gallery message.
  final String galleryEmpty;

  /// Camera permission prompt title.
  final String cameraPermissionTitle;

  /// Camera permission prompt message.
  final String cameraPermissionMessage;

  /// Notice when the microphone permission is denied.
  final String microphonePermissionMessage;

  /// Photos permission prompt title.
  final String photosPermissionTitle;

  /// Photos permission prompt message.
  final String photosPermissionMessage;

  /// Banner shown with limited photo access.
  final String limitedAccessMessage;

  /// Opens the limited-access selection UI.
  final String manageSelection;

  /// Requests a permission.
  final String allowAccess;

  /// Error when no usable camera exists.
  final String cameraUnavailable;

  /// Error when the camera session was interrupted.
  final String cameraInterrupted;

  /// Notice when a recording is shorter than the minimum.
  final String recordingTooShort;

  /// Error for a file type the device cannot decode.
  final String mediaUnsupported;

  /// Error for media that cannot be read (deleted, offline cloud item).
  final String mediaUnavailable;

  /// Progress text while an iCloud item downloads.
  final String downloadingFromCloud;

  /// Camera tile label in the gallery grid.
  final String camera;

  /// Selection action label.
  final String selectMedia;

  /// Semantics label for a video tile.
  final String videoItem;

  /// Semantics label for a photo tile.
  final String photoItem;

  /// Semantics label of the live preview.
  final String cameraPreview;

  /// Camera permission message when access was denied permanently (only
  /// the settings app can change it).
  final String cameraBlockedMessage;

  /// Shown while the camera starts or reconnects.
  final String cameraStarting;

  /// Label of the lock target shown while holding the shutter.
  final String lockRecording;

  /// Hint shown while a locked (hands-free) recording runs.
  final String recordingLockedHint;

  /// Notice when an interrupted recording was too short to keep.
  final String recordingDiscarded;

  /// Error for a picked video shorter than the minimum duration.
  final String videoTooShort;

  /// Error for a picked file larger than the import limit.
  final String mediaTooLarge;

  /// Semantics label of the busy indicator while media is imported.
  final String importing;

  /// Photos permission message when access was denied permanently.
  final String photosPermissionBlockedMessage;

  /// Opens the system photo picker instead of the in-app grid.
  final String useSystemPicker;

  /// Cancels an iCloud download of a gallery item.
  final String cancelDownload;

  /// Error when albums or assets cannot be listed.
  final String galleryLoadFailed;

  /// Semantics label of the album selector.
  final String selectAlbum;

  /// Semantics label prefix of the zoom indicator (followed by the factor).
  final String zoomLevel;

  /// Video option of the capture mode toggle.
  final String videoMode;

  /// Photo option of the capture mode toggle.
  final String photoMode;

  /// Semantics label of the capture mode toggle ("Video | Photo").
  final String captureMode;

  /// Semantics hint of the shutter in video mode.
  final String videoModeHint;

  /// Label of the camera's text button, which starts a story on a plain
  /// gradient background.
  final String textStory;
}
