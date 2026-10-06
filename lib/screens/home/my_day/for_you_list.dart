import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/datetime_utils.dart';
import '../../../core/theme.dart';
import '../../../models/my_day.dart';
import 'my_day_colors.dart';

String _shortDate(String value) {
  final date = DateTime.tryParse(value);
  return date == null ? value : DateFormat('d MMM', 'en_US').format(date);
}

String _dateRange(String from, String to) {
  final a = _shortDate(from);
  final b = _shortDate(to);
  return a == b || b.isEmpty ? a : '$a – $b';
}

String _expenseStateLabel(String state) {
  switch (state) {
    case 'submitted':
      return 'Waiting for approval';
    case 'approved':
    case 'posted':
    case 'in_payment':
    case 'paid':
      return 'Approved';
    case 'refused':
      return 'Refused';
    default:
      return state;
  }
}

/// First line of a For-you row.
String forYouTitle(ForYouItem item) {
  switch (item.kind) {
    case 'leave_approvals':
      return '${item.count} leave request${item.count == 1 ? '' : 's'} '
          'to approve';
    case 'my_leave':
      return '${item.type.isEmpty ? 'Leave' : item.type} · '
          '${_dateRange(item.dateFrom, item.dateTo)}';
    case 'my_expense':
      return item.name.isEmpty ? 'Expense' : item.name;
    case 'payslip':
      return item.period.isEmpty
          ? 'Payslip is ready'
          : '${item.period} payslip is ready';
    default:
      return '';
  }
}

/// Second line of a For-you row. [now] is injectable for tests.
String forYouSubtitle(ForYouItem item, {DateTime? now}) {
  switch (item.kind) {
    case 'leave_approvals':
      final oldest = DateTimeUtils.parseOdooUtc(item.oldestAt);
      if (oldest == null) return 'Waiting for your decision';
      final days = (now ?? DateTime.now()).toUtc().difference(oldest).inDays;
      if (days <= 0) return 'Oldest is from today';
      return 'Oldest has waited $days day${days == 1 ? '' : 's'}';
    case 'my_leave':
      switch (item.state) {
        case 'confirm':
          return item.approver.isEmpty
              ? 'Waiting for approval'
              : 'Waiting for ${item.approver}';
        case 'validate1':
          return 'Waiting for second approval';
        case 'validate':
          return item.approver.isEmpty
              ? 'Approved'
              : 'Approved by ${item.approver}';
        case 'refuse':
          return item.reason.isEmpty ? 'Refused' : 'Refused: ${item.reason}';
        default:
          return item.state;
      }
    case 'my_expense':
      final amount = NumberFormat('#,##0.##', 'en_US').format(item.amount);
      final money = item.currency.isEmpty ? amount : '${item.currency} $amount';
      return '${_expenseStateLabel(item.state)} · $money';
    case 'payslip':
      return 'Tap to view';
    default:
      return '';
  }
}

IconData _icon(String kind) {
  switch (kind) {
    case 'leave_approvals':
      return Icons.how_to_reg_outlined;
    case 'my_leave':
      return Icons.event_note_outlined;
    case 'my_expense':
      return Icons.receipt_long_outlined;
    default:
      return Icons.payments_outlined;
  }
}

MyDayTone _tone(String kind) {
  switch (kind) {
    case 'leave_approvals':
    case 'my_expense':
      return MyDayColors.brk;
    case 'payslip':
      return MyDayColors.overtime;
    default:
      return MyDayColors.work;
  }
}

Widget _tile(Key key, IconData icon, MyDayTone tone, {bool inverted = false}) =>
    Container(
      key: key,
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: inverted ? Colors.white : tone.tint,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, size: 20, color: tone.onTint),
    );

/// The "For you" list of My day: one row per item, unknown kinds skipped.
/// With [missing] a red "No check-in" row comes first (spec 2026-10-06
/// §4.5); it is the app's own, not a server item.
class ForYouList extends StatelessWidget {
  const ForYouList({
    super.key,
    required this.items,
    required this.onTap,
    this.missing = false,
    this.onMissingTap,
  });

  final List<ForYouItem> items;
  final void Function(ForYouItem item) onTap;
  final bool missing;
  final VoidCallback? onMissingTap;

  static const emptyText = 'Nothing needs your attention.';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final known = items.where((item) => item.isKnown).toList();
    if (known.isEmpty && !missing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          emptyText,
          style: text.bodyMedium?.copyWith(color: AppTheme.outline),
        ),
      );
    }
    return Column(
      children: [
        if (missing)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: MyDayColors.missing.tint,
            child: ListTile(
              key: const ValueKey('for-you-missing'),
              leading: _tile(
                const ValueKey('for-you-tile-missing'),
                Icons.error_outline,
                MyDayColors.missing,
                inverted: true,
              ),
              title: Text(
                'No check-in recorded today',
                style: TextStyle(
                  color: MyDayColors.missing.onTint,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Tell HR if you are at work',
                style: TextStyle(color: MyDayColors.missing.onTint),
              ),
              trailing: Icon(
                Icons.chevron_right,
                color: MyDayColors.missing.onTint,
              ),
              onTap: onMissingTap,
            ),
          ),
        for (final item in known)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              key: ValueKey('for-you-${item.kind}-${item.id}'),
              leading: _tile(
                ValueKey('for-you-tile-${item.kind}-${item.id}'),
                _icon(item.kind),
                _tone(item.kind),
              ),
              title: Text(forYouTitle(item)),
              subtitle: Text(forYouSubtitle(item)),
              trailing: const Icon(
                Icons.chevron_right,
                color: AppTheme.outline,
              ),
              onTap: () => onTap(item),
            ),
          ),
      ],
    );
  }
}
