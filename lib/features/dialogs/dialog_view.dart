// The dialog renderer: a `DialogSpec` in, a Flutter widget tree out.
//
// This is the widget the secondary window's isolate builds (see
// `lib/app/windows/dialog_window.dart`). It is also the widget the manager
// window can embed to preview a dialog for real, as opposed to
// `TpDialogSpecPreview`'s schematic rendering.
//
// The three borderless interactions are here rather than in the native halves,
// because two of the three are cheap in Dart and only one needs the OS:
//
//   Shift+drag to move      -> native  (`WM_NCLBUTTONDOWN`/`HTCAPTION`)
//   Shift+scroll to resize  -> native  (`SetWindowPos`, with the C clamps)
//   ESC while hovering      -> DART    (see [_DialogShortcuts])
//
// ESC is Dart because the C implementation is already a polled timer, not a
// message handler: `IDT_DIALOG_ESC` fires every 100 ms and checks
// `GetAsyncKeyState(VK_ESCAPE)` plus `PtInRect` against the cursor
// (`lib/script_dialog.c:397-399, 415-424`). A Flutter `Timer.periodic` at the
// same cadence over `HardwareKeyboard.instance` and a `MouseRegion` hover flag
// is the same mechanism without a native polling loop. The C layer ALSO handles
// `WM_KEYDOWN VK_ESCAPE` (`:628-633`), which Flutter gets for free whenever the
// window has focus — the polled path is what covers the "hovering but not
// focused" case, which is the whole point of the feature.

import 'dart:async';

import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent, kPrimaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:taskpin_design/taskpin_design.dart';

import 'dialog_action.dart';
import 'dialog_controller.dart';
import 'dialog_spec.dart';
import 'items/button_item.dart';
import 'items/hr_item.dart';
import 'items/image_item.dart';
import 'items/table_item.dart';
import 'items/text_item.dart';
import 'items/webview_item.dart';
import 'window_channel.dart';

/// The cadence of the ESC poll. C: `SetTimer(hwnd, IDT_DIALOG_ESC, 100, NULL)`.
const Duration kDialogEscPollInterval = Duration(milliseconds: 100);

/// Renders one [DialogSpec].
class DialogView extends StatefulWidget {
  const DialogView({super.key, required this.controller, this.onClose});

  final DialogController controller;

  /// Called when the user dismisses the dialog. Null disables the close
  /// affordance in the title bar (the native close still works).
  final VoidCallback? onClose;

  @override
  State<DialogView> createState() => _DialogViewState();
}

class _DialogViewState extends State<DialogView> {
  final ScrollController _scroll = ScrollController();
  bool _hovering = false;
  Timer? _escPoll;
  bool _shiftDown = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    // The ESC poll only runs for a borderless dialog, matching the C timer,
    // which is only created under `spec->borderless` (`lib/script_dialog.c:397`).
    _syncEscPoll();
    HardwareKeyboard.instance.addHandler(_onKey);
    _shiftDown =
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftLeft,
        ) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftRight,
        );
  }

  @override
  void didUpdateWidget(DialogView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    _syncEscPoll();
  }

  @override
  void dispose() {
    _escPoll?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    widget.controller.removeListener(_onControllerChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _syncEscPoll() {
    final bool wanted = widget.controller.spec.borderless;
    if (wanted && _escPoll == null) {
      _escPoll = Timer.periodic(kDialogEscPollInterval, (_) => _pollEscape());
    } else if (!wanted && _escPoll != null) {
      _escPoll!.cancel();
      _escPoll = null;
    }
  }

  /// The C poll, reproduced: ESC down AND the pointer inside the window.
  ///
  /// `HardwareKeyboard` reports the real key state rather than a synthesized
  /// one, which is what `GetAsyncKeyState` gives the C timer.
  void _pollEscape() {
    if (!mounted || !_hovering) {
      return;
    }
    if (HardwareKeyboard.instance.logicalKeysPressed.contains(
      LogicalKeyboardKey.escape,
    )) {
      widget.controller.close();
    }
  }

  /// Track Shift for the drag/resize gestures.
  ///
  /// `HardwareKeyboard`'s handler is the reliable place to see a modifier go
  /// down while the pointer is idle over the window, which is exactly the
  /// state a Shift+drag starts from.
  bool _onKey(KeyEvent event) {
    final bool down = event is! KeyUpEvent;
    if (event.logicalKey == LogicalKeyboardKey.shiftLeft ||
        event.logicalKey == LogicalKeyboardKey.shiftRight) {
      if (_shiftDown != down && mounted) {
        setState(() => _shiftDown = down);
      }
    }
    // Enter/Space on the dialog itself do nothing; let descendants handle keys.
    return false;
  }

  /// Shift+scroll resizes, plain scroll scrolls the content.
  ///
  /// C parity (`lib/script_dialog.c:589-613`): the Shift branch returns before
  /// the scroll branch, so a Shift+scroll never scrolls.
  void _onScroll(PointerScrollEvent event) {
    if (!widget.controller.spec.borderless) {
      return;
    }
    if (_shiftDown) {
      applyShiftScrollResize(widget.controller.windowApi, event.scrollDelta.dy);
      return;
    }
    if (!_scroll.hasClients) {
      return;
    }
    // C: `scroll_y -= delta / 2` (`:604`).
    final double next = (_scroll.offset - event.scrollDelta.dy / 2).clamp(
      _scroll.position.minScrollExtent,
      _scroll.position.maxScrollExtent,
    );
    _scroll.jumpTo(next);
  }

  @override
  Widget build(BuildContext context) {
    final DialogSpec spec = widget.controller.spec;
    final TaskPinTheme theme = TaskPinTheme.of(context);

    Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < spec.items.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: TpSpacing.s4),
          _item(context, spec.items[i]),
        ],
      ],
    );

    if (widget.controller.refreshError != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TpInfoBar(
            kind: TpStateKind.critical,
            title: 'Refresh failed',
            message: widget.controller.refreshError!,
          ),
          const SizedBox(height: TpSpacing.s8),
          body,
        ],
      );
    }

    Widget content = Padding(
      // C: PADDING_X 12, PADDING_Y 8 (`lib/script_dialog.c:17-18`).
      padding: const EdgeInsets.symmetric(
        horizontal: TpSpacing.s12,
        vertical: TpSpacing.s8,
      ),
      child: body,
    );

    content = SingleChildScrollView(controller: _scroll, child: content);

    if (!spec.borderless) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _titleBar(context, theme, spec),
          const TpDivider(),
          Expanded(child: content),
        ],
      );
    }

    // The dialog surface. `transparent_bg` means the host composites the window
    // over the desktop, so painting a fill here would defeat it; the C layer
    // has no equivalent and always fills with DIALOG_BG (`:171-173`).
    final Widget surface = spec.transparentBg
        ? content
        : DecoratedBox(
            decoration: BoxDecoration(
              color: spec.borderless ? theme.bg.window : theme.bg.flyout,
              borderRadius: spec.borderless
                  ? BorderRadius.zero
                  : TpRadius.overlay,
              border: spec.borderless
                  ? null
                  : Border.all(color: theme.stroke.divider),
            ),
            child: content,
          );

    return _DialogShortcuts(
      shiftDown: _shiftDown,
      onEscape: widget.controller.close,
      onDragStart: widget.controller.spec.borderless
          ? widget.controller.windowApi.beginDrag
          : null,
      child: MouseRegion(
        onEnter: (_) => _hovering = true,
        onExit: (_) => _hovering = false,
        child: Listener(
          onPointerSignal: (PointerSignalEvent e) {
            if (e is PointerScrollEvent) {
              _onScroll(e);
            }
          },
          child: ClipRRect(
            borderRadius: spec.borderless
                ? BorderRadius.zero
                : TpRadius.overlay,
            child: surface,
          ),
        ),
      ),
    );
  }

  Widget _titleBar(BuildContext context, TaskPinTheme theme, DialogSpec spec) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TpSpacing.s12,
        vertical: TpSpacing.s6,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              spec.title,
              style: TpTypography.body.toTextStyle().copyWith(
                color: theme.text.secondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.onClose != null)
            TpFocusRing(
              radius: TpRadius.control,
              onTap: widget.onClose,
              child: Padding(
                padding: const EdgeInsets.all(TpSpacing.s4),
                child: Icon(
                  TpIcons.close,
                  size: 14,
                  color: theme.text.tertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, DialogItem item) {
    switch (item.kind) {
      case TpDialogItemKind.text:
        return DialogTextItem(
          item: item,
          baseDirectory: widget.controller.baseDirectory,
        );
      case TpDialogItemKind.hr:
        return const DialogHrItem();
      case TpDialogItemKind.table:
        return DialogTableItem(item: item, runner: widget.controller.actions);
      case TpDialogItemKind.image:
        return DialogImageItem(
          item: item,
          baseDirectory: widget.controller.baseDirectory,
        );
      case TpDialogItemKind.button:
        return DialogButtonItem(item: item, runner: widget.controller.actions);
      case TpDialogItemKind.webview:
        return DialogWebviewItem(
          item: item,
          borderless: widget.controller.spec.borderless,
        );
      case TpDialogItemKind.unknown:
        // The C parser `continue`s on an unknown type
        // (`lib/scripting.c:687-691`), so the item vanishes with no
        // explanation. Saying so is strictly more useful than silence, and it
        // is the difference that makes a future engine addition debuggable.
        return TpInfoBar(
          kind: TpStateKind.caution,
          title: 'Unsupported item',
          message:
              'This TaskPin build does not know the dialog item type '
              '"${item.rawType}".',
        );
    }
  }
}

/// The Shift+drag gesture and the ESC shortcut, in one place.
///
/// Shift+drag is a `Listener` rather than a `GestureDetector`: the native
/// `beginDrag` hands the drag to the OS window manager, so the Dart side only
/// has to decide WHEN to hand off, not to track the movement itself. Doing it
/// with a gesture arena would fight the window manager for the pointer.
class _DialogShortcuts extends StatelessWidget {
  const _DialogShortcuts({
    required this.child,
    required this.shiftDown,
    required this.onEscape,
    required this.onDragStart,
  });

  final Widget child;
  final bool shiftDown;
  final Future<void> Function() onEscape;

  /// Null when the dialog is not borderless — the C `WM_NCHITTEST` branch is
  /// gated on `spec->borderless` (`lib/script_dialog.c:621`).
  final Future<void> Function()? onDragStart;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.escape):
            const _CloseDialogIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _CloseDialogIntent: CallbackAction<_CloseDialogIntent>(
            onInvoke: (_) {
              onEscape();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Listener(
            onPointerDown: (PointerDownEvent e) {
              final Future<void> Function()? drag = onDragStart;
              if (drag == null || !shiftDown) {
                return;
              }
              // Primary button only, mirroring `HTCAPTION` on a left press.
              if (e.buttons & kPrimaryMouseButton == 0) {
                return;
              }
              drag();
            },
            child: child,
          ),
        ),
      ),
    );
  }
}

class _CloseDialogIntent extends Intent {
  const _CloseDialogIntent();
}
