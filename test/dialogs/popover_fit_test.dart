// The macOS popover's fit-to-content path.
//
// The popover hosts the same `DialogWindowScaffold` -> `DialogView` as a dialog
// window, with two switches only it sets: a visible scrollbar, and a
// natural-size report that `popover_window.dart` turns into `resize` calls.
// These tests pin both, plus the reporter's de-duplication and width rule.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin/app/windows/dialog_window.dart';
import 'package:taskpin/app/windows/popover_window.dart';
import 'package:taskpin/features/dialogs/dialog_action.dart';
import 'package:taskpin/features/dialogs/dialog_spec.dart';
import 'package:taskpin/features/dialogs/window_channel.dart';

DialogSpec _tallSpec({int width = 360}) => DialogSpec.fromJson(<String, dynamic>{
      'title': 'Tall',
      'width': width,
      'height': 240,
      'items': <Map<String, dynamic>>[
        for (int i = 0; i < 20; i++)
          <String, dynamic>{'type': 'text', 'value': 'Row $i'},
        <String, dynamic>{'type': 'button', 'value': 'Last'},
      ],
    });

Future<void> _pumpPopover(
  WidgetTester tester,
  DialogSpec spec, {
  required double height,
  required List<Size> reports,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 360,
          height: height,
          child: DialogWindowScaffold(
            spec: spec,
            windowApi: const NoopDialogWindowApi(),
            actions: RecordingDialogActionRunner(),
            showScrollbar: true,
            onNaturalSize: reports.add,
          ),
        ),
      ),
    ),
  );
  // `start()` resolves, the view is built, then one more frame for the
  // post-frame measurement.
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('popover mode: a tall spec scrolls behind a visible scrollbar', (
    WidgetTester tester,
  ) async {
    final List<Size> reports = <Size>[];
    await _pumpPopover(tester, _tallSpec(), height: 240, reports: reports);

    final Scrollbar bar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(bar.thumbVisibility, isTrue);

    final ScrollableState scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    // The scrollbar drives the same position the view scrolls.
    expect(bar.controller, same(scrollable.widget.controller));

    // The natural height is the whole dialog, not the 240 it was given:
    // exactly the given height plus what is scrolled out of view.
    expect(reports, isNotEmpty);
    expect(
      reports.last.height,
      moreOrLessEquals(240 + scrollable.position.maxScrollExtent, epsilon: 0.5),
    );
  });

  testWidgets('popover mode: the reported natural height fits exactly', (
    WidgetTester tester,
  ) async {
    final List<Size> reports = <Size>[];
    await _pumpPopover(tester, _tallSpec(), height: 240, reports: reports);
    final double natural = reports.last.height;

    // Given its natural height, nothing scrolls...
    await _pumpPopover(tester, _tallSpec(), height: natural, reports: reports);
    ScrollableState scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, lessThan(0.5));
    // ...and the measurement did not drift with the new viewport.
    expect(reports.last.height, moreOrLessEquals(natural, epsilon: 0.5));

    // Two pixels less and it overflows: the measurement is tight, not padded.
    await _pumpPopover(tester, _tallSpec(), height: natural - 2, reports: reports);
    scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, greaterThan(1));
  });

  testWidgets('dialog-window mode does not measure or draw a scrollbar', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 360,
            height: 240,
            child: DialogWindowScaffold(
              spec: _tallSpec(),
              windowApi: const NoopDialogWindowApi(),
              actions: RecordingDialogActionRunner(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(Scrollbar), findsNothing);
    expect(find.byType(RawScrollbar), findsNothing);
  });

  group('PopoverResizeReporter', () {
    test('sends once, drops sub-pixel repeats, resends after reset', () async {
      final List<Size> sent = <Size>[];
      final PopoverResizeReporter r = PopoverResizeReporter(
        spec: () => _tallSpec(),
        send: (double w, double h) async => sent.add(Size(w, h)),
      );

      r.report(const Size(300, 500.2));
      await Future<void>.delayed(Duration.zero);
      expect(sent, <Size>[const Size(360, 501)]);

      // Within 1 px of what was sent: the popover already has it.
      r.report(const Size(300, 500.9));
      await Future<void>.delayed(Duration.zero);
      expect(sent, hasLength(1));

      // Several reports in one turn coalesce to the latest.
      r.report(const Size(300, 600));
      r.report(const Size(300, 700));
      await Future<void>.delayed(Duration.zero);
      expect(sent.last, const Size(360, 700));
      expect(sent, hasLength(2));

      // A new spec resets the host to the spec size, so the same value goes
      // out again.
      r.reset();
      r.report(const Size(300, 700));
      await Future<void>.delayed(Duration.zero);
      expect(sent, hasLength(3));
    });

    test('width: spec width wins; the default shrinks to content only', () {
      // An explicit width is honoured either way.
      expect(
        PopoverResizeReporter.targetSize(_tallSpec(width: 520), const Size(200, 100)),
        const Size(520, 100),
      );
      // No width (the parser's default): narrow content stays narrow...
      final DialogSpec noWidth = DialogSpec.fromJson(<String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'text', 'value': 'x'},
        ],
      });
      expect(
        PopoverResizeReporter.targetSize(noWidth, const Size(180.3, 100)),
        const Size(181, 100),
      );
      // ...and wide content does not grow past the default.
      expect(
        PopoverResizeReporter.targetSize(noWidth, const Size(900, 100)),
        Size(kDialogDefaultWidth.toDouble(), 100),
      );
    });
  });
}
