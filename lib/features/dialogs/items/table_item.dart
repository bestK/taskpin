// A `DI_TABLE` item: a header row, a rule, then body rows with an optional
// per-row action.
//
// C parity (`lib/script_dialog.c:230-310` and the action handling at
// `:532-563`):
//   - header row, bold, on `RGB(45,45,45)` (`TABLE_HDR_BG`);
//   - a 1 px separator under the header;
//   - body rows alternating `RGB(35,35,35)` / `RGB(40,40,40)`;
//   - the "Open" affordance appears ONLY for a row whose `row_urls[r]` or
//     `row_cmds[r]` is non-empty (`:275`), is 50 px wide, and reads "Open" in
//     `RGB(100,180,255)` (`:443-446`);
//   - the button opens the row's URL, else runs the row's command, with the
//     same `ShellExecuteW` / `cmd /c` split as a button item.
//
// PARITY — per-row text colour is NOT supported. The legacy struct carries
// `row_colors[DIALOG_MAX_ROWS]` (`lib/scripting.h:53`) and the renderer reads
// it (`lib/script_dialog.c:270`), but the legacy Lua parser never populates it
// (it is zeroed at `lib/scripting.c:560`) and the unified ABI has no such field
// at all (`native/engine/taskpin_engine.h`, TPDialogItem). So in every shipped
// build it is `0` and every row draws in the default foreground. Rows are
// rendered in `text/primary` here; if `row_colors` is ever resurrected, this
// file is where it lands.
//
// INTENTIONAL DIFFERENCE — the action column is reserved for the WHOLE table
// when any row has an action, rather than per-row as the C renderer does
// (`:275-279` computes `text_col_w` from that row's own `btn_w_px`). The C
// behaviour makes rows with an action have narrower text columns than rows
// without, so the columns do not line up down the table. Reserving the column
// once keeps the grid aligned. This is a rendering nuance, not a data change —
// which rows have actions is identical.

import 'package:flutter/widgets.dart';
import 'package:taskpin_design/taskpin_design.dart';

import '../dialog_action.dart';
import '../dialog_palette.dart';
import '../dialog_spec.dart';

class DialogTableItem extends StatelessWidget {
  const DialogTableItem({super.key, required this.item, required this.runner});

  final DialogItem item;

  /// Where a row's URL / command goes.
  final DialogActionRunner runner;

  /// The C width of the per-row "Open" button (`lib/script_dialog.c:277`).
  static const double actionColumnWidth = 50;

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    if (item.colCount == 0) {
      // A table with no columns has nothing to lay out. The C renderer divides
      // by `col_count > 0 ? : 1` and draws an empty header (`:237`), which
      // amounts to a stray grey band; nothing is the better rendering.
      return const SizedBox.shrink();
    }

    final bool reserveAction = item.hasAnyRowAction;

    return TpSurface(
      level: TpSurfaceLevel.inset,
      radius: TpRadius.control,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _header(context, theme, reserveAction),
          const TpDivider(),
          for (int r = 0; r < item.rowCount; r++)
            _row(context, theme, r, reserveAction),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, TaskPinTheme theme, bool reserveAction) {
    return ColoredBox(
      // C: TABLE_HDR_BG, RGB(45,45,45).
      color: theme.bg.flyout,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TpSpacing.s8,
          vertical: TpSpacing.s4,
        ),
        child: Row(
          children: <Widget>[
            for (final String c in item.columns)
              Expanded(
                child: Text(
                  c,
                  // C draws the header with the BOLD font (`:231, :245`).
                  style: TpTypography.body.toTextStyle().copyWith(
                    color: theme.text.secondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            if (reserveAction) const SizedBox(width: actionColumnWidth),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    TaskPinTheme theme,
    int r,
    bool reserveAction,
  ) {
    final bool hasAction = item.rowHasAction(r);
    final List<String> cells = r < item.cells.length
        ? item.cells[r]
        : const <String>[];

    return TpHoverBuilder(
      builder: (BuildContext context, bool hovered) {
        return ColoredBox(
          // C: alternating TABLE_ROW_EVEN / TABLE_ROW_ODD (`:266`).
          color: r.isEven
              ? theme.bg.window
              : (hovered ? theme.bg.cardSecondary : theme.bg.window),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TpSpacing.s8,
              vertical: TpSpacing.s4,
            ),
            child: Row(
              children: <Widget>[
                for (int c = 0; c < item.colCount; c++)
                  Expanded(
                    child: Text(
                      c < cells.length ? cells[c] : '',
                      style: TpTypography.body.toTextStyle().copyWith(
                        color: theme.text.primary,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                if (reserveAction)
                  SizedBox(
                    width: actionColumnWidth,
                    child: hasAction
                        ? _action(context, theme, r)
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _action(BuildContext context, TaskPinTheme theme, int r) {
    return Align(
      alignment: Alignment.centerRight,
      child: TpFocusRing(
        radius: TpRadius.control,
        onTap: () => _runRowAction(r),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TpSpacing.s4,
            vertical: TpSpacing.s2,
          ),
          child: Text(
            'Open',
            // C: RGB(100,180,255) — an accent-coloured link (`:443`).
            style: TpTypography.body.toTextStyle().copyWith(
              color: theme.accent.fill,
            ),
          ),
        ),
      ),
    );
  }

  /// URL first, then command — the same precedence as the C handler
  /// (`lib/script_dialog.c:541-556`).
  void _runRowAction(int r) {
    if (r < item.rowUrls.length && item.rowUrls[r].isNotEmpty) {
      runner.openUrl(item.rowUrls[r]);
      return;
    }
    if (r < item.rowCmds.length && item.rowCmds[r].isNotEmpty) {
      runner.runCommand(item.rowCmds[r]);
    }
  }
}
