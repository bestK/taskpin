// Type ramp: docs/VISUAL_SPEC.md §2.

import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
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
      expectSpec(TpTypography.figure, 30, 36, FontWeight.w600);
      expectSpec(TpTypography.headline, 48, 56, FontWeight.w700);
      expectSpec(TpTypography.display, 64, 72, FontWeight.w700);
      expectSpec(TpTypography.mono, 13, 20, FontWeight.w400);
    });

    test('the ramp has exactly these roles', () {
      expect(TpTypography.all.keys.toSet(), <String>{
        'caption',
        'body',
        'bodyStrong',
        'bodyLarge',
        'subtitle',
        'title',
        'figure',
        'headline',
        'display',
        'mono',
      });
    });

    test('700 is reserved for the two display roles', () {
      for (final MapEntry<String, TpTextStyleSpec> e
          in TpTypography.all.entries) {
        if (e.key == 'headline' || e.key == 'display') {
          expect(e.value.weight, FontWeight.w700, reason: e.key);
        } else {
          expect(
            e.value.weight == FontWeight.w400 ||
                e.value.weight == FontWeight.w600,
            isTrue,
            reason: e.key,
          );
        }
      }
    });

    test('display roles run tight; UI roles do not', () {
      expect(TpTypography.display.tracking, -0.03);
      expect(TpTypography.headline.tracking, -0.03);
      expect(TpTypography.body.tracking, 0);
      expect(TpTypography.display.toTextStyle().letterSpacing, closeTo(-1.92, 0.001));
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

  group('macOS resolution', () {
    // Names that do NOT resolve to San Francisco on macOS. CoreText maps each
    // of these to Helvetica (verified by CTFontCreateWithName and by a
    // family-name descriptor; see the comment on TpFontFamily.macUi).
    const List<String> notSanFrancisco = <String>[
      'SF Pro Text',
      'SF Pro',
      'SF Mono',
      'CupertinoSystemText',
    ];

    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.macOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('UI roles resolve to the system UI face', () {
      expect(TpFontFamily.macUi, '.AppleSystemUIFont');
      expect(TpTypography.body.toTextStyle().fontFamily, '.AppleSystemUIFont');
      expect(TpTypography.title.toTextStyle().fontFamily, '.AppleSystemUIFont');
    });

    test('mono roles resolve to Menlo', () {
      expect(TpTypography.mono.toTextStyle().fontFamily, 'Menlo');
    });

    test('no macOS family name is one CoreText fails to resolve', () {
      final Iterable<String?> resolved = <TextStyle>[
        for (final TpTextStyleSpec s in TpTypography.all.values)
          s.toTextStyle(),
      ].map((TextStyle t) => t.fontFamily);
      for (final String? name in resolved) {
        expect(notSanFrancisco.contains(name), isFalse, reason: name);
      }
    });

    test('UI fallback is installed macOS faces', () {
      expect(TpTypography.body.toTextStyle().fontFamilyFallback,
          <String>['PingFang SC', 'Helvetica Neue']);
    });

    test('mono fallback is installed macOS faces', () {
      expect(TpTypography.mono.toTextStyle().fontFamilyFallback,
          <String>['Monaco', 'PingFang SC']);
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
