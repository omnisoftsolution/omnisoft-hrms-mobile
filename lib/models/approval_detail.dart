import 'approval_item.dart';
import 'leave_record.dart' show LeaveAttachment;

/// Balance left on the leave type once this request is counted.
/// Null on the detail for types that need no allocation.
class ApprovalBalance {
  /// Odoo request_unit: day | half_day | hour.
  final String unit;
  final double total;
  final double remaining;

  const ApprovalBalance({
    required this.unit,
    required this.total,
    required this.remaining,
  });

  static ApprovalBalance? fromJson(dynamic j) {
    if (j is! Map) return null;
    return ApprovalBalance(
      unit: ApprovalItem.strOf(j['unit']),
      total: ApprovalItem.numOf(j['total']),
      remaining: ApprovalItem.numOf(j['remaining']),
    );
  }

  /// '10 days left of 14' / '96h left of 112h'.
  String get label {
    final r = ApprovalItem.fmtNum(remaining);
    final t = ApprovalItem.fmtNum(total);
    if (unit == 'hour') return '${r}h left of ${t}h';
    return '$r ${remaining == 1 ? 'day' : 'days'} left of $t';
  }
}

/// One approval step of a request, in Odoo's order.
class ApprovalStep {
  /// manager_approval | hr_approval.
  final String label;

  /// done | current | next | refused.
  final String status;

  /// Who approved or refused at this step ('' when unknown).
  final String byName;

  /// Raw Odoo UTC datetime of the decision ('' when not decided).
  final String at;

  /// Who can act at this step.
  final List<String> candidates;

  const ApprovalStep({
    required this.label,
    required this.status,
    this.byName = '',
    this.at = '',
    this.candidates = const [],
  });

  factory ApprovalStep.fromJson(Map<String, dynamic> j) => ApprovalStep(
        label: ApprovalItem.strOf(j['label']),
        status: ApprovalItem.strOf(j['status']),
        byName: ApprovalItem.strOf(ApprovalItem.mapOf(j['by'])['name']),
        at: ApprovalItem.strOf(j['at']),
        candidates: (j['candidates'] is List ? j['candidates'] as List : const [])
            .map((e) => e.toString())
            .toList(),
      );

  bool get isDone => status == 'done';
  bool get isCurrent => status == 'current';
  bool get isRefused => status == 'refused';

  String get title => label == 'hr_approval' ? 'HR approval' : 'Manager approval';

  /// Done: who approved. Refused: who refused. Otherwise: who can act.
  String get subtitle {
    if (isRefused) return byName.isEmpty ? 'Refused' : 'Refused by $byName';
    if (isDone) return byName.isEmpty ? 'Done' : byName;
    return candidates.join(' or ');
  }
}

/// The `/leave/approvals/get` payload: the list row plus everything the
/// approver needs to decide.
class ApprovalDetail {
  final ApprovalItem item;

  /// The employee's own note on the request.
  final String note;
  final String avatarB64;
  final String resourceCalendar;
  final List<LeaveAttachment> attachments;
  final ApprovalBalance? balanceAfter;
  final List<ApprovalStep> steps;

  const ApprovalDetail({
    required this.item,
    this.note = '',
    this.avatarB64 = '',
    this.resourceCalendar = '',
    this.attachments = const [],
    this.balanceAfter,
    this.steps = const [],
  });

  factory ApprovalDetail.fromJson(Map<String, dynamic> j) {
    final emp = ApprovalItem.mapOf(j['employee']);
    List<Map<String, dynamic>> maps(dynamic v) =>
        (v is List ? v : const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
    return ApprovalDetail(
      item: ApprovalItem.fromJson(j),
      note: ApprovalItem.strOf(j['name']),
      avatarB64: ApprovalItem.strOf(emp['avatar_b64']),
      resourceCalendar: ApprovalItem.strOf(emp['resource_calendar']),
      attachments: maps(j['attachments']).map(LeaveAttachment.fromJson).toList(),
      balanceAfter: ApprovalBalance.fromJson(j['balance_after']),
      steps: maps(j['steps']).map(ApprovalStep.fromJson).toList(),
    );
  }
}
