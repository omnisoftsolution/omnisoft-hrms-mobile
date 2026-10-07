import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_hr/models/attendance_ask.dart';
import 'package:omni_hr/screens/home/my_day/declaration_sheet.dart';

const _title = 'Your shift started at 08:00. Forgot to check in?';
const _footnote = 'Your check-in stays at 09:12. HR will review your answer.';
final _day = DateTime(2026, 10, 7);

List<AskOption> _late() => [
  AskOption(
    code: 'started_at',
    label: 'I started at',
    needsTime: true,
    suggestedTime: DateTime(2026, 10, 7, 8).toUtc(),
  ),
  const AskOption(code: 'just_arriving', label: 'Just arriving'),
];

class _Result {
  bool done = false;
  DeclarationAnswer? answer;
}

Widget _host(
  _Result result, {
  List<AskOption>? options,
  DeclarationTimePicker? pickTime,
  GlobalKey<NavigatorState>? rootKey,
}) => MaterialApp(
  navigatorKey: rootKey,
  home: Navigator(
    onGenerateRoute: (_) => MaterialPageRoute(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async {
              result.answer = await showDeclarationSheet(
                context,
                title: _title,
                options: options ?? _late(),
                day: _day,
                footnote: _footnote,
                pickTime: pickTime,
              );
              result.done = true;
            },
            child: const Text('OPEN'),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}

Future<void> _send(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('declaration-send')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'shows the question, the options, the suggested time and the footnote',
    (tester) async {
      await tester.pumpWidget(_host(_Result()));
      await _open(tester);
      expect(find.text('Forgot something?'), findsOneWidget);
      expect(find.text(_title), findsOneWidget);
      expect(find.text('I started at'), findsOneWidget);
      expect(find.text('Just arriving'), findsOneWidget);
      expect(find.text('08:00'), findsOneWidget);
      expect(find.text(_footnote), findsOneWidget);
      expect(find.text('Send to HR'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
    },
  );

  testWidgets('Send returns the first option with its suggested time', (
    tester,
  ) async {
    final result = _Result();
    await tester.pumpWidget(_host(result));
    await _open(tester);
    await _send(tester);
    expect(result.done, isTrue);
    expect(result.answer?.code, 'started_at');
    expect(result.answer?.time, DateTime(2026, 10, 7, 8).toUtc());
    expect(result.answer?.note, '');
  });

  testWidgets('picking another option returns it without a time', (
    tester,
  ) async {
    final result = _Result();
    await tester.pumpWidget(_host(result));
    await _open(tester);
    await tester.tap(
      find.byKey(const ValueKey('declaration-option-just_arriving')),
    );
    await tester.pump();
    await _send(tester);
    expect(result.answer?.code, 'just_arriving');
    expect(result.answer?.time, isNull);
  });

  testWidgets('the time chip opens the picker and its value is returned', (
    tester,
  ) async {
    final result = _Result();
    TimeOfDay? shown;
    await tester.pumpWidget(
      _host(
        result,
        pickTime: (context, initial) async {
          shown = initial;
          return const TimeOfDay(hour: 7, minute: 45);
        },
      ),
    );
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('declaration-time-started_at')));
    await tester.pumpAndSettle();
    expect(shown, const TimeOfDay(hour: 8, minute: 0));
    expect(find.text('07:45'), findsOneWidget);
    await _send(tester);
    expect(result.answer?.time, DateTime(2026, 10, 7, 7, 45).toUtc());
  });

  testWidgets('the default picker is the Material time picker', (tester) async {
    final result = _Result();
    await tester.pumpWidget(_host(result));
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('declaration-time-started_at')));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await _send(tester);
    expect(result.answer?.time, DateTime(2026, 10, 7, 8).toUtc());
  });

  testWidgets('the note is trimmed and returned', (tester) async {
    final result = _Result();
    await tester.pumpWidget(_host(result));
    await _open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('declaration-note')),
      '  phone died  ',
    );
    await _send(tester);
    expect(result.answer?.note, 'phone died');
  });

  testWidgets('Skip returns null', (tester) async {
    final result = _Result();
    await tester.pumpWidget(_host(result));
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('declaration-skip')));
    await tester.pumpAndSettle();
    expect(result.done, isTrue);
    expect(result.answer, isNull);
  });

  testWidgets('no suggested time: Send waits until a time is picked', (
    tester,
  ) async {
    final result = _Result();
    await tester.pumpWidget(
      _host(
        result,
        options: const [
          AskOption(
            code: 'back_at',
            label: 'Back from break since',
            needsTime: true,
          ),
        ],
        pickTime: (context, initial) async =>
            const TimeOfDay(hour: 13, minute: 0),
      ),
    );
    await _open(tester);
    expect(find.text('Pick a time'), findsOneWidget);
    FilledButton send() => tester.widget<FilledButton>(
      find.byKey(const ValueKey('declaration-send')),
    );
    expect(send().onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('declaration-time-back_at')));
    await tester.pumpAndSettle();
    expect(send().onPressed, isNotNull);
    await _send(tester);
    expect(result.answer?.time, DateTime(2026, 10, 7, 13).toUtc());
  });

  testWidgets('choosing undo turns the button into Undo check-in', (
    tester,
  ) async {
    final result = _Result();
    await tester.pumpWidget(
      _host(
        result,
        options: const [
          AskOption(code: 'overtime', label: 'Yes, overtime'),
          AskOption(code: 'undo', label: 'No — undo this check-in'),
        ],
      ),
    );
    await _open(tester);
    expect(find.text('Send to HR'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('declaration-option-undo')));
    await tester.pump();
    expect(find.text('Undo check-in'), findsOneWidget);
    await _send(tester);
    expect(result.answer?.code, 'undo');
  });

  testWidgets('the sheet opens on the root navigator', (tester) async {
    final rootKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_host(_Result(), rootKey: rootKey));
    await _open(tester);
    final sheetContext = tester.element(find.byType(DeclarationSheet));
    expect(Navigator.of(sheetContext), same(rootKey.currentState));
  });
}
