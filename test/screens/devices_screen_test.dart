import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/screens/profile/devices_screen.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';
import 'package:omni_hr/widgets/error_state_view.dart';

/// Scriptable API: each devicesList() call pops the next scripted result
/// (a list, or an Object to throw); the last one repeats.
class _FakeApi extends OmniMobileApi {
  _FakeApi(this.script) : super(baseUrl: '', db: '', token: '');

  final List<Object> script;
  int listCalls = 0;
  final List<String> revoked = [];

  @override
  Future<List<Map<String, dynamic>>> devicesList() async {
    final i = listCalls < script.length ? listCalls : script.length - 1;
    listCalls++;
    final r = script[i];
    if (r is List<Map<String, dynamic>>) return r;
    throw r;
  }

  @override
  Future<void> deviceRevoke(String deviceId) async => revoked.add(deviceId);
}

const _current = <String, dynamic>{
  'id': 1,
  'label': 'Budi iPhone',
  'device_id': 'dev-current',
  'trusted_since': '2026-09-01 02:00:00',
  'last_seen_at': '2026-09-20 03:30:00',
  'current': true,
};
const _other = <String, dynamic>{
  'id': 2,
  'label': '',
  'device_id': 'dev-other',
  'trusted_since': '2026-08-15 02:00:00',
  'last_seen_at': '2026-09-10 03:30:00',
  'current': false,
};

Widget _host(_FakeApi api) => MaterialApp(
      home: ChangeNotifierProvider<SessionService>(
        create: (_) => SessionService(),
        child: DevicesScreen(apiBuilder: (_) => api),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('lists devices: current row has chip, others have Revoke',
      (tester) async {
    final api = _FakeApi([
      [_current, _other]
    ]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    expect(find.text('Budi iPhone'), findsOneWidget);
    expect(find.text('Unnamed phone'), findsOneWidget);
    expect(find.textContaining('Trusted since 01 Sep 2026 · last seen'),
        findsOneWidget);
    expect(find.textContaining('Trusted since 15 Aug 2026 · last seen'),
        findsOneWidget);

    final currentTile = find.widgetWithText(ListTile, 'Budi iPhone');
    expect(find.descendant(of: currentTile, matching: find.text('This phone')),
        findsOneWidget);
    expect(find.descendant(of: currentTile, matching: find.text('Revoke')),
        findsNothing);
    final otherTile = find.widgetWithText(ListTile, 'Unnamed phone');
    expect(find.descendant(of: otherTile, matching: find.text('Revoke')),
        findsOneWidget);
    expect(find.text('This phone'), findsOneWidget);
    expect(find.text('No other phones are signed in.'), findsNothing);
  });

  testWidgets('Revoke → confirm → revokes that device and reloads',
      (tester) async {
    final api = _FakeApi([
      [_current, _other],
      [_current],
    ]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Revoke'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out this phone? It will need the password next time.'),
        findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(api.revoked, ['dev-other']);
    expect(api.listCalls, 2);
    expect(find.text('Unnamed phone'), findsNothing);
    expect(find.text('No other phones are signed in.'), findsOneWidget);
  });

  testWidgets('cancel in the confirm dialog does not revoke', (tester) async {
    final api = _FakeApi([
      [_current, _other]
    ]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Revoke'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(api.revoked, isEmpty);
    expect(api.listCalls, 1);
    expect(find.text('Unnamed phone'), findsOneWidget);
  });

  testWidgets('load error shows the error state; Retry reloads',
      (tester) async {
    final api = _FakeApi([
      ApiException('network_error'),
      [_current, _other],
    ]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    expect(find.byType(ErrorStateView), findsOneWidget);
    expect(find.textContaining('No internet connection'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(api.listCalls, 2);
    expect(find.byType(ErrorStateView), findsNothing);
    expect(find.text('Budi iPhone'), findsOneWidget);
  });

  testWidgets('an empty Char serialised as false (label, dates) does not crash',
      (tester) async {
    final api = _FakeApi([
      [
        _current,
        <String, dynamic>{
          'id': 3,
          'label': false,
          'device_id': 'dev-x',
          'trusted_since': false,
          'last_seen_at': false,
          'current': false,
        },
      ]
    ]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Unnamed phone'), findsOneWidget);
    expect(find.text('Trusted since - · last seen -'), findsOneWidget);
  });

  testWidgets('only the current device shows the empty message',
      (tester) async {
    final api = _FakeApi([
      [_current]
    ]);
    await tester.pumpWidget(_host(api));
    await tester.pumpAndSettle();

    expect(find.text('Budi iPhone'), findsOneWidget);
    expect(find.text('Revoke'), findsNothing);
    expect(find.text('No other phones are signed in.'), findsOneWidget);
  });
}
