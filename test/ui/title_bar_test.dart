// Title bar behaviour: platform branching, the channel availability probe,
// maximize icon state, and the click/double-tap commands.
//
// The native hit test and WM_NCCALCSIZE are not testable from Dart; this file
// pins everything above the channel. Two seams make that possible without a
// real window:
//
//   * `TitleBar(platform:)` overrides `defaultTargetPlatform`;
//   * `TitleBar(api:)` injects a [MainWindowApi]. The default implementation is
//     still exercised once, against a mocked binary messenger, to prove the
//     real MethodChannel path works and that a missing plugin degrades to "no
//     buttons" instead of an exception.
//
// The channel names are asserted literally. They are a cross-language contract
// with native/win/taskpin_window_plugin.cpp, and a typo there would otherwise
// only show up on a real Windows build.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin/core/window/main_window_channel.dart';
import 'package:taskpin/ui/widgets/title_bar.dart';
import 'package:taskpin_design/taskpin_design.dart';

/// A title bar with the real theme, on a fixed platform.
Widget _bar({
  TargetPlatform platform = TargetPlatform.windows,
  MainWindowApi? api,
  double width = 800,
}) {
  return MaterialApp(
    theme: TaskPinTheme.dark().toThemeData(),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          child: TitleBar(platform: platform, api: api),
        ),
      ),
    ),
  );
}

/// Let the asynchronous `isMaximized` probe settle.
Future<void> _pumpBar(WidgetTester tester, Widget bar) async {
  await tester.pumpWidget(bar);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('platform branching', () {
    testWidgets('Windows renders minimize, maximize and close', (
      WidgetTester tester,
    ) async {
      final RecordingMainWindowApi api = RecordingMainWindowApi();
      addTearDown(api.dispose);

      await _pumpBar(tester, _bar(api: api));

      expect(find.byKey(const Key('title_bar_minimize')), findsOneWidget);
      expect(find.byKey(const Key('title_bar_maximize')), findsOneWidget);
      expect(find.byKey(const Key('title_bar_close')), findsOneWidget);
    });

    testWidgets('macOS renders no window buttons', (WidgetTester tester) async {
      // The API is injectable and reports support; the platform check alone
      // must suppress the buttons.
      final RecordingMainWindowApi api = RecordingMainWindowApi();
      addTearDown(api.dispose);

      await _pumpBar(tester, _bar(platform: TargetPlatform.macOS, api: api));

      expect(find.byKey(const Key('title_bar_minimize')), findsNothing);
      expect(find.byKey(const Key('title_bar_maximize')), findsNothing);
      expect(find.byKey(const Key('title_bar_close')), findsNothing);
    });

    testWidgets('macOS reserves 72 px for the traffic lights', (
      WidgetTester tester,
    ) async {
      await _pumpBar(tester, _bar(platform: TargetPlatform.macOS));

      // The leading inset is the first SizedBox inside the bar.
      final Iterable<SizedBox> boxes = tester.widgetList<SizedBox>(
        find.descendant(
          of: find.byType(TitleBar),
          matching: find.byType(SizedBox),
        ),
      );
      expect(
        boxes.any((SizedBox b) => b.width == kMacTrafficLightInset),
        isTrue,
      );
      expect(kMacTrafficLightInset, 72);
    });

    testWidgets('Linux renders no window buttons', (WidgetTester tester) async {
      final RecordingMainWindowApi api = RecordingMainWindowApi();
      addTearDown(api.dispose);

      await _pumpBar(tester, _bar(platform: TargetPlatform.linux, api: api));

      expect(find.byKey(const Key('title_bar_minimize')), findsNothing);
      expect(find.byKey(const Key('title_bar_close')), findsNothing);
    });
  });

  group('channel availability', () {
    testWidgets('buttons are hidden when the channel is not registered', (
      WidgetTester tester,
    ) async {
      // No mock handler installed: `isMaximized` throws MissingPluginException,
      // which the API turns into null.
      await _pumpBar(tester, _bar());

      expect(find.byKey(const Key('title_bar_minimize')), findsNothing);
      expect(find.byKey(const Key('title_bar_maximize')), findsNothing);
      expect(find.byKey(const Key('title_bar_close')), findsNothing);
      // The bar itself still renders, so the window is not blank.
      expect(find.text('TaskPin'), findsOneWidget);
    });

    testWidgets('the real channel path answers through the messenger', (
      WidgetTester tester,
    ) async {
      final TestDefaultBinaryMessenger messenger =
          tester.binding.defaultBinaryMessenger;
      final List<String> methods = <String>[];

      messenger.setMockMethodCallHandler(
        const MethodChannel(kMainWindowChannel),
        (MethodCall call) async {
          methods.add(call.method);
          if (call.method == 'isMaximized') return false;
          return null;
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel(kMainWindowChannel),
          null,
        ),
      );

      await _pumpBar(tester, _bar());

      expect(methods, <String>['isMaximized']);
      expect(find.byKey(const Key('title_bar_maximize')), findsOneWidget);
    });

    test('channel names match the native contract', () {
      // native/win/taskpin_window_plugin.cpp registers these exact strings.
      expect(kMainWindowChannel, 'taskpin/main_window');
      expect(kMainWindowEventsChannel, 'taskpin/main_window/events');
      // The dialog window owns `taskpin/window`; a collision would make each
      // side answer the other's methods with NotImplemented.
      expect(kMainWindowChannel, isNot('taskpin/window'));
    });
  });

  group('commands', () {
    testWidgets('minimize and close call the channel', (
      WidgetTester tester,
    ) async {
      final RecordingMainWindowApi api = RecordingMainWindowApi();
      addTearDown(api.dispose);

      await _pumpBar(tester, _bar(api: api));

      await tester.tap(find.byKey(const Key('title_bar_minimize')));
      await tester.tap(find.byKey(const Key('title_bar_close')));
      await tester.pump();

      expect(api.calls, <String>['minimize', 'close']);
    });

    testWidgets('double-tapping the title bar toggles maximize', (
      WidgetTester tester,
    ) async {
      final RecordingMainWindowApi api = RecordingMainWindowApi();
      addTearDown(api.dispose);

      await _pumpBar(tester, _bar(api: api));

      // Somewhere in the empty middle of the bar, away from the buttons.
      await tester.tap(find.text('TaskPin'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('TaskPin'));
      await tester.pump(const Duration(milliseconds: 350));

      expect(api.calls, <String>['toggleMaximize']);
    });

    testWidgets('double-tap does nothing without a native half', (
      WidgetTester tester,
    ) async {
      final RecordingMainWindowApi api =
          RecordingMainWindowApi(supported: false);
      addTearDown(api.dispose);

      await _pumpBar(tester, _bar(api: api));

      await tester.tap(find.text('TaskPin'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('TaskPin'));
      await tester.pump(const Duration(milliseconds: 350));

      expect(api.calls, isEmpty);
    });
  });

  group('maximized state', () {
    testWidgets('the event channel changes the maximize glyph', (
      WidgetTester tester,
    ) async {
      final RecordingMainWindowApi api = RecordingMainWindowApi();
      addTearDown(api.dispose);

      await _pumpBar(tester, _bar(api: api));

      Icon glyph() => tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('title_bar_maximize')),
          matching: find.byType(Icon),
        ),
      );
      final IconData restore = glyph().icon!;

      api.emitMaximized(true);
      // The broadcast stream delivers on a microtask, so the rebuild lands on
      // the following frame; two pumps settle it.
      await tester.pump();
      await tester.pump();
      final IconData maximized = glyph().icon!;
      expect(maximized, isNot(restore));

      api.emitMaximized(false);
      await tester.pump();
      await tester.pump();
      expect(glyph().icon, restore);
    });

    testWidgets('a window that starts maximized shows restore', (
      WidgetTester tester,
    ) async {
      final RecordingMainWindowApi api =
          RecordingMainWindowApi(maximized: true);
      addTearDown(api.dispose);

      await _pumpBar(tester, _bar(api: api));

      // The two glyphs differ; the semantic label is the readable assertion.
      expect(
        tester.getSemantics(find.byKey(const Key('title_bar_maximize'))).label,
        contains('Restore'),
      );
    });
  });

  group('appearance', () {
    testWidgets('36 px tall with a 1 px divider and no raw colours', (
      WidgetTester tester,
    ) async {
      await _pumpBar(tester, _bar());

      expect(
        tester.getSize(find.byType(TitleBar)).height,
        kTitleBarHeight,
      );
      expect(kTitleBarHeight, 36);

      final Container container = tester.widget<Container>(
        find.descendant(
          of: find.byType(TitleBar),
          matching: find.byType(Container),
        ).first,
      );
      final BoxDecoration decoration = container.decoration! as BoxDecoration;
      final BoxDecoration foreground =
          container.foregroundDecoration! as BoxDecoration;
      final TaskPinTheme theme = TaskPinTheme.dark();
      expect(decoration.color, theme.bg.window);
      expect(
        foreground.border,
        Border(bottom: BorderSide(color: theme.stroke.divider)),
      );
    });

    testWidgets('the name is 13/500 in the primary text colour', (
      WidgetTester tester,
    ) async {
      await _pumpBar(tester, _bar());

      final Text text = tester.widget<Text>(find.text('TaskPin'));
      expect(text.style!.fontSize, 13);
      expect(text.style!.fontWeight, FontWeight.w500);
      expect(text.style!.color, TaskPinTheme.dark().text.primary);
    });

    testWidgets('each button is 46 x 36', (WidgetTester tester) async {
      final RecordingMainWindowApi api = RecordingMainWindowApi();
      addTearDown(api.dispose);

      await _pumpBar(tester, _bar(api: api));

      for (final String key in <String>[
        'title_bar_minimize',
        'title_bar_maximize',
        'title_bar_close',
      ]) {
        expect(
          tester.getSize(find.byKey(Key(key))),
          const Size(kTitleBarButtonWidth, kTitleBarHeight),
        );
      }
      expect(kTitleBarButtonWidth, 46);
    });
  });
}
