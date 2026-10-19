// Feedback and action components: Button, Toast, InfoBar, ConfirmDialog,
// EmptyState, ErrorState, Skeleton, ProgressBar, Tooltip.

import 'dart:async' show Timer;

import 'package:flutter/material.dart';

import '../theme/taskpin_theme.dart';
import '../tokens/motion.dart';
import '../tokens/radius.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import '../util/focus.dart';
import 'ui.dart';

/// Button variants (docs/VISUAL_SPEC.md §6.2).
enum TpButtonVariant {
  /// The one action a screen is for. Accent fill, no border.
  primary,

  /// Default button. Control fill with a 1 px outline.
  standard,

  /// Borderless. Accent text, subtle hover.
  text,

  /// Square icon button, 32 x 32. Icon is required. Use [TpButton.label] as
  /// the tooltip.
  icon,
}

/// A button. Keyboard-activatable (Enter/Space) and focus-ringed.
class TpButton extends StatefulWidget {
  const TpButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = TpButtonVariant.standard,
    this.size = TpControlSize.control,
    this.expand = false,
    this.enabled = true,
  });

  /// Visible text. For [TpButtonVariant.icon] it is the tooltip and the
  /// accessible name.
  final String label;

  final VoidCallback? onPressed;

  /// Glyph shown before the label, or the only content for the icon variant.
  final IconData? icon;

  final TpButtonVariant variant;

  /// Height. Defaults to 32.
  final double size;

  /// Stretch to fill the available width.
  final bool expand;

  /// Explicit enable flag. The button is interactive only when this is true
  /// and [onPressed] is non-null.
  final bool enabled;

  @override
  State<TpButton> createState() => _TpButtonState();
}

class _TpButtonState extends State<TpButton> {
  bool _hovered = false;
  bool _pressed = false;

  void _setHovered(bool v) {
    if (v != _hovered) {
      setState(() => _hovered = v);
    }
  }

  void _setPressed(bool v) {
    if (v != _pressed) {
      setState(() => _pressed = v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final bool interactive = widget.enabled && widget.onPressed != null;
    final _TpButtonSkin skin = _TpButtonSkin.resolve(
      theme,
      widget.variant,
      interactive: interactive,
      hovered: _hovered,
      pressed: _pressed,
    );
    final bool isIcon = widget.variant == TpButtonVariant.icon;
    final IconData? glyph = widget.icon;

    final List<Widget> parts = <Widget>[
      if (glyph != null)
        Icon(
          glyph,
          size: 16,
          color: skin.foreground,
        ),
      if (!isIcon && glyph != null) const SizedBox(width: TpSpacing.s8),
      if (!isIcon)
        Flexible(
          child: Text(
            widget.label,
            style: TpTypography.body
                .toTextStyle()
                .copyWith(color: skin.foreground),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
    ];

    final Widget content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: parts,
    );

    final double height = isIcon ? TpControlSize.iconButton : widget.size;

    Widget body = AnimatedContainer(
      duration: TpMotion.resolve(context, TpMotion.fast),
      curve: TpMotion.linear,
      height: height,
      width: isIcon ? TpControlSize.iconButton : null,
      padding: isIcon
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: TpSpacing.s12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: skin.background,
        borderRadius: TpRadius.control,
        border: skin.border,
      ),
      child: content,
    );

    if (widget.expand) {
      body = SizedBox(width: double.infinity, child: body);
    }

    body = MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) {
        _setHovered(false);
        _setPressed(false);
      },
      child: Listener(
        onPointerDown: interactive ? (_) => _setPressed(true) : null,
        onPointerUp: interactive ? (_) => _setPressed(false) : null,
        onPointerCancel: interactive ? (_) => _setPressed(false) : null,
        child: TpFocusRing(
          radius: TpRadius.control,
          enabled: interactive,
          onTap: interactive ? widget.onPressed : null,
          child: body,
        ),
      ),
    );

    if (isIcon) {
      return Tooltip(message: widget.label, child: body);
    }
    return body;
  }
}

/// Colours and border for one button state.
class _TpButtonSkin {
  const _TpButtonSkin({
    required this.background,
    required this.foreground,
    required this.border,
    this.bottomEdge,
  });

  final Color background;
  final Color foreground;
  final Border? border;

  /// Colour of a band along the bottom edge, or null.
  final Color? bottomEdge;

  static _TpButtonSkin resolve(
    TaskPinTheme t,
    TpButtonVariant variant, {
    required bool interactive,
    required bool hovered,
    required bool pressed,
  }) {
    if (!interactive) {
      switch (variant) {
        case TpButtonVariant.primary:
          return _TpButtonSkin(
            background: t.control.fill,
            foreground: t.text.disabled,
            border: null,
          );
        case TpButtonVariant.standard:
          return _TpButtonSkin(
            background: t.control.fill,
            foreground: t.text.disabled,
            border: Border.all(color: t.control.stroke),
          );
        case TpButtonVariant.text:
          return _TpButtonSkin(
            background: Colors.transparent,
            foreground: t.text.disabled,
            border: null,
          );
        case TpButtonVariant.icon:
          return _TpButtonSkin(
            background: Colors.transparent,
            foreground: t.text.disabled,
            border: null,
          );
      }
    }
    switch (variant) {
      case TpButtonVariant.primary:
        return _TpButtonSkin(
          background: hovered ? t.accent.fillHover : t.accent.fill,
          foreground: t.accent.onFill,
          border: null,
        );
      case TpButtonVariant.standard:
        final Color bg = pressed
            ? t.control.fillPressed
            : (hovered ? t.control.fillHover : t.control.fill);
        return _TpButtonSkin(
          background: bg,
          foreground: t.text.primary,
          border: Border.all(color: t.control.stroke),
          bottomEdge: t.control.strokeBottom,
        );
      case TpButtonVariant.text:
        return _TpButtonSkin(
          background: pressed
              ? t.subtle.pressed
              : (hovered ? t.subtle.hover : Colors.transparent),
          foreground: t.accent.text,
          border: null,
        );
      case TpButtonVariant.icon:
        return _TpButtonSkin(
          background: pressed
              ? t.subtle.pressed
              : (hovered ? t.subtle.hover : Colors.transparent),
          foreground: t.text.primary,
          border: null,
        );
    }
  }
}

/// A transient message.
class TpToast {
  const TpToast({
    required this.message,
    this.kind = TpStateKind.info,
    this.duration = const Duration(seconds: 4),
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final TpStateKind kind;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
}

/// Hosts toasts above [child].
class TpToastHost extends StatefulWidget {
  const TpToastHost({super.key, required this.child, this.maxVisible = 3});

  final Widget child;
  final int maxVisible;

  /// Shows [toast] in the nearest host. Returns false when there is none.
  static bool show(BuildContext context, TpToast toast) {
    final _TpToastHostState? host =
        context.findAncestorStateOfType<_TpToastHostState>();
    if (host == null) {
      return false;
    }
    host.push(toast);
    return true;
  }

  @override
  State<TpToastHost> createState() => _TpToastHostState();
}

class _TpToastHostState extends State<TpToastHost> {
  final List<_TpToastEntry> _entries = <_TpToastEntry>[];
  int _nextId = 0;

  void push(TpToast toast) {
    final int id = _nextId++;
    setState(() {
      _entries.add(_TpToastEntry(id: id, toast: toast));
      while (_entries.length > widget.maxVisible) {
        _entries.removeAt(0);
      }
    });
    Timer(toast.duration, () => _dismiss(id));
  }

  void _dismiss(int id) {
    if (!mounted) {
      return;
    }
    setState(() => _entries.removeWhere((_TpToastEntry e) => e.id == id));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        widget.child,
        Positioned(
          right: TpSpacing.s16,
          bottom: TpSpacing.s16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (final _TpToastEntry e in _entries)
                Padding(
                  padding: const EdgeInsets.only(top: TpSpacing.s8),
                  child: TpToastCard(
                    toast: e.toast,
                    onDismiss: () => _dismiss(e.id),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TpToastEntry {
  const _TpToastEntry({required this.id, required this.toast});

  final int id;
  final TpToast toast;
}

/// One toast card.
class TpToastCard extends StatelessWidget {
  const TpToastCard({
    super.key,
    required this.toast,
    this.onDismiss,
  });

  final TpToast toast;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final Color color = theme.stateColor(toast.kind);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 420),
      child: TpSurface(
        level: TpSurfaceLevel.flyout,
        padding: const EdgeInsets.all(TpSpacing.s16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Icon(_glyphFor(toast.kind), size: 16, color: color),
            const SizedBox(width: TpSpacing.s12),
            Flexible(
              child: TpText(
                toast.message,
                style: TpTypography.body,
                maxLines: 3,
              ),
            ),
            if (toast.actionLabel != null) ...<Widget>[
              const SizedBox(width: TpSpacing.s8),
              TpButton(
                label: toast.actionLabel!,
                variant: TpButtonVariant.text,
                onPressed: toast.onAction,
              ),
            ],
            if (onDismiss != null) ...<Widget>[
              const SizedBox(width: TpSpacing.s4),
              TpButton(
                label: '关闭',
                icon: TpIcons.close,
                variant: TpButtonVariant.icon,
                onPressed: onDismiss,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Status glyph for [kind].
IconData _glyphFor(TpStateKind kind) {
  switch (kind) {
    case TpStateKind.success:
      return TpIcons.success;
    case TpStateKind.caution:
      return TpIcons.warning;
    case TpStateKind.critical:
      return TpIcons.danger;
    case TpStateKind.neutral:
    case TpStateKind.info:
      return TpIcons.info;
  }
}

/// An in-page message (docs/VISUAL_SPEC.md §6.8).
///
/// Background is the status colour at 12 % opacity, radius 4, minimum height
/// 48. Shows a status glyph, an optional title and the message.
class TpInfoBar extends StatelessWidget {
  const TpInfoBar({
    super.key,
    required this.message,
    this.kind = TpStateKind.info,
    this.title,
    this.actions = const <Widget>[],
    this.onDismiss,
  });

  final String message;
  final TpStateKind kind;
  final String? title;
  final List<Widget> actions;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final Color glyphColor = theme.stateColor(kind);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(
        horizontal: TpSpacing.s16,
        vertical: TpSpacing.s12,
      ),
      decoration: BoxDecoration(
        color: theme.stateSubtle(kind),
        borderRadius: TpRadius.control,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(_glyphFor(kind), size: 16, color: glyphColor),
          ),
          const SizedBox(width: TpSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (title != null)
                  TpText(title!, style: TpTypography.bodyStrong),
                TpText(message, style: TpTypography.body),
              ],
            ),
          ),
          for (final Widget a in actions) ...<Widget>[
            const SizedBox(width: TpSpacing.s8),
            a,
          ],
          if (onDismiss != null) ...<Widget>[
            const SizedBox(width: TpSpacing.s8),
            TpButton(
              label: '关闭',
              icon: TpIcons.close,
              variant: TpButtonVariant.icon,
              onPressed: onDismiss,
            ),
          ],
        ],
      ),
    );
  }
}

/// A modal confirmation (docs/VISUAL_SPEC.md §6.6).
///
/// 448 wide, radius 8, flyout background, 24 padding. The footer is
/// `bg.cardSecondary` with the confirm button first, then cancel, right
/// aligned.
class TpConfirmDialog extends StatelessWidget {
  const TpConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.detail,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.destructive = false,
  });

  final String title;
  final String message;
  final String? detail;
  final String confirmLabel;
  final String cancelLabel;

  /// Renders the confirm button as standard instead of primary.
  final bool destructive;

  /// Opens the dialog. Resolves to true when confirmed, false when cancelled,
  /// null when dismissed.
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String message,
    String? detail,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
  }) =>
      showDialog<bool>(
        context: context,
        barrierColor: TaskPinTheme.of(context).smoke,
        builder: (BuildContext ctx) => TpConfirmDialog(
          title: title,
          message: message,
          detail: detail,
          confirmLabel: confirmLabel,
          cancelLabel: cancelLabel,
          destructive: destructive,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(TpSpacing.s24),
      shape: const RoundedRectangleBorder(borderRadius: TpRadius.overlay),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: 448,
        decoration: BoxDecoration(
          color: theme.bg.flyout,
          borderRadius: TpRadius.overlay,
          border: Border.all(color: theme.stroke.card),
          boxShadow: theme.shadowDialog,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(TpSpacing.s24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TpText(title, style: TpTypography.subtitle),
                  const SizedBox(height: TpSpacing.s12),
                  TpText(message, style: TpTypography.body),
                  if (detail != null) ...<Widget>[
                    const SizedBox(height: TpSpacing.s8),
                    TpText(
                      detail!,
                      style: TpTypography.caption,
                      role: TpTextRole.secondary,
                    ),
                  ],
                ],
              ),
            ),
            Container(
              color: theme.bg.cardSecondary,
              padding: const EdgeInsets.symmetric(
                horizontal: TpSpacing.s24,
                vertical: TpSpacing.s16,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TpButton(
                    label: confirmLabel,
                    variant: destructive
                        ? TpButtonVariant.standard
                        : TpButtonVariant.primary,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                  const SizedBox(width: TpSpacing.buttonGap),
                  TpButton(
                    label: cancelLabel,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centred empty state: icon, one line of body text, one primary action.
class TpEmptyState extends StatelessWidget {
  const TpEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.action,
  });

  final String title;
  final String? message;

  /// Defaults to the signals glyph.
  final IconData? icon;

  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon ?? TpIcons.signals, size: 48, color: theme.text.tertiary),
          const SizedBox(height: TpSpacing.s12),
          TpText(title, style: TpTypography.body, textAlign: TextAlign.center),
          if (message != null) ...<Widget>[
            const SizedBox(height: TpSpacing.s4),
            TpText(
              message!,
              style: TpTypography.body,
              role: TpTextRole.secondary,
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null) ...<Widget>[
            const SizedBox(height: TpSpacing.s16),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Error state: critical icon, message, optional detail and a retry action.
class TpErrorState extends StatelessWidget {
  const TpErrorState({
    super.key,
    required this.title,
    this.message,
    this.detail,
    this.onRetry,
    this.retryLabel = 'Retry',
  });

  final String title;
  final String? message;
  final String? detail;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(TpIcons.danger, size: 48, color: theme.status.critical),
          const SizedBox(height: TpSpacing.s12),
          TpText(title, style: TpTypography.bodyStrong),
          if (message != null) ...<Widget>[
            const SizedBox(height: TpSpacing.s4),
            TpText(
              message!,
              style: TpTypography.body,
              role: TpTextRole.secondary,
              textAlign: TextAlign.center,
            ),
          ],
          if (detail != null) ...<Widget>[
            const SizedBox(height: TpSpacing.s8),
            SelectableText(
              detail!,
              style: TpTypography.mono.toTextStyle().copyWith(
                    color: theme.text.tertiary,
                  ),
            ),
          ],
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: TpSpacing.s16),
            TpButton(label: retryLabel, onPressed: onRetry),
          ],
        ],
      ),
    );
  }
}

/// A static placeholder block for content that is loading.
class TpSkeleton extends StatelessWidget {
  const TpSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius,
    this.shimmer = false,
  });

  final double? width;
  final double height;
  final BorderRadius? radius;

  /// Accepted and ignored. Placeholders do not animate.
  final bool shimmer;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.control.fill,
          borderRadius: radius ?? TpRadius.control,
        ),
      ),
    );
  }
}

/// A column of [TpSkeleton] lines.
class TpSkeletonLines extends StatelessWidget {
  const TpSkeletonLines({
    super.key,
    this.count = 3,
    this.lineHeight = 12,
    this.spacing = TpSpacing.s8,
  });

  final int count;
  final double lineHeight;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < count; i++) ...<Widget>[
          if (i > 0) SizedBox(height: spacing),
          TpSkeleton(
            width: i == count - 1 ? 160 : null,
            height: lineHeight,
          ),
        ],
      ],
    );
  }
}

/// A thin progress bar. [value] null with [indeterminate] set animates a
/// sliding segment; reduced motion shows a static segment.
class TpProgressBar extends StatelessWidget {
  const TpProgressBar({
    super.key,
    required this.value,
    this.height = 4,
    this.color,
    this.indeterminate = false,
  });

  /// 0.0 to 1.0, or null.
  final double? value;
  final double height;
  final Color? color;
  const TpProgressBar.indeterminate({super.key, this.height = 4, this.color})
      : value = null,
        indeterminate = true;

  final bool indeterminate;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final Color fill = color ?? theme.accent.fill;
    final bool showIndeterminate = indeterminate || value == null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: ColoredBox(
          color: theme.control.fill,
          child: showIndeterminate
              ? _TpIndeterminateFill(color: fill)
              : Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: value!.clamp(0.0, 1.0),
                    child: ColoredBox(color: fill),
                  ),
                ),
        ),
      ),
    );
  }
}

class _TpIndeterminateFill extends StatefulWidget {
  const _TpIndeterminateFill({required this.color});

  final Color color;

  @override
  State<_TpIndeterminateFill> createState() => _TpIndeterminateFillState();
}

class _TpIndeterminateFillState extends State<_TpIndeterminateFill>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduced = TpMotion.reduced(context);
    if (reduced) {
      _controller?.dispose();
      _controller = null;
    } else if (_controller == null) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1400),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AnimationController? c = _controller;
    if (c == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: 0.3,
          child: ColoredBox(color: widget.color),
        ),
      );
    }
    return AnimatedBuilder(
      animation: c,
      builder: (BuildContext context, Widget? _) {
        final double start = -0.3 + (1.3 * c.value);
        return Align(
          alignment: Alignment(start * 2 - 1, 0),
          child: FractionallySizedBox(
            widthFactor: 0.3,
            child: ColoredBox(color: widget.color),
          ),
        );
      },
    );
  }
}

/// A tooltip with the 500 ms show delay (docs/VISUAL_SPEC.md §6.7).
class TpTooltip extends StatelessWidget {
  const TpTooltip({
    super.key,
    required this.message,
    required this.child,
    this.shortcut,
  });

  final String message;
  final Widget child;
  final String? shortcut;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    return Tooltip(
      message: shortcut == null ? message : '$message  $shortcut',
      waitDuration: const Duration(milliseconds: 500),
      padding: const EdgeInsets.symmetric(
        horizontal: TpSpacing.s8,
        vertical: TpSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: theme.bg.flyout,
        borderRadius: TpRadius.control,
        border: Border.all(color: theme.stroke.card),
        boxShadow: theme.shadowFlyout,
      ),
      textStyle: TpTypography.caption.toTextStyle().copyWith(
            color: theme.text.primary,
          ),
      child: child,
    );
  }
}
