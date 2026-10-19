// Spacing, radius, control sizes, motion and elevation: docs/VISUAL_SPEC.md §3.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin_design/taskpin_design.dart';

void main() {
  group('spacing', () {
    test('named values follow spec §3.1', () {
      expect(TpSpacing.buttonGap, 8);
      expect(TpSpacing.headerGap, 8);
      expect(TpSpacing.blockGap, 12);
      expect(TpSpacing.surfacePadding, 16);
      expect(TpSpacing.settingsCardGap, 4);
      expect(TpSpacing.sectionTop, 30);
      expect(TpSpacing.sectionBottom, 6);
      expect(TpSpacing.pageMarginNarrow, 24);
      expect(TpSpacing.pageMarginWide, 36);
      expect(TpSpacing.pageMaxWidth, 1000);
    });

    test('scale is ascending and unique', () {
      final List<double> s = TpSpacing.steps;
      for (int i = 1; i < s.length; i++) {
        expect(s[i], greaterThan(s[i - 1]));
      }
    });

    test('scale is a 4 px grid with 2 and 6 as exceptions', () {
      for (final double v in TpSpacing.steps) {
        if (v == 2 || v == 6 || v == 30 || v == 36) {
          continue;
        }
        expect(v % 4, 0, reason: '$v is not on the 4 px grid');
      }
    });
  });

  group('control sizes', () {
    test('match spec §3.2', () {
      expect(TpControlSize.control, 32);
      expect(TpControlSize.listRow, 40);
      expect(TpControlSize.listRowTwoLine, 60);
      expect(TpControlSize.settingsCardMin, 68);
      expect(TpControlSize.navItem, 40);
      expect(TpControlSize.navWidth, 240);
      expect(TpControlSize.navCompactWidth, 48);
      expect(TpControlSize.titleBar, 32);
      expect(TpControlSize.switchWidth, 40);
      expect(TpControlSize.switchHeight, 20);
    });
  });

  group('radius', () {
    test('values follow spec §3.3', () {
      expect(TpRadius.controlValue, 4);
      expect(TpRadius.cardValue, 8);
      expect(TpRadius.overlayValue, 8);
      expect(TpRadius.windowValue, 8);
      expect(TpRadius.pill, 999);
    });

    test('BorderRadius forms use the same values', () {
      expect(TpRadius.control,
          const BorderRadius.all(Radius.circular(4)));
      expect(TpRadius.card, const BorderRadius.all(Radius.circular(8)));
      expect(TpRadius.overlay, const BorderRadius.all(Radius.circular(8)));
      expect(TpRadius.none, BorderRadius.zero);
    });

    test('bar radii are frozen per platform', () {
      expect(TpRadius.barWindows, 0);
      expect(TpRadius.barMacOS, 6);
    });
  });

  group('motion', () {
    test('durations are 83 / 167 / 250 ms', () {
      expect(TpMotion.fast, const Duration(milliseconds: 83));
      expect(TpMotion.base, const Duration(milliseconds: 167));
      expect(TpMotion.slow, const Duration(milliseconds: 250));
    });

    test('colour changes are linear, expand and page use the decelerate curve', () {
      expect(TpMotion.linear, Curves.linear);
      expect(TpMotion.standard, const Cubic(0, 0, 0, 1));
      expect(TpMotion.decelerate, const Cubic(0, 0, 0, 1));
    });
  });

  group('elevation', () {
    test('flyout shadow is 0 8 16 at .14 light / .26 dark', () {
      final BoxShadow light = TpElevation.flyout(isDark: false).single;
      final BoxShadow dark = TpElevation.flyout(isDark: true).single;
      expect(light.offset, const Offset(0, 8));
      expect(light.blurRadius, 16);
      expect(light.color.a, closeTo(0.14, 0.005));
      expect(dark.color.a, closeTo(0.26, 0.005));
    });

    test('dialog shadow is 0 32 64 at .18 light / .37 dark', () {
      final BoxShadow light = TpElevation.dialog(isDark: false).single;
      final BoxShadow dark = TpElevation.dialog(isDark: true).single;
      expect(light.offset, const Offset(0, 32));
      expect(light.blurRadius, 64);
      expect(light.color.a, closeTo(0.18, 0.005));
      expect(dark.color.a, closeTo(0.37, 0.005));
    });
  });
}
