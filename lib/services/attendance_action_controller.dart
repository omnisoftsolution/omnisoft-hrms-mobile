import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/error_messages.dart';
import '../core/wifi_gate.dart';
import '../core/datetime_utils.dart';
import '../models/attendance_ask.dart';
import '../models/attendance_status.dart';
import '../models/auto_close_previous.dart';
import '../models/face_capture_result.dart';
import '../models/location_result.dart';
import '../models/wifi_info_result.dart';
import 'device_service.dart';
import 'face_recognition_service.dart';
import 'location_service.dart';
import 'omni_mobile_api.dart';
import 'session_service.dart';
import 'wifi_info_service.dart';

/// What the status tile's button should look like right now.
enum AttendanceButtonState { enroll, ready, blocked, acting }

/// The check-in page's checklist rows, in the order [perform] runs them.
enum PunchStep { location, wifi, face, record }

/// running → done (or skipped when the tenant does not require it). A
/// step that fails just never reports done; the outcome carries why.
enum PunchStepState { running, done, skipped }

typedef PunchStepCallback =
    void Function(PunchStep step, PunchStepState state, String detail);

/// The result of [AttendanceActionController.perform]. `null` from
/// perform means nothing happened (a second tap, a cancelled capture).
class AttendanceActionOutcome {
  const AttendanceActionOutcome._({
    this.error,
    this.checkedIn = false,
    this.autoClosed,
    this.enrolled = false,
    this.ask,
    this.undoUntil,
    this.attendanceId,
  });

  const AttendanceActionOutcome.success({
    required bool checkedIn,
    AutoClosePrevious? autoClosed,
    AttendanceAsk? ask,
    DateTime? undoUntil,
    int? attendanceId,
  }) : this._(
         checkedIn: checkedIn,
         autoClosed: autoClosed,
         ask: ask,
         undoUntil: undoUntil,
         attendanceId: attendanceId,
       );

  const AttendanceActionOutcome.failure(String error) : this._(error: error);

  /// The one-time face setup was shown instead of a punch.
  const AttendanceActionOutcome.enrolment() : this._(enrolled: true);

  final String? error;

  /// After a success: true when the punch was a check-in.
  final bool checkedIn;

  /// Echoed by the connector when it auto-closed a forgotten attendance.
  final AutoClosePrevious? autoClosed;
  final bool enrolled;

  /// Connector 2.54.0: the question to ask after a check-in, else null.
  final AttendanceAsk? ask;

  /// Connector 2.54.0: UNDO is offered until this time (UTC), else null.
  final DateTime? undoUntil;

  /// The row just punched (`attendance_id` of the response).
  final int? attendanceId;

  bool get ok => error == null && !enrolled;
}

/// The phone check-in machinery that used to live in the classic home
/// (spec 2026-10-07 §4.4): the attendance status, the live GPS and Wi-Fi
/// samples, the enrolment flag, the button state and the punch itself.
/// No widgets: the screen passes the two UI steps (face capture,
/// enrolment) as callbacks and renders the outcome.
class AttendanceActionController extends ChangeNotifier {
  AttendanceActionController({
    required this.session,
    FaceRecognitionService? faceService,
    OmniMobileApi Function(SessionService session)? apiBuilder,
    Future<LocationResult> Function()? getLocation,
    Future<WifiInfoResult> Function()? getWifi,
    Future<String> Function()? getDeviceId,
    bool? Function()? isEnrolled,
    Future<FaceVerifyResult> Function(String imagePath)? verifyFace,
    Future<void> Function()? refreshEnrolled,
    bool? devLocation,
    bool? simulateFace,
  }) : _apiBuilder = apiBuilder ?? _defaultApi,
       _getLocation = getLocation ?? LocationService().getCurrent,
       _getWifi = getWifi ?? WifiInfoService().getCurrent,
       _getDeviceId = getDeviceId ?? DeviceService().getDeviceId,
       _isEnrolled = isEnrolled ?? (() => faceService!.isEnrolled),
       _verifyFace = verifyFace ?? ((path) => faceService!.verifyFace(path)),
       _refreshEnrolled =
           refreshEnrolled ??
           (() => faceService!.refreshEnrolledStatus(session)),
       devLocation = devLocation ?? DevConstants.useDevLocation,
       simulateFace = simulateFace ?? DevConstants.simulateFaceRecognition;

  static OmniMobileApi _defaultApi(SessionService s) =>
      OmniMobileApi(baseUrl: s.clientUrl, db: s.clientDb, token: s.token);

  final SessionService session;
  final OmniMobileApi Function(SessionService session) _apiBuilder;
  final Future<LocationResult> Function() _getLocation;
  final Future<WifiInfoResult> Function() _getWifi;
  final Future<String> Function() _getDeviceId;
  final bool? Function() _isEnrolled;
  final Future<FaceVerifyResult> Function(String imagePath) _verifyFace;
  final Future<void> Function() _refreshEnrolled;
  final bool devLocation;
  final bool simulateFace;

  /// Fallback office radius when the tenant configured a geofence but
  /// left the radius unset. Matches the connector's server-side default.
  static const double defaultRadiusMeters = 200;

  AttendanceStatus? status;
  DateTime? statusFetchedAt;
  String? statusError;

  /// Metres from the office per the last GPS sample; null = no fix yet
  /// or no geofence.
  double? distanceMeters;
  bool gpsFailed = false;

  /// Most recent Wi-Fi sample; null until sampled ("unknown, don't block").
  WifiInfoResult? lastWifi;
  bool acting = false;

  /// `== false` on purpose: null (not fetched yet) counts as enrolled, so
  /// the button never flashes "Set up your face" on a cold start.
  bool get needsEnrollment =>
      session.featureFaceVerification &&
      !simulateFace &&
      _isEnrolled() == false;

  /// True when the tile has a live place to show (pin badge on).
  bool get hasPlace =>
      session.featureGeolocation &&
      !devLocation &&
      (status?.hasGeofence ?? false);

  bool get isOutside {
    final s = status;
    final d = distanceMeters;
    return hasPlace &&
        s != null &&
        d != null &&
        !s.flexibleLocation &&
        !isInsideRadius(s, d);
  }

  /// The tile's place text: "Office (40 m)", "Outside the office (1.2 km)",
  /// "Remote (3.4 km)", "Locating…", "GPS unavailable", or '' when there
  /// is no office to measure against.
  String get placeLabel {
    if (!session.featureGeolocation) return '';
    if (devLocation) return 'DEV · bypass';
    final s = status;
    if (s == null || !s.hasGeofence) return '';
    final d = distanceMeters;
    if (d == null) return gpsFailed ? 'GPS unavailable' : 'Locating…';
    final dist = formatDistance(d);
    if (isInsideRadius(s, d)) return 'Office ($dist)';
    if (s.flexibleLocation) return 'Remote ($dist)';
    return 'Outside the office ($dist)';
  }

  /// Enrolment first, then the geofence; "no fix yet" stays ready and the
  /// tap decides. The Wi-Fi gate never deads the button: [perform] reports
  /// it at tap time with the friendly reason (the tile has no Wi-Fi line).
  AttendanceButtonState get buttonState {
    if (acting) return AttendanceButtonState.acting;
    if (needsEnrollment) return AttendanceButtonState.enroll;
    if (isOutside) return AttendanceButtonState.blocked;
    return AttendanceButtonState.ready;
  }

  static bool isInsideRadius(AttendanceStatus s, double distance) =>
      distance <= (s.officeRadiusMeters ?? defaultRadiusMeters);

  static double haversineMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  /// 40 → "40 m"; 1234 → "1.2 km".
  static String formatDistance(double m) {
    if (m < 1000) return '${m.round()} m';
    return '${(m / 1000).toStringAsFixed(1)} km';
  }

  /// `/attendance/status`, then a GPS sample against the (possibly new)
  /// geofence. A failure keeps the last status and records the message.
  Future<void> refreshStatus() async {
    if (!session.featureAttendance) return;
    try {
      status = await _apiBuilder(session).getAttendanceStatus();
      statusFetchedAt = DateTime.now();
      statusError = null;
    } catch (e) {
      statusError = friendlyError(e);
    }
    _notify();
    await sampleLocation();
  }

  /// The 60-second poll of the old GPS card: a Wi-Fi sample when the
  /// office requires one, then the distance to the office. Never throws.
  Future<void> sampleLocation() async {
    if (status?.wifiRequired == true) {
      try {
        lastWifi = await _getWifi();
      } catch (_) {
        // keep the last sample
      }
    }
    final s = status;
    if (session.featureGeolocation && s != null && s.hasGeofence) {
      try {
        final loc = await _getLocation();
        if (!loc.isReady) {
          distanceMeters = null;
          gpsFailed = true;
        } else {
          distanceMeters = haversineMeters(
            loc.latitude!,
            loc.longitude!,
            s.officeLatitude!,
            s.officeLongitude!,
          );
          gpsFailed = false;
        }
      } catch (_) {
        // keep the last reading
      }
    }
    _notify();
  }

  /// The status attendance/undo answered with (spec 2026-10-07 §4.4): the
  /// tile redraws without a second /attendance/status call.
  void applyStatus(AttendanceStatus value) {
    status = value;
    statusFetchedAt = DateTime.now();
    statusError = null;
    _notify();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// An in-flight sample / refresh / punch can finish after the screen
  /// disposed us; notifying then would throw.
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  void _setActing(bool value) {
    acting = value;
    _notify();
  }

  /// The punch: face setup short-circuit, fresh GPS fix + geofence
  /// fast-fail, Wi-Fi gate, face capture + on-device verification, then
  /// `checkIn` / `checkOut` and a status refresh. [captureFace] shows the
  /// camera and returns its result; [enrol] shows the one-time setup.
  /// [onStep] follows the checklist on the check-in page.
  Future<AttendanceActionOutcome?> perform({
    required Future<FaceCaptureResult> Function() captureFace,
    required Future<void> Function() enrol,
    PunchStepCallback? onStep,
  }) async {
    void step(PunchStep s, PunchStepState state, [String detail = '']) =>
        onStep?.call(s, state, detail);
    if (acting) return null;
    if (!session.featureAttendance) return null;

    if (needsEnrollment) {
      await enrol();
      await _refreshEnrolled();
      _notify();
      return const AttendanceActionOutcome.enrolment();
    }

    _setActing(true);
    try {
      double? latitude;
      double? longitude;
      var isMocked = false;
      double? accuracy;
      if (session.featureGeolocation) {
        step(PunchStep.location, PunchStepState.running, 'Locating…');
        var measured = false;
        final loc = await _getLocation();
        if (!loc.isReady) {
          return AttendanceActionOutcome.failure(loc.friendlyMessage);
        }
        latitude = loc.latitude;
        longitude = loc.longitude;
        isMocked = loc.isMocked;
        accuracy = loc.accuracy;
        // Fresh-fix geofence fast-fail; the server still enforces it.
        final s = status;
        if (!devLocation &&
            s != null &&
            !s.flexibleLocation &&
            s.hasGeofence &&
            s.officeLatitude != null &&
            s.officeLongitude != null) {
          final distance = haversineMeters(
            latitude!,
            longitude!,
            s.officeLatitude!,
            s.officeLongitude!,
          );
          distanceMeters = distance;
          gpsFailed = false;
          measured = true;
          if (!isInsideRadius(s, distance)) {
            return AttendanceActionOutcome.failure(
              friendlyError('outside_geofence'),
            );
          }
        }
        step(
          PunchStep.location,
          PunchStepState.done,
          measured ? placeLabel : 'Location recorded',
        );
      } else {
        step(PunchStep.location, PunchStepState.skipped, 'Not required');
      }

      step(PunchStep.wifi, PunchStepState.running, 'Checking…');
      final wifiInfo = await _getWifi();
      lastWifi = wifiInfo;
      final wifiFail = wifiPreCheckErrorCode(
        status: status,
        wifi: wifiInfo,
        devLocation: devLocation,
      );
      if (wifiFail != null) {
        return AttendanceActionOutcome.failure(friendlyError(wifiFail));
      }
      if (status?.wifiRequired == true) {
        step(
          PunchStep.wifi,
          PunchStepState.done,
          wifiInfo.ssid ?? 'Office network',
        );
      } else {
        step(PunchStep.wifi, PunchStepState.skipped, 'Not required');
      }

      var faceVerified = false;
      if (session.featureFaceVerification) {
        step(PunchStep.face, PunchStepState.running, 'Look at the camera');
        final capture = await captureFace();
        if (!capture.success) {
          final message = capture.errorMessage;
          return message == null
              ? null
              : AttendanceActionOutcome.failure(message);
        }
        final verify = await _verifyFace(capture.imagePath!);
        if (!verify.ok) {
          return AttendanceActionOutcome.failure(
            verify.errorMessage ?? 'Face not recognized. Please try again.',
          );
        }
        faceVerified = capture.faceVerified;
        step(PunchStep.face, PunchStepState.done, 'Matched');
      } else {
        step(PunchStep.face, PunchStepState.skipped, 'Not required');
      }

      step(PunchStep.record, PunchStepState.running, 'Sending…');
      final api = _apiBuilder(session);
      final deviceId = await _getDeviceId();
      final wasCheckedIn = status?.checkedIn == true;
      AutoClosePrevious? autoClosed;
      var resp = const <String, dynamic>{};
      try {
        if (wasCheckedIn) {
          resp = await api.checkOut(
            latitude: latitude,
            longitude: longitude,
            faceVerified: faceVerified,
            deviceId: deviceId,
            devLocation: devLocation,
            isMocked: isMocked,
            accuracy: accuracy,
            wifiSsid: wifiInfo.ssid,
            wifiBssid: wifiInfo.bssid,
          );
        } else {
          resp = await api.checkIn(
            latitude: latitude,
            longitude: longitude,
            faceVerified: faceVerified,
            deviceId: deviceId,
            devLocation: devLocation,
            isMocked: isMocked,
            accuracy: accuracy,
            wifiSsid: wifiInfo.ssid,
            wifiBssid: wifiInfo.bssid,
          );
          final acp = resp['auto_closed_previous'];
          if (acp is Map<String, dynamic>) {
            autoClosed = AutoClosePrevious.fromJson(acp);
          }
        }
      } on ApiException catch (e) {
        if (e.errorCode == 'outside_geofence' && e.distanceFromOffice != null) {
          distanceMeters = e.distanceFromOffice;
        }
        return AttendanceActionOutcome.failure(friendlyError(e));
      } catch (e) {
        return AttendanceActionOutcome.failure(friendlyError(e));
      }
      await refreshStatus();
      step(PunchStep.record, PunchStepState.done);
      final until = resp['undo_until'];
      final id = resp['attendance_id'];
      return AttendanceActionOutcome.success(
        checkedIn: !wasCheckedIn,
        autoClosed: autoClosed,
        // Connector 2.54.0 keys; absent on 2.53.x: nothing asked or undone.
        ask: wasCheckedIn ? null : AttendanceAsk.tryParse(resp['ask']),
        undoUntil: until is String ? DateTimeUtils.parseOdooUtc(until) : null,
        attendanceId: id is num ? id.toInt() : null,
      );
    } finally {
      _setActing(false);
    }
  }
}
