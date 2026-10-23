import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The storage under SharedPreferences, to make a write fail. It comes with
// shared_preferences; the app does not list it itself.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:omni_hr/models/approval_item.dart';
import 'package:omni_hr/models/leave_type.dart';
import 'package:omni_hr/models/team_outlook.dart';
import 'package:omni_hr/screens/leave/leave_screen.dart';
import 'package:omni_hr/services/holiday_service.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:omni_hr/services/team_cache.dart';
import 'package:omni_hr/widgets/primary_button.dart';

Map<String, dynamic> _outlookJson({int off = 2, String? emptyReason}) => {
  'success': true,
  'context': 'team',
  'view': 'team',
  'views': ['team'],
  'range': {'from': '2026-10-22', 'to': '2026-11-20', 'days': 30},
  'today': '2026-10-22',
  'team': {
    'kind': 'department',
    'label': 'Marketing',
    'size': 12,
    'department_id': 5,
  },
  'empty_reason': emptyReason,
  // The HR defaults: no type, no colleagues' pending requests (D3, A-L25).
  'disclosure': {'show_type': false, 'show_pending': false},
  'summary': {
    'this_week_off': off,
    'label': 'Marketing',
    'faces': off == 0
        ? []
        : [
            {'id': 12, 'initials': 'MO'},
            {'id': 14, 'initials': 'PN'},
          ],
  },
  'people': [],
  'leaves': [],
  'days': [],
  'holidays': [],
  'truncated': false,
};

Map<String, dynamic> _overlapJson({bool empty = false}) => {
  'success': true,
  'people': empty
      ? []
      : [
          {
            'name': 'Rachel Wong',
            'date_from': '2026-11-12',
            'date_to': '2026-11-12',
            'from_period': null,
            'to_period': null,
            'hour_from': 0.0,
            'hour_to': 0.0,
            'unit': 'day',
            'state': 'approved',
          },
          {
            'name': 'Jason Lee',
            'date_from': '2026-11-12',
            'date_to': '2026-11-12',
            'from_period': 'pm',
            'to_period': 'pm',
            'hour_from': 0.0,
            'hour_to': 0.0,
            'unit': 'half_day',
            'state': 'pending',
          },
        ],
  'more': empty ? 0 : 2,
  'empty_reason': empty ? 'no_department' : null,
};

class _Api extends OmniMobileApi {
  _Api() : super(baseUrl: '', db: '', token: '');

  int outlookCalls = 0;
  int overlapCalls = 0;
  int applies = 0;
  Object? outlookError;
  Object? overlapError;
  Map<String, dynamic> outlook = _outlookJson();
  Map<String, dynamic> overlap = _overlapJson();
  final outlookArgs = <String>[];

  /// One-shot: the next outlook / overlap call waits for it, answering
  /// with the body it read when it started; later calls answer at once.
  Completer<void>? outlookGate;
  Completer<void>? overlapGate;

  @override
  Future<List<ApprovalItem>> getPendingApprovals() async => const [];

  @override
  Future<List<LeaveType>> getLeaveTypes() async => [
    LeaveType.fromJson({
      'id': 74,
      'name': 'Annual Leave',
      'request_unit': 'day',
      'requires_allocation': false,
    }),
  ];

  @override
  Future<TeamOutlook> fetchTeamOutlook({
    int days = 30,
    String context = 'team',
    String view = 'team',
    int? departmentId,
  }) async {
    outlookCalls++;
    outlookArgs.add('$days/$context/$view/${departmentId ?? '-'}');
    final error = outlookError;
    final body = outlook;
    final gate = outlookGate;
    if (gate != null) {
      outlookGate = null;
      await gate.future;
    }
    if (error != null) throw error;
    return TeamOutlook.fromJson(body);
  }

  @override
  Future<TeamOverlap> fetchTeamOverlap(DateTime from, DateTime to) async {
    overlapCalls++;
    final error = overlapError;
    final body = overlap;
    final gate = overlapGate;
    if (gate != null) {
      overlapGate = null;
      await gate.future;
    }
    if (error != null) throw error;
    return TeamOverlap.fromJson(body);
  }

  @override
  Future<Map<String, dynamic>> applyLeave({
    required int holidayStatusId,
    required String dateFrom,
    required String dateTo,
    String reason = '',
    String? dateFromPeriod,
    String? dateToPeriod,
    double? hourFrom,
    double? hourTo,
    Map<String, dynamic>? attachment,
  }) async {
    applies++;
    return {'success': true, 'leave_id': 51, 'state': 'confirm'};
  }
}

/// Team leave on (or off), optionally an approver; counts /me pulls. A
/// real employee id: TeamCache stores nothing for id 0 (Task 3).
class _TeamSession extends SessionService {
  _TeamSession({this.team = true, this.approver = false});

  final bool team;
  final bool approver;
  int meRefreshes = 0;

  /// The cache signature (A-L14); [changeScope] plays a /me that changed it.
  String scope = '1111111111111111';

  @override
  int get employeeId => 6;

  @override
  String get clientDb => 'acme';

  @override
  bool get teamLeaveEnabled => team;

  @override
  bool get leaveApprovalsEnabled => approver;

  @override
  String get teamCacheSignature => scope;

  void changeScope(String next) {
    scope = next;
    notifyListeners();
  }

  @override
  Future<bool> refreshMe() async {
    meRefreshes++;
    return true;
  }
}

/// Storage whose team-cache writes fail (a full disk, a broken prefs file).
class _NoTeamWriteStore extends InMemorySharedPreferencesStore {
  _NoTeamWriteStore() : super.empty();

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      key.startsWith('flutter.${TeamCache.prefix}')
      ? Future<bool>.error(StateError('disk full'))
      : super.setValue(valueType, key, value);
}

/// A test-side write with the binding taken right now.
Future<void> _write(SessionService s, Map<String, dynamic> body) =>
    TeamCache.write(s, _key(s), body, binding: TeamCache.bind(s));

Widget _host(_Api api, SessionService session, {Key? key}) => MultiProvider(
  providers: [
    ChangeNotifierProvider<SessionService>.value(value: session),
    ChangeNotifierProvider<HolidayService>(create: (_) => HolidayService()),
  ],
  child: MaterialApp(
    home: LeaveScreen(
      key: key,
      apiBuilder: (_) => api,
      appBar: AppBar(title: const Text('TEST BAR')),
      teamLeaveBuilder: () => Scaffold(
        appBar: AppBar(),
        body: const Text('OUTLOOK'),
      ),
    ),
  ),
);

String _key(SessionService s) => TeamCache.outlookKey(s, days: 30);

const _tile = ValueKey('team-leave-tile');
const _approvals = ValueKey('leave-approvals-row');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the Team leave tile', () {
    testWidgets('sits under the approvals row, above the leave types', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_Api(), _TeamSession(approver: true)));
      await tester.pumpAndSettle();
      final approvalsY = tester.getTopLeft(find.byKey(_approvals)).dy;
      final tileY = tester.getTopLeft(find.byKey(_tile)).dy;
      final typeY = tester.getTopLeft(find.text('Annual Leave')).dy;
      expect(approvalsY, lessThan(tileY));
      expect(tileY, lessThan(typeY));
      expect(find.text('2 out this week · Marketing'), findsOneWidget);
    });

    testWidgets('without the approvals row it tops the list', (tester) async {
      await tester.pumpWidget(_host(_Api(), _TeamSession()));
      await tester.pumpAndSettle();
      expect(find.byKey(_approvals), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(_tile)).dy,
        lessThan(tester.getTopLeft(find.text('Annual Leave')).dy),
      );
    });

    testWidgets('asks the 30-day team outlook (A-L1) and caches it', (
      tester,
    ) async {
      final api = _Api();
      final session = _TeamSession();
      await tester.pumpWidget(_host(api, session));
      await tester.pumpAndSettle();
      expect(api.outlookArgs, ['30/team/team/-']);
      final cached = await tester.runAsync(
        () => TeamCache.read(session, _key(session)),
      );
      expect(cached, isNotNull);
      expect(TeamOutlook.fromJson(cached!.$1).summary.thisWeekOff, 2);
    });

    testWidgets('a cache write that fails does not touch the tile (M1)', (
      tester,
    ) async {
      SharedPreferencesStorePlatform.instance = _NoTeamWriteStore();
      final api = _Api();
      await tester.pumpWidget(_host(api, _TeamSession()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('2 out this week · Marketing'), findsOneWidget);
      expect(api.outlookCalls, 1);
    });

    testWidgets('team leave off: no tile and no outlook call', (
      tester,
    ) async {
      final api = _Api();
      await tester.pumpWidget(_host(api, _TeamSession(team: false)));
      await tester.pumpAndSettle();
      expect(find.byKey(_tile), findsNothing);
      expect(api.outlookCalls, 0);
    });

    testWidgets('an older connector (HTML 404) hides it; a later answer '
        'brings it back', (tester) async {
      final api = _Api()
        ..outlookError = ApiException(
          'server_error',
          data: {'http_status': 404},
        );
      final key = GlobalKey<LeaveScreenState>();
      await tester.pumpWidget(_host(api, _TeamSession(), key: key));
      await tester.pumpAndSettle();
      expect(find.byKey(_tile), findsNothing);
      expect(find.text('Annual Leave'), findsOneWidget);

      api.outlookError = null;
      await key.currentState!.refresh();
      await tester.pumpAndSettle();
      expect(find.byKey(_tile), findsOneWidget);
    });

    testWidgets('offline: falls back to the cached summary', (tester) async {
      final session = _TeamSession();
      await tester.runAsync(() => _write(session, _outlookJson(off: 3)));
      final api = _Api()..outlookError = ApiException('network_error');
      await tester.pumpWidget(_host(api, session));
      await tester.pumpAndSettle();
      expect(find.text('3 out this week · Marketing'), findsOneWidget);
    });

    testWidgets('an empty team reads "No team to show yet"', (tester) async {
      final api = _Api()
        ..outlook = _outlookJson(off: 0, emptyReason: 'no_department');
      await tester.pumpWidget(_host(api, _TeamSession()));
      await tester.pumpAndSettle();
      expect(find.text('No team to show yet'), findsOneWidget);
    });

    testWidgets('lost access clears the cache, re-pulls /me and hides the '
        'tile (no dead tile, A5)', (tester) async {
      final session = _TeamSession();
      await tester.runAsync(() => _write(session, _outlookJson()));
      final api = _Api()..outlookError = ApiException('not_allowed');
      await tester.pumpWidget(_host(api, session));
      await tester.pumpAndSettle();
      // One /me from opening the tab (refreshMeIfStale), one for the
      // lost access.
      expect(session.meRefreshes, 2);
      final cached = await tester.runAsync(
        () => TeamCache.read(session, _key(session)),
      );
      expect(cached, isNull);
      expect(find.textContaining('out this week'), findsNothing);
      expect(find.byKey(_tile), findsNothing);
      // A session notify that leaves the scope as it was keeps it hidden.
      session.changeScope(session.scope);
      await tester.pumpAndSettle();
      expect(find.byKey(_tile), findsNothing);
      expect(api.outlookCalls, 1);
    });

    testWidgets('after lost access, a /me that changes the scope brings the '
        'tile back and asks again', (tester) async {
      final session = _TeamSession();
      final api = _Api()..outlookError = ApiException('feature_unavailable');
      await tester.pumpWidget(_host(api, session));
      await tester.pumpAndSettle();
      expect(find.byKey(_tile), findsNothing);
      expect(api.outlookCalls, 1);

      api.outlookError = null;
      session.changeScope('2222222222222222');
      await tester.pumpAndSettle();
      expect(api.outlookCalls, 2);
      expect(find.byKey(_tile), findsOneWidget);
      expect(find.text('2 out this week · Marketing'), findsOneWidget);
    });

    testWidgets('after lost access, a pull-down that answers brings the '
        'tile back', (tester) async {
      final session = _TeamSession();
      final api = _Api()..outlookError = ApiException('not_allowed');
      final key = GlobalKey<LeaveScreenState>();
      await tester.pumpWidget(_host(api, session, key: key));
      await tester.pumpAndSettle();
      expect(find.byKey(_tile), findsNothing);
      api.outlookError = null;
      await key.currentState!.refresh();
      await tester.pumpAndSettle();
      expect(find.byKey(_tile), findsOneWidget);
    });

    testWidgets('opens the outlook on the tab navigator; refreshes on return', (
      tester,
    ) async {
      final api = _Api();
      await tester.pumpWidget(_host(api, _TeamSession()));
      await tester.pumpAndSettle();
      expect(api.outlookCalls, 1);
      await tester.tap(find.byKey(_tile));
      await tester.pumpAndSettle();
      expect(find.text('OUTLOOK'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(api.outlookCalls, 2);
    });

    testWidgets('an answer that lands after a cache clear is neither shown '
        'nor stored; the tile asks again (A-L21)', (tester) async {
      final session = _TeamSession();
      final gate = Completer<void>();
      final api = _Api()..outlookGate = gate;
      await tester.pumpWidget(_host(api, session));
      for (var i = 0; i < 10 && api.outlookCalls == 0; i++) {
        await tester.pump();
      }
      expect(api.outlookCalls, 1); // answers off: 2 once released
      // Another screen got not_allowed while this request was on the wire.
      await tester.runAsync(() => TeamCache.clearEmployee(session));
      api.outlook = _outlookJson(off: 4);
      gate.complete();
      await tester.pumpAndSettle();
      expect(api.outlookCalls, 2);
      expect(find.text('2 out this week · Marketing'), findsNothing);
      expect(find.text('4 out this week · Marketing'), findsOneWidget);
      final cached = await tester.runAsync(
        () => TeamCache.read(session, _key(session)),
      );
      expect(TeamOutlook.fromJson(cached!.$1).summary.thisWeekOff, 4);
    });

    testWidgets('a /me that changes the scope after a successful display, '
        'with nothing on the wire, drops the summary at once; the failed '
        'reload shows no stale summary (A-L22)', (tester) async {
      final session = _TeamSession();
      final api = _Api();
      await tester.pumpWidget(_host(api, session));
      await tester.pumpAndSettle();
      expect(find.text('2 out this week · Marketing'), findsOneWidget);
      expect(api.outlookCalls, 1); // no request outstanding
      api.outlookError = ApiException('network_error');
      session.changeScope('2222222222222222');
      await tester.pump();
      expect(find.text('2 out this week · Marketing'), findsNothing);
      await tester.pumpAndSettle();
      expect(api.outlookCalls, 2); // asked again under the new scope
      // The cached summary was saved under the old scope: not shown either.
      expect(find.textContaining('out this week'), findsNothing);
      expect(find.byKey(_tile), findsOneWidget);
    });

    testWidgets('a failed pull-down after a scope change that did not '
        'notify drops the stale summary; only a cache entry under the new '
        'scope may take its place (A-L22)', (tester) async {
      final session = _TeamSession();
      final api = _Api();
      final key = GlobalKey<LeaveScreenState>();
      await tester.pumpWidget(_host(api, session, key: key));
      await tester.pumpAndSettle();
      expect(find.text('2 out this week · Marketing'), findsOneWidget);
      session.scope = '2222222222222222'; // no notify
      await tester.runAsync(() => _write(session, _outlookJson(off: 5)));
      api.outlookError = ApiException('network_error');
      await key.currentState!.refresh();
      await tester.pumpAndSettle();
      expect(api.outlookCalls, 2);
      expect(find.text('2 out this week · Marketing'), findsNothing);
      expect(find.text('5 out this week · Marketing'), findsOneWidget);
    });

    testWidgets('the same employee signs in again during the sign-out hook: '
        'the retry sends the new token; the old summary is neither shown nor '
        'cached (A-L22, TLP3-F01)', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final session = _TeamSession(); // employee 6 before and after
      await tester.runAsync(() => _signIn(session, 'tok-A', 6));
      final gate = Completer<void>();
      final log = _TokenLog()..outlookGate = gate;
      await tester.pumpWidget(_tokenHost(session, log));
      for (var i = 0; i < 10 && log.outlookTokens.isEmpty; i++) {
        await tester.pump();
      }
      expect(log.outlookTokens, ['tok-A']);
      await tester.runAsync(() => _overlappingSignIn(session, 'tok-B', 6));
      gate.complete(); // A's answer lands under B's sign-in
      await tester.pumpAndSettle();
      expect(log.outlookTokens, ['tok-A', 'tok-B']);
      expect(find.text('2 out this week · Team of tok-A'), findsNothing);
      expect(find.text('2 out this week · Team of tok-B'), findsOneWidget);
      final cached = await tester.runAsync(
        () => TeamCache.read(session, _key(session)),
      );
      expect(TeamOutlook.fromJson(cached!.$1).summary.label, 'Team of tok-B');
      expect(await tester.runAsync(_storedTeamBodies), isNot(contains('tok-A')));
    });

    testWidgets('another employee signs in during the sign-out hook: the '
        "retry sends their token; the first account's summary is neither "
        'shown nor cached under the new one (A-L22, TLP3-F01)', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final session = _LiveTeamSession(); // the real employee id
      await tester.runAsync(() => _signIn(session, 'tok-A', 6));
      final gate = Completer<void>();
      final log = _TokenLog()..outlookGate = gate;
      await tester.pumpWidget(_tokenHost(session, log));
      for (var i = 0; i < 10 && log.outlookTokens.isEmpty; i++) {
        await tester.pump();
      }
      expect(log.outlookTokens, ['tok-A']);
      await tester.runAsync(() => _overlappingSignIn(session, 'tok-B', 9));
      expect(session.employeeId, 9);
      gate.complete();
      await tester.pumpAndSettle();
      expect(log.outlookTokens, ['tok-A', 'tok-B']);
      expect(find.text('2 out this week · Team of tok-A'), findsNothing);
      expect(find.text('2 out this week · Team of tok-B'), findsOneWidget);
      final cached = await tester.runAsync(
        () => TeamCache.read(session, _key(session)),
      );
      expect(TeamOutlook.fromJson(cached!.$1).summary.label, 'Team of tok-B');
      expect(await tester.runAsync(_storedTeamBodies), isNot(contains('tok-A')));
    });
  });

  group('the apply sheet\'s "Also off" line', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.text('Annual Leave'));
      await tester.pump(); // the sheet's first frame starts the debounce
    }

    /// The sheet's entry animation (250 ms) ends before the 400 ms
    /// debounce, so pumpAndSettle alone would stop with the timer pending.
    Future<void> openSheetAndWait(WidgetTester tester) async {
      await openSheet(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    testWidgets('shows 400 ms after the sheet opens', (tester) async {
      final api = _Api();
      await tester.pumpWidget(_host(api, _TeamSession()));
      await tester.pumpAndSettle();
      await openSheet(tester);
      await tester.pump(const Duration(milliseconds: 399));
      expect(api.overlapCalls, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(api.overlapCalls, 1);
      await tester.pumpAndSettle();
      expect(find.text('Also off on these dates'), findsOneWidget);
      expect(find.text('Rachel Wong · Thu 12 Nov'), findsOneWidget);
      expect(
        find.text('Jason Lee · Thu 12 Nov (afternoon) · pending'),
        findsOneWidget,
      );
      expect(find.text('+2 more'), findsOneWidget);
    });

    testWidgets('never changes the submit button', (tester) async {
      final api = _Api();
      await tester.pumpWidget(_host(api, _TeamSession()));
      await tester.pumpAndSettle();
      await openSheet(tester);
      expect(
        tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
        isNotNull,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('also-off-line')), findsOneWidget);
      expect(
        tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
        isNotNull,
      );
      await tester.ensureVisible(find.text('SUBMIT LEAVE'));
      await tester.tap(find.text('SUBMIT LEAVE'));
      await tester.pumpAndSettle();
      expect(api.applies, 1);
      expect(find.text('Leave request submitted'), findsOneWidget);
    });

    testWidgets('hidden on an error', (tester) async {
      final api = _Api()..overlapError = ApiException('network_error');
      await tester.pumpWidget(_host(api, _TeamSession()));
      await tester.pumpAndSettle();
      await openSheetAndWait(tester);
      expect(api.overlapCalls, 1);
      expect(find.byKey(const ValueKey('also-off-line')), findsNothing);
      expect(find.text('SUBMIT LEAVE'), findsOneWidget);
    });

    testWidgets('hidden on an empty list', (tester) async {
      final api = _Api()..overlap = _overlapJson(empty: true);
      await tester.pumpWidget(_host(api, _TeamSession()));
      await tester.pumpAndSettle();
      await openSheetAndWait(tester);
      expect(api.overlapCalls, 1);
      expect(find.byKey(const ValueKey('also-off-line')), findsNothing);
    });

    testWidgets('not asked while team leave is off', (tester) async {
      final api = _Api();
      await tester.pumpWidget(_host(api, _TeamSession(team: false)));
      await tester.pumpAndSettle();
      await openSheet(tester);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(api.overlapCalls, 0);
      expect(find.byKey(const ValueKey('also-off-line')), findsNothing);
    });

    testWidgets('"See team leave" closes the sheet and opens the outlook', (
      tester,
    ) async {
      final api = _Api();
      await tester.pumpWidget(_host(api, _TeamSession()));
      await tester.pumpAndSettle();
      await openSheetAndWait(tester);
      await tester.ensureVisible(find.text('See team leave'));
      await tester.tap(find.text('See team leave'));
      await tester.pumpAndSettle();
      expect(find.text('SUBMIT LEAVE'), findsNothing);
      expect(find.text('OUTLOOK'), findsOneWidget);
      expect(api.applies, 0);
    });

    testWidgets('an overlap answer that lands after a cache clear is never '
        'shown; the same dates are asked again (A-L21)', (tester) async {
      final session = _TeamSession();
      final api = _Api();
      await tester.pumpWidget(_host(api, session));
      await tester.pumpAndSettle();
      final gate = Completer<void>();
      api.overlapGate = gate;
      await openSheet(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.overlapCalls, 1); // answers Rachel / Jason once released
      await tester.runAsync(() => TeamCache.clearEmployee(session));
      final first =
          (_overlapJson()['people'] as List).first as Map<String, dynamic>;
      api.overlap = {
        ..._overlapJson(),
        'people': [
          {...first, 'name': 'Mei Lin Ong'},
        ],
        'more': 0,
      };
      gate.complete();
      await tester.pumpAndSettle();
      expect(api.overlapCalls, 2);
      expect(find.text('Rachel Wong · Thu 12 Nov'), findsNothing);
      expect(find.text('+2 more'), findsNothing);
      expect(find.text('Mei Lin Ong · Thu 12 Nov'), findsOneWidget);
    });

    testWidgets('a /me that changes the scope while the line shows hides it '
        'at once and asks the same dates again (A-L22)', (tester) async {
      final session = _TeamSession();
      final api = _Api();
      await tester.pumpWidget(_host(api, session));
      await tester.pumpAndSettle();
      await openSheetAndWait(tester);
      expect(find.text('Rachel Wong · Thu 12 Nov'), findsOneWidget);
      expect(api.overlapCalls, 1); // no request outstanding
      api.overlapError = ApiException('network_error');
      session.changeScope('2222222222222222');
      await tester.pump();
      expect(find.byKey(const ValueKey('also-off-line')), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(api.overlapCalls, 2);
      expect(find.text('Rachel Wong · Thu 12 Nov'), findsNothing);
      expect(find.text('SUBMIT LEAVE'), findsOneWidget);
    });

    testWidgets('the same employee signs in again during the sign-out hook: '
        "the overlap retry sends the new token; the old account's names are "
        'never shown (A-L22, TLP3-F01)', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final session = _TeamSession();
      await tester.runAsync(() => _signIn(session, 'tok-A', 6));
      final log = _TokenLog();
      await tester.pumpWidget(_tokenHost(session, log));
      await tester.pumpAndSettle();
      final gate = Completer<void>();
      log.overlapGate = gate;
      await tester.tap(find.text('Annual Leave'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(log.overlapTokens, ['tok-A']);
      await tester.runAsync(() => _overlappingSignIn(session, 'tok-B', 6));
      gate.complete(); // A's names land under B's sign-in
      await tester.pumpAndSettle();
      expect(log.overlapTokens, ['tok-A', 'tok-B']);
      expect(find.text('Person of tok-A · Thu 12 Nov'), findsNothing);
      expect(find.text('Person of tok-B · Thu 12 Nov'), findsOneWidget);
    });
  });
}

/// Employee [employeeId] as `saveSession` sets it (no override), team
/// leave on: the other-employee sign-in (A-L22).
class _LiveTeamSession extends SessionService {
  @override
  String get clientDb => 'acme';

  @override
  bool get teamLeaveEnabled => true;

  @override
  String get teamCacheSignature => '1111111111111111';

  @override
  Future<bool> refreshMe() async => true;
}

/// What the credential-sensitive fakes saw (A-L22): the token of every
/// outlook / overlap call. Each gate holds the next call of its kind only.
class _TokenLog {
  final outlookTokens = <String>[];
  final overlapTokens = <String>[];
  Completer<void>? outlookGate;
  Completer<void>? overlapGate;
}

/// Built by the screen (and the sheet) for each attempt from the session
/// of the moment; its answers name the token it was built with, so an
/// answer sent with an old token is recognisable on screen and in the
/// cache.
class _TokenApi extends OmniMobileApi {
  _TokenApi(this.log, String token)
    : super(baseUrl: '', db: '', token: token);

  final _TokenLog log;

  @override
  Future<List<ApprovalItem>> getPendingApprovals() async => const [];

  @override
  Future<List<LeaveType>> getLeaveTypes() async => [
    LeaveType.fromJson({
      'id': 74,
      'name': 'Annual Leave',
      'request_unit': 'day',
      'requires_allocation': false,
    }),
  ];

  @override
  Future<TeamOutlook> fetchTeamOutlook({
    int days = 30,
    String context = 'team',
    String view = 'team',
    int? departmentId,
  }) async {
    log.outlookTokens.add(token);
    final gate = log.outlookGate;
    log.outlookGate = null;
    if (gate != null) await gate.future;
    final body = _outlookJson();
    return TeamOutlook.fromJson({
      ...body,
      'summary': {
        ...body['summary'] as Map<String, dynamic>,
        'label': 'Team of $token',
      },
    });
  }

  @override
  Future<TeamOverlap> fetchTeamOverlap(DateTime from, DateTime to) async {
    log.overlapTokens.add(token);
    final gate = log.overlapGate;
    log.overlapGate = null;
    if (gate != null) await gate.future;
    final first =
        (_overlapJson()['people'] as List).first as Map<String, dynamic>;
    return TeamOverlap.fromJson({
      ..._overlapJson(),
      'people': [
        {...first, 'name': 'Person of $token'},
      ],
      'more': 0,
    });
  }
}

Widget _tokenHost(SessionService session, _TokenLog log) => MultiProvider(
  providers: [
    ChangeNotifierProvider<SessionService>.value(value: session),
    ChangeNotifierProvider<HolidayService>(create: (_) => HolidayService()),
  ],
  child: MaterialApp(
    home: LeaveScreen(
      apiBuilder: (s) => _TokenApi(log, s.token),
      appBar: AppBar(title: const Text('TEST BAR')),
      teamLeaveBuilder: () => Scaffold(
        appBar: AppBar(),
        body: const Text('OUTLOOK'),
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
