import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/core/error_messages.dart';
import 'package:omni_hr/models/attendance_status.dart';
import 'package:omni_hr/models/expense_record.dart';
import 'package:omni_hr/models/face_capture_result.dart';
import 'package:omni_hr/models/location_result.dart';
import 'package:omni_hr/models/wifi_info_result.dart';
import 'package:omni_hr/models/my_day.dart';
import 'package:omni_hr/screens/home/my_day/check_in_out_screen.dart';
import 'package:omni_hr/screens/home/my_day/declaration_sheet.dart';
import 'package:omni_hr/screens/home/my_day/my_day_screen.dart';
import 'package:omni_hr/services/attendance_action_controller.dart';
import 'package:omni_hr/services/face_recognition_service.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';

import '../../fixtures/my_day_fixture.dart';

const _banner = "Couldn't refresh. Pull down to try again.";

/// Scriptable API: each fetchMyDay() call pops the next scripted result
/// (a MyDay, or an Object to throw); the last one repeats.
class _FakeApi extends OmniMobileApi {
  _FakeApi(this.script) : super(baseUrl: '', db: '', token: '');

  final List<Object> script;
  int calls = 0;
  int expenseCalls = 0;
  List<ExpenseRecord> expenses = [];

  /// When set, fetchMyDay / getExpenseList wait for it before answering.
  Completer<void>? fetchGate;
  Completer<void>? expenseGate;

  AttendanceStatus attendance = AttendanceStatus.fromJson({
    'checked_in': false,
    'hours_today': 0,
    'employee_id': 1,
    'auth_type': 'app',
    'office_latitude': 1.3,
    'office_longitude': 103.8,
    'office_radius_meters': 200,
    'flexible_location': false,
  });
  final checkIns = <bool>[];
  Map<String, dynamic> checkInResponse = const {};
  Object? checkInError;

  @override
  Future<AttendanceStatus> getAttendanceStatus() async => attendance;

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
    final error = checkInError;
    if (error != null) throw error;
    checkIns.add(faceVerified);
    attendance = AttendanceStatus.fromJson({
      'checked_in': true,
      'hours_today': 0,
      'employee_id': 1,
      'auth_type': 'app',
      'office_latitude': 1.3,
      'office_longitude': 103.8,
      'office_radius_meters': 200,
      'flexible_location': false,
    });
    return checkInResponse;
  }

  int checkOuts = 0;

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
    checkOuts++;
    return const {};
  }

  final declares = <Map<String, Object?>>[];
  final undos = <int>[];

  @override
  Future<bool> declare({
    required int attendanceId,
    required String trigger,
    required String answerCode,
    DateTime? declaredTime,
    String note = '',
  }) async {
    declares.add({
      'attendance_id': attendanceId,
      'trigger': trigger,
      'answer_code': answerCode,
      'declared_time': declaredTime,
      'note': note,
    });
    return true;
  }

  @override
  Future<AttendanceStatus> undoPunch(int attendanceId) async {
    undos.add(attendanceId);
    attendance = AttendanceStatus.fromJson({
      'checked_in': false,
      'hours_today': 0,
      'employee_id': 1,
      'auth_type': 'app',
      'office_latitude': 1.3,
      'office_longitude': 103.8,
      'office_radius_meters': 200,
      'flexible_location': false,
    });
    return attendance;
  }

  @override
  Future<MyDay> fetchMyDay() async {
    final i = calls < script.length ? calls : script.length - 1;
    calls++;
    final gate = fetchGate;
    if (gate != null) await gate.future;
    final result = script[i];
    if (result is MyDay) return result;
    throw result;
  }

  @override
  Future<ExpenseListPage> getExpenseList({int? beforeId}) async {
    expenseCalls++;
    final gate = expenseGate;
    if (gate != null) await gate.future;
    return ExpenseListPage(records: expenses, hasMore: false);
  }
}

class _Calls {
  final leave = <int>[];
  final expense = <int>[];
  int sessionRefreshes = 0;
  int captures = 0;
  int enrolments = 0;
  int controllers = 0;
}

/// A tenant whose subscription has Attendance switched off.
class _NoAttendanceSession extends SessionService {
  @override
  bool get featureAttendance => false;
}

/// A /me approvals block that agrees with the fixture's For-you card.
const _approver3 = {
  'leave_approvals': {'enabled': true, 'pending_count': 3},
};

/// A session that already knows the user approves leave.
class _ApproverSession extends SessionService {
  _ApproverSession({required this.count});

  final int count;

  @override
  bool get leaveApprovalsEnabled => true;

  @override
  int get leaveApprovalsPendingCount => count;
}

Widget _host(
  _FakeApi api, {
  Key? key,
  _Calls? calls,
  SessionService? session,
  double latitude = 1.3,
  bool enrolled = true,
  _Calls? enrolCalls,
  Future<LocationResult> Function()? getLocation,
  bool signaturePage = false,
}) => ChangeNotifierProvider<SessionService>(
  create: (_) => session ?? SessionService(),
  child: MaterialApp(
    home: MyDayScreen(
      key: key,
      apiBuilder: (_) => api,
      appBar: AppBar(title: const Text('TEST BAR')),
      onOpenLeave: (id) => calls?.leave.add(id),
      onOpenExpense: (id) => calls?.expense.add(id),
      refreshSession: () async => calls?.sessionRefreshes++,
      controllerBuilder: (session) => _counted(
        calls,
        AttendanceActionController(
          session: session,
          apiBuilder: (_) => api,
          getLocation:
              getLocation ??
              () async => LocationResult(
                status: LocationStatus.ready,
                latitude: latitude,
                longitude: 103.8,
                accuracy: 5,
              ),
          getWifi: () async => const WifiInfoResult.ready(ssid: 'office'),
          getDeviceId: () async => 'device-1',
          isEnrolled: () => enrolled,
          verifyFace: (_) async => FaceVerifyResult(ok: true),
          refreshEnrolled: () async {},
          devLocation: false,
          simulateFace: false,
        ),
      ),
      captureFace: signaturePage
          ? null
          : () async {
              calls?.captures++;
              return FaceCaptureResult.success('/tmp/face.jpg');
            },
      signatureCaptureBuilder: signaturePage
          ? (onResult) => TextButton(
              key: const ValueKey('fake-capture'),
              onPressed: () {
                calls?.captures++;
                onResult(FaceCaptureResult.success('/tmp/face.jpg'));
              },
              child: const Text('SNAP'),
            )
          : null,
      enrol: () async => enrolCalls?.enrolments++,
      destinationBuilder: (item, expense) => Scaffold(
        appBar: AppBar(),
        body: Text('DEST ${item.kind} ${expense?.id ?? '-'}'),
      ),
    ),
  ),
);

AttendanceActionController _counted(
  _Calls? calls,
  AttendanceActionController controller,
) {
  calls?.controllers++;
  return controller;
}

/// Tall enough that every row of the screen is built.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('loads once and shows the card, the timeline and For you', (
    tester,
  ) async {
    _tallScreen(tester);
    final api = _FakeApi([sampleMyDay()]);
    await tester.pumpWidget(_host(api));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(api.calls, 1);
    expect(find.byKey(const ValueKey('status-tile')), findsOneWidget);
    expect(find.text('Checked in'), findsOneWidget);
    expect(find.text('Check in'), findsOneWidget);
    expect(find.text('Shift ends'), findsOneWidget);
    expect(find.text('For you'), findsOneWidget);
    expect(find.text('3 leave requests to approve'), findsOneWidget);
    expect(find.text(_banner), findsNothing);
  });

  testWidgets('sections in order: tile, week, timeline, for you', (
    tester,
  ) async {
    _tallScreen(tester);
    await tester.pumpWidget(_host(_FakeApi([sampleMyDay()])));
    await tester.pumpAndSettle();
    final tile = tester.getTopLeft(find.byKey(const ValueKey('status-tile')));
    final week = tester.getTopLeft(find.text('This week'));
    final timeline = tester.getTopLeft(find.text('Timeline'));
    final forYou = tester.getTopLeft(find.text('For you'));
    expect(tile.dy, lessThan(week.dy));
    expect(week.dy, lessThan(timeline.dy));
    expect(timeline.dy, lessThan(forYou.dy));
  });

  testWidgets('missing day: red For-you row opens the kiosk sheet', (
    tester,
  ) async {
    _tallScreen(tester);
    final day = sampleMyDay(state: 'not_in', missing: true, punches: []);
    await tester.pumpWidget(_host(_FakeApi([day])));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('for-you-missing')),
      200,
    );
    await tester.tap(find.byKey(const ValueKey('for-you-missing')));
    await tester.pumpAndSettle();
    expect(find.text('Phone check-in is off'), findsOneWidget);
  });

  testWidgets('leave day: off card replaces the timeline', (tester) async {
    _tallScreen(tester);
    final day = sampleMyDay(
      state: 'not_in',
      withShift: false,
      punches: [],
      off: {
        'kind': 'leave',
        'name': 'Annual leave',
        'date_from': '2026-10-06',
        'date_to': '2026-10-07',
        'back_on': '2026-10-08',
      },
    );
    await tester.pumpWidget(_host(_FakeApi([day])));
    await tester.pumpAndSettle();
    expect(find.text('Timeline'), findsNothing);
    expect(find.text('Annual leave'), findsOneWidget);
    expect(find.text('From 6 Oct to 7 Oct'), findsOneWidget);
    expect(find.text('Next shift 6 Oct · 08:00 – 17:00'), findsOneWidget);
  });

  testWidgets('holiday: off card with the name and the kiosk line', (
    tester,
  ) async {
    _tallScreen(tester);
    final day = sampleMyDay(
      state: 'not_in',
      withShift: false,
      punches: [],
      off: {'kind': 'public_holiday', 'name': 'Deepavali'},
    );
    await tester.pumpWidget(_host(_FakeApi([day])));
    await tester.pumpAndSettle();
    expect(find.text('Timeline'), findsNothing);
    // The status tile's subtitle and the card's title.
    expect(find.text('Deepavali'), findsNWidgets(2));
    expect(find.text('Nothing is expected at the kiosk today'), findsOneWidget);
    expect(find.text('Next shift 6 Oct · 08:00 – 17:00'), findsOneWidget);
  });

  testWidgets('not scheduled: off card says enjoy your day', (tester) async {
    _tallScreen(tester);
    final day = sampleMyDay(
      state: 'not_in',
      withShift: false,
      punches: [],
      off: {'kind': 'not_scheduled'},
    );
    await tester.pumpWidget(_host(_FakeApi([day])));
    await tester.pumpAndSettle();
    expect(find.text('Timeline'), findsNothing);
    expect(find.text('Enjoy your day'), findsOneWidget);
    expect(find.text('Nothing is expected at the kiosk today'), findsOneWidget);
  });

  testWidgets('empty day: both empty texts', (tester) async {
    _tallScreen(tester);
    final api = _FakeApi([
      sampleMyDay(state: 'not_in', withShift: false, punches: [], forYou: []),
    ]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    expect(find.text('No attendance recorded today.'), findsOneWidget);
    expect(find.text('Nothing needs your attention.'), findsOneWidget);
  });

  testWidgets('first load fails: centred message and Retry', (tester) async {
    _tallScreen(tester);
    final api = _FakeApi([ApiException('network_error'), sampleMyDay()]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    expect(
      find.text('No internet connection. Check your network and try again.'),
      findsOneWidget,
    );
    expect(find.text(_banner), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(api.calls, 2);
    expect(find.text('Checked in'), findsOneWidget);
  });

  testWidgets('a failed refresh keeps the last day under a banner', (
    tester,
  ) async {
    _tallScreen(tester);
    final key = GlobalKey<MyDayScreenState>();
    final api = _FakeApi([
      sampleMyDay(),
      ApiException('timeout'),
      sampleMyDay(state: 'on_break'),
    ]);
    await tester.pumpWidget(_host(api, key: key));
    await tester.pumpAndSettle();

    await key.currentState!.refresh();
    await tester.pumpAndSettle();
    expect(find.text(_banner), findsOneWidget);
    expect(find.text('Checked in'), findsOneWidget);

    await key.currentState!.refresh();
    await tester.pumpAndSettle();
    expect(find.text(_banner), findsNothing);
    expect(find.text('On break'), findsOneWidget);
  });

  testWidgets('pull down refreshes', (tester) async {
    _tallScreen(tester);
    final api = _FakeApi([sampleMyDay()]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Timeline'), const Offset(0, 800));
    await tester.pumpAndSettle();
    expect(api.calls, 2);
  });

  testWidgets('leave_approvals row opens approvals; back refreshes both', (
    tester,
  ) async {
    _tallScreen(tester);
    final calls = _Calls();
    final api = _FakeApi([sampleMyDay()]);
    await tester.pumpWidget(
      _host(api, calls: calls, session: _ApproverSession(count: 3)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 leave requests to approve'));
    await tester.pumpAndSettle();
    expect(find.text('DEST leave_approvals -'), findsOneWidget);
    expect(api.calls, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(calls.sessionRefreshes, 1);
    expect(api.calls, 2);
  });

  testWidgets('my_leave row hands the id to onOpenLeave', (tester) async {
    _tallScreen(tester);
    final calls = _Calls();
    await tester.pumpWidget(_host(_FakeApi([sampleMyDay()]), calls: calls));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annual leave · 12 Oct – 13 Oct'));
    await tester.pumpAndSettle();
    expect(calls.leave, [412]);
    expect(find.textContaining('DEST'), findsNothing);
  });

  testWidgets('my_expense row opens the expense detail; back refreshes', (
    tester,
  ) async {
    _tallScreen(tester);
    final calls = _Calls();
    final api = _FakeApi([sampleMyDay()])
      ..expenses = [
        ExpenseRecord.fromJson({
          'id': 88,
          'name': 'Transport',
          'state': 'submitted',
        }),
      ];
    await tester.pumpWidget(
      _host(api, calls: calls, session: _ApproverSession(count: 3)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transport'));
    await tester.pumpAndSettle();
    expect(find.text('DEST my_expense 88'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(api.calls, 2);
    expect(calls.sessionRefreshes, 0);
    expect(calls.expense, isEmpty);
  });

  testWidgets('my_expense row falls back to the Expenses tab', (tester) async {
    _tallScreen(tester);
    final calls = _Calls();
    await tester.pumpWidget(_host(_FakeApi([sampleMyDay()]), calls: calls));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transport'));
    await tester.pumpAndSettle();
    expect(calls.expense, [88]);
    expect(find.textContaining('DEST'), findsNothing);
  });

  testWidgets('payslip row opens the payslip screen; back refreshes', (
    tester,
  ) async {
    _tallScreen(tester);
    final api = _FakeApi([sampleMyDay()]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('September 2026 payslip is ready'));
    await tester.pumpAndSettle();
    expect(find.text('DEST payslip -'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(api.calls, 2);
  });

  testWidgets('rows without an id (0) do nothing', (tester) async {
    _tallScreen(tester);
    final calls = _Calls();
    final api = _FakeApi([
      sampleMyDay(
        forYou: [
          {'kind': 'my_leave', 'type': 'Sick leave', 'state': 'confirm'},
          {'kind': 'my_expense', 'name': 'Taxi', 'state': 'submitted'},
        ],
      ),
    ]);
    await tester.pumpWidget(_host(api, calls: calls));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Sick leave'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Taxi'));
    await tester.pumpAndSettle();
    expect(calls.leave, isEmpty);
    expect(calls.expense, isEmpty);
    expect(find.textContaining('DEST'), findsNothing);
    expect(api.calls, 1);
  });

  testWidgets('a refresh during a push is shared with the return refresh', (
    tester,
  ) async {
    _tallScreen(tester);
    final key = GlobalKey<MyDayScreenState>();
    final api = _FakeApi([sampleMyDay()]);
    await tester.pumpWidget(_host(api, key: key));
    await tester.pumpAndSettle();
    await tester.tap(find.text('September 2026 payslip is ready'));
    await tester.pumpAndSettle();
    expect(api.calls, 1);

    api.fetchGate = Completer<void>();
    final tabTap = key.currentState!.refresh(); // e.g. a Home tab tap
    await tester.pageBack(); // the return-from-push refresh
    await tester.pump(const Duration(seconds: 1));
    expect(api.calls, 2);
    api.fetchGate!.complete();
    await tabTap;
    await tester.pumpAndSettle();
    expect(api.calls, 2);

    // Once finished, a new refresh issues a new request.
    api.fetchGate = null;
    await key.currentState!.refresh();
    expect(api.calls, 3);
  });

  testWidgets('app resume refreshes once', (tester) async {
    _tallScreen(tester);
    final api = _FakeApi([sampleMyDay()]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    expect(api.calls, 1);

    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(api.calls, 1);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(api.calls, 2);
  });

  testWidgets(
    'kiosk_only false re-pulls /me when the session still says true',
    (tester) async {
      _tallScreen(tester);
      FlutterSecureStorage.setMockInitialValues({});
      final session = SessionService();
      await tester.runAsync(
        () => session.saveLoginResponse({
          'success': true,
          'access_token': 'A',
          'expires_at': '2026-10-13 10:00:00',
          'auth_source': 'omni',
          'user': {'id': 9, 'login': 'a@b.c', 'name': 'A'},
          'employee': {'id': 6, 'name': 'A', 'attendance_kiosk_only': true},
        }),
      );
      // The session agrees with the fixture's approvals card (3), so only
      // the kiosk flag can cause a re-pull here.
      await tester.runAsync(() => session.updateLeaveApprovalsFromMe(_approver3));
      expect(session.attendanceKioskOnly, isTrue);

      final calls = _Calls();
      final api = _FakeApi([
        sampleMyDay(),
        sampleMyDay(kioskOnly: false),
        sampleMyDay(kioskOnly: false),
      ]);
      final key = GlobalKey<MyDayScreenState>();
      await tester.pumpWidget(
        _host(api, key: key, calls: calls, session: session),
      );
      await tester.pumpAndSettle();
      expect(calls.sessionRefreshes, 0);

      await key.currentState!.refresh();
      await tester.pumpAndSettle();
      expect(calls.sessionRefreshes, 1);
    },
  );

  testWidgets('a kiosk_only answer does not re-pull /me', (tester) async {
    _tallScreen(tester);
    FlutterSecureStorage.setMockInitialValues({});
    final session = SessionService();
    await tester.runAsync(
      () => session.saveLoginResponse({
        'success': true,
        'access_token': 'A',
        'expires_at': '2026-10-13 10:00:00',
        'auth_source': 'omni',
        'user': {'id': 9, 'login': 'a@b.c', 'name': 'A'},
        'employee': {'id': 6, 'name': 'A', 'attendance_kiosk_only': true},
      }),
    );
    await tester.runAsync(() => session.updateLeaveApprovalsFromMe(_approver3));
    expect(session.attendanceKioskOnly, isTrue);

    final calls = _Calls();
    final key = GlobalKey<MyDayScreenState>();
    await tester.pumpWidget(
      _host(
        _FakeApi([sampleMyDay()]), // the server also says kiosk_only: true
        key: key,
        calls: calls,
        session: session,
      ),
    );
    await tester.pumpAndSettle();
    await key.currentState!.refresh();
    await tester.pumpAndSettle();
    expect(calls.sessionRefreshes, 0);
  });

  testWidgets('rows stay tappable while the return refresh is pending', (
    tester,
  ) async {
    _tallScreen(tester);
    final api = _FakeApi([sampleMyDay()]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('September 2026 payslip is ready'));
    await tester.pumpAndSettle();
    expect(find.text('DEST payslip -'), findsOneWidget);

    // Back from the pushed screen, with the follow-up refresh still pending.
    api.fetchGate = Completer<void>();
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(api.calls, 2);
    expect(find.textContaining('DEST'), findsNothing);

    // Another row is not ignored: it pushes its screen.
    await tester.tap(find.text('3 leave requests to approve'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('DEST leave_approvals -'), findsOneWidget);

    api.fetchGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('DEST leave_approvals -'), findsOneWidget);
  });

  testWidgets('a second tap while the expense lookup runs is ignored', (
    tester,
  ) async {
    _tallScreen(tester);
    final calls = _Calls();
    final api = _FakeApi([sampleMyDay()])
      ..expenses = [
        ExpenseRecord.fromJson({
          'id': 88,
          'name': 'Transport',
          'state': 'submitted',
        }),
      ]
      ..expenseGate = Completer<void>();
    await tester.pumpWidget(_host(api, calls: calls));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transport'));
    await tester.pump();
    await tester.tap(find.text('Transport'));
    await tester.pump();
    api.expenseGate!.complete();
    await tester.pumpAndSettle();
    expect(api.expenseCalls, 1);
    expect(find.text('DEST my_expense 88'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('DEST'), findsNothing);
    expect(find.text('For you'), findsOneWidget);
    expect(api.calls, 2);

    // The guard is released afterwards: the row opens again.
    api.expenseGate = null;
    await tester.tap(find.text('Transport'));
    await tester.pumpAndSettle();
    expect(find.text('DEST my_expense 88'), findsOneWidget);
    expect(api.expenseCalls, 2);
  });

  testWidgets('phone day: the tile carries Check in and the live place', (
    tester,
  ) async {
    _tallScreen(tester);
    final day = sampleMyDay(state: 'not_in', punches: [], kioskOnly: false);
    await tester.pumpWidget(_host(_FakeApi([day])));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('status-action')), findsOneWidget);
    expect(find.text('Check in'), findsOneWidget);
    expect(find.byKey(const ValueKey('status-kiosk-button')), findsNothing);
    expect(find.byKey(const ValueKey('status-pin-on')), findsOneWidget);
    expect(find.textContaining('Office (0 m)'), findsOneWidget);
  });

  testWidgets('tapping Check in captures, posts and reloads the day', (
    tester,
  ) async {
    _tallScreen(tester);
    final before = sampleMyDay(state: 'not_in', punches: [], kioskOnly: false);
    final after = sampleMyDay(kioskOnly: false);
    final api = _FakeApi([before, after]);
    final calls = _Calls();
    await tester.pumpWidget(_host(api, calls: calls));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('status-action')));
    await tester.pumpAndSettle();
    expect(calls.captures, 1);
    expect(api.checkIns, [true]);
    expect(find.text('Checked in successfully!'), findsOneWidget);
    expect(api.calls, 2);
    expect(find.text('Check out'), findsOneWidget);
  });

  testWidgets('Check in opens the signature page, counts down and posts', (
    tester,
  ) async {
    _tallScreen(tester);
    final before = sampleMyDay(state: 'not_in', punches: [], kioskOnly: false);
    final after = sampleMyDay(kioskOnly: false);
    final api = _FakeApi([before, after]);
    final calls = _Calls();
    await tester.pumpWidget(_host(api, calls: calls, signaturePage: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('status-action')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CheckInOutScreen), findsOneWidget);
    expect(find.text('CHECK IN'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('fake-capture')));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(calls.captures, 1);
    expect(api.checkIns, [true]);
    expect(find.byType(CheckInOutScreen), findsNothing);
    expect(find.text('Checked in successfully!'), findsOneWidget);
    expect(find.text('Check out'), findsOneWidget);
  });

  testWidgets('a missing phone day has no red For-you row', (tester) async {
    _tallScreen(tester);
    final day = sampleMyDay(
      state: 'not_in',
      missing: true,
      punches: [],
      kioskOnly: false,
    );
    await tester.pumpWidget(_host(_FakeApi([day])));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('for-you-missing')), findsNothing);
    expect(find.text('No check-in'), findsOneWidget);
  });

  testWidgets('kiosk-only day: no action button', (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(_host(_FakeApi([sampleMyDay()])));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('status-action')), findsNothing);
    expect(find.byKey(const ValueKey('status-kiosk-button')), findsOneWidget);
  });

  testWidgets(
    'a For-you approvals count that differs from the session re-pulls /me',
    (tester) async {
      _tallScreen(tester);
      final day = sampleMyDay(
        forYou: [
          {
            'kind': 'leave_approvals',
            'count': 2,
            'oldest_at': '2026-10-05 01:00:00',
          },
        ],
      );
      final calls = _Calls();
      await tester.pumpWidget(
        _host(
          _FakeApi([day]),
          calls: calls,
          session: _ApproverSession(count: 1),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls.sessionRefreshes, 1);

      // A session that does not know yet that the user approves (fresh
      // login: /login has no leave_approvals block) re-pulls too, so the
      // LEAVE badge shows the card's count (M8).
      final fresh = _Calls();
      // Unmount first: a re-pump would keep the old Provider's session.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _host(_FakeApi([day]), calls: fresh, key: UniqueKey()),
      );
      await tester.pumpAndSettle();
      expect(fresh.sessionRefreshes, 1);

      // No card and no approver: nothing to re-pull.
      final none = _Calls();
      // Unmount first: a re-pump would keep the old Provider's session.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _host(
          _FakeApi([sampleMyDay(forYou: [])]),
          calls: none,
          key: UniqueKey(),
        ),
      );
      await tester.pumpAndSettle();
      expect(none.sessionRefreshes, 0);

      // The numbers agree: nothing to re-pull.
      final agreed = _Calls();
      // Unmount first: a re-pump would keep the old Provider's session.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _host(
          _FakeApi([day]),
          calls: agreed,
          session: _ApproverSession(count: 2),
          key: UniqueKey(),
        ),
      );
      await tester.pumpAndSettle();
      expect(agreed.sessionRefreshes, 0);
    },
  );

  testWidgets('not enrolled: the tile offers face setup, no punch', (
    tester,
  ) async {
    _tallScreen(tester);
    final day = sampleMyDay(state: 'not_in', punches: [], kioskOnly: false);
    final api = _FakeApi([day]);
    final calls = _Calls();
    await tester.pumpWidget(_host(api, enrolled: false, enrolCalls: calls));
    await tester.pumpAndSettle();
    expect(find.text('Set up your face'), findsOneWidget);
    expect(find.byIcon(Icons.face_retouching_natural), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('status-action')));
    await tester.pumpAndSettle();
    expect(calls.enrolments, 1);
    expect(api.checkIns, isEmpty);
  });

  testWidgets('a failed punch shows the error and does not reload the day', (
    tester,
  ) async {
    _tallScreen(tester);
    final day = sampleMyDay(state: 'not_in', punches: [], kioskOnly: false);
    final api = _FakeApi([day])..checkInError = ApiException('network_error');
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('status-action')));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.text('No internet connection. Check your network and try again.'),
      findsOneWidget,
    );
    expect(find.text('Checked in successfully!'), findsNothing);
    expect(api.calls, 1);
  });

  testWidgets('an auto-closed check-in shows the banner; dismiss hides it', (
    tester,
  ) async {
    _tallScreen(tester);
    final before = sampleMyDay(state: 'not_in', punches: [], kioskOnly: false);
    final api = _FakeApi([before, sampleMyDay(kioskOnly: false)])
      ..checkInResponse = {
        'auto_closed_previous': {
          'attendance_id': 7,
          'original_check_in': '2026-10-03 00:00:00',
          'inferred_check_out': '2026-10-03 09:00:00',
          'hours_assumed': 9,
          'hours_open_when_closed': 30,
        },
      };
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('status-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('auto-closed-banner')), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('auto-closed-banner')), findsNothing);
  });

  testWidgets('outside the office: a dead Check in and the off pin', (
    tester,
  ) async {
    _tallScreen(tester);
    final day = sampleMyDay(state: 'not_in', punches: [], kioskOnly: false);
    final api = _FakeApi([day]);
    await tester.pumpWidget(_host(api, latitude: 1.31));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('status-pin-off')), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('status-action')),
    );
    expect(button.onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('status-action')));
    await tester.pumpAndSettle();
    expect(api.checkIns, isEmpty);
  });

  testWidgets('a closed punch row and not_in: outlined Check in again', (
    tester,
  ) async {
    _tallScreen(tester);
    final day = sampleMyDay(state: 'not_in', kioskOnly: false);
    await tester.pumpWidget(_host(_FakeApi([day])));
    await tester.pumpAndSettle();
    expect(find.text('Check in again'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is OutlinedButton && w.key == const ValueKey('status-action'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'the day turning kiosk-only swaps the action for the kiosk hint',
    (tester) async {
      _tallScreen(tester);
      final key = GlobalKey<MyDayScreenState>();
      final api = _FakeApi([
        sampleMyDay(state: 'not_in', punches: [], kioskOnly: false),
        sampleMyDay(state: 'not_in', punches: []),
      ]);
      await tester.pumpWidget(_host(api, key: key));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('status-action')), findsOneWidget);

      await key.currentState!.refresh();
      await tester.pump();
      expect(find.byKey(const ValueKey('status-action')), findsNothing);
      expect(find.byKey(const ValueKey('status-kiosk-button')), findsOneWidget);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'on break (checked out): outlined Check in again posts a check-in',
    (tester) async {
      _tallScreen(tester);
      final day = sampleMyDay(state: 'on_break', kioskOnly: false);
      final api = _FakeApi([day]); // /attendance/status: not checked in
      final calls = _Calls();
      await tester.pumpWidget(_host(api, calls: calls));
      await tester.pumpAndSettle();
      expect(find.text('On break'), findsOneWidget);
      expect(find.text('Check out'), findsNothing);
      expect(find.text('Check in again'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is OutlinedButton && w.key == const ValueKey('status-action'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('status-action')));
      await tester.pumpAndSettle();
      expect(api.checkIns, [true]);
      expect(api.checkOuts, 0);
      expect(find.text('Checked in successfully!'), findsOneWidget);
    },
  );

  for (final off in <Map<String, dynamic>>[
    {'kind': 'leave', 'name': 'Annual leave'},
    {'kind': 'public_holiday', 'name': 'Deepavali'},
    {'kind': 'not_scheduled'},
  ]) {
    testWidgets('${off['kind']} phone day: outlined Check in that punches', (
      tester,
    ) async {
      _tallScreen(tester);
      final day = sampleMyDay(
        state: 'not_in',
        withShift: false,
        punches: [],
        off: off,
        kioskOnly: false,
      );
      final api = _FakeApi([day]);
      await tester.pumpWidget(_host(api));
      await tester.pumpAndSettle();
      expect(find.text('Check in'), findsOneWidget);
      final button = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('status-action')),
      );
      expect(button.onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('status-action')));
      await tester.pumpAndSettle();
      expect(api.checkIns, [true]);
    });
  }

  testWidgets('Attendance off: locked pane, no tile, no controller', (
    tester,
  ) async {
    _tallScreen(tester);
    final calls = _Calls();
    final day = sampleMyDay(state: 'not_in', punches: [], kioskOnly: false);
    await tester.pumpWidget(
      _host(_FakeApi([day]), calls: calls, session: _NoAttendanceSession()),
    );
    await tester.pumpAndSettle();
    expect(calls.controllers, 0);
    expect(find.text('Attendance not active'), findsOneWidget);
    expect(find.byKey(const ValueKey('status-tile')), findsNothing);
    expect(find.byKey(const ValueKey('status-action')), findsNothing);
    expect(find.text('Timeline'), findsNothing);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('For you'), findsOneWidget);
    expect(find.text('3 leave requests to approve'), findsOneWidget);
  });

  testWidgets('a punch that throws shows the friendly error', (tester) async {
    _tallScreen(tester);
    final day = sampleMyDay(state: 'not_in', punches: [], kioskOnly: false);
    final api = _FakeApi([day]);
    var fixes = 0;
    final boom = StateError('gps boom');
    await tester.pumpWidget(
      _host(
        api,
        getLocation: () async {
          // The first fix (screen load) works; the punch's fresh fix throws.
          if (fixes++ == 0) {
            return LocationResult(
              status: LocationStatus.ready,
              latitude: 1.3,
              longitude: 103.8,
              accuracy: 5,
            );
          }
          throw boom;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('status-action')));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(friendlyError(boom)), findsOneWidget);
    expect(api.checkIns, isEmpty);
    expect(api.calls, 1);
    // `acting` was reset: the button is live again.
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('status-action')),
    );
    expect(button.onPressed, isNotNull);
  });

  group('forgot something (connector 2.54.0)', () {
    Map<String, dynamic> lateAsk() => {
      'trigger': 'late_first_in',
      'attendance_id': 812,
      'tapped_at': '2026-10-05 10:12:00',
      'shift_start': '2026-10-05 09:00:00',
      'shift_end': '2026-10-05 18:00:00',
      'last_out': null,
      'suggested_time': '2026-10-05 09:00:00',
      'options': [
        {'code': 'started_at', 'label': 'I started at', 'needs_time': true},
        {
          'code': 'just_arriving',
          'label': 'Just arriving',
          'needs_time': false,
        },
      ],
    };

    /// A phone day: tap Check in; the connector answers [response].
    Future<_FakeApi> punch(
      WidgetTester tester,
      Map<String, dynamic> response,
    ) async {
      _tallScreen(tester);
      final api = _FakeApi([
        sampleMyDay(state: 'not_in', punches: [], kioskOnly: false),
        sampleMyDay(kioskOnly: false),
      ])..checkInResponse = response;
      await tester.pumpWidget(_host(api));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('status-action')));
      await tester.pumpAndSettle();
      return api;
    }

    testWidgets('an ask opens the sheet after the snackbar and the reload', (
      tester,
    ) async {
      final api = await punch(tester, {'attendance_id': 812, 'ask': lateAsk()});
      expect(find.text('Checked in successfully!'), findsOneWidget);
      expect(find.byType(DeclarationSheet), findsOneWidget);
      expect(find.text('Forgot something?'), findsOneWidget);
      expect(find.text('I started at'), findsOneWidget);
      expect(api.calls, 2);
    });

    testWidgets(
      'answering posts declare with the trigger, the row and the time',
      (tester) async {
        final api = await punch(tester, {
          'attendance_id': 812,
          'ask': lateAsk(),
        });
        await tester.tap(find.byKey(const ValueKey('declaration-send')));
        await tester.pumpAndSettle();
        expect(api.declares, [
          {
            'attendance_id': 812,
            'trigger': 'late_first_in',
            'answer_code': 'started_at',
            'declared_time': DateTime.utc(2026, 10, 5, 9),
            'note': '',
          },
        ]);
        expect(find.byType(DeclarationSheet), findsNothing);
        expect(find.text('Sent to HR'), findsOneWidget);
      },
    );

    testWidgets('Starting now posts nothing', (tester) async {
      final ask = {
        ...lateAsk(),
        'trigger': 'break_long',
        'last_out': '2026-10-05 05:00:00',
        'options': [
          {
            'code': 'back_at',
            'label': 'Back from break since',
            'needs_time': true,
          },
          {
            'code': 'long_break',
            'label': 'It was a long break',
            'needs_time': false,
          },
          {'code': 'start_now', 'label': 'Starting now', 'needs_time': false},
        ],
      };
      final api = await punch(tester, {'attendance_id': 812, 'ask': ask});
      await tester.tap(
        find.byKey(const ValueKey('declaration-option-start_now')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('declaration-send')));
      await tester.pumpAndSettle();
      expect(api.declares, isEmpty);
      expect(find.text('Sent to HR'), findsNothing);
    });

    testWidgets('Skip posts nothing', (tester) async {
      final api = await punch(tester, {'attendance_id': 812, 'ask': lateAsk()});
      await tester.tap(find.byKey(const ValueKey('declaration-skip')));
      await tester.pumpAndSettle();
      expect(find.byType(DeclarationSheet), findsNothing);
      expect(api.declares, isEmpty);
    });

    testWidgets('no ask (connector 2.53.x): no sheet', (tester) async {
      final api = await punch(tester, {'attendance_id': 812});
      expect(find.text('Checked in successfully!'), findsOneWidget);
      expect(find.byType(DeclarationSheet), findsNothing);
      expect(find.text('UNDO'), findsNothing);
      expect(api.declares, isEmpty);
    });

    testWidgets(
      'UNDO before undo_until undoes the punch and applies the status',
      (tester) async {
        final until = DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 2))
            .toIso8601String();
        final api = await punch(tester, {
          'attendance_id': 812,
          'undo_until': until,
        });
        expect(find.text('UNDO'), findsOneWidget);
        await tester.tap(find.text('UNDO'));
        await tester.pumpAndSettle();
        expect(api.undos, [812]);
        expect(find.text('Punch undone'), findsOneWidget);
        expect(api.calls, 3);
        expect(find.text('Check out'), findsNothing);
        expect(find.text('Check in again'), findsOneWidget);
      },
    );

    testWidgets('UNDO before the reload finishes: no question afterwards', (
      tester,
    ) async {
      _tallScreen(tester);
      final until = DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 2))
          .toIso8601String();
      final api =
          _FakeApi([
              sampleMyDay(state: 'not_in', punches: [], kioskOnly: false),
              sampleMyDay(kioskOnly: false),
            ])
            ..checkInResponse = {
              'attendance_id': 812,
              'ask': lateAsk(),
              'undo_until': until,
            };
      await tester.pumpWidget(_host(api));
      await tester.pumpAndSettle();
      final gate = Completer<void>();
      api.fetchGate = gate;
      await tester.tap(find.byKey(const ValueKey('status-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('UNDO'), findsOneWidget);
      await tester.tap(find.text('UNDO'));
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();
      expect(api.undos, [812]);
      expect(api.declares, isEmpty);
      expect(find.byType(DeclarationSheet), findsNothing);
    });

    testWidgets('an expired undo_until offers no UNDO', (tester) async {
      final until = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 1))
          .toIso8601String();
      await punch(tester, {'attendance_id': 812, 'undo_until': until});
      expect(find.text('Checked in successfully!'), findsOneWidget);
      expect(find.text('UNDO'), findsNothing);
    });

    testWidgets('after the shift: the undo answer undoes the check-in', (
      tester,
    ) async {
      final ask = {
        ...lateAsk(),
        'trigger': 'after_end',
        'suggested_time': null,
        'options': [
          {'code': 'overtime', 'label': 'Yes, overtime', 'needs_time': false},
          {
            'code': 'undo',
            'label': 'No — undo this check-in',
            'needs_time': false,
          },
        ],
      };
      final api = await punch(tester, {'attendance_id': 812, 'ask': ask});
      await tester.tap(find.byKey(const ValueKey('declaration-option-undo')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('declaration-send')));
      await tester.pumpAndSettle();
      expect(api.undos, [812]);
      expect(api.declares, isEmpty);
      expect(find.text('Punch undone'), findsOneWidget);
    });
  });

  group('yesterday looks incomplete (connector 2.54.0)', () {
    final item = <String, dynamic>{
      'kind': 'yesterday_incomplete',
      'date': '2026-10-04',
      'verdict': 'no_checkout',
      'attendance_id': 798,
      'title': 'Yesterday looks incomplete',
      'body': 'No check-out was recorded for Sun 4 Oct. Tell HR when you left.',
      'options': [
        {
          'code': 'left_at',
          'label': 'I left at',
          'needs_time': true,
          'suggested_time': '2026-10-04 10:00:00',
        },
      ],
    };

    testWidgets('Tell HR opens the sheet and posts with trigger yesterday', (
      tester,
    ) async {
      _tallScreen(tester);
      final api = _FakeApi([
        sampleMyDay(forYou: [item]),
      ]);
      await tester.pumpWidget(_host(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tell HR'));
      await tester.pumpAndSettle();
      expect(find.byType(DeclarationSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DeclarationSheet),
          matching: find.text(
            'No check-out was recorded for Sun 4 Oct. Tell HR when you left.',
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('declaration-send')));
      await tester.pumpAndSettle();
      expect(api.declares, [
        {
          'attendance_id': 798,
          'trigger': 'yesterday',
          'answer_code': 'left_at',
          'declared_time': DateTime.utc(2026, 10, 4, 10),
          'note': '',
        },
      ]);
      expect(find.text('Sent to HR'), findsOneWidget);
      expect(api.calls, 2);
    });

    testWidgets('no item (connector 2.53.x): no card', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(_host(_FakeApi([sampleMyDay()])));
      await tester.pumpAndSettle();
      expect(find.text('Tell HR'), findsNothing);
      expect(find.text('Yesterday looks incomplete'), findsNothing);
    });
  });
}
