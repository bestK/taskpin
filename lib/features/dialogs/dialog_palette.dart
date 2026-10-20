// The dart:ui half of the dialog model: wire colour strings -> `Color`, and
// the conversion into `taskpin_design`'s preview item.
//
// Kept separate from `dialog_spec.dart` so the model itself stays importable
// from a bare Dart VM (see `test/dialogs/spec_parse_selftest.dart`). Everything
// that needs `dart:ui` or the design package lives here.

import 'dart:ui' show Color;

import 'package:taskpin_design/taskpin_design.dart';

import 'dialog_spec.dart';

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
