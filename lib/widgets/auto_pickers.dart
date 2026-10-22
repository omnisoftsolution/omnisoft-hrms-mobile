import 'package:flutter/material.dart';
import '../core/omni_colors.dart';

/// Calendar date picker that auto-pops on selection (no OK button).
Future<DateTime?> showAutoDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
  String? Function(DateTime)? holidayName,
  bool Function(DateTime)? isNonWorkingDay,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: _AutoDatePickerBody(
          initialDate: initialDate,
          firstDate: firstDate,
          lastDate: lastDate,
          helpText: helpText,
          holidayName: holidayName,
          isNonWorkingDay: isNonWorkingDay,
        ),
      ),
    ),
  );
}

class _AutoDatePickerBody extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String? helpText;
  final String? Function(DateTime)? holidayName;
  final bool Function(DateTime)? isNonWorkingDay;

  const _AutoDatePickerBody({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    this.helpText,
    this.holidayName,
    this.isNonWorkingDay,
  });

  @override
  State<_AutoDatePickerBody> createState() => _AutoDatePickerBodyState();
}

class _AutoDatePickerBodyState extends State<_AutoDatePickerBody> {
  late DateTime _focused;

  @override
  void initState() {
    super.initState();
    _focused = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.holidayName;
    final focusedHoliday = f?.call(_focused);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.helpText != null)
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(widget.helpText!,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        CalendarDatePicker(
          initialDate: widget.initialDate,
          firstDate: widget.firstDate,
          lastDate: widget.lastDate,
          onDateChanged: (d) {
            setState(() => _focused = d);
            final navigator = Navigator.of(context);
            // Pop on a microtask so the user briefly sees their selection.
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) navigator.pop(d);
            });
          },
        ),
        if (focusedHoliday != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.omni.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_busy, size: 16, color: context.omni.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Public holiday: $focusedHoliday',
                      style: TextStyle(
                          fontSize: 12, color: context.omni.error),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
