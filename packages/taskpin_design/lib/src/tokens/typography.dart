// Typography (docs/VISUAL_SPEC.md §2).
//
// Weights 400 and 600 for UI text; 700 only for the two display roles, which
// also run tight (negative tracking) the way a keynote headline does. Sizes
// start at 12. System fonts only; nothing is bundled.

import 'dart:ui' show FontFeature;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
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

  /// macOS system UI face (San Francisco).
  ///
  /// The only name that reaches SF through the font manager. `SF Pro Text`,
  /// `SF Pro`, `SF Mono` and `CupertinoSystemText` are not family names on
  /// macOS and resolve to Helvetica. This is also the engine's default family
  /// (`GetDefaultFontFamilies` in txt/src/txt/platform_mac.mm).
  static const String macUi = '.AppleSystemUIFont';

  /// macOS monospaced face for code. Menlo ships with macOS and resolves by
  /// name. `.AppleSystemUIFontMonospaced` resolves to Helvetica through
  /// CTFontCreateWithName, so it is not used.
  static const String macMono = 'Menlo';
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
    this.tracking = 0,
  });

  final double size;
  final double lineHeight;
  final FontWeight weight;
  final String family;
  final List<String> fallback;

  /// Whether this role uses tabular figures by default.
  final bool useTabularFigures;

  /// Letter spacing as a fraction of [size] (CSS `em`). Negative tightens.
  final double tracking;

  /// Materialise a [TextStyle].
  ///
  /// [tabular] forces tabular figures on or off; null keeps the role default.
  TextStyle toTextStyle({bool? tabular}) {
    final bool figures = tabular ?? useTabularFigures;
    // Resolve the platform's own face HERE rather than in the token.
    //
    // The tokens are `const` (the whole type ramp is a compile-time table), so
    // they cannot branch on `defaultTargetPlatform`. This method runs at build
    // time, where the platform is known.
    //
    // WHY IT MATTERS: the tokens name Segoe UI Variable, which does not exist
    // on macOS. Naming the platform's own face first (not a fallback) keeps the
    // result the same in every build. macOS has no family called "SF Pro
    // Text": CoreText resolves that name to Helvetica. See
    // [TpFontFamily.macUi].
    final bool mac = defaultTargetPlatform == TargetPlatform.macOS;
    final String resolved = mac ? _macEquivalent(family) : family;
    final List<String> resolvedFallback =
        mac ? _macFallback(fallback) : fallback;
    return TextStyle(
      fontFamily: resolved,
      fontFamilyFallback: resolvedFallback,
      fontSize: size,
      height: lineHeight / size,
      fontWeight: weight,
      letterSpacing: tracking == 0 ? null : tracking * size,
      fontFeatures: figures
          ? const <FontFeature>[FontFeature.tabularFigures()]
          : null,
    );
  }
}

/// The macOS face for a Windows family name.
///
/// Only the families the tokens actually use; anything else is passed through
/// so a caller-supplied family is never silently replaced. Both Segoe UI
/// roles map to [TpFontFamily.macUi]. The display role is not given the
/// engine's `CupertinoSystemDisplay` because its large-size registration was
/// not verified here.
String _macEquivalent(String family) {
  switch (family) {
    case 'Segoe UI Variable Text':
    case 'Segoe UI Variable Display':
    case 'Segoe UI':
      return TpFontFamily.macUi;
    case 'Cascadia Mono':
    case 'Consolas':
      return TpFontFamily.macMono;
    default:
      return family;
  }
}

/// The macOS fallback chain for a Windows one.
///
/// Each chain lists faces that are installed on macOS. CJK text falls through
/// to PingFang SC, which the Windows chains already use.
List<String> _macFallback(List<String> fallback) {
  if (fallback.contains('Consolas') || fallback.contains('Cascadia Mono')) {
    return const <String>['Monaco', 'PingFang SC'];
  }
  return const <String>['PingFang SC', 'Helvetica Neue'];
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
    tracking: -0.02,
  );

  /// 30/36 · 600 · tabular. The figures under the stage strip.
  static const TpTextStyleSpec figure = TpTextStyleSpec(
    size: 30,
    lineHeight: 36,
    weight: FontWeight.w600,
    family: TpFontFamily.uiDisplay,
    useTabularFigures: true,
    tracking: -0.02,
  );

  /// 48/56 · 700. Second-level stage headline (a page's own name).
  static const TpTextStyleSpec headline = TpTextStyleSpec(
    size: 48,
    lineHeight: 56,
    weight: FontWeight.w700,
    family: TpFontFamily.uiDisplay,
    tracking: -0.03,
  );

  /// 64/72 · 700. The one sentence on the project stage.
  static const TpTextStyleSpec display = TpTextStyleSpec(
    size: 64,
    lineHeight: 72,
    weight: FontWeight.w700,
    family: TpFontFamily.uiDisplay,
    tracking: -0.03,
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
    'figure': figure,
    'headline': headline,
    'display': display,
    'mono': mono,
  };

  /// Roles that render metrics and therefore use tabular figures.
  static const List<String> tabularRoles = <String>['title', 'figure', 'mono'];
}
