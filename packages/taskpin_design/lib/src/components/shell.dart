// Shell components: AppShell, NavRail, PageHeader, Toolbar, SplitPane.
//
// These define the frame the management window lives in. The layout is a
// fixed navigation rail plus a content column (docs/VISUAL_SPEC.md §5.1).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show LogicalKeyboardKey, SystemMouseCursors;

import '../theme/taskpin_theme.dart';
import '../tokens/motion.dart';
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

/// The centered top navigation of the stage world.
///
/// [TpControlSize.topNav] high, on the window ground with a hairline under
/// it. Destinations are plain 13 px words centred in the bar, the way a
/// product site names its sections: the selected one is `text.primary` at
/// 600, the rest `text.secondary`, and a 2 px pill under the selected word
/// grows in when the route changes. A count follows a label in the critical
/// colour when [TpNavDestination.badgeCritical] is set; plain counts are not
/// shown here (the page itself says how many projects there are).
///
/// [leading] and [trailing] sit at the two ends and do not push the centre.
class TpTopNav extends StatelessWidget {
  const TpTopNav({
    super.key,
    required this.destinations,
    required this.selectedRoute,
    required this.onSelect,
    this.leading,
    this.trailing,
  });

  final List<TpNavDestination> destinations;
  final String selectedRoute;
  final ValueChanged<String> onSelect;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    return Container(
      height: TpControlSize.topNav,
      foregroundDecoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.stroke.divider)),
      ),
      child: Stack(
        children: <Widget>[
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 0; i < destinations.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: TpSpacing.s8),
                  _TpTopNavItem(
                    destination: destinations[i],
                    selected: destinations[i].route == selectedRoute,
                    onTap: () => onSelect(destinations[i].route),
                  ),
                ],
              ],
            ),
          ),
          if (leading != null)
            Positioned(
              left: TpSpacing.s24,
              top: 0,
              bottom: 0,
              child: Center(child: leading),
            ),
          if (trailing != null)
            Positioned(
              right: TpSpacing.s24,
              top: 0,
              bottom: 0,
              child: Center(child: trailing),
            ),
        ],
      ),
    );
  }
}

class _TpTopNavItem extends StatelessWidget {
  const _TpTopNavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final TpNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final int? count = destination.badgeCount;
    final bool showBadge =
        destination.badgeCritical && count != null && count > 0;

    return TpHoverBuilder(
      builder: (BuildContext context, bool hovered) {
        final Color fg =
            selected || hovered ? theme.text.primary : theme.text.secondary;
        return TpFocusRing(
          radius: TpRadius.chip,
          onTap: onTap,
          child: SizedBox(
            height: TpControlSize.topNav,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: TpSpacing.s12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const SizedBox(height: TpSpacing.s6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        destination.label,
                        style: TpTypography.body.toTextStyle().copyWith(
                              fontSize: 13,
                              color: fg,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                            ),
                      ),
                      if (showBadge) ...<Widget>[
                        const SizedBox(width: TpSpacing.s6),
                        Text(
                          '$count',
                          style: TpTypography.caption
                              .toTextStyle(tabular: true)
                              .copyWith(color: theme.status.critical),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: TpSpacing.s4),
                  AnimatedContainer(
                    duration: TpMotion.resolve(context, TpMotion.slow),
                    curve: TpMotion.resolveCurve(context, TpMotion.stage),
                    width: selected ? 16 : 0,
                    height: 2,
                    decoration: BoxDecoration(
                      color: theme.text.primary,
                      borderRadius: TpRadius.chip,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The stage behind a page's opening: a soft radial glow on the window
/// ground, and a spotlight that drifts slowly from side to side.
///
/// [animate] false holds the spotlight still, and so does reduced motion. The
/// drift repeats forever, so widget tests (which wait for the frame to
/// settle) run with reduced motion or pass false.
class TpStageBackdrop extends StatefulWidget {
  const TpStageBackdrop({super.key, this.animate = true});

  final bool animate;

  @override
  State<TpStageBackdrop> createState() => _TpStageBackdropState();
}

class _TpStageBackdropState extends State<TpStageBackdrop>
    with SingleTickerProviderStateMixin {
  /// One slow sweep from the left edge to the right, then still. A keynote
  /// spotlight settles; it does not loop, and a window that repaints forever
  /// is a window that never lets the frame settle (tests included).
  late final AnimationController _drift =
      AnimationController(vsync: this, duration: TpMotion.drift, value: 0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(TpStageBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final bool run = widget.animate && !TpMotion.reduced(context);
    if (!run) {
      if (_drift.isAnimating) _drift.stop();
      _drift.value = 0.5;
    } else if (_drift.isDismissed) {
      _drift.forward();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, 0.24),
                radius: 0.9,
                colors: <Color>[
                  theme.stageGlow,
                  theme.stageMid,
                  theme.bg.window,
                ],
                stops: const <double>[0, 0.62, 1],
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _drift,
            builder: (BuildContext context, Widget? child) {
              final double t =
                  Curves.easeInOut.transform(_drift.value) * 2 - 1;
              return Align(
                alignment: Alignment(t * 0.16, -1.4),
                child: child,
              );
            },
            child: FractionallySizedBox(
              widthFactor: 0.7,
              heightFactor: 1.3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: <Color>[
                      theme.spotlight,
                      theme.spotlight.withAlpha(0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fades a block in while it rises into place, after [delay].
///
/// One controller covers delay plus travel, with the delay expressed as an
/// [Interval], so there is no timer left pending. [lift] adds the slab's
/// larger rise and a 0.96 to 1 scale. Reduced motion shows the block at rest.
class TpEntrance extends StatefulWidget {
  const TpEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = TpMotion.entrance,
    this.lift = false,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final bool lift;

  @override
  State<TpEntrance> createState() => _TpEntranceState();
}

class _TpEntranceState extends State<TpEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.delay + widget.duration,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(
      widget.delay.inMicroseconds /
          (widget.delay + widget.duration).inMicroseconds,
      1,
      curve: TpMotion.stage,
    ),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (TpMotion.reduced(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double rise = widget.lift ? 40 : 18;
    return AnimatedBuilder(
      animation: _t,
      builder: (BuildContext context, Widget? child) {
        final double v = _t.value;
        Widget out = Transform.translate(
          offset: Offset(0, (1 - v) * rise),
          child: child,
        );
        if (widget.lift) {
          out = Transform.scale(scale: 0.96 + 0.04 * v, child: out);
        }
        return Opacity(opacity: v.clamp(0.0, 1.0), child: out);
      },
      child: widget.child,
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
  const TpBreadcrumb({
    super.key,
    required this.segments,
    this.role = TpTypography.title,
  });

  final List<TpBreadcrumbSegment> segments;

  /// Type role for every segment. Second-level pages pass `headline`.
  final TpTextStyleSpec role;

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
            style: role
                .toTextStyle()
                .copyWith(color: theme.text.tertiary),
          ),
        ));
      }
      final TextStyle style = role.toTextStyle().copyWith(
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
