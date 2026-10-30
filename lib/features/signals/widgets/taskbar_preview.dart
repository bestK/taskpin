// The stage strip: the pinned plugins, lifted onto a raised slab.
//
// This is the product's one signature object. The real taskbar is a row of
// small native windows; here it is drawn at reading size on a #111113 slab so
// the user can see what is on it, what it says, and drag the order.
//
// It is chrome inside the manager window, so it reads theme tokens rather
// than the frozen bar palette.

import 'package:flutter/material.dart';
import 'package:taskpin_design/taskpin_design.dart';

import '../../../app/l10n.dart';

/// One segment in the stage strip.
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

/// Height of one segment on the slab.
const double kStageSegmentHeight = 68;

/// Widest a single segment may draw.
const double kTaskbarSegmentMaxWidth = 320;

/// The slab: segments on the left, the tray clock on the right.
class TaskbarStageStrip extends StatelessWidget {
  const TaskbarStageStrip({
    super.key,
    required this.segments,
    required this.onReorder,
    this.emptyHint,
  });

  final List<TaskbarPreviewSegment> segments;

  /// Called with (oldIndex, newIndex) when a segment is dropped on another.
  final void Function(int oldIndex, int newIndex) onReorder;

  /// Shown when nothing is pinned.
  final String? emptyHint;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.stageSlab,
        borderRadius: TpRadius.slab,
        boxShadow: theme.slabShadow,
        border: Border.all(color: theme.stroke.card),
      ),
      child: Row(
        children: <Widget>[
          if (segments.isEmpty)
            Expanded(
              child: SizedBox(
                height: kStageSegmentHeight,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: TpSpacing.s8),
                    child: Text(
                      emptyHint ?? '',
                      style: TpTypography.body.toTextStyle().copyWith(
                            color: theme.taskbarLabel,
                          ),
                    ),
                  ),
                ),
              ),
            )
          else
            Flexible(
              child: Row(
                children: <Widget>[
                  for (int i = 0; i < segments.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(width: 10),
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: kTaskbarSegmentMaxWidth,
                        ),
                        child: _StageSegment(
                          segment: segments[i],
                          position: i,
                          onReorder: onReorder,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(width: TpSpacing.s16),
          const _TrayClock(),
        ],
      ),
    );
  }
}

class _StageSegment extends StatelessWidget {
  const _StageSegment({
    required this.segment,
    required this.position,
    required this.onReorder,
  });

  final TaskbarPreviewSegment segment;
  final int position;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    final Widget chip = _SegmentChip(segment: segment, elevated: false);

    return DragTarget<int>(
      onWillAcceptWithDetails: (DragTargetDetails<int> d) => d.data != position,
      onAcceptWithDetails: (DragTargetDetails<int> d) =>
          onReorder(d.data, position),
      builder: (BuildContext context, List<int?> candidates, _) {
        final bool over = candidates.isNotEmpty;
        return AnimatedOpacity(
          duration: TpMotion.resolve(context, TpMotion.fast),
          opacity: over ? 0.5 : 1,
          child: Draggable<int>(
            data: position,
            feedback: Material(
              color: Colors.transparent,
              child: MouseRegion(
                cursor: SystemMouseCursors.grabbing,
                child: _SegmentChip(segment: segment, elevated: true),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.3, child: chip),
            child: TpFocusRing(
              radius: TpRadius.segment,
              onTap: segment.onTap,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: chip,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One plugin on the slab: a 68 px chip in the segment colour.
class _SegmentChip extends StatelessWidget {
  const _SegmentChip({required this.segment, required this.elevated});

  final TaskbarPreviewSegment segment;

  /// True for the drag feedback: lifted off the slab.
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final bool empty = segment.content.isEmpty;

    return Container(
      height: kStageSegmentHeight,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: theme.stageSegment,
        borderRadius: TpRadius.segment,
        boxShadow: elevated ? theme.shadowDialog : null,
      ),
      alignment: Alignment.centerLeft,
      child: empty
          ? Text(
              segment.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TpTypography.body.toTextStyle().copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.text.tertiary,
                  ),
            )
          // The strip is drawn at the bar's own 56 px height and scaled up
          // through the text scaler, so the reading keeps the bar's exact
          // layout instead of a lookalike built from other type.
          : MediaQuery.withClampedTextScaling(
              minScaleFactor: 1.4,
              maxScaleFactor: 1.4,
              child: SizedBox(
                height: kStageSegmentHeight - 12,
                child: TpBarPreviewStrip(
                  content: segment.content,
                  height: kStageSegmentHeight - 12,
                  background: theme.stageSegment,
                  showStateStrip: false,
                ),
              ),
            ),
    );
  }
}

/// The tray at the right end of the slab: time over date, 18 px.
class _TrayClock extends StatelessWidget {
  const _TrayClock();

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final DateTime now = DateTime.now();
    final String time = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
    final String date = '${now.year}/${now.month.toString().padLeft(2, '0')}/'
        '${now.day.toString().padLeft(2, '0')}';

    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.only(right: TpSpacing.s8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              time,
              style: TpTypography.body.toTextStyle(tabular: true).copyWith(
                    fontSize: 18,
                    color: theme.taskbarMuted,
                  ),
            ),
            Text(
              date,
              style: TpTypography.caption.toTextStyle(tabular: true).copyWith(
                    color: theme.taskbarLabel,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Caption row above the slab: what the strip is, and how to change it.
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
    );
  }
}
