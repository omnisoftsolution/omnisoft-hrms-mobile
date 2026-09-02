// Pure unit helpers for leave balances and durations.
//
// Contract with the connector (v2.39.1+): balance numbers arrive in
// the type's request_unit — hours for hour-unit types, days otherwise
// — and /leave/types carries the employee's `hours_per_day` so hour
// balances can show a day equivalent. When hours_per_day is absent
// (older connector) we fall back to 8.
//
// Connector v2.41.0+ adds /leave/preview: the duration Odoo itself
// would store for a prospective request. "Specific hours" previews
// use it because the app cannot see the employee's schedule — 11:00
// to 15:00 is 4h end-minus-start but 3h once Odoo drops the 12-13
// lunch block. Without the endpoint the sheets fall back to the naive
// number, never blocking the form on a preview.

const double kFallbackHoursPerDay = 8.0;

String _fmt(double n) =>
    n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(1);

/// "112h (14d)" / "112 hours (14 days)" for hour-unit types;
/// "6d" / "6 days" for day-unit types.
String balanceAmountLabel(
  double n,
  String requestUnit,
  double? hoursPerDay, {
  required bool longForm,
}) {
  if (requestUnit == 'hour') {
    final hpd = (hoursPerDay != null && hoursPerDay > 0)
        ? hoursPerDay
        : kFallbackHoursPerDay;
    final days = _fmt(n / hpd);
    return longForm
        ? '${_fmt(n)} hours ($days days)'
        : '${_fmt(n)}h (${days}d)';
  }
  return longForm ? '${_fmt(n)} days' : '${_fmt(n)}d';
}

/// Compact duration label for a full-day range on an hour-unit type,
/// shown in the apply sheet's date box: "2d (16h)".
String compactDaysWithHours(double days, double hoursPerDay) {
  return '${_fmt(days)}d (${_fmt(days * hoursPerDay)}h)';
}

/// Duration label for a "Specific hours" selection: "3h" / "2.5h".
///
/// [serverHours] is Odoo's computed duration from /leave/preview and
/// wins when present, even while a newer preview is [loading] (no
/// flicker back to the naive number). With nothing from the server yet
/// the label is an ellipsis while loading, otherwise [naiveHours]
/// (end minus start — the pre-2.41.0 connector behaviour).
String customHoursLabel({
  required double naiveHours,
  double? serverHours,
  bool loading = false,
}) {
  if (serverHours != null) return '${_fmt(serverHours)}h';
  if (loading) return '…';
  return '${_fmt(naiveHours)}h';
}

/// One-line explanation shown under the time pickers when Odoo counts
/// fewer hours than end-minus-start; null when there is nothing to
/// explain (no server value, or the two agree).
String? customHoursCaption({
  required double naiveHours,
  double? serverHours,
}) {
  if (serverHours == null || serverHours >= naiveHours) return null;
  if (serverHours <= 0) {
    return 'The selected time is outside your work schedule.';
  }
  return 'Breaks in your work schedule are not counted.';
}
