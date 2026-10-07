import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/screens/leave/leave_approvals_row.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Session extends SessionService {
  _Session({required this.enabled, required this.count});

  bool enabled;
  int count;

  @override
  bool get leaveApprovalsEnabled => enabled;

  @override
  int get leaveApprovalsPendingCount => count;
}

Widget _host(_Session session, {String breakdown = '', VoidCallback? onTap}) =>
    ChangeNotifierProvider<SessionService>.value(
      value: session,
      child: MaterialApp(
        home: Scaffold(
          body: LeaveApprovalsRow(breakdown: breakdown, onTap: onTap ?? () {}),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('hidden for non-approvers', (tester) async {
    await tester.pumpWidget(_host(_Session(enabled: false, count: 0)));
    expect(find.byKey(const ValueKey('leave-approvals-row')), findsNothing);
  });

  testWidgets('nothing waiting: white row pointing at Recent', (tester) async {
    await tester.pumpWidget(_host(_Session(enabled: true, count: 0)));
    expect(find.byKey(const ValueKey('leave-approvals-row')), findsOneWidget);
    expect(find.text('Leave approvals'), findsOneWidget);
    expect(find.text('Nothing waiting · Recent decisions'), findsOneWidget);
    expect(find.byType(Badge), findsNothing);
  });

  testWidgets('waiting: count, breakdown and a tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        _Session(enabled: true, count: 2),
        breakdown: '1 Childcare Leave · 1 Sick Leave',
        onTap: () => taps++,
      ),
    );
    expect(find.text('2 waiting for you'), findsOneWidget);
    expect(find.text('1 Childcare Leave · 1 Sick Leave'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('leave-approvals-row')));
    expect(taps, 1);
  });
}
