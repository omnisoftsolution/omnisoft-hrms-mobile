import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'services/face_recognition_service.dart';
import 'services/holiday_service.dart';
import 'services/notification_service.dart';
import 'services/omni_mobile_api.dart';
import 'services/session_service.dart';
import 'services/biometric_auth_service.dart';
import 'services/deep_link_service.dart';
import 'screens/activation/activation_screen.dart';
import 'screens/company_code/company_code_screen.dart';
import 'screens/home/home_shell.dart';
import 'screens/login/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConstants.initAppVersion();
  final session = SessionService();
  await session.load();

  final biometric = BiometricAuthService();
  await biometric.load();

  // A deliberate sign-out also forgets the biometric credential.
  session.onLogout = () {
    biometric.disable();
  };

  // When any /api/v1 call returns invalid_session, wipe the local
  // auth session so the top-level Consumer below re-renders to the
  // Login screen. SaaS routing (company code) is preserved. Biometric
  // credential is intentionally KEPT — this is the case it exists for.
  OmniMobileApi.onInvalidSession = () {
    session.clearSession();
  };

  runApp(OmniHrApp(session: session, biometric: biometric));
}

class OmniHrApp extends StatefulWidget {
  final SessionService session;
  final BiometricAuthService biometric;
  const OmniHrApp({super.key, required this.session, required this.biometric});

  @override
  State<OmniHrApp> createState() => _OmniHrAppState();
}

class _OmniHrAppState extends State<OmniHrApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _deepLinks = DeepLinkService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Invite links (omnihr://activate) open the activation screen on
    // top of whatever the session Consumer below is showing — on a cold
    // start (initial link) or while the app is running.
    _deepLinks.listen(_openActivation);
    // Cold-start refresh — picks up subscription + employee changes
    // the admin/HR made while the app was closed. Fire-and-forget;
    // we don't block the first frame on a network round-trip.
    _refreshSubscriptionInBackground();
    _refreshMeInBackground();
  }

  void _openActivation(ActivationArgs a) {
    final nav = _navigatorKey.currentState;
    if (nav == null) {
      // Link arrived before the first frame built the navigator.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _openActivation(a));
      return;
    }
    nav.push(MaterialPageRoute(
      builder: (_) =>
          ActivationScreen(companyCode: a.companyCode, token: a.token),
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deepLinks.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Hot-resume refresh — covers the "user backgrounded the app
      // while admin toggled a feature or HR updated the employee
      // record" case.
      _refreshSubscriptionInBackground();
      _refreshMeInBackground();
    }
  }

  /// Re-pulls subscription feature flags from the SaaS server and
  /// updates SessionService. Delegated to the service so other
  /// callers (HomeShell tab tap, manual button) share the same path.
  Future<void> _refreshSubscriptionInBackground() async {
    await widget.session.refreshSubscription();
  }

  /// Re-pulls the authenticated user/employee/approver state from the
  /// client connector and updates SessionService. Skipped when not
  /// signed in. Errors are swallowed (offline, rate limit, etc.) —
  /// invalid_session has its own handler that wipes auth and routes
  /// the user back to Login.
  Future<void> _refreshMeInBackground() async {
    final s = widget.session;
    if (!s.isLoggedIn) return;
    // Errors are swallowed inside refreshMe — cached employee fields
    // stay. invalid_session is handled by the global onInvalidSession
    // callback set in main().
    await s.refreshMe();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.session),
        ChangeNotifierProvider.value(value: widget.biometric),
        ChangeNotifierProvider(create: (_) => HolidayService()),
        ChangeNotifierProvider(create: (_) => FaceRecognitionService()),
        ChangeNotifierProvider(create: (_) => NotificationService()),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: AppConstants.appName,
        theme: AppTheme.lightTheme,
        debugShowCheckedModeBanner: false,
        // Reactive routing: rebuilds when session state changes.
        //   no company resolved      → CompanyCodeScreen
        //   company set, not signed  → LoginScreen
        //   signed in                → HomeShell
        home: Consumer<SessionService>(
          builder: (_, s, _) {
            if (!s.hasCompany) return const CompanyCodeScreen();
            if (!s.isLoggedIn) return const LoginScreen();
            return const HomeShell();
          },
        ),
      ),
    );
  }
}
