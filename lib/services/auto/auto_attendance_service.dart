import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../models/auto_attendance_config.dart';
import '../attendance_action_controller.dart';
import '../device_service.dart';
import '../omni_mobile_api.dart';
import '../session_service.dart';
import 'auto_api.dart';
import 'auto_background.dart';
import 'auto_event.dart';
import 'auto_event_queue.dart';
import 'auto_fence.dart';
import 'auto_key_store.dart';
import 'auto_sampler.dart';
import 'auto_sender.dart';

/// What automatic check-in looks like on this phone.
enum AutoPhoneState {
  /// HR's switch is off (or an older connector, or signed out).
  off,

  /// The phone is not set up for it (`device_required`: the session is not
  /// bound to this device).
  needsSetup,

  /// Location is not allowed "Always".
  needsAlways,

  /// The office region is armed.
  on,

  /// Armed, and the last arrival waits for the office Wi-Fi (< 30 min).
  waitingWifi,

  /// The employee turned it off on this phone (lead decision L7).
  optedOut,
}

/// The status last accepted by the server: `permission|enabled|platform`.
const autoStatusSentKey = 'omni_auto_status_sent';

/// The app version the regions were last armed under (Android, Ruling R9).
const autoArmedAppVersionKey = 'omni_auto_armed_app_version';

/// Every `omni_auto_*` pref (all in [SharedPreferencesAsync]).
const _autoPrefix = 'omni_auto_';

/// Builds the auto-route client: [autoKey] when given, else the session's
/// bearer token (status posts, Ruling R1).
typedef AutoApiFor = AutoApi Function(SessionService s, String? autoKey);

enum _KeyResult { ok, notEnabled, deviceRequired, failed }

/// Foreground orchestration of automatic check-in: keeps the office region,
/// the auto key, the status the server knows and the offline queue in step
/// with HR's switch, the location permission and this phone's opt-out.
///
/// [sync] runs on app start, resume and after every sign-in; calls are
/// serialised (a call while one runs asks for one more run). Nothing here
/// throws to callers.
class AutoAttendanceService extends ChangeNotifier {
  AutoAttendanceService({
    required SessionService session,
    Future<String> Function()? permission,
    AutoFence? fence,
    AutoKeyStore? keyStore,
    OmniMobileApi Function(SessionService s)? apiBuilder,
    AutoApiFor? autoApiBuilder,
    AutoSender? sender,
    Future<AutoSample> Function()? sampler,
    String? platform,
    AutoEventQueue? queue,
    SharedPreferencesAsync? prefs,
    Future<void> Function()? refresh,
    Future<String> Function()? deviceId,
    String Function()? appVersion,
    DateTime Function()? now,
  }) : _session = session,
       _permission = permission ?? locationPermissionWord,
       _fence = fence ?? AutoFence(),
       _keyStore = keyStore ?? AutoKeyStore(),
       _apiBuilder = apiBuilder ?? _defaultMobileApi,
       _sampler = sampler ?? sampleNow,
       _platform = platform ?? (Platform.isIOS ? 'ios' : 'android'),
       _prefs = prefs ?? SharedPreferencesAsync(),
       _deviceId = deviceId ?? DeviceService().getDeviceId,
       _appVersion = appVersion ?? (() => AppConstants.appVersion),
       _now = now ?? DateTime.now {
    _queue = queue ?? AutoEventQueue(prefs: _prefs);
    _autoApi = autoApiBuilder ?? _defaultAutoApi;
    _refresh =
        refresh ??
        () =>
            refreshIfExpiringSoon(session: _session, prefs: _prefs, now: _now);
    _sender =
        sender ??
        AutoSender(
          queue: _queue,
          api: () => _autoApi(_session, _key),
          notifyDropped: (_) => showAutoDroppedNotice(),
          prefs: _prefs,
          now: _now,
        );
    _seenSignIn = _signInOf(session);
    session.addListener(_onSessionChanged);
  }

  final SessionService _session;
  final Future<String> Function() _permission;
  final AutoFence _fence;
  final AutoKeyStore _keyStore;
  final OmniMobileApi Function(SessionService s) _apiBuilder;
  final Future<AutoSample> Function() _sampler;
  final String _platform;
  final SharedPreferencesAsync _prefs;
  final Future<String> Function() _deviceId;
  final String Function() _appVersion;
  final DateTime Function() _now;
  late final AutoEventQueue _queue;
  late final AutoApiFor _autoApi;
  late final Future<void> Function() _refresh;
  late final AutoSender _sender;

  /// One client for the default auto-route builder, closed in [dispose].
  final http.Client _client = http.Client();

  AutoPhoneState _state = AutoPhoneState.off;
  AutoPhoneState get state => _state;

  /// HR's settings for this employee, or null when the switch is off.
  AutoAttendanceConfig? get config => _session.autoAttendance;

  /// The auto key read or fetched by the current run.
  String? _key;

  Future<void>? _running;
  bool _rerun = false;
  bool _pendingAppStart = false;

  /// Bumped by [onSessionClearing]: a run that started before stops writing.
  int _epoch = 0;

  /// `db|employee` while signed in, else ''. A change to a non-empty value
  /// is a sign-in.
  String _seenSignIn = '';

  static String _signInOf(SessionService s) =>
      s.isLoggedIn && !s.isClearing && s.employeeId > 0
      ? '${s.clientDb}|${s.employeeId}'
      : '';

  void _onSessionChanged() {
    final now = _signInOf(_session);
    if (now == _seenSignIn) return;
    _seenSignIn = now;
    if (now.isNotEmpty) unawaited(sync());
  }

  static Future<String> locationPermissionWord() async {
    try {
      return switch (await Geolocator.checkPermission()) {
        LocationPermission.always => 'always',
        LocationPermission.whileInUse => 'while_using',
        _ => 'denied',
      };
    } catch (_) {
      return 'denied';
    }
  }

  static OmniMobileApi _defaultMobileApi(SessionService s) =>
      OmniMobileApi(baseUrl: s.clientUrl, db: s.clientDb, token: s.token);

  AutoApi _defaultAutoApi(SessionService s, String? autoKey) => AutoApi(
    baseUrl: s.clientUrl,
    db: s.clientDb,
    autoKey: autoKey,
    bearer: s.token,
    client: _client,
  );

  static void _log(String message) {
    if (kDebugMode) debugPrint('auto: $message');
  }

  void _setState(AutoPhoneState s) {
    if (_state == s) return;
    _state = s;
    notifyListeners();
  }

  /// Brings the phone in step with HR's switch. A call while one runs asks
  /// for one more run (with [appStart] if any caller asked for it) and
  /// completes when that run has finished.
  Future<void> sync({bool appStart = false}) {
    _pendingAppStart |= appStart;
    final running = _running;
    if (running != null) {
      _rerun = true;
      return running;
    }
    final done = Completer<void>();
    _running = done.future;
    unawaited(
      _loop().whenComplete(() {
        _running = null;
        done.complete();
      }),
    );
    return done.future;
  }

  Future<void> _loop() async {
    do {
      _rerun = false;
      final appStart = _pendingAppStart;
      _pendingAppStart = false;
      try {
        await _syncOnce(appStart: appStart);
      } catch (e) {
        _log('sync ended early (${e.runtimeType})');
      }
    } while (_rerun);
  }

  bool _stale(int epoch) =>
      epoch != _epoch || !_session.isLoggedIn || _session.isClearing;

  Future<void> _syncOnce({required bool appStart}) async {
    final epoch = _epoch;
    final s = _session;
    if (!s.isLoggedIn || s.isClearing || s.employeeId <= 0) {
      _setState(AutoPhoneState.off);
      return;
    }
    final db = s.clientDb;
    final employeeId = s.employeeId;
    final config = s.autoAttendance;
    final optedOut =
        config != null &&
        await _prefs.getBool(autoOptedOutKey(employeeId)) == true;
    final permission = await _permission();
    if (_stale(epoch)) return;

    if (config == null || optedOut) {
      await _disarm(db, epoch, permission);
      if (_stale(epoch)) return;
      _setState(optedOut ? AutoPhoneState.optedOut : AutoPhoneState.off);
      return;
    }

    // AA-F02: refresh first, then fetch the key — never both at once.
    try {
      await _refresh();
    } catch (e) {
      _log('refresh failed (${e.runtimeType})');
    }
    if (_stale(epoch)) return;
    final key = await _ensureKey(epoch);
    if (_stale(epoch)) return;
    if (key == _KeyResult.notEnabled) {
      await _disarm(db, epoch, permission);
      if (!_stale(epoch)) _setState(AutoPhoneState.off);
      return;
    }

    final needsSetup = key == _KeyResult.deviceRequired;
    final always = permission == 'always';
    final armWanted = always && !needsSetup;
    if (armWanted && appStart && _platform == 'android') {
      await _reCreateAfterUpdate();
    }
    if (_stale(epoch)) return;
    try {
      await _fence.sync(
        db: db,
        employeeId: employeeId,
        config: needsSetup ? null : config,
        alwaysGranted: always,
      );
    } catch (e) {
      _log('fence sync failed (${e.runtimeType})');
    }
    if (_stale(epoch)) return;

    final armedState = needsSetup
        ? AutoPhoneState.needsSetup
        : always
        ? AutoPhoneState.on
        : AutoPhoneState.needsAlways;
    await _postStatus(
      permission,
      armedState == AutoPhoneState.on,
      force: appStart,
    );
    if (_stale(epoch)) return;

    if (armedState == AutoPhoneState.on) {
      await _foregroundArrive(config, epoch);
      if (_stale(epoch)) return;
    }

    await _flush(epoch);
    if (_stale(epoch)) return;

    _setState(
      armedState == AutoPhoneState.on && await _waitingWifi()
          ? AutoPhoneState.waitingWifi
          : armedState,
    );
  }

  /// Off or opted out: no region, no key, and the server told once.
  Future<void> _disarm(String db, int epoch, String permission) async {
    try {
      await _fence.removeAll(db);
    } catch (e) {
      _log('fence removal failed (${e.runtimeType})');
    }
    _key = null;
    await _keyStore.delete();
    if (_stale(epoch)) return;
    await _postStatus(permission, false, force: false);
  }

  /// The stored key, else one fetched with the bearer session.
  Future<_KeyResult> _ensureKey(int epoch) async {
    final stored = await _keyStore.read();
    if (stored != null && stored.isNotEmpty) {
      _key = stored;
      return _KeyResult.ok;
    }
    _key = null;
    try {
      final got = await _apiBuilder(_session).fetchAutoKey();
      if (_stale(epoch)) return _KeyResult.failed;
      await _keyStore.write(got.key, got.deviceId);
      _key = got.key;
      return _KeyResult.ok;
    } on ApiException catch (e) {
      switch (e.errorCode) {
        case 'not_enabled':
          return _KeyResult.notEnabled;
        case 'device_required':
          debugPrint(
            'auto: this sign-in is not bound to the phone (device_required)',
          );
          return _KeyResult.deviceRequired;
      }
      _log('key fetch failed (${e.errorCode})');
      return _KeyResult.failed;
    } catch (e) {
      _log('key fetch failed (${e.runtimeType})');
      return _KeyResult.failed;
    }
  }

  /// Android forgets its geofences on an app update while the plugin still
  /// lists them (Ruling R9): register them again once per new version.
  Future<void> _reCreateAfterUpdate() async {
    final version = _appVersion();
    if (await _prefs.getString(autoArmedAppVersionKey) == version) return;
    try {
      await _fence.reCreateAll();
      await _prefs.setString(autoArmedAppVersionKey, version);
    } catch (e) {
      _log('re-creating regions failed (${e.runtimeType})');
    }
  }

  /// Posts `{permission, enabled, platform}` (bearer, Ruling R1) when it
  /// differs from the last accepted one, or always when [force].
  Future<void> _postStatus(
    String permission,
    bool enabled, {
    required bool force,
  }) async {
    final sig = '$permission|$enabled|$_platform';
    if (!force && await _prefs.getString(autoStatusSentKey) == sig) return;
    final result = await _autoApi(
      _session,
      null,
    ).postStatus(permission: permission, enabled: enabled, platform: _platform);
    switch (result) {
      case AutoAccepted():
      case AutoFinal():
        // A final refusal will not change by asking again for the same.
        await _prefs.setString(autoStatusSentKey, sig);
      case AutoRetry(:final why):
        _log('status not sent ($why)');
      case AutoKeyInvalid():
        _log('status not sent (401)');
    }
  }

  /// Lead decision L4: opening the app checks in only when the phone has no
  /// inside state, or the last arrival waits for the Wi-Fi (< 30 min).
  Future<void> _foregroundArrive(AutoAttendanceConfig config, int epoch) async {
    final inside = await _prefs.getString(autoLastStateKey) == autoStateInside;
    if (inside && !await _waitingWifi()) return;
    final at = _now().toUtc();
    final sample = await _sampler();
    final lat = sample.latitude;
    final lng = sample.longitude;
    if (lat == null || lng == null) return;
    final distance = AttendanceActionController.haversineMeters(
      lat,
      lng,
      config.office.latitude,
      config.office.longitude,
    );
    final slack = math.max(0.0, math.min(sample.accuracy ?? 0, 100.0));
    if (distance > config.office.areaM + slack) return;
    if (_stale(epoch)) return;
    await _prefs.setString(autoLastStateKey, autoStateInside);
    await _queue.add(
      AutoEvent(
        eventUid: AutoEvent.newUid(),
        kind: AutoKind.arrive,
        eventAt: at,
        latitude: lat,
        longitude: lng,
        accuracy: sample.accuracy,
        isMocked: sample.isMocked,
        wifiSsid: sample.ssid,
        wifiBssid: sample.bssid,
        deviceId: await _deviceId(),
        appVersion: _appVersion(),
        source: AutoSource.foreground,
      ),
    );
  }

  /// Sends the queue; a refused key is deleted and fetched once more.
  Future<void> _flush(int epoch) async {
    final outcome = await _sender.flush();
    if (outcome != FlushOutcome.keyInvalid || _stale(epoch)) return;
    _key = null;
    await _keyStore.delete();
    if (await _ensureKey(epoch) == _KeyResult.ok && !_stale(epoch)) {
      await _sender.flush();
    }
  }

  Future<bool> _waitingWifi() async {
    final last = await AutoSender.lastAnswer(_prefs);
    if (last == null || last.state != 'waiting_wifi') return false;
    return _now().toUtc().difference(last.at).abs() <
        const Duration(minutes: 30);
  }

  /// Turns automatic check-in off on this phone only (lead decision L7).
  Future<void> turnOffOnThisPhone() async {
    final id = _session.employeeId;
    if (id <= 0) return;
    await _prefs.setBool(autoOptedOutKey(id), true);
    await sync();
  }

  /// Undoes [turnOffOnThisPhone].
  Future<void> turnOnAgain() async {
    final id = _session.employeeId;
    if (id <= 0) return;
    await _prefs.remove(autoOptedOutKey(id));
    await sync();
  }

  /// An automatic punch was undone: the next app open may check in again.
  void onAutoUndone() {
    unawaited(
      _prefs.setString(autoLastStateKey, 'unknown').catchError((Object e) {
        _log('last state not saved (${e.runtimeType})');
      }),
    );
  }

  /// Runs before every sign-out, while the session is intact: removes this
  /// db's region, the key, the queue and every `omni_auto_*` pref.
  Future<void> onSessionClearing() async {
    _epoch++;
    _key = null;
    final db = _session.clientDb;
    try {
      await _fence.removeAll(db);
    } catch (e) {
      _log('fence removal failed (${e.runtimeType})');
    }
    try {
      await _keyStore.delete();
    } catch (e) {
      _log('key not deleted (${e.runtimeType})');
    }
    try {
      await _queue.clear();
      final keys = await _prefs.getKeys();
      final ours = keys.where((k) => k.startsWith(_autoPrefix)).toSet();
      if (ours.isNotEmpty) await _prefs.clear(allowList: ours);
    } catch (e) {
      _log('prefs not cleared (${e.runtimeType})');
    }
    _setState(AutoPhoneState.off);
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _client.close();
    super.dispose();
  }
}
