import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:omni_hr/models/notification_record.dart';
import 'package:omni_hr/screens/notifications/notifications_screen.dart';
import 'package:omni_hr/services/notification_service.dart';
import 'package:omni_hr/services/push_service.dart';
import 'package:omni_hr/services/session_service.dart';

import '../services/push_fakes.dart';

class _Bell extends NotificationService {
  _Bell(this._list);

  final List<NotificationRecord> _list;

  /// The next refreshList waits for it (used once, then cleared).
  Completer<void>? listGate;

  @override
  List<NotificationRecord> get items => _list;

  @override
  int get unreadCount => _list.where((n) => !n.read).length;

  @override
  bool get loading => false;

  /// What the last refreshList left behind (null: the list came).
  String? error;

  @override
  String? get lastError => error;

  @override
  Future<void> refreshList() async {
    final gate = listGate;
    listGate = null;
    if (gate != null) await gate.future;
  }
}

void main() {
  late FakeNative native;
  late _Bell bell;
  late SessionService session;
  late PushService push;

  setUp(() {
    native = FakeNative();
    bell = _Bell([
      NotificationRecord(id: 1, kind: 'leave_approved', title: 'Leave approved'),
      NotificationRecord(
        id: 2,
        kind: 'announcement',
        title: 'Town hall',
        read: true,
      ),
    ]);
  });

  /// A signed-in PushService wired to the session, as main() does.
  Future<void> signedIn(WidgetTester tester) => tester.runAsync(() async {
    session = await signedInSession();
    push = pushService(
      messaging: FakeMessaging(),
      log: PushApiLog(),
      pushNative: native,
    );
    session.onSessionClearing = push.onSessionCleared;
    await push.onSignedIn(session);
    native.calls.clear();
  });

  Widget app(Widget home) => MultiProvider(
    providers: [
      ChangeNotifierProvider<NotificationService>.value(value: bell),
      ChangeNotifierProvider<PushService>.value(value: push),
    ],
    child: MaterialApp(home: home),
  );

  testWidgets('opening the bell clears delivered notifications and sets the '
      'badge to the unread count (spec §6.5)', (tester) async {
    await signedIn(tester);
    await tester.pumpWidget(app(const NotificationsScreen()));
    await tester.pumpAndSettle();
    expect(native.calls, ['clear', 'badge 1']);
  });

  testWidgets('a bell that could not load (offline) clears delivered '
      'notifications but leaves the badge alone', (tester) async {
    await signedIn(tester);
    bell.error = 'network_error';
    await tester.pumpWidget(app(const NotificationsScreen()));
    await tester.pumpAndSettle();
    expect(native.calls, ['clear']);
  });

  testWidgets('a sign-out while the bell loads: no stale badge afterwards', (
    tester,
  ) async {
    await signedIn(tester);
    final gate = Completer<void>();
    bell.listGate = gate;
    await tester.pumpWidget(app(const NotificationsScreen()));
    await tester.pump();
    await tester.runAsync(() => session.signOut());
    gate.complete();
    await tester.pumpAndSettle();
    // Only the sign-out's own clean-up; the bell added nothing.
    expect(native.calls, ['clear', 'badge 0']);
  });

  testWidgets('a bell closed while it loads clears nothing', (tester) async {
    await signedIn(tester);
    final gate = Completer<void>();
    bell.listGate = gate;
    await tester.pumpWidget(app(const NotificationsScreen()));
    await tester.pump();
    await tester.pumpWidget(app(const SizedBox()));
    gate.complete();
    await tester.pumpAndSettle();
    expect(native.calls, isEmpty);
  });
}
