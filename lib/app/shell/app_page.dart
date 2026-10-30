// Page frame: the stage opening, then content, scrollable.
//
// The page opens the way a product page does: a large tight headline, one
// secondary line under it, actions on the right, then the content. Margin is
// 24 below 1000 px of content width and 36 above; content is at most 1000 px
// wide.
//
// A page that wants the spotlight behind its opening passes [stage] (a
// [TpStageBackdrop]); it is painted under the header only, so the list below
// reads on the plain ground.

import 'package:flutter/material.dart';
import 'package:taskpin_design/taskpin_design.dart';

/// Content width above which the larger page margin applies.
const double kPageWideBreakpoint = 1000;

/// Maximum width of page content.
const double kPageMaxContentWidth = 1000;

/// A routed page: stage header and a scrollable column of [children].
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    this.title,
    this.breadcrumb,
    this.subtitle,
    this.headerTrailing = const <Widget>[],
    this.actions = const <Widget>[],
    this.children = const <Widget>[],
    this.stage,
    this.hero,
  }) : assert(title != null || breadcrumb != null || hero != null);

  /// Page title. Ignored when [breadcrumb] is set.
  final String? title;

  /// Path shown instead of the title on a second-level page.
  final List<TpBreadcrumbSegment>? breadcrumb;

  /// Widget under the title, e.g. the project status line.
  final Widget? subtitle;

  /// Controls placed on the title row, left of [actions]. The project page
  /// puts its search field here.
  final List<Widget> headerTrailing;

  /// Header actions, right-aligned.
  final List<Widget> actions;

  /// Page content under the header.
  final List<Widget> children;

  /// Backdrop painted behind the header, e.g. [TpStageBackdrop].
  final Widget? stage;

  /// Replaces the headline with a widget of the page's own, e.g. the one
  /// sentence that opens the project stage. [title] is then unused.
  final Widget? hero;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double margin =
            constraints.maxWidth < kPageWideBreakpoint ? 24 : 36;
        final Widget header = _StageHeader(
          title: title,
          breadcrumb: breadcrumb,
          subtitle: subtitle,
          hero: hero,
          actions: <Widget>[...headerTrailing, ...actions],
        );

        // The content column is CENTRED, not left-anchored. On a wide window a
        // 1000 px column pinned to the left edge leaves a dead field on the
        // right and puts the header's actions at the column's edge rather than
        // the page's — the search field and the primary button floated in the
        // middle of the window. Centring is what the stage world does: one
        // column, one centre line, whatever the window width.
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(margin, 0, margin, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (stage == null)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: kPageMaxContentWidth,
                      ),
                      child: header,
                    ),
                  ),
                )
              else
                Stack(
                  children: <Widget>[
                    // The stage spans the window; the words sit on the
                    // content column.
                    Positioned.fill(child: stage!),
                    Padding(
                      padding: const EdgeInsets.only(top: 56, bottom: 8),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: kPageMaxContentWidth,
                          ),
                          child: header,
                        ),
                      ),
                    ),
                  ],
                ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: kPageMaxContentWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The opening: headline (or breadcrumb), one line under it, actions right.
class _StageHeader extends StatelessWidget {
  const _StageHeader({
    required this.title,
    required this.breadcrumb,
    required this.subtitle,
    required this.hero,
    required this.actions,
  });

  final String? title;
  final List<TpBreadcrumbSegment>? breadcrumb;
  final Widget? subtitle;
  final Widget? hero;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final List<TpBreadcrumbSegment>? crumbs = breadcrumb;

    final Widget heading = hero ??
        (crumbs != null && crumbs.isNotEmpty
        ? TpBreadcrumb(segments: crumbs, role: TpTypography.headline)
        : Text(
            title ?? '',
            style: TpTypography.headline
                .toTextStyle()
                .copyWith(color: theme.text.primary),
          ));

    final Widget headingBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        heading,
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: TpSpacing.s12),
          subtitle!,
        ],
      ],
    );

    final Widget actionRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < actions.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: TpSpacing.s12),
          actions[i],
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Actions ride above the headline, right-aligned, the way a product
          // page puts its search and its one button in the bar above the
          // statement. Keeping them out of the headline's row is what lets the
          // statement run the full content width on one line.
          if (actions.isNotEmpty) ...<Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[Flexible(child: actionRow)],
            ),
            const SizedBox(height: TpSpacing.s24),
          ],
          headingBlock,
        ],
      ),
    );
  }
}
