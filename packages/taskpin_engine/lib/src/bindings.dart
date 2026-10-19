/// dart:ffi bindings for the whole `native/engine/taskpin_engine.h` ABI.
///
/// This file is a 1:1 transcription of the C header. Nothing here is
/// interpreted; see `models.dart` for the struct -> Dart-model conversion.
///
/// Two things are worth knowing before editing it:
///
///  * **Layout drift is the failure mode.** If a `@Array()` dimension or a
///    field's position stops matching the header, `dart:ffi` will read and
///    write the wrong bytes and the process will corrupt memory silently.
///    `test/abi_layout_test.dart` pins every `sizeOf` and every field offset
///    against numbers measured from the C compiler (see `tool/abi_probe.c`),
///    so a mistake here fails loudly instead of at runtime.
///
///  * **The header declares no `tp_last_error`.** Errors come back inside
///    `TPScriptResult.error` with `TPScriptResult.ok == 0`; there is no
///    thread-local error accessor to bind. `EngineApi` surfaces them as
///    `EngineException`.
library;

import 'dart:ffi';

// `Utf8` (the UTF-8 `NativeType` used by every `const char *` in this ABI) is
// declared in package:ffi, not dart:ffi.
import 'package:ffi/ffi.dart';

// ─── capacities (TP_* macros) ───

const int tpMaxSpans = 32;
const int tpSpanTextLen = 512;
const int tpColorLen = 16;
const int tpDisplayLen = 2048;
const int tpUrlLen = 1024;
const int tpErrorLen = 1024;

const int tpDialogMaxItems = 8;
const int tpDialogMaxCols = 6;
const int tpDialogMaxRows = 24;

// ─── span alignment (TP_SPAN_ALIGN_*) ───

const int tpSpanAlignLeft = 0;
const int tpSpanAlignRight = 1;
const int tpSpanAlignCenter = 2;

// ─── click_action (TP_CLICK_*) ───

const int tpClickUrl = 0;
const int tpClickDialog = 1;

/// `TP_DIALOG_TYPE_WEBVIEW`. The engine stores this string in
/// [TPDialogItem.type]; it is carried through for the Flutter host to render.
const String tpDialogTypeWebview = 'webview';

// ─── structs ───
//
// Field names are camelCase Dart; the C member each one maps to is in the doc
// comment, because the ABI test compares against `offsetof(TPSpan, font_size)`
// and the mapping has to be checkable by eye.

/// `TPSpan` — one run of styled text (or one image) on the bar.
final class TPSpan extends Struct {
  /// `char text[TP_SPAN_TEXT_LEN]` — the text, or the image source when
  /// [isImage] is 1.
  @Array(tpSpanTextLen)
  external Array<Uint8> text;

  /// `char color[TP_COLOR_LEN]` — `"#RRGGBB"` / `"#RGB"`, `""` = use default.
  @Array(tpColorLen)
  external Array<Uint8> color;

  /// `int font_size` — 0 = default.
  @Int32()
  external int fontSize;

  /// `int align` — one of `tpSpanAlign*`.
  @Int32()
  external int align;

  /// `int newline` — 1 = this span starts a new line.
  @Int32()
  external int newline;

  /// `int is_image` — 1 = [text] holds an image source.
  @Int32()
  external int isImage;

  /// `int img_w`.
  @Int32()
  external int imgW;

  /// `int img_h`.
  @Int32()
  external int imgH;
}

/// `TPDisplayContent` — a flat span list plus its count.
final class TPDisplayContent extends Struct {
  /// `TPSpan spans[TP_MAX_SPANS]`.
  @Array(tpMaxSpans)
  external Array<TPSpan> spans;

  /// `int count` — how many entries of [spans] are live.
  @Int32()
  external int count;
}

/// `TPDialogItem` — one entry of a dialog's `content` table.
///
/// One struct covers all six item types; which fields are meaningful is
/// selected by [type]. That is the C header's design, not a simplification
/// here, and it is why `models.dart` exposes a single `DialogItem` class with
/// nullable per-type fields rather than a sealed hierarchy.
final class TPDialogItem extends Struct {
  /// `char type[16]` — `"text" | "hr" | "table" | "image" | "button" |
  /// "webview"`.
  @Array(16)
  external Array<Uint8> type;

  /// `char value[256]` — text, or a button label.
  @Array(256)
  external Array<Uint8> value;

  /// `char color[TP_COLOR_LEN]`.
  @Array(tpColorLen)
  external Array<Uint8> color;

  /// `int font_size` — 0 = default.
  @Int32()
  external int fontSize;

  /// `int bold`.
  @Int32()
  external int bold;

  /// `char image[512]` — inline icon source for a text item.
  @Array(512)
  external Array<Uint8> image;

  /// `int image_width`.
  @Int32()
  external int imageWidth;

  /// `int image_height`.
  @Int32()
  external int imageHeight;

  /// `char url[512]` — button / table-row URL, or the webview URL.
  @Array(512)
  external Array<Uint8> url;

  /// `char cmd[512]` — button / table-row command.
  @Array(512)
  external Array<Uint8> cmd;

  /// `char bg[TP_COLOR_LEN]` — button background; `""` = default.
  @Array(tpColorLen)
  external Array<Uint8> bg;

  /// `int web_w` — webview box width.
  @Int32()
  external int webW;

  /// `int web_h` — webview box height.
  @Int32()
  external int webH;

  /// `int col_count` — table column count.
  @Int32()
  external int colCount;

  /// `int row_count` — table row count.
  @Int32()
  external int rowCount;

  /// `char columns[TP_DIALOG_MAX_COLS][64]` — table header cells.
  @Array.multi([tpDialogMaxCols, 64])
  external Array<Array<Uint8>> columns;

  /// `char cells[TP_DIALOG_MAX_ROWS][TP_DIALOG_MAX_COLS][64]` — table body.
  ///
  /// Indexed `cells[row][col]`, each element a 64-byte NUL-terminated string.
  @Array.multi([tpDialogMaxRows, tpDialogMaxCols, 64])
  external Array<Array<Array<Uint8>>> cells;

  /// `char row_urls[TP_DIALOG_MAX_ROWS][256]` — per-row click URL.
  @Array.multi([tpDialogMaxRows, 256])
  external Array<Array<Uint8>> rowUrls;

  /// `char row_cmds[TP_DIALOG_MAX_ROWS][256]` — per-row command.
  @Array.multi([tpDialogMaxRows, 256])
  external Array<Array<Uint8>> rowCmds;
}

/// `TPDialogSpec` — the `dialog({...})` spec a script can return.
final class TPDialogSpec extends Struct {
  /// `char title[128]`.
  @Array(128)
  external Array<Uint8> title;

  /// `int width`.
  @Int32()
  external int width;

  /// `int height`.
  @Int32()
  external int height;

  /// `int refresh` — seconds, 0 = no auto-refresh.
  @Int32()
  external int refresh;

  /// `int borderless`.
  @Int32()
  external int borderless;

  /// `int clickthrough`.
  @Int32()
  external int clickthrough;

  /// `int opacity` — 0-255, 255 = opaque (default).
  @Int32()
  external int opacity;

  /// `char bg_color[TP_COLOR_LEN]` — `""` = default.
  @Array(tpColorLen)
  external Array<Uint8> bgColor;

  /// `int transparent_bg` — 1 = let the host composite over the desktop.
  @Int32()
  external int transparentBg;

  /// `int item_count` — how many entries of [items] are live.
  @Int32()
  external int itemCount;

  /// `TPDialogItem items[TP_DIALOG_MAX_ITEMS]`.
  @Array(tpDialogMaxItems)
  external Array<TPDialogItem> items;
}

/// `TPScriptResult` — everything one script execution produced.
///
/// Allocated with `calloc` on the engine isolate and reused across executions:
/// `tp_execute_*` calls `result_init` (a `memset`) before filling it, so a
/// stale result can never leak into the next call.
final class TPScriptResult extends Struct {
  /// `TPDisplayContent rich` — use when `rich.count > 0`.
  external TPDisplayContent rich;

  /// `char display[TP_DISPLAY_LEN]` — plain-text fallback.
  @Array(tpDisplayLen)
  external Array<Uint8> display;

  /// `int clickable`.
  @Int32()
  external int clickable;

  /// `int click_action` — `tpClickUrl` | `tpClickDialog`.
  @Int32()
  external int clickAction;

  /// `char click_url[TP_URL_LEN]` — valid when [clickAction] == `tpClickUrl`.
  @Array(tpUrlLen)
  external Array<Uint8> clickUrl;

  /// `TPDialogSpec dialog` — valid when [clickAction] == `tpClickDialog`.
  external TPDialogSpec dialog;

  /// `char error[TP_ERROR_LEN]` — Lua error text; empty on success.
  @Array(tpErrorLen)
  external Array<Uint8> error;

  /// `int ok` — 1 = ran without a Lua error.
  @Int32()
  external int ok;
}

/// `TPParamDecl` — one `-- @param` declaration from a script header.
final class TPParamDecl extends Struct {
  /// `char key[64]`.
  @Array(64)
  external Array<Uint8> key;

  /// `char type[16]` — `"string"`, `"number"`, ... as written in the header.
  @Array(16)
  external Array<Uint8> type;

  /// `char label[128]`.
  @Array(128)
  external Array<Uint8> label;
}

// ─── function signatures ───
//
// Opaque `TPEngine*` is bound as `Pointer<Void>`: the header keeps
// `struct TPEngine` behind TASKPIN_ENGINE_INTERNAL, so there is no layout to
// bind and no reason to. Handles are integers on the Dart side (see
// `engine_isolate.dart`) so the ABI can grow to N engines without changing.

/// `typedef void (*TPLogFn)(int level, const char *utf8_msg, void *user)`.
typedef TPLogFnNative = Void Function(Int32 level, Pointer<Utf8> message, Pointer<Void> user);
typedef TPLogFnDart = void Function(int level, Pointer<Utf8> message, Pointer<Void> user);

/// `TPEngine *tp_engine_create(void)`.
typedef TPEngineCreateNative = Pointer<Void> Function();
typedef TPEngineCreateDart = Pointer<Void> Function();

/// `void tp_engine_destroy(TPEngine *e)`.
typedef TPEngineDestroyNative = Void Function(Pointer<Void> engine);
typedef TPEngineDestroyDart = void Function(Pointer<Void> engine);

/// `void tp_set_log_callback(TPEngine *e, TPLogFn cb, void *user)`.
typedef TPSetLogCallbackNative = Void Function(
    Pointer<Void> engine, Pointer<NativeFunction<TPLogFnNative>> callback, Pointer<Void> user);
typedef TPSetLogCallbackDart = void Function(
    Pointer<Void> engine, Pointer<NativeFunction<TPLogFnNative>> callback, Pointer<Void> user);

/// `void tp_engine_set_instruction_budget(TPEngine *e, long long instructions)`.
typedef TPSetInstructionBudgetNative = Void Function(Pointer<Void> engine, Int64 instructions);
typedef TPSetInstructionBudgetDart = void Function(Pointer<Void> engine, int instructions);

/// `int tp_execute_file(TPEngine *e, const char *utf8_path, const char *args_json,
/// TPScriptResult *out)`.
typedef TPExecuteFileNative = Int32 Function(
    Pointer<Void> engine, Pointer<Utf8> path, Pointer<Utf8> argsJson, Pointer<TPScriptResult> out);
typedef TPExecuteFileDart = int Function(
    Pointer<Void> engine, Pointer<Utf8> path, Pointer<Utf8> argsJson, Pointer<TPScriptResult> out);

/// `int tp_execute_template(TPEngine *e, const char *lua_code,
/// const char *response_raw, TPScriptResult *out)`.
typedef TPExecuteTemplateNative = Int32 Function(Pointer<Void> engine, Pointer<Utf8> luaCode,
    Pointer<Utf8> responseRaw, Pointer<TPScriptResult> out);
typedef TPExecuteTemplateDart = int Function(Pointer<Void> engine, Pointer<Utf8> luaCode,
    Pointer<Utf8> responseRaw, Pointer<TPScriptResult> out);

/// `int tp_parse_params(const char *utf8_path, TPParamDecl *out, int max_decls)`.
typedef TPParseParamsNative = Int32 Function(
    Pointer<Utf8> path, Pointer<TPParamDecl> out, Int32 maxDecls);
typedef TPParseParamsDart = int Function(
    Pointer<Utf8> path, Pointer<TPParamDecl> out, int maxDecls);

/// `int tp_parse_refresh(const char *utf8_path)`.
typedef TPParseRefreshNative = Int32 Function(Pointer<Utf8> path);
typedef TPParseRefreshDart = int Function(Pointer<Utf8> path);

/// The looked-up C functions, plus the library they came from.
///
/// Built with [TPEngineLibrary.from]; the lookups are eager so a missing or
/// renamed symbol fails at startup with a clear message instead of at the
/// first call.
final class TPEngineLibrary {
  final DynamicLibrary library;

  final TPEngineCreateDart engineCreate;
  final TPEngineDestroyDart engineDestroy;
  final TPSetLogCallbackDart setLogCallback;
  final TPSetInstructionBudgetDart setInstructionBudget;
  final TPExecuteFileDart executeFile;
  final TPExecuteTemplateDart executeTemplate;
  final TPParseParamsDart parseParams;
  final TPParseRefreshDart parseRefresh;

  TPEngineLibrary._({
    required this.library,
    required this.engineCreate,
    required this.engineDestroy,
    required this.setLogCallback,
    required this.setInstructionBudget,
    required this.executeFile,
    required this.executeTemplate,
    required this.parseParams,
    required this.parseRefresh,
  });

  /// Resolve every ABI symbol out of [library].
  ///
  /// Throws [ArgumentError] naming the missing symbol if the loaded library is
  /// not the TaskPin engine (e.g. a stale DLL).
  factory TPEngineLibrary.from(DynamicLibrary library) {
    // Each lookup is written out rather than hidden behind a generic helper:
    // lookupFunction's two type arguments are what keep this type-safe, and
    // Dart cannot verify `T extends Function` really is a native function type,
    // so a generic wrapper loses the check instead of adding one.
    TPEngineCreateDart create() => _lookup(
        library,
        'tp_engine_create',
        () => library.lookupFunction<TPEngineCreateNative, TPEngineCreateDart>(
            'tp_engine_create'));

    TPEngineDestroyDart destroy() => _lookup(
        library,
        'tp_engine_destroy',
        () => library.lookupFunction<TPEngineDestroyNative, TPEngineDestroyDart>(
            'tp_engine_destroy'));

    TPSetLogCallbackDart setLog() => _lookup(
        library,
        'tp_set_log_callback',
        () => library
            .lookupFunction<TPSetLogCallbackNative, TPSetLogCallbackDart>(
                'tp_set_log_callback'));

    TPSetInstructionBudgetDart setBudget() => _lookup(
        library,
        'tp_engine_set_instruction_budget',
        () => library.lookupFunction<TPSetInstructionBudgetNative,
            TPSetInstructionBudgetDart>('tp_engine_set_instruction_budget'));

    TPExecuteFileDart execFile() => _lookup(
        library,
        'tp_execute_file',
        () => library.lookupFunction<TPExecuteFileNative, TPExecuteFileDart>(
            'tp_execute_file'));

    TPExecuteTemplateDart execTemplate() => _lookup(
        library,
        'tp_execute_template',
        () => library
            .lookupFunction<TPExecuteTemplateNative, TPExecuteTemplateDart>(
                'tp_execute_template'));

    TPParseParamsDart parseParams() => _lookup(
        library,
        'tp_parse_params',
        () => library.lookupFunction<TPParseParamsNative, TPParseParamsDart>(
            'tp_parse_params'));

    TPParseRefreshDart parseRefresh() => _lookup(
        library,
        'tp_parse_refresh',
        () => library.lookupFunction<TPParseRefreshNative, TPParseRefreshDart>(
            'tp_parse_refresh'));

    return TPEngineLibrary._(
      library: library,
      engineCreate: create(),
      engineDestroy: destroy(),
      setLogCallback: setLog(),
      setInstructionBudget: setBudget(),
      executeFile: execFile(),
      executeTemplate: execTemplate(),
      parseParams: parseParams(),
      parseRefresh: parseRefresh(),
    );
  }

  /// Run a lookup, translating "symbol not found" into a message that names the
  /// symbol and the fix. Any other `ArgumentError` propagates unchanged.
  static T _lookup<T>(DynamicLibrary library, String symbol, T Function() body) {
    try {
      return body();
    } on ArgumentError catch (e) {
      if (!e.toString().contains('Failed to lookup symbol')) rethrow;
      throw ArgumentError(
        'The library "${library.toString()}" does not export "$symbol". '
        'It is not the TaskPin engine, or it is a stale build. Rebuild it with '
        'packages/taskpin_engine/tool/build_dll.sh.',
      );
    }
  }
}
