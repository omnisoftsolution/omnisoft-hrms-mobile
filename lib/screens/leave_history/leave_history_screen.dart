import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/error_messages.dart';
import '../../models/leave_record.dart';
import '../../models/leave_type.dart';
import '../../services/omni_mobile_api.dart';
import '../../services/session_service.dart';
import '../../services/holiday_service.dart';
import '../../widgets/auto_pickers.dart';
import '../../widgets/error_state_view.dart';
import '../../widgets/document_picker_field.dart';
import '../../widgets/file_viewer.dart';
import '../../widgets/range_picker_dialog.dart';

class LeaveHistoryScreen extends StatefulWidget {
  const LeaveHistoryScreen({super.key});

  @override
  State<LeaveHistoryScreen> createState() => LeaveHistoryScreenState();
}

class LeaveHistoryScreenState extends State<LeaveHistoryScreen> {
  List<LeaveRecord> _leaves = [];
  bool _loading = true;
  String? _error;
  int? _expandedId;
  // Set briefly when a notification deep-links to a specific leave —
  // the matching card pulses with a tinted background and auto-
  // expands. Cleared after ~2.5 s.
  int? _highlightId;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Scroll to a leave by id, expand its card, and flash a teal tint
  /// behind it that fades over ~2.5 s. Triggered when the user taps a
  /// "Leave approved/refused" notification.
  Future<void> scrollToAndHighlight(int leaveId) async {
    // Refresh first so a freshly-approved leave is in our list.
    await refresh();
    if (!mounted) return;
    final index = _leaves.indexWhere((l) => l.id == leaveId);
    if (index < 0) {
      // Older than the 50-record cap — just show a hint and bail.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That leave is older than the most recent 50 — '
              'scroll the list to find it.'),
        ),
      );
      return;
    }
    setState(() {
      _expandedId = leaveId;
      _highlightId = leaveId;
    });
    // Approximate scroll position. Cards are ~110 px collapsed and
    // grow when the highlighted one auto-expands; 140 lands close
    // enough on the iPhone-width canvas. Worst case the user scrolls
    // a bit, but the highlight tint guides their eye.
    final target = (index * 140.0).clamp(
        0.0, _scrollController.position.maxScrollExtent);
    if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    }
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;
    if (_highlightId == leaveId) {
      setState(() => _highlightId = null);
    }
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
      _leaves = await api.getLeaveHistory();
    } catch (e) {
      _error = friendlyError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtDays(double n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(1);

  Color _stateColor(String state) {
    switch (state) {
      case 'validate':
      case 'validate1':
        return AppTheme.primary;
      case 'refuse':
        return AppTheme.error;
      case 'confirm':
        return AppTheme.secondary;
      case 'cancel':
        return AppTheme.outline;
      default:
        return AppTheme.outline;
    }
  }

  OmniMobileApi _api() {
    final s = context.read<SessionService>();
    return OmniMobileApi(
      baseUrl: s.clientUrl,
      db: s.clientDb,
      token: s.token,
    );
  }

  Future<void> _openCancelDialog(LeaveRecord r) async {
    final confirmed = await showDialog<({bool ok, String reason})>(
      context: context,
      builder: (_) => _CancelLeaveDialog(record: r),
    );
    if (confirmed == null || !confirmed.ok || !mounted) return;
    try {
      await _api().cancelLeave(
        leaveId: r.id,
        reason: confirmed.reason.isEmpty ? null : confirmed.reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Leave cancelled'),
          backgroundColor: AppTheme.primary,
        ),
      );
      await refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _viewHistoryAttachment(LeaveAttachment a) async {
    try {
      final res = await _api().getAttachment(a.id);
      final dataB64 = (res['data_b64'] ?? '').toString();
      if (dataB64.isEmpty) throw Exception('empty file');
      final err = await openBase64File(name: a.name, dataB64: dataB64);
      if (err != null && mounted) showFileViewError(context, err);
    } catch (e) {
      if (mounted) showFileViewError(context, e.toString());
    }
  }

  Future<void> _openEditSheet(LeaveRecord r) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // Persistent bottom nav lives in HomeShell. Root navigator
      // ensures the sheet overlays the bottom nav, not our tab's
      // nested Navigator.
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _EditLeaveSheet(record: r, api: _api()),
    );
    if (saved == true) await refresh();
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
      child: _leaves.isEmpty
          ? ListView(
              controller: _scrollController,
              children: const [
                SizedBox(height: 100),
                Center(child: Text('No leave records yet')),
              ],
            )
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _leaves.length,
              itemBuilder: (_, i) => _buildItem(_leaves[i]),
            ),
    );
  }

  Widget _buildItem(LeaveRecord r) {
    final expanded = _expandedId == r.id;
    final highlighted = _highlightId == r.id;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: highlighted
            ? AppTheme.primaryContainer.withValues(alpha: 0.18)
            : Colors.transparent,
      ),
      padding: const EdgeInsets.all(2),
      child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => setState(
            () => _expandedId = expanded ? null : r.id),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.leaveType,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15)),
                        const SizedBox(height: 4),
                        Text(
                          '${r.dateFrom ?? ''} → ${r.dateTo ?? ''}  ·  ${r.daysLabel}',
                          style: TextStyle(
                              fontSize: 13, color: AppTheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _stateColor(r.state).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      r.stateLabel,
                      style: TextStyle(
                        color: _stateColor(r.state),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppTheme.outline,
                    size: 20,
                  ),
                ],
              ),
              // Expanded details
              if (expanded) ...[
                const Divider(height: 24),
                if (r.reason.isNotEmpty)
                  _detailRow('Reason', r.reason),
                if (r.requiresAllocation &&
                    r.allocationTotal != null) ...[
                  _detailRow(
                    'Allocation',
                    '${_fmtDays(r.allocationTotal!)} ${r.allocationUnit} total',
                  ),
                  _detailRow(
                    'Used',
                    '${_fmtDays(r.allocationTotal! - (r.allocationRemaining ?? 0))} ${r.allocationUnit}',
                  ),
                  _detailRow(
                    'Remaining',
                    '${_fmtDays(r.allocationRemaining ?? 0)} ${r.allocationUnit}',
                  ),
                  const SizedBox(height: 8),
                  _balanceBar(r),
                ],
                if (!r.requiresAllocation)
                  _detailRow('Allocation', 'No allocation required'),
                if (r.attachments.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final a in r.attachments)
                    InkWell(
                      onTap: () => _viewHistoryAttachment(a),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(Icons.description_outlined,
                                size: 16, color: AppTheme.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${a.name} · ${a.sizeLabel}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.primary,
                                  decoration: TextDecoration.underline,
                                  decorationColor: AppTheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                if (r.state == 'confirm') ...[
                  const SizedBox(height: 12),
                  // Both buttons share half-width via Expanded. Default
                  // OutlinedButton.icon padding + a 6-char label like
                  // "Cancel" overflows on iPhone 15 with iOS Dynamic
                  // Type bumped above default — the label wraps mid-
                  // word. Tighten horizontal padding and lock the
                  // label to one line with ellipsis as graceful
                  // degradation if it still doesn't fit.
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text(
                            'Edit',
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8),
                          ),
                          onPressed: () => _openEditSheet(r),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text(
                            'Cancel',
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.error,
                            side: BorderSide(color: AppTheme.error),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8),
                          ),
                          onPressed: () => _openCancelDialog(r),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _balanceBar(LeaveRecord r) {
    final total = r.allocationTotal ?? 0;
    final remaining = r.allocationRemaining ?? 0;
    final taken = total - remaining;
    final fraction = total > 0 ? (taken / total).clamp(0.0, 1.0) : 0.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: fraction,
        minHeight: 6,
        backgroundColor: AppTheme.surfaceContainer,
        valueColor: AlwaysStoppedAnimation<Color>(
          fraction > 0.8 ? AppTheme.error : AppTheme.primary,
        ),
      ),
    );
  }
}

class _CancelLeaveDialog extends StatefulWidget {
  final LeaveRecord record;
  const _CancelLeaveDialog({required this.record});

  @override
  State<_CancelLeaveDialog> createState() => _CancelLeaveDialogState();
}

class _CancelLeaveDialogState extends State<_CancelLeaveDialog> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    return AlertDialog(
      title: const Text('Cancel this leave?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${r.leaveType}\n${r.dateFrom ?? ''} → ${r.dateTo ?? ''}',
            style: TextStyle(color: AppTheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reasonController,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context)
              .pop((ok: false, reason: '')),
          child: const Text('Keep it'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
          onPressed: () => Navigator.of(context).pop(
              (ok: true, reason: _reasonController.text.trim())),
          child: const Text('Cancel leave'),
        ),
      ],
    );
  }
}

class _EditLeaveSheet extends StatefulWidget {
  final LeaveRecord record;
  final OmniMobileApi api;
  const _EditLeaveSheet({required this.record, required this.api});

  @override
  State<_EditLeaveSheet> createState() => _EditLeaveSheetState();
}

class _EditLeaveSheetState extends State<_EditLeaveSheet> {
  late DateTime _dateFrom;
  late DateTime _dateTo;
  late final TextEditingController _reasonController;
  bool _submitting = false;
  String? _error;

  String _fromPeriod = 'am';
  String _toPeriod = 'pm';
  TimeOfDay _hourFrom = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _hourTo = const TimeOfDay(hour: 17, minute: 0);
  PickedDocument? _document;
  late List<LeaveAttachment> _existingAttachments;
  final Set<int> _busyAttachments = {};

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _dateFrom = _parseDate(r.dateFrom) ??
        DateTime.now().add(const Duration(days: 1));
    _dateTo = _parseDate(r.dateTo) ?? _dateFrom;
    _fromPeriod = r.dateFromPeriod ?? 'am';
    _toPeriod = r.dateToPeriod ?? 'pm';
    if (r.hourFrom != null) {
      _hourFrom = _floatToTod(r.hourFrom!);
    }
    if (r.hourTo != null) {
      _hourTo = _floatToTod(r.hourTo!);
    }
    _reasonController = TextEditingController(text: r.reason);
    _existingAttachments = List<LeaveAttachment>.from(r.attachments);
  }

  Future<void> _viewAttachment(LeaveAttachment a) async {
    setState(() => _busyAttachments.add(a.id));
    try {
      final res = await widget.api.getAttachment(a.id);
      final dataB64 = (res['data_b64'] ?? '').toString();
      if (dataB64.isEmpty) throw Exception('empty file');
      final err = await openBase64File(name: a.name, dataB64: dataB64);
      if (err != null && mounted) showFileViewError(context, err);
    } catch (e) {
      if (mounted) showFileViewError(context, e.toString());
    } finally {
      if (mounted) setState(() => _busyAttachments.remove(a.id));
    }
  }

  Future<void> _deleteAttachment(LeaveAttachment a) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this file?'),
        content: Text(a.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyAttachments.add(a.id));
    try {
      await widget.api.deleteAttachment(a.id);
      if (mounted) {
        setState(() => _existingAttachments.removeWhere((x) => x.id == a.id));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppTheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _busyAttachments.remove(a.id));
    }
  }

  TimeOfDay _floatToTod(double f) =>
      TimeOfDay(hour: f.floor(), minute: ((f - f.floor()) * 60).round());

  double _todToFloat(TimeOfDay t) => t.hour + t.minute / 60.0;

  DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  bool get _isHalfDay => widget.record.requestUnit == 'half_day';
  bool get _isHourly => widget.record.requestUnit == 'hour';

  bool get _isSameDate =>
      _dateFrom.year == _dateTo.year &&
      _dateFrom.month == _dateTo.month &&
      _dateFrom.day == _dateTo.day;

  double get _hourCount => _todToFloat(_hourTo) - _todToFloat(_hourFrom);

  String get _hourLabel {
    final h = _hourCount;
    return h == h.roundToDouble()
        ? '${h.toInt()}h'
        : '${h.toStringAsFixed(1)}h';
  }

  double get _dayCount {
    final holidays = context.read<HolidayService>();
    if (_isHalfDay) {
      if (_isSameDate) {
        if (!holidays.isWorkingDay(_dateFrom)) return 0;
        return _fromPeriod == _toPeriod ? 0.5 : 1.0;
      }
      var d = holidays.workingDaysBetween(_dateFrom, _dateTo).toDouble();
      if (_fromPeriod == 'pm' && holidays.isWorkingDay(_dateFrom)) d -= 0.5;
      if (_toPeriod == 'am' && holidays.isWorkingDay(_dateTo)) d -= 0.5;
      return d < 0 ? 0 : d;
    }
    return holidays.workingDaysBetween(_dateFrom, _dateTo).toDouble();
  }

  String get _dayCountLabel {
    final n = _dayCount;
    return n == n.roundToDouble()
        ? '${n.toInt()}d'
        : '${n.toStringAsFixed(1)}d';
  }

  bool get _periodValid {
    if (_isHourly) return _hourCount > 0;
    if (!_isHalfDay) return true;
    if (_isSameDate && _fromPeriod == 'pm' && _toPeriod == 'am') return false;
    return _dayCount > 0;
  }

  Future<void> _pickRange() async {
    final today = DateTime.now();
    final firstDate = backdateFirstDate(null, today);
    final lastDate = DateTime(today.year, today.month, today.day)
        .add(const Duration(days: 365));
    final holidays = context.read<HolidayService>();
    if (_isHourly) {
      final picked = await showAutoDatePicker(
        context: context,
        initialDate: _dateFrom.isBefore(firstDate) ? firstDate : _dateFrom,
        firstDate: firstDate,
        lastDate: lastDate,
        helpText: 'Select date',
        holidayName: holidays.holidayName,
        isNonWorkingDay: (d) => !holidays.isWorkingDay(d),
      );
      if (picked != null) {
        setState(() {
          _dateFrom = picked;
          _dateTo = picked;
          _error = null;
        });
      }
      return;
    }
    final picked = await showDialog<DateTimeRange>(
      context: context,
      builder: (_) => RangePickerDialog(
        initialStart:
            _dateFrom.isBefore(firstDate) ? firstDate : _dateFrom,
        initialEnd: _dateTo.isBefore(firstDate) ? firstDate : _dateTo,
        firstDate: firstDate,
        lastDate: lastDate,
        holidayName: holidays.holidayName,
        isNonWorkingDay: (d) => !holidays.isWorkingDay(d),
        dayCount: holidays.workingDaysBetween,
      ),
    );
    if (picked != null) {
      setState(() {
        _dateFrom = picked.start;
        _dateTo = picked.end;
        _error = null;
      });
    }
  }

  Future<void> _pickTime(bool isFrom) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isFrom ? _hourFrom : _hourTo,
      initialEntryMode: TimePickerEntryMode.dial,
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _hourFrom = picked;
        } else {
          _hourTo = picked;
        }
        _error = null;
      });
    }
  }

  bool get _hasAnyDocument =>
      _existingAttachments.isNotEmpty || _document != null;

  bool get _docRequirementMet =>
      !widget.record.requiresDocument || _hasAnyDocument;

  Future<void> _submit() async {
    if (!_periodValid) {
      setState(() => _error = _isHourly
          ? 'End time must be after start time.'
          : 'Afternoon → Morning on the same date is not a valid range.');
      return;
    }
    if (!_docRequirementMet) {
      setState(() => _error =
          'A supporting document is required. Please upload one before saving.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.api.modifyLeave(
        leaveId: widget.record.id,
        dateFrom: DateFormat('yyyy-MM-dd').format(_dateFrom),
        dateTo: DateFormat('yyyy-MM-dd').format(
            _isHourly ? _dateFrom : _dateTo),
        reason: _reasonController.text.trim(),
        dateFromPeriod: _isHalfDay ? _fromPeriod : null,
        dateToPeriod: _isHalfDay ? _toPeriod : null,
        hourFrom: _isHourly ? _todToFloat(_hourFrom) : null,
        hourTo: _isHourly ? _todToFloat(_hourTo) : null,
        attachment: _document?.toApiJson(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Leave updated'),
          backgroundColor: AppTheme.primary,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = _humanizeError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _humanizeError(Object e) {
    final raw = e.toString();
    if (raw.contains('overlap') || raw.contains('already')) {
      return 'You already have a leave request on these dates.';
    }
    if (raw.contains('allocation') || raw.contains('No more')) {
      return 'Not enough allocation balance for these dates.';
    }
    if (raw.contains('invalid_dates')) {
      return 'Invalid dates. Make sure they are in the future and ordered.';
    }
    if (raw.contains('document_required')) {
      return 'A supporting document is required for this leave type.';
    }
    // Anything else (incl. network/timeout/server) goes through the
    // shared safe humanizer — never echo the raw exception text.
    return friendlyError(e);
  }

  Widget _periodRow({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'am',
                label: Text('Morning'),
                icon: Icon(Icons.wb_sunny_outlined, size: 16),
              ),
              ButtonSegment(
                value: 'pm',
                label: Text('Afternoon'),
                icon: Icon(Icons.wb_twilight, size: 16),
              ),
            ],
            selected: {value},
            onSelectionChanged: (s) => onChanged(s.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStateProperty.all(
                  const TextStyle(fontSize: 12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _timeBox({
    required String label,
    required TimeOfDay time,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.outline),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule, size: 18, color: AppTheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text(
                    time.format(context),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd MMM yyyy');
    final mq = MediaQuery.of(context);
    // SingleChildScrollView so the form survives keyboard-up without
    // overflow. viewPadding.bottom covers the persistent bottom nav's
    // system-nav inset (we render past the nav via useRootNavigator).
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: mq.viewInsets.bottom + mq.viewPadding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Edit ${widget.record.leaveType}',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          InkWell(
            onTap: _pickRange,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.outline),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today,
                      size: 18, color: AppTheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Leave dates',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.onSurfaceVariant)),
                        const SizedBox(height: 2),
                        Text(
                          _isHourly
                              ? '${fmt.format(_dateFrom)}  ·  $_hourLabel'
                              : '${fmt.format(_dateFrom)} → ${fmt.format(_dateTo)}  ·  $_dayCountLabel',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppTheme.outline),
                ],
              ),
            ),
          ),
          if (_isHourly) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _timeBox(
                      label: 'From', time: _hourFrom,
                      onTap: () => _pickTime(true)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _timeBox(
                      label: 'To', time: _hourTo,
                      onTap: () => _pickTime(false)),
                ),
              ],
            ),
          ],
          if (_isHalfDay) ...[
            const SizedBox(height: 16),
            _periodRow(
              label: 'Start period',
              value: _fromPeriod,
              onChanged: (v) => setState(() {
                _fromPeriod = v;
                _error = null;
              }),
            ),
            const SizedBox(height: 12),
            _periodRow(
              label: 'End period',
              value: _toPeriod,
              onChanged: (v) => setState(() {
                _toPeriod = v;
                _error = null;
              }),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _reasonController,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              prefixIcon: Icon(Icons.notes),
            ),
            maxLines: 2,
          ),
          if (_existingAttachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final a in _existingAttachments)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: AppTheme.outline.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.description_outlined,
                          size: 18, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${a.name} · ${a.sizeLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      if (_busyAttachments.contains(a.id))
                        const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else ...[
                        IconButton(
                          tooltip: 'View',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 36, minHeight: 36),
                          icon: Icon(Icons.visibility_outlined,
                              size: 20, color: AppTheme.primary),
                          onPressed: () => _viewAttachment(a),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 36, minHeight: 36),
                          icon: Icon(Icons.close_rounded,
                              size: 20, color: AppTheme.error),
                          onPressed: () => _deleteAttachment(a),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          DocumentPickerField(
            picked: _document,
            required: widget.record.requiresDocument && !_hasAnyDocument,
            onChanged: (d) => setState(() {
              _document = d;
              _error = null;
            }),
          ),
          if (widget.record.requiresDocument && !_hasAnyDocument) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: AppTheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'This leave type needs a supporting document. Upload one to save your changes.',
                    style: TextStyle(fontSize: 12, color: AppTheme.error),
                  ),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: AppTheme.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: AppTheme.error, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_submitting || !_docRequirementMet)
                  ? null
                  : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save changes'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Earliest selectable start date for [type], from the policy the server
/// computed. Robust to old servers (backdating defaults off).
DateTime backdateFirstDate(LeaveType? type, DateTime now) {
  final midnightToday = DateTime(now.year, now.month, now.day);
  if (type == null || !type.allowBackdated) return midnightToday;
  final floor = type.earliestBackdateDate;
  if (floor != null) return DateTime(floor.year, floor.month, floor.day);
  // Unlimited: keep the picker bounded, mirroring the forward window.
  return midnightToday.subtract(const Duration(days: 365));
}
