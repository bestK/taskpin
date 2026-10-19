// Bar token tests.
//
// This file guards the FROZEN contract. Every assertion here corresponds to a
// number that is hand-written a second time in C++ and a third time in Swift,
// so a failure means the three implementations have diverged.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin_design/taskpin_design.dart';

void main() {
  group('frozen token list', () {
    test('is exactly the documented set', () {
      // The plan's list, verbatim. Adding a token is a cross-language change;
      // this test makes it a deliberate one.
      const List<String> expected = <String>[
        'bar/bg',
        'bar/bgHover',
        'bar/hairline',
        'bar/separator',
        'bar/state.running',
        'bar/state.error',
        'bar/state.stale',
        'bar/icon',
        'bar/label',
        'bar/value',
      ];

      expect(kFrozenBarTokenNames, expected);
      expect(TpBarColors.all.keys.toSet(), expected.toSet());
    });

    test('the list is short', () {
      // "这个列表要短且冻结" — each token costs two native implementations.
      // 10 is the budget; if this needs raising, the design has drifted.
      expect(kFrozenBarTokenNames.length, lessThanOrEqualTo(10));
    });

    test('the flat list and the map agree', () {
      expect(TpBarColors.all.keys.toList(), kFrozenBarTokenNames);
    });

    test('every token is fully specified', () {
      for (final MapEntry<String, Color> e in TpBarColors.all.entries) {
        // A token with no value would silently render as transparent.
        expect(e.value, isNotNull, reason: '${e.key} is null');
      }
    });
  });

  group('token values', () {
    test('running state is transparent by design', () {
      // Health is the ABSENCE of a signal. A healthy item shows nothing so the
      // eye is drawn only to problems.
      expect(TpBarColors.stateRunning.toARGB32() & 0xFF000000, 0);
    });

    test('error and stale keep the frozen bar hues', () {
      // The bar palette is frozen in bar_tokens.dart and no longer shares the
      // app status colours.
      expect(TpBarColors.stateError.toARGB32() & 0xFFFFFF, 0xF85149);
      expect(TpBarColors.stateStale.toARGB32() & 0xFFFFFF, 0xD29922);
    });

    test('separator is 20% alpha', () {
      // The plan: "1x14px、20% alpha 的竖线". 20% of 255 is 51 = 0x33.
      final int alpha = (TpBarColors.separator.toARGB32() >> 24) & 0xFF;
      expect(alpha, 0x33);
    });

    test('bg is OPAQUE, matching what the native renderer draws', () {
      // This assertion used to be the opposite — it required an alpha of 0,
      // arguing the strip should let the taskbar show through. That was wrong
      // and it hid a real divergence: `native/win/bar_tokens.h` has always
      // defined `kColorBg` as opaque near-black, so the Flutter preview strip
      // was drawing a transparent background while the real taskbar strip drew
      // an opaque one. The preview exists specifically so the manager shows
      // what the taskbar draws, so opacity must agree.
      //
      // Per-item transparency is a different thing entirely and still works:
      // `bar_bg_color` in config.json, when its alpha is below 255, tells the
      // native bar to switch to a layered window. That is the item's colour,
      // not this token.
      expect((TpBarColors.bg.toARGB32() >> 24) & 0xFF, 0xFF);
    });

    test('value is the brightest default, label is dimmer', () {
      // Values are the point of the strip, so they out-shine their labels.
      expect(
        _luminance(TpBarColors.value),
        greaterThan(_luminance(TpBarColors.label)),
      );
    });
  });

  group('windows metrics', () {
    test('match the plan', () {
      const TpBarMetrics m = TpBarMetrics.windows;
      expect(m.platform, TpBarPlatform.windows);
      expect(m.padHorizontal, 8);
      expect(m.padVertical, 6);
      expect(m.iconSize, 16);
      expect(m.maxLines, 2);
      expect(m.separatorWidth, 1);
      expect(m.separatorHeight, 14);
      expect(m.separatorGap, 6);
      expect(m.stateStripWidth, 2);
      expect(m.widthStep, 5);
      expect(m.minWidth, 50);
      expect(m.maxWidth, 800);
    });

    test('taskbar segments are square', () {
      expect(TpBarMetrics.windows.radius, 0);
    });

    test('height is one of the real taskbar heights', () {
      // Win11 @100% is 48, Win10 is 40. The renderer must handle both.
      expect(
        TpBarMetrics.windowsKnownTaskbarHeights,
        contains(TpBarMetrics.windows.height),
      );
      expect(TpBarMetrics.windowsKnownTaskbarHeights, <double>[40, 48]);
    });

    test('allows two lines, per the existing double-line layout', () {
      expect(TpBarMetrics.windows.maxLines, 2);
    });
  });

  group('macos metrics', () {
    test('match the plan', () {
      const TpBarMetrics m = TpBarMetrics.macOS;
      expect(m.platform, TpBarPlatform.macOS);
      expect(m.height, 24);
      expect(m.padHorizontal, 6);
      expect(m.radius, 6);
      expect(m.iconSize, 16);
      expect(m.stateStripWidth, 2);
    });

    test('is one line only', () {
      // "菜单栏高 24pt：最多一行，字号钳制，超长省略号截断"
      expect(TpBarMetrics.macOS.maxLines, 1);
    });

    test('is shorter than the Windows strip', () {
      expect(TpBarMetrics.macOS.height, lessThan(TpBarMetrics.windows.height));
    });
  });

  group('of()', () {
    test('resolves by platform', () {
      expect(TpBarMetrics.of(TpBarPlatform.windows), TpBarMetrics.windows);
      expect(TpBarMetrics.of(TpBarPlatform.macOS), TpBarMetrics.macOS);
    });
  });

  group('theme integration', () {
    testWidgets('the theme carries the bar colours and platform',
        (WidgetTester tester) async {
      final TaskPinTheme win = TaskPinTheme.dark();
      expect(win.barColors, isA<TpBarColors>());
      expect(win.barPlatform, TpBarPlatform.windows);
      expect(win.barMetrics, TpBarMetrics.windows);

      final TaskPinTheme mac =
          TaskPinTheme.dark(barPlatform: TpBarPlatform.macOS);
      expect(mac.barMetrics, TpBarMetrics.macOS);
    });

    testWidgets('the bar does not lerp during a theme transition',
        (WidgetTester tester) async {
      // A half-animated taskbar strip is not something we want to be able to
      // produce, so the bar snaps at the midpoint.
      final TaskPinTheme dark =
          TaskPinTheme.dark(barPlatform: TpBarPlatform.windows);
      final TaskPinTheme light =
          TaskPinTheme.light(barPlatform: TpBarPlatform.macOS);

      expect(dark.lerp(light, 0.25).barPlatform, TpBarPlatform.windows);
      expect(dark.lerp(light, 0.75).barPlatform, TpBarPlatform.macOS);
    });
  });
}

double _luminance(Color c) {
  final int argb = c.toARGB32();
  // A cheap perceptual stand-in: enough to assert an ordering, not a contrast
  // ratio. Keeps this file free of a pow import for one comparison.
  return 0.299 * ((argb >> 16) & 0xFF) +
      0.587 * ((argb >> 8) & 0xFF) +
      0.114 * (argb & 0xFF);
}
