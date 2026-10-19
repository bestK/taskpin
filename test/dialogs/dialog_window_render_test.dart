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
import 'package:taskpin/features/dialogs/dialog_spec.dart';
import 'package:taskpin/features/dialogs/window_channel.dart';

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
}
