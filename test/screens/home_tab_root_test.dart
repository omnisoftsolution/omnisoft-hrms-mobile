import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/screens/home/home_tab_root.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';

class _FakeApi extends OmniMobileApi {
  _FakeApi(this.reply)
      : super(baseUrl: 'https://example.test', db: 'testdb', token: '');

  final Map<String, dynamic> reply;

  @override
  Future<Map<String, dynamic>> me() async => reply;
}

Map<String, dynamic> _body({bool? kioskOnly}) => {
      'success': true,
      'access_token': 'A',
      'auth_source': 'omni',
      'user': {'id': 9, 'login': 'a@b.c', 'name': 'A'},
      'employee': {
        'id': 6,
        'name': 'A',
        'attendance_kiosk_only': ?kioskOnly,
      },
    };

Widget _host(SessionService session) =>
    ChangeNotifierProvider<SessionService>.value(
      value: session,
      child: const MaterialApp(
        home: HomeTabRoot(
          classicHome: Text('CLASSIC HOME'),
          myDay: Text('MY DAY HOME'),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('classic home by default (older connector, no flag)',
      (tester) async {
    final session = SessionService();
    await tester.runAsync(() => session.saveLoginResponse(_body()));
    await tester.pumpWidget(_host(session));
    expect(find.text('CLASSIC HOME'), findsOneWidget);
    expect(find.text('MY DAY HOME'), findsNothing);
  });

  testWidgets('My day when the session says kiosk-only', (tester) async {
    final session = SessionService();
    await tester
        .runAsync(() => session.saveLoginResponse(_body(kioskOnly: true)));
    await tester.pumpWidget(_host(session));
    expect(find.text('MY DAY HOME'), findsOneWidget);
    expect(find.text('CLASSIC HOME'), findsNothing);
  });

  testWidgets('switches both ways when /me changes the flag', (tester) async {
    final session = SessionService();
    await tester.runAsync(() => session.saveLoginResponse(_body()));
    await tester.pumpWidget(_host(session));
    expect(find.text('CLASSIC HOME'), findsOneWidget);

    await tester.runAsync(
        () => session.refreshMeWith(_FakeApi(_body(kioskOnly: true))));
    await tester.pump();
    expect(find.text('MY DAY HOME'), findsOneWidget);

    await tester.runAsync(
        () => session.refreshMeWith(_FakeApi(_body(kioskOnly: false))));
    await tester.pump();
    expect(find.text('CLASSIC HOME'), findsOneWidget);
  });
}
