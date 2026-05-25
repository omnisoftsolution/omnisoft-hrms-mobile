import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Omni HR design system — see DESIGN.md from the design source folder.
///
/// Color tokens map directly to Material 3 ColorScheme slots so
/// every Material widget picks up the right shade by default. The
/// AppBar / button / input / card themes are tuned to match the
/// reference: white surfaces, blue-tinted ambient shadows, lighter
/// `primaryContainer` (#2BB8C4) for the call-to-action button.
class AppTheme {
  // ---- Color tokens (from design.md) -----------------------------------
  static const Color primary = Color(0xFF006971);
  static const Color onPrimary = Color(0xFFFFFFFF);
  /// Lighter teal used for the primary call-to-action and focus accents.
  static const Color primaryContainer = Color(0xFF2BB8C4);
  static const Color onPrimaryContainer = Color(0xFF004449);
  static const Color secondary = Color(0xFF395F97);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF7F9FB);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF191C1E);
  static const Color onSurfaceVariant = Color(0xFF3D494A);
  static const Color error = Color(0xFFBA1A1A);
  static const Color outline = Color(0xFF6C797B);
  static const Color outlineVariant = Color(0xFFBCC9CA);
  static const Color surfaceContainer = Color(0xFFECEEF0);
  static const Color inversePrimary = Color(0xFF58D8E4);

  /// Soft blue-tinted ambient shadow used by cards and inputs.
  /// Per DESIGN.md: 0px 4px 20px rgba(80, 117, 175, 0.08).
  static List<BoxShadow> get glassShadow => [
        BoxShadow(
          color: const Color(0xFF5075AF).withValues(alpha: 0.08),
          blurRadius: 20,
          offset: const Offset(0, 4),
        ),
      ];

  /// Stronger glow used by the primary CTA button.
  /// Per DESIGN.md: 0px 10px 30px rgba(43, 184, 196, 0.30).
  static List<BoxShadow> get primaryGlow => [
        BoxShadow(
          color: primaryContainer.withValues(alpha: 0.30),
          blurRadius: 30,
          offset: const Offset(0, 10),
        ),
      ];

  /// Dark status-bar icons on the now-white AppBar.
  static const SystemUiOverlayStyle _statusBarStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark, // Android
    statusBarBrightness: Brightness.light,    // iOS
  );

  static ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        secondary: secondary,
        onSecondary: onSecondary,
        surface: surface,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        error: error,
        outline: outline,
        outlineVariant: outlineVariant,
      ),
      scaffoldBackgroundColor: surface,
    );

    final inter = GoogleFonts.interTextTheme(base.textTheme);

    return base.copyWith(
      textTheme: inter.copyWith(
        // Tighter, heavier display variants per design tokens.
        displaySmall: inter.displaySmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: onSurface,
        ),
        headlineLarge: inter.headlineLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: onSurface,
        ),
        headlineMedium: inter.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: onSurface,
        ),
        titleLarge: inter.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: onSurface,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceContainerLowest,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        systemOverlayStyle: _statusBarStyle,
        iconTheme: const IconThemeData(color: onSurfaceVariant, size: 22),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: onSurface,
          letterSpacing: -0.2,
        ),
        shape: Border(
          bottom: BorderSide(
            color: outline.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shadowColor: secondary.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        color: surfaceContainerLowest,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryContainer,
          foregroundColor: onPrimary,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
          // We render our own glow via the PrimaryButton widget; keep
          // Material's elevated button shadow off here so we don't get
          // double-shadow stacking.
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          side: const BorderSide(color: primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryContainer,
          foregroundColor: onPrimary,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryContainer, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        prefixIconColor: onSurfaceVariant,
        suffixIconColor: onSurfaceVariant,
        labelStyle: GoogleFonts.inter(
          fontSize: 14,
          color: onSurfaceVariant,
        ),
        floatingLabelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: primaryContainer,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceContainerLowest,
        selectedItemColor: primary,
        unselectedItemColor: outline,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: outline.withValues(alpha: 0.12),
        thickness: 1,
        space: 1,
      ),
    );
  }
}
