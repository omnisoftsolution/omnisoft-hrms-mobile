import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:omni_hr/screens/activation/invite_scan_screen.dart';

void main() {
  testWidgets('non-permission camera errors show the enter-code message',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: cameraErrorView(
                MobileScannerErrorCode.genericError, () {}))));
    expect(find.text('The camera could not start. Enter the code instead.'),
        findsOneWidget);
  });

  testWidgets('permission denied keeps the black box and calls back',
      (tester) async {
    var called = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: cameraErrorView(
                MobileScannerErrorCode.permissionDenied, () => called++))));
    await tester.pump();
    expect(find.text('The camera could not start. Enter the code instead.'),
        findsNothing);
    expect(called, 1);
  });
}
