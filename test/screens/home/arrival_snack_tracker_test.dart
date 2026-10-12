import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/screens/home/arrival_snack_tracker.dart';

void main() {
  test('a tap on the notice whose arrival snackbar is on screen hides it, '
      'once (F1)', () {
    final t = ArrivalSnackTracker();
    t.shown(11);
    expect(t.takeIfShowing(12), isFalse);
    expect(t.takeIfShowing(11), isTrue);
    expect(t.takeIfShowing(11), isFalse);
  });

  test('a snackbar that replaced the arrival (a reminder) is not hidden by a '
      'tap on the old notice', () {
    final t = ArrivalSnackTracker();
    t.shown(11);
    t.replaced();
    expect(t.takeIfShowing(11), isFalse);
  });

  test('a closed arrival snackbar is no longer on screen; a late close of an '
      'older one does not clear a newer one', () {
    final t = ArrivalSnackTracker();
    final closeOld = t.shown(11);
    closeOld();
    expect(t.takeIfShowing(11), isFalse);

    final closeA = t.shown(11);
    t.shown(12); // a newer arrival replaced it
    closeA(); // the old snackbar's close lands late
    expect(t.takeIfShowing(12), isTrue);
  });
}
