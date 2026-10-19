// The plugin market (docs/VISUAL_SPEC.md section 5.5).
//
// Header, a segmented filter plus search row, then a responsive card grid.
// Each card shows a letter avatar, name, description, the bar preview (or the
// script name), its source, and the install state.
//
// Catalog fetching and installing live in `core/market/`; this file only
// presents them.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:taskpin_design/taskpin_design.dart';

import '../../app/l10n.dart';
import '../../app/shell/app_page.dart';
import '../../app/shell/routes.dart';
import '../../core/config/config_providers.dart';
import '../../core/config/config_schema.dart';
import '../../core/market/market_installer.dart';
import '../../core/market/market_models.dart';
import '../../core/scripts/script_files.dart';
import '../signals/widgets/avatar.dart';
import 'market_providers.dart';
import 'sources_dialog.dart';

/// Width of the search field.
const double kMarketSearchWidth = 320;

/// Height of every market card. 16 padding + 40 avatar row + 12 + 36 bar +
/// 12 + 32 footer + 16 padding. A card without a description is the same
/// height as one with it.
const double kMarketCardHeight = 164;

/// Grid breakpoints, in content width.
const double kMarketThreeColumns = 1000;
const double kMarketTwoColumns = 760;

/// Which entries the grid shows.
enum _Filter { all, installed, notInstalled }

/// The plugin market page.
class MarketPage extends ConsumerStatefulWidget {
  const MarketPage({super.key});

  @override
  ConsumerState<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends ConsumerState<MarketPage> {
  String _query = '';
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<MarketCatalog> async = ref.watch(marketCatalogProvider);
    // Hide the previous list while a refresh is running.
    final MarketCatalog? catalog = async.isLoading ? null : async.valueOrNull;
    final bool viaProxy = catalog?.inChina ?? false;
    final TaskPinConfig config = ref.watch(configProvider);
    final String baseDir = _baseDir();
    final String scriptsDir = _scriptsDir();

    final List<MarketScript> all = <MarketScript>[
      for (final MarketSourceCatalog s in catalog?.sources ?? const <MarketSourceCatalog>[])
        ...s.scripts,
    ];
    final ScriptInstallState Function(MarketScript) stateOf =
        (MarketScript s) => scriptInstallState(
              config: config,
              baseDir: baseDir,
              scriptsDir: scriptsDir,
              file: s.file,
            );
    final bool Function(MarketScript) isInstalled =
        (MarketScript s) => stateOf(s).installed;
    final int installedCount = all.where(isInstalled).length;
    final int total = all.length;

    return AppPage(
      title: l10n.marketTitle,
      subtitle: catalog == null
          ? null
          : Text(
              l10n.marketSubtitle(
                total,
                installedCount,
                (catalog.sources.map((MarketSourceCatalog s) => s.repo))
                    .join(l10n.marketSourceSeparator),
              ),
              style: TpTypography.body
                  .toTextStyle(tabular: true)
                  .copyWith(color: TaskPinTheme.of(context).text.secondary),
            ),
      actions: <Widget>[
        TpButton(
          label: l10n.marketManageSources,
          icon: TpIcons.externalLink,
          onPressed: () => showMarketSourcesDialog(context),
        ),
        TpButton(
          label: l10n.marketRefresh,
          icon: TpIcons.refresh,
          variant: TpButtonVariant.icon,
          onPressed: _refresh,
        ),
      ],
      children: <Widget>[
        _FilterRow(
          filter: _filter,
          total: total,
          installed: installedCount,
          onFilter: (_Filter f) => setState(() => _filter = f),
          onQuery: (String v) => setState(() => _query = v),
        ),
        if (viaProxy)
          Padding(
            padding: const EdgeInsets.only(top: TpSpacing.s8),
            child: Text(
              l10n.marketViaProxy,
              style: TpTypography.caption
                  .toTextStyle()
                  .copyWith(color: TaskPinTheme.of(context).text.secondary),
            ),
          ),
        const SizedBox(height: TpSpacing.s16),
        ..._body(context, l10n, async, catalog, all, stateOf, baseDir),
      ],
    );
  }

  void _refresh() => ref.invalidate(marketCatalogProvider);

  List<Widget> _body(
    BuildContext context,
    AppLocalizations l10n,
    AsyncValue<MarketCatalog> async,
    MarketCatalog? catalog,
    List<MarketScript> all,
    ScriptInstallState Function(MarketScript) stateOf,
    String baseDir,
  ) {
    if (catalog == null) {
      final Object? error = async.error;
      if (error != null) {
        return <Widget>[_errorBar(l10n, '$error')];
      }
      final TaskPinTheme theme = TaskPinTheme.of(context);
      return <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 64),
          child: Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: theme.accent.fill,
              ),
            ),
          ),
        ),
      ];
    }

    final List<Widget> out = <Widget>[];
    for (final MarketSourceCatalog s in catalog.sources) {
      if (s.failed) {
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: TpSpacing.s8),
          child: _errorBar(l10n, _errorText(l10n, s)),
        ));
      }
    }

    final Set<String> installing = ref.watch(marketInstallProvider);
    final List<MarketScript> visible = <MarketScript>[
      for (final MarketScript script in all)
        if (script.matches(_query))
          if (_filter == _Filter.all ||
              (_filter == _Filter.installed && stateOf(script).installed) ||
              (_filter == _Filter.notInstalled && !stateOf(script).installed))
            script,
    ];

    if (visible.isEmpty && !catalog.allFailed) {
      out.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Text(
            _query.trim().isEmpty ? l10n.marketEmpty : l10n.marketNoMatch,
            style: TpTypography.body
                .toTextStyle()
                .copyWith(color: TaskPinTheme.of(context).text.secondary),
          ),
        ),
      ));
      return out;
    }

    out.add(
      LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final int columns = constraints.maxWidth < kMarketTwoColumns
              ? 1
              : (constraints.maxWidth < kMarketThreeColumns ? 2 : 3);
          return _MarketGrid(
            columns: columns,
            children: <Widget>[
              for (final MarketScript script in visible)
                _MarketCard(
                  key: ValueKey<String>(marketScriptKey(script)),
                  script: script,
                  installing: installing.contains(marketScriptKey(script)),
                  state: stateOf(script),
                ),
            ],
          );
        },
      ),
    );
    return out;
  }

  Widget _errorBar(AppLocalizations l10n, String message) => TpInfoBar(
        kind: TpStateKind.critical,
        title: l10n.marketLoadFailed,
        message: message,
        actions: <Widget>[
          TpButton(label: l10n.marketRetry, onPressed: _refresh),
        ],
      );

  String _errorText(AppLocalizations l10n, MarketSourceCatalog s) {
    final String reason = switch (s.error) {
      'network' => l10n.marketErrorNetwork,
      'api' => l10n.marketErrorApi,
      final String other => other,
    };
    return '${s.repo}: $reason';
  }

  String _baseDir() {
    try {
      return ref.read(configRepositoryProvider).paths.baseDir;
    } on Object {
      return '';
    }
  }

  String _scriptsDir() {
    try {
      return ref.read(configRepositoryProvider).paths.scriptsDir;
    } on Object {
      return '';
    }
  }
}

/// Segmented filter on the left, search on the right.
class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.filter,
    required this.total,
    required this.installed,
    required this.onFilter,
    required this.onQuery,
  });

  final _Filter filter;
  final int total;
  final int installed;
  final ValueChanged<_Filter> onFilter;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final Widget segments = TpSegmentedControl<_Filter>(
      value: filter,
      onChanged: onFilter,
      segments: <TpSelectItem<_Filter>>[
        TpSelectItem<_Filter>(
          value: _Filter.all,
          label: l10n.marketFilterAll(total),
        ),
        TpSelectItem<_Filter>(
          value: _Filter.installed,
          label: l10n.marketFilterInstalled(installed),
        ),
        TpSelectItem<_Filter>(
          value: _Filter.notInstalled,
          label: l10n.marketFilterNotInstalled(total - installed),
        ),
      ],
    );
    final Widget search = TpTextField(
      hint: l10n.marketSearchHint,
      leading: Icon(TpIcons.search, size: 16),
      onChanged: onQuery,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Narrow: stack the search under the filter instead of overflowing.
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Align(alignment: Alignment.centerLeft, child: segments),
              const SizedBox(height: TpSpacing.s8),
              search,
            ],
          );
        }
        return Row(
          children: <Widget>[
            segments,
            const Spacer(),
            SizedBox(width: kMarketSearchWidth, child: search),
          ],
        );
      },
    );
  }
}

/// A fixed-column grid, 16 apart.
class _MarketGrid extends StatelessWidget {
  const _MarketGrid({required this.columns, required this.children});

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

class _MarketCard extends ConsumerWidget {
  const _MarketCard({
    super.key,
    required this.script,
    required this.installing,
    required this.state,
  });

  final MarketScript script;
  final bool installing;

  /// Where this script is on disk and which item, if any, references it.
  final ScriptInstallState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final bool installed = state.installed;
    final int itemIndex = state.itemIndex;
    final FolderOpener? openFolder = ref.watch(scriptFolderOpenerProvider);
    final String name = script.name.isEmpty ? script.file : script.name;
    final String description =
        script.description.isEmpty ? l10n.marketNoDescription : script.description;

    final Widget trailing;
    if (installing) {
      trailing = SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: theme.accent.fill,
        ),
      );
    } else if (installed) {
      final VoidCallback? open = itemIndex >= 0
          ? () => context.go(AppRoutes.signal(itemIndex))
          : openFolder == null
              ? null
              : () => _openFolder(ref, openFolder);
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            l10n.marketInstalled,
            style: TpTypography.caption.toTextStyle().copyWith(
                  color: theme.status.success,
                ),
          ),
          if (open != null) ...<Widget>[
            const SizedBox(width: TpSpacing.s8),
            TpButton(label: l10n.actionOpen, onPressed: open),
          ],
        ],
      );
    } else {
      trailing = TpButton(
        label: l10n.marketInstall,
        variant: TpButtonVariant.primary,
        onPressed: () => _install(context, ref),
      );
    }

    return SizedBox(
      height: kMarketCardHeight,
      child: TpSurface(
        level: TpSurfaceLevel.card,
        radius: TpRadius.card,
        padding: const EdgeInsets.all(TpSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TpAvatar(name: name),
                const SizedBox(width: TpSpacing.s12),
                Expanded(
                  child: Column(
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
                      Text(
                        description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TpTypography.caption
                            .toTextStyle()
                            .copyWith(color: theme.text.secondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: TpSpacing.s12),
            _MarketBar(label: l10n.marketBarLabel, value: script.file),
            const SizedBox(height: TpSpacing.s12),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    script.sourceRepo.isEmpty ? l10n.marketTitle : script.sourceRepo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TpTypography.caption
                        .toTextStyle()
                        .copyWith(color: theme.text.tertiary),
                  ),
                ),
                const SizedBox(width: TpSpacing.s8),
                trailing,
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openFolder(WidgetRef ref, FolderOpener opener) {
    final String dir = ref.read(configRepositoryProvider).paths.scriptsDir;
    opener(dir).catchError((Object _) {});
  }

  Future<void> _install(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = context.l10n;
    final InstallResult result =
        await ref.read(marketInstallProvider.notifier).install(script);
    if (!context.mounted) return;
    final TpToast? toast = switch (result.outcome) {
      InstallOutcome.installed || InstallOutcome.updated => null,
      InstallOutcome.itemLimitReached => TpToast(
          message: l10n.marketItemLimit,
          kind: TpStateKind.caution,
        ),
      InstallOutcome.downloadFailed => TpToast(
          message: l10n.marketDownloadFailed,
          kind: TpStateKind.critical,
        ),
      InstallOutcome.saveFailed => TpToast(
          message: l10n.marketSaveFailed,
          kind: TpStateKind.critical,
        ),
    };
    if (toast != null) TpToastHost.show(context, toast);
  }
}

/// The 36-high dark strip: label on the left, value on the right.
class _MarketBar extends StatelessWidget {
  const _MarketBar({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: TpSpacing.s12),
      decoration: BoxDecoration(
        color: theme.taskbar,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: <Widget>[
          Text(
            label,
            style: TpTypography.caption
                .toTextStyle()
                .copyWith(color: theme.taskbarLabel),
          ),
          const SizedBox(width: TpSpacing.s12),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TpTypography.mono
                    .toTextStyle(tabular: true)
                    .copyWith(color: theme.taskbarMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
