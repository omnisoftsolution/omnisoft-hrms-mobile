import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/saas_service.dart';
import '../services/session_service.dart';
import 'primary_button.dart';

/// Shown wherever a feature (Time Off, Payroll, Expenses, …) is
/// disabled by the SaaS subscription. Includes a "Refresh
/// subscription" button that re-runs the SaaS resolve so users
/// don't have to log out + back in after their admin upgrades.
class FeatureLockedPane extends StatefulWidget {
  /// Display name for the feature, e.g. "Time Off".
  final String featureName;

  /// Short description of what this feature unlocks.
  final String? subtitle;

  /// Optional callback fired after a successful subscription refresh.
  /// Useful when the parent wants to e.g. switch to a different tab.
  final VoidCallback? onRefreshed;

  const FeatureLockedPane({
    super.key,
    required this.featureName,
    this.subtitle,
    this.onRefreshed,
  });

  @override
  State<FeatureLockedPane> createState() => _FeatureLockedPaneState();
}

class _FeatureLockedPaneState extends State<FeatureLockedPane> {
  bool _refreshing = false;
  String? _error;

  Future<void> _refresh() async {
    final session = context.read<SessionService>();
    if (session.saasUrl.isEmpty || session.companyCode.isEmpty) {
      setState(() => _error =
          'Company is not configured. Open Settings to set it up.');
      return;
    }
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final info = await SaasService()
          .resolveCompany(session.saasUrl, session.companyCode);
      await session.saveCompany(
        saasUrl: session.saasUrl,
        companyCode: info.companyCode,
        clientUrl: info.odooUrl,
        clientDb: info.database,
        features: info.features,
        companyName: info.name,
        companyLogoB64: info.companyLogoB64,
        showConnectionDetails: info.showConnectionDetails,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.primary,
          content: const Text('Subscription refreshed.'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      widget.onRefreshed?.call();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.outline.withValues(alpha: 0.08),
              border: Border.all(
                color: AppTheme.outline.withValues(alpha: 0.2),
                width: 1.5,
              ),
            ),
            child: Icon(
              Icons.lock_outline_rounded,
              size: 36,
              color: AppTheme.outline,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '${widget.featureName} not active',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.onSurface,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.subtitle ??
                'Your subscription does not include ${widget.featureName}. '
                    'Contact your administrator to upgrade.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppTheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      color: AppTheme.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                          color: AppTheme.error, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),
          PrimaryButton(
            label: 'REFRESH SUBSCRIPTION',
            icon: Icons.refresh_rounded,
            loading: _refreshing,
            onPressed: _refreshing ? null : _refresh,
          ),
        ],
      ),
    );
  }
}
