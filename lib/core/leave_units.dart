// Pure unit helpers for leave balances and durations.
//
// Contract with the connector (v2.39.1+): balance numbers arrive in
// the type's request_unit — hours for hour-unit types, days otherwise
// — and /leave/types carries the employee's `hours_per_day` so hour
// balances can show a day equivalent. When hours_per_day is absent
// (older connector) we fall back to 8.

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
