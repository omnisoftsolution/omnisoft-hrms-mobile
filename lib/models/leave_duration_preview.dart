/// Duration Odoo would store for a prospective leave request, as
/// returned by the connector's /leave/preview (v2.41.0+). Numbers are
/// in Odoo's units — both days and hours are always present — and
/// [requestUnit] says which one the type leads with.
class LeaveDurationPreview {
  final double days;
  final double hours;
  final String requestUnit;

  const LeaveDurationPreview({
    required this.days,
    required this.hours,
    required this.requestUnit,
  });

  factory LeaveDurationPreview.fromJson(Map<String, dynamic> json) {
    return LeaveDurationPreview(
      days: _toDouble(json['number_of_days']),
      hours: _toDouble(json['number_of_hours']),
      requestUnit: json['request_unit']?.toString() ?? 'day',
    );
  }

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }
}
