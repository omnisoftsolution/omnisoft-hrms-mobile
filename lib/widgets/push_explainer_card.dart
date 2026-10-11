import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme.dart';
import '../services/push_service.dart';
import 'primary_button.dart';

/// Home's one-time notification explainer (spec 2026-10-11 §6.2): our own
/// words first; only "Turn on notifications" opens the system prompt.
class PushExplainerCard extends StatelessWidget {
  const PushExplainerCard({
    super.key,
    required this.onTurnOn,
    required this.onNotNow,
    this.busy = false,
  });

  final VoidCallback? onTurnOn;
  final VoidCallback? onNotNow;

  /// The system prompt is up: both buttons wait.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    // Bottom CTAs: viewPadding, because an ancestor may consume padding.
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      key: const ValueKey('push-explainer-body'),
      padding: EdgeInsets.fromLTRB(24, 24, 24, bottom + 24),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryContainer.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(
                        Icons.notifications_active_rounded,
                        size: 40,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Stay on top of your day',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Text(
                        'Get told when your leave is approved, when someone '
                        'needs your approval, and when you forget to check in '
                        'or out.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          height: 1.4,
                          color: AppTheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          PrimaryButton(
            label: 'Turn on notifications',
            loading: busy,
            onPressed: busy ? null : onTurnOn,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: busy ? null : onNotNow,
              child: const Text('Not now'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'You can change it later in Profile → Notifications.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppTheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the explainer full screen on the root navigator, above the tabs,
/// and marks it seen first (so it is never shown twice, even if the app is
/// closed while it is up).
Future<void> showPushExplainer(BuildContext context, PushService push) async {
  await push.markExplainerSeen();
  if (!context.mounted) return;
  await Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _PushExplainerPage(push: push),
    ),
  );
}

class _PushExplainerPage extends StatefulWidget {
  const _PushExplainerPage({required this.push});

  final PushService push;

  @override
  State<_PushExplainerPage> createState() => _PushExplainerPageState();
}

class _PushExplainerPageState extends State<_PushExplainerPage> {
  bool _busy = false;

  Future<void> _turnOn() async {
    setState(() => _busy = true);
    await widget.push.requestPermission();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        // The card pads the bottom itself (viewPadding).
        bottom: false,
        child: PushExplainerCard(
          busy: _busy,
          onTurnOn: _turnOn,
          onNotNow: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}
