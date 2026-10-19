// Keyboard focus ring (docs/VISUAL_SPEC.md §6.10).
//
// Outer 2 px `focusOuter` line outside the control, inner 1 px `focusInner`
// line inside it. Radius follows the control. Shown only for keyboard focus
// (FocusableActionDetector's focus highlight mode).

import 'package:flutter/material.dart' show Colors;
import 'package:flutter/services.dart' show SystemMouseCursors;
import 'package:flutter/widgets.dart';

import '../theme/taskpin_theme.dart';

/// Outer ring width, outside the control edge.
const double kTpFocusRingWidth = 2;

/// Inner ring width, inside the control edge.
const double kTpFocusInnerWidth = 1;

/// Outer ring decoration. Transparent when [isFocused] is false, with the same
/// geometry, so focus never changes layout.
BoxDecoration tpFocusRingDecoration(
  BuildContext context, {
  required bool isFocused,
  BorderRadius? radius,
}) {
  final TaskPinTheme theme = TaskPinTheme.of(context);
  return BoxDecoration(
    borderRadius: radius,
    border: Border.all(
      color: isFocused ? theme.focusOuter : Colors.transparent,
      width: kTpFocusRingWidth,
      strokeAlign: BorderSide.strokeAlignOutside,
    ),
  );
}

/// Inner ring decoration, drawn inside the control edge.
BoxDecoration tpFocusInnerRingDecoration(
  BuildContext context, {
  required bool isFocused,
  BorderRadius? radius,
}) {
  final TaskPinTheme theme = TaskPinTheme.of(context);
  return BoxDecoration(
    borderRadius: radius,
    border: Border.all(
      color: isFocused ? theme.focusInner : Colors.transparent,
      width: kTpFocusInnerWidth,
      strokeAlign: BorderSide.strokeAlignInside,
    ),
  );
}

/// Wrap any interactive widget to give it a focus ring.
///
/// Uses [FocusableActionDetector] rather than a bare [Focus] so the component
/// also gets hover state and a semantic focus node for free — the same
/// primitive the Material widgets build on.
///
/// [onTap] and [onActivate] are distinct on purpose: [onActivate] fires for
/// Enter/Space (keyboard "click"), [onTap] for pointer. A component that only
/// implements pointer activation is not keyboard-operable, which is the exact
/// gap this package exists to close.
class TpFocusRing extends StatefulWidget {
  const TpFocusRing({
    super.key,
    required this.child,
    this.radius,
    this.onTap,
    this.onActivate,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.mouseCursor = SystemMouseCursors.click,
    this.hitTestBehavior = HitTestBehavior.opaque,
  });

  final Widget child;

  /// Corner radius of the ring. Should match the child's own radius.
  final BorderRadius? radius;

  /// Pointer activation.
  final VoidCallback? onTap;

  /// Keyboard activation (Enter / Space).
  final VoidCallback? onActivate;

  /// When false, the component is skipped in the tab order entirely.
  final bool enabled;

  final bool autofocus;
  final FocusNode? focusNode;
  final MouseCursor mouseCursor;

  /// How the tap region participates in hit testing. Use
  /// [HitTestBehavior.translucent] when the child contains its own controls
  /// (a switch, a button) that must still receive the pointer.
  final HitTestBehavior hitTestBehavior;

  @override
  State<TpFocusRing> createState() => _TpFocusRingState();
}

class _TpFocusRingState extends State<TpFocusRing> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Widget content = Stack(
      // The ring is drawn with `strokeAlignOutside`, i.e. OUTSIDE the child's
      // bounds. A Stack clips by default, which would cut the ring off
      // entirely — so this must stay `Clip.none`.
      clipBehavior: Clip.none,
      children: <Widget>[
        widget.child,
        // Positioned.fill + IgnorePointer keeps the rings purely decorative.
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: tpFocusRingDecoration(
                context,
                isFocused: _focused,
                radius: widget.radius,
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: tpFocusInnerRingDecoration(
                context,
                isFocused: _focused,
                radius: widget.radius,
              ),
            ),
          ),
        ),
      ],
    );

    return FocusableActionDetector(
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      mouseCursor: widget.enabled
          ? widget.mouseCursor
          : SystemMouseCursors.basic,
      onShowFocusHighlight: (bool v) {
        if (v != _focused) {
          setState(() => _focused = v);
        }
      },
      onShowHoverHighlight: (bool v) {
        if (v != _hovered) {
          setState(() => _hovered = v);
        }
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (ActivateIntent _) {
            (widget.onActivate ?? widget.onTap)?.call();
            return null;
          },
        ),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
          onInvoke: (ButtonActivateIntent _) {
            (widget.onActivate ?? widget.onTap)?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: widget.hitTestBehavior,
        onTap: widget.enabled ? widget.onTap : null,
        child: content,
      ),
    );
  }
}

/// Convenience: is the surrounding control currently hovered?
///
/// Exposed as a helper so hover styling is consistent and so components do not
/// each grow their own `MouseRegion`.
class TpHoverBuilder extends StatefulWidget {
  const TpHoverBuilder({super.key, required this.builder});

  /// Called with the current hover state.
  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<TpHoverBuilder> createState() => _TpHoverBuilderState();
}

class _TpHoverBuilderState extends State<TpHoverBuilder> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(context, _hovered),
    );
  }
}
