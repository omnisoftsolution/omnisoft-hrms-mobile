import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../core/omni_colors.dart';
import '../screens/home/home_shell.dart';
import '../screens/home/side_tab_column.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../services/notification_service.dart';
import '../services/session_service.dart';
import 'brand_logo.dart';
import 'employee_avatar.dart';

/// Shared AppBar used by every main tab (Home, Leave, History,
/// Expenses). Brand logo on the left, screen title in the middle,
/// notification bell + tappable employee avatar on the right.
///
/// - Bell tap → push NotificationsScreen with the leave-tap
///   callback wired to the ancestor HomeShell.
/// - Avatar tap → push ProfileScreen as a new route.
///
/// iPhone Duo (closed, or open sideways): the back arrow, the bell and the
/// avatar move to the top of the system's side column, as iOS does with
/// native toolbar buttons; the logo, the title and [extraActions] stay.
/// Only the bar on top offers them — the visible tab, the current route
/// (`TickerMode` is off in hidden tabs and under a covering route).
class OmniAppBar extends StatefulWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget> extraActions;

  const OmniAppBar({
    super.key,
    required this.title,
    this.extraActions = const [],
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  State<OmniAppBar> createState() => _OmniAppBarState();
}

class _OmniAppBarState extends State<OmniAppBar> {
  /// Kept for [dispose], which can't look it up.
  SideColumnHostState? _sideHost;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sideHost = SideColumnHost.maybeOf(context);
  }

  @override
  void dispose() {
    _sideHost?.withdrawTools(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    // When this AppBar is used on a pushed route (Profile, Payslips,
    // future pushed screens), Navigator can pop → show a back arrow
    // instead of the brand logo. Root-tab screens keep the logo
    // (canPop is false there because the tabs live inside IndexedStack
    // on the HomeShell root, not a deeper navigator stack).
    final canPop = Navigator.of(context).canPop();
    final inColumn = SideColumnHost.sideOf(context) != SideColumn.none;
    final onTop =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    final name = session.employeeName.isNotEmpty
        ? session.employeeName
        : session.userName;
    if (inColumn && onTop) {
      final unread = context.watch<NotificationService>().unreadCount;
      _sideHost?.offerTools(this, [
        if (canPop)
          SideTool(
            label: 'Back',
            icon: const BackButtonIcon(),
            onTap: () => Navigator.of(context).maybePop(),
          ),
        SideTool(
          label: unread > 0
              ? '$unread unread notification${unread == 1 ? '' : 's'}'
              : 'Notifications',
          icon: Icon(
            unread > 0
                ? Icons.notifications_rounded
                : Icons.notifications_outlined,
          ),
          badge: unread,
          onTap: () => _openNotifications(context),
        ),
        SideTool(
          label: 'Profile',
          onTap: () => _openProfile(context),
          child: EmployeeAvatar(
            avatarB64: session.employeeAvatarB64,
            name: name,
            size: 40,
            online: true,
          ),
        ),
      ]);
    } else {
      _sideHost?.withdrawTools(this);
    }
    if (inColumn) {
      return AppBar(
        titleSpacing: canPop ? 16 : 12,
        centerTitle: false,
        automaticallyImplyLeading: false,
        leadingWidth: canPop ? null : 56,
        leading: canPop
            ? null
            : const Padding(
                padding: EdgeInsets.only(left: 16),
                child: Center(child: BrandLogo.small()),
              ),
        title: _title(context),
        actions: [...widget.extraActions, const SizedBox(width: 8)],
      );
    }
    return AppBar(
      titleSpacing: 12,
      centerTitle: false,
      leadingWidth: 56,
      leading: canPop
          ? const BackButton()
          : const Padding(
              padding: EdgeInsets.only(left: 16),
              child: Center(child: BrandLogo.small()),
            ),
      title: _title(context),
      actions: [
        ...widget.extraActions,
        Consumer<NotificationService>(
          builder: (_, notif, _) => OmniBellButton(
            unreadCount: notif.unreadCount,
            onPressed: () => _openNotifications(context),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 16, left: 4),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openProfile(context),
            child: Tooltip(
              message: 'Profile',
              child: EmployeeAvatar(
                avatarB64: session.employeeAvatarB64,
                name: name,
                size: 36,
                online: true,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _title(BuildContext context) => Text(
    widget.title,
    style: GoogleFonts.inter(
      fontSize: 20,
      fontWeight: FontWeight.w800,
      color: context.omni.text,
      letterSpacing: -0.3,
    ),
  );

  // rootNavigator: true so Profile renders above HomeShell's per-tab
  // Navigators. Without it, Profile gets pushed into the currently-active
  // tab's stack — the bottom nav stays highlighted on that tab while
  // viewing Profile, and the tab's back history diverges per tab.
  void _openProfile(BuildContext context) => Navigator.of(
    context,
    rootNavigator: true,
  ).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));

  void _openNotifications(BuildContext context) {
    final shell = context.findAncestorStateOfType<HomeShellState>();
    if (shell != null) {
      // rootNavigator: true so Notifications renders above HomeShell —
      // same reason as the Profile push above. A routable tap pops back
      // to the tabs, then HomeShell switches tab (HomeShell.openNotifications,
      // shared with push taps). Fire-and-forget: the bell is its own page.
      unawaited(shell.openNotifications());
      return;
    }
    // Outside the shell (a screen pushed on the root navigator, e.g.
    // Payslips): the bell closes on a routable tap, as before.
    final nav = Navigator.of(context, rootNavigator: true);
    nav.push(
      MaterialPageRoute(
        builder: (_) => NotificationsScreen(
          onLeaveTap: (_) => nav.pop(),
          onExpenseTap: (_) => nav.pop(),
          onApprovalTap: (_) => nav.pop(),
          onMyDayTap: () => nav.pop(),
        ),
      ),
    );
  }
}

/// AppBar bell with an optional unread badge. Public so any
/// AppBar variant can reuse it; OmniAppBar wires it directly.
class OmniBellButton extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onPressed;

  const OmniBellButton({
    super.key,
    required this.unreadCount,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final hasUnread = unreadCount > 0;
    final c = context.omni;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        IconButton(
          tooltip: hasUnread
              ? '$unreadCount unread notification${unreadCount == 1 ? '' : 's'}'
              : 'Notifications',
          icon: Icon(
            hasUnread
                ? Icons.notifications_rounded
                : Icons.notifications_outlined,
            color: hasUnread ? c.accent : c.textMuted.withValues(alpha: 0.7),
          ),
          onPressed: onPressed,
        ),
        // The badge is decoration only: IgnorePointer lets a tap on it
        // reach the IconButton underneath (APP-3 — it used to swallow it).
        // Its LEFT edge is anchored just right of the glyph's centre (the
        // 48 dp button centres the 24 dp glyph at 24, 24) and it grows to
        // the right, so a wide "9+" sits on the bell's top-right corner
        // instead of hiding the bell (APP-6, was right: 8 growing left).
        if (hasUnread)
          Positioned(
            top: 4,
            left: 26,
            child: IgnorePointer(
              child: Container(
                key: const ValueKey('bell-badge'),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: c.badge,
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: c.bar, width: 1.5),
                ),
                child: Text(
                  unreadCount > 9 ? '9+' : '$unreadCount',
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
    );
  }
}
