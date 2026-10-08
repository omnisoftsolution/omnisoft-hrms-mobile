import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/datetime_utils.dart';
import '../../../core/theme.dart';
import '../../../models/my_day.dart';
import 'my_day_colors.dart';
import 'my_day_display.dart';

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
          '${dateRange(item.dateFrom, item.dateTo)}';
    case 'my_expense':
      return item.name.isEmpty ? 'Expense' : item.name;
    case 'payslip':
      return item.period.isEmpty
          ? 'Payslip is ready'
          : '${item.period} payslip is ready';
    case 'yesterday_incomplete':
      return item.title.isEmpty ? 'Yesterday looks incomplete' : item.title;
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
    case 'yesterday_incomplete':
      return item.body;
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

/// "Yesterday looks incomplete" (connector 2.54.0, spec 2026-10-07 §4.3):
/// amber like the auto-closed banner, with its own "Tell HR" button.
class YesterdayCard extends StatelessWidget {
  const YesterdayCard({super.key, required this.item, this.onTellHr});

  final ForYouItem item;
  final VoidCallback? onTellHr;

  static const _amber = Color(0xFFB45309); // amber-800
  static const _bg = Color(0xFFFEF3C7); // amber-100

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('for-you-yesterday-${item.date}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.history, size: 20, color: _amber),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  forYouTitle(item),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _amber,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  forYouSubtitle(item),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const ValueKey('for-you-yesterday-tell'),
            style: FilledButton.styleFrom(
              backgroundColor: _amber,
              foregroundColor: Colors.white,
            ),
            onPressed: onTellHr,
            child: const Text('Tell HR'),
          ),
        ],
      ),
    );
  }
}

/// The "For you" list of My day: one row per item, unknown kinds skipped.
/// With [missing] a red "No check-in" row comes first (spec 2026-10-06
/// §4.5); it is the app's own, not a server item. A
/// `yesterday_incomplete` item is a [YesterdayCard] that calls
/// [onYesterday] instead of [onTap].
class ForYouList extends StatelessWidget {
  const ForYouList({
    super.key,
    required this.items,
    required this.onTap,
    this.missing = false,
    this.onMissingTap,
    this.onYesterday,
  });

  final List<ForYouItem> items;
  final void Function(ForYouItem item) onTap;
  final bool missing;
  final VoidCallback? onMissingTap;
  final void Function(ForYouItem item)? onYesterday;

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
          if (item.kind == 'yesterday_incomplete')
            YesterdayCard(
              item: item,
              onTellHr: onYesterday == null ? null : () => onYesterday!(item),
            )
          else
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
