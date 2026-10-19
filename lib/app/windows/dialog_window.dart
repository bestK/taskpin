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
  // Start this window's own engine only when the dialog can refresh (the args
  // name a script). A dialog with no `@refresh` never pays for an isolate.
  engine_ffi.EngineApi? engine;
  if (args.luaPath.isNotEmpty) {
    try {
      engine = await engine_ffi.EngineApi.start(debugName: 'taskpin-dialog-engine');
    } catch (_) {
      // No engine (library missing). The dialog still renders; its refresh
      // simply reports the failure through `DialogController.refreshError`.
      engine = null;
    }
  }

  final _DialogWindowBridge bridge = _DialogWindowBridge(args);
  await bridge.listen();
  runApp(_DialogWindowApp(bridge: bridge, engine: engine));
}

/// Receives the spec from the manager window and keeps the running controller.
class _DialogWindowBridge {
  _DialogWindowBridge(this.arguments);

  final DialogWindowArguments arguments;

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
      _spec = DialogSpec.fromJson(Map<String, dynamic>.from(payload));
      if (!_firstSpec.isCompleted) {
        _firstSpec.complete();
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

class _DialogWindowApp extends StatelessWidget {
  const _DialogWindowApp({required this.bridge, required this.engine});

  final _DialogWindowBridge bridge;

  /// The dialog window's own engine, or null when it could not start.
  final engine_ffi.EngineApi? engine;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: TaskPinTheme.light().toThemeData(),
      darkTheme: TaskPinTheme.dark().toThemeData(),
      themeMode: ThemeMode.dark,
      // A dialog has no chrome to title, and the OS window carries the title.
      title: '',
      home: FutureBuilder<void>(
        future: bridge.ready,
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            // `hiddenAtLaunch` means this frame is not visible in practice; it
            // exists so the engine has something to render while the spec
            // crosses the channel.
            return const SizedBox.shrink();
          }
          return DialogWindowScaffold(
            spec: bridge.spec!,
            windowApi: bridge._windowApi,
            rerun: dialogRerun(arguments: bridge.arguments, engine: engine),
          );
        },
      ),
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
    return DialogView(controller: _controller, onClose: _controller.close);
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

  /// Whether a dialog window is currently open.
  bool get isOpen => _window != null;

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
      WindowController? window = _window;
      if (window == null) {
        window = await WindowController.create(
          WindowConfiguration(
            arguments: DialogWindowArguments(
              luaPath: luaPath,
              argsJson: argsJson,
            ).encode(),
            // Hide until positioned and populated: otherwise the user sees an
            // empty window at the OS default position for one frame.
            hiddenAtLaunch: true,
          ),
        );
        _window = window;
        // The child registers the same channel name (see
        // `_DialogWindowBridge.listen`), so the name must NOT carry the window
        // id — `WindowMethodChannel` routes by engine, not by name.
        await window.show();
      }
      await kDialogSpecChannel.invokeMethod<void>('setSpec', spec.toJson());
      return true;
    } on Exception {
      // No plugin / no runner wiring. The caller falls back.
      _window = null;
      return false;
    }
  }

  /// Close the dialog window, if any.
  Future<void> close() async {
    final WindowController? window = _window;
    _window = null;
    if (window != null) {
      await window.hide();
    }
  }
}
