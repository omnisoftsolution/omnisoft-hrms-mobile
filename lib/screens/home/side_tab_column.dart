import 'package:flutter/material.dart';

import '../../core/omni_colors.dart';

/// Which side of the screen holds the system's vertical bar column, if any.
///
/// iPhone Duo (iOS 27.1) moves the status bar and camera into an 84 pt
/// column along the camera side, on the closed cover display and when the
/// open phone is held sideways; the safe area reports that column as a
/// side inset. Native tab bars move into it on their own — the app's own
/// bottom bar does not, so [HomeShell] draws its tabs there instead.
///
/// A plain iPhone held sideways has insets on both sides (the notch or
/// island on one, a mirror on the other); only a wide, lopsided inset
/// counts as the column.
enum SideColumn { none, left, right }

/// Minimum side inset read as the Duo column (it reports 84 pt).
const kSideColumnMinInset = 60.0;

SideColumn sideColumnOf(EdgeInsets viewPadding) {
  final l = viewPadding.left;
  final r = viewPadding.right;
  if ((l - r).abs() < 40) return SideColumn.none;
  if (r >= kSideColumnMinInset && r > l) return SideColumn.right;
  if (l >= kSideColumnMinInset && l > r) return SideColumn.left;
  return SideColumn.none;
}

/// One tab of the side pill: the same icons and label as the bottom bar.
class SideTab {
  const SideTab({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final Widget icon;
  final Widget selectedIcon;
  final String label;
}

/// The tabs as a vertical pill inside the system column, under the status
/// bar and near the thumb (bottom of the column), as iOS lays out its own
/// tab bars on iPhone Duo. [width] is the column's inset; [bottomInset]
/// keeps the pill above the home indicator.
class SideTabColumn extends StatelessWidget {
  const SideTabColumn({
    super.key,
    required this.width,
    required this.bottomInset,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  final double width;
  final double bottomInset;
  final List<SideTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.omni;
    return SizedBox(
      width: width,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset + 16),
          child: Container(
            width: 60,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: c.bar,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: c.lineSoft),
              boxShadow: c.cardShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < tabs.length; i++) ...[
                  if (i > 0) const SizedBox(height: 4),
                  _SideTabButton(
                    tab: tabs[i],
                    selected: i == selectedIndex,
                    onTap: () => onSelected(i),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SideTabButton extends StatelessWidget {
  const _SideTabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final SideTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omni;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      excludeSemantics: true,
      child: Tooltip(
        message: tab.label,
        child: Material(
          color: selected ? c.navIndicator : Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 48,
              height: 48,
              child: IconTheme.merge(
                data: IconThemeData(color: selected ? c.accent : c.textMuted),
                child: Center(child: selected ? tab.selectedIcon : tab.icon),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
