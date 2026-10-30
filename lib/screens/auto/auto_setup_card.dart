import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/omni_colors.dart';
import '../../services/auto/auto_attendance_service.dart';
import 'auto_setup_screen.dart';

/// Asks the system for one location step and answers the permission the
/// phone has afterwards: `always`, `while_using` or `denied`. [step] is
/// `while_using`, `always` or `settings` (opens the app's system settings,
/// Android's only way to "Allow all the time").
typedef AutoPermissionRequest = Future<String> Function(String step);

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
  } catch (_) {
    // Treated as not granted; the sync after the flow reads the truth.
  }
  return 'denied';
}

/// "Automatic check-in" card on My day, right below the status tile. Shows
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
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
                    Text(
                      'Automatic check-in',
                      style: text.titleMedium?.copyWith(
                        color: c.onAccentTint,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  optedOut
                      ? 'Automatic check-in is off on this phone. Turn it on '
                            'and Omni HR checks you in and out at $office.'
                      : 'Your HR turned it on. Set it up once and Omni HR '
                            'checks you in and out at $office.',
                  style: text.bodyMedium?.copyWith(color: c.onAccentTint),
                ),
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
      // On again: nothing more to do unless the permission is missing.
      final s = auto.state;
      if (s != AutoPhoneState.needsAlways && s != AutoPhoneState.needsSetup) {
        return;
      }
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
