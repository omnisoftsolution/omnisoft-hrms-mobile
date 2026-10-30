import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/omni_colors.dart';
import '../../services/auto/auto_attendance_service.dart';
import 'auto_setup_screen.dart';

/// Asks the system for one location step and answers the permission the
/// phone has afterwards: `always`, `while_using`, `denied` (may be asked
/// again) or `blocked` (denied for good: only the system settings can
/// change it). [step] is `while_using`, `always` or `settings` (opens the
/// app's system settings, Android's only way to "Allow all the time").
typedef AutoPermissionRequest = Future<String> Function(String step);

/// What the card and the result say when the session is not this phone's
/// (`needsSetup`, `device_required`): a location permission cannot fix it.
const autoNeedsThisPhoneText =
    'Automatic check-in needs this phone to be your signed-in phone. Sign '
    'out and sign in again on this phone, then come back here.';

/// The real [AutoPermissionRequest]; widget tests pass a fake instead so
/// nothing touches a platform channel.
Future<String> requestAutoPermission(String step) async {
  try {
    switch (step) {
      case 'while_using':
        await Permission.locationWhenInUse.request();
      case 'always':
        await Permission.locationAlways.request();
      case 'settings':
        await openAppSettings();
    }
    if (await Permission.locationAlways.isGranted) return 'always';
    if (await Permission.locationWhenInUse.isGranted) return 'while_using';
    if (await Permission.locationWhenInUse.isPermanentlyDenied) {
      return 'blocked';
    }
  } catch (_) {
    // Treated as not granted; the sync after the flow reads the truth.
  }
  return 'denied';
}

/// "Automatic check-in" card at the top of My day's list. Shows
/// while the phone still needs setting up (or the employee turned it off
/// here) and is gone once it is on.
class AutoSetupCard extends StatelessWidget {
  const AutoSetupCard({
    super.key,
    required this.auto,
    this.requestPermission = requestAutoPermission,
    this.isIos,
  });

  final AutoAttendanceService auto;

  @visibleForTesting
  final AutoPermissionRequest requestPermission;

  /// Platform choice; null reads `Platform.isIOS`.
  @visibleForTesting
  final bool? isIos;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: auto,
      builder: (context, _) {
        final state = auto.state;
        if (state != AutoPhoneState.needsSetup &&
            state != AutoPhoneState.needsAlways &&
            state != AutoPhoneState.optedOut) {
          return const SizedBox.shrink();
        }
        final c = context.omni;
        final text = Theme.of(context).textTheme;
        final office = auto.config?.office.name ?? 'your office';
        final optedOut = state == AutoPhoneState.optedOut;
        final needsPhone = state == AutoPhoneState.needsSetup;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Container(
            key: const ValueKey('auto-setup-card'),
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: c.accentTint,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.my_location_rounded,
                      size: 20,
                      color: c.onAccentTint,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Automatic check-in',
                        style: text.titleMedium?.copyWith(
                          color: c.onAccentTint,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  needsPhone
                      ? autoNeedsThisPhoneText
                      : optedOut
                      ? 'Automatic check-in is off on this phone. Turn it on '
                            'and Omni HR checks you in and out at $office.'
                      : 'Your HR turned it on. Set it up once and Omni HR '
                            'checks you in and out at $office.',
                  style: text.bodyMedium?.copyWith(color: c.onAccentTint),
                ),
                // A permission cannot fix a session that is not this phone's.
                if (!needsPhone) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      key: const ValueKey('auto-setup-button'),
                      onPressed: () => _onPressed(context, optedOut),
                      child: Text(optedOut ? 'Turn on' : 'Set up'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _onPressed(BuildContext context, bool optedOut) async {
    final navigator = Navigator.of(context);
    if (optedOut) {
      await auto.turnOnAgain();
      // On again: nothing more to do unless the permission is missing (a
      // session that is not this phone's shows its own card text).
      if (auto.state != AutoPhoneState.needsAlways) return;
    }
    await navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => AutoSetupScreen(
          auto: auto,
          requestPermission: requestPermission,
          isIos: isIos,
        ),
      ),
    );
  }
}
