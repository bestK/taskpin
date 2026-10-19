// The market's source list dialog: add and remove `user/repo` sources.
//
// The add/remove rules (8 sources at most, `user/repo` format, no duplicates)
// are in `core/market/market_source.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskpin_design/taskpin_design.dart';

import '../../app/l10n.dart';
import '../../core/config/config_providers.dart';
import '../../core/config/config_schema.dart';
import '../../core/market/market_sources.dart';
import 'market_providers.dart';

/// Opens the dialog.
Future<void> showMarketSourcesDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: TaskPinTheme.of(context).smoke,
    builder: (BuildContext ctx) => const MarketSourcesDialog(),
  );
}

/// Source list with an add field.
class MarketSourcesDialog extends ConsumerStatefulWidget {
  const MarketSourcesDialog({super.key});

  @override
  ConsumerState<MarketSourcesDialog> createState() =>
      _MarketSourcesDialogState();
}

class _MarketSourcesDialogState extends ConsumerState<MarketSourcesDialog> {
  final TextEditingController _input = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    final AppLocalizations l10n = context.l10n;
    final SourceAddResult result = addMarketSource(ref, _input.text);
    setState(() {
      switch (result) {
        case SourceAddResult.added:
          _input.clear();
          _error = null;
        case SourceAddResult.empty:
          _error = null;
        case SourceAddResult.invalidFormat:
          _error = l10n.marketSourceInvalid;
        case SourceAddResult.duplicate:
          _error = l10n.marketSourceDuplicate;
        case SourceAddResult.limitReached:
          _error = l10n.marketMaxSources;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final List<String> sources =
        ref.watch(configProvider.select((TaskPinConfig c) => c.sources.toList()));
    final bool canAdd = canAddSource(sources);

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
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(TpSpacing.s24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TpText(l10n.marketSourcesTitle, style: TpTypography.subtitle),
                    const SizedBox(height: TpSpacing.s12),
                    for (int i = 0; i < sources.length; i++)
                      _SourceRow(
                        source: sources[i],
                        removeLabel: l10n.mainDelete,
                        // The config cannot hold an empty list: loading it
                        // puts the default source back.
                        onRemove: sources.length > 1
                            ? () => removeMarketSource(ref, i)
                            : null,
                      ),
                    const SizedBox(height: TpSpacing.s12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: TpTextField(
                            controller: _input,
                            hint: l10n.marketSourceHint,
                            enabled: canAdd,
                            error: _error,
                            onChanged: (String _) {
                              if (_error != null) setState(() => _error = null);
                            },
                            onSubmitted: (String _) => _add(),
                          ),
                        ),
                        const SizedBox(width: TpSpacing.buttonGap),
                        TpButton(
                          label: l10n.mainAdd,
                          icon: TpIcons.add,
                          enabled: canAdd,
                          onPressed: _add,
                        ),
                      ],
                    ),
                    if (!canAdd)
                      Padding(
                        padding: const EdgeInsets.only(top: TpSpacing.s8),
                        child: TpText(
                          l10n.marketMaxSources,
                          style: TpTypography.caption,
                          role: TpTextRole.secondary,
                        ),
                      ),
                  ],
                ),
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
                    label: l10n.marketClose,
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

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.source,
    required this.removeLabel,
    required this.onRemove,
  });

  final String source;
  final String removeLabel;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: TpControlSize.control + TpSpacing.s4,
      child: Row(
        children: <Widget>[
          Expanded(
            child: TpText(
              source,
              style: TpTypography.body,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TpButton(
            label: removeLabel,
            icon: TpIcons.delete,
            variant: TpButtonVariant.icon,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
