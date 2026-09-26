import 'package:flutter/foundation.dart';

/// Keys of the camera screen's controls (tests and integration tests).
abstract final class CameraKeys {
  /// Shutter button.
  static const shutter = ValueKey<String>('story_camera_shutter');

  /// Close button.
  static const close = ValueKey<String>('story_camera_close');

  /// Flash toggle.
  static const flash = ValueKey<String>('story_camera_flash');

  /// Lens switch.
  static const switchLens = ValueKey<String>('story_camera_switch_lens');

  /// Gallery shortcut.
  static const gallery = ValueKey<String>('story_camera_gallery');

  /// Live preview area.
  static const preview = ValueKey<String>('story_camera_preview');

  /// Recording timer pill.
  static const recordingIndicator = ValueKey<String>(
    'story_camera_recording_indicator',
  );

  /// Lock target shown while holding the shutter.
  static const lock = ValueKey<String>('story_camera_lock');

  /// Permission explanation view.
  static const permissionPrompt = ValueKey<String>(
    'story_camera_permission_prompt',
  );

  /// Camera unavailable view.
  static const unavailable = ValueKey<String>('story_camera_unavailable');

  /// Starting / reconnecting view.
  static const starting = ValueKey<String>('story_camera_starting');

  /// Busy overlay while importing.
  static const busy = ValueKey<String>('story_camera_busy');

  /// Full-screen white flash for front-camera photos.
  static const screenFlash = ValueKey<String>('story_camera_screen_flash');

  /// Notice toast.
  static const notice = ValueKey<String>('story_camera_notice');

  /// Focus marker.
  static const focusMarker = ValueKey<String>('story_camera_focus_marker');

  /// "Video | Photo" capture mode toggle.
  static const captureMode = ValueKey<String>('story_camera_capture_mode');

  /// Text story button (left CTA column).
  static const textStory = ValueKey<String>('story_camera_text_story');

  /// Zoom indicator.
  static const zoom = ValueKey<String>('story_camera_zoom');
}
