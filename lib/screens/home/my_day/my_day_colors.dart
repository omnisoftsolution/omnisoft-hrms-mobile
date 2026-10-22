import '../../../core/omni_colors.dart';

export '../../../core/omni_colors.dart' show MyDayTone, MyDayToneKind;

/// The light My day tones, kept for the call sites that have not moved
/// to `context.omni.myDay` yet (dark mode, M2). Values live in
/// [MyDayPalette]; this class only points at them.
class MyDayColors {
  MyDayColors._();

  static const work = MyDayPalette.lightWork;
  static const brk = MyDayPalette.lightBrk;
  static const leave = MyDayPalette.lightLeave;
  static const late = MyDayPalette.lightLate;
  static const overtime = MyDayPalette.lightOvertime;
  static const missing = MyDayPalette.lightMissing;
  static const waiting = MyDayPalette.lightWaiting;
  static const holiday = MyDayPalette.lightHoliday;
}
