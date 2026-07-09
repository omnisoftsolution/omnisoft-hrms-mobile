import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/datetime_utils.dart';
import '../../core/theme.dart';
import '../../services/face_recognition_service.dart';
import '../../services/omni_mobile_api.dart';
import '../../services/device_service.dart';
import '../../services/session_service.dart';
import '../../widgets/employee_avatar.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/security_privacy_card.dart';
import '../login/company_settings_screen.dart';
import '../login/login_screen.dart';
import '../payroll/payslips_screen.dart';
import '../face_scan/face_enrollment_screen.dart';
import 'delete_account_screen.dart';

/// Employee profile screen — reached from the avatar in OmniAppBar.
/// Hero avatar + identity, then face enrollment, payslips (gated by
/// subscription), then logout. Diagnostic info (URLs, db, version) is
/// behind the gear icon → CompanySettingsScreen.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    final face = context.watch<FaceRecognitionService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Company settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const CompanySettingsScreen(),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          _hero(context, session),
          const SizedBox(height: 24),
          if (session.employeeCompanyName.isNotEmpty) ...[
            _companyCard(session),
            const SizedBox(height: 16),
          ],
          _identityCard(session),
          // Payslips promoted above approvers/face so it's reachable
          // without scrolling on standard phone heights — monthly
          // viewing is the primary reason most users open Profile.
          const SizedBox(height: 16),
          _payslipCard(context, session),
          if (_hasAnyApprover(session)) ...[
            const SizedBox(height: 16),
            _approversCard(session),
          ],
          // Face enrollment card is only meaningful when the SaaS
          // face_verification flag is on for this company. When off,
          // showing an inert "Enroll Face" card just confuses users
          // — hide it entirely (same pattern as feature-locked tabs).
          if (session.featureFaceVerification) ...[
            const SizedBox(height: 16),
            _faceCard(context, face, session),
          ],
          const SizedBox(height: 16),
          SecurityPrivacyCard(
            login: session.userLogin,
            displayName: session.employeeName,
            verifyPassword: (password) async {
              final api = OmniMobileApi(
                baseUrl: session.clientUrl,
                db: session.clientDb,
                token: '',
              );
              final deviceId = await DeviceService().getDeviceId();
              try {
                final res = await api.login(
                  login: session.userLogin,
                  password: password,
                  deviceId: deviceId,
                  appVersion: AppConstants.appVersion,
                );
                await session.saveLoginResponse(res);
                return PasswordCheck.ok;
              } on ApiException catch (e) {
                return e.errorCode == 'invalid_credentials'
                    ? PasswordCheck.wrongPassword
                    : PasswordCheck.error;
              } catch (_) {
                return PasswordCheck.error;
              }
            },
          ),
          const SizedBox(height: 32),
          PrimaryButton(
            label: 'LOGOUT',
            icon: Icons.logout_rounded,
            variant: PrimaryButtonVariant.danger,
            onPressed: () => _logout(context, session),
          ),
          // App Store / Play Store policy: account deletion path
          // must be reachable from within the app. Kept as a low-key
          // text button so it doesn't compete with LOGOUT as the
          // primary "leave this screen" affordance.
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DeleteAccountScreen(),
                ),
              ),
              child: Text(
                'Delete my account',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.onSurfaceVariant,
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

  // ------------------------------------------------------------------
  // Hero — avatar, name, role line, manager line
  // ------------------------------------------------------------------

  Widget _hero(BuildContext context, SessionService session) {
    final roleLine = _composeRoleLine(session);
    final manager = session.employeeManager;
    return Column(
      children: [
        EmployeeAvatar(
          avatarB64: session.employeeAvatarB64.isEmpty
              ? null
              : session.employeeAvatarB64,
          name: session.employeeName.isNotEmpty
              ? session.employeeName
              : session.userName,
          size: 112,
        ),
        const SizedBox(height: 16),
        Text(
          session.employeeName.isNotEmpty
              ? session.employeeName
              : (session.userName.isNotEmpty ? session.userName : '—'),
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppTheme.onSurface,
            letterSpacing: -0.3,
          ),
        ),
        if (roleLine.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            roleLine,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppTheme.onSurfaceVariant,
            ),
          ),
        ],
        if (manager.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primaryContainer.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.supervisor_account_rounded,
                  size: 14,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Reports to $manager',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Combine job title and department into a single subtitle line.
  /// Either part may be empty; an empty result hides the whole line.
  String _composeRoleLine(SessionService session) {
    final parts = <String>[];
    if (session.employeeJobTitle.isNotEmpty) {
      parts.add(session.employeeJobTitle);
    }
    if (session.employeeDepartment.isNotEmpty) {
      parts.add(session.employeeDepartment);
    }
    return parts.join(' · ');
  }

  // ------------------------------------------------------------------
  // Identity card — login + work contact (only when populated)
  // ------------------------------------------------------------------

  Widget _identityCard(SessionService session) {
    final rows = <Widget>[];
    void addRow(String label, String value, {IconData? icon}) {
      if (value.isEmpty) return;
      if (rows.isNotEmpty) rows.add(const Divider(height: 24));
      rows.add(_kv(label, value, icon: icon));
    }

    addRow('Login', session.userLogin, icon: Icons.alternate_email_rounded);
    addRow('Work email', session.employeeWorkEmail,
        icon: Icons.email_outlined);
    addRow('Work phone', session.employeeWorkPhone,
        icon: Icons.phone_outlined);

    if (rows.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        ),
      ),
    );
  }

  Widget _kv(String label, String value, {IconData? icon}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: AppTheme.onSurfaceVariant),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Company — which res.company this employee belongs to
  // ------------------------------------------------------------------

  /// Decode the company logo base64 once. Returns null on missing or
  /// malformed bytes; the card falls through to the generic icon.
  Uint8List? _decodeCompanyLogo(String b64) {
    if (b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  Widget _companyCard(SessionService session) {
    final logoBytes = _decodeCompanyLogo(session.employeeCompanyLogoB64);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'COMPANY',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppTheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: logoBytes != null
                        ? Colors.white
                        : AppTheme.primaryContainer.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppTheme.outlineVariant.withValues(alpha: 0.6),
                      width: 1,
                    ),
                    image: logoBytes != null
                        ? DecorationImage(
                            image: MemoryImage(logoBytes),
                            fit: BoxFit.contain,
                          )
                        : null,
                  ),
                  child: logoBytes != null
                      ? null
                      : Icon(
                          Icons.business_rounded,
                          size: 22,
                          color: AppTheme.primary,
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    session.employeeCompanyName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Approvers — who to chase when a request sits pending
  // ------------------------------------------------------------------

  bool _hasAnyApprover(SessionService session) {
    if (session.employeeHrApprover.isNotEmpty) return true;
    if (session.employeeTimeOffApprover.isNotEmpty) return true;
    if (session.employeeAttendanceApprover.isNotEmpty) return true;
    // Mirror the gate in _approversCard: expense row only renders
    // when expenses are part of the subscription.
    if (session.featureExpenses &&
        session.employeeExpenseApprover.isNotEmpty) {
      return true;
    }
    return false;
  }

  Widget _approversCard(SessionService session) {
    final rows = <Widget>[];
    void addRow(String label, String value) {
      if (value.isEmpty) return;
      if (rows.isNotEmpty) rows.add(const Divider(height: 20));
      rows.add(_approverRow(label, value));
    }

    addRow('HR RESPONSIBLE', session.employeeHrApprover);
    addRow('TIME OFF', session.employeeTimeOffApprover);
    addRow('ATTENDANCE', session.employeeAttendanceApprover);
    // Only meaningful when the user's subscription includes expenses.
    // Hide the row otherwise — it'd be confusing to chase someone for
    // a feature you can't use on this app.
    if (session.featureExpenses) {
      addRow('EXPENSE', session.employeeExpenseApprover);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.assignment_ind_outlined,
                  size: 18,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Approvers',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...rows,
          ],
        ),
      ),
    );
  }

  Widget _approverRow(String label, String name) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppTheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Payslip card — entry point into the PayslipsScreen list view.
  // Gated by featurePayroll: when locked, shows a non-tappable
  // "not active" state so the same widget covers both gated and
  // active subscriptions.
  // ------------------------------------------------------------------

  Widget _payslipCard(BuildContext context, SessionService session) {
    final enabled = session.featurePayroll;
    final cardBody = Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled
                  ? AppTheme.primaryContainer.withValues(alpha: 0.15)
                  : AppTheme.surfaceContainer,
            ),
            child: Icon(
              enabled
                  ? Icons.payments_rounded
                  : Icons.lock_outline_rounded,
              size: 22,
              color:
                  enabled ? AppTheme.primary : AppTheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  enabled ? 'Payslips' : 'Payslips not active',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  enabled
                      ? 'View and download your published payslips.'
                      : 'Your subscription does not include payroll. '
                          'Contact your administrator to upgrade.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (enabled) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
    if (!enabled) return Card(child: cardBody);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PayslipsScreen()),
          );
        },
        child: cardBody,
      ),
    );
  }

  // ------------------------------------------------------------------
  // Face enrollment — unchanged from prior version, still the source
  // of truth for the user's face state on this device.
  // ------------------------------------------------------------------

  Widget _faceCard(BuildContext context, FaceRecognitionService face,
      SessionService session) {
    final enrolled = face.isEnrolled == true;
    final canReenroll = face.isReenrollAllowed;

    Widget statusText;
    Widget? primaryAction;
    if (!enrolled) {
      statusText = Text(
        'No face enrolled yet. Enroll one to enable face-verified attendance.',
        style: TextStyle(fontSize: 13, color: AppTheme.onSurfaceVariant),
      );
      primaryAction = FilledButton.icon(
        icon: const Icon(Icons.face_rounded),
        label: const Text('Enroll Face'),
        onPressed: face.loading
            ? null
            : () => _openEnroll(context, face, session),
      );
    } else if (!canReenroll) {
      statusText = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Face already enrolled. Contact HR to reset face enrollment.',
            style:
                TextStyle(fontSize: 13, color: AppTheme.onSurfaceVariant),
          ),
          if (face.lastEnrolledAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Enrolled on '
              '${DateTimeUtils.formatLocalDate(face.lastEnrolledAt!.toIso8601String())}.',
              style: TextStyle(
                  fontSize: 12, color: AppTheme.onSurfaceVariant),
            ),
          ],
        ],
      );
      primaryAction = FilledButton.icon(
        icon: const Icon(Icons.lock_rounded),
        label: const Text('Re-enroll Face'),
        onPressed: null,
      );
    } else {
      statusText = Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_open_rounded,
                size: 18, color: AppTheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'HR has allowed face re-enrollment. This will replace your current enrolled face.',
                style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      );
      primaryAction = FilledButton.icon(
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Re-enroll Face'),
        onPressed: face.loading
            ? null
            : () => _openEnroll(context, face, session),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  enrolled
                      ? Icons.verified_user
                      : Icons.face_retouching_off,
                  color: enrolled ? AppTheme.primary : AppTheme.outline,
                ),
                const SizedBox(width: 8),
                const Text('Face Enrollment',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (enrolled)
                  Icon(
                    canReenroll
                        ? Icons.lock_open_rounded
                        : Icons.lock_rounded,
                    size: 16,
                    color: canReenroll
                        ? AppTheme.primary
                        : AppTheme.onSurfaceVariant,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            statusText,
            if (DevConstants.simulateFaceRecognition) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.developer_mode,
                      size: 14, color: Colors.orange),
                  const SizedBox(width: 4),
                  Text(
                    'DEV MODE: face recognition simulated',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: primaryAction),
            // Local-cache wipe is a debugging tool — leaves the
            // server-side enrollment intact, which can confuse a
            // regular user. Show it only in dev builds, gated on the
            // same flag that drives the "DEV MODE" badge above.
            if (DevConstants.simulateFaceRecognition) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.cleaning_services_outlined),
                label: const Text('Clear local face cache'),
                onPressed: face.loading
                    ? null
                    : () async {
                        await face.clearLocalCache();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Local face cache cleared')),
                          );
                          await face.refreshEnrolledStatus(session);
                        }
                      },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _logout(BuildContext context, SessionService session) async {
    // Best-effort server-side revocation; even if it fails (network
    // down, expired session), we still wipe the local copy.
    try {
      final api = OmniMobileApi(
        baseUrl: session.clientUrl,
        db: session.clientDb,
        token: session.token,
      );
      await api.logout();
    } catch (_) {
      // ignored — local clear runs regardless
    }
    // clearSession (not signOut) so a deliberate Log out ends the session
    // but KEEPS the biometric credential — the user can sign back in with
    // Face ID. Delete account / company-change still use signOut().
    await session.clearSession();
    if (context.mounted) {
      // Root navigator: tear down the entire HomeShell (including all
      // tab Navigators and the persistent bottom nav). The tab-scoped
      // Navigator.of(context) here would only clear this tab's stack.
      // autoPromptBiometric: false so we don't immediately re-prompt the
      // user into the session they just left — the button is still there.
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (_) => const LoginScreen(autoPromptBiometric: false)),
        (_) => false,
      );
    }
  }

  Future<void> _openEnroll(BuildContext context,
      FaceRecognitionService face, SessionService session) async {
    // Root navigator so the camera modal isn't stacked inside the
    // tab navigator (would leave the bottom nav bleeding through).
    await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (_) => const FaceEnrollmentScreen(),
      ),
    );
    if (context.mounted) {
      await face.refreshEnrolledStatus(session);
    }
  }
}
