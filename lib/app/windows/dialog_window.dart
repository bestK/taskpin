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
  runApp(DialogSpecApp(source: bridge, windowApi: bridge.windowApi));
}

/// Receives the spec from the manager window and keeps the running controller.
class _DialogWindowBridge implements DialogSpecSource {
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

  @override
  String get luaPath => _arguments.luaPath;

  @override
  String get argsJson => _arguments.argsJson;

  /// Called when the script identity changes, so the app can (re)build the
  /// re-run callback for the new script.
  @override
  void Function()? onIdentityChanged;

  /// Whether the window has been shown at least once.
  ///
  /// A spec that arrives before the first frame must not show the window: it
  /// is still the runner's default 800x600 in the top-left corner and has no
  /// content. Once the first frame has been shown, every later spec — a repeat
  /// click, or a click after the dialog's X hid the window — may show it
  /// immediately, because the size and position are already right.
  bool _shown = false;

  /// Called by the scaffold once the window is on screen.
  @override
  void markShown() => _shown = true;

  DialogSpec? _spec;
  final MethodChannelDialogWindowApi _windowApi =
      MethodChannelDialogWindowApi();

  /// The window-effect API the renderer uses. A popover supplies
  /// `PopoverDialogWindowApi` instead (no-ops except `close`): an `NSPopover`
  /// is not an `NSWindow` this app may resize or restyle.
  DialogWindowApi get windowApi => _windowApi;

  /// Completes when the first spec arrives. The app waits on this rather than
  /// showing an empty frame.
  final Completer<void> _firstSpec = Completer<void>();

  @override
  DialogSpec? get spec => _spec;

  @override
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
      final bool first = !_firstSpec.isCompleted;
      _spec = DialogSpec.fromJson(Map<String, dynamic>.from(payload));
      if (first) {
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
      // SHOW ONLY ONCE THE WINDOW HAS SOMETHING TO SHOW.
      //
      // The first spec must not show it: the window is still the runner's
      // default 800x600 at 10,10 with nothing painted. `DialogWindowScaffold`
      // shows it after the frame is applied and the first frame is on screen,
      // and tells us with [markShown].
      //
      // Every later spec may show: the size and position are already right,
      // and the two cases that reach here — a second click on the same bar, and
      // a click after the dialog's X hid the window — both mean "be visible".
      // Without this, a dialog closed with its X could never be reopened: the
      // window still existed, so nothing re-created it, and nothing showed it.
      if (_shown) {
        unawaited(_windowApi.show());
      }
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

/// What a dialog-rendering engine needs from its host.
///
/// Two hosts exist: a `desktop_multi_window` child window (specs arrive on the
/// cross-engine [kDialogSpecChannel]) and the macOS menu-bar `NSPopover`
/// (specs arrive on a plain `taskpin/dialog_spec` MethodChannel). Both feed the
/// same [DialogSpecApp], so the decoder and renderer are written once.
abstract class DialogSpecSource {
  /// Completes when the first spec has arrived.
  Future<void> get ready;

  /// The spec currently on screen, or null before the first one.
  DialogSpec? get spec;

  /// The script that produced [spec], for the refresh loop. Empty disables it.
  String get luaPath;

  /// The `args` JSON to bind when re-running [luaPath].
  String get argsJson;

  /// Called when [luaPath] / [argsJson] change, so the app rebuilds the rerun.
  void Function()? onIdentityChanged;

  /// Called once the host has shown the content.
  void markShown();
}

/// The dialog-rendering app, shared by a dialog window and the macOS popover.
///
/// Stateful because the host is REUSED: it outlives the dialog it shows, and a
/// later dialog may come from a different script. Two things therefore change
/// at runtime — the script identity (from the source) and, the first time a
/// refreshing spec arrives, the engine. Both are owned here.
class DialogSpecApp extends StatefulWidget {
  const DialogSpecApp({
    super.key,
    required this.source,
    required this.windowApi,
    this.showScrollbar = false,
    this.onNaturalSize,
    this.hostDrawsSurface = false,
  });

  final DialogSpecSource source;

  /// Native window effects. A dialog window supplies the real `taskpin/window`
  /// API; the popover supplies `PopoverDialogWindowApi` (no-ops except
  /// `close`).
  final DialogWindowApi windowApi;

  /// See [DialogView.showScrollbar]. Only the popover sets it.
  final bool showScrollbar;

  /// See [DialogView.onNaturalSize]. Only the popover sets it: a dialog
  /// window fits itself through [DialogWindowApi.setHeight] instead.
  final ValueChanged<Size>? onNaturalSize;

  /// The host (the macOS popover) draws the frame and the material, and the
  /// app follows the system light/dark setting.
  ///
  /// A dialog window keeps the dark theme and paints its own rounded card. Only
  /// the popover sets this; see [DialogView.hostDrawsSurface].
  final bool hostDrawsSurface;

  @override
  State<DialogSpecApp> createState() => _DialogSpecAppState();
}

class _DialogSpecAppState extends State<DialogSpecApp> {
  /// Started on demand: a warmed window that only ever shows a non-refreshing
  /// dialog never pays for a Lua isolate.
  engine_ffi.EngineApi? _engine;

  /// The script the current spec belongs to, so a refresh re-runs the right
  /// one after the window is reused for a different bar.
  String _luaPath = '';

  @override
  void initState() {
    super.initState();
    _luaPath = widget.source.luaPath;
    widget.source.onIdentityChanged = _onIdentityChanged;
  }

  @override
  void dispose() {
    widget.source.onIdentityChanged = null;
    _engine?.dispose();
    super.dispose();
  }

  void _onIdentityChanged() {
    setState(() {
      _luaPath = widget.source.luaPath;
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
      // A popover's text must match the system appearance the NSPopover uses;
      // a dialog window stays dark, as it always has.
      themeMode: widget.hostDrawsSurface ? ThemeMode.system : ThemeMode.dark,
      // A dialog has no chrome to title, and the OS window carries the title.
      title: '',
      home: FutureBuilder<void>(
        future: widget.source.ready,
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            // A dialog WINDOW is hidden until its spec arrives, so this frame
            // is never seen there. The macOS popover is already on screen when
            // its engine boots, and it must not paint a flat block over the
            // popover's own material while it waits for the spec.
            if (widget.hostDrawsSurface) {
              return const SizedBox.expand();
            }
            return ColoredBox(
              color: TaskPinTheme.of(context).bg.flyout,
              child: const SizedBox.expand(),
            );
          }
          final DialogSpec spec = widget.source.spec!;
          return _EngineBoundScaffold(
            // Keyed by script identity: when the host is reused for another
            // bar, the scaffold is rebuilt from scratch, so the old
            // `DialogController` (with its timer and its stale rerun callback)
            // is disposed rather than left pointing at the previous script.
            key: ValueKey<String>('${_luaPath}\u0000${spec.title}'),
            spec: spec,
            windowApi: widget.windowApi,
            source: widget.source,
            engineFor: _engineFor,
            showScrollbar: widget.showScrollbar,
            onNaturalSize: widget.onNaturalSize,
            hostDrawsSurface: widget.hostDrawsSurface,
          );
        },
      ),
    );
  }
}

/// Binds a [DialogWindowScaffold] to an engine that may not exist yet.
///
/// The engine is started only when the spec asks for a refresh (see
/// `_DialogSpecAppState._engineFor`), so the scaffold cannot receive it at
/// construction. It resolves it in `initState` and holds the scaffold back
/// until it is ready, which is one frame at most after the first refresh.
class _EngineBoundScaffold extends StatefulWidget {
  const _EngineBoundScaffold({
    super.key,
    required this.spec,
    required this.windowApi,
    required this.source,
    required this.engineFor,
    this.showScrollbar = false,
    this.onNaturalSize,
    this.hostDrawsSurface = false,
  });

  final DialogSpec spec;
  final DialogWindowApi windowApi;
  final DialogSpecSource source;
  final Future<engine_ffi.EngineApi?> Function(DialogSpec spec) engineFor;
  final bool showScrollbar;
  final ValueChanged<Size>? onNaturalSize;
  final bool hostDrawsSurface;

  @override
  State<_EngineBoundScaffold> createState() => _EngineBoundScaffoldState();
}

class _EngineBoundScaffoldState extends State<_EngineBoundScaffold> {
  DialogRerun? _rerun;

  @override
  void initState() {
    super.initState();
    // THE FIRST FRAME DOES NOT WAIT FOR THE ENGINE.
    //
    // Starting a Lua isolate costs well over a second, and this used to hold
    // the scaffold back until it finished — so the dialog (and the window
    // show that follows its first frame) waited on the engine. The dialog's
    // content is already in the spec; only its `@refresh` loop needs the
    // engine. Rendering now and attaching the rerun when it is ready moves
    // that second off the click.
    _resolve();
  }

  Future<void> _resolve() async {
    final engine_ffi.EngineApi? engine = await widget.engineFor(widget.spec);
    if (!mounted) return;
    setState(() {
      _rerun = dialogRerun(
        // The source carries the CURRENT script identity: a reused host may
        // have adopted a different script since this state was built.
        arguments: DialogWindowArguments(
          luaPath: widget.source.luaPath,
          argsJson: widget.source.argsJson,
        ),
        engine: engine,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return DialogWindowScaffold(
      spec: widget.spec,
      windowApi: widget.windowApi,
      rerun: _rerun,
      onShown: widget.source.markShown,
      showScrollbar: widget.showScrollbar,
      onNaturalSize: widget.onNaturalSize,
      hostDrawsSurface: widget.hostDrawsSurface,
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
/// Separate from [DialogSpecApp] so a widget test can drive the whole
/// controller/view pair without a secondary window.
class DialogWindowScaffold extends StatefulWidget {
  const DialogWindowScaffold({
    super.key,
    required this.spec,
    required this.windowApi,
    this.rerun,
    this.actions,
    this.baseDirectory,
    this.onShown,
    this.showScrollbar = false,
    this.onNaturalSize,
    this.hostDrawsSurface = false,
  });

  final DialogSpec spec;
  final DialogWindowApi windowApi;

  /// PHASE 3 IS THE BINDER — see `dialog_controller.dart`'s [DialogRerun].
  final DialogRerun? rerun;

  /// Defaults to the real process runner.
  final DialogActionRunner? actions;

  final String? baseDirectory;

  /// Called once the window has been shown for the first time.
  ///
  /// The bridge uses it to stop suppressing later shows: a spec that arrives
  /// after the first frame may show the window immediately (repeat click, or a
  /// click after the dialog's X hid it).
  final VoidCallback? onShown;

  /// See [DialogView.showScrollbar].
  final bool showScrollbar;

  /// See [DialogView.onNaturalSize].
  final ValueChanged<Size>? onNaturalSize;

  /// See [DialogView.hostDrawsSurface].
  final bool hostDrawsSurface;

  @override
  State<DialogWindowScaffold> createState() => _DialogWindowScaffoldState();
}

class _DialogWindowScaffoldState extends State<DialogWindowScaffold> {
  late DialogController _controller;

  /// Whether the window's frame has been applied. The view waits for it: see
  /// `_startThenShow`.
  bool _framed = false;

  @override
  void initState() {
    super.initState();
    _controller = _build();
    unawaited(_startThenShow());
  }

  /// Apply the window effects, let one frame paint, then show.
  ///
  /// The window is created hidden so nothing is visible until it is both the
  /// right size (frame applied) and painted (first frame rendered). Showing at
  /// create time is what produced an empty 800x600 rectangle in the corner
  /// before the dialog appeared.
  Future<void> _startThenShow() async {
    await _controller.start();
    if (!mounted) return;
    // The view is built only now. It measures its content and asks the window
    // to fit it, so building before the frame is applied would measure the
    // runner's 800x600 creation size and grow the window to that — the dialog
    // came up nearly twice its content's height.
    setState(() => _framed = true);
    // One frame with the content in place, then show.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.windowApi.show());
      widget.onShown?.call();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void didUpdateWidget(DialogWindowScaffold old) {
    super.didUpdateWidget(old);
    if (old.spec != widget.spec) {
      _controller.dispose();
      _controller = _build();
      _controller.start();
    } else if (old.rerun != widget.rerun) {
      // The engine finished starting after the first frame: the refresh loop
      // was built without a rerun. Rebuild the controller, but only restart
      // the timer — `start` would re-centre a window the user may have moved.
      _controller.dispose();
      _controller = _build();
      _controller.startRefreshOnly();
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
    if (!_framed) {
      return const SizedBox.shrink();
    }
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
          showScrollbar: widget.showScrollbar,
          onNaturalSize: widget.onNaturalSize,
          hostDrawsSurface: widget.hostDrawsSurface,
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
  DialogWindowHost({this.actions, this.onError});

  final DialogActionRunner? actions;

  /// Called with the exception when the window cannot be created or reached.
  ///
  /// The failure used to be swallowed: `open` returned false and the caller
  /// had no way to say WHY, which made a broken runner look identical to a
  /// script that produced no dialog. Null keeps the old silent behaviour.
  final void Function(Object error)? onError;

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
          // Hidden until a spec has been painted into it: the first visible
          // frame must be the dialog, not an empty 800x600 window.
          hiddenAtLaunch: true,
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

  /// Create the dialog window now and boot its engine, hidden.
  ///
  /// WHY THIS EXISTS: a cold window costs ~3 s on this machine — native window,
  /// a second Flutter engine, a Dart isolate, `main`, the channel registration
  /// — and all of it happens after the user's click, so the first click looks
  /// broken. Warming moves that cost off the click: the window and its engine
  /// are already up, and the first `open()` is a `setSpec` plus a show.
  ///
  /// The trade-off is memory: a second engine stays resident (~120 MB). It is
  /// started lazily (see `main.dart`, a couple of seconds after the first
  /// frame) rather than at launch, so startup time is unaffected.
  ///
  /// Never throws: a platform without multi-window support simply keeps the
  /// lazy path, and [onError] hears about it.
  Future<void> warm() async {
    try {
      await _ensureWindow();
      // Wait for the child's `taskpin/dialog_spec` handler so the first real
      // spec does not spend its retry budget on a channel that is not up yet.
      for (int attempt = 0; attempt < 400; attempt++) {
        try {
          await kDialogSpecChannel.invokeMethod<void>('probe');
          return;
        } on WindowChannelException {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
    } on Object catch (e) {
      onError?.call(e);
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
      await _ensureWindow();
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
      bool sent = await _sendSpecWithRetry(
        spec,
        luaPath: luaPath,
        argsJson: argsJson,
      );
      if (!sent) {
        // The window on file is dead — it was destroyed from outside, or its
        // engine never came up. Tear it down and try ONE more with a fresh
        // window, which is what "click again and nothing happens" needed: the
        // host used to keep a dead handle and every later click failed the
        // same way.
        await _destroyWindow();
        try {
          await _ensureWindow();
          sent = await _sendSpecWithRetry(
            spec,
            luaPath: luaPath,
            argsJson: argsJson,
          );
        } on Object {
          sent = false;
        }
        if (!sent) {
          await _destroyWindow();
          return false;
        }
      }
      // The child shows itself after the spec is painted (see
      // `DialogWindowScaffold._startThenShow`). The plugin's `window.show()`
      // is not used here: it targets the handle recorded at create time, which
      // is not the root window, and it would show the window before the frame
      // is applied — the empty-corner flash.
      //
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
    } on Object catch (e) {
      // No plugin / no runner wiring. The caller falls back, and `onError`
      // (when supplied) says what went wrong.
      onError?.call(e);
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
      await const MethodChannel(kDialogWindowChannel)
          .invokeMethod<void>('destroy');
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
