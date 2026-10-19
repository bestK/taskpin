// DialogSpec — the Dart face of `TPDialogSpec` / `TPDialogItem`.
//
// Authoritative C definitions:
//   native/engine/taskpin_engine.h   the unified ABI (field names below)
//   lib/scripting.h                  the legacy GDI dialog (behaviour parity)
//   lib/script_dialog.c              the GDI renderer (behaviour parity)
//
// PARSING IS PHASE 3'S JOB. `packages/taskpin_engine/lib/models.dart` will own
// decoding a `TPScriptResult` out of the FFI struct; this file deliberately only
// knows how to build itself from a plain `Map<String, dynamic>` so that package
// can hand over a decoded JSON map without either side depending on the other.
// The map keys are exactly the ones `tool/engine_cli.c` emits, so a golden file
// under `test/dialogs/golden/` can be fed straight in.
//
// This file imports NOTHING from dart:ui on purpose:
//   - colours stay as the ABI's wire strings (`""` = "use the default"), which
//     is field-for-field what the C struct carries (`char color[16]`);
//   - it keeps the model runnable under a bare `dart` VM, so
//     `test/dialogs/spec_parse_selftest.dart` verifies the parser against real
//     engine output with no Flutter, no pub and no packages.
// `dialog_palette.dart` is the dart:ui half that turns a wire string into a
// `Color` for the widgets.

/// Maximum items in one dialog. Mirrors `TP_DIALOG_MAX_ITEMS`.
const int kDialogMaxItems = 8;

/// Maximum table columns. Mirrors `TP_DIALOG_MAX_COLS`.
const int kDialogMaxCols = 6;

/// Maximum table rows. Mirrors `TP_DIALOG_MAX_ROWS`.
const int kDialogMaxRows = 24;

/// Default dialog size when the script asks for 0. `lib/script_dialog.c:75-76`.
const int kDialogDefaultWidth = 400;
const int kDialogDefaultHeight = 300;

/// `TP_CLICK_URL` / `TP_CLICK_DIALOG`.
const int kClickUrl = 0;
const int kClickDialog = 1;

/// The kinds of dialog item.
///
/// `taskpin_design` already has `TpDialogItemType` (text/hr/table/image/button)
/// for `TpDialogSpecPreview`. That enum has no `webview`, and the design package
/// belongs to another agent, so this is a deliberate superset rather than an
/// edit to theirs. `toPreviewItems()` below converts back down for the preview,
/// which is the reconciliation point: the only thing this enum adds is
/// [webview] (carried by the ABI, rendered from Phase 9) and [unknown] (a type
/// a future engine emits that this build does not know).
enum TpDialogItemKind {
  text,
  hr,
  table,
  image,
  button,
  webview,

  /// A `type` string the engine sent that this build does not recognise.
  /// Rendered as a visible warning rather than silently dropped — the C parser
  /// `continue`s on unknown types (`lib/scripting.c:687-691`), which is how a
  /// script's item disappears without explanation.
  unknown,
}

/// One dialog item. Mirrors `TPDialogItem` field-for-field.
class DialogItem {
  const DialogItem({
    required this.kind,
    this.value = '',
    this.color = '',
    this.fontSize = 0,
    this.bold = false,
    this.image = '',
    this.imageWidth = 0,
    this.imageHeight = 0,
    this.url = '',
    this.cmd = '',
    this.bg = '',
    this.webWidth = 0,
    this.webHeight = 0,
    this.columns = const <String>[],
    this.cells = const <List<String>>[],
    this.rowUrls = const <String>[],
    this.rowCmds = const <String>[],
    this.rawType = '',
  });

  /// `type` in the ABI: "text" | "hr" | "table" | "image" | "button" | "webview".
  final TpDialogItemKind kind;

  /// The `type` string as received. Kept so an [TpDialogItemKind.unknown] item
  /// can say *what* it did not understand.
  final String rawType;

  /// Text, or the button label. `TPDialogItem.value`.
  final String value;

  /// `"#RRGGBB"` / `"#RGB"`, or `""` for the default. Text/button foreground.
  final String color;

  /// Point size, `0` = default. `lib/script_dialog.c:123` treats `0` as 10 pt.
  final int fontSize;

  final bool bold;

  /// Inline icon source for a text item (path / URL / `data:` URI).
  final String image;

  /// Requested inline-icon box. `0` = the line height (C: `tm.tmHeight`).
  final int imageWidth;
  final int imageHeight;

  /// Button / table-row URL, or the webview URL.
  final String url;

  /// Button / table-row command.
  final String cmd;

  /// Button background, `""` = default. C default is `RGB(50,50,50)`.
  final String bg;

  /// Webview box size (`web_w` / `web_h`).
  final int webWidth;
  final int webHeight;

  /// Table header labels. At most [kDialogMaxCols].
  final List<String> columns;

  /// Table body rows, each at most `columns.length` wide. At most
  /// [kDialogMaxRows] rows. (The C parser truncates a row to `col_count` —
  /// `lib/scripting.c:627` — so a ragged row is not representable.)
  final List<List<String>> cells;

  /// Per-row URL, parallel to [cells]. Empty string = no URL.
  final List<String> rowUrls;

  /// Per-row command, parallel to [cells]. Empty string = no command.
  final List<String> rowCmds;

  /// Number of header columns actually present.
  int get colCount => columns.length;

  /// Number of body rows actually present.
  int get rowCount => cells.length;

  /// Whether this table row has an action, which is what makes the GDI layer
  /// draw its "Open" button (`lib/script_dialog.c:275`).
  bool rowHasAction(int r) =>
      (r < rowUrls.length && rowUrls[r].isNotEmpty) ||
      (r < rowCmds.length && rowCmds[r].isNotEmpty);

  /// Whether any row of this table has an action.
  bool get hasAnyRowAction {
    for (int r = 0; r < rowCount; r++) {
      if (rowHasAction(r)) {
        return true;
      }
    }
    return false;
  }

  /// Whether this item does anything when activated.
  bool get isActionable => url.isNotEmpty || cmd.isNotEmpty;

  /// Build from the engine's flat item map.
  factory DialogItem.fromJson(Map<String, dynamic> json) {
    final String rawType = _str(json['type']);
    return DialogItem(
      kind: _kindOf(rawType),
      rawType: rawType,
      value: _str(json['value']),
      color: _str(json['color']),
      fontSize: _int(json['font_size']),
      bold: _bool(json['bold']),
      image: _str(json['image']),
      imageWidth: _int(json['image_width']),
      imageHeight: _int(json['image_height']),
      url: _str(json['url']),
      cmd: _str(json['cmd']),
      bg: _str(json['bg']),
      webWidth: _int(json['web_w']),
      webHeight: _int(json['web_h']),
      columns: _clampColumns(_strList(json['columns'])),
      cells: _clampCells(
        _strMatrix(json['rows']),
        _clampColumns(_strList(json['columns'])).length,
      ),
      rowUrls: _clampParallel(_strList(json['row_urls'])),
      rowCmds: _clampParallel(_strList(json['row_cmds'])),
    );
  }

  /// Round-trip back to the engine's key names, so a parsed spec can be
  /// diffed against a golden without a translation layer.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': rawType.isEmpty ? _wireName(kind) : rawType,
    'value': value,
    'color': color,
    'font_size': fontSize,
    'bold': bold ? 1 : 0,
    'image': image,
    'image_width': imageWidth,
    'image_height': imageHeight,
    'url': url,
    'cmd': cmd,
    'bg': bg,
    'web_w': webWidth,
    'web_h': webHeight,
    'col_count': colCount,
    'row_count': rowCount,
    'columns': columns,
    'rows': cells,
    'row_urls': rowUrls,
    'row_cmds': rowCmds,
  };
}

/// A whole dialog. Mirrors `TPDialogSpec` field-for-field.
class DialogSpec {
  const DialogSpec({
    this.title = 'Dialog',
    this.width = kDialogDefaultWidth,
    this.height = kDialogDefaultHeight,
    this.refreshSeconds = 0,
    this.borderless = false,
    this.clickthrough = false,
    this.opacity = 255,
    this.bgColor = '',
    this.transparentBg = false,
    this.items = const <DialogItem>[],
  });

  final String title;

  /// Requested size. `0` is normalised to the C defaults on parse, so a
  /// constructed spec always carries a usable size.
  final int width;
  final int height;

  /// Auto-refresh interval in SECONDS (`0` = none). The ABI field is `refresh`;
  /// `lib/script_dialog.c:395` multiplies by 1000 for `SetTimer`.
  final int refreshSeconds;

  /// No title bar; also makes the window a tool window (hidden from the taskbar
  /// and Alt+Tab) — `lib/script_dialog.c:78-83`.
  final bool borderless;

  /// Mouse clicks pass through to the window beneath.
  final bool clickthrough;

  /// `0`-`255`, `255` = opaque.
  final int opacity;

  /// `""` = default.
  final String bgColor;

  /// Let the host composite the dialog over the desktop instead of painting
  /// [bgColor].
  final bool transparentBg;

  final List<DialogItem> items;

  /// Whether the dialog wants a native window effect applied. Both flags route
  /// the window to a layered one in the C layer (`lib/script_dialog.c:84-85`).
  bool get needsLayered => clickthrough || opacity < 255;

  /// Build from the `dialog` object of a `TPScriptResult`.
  factory DialogSpec.fromJson(Map<String, dynamic> json) {
    final int w = _int(json['width']);
    final int h = _int(json['height']);
    return DialogSpec(
      title: _str(json['title']).isEmpty ? 'Dialog' : _str(json['title']),
      width: w > 0 ? w : kDialogDefaultWidth,
      height: h > 0 ? h : kDialogDefaultHeight,
      refreshSeconds: _int(json['refresh']),
      borderless: _bool(json['borderless']),
      clickthrough: _bool(json['clickthrough']),
      opacity: _clampOpacity(_defaulted(json['opacity'], 255)),
      bgColor: _str(json['bg_color']),
      transparentBg: _bool(json['transparent_bg']),
      items: _clampItems(_items(json['items'])),
    );
  }

  /// Extract the dialog from a whole `TPScriptResult` map.
  ///
  /// Returns null unless the result is clickable with
  /// `click_action == TP_CLICK_DIALOG` and carries at least one item — the same
  /// gate the C layer applies before it will show anything
  /// (`lib/script_dialog.c:362`, `src/bar_window.c:349`).
  static DialogSpec? fromScriptResult(Map<String, dynamic> result) {
    if (!_bool(result['clickable'])) {
      return null;
    }
    if (_int(result['click_action']) != kClickDialog) {
      return null;
    }
    final Object? dialog = result['dialog'];
    if (dialog is! Map) {
      return null;
    }
    final DialogSpec spec = DialogSpec.fromJson(
      Map<String, dynamic>.from(dialog),
    );
    return spec.items.isEmpty ? null : spec;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'title': title,
    'width': width,
    'height': height,
    'refresh': refreshSeconds,
    'borderless': borderless ? 1 : 0,
    'clickthrough': clickthrough ? 1 : 0,
    'opacity': opacity,
    'bg_color': bgColor,
    'transparent_bg': transparentBg ? 1 : 0,
    'item_count': items.length,
    'items': items.map((DialogItem i) => i.toJson()).toList(),
  };

  /// A copy with a replaced item list — used by the refresh loop to swap in a
  /// freshly executed spec while keeping window state (position, size) intact,
  /// which is what the C layer does with its `memcpy` + `InvalidateRect`
  /// (`lib/script_dialog.c:363`).
  DialogSpec withItems(List<DialogItem> newItems) => DialogSpec(
    title: title,
    width: width,
    height: height,
    refreshSeconds: refreshSeconds,
    borderless: borderless,
    clickthrough: clickthrough,
    opacity: opacity,
    bgColor: bgColor,
    transparentBg: transparentBg,
    items: newItems,
  );
}

// ─── parsing helpers ────────────────────────────────────────────────────────
//
// Deliberately total: a malformed or absent field yields the same value the C
// parser would, never a throw. A dialog that fails to parse must still render
// (possibly empty), because the alternative — an exception in the secondary
// window's isolate — is a blank window with no explanation.

TpDialogItemKind _kindOf(String type) {
  switch (type) {
    case 'text':
      return TpDialogItemKind.text;
    case 'hr':
      return TpDialogItemKind.hr;
    case 'table':
      return TpDialogItemKind.table;
    case 'image':
      return TpDialogItemKind.image;
    case 'button':
      return TpDialogItemKind.button;
    case 'webview':
      return TpDialogItemKind.webview;
    default:
      return TpDialogItemKind.unknown;
  }
}

String _wireName(TpDialogItemKind kind) {
  switch (kind) {
    case TpDialogItemKind.text:
      return 'text';
    case TpDialogItemKind.hr:
      return 'hr';
    case TpDialogItemKind.table:
      return 'table';
    case TpDialogItemKind.image:
      return 'image';
    case TpDialogItemKind.button:
      return 'button';
    case TpDialogItemKind.webview:
      return 'webview';
    case TpDialogItemKind.unknown:
      return 'unknown';
  }
}

String _str(Object? v) => v == null ? '' : '$v';

int _int(Object? v) {
  if (v is int) {
    return v;
  }
  if (v is num) {
    return v.toInt();
  }
  if (v is String) {
    return int.tryParse(v) ?? 0;
  }
  return 0;
}

Object? _defaulted(Object? v, Object? fallback) => v ?? fallback;

bool _bool(Object? v) {
  if (v is bool) {
    return v;
  }
  if (v is num) {
    return v != 0;
  }
  if (v is String) {
    return v.isNotEmpty && v != '0' && v.toLowerCase() != 'false';
  }
  return false;
}

int _clampOpacity(Object? v) {
  final int n = _int(v);
  if (n < 0) {
    return 0;
  }
  if (n > 255) {
    return 255;
  }
  return n;
}

List<String> _strList(Object? v) {
  if (v is! List) {
    return const <String>[];
  }
  return v.map(_str).toList(growable: false);
}

List<List<String>> _strMatrix(Object? v) {
  if (v is! List) {
    return const <List<String>>[];
  }
  return v
      .map((Object? row) => row is List ? _strList(row) : const <String>[])
      .toList(growable: false);
}

List<String> _clampColumns(List<String> cols) =>
    cols.length <= kDialogMaxCols ? cols : cols.sublist(0, kDialogMaxCols);

List<String> _clampParallel(List<String> v) =>
    v.length <= kDialogMaxRows ? v : v.sublist(0, kDialogMaxRows);

/// Truncate to [kDialogMaxRows] rows, and each row to [cols] cells.
///
/// The cell truncation mirrors `lib/scripting.c:627`
/// (`if (rc > item->col_count) rc = item->col_count;`) — a row is never wider
/// than the header, so the renderer can lay out on a fixed grid.
List<List<String>> _clampCells(List<List<String>> rows, int cols) {
  final List<List<String>> limited = rows.length <= kDialogMaxRows
      ? rows
      : rows.sublist(0, kDialogMaxRows);
  return limited
      .map((List<String> r) => r.length <= cols ? r : r.sublist(0, cols))
      .toList(growable: false);
}

List<DialogItem> _items(Object? v) {
  if (v is! List) {
    return const <DialogItem>[];
  }
  final List<DialogItem> out = <DialogItem>[];
  for (final Object? e in v) {
    if (out.length >= kDialogMaxItems) {
      break;
    }
    if (e is Map) {
      out.add(DialogItem.fromJson(Map<String, dynamic>.from(e)));
    }
  }
  return out;
}

List<DialogItem> _clampItems(List<DialogItem> items) =>
    items.length <= kDialogMaxItems ? items : items.sublist(0, kDialogMaxItems);
