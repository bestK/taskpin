// TaskPinTheme — the ThemeExtension widgets read.
//
// A widget never names a colour. It reads `TaskPinTheme.of(context).<group>.<role>`.
// Spacing, radius, sizes, type and motion are static and imported directly
// from their token files.

import 'package:flutter/material.dart';

import '../tokens/bar_tokens.dart';
import '../tokens/elevation.dart';
import '../tokens/primitives.dart';
import '../tokens/semantic.dart';
import '../tokens/typography.dart';
export '../tokens/semantic.dart' show TpStateKind;

/// The TaskPin theme as a [ThemeExtension].
@immutable
class TaskPinTheme extends ThemeExtension<TaskPinTheme> {
  const TaskPinTheme({
    required this.brightness,
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
    required this.barColors,
    required this.barPlatform,
  });

  final Brightness brightness;

  final TpBgColors bg;
  final TpStrokeColors stroke;
  final TpControlColors control;
  final TpSubtleColors subtle;
  final TpTextColors text;
  final TpAccentColors accent;
  final TpStatusColors status;

  /// Modal backdrop.
  final Color smoke;

  /// Keyboard focus ring inner line.
  final Color focusInner;

  /// Selected navigation item fill.
  final Color navActive;

  /// Label and icon on [navActive].
  final Color navActiveText;

  /// Taskbar mock inside the manager window.
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

  /// Taskbar colour for the preview strip. Follows the theme brightness.
  Color get taskbarPreview => isDark
      ? TpPrimitives.taskbarPreviewDark
      : TpPrimitives.taskbarPreviewLight;

  /// Keyboard focus ring outer line (`text.primary`).
  Color get focusOuter => text.primary;

  /// The bar palette. Frozen — see `bar_tokens.dart`.
  final TpBarColors barColors;

  /// Which platform's bar metrics to use when previewing.
  final TpBarPlatform barPlatform;

  // -- Construction ---------------------------------------------------------

  factory TaskPinTheme.dark({TpBarPlatform barPlatform = TpBarPlatform.windows}) =>
      _fromSemantic(Brightness.dark, TpSemantic.dark, barPlatform);

  factory TaskPinTheme.light({TpBarPlatform barPlatform = TpBarPlatform.windows}) =>
      _fromSemantic(Brightness.light, TpSemantic.light, barPlatform);

  static TaskPinTheme _fromSemantic(
    Brightness brightness,
    TpSemanticColors c,
    TpBarPlatform barPlatform,
  ) =>
      TaskPinTheme(
        brightness: brightness,
        bg: c.bg,
        stroke: c.stroke,
        control: c.control,
        subtle: c.subtle,
        text: c.text,
        accent: c.accent,
        status: c.status,
        smoke: c.smoke,
        focusInner: c.focusInner,
        navActive: c.navActive,
        navActiveText: c.navActiveText,
        taskbar: c.taskbar,
        taskbarLabel: c.taskbarLabel,
        taskbarMuted: c.taskbarMuted,
        taskbarPlaceholder: c.taskbarPlaceholder,
        taskbarChip: c.taskbarChip,
        taskbarChipBorder: c.taskbarChipBorder,
        barColors: const TpBarColors(),
        barPlatform: barPlatform,
      );

  /// Resolve by brightness.
  factory TaskPinTheme.forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? TaskPinTheme.dark() : TaskPinTheme.light();

  /// Read the theme. Falls back to dark when the extension is absent.
  static TaskPinTheme of(BuildContext context) {
    final TaskPinTheme? t = Theme.of(context).extension<TaskPinTheme>();
    return t ?? TaskPinTheme.dark();
  }

  bool get isDark => brightness == Brightness.dark;

  /// Bar geometry for the configured platform.
  TpBarMetrics get barMetrics => TpBarMetrics.of(barPlatform);

  // -- Text helpers ---------------------------------------------------------

  /// Materialise a type-scale entry.
  TextStyle style(TpTextStyleSpec spec, {bool? tabular}) =>
      spec.toTextStyle(tabular: tabular);

  /// A metric readout: mono with tabular figures.
  TextStyle get metricStyle => TpTypography.mono.toTextStyle(tabular: true);

  /// Colour for a text emphasis.
  Color textColor(TpTextRole role) {
    switch (role) {
      case TpTextRole.primary:
        return text.primary;
      case TpTextRole.secondary:
        return text.secondary;
      case TpTextRole.tertiary:
        return text.tertiary;
      case TpTextRole.disabled:
        return text.disabled;
      case TpTextRole.onAccent:
        return accent.onFill;
    }
  }

  // -- Status helpers -------------------------------------------------------

  /// Base colour for a status kind.
  Color stateColor(TpStateKind kind) => status.colorOf(kind);

  /// 12 % fill for a status kind.
  Color stateSubtle(TpStateKind kind) => status.subtleOf(kind);

  /// Tinted fill for a status kind at an explicit opacity, e.g. the 8 %
  /// error banner.
  Color stateSubtleOf(TpStateKind kind, double alpha) =>
      status.subtleOf(kind, alpha: alpha);

  // -- Elevation ------------------------------------------------------------

  /// Menus, dropdowns, tooltips.
  List<BoxShadow> get shadowFlyout => TpElevation.flyout(isDark: isDark);

  /// Dialogs.
  List<BoxShadow> get shadowDialog => TpElevation.dialog(isDark: isDark);

  // -- ThemeExtension -------------------------------------------------------

  @override
  TaskPinTheme copyWith({
    Brightness? brightness,
    TpBgColors? bg,
    TpStrokeColors? stroke,
    TpControlColors? control,
    TpSubtleColors? subtle,
    TpTextColors? text,
    TpAccentColors? accent,
    TpStatusColors? status,
    Color? smoke,
    Color? focusInner,
    Color? navActive,
    Color? navActiveText,
    Color? taskbar,
    Color? taskbarLabel,
    Color? taskbarMuted,
    Color? taskbarPlaceholder,
    Color? taskbarChip,
    Color? taskbarChipBorder,
    TpBarColors? barColors,
    TpBarPlatform? barPlatform,
  }) =>
      TaskPinTheme(
        brightness: brightness ?? this.brightness,
        bg: bg ?? this.bg,
        stroke: stroke ?? this.stroke,
        control: control ?? this.control,
        subtle: subtle ?? this.subtle,
        text: text ?? this.text,
        accent: accent ?? this.accent,
        status: status ?? this.status,
        smoke: smoke ?? this.smoke,
        focusInner: focusInner ?? this.focusInner,
        navActive: navActive ?? this.navActive,
        navActiveText: navActiveText ?? this.navActiveText,
        taskbar: taskbar ?? this.taskbar,
        taskbarLabel: taskbarLabel ?? this.taskbarLabel,
        taskbarMuted: taskbarMuted ?? this.taskbarMuted,
        taskbarPlaceholder: taskbarPlaceholder ?? this.taskbarPlaceholder,
        taskbarChip: taskbarChip ?? this.taskbarChip,
        taskbarChipBorder: taskbarChipBorder ?? this.taskbarChipBorder,
        barColors: barColors ?? this.barColors,
        barPlatform: barPlatform ?? this.barPlatform,
      );

  /// Interpolate for theme transitions.
  ///
  /// Colours interpolate. `brightness`, `barPlatform` and the bar palette
  /// snap at the midpoint.
  @override
  TaskPinTheme lerp(covariant TaskPinTheme? other, double t) {
    if (other == null) {
      return this;
    }
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return TaskPinTheme(
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: TpBgColors(
        window: l(bg.window, other.bg.window),
        card: l(bg.card, other.bg.card),
        cardSecondary: l(bg.cardSecondary, other.bg.cardSecondary),
        flyout: l(bg.flyout, other.bg.flyout),
      ),
      stroke: TpStrokeColors(
        card: l(stroke.card, other.stroke.card),
        divider: l(stroke.divider, other.stroke.divider),
        strong: l(stroke.strong, other.stroke.strong),
      ),
      control: TpControlColors(
        fill: l(control.fill, other.control.fill),
        fillHover: l(control.fillHover, other.control.fillHover),
        fillPressed: l(control.fillPressed, other.control.fillPressed),
        fillInputActive: l(control.fillInputActive, other.control.fillInputActive),
        stroke: l(control.stroke, other.control.stroke),
        strokeBottom: l(control.strokeBottom, other.control.strokeBottom),
        strokeStrong: l(control.strokeStrong, other.control.strokeStrong),
      ),
      subtle: TpSubtleColors(
        hover: l(subtle.hover, other.subtle.hover),
        pressed: l(subtle.pressed, other.subtle.pressed),
      ),
      text: TpTextColors(
        primary: l(text.primary, other.text.primary),
        secondary: l(text.secondary, other.text.secondary),
        tertiary: l(text.tertiary, other.text.tertiary),
        disabled: l(text.disabled, other.text.disabled),
      ),
      accent: TpAccentColors(
        fill: l(accent.fill, other.accent.fill),
        fillHover: l(accent.fillHover, other.accent.fillHover),
        onFill: l(accent.onFill, other.accent.onFill),
        text: l(accent.text, other.accent.text),
      ),
      status: TpStatusColors(
        success: l(status.success, other.status.success),
        caution: l(status.caution, other.status.caution),
        critical: l(status.critical, other.status.critical),
        neutral: l(status.neutral, other.status.neutral),
        info: l(status.info, other.status.info),
      ),
      smoke: l(smoke, other.smoke),
      focusInner: l(focusInner, other.focusInner),
      navActive: l(navActive, other.navActive),
      navActiveText: l(navActiveText, other.navActiveText),
      taskbar: l(taskbar, other.taskbar),
      taskbarLabel: l(taskbarLabel, other.taskbarLabel),
      taskbarMuted: l(taskbarMuted, other.taskbarMuted),
      taskbarPlaceholder: l(taskbarPlaceholder, other.taskbarPlaceholder),
      taskbarChip: l(taskbarChip, other.taskbarChip),
      taskbarChipBorder: l(taskbarChipBorder, other.taskbarChipBorder),
      barColors: t < 0.5 ? barColors : other.barColors,
      barPlatform: t < 0.5 ? barPlatform : other.barPlatform,
    );
  }

  // -- ThemeData bridge -----------------------------------------------------

  /// Build a [ThemeData] carrying this extension.
  ///
  /// The ColorScheme is derived from this theme so Material widgets pick up
  /// the same colours. Font family is set on the root style so Material text
  /// uses the UI family.
  ThemeData toThemeData() {
    final Brightness b = brightness;
    final ColorScheme scheme = ColorScheme(
      brightness: b,
      primary: accent.fill,
      onPrimary: accent.onFill,
      secondary: accent.fill,
      onSecondary: accent.onFill,
      error: status.critical,
      onError: accent.onFill,
      surface: bg.window,
      onSurface: text.primary,
      surfaceContainerHighest: bg.flyout,
      onSurfaceVariant: text.secondary,
      outline: control.strokeStrong,
      outlineVariant: stroke.divider,
      shadow: TpPrimitives.black,
      scrim: smoke,
      inverseSurface: text.primary,
      onInverseSurface: bg.window,
    );

    final TextStyle Function(TpTextStyleSpec) ts = (spec) => spec.toTextStyle();
    final TextTheme textTheme = TextTheme(
      displaySmall: ts(TpTypography.title),
      headlineSmall: ts(TpTypography.subtitle),
      titleLarge: ts(TpTypography.subtitle),
      titleMedium: ts(TpTypography.bodyStrong),
      bodyLarge: ts(TpTypography.bodyLarge),
      bodyMedium: ts(TpTypography.body),
      bodySmall: ts(TpTypography.caption),
      labelLarge: ts(TpTypography.bodyStrong),
      labelMedium: ts(TpTypography.body),
      labelSmall: ts(TpTypography.caption),
    ).apply(
      fontFamily: TpFontFamily.uiText,
      fontFamilyFallback: TpFontFamily.uiFallback,
      bodyColor: text.primary,
      displayColor: text.primary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg.window,
      canvasColor: bg.window,
      dividerColor: stroke.divider,
      splashFactory: NoSplash.splashFactory,
      fontFamily: TpFontFamily.uiText,
      fontFamilyFallback: TpFontFamily.uiFallback,
      extensions: <ThemeExtension<dynamic>>[this],
      textTheme: textTheme,
    );
  }
}

/// Emphasis of a text role.
enum TpTextRole {
  primary,
  secondary,
  tertiary,
  disabled,
  onAccent,
}
