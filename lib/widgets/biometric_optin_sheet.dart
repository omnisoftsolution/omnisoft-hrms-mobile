import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/biometric_types.dart';
import 'primary_button.dart';

/// Human label for a biometric kind, used in button/body copy.
String biometricLabel(BiometricKind kind) {
  switch (kind) {
    case BiometricKind.faceId:
      return 'Face ID';
    case BiometricKind.touchId:
      return 'Touch ID';
    case BiometricKind.fingerprint:
      return 'fingerprint';
    case BiometricKind.face:
      return 'face unlock';
    case BiometricKind.iris:
      return 'iris';
    case BiometricKind.generic:
    case BiometricKind.none:
      return 'biometric';
  }
}

IconData _iconFor(BiometricKind kind) {
  switch (kind) {
    case BiometricKind.faceId:
    case BiometricKind.face:
      return Icons.face;
    default:
      return Icons.fingerprint;
  }
}

/// Post-login opt-in prompt (Flow A). Pure widget — callbacks injected.
class BiometricOptInSheet extends StatelessWidget {
  final BiometricKind kind;
  final VoidCallback onEnable;
  final VoidCallback onNotNow;

  const BiometricOptInSheet({
    super.key,
    required this.kind,
    required this.onEnable,
    required this.onNotNow,
  });

  @override
  Widget build(BuildContext context) {
    final label = biometricLabel(kind);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconFor(kind), size: 56, color: AppTheme.primary),
          const SizedBox(height: 16),
          Text('Faster sign-in next time',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            'Use $label to log back in when your session expires, '
            'instead of typing your password.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          PrimaryButton(label: 'Enable $label', onPressed: onEnable),
          const SizedBox(height: 8),
          TextButton(onPressed: onNotNow, child: const Text('Not now')),
        ],
      ),
    );
  }
}

/// Shows [BiometricOptInSheet] as a modal bottom sheet and returns the
/// user's choice: true (enable), false (not now), or null (dismissed by
/// tapping the barrier). The caller is responsible for awaiting this and
/// then performing the enable/dismiss work itself, so it can run before
/// any subsequent navigation.
Future<bool?> showBiometricOptInSheet(
  BuildContext context, {
  required BiometricKind kind,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surfaceContainerLowest,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => BiometricOptInSheet(
      kind: kind,
      onEnable: () => Navigator.of(ctx).pop(true),
      onNotNow: () => Navigator.of(ctx).pop(false),
    ),
  );
}
