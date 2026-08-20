import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';

/// Compact white card with an icon, label, primary value, and an
/// optional accented suffix. Used by the home screen's two-up row
/// (Current Time / GPS Status).
class InfoCard extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final String value;
  final String? suffix;
  final Color? suffixColor;
  final IconData? secondaryIcon;
  final Color? secondaryIconColor;

  const InfoCard({
    super.key,
    required this.icon,
    this.iconColor,
    required this.label,
    required this.value,
    this.suffix,
    this.suffixColor,
    this.secondaryIcon,
    this.secondaryIconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.glassShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: iconColor ?? AppTheme.primary),
              if (secondaryIcon != null) ...[
                const SizedBox(width: 8),
                Icon(secondaryIcon, size: 22,
                    color: secondaryIconColor ?? AppTheme.outline),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppTheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.onSurface,
                    height: 1.1,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (suffix != null && suffix!.isNotEmpty) ...[
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '· $suffix',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: suffixColor ?? AppTheme.outline,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
