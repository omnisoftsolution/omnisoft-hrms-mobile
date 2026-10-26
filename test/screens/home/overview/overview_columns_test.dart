import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/screens/home/overview/team_overview_screen.dart';

Widget _box(String key) =>
    SizedBox(key: ValueKey(key), height: 100, child: Text(key));

Future<void> _pump(
  WidgetTester tester,
  double width, {
  List<List<Widget>>? blocks,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: OverviewColumns(
              blocks:
                  blocks ??
                  [
                    [_box('tile')],
                    [_box('who')],
                    [_box('forYou')],
                  ],
            ),
          ),
        ),
      ),
    ),
  );
}

double _x(WidgetTester tester, String key) =>
    tester.getTopLeft(find.byKey(ValueKey(key))).dx;
double _y(WidgetTester tester, String key) =>
    tester.getTopLeft(find.byKey(ValueKey(key))).dy;

void main() {
  testWidgets('a phone stacks the blocks in one column', (tester) async {
    await _pump(tester, 358);
    expect(_x(tester, 'who'), _x(tester, 'tile'));
    expect(_x(tester, 'forYou'), _x(tester, 'tile'));
    expect(_y(tester, 'who'), greaterThan(_y(tester, 'tile')));
    expect(_y(tester, 'forYou'), greaterThan(_y(tester, 'who')));
  });

  testWidgets('iPhone Duo open upright: Who\'s out and For you share the '
      'second column', (tester) async {
    await _pump(tester, 637);
    expect(_x(tester, 'who'), greaterThan(_x(tester, 'tile')));
    expect(_x(tester, 'forYou'), _x(tester, 'who'));
    expect(_y(tester, 'who'), _y(tester, 'tile'));
    expect(_y(tester, 'forYou'), greaterThan(_y(tester, 'who')));
  });

  testWidgets('iPhone Duo open sideways: three columns', (tester) async {
    await _pump(tester, 835);
    expect(_x(tester, 'who'), greaterThan(_x(tester, 'tile')));
    expect(_x(tester, 'forYou'), greaterThan(_x(tester, 'who')));
    expect(_y(tester, 'forYou'), _y(tester, 'tile'));
  });

  testWidgets('an empty block takes no column', (tester) async {
    await _pump(
      tester,
      835,
      blocks: [
        [],
        [_box('who')],
        [_box('forYou')],
      ],
    );
    expect(_x(tester, 'forYou'), greaterThan(_x(tester, 'who')));
    expect(
      tester.getSize(find.byKey(const ValueKey('who'))).width,
      closeTo((835 - 16) / 2, 0.5),
    );
  });
}
