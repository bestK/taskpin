// The dialog's runtime state: the current spec, the refresh timer, and the
// actions.
//
// Kept as a plain `ChangeNotifier` rather than a Riverpod provider because a
// dialog lives in its OWN window isolate (`lib/app/windows/dialog_window.dart`)
// where there is no `ProviderScope` — the manager window's container does not
// cross the isolate boundary. A widget test can drive this directly.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'dialog_action.dart';
import 'dialog_spec.dart';
import 'window_channel.dart';

/// Re-runs the script that produced a dialog.
///
/// PHASE 3 IS THE BINDER. `packages/taskpin_engine` does not exist yet, so this
/// phase cannot call the engine; the dialog takes a callback instead. When
/// Phase 3 lands, its `EngineApi` supplies the implementation and nothing in
/// this directory changes:
///
///   DialogController(rerun: () async {
///     final result = await engineApi.executeFile(luaPath, argsJson);
///     return DialogSpec.fromScriptResult(result.toJson());
///   })
///
/// Returning null means "the script produced no dialog this time", which leaves
/// the existing content on screen rather than blanking the window — the C
/// behaviour when `script_exec_file` fails or the result is not a dialog
/// (`lib/script_dialog.c:361-366`).
typedef DialogRerun = Future<DialogSpec?> Function();

/// Owns a dialog's mutable state for the lifetime of its window.
class DialogController extends ChangeNotifier {
  DialogController({
    required DialogSpec spec,
    required this.windowApi,
    required this.actions,
    this.rerun,
    this.baseDirectory,
  }) : _spec = spec;

  DialogSpec _spec;

  /// The spec currently on screen.
  DialogSpec get spec => _spec;

  /// Native window effects.
  final DialogWindowApi windowApi;

  /// Where URL / command actions go.
  final DialogActionRunner actions;

  /// The script re-runner. Null disables refresh even if the spec asks for it.
  final DialogRerun? rerun;

  /// Base directory for resolving relative image paths.
  final String? baseDirectory;

  Timer? _timer;
  bool _inFlight = false;
  bool _disposed = false;

  /// Set when a refresh failed, so the view can say so instead of silently
  /// showing stale content. Cleared on the next success.
  String? refreshError;

  /// Apply the window's native effects and start the refresh timer.
  ///
  /// Order matters: the effects are applied to the window this controller was
  /// built for, so this must run after the window exists.
  Future<void> start() async {
    await applyWindowEffects();
    await centerOnPrimaryScreen();
    _startTimer();
  }

  /// Size and centre the window, the way `show_script_dialog` does.
  ///
  /// The C layer computes `x = (screen_w - win_w) / 2` (`lib/script_dialog.c:92-94`)
  /// and never moves the window again — a user's Shift+drag sticks for the life
  /// of the dialog. This is called once, from [start], for the same reason.
  ///
  /// PARITY: the `dlg_x` / `dlg_y` / `dlg_w` / `dlg_h` fields on `PinItem` are
  /// deliberately NOT honoured here. The C layer does not pass them either:
  /// `src/bar_window.c:350` calls `show_script_dialog(it->lua_path,
  /// it->params, it->param_count, &bar->script_result.dialog)` — the spec comes
  /// straight from the script result, and the four config fields are written by
  /// `lib/config.c:412-415` but never read. Honouring them now would silently
  /// move and resize every existing user's dialogs, so it is left for a later
  /// phase to decide deliberately.
  Future<void> centerOnPrimaryScreen() => windowApi.setFrame(
    // -1 is the "centre me" sentinel the native side understands.
    x: -1,
    y: -1,
    width: _spec.width,
    height: _spec.height,
  );

  /// Push the spec's window flags to the native side.
  ///
  /// Mirrors `show_script_dialog` (`lib/script_dialog.c:78-104`): borderless is
  /// independent of the other two, and `WS_EX_LAYERED` is only added when the
  /// window is clickthrough OR translucent (`:84-85`), which is what
  /// [DialogSpec.needsLayered] encodes.
  Future<void> applyWindowEffects() async {
    await windowApi.setBorderless(_spec.borderless);
    await windowApi.setTransparentBackground(_spec.transparentBg);
    await windowApi.setClickthrough(_spec.clickthrough);
    await windowApi.setOpacity(_spec.needsLayered ? _spec.opacity : 255);
  }

  void _startTimer() {
    _timer?.cancel();
    final int seconds = _spec.refreshSeconds;
    if (seconds <= 0 || rerun == null) {
      return;
    }
    // C: `SetTimer(hwnd, IDT_DIALOG_REFRESH, spec.refresh * 1000, NULL)`
    // (`lib/script_dialog.c:394-396`).
    _timer = Timer.periodic(Duration(seconds: seconds), (_) => refresh());
  }

  /// Re-run the script and swap the spec in place.
  ///
  /// The window is NOT recreated: position and size are the user's (they may
  /// have Shift+dragged it), and the C layer only replaces the spec and
  /// repaints (`lib/script_dialog.c:362-364`).
  ///
  /// A refresh that is still running when the next tick fires is skipped rather
  /// than queued — a slow `http.get` inside the script must not build a backlog
  /// of executions.
  Future<void> refresh() async {
    final DialogRerun? run = rerun;
    if (_disposed || run == null || _inFlight) {
      return;
    }
    _inFlight = true;
    try {
      final DialogSpec? next = await run();
      if (_disposed || next == null) {
        return;
      }
      // The window flags can change between runs (a clock that becomes
      // translucent at night, say), so they are re-applied, not just the items.
      _spec = next;
      refreshError = null;
      await applyWindowEffects();
      _startTimer();
      notifyListeners();
    } catch (e) {
      // A script error must not kill the refresh loop or blank the dialog. The
      // engine's own error reporting (`TPScriptResult.error`) is the primary
      // channel; this is the belt-and-braces path for a transport failure.
      refreshError = '$e';
      notifyListeners();
    } finally {
      _inFlight = false;
    }
  }

  /// Run a button item's action.
  Future<void> activate(DialogItem item) async {
    if (item.url.isNotEmpty) {
      await actions.openUrl(item.url);
      return;
    }
    if (item.cmd.isNotEmpty) {
      await actions.runCommand(item.cmd);
    }
  }

  /// Close the window.
  Future<void> close() async {
    _timer?.cancel();
    _timer = null;
    await windowApi.close();
  }

  /// Whether the refresh timer is running.
  @visibleForTesting
  bool get isRefreshing => _timer?.isActive ?? false;

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
