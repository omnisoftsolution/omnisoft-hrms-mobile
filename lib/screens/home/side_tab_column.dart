import 'dart:math' as math;
import 'dart:ui' show DisplayFeature;

import 'package:flutter/material.dart';

import '../../core/omni_colors.dart';
import '../../services/duo_service.dart';

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

/// One icon button a screen's app bar moves into the column (Apple, iPhone
/// Duo: toolbar buttons with an icon — back, close, bell, profile — sit at
/// the top of the side column under the status; titles, text buttons and
/// segmented controls stay in the screen).
class SideTool {
  const SideTool({
    required this.label,
    required this.onTap,
    this.icon,
    this.child,
    this.badge = 0,
  }) : assert(icon != null || child != null);

  /// The screen-reader label (the column has no Overlay for a Tooltip).
  final String label;
  final VoidCallback onTap;

  /// A glyph drawn on the column's glass button…
  final Widget? icon;

  /// …or a widget drawn as is (the profile avatar).
  final Widget? child;

  /// Unread count on the button's corner; 0 = none.
  final int badge;
}

/// Room left at the top of the column for the system's camera, clock and
/// status icons when iOS gives no bar frame (`DuoGeometry.barLeft` /
/// `barRight`, which the column normally follows). On the iOS 27.1
/// simulator the bar starts at 170 pt closed and 120 pt open sideways; the
/// larger one is the safe default.
const kSideStatusHeight = 170.0;

/// Width of the column's buttons; the bar frame iOS reports is asked for
/// this extent.
const kSideButtonSize = 48.0;

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
  final ValueNotifier<List<SideTool>?> _tools = ValueNotifier(null);
  Object? _toolsOwner;

  @visibleForTesting
  SideTabsSpec? get offered => _tabs.value;

  @visibleForTesting
  List<SideTool>? get offeredTools => _tools.value;

  /// [owner] (the screen on top) shows [tools] at the top of the column.
  /// Called from a build, so the change lands after the frame.
  void offerTools(Object owner, List<SideTool> tools) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _toolsOwner = owner;
      _tools.value = tools;
    });
  }

  /// [owner] is gone or covered; its buttons leave the column.
  void withdrawTools(Object owner) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_toolsOwner, owner)) return;
      _toolsOwner = null;
      _tools.value = null;
    });
  }

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
    _tools.dispose();
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
    final bar = _barIn(DuoFeatures.geometryOf(context), side, width, media);
    final column = SizedBox(
      key: const ValueKey('side-column'),
      width: width,
      child: side == SideColumn.none
          ? null
          : ColoredBox(
              color: context.omni.background,
              child: Column(
                children: [
                  ValueListenableBuilder<List<SideTool>?>(
                    valueListenable: _tools,
                    builder: (context, tools, _) => SideToolColumn(
                      tools: tools ?? const [],
                      width: width,
                      bar: bar,
                    ),
                  ),
                  Expanded(
                    child: ValueListenableBuilder<SideTabsSpec?>(
                      valueListenable: _tabs,
                      builder: (context, spec, _) => spec == null
                          ? const SizedBox.expand()
                          : SideTabColumn(
                              width: width,
                              bottomInset: media.viewPadding.bottom,
                              bar: bar,
                              columnHeight: media.size.height,
                              tabs: spec.tabs,
                              selectedIndex: spec.selectedIndex,
                              onSelected: spec.onSelected,
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
    // The app's frame starts right of a left column: move the display
    // features (the iPhone Duo fold) into its coordinates.
    final shifted = side == SideColumn.left
        ? [
            for (final f in media.displayFeatures)
              if (f.bounds.right > width)
                DisplayFeature(
                  bounds: f.bounds.shift(Offset(-width, 0)),
                  type: f.type,
                  state: f.state,
                ),
          ]
        : media.displayFeatures;
    final app = Expanded(
      child: MediaQuery(
        data: media
            .removePadding(
              removeLeft: side == SideColumn.left,
              removeRight: side == SideColumn.right,
            )
            .copyWith(displayFeatures: shifted),
        child: _SideColumnScope(host: this, side: side, child: widget.child),
      ),
    );
    return Row(
      textDirection: TextDirection.ltr,
      children: side == SideColumn.left ? [column, app] : [app, column],
    );
  }

  /// iOS's bar frame for [side], in the column's own coordinates; null
  /// when iOS gave none or it does not fall inside the column.
  static Rect? _barIn(
    DuoGeometry geometry,
    SideColumn side,
    double width,
    MediaQueryData media,
  ) {
    final raw = switch (side) {
      SideColumn.right => geometry.barRight,
      SideColumn.left => geometry.barLeft,
      SideColumn.none => null,
    };
    if (raw == null) return null;
    final originX = side == SideColumn.right ? media.size.width - width : 0.0;
    final bar = raw.shift(Offset(-originX, 0));
    if (bar.left < -1 || bar.right > width + 1) return null;
    return bar;
  }
}

/// Moves [child], laid out centred in a [width] column, onto [centreX]
/// (iOS's bar centre line, the camera's axis); as is without one. Taps
/// follow the move.
Widget _onAxis(double? centreX, double width, Widget child) {
  if (centreX == null) return child;
  return Transform.translate(
    offset: Offset(centreX - width / 2, 0),
    child: child,
  );
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
/// tab bars on iPhone Duo. [width] is the column's inset. With iOS's [bar]
/// frame the pill ends where the bar does and sits on its centre line;
/// without one [bottomInset] keeps it above the home indicator.
class SideTabColumn extends StatelessWidget {
  const SideTabColumn({
    super.key,
    required this.width,
    required this.bottomInset,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    this.bar,
    this.columnHeight,
  });

  final double width;
  final double bottomInset;
  final Rect? bar;

  /// The column's height, to turn [bar]'s bottom into a margin.
  final double? columnHeight;
  final List<SideTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.omni;
    final b = bar;
    final h = columnHeight;
    final bottom = b != null && h != null
        ? math.max(0.0, h - b.bottom)
        : bottomInset + 16;
    return SizedBox(
      width: width,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: _onAxis(
            b?.center.dx,
            width,
            Container(
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
      ),
    );
  }
}

/// The top of the column: the screen's [SideTool]s, one under the other,
/// from the top of iOS's [bar] frame (under the clock, status icons and
/// camera) on its centre line; [kSideStatusHeight] down and centred
/// without one. Nothing (no height) without tools.
class SideToolColumn extends StatelessWidget {
  const SideToolColumn({super.key, required this.tools, this.width, this.bar});

  final List<SideTool> tools;
  final double? width;
  final Rect? bar;

  @override
  Widget build(BuildContext context) {
    if (tools.isEmpty) return const SizedBox.shrink();
    final b = bar;
    final w = width;
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < tools.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _SideToolButton(key: ValueKey('side-tool-$i'), tool: tools[i]),
        ],
      ],
    );
    return Padding(
      padding: EdgeInsets.only(top: b?.top ?? kSideStatusHeight),
      child: w == null
          ? column
          : SizedBox(width: w, child: _onAxis(b?.center.dx, w, column)),
    );
  }
}

class _SideToolButton extends StatelessWidget {
  const _SideToolButton({super.key, required this.tool});

  final SideTool tool;

  @override
  Widget build(BuildContext context) {
    final c = context.omni;
    final custom = tool.child;
    final button = custom != null
        ? Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: tool.onTap,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(child: custom),
              ),
            ),
          )
        : Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: c.lineSoft),
              boxShadow: c.cardShadow,
            ),
            child: Material(
              color: c.bar,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: tool.onTap,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: IconTheme.merge(
                    data: IconThemeData(color: c.text, size: 22),
                    child: Center(child: tool.icon),
                  ),
                ),
              ),
            ),
          );
    return Semantics(
      button: true,
      label: tool.label,
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          if (tool.badge > 0)
            Positioned(
              top: 0,
              right: -2,
              child: IgnorePointer(
                child: Container(
                  key: const ValueKey('side-tool-badge'),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: c.badge,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: c.bar, width: 1.5),
                  ),
                  child: Text(
                    tool.badge > 9 ? '9+' : '${tool.badge}',
                    style: TextStyle(
                      color: c.onBadge,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
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
