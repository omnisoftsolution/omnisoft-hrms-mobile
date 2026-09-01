import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../screens/home/home_shell.dart';
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
class OmniAppBar extends StatelessWidget implements PreferredSizeWidget {
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
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    // When this AppBar is used on a pushed route (Profile, Payslips,
    // future pushed screens), Navigator can pop → show a back arrow
    // instead of the brand logo. Root-tab screens keep the logo
    // (canPop is false there because the tabs live inside IndexedStack
    // on the HomeShell root, not a deeper navigator stack).
    final canPop = Navigator.of(context).canPop();
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
      title: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: AppTheme.onSurface,
          letterSpacing: -0.3,
        ),
      ),
      actions: [
        ...extraActions,
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
            // rootNavigator: true so Profile renders above HomeShell's
            // per-tab Navigators. Without it, Profile gets pushed into
            // the currently-active tab's stack — the bottom nav stays
            // highlighted on that tab while viewing Profile, and the
            // tab's back history diverges per tab.
            onTap: () =>
                Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(
                builder: (_) => const ProfileScreen(),
              ),
            ),
            child: Tooltip(
              message: 'Profile',
              child: EmployeeAvatar(
                avatarB64: session.employeeAvatarB64,
                name: session.employeeName.isNotEmpty
                    ? session.employeeName
                    : session.userName,
                size: 36,
                online: true,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openNotifications(BuildContext context) {
    final shell = context.findAncestorStateOfType<HomeShellState>();
    // rootNavigator: true so Notifications renders above HomeShell —
    // same reason as the Profile push above. The onLeaveTap /
    // onExpenseTap pops back to root, then HomeShell handles the
    // tab switch + nested navigation.
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => NotificationsScreen(
          onLeaveTap: (leaveId) async {
            Navigator.of(context, rootNavigator: true).pop();
            await shell?.navigateToLeave(leaveId);
          },
          onExpenseTap: (expenseId) async {
            Navigator.of(context, rootNavigator: true).pop();
            await shell?.navigateToExpense(expenseId);
          },
          onAnnouncementTap: (announcementId) async {
            Navigator.of(context, rootNavigator: true).pop();
            await shell?.openAnnouncement(announcementId);
          },
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

  const OmniBellButton(
      {super.key, required this.unreadCount, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final hasUnread = unreadCount > 0;
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
            color: hasUnread
                ? AppTheme.primary
                : AppTheme.outline.withValues(alpha: 0.7),
          ),
          onPressed: onPressed,
        ),
        if (hasUnread)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              constraints:
                  const BoxConstraints(minWidth: 18, minHeight: 18),
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.error,
                shape: BoxShape.rectangle,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                unreadCount > 9 ? '9+' : '$unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
