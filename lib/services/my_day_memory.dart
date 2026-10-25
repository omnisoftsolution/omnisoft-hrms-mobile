import '../models/my_day.dart';
import 'omni_mobile_api.dart';
import 'session_service.dart';

/// The last My day body of this sign-in, **in memory only** (1.34.1, P1):
/// flipping Home from Team overview to My day builds a new MyDayScreen,
/// which paints this at once and refetches, instead of a full spinner.
///
/// Never written to disk. It belongs to one sign-in: the key is the
/// server, the database, the employee and [SessionService.requestEpoch]
/// (which moves when a sign-out or logout begins and on every new access
/// token), so a body of another user, company or session is never read.
/// [SessionService] also clears it when a sign-out or logout begins, and
/// MyDayScreen clears it when the server says the employee or the session
/// is gone. A session without an employee keeps nothing.
///
/// The body only paints the screen: the check-in controller (GPS timer,
/// attendance status) is still created from the fresh answer, so no punch
/// is ever offered from a remembered day.
class MyDayMemory {
  MyDayMemory._();

  static MyDay? _day;
  static String? _key;

  static String? _keyOf(SessionService s) {
    if (s.employeeId <= 0) return null;
    return '${s.clientUrl}|${s.clientDb}|${s.employeeId}|${s.requestEpoch}';
  }

  /// The remembered body of [s]'s sign-in, or null (also drops a body that
  /// belongs to another sign-in).
  static MyDay? read(SessionService s) {
    final key = _keyOf(s);
    if (key == null || key != _key) {
      if (_key != null && key != _key) clear();
      return null;
    }
    return _day;
  }

  /// The sign-in a request is asked under: take it before the request and
  /// hand it to [write] with the answer.
  static String? bind(SessionService s) => _keyOf(s);

  /// Remembers [day], asked under [askedUnder] ([bind]), only while that is
  /// still [s]'s sign-in: an answer that lands after a sign-out or another
  /// sign-in is not kept (nothing without an employee either).
  static void write(SessionService s, String? askedUnder, MyDay day) {
    final key = _keyOf(s);
    if (key == null || key != askedUnder) return;
    _key = key;
    _day = day;
  }

  /// Answers after which the remembered body must go: the employee, the
  /// session or the app access is gone.
  static bool dropsOn(Object e) =>
      e is ApiException &&
      const {
        'no_employee_linked',
        'invalid_session',
        'session_expired',
        'not_allowed',
        'feature_unavailable',
        'mobile_not_enabled',
      }.contains(e.errorCode);

  /// Forgets the body (sign-out, logout, lost employee or session).
  static void clear() {
    _key = null;
    _day = null;
  }
}
