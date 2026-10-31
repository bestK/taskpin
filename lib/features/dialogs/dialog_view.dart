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
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/services.dart';
import 'package:taskpin_design/taskpin_design.dart';

import 'dialog_controller.dart';
import 'dialog_palette.dart';
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
  const DialogView({
    super.key,
    required this.controller,
    this.onClose,
    this.showScrollbar = false,
    this.onNaturalSize,
    this.hostDrawsSurface = false,
  });

  final DialogController controller;

  /// Called when the user dismisses the dialog. Null disables the close
  /// affordance in the title bar (the native close still works).
  final VoidCallback? onClose;

  /// Draw an always-visible scrollbar on the item area.
  ///
  /// Off for a dialog WINDOW: it grows itself to fit (see
  /// `_reportContentHeight`) and the user can Shift+scroll it bigger, so a
  /// scrollbar there is only noise. The macOS popover can do neither — its
  /// height is capped by the screen — so without a visible thumb its overflow
  /// looked like clipped content.
  final bool showScrollbar;

  /// Receives the dialog's NATURAL size after a layout that may have changed
  /// it: `height` is what the whole dialog (title band + padding + every item)
  /// needs at the current width, whatever height it was actually given;
  /// `width` is the item area's preferred (max intrinsic) width plus padding.
  ///
  /// At most one call per frame, and NOT de-duplicated: the host decides what
  /// counts as a change, because only it knows what it last applied. Null (the
  /// default) skips the measurement entirely.
  final ValueChanged<Size>? onNaturalSize;

  /// The host draws the dialog's frame, so this view must not.
  ///
  /// Set by the macOS popover: the `NSPopover` supplies its own material and
  /// rounded frame, and a flyout fill, a border and a 16 px clip on top of it
  /// read as a black-edged box. Off for a dialog WINDOW, which has no frame of
  /// its own and draws the rounded card.
  final bool hostDrawsSurface;

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

  /// Wraps the item column so its laid-out size can be read back.
  final GlobalKey _bodyKey = GlobalKey();

  /// Whether a natural-size measurement is already queued for this frame.
  bool _naturalQueued = false;

  /// Queue one [DialogView.onNaturalSize] report after the current layout.
  ///
  /// HOW THE NATURAL HEIGHT IS MEASURED. The item column is the child of a
  /// `SingleChildScrollView`, and a scroll view lays its child out with an
  /// UNBOUNDED main axis — so the column's laid-out height already is its
  /// natural height for the current width, whether or not it fits. That is
  /// read straight off its `RenderBox`; nothing is laid out twice and no
  /// intrinsic-height pass is needed (those are unsupported or wrong for
  /// several widgets). Everything around the item area — title band, divider,
  /// borders — is `outer - viewport`, so the chrome is measured rather than
  /// assumed. Unlike `_reportContentHeight`, this does not depend on the
  /// current viewport, so a resize by the host cannot feed back into it.
  void _scheduleNaturalSize() {
    if (widget.onNaturalSize == null || _naturalQueued) return;
    _naturalQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _naturalQueued = false;
      final ValueChanged<Size>? report = widget.onNaturalSize;
      if (!mounted || report == null || !_scroll.hasClients) return;
      final RenderObject? outer = context.findRenderObject();
      final RenderObject? body = _bodyKey.currentContext?.findRenderObject();
      if (outer is! RenderBox || body is! RenderBox) return;
      if (!outer.hasSize || !body.hasSize) return;
      final EdgeInsets padding = _contentPadding(widget.hostDrawsSurface);
      final double chrome =
          outer.size.height - _scroll.position.viewportDimension;
      final double height =
          chrome + body.size.height + padding.vertical;
      double width;
      try {
        width = body.getMaxIntrinsicWidth(double.infinity) +
            padding.horizontal;
      } catch (_) {
        // An item that cannot answer intrinsics: keep the width it has.
        width = outer.size.width;
      }
      report(Size(width, height));
    });
    // From a post-frame callback (a `ScrollMetricsNotification`) the callback
    // above lands in the NEXT frame, which nothing else may schedule.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Shift+scroll resizes the window. Plain scroll is not handled here: the
  /// `SingleChildScrollView` owns the wheel, so handling it again would move the
  /// content twice per event.
  ///
  /// C parity (`lib/script_dialog.c:589-613`): the Shift branch returns before
  /// the scroll branch, so a Shift+scroll never scrolls the content. That is
  /// enforced by [_scrollPhysics], which refuses the wheel while Shift is down.
  ///
  /// Resizing is not gated on `spec.borderless`. The window is always borderless
  /// at the OS level (the panel draws its own chrome; see
  /// `DialogController.applyWindowEffects`), so that flag only means "no title
  /// row". Resizing matters most for normal dialogs, which are the ones with
  /// tables that can overflow.
  void _onPointerSignal(PointerScrollEvent event) {
    if (_shiftDown) {
      applyShiftScrollResize(widget.controller.windowApi, event.scrollDelta.dy);
    }
  }

  /// While Shift is held the content must not scroll, so the wheel goes to the
  /// resize instead. A `Scrollable` ignores pointer-scroll its physics refuses.
  ScrollPhysics? get _scrollPhysics =>
      _shiftDown ? const NeverScrollableScrollPhysics() : null;

  /// The explicit background a popover paints behind its content, or null for
  /// the default, which is transparent so the popover material shows through.
  /// `transparent_bg` wins: it asks the host not to paint a colour at all.
  Color? _hostFill(DialogSpec spec) {
    if (!widget.hostDrawsSurface || spec.transparentBg) {
      return null;
    }
    return parseDialogColor(spec.bgColor);
  }

  @override
  Widget build(BuildContext context) {
    final DialogSpec spec = widget.controller.spec;
    // With an explicit fill, the text follows the fill's brightness instead of
    // the system appearance, so a dark script colour on a light system (or the
    // reverse) stays readable.
    final Color? hostFill = _hostFill(spec);
    final TaskPinTheme theme = hostFill == null
        ? TaskPinTheme.of(context)
        : TaskPinTheme.forBrightness(
            ThemeData.estimateBrightnessForColor(hostFill),
          );

    final Color effectiveSurface;
    if (widget.hostDrawsSurface) {
      effectiveSurface = hostFill ??
          (theme.brightness == Brightness.light
              ? kMacPopoverLightSurface
              : kMacPopoverDarkSurface);
    } else {
      effectiveSurface = hostFill ?? theme.bg.flyout;
    }

    Widget body = spec.items.isEmpty
        ? const SizedBox(height: TpSpacing.s8)
        : Column(
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
    if (widget.onNaturalSize != null) {
      // Re-measure when the items change size on their own (an image that
      // finishes decoding, a refresh that adds rows) without this widget
      // rebuilding.
      body = _SizeWatcher(
        key: _bodyKey,
        onChanged: _scheduleNaturalSize,
        child: body,
      );
    }
    Widget scrollView = SingleChildScrollView(
      controller: _scroll,
      physics: _scrollPhysics,
      padding: _contentPadding(widget.hostDrawsSurface),
      child: body,
    );
    if (widget.showScrollbar) {
      // The automatic desktop scrollbar stays suppressed below; this explicit
      // one shares the view's controller so it tracks the same position.
      // macOS overlay styling uses a thin pill thumb with adequate margin
      // so it never overlaps the table's rightmost column.
      scrollView = ScrollbarTheme(
        data: ScrollbarThemeData(
          thumbVisibility: const WidgetStatePropertyAll<bool>(true),
          thickness: const WidgetStatePropertyAll<double>(5.0),
          radius: const Radius.circular(3.0),
          // A theme token, not an alpha-adjusted text colour: the project
          // forbids overriding a token's alpha (no_token_alpha_override_test).
          thumbColor: WidgetStatePropertyAll<Color>(theme.control.strokeStrong),
          crossAxisMargin: 2.0,
          mainAxisMargin: 4.0,
        ),
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          child: scrollView,
        ),
      );
    }
    Widget scroll = ScrollConfiguration(
      behavior: const _NoScrollbarBehavior(),
      child: scrollView,
    );
    scroll = NotificationListener<ScrollMetricsNotification>(
      onNotification: (ScrollMetricsNotification n) {
        _scheduleMeasure();
        _scheduleNaturalSize();
        return false;
      },
      child: scroll,
    );
    // The notification only fires when the metrics CHANGE, which is not
    // guaranteed on the first frame. Measure after every build instead; the
    // reporter ignores readings that agree with the last request.
    _scheduleMeasure();
    _scheduleNaturalSize();
    Widget content = scroll;

    if (!spec.borderless) {
      final Widget titleWidget = _titleBar(context, theme, spec);
      if (widget.hostDrawsSurface) {
        // Popover mode: let the native macOS vibrant material show through the
        // title band and drop the harsh separator under the title.
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ColoredBox(
              color: hostFill ?? Colors.transparent,
              child: titleWidget,
            ),
            Expanded(child: content),
          ],
        );
      } else {
        // Window mode: keep existing title card and divider intact.
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ColoredBox(
              color: hostFill ?? theme.bg.cardSecondary,
              child: titleWidget,
            ),
            const TpDivider(),
            Expanded(child: content),
          ],
        );
      }
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
    //
    // A popover (`hostDrawsSurface`) has its own frame, so the card is skipped
    // there and the content sits on the popover's material. An explicit script
    // colour (`_hostFill`) fills the content instead. The popover clips the
    // corners, so this fill is square and carries no border.
    if (hostFill != null) {
      content = Theme(
        data: theme.toThemeData(),
        child: ColoredBox(color: hostFill, child: content),
      );
    }
    final Widget surface = spec.transparentBg || widget.hostDrawsSurface
        ? content
        : DecoratedBox(
            decoration: BoxDecoration(
              color: theme.bg.flyout,
              borderRadius: TpRadius.overlay,
              border: Border.all(color: theme.stroke.divider),
            ),
            child: content,
          );

    final Widget framed = widget.hostDrawsSurface
        ? surface
        : ClipRRect(
            borderRadius: TpRadius.overlay,
            child: surface,
          );

    return DialogSurfaceContext(
      hostDrawsSurface: widget.hostDrawsSurface,
      surfaceColor: effectiveSurface,
      child: _DialogShortcuts(
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
                _onPointerSignal(e);
              }
            },
            child: framed,
          ),
        ),
      ),
    );
  }

  /// Compute deliberate vertical rhythm between adjacent dialog items.
  ///
  /// Text-to-text lines stay compact at 4 px, while structured blocks (tables)
  /// and buttons receive 8 px before them. A rule (`hr`) supplies its own 8 px
  /// on each side (`DialogHrItem`), so no gap is added next to one; that keeps
  /// the rule at 8 px whatever item it sits between.
  double _verticalSpacing(DialogItem prev, DialogItem current) {
    if (current.kind == TpDialogItemKind.hr ||
        prev.kind == TpDialogItemKind.hr) {
      return 0;
    }
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
    final EdgeInsets titlePadding = widget.hostDrawsSurface
        ? const EdgeInsets.only(
            left: 14,
            right: 10,
            top: 10,
            bottom: 4,
          )
        : const EdgeInsets.only(
            left: TpSpacing.s12,
            right: TpSpacing.s8,
            top: TpSpacing.s4,
            bottom: TpSpacing.s4,
          );

    final Widget band = Padding(
      padding: titlePadding,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 28),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Text(
                spec.title,
                // Window caption reads with strong weight and primary text emphasis.
                style: TpTypography.bodyStrong.toTextStyle().copyWith(
                  color: theme.text.primary,
                ),
                // One line, so a long title ellipsizes and the close button
                // stays on the same row.
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.onClose != null)
              _DialogCloseButton(
                onClose: widget.onClose!,
                isPopover: widget.hostDrawsSurface,
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

/// Close button affordance with deliberate hover and pressed feedback.
class _DialogCloseButton extends StatefulWidget {
  const _DialogCloseButton({
    required this.onClose,
    required this.isPopover,
  });

  final VoidCallback onClose;
  final bool isPopover;

  @override
  State<_DialogCloseButton> createState() => _DialogCloseButtonState();
}

class _DialogCloseButtonState extends State<_DialogCloseButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final double buttonSize = widget.isPopover ? 24 : 28;
    final double iconSize = widget.isPopover ? 13 : 14;
    final BorderRadius radius = widget.isPopover
        ? BorderRadius.circular(14)
        : TpRadius.control;
    final Color bg = _pressed
        ? theme.subtle.pressed
        : (_hovered ? theme.subtle.hover : Colors.transparent);
    final Color iconColor = (_hovered || _pressed)
        ? theme.text.primary
        : theme.text.secondary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: TpFocusRing(
          radius: radius,
          onTap: widget.onClose,
          onActivate: widget.onClose,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: radius,
            ),
            child: SizedBox(
              width: buttonSize,
              height: buttonSize,
              child: Center(
                child: Icon(
                  TpIcons.close,
                  size: iconSize,
                  color: iconColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dynamic content padding: popover mode supplies slightly more right inset (16px)
/// so the overlay scrollbar never overlaps table content or right-aligned numbers.
EdgeInsets _contentPadding(bool hostDrawsSurface) {
  if (hostDrawsSurface) {
    return const EdgeInsets.only(
      left: 14,
      right: 16,
      top: 6,
      bottom: 12,
    );
  }
  return _kContentPadding;
}

/// Padding around the item area. C: PADDING_X 12, PADDING_Y 8
/// (`lib/script_dialog.c:17-18`). One constant because the natural-size
/// measurement must add back exactly what the scroll view pads.
const EdgeInsets _kContentPadding = EdgeInsets.symmetric(
  horizontal: TpSpacing.s12,
  vertical: TpSpacing.s8,
);

/// Calls [onChanged] whenever its child's laid-out size changes.
///
/// A render object rather than a `LayoutBuilder` / `SizeChangedLayoutNotifier`:
/// it sees the child's actual size in the layout that produced it, and it adds
/// no intrinsic-dimension restrictions to the subtree (a `LayoutBuilder` would
/// make the item column unable to answer the intrinsic-width query the popover
/// uses for its width).
class _SizeWatcher extends SingleChildRenderObjectWidget {
  const _SizeWatcher({super.key, required this.onChanged, super.child});

  final VoidCallback onChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeWatcher(onChanged);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeWatcher renderObject,
  ) {
    renderObject.onChanged = onChanged;
  }
}

class _RenderSizeWatcher extends RenderProxyBox {
  _RenderSizeWatcher(this.onChanged);

  VoidCallback onChanged;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (size != _last) {
      _last = size;
      // Only queues a post-frame callback, which is safe mid-layout.
      onChanged();
    }
  }
}

/// Height of the window-mode caption band, in logical pixels.
///
/// Matches `_titleBar` plus the rule under it: 4 px padding above and below, a
/// 28 px row (the band's minimum height), and the 1 px `TpDivider`. The window's
/// height must include it, or the content would be that much short.
const double _kTitleBarHeight = 37;
