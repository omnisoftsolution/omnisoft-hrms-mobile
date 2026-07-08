import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/biometric_types.dart';
import 'biometric_optin_sheet.dart' show biometricLabel;
import 'primary_button.dart';

/// Biometric variant of the login screen (Flow B). Pure widget —
/// callbacks and data injected; no provider/network access here.
class BiometricLoginPanel extends StatelessWidget {
  final BiometricKind kind;
  final String greetingName;
  final String companyName;
  final String? companyLogoB64;
  final bool busy;
  final VoidCallback onBiometric;
  final VoidCallback onUsePassword;

  const BiometricLoginPanel({
    super.key,
    required this.kind,
    required this.greetingName,
    required this.companyName,
    required this.companyLogoB64,
    required this.busy,
    required this.onBiometric,
    required this.onUsePassword,
  });

  @override
  Widget build(BuildContext context) {
    final label = biometricLabel(kind);
    final greeting =
        greetingName.isEmpty ? 'Welcome back' : 'Welcome back, $greetingName';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _logo(),
            const SizedBox(height: 16),
            Text(companyName,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Text(greeting,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Log in with $label',
              icon: kind == BiometricKind.faceId || kind == BiometricKind.face
                  ? Icons.face
                  : Icons.fingerprint,
              loading: busy,
              onPressed: busy ? null : onBiometric,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: busy ? null : onUsePassword,
              child: const Text('Use password instead'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logo() {
    final b64 = companyLogoB64;
    if (b64 != null && b64.isNotEmpty) {
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.memory(base64Decode(b64), width: 88, height: 88),
        );
      } catch (_) {
        // fall through to the icon
      }
    }
    return Icon(Icons.badge_outlined, size: 72, color: AppTheme.primary);
  }
}
