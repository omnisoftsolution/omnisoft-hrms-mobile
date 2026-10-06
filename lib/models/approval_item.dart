import 'package:intl/intl.dart';

import '../core/datetime_utils.dart';

/// One row of the approver's Pending or Recent list
/// (`/leave/approvals/pending` and `/leave/approvals/recent`,
/// connector 2.43.0+). The Recent-only fields stay empty on Pending rows.
class ApprovalItem {
  final int id;
  final int employeeId;
  final String employeeName;
  final String department;
  final int leaveTypeId;
  final String leaveTypeName;

  /// Odoo state: confirm | validate1 | validate | refuse | cancel.
  final String state;

  /// Odoo leave_validation_type: both | hr | manager | no_validation.
  final String validationType;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final bool unitHours;
  final double hourFrom;
  final double hourTo;
  final double numberOfDays;
  final double numberOfHours;

  /// Short text from the connector: '2d', '0.5d', '3h'.
  final String durationLabel;

  /// manager_approval | hr_approval.
  final String step;
  final bool assignedToMe;
  final bool hasAttachment;

  /// Raw Odoo UTC datetime ('YYYY-MM-DD HH:MM:SS'), '' when absent.
  final String createDate;
  final bool canApprove;
  final bool canRefuse;

  /// Recent only: approved | refused | waiting_hr ('' on Pending rows).
  final String outcome;

  /// Recent only: raw Odoo UTC datetime of the last change.
  final String decidedAt;
  final String firstApproverName;
  final String secondApproverName;
  final String refusalReason;

  const ApprovalItem({
    required this.id,
    this.employeeId = 0,
    this.employeeName = '',
    this.department = '',
    this.leaveTypeId = 0,
    this.leaveTypeName = '',
    this.state = '',
    this.validationType = '',
    this.dateFrom,
    this.dateTo,
    this.unitHours = false,
    this.hourFrom = 0,
    this.hourTo = 0,
    this.numberOfDays = 0,
    this.numberOfHours = 0,
    this.durationLabel = '',
    this.step = '',
    this.assignedToMe = false,
    this.hasAttachment = false,
    this.createDate = '',
    this.canApprove = false,
    this.canRefuse = false,
    this.outcome = '',
    this.decidedAt = '',
    this.firstApproverName = '',
    this.secondApproverName = '',
    this.refusalReason = '',
  });

  factory ApprovalItem.fromJson(Map<String, dynamic> j) {
    final emp = mapOf(j['employee']);
    final type = mapOf(j['leave_type']);
    return ApprovalItem(
      id: intOf(j['id']),
      employeeId: intOf(emp['id']),
      employeeName: strOf(emp['name']),
      department: strOf(emp['department']),
      leaveTypeId: intOf(type['id']),
      leaveTypeName: strOf(type['name']),
      state: strOf(j['state']),
      validationType: strOf(j['validation_type']),
      dateFrom: DateTime.tryParse(strOf(j['request_date_from'])),
      dateTo: DateTime.tryParse(strOf(j['request_date_to'])),
      unitHours: j['request_unit_hours'] == true,
      hourFrom: numOf(j['request_hour_from']),
      hourTo: numOf(j['request_hour_to']),
      numberOfDays: numOf(j['number_of_days']),
      numberOfHours: numOf(j['number_of_hours']),
      durationLabel: strOf(j['duration_label']),
      step: strOf(j['step']),
      assignedToMe: j['assigned_to_me'] == true,
      hasAttachment: j['has_attachment'] == true,
      createDate: strOf(j['create_date']),
      canApprove: j['can_approve'] == true,
      canRefuse: j['can_refuse'] == true,
      outcome: strOf(j['outcome']),
      decidedAt: strOf(j['decided_at']),
      firstApproverName: strOf(mapOf(j['first_approver'])['name']),
      secondApproverName: strOf(mapOf(j['second_approver'])['name']),
      refusalReason: strOf(j['refusal_reason']),
    );
  }

  /// Still waiting for a decision (To Approve or Second Approval).
  bool get isPending => state == 'confirm' || state == 'validate1';

  /// Chip on a Pending row.
  String get stepLabel {
    if (assignedToMe) return 'Your approval';
    return step == 'hr_approval' ? 'HR approval' : 'Manager approval';
  }

  /// Chip on a Recent row ('' when the connector sent no outcome).
  String get outcomeLabel {
    switch (outcome) {
      case 'approved':
        return 'Approved';
      case 'refused':
        return 'Refused';
      case 'waiting_hr':
        return 'Waiting for HR';
      default:
        return '';
    }
  }

  /// 'Tue 6 Oct – Wed 7 Oct', 'Tue 6 Oct', 'Tue 6 Oct, 13:30 – 17:30'.
  String get datesLabel {
    final from = dateFrom;
    if (from == null) return '';
    final f = DateFormat('EEE d MMM');
    final to = dateTo;
    if (to != null && !_sameDay(from, to)) {
      return '${f.format(from)} – ${f.format(to)}';
    }
    if (unitHours && hourTo > hourFrom) {
      return '${f.format(from)}, ${_hm(hourFrom)} – ${_hm(hourTo)}';
    }
    return f.format(from);
  }

  /// The duration Odoo computed: '2 days (16h)', '1 day (8h)', '4h'.
  /// Falls back to the connector's short label when it sent no numbers.
  String get durationLong {
    if (numberOfDays <= 0 && numberOfHours <= 0) return durationLabel;
    final hours = '${fmtNum(numberOfHours)}h';
    if (unitHours || durationLabel.endsWith('h')) return hours;
    final days =
        '${fmtNum(numberOfDays)} ${numberOfDays == 1 ? 'day' : 'days'}';
    return numberOfHours > 0 ? '$days ($hours)' : days;
  }

  /// 'Submitted today', 'Submitted 2d ago', ... ('' without a date).
  String get submittedLabel => DateTimeUtils.formatSubmittedAgo(createDate);

  /// 'Decided 10 Sep' ('' without a date).
  String get decidedLabel {
    final dt = DateTimeUtils.parseOdooUtc(decidedAt);
    if (dt == null) return '';
    return 'Decided ${DateFormat('d MMM').format(dt.toLocal())}';
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _hm(double h) {
    var hh = h.floor();
    var mm = ((h - hh) * 60).round();
    if (mm == 60) {
      hh += 1;
      mm = 0;
    }
    return '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
  }

  // ---- JSON helpers shared with approval_detail.dart ----

  /// A nested JSON object, or an empty map for null / false / other.
  static Map<String, dynamic> mapOf(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

  /// Odoo serialises an empty value as `false`: read it as ''.
  static String strOf(dynamic v) =>
      (v == null || v == false) ? '' : v.toString();

  static double numOf(dynamic v) => v is num ? v.toDouble() : 0;

  static int intOf(dynamic v) => v is num ? v.toInt() : 0;

  /// 2.0 -> '2', 0.5 -> '0.5'.
  static String fmtNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}
