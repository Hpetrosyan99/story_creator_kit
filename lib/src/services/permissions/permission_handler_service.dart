import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../../api/errors/story_exception.dart';
import 'permission_service.dart';

/// [PermissionService] backed by `permission_handler`.
///
/// Android cannot report "permanently denied" from a status check
/// (`checkPermissionStatus` only returns granted or denied); it is only
/// visible in the result of `request()`. This service remembers a
/// `permanentlyDenied` request result for the life of the process and keeps
/// reporting it from [checkCamera] / [checkMicrophone] until the permission
/// is granted (e.g. in the settings app). iOS reports `permanentlyDenied`
/// from status checks once the user declined, and `restricted` (Screen Time,
/// MDM) is mapped to [PermissionState.permanentlyDenied] as well.
class PermissionHandlerService implements PermissionService {
  /// Creates the service.
  PermissionHandlerService();

  final Set<ph.Permission> _blocked = {};

  @override
  Future<PermissionState> checkCamera() => _check(ph.Permission.camera);

  @override
  Future<PermissionState> requestCamera() => _request(ph.Permission.camera);

  @override
  Future<PermissionState> checkMicrophone() => _check(ph.Permission.microphone);

  @override
  Future<PermissionState> requestMicrophone() =>
      _request(ph.Permission.microphone);

  @override
  Future<bool> openSettings() async {
    try {
      return await ph.openAppSettings();
    } on PlatformException catch (e, s) {
      throw StoryException(
        StoryErrorCode.unknown,
        'Could not open the app settings.',
        e,
        s,
      );
    }
  }

  Future<PermissionState> _check(ph.Permission permission) async {
    final ph.PermissionStatus status;
    try {
      status = await permission.status;
    } on PlatformException catch (e, s) {
      throw _error(permission, e, s);
    }
    return _map(permission, status);
  }

  Future<PermissionState> _request(ph.Permission permission) async {
    final ph.PermissionStatus status;
    try {
      status = await permission.request();
    } on PlatformException catch (e, s) {
      throw _error(permission, e, s);
    }
    return _map(permission, status);
  }

  PermissionState _map(ph.Permission permission, ph.PermissionStatus status) {
    switch (status) {
      case ph.PermissionStatus.granted:
      case ph.PermissionStatus.limited:
      case ph.PermissionStatus.provisional:
        _blocked.remove(permission);
        return PermissionState.granted;
      case ph.PermissionStatus.permanentlyDenied:
      case ph.PermissionStatus.restricted:
        _blocked.add(permission);
        return PermissionState.permanentlyDenied;
      case ph.PermissionStatus.denied:
        return _blocked.contains(permission)
            ? PermissionState.permanentlyDenied
            : PermissionState.denied;
    }
  }

  static StoryException _error(
    ph.Permission permission,
    PlatformException e,
    StackTrace s,
  ) => StoryException(
    permission == ph.Permission.camera
        ? StoryErrorCode.cameraPermissionDenied
        : StoryErrorCode.microphonePermissionDenied,
    'Could not read the permission state.',
    e,
    s,
  );
}
