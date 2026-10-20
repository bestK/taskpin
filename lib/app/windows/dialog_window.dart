// The dialog's secondary window.
//
// A dialog is its OWN top-level window, not a route in the manager window: it
// has to outlive navigation, be movable independently, sit above other windows,
// and be hidden from the taskbar and Alt+Tab when `borderless`. Hosting is
// `desktop_multi_window` (docs/FLUTTER_REWRITE_PLAN.md, Phase 6).
//
// The handshake, and the two places the plugin's API forces the shape:
//
//   1. `main()` in the CHILD engine must call [dialogWindowMain]. That function
//      registers a `WindowMethodChannel` handler, and the manager sends the
//      spec over it.
//   2. The spec cannot be passed in `WindowConfiguration.arguments`: those
//      arrive before `main()` can decode them, and a spec can be large (24 rows
//      x 6 columns of text, plus a 200 KB `data:` image URI). Sending it after
//      the window is up keeps the argument string small and lets the child ask
//      for nothing it does not need.
//   3. `hiddenAtLaunch: true` + `WindowController.show()` rather than a plain
//      create: it hides the flash of an empty, unpositioned window between
//      creation and the first frame.
//
// KNOWN GAP (this phase): the child engine needs `DesktopMultiWindowPlugin`
// registered to have the `mixin.one/desktop_multi_window` channel at all, and
// that registration is runner-side (`windows/runner/flutter_window.cpp`, and
// the generated `generated_plugin_registrant.cc`). This repo has no `windows/`
// or `macos/` runner yet — Phase 0 owns creating them — so this file cannot be
// exercised on this machine. It is written to the plugin's real 0.3.1 API
// (verified against the published package, not guessed), and the runner wiring
// is the one-line `DesktopMultiWindowSetWindowCreatedCallback` +
// `InternalMultiWindowPluginRegisterWithRegistrar` pair documented in the
// plugin's own `windows/` sources.

import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:taskpin_design/taskpin_design.dart';
import 'package:taskpin_engine/taskpin_engine.dart' as engine_ffi
    show DialogItem, EngineApi, ScriptResult;

import '../../features/dialogs/dialog_action.dart';
import '../../features/dialogs/dialog_controller.dart';
import '../../features/dialogs/dialog_spec.dart';
import '../../features/dialogs/dialog_view.dart';
import '../../features/dialogs/window_channel.dart';

/// The channel the manager window uses to hand a spec to a dialog window.
///
/// A `WindowMethodChannel` rather than a plain `MethodChannel`: the latter is
/// per-engine, and the child engine's `MethodChannel` handler is not reachable
/// from the parent's engine without the plugin's cross-engine routing.
const WindowMethodChannel kDialogSpecChannel = WindowMethodChannel(
  'taskpin/dialog_spec',
  mode: ChannelMode.unidirectional,
);

/// Marks a window as a TaskPin dialog and names its role.
///
/// `WindowConfiguration.arguments` is a string, so this is the small payload
/// that goes in it; the spec follows over [kDialogSpecChannel].
///
/// The MANAGER window has an EMPTY argument string (the plugin's
/// `AttachFlutterMainWindow` registers it with no `WindowConfiguration`), which
/// is why [decode] maps `''` to [unknown] rather than to a dialog — otherwise
/// the manager would misidentify itself.
class DialogWindowArguments {
  const DialogWindowArguments({
    this.kind = kDialogKind,
    this.luaPath = '',
    this.argsJson = '',
  });

  /// The `kind` value that marks a dialog window.
  static const String kDialogKind = 'dialog';

  /// The `kind` value for a secondary window with no known role.
  static const String kUnknownKind = 'unknown';

  final String kind;

  /// The script that produced the dialog, so the window can re-run it on its
  /// `@refresh` interval. Empty disables refresh (the controller already treats
  /// a null rerun that way), which is the correct behaviour for a dialog opened
  /// without a known source.
  final String luaPath;

  /// The `args` JSON to bind when re-running [luaPath], as the manager passed it.
  final String argsJson;

  /// Whether this is a dialog window.
  bool get isDialog => kind == kDialogKind;

  String encode() => jsonEncode(<String, dynamic>{
        'kind': kind,
        if (luaPath.isNotEmpty) 'luaPath': luaPath,
        if (argsJson.isNotEmpty) 'argsJson': argsJson,
      });

  static DialogWindowArguments decode(String raw) {
    if (raw.isEmpty) {
      // The manager window's argument string. Not a dialog.
      return const DialogWindowArguments(kind: kUnknownKind);
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map && decoded['kind'] is String) {
        return DialogWindowArguments(
          kind: decoded['kind'] as String,
          luaPath: decoded['luaPath'] is String ? decoded['luaPath'] as String : '',
          argsJson: decoded['argsJson'] is String ? decoded['argsJson'] as String : '',
        );
      }
    } on FormatException {
      // Fall through: an unparseable argument string means "not a dialog".
    }
    return const DialogWindowArguments(kind: kUnknownKind);
  }
}

/// Whether the current engine is a dialog window.
///
/// Called from `main()` before `runApp`. Returns null when this engine is the
/// manager window (or multi-window support is unavailable), which is the signal
/// to run the normal app instead.
///
/// Returns non-null ONLY for a window whose arguments name a dialog — the
/// manager window (empty arguments) and any unrecognised secondary window yield
/// null, so the caller never mistakes the manager for a dialog.
Future<DialogWindowArguments?> dialogWindowArguments() async {
  try {
    final WindowController controller =
        await WindowController.fromCurrentEngine();
    final DialogWindowArguments args =
        DialogWindowArguments.decode(controller.arguments);
    return args.isDialog ? args : null;
  } on Exception {
    // No plugin, or this is the first engine. Either way: not a dialog.
    return null;
  }
}

/// Entry point for a dialog window's isolate.
///
/// The child engine's `main()` is:
///
///   void main(List<String> args) async {
///     WidgetsFlutterBinding.ensureInitialized();
///     final dialog = await dialogWindowArguments();
///     if (dialog != null) {
///       await dialogWindowMain(dialog, args);
///       return;
///     }
///     await taskpinMain(args);   // the manager window
///   }
///
/// It must NOT be `@pragma('vm:entry-point')`: `desktop_multi_window` starts the
/// child engine on the same Dart entry point as the parent (`dart_entrypoint`
/// in its Windows `FlutterWindow`), so the branch happens inside one `main`.
///
/// [entrypointArgs] is the child engine's entrypoint argument list, which the
/// plugin sets to `['multi_window', <windowId>, <windowArgument>]`
/// (`windows/flutter_window.cc` in desktop_multi_window 0.3.1). It is accepted
/// so the branch in `main` can forward it without `main` needing to know the
/// shape; the dialog needs nothing from it, because the spec arrives over
/// [kDialogSpecChannel] and the script identity arrives in [args].
Future<void> dialogWindowMain(
  DialogWindowArguments args, [
  List<String> entrypointArgs = const <String>[],
]) async {
  // The engine is started LAZILY, on the first spec that asks for a refresh.
  //
  // A window created by `DialogWindowHost.warm()` has no script yet: it exists
  // only so the first click does not pay for the engine boot. Starting a Lua
  // isolate for it would undo that. The first `setSpec` carries the script
  // identity, and that is when an engine becomes necessary — and only if the
  // spec has a `@refresh` interval.
  final _DialogWindowBridge bridge = _DialogWindowBridge(args);
  await bridge.listen();
  runApp(_DialogWindowApp(bridge: bridge));
}

/// Receives the spec from the manager window and keeps the running controller.
class _DialogWindowBridge {
  _DialogWindowBridge(this._arguments);

  /// The window's launch arguments.
  ///
  /// Mutable identity: `DialogWindowHost` reuses ONE window for every dialog,
  /// so the script a window refreshes changes when a different bar is clicked.
  /// The manager sends the new identity with every `setSpec`, and [_adopt]
  /// applies it.
  DialogWindowArguments _arguments;

  /// The script this window currently represents, for the refresh loop.
  DialogWindowArguments get arguments => _arguments;

  /// Called when the script identity changes, so the app can (re)build the
  /// re-run callback for the new script.
  void Function()? onIdentityChanged;

  DialogSpec? _spec;
  final MethodChannelDialogWindowApi _windowApi =
      MethodChannelDialogWindowApi();

  /// Completes when the first spec arrives. The app waits on this rather than
  /// showing an empty frame.
  final Completer<void> _firstSpec = Completer<void>();

  DialogSpec? get spec => _spec;

  Future<void> get ready => _firstSpec.future;

  Future<void> listen() async {
    await kDialogSpecChannel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'setSpec') {
        return null;
      }
      final Object? payload = call.arguments;
      if (payload is! Map) {
        return null;
      }
      // A spec always carries items; anything else is a probe or a malformed
      // message. Accepting an empty map here once turned the channel probe
      // into the first dialog (see `DialogWindowHost._waitForChannel`).
      final Object? items = payload['items'];
      if (items is! List) {
        return null;
      }
      // The identity travels WITH the spec, because the window is reused: the
      // launch arguments are only correct for the first dialog it ever showed.
      final String luaPath = payload['luaPath'] is String
          ? payload['luaPath'] as String
          : '';
      final String argsJson = payload['argsJson'] is String
          ? payload['argsJson'] as String
          : '';
      final bool identityChanged = luaPath != _arguments.luaPath ||
          argsJson != _arguments.argsJson;
      if (identityChanged) {
        _arguments = DialogWindowArguments(
          luaPath: luaPath,
          argsJson: argsJson,
        );
      }
      _spec = DialogSpec.fromJson(Map<String, dynamic>.from(payload));
      if (!_firstSpec.isCompleted) {
        _firstSpec.complete();
      }
      // RAISE OURSELVES ON EVERY SPEC.
      //
      // A click on a bar whose dialog is already open must bring that dialog
      // to the front. The manager cannot do it for us: it is a different
      // process from this window's engine, and `SetForegroundWindow` from a
      // background process is refused by the foreground lock. This window CAN
      // raise itself, so the manager sends the spec again on every click and
      // this handler does the rest.
      //
      // `_windowApi.show()` is the `taskpin/window` path, which un-minimises,
      // does a topmost round-trip and calls `SetForegroundWindow` — see the
      // native `show` handler for why the round-trip is needed.
      unawaited(_windowApi.show());
      if (identityChanged) {
        onIdentityChanged?.call();
      }
      return null;
    });
  }
}

/// The re-run callback for a dialog, or null when it cannot refresh.
///
/// The dialog's own isolate has its own [EngineApi] (the manager's engine is in
/// a different isolate and does not cross the boundary). A Lua error is NOT
/// thrown: it comes back in `ScriptResult.error` and the controller keeps the
/// existing content on screen. A transport failure throws, and the controller
/// records it in `refreshError`.
DialogRerun? dialogRerun({
  required DialogWindowArguments arguments,
  required engine_ffi.EngineApi? engine,
}) {
  if (engine == null || arguments.luaPath.isEmpty) return null;
  return () async {
    final engine_ffi.ScriptResult result = await engine.executeFile(
      arguments.luaPath,
      argsJson: arguments.argsJson.isEmpty ? null : arguments.argsJson,
    );
    // No dialog this run: keep what is on screen (the C behaviour when the
    // result is not a dialog, `lib/script_dialog.c:361-366`).
    return DialogSpec.fromScriptResult(scriptResultToDialogMap(result));
  };
}

/// The dialog window's app.
///
/// Stateful because the window is REUSED: it outlives the dialog it shows, and
/// a later dialog may come from a different script. Two things therefore change
/// at runtime — the script identity (from the bridge) and, the first time a
/// refreshing spec arrives, the engine. Both are owned here.
class _DialogWindowApp extends StatefulWidget {
  const _DialogWindowApp({required this.bridge});

  final _DialogWindowBridge bridge;

  @override
  State<_DialogWindowApp> createState() => _DialogWindowAppState();
}

class _DialogWindowAppState extends State<_DialogWindowApp> {
  /// Started on demand: a warmed window that only ever shows a non-refreshing
  /// dialog never pays for a Lua isolate.
  engine_ffi.EngineApi? _engine;

  /// The script the current spec belongs to, so a refresh re-runs the right
  /// one after the window is reused for a different bar.
  String _luaPath = '';

  @override
  void initState() {
    super.initState();
    _luaPath = widget.bridge.arguments.luaPath;
    widget.bridge.onIdentityChanged = _onIdentityChanged;
  }

  @override
  void dispose() {
    widget.bridge.onIdentityChanged = null;
    _engine?.dispose();
    super.dispose();
  }

  void _onIdentityChanged() {
    setState(() {
      _luaPath = widget.bridge.arguments.luaPath;
    });
  }

  /// Start the engine the first time a spec actually needs it.
  Future<engine_ffi.EngineApi?> _engineFor(DialogSpec spec) async {
    if (_luaPath.isEmpty || spec.refreshSeconds <= 0) return null;
    if (_engine != null) return _engine;
    try {
      _engine = await engine_ffi.EngineApi.start(
        debugName: 'taskpin-dialog-engine',
      );
    } catch (_) {
      // No engine (library missing). The dialog still renders; its refresh
      // simply reports the failure through `DialogController.refreshError`.
      _engine = null;
    }
    return _engine;
  }

  @override
  Widget build(BuildContext context) {
    // TRANSPARENT BACKGROUND.
    //
    // The window is borderless and DWM rounds its corners, so the area outside
    // the dialog's own rounded surface must be see-through. Without this the
    // theme's `scaffoldBackgroundColor` (a dark grey) fills the whole window
    // and the rounded panel sits on a black square.
    //
    // `color` + `MaterialApp` alone are not enough: Flutter's root surface is
    // cleared to the scaffold colour, so both the theme override and the
    // transparent `home` below are needed.
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: TaskPinTheme.light().toThemeData().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
      ),
      darkTheme: TaskPinTheme.dark().toThemeData().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
      ),
      themeMode: ThemeMode.dark,
      // A dialog has no chrome to title, and the OS window carries the title.
      title: '',
      home: FutureBuilder<void>(
        future: widget.bridge.ready,
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            // `hiddenAtLaunch` means this frame is not visible in practice; it
            // exists so the engine has something to render while the spec
            // crosses the channel.
            return const SizedBox.shrink();
          }
          final DialogSpec spec = widget.bridge.spec!;
          return _EngineBoundScaffold(
            // Keyed by script identity: when the window is reused for another
            // bar, the scaffold is rebuilt from scratch, so the old
            // `DialogController` (with its timer and its stale rerun callback)
            // is disposed rather than left pointing at the previous script.
            key: ValueKey<String>('${_luaPath}\u0000${spec.title}'),
            spec: spec,
            windowApi: widget.bridge._windowApi,
            bridge: widget.bridge,
            engineFor: _engineFor,
          );
        },
      ),
    );
  }
}

/// Binds a [DialogWindowScaffold] to an engine that may not exist yet.
///
/// The engine is started only when the spec asks for a refresh (see
/// `_DialogWindowAppState._engineFor`), so the scaffold cannot receive it at
/// construction. It resolves it in `initState` and holds the scaffold back
/// until it is ready, which is one frame at most after the first refresh.
class _EngineBoundScaffold extends StatefulWidget {
  const _EngineBoundScaffold({
    super.key,
    required this.spec,
    required this.windowApi,
    required this.bridge,
    required this.engineFor,
  });

  final DialogSpec spec;
  final DialogWindowApi windowApi;
  final _DialogWindowBridge bridge;
  final Future<engine_ffi.EngineApi?> Function(DialogSpec spec) engineFor;

  @override
  State<_EngineBoundScaffold> createState() => _EngineBoundScaffoldState();
}

class _EngineBoundScaffoldState extends State<_EngineBoundScaffold> {
  DialogRerun? _rerun;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final engine_ffi.EngineApi? engine = await widget.engineFor(widget.spec);
    if (!mounted) return;
    setState(() {
      _rerun = dialogRerun(
        arguments: widget.bridge.arguments,
        engine: engine,
      );
      _resolved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_resolved) {
      return const SizedBox.shrink();
    }
    return DialogWindowScaffold(
      spec: widget.spec,
      windowApi: widget.windowApi,
      rerun: _rerun,
    );
  }
}

/// Turns an engine [ScriptResult] into the `Map<String, dynamic>` shape
/// `DialogSpec.fromScriptResult` reads.
///
/// `DialogSpec` is deliberately `Map`-based (see its header) so it does not
/// depend on the engine package. This is the one adapter between them.
Map<String, dynamic> scriptResultToDialogMap(engine_ffi.ScriptResult r) => <String, dynamic>{
      'clickable': r.clickable,
      'click_action': r.clickAction.wireValue,
      'dialog': <String, dynamic>{
        'title': r.dialog.title,
        'width': r.dialog.width,
        'height': r.dialog.height,
        'refresh': r.dialog.refresh,
        'borderless': r.dialog.borderless ? 1 : 0,
        'clickthrough': r.dialog.clickthrough ? 1 : 0,
        'opacity': r.dialog.opacity,
        'bg_color': r.dialog.backgroundColor,
        'transparent_bg': r.dialog.transparentBackground ? 1 : 0,
        'items': <Map<String, dynamic>>[
          for (final engine_ffi.DialogItem i in r.dialog.items) _dialogItemToMap(i),
        ],
      },
    };

Map<String, dynamic> _dialogItemToMap(engine_ffi.DialogItem i) => <String, dynamic>{
      'type': i.type.wireValue,
      'value': i.value,
      'color': i.color,
      'font_size': i.fontSize,
      'bold': i.bold ? 1 : 0,
      'image': i.image,
      'image_width': i.imageWidth,
      'image_height': i.imageHeight,
      'url': i.url,
      'cmd': i.cmd,
      'bg': i.bg,
      'web_w': i.webWidth,
      'web_h': i.webHeight,
      'col_count': i.columns.length,
      'row_count': i.rows.length,
      'columns': i.columns,
      'cells': i.rows,
      'row_urls': i.rowUrls,
      'row_cmds': i.rowCmds,
    };

/// Wires a [DialogController] to a [DialogView] for one spec.
///
/// Separate from [_DialogWindowApp] so a widget test can drive the whole
/// controller/view pair without a secondary window.
class DialogWindowScaffold extends StatefulWidget {
  const DialogWindowScaffold({
    super.key,
    required this.spec,
    required this.windowApi,
    this.rerun,
    this.actions,
    this.baseDirectory,
  });

  final DialogSpec spec;
  final DialogWindowApi windowApi;

  /// PHASE 3 IS THE BINDER — see `dialog_controller.dart`'s [DialogRerun].
  final DialogRerun? rerun;

  /// Defaults to the real process runner.
  final DialogActionRunner? actions;

  final String? baseDirectory;

  @override
  State<DialogWindowScaffold> createState() => _DialogWindowScaffoldState();
}

class _DialogWindowScaffoldState extends State<DialogWindowScaffold> {
  late DialogController _controller;

  @override
  void initState() {
    super.initState();
    _controller = _build();
    _controller.start();
  }

  @override
  void didUpdateWidget(DialogWindowScaffold old) {
    super.didUpdateWidget(old);
    if (old.spec != widget.spec) {
      _controller.dispose();
      _controller = _build();
      _controller.start();
    }
  }

  DialogController _build() => DialogController(
    spec: widget.spec,
    windowApi: widget.windowApi,
    actions: widget.actions ?? const ProcessDialogActionRunner(),
    rerun: widget.rerun,
    baseDirectory: widget.baseDirectory,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    // `Material` is NOT optional here.
    //
    // `DialogView` draws its own surface (a `DecoratedBox` with the flyout
    // colour), but it renders `Text` widgets, and a `Text` with no `Material`
    // ancestor does not inherit `DefaultTextStyle` — it falls back to the
    // engine's debug style, which is what produced the yellow underlines and
    // the wrong type ramp in the dialog window. The manager window never hit
    // this because its tree starts at a `Scaffold`.
    //
    // Transparent, because the surface colour belongs to `DialogView`: painting
    // it here as well would double up and break `transparent_bg`.
    return Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle(
        style: TpTypography.body.toTextStyle().copyWith(
          color: theme.text.primary,
        ),
        child: DialogView(
          controller: _controller,
          onClose: _controller.close,
        ),
      ),
    );
  }
}

/// Opens (or focuses) a dialog window for [spec].
///
/// Mirrors the C layer's single-dialog rule: `show_script_dialog` returns early
/// with `SetForegroundWindow` when a dialog is already up
/// (`lib/script_dialog.c:59-62`), so a second click on the bar raises the
/// existing dialog rather than stacking another one.
class DialogWindowHost {
  DialogWindowHost({this.actions});

  final DialogActionRunner? actions;

  WindowController? _window;

  /// The in-flight create, shared by `warm()` and `open()`.
  ///
  /// WITHOUT THIS, A CLICK DURING WARM-UP CREATES A SECOND ENGINE. `warm()`
  /// runs at startup and takes a while (native window + Flutter engine + Dart
  /// isolate); if the user clicks a bar before it finishes, `open()` saw
  /// `_window == null`, created another window, and the first one was orphaned
  /// — two engines, two isolates, and the orphan kept polling. That is the
  /// "slow and heavy" behaviour: not one slow open, but two engines competing.
  ///
  /// Both callers now await the same future, so exactly one window exists.
  Future<WindowController>? _creating;

  /// Whether a dialog window is currently open.
  bool get isOpen => _window != null;

  /// Get the window, creating it at most once.
  Future<WindowController> _ensureWindow() {
    final WindowController? existing = _window;
    if (existing != null) return Future<WindowController>.value(existing);
    return _creating ??= _createWindow();
  }

  Future<WindowController> _createWindow() async {
    try {
      final WindowController window = await WindowController.create(
        WindowConfiguration(
          arguments: const DialogWindowArguments().encode(),
          hiddenAtLaunch: false,
        ),
      );
      _window = window;
      return window;
    } finally {
      // Cleared on both paths: on success the window is cached in `_window`,
      // and on failure the next caller must be allowed to retry.
      _creating = null;
    }
  }

  /// Create the window if needed, then send [spec].
  ///
  /// [luaPath] / [argsJson] identify the script that produced [spec], so the
  /// window can re-run it on its `@refresh` interval. Pass them whenever they
  /// are known; omit them (or pass empty) for a dialog that need not refresh.
  ///
  /// Returns false when multi-window support is unavailable — the caller
  /// decides what to do (the manager window can embed [DialogWindowScaffold]
  /// directly instead).
  Future<bool> open(
    DialogSpec spec, {
    String luaPath = '',
    String argsJson = '',
  }) async {
    try {
      // Awaits the startup warm-up instead of racing it (see `_creating`).
      final WindowController window = await _ensureWindow();
      // WAIT FOR THE CHILD ENGINE TO REGISTER ITS HANDLER.
      //
      // `WindowController.create` returns as soon as the native window exists.
      // The child engine then boots its own Dart isolate, runs `main`, decodes
      // the window arguments and only THEN calls `bridge.listen()` — which is
      // what registers `taskpin/dialog_spec`. Sending the spec immediately
      // races that registration and fails with
      // `WindowMethodChannelException(CHANNEL_UNREGISTERED, ...)`, which the
      // catch below used to swallow, leaving an empty 800x600 window.
      //
      // Poll until the handler answers. The window is `hiddenAtLaunch`, so a
      // short wait is invisible; the timeout keeps a genuinely broken child
      // (no runner wiring, crashed isolate) from hanging the click forever.
      final bool sent = await _sendSpecWithRetry(
        spec,
        luaPath: luaPath,
        argsJson: argsJson,
      );
      if (!sent) {
        // The child never registered the channel. Tear the window down rather
        // than leaving a half-started engine resident for the rest of the
        // session; the next open tries a fresh one.
        await _destroyWindow();
        return false;
      }
      // The spec is in the child now. Showing here (rather than at create)
      // means the first visible frame is the populated dialog.
      await window.show();
      // Raise it through the MANAGER's channel.
      //
      // The dialog's own engine tried to raise itself when the spec arrived,
      // but Windows' foreground lock refuses `SetForegroundWindow` from a
      // process that did not just receive user input. This process did: the
      // click that got us here. `raiseDialog` is the one call that has the
      // rights to do it.
      try {
        await const MethodChannel('taskpin/main_window')
            .invokeMethod<bool>('raiseDialog');
      } on Object {
        // No manager channel (a test, or a platform without it). The dialog is
        // still visible; it just may not be on top.
      }
      return true;
    } on Exception {
      // No plugin / no runner wiring. The caller falls back.
      await _destroyWindow();
      return false;
    }
  }

  /// Forget and destroy the current window, if any.
  ///
  /// `desktop_multi_window` exposes only `show` / `hide`; there is no
  /// `WindowController.close`. Destroying means asking the window's own engine
  /// to post `WM_CLOSE` through `taskpin/window`, which is the channel this app
  /// already owns — the window then goes away and takes its engine and isolate
  /// with it.
  Future<void> _destroyWindow() async {
    final WindowController? window = _window;
    _window = null;
    if (window == null) return;
    try {
      await const MethodChannel(kDialogWindowChannel).invokeMethod<void>('close');
    } on Object {
      // The child is already gone, or the channel was never up. Either way
      // there is nothing left to release.
    }
  }

  /// Send [spec], retrying while the child engine is still starting.
  ///
  /// [luaPath] / [argsJson] ride along because the window is reused: its launch
  /// arguments only describe the first dialog it ever showed, and the refresh
  /// loop needs the CURRENT script.
  ///
  /// Returns false if every attempt failed, which means the child never
  /// registered the channel.
  Future<bool> _sendSpecWithRetry(
    DialogSpec spec, {
    String luaPath = '',
    String argsJson = '',
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      ...spec.toJson(),
      'luaPath': luaPath,
      'argsJson': argsJson,
    };
    for (int attempt = 0; attempt < 400; attempt++) {
      try {
        await kDialogSpecChannel.invokeMethod<void>('setSpec', payload);
        return true;
      } on WindowChannelException {
        // Not registered yet.
        //
        // 10 ms, not 50: the wait is pure latency on the user's click, and the
        // channel becomes available the instant the child's `main` reaches
        // `bridge.listen()`. A 50 ms poll added up to 50 ms of dead time per
        // missed attempt — measured at ~350 ms of the 3.4 s first open on this
        // machine. 400 attempts still bounds a broken child at ~4 s.
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
    return false;
  }

  /// Hide the dialog window.
  ///
  /// The window is NOT destroyed: keeping the engine alive is what makes the
  /// next open instant. It is released when the app exits (`dispose`).
  Future<void> close() async {
    final WindowController? window = _window;
    if (window == null) return;
    await window.hide();
  }

  /// Release everything. Called when the app is shutting down.
  Future<void> dispose() => _destroyWindow();
}
