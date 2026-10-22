import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/omni_colors.dart';

/// Round avatar showing the employee's photo (base64 from
/// hr.employee.image_128) when available, else their initials, with
/// an optional green online dot.
class EmployeeAvatar extends StatelessWidget {
  final String? avatarB64;
  final String name;
  final double size;
  final bool online;

  const EmployeeAvatar({
    super.key,
    this.avatarB64,
    required this.name,
    this.size = 40,
    this.online = false,
  });

  /// Decode the base64 once. Returned `null` means the source is
  /// missing or invalid; the widget falls back to initials.
  Uint8List? get _imageBytes {
    final s = avatarB64;
    if (s == null || s.isEmpty) return null;
    try {
      return base64Decode(s);
    } catch (_) {
      return null;
    }
  }

  /// "Alex Lim" → "AL"; single word → first letter; empty → "?".
  String get _initials {
    final n = name.trim();
    if (n.isEmpty) return '?';
    final parts = n.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// Deterministic background color for the no-image fallback. Same
  /// name → same color across launches and devices, so the AppBar
  /// avatar and Profile hero match for the same user. FNV-1a is a
  /// stable, fast non-cryptographic hash; we map the result onto the
  /// HSL hue wheel and pick a fixed saturation/lightness that
  /// guarantees readable white text. Mirrors Odoo's own avatar
  /// fallback approach (avatar_mixin.get_hsl_from_seed).
  Color _fallbackBg(OmniColors c) {
    final n = name.trim();
    if (n.isEmpty) return c.brandFill;
    int hash = 0x811c9dc5;
    for (final c in n.codeUnits) {
      hash ^= c;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.55, 0.45).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _imageBytes;
    final hasImage = bytes != null;
    final c = context.omni;
    final core = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Solid hashed color for the initials fallback; pale teal
        // background only when an image is present (so the disc still
        // reads as a separate element against light card backgrounds).
        color: hasImage
            ? c.button.withValues(alpha: 0.15)
            : _fallbackBg(c),
        border: hasImage
            ? Border.all(
                color: c.button.withValues(alpha: 0.4),
                width: 1.5,
              )
            : null,
        image: hasImage
            ? DecorationImage(
                image: MemoryImage(bytes),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: hasImage
          ? null
          : Center(
              child: Text(
                _initials,
                style: TextStyle(
                  fontSize: size * 0.36,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
    );
    if (!online) return core;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        core,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: size * 0.28,
            height: size * 0.28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF22C55E),
              border: Border.all(color: c.bar, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
