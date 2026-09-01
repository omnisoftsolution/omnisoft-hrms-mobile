import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/announcement_record.dart';
import 'package:omni_hr/widgets/announcement_card.dart';

AnnouncementRecord _r({String kind = 'announcement',
        String priority = 'normal', bool acked = false}) =>
    AnnouncementRecord.fromJson({
      'id': 1, 'name': 'Holiday notice', 'body': 'Dec 25 – Jan 1',
      'kind': kind, 'priority': priority, 'acked': acked,
    });

Widget _app(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders title, body, eyebrow and taps', (t) async {
    var taps = 0;
    await t.pumpWidget(_app(AnnouncementCard(
        announcement: _r(), totalCount: 1, onTap: () => taps++)));
    expect(find.text('Holiday notice'), findsOneWidget);
    expect(find.text('Dec 25 – Jan 1'), findsOneWidget);
    expect(find.text('ANNOUNCEMENT · HR'), findsOneWidget);
    await t.tap(find.byKey(const Key('announcement-card')));
    expect(taps, 1);
  });

  testWidgets('direct message eyebrow + more chip', (t) async {
    await t.pumpWidget(_app(AnnouncementCard(
        announcement: _r(kind: 'direct_message'),
        totalCount: 3,
        onTap: () {})));
    expect(find.text('MESSAGE FROM HR'), findsOneWidget);
    expect(find.text('+2 more'), findsOneWidget);
  });
}
