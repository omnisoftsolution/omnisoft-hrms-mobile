import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:omni_hr/models/notification_record.dart';
import 'package:omni_hr/screens/notifications/notification_tap.dart';
import 'package:omni_hr/services/notification_service.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';

class _Bell extends NotificationService {
  final List<int> marked = [];

  /// markRead(id) waits for markGates[id] when one is set.
  final Map<int, Completer<void>> markGates = {};

  @override
  Future<void> refreshList() async {}

  @override
  Future<void> markRead(int id) async {
    marked.add(id);
    final gate = markGates[id];
    if (gate != null) await gate.future;
  }
}

NotificationRecord _n(int id, String kind, {Map<String, dynamic> payload = const {}, bool answered = false}) =>
    NotificationRecord(id: id, kind: kind, title: 'Notice $id', payload: payload, answered: answered);

void main() {
  group('handleNotificationTap (the bell handler, shared with push taps)', () {
    late _Bell bell;
    late List<String> taps;

    setUp(() {
      bell = _Bell();
      taps = [];
    });

    Widget host(NotificationRecord n) => ChangeNotifierProvider<NotificationService>.value(
      value: bell,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => handleNotificationTap(
                ctx,
                n,
                targets: NotificationTapTargets(
                  onLeaveTap: (id) => taps.add('leave:$id'),
                  onExpenseTap: (id) => taps.add('expense:$id'),
                  onApprovalTap: (id) => taps.add('approval:$id'),
                  onMyDayTap: () => taps.add('myday'),
                ),
              ),
              child: const Text('TAP'),
            ),
          ),
        ),
      ),
    );

    Future<void> tap(WidgetTester tester, NotificationRecord n) async {
      await tester.pumpWidget(host(n));
      await tester.tap(find.text('TAP'));
      await tester.pumpAndSettle();
    }

    testWidgets('Approval needed opens the request', (tester) async {
      await tap(tester, _n(11, 'leave_approval_requested', payload: const {'leave_id': 148}));
      expect(bell.marked, [11]);
      expect(taps, ['approval:148']);
    });

    testWidgets('a decision on my leave opens my leave', (tester) async {
      await tap(tester, _n(12, 'leave_refused', payload: const {'leave_id': 9}));
      expect(taps, ['leave:9']);
    });

    testWidgets('an expense decision opens Expenses', (tester) async {
      await tap(tester, _n(13, 'expense_approved', payload: const {'expense_id': 3}));
      expect(taps, ['expense:3']);
    });

    testWidgets('HR updated your attendance opens My day', (tester) async {
      await tap(tester, _n(14, 'attendance_declaration_applied'));
      expect(taps, ['myday']);
    });

    testWidgets('an announcement is only marked read', (tester) async {
      await tap(tester, _n(15, 'announcement', payload: const {'announcement_id': 4}));
      expect(bell.marked, [15]);
      expect(taps, isEmpty);
    });

    // Fix round 2 (Codex r2 MINOR): the latest-tap check is carried into
    // the handler and asked again after its own awaits.
    testWidgets('a push tap whose mark-read is overtaken by a newer tap '
        'navigates nowhere; the newer one does', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        ChangeNotifierProvider<NotificationService>.value(
          value: bell,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (c) {
                  ctx = c;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      final targets = NotificationTapTargets(
        onLeaveTap: (id) => taps.add('leave:$id'),
      );
      final gate = Completer<void>();
      bell.markGates[21] = gate;
      final latest = LatestTap();
      final older = handleNotificationTap(
        ctx,
        _n(21, 'leave_approved', payload: const {'leave_id': 1}),
        targets: targets,
        stillCurrent: latest.next(),
      );
      await tester.pump();
      await handleNotificationTap(
        ctx,
        _n(22, 'leave_approved', payload: const {'leave_id': 2}),
        targets: targets,
        stillCurrent: latest.next(),
      );
      expect(taps, ['leave:2']);
      gate.complete();
      await older;
      await tester.pump();
      expect(taps, ['leave:2']);
    });

    testWidgets('an answered HR question says so', (tester) async {
      await tap(tester, _n(16, 'attendance_query', answered: true));
      expect(find.text('You already answered this question.'), findsOneWidget);
    });
  });

  group('tapsThroughHandler', () {
    test('kinds the bell handler routes, with their ids', () {
      expect(tapsThroughHandler(_n(1, 'leave_approval_requested', payload: const {'leave_id': 1})), isTrue);
      expect(tapsThroughHandler(_n(1, 'leave_approved', payload: const {'leave_id': 1})), isTrue);
      expect(tapsThroughHandler(_n(1, 'leave_first_approved', payload: const {'leave_id': 1})), isTrue);
      expect(tapsThroughHandler(_n(1, 'expense_refused', payload: const {'expense_id': 1})), isTrue);
      expect(
        tapsThroughHandler(
          _n(1, 'attendance_query', payload: const {
            'options': [
              {'code': 'yes', 'label': 'Yes'},
            ],
          }),
        ),
        isTrue,
      );
      expect(tapsThroughHandler(_n(1, 'attendance_query', answered: true)), isTrue);
      expect(tapsThroughHandler(_n(1, 'attendance_declaration_applied')), isTrue);
    });

    // Review fix round 1 (Codex 8): the handler can neither open the answer
    // sheet nor say "already answered" — the bell shows it instead.
    test('an unanswered HR question without options goes to the bell', () {
      expect(tapsThroughHandler(_n(1, 'attendance_query')), isFalse);
      expect(
        tapsThroughHandler(
          _n(1, 'attendance_query', payload: const {'options': <Object>[]}),
        ),
        isFalse,
      );
    });

    test('announcements, system notices and missing ids go to the bell', () {
      expect(tapsThroughHandler(_n(1, 'announcement')), isFalse);
      expect(tapsThroughHandler(_n(1, 'system', payload: const {'event': 'device_added'})), isFalse);
      expect(tapsThroughHandler(_n(1, 'leave_approved')), isFalse);
      expect(tapsThroughHandler(_n(1, 'expense_approved')), isFalse);
    });
  });

  test('a push tap on an approval request re-pulls the approvals count; '
      'other kinds do not (Fable r2 #1)', () {
    expect(pushTapRefreshesApprovals({'kind': 'leave_approval_requested'}),
        isTrue);
    expect(pushTapRefreshesApprovals({'kind': 'leave_approved'}), isFalse);
    expect(pushTapRefreshesApprovals(const {}), isFalse);
  });

  group('openPushTap (spec §6.4)', () {
    late List<String> did;

    setUp(() => did = []);

    Future<void> open(
      Map<String, dynamic> data,
      Future<NotificationRecord> Function(int id) fetch, {
      bool Function()? stillCurrent,
    }) => openPushTap(
      data,
      fetch: fetch,
      openHome: () async => did.add('home'),
      openBell: () async => did.add('bell'),
      runHandler: (n) async => did.add('handler ${n.id}'),
      stillCurrent: stillCurrent,
    );

    Future<NotificationRecord> never(int id) => throw StateError('no fetch expected');

    test('a reminder opens Home without a fetch', () async {
      await open({'kind': 'remind_check_out', 'notification_id': ''}, never);
      expect(did, ['home']);
    });

    test('a routable notice is fetched and runs the bell handler', () async {
      await open(
        {'kind': 'leave_approval_requested', 'notification_id': '41'},
        (id) async => _n(id, 'leave_approval_requested', payload: const {'leave_id': 148}),
      );
      expect(did, ['handler 41']);
    });

    test('an announcement opens the bell', () async {
      await open({'kind': 'announcement', 'notification_id': '42'}, (id) async => _n(id, 'announcement'));
      expect(did, ['bell']);
    });

    test('404 not_found opens the bell', () async {
      await open(
        {'kind': 'leave_approved', 'notification_id': '43'},
        (id) async => throw ApiException('not_found'),
      );
      expect(did, ['bell']);
    });

    test('no network opens the bell', () async {
      await open(
        {'kind': 'leave_approved', 'notification_id': '44'},
        (id) async => throw ApiException('network_error'),
      );
      expect(did, ['bell']);
    });

    test('a notice without an id opens the bell', () async {
      await open({'kind': 'leave_approved'}, never);
      expect(did, ['bell']);
    });

    test('an answer for a session that ended (or got a new access token) '
        'while it was fetched opens nothing', () async {
      var current = true;
      Future<NotificationRecord> Function(int id) endsWhile(
        Future<NotificationRecord> Function(int id) answer,
      ) => (id) async {
        current = false;
        return answer(id);
      };
      for (final fetch in [
        endsWhile(
          (id) async =>
              _n(id, 'leave_approval_requested', payload: const {'leave_id': 1}),
        ),
        endsWhile((id) async => _n(id, 'announcement')),
        endsWhile((id) async => throw ApiException('invalid_session')),
      ]) {
        current = true;
        await open(
          {'kind': 'leave_approved', 'notification_id': '45'},
          fetch,
          stillCurrent: () => current,
        );
      }
      expect(did, isEmpty);
    });

    // Review fix round 1 (Codex 8): two taps whose fetches overlap — only
    // the latest one opens anything (HomeShell's LatestTap guard).
    test('two taps at once: the latest wins, the older answer is dropped',
        () async {
      final taps = LatestTap();
      final slow = Completer<NotificationRecord>();
      final first = taps.next();
      final older = open(
        {'kind': 'leave_approval_requested', 'notification_id': '47'},
        (id) => slow.future,
        stillCurrent: first,
      );
      final second = taps.next();
      await open(
        {'kind': 'leave_approval_requested', 'notification_id': '48'},
        (id) async => _n(id, 'leave_approval_requested', payload: const {'leave_id': 3}),
        stillCurrent: second,
      );
      slow.complete(_n(47, 'leave_approval_requested', payload: const {'leave_id': 4}));
      await older;
      expect(did, ['handler 48']);
    });

    test('an unanswered HR question without options opens the bell', () async {
      await open(
        {'kind': 'attendance_query', 'notification_id': '49'},
        (id) async => _n(id, 'attendance_query'),
      );
      expect(did, ['bell']);
    });

    test('a current session routes as usual', () async {
      await open(
        {'kind': 'leave_approval_requested', 'notification_id': '46'},
        (id) async => _n(id, 'leave_approval_requested', payload: const {'leave_id': 2}),
        stillCurrent: () => true,
      );
      expect(did, ['handler 46']);
    });
  });

  group('a push tap while Profile is open (spec §6.4)', () {
    /// A page on the root navigator, as OmniAppBar opens Profile and the bell.
    Route<void> page(String text) => MaterialPageRoute<void>(
      builder: (_) => Scaffold(body: Text(text)),
    );

    testWidgets('popAbove closes Profile and the bell above the shell; the '
        'tap then opens its target on the shell', (tester) async {
      late BuildContext shell;
      var opened = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              shell = ctx;
              return const Scaffold(body: Text('SHELL'));
            },
          ),
        ),
      );
      final root = Navigator.of(shell, rootNavigator: true);
      unawaited(root.push(page('PROFILE')));
      unawaited(root.push(page('BELL')));
      await tester.pumpAndSettle();
      expect(find.text('BELL'), findsOneWidget);

      // What HomeShell._openPushTap does: popAbove, then openPushTap.
      popAbove(shell);
      await openPushTap(
        {'kind': 'remind_check_in', 'notification_id': ''},
        fetch: (_) async => throw StateError('no fetch expected'),
        openHome: () async => opened = 'home',
        openBell: () async => opened = 'bell',
        runHandler: (_) async => opened = 'handler',
      );
      await tester.pumpAndSettle();
      expect(find.text('PROFILE'), findsNothing);
      expect(find.text('BELL'), findsNothing);
      expect(find.text('SHELL'), findsOneWidget);
      expect(opened, 'home');
    });

    testWidgets('pages below the shell stay; with the shell on top nothing '
        'is popped', (tester) async {
      late BuildContext shell;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('LOGIN'))),
      );
      final root = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        root.push(
          MaterialPageRoute<void>(
            builder: (ctx) {
              shell = ctx;
              return const Scaffold(body: Text('SHELL'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      popAbove(shell);
      await tester.pumpAndSettle();
      expect(find.text('SHELL'), findsOneWidget);
      unawaited(root.push(page('PROFILE')));
      await tester.pumpAndSettle();
      popAbove(shell);
      await tester.pumpAndSettle();
      expect(find.text('PROFILE'), findsNothing);
      expect(find.text('SHELL'), findsOneWidget);
      expect(root.canPop(), isTrue);
    });
  });
}
