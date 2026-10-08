import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:omni_hr/core/theme.dart';
import 'package:omni_hr/models/leave_record.dart';
import 'package:omni_hr/screens/leave_history/leave_history_screen.dart';
import 'package:omni_hr/services/holiday_service.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:omni_hr/widgets/error_state_view.dart';

LeaveRecord leave(Map<String, dynamic> extra) => LeaveRecord.fromJson({
  'id': 1,
  'leave_type': 'Annual Leave',
  'date_from': '2026-10-26',
  'date_to': '2026-10-26',
  'number_of_days': 1,
  'state': 'confirm',
  'request_unit': 'day',
  ...extra,
});

class FakeApi extends OmniMobileApi {
  FakeApi(this.pages) : super(baseUrl: '', db: '', token: '');

  /// One list per getLeaveHistory call; the last one repeats.
  final List<List<LeaveRecord>> pages;
  int historyCalls = 0;
  Object? cancelError;
  Object? modifyError;
  final List<int> cancelled = [];
  int modifies = 0;

  /// When set, the next getLeaveHistory waits for it.
  Completer<void>? gate;

  @override
  Future<List<LeaveRecord>> getLeaveHistory() async {
    final page = pages[historyCalls.clamp(0, pages.length - 1)];
    historyCalls++;
    final g = gate;
    if (g != null) {
      gate = null;
      await g.future;
    }
    return page;
  }

  @override
  Future<Map<String, dynamic>> modifyLeave({
    required int leaveId,
    required String dateFrom,
    required String dateTo,
    required String reason,
    String? dateFromPeriod,
    String? dateToPeriod,
    double? hourFrom,
    double? hourTo,
    Map<String, dynamic>? attachment,
  }) async {
    modifies++;
    if (modifyError != null) throw modifyError!;
    return {'success': true};
  }

  @override
  Future<Map<String, dynamic>> cancelLeave({
    required int leaveId,
    String? reason,
  }) async {
    if (cancelError != null) throw cancelError!;
    cancelled.add(leaveId);
    return {'success': true};
  }
}

/// The second getLeaveHistory call (after its gate) fails.
class _FailingFirstReload extends FakeApi {
  _FailingFirstReload(super.pages);

  @override
  Future<List<LeaveRecord>> getLeaveHistory() async {
    final call = historyCalls;
    final page = await super.getLeaveHistory();
    if (call == 1) throw ApiException('network_error');
    return page;
  }
}

Widget host(FakeApi api, {GlobalKey<LeaveHistoryScreenState>? key}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionService>(create: (_) => SessionService()),
        ChangeNotifierProvider<HolidayService>(create: (_) => HolidayService()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: LeaveHistoryScreen(key: key, apiBuilder: (_) => api),
        ),
      ),
    );

void main() {
  test('validate1 uses the pending chip colour, not the approved one', () {
    expect(leaveStateColor('validate1'), leaveStateColor('confirm'));
    expect(leaveStateColor('validate1'), isNot(leaveStateColor('validate')));
    expect(leaveStateColor('validate'), AppTheme.primary);
    expect(leaveStateColor('refuse'), AppTheme.error);
  });

  testWidgets('the expanded card pluralises the balance rows', (tester) async {
    final api = FakeApi([
      [
        leave({
          'requires_allocation': true,
          'allocation_total': 2,
          'allocation_remaining': 1,
        }),
      ],
    ]);
    await tester.pumpWidget(host(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annual Leave'));
    await tester.pumpAndSettle();
    expect(find.text('2 days total'), findsOneWidget);
    expect(find.text('1 day'), findsNWidgets(2)); // Used + Remaining
    expect(find.textContaining('1 days'), findsNothing);
  });

  testWidgets('a refused leave shows its refusal reason after the reason', (
    tester,
  ) async {
    final api = FakeApi([
      [
        leave({
          'id': 7,
          'state': 'refuse',
          'reason': 'Family trip',
          'refusal_reason': 'Team is short that week',
        }),
        leave({
          'id': 8,
          'leave_type': 'Sick Leave',
          'state': 'refuse',
          'refusal_reason': false,
        }),
      ],
    ]);
    await tester.pumpWidget(host(api));
    await tester.pumpAndSettle();
    expect(find.text('Refusal reason'), findsNothing); // collapsed

    await tester.tap(find.text('Annual Leave'));
    await tester.pumpAndSettle();
    expect(find.text('Refusal reason'), findsOneWidget);
    expect(find.text('Team is short that week'), findsOneWidget);
    final reasonY = tester.getTopLeft(find.text('Reason')).dy;
    final refusalY = tester.getTopLeft(find.text('Refusal reason')).dy;
    expect(refusalY, greaterThan(reasonY));

    // No reason from the server (older connector or HR left it empty).
    await tester.tap(find.text('Sick Leave'));
    await tester.pumpAndSettle();
    expect(find.text('Refusal reason'), findsNothing);
  });

  test('label column: longest label + gap, capped (N2)', () {
    double w(double scale, double max) => detailLabelColumnWidth(
      labels: const ['Used', 'Refusal reason'],
      style: const TextStyle(fontSize: 10),
      textScaler: TextScaler.linear(scale),
      gap: 12,
      maxWidth: max,
    );
    // FlutterTest font: every glyph is font-size wide; 14 characters.
    expect(w(1.0, 1000), 140 + 12);
    expect(w(2.0, 1000), 280 + 12);
    expect(w(2.0, 200), 200);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('a narrow phone keeps a gap after every label (N2, x$scale)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 1400);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      const refusal = 'Project deadline that week, please pick other dates';
      final api = FakeApi([
        [
          leave({
            'state': 'refuse',
            'reason': 'Family trip',
            'refusal_reason': refusal,
            'requires_allocation': true,
            'allocation_total': 14,
            'allocation_remaining': 13,
          }),
        ],
      ]);
      await tester.pumpWidget(host(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annual Leave'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final pairs = {
        'Reason': 'Family trip',
        'Refusal reason': refusal,
        'Allocation': '14 days total',
        'Used': '1 day',
        'Remaining': '13 days',
      };
      final valueLefts = <double>{};
      pairs.forEach((label, value) {
        final l = tester.getRect(find.text(label));
        final v = tester.getRect(find.text(value));
        expect(v.left - l.right, greaterThanOrEqualTo(8), reason: label);
        valueLefts.add(v.left);
      });
      // One value column: every value starts at the same x …
      expect(valueLefts.length, 1);
      // … and a long value wraps under it rather than running off.
      final r = tester.getRect(find.text(refusal));
      expect(r.height, greaterThan(13 * scale * 1.5));
      expect(r.right, lessThanOrEqualTo(360));
    });
  }

  testWidgets('the card and the cancel dialog show formatted dates', (
    tester,
  ) async {
    final api = FakeApi([
      [leave({})],
    ]);
    await tester.pumpWidget(host(api));
    await tester.pumpAndSettle();
    expect(find.text('Mon 26 Oct · 1d'), findsOneWidget);
    expect(find.textContaining('2026-10-26'), findsNothing);

    await tester.tap(find.text('Annual Leave'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel this leave?'), findsOneWidget);
    expect(find.text('Annual Leave\nMon 26 Oct · 1d'), findsOneWidget);
  });

  group('a request decided while the list was open (M4)', () {
    final pending = leave({'state': 'confirm'});
    final approved = leave({'state': 'validate'});

    testWidgets('Cancel: says so without "Pull down" and reloads', (
      tester,
    ) async {
      final api = FakeApi([
        [pending],
        [approved],
      ])..cancelError = ApiException('not_cancellable', data: {'state': 'validate'});
      await tester.pumpWidget(host(api));
      await tester.pumpAndSettle();
      expect(find.text('Pending'), findsOneWidget);

      await tester.tap(find.text('Annual Leave'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel leave'));
      await tester.pumpAndSettle();

      expect(find.text('This request was already decided.'), findsOneWidget);
      expect(find.textContaining('Pull down'), findsNothing);
      expect(api.historyCalls, 2);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Pending'), findsNothing);
      // An approved leave has no Edit / Cancel any more.
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
    });

    testWidgets('Edit: the sheet closes, says so and the list reloads', (
      tester,
    ) async {
      final api = FakeApi([
        [pending],
        [approved],
      ])..modifyError = ApiException('not_modifiable', data: {'state': 'validate'});
      await tester.pumpWidget(host(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annual Leave'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(api.modifies, 1);
      expect(find.text('Save changes'), findsNothing); // sheet closed
      expect(find.text('This request was already decided.'), findsOneWidget);
      expect(api.historyCalls, 2);
      expect(find.text('Approved'), findsOneWidget);
    });

    testWidgets('a quiet reload keeps the cards on screen meanwhile', (
      tester,
    ) async {
      final key = GlobalKey<LeaveHistoryScreenState>();
      final api = FakeApi([
        [pending],
        [approved],
      ]);
      await tester.pumpWidget(host(api, key: key));
      await tester.pumpAndSettle();
      final gate = Completer<void>();
      api.gate = gate;
      unawaited(key.currentState!.refresh(quiet: true));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Pending'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Approved'), findsOneWidget);
    });

    testWidgets('an older reload finishing last does not undo a newer one', (
      tester,
    ) async {
      final key = GlobalKey<LeaveHistoryScreenState>();
      final api = FakeApi([
        [pending], // first load
        [pending], // slow reload A (asked before the decision)
        [approved], // reload B (after the leave_approved notification)
      ]);
      await tester.pumpWidget(host(api, key: key));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annual Leave'));
      await tester.pumpAndSettle();

      final gateA = Completer<void>();
      api.gate = gateA;
      final a = key.currentState!.refresh(quiet: true);
      final gateB = Completer<void>();
      api.gate = gateB;
      final b = key.currentState!.refresh(quiet: true);

      gateB.complete();
      await b;
      await tester.pumpAndSettle();
      expect(find.text('Approved'), findsOneWidget);

      gateA.complete(); // the stale answer arrives last
      await a;
      await tester.pumpAndSettle();
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Pending'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets('a highlight waits for an overlapping newer reload', (
      tester,
    ) async {
      final key = GlobalKey<LeaveHistoryScreenState>();
      final fresh = leave({'id': 99, 'leave_type': 'Sick Leave'});
      final old = leave({'id': 1});
      final api = FakeApi([
        [old], // first load
        [old], // the notification tap's reload: slow, from before #99
        [fresh, old], // an overlapping reload that already has #99
      ]);
      await tester.pumpWidget(host(api, key: key));
      await tester.pumpAndSettle();

      final gateTap = Completer<void>();
      api.gate = gateTap;
      var highlightDone = false;
      unawaited(
        key.currentState!
            .scrollToAndHighlight(99)
            .then((_) => highlightDone = true),
      );
      final gateNewer = Completer<void>();
      api.gate = gateNewer;
      final newer = key.currentState!.refresh(quiet: true);

      // The superseded (older) answer lands first: the highlight must not
      // judge the list by it.
      gateTap.complete();
      await tester.pump();
      expect(highlightDone, isFalse);
      expect(find.textContaining('older than the most recent 50'),
          findsNothing);

      gateNewer.complete();
      await newer;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // scroll
      expect(find.textContaining('older than the most recent 50'),
          findsNothing);
      expect(find.text('Sick Leave'), findsOneWidget);
      // #99 auto-expanded by the highlight.
      expect(find.text('Cancel'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3)); // highlight fades
      await tester.pumpAndSettle();
      expect(highlightDone, isTrue);
    });

    testWidgets('every overlapping refresh resolves with the newest', (
      tester,
    ) async {
      final key = GlobalKey<LeaveHistoryScreenState>();
      final api = FakeApi([
        [pending],
        [pending],
        [approved],
      ]);
      await tester.pumpWidget(host(api, key: key));
      await tester.pumpAndSettle();
      final gateA = Completer<void>();
      api.gate = gateA;
      var aDone = false;
      unawaited(
        key.currentState!.refresh(quiet: true).then((_) => aDone = true),
      );
      final gateB = Completer<void>();
      api.gate = gateB;
      final b = key.currentState!.refresh(quiet: true);
      gateA.complete();
      await tester.pump();
      expect(aDone, isFalse); // superseded: waits for B
      gateB.complete();
      await b;
      await tester.pump();
      expect(aDone, isTrue);
      expect(find.text('Approved'), findsOneWidget);
    });

    testWidgets('an older failure after a newer success shows no error', (
      tester,
    ) async {
      final key = GlobalKey<LeaveHistoryScreenState>();
      final api = _FailingFirstReload([
        [pending],
        [pending],
        [approved],
      ]);
      await tester.pumpWidget(host(api, key: key));
      await tester.pumpAndSettle();

      final gateA = Completer<void>();
      api.gate = gateA;
      final a = key.currentState!.refresh(); // loud: errors would show
      final gateB = Completer<void>();
      api.gate = gateB;
      final b = key.currentState!.refresh();
      gateB.complete();
      await b;
      gateA.complete();
      await a;
      await tester.pumpAndSettle();
      expect(find.text('Approved'), findsOneWidget);
      expect(find.byType(ErrorStateView), findsNothing);
    });

    testWidgets('another error keeps the old message path, no reload', (
      tester,
    ) async {
      final api = FakeApi([
        [pending],
      ])..cancelError = ApiException('network_error');
      await tester.pumpWidget(host(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annual Leave'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel leave'));
      await tester.pumpAndSettle();
      expect(
        find.text('No internet connection. Check your network and try again.'),
        findsOneWidget,
      );
      expect(api.historyCalls, 1);
    });
  });
}
