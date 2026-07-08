import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/error_messages.dart';
import '../../services/biometric_auth_service.dart';
import '../../services/biometric_types.dart';
import '../../services/saas_service.dart';
import '../../services/session_service.dart';
import '../../widgets/biometric_optin_sheet.dart' show biometricLabel;
import '../../widgets/labeled_field.dart';
import '../../widgets/primary_button.dart';
import 'login_screen.dart';

/// Lets the user re-resolve the company (point at a different SaaS or
/// switch company codes) without going through the full
/// CompanyCodeScreen flow. Reached via the gear icon on LoginScreen.
class CompanySettingsScreen extends StatefulWidget {
  const CompanySettingsScreen({super.key});

  @override
  State<CompanySettingsScreen> createState() => _CompanySettingsScreenState();
}

class _CompanySettingsScreenState extends State<CompanySettingsScreen> {
  late final TextEditingController _saasUrlController;
  late final TextEditingController _codeController;
  late String _clientUrl;
  late String _clientDb;
  bool _resolving = false;
  String? _error;
  String? _info;

  // The database name is hidden by default — it's an internal detail
  // most users never need and shouldn't see. Tapping the Client URL
  // tile [_kDbRevealTaps] times reveals it, a quiet support/diagnostics
  // affordance mirroring the kiosk app's provisioning screen. The reveal
  // is derived purely from the tap count, so resetting _dbTaps (on
  // re-resolve) re-hides it with no second flag to keep in sync.
  static const int _kDbRevealTaps = 7;
  int _dbTaps = 0;
  bool get _showDb => _dbTaps >= _kDbRevealTaps;

  bool _bioCapable = false;
  BiometricKind _bioKind = BiometricKind.none;

  @override
  void initState() {
    super.initState();
    final s = context.read<SessionService>();
    _saasUrlController = TextEditingController(text: s.saasUrl);
    _codeController = TextEditingController(text: s.companyCode);
    _clientUrl = s.clientUrl;
    _clientDb = s.clientDb;
    _resolveBio();
  }

  Future<void> _resolveBio() async {
    final bio = context.read<BiometricAuthService>();
    final capable = await bio.isDeviceCapable();
    final kind = capable ? await bio.deviceBiometricKind() : BiometricKind.none;
    if (!mounted) return;
    setState(() {
      _bioCapable = capable;
      _bioKind = kind;
    });
  }

  @override
  void dispose() {
    _saasUrlController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    final saasUrl = _saasUrlController.text.trim();
    final code = _codeController.text.trim();
    if (saasUrl.isEmpty || code.isEmpty) {
      setState(() => _error = 'Enter SaaS URL and Company Code.');
      return;
    }

    final session = context.read<SessionService>();
    // If the user edited either field AND they're currently signed in,
    // resolving will likely yield a different client db / company code,
    // which means clearSession() will fire and they'll be logged out.
    // Warn before doing the destructive thing.
    final fieldsEdited = saasUrl != session.saasUrl ||
        code.toUpperCase() != session.companyCode.toUpperCase();
    if (fieldsEdited && session.isLoggedIn) {
      final ok = await _confirmSwitchCompany(
        currentCode: session.companyCode,
        currentSaasUrl: session.saasUrl,
        newCode: code.toUpperCase(),
        newSaasUrl: saasUrl,
      );
      if (ok != true) return;
    }

    setState(() {
      _resolving = true;
      _error = null;
      _info = null;
    });
    try {
      final priorClientUrl = session.clientUrl;
      final priorCompanyCode = session.companyCode;

      final saas = SaasService();
      final info = await saas.resolveCompany(saasUrl, code);

      // If company routing actually changed, drop the auth session —
      // a token issued by the old client db is meaningless on a new one.
      final changed = info.odooUrl != priorClientUrl ||
          info.companyCode != priorCompanyCode;
      await session.saveCompany(
        saasUrl: saasUrl,
        companyCode: info.companyCode,
        clientUrl: info.odooUrl,
        clientDb: info.database,
        features: info.features,
        companyName: info.name,
        companyLogoB64: info.companyLogoB64,
        showConnectionDetails: info.showConnectionDetails,
      );
      if (changed) {
        await session.signOut();
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _clientUrl = info.odooUrl;
        _clientDb = info.database;
        _info = 'Company refreshed.';
        // New routing resolved — re-hide the database name (derived
        // from the tap count, so zeroing it re-hides the tile).
        _dbTaps = 0;
      });
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<bool?> _confirmSwitchCompany({
    required String currentCode,
    required String currentSaasUrl,
    required String newCode,
    required String newSaasUrl,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Switch company?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reconnecting will sign you out — you\'ll need to log in '
              'with the new company\'s credentials.',
              style: TextStyle(
                color: AppTheme.onSurfaceVariant,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            _diffRow(
                label: 'Stay on',
                code: currentCode,
                url: currentSaasUrl),
            const SizedBox(height: 8),
            _diffRow(
                label: 'Switch to',
                code: newCode,
                url: newSaasUrl,
                emphasised: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Switch company'),
          ),
        ],
      ),
    );
  }

  Widget _diffRow({
    required String label,
    required String code,
    required String url,
    bool emphasised = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: emphasised
            ? AppTheme.primaryContainer.withValues(alpha: 0.10)
            : AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: emphasised
                  ? AppTheme.primary
                  : AppTheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            code.isEmpty ? '—' : code,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (url.isNotEmpty)
            Text(
              url,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  /// Reveal the hidden Database tile after 7 taps on the Client URL tile.
  /// No-op once already shown.
  void _revealDbTap() {
    if (_showDb) return;
    setState(() => _dbTaps++);
  }

  Future<void> _clearCompany() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear company?'),
        content: const Text(
          'This signs you out and removes the SaaS / company routing. '
          'You will be returned to the company code screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final session = context.read<SessionService>();
    await session.logout();
    // Top-level Consumer<SessionService> in main.dart will rebuild to
    // CompanyCodeScreen now that hasCompany is false. Just pop ourselves.
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _toggleBiometric(bool on) async {
    final bio = context.read<BiometricAuthService>();
    if (!on) {
      await bio.disable();
      return;
    }
    final session = context.read<SessionService>();
    final password = await _promptPassword();
    if (password == null || password.isEmpty) return;
    final ok = await bio.enable(
      login: session.userLogin,
      password: password,
      displayName: session.employeeName,
    );
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${biometricLabel(_bioKind)} login enabled')));
    }
  }

  Future<String?> _promptPassword() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm your password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Confirm')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch (not read) so the Clear branch reacts to session changes —
    // e.g. invalid_session fires while the screen is open and the
    // button needs to appear without a re-navigation.
    final session = context.watch<SessionService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Company Settings'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Where the app talks to',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppTheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              LabeledField(
                label: 'SaaS URL',
                controller: _saasUrlController,
                prefixIcon: Icons.cloud_outlined,
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 16),
              LabeledField(
                label: 'Company Code',
                controller: _codeController,
                prefixIcon: Icons.vpn_key_outlined,
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 20),
              Text(
                'Resolved from SaaS',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppTheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              // Tapping the Client URL tile 7 times reveals the hidden
              // Database tile (support/diagnostics affordance). opaque
              // hit-test so taps anywhere on the tile count.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _revealDbTap,
                child: _readOnlyTile(
                    icon: Icons.public_rounded,
                    label: 'Client URL',
                    value: _clientUrl.isEmpty ? '—' : _clientUrl),
              ),
              if (_showDb) ...[
                const SizedBox(height: 8),
                _readOnlyTile(
                    icon: Icons.storage_outlined,
                    label: 'Database',
                    value: _clientDb.isEmpty ? '—' : _clientDb),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                _banner(_error!, AppTheme.error, Icons.error_outline),
              ],
              if (_info != null) ...[
                const SizedBox(height: 16),
                _banner(_info!, AppTheme.primary, Icons.check_circle_outline),
              ],
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'RESOLVE COMPANY',
                icon: _resolving ? null : Icons.refresh_rounded,
                loading: _resolving,
                onPressed: _resolving ? null : _resolve,
              ),
              const SizedBox(height: 12),
              // Clear Company is a full reset (auth + SaaS routing).
              // When the user is signed in we hide it entirely — they
              // must Logout from Profile first, then come back here
              // and clear from the logged-out state. This avoids the
              // "I tapped clear and got logged out without realising"
              // trap.
              if (!session.isLoggedIn)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Clear Company'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.error,
                      side: BorderSide(color: AppTheme.error),
                    ),
                    onPressed: _resolving ? null : _clearCompany,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'Sign out from Profile first to clear the company.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (_bioCapable) ...[
                const SizedBox(height: 32),
                Text(
                  'Security',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppTheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${biometricLabel(_bioKind)} login'),
                  subtitle: Text(
                      'Log in with ${biometricLabel(_bioKind)} when your session expires.'),
                  value: context.watch<BiometricAuthService>().isEnabled,
                  onChanged: (on) => _toggleBiometric(on),
                ),
              ],
              const SizedBox(height: 32),
              // Legal links — required to be discoverable from inside
              // the app for biometric data handling (Apple) and best
              // practice for Play Store data-safety disclosures.
              Text(
                'Legal',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppTheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              _legalLinkTile(
                icon: Icons.shield_outlined,
                label: 'Privacy Policy',
                url: AppConstants.privacyPolicyUrl,
              ),
              const SizedBox(height: 8),
              _legalLinkTile(
                icon: Icons.delete_outline,
                label: 'Account Deletion',
                url: AppConstants.accountDeletionUrl,
              ),
              const SizedBox(height: 32),
              Center(
                child: Text(
                  'App version ${AppConstants.appVersion}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.onSurfaceVariant,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legalLinkTile({
    required IconData icon,
    required String label,
    required String url,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openExternalUrl(url),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.open_in_new, size: 16, color: AppTheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Future<void> _openExternalUrl(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(url);
    if (uri == null) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Invalid link.'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text("Couldn't open the link."),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Widget _readOnlyTile(
      {required IconData icon, required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
