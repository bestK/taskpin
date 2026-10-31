// The project page: the stage opening, then one hairline list.
//
// The page is built around the product's one signature object. Under a moving
// spotlight the pinned strip is lifted onto a raised slab; below it every
// project is one row, separated by hairlines rather than boxed in cards, so
// the list reads as a table of what is on the taskbar and what is not.
//
// Row order is by urgency: what needs attention first, then what is running,
// then what is stopped. The status text carries the group, so there are no
// group headers.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:taskpin_design/taskpin_design.dart';

import '../../app/l10n.dart';
import '../../app/shell/app_page.dart';
import '../../app/shell/routes.dart';
import '../../core/bar/bar_controller.dart';
import '../../core/bar/bar_source.dart' show resolveScriptPath;
import '../../core/config/config_providers.dart';
import '../../core/config/config_schema.dart';
import 'widgets/item_labels.dart';
import 'widgets/item_status.dart';
import 'widgets/script_open_card.dart';
import 'widgets/taskbar_preview.dart';

/// Width of the search field.
const double kSearchWidth = 320;

/// Height of one project row.
const double kProjectRowHeight = 56;

/// Width of the status column, and of the interval column beside it.
const double kStatusColumnWidth = 240;
const double kIntervalColumnWidth = 120;

/// Below this row width the status text moves under the name.
const double kRowNarrowWidth = 760;

/// The project list page.
class SignalsListPage extends ConsumerStatefulWidget {
  const SignalsListPage({super.key});

  @override
  ConsumerState<SignalsListPage> createState() => _SignalsListPageState();
}

class _SignalsListPageState extends ConsumerState<SignalsListPage> {
  String _query = '';
  final FocusNode _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final TaskPinConfig config = ref.watch(configProvider);
    final Map<int, BarSnapshot> bars =
        ref.watch(barControllerProvider.select((BarState s) => s.bars));
    final String baseDir = _baseDir();
    final List<PinItem> items = config.items;
    final String query = _query.trim().toLowerCase();

    final List<int> visible = <int>[
      for (int i = 0; i < items.length; i++)
        if (query.isEmpty ||
            itemDisplayName(items[i], i, l10n).toLowerCase().contains(query) ||
            itemSourceLabel(items[i]).toLowerCase().contains(query))
          i,
    ];

    final List<int> running = <int>[];
    final List<int> attention = <int>[];
    final List<int> stopped = <int>[];
    for (final int i in visible) {
      final SignalStatus status = _statusOf(items[i], baseDir);
      final String? problem = itemConfigProblem(status, l10n);
      final BarSnapshot? snapshot = bars[i];
      final String? runError = items[i].pinned && snapshot?.error != null
          ? _oneLine(snapshot!.error!)
          : null;
      if (problem != null || (runError != null && runError.isNotEmpty)) {
        attention.add(i);
      } else if (items[i].pinned) {
        running.add(i);
      } else {
        stopped.add(i);
      }
    }

    final List<int> order = <int>[...attention, ...running, ...stopped];
    final int errorCount = attention.length;
    final bool empty = items.isEmpty;
    final List<int> pinned = <int>[
      for (int i = 0; i < items.length; i++)
        if (items[i].pinned) i,
    ];

    final bool isMac = defaultTargetPlatform == TargetPlatform.macOS;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            _searchFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            _searchFocus.requestFocus(),
      },
      child: AppPage(
        title: l10n.navProjects,
        stage: const TpStageBackdrop(),
        // The page's name is already the selected word in the top nav, so the
        // opening says the one thing the page is for: what is on the taskbar
        // and whether anything wants the user.
        hero: empty
            ? null
            : Text(
                _stageSentence(l10n, pinned.length, errorCount),
                style: TpTypography.headline.toTextStyle(tabular: true).copyWith(
                      color: TaskPinTheme.of(context).text.primary,
                    ),
              ),
        headerTrailing: <Widget>[
          if (!empty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kSearchWidth),
              child: SizedBox(
                width: kSearchWidth,
                child: TpTextField(
                  hint: l10n.projectsSearchHint,
                  focusNode: _searchFocus,
                  leading: Icon(TpIcons.search, size: 16),
                  trailing: _ShortcutChip(
                    label: isMac ? '⌘K' : l10n.projectsSearchShortcut,
                  ),
                  onChanged: (String v) => setState(() => _query = v),
                ),
              ),
            ),
        ],
        actions: <Widget>[
          if (!empty)
            TpButton(
              label: l10n.projectsEmptyAction,
              variant: TpButtonVariant.primary,
              onPressed: () => _addItem(context),
            ),
        ],
        children: <Widget>[
          if (empty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 96),
              child: TpEmptyState(
                title: l10n.projectsEmptyTitle,
                action: TpButton(
                  label: l10n.projectsEmptyAction,
                  variant: TpButtonVariant.primary,
                  onPressed: () => _addItem(context),
                ),
              ),
            )
          else ...<Widget>[
            TpEntrance(
              lift: true,
              delay: const Duration(milliseconds: 120),
              duration: const Duration(milliseconds: 1100),
              child: _TaskbarPreviewBlock(
                items: items,
                bars: bars,
                pinned: pinned,
              ),
            ),
            if (errorCount > 0) ...<Widget>[
              const SizedBox(height: TpSpacing.s24),
              _ErrorBanner(
                count: errorCount,
                onRelocate: () => _relocateAll(attention),
              ),
            ],
            const SizedBox(height: TpSpacing.s24),
            if (order.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: TpText(
                    l10n.projectsNoMatch,
                    role: TpTextRole.secondary,
                  ),
                ),
              )
            else
              for (int k = 0; k < order.length; k++)
                TpEntrance(
                  delay: Duration(milliseconds: 260 + k * 60),
                  child: _ProjectRow(
                    key: ValueKey<int>(order[k]),
                    index: order[k],
                    item: items[order[k]],
                    snapshot: bars[order[k]],
                    baseDir: baseDir,
                    kind: attention.contains(order[k])
                        ? _RowKind.attention
                        : running.contains(order[k])
                            ? _RowKind.running
                            : _RowKind.stopped,
                  ),
                ),
          ],
        ],
      ),
    );
  }

  String _baseDir() {
    try {
      return ref.watch(configRepositoryProvider).paths.baseDir;
    } on Object {
      return '';
    }
  }

  SignalStatus _statusOf(PinItem item, String baseDir) =>
      SignalStatus.of(
        item,
        pathExists: (String p) {
          try {
            return File(resolveScriptPath(p, baseDir)).existsSync();
          } on Object {
            return false;
          }
        },
      );

  void _addItem(BuildContext context) {
    final int index = ref.read(configProvider.notifier).addItem(
          PinItem(
            type: PinItemType.lua,
            name: context.l10n.projectNewName,
            intervalMs: 5000,
          ),
        );
    context.go(AppRoutes.signal(index));
  }

  /// Prompts for a new path for each item in [indices], one after another.
  Future<void> _relocateAll(List<int> indices) async {
    for (final int i in indices) {
      if (!mounted) return;
      final String? path = await showRelocateDialog(
        context,
        name: itemDisplayName(ref.read(configProvider).items[i], i, context.l10n),
        current: ref.read(configProvider).items[i].luaPath,
      );
      if (path == null) continue;
      ref.read(configProvider.notifier).editItem(i, (PinItem item) {
        item.luaPath = path;
      });
    }
  }
}

String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// The one sentence that opens the page.
String _stageSentence(AppLocalizations l10n, int pinned, int attention) {
  if (attention > 0) return l10n.projectsStageNeedsYou(pinned, attention);
  if (pinned > 0) return l10n.projectsStageReady(pinned);
  return l10n.projectsStageIdle;
}

/// A small bordered "Ctrl K" chip.
class _ShortcutChip extends StatelessWidget {
  const _ShortcutChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: TpSpacing.s6),
      decoration: BoxDecoration(
        borderRadius: TpRadius.control,
        border: Border.all(color: theme.control.strokeStrong),
      ),
      child: Text(
        label,
        style: TpTypography.caption
            .toTextStyle(tabular: true)
            .copyWith(color: theme.text.tertiary),
      ),
    );
  }
}

/// Caption row plus the slab.
class _TaskbarPreviewBlock extends ConsumerWidget {
  const _TaskbarPreviewBlock({
    required this.items,
    required this.bars,
    required this.pinned,
  });

  final List<PinItem> items;
  final Map<int, BarSnapshot> bars;
  final List<int> pinned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final Map<int, int> positionOf = <int, int>{
      for (int k = 0; k < pinned.length; k++) pinned[k]: k,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: TpSpacing.s12),
          child: TaskbarPreviewHeader(count: pinned.length),
        ),
        TaskbarStageStrip(
          emptyHint: l10n.projectsStripEmpty,
          onReorder: (int from, int to) {
            final int? a = pinned.length > from ? pinned[from] : null;
            final int? b = pinned.length > to ? pinned[to] : null;
            if (a == null || b == null) return;
            ref.read(configProvider.notifier).moveItem(a, b);
          },
          segments: <TaskbarPreviewSegment>[
            for (int i = 0; i < items.length; i++)
              if (items[i].pinned && positionOf.containsKey(i))
                TaskbarPreviewSegment(
                  key: i,
                  index: i,
                  label: itemDisplayName(items[i], i, l10n),
                  content: bars[i]?.content ?? const TpBarContent(),
                  onTap: () => context.go(AppRoutes.signal(i)),
                ),
          ],
        ),
      ],
    );
  }
}

/// Full-width error banner with a relocate action.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.count, required this.onRelocate});

  final int count;
  final VoidCallback onRelocate;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final TaskPinTheme theme = TaskPinTheme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(
        horizontal: TpSpacing.s16,
        vertical: TpSpacing.s12,
      ),
      decoration: BoxDecoration(
        color: theme.bg.card,
        borderRadius: TpRadius.card,
      ),
      child: Row(
        children: <Widget>[
          Icon(TpIcons.danger, size: 16, color: theme.status.critical),
          const SizedBox(width: TpSpacing.s12),
          Expanded(
            child: Text(
              l10n.projectsErrorBanner(count),
              style: TpTypography.body
                  .toTextStyle()
                  .copyWith(color: theme.text.primary),
            ),
          ),
          const SizedBox(width: TpSpacing.s16),
          TpButton(label: l10n.projectsRelocateAll, onPressed: onRelocate),
        ],
      ),
    );
  }
}

/// What a row's status reads as.
enum _RowKind { running, attention, stopped }

/// One project: name and source, status, interval, toggle, more.
///
/// Rows are separated by a hairline above each one; hovering lifts the row's
/// ground instead of outlining it. The columns drop away as the window
/// narrows: status moves under the name below 760, the interval below 560.
class _ProjectRow extends ConsumerStatefulWidget {
  const _ProjectRow({
    super.key,
    required this.index,
    required this.item,
    required this.snapshot,
    required this.baseDir,
    required this.kind,
  });

  final int index;
  final PinItem item;
  final BarSnapshot? snapshot;
  final String baseDir;
  final _RowKind kind;

  @override
  ConsumerState<_ProjectRow> createState() => _ProjectRowState();
}

class _ProjectRowState extends ConsumerState<_ProjectRow> {
  /// The running row's status carries an age, so it re-reads the clock once
  /// per second while it is mounted. Stopped and attention rows do not.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _startTick();
  }

  @override
  void didUpdateWidget(_ProjectRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind ||
        oldWidget.snapshot?.updatedAt != widget.snapshot?.updatedAt) {
      _startTick();
    }
  }

  void _startTick() {
    _tick?.cancel();
    if (widget.kind != _RowKind.running ||
        widget.snapshot?.updatedAt == null) {
      return;
    }
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PinItem item = widget.item;
    final int index = widget.index;
    final _RowKind kind = widget.kind;
    final AppLocalizations l10n = context.l10n;
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final String name = itemDisplayName(item, index, l10n);
    final String source = itemSourceLabel(item);
    final String interval = itemIntervalLabel(item.intervalMs, l10n);
    final String status = _statusText(context, ref, l10n);
    final Color statusColor = switch (kind) {
      _RowKind.running => theme.status.success,
      _RowKind.attention => theme.status.critical,
      _RowKind.stopped => theme.text.tertiary,
    };

    return SizedBox(
      height: kProjectRowHeight,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.25,
        child: TpHoverBuilder(
          builder: (BuildContext context, bool hovered) => DecoratedBox(
            decoration: BoxDecoration(
              color: hovered ? theme.subtle.hover : Colors.transparent,
              border: Border(top: BorderSide(color: theme.stroke.divider)),
            ),
            child: TpFocusRing(
              radius: BorderRadius.zero,
              onTap: () => context.go(AppRoutes.signal(index)),
              hitTestBehavior: HitTestBehavior.translucent,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: TpSpacing.s8),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints c) {
                    final bool wide = c.maxWidth >= kRowNarrowWidth;
                    final bool medium = c.maxWidth >= 560;
                    return Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TpTypography.bodyStrong
                                    .toTextStyle()
                                    .copyWith(color: theme.text.primary),
                              ),
                              if (source.isNotEmpty)
                                Text(
                                  source,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TpTypography.caption.toTextStyle(
                                    tabular: true,
                                  ).copyWith(color: theme.text.tertiary),
                                ),
                            ],
                          ),
                        ),
                        if (wide)
                          SizedBox(
                            width: kStatusColumnWidth,
                            child: _StatusCell(
                              text: status,
                              color: statusColor,
                              filled: kind != _RowKind.stopped,
                            ),
                          )
                        else ...<Widget>[
                          const SizedBox(width: TpSpacing.s12),
                          Flexible(
                            child: _StatusCell(
                              text: status,
                              color: statusColor,
                              filled: kind != _RowKind.stopped,
                              alignEnd: true,
                            ),
                          ),
                        ],
                        if (wide)
                          SizedBox(
                            width: kIntervalColumnWidth,
                            child: Text(
                              interval,
                              maxLines: 1,
                              textAlign: TextAlign.right,
                              style: TpTypography.body
                                  .toTextStyle(tabular: true)
                                  .copyWith(color: theme.text.secondary),
                            ),
                          ),
                        const SizedBox(width: TpSpacing.s16),
                        if (medium && kind == _RowKind.attention) ...<Widget>[
                          TpButton(
                            label: l10n.projectRelocate,
                            onPressed: () => _relocate(context, ref),
                          ),
                          const SizedBox(width: TpSpacing.s8),
                        ],
                        TpSwitch(
                          value: item.pinned,
                          onChanged: (bool _) => ref
                              .read(configProvider.notifier)
                              .togglePinned(index),
                        ),
                        const SizedBox(width: TpSpacing.s4),
                        ProjectMoreButton(index: index, item: item),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// `运行中 · 刚刚` for a running row, the problem for an attention row,
  /// `已停止` for a stopped one.
  String _statusText(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final PinItem item = widget.item;
    final BarSnapshot? snapshot = widget.snapshot;
    final String baseDir = widget.baseDir;
    final _RowKind kind = widget.kind;
    switch (kind) {
      case _RowKind.running:
        final String updated =
            formatRelativeUpdated(snapshot?.updatedAt, l10n);
        return updated.isEmpty
            ? l10n.statusRunning
            : '${l10n.statusRunning} · $updated';
      case _RowKind.stopped:
        return l10n.projectsGroupStopped;
      case _RowKind.attention:
        final SignalStatus status = SignalStatus.of(
          item,
          pathExists: (String p) {
            try {
              return File(resolveScriptPath(p, baseDir)).existsSync();
            } on Object {
              return false;
            }
          },
        );
        final String? problem = itemConfigProblem(status, l10n);
        if (problem != null) return problem;
        final String? error = snapshot?.error;
        return error == null ? l10n.statusError : _oneLine(error);
      }
  }

  Future<void> _relocate(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = context.l10n;
    final String? path = await showRelocateDialog(
      context,
      name: itemDisplayName(widget.item, widget.index, l10n),
      current: widget.item.luaPath,
    );
    if (path == null) return;
    ref.read(configProvider.notifier).editItem(widget.index, (PinItem i) {
      i.luaPath = path;
    });
  }
}

/// A status word with a 6 px dot in front.
class _StatusCell extends StatelessWidget {
  const _StatusCell({
    required this.text,
    required this.color,
    required this.filled,
    this.alignEnd = false,
  });

  final String text;
  final Color color;

  /// Running and error rows carry a filled dot; stopped rows a hollow one.
  final bool filled;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment:
          alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: filled ? color : Colors.transparent,
            shape: BoxShape.circle,
            border: filled ? null : Border.all(color: color),
          ),
        ),
        const SizedBox(width: TpSpacing.s8),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TpTypography.body.toTextStyle(tabular: true).copyWith(
                  color: color,
                ),
          ),
        ),
      ],
    );
  }
}

/// The "more" icon button: duplicate and delete.
class ProjectMoreButton extends ConsumerWidget {
  const ProjectMoreButton({
    super.key,
    required this.index,
    required this.item,
  });

  final int index;
  final PinItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Builder(
      builder: (BuildContext ctx) => TpButton(
        label: context.l10n.projectMore,
        icon: TpIcons.more,
        variant: TpButtonVariant.icon,
        onPressed: () {
          final RenderBox box = ctx.findRenderObject()! as RenderBox;
          _openMenu(
            context,
            ref,
            box.localToGlobal(Offset(0, box.size.height)),
          );
        },
      ),
    );
  }

  Future<void> _openMenu(
    BuildContext context,
    WidgetRef ref,
    Offset position,
  ) async {
    final AppLocalizations l10n = context.l10n;
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final Size screen = MediaQuery.sizeOf(context);

    TextStyle style() =>
        TpTypography.body.toTextStyle().copyWith(color: theme.text.primary);

    PopupMenuItem<_RowAction> entry(
      _RowAction action,
      IconData icon,
      String label,
    ) =>
        PopupMenuItem<_RowAction>(
          value: action,
          height: 32,
          child: Row(
            children: <Widget>[
              Icon(icon, size: 16, color: theme.text.primary),
              const SizedBox(width: TpSpacing.s12),
              Text(label, style: style()),
            ],
          ),
        );

    final _RowAction? picked = await showMenu<_RowAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        screen.width - position.dx,
        screen.height - position.dy,
      ),
      color: theme.bg.flyout,
      surfaceTintColor: Colors.transparent,
      shadowColor: theme.shadowFlyout.first.color,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: TpRadius.card,
        side: BorderSide(color: theme.stroke.card),
      ),
      items: <PopupMenuEntry<_RowAction>>[
        // Only a Lua item has a file to open; a URL item's "source" is a
        // remote address, and there is nothing local to edit.
        if (item.type == PinItemType.lua && item.luaPath.trim().isNotEmpty)
          entry(_RowAction.openScript, TpIcons.code, l10n.detailScriptOpen),
        entry(_RowAction.copy, TpIcons.copy, l10n.projectCopy),
        entry(_RowAction.delete, TpIcons.delete, l10n.mainDelete),
      ],
    );
    if (picked == null || !context.mounted) return;

    switch (picked) {
      case _RowAction.openScript:
        await openScriptWithDefaultApp(context, item.luaPath.trim());
      case _RowAction.copy:
        final PinItem copy = item.copy();
        copy.name = '${itemDisplayName(item, index, l10n)}${l10n.projectCopySuffix}';
        ref.read(configProvider.notifier).addItem(copy);
      case _RowAction.delete:
        await confirmProjectDelete(context, ref, index, item);
    }
  }
}

/// A delete icon button that asks for confirmation.
class ProjectDeleteButton extends ConsumerWidget {
  const ProjectDeleteButton({
    super.key,
    required this.index,
    required this.item,
  });

  final int index;
  final PinItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TpButton(
      label: context.l10n.mainDelete,
      icon: TpIcons.delete,
      variant: TpButtonVariant.icon,
      onPressed: () => confirmProjectDelete(context, ref, index, item),
    );
  }
}

enum _RowAction { openScript, copy, delete }

/// Confirms and deletes the item at [index].
Future<void> confirmProjectDelete(
  BuildContext context,
  WidgetRef ref,
  int index,
  PinItem item,
) async {
  final AppLocalizations l10n = context.l10n;
  final bool? confirmed = await TpConfirmDialog.show(
    context,
    title: l10n.projectDeleteTitle,
    message: l10n.confirmDeleteDesc,
    detail: itemDisplayName(item, index, l10n),
    confirmLabel: l10n.mainDelete,
    cancelLabel: l10n.editCancel,
    destructive: true,
  );
  if (confirmed != true) return;
  ref.read(configProvider.notifier).removeItemAt(index);
}

/// Asks for a new script path. Returns null when cancelled.
Future<String?> showRelocateDialog(
  BuildContext context, {
  required String name,
  required String current,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: TaskPinTheme.of(context).smoke,
    builder: (BuildContext ctx) => _RelocateDialog(name: name, current: current),
  );
}

class _RelocateDialog extends StatefulWidget {
  const _RelocateDialog({required this.name, required this.current});

  final String name;
  final String current;

  @override
  State<_RelocateDialog> createState() => _RelocateDialogState();
}

class _RelocateDialogState extends State<_RelocateDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
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
                  TpText(l10n.projectRelocateTitle,
                      style: TpTypography.subtitle),
                  const SizedBox(height: TpSpacing.s12),
                  TpText(
                    l10n.projectRelocateMessage(widget.name),
                    style: TpTypography.body,
                  ),
                  const SizedBox(height: TpSpacing.s12),
                  TpTextField(controller: _controller),
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
                    label: l10n.editOk,
                    variant: TpButtonVariant.primary,
                    onPressed: () => Navigator.of(context)
                        .pop(_controller.text.trim()),
                  ),
                  const SizedBox(width: TpSpacing.buttonGap),
                  TpButton(
                    label: l10n.editCancel,
                    onPressed: () => Navigator.of(context).pop(),
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

/// `2 秒前更新`, ticking once per second.
String formatRelativeUpdated(DateTime? time, AppLocalizations l10n) {
  if (time == null) return '';
  final Duration age = DateTime.now().difference(time);
  if (age.inSeconds < 1) return l10n.projectUpdatedJustNow;
  if (age.inMinutes < 1) return l10n.projectUpdatedSec(age.inSeconds);
  if (age.inHours < 1) return l10n.projectUpdatedMin(age.inMinutes);
  if (age.inDays < 1) return l10n.projectUpdatedHour(age.inHours);
  return l10n.projectUpdatedDay(age.inDays);
}
