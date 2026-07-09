import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/error_messages.dart';
import '../../services/biometric_auth_service.dart';
import '../../services/biometric_types.dart';
import '../../services/device_service.dart';
import '../../services/omni_mobile_api.dart';
import '../../services/session_service.dart';
import 'dart:convert';
import '../../widgets/biometric_optin_sheet.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/labeled_field.dart';
import '../../widgets/primary_button.dart';
import '../home/home_shell.dart';
import 'company_settings_screen.dart';

/// Email/password login. Reached after CompanyCodeScreen has resolved
/// the SaaS routing (clientUrl + clientDb). On success, calls
/// /api/v1/omni_mobile/login and persists the access token + user/
/// employee details to SessionService. The top-level Consumer in
/// OmniHrApp then renders HomeShell.
class LoginScreen extends StatefulWidget {
  /// Whether to automatically show the biometric prompt on open (when a
  /// credential is stored). Set to false right after a manual Log out so
  /// the user isn't immediately re-prompted into what they just left.
  final bool autoPromptBiometric;
  const LoginScreen({super.key, this.autoPromptBiometric = true});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loginController =
      TextEditingController(text: DevConstants.defaultLogin);
  final _passwordController = TextEditingController();
  final _deviceService = DeviceService();
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _error;
  bool _capable = false;
  bool _bioResolved = false;
  BiometricKind _bioKind = BiometricKind.none;

  @override
  void initState() {
    super.initState();
    _resolveBiometric();
  }

  Future<void> _resolveBiometric() async {
    final bio = context.read<BiometricAuthService>();
    final capable = bio.isEnabled ? await bio.isDeviceCapable() : false;
    final kind = capable ? await bio.deviceBiometricKind() : BiometricKind.none;
    if (!mounted) return;
    setState(() {
      _capable = capable;
      _bioKind = kind;
      _bioResolved = true;
    });
    // Auto-prompt once, unless suppressed (e.g. right after a manual logout).
    if (_capable && widget.autoPromptBiometric) {
      _biometricLogin();
    }
  }

  Future<void> _biometricLogin() async {
    final bio = context.read<BiometricAuthService>();
    final res = await bio.authenticateAndRetrieve();
    if (!mounted) return;
    if (res.outcome == BiometricAuthOutcome.success && res.credential != null) {
      await _performLogin(res.credential!.login, res.credential!.password,
          fromBiometric: true);
      return;
    }
    if (res.outcome == BiometricAuthOutcome.lockedOut) {
      setState(() {
        _error = 'Too many attempts — please log in with your password.';
      });
    }
    // canceled / failed / unavailable: stay on the panel; user can retry
    // or tap "Use password instead".
  }

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final loginText = _loginController.text.trim();
    final password = _passwordController.text;
    if (loginText.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }
    await _performLogin(loginText, password);
  }

  /// Shared login path for both the password form and biometric replay.
  Future<void> _performLogin(String loginText, String password,
      {bool fromBiometric = false}) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final session = context.read<SessionService>();
      final api = OmniMobileApi(
        baseUrl: session.clientUrl,
        db: session.clientDb,
        token: '', // login has no auth header
      );
      final deviceId = await _deviceService.getDeviceId();
      final res = await api.login(
        login: loginText,
        password: password,
        deviceId: deviceId,
        appVersion: AppConstants.appVersion,
      );
      final user = res['user'] as Map<String, dynamic>? ?? {};
      final employee = res['employee'] as Map<String, dynamic>? ?? {};
      final expiresAtStr = res['expires_at']?.toString() ?? '';
      await session.saveSession(
        accessToken: res['access_token']?.toString() ?? '',
        expiresAt: expiresAtStr.isNotEmpty
            ? DateTime.tryParse(expiresAtStr)
            : null,
        userId: (user['id'] as num?)?.toInt() ?? 0,
        userLogin: user['login']?.toString() ?? '',
        userName: user['name']?.toString() ?? '',
        employeeId: (employee['id'] as num?)?.toInt() ?? 0,
        employeeName: employee['name']?.toString() ?? '',
        employeeAvatarB64: employee['avatar_b64']?.toString() ?? '',
        employeeJobTitle: employee['job_title']?.toString() ?? '',
        employeeJobPosition: employee['job_position']?.toString() ?? '',
        employeeDepartment: employee['department_name']?.toString() ?? '',
        employeeManager: employee['manager_name']?.toString() ?? '',
        employeeWorkEmail: employee['work_email']?.toString() ?? '',
        employeeWorkPhone: employee['work_phone']?.toString() ?? '',
        employeeCompanyName: employee['company_name']?.toString() ?? '',
        employeeCompanyLogoB64:
            employee['company_logo_b64']?.toString() ?? '',
        employeeHrApprover: employee['hr_approver_name']?.toString() ?? '',
        employeeTimeOffApprover:
            employee['time_off_approver_name']?.toString() ?? '',
        employeeAttendanceApprover:
            employee['attendance_approver_name']?.toString() ?? '',
        employeeExpenseApprover:
            employee['expense_approver_name']?.toString() ?? '',
      );
      if (!mounted) return;
      await _maybeOfferBiometricOptIn(loginText, password,
          employee['name']?.toString() ?? '');
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (_) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      final bio = context.read<BiometricAuthService>();
      if (e.errorCode == 'invalid_credentials' &&
          fromBiometric &&
          bio.isEnabled) {
        await bio.disable();
        if (mounted) {
          setState(() {
            _capable = false;
            _error =
                'Your password has changed — please log in with your password.';
          });
        }
      } else {
        setState(() => _error = _humanize(e));
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Offer to enable biometric login once, right after a successful
  /// manual login, when the device is capable, it is not already
  /// enabled, and the user has not dismissed the offer before.
  Future<void> _maybeOfferBiometricOptIn(
      String loginText, String password, String displayName) async {
    final bio = context.read<BiometricAuthService>();
    if (bio.isEnabled) return;
    if (await bio.hasDismissedOptIn()) return;
    if (!await bio.isDeviceCapable()) return;
    final kind = await bio.deviceBiometricKind();
    if (!mounted) return;
    final choice = await showBiometricOptInSheet(context, kind: kind);
    if (!mounted) return;
    if (choice == true) {
      final ok = await bio.enable(
          login: loginText, password: password, displayName: displayName);
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${biometricLabel(kind)} login enabled')));
      }
    } else if (choice == false) {
      await bio.markOptInDismissed();
    }
  }

  String _humanize(ApiException e) {
    switch (e.errorCode) {
      case 'invalid_credentials':
        return 'Invalid email or password.';
      case 'missing_credentials':
        return 'Enter your email and password.';
      case 'no_employee_linked':
        return 'No employee record is linked to that user.';
      case 'mobile_not_enabled':
        return 'Mobile access is not enabled for this employee. Ask HR to enable it.';
      case 'seat_limit_exceeded':
        return 'Your organization has reached its mobile seat limit. '
            'Contact your administrator to request access.';
      case 'rate_limit_exceeded':
        return 'Too many login attempts. Try again in a few minutes.';
      default:
        // Friendly fallback for any error code we haven't explicitly
        // mapped — keeps cryptic snake_case codes off the UI.
        return 'Login failed. Please try again or contact your '
            'administrator.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign In'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Company settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const CompanySettingsScreen(),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 48),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),
                      // Branding block — two modes:
                      // Clean (default): client company logo + name.
                      // Debug: Omnisoft logo + company code + URL + DB.
                      Center(
                        child: session.showConnectionDetails
                            ? _debugBranding(session)
                            : _cleanBranding(session),
                      ),
                      const SizedBox(height: 40),
                      // Form
                      LabeledField(
                        label: 'Email or login',
                        controller: _loginController,
                        hintText: 'name@company.com',
                        prefixIcon: Icons.mail_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 20),
                      LabeledField(
                        label: 'Password',
                        controller: _passwordController,
                        prefixIcon: Icons.lock_outline_rounded,
                        obscureText: _obscurePassword,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _login(),
                        suffix: IconButton(
                          tooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        _errorBanner(_error!),
                      ],
                      const SizedBox(height: 28),
                      PrimaryButton(
                        label: 'SIGN IN',
                        loading: _submitting,
                        onPressed: _submitting ? null : _login,
                      ),
                      if (_bioResolved && _capable) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _submitting ? null : _biometricLogin,
                            icon: Icon(_bioKind == BiometricKind.faceId ||
                                    _bioKind == BiometricKind.face
                                ? Icons.face
                                : Icons.fingerprint),
                            label: Text(
                                'Sign in with ${biometricLabel(_bioKind)}'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.primary,
                              side: BorderSide(
                                  color:
                                      AppTheme.primary.withValues(alpha: 0.5)),
                              shape: const StadiumBorder(),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                      // Push the footer to the bottom of the safe area.
                      const Spacer(),
                      const SizedBox(height: 24),
                      Center(
                        child: Text(
                          'POWERED BY OMNISOFT TECHNOLOGIES',
                          maxLines: 1,
                          overflow: TextOverflow.visible,
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                            color: AppTheme.outline.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _errorBanner(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppTheme.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: AppTheme.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cleanBranding(SessionService session) {
    final hasLogo = session.companyLogoB64.isNotEmpty;
    final name = session.companyName.isNotEmpty
        ? session.companyName
        : (session.companyCode.isNotEmpty
            ? session.companyCode
            : AppConstants.appName);
    return Column(
      children: [
        if (hasLogo)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(
              base64Decode(session.companyLogoB64),
              width: 120,
              height: 120,
              fit: BoxFit.contain,
              errorBuilder: (_, e, st) => _logoFallback(name),
            ),
          )
        else
          _logoFallback(name),
        const SizedBox(height: 16),
        Text(
          name,
          style: GoogleFonts.inter(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppTheme.onSurface,
            letterSpacing: -0.3,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _logoFallback(String name) {
    final initials = name.isNotEmpty
        ? name
            .split(' ')
            .where((w) => w.isNotEmpty)
            .take(2)
            .map((w) => w[0].toUpperCase())
            .join()
        : '?';
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: AppTheme.primaryContainer.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          initials,
          style: GoogleFonts.inter(
            fontSize: 48,
            fontWeight: FontWeight.w800,
            color: AppTheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _debugBranding(SessionService session) {
    return Column(
      children: [
        const BrandLogo.large(),
        const SizedBox(height: 24),
        Text(
          session.companyCode.isNotEmpty
              ? session.companyCode
              : AppConstants.appName,
          style: Theme.of(context)
              .textTheme
              .displaySmall
              ?.copyWith(color: AppTheme.onSurface),
        ),
        if (session.clientUrl.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            session.clientUrl,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryContainer,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        if (session.clientDb.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            session.clientDb,
            style: GoogleFonts.firaCode(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: AppTheme.outline,
            ),
          ),
        ],
      ],
    );
  }
}
