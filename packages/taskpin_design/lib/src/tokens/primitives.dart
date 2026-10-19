// Layer 1 of 3 — PRIMITIVES.
//
// Raw colour values from docs/VISUAL_SPEC.md §1 (WinUI 3 default theme). Widget
// code must not import this file; it reads `semantic.dart` through
// `TaskPinTheme`.
//
// Together with bar_tokens.dart this is the only file in the package that may
// contain `Color(0x...)` literals. Enforced by test/no_raw_colors_test.dart.

import 'dart:ui' show Color;

/// Raw palette. Each name is `<theme><role>` with the spec token in the
/// comment. Alpha-composited colours keep their alpha byte.
class TpPrimitives {
  const TpPrimitives._();

  // -- Shared ---------------------------------------------------------------

  /// Modal backdrop, both themes. `smoke`.
  static const Color smoke = Color(0x4D000000);

  /// Text and icons on the accent fill (`accent/onFill`, both themes).
  static const Color white = Color(0xFFFFFFFF);

  /// Black. Kept for the focus ring and Material's shadow.
  static const Color black = Color(0xFF000000);

  /// Taskbar colour behind the detail-page preview strip, dark taskbar.
  static const Color taskbarPreviewDark = Color(0xFF1C1C1C);

  /// Taskbar colour behind the detail-page preview strip, light taskbar.
  static const Color taskbarPreviewLight = Color(0xFFEEEEEE);

  // -- Shared taskbar mock ------------------------------------------------

  /// `bg/taskbar`. The dark strip drawn inside the manager window.
  static const Color taskbar = Color(0xFF16181D);

  /// Label text on the taskbar mock (`#9AA0A8`).
  static const Color taskbarLabel = Color(0xFF9AA0A8);

  /// Secondary text on the taskbar mock, e.g. the tray clock (`#C9CDD3`).
  static const Color taskbarMuted = Color(0xFFC9CDD3);

  /// Drag placeholder square and segment divider on the taskbar mock.
  static const Color taskbarPlaceholder = Color(0xFF2A2D33);

  /// Low-saturation letter-avatar fills, indexed by name hash. Light pastels
  /// with dark text, used in both themes so an item keeps one identity colour.
  static const List<Color> avatarFills = <Color>[
    Color(0xFFDCE6F7),
    Color(0xFFDDEEDF),
    Color(0xFFF6E3D7),
    Color(0xFFEAE2F6),
    Color(0xFFF4EBD3),
    Color(0xFFD9EDF0),
    Color(0xFFF4DDE4),
    Color(0xFFE6E7EA),
  ];

  /// Text on [avatarFills].
  static const Color avatarText = Color(0xFF1C1E22);

  // -- Dark -----------------------------------------------------------------

  static const Color darkBgWindow = Color(0xFF1C1E22);
  static const Color darkBgCard = Color(0xFF24262B);
  static const Color darkBgCardSecondary = Color(0xFF2A2D33);
  static const Color darkBgFlyout = Color(0xFF2C2E34);

  static const Color darkStrokeCard = Color(0x33FFFFFF);
  static const Color darkStrokeDivider = Color(0x26FFFFFF);
  static const Color darkStrokeStrong = Color(0xFF4A4F57);

  static const Color darkControlFill = Color(0x0FFFFFFF);
  static const Color darkControlFillHover = Color(0x15FFFFFF);
  static const Color darkControlFillPressed = Color(0x08FFFFFF);
  static const Color darkControlFillInputActive = Color(0xB31E1E1E);
  static const Color darkControlStroke = Color(0x12FFFFFF);
  static const Color darkControlStrokeBottom = Color(0x18FFFFFF);
  static const Color darkControlStrokeStrong = Color(0x8BFFFFFF);

  static const Color darkSubtleHover = Color(0x0FFFFFFF);
  static const Color darkSubtlePressed = Color(0x0AFFFFFF);

  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xC5FFFFFF);
  static const Color darkTextTertiary = Color(0x87FFFFFF);
  static const Color darkTextDisabled = Color(0x5DFFFFFF);

  static const Color darkAccentFill = Color(0xFF4C8DFF);
  static const Color darkAccentFillHover = Color(0xFF5C99FF);
  static const Color darkAccentOnFill = Color(0xFFFFFFFF);
  static const Color darkAccentText = Color(0xFF7FB0FF);

  static const Color darkStatusSuccess = Color(0xFF5BD08A);
  static const Color darkStatusCaution = Color(0xFFF5C542);
  static const Color darkStatusCritical = Color(0xFFFF8A80);
  static const Color darkStatusNeutral = Color(0xFF9AA0A8);

  /// Keyboard focus ring, inner 1px.
  static const Color darkFocusInner = Color(0xB3000000);

  // -- Light ----------------------------------------------------------------

  static const Color lightBgWindow = Color(0xFFF6F6F3);
  static const Color lightBgCard = Color(0xFFFFFFFF);
  static const Color lightBgCardSecondary = Color(0xFFF4F4F1);
  static const Color lightBgFlyout = Color(0xFFFFFFFF);

  static const Color lightStrokeCard = Color(0xFFE6E4DE);
  static const Color lightStrokeDivider = Color(0xFFEAE8E2);
  static const Color lightStrokeStrong = Color(0xFFC9C6BE);

  static const Color lightControlFill = Color(0xB3FFFFFF);
  static const Color lightControlFillHover = Color(0x80F9F9F9);
  static const Color lightControlFillPressed = Color(0x4DF9F9F9);
  static const Color lightControlFillInputActive = Color(0xFFFFFFFF);
  static const Color lightControlStroke = Color(0x0F000000);
  static const Color lightControlStrokeBottom = Color(0x29000000);
  static const Color lightControlStrokeStrong = Color(0x72000000);

  static const Color lightSubtleHover = Color(0x09000000);
  static const Color lightSubtlePressed = Color(0x06000000);

  static const Color lightTextPrimary = Color(0xE4000000);
  static const Color lightTextSecondary = Color(0x9E000000);
  static const Color lightTextTertiary = Color(0x72000000);
  static const Color lightTextDisabled = Color(0x5C000000);

  static const Color lightAccentFill = Color(0xFF2457D6);
  static const Color lightAccentFillHover = Color(0xFF1E4BB8);
  static const Color lightAccentOnFill = Color(0xFFFFFFFF);
  static const Color lightAccentText = Color(0xFF2457D6);

  static const Color lightStatusSuccess = Color(0xFF1E7F4F);
  static const Color lightStatusCaution = Color(0xFFB07800);
  static const Color lightStatusCritical = Color(0xFFB42318);
  static const Color lightStatusNeutral = Color(0xFF868A93);

  /// Keyboard focus ring, inner 1px.
  static const Color lightFocusInner = Color(0xB3FFFFFF);
}
