import 'dart:convert';

class NotificationRecord {
  final int id;
  final String kind;
  final String title;
  final String body;
  final Map<String, dynamic> payload;
  final bool read;
  final DateTime? createDate;

  /// attendance_query: the employee already replied (one answer only).
  final bool answered;

  NotificationRecord({
    required this.id,
    required this.kind,
    required this.title,
    this.body = '',
    this.payload = const {},
    this.read = false,
    this.createDate,
    this.answered = false,
  });

  /// HR's "Ask the employee" (spec 2026-10-07 §4.5): answered in the app
  /// with the declaration sheet.
  bool get isAttendanceQuery => kind == 'attendance_query';

  /// HR applied the employee's declared time (connector 2.54.0).
  bool get isDeclarationApplied => kind == 'attendance_declaration_applied';

  /// Tap-through hint: where the app should send the user.
  ///
  /// Returns the leave id when this is a leave_* notification, else null.
  int? get leaveIdHint {
    final v = payload['leave_id'];
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// A notice about the user's OWN leave request: tapping it opens their
  /// leave history on that request. `leave_first_approved` (connector
  /// 2.43.0+) is the "first approval done, now waiting for HR" notice.
  bool get isLeaveKind =>
      kind == 'leave_approved' ||
      kind == 'leave_refused' ||
      kind == 'leave_first_approved';

  /// "Approval needed": someone else's request waits for this user's
  /// decision. Tapping it opens the request for approval ([leaveIdHint]).
  bool get isApprovalRequestKind => kind == 'leave_approval_requested';

  /// Label of the snackbar action shown when this notification arrives
  /// while the app is open; null when it has nowhere to go.
  String? get snackActionLabel {
    if (isApprovalRequestKind) return 'Review';
    if (isLeaveKind || isExpenseKind) return 'VIEW';
    return null;
  }

  bool get isExpenseKind =>
      kind == 'expense_approved' || kind == 'expense_refused';

  /// Tap-through hint for expense_* notifications. Mirrors
  /// [leaveIdHint] but reads `expense_id` from the payload.
  int? get expenseIdHint {
    final v = payload['expense_id'];
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  factory NotificationRecord.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> payload = const {};
    final raw = json['payload'];
    if (raw is String && raw.isNotEmpty) {
      try {
        payload = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        // ignore — leave payload empty if server sent garbage
      }
    } else if (raw is Map<String, dynamic>) {
      payload = raw;
    }
    return NotificationRecord(
      id: (json['id'] as num?)?.toInt() ?? 0,
      kind: json['kind']?.toString() ?? 'system',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      payload: payload,
      read: json['read'] == true,
      createDate: _parseDateTime(json['create_date']),
      answered: json['answered'] == true,
    );
  }

  static DateTime? _parseDateTime(dynamic v) {
    if (v == null || v == false) return null;
    final s = v.toString();
    if (s.isEmpty) return null;
    final parsed = DateTime.tryParse(s);
    if (parsed == null) return null;
    return parsed.isUtc
        ? parsed.toLocal()
        : DateTime.utc(
            parsed.year,
            parsed.month,
            parsed.day,
            parsed.hour,
            parsed.minute,
            parsed.second,
          ).toLocal();
  }
}
