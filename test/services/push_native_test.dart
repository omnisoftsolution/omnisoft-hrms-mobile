import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/push_groups.dart';
import 'package:omni_hr/services/push_native.dart';

/// Records what PushNative asks the Android tray to do.
class FakeTray extends AndroidTray {
  FakeTray();

  final List<String> calls = [];

  @override
  Future<void> init() async {
    calls.add('init');
  }

  @override
  Future<void> createChannel(PushGroup group) async {
    calls.add('channel ${group.key}');
  }

  @override
  Future<void> cancel(String tag) async {
    calls.add('cancel $tag');
  }

  @override
  Future<void> cancelAll() async {
    calls.add('cancelAll');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('omnihr/push');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('iOS: remove, clear and badge go to the omnihr/push channel', () async {
    final tray = FakeTray();
    final n = PushNative(platform: TargetPlatform.iOS, tray: tray);
    await n.removeDelivered(['leave:12', 'approve:77']);
    await n.clearDelivered();
    await n.setBadge(4);
    await n.cancelTag('leave:12'); // Android only
    await n.createChannels(); // Android only
    expect(calls.map((c) => c.method), [
      'removeDelivered',
      'clearDelivered',
      'setBadge',
    ]);
    expect(calls[0].arguments, {
      'ids': ['leave:12', 'approve:77'],
    });
    expect(calls[2].arguments, {'count': 4});
    expect(tray.calls, isEmpty);
  });

  test('iOS: a negative badge is sent as 0; an empty removal is not sent', () async {
    final n = PushNative(platform: TargetPlatform.iOS, tray: FakeTray());
    await n.setBadge(-3);
    await n.removeDelivered(const []);
    expect(calls.map((c) => c.method), ['setBadge']);
    expect(calls.single.arguments, {'count': 0});
  });

  test('Android: no channel call; the tray cancels by tag, clears all and '
      'gets one channel per group', () async {
    final tray = FakeTray();
    final n = PushNative(platform: TargetPlatform.android, tray: tray);
    await n.createChannels();
    await n.removeDelivered(['leave:12']); // iOS only
    await n.cancelTag('leave:12');
    await n.clearDelivered();
    await n.setBadge(3); // iOS only: Android launchers show a dot
    expect(calls, isEmpty);
    expect(tray.calls, [
      'init',
      'channel requests',
      'channel approvals',
      'channel attendance',
      'channel reminders',
      'channel news',
      'channel security',
      'cancel leave:12',
      'cancelAll',
    ]);
  });

  test('a missing native side never throws', () async {
    messenger.setMockMethodCallHandler(channel, null);
    final n = PushNative(platform: TargetPlatform.iOS);
    await n.removeDelivered(['x']);
    await n.clearDelivered();
    await n.setBadge(1);
  });
}
