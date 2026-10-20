// Inline dialogs: a script's `dialog(...)` shown as a floating panel INSIDE
// the manager window.
//
// WHY NOT A SECOND WINDOW. The original design (docs/FLUTTER_REWRITE_PLAN.md,
// Phase 6) opened each dialog in its own top-level window through
// `desktop_multi_window`. That costs, on every first click:
//
//   create a native window -> boot a second Flutter engine -> start a Dart
//   isolate -> decode the arguments -> register `taskpin/dialog_spec`
//
// which is several hundred milliseconds to seconds of "nothing happened" after
// the click, and it left the dialog with the OS title bar (inconsistent with
// the manager window's self-drawn one). The window also could not be sized or
// styled because the `taskpin/window` native half is not compiled into the
// Windows build.
//
// An overlay has none of those costs: the widgets already exist, so the panel
// appears on the next frame, the title bar is ours, and the dialog inherits the
// manager window's theme.
//
// TRADE-OFF, stated plainly: an inline dialog cannot be dragged outside the
// manager window, and it does not float over other applications. A script that
// wants a desktop HUD (a clock pinned over everything) needs a real window —
// that is the Phase C work, and `DialogWindowHost` remains in the tree for it.
//
// The C layer allows ONE dialog at a time (`lib/script_dialog.c:59-62` raises
// the existing one instead of stacking). This host keeps that rule: a second
// open replaces the spec in the existing panel.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dialog_spec.dart';

/// The open inline dialog, or null when none is shown.
///
/// A `Notifier` rather than a `StateProvider` so the open/close calls are
/// named operations that a test can read without knowing the state shape.
@immutable
class InlineDialogState {
  const InlineDialogState({this.spec, this.luaPath = '', this.argsJson = ''});

  /// The dialog to render, or null when the panel is closed.
  final DialogSpec? spec;

  /// The script that produced [spec], so the panel can re-run it on its
  /// `@refresh` interval. Empty disables refresh.
  final String luaPath;

  /// The `args` JSON to bind when re-running [luaPath].
  final String argsJson;

  bool get isOpen => spec != null;

  InlineDialogState copyWith({
    DialogSpec? spec,
    String? luaPath,
    String? argsJson,
    bool clear = false,
  }) =>
      clear
          ? const InlineDialogState()
          : InlineDialogState(
              spec: spec ?? this.spec,
              luaPath: luaPath ?? this.luaPath,
              argsJson: argsJson ?? this.argsJson,
            );
}

class InlineDialogNotifier extends Notifier<InlineDialogState> {
  @override
  InlineDialogState build() => const InlineDialogState();

  /// Show [spec], replacing whatever is already open.
  void open(DialogSpec spec, {String luaPath = '', String argsJson = ''}) {
    state = InlineDialogState(
      spec: spec,
      luaPath: luaPath,
      argsJson: argsJson,
    );
  }

  void close() {
    if (!state.isOpen) return;
    state = const InlineDialogState();
  }

  /// Replace the spec without touching the script identity.
  ///
  /// Used by the refresh loop: a re-run produced a new spec for the same
  /// script, and the panel must not lose the ability to refresh again.
  void replaceSpec(DialogSpec spec) {
    if (!state.isOpen) return;
    state = state.copyWith(spec: spec);
  }
}

final NotifierProvider<InlineDialogNotifier, InlineDialogState>
    inlineDialogProvider =
    NotifierProvider<InlineDialogNotifier, InlineDialogState>(
      InlineDialogNotifier.new,
    );
