// test/screens/change_password_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/screens/profile/change_password_screen.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';

/// /auth/password/change always fails with [error].
class _FakeApi extends OmniMobileApi {
  _FakeApi(this.error) : super(baseUrl: '', db: '', token: '');
  final ApiException error;

  @override
  Future<void> passwordChange({
    required String currentPassword,
    required String newPassword,
  }) async =>
      throw error;
}

void main() {
  testWidgets('submit enabled only when new passwords match and are long enough', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ChangePasswordScreen()));
    final btn = find.widgetWithText(FilledButton, 'Change password');
    expect(tester.widget<FilledButton>(btn).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('pw_current')), 'oldpassword');
    await tester.enterText(find.byKey(const Key('pw_new')), 'newpassword1');
    await tester.enterText(find.byKey(const Key('pw_new2')), 'newpassword2');
    await tester.pump();
    expect(tester.widget<FilledButton>(btn).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('pw_new2')), 'newpassword1');
    await tester.pump();
    expect(tester.widget<FilledButton>(btn).onPressed, isNotNull);
  });

  testWidgets('submit stays disabled when the new password is under 8 characters',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ChangePasswordScreen()));
    final btn = find.widgetWithText(FilledButton, 'Change password');
    await tester.enterText(find.byKey(const Key('pw_current')), 'oldpassword');
    await tester.enterText(find.byKey(const Key('pw_new')), 'short7c');
    await tester.enterText(find.byKey(const Key('pw_new2')), 'short7c');
    await tester.pump();
    expect(tester.widget<FilledButton>(btn).onPressed, isNull);
  });

  Future<void> submitWith(WidgetTester tester, ApiException error) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider<SessionService>(
        create: (_) => SessionService(),
        child: ChangePasswordScreen(apiBuilder: (_) => _FakeApi(error)),
      ),
    ));
    await tester.enterText(find.byKey(const Key('pw_current')), 'oldpassword');
    await tester.enterText(find.byKey(const Key('pw_new')), 'newpassword1');
    await tester.enterText(find.byKey(const Key('pw_new2')), 'newpassword1');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Change password'));
    await tester.pumpAndSettle();
  }

  testWidgets('not_allowed says password change is not available',
      (tester) async {
    await submitWith(tester, ApiException('not_allowed'));
    expect(
        find.text('Password change is not available for this account. '
            'Ask HR.'),
        findsOneWidget);
  });

  testWidgets('account_locked shows the wait in minutes', (tester) async {
    await submitWith(
        tester, ApiException('account_locked', data: {'retry_after': 120}));
    expect(find.text('Too many attempts. Try again in 2 minutes.'),
        findsOneWidget);
  });

  testWidgets('submit stays disabled when the current password is empty',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ChangePasswordScreen()));
    final btn = find.widgetWithText(FilledButton, 'Change password');
    await tester.enterText(find.byKey(const Key('pw_new')), 'newpassword1');
    await tester.enterText(find.byKey(const Key('pw_new2')), 'newpassword1');
    await tester.pump();
    expect(tester.widget<FilledButton>(btn).onPressed, isNull);
  });
}
