/// State of a runtime permission.
enum PermissionState {
  /// Granted.
  granted,

  /// Not granted yet, or denied once; asking again shows the prompt.
  denied,

  /// Denied permanently or restricted; only the settings app can change it.
  permanentlyDenied,
}

/// Camera and microphone permissions. Photo library access is part of
/// `GallerySource`.
abstract class PermissionService {
  /// Current camera permission without prompting.
  Future<PermissionState> checkCamera();

  /// Prompts for the camera if needed.
  Future<PermissionState> requestCamera();

  /// Current microphone permission without prompting.
  Future<PermissionState> checkMicrophone();

  /// Prompts for the microphone if needed.
  Future<PermissionState> requestMicrophone();

  /// Opens the app's page in the system settings.
  Future<bool> openSettings();
}
