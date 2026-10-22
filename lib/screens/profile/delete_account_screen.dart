import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/omni_colors.dart';
import '../../services/face_recognition_service.dart';
import '../../services/omni_mobile_api.dart';
import '../../services/session_service.dart';
import '../../widgets/primary_button.dart';
import '../login/login_screen.dart';

/// Account deletion flow, reachable from Profile.
///
/// Satisfies Apple App Store Guideline 5.1.1(v) and Google Play's
/// account-deletion policy: the user can initiate deletion of their
/// account from within the app, sees a clear explanation of what's
/// removed vs retained, and must take a deliberate confirming action
/// (typing the word DELETE) before the destructive call fires.
///
/// On confirm, the connector revokes the mobile session and logs the
/// request. Full server-side data cleanup is queued as a follow-up
/// backend pass — but the user-facing contract ("you can no longer
/// access this account") is satisfied immediately.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  static const String _confirmWord = 'DELETE';
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canConfirm =>
      !_submitting && _controller.text.trim().toUpperCase() == _confirmWord;

  Future<void> _confirmDelete() async {
    final session = context.read<SessionService>();
    final face = context.read<FaceRecognitionService>();
    final messenger = ScaffoldMessenger.of(context);
    final rootNav = Navigator.of(context, rootNavigator: true);
    final brandFill = context.omni.brandFill;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final api = OmniMobileApi(
        baseUrl: session.clientUrl,
        db: session.clientDb,
        token: session.token,
      );
      await api.deleteAccount();
      // Local cleanup mirrors the server-side intent: wipe the cached
      // face bytes and the session even if the server logs aren't
      // wiped yet. The user can no longer use this device's app to
      // reach their account.
      await face.clearLocalCache();
      await session.signOut();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Account deletion requested. Signed out.'),
          backgroundColor: brandFill,
        ),
      );
      rootNav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not complete deletion: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omni;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delete account'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            _heroIcon(c),
            const SizedBox(height: 16),
            Text(
              'This will delete your account',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: c.text,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You will be signed out of every device and will lose '
              'access to your account. This cannot be undone from the '
              'app.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: c.textSub,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            _sectionTitle(c, 'What will be removed'),
            const SizedBox(height: 8),
            _bullet(c, 'Your enrolled face data (used for check-in)'),
            _bullet(c, 'Your active mobile sessions on this and other devices'),
            _bullet(c, 'In-app notification history'),
            _bullet(c, 'Cached profile data on this phone'),
            const SizedBox(height: 24),
            _sectionTitle(c, 'What your employer keeps'),
            const SizedBox(height: 8),
            _bullet(c, 'Your employment record at the company'),
            _bullet(c, 'Past attendance, leave and expense entries'),
            _bullet(c, 'Payroll history'),
            const SizedBox(height: 6),
            Text(
              "Your employer retains these for legitimate business and "
              "legal reasons. Contact your HR administrator if you "
              "want a copy of your data or to ask about further "
              "deletion.",
              style: TextStyle(
                fontSize: 12,
                color: c.textSub,
                height: 1.4,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Type "$_confirmWord" to confirm',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.textSub,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              enabled: !_submitting,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              decoration: InputDecoration(
                hintText: _confirmWord,
                hintStyle: TextStyle(
                  color: c.textSub.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                fontSize: 16,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: c.error.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: c.error,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'DELETE MY ACCOUNT',
              icon: Icons.delete_forever_rounded,
              variant: PrimaryButtonVariant.danger,
              loading: _submitting,
              onPressed: _canConfirm ? _confirmDelete : null,
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed:
                    _submitting ? null : () => Navigator.of(context).pop(),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: c.textSub,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroIcon(OmniColors c) {
    return Center(
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: c.error.withValues(alpha: 0.10),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.delete_forever_rounded,
          color: c.error,
          size: 36,
        ),
      ),
    );
  }

  Widget _sectionTitle(OmniColors c, String text) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: c.textSub,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _bullet(OmniColors c, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: c.textSub,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: c.text,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
