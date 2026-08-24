import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/error_messages.dart';
import '../../core/money.dart';
import '../../models/payslip_record.dart';
import '../../services/omni_mobile_api.dart';
import '../../services/session_service.dart';
import '../../widgets/feature_locked_pane.dart';
import '../../widgets/file_viewer.dart';
import '../../widgets/omni_app_bar.dart';
import 'pdf_viewer_screen.dart';

/// Payroll tab — list of the employee's published payslips. Tap a
/// card to fetch the official Odoo-rendered PDF and hand it to the
/// system viewer (same path the expense receipt preview uses).
///
/// Subscription-gated via `session.featurePayroll`. Read-only: no
/// editing, no aggregation. Mobile is a viewer; payroll math lives
/// in Odoo.
class PayslipsScreen extends StatefulWidget {
  const PayslipsScreen({super.key});

  @override
  State<PayslipsScreen> createState() => PayslipsScreenState();
}

class PayslipsScreenState extends State<PayslipsScreen> {
  List<PayslipRecord> _records = const [];
  bool _loading = false;
  String? _error;
  // Tracks the payslip id that's currently being fetched as a PDF
  // so we can render a per-row spinner without freezing the rest of
  // the list.
  int? _openingId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
    });
  }

  Future<void> refresh() => _refresh();

  Future<void> _refresh() async {
    final session = context.read<SessionService>();
    if (!session.featurePayroll || !session.isLoggedIn) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = OmniMobileApi(
        baseUrl: session.clientUrl,
        db: session.clientDb,
        token: session.token,
      );
      final list = await api.getPayslips();
      if (!mounted) return;
      setState(() => _records = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openPayslip(PayslipRecord r) async {
    if (_openingId != null) return;
    final session = context.read<SessionService>();
    setState(() => _openingId = r.id);
    try {
      final api = OmniMobileApi(
        baseUrl: session.clientUrl,
        db: session.clientDb,
        token: session.token,
      );
      final body = await api.getPayslipPdf(r.id);
      final dataB64 = body['data_b64']?.toString() ?? '';
      final filename = body['filename']?.toString() ?? 'payslip.pdf';
      if (dataB64.isEmpty) {
        if (!mounted) return;
        showFileViewError(context, 'Empty PDF payload.');
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(
            dataB64: dataB64,
            filename: filename,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      final serverMsg = e.data?['message']?.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(serverMsg?.isNotEmpty == true
              ? serverMsg!
              : _humanizePayslipError(e.errorCode)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open payslip: $e')),
      );
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  String _humanizePayslipError(String code) {
    switch (code) {
      case 'render_failed':
        return 'Server could not render the PDF. Please contact HR.';
      case 'not_published':
        return 'Payslip is not yet published.';
      case 'not_owner':
        return 'You can only view your own payslips.';
      case 'not_found':
        return 'Payslip not found.';
      default:
        return 'Could not load payslip. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    return Scaffold(
      appBar: const OmniAppBar(title: 'Payroll'),
      body: SafeArea(
        child: !session.featurePayroll
            ? const FeatureLockedPane(
                featureName: 'Payroll',
                subtitle: 'Your subscription does not include payslip '
                    'access. Contact your administrator to upgrade.',
              )
            : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _records.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _records.isEmpty) {
      return _errorPane(_error!);
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: _records.isEmpty
          ? _emptyState()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: _records.length,
              itemBuilder: (_, i) => _payslipTile(_records[i]),
            ),
    );
  }

  Widget _emptyState() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
      children: [
        Container(
          width: 88,
          height: 88,
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.primaryContainer.withValues(alpha: 0.12),
            border: Border.all(
              color: AppTheme.primaryContainer.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          child: Icon(
            Icons.payments_rounded,
            size: 36,
            color: AppTheme.primary,
          ),
        ),
        Text(
          'No payslips yet',
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
          "When HR publishes your payslip, it'll appear here.",
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: AppTheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _payslipTile(PayslipRecord r) {
    final isOpening = _openingId == r.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: isOpening ? null : () => _openPayslip(r),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primaryContainer.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: isOpening
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Icon(
                        Icons.payments_rounded,
                        color: AppTheme.primary,
                        size: 22,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _periodLabel(r),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      r.name.isEmpty ? '—' : r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    payslipAmount(r),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _stateColor(r.state).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      r.stateLabel.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: _stateColor(r.state),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Most payslips span a calendar month, so prefer the month label
  /// ("Apr 2026"). Falls back to a range when from/to cross months.
  String _periodLabel(PayslipRecord r) {
    final from = DateTime.tryParse(r.dateFrom);
    final to = DateTime.tryParse(r.dateTo);
    if (from == null || to == null) return r.name;
    final sameMonth = from.year == to.year && from.month == to.month;
    if (sameMonth) {
      return DateFormat('MMM yyyy').format(from);
    }
    return '${DateFormat('d MMM').format(from)} – '
        '${DateFormat('d MMM yyyy').format(to)}';
  }

  Color _stateColor(String state) {
    switch (state) {
      case 'paid':
        return const Color(0xFF22C55E);
      case 'done':
        return AppTheme.primary;
      case 'validated':
        // Distinct non-grey color so a validated-but-not-paid payslip
        // reads as live, not stale.
        return AppTheme.secondary;
      default:
        return AppTheme.onSurfaceVariant;
    }
  }

  Widget _errorPane(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: AppTheme.error, size: 48),
            const SizedBox(height: 12),
            Text(msg,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.error)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _refresh,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
