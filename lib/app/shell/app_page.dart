// Page frame: title row, then content, scrollable.
//
// Page margin is 24 below 1000 px of content width and 36 above. Content is at
// most 1000 px wide and starts at the left edge of the content area.
// See docs/VISUAL_SPEC.md section 3.1 and 5.2.

import 'package:flutter/material.dart';
import 'package:taskpin_design/taskpin_design.dart';

/// Content width above which the larger page margin applies.
const double kPageWideBreakpoint = 1000;

/// Maximum width of page content.
const double kPageMaxContentWidth = 1000;

/// A routed page: header and a scrollable column of [children].
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    this.title,
    this.breadcrumb,
    this.subtitle,
    this.headerTrailing = const <Widget>[],
    this.actions = const <Widget>[],
    this.children = const <Widget>[],
  }) : assert(title != null || breadcrumb != null);

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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double margin =
            constraints.maxWidth < kPageWideBreakpoint ? 24 : 36;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(margin, 24, margin, 24),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kPageMaxContentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TpPageHeader(
                    title: title,
                    breadcrumb: breadcrumb,
                    subtitle: subtitle,
                    actions: <Widget>[...headerTrailing, ...actions],
                    padding: const EdgeInsets.only(bottom: 24),
                  ),
                  ...children,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
