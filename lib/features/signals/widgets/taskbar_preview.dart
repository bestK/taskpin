// Shared widgets for the project page's taskbar preview.
//
// The strip mimics the Windows taskbar: a dark bar with drag placeholders, one
// segment per pinned item, and a decorative tray at the right end. It is drawn
// with theme tokens, not the frozen bar palette, because it is chrome inside
// the manager window rather than a real taskbar item.

import 'package:flutter/material.dart';
import 'package:taskpin_design/taskpin_design.dart';

import '../../../app/l10n.dart';

/// One segment in the taskbar preview.
class TaskbarPreviewSegment {
  const TaskbarPreviewSegment({
    required this.key,
    required this.index,
    required this.label,
    required this.content,
    required this.onTap,
  });

  /// Stable key: the item index.
  final int key;

  /// Item index, used as the reorder payload.
  final int index;

  /// Text shown when there is no output yet.
  final String label;

  /// Latest output. Empty renders [label] instead.
  final TpBarContent content;

  final VoidCallback onTap;
}

/// The full-width taskbar mock.
class TaskbarPreviewBar extends StatelessWidget {
  const TaskbarPreviewBar({
    super.key,
    required this.segments,
    required this.onReorder,
    required this.pinnedCount,
  });

  final List<TaskbarPreviewSegment> segments;

  /// Called with (oldIndex, newIndex) from the placeholder drag.
  final void Function(int oldIndex, int newIndex) onReorder;

  /// Number of pinned items, which is also the number of placeholders.
  final int pinnedCount;

  static const double height = 56;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: TpSpacing.s16),
      decoration: BoxDecoration(
        color: theme.taskbar,
        borderRadius: TpRadius.card,
      ),
      child: Row(
        children: <Widget>[
          _DragPlaceholders(
            count: pinnedCount,
            onReorder: onReorder,
            color: theme.taskbarPlaceholder,
          ),
          const SizedBox(width: TpSpacing.s16),
          Expanded(
            child: Row(
              children: <Widget>[
                for (int i = 0; i < segments.length; i++) ...<Widget>[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: TpSpacing.s12,
                      ),
                      child: SizedBox(
                        width: 1,
                        height: 20,
                        child: ColoredBox(color: theme.taskbarPlaceholder),
                      ),
                    ),
                  Flexible(child: _Segment(segment: segments[i])),
                ],
              ],
            ),
          ),
          const SizedBox(width: TpSpacing.s12),
          const _TrayHint(),
        ],
      ),
    );
  }
}

/// Vertical room inside a segment: the 56 bar minus 6 above and 6 below.
const double _kSegmentInnerHeight = TaskbarPreviewBar.height - 12;

class _DragPlaceholders extends StatelessWidget {
  const _DragPlaceholders({
    required this.count,
    required this.onReorder,
    required this.color,
  });

  final int count;
  final void Function(int oldIndex, int newIndex) onReorder;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < count; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: TpSpacing.s8),
          DragTarget<int>(
            onWillAcceptWithDetails: (DragTargetDetails<int> d) => d.data != i,
            onAcceptWithDetails: (DragTargetDetails<int> d) =>
                onReorder(d.data, i),
            builder: (BuildContext context, _, __) => Draggable<int>(
              data: i,
              feedback: MouseRegion(
                cursor: SystemMouseCursors.grabbing,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: TpRadius.control,
                    border: Border.all(color: color),
                  ),
                ),
              ),
              childWhenDragging: const SizedBox(width: 24, height: 24),
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: TpRadius.control,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.segment});

  final TaskbarPreviewSegment segment;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final bool empty = segment.content.isEmpty;

    return TpFocusRing(
      radius: TpRadius.control,
      onTap: segment.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TpSpacing.s4,
          vertical: TpSpacing.s6,
        ),
        // The segment is 44 high inside the 56 bar; clipping keeps a long
        // reading from painting outside its own segment.
        child: ClipRect(
          child: empty
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    segment.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TpTypography.caption.toTextStyle(
                      tabular: true,
                    ).copyWith(color: theme.taskbarMuted),
                  ),
                )
              : SizedBox(
                  height: _kSegmentInnerHeight,
                  width: double.infinity,
                  child: TpBarPreviewStrip(
                    content: segment.content,
                    height: _kSegmentInnerHeight,
                    background: theme.taskbar,
                    width: double.infinity,
                    showStateStrip: false,
                  ),
                ),
        ),
      ),
    );
  }
}

/// The decorative tray at the right end: network, volume, clock.
class _TrayHint extends StatelessWidget {
  const _TrayHint();

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final DateTime now = DateTime.now();
    final String time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final String date =
        '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';

    return IgnorePointer(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(TpIcons.network, size: 16, color: theme.taskbarMuted),
          const SizedBox(width: TpSpacing.s12),
          Icon(TpIcons.volume, size: 16, color: theme.taskbarMuted),
          const SizedBox(width: TpSpacing.s12),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                time,
                style: TpTypography.caption.toTextStyle(
                  tabular: true,
                ).copyWith(color: theme.taskbarMuted),
              ),
              Text(
                date,
                style: TpTypography.caption.toTextStyle(
                  tabular: true,
                ).copyWith(color: theme.taskbarMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Caption row above the preview: title on the left, hint on the right.
class TaskbarPreviewHeader extends StatelessWidget {
  const TaskbarPreviewHeader({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final TaskPinTheme theme = TaskPinTheme.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            l10n.projectsPreviewTitle(count),
            style: TpTypography.caption
                .toTextStyle(tabular: true)
                .copyWith(color: theme.text.secondary),
          ),
        ),
        Text(
          l10n.projectsDragHint,
          style: TpTypography.caption.toTextStyle().copyWith(
                color: theme.text.tertiary,
              ),
        ),
      ],
    );
  }
}
