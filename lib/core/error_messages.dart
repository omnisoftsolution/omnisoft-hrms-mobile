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

/// Maps a known server/error code (or an exception whose `.toString()`
/// contains one) to a friendly, human message. Falls back to a generic
/// message for anything unrecognized — it will not echo raw exception
/// text unless that text is a short, obviously-safe snake_case code.
String friendlyError(Object e) {
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
  if (raw.contains('device_mismatch')) {
    return 'This device is not registered to your account. Please contact HR.';
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

  // --- Leave ---
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
  return 'Something went wrong. Please try again.';
}
