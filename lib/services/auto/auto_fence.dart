import 'dart:io' show Platform;

import 'package:native_geofence/native_geofence.dart';

import '../../models/auto_attendance_config.dart';
import 'auto_background.dart';

/// The native geofence plugin, as far as [AutoFence] needs it. A fake
/// subclass stands in for it in tests.
abstract class GeofencePort {
  Future<List<ActiveGeofence>> registered();
  Future<void> create(Geofence g);
  Future<void> removeById(String id);
}

/// The real plugin. A thin wrapper (platform channel), not unit-tested.
class NativeGeofencePort implements GeofencePort {
  NativeGeofencePort();

  Future<void>? _initialized;

  Future<void> _ready() => _initialized ??= NativeGeofenceManager.instance
          .initialize()
          .catchError((Object e) {
        // Allow a retry on the next call.
        _initialized = null;
        throw e;
      });

  @override
  Future<List<ActiveGeofence>> registered() async {
    await _ready();
    return NativeGeofenceManager.instance.getRegisteredGeofences();
  }

  @override
  Future<void> create(Geofence g) async {
    await _ready();
    await NativeGeofenceManager.instance.createGeofence(
      g,
      autoGeofenceTriggered,
    );
  }

  @override
  Future<void> removeById(String id) async {
    await _ready();
    await NativeGeofenceManager.instance.removeGeofenceById(id);
  }
}

/// Arms and disarms the office region (`omni_office_<db>_<employee>`).
///
/// [sync] is idempotent (lead decision L3): re-registering a region resets
/// iOS's state and loses a crossing, so it re-creates only when the id,
/// centre (6 decimals) or radius differ from what is registered.
class AutoFence {
  AutoFence({GeofencePort? port, bool? isAndroid})
      : _port = port ?? NativeGeofencePort(),
        _isAndroid = isAndroid ?? Platform.isAndroid;

  final GeofencePort _port;
  final bool _isAndroid;

  static String regionId(String db, int employeeId) =>
      autoRegionId(db, employeeId);

  /// Every region of [db] that this feature owns: `omni_office_<db>_<digits>`.
  /// The digits-only tail keeps db `a` from claiming the regions of db `a_b`.
  static bool _isOurs(String id, String db) {
    final prefix = 'omni_office_${db}_';
    if (!id.startsWith(prefix)) return false;
    final tail = id.substring(prefix.length);
    return tail.isNotEmpty && tail.codeUnits.every((c) => c >= 48 && c <= 57);
  }

  /// Arms the region for [employeeId] when [config] is present and Always
  /// location is granted; removes it otherwise, along with any other office
  /// region of this [db]. True when the region is armed afterwards.
  Future<bool> sync({
    required String db,
    required int employeeId,
    required AutoAttendanceConfig? config,
    required bool alwaysGranted,
  }) async {
    final wantedId = regionId(db, employeeId);
    final wanted = config != null && alwaysGranted;
    final mine = [
      for (final g in await _port.registered())
        if (_isOurs(g.id, db)) g,
    ];

    ActiveGeofence? current;
    for (final g in mine) {
      if (wanted && g.id == wantedId) {
        current = g;
      } else {
        await _port.removeById(g.id);
      }
    }
    if (!wanted) return false;

    if (current != null && _sameRegion(current, config)) return true;
    if (current != null) await _port.removeById(wantedId);
    await _port.create(_build(wantedId, config));
    return true;
  }

  /// Removes this [db]'s office regions (sign-out). Other tenants' and other
  /// plugins' regions are left alone.
  Future<void> removeAll(String db) async {
    for (final g in await _port.registered()) {
      if (_isOurs(g.id, db)) await _port.removeById(g.id);
    }
  }

  static double _round6(double v) => double.parse(v.toStringAsFixed(6));

  static bool _sameRegion(ActiveGeofence g, AutoAttendanceConfig c) =>
      _round6(g.location.latitude) == _round6(c.office.latitude) &&
      _round6(g.location.longitude) == _round6(c.office.longitude) &&
      g.radiusMeters == c.office.areaM.toDouble();

  Geofence _build(String id, AutoAttendanceConfig c) => Geofence(
        id: id,
        location: Location(
          latitude: c.office.latitude,
          longitude: c.office.longitude,
        ),
        radiusMeters: c.office.areaM.toDouble(),
        triggers: {
          GeofenceEvent.enter,
          GeofenceEvent.exit,
          if (_isAndroid) GeofenceEvent.dwell,
        },
        iosSettings: const IosGeofenceSettings(initialTrigger: false),
        androidSettings: AndroidGeofenceSettings(
          initialTriggers: const {},
          expiration: const Duration(days: 365),
          loiteringDelay: Duration(minutes: c.dwellMin),
          notificationResponsiveness: const Duration(minutes: 1),
        ),
      );
}
