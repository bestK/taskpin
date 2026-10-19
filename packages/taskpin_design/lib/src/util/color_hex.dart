// Colour <-> string conversion, for config parity.
//
// The existing Windows config stores colours as `"AARRGGBB"` strings
// (`lib/config.h`: `COLORREF bar_bg_color; /* 0xFFFFFFFF = use global default */`).
// That format is frozen: Phase 1 requires byte-for-byte round-tripping of real
// config.json files, and `"FFFFFFFF"` specifically means "inherit the default",
// not "opaque white".
//
// This utility is deliberately in `util/` and not in `tokens/`: it converts
// between the config wire format and `Color`, which is data plumbing, not a
// token. It therefore contains no colour literals.

import 'dart:ui' show Color;

/// Sentinel meaning "use the global/default colour" in config.json.
const String kColorInherit = 'FFFFFFFF';

/// Conversion between the config `AARRGGBB` wire format and [Color].
class TpColorHex {
  const TpColorHex._();

  /// Serialise to the 8-digit uppercase `AARRGGBB` form config.json uses.
  static String toWire(Color color, {bool withAlpha = true}) {
    final String hex = color
        .toARGB32()
        .toRadixString(16)
        .toUpperCase()
        .padLeft(8, '0');
    return withAlpha ? hex : hex.substring(2);
  }

  /// Parse `AARRGGBB` or `RRGGBB` (case-insensitive, optional leading `#`).
  ///
  /// Returns null for anything else, including the empty string. Callers that
  /// need the inherit sentinel should check [isInherit] first.
  static Color? fromWire(String wire) {
    String s = wire.trim();
    if (s.startsWith('#')) {
      s = s.substring(1);
    }
    if (s.length == 6) {
      s = 'FF$s';
    }
    if (s.length != 8) {
      return null;
    }
    final int? value = int.tryParse(s, radix: 16);
    if (value == null) {
      return null;
    }
    return Color(value);
  }

  /// Whether the wire string is the "inherit default" sentinel.
  static bool isInherit(String wire) =>
      wire.trim().toUpperCase() == kColorInherit;

  /// Whether the colour is fully transparent — the case that makes the native
  /// bar switch to a layered window (see the plan's transparency trade-off).
  static bool isTransparent(Color color) =>
      (color.toARGB32() >> 24) & 0xFF == 0;
}
