import 'dart:math';

/// What the phone saw: it arrived at the office or left it.
enum AutoKind { arrive, leave }

/// What produced the event. `geofence` is the default and is omitted from the
/// request body (the server treats a missing source as `geofence`).
enum AutoSource { geofence, dwell, foreground, wifi, recheck }

/// One automatic check-in / check-out event, as posted to the connector's
/// auto-event route and as kept in the offline queue ([AutoEventQueue]).
///
/// [eventAt] is always UTC. [deviceId] and [appVersion] are supplied by the
/// caller (the background isolate cannot rely on app singletons).
class AutoEvent {
  const AutoEvent({
    required this.eventUid,
    required this.kind,
    required this.eventAt,
    this.latitude,
    this.longitude,
    this.accuracy,
    required this.isMocked,
    this.wifiSsid,
    this.wifiBssid,
    required this.deviceId,
    required this.appVersion,
    required this.source,
    this.owner,
  });

  final String eventUid;
  final AutoKind kind;
  final DateTime eventAt;
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final bool isMocked;
  final String? wifiSsid;
  final String? wifiBssid;
  final String deviceId;
  final String appVersion;
  final AutoSource source;

  /// Whose event this is, `<db>|<employee id>` (`AutoKeyStore.ownerOf`):
  /// kept in the queue only, never sent. [AutoSender.flush] drops an event
  /// of another sign-in (R136-F03). Null = queued before 1.36.0 (115).
  final String? owner;

  /// The request body of the auto-event route (contract keys, verbatim).
  Map<String, dynamic> toBody() => {
    'event_uid': eventUid,
    'kind': kind.name,
    'event_at': _naiveUtc(eventAt),
    'latitude': latitude,
    'longitude': longitude,
    'location_accuracy': accuracy,
    'is_mocked': isMocked,
    'wifi_ssid': wifiSsid,
    'wifi_bssid': wifiBssid,
    'device_id': deviceId,
    'app_version': appVersion,
    if (source != AutoSource.geofence) 'source': source.name,
  };

  /// Queue storage form (not the request body).
  Map<String, dynamic> toJson() => {
    'event_uid': eventUid,
    'kind': kind.name,
    'event_at': eventAt.toUtc().toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'is_mocked': isMocked,
    'wifi_ssid': wifiSsid,
    'wifi_bssid': wifiBssid,
    'device_id': deviceId,
    'app_version': appVersion,
    'source': source.name,
    'owner': ?owner,
  };

  factory AutoEvent.fromJson(Map json) => AutoEvent(
    eventUid: json['event_uid'] as String,
    kind: AutoKind.values.byName(json['kind'] as String),
    eventAt: DateTime.parse(json['event_at'] as String).toUtc(),
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    accuracy: (json['accuracy'] as num?)?.toDouble(),
    isMocked: json['is_mocked'] as bool? ?? false,
    wifiSsid: json['wifi_ssid'] as String?,
    wifiBssid: json['wifi_bssid'] as String?,
    deviceId: json['device_id'] as String,
    appVersion: json['app_version'] as String,
    source: AutoSource.values.byName(
      json['source'] as String? ?? AutoSource.geofence.name,
    ),
    owner: json['owner'] as String?,
  );

  /// `'a-'` + 24 lowercase hex chars (fits the server's `[\x21-\x7e]{1,64}`).
  static String newUid() {
    final rng = Random.secure();
    final hex = StringBuffer('a-');
    for (var i = 0; i < 24; i++) {
      hex.write(rng.nextInt(16).toRadixString(16));
    }
    return hex.toString();
  }

  static String _naiveUtc(DateTime t) {
    final u = t.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}'
        ' ${two(u.hour)}:${two(u.minute)}:${two(u.second)}';
  }
}
