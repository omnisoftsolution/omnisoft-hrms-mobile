import 'package:flutter/material.dart';

/// Asks for the 6-digit sign-in code the connector emailed when this
/// phone is not yet trusted (`device_verification_required`). Returns
/// the digits, or null when the user cancels.
Future<String?> showDeviceCodeDialog(BuildContext context,
    {required String email, String? error}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('New phone'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('We sent a 6-digit code to $email. '
                'Enter it to trust this phone.'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Code'),
              onChanged: (_) => setState(() {}),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: ctrl.text.trim().length == 6
                ? () => Navigator.of(ctx).pop(ctrl.text.trim())
                : null,
            child: const Text('Continue'),
          ),
        ],
      ),
    ),
  );
}
