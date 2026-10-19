// Elevation: detecting whether we are already elevated, and relaunching
// elevated.
//
// ─────────────────────────────────────────────────────────────────────────────
// The implementation this replaces is GONE
// ─────────────────────────────────────────────────────────────────────────────
// The four `elevate.*` i18n keys survived the July UI rewrite, but nothing in
// `src/` or `lib/*.c` references them. `grep -rni 'elevate|runas|IsUserAnAdmin'
// src/ lib/*.c` finds only unrelated `ShellExecuteW(NULL, L"open", ...)` calls.
// So this is a reimplementation from the key semantics, not a port.
//
// What the keys say the behaviour is:
//
//   elevate.blocked          '⚠️ 需要管理员权限' / '⚠️ Admin required'
//                            -> the bar shows this when a script needs admin
//   elevate.desc_default     '此脚本需要管理员权限'
//                            -> the supporting line
//   elevate.restart_confirm  '是否以管理员身份重启 TaskPin？'
//                            -> the confirm dialog's body
//   elevate.dialog_title     'TaskPin - 需要管理员权限'
//                            -> the confirm dialog's title
//
// Which is: the bar shows `blocked`; clicking it asks `restart_confirm`;
// confirming relaunches the app elevated. That flow lives in
// `lib/features/elevate/elevate_flow.dart`.
//
// ─────────────────────────────────────────────────────────────────────────────
// FFI, not new native code
// ─────────────────────────────────────────────────────────────────────────────
// `native/` belongs to another phase (`native/win/relaunch_helper.cpp` is that
// phase's file), so nothing here adds a compiled artifact. Everything needed is
// already exported by system libraries and is reached through `dart:ffi`:
//
//   Windows  ShellExecuteW(shell32, "runas")            relaunch elevated
//            OpenProcessToken + GetTokenInformation      "am I elevated?"
//            IsUserAnAdmin(shell32)                      fallback for the same
//   macOS    geteuid() (libc)                            "am I root?"
//            osascript "with administrator privileges"   relaunch elevated
//
// On any other platform both operations report "unsupported" rather than
// throwing, so a Linux CI run is not a crash.
//
// ─────────────────────────────────────────────────────────────────────────────
// Why the allocator is hand-rolled
// ─────────────────────────────────────────────────────────────────────────────
// `dart:ffi` core exports no allocator; `calloc` and `toNativeUtf16` come from
// `package:ffi`. Adding that package means editing the shared `pubspec.yaml`,
// which other agents are working in, so the two functions actually needed
// (`malloc`/`free` and a UTF-16 encoder) are inlined below instead. They are
// ~40 lines and remove a cross-lane dependency.
//
// Pure Dart (`dart:ffi` + `dart:io`). No Flutter.

import 'dart:ffi';
import 'dart:io';

/// The outcome of a relaunch-elevated attempt.
enum ElevateResult {
  /// The elevated process was started; the caller should exit.
  started,

  /// The user dismissed the UAC prompt (Windows `ERROR_CANCELLED`, 1223) or
  /// cancelled the macOS authorization sheet. Not an error: say nothing.
  cancelled,

  /// We are already elevated. Relaunching would be a no-op.
  alreadyElevated,

  /// The attempt failed for another reason.
  failed,

  /// This platform has no elevation mechanism wired up.
  unsupported,
}

/// The Windows `ShellExecuteW` return value at or below which the call failed.
///
/// `ShellExecuteW` returns a fake `HINSTANCE`; anything <= 32 is an error code
/// (the `SE_ERR_*` family), which is the documented contract.
const int kShellExecuteErrorThreshold = 32;

/// `ERROR_CANCELLED`: what `ShellExecuteW("runas")` sets when the user declines
/// the UAC prompt.
const int kErrorCancelled = 1223;

/// `TOKEN_QUERY` — the access right `OpenProcessToken` needs.
const int _tokenQuery = 0x0008;

/// `TokenElevation` from `TOKEN_INFORMATION_CLASS`.
const int _tokenElevation = 20;

/// `ShellExecuteW`'s `SW_SHOWNORMAL`.
const int _swShowNormal = 1;

/// Elevation detection and relaunch.
///
/// Every platform call is behind an overridable hook so the whole thing is
/// testable on any OS, and so a Flutter layer can substitute a native
/// implementation later without touching the call sites.
class ElevateService {
  ElevateService({
    bool? isElevatedOverride,
    Future<ElevateResult> Function()? relaunchOverride,
    String? executablePath,
    String? arguments,
    String? platformOverride,
  })  : _isElevatedOverride = isElevatedOverride,
        _relaunchOverride = relaunchOverride,
        _exePath = executablePath,
        _arguments = arguments,
        _platform = platformOverride;

  final bool? _isElevatedOverride;
  final Future<ElevateResult> Function()? _relaunchOverride;
  final String? _exePath;
  final String? _arguments;
  final String? _platform;

  String get _platformName =>
      _platform ?? (Platform.isWindows ? 'windows' : Platform.isMacOS ? 'macos' : 'other');

  String get _executable => _exePath ?? Platform.resolvedExecutable;

  /// The arguments the elevated instance should be relaunched with.
  ///
  /// Empty by default: the app takes no command-line arguments and reads its
  /// state from the config file, so a plain relaunch is the correct semantics.
  String get _launchArguments => _arguments ?? '';

  /// Whether this process is already running elevated.
  ///
  /// Windows: queries the process token for `TokenElevation`, falling back to
  /// `IsUserAnAdmin` when the token query is unavailable. macOS: `geteuid() == 0`.
  bool isElevated() {
    final bool? override = _isElevatedOverride;
    if (override != null) return override;

    if (_platformName == 'windows') return _isElevatedWindows();
    if (_platformName == 'macos') return _geteuid() == 0;
    return false;
  }

  /// Relaunches this executable elevated.
  ///
  /// The caller exits once this returns [ElevateResult.started].
  Future<ElevateResult> relaunchElevated() async {
    final Future<ElevateResult> Function()? override = _relaunchOverride;
    if (override != null) return override();

    if (isElevated()) return ElevateResult.alreadyElevated;

    if (_platformName == 'windows') return _relaunchWindows();
    if (_platformName == 'macos') return _relaunchMacos();
    return ElevateResult.unsupported;
  }

  // ── Windows ───────────────────────────────────────────────────────────────

  bool _isElevatedWindows() {
    // Preferred: the process token's TokenElevation. Works regardless of the
    // `IsUserAnAdmin` deprecation.
    final int? viaToken = _tokenElevationQuery();
    if (viaToken != null) return viaToken != 0;

    // Fallback: shell32's IsUserAnAdmin. Deprecated (and dropped from newer SDK
    // headers) but still exported by every shipping shell32.dll, which is why it
    // is looked up dynamically rather than declared at compile time.
    try {
      final DynamicLibrary shell32 = DynamicLibrary.open('shell32.dll');
      final int Function() isUserAnAdmin =
          shell32.lookupFunction<Int32 Function(), int Function()>('IsUserAnAdmin');
      return isUserAnAdmin() != 0;
    } catch (_) {
      return false;
    }
  }

  /// Returns the `TokenElevation` DWORD, or null when it cannot be read.
  int? _tokenElevationQuery() {
    Pointer<IntPtr>? tokenPtr;
    Pointer<Uint32>? returnedPtr;
    Pointer<Uint8>? buffer;
    int token = 0;
    try {
      final DynamicLibrary kernel32 = DynamicLibrary.open('kernel32.dll');
      final DynamicLibrary advapi32 = DynamicLibrary.open('advapi32.dll');

      final int Function() getCurrentProcess =
          kernel32.lookupFunction<IntPtr Function(), int Function()>('GetCurrentProcess');
      final int Function(int, int, Pointer<IntPtr>) openProcessToken = advapi32.lookupFunction<
          Int32 Function(IntPtr, Uint32, Pointer<IntPtr>),
          int Function(int, int, Pointer<IntPtr>)>('OpenProcessToken');
      final int Function(int, int, Pointer<Uint8>, int, Pointer<Uint32>) getTokenInformation =
          advapi32.lookupFunction<
              Int32 Function(IntPtr, Int32, Pointer<Uint8>, Uint32, Pointer<Uint32>),
              int Function(int, int, Pointer<Uint8>, int,
                  Pointer<Uint32>)>('GetTokenInformation');

      tokenPtr = _allocIntPtr();
      returnedPtr = _allocUint32();
      // TokenElevation is a TOKEN_ELEVATION struct with a single DWORD member,
      // so a 4-byte buffer is exactly right.
      buffer = _allocUint8(4);

      if (openProcessToken(getCurrentProcess(), _tokenQuery, tokenPtr) == 0) {
        return null;
      }
      token = tokenPtr.value;
      if (getTokenInformation(token, _tokenElevation, buffer, 4, returnedPtr) == 0) {
        return null;
      }
      // Little-endian DWORD read.
      return buffer[0] | (buffer[1] << 8) | (buffer[2] << 16) | (buffer[3] << 24);
    } catch (_) {
      return null;
    } finally {
      if (token != 0) _closeHandleQuietly(token);
      if (tokenPtr != null) _free(tokenPtr.cast<Void>());
      if (returnedPtr != null) _free(returnedPtr.cast<Void>());
      if (buffer != null) _free(buffer.cast<Void>());
    }
  }

  void _closeHandleQuietly(int handle) {
    try {
      final DynamicLibrary kernel32 = DynamicLibrary.open('kernel32.dll');
      final int Function(int) closeHandle =
          kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
      closeHandle(handle);
    } catch (_) {
      // A leaked handle at process exit is not worth failing over.
    }
  }

  Future<ElevateResult> _relaunchWindows() async {
    Pointer<Uint16>? verb;
    Pointer<Uint16>? file;
    Pointer<Uint16>? params;
    try {
      final DynamicLibrary shell32 = DynamicLibrary.open('shell32.dll');
      final DynamicLibrary kernel32 = DynamicLibrary.open('kernel32.dll');

      final int Function(int, Pointer<Uint16>, Pointer<Uint16>, Pointer<Uint16>,
              Pointer<Uint16>, int) shellExecute =
          shell32.lookupFunction<
              IntPtr Function(IntPtr, Pointer<Uint16>, Pointer<Uint16>, Pointer<Uint16>,
                  Pointer<Uint16>, Int32),
              int Function(int, Pointer<Uint16>, Pointer<Uint16>, Pointer<Uint16>,
                  Pointer<Uint16>, int)>('ShellExecuteW');
      final int Function() getLastError =
          kernel32.lookupFunction<Uint32 Function(), int Function()>('GetLastError');

      verb = _toNativeUtf16('runas');
      file = _toNativeUtf16(_executable);
      params = _toNativeUtf16(_launchArguments);

      final int result = shellExecute(0, verb, file, params, nullptr, _swShowNormal);
      if (result > kShellExecuteErrorThreshold) return ElevateResult.started;

      // ShellExecuteW's return value says "failed"; GetLastError says why.
      final int error = getLastError();
      if (error == kErrorCancelled) return ElevateResult.cancelled;
      return ElevateResult.failed;
    } catch (_) {
      return ElevateResult.failed;
    } finally {
      if (verb != null) _free(verb.cast<Void>());
      if (file != null) _free(file.cast<Void>());
      if (params != null) _free(params.cast<Void>());
    }
  }

  // ── macOS ─────────────────────────────────────────────────────────────────

  int _geteuid() {
    try {
      final DynamicLibrary libc = DynamicLibrary.process();
      final int Function() geteuid =
          libc.lookupFunction<Uint32 Function(), int Function()>('geteuid');
      return geteuid();
    } catch (_) {
      return -1;
    }
  }

  Future<ElevateResult> _relaunchMacos() async {
    // `do shell script ... with administrator privileges` is the supported
    // non-deprecated path (AuthorizationExecuteWithPrivileges was removed). The
    // bundle is relaunched with `open -n` so the running instance's own binary
    // is not what gets elevated.
    final String bundle = bundlePathFor(_executable);
    final String script =
        'do shell script "open -n \\"$bundle\\"" with administrator privileges';
    try {
      final ProcessResult result =
          await Process.run('/usr/bin/osascript', <String>['-e', script]);
      if (result.exitCode == 0) return ElevateResult.started;
      // osascript reports a user cancel as -128 on stderr.
      final String err = '${result.stderr}';
      if (err.contains('-128') || err.contains('User canceled')) {
        return ElevateResult.cancelled;
      }
      return ElevateResult.failed;
    } catch (_) {
      return ElevateResult.failed;
    }
  }
}

/// `.../TaskPin.app/Contents/MacOS/TaskPin` -> `.../TaskPin.app`.
///
/// Exposed as a top-level function because `update_service.dart` needs the same
/// derivation and the two must not disagree.
String bundlePathFor(String executable) {
  final int idx = executable.indexOf('.app/Contents/MacOS/');
  if (idx < 0) return File(executable).parent.path;
  return executable.substring(0, idx + '.app'.length);
}

// ─────────────────────────────────────────────────────────────────────────────
// Minimal allocator + UTF-16 encoder
//
// `dart:ffi` core has neither. `package:ffi` has both, but adding it means
// editing the shared pubspec, so they are inlined here instead.
// ─────────────────────────────────────────────────────────────────────────────

/// The C runtime, used for `malloc`/`free`.
///
/// On Windows the CRT lives in `ucrtbase.dll` (Universal CRT, shipped with
/// Windows 10+) or `msvcrt.dll` on older builds. On macOS and Linux,
/// `DynamicLibrary.process()` resolves libc symbols.
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
  final Pointer<Void> Function(int) malloc =
      _crt.lookupFunction<Pointer<Void> Function(IntPtr), Pointer<Void> Function(int)>('malloc');
  return malloc(bytes);
}

void _free(Pointer<Void> ptr) {
  if (ptr == nullptr) return;
  try {
    final void Function(Pointer<Void>) free = _crt
        .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('free');
    free(ptr);
  } catch (_) {
    // Nothing useful to do; the process is exiting in the failure path anyway.
  }
}

/// Zero-initialised allocation of [byteCount] bytes, cast to [T].
Pointer<T> _alloc<T extends NativeType>(int byteCount) {
  final Pointer<Void> raw = _malloc(byteCount);
  if (raw == nullptr) {
    throw StateError('malloc($byteCount) returned null');
  }
  final Pointer<Uint8> bytes = raw.cast<Uint8>();
  for (int i = 0; i < byteCount; i++) {
    bytes[i] = 0;
  }
  return raw.cast<T>();
}

Pointer<IntPtr> _allocIntPtr() => _alloc<IntPtr>(sizeOf<IntPtr>());

Pointer<Uint32> _allocUint32() => _alloc<Uint32>(sizeOf<Uint32>());

Pointer<Uint8> _allocUint8(int count) => _alloc<Uint8>(count);

/// Encodes [s] as a NUL-terminated UTF-16 buffer.
///
/// This is `package:ffi`'s `toNativeUtf16`, inlined. Surrogate pairs are
/// emitted for anything above the BMP so that a non-ASCII path or argument
/// reaches the Win32 `W` API intact.
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

  final Pointer<Uint16> ptr = _alloc<Uint16>(units.length * sizeOf<Uint16>());
  for (int i = 0; i < units.length; i++) {
    ptr[i] = units[i];
  }
  return ptr;
}
