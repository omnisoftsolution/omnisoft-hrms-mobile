import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The storage under SharedPreferences, to make a write, read or removal
// fail. It comes with shared_preferences; the app does not list it itself.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:omni_hr/models/team_overview.dart';
import 'package:omni_hr/screens/home/overview/overview_copy.dart';
import 'package:omni_hr/screens/home/overview/overview_drill_screen.dart';
import 'package:omni_hr/screens/home/overview/team_overview_screen.dart';
import 'package:omni_hr/services/notification_service.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:omni_hr/services/team_cache.dart';

const _strip = ValueKey('ov-refresh-strip');

Map<String, dynamic> _json({
  String day = 'today',
  bool attendance = true,
  bool leave = true,
  bool names = true,
  String access = 'company',
  String label = 'Novaworks',
  int? departmentId,
  String? emptyReason,
  bool provisional = false,
  Map<String, dynamic>? counts,
  List<Map<String, dynamic>> forYou = const [],
  bool whoOutTruncated = false,
}) => {
  'success': true,
  'day': day,
  'date': day == 'today' ? '2026-10-22' : '2026-10-21',
  'as_of': '09:12',
  'live': day == 'today',
  'scope': {
    'access': access,
    'label': label,
    'department_id': departmentId,
    'empty_reason': emptyReason,
  },
  'departments': access == 'company'
      ? [
          {'id': 5, 'name': 'Marketing'},
          {'id': 6, 'name': 'Fabric'},
        ]
      : [],
  'sections': {'attendance': attendance, 'leave': leave},
  'names': names,
  'counts': attendance && day == 'today'
      ? (counts ??
            {
              'on_time': 36,
              'late': 6,
              'not_in_yet': 4,
              'no_check_in': 3,
              'on_leave': 4,
              'off_today': 1,
              'checked_in': 42,
              'expected': 49,
              'tracked': 54,
            })
      : null,
  if (day == 'yesterday')
    'reviewed': {
      'date': '2026-10-21',
      'provisional': provisional,
      'counts': {
        'on_time': 43,
        'late': 4,
        'left_early': 2,
        'absent': 1,
        'on_leave': 3,
        'off': 1,
        'worked': 47,
        'expected': 50,
        'tracked': 54,
      },
    },
  'who_out': leave && day == 'today'
      ? {
          'today': [
            {
              'id': 31,
              'name': 'Lina Koh',
              'initials': 'LK',
              'department': 'Fabric',
              'type': 'Annual Leave',
              'state': 'approved',
              'part': null,
              'until': '2026-10-23',
              'back_at': null,
              'tracked': true,
            },
            {
              'id': 32,
              'name': 'Mei Lin Ong',
              'initials': 'MO',
              'department': 'Marketing',
              'type': null,
              'state': 'approved',
              'part': 'morning',
              'until': '2026-10-22',
              'back_at': '13:30',
              'tracked': true,
            },
            {
              'id': 33,
              'name': 'Patricia Wee',
              'initials': 'PW',
              'department': 'Management',
              'type': null,
              'state': 'approved',
              'part': null,
              'until': '2026-10-22',
              'back_at': null,
              'tracked': false,
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
                {
                  'id': 31,
                  'name': 'Lina Koh',
                  'department': 'Fabric',
                  'state': 'pending',
                },
              ],
            },
          ],
          'truncated': whoOutTruncated,
        }
      : null,
  'for_you': forYou,
  'auth_type': 'session',
};

/// Each fetchOverview() call takes the next scripted result (a JSON map,
/// or an Object to throw); the last one repeats.
class _Api extends OmniMobileApi {
  _Api(this.script) : super(baseUrl: '', db: '', token: '');

  final List<Object> script;
  final calls = <String>[];
  Completer<void>? gate;

  @override
  Future<TeamOverview> fetchOverview({
    String day = 'today',
    int? departmentId,
  }) async {
    final i = calls.length < script.length ? calls.length : script.length - 1;
    calls.add('$day/${departmentId ?? '-'}');
    final g = gate;
    if (g != null) await g.future;
    final result = script[i];
    if (result is Map<String, dynamic>) return TeamOverview.fromJson(result);
    throw result;
  }

  /// Task 7's drill-down asks here: an empty page.
  final listed = <String>[];

  @override
  Future<OverviewPage> fetchOverviewList({
    required String bucket,
    int? departmentId,
    int offset = 0,
    int limit = 50,
  }) async {
    listed.add('$bucket/${departmentId ?? '-'}');
    return OverviewPage.fromJson({'bucket': bucket, 'total': 0, 'rows': []});
  }

  /// Task 7's person sheet asks here.
  final people = <int>[];

  @override
  Future<OverviewPerson> fetchOverviewPerson(int employeeId) async {
    people.add(employeeId);
    return OverviewPerson.fromJson({
      'person': {'id': employeeId, 'name': 'Lina Koh', 'initials': 'LK'},
      'today': {'bucket': 'on_leave', 'late_minutes': 0},
      'punches': [],
    });
  }
}

class _Log {
  final leave = <int>[];
  final expense = <int>[];
  final buckets = <String>[];
  final people = <int>[];
  final outlook = <String>[];
  int unavailable = 0;
  int sessionRefreshes = 0;
}

/// A real employee: TeamCache stores nothing for employee id 0 (Task 3).
class _Session extends SessionService {
  @override
  int get employeeId => 6;

  @override
  String get clientDb => 'acme';
}

/// A session that already knows the user approves [count] requests.
class _ApproverSession extends _Session {
  _ApproverSession(this.count);

  final int count;

  @override
  bool get leaveApprovalsEnabled => true;

  @override
  int get leaveApprovalsPendingCount => count;
}

/// Employee 6 whose scope signature a /me can change (A-L22).
class _ScopeSession extends _Session {
  String scope = '1111111111111111';

  @override
  String get teamCacheSignature => scope;

  void changeScope(String next) {
    scope = next;
    notifyListeners();
  }
}

/// What the credential-sensitive fake saw (A-L22); [gate] holds the next
/// call only.
class _TokenLog {
  final tokens = <String>[];
  Completer<void>? gate;
}

/// Built by the screen for each attempt from the session of the moment;
/// the team it answers is named after the token it was built with.
class _TokenApi extends OmniMobileApi {
  _TokenApi(this.log, String token) : super(baseUrl: '', db: '', token: token);

  final _TokenLog log;

  @override
  Future<TeamOverview> fetchOverview({
    String day = 'today',
    int? departmentId,
  }) async {
    log.tokens.add(token);
    final gate = log.gate;
    log.gate = null;
    if (gate != null) await gate.future;
    return TeamOverview.fromJson(_json(label: 'Team of $token'));
  }
}

Widget _tokenHost(SessionService session, _TokenLog log) =>
    ChangeNotifierProvider<SessionService>.value(
      value: session,
      child: MaterialApp(
        home: TeamOverviewScreen(
          apiBuilder: (s) => _TokenApi(log, s.token),
          appBar: AppBar(title: const Text('TEST BAR')),
          refreshSession: () async {},
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

Widget _host(
  _Api api, {
  Key? key,
  SessionService? session,
  _Log? log,
  Widget? header,
  Future<void> Function()? refreshSession,
}) => ChangeNotifierProvider<SessionService>(
  create: (_) => session ?? _Session(),
  child: MaterialApp(
    home: TeamOverviewScreen(
      key: key,
      apiBuilder: (_) => api,
      appBar: AppBar(title: const Text('TEST BAR')),
      header: header,
      onOpenLeave: (id) => log?.leave.add(id),
      onOpenExpense: (id) => log?.expense.add(id),
      onUnavailable: () => log?.unavailable++,
      refreshSession: refreshSession ?? () async => log?.sessionRefreshes++,
      destinationBuilder: (item, expense) =>
          Scaffold(appBar: AppBar(), body: Text('DEST ${item.kind}')),
      outlookBuilder: (ctx, departmentId) {
        log?.outlook.add('$ctx/${departmentId ?? '-'}');
        return Scaffold(appBar: AppBar(), body: const Text('OUTLOOK'));
      },
      onBucketTap: (bucket) => log?.buckets.add(bucket),
      onPersonTap: (id) => log?.people.add(id),
    ),
  ),
);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

InkWell _inkOf(WidgetTester tester, Key key) => tester.widget<InkWell>(
  find.descendant(of: find.byKey(key), matching: find.byType(InkWell)),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('today: team tile, bar, six tiles, Who\'s out, For you', (
    tester,
  ) async {
    _tall(tester);
    final api = _Api([_json()]);
    await tester.pumpWidget(_host(api));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(api.calls, ['today/-']);
    expect(find.text('Today · live'), findsOneWidget);
    expect(find.text('Yesterday · reviewed'), findsOneWidget);
    expect(find.text('42 checked in'), findsOneWidget);
    expect(find.text('of 49 expected · Novaworks today'), findsOneWidget);
    expect(
      find.text(
        'Live · as of 09:12 · not yet reviewed by HR · 54 people tracked',
      ),
      findsOneWidget,
    );
    for (final b in overviewBucketOrder) {
      expect(find.byKey(ValueKey('ov-tile-$b')), findsOneWidget);
    }
    expect(find.text(OverviewCopy.countsOnly), findsNothing);
    expect(find.text("Who's out"), findsOneWidget);
    expect(find.text('everyone in Novaworks'), findsOneWidget);
    expect(find.text('TODAY · 3'), findsOneWidget);
    expect(
      find.text('Fabric · Annual Leave · until Fri 23 Oct'),
      findsOneWidget,
    );
    expect(find.text('Marketing · morning only, back 13:30'), findsOneWidget);
    expect(find.text('Part day'), findsOneWidget);
    expect(find.text('Management · On leave · today'), findsOneWidget);
    expect(find.text('NEXT 7 DAYS'), findsOneWidget);
    // One line per person per run of days (1.34.1), pending as a chip.
    expect(find.text('Priya Nair · Marketing · Fri 23'), findsOneWidget);
    expect(find.text('Lina Koh · Fabric · Fri 23'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ov-next-0')),
        matching: find.text('Pending'),
      ),
      findsOneWidget, // Lina (sorted first by name on the same day)
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ov-next-1')),
        matching: find.text('Pending'),
      ),
      findsNothing,
    );
    expect(find.text('See 30 / 60 / 90 days'), findsOneWidget);
    expect(find.text('For you'), findsOneWidget);
    expect(find.text('Nothing needs your attention.'), findsOneWidget);
  });

  testWidgets('count tiles carry "Late: 6 people" semantics', (tester) async {
    _tall(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(_Api([_json()])));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Late: 6 people'), findsOneWidget);
    expect(find.bySemanticsLabel('Off today: 1 person'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the bar: one segment per non-zero bucket, sized by count', (
    tester,
  ) async {
    _tall(tester);
    final api = _Api([
      _json(
        counts: {
          'on_time': 36,
          'late': 6,
          'not_in_yet': 0,
          'no_check_in': 3,
          'on_leave': 4,
          'off_today': 1,
          'checked_in': 42,
          'expected': 45,
          'tracked': 50,
        },
      ),
    ]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    Expanded seg(String id) =>
        tester.widget<Expanded>(find.byKey(ValueKey('ov-bar-$id')));
    expect(seg('on_time').flex, 36);
    expect(seg('late').flex, 6);
    expect(seg('no_check_in').flex, 3);
    expect(find.byKey(const ValueKey('ov-bar-not_in_yet')), findsNothing);
    final onTime = tester.getSize(find.byKey(const ValueKey('ov-bar-on_time')));
    final late = tester.getSize(find.byKey(const ValueKey('ov-bar-late')));
    expect(onTime.width / late.width, closeTo(6, 0.1));
    expect(find.text('On time 36'), findsOneWidget);
    expect(find.text('Late 6'), findsOneWidget);
    expect(find.text('No check-in 3'), findsOneWidget);
    expect(find.text('Not in yet 0'), findsNothing);
  });

  group('sections', () {
    testWidgets('Time Off off (who_out null): counts, no Who\'s out, no '
        'outlook link (A-L24)', (tester) async {
      _tall(tester);
      // The server's shape (sections.leave false, who_out null), and a
      // who_out null under sections.leave true: Who's out is hidden both
      // ways, and with it the way into the outlook.
      for (final body in [
        _json(leave: false),
        {..._json(), 'who_out': null},
      ]) {
        await tester.pumpWidget(_host(_Api([body])));
        await tester.pumpAndSettle();
        expect(find.text('Today · live'), findsOneWidget);
        expect(find.text('42 checked in'), findsOneWidget);
        expect(find.byKey(const ValueKey('ov-tile-late')), findsOneWidget);
        expect(find.text("Who's out"), findsNothing);
        expect(find.text('NEXT 7 DAYS'), findsNothing);
        expect(find.byKey(const ValueKey('ov-see-outlook')), findsNothing);
        expect(find.text('For you'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('a body without the attendance section (tolerated; '
        'connector 2.65.0 answers feature_unavailable instead, A-L24): no '
        'day switch, no tiles; Who\'s out rows cannot open the person', (
      tester,
    ) async {
      _tall(tester);
      final log = _Log();
      await tester.pumpWidget(
        _host(_Api([_json(attendance: false)]), log: log),
      );
      await tester.pumpAndSettle();
      expect(find.text('Today · live'), findsNothing);
      expect(find.byKey(const ValueKey('ov-today-tile')), findsNothing);
      expect(find.byKey(const ValueKey('ov-tile-late')), findsNothing);
      expect(find.text(OverviewCopy.countsOnly), findsNothing);
      expect(find.text("Who's out"), findsOneWidget);
      expect(
        tester.widget<InkWell>(find.byKey(const ValueKey('ov-out-31'))).onTap,
        isNull,
      );
    });

    testWidgets('Attendance off (Time Off on or off): feature_unavailable '
        'falls back (A-L5, A-L24)', (tester) async {
      _tall(tester);
      final log = _Log();
      await tester.pumpWidget(
        _host(_Api([ApiException('feature_unavailable')]), log: log),
      );
      await tester.pumpAndSettle();
      expect(log.unavailable, 1);
      expect(log.sessionRefreshes, 1);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byKey(const ValueKey('ov-today-tile')), findsNothing);
    });
  });

  testWidgets('counts only (L2): no taps, the lock line, names still shown', (
    tester,
  ) async {
    _tall(tester);
    final log = _Log();
    await tester.pumpWidget(_host(_Api([_json(names: false)]), log: log));
    await tester.pumpAndSettle();
    expect(find.text(OverviewCopy.countsOnly), findsOneWidget);
    expect(_inkOf(tester, const ValueKey('ov-tile-late')).onTap, isNull);
    await tester.tap(find.byKey(const ValueKey('ov-tile-late')));
    expect(log.buckets, isEmpty);
    expect(find.text('Lina Koh'), findsOneWidget);
    expect(
      tester.widget<InkWell>(find.byKey(const ValueKey('ov-out-31'))).onTap,
      isNull,
    );
  });

  testWidgets('names: a tile opens its bucket; only tracked people open', (
    tester,
  ) async {
    _tall(tester);
    final log = _Log();
    await tester.pumpWidget(_host(_Api([_json()]), log: log));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ov-tile-late')));
    expect(log.buckets, ['late']);
    await tester.ensureVisible(find.byKey(const ValueKey('ov-out-31')));
    await tester.tap(find.byKey(const ValueKey('ov-out-31')));
    expect(log.people, [31]);
    expect(
      tester.widget<InkWell>(find.byKey(const ValueKey('ov-out-33'))).onTap,
      isNull,
    );
  });

  testWidgets('without the seams: a tile pushes the drill-down, a tracked '
      'row opens the person sheet (Task 7)', (tester) async {
    _tall(tester);
    final api = _Api([_json()]);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionService>(create: (_) => _Session()),
          // OverviewDrillScreen builds OmniAppBar, which reads the bell.
          ChangeNotifierProvider<NotificationService>(
            create: (_) => NotificationService(),
          ),
        ],
        child: MaterialApp(
          home: TeamOverviewScreen(
            apiBuilder: (_) => api,
            appBar: AppBar(title: const Text('TEST BAR')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ov-tile-late')));
    await tester.pumpAndSettle();
    expect(find.byType(OverviewDrillScreen), findsOneWidget);
    expect(api.listed, ['late/-']);
    Navigator.of(tester.element(find.byType(OverviewDrillScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(OverviewDrillScreen), findsNothing);
    expect(api.calls, ['today/-', 'today/-']); // back refreshes

    await tester.ensureVisible(find.byKey(const ValueKey('ov-out-31')));
    await tester.tap(find.byKey(const ValueKey('ov-out-31')));
    await tester.pumpAndSettle();
    expect(api.people, [31]);
    expect(find.text('Punches today'), findsOneWidget);
  });

  group('Yesterday (D7)', () {
    testWidgets('switching asks day yesterday and shows the reviewed copy', (
      tester,
    ) async {
      _tall(tester);
      final api = _Api([_json(), _json(day: 'yesterday'), _json()]);
      await tester.pumpWidget(_host(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yesterday · reviewed'));
      await tester.pumpAndSettle();
      expect(api.calls, ['today/-', 'yesterday/-']);
      expect(find.text('47 worked'), findsOneWidget);
      expect(
        find.text('of 50 expected · Wed 21 Oct · Novaworks'),
        findsOneWidget,
      );
      expect(find.text(OverviewCopy.reviewedFinal), findsOneWidget);
      expect(find.text('Left early'), findsOneWidget);
      expect(find.text('Absent'), findsOneWidget);
      expect(
        _inkOf(tester, const ValueKey('ov-tile-left_early')).onTap,
        isNull,
      );
      expect(find.text('42 checked in'), findsNothing);
      expect(find.text("Who's out"), findsNothing);

      await tester.tap(find.text('Today · live'));
      await tester.pumpAndSettle();
      expect(api.calls.last, 'today/-');
      expect(find.text('42 checked in'), findsOneWidget);
    });

    testWidgets('provisional: "Still being scored"', (tester) async {
      _tall(tester);
      final api = _Api([_json(), _json(day: 'yesterday', provisional: true)]);
      await tester.pumpWidget(_host(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yesterday · reviewed'));
      await tester.pumpAndSettle();
      expect(find.text(OverviewCopy.reviewedProvisional), findsOneWidget);
      expect(find.text(OverviewCopy.reviewedFinal), findsNothing);
    });
  });

  group('departments', () {
    testWidgets('a chip refetches with department_id; All goes back', (
      tester,
    ) async {
      _tall(tester);
      final api = _Api([
        _json(),
        _json(label: 'Marketing', departmentId: 5),
        _json(),
      ]);
      await tester.pumpWidget(_host(api));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ov-dept-all')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ov-dept-5')));
      await tester.pumpAndSettle();
      expect(api.calls, ['today/-', 'today/5']);
      expect(find.text('of 49 expected · Marketing today'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ov-dept-all')));
      await tester.pumpAndSettle();
      expect(api.calls.last, 'today/-');
    });

    testWidgets('no chips for department access', (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        _host(_Api([_json(access: 'department', label: 'Marketing')])),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ov-dept-all')), findsNothing);
    });

    testWidgets('a department gone since: snackbar, back to All', (
      tester,
    ) async {
      _tall(tester);
      final api = _Api([_json(), ApiException('invalid_department'), _json()]);
      await tester.pumpWidget(_host(api));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ov-dept-5')));
      await tester.pumpAndSettle();
      expect(api.calls, ['today/-', 'today/5', 'today/-']);
      expect(
        find.text("That department isn't available any more."),
        findsOneWidget,
      );
      expect(find.text('42 checked in'), findsOneWidget);
    });
  });

  testWidgets('See 30 / 60 / 90 opens the outlook in the overview context '
      'with the department; back refreshes', (tester) async {
    _tall(tester);
    final log = _Log();
    final api = _Api([_json(), _json(label: 'Marketing', departmentId: 5)]);
    await tester.pumpWidget(_host(api, log: log));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ov-dept-5')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('ov-see-outlook')));
    await tester.tap(find.byKey(const ValueKey('ov-see-outlook')));
    await tester.pumpAndSettle();
    expect(log.outlook, ['overview/5']);
    expect(find.text('OUTLOOK'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(api.calls, ['today/-', 'today/5', 'today/5']);
  });

  group('refresh', () {
    testWidgets('a failed refresh keeps the last answer under the strip', (
      tester,
    ) async {
      _tall(tester);
      final key = GlobalKey<TeamOverviewScreenState>();
      final api = _Api([_json(), ApiException('timeout'), _json()]);
      await tester.pumpWidget(_host(api, key: key));
      await tester.pumpAndSettle();
      await key.currentState!.refresh();
      await tester.pumpAndSettle();
      expect(find.byKey(_strip), findsOneWidget);
      expect(find.textContaining("Couldn't refresh."), findsOneWidget);
      expect(find.text('42 checked in'), findsOneWidget);
      await key.currentState!.refresh();
      await tester.pumpAndSettle();
      expect(find.byKey(_strip), findsNothing);
    });

    testWidgets('offline on open: today\'s cached answer with its time', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(_host(_Api([_json()])));
      await tester.pumpAndSettle(); // a good answer is cached

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_host(_Api([ApiException('network_error')])));
      await tester.pumpAndSettle();
      expect(find.text('42 checked in'), findsOneWidget);
      expect(find.byKey(_strip), findsOneWidget);
      expect(find.textContaining('Showing what you saw at '), findsOneWidget);
    });

    testWidgets('a cached answer never reads as live, even when the stored '
        'body says live (T8-m4)', (tester) async {
      _tall(tester);
      final session = _Session();
      final body = _json();
      expect(body['live'], isTrue);
      await tester.runAsync(
        () => TeamCache.write(
          session,
          TeamCache.overviewKey(session),
          body,
          binding: TeamCache.bind(session),
        ),
      );
      await tester.pumpWidget(
        _host(_Api([ApiException('network_error')]), session: session),
      );
      await tester.pumpAndSettle();
      expect(find.text('42 checked in'), findsOneWidget);
      expect(find.byKey(_strip), findsOneWidget);
      expect(find.textContaining('Live · '), findsNothing);
      expect(find.textContaining('not yet reviewed by HR'), findsNothing);
    });

    testWidgets('the strip names the day of a cache saved before today '
        '(T8-m4)', (tester) async {
      _tall(tester);
      addTearDown(() => TeamCache.clock = DateTime.now);
      final now = DateTime.now();
      final cases = {
        DateTime(now.year, now.month, now.day - 1, 18, 3):
            'Showing what you saw yesterday at 18:03',
        DateTime(now.year, now.month, now.day - 2, 18, 3):
            'Showing what you saw on '
            '${DateFormat('EEE d MMM', 'en_US').format(DateTime(now.year, now.month, now.day - 2))}'
            ' at 18:03',
      };
      for (final MapEntry(key: saved, value: line) in cases.entries) {
        final session = _Session();
        TeamCache.clock = () => saved;
        await tester.runAsync(
          () => TeamCache.write(
            session,
            TeamCache.overviewKey(session),
            _json(),
            binding: TeamCache.bind(session),
          ),
        );
        await tester.pumpWidget(
          _host(
            _Api([ApiException('network_error')]),
            key: UniqueKey(),
            session: session,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining(line), findsOneWidget, reason: line);
        expect(find.textContaining('Showing what you saw at '), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('offline with no cache: the error and Retry', (tester) async {
      _tall(tester);
      final api = _Api([ApiException('network_error'), _json()]);
      await tester.pumpWidget(_host(api));
      await tester.pumpAndSettle();
      expect(
        find.text('No internet connection. Check your network and try again.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('42 checked in'), findsOneWidget);
    });

    testWidgets('pull down and app resume refresh', (tester) async {
      _tall(tester);
      final api = _Api([_json()]);
      await tester.pumpWidget(_host(api));
      await tester.pumpAndSettle();
      await tester.drag(find.text("Who's out"), const Offset(0, 800));
      await tester.pumpAndSettle();
      expect(api.calls.length, 2);

      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(api.calls.length, 3);
    });

    testWidgets('overlapping refreshes share one request', (tester) async {
      _tall(tester);
      final key = GlobalKey<TeamOverviewScreenState>();
      final api = _Api([_json()]);
      await tester.pumpWidget(_host(api, key: key));
      await tester.pumpAndSettle();
      api.gate = Completer<void>();
      final a = key.currentState!.refresh();
      final b = key.currentState!.refresh();
      await tester.pump();
      expect(api.calls.length, 2);
      api.gate!.complete();
      await a;
      await b;
      await tester.pumpAndSettle();
      expect(api.calls.length, 2);
      api.gate = null;
      await key.currentState!.refresh();
      expect(api.calls.length, 3);
    });
  });

  testWidgets("a truncated Who's out says some rows are not shown (A9)", (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(_host(_Api([_json(whoOutTruncated: true)])));
    await tester.pumpAndSettle();
    expect(find.text('Some rows are not shown.'), findsOneWidget);
  });

  testWidgets("a complete Who's out has no truncation line", (tester) async {
    _tall(tester);
    await tester.pumpWidget(_host(_Api([_json()])));
    await tester.pumpAndSettle();
    expect(find.text('Some rows are not shown.'), findsNothing);
  });

  group('lost access', () {
    testWidgets('not_allowed clears the cache, re-pulls /me, falls back', (
      tester,
    ) async {
      _tall(tester);
      final session = _Session();
      final log = _Log();
      final key = GlobalKey<TeamOverviewScreenState>();
      final api = _Api([_json(), ApiException('not_allowed')]);
      await tester.pumpWidget(_host(api, key: key, session: session, log: log));
      await tester.pumpAndSettle();
      final cacheKey = TeamCache.overviewKey(session);
      expect(
        await tester.runAsync(() => TeamCache.read(session, cacheKey)),
        isNotNull,
      );

      await key.currentState!.refresh();
      await tester.pumpAndSettle();
      expect(log.unavailable, 1);
      expect(log.sessionRefreshes, 1);
      expect(
        await tester.runAsync(() => TeamCache.read(session, cacheKey)),
        isNull,
      );
      expect(
        find.text('You no longer have access to this view.'),
        findsOneWidget,
      );
      expect(find.text('42 checked in'), findsNothing);
    });

    testWidgets('lost access falls back at once, without waiting for /me '
        '(A4)', (tester) async {
      _tall(tester);
      final log = _Log();
      final me = Completer<void>(); // a /me on a slow link
      var meStarted = 0;
      await tester.pumpWidget(
        _host(
          _Api([ApiException('not_allowed')]),
          log: log,
          refreshSession: () {
            meStarted++;
            return me.future;
          },
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(meStarted, 1);
      expect(log.unavailable, 1);
      expect(
        find.text('You no longer have access to this view.'),
        findsOneWidget,
      );
      me.complete();
      await tester.pumpAndSettle();
      expect(log.unavailable, 1);
    });

    testWidgets('an answer that lands after a cache clear is neither shown '
        'nor stored; the overview asks again (A-L21)', (tester) async {
      _tall(tester);
      final session = _Session();
      final api = _Api([_json(label: 'Old team'), _json(label: 'New team')])
        ..gate = Completer<void>();
      await tester.pumpWidget(_host(api, session: session));
      await tester.pump();
      expect(api.calls, ['today/-']);
      // Another screen got not_allowed while this request was on the wire.
      await tester.runAsync(() => TeamCache.clearEmployee(session));
      api.gate!.complete();
      await tester.pumpAndSettle();
      expect(api.calls, ['today/-', 'today/-']);
      expect(find.text('of 49 expected · Old team today'), findsNothing);
      expect(find.text('of 49 expected · New team today'), findsOneWidget);
      final cached = await tester.runAsync(
        () => TeamCache.read(session, TeamCache.overviewKey(session)),
      );
      expect(cached!.$1['scope']['label'], 'New team');
    });

    testWidgets('a /me that narrows the scope after a successful display, '
        'with nothing on the wire, drops the overview at once; the failed '
        'reload shows no privileged data (A-L22)', (tester) async {
      _tall(tester);
      final session = _ScopeSession();
      final api = _Api([
        _json(label: 'Old team'),
        ApiException('network_error'),
      ]);
      await tester.pumpWidget(_host(api, session: session));
      await tester.pumpAndSettle();
      expect(find.text('of 49 expected · Old team today'), findsOneWidget);
      expect(find.text('Lina Koh'), findsOneWidget);
      expect(api.calls, ['today/-']); // no request outstanding
      session.changeScope('2222222222222222'); // a /me: another signature
      await tester.pump();
      expect(find.text('of 49 expected · Old team today'), findsNothing);
      await tester.pumpAndSettle();
      expect(api.calls, ['today/-', 'today/-']);
      expect(find.text('of 49 expected · Old team today'), findsNothing);
      expect(find.text('Lina Koh'), findsNothing);
      expect(find.byKey(const ValueKey('ov-dept-5')), findsNothing);
      expect(find.byKey(_strip), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a failed pull-down after a scope change that did not '
        'notify drops the old overview; only a cache entry under the new '
        'scope may take its place (A-L22)', (tester) async {
      _tall(tester);
      final session = _ScopeSession();
      final key = GlobalKey<TeamOverviewScreenState>();
      final api = _Api([
        _json(label: 'Old team'),
        ApiException('network_error'),
      ]);
      await tester.pumpWidget(_host(api, key: key, session: session));
      await tester.pumpAndSettle();
      expect(find.text('of 49 expected · Old team today'), findsOneWidget);
      session.scope = '2222222222222222'; // no notify
      await tester.runAsync(
        () => TeamCache.write(
          session,
          TeamCache.overviewKey(session),
          _json(label: 'Cached team'),
          binding: TeamCache.bind(session),
        ),
      );
      await key.currentState!.refresh();
      await tester.pumpAndSettle();
      expect(api.calls, ['today/-', 'today/-']);
      expect(find.text('of 49 expected · Old team today'), findsNothing);
      expect(find.text('of 49 expected · Cached team today'), findsOneWidget);
      expect(find.byKey(_strip), findsOneWidget);
    });

    testWidgets('the same employee signs in again during the sign-out hook: '
        'the retry sends the new token; the old overview is neither shown '
        'nor cached (A-L22, TLP3-F01)', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      _tall(tester);
      final session = _Session(); // employee 6 before and after
      await tester.runAsync(() => _signIn(session, 'tok-A', 6));
      final gate = Completer<void>();
      final log = _TokenLog()..gate = gate;
      await tester.pumpWidget(_tokenHost(session, log));
      await tester.pump();
      expect(log.tokens, ['tok-A']);
      await tester.runAsync(() => _overlappingSignIn(session, 'tok-B', 6));
      gate.complete(); // A's answer lands under B's sign-in
      await tester.pumpAndSettle();
      expect(log.tokens, ['tok-A', 'tok-B']);
      expect(find.text('of 49 expected · Team of tok-A today'), findsNothing);
      expect(find.text('of 49 expected · Team of tok-B today'), findsOneWidget);
      final cached = await tester.runAsync(
        () => TeamCache.read(session, TeamCache.overviewKey(session)),
      );
      expect(cached!.$1['scope']['label'], 'Team of tok-B');
    });

    testWidgets('an older connector (HTML 404) falls back, cache kept', (
      tester,
    ) async {
      _tall(tester);
      final log = _Log();
      await tester.pumpWidget(
        _host(
          _Api([
            ApiException('server_error', data: {'http_status': 404}),
          ]),
          log: log,
        ),
      );
      await tester.pumpAndSettle();
      expect(log.unavailable, 1);
      expect(log.sessionRefreshes, 0);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  testWidgets('no department (scope empty reason): the explanation card', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(
      _host(_Api([_json(access: 'department', emptyReason: 'no_department')])),
    );
    await tester.pumpAndSettle();
    expect(find.text(OverviewCopy.noDepartment), findsOneWidget);
    expect(find.byKey(const ValueKey('ov-today-tile')), findsNothing);
    expect(find.text('For you'), findsOneWidget);
  });

  testWidgets('For you: the shared tap handling (my_leave, approvals)', (
    tester,
  ) async {
    _tall(tester);
    final log = _Log();
    final api = _Api([
      _json(
        forYou: [
          {
            'kind': 'my_leave',
            'id': 412,
            'type': 'Annual leave',
            'date_from': '2026-10-12',
            'date_to': '2026-10-13',
            'state': 'confirm',
          },
          {
            'kind': 'leave_approvals',
            'count': 2,
            'oldest_at': '2026-10-20 01:00:00',
          },
          {
            'kind': 'yesterday_incomplete',
            'date': '2026-10-21',
            'title': 'Yesterday looks incomplete',
            'attendance_id': 9,
          },
        ],
      ),
    ]);
    await tester.pumpWidget(_host(api, log: log, session: _ApproverSession(2)));
    await tester.pumpAndSettle();
    expect(find.text('Tell HR'), findsNothing); // stays on My day

    await tester.tap(find.textContaining('Annual leave'));
    await tester.pumpAndSettle();
    expect(log.leave, [412]);

    await tester.tap(find.text('2 leave requests to approve'));
    await tester.pumpAndSettle();
    expect(find.text('DEST leave_approvals'), findsOneWidget);
    expect(api.calls.length, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(log.sessionRefreshes, 1);
    expect(api.calls.length, 2);
  });

  testWidgets('the header comes first, also while loading and on errors', (
    tester,
  ) async {
    _tall(tester);
    final api = _Api([_json()])..gate = Completer<void>();
    await tester.pumpWidget(_host(api, header: const Text('SWITCH')));
    await tester.pump();
    expect(find.text('SWITCH'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    api.gate!.complete();
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('SWITCH')).dy,
      lessThan(tester.getTopLeft(find.text('Today · live')).dy),
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      _host(
        _Api([
          ApiException('server_error', data: {'http_status': 404}),
        ]),
        header: const Text('SWITCH'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('SWITCH'), findsOneWidget);
  });

  group('For you is never served from the team cache (A-X2)', () {
    testWidgets('a live fetch shows the cards; the stored body has an empty '
        'for_you, and the decoded answer is not changed', (tester) async {
      _tall(tester);
      final session = _Session();
      final body = _json(forYou: [_myLeave]);
      await tester.pumpWidget(_host(_Api([body]), session: session));
      await tester.pumpAndSettle();
      expect(find.text('For you'), findsOneWidget);
      expect(find.textContaining('Annual leave'), findsOneWidget);
      final cached = await tester.runAsync(
        () => TeamCache.read(session, TeamCache.overviewKey(session)),
      );
      expect(cached, isNotNull);
      expect(cached!.$1['for_you'], isEmpty);
      expect(cached.$1['scope']['label'], 'Novaworks');
      // TeamOverview.raw is this very map: the write built a new one.
      expect(body['for_you'], hasLength(1));
    });

    testWidgets('offline, the cached answer shows no For you section, even '
        'when the stored body carries items', (tester) async {
      _tall(tester);
      final session = _Session();
      // As an earlier build could have stored it.
      await tester.runAsync(
        () => TeamCache.write(
          session,
          TeamCache.overviewKey(session),
          _json(forYou: [_myLeave]),
          binding: TeamCache.bind(session),
        ),
      );
      await tester.pumpWidget(
        _host(_Api([ApiException('network_error')]), session: session),
      );
      await tester.pumpAndSettle();
      expect(find.text('42 checked in'), findsOneWidget);
      expect(find.byKey(_strip), findsOneWidget);
      expect(find.text('For you'), findsNothing);
      expect(find.textContaining('Annual leave'), findsNothing);
      expect(find.text('Nothing needs your attention.'), findsNothing);
    });
  });

  group('holes found in the Task 5-7 reviews', () {
    testWidgets('a switch while the old request is on the wire, then a scope '
        'change: no stuck spinner; the new choice loads under the new scope '
        '(T7-I2)', (tester) async {
      _tall(tester);
      final session = _ScopeSession();
      final key = GlobalKey<TeamOverviewScreenState>();
      final api = _Api([
        _json(),
        _json(label: 'Old pull'),
        _json(label: 'Marketing', departmentId: 5),
      ]);
      await tester.pumpWidget(_host(api, key: key, session: session));
      await tester.pumpAndSettle();
      final held = Completer<void>();
      api.gate = held;
      unawaited(key.currentState!.refresh()); // today/- on the wire
      api.gate = null;
      await tester.tap(find.byKey(const ValueKey('ov-dept-5')));
      await tester.pump();
      session.changeScope('2222222222222222');
      await tester.pump();
      expect(find.text('of 49 expected · Novaworks today'), findsNothing);
      expect(find.byKey(const ValueKey('ov-dept-5')), findsNothing);
      held.complete(); // the old choice's answer lands, stale twice over
      await tester.pumpAndSettle();
      expect(api.calls, ['today/-', 'today/-', 'today/5']);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('of 49 expected · Marketing today'), findsOneWidget);
      expect(find.text('of 49 expected · Old pull today'), findsNothing);
    });

    testWidgets('a shown empty answer also goes when its scope moves, and '
        'is asked again (T7-I1)', (tester) async {
      _tall(tester);
      final session = _ScopeSession();
      final api = _Api([
        _json(emptyReason: 'no_people'),
        _json(label: 'New team'),
      ]);
      await tester.pumpWidget(_host(api, session: session));
      await tester.pumpAndSettle();
      expect(find.text(OverviewCopy.noPeople), findsOneWidget);
      api.gate = Completer<void>();
      session.changeScope('2222222222222222');
      await tester.pump();
      expect(find.text(OverviewCopy.noPeople), findsNothing);
      expect(api.calls, ['today/-', 'today/-']);
      api.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('of 49 expected · New team today'), findsOneWidget);
    });

    testWidgets('a day switch during a refresh: the refresh answer is '
        'dropped and the new day loads (the T7-M1 case; no load-more here)', (
      tester,
    ) async {
      _tall(tester);
      final key = GlobalKey<TeamOverviewScreenState>();
      final api = _Api([
        _json(),
        _json(label: 'Stale'),
        _json(day: 'yesterday'),
      ]);
      await tester.pumpWidget(_host(api, key: key));
      await tester.pumpAndSettle();
      final held = Completer<void>();
      api.gate = held;
      final pull = key.currentState!.refresh();
      api.gate = null;
      await tester.tap(find.text('Yesterday · reviewed'));
      await tester.pump();
      held.complete();
      await pull;
      await tester.pumpAndSettle();
      expect(api.calls, ['today/-', 'today/-', 'yesterday/-']);
      expect(find.text('47 worked'), findsOneWidget);
      expect(find.text('of 49 expected · Stale today'), findsNothing);
      expect(find.byKey(_strip), findsNothing);
    });

    testWidgets('the chips and the day switch stay while a choice loads and '
        'after it fails, so the way back is one tap (T5-M3)', (tester) async {
      _tall(tester);
      final api = _Api([_json(), ApiException('network_error'), _json()]);
      await tester.pumpWidget(_host(api));
      await tester.pumpAndSettle();
      api.gate = Completer<void>();
      await tester.tap(find.text('Yesterday · reviewed'));
      await tester.pump();
      expect(find.byKey(const ValueKey('ov-dept-5')), findsOneWidget);
      expect(find.text('Today · live'), findsOneWidget);
      api.gate!.complete();
      api.gate = null;
      await tester.pumpAndSettle();
      expect(
        find.text('No internet connection. Check your network and try again.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('ov-dept-all')), findsOneWidget);
      expect(find.byKey(const ValueKey('ov-dept-5')), findsOneWidget);
      await tester.tap(find.text('Today · live'));
      await tester.pumpAndSettle();
      expect(api.calls, ['today/-', 'yesterday/-', 'today/-']);
      expect(find.text('42 checked in'), findsOneWidget);
    });

    testWidgets('a cache write that fails: the fresh answer, no strip, no '
        'error (T5-M1)', (tester) async {
      _tall(tester);
      SharedPreferencesStorePlatform.instance = _NoTeamWriteStore();
      await tester.pumpWidget(_host(_Api([_json()])));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('42 checked in'), findsOneWidget);
      expect(find.byKey(_strip), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('offline with unreadable prefs: the error and Retry, no '
        'unhandled error, no endless spinner (T6-M2)', (tester) async {
      _tall(tester);
      final store = _FlakyReadStore()..failReads = true;
      SharedPreferencesStorePlatform.instance = store;
      final session = _Session();
      final api = _Api([ApiException('network_error'), _json()]);
      await tester.pumpWidget(_host(api, session: session));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.text('No internet connection. Check your network and try again.'),
        findsOneWidget,
      );
      store.failReads = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('42 checked in'), findsOneWidget);
    });

    testWidgets('lost access with a cache clear that fails: no unhandled '
        'error, the fallback still runs (T6-M2)', (tester) async {
      _tall(tester);
      SharedPreferencesStorePlatform.instance = _NoTeamRemoveStore();
      final session = _Session();
      await tester.runAsync(
        () => TeamCache.write(
          session,
          TeamCache.overviewKey(session),
          _json(),
          binding: TeamCache.bind(session),
        ),
      );
      final log = _Log();
      await tester.pumpWidget(
        _host(_Api([ApiException('not_allowed')]), session: session, log: log),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(log.unavailable, 1);
      expect(log.sessionRefreshes, 1);
      expect(
        find.text('You no longer have access to this view.'),
        findsOneWidget,
      );
    });

    testWidgets('lost access with a /me re-pull that throws: no unhandled '
        'error, the fallback still runs (T8-m3)', (tester) async {
      _tall(tester);
      final log = _Log();
      var asked = 0;
      await tester.pumpWidget(
        _host(
          _Api([ApiException('not_allowed')]),
          log: log,
          refreshSession: () async {
            asked++;
            throw StateError('me failed');
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(asked, 1);
      expect(log.unavailable, 1);
      expect(
        find.text('You no longer have access to this view.'),
        findsOneWidget,
      );
    });

    testWidgets('a chip tap during a held sign-out sends no request; the end '
        'of the sign-out asks nothing for a signed-out phone (T8-m1)', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({});
      _tall(tester);
      final session = _RealSession();
      await tester.runAsync(() => _signIn(session, 'tok-A', 6));
      final api = _Api([_json(), _json(label: 'Marketing', departmentId: 5)]);
      await tester.pumpWidget(_host(api, session: session));
      await tester.pumpAndSettle();
      expect(api.calls, ['today/-']);
      late Completer<void> hook;
      late Future<void> out;
      await tester.runAsync(() async {
        hook = Completer<void>();
        session.onSessionClearing = () => hook.future;
        out = session.clearSession(); // waits in its hook
        await Future<void>.delayed(Duration.zero);
      });
      expect(session.isClearing, isTrue);
      // The new choice's spinner keeps running: no pumpAndSettle here.
      await tester.tap(find.byKey(const ValueKey('ov-dept-5')));
      await tester.pump();
      await tester.pump();
      expect(api.calls, ['today/-']); // nothing sent with the revoked token
      await tester.runAsync(() async {
        hook.complete();
        await out;
      });
      await tester.pump();
      await tester.pump();
      expect(session.employeeId, 0);
      expect(api.calls, ['today/-']);
      expect(find.text('of 49 expected · Novaworks today'), findsNothing);
    });

    testWidgets('a reload kept pending by a held sign-out runs when a new '
        'sign-in ends it (T8-m1)', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      _tall(tester);
      final session = _RealSession();
      await tester.runAsync(() => _signIn(session, 'tok-A', 6));
      final api = _Api([_json(), _json(label: 'Marketing', departmentId: 5)]);
      await tester.pumpWidget(_host(api, session: session));
      await tester.pumpAndSettle();
      late Completer<void> hook;
      late Future<void> out;
      await tester.runAsync(() async {
        hook = Completer<void>();
        session.onSessionClearing = () => hook.future;
        out = session.clearSession();
        await Future<void>.delayed(Duration.zero);
      });
      await tester.tap(find.byKey(const ValueKey('ov-dept-5')));
      await tester.pump();
      await tester.pump();
      expect(api.calls, ['today/-']);
      await tester.runAsync(() async {
        await _signIn(session, 'tok-B', 6); // newer: the wipe is skipped
        hook.complete();
        await out;
      });
      await tester.pumpAndSettle();
      expect(api.calls, ['today/-', 'today/5']);
      expect(find.text('of 49 expected · Marketing today'), findsOneWidget);
    });
  });
}

/// The real employee id (`saveSession` sets it, a sign-out wipes it).
class _RealSession extends SessionService {
  @override
  String get clientDb => 'acme';
}

/// A For-you `my_leave` row ("Annual leave …").
const _myLeave = <String, dynamic>{
  'kind': 'my_leave',
  'id': 412,
  'type': 'Annual leave',
  'date_from': '2026-10-12',
  'date_to': '2026-10-13',
  'state': 'confirm',
};

/// Storage whose team-cache writes fail (a full disk, a broken prefs file).
class _NoTeamWriteStore extends InMemorySharedPreferencesStore {
  _NoTeamWriteStore() : super.empty();

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      key.startsWith('flutter.${TeamCache.prefix}')
      ? Future<bool>.error(StateError('disk full'))
      : super.setValue(valueType, key, value);
}

/// Storage whose reads fail while [failReads] is set.
class _FlakyReadStore extends InMemorySharedPreferencesStore {
  _FlakyReadStore() : super.empty();

  bool failReads = false;

  @override
  Future<Map<String, Object>> getAll() => failReads
      ? Future<Map<String, Object>>.error(StateError('prefs unreadable'))
      : super.getAll();
}

/// Storage whose team-cache removals fail.
class _NoTeamRemoveStore extends InMemorySharedPreferencesStore {
  _NoTeamRemoveStore() : super.empty();

  @override
  Future<bool> remove(String key) =>
      key.startsWith('flutter.${TeamCache.prefix}')
      ? Future<bool>.error(StateError('prefs broken'))
      : super.remove(key);
}
