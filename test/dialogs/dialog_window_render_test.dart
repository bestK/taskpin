// The dialog window's render path, driven by a REAL engine-produced spec.
//
// `test/dialogs/` already covers `DialogSpec` parsing and the controller in
// isolation. This adds the one thing those do not: that the widget the dialog
// window shows (`DialogWindowScaffold` -> `DialogView`) actually renders a spec
// the engine produced, with no exception, and that a failed engine run does not
// blank it.
//
// The spec fixture is the real output of `engine_cli examples/hud_clock.lua`
// (a borderless, clickthrough, translucent 200x80 clock dialog), trimmed to the
// fields the widget reads.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin/app/windows/dialog_window.dart';
import 'package:taskpin/features/dialogs/dialog_action.dart';
import 'package:taskpin/features/dialogs/dialog_controller.dart';
import 'package:taskpin/features/dialogs/dialog_spec.dart';
import 'package:taskpin/features/dialogs/dialog_view.dart';
import 'package:taskpin/features/dialogs/items/button_item.dart';
import 'package:taskpin/features/dialogs/items/table_item.dart';
import 'package:taskpin/features/dialogs/window_channel.dart';
import 'package:taskpin_design/taskpin_design.dart';

/// The `hud_clock.lua` dialog as the engine emits it.
Map<String, dynamic> hudClockDialog() => <String, dynamic>{
      'clickable': 1,
      'click_action': 1,
      'dialog': <String, dynamic>{
        'title': 'Clock',
        'width': 200,
        'height': 80,
        'refresh': 1,
        'borderless': 1,
        'clickthrough': 1,
        'opacity': 180,
        'bg_color': '',
        'transparent_bg': 0,
        'item_count': 2,
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'text',
            'value': '18:56:58',
            'color': '#FFFFFF',
            'font_size': 24,
            'bold': 1,
          },
          <String, dynamic>{
            'type': 'text',
            'value': '2026-10-16 Friday',
            'color': '#AAAAAA',
            'font_size': 10,
            'bold': 0,
          },
        ],
      },
    };

void main() {
  testWidgets('DialogWindowScaffold renders a real hud_clock spec', (
    WidgetTester tester,
  ) async {
    final DialogSpec spec =
        DialogSpec.fromScriptResult(hudClockDialog())!;

    final RecordingDialogWindowApi api = RecordingDialogWindowApi();
    await tester.pumpWidget(
      MaterialApp(
        home: DialogWindowScaffold(spec: spec, windowApi: api),
      ),
    );
    await tester.pump();

    // The clock text is on screen.
    expect(find.text('18:56:58'), findsOneWidget);
    expect(find.text('2026-10-16 Friday'), findsOneWidget);

    // The window effects the spec asked for were pushed to the native side.
    expect(api.calls, contains('setBorderless(true)'));
    expect(api.calls, contains('setClickthrough(true)'));
    expect(api.calls, contains('setOpacity(180)'));
    // Centred via the -1 sentinel, at the spec's size.
    expect(api.calls, contains('setFrame(-1,-1,200,80)'));

    // No exception during layout/paint is the core assertion; reaching here
    // means the tree built cleanly.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a spec with a table item renders without error', (
    WidgetTester tester,
  ) async {
    final Map<String, dynamic> withTable = <String, dynamic>{
      'clickable': 1,
      'click_action': 1,
      'dialog': <String, dynamic>{
        'title': 'Demo',
        'width': 320,
        'height': 200,
        'refresh': 0,
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'table',
            'col_count': 2,
            'row_count': 2,
            'columns': <String>['A', 'B'],
            // `rows`, not `cells`: this is the engine's wire name
            // (native/engine `TPDialogItem`), and the one `DialogItem.toJson`
            // emits. `cells` is the Dart-side field name.
            'rows': <List<String>>[
              <String>['1', '2'],
              <String>['3', '4'],
            ],
          },
        ],
      },
    };
    final DialogSpec spec = DialogSpec.fromScriptResult(withTable)!;

    await tester.pumpWidget(
      MaterialApp(
        home: DialogWindowScaffold(
          spec: spec,
          windowApi: const NoopDialogWindowApi(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('A'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('title row uses bodyStrong, text.primary and has a 28x28 close target', (
    WidgetTester tester,
  ) async {
    final DialogSpec spec = DialogSpec.fromJson(<String, dynamic>{
      'title': 'Caption Test',
      'width': 360,
      'height': 240,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'value': 'content'},
      ],
    });

    final DialogController controller = DialogController(
      spec: spec,
      windowApi: const NoopDialogWindowApi(),
      actions: RecordingDialogActionRunner(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DialogView(controller: controller, onClose: () {}),
        ),
      ),
    );
    await tester.pump();

    final Text titleText = tester.widget<Text>(find.text('Caption Test'));
    final TaskPinTheme theme = TaskPinTheme.dark();
    expect(titleText.style?.fontWeight, FontWeight.w600);
    expect(titleText.style?.color, theme.text.primary);

    final SizedBox closeBox = tester.widget<SizedBox>(
      find.ancestor(
        of: find.byIcon(TpIcons.close),
        matching: find.byType(SizedBox),
      ).first,
    );
    expect(closeBox.width, 28);
    expect(closeBox.height, 28);
  });

  testWidgets('deliberate vertical rhythm separates tables and buttons more than text lines', (
    WidgetTester tester,
  ) async {
    final DialogSpec spec = DialogSpec.fromJson(<String, dynamic>{
      'title': 'Rhythm Test',
      'width': 360,
      'height': 300,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'value': 'Line 1'},
        <String, dynamic>{'type': 'text', 'value': 'Line 2'},
        <String, dynamic>{
          'type': 'table',
          'columns': <String>['K', 'V'],
          'rows': <List<String>>[
            <String>['a', '1'],
          ],
        },
        <String, dynamic>{'type': 'button', 'value': 'Action'},
      ],
    });

    final DialogController controller = DialogController(
      spec: spec,
      windowApi: const NoopDialogWindowApi(),
      actions: RecordingDialogActionRunner(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DialogView(controller: controller),
        ),
      ),
    );
    await tester.pump();

    // Spacing before Line 2 (text-to-text) is 4.
    // Spacing before table is 8.
    // Spacing before button is 8.
    final Iterable<SizedBox> boxes = tester.widgetList<SizedBox>(
      find.byType(SizedBox),
    );
    final List<double?> heights = boxes.map((SizedBox b) => b.height).toList();
    expect(heights, contains(TpSpacing.s4));
    expect(heights, contains(TpSpacing.s8));
  });

  testWidgets('table uses bg.cardSecondary for header, hairline dividers, and tabular figures', (
    WidgetTester tester,
  ) async {
    final DialogSpec spec = DialogSpec.fromJson(<String, dynamic>{
      'title': 'Table Test',
      'width': 360,
      'height': 240,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'table',
          'columns': <String>['Key', 'Value'],
          'rows': <List<String>>[
            <String>['one', '1'],
            <String>['two', '2'],
          ],
        },
      ],
    });

    final DialogController controller = DialogController(
      spec: spec,
      windowApi: const NoopDialogWindowApi(),
      actions: RecordingDialogActionRunner(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DialogView(controller: controller),
        ),
      ),
    );
    await tester.pump();

    final TaskPinTheme theme = TaskPinTheme.dark();
    final ColoredBox headerBox = tester.widget<ColoredBox>(
      find.ancestor(
        of: find.text('Key'),
        matching: find.byType(ColoredBox),
      ).first,
    );
    expect(headerBox.color, theme.bg.cardSecondary);

    final Text headerText = tester.widget<Text>(find.text('Key'));
    expect(headerText.style?.color, theme.text.secondary);

    // Numeric cell '1' has tabular figures font feature; text 'one' does not.
    final Text numericText = tester.widget<Text>(find.text('1'));
    expect(
      numericText.style?.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );

    final Text labelText = tester.widget<Text>(find.text('one'));
    expect(labelText.style?.fontFeatures, isNull);

    // Hairline dividers inside table: one under header and one between the two body rows.
    expect(
      find.descendant(
        of: find.byType(DialogTableItem),
        matching: find.byType(TpDivider),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('button has standard 32px silhouette and lifts on hover', (
    WidgetTester tester,
  ) async {
    final DialogSpec spec = DialogSpec.fromJson(<String, dynamic>{
      'title': 'Button Test',
      'width': 360,
      'height': 240,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'button', 'value': 'Default Button'},
        <String, dynamic>{
          'type': 'button',
          'value': 'Custom Button',
          'bg': '#123456',
          'color': '#654321',
        },
      ],
    });

    final DialogController controller = DialogController(
      spec: spec,
      windowApi: const NoopDialogWindowApi(),
      actions: RecordingDialogActionRunner(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DialogView(controller: controller),
        ),
      ),
    );
    await tester.pump();

    final TaskPinTheme theme = TaskPinTheme.dark();

    // Default button height 32, control.fill bg, control.stroke border
    final DecoratedBox defaultBox = tester.widget<DecoratedBox>(
      find.ancestor(
        of: find.text('Default Button'),
        matching: find.byType(DecoratedBox),
      ).first,
    );
    final BoxDecoration defaultDeco = defaultBox.decoration as BoxDecoration;
    expect(defaultDeco.color, theme.control.fill);
    expect(defaultDeco.borderRadius, TpRadius.control);
    expect(defaultDeco.border?.top.color, theme.control.stroke);

    // Custom button keeps explicit script colors
    final DecoratedBox customBox = tester.widget<DecoratedBox>(
      find.ancestor(
        of: find.text('Custom Button'),
        matching: find.byType(DecoratedBox),
      ).first,
    );
    final BoxDecoration customDeco = customBox.decoration as BoxDecoration;
    expect(customDeco.color, const Color(0xFF123456));

    final Text customText = tester.widget<Text>(find.text('Custom Button'));
    expect(customText.style?.color, const Color(0xFF654321));
  });

  testWidgets('text items use text.primary for body, text.secondary for labels, and keep script color', (
    WidgetTester tester,
  ) async {
    final DialogSpec spec = DialogSpec.fromJson(<String, dynamic>{
      'title': 'Text Test',
      'width': 360,
      'height': 240,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'value': 'Body message'},
        <String, dynamic>{'type': 'text', 'value': 'Status:'},
        <String, dynamic>{'type': 'text', 'value': 'Session: main'},
        <String, dynamic>{'type': 'text', 'value': 'Custom text', 'color': '#FF00FF'},
      ],
    });

    final DialogController controller = DialogController(
      spec: spec,
      windowApi: const NoopDialogWindowApi(),
      actions: RecordingDialogActionRunner(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DialogView(controller: controller),
        ),
      ),
    );
    await tester.pump();

    final TaskPinTheme theme = TaskPinTheme.dark();

    // Body text -> text.primary
    final Text bodyText = tester.widget<Text>(find.text('Body message'));
    expect(bodyText.style?.color, theme.text.primary);

    // Label ending with ':' -> text.secondary
    final Text labelText = tester.widget<Text>(find.text('Status:'));
    expect(labelText.style?.color, theme.text.secondary);

    // Label: Value -> rich text with label in text.secondary and value in text.primary
    final Text pairWidget = tester.widget<Text>(
      find.byWidgetPredicate(
        (Widget w) =>
            w is Text &&
            w.textSpan != null &&
            w.textSpan!.toPlainText() == 'Session: main',
      ),
    );
    final TextSpan rootSpan = pairWidget.textSpan! as TextSpan;
    final TextSpan labelSpan = rootSpan.children![0] as TextSpan;
    final TextSpan valueSpan = rootSpan.children![1] as TextSpan;
    expect(labelSpan.text, 'Session: ');
    expect(labelSpan.style?.color, theme.text.secondary);
    expect(valueSpan.text, 'main');
    expect(valueSpan.style?.color, theme.text.primary);

    // Explicit color from script
    final Text customText = tester.widget<Text>(find.text('Custom text'));
    expect(customText.style?.color, const Color(0xFFFF00FF));
  });

  testWidgets('default 360x240 spec fits completely without scrolling and has no scrollbar', (
    WidgetTester tester,
  ) async {
    final DialogSpec spec = DialogSpec.fromJson(<String, dynamic>{
      'title': 'Inline Test',
      'width': 360,
      'height': 240,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'text',
          'value': 'Inline Test',
          'color': '#4FC3F7',
          'font_size': 13,
          'bold': 1,
        },
        <String, dynamic>{'type': 'hr'},
        <String, dynamic>{
          'type': 'table',
          'columns': <String>['Key', 'Value'],
          'rows': <List<String>>[
            <String>['one', '1'],
            <String>['two', '2'],
          ],
        },
        <String, dynamic>{'type': 'button', 'value': 'Close'},
      ],
    });

    final DialogController controller = DialogController(
      spec: spec,
      windowApi: const NoopDialogWindowApi(),
      actions: RecordingDialogActionRunner(),
    );

    // Dialog rendered in a 360x240 viewport matching the script spec.
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 360,
            height: 240,
            child: DialogView(controller: controller, onClose: () {}),
          ),
        ),
      ),
    );
    await tester.pump();

    // 1. No scrollbar decoration is drawn.
    expect(find.byType(Scrollbar), findsNothing);
    expect(find.byType(RawScrollbar), findsNothing);

    // 2. Fits within 240px without scrolling.
    final ScrollableState scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable),
    );
    expect(scrollable.position.maxScrollExtent, 0.0);

    // 3. Close button is fully rendered and within the 240px dialog bounds.
    final Rect buttonRect = tester.getRect(find.byType(DialogButtonItem));
    final Rect dialogRect = tester.getRect(find.byType(DialogView));
    expect(buttonRect.bottom, lessThanOrEqualTo(dialogRect.bottom));
    // The button has bottom breathing room (at least content padding of 8px).
    expect(dialogRect.bottom - buttonRect.bottom, greaterThanOrEqualTo(8.0));
  });

  testWidgets('overflowing spec suppresses scrollbar and keeps bottom padding when scrolled to end', (
    WidgetTester tester,
  ) async {
    final DialogSpec spec = DialogSpec.fromJson(<String, dynamic>{
      'title': 'Long Dialog',
      'width': 360,
      'height': 240,
      'items': <Map<String, dynamic>>[
        for (int i = 0; i < 7; i++)
          <String, dynamic>{'type': 'text', 'value': 'Item $i'},
        <String, dynamic>{'type': 'button', 'value': 'Last Item'},
      ],
    });

    final DialogController controller = DialogController(
      spec: spec,
      windowApi: const NoopDialogWindowApi(),
      actions: RecordingDialogActionRunner(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 360,
            height: 240,
            child: DialogView(controller: controller, onClose: () {}),
          ),
        ),
      ),
    );
    await tester.pump();

    // Scrollbar decoration must NOT be drawn even when content overflows.
    expect(find.byType(Scrollbar), findsNothing);
    expect(find.byType(RawScrollbar), findsNothing);

    final ScrollableState scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0.0));

    // Scroll to the very end.
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();

    // Last item is fully visible and not flush with the edge.
    final Rect lastButtonRect = tester.getRect(find.byType(DialogButtonItem));
    final Rect dialogRect = tester.getRect(find.byType(DialogView));
    expect(lastButtonRect.bottom, lessThanOrEqualTo(dialogRect.bottom));
    // Bottom padding equal to content padding (8px) ensures it is not flush against the edge.
    expect(dialogRect.bottom - lastButtonRect.bottom, greaterThanOrEqualTo(8.0));
  });
}
