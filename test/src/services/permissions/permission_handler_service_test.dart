import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_creator_kit/services.dart';
import 'package:story_creator_kit/src/services/permissions/permission_handler_service.dart';
import 'package:story_creator_kit/story_creator_kit.dart';

// permission_handler's method channel protocol: permissions and statuses
// are sent as ints (camera = 1, microphone = 7; denied = 0, granted = 1,
// restricted = 2, limited = 3, permanentlyDenied = 4).
const _channel = MethodChannel('flutter.baseflow.com/permissions/methods');
const _camera = 1;
const _microphone = 7;
const _denied = 0;
const _granted = 1;
const _restricted = 2;
const _permanentlyDenied = 4;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<int, int> status;
  late Map<int, int> requestResult;
  late List<String> calls;
  PlatformException? error;

  setUp(() {
    status = {_camera: _denied, _microphone: _denied};
    requestResult = {};
    calls = [];
    error = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call.method);
          if (error != null) {
            throw error!;
          }
          switch (call.method) {
            case 'checkPermissionStatus':
              return status[call.arguments as int];
            case 'requestPermissions':
              final list = (call.arguments as List).cast<int>();
              return {for (final p in list) p: requestResult[p] ?? status[p]!};
            case 'openAppSettings':
              return true;
          }
          return null;
        });
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );

  test('maps granted and denied', () async {
    final service = PermissionHandlerService();
    expect(await service.checkCamera(), PermissionState.denied);
    status[_camera] = _granted;
    expect(await service.checkCamera(), PermissionState.granted);
    expect(await service.checkMicrophone(), PermissionState.denied);
  });

  test('restricted is permanently denied', () async {
    status[_camera] = _restricted;
    expect(
      await PermissionHandlerService().checkCamera(),
      PermissionState.permanentlyDenied,
    );
  });

  test('a permanently denied request result sticks until granted', () async {
    final service = PermissionHandlerService();
    requestResult[_microphone] = _permanentlyDenied;

    expect(
      await service.requestMicrophone(),
      PermissionState.permanentlyDenied,
    );
    // Android status checks only say "denied".
    expect(await service.checkMicrophone(), PermissionState.permanentlyDenied);
    // The camera is unaffected.
    expect(await service.checkCamera(), PermissionState.denied);

    status[_microphone] = _granted;
    expect(await service.checkMicrophone(), PermissionState.granted);
    status[_microphone] = _denied;
    expect(await service.checkMicrophone(), PermissionState.denied);
  });

  test('request returns the new state', () async {
    requestResult[_camera] = _granted;
    expect(
      await PermissionHandlerService().requestCamera(),
      PermissionState.granted,
    );
    expect(calls, contains('requestPermissions'));
  });

  test('openSettings opens the app settings', () async {
    expect(await PermissionHandlerService().openSettings(), isTrue);
    expect(calls, ['openAppSettings']);
  });

  test('platform errors become typed errors', () async {
    error = PlatformException(code: 'boom');
    await expectLater(
      PermissionHandlerService().checkMicrophone(),
      throwsA(
        isA<StoryException>().having(
          (e) => e.code,
          'code',
          StoryErrorCode.microphonePermissionDenied,
        ),
      ),
    );
    await expectLater(
      PermissionHandlerService().requestCamera(),
      throwsA(
        isA<StoryException>().having(
          (e) => e.code,
          'code',
          StoryErrorCode.cameraPermissionDenied,
        ),
      ),
    );
  });
}
