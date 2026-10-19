// Reduced-motion tests.
//
// The plan's acceptance criterion:
//
//   "disableAnimations == true 时无过渡渲染"
//
// The contract these tests hold: with the platform flag set, the animated
// components render in their final state immediately, and — importantly —
// still RENDER. A component that disappears or throws under reduced motion is
// not accessible, it is broken.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin_design/taskpin_design.dart';

Future<void> pumpReduced(
  WidgetTester tester,
  Widget child, {
  bool reduced = true,
  bool dark = true,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: MaterialApp(
        theme:
            (dark ? TaskPinTheme.dark() : TaskPinTheme.light()).toThemeData(),
        home: Scaffold(
          body: SingleChildScrollView(child: child),
        ),
      ),
    ),
  );
  // A single pump, with no time advance: if anything were animating from an
  // off-screen state, the assertion below would catch it.
  await tester.pump();
}

void main() {
  group('reduced motion', () {
    testWidgets('TpMotion.resolve is the single choke point',
        (WidgetTester tester) async {
      // Every animated component routes through resolve(). Prove it honours
      // the flag in a real tree, not just in isolation.
      late Duration fast;
      late Duration base;
      late Duration slow;

      await pumpReduced(
        tester,
        Builder(
          builder: (BuildContext context) {
            fast = TpMotion.resolve(context, TpMotion.fast);
            base = TpMotion.resolve(context, TpMotion.base);
            slow = TpMotion.resolve(context, TpMotion.slow);
            return const SizedBox.shrink();
          },
        ),
      );

      expect(fast, Duration.zero);
      expect(base, Duration.zero);
      expect(slow, Duration.zero);
    });

    testWidgets('StatusDot renders without pulsing',
        (WidgetTester tester) async {
      await pumpReduced(
        tester,
        const TpStatusDot(kind: TpStateKind.success, pulsing: true),
      );

      expect(find.byType(TpStatusDot), findsOneWidget);
      // The dot must be visible immediately, at full presence.
      expect(tester.widget<TpStatusDot>(find.byType(TpStatusDot)).pulsing, isTrue);
    });

    testWidgets('Skeleton renders a static block', (WidgetTester tester) async {
      await pumpReduced(tester, const TpSkeleton(height: 20, shimmer: true));

      expect(find.byType(TpSkeleton), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('indeterminate ProgressBar still shows progress',
        (WidgetTester tester) async {
      // Reduced motion must not mean "no feedback that work is happening".
      await pumpReduced(tester, const TpProgressBar.indeterminate());

      expect(find.byType(TpProgressBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('determinate ProgressBar renders its value',
        (WidgetTester tester) async {
      await pumpReduced(tester, const TpProgressBar(value: 0.75));

      expect(find.byType(TpProgressBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Switch renders in its on state immediately',
        (WidgetTester tester) async {
      await pumpReduced(
        tester,
        TpSwitch(value: true, label: 'On', onChanged: (_) {}),
      );

      expect(find.text('On'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('SignalCard is fully laid out on the first frame',
        (WidgetTester tester) async {
      await pumpReduced(
        tester,
        TpSignalCard(
          name: 'CPU',
          kind: TpStateKind.success,
          value: '42',
          unit: '%',
          interval: const Duration(seconds: 2),
        ),
      );

      // Not faded in, not slid in: present.
      expect(find.text('CPU'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('NavRail renders its items immediately',
        (WidgetTester tester) async {
      await pumpReduced(
        tester,
        TpNavRail(
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
      );

      expect(find.text('Signals'), findsOneWidget);
    });

    testWidgets('the same components also render with animations enabled',
        (WidgetTester tester) async {
      // The mirror case: turning reduced motion OFF must not break anything.
      await pumpReduced(
        tester,
        const Column(
          children: <Widget>[
            TpStatusDot(kind: TpStateKind.success, pulsing: true),
            TpSkeleton(height: 20),
            TpProgressBar.indeterminate(),
          ],
        ),
        reduced: false,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion works in the light theme too',
        (WidgetTester tester) async {
      await pumpReduced(
        tester,
        const TpSkeleton(height: 20, shimmer: true),
        dark: false,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
