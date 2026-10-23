import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/models/team_outlook.dart';
import 'package:omni_hr/screens/team/team_leave_screen.dart';
import 'package:omni_hr/services/notification_service.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:omni_hr/services/team_cache.dart';
import 'package:omni_hr/widgets/error_state_view.dart';

import 'team_fixture.dart';

const _offline = 'No internet connection. Check your network and try again.';

/// Scriptable API: each fetchTeamOutlook() call takes the next scripted
/// answer (a TeamOutlook, or an Object to throw); the last one repeats.
class _FakeApi extends OmniMobileApi {
  _FakeApi(this.script) : super(baseUrl: '', db: '', token: '');

  final List<Object> script;
  final calls = <Map<String, Object?>>[];

  /// When set, every call waits for it before answering.
  Completer<void>? gate;

  @override
  Future<TeamOutlook> fetchTeamOutlook({
    int days = 30,
    String context = 'team',
    String view = 'team',
    int? departmentId,
  }) async {
    final i = calls.length;
    calls.add({
      'days': days,
      'context': context,
      'view': view,
      'department_id': departmentId,
    });
    final g = gate;
    if (g != null) await g.future;
    final next = script[i < script.length ? i : script.length - 1];
    if (next is TeamOutlook) return next;
    throw next;
  }
}

/// A signed-in employee 7 of db `demo` whose /me re-pulls are counted.
class _Session extends SessionService {
  int refreshes = 0;

  @override
  String get clientDb => 'demo';

  @override
  int get employeeId => 7;

  @override
  String get overviewAccess => 'company';

  @override
  String get teamLeaveSource => 'department';

  @override
  Future<bool> refreshMe() async {
    refreshes++;
    return true;
  }
}

Widget _host(
  _FakeApi api, {
  _Session? session,
  String context = 'team',
  int? departmentId,
  int? initialDays,
  Key? key,
}) => ChangeNotifierProvider<SessionService>.value(
  value: session ?? _Session(),
  child: MaterialApp(
    home: TeamLeaveScreen(
      key: key,
      context: context,
      departmentId: departmentId,
      initialDays: initialDays,
      apiBuilder: (_) => api,
      appBar: AppBar(title: const Text('TEST BAR')),
    ),
  ),
);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

String _key(SessionService s, {String context = 'team', int days = 30}) =>
    TeamCache.outlookKey(s, days: days, context: context);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('happy path: header, range, privacy line, heat map, today', (
    tester,
  ) async {
    _tall(tester);
    // HR turned pending on (off by default, D3): the fixture's leaves
    // include Priya's pending request.
    final api = _FakeApi([outlook(showPending: true)]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    expect(api.calls, [
      {'days': 30, 'context': 'team', 'view': 'team', 'department_id': null},
    ]);
    expect(find.text('Marketing'), findsOneWidget);
    expect(find.text('Your department · 12 people'), findsOneWidget);
    expect(find.text('30 days'), findsOneWidget);
    expect(find.text('90 days'), findsOneWidget);
    expect(
      find.text(
        'Shown as “On leave” — no type or reason · includes pending requests',
      ),
      findsOneWidget,
    );
    expect(find.text('October 2026'), findsOneWidget);
    // Someone is off today, so today is selected.
    expect(find.text('Thu 22 Oct · 2 off'), findsOneWidget);
    expect(find.text('Mei Lin Ong'), findsOneWidget);
    expect(find.text('Thu 22 Oct (morning)'), findsOneWidget);
    expect(find.text('Priya Nair'), findsOneWidget);
    // Priya's request is pending; Mei Lin's is approved.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('team-row-902')),
        matching: find.text('Pending'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('team-row-901')),
        matching: find.text('Pending'),
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('team-strip')), findsNothing);
  });

  testWidgets('pending off (the default, D3, A-L25): "approved leave only"', (
    tester,
  ) async {
    _tall(tester);
    // An answer without the disclosure block reads as off too.
    final body = outlookJson()..remove('disclosure');
    for (final answer in [outlook(), TeamOutlook.fromJson(body)]) {
      await tester.pumpWidget(_host(_FakeApi([answer])));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Shown as “On leave” — no type or reason · approved leave only',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('includes pending requests'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('tapping a day lists who is off, with You and the type sent', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(_host(_FakeApi([outlook()])));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('heat-tap-2026-11-12')));
    await tester.pumpAndSettle();
    expect(find.text('Thu 12 Nov · 1 off'), findsOneWidget);
    final row = find.byKey(const ValueKey('team-row-903'));
    expect(
      find.descendant(of: row, matching: find.text('Alexa Tan')),
      findsOneWidget,
    );
    expect(find.descendant(of: row, matching: find.text('You')), findsOneWidget);
    // The server sent a type for this row only (D4).
    expect(
      find.text('Thu 12 Nov – Fri 13 Nov · 2 days · Annual Leave'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('heat-tap-2026-10-23')));
    await tester.pumpAndSettle();
    expect(find.text('Fri 23 Oct · 0 off'), findsOneWidget);
    expect(find.text('No one off. Tap a shaded day.'), findsOneWidget);
  });

  testWidgets('the selected day names its holiday', (tester) async {
    _tall(tester);
    await tester.pumpWidget(
      _host(
        _FakeApi([
          outlook(
            holidays: const {
              '2026-11-09': {'name': 'Deepavali (observed)', 'everyone': true},
            },
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('heat-tap-2026-11-09')));
    await tester.pumpAndSettle();
    // Mockup order: date · holiday · count.
    expect(find.text('Mon 9 Nov · Deepavali (observed) · 0 off'), findsOneWidget);
  });

  testWidgets('a truncated answer says some rows are not shown', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(_host(_FakeApi([outlook(truncated: true)])));
    await tester.pumpAndSettle();
    expect(find.text('Some rows are not shown.'), findsOneWidget);
    // The counts stay the server's: the day card title is unchanged.
    expect(find.text('Thu 22 Oct · 2 off'), findsOneWidget);
  });

  testWidgets('a complete answer has no truncation line', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_host(_FakeApi([outlook()])));
    await tester.pumpAndSettle();
    expect(find.text('Some rows are not shown.'), findsNothing);
  });

  testWidgets('nobody off today: the busiest day is selected', (tester) async {
    _tall(tester);
    await tester.pumpWidget(
      _host(
        _FakeApi([
          outlook(off: const {'2026-11-12': 1, '2026-11-13': 1}),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Thu 12 Nov · 1 off'), findsOneWidget);
  });

  testWidgets('the range switch refetches and is remembered', (tester) async {
    _tall(tester);
    final api = _FakeApi([outlook(), outlook(days: 60)]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('pill-1')));
    await tester.pumpAndSettle();
    expect(api.calls.last['days'], 60);
    expect(find.text('December 2026'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('team_leave_range|demo|7'), 60);

    // Opening the screen again starts on 60 days.
    final again = _FakeApi([outlook(days: 60)]);
    await tester.pumpWidget(_host(again, key: UniqueKey()));
    await tester.pumpAndSettle();
    expect(again.calls.single['days'], 60);
  });

  testWidgets('initialDays wins over the remembered range', (tester) async {
    SharedPreferences.setMockInitialValues({'team_leave_range|demo|7': 60});
    final api = _FakeApi([outlook(days: 90)]);
    await tester.pumpWidget(_host(api, initialDays: 90));
    await tester.pumpAndSettle();
    expect(api.calls.single['days'], 90);
  });

  testWidgets('view chips show when more than one view is offered', (
    tester,
  ) async {
    _tall(tester);
    final api = _FakeApi([
      outlook(views: const ['team', 'approvees', 'company']),
    ]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    expect(find.text('My team'), findsOneWidget);
    expect(find.text('People you approve'), findsOneWidget);
    expect(find.text('Everyone'), findsOneWidget);

    await tester.tap(find.text('People you approve'));
    await tester.pumpAndSettle();
    expect(api.calls.last['view'], 'approvees');
    expect(api.calls.last['context'], 'team');
  });

  testWidgets('one view: no chips', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_host(_FakeApi([outlook()])));
    await tester.pumpAndSettle();
    expect(find.text('My team'), findsNothing);
  });

  testWidgets('overview context: department chips send department_id', (
    tester,
  ) async {
    _tall(tester);
    final api = _FakeApi([
      outlook(
        context: 'overview',
        team: const {'kind': 'overview', 'label': 'Novaworks', 'size': 60},
        departments: const [
          {'id': 5, 'name': 'Marketing', 'size': 20},
          {'id': 9, 'name': 'Fabric', 'size': 15},
        ],
      ),
    ]);
    await tester.pumpWidget(_host(api, context: 'overview', departmentId: 5));
    await tester.pumpAndSettle();
    expect(api.calls.single, {
      'days': 30,
      'context': 'overview',
      'view': 'team',
      'department_id': 5,
    });
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Fabric'), findsOneWidget);
    // No privacy line outside the team context (either wording).
    expect(find.textContaining('no type or reason'), findsNothing);
    expect(find.textContaining('approved leave only'), findsNothing);

    // A department chip: the header names that department and its size.
    expect(find.text('Marketing · 20 people'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dept-9')));
    await tester.pumpAndSettle();
    expect(api.calls.last['department_id'], 9);
    expect(find.text('Fabric · 15 people'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dept-all')));
    await tester.pumpAndSettle();
    expect(api.calls.last['department_id'], isNull);
    expect(find.text('60 people · 2 departments'), findsOneWidget);
  });

  testWidgets('overview context, nobody off: no "your team" wording', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(
      _host(
        _FakeApi([
          outlook(
            context: 'overview',
            team: const {'kind': 'overview', 'label': 'Novaworks', 'size': 60},
            off: const {},
            leaves: const [],
          ),
        ]),
        context: 'overview',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Everyone's in"), findsOneWidget);
    expect(find.text('No one is off in the next 30 days.'), findsOneWidget);
    expect(find.textContaining('your team'), findsNothing);
  });

  testWidgets('the team context never sends a department', (tester) async {
    final api = _FakeApi([outlook()]);
    await tester.pumpWidget(_host(api, departmentId: 5));
    await tester.pumpAndSettle();
    expect(api.calls.single['department_id'], isNull);
  });

  for (final reason in ['no_department', 'no_approver', 'no_people', 'off']) {
    testWidgets('empty_reason $reason explains itself', (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        _host(_FakeApi([outlook(emptyReason: reason)])),
      );
      await tester.pumpAndSettle();
      expect(find.text('No team to show yet'), findsOneWidget);
      expect(find.text(_emptyText[reason]!), findsOneWidget);
      expect(find.text('October 2026'), findsNothing);
      // No privacy line on the empty card (either wording).
      expect(find.textContaining('no type or reason'), findsNothing);
      expect(find.textContaining('approved leave only'), findsNothing);
    });
  }

  testWidgets('nobody off: "Everyone\'s in" and a wider look', (tester) async {
    _tall(tester);
    final api = _FakeApi([
      outlook(off: const {}, leaves: const []),
      outlook(days: 90, off: const {}, leaves: const []),
    ]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    expect(find.text("Everyone's in"), findsOneWidget);
    expect(
      find.text('No one on your team is off in the next 30 days.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Look 90 days ahead'));
    await tester.pumpAndSettle();
    expect(api.calls.last['days'], 90);
    expect(
      find.text('No one on your team is off in the next 90 days.'),
      findsOneWidget,
    );
    expect(find.text('Look 90 days ahead'), findsNothing);
  });

  testWidgets('offline with a cache: the strip, the time and the cached rows', (
    tester,
  ) async {
    _tall(tester);
    final session = _Session();
    await TeamCache.write(
      session,
      _key(session),
      outlookJson(),
      binding: TeamCache.bind(session),
    );
    final api = _FakeApi([ApiException('network_error')]);
    await tester.pumpWidget(_host(api, session: session));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('team-strip')), findsOneWidget);
    expect(find.text(_offline), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'^Showing what you saw at \d\d:\d\d$')),
      findsOneWidget,
    );
    expect(find.text('Mei Lin Ong'), findsOneWidget);
    expect(find.byType(ErrorStateView), findsNothing);
  });

  testWidgets('a cache under another grant is not shown', (tester) async {
    final session = _Session();
    final other = _OtherGrantSession();
    await TeamCache.write(
      other,
      _key(session),
      outlookJson(),
      binding: TeamCache.bind(other),
    );
    await tester.pumpWidget(
      _host(_FakeApi([ApiException('network_error')]), session: session),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorStateView), findsOneWidget);
    expect(find.text('Mei Lin Ong'), findsNothing);
  });

  testWidgets('a failed pull-down keeps the answer with the strip', (
    tester,
  ) async {
    _tall(tester);
    final api = _FakeApi([outlook(), ApiException('network_error')]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    // RefreshIndicator arms after a quarter of the 4000 px view.
    await tester.drag(find.text('Marketing'), const Offset(0, 1500));
    await tester.pumpAndSettle();
    expect(api.calls.length, 2);
    expect(find.text(_offline), findsOneWidget);
    expect(find.text('Mei Lin Ong'), findsOneWidget);
  });

  testWidgets('first load fails without a cache: error view and Retry', (
    tester,
  ) async {
    final api = _FakeApi([ApiException('network_error'), outlook()]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorStateView), findsOneWidget);
    expect(find.text(_offline), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorStateView), findsNothing);
    expect(find.text('Marketing'), findsOneWidget);
  });

  testWidgets('not_allowed clears the cache, re-pulls /me and says so', (
    tester,
  ) async {
    final session = _Session();
    final key = _key(session);
    await TeamCache.write(
      session,
      key,
      outlookJson(),
      binding: TeamCache.bind(session),
    );
    await tester.pumpWidget(
      _host(_FakeApi([ApiException('not_allowed')]), session: session),
    );
    await tester.pumpAndSettle();
    expect(find.text('You no longer have access to this view.'), findsOneWidget);
    expect(find.text('Mei Lin Ong'), findsNothing);
    expect(session.refreshes, 1);
    expect(await TeamCache.read(session, key), isNull);
  });

  testWidgets('a successful answer is cached for the next open', (
    tester,
  ) async {
    final session = _Session();
    await tester.pumpWidget(_host(_FakeApi([outlook()]), session: session));
    await tester.pumpAndSettle();
    expect(await TeamCache.read(session, _key(session)), isNotNull);
  });

  testWidgets('an answer that lands after a cache clear is neither shown nor '
      'stored; the outlook asks again (A-L21)', (tester) async {
    _tall(tester);
    final session = _Session();
    final api = _FakeApi([
      outlook(team: const {'kind': 'department', 'label': 'Old', 'size': 1}),
      outlook(team: const {'kind': 'department', 'label': 'New', 'size': 1}),
    ])..gate = Completer<void>();
    await tester.pumpWidget(_host(api, session: session));
    await tester.pump();
    await tester.pump();
    expect(api.calls.length, 1);
    // Another screen got not_allowed while this request was on the wire.
    await tester.runAsync(() => TeamCache.clearEmployee(session));
    api.gate!.complete();
    await tester.pumpAndSettle();
    expect(api.calls.length, 2);
    expect(find.text('Old'), findsNothing);
    expect(find.text('New'), findsOneWidget);
    final cached = await tester.runAsync(
      () => TeamCache.read(session, _key(session)),
    );
    expect(TeamOutlook.fromJson(cached!.$1).team?.label, 'New');
  });

  testWidgets('the same employee signs in again while a sign-out waits in '
      'its hook: the old answer, released after the clearing finished, is '
      'neither shown nor stored (A-L21)', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final session = _Session();
    final api = _FakeApi([
      outlook(team: const {'kind': 'department', 'label': 'Old', 'size': 1}),
      ApiException('network_error'),
    ])..gate = Completer<void>();
    await tester.pumpWidget(_host(api, session: session));
    await tester.pump();
    await tester.pump();
    expect(api.calls.length, 1);
    final signature = session.teamCacheSignature;
    final generation = TeamCache.generation;
    // The hook's completer is made inside runAsync: a future of the
    // fake-async zone never completes in the real one.
    await tester.runAsync(() async {
      final hook = Completer<void>();
      session.onSessionClearing = () => hook.future;
      final out = session.clearSession(); // waits in its hook
      await session.saveSession(
        accessToken: 'tok-7-again',
        userId: 107,
        userLogin: 'u7',
        userName: 'U',
        employeeId: 7,
        employeeName: 'Employee 7',
      );
      hook.complete();
      await out; // the wipe is skipped: the sign-in is newer
    });
    // Same employee, same signature, no clear: only the request epoch moved.
    expect(session.teamCacheSignature, signature);
    expect(TeamCache.generation, generation);
    api.gate!.complete(); // the old answer lands now
    await tester.pumpAndSettle();
    expect(api.calls.length, 2); // asked again under the new sign-in
    expect(find.text('Old'), findsNothing);
    expect(find.byType(ErrorStateView), findsOneWidget);
    expect(
      await tester.runAsync(() => TeamCache.read(session, _key(session))),
      isNull,
    );
  });

  group('a shown answer keeps its binding (A-L22)', () {
    testWidgets('a /me that narrows the scope after a successful display, '
        'with nothing on the wire, drops the answer at once; the failed '
        'reload shows no old data', (tester) async {
      _tall(tester);
      final session = _ScopeSession();
      final api = _FakeApi([
        outlook(team: const {'kind': 'department', 'label': 'Old', 'size': 1}),
        ApiException('network_error'),
      ]);
      await tester.pumpWidget(_host(api, session: session));
      await tester.pumpAndSettle();
      expect(find.text('Old'), findsOneWidget);
      expect(api.calls.length, 1); // no request outstanding
      session.changeAccess('team'); // a /me: another signature
      await tester.pump();
      expect(find.text('Old'), findsNothing); // gone in the very next frame
      await tester.pumpAndSettle();
      expect(api.calls.length, 2); // asked again under the new binding
      expect(find.text('Old'), findsNothing);
      expect(find.byKey(const ValueKey('team-strip')), findsNothing);
      expect(find.byType(ErrorStateView), findsOneWidget);
    });

    testWidgets('a failed pull-down after a scope change that did not '
        'notify drops the old answer instead of keeping it under the strip', (
      tester,
    ) async {
      _tall(tester);
      final session = _ScopeSession();
      final api = _FakeApi([
        outlook(team: const {'kind': 'department', 'label': 'Old', 'size': 1}),
        ApiException('network_error'),
      ]);
      await tester.pumpWidget(_host(api, session: session));
      await tester.pumpAndSettle();
      expect(find.text('Old'), findsOneWidget);
      session.changeAccess('team', notify: false);
      // RefreshIndicator arms after a quarter of the 4000 px view.
      await tester.drag(find.text('Old'), const Offset(0, 1500));
      await tester.pumpAndSettle();
      expect(api.calls.length, 2);
      expect(find.text('Old'), findsNothing);
      expect(find.byKey(const ValueKey('team-strip')), findsNothing);
      expect(find.byType(ErrorStateView), findsOneWidget);
    });

    testWidgets('a cache clear elsewhere drops the shown answer and asks '
        'again', (tester) async {
      _tall(tester);
      final session = _Session();
      final api = _FakeApi([
        outlook(team: const {'kind': 'department', 'label': 'Old', 'size': 1}),
        outlook(team: const {'kind': 'department', 'label': 'New', 'size': 1}),
      ]);
      await tester.pumpWidget(_host(api, session: session));
      await tester.pumpAndSettle();
      expect(find.text('Old'), findsOneWidget);
      // Another screen got not_allowed: its clear notifies at once.
      await tester.runAsync(() => TeamCache.clearEmployee(session));
      await tester.pumpAndSettle();
      expect(api.calls.length, 2);
      expect(find.text('Old'), findsNothing);
      expect(find.text('New'), findsOneWidget);
    });
  });

  group('each attempt builds its client from the session of now (A-L22, '
      'TLP3-F01)', () {
    testWidgets('the same employee signs in again during the sign-out hook: '
        'the retry sends the new token; the old answer is neither shown nor '
        'cached', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      _tall(tester);
      final session = _Session(); // employee 7 before and after
      await tester.runAsync(() => _signIn(session, 'tok-A', 7));
      final gate = Completer<void>();
      final log = _TokenLog()..gate = gate;
      await tester.pumpWidget(_tokenHost(session, log));
      await tester.pump();
      await tester.pump();
      expect(log.tokens, ['tok-A']);
      await tester.runAsync(() => _overlappingSignIn(session, 'tok-B', 7));
      gate.complete(); // A's answer lands under B's sign-in
      await tester.pumpAndSettle();
      expect(log.tokens, ['tok-A', 'tok-B']);
      expect(find.text('Team of tok-A'), findsNothing);
      expect(find.text('Team of tok-B'), findsOneWidget);
      final cached = await tester.runAsync(
        () => TeamCache.read(session, _key(session)),
      );
      expect(TeamOutlook.fromJson(cached!.$1).team?.label, 'Team of tok-B');
      expect(await tester.runAsync(_storedTeamBodies), isNot(contains('tok-A')));
    });

    testWidgets('another employee signs in during the sign-out hook: the '
        "retry sends their token; the first account's answer is neither shown "
        'nor cached under the new one', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      _tall(tester);
      final session = _LiveSession(); // the real employee id
      await tester.runAsync(() => _signIn(session, 'tok-A', 7));
      final gate = Completer<void>();
      final log = _TokenLog()..gate = gate;
      await tester.pumpWidget(_tokenHost(session, log));
      await tester.pump();
      await tester.pump();
      expect(log.tokens, ['tok-A']);
      await tester.runAsync(() => _overlappingSignIn(session, 'tok-B', 8));
      expect(session.employeeId, 8);
      gate.complete();
      await tester.pumpAndSettle();
      expect(log.tokens, ['tok-A', 'tok-B']);
      expect(find.text('Team of tok-A'), findsNothing);
      expect(find.text('Team of tok-B'), findsOneWidget);
      final cached = await tester.runAsync(
        () => TeamCache.read(session, _key(session)),
      );
      expect(TeamOutlook.fromJson(cached!.$1).team?.label, 'Team of tok-B');
      expect(await tester.runAsync(_storedTeamBodies), isNot(contains('tok-A')));
    });
  });

  testWidgets('overlapping refreshes share one request', (tester) async {
    final key = GlobalKey<TeamLeaveScreenState>();
    final api = _FakeApi([outlook()])..gate = Completer<void>();
    await tester.pumpWidget(_host(api, key: key));
    await tester.pump();
    await tester.pump();
    expect(api.calls.length, 1);
    unawaited(key.currentState!.refresh());
    unawaited(key.currentState!.refresh());
    api.gate!.complete();
    await tester.pumpAndSettle();
    expect(api.calls.length, 1);
  });

  testWidgets('an answer for an older range is dropped', (tester) async {
    _tall(tester);
    final api = _FakeApi([
      outlook(team: const {'kind': 'department', 'label': 'Old', 'size': 1}),
      outlook(
        days: 60,
        team: const {'kind': 'department', 'label': 'New', 'size': 1},
      ),
    ])..gate = Completer<void>();
    await tester.pumpWidget(_host(api));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pill-1')));
    await tester.pump();
    await tester.pump();
    expect(api.calls.length, 2);
    api.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Old'), findsNothing);
  });

  testWidgets('the app bar says Team leave or Leave outlook', (tester) async {
    for (final (ctx, title) in [
      ('team', 'Team leave'),
      ('overview', 'Leave outlook'),
    ]) {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SessionService>.value(value: _Session()),
            ChangeNotifierProvider<NotificationService>(
              create: (_) => NotificationService(),
            ),
          ],
          child: MaterialApp(
            home: TeamLeaveScreen(
              key: UniqueKey(),
              context: ctx,
              apiBuilder: (_) => _FakeApi([outlook(context: ctx)]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
    }
  });
}

/// The same employee under another grant (another cache signature).
class _OtherGrantSession extends _Session {
  @override
  String get overviewAccess => 'none';
}

/// Employee 7 whose grant a /me can change ([changeAccess]); the grant is
/// part of the fallback cache signature (A-L14).
class _ScopeSession extends _Session {
  String access = 'company';

  @override
  String get overviewAccess => access;

  /// [notify] false: a change the screen is not told about (the A-L22
  /// failed-refresh check must catch it anyway).
  void changeAccess(String next, {bool notify = true}) {
    access = next;
    if (notify) notifyListeners();
  }
}

/// A session whose employee id is the real one (`saveSession` sets it),
/// for the other-employee sign-in.
class _LiveSession extends SessionService {
  @override
  String get clientDb => 'demo';

  @override
  String get overviewAccess => 'company';

  @override
  String get teamLeaveSource => 'department';

  @override
  Future<bool> refreshMe() async => true;
}

/// What the credential-sensitive fakes saw (A-L22): the token of every
/// call, in order. [gate] holds the first call only.
class _TokenLog {
  final tokens = <String>[];
  Completer<void>? gate;
}

/// Built by the screen for each attempt from the session of the moment;
/// answers with the team of the token it was built with, so an answer sent
/// with an old token is recognisable on screen and in the cache.
class _TokenApi extends OmniMobileApi {
  _TokenApi(this.log, String token)
    : super(baseUrl: '', db: '', token: token);

  final _TokenLog log;

  @override
  Future<TeamOutlook> fetchTeamOutlook({
    int days = 30,
    String context = 'team',
    String view = 'team',
    int? departmentId,
  }) async {
    log.tokens.add(token);
    final g = log.gate;
    log.gate = null;
    if (g != null) await g.future;
    return outlook(
      team: {'kind': 'department', 'label': 'Team of $token', 'size': 1},
    );
  }
}

Widget _tokenHost(SessionService session, _TokenLog log) =>
    ChangeNotifierProvider<SessionService>.value(
      value: session,
      child: MaterialApp(
        home: TeamLeaveScreen(
          apiBuilder: (s) => _TokenApi(log, s.token),
          appBar: AppBar(title: const Text('TEST BAR')),
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
/// then skipped (the sign-in is newer). Run inside `runAsync`: the hook's
/// completer must belong to the real zone.
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

/// Every stored TeamCache value, joined (for "no trace of token A").
Future<String> _storedTeamBodies() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs
      .getKeys()
      .where((k) => k.startsWith(TeamCache.prefix))
      .map((k) => prefs.getString(k) ?? '')
      .join('\n');
}

const _emptyText = {
  'no_department':
      'Team leave shows the people in your department. Ask HR to add you to one.',
  'no_approver':
      'Team leave shows the people who share your leave approver. Ask HR to set yours.',
  'no_people': 'No one to show here yet.',
  'off': 'Team leave is turned off for your company.',
};
