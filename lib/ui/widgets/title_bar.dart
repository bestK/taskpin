// The self-drawn window title bar (docs/UI_REFACTOR_PLAN.md §5).
//
// 36 logical px tall, `bg.window`, a 1 px `stroke.divider` bottom edge, the app
// mark and name on the left, and — on Windows only — minimize / maximize-close
// buttons on the right. Dragging and double-click-to-maximize are handled by
// the native window (see below), not by Flutter.
//
// ─────────────────────────────────────────────────────────────────────────────
// WHO DOES WHAT
// ─────────────────────────────────────────────────────────────────────────────
// Windows:
//   * The runner removes the system caption in `WM_NCCALCSIZE`
//     (windows/runner/win32_window.cpp). That gives Flutter the full window
//     height to paint into, which is why this widget can be the first row of
//     the app.
//   * Dragging is native. The Flutter surface is a child HWND, so the child is
//     subclassed to return HTTRANSPARENT over this strip; the parent then
//     answers HTCAPTION and Windows runs the move loop
//     (native/win/taskpin_window_plugin.cpp). Flutter never sees those pointer
//     events — which is also why the double-tap handler below is a fallback
//     rather than the mechanism: the system already toggles maximize on a
//     double-click of a caption.
//   * The three buttons are excluded from that native strip, so Flutter does
//     receive their hover and clicks. They call `taskpin/main_window`.
//
// macOS:
//   * `MainFlutterWindow` hides the title and makes the title bar transparent,
//     and inserts `.fullSizeContentView`; the traffic lights float over the top
//     left. This widget reserves 72 px there and draws no right-side buttons.
//   * There is no native half of the channel, so `isMaximized()` answers null
//     and the button row stays hidden even if the platform check were wrong.
//
// Any other platform: no buttons.
//
// ─────────────────────────────────────────────────────────────────────────────
// GEOMETRY CONTRACT WITH C++
// ─────────────────────────────────────────────────────────────────────────────
// `kTitleBarHeight` and `kTitleBarButtonWidth` are duplicated in
// `native/win/taskpin_window_plugin.h` as `kTaskpinTitleBarHeightDip` and
// `kTaskpinWindowButtonWidthDip`. The native hit test excludes exactly
// `3 * 46` logical px on the right of a 36 px strip; if the Dart layout drifts,
// either the drag region eats the buttons or the buttons leave a dead strip.
// Change both together.
//
// ─────────────────────────────────────────────────────────────────────────────
// COLOUR TOKENS
// ─────────────────────────────────────────────────────────────────────────────
// Nothing here names a `Color(0x...)`. Hover fills use `control.fillHover`; the
// close button's hover red is `status.critical`, the token layer's error red
// (light #B42318, dark #FF8A80), with `accent.onFill` (white) as the glyph. That
// is deliberately not a new literal: the design system has one danger colour,
// and a second hard-coded red would be the beginning of a second palette.

import 'dart:async' show StreamSubscription;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:taskpin_design/taskpin_design.dart';

import '../../core/window/main_window_channel.dart';

/// Height of the title bar, in logical pixels. Mirrors
/// `kTaskpinTitleBarHeightDip`.
const double kTitleBarHeight = 36;

/// Width of one window button, in logical pixels. Mirrors
/// `kTaskpinWindowButtonWidthDip`.
const double kTitleBarButtonWidth = 46;

/// Space reserved on the left for the macOS traffic lights.
const double kMacTrafficLightInset = 72;

/// Caption glyphs from `Segoe Fluent Icons` (`Segoe MDL2 Assets` on Win10).
///
/// `TpIcons` has close but not minimize/maximize/restore, and the design package
/// is outside this change's scope. Local constants keep the glyphs in one place
/// without pretending they are a general icon set.
const IconData _kMinimizeGlyph = IconData(
  0xE921,
  fontFamily: 'Segoe Fluent Icons',
  fontFamilyFallback: <String>['Segoe MDL2 Assets'],
);
const IconData _kMaximizeGlyph = IconData(
  0xE922,
  fontFamily: 'Segoe Fluent Icons',
  fontFamilyFallback: <String>['Segoe MDL2 Assets'],
);
const IconData _kRestoreGlyph = IconData(
  0xE923,
  fontFamily: 'Segoe Fluent Icons',
  fontFamilyFallback: <String>['Segoe MDL2 Assets'],
);

/// The title bar.
///
/// Put it as the first child of the manager window's column, above the app
/// shell. It is not a Material `AppBar`: that would bring its own height,
/// elevation and toolbar semantics, none of which match a Win32 caption.
class TitleBar extends StatefulWidget {
  const TitleBar({
    super.key,
    this.api,
    this.platform,
  });

  /// Window commands. Defaults to the real channel.
  ///
  /// Injectable so a test can drive the maximized state without a message
  /// handler; production code leaves it null.
  final MainWindowApi? api;

  /// Platform override for tests. Defaults to [defaultTargetPlatform].
  final TargetPlatform? platform;

  @override
  State<TitleBar> createState() => _TitleBarState();
}

class _TitleBarState extends State<TitleBar> {
  late final MainWindowApi _api = widget.api ?? MethodChannelMainWindowApi();

  StreamSubscription<bool>? _events;

  /// `null` until the probe answers. The buttons stay hidden meanwhile, so the
  /// bar does not flicker from "no buttons" to "buttons" on every launch.
  bool? _supported;

  bool _maximized = false;

  TargetPlatform get _platform => widget.platform ?? defaultTargetPlatform;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  /// Ask the native side whether it exists, then subscribe.
  ///
  /// A platform without a native half — macOS today, and every widget test
  /// without a mock handler — returns null. In that case the buttons are never
  /// rendered and the event channel is never opened: subscribing to a missing
  /// stream handler is reported through `FlutterError.reportError`, which would
  /// turn a graceful fallback into test noise.
  Future<void> _probe() async {
    final bool? maximized = await _api.isMaximized();
    if (!mounted) return;
    setState(() {
      _supported = maximized != null;
      _maximized = maximized ?? false;
    });
    if (_supported == true) {
      _events = _api.maximizedChanged.listen((bool value) {
        if (!mounted) return;
        setState(() => _maximized = value);
      });
    }
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  Future<void> _toggleMaximize() => _api.toggleMaximize();

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final bool isMac = _platform == TargetPlatform.macOS;
    final bool isWindows = _platform == TargetPlatform.windows;
    final bool showButtons = isWindows && _supported == true;

    return Container(
      height: kTitleBarHeight,
      decoration: BoxDecoration(color: theme.bg.window),
      // The divider is a FOREGROUND decoration, not a `border`. A border is
      // laid out as padding, which would shrink the content box to 35 px and
      // make the 36 px buttons one pixel short. Painting over the bottom row
      // keeps the geometry the design and the native hit test both assume.
      foregroundDecoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.stroke.divider)),
      ),
      child: Row(
        children: <Widget>[
          // The double-click fallback covers the title area only. Wrapping the
          // whole bar — including the buttons — in a GestureDetector with
          // `onDoubleTap` puts a double-tap recognizer in the same gesture
          // arena as every button tap, which delays and can swallow clicks.
          // On Windows the native caption already toggles maximize on a
          // double-click, so this is a belt-and-braces path for platforms
          // where the child-window subclass is not installed.
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap:
                  isWindows && _supported == true ? _toggleMaximize : null,
              child: Row(
                children: <Widget>[
                  SizedBox(width: isMac ? kMacTrafficLightInset : TpSpacing.s16),
                  _AppMark(theme: theme),
                  const SizedBox(width: TpSpacing.s8),
                  Text(
                    'TaskPin',
                    // 13/500: the design type ramp starts at 12 and 14, and
                    // the caption sits between them. Built from `body` so the
                    // family and fallback chain stay in the token layer.
                    style: TpTypography.body.toTextStyle().copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: theme.text.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (showButtons) ..._buttons(theme),
        ],
      ),
    );
  }

  List<Widget> _buttons(TaskPinTheme theme) {
    return <Widget>[
      _WindowButton(
        key: const Key('title_bar_minimize'),
        glyph: _kMinimizeGlyph,
        semanticLabel: 'Minimize',
        theme: theme,
        onPressed: _api.minimize,
      ),
      _WindowButton(
        key: const Key('title_bar_maximize'),
        // Restore when maximized: the glyph is the state, the action is the
        // opposite.
        glyph: _maximized ? _kRestoreGlyph : _kMaximizeGlyph,
        semanticLabel: _maximized ? 'Restore' : 'Maximize',
        theme: theme,
        onPressed: _toggleMaximize,
      ),
      _WindowButton(
        key: const Key('title_bar_close'),
        glyph: TpIcons.close,
        semanticLabel: 'Close',
        theme: theme,
        destructive: true,
        onPressed: _api.close,
      ),
    ];
  }
}

/// The app mark: a 16 px pin glyph on the accent colour.
///
/// A glyph rather than an image because `pubspec.yaml` registers no assets and
/// this change may not add one. The pin is the app's identity in `TpIcons`.
class _AppMark extends StatelessWidget {
  const _AppMark({required this.theme});

  final TaskPinTheme theme;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: Icon(TpIcons.pin, size: 16, color: theme.accent.fill),
    );
  }
}

/// One caption button: 46 x 36, transparent at rest, `control.fillHover` on
/// hover, and — for close — `status.critical` with a white glyph.
class _WindowButton extends StatefulWidget {
  const _WindowButton({
    super.key,
    required this.glyph,
    required this.semanticLabel,
    required this.theme,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData glyph;
  final String semanticLabel;
  final TaskPinTheme theme;
  final Future<void> Function() onPressed;

  /// Close: hover turns the button red.
  final bool destructive;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = widget.theme;
    final Color? fill = _hovered
        ? (widget.destructive ? theme.status.critical : theme.control.fillHover)
        : null;
    final Color glyphColor = _hovered && widget.destructive
        ? theme.accent.onFill
        : theme.text.primary;

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onPressed(),
          child: Container(
            width: kTitleBarButtonWidth,
            height: kTitleBarHeight,
            color: fill,
            alignment: Alignment.center,
            child: Icon(widget.glyph, size: 10, color: glyphColor),
          ),
        ),
      ),
    );
  }
}
