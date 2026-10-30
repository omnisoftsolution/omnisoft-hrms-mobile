import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auto_event.dart';

/// What the server said about a posted auto event (or status).
sealed class AutoPostResult {
  const AutoPostResult();
}

/// 2xx with `success: true`. [state] is the server's word for what happened
/// (`checked_in`, `waiting_wifi`, ...); [reason] and [confirmAfter] are only
/// present on some states. For a status post the state is simply `'ok'`.
class AutoAccepted extends AutoPostResult {
  const AutoAccepted(this.state, {this.reason, this.confirmAfter});

  final String state;
  final String? reason;

  /// When the server wants the Wi-Fi re-checked (UTC).
  final DateTime? confirmAfter;
}

/// The server refused the post for good: resending the same event will not
/// help (bad event, no employee linked, feature off, any other 4xx).
class AutoFinal extends AutoPostResult {
  const AutoFinal(this.error);

  final String error;
}

/// Not answered usefully (409 busy, 422, 5xx, timeout, network error,
/// non-JSON): keep the event and resend it later with the same `event_uid`.
class AutoRetry extends AutoPostResult {
  const AutoRetry(this.why);

  final String why;
}

/// 401: the auto key (or bearer session) is no longer valid.
class AutoKeyInvalid extends AutoPostResult {
  const AutoKeyInvalid();
}

/// Client for the automatic check-in routes.
///
/// Deliberately separate from `OmniMobileApi` (lead decision L8): it needs the
/// HTTP status to tell a retryable answer from a final one, and a background
/// wake must never fire `OmniMobileApi.onInvalidSession` (it would sign the
/// user out). It authenticates with the auto key (`X-Omni-Auto-Key`) when one
/// is given, else with the bearer session.
class AutoApi {
  AutoApi({
    required this.baseUrl,
    required this.db,
    this.autoKey,
    this.bearer,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String db;
  final String? autoKey;
  final String? bearer;
  final Duration timeout;
  final http.Client _client;

  Map<String, String> get _headers {
    final key = autoKey;
    final token = bearer;
    return {
      'Content-Type': 'application/json',
      if (key != null && key.isNotEmpty)
        'X-Omni-Auto-Key': key
      else if (token != null && token.isNotEmpty)
        'Authorization': 'Bearer $token',
    };
  }

  Uri _uri(String path) => Uri.parse('$baseUrl/api/v1/omni_mobile$path?db=$db');

  Future<AutoPostResult> postEvent(AutoEvent e) =>
      _post('/attendance/auto/event', e.toBody());

  /// Tells the server this phone's permission and arming state. Success is
  /// `200 {success: true}`, reported as `AutoAccepted('ok')`.
  Future<AutoPostResult> postStatus({
    required String permission,
    required bool enabled,
    required String platform,
  }) => _post('/attendance/auto/status', {
    'permission': permission,
    'enabled': enabled,
    'platform': platform,
  });

  Future<AutoPostResult> _post(String path, Map<String, dynamic> body) async {
    final http.Response response;
    try {
      response = await _client
          .post(_uri(path), headers: _headers, body: jsonEncode(body))
          .timeout(timeout);
    } on TimeoutException {
      return const AutoRetry('timeout');
    } catch (_) {
      // Raw network errors carry the request URI (with the database name);
      // keep only a clean code.
      return const AutoRetry('network_error');
    }
    return _classify(response);
  }

  AutoPostResult _classify(http.Response response) {
    final status = response.statusCode;
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } on FormatException {
      data = null;
    }
    final error = data?['error']?.toString();

    if (data == null) {
      // Not a JSON object, whatever the status (a proxy or error page, a bare
      // 404 from a connector without the route): never a verdict on the
      // event, so keep it and resend later.
      return AutoRetry(status >= 400 ? 'http_$status' : 'non_json');
    }
    if (status == 401) return const AutoKeyInvalid();
    if (status == 408 ||
        status == 409 ||
        status == 422 ||
        status == 429 ||
        status >= 500) {
      return AutoRetry(error ?? 'http_$status');
    }
    if (status >= 400) return AutoFinal(error ?? 'http_$status');
    if (data['success'] == true) {
      return AutoAccepted(
        data['state']?.toString() ?? 'ok',
        reason: data['reason']?.toString(),
        confirmAfter: _parseNaiveUtc(data['confirm_after']),
      );
    }
    return AutoFinal(error ?? 'unknown_error');
  }

  /// Server timestamps are naive UTC `YYYY-MM-DD HH:MM:SS`.
  static DateTime? _parseNaiveUtc(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    final t = raw.trim().replaceFirst(' ', 'T');
    final hasZone = t.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(t);
    return DateTime.tryParse(hasZone ? t : '${t}Z')?.toUtc();
  }
}
