// Type ramp: docs/VISUAL_SPEC.md §2.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin_design/taskpin_design.dart';

void main() {
  group('type ramp matches spec §2.2', () {
    test('size, line height and weight', () {
      void expectSpec(TpTextStyleSpec s, double size, double line, FontWeight w) {
        expect(s.size, size);
        expect(s.lineHeight, line);
        expect(s.weight, w);
      }

      expectSpec(TpTypography.caption, 12, 16, FontWeight.w400);
      expectSpec(TpTypography.body, 14, 20, FontWeight.w400);
      expectSpec(TpTypography.bodyStrong, 14, 20, FontWeight.w600);
      expectSpec(TpTypography.bodyLarge, 18, 24, FontWeight.w400);
      expectSpec(TpTypography.subtitle, 20, 28, FontWeight.w600);
      expectSpec(TpTypography.title, 28, 36, FontWeight.w600);
      expectSpec(TpTypography.mono, 13, 20, FontWeight.w400);
    });

    test('only the 7 roles exist', () {
      expect(TpTypography.all.keys.toSet(), <String>{
        'caption',
        'body',
        'bodyStrong',
        'bodyLarge',
        'subtitle',
        'title',
        'mono',
      });
    });

    test('only weights 400 and 600 are used', () {
      for (final TpTextStyleSpec s in TpTypography.all.values) {
        expect(
          s.weight == FontWeight.w400 || s.weight == FontWeight.w600,
          isTrue,
        );
      }
    });

    test('no size is below 12', () {
      for (final TpTextStyleSpec s in TpTypography.all.values) {
        expect(s.size, greaterThanOrEqualTo(12));
      }
    });
  });

  group('font families', () {
    test('UI text uses Segoe UI Variable Text up to 18 px', () {
      expect(TpTypography.caption.family, 'Segoe UI Variable Text');
      expect(TpTypography.body.family, 'Segoe UI Variable Text');
      expect(TpTypography.bodyLarge.family, 'Segoe UI Variable Text');
    });

    test('UI display uses Segoe UI Variable Display from 20 px', () {
      expect(TpTypography.subtitle.family, 'Segoe UI Variable Display');
      expect(TpTypography.title.family, 'Segoe UI Variable Display');
    });

    test('UI fallback chain', () {
      expect(TpFontFamily.uiFallback,
          <String>['Segoe UI', 'Microsoft YaHei UI', 'PingFang SC']);
      expect(TpTypography.body.toTextStyle().fontFamilyFallback,
          TpFontFamily.uiFallback);
    });

    test('mono uses Cascadia Mono with its fallback chain', () {
      expect(TpTypography.mono.family, 'Cascadia Mono');
      expect(TpFontFamily.monoFallback,
          <String>['Consolas', 'SF Mono', 'Menlo', 'Microsoft YaHei UI']);
    });
  });

  group('style conversion', () {
    test('line height becomes a multiplier of the font size', () {
      final TextStyle s = TpTypography.body.toTextStyle();
      expect(s.fontSize, 14);
      expect(s.height, closeTo(20 / 14, 1e-9));
    });
  });

  group('tabular figures', () {
    test('title and mono default to tabular figures', () {
      expect(TpTypography.tabularRoles, containsAll(<String>['title', 'mono']));
      expect(
        TpTypography.mono.toTextStyle().fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    test('body does not default to tabular figures', () {
      expect(TpTypography.body.toTextStyle().fontFeatures, isNull);
    });

    test('tabular can be forced on for a body role', () {
      expect(
        TpTypography.body.toTextStyle(tabular: true).fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });
  });
}
