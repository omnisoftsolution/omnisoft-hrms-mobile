import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../core/omni_colors.dart';
import '../../services/auto/auto_attendance_service.dart';
import 'auto_setup_card.dart';

enum _Step { disclosure, alwaysIos, alwaysAndroid, checking, result }

/// Setup flow of automatic check-in: the location disclosure (Play's
/// prominent disclosure, shown before any system prompt), the permission
/// steps, then the result read from [AutoAttendanceService.state].
class AutoSetupScreen extends StatefulWidget {
  const AutoSetupScreen({
    super.key,
    required this.auto,
    this.requestPermission = requestAutoPermission,
    this.isIos,
  });

  final AutoAttendanceService auto;

  @visibleForTesting
  final AutoPermissionRequest requestPermission;

  /// Platform choice; null reads [Platform].
  @visibleForTesting
  final bool? isIos;

  @override
  State<AutoSetupScreen> createState() => _AutoSetupScreenState();
}

class _AutoSetupScreenState extends State<AutoSetupScreen>
    with WidgetsBindingObserver {
  _Step _step = _Step.disclosure;
  bool _set = false;

  /// The session is not this phone's (`needsSetup`): no permission helps.
  bool _needsPhone = false;

  /// Location is denied for good: only the phone's settings can change it.
  bool _blocked = false;

  /// Android: the phone's settings were opened, so a resume re-checks.
  bool _openedSettings = false;

  bool get _ios => widget.isIos ?? Platform.isIOS;
  String get _office => widget.auto.config?.office.name ?? 'your office';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.auto.addListener(_onAuto);
  }

  @override
  void dispose() {
    widget.auto.removeListener(_onAuto);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool get _pausedResult => _step == _Step.result && !_set && !_needsPhone;

  /// iOS may answer the Always request before "Change to Always Allow" is
  /// tapped (device test 2026-10-30): a later sync that finds the phone set
  /// turns the paused result into the set one.
  void _onAuto() {
    final s = widget.auto.state;
    if (_pausedResult &&
        (s == AutoPhoneState.on || s == AutoPhoneState.waitingWifi)) {
      setState(() => _set = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_openedSettings &&
        (_step == _Step.alwaysAndroid || _step == _Step.result)) {
      _openedSettings = false;
      // Back from the settings and still not Always: they stay on offer.
      _finish(blocked: true);
    } else if (_pausedResult) {
      // Back from a system dialog answered after the request returned.
      _finish(blocked: _blocked);
    }
  }

  /// Continue: the while-in-use request, then the Always step.
  Future<void> _ask() async {
    setState(() => _step = _Step.checking);
    final word = await widget.requestPermission('while_using');
    if (!mounted) return;
    if (word == 'while_using') {
      setState(() => _step = _ios ? _Step.alwaysIos : _Step.alwaysAndroid);
    } else {
      await _finish(blocked: word == 'blocked');
    }
  }

  Future<void> _askAlways() async {
    setState(() => _step = _Step.checking);
    final word = await widget.requestPermission('always');
    if (!mounted) return;
    // Asked once and not Always: the phone does not ask again, so only the
    // settings are left.
    await _finish(blocked: word != 'always');
  }

  /// Try again goes back to the disclosure, so it is read before every
  /// request (Play's prominent disclosure).
  void _again() => setState(() {
    _blocked = false;
    _step = _Step.disclosure;
  });

  Future<void> _openSettings() async {
    _openedSettings = true;
    await widget.requestPermission('settings');
  }

  /// The permission changed (or the user gave up): tell the service and
  /// show what it says.
  Future<void> _finish({bool blocked = false}) async {
    if (mounted) setState(() => _step = _Step.checking);
    await widget.auto.sync();
    if (!mounted) return;
    final s = widget.auto.state;
    setState(() {
      _set = s == AutoPhoneState.on || s == AutoPhoneState.waitingWifi;
      _needsPhone = s == AutoPhoneState.needsSetup;
      _blocked = blocked;
      _step = _Step.result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omni;
    final text = Theme.of(context).textTheme;
    final bold = text.bodyLarge?.copyWith(
      color: c.text,
      fontWeight: FontWeight.w700,
    );
    final body = text.bodyLarge?.copyWith(color: c.text, height: 1.4);
    final sub = text.bodyMedium?.copyWith(color: c.textSub, height: 1.4);
    final title = text.headlineSmall?.copyWith(
      color: c.text,
      fontWeight: FontWeight.w700,
    );

    final List<Widget> children;
    switch (_step) {
      case _Step.disclosure:
        children = [
          Text('Automatic check-in', style: title),
          const SizedBox(height: 16),
          Text.rich(
            key: const ValueKey('auto-disclosure'),
            TextSpan(
              style: body,
              children: [
                TextSpan(
                  text:
                      'Omni HR collects your location to check you in when '
                      'you arrive at $_office and out when you leave, ',
                ),
                TextSpan(
                  text: 'even when the app is closed or not in use',
                  style: bold,
                ),
                const TextSpan(
                  text:
                      '. Only your office area is watched. Every automatic '
                      'check-in shows you a notice with Undo.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          FilledButton(
            key: const ValueKey('auto-continue-button'),
            onPressed: _ask,
            child: const Text('Continue'),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const ValueKey('auto-not-now-button'),
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Not now'),
          ),
        ];
      case _Step.alwaysIos:
        children = [
          Text('One more step', style: title),
          const SizedBox(height: 16),
          Text(
            'To check you in when the app is closed, Omni HR needs your '
            'location set to Always. When iPhone asks later, choose Change '
            'to Always Allow.',
            style: body,
          ),
          const SizedBox(height: 32),
          FilledButton(
            key: const ValueKey('auto-always-button'),
            onPressed: _askAlways,
            child: const Text('Continue'),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: _finish, child: const Text('Not now')),
        ];
      case _Step.alwaysAndroid:
        children = [
          Text('Choose Allow all the time', style: title),
          const SizedBox(height: 16),
          Text(
            'To check you in when the app is closed, open the settings, '
            'tap Permissions, then Location, and choose Allow all the time. '
            'Then come back to Omni HR.',
            style: body,
          ),
          const SizedBox(height: 32),
          FilledButton(
            key: const ValueKey('auto-settings-button'),
            onPressed: _openSettings,
            child: const Text('Open settings'),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: _finish, child: const Text('Not now')),
        ];
      case _Step.checking:
        children = const [
          SizedBox(height: 48),
          Center(child: CircularProgressIndicator()),
        ];
      case _Step.result:
        children = _set
            ? [
                Center(
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 48,
                    color: c.success,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "You're set. Omni HR checks you in at $_office.",
                  style: title,
                ),
                const SizedBox(height: 32),
                FilledButton(
                  key: const ValueKey('auto-done-button'),
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Done'),
                ),
              ]
            : [
                Center(
                  child: Icon(
                    Icons.pause_circle_rounded,
                    size: 48,
                    color: c.warning,
                  ),
                ),
                const SizedBox(height: 16),
                Text('Automatic check-in is paused', style: title),
                const SizedBox(height: 12),
                Text(
                  _needsPhone
                      ? autoNeedsThisPhoneText
                      : 'Omni HR needs your location set to Always to check '
                            'you in at $_office. You can still check in '
                            'yourself.',
                  style: sub,
                ),
                const SizedBox(height: 32),
                if (_needsPhone)
                  const SizedBox.shrink()
                else if (_blocked)
                  FilledButton(
                    key: const ValueKey('auto-settings-button'),
                    onPressed: _openSettings,
                    child: const Text('Open settings'),
                  )
                else
                  FilledButton(
                    key: const ValueKey('auto-retry-button'),
                    onPressed: _again,
                    child: const Text('Try again'),
                  ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Close'),
                ),
              ];
    }

    return PopScope(
      // Leaving between the steps: the permission may already have changed.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop &&
            (_step == _Step.alwaysIos || _step == _Step.alwaysAndroid)) {
          widget.auto.sync();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Automatic check-in')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            children: [...children],
          ),
        ),
      ),
    );
  }
}
