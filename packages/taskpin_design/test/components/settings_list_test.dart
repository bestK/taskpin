// Smoke test: settings and list components render in both themes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin_design/taskpin_design.dart';

Future<void> _pump(
  WidgetTester tester,
  TaskPinTheme theme,
  Widget child,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme.toThemeData(),
      home: Scaffold(
        backgroundColor: theme.bg.window,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(TpSpacing.s24),
          child: SizedBox(width: 600, child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  for (final MapEntry<String, TaskPinTheme> entry in <String, TaskPinTheme>{
    'dark': TaskPinTheme.dark(),
    'light': TaskPinTheme.light(),
  }.entries) {
    group('${entry.key} theme', () {
      final TaskPinTheme theme = entry.value;

      testWidgets('TpSettingsCard renders title, description and trailing',
          (WidgetTester tester) async {
        await _pump(
          tester,
          theme,
          TpSettingsCard(
            title: 'Default width',
            description: 'Used by new items.',
            icon: TpIcons.settings,
            trailing: TpButton(label: 'Reset', onPressed: () {}),
          ),
        );
        expect(find.text('Default width'), findsOneWidget);
        expect(find.text('Used by new items.'), findsOneWidget);
        expect(find.text('Reset'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('clickable TpSettingsCard fires onTap',
          (WidgetTester tester) async {
        int taps = 0;
        await _pump(
          tester,
          theme,
          TpSettingsCard(title: 'Market', onTap: () => taps++),
        );
        await tester.tap(find.text('Market'));
        await tester.pump();
        expect(taps, 1);
      });

      testWidgets('TpSettingsCard wraps the trailing control below 476 px',
          (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme.toThemeData(),
            home: Scaffold(
              body: SizedBox(
                width: 400,
                child: TpSettingsCard(
                  title: 'Narrow',
                  trailing: TpButton(label: 'Wrapped', onPressed: () {}),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final Offset title = tester.getTopLeft(find.text('Narrow'));
        final Offset button = tester.getTopLeft(find.text('Wrapped'));
        expect(button.dy, greaterThan(title.dy));
        expect(tester.takeException(), isNull);
      });

      testWidgets('TpSettingsExpander expands and collapses',
          (WidgetTester tester) async {
        await _pump(
          tester,
          theme,
          TpSettingsExpander(
            title: 'Sources',
            description: 'Two sources.',
            children: <Widget>[
              const Text('https://example.com/a'),
              const Text('https://example.com/b'),
            ],
          ),
        );

        expect(find.text('https://example.com/a'), findsNothing);
        await tester.tap(find.text('Sources'));
        await tester.pumpAndSettle();
        expect(find.text('https://example.com/a'), findsOneWidget);
        expect(find.text('https://example.com/b'), findsOneWidget);

        await tester.tap(find.text('Sources'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('TpSettingsSection lays out header and cards',
          (WidgetTester tester) async {
        await _pump(
          tester,
          theme,
          TpSettingsSection(
            title: 'Updates',
            children: <Widget>[
              TpSettingsCard(title: 'Check automatically'),
              TpSettingsCard(title: 'Current version'),
            ],
          ),
        );
        expect(find.text('Updates'), findsOneWidget);
        expect(find.text('Check automatically'), findsOneWidget);
        expect(find.text('Current version'), findsOneWidget);
      });

      testWidgets('TpListGroup renders rows, with and without subtitle',
          (WidgetTester tester) async {
        await _pump(
          tester,
          theme,
          TpListGroup(
            children: <Widget>[
              TpListRow(
                title: 'Rich',
                subtitle: 'rich_text_demo.lua · every 5 s',
                trailing: TpStatusDot(kind: TpStateKind.success),
                onTap: () {},
              ),
              const TpListRow(title: 'Clock'),
            ],
          ),
        );
        expect(find.text('Rich'), findsOneWidget);
        expect(find.text('rich_text_demo.lua · every 5 s'), findsOneWidget);
        expect(find.text('Clock'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('TpListRow height is 40 without a subtitle and 60 with one',
          (WidgetTester tester) async {
        await _pump(
          tester,
          theme,
          TpListGroup(
            children: <Widget>[
              const TpListRow(title: 'One line'),
              const TpListRow(title: 'Two lines', subtitle: 'detail'),
            ],
          ),
        );
        final Size one = tester.getSize(find.text('One line'));
        expect(one.height, lessThanOrEqualTo(TpControlSize.listRow));
        final Size rowTwo = tester.getSize(
          find.ancestor(
            of: find.text('Two lines'),
            matching: find.byType(Container),
          ).first,
        );
        expect(rowTwo.height, TpControlSize.listRowTwoLine);
      });

      testWidgets('TpListRow tap fires onTap', (WidgetTester tester) async {
        int taps = 0;
        await _pump(
          tester,
          theme,
          TpListGroup(
            children: <Widget>[
              TpListRow(title: 'Tap me', onTap: () => taps++),
            ],
          ),
        );
        await tester.tap(find.text('Tap me'));
        await tester.pump();
        expect(taps, 1);
      });
    });
  }
}
