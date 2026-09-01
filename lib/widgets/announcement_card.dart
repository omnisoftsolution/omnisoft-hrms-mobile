import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme.dart';
import '../models/announcement_record.dart';

/// Notice-board card shown at the top of the home screen. Hidden by
/// the caller when there is nothing to show.
class AnnouncementCard extends StatelessWidget {
  final AnnouncementRecord announcement;
  final int totalCount;
  final VoidCallback onTap;

  const AnnouncementCard({
    super.key,
    required this.announcement,
    required this.totalCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final a = announcement;
    final spine = a.isUrgent ? AppTheme.error : AppTheme.primary;
    final unread = a.isDirect && !a.acked;
    return GestureDetector(
      key: const Key('announcement-card'),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 16),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppTheme.glassShadow,
          border: unread
              ? Border.all(
                  color: AppTheme.primaryContainer
                      .withValues(alpha: 0.4),
                  width: 1.5)
              : null,
        ),
        child: Stack(children: [
          Positioned(left: 0, top: 0, bottom: 0,
              child: Container(width: 5, color: spine)),
          Padding(
            padding: const EdgeInsets.fromLTRB(21, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      a.isDirect
                          ? 'MESSAGE FROM HR'
                          : 'ANNOUNCEMENT · HR',
                      style: GoogleFonts.inter(fontSize: 10.5,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                          color: a.isUrgent
                              ? AppTheme.error
                              : AppTheme.primary),
                    ),
                  ),
                  if (totalCount > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('+${totalCount - 1} more',
                          style: GoogleFonts.inter(fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.onSurfaceVariant)),
                    ),
                ]),
                const SizedBox(height: 4),
                Text(a.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.onSurface)),
                const SizedBox(height: 2),
                Text(a.body,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 13, height: 1.4,
                        color: AppTheme.onSurfaceVariant)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
