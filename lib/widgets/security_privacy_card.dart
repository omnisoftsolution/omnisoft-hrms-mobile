import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../services/biometric_auth_service.dart';
import '../services/biometric_types.dart';
import 'biometric_optin_sheet.dart' show biometricLabel;

/// Profile → "Security & Privacy" card. Hosts the biometric-login toggle
/// (only when the device is biometric-capable) and the Privacy Policy link.
/// [login] and [displayName] come from the signed-in SessionService at the
/// call site and are used when enabling biometric login (the password is
/// confirmed once here — it is not retained after login).
class SecurityPrivacyCard extends StatefulWidget {
  const SecurityPrivacyCard({
    super.key,
    required this.login,
    required this.displayName,
  });

  final String login;
  final String displayName;

  @override
  State<SecurityPrivacyCard> createState() => _SecurityPrivacyCardState();
}

class _SecurityPrivacyCardState extends State<SecurityPrivacyCard> {
  bool _bioCapable = false;
  BiometricKind _bioKind = BiometricKind.none;

  @override
  void initState() {
    super.initState();
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

  Future<void> _toggleBiometric(bool on) async {
    final bio = context.read<BiometricAuthService>();
    if (!on) {
      await bio.disable();
      return;
    }
    final password = await _promptPassword();
    if (password == null || password.isEmpty) return;
    final ok = await bio.enable(
      login: widget.login,
      password: password,
      displayName: widget.displayName,
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

  Future<void> _openExternalUrl(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(url);
    if (uri == null) {
      messenger.showSnackBar(SnackBar(
          content: const Text('Invalid link.'),
          backgroundColor: AppTheme.error));
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      messenger.showSnackBar(SnackBar(
          content: const Text("Couldn't open the link."),
          backgroundColor: AppTheme.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.security, size: 18, color: AppTheme.primary),
                const SizedBox(width: 8),
                const Text('Security & Privacy',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            if (_bioCapable) ...[
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${biometricLabel(_bioKind)} login'),
                subtitle: Text('Log in with ${biometricLabel(_bioKind)} '
                    'when your session expires.'),
                value: context.watch<BiometricAuthService>().isEnabled,
                onChanged: _toggleBiometric,
              ),
            ],
            const SizedBox(height: 12),
            _linkTile(
              icon: Icons.shield_outlined,
              label: 'Privacy Policy',
              url: AppConstants.privacyPolicyUrl,
            ),
          ],
        ),
      ),
    );
  }

  Widget _linkTile({
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
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.open_in_new, size: 16, color: AppTheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
