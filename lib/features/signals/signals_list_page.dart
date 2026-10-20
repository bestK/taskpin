// The project list (docs/VISUAL_SPEC.md section 5.3).
//
// Four blocks, fixed order: status line, taskbar preview, error banner, then
// the three status groups. Cards are grouped by state:
//
//   运行中     two-column cards with the switch and latest output
//   需要处理   one-column rows for items whose script is missing
//   已停止     shorter two-column cards with a letter avatar
//
// A card tap opens the detail page. The more menu duplicates or deletes.

import 'dart:async';
import 'dart:io';

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
import 'widgets/avatar.dart';
import 'widgets/item_labels.dart';
import 'widgets/item_status.dart';
import 'widgets/taskbar_preview.dart';

/// Width of the search field.
const double kSearchWidth = 320;

/// Narrowest a project card may be before the grid drops a column.
///
/// The grid used to be "one column below 1000 px, two above", which meant a
/// manager window at its default size (~880 px of content) showed every card
/// full-width: the name sat on the left, the switch and the "…" button were
/// pushed to the far right, and a third of the row was empty. Sizing by the
/// card instead of the page keeps a 1100 px window at two columns and only
/// collapses when a card would genuinely be cramped.
const double kMinCardWidth = 360;

/// Fixed card heights, so every card in a grid is identical whether or not a
/// line has a relative time. Measured at 12/16 and 14/20 type with 16 padding.
///
/// The running card is sized to its content plus a small slack: 32 padding +
/// 24 title row + 4 + 16 meta + 36 mini bar = 112 at 1x, and 122 at the 1.25
/// text-scale clamp. 128 was the previous 148 minus the gap that a `Spacer`
/// used to absorb, which read as an empty band between the meta line and the
/// bar.
const double kRunningCardHeight = 128;
const double kStoppedCardHeight = 88;
const double kAttentionRowHeight = 64;

/// The mini bar inside the running card. The strip fills it; its own 6 + 6
/// padding leaves 24 for content, so a two-line reading shows its first line
/// only.
const double kMiniBarHeight = 36;

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

    final int errorCount = attention.length;
    final bool empty = items.isEmpty;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            _searchFocus.requestFocus(),
      },
      child: AppPage(
        title: l10n.navProjects,
        subtitle: empty
            ? null
            : _StatusLine(
                running: running.length,
                errors: errorCount,
                stopped: stopped.length,
              ),
        headerTrailing: <Widget>[
          if (!empty)
            SizedBox(
              width: kSearchWidth,
              child: TpTextField(
                hint: l10n.projectsSearchHint,
                focusNode: _searchFocus,
                leading: Icon(TpIcons.search, size: 16),
                trailing: _ShortcutChip(label: l10n.projectsSearchShortcut),
                onChanged: (String v) => setState(() => _query = v),
              ),
            ),
        ],
        actions: <Widget>[
          if (!empty)
            TpButton(
              label: l10n.projectsEmptyAction,
              icon: TpIcons.add,
              variant: TpButtonVariant.primary,
              onPressed: () => _addItem(context),
            ),
        ],
        children: <Widget>[
          if (empty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 64),
              child: TpEmptyState(
                title: l10n.projectsEmptyTitle,
                action: TpButton(
                  label: l10n.projectsEmptyAction,
                  icon: TpIcons.add,
                  variant: TpButtonVariant.primary,
                  onPressed: () => _addItem(context),
                ),
              ),
            )
          else ...<Widget>[
            _TaskbarPreviewBlock(
              items: items,
              bars: bars,
              baseDir: baseDir,
            ),
            if (errorCount > 0) ...<Widget>[
              const SizedBox(height: TpSpacing.s16),
              _ErrorBanner(
                count: errorCount,
                onRelocate: () => _relocateAll(attention),
              ),
            ],
            if (running.isEmpty && attention.isEmpty && stopped.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: TpText(
                    l10n.projectsNoMatch,
                    role: TpTextRole.secondary,
                  ),
                ),
              )
            else ...<Widget>[
              if (running.isNotEmpty) ...<Widget>[
                _GroupHeader(l10n.projectsGroupRunning),
                _ProjectGrid(
                  columns: 2,
                  children: <Widget>[
                    for (final int i in running)
                      _RunningCard(
                        key: ValueKey<int>(i),
                        index: i,
                        item: items[i],
                        snapshot: bars[i],
                        baseDir: baseDir,
                      ),
                  ],
                ),
              ],
              if (attention.isNotEmpty) ...<Widget>[
                _GroupHeader(l10n.projectsGroupAttention),
                _AttentionList(
                  children: <Widget>[
                    for (final int i in attention)
                      _AttentionRow(
                        key: ValueKey<int>(i),
                        index: i,
                        item: items[i],
                        snapshot: bars[i],
                        baseDir: baseDir,
                      ),
                  ],
                ),
              ],
              if (stopped.isNotEmpty) ...<Widget>[
                _GroupHeader(l10n.projectsGroupStopped),
                _ProjectGrid(
                  columns: 2,
                  children: <Widget>[
                    for (final int i in stopped)
                      _StoppedCard(
                        key: ValueKey<int>(i),
                        index: i,
                        item: items[i],
                        baseDir: baseDir,
                      ),
                  ],
                ),
              ],
            ],
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

/// `● 3 运行中　● 3 异常　○ 2 已停止`.
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.running,
    required this.errors,
    required this.stopped,
  });

  final int running;
  final int errors;
  final int stopped;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return Wrap(
      spacing: TpSpacing.s16,
      runSpacing: TpSpacing.s4,
      children: <Widget>[
        _StatusItem(
          kind: TpStateKind.success,
          filled: true,
          label: l10n.projectsStatusRunning(running),
        ),
        _StatusItem(
          kind: TpStateKind.critical,
          filled: true,
          label: l10n.projectsStatusError(errors),
        ),
        _StatusItem(
          kind: TpStateKind.neutral,
          filled: false,
          label: l10n.projectsStatusStopped(stopped),
        ),
      ],
    );
  }
}

class _StatusItem extends StatelessWidget {
  const _StatusItem({
    required this.kind,
    required this.filled,
    required this.label,
  });

  final TpStateKind kind;
  final bool filled;
  final String label;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final Color color = theme.stateColor(kind);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: filled ? color : Colors.transparent,
            shape: BoxShape.circle,
            border: filled ? null : Border.all(color: color, width: 1.5),
          ),
        ),
        const SizedBox(width: TpSpacing.s8),
        Text(
          label,
          style: TpTypography.body
              .toTextStyle(tabular: true)
              .copyWith(color: theme.text.secondary),
        ),
      ],
    );
  }
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
        border: Border.all(color: theme.control.stroke),
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

/// Caption row plus the taskbar mock.
class _TaskbarPreviewBlock extends ConsumerWidget {
  const _TaskbarPreviewBlock({
    required this.items,
    required this.bars,
    required this.baseDir,
  });

  final List<PinItem> items;
  final Map<int, BarSnapshot> bars;
  final String baseDir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final List<int> pinned = <int>[
      for (int i = 0; i < items.length; i++)
        if (items[i].pinned) i,
    ];
    final Map<int, int> positionOf = <int, int>{
      for (int k = 0; k < pinned.length; k++) pinned[k]: k,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TaskbarPreviewHeader(count: pinned.length),
        const SizedBox(height: TpSpacing.s8),
        TaskbarPreviewBar(
          pinnedCount: pinned.length,
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
        color: theme.stateSubtleOf(TpStateKind.critical, 0.08),
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

/// A caption group header with the section spacing from the spec.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        top: TpSpacing.sectionTop,
        bottom: TpSpacing.sectionBottom + TpSpacing.s4,
      ),
      child: Text(
        label,
        style: TpTypography.caption
            .toTextStyle()
            .copyWith(color: theme.text.secondary),
      ),
    );
  }
}

/// A responsive grid of cards, 16 apart.
class _ProjectGrid extends StatelessWidget {
  const _ProjectGrid({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Fit as many [kMinCardWidth] columns as the row can hold, capped at
        // the requested [columns]. The gap is included in the arithmetic so
        // two cards plus the gap, not two cards alone, is the threshold.
        final int fit = constraints.maxWidth <= 0
            ? 1
            : ((constraints.maxWidth + TpSpacing.s16) /
                      (kMinCardWidth + TpSpacing.s16))
                  .floor();
        final int cols = fit.clamp(1, columns);
        return _GridLayout(columns: cols, children: children);
      },
    );
  }
}

class _GridLayout extends StatelessWidget {
  const _GridLayout({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < children.length; i += columns) {
      final List<Widget> row = <Widget>[];
      for (int c = 0; c < columns; c++) {
        final int k = i + c;
        if (c > 0) row.add(const SizedBox(width: TpSpacing.s16));
        row.add(Expanded(
          child: k < children.length ? children[k] : const SizedBox.shrink(),
        ));
      }
      if (i > 0) rows.add(const SizedBox(height: TpSpacing.s16));
      // IntrinsicHeight gives the row a bounded height inside the page's
      // scroll view, so CrossAxisAlignment.stretch can equalise card heights.
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: row,
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// One card surface: bg.card, 1 px stroke.card, radius 8, padding 16. Hover
/// swaps the outline for stroke.strong. The card tap is translucent so its
/// inner switch and buttons still receive the pointer.
class _CardShell extends StatelessWidget {
  const _CardShell({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    return TpHoverBuilder(
      builder: (BuildContext context, bool hovered) => TpFocusRing(
        radius: TpRadius.card,
        onTap: onTap,
        hitTestBehavior: HitTestBehavior.translucent,
        // The focus ring wraps the child in a Stack, which hands it loose
        // constraints; expand so the card keeps the fixed height around it.
        child: SizedBox.expand(
          child: AnimatedContainer(
            duration: TpMotion.resolve(context, TpMotion.fast),
            padding: const EdgeInsets.all(TpSpacing.s16),
            decoration: BoxDecoration(
              color: theme.bg.card,
              borderRadius: TpRadius.card,
              border: Border.all(
                color: hovered ? theme.stroke.strong : theme.stroke.card,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A running project: name, badge, switch, more; metadata; mini bar.
///
/// Fixed height: every card in the grid is identical whether or not the
/// metadata line carries a relative time. At 150 % text scaling the content
/// still fits (see the widget tests).
class _RunningCard extends ConsumerWidget {
  const _RunningCard({
    super.key,
    required this.index,
    required this.item,
    required this.snapshot,
    required this.baseDir,
  });

  final int index;
  final PinItem item;
  final BarSnapshot? snapshot;
  final String baseDir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final String name = itemDisplayName(item, index, l10n);
    final String source = itemSourceLabel(item);
    final String interval = itemIntervalLabel(item.intervalMs, l10n);
    return SizedBox(
      height: kRunningCardHeight,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.25,
        child: _CardShell(
          onTap: () => context.go(AppRoutes.signal(index)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.max,
            children: <Widget>[
              // One Expanded for the whole left group, then the controls.
              //
              // This used to be `Flexible(name) + Badge + Spacer + controls`.
              // A `Flexible` (loose) and a `Spacer` (a flex-1 `Expanded`) in
              // the same row split the free space, and the badge in between
              // made the split depend on the name's width — so the controls
              // did not land at the same offset as the stopped card's, which
              // has no Spacer. Grouping the left side into one `Expanded`
              // leaves exactly one elastic child, so the controls are pinned
              // to the card's trailing edge in both card types.
              Row(
                children: <Widget>[
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TpTypography.bodyStrong
                                .toTextStyle()
                                .copyWith(color: theme.text.primary),
                          ),
                        ),
                        const SizedBox(width: TpSpacing.s8),
                        _RunningBadge(label: l10n.statusRunning),
                      ],
                    ),
                  ),
                  const SizedBox(width: TpSpacing.s12),
                  _CardControls(index: index, item: item),
                ],
              ),
              const SizedBox(height: TpSpacing.s4),
              _UpdatedLine(
                parts: <String>[source, interval],
                updatedAt: snapshot?.updatedAt,
                style: TpTypography.caption
                    .toTextStyle(tabular: true)
                    .copyWith(color: theme.text.secondary),
              ),
              const Spacer(),
              _MiniBar(content: snapshot?.content),
            ],
          ),
        ),
      ),
    );
  }
}

/// The trailing pair on every project card: the pin switch and the "…" menu.
///
/// Grouping them is what stops the card from looking like two unrelated
/// islands. The 1 px rule is the same `stroke.divider` the rest of the UI
/// uses, and it is vertical because the pair is laid out in a row.
class _CardControls extends ConsumerWidget {
  const _CardControls({required this.index, required this.item});

  final int index;
  final PinItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TpDivider(vertical: true),
        const SizedBox(width: TpSpacing.s12),
        TpSwitch(
          value: item.pinned,
          onChanged: (bool _) =>
              ref.read(configProvider.notifier).togglePinned(index),
        ),
        const SizedBox(width: TpSpacing.s4),
        ProjectMoreButton(index: index, item: item),
      ],
    );
  }
}

/// `运行中` pill: success text on a 12 % success fill, radius 4.
class _RunningBadge extends StatelessWidget {
  const _RunningBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: TpSpacing.s6,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: theme.stateSubtle(TpStateKind.success),
        borderRadius: TpRadius.control,
      ),
      child: Text(
        label,
        style: TpTypography.caption.toTextStyle().copyWith(
              color: theme.status.success,
            ),
      ),
    );
  }
}

/// The 36-high dark strip inside a card: label plus latest output.
class _MiniBar extends StatelessWidget {
  const _MiniBar({required this.content});

  final TpBarContent? content;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final TpBarContent? c = content;
    return Container(
      height: kMiniBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: TpSpacing.s12),
      decoration: BoxDecoration(
        color: theme.taskbar,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: <Widget>[
          Text(
            l10n.taskbarShowLabel,
            style: TpTypography.caption
                .toTextStyle()
                .copyWith(color: theme.taskbarLabel),
          ),
          const SizedBox(width: TpSpacing.s12),
          Expanded(
            child: c == null || c.isEmpty
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      height: kMiniBarHeight,
                      width: double.infinity,
                      child: TpBarPreviewStrip(
                        content: c,
                        height: kMiniBarHeight,
                        background: theme.taskbar,
                        width: double.infinity,
                        showStateStrip: false,
                      ),
                    ),
                  ),          ),
        ],
      ),
    );
  }
}

/// A needs-attention row: critical file icon, name, error, actions.
class _AttentionRow extends ConsumerWidget {
  const _AttentionRow({
    super.key,
    required this.index,
    required this.item,
    required this.snapshot,
    required this.baseDir,
  });

  final int index;
  final PinItem item;
  final BarSnapshot? snapshot;
  final String baseDir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final String name = itemDisplayName(item, index, l10n);
    final String? problem = _problemText(context, ref);

    return SizedBox(
      height: kAttentionRowHeight,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.25,
        child: TpHoverBuilder(
          builder: (BuildContext context, bool hovered) => TpFocusRing(
            radius: TpRadius.card,
            onTap: () => context.go(AppRoutes.signal(index)),
            hitTestBehavior: HitTestBehavior.translucent,
            child: SizedBox.expand(
              child: AnimatedContainer(
                duration: TpMotion.resolve(context, TpMotion.fast),
                padding: const EdgeInsets.symmetric(
                  horizontal: TpSpacing.s16,
                  vertical: TpSpacing.s8,
                ),
                decoration: BoxDecoration(
                  color: theme.bg.card,
                  border: Border.all(
                    color: hovered ? theme.stroke.strong : theme.stroke.card,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(TpIcons.file, size: 16, color: theme.status.critical),
                    const SizedBox(width: TpSpacing.s12),
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
                            style: TpTypography.body
                                .toTextStyle()
                                .copyWith(color: theme.text.primary),
                          ),
                          if (problem != null)
                            Text(
                              problem,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TpTypography.caption
                                  .toTextStyle()
                                  .copyWith(color: theme.status.critical),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: TpSpacing.s16),
                    TpButton(
                      label: l10n.projectRelocate,
                      onPressed: () => _relocate(context, ref),
                    ),
                    const SizedBox(width: TpSpacing.s8),
                    ProjectDeleteButton(index: index, item: item),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _problemText(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
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
    return error == null ? null : _oneLine(error);
  }

  Future<void> _relocate(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = context.l10n;
    final String? path = await showRelocateDialog(
      context,
      name: itemDisplayName(item, index, l10n),
      current: item.luaPath,
    );
    if (path == null) return;
    ref.read(configProvider.notifier).editItem(index, (PinItem i) {
      i.luaPath = path;
    });
  }
}

/// The needs-attention group is one card holding divided rows. Each row is
/// [kAttentionRowHeight] high; the 1 px divider sits between rows, so the
/// rows themselves stay identical.
class _AttentionList extends StatelessWidget {
  const _AttentionList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Container(height: 1, color: theme.stroke.divider));
      }
      rows.add(children[i]);
    }
    return ClipRRect(
      borderRadius: TpRadius.card,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

/// A stopped project: letter avatar, name, source, switch, more.
///
/// Fixed height, so every stopped card is identical.
class _StoppedCard extends ConsumerWidget {
  const _StoppedCard({
    super.key,
    required this.index,
    required this.item,
    required this.baseDir,
  });

  final int index;
  final PinItem item;
  final String baseDir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final String name = itemDisplayName(item, index, l10n);
    final String source = itemSourceLabel(item);
    final String interval = itemIntervalLabel(item.intervalMs, l10n);

    return SizedBox(
      height: kStoppedCardHeight,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.25,
        child: _CardShell(
          onTap: () => context.go(AppRoutes.signal(index)),
          child: Row(
            children: <Widget>[
              TpAvatar(name: name, size: 40),
              const SizedBox(width: TpSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TpTypography.body
                          .toTextStyle()
                          .copyWith(color: theme.text.primary),
                    ),
                    Text(
                      <String>[source, interval]
                          .where((String s) => s.isNotEmpty)
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TpTypography.caption
                          .toTextStyle(tabular: true)
                          .copyWith(color: theme.text.secondary),
                    ),
                  ],
                ),
              ),
              // 12, matching the running card: both cards put the same gap
              // between their content and the control group, so the switch
              // and the "…" sit at the same offset from the trailing edge.
              const SizedBox(width: TpSpacing.s12),
              _CardControls(index: index, item: item),
            ],
          ),
        ),
      ),
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
        entry(_RowAction.copy, TpIcons.copy, l10n.projectCopy),
        entry(_RowAction.delete, TpIcons.delete, l10n.mainDelete),
      ],
    );
    if (picked == null || !context.mounted) return;

    switch (picked) {
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

enum _RowAction { copy, delete }

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

/// Source and interval, followed by the relative update time. Ticks once per
/// second while the card is mounted.
class _UpdatedLine extends StatefulWidget {
  const _UpdatedLine({
    required this.parts,
    required this.updatedAt,
    required this.style,
  });

  final List<String> parts;
  final DateTime? updatedAt;
  final TextStyle style;

  @override
  State<_UpdatedLine> createState() => _UpdatedLineState();
}

class _UpdatedLineState extends State<_UpdatedLine> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(_UpdatedLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.updatedAt != widget.updatedAt) {
      _start();
    }
  }

  void _start() {
    _timer?.cancel();
    if (widget.updatedAt == null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String updated =
        formatRelativeUpdated(widget.updatedAt, context.l10n);
    return Text(
      <String>[...widget.parts, if (updated.isNotEmpty) updated].join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: widget.style,
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
