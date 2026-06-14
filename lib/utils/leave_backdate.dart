/// Earliest selectable start date for a leave, given the backdate policy the
/// server computed for its type. Robust to old servers (backdating off).
///
/// - [allowBackdated] false  -> today (no past).
/// - [floor] non-null        -> that date (the server-computed working-day floor).
/// - [floor] null + allowed  -> today - 365 days (unlimited; keep picker bounded).
DateTime backdateFirstDate(bool allowBackdated, DateTime? floor, DateTime now) {
  final midnightToday = DateTime(now.year, now.month, now.day);
  if (!allowBackdated) return midnightToday;
  if (floor != null) return DateTime(floor.year, floor.month, floor.day);
  return midnightToday.subtract(const Duration(days: 365));
}
