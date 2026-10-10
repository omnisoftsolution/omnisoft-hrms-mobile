import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/session_service.dart';
import 'company_code/company_code_screen.dart';
import 'home/home_shell.dart';
import 'login/login_screen.dart';

/// The app's session-aware front door. It rebuilds whenever the session
/// changes:
///   no company resolved      → CompanyCodeScreen
///   company set, not signed  → LoginScreen
///   signed in                → HomeShell
///
/// `main.dart` uses it as the MaterialApp home. A screen that clears the
/// whole route stack after signing in pushes a fresh [SessionGate] rather
/// than a bare [HomeShell], so a later `invalid_session` (HR revoked this
/// phone) still lands on sign-in.
class SessionGate extends StatelessWidget {
  const SessionGate({super.key, this.homeBuilder});

  /// Test seam: the signed-in screen. Defaults to [HomeShell].
  @visibleForTesting
  final WidgetBuilder? homeBuilder;

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionService>(
      builder: (context, s, _) {
        if (!s.hasCompany) return const CompanyCodeScreen();
        if (!s.isLoggedIn) return const LoginScreen();
        return homeBuilder?.call(context) ?? const HomeShell();
      },
    );
  }
}
