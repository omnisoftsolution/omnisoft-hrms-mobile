import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Shared "something went wrong" state — a centered card with a red
/// alert icon, a friendly message, and an optional Retry button.
///
/// This is the single source of truth for the look of a failed data
/// load across the app (Home, Leave, History, etc.). Always feed it a
/// message that has already been through `friendlyError()` — never a
/// raw exception string. See lib/core/error_messages.dart.
class ErrorStateView extends StatelessWidget {
  /// The user-facing message (already humanized).
  final String message;

  /// Called when the user taps Retry. If null, the button is hidden.
  final Future<void> Function()? onRetry;

  /// Label for the retry action.
  final String retryLabel;

  const ErrorStateView({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Retry',
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppTheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => onRetry!.call(),
                child: Text(retryLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
