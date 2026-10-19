/// Immutable Dart models for the engine's output, plus the conversion from the
/// C structs in `bindings.dart`.
///
/// The conversion functions take a `*Native` struct that points into native
/// memory and copy everything out immediately. Nothing in this file retains a
/// `Pointer`, so a model is safe to send across an isolate boundary and safe to
/// keep after the engine has been disposed — which is the whole point of the
/// isolate design.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'bindings.dart';

/// How a span's text is aligned within its line.
///
/// Mirrors `TP_SPAN_ALIGN_*`. An unrecognised value from a future engine
/// degrades to [left] rather than throwing: the bar must still render.
enum SpanAlign {
  left(tpSpanAlignLeft),
  right(tpSpanAlignRight),
  center(tpSpanAlignCenter);

  const SpanAlign(this.wireValue);

  /// The `TP_SPAN_ALIGN_*` integer this maps to.
  final int wireValue;

  static SpanAlign fromWire(int value) {
    for (final a in SpanAlign.values) {
      if (a.wireValue == value) return a;
    }
    return SpanAlign.left;
  }
}

/// What clicking the bar does.
///
/// Mirrors `TP_CLICK_*`. Note the engine's default is [url] (its
/// `result_init` sets `click_action = TP_CLICK_URL`), so an unrecognised value
/// also degrades to [url].
enum ClickAction {
  url(tpClickUrl),
  dialog(tpClickDialog);

  const ClickAction(this.wireValue);

  /// The `TP_CLICK_*` integer this maps to.
  final int wireValue;

  static ClickAction fromWire(int value) {
    for (final a in ClickAction.values) {
      if (a.wireValue == value) return a;
    }
    return ClickAction.url;
  }
}

/// The six dialog item types the engine understands.
///
/// The engine drops an item whose `type` it does not recognise (`taskpin_lua.c`
/// `continue`s past it), so [unknown] should never be observed from this
/// engine; it exists so that a future engine adding a type cannot crash the UI.
enum DialogItemType {
  text('text'),
  hr('hr'),
  table('table'),
  image('image'),
  button('button'),
  webview('webview'),
  unknown('');

  const DialogItemType(this.wireValue);

  /// The string the engine stores in `TPDialogItem.type`.
  final String wireValue;

  static DialogItemType fromWire(String value) {
    for (final t in DialogItemType.values) {
      if (t.wireValue == value) return t;
    }
    return DialogItemType.unknown;
  }
}

/// One styled run of the bar display. `TPSpan` in the C ABI.
final class Span {
  const Span({
    required this.text,
    required this.color,
    required this.fontSize,
    required this.align,
    required this.newline,
    required this.isImage,
    required this.imageWidth,
    required this.imageHeight,
  });

  /// The text, or the image source when [isImage] is true.
  final String text;

  /// `"#RRGGBB"` / `"#RGB"`, or `''` for the host's default.
  final String color;

  /// Point size, or 0 for the host's default.
  final int fontSize;

  final SpanAlign align;

  /// True when this span starts a new line.
  final bool newline;

  /// True when [text] is an image source rather than literal text.
  final bool isImage;

  /// Requested display width when [isImage]; 0 otherwise.
  final int imageWidth;

  /// Requested display height when [isImage]; 0 otherwise.
  final int imageHeight;

  /// Copy one `TPSpan` out of native memory.
  factory Span.fromNative(TPSpan native) => Span(
        text: _readCString(native.text, tpSpanTextLen),
        color: _readCString(native.color, tpColorLen),
        fontSize: native.fontSize,
        align: SpanAlign.fromWire(native.align),
        newline: native.newline != 0,
        isImage: native.isImage != 0,
        imageWidth: native.imgW,
        imageHeight: native.imgH,
      );

  @override
  bool operator ==(Object other) =>
      other is Span &&
      other.text == text &&
      other.color == color &&
      other.fontSize == fontSize &&
      other.align == align &&
      other.newline == newline &&
      other.isImage == isImage &&
      other.imageWidth == imageWidth &&
      other.imageHeight == imageHeight;

  @override
  int get hashCode => Object.hash(
      text, color, fontSize, align, newline, isImage, imageWidth, imageHeight);

  @override
  String toString() => 'Span(${jsonEncode(text)}, $color, size: $fontSize, '
      'align: ${align.name}, newline: $newline, image: $isImage)';
}

/// One entry of a dialog's `content` table. `TPDialogItem` in the C ABI.
///
/// The C struct is a single flat record whose meaningful fields depend on
/// [type]; this mirrors that rather than pretending it is a sealed hierarchy,
/// because `models.dart`'s job is to be a faithful copy of the ABI. Consumers
/// (the Phase 6 dialog window) switch on [type].
final class DialogItem {
  const DialogItem({
    required this.type,
    required this.value,
    required this.color,
    required this.fontSize,
    required this.bold,
    required this.image,
    required this.imageWidth,
    required this.imageHeight,
    required this.url,
    required this.cmd,
    required this.bg,
    required this.webWidth,
    required this.webHeight,
    required this.columns,
    required this.rows,
    required this.rowUrls,
    required this.rowCmds,
  });

  /// Which of the fields below are meaningful.
  final DialogItemType type;

  /// Text content, or a button label.
  final String value;

  /// `"#RRGGBB"` / `"#RGB"`, or `''` for default.
  final String color;

  /// Point size, or 0 for default.
  final int fontSize;

  /// True for a bold text item.
  final bool bold;

  /// Inline icon source for a text item.
  final String image;

  /// Inline icon width, or 0.
  final int imageWidth;

  /// Inline icon height, or 0.
  final int imageHeight;

  /// Button / table-row URL, or the webview URL.
  final String url;

  /// Button / table-row command.
  final String cmd;

  /// Button background colour, or `''` for default.
  final String bg;

  /// Webview box width ([DialogItemType.webview]).
  final int webWidth;

  /// Webview box height ([DialogItemType.webview]).
  final int webHeight;

  /// Table header cells ([DialogItemType.table]); length `colCount`.
  final List<String> columns;

  /// Table body rows ([DialogItemType.table]); `rows[r][c]`, `rowCount` rows of
  /// `colCount` cells each.
  final List<List<String>> rows;

  /// Per-row click URL; length `rowCount`.
  final List<String> rowUrls;

  /// Per-row command; length `rowCount`.
  final List<String> rowCmds;

  /// Copy one `TPDialogItem` out of native memory.
  ///
  /// Only `columns[0..colCount)`, `cells[0..rowCount)[0..colCount)` and
  /// `rowUrls/rowCmds[0..rowCount)` are read — the fixed-capacity arrays hold
  /// stale bytes past those counts, and copying them out would surface
  /// garbage.
  factory DialogItem.fromNative(TPDialogItem native) {
    final type = DialogItemType.fromWire(_readCString(native.type, 16));
    final colCount = native.colCount.clamp(0, tpDialogMaxCols);
    final rowCount = native.rowCount.clamp(0, tpDialogMaxRows);

    final columns = <String>[
      for (var c = 0; c < colCount; c++) _readCString(native.columns[c], 64),
    ];

    final rows = <List<String>>[
      for (var r = 0; r < rowCount; r++)
        <String>[
          for (var c = 0; c < colCount; c++) _readCString(native.cells[r][c], 64),
        ],
    ];

    return DialogItem(
      type: type,
      value: _readCString(native.value, 256),
      color: _readCString(native.color, tpColorLen),
      fontSize: native.fontSize,
      bold: native.bold != 0,
      image: _readCString(native.image, 512),
      imageWidth: native.imageWidth,
      imageHeight: native.imageHeight,
      url: _readCString(native.url, 512),
      cmd: _readCString(native.cmd, 512),
      bg: _readCString(native.bg, tpColorLen),
      webWidth: native.webW,
      webHeight: native.webH,
      columns: columns,
      rows: rows,
      rowUrls: [
        for (var r = 0; r < rowCount; r++) _readCString(native.rowUrls[r], 256),
      ],
      rowCmds: [
        for (var r = 0; r < rowCount; r++) _readCString(native.rowCmds[r], 256),
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DialogItem &&
      other.type == type &&
      other.value == value &&
      other.color == color &&
      other.fontSize == fontSize &&
      other.bold == bold &&
      other.image == image &&
      other.imageWidth == imageWidth &&
      other.imageHeight == imageHeight &&
      other.url == url &&
      other.cmd == cmd &&
      other.bg == bg &&
      other.webWidth == webWidth &&
      other.webHeight == webHeight &&
      _listEq(other.columns, columns) &&
      _listListEq(other.rows, rows) &&
      _listEq(other.rowUrls, rowUrls) &&
      _listEq(other.rowCmds, rowCmds);

  @override
  int get hashCode => Object.hash(
        type,
        value,
        color,
        fontSize,
        bold,
        image,
        imageWidth,
        imageHeight,
        url,
        cmd,
        bg,
        webWidth,
        webHeight,
        Object.hashAll(columns),
        Object.hashAll(rows.map(Object.hashAll)),
        Object.hashAll(rowUrls),
        Object.hashAll(rowCmds),
      );

  @override
  String toString() => 'DialogItem(${type.name}, ${jsonEncode(value)})';
}

/// The `dialog({...})` spec. `TPDialogSpec` in the C ABI.
final class DialogSpec {
  const DialogSpec({
    required this.title,
    required this.width,
    required this.height,
    required this.refresh,
    required this.borderless,
    required this.clickthrough,
    required this.opacity,
    required this.backgroundColor,
    required this.transparentBackground,
    required this.items,
  });

  final String title;
  final int width;
  final int height;

  /// Auto-refresh interval in seconds; 0 = none.
  final int refresh;

  final bool borderless;
  final bool clickthrough;

  /// 0-255; 255 = opaque (the engine's default).
  final int opacity;

  /// `""` = host default.
  final String backgroundColor;

  /// True when the host should composite the dialog over the desktop instead
  /// of painting [backgroundColor].
  final bool transparentBackground;

  /// Length is the C `item_count`, at most `TP_DIALOG_MAX_ITEMS`.
  final List<DialogItem> items;

  /// Copy one `TPDialogSpec` out of native memory.
  factory DialogSpec.fromNative(TPDialogSpec native) {
    final count = native.itemCount.clamp(0, tpDialogMaxItems);
    return DialogSpec(
      title: _readCString(native.title, 128),
      width: native.width,
      height: native.height,
      refresh: native.refresh,
      borderless: native.borderless != 0,
      clickthrough: native.clickthrough != 0,
      opacity: native.opacity,
      backgroundColor: _readCString(native.bgColor, tpColorLen),
      transparentBackground: native.transparentBg != 0,
      items: [
        for (var i = 0; i < count; i++) DialogItem.fromNative(native.items[i]),
      ],
    );
  }

  /// An empty spec, matching what the engine's `result_init` leaves behind when
  /// the script returns no dialog (opacity 255 is the one non-zero default).
  static const empty = DialogSpec(
    title: '',
    width: 0,
    height: 0,
    refresh: 0,
    borderless: false,
    clickthrough: false,
    opacity: 255,
    backgroundColor: '',
    transparentBackground: false,
    items: [],
  );

  @override
  bool operator ==(Object other) =>
      other is DialogSpec &&
      other.title == title &&
      other.width == width &&
      other.height == height &&
      other.refresh == refresh &&
      other.borderless == borderless &&
      other.clickthrough == clickthrough &&
      other.opacity == opacity &&
      other.backgroundColor == backgroundColor &&
      other.transparentBackground == transparentBackground &&
      _listEq(other.items, items);

  @override
  int get hashCode => Object.hash(
      title,
      width,
      height,
      refresh,
      borderless,
      clickthrough,
      opacity,
      backgroundColor,
      transparentBackground,
      Object.hashAll(items));

  @override
  String toString() =>
      'DialogSpec(${jsonEncode(title)}, ${width}x$height, ${items.length} items)';
}

/// Everything one script execution produced. `TPScriptResult` in the C ABI.
final class ScriptResult {
  const ScriptResult({
    required this.ok,
    required this.error,
    required this.display,
    required this.spans,
    required this.clickable,
    required this.clickAction,
    required this.clickUrl,
    required this.dialog,
  });

  /// False when the script raised a Lua error. The script's partial output is
  /// still present, but [display]/[spans] are what the failed run left behind.
  final bool ok;

  /// Lua error text; `''` on success.
  ///
  /// This is the ABI's replacement for `lib/scripting.c`'s habit of writing the
  /// traceback into `display` — where the bar then rendered it. A host must
  /// show [error] as an error state and never put it on the bar.
  final String error;

  /// Plain-text fallback. Per the engine, this is every span's `text`
  /// concatenated — including image sources — so a host that renders [spans]
  /// should ignore this.
  final String display;

  /// Rich spans; use these when non-empty.
  final List<Span> spans;

  /// Whether the bar responds to clicks at all.
  final bool clickable;

  /// What a click does.
  final ClickAction clickAction;

  /// Target URL; meaningful when [clickAction] is [ClickAction.url].
  final String clickUrl;

  /// The click-through dialog spec; meaningful when [clickAction] is
  /// [ClickAction.dialog].
  final DialogSpec dialog;

  /// Copy a whole `TPScriptResult` out of native memory.
  ///
  /// `spans` is read up to `rich.count`; `dialog` is always read, because the
  /// engine fills it unconditionally (`result_init`) and a golden can therefore
  /// compare it even when `click_action` is [ClickAction.url].
  factory ScriptResult.fromNative(TPScriptResult native) {
    final spanCount = native.rich.count.clamp(0, tpMaxSpans);
    return ScriptResult(
      ok: native.ok != 0,
      error: _readCString(native.error, tpErrorLen),
      display: _readCString(native.display, tpDisplayLen),
      spans: [
        for (var i = 0; i < spanCount; i++) Span.fromNative(native.rich.spans[i]),
      ],
      clickable: native.clickable != 0,
      clickAction: ClickAction.fromWire(native.clickAction),
      clickUrl: _readCString(native.clickUrl, tpUrlLen),
      dialog: DialogSpec.fromNative(native.dialog),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ScriptResult &&
      other.ok == ok &&
      other.error == error &&
      other.display == display &&
      _listEq(other.spans, spans) &&
      other.clickable == clickable &&
      other.clickAction == clickAction &&
      other.clickUrl == clickUrl &&
      other.dialog == dialog;

  @override
  int get hashCode => Object.hash(ok, error, display, Object.hashAll(spans),
      clickable, clickAction, clickUrl, dialog);

  @override
  String toString() => 'ScriptResult(ok: $ok, spans: ${spans.length}, '
      'clickable: $clickable, ${clickAction.name}'
      '${error.isEmpty ? '' : ', error: ${jsonEncode(error)}'})';
}

/// One `-- @param` declaration. `TPParamDecl` in the C ABI.
final class ParamDecl {
  const ParamDecl({required this.key, required this.type, required this.label});

  /// The parameter name, as written in the header.
  final String key;

  /// The declared type, verbatim (`"string"`, `"number"`, ...). The engine does
  /// not validate it; it is metadata for the editor UI.
  final String type;

  /// Human-readable label (may be CJK).
  final String label;

  /// Copy one `TPParamDecl` out of native memory.
  factory ParamDecl.fromNative(TPParamDecl native) => ParamDecl(
        key: _readCString(native.key, 64),
        type: _readCString(native.type, 16),
        label: _readCString(native.label, 128),
      );

  @override
  bool operator ==(Object other) =>
      other is ParamDecl &&
      other.key == key &&
      other.type == type &&
      other.label == label;

  @override
  int get hashCode => Object.hash(key, type, label);

  @override
  String toString() => 'ParamDecl($key: $type, ${jsonEncode(label)})';
}

// ─── helpers ───

/// Read a NUL-terminated UTF-8 string out of a fixed-size C `char[]`.
///
/// [capacity] is passed in rather than derived because `dart:ffi` gives an
/// `Array<Uint8>` no length: the size is a property of the struct field, known
/// only to the caller that declared the `@Array()`.
///
/// Decoding is `allowMalformed`, so a source that was truncated mid-sequence
/// (the engine's `copy_str` can split a multi-byte character at the capacity
/// boundary) yields U+FFFD instead of throwing.
///
/// Reads the array element by element rather than through the `Array.elements`
/// `Uint8List` view, which only exists from Dart 3.8; this keeps the package's
/// SDK floor at 3.6 with no measurable cost at these sizes.
String _readCString(Array<Uint8> array, int capacity) {
  var end = 0;
  while (end < capacity && array[end] != 0) {
    end++;
  }
  if (end == 0) return '';
  final bytes = Uint8List(end);
  for (var i = 0; i < end; i++) {
    bytes[i] = array[i];
  }
  return utf8.decode(bytes, allowMalformed: true);
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _listListEq<T>(List<List<T>> a, List<List<T>> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!_listEq(a[i], b[i])) return false;
  }
  return true;
}
