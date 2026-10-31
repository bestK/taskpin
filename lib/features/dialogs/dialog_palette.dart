// The dart:ui half of the dialog model: wire colour strings -> `Color`, and the
// WCAG contrast helpers the item widgets use.
//
// Kept separate from `dialog_spec.dart` so the model itself stays importable
// from a bare Dart VM (see `test/dialogs/spec_parse_selftest.dart`). Everything
// that needs `dart:ui` lives here.

import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/painting.dart' show HSLColor;
import 'package:flutter/widgets.dart' show BuildContext, InheritedWidget;

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

/// Hex digits only. `int.tryParse` alone also takes a sign ("-0FF00").
final RegExp _kHexDigits = RegExp(r'^[0-9a-fA-F]+$');

/// Parse a dialog colour string the way the C engine does, plus alpha.
///
/// `parse_color_str` (`lib/scripting.c:149-161`) accepts:
///   - `#RGB`   — each digit doubled (`#ABC` -> `#AABBCC`), line 154-156
///   - `#RRGGBB` — as-is, line 157-159
///   - anything else, or `""` — the "use the default" sentinel
///
/// This build also accepts `#RRGGBBAA` (CSS order, alpha last) so a script can
/// ask for a translucent fill. The C parser has no alpha; this is the one
/// deliberate extension.
///
/// Returns null for the sentinel and for anything that is not hex digits, which
/// is the Dart-idiomatic spelling of the same idea (the C side uses
/// `0xFFFFFFFF`).
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
  final String s = wire.startsWith('#') ? wire.substring(1) : wire;
  if (!_kHexDigits.hasMatch(s)) {
    return null;
  }
  final int v = int.parse(s, radix: 16);
  switch (s.length) {
    case 3:
      // Each nibble doubled, matching `r *= 17` in the C parser.
      return Color.fromARGB(
        255,
        ((v >> 8) & 0xF) * 17,
        ((v >> 4) & 0xF) * 17,
        (v & 0xF) * 17,
      );
    case 6:
      return Color.fromARGB(255, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
    case 8:
      return Color.fromARGB(
        v & 0xFF,
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
      );
    default:
      return null;
  }
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

const Color _kBlack = Color(0xFF000000);
const Color _kWhite = Color(0xFFFFFFFF);

/// Black or white, whichever has the higher contrast against [background].
///
/// Used for a button's label on a script-chosen fill, and as the last resort
/// when [ensureContrast] cannot reach its target.
Color contrastingTextColor(Color background) =>
    contrastRatio(_kWhite, background) > contrastRatio(_kBlack, background)
    ? _kWhite
    : _kBlack;

/// Ensure [foreground] has at least [minContrast] against [surface].
///
/// In popover mode, scripts often hard-code light colours like `#FFFFFF` or
/// `#4FC3F7` assuming a dark background. On a light macOS popover appearance,
/// these become illegible.
///
/// This principled adaptation preserves the script author's chosen hue and
/// saturation in HSL space, shifting only lightness until the target contrast
/// ratio is met. The search runs toward whichever of black or white contrasts
/// more with [surface], so a mid-grey surface is approached from the side that
/// can reach the target at all. If even that extreme falls short, the extreme
/// itself is returned: it is the most legible colour available. If the colour
/// already satisfies [minContrast], it is returned unmodified.
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

  // Search toward the extreme with more contrast. Lightness 1 is white and 0 is
  // black, so the extreme is the most legible lightness this hue can reach.
  final Color extreme = contrastingTextColor(surface);
  if (contrastRatio(extreme, surface) < minContrast) {
    return extreme;
  }
  final double extremeLightness = extreme == _kWhite ? 1.0 : 0.0;

  // Binary search between the original lightness (known to fail) and the
  // extreme (known to pass), for the lightness nearest the original that passes.
  double fails = hsl.lightness;
  double passes = extremeLightness;
  for (int i = 0; i < 16; i++) {
    final double mid = (fails + passes) / 2;
    if (contrastRatio(hsl.withLightness(mid).toColor(), surface) >= minContrast) {
      passes = mid;
    } else {
      fails = mid;
    }
  }
  return hsl.withLightness(passes).toColor();
}

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
