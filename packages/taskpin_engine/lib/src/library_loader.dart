/// Locating and loading the engine's shared library.
///
/// **The shipped app does not use this file.** Per `docs/FLUTTER_REWRITE_PLAN.md`
/// ("C 库的构建方式") the engine is compiled as a STATIC library and linked into
/// the Flutter runner, so the product stays a single artifact with no runtime
/// dependency and `tp_*` symbols resolve through [DynamicLibrary.process]. This
/// loader exists for the one case that cannot work that way: **the tests**, which
/// run under plain `dart test` with no Flutter runner to link against, and
/// therefore need `taskpin_engine.dll` on disk.
///
/// See `tool/build_dll.sh` to produce it.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Thrown when the engine library cannot be found or opened.
///
/// The message deliberately lists **every path that was tried**, because the
/// overwhelmingly common cause is "you did not run `tool/build_dll.sh` yet" and
/// a bare "cannot open library" wastes a debugging session.
final class EngineLibraryNotFoundException implements Exception {
  EngineLibraryNotFoundException(this.searched, {this.cause});

  /// Every candidate path that was tested, in order, with a marker on the ones
  /// that existed but failed to load.
  final List<String> searched;

  /// The underlying `dlopen`/`LoadLibrary` failure, when one occurred.
  final Object? cause;

  /// The path the loader most expects to find the library at.
  String get expectedPath => searched.isEmpty ? '<none>' : searched.first;

  @override
  String toString() {
    final buffer = StringBuffer()
      ..writeln('taskpin_engine: could not load the engine shared library.')
      ..writeln()
      ..writeln('Expected it at:')
      ..writeln('  $expectedPath')
      ..writeln()
      ..writeln('Paths tried, in order:');
    for (final path in searched) {
      buffer.writeln('  $path');
    }
    buffer
      ..writeln()
      ..writeln('Build it with:')
      ..writeln('  bash packages/taskpin_engine/tool/build_dll.sh')
      ..writeln()
      ..writeln('(The SHIPPED app links this engine statically and does not use '
          'this loader at all; it is only for `dart test`.)');
    if (cause != null) {
      buffer
        ..writeln()
        ..writeln('Last load error: $cause');
    }
    return buffer.toString();
  }
}

/// The file name of the engine library on this platform.
String get engineLibraryFileName {
  if (Platform.isWindows) return 'taskpin_engine.dll';
  if (Platform.isMacOS) return 'libtaskpin_engine.dylib';
  return 'libtaskpin_engine.so';
}

/// Load the engine library.
///
/// [explicitPath] wins if given. Otherwise `TP_ENGINE_LIB`, then a list of
/// conventional build-output locations. The first path that opens wins; a path
/// that exists but fails to load does not stop the search, so a broken
/// build-dll output cannot shadow a good one.
///
/// Throws [EngineLibraryNotFoundException] listing everything tried.
DynamicLibrary loadEngineLibrary({String? explicitPath}) {
  final candidates = <String>[
    if (explicitPath != null) p.absolute(explicitPath),
    if (Platform.environment['TP_ENGINE_LIB'] case final fromEnv?
        when fromEnv.isNotEmpty)
      p.absolute(fromEnv),
    ..._defaultSearchPaths(),
  ];

  // De-duplicate while preserving order: the same directory reached by two
  // different walks should not be reported twice.
  final seen = <String>{};
  final searched = <String>[];
  Object? lastError;

  for (final candidate in candidates) {
    final normalized = p.normalize(candidate);
    if (!seen.add(normalized)) continue;
    searched.add(normalized);

    if (!File(normalized).existsSync()) continue;

    try {
      return DynamicLibrary.open(normalized);
    } on ArgumentError catch (e) {
      // Exists but will not load (wrong arch, missing dependency, corrupt).
      // Remember why, and keep looking.
      lastError = e;
    }
  }

  throw EngineLibraryNotFoundException(searched, cause: lastError);
}

/// Conventional locations, most-specific first.
List<String> _defaultSearchPaths() {
  final name = engineLibraryFileName;
  final paths = <String>[];

  final root = findRepoRoot();
  if (root != null) {
    // 1. Vendored next to the package by tool/build_dll.sh — the documented,
    //    deterministic place, and therefore the one the error message names.
    paths.add(p.join(root, 'packages', 'taskpin_engine', 'native', name));
    // 2. Raw CMake output, so a manual build works without the copy step.
    paths.add(p.join(root, 'native', 'engine', 'build-dll', name));
    // 3. The MinGW build tree, for cross-checking.
    paths.add(p.join(root, 'native', 'engine', 'build', name));
  }

  // 4. Wherever the running process lives, and the CWD — covers a test runner
  //    invoked from an unusual directory.
  paths.add(p.join(p.dirname(Platform.resolvedExecutable), name));
  paths.add(p.join(Directory.current.path, name));

  return paths;
}

/// Walk up from the current directory looking for the repository root.
///
/// Identified by `version.txt` **and** `native/engine/taskpin_engine.h`, so that
/// a directory which merely happens to be named like the repo cannot match.
/// Returns null when the tests are run from outside a checkout, in which case
/// [loadEngineLibrary] falls back to CWD/executable-relative paths.
String? findRepoRoot({String? from}) {
  var dir = p.absolute(from ?? Directory.current.path);
  for (var i = 0; i < 40; i++) {
    if (File(p.join(dir, 'version.txt')).existsSync() &&
        File(p.join(dir, 'native', 'engine', 'taskpin_engine.h')).existsSync()) {
      return dir;
    }
    final parent = p.dirname(dir);
    if (parent == dir) return null; // filesystem root
    dir = parent;
  }
  return null;
}
