import '../models/approval_item.dart';

/// "2 Annual Leave · 1 Sick Leave" for the requests waiting on this
/// user's own step. Most frequent type first, then by name.
String approvalsBreakdown(List<ApprovalItem> items) {
  final counts = <String, int>{};
  for (final it in items) {
    if (!it.assignedToMe || it.leaveTypeName.isEmpty) continue;
    counts[it.leaveTypeName] = (counts[it.leaveTypeName] ?? 0) + 1;
  }
  final names = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
  return names.map((n) => '${counts[n]} $n').join(' · ');
}
