// The popover's content background.
//
// A popover draws its own frame and material, so `DialogView` skips the card.
// A script that sets `bg_color` still gets that colour painted behind the
// whole content, and its text follows the colour's brightness. Without an
// explicit colour the content stays transparent.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin/app/windows/dialog_window.dart';
import 'package:taskpin/features/dialogs/dialog_action.dart';
import 'package:taskpin/features/dialogs/dialog_spec.dart';
import 'package:taskpin/features/dialogs/window_channel.dart';
import 'package:taskpin_design/taskpin_design.dart';

DialogSpec _spec({String bgColor = '', bool transparent = false}) =>
    DialogSpec.fromJson(<String, dynamic>{
      'title': 'Fill',
      'width': 360,
      'height': 240,
      'bg_color': bgColor,
      'transparent_bg': transparent ? 1 : 0,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'value': 'Row 0'},
      ],
    });

/// Pumps the popover host over a light system appearance, which is what the
/// NSPopover uses when the user runs in light mode.
Future<void> _pumpPopover(WidgetTester tester, DialogSpec spec) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TaskPinTheme.light().toThemeData(),
      themeMode: ThemeMode.light,
      home: Center(
        child: SizedBox(
          width: 360,
          height: 240,
          child: DialogWindowScaffold(
            spec: spec,
            windowApi: const NoopDialogWindowApi(),
            actions: RecordingDialogActionRunner(),
            hostDrawsSurface: true,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// The card `DialogView` paints on a window: a bordered box with the overlay
/// radius. The popover path must not paint one.
Finder _cardFinder() => find.byWidgetPredicate(
      (Widget w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).border != null &&
          (w.decoration as BoxDecoration).borderRadius == TpRadius.overlay,
    );

/// Every colour a `ColoredBox` paints in the tree.
List<Color> _paintedColors(WidgetTester tester) => <Color>[
      for (final ColoredBox box in tester.widgetList<ColoredBox>(find.byType(ColoredBox)))
        box.color,
    ];

void main() {
  testWidgets('popover mode: an explicit bg_color paints the whole content', (
    WidgetTester tester,
  ) async {
    await _pumpPopover(tester, _spec(bgColor: 'FF0000'));

    expect(_paintedColors(tester), contains(const Color(0xFFFF0000)));
    // The popover clips the corners, so the content carries no border of ours.
    expect(_cardFinder(), findsNothing);
  });

  testWidgets('popover mode: no bg_color leaves the content transparent', (
    WidgetTester tester,
  ) async {
    await _pumpPopover(tester, _spec());

    // Neither the flyout card nor the window colour is painted behind content.
    expect(_paintedColors(tester), isNot(contains(TaskPinTheme.light().bg.flyout)));
    expect(_paintedColors(tester), isNot(contains(TaskPinTheme.light().bg.window)));
    expect(_cardFinder(), findsNothing);
  });

  testWidgets('popover mode: transparent_bg wins over bg_color', (
    WidgetTester tester,
  ) async {
    await _pumpPopover(tester, _spec(bgColor: 'FF0000', transparent: true));

    expect(_paintedColors(tester), isNot(contains(const Color(0xFFFF0000))));
  });

  testWidgets('popover mode: a dark fill gets light text on a light system', (
    WidgetTester tester,
  ) async {
    await _pumpPopover(tester, _spec(bgColor: '101010'));

    final Text row = tester.widget<Text>(find.text('Row 0'));
    expect(row.style?.color, TaskPinTheme.dark().text.primary);
  });

  testWidgets('popover mode: a light fill keeps dark text on a light system', (
    WidgetTester tester,
  ) async {
    await _pumpPopover(tester, _spec(bgColor: 'F5F5F5'));

    final Text row = tester.widget<Text>(find.text('Row 0'));
    expect(row.style?.color, TaskPinTheme.light().text.primary);
  });
}
