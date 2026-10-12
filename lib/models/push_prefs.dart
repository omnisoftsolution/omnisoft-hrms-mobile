/// The signed-in user's push settings: the answer of `push/prefs/get` and
/// `push/prefs/set` (connector 2.63.0, spec 2026-10-11 §4.1).
class PushPrefs {
  const PushPrefs({
    required this.pushAvailable,
    required this.remindersAvailable,
    required this.muted,
  });

  /// The tenant is connected to hrmsmanager, so pushes are sent. False
  /// hides Profile → Notifications (spec §6.6).
  final bool pushAvailable;

  /// Check-in reminders can apply to this employee (company switch,
  /// attendance feature, not kiosk-only, a fixed schedule).
  final bool remindersAvailable;

  /// Muted group keys (never `security`).
  final Set<String> muted;

  factory PushPrefs.fromJson(Map<String, dynamic> json) {
    final raw = json['muted'];
    return PushPrefs(
      pushAvailable: json['push_available'] == true,
      remindersAvailable: json['reminders_available'] == true,
      muted: raw is List ? raw.whereType<String>().toSet() : <String>{},
    );
  }

  PushPrefs copyWith({Set<String>? muted}) => PushPrefs(
    pushAvailable: pushAvailable,
    remindersAvailable: remindersAvailable,
    muted: muted ?? this.muted,
  );
}
