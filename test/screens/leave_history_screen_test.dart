import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:omni_hr/core/theme.dart';
import 'package:omni_hr/models/leave_record.dart';
import 'package:omni_hr/screens/leave_history/leave_history_screen.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';

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
  final List<int> cancelled = [];

  @override
  Future<List<LeaveRecord>> getLeaveHistory() async {
    final page = pages[historyCalls.clamp(0, pages.length - 1)];
    historyCalls++;
    return page;
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

Widget host(FakeApi api, {GlobalKey<LeaveHistoryScreenState>? key}) =>
    ChangeNotifierProvider<SessionService>(
      create: (_) => SessionService(),
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
}
