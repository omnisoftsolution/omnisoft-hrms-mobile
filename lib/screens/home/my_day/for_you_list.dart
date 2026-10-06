import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/datetime_utils.dart';
import '../../../core/theme.dart';
import '../../../models/my_day.dart';

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
      final money =
          item.currency.isEmpty ? amount : '${item.currency} $amount';
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

/// The "For you" list of My day: one row per item, unknown kinds skipped.
class ForYouList extends StatelessWidget {
  const ForYouList({super.key, required this.items, required this.onTap});

  final List<ForYouItem> items;
  final void Function(ForYouItem item) onTap;

  static const emptyText = 'Nothing needs your attention.';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final known = items.where((item) => item.isKnown).toList();
    if (known.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(emptyText,
            style: text.bodyMedium?.copyWith(color: AppTheme.outline)),
      );
    }
    return Column(
      children: [
        for (final item in known)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              key: ValueKey('for-you-${item.kind}-${item.id}'),
              leading: Icon(
                _icon(item.kind),
                // Something the user must act on stands out.
                color: item.kind == 'leave_approvals'
                    ? AppTheme.secondary
                    : AppTheme.primary,
              ),
              title: Text(forYouTitle(item)),
              subtitle: Text(forYouSubtitle(item)),
              trailing:
                  const Icon(Icons.chevron_right, color: AppTheme.outline),
              onTap: () => onTap(item),
            ),
          ),
      ],
    );
  }
}
