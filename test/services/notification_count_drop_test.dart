import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/notification_record.dart';
import 'package:omni_hr/services/notification_service.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';

import 'push_fakes.dart';

/// The bell's server as NotificationService polls it.
class _BellApi extends OmniMobileApi {
  _BellApi() : super(baseUrl: 'https://acme.test', db: 'acme', token: 'tok-1');

  List<NotificationRecord> items = const [];
  int listCalls = 0;

  @override
  Future<int> getUnreadNotificationCount() async =>
      items.where((n) => !n.read).length;

  @override
  Future<List<NotificationRecord>> getNotifications() async {
    listCalls++;
    return items;
  }
}

NotificationRecord n(int id, {bool read = false}) => NotificationRecord(
  id: id,
  kind: 'leave_approval_requested',
  title: 'Approval needed',
  read: read,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the unread count dropping on a poll reloads the list and flags the '
      'drop once (F3: a request closed elsewhere)', () async {
    final api = _BellApi()..items = [n(12), n(11)];
    final svc = NotificationService(apiFor: (_) => api);
    svc.start(await signedInSession());
    await flush();
    await svc.refreshList();
    expect(svc.items.where((e) => !e.read).map((e) => e.id), [12, 11]);
    expect(svc.consumeUnreadDrop(), isFalse);

    // Someone else approved request 12: the server marked its row read.
    api.items = [n(12, read: true), n(11)];
    final calls = api.listCalls;
    expect(await svc.refreshNow(), isTrue);
    expect(api.listCalls, calls + 1);
    expect(svc.unreadCount, 1);
    expect(svc.items.where((e) => !e.read).map((e) => e.id), [11]);
    expect(svc.consumeUnreadDrop(), isTrue);
    expect(svc.consumeUnreadDrop(), isFalse);
    expect(svc.consumeFreshArrivals(), isEmpty);
    svc.stop();
  });

  test('an unchanged count reloads nothing and flags no drop', () async {
    final api = _BellApi()..items = [n(11)];
    final svc = NotificationService(apiFor: (_) => api);
    svc.start(await signedInSession());
    await flush();
    final calls = api.listCalls;
    await svc.refreshNow();
    expect(api.listCalls, calls);
    expect(svc.consumeUnreadDrop(), isFalse);
    svc.stop();
  });
}
