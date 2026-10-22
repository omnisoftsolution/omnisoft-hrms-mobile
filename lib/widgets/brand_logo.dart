import 'package:flutter/material.dart';
import '../core/omni_colors.dart';

/// Omnisoft "S" logo rendered inside a white squircle with a soft
/// blue-tinted shadow ("glass shadow"). Used on the login,
/// company-code, and welcome screens.
class BrandLogo extends StatelessWidget {
  final double size;
  final double cornerRadius;

  const BrandLogo({super.key, this.size = 96, this.cornerRadius = 28});

  /// Compact 32x32 version for AppBar leading icons.
  const BrandLogo.small({super.key})
      : size = 32,
        cornerRadius = 10;

  /// Default 96x96 hero version for branding screens.
  const BrandLogo.large({super.key})
      : size = 96,
        cornerRadius = 28;

  @override
  Widget build(BuildContext context) {
    // Tight padding — the source PNG already has its own breathing
    // room around the glyph, so we don't need to add much more.
    final padding = size * 0.06;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // The brand chip stays white in dark too (like the app icon).
        color: Colors.white,
        borderRadius: BorderRadius.circular(cornerRadius),
        boxShadow: context.omni.cardShadow,
      ),
      padding: EdgeInsets.all(padding),
      child: Image.asset(
        'assets/images/omnisoft_logo.png',
        fit: BoxFit.contain,
        // Cache at the rendered pixel size so big retinas don't decode
        // the full file every frame.
        cacheWidth: (size * 3).round(),
      ),
    );
  }
}
