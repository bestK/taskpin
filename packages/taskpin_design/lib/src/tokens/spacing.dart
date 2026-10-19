// Spacing scale, 4 px base (docs/VISUAL_SPEC.md §3.1).

import 'package:flutter/painting.dart';

/// Spacing values. Use these instead of bare doubles in padding and gaps.
class TpSpacing {
  const TpSpacing._();

  static const double s2 = 2;
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s30 = 30;
  static const double s32 = 32;
  static const double s36 = 36;
  static const double s40 = 40;
  static const double s48 = 48;

  /// Every step, in order.
  static const List<double> steps = <double>[
    s2, s4, s6, s8, s12, s16, s20, s24, s30, s32, s36, s40, s48,
  ];

  /// Between adjacent buttons.
  static const double buttonGap = s8;

  /// Between a label and the control below it.
  static const double headerGap = s8;

  /// Between two content blocks.
  static const double blockGap = s12;

  /// Inside cards and dialogs.
  static const double surfacePadding = s16;

  /// Between settings cards in a section.
  static const double settingsCardGap = s4;

  /// Above a settings section header.
  static const double sectionTop = s30;

  /// Below a settings section header.
  static const double sectionBottom = s6;

  /// Page side margin when the window is narrower than 1000.
  static const double pageMarginNarrow = s24;

  /// Page side margin otherwise.
  static const double pageMarginWide = s36;

  /// Maximum width of page content.
  static const double pageMaxWidth = 1000;

  static const EdgeInsets cardPadding = EdgeInsets.all(surfacePadding);
  static const EdgeInsets controlPadding =
      EdgeInsets.symmetric(horizontal: s12);
}

/// Component heights and widths (docs/VISUAL_SPEC.md §3.2).
class TpControlSize {
  const TpControlSize._();

  /// Buttons, inputs, selects.
  static const double control = 32;

  /// List row without a subtitle.
  static const double listRow = 40;

  /// List row with a subtitle.
  static const double listRowTwoLine = 60;

  /// Settings card minimum height.
  static const double settingsCardMin = 68;

  /// Navigation item.
  /// Navigation item height (docs/VISUAL_SPEC.md section 5.1).
  static const double navItem = 40;

  /// Expanded navigation rail width.
  static const double navWidth = 240;

  /// Collapsed navigation rail width (icons only).
  static const double navCompactWidth = 48;

  /// Window title bar.
  static const double titleBar = 32;

  /// Switch width.
  static const double switchWidth = 40;

  /// Switch height.
  static const double switchHeight = 20;

  /// Icon button edge.
  static const double iconButton = 32;

  /// Width of the window below which the navigation rail collapses.
  static const double navCollapseBreakpoint = 900;

  /// Width of the settings card below which the trailing control wraps.
  static const double settingsCardWrapWidth = 476;

  /// Minimum width of a settings card trailing control.
  static const double settingsTrailingMinWidth = 120;
}
