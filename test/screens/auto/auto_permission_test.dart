import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/screens/auto/auto_setup_card.dart';
import 'package:permission_handler/permission_handler.dart';

/// [requestAutoPermission] against permission_handler's real method
/// channel, answered with one status for every location permission (the
/// channel sends a status as its index in [PermissionStatus]).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter.baseflow.com/permissions/methods');

  void answer(PermissionStatus status) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'checkPermissionStatus':
              return status.index;
            case 'requestPermissions':
              return {
                for (final p in call.arguments as List) p as int: status.index,
              };
          }
          return null;
        });
  }

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('Always granted answers always', () async {
    answer(PermissionStatus.granted);
    expect(await requestAutoPermission('always'), 'always');
  });

  test('an ordinary denial may be asked again', () async {
    answer(PermissionStatus.denied);
    expect(await requestAutoPermission('while_using'), 'denied');
  });

  test('denied for good is blocked', () async {
    answer(PermissionStatus.permanentlyDenied);
    expect(await requestAutoPermission('while_using'), 'blocked');
  });

  test('restricted (Screen Time, a company profile) is blocked, not '
      '"try again" (R136-F07)', () async {
    answer(PermissionStatus.restricted);
    expect(await requestAutoPermission('while_using'), 'blocked');
  });
}
