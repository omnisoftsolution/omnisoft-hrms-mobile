import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../home/my_day/my_day_colors.dart';
import 'team_format.dart';

/// Colours of the team screens (Team leave outlook, Team overview), copied
/// from the light palettes of the mockups `TeamLeave.dc.html` (`c`) and
/// `Overview.dc.html` (`BUCKETS`). This is the only team file that holds
/// hex values, so the later dark-mode pass changes one place.
class TeamColors {
  TeamColors._();

  // ---- Heat map (TeamLeave.dc.html `c`) --------------------------------
  /// A working day nobody is off.
  static const cell0 = Color(0xFFE6E8EA);

  /// A day nobody in the set works (mockup `cellW`).
  static const cellOff = Color(0xFFF2F4F6);

  /// One, two, three or more people off.
  static const c1 = Color(0xFFC9DAF8);
  static const c2 = Color(0xFF8FB0E3);
  static const c3 = Color(0xFF395F97);

  /// Text on [c3].
  static const onC3 = Color(0xFFFFFFFF);

  /// Public holiday (legend swatch colour).
  static const hol = Color(0xFF9AA5A6);

  /// A public-holiday cell: [hol] at the mockup's `88` alpha.
  static const holCell = Color(0x889AA5A6);

  /// The dot on a day that is a public holiday for some people only.
  static const holDot = Color(0xFFB3261E);

  // ---- Leave tones ------------------------------------------------------
  static const leave = Color(0xFF395F97);
  static const leaveTint = Color(0xFFD6E3FF);
  static const leaveOn = Color(0xFF1D477E);

  // ---- Accent and text --------------------------------------------------
  static const accent = AppTheme.primary;
  static const accentTint = Color(0xFFDCEFF1);
  static const onAccentTint = Color(0xFF004F55);

  /// Secondary text (mockup `muted`).
  static const muted = Color(0xFF5F6C6E);

  /// Loading placeholders (mockup `skel`).
  static const skeleton = Color(0xFFE6E8EA);

  /// Unselected filter chip border (mockup `line2`).
  static const chipBorder = AppTheme.outlineVariant;

  /// Heat-map shade for [off] people off on a working day.
  static Color shade(int off) {
    if (off <= 0) return cell0;
    if (off == 1) return c1;
    if (off == 2) return c2;
    return c3;
  }

  /// Initials-avatar fill (A-L6): `hsl(id * 47 % 360, 55%, 45%)`, the
  /// same colour as [initialsHue].
  static Color avatar(int id) => initialsHue(id);

  // ---- Team overview buckets (Overview.dc.html `BUCKETS`) ---------------
  // fill = the bar segment on the overview tile, tint / onTint = the chip,
  // dot = the count tile's dot.
  static const onTime = MyDayTone(
    fill: Color(0xFFFFFFFF),
    tint: Color(0xFFDCEFF1),
    onTint: Color(0xFF004F55),
    dot: Color(0xFF006971),
  );
  static const late = MyDayTone(
    fill: Color(0xFFFFD58A),
    tint: Color(0xFFFFE4A8),
    onTint: Color(0xFF6B4400),
    dot: Color(0xFFD99A1C),
  );
  static const notInYet = MyDayTone(
    fill: Color(0x73FFFFFF),
    tint: Color(0xFFECEEF0),
    onTint: Color(0xFF55666A),
    dot: Color(0xFF6C797B),
  );
  static const noCheckIn = MyDayTone(
    fill: Color(0xFFFFB4AB),
    tint: Color(0xFFFFDAD6),
    onTint: Color(0xFF93000A),
    dot: Color(0xFFBA1A1A),
  );
  static const onLeave = MyDayTone(
    fill: Color(0xFFA8C8FF),
    tint: Color(0xFFD6E3FF),
    onTint: Color(0xFF1D477E),
    dot: Color(0xFF395F97),
  );
  static const offToday = MyDayTone(
    fill: Color(0x33FFFFFF),
    tint: Color(0xFFE0E3E5),
    onTint: Color(0xFF3D494A),
    dot: Color(0xFF9AA5A6),
  );

  /// The overview tile: today (live) and yesterday (reviewed).
  static const overviewTile = AppTheme.primary;
  static const overviewTileYesterday = AppTheme.secondary;

  // ---- On the overview tiles (Overview.dc.html white overlays) ---------
  // Text, icons and lines drawn on [overviewTile] / [overviewTileYesterday].
  // New widgets never write Colors.white (A-L19): the dark pass changes
  // these names only.
  /// Headline text and icons on a tile.
  static const onTile = Color(0xFFFFFFFF);

  /// Secondary text on a tile (white at 0.9).
  static const onTileSoft = Color(0xE6FFFFFF);

  /// The quietest text on a tile: the live line, the reviewed copy (0.85).
  static const onTileFaint = Color(0xD9FFFFFF);

  /// The divider on a tile (white at 0.22).
  static const tileLine = Color(0x38FFFFFF);

  /// The bar's empty track on a tile (white at 0.14).
  static const tileTrack = Color(0x24FFFFFF);

  /// The icon badge behind the tile's group icon (white at 0.18).
  static const tileBadge = Color(0x2EFFFFFF);

  /// Tone of an overview bucket key (`on_time`, `late`, `not_in_yet`,
  /// `no_check_in`, `on_leave`, `off_today`); unknown keys read as off.
  static MyDayTone bucket(String key) => switch (key) {
    'on_time' => onTime,
    'late' => late,
    'not_in_yet' => notInYet,
    'no_check_in' => noCheckIn,
    'on_leave' => onLeave,
    _ => offToday,
  };
}
