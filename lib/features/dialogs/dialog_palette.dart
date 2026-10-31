// The dart:ui half of the dialog model: wire colour strings -> `Color`, and
// the conversion into `taskpin_design`'s preview item.
//
// Kept separate from `dialog_spec.dart` so the model itself stays importable
// from a bare Dart VM (see `test/dialogs/spec_parse_selftest.dart`). Everything
// that needs `dart:ui` or the design package lives here.

import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/painting.dart' show HSLColor;
import 'package:flutter/widgets.dart' show BuildContext, InheritedWidget;
import 'package:taskpin_design/taskpin_design.dart';

import 'dialog_spec.dart';

/// Approximate background surface colors of macOS NSPopover translucent material.
///
/// Under standard macOS system appearance, NSPopover with `.popover` material
/// composites blurred vibrancy behind the content.
///
/// In light mode, the translucent frosted white reads visually around #ECECEC
/// (luminance ~0.83).
/// In dark mode, the translucent frosted charcoal reads visually around #242424
/// (luminance ~0.02).
const Color kMacPopoverLightSurface = Color(0xFFECECEC);
const Color kMacPopoverDarkSurface = Color(0xFF242424);

/// Injects the dialog's surface rendering state into the item subtree.
///
/// Popover mode (`hostDrawsSurface == true`) renders directly on native macOS
/// NSPopover material (or an explicit script `bg_color` fill), whereas Window
/// mode (`hostDrawsSurface == false`, Windows default) renders a self-contained
/// card where script colours must stay strictly untouched.
class DialogSurfaceContext extends InheritedWidget {
  const DialogSurfaceContext({
    super.key,
    required this.hostDrawsSurface,
    required this.surfaceColor,
    required super.child,
  });

  /// Whether the host renders the surface (macOS popover mode).
  final bool hostDrawsSurface;

  /// The effective background colour behind the content.
  final Color surfaceColor;

  static DialogSurfaceContext? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DialogSurfaceContext>();

  @override
  bool updateShouldNotify(DialogSurfaceContext oldWidget) =>
      hostDrawsSurface != oldWidget.hostDrawsSurface ||
      surfaceColor != oldWidget.surfaceColor;
}

/// Parse a dialog colour string the way the C engine does.
///
/// `parse_color_str` (`lib/scripting.c:149-161`) accepts:
///   - `#RGB`   — each digit doubled (`#ABC` -> `#AABBCC`), line 154-156
///   - `#RRGGBB` — as-is, line 157-159
///   - anything else, or `""` — the "use the default" sentinel
///
/// Returns null for the sentinel, which is the Dart-idiomatic spelling of the
/// same idea (the C side uses `0xFFFFFFFF`).
///
/// Deliberately NOT `TpBarSpan.parseWireColor`: that one requires exactly
/// `#RRGGBB` and rejects the 3-digit form the dialog DSL accepts, and it lives
/// in the design package, which is another agent's file. Not reusing
/// `TpColorHex.fromWire` either — that parses config.json's `AARRGGBB`, a
/// different format for a different purpose.
Color? parseDialogColor(String wire) {
  if (wire.isEmpty) {
    return null;
  }
  String s = wire;
  if (s.startsWith('#')) {
    s = s.substring(1);
  }
  int r;
  int g;
  int b;
  if (s.length == 3) {
    final int? v = int.tryParse(s, radix: 16);
    if (v == null) {
      return null;
    }
    // Each nibble doubled, matching `r *= 17` in the C parser.
    r = ((v >> 8) & 0xF) * 17;
    g = ((v >> 4) & 0xF) * 17;
    b = (v & 0xF) * 17;
  } else if (s.length == 6) {
    final int? v = int.tryParse(s, radix: 16);
    if (v == null) {
      return null;
    }
    r = (v >> 16) & 0xFF;
    g = (v >> 8) & 0xFF;
    b = v & 0xFF;
  } else {
    return null;
  }
  return Color.fromARGB(255, r, g, b);
}

/// WCAG 2.1 contrast ratio between two colours.
///
/// Returns a value between 1.0 (identical) and 21.0 (black on white).
double contrastRatio(Color a, Color b) {
  final double l1 = a.computeLuminance();
  final double l2 = b.computeLuminance();
  final double lighter = math.max(l1, l2);
  final double darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Ensure [foreground] has at least [minContrast] against [surface].
///
/// In popover mode, scripts often hard-code light colours like `#FFFFFF` or
/// `#4FC3F7` assuming a dark background. On a light macOS popover appearance,
/// these become illegible.
///
/// This principled adaptation preserves the script author's chosen hue and
/// saturation in HSL space, shifting only lightness until the target contrast
/// ratio is met. If the colour already satisfies [minContrast] (or on dark
/// surfaces where contrast is already high), it is returned unmodified.
Color ensureContrast(
  Color foreground,
  Color surface, {
  double minContrast = 4.5,
}) {
  if (contrastRatio(foreground, surface) >= minContrast) {
    return foreground;
  }

  final HSLColor hsl = HSLColor.fromColor(foreground);
  final bool surfaceIsLight = surface.computeLuminance() > 0.5;

  // For near-neutral / white text (saturation < 0.05): on a light surface,
  // drop to crisp dark text matching primary readability.
  if (hsl.saturation < 0.05 && surfaceIsLight) {
    final Color candidate = hsl.withLightness(math.min(hsl.lightness, 0.15)).toColor();
    if (contrastRatio(candidate, surface) >= minContrast) {
      return candidate;
    }
  }

  double low = surfaceIsLight ? 0.0 : hsl.lightness;
  double high = surfaceIsLight ? hsl.lightness : 1.0;
  Color best = foreground;

  // Binary search for the closest lightness that satisfies the contrast threshold.
  for (int i = 0; i < 16; i++) {
    final double mid = (low + high) / 2;
    final Color candidate = hsl.withLightness(mid).toColor();
    final double ratio = contrastRatio(candidate, surface);

    if (ratio >= minContrast) {
      best = candidate;
      if (surfaceIsLight) {
        // Try higher lightness (closer to original color)
        low = mid;
      } else {
        // Try lower lightness (closer to original color)
        high = mid;
      }
    } else {
      if (surfaceIsLight) {
        // Too light, must be darker
        high = mid;
      } else {
        // Too dark, must be lighter
        low = mid;
      }
    }
  }

  return best;
}

/// Resolve an item's foreground against the theme default.
///
/// The C renderer's default is `RGB(220,220,220)` (`DIALOG_FG`,
/// `lib/script_dialog.c:11`). In TaskPin, body text resolves to `theme.text.primary`,
/// while label or caption-like text resolves to `theme.text.secondary`.
/// An explicit script colour wins when provided.
Color dialogForeground(
  TaskPinTheme theme,
  String wire, {
  bool isLabel = false,
}) =>
    parseDialogColor(wire) ??
    (isLabel ? theme.text.secondary : theme.text.primary);

/// Resolve a button background against the theme default.
///
/// When the script specifies no explicit background, standard buttons rest on
/// `theme.control.fill` to fit the Aurora control silhouette. An explicit
/// script background (`#RRGGBB` or `#RGB`) takes precedence.
Color dialogButtonBackground(TaskPinTheme theme, String wire) =>
    parseDialogColor(wire) ?? theme.control.fill;

/// Point size -> logical pixels, matching `create_dialog_font`.
///
/// C: `-MulDiv(pt, 96, 72)` i.e. `pt * 96 / 72` at 96 dpi
/// (`lib/script_dialog.c:111`). `0` means "the default size", which the C layer
/// spells as 10 pt; callers that want the type-scale default should pass the
/// role style instead and only call this when `fontSize > 0`.
double dialogFontPixels(int pointSize) =>
    pointSize > 0 ? pointSize * 96 / 72 : 10 * 96 / 72;

/// The C layer's "default point size" for dialog text (`lib/script_dialog.c:123`).
const int kDialogDefaultPointSize = 10;

/// Convert a parsed item into `TpDialogSpecPreview`'s item shape.
///
/// Returns null for [TpDialogItemKind.webview] and
/// [TpDialogItemKind.unknown]: the design package's preview enum has no case
/// for either, and its own doc comment calls it "deliberately schematic", so
/// the manager window renders its own placeholder rather than a wrong-shaped
/// preview. This is the single reconciliation point with `taskpin_design` —
/// if that package later grows `webview`, only this function changes.
TpDialogSpecItem? toPreviewItem(DialogItem item) {
  switch (item.kind) {
    case TpDialogItemKind.text:
      return TpDialogSpecItem(type: TpDialogItemType.text, text: item.value);
    case TpDialogItemKind.hr:
      return const TpDialogSpecItem(type: TpDialogItemType.hr);
    case TpDialogItemKind.image:
      return TpDialogSpecItem(
        type: TpDialogItemType.image,
        text: item.image,
        width: item.imageWidth,
        height: item.imageHeight,
      );
    case TpDialogItemKind.button:
      return TpDialogSpecItem(
        type: TpDialogItemType.button,
        text: item.value,
        url: item.url,
        cmd: item.cmd,
      );
    case TpDialogItemKind.table:
      // Row 0 of the preview's `rows` is its header, so the columns are
      // prepended — see `TpDialogSpecPreview._table`.
      return TpDialogSpecItem(
        type: TpDialogItemType.table,
        rows: <List<String>>[
          if (item.columns.isNotEmpty) item.columns,
          ...item.cells,
        ],
      );
    case TpDialogItemKind.webview:
    case TpDialogItemKind.unknown:
      return null;
  }
}

/// Every item of a spec that the preview can represent, dropping the rest.
List<TpDialogSpecItem> toPreviewItems(DialogSpec spec) => spec.items
    .map(toPreviewItem)
    .whereType<TpDialogSpecItem>()
    .toList(growable: false);
