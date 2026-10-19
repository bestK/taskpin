/// The isolate that owns the Lua state.
///
/// **Why an isolate at all.** Lua is single-threaded and stateful: one
/// `TPEngine` is one `lua_State`, and the engine's C side assumes it is driven
/// from one thread at a time (it dropped `lib/scripting.c`'s `CRITICAL_SECTION`
/// for exactly that reason). So the engine gets a dedicated isolate, the UI
/// isolate talks to it only through `SendPort`s, and `dart:ffi` is never called
/// from the UI isolate. `test/isolate_test.dart` asserts that.
///
/// **Handles, not a singleton.** The public methods take an `int handle`, not a
/// bare `void`, even though v1 creates exactly one engine. The C ABI was
/// designed handle-based so a later build can run N engines (e.g. one for slow
/// HTTP items so one hanging request cannot stall everything) without an ABI
/// change; this class keeps that door open by never hard-coding "the" engine.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'bindings.dart';
import 'library_loader.dart';
import 'models.dart';
import 'protocol.dart';

/// A spawned engine isolate, seen from the UI isolate.
///
/// Obtained from [spawn]. Every method is asynchronous and returns a `Future`;
/// there is deliberately no synchronous accessor, which is what makes it
/// impossible for a caller to reach the FFI from the UI isolate by accident.
final class EngineIsolate {
  EngineIsolate._(this._toEngine, this._fromEngine, this._isolate);

  final SendPort _toEngine;
  final ReceivePort _fromEngine;
  final Isolate _isolate;

  final Map<int, Completer<EngineResponse>> _pending = {};
  final StreamController<EngineLog> _logs = StreamController<EngineLog>.broadcast();

  int _nextRequestId = 1;
  bool _disposed = false;

  /// The isolate's own debug name, useful in stack traces and tests.
  String? get debugName => _isolate.debugName;

  /// The control port of the engine isolate.
  ///
  /// Comparing this against `Isolate.current.controlPort` is how a test proves
  /// the FFI calls happen somewhere else. It is `SendPort` equality, which Dart
  /// defines as "points to the same `ReceivePort`".
  SendPort get controlPort => _isolate.controlPort;

  /// `log()` output from scripts, in arrival order.
  Stream<EngineLog> get logs => _logs.stream;

  /// Spawn an engine isolate and complete once it is ready to serve.
  ///
  /// [libraryPath] overrides the library search (see [loadEngineLibrary]);
  /// tests use it to point at a specific build. [debugName] shows up in
  /// profiler/`Isolate` listings.
  static Future<EngineIsolate> spawn({
    String? libraryPath,
    String debugName = 'taskpin-engine',
  }) async {
    final fromEngine = ReceivePort();
    final ready = Completer<SendPort>();

    final isolate = await Isolate.spawn<Object?>(
      _engineIsolateEntry,
      <Object?>[fromEngine.sendPort, libraryPath],
      debugName: debugName,
      onError: fromEngine.sendPort, // surfaces spawn-time errors to the parent
      onExit: fromEngine.sendPort,
    );

    late final EngineIsolate self;
    late final StreamSubscription<Object?> sub;

    void handle(Object? message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      if (message is List) {
        final kind = message[1];
        if (kind == 'response') {
          final response = EngineResponse.fromWire(message.cast<Object?>());
          self._pending.remove(response.id)?.complete(response);
        } else if (kind == 'log') {
          self._logs.add(EngineLog.fromWire(message.cast<Object?>()));
        }
        return;
      }
      if (message is List<Object?> && message.length >= 2) {
        // Isolate.spawn error payloads arrive as a 2-element list.
        final error = message[0];
        if (!ready.isCompleted) {
          ready.completeError(
              EngineException('engine isolate failed to start: $error'));
        }
        self._failAll(EngineException('engine isolate error: $error'));
      }
    }

    sub = fromEngine.listen(handle);

    self = EngineIsolate._(await ready.future, fromEngine, isolate);
    self._subscription = sub;
    return self;
  }

  late final StreamSubscription<Object?> _subscription;

  /// Create an engine and return its handle.
  Future<int> createEngine() async {
    final value = await _request(Op.createEngine);
    return value! as int;
  }

  /// Destroy an engine. Further calls with the same handle fail.
  Future<void> destroyEngine(int handle) async {
    await _request(Op.destroyEngine, handle: handle);
  }

  /// Run a `.lua` file.
  ///
  /// [argsJson] is an optional JSON object that becomes the global `args`
  /// table; null or empty means an empty table.
  ///
  /// Never throws for a Lua error: the returned [ScriptResult] carries
  /// `ok == false` and `error`. Only transport failures throw.
  Future<ScriptResult> executeFile(int handle, String path, {String? argsJson}) async {
    final value = await _request(Op.executeFile, handle: handle, args: {
      'path': path,
      'argsJson': argsJson,
    });
    return _decodeScriptResult(value);
  }

  /// Run Lua source with the global `response` set to [responseRaw].
  ///
  /// This is the expression-template mode: the code is wrapped in
  /// `return (function() ... end)()` by the engine, so it can use `return` and
  /// refer to `response`.
  Future<ScriptResult> executeTemplate(int handle, String luaCode,
      {String? responseRaw}) async {
    final value = await _request(Op.executeTemplate, handle: handle, args: {
      'code': luaCode,
      'responseRaw': responseRaw,
    });
    return _decodeScriptResult(value);
  }

  /// Parse `-- @param` declarations out of a script header.
  Future<List<ParamDecl>> parseParams(int handle, String path) async {
    final value = await _request(Op.parseParams, handle: handle, args: {'path': path});
    return (value! as List).cast<ParamDecl>();
  }

  /// Parse `-- @refresh <ms>`; 0 when not declared.
  Future<int> parseRefresh(int handle, String path) async {
    final value = await _request(Op.parseRefresh, handle: handle, args: {'path': path});
    return value! as int;
  }

  /// Set the per-execution Lua instruction budget.
  ///
  /// Exceeding it raises a Lua error instead of hanging, which is how
  /// `while true do end` is contained. Pass <= 0 to disable the watchdog.
  /// The C default is 50,000,000 instructions.
  Future<void> setInstructionBudget(int handle, int instructions) async {
    await _request(Op.setInstructionBudget,
        handle: handle, args: {'instructions': instructions});
  }

  /// Ask the isolate to report its own identity.
  ///
  /// Returns the control port of whoever answered, i.e. the isolate that would
  /// perform FFI calls. Used by `test/isolate_test.dart`.
  Future<SendPort> identify(int handle) async {
    final value = await _request(Op.identify, handle: handle);
    return value! as SendPort;
  }

  /// Shut the isolate down: destroy every engine, close the log callback, kill
  /// the isolate. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    try {
      await _request(Op.shutdown).timeout(const Duration(seconds: 5));
    } on Object {
      // Best effort: the isolate may already be gone, or wedged in a native
      // call. Falling through to kill() below is the correct recovery either
      // way — never let dispose() hang the app.
    }

    _isolate.kill(priority: Isolate.beforeNextEvent);
    _failAll(EngineException('engine isolate disposed'));
    await _subscription.cancel();
    _fromEngine.close();
    await _logs.close();
  }

  Future<Object?> _request(String op, {int? handle, Map<String, Object?>? args}) {
    if (_disposed) {
      return Future.error(
          EngineException('engine isolate has been disposed', operation: op));
    }

    final id = _nextRequestId++;
    final completer = Completer<EngineResponse>();
    _pending[id] = completer;

    _toEngine.send(EngineRequest(id, op, handle: handle, args: args ?? const {}).toWire());

    return completer.future.then<Object?>((response) {
      if (!response.ok) {
        throw EngineException(response.error!, operation: op);
      }
      return response.value;
    });
  }

  void _failAll(Object error) {
    final pending = _pending.values.toList();
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.completeError(error);
    }
  }

  /// Responses carry `ScriptResult`s as maps of primitives (never as Dart
  /// objects), so nothing that holds a `Pointer` can cross the boundary.
  static ScriptResult _decodeScriptResult(Object? value) =>
      ScriptResultCodec.decode(value! as Map<String, Object?>);
}

// ─────────────────────────────────────────────────────────────────────────────
// Engine-isolate side
// ─────────────────────────────────────────────────────────────────────────────

/// Entry point. Runs on the engine isolate; never returns until shutdown.
///
/// Typed as `void Function(Object?)` rather than `Future<void>` because
/// `Isolate.spawn` discards the returned future and only accepts a synchronous
/// entry point. The `async` work is kicked off and deliberately not awaited
/// here; `_engineIsolateMain` owns its own lifecycle and keeps the isolate alive
/// through the `ReceivePort`.
void _engineIsolateEntry(Object? message) {
  unawaited(_engineIsolateMain((message! as List).cast<Object?>()));
}

Future<void> _engineIsolateMain(List<Object?> args) async {
  final toUi = args[0] as SendPort;
  final libraryPath = args[1] as String?;

  final engine = _EngineHost(toUi, libraryPath);
  try {
    engine.start();
  } on Object catch (error, stack) {
    // Hand the failure back instead of dying silently: the facade is waiting on
    // a ready handshake and must not hang forever.
    toUi.send(<Object?>[error.toString(), stack.toString()]);
    return;
  }

  // The ready handshake. Sent after the library is loaded and the log callback
  // is wired, so "spawned" means "usable".
  toUi.send(engine.fromUi.sendPort);

  await for (final message in engine.fromUi) {
    if (message is! List) continue;
    final wire = message.cast<Object?>();
    final request = EngineRequest(wire[2] as int, wire[3] as String,
        handle: wire[4] as int?, args: (wire[5] as Map).cast<String, Object?>());

    if (request.op == Op.shutdown) {
      engine.shutdown();
      break;
    }

    try {
      final value = engine.dispatch(request);
      toUi.send(EngineResponse(request.id, value: value).toWire());
    } on Object catch (error) {
      toUi.send(EngineResponse(request.id, error: error.toString()).toWire());
    }
  }

  engine.shutdown();
}

/// Owns the loaded library, the handle table and the scratch buffers.
///
/// This type only ever exists on the engine isolate. It is the only place in
/// the package that calls into C.
final class _EngineHost {
  _EngineHost(this.toUi, this.libraryPath);

  final SendPort toUi;
  final String? libraryPath;
  final ReceivePort fromUi = ReceivePort();

  late final TPEngineLibrary _lib;

  /// One `TPScriptResult` for the isolate's lifetime. `tp_execute_*` calls
  /// `result_init` (a `memset`) before filling it, so there is nothing to clear
  /// between runs. It is 212 KB on x64 (see `test/abi_layout_test.dart`), so
  /// allocating per call would churn that much on every refresh tick.
  late final Pointer<TPScriptResult> _resultBuffer;

  late final Pointer<Utf8> _emptyString;

  final Map<int, Pointer<Void>> _engines = {};
  int _nextHandle = 1;

  NativeCallable<TPLogFnNative>? _logCallable;

  void start() {
    _lib = TPEngineLibrary.from(loadEngineLibrary(explicitPath: libraryPath));
    _resultBuffer = calloc<TPScriptResult>();

    // tp_execute_file takes `const char *args_json` and treats NULL as "empty
    // table"; a shared empty string is cheaper than nulling a pointer per call.
    _emptyString = ''.toNativeUtf8();

    _logCallable = NativeCallable<TPLogFnNative>.isolateLocal(_onNativeLog);
  }

  void shutdown() {
    for (final handle in _engines.values) {
      _lib.engineDestroy(handle);
    }
    _engines.clear();

    _logCallable?.close();
    _logCallable = null;

    calloc.free(_emptyString);
    calloc.free(_resultBuffer);

    fromUi.close();
  }

  Object? dispatch(EngineRequest request) {
    switch (request.op) {
      case Op.createEngine:
        final handle = _lib.engineCreate();
        if (handle == nullptr) {
          throw StateError('tp_engine_create() returned NULL');
        }
        final id = _nextHandle++;
        _engines[id] = handle;
        // Route log() into the stream rather than the default sink, which would
        // append to taskpin.log in the process CWD.
        _lib.setLogCallback(handle, _logCallable!.nativeFunction, nullptr);
        return id;

      case Op.destroyEngine:
        final engine = _require(request.handle);
        _lib.engineDestroy(engine);
        _engines.remove(request.handle);
        return null;

      case Op.executeFile:
        final engine = _require(request.handle);
        final path = (request.args['path']! as String).toNativeUtf8();
        final argsJson = (request.args['argsJson'] as String?)?.toNativeUtf8();
        try {
          _lib.executeFile(engine, path, argsJson ?? _emptyString, _resultBuffer);
          return ScriptResultCodec.encode(ScriptResult.fromNative(_resultBuffer.ref));
        } finally {
          calloc.free(path);
          if (argsJson != null) calloc.free(argsJson);
        }

      case Op.executeTemplate:
        final engine = _require(request.handle);
        final code = (request.args['code']! as String).toNativeUtf8();
        final responseRaw = (request.args['responseRaw'] as String?)?.toNativeUtf8();
        try {
          _lib.executeTemplate(engine, code, responseRaw ?? _emptyString, _resultBuffer);
          return ScriptResultCodec.encode(ScriptResult.fromNative(_resultBuffer.ref));
        } finally {
          calloc.free(code);
          if (responseRaw != null) calloc.free(responseRaw);
        }

      case Op.parseParams:
        final path = (request.args['path']! as String).toNativeUtf8();
        // TPParamDecl is 208 bytes; 32 slots is what tool/engine_cli.c uses.
        const maxDecls = 32;
        final buffer = calloc<TPParamDecl>(maxDecls);
        try {
          final count = _lib.parseParams(path, buffer, maxDecls).clamp(0, maxDecls);
          return [
            for (var i = 0; i < count; i++) ParamDecl.fromNative(buffer[i]),
          ];
        } finally {
          calloc.free(buffer);
          calloc.free(path);
        }

      case Op.parseRefresh:
        final path = (request.args['path']! as String).toNativeUtf8();
        try {
          return _lib.parseRefresh(path);
        } finally {
          calloc.free(path);
        }

      case Op.setInstructionBudget:
        final engine = _require(request.handle);
        _lib.setInstructionBudget(engine, request.args['instructions']! as int);
        return null;

      case Op.identify:
        // Answer with our own control port. The facade compares it against the
        // caller's to prove where the FFI runs.
        return fromUi.sendPort;

      default:
        throw StateError('unknown engine operation: ${request.op}');
    }
  }

  Pointer<Void> _require(int? handle) {
    if (handle == null) {
      throw StateError('this operation requires an engine handle');
    }
    final engine = _engines[handle];
    if (engine == null) {
      throw StateError('no such engine handle: $handle '
          '(known: ${_engines.keys.toList()..sort()})');
    }
    return engine;
  }

  /// `tp_set_log_callback` sink. Called from the same thread that runs the
  /// script, i.e. this isolate, so it may use the isolate's Dart state freely.
  void _onNativeLog(int level, Pointer<Utf8> message, Pointer<Void> user) {
    final text = message == nullptr ? '' : message.toDartString();
    // Find which engine logged, so the UI can attribute it. Cheap: the table
    // holds one entry in v1.
    int? handle;
    for (final entry in _engines.entries) {
      if (entry.value == user) {
        handle = entry.key;
        break;
      }
    }
    toUi.send(<Object?>[protocolVersion, 'log', handle, level, text]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ScriptResult <-> primitive map
// ─────────────────────────────────────────────────────────────────────────────

/// Encodes a [ScriptResult] into `Map`/`List`/`String`/`int`/`bool` so it can
/// cross the isolate boundary, and back.
///
/// Hand-written rather than `dart:convert`-based because the models use enums
/// and are deliberately not `toJson`-shaped: the wire format is private to this
/// package and should not leak into the models' public API.
abstract final class ScriptResultCodec {
  static Map<String, Object?> encode(ScriptResult r) => {
        'ok': r.ok,
        'error': r.error,
        'display': r.display,
        'clickable': r.clickable,
        'clickAction': r.clickAction.wireValue,
        'clickUrl': r.clickUrl,
        'spans': [for (final s in r.spans) _encodeSpan(s)],
        'dialog': _encodeDialog(r.dialog),
      };

  static ScriptResult decode(Map<String, Object?> m) => ScriptResult(
        ok: m['ok']! as bool,
        error: m['error']! as String,
        display: m['display']! as String,
        clickable: m['clickable']! as bool,
        clickAction: ClickAction.fromWire(m['clickAction']! as int),
        clickUrl: m['clickUrl']! as String,
        spans: [
          for (final s in m['spans']! as List) _decodeSpan((s as Map).cast<String, Object?>()),
        ],
        dialog: _decodeDialog((m['dialog']! as Map).cast<String, Object?>()),
      );

  static Map<String, Object?> _encodeSpan(Span s) => {
        'text': s.text,
        'color': s.color,
        'fontSize': s.fontSize,
        'align': s.align.wireValue,
        'newline': s.newline,
        'isImage': s.isImage,
        'imageWidth': s.imageWidth,
        'imageHeight': s.imageHeight,
      };

  static Span _decodeSpan(Map<String, Object?> m) => Span(
        text: m['text']! as String,
        color: m['color']! as String,
        fontSize: m['fontSize']! as int,
        align: SpanAlign.fromWire(m['align']! as int),
        newline: m['newline']! as bool,
        isImage: m['isImage']! as bool,
        imageWidth: m['imageWidth']! as int,
        imageHeight: m['imageHeight']! as int,
      );

  static Map<String, Object?> _encodeDialog(DialogSpec d) => {
        'title': d.title,
        'width': d.width,
        'height': d.height,
        'refresh': d.refresh,
        'borderless': d.borderless,
        'clickthrough': d.clickthrough,
        'opacity': d.opacity,
        'backgroundColor': d.backgroundColor,
        'transparentBackground': d.transparentBackground,
        'items': [for (final i in d.items) _encodeItem(i)],
      };

  static DialogSpec _decodeDialog(Map<String, Object?> m) => DialogSpec(
        title: m['title']! as String,
        width: m['width']! as int,
        height: m['height']! as int,
        refresh: m['refresh']! as int,
        borderless: m['borderless']! as bool,
        clickthrough: m['clickthrough']! as bool,
        opacity: m['opacity']! as int,
        backgroundColor: m['backgroundColor']! as String,
        transparentBackground: m['transparentBackground']! as bool,
        items: [
          for (final i in m['items']! as List)
            _decodeItem((i as Map).cast<String, Object?>()),
        ],
      );

  static Map<String, Object?> _encodeItem(DialogItem i) => {
        'type': i.type.wireValue,
        'value': i.value,
        'color': i.color,
        'fontSize': i.fontSize,
        'bold': i.bold,
        'image': i.image,
        'imageWidth': i.imageWidth,
        'imageHeight': i.imageHeight,
        'url': i.url,
        'cmd': i.cmd,
        'bg': i.bg,
        'webWidth': i.webWidth,
        'webHeight': i.webHeight,
        'columns': i.columns,
        'rows': i.rows,
        'rowUrls': i.rowUrls,
        'rowCmds': i.rowCmds,
      };

  static DialogItem _decodeItem(Map<String, Object?> m) => DialogItem(
        type: DialogItemType.fromWire(m['type']! as String),
        value: m['value']! as String,
        color: m['color']! as String,
        fontSize: m['fontSize']! as int,
        bold: m['bold']! as bool,
        image: m['image']! as String,
        imageWidth: m['imageWidth']! as int,
        imageHeight: m['imageHeight']! as int,
        url: m['url']! as String,
        cmd: m['cmd']! as String,
        bg: m['bg']! as String,
        webWidth: m['webWidth']! as int,
        webHeight: m['webHeight']! as int,
        columns: (m['columns']! as List).cast<String>(),
        rows: [
          for (final row in m['rows']! as List) (row as List).cast<String>(),
        ],
        rowUrls: (m['rowUrls']! as List).cast<String>(),
        rowCmds: (m['rowCmds']! as List).cast<String>(),
      );
}
