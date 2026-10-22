import 'package:flutter/material.dart';

/// Which My day state a [MyDayTone] paints. Compare tones by [kind],
/// never by identity: the light and dark palettes hold different
/// instances for the same state.
enum MyDayToneKind { work, brk, leave, late, overtime, missing, waiting, holiday }

/// One semantic colour of My day (spec 2026-10-06 §4.1): the tile fill
/// (white text on it), the tint for chips and cells, the text on that
/// tint, and the dot / rail colour.
class MyDayTone {
  final MyDayToneKind kind;
  final Color fill;
  final Color tint;
  final Color onTint;
  final Color dot;

  const MyDayTone({
    required this.kind,
    required this.fill,
    required this.tint,
    required this.onTint,
    required this.dot,
  });

  static MyDayTone lerp(MyDayTone a, MyDayTone b, double t) => MyDayTone(
        kind: t < 0.5 ? a.kind : b.kind,
        fill: Color.lerp(a.fill, b.fill, t)!,
        tint: Color.lerp(a.tint, b.tint, t)!,
        onTint: Color.lerp(a.onTint, b.onTint, t)!,
        dot: Color.lerp(a.dot, b.dot, t)!,
      );
}

/// The eight My day tones for one brightness.
class MyDayPalette {
  final MyDayTone work;
  final MyDayTone brk;
  final MyDayTone leave;
  final MyDayTone late;
  final MyDayTone overtime;
  final MyDayTone missing;
  final MyDayTone waiting;
  final MyDayTone holiday;

  const MyDayPalette({
    required this.work,
    required this.brk,
    required this.leave,
    required this.late,
    required this.overtime,
    required this.missing,
    required this.waiting,
    required this.holiday,
  });

  MyDayTone of(MyDayToneKind kind) => switch (kind) {
        MyDayToneKind.work => work,
        MyDayToneKind.brk => brk,
        MyDayToneKind.leave => leave,
        MyDayToneKind.late => late,
        MyDayToneKind.overtime => overtime,
        MyDayToneKind.missing => missing,
        MyDayToneKind.waiting => waiting,
        MyDayToneKind.holiday => holiday,
      };

  List<MyDayTone> get all =>
      [work, brk, leave, late, overtime, missing, waiting, holiday];

  static MyDayPalette lerp(MyDayPalette a, MyDayPalette b, double t) =>
      MyDayPalette(
        work: MyDayTone.lerp(a.work, b.work, t),
        brk: MyDayTone.lerp(a.brk, b.brk, t),
        leave: MyDayTone.lerp(a.leave, b.leave, t),
        late: MyDayTone.lerp(a.late, b.late, t),
        overtime: MyDayTone.lerp(a.overtime, b.overtime, t),
        missing: MyDayTone.lerp(a.missing, b.missing, t),
        waiting: MyDayTone.lerp(a.waiting, b.waiting, t),
        holiday: MyDayTone.lerp(a.holiday, b.holiday, t),
      );

  // ---- Light (the app's colours up to 1.33.0) ---------------------------
  static const lightWork = MyDayTone(
    kind: MyDayToneKind.work,
    fill: Color(0xFF006971),
    tint: Color(0xFFDCEFF1),
    onTint: Color(0xFF004F55),
    dot: Color(0xFF006971),
  );
  static const lightBrk = MyDayTone(
    kind: MyDayToneKind.brk,
    fill: Color(0xFF1D477E),
    tint: Color(0xFFD6E3FF),
    onTint: Color(0xFF1D477E),
    dot: Color(0xFF395F97),
  );
  static const lightLeave = MyDayTone(
    kind: MyDayToneKind.leave,
    fill: Color(0xFF395F97),
    tint: Color(0xFFD6E3FF),
    onTint: Color(0xFF1D477E),
    dot: Color(0xFF395F97),
  );
  static const lightLate = MyDayTone(
    kind: MyDayToneKind.late,
    fill: Color(0xFF8A5A00),
    tint: Color(0xFFFFE4A8),
    onTint: Color(0xFF6B4400),
    dot: Color(0xFFD99A1C),
  );
  static const lightOvertime = MyDayTone(
    kind: MyDayToneKind.overtime,
    fill: Color(0xFF1B5E38),
    tint: Color(0xFFDDF3E4),
    onTint: Color(0xFF1B5E38),
    dot: Color(0xFF2E8B57),
  );
  static const lightMissing = MyDayTone(
    kind: MyDayToneKind.missing,
    fill: Color(0xFF93000A),
    tint: Color(0xFFFFDAD6),
    onTint: Color(0xFF93000A),
    dot: Color(0xFFBA1A1A),
  );
  static const lightWaiting = MyDayTone(
    kind: MyDayToneKind.waiting,
    fill: Color(0xFF516161),
    tint: Color(0xFFECEEF0),
    onTint: Color(0xFF55666A),
    dot: Color(0xFFBCC9CA),
  );
  static const lightHoliday = MyDayTone(
    kind: MyDayToneKind.holiday,
    fill: Color(0xFF3A4A49),
    tint: Color(0xFFE0E3E5),
    onTint: Color(0xFF3D494A),
    dot: Color(0xFF3D494A),
  );

  static const light = MyDayPalette(
    work: lightWork,
    brk: lightBrk,
    leave: lightLeave,
    late: lightLate,
    overtime: lightOvertime,
    missing: lightMissing,
    waiting: lightWaiting,
    holiday: lightHoliday,
  );

  // ---- Dark (canvas 2026-10-22; fills step down so tiles don't glow) ----
  static const dark = MyDayPalette(
    work: MyDayTone(
      kind: MyDayToneKind.work,
      fill: Color(0xFF00525A),
      tint: Color(0xFF0F3B3F),
      onTint: Color(0xFF9EF0F7),
      dot: Color(0xFF58D8E4),
    ),
    brk: MyDayTone(
      kind: MyDayToneKind.brk,
      fill: Color(0xFF1D477E),
      tint: Color(0xFF1F3557),
      onTint: Color(0xFFD6E3FF),
      dot: Color(0xFFA8C8FF),
    ),
    leave: MyDayTone(
      kind: MyDayToneKind.leave,
      fill: Color(0xFF2F558F),
      tint: Color(0xFF1F3557),
      onTint: Color(0xFFD6E3FF),
      dot: Color(0xFFA8C8FF),
    ),
    late: MyDayTone(
      kind: MyDayToneKind.late,
      fill: Color(0xFF6B4400),
      tint: Color(0xFF4A3A12),
      onTint: Color(0xFFFFE4A8),
      dot: Color(0xFFE8A93A),
    ),
    overtime: MyDayTone(
      kind: MyDayToneKind.overtime,
      fill: Color(0xFF1B5E38),
      tint: Color(0xFF173D27),
      onTint: Color(0xFFB7F0C9),
      dot: Color(0xFF5FC88A),
    ),
    missing: MyDayTone(
      kind: MyDayToneKind.missing,
      fill: Color(0xFF93000A),
      tint: Color(0xFF5C1A16),
      onTint: Color(0xFFFFDAD6),
      dot: Color(0xFFFF8A80),
    ),
    waiting: MyDayTone(
      kind: MyDayToneKind.waiting,
      fill: Color(0xFF3A4647),
      tint: Color(0xFF2A3334),
      onTint: Color(0xFFBFC8CA),
      dot: Color(0xFF6F7B7C),
    ),
    holiday: MyDayTone(
      kind: MyDayToneKind.holiday,
      fill: Color(0xFF33403F),
      tint: Color(0xFF2A3334),
      onTint: Color(0xFFC9D1D2),
      dot: Color(0xFF9AA5A6),
    ),
  );
}

/// Omni HR colour tokens for one brightness. Every screen reads its
/// colours from here (`context.omni`), never from hex literals, so the
/// app can follow the phone's light / dark setting.
///
/// Names describe the job, not the hue: `accent` is teal text and icons
/// on a card, `brandFill` is the teal behind white text (status tile,
/// "waiting for you" banner). Both are #006971 in light but split in
/// dark (#58D8E4 vs #00525A), so pick by job.
///
/// Canvas: https://claude.ai/artifact/DGNNsiweTNJ1fspz9uhyXG (Tokens board).
@immutable
class OmniColors extends ThemeExtension<OmniColors> {
  /// Page behind cards (scaffold).
  final Color background;
  /// Cards, inputs.
  final Color card;
  /// App bar and bottom navigation.
  final Color bar;
  /// Bottom sheets and dialogs.
  final Color sheet;
  /// Segment track, quiet chips.
  final Color soft;
  final Color text;
  final Color textSub;
  final Color textMuted;
  /// Outlines (inputs, segmented controls).
  final Color line;
  /// Hairline dividers.
  final Color lineSoft;
  /// Teal text and icons on a card.
  final Color accent;
  /// Approved chip, icon circles.
  final Color accentTint;
  final Color onAccentTint;
  /// Teal fill behind white text.
  final Color brandFill;
  final Color onBrandFill;
  /// Main call-to-action button.
  final Color button;
  final Color onButton;
  /// Focused input border and floating label.
  final Color focus;
  /// Blue text (pending, links).
  final Color secondary;
  /// Selected segment, white text on it.
  final Color segmentOn;
  final Color onSegmentOn;
  /// Waiting / pending chip.
  final Color pendingTint;
  final Color onPendingTint;
  final Color error;
  final Color errorTint;
  final Color onErrorTint;
  final Color success;
  final Color successTint;
  final Color warning;
  final Color warningTint;
  /// Count badges (bell, tabs).
  final Color badge;
  final Color onBadge;
  /// Active tab pill in the bottom navigation.
  final Color navIndicator;
  /// Button on a coloured tile (its text uses the tile's fill).
  final Color tilePill;
  /// Card elevation shadow colour (transparent in dark).
  final Color cardShadowColor;
  /// Soft ambient shadow for cards and inputs (empty in dark).
  final List<BoxShadow> cardShadow;
  /// Glow under the main button (empty in dark).
  final List<BoxShadow> buttonGlow;
  final MyDayPalette myDay;

  const OmniColors({
    required this.background,
    required this.card,
    required this.bar,
    required this.sheet,
    required this.soft,
    required this.text,
    required this.textSub,
    required this.textMuted,
    required this.line,
    required this.lineSoft,
    required this.accent,
    required this.accentTint,
    required this.onAccentTint,
    required this.brandFill,
    required this.onBrandFill,
    required this.button,
    required this.onButton,
    required this.focus,
    required this.secondary,
    required this.segmentOn,
    required this.onSegmentOn,
    required this.pendingTint,
    required this.onPendingTint,
    required this.error,
    required this.errorTint,
    required this.onErrorTint,
    required this.success,
    required this.successTint,
    required this.warning,
    required this.warningTint,
    required this.badge,
    required this.onBadge,
    required this.navIndicator,
    required this.tilePill,
    required this.cardShadowColor,
    required this.cardShadow,
    required this.buttonGlow,
    required this.myDay,
  });

  /// Today's light values (design.md), unchanged.
  static final OmniColors light = OmniColors(
    background: const Color(0xFFF7F9FB),
    card: const Color(0xFFFFFFFF),
    bar: const Color(0xFFFFFFFF),
    sheet: const Color(0xFFFFFFFF),
    soft: const Color(0xFFECEEF0),
    text: const Color(0xFF191C1E),
    textSub: const Color(0xFF3D494A),
    textMuted: const Color(0xFF6C797B),
    line: const Color(0xFFBCC9CA),
    lineSoft: const Color(0xFF6C797B).withValues(alpha: 0.12),
    accent: const Color(0xFF006971),
    accentTint: const Color(0xFFDCEFF1),
    onAccentTint: const Color(0xFF004F55),
    brandFill: const Color(0xFF006971),
    onBrandFill: const Color(0xFFFFFFFF),
    button: const Color(0xFF2BB8C4),
    onButton: const Color(0xFFFFFFFF),
    focus: const Color(0xFF2BB8C4),
    secondary: const Color(0xFF395F97),
    segmentOn: const Color(0xFF395F97),
    onSegmentOn: const Color(0xFFFFFFFF),
    pendingTint: const Color(0xFFD6E3FF),
    onPendingTint: const Color(0xFF1D477E),
    error: const Color(0xFFBA1A1A),
    errorTint: const Color(0xFFFFDAD6),
    onErrorTint: const Color(0xFF93000A),
    success: const Color(0xFF1B7F3B),
    successTint: const Color(0xFFDCF2E3),
    warning: const Color(0xFFB45309),
    warningTint: const Color(0xFFFEF3C7),
    badge: const Color(0xFFBA1A1A),
    onBadge: const Color(0xFFFFFFFF),
    navIndicator: const Color(0xFF2BB8C4).withValues(alpha: 0.18),
    tilePill: const Color(0xFFFFFFFF),
    cardShadowColor: const Color(0xFF395F97).withValues(alpha: 0.08),
    // DESIGN.md: 0px 4px 20px rgba(80, 117, 175, 0.08).
    cardShadow: [
      BoxShadow(
        color: const Color(0xFF5075AF).withValues(alpha: 0.08),
        blurRadius: 20,
        offset: const Offset(0, 4),
      ),
    ],
    // DESIGN.md: 0px 10px 30px rgba(43, 184, 196, 0.30).
    buttonGlow: [
      BoxShadow(
        color: const Color(0xFF2BB8C4).withValues(alpha: 0.30),
        blurRadius: 30,
        offset: const Offset(0, 10),
      ),
    ],
    myDay: MyDayPalette.light,
  );

  /// Dark values (canvas 2026-10-22, approved by Willy). Cards separate
  /// from the page by tone, so there are no shadows.
  static final OmniColors dark = OmniColors(
    background: const Color(0xFF0E1415),
    card: const Color(0xFF182022),
    bar: const Color(0xFF141B1C),
    sheet: const Color(0xFF1D2627),
    soft: const Color(0xFF222B2C),
    text: const Color(0xFFE1E3E3),
    textSub: const Color(0xFFBFC8CA),
    textMuted: const Color(0xFF8F9A9B),
    line: const Color(0xFF3A4647),
    lineSoft: const Color(0xFFFFFFFF).withValues(alpha: 0.08),
    accent: const Color(0xFF58D8E4),
    accentTint: const Color(0xFF0F3B3F),
    onAccentTint: const Color(0xFF9EF0F7),
    brandFill: const Color(0xFF00525A),
    onBrandFill: const Color(0xFFFFFFFF),
    button: const Color(0xFF58D8E4),
    onButton: const Color(0xFF00363B),
    focus: const Color(0xFF58D8E4),
    secondary: const Color(0xFFA8C8FF),
    segmentOn: const Color(0xFF2F558F),
    onSegmentOn: const Color(0xFFFFFFFF),
    pendingTint: const Color(0xFF1F3557),
    onPendingTint: const Color(0xFFD6E3FF),
    error: const Color(0xFFFFB4AB),
    errorTint: const Color(0xFF5C1A16),
    onErrorTint: const Color(0xFFFFDAD6),
    success: const Color(0xFF7FD89F),
    successTint: const Color(0xFF173D27),
    warning: const Color(0xFFFFD58A),
    warningTint: const Color(0xFF3D3012),
    badge: const Color(0xFFFFB4AB),
    onBadge: const Color(0xFF690005),
    navIndicator: const Color(0xFF58D8E4).withValues(alpha: 0.16),
    tilePill: const Color(0xFFE6F2F3),
    cardShadowColor: Colors.transparent,
    cardShadow: const [],
    buttonGlow: const [],
    myDay: MyDayPalette.dark,
  );

  @override
  OmniColors copyWith({
    Color? background,
    Color? card,
    Color? bar,
    Color? sheet,
    Color? soft,
    Color? text,
    Color? textSub,
    Color? textMuted,
    Color? line,
    Color? lineSoft,
    Color? accent,
    Color? accentTint,
    Color? onAccentTint,
    Color? brandFill,
    Color? onBrandFill,
    Color? button,
    Color? onButton,
    Color? focus,
    Color? secondary,
    Color? segmentOn,
    Color? onSegmentOn,
    Color? pendingTint,
    Color? onPendingTint,
    Color? error,
    Color? errorTint,
    Color? onErrorTint,
    Color? success,
    Color? successTint,
    Color? warning,
    Color? warningTint,
    Color? badge,
    Color? onBadge,
    Color? navIndicator,
    Color? tilePill,
    Color? cardShadowColor,
    List<BoxShadow>? cardShadow,
    List<BoxShadow>? buttonGlow,
    MyDayPalette? myDay,
  }) =>
      OmniColors(
        background: background ?? this.background,
        card: card ?? this.card,
        bar: bar ?? this.bar,
        sheet: sheet ?? this.sheet,
        soft: soft ?? this.soft,
        text: text ?? this.text,
        textSub: textSub ?? this.textSub,
        textMuted: textMuted ?? this.textMuted,
        line: line ?? this.line,
        lineSoft: lineSoft ?? this.lineSoft,
        accent: accent ?? this.accent,
        accentTint: accentTint ?? this.accentTint,
        onAccentTint: onAccentTint ?? this.onAccentTint,
        brandFill: brandFill ?? this.brandFill,
        onBrandFill: onBrandFill ?? this.onBrandFill,
        button: button ?? this.button,
        onButton: onButton ?? this.onButton,
        focus: focus ?? this.focus,
        secondary: secondary ?? this.secondary,
        segmentOn: segmentOn ?? this.segmentOn,
        onSegmentOn: onSegmentOn ?? this.onSegmentOn,
        pendingTint: pendingTint ?? this.pendingTint,
        onPendingTint: onPendingTint ?? this.onPendingTint,
        error: error ?? this.error,
        errorTint: errorTint ?? this.errorTint,
        onErrorTint: onErrorTint ?? this.onErrorTint,
        success: success ?? this.success,
        successTint: successTint ?? this.successTint,
        warning: warning ?? this.warning,
        warningTint: warningTint ?? this.warningTint,
        badge: badge ?? this.badge,
        onBadge: onBadge ?? this.onBadge,
        navIndicator: navIndicator ?? this.navIndicator,
        tilePill: tilePill ?? this.tilePill,
        cardShadowColor: cardShadowColor ?? this.cardShadowColor,
        cardShadow: cardShadow ?? this.cardShadow,
        buttonGlow: buttonGlow ?? this.buttonGlow,
        myDay: myDay ?? this.myDay,
      );

  @override
  OmniColors lerp(ThemeExtension<OmniColors>? other, double t) {
    if (other is! OmniColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return OmniColors(
      background: c(background, other.background),
      card: c(card, other.card),
      bar: c(bar, other.bar),
      sheet: c(sheet, other.sheet),
      soft: c(soft, other.soft),
      text: c(text, other.text),
      textSub: c(textSub, other.textSub),
      textMuted: c(textMuted, other.textMuted),
      line: c(line, other.line),
      lineSoft: c(lineSoft, other.lineSoft),
      accent: c(accent, other.accent),
      accentTint: c(accentTint, other.accentTint),
      onAccentTint: c(onAccentTint, other.onAccentTint),
      brandFill: c(brandFill, other.brandFill),
      onBrandFill: c(onBrandFill, other.onBrandFill),
      button: c(button, other.button),
      onButton: c(onButton, other.onButton),
      focus: c(focus, other.focus),
      secondary: c(secondary, other.secondary),
      segmentOn: c(segmentOn, other.segmentOn),
      onSegmentOn: c(onSegmentOn, other.onSegmentOn),
      pendingTint: c(pendingTint, other.pendingTint),
      onPendingTint: c(onPendingTint, other.onPendingTint),
      error: c(error, other.error),
      errorTint: c(errorTint, other.errorTint),
      onErrorTint: c(onErrorTint, other.onErrorTint),
      success: c(success, other.success),
      successTint: c(successTint, other.successTint),
      warning: c(warning, other.warning),
      warningTint: c(warningTint, other.warningTint),
      badge: c(badge, other.badge),
      onBadge: c(onBadge, other.onBadge),
      navIndicator: c(navIndicator, other.navIndicator),
      tilePill: c(tilePill, other.tilePill),
      cardShadowColor: c(cardShadowColor, other.cardShadowColor),
      cardShadow: BoxShadow.lerpList(cardShadow, other.cardShadow, t) ?? const [],
      buttonGlow: BoxShadow.lerpList(buttonGlow, other.buttonGlow, t) ?? const [],
      myDay: MyDayPalette.lerp(myDay, other.myDay, t),
    );
  }
}

extension OmniColorsContext on BuildContext {
  /// The Omni HR colour tokens for the current brightness.
  OmniColors get omni =>
      Theme.of(this).extension<OmniColors>() ?? OmniColors.light;
}
