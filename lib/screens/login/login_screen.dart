import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/device_service.dart';
import '../../services/omni_mobile_api.dart';
import '../../services/session_service.dart';
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
  const LoginScreen({super.key});

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
        employeeCompanyName:
            employee['company_name']?.toString() ?? '',
        employeeCompanyLogoB64:
            employee['company_logo_b64']?.toString() ?? '',
        employeeHrApprover:
            employee['hr_approver_name']?.toString() ?? '',
        employeeTimeOffApprover:
            employee['time_off_approver_name']?.toString() ?? '',
        employeeAttendanceApprover:
            employee['attendance_approver_name']?.toString() ?? '',
        employeeExpenseApprover:
            employee['expense_approver_name']?.toString() ?? '',
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (_) => false,
      );
    } on ApiException catch (e) {
      setState(() => _error = _humanize(e));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
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
                      // Branding block
                      Center(
                        child: Column(
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
                        ),
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
}
