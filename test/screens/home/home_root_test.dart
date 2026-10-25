import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/models/my_day.dart';
import 'package:omni_hr/models/notification_record.dart';
import 'package:omni_hr/models/team_overview.dart';
import 'package:omni_hr/screens/home/home_root.dart';
import 'package:omni_hr/screens/home/my_day/my_day_screen.dart';
import 'package:omni_hr/screens/home/overview/team_overview_screen.dart';
import 'package:omni_hr/screens/notifications/notification_tap.dart';
import 'package:omni_hr/services/my_day_memory.dart';
import 'package:omni_hr/services/notification_service.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:omni_hr/widgets/error_state_view.dart';
import 'package:omni_hr/widgets/feature_locked_pane.dart';

import '../../fixtures/my_day_fixture.dart';

/// The real session (T1 parsing, `homeView`), with `refreshMe` counted
/// instead of sent.
class _Session extends SessionService {
  int refreshes = 0;

  @override
  Future<bool> refreshMe() async {
    refreshes++;
    return true;
  }
}

/// A `/me` answer for [SessionService.refreshMeWith].
class _MeApi extends OmniMobileApi {
  _MeApi(this.employee)
    : super(baseUrl: 'https://example.test', db: 'testdb', token: '');

  final Map<String, dynamic> employee;

  @override
  Future<Map<String, dynamic>> me() async => {
    'success': true,
    'auth_source': 'omni',
    'user': {'id': 9, 'login': 'a@b.c', 'name': 'A'},
    'employee': employee,
  };
}

class _MyDayApi extends OmniMobileApi {
  _MyDayApi() : super(baseUrl: '', db: '', token: '');

  int calls = 0;
  Object? error;

  /// When set, every call waits for it before answering.
  Completer<void>? gate;

  @override
  Future<MyDay> fetchMyDay() async {
    calls++;
    final g = gate;
    if (g != null) await g.future;
    final e = error;
    if (e != null) throw e;
    return sampleMyDay();
  }
}

class _OverviewApi extends OmniMobileApi {
  _OverviewApi({this.timeOff = true}) : super(baseUrl: '', db: '', token: '');

  /// The plan's Time Off. Without it the server sends no Who's out
  /// (`sections.leave: false`, `who_out: null`, A-L24).
  final bool timeOff;
  int calls = 0;
  Object? error;

  @override
  Future<TeamOverview> fetchOverview({
    String day = 'today',
    int? departmentId,
  }) async {
    calls++;
    final e = error;
    if (e != null) throw e;
    return TeamOverview.fromJson({
      ..._overviewJson(),
      if (!timeOff) ...{
        'sections': {'attendance': true, 'leave': false},
        'who_out': null,
      },
    });
  }
}

class _Bell extends NotificationService {
  final marked = <int>[];

  @override
  Future<void> refreshList() async {}

  @override
  Future<void> markRead(int id) async {
    marked.add(id);
  }
}

/// The contract's `home/overview` example.
Map<String, dynamic> _overviewJson() => {
  'success': true,
  'day': 'today',
  'date': '2026-10-22',
  'as_of': '09:12',
  'live': true,
  'scope': {
    'access': 'company',
    'label': 'Novaworks',
    'department_id': null,
    'empty_reason': null,
  },
  'departments': [
    {'id': 5, 'name': 'Marketing'},
  ],
  'sections': {'attendance': true, 'leave': true},
  'names': true,
  'counts': {
    'on_time': 36,
    'late': 6,
    'not_in_yet': 4,
    'no_check_in': 3,
    'on_leave': 4,
    'off_today': 1,
    'checked_in': 42,
    'expected': 49,
    'tracked': 54,
  },
  'who_out': {
    'today': [
      {
        'id': 31,
        'name': 'Lina Koh',
        'initials': 'LK',
        'department': 'Fabric',
        'type': null,
        'state': 'approved',
        'part': null,
        'until': '2026-10-23',
        'back_at': null,
      },
    ],
    'next_7': [
      {
        'date': '2026-10-23',
        'people': [
          {
            'id': 14,
            'name': 'Priya Nair',
            'department': 'Marketing',
            'state': 'approved',
          },
        ],
      },
    ],
  },
  'for_you': [],
  'auth_type': 'session',
};

/// The /login and /me employee block; a null key is left out (an older
/// connector).
Map<String, dynamic> _employee({
  int id = 6,
  bool? tracked,
  String? access,
  String? source,
}) => {
  'id': id,
  'name': 'Raymond Tan',
  'attendance_tracked': ?tracked,
  'overview_access': ?access,
  'team_leave_source': ?source,
};

Future<_Session> _signedIn(
  WidgetTester tester,
  Map<String, dynamic> employee,
) async {
  final session = _Session();
  await tester.runAsync(
    () => session.saveLoginResponse({
      'success': true,
      'access_token': 'A',
      'expires_at': '2026-10-13 10:00:00',
      'auth_source': 'omni',
      'user': {'id': 9, 'login': 'a@b.c', 'name': 'A'},
      'employee': employee,
    }),
  );
  return session;
}

/// Sets the SaaS plan features through the session's `saveCompany` seam
/// (T1). A fresh `SessionService` has both on.
Future<void> _plan(
  WidgetTester tester,
  SessionService session, {
  required bool attendance,
  required bool timeOff,
}) async {
  await tester.runAsync(
    () => session.saveCompany(
      saasUrl: 'https://saas.test',
      companyCode: 'ACME',
      clientUrl: 'https://acme.test',
      clientDb: 'acme',
      features: {'attendance': attendance, 'time_off': timeOff},
    ),
  );
}

/// A /me answer arrives (SessionService notifies; HomeRoot re-evaluates).
Future<void> _me(
  WidgetTester tester,
  _Session session,
  Map<String, dynamic> employee,
) async {
  await tester.runAsync(() => session.refreshMeWith(_MeApi(employee)));
  await tester.pumpAndSettle();
}

NotificationRecord _n(
  int id,
  String kind, {
  Map<String, dynamic> payload = const {},
  bool answered = false,
}) => NotificationRecord(
  id: id,
  kind: kind,
  title: 'Notice $id',
  payload: payload,
  answered: answered,
);

/// HomeShell's Home tab: its own Navigator in a Scaffold body, under the
/// session and notification providers; the screens' seams through the
/// HomeRoot builders.
Widget _host(
  SessionService session, {
  required _MyDayApi myDayApi,
  required _OverviewApi overviewApi,
  GlobalKey<HomeRootState>? rootKey,
  GlobalKey<MyDayScreenState>? myDayKey,
  GlobalKey<TeamOverviewScreenState>? overviewKey,
  GlobalKey<NavigatorState>? navKey,
  NotificationService? bell,
}) {
  final myDay = myDayKey ?? GlobalKey<MyDayScreenState>();
  final overview = overviewKey ?? GlobalKey<TeamOverviewScreenState>();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SessionService>.value(value: session),
      ChangeNotifierProvider<NotificationService>.value(
        value: bell ?? _Bell(),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Navigator(
          key: navKey,
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => HomeRoot(
              key: rootKey,
              myDayKey: myDay,
              overviewKey: overview,
              myDayBuilder: (key, header) => MyDayScreen(
                key: key,
                header: header,
                apiBuilder: (_) => myDayApi,
                appBar: AppBar(title: const Text('MY DAY BAR')),
                refreshSession: () async {},
              ),
              overviewBuilder: (key, header, onUnavailable) =>
                  TeamOverviewScreen(
                    key: key,
                    header: header,
                    onUnavailable: onUnavailable,
                    apiBuilder: (_) => overviewApi,
                    appBar: AppBar(title: const Text('OVERVIEW BAR')),
                  ),
            ),
          ),
        ),
      ),
    ),
  );
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Finder _switch() => find.byKey(const ValueKey('home-switch'));

Finder _pill(int i) =>
    find.descendant(of: _switch(), matching: find.byKey(ValueKey('pill-$i')));

/// This employee's Team-overview cache keys (A-L3).
Iterable<String> _cacheKeys(SharedPreferences prefs, SessionService s) =>
    prefs.getKeys().where(
      (k) => k.startsWith('team_v1|${s.clientDb}|${s.employeeId}|'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    // In-memory and static: one test's My day must not paint the next's.
    MyDayMemory.clear();
  });

  group('compatibility matrix (front matter), row by row', () {
    testWidgets('connector ≤ 2.64 (no /me keys): My day; no Team leave row', (
      tester,
    ) async {
      _tall(tester);
      final session = await _signedIn(tester, _employee());
      final myDayApi = _MyDayApi();
      final overviewApi = _OverviewApi();
      await tester.pumpWidget(
        _host(session, myDayApi: myDayApi, overviewApi: overviewApi),
      );
      await tester.pumpAndSettle();
      expect(session.homeView, HomeView.myDay);
      expect(session.teamLeaveEnabled, isFalse);
      expect(find.text('MY DAY BAR'), findsOneWidget);
      expect(_switch(), findsNothing);
      expect(myDayApi.calls, 1);
      expect(overviewApi.calls, 0);
    });

    testWidgets('2.65, grant none: My day; the row follows the setting', (
      tester,
    ) async {
      _tall(tester);
      final session = await _signedIn(
        tester,
        _employee(tracked: true, access: 'none', source: 'department'),
      );
      final overviewApi = _OverviewApi();
      await tester.pumpWidget(
        _host(session, myDayApi: _MyDayApi(), overviewApi: overviewApi),
      );
      await tester.pumpAndSettle();
      expect(session.homeView, HomeView.myDay);
      expect(session.teamLeaveEnabled, isTrue);
      expect(find.text('MY DAY BAR'), findsOneWidget);
      expect(overviewApi.calls, 0);

      final off = await _signedIn(
        tester,
        _employee(tracked: true, access: 'none', source: 'off'),
      );
      expect(off.teamLeaveEnabled, isFalse);
    });

    testWidgets('2.65, grant set, not tracked: Team overview, no switch', (
      tester,
    ) async {
      _tall(tester);
      final session = await _signedIn(
        tester,
        _employee(tracked: false, access: 'company', source: 'department'),
      );
      final myDayApi = _MyDayApi();
      final overviewApi = _OverviewApi();
      await tester.pumpWidget(
        _host(session, myDayApi: myDayApi, overviewApi: overviewApi),
      );
      await tester.pumpAndSettle();
      expect(session.homeView, HomeView.overview);
      expect(session.teamLeaveEnabled, isTrue);
      expect(find.text('OVERVIEW BAR'), findsOneWidget);
      expect(_switch(), findsNothing);
      expect(overviewApi.calls, 1);
      expect(myDayApi.calls, 0);
    });

    testWidgets('2.65, grant set, tracked: the switch, Team overview first', (
      tester,
    ) async {
      _tall(tester);
      final session = await _signedIn(
        tester,
        _employee(tracked: true, access: 'department', source: 'approver'),
      );
      final myDayApi = _MyDayApi();
      await tester.pumpWidget(
        _host(session, myDayApi: myDayApi, overviewApi: _OverviewApi()),
      );
      await tester.pumpAndSettle();
      expect(session.homeView, HomeView.dual);
      expect(find.text('OVERVIEW BAR'), findsOneWidget);
      expect(_switch(), findsOneWidget);
      expect(
        find.descendant(of: _switch(), matching: find.text('Team overview')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _switch(), matching: find.text('My day')),
        findsOneWidget,
      );
      expect(myDayApi.calls, 0);
    });

    testWidgets(
      '2.65, grant set, plan without Attendance: My day with the locked '
      'attendance pane, whatever Time Off and tracking are (A-L24)',
      (tester) async {
        _tall(tester);
        for (final (tracked, timeOff) in const [
          (false, true),
          (true, true),
          (false, false),
          (true, false),
        ]) {
          final session = await _signedIn(
            tester,
            _employee(tracked: tracked, access: 'company', source: 'department'),
          );
          await _plan(tester, session, attendance: false, timeOff: timeOff);
          final myDayApi = _MyDayApi();
          final overviewApi = _OverviewApi(timeOff: timeOff);
          await tester.pumpWidget(
            _host(session, myDayApi: myDayApi, overviewApi: overviewApi),
          );
          await tester.pumpAndSettle();
          final why = 'tracked=$tracked timeOff=$timeOff';
          expect(session.homeView, HomeView.myDay, reason: why);
          expect(session.teamLeaveEnabled, timeOff, reason: why);
          expect(find.text('MY DAY BAR'), findsOneWidget, reason: why);
          expect(find.byType(FeatureLockedPane), findsOneWidget, reason: why);
          expect(_switch(), findsNothing, reason: why);
          expect(overviewApi.calls, 0, reason: why);
          expect(myDayApi.calls, 1, reason: why);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    testWidgets(
      '2.65, grant set, Attendance on, Time Off off: the overview (or the '
      "switch) without Who's out; no Team leave row (A-L24)",
      (tester) async {
        _tall(tester);
        for (final tracked in const [false, true]) {
          final session = await _signedIn(
            tester,
            _employee(tracked: tracked, access: 'company', source: 'department'),
          );
          await _plan(tester, session, attendance: true, timeOff: false);
          final myDayApi = _MyDayApi();
          final overviewApi = _OverviewApi(timeOff: false);
          await tester.pumpWidget(
            _host(session, myDayApi: myDayApi, overviewApi: overviewApi),
          );
          await tester.pumpAndSettle();
          final why = 'tracked=$tracked';
          expect(
            session.homeView,
            tracked ? HomeView.dual : HomeView.overview,
            reason: why,
          );
          expect(session.teamLeaveEnabled, isFalse, reason: why);
          expect(find.text('OVERVIEW BAR'), findsOneWidget, reason: why);
          expect(_switch(), tracked ? findsOneWidget : findsNothing, reason: why);
          expect(find.text('42 checked in'), findsOneWidget, reason: why);
          expect(find.text("Who's out"), findsNothing, reason: why);
          expect(
            find.byKey(const ValueKey('ov-see-outlook')),
            findsNothing,
            reason: why,
          );
          expect(overviewApi.calls, 1, reason: why);
          expect(myDayApi.calls, 0, reason: why);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    testWidgets(
      'overview answers not_allowed (revoked): My day this run, /me '
      're-pulled, cache cleared; a changed grant tries again',
      (tester) async {
        _tall(tester);
        final employee = _employee(
          tracked: false,
          access: 'company',
          source: 'department',
        );
        final session = await _signedIn(tester, employee);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'team_v1|${session.clientDb}|${session.employeeId}'
          '|overview|overview|-|-|day',
          '{}',
        );
        final overviewApi = _OverviewApi()..error = ApiException('not_allowed');
        await tester.pumpWidget(
          _host(session, myDayApi: _MyDayApi(), overviewApi: overviewApi),
        );
        await tester.pumpAndSettle();
        expect(find.text('MY DAY BAR'), findsOneWidget);
        expect(find.text('OVERVIEW BAR'), findsNothing);
        expect(session.refreshes, greaterThanOrEqualTo(1));
        expect(_cacheKeys(prefs, session), isEmpty);

        // /me still grants the same access: My day for the rest of the run.
        overviewApi.error = null;
        await _me(tester, session, employee);
        expect(find.text('MY DAY BAR'), findsOneWidget);
        expect(overviewApi.calls, 1);

        // HR changes the grant: the overview is tried again.
        await _me(
          tester,
          session,
          _employee(tracked: false, access: 'department', source: 'department'),
        );
        expect(find.text('OVERVIEW BAR'), findsOneWidget);
        expect(overviewApi.calls, 2);
      },
    );

    testWidgets('new app + route 404 (tenant rolled back): My day', (
      tester,
    ) async {
      _tall(tester);
      final session = await _signedIn(
        tester,
        _employee(tracked: false, access: 'company', source: 'department'),
      );
      // An older connector's HTML 404 (CLAUDE.md "Old connectors"). The
      // Team leave row's half of this row is Task 6's LeaveScreen test.
      final overviewApi = _OverviewApi()
        ..error = ApiException('server_error', data: {'http_status': 404});
      await tester.pumpWidget(
        _host(session, myDayApi: _MyDayApi(), overviewApi: overviewApi),
      );
      await tester.pumpAndSettle();
      expect(find.text('MY DAY BAR'), findsOneWidget);
      expect(find.text('OVERVIEW BAR'), findsNothing);
    });
  });

  group('the switch', () {
    testWidgets('remembers its choice per employee (A-L4)', (tester) async {
      _tall(tester);
      final session = await _signedIn(
        tester,
        _employee(tracked: true, access: 'company', source: 'department'),
      );
      final overviewApi = _OverviewApi();
      await tester.pumpWidget(
        _host(session, myDayApi: _MyDayApi(), overviewApi: overviewApi),
      );
      await tester.pumpAndSettle();
      await tester.tap(_pill(1));
      await tester.pumpAndSettle();
      expect(find.text('MY DAY BAR'), findsOneWidget);
      expect(_switch(), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(homeModeKey(session), 'home_mode|${session.clientDb}|6');
      expect(prefs.getString(homeModeKey(session)), 'my_day');

      // The next app run opens My day straight away.
      await tester.pumpWidget(const SizedBox.shrink());
      final again = _OverviewApi();
      await tester.pumpWidget(
        _host(session, myDayApi: _MyDayApi(), overviewApi: again),
      );
      await tester.pumpAndSettle();
      expect(find.text('MY DAY BAR'), findsOneWidget);
      expect(again.calls, 0);

      // Another employee on this phone starts on the default.
      await tester.pumpWidget(const SizedBox.shrink());
      final other = await _signedIn(
        tester,
        _employee(id: 7, tracked: true, access: 'company', source: 'department'),
      );
      await tester.pumpWidget(
        _host(other, myDayApi: _MyDayApi(), overviewApi: _OverviewApi()),
      );
      await tester.pumpAndSettle();
      expect(find.text('OVERVIEW BAR'), findsOneWidget);

      // Back to Team overview is remembered too.
      await tester.tap(_pill(1));
      await tester.pumpAndSettle();
      await tester.tap(_pill(0));
      await tester.pumpAndSettle();
      expect(prefs.getString(homeModeKey(other)), 'overview');
    });

    testWidgets("sits above My day's status tile", (tester) async {
      _tall(tester);
      final session = await _signedIn(
        tester,
        _employee(tracked: true, access: 'company', source: 'department'),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(homeModeKey(session), 'my_day');
      await tester.pumpWidget(
        _host(session, myDayApi: _MyDayApi(), overviewApi: _OverviewApi()),
      );
      await tester.pumpAndSettle();
      final switchTop = tester.getTopLeft(_switch()).dy;
      final tileTop = tester
          .getTopLeft(find.byKey(const ValueKey('status-tile')))
          .dy;
      expect(switchTop, lessThan(tileTop));
    });

    testWidgets('P1: flipping back to My day paints the last day at once '
        '(in memory) and refetches; no punch button until the fresh answer', (
      tester,
    ) async {
      _tall(tester);
      final session = await _signedIn(
        tester,
        _employee(tracked: true, access: 'company', source: 'department'),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(homeModeKey(session), 'my_day');
      final myDayApi = _MyDayApi();
      await tester.pumpWidget(
        _host(session, myDayApi: myDayApi, overviewApi: _OverviewApi()),
      );
      await tester.pumpAndSettle();
      expect(myDayApi.calls, 1);
      expect(MyDayMemory.read(session), isNotNull);
      final keysBefore = prefs.getKeys();

      await tester.tap(_pill(0));
      await tester.pumpAndSettle();
      expect(find.text('OVERVIEW BAR'), findsOneWidget);

      myDayApi.gate = Completer<void>();
      await tester.tap(_pill(1));
      await tester.pump();
      expect(find.byKey(const ValueKey('status-tile')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('my-day-memory-progress')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(myDayApi.calls, 2); // refetching
      myDayApi.gate!.complete();
      myDayApi.gate = null;
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('my-day-memory-progress')),
        findsNothing,
      );
      // Nothing new on disk for My day (the overview's own TeamCache entry
      // is the only addition).
      expect(
        prefs.getKeys().difference(keysBefore).where(
          (k) => !k.startsWith('team_v1|'),
        ),
        isEmpty,
      );
    });

    testWidgets('P1: a failed refetch keeps the remembered day under the '
        'stale strip; an access answer drops it', (tester) async {
      _tall(tester);
      final session = await _signedIn(
        tester,
        _employee(tracked: true, access: 'company', source: 'department'),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(homeModeKey(session), 'my_day');
      final myDayApi = _MyDayApi();
      await tester.pumpWidget(
        _host(session, myDayApi: myDayApi, overviewApi: _OverviewApi()),
      );
      await tester.pumpAndSettle();
      await tester.tap(_pill(0));
      await tester.pumpAndSettle();

      myDayApi.error = ApiException('network_error');
      await tester.tap(_pill(1));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('status-tile')), findsOneWidget);
      expect(find.textContaining("Couldn't refresh"), findsOneWidget);
      expect(find.byType(ErrorStateView), findsNothing);

      await tester.tap(_pill(0));
      await tester.pumpAndSettle();
      myDayApi.error = ApiException('no_employee_linked');
      await tester.tap(_pill(1));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('status-tile')), findsNothing);
      expect(find.byType(ErrorStateView), findsOneWidget);
      expect(MyDayMemory.read(session), isNull);
    });

    testWidgets('P1: signing out forgets the remembered day', (tester) async {
      _tall(tester);
      final session = await _signedIn(
        tester,
        _employee(tracked: true, access: 'company', source: 'department'),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(homeModeKey(session), 'my_day');
      await tester.pumpWidget(
        _host(session, myDayApi: _MyDayApi(), overviewApi: _OverviewApi()),
      );
      await tester.pumpAndSettle();
      expect(MyDayMemory.read(session), isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(session.clearSession);
      expect(MyDayMemory.read(session), isNull);
      // A new sign-in of the same employee does not see it either.
      final again = await _signedIn(
        tester,
        _employee(tracked: true, access: 'company', source: 'department'),
      );
      expect(MyDayMemory.read(again), isNull);
    });

    testWidgets('stays while My day fails, so Team overview is one tap away', (
      tester,
    ) async {
      _tall(tester);
      final session = await _signedIn(
        tester,
        _employee(tracked: true, access: 'company', source: 'department'),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(homeModeKey(session), 'my_day');
      final myDayApi = _MyDayApi()..error = ApiException('server_error');
      await tester.pumpWidget(
        _host(session, myDayApi: myDayApi, overviewApi: _OverviewApi()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ErrorStateView), findsOneWidget);
      expect(_switch(), findsOneWidget);
      await tester.tap(_pill(0));
      await tester.pumpAndSettle();
      expect(find.text('OVERVIEW BAR'), findsOneWidget);
    });

    testWidgets('a fallback in dual mode drops the switch', (tester) async {
      _tall(tester);
      final session = await _signedIn(
        tester,
        _employee(tracked: true, access: 'company', source: 'department'),
      );
      final overviewApi = _OverviewApi()..error = ApiException('not_allowed');
      await tester.pumpWidget(
        _host(session, myDayApi: _MyDayApi(), overviewApi: overviewApi),
      );
      await tester.pumpAndSettle();
      expect(find.text('MY DAY BAR'), findsOneWidget);
      expect(_switch(), findsNothing);
    });
  });

  group('refresh and navigation', () {
    testWidgets('a Home tab re-tap refreshes the visible screen only', (
      tester,
    ) async {
      _tall(tester);
      final session = await _signedIn(
        tester,
        _employee(tracked: true, access: 'company', source: 'department'),
      );
      final rootKey = GlobalKey<HomeRootState>();
      final myDayApi = _MyDayApi();
      final overviewApi = _OverviewApi();
      await tester.pumpWidget(
        _host(
          session,
          rootKey: rootKey,
          myDayApi: myDayApi,
          overviewApi: overviewApi,
        ),
      );
      await tester.pumpAndSettle();
      expect(overviewApi.calls, 1);

      // What HomeShell._onTabTap(0) calls.
      unawaited(rootKey.currentState!.refresh());
      await tester.pumpAndSettle();
      expect(overviewApi.calls, 2);
      expect(myDayApi.calls, 0);

      await tester.tap(_pill(1));
      await tester.pumpAndSettle();
      expect(myDayApi.calls, 1);
      unawaited(rootKey.currentState!.refresh());
      await tester.pumpAndSettle();
      expect(myDayApi.calls, 2);
      expect(overviewApi.calls, 2);
    });

    testWidgets(
      'showMyDay (HR updated your attendance, reminders) shows My day for '
      'this visit without changing the remembered choice',
      (tester) async {
        _tall(tester);
        final session = await _signedIn(
          tester,
          _employee(tracked: true, access: 'company', source: 'department'),
        );
        final rootKey = GlobalKey<HomeRootState>();
        final myDayApi = _MyDayApi();
        await tester.pumpWidget(
          _host(
            session,
            rootKey: rootKey,
            myDayApi: myDayApi,
            overviewApi: _OverviewApi(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('OVERVIEW BAR'), findsOneWidget);

        unawaited(rootKey.currentState!.showMyDay());
        await tester.pumpAndSettle();
        expect(find.text('MY DAY BAR'), findsOneWidget);
        expect(_switch(), findsOneWidget);
        expect(myDayApi.calls, greaterThanOrEqualTo(1));
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(homeModeKey(session)), isNull);
      },
    );
  });

  group('notification taps while the overview shows (A-L8)', () {
    testWidgets('the bell handler runs from the overview context', (
      tester,
    ) async {
      _tall(tester);
      final session = await _signedIn(
        tester,
        _employee(tracked: false, access: 'company', source: 'department'),
      );
      final bell = _Bell();
      final myDayKey = GlobalKey<MyDayScreenState>();
      final overviewKey = GlobalKey<TeamOverviewScreenState>();
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        _host(
          session,
          myDayApi: _MyDayApi(),
          overviewApi: _OverviewApi(),
          bell: bell,
          myDayKey: myDayKey,
          overviewKey: overviewKey,
          navKey: navKey,
        ),
      );
      await tester.pumpAndSettle();
      // Before A-L8, HomeShell asked My day for this context: none here.
      expect(myDayKey.currentContext, isNull);
      final ctx = homeTabContext(
        myDayKey: myDayKey,
        overviewKey: overviewKey,
        homeNavKey: navKey,
      );
      expect(ctx, same(overviewKey.currentContext));
      final tapContext = ctx!;

      final taps = <String>[];
      await handleNotificationTap(
        tapContext,
        _n(11, 'leave_approval_requested', payload: const {'leave_id': 148}),
        targets: NotificationTapTargets(
          onApprovalTap: (id) => taps.add('approval:$id'),
        ),
      );
      await tester.pumpAndSettle();
      expect(bell.marked, [11]);
      expect(taps, ['approval:148']);

      // The handler's snackbar finds a messenger from this context.
      await handleNotificationTap(
        tapContext,
        _n(16, 'attendance_query', answered: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('You already answered this question.'), findsOneWidget);
    });

    testWidgets("neither screen mounted: the Home tab navigator's context", (
      tester,
    ) async {
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            key: navKey,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => const SizedBox.shrink(),
            ),
          ),
        ),
      );
      final ctx = homeTabContext(
        myDayKey: GlobalKey<MyDayScreenState>(),
        overviewKey: GlobalKey<TeamOverviewScreenState>(),
        homeNavKey: navKey,
      );
      expect(ctx, same(navKey.currentContext));
      // Pushes from it stay on the tab navigator.
      expect(Navigator.of(ctx!), same(navKey.currentState));
    });
  });
}
