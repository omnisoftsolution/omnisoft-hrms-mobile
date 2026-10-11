import 'package:flutter/material.dart';

/// Button label that turns into a small spinner and [busyLabel] while the
/// request behind the button runs. Use it for actions the server can take
/// several seconds to answer (an approval waits for Odoo to email the
/// followers), so the tap visibly registered. The spinner takes the
/// button's foreground colour.
class BusyButtonLabel extends StatelessWidget {
  const BusyButtonLabel({
    super.key,
    required this.busy,
    required this.label,
    required this.busyLabel,
  });

  final bool busy;
  final String label;
  final String busyLabel;

  @override
  Widget build(BuildContext context) {
    if (!busy) return Text(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: DefaultTextStyle.of(context).style.color,
          ),
        ),
        const SizedBox(width: 10),
        Text(busyLabel),
      ],
    );
  }
}
