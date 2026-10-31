// The macOS menu-bar popover's Dart entry.
//
// `native/mac/PopoverHost.swift` starts a SECOND Flutter engine with the
// positional argument `popover` and hosts it in an `NSPopover` anchored to the
// clicked status item. That engine must render one script dialog and nothing
// else: no config load, no single-instance guard, no `BarController`. Running
// the manager shell there is what showed the whole manager inside the popover.
//
// The spec crosses on a PLAIN `MethodChannel` named `taskpin/dialog_spec`, not
// on `desktop_multi_window`'s `WindowMethodChannel`: the popover engine has no
// multi-window plugin, and a `WindowMethodChannel` can only reach engines that
// registered one. The method name (`setSpec`) and the payload shape are the
// same as the dialog window's, so the decoder and renderer are shared through
// [DialogSpecApp] rather than duplicated.
//
// REFRESH: the engine re-runs the script itself, exactly like a dialog window
// (`DialogSpecApp` + `dialogRerun`). The spec carries `luaPath` / `argsJson`, so
// the dialog's own `@refresh` interval is honoured. The alternative — the
// manager pushing a fresh spec on every bar refresh — would use the bar's
// interval instead and would need the manager to track which popover is open;
// reusing the dialog path is both simpler and consistent with the windowed
// dialog.
//
// SIZE: the popover is sized to its CONTENT, not to the spec's guess. A
// script's `height` is routinely wrong (and absent ones become 300), which cut
// tall dialogs off. After each layout that changes the dialog's natural size
// (see `DialogView.onNaturalSize`), this engine sends `resize` on the same
// channel; the host clamps it to the screen. When it is clamped, the dialog's
// item area scrolls, with a visible scrollbar (`showScrollbar`).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/dialogs/dialog_spec.dart';
import '../../features/dialogs/window_channel.dart';
import 'dialog_window.dart';

/// The popover's spec channel. Must match `kPopoverSpecChannel` in
/// `native/mac/StatusItemPlugin.swift` / `PopoverHost.swift`.
const String kPopoverSpecChannel = 'taskpin/dialog_spec';

/// Run the popover engine's isolate.
///
/// Called from `main()` BEFORE the manager or dialog-window branches: the
/// `popover` argument is this engine's whole identity.
Future<void> popoverMain() async {
  final _PopoverSpecSource source = _PopoverSpecSource();
  // Register the handler, then tell the host we are listening. The host does
  // not push before that (a push to an engine that is still starting is
  // dropped), so the first spec arrives as the reply to `ready`.
  source.listen();
  unawaited(source.announceReady());
  runApp(DialogSpecApp(
    source: source,
    // An `NSPopover` is not a window this app may resize, restyle or raise;
    // every effect but `close` is a no-op. Sizing goes through `resize`
    // instead, which the native host clamps and applies.
    windowApi: const PopoverDialogWindowApi(),
    showScrollbar: true,
    onNaturalSize: source.resizer.report,
    // The NSPopover draws the frame, material and corners; see
    // `DialogView.hostDrawsSurface`.
    hostDrawsSurface: true,
  ));
}

/// The popover's window effects: [NoopDialogWindowApi], except [close].
///
/// The dialog's X and Escape both end in `DialogController.close` ->
/// `windowApi.close()`. With the plain no-op API that did nothing, so the X in
/// the popover was dead. `close` asks the host to close the popover instead
/// (`PopoverHost`, same channel as `ready` / `resize`).
class PopoverDialogWindowApi extends NoopDialogWindowApi {
  const PopoverDialogWindowApi();

  static const MethodChannel _channel = MethodChannel(kPopoverSpecChannel);

  @override
  Future<void> close() async {
    try {
      await _channel.invokeMethod<void>('close');
    } on PlatformException {
      // A host without `close`: the popover still closes on a click outside.
    } on MissingPluginException {
      // Same.
    }
  }
}

/// Receives specs over the plain `taskpin/dialog_spec` channel.
///
/// Deliberately much smaller than `_DialogWindowBridge`: there is no window to
/// show/hide (the popover is already on screen when this engine boots) and no
/// cross-engine routing to wait for.
class _PopoverSpecSource implements DialogSpecSource {
  final MethodChannel _channel = const MethodChannel(kPopoverSpecChannel);
  final Completer<void> _firstSpec = Completer<void>();

  /// Fits the popover to the dialog's natural size.
  late final PopoverResizeReporter resizer = PopoverResizeReporter(
    spec: () => _spec,
    send: (double width, double height) async {
      try {
        await _channel.invokeMethod<void>('resize', <String, double>{
          'width': width,
          'height': height,
        });
      } on PlatformException {
        // A host without `resize` keeps the spec size; the scrollbar still
        // makes the overflow reachable.
      } on MissingPluginException {
        // Same.
      }
    },
  );

  DialogSpec? _spec;
  String _luaPath = '';
  String _argsJson = '';

  @override
  void Function()? onIdentityChanged;

  @override
  Future<void> get ready => _firstSpec.future;

  @override
  DialogSpec? get spec => _spec;

  @override
  String get luaPath => _luaPath;

  @override
  String get argsJson => _argsJson;

  /// Nothing to show: the popover is presented by the native host.
  @override
  void markShown() {}

  /// Register the `setSpec` handler.
  void listen() {
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'setSpec') {
        return null;
      }
      _accept(call.arguments);
      return null;
    });
  }

  /// Tell the native host this isolate can take specs, and adopt the spec it
  /// already holds (the click that opened the popover), if any.
  Future<void> announceReady() async {
    try {
      _accept(await _channel.invokeMethod<Object?>('ready'));
    } on PlatformException {
      // A host without the handshake: later `setSpec` pushes still arrive.
    } on MissingPluginException {
      // Same.
    }
  }

  void _accept(Object? payload) {
    // `null` is the normal reply to `ready` when the engine was pre-warmed
    // before any click: there is no spec yet, and the first one arrives later
    // as a `setSpec` push. Nothing to adopt.
    if (payload is! Map) {
      return;
    }
    // A spec always carries items; anything else is a probe or a malformed
    // message (same gate as the dialog window's bridge).
    final Object? items = payload['items'];
    if (items is! List) {
      return;
    }

    _luaPath = payload['luaPath'] is String
        ? payload['luaPath'] as String
        : '';
    _argsJson = payload['argsJson'] is String
        ? payload['argsJson'] as String
        : '';
    _spec = DialogSpec.fromJson(Map<String, dynamic>.from(payload));
    // The host resets the popover to the spec's own size on every `setSpec`,
    // so what was last sent no longer describes the popover: the next
    // measurement must be sent even if it matches.
    resizer.reset();
    if (!_firstSpec.isCompleted) {
      _firstSpec.complete();
    }
    // Notify on EVERY spec, not only when the script identity changes: the
    // popover has no controller-level refresh fed by the manager, so this is
    // the only way a later `showPopover` (a click on another bar) swaps the
    // content. Re-running the same script is handled by `DialogSpecApp`'s
    // own rerun callback, not by this notification.
    onIdentityChanged?.call();
  }
}

/// Turns natural-size reports into `resize` calls the host can apply.
///
/// Separate from the source so a test can drive the rules without a channel.
///
/// FEEDBACK. A `resize` changes the popover, which re-lays-out the dialog and
/// produces another report. The natural height does not depend on the
/// popover's height, so that report matches and is dropped by the 1 px
/// tolerance. The width can change the height (text wraps differently), but
/// the width itself is not derived from the popover's size, so that settles in
/// one more step rather than oscillating.
class PopoverResizeReporter {
  PopoverResizeReporter({required this.spec, required this.send});

  /// The spec on screen, for the width rule.
  final DialogSpec? Function() spec;

  /// Delivers one size, in logical pixels.
  final Future<void> Function(double width, double height) send;

  Size? _lastSent;
  Size? _pending;

  /// Forget what was sent, so the next report is sent unconditionally.
  void reset() => _lastSent = null;

  /// Accept a natural size from `DialogView.onNaturalSize`.
  ///
  /// Coalesced in a microtask: the view reports at most once per frame, but
  /// several reports landing in one frame's post-frame phase still become one
  /// call, carrying the latest.
  void report(Size natural) {
    final bool queued = _pending != null;
    _pending = natural;
    if (!queued) scheduleMicrotask(_flush);
  }

  void _flush() {
    final Size? natural = _pending;
    _pending = null;
    if (natural == null) return;
    final Size target = targetSize(spec(), natural);
    final Size? last = _lastSent;
    if (last != null &&
        (target.width - last.width).abs() <= 1 &&
        (target.height - last.height).abs() <= 1) {
      return;
    }
    _lastSent = target;
    unawaited(send(target.width, target.height));
  }

  /// The size to ask the host for, given the dialog's natural size.
  ///
  /// WIDTH. A script's `width` is honoured. A spec without one carries
  /// [kDialogDefaultWidth] (the parser fills it in, so "absent" and "asked
  /// for exactly 400" are indistinguishable); that one shrinks to the content
  /// but never grows past it. Growing to the content's max intrinsic width
  /// would make any dialog with one long text line as wide as the host allows
  /// (720), and would make a table that wraps today suddenly very wide.
  ///
  /// Both values are rounded UP: a fractional shortfall would leave a 1 px
  /// scroll range and a scrollbar on a dialog that fits.
  static Size targetSize(DialogSpec? spec, Size natural) {
    final int specWidth = spec?.width ?? kDialogDefaultWidth;
    final double width = specWidth != kDialogDefaultWidth
        ? specWidth.toDouble()
        : math.min(natural.width, kDialogDefaultWidth.toDouble());
    return Size(width.ceilToDouble(), natural.height.ceilToDouble());
  }
}
