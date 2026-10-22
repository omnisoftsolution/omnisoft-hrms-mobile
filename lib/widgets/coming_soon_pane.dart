import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/omni_colors.dart';

/// Shown for features the user's subscription enables but we haven't
/// shipped yet. Sibling to FeatureLockedPane — same chrome, different
/// tone (excited rather than restrictive).
class ComingSoonPane extends StatelessWidget {
  final String featureName;
  final String? subtitle;

  const ComingSoonPane({
    super.key,
    required this.featureName,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.omni;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.button.withValues(alpha: 0.12),
              border: Border.all(
                color: c.button.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            child: Icon(
              Icons.engineering_rounded,
              size: 36,
              color: c.accent,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '$featureName coming soon',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: c.text,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle ??
                'Your subscription includes $featureName. We\'re still '
                    'building this feature for the mobile app — it will '
                    'appear here once it\'s ready.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: c.textSub,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
