import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/models/team_overview.dart';
import 'package:omni_hr/screens/home/overview/overview_drill_screen.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:omni_hr/widgets/error_state_view.dart';

class _Session extends SessionService {
  int refreshes = 0;

  @override
  Future<bool> refreshMe() async {
    refreshes++;
    return true;
  }
}

/// `home/overview/list` answers come from [onList]: a page body, or an
/// Object to throw. A gate per bucket holds that bucket's answers.
class _FakeApi extends OmniMobileApi {
  _FakeApi(this.onList) : super(baseUrl: '', db: '', token: '');

  Object Function(String bucket, int offset) onList;
  final calls = <Map<String, Object?>>[];
  final gates = <String, Completer<void>>{};
  final personIds = <int>[];

  @override
  Future<OverviewPage> fetchOverviewList({
    required String bucket,
    int? departmentId,
    int offset = 0,
    int limit = 50,
  }) async {
    calls.add({
      'bucket': bucket,
      'department_id': departmentId,
      'offset': offset,
      'limit': limit,
    });
    final gate = gates[bucket];
    if (gate != null) await gate.future;
    final answer = onList(bucket, offset);
    if (answer is Map<String, dynamic>) return OverviewPage.fromJson(answer);
    throw answer;
  }

  @override
  Future<OverviewPerson> fetchOverviewPerson(int employeeId) async {
    personIds.add(employeeId);
    return OverviewPerson.fromJson({
      'success': true,
      'person': {
        'id': employeeId,
        'name': 'Jason Lee',
        'initials': 'JL',
        'department': 'Marketing',
        'calendar': 'Standard 44 hours/week',
        'you': false,
      },
      'today': {'bucket': 'late', 'late_minutes': 28, 'note': null},
      'shift': {'start': '08:30', 'end': '17:30', 'blocks': []},
      'punches': [
        {
          'at': '08:58',
          'kind': 'check_in',
          'source': 'mobile',
          'kiosk_name': null,
          'location': null,
        },
      ],
      'leave_week': [],
      'sections': {'attendance': true, 'leave': true},
    });
  }
}

Map<String, dynamic> _page(
  String bucket,
  List<Map<String, dynamic>> rows, {
  int? total,
  int? next,
}) => {
  'success': true,
  'bucket': bucket,
  'total': total ?? rows.length,
  'next_offset': next,
  'rows': rows,
};

/// One row of the contract, every key present; [extra] overrides keys.
Map<String, dynamic> _row(
  int id,
  String name,
  String bucket, {
  Map<String, Object?> extra = const {},
}) => {
  'id': id,
  'name': name,
  'initials': name.split(' ').map((w) => w[0]).take(2).join(),
  'department': 'Marketing',
  'you': false,
  'bucket': bucket,
  'first_in': null,
  'late_minutes': 0,
  'shift': null,
  'minutes_since_start': null,
  'starts_in_min': null,
  'later_today': false,
  'flexible': false,
  'source': null,
  'kiosk_name': null,
  'location': null,
  'note': null,
  'leave': null,
  ...extra,
};

DrillRowText _text(Map<String, dynamic> row) =>
    drillRowText(OverviewRow.fromJson(row), today: DateTime(2026, 10, 22));

OverviewCounts _counts() => OverviewCounts.fromJson({
  'on_time': 36,
  'late': 6,
  'not_in_yet': 4,
  'no_check_in': 3,
  'on_leave': 4,
  'off_today': 1,
  'checked_in': 42,
  'expected': 49,
  'tracked': 54,
});

Widget _host(
  _FakeApi api, {
  String bucket = 'late',
  int? departmentId,
  SessionService? session,
}) => ChangeNotifierProvider<SessionService>.value(
  value: session ?? _Session(),
  child: MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => OverviewDrillScreen(
                  bucket: bucket,
                  counts: _counts(),
                  departmentId: departmentId,
                  scopeLabel: 'Novaworks',
                  apiBuilder: (_) => api,
                  appBar: AppBar(title: const Text('DRILL BAR')),
                ),
              ),
            ),
            child: const Text('OPEN'),
          ),
        ),
      ),
    ),
  ),
);

/// Wide enough for all six chips (the test font draws every glyph 1 em
/// wide), short enough that 50 rows need scrolling.
void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _open(
  WidgetTester tester,
  _FakeApi api, {
  String bucket = 'late',
  int? departmentId,
  SessionService? session,
}) async {
  _wide(tester);
  await tester.pumpWidget(
    _host(api, bucket: bucket, departmentId: departmentId, session: session),
  );
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}

/// Opens the drill without settling: its first request is gated.
Future<void> _openPending(
  WidgetTester tester,
  _FakeApi api, {
  String bucket = 'late',
  SessionService? session,
}) async {
  _wide(tester);
  await tester.pumpWidget(_host(api, bucket: bucket, session: session));
  await tester.tap(find.text('OPEN'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Finder _listScrollable() => find.descendant(
  of: find.byKey(const ValueKey('drill-list')),
  matching: find.byType(Scrollable),
);

Map<String, dynamic> _jason() => _row(
  40,
  'Jason Lee',
  'late',
  extra: {'first_in': '08:58', 'late_minutes': 28, 'source': 'mobile'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('drillRowText', () {
    test('title', () {
      expect(drillTitle('Novaworks'), 'Today · Novaworks');
    });

    test('late: department, Phone, first check-in, minutes late', () {
      final t = _text(_jason());
      expect(t.line, 'Marketing · Phone');
      expect(t.time, '08:58');
      expect(t.chip, '28 min late');
      expect(t.note, '');
    });

    test('late past the hour; kiosk name and location (L3)', () {
      final t = _text(
        _row(
          41,
          'Aisha Rahman',
          'late',
          extra: {
            'first_in': '09:45',
            'late_minutes': 75,
            'source': 'kiosk',
            'kiosk_name': 'Front door',
            'location': 'Warehouse',
          },
        ),
      );
      expect(t.line, 'Marketing · Kiosk · Front door · Warehouse');
      expect(t.chip, '1h 15m late');
    });

    test('on time: no chip; came in on leave is a quiet note', () {
      final t = _text(
        _row(
          42,
          'Wei Ling Teo',
          'on_time',
          extra: {
            'first_in': '08:21',
            'source': 'mobile',
            'note': {'kind': 'came_in_on_leave'},
          },
        ),
      );
      expect(t.line, 'Marketing · Phone');
      expect(t.time, '08:21');
      expect(t.chip, '');
      expect(t.note, 'On leave today · came in anyway');
    });

    test('no department, no source: nothing but what is known', () {
      final t = _text(
        _row(
          43,
          'Ken Ho',
          'on_time',
          extra: {'department': '', 'first_in': '08:10'},
        ),
      );
      expect(t.line, '');
      expect(t.time, '08:10');
    });

    test('not in yet, before the start', () {
      final t = _text(
        _row(
          44,
          'Ravi Kumar',
          'not_in_yet',
          extra: {
            'shift': {'start': '09:30', 'end': '18:30'},
            'starts_in_min': 18,
          },
        ),
      );
      expect(t.line, 'Marketing · Shift 09:30 – 18:30 · starts in 18 min');
      expect(t.time, '09:30');
      expect(t.chip, '');
    });

    test('not in yet, past the start (under 30 min)', () {
      final t = _text(
        _row(
          45,
          'Daryl Ng',
          'not_in_yet',
          extra: {
            'shift': {'start': '08:45', 'end': '17:45'},
            'minutes_since_start': 27,
          },
        ),
      );
      expect(t.line, 'Marketing · Shift 08:45 · no check-in for 27 min');
      expect(t.time, '08:45');
    });

    test('not in yet, leave this morning: back time and the leave note', () {
      final t = _text(
        _row(
          46,
          'Mei Lin Ong',
          'not_in_yet',
          extra: {
            'shift': {'start': '08:30', 'end': '17:30'},
            'note': {'kind': 'part_day_leave'},
            'leave': {
              'type': 'Annual Leave',
              'state': 'approved',
              'part': 'morning',
              'back_at': '13:30',
              'until': null,
            },
          },
        ),
      );
      expect(t.line, 'Marketing · Back 13:30 · leave this morning');
      expect(t.time, '13:30');
      expect(t.note, 'Annual Leave (morning)');
    });

    test('not in yet: flexible hours, later today, a bare shift', () {
      expect(
        _text(
          _row(47, 'Sophia Lim', 'not_in_yet', extra: {'flexible': true}),
        ).line,
        'Marketing · Flexible hours',
      );
      expect(
        _text(
          _row(
            48,
            'Clara Sim',
            'not_in_yet',
            extra: {
              'shift': {'start': '14:00', 'end': '18:00'},
              'later_today': true,
            },
          ),
        ).line,
        'Marketing · Shift 14:00 – 18:00 · later today',
      );
      expect(
        _text(
          _row(
            49,
            'Leon Phua',
            'not_in_yet',
            extra: {
              'shift': {'start': '10:00', 'end': '19:00'},
            },
          ),
        ).line,
        'Marketing · Shift 10:00 – 19:00',
      );
    });

    test('no check-in: minutes since the start, a dash, the chip (D8)', () {
      final t = _text(
        _row(
          50,
          'Hui Min Tan',
          'no_check_in',
          extra: {
            'shift': {'start': '08:30', 'end': '17:30'},
            'minutes_since_start': 42,
          },
        ),
      );
      expect(t.line, 'Marketing · Shift 08:30 – 17:30 · 42 min since start');
      expect(t.time, '—');
      expect(t.chip, 'No check-in');
    });

    test('on leave: the type when sent (D4), until a later day or today', () {
      expect(
        _text(
          _row(
            51,
            'Lina Koh',
            'on_leave',
            extra: {
              'leave': {
                'type': 'Annual Leave',
                'state': 'approved',
                'part': null,
                'back_at': null,
                'until': '2026-10-23',
              },
            },
          ),
        ).line,
        'Marketing · Annual Leave · until Fri 23 Oct',
      );
      expect(
        _text(
          _row(
            52,
            'Joanne Lim',
            'on_leave',
            extra: {
              'leave': {
                'type': null,
                'state': 'approved',
                'part': null,
                'back_at': null,
                'until': '2026-10-22',
              },
            },
          ),
        ).line,
        'Marketing · On leave · today',
      );
      expect(
        _text(_row(53, 'Hafiz Osman', 'on_leave')).line,
        'Marketing · On leave · today',
      );
    });

    test('off today', () {
      final t = _text(_row(54, 'Sarah Chen', 'off_today'));
      expect(t.line, 'Marketing · No shift today');
      expect(t.time, '');
      expect(t.chip, '');
    });
  });

  group('OverviewDrillScreen', () {
    testWidgets('opens on the tapped bucket: hint, rows, exact chip totals', (
      tester,
    ) async {
      final api = _FakeApi(
        (bucket, _) => _page(bucket, [
          _jason(),
          _row(
            41,
            'Marcus Yeo',
            'late',
            extra: {
              'first_in': '08:51',
              'late_minutes': 21,
              'source': 'mobile',
            },
          ),
        ], total: 7),
      );
      await _open(tester, api);
      expect(api.calls, [
        {'bucket': 'late', 'department_id': null, 'offset': 0, 'limit': 50},
      ]);
      expect(
        find.text(
          'Checked in after the grace period of their attendance rule. '
          'Latest first.',
        ),
        findsOneWidget,
      );
      // The open bucket shows the list's exact total; the others the counts.
      expect(find.text('Late · 7'), findsOneWidget);
      expect(find.text('On time · 36'), findsOneWidget);
      expect(find.text('Jason Lee'), findsOneWidget);
      expect(find.text('28 min late'), findsOneWidget);
      expect(find.text('08:58'), findsOneWidget);
      expect(find.text('Marcus Yeo'), findsOneWidget);
    });

    testWidgets('the You chip and the came-in-anyway note', (tester) async {
      final api = _FakeApi(
        (bucket, _) => _page(bucket, [
          _row(
            9,
            'Raymond Tan',
            'on_time',
            extra: {
              'you': true,
              'first_in': '08:12',
              'source': 'mobile',
              'note': {'kind': 'came_in_on_leave'},
            },
          ),
        ]),
      );
      await _open(tester, api, bucket: 'on_time');
      expect(find.text('You'), findsOneWidget);
      expect(find.text('On leave today · came in anyway'), findsOneWidget);
    });

    testWidgets('a chip switches the bucket and reloads from offset 0', (
      tester,
    ) async {
      final api = _FakeApi(
        (bucket, _) => bucket == 'late'
            ? _page('late', [_jason()], total: 6)
            : _page(bucket, [
                _row(
                  50,
                  'Hui Min Tan',
                  'no_check_in',
                  extra: {
                    'shift': {'start': '08:30', 'end': '17:30'},
                    'minutes_since_start': 42,
                  },
                ),
              ], total: 3),
      );
      await _open(tester, api);
      await tester.tap(find.byKey(const ValueKey('drill-chip-no_check_in')));
      await tester.pumpAndSettle();
      expect(api.calls.last, {
        'bucket': 'no_check_in',
        'department_id': null,
        'offset': 0,
        'limit': 50,
      });
      expect(find.text('Jason Lee'), findsNothing);
      expect(find.text('Hui Min Tan'), findsOneWidget);
      expect(find.text('No check-in'), findsOneWidget);
      expect(find.text('No check-in · 3'), findsOneWidget);
      expect(
        find.text(
          'No check-in 30 minutes after their shift started — the same rule '
          'My day uses. It updates the moment they check in.',
        ),
        findsOneWidget,
      );
      // The same chip again does nothing.
      await tester.tap(find.byKey(const ValueKey('drill-chip-no_check_in')));
      await tester.pumpAndSettle();
      expect(api.calls, hasLength(2));
    });

    testWidgets('the department goes with every page', (tester) async {
      final api = _FakeApi((bucket, _) => _page(bucket, [_jason()]));
      await _open(tester, api, departmentId: 5);
      await tester.tap(find.byKey(const ValueKey('drill-chip-on_time')));
      await tester.pumpAndSettle();
      expect(api.calls.map((c) => c['department_id']), [5, 5]);
    });

    testWidgets('scrolling to the end loads the next 50, then stops', (
      tester,
    ) async {
      final first = [
        for (var i = 0; i < 50; i++)
          _row(
            100 + i,
            'Person $i',
            'on_time',
            extra: {'first_in': '08:00', 'source': 'mobile'},
          ),
      ];
      final second = [
        for (var i = 50; i < 60; i++)
          _row(
            100 + i,
            'Person $i',
            'on_time',
            extra: {'first_in': '08:30', 'source': 'mobile'},
          ),
      ];
      final api = _FakeApi(
        (_, offset) => offset == 0
            ? _page('on_time', first, total: 60, next: 50)
            : _page('on_time', second, total: 60),
      );
      await _open(tester, api, bucket: 'on_time');
      expect(api.calls.map((c) => c['offset']), [0]);
      expect(find.text('On time · 60'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Person 49'),
        300,
        scrollable: _listScrollable(),
      );
      await tester.pumpAndSettle();
      expect(api.calls.map((c) => c['offset']), [0, 50]);
      expect(api.calls.last['limit'], 50);
      await tester.scrollUntilVisible(
        find.text('Person 59'),
        300,
        scrollable: _listScrollable(),
      );
      await tester.pumpAndSettle();
      expect(find.text('Person 59'), findsOneWidget);
      expect(api.calls, hasLength(2));
    });

    testWidgets('an answer for the bucket left behind is dropped', (
      tester,
    ) async {
      final api = _FakeApi(
        (bucket, _) => bucket == 'late'
            ? _page('late', [_jason()])
            : _page(bucket, [
                _row(
                  60,
                  'Alexa Tan',
                  'on_time',
                  extra: {'first_in': '08:01', 'source': 'mobile'},
                ),
              ]),
      );
      final gate = Completer<void>();
      api.gates['late'] = gate;
      _wide(tester);
      await tester.pumpWidget(_host(api));
      await tester.tap(find.text('OPEN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('drill-chip-on_time')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Alexa Tan'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Alexa Tan'), findsOneWidget);
      expect(find.text('Jason Lee'), findsNothing);
    });

    testWidgets('an empty bucket says nobody is here', (tester) async {
      final api = _FakeApi((bucket, _) => _page(bucket, const []));
      await _open(tester, api, bucket: 'off_today');
      expect(find.text('Nobody here right now.'), findsOneWidget);
      expect(find.text('Off today · 0'), findsOneWidget);
    });

    testWidgets(
      'names_hidden: back to the overview with the reason; /me re-pulled; '
      'cache cleared',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'team_v1||0|overview|overview|-|-|day': '{}',
          'team_v1||9|overview|overview|-|-|day': '{}',
        });
        final session = _Session();
        final api = _FakeApi((_, _) => ApiException('names_hidden'));
        await _open(tester, api, session: session);
        expect(find.byType(OverviewDrillScreen), findsNothing);
        expect(find.text('OPEN'), findsOneWidget);
        expect(
          find.text("Counts only — your company doesn't show names here."),
          findsOneWidget,
        );
        expect(session.refreshes, 1);
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.containsKey('team_v1||0|overview|overview|-|-|day'),
          isFalse,
        );
        expect(
          prefs.containsKey('team_v1||9|overview|overview|-|-|day'),
          isTrue,
        );
      },
    );

    testWidgets('not_allowed: back with "no longer have access"', (
      tester,
    ) async {
      final session = _Session();
      final api = _FakeApi((_, _) => ApiException('not_allowed'));
      await _open(tester, api, session: session);
      expect(find.byType(OverviewDrillScreen), findsNothing);
      expect(
        find.text('You no longer have access to this view.'),
        findsOneWidget,
      );
      expect(session.refreshes, 1);
    });

    testWidgets('another failure stays with Retry, which loads the rows', (
      tester,
    ) async {
      var n = 0;
      final api = _FakeApi(
        (bucket, _) =>
            n++ == 0 ? ApiException('server_error') : _page(bucket, [_jason()]),
      );
      await _open(tester, api);
      expect(find.byType(ErrorStateView), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Jason Lee'), findsOneWidget);
    });

    testWidgets('a row opens the person sheet', (tester) async {
      final api = _FakeApi((bucket, _) => _page(bucket, [_jason()]));
      await _open(tester, api);
      await tester.tap(find.byKey(const ValueKey('drill-row-40')));
      await tester.pumpAndSettle();
      expect(api.personIds, [40]);
      expect(find.text('Punches today'), findsOneWidget);
      expect(find.text('Checked in · 28 min late'), findsOneWidget);
    });

    testWidgets('a /me that changes the scope after the rows showed, with '
        'nothing on the wire, drops them at once; the failed reload shows no '
        'old rows (A-L22)', (tester) async {
      final session = _ScopeSession();
      var n = 0;
      final api = _FakeApi(
        (bucket, _) => n++ == 0
            ? _page(bucket, [_jason()])
            : ApiException('network_error'),
      );
      await _open(tester, api, session: session);
      expect(find.text('Jason Lee'), findsOneWidget);
      expect(api.calls.length, 1); // no request outstanding
      session.changeScope('2222222222222222');
      await tester.pump();
      expect(find.text('Jason Lee'), findsNothing);
      await tester.pumpAndSettle();
      expect(api.calls.length, 2); // the first page, asked again
      expect(api.calls.last['offset'], 0);
      expect(find.text('Jason Lee'), findsNothing);
      expect(find.byType(ErrorStateView), findsOneWidget);
    });

    testWidgets('a shown empty answer is dropped when its binding moves and '
        'asked again under the new one (A-L22, T7 review I1)', (tester) async {
      final session = _ScopeSession();
      var n = 0;
      final api = _FakeApi(
        (bucket, _) => n++ == 0
            ? _page(bucket, const [])
            : _page(bucket, [_row(60, 'Alexa Tan', 'off_today')]),
      );
      await _open(tester, api, bucket: 'off_today', session: session);
      expect(find.text('Nobody here right now.'), findsOneWidget);
      expect(api.calls.length, 1);
      final gate = Completer<void>();
      api.gates['off_today'] = gate;
      session.changeScope('2222222222222222');
      await tester.pump();
      // The empty answer belonged to the old scope: gone, asking again.
      expect(find.text('Nobody here right now.'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(api.calls.length, 2);
      expect(api.calls.last['offset'], 0);
      // The chip totals are not part of the binding: they stay.
      expect(find.text('Off today · 0'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Alexa Tan'), findsOneWidget);
      expect(find.text('Off today · 1'), findsOneWidget);
    });

    testWidgets('a stale request returning after the rows were dropped does '
        'not leave the spinner stuck (T7 review I2)', (tester) async {
      final session = _ScopeSession();
      final api = _FakeApi(
        (bucket, _) => bucket == 'late'
            ? _page('late', [_jason()])
            : _page(bucket, [
                _row(
                  60,
                  'Alexa Tan',
                  'on_time',
                  extra: {'first_in': '08:01', 'source': 'mobile'},
                ),
              ]),
      );
      final old = Completer<void>();
      api.gates['late'] = old; // the old request stays pending
      await _openPending(tester, api, session: session);
      await tester.tap(find.byKey(const ValueKey('drill-chip-on_time')));
      await tester.pumpAndSettle();
      expect(find.text('Alexa Tan'), findsOneWidget); // the new rows landed
      expect(api.calls.length, 2);
      // The binding moves while the old request is still on the wire.
      session.changeScope('2222222222222222');
      await tester.pumpAndSettle();
      // The rows reloaded without waiting for the stale answer.
      expect(api.calls.map((c) => c['bucket']), ['late', 'on_time', 'on_time']);
      expect(find.text('Alexa Tan'), findsOneWidget);
      // Now the stale answer returns: dropped, nothing changes.
      old.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Alexa Tan'), findsOneWidget);
      expect(find.text('Jason Lee'), findsNothing);
    });

    testWidgets('a stale answer returning after the binding moved lets the '
        'reload run (T7 review I2, the sequence in the brief)', (tester) async {
      final session = _ScopeSession();
      final api = _FakeApi(
        (bucket, _) => bucket == 'late'
            ? _page('late', [_jason()])
            : _page(bucket, [
                _row(
                  60,
                  'Alexa Tan',
                  'on_time',
                  extra: {'first_in': '08:01', 'source': 'mobile'},
                ),
              ]),
      );
      final old = Completer<void>();
      api.gates['late'] = old;
      await _openPending(tester, api, session: session);
      await tester.tap(find.byKey(const ValueKey('drill-chip-on_time')));
      await tester.pumpAndSettle();
      expect(find.text('Alexa Tan'), findsOneWidget);
      // Hold the reload's answer, move the binding, then let the old one go.
      final held = Completer<void>();
      api.gates['on_time'] = held;
      session.changeScope('2222222222222222');
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      old.complete();
      await tester.pump();
      held.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Alexa Tan'), findsOneWidget);
    });

    testWidgets('load-more does nothing while a refresh is in flight; the '
        'old-offset page is never appended (T7 review M1)', (tester) async {
      var firstPages = 0;
      final api = _FakeApi((_, offset) {
        if (offset == 0) {
          // The first answer is the old list; the refresh gets a new one.
          return firstPages++ == 0
              ? _page(
                  'on_time',
                  [
                    for (var i = 0; i < 50; i++)
                      _row(100 + i, 'Person $i', 'on_time'),
                  ],
                  total: 60,
                  next: 50,
                )
              : _page('on_time', [
                  for (var i = 0; i < 50; i++)
                    _row(200 + i, 'Fresh $i', 'on_time'),
                ]);
        }
        return _page('on_time', [
          for (var i = 50; i < 60; i++) _row(100 + i, 'Person $i', 'on_time'),
        ], total: 60);
      });
      await _open(tester, api, bucket: 'on_time');
      expect(api.calls.map((c) => c['offset']), [0]);
      final gate = Completer<void>();
      api.gates['on_time'] = gate;
      // Pull to refresh: the first page is asked again and held.
      unawaited(
        tester
            .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
            .show(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(api.calls.map((c) => c['offset']), [0, 0]);
      // The user reaches the footer meanwhile.
      await tester.drag(_listScrollable(), const Offset(0, -6000));
      await tester.pump();
      await tester.pump();
      expect(api.calls.map((c) => c['offset']), [0, 0]); // no load-more
      gate.complete();
      await tester.pumpAndSettle();
      expect(api.calls.map((c) => c['offset']), [0, 0]);
      expect(find.text('Person 0'), findsNothing);
      final list = tester.widget<ListView>(
        find.byKey(const ValueKey('drill-list')),
      );
      expect(list.semanticChildCount, 50); // the fresh page only, no footer
      await tester.scrollUntilVisible(
        find.text('Fresh 49'),
        300,
        scrollable: _listScrollable(),
      );
      expect(find.text('Fresh 49'), findsOneWidget);
      expect(find.text('Person 50'), findsNothing);
    });

    testWidgets('load-more resumes after a refresh following a failed '
        'load-more', (tester) async {
      var moreAsks = 0;
      final api = _FakeApi((_, offset) {
        if (offset == 0) {
          return _page(
            'on_time',
            [for (var i = 0; i < 50; i++) _row(100 + i, 'Person $i', 'on_time')],
            total: 60,
            next: 50,
          );
        }
        return moreAsks++ == 0
            ? ApiException('network_error')
            : _page('on_time', [
                for (var i = 50; i < 60; i++)
                  _row(100 + i, 'Person $i', 'on_time'),
              ], total: 60);
      });
      await _open(tester, api, bucket: 'on_time');
      // The end of the list asks the next page, which fails.
      await tester.drag(_listScrollable(), const Offset(0, -6000));
      await tester.pumpAndSettle();
      expect(api.calls.map((c) => c['offset']), [0, 50]);
      expect(find.text("Couldn't load more. Try again"), findsOneWidget);
      // A pull to refresh that succeeds, with more pages to come.
      unawaited(
        tester
            .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
            .show(),
      );
      await tester.pumpAndSettle();
      await tester.drag(_listScrollable(), const Offset(0, -6000));
      await tester.pumpAndSettle();
      // The footer is the spinner again, and it asked the next page.
      expect(find.text("Couldn't load more. Try again"), findsNothing);
      expect(api.calls.map((c) => c['offset']), [0, 50, 0, 50]);
      expect(find.text('Person 59'), findsOneWidget);
    });

    testWidgets('another employee signs in during the sign-out hook: the '
        "reload sends their token; the first account's rows are never shown "
        '(A-L22, TLP3-F01)', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      _wide(tester);
      final session = _Session(); // the real employee id
      await tester.runAsync(() => _signIn(session, 'tok-A', 7));
      final gate = Completer<void>();
      final log = _TokenLog()..gate = gate;
      await tester.pumpWidget(_tokenHost(session, log));
      await tester.tap(find.text('OPEN'));
      await tester.pump();
      await tester.pump();
      expect(log.tokens, ['tok-A']);
      await tester.runAsync(() => _overlappingSignIn(session, 'tok-B', 8));
      expect(session.employeeId, 8);
      gate.complete(); // A's page lands under B's sign-in
      await tester.pumpAndSettle();
      expect(log.tokens, ['tok-A', 'tok-B']);
      expect(find.text('Person of tok-A'), findsNothing);
      expect(find.text('Person of tok-B'), findsOneWidget);
    });
  });
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

/// What the credential-sensitive fake saw (A-L22); [gate] holds the next
/// call only.
class _TokenLog {
  final tokens = <String>[];
  Completer<void>? gate;
}

/// Built by the drill for each attempt from the session of the moment;
/// its one row is named after the token it was built with.
class _TokenApi extends OmniMobileApi {
  _TokenApi(this.log, String token) : super(baseUrl: '', db: '', token: token);

  final _TokenLog log;

  @override
  Future<OverviewPage> fetchOverviewList({
    required String bucket,
    int? departmentId,
    int offset = 0,
    int limit = 50,
  }) async {
    log.tokens.add(token);
    final gate = log.gate;
    log.gate = null;
    if (gate != null) await gate.future;
    return OverviewPage.fromJson(
      _page(bucket, [_row(41, 'Person of $token', bucket)]),
    );
  }
}

Widget _tokenHost(SessionService session, _TokenLog log) =>
    ChangeNotifierProvider<SessionService>.value(
      value: session,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => OverviewDrillScreen(
                      bucket: 'late',
                      counts: _counts(),
                      scopeLabel: 'Novaworks',
                      apiBuilder: (s) => _TokenApi(log, s.token),
                      appBar: AppBar(title: const Text('DRILL BAR')),
                    ),
                  ),
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
