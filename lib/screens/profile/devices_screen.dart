import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/datetime_utils.dart';
import '../../core/error_messages.dart';
import '../../core/theme.dart';
import '../../services/omni_mobile_api.dart';
import '../../services/session_service.dart';
import '../../widgets/error_state_view.dart';

/// Profile → Security & Privacy → "Your devices" (App Identity accounts
/// only). Lists the phones trusted for this account; any phone other than
/// this one can be signed out (revoked) here.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late final OmniMobileApi _api;
  List<Map<String, dynamic>>? _devices;
  String? _error;
  bool _loading = true;
  bool _revoking = false;

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionService>();
    _api = OmniMobileApi(
      baseUrl: session.clientUrl,
      db: session.clientDb,
      token: session.token,
    );
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final devices = await _api.devicesList();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  Future<void> _revoke(Map<String, dynamic> device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text(
            'Sign out this phone? It will need the password next time.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _revoking = true);
    try {
      await _api.deviceRevoke('${device['device_id'] ?? ''}');
      if (!mounted) return;
      setState(() => _revoking = false);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _revoking = false);
      messenger.showSnackBar(SnackBar(
          content: Text(friendlyError(e)), backgroundColor: AppTheme.error));
    }
  }

  String _subtitle(Map<String, dynamic> d) {
    final since = DateTimeUtils.formatLocalDate(d['trusted_since'] as String?);
    final seen =
        DateTimeUtils.formatLocalDateTime(d['last_seen_at'] as String?);
    return 'Trusted since $since · last seen $seen';
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [ErrorStateView(message: _error!, onRetry: _load)],
      );
    }
    final devices = _devices ?? const [];
    final others = devices.where((d) => d['current'] != true);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final d in devices)
            ListTile(
              leading: const Icon(Icons.smartphone),
              title: Text((d['label'] as String?)?.isNotEmpty == true
                  ? d['label'] as String
                  : 'Unnamed phone'),
              subtitle: Text(_subtitle(d)),
              trailing: d['current'] == true
                  ? const Chip(label: Text('This phone'))
                  : TextButton(
                      onPressed: _revoking ? null : () => _revoke(d),
                      child: const Text('Revoke'),
                    ),
            ),
          if (others.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('No other phones are signed in.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your devices')),
      body: SafeArea(child: _body()),
    );
  }
}
