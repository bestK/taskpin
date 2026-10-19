// List components (docs/VISUAL_SPEC.md §6.5).
//
// TpListGroup is a card holding rows. TpListRow is one row.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemMouseCursors;

import '../theme/taskpin_theme.dart';
import '../tokens/radius.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import '../util/focus.dart';

/// A card of list rows. Rows are separated by a 1 px `stroke.divider`.
class TpListGroup extends StatelessWidget {
  const TpListGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(ColoredBox(
          color: theme.stroke.divider,
          child: const SizedBox(height: 1),
        ));
      }
      rows.add(children[i]);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.bg.card,
        borderRadius: TpRadius.card,
        border: Border.all(color: theme.stroke.card),
      ),
      child: ClipRRect(
        borderRadius: TpRadius.card,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
  }
}

/// One row in a [TpListGroup].
///
/// Height 40 with a title only, 60 with a [subtitle]. Horizontal padding 16.
/// Hover fills `subtle.hover`, pressed `subtle.pressed`. Keyboard focusable
/// when [onTap] is set.
class TpListRow extends StatefulWidget {
  const TpListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.subtitleColor,
  });

  final String title;

  /// Second line in caption, secondary colour. Single line, truncated.
  final String? subtitle;

  /// Overrides the subtitle colour, for example `status.critical` on error.
  final Color? subtitleColor;

  /// Widget before the title.
  final Widget? leading;

  /// Widget after the title, right-aligned.
  final Widget? trailing;

  final VoidCallback? onTap;

  @override
  State<TpListRow> createState() => _TpListRowState();
}

class _TpListRowState extends State<TpListRow> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (v != _pressed) {
      setState(() => _pressed = v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final bool clickable = widget.onTap != null;
    final String? sub = widget.subtitle;

    final Widget text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          widget.title,
          style: TpTypography.body.toTextStyle().copyWith(
                color: theme.text.primary,
              ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        if (sub != null)
          Text(
            sub,
            style: TpTypography.caption.toTextStyle().copyWith(
                  color: widget.subtitleColor ?? theme.text.secondary,
                ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
      ],
    );

    return TpHoverBuilder(
      builder: (BuildContext context, bool hovered) {
        final Color bg = !clickable
            ? Colors.transparent
            : (_pressed
                ? theme.subtle.pressed
                : (hovered ? theme.subtle.hover : Colors.transparent));

        final Widget row = Container(
          height: sub == null
              ? TpControlSize.listRow
              : TpControlSize.listRowTwoLine,
          padding: const EdgeInsets.symmetric(
            horizontal: TpSpacing.surfacePadding,
          ),
          color: bg,
          child: Row(
            children: <Widget>[
              if (widget.leading != null) ...<Widget>[
                widget.leading!,
                const SizedBox(width: TpSpacing.s12),
              ],
              Expanded(child: text),
              if (widget.trailing != null) ...<Widget>[
                const SizedBox(width: TpSpacing.s12),
                widget.trailing!,
              ],
            ],
          ),
        );

        if (!clickable) {
          return row;
        }
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onExit: (_) => _setPressed(false),
          child: Listener(
            onPointerDown: (_) => _setPressed(true),
            onPointerUp: (_) => _setPressed(false),
            onPointerCancel: (_) => _setPressed(false),
            child: TpFocusRing(
              radius: TpRadius.control,
              onTap: widget.onTap,
              child: row,
            ),
          ),
        );
      },
    );
  }
}
