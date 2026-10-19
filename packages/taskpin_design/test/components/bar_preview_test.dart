// TpBarPreviewStrip never overflows.
//
// The compact strips inside project and market cards are 36 high with 6 px of
// vertical padding, leaving 24 for content. Two 11 px lines at height 1.25 need
// 27.5, which used to report a RenderFlex overflow. The strip now drops the
// second line when it does not fit and clamps a single line's height.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin_design/taskpin_design.dart';

const TpBarContent _twoLines = TpBarContent(
  spans: <TpBarSpan>[
    TpBarSpan(text: 'CPU 12%'),
    TpBarSpan(text: 'MEM 34%', newline: true),
  ],
);

const TpBarContent _oneLine = TpBarContent(
  spans: <TpBarSpan>[TpBarSpan(text: 'CPU 12%')],
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: MaterialApp(
        theme: TaskPinTheme.dark().toThemeData(),
        home: Scaffold(
          body: Center(child: SizedBox(width: 300, child: child)),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('two lines in a 36 high strip do not overflow', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const TpBarPreviewStrip(content: _twoLines, height: 36),
    );

    expect(tester.takeException(), isNull);
    // Only the first line fits; the second is dropped rather than squeezed.
    expect(find.text('CPU 12%'), findsOneWidget);
    expect(find.text('MEM 34%'), findsNothing);
  });

  testWidgets('two lines still render at the full bar height', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const TpBarPreviewStrip(content: _twoLines, height: 56),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('CPU 12%'), findsOneWidget);
    expect(find.text('MEM 34%'), findsOneWidget);
  });

  testWidgets('a single line does not overflow at 150 % text scaling', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const TpBarPreviewStrip(content: _oneLine, height: 36),
      textScale: 1.5,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('CPU 12%'), findsOneWidget);
  });

  testWidgets('a long line is clipped, not reported as an overflow', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const TpBarPreviewStrip(
        content: TpBarContent(
          spans: <TpBarSpan>[
            TpBarSpan(
              text: 'a very long reading that is wider than the strip itself',
            ),
          ],
        ),
        height: 36,
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
