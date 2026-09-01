import 'dart:convert';

class NotificationRecord {
  final int id;
  final String kind;
  final String title;
  final String body;
  final Map<String, dynamic> payload;
  final bool read;
  final DateTime? createDate;

  NotificationRecord({
    required this.id,
    required this.kind,
    required this.title,
    this.body = '',
    this.payload = const {},
    this.read = false,
    this.createDate,
  });

  /// Tap-through hint: where the app should send the user.
  ///
  /// Returns the leave id when this is a leave_* notification, else null.
  int? get leaveIdHint {
    final v = payload['leave_id'];
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  bool get isLeaveKind =>
      kind == 'leave_approved' || kind == 'leave_refused';

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

  bool get isAnnouncementKind => kind == 'announcement';

  /// Tap-through hint for announcement notifications. Mirrors
  /// [leaveIdHint] but reads `announcement_id` from the payload.
  int? get announcementIdHint {
    final v = payload['announcement_id'];
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
    );
  }

  static DateTime? _parseDateTime(dynamic v) {
    if (v == null || v == false) return null;
    final s = v.toString();
    if (s.isEmpty) return null;
    final parsed = DateTime.tryParse(s);
    if (parsed == null) return null;
    return parsed.isUtc ? parsed.toLocal() : DateTime.utc(
      parsed.year, parsed.month, parsed.day,
      parsed.hour, parsed.minute, parsed.second,
    ).toLocal();
  }
}
