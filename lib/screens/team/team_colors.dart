import 'package:flutter/material.dart';

import '../../core/omni_colors.dart';
import 'team_format.dart';

/// Colours of the team screens (Team leave outlook, Team overview), copied
/// from the light palettes of the mockups `TeamLeave.dc.html` (`c`) and
/// `Overview.dc.html` (`BUCKETS`). This is the only team file that holds
/// hex values, so the dark-mode pass changes one place.
///
/// One instance per brightness: [light] (the values up to 1.34.1, unchanged)
/// and [dark] (canvas 2026-10-26, approved by Willy). Read it with
/// `TeamColors.of(context)`. Dark notes: the heat map steps down to dark
/// blues with a white digit on [c1] / [c2] and a light [c3] with a dark
/// digit; Sunday and "PH" use the dark error tone; the overview buckets keep
/// their [MyDayTone.fill] (it sits on the coloured tile) and take tint /
/// onTint / dot from `OmniColors.dark.myDay` of the bucket's kind.
@immutable
class TeamColors {
  const TeamColors._({
    required this.cell0,
    required this.cellLine,
    required this.offDigit,
    required this.sunday,
    required this.c1,
    required this.c2,
    required this.c3,
    required this.onC1,
    required this.onC2,
    required this.onC3,
    required this.holCell,
    required this.holText,
    required this.holDot,
    required this.leave,
    required this.leaveTint,
    required this.leaveOn,
    required this.accent,
    required this.accentTint,
    required this.onAccentTint,
    required this.muted,
    required this.skeleton,
    required this.chipBorder,
    required this.onTime,
    required this.late,
    required this.notInYet,
    required this.noCheckIn,
    required this.onLeave,
    required this.offToday,
    required this.overviewTile,
    required this.overviewTileYesterday,
  });

  /// The palette of the current brightness.
  static TeamColors of(BuildContext context) =>
      context.isDarkTheme ? dark : light;

  // ---- Heat map (TeamLeave.dc.html `c`, recoloured in 1.34.1) ----------
  // 1.34.1 (colleague feedback): the three near-identical greys are gone.
  // A working day is a very light surface with a hairline, a non-working day
  // has no fill and a muted digit, a public holiday is a light red tint with
  // a red "PH", and Sunday's digit is red like a paper calendar.

  /// A working day nobody is off: a very light neutral surface…
  final Color cell0;

  /// …outlined by this hairline.
  final Color cellLine;

  /// A day nobody in the set works: no fill (the digit is [offDigit]).
  Color get cellOff => const Color(0x00000000);

  /// The digit of a non-working day (muted; 5.4:1 on the white card).
  final Color offDigit;

  /// Sunday's digit and weekday letter (calendar convention only — it does
  /// not say the day is a rest day). AppTheme.error; 6:1 on [cell0], 4.6:1
  /// on [c1]. On [c2] / [c3] the usual digit colour is kept for contrast.
  final Color sunday;

  /// One, two, three or more people off.
  final Color c1;
  final Color c2;
  final Color c3;

  /// Text on [c1] and [c2] (light: the usual text colour; dark: white).
  final Color onC1;
  final Color onC2;

  /// Text on [c3].
  final Color onC3;

  /// A public holiday for everyone: light red tint (the error container).
  final Color holCell;

  /// The "PH" on [holCell] (AppTheme.error; 5.1:1).
  final Color holText;

  /// The dot on a day that is a public holiday for some people only.
  final Color holDot;

  // ---- Leave tones ------------------------------------------------------
  final Color leave;
  final Color leaveTint;
  final Color leaveOn;

  // ---- Accent and text --------------------------------------------------
  final Color accent;
  final Color accentTint;
  final Color onAccentTint;

  /// Secondary text (mockup `muted`).
  final Color muted;

  /// Loading placeholders (mockup `skel`).
  final Color skeleton;

  /// Unselected filter chip border (mockup `line2`).
  final Color chipBorder;

  /// Heat-map shade for [off] people off on a working day.
  Color shade(int off) {
    if (off <= 0) return cell0;
    if (off == 1) return c1;
    if (off == 2) return c2;
    return c3;
  }

  /// Initials-avatar fill (A-L6): `hsl(id * 47 % 360, 55%, 45%)`, the
  /// same colour as [initialsHue]. The same in both brightnesses.
  Color avatar(int id) => initialsHue(id);

  /// The initials on an [avatar] (white in both brightnesses).
  Color get onAvatar => const Color(0xFFFFFFFF);

  // ---- Team overview buckets (Overview.dc.html `BUCKETS`) ---------------
  // fill = the bar segment on the overview tile, tint / onTint = the chip,
  // dot = the count tile's dot.
  final MyDayTone onTime;
  final MyDayTone late;
  final MyDayTone notInYet;
  final MyDayTone noCheckIn;
  final MyDayTone onLeave;
  final MyDayTone offToday;

  /// The overview tile: today (live) and yesterday (reviewed).
  final Color overviewTile;
  final Color overviewTileYesterday;

  // ---- On the overview tiles (Overview.dc.html white overlays) ---------
  // Text, icons and lines drawn on [overviewTile] / [overviewTileYesterday].
  // New widgets never write Colors.white (A-L19). The same in both
  // brightnesses (the tile stays a dark fill).
  /// Headline text and icons on a tile.
  Color get onTile => const Color(0xFFFFFFFF);

  /// Secondary text on a tile (white at 0.9).
  Color get onTileSoft => const Color(0xE6FFFFFF);

  /// The quietest text on a tile: the live line, the reviewed copy (0.85).
  Color get onTileFaint => const Color(0xD9FFFFFF);

  /// The divider on a tile (white at 0.22).
  Color get tileLine => const Color(0x38FFFFFF);

  /// The bar's empty track on a tile (white at 0.14).
  Color get tileTrack => const Color(0x24FFFFFF);

  /// The icon badge behind the tile's group icon (white at 0.18).
  Color get tileBadge => const Color(0x2EFFFFFF);

  /// Tone of an overview bucket key (`on_time`, `late`, `not_in_yet`,
  /// `no_check_in`, `on_leave`, `off_today`); unknown keys read as off.
  MyDayTone bucket(String key) => switch (key) {
    'on_time' => onTime,
    'late' => late,
    'not_in_yet' => notInYet,
    'no_check_in' => noCheckIn,
    'on_leave' => onLeave,
    _ => offToday,
  };

  /// The values up to 1.34.1 (light mockups), unchanged.
  static const light = TeamColors._(
    cell0: Color(0xFFF5F7F9),
    cellLine: Color(0xFFE0E3E5),
    offDigit: Color(0xFF5F6C6E), // = muted
    sunday: Color(0xFFBA1A1A), // AppTheme.error
    c1: Color(0xFFC9DAF8),
    c2: Color(0xFF8FB0E3),
    c3: Color(0xFF395F97),
    onC1: Color(0xFF191C1E), // AppTheme.onSurface
    onC2: Color(0xFF191C1E), // AppTheme.onSurface
    onC3: Color(0xFFFFFFFF),
    holCell: Color(0xFFFFDAD6),
    holText: Color(0xFFBA1A1A), // AppTheme.error
    holDot: Color(0xFFB3261E),
    leave: Color(0xFF395F97),
    leaveTint: Color(0xFFD6E3FF),
    leaveOn: Color(0xFF1D477E),
    accent: Color(0xFF006971), // AppTheme.primary
    accentTint: Color(0xFFDCEFF1),
    onAccentTint: Color(0xFF004F55),
    muted: Color(0xFF5F6C6E),
    skeleton: Color(0xFFE6E8EA),
    chipBorder: Color(0xFFBCC9CA), // AppTheme.outlineVariant
    onTime: MyDayTone(
      kind: MyDayToneKind.work,
      fill: Color(0xFFFFFFFF),
      tint: Color(0xFFDCEFF1),
      onTint: Color(0xFF004F55),
      dot: Color(0xFF006971),
    ),
    late: MyDayTone(
      kind: MyDayToneKind.late,
      fill: Color(0xFFFFD58A),
      tint: Color(0xFFFFE4A8),
      onTint: Color(0xFF6B4400),
      dot: Color(0xFFD99A1C),
    ),
    notInYet: MyDayTone(
      kind: MyDayToneKind.waiting,
      fill: Color(0x73FFFFFF),
      tint: Color(0xFFECEEF0),
      onTint: Color(0xFF55666A),
      dot: Color(0xFF6C797B),
    ),
    noCheckIn: MyDayTone(
      kind: MyDayToneKind.missing,
      fill: Color(0xFFFFB4AB),
      tint: Color(0xFFFFDAD6),
      onTint: Color(0xFF93000A),
      dot: Color(0xFFBA1A1A),
    ),
    onLeave: MyDayTone(
      kind: MyDayToneKind.leave,
      fill: Color(0xFFA8C8FF),
      tint: Color(0xFFD6E3FF),
      onTint: Color(0xFF1D477E),
      dot: Color(0xFF395F97),
    ),
    offToday: MyDayTone(
      kind: MyDayToneKind.holiday,
      fill: Color(0x33FFFFFF),
      tint: Color(0xFFE0E3E5),
      onTint: Color(0xFF3D494A),
      dot: Color(0xFF9AA5A6),
    ),
    overviewTile: Color(0xFF006971), // AppTheme.primary
    overviewTileYesterday: Color(0xFF395F97), // AppTheme.secondary
  );

  /// Dark values (canvas 2026-10-26, approved by Willy). Bucket tint /
  /// onTint / dot are `MyDayPalette.dark` of each kind (a test checks it).
  static const dark = TeamColors._(
    cell0: Color(0xFF222B2C),
    cellLine: Color(0xFF2C3738),
    offDigit: Color(0xFF8F9A9B),
    sunday: Color(0xFFFFB4AB),
    c1: Color(0xFF27416B),
    c2: Color(0xFF3B66A6),
    c3: Color(0xFFA8C8FF),
    onC1: Color(0xFFFFFFFF),
    onC2: Color(0xFFFFFFFF),
    onC3: Color(0xFF0E1415),
    holCell: Color(0xFF5C1A16),
    holText: Color(0xFFFFB4AB),
    holDot: Color(0xFFFF8A80),
    leave: Color(0xFFA8C8FF),
    leaveTint: Color(0xFF1F3557),
    leaveOn: Color(0xFFD6E3FF),
    accent: Color(0xFF58D8E4),
    accentTint: Color(0xFF0F3B3F),
    onAccentTint: Color(0xFF9EF0F7),
    muted: Color(0xFF8F9A9B),
    skeleton: Color(0xFF222B2C),
    chipBorder: Color(0xFF3A4647),
    onTime: MyDayTone(
      kind: MyDayToneKind.work,
      fill: Color(0xFFFFFFFF),
      tint: Color(0xFF0F3B3F),
      onTint: Color(0xFF9EF0F7),
      dot: Color(0xFF58D8E4),
    ),
    late: MyDayTone(
      kind: MyDayToneKind.late,
      fill: Color(0xFFFFD58A),
      tint: Color(0xFF4A3A12),
      onTint: Color(0xFFFFE4A8),
      dot: Color(0xFFE8A93A),
    ),
    notInYet: MyDayTone(
      kind: MyDayToneKind.waiting,
      fill: Color(0x73FFFFFF),
      tint: Color(0xFF2A3334),
      onTint: Color(0xFFBFC8CA),
      dot: Color(0xFF6F7B7C),
    ),
    noCheckIn: MyDayTone(
      kind: MyDayToneKind.missing,
      fill: Color(0xFFFFB4AB),
      tint: Color(0xFF5C1A16),
      onTint: Color(0xFFFFDAD6),
      dot: Color(0xFFFF8A80),
    ),
    onLeave: MyDayTone(
      kind: MyDayToneKind.leave,
      fill: Color(0xFFA8C8FF),
      tint: Color(0xFF1F3557),
      onTint: Color(0xFFD6E3FF),
      dot: Color(0xFFA8C8FF),
    ),
    offToday: MyDayTone(
      kind: MyDayToneKind.holiday,
      fill: Color(0x33FFFFFF),
      tint: Color(0xFF2A3334),
      onTint: Color(0xFFC9D1D2),
      dot: Color(0xFF9AA5A6),
    ),
    overviewTile: Color(0xFF00525A), // = OmniColors.dark.brandFill
    overviewTileYesterday: Color(0xFF2F558F), // = OmniColors.dark.segmentOn
  );
}
