import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/auto/auto_api.dart';
import 'package:omni_hr/services/auto/auto_event.dart';
import 'package:omni_hr/services/auto/auto_event_queue.dart';
import 'package:omni_hr/services/auto/auto_sender.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

AutoEvent _e(String uid, DateTime at, {AutoKind kind = AutoKind.arrive}) =>
    AutoEvent(
      eventUid: uid,
      kind: kind,
      eventAt: at,
      isMocked: false,
      deviceId: 'd',
      appVersion: '1.36.0',
      source: AutoSource.geofence,
    );

/// Answers each post from [answer] (by event uid) and records the posts.
class _FakeApi extends AutoApi {
  _FakeApi(this.answer, {this.onPost})
    : super(baseUrl: 'http://localhost', db: 'd');

  final AutoPostResult Function(AutoEvent e) answer;
  final Future<void> Function(AutoEvent e)? onPost;
  final posted = <String>[];

  @override
  Future<AutoPostResult> postEvent(AutoEvent e) async {
    posted.add(e.eventUid);
    await onPost?.call(e);
    return answer(e);
  }
}

void main() {
  final now = DateTime.utc(2026, 10, 30, 1, 0, 0);
  final t0 = now.subtract(const Duration(minutes: 10));
  late SharedPreferencesAsync prefs;
  late AutoEventQueue queue;
  late List<int> dropped;

  AutoSender sender(_FakeApi api, {DateTime Function()? clock}) => AutoSender(
    queue: queue,
    api: () => api,
    notifyDropped: (n) async => dropped.add(n),
    prefs: prefs,
    now: clock ?? () => now,
  );

  AutoPostResult accepted(AutoEvent e) => const AutoAccepted('checked_in');

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    prefs = SharedPreferencesAsync();
    queue = AutoEventQueue(prefs: prefs);
    dropped = [];
  });

  test('posts in event_at order', () async {
    // Added out of order on purpose.
    await queue.add(_e('a-2', t0.add(const Duration(minutes: 2))));
    await queue.add(_e('a-0', t0));
    await queue.add(_e('a-1', t0.add(const Duration(minutes: 1))));
    final api = _FakeApi(accepted);
    final outcome = await sender(api).flush();
    expect(outcome, FlushOutcome.done);
    expect(api.posted, ['a-0', 'a-1', 'a-2']);
    expect(await queue.ordered(), isEmpty);
  });

  test('flush keeps order after a 409', () async {
    await queue.add(_e('a-0', t0));
    await queue.add(_e('a-1', t0.add(const Duration(minutes: 1))));
    final api = _FakeApi((e) => const AutoRetry('busy_retry'));
    final outcome = await sender(api).flush();
    expect(outcome, FlushOutcome.retryLater);
    expect(api.posted, ['a-0']); // the second is not posted
    expect((await queue.ordered()).map((e) => e.eventUid), ['a-0', 'a-1']);
  });

  test('final 4xx removes the event and continues', () async {
    await queue.add(_e('a-0', t0));
    await queue.add(_e('a-1', t0.add(const Duration(minutes: 1))));
    final api = _FakeApi(
      (e) => e.eventUid == 'a-0' ? const AutoFinal('bad_event') : accepted(e),
    );
    final outcome = await sender(api).flush();
    expect(outcome, FlushOutcome.done);
    expect(api.posted, ['a-0', 'a-1']);
    expect(await queue.ordered(), isEmpty);
  });

  test('drops stale with one notice', () async {
    final old = now.subtract(const Duration(minutes: 45));
    await queue.add(_e('a-s0', old));
    await queue.add(_e('a-s1', old.add(const Duration(minutes: 1))));
    await queue.add(_e('a-s2', old.add(const Duration(minutes: 2))));
    await queue.add(_e('a-ok', t0));
    final api = _FakeApi(accepted);
    final outcome = await sender(api).flush();
    expect(outcome, FlushOutcome.done);
    expect(dropped, [3]);
    expect(api.posted, ['a-ok']);
  });

  test('no notice when nothing is stale', () async {
    await queue.add(_e('a-0', t0));
    await sender(_FakeApi(accepted)).flush();
    expect(dropped, isEmpty);
  });

  test('key invalid keeps the event and stops', () async {
    await queue.add(_e('a-0', t0));
    await queue.add(_e('a-1', t0.add(const Duration(minutes: 1))));
    final api = _FakeApi((e) => const AutoKeyInvalid());
    final outcome = await sender(api).flush();
    expect(outcome, FlushOutcome.keyInvalid);
    expect(api.posted, ['a-0']);
    expect((await queue.ordered()).map((e) => e.eventUid), ['a-0', 'a-1']);
  });

  test('second flush inside the lease posts nothing', () async {
    await queue.add(_e('a-0', t0));
    final gate = Completer<void>();
    final slow = _FakeApi(accepted, onPost: (_) => gate.future);
    final first = sender(slow).flush();
    await pumpEventQueue(); // first flush is now waiting inside postEvent

    final other = _FakeApi(accepted);
    final second = await sender(other).flush();
    expect(second, FlushOutcome.busy);
    expect(other.posted, isEmpty);

    gate.complete();
    expect(await first, FlushOutcome.done);
  });

  test('a live lease left in prefs makes flush busy', () async {
    await queue.add(_e('a-0', t0));
    await prefs.setString(
      AutoSender.leaseKey,
      now.add(const Duration(seconds: 10)).toIso8601String(),
    );
    final api = _FakeApi(accepted);
    expect(await sender(api).flush(), FlushOutcome.busy);
    expect(api.posted, isEmpty);
    // A busy call must not drop the other holder's lease.
    expect(await prefs.getString(AutoSender.leaseKey), isNotNull);
  });

  test('an expired lease is taken over', () async {
    await queue.add(_e('a-0', t0));
    await prefs.setString(
      AutoSender.leaseKey,
      now.subtract(const Duration(seconds: 1)).toIso8601String(),
    );
    final api = _FakeApi(accepted);
    expect(await sender(api).flush(), FlushOutcome.done);
    expect(api.posted, ['a-0']);
  });

  test('the lease is released after done, retry and key invalid', () async {
    await queue.add(_e('a-0', t0));
    await sender(_FakeApi((e) => const AutoRetry('x'))).flush();
    expect(await prefs.getString(AutoSender.leaseKey), isNull);
    await sender(_FakeApi((e) => const AutoKeyInvalid())).flush();
    expect(await prefs.getString(AutoSender.leaseKey), isNull);
    await sender(_FakeApi(accepted)).flush();
    expect(await prefs.getString(AutoSender.leaseKey), isNull);
  });

  test('the lease is released when the api throws', () async {
    await queue.add(_e('a-0', t0));
    final s = AutoSender(
      queue: queue,
      api: () => throw StateError('no key'),
      notifyDropped: (n) async {},
      prefs: prefs,
      now: () => now,
    );
    await expectLater(s.flush(), throwsStateError);
    expect(await prefs.getString(AutoSender.leaseKey), isNull);
  });

  test('stores the last answer', () async {
    await queue.add(_e('a-0', t0));
    final api = _FakeApi(
      (e) => const AutoAccepted('waiting_wifi', reason: 'wifi_mismatch'),
    );
    await sender(api).flush();
    final a = await AutoSender.lastAnswer(prefs);
    expect(a, isNotNull);
    expect(a!.state, 'waiting_wifi');
    expect(a.reason, 'wifi_mismatch');
    expect(a.at, now);
  });

  test(
    'last answer is the newest accepted one, never a final or retry',
    () async {
      await queue.add(_e('a-0', t0));
      await queue.add(_e('a-1', t0.add(const Duration(minutes: 1))));
      await queue.add(_e('a-2', t0.add(const Duration(minutes: 2))));
      final api = _FakeApi(
        (e) => switch (e.eventUid) {
          'a-0' => const AutoAccepted('checked_in'),
          'a-1' => const AutoFinal('bad_event'),
          _ => const AutoRetry('busy_retry'),
        },
      );
      await sender(api).flush();
      final a = await AutoSender.lastAnswer(prefs);
      expect(a!.state, 'checked_in');
      expect(a.reason, isNull);
    },
  );

  test('no last answer when nothing was accepted', () async {
    await queue.add(_e('a-0', t0));
    await sender(_FakeApi((e) => const AutoFinal('x'))).flush();
    expect(await AutoSender.lastAnswer(prefs), isNull);
  });

  test('an event removed by another isolate meanwhile is tolerated', () async {
    await queue.add(_e('a-0', t0));
    await queue.add(_e('a-1', t0.add(const Duration(minutes: 1))));
    final api = _FakeApi(
      accepted,
      // The other isolate already removed the event we are posting.
      onPost: (e) => queue.remove(e.eventUid),
    );
    expect(await sender(api).flush(), FlushOutcome.done);
    expect(api.posted, ['a-0', 'a-1']);
  });

  test('an empty queue is done and never builds the api', () async {
    var built = 0;
    final s = AutoSender(
      queue: queue,
      api: () {
        built++;
        return _FakeApi(accepted);
      },
      notifyDropped: (n) async {},
      prefs: prefs,
      now: () => now,
    );
    expect(await s.flush(), FlushOutcome.done);
    expect(built, 0);
  });

  test('a failing notice does not stop the flush', () async {
    await queue.add(_e('a-s', now.subtract(const Duration(minutes: 45))));
    await queue.add(_e('a-0', t0));
    final api = _FakeApi(accepted);
    final s = AutoSender(
      queue: queue,
      api: () => api,
      notifyDropped: (n) async => throw StateError('no plugin'),
      prefs: prefs,
      now: () => now,
    );
    expect(await s.flush(), FlushOutcome.done);
    expect(api.posted, ['a-0']);
  });
}
