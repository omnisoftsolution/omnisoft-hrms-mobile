import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../models/leave_type.dart';
import '../../services/holiday_service.dart';
import '../../services/omni_mobile_api.dart';
import '../../services/session_service.dart';
import '../../widgets/auto_pickers.dart';
import '../../widgets/document_picker_field.dart';
import '../../widgets/feature_locked_pane.dart';
import '../../widgets/omni_app_bar.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/range_picker_dialog.dart';
import '../home/home_shell.dart';

/// Renders the remaining-balance indicator for a leave type. Returns
/// null when the type carries no balance info (server didn't send the
/// field — e.g. older connector). `longForm: true` produces the verbose
/// sheet header subtitle; `longForm: false` produces the compact
/// list-tile pill. Suffix follows the type's `requestUnit` (h for
/// hour-types, d otherwise). Color is muted for normal balances, red
/// when depleted.
({String label, Color color})? _balanceVisual(
  LeaveType t, {
  required bool longForm,
}) {
  final unitNoun = _unitNounLong(t.requestUnit);
  if (!t.requiresAllocation) {
    return (
      label: longForm ? 'Unlimited $unitNoun available' : 'Unlimited',
      color: AppTheme.onSurfaceVariant,
    );
  }
  final n = t.virtualRemainingLeaves;
  if (n == null) return null;
  final suffix = _unitSuffix(t.requestUnit);
  if (n <= 0) {
    return (
      label: longForm ? 'No $unitNoun remaining' : '0$suffix left',
      color: AppTheme.error,
    );
  }
  final s = n == n.roundToDouble()
      ? n.toInt().toString()
      : n.toStringAsFixed(1);
  return (
    label: longForm ? '$s $unitNoun remaining' : '$s$suffix left',
    color: AppTheme.onSurfaceVariant,
  );
}

String _unitSuffix(String requestUnit) {
  switch (requestUnit) {
    case 'hour':
      return 'h';
    case 'half_day':
    case 'day':
    default:
      return 'd';
  }
}

String _unitNounLong(String requestUnit) {
  switch (requestUnit) {
    case 'hour':
      return 'hours';
    case 'half_day':
    case 'day':
    default:
      return 'days';
  }
}

class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key});

  @override
  State<LeaveScreen> createState() => LeaveScreenState();
}

class LeaveScreenState extends State<LeaveScreen> {
  List<LeaveType> _types = [];
  bool _loading = true;
  String? _error;

  OmniMobileApi _api(SessionService s) => OmniMobileApi(
        baseUrl: s.clientUrl,
        db: s.clientDb,
        token: s.token,
      );

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
      _types = await _api(session).getLeaveTypes();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openApplyForm(LeaveType type) async {
    // Sheet returns the new leave's id on a successful submit (null
    // when the user dismissed without submitting). Doing the post-
    // submit work (snackbar + navigate to History) HERE — rather than
    // inside the sheet — is what keeps both lookups working. The
    // sheet uses useRootNavigator: true so it lives on the root
    // Navigator, OUTSIDE HomeShell's subtree. From inside the sheet,
    // ScaffoldMessenger.of(context) returns MaterialApp's default
    // messenger (no descendant Scaffolds → showSnackBar asserts) and
    // findAncestorStateOfType<HomeShellState>() returns null. This
    // screen's context IS inside HomeShell, so both resolve cleanly.
    final leaveId = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ApplyLeaveSheet(leaveType: type),
    );
    // DONE pops with null → stay on Leave tab. VIEW IN HISTORY pops
    // with a positive leave id → navigate. No snackbar — the in-sheet
    // receipt is the user's confirmation; doubling it with a banner
    // would be noise.
    if (!mounted || leaveId == null || leaveId <= 0) return;
    final shell = context.findAncestorStateOfType<HomeShellState>();
    await shell?.navigateToLeave(leaveId);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    return Scaffold(
      appBar: const OmniAppBar(title: 'Leave'),
      body: !session.featureTimeOff
          ? const FeatureLockedPane(
              featureName: 'Time Off',
              subtitle: 'Your subscription does not include leave '
                  'application. Contact your administrator to upgrade.',
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : RefreshIndicator(
                      onRefresh: refresh,
                      child: _buildList(),
                    ),
    );
  }

  Widget _buildList() {
    // Flat list ordered by Odoo's hr.leave.type.sequence — the
    // connector returns types in `sequence asc, id asc` order, so
    // we render them as received. HR controls ordering by drag-
    // reordering in the Odoo admin list view; no mobile release
    // needed when the order changes.
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: _types.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final type = _types[i];
        return Opacity(
          // Exhausted-allocation tiles fade in place. The red
          // "0d left" badge in _tileSubtitle is the explanation;
          // onTap is gated below so the user can't submit a leave
          // the server would reject.
          opacity: _isExhausted(type) ? 0.55 : 1.0,
          child: Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    AppTheme.primary.withValues(alpha: 0.1),
                child: Icon(
                  _categoryIcon(type.mobileCategory),
                  color: AppTheme.primary,
                ),
              ),
              title: Text(type.name),
              subtitle: _tileSubtitle(type),
              trailing: const Icon(Icons.chevron_right),
              onTap: _isExhausted(type)
                  ? null
                  : () => _openApplyForm(type),
            ),
          ),
        );
      },
    );
  }

  /// True when this leave type has an allocation that's been used
  /// up. Unlimited (`requiresAllocation == false`) types are never
  /// exhausted. Null balance (rare server quirk where the computed
  /// field didn't populate) is also treated as not-exhausted — we
  /// let the user try and rely on the server's check rather than
  /// silently disabling.
  bool _isExhausted(LeaveType t) =>
      t.requiresAllocation &&
      t.virtualRemainingLeaves != null &&
      t.virtualRemainingLeaves! <= 0;

  /// Combines the balance pill and the optional "Document required"
  /// note into a single subtitle widget. Returns null when neither
  /// applies — letting the ListTile collapse to single-line height.
  Widget? _tileSubtitle(LeaveType type) {
    final balance = _balanceVisual(type, longForm: false);
    final hasDoc = type.mobileRequiresDocument;
    if (balance == null && !hasDoc) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (balance != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              balance.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: balance.color,
              ),
            ),
          ),
        if (hasDoc)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              'Document required',
              style: TextStyle(fontSize: 12, color: AppTheme.error),
            ),
          ),
      ],
    );
  }

  IconData _categoryIcon(String cat) {
    switch (cat) {
      case 'annual':
        return Icons.beach_access;
      case 'medical':
        return Icons.local_hospital;
      case 'family':
        return Icons.family_restroom;
      case 'unpaid':
        return Icons.money_off;
      case 'compassionate':
        return Icons.volunteer_activism;
      default:
        return Icons.event;
    }
  }
}

class _ApplyLeaveSheet extends StatefulWidget {
  final LeaveType leaveType;
  const _ApplyLeaveSheet({required this.leaveType});

  @override
  State<_ApplyLeaveSheet> createState() => _ApplyLeaveSheetState();
}

class _ApplyLeaveSheetState extends State<_ApplyLeaveSheet> {
  DateTime _dateFrom = DateTime.now().add(const Duration(days: 1));
  DateTime _dateTo = DateTime.now().add(const Duration(days: 1));
  String _fromPeriod = 'am';
  String _toPeriod = 'pm';
  TimeOfDay _hourFrom = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _hourTo = const TimeOfDay(hour: 17, minute: 0);
  final _reasonController = TextEditingController();
  PickedDocument? _document;
  bool _submitting = false;
  String? _error;
  // When set, the sheet is in success-receipt mode (form hidden,
  // receipt shown). Holds the leave id returned by the connector so
  // VIEW IN HISTORY can pass it back to the parent for highlight.
  int? _submittedLeaveId;

  bool get _isHalfDay => widget.leaveType.requestUnit == 'half_day';
  bool get _isHourly => widget.leaveType.requestUnit == 'hour';

  double _todToFloat(TimeOfDay t) => t.hour + t.minute / 60.0;
  double get _hourCount => _todToFloat(_hourTo) - _todToFloat(_hourFrom);

  String get _hourLabel {
    final h = _hourCount;
    return h == h.roundToDouble()
        ? '${h.toInt()}h'
        : '${h.toStringAsFixed(1)}h';
  }

  bool get _isSameDate =>
      _dateFrom.year == _dateTo.year &&
      _dateFrom.month == _dateTo.month &&
      _dateFrom.day == _dateTo.day;

  /// Working-day count, mirroring Odoo's hr.leave duration math.
  /// Skips weekends and public holidays based on the employee's
  /// calendar (HolidayService).
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

  /// Half-day mode rejects pm→am on the same date (would be 0 days).
  bool get _periodValid {
    if (_isHourly) return _hourCount > 0;
    if (!_isHalfDay) return true;
    if (_isSameDate && _fromPeriod == 'pm' && _toPeriod == 'am') return false;
    return _dayCount > 0;
  }

  Future<void> _pickRange() async {
    final today = DateTime.now();
    final firstDate = DateTime(today.year, today.month, today.day);
    final holidays = context.read<HolidayService>();
    if (_isHourly) {
      final picked = await showAutoDatePicker(
        context: context,
        initialDate: _dateFrom,
        firstDate: firstDate,
        lastDate: firstDate.add(const Duration(days: 365)),
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
        initialStart: _dateFrom,
        initialEnd: _dateTo,
        firstDate: firstDate,
        lastDate: firstDate.add(const Duration(days: 365)),
        holidayName: holidays.holidayName,
        isNonWorkingDay: (d) => !holidays.isWorkingDay(d),
        // Show working-day count in the picker header so it matches
        // the count shown on the leave form after the picker closes
        // (Fri→Mon was previously "4d" in picker but "2d" on form).
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

  Future<void> _submit() async {
    if (!_periodValid) {
      setState(() => _error = _isHourly
          ? 'End time must be after start time.'
          : 'Afternoon → Morning on the same date is not a valid range.');
      return;
    }
    if (widget.leaveType.mobileRequiresDocument && _document == null) {
      setState(() =>
          _error = 'A supporting document is required for this leave type.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final session = context.read<SessionService>();
      final api = OmniMobileApi(
        baseUrl: session.clientUrl,
        db: session.clientDb,
        token: session.token,
      );
      final response = await api.applyLeave(
        holidayStatusId: widget.leaveType.id,
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
      // Don't pop yet — transition to the in-sheet receipt. The user
      // sees a confirmation of what they just submitted (Type / Dates
      // / Reason / Approver / Reference) and then chooses where to go
      // via the DONE or VIEW IN HISTORY buttons in `_buildSuccess`.
      final leaveId = (response['leave_id'] as num?)?.toInt() ?? 0;
      setState(() => _submittedLeaveId = leaveId);
    } catch (e, st) {
      debugPrint('leave/apply failed: $e\n$st');
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
      return 'Not enough allocation balance for this request.';
    }
    if (raw.contains('document_required')) {
      return 'A supporting document is required for this leave type.';
    }
    return raw.replaceFirst(RegExp(r'^Exception: '), '');
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

  @override
  Widget build(BuildContext context) {
    // Two visual phases: form (pre-submit) and receipt (post-success).
    // The form stays available on validation/network failures so the
    // user can fix-and-retry; the receipt only takes over after the
    // connector confirms creation and we know the leave id.
    if (_submittedLeaveId != null) return _buildSuccess(context);
    return _buildForm(context);
  }

  Widget _buildForm(BuildContext context) {
    final fmt = DateFormat('dd MMM yyyy');
    // Bottom sum:
    //   viewInsets.bottom  → keyboard inset (non-zero while keyboard open)
    //   viewPadding.bottom → system nav / home-indicator inset
    //   + 24               → visual gap above the SUBMIT button
    // They never double-pad: when keyboard rises, viewPadding.bottom
    // collapses to 0 (the keyboard consumes the bottom inset).
    final mq = MediaQuery.of(context);
    final balance = _balanceVisual(widget.leaveType, longForm: true);
    // SingleChildScrollView (not Padding) so the form scrolls when
    // the keyboard rises and pushes available height below the
    // column's intrinsic size — otherwise the column would overflow.
    //
    // Wrapped in a GestureDetector so tapping anywhere outside an
    // input dismisses the keyboard. Combined with the explicit close
    // (X) button in the header row below, this addresses the older-
    // iPhone softlock where users couldn't dismiss the modal once an
    // inline validation error appeared with the keyboard up.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(widget.leaveType.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              // Always-visible dismiss affordance. The native drag-to-
              // dismiss strip is too small to grab on iPhone 8 / X
              // when the keyboard is up; an explicit button removes
              // the softlock risk on every screen size.
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: 40, minHeight: 40),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
          if (balance != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                balance.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: balance.color,
                ),
              ),
            ),
          if (widget.leaveType.mobileRequiresDocument)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Supporting document required.',
                style: TextStyle(fontSize: 12, color: AppTheme.error),
              ),
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
                        Text(_isHourly ? 'Leave date' : 'Leave dates',
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
          if (widget.leaveType.mobileRequiresDocument ||
              _document != null) ...[
            const SizedBox(height: 12),
            DocumentPickerField(
              picked: _document,
              required: widget.leaveType.mobileRequiresDocument,
              onChanged: (d) => setState(() {
                _document = d;
                _error = null;
              }),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
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
          PrimaryButton(
            label: 'SUBMIT LEAVE',
            loading: _submitting,
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    final mq = MediaQuery.of(context);
    final session = context.read<SessionService>();
    final fmt = DateFormat('dd MMM yyyy');
    // Build a one-line dates blurb that matches the form's math —
    // reuses _dayCountLabel / _hourLabel so the receipt agrees with
    // what the user just saw.
    String datesBlurb;
    if (_isHourly) {
      datesBlurb = '${fmt.format(_dateFrom)}  ·  $_hourLabel';
    } else if (_isHalfDay) {
      final period = '${_fromPeriod.toUpperCase()} → ${_toPeriod.toUpperCase()}';
      datesBlurb = _isSameDate
          ? '${fmt.format(_dateFrom)}  ·  $_dayCountLabel  ·  $period'
          : '${fmt.format(_dateFrom)} → ${fmt.format(_dateTo)}  '
              '·  $_dayCountLabel  ·  $period';
    } else {
      datesBlurb = _isSameDate
          ? '${fmt.format(_dateFrom)}  ·  $_dayCountLabel'
          : '${fmt.format(_dateFrom)} → ${fmt.format(_dateTo)}  '
              '·  $_dayCountLabel';
    }
    final reason = _reasonController.text.trim();
    final approver = session.employeeTimeOffApprover;
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: mq.viewInsets.bottom + mq.viewPadding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryContainer.withValues(alpha: 0.15),
              ),
              child: Icon(
                Icons.check_rounded,
                color: AppTheme.primary,
                size: 30,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              'Leave request submitted',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Waiting for approval',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Divider(
              height: 1,
              color: AppTheme.outlineVariant.withValues(alpha: 0.6)),
          const SizedBox(height: 16),
          _summaryRow('Type', widget.leaveType.name),
          _summaryRow('Dates', datesBlurb),
          if (reason.isNotEmpty) _summaryRow('Reason', reason),
          if (approver.isNotEmpty) _summaryRow('Approver', approver),
          if (_submittedLeaveId != null && _submittedLeaveId! > 0)
            _summaryRow('Reference', '#${_submittedLeaveId!}'),
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'DONE',
            // Null pop result tells the parent: stay on the Leave tab.
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.history_rounded, size: 18),
            label: const Text('VIEW IN HISTORY'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: BorderSide(
                color: AppTheme.outline.withValues(alpha: 0.5),
              ),
              foregroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            onPressed: () =>
                Navigator.of(context).pop(_submittedLeaveId),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: AppTheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
