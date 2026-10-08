import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/error_messages.dart';
import 'package:omni_hr/models/attendance_status.dart';
import 'package:omni_hr/models/face_capture_result.dart';
import 'package:omni_hr/models/location_result.dart';
import 'package:omni_hr/models/wifi_info_result.dart';
import 'package:omni_hr/services/attendance_action_controller.dart';
import 'package:omni_hr/services/face_recognition_service.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _officeLat = 1.3;
const _officeLng = 103.8;

AttendanceStatus _status({
  bool checkedIn = false,
  bool office = true,
  bool flexible = false,
  List<String>? requiredSsids,
}) => AttendanceStatus.fromJson({
  'checked_in': checkedIn,
  'hours_today': 0,
  'employee_id': 1,
  'auth_type': 'app',
  if (office) ...{
    'office_latitude': _officeLat,
    'office_longitude': _officeLng,
    'office_radius_meters': 200,
  },
  'flexible_location': flexible,
  if (requiredSsids != null)
    'network_gate': {'wifi_required': true, 'expected_ssids': requiredSsids},
});

LocationResult _at(double lat, double lng) => LocationResult(
  status: LocationStatus.ready,
  latitude: lat,
  longitude: lng,
  accuracy: 5,
);

/// Records the attendance calls; answers with the scripted status.
class _FakeApi extends OmniMobileApi {
  _FakeApi(this.status) : super(baseUrl: '', db: '', token: '');

  AttendanceStatus status;
  int statusCalls = 0;
  final checkIns = <Map<String, dynamic>>[];
  final checkOuts = <Map<String, dynamic>>[];
  Map<String, dynamic> checkInResponse = const {};

  @override
  Future<AttendanceStatus> getAttendanceStatus() async {
    statusCalls++;
    return status;
  }

  @override
  Future<Map<String, dynamic>> checkIn({
    double? latitude,
    double? longitude,
    bool faceVerified = true,
    String? deviceId,
    bool devLocation = false,
    bool isMocked = false,
    double? accuracy,
    String? wifiSsid,
    String? wifiBssid,
  }) async {
    checkIns.add({'lat': latitude, 'lng': longitude, 'face': faceVerified});
    status = _status(checkedIn: true);
    return checkInResponse;
  }

  @override
  Future<Map<String, dynamic>> checkOut({
    double? latitude,
    double? longitude,
    bool faceVerified = true,
    String? deviceId,
    bool devLocation = false,
    bool isMocked = false,
    double? accuracy,
    String? wifiSsid,
    String? wifiBssid,
  }) async {
    checkOuts.add({'lat': latitude, 'lng': longitude});
    status = _status(checkedIn: false);
    return const {};
  }
}

class _Harness {
  _Harness({
    AttendanceStatus? status,
    LocationResult? location,
    bool? enrolled = true,
    bool faceOk = true,
  }) : api = _FakeApi(status ?? _status()) {
    controller = AttendanceActionController(
      session: SessionService(),
      apiBuilder: (_) => api,
      getLocation: () async => location ?? _at(_officeLat, _officeLng),
      getWifi: () async => const WifiInfoResult.ready(ssid: 'office'),
      getDeviceId: () async => 'device-1',
      isEnrolled: () => enrolled,
      verifyFace: (_) async => FaceVerifyResult(ok: faceOk),
      refreshEnrolled: () async => refreshes++,
      devLocation: false,
      simulateFace: false,
    );
  }

  final _FakeApi api;
  late final AttendanceActionController controller;
  int refreshes = 0;
  int captures = 0;
  int enrolments = 0;

  Future<AttendanceActionOutcome?> perform({bool cancel = false}) =>
      controller.perform(
        captureFace: () async {
          captures++;
          return cancel
              ? FaceCaptureResult.cancelled()
              : FaceCaptureResult.success('/tmp/face.jpg');
        },
        enrol: () async => enrolments++,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('button state', () {
    test('enroll when the face is not set up', () {
      final h = _Harness(enrolled: false)..controller.status = _status();
      expect(h.controller.buttonState, AttendanceButtonState.enroll);
      expect(h.controller.needsEnrollment, isTrue);
    });

    test('blocked outside the office, ready inside', () async {
      final h = _Harness(location: _at(1.31, _officeLng));
      await h.controller.refreshStatus();
      expect(h.controller.isOutside, isTrue);
      expect(h.controller.buttonState, AttendanceButtonState.blocked);
      expect(h.controller.placeLabel, 'Outside the office (1.1 km)');

      final inside = _Harness();
      await inside.controller.refreshStatus();
      expect(inside.controller.isOutside, isFalse);
      expect(inside.controller.buttonState, AttendanceButtonState.ready);
      expect(inside.controller.placeLabel, 'Office (0 m)');
    });

    test('remote and no-office employees stay ready', () async {
      final remote = _Harness(
        status: _status(flexible: true),
        location: _at(1.31, _officeLng),
      );
      await remote.controller.refreshStatus();
      expect(remote.controller.buttonState, AttendanceButtonState.ready);
      expect(remote.controller.placeLabel, 'Remote (1.1 km)');
      expect(remote.controller.hasPlace, isTrue);

      final none = _Harness(status: _status(office: false));
      await none.controller.refreshStatus();
      expect(none.controller.buttonState, AttendanceButtonState.ready);
      expect(none.controller.placeLabel, '');
      expect(none.controller.hasPlace, isFalse);
    });

    test(
      'no fix yet: Locating…, then GPS unavailable after a failure',
      () async {
        final h = _Harness()..controller.status = _status();
        expect(h.controller.placeLabel, 'Locating…');
        expect(h.controller.buttonState, AttendanceButtonState.ready);
        final failing = _Harness(
          location: LocationResult(status: LocationStatus.permissionDenied),
        );
        await failing.controller.refreshStatus();
        expect(failing.controller.placeLabel, 'GPS unavailable');
        expect(failing.controller.buttonState, AttendanceButtonState.ready);
      },
    );
  });

  group('perform', () {
    test('outside the office: fast-fail, nothing sent', () async {
      final h = _Harness(location: _at(1.31, _officeLng));
      await h.controller.refreshStatus();
      final outcome = await h.perform();
      expect(outcome?.error, friendlyError('outside_geofence'));
      expect(h.captures, 0);
      expect(h.api.checkIns, isEmpty);
      expect(h.controller.acting, isFalse);
    });

    test('check-in: capture, verify, post, refresh', () async {
      final h = _Harness();
      h.api.checkInResponse = {
        'auto_closed_previous': {
          'attendance_id': 7,
          'original_check_in': '2026-10-05 00:00:00',
          'inferred_check_out': '2026-10-05 09:00:00',
          'hours_assumed': 9,
          'hours_open_when_closed': 30,
        },
      };
      await h.controller.refreshStatus();
      final outcome = await h.perform();
      expect(outcome?.ok, isTrue);
      expect(outcome?.checkedIn, isTrue);
      expect(outcome?.autoClosed?.attendanceId, 7);
      expect(h.captures, 1);
      expect(h.api.checkIns.single['face'], isTrue);
      expect(h.api.checkIns.single['lat'], _officeLat);
      expect(h.controller.status?.checkedIn, isTrue);
      expect(h.api.statusCalls, 2);
    });

    test('checked in: the same tap checks out', () async {
      final h = _Harness(status: _status(checkedIn: true));
      await h.controller.refreshStatus();
      final outcome = await h.perform();
      expect(outcome?.ok, isTrue);
      expect(outcome?.checkedIn, isFalse);
      expect(h.api.checkOuts, hasLength(1));
      expect(h.api.checkIns, isEmpty);
    });

    test(
      'Wi-Fi gate not met: the button stays ready, the tap says why',
      () async {
        final h = _Harness(status: _status(requiredSsids: ['hq-wifi']));
        await h.controller.refreshStatus();
        expect(h.controller.lastWifi?.ssid, 'office');
        expect(h.controller.buttonState, AttendanceButtonState.ready);
        final outcome = await h.perform();
        expect(outcome?.error, friendlyError('wifi_not_recognized'));
        expect(h.captures, 0);
        expect(h.api.checkIns, isEmpty);
        expect(h.api.checkOuts, isEmpty);
      },
    );

    test('a cancelled capture is silent', () async {
      final h = _Harness();
      await h.controller.refreshStatus();
      expect(await h.perform(cancel: true), isNull);
      expect(h.api.checkIns, isEmpty);
    });

    test('face not recognised: error, nothing sent', () async {
      final h = _Harness(faceOk: false);
      await h.controller.refreshStatus();
      final outcome = await h.perform();
      expect(outcome?.error, 'Face not recognized. Please try again.');
      expect(h.api.checkIns, isEmpty);
    });

    test('not enrolled: opens enrolment instead of punching', () async {
      final h = _Harness(enrolled: false);
      await h.controller.refreshStatus();
      final outcome = await h.perform();
      expect(outcome?.enrolled, isTrue);
      expect(h.enrolments, 1);
      expect(h.refreshes, 1);
      expect(h.api.checkIns, isEmpty);
    });

    test(
      'disposed while a punch awaits the GPS: completing it is silent',
      () async {
        final gps = Completer<LocationResult>();
        final api = _FakeApi(_status());
        final controller = AttendanceActionController(
          session: SessionService(),
          apiBuilder: (_) => api,
          getLocation: () => gps.future,
          getWifi: () async => const WifiInfoResult.ready(ssid: 'office'),
          getDeviceId: () async => 'device-1',
          isEnrolled: () => true,
          verifyFace: (_) async => FaceVerifyResult(ok: true),
          refreshEnrolled: () async {},
          devLocation: false,
          simulateFace: false,
        );
        final pending = controller.perform(
          captureFace: () async => FaceCaptureResult.success('/tmp/face.jpg'),
          enrol: () async {},
        );
        await Future<void>.delayed(Duration.zero);
        controller.dispose();
        gps.complete(_at(1.31, _officeLng));
        await expectLater(pending, completes); // no "used after dispose"
      },
    );
  });
}
