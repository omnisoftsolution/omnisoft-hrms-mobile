import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_login.dart';
import '../../core/constants.dart';
import '../../core/error_messages.dart';
import '../../core/theme.dart';
import '../../models/company_info.dart';
import '../../services/biometric_auth_service.dart';
import '../../services/device_service.dart';
import '../../services/omni_mobile_api.dart';
import '../../services/session_service.dart';
import '../../widgets/biometric_optin_sheet.dart';
import '../../widgets/labeled_field.dart';
import '../home/home_shell.dart';

/// Adds this phone to an Omni HR account that is already active on
/// another phone (connector 2.62.0+, `POST auth/add_device`, spec
/// 2026-10-10 §3.8). HR's Add phone gives a one-time pair: a link / QR
/// (`k=add`, token prefilled, see `screenForActivationLink`) or a 6-digit
/// code typed here with the app login. The employee also types their own
/// app password, so HR alone can never add a phone. The other phones stay
/// signed in and the password does not change.
///
/// Like `ActivationScreen`, another company's code is looked up but the
/// switch is staged: the saved company and any live session change only
/// once the phone is added. Providers are read only inside the submit
/// handler, so the form builds without any provider above it.
class AddPhoneScreen extends StatefulWidget {
  final String? companyCode;

  /// Add-phone token from the link / QR; null = manual code entry.
  final String? token;

  /// Login carried by the link (`l`), prefilled and editable.
  final String? login;

  /// Test seam: builds the unauthenticated API client for a company's
  /// Odoo URL + database. Defaults to the real [OmniMobileApi].
  @visibleForTesting
  final OmniMobileApi Function(String baseUrl, String db)? apiBuilder;

  /// Test seam: the screen shown after the phone is added. Defaults to
  /// [HomeShell].
  @visibleForTesting
  final WidgetBuilder? homeBuilder;

  const AddPhoneScreen({
    super.key,
    this.companyCode,
    this.token,
    this.login,
    this.apiBuilder,
    this.homeBuilder,
  });

  @override
  State<AddPhoneScreen> createState() => _AddPhoneScreenState();
}

class _AddPhoneScreenState extends State<AddPhoneScreen> {
  final _companyController = TextEditingController();
  final _loginController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _deviceService = DeviceService();
  bool _obscurePassword = true;
  bool _submitting = false;

  /// The server added this phone but saving the result locally failed;
  /// the form is spent (its pair is void) and must not post again.
  bool _added = false;
  String? _error;

  static const _addedSignInMessage =
      'This phone is added. Sign in with your app login and password.';

  bool get _hasToken => widget.token != null && widget.token!.isNotEmpty;
  bool get _hasCompany =>
      widget.companyCode != null && widget.companyCode!.isNotEmpty;

  List<TextEditingController> get _controllers => [
        _companyController,
        _loginController,
        _codeController,
        _passwordController,
      ];

  @override
  void initState() {
    super.initState();
    if (widget.login != null) _loginController.text = widget.login!;
    for (final c in _controllers) {
      c.addListener(_onChanged);
    }
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSubmit =>
      !_added &&
      _loginController.text.trim().isNotEmpty &&
      _passwordController.text.isNotEmpty &&
      (_hasToken || _codeController.text.trim().length == 6) &&
      (_hasCompany || _companyController.text.trim().isNotEmpty);

  Future<void> _addPhone() async {
    // Never send an empty login / password / code: the server would answer
    // `missing_fields`, which has no friendly text. The button is already
    // disabled in this state; this guards any other caller.
    if (!_canSubmit) return;
    final session = context.read<SessionService>();
    final bio = context.read<BiometricAuthService>();
    final companyCode =
        (_hasCompany ? widget.companyCode! : _companyController.text).trim();
    final login = _loginController.text.trim();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final sameCompany = session.hasCompany &&
          companyCode.toUpperCase() == session.companyCode.toUpperCase();
      CompanyInfo? staged;
      String stagedSaasUrl = '';
      var baseUrl = session.clientUrl;
      var db = session.clientDb;
      if (!sameCompany) {
        stagedSaasUrl = session.effectiveSaasUrl();
        staged =
            await session.lookupCompany(companyCode, saasUrl: stagedSaasUrl);
        baseUrl = staged.odooUrl;
        db = staged.database;
      }
      final deviceId = await _deviceService.getDeviceId();
      final deviceLabel = await _deviceService.getDeviceLabel();
      final api = widget.apiBuilder?.call(baseUrl, db) ??
          OmniMobileApi(
            baseUrl: baseUrl,
            db: db,
            token: '', // add_device has no auth header
          );
      final res = await api.addDevice(
        login: login,
        token: _hasToken ? widget.token : null,
        code: _hasToken ? null : _codeController.text.trim(),
        password: _passwordController.text,
        deviceId: deviceId,
        deviceLabel: deviceLabel,
        appVersion: AppConstants.appVersion,
      );
      // From here the server has trusted this phone and voided the pair, so
      // a failure to store the result locally must NOT read as "ask HR for
      // a new code": a plain sign-in already works.
      final String faceIdLogin;
      try {
        if (staged != null) {
          // Commit the switch: drop the other company's session first.
          if (session.accessToken.isNotEmpty) await session.clearSession();
          await session.saveCompanyInfo(staged, saasUrl: stagedSaasUrl);
        }
        // Same payload as /login: stored exactly like a sign-in.
        await session.saveLoginResponse(res);
        // Face ID follows the server's login, never the typed text, and
        // never a hidden Odoo user an older connector could return.
        final returned = session.userLogin;
        faceIdLogin = returned.isNotEmpty && !isHiddenOdooLogin(returned)
            ? returned
            : login;
        await bio.adoptRefreshToken(session.refreshToken, login: faceIdLogin);
      } catch (_) {
        if (!mounted) return;
        _passwordController.clear();
        _codeController.clear();
        setState(() {
          _added = true; // the form must not post again
          _error = _addedSignInMessage;
        });
        // Leave the dead form; the app's front door shows the sign-in.
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text(_addedSignInMessage)));
          nav.popUntil((r) => r.isFirst);
        }
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('This phone is added. Your other phones stay signed in.')));
      await _maybeOfferBiometricOptIn(
          bio, faceIdLogin, session.refreshToken, session.employeeName);
      if (!mounted) return;
      // The secrets did their job: drop them from the form, now that the
      // session is saved (a disposed controller must never be cleared).
      _passwordController.clear();
      _codeController.clear();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: widget.homeBuilder ?? (_) => const HomeShell()),
        (_) => false,
      );
    } catch (e) {
      // invalid_code, invalid_credentials, account_locked, not_active,
      // mobile_not_enabled and the rest: the shared humanizer only.
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Same one-time offer as activation (add_device always issues a
  /// refresh token).
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // No backing out while the request runs: the pair would be spent with
    // nothing saved on this phone.
    return PopScope(
      canPop: !_submitting,
      child: Scaffold(
      appBar: AppBar(),
      body: SingleChildScrollView(
        // viewPadding (not SafeArea): the system inset below the button,
        // whatever an ancestor did to MediaQuery.padding.
        padding: EdgeInsets.fromLTRB(
            28, 16, 28, MediaQuery.viewPaddingOf(context).bottom + 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add this phone to Omni HR',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
                'Use the code or QR from HR and your Omni HR password. '
                'Your other phones stay signed in.',
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
                key: const Key('add_phone_company'),
                label: 'Company code',
                controller: _companyController,
                prefixIcon: Icons.business_outlined,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
              ),
            const SizedBox(height: 20),
            LabeledField(
              key: const Key('add_phone_login'),
              label: 'App login',
              controller: _loginController,
              hintText: 'Email, phone or username',
              prefixIcon: Icons.person_outline_rounded,
              keyboardType: TextInputType.text,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
            ),
            if (!_hasToken) ...[
              const SizedBox(height: 20),
              LabeledField(
                key: const Key('add_phone_code'),
                label: 'Add-phone code',
                controller: _codeController,
                hintText: '6 digits from HR',
                prefixIcon: Icons.pin_outlined,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                textInputAction: TextInputAction.next,
              ),
            ],
            const SizedBox(height: 20),
            LabeledField(
              key: const Key('add_phone_password'),
              label: 'Your app password',
              controller: _passwordController,
              prefixIcon: Icons.lock_outline_rounded,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
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
              child: Text('The password you use on your other phone.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppTheme.outline)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!,
                  style: TextStyle(color: AppTheme.error, fontSize: 13)),
            ],
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _submitting || !_canSubmit ? null : _addPhone,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const StadiumBorder(),
              ),
              child: const Text('Add this phone'),
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
