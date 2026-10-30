/// Push notification groups (spec 2026-10-11 §3.1), in the order the app
/// shows them. Keys are the connector's `PUSH_GROUPS` and the Android
/// notification channel ids (hrmsmanager sets `channel_id = push_group`).
class PushGroup {
  const PushGroup(
    this.key,
    this.name,
    this.description, {
    required this.channelDescription,
    this.canMute = true,
  });

  final String key;

  /// Name in Profile → Notifications and in Android's channel list.
  final String name;

  /// Line under the switch in Profile → Notifications.
  final String description;

  /// Description of the Android notification channel.
  final String channelDescription;

  /// Security cannot be muted (spec D8).
  final bool canMute;
}

const pushGroups = <PushGroup>[
  PushGroup(
    'requests',
    'My requests',
    'Leave and expense decisions',
    channelDescription: 'Leave and expense decisions',
  ),
  PushGroup(
    'approvals',
    'Approvals',
    'Requests waiting for you',
    channelDescription: 'Requests waiting for you',
  ),
  PushGroup(
    'attendance',
    'Attendance',
    'Questions and changes from HR',
    channelDescription: 'Questions and changes from HR',
  ),
  PushGroup(
    'reminders',
    'Check-in reminders',
    'Check in and check out',
    channelDescription: 'Reminders to check in and out',
  ),
  PushGroup(
    'news',
    'Company news',
    'Announcements and messages',
    channelDescription: 'Announcements and messages',
  ),
  PushGroup(
    'security',
    'Security',
    'Always on',
    channelDescription: 'Phones added to your account',
    canMute: false,
  ),
];

/// Push-only kinds (spec §4.8): no bell row; a tap opens Home.
const reminderPushKinds = {'remind_check_in', 'remind_check_out'};

bool isReminderKind(String kind) => reminderPushKinds.contains(kind);

/// Push-only confirmations of an automatic punch (connector 2.66.0): no
/// bell row either. They are not reminders ([isReminderKind] stays false),
/// but a tap and a foreground arrival go to Home like a reminder's
/// ([opensHomeKind]). `auto_recheck` is silent and never shown.
const autoConfirmationPushKinds = {'auto_checked_in', 'auto_checked_out'};

bool isAutoConfirmationKind(String kind) =>
    autoConfirmationPushKinds.contains(kind);

/// Push-only kinds whose tap opens Home and whose foreground arrival is a
/// snackbar with "Open": the reminders and the automatic-punch
/// confirmations.
bool opensHomeKind(String kind) =>
    isReminderKind(kind) || isAutoConfirmationKind(kind);

/// The title of an automatic-punch confirmation when the push carries none.
String autoConfirmationTitle(String kind) => kind == 'auto_checked_out'
    ? 'Checked out automatically'
    : 'Checked in automatically';

/// A reminder's title when the push carries none: the connector's own
/// wording (omni_mobile_push_reminder.py `TITLES`).
String reminderTitle(String kind) =>
    kind == 'remind_check_out' ? 'Still at work?' : 'Time to check in';
