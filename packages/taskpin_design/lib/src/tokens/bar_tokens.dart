// ============================================================================
//  F R O Z E N   —   D O   N O T   E X T E N D   W I T H O U T   C O O R D I N A T I O N
// ============================================================================
//
// This token list is duplicated in THREE places:
//
//   1. Dart   — this file                                   (Flutter: preview strip, inspector)
//   2. C++    — native/win/bar_render_d2d.cpp               (Direct2D taskbar strip)
//   3. Swift  — native/mac/StatusItemView.swift             (Core Text menu-bar item)
//
// Every token here costs two hand-written native implementations. The list is
// therefore deliberately SHORT and FROZEN. The plan says so explicitly:
//
//   "这个列表要短且冻结 —— 每个 token 都在 C++/Swift 里重复一份。"
//
// Adding a token is a cross-language change: update all three files and the
// parity test in `test/tokens/bar_tokens_test.dart` in the same commit.
//
// The bar is NOT themed by `TaskPinTheme`. It has its own small palette because
// it must sit inside the OS shell, not inside the app. In particular the bar
// uses the SYSTEM UI FONT (Segoe UI Variable / SF Pro), never Inter — forcing
// Inter onto the taskbar would make TaskPin's strip visibly foreign next to
// every other taskbar segment.
//
// This file and `primitives.dart` are the only two allowed to hold raw
// `Color(0x...)` literals.
// ============================================================================

import 'dart:ui' show Color;

/// Which OS shell the bar is embedded in. The metrics differ per platform and
/// the renderer must be told which set to use.
enum TpBarPlatform {
  /// Windows taskbar. Height follows the taskbar (40 on Win10, 48 on Win11
  /// at 100 % DPI), so [TpBarMetrics.height] is a default, not a constant.
  windows,

  /// macOS menu bar. Height is fixed at 24 pt and only ONE line fits.
  macOS,
}

/// The frozen bar palette.
///
/// Named with the `bar/` prefix from the plan so the three implementations can
/// be diffed textually.
class TpBarColors {
  /// Public const constructor so `TaskPinTheme` can hold an instance of it as
  /// a field (a field of type `Type` would be useless, and the theme must be
  /// able to `copyWith`/`lerp` it).
  const TpBarColors();

  /// The single shared instance.
  static const TpBarColors instance = TpBarColors();

  // -- Backgrounds ----------------------------------------------------------

  /// `bar/bg` — the strip's resting background.
  ///
  /// NOTE: this is the default. A pinned item may override it via
  /// `bar_bg_color` in config.json (`"FFFFFFFF"` means "use this default").
  /// The override path is the item's own colour, not a token.
  ///
  /// PARITY: native/win/bar_tokens.h `kColorBg`. These three files must agree —
  /// the Flutter preview exists so the manager shows what the taskbar will
  /// actually draw, so a divergence here is a visible bug, not a cosmetic one.
  static const Color bg = Color(0xFF0E1015);

  /// `bar/bgHover` — hover fill. The plan replaces the old abrupt
  /// `RGB(39,39,39)` swap with this plus a hairline inset.
  ///
  /// PARITY: native/win/bar_tokens.h `kColorBgHover`.
  static const Color bgHover = Color(0xFF1F242E);

  /// `bar/hairline` — the 1 px inset outline drawn top and bottom on hover.
  static const Color hairline = Color(0x1FFFFFFF);

  /// `bar/separator` — the vertical rule between segments.
  ///
  /// 20 % alpha, 1 px wide, 14 px tall, 6 px either side. This is the token
  /// the plan calls "把'绿字挨着红字'变成可读读数的关键".
  static const Color separator = Color(0x33FFFFFF);

  // -- State strip ----------------------------------------------------------
  //
  // The 2 px full-height strip at the far left of the item. `running` is
  // transparent on purpose: a healthy item shows nothing, so the eye is drawn
  // only to problems. This is also why the script's own span colours are
  // never used for state.

  /// `bar/state.running` — transparent. Health is the absence of a signal.
  static const Color stateRunning = Color(0x00000000);

  /// `bar/state.error` — a Lua error or a failed fetch.
  ///
  /// Matches the dark-theme danger primitive so the bar and the app agree.
  static const Color stateError = Color(0xFFF85149);

  /// `bar/state.stale` — `now - lastUpdate > 2 x interval`.
  ///
  /// New in Aurora; the plan notes it is cheap and genuinely useful.
  static const Color stateStale = Color(0xFFD29922);

  // -- Content --------------------------------------------------------------

  /// `bar/icon` — fallback tint for monochrome icons from `icon()`.
  ///
  /// PARITY: native/win/bar_tokens.h `kColorIcon`. Icons sit on the taskbar's
  /// own chrome rather than inside the app, so they read as the bar's secondary
  /// tone, the same weight as a label.
  static const Color icon = Color(0xFFA2ACBA);

  /// `bar/label` — the segment's label text when the script did not colour it.
  static const Color label = Color(0xFFA2ACBA);

  /// `bar/value` — the segment's value text when the script did not colour it.
  ///
  /// Values are the point of the strip, so they are the brightest default.
  static const Color value = Color(0xFFE6EAF0);

  /// Every token keyed by its frozen name. The parity test diffs this map's
  /// keys against the documented list, so a rename here fails loudly.
  static const Map<String, Color> all = <String, Color>{
    'bar/bg': bg,
    'bar/bgHover': bgHover,
    'bar/hairline': hairline,
    'bar/separator': separator,
    'bar/state.running': stateRunning,
    'bar/state.error': stateError,
    'bar/state.stale': stateStale,
    'bar/icon': icon,
    'bar/label': label,
    'bar/value': value,
  };
}

/// Per-platform bar geometry.
///
/// These are the numbers the native renderers hard-code. They are here so the
/// Flutter preview strip can match them pixel-for-pixel, which is the whole
/// point of `TpBarPreviewStrip`: what you see in the manager window is what
/// appears in the taskbar.
class TpBarMetrics {
  const TpBarMetrics({
    required this.platform,
    required this.height,
    required this.padHorizontal,
    required this.padVertical,
    required this.iconSize,
    required this.radius,
    required this.maxLines,
    required this.separatorWidth,
    required this.separatorHeight,
    required this.separatorGap,
    required this.stateStripWidth,
    required this.minWidth,
    required this.maxWidth,
    required this.widthStep,
  });

  final TpBarPlatform platform;

  /// Strip height. Windows follows the taskbar (48 on Win11 @100 %, 40 on
  /// Win10); macOS is fixed at 24.
  final double height;

  /// Horizontal padding inside the strip.
  final double padHorizontal;

  /// Vertical padding inside the strip.
  final double padVertical;

  /// Icon box size.
  final double iconSize;

  /// Corner radius. Windows taskbar segments are square.
  final double radius;

  /// Maximum text lines. Windows allows 2 (the existing double-line layout),
  /// macOS allows 1.
  final int maxLines;

  /// Separator rule dimensions.
  final double separatorWidth;
  final double separatorHeight;

  /// Gap either side of a separator.
  final double separatorGap;

  /// Width of the state strip at the far left.
  final double stateStripWidth;

  /// Scroll-wheel width clamping, and the step per notch. Frozen because the
  /// native message handler implements the same clamp.
  final double minWidth;
  final double maxWidth;
  final double widthStep;

  /// Windows defaults: height follows the taskbar; 48 is the Win11 value.
  static const TpBarMetrics windows = TpBarMetrics(
    platform: TpBarPlatform.windows,
    height: 48,
    padHorizontal: 8,
    padVertical: 6,
    iconSize: 16,
    radius: 0,
    maxLines: 2,
    separatorWidth: 1,
    separatorHeight: 14,
    separatorGap: 6,
    stateStripWidth: 2,
    minWidth: 50,
    maxWidth: 800,
    widthStep: 5,
  );

  /// macOS defaults: 24 pt, one line only, 6 pt radius.
  static const TpBarMetrics macOS = TpBarMetrics(
    platform: TpBarPlatform.macOS,
    height: 24,
    padHorizontal: 6,
    padVertical: 0,
    iconSize: 16,
    radius: 6,
    maxLines: 1,
    separatorWidth: 1,
    separatorHeight: 12,
    separatorGap: 4,
    stateStripWidth: 2,
    minWidth: 40,
    maxWidth: 600,
    widthStep: 5,
  );

  /// Resolve metrics for a platform.
  static TpBarMetrics of(TpBarPlatform p) =>
      p == TpBarPlatform.windows ? windows : macOS;

  /// Windows taskbar heights the renderer must cope with, for tests.
  static const List<double> windowsKnownTaskbarHeights = <double>[40, 48];
}

/// The frozen token names, as a flat list, for the parity test.
const List<String> kFrozenBarTokenNames = <String>[
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

/// Bar text styles.
///
/// The bar uses the SYSTEM font, not Inter. Sizes are fixed points, not part
/// of the app type scale, because the strip must match its shell.
class TpBarTypography {
  const TpBarTypography._();

  /// The family the native renderers ask for, per platform.
  static const String windowsFamily = 'Segoe UI Variable';
  static const String macOSFamily = 'SF Pro';

  /// Label text size (Windows 11 pt / macOS 11 pt are the same nominal size,
  /// the shells just render them differently).
  static const double labelSize = 11;

  /// Value text size. Same as the label — values are distinguished by weight
  /// and colour, not by being bigger, so a two-line segment stays balanced.
  static const double valueSize = 11;

  /// Weight for labels.
  static const int labelWeight = 400;

  /// Weight for values.
  static const int valueWeight = 500;

  /// Metric text is ALWAYS tabular in the bar. This is the single most
  /// important typographic rule in the whole bar design: without it,
  /// `CPU: 9%` -> `CPU: 100%` shifts everything to its right.
  static const bool tabularFigures = true;

  /// Loading state opacity (the plan: 55 % + shimmer).
  static const double loadingOpacity = 0.55;

  /// Stale threshold, as a multiple of the item's refresh interval.
  static const double staleIntervalMultiplier = 2.0;

  /// Line height as a multiplier of the font size.
  static const double lineHeightMultiplier = 1.25;
}
