import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/core/omni_colors.dart';
import 'package:omni_hr/core/theme.dart';
import 'package:omni_hr/models/approval_item.dart';
import 'package:omni_hr/screens/approvals/approvals_screen.dart';
import 'package:omni_hr/screens/leave/leave_approvals_row.dart';
import 'package:omni_hr/screens/leave_history/leave_history_screen.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dark mode M3/M4: screens take their colours from the theme.
class _Session extends SessionService {
  _Session({this.count = 0});

  final int count;

  @override
  bool get leaveApprovalsEnabled => true;

  @override
  int get leaveApprovalsPendingCount => count;

  @override
  Future<bool> refreshMe() async => true;
}

class _Api extends OmniMobileApi {
  _Api() : super(baseUrl: '', db: '', token: '');

  @override
  Future<List<ApprovalItem>> getPendingApprovals() async => [
    ApprovalItem(
      id: 1,
      employeeName: 'Emp 1',
      leaveTypeName: 'Annual Leave',
      state: 'confirm',
      dateFrom: DateTime(2026, 10, 6),
      dateTo: DateTime(2026, 10, 7),
      numberOfDays: 2,
      numberOfHours: 16,
      durationLabel: '2d',
      step: 'manager_approval',
      assignedToMe: true,
      canApprove: true,
      canRefuse: true,
    ),
  ];

  @override
  Future<List<ApprovalItem>> getRecentApprovals() async => [];
}

Widget _app(SessionService session, Widget home, {bool dark = true}) =>
    ChangeNotifierProvider<SessionService>.value(
      value: session,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: home,
      ),
    );

Color? _rowColor(WidgetTester tester) => tester
    .widget<Card>(find.byKey(const ValueKey('leave-approvals-row')))
    .color;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final dark = OmniColors.dark;
  final light = OmniColors.light;

  test('leaveStateColor: light default unchanged, dark from the palette', () {
    expect(leaveStateColor('validate'), AppTheme.primary);
    expect(leaveStateColor('refuse'), AppTheme.error);
    expect(leaveStateColor('confirm'), AppTheme.secondary);
    expect(leaveStateColor('draft'), AppTheme.outline);
    expect(leaveStateColor('validate', dark), dark.accent);
    expect(leaveStateColor('refuse', dark), dark.error);
    expect(leaveStateColor('validate1', dark), dark.secondary);
  });

  group('LeaveApprovalsRow', () {
    testWidgets('dark, waiting: teal fill behind white text', (tester) async {
      await tester.pumpWidget(
        _app(
          _Session(count: 2),
          const Scaffold(body: LeaveApprovalsRow(breakdown: '', onTap: _noop)),
        ),
      );
      expect(_rowColor(tester), dark.brandFill);
    });

    testWidgets('dark, nothing waiting: a dark card', (tester) async {
      await tester.pumpWidget(
        _app(
          _Session(),
          const Scaffold(body: LeaveApprovalsRow(breakdown: '', onTap: _noop)),
        ),
      );
      expect(_rowColor(tester), dark.card);
    });

    testWidgets('light: white card as before', (tester) async {
      await tester.pumpWidget(
        _app(
          _Session(),
          const Scaffold(body: LeaveApprovalsRow(breakdown: '', onTap: _noop)),
          dark: false,
        ),
      );
      expect(_rowColor(tester), light.card);
      expect(light.card, Colors.white);
    });
  });

  testWidgets('ApprovalsScreen renders on the dark background', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_Session(), ApprovalsScreen(apiBuilder: (_) => _Api())),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Emp 1'), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, dark.background);
  });
}

void _noop() {}
