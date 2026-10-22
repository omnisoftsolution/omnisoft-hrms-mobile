import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/error_messages.dart';
import '../../core/push_groups.dart';
import '../../core/omni_colors.dart';
import '../../models/push_prefs.dart';
import '../../services/push_service.dart';
import '../../widgets/primary_button.dart';

/// Profile → Notifications (spec 2026-10-11 §6.6): a switch per group the
/// user can mute (Check-in reminders only when they apply), Security
/// always on, and "Notifications are off" while the phone does not allow
/// them (§6.2). Reads `push/prefs/get`, writes `push/prefs/set`.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key, this.push});

  /// Test seam; defaults to the app's [PushService].
  @visibleForTesting
  final PushService? push;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  late final PushService _push = widget.push ?? context.read<PushService>();
  PushPrefs? _prefs;
  PushPermission? _permission;
  bool _loading = true;
  Object? _error;

  /// A save is out: every switch waits (push/prefs/set replaces all mutes,
  /// so two overlapping saves could undo each other).
  bool _saving = false;

  /// The system prompt (or the settings page) is being opened: the button
  /// waits, so one tap is one request.
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the phone's settings: the permission may have changed.
    if (state == AppLifecycleState.resumed) _loadPermission();
  }

  Future<void> _load() async {
    try {
      final prefs = await _push.loadPrefs();
      final permission = await _push.permission();
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _permission = permission;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _load();
  }

  Future<void> _loadPermission() async {
    final permission = await _push.permission();
    if (mounted) setState(() => _permission = permission);
  }

  Future<void> _turnOn() async {
    if (_asking) return;
    setState(() => _asking = true);
    try {
      if (_permission == PushPermission.denied) {
        await _push.openSystemSettings();
        return;
      }
      final permission = await _push.requestPermission();
      if (mounted) setState(() => _permission = permission);
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  Future<void> _toggle(String group, bool on) async {
    if (_saving) return;
    // The last saved state: no other save can be out (switches wait).
    final before = _prefs!;
    final muted = {...before.muted};
    if (on) {
      muted.remove(group);
    } else {
      muted.add(group);
    }
    setState(() {
      _prefs = before.copyWith(muted: muted);
      _saving = true;
    });
    try {
      final saved = await _push.savePrefs(muted);
      if (!mounted) return;
      setState(() => _prefs = saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _prefs = before);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e)),
          backgroundColor: context.omni.errorFill,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final c = context.omni;
    if (_loading) return const Center(child: CircularProgressIndicator());
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                friendlyError(error),
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: c.textSub,
                ),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: _retry, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    final prefs = _prefs!;
    if (!prefs.pushAvailable) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            "Notifications aren't available for your company yet.",
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: c.textSub,
            ),
          ),
        ),
      );
    }
    final groups = pushGroups.where(
      (g) => g.key != 'reminders' || prefs.remindersAvailable,
    );
    return ListView(
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        32 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      children: [
        if (_permission != PushPermission.granted) ...[
          _offCard(c),
          const SizedBox(height: 16),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [for (final g in groups) _row(c, g, prefs)],
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(OmniColors c, PushGroup g, PushPrefs prefs) {
    final on = !g.canMute || !prefs.muted.contains(g.key);
    return SwitchListTile(
      key: ValueKey('push-switch-${g.key}'),
      title: Text(
        g.name,
        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        g.description,
        style: GoogleFonts.inter(
          fontSize: 12,
          color: c.textSub,
        ),
      ),
      value: on,
      activeTrackColor: c.brandFill,
      onChanged: !g.canMute || _saving ? null : (v) => _toggle(g.key, v),
    );
  }

  Widget _offCard(OmniColors c) {
    final denied = _permission == PushPermission.denied;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.notifications_off_outlined,
                  color: c.error,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Notifications are off',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              denied
                  ? 'Turn them on in your phone settings to hear about your '
                        'requests, approvals and reminders.'
                  : 'Turn them on to hear about your requests, approvals '
                        'and reminders.',
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.4,
                color: c.textSub,
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: denied ? 'Open settings' : 'Turn on notifications',
              loading: _asking,
              onPressed: _asking ? null : _turnOn,
            ),
          ],
        ),
      ),
    );
  }
}
