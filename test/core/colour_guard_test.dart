import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Dark mode M5 guard: screens and widgets take their colours from the
/// theme (`context.omni`, or a palette that has a dark twin). A raw
/// `Color(0x…)` there would stay the same in dark mode, so it is only
/// allowed:
/// - in the palette files listed in [_palettes], which hold both themes;
/// - as the light side of a light/dark switch (`dark ? … : Color(…)`,
///   `isDarkTheme`), within five lines of it;
/// - in a light-only shadow (`BoxShadow`), which dark mode skips.
const _palettes = {'lib/screens/team/team_colors.dart'};

void main() {
  test('no raw hex colour in screens or widgets outside a dark switch', () {
    final offenders = <String>[];
    for (final dir in ['lib/screens', 'lib/widgets']) {
      final files = Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final file in files) {
        final path = file.path.replaceAll(r'\', '/');
        if (_palettes.contains(path)) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (!lines[i].contains('Color(0x')) continue;
          final context = lines
              .sublist(i < 5 ? 0 : i - 5, i + 1)
              .join('\n')
              .toLowerCase();
          if (context.contains('dark') || context.contains('boxshadow')) {
            continue;
          }
          offenders.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('the app follows the phone', () {
    final theme = File('lib/core/theme.dart').readAsStringSync();
    expect(theme, contains('themeMode = ThemeMode.system'));
  });
}
