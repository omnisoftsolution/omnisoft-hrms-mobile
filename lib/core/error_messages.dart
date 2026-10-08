/// Central, safe converter from caught errors/exceptions to
/// user-friendly messages.
///
/// SECURITY: this function must NEVER return text that could contain the
/// request URI or the database name. Raw network exceptions
/// (`SocketException`, `http.ClientException`, `HandshakeException`) embed
/// the full request URL — which includes `?db=<database-name>` — in their
/// `.toString()`. The API layer (`OmniMobileApi._post`) already converts
/// those into the short `network_error` code, but this function is the
/// final safety net for every screen that renders an error string.
///
/// Usage: `setState(() => _error = friendlyError(e));`
library;

import '../services/omni_mobile_api.dart';

/// Local code (never sent by the server) for "My day could not be
/// refreshed and an older copy is still on screen".
const myDayRefreshFailed = 'my_day_refresh_failed';

/// App Identity error codes that [friendlyErrorCode] owns.
const _identityCodes = {
  'account_locked',
  'device_verification_required',
  'verification_code_invalid',
  'activation_invalid',
  'activation_expired',
  'activation_attempts_exceeded',
  'password_too_short',
  'refresh_invalid',
  'mail_not_configured',
  'login_invalid',
  'login_taken',
  'device_verification_unavailable',
  'email_send_failed',
};

/// Human message for an App Identity error code. [retryAfter] (seconds)
/// is only used by `account_locked`.
String friendlyErrorCode(String code, {int? retryAfter}) {
  switch (code) {
    case 'account_locked':
      final mins = ((retryAfter ?? 0) / 60).ceil().clamp(1, 1440);
      return 'Too many attempts. Try again in $mins minute${mins == 1 ? '' : 's'}.';
    case 'device_verification_required':
      return 'Check your work email for a sign-in code.';
    case 'verification_code_invalid':
      return 'That code is not right or has expired.';
    case 'activation_invalid':
      return 'This invite is not valid. Check the code, or ask HR to send a new one.';
    case 'activation_expired':
      return 'This invite has expired. Ask HR to send a new one.';
    case 'activation_attempts_exceeded':
      return 'Too many wrong codes. Ask HR to send a new invite.';
    case 'password_too_short':
      return 'Choose a longer password.';
    case 'refresh_invalid':
      return 'Please sign in again.';
    case 'mail_not_configured':
      return 'Password reset by email is not available here. Ask HR to reset it for you.';
    case 'login_invalid':
      return 'Use 3 to 64 characters without spaces.';
    case 'login_taken':
      return 'That login is already used. Choose another.';
    case 'device_verification_unavailable':
      return 'This phone needs a sign-in code, but there is no email on '
          'file for you. Ask HR for a new QR code.';
    case 'email_send_failed':
      return "We couldn't send the email right now. Try again in a few "
          'minutes, or ask HR for a new QR code.';
    default:
      return 'Something went wrong ($code). Please try again.';
  }
}

/// Maps a known server/error code (or an exception whose `.toString()`
/// contains one) to a friendly, human message. Falls back to a generic
/// message for anything unrecognized — it will not echo raw exception
/// text unless that text is a short, obviously-safe snake_case code.
String friendlyError(Object e) {
  if (e is ApiException && _identityCodes.contains(e.errorCode)) {
    return friendlyErrorCode(
      e.errorCode,
      retryAfter: (e.data?['retry_after'] as num?)?.toInt(),
    );
  }

  final approval = _approvalMessage(e);
  if (approval != null) return approval;

  final raw = e.toString();

  // --- Connectivity / transport ---
  if (raw.contains('network_error')) {
    return 'No internet connection. Check your network and try again.';
  }
  if (raw.contains('timeout')) {
    return 'The server is taking too long to respond. Please try again.';
  }
  if (raw.contains('server_error')) {
    return 'Something went wrong on our end. Please try again in a moment.';
  }

  // --- Session ---
  if (raw.contains('invalid_session') || raw.contains('invalid_token')) {
    return 'Your session has expired. Please log in again.';
  }

  // --- Attendance / geofence / face ---
  if (raw.contains('kiosk_only')) {
    return 'Your attendance is recorded at the kiosk.';
  }
  if (raw.contains(myDayRefreshFailed)) {
    return "Couldn't refresh. Pull down to try again.";
  }
  if (raw.contains('office_geofence_not_configured')) {
    return 'No office location is set for your profile. Ask HR to '
        'configure your work address.';
  }
  if (raw.contains('outside_geofence')) {
    return 'You are outside the allowed office location.';
  }
  if (raw.contains('mock_location')) {
    return 'Check-in blocked: your device appears to be using a fake (mock) '
        'location. Turn off any fake-GPS or mock location apps and try again.';
  }
  if (raw.contains('invalid_coordinates')) {
    return "We couldn't read a valid location from your device. Make sure "
        'location is turned on and try again.';
  }
  if (raw.contains('geo_required_missing_coords')) {
    return 'Location is required for your check-in. Turn on location '
        'services and try again.';
  }
  if (raw.contains('device_mismatch')) {
    return 'This device is not registered to your account. Please contact HR.';
  }
  if (raw.contains('wifi_required_missing')) {
    return 'Connect to the office Wi-Fi network to check in. Make sure '
        'Wi-Fi is on and Location is enabled.';
  }
  if (raw.contains('wifi_not_recognized') ||
      raw.contains('wifi_bssid_mismatch')) {
    return 'This Wi-Fi network is not recognized as your office network. '
        'Connect to the office Wi-Fi and try again.';
  }
  if (raw.contains('egress_ip_mismatch')) {
    return 'Your connection does not appear to come from the office '
        'network. Connect to the office Wi-Fi and try again.';
  }
  if (raw.contains('face_not_verified')) {
    return 'Face verification failed. Please try again.';
  }
  if (raw.contains('mobile_not_enabled')) {
    return 'Mobile attendance is not enabled for your profile.';
  }
  if (raw.contains('already_checked_in')) {
    return 'You are already checked in.';
  }
  if (raw.contains('not_checked_in')) {
    return 'You are not currently checked in.';
  }
  if (raw.contains('invalid_attendance')) {
    return 'Your previous check-in was too long ago. Please contact HR '
        'or close the record in the web app.';
  }

  // --- Forgot something? (connector 2.54.0) ---
  if (raw.contains('undo_expired')) {
    return 'It is too late to undo this punch. Ask HR to correct it.';
  }
  if (raw.contains('undo_not_last')) {
    return 'Only your latest punch can be undone.';
  }
  if (raw.contains('bad_time')) {
    return "That time doesn't fit this punch. Pick another time.";
  }
  if (raw.contains('too_old')) {
    return 'This day can no longer be changed from the app. Tell HR directly.';
  }
  if (raw.contains('not_yours')) {
    return 'This punch is not yours.';
  }
  if (raw.contains('already_answered')) {
    return 'You already answered this question.';
  }
  if (raw.contains('invalid_answer')) {
    return 'That answer is no longer available. Pull down to refresh.';
  }

  // --- Plan gate ---
  if (raw.contains('feature_unavailable')) {
    return "This feature isn't included in your company's plan. Ask HR.";
  }

  // --- Leave ---
  // HR decided the request while the History screen was open.
  if (raw.contains('not_cancellable') || raw.contains('not_modifiable')) {
    return 'This request was already decided. Pull down to refresh.';
  }
  if (raw.contains('leave_type_not_allowed')) {
    return "This leave type can't be requested from the app. Ask HR.";
  }
  if (raw.contains('invalid_hours')) {
    return 'Pick a start time before the end time.';
  }
  if (raw.contains('invalid_period')) {
    return 'Pick a valid half of the day.';
  }
  if (raw.contains('overlap')) {
    return 'You already have a leave request on these dates.';
  }
  if (raw.contains('allocation') || raw.contains('No more')) {
    return 'Not enough leave balance for this request.';
  }
  if (raw.contains('document_required')) {
    return 'A supporting document is required for this leave type.';
  }
  if (raw.contains('backdate_limit_exceeded')) {
    return 'This leave type does not allow a start date that far in the '
        'past. Please choose a later start date.';
  }

  // --- Safe fallback ---
  // Strip a leading "Exception: " then decide whether the remainder is
  // safe to show. Only surface it if it looks like a short server code
  // (snake_case, no spaces, no URLs, no '='). Anything else — including
  // raw SocketException/ClientException text that carries the db name —
  // collapses to a generic message.
  final stripped = raw.replaceFirst(RegExp(r'^Exception: '), '').trim();
  final looksLikeSafeCode = RegExp(r'^[a-z0-9_]{1,40}$').hasMatch(stripped);
  if (looksLikeSafeCode) return stripped;
  return _genericMessage;
}

const _genericMessage = 'Something went wrong. Please try again.';

/// Leave-approval codes from `/leave/approvals/*` (and `not_owner` from
/// `/leave/attachment/get`). Matched on the exact code, so a longer code
/// that merely contains one of these is left to the rules below.
String? _approvalMessage(Object e) {
  final code = e is ApiException ? e.errorCode : e.toString();
  final data = e is ApiException ? e.data : null;
  switch (code) {
    case 'not_allowed':
      return "You can't approve this request.";
    case 'state_changed':
      final state = data?['state']?.toString() ?? '';
      final by = data?['decided_by'];
      final name = by is String ? by.trim() : '';
      if (state == 'refuse') return 'Already refused';
      if (state == 'cancel') return 'This request was cancelled.';
      if (state == 'validate' || state == 'validate1') {
        return name.isEmpty ? 'Already approved' : 'Already approved by $name';
      }
      return 'This request has changed. Pull down to refresh.';
    case 'reason_required':
      final min = (data?['min'] as num?)?.toInt() ?? 3;
      final max = (data?['max'] as num?)?.toInt() ?? 500;
      return 'Write a reason of $min to $max characters.';
    case 'not_found':
      return 'This request no longer exists.';
    case 'not_owner':
      return "You don't have access to this file.";
  }
  return null;
}

/// Text for the dialog after a failed approve or refuse. When Odoo
/// refused the change with a validation message, the connector passes
/// that sentence through as the error code; it is shown as it is, ahead
/// of the app's keyword rules (a sentence mentioning "overlap" must not
/// become employee wording), because it tells the approver what to fix.
/// Only an [ApiException] qualifies (its text came from a JSON body,
/// never from a raw network exception), and anything that looks like a
/// URL or a query string falls through to [friendlyError]. Mapped codes
/// are single tokens without spaces, so they keep their own text.
String friendlyDecisionError(Object e) {
  if (e is ApiException) {
    final raw = e.errorCode.trim();
    // 'Unknown error' is ApiException.fromBody's default when the body
    // has no `error` key; it is not a sentence from Odoo.
    final safe =
        raw.contains(' ') &&
        raw != 'Unknown error' &&
        raw.length <= 300 &&
        !raw.contains('://') &&
        !raw.contains('=');
    if (safe) return raw;
  }
  return friendlyError(e);
}
