import 'package:flutter/material.dart';

import '../../core/omni_colors.dart';
import '../../services/auto/auto_attendance_service.dart';
import 'auto_setup_card.dart';
import 'auto_setup_screen.dart';

/// One short phrase for what automatic check-in is doing on this phone
/// (Profile's subtitle and the status screen's first row).
String autoStateWord(AutoPhoneState state, {String? office}) {
  switch (state) {
    case AutoPhoneState.on:
      return (office == null || office.isEmpty) ? 'On' : 'On · $office';
    case AutoPhoneState.waitingWifi:
      return 'Waiting for office Wi-Fi';
    case AutoPhoneState.needsAlways:
      // Also the state before setup was ever done (F-a): nothing is paused.
      return 'Needs location access';
    case AutoPhoneState.optedOut:
      return 'Off on this phone';
    case AutoPhoneState.needsSetup:
      return 'Not set up';
    case AutoPhoneState.off:
      return 'Off';
  }
}

/// What the location permission amounts to in each state.
String _permissionWord(AutoPhoneState state) {
  switch (state) {
    case AutoPhoneState.on:
    case AutoPhoneState.waitingWifi:
      return 'Always allowed';
    case AutoPhoneState.needsAlways:
      return 'Needs "Always"';
    case AutoPhoneState.optedOut:
      return 'Not used (off on this phone)';
    case AutoPhoneState.needsSetup:
    case AutoPhoneState.off:
      return 'Not checked';
  }
}

/// Profile -> Automatic check-in: the office, how it triggers, the
/// permission and the buttons to fix it or turn it off on this phone.
class AutoCheckinScreen extends StatelessWidget {
  const AutoCheckinScreen({
    super.key,
    required this.auto,
    this.requestPermission = requestAutoPermission,
    this.isIos,
  });

  final AutoAttendanceService auto;

  @visibleForTesting
  final AutoPermissionRequest requestPermission;

  /// Platform choice for the setup flow; null reads `Platform.isIOS`.
  @visibleForTesting
  final bool? isIos;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Automatic check-in')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: auto,
          builder: (context, _) => _body(context),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final c = context.omni;
    final text = Theme.of(context).textTheme;
    final state = auto.state;
    final cfg = auto.config;
    final active =
        state == AutoPhoneState.on ||
        state == AutoPhoneState.waitingWifi ||
        state == AutoPhoneState.needsAlways;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row(c, text, 'Status', autoStateWord(state)),
                if (cfg != null) ...[
                  _row(c, text, 'Office', cfg.office.name),
                  _row(
                    c,
                    text,
                    'Area',
                    '${cfg.office.areaM} m around the office',
                  ),
                  _row(
                    c,
                    text,
                    'Triggers on',
                    // The server's answer for this office (F-c): Location +
                    // Wi-Fi falls back to Location without a Wi-Fi list.
                    cfg.wifiRequired ? 'Location + Wi-Fi' : 'Location',
                  ),
                ],
                _row(c, text, 'Location permission', _permissionWord(state)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (state == AutoPhoneState.needsSetup)
          Text(
            autoNeedsThisPhoneText,
            style: text.bodyMedium?.copyWith(color: c.textSub, height: 1.4),
          ),
        if (state == AutoPhoneState.needsAlways) ...[
          FilledButton(
            key: const ValueKey('auto-fix-button'),
            onPressed: () => _fix(context),
            child: const Text('Fix permission'),
          ),
          const SizedBox(height: 8),
        ],
        if (active)
          OutlinedButton(
            key: const ValueKey('auto-turnoff-button'),
            onPressed: () => _confirmTurnOff(context),
            child: const Text('Turn off on this phone'),
          ),
        if (state == AutoPhoneState.optedOut)
          FilledButton(
            key: const ValueKey('auto-turnon-button'),
            onPressed: auto.turnOnAgain,
            child: const Text('Turn on again'),
          ),
      ],
    );
  }

  Widget _row(OmniColors c, TextTheme text, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.bodySmall?.copyWith(color: c.textSub)),
          const SizedBox(height: 2),
          Text(
            value,
            style: text.bodyLarge?.copyWith(
              color: c.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _fix(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AutoSetupScreen(
          auto: auto,
          requestPermission: requestPermission,
          isIos: isIos,
        ),
      ),
    );
  }

  Future<void> _confirmTurnOff(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn off on this phone?'),
        content: const Text(
          'Omni HR stops checking you in and out here. You can still check '
          'in yourself, and you can turn it on again any time.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('auto-turnoff-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('auto-turnoff-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
    if (yes == true) await auto.turnOffOnThisPhone();
  }
}
