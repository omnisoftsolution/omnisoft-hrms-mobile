/// One announcement / personal message from the connector.
/// All parsing is tolerant: junk or old-server payloads degrade to
/// safe defaults, never throw.
class AnnouncementRecord {
  final int id;
  final String name;
  final String body;
  final String kind; // 'announcement' | 'direct_message'
  final String priority; // 'normal' | 'urgent'
  final DateTime? dateStart;
  final DateTime? dateEnd;
  final bool hasImage;
  final bool acked;

  const AnnouncementRecord({
    required this.id,
    required this.name,
    required this.body,
    required this.kind,
    required this.priority,
    required this.dateStart,
    required this.dateEnd,
    required this.hasImage,
    required this.acked,
  });

  bool get isDirect => kind == 'direct_message';
  bool get isUrgent => priority == 'urgent';

  static DateTime? _parseDateTime(dynamic v) {
    if (v == null || v == false) return null;
    final s = v.toString();
    if (s.isEmpty) return null;
    final parsed = DateTime.tryParse(s);
    if (parsed == null) return null;
    return parsed.isUtc
        ? parsed.toLocal()
        : DateTime.utc(parsed.year, parsed.month, parsed.day,
            parsed.hour, parsed.minute, parsed.second).toLocal();
  }

  factory AnnouncementRecord.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    return AnnouncementRecord(
      id: rawId is num
          ? rawId.toInt()
          : int.tryParse(rawId?.toString() ?? '') ?? 0,
      name: json['name'] is String ? json['name'] as String : '',
      body: json['body'] is String ? json['body'] as String : '',
      kind: json['kind'] == 'direct_message'
          ? 'direct_message'
          : 'announcement',
      priority: json['priority'] == 'urgent' ? 'urgent' : 'normal',
      dateStart: _parseDateTime(json['date_start']),
      dateEnd: _parseDateTime(json['date_end']),
      hasImage: json['has_image'] == true,
      acked: json['acked'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'body': body,
        'kind': kind,
        'priority': priority,
        'date_start': dateStart?.toUtc().toIso8601String(),
        'date_end': dateEnd?.toUtc().toIso8601String(),
        'has_image': hasImage,
        'acked': acked,
      };
}

/// Whole /announcement/list response — the tenant-scoped cache unit.
class AnnouncementListResult {
  final List<AnnouncementRecord> announcements;
  const AnnouncementListResult({required this.announcements});

  factory AnnouncementListResult.fromJson(Map<String, dynamic> json) {
    final list = json['announcements'] as List<dynamic>? ?? const [];
    return AnnouncementListResult(
      announcements: list
          .whereType<Map>()
          .map((e) =>
              AnnouncementRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
        'announcements': announcements.map((a) => a.toJson()).toList(),
      };
}
