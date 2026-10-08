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

  group('refreshMeIfStale (M8)', () {
    /// Counts /me calls; each answers with [answer] (null = fails).
    SessionService counting(List<int> calls, {Map<String, dynamic>? answer}) {
      final s = _CountingSession(calls, answer);
      return s;
    }

    test('asks once, then not again within 30 s, then again after', () async {
      final calls = <int>[];
      final s = counting(calls, answer: me({
        'leave_approvals': {'enabled': true, 'pending_count': 1},
      }));
      var t = DateTime(2026, 10, 8, 9);
      s.clock = () => t;

      expect(await s.refreshMeIfStale(), isTrue);
      expect(s.leaveApprovalsEnabled, isTrue);
      t = t.add(const Duration(seconds: 29));
      expect(await s.refreshMeIfStale(), isFalse);
      expect(calls.length, 1);
      t = t.add(const Duration(seconds: 2));
      expect(await s.refreshMeIfStale(), isTrue);
      expect(calls.length, 2);
    });

    test('any /me counts: a resume refresh holds off the Leave tab', () async {
      final calls = <int>[];
      final s = counting(calls, answer: me());
      final t = DateTime(2026, 10, 8, 9);
      s.clock = () => t;
      await s.refreshMe(); // e.g. app resume
      expect(await s.refreshMeIfStale(), isFalse);
      expect(calls.length, 1);
    });

    test('a failure does not start the wait', () async {
      final calls = <int>[];
      final s = counting(calls); // /me fails
      final t = DateTime(2026, 10, 8, 9);
      s.clock = () => t;
      expect(await s.refreshMeIfStale(), isFalse);
      expect(await s.refreshMeIfStale(), isFalse);
      expect(calls.length, 2);
    });

    test('a new login resets the wait (/login has no approvals block)',
        () async {
      final calls = <int>[];
      final s = counting(calls, answer: me());
      final t = DateTime(2026, 10, 8, 9);
      s.clock = () => t;
      await s.refreshMeIfStale();
      await s.saveLoginResponse({
        'access_token': 'tok',
        'user': {'id': 9, 'login': 'a@b.c', 'name': 'A'},
        'employee': {'id': 6, 'name': 'A'},
      });
      expect(await s.refreshMeIfStale(), isTrue);
      expect(calls.length, 2);
    });
  });
}

/// refreshMe goes through the real refreshMeWith with a fake /me.
class _CountingSession extends SessionService {
  _CountingSession(this.calls, this.answer);

  final List<int> calls;
  final Map<String, dynamic>? answer;

  @override
  Future<bool> refreshMe() => refreshMeWith(_FakeApi(() async {
        calls.add(calls.length);
        final a = answer;
        if (a == null) throw ApiException('network_error');
        return a;
      }));
}
