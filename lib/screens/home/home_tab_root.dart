import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/session_service.dart';

/// Root of the Home tab: My day for employees whose attendance is
/// kiosk-only, the classic check-in home for everyone else (spec
/// 2026-10-05 §5.2). It sits INSIDE the tab's Navigator route and listens
/// to the session, because that route is built only once: the home must
/// switch as soon as /me changes the flag.
class HomeTabRoot extends StatelessWidget {
  const HomeTabRoot({
    super.key,
    required this.classicHome,
    required this.myDay,
  });

  final Widget classicHome;
  final Widget myDay;

  @override
  Widget build(BuildContext context) {
    final kioskOnly = context
        .select<SessionService, bool>((session) => session.attendanceKioskOnly);
    return kioskOnly ? myDay : classicHome;
  }
}
