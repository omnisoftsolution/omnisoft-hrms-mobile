import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/services/omni_mobile_api.dart';
import 'package:omni_hr/services/session_service.dart';

/// /me returns whatever [onMe] says; nothing touches the network.
class _FakeApi extends OmniMobileApi {
  _FakeApi(this.onMe) : super(baseUrl: 'https://example.test', db: 'testdb', token: '');

  final Future<Map<String, dynamic>> Function() onMe;

  @override
  Future<Map<String, dynamic>> me() => onMe();
}

Map<String, dynamic> me([Map<String, dynamic> extra = const {}]) => {
      'success': true,
      'auth_source': 'omni',
      'user': {'id': 9, 'login': 'a@b.c', 'name': 'A'},
      'employee': {'id': 6, 'name': 'A'},
      ...extra,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('defaults to disabled with nothing stored', () async {
    final s = SessionService();
    await s.load();
    expect(s.leaveApprovalsEnabled, isFalse);
    expect(s.leaveApprovalsPendingCount, 0);
  });

  test('refreshMe stores the block, notifies and persists', () async {
    final s = SessionService();
    var notified = 0;
    s.addListener(() => notified++);
    final ok = await s.refreshMeWith(_FakeApi(() async => me({
          'leave_approvals': {'enabled': true, 'pending_count': 3},
        })));
    expect(ok, isTrue);
    expect(s.leaveApprovalsEnabled, isTrue);
    expect(s.leaveApprovalsPendingCount, 3);
    expect(notified, greaterThan(0));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('leave_approvals_enabled'), isTrue);
    expect(prefs.getInt('leave_approvals_pending_count'), 3);

    final again = SessionService();
    await again.load();
    expect(again.leaveApprovalsEnabled, isTrue);
    expect(again.leaveApprovalsPendingCount, 3);
  });

  test('old connector: a /me without the key disables approvals', () async {
    final s = SessionService();
    await s.refreshMeWith(_FakeApi(() async => me({
          'leave_approvals': {'enabled': true, 'pending_count': 2},
        })));
    expect(s.leaveApprovalsEnabled, isTrue);

    final ok = await s.refreshMeWith(_FakeApi(() async => me()));
    expect(ok, isTrue);
    expect(s.leaveApprovalsEnabled, isFalse);
    expect(s.leaveApprovalsPendingCount, 0);
  });

  test('a pre-identity connector (no auth_source, no block) is disabled',
      () async {
    final s = SessionService();
    final ok = await s.refreshMeWith(_FakeApi(() async => {
          'success': true,
          'user': {'id': 9, 'login': 'a@b.c', 'name': 'A'},
          'employee': {'id': 6, 'name': 'A'},
        }));
    expect(ok, isTrue);
    expect(s.leaveApprovalsEnabled, isFalse);
    expect(s.leaveApprovalsPendingCount, 0);
  });

  test('a malformed block never throws and reads as disabled', () async {
    final s = SessionService();
    for (final bad in <Object?>[
      false,
      'yes',
      <String, dynamic>{'enabled': 'yes', 'pending_count': 4},
      <String, dynamic>{'enabled': true, 'pending_count': 'many'},
    ]) {
      await s.updateLeaveApprovalsFromMe({'leave_approvals': bad});
      expect(s.leaveApprovalsPendingCount, 0, reason: '$bad');
    }
    await s.updateLeaveApprovalsFromMe({'leave_approvals': 'yes'});
    expect(s.leaveApprovalsEnabled, isFalse);
  });

  test('a disabled block never carries a count', () async {
    final s = SessionService();
    await s.updateLeaveApprovalsFromMe({
      'leave_approvals': {'enabled': false, 'pending_count': 5},
    });
    expect(s.leaveApprovalsEnabled, isFalse);
    expect(s.leaveApprovalsPendingCount, 0);
  });

  test('a failed /me keeps the cached values', () async {
    final s = SessionService();
    await s.updateLeaveApprovalsFromMe({
      'leave_approvals': {'enabled': true, 'pending_count': 4},
    });
    final ok = await s.refreshMeWith(
        _FakeApi(() async => throw ApiException('network_error')));
    expect(ok, isFalse);
    expect(s.leaveApprovalsEnabled, isTrue);
    expect(s.leaveApprovalsPendingCount, 4);
  });

  test('clearSession wipes the values and the stored keys', () async {
    final s = SessionService();
    await s.updateLeaveApprovalsFromMe({
      'leave_approvals': {'enabled': true, 'pending_count': 4},
    });
    await s.clearSession();
    expect(s.leaveApprovalsEnabled, isFalse);
    expect(s.leaveApprovalsPendingCount, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('leave_approvals_enabled'), isFalse);
    expect(prefs.containsKey('leave_approvals_pending_count'), isFalse);
  });
}
