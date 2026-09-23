import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/error_messages.dart';
import '../../core/theme.dart';
import '../../services/omni_mobile_api.dart';
import '../../services/session_service.dart';

/// Profile → Security & Privacy → "Change password" (App Identity accounts
/// only). The server signs out every other phone on success.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  static const _minLength = 8;

  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_busy &&
      _current.text.isNotEmpty &&
      _new.text.length >= _minLength &&
      _new.text == _confirm.text;

  Future<void> _submit() async {
    final session = context.read<SessionService>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = OmniMobileApi(
      baseUrl: session.clientUrl,
      db: session.clientDb,
      token: session.token,
    );
    try {
      await api.passwordChange(
        currentPassword: _current.text,
        newPassword: _new.text,
      );
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
          content: Text('Password changed. Other phones were signed out.')));
      navigator.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (e.errorCode) {
          'invalid_credentials' => 'Current password is not right.',
          'password_too_short' => friendlyErrorCode('password_too_short'),
          _ => friendlyError(e),
        };
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyError(e);
      });
    }
  }

  Widget _field(String key, String label, TextEditingController c) {
    return TextField(
      key: Key(key),
      controller: c,
      obscureText: true,
      enabled: !_busy,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(labelText: label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _field('pw_current', 'Current password', _current),
            const SizedBox(height: 16),
            _field('pw_new', 'New password', _new),
            const SizedBox(height: 16),
            _field('pw_new2', 'Confirm new password', _confirm),
            const SizedBox(height: 8),
            Text('At least $_minLength characters.',
                style:
                    TextStyle(fontSize: 12, color: AppTheme.onSurfaceVariant)),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: AppTheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _canSubmit ? _submit : null,
              child: const Text('Change password'),
            ),
          ],
        ),
      ),
    );
  }
}
