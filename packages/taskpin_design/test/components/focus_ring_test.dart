// Focus ring tests.
//
// The plan's acceptance criterion:
//
//   "每个可交互组件可键盘聚焦且有可见焦点环"
//
// The old ImGui UI and the Win32 bar had NO keyboard focus story at all, so
// this is new capability and needs to be asserted rather than assumed.
//
// What "has a focus ring" means concretely: the component contains a
// FocusableActionDetector (which TpFocusRing is built on), and that detector
// paints a 2 px border/focus border when focused.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin_design/taskpin_design.dart';

/// Pump [child] inside a themed MaterialApp.
Future<void> pumpThemed(
  WidgetTester tester,
  Widget child, {
  bool dark = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: (dark ? TaskPinTheme.dark() : TaskPinTheme.light()).toThemeData(),
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

/// The focused border width of the first DecoratedBox carrying a ring.
double? ringWidth(WidgetTester tester) {
  for (final Element element
      in find.byType(DecoratedBox).evaluate().toList()) {
    final Widget widget = element.widget;
    if (widget is! DecoratedBox) {
      continue;
    }
    // `Decoration` has no `border`; only `BoxDecoration` does. The focus ring
    // is painted with a BoxDecoration, so a non-box decoration simply has no
    // ring to measure.
    final Decoration decoration = widget.decoration;
    if (decoration is! BoxDecoration) {
      continue;
    }
    final BoxBorder? border = decoration.border;
    if (border is Border) {
      return border.top.width;
    }
  }
  return null;
}

void main() {
  group('the focus ring primitive', () {
    testWidgets('exposes a FocusableActionDetector',
        (WidgetTester tester) async {
      await pumpThemed(
        tester,
        TpFocusRing(
          radius: TpRadius.control,
          onTap: () {},
          child: const SizedBox(width: 40, height: 40),
        ),
      );

      expect(find.byType(FocusableActionDetector), findsOneWidget);
    });

    testWidgets('is focusable and reports focus', (WidgetTester tester) async {
      final FocusNode node = FocusNode();
      addTearDown(node.dispose);

      await pumpThemed(
        tester,
        TpFocusRing(
          focusNode: node,
          radius: TpRadius.control,
          onTap: () {},
          child: const SizedBox(width: 40, height: 40),
        ),
      );

      expect(node.canRequestFocus, isTrue);

      node.requestFocus();
      await tester.pumpAndSettle();
      expect(node.hasFocus, isTrue);
    });

    testWidgets('a disabled ring is not focusable',
        (WidgetTester tester) async {
      await pumpThemed(
        tester,
        TpFocusRing(
          enabled: false,
          radius: TpRadius.control,
          onTap: () {},
          child: const SizedBox(width: 40, height: 40),
        ),
      );

      final FocusableActionDetector detector =
          tester.widget(find.byType(FocusableActionDetector));
      expect(detector.enabled, isFalse);
    });

    testWidgets('keyboard activation fires onActivate',
        (WidgetTester tester) async {
      int taps = 0;
      final FocusNode node = FocusNode();
      addTearDown(node.dispose);

      await pumpThemed(
        tester,
        TpFocusRing(
          focusNode: node,
          radius: TpRadius.control,
          onActivate: () => taps++,
          child: const SizedBox(width: 40, height: 40),
        ),
      );

      node.requestFocus();
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(taps, 1);
    });

    testWidgets('pointer activation fires onTap', (WidgetTester tester) async {
      int taps = 0;

      await pumpThemed(
        tester,
        TpFocusRing(
          radius: TpRadius.control,
          onTap: () => taps++,
          child: const SizedBox(width: 40, height: 40),
        ),
      );

      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      expect(taps, 1);
    });
  });

  group('the ring decoration', () {
    testWidgets('is 2 px and uses border/focus', (WidgetTester tester) async {
      late BoxDecoration focused;
      late BoxDecoration unfocused;

      await tester.pumpWidget(
        MaterialApp(
          theme: TaskPinTheme.dark().toThemeData(),
          home: Builder(
            builder: (BuildContext context) {
              focused = tpFocusRingDecoration(
                context,
                isFocused: true,
                radius: TpRadius.control,
              );
              unfocused = tpFocusRingDecoration(
                context,
                isFocused: false,
                radius: TpRadius.control,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final Border focusedBorder = focused.border! as Border;
      expect(focusedBorder.top.width, kTpFocusRingWidth);
      expect(focusedBorder.top.width, 2);
      expect(focusedBorder.top.color, TpSemantic.dark.focusOuter);

      // Unfocused keeps the SAME geometry so toggling focus never moves
      // anything — a control that resizes when you tab to it is worse than no
      // ring at all.
      final Border unfocusedBorder = unfocused.border! as Border;
      expect(unfocusedBorder.top.width, focusedBorder.top.width);
      expect(unfocusedBorder.top.color.a, 0);
    });

    test('the ring constants match the plan', () {
      expect(kTpFocusRingWidth, 2);
      expect(kTpFocusInnerWidth, 1);
    });
  });

  group('interactive components are focusable', () {
    // Each entry: a description and a builder. The assertion is uniform: the
    // rendered tree must contain at least one FocusableActionDetector.
    final Map<String, Widget Function()> cases = <String, Widget Function()>{
      'TpButton': () => TpButton(label: 'Go', onPressed: () {}),
      'TpSwitch': () => TpSwitch(value: true, onChanged: (_) {}),
      'TpSegmentedControl': () => TpSegmentedControl<int>(
            value: 0,
            segments: const <TpSelectItem<int>>[
              TpSelectItem<int>(value: 0, label: 'A'),
              TpSelectItem<int>(value: 1, label: 'B'),
            ],
            onChanged: (_) {},
          ),
      'TpNavRail': () => TpNavRail(
            destinations: <TpNavDestination>[
              TpNavDestination(
                label: 'Signals',
                icon: TpIcons.signals,
                route: '/signals',
              ),
            ],
            selectedRoute: '/signals',
            onSelect: (_) {},
          ),
      'TpSignalCard': () => TpSignalCard(
            name: 'CPU',
            // Not `success`: that kind makes the status dot pulse forever,
            // and `pumpAndSettle` never settles with a repeating animation.
            kind: TpStateKind.caution,
            value: '42',
            onTap: () {},
          ),
      'TpSignalGrid': () => TpSignalGrid(
            rows: <TpSignalRow>[
              TpSignalRow(
                name: 'CPU',
                kind: TpStateKind.success,
                value: '42',
              ),
            ],
            onSelect: (_) {},
          ),
      'TpMarketCard': () => TpMarketCard(
            name: 'github_trending',
            description: 'Trending repos',
            onInstall: () {},
            onOpen: () {},
          ),
      'TpToastCard': () => TpToastCard(
            toast: const TpToast(message: 'Saved'),
            onDismiss: () {},
          ),
      'TpInfoBar': () => TpInfoBar(
            message: 'Something happened',
            onDismiss: () {},
          ),
      'TpPathPicker': () => TpPathPicker(
            value: 'a.lua',
            onChanged: (_) {},
            onBrowse: () async => null,
          ),
      'TpHeaderListEditor': () => TpHeaderListEditor(
            entries: const <TpHeaderEntry>[
              TpHeaderEntry(name: 'a', value: 'b'),
            ],
            onChanged: (_) {},
          ),
      'TpExpressionEditor': () => TpExpressionEditor(
            value: r'$.a',
            availablePaths: const <String>[r'$.b'],
            onChanged: (_) {},
          ),
      'TpSpanInspector': () => TpSpanInspector(
            spans: const <TpBarSpan>[TpBarSpan(text: 'CPU')],
            onChanged: (_) {},
          ),
    };

    for (final MapEntry<String, Widget Function()> entry in cases.entries) {
      testWidgets('${entry.key} contains a focus ring',
          (WidgetTester tester) async {
        await pumpThemed(
          tester,
          SingleChildScrollView(child: entry.value()),
        );

        expect(
          find.byType(FocusableActionDetector),
          findsAtLeastNWidgets(1),
          reason: '${entry.key} must be keyboard-focusable',
        );
      });
    }
  });
}
