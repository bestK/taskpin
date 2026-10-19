// The Dart half of the `taskpin/window` MethodChannel.
//
// This is the only way a dialog window can get native window effects: Flutter
// has no API for "no title bar", "hide from Alt+Tab", "let clicks through" or
// "be 70% opaque". The native halves are
//   native/win/dialog_window_styles.cpp
//   native/mac/DialogWindowStyles.swift
// and they must stay argument-compatible with the method names below — that
// pairing is the contract, mirrored the same way `taskpin/bar` is.
//
// Behaviour parity is against the Win32 message handling in
// `lib/script_dialog.c`, which is the reference implementation of these four
// effects. Each method names the C lines it reproduces.

import 'dart:io';

import 'package:flutter/services.dart';

/// The channel name. Shared with both native implementations.
const String kDialogWindowChannel = 'taskpin/window';

/// Window effects a dialog can ask for.
///
/// Every method is a no-op when the platform has no implementation, so the
/// renderer can call them unconditionally: a missing plugin must degrade to
/// "the dialog looks ordinary", never to an exception that blanks the window.
abstract class DialogWindowApi {
  /// Remove the title bar and frame, and hide the window from the taskbar and
  /// Alt+Tab.
  ///
  /// Windows: strip `WS_CAPTION|WS_THICKFRAME`, add `WS_EX_TOOLWINDOW`, drop
  /// `WS_EX_APPWINDOW`. C parity: `WS_POPUP` + `WS_EX_TOOLWINDOW`,
  /// `lib/script_dialog.c:78-83`.
  Future<void> setBorderless(bool borderless);

  /// Let mouse input pass through to whatever is beneath.
  ///
  /// C parity: `WM_NCHITTEST` -> `HTTRANSPARENT`, `lib/script_dialog.c:623-624`.
  /// The native side uses `WS_EX_TRANSPARENT` instead, which is the correct
  /// spelling for a window Flutter owns (the C layer could answer the hit test
  /// itself because it owned the WndProc).
  Future<void> setClickthrough(bool clickthrough);

  /// Window alpha, `0`-`255`.
  ///
  /// C parity: `WS_EX_LAYERED` + `SetLayeredWindowAttributes(0, a, LWA_ALPHA)`,
  /// `lib/script_dialog.c:84-85, 101-104`. Note the C layer only adds
  /// `WS_EX_LAYERED` when `opacity < 255 || clickthrough` — see
  /// `DialogSpec.needsLayered`.
  Future<void> setOpacity(int alpha);

  /// Let the host composite the window over the desktop rather than painting a
  /// background. `TPDialogSpec.transparent_bg`.
  Future<void> setTransparentBackground(bool transparent);

  /// Move and size the window in screen coordinates.
  ///
  /// NOT `WindowController.setFrame`: `desktop_multi_window` 0.3.1 only handles
  /// `window_show` / `window_hide` in `FlutterWindowWrapper::HandleWindowMethod`
  /// (windows/flutter_window_wrapper.h), so a `window_setFrame` call errors with
  /// "unknown method". Position and size therefore go through this channel.
  ///
  /// [x] / [y] of -1 mean "centre on the primary screen", which is what the C
  /// layer does (`(screen - window) / 2`, `lib/script_dialog.c:92-94`).
  Future<void> setFrame({
    required int x,
    required int y,
    required int width,
    required int height,
  });

  /// Begin a system window drag from the current pointer position.
  ///
  /// C parity: `WM_NCHITTEST` -> `HTCAPTION` while Shift is held,
  /// `lib/script_dialog.c:621-622`.
  Future<void> beginDrag();

  /// Grow the window by a pixel delta, clamped to a usable minimum.
  ///
  /// C parity: Shift+wheel, `step = ±20`, `w<80 -> 80`, `h<40 -> 40`,
  /// `SetWindowPos(..., SWP_NOMOVE|SWP_NOZORDER)`,
  /// `lib/script_dialog.c:592-602`. The clamp lives in the native side so both
  /// platforms agree; the Dart side may pass any delta.
  Future<void> resizeBy(int dx, int dy);

  /// Close the window.
  Future<void> close();
}

/// The real implementation, over [kDialogWindowChannel].
class MethodChannelDialogWindowApi implements DialogWindowApi {
  MethodChannelDialogWindowApi({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(kDialogWindowChannel);

  final MethodChannel _channel;

  /// Swallow platform errors.
  ///
  /// A dialog that cannot apply its native effects is still a dialog: it must
  /// render, not throw. The failure is reported to the caller's log through
  /// [onError] rather than being silently dropped.
  Future<void> _invoke(String method, [Object? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // No native implementation on this platform / in this build. Expected on
      // a platform whose half has not been wired into a runner yet.
      onError?.call(method, 'no native implementation');
    } on PlatformException catch (e) {
      onError?.call(method, e.message ?? e.code);
    }
  }

  /// Invoked when a native call could not be applied. Null = ignore.
  void Function(String method, String reason)? onError;

  @override
  Future<void> setBorderless(bool borderless) =>
      _invoke('setBorderless', <String, dynamic>{'borderless': borderless});

  @override
  Future<void> setClickthrough(bool clickthrough) => _invoke(
    'setClickthrough',
    <String, dynamic>{'clickthrough': clickthrough},
  );

  @override
  Future<void> setOpacity(int alpha) =>
      _invoke('setOpacity', <String, dynamic>{'alpha': alpha});

  @override
  Future<void> setTransparentBackground(bool transparent) => _invoke(
    'setTransparentBackground',
    <String, dynamic>{'transparent': transparent},
  );

  @override
  Future<void> setFrame({
    required int x,
    required int y,
    required int width,
    required int height,
  }) => _invoke('setFrame', <String, dynamic>{
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  });

  @override
  Future<void> beginDrag() => _invoke('beginDrag');
  @override
  Future<void> resizeBy(int dx, int dy) =>
      _invoke('resizeBy', <String, dynamic>{'dx': dx, 'dy': dy});

  @override
  Future<void> close() => _invoke('close');
}

/// A no-op implementation for tests and for platforms without a native half.
class NoopDialogWindowApi implements DialogWindowApi {
  const NoopDialogWindowApi();

  @override
  Future<void> setBorderless(bool borderless) async {}
  @override
  Future<void> setClickthrough(bool clickthrough) async {}
  @override
  Future<void> setOpacity(int alpha) async {}
  @override
  Future<void> setTransparentBackground(bool transparent) async {}
  @override
  Future<void> setFrame({
    required int x,
    required int y,
    required int width,
    required int height,
  }) async {}
  @override
  Future<void> beginDrag() async {}
  @override
  Future<void> resizeBy(int dx, int dy) async {}
  @override
  Future<void> close() async {}
}

/// Records calls instead of applying them. Test seam.
class RecordingDialogWindowApi implements DialogWindowApi {
  final List<String> calls = <String>[];

  @override
  Future<void> setBorderless(bool borderless) async =>
      calls.add('setBorderless($borderless)');
  @override
  Future<void> setClickthrough(bool clickthrough) async =>
      calls.add('setClickthrough($clickthrough)');
  @override
  Future<void> setOpacity(int alpha) async => calls.add('setOpacity($alpha)');
  @override
  Future<void> setTransparentBackground(bool transparent) async =>
      calls.add('setTransparentBackground($transparent)');
  @override
  Future<void> setFrame({
    required int x,
    required int y,
    required int width,
    required int height,
  }) async => calls.add('setFrame($x,$y,$width,$height)');
  @override
  Future<void> beginDrag() async => calls.add('beginDrag');
  @override
  Future<void> resizeBy(int dx, int dy) async => calls.add('resizeBy($dx,$dy)');
  @override
  Future<void> close() async => calls.add('close');
}

/// The Shift+wheel resize step, in pixels. `lib/script_dialog.c:597`.
const int kDialogResizeStep = 20;

/// Minimum window size, matching the C clamps (`lib/script_dialog.c:599-600`).
const int kDialogMinWidth = 80;
const int kDialogMinHeight = 40;

/// Turn a scroll delta into a resize call, applying the C layer's rule.
///
/// Extracted so the sign convention is testable without a window: the C code
/// does `step = delta > 0 ? 20 : -20` and adds it to BOTH width and height
/// (`lib/script_dialog.c:596-598`), so scrolling up grows the dialog in both
/// axes at once.
Future<void> applyShiftScrollResize(
  DialogWindowApi api,
  double scrollDeltaY,
) async {
  if (scrollDeltaY == 0) {
    return;
  }
  final int step = scrollDeltaY > 0 ? kDialogResizeStep : -kDialogResizeStep;
  await api.resizeBy(step, step);
}

/// Whether this platform has a native half at all.
///
/// Used to decide between the real API and [NoopDialogWindowApi] at startup;
/// both files exist for Windows and macOS, so this is only false elsewhere.
bool get platformHasDialogWindowStyles =>
    Platform.isWindows || Platform.isMacOS;
