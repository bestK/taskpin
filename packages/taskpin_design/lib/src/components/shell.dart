// Shell components: AppShell, NavRail, PageHeader, Toolbar, SplitPane.
//
// These define the frame the management window lives in. The layout is a
// fixed navigation rail plus a content column (docs/VISUAL_SPEC.md §5.1).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show LogicalKeyboardKey, SystemMouseCursors;

import '../theme/taskpin_theme.dart';
import '../tokens/radius.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import '../util/focus.dart';
import 'ui.dart';

/// One destination in the [TpNavRail].
class TpNavDestination {
  const TpNavDestination({
    required this.label,
    required this.icon,
    required this.route,
    this.badgeCount,
    this.badgeCritical = false,
  });

  final String label;
  final IconData icon;

  /// Route path this destination navigates to. The shell does not own the
  /// router; it just reports the path.
  final String route;

  /// Optional count shown at the trailing edge. Null or 0 hides it.
  final int? badgeCount;

  /// When true the badge is a `status/critical` pill with white text, used for
  /// the error count on the log destination.
  final bool badgeCritical;
}

/// The navigation rail.
///
/// No background and no divider; it sits on the window ground. Items are 40
/// high, radius 8, 16 px icon and body text, 12 px horizontal padding.
/// Selection is a `nav/active` fill with white text and icon; hover is
/// `subtle/hover`. There is no indicator bar.
///
/// [destinations] are listed from the top. [footerDestinations] are pinned to
/// the bottom above the collapse toggle (for Settings).
///
/// Sizing: in a bounded height the destination list takes the slack and the
/// footer stays at the bottom. In an unbounded height the list shrink-wraps.
class TpNavRail extends StatelessWidget {
  const TpNavRail({
    super.key,
    required this.destinations,
    required this.selectedRoute,
    required this.onSelect,
    this.footerDestinations = const <TpNavDestination>[],
    this.collapsed = false,
    this.onToggleCollapsed,
    this.header,
    this.footer,
  });

  final List<TpNavDestination> destinations;

  /// Destinations pinned to the bottom of the rail.
  final List<TpNavDestination> footerDestinations;

  final String selectedRoute;
  final ValueChanged<String> onSelect;
  final bool collapsed;
  final VoidCallback? onToggleCollapsed;

  /// Optional block at the top.
  final Widget? header;

  /// Optional widget pinned at the bottom, below [footerDestinations].
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);

    final double width = collapsed
        ? TpControlSize.navCompactWidth
        : TpControlSize.navWidth;

    final double listInset = collapsed ? TpSpacing.s4 : TpSpacing.s12;

    return SizedBox(
      width: width,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool boundedHeight = constraints.hasBoundedHeight;

          final Widget list = ListView(
            shrinkWrap: !boundedHeight,
            physics:
                boundedHeight ? null : const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: listInset),
            children: <Widget>[
              for (final TpNavDestination d in destinations)
                _TpNavItem(
                  destination: d,
                  selected: d.route == selectedRoute,
                  collapsed: collapsed,
                  onTap: () => onSelect(d.route),
                ),
            ],
          );

          final Widget footerList = Padding(
            padding: EdgeInsets.symmetric(horizontal: listInset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final TpNavDestination d in footerDestinations)
                  _TpNavItem(
                    destination: d,
                    selected: d.route == selectedRoute,
                    collapsed: collapsed,
                    onTap: () => onSelect(d.route),
                  ),
              ],
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: boundedHeight ? MainAxisSize.max : MainAxisSize.min,
            children: <Widget>[
              if (header != null)
                Padding(
                  padding:
                      EdgeInsets.all(collapsed ? TpSpacing.s4 : TpSpacing.s12),
                  child: header,
                ),
              if (boundedHeight) Expanded(child: list) else list,
              if (footerDestinations.isNotEmpty) footerList,
              if (footer != null) footer!,
              if (onToggleCollapsed != null)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: listInset),
                  child: TpFocusRing(
                    radius: TpRadius.control,
                    onTap: onToggleCollapsed,
                    child: SizedBox(
                      height: TpControlSize.navItem - 4,
                      child: Center(
                        child: Icon(
                          collapsed ? TpIcons.expand : TpIcons.collapse,
                          size: 16,
                          color: theme.text.tertiary,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: TpSpacing.s8),
            ],
          );
        },
      ),
    );
  }
}

class _TpNavItem extends StatelessWidget {
  const _TpNavItem({
    required this.destination,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final TpNavDestination destination;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final int? count = destination.badgeCount;
    final bool showBadge = !collapsed && count != null && count > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TpSpacing.s2),
      child: TpHoverBuilder(
        builder: (BuildContext context, bool hovered) {
          final Color bg = selected
              ? theme.navActive
              : (hovered ? theme.subtle.hover : Colors.transparent);
          final Color fg = selected ? theme.accent.onFill : theme.text.secondary;

          return TpFocusRing(
            radius: TpRadius.card,
            onTap: onTap,
            child: SizedBox(
              height: TpControlSize.navItem,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: TpRadius.card,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: TpSpacing.s12,
                  ),
                  child: Row(
                    mainAxisAlignment: collapsed
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    children: <Widget>[
                      Icon(destination.icon, size: 16, color: fg),
                      if (!collapsed) ...<Widget>[
                        const SizedBox(width: TpSpacing.s12),
                        Expanded(
                          child: Text(
                            destination.label,
                            style: TpTypography.body
                                .toTextStyle()
                                .copyWith(color: fg),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (showBadge)
                          _TpNavBadge(
                            count: count,
                            critical: destination.badgeCritical,
                            selected: selected,
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TpNavBadge extends StatelessWidget {
  const _TpNavBadge({
    required this.count,
    required this.critical,
    required this.selected,
  });

  final int count;
  final bool critical;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    if (critical) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: TpSpacing.s6,
          vertical: TpSpacing.s2,
        ),
        decoration: BoxDecoration(
          color: theme.status.critical,
          borderRadius: TpRadius.chip,
        ),
        child: Text(
          '$count',
          style: TpTypography.caption.toTextStyle(tabular: true).copyWith(
                color: theme.accent.onFill,
              ),
        ),
      );
    }
    return Text(
      '$count',
      style: TpTypography.caption.toTextStyle(tabular: true).copyWith(
            color: selected ? theme.accent.onFill : theme.text.tertiary,
          ),
    );
  }
}

/// The management window frame: rail on the left, content on the right.
class TpAppShell extends StatelessWidget {
  const TpAppShell({
    super.key,
    required this.rail,
    required this.child,
    this.overlay,
  });

  /// The [TpNavRail].
  final Widget rail;

  /// The routed page.
  final Widget child;

  /// Anything that floats above everything: toast host, dialogs.
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final Widget shell = ColoredBox(
      color: theme.bg.window,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          rail,
          Expanded(child: child),
        ],
      ),
    );

    if (overlay == null) {
      return shell;
    }
    return Stack(
      children: <Widget>[
        shell,
        overlay!,
      ],
    );
  }
}

/// One segment of a breadcrumb. [onTap] is null on the last segment.
class TpBreadcrumbSegment {
  const TpBreadcrumbSegment({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;
}

/// Title-sized breadcrumb, for example "Projects > Rich". Earlier segments
/// are tappable text.secondary. The last segment is text.primary.
class TpBreadcrumb extends StatelessWidget {
  const TpBreadcrumb({super.key, required this.segments});

  final List<TpBreadcrumbSegment> segments;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final List<Widget> parts = <Widget>[];
    for (int i = 0; i < segments.length; i++) {
      final TpBreadcrumbSegment s = segments[i];
      final bool last = i == segments.length - 1;
      if (i > 0) {
        parts.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: TpSpacing.s8),
          child: Text(
            '›',
            style: TpTypography.title
                .toTextStyle()
                .copyWith(color: theme.text.secondary),
          ),
        ));
      }
      final TextStyle style = TpTypography.title.toTextStyle().copyWith(
            color: last ? theme.text.primary : theme.text.secondary,
          );
      if (last || s.onTap == null) {
        parts.add(Text(s.label, style: style));
      } else {
        parts.add(TpFocusRing(
          radius: TpRadius.control,
          onTap: s.onTap,
          child: Text(s.label, style: style),
        ));
      }
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: parts,
    );
  }
}

/// Page title row: title (or breadcrumb) on the left, actions on the right.
class TpPageHeader extends StatelessWidget {
  const TpPageHeader({
    super.key,
    this.title,
    this.breadcrumb,
    this.description,
    this.subtitle,
    this.actions = const <Widget>[],
    this.padding = const EdgeInsets.fromLTRB(
      TpSpacing.s24,
      TpSpacing.s20,
      TpSpacing.s24,
      TpSpacing.s16,
    ),
  }) : assert(title != null || breadcrumb != null);

  /// Page title (title role). Ignored when [breadcrumb] is set.
  final String? title;

  /// Path segments, shown instead of [title].
  final List<TpBreadcrumbSegment>? breadcrumb;

  /// One line under the title.
  final String? description;

  /// A widget under the title, for content the description cannot express
  /// (the status line with coloured dots).
  final Widget? subtitle;

  /// Right-aligned actions, 8 apart.
  final List<Widget> actions;

  /// Space around the header row.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final String? descriptionText = description;
    final List<TpBreadcrumbSegment>? crumbs = breadcrumb;

    final Widget heading = crumbs != null && crumbs.isNotEmpty
        ? TpBreadcrumb(segments: crumbs)
        : Text(
            title ?? '',
            style: TpTypography.title
                .toTextStyle()
                .copyWith(color: theme.text.primary),
          );

    final Widget headingBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        heading,
        if (descriptionText != null) ...<Widget>[
          const SizedBox(height: TpSpacing.s4),
          Text(
            descriptionText,
            style: TpTypography.body
                .toTextStyle()
                .copyWith(color: theme.text.secondary),
          ),
        ],
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: TpSpacing.s8),
          subtitle!,
        ],
      ],
    );

    final Widget actionRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < actions.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: TpSpacing.buttonGap),
          actions[i],
        ],
      ],
    );

    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Narrow: the actions move under the title instead of squeezing it.
          if (actions.isNotEmpty && constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                headingBlock,
                const SizedBox(height: TpSpacing.s16),
                actionRow,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(child: headingBlock),
              if (actions.isNotEmpty) ...<Widget>[
                const SizedBox(width: TpSpacing.s16),
                actionRow,
              ],
            ],
          );
        },
      ),
    );
  }
}

/// A horizontal toolbar: leading content, a flexible gap, trailing actions.
class TpToolbar extends StatelessWidget {
  const TpToolbar({
    super.key,
    this.leading = const <Widget>[],
    this.trailing = const <Widget>[],
    this.height = TpControlSize.titleBar,
  });

  final List<Widget> leading;
  final List<Widget> trailing;
  final double height;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: TpSpacing.s16),
      decoration: BoxDecoration(
        color: theme.bg.window,
        border: Border(bottom: BorderSide(color: theme.stroke.divider)),
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < leading.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: TpSpacing.s8),
            leading[i],
          ],
          const Spacer(),
          for (int i = 0; i < trailing.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: TpSpacing.s8),
            trailing[i],
          ],
        ],
      ),
    );
  }
}

/// A two-pane split: a fixed-width master and a flexible detail.
///
/// Draggable, and keyboard-operable: arrow keys nudge the divider. A resize
/// affordance that only works with a mouse is exactly the kind of thing the
/// focus work is meant to eliminate.
class TpSplitPane extends StatefulWidget {
  const TpSplitPane({
    super.key,
    required this.master,
    required this.detail,
    this.initialMasterWidth = 320,
    this.minMasterWidth = 240,
    this.maxMasterWidth = 560,
    this.masterWidth,
    this.onMasterWidthChanged,
  });

  final Widget master;
  final Widget detail;
  final double initialMasterWidth;
  final double minMasterWidth;
  final double maxMasterWidth;

  /// Controlled width. When provided the widget follows it.
  final double? masterWidth;
  final ValueChanged<double>? onMasterWidthChanged;

  @override
  State<TpSplitPane> createState() => _TpSplitPaneState();
}

class _TpSplitPaneState extends State<TpSplitPane> {
  late double _width = widget.masterWidth ?? widget.initialMasterWidth;

  @override
  void didUpdateWidget(TpSplitPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final double? controlled = widget.masterWidth;
    if (controlled != null && controlled != _width) {
      setState(() => _width = controlled);
    }
  }

  void _setWidth(double next) {
    final double clamped =
        next.clamp(widget.minMasterWidth, widget.maxMasterWidth);
    if (clamped == _width) {
      return;
    }
    setState(() => _width = clamped);
    widget.onMasterWidthChanged?.call(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(width: _width, child: widget.master),
        MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: TpFocusRing(
            radius: TpRadius.controlValue == 0
                ? BorderRadius.zero
                : const BorderRadius.all(Radius.circular(TpRadius.controlValue)),
            onActivate: () {},
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (DragUpdateDetails d) =>
                  _setWidth(_width + d.delta.dx),
              child: Actions(
                actions: <Type, Action<Intent>>{
                  // Arrow keys nudge the divider, so the pane is resizable
                  // without a mouse.
                  _TpResizeIntent: CallbackAction<_TpResizeIntent>(
                    onInvoke: (_TpResizeIntent i) {
                      _setWidth(_width + i.delta);
                      return null;
                    },
                  ),
                },
                child: Shortcuts(
                  shortcuts: const <ShortcutActivator, Intent>{
                    SingleActivator(LogicalKeyboardKey.arrowLeft):
                        _TpResizeIntent(-16.0),
                    SingleActivator(LogicalKeyboardKey.arrowRight):
                        _TpResizeIntent(16.0),
                  },
                  child: SizedBox(
                    width: TpSpacing.s6,
                    child: Center(
                      child: Container(
                        width: 1,
                        color: theme.stroke.divider,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(child: widget.detail),
      ],
    );
  }
}

/// Intent for keyboard resizing of [TpSplitPane].
class _TpResizeIntent extends Intent {
  const _TpResizeIntent(this.delta);

  final double delta;
}
