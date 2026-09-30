/// Mirror of the connector's `normalize_login` (spec 2026-09-30 §2).
///
/// Used only to compare what the employee typed with the login the invite
/// link carried; the server stays the authority on what is stored.
/// Trim + lowercase; phone-shaped input (digits, spaces, + - . ( ) and at
/// least 6 digits) becomes digits only.
String normalizeAppLogin(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isNotEmpty && RegExp(r'^[\d\s+\-.()]+$').hasMatch(s)) {
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 6) return digits;
  }
  return s;
}
