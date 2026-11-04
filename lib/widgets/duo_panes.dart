import 'package:flutter/widgets.dart';

import '../screens/home/side_tab_column.dart';
import '../services/duo_service.dart';

/// Content width from which a screen shows two panes, one on each side of
/// the fold: the iPhone Duo open sideways leaves 867 pt next to its side
/// column; open upright (669) stays one column.
const kTwoPaneMinWidth = 820.0;

/// Space between a pane's content and the fold.
const kPaneFoldGap = 14.0;

/// Where a box [width] wide that spans the screen's content (a tab screen,
/// a pushed page) splits in two, in its own coordinates; null for one
/// column. The split follows the fold iOS reports (flat or not), else the
/// middle of the whole view: the side column belongs to the right-hand
/// half, so the content's own middle would put the split off the fold. A
/// fold that would leave either pane under 35 % (the app beside another one)
/// splits the box in the middle instead. Only sideways, and only on a
/// tablet-sized screen (shortest side 600 pt, Apple's regular size class):
/// a wide screen held upright (a tablet) and an ordinary phone held
/// sideways keep one column.
double? twoPaneSplit(BuildContext context, double width) =>
    _twoPanes(context, width)?.split;

/// [twoPaneSplit] plus the width of an active fold there (half-folded,
/// e.g. 40 pt in book pose; 0 when flat), which no pane may cover.
({double split, double fold})? _twoPanes(BuildContext context, double width) {
  if (width < kTwoPaneMinWidth) return null;
  final view = MediaQueryData.fromView(View.of(context));
  if (view.size.width <= view.size.height) return null;
  if (view.size.shortestSide < 600) return null;
  final columnLeft = sideColumnOf(view.viewPadding) == SideColumn.left
      ? view.viewPadding.left
      : 0.0;
  DuoRegion? fold;
  for (final d in DuoFeatures.geometryOf(context).divisions) {
    if (d.rect.height > d.rect.width) {
      fold = d;
      break;
    }
  }
  final x = (fold?.rect.center.dx ?? view.size.width / 2) - columnLeft;
  if (x < width * 0.35 || x > width * 0.65) return (split: width / 2, fold: 0);
  return (split: x, fold: fold != null && fold.active ? fold.rect.width : 0.0);
}

/// Padding for a pane's scroll view: 16 at the screen edge, [kPaneFoldGap]
/// at the fold.
EdgeInsets paneInsets({
  required bool left,
  double top = 16,
  double bottom = 16,
}) => EdgeInsets.fromLTRB(
  left ? 16 : kPaneFoldGap,
  top,
  left ? kPaneFoldGap : 16,
  bottom,
);

/// One page on each side of the fold when the screen is wide enough
/// ([twoPaneSplit]), else [single]. Each pane scrolls on its own.
class DuoPanes extends StatelessWidget {
  const DuoPanes({
    super.key,
    required this.single,
    required this.left,
    required this.right,
  });

  final WidgetBuilder single;
  final WidgetBuilder left;
  final WidgetBuilder right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final panes = constraints.hasBoundedWidth
            ? _twoPanes(context, constraints.maxWidth)
            : null;
        if (panes == null) return single(context);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              key: const ValueKey('duo-pane-left'),
              width: panes.split - panes.fold / 2,
              child: left(context),
            ),
            if (panes.fold > 0) SizedBox(width: panes.fold),
            Expanded(
              key: const ValueKey('duo-pane-right'),
              child: right(context),
            ),
          ],
        );
      },
    );
  }
}
