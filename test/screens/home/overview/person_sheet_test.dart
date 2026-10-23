import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/models/team_overview.dart';
import 'package:omni_hr/screens/home/overview/person_sheet.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';

class _Session extends SessionService {
  int refreshes = 0;

  @override
  Future<bool> refreshMe() async {
    refreshes++;
    return true;
  }
}

/// Employee 7 whose scope signature a /me can change (A-L22).
class _ScopeSession extends _Session {
  String scope = '1111111111111111';

  @override
  int get employeeId => 7;

  @override
  String get teamCacheSignature => scope;

  void changeScope(String next) {
    scope = next;
    notifyListeners();
  }
}

/// What the credential-sensitive fake saw (A-L22). [gate] holds the next
/// call only; [fail] makes the next call fail with server_error.
class _TokenLog {
  final tokens = <String>[];
  Completer<void>? gate;
  bool fail = false;
}

/// Built by the sheet for each attempt from the session of the moment;
/// the person it answers is named after the token it was built with.
class _TokenApi extends OmniMobileApi {
  _TokenApi(this.log, String token) : super(baseUrl: '', db: '', token: token);

  final _TokenLog log;

  @override
  Future<OverviewPerson> fetchOverviewPerson(int employeeId) async {
    log.tokens.add(token);
    final gate = log.gate;
    log.gate = null;
    if (gate != null) await gate.future;
    if (log.fail) {
      log.fail = false;
      throw ApiException('server_error');
    }
    final body = _person();
    return OverviewPerson.fromJson({
      ...body,
      'person': {
        ...body['person'] as Map<String, dynamic>,
        'name': 'Person of $token',
      },
    });
  }
}

Widget _tokenHost(SessionService session, _TokenLog log) =>
    ChangeNotifierProvider<SessionService>.value(
      value: session,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () => showOverviewPersonSheet(
                  ctx,
                  employeeId: 40,
                  apiFor: (s) => _TokenApi(log, s.token),
                ),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _signIn(SessionService s, String token, int employeeId) =>
    s.saveSession(
      accessToken: token,
      userId: 100 + employeeId,
      userLogin: 'u$employeeId',
      userName: 'U',
      employeeId: employeeId,
      employeeName: 'Employee $employeeId',
    );

/// A sign-out that waits in its hook while [token] signs in; the wipe is
/// then skipped. Run inside `runAsync` (the hook's completer must belong
/// to the real zone).
Future<void> _overlappingSignIn(
  SessionService s,
  String token,
  int employeeId,
) async {
  final hook = Completer<void>();
  s.onSessionClearing = () => hook.future;
  final out = s.clearSession();
  await _signIn(s, token, employeeId);
  hook.complete();
  await out;
}

/// `home/overview/person`: [answer] is a body to parse, or an Object to
/// throw; [next] (when set) replaces it after the first call.
class _FakeApi extends OmniMobileApi {
  _FakeApi(this.answer) : super(baseUrl: '', db: '', token: '');

  Object answer;
  Object? next;
  final ids = <int>[];

  @override
  Future<OverviewPerson> fetchOverviewPerson(int employeeId) async {
    ids.add(employeeId);
    final a = answer;
    if (next != null) answer = next!;
    if (a is Map<String, dynamic>) return OverviewPerson.fromJson(a);
    throw a;
  }
}

/// The contract's example answer, with switches for the variants.
Map<String, dynamic> _person({
  String bucket = 'late',
  int lateMinutes = 28,
  bool shift = true,
  List<Map<String, dynamic>>? punches,
  List<Map<String, dynamic>>? leaveWeek,
  bool timeOffOff = false,
  String calendar = 'Standard 44 hours/week',
  bool you = false,
}) => {
  'success': true,
  'person': {
    'id': 40,
    'name': 'Jason Lee',
    'initials': 'JL',
    'department': 'Marketing',
    'calendar': calendar,
    'you': you,
  },
  'today': {'bucket': bucket, 'late_minutes': lateMinutes, 'note': null},
  'shift': shift
      ? {
          'start': '08:30',
          'end': '17:30',
          'blocks': [
            {'start': '08:30', 'end': '12:30'},
            {'start': '13:30', 'end': '17:30'},
          ],
        }
      : null,
  'punches':
      punches ??
      [
        {
          'at': '08:58',
          'kind': 'check_in',
          'source': 'mobile',
          'kiosk_name': null,
          'location': 'Office',
        },
      ],
  'leave_week': timeOffOff
      ? null
      : (leaveWeek ??
            [
              {
                'date_from': '2026-10-27',
                'date_to': '2026-10-28',
                'from_period': null,
                'to_period': null,
                'hour_from': 0.0,
                'hour_to': 0.0,
                'number_of_days': 2.0,
                'unit': 'day',
                'state': 'approved',
                'type': 'Annual Leave',
              },
            ]),
  'sections': {'attendance': true, 'leave': !timeOffOff},
};

Widget _host(_FakeApi api, {SessionService? session}) =>
    ChangeNotifierProvider<SessionService>.value(
      value: session ?? _Session(),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () => showOverviewPersonSheet(
                  ctx,
                  employeeId: 40,
                  apiFor: (_) => api,
                ),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      ),
    );

/// Tall enough that the whole sheet is on screen (the test font is wide).
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _open(
  WidgetTester tester,
  _FakeApi api, {
  SessionService? session,
}) async {
  _tall(tester);
  await tester.pumpWidget(_host(api, session: session));
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('pure helpers', () {
    test('status per bucket', () {
      expect(personStatusLabel('on_time', 0), 'Checked in · on time');
      expect(personStatusLabel('late', 28), 'Checked in · 28 min late');
      expect(personStatusLabel('late', 75), 'Checked in · 1h 15m late');
      expect(personStatusLabel('late', 0), 'Checked in · late');
      expect(personStatusLabel('not_in_yet', 0), 'Not in yet');
      expect(personStatusLabel('no_check_in', 0), 'No check-in');
      expect(personStatusLabel('on_leave', 0), 'On leave');
      expect(personStatusLabel('off_today', 0), 'Off today');
      expect(personStatusLabel('weird', 0), '—');
    });

    test('source labels (L3)', () {
      expect(punchSourceLabel('mobile', ''), 'Phone');
      expect(punchSourceLabel('kiosk', 'Front door'), 'Kiosk · Front door');
      expect(punchSourceLabel('kiosk', ''), 'Kiosk');
      expect(punchSourceLabel('other', ''), '');
      expect(punchSourceLabel('', ''), '');
    });
  });

  testWidgets('header, Today, Shift, punches, leave and the footer', (
    tester,
  ) async {
    final api = _FakeApi(_person());
    await _open(tester, api);
    expect(api.ids, [40]);
    expect(find.text('Jason Lee'), findsOneWidget);
    expect(find.text('JL'), findsOneWidget);
    expect(find.text('Marketing · Standard 44 hours/week'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Checked in · 28 min late'), findsOneWidget);
    expect(find.text('Shift'), findsOneWidget);
    expect(find.text('08:30 – 17:30'), findsOneWidget);
    expect(find.text('Punches today'), findsOneWidget);
    expect(find.text('08:58'), findsOneWidget);
    expect(find.text('Check in · Phone · Office'), findsOneWidget);
    expect(
      find.text('Leave · Annual Leave · Tue 27 Oct – Wed 28 Oct · 2 days'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Read-only. Fixes and approvals stay in Odoo and in Leave approvals.',
      ),
      findsOneWidget,
    );
    expect(find.text('You'), findsNothing);
  });

  testWidgets('kiosk punches name the kiosk; no location, no source', (
    tester,
  ) async {
    final api = _FakeApi(
      _person(
        bucket: 'on_time',
        lateMinutes: 0,
        punches: [
          {
            'at': '08:02',
            'kind': 'check_in',
            'source': 'kiosk',
            'kiosk_name': 'Front door',
            'location': null,
          },
          {
            'at': '12:31',
            'kind': 'check_out',
            'source': 'other',
            'kiosk_name': null,
            'location': null,
          },
        ],
      ),
    );
    await _open(tester, api);
    expect(find.text('Checked in · on time'), findsOneWidget);
    expect(find.text('Check in · Kiosk · Front door'), findsOneWidget);
    expect(find.text('Check out'), findsOneWidget);
  });

  testWidgets('no shift, no punches, no leave this week, no calendar', (
    tester,
  ) async {
    final api = _FakeApi(
      _person(
        bucket: 'off_today',
        lateMinutes: 0,
        shift: false,
        punches: const [],
        leaveWeek: const [],
        calendar: '',
      ),
    );
    await _open(tester, api);
    expect(find.text('Marketing'), findsOneWidget);
    expect(find.text('Off today'), findsOneWidget);
    expect(find.text('No shift'), findsOneWidget);
    expect(find.text('None yet.'), findsOneWidget);
    expect(find.text('Leave · none in the next 7 days'), findsOneWidget);
  });

  testWidgets('Time Off off (leave_week null): no leave box', (tester) async {
    await _open(tester, _FakeApi(_person(timeOffOff: true)));
    expect(find.byKey(const ValueKey('person-leave')), findsNothing);
    expect(find.textContaining('Leave ·'), findsNothing);
  });

  testWidgets('a pending leave without a type says so (D3, D4)', (
    tester,
  ) async {
    final api = _FakeApi(
      _person(
        leaveWeek: [
          {
            'date_from': '2026-10-22',
            'date_to': '2026-10-22',
            'from_period': null,
            'to_period': null,
            'hour_from': 0.0,
            'hour_to': 0.0,
            'number_of_days': 1.0,
            'unit': 'day',
            'state': 'pending',
            'type': null,
          },
        ],
      ),
    );
    await _open(tester, api);
    expect(find.text('Leave · Thu 22 Oct · pending'), findsOneWidget);
  });

  testWidgets('the viewer sees a You chip on their own sheet', (tester) async {
    await _open(tester, _FakeApi(_person(you: true)));
    expect(find.text('You'), findsOneWidget);
  });

  testWidgets('404: this person is no longer in your view', (tester) async {
    final session = _Session();
    await _open(tester, _FakeApi(ApiException('not_found')), session: session);
    expect(find.text('This person is no longer in your view.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(session.refreshes, 0);
  });

  testWidgets('names_hidden: the reason, /me re-pulled, cache cleared', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'team_v1||0|overview|overview|-|-|day': '{}',
      'team_v1||9|overview|overview|-|-|day': '{}',
    });
    final session = _Session();
    await _open(
      tester,
      _FakeApi(ApiException('names_hidden')),
      session: session,
    );
    expect(
      find.text("Counts only — your company doesn't show names here."),
      findsOneWidget,
    );
    expect(session.refreshes, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('team_v1||0|overview|overview|-|-|day'), isFalse);
    expect(prefs.containsKey('team_v1||9|overview|overview|-|-|day'), isTrue);
  });

  testWidgets('another failure offers Retry, which loads the person', (
    tester,
  ) async {
    final api = _FakeApi(ApiException('server_error'))..next = _person();
    await _open(tester, api);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Checked in · 28 min late'), findsOneWidget);
    expect(api.ids, [40, 40]);
  });

  testWidgets('Close closes the sheet', (tester) async {
    await _open(tester, _FakeApi(_person()));
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Punches today'), findsNothing);
    expect(find.text('OPEN'), findsOneWidget);
  });

  testWidgets('on the root navigator: the sheet covers the bottom bar', (
    tester,
  ) async {
    late BuildContext tabContext;
    final api = _FakeApi(_person());
    await tester.pumpWidget(
      ChangeNotifierProvider<SessionService>.value(
        value: _Session(),
        child: MaterialApp(
          home: Scaffold(
            // Like HomeShell: the tab's own Navigator in the body, the bar
            // outside it.
            body: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (c) {
                  tabContext = c;
                  return const SizedBox.shrink();
                },
              ),
            ),
            bottomNavigationBar: const SizedBox(
              key: ValueKey('nav'),
              height: 80,
            ),
          ),
        ),
      ),
    );
    showOverviewPersonSheet(tabContext, employeeId: 40, apiFor: (_) => api);
    await tester.pumpAndSettle();
    final sheetBottom = tester.getBottomLeft(find.byType(BottomSheet)).dy;
    final navTop = tester.getTopLeft(find.byKey(const ValueKey('nav'))).dy;
    expect(sheetBottom, greaterThan(navTop));
  });

  testWidgets('a /me that changes the scope after the sheet showed, with '
      'nothing on the wire, hides the person at once; the failed reload '
      'shows no old data (A-L22)', (tester) async {
    final session = _ScopeSession();
    final api = _FakeApi(_person())..next = ApiException('network_error');
    await _open(tester, api, session: session);
    expect(find.text('Checked in · 28 min late'), findsOneWidget);
    expect(api.ids, [40]); // no request outstanding
    session.changeScope('2222222222222222');
    await tester.pump();
    expect(find.text('Checked in · 28 min late'), findsNothing);
    await tester.pumpAndSettle();
    expect(api.ids, [40, 40]); // asked again under the new scope
    expect(find.text('Jason Lee'), findsNothing);
    expect(find.text('Checked in · 28 min late'), findsNothing);
    expect(find.byKey(const ValueKey('person-error')), findsOneWidget);
  });

  testWidgets('the same employee signs in again during the sign-out hook: '
      'the reload sends the new token; the old answer is never shown '
      '(A-L22, TLP3-F01)', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    _tall(tester);
    final session = _ScopeSession(); // employee 7 before and after
    await tester.runAsync(() => _signIn(session, 'tok-A', 7));
    final gate = Completer<void>();
    final log = _TokenLog()..gate = gate;
    await tester.pumpWidget(_tokenHost(session, log));
    await tester.tap(find.text('OPEN'));
    await tester.pump();
    await tester.pump();
    expect(log.tokens, ['tok-A']);
    await tester.runAsync(() => _overlappingSignIn(session, 'tok-B', 7));
    gate.complete(); // A's answer lands under B's sign-in
    await tester.pumpAndSettle();
    expect(log.tokens, ['tok-A', 'tok-B']);
    expect(find.text('Person of tok-A'), findsNothing);
    expect(find.text('Person of tok-B'), findsOneWidget);
  });

  testWidgets('Retry after another employee signed in sends their token '
      '(A-L22, TLP3-F01)', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    _tall(tester);
    final session = _Session(); // the real employee id
    await tester.runAsync(() => _signIn(session, 'tok-A', 7));
    final log = _TokenLog()..fail = true;
    await tester.pumpWidget(_tokenHost(session, log));
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    await tester.runAsync(() => _overlappingSignIn(session, 'tok-B', 8));
    expect(session.employeeId, 8);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(log.tokens, ['tok-A', 'tok-B']);
    expect(find.text('Person of tok-B'), findsOneWidget);
  });
}
