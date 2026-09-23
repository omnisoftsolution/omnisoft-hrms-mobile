// test/screens/change_password_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/screens/profile/change_password_screen.dart';

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
