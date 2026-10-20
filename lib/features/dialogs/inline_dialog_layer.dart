// The inline dialog panel: `DialogView` floating over the manager window.
//
// See `inline_dialog_provider.dart` for why this exists instead of a second
// top-level window. This file is the presentation half:
//
//   * a dimmed, click-to-dismiss scrim behind the panel (the C layer's dialog
//     was modal to the bar, not to the desktop, so a scrim is the closest
//     equivalent — and it gives the panel an obvious way out);
//   * the panel itself, positioned from the spec's size, draggable within the
//     window, closable with the panel's X or Escape;
//   * a refresh loop that re-runs the script and swaps the spec in place,
//     exactly as `DialogController.refresh` does for the windowed version.
//
// It deliberately does NOT reuse `DialogController`: that class exists to drive
// a native window (frame, opacity, clickthrough, borderless) and every one of
// those calls is meaningless here. What it shares is `DialogView`, the actual
// renderer, so a spec looks identical in both presentations.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskpin_design/taskpin_design.dart';

import '../../core/engine/engine_provider.dart';
import '../../app/windows/dialog_window.dart' show scriptResultToDialogMap;
import 'package:taskpin_engine/taskpin_engine.dart' show EngineApi, ScriptResult;

import 'dialog_action.dart';
import 'dialog_controller.dart';
import 'dialog_spec.dart';
import 'dialog_view.dart';
import 'inline_dialog_provider.dart';
import 'window_channel.dart';

/// The panel, or nothing when no dialog is open.
///
/// Put this as the last child of the manager window's root `Stack` so it
/// paints above the shell and its toasts.
class InlineDialogLayer extends ConsumerStatefulWidget {
  const InlineDialogLayer({
    super.key,
    this.actions,
  });

  /// Where URL / command actions go. Defaults to the real process runner.
  final DialogActionRunner? actions;

  @override
  ConsumerState<InlineDialogLayer> createState() => _InlineDialogLayerState();
}

class _InlineDialogLayerState extends ConsumerState<InlineDialogLayer> {
  /// Offset of the panel's top-left from the window's centre.
  ///
  /// Offset.zero means centred, which is what the C layer does
  /// (`lib/script_dialog.c:92-94`). Kept relative to the centre so the panel
  /// stays put when the window is resized.
  Offset _drag = Offset.zero;

  /// The spec on screen. Held here rather than read from the provider on every
  /// frame so a refresh can swap it without the provider round-trip.
  DialogSpec? _spec;

  Timer? _refresh;
  bool _refreshing = false;

  /// The spec the drag offset belongs to, so opening a different dialog
  /// re-centres instead of inheriting the previous one's position.
  String? _identity;

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  void _syncRefresh(DialogSpec spec, String luaPath, String argsJson) {
    _refresh?.cancel();
    _refresh = null;
    final int seconds = spec.refreshSeconds;
    if (seconds <= 0 || luaPath.isEmpty) return;
    _refresh = Timer.periodic(
      Duration(seconds: seconds),
      (_) => unawaited(_runRefresh(luaPath, argsJson)),
    );
  }

  Future<void> _runRefresh(String luaPath, String argsJson) async {
    if (_refreshing) return;
    // The engine may not be up yet (it starts asynchronously); a dialog with a
    // refresh interval but no engine simply keeps showing what it has.
    final AsyncValue<EngineApi> engineAsync = ref.read(engineProvider);
    final EngineApi? engine = engineAsync.valueOrNull;
    if (engine == null) return;
    _refreshing = true;
    try {
      final ScriptResult result = await engine.executeFile(
        luaPath,
        argsJson: argsJson.isEmpty ? null : argsJson,
      );
      if (!mounted) return;
      // Same gate as the click path: only a dialog result replaces the panel.
      final DialogSpec? next = DialogSpec.fromScriptResult(
        scriptResultToDialogMap(result),
      );
      if (next == null) return;
      setState(() => _spec = next);
      // The interval can change between runs (a script that slows down when
      // idle), so the timer is rebuilt rather than left on the old cadence.
      _syncRefresh(next, luaPath, argsJson);
    } on Object {
      // A failed re-run keeps the existing content, which is what the C layer
      // does (`lib/script_dialog.c:361-366`).
    } finally {
      _refreshing = false;
    }
  }

  void _close() => ref.read(inlineDialogProvider.notifier).close();

  @override
  Widget build(BuildContext context) {
    final InlineDialogState state = ref.watch(inlineDialogProvider);
    final DialogSpec? incoming = state.spec;

    if (incoming == null) {
      // Keep the last spec so the panel does not flash while closing.
      return const SizedBox.shrink();
    }

    // A NEW dialog (different script, or a fresh open) resets position and
    // takes the incoming spec. A refresh keeps both.
    final String identity = '${state.luaPath}\u0000${incoming.title}';
    if (_spec == null || identity != _identity) {
      _spec = incoming;
      _identity = identity;
      _drag = Offset.zero;
      // Assigning during build is safe here: it only touches fields that the
      // build below already reads, and the timer is not part of the tree.
      _syncRefresh(incoming, state.luaPath, state.argsJson);
    }

    final DialogSpec spec = _spec!;
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final Size viewport = MediaQuery.sizeOf(context);

    // The spec asks for a pixel size; clamp it to the window so a 1200x900
    // dialog on a small window is still usable.
    final double maxW = math.max(240, viewport.width - 48);
    final double maxH = math.max(180, viewport.height - 48);
    final double width = spec.width.clamp(240, maxW).toDouble();
    final double height = spec.height.clamp(180, maxH).toDouble();

    return Stack(
      children: <Widget>[
        // Scrim. Absorbing the tap is the point: it dismisses, and it stops
        // clicks reaching the shell underneath while a dialog is up.
        Positioned.fill(
          child: GestureDetector(
            onTap: _close,
            behavior: HitTestBehavior.opaque,
            // `smoke` already carries its own alpha (0x4D = 30%). Replacing it
            // with `withValues` would both break the "no token alpha override"
            // rule and lose the theme's chosen density.
            child: ColoredBox(color: theme.smoke),
          ),
        ),
        Center(
          child: Transform.translate(
            offset: _drag,
            child: _Panel(
              width: width,
              height: height,
              spec: spec,
              actions: widget.actions,
              onClose: _close,
              onDrag: (Offset delta) => setState(() => _drag += delta),
            ),
          ),
        ),
      ],
    );
  }
}

/// The floating card: a self-drawn title bar plus the shared renderer.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.width,
    required this.height,
    required this.spec,
    required this.actions,
    required this.onClose,
    required this.onDrag,
  });

  final double width;
  final double height;
  final DialogSpec spec;
  final DialogActionRunner? actions;
  final VoidCallback onClose;
  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);

    // `DialogView` draws the dialog's own title bar (the spec's title and its
    // close affordance), so this panel must NOT add a second one — that is how
    // the title ended up duplicated. What the panel adds is the surface the
    // window used to provide: an edge, a shadow, and a drag handle.
    final Widget body = DialogView(
      controller: _InlineController(
        spec: spec,
        actions: actions ?? const ProcessDialogActionRunner(),
      ),
      onClose: onClose,
    );

    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: theme.bg.flyout,
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: 0.45),
        borderRadius: TpRadius.overlay,
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: theme.stroke.card),
            borderRadius: TpRadius.overlay,
          ),
          // Dragging the panel is the inline equivalent of dragging the
          // window. `DialogView`'s own title bar has no drag recognizer (the
          // windowed version relied on the OS caption), so the whole panel
          // takes the pan — buttons and scroll views inside still win the
          // gesture arena, which is what makes "drag from empty space" work
          // without stealing clicks.
          child: GestureDetector(
            onPanUpdate: (DragUpdateDetails d) => onDrag(d.delta),
            child: MouseRegion(
              cursor: SystemMouseCursors.basic,
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}

/// The minimal controller `DialogView` needs.
///
/// `DialogView` takes a `DialogController`, which is built around a native
/// window. Rather than fork the renderer, this subclass supplies the same
/// surface with the window-side operations reduced to no-ops.
class _InlineController extends DialogController {
  _InlineController({
    required DialogSpec spec,
    required DialogActionRunner actions,
  }) : super(
          spec: spec,
          // Every one of these is a native-window call. Inline there is no
          // window: the panel's frame is the widget tree.
          windowApi: const NoopDialogWindowApi(),
          actions: actions,
          // Refresh is driven by the layer's own timer, which owns the
          // script identity and the "replace in place" semantics.
          rerun: null,
        );
}
