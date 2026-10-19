// The Lua engine, as a Riverpod provider.
//
// `EngineApi.start()` spins up a dedicated Dart isolate that owns the single
// C `TPEngine*`. That isolates a real constraint: Lua is single-threaded and
// stateful, so a second isolate touching the same engine would corrupt it. The
// UI isolate never calls FFI — it only sends messages, which is why every
// method on `EngineApi` is async.
//
// Why the app can use the same code the tests use: `packages/taskpin_engine`
// loads the engine from a DLL. The SHIPPED app links the identical sources
// STATICALLY into the Windows runner (`windows/CMakeLists.txt`), so there is no
// runtime DLL to carry — the dynamic load exists only because `dart test` has
// no runner to link against. `library_loader.dart` handles both, preferring the
// directory of the running executable.
//
// Lifecycle: this is deliberately NOT `autoDispose`. Those tear down the moment
// the last listener goes away — which happens whenever the editor closes while
// the Symbols list is still refreshing — and each rebuild pays a cold engine
// restart. Keeping it alive for the process costs one isolate and a few hundred
// KB.
//
// Hand-written rather than generated: `riverpod_generator` is not a dependency
// of this project (it pins `analyzer` ^6/^7, which conflicts with `test` via
// `flutter_test`'s `matcher` pin — see the note in pubspec.yaml).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskpin_engine/taskpin_engine.dart';

/// The live engine.
///
/// Read with `ref.watch(engineProvider)` and handle the `AsyncValue` states:
/// `loading` while the Lua state comes up, `error` if the C library could not
/// be loaded (see `EngineLibraryNotFoundException`, whose message lists every
/// path that was tried). Hold the value with `.valueOrNull` once you have
/// rendered an error path of your own.
final FutureProvider<EngineApi> engineProvider =
    FutureProvider<EngineApi>((FutureProviderRef<EngineApi> ref) async {
  final EngineApi engine = await EngineApi.start();
  ref.onDispose(engine.dispose);
  return engine;
});
