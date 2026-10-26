import 'package:flutter/material.dart';

import '../../core/omni_colors.dart';

/// Which side of the screen holds the system's vertical bar column, if any.
///
/// iPhone Duo (iOS 27.1) moves the status bar and camera into an 84 pt
/// column along the camera side, on the closed cover display and when the
/// open phone is held sideways; the safe area reports that column as a
/// side inset. Native tab bars move into it on their own — the app's own
/// bottom bar does not, so [SideColumnHost] keeps the whole app left of the
/// column and draws [HomeShell]'s tabs in it.
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

/// What [HomeShell] wants in the column: its tabs and the selected one.
class SideTabsSpec {
  const SideTabsSpec({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<SideTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
}

/// Sits right under [MaterialApp] (its `builder`). On iPhone Duo, closed or
/// open sideways, the app gets the space left of the system column, as iOS
/// gives it to native apps: every route — tab screens, full-screen pages,
/// sheets, sign-in — is laid out there with that side's inset removed, so
/// nothing lands under the status bar or the camera. The column itself
/// shows the tabs [HomeShell] offers (none before sign-in).
///
/// The tree has the same shape with and without the column, so folding or
/// unfolding the phone never rebuilds the app's Navigator (state, tabs and
/// pushed pages survive).
class SideColumnHost extends StatefulWidget {
  const SideColumnHost({super.key, required this.child});

  final Widget child;

  /// The column side below this host ([SideColumn.none] without a host).
  static SideColumn sideOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SideColumnScope>()?.side ??
      SideColumn.none;

  static SideColumnHostState? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_SideColumnScope>()?.host;

  @override
  State<SideColumnHost> createState() => SideColumnHostState();
}

class SideColumnHostState extends State<SideColumnHost> {
  final ValueNotifier<SideTabsSpec?> _tabs = ValueNotifier(null);
  Object? _owner;

  @visibleForTesting
  SideTabsSpec? get offered => _tabs.value;

  /// [owner] shows [spec] in the column. Called from a build, so the
  /// change lands after the frame.
  void offer(Object owner, SideTabsSpec spec) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _owner = owner;
      _tabs.value = spec;
    });
  }

  /// [owner] is gone; its tabs leave the column.
  void withdraw(Object owner) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_owner, owner)) return;
      _owner = null;
      _tabs.value = null;
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final side = sideColumnOf(media.viewPadding);
    final width = switch (side) {
      SideColumn.right => media.viewPadding.right,
      SideColumn.left => media.viewPadding.left,
      SideColumn.none => 0.0,
    };
    final column = SizedBox(
      key: const ValueKey('side-column'),
      width: width,
      child: side == SideColumn.none
          ? null
          : ColoredBox(
              color: context.omni.background,
              child: ValueListenableBuilder<SideTabsSpec?>(
                valueListenable: _tabs,
                builder: (context, spec, _) => spec == null
                    ? const SizedBox.expand()
                    : SideTabColumn(
                        width: width,
                        bottomInset: media.viewPadding.bottom,
                        tabs: spec.tabs,
                        selectedIndex: spec.selectedIndex,
                        onSelected: spec.onSelected,
                      ),
              ),
            ),
    );
    final app = Expanded(
      child: MediaQuery.removePadding(
        context: context,
        removeLeft: side == SideColumn.left,
        removeRight: side == SideColumn.right,
        child: _SideColumnScope(host: this, side: side, child: widget.child),
      ),
    );
    return Row(
      textDirection: TextDirection.ltr,
      children: side == SideColumn.left ? [column, app] : [app, column],
    );
  }
}

class _SideColumnScope extends InheritedWidget {
  const _SideColumnScope({
    required this.host,
    required this.side,
    required super.child,
  });

  final SideColumnHostState host;
  final SideColumn side;

  @override
  bool updateShouldNotify(_SideColumnScope old) => old.side != side;
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
      // No Tooltip: the column sits above the app's Navigator, so there is
      // no Overlay to show one in.
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
    );
  }
}
