class LeaveType {
  final int id;
  final String name;
  final bool requiresAllocation;
  final String requestUnit;
  final int color;
  final String mobileCategory;
  final bool mobileRequiresDocument;
  final bool allowBackdated;
  final int backdateLimitDays;
  final DateTime? earliestBackdateDate;

  // Balance fields — null when requiresAllocation is false (the
  // type is "unlimited"). When requiresAllocation is true these
  // reflect this employee's current allocation/usage from Odoo's
  // hr.leave.type computed fields.
  final double? maxLeaves;
  final double? leavesTaken;
  final double? virtualRemainingLeaves;

  // Employee's working hours per day (connector 2.39.1+). Used to show
  // a day equivalent next to hour-unit balances; null on older
  // connectors (callers fall back to 8).
  final double? hoursPerDay;

  LeaveType({
    required this.id,
    required this.name,
    required this.requiresAllocation,
    this.requestUnit = 'day',
    this.color = 0,
    this.mobileCategory = 'other',
    this.mobileRequiresDocument = false,
    this.allowBackdated = false,
    this.backdateLimitDays = 0,
    this.earliestBackdateDate,
    this.maxLeaves,
    this.leavesTaken,
    this.virtualRemainingLeaves,
    this.hoursPerDay,
  });

  factory LeaveType.fromJson(Map<String, dynamic> json) {
    return LeaveType(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      requiresAllocation: json['requires_allocation'] == true,
      requestUnit: json['request_unit'] ?? 'day',
      color: json['color'] ?? 0,
      mobileCategory: json['mobile_category'] ?? 'other',
      mobileRequiresDocument: json['mobile_requires_document'] == true,
      allowBackdated: json['allow_backdated'] == true,
      backdateLimitDays: _toInt(json['backdate_limit_days']),
      earliestBackdateDate: _toDate(json['earliest_backdate_date']),
      maxLeaves: _toDouble(json['max_leaves']),
      leavesTaken: _toDouble(json['leaves_taken']),
      virtualRemainingLeaves: _toDouble(json['virtual_remaining_leaves']),
      hoursPerDay: _toDouble(json['hours_per_day']),
    );
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static DateTime? _toDate(dynamic v) {
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }
}
