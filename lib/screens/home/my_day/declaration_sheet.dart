import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../../../models/attendance_ask.dart';

/// Picks a time for an answer; tests replace it.
typedef DeclarationTimePicker =
    Future<TimeOfDay?> Function(BuildContext context, TimeOfDay initial);

/// Material's time picker in 24 h, en_US (spec 2026-10-07 §4.1).
Future<TimeOfDay?> pickDeclarationTime(
  BuildContext context,
  TimeOfDay initial,
) => showTimePicker(
  context: context,
  initialTime: initial,
  builder: (context, child) => Localizations.override(
    context: context,
    locale: const Locale('en', 'US'),
    child: MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
  ),
);

/// Opens the "Forgot something?" sheet on the root navigator: it covers
/// the bottom bar, like face capture. [day] is the local calendar day the
/// picked times belong to. Returns the answer, or null on Skip / dismiss.
Future<DeclarationAnswer?> showDeclarationSheet(
  BuildContext context, {
  required String title,
  required List<AskOption> options,
  required DateTime day,
  required String footnote,
  DeclarationTimePicker? pickTime,
}) => showModalBottomSheet<DeclarationAnswer>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => DeclarationSheet(
    title: title,
    options: options,
    day: day,
    footnote: footnote,
    pickTime: pickTime,
  ),
);

/// One question, one answer at a time, an optional note for HR. The punch
/// is already recorded; the footnote says so (spec D6).
class DeclarationSheet extends StatefulWidget {
  const DeclarationSheet({
    super.key,
    required this.title,
    required this.options,
    required this.day,
    required this.footnote,
    this.pickTime,
  });

  final String title;
  final List<AskOption> options;
  final DateTime day;
  final String footnote;
  final DeclarationTimePicker? pickTime;

  @override
  State<DeclarationSheet> createState() => _DeclarationSheetState();
}

class _DeclarationSheetState extends State<DeclarationSheet> {
  late String _selected = widget.options.isEmpty
      ? ''
      : widget.options.first.code;
  final _times = <String, TimeOfDay>{};
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final option in widget.options) {
      final suggested = option.suggestedTime;
      if (option.needsTime && suggested != null) {
        _times[option.code] = TimeOfDay.fromDateTime(suggested.toLocal());
      }
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  AskOption? get _option =>
      widget.options.where((o) => o.code == _selected).firstOrNull;

  bool get _ready {
    final option = _option;
    return option != null && (!option.needsTime || _times[option.code] != null);
  }

  static String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pick(AskOption option) async {
    setState(() => _selected = option.code);
    final picker = widget.pickTime ?? pickDeclarationTime;
    final picked = await picker(
      context,
      _times[option.code] ?? TimeOfDay.now(),
    );
    if (!mounted || picked == null) return;
    setState(() => _times[option.code] = picked);
  }

  void _send() {
    final option = _option;
    if (option == null || !_ready) return;
    final t = _times[option.code];
    final day = widget.day.toLocal();
    Navigator.of(context).pop(
      DeclarationAnswer(
        code: option.code,
        time: option.needsTime && t != null
            ? DateTime(day.year, day.month, day.day, t.hour, t.minute).toUtc()
            : null,
        note: _note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final undo = _selected == 'undo';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Forgot something?',
                style: text.labelLarge?.copyWith(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.title,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              for (final option in widget.options)
                ListTile(
                  key: ValueKey('declaration-option-${option.code}'),
                  contentPadding: EdgeInsets.zero,
                  selected: option.code == _selected,
                  leading: Icon(
                    option.code == _selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(option.label),
                  trailing: option.needsTime
                      ? ActionChip(
                          key: ValueKey('declaration-time-${option.code}'),
                          avatar: const Icon(Icons.schedule, size: 18),
                          label: Text(
                            _times[option.code] == null
                                ? 'Pick a time'
                                : _hhmm(_times[option.code]!),
                          ),
                          onPressed: () => _pick(option),
                        )
                      : null,
                  onTap: () => setState(() => _selected = option.code),
                ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('declaration-note'),
                controller: _note,
                maxLines: 2,
                inputFormatters: [LengthLimitingTextInputFormatter(500)],
                decoration: const InputDecoration(
                  labelText: 'Note for HR (optional)',
                  hintText: 'e.g. My phone was out of battery',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    key: const ValueKey('declaration-skip'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Skip'),
                  ),
                  const Spacer(),
                  FilledButton(
                    key: const ValueKey('declaration-send'),
                    style: undo
                        ? FilledButton.styleFrom(
                            backgroundColor: AppTheme.error,
                          )
                        : null,
                    onPressed: _ready ? _send : null,
                    // Nothing reaches HR for these answers (review M3).
                    child: Text(
                      undo
                          ? 'Undo check-in'
                          : nothingToDeclare.contains(_selected)
                          ? 'Done'
                          : 'Send to HR',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.footnote,
                key: const ValueKey('declaration-footnote'),
                style: text.bodySmall?.copyWith(color: AppTheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
