import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:omni_hr/models/notification_record.dart';
import 'package:omni_hr/screens/notifications/notifications_screen.dart';
import 'package:omni_hr/services/notification_service.dart';
import 'package:omni_hr/services/push_native.dart';

import '../services/push_fakes.dart';

class _Bell extends NotificationService {
  _Bell(this._list);

  final List<NotificationRecord> _list;

  @override
  List<NotificationRecord> get items => _list;

  @override
  int get unreadCount => _list.where((n) => !n.read).length;

  @override
  bool get loading => false;

  @override
  String? get lastError => null;

  @override
  Future<void> refreshList() async {}
}

void main() {
  late FakeNative native;

  setUp(() {
    native = FakeNative();
    PushNative.instance = native;
  });

  tearDown(() => PushNative.instance = PushNative());

  testWidgets('opening the bell clears delivered notifications and sets the '
      'badge to the unread count (spec §6.5)', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<NotificationService>.value(
        value: _Bell([
          NotificationRecord(
            id: 1,
            kind: 'leave_approved',
            title: 'Leave approved',
          ),
          NotificationRecord(
            id: 2,
            kind: 'announcement',
            title: 'Town hall',
            read: true,
          ),
        ]),
        child: const MaterialApp(home: NotificationsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(native.calls, ['clear', 'badge 1']);
  });
}
