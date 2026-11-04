import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/push_groups.dart';
import 'auto_api.dart';
import 'auto_event_queue.dart';

/// How a [AutoSender.flush] ended.
enum FlushOutcome {
  /// The queue is empty (everything was answered, or there was nothing).
  done,

  /// An event was not answered usefully (409 / 422 / 5xx / timeout /
  /// non-JSON). It stays queued, as does everything after it.
  retryLater,

  /// 401: the auto key is no longer valid. The event stays queued.
  keyInvalid,

  /// Another isolate holds the flush lease; nothing was posted.
  busy,
}

/// The server's last accepted answer to an auto event, kept so the foreground
/// service can show e.g. "Waiting for office Wi-Fi".
class AutoLastAnswer {
  const AutoLastAnswer({required this.state, this.reason, required this.at});

  final String state;
  final String? reason;

  /// When the phone received the answer (UTC).
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'state': state,
    'reason': reason,
    'at': at.toUtc().toIso8601String(),
  };

  static AutoLastAnswer? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final state = j['state'];
      final at = DateTime.tryParse('${j['at']}');
      if (state is! String || at == null) return null;
      return AutoLastAnswer(
        state: state,
        reason: j['reason'] as String?,
        at: at.toUtc(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Sends the offline queue of automatic events, one at a time and in order
/// (AA-F01): the next event is posted only after a 2xx or a final 4xx; on
/// 409 / 5xx / timeout the same event is resent before any later one.
///
/// Called from the UI isolate, the background geofence isolate and the
/// foreground service, so a 30 s lease in [SharedPreferencesAsync] keeps two
/// of them from posting the same queue at once (lead decision L5).
class AutoSender {
  AutoSender({
    required AutoEventQueue queue,
    required AutoApi Function() api,
    required Future<void> Function(int dropped) notifyDropped,
    SharedPreferencesAsync? prefs,
    DateTime Function()? now,
  }) : _queue = queue,
       _api = api,
       _notifyDropped = notifyDropped,
       _prefsOverride = prefs,
       _now = now ?? DateTime.now;

  static const leaseKey = 'omni_auto_flush_lease_until';
  static const lastAnswerKey = 'omni_auto_last_answer';
  static const leaseFor = Duration(seconds: 30);

  final AutoEventQueue _queue;
  final AutoApi Function() _api;
  final Future<void> Function(int dropped) _notifyDropped;
  final SharedPreferencesAsync? _prefsOverride;
  final DateTime Function() _now;

  SharedPreferencesAsync? _prefs;
  SharedPreferencesAsync get _p =>
      _prefs ??= _prefsOverride ?? SharedPreferencesAsync();

  /// The newest accepted answer, or null.
  static Future<AutoLastAnswer?> lastAnswer(
    SharedPreferencesAsync prefs,
  ) async => AutoLastAnswer.tryParse(await prefs.getString(lastAnswerKey));

  /// [owner] is the signed-in employee ([AutoKeyStore.ownerOf]); an event
  /// queued for anyone else (a wake that finished during a sign-out) is
  /// removed unsent.
  Future<FlushOutcome> flush({String? owner}) async {
    final held = await _p.getString(leaseKey);
    final until = held == null ? null : DateTime.tryParse(held);
    if (until != null && _now().toUtc().isBefore(until.toUtc())) {
      return FlushOutcome.busy;
    }

    String mine = await _takeLease();
    try {
      final stale = await _queue.takeStale(_now());
      if (stale.isNotEmpty) {
        try {
          await _notifyDropped(stale.length);
        } catch (_) {
          // A missing notification must not hold back the rest of the queue.
        }
      }

      final events = await _queue.ordered();
      if (events.isEmpty) return FlushOutcome.done;

      // Built once per flush and not kept: the key may change between runs.
      final api = _api();
      for (final e in events) {
        if (owner != null && e.owner != null && e.owner != owner) {
          await _queue.remove(e.eventUid);
          continue;
        }
        // Posting can take up to the HTTP timeout; keep the lease ours.
        mine = await _takeLease();
        final result = await api.postEvent(e);
        switch (result) {
          case AutoAccepted(:final state, :final reason):
            // Another isolate may have removed it already; remove is a no-op
            // for a missing uid.
            await _queue.remove(e.eventUid);
            await _p.setString(
              lastAnswerKey,
              jsonEncode(
                AutoLastAnswer(
                  state: state,
                  reason: reason,
                  at: _now(),
                ).toJson(),
              ),
            );
          case AutoFinal():
            await _queue.remove(e.eventUid);
          case AutoRetry():
            return FlushOutcome.retryLater;
          case AutoKeyInvalid():
            return FlushOutcome.keyInvalid;
        }
      }
      return FlushOutcome.done;
    } finally {
      await _releaseLease(mine);
    }
  }

  /// Writes a fresh lease and returns the value written.
  Future<String> _takeLease() async {
    final value = _now().toUtc().add(leaseFor).toIso8601String();
    await _p.setString(leaseKey, value);
    return value;
  }

  /// Releases the lease only while it is still the one this call wrote, so a
  /// flush that overran its lease never deletes a later holder's.
  Future<void> _releaseLease(String mine) async {
    try {
      if (await _p.getString(leaseKey) == mine) await _p.remove(leaseKey);
    } catch (_) {
      // The lease expires by itself after 30 s.
    }
  }
}

const _droppedNoticeId = 4101;

/// Local notification for events that waited too long to be sent:
/// "Couldn't check you in/out — Open Omni HR". Safe in a background isolate
/// (it initialises the plugin itself, without asking for permission).
Future<void> showAutoDroppedNotice() async {
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_stat_notify'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
  );
  final group = pushGroups.firstWhere((g) => g.key == 'attendance');
  await plugin.show(
    id: _droppedNoticeId,
    title: "Couldn't check you in/out",
    body: 'Open Omni HR',
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        group.key,
        group.name,
        channelDescription: group.channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
    ),
  );
}
