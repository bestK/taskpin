// The Logs page: the projects that cannot run, newest failure first.
//
// It lists exactly what the top-nav badge counts (`collectItemProblems`). Rows
// have a time only when the failing run has one; config problems show no time.
// There is no clear action because nothing here is stored: each row is
// recomputed from the config and the bar controller's last snapshot.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskpin_design/taskpin_design.dart';

import '../../app/l10n.dart';
import '../../app/shell/app_page.dart';
import '../../core/bar/bar_controller.dart';
import '../../core/config/config_providers.dart';
import '../../core/config/config_schema.dart';
import 'item_problems.dart';

/// Text longer than this, in characters, collapses behind a "details" toggle.
const int kLogInlineLength = 120;

/// Time-of-day stamp, `HH:mm:ss`, the way a log view reads it.
String formatLogTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// The Logs page, the destination of the top-nav Logs tab.
class LogsPage extends ConsumerWidget {
  const LogsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final TaskPinConfig config = ref.watch(configProvider);
    final Map<int, BarSnapshot> bars =
        ref.watch(barControllerProvider.select((BarState s) => s.bars));
    final List<ItemProblem> problems = collectItemProblems(
      config.items,
      bars,
      _baseDir(ref),
      l10n,
    );

    return AppPage(
      title: l10n.navLogs,
      children: <Widget>[
        if (problems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 64),
            child: TpEmptyState(title: l10n.logsEmpty, icon: TpIcons.diagnostics),
          )
        else
          TpSurface(
            level: TpSurfaceLevel.card,
            radius: TpRadius.card,
            clip: true,
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < problems.length; i++) ...<Widget>[
                  if (i > 0) const TpDivider(),
                  _LogRow(problem: problems[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }

  static String _baseDir(WidgetRef ref) {
    try {
      return ref.watch(configRepositoryProvider).paths.baseDir;
    } on Object {
      return '';
    }
  }
}

/// One row: time, project, state pill, message.
///
/// A long message is selectable and cut to one line until the user opens it.
class _LogRow extends StatefulWidget {
  const _LogRow({required this.problem});

  final ItemProblem problem;

  @override
  State<_LogRow> createState() => _LogRowState();
}

class _LogRowState extends State<_LogRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final AppLocalizations l10n = context.l10n;
    final ItemProblem p = widget.problem;
    final DateTime? time = p.updatedAt;
    final bool long = p.message.length > kLogInlineLength;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TpSpacing.s16,
        vertical: TpSpacing.s12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(
              time == null ? '--:--:--' : formatLogTime(time),
              style: TpTypography.caption.toTextStyle(tabular: true).copyWith(
                    color: theme.text.tertiary,
                  ),
            ),
          ),
          const SizedBox(width: TpSpacing.s12),
          SizedBox(
            width: 160,
            child: Text(
              p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TpTypography.bodyStrong
                  .toTextStyle()
                  .copyWith(color: theme.text.primary),
            ),
          ),
          const SizedBox(width: TpSpacing.s12),
          TpStatusPill(label: l10n.statusError, kind: TpStateKind.critical),
          const SizedBox(width: TpSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SelectableText(
                  _expanded || !long
                      ? p.message
                      : '${p.message.substring(0, kLogInlineLength)}...',
                  style: TpTypography.body
                      .toTextStyle()
                      .copyWith(color: theme.text.secondary),
                ),
                if (long)
                  TpButton(
                    label: _expanded ? l10n.logsLess : l10n.logsMore,
                    variant: TpButtonVariant.text,
                    onPressed: () => setState(() => _expanded = !_expanded),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
