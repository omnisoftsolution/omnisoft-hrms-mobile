import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/error_messages.dart';
import '../../core/theme.dart';
import '../../services/biometric_auth_service.dart';
import '../../services/device_service.dart';
import '../../services/omni_mobile_api.dart';
import '../../services/session_service.dart';
import '../../widgets/biometric_optin_sheet.dart';
import '../../widgets/labeled_field.dart';
import '../home/home_shell.dart';

/// First sign-in from an HR invite: the employee sets their own app
/// password. Opened by an `omnihr://activate` link or QR (company code
/// and token prefilled) or from the login screen's "Activate with an
/// invite" (manual mode: company code + the 6-digit code from the
/// invite email). On success the device is signed in and lands on home.
///
/// Providers are read only inside the submit handler, so the form
/// builds without any provider above it.
class ActivationScreen extends StatefulWidget {
  final String? companyCode;
  final String? token;

  const ActivationScreen({super.key, this.companyCode, this.token});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _companyController = TextEditingController();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _password2Controller = TextEditingController();
  final _deviceService = DeviceService();
  bool _obscurePassword = true;
  bool _submitting = false;
  bool _codeLocked = false;
  String? _error;

  bool get _hasToken => widget.token != null && widget.token!.isNotEmpty;
  bool get _hasCompany =>
      widget.companyCode != null && widget.companyCode!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    for (final c in _controllers) {
      c.addListener(_onChanged);
    }
  }

  List<TextEditingController> get _controllers => [
        _companyController,
        _emailController,
        _codeController,
        _passwordController,
        _password2Controller,
      ];

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSubmit {
    final password = _passwordController.text;
    return _emailController.text.contains('@') &&
        password.length >= 8 &&
        password == _password2Controller.text &&
        (_hasToken ||
            (!_codeLocked && _codeController.text.trim().length == 6)) &&
        (_hasCompany || _companyController.text.trim().isNotEmpty);
  }

  Future<void> _activate() async {
    final session = context.read<SessionService>();
    final bio = context.read<BiometricAuthService>();
    final companyCode =
        _hasCompany ? widget.companyCode! : _companyController.text.trim();
    final login = _emailController.text.trim().toLowerCase();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (!session.hasCompany || session.companyCode != companyCode) {
        await session.resolveCompany(companyCode);
      }
      final deviceId = await _deviceService.getDeviceId();
      final deviceLabel = await _deviceService.getDeviceLabel();
      final api = OmniMobileApi(
        baseUrl: session.clientUrl,
        db: session.clientDb,
        token: '', // activation has no auth header
      );
      final res = await api.activate(
        login: login,
        token: _hasToken ? widget.token : null,
        code: _hasToken ? null : _codeController.text.trim(),
        password: _passwordController.text,
        deviceId: deviceId,
        deviceLabel: deviceLabel,
        appVersion: AppConstants.appVersion,
      );
      await session.saveLoginResponse(res);
      if (!mounted) return;
      await _maybeOfferBiometricOptIn(
          bio, login, session.refreshToken, session.employeeName);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (_) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.errorCode == 'activation_attempts_exceeded') _codeLocked = true;
        _error = _humanize(e);
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Same one-time offer as the login screen, refresh-token mode only
  /// (activation always issues a refresh token).
  Future<void> _maybeOfferBiometricOptIn(BiometricAuthService bio,
      String login, String refreshToken, String displayName) async {
    if (refreshToken.isEmpty || bio.isEnabled) return;
    if (await bio.hasDismissedOptIn()) return;
    if (!await bio.isDeviceCapable()) return;
    final kind = await bio.deviceBiometricKind();
    if (!mounted) return;
    final choice = await showBiometricOptInSheet(context, kind: kind);
    if (!mounted) return;
    if (choice == true) {
      final ok = await bio.enableWithRefreshToken(
          login: login, refreshToken: refreshToken, displayName: displayName);
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
      case 'mobile_not_enabled':
        return 'Mobile access is not enabled for this employee. '
            'Ask HR to enable it.';
      case 'seat_limit_exceeded':
        return 'Your organization has reached its mobile seat limit. '
            'Contact your administrator to request access.';
      case 'missing_fields':
        return 'Fill in every field.';
      default:
        // Activation codes route through friendlyErrorCode.
        return friendlyError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Activate Omni HR',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('Use the link or code HR sent you.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppTheme.outline)),
              const SizedBox(height: 28),
              if (_hasCompany) ...[
                Text('Company',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: AppTheme.outline)),
                const SizedBox(height: 4),
                Text(widget.companyCode!,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ] else
                LabeledField(
                  key: const Key('activation_company'),
                  label: 'Company code',
                  controller: _companyController,
                  prefixIcon: Icons.business_outlined,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.next,
                ),
              const SizedBox(height: 20),
              LabeledField(
                key: const Key('activation_email'),
                label: 'Work email',
                controller: _emailController,
                hintText: 'name@company.com',
                prefixIcon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
              ),
              if (!_hasToken) ...[
                const SizedBox(height: 20),
                LabeledField(
                  key: const Key('activation_code'),
                  label: 'Invite code',
                  controller: _codeController,
                  hintText: '6 digits',
                  prefixIcon: Icons.pin_outlined,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  enabled: !_codeLocked,
                  textInputAction: TextInputAction.next,
                ),
              ],
              const SizedBox(height: 20),
              LabeledField(
                key: const Key('activation_password'),
                label: 'New password',
                controller: _passwordController,
                prefixIcon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                suffix: IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 6),
                child: Text('At least 8 characters',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppTheme.outline)),
              ),
              const SizedBox(height: 20),
              LabeledField(
                key: const Key('activation_password2'),
                label: 'Confirm password',
                controller: _password2Controller,
                prefixIcon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!,
                    style: TextStyle(color: AppTheme.error, fontSize: 13)),
              ],
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _submitting || !_canSubmit ? null : _activate,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
                child: const Text('Activate'),
              ),
              if (_submitting) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
