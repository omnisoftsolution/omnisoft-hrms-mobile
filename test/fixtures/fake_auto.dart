import 'package:omni_hr/models/auto_attendance_config.dart';
import 'package:omni_hr/services/auto/auto_attendance_service.dart';
import 'package:omni_hr/services/session_service.dart';

final fakeAutoConfig = AutoAttendanceConfig.fromJson({
  'trigger': 'location_wifi',
  'dwell_min': 5,
  'exit_min': 10,
  'office': {'name': 'HQ', 'latitude': 1.3, 'longitude': 103.8, 'area_m': 150},
  'wifi_required': true,
})!;

/// Automatic check-in with a scripted state: no platform, no network.
/// [sync] moves to [afterSync] (when set) and counts the call. Set
/// SharedPreferencesAsync's in-memory platform before constructing one.
class FakeAuto extends AutoAttendanceService {
  FakeAuto({AutoPhoneState initial = AutoPhoneState.needsAlways})
    : _state = initial,
      super(session: SessionService());

  AutoPhoneState _state;
  AutoPhoneState? afterSync;
  AutoPhoneState? afterTurnOn;
  int syncs = 0;
  int turnOns = 0;

  @override
  AutoPhoneState get state => _state;

  @override
  AutoAttendanceConfig? get config => fakeAutoConfig;

  void setState(AutoPhoneState s) {
    _state = s;
    notifyListeners();
  }

  @override
  Future<void> sync({bool appStart = false}) async {
    syncs++;
    final next = afterSync;
    if (next != null) setState(next);
  }

  @override
  Future<void> turnOnAgain() async {
    turnOns++;
    final next = afterTurnOn;
    if (next != null) setState(next);
  }
}
