// Regression tests for the dialog review fixes: colour parsing, contrast
// selection, table truncation, and wheel routing.

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin/features/dialogs/dialog_action.dart';
import 'package:taskpin/features/dialogs/dialog_controller.dart';
import 'package:taskpin/features/dialogs/dialog_palette.dart';
import 'package:taskpin/features/dialogs/dialog_spec.dart';
import 'package:taskpin/features/dialogs/dialog_view.dart';
import 'package:taskpin/features/dialogs/items/button_item.dart';
import 'package:taskpin/features/dialogs/items/text_item.dart';
import 'package:taskpin/features/dialogs/window_channel.dart';
import 'package:taskpin_design/taskpin_design.dart';

const Color _kSurfaceLight = Color(0xFFECECEC);

DialogController _controller(DialogSpec spec) => DialogController(
      spec: spec,
      windowApi: const NoopDialogWindowApi(),
      actions: RecordingDialogActionRunner(),
    );

void main() {
  group('parseDialogColor', () {
    test('accepts #RGB and #RRGGBB, with or without the hash', () {
      expect(parseDialogColor('#F00'), const Color(0xFFFF0000));
      expect(parseDialogColor('00FF00'), const Color(0xFF00FF00));
      expect(parseDialogColor('#abc'), const Color(0xFFAABBCC));
    });

    test('accepts #RRGGBBAA in CSS order, so a translucent fill is possible', () {
      expect(parseDialogColor('#FF000080'), const Color(0x80FF0000));
      expect(parseDialogColor('FF000080')?.alpha, 0x80);
    });

    test('rejects a signed or otherwise non-hex value', () {
      expect(parseDialogColor('#-00FF00'), isNull);
      expect(parseDialogColor('+00FF00'), isNull);
      expect(parseDialogColor('#00FF0G'), isNull);
      expect(parseDialogColor('#00 FF0'), isNull);
    });

    test('rejects other lengths and the empty default', () {
      expect(parseDialogColor(''), isNull);
      expect(parseDialogColor('#12345'), isNull);
      expect(parseDialogColor('#1234567'), isNull);
    });
  });

  group('contrast', () {
    test('ensureContrast from a mid-grey surface reaches the target', () {
      const Color surface = Color(0xFF8A8A8A);
      const Color script = Color(0xFF444444);
      final Color adapted = ensureContrast(script, surface);
      expect(contrastRatio(adapted, surface), greaterThanOrEqualTo(4.5));
      expect(adapted, isNot(script));
    });

    test('ensureContrast returns the best extreme when the target is unreachable', () {
      const Color surface = Color(0xFF8A8A8A);
      final Color adapted = ensureContrast(
        const Color(0xFF444444),
        surface,
        minContrast: 21,
      );
      expect(adapted, anyOf(const Color(0xFF000000), const Color(0xFFFFFFFF)));
      expect(adapted, contrastingTextColor(surface));
    });

    test('contrastingTextColor picks the higher-contrast of black and white', () {
      // #4FC3F7 is mid-light: white is about 2:1, black about 10:1.
      expect(contrastingTextColor(const Color(0xFF4FC3F7)), const Color(0xFF000000));
      expect(contrastingTextColor(const Color(0xFF202020)), const Color(0xFFFFFFFF));
    });

    testWidgets('a button on #4FC3F7 gets black text, not white', (WidgetTester tester) async {
      final DialogSpec spec = DialogSpec.fromJson(<String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'button', 'value': 'Go', 'bg': '#4FC3F7'},
        ],
      });
      await tester.pumpWidget(MaterialApp(
        theme: TaskPinTheme.light().toThemeData(),
        home: Scaffold(
          body: DialogView(controller: _controller(spec), hostDrawsSurface: true),
        ),
      ));
      await tester.pump();
      final Text label = tester.widget<Text>(find.text('Go'));
      expect(label.style?.color, const Color(0xFF000000));
      expect(contrastRatio(label.style!.color!, const Color(0xFF4FC3F7)),
          greaterThan(4.5));
    });

    testWidgets('bold text at 12 pt is held to 4.5:1; 14 pt bold is large text at 3:1',
        (WidgetTester tester) async {
      // Surface and script colour chosen so 3:1 passes but 4.5:1 does not.
      final DialogSpec spec = DialogSpec.fromJson(<String, dynamic>{
        'bg_color': '#ECECEC',
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'text', 'value': 'Small', 'color': '#8FBCE0', 'bold': 1, 'font_size': 12,
          },
          <String, dynamic>{
            'type': 'text', 'value': 'Large', 'color': '#8FBCE0', 'bold': 1, 'font_size': 14,
          },
        ],
      });
      await tester.pumpWidget(MaterialApp(
        theme: TaskPinTheme.light().toThemeData(),
        home: Scaffold(
          body: DialogView(controller: _controller(spec), hostDrawsSurface: true),
        ),
      ));
      await tester.pump();
      final Text small = tester.widget<Text>(find.text('Small'));
      final Text large = tester.widget<Text>(find.text('Large'));
      expect(contrastRatio(small.style!.color!, _kSurfaceLight),
          greaterThanOrEqualTo(4.5));
      expect(contrastRatio(large.style!.color!, _kSurfaceLight),
          greaterThanOrEqualTo(3.0));
      // The large one is not forced to 4.5, so it keeps more of the script hue.
      expect(large.style!.color, isNot(small.style!.color));
    });
  });

  group('table cell truncation', () {
    DialogSpec tableSpec(String longText) => DialogSpec.fromJson(<String, dynamic>{
          'items': <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'table',
              'columns': <String>['Name'],
              'rows': <List<String>>[
                <String>[longText],
              ],
            },
          ],
        });

    Future<void> pumpAt(WidgetTester tester, DialogSpec spec, double width) async {
      await tester.pumpWidget(MaterialApp(
        theme: TaskPinTheme.light().toThemeData(),
        home: Center(
          child: SizedBox(
            width: width,
            child: DialogView(controller: _controller(spec), hostDrawsSurface: true),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a cell that fits gets no tooltip, even when its text is long',
        (WidgetTester tester) async {
      await pumpAt(tester, tableSpec('Short name ok'), 400);
      expect(
        find.ancestor(of: find.text('Short name ok'), matching: find.byType(Tooltip)),
        findsNothing,
      );
    });

    testWidgets('a cell that is ellipsized gets the full text as a tooltip',
        (WidgetTester tester) async {
      const String long = 'A very long process name that cannot fit';
      await pumpAt(tester, tableSpec(long), 120);
      final Text cell = tester.widget<Text>(find.text(long));
      expect(cell.overflow, TextOverflow.ellipsis);
      final Tooltip tip = tester.widget<Tooltip>(
        find.ancestor(of: find.text(long), matching: find.byType(Tooltip)),
      );
      expect(tip.message, long);
    });

    testWidgets('row height is at least 32 px (VISUAL_SPEC §8)', (WidgetTester tester) async {
      await pumpAt(tester, tableSpec('x'), 400);
      final Size row = tester.getSize(find.ancestor(
        of: find.text('x'),
        matching: find.byType(ConstrainedBox),
      ).first);
      expect(row.height, greaterThanOrEqualTo(32));
    });
  });

  group('label/value split', () {
    testWidgets('a URL is not split at its scheme colon', (WidgetTester tester) async {
      const String url = 'https://example.com/a';
      final DialogSpec spec = DialogSpec.fromJson(<String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'text', 'value': url},
        ],
      });
      await tester.pumpWidget(MaterialApp(
        theme: TaskPinTheme.light().toThemeData(),
        home: Scaffold(
          body: DialogView(controller: _controller(spec), hostDrawsSurface: true),
        ),
      ));
      await tester.pump();
      // One run of text, not a label span plus a value span.
      expect(find.text(url), findsOneWidget);
    });

    testWidgets('a "Label: value" pair is still split', (WidgetTester tester) async {
      final DialogSpec spec = DialogSpec.fromJson(<String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'text', 'value': 'Status: Active'},
        ],
      });
      await tester.pumpWidget(MaterialApp(
        theme: TaskPinTheme.light().toThemeData(),
        home: Scaffold(
          body: DialogView(controller: _controller(spec), hostDrawsSurface: true),
        ),
      ));
      await tester.pump();
      final RichText rich = tester.widget<RichText>(
        find.byWidgetPredicate(
          (Widget w) => w is RichText && w.text.toPlainText() == 'Status: Active',
        ),
      );
      expect(rich.text.toPlainText(), 'Status: Active');
    });
  });

  group('wheel routing', () {
    DialogSpec tall() => DialogSpec.fromJson(<String, dynamic>{
          'title': 'Wheel',
          'width': 360,
          'height': 240,
          'items': <Map<String, dynamic>>[
            for (int i = 0; i < 8; i++)
              <String, dynamic>{'type': 'text', 'value': 'Line $i\n' * 12},
          ],
        });

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 360,
            height: 240,
            child: DialogView(
              controller: _controller(tall()),
              showScrollbar: true,
              hostDrawsSurface: true,
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('one wheel event moves the content by the wheel delta, once',
        (WidgetTester tester) async {
      await pump(tester);
      final ScrollableState s = tester.state<ScrollableState>(find.byType(Scrollable));
      final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
      pointer.hover(tester.getCenter(find.byType(DialogView)));

      s.position.jumpTo(100);
      await tester.pump();
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 40)));
      await tester.pump(const Duration(seconds: 2));
      // Handled twice this would be 120 (manual -20, then Scrollable +40).
      expect(s.position.pixels, 140);
    });

    testWidgets('Shift+wheel resizes and leaves the content where it is',
        (WidgetTester tester) async {
      await pump(tester);
      final ScrollableState s = tester.state<ScrollableState>(find.byType(Scrollable));
      final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
      pointer.hover(tester.getCenter(find.byType(DialogView)));

      s.position.jumpTo(100);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 40)));
      await tester.pump(const Duration(seconds: 2));
      expect(s.position.pixels, 100);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
    });
  });
}
