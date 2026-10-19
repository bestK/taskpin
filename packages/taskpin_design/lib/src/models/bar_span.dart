// The bar span model.
//
// This mirrors the `TPSpan` C ABI field-for-field. The authoritative C
// definition is `native/engine/taskpin_engine.h`:
//
//   typedef struct {
//     char text[512];
//     char color[16];   // "#RRGGBB" or "" = default
//     int  font_size;   // 0 = default
//     int  align;       // 0 left / 1 right / 2 center
//     int  newline;     // 1 = starts a new line
//     int  is_image, img_w, img_h;
//   } TPSpan;
//
// The field names, order and semantics here are the contract. If the C struct
// changes, this file changes in the same commit, and the FFI layer
// (`packages/taskpin_engine`) is the thing that actually marshals between them.
//
// Why the model lives in the design package rather than the engine package:
// `TpBarPreviewStrip` and `TpSpanInspector` must render the SAME span model the
// bar does, so that "what you see in the manager window is what appears in the
// taskbar". Putting the model in the engine package would make the design
// package depend on FFI, which it must not.

import 'dart:ui' show Color;

/// Horizontal alignment of a span within its line.
///
/// Integer values match the C ABI exactly. Do not reorder.
enum TpSpanAlign {
  left(0),
  right(1),
  center(2);

  const TpSpanAlign(this.abiValue);

  /// The `align` int in `TPSpan`.
  final int abiValue;

  /// Parse the ABI int. Unknown values fall back to [left], matching the
  /// native renderers' `default:` branch.
  static TpSpanAlign fromAbi(int value) {
    switch (value) {
      case 1:
        return TpSpanAlign.right;
      case 2:
        return TpSpanAlign.center;
      default:
        return TpSpanAlign.left;
    }
  }
}

/// One rendered span inside a bar segment or a dialog.
///
/// Immutable and `const`-constructible so previews can be built in const
/// widget trees.
class TpBarSpan {
  const TpBarSpan({
    this.text = '',
    this.color,
    this.fontSize = 0,
    this.align = TpSpanAlign.left,
    this.newline = false,
    this.isImage = false,
    this.imageWidth = 0,
    this.imageHeight = 0,
  });

  /// Plain text, or the image source when [isImage] is true.
  ///
  /// The C ABI caps this at 512 bytes; the renderer truncates rather than
  /// overflows. Callers should not rely on longer strings surviving.
  final String text;

  /// `"#RRGGBB"` in the ABI. `null` means "use the token default"
  /// (`bar/label` for labels, `bar/value` for values).
  ///
  /// Deliberately nullable rather than an empty string: the C side uses `""`
  /// as the sentinel, but in Dart an absent colour should be absent.
  final Color? color;

  /// Point size. `0` means "use the default" (`TpBarTypography.labelSize`).
  final int fontSize;

  /// Horizontal alignment within the line.
  final TpSpanAlign align;

  /// When true, this span begins a new line (Windows allows 2, macOS 1).
  final bool newline;

  /// Whether [text] is an image source (path, URL or `data:` URI).
  final bool isImage;

  /// Intrinsic image size, when known. `0` means "size from the image".
  final int imageWidth;
  final int imageHeight;

  /// The `color` field as it appears on the wire: `"#RRGGBB"` or `""`.
  String get colorWire {
    final Color? c = color;
    if (c == null) {
      return '';
    }
    final int argb = c.toARGB32();
    final int r = (argb >> 16) & 0xFF;
    final int g = (argb >> 8) & 0xFF;
    final int b = argb & 0xFF;
    return '#'
        '${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';
  }

  /// Build from a `"#RRGGBB"` wire string. Empty or malformed yields null.
  ///
  /// Built with `Color.fromARGB` rather than an `0xFF000000 | value` literal so
  /// that this file stays free of `Color(0x...)` — see
  /// `test/no_raw_colors_test.dart`. The opacity is always fully opaque: the
  /// bar span ABI carries `#RRGGBB` with no alpha channel.
  static Color? parseWireColor(String wire) {
    if (wire.isEmpty || wire.length != 7 || !wire.startsWith('#')) {
      return null;
    }
    final int? value = int.tryParse(wire.substring(1), radix: 16);
    if (value == null) {
      return null;
    }
    return Color.fromARGB(
      255,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    );
  }

  TpBarSpan copyWith({
    String? text,
    Color? color,
    bool clearColor = false,
    int? fontSize,
    TpSpanAlign? align,
    bool? newline,
    bool? isImage,
    int? imageWidth,
    int? imageHeight,
  }) =>
      TpBarSpan(
        text: text ?? this.text,
        color: clearColor ? null : (color ?? this.color),
        fontSize: fontSize ?? this.fontSize,
        align: align ?? this.align,
        newline: newline ?? this.newline,
        isImage: isImage ?? this.isImage,
        imageWidth: imageWidth ?? this.imageWidth,
        imageHeight: imageHeight ?? this.imageHeight,
      );
}

/// The full bar content for one pinned item: up to 2 lines of spans.
///
/// Mirrors `TPDisplayContent` / the `rich` field of `TPScriptResult`.
class TpBarContent {
  const TpBarContent({this.spans = const <TpBarSpan>[]});

  /// The C ABI caps a display at 32 spans. The renderer drops the overflow;
  /// this constant lets the inspector warn before that happens.
  static const int maxSpans = 32;

  final List<TpBarSpan> spans;

  /// Group spans into lines, honouring the `newline` flag.
  ///
  /// The first span always starts line 1. A span with `newline: true` starts a
  /// new line; everything else appends to the current one.
  List<List<TpBarSpan>> get lines {
    final List<List<TpBarSpan>> out = <List<TpBarSpan>>[];
    List<TpBarSpan> current = <TpBarSpan>[];
    for (final TpBarSpan s in spans) {
      if (s.newline && current.isNotEmpty) {
        out.add(current);
        current = <TpBarSpan>[];
      }
      current.add(s);
    }
    if (current.isNotEmpty) {
      out.add(current);
    }
    return out;
  }

  /// The number of lines this content occupies.
  int get lineCount => lines.length;

  /// Plain-text fallback, as the C side builds into `display[2048]`.
  String get plainText =>
      lines.map((List<TpBarSpan> l) => l.map((TpBarSpan s) => s.text).join(' ')).join('\n');

  bool get isEmpty => spans.isEmpty;

  /// Truncate to the ABI limit, mirroring the renderer's drop-overflow.
  TpBarContent clamped() => spans.length <= maxSpans
      ? this
      : TpBarContent(spans: spans.sublist(0, maxSpans));
}
