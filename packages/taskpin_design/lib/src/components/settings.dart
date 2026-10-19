// Settings components (docs/VISUAL_SPEC.md §6.1).
//
// TpSettingsCard: one setting. TpSettingsExpander: a setting with children
// below it. TpSettingsSection: a bold group header and its cards.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemMouseCursors;

import '../theme/taskpin_theme.dart';
import '../tokens/motion.dart';
import '../tokens/radius.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import '../util/focus.dart';
import 'ui.dart';

/// Below this card width the trailing control moves under the title.
const double kTpSettingsWrapWidth = 476;

/// Layout of one settings row: optional leading icon, title and description,
/// and a trailing control. Used by [TpSettingsCard] and [TpSettingsExpander].
class _TpSettingsRow extends StatelessWidget {
  const _TpSettingsRow({
    required this.title,
    this.description,
    this.icon,
    this.trailing,
    this.trailingAccessory,
  });

  final String title;
  final String? description;
  final IconData? icon;
  final Widget? trailing;

  /// Shown after [trailing] (chevron for clickable cards).
  final Widget? trailingAccessory;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);

    final Widget text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          style: TpTypography.body.toTextStyle().copyWith(
                color: theme.text.primary,
              ),
        ),
        if (description != null)
          Text(
            description!,
            style: TpTypography.caption.toTextStyle().copyWith(
                  color: theme.text.secondary,
                ),
          ),
      ],
    );

    final Widget? leading = icon == null
        ? null
        : Icon(icon, size: 20, color: theme.text.primary);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wrap = constraints.maxWidth < kTpSettingsWrapWidth &&
            trailing != null;

        final Widget head = Row(
          children: <Widget>[
            if (leading != null) ...<Widget>[
              leading,
              const SizedBox(width: TpSpacing.s20),
            ],
            Expanded(child: text),
            if (!wrap && trailing != null) ...<Widget>[
              const SizedBox(width: TpSpacing.s16),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: TpControlSize.settingsTrailingMinWidth,
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: trailing,
                ),
              ),
            ],
            if (trailingAccessory != null) ...<Widget>[
              const SizedBox(width: TpSpacing.s8),
              trailingAccessory!,
            ],
          ],
        );

        if (!wrap) {
          return head;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            head,
            const SizedBox(height: TpSpacing.s12),
            Align(
              alignment: Alignment.centerRight,
              child: trailing,
            ),
          ],
        );
      },
    );
  }
}

/// One setting on a card. Minimum height 68, padding 16, radius 4, 1 px
/// `stroke.card` outline.
///
/// With [onTap] the card is clickable: hover fills `control.fillHover` and a
/// chevron is shown on the right. [trailing] sits right-aligned, minimum 120
/// wide. Below 476 px the trailing control moves under the title.
class TpSettingsCard extends StatelessWidget {
  const TpSettingsCard({
    super.key,
    required this.title,
    this.description,
    this.icon,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? description;

  /// 20 px glyph on the left.
  final IconData? icon;

  /// Right-aligned control.
  final Widget? trailing;

  /// Makes the whole card a button.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final bool clickable = onTap != null;

    return TpHoverBuilder(
      builder: (BuildContext context, bool hovered) {
        final Widget row = _TpSettingsRow(
          title: title,
          description: description,
          icon: icon,
          trailing: trailing,
          trailingAccessory: clickable
              ? Icon(TpIcons.chevronRight, size: 16, color: theme.text.tertiary)
              : null,
        );

        final Widget card = AnimatedContainer(
          duration: TpMotion.resolve(context, TpMotion.fast),
          constraints: const BoxConstraints(
            minHeight: TpControlSize.settingsCardMin,
          ),
          padding: const EdgeInsets.all(TpSpacing.surfacePadding),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: clickable && hovered ? theme.control.fillHover : theme.bg.card,
            borderRadius: TpRadius.control,
            border: Border.all(color: theme.stroke.card),
          ),
          child: row,
        );

        if (!clickable) {
          return card;
        }
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: TpFocusRing(
            radius: TpRadius.control,
            onTap: onTap,
            child: card,
          ),
        );
      },
    );
  }
}

/// A setting with a collapsible list below it.
///
/// The header is a settings card with a chevron that rotates when expanded.
/// [children] sit below the header, indented 48 and separated by a 1 px
/// `stroke.divider`. Expansion animates with [TpMotion.base].
class TpSettingsExpander extends StatefulWidget {
  const TpSettingsExpander({
    super.key,
    required this.title,
    this.description,
    this.icon,
    this.trailing,
    this.children = const <Widget>[],
    this.initiallyExpanded = false,
  });

  final String title;
  final String? description;
  final IconData? icon;
  final Widget? trailing;

  /// Rows shown when expanded.
  final List<Widget> children;

  final bool initiallyExpanded;

  @override
  State<TpSettingsExpander> createState() => _TpSettingsExpanderState();
}

class _TpSettingsExpanderState extends State<TpSettingsExpander> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final Duration duration = TpMotion.resolve(context, TpMotion.base);

    final Widget header = TpHoverBuilder(
      builder: (BuildContext context, bool hovered) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: TpFocusRing(
            radius: TpRadius.control,
            onTap: _toggle,
            onActivate: _toggle,
            child: AnimatedContainer(
              duration: TpMotion.resolve(context, TpMotion.fast),
              constraints: const BoxConstraints(
                minHeight: TpControlSize.settingsCardMin,
              ),
              padding: const EdgeInsets.all(TpSpacing.surfacePadding),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: hovered ? theme.control.fillHover : Colors.transparent,
                borderRadius: _expanded
                    ? const BorderRadius.only(
                        topLeft: Radius.circular(TpRadius.controlValue),
                        topRight: Radius.circular(TpRadius.controlValue),
                      )
                    : TpRadius.control,
              ),
              child: _TpSettingsRow(
                title: widget.title,
                description: widget.description,
                icon: widget.icon,
                trailing: widget.trailing,
                trailingAccessory: AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: duration,
                  curve: TpMotion.standard,
                  child: Icon(
                    TpIcons.chevronDown,
                    size: 16,
                    color: theme.text.tertiary,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < widget.children.length; i++) {
      if (i > 0) {
        rows.add(Padding(
          padding: const EdgeInsets.only(left: 48),
          child: ColoredBox(
            color: theme.stroke.divider,
            child: const SizedBox(height: 1),
          ),
        ));
      }
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(
          48,
          TpSpacing.s12,
          TpSpacing.surfacePadding,
          TpSpacing.s12,
        ),
        child: widget.children[i],
      ));
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.bg.card,
        borderRadius: TpRadius.control,
        border: Border.all(color: theme.stroke.card),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          header,
          AnimatedSize(
            duration: duration,
            curve: TpMotion.standard,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: rows,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// A settings group: a bold header with 30 px above and 6 px below, then the
/// cards with 4 px between them.
class TpSettingsSection extends StatelessWidget {
  const TpSettingsSection({
    super.key,
    required this.title,
    this.children = const <Widget>[],
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: TpSpacing.sectionTop),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: TpSpacing.sectionBottom),
            child: Text(
              title,
              style: TpTypography.bodyStrong.toTextStyle().copyWith(
                    color: theme.text.primary,
                  ),
            ),
          ),
          for (int i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: TpSpacing.settingsCardGap),
            children[i],
          ],
        ],
      ),
    );
  }
}
