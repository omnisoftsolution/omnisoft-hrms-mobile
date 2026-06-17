class LeaveRecord {
  final int id;
  final int leaveTypeId;
  final String leaveType;
  final String? dateFrom;
  final String? dateTo;
  final double numberOfDays;
  final String state;
  final String reason;
  final double? allocationTotal;
  final double? allocationTaken;
  final double? allocationRemaining;
  final bool requiresAllocation;
  final bool requiresDocument;
  final String requestUnit;
  final String? dateFromPeriod;
  final String? dateToPeriod;
  final double? hourFrom;
  final double? hourTo;
  final double numberOfHours;
  final List<LeaveAttachment> attachments;
  final bool allowBackdated;
  final DateTime? earliestBackdateDate;

  LeaveRecord({
    required this.id,
    this.leaveTypeId = 0,
    required this.leaveType,
    this.dateFrom,
    this.dateTo,
    required this.numberOfDays,
    required this.state,
    this.reason = '',
    this.allocationTotal,
    this.allocationTaken,
    this.allocationRemaining,
    this.requiresAllocation = false,
    this.requiresDocument = false,
    this.requestUnit = 'day',
    this.dateFromPeriod,
    this.dateToPeriod,
    this.hourFrom,
    this.hourTo,
    this.numberOfHours = 0,
    this.attachments = const [],
    this.allowBackdated = false,
    this.earliestBackdateDate,
  });

  factory LeaveRecord.fromJson(Map<String, dynamic> json) {
    return LeaveRecord(
      id: json['id'] ?? 0,
      leaveTypeId: json['leave_type_id'] ?? 0,
      leaveType: json['leave_type'] ?? '',
      dateFrom: json['date_from']?.toString(),
      dateTo: json['date_to']?.toString(),
      numberOfDays: (json['number_of_days'] ?? 0).toDouble(),
      state: json['state'] ?? '',
      reason: json['reason'] ?? '',
      allocationTotal: (json['allocation_total'] as num?)?.toDouble(),
      allocationTaken: (json['allocation_taken'] as num?)?.toDouble(),
      allocationRemaining: (json['allocation_remaining'] as num?)?.toDouble(),
      requiresAllocation: _parseBool(json['requires_allocation']),
      requiresDocument: _parseBool(json['requires_document']),
      requestUnit: json['request_unit'] ?? 'day',
      dateFromPeriod: json['date_from_period']?.toString(),
      dateToPeriod: json['date_to_period']?.toString(),
      hourFrom: (json['hour_from'] as num?)?.toDouble(),
      hourTo: (json['hour_to'] as num?)?.toDouble(),
      numberOfHours: (json['number_of_hours'] ?? 0).toDouble(),
      attachments: (json['attachments'] as List<dynamic>? ?? [])
          .map((e) => LeaveAttachment.fromJson(e as Map<String, dynamic>))
          .toList(),
      allowBackdated: _parseBool(json['allow_backdated']),
      earliestBackdateDate: _parseDate(json['earliest_backdate_date']),
    );
  }

  String get daysLabel {
    if (requestUnit == 'hour') {
      final h = numberOfHours;
      return h == h.roundToDouble()
          ? '${h.toInt()}h'
          : '${h.toStringAsFixed(1)}h';
    }
    final n = numberOfDays;
    return n == n.roundToDouble()
        ? '${n.toInt()}d'
        : '${n.toStringAsFixed(1)}d';
  }

  String get allocationUnit => requestUnit == 'hour' ? 'hours' : 'days';

  static DateTime? _parseDate(dynamic v) {
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  static bool _parseBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.toLowerCase();
      return s == 'true' || s == 'yes' || s == '1';
    }
    return false;
  }

  String get stateLabel {
    switch (state) {
      case 'draft':
        return 'Draft';
      case 'confirm':
        return 'Pending';
      case 'validate1':
        return 'Approved (L1)';
      case 'validate':
        return 'Approved';
      case 'refuse':
        return 'Refused';
      case 'cancel':
        return 'Cancelled';
      default:
        return state;
    }
  }
}

class LeaveAttachment {
  final int id;
  final String name;
  final String mimetype;
  final int fileSize;

  LeaveAttachment({
    required this.id,
    required this.name,
    required this.mimetype,
    this.fileSize = 0,
  });

  factory LeaveAttachment.fromJson(Map<String, dynamic> json) {
    return LeaveAttachment(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      mimetype: json['mimetype'] ?? '',
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
    );
  }

  String get sizeLabel {
    if (fileSize < 1024) return '${fileSize}B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(0)}KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}
