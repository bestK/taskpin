// Layer 2 of 3 — SEMANTIC.
//
// Names a role, not a colour. Widget code reads these through `TaskPinTheme`.
// Every value comes from `primitives.dart`; this file has no literals.

import 'dart:ui' show Color;

import 'primitives.dart';

/// Status kinds. `info` maps to `accent.text`; it is not a status colour.
enum TpStateKind {
  success,
  caution,
  critical,
  neutral,
  info,
}

/// Alpha of the tinted fill used by [TpStatusColors.subtleOf] and InfoBar.
const double kSubtleAlpha = 0.12;

/// Window and card surfaces.
class TpBgColors {
  const TpBgColors({
    required this.window,
    required this.card,
    required this.cardSecondary,
    required this.flyout,
  });

  /// Window ground. Mica replaces it on Windows 11 when available.
  final Color window;

  /// Settings cards and list groups.
  final Color card;

  /// Secondary area inside a card: code wells, log areas, dialog footer.
  final Color cardSecondary;

  /// Menus, dropdowns, tooltips and dialogs.
  final Color flyout;
}

/// Card and divider lines.
class TpStrokeColors {
  const TpStrokeColors({
    required this.card,
    required this.divider,
    required this.strong,
  });

  /// 1px card outline.
  final Color card;

  /// 1px line between rows inside a group.
  final Color divider;

  /// Hovered card outline.
  final Color strong;
}

/// Button, input and switch surfaces.
class TpControlColors {
  const TpControlColors({
    required this.fill,
    required this.fillHover,
    required this.fillPressed,
    required this.fillInputActive,
    required this.stroke,
    required this.strokeBottom,
    required this.strokeStrong,
  });

  /// Resting background.
  final Color fill;
  final Color fillHover;
  final Color fillPressed;

  /// Input background while focused.
  final Color fillInputActive;

  /// 1px outline.
  final Color stroke;

  /// Bottom edge of a button.
  final Color strokeBottom;

  /// Input bottom edge; switch off outline; checkbox outline.
  final Color strokeStrong;
}

/// Hover and pressed fills for elements without a border.
class TpSubtleColors {
  const TpSubtleColors({required this.hover, required this.pressed});

  final Color hover;
  final Color pressed;
}

/// Text colours, by descending emphasis.
class TpTextColors {
  const TpTextColors({
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.disabled,
  });

  final Color primary;
  final Color secondary;

  /// Placeholders and secondary metadata only.
  final Color tertiary;

  final Color disabled;
}

/// Accent colours. One accent: Windows default blue.
class TpAccentColors {
  const TpAccentColors({
    required this.fill,
    required this.fillHover,
    required this.onFill,
    required this.text,
  });

  /// Primary button, switch on, selection indicator.
  final Color fill;

  /// [fill] on hover.
  final Color fillHover;

  /// Text and icons on [fill].
  final Color onFill;

  /// Text-button label and links.
  final Color text;
}

/// Status colours. [info] is `accent.text`, so [TpStateKind.info] reads as
/// accent text.
class TpStatusColors {
  const TpStatusColors({
    required this.success,
    required this.caution,
    required this.critical,
    required this.neutral,
    required this.info,
  });

  final Color success;
  final Color caution;
  final Color critical;
  final Color neutral;

  /// Equal to `accent.text`.
  final Color info;

  /// Base colour for [kind].
  Color colorOf(TpStateKind kind) {
    switch (kind) {
      case TpStateKind.success:
        return success;
      case TpStateKind.caution:
        return caution;
      case TpStateKind.critical:
        return critical;
      case TpStateKind.neutral:
        return neutral;
      case TpStateKind.info:
        return info;
    }
  }

  /// [colorOf] at [alpha] opacity, 12 % by default. Used as the InfoBar
  /// background and for status pills.
  Color subtleOf(TpStateKind kind, {double alpha = kSubtleAlpha}) =>
      colorOf(kind).withValues(alpha: alpha);
}

/// The complete semantic layer for one theme.
class TpSemanticColors {
  const TpSemanticColors({
    required this.bg,
    required this.stroke,
    required this.control,
    required this.subtle,
    required this.text,
    required this.accent,
    required this.status,
    required this.smoke,
    required this.focusInner,
    required this.navActive,
    required this.navActiveText,
    required this.taskbar,
    required this.taskbarLabel,
    required this.taskbarMuted,
    required this.taskbarPlaceholder,
    required this.taskbarChip,
    required this.taskbarChipBorder,
  });

  final TpBgColors bg;
  final TpStrokeColors stroke;
  final TpControlColors control;
  final TpSubtleColors subtle;
  final TpTextColors text;
  final TpAccentColors accent;
  final TpStatusColors status;

  /// Modal backdrop.
  final Color smoke;

  /// Keyboard focus ring inner line. The outer line is [TpTextColors.primary].
  final Color focusInner;

  /// Selected navigation item fill (`nav/active`).
  final Color navActive;

  /// Label and icon on [navActive].
  ///
  /// Separate from [navActive] because the two themes pick different
  /// treatments: dark fills the item with the taskbar colour and uses white,
  /// light tints it and uses a darker accent, so the selected item does not
  /// become a black block on a light page.
  final Color navActiveText;

  /// Taskbar mock inside the manager window (`bg/taskbar`). Same in both
  /// themes.
  final Color taskbar;

  /// Label text on the taskbar mock.
  final Color taskbarLabel;

  /// Secondary text on the taskbar mock, e.g. the tray clock.
  final Color taskbarMuted;

  /// Drag placeholder square and segment divider on the taskbar mock.
  final Color taskbarPlaceholder;

  /// One pinned plugin inside the taskbar mock.
  final Color taskbarChip;

  /// 1 px outline on [taskbarChip].
  final Color taskbarChipBorder;

  /// Keyboard focus ring outer line. Equal to `text.primary`.
  Color get focusOuter => text.primary;
}

/// Semantic colours, resolved per theme.
class TpSemantic {
  const TpSemantic._();

  static const TpSemanticColors dark = TpSemanticColors(
    bg: TpBgColors(
      window: TpPrimitives.darkBgWindow,
      card: TpPrimitives.darkBgCard,
      cardSecondary: TpPrimitives.darkBgCardSecondary,
      flyout: TpPrimitives.darkBgFlyout,
    ),
    stroke: TpStrokeColors(
      card: TpPrimitives.darkStrokeCard,
      divider: TpPrimitives.darkStrokeDivider,
      strong: TpPrimitives.darkStrokeStrong,
    ),
    control: TpControlColors(
      fill: TpPrimitives.darkControlFill,
      fillHover: TpPrimitives.darkControlFillHover,
      fillPressed: TpPrimitives.darkControlFillPressed,
      fillInputActive: TpPrimitives.darkControlFillInputActive,
      stroke: TpPrimitives.darkControlStroke,
      strokeBottom: TpPrimitives.darkControlStrokeBottom,
      strokeStrong: TpPrimitives.darkControlStrokeStrong,
    ),
    subtle: TpSubtleColors(
      hover: TpPrimitives.darkSubtleHover,
      pressed: TpPrimitives.darkSubtlePressed,
    ),
    text: TpTextColors(
      primary: TpPrimitives.darkTextPrimary,
      secondary: TpPrimitives.darkTextSecondary,
      tertiary: TpPrimitives.darkTextTertiary,
      disabled: TpPrimitives.darkTextDisabled,
    ),
    accent: TpAccentColors(
      fill: TpPrimitives.darkAccentFill,
      fillHover: TpPrimitives.darkAccentFillHover,
      onFill: TpPrimitives.darkAccentOnFill,
      text: TpPrimitives.darkAccentText,
    ),
    status: TpStatusColors(
      success: TpPrimitives.darkStatusSuccess,
      caution: TpPrimitives.darkStatusCaution,
      critical: TpPrimitives.darkStatusCritical,
      neutral: TpPrimitives.darkStatusNeutral,
      info: TpPrimitives.darkAccentText,
    ),
    smoke: TpPrimitives.smoke,
    focusInner: TpPrimitives.darkFocusInner,
    navActive: TpPrimitives.taskbar,
    navActiveText: TpPrimitives.white,
    taskbar: TpPrimitives.taskbar,
    taskbarLabel: TpPrimitives.taskbarLabel,
    taskbarMuted: TpPrimitives.taskbarMuted,
    taskbarPlaceholder: TpPrimitives.taskbarPlaceholder,
    taskbarChip: TpPrimitives.taskbarChip,
    taskbarChipBorder: TpPrimitives.taskbarChipBorder,
  );

  static const TpSemanticColors light = TpSemanticColors(
    bg: TpBgColors(
      window: TpPrimitives.lightBgWindow,
      card: TpPrimitives.lightBgCard,
      cardSecondary: TpPrimitives.lightBgCardSecondary,
      flyout: TpPrimitives.lightBgFlyout,
    ),
    stroke: TpStrokeColors(
      card: TpPrimitives.lightStrokeCard,
      divider: TpPrimitives.lightStrokeDivider,
      strong: TpPrimitives.lightStrokeStrong,
    ),
    control: TpControlColors(
      fill: TpPrimitives.lightControlFill,
      fillHover: TpPrimitives.lightControlFillHover,
      fillPressed: TpPrimitives.lightControlFillPressed,
      fillInputActive: TpPrimitives.lightControlFillInputActive,
      stroke: TpPrimitives.lightControlStroke,
      strokeBottom: TpPrimitives.lightControlStrokeBottom,
      strokeStrong: TpPrimitives.lightControlStrokeStrong,
    ),
    subtle: TpSubtleColors(
      hover: TpPrimitives.lightSubtleHover,
      pressed: TpPrimitives.lightSubtlePressed,
    ),
    text: TpTextColors(
      primary: TpPrimitives.lightTextPrimary,
      secondary: TpPrimitives.lightTextSecondary,
      tertiary: TpPrimitives.lightTextTertiary,
      disabled: TpPrimitives.lightTextDisabled,
    ),
    accent: TpAccentColors(
      fill: TpPrimitives.lightAccentFill,
      fillHover: TpPrimitives.lightAccentFillHover,
      onFill: TpPrimitives.lightAccentOnFill,
      text: TpPrimitives.lightAccentText,
    ),
    status: TpStatusColors(
      success: TpPrimitives.lightStatusSuccess,
      caution: TpPrimitives.lightStatusCaution,
      critical: TpPrimitives.lightStatusCritical,
      neutral: TpPrimitives.lightStatusNeutral,
      info: TpPrimitives.lightAccentText,
    ),
    smoke: TpPrimitives.smoke,
    focusInner: TpPrimitives.lightFocusInner,
    navActive: TpPrimitives.lightNavActive,
    navActiveText: TpPrimitives.lightNavActiveText,
    taskbar: TpPrimitives.taskbar,
    taskbarLabel: TpPrimitives.taskbarLabel,
    taskbarMuted: TpPrimitives.taskbarMuted,
    taskbarPlaceholder: TpPrimitives.taskbarPlaceholder,
    taskbarChip: TpPrimitives.taskbarChip,
    taskbarChipBorder: TpPrimitives.taskbarChipBorder,
  );

  /// Resolve by brightness flag.
  static TpSemanticColors of(bool isDark) => isDark ? dark : light;
}
