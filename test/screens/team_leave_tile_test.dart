import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_hr/models/team_outlook.dart';
import 'package:omni_hr/screens/leave/team_leave_row.dart';
import 'package:omni_hr/services/session_service.dart';

Widget _host(Widget child) => ChangeNotifierProvider<SessionService>(
  create: (_) => SessionService(),
  child: MaterialApp(
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  ),
);

TeamSummary _summary({int off = 2, List<Map<String, dynamic>>? faces}) =>
    TeamOutlook.fromJson({
      'summary': {
        'this_week_off': off,
        'label': 'Marketing',
        'faces':
            faces ??
            [
              {'id': 12, 'initials': 'MO'},
              {'id': 14, 'initials': 'PN'},
            ],
      },
    }).summary;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('TeamLeaveTile.subtitleFor', () {
    test('people out this week, with the team label', () {
      expect(
        TeamLeaveTile.subtitleFor(_summary(), null),
        '2 out this week · Marketing',
      );
    });

    test('nobody out this week', () {
      expect(
        TeamLeaveTile.subtitleFor(_summary(off: 0, faces: []), null),
        'No one out this week · Marketing',
      );
    });

    test('an empty reason wins over the summary', () {
      expect(
        TeamLeaveTile.subtitleFor(_summary(off: 0, faces: []), 'no_department'),
        'No team to show yet',
      );
    });

    test('nothing loaded yet: no subtitle', () {
      expect(TeamLeaveTile.subtitleFor(null, null), isNull);
    });
  });

  testWidgets('shows the title, the week line and two overlapping faces', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        TeamLeaveTile(
          summary: _summary(
            off: 3,
            faces: [
              {'id': 12, 'initials': 'MO'},
              {'id': 14, 'initials': 'PN'},
              {'id': 15, 'initials': 'RW'},
            ],
          ),
          emptyReason: null,
          onTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Team leave'), findsOneWidget);
    expect(find.text('3 out this week · Marketing'), findsOneWidget);
    expect(find.text('MO'), findsOneWidget);
    expect(find.text('PN'), findsOneWidget);
    expect(find.text('RW'), findsNothing); // at most two faces
    final mo = tester.getTopLeft(find.byKey(const ValueKey('team-leave-face-12')));
    final pn = tester.getTopLeft(find.byKey(const ValueKey('team-leave-face-14')));
    expect(pn.dx - mo.dx, 18); // 26 pt faces overlapping by 8 pt
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('an empty reason: "No team to show yet" and no faces', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        TeamLeaveTile(
          summary: _summary(off: 0, faces: []),
          emptyReason: 'no_approver',
          onTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No team to show yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('team-leave-face-12')), findsNothing);
  });

  testWidgets('NEW shows until the first open, then stays gone', (
    tester,
  ) async {
    var taps = 0;
    Widget tile() => _host(
      TeamLeaveTile(
        summary: _summary(),
        emptyReason: null,
        onTap: () => taps++,
      ),
    );
    await tester.pumpWidget(tile());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('team-leave-new')), findsOneWidget);
    expect(find.text('NEW'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('team-leave-tile')));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(find.text('NEW'), findsNothing);
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    expect(prefs.getBool('team_leave_seen||0'), isTrue);

    // The next app start (a new tile) reads the flag: no NEW.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(tile());
    await tester.pumpAndSettle();
    expect(find.text('NEW'), findsNothing);
  });

  testWidgets('NEW is per employee: another employee still sees it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'team_leave_seen|other|7': true});
    await tester.pumpWidget(
      _host(TeamLeaveTile(summary: _summary(), emptyReason: null, onTap: () {})),
    );
    await tester.pumpAndSettle();
    expect(find.text('NEW'), findsOneWidget);
  });

  testWidgets('one semantics button with the whole line', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(TeamLeaveTile(summary: _summary(), emptyReason: null, onTap: () {})),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('Team leave, new, 2 out this week · Marketing'),
      findsOneWidget,
    );
    handle.dispose();
  });
}
