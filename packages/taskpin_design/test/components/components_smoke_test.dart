// Smoke tests: every component builds, in both themes, without throwing.
//
// These are not golden tests (those need a GPU-less rasteriser and the
// `--update-goldens` run, which happens once the SDK is installed). They are
// the cheap first line of defence: a component that throws on build, asserts
// on layout, or crashes on an empty input fails here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin_design/taskpin_design.dart';

Future<void> pumpBoth(
  WidgetTester tester,
  Widget Function() build, {
  Size size = const Size(900, 1400),
}) async {
  for (final bool dark in <bool>[true, false]) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme:
            (dark ? TaskPinTheme.dark() : TaskPinTheme.light()).toThemeData(),
        home: Scaffold(
          body: SingleChildScrollView(child: build()),
        ),
      ),
    );
    await tester.pump();
  }
}

void main() {
  group('shell', () {
    testWidgets('NavRail renders destinations and badges',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => TpNavRail(
          destinations: <TpNavDestination>[
            TpNavDestination(
              label: 'Signals',
              icon: TpIcons.signals,
              route: '/signals',
            ),
            TpNavDestination(
              label: 'Market',
              icon: TpIcons.market,
              route: '/market',
              badgeCount: 3,
            ),
          ],
          selectedRoute: '/market',
          onSelect: (_) {},
        ),
      );

      expect(find.text('Signals'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('NavRail collapsed hides labels', (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => TpNavRail(
          destinations: <TpNavDestination>[
            TpNavDestination(
              label: 'Signals',
              icon: TpIcons.signals,
              route: '/signals',
            ),
          ],
          selectedRoute: '/signals',
          collapsed: true,
          onSelect: (_) {},
        ),
      );

      expect(find.text('Signals'), findsNothing);
    });

    testWidgets('AppShell composes rail and content',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => SizedBox(
          height: 400,
          child: TpAppShell(
            rail: const SizedBox(width: 60),
            child: const Text('content'),
          ),
        ),
      );

      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('PageHeader renders title, description and actions',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => TpPageHeader(
          title: 'Signals',
          description: 'Everything you pinned.',
          actions: <Widget>[TpButton(label: 'Add', onPressed: () {})],
        ),
      );

      expect(find.text('Signals'), findsOneWidget);
      expect(find.text('Everything you pinned.'), findsOneWidget);
    });

    testWidgets('Toolbar lays out leading and trailing',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => TpToolbar(
          leading: <Widget>[TpButton(label: 'L', onPressed: () {})],
          trailing: <Widget>[TpButton(label: 'R', onPressed: () {})],
        ),
      );

      expect(find.text('L'), findsOneWidget);
      expect(find.text('R'), findsOneWidget);
    });

    testWidgets('SplitPane renders both panes', (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => SizedBox(
          height: 200,
          child: TpSplitPane(
            master: const Text('master'),
            detail: const Text('detail'),
          ),
        ),
      );

      expect(find.text('master'), findsOneWidget);
      expect(find.text('detail'), findsOneWidget);
    });
  });

  group('status', () {
    testWidgets('StatusDot renders for every kind',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => Column(
          children: <Widget>[
            for (final TpStateKind k in TpStateKind.values) TpStatusDot(kind: k),
          ],
        ),
      );

      expect(find.byType(TpStatusDot), findsNWidgets(5));
    });

    testWidgets('StatusDot with a label exposes semantics',
        (WidgetTester tester) async {
      // Semantics must be explicitly enabled in a widget test.
      //
      // The handle is disposed at the END OF THE BODY, not via `addTearDown`:
      // `flutter_test` verifies all handles are disposed before teardowns run,
      // so a teardown-registered dispose is always too late and the test fails
      // with "A SemanticsHandle was active at the end of the test" even though
      // the assertion itself passed.
      final SemanticsHandle handle = tester.ensureSemantics();

      await pumpBoth(
        tester,
        () => const TpStatusDot(
          kind: TpStateKind.success,
          tooltip: 'Healthy',
        ),
      );

      expect(find.bySemanticsLabel('Healthy'), findsOneWidget);

      handle.dispose();
    });

    testWidgets('StatusPill renders its label',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => const TpStatusPill(
          label: 'RUNNING',
          kind: TpStateKind.success,
        ),
      );

      expect(find.text('RUNNING'), findsOneWidget);
    });
  });

  group('IntervalBadge formatting', () {
    test('picks the shortest exact unit', () {
      expect(TpIntervalBadge.format(const Duration(milliseconds: 500)), '500 ms');
      expect(TpIntervalBadge.format(const Duration(seconds: 5)), '5 s');
      expect(TpIntervalBadge.format(const Duration(seconds: 90)), '1 m 30 s');
      expect(TpIntervalBadge.format(const Duration(minutes: 5)), '5 m');
      expect(TpIntervalBadge.format(const Duration(minutes: 90)), '1 h 30 m');
      expect(TpIntervalBadge.format(const Duration(hours: 2)), '2 h');
    });

    testWidgets('renders', (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => const TpIntervalBadge(interval: Duration(seconds: 30)),
      );
      expect(find.text('30 s'), findsOneWidget);
    });
  });

  group('RelativeTime formatting', () {
    test('formats each magnitude', () {
      expect(TpRelativeTime.formatAge(const Duration(seconds: 0)), 'just now');
      expect(TpRelativeTime.formatAge(const Duration(seconds: 12)), '12s ago');
      expect(TpRelativeTime.formatAge(const Duration(minutes: 3)), '3m ago');
      expect(TpRelativeTime.formatAge(const Duration(hours: 2)), '2h ago');
      expect(TpRelativeTime.formatAge(const Duration(days: 3)), '3d ago');
    });

    testWidgets('renders a fixed age without ticking',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => TpRelativeTime(
          timestamp: DateTime(2026, 1, 1, 12, 0, 0),
          now: DateTime(2026, 1, 1, 12, 0, 30),
        ),
      );

      expect(find.text('30s ago'), findsOneWidget);
    });

    testWidgets('shows a warning glyph when stale',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => TpRelativeTime(
          timestamp: DateTime(2026, 1, 1, 12, 0, 0),
          now: DateTime(2026, 1, 1, 12, 1, 0),
          staleAfter: const Duration(seconds: 10),
        ),
      );

      expect(find.byIcon(TpIcons.warning), findsOneWidget);
    });
  });

  group('Sparkline', () {
    testWidgets('renders with data', (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => const TpSparkline(
          values: <double?>[1, 5, 3, 9, 2],
          width: 100,
          height: 30,
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('renders an empty series without throwing',
        (WidgetTester tester) async {
      // A flat baseline rather than nothing, so the card's layout is stable.
      await pumpBoth(
        tester,
        () => const TpSparkline(values: <double?>[], width: 100, height: 30),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('renders a constant series without dividing by zero',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => const TpSparkline(
          values: <double?>[5, 5, 5, 5],
          width: 100,
          height: 30,
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('handles a single point', (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => const TpSparkline(values: <double?>[5], width: 100, height: 30),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });
  });

  group('data', () {
    testWidgets('SignalCard renders name, value and unit',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => TpSignalCard(
          name: 'CPU',
          kind: TpStateKind.success,
          value: '42',
          unit: '%',
          interval: const Duration(seconds: 2),
          lastUpdated: DateTime(2026, 1, 1, 12, 0, 0),
          source: 'system_monitor.lua',
        ),
      );

      expect(find.text('CPU'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('%'), findsOneWidget);
    });

    testWidgets('SignalCard shows an error instead of a value',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => const TpSignalCard(
          name: 'Balance',
          kind: TpStateKind.critical,
          value: '—',
          error: 'attempt to index a nil value',
        ),
      );

      expect(find.text('attempt to index a nil value'), findsOneWidget);
    });

    testWidgets('SignalGrid renders rows', (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => TpSignalGrid(
          rows: <TpSignalRow>[
            TpSignalRow(
              name: 'CPU',
              kind: TpStateKind.success,
              value: '42',
              unit: '%',
              interval: const Duration(seconds: 2),
              lastUpdated: DateTime(2026, 1, 1, 12, 0, 0),
            ),
          ],
        ),
      );

      expect(find.text('CPU'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('SignalGrid renders its empty state',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => const TpSignalGrid(rows: <TpSignalRow>[]),
      );

      expect(find.byType(TpEmptyState), findsOneWidget);
    });

    testWidgets('KeyValueList renders pairs', (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => const TpKeyValueList(
          entries: <String, String>{'id': 'zeeho', 'type': 'lua'},
        ),
      );

      expect(find.text('id'), findsOneWidget);
      expect(find.text('zeeho'), findsOneWidget);
    });
  });

  group('feedback', () {
    testWidgets('all button variants render', (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => Wrap(
          children: <Widget>[
            for (final TpButtonVariant v in TpButtonVariant.values)
              TpButton(label: v.name, variant: v, onPressed: () {}),
          ],
        ),
      );

      expect(find.text('primary'), findsOneWidget);
      expect(find.text('standard'), findsOneWidget);
      expect(find.text('text'), findsOneWidget);
    });

    testWidgets('a disabled button does not fire', (WidgetTester tester) async {
      int taps = 0;
      await pumpBoth(
        tester,
        () => TpButton(label: 'Nope', enabled: false, onPressed: () => taps++),
      );

      await tester.tap(find.text('Nope'));
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('InlineBanner renders title, message and actions',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => TpInfoBar(
          title: 'Script failed',
          message: 'nil value',
          actions: <Widget>[TpButton(label: 'Retry', onPressed: () {})],
        ),
      );

      expect(find.text('Script failed'), findsOneWidget);
      expect(find.text('nil value'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('EmptyState renders', (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => const TpEmptyState(title: 'Nothing here', message: 'Add one'),
      );

      expect(find.text('Nothing here'), findsOneWidget);
    });

    testWidgets('ErrorState renders detail and retry',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => TpErrorState(
          title: 'Failed',
          message: 'Timed out',
          detail: 'SocketException',
          onRetry: () {},
        ),
      );

      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('SocketException'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('Skeleton and ProgressBar render',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => const Column(
          children: <Widget>[
            TpSkeleton(height: 16),
            TpSkeletonLines(count: 3),
            TpProgressBar(value: 0.5),
            TpProgressBar.indeterminate(),
          ],
        ),
      );

      expect(find.byType(TpProgressBar), findsNWidgets(2));
    });

    testWidgets('ConfirmDialog shows and returns a result',
        (WidgetTester tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          theme: TaskPinTheme.dark().toThemeData(),
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: TpButton(
                  label: 'Open',
                  onPressed: () async {
                    result = await TpConfirmDialog.show(
                      context,
                      title: 'Delete?',
                      message: 'This cannot be undone.',
                      destructive: true,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Delete?'), findsOneWidget);
      expect(find.text('This cannot be undone.'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('ToastHost stacks toasts', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TaskPinTheme.dark().toThemeData(),
          home: TpToastHost(
            child: Builder(
              builder: (BuildContext context) => Scaffold(
                body: Center(
                  child: TpButton(
                    label: 'Toast',
                    onPressed: () => TpToastHost.show(
                      context,
                      const TpToast(message: 'Saved'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Saved'), findsOneWidget);

      // Let the auto-dismiss timer fire so the test does not end with a
      // pending timer.
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('forms', () {
    testWidgets('TextField renders label, hint and error',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => const TpTextField(
          label: 'Bar width',
          hint: 'px',
          error: 'Required',
        ),
      );

      expect(find.text('Bar width'), findsOneWidget);
      expect(find.text('Required'), findsOneWidget);
    });

    testWidgets('TextField accepts typing', (WidgetTester tester) async {
      String? changed;
      await pumpBoth(
        tester,
        () => TpTextField(label: 'Name', onChanged: (String v) => changed = v),
      );

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      expect(changed, 'hello');
    });

    testWidgets('TextArea renders', (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => const TpTextArea(label: 'Headers', rows: 4),
      );

      expect(find.text('Headers'), findsOneWidget);
    });

    testWidgets('NumberField steps with its buttons',
        (WidgetTester tester) async {
      num? value;
      await pumpBoth(
        tester,
        () => TpNumberField(
          value: 10,
          label: 'Width',
          step: 5,
          onChanged: (num? v) => value = v,
        ),
      );

      await tester.tap(find.byIcon(TpIcons.chevronUp));
      await tester.pump();
      expect(value, 15);

      await tester.tap(find.byIcon(TpIcons.chevronDown));
      await tester.pump();
      expect(value, 10);
    });

    testWidgets('NumberField clamps to min and max',
        (WidgetTester tester) async {
      num? value;
      await pumpBoth(
        tester,
        () => TpNumberField(
          value: 795,
          min: 50,
          max: 800,
          step: 5,
          label: 'Width',
          onChanged: (num? v) => value = v,
        ),
      );

      await tester.tap(find.byIcon(TpIcons.chevronUp));
      await tester.pump();
      expect(value, 800);

      await tester.tap(find.byIcon(TpIcons.chevronUp));
      await tester.pump();
      expect(value, 800, reason: 'must not exceed max');
    });

    testWidgets('IntervalField converts 300000 ms to 5 m',
        (WidgetTester tester) async {
      // The whole reason the field exists.
      await pumpBoth(
        tester,
        () => TpIntervalField(
          value: const Duration(milliseconds: 300000),
          label: 'Interval',
          onChanged: (_) {},
        ),
      );

      expect(find.text('5'), findsOneWidget);
      expect(find.text('m'), findsWidgets);
    });

    test('IntervalField picks the largest exact unit', () {
      expect(
        TpIntervalField.bestUnit(const Duration(milliseconds: 500)).label,
        'ms',
      );
      expect(
        TpIntervalField.bestUnit(const Duration(seconds: 5)).label,
        's',
      );
      expect(
        TpIntervalField.bestUnit(const Duration(milliseconds: 300000)).label,
        'm',
      );
      expect(
        TpIntervalField.bestUnit(const Duration(hours: 2)).label,
        'h',
      );
    });

    testWidgets('ColorField shows the inherit state',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => TpColorField(
          wireValue: kColorInherit,
          label: 'Background',
          onChanged: (_) {},
        ),
      );

      expect(find.text('Inherit default'), findsOneWidget);
    });

    testWidgets('Select renders and opens', (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => TpSelect<String>(
          value: 'a',
          label: 'Pick',
          items: const <TpSelectItem<String>>[
            TpSelectItem<String>(value: 'a', label: 'Alpha'),
            TpSelectItem<String>(value: 'b', label: 'Beta'),
          ],
          onChanged: (_) {},
        ),
      );

      expect(find.text('Alpha'), findsOneWidget);
    });

    testWidgets('Select tolerates a value missing from the items',
        (WidgetTester tester) async {
      // DropdownButton asserts on this; the guard must hold.
      await pumpBoth(
        tester,
        () => TpSelect<String>(
          value: 'zzz',
          label: 'Pick',
          hint: 'Choose',
          items: const <TpSelectItem<String>>[
            TpSelectItem<String>(value: 'a', label: 'Alpha'),
          ],
          onChanged: (_) {},
        ),
      );

      expect(find.text('Choose'), findsOneWidget);
    });

    testWidgets('Switch toggles', (WidgetTester tester) async {
      bool? value;
      await pumpBoth(
        tester,
        () => TpSwitch(
          value: false,
          label: 'Enabled',
          onChanged: (bool v) => value = v,
        ),
      );

      await tester.tap(find.text('Enabled'));
      await tester.pump();
      expect(value, isTrue);
    });

    testWidgets('SegmentedControl selects', (WidgetTester tester) async {
      int? value;
      await pumpBoth(
        tester,
        () => TpSegmentedControl<int>(
          value: 0,
          segments: const <TpSelectItem<int>>[
            TpSelectItem<int>(value: 0, label: 'A'),
            TpSelectItem<int>(value: 1, label: 'B'),
          ],
          onChanged: (int v) => value = v,
        ),
      );

      await tester.tap(find.text('B'));
      await tester.pump();
      expect(value, 1);
    });

    testWidgets('ParamField renders every declared type',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => Column(
          children: <Widget>[
            for (final TpParamType t in TpParamType.values)
              TpParamField(
                param: TpParamValue(
                  decl: TpParamDecl(key: 'K', type: t, label: t.wireName),
                  value: '',
                ),
                onChanged: (_) {},
              ),
          ],
        ),
      );

      expect(find.text('string'), findsOneWidget);
      expect(find.text('number'), findsOneWidget);
      expect(find.text('boolean'), findsOneWidget);
      expect(find.text('color'), findsOneWidget);
      expect(find.text('path'), findsOneWidget);
    });

    testWidgets('PathPicker shows the path and a browse button',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => TpPathPicker(
          value: 'scripts/zeeho.lua',
          label: 'Script',
          onChanged: (_) {},
          onBrowse: () async => null,
        ),
      );

      expect(find.text('scripts/zeeho.lua'), findsOneWidget);
      expect(find.text('Browse'), findsOneWidget);
    });

    testWidgets('PathPicker shows a placeholder when empty',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => TpPathPicker(
          value: '',
          placeholder: 'No file selected',
          onChanged: (_) {},
        ),
      );

      expect(find.text('No file selected'), findsOneWidget);
    });

    testWidgets('HeaderListEditor adds a row', (WidgetTester tester) async {
      List<TpHeaderEntry> entries = <TpHeaderEntry>[];
      await pumpBoth(
        tester,
        () => TpHeaderListEditor(
          entries: entries,
          onChanged: (List<TpHeaderEntry> next) => entries = next,
        ),
      );

      await tester.tap(find.text('Add header'));
      await tester.pump();
      expect(entries.length, 1);
    });
  });

  group('code', () {
    testWidgets('LuaEditor renders a gutter with line numbers',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => const TpLuaEditor(
          initialValue: 'line one\nline two\nline three',
          minLines: 3,
        ),
      );

      expect(find.text('1'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('LuaEditor can hide the gutter', (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => const TpLuaEditor(
          initialValue: 'x',
          gutter: false,
          minLines: 2,
        ),
      );

      expect(find.text('1'), findsNothing);
    });

    testWidgets('ResponsePreview renders status and body',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => const TpResponsePreview(
          statusCode: 200,
          contentType: 'application/json',
          body: '{"a":1}',
        ),
      );

      expect(find.text('200'), findsOneWidget);
      expect(find.textContaining('{"a":1}'), findsOneWidget);
    });

    testWidgets('ExpressionEditor renders path chips',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => TpExpressionEditor(
          value: r'$.a',
          availablePaths: const <String>[r'$.b.c'],
          onChanged: (_) {},
        ),
      );

      expect(find.text(r'$.b.c'), findsOneWidget);
    });
  });

  group('bar', () {
    testWidgets('BarPreviewStrip renders Windows metrics',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => const TpBarPreviewStrip(
          content: TpBarContent(
            spans: <TpBarSpan>[
              TpBarSpan(text: 'CPU'),
              TpBarSpan(text: '42%'),
            ],
          ),
        ),
      );

      expect(find.text('CPU'), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);
    });

    testWidgets('BarPreviewStrip renders macOS one-line metrics',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => const TpBarPreviewStrip(
          platform: TpBarPlatform.macOS,
          content: TpBarContent(
            spans: <TpBarSpan>[
              TpBarSpan(text: 'CPU'),
              TpBarSpan(text: '42%'),
              // This second line must be dropped on macOS.
              TpBarSpan(text: 'MEM', newline: true),
            ],
          ),
        ),
      );

      expect(find.text('CPU'), findsOneWidget);
      expect(find.text('MEM'), findsNothing);
    });

    testWidgets('BarPreviewStrip renders every state',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => Column(
          children: <Widget>[
            for (final TpBarState s in TpBarState.values)
              TpBarPreviewStrip(
                state: s,
                content: const TpBarContent(
                  spans: <TpBarSpan>[TpBarSpan(text: 'X')],
                ),
              ),
          ],
        ),
      );

      expect(find.byType(TpBarPreviewStrip), findsNWidgets(4));
    });

    testWidgets('SpanInspector renders one row per span',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => TpSpanInspector(
          spans: const <TpBarSpan>[
            TpBarSpan(text: 'CPU'),
            TpBarSpan(text: '42%'),
          ],
          onChanged: (_) {},
        ),
      );

      expect(find.text('Span 1'), findsOneWidget);
      expect(find.text('Span 2'), findsOneWidget);
    });

    testWidgets('SpanInspector handles an empty span list',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => TpSpanInspector(
          spans: const <TpBarSpan>[],
          onChanged: (_) {},
        ),
      );

      expect(find.text('This script returns no spans.'), findsOneWidget);
    });

    testWidgets('DialogSpecPreview renders every item type',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => const TpDialogSpecPreview(
          items: <TpDialogSpecItem>[
            TpDialogSpecItem(type: TpDialogItemType.text, text: 'Hello'),
            TpDialogSpecItem(type: TpDialogItemType.hr),
            TpDialogSpecItem(
              type: TpDialogItemType.table,
              rows: <List<String>>[
                <String>['A', 'B'],
                <String>['1', '2'],
              ],
            ),
            TpDialogSpecItem(type: TpDialogItemType.image, text: 'chart.png'),
            TpDialogSpecItem(type: TpDialogItemType.button, text: 'Open'),
          ],
        ),
      );

      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('chart.png'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('TaskbarFlightStrip renders pinned items and dock elements',
        (WidgetTester tester) async {
      await pumpBoth(
        tester,
        () => TpTaskbarFlightStrip(
          items: const <TpTaskbarFlightStripItem>[
            TpTaskbarFlightStripItem(
              name: 'CPU Monitor',
              spans: <TpBarSpan>[TpBarSpan(text: 'CPU: 12%')],
              pinned: true,
              itemIndex: 0,
            ),
            TpTaskbarFlightStripItem(
              name: 'Crypto Ticker',
              pinned: false,
              itemIndex: 1,
            ),
          ],
          selectedIndex: 0,
        ),
      );

      expect(find.text('TASKBAR DOCK'), findsOneWidget);
      expect(find.text('CPU: 12%'), findsOneWidget);
      expect(find.text('1/16 Pinned'), findsOneWidget);
    });
  });
}
