import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/auto/auto_event.dart';
import 'package:omni_hr/services/auto/auto_event_queue.dart';
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

void main() {
  final t0 = DateTime.utc(2026, 10, 30, 1, 0, 0);

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('ordered sorts by eventAt', () async {
    final q = AutoEventQueue();
    await q.add(_e('a-2', t0.add(const Duration(minutes: 2))));
    await q.add(_e('a-0', t0));
    await q.add(_e('a-1', t0.add(const Duration(minutes: 1))));
    final got = await q.ordered();
    expect(got.map((e) => e.eventUid), ['a-0', 'a-1', 'a-2']);
  });

  test('add ignores a repeated uid', () async {
    final q = AutoEventQueue();
    await q.add(_e('a-1', t0));
    await q.add(_e('a-1', t0.add(const Duration(minutes: 5))));
    final got = await q.ordered();
    expect(got, hasLength(1));
    expect(got.single.eventAt, t0);
  });

  test('21st event drops the oldest', () async {
    final q = AutoEventQueue();
    for (var i = 0; i < AutoEventQueue.maxEvents + 1; i++) {
      await q.add(_e('a-$i', t0.add(Duration(minutes: i))));
    }
    final got = await q.ordered();
    expect(got, hasLength(AutoEventQueue.maxEvents));
    expect(got.first.eventUid, 'a-1');
    expect(got.last.eventUid, 'a-20');
  });

  test('takeStale returns and removes events older than 30 min', () async {
    final q = AutoEventQueue();
    final now = t0.add(const Duration(hours: 1));
    await q.add(_e('old', now.subtract(const Duration(minutes: 31))));
    await q.add(_e('edge', now.subtract(const Duration(minutes: 30))));
    await q.add(_e('fresh', now.subtract(const Duration(minutes: 5))));
    final stale = await q.takeStale(now);
    expect(stale.map((e) => e.eventUid), ['old']);
    expect((await q.ordered()).map((e) => e.eventUid), ['edge', 'fresh']);
  });

  test('remove deletes one uid; unknown uid is a no-op', () async {
    final q = AutoEventQueue();
    await q.add(_e('a-1', t0));
    await q.add(_e('a-2', t0.add(const Duration(minutes: 1))));
    await q.remove('a-1');
    await q.remove('nope');
    expect((await q.ordered()).map((e) => e.eventUid), ['a-2']);
  });

  test('clear empties the queue', () async {
    final q = AutoEventQueue();
    await q.add(_e('a-1', t0));
    await q.clear();
    expect(await q.ordered(), isEmpty);
  });

  test('a second instance (other isolate) sees the same queue', () async {
    await AutoEventQueue().add(_e('a-1', t0));
    expect((await AutoEventQueue().ordered()).single.eventUid, 'a-1');
  });

  test('corrupt stored value reads as empty and add recovers', () async {
    await SharedPreferencesAsync().setString('omni_auto_queue', '{not json');
    final q = AutoEventQueue();
    expect(await q.ordered(), isEmpty);
    await q.add(_e('a-1', t0));
    expect((await q.ordered()).single.eventUid, 'a-1');
  });

  test('concurrent adds in one isolate are not lost', () async {
    final q = AutoEventQueue();
    await Future.wait([
      for (var i = 0; i < 10; i++)
        q.add(_e('a-$i', t0.add(Duration(minutes: i)))),
    ]);
    expect(await q.ordered(), hasLength(10));
  });
}
