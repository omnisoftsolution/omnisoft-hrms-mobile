import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme.dart';
import '../models/announcement_record.dart';

/// Bottom-sheet detail for one announcement. For an unacked direct
/// message the acknowledgement fires as soon as the sheet opens —
/// seeing the message IS the receipt.
Future<void> showAnnouncementDetailSheet(
  BuildContext context, {
  required AnnouncementRecord announcement,
  required Future<void> Function() onAck,
  Future<String?> Function()? loadImage,
}) {
  if (announcement.isDirect && !announcement.acked) {
    // Fire-and-forget; failure just means the receipt lands on a
    // later open or the kiosk.
    onAck().catchError((_) {});
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
          left: 24, right: 24, top: 20,
          bottom: 24 + MediaQuery.of(ctx).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            announcement.isDirect
                ? 'MESSAGE FROM HR'
                : 'ANNOUNCEMENT · HR',
            style: GoogleFonts.inter(fontSize: 11, letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: announcement.isUrgent
                    ? AppTheme.error
                    : AppTheme.primary),
          ),
          const SizedBox(height: 8),
          Text(announcement.name,
              style: GoogleFonts.inter(fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.onSurface)),
          if (announcement.hasImage && loadImage != null) ...[
            const SizedBox(height: 12),
            FutureBuilder<String?>(
              future: loadImage(),
              builder: (_, snap) {
                final b64 = snap.data;
                if (b64 == null || b64.isEmpty) {
                  return const SizedBox.shrink();
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(base64Decode(b64),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink()),
                );
              },
            ),
          ],
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Text(announcement.body,
                  style: GoogleFonts.inter(fontSize: 15, height: 1.55,
                      color: AppTheme.onSurfaceVariant)),
            ),
          ),
        ],
      ),
    ),
  );
}
