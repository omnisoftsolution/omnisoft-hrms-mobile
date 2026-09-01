import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/announcement_record.dart';
import 'package:omni_hr/widgets/announcement_detail_sheet.dart';

AnnouncementRecord _r({String kind = 'announcement', bool acked = false}) =>
    AnnouncementRecord.fromJson({
      'id': 7, 'name': 'Holiday notice', 'body': 'Dec 25 – Jan 1',
      'kind': kind, 'priority': 'normal', 'acked': acked,
    });

/// A single button that opens the real detail sheet on tap, so the
/// ack-on-open behavior is exercised through the actual public API
/// rather than a mock.
Widget _app(AnnouncementRecord announcement, VoidCallback onAckCalled) =>
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showAnnouncementDetailSheet(
              context,
              announcement: announcement,
              onAck: () async => onAckCalled(),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

void main() {
  testWidgets('unacked direct message fires onAck exactly once', (t) async {
    var acks = 0;
    await t.pumpWidget(
        _app(_r(kind: 'direct_message', acked: false), () => acks++));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(acks, 1);
  });

  testWidgets('broadcast announcement fires no ack', (t) async {
    var acks = 0;
    await t.pumpWidget(
        _app(_r(kind: 'announcement', acked: false), () => acks++));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(acks, 0);
  });

  testWidgets('already-acked direct message fires no ack', (t) async {
    var acks = 0;
    await t.pumpWidget(
        _app(_r(kind: 'direct_message', acked: true), () => acks++));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(acks, 0);
  });
}
