/// The wire format between the UI isolate and the engine-owning isolate.
///
/// Deliberately plain: every message is a `List<Object?>` of primitives, `SendPort`s
/// and `Map<String, Object?>`s. That keeps it sendable under any isolate policy,
/// keeps it debuggable, and means the protocol has no dependency on the Dart
/// model classes — which is what lets the models live on either side.
///
/// Two shapes travel from the engine isolate back to the UI isolate:
///
///   * a **response**, one per request, matched by request id; and
///   * a **log event**, pushed whenever a script calls `log()`, with no
///     request to match it to. Logs are a stream, not a reply.
library;

/// Protocol version. Bumped when a message shape changes incompatibly; the
/// engine isolate and the facade are compiled together, so this exists only to
/// make a mismatched pair fail fast rather than mis-parse.
const int protocolVersion = 1;

/// Operations the engine isolate understands.
abstract final class Op {
  /// `tp_engine_create` -> handle.
  static const String createEngine = 'createEngine';

  /// `tp_engine_destroy`.
  static const String destroyEngine = 'destroyEngine';

  /// `tp_execute_file`.
  static const String executeFile = 'executeFile';

  /// `tp_execute_template`.
  static const String executeTemplate = 'executeTemplate';

  /// `tp_parse_params`.
  static const String parseParams = 'parseParams';

  /// `tp_parse_refresh`.
  static const String parseRefresh = 'parseRefresh';

  /// `tp_engine_set_instruction_budget`.
  static const String setInstructionBudget = 'setInstructionBudget';

  /// Shut the isolate down cleanly: destroy every engine, close the
  /// `NativeCallable`, close the receive port.
  static const String shutdown = 'shutdown';

  /// Answer "which isolate are you?" — the basis of the no-FFI-on-the-main-
  /// isolate test.
  static const String identify = 'identify';
}

/// A request from the UI isolate to the engine isolate.
final class EngineRequest {
  const EngineRequest(this.id, this.op, {this.handle, this.args = const {}});

  /// Correlates the response. Unique per `EngineIsolate` instance.
  final int id;

  /// One of [Op].
  final String op;

  /// The engine this applies to; null for isolate-level operations
  /// ([Op.createEngine], [Op.shutdown], [Op.identify]).
  final int? handle;

  /// Operation-specific arguments, always primitives.
  final Map<String, Object?> args;

  /// `[version, 'request', id, op, handle, args]`.
  List<Object?> toWire() => [protocolVersion, 'request', id, op, handle, args];
}

/// A reply from the engine isolate.
final class EngineResponse {
  const EngineResponse(this.id, {this.value, this.error});

  final int id;

  /// Operation-specific payload, already a plain Dart value.
  final Object? value;

  /// Human-readable failure, or null on success.
  final String? error;

  bool get ok => error == null;

  static EngineResponse fromWire(List<Object?> wire) {
    // [version, 'response', id, value, error]
    return EngineResponse(
      wire[2] as int,
      value: wire[3],
      error: wire[4] as String?,
    );
  }

  List<Object?> toWire() => [protocolVersion, 'response', id, value, error];
}

/// One `log()` call made by a script.
///
/// The C side hands these to `tp_set_log_callback`; the isolate forwards them
/// verbatim. [level] is reserved by the ABI (always 0 today).
final class EngineLog {
  const EngineLog(this.level, this.message, {this.handle});

  final int level;
  final String message;

  /// The engine that logged, when known.
  final int? handle;

  static EngineLog fromWire(List<Object?> wire) {
    // [version, 'log', handle, level, message]
    return EngineLog(wire[3] as int, wire[4] as String, handle: wire[2] as int?);
  }

  @override
  String toString() => 'EngineLog(level: $level, ${message.trim()})';
}

/// Thrown by the facade when the engine isolate reports a failure.
///
/// Note that a **Lua** failure is *not* an exception: `tp_execute_*` returns 0
/// with `TPScriptResult.error` filled and `ok == 0`, and the facade returns that
/// `ScriptResult` unchanged so callers can render the item's error state. This
/// exception is for the other case — the engine could not be reached or driven
/// at all (isolate died, engine handle invalid, library missing).
final class EngineException implements Exception {
  EngineException(this.message, {this.operation, this.luaError});

  final String message;

  /// The [Op] that failed, when known.
  final String? operation;

  /// Lua error text, when the failure came from a script rather than the
  /// transport. Usually null: Lua errors arrive inside a `ScriptResult`.
  final String? luaError;

  @override
  String toString() {
    final where = operation == null ? '' : ' [$operation]';
    final lua = luaError == null ? '' : ' (lua: $luaError)';
    return 'EngineException$where: $message$lua';
  }
}
