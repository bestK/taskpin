// The Dart half of `taskpin/main_window`.
//
// This channel drives the MANAGER window's own chrome: the minimize / maximize
// / close buttons of the self-drawn title bar (`lib/ui/widgets/title_bar.dart`).
// The native half is `native/win/taskpin_window_plugin.cpp`.
//
// ─────────────────────────────────────────────────────────────────────────────
// WHY THE NAME IS NOT `taskpin/window`
// ─────────────────────────────────────────────────────────────────────────────
// `taskpin/window` already belongs to the script dialog window — see
// `lib/features/dialogs/window_channel.dart` and
// `native/win/dialog_window_styles.cpp`. Those methods (setBorderless,
// setClickthrough, setOpacity, ...) describe a popup with no title bar at all,
// which is the opposite of what the manager window needs. Sharing one channel
// name would make each side's `NotImplemented` fall through to the other's
// methods and couple two unrelated windows.
//
// The file name is `main_window_channel.dart`, not `window_channel.dart`, so it
// cannot be confused with (or shadow) the dialog channel file.
//
// ─────────────────────────────────────────────────────────────────────────────
// CONTRACT
// ─────────────────────────────────────────────────────────────────────────────
//   taskpin/main_window          MethodChannel
//     minimize() -> void
//     toggleMaximize() -> void
//     close() -> void
//     isMaximized() -> bool
//
//   taskpin/main_window/events   EventChannel, Stream<bool>
//     One `maximizedChanged` event per WM_SIZE. Covers every path that can
//     change the state, including Aero Snap and Win+Up, which never go through
//     this class.
//
// `isMaximized` doubles as the availability probe. A platform without a native
// half (macOS today, and every widget test that does not install a mock)
// answers with MissingPluginException, which this file turns into `null`. The
// title bar then renders no buttons instead of throwing — the same "degrade,
// never crash" rule the dialog channel follows.
//
// No third-party dependency: only `package:flutter/services.dart`.

import 'dart:async';

import 'package:flutter/services.dart';

/// Window commands for the manager window.
const String kMainWindowChannel = 'taskpin/main_window';

/// Native -> Dart window state events. Same name the C++ side registers.
const String kMainWindowEventsChannel = 'taskpin/main_window/events';

/// The window commands the title bar needs.
///
/// Every method is a no-op when no native implementation exists, so callers
/// never have to guard them.
abstract class MainWindowApi {
  /// Minimize the manager window.
  Future<void> minimize();

  /// Maximize if restored, restore if maximized.
  Future<void> toggleMaximize();

  /// Close the manager window (which quits the app — the runner sets
  /// `SetQuitOnClose(true)`).
  Future<void> close();

  /// Whether the window is maximized.
  ///
  /// Returns `null` when the platform has no native half, which is also the
  /// signal the title bar uses to hide its buttons.
  Future<bool?> isMaximized();

  /// Emits `true` on maximize and `false` on restore.
  ///
  /// Only subscribe after [isMaximized] returned non-null: on a platform
  /// without the native half, subscribing would report a MissingPluginException
  /// through `FlutterError.reportError`.
  Stream<bool> get maximizedChanged;
}

/// The real implementation, over the two channels above.
class MethodChannelMainWindowApi implements MainWindowApi {
  MethodChannelMainWindowApi({
    MethodChannel? channel,
    EventChannel? events,
  }) : _channel = channel ?? const MethodChannel(kMainWindowChannel),
       _events = events ?? const EventChannel(kMainWindowEventsChannel);

  final MethodChannel _channel;
  final EventChannel _events;

  /// One broadcast stream per api instance. `receiveBroadcastStream()` starts a
  /// new native subscription each time it is called, so it must not be called
  /// from `build`.
  late final Stream<bool> _maximizedChanged = _events
      .receiveBroadcastStream()
      .where((Object? event) => event is bool)
      .cast<bool>();

  /// Fire-and-forget a command.
  ///
  /// A window command that cannot be delivered is not worth an exception: the
  /// window stays as it is, which is the least surprising outcome. The dialog
  /// channel reports these through an `onError` hook; the title bar has no log
  /// surface of its own, and a failed minimize is visible to the user anyway.
  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // No native half on this platform / in this build.
    } on PlatformException {
      // The window is gone, or the command was rejected. Nothing to do.
    }
  }

  @override
  Future<void> minimize() => _invoke('minimize');

  @override
  Future<void> toggleMaximize() => _invoke('toggleMaximize');

  @override
  Future<void> close() => _invoke('close');

  @override
  Future<bool?> isMaximized() async {
    try {
      return await _channel.invokeMethod<bool>('isMaximized');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Stream<bool> get maximizedChanged => _maximizedChanged;
}

/// A no-op implementation for platforms without a native half.
class NoopMainWindowApi implements MainWindowApi {
  const NoopMainWindowApi();

  @override
  Future<void> minimize() async {}
  @override
  Future<void> toggleMaximize() async {}
  @override
  Future<void> close() async {}

  /// Null = "not supported", so the title bar hides its buttons.
  @override
  Future<bool?> isMaximized() async => null;

  @override
  Stream<bool> get maximizedChanged => const Stream<bool>.empty();
}

/// Records calls instead of applying them. Test seam.
class RecordingMainWindowApi implements MainWindowApi {
  RecordingMainWindowApi({this.maximized = false, this.supported = true});

  /// What [isMaximized] returns. `null` (via [supported] = false) simulates a
  /// platform with no native half.
  bool maximized;

  /// Whether the "channel" exists.
  bool supported;

  final List<String> calls = <String>[];

  final StreamController<bool> _events = StreamController<bool>.broadcast();

  /// Push a native `maximizedChanged` event.
  void emitMaximized(bool value) {
    maximized = value;
    _events.add(value);
  }

  /// Release the controller. Call from `tearDown`.
  Future<void> dispose() => _events.close();

  @override
  Future<void> minimize() async => calls.add('minimize');
  @override
  Future<void> toggleMaximize() async => calls.add('toggleMaximize');
  @override
  Future<void> close() async => calls.add('close');

  @override
  Future<bool?> isMaximized() async => supported ? maximized : null;

  @override
  Stream<bool> get maximizedChanged => _events.stream;
}
