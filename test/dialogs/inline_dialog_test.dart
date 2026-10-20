// Inline dialogs: the panel replaces the second window.
//
// THE CHANGE: a bar click used to create a top-level window through
// `desktop_multi_window`, which meant booting a second Flutter engine and a
// Dart isolate before anything appeared — seconds of nothing after the click —
// and the dialog carried the OS title bar. It is now a panel inside the
// manager window, so it paints on the next frame and shares the app's chrome.
//
// These tests cover the state layer and the render path. The window
// bookkeeping (position, drag) is deliberately not asserted here: it is
// geometry, and the widget tests in `test/app` cover the layout that matters.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin/app/l10n.dart';
import 'package:taskpin/features/dialogs/dialog_spec.dart';
import 'package:taskpin/features/dialogs/dialog_view.dart';
import 'package:taskpin/features/dialogs/inline_dialog_layer.dart';
import 'package:taskpin/features/dialogs/inline_dialog_provider.dart';
import 'package:taskpin_design/taskpin_design.dart';

DialogSpec _spec({String title = 'Clock', int width = 320, int height = 260}) =>
    DialogSpec.fromJson(<String, dynamic>{
      'title': title,
      'width': width,
      'height': height,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'value': 'hello'},
      ],
    });

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  group('InlineDialogState', () {
    test('starts closed', () {
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(inlineDialogProvider).isOpen, isFalse);
    });

    test('open shows a spec and close hides it', () {
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(inlineDialogProvider.notifier).open(_spec(), luaPath: 'a.lua');
      expect(c.read(inlineDialogProvider).isOpen, isTrue);
      expect(c.read(inlineDialogProvider).luaPath, 'a.lua');

      c.read(inlineDialogProvider.notifier).close();
      expect(c.read(inlineDialogProvider).isOpen, isFalse);
    });

    test('a second open replaces the first, like the C single-dialog rule', () {
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);
      final InlineDialogNotifier n = c.read(inlineDialogProvider.notifier);
      n.open(_spec(title: 'First'), luaPath: 'a.lua');
      n.open(_spec(title: 'Second'), luaPath: 'b.lua');
      expect(c.read(inlineDialogProvider).spec!.title, 'Second');
      expect(c.read(inlineDialogProvider).luaPath, 'b.lua');
    });

    test('replaceSpec keeps the script identity for the refresh loop', () {
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);
      final InlineDialogNotifier n = c.read(inlineDialogProvider.notifier);
      n.open(_spec(title: 'First'), luaPath: 'a.lua');
      n.replaceSpec(_spec(title: 'Refreshed'));
      expect(c.read(inlineDialogProvider).spec!.title, 'Refreshed');
      expect(c.read(inlineDialogProvider).luaPath, 'a.lua',
          reason: 'a refresh must not lose the ability to refresh again');
    });

    test('replaceSpec on a closed panel is a no-op', () {
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(inlineDialogProvider.notifier).replaceSpec(_spec());
      expect(c.read(inlineDialogProvider).isOpen, isFalse);
    });
  });

  group('InlineDialogLayer', () {
    testWidgets('renders nothing while closed', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(child: _app(const InlineDialogLayer())),
      );
      expect(find.byType(DialogView), findsNothing);
      expect(find.text('Clock'), findsNothing);
    });

    testWidgets('shows the title and the item once opened', (
      WidgetTester tester,
    ) async {
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: _app(const InlineDialogLayer()),
        ),
      );

      c.read(inlineDialogProvider.notifier).open(_spec());
      await tester.pump();

      expect(find.text('Clock'), findsOneWidget);
      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('the scrim dismisses the panel', (WidgetTester tester) async {
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: _app(const InlineDialogLayer()),
        ),
      );

      c.read(inlineDialogProvider.notifier).open(_spec());
      await tester.pump();
      expect(c.read(inlineDialogProvider).isOpen, isTrue);

      // Tap near the top-left corner: outside the centred panel, on the scrim.
      await tester.tapAt(const Offset(4, 4));
      await tester.pump();
      expect(c.read(inlineDialogProvider).isOpen, isFalse);
    });

    testWidgets('the close button dismisses the panel', (
      WidgetTester tester,
    ) async {
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: _app(const InlineDialogLayer()),
        ),
      );

      c.read(inlineDialogProvider.notifier).open(_spec());
      await tester.pump();

      // The title row's close affordance is the first close glyph.
      await tester.tap(find.byIcon(TpIcons.close).first);
      await tester.pump();
      expect(c.read(inlineDialogProvider).isOpen, isFalse);
    });

    testWidgets('a borderless spec keeps the panel edge but drops the title', (
      WidgetTester tester,
    ) async {
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: _app(const InlineDialogLayer()),
        ),
      );

      final DialogSpec borderless = DialogSpec.fromJson(<String, dynamic>{
        'title': 'HUD',
        'width': 200,
        'height': 120,
        'borderless': 1,
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'text', 'value': 'bare'},
        ],
      });
      c.read(inlineDialogProvider.notifier).open(borderless);
      await tester.pump();

      // The item is rendered; the panel's own caption is not.
      expect(find.text('bare'), findsOneWidget);
      expect(find.text('HUD'), findsNothing);
    });
  });
}
