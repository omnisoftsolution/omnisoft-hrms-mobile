import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/screens/activation/invite_scan_screen.dart';

/// Stand-in scanner: exposes the callbacks so tests drive them.
class _FakeScanner {
  void Function(String)? onCode;
  VoidCallback? onDenied;
  int builds = 0;
  Widget build(BuildContext context,
      {required void Function(String raw) onCode,
      required VoidCallback onPermissionDenied}) {
    builds++;
    this.onCode = onCode;
    onDenied = onPermissionDenied;
    return const ColoredBox(color: Colors.black, key: Key('fake_camera'));
  }
}

void main() {
  late _FakeScanner scanner;
  late List<ScanOutcome?> popped;
  var settingsOpened = 0;

  Future<void> pumpScreen(WidgetTester tester) async {
    popped = [];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async {
              popped.add(await Navigator.of(ctx).push<ScanOutcome>(
                  MaterialPageRoute(
                      builder: (_) => InviteScanScreen(
                            scannerBuilder: scanner.build,
                            openSettings: () async => settingsOpened++,
                          ))));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    scanner = _FakeScanner();
    settingsOpened = 0;
  });

  testWidgets('an invite pops ScannedInvite once, even if seen twice',
      (tester) async {
    await pumpScreen(tester);
    scanner.onCode!('https://h.example/omni/activate#c=NOVAWORKS&t=T&l=budi.s');
    scanner.onCode!('https://h.example/omni/activate#c=NOVAWORKS&t=T&l=budi.s');
    await tester.pumpAndSettle();
    expect(popped, hasLength(1));
    final out = popped.single as ScannedInvite;
    expect(out.args.companyCode, 'NOVAWORKS');
    expect(out.args.login, 'budi.s');
  });

  testWidgets('other QR shows the message and keeps scanning',
      (tester) async {
    await pumpScreen(tester);
    scanner.onCode!('WIFI:S:Office;T:WPA;P:x;;');
    await tester.pump();
    expect(find.text('This is not an Omni HR invite QR.'), findsOneWidget);
    expect(popped, isEmpty);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('This is not an Omni HR invite QR.'), findsNothing);
    scanner.onCode!('omnihr://activate?c=NOVAWORKS&t=T');
    await tester.pumpAndSettle();
    expect(popped.single, isA<ScannedInvite>());
  });

  testWidgets('Enter code instead pops EnterCodeInstead', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Enter code instead'));
    await tester.pumpAndSettle();
    expect(popped.single, isA<EnterCodeInstead>());
  });

  testWidgets('camera refused shows the card; Enter code pops',
      (tester) async {
    await pumpScreen(tester);
    scanner.onDenied!();
    await tester.pump();
    expect(
        find.text(
            'Camera access is off. Turn it on in Settings, or enter the code instead.'),
        findsOneWidget);
    await tester.tap(find.text('Open Settings'));
    await tester.pump();
    expect(settingsOpened, 1);
    await tester.tap(find.text('Enter code'));
    await tester.pumpAndSettle();
    expect(popped.single, isA<EnterCodeInstead>());
  });

  testWidgets('back from Settings restarts the scanner', (tester) async {
    await pumpScreen(tester);
    final before = scanner.builds;
    scanner.onDenied!();
    await tester.pump();
    await tester.tap(find.text('Open Settings'));
    await tester.pump();
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byKey(const Key('fake_camera')), findsOneWidget);
    expect(scanner.builds, greaterThan(before));
  });
}
