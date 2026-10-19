// The single-instance guard.
//
// Ports `src/main.c:16-22`:
//
//     HANDLE hMutex = CreateMutexW(NULL, TRUE, L"Global\\TaskPin_SingleInstance");
//     if (GetLastError() == ERROR_ALREADY_EXISTS) { CloseHandle(hMutex); return 0; }
//
// The manager window is a singleton: a second launch must not create a second
// set of taskbar bars. A named kernel mutex is the same mechanism the C build
// used and needs no extra native artifact — `dart:ffi` reaches `kernel32.dll`
// directly.
//
// ─────────────────────────────────────────────────────────────────────────────
// Why the name is a constant, and why it is NOT the C one verbatim
// ─────────────────────────────────────────────────────────────────────────────
// The C source currently holds a TEMPORARY name with a `_UITest` suffix so a new
// build could be launched beside an elevated old one during testing. The
// production name it stands in for is `Global\TaskPin_SingleInstance`; that is
// what this uses. `Global\` puts the object in the machine-wide namespace, so
// two users on the same machine (or an elevated and a non-elevated launch by the
// same user) still collide — which is the intent.
//
// On any non-Windows platform [acquire] is a no-op that reports success, so a
// Linux/macOS build is not a crash. macOS single-instance is the app bundle's
// business, not this guard's.
//
// Pure Dart (`dart:ffi` + `dart:io`). No Flutter.

import 'dart:ffi';
import 'dart:io';

/// `ERROR_ALREADY_EXISTS`: `CreateMutexW` sets this when the named object
/// already existed.
const int kErrorAlreadyExists = 183;

/// The mutex name. `Global\` = machine-wide namespace.
const String kSingleInstanceMutexName = r'Global\TaskPin_SingleInstance';

/// A held single-instance mutex.
///
/// Acquire once at startup and keep the instance alive for the process lifetime;
/// the mutex is released when the handle is closed or the process exits.
class SingleInstanceGuard {
  SingleInstanceGuard._(this._handle);

  /// The raw `HANDLE` (0 on non-Windows / when not acquired).
  final int _handle;

  /// Whether this process owns the mutex (i.e. it is the first instance).
  bool get acquired => _handle != 0 || !Platform.isWindows;

  /// The handle, for tests and diagnostics.
  int get handle => _handle;

  /// Tries to become the single instance.
  ///
  /// Returns an [SingleInstanceGuard] whose [acquired] is false when another
  /// instance already holds the mutex. Never throws: a platform/FFI failure is
  /// treated as "could not determine", and the app is allowed to run (failing
  /// open is the safe direction — refusing to start is worse than two windows).
  static SingleInstanceGuard acquire({String name = kSingleInstanceMutexName}) {
    if (!Platform.isWindows) {
      return SingleInstanceGuard._(0);
    }
    try {
      final DynamicLibrary kernel32 = DynamicLibrary.open('kernel32.dll');
      final int Function(Pointer<Void>, int, Pointer<Uint16>) createMutex =
          kernel32.lookupFunction<
              IntPtr Function(Pointer<Void>, Int32, Pointer<Uint16>),
              int Function(Pointer<Void>, int, Pointer<Uint16>)>('CreateMutexW');
      final int Function() getLastError =
          kernel32.lookupFunction<Uint32 Function(), int Function()>('GetLastError');

      final Pointer<Uint16> namePtr = _toNativeUtf16(name);
      try {
        final int handle = createMutex(nullptr, 1, namePtr);
        final int err = getLastError();
        if (handle == 0) {
          // Could not create the object at all; fail open.
          return SingleInstanceGuard._(0);
        }
        if (err == kErrorAlreadyExists) {
          // Another instance owns it. Drop our handle and report the loss.
          _closeHandle(handle);
          return SingleInstanceGuard._(0);
        }
        return SingleInstanceGuard._(handle);
      } finally {
        _free(namePtr.cast<Void>());
      }
    } catch (_) {
      // FFI unavailable (unexpected on Windows): fail open rather than refuse.
      return SingleInstanceGuard._(0);
    }
  }
}

// ─── minimal CRT helpers (package:ffi is not a direct dependency here) ───

final DynamicLibrary _crt = _openCrt();

DynamicLibrary _openCrt() {
  if (Platform.isWindows) {
    for (final String name in <String>['ucrtbase.dll', 'msvcrt.dll']) {
      try {
        return DynamicLibrary.open(name);
      } catch (_) {
        continue;
      }
    }
  }
  return DynamicLibrary.process();
}

Pointer<Void> _malloc(int bytes) {
  final Pointer<Void> Function(int) malloc = _crt
      .lookupFunction<Pointer<Void> Function(IntPtr), Pointer<Void> Function(int)>('malloc');
  return malloc(bytes);
}

void _free(Pointer<Void> ptr) {
  if (ptr == nullptr) return;
  try {
    final void Function(Pointer<Void>) free = _crt
        .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('free');
    free(ptr);
  } catch (_) {}
}

void _closeHandle(int handle) {
  try {
    final DynamicLibrary kernel32 = DynamicLibrary.open('kernel32.dll');
    final int Function(int) closeHandle =
        kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
    closeHandle(handle);
  } catch (_) {}
}

/// NUL-terminated UTF-16, inlined so this file needs no `package:ffi`.
Pointer<Uint16> _toNativeUtf16(String s) {
  final List<int> units = <int>[];
  for (final int rune in s.runes) {
    if (rune <= 0xFFFF) {
      units.add(rune);
    } else {
      final int v = rune - 0x10000;
      units.add(0xD800 + (v >> 10));
      units.add(0xDC00 + (v & 0x3FF));
    }
  }
  units.add(0); // NUL terminator

  final Pointer<Uint16> ptr = _malloc(units.length * sizeOf<Uint16>()).cast<Uint16>();
  for (int i = 0; i < units.length; i++) {
    ptr[i] = units[i];
  }
  return ptr;
}
