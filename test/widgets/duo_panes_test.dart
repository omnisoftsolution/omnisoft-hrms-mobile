import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/services/duo_service.dart';
import 'package:omni_hr/widgets/duo_panes.dart';

/// The view the way iOS reports it: [size] with an 84 pt column inset on
/// one side when the iPhone Duo puts its status there.
void _view(
  WidgetTester tester,
  Size size, {
  double right = 0,
  double left = 0,
}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewPadding = FakeViewPadding(right: right, left: left);
  tester.view.padding = FakeViewPadding(right: right, left: left);
}

/// [DuoPanes] laid out [width] wide from [x], the way a tab screen sits
/// next to the side column.
Widget _panes(double width, {double x = 0}) => MaterialApp(
  home: Stack(
    children: [
      Positioned(
        left: x,
        top: 0,
        bottom: 0,
        width: width,
        child: DuoPanes(
          single: (_) => const SizedBox(key: ValueKey('single')),
          left: (_) => const SizedBox.expand(key: ValueKey('left')),
          right: (_) => const SizedBox.expand(key: ValueKey('right')),
        ),
      ),
    ],
  ),
);

void main() {
  testWidgets('a phone keeps one column', (tester) async {
    addTearDown(tester.view.reset);
    _view(tester, const Size(390, 844));
    await tester.pumpWidget(_panes(390));
    expect(find.byKey(const ValueKey('single')), findsOneWidget);
    expect(find.byKey(const ValueKey('left')), findsNothing);
  });

  testWidgets('Duo open upright (669 wide) keeps one column', (tester) async {
    addTearDown(tester.view.reset);
    _view(tester, const Size(669, 951));
    await tester.pumpWidget(_panes(669));
    expect(find.byKey(const ValueKey('single')), findsOneWidget);
  });

  testWidgets('Duo open sideways: the split sits on the middle of the whole '
      'screen, not of the space left of the column', (tester) async {
    addTearDown(tester.view.reset);
    _view(tester, const Size(951, 669), right: 84);
    await tester.pumpWidget(_panes(867));
    final left = tester.getRect(find.byKey(const ValueKey('left')));
    final right = tester.getRect(find.byKey(const ValueKey('right')));
    expect(left.left, 0);
    expect(left.right, 475.5);
    expect(right.left, 475.5);
    expect(right.right, 867);
  });

  testWidgets('the fold iOS reports wins over the middle', (tester) async {
    addTearDown(tester.view.reset);
    final service = DuoService.instance;
    addTearDown(() => service.debugGeometry = DuoGeometry.none);
    _view(tester, const Size(951, 669), right: 84);
    // Flat: the division is reported inactive and zero wide.
    service.debugGeometry = DuoGeometry.fromMap(const {
      'available': true,
      'hinge': 'open',
      'divisions': [
        [470, 0, 0, 669, 0],
      ],
      'occlusions': [],
    });
    await tester.pumpWidget(DuoFeatures(child: _panes(867)));
    await tester.pump();
    expect(tester.getRect(find.byKey(const ValueKey('left'))).right, 470);
  });

  testWidgets('a column on the left moves the content, not the fold', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    _view(tester, const Size(951, 669), left: 84);
    await tester.pumpWidget(_panes(867, x: 84));
    expect(tester.getRect(find.byKey(const ValueKey('left'))).right, 475.5);
  });

  testWidgets('a fold far from this box (another app beside it) falls back '
      'to its own middle', (tester) async {
    addTearDown(tester.view.reset);
    _view(tester, const Size(2000, 1000));
    await tester.pumpWidget(_panes(900));
    expect(tester.getRect(find.byKey(const ValueKey('left'))).right, 450);
  });

  test('pane insets keep 16 at the screen edge and 14 at the fold', () {
    expect(paneInsets(left: true), const EdgeInsets.fromLTRB(16, 16, 14, 16));
    expect(paneInsets(left: false), const EdgeInsets.fromLTRB(14, 16, 16, 16));
    expect(
      paneInsets(left: true, top: 0, bottom: 40),
      const EdgeInsets.fromLTRB(16, 0, 14, 40),
    );
  });
}
