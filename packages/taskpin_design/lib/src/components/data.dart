// Data components: SignalCard, SignalGrid, MarketCard, SourceChip, KeyValueList.
//
// `TpSignalCard` is the primary object of the app: one pinned thing, its
// current reading, and its health. `TpSignalGrid` is the dense-table variant
// for people running a dozen signals, where the card's whitespace is the enemy.

import 'package:flutter/material.dart';

import '../theme/taskpin_theme.dart';
import '../tokens/motion.dart';
import '../tokens/radius.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import '../util/focus.dart';
import 'feedback.dart';
import 'status.dart';
import 'ui.dart';

/// A card representing one signal.
///
/// Layout: a header row (name, status, interval), a value row (the reading,
/// large and tabular), and a footer (source, last-updated). The sparkline slot
/// is optional and always occupies its space so the card's height does not
/// jump when history arrives.
class TpSignalCard extends StatelessWidget {
  const TpSignalCard({
    super.key,
    required this.name,
    required this.kind,
    required this.value,
    this.unit,
    this.interval,
    this.lastUpdated,
    this.source,
    this.sparklineValues,
    this.onTap,
    this.onPin,
    this.pinned = false,
    this.selected = false,
    this.error,
  });

  final String name;

  /// Health of this signal. Drives the status pill and the card's accent edge.
  final TpStateKind kind;

  /// The current reading, already formatted. Rendered tabular.
  final String value;

  /// Optional unit, rendered in tertiary text next to the value.
  final String? unit;

  final Duration? interval;
  final DateTime? lastUpdated;

  /// Where the value came from: a URL host, a script name, `HTTP`.
  final String? source;

  /// Sparkline series. Null hides the slot's content but keeps its height.
  final List<double?>? sparklineValues;

  final VoidCallback? onTap;

  /// Pin/unpin affordance. Null hides it.
  final VoidCallback? onPin;
  final bool pinned;

  final bool selected;

  /// When set, the card renders in the error state and shows this message
  /// instead of [value]. This is the plan's replacement for shoving a Lua
  /// traceback into the taskbar.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final String? err = error;
    final bool isError = err != null || kind == TpStateKind.critical;

    return TpHoverBuilder(
      builder: (BuildContext context, bool hovered) {
        final Widget body = TpSurface(
          level: TpSurfaceLevel.card,
          radius: TpRadius.card,
          clip: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: isError ? theme.status.critical : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(TpSpacing.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _header(context),
                  const SizedBox(height: TpSpacing.s12),
                  _reading(context),
                  const SizedBox(height: TpSpacing.s12),
                  _footer(context),
                ],
              ),
            ),
          ),
        );

        return TpFocusRing(
          radius: TpRadius.card,
          onTap: onTap,
          child: AnimatedContainer(
            duration: TpMotion.resolve(context, TpMotion.fast),
            decoration: BoxDecoration(
              borderRadius: TpRadius.card,
              border: Border.all(
                color: selected
                    ? theme.focusOuter
                    : (hovered ? theme.control.strokeStrong : Colors.transparent),
              ),
            ),
            child: body,
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            name,
            style: TpTypography.subtitle
                .toTextStyle()
                .copyWith(color: theme.text.primary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (interval != null) ...<Widget>[
          TpIntervalBadge(interval: interval!),
          const SizedBox(width: TpSpacing.s8),
        ],
        TpStatusDot(kind: kind),
      ],
    );
  }

  Widget _reading(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final String? err = error;
    if (err != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(TpIcons.danger, size: 16, color: theme.status.critical),
          const SizedBox(width: TpSpacing.s8),
          Expanded(
            child: Text(
              err,
              style: TpTypography.caption
                  .toTextStyle()
                  .copyWith(color: theme.status.critical),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    // The value and its unit share a baseline; the sparkline sits beside them
    // centred. Putting the sparkline in the baseline Row would be a mistake:
    // it has no text baseline, and mixing baseline-aligned children with
    // baseline-less ones is how you get a layout assertion.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TpMetric(value, spec: TpTypography.title),
            if (unit != null) ...<Widget>[
              const SizedBox(width: TpSpacing.s4),
              Text(
                unit!,
                style: TpTypography.body
                    .toTextStyle()
                    .copyWith(color: theme.text.tertiary),
              ),
            ],
          ],
        ),
        const Spacer(),
        if (sparklineValues != null)
          TpSparkline(values: sparklineValues!, width: 64, height: 20),
      ],
    );
  }

  Widget _footer(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final DateTime? updated = lastUpdated;
    final String? src = source;

    return Row(
      children: <Widget>[
        if (src != null)
          Expanded(
            child: Text(
              src,
              style: TpTypography.caption
                  .toTextStyle()
                  .copyWith(color: theme.text.tertiary),
              overflow: TextOverflow.ellipsis,
            ),
          )
        else
          const Spacer(),
        if (updated != null)
          TpRelativeTime(
            timestamp: updated,
            staleAfter: interval == null ? null : interval! * 2,
          ),
        if (onPin != null) ...<Widget>[
          const SizedBox(width: TpSpacing.s8),
          TpFocusRing(
            radius: TpRadius.control,
            onTap: onPin,
            child: Padding(
              padding: const EdgeInsets.all(TpSpacing.s4),
              child: Icon(
                pinned ? TpIcons.unpin : TpIcons.pin,
                size: 14,
                color: pinned ? theme.accent.text : theme.text.tertiary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One row of a [TpSignalGrid].
class TpSignalRow {
  const TpSignalRow({
    required this.name,
    required this.kind,
    required this.value,
    this.unit,
    this.interval,
    this.lastUpdated,
    this.source,
    this.error,
  });

  final String name;
  final TpStateKind kind;
  final String value;
  final String? unit;
  final Duration? interval;
  final DateTime? lastUpdated;
  final String? source;
  final String? error;
}

/// The dense table for heavy users.
///
/// Deliberately a table, not a grid of cards: at 12+ signals the card layout
/// wastes more space than it buys, and a table is scannable in a way cards are
/// not. Column widths are proportional so it survives resizing.
class TpSignalGrid extends StatelessWidget {
  const TpSignalGrid({
    super.key,
    required this.rows,
    this.selectedIndex,
    this.onSelect,
    this.emptyState,
  });

  final List<TpSignalRow> rows;
  final int? selectedIndex;
  final ValueChanged<int>? onSelect;

  /// Shown when [rows] is empty. Defaults to a plain [TpEmptyState].
  final Widget? emptyState;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);

    if (rows.isEmpty) {
      return emptyState ??
          const TpEmptyState(
            title: 'No signals',
            message: 'Add a signal to start monitoring.',
          );
    }

    return TpSurface(
      level: TpSurfaceLevel.card,
      radius: TpRadius.card,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _headerRow(context),
          const TpDivider(),
          for (int i = 0; i < rows.length; i++) ...<Widget>[
            _dataRow(context, i),
            if (i < rows.length - 1) const TpDivider(),
          ],
        ],
      ),
    );
  }

  Widget _headerRow(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final TextStyle style = TpTypography.caption
        .toTextStyle()
        .copyWith(color: theme.text.tertiary);

    return Container(
      color: theme.bg.cardSecondary,
      padding: const EdgeInsets.symmetric(
        horizontal: TpSpacing.s12,
        vertical: TpSpacing.s8,
      ),
      child: DefaultTextStyle(
        style: style,
        child: const Row(
          children: <Widget>[
            Expanded(flex: 4, child: TpText('Signal')),
            Expanded(flex: 3, child: TpText('Value')),
            Expanded(flex: 2, child: TpText('Interval')),
            Expanded(flex: 2, child: TpText('Updated')),
          ],
        ),
      ),
    );
  }

  Widget _dataRow(BuildContext context, int index) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final TpSignalRow row = rows[index];
    final bool selected = selectedIndex == index;

    return TpHoverBuilder(
      builder: (BuildContext context, bool hovered) {
        final Color bg = selected
            ? theme.subtle.hover
            : (hovered ? theme.bg.cardSecondary : Colors.transparent);

        return TpFocusRing(
          radius: BorderRadius.zero,
          onTap: onSelect == null ? null : () => onSelect!(index),
          child: ColoredBox(
            color: bg,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TpSpacing.s12,
                vertical: TpSpacing.s8,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: 4,
                    child: Row(
                      children: <Widget>[
                        TpStatusDot(kind: row.kind, size: 6),
                        const SizedBox(width: TpSpacing.s8),
                        Expanded(
                          child: Text(
                            row.name,
                            style: TpTypography.bodyStrong
                                .toTextStyle()
                                .copyWith(color: theme.text.primary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: row.error != null
                        ? Text(
                            row.error!,
                            style: TpTypography.caption
                                .toTextStyle()
                                .copyWith(color: theme.status.critical),
                            overflow: TextOverflow.ellipsis,
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: <Widget>[
                              TpMetric(row.value, spec: TpTypography.mono),
                              if (row.unit != null) ...<Widget>[
                                const SizedBox(width: TpSpacing.s4),
                                Text(
                                  row.unit!,
                                  style: TpTypography.caption
                                      .toTextStyle()
                                      .copyWith(color: theme.text.tertiary),
                                ),
                              ],
                            ],
                          ),
                  ),
                  Expanded(
                    flex: 2,
                    child: row.interval == null
                        ? const SizedBox.shrink()
                        : TpIntervalBadge(interval: row.interval!),
                  ),
                  Expanded(
                    flex: 2,
                    child: row.lastUpdated == null
                        ? const SizedBox.shrink()
                        : TpRelativeTime(
                            timestamp: row.lastUpdated!,
                            staleAfter: row.interval == null
                                ? null
                                : row.interval! * 2,
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

/// A marketplace entry.
class TpMarketCard extends StatelessWidget {
  const TpMarketCard({
    super.key,
    required this.name,
    required this.description,
    this.author,
    this.sourceRepo,
    this.installed = false,
    this.busy = false,
    this.onInstall,
    this.onOpen,
  });

  final String name;
  final String description;
  final String? author;

  /// `user/repo` the script came from.
  final String? sourceRepo;

  final bool installed;

  /// An install is in flight: disables the action and shows a progress bar.
  final bool busy;

  final VoidCallback? onInstall;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final String? repo = sourceRepo;

    return TpSurface(
      level: TpSurfaceLevel.card,
      radius: TpRadius.card,
      padding: const EdgeInsets.all(TpSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  name,
                  style: TpTypography.subtitle
                      .toTextStyle()
                      .copyWith(color: theme.text.primary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (installed)
                TpStatusPill(
                  label: 'Installed',
                  kind: TpStateKind.success,
                ),
            ],
          ),
          const SizedBox(height: TpSpacing.s6),
          Text(
            description,
            style: TpTypography.body
                .toTextStyle()
                .copyWith(color: theme.text.secondary),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: TpSpacing.s12),
          if (busy) ...<Widget>[
            const TpProgressBar(value: null, indeterminate: true),
            const SizedBox(height: TpSpacing.s8),
          ],
          Row(
            children: <Widget>[
              if (author != null) TpSourceChip(label: author!),
              if (author != null && repo != null)
                const SizedBox(width: TpSpacing.s6),
              if (repo != null) TpSourceChip(label: repo, icon: TpIcons.code),
              const Spacer(),
              if (onOpen != null)
                TpFocusRing(
                  radius: TpRadius.control,
                  onTap: onOpen,
                  child: Padding(
                    padding: const EdgeInsets.all(TpSpacing.s6),
                    child: Icon(
                      TpIcons.externalLink,
                      size: 14,
                      color: theme.text.tertiary,
                    ),
                  ),
                ),
              if (onInstall != null && !installed) ...<Widget>[
                const SizedBox(width: TpSpacing.s8),
                TpButton(
                  label: 'Install',
                  icon: TpIcons.download,
                  onPressed: busy ? null : onInstall,
                  variant: TpButtonVariant.primary,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A small chip naming where something came from.
class TpSourceChip extends StatelessWidget {
  const TpSourceChip({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final IconData? i = icon;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: TpSpacing.s8,
        vertical: TpSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: theme.bg.cardSecondary,
        borderRadius: TpRadius.chip,
        border: Border.all(color: theme.stroke.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (i != null) ...<Widget>[
            Icon(i, size: 11, color: theme.text.tertiary),
            const SizedBox(width: TpSpacing.s4),
          ],
          Text(
            label,
            style: TpTypography.caption
                .toTextStyle()
                .copyWith(color: theme.text.secondary),
          ),
        ],
      ),
    );
  }
}

/// A label/value list. The read-only presentation of a record.
class TpKeyValueList extends StatelessWidget {
  const TpKeyValueList({
    super.key,
    required this.entries,
    this.monoValues = false,
    this.divider = true,
  });

  /// Label -> value. Order is preserved (pass a `LinkedHashMap` or a list).
  final Map<String, String> entries;

  /// Render values in the mono role. Use when the values are identifiers,
  /// paths or numbers rather than prose.
  final bool monoValues;

  final bool divider;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final List<MapEntry<String, String>> items = entries.entries.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...<Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: TpSpacing.s6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 140,
                  child: Text(
                    items[i].key,
                    style: TpTypography.body
                        .toTextStyle()
                        .copyWith(color: theme.text.tertiary),
                  ),
                ),
                const SizedBox(width: TpSpacing.s12),
                Expanded(
                  child: monoValues
                      ? TpMetric(items[i].value, spec: TpTypography.mono)
                      : Text(
                          items[i].value,
                          style: TpTypography.body
                              .toTextStyle()
                              .copyWith(color: theme.text.primary),
                        ),
                ),
              ],
            ),
          ),
          if (divider && i < items.length - 1) const TpDivider(),
        ],
      ],
    );
  }
}
