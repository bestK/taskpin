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
          // Flexible, not Expanded: the placeholders and the tray are fixed
          // widths, so at a narrow window the plugin row must be allowed to
          // shrink below its natural size instead of overflowing the strip.
          Flexible(
            child: Row(
              // LEFT-aligned, directly after the drag placeholders.
              //
              // The placeholders at the start of the strip are the pinned
              // items' drag handles, and they already mark where the row
              // begins. Pushing the segments to the right edge (an earlier
              // attempt at "match the real taskbar, which sits next to the
              // tray") left a lone plugin floating against the clock with a
              // wide black gap before it — it read as a missing segment, not
              // as a taskbar. The tray stays pinned at the far right below,
              // so the strip still has both ends anchored.
              mainAxisAlignment: MainAxisAlignment.start,
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
                  // Flexible with a tight cap: the segment sizes to its
                  // reading up to [kTaskbarSegmentMaxWidth], and may shrink
                  // below that when the row is narrow. A bare ConstrainedBox
                  // was measured at its natural width and overflowed the row
                  // at 560 px windows; a bare Flexible let one segment claim
                  // the whole strip and draw as a full-width black band.
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: kTaskbarSegmentMaxWidth,
                      ),
                      child: _Segment(segment: segments[i]),
                    ),
                  ),
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

/// Widest a single pinned plugin may draw in the preview.
///
/// Real bars are 50–800 wide, but the preview is about arrangement, not
/// resizing, and an unbounded segment swallows the strip. This keeps one
/// plugin looking like a plugin next to the tray.
const double kTaskbarSegmentMaxWidth = 260;

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

    // Each segment gets its own chip so the strip reads as a row of distinct
    // items rather than as one long dark band with text scattered on it. This
    // mirrors the real taskbar, where every pinned item is its own child
    // window with its own edge.
    final Widget body = empty
        ? Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: TpSpacing.s8),
              child: Text(
                segment.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TpTypography.caption.toTextStyle(
                  tabular: true,
                ).copyWith(color: theme.taskbarMuted),
              ),
            ),
          )
        // No `width: double.infinity` here: the segment is already bounded by
        // [kTaskbarSegmentMaxWidth] and by the row's remaining space. An
        // infinite width inside a bounded parent makes the strip fight the
        // constraint and overflow at narrow window sizes.
        : SizedBox(
            height: _kSegmentInnerHeight,
            child: TpBarPreviewStrip(
              content: segment.content,
              height: _kSegmentInnerHeight,
              background: theme.taskbarChip,
              showStateStrip: false,
            ),
          );

    return TpFocusRing(
      radius: TpRadius.control,
      onTap: segment.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: TpSpacing.s6),
        // The segment is 44 high inside the 56 bar; clipping keeps a long
        // reading from painting outside its own segment.
        child: ClipRRect(
          borderRadius: TpRadius.control,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.taskbarChip,
              borderRadius: TpRadius.control,
              border: Border.all(color: theme.taskbarChipBorder),
            ),
            child: body,
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
    // A fixed 20 px line. Without it the row collapsed to the 16 px text
    // height, and the 8 px gap below left the two captions visually touching
    // the strip — which reads as clipped text rather than as a caption.
    return SizedBox(
      height: 20,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              l10n.projectsPreviewTitle(count),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TpTypography.caption
                  .toTextStyle(tabular: true)
                  .copyWith(color: theme.text.secondary),
            ),
          ),
          const SizedBox(width: TpSpacing.s16),
          Text(
            l10n.projectsDragHint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TpTypography.caption.toTextStyle().copyWith(
                  color: theme.text.tertiary,
                ),
          ),
        ],
      ),
    );
  }
}
