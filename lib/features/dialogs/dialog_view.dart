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
  /// The window height we last asked for, so repeated layout passes that
  /// agree do not issue another resize.
  double? _requestedHeight;

  /// Grow the window until the content fits.
  ///
  /// Driven by `ScrollMetricsNotification`, which fires after layout and knows
  /// both the viewport and how far the content extends past it.
  ///
  /// THE LOOP THIS AVOIDS. `maxScrollExtent` is relative to the CURRENT
  /// viewport, so `viewport + maxScrollExtent` is the content height only while
  /// the content overflows. After the window grows, the same content reports
  /// `maxScrollExtent == 0` and a viewport equal to the new window — summing
  /// again would keep growing it. So the request is capped: once a value has
  /// been asked for, a later reading may only make it SMALLER, and only when
  /// the content genuinely fits (extent 0). That converges in one step.
  /// Measure on the next frame, when the scroll position has real metrics.
  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final ScrollPosition p = _scroll.position;
      _reportContentHeight(
        viewportHeight: p.viewportDimension,
        maxScrollExtent: p.maxScrollExtent,
      );
    });
  }

  void _reportContentHeight({
    required double viewportHeight,
    required double maxScrollExtent,
  }) {
    if (!mounted) return;
    final DialogSpec spec = widget.controller.spec;
    final double chrome = spec.borderless ? 0 : _kTitleBarHeight;
    final double floor = spec.height.toDouble();

    final double? previous = _requestedHeight;
    double target;
    if (maxScrollExtent > 0.5) {
      // Overflowing: the content needs the viewport plus the overflow.
      target = viewportHeight + maxScrollExtent + chrome;
    } else if (previous != null) {
      // Fits: the window is already big enough. Keep what we asked for; the
      // viewport merely reports back the height we set.
      target = previous;
    } else {
      target = viewportHeight + chrome;
    }
    if (target < floor) target = floor;

    if (previous != null && (target - previous).abs() < 1.0) return;
    _requestedHeight = target;
    unawaited(widget.controller.windowApi.setHeight(target.ceil()));
  }

  void _onScroll(PointerScrollEvent event) {
    // Shift+scroll resizes. This used to be gated on `spec.borderless`, but
    // the window is now ALWAYS borderless at the OS level (the panel draws its
    // own chrome — see `DialogController.applyWindowEffects`), so the gate was
    // reading the script's flag and disabling resize for every normal dialog.
    // Resizing is useful for those most of all: they are the ones with tables
    // that can overflow.
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
          if (i > 0)
            SizedBox(
              height: _verticalSpacing(spec.items[i - 1], spec.items[i]),
            ),
          // A button sizes to its label, not to the dialog. `stretch` is right
          // for text and tables (they should fill the width) but turns a
          // one-word button into a full-width bar, which reads as a text field.
          if (spec.items[i].kind == TpDialogItemKind.button)
            Align(
              alignment: Alignment.centerLeft,
              child: IntrinsicWidth(child: _item(context, spec.items[i])),
            )
          else
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

    // FIT THE WINDOW TO THE CONTENT.
    //
    // A script's `height` is a guess: `zeeho.lua` says 260 but renders a
    // seven-row table that needs ~380. The scrollbar is suppressed (noise in a
    // small panel), so the overflow was unreachable — the dialog looked
    // clipped with no hint that it could scroll.
    //
    // `ScrollMetricsNotification` is the signal to use: after every layout the
    // scroll position knows `maxScrollExtent`, which is exactly how much taller
    // the content is than the viewport. Content height = viewport + that.
    // Reporting only when the number changes keeps this from looping (a resize
    // changes the viewport, which re-fires the notification).
    Widget scroll = ScrollConfiguration(
      behavior: const _NoScrollbarBehavior(),
      child: SingleChildScrollView(
        controller: _scroll,
        // C: PADDING_X 12, PADDING_Y 8 (`lib/script_dialog.c:17-18`).
        padding: const EdgeInsets.symmetric(
          horizontal: TpSpacing.s12,
          vertical: TpSpacing.s8,
        ),
        child: body,
      ),
    );
    scroll = NotificationListener<ScrollMetricsNotification>(
      onNotification: (ScrollMetricsNotification n) {
        _scheduleMeasure();
        return false;
      },
      child: scroll,
    );
    // The notification only fires when the metrics CHANGE, which is not
    // guaranteed on the first frame. Measure after every build instead; the
    // reporter ignores readings that agree with the last request.
    _scheduleMeasure();
    Widget content = scroll;

    if (!spec.borderless) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // A title band, not bare text on the dialog's own fill: without a
          // distinct surface the caption and the first content row read as one
          // block, and the divider between them looked like a stray line.
          ColoredBox(
            color: theme.bg.cardSecondary,
            child: _titleBar(context, theme, spec),
          ),
          const TpDivider(),
          Expanded(child: content),
        ],
      );
    }

    // The dialog surface. `transparent_bg` means the host composites the window
    // over the desktop, so painting a fill here would defeat it; the C layer
    // has no equivalent and always fills with DIALOG_BG (`:171-173`).
    // The surface is ALWAYS the floating card, whatever `borderless` says.
    //
    // `borderless` used to switch the surface to a square, window-coloured
    // block because it also removed the OS frame; the two were the same thing
    // in the C renderer. They are not any more: `DialogController` always
    // strips the OS frame (the panel draws its own title), so `borderless` now
    // means only "no title row" and the surface stays a rounded flyout.
    final Widget surface = spec.transparentBg
        ? content
        : DecoratedBox(
            decoration: BoxDecoration(
              color: theme.bg.flyout,
              borderRadius: TpRadius.overlay,
              border: Border.all(color: theme.stroke.divider),
            ),
            child: content,
          );

    return _DialogShortcuts(
      shiftDown: _shiftDown,
      onEscape: widget.controller.close,
      // Always enabled: the OS frame is always removed now (see
      // `DialogController.applyWindowEffects`), so Shift+drag is the only way
      // to move the dialog. The script's `borderless` flag no longer gates it,
      // because it no longer gates the frame.
      onDragStart: widget.controller.windowApi.beginDrag,
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
            borderRadius: TpRadius.overlay,
            child: surface,
          ),
        ),
      ),
    );
  }

  /// Compute deliberate vertical rhythm between adjacent dialog items.
  ///
  /// Text-to-text lines stay compact at 4 px, while structured blocks (tables)
  /// and buttons receive 8 px before them.
  double _verticalSpacing(DialogItem prev, DialogItem current) {
    if (current.kind == TpDialogItemKind.table ||
        current.kind == TpDialogItemKind.button) {
      return TpSpacing.s8;
    }
    if (prev.kind == TpDialogItemKind.table ||
        prev.kind == TpDialogItemKind.button) {
      return TpSpacing.s8;
    }
    if (current.kind == TpDialogItemKind.image ||
        current.kind == TpDialogItemKind.webview) {
      return TpSpacing.s8;
    }
    return TpSpacing.s4;
  }

  Widget _titleBar(BuildContext context, TaskPinTheme theme, DialogSpec spec) {
    // The caption band is the drag handle for a NORMAL dialog.
    //
    // The OS frame is always stripped (see
    // `DialogController.applyWindowEffects`), so there is no system caption to
    // drag. Shift+drag is the BORDERLESS gesture and stays that way (it is a
    // feature: a borderless dialog is a bare HUD with no chrome to grab).
    // Without this branch a normal dialog could not be moved at all — it had
    // no caption and did not satisfy the Shift requirement.
    //
    // `beginDrag` hands the drag to the window manager rather than tracking
    // the pointer in Dart, which is what lets the window follow the cursor
    // across the whole desktop instead of only inside its own bounds.
    final Future<void> Function() drag =
        widget.controller.windowApi.beginDrag;
    final Widget band = Padding(
      // Caption band: 36 px total (28 px close target + 4 px top/bottom padding).
      // Left inset aligns with content padding (12 px).
      padding: const EdgeInsets.only(
        left: TpSpacing.s12,
        right: TpSpacing.s8,
        top: TpSpacing.s4,
        bottom: TpSpacing.s4,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 28),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                spec.title,
                // Window caption reads with strong weight and primary text emphasis.
                style: TpTypography.bodyStrong.toTextStyle().copyWith(
                  color: theme.text.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.onClose != null)
              TpHoverBuilder(
                builder: (BuildContext context, bool hovered) {
                  return TpFocusRing(
                    radius: TpRadius.control,
                    onTap: widget.onClose,
                    onActivate: widget.onClose,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color:
                            hovered ? theme.subtle.hover : Colors.transparent,
                        borderRadius: TpRadius.control,
                      ),
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: Center(
                          child: Icon(
                            TpIcons.close,
                            size: 14,
                            color: hovered
                                ? theme.text.primary
                                : theme.text.secondary,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );

    // Borderless dialogs keep the Shift gesture only; a normal dialog is
    // dragged by its caption, which is what every desktop window does.
    if (spec.borderless) {
      return band;
    }
    return GestureDetector(
      onPanStart: (_) => drag(),
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: band,
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

/// Suppresses the desktop scrollbar decoration. Dialogs are compact panels
/// where a drawn scrollbar introduces visual noise.
class _NoScrollbarBehavior extends ScrollBehavior {
  const _NoScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

/// Height of the dialog's own caption band, in logical pixels.
///
/// Matches `_titleBar`: 8 px padding above and below plus a 28 px row. The
/// window's height must include it, or the content would be that much short.
const double _kTitleBarHeight = 44;
