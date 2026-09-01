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

/// The card's outer decorated Container is the only one with a white
/// fill (the spine bar and the "+N more" chip are colored
/// differently), so it's the reliable way to reach the card's own
/// BoxDecoration.border from the widget tree.
BoxDecoration _cardDecoration(WidgetTester t) {
  final containers = t.widgetList<Container>(find.descendant(
      of: find.byKey(const Key('announcement-card')),
      matching: find.byType(Container)));
  return containers
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .firstWhere((d) => d.color == Colors.white);
}

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

  testWidgets('unacked direct message renders unread border', (t) async {
    await t.pumpWidget(_app(AnnouncementCard(
        announcement: _r(kind: 'direct_message', acked: false),
        totalCount: 1,
        onTap: () {})));
    expect(_cardDecoration(t).border, isNotNull);
  });

  testWidgets('acked direct message renders no unread border', (t) async {
    await t.pumpWidget(_app(AnnouncementCard(
        announcement: _r(kind: 'direct_message', acked: true),
        totalCount: 1,
        onTap: () {})));
    expect(_cardDecoration(t).border, isNull);
  });

  testWidgets('totalCount 1 renders no more chip', (t) async {
    await t.pumpWidget(_app(AnnouncementCard(
        announcement: _r(), totalCount: 1, onTap: () {})));
    expect(find.textContaining('more'), findsNothing);
  });
}
