import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/push_groups.dart';

/// The Android notification tray, through flutter_local_notifications.
/// A seam: tests subclass it.
class AndroidTray {
  const AndroidTray();

  FlutterLocalNotificationsPlugin get _plugin =>
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_notify'),
      ),
    );
  }

  Future<void> createChannel(PushGroup group) async {
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          AndroidNotificationChannel(
            group.key,
            group.name,
            description: group.channelDescription,
            importance: Importance.high,
          ),
        );
  }

  /// FCM posts a notification with `notification.tag` = omni_key and id 0.
  Future<void> cancel(String tag) => _plugin.cancel(id: 0, tag: tag);

  Future<void> cancelAll() => _plugin.cancelAll();
}

/// The phone side of push notifications that Firebase does not cover
/// (spec 2026-10-11 §6.1 / §6.4 / §6.5): iOS through the `omnihr/push`
/// channel (ios/Runner/PushPlugin.swift), Android through [AndroidTray].
/// Every call is best effort: a failure is logged, never thrown.
class PushNative {
  PushNative({
    MethodChannel? channel,
    AndroidTray tray = const AndroidTray(),
    TargetPlatform? platform,
  }) : _channel = channel ?? const MethodChannel('omnihr/push'),
       _tray = tray,
       _platform = platform;

  /// The app-wide instance. Tests may replace it.
  static PushNative instance = PushNative();

  final MethodChannel _channel;
  final AndroidTray _tray;
  final TargetPlatform? _platform;

  TargetPlatform get _os => _platform ?? defaultTargetPlatform;
  bool get _ios => _os == TargetPlatform.iOS;
  bool get _android => _os == TargetPlatform.android;

  /// Android: start the tray plugin and create one channel per group, so
  /// users can also manage groups in Android settings. iOS: nothing.
  Future<void> createChannels() async {
    if (!_android) return;
    await _quiet(_tray.init);
    for (final group in pushGroups) {
      await _quiet(() => _tray.createChannel(group));
    }
  }

  /// iOS: remove delivered notifications by identifier (= omni_key).
  Future<void> removeDelivered(List<String> ids) async {
    if (!_ios || ids.isEmpty) return;
    await _quiet(() async {
      await _channel.invokeMethod<void>('removeDelivered', {'ids': ids});
    });
  }

  /// Android: cancel the notification FCM posted with this tag (omni_key).
  Future<void> cancelTag(String tag) async {
    if (!_android || tag.isEmpty) return;
    await _quiet(() => _tray.cancel(tag));
  }

  /// Remove every delivered Omni HR notification (the bell was opened).
  Future<void> clearDelivered() async {
    if (_ios) {
      await _quiet(() async {
        await _channel.invokeMethod<void>('clearDelivered');
      });
    } else if (_android) {
      await _quiet(_tray.cancelAll);
    }
  }

  /// iOS app icon badge. Android has no numeric badge API (launchers show
  /// a dot from active notifications), so nothing happens there.
  Future<void> setBadge(int n) async {
    if (!_ios) return;
    await _quiet(() async {
      await _channel.invokeMethod<void>('setBadge', {'count': n < 0 ? 0 : n});
    });
  }

  static Future<void> _quiet(Future<void> Function() call) async {
    try {
      await call();
    } catch (e) {
      debugPrint('omnihr/push: $e');
    }
  }
}
