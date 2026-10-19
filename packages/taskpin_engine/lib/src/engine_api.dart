/// The async facade the UI uses.
///
/// `EngineApi` is the only thing application code should import. It owns exactly
/// one [EngineIsolate] (v1 runs a single engine, per the plan) and forwards to
/// it; every method returns a `Future` and there is no synchronous path to the
/// FFI at all.
///
/// Usage:
///
/// ```dart
/// final engine = await EngineApi.start();
/// final result = await engine.executeFile('/path/to/zeeho.lua',
///     argsJson: '{"VIN":"..."}');
/// if (!result.ok) {
///   // Render the item's error state. Do NOT put result.error on the bar:
///   // that is the behaviour this ABI was designed to stop.
/// } else {
///   for (final span in result.spans) { /* ... */ }
/// }
/// await engine.dispose();
/// ```
library;

import 'dart:async';

import 'engine_isolate.dart';
import 'models.dart';
import 'protocol.dart';

export 'protocol.dart' show EngineException, EngineLog;

/// A running engine. One per application, in v1.
final class EngineApi {
  EngineApi._(this._isolate, this._handle);

  final EngineIsolate _isolate;
  final int _handle;

  /// The underlying isolate, exposed for tests and for future multi-engine
  /// work. Application code should use the typed methods below.
  EngineIsolate get isolate => _isolate;

  /// The engine handle this facade drives.
  int get handle => _handle;

  /// Spawn the engine isolate and create one engine.
  ///
  /// [libraryPath] overrides the shared-library search; leave it null in
  /// production, where the loader's conventional paths apply.
  ///
  /// Throws `EngineLibraryNotFoundException` when the library is missing (with
  /// every path it tried) and `EngineException` when the isolate fails to start.
  static Future<EngineApi> start({
    String? libraryPath,
    String debugName = 'taskpin-engine',
  }) async {
    final isolate =
        await EngineIsolate.spawn(libraryPath: libraryPath, debugName: debugName);
    try {
      final handle = await isolate.createEngine();
      return EngineApi._(isolate, handle);
    } on Object {
      // Do not leak a live isolate if engine creation failed.
      await isolate.dispose();
      rethrow;
    }
  }

  /// `log()` output from scripts, in arrival order.
  Stream<EngineLog> get logs => _isolate.logs;

  /// Run a `.lua` file.
  ///
  /// [argsJson] is an optional JSON object that becomes the global `args`
  /// table. A Lua error does **not** throw: the returned [ScriptResult] has
  /// `ok == false` and [ScriptResult.error] set. Only transport failures throw
  /// [EngineException].
  Future<ScriptResult> executeFile(String path, {String? argsJson}) =>
      _isolate.executeFile(_handle, path, argsJson: argsJson);

  /// Run Lua source in template mode, with the global `response` set to
  /// [responseRaw]. Same result contract as [executeFile].
  Future<ScriptResult> executeTemplate(String luaCode, {String? responseRaw}) =>
      _isolate.executeTemplate(_handle, luaCode, responseRaw: responseRaw);

  /// Parse `-- @param` declarations out of a script header.
  Future<List<ParamDecl>> parseParams(String path) =>
      _isolate.parseParams(_handle, path);

  /// Parse `-- @refresh <ms>`; 0 when the script does not declare one.
  Future<int> parseRefresh(String path) => _isolate.parseRefresh(_handle, path);

  /// Set the per-execution Lua instruction budget.
  ///
  /// Exceeding it raises a Lua error rather than hanging, which is what stops
  /// `while true do end` from wedging the engine. Pass <= 0 to disable. The C
  /// default is 50,000,000 instructions.
  Future<void> setInstructionBudget(int instructions) =>
      _isolate.setInstructionBudget(_handle, instructions);

  /// Shut down the engine and its isolate. Idempotent.
  Future<void> dispose() => _isolate.dispose();
}
