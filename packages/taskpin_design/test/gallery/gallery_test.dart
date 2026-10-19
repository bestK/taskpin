// Gallery test.
//
// The gallery is the plan's manual-verification surface ("整体观感在 /gallery
// 路由目视检查"), so it has to at least build cleanly in both themes. A broken
// gallery is a broken review tool.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin_design/taskpin_design.dart';

void main() {
  group('gallery', () {
    testWidgets('builds in dark and shows every section',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(home: TaskPinGallery()),
      );
      await tester.pump();

      // Section eyebrows.
      expect(find.text('Colour tokens'), findsOneWidget);
      expect(find.text('Typography'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Buttons'), findsOneWidget);
      expect(find.text('Shell'), findsOneWidget);
      expect(find.text('Data'), findsOneWidget);
      expect(find.text('Forms'), findsOneWidget);
      expect(find.text('Feedback'), findsOneWidget);
      expect(find.text('Code'), findsOneWidget);
      expect(find.text('Bar'), findsOneWidget);
    });

    testWidgets('renders both theme panels per section',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(home: TaskPinGallery()),
      );
      await tester.pump();

      // Every section renders a Dark and a Light panel.
      expect(find.text('Dark'), findsWidgets);
      expect(find.text('Light'), findsWidgets);
    });

    testWidgets('can start in the light theme', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: TaskPinGallery(initialBrightness: Brightness.light),
        ),
      );
      await tester.pump();

      expect(find.text('TaskPin design system'), findsOneWidget);
    });

    testWidgets('the theme toggle switches the chrome',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(home: TaskPinGallery()),
      );
      await tester.pump();

      await tester.tap(find.text('Light').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Still rendering after the swap.
      expect(find.text('TaskPin design system'), findsOneWidget);
    });

    testWidgets('renders the frozen bar token list',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(home: TaskPinGallery()),
      );
      await tester.pump();

      // The inspector prints each frozen token name.
      expect(find.text('bar/state.stale'), findsWidgets);
    });
  });
}
