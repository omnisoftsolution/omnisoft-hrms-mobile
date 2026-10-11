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

  /// The request's `waiting_for` (2.62.0+), set only on the current step
  /// of a pending request; it replaces the step title.
  final WaitingFor? waitingFor;

  const ApprovalStep({
    required this.label,
    required this.status,
    this.byName = '',
    this.at = '',
    this.candidates = const [],
    this.waitingFor,
  });

  factory ApprovalStep.fromJson(Map<String, dynamic> j,
          {WaitingFor? waitingFor}) =>
      ApprovalStep(
        label: ApprovalItem.strOf(j['label']),
        status: ApprovalItem.strOf(j['status']),
        byName: ApprovalItem.strOf(ApprovalItem.mapOf(j['by'])['name']),
        at: ApprovalItem.strOf(j['at']),
        candidates: (j['candidates'] is List ? j['candidates'] as List : const [])
            .map((e) => e.toString())
            .toList(),
        waitingFor: waitingFor,
      );

  bool get isDone => status == 'done';
  bool get isCurrent => status == 'current';
  bool get isRefused => status == 'refused';

  /// 'Your approval' / 'Waiting for Kelvin (manager)' / 'Waiting for HR'
  /// on the current step (2.62.0+); otherwise the step's name.
  String get title =>
      waitingFor?.label ??
      (label == 'hr_approval' ? 'HR approval' : 'Manager approval');

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
    final item = ApprovalItem.fromJson(j);
    List<Map<String, dynamic>> maps(dynamic v) =>
        (v is List ? v : const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
    // waiting_for names whose turn it is now, so it titles only the
    // current step, and only while the request is still pending.
    WaitingFor? waitingFor(Map<String, dynamic> step) =>
        item.isPending && ApprovalItem.strOf(step['status']) == 'current'
            ? item.waitingFor
            : null;
    return ApprovalDetail(
      item: item,
      note: ApprovalItem.strOf(j['name']),
      avatarB64: ApprovalItem.strOf(emp['avatar_b64']),
      resourceCalendar: ApprovalItem.strOf(emp['resource_calendar']),
      attachments: maps(j['attachments']).map(LeaveAttachment.fromJson).toList(),
      balanceAfter: ApprovalBalance.fromJson(j['balance_after']),
      steps: maps(j['steps'])
          .map((s) => ApprovalStep.fromJson(s, waitingFor: waitingFor(s)))
          .toList(),
    );
  }
}
