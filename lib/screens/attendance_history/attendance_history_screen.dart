import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/error_messages.dart';
import '../../widgets/error_state_view.dart';
import '../../models/attendance_record.dart';
import '../../services/omni_mobile_api.dart';
import '../../services/session_service.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  State<AttendanceHistoryScreen> createState() =>
      AttendanceHistoryScreenState();
}

class AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  List<AttendanceRecord> _records = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  Future<void> refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = context.read<SessionService>();
      final api = OmniMobileApi(
        baseUrl: session.clientUrl,
        db: session.clientDb,
        token: session.token,
      );
      _records = await api.getAttendanceHistory();
    } catch (e) {
      _error = friendlyError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Mode-pill background color. Mobile = primary (the expected source),
  /// Manual = secondary (HR tweak), Auto check-out = error (system stepped in).
  Color _modeColor(String? mode) {
    switch (mode) {
      case 'kiosk':
      case 'systray':
        return AppTheme.primary;
      case 'manual':
        return AppTheme.secondary;
      case 'auto_check_out':
        return AppTheme.error;
      default:
        return AppTheme.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 80, 20, 24),
          children: [
            ErrorStateView(message: _error!, onRetry: refresh),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: refresh,
      child: _records.isEmpty
          ? ListView(children: [
              const SizedBox(height: 100),
              const Center(child: Text('No attendance records yet')),
              const SizedBox(height: 24),
              _scopeFooter(),
            ])
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              // +1 row for the "Showing the last 30 days" footer.
              itemCount: _records.length + 1,
              itemBuilder: (_, i) => i == _records.length
                  ? _scopeFooter()
                  : _buildItem(_records[i]),
            ),
    );
  }

  Widget _scopeFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
      child: Center(
        child: Text(
          'Showing the last 30 days',
          style: GoogleFonts.inter(
            fontSize: 12,
            color: AppTheme.outline,
          ),
        ),
      ),
    );
  }

  Widget _buildItem(AttendanceRecord r) {
    final dateFmt = DateFormat('EEE, dd MMM yyyy');
    final timeFmt = DateFormat('HH:mm');
    final dateLabel = r.date != null
        ? dateFmt.format(r.date!)
        : (r.checkIn != null ? dateFmt.format(r.checkIn!) : '—');
    final inLabel = r.checkIn != null ? timeFmt.format(r.checkIn!) : '—';
    final outLabel =
        r.checkOut != null ? timeFmt.format(r.checkOut!) : 'In progress';
    final hours = r.isOpen
        ? '${r.hoursLabel} so far'
        : r.hoursLabel;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dateLabel,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(
                        '$inLabel  →  $outLabel  ·  $hours',
                        style: TextStyle(
                            fontSize: 13, color: AppTheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _modeColor(r.inMode).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    r.modeLabel,
                    style: TextStyle(
                      color: _modeColor(r.inMode),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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
}
