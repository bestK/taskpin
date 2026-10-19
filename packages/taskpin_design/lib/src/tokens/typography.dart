// Typography (docs/VISUAL_SPEC.md §2).
//
// Only weights 400 and 600. Sizes start at 12. System fonts only; nothing is
// bundled.

import 'dart:ui' show FontFeature;

import 'package:flutter/painting.dart';

/// Font family names and fallback chains.
class TpFontFamily {
  const TpFontFamily._();

  /// UI text at sizes up to 18.
  static const String uiText = 'Segoe UI Variable Text';

  /// UI text at sizes 20 and up.
  static const String uiDisplay = 'Segoe UI Variable Display';

  /// Code, paths, expressions.
  static const String mono = 'Cascadia Mono';

  /// Fallback for both UI families.
  static const List<String> uiFallback = <String>[
    'Segoe UI',
    'Microsoft YaHei UI',
    'PingFang SC',
  ];

  /// Fallback for [mono].
  static const List<String> monoFallback = <String>[
    'Consolas',
    'SF Mono',
    'Menlo',
    'Microsoft YaHei UI',
  ];
}

/// One entry in the type scale.
class TpTextStyleSpec {
  const TpTextStyleSpec({
    required this.size,
    required this.lineHeight,
    required this.weight,
    required this.family,
    this.fallback = TpFontFamily.uiFallback,
    this.useTabularFigures = false,
  });

  final double size;
  final double lineHeight;
  final FontWeight weight;
  final String family;
  final List<String> fallback;

  /// Whether this role uses tabular figures by default.
  final bool useTabularFigures;

  /// Materialise a [TextStyle].
  ///
  /// [tabular] forces tabular figures on or off; null keeps the role default.
  TextStyle toTextStyle({bool? tabular}) {
    final bool figures = tabular ?? useTabularFigures;
    return TextStyle(
      fontFamily: family,
      fontFamilyFallback: fallback,
      fontSize: size,
      height: lineHeight / size,
      fontWeight: weight,
      fontFeatures: figures
          ? const <FontFeature>[FontFeature.tabularFigures()]
          : null,
    );
  }
}

/// The type ramp (docs/VISUAL_SPEC.md §2.2).
class TpTypography {
  const TpTypography._();

  /// 12/16 · 400. Card descriptions, timestamps, badges.
  static const TpTextStyleSpec caption = TpTextStyleSpec(
    size: 12,
    lineHeight: 16,
    weight: FontWeight.w400,
    family: TpFontFamily.uiText,
  );

  /// 14/20 · 400. Body text, control text, list primary text.
  static const TpTextStyleSpec body = TpTextStyleSpec(
    size: 14,
    lineHeight: 20,
    weight: FontWeight.w400,
    family: TpFontFamily.uiText,
  );

  /// 14/20 · 600. Group headers, emphasised names.
  static const TpTextStyleSpec bodyStrong = TpTextStyleSpec(
    size: 14,
    lineHeight: 20,
    weight: FontWeight.w600,
    family: TpFontFamily.uiText,
  );

  /// 18/24 · 400. Rarely used.
  static const TpTextStyleSpec bodyLarge = TpTextStyleSpec(
    size: 18,
    lineHeight: 24,
    weight: FontWeight.w400,
    family: TpFontFamily.uiText,
  );

  /// 20/28 · 600. Dialog titles.
  static const TpTextStyleSpec subtitle = TpTextStyleSpec(
    size: 20,
    lineHeight: 28,
    weight: FontWeight.w600,
    family: TpFontFamily.uiDisplay,
  );

  /// 28/36 · 600. Page titles.
  static const TpTextStyleSpec title = TpTextStyleSpec(
    size: 28,
    lineHeight: 36,
    weight: FontWeight.w600,
    family: TpFontFamily.uiDisplay,
  );

  /// 13/20 · 400. Code, paths, script output.
  static const TpTextStyleSpec mono = TpTextStyleSpec(
    size: 13,
    lineHeight: 20,
    weight: FontWeight.w400,
    family: TpFontFamily.mono,
    fallback: TpFontFamily.monoFallback,
    useTabularFigures: true,
  );

  /// All roles, keyed by name.
  static const Map<String, TpTextStyleSpec> all = <String, TpTextStyleSpec>{
    'caption': caption,
    'body': body,
    'bodyStrong': bodyStrong,
    'bodyLarge': bodyLarge,
    'subtitle': subtitle,
    'title': title,
    'mono': mono,
  };

  /// Roles that render metrics and therefore use tabular figures.
  static const List<String> tabularRoles = <String>['title', 'mono'];
}
