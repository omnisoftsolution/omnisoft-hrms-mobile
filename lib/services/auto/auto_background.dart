import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:native_geofence/native_geofence.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../models/auto_attendance_config.dart';
import '../device_service.dart';
import '../session_service.dart';
import 'auto_api.dart';
import 'auto_event.dart';
import 'auto_event_queue.dart';
import 'auto_key_store.dart';
import 'auto_sampler.dart';
import 'auto_sender.dart';

// The automatic check-in background wake: the phone crossed the office
// area (native_geofence callback) or a silent `auto_recheck` push arrived.
// It runs in a headless isolate (or, for a push on iOS, on the main
// isolate) with no app singletons: everything is read back from storage.
//
// Every `omni_auto_*` key below lives in SharedPreferencesAsync (no
// per-isolate cache), like the queue and the flush lease (lead decision
// L5): the UI isolate and a wake read and write them both.

/// Last region state the phone saw: [autoStateInside], [autoStateOutside]
/// or `unknown` (written by the foreground after an Undo).
const autoLastStateKey = 'omni_auto_last_state';
const autoStateInside = 'inside';
const autoStateOutside = 'outside';

/// Until when (UTC ISO 8601) one isolate holds the session refresh.
const autoRefreshLeaseKey = 'omni_auto_refresh_lease_until';
const _refreshLeaseFor = Duration(seconds: 60);

/// `true` when the employee turned automatic check-in off on this phone
/// (lead decision L7).
String autoOptedOutKey(int employeeId) => 'omni_auto_opted_out_$employeeId';

/// The id of the office region armed for [employeeId] in [db].
String autoRegionId(String db, int employeeId) =>
    'omni_office_${db}_$employeeId';

/// How long one wake may run (iOS gives a woken app ~30 s).
const autoWakeLimit = Duration(seconds: 25);

/// What a background wake needs, read back from storage.
class AutoBackgroundContext {
  const AutoBackgroundContext({
    required this.baseUrl,
    required this.db,
    required this.deviceId,
    required this.appVersion,
    required this.employeeId,
    this.autoKey,
    this.config,
  });

  final String baseUrl;
  final String db;
  final String deviceId;
  final String appVersion;
  final int employeeId;

  /// Null when none is stored or the keychain cannot be read now.
  final String? autoKey;
  final AutoAttendanceConfig? config;

  String get regionId => autoRegionId(db, employeeId);

  /// The context, or null when no one is signed in, HR's switch is off
  /// (no `employee_auto_attendance` block) or the employee turned it off
  /// on this phone. The seams default to the real stores.
  static Future<AutoBackgroundContext?> load({
    Future<SharedPreferences> Function()? openPrefs,
    SharedPreferencesAsync? asyncPrefs,
    AutoKeyStore? keyStore,
    Future<String> Function()? appVersion,
  }) async {
    final prefs = await (openPrefs ?? SharedPreferences.getInstance)();
    // This isolate's cache may predate a sign-in / sign-out in the UI.
    await prefs.reload();
    final baseUrl = prefs.getString(SessionService.clientUrlPrefsKey) ?? '';
    final db = prefs.getString(SessionService.clientDbPrefsKey) ?? '';
    final employeeId = prefs.getInt(SessionService.employeeIdPrefsKey) ?? 0;
    final deviceId = prefs.getString(DeviceService.prefsKey) ?? '';
    if (baseUrl.isEmpty || employeeId <= 0 || deviceId.isEmpty) return null;
    final config = SessionService.decodeAutoAttendance(
      prefs.getString(SessionService.autoAttendancePrefsKey),
    );
    if (config == null) return null;
    final async = asyncPrefs ?? SharedPreferencesAsync();
    if (await async.getBool(autoOptedOutKey(employeeId)) == true) return null;
    return AutoBackgroundContext(
      baseUrl: baseUrl,
      db: db,
      deviceId: deviceId,
      appVersion: await (appVersion ?? _appVersion)(),
      employeeId: employeeId,
      // Only this employee's key (F4); another one's (a sign-out whose
      // delete failed) is left for the foreground to delete and replace.
      autoKey: await (keyStore ?? AutoKeyStore()).readFor(db, employeeId),
      config: config,
    );
  }
}

/// The version the app sends everywhere else ([AppConstants.appVersion]);
/// statics are empty in a fresh isolate, so it is read again here.
Future<String> _appVersion() async {
  await AppConstants.initAppVersion();
  return AppConstants.appVersion;
}

/// Starts one wake: [handleAutoWake] itself, or a test fake.
typedef AutoWake =
    Future<void> Function({
      required AutoKind kind,
      required AutoSource source,
      AutoBackgroundContext? ctx,
    });

/// Builds the auto-route client of one wake: the auto key when the context
/// has one, else [bearer].
typedef AutoWakeApiBuilder =
    AutoApi Function(
      AutoBackgroundContext ctx,
      String? bearer,
      http.Client client,
    );

/// One wake: record the region state, sample, queue the event, refresh the
/// session when it is about to expire (AA-F06), then send the queue. The
/// whole wake is bounded by [timeout] and never throws.
///
/// Without an auto key it posts with the bearer access token when one can
/// be read; with neither, the event just waits in the queue for the
/// foreground. It never fetches a key (AA-F02: a fetch can sign the user
/// out) and never touches the session on a refusal.
Future<void> handleAutoWake({
  required AutoKind kind,
  required AutoSource source,
  AutoBackgroundContext? ctx,
  Future<AutoBackgroundContext?> Function()? loadContext,
  Future<AutoSample> Function()? sampler,
  AutoEventQueue? queue,
  SharedPreferencesAsync? prefs,
  Future<void> Function()? refresh,
  Future<String?> Function()? bearer,
  AutoWakeApiBuilder? apiBuilder,
  http.Client Function()? clientFactory,
  Future<void> Function(int dropped)? notifyDropped,
  DateTime Function()? now,
  Duration timeout = autoWakeLimit,
}) async {
  final clock = now ?? DateTime.now;
  final p = prefs ?? SharedPreferencesAsync();
  final client = (clientFactory ?? http.Client.new)();
  try {
    await () async {
      final c = ctx ?? await (loadContext ?? AutoBackgroundContext.load)();
      if (c == null) return;
      final at = clock().toUtc();

      // First, so a wake cut short still leaves the state for the
      // foreground (lead decision L4).
      if (kind == AutoKind.leave) {
        await p.setString(autoLastStateKey, autoStateOutside);
      } else if (source == AutoSource.geofence || source == AutoSource.dwell) {
        await p.setString(autoLastStateKey, autoStateInside);
      }

      AutoSample sample;
      try {
        sample = await (sampler ?? sampleNow)();
      } catch (_) {
        sample = AutoSample.empty;
      }

      final q = queue ?? AutoEventQueue(prefs: prefs);
      await q.add(
        AutoEvent(
          eventUid: AutoEvent.newUid(),
          kind: kind,
          eventAt: at,
          latitude: sample.latitude,
          longitude: sample.longitude,
          accuracy: sample.accuracy,
          isMocked: sample.isMocked,
          wifiSsid: sample.ssid,
          wifiBssid: sample.bssid,
          deviceId: c.deviceId,
          appVersion: c.appVersion,
          source: source,
        ),
      );

      try {
        await (refresh ?? () => refreshIfExpiringSoon(prefs: p, now: clock))();
      } catch (_) {
        // Best effort; the foreground refreshes too.
      }

      String? token;
      final key = c.autoKey;
      if (key == null || key.isEmpty) {
        token = await (bearer ?? _readBearer)();
        if (token == null || token.isEmpty) return; // the foreground sends it
      }

      await AutoSender(
        queue: q,
        api: () => (apiBuilder ?? _defaultApi)(c, token, client),
        notifyDropped: notifyDropped ?? (_) => showAutoDroppedNotice(),
        prefs: prefs,
        now: clock,
      ).flush();
    }().timeout(timeout);
  } catch (e) {
    if (kDebugMode) debugPrint('auto wake ended early: ${e.runtimeType}');
  } finally {
    client.close();
  }
}

AutoApi _defaultApi(
  AutoBackgroundContext c,
  String? bearer,
  http.Client client,
) => AutoApi(
  baseUrl: c.baseUrl,
  db: c.db,
  autoKey: c.autoKey,
  bearer: bearer,
  client: client,
);

/// The stored access token, or null (signed out, or keychain unreadable).
Future<String?> _readBearer() async {
  final s = await _loadSessionQuietly();
  final token = s?.accessToken ?? '';
  return token.isEmpty ? null : token;
}

/// A [SessionService] loaded in this isolate, or null on any error (a
/// locked keychain makes `load` throw on the refresh token).
Future<SessionService?> _loadSessionQuietly() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final s = SessionService();
    await s.load();
    return s;
  } catch (_) {
    return null;
  }
}

/// AA-F06: when the access session expires within [within] (or already
/// has), trade the device refresh token for a new one before posting.
/// Best effort, one isolate at a time (lease [autoRefreshLeaseKey], 60 s).
///
/// Returns null when skipped (not due, lease held, nothing readable, an
/// error), else the refresh outcome. A refusal (`invalid`) changes nothing
/// stored — the foreground deals with it — and nothing here can sign the
/// user out: `/auth/refresh` never answers `invalid_session`, and
/// `OmniMobileApi.onInvalidSession` is unset in a background isolate.
///
/// [session] is the foreground's own session (Task 7); without it one is
/// loaded in this isolate ([loadSession] is the test seam).
Future<RefreshOutcome?> refreshIfExpiringSoon({
  Duration within = const Duration(days: 7),
  SessionService? session,
  Future<SessionService?> Function()? loadSession,
  Future<SharedPreferences> Function()? openPrefs,
  SharedPreferencesAsync? prefs,
  DateTime Function()? now,
}) async {
  final clock = now ?? DateTime.now;
  try {
    final legacy = await (openPrefs ?? SharedPreferences.getInstance)();
    await legacy.reload();
    final expiresAt =
        session?.expiresAt ??
        DateTime.tryParse(
          legacy.getString(SessionService.expiresAtPrefsKey) ?? '',
        );
    if (expiresAt == null) return null;
    if (expiresAt.isAfter(clock().add(within))) return null;
    final deviceId = legacy.getString(DeviceService.prefsKey) ?? '';
    if (deviceId.isEmpty) return null;

    final p = prefs ?? SharedPreferencesAsync();
    final held = DateTime.tryParse(
      await p.getString(autoRefreshLeaseKey) ?? '',
    );
    if (held != null && clock().toUtc().isBefore(held.toUtc())) return null;
    final mine = clock().toUtc().add(_refreshLeaseFor).toIso8601String();
    await p.setString(autoRefreshLeaseKey, mine);
    try {
      final s = session ?? await (loadSession ?? _loadSessionQuietly)();
      if (s == null || s.refreshToken.isEmpty) return null;
      return await s.refreshAccessToken(deviceId, forgetOnRefusal: false);
    } finally {
      try {
        if (await p.getString(autoRefreshLeaseKey) == mine) {
          await p.remove(autoRefreshLeaseKey);
        }
      } catch (_) {
        // The lease expires by itself.
      }
    }
  } catch (_) {
    return null;
  }
}

/// The geofence callback's work, testable without the plugin: [event] on
/// the regions [regionIds]. Only the current employee's office region
/// counts (`omni_office_<db>_<employee>`); anything else is ignored.
Future<void> handleGeofenceEvent(
  GeofenceEvent event,
  List<String> regionIds, {
  Future<AutoBackgroundContext?> Function()? loadContext,
  AutoWake? wake,
}) async {
  try {
    await () async {
      if (regionIds.isEmpty) return;
      final c = await (loadContext ?? AutoBackgroundContext.load)();
      if (c == null || !regionIds.contains(c.regionId)) return;
      final (kind, source) = switch (event) {
        GeofenceEvent.enter => (AutoKind.arrive, AutoSource.geofence),
        GeofenceEvent.exit => (AutoKind.leave, AutoSource.geofence),
        GeofenceEvent.dwell => (AutoKind.arrive, AutoSource.dwell),
      };
      await (wake ?? handleAutoWake)(kind: kind, source: source, ctx: c);
    }().timeout(autoWakeLimit);
  } catch (e) {
    if (kDebugMode) debugPrint('auto geofence ended early: ${e.runtimeType}');
  }
}

/// native_geofence's callback (registered by AutoFence): the phone entered,
/// left or stayed in the office region. Runs in a headless isolate.
@pragma('vm:entry-point')
Future<void> autoGeofenceTriggered(GeofenceCallbackParams params) async {
  try {
    // Register the Dart side of the plugins (shared_preferences, secure
    // storage, geolocator, network_info) in this isolate. Idempotent.
    DartPluginRegistrant.ensureInitialized();
  } catch (_) {}
  await handleGeofenceEvent(params.event, [
    for (final g in params.geofences) g.id,
  ]);
}

/// A silent `auto_recheck` push (iPhone, while an arrive waits for the
/// office Wi-Fi): sample again and post an arrive with `source: recheck`,
/// but only while the phone last saw itself inside the office region.
Future<void> handleAutoRecheck(
  Map<String, dynamic> data, {
  SharedPreferencesAsync? prefs,
  AutoWake? wake,
}) async {
  try {
    final p = prefs ?? SharedPreferencesAsync();
    if (await p.getString(autoLastStateKey) != autoStateInside) return;
    await (wake ?? handleAutoWake)(
      kind: AutoKind.arrive,
      source: AutoSource.recheck,
    );
  } catch (e) {
    if (kDebugMode) debugPrint('auto recheck ended early: ${e.runtimeType}');
  }
}
