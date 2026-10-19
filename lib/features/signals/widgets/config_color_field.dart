// The config colour field: the fix for the R/B swap and the sentinel collision.
//
// ---------------------------------------------------------------------------
// WHY THIS IS NOT JUST `TpColorField`
// ---------------------------------------------------------------------------
// `TpColorField` (taskpin_design) speaks the config wire format as if it were
// `AARRGGBB` — `TpColorHex.fromWire` does `Color(value)`. But a config colour is
// a Win32 **COLORREF**, i.e. `0x00BBGGRR` (see the banner in
// `lib/core/config/config_schema.dart`, and `lib/config.c:61-85`). So the byte
// order is reversed relative to what `TpColorField` assumes.
//
// That mismatch is EXACTLY the defect the plan lists as item 3
// ("设置页颜色输入会 R/B 互换"): `src/settings_dialog.c:140` and
// `src/ui_settings_view.cpp:64` hand the user's hex straight to `wcstoul`, so
// typing `FF0000` (meaning red) produces blue. Reusing `TpColorField` unchanged
// would inherit the same bug, just moved from C into Dart.
//
// This widget adapts instead of reimplementing:
//
//   * DISPLAY: `ConfigColor.colorrefToArgb` converts the stored COLORREF to the
//     ARGB a Flutter `Color` wants, so the swatch shows the colour the taskbar
//     will actually paint. The old UI showed the *raw* value, which is why it
//     looked wrong.
//   * COMMIT: `ConfigColor.argbToColorref` converts back, so the string written
//     to disk is byte-identical to what the C layer writes. Phase 1's
//     field-by-field round-trip requirement is therefore untouched — this
//     changes only what the user sees, never the file format.
//   * The `"FFFFFFFF"` sentinel is passed through UNTOUCHED, so `TpColorField`'s
//     existing "Default" switch and its crossed-out swatch render correctly. The
//     sentinel is deliberately not treated as white: `src/bar_window.c:93` tests
//     `bar_bg_color != 0xFFFFFFFF`, so it means "inherit", and a user-chosen
//     opaque white would have to be written as a different value.
//
// The picker itself (`ColorPickerPopup`) is app-level and built from
// design-system primitives + CustomPaint; no `Tp` component was added to
// `taskpin_design`, which other agents own.

import 'package:flutter/material.dart';
import 'package:taskpin_design/taskpin_design.dart';

import '../../../app/l10n.dart';
import '../../../core/config/config_schema.dart';
import 'color_picker_popup.dart';

/// Edits one config colour string, in the config's BGR COLORREF hex encoding.
class ConfigColorField extends StatelessWidget {
  const ConfigColorField({
    super.key,
    required this.wireValue,
    required this.onChanged,
    this.label,
    this.helper,
    this.error,
    this.enabled = true,
    this.allowInherit = true,
    this.inheritLabel,
  });

  /// The value as stored in config.json: 6 or 8 uppercase hex digits, BGR.
  final String wireValue;

  /// Receives the new value in the SAME encoding, ready to persist.
  final ValueChanged<String> onChanged;

  final String? label;
  final String? helper;
  final String? error;
  final bool enabled;

  /// Offer the "use default" option. Only `bar_bg_color` has a sentinel; the
  /// global `font_color`/`bg_color` are always concrete.
  final bool allowInherit;

  /// Label of the "use default" switch. Defaults to the localized text.
  final String? inheritLabel;

  /// True when the stored value is the "use global default" sentinel.
  bool get isInherit => allowInherit && ConfigColor.isUseGlobal(wireValue);

  /// The stored value as the colour the taskbar will paint, or null when the
  /// value is unparsable.
  Color? get displayColor {
    if (isInherit) return null;
    final int? raw = ConfigColor.tryParse(wireValue);
    if (raw == null) return null;
    return Color(ConfigColor.colorrefToArgb(raw));
  }

  /// The on-disk form of [color], which is what [onChanged] receives.
  static String wireFromColor(Color color, {bool withAlpha = true}) {
    final int colorref = ConfigColor.argbToColorref(color.toARGB32());
    return withAlpha
        ? ConfigColor.format8(colorref)
        : ConfigColor.format6(colorref);
  }

  /// The 6-digit form used by `global.font_color`, which `config.c` writes with
  /// `%06X` (alpha masked away).
  static String wire6FromColor(Color color) =>
      wireFromColor(color, withAlpha: false);

  void _commit(Color color) {
    // Preserve the stored width: `font_color` is 6 digits, `bg_color` and
    // `bar_bg_color` are 8. Changing the width would be a format change.
    final int width = wireValue.trim().length <= 6 && wireValue.trim().isNotEmpty
        ? 6
        : 8;
    onChanged(width == 6 ? wire6FromColor(color) : wireFromColor(color));
  }

  @override
  Widget build(BuildContext context) {
    final Color? swatch = displayColor;
    final String inherit = inheritLabel ?? context.l10n.colorInherit;

    return TpFieldShell(
      label: label,
      helper: helper,
      error: error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              _Swatch(
                color: swatch,
                inherit: isInherit,
                tooltip: isInherit
                    ? context.l10n.colorInheritTip
                    : context.l10n.colorPickTip,
                onTap: enabled
                    ? () => _openPicker(context, swatch)
                    : null,
              ),
              const SizedBox(width: TpSpacing.s12),
              Expanded(
                child: TpTextField(
                  // Re-seeded when the "use default" switch flips.
                  key: ValueKey<bool>(isInherit),
                  // Deliberately NOT keyed on `wireValue`. A value-derived key
                  // would rebuild the field on every commit, reseeding the
                  // controller and jumping the caret to the end mid-typing —
                  // and it would rewrite the user's lowercase input as uppercase
                  // under their cursor. The field is seeded once from
                  // `initialValue`; an EXTERNAL change (switching items, revert)
                  // is forced by re-keying the whole editor, which the parent
                  // already does with `ValueKey<int>(index)`.
                  initialValue: isInherit ? '' : wireValue,
                  enabled: enabled && !isInherit,
                  hint: isInherit ? inherit : 'AARRGGBB (BGR)',
                  onSubmitted: _commitHex,
                  onChanged: (String v) {
                    // Commit only complete values while typing, so a partially
                    // typed hex does not clobber the stored colour.
                    final int len = v.trim().length;
                    if (len == 6 || len == 8) {
                      _commitHex(v);
                    }
                  },
                  leading: Icon(TpIcons.palette),
                ),
              ),
              if (allowInherit) ...<Widget>[
                const SizedBox(width: TpSpacing.s8),
                TpSwitch(
                  value: isInherit,
                  label: inherit,
                  enabled: enabled,
                  onChanged: (bool v) => onChanged(
                    v ? kColorUseGlobal : wireFromColor(Colors.black),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Accepts the hex the user typed and normalises it to the stored width.
  ///
  /// The user types the value they will see on disk, so no byte swapping happens
  /// here beyond validation — this is the "label the field as BGR" half of the
  /// plan's fix, complemented by the swatch showing the true colour.
  void _commitHex(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      if (allowInherit) onChanged(kColorUseGlobal);
      return;
    }
    final int? parsed = ConfigColor.tryParse(trimmed);
    if (parsed == null) return;
    final int width = trimmed.length <= 6 ? 6 : 8;
    onChanged(
      width == 6 ? ConfigColor.format6(parsed) : ConfigColor.format8(parsed),
    );
  }

  Future<void> _openPicker(BuildContext context, Color? current) async {
    final Color? picked = await ColorPickerPopup.show(
      context,
      initial: current ?? Colors.black,
      title: label,
    );
    if (picked != null) _commit(picked);
  }
}

/// The colour swatch. Checkerboarded when translucent, crossed-out when
/// inheriting — so "transparent" never reads as "black" (the existing bar bug
/// where `bg_color 00000000` is fed to `CreateSolidBrush`) and "inherit" never
/// reads as "white".
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.inherit,
    required this.tooltip,
    this.onTap,
  });

  final Color? color;
  final bool inherit;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final Color? c = color;
    final bool translucent =
        c != null && (c.toARGB32() >> 24) & 0xFF < 0xFF;

    return TpTooltip(
      message: tooltip,
      child: TpFocusRing(
        radius: TpRadius.control,
        enabled: onTap != null,
        onTap: onTap,
        child: TpSurface(
          level: TpSurfaceLevel.inset,
          radius: TpRadius.control,
          clip: true,
          child: SizedBox(
            width: 36,
            height: 36,
            child: inherit
                ? Icon(TpIcons.close, size: 16, color: theme.text.tertiary)
                : _fill(context, c, translucent),
          ),
        ),
      ),
    );
  }

  Widget _fill(BuildContext context, Color? c, bool translucent) {
    if (c == null) {
      return Center(
        child: Icon(TpIcons.warning, size: 14, color: TaskPinTheme.of(context).text.tertiary),
      );
    }
    if (!translucent) return ColoredBox(color: c);
    // A cheap checkerboard: two greys, drawn with a CustomPaint so the widget
    // stays free of raw colour literals at the call site.
    return CustomPaint(
      painter: _CheckerPainter(context),
      child: ColoredBox(color: c),
    );
  }
}

class _CheckerPainter extends CustomPainter {
  _CheckerPainter(this.context);

  final BuildContext context;

  @override
  void paint(Canvas canvas, Size size) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final Paint light = Paint()..color = theme.bg.card;
    final Paint dark = Paint()..color = theme.bg.window;
    const double cell = 6;
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        final bool even = ((x / cell).floor() + (y / cell).floor()) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, y, cell, cell),
          even ? light : dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter old) => false;
}
