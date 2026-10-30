import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'auto_event.dart';

/// Offline queue of automatic attendance events.
///
/// Both the UI isolate and a background geofence isolate read and write it,
/// so it lives in [SharedPreferencesAsync] (no per-isolate cache) under
/// [storageKey]. Writes within one isolate are serialised; the cross-isolate
/// "one flusher at a time" rule is the flush lease (a later task).
class AutoEventQueue {
  AutoEventQueue({SharedPreferencesAsync? prefs}) : _prefsOverride = prefs;

  static const storageKey = 'omni_auto_queue';
  static const maxEvents = 20;
  static const staleAfter = Duration(minutes: 30);

  final SharedPreferencesAsync? _prefsOverride;
  SharedPreferencesAsync? _prefs;
  SharedPreferencesAsync get _p =>
      _prefs ??= _prefsOverride ?? SharedPreferencesAsync();

  // Serialises read-modify-write cycles inside this isolate.
  static Future<void> _tail = Future<void>.value();

  Future<T> _locked<T>(Future<T> Function() body) {
    final result = _tail.then((_) => body());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<List<AutoEvent>> _read() async {
    final raw = await _p.getString(storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <AutoEvent>[];
      for (final item in decoded) {
        try {
          out.add(AutoEvent.fromJson(item as Map));
        } catch (_) {
          // Skip one unreadable entry; keep the rest.
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(List<AutoEvent> events) async {
    if (events.isEmpty) {
      await _p.remove(storageKey);
      return;
    }
    await _p.setString(
      storageKey,
      jsonEncode([for (final e in events) e.toJson()]),
    );
  }

  static int _byTime(AutoEvent a, AutoEvent b) =>
      a.eventAt.compareTo(b.eventAt);

  /// Adds [e]; a repeated `eventUid` is ignored. Beyond [maxEvents] the oldest
  /// events are dropped.
  Future<void> add(AutoEvent e) => _locked(() async {
    final events = await _read();
    if (events.any((x) => x.eventUid == e.eventUid)) return;
    events
      ..add(e)
      ..sort(_byTime);
    if (events.length > maxEvents) {
      events.removeRange(0, events.length - maxEvents);
    }
    await _write(events);
  });

  /// All queued events, oldest `eventAt` first.
  Future<List<AutoEvent>> ordered() => _locked(() async {
    final events = await _read()
      ..sort(_byTime);
    return events;
  });

  Future<void> remove(String eventUid) => _locked(() async {
    final events = await _read();
    final kept = events.where((e) => e.eventUid != eventUid).toList();
    if (kept.length != events.length) await _write(kept);
  });

  /// Removes and returns events with `eventAt < now - staleAfter`.
  Future<List<AutoEvent>> takeStale(DateTime now) => _locked(() async {
    final cutoff = now.toUtc().subtract(staleAfter);
    final events = await _read()
      ..sort(_byTime);
    final stale = events.where((e) => e.eventAt.isBefore(cutoff)).toList();
    if (stale.isNotEmpty) {
      await _write(events.where((e) => !e.eventAt.isBefore(cutoff)).toList());
    }
    return stale;
  });

  Future<void> clear() => _locked(() => _p.remove(storageKey));
}
