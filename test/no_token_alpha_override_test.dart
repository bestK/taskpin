// Theme colours carry their own alpha (for example `bg.cardSecondary` is
// #08FFFFFF). `withValues(alpha:)`, `withOpacity` and `withAlpha` replace that
// alpha, so `bg.cardSecondary.withValues(alpha: 0.5)` becomes a 50% white block.
// Use the tokens as they are.
//
// This scans lib/ for a theme colour followed by one of those calls.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no TaskPinTheme colour has its alpha replaced', () {
    final RegExp pattern = RegExp(
      r'theme\.[a-zA-Z.]+\.with(Values\(alpha|Opacity|Alpha)',
    );

    final List<String> hits = <String>[];
    for (final FileSystemEntity f
        in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final List<String> lines = f.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) {
          hits.add('${f.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
