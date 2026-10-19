/// The Dart face of the TaskPin C engine (`native/engine`).
///
/// Pure Dart, no Flutter: `dart:ffi` bindings over the whole
/// `taskpin_engine.h` ABI, immutable models for the result structs, and an
/// isolate that owns the single-threaded Lua state so the UI isolate never
/// calls FFI directly.
///
/// Start with `EngineApi`.
///
/// ```dart
/// import 'package:taskpin_engine/taskpin_engine.dart';
///
/// final engine = await EngineApi.start();
/// final result = await engine.executeFile('scripts/zeeho.lua');
/// print(result.spans.map((s) => s.text).join());
/// await engine.dispose();
/// ```
///
/// See `README.md` for the static-link-vs-DLL story and how to build the
/// library the tests load.
library;

export 'src/bindings.dart'
    show
        // structs (needed by the ABI layout test and by any future native glue)
        TPSpan,
        TPDisplayContent,
        TPDialogItem,
        TPDialogSpec,
        TPScriptResult,
        TPParamDecl,
        TPEngineLibrary,
        // capacities
        tpMaxSpans,
        tpSpanTextLen,
        tpColorLen,
        tpDisplayLen,
        tpUrlLen,
        tpErrorLen,
        tpDialogMaxItems,
        tpDialogMaxCols,
        tpDialogMaxRows,
        // constants
        tpSpanAlignLeft,
        tpSpanAlignRight,
        tpSpanAlignCenter,
        tpClickUrl,
        tpClickDialog,
        tpDialogTypeWebview;
export 'src/engine_api.dart' show EngineApi;
export 'src/engine_isolate.dart' show EngineIsolate;
export 'src/library_loader.dart'
    show
        EngineLibraryNotFoundException,
        engineLibraryFileName,
        findRepoRoot,
        loadEngineLibrary;
export 'src/models.dart'
    show
        ClickAction,
        DialogItem,
        DialogItemType,
        DialogSpec,
        ParamDecl,
        ScriptResult,
        Span,
        SpanAlign;
export 'src/protocol.dart' show EngineException, EngineLog;
