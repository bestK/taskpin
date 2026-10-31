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

import 'dart:math' as math;

import 'package:flutter/material.dart' show Colors, Tooltip;
import 'package:flutter/widgets.dart';
import 'package:taskpin_design/taskpin_design.dart';

import '../dialog_action.dart';
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
    final List<bool> numericCols = _detectNumericColumns(item);
    final List<int> flexes = _computeColumnFlexes(item, numericCols);

    return TpSurface(
      level: TpSurfaceLevel.card,
      radius: TpRadius.control,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _header(context, theme, reserveAction, numericCols, flexes),
          const TpDivider(),
          for (int r = 0; r < item.rowCount; r++) ...<Widget>[
            if (r > 0) const TpDivider(),
            _row(context, theme, r, reserveAction, numericCols, flexes),
          ],
        ],
      ),
    );
  }

  Widget _header(
    BuildContext context,
    TaskPinTheme theme,
    bool reserveAction,
    List<bool> numericCols,
    List<int> flexes,
  ) {
    return ColoredBox(
      // Header surface is cardSecondary so it visibly steps up from the dialog
      // ground, providing clear visual structure for the table columns.
      color: theme.bg.cardSecondary,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TpSpacing.s8,
          vertical: TpSpacing.s4,
        ),
        child: Row(
          children: <Widget>[
            for (int c = 0; c < item.columns.length; c++)
              Expanded(
                flex: c < flexes.length ? flexes[c] : 1,
                child: Text(
                  item.columns[c],
                  // Header styling uses caption-weight semibold for crisp, dense structure.
                  style: TpTypography.caption.toTextStyle().copyWith(
                    color: theme.text.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: c < numericCols.length && numericCols[c]
                      ? TextAlign.right
                      : TextAlign.left,
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
    List<bool> numericCols,
    List<int> flexes,
  ) {
    final bool hasAction = item.rowHasAction(r);
    final List<String> cells = r < item.cells.length
        ? item.cells[r]
        : const <String>[];

    return TpHoverBuilder(
      builder: (BuildContext context, bool hovered) {
        return ColoredBox(
          // Rows sit on the card surface at rest, with a subtle hover highlight
          // rather than alternating fills now that hairline dividers delineate
          // the rows cleanly.
          color: hovered ? theme.subtle.hover : Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 28),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TpSpacing.s8,
                vertical: TpSpacing.s4,
              ),
              child: Row(
                children: <Widget>[
                  for (int c = 0; c < item.colCount; c++)
                    Expanded(
                      flex: c < flexes.length ? flexes[c] : 1,
                      child: _cellText(
                        theme,
                        c < cells.length ? cells[c] : '',
                        isNumeric: c < numericCols.length && numericCols[c],
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
          ),
        );
      },
    );
  }

  Widget _cellText(
    TaskPinTheme theme,
    String text, {
    required bool isNumeric,
  }) {
    final bool numeric = isNumeric || _isNumeric(text);
    final Widget content = Text(
      text,
      // Numeric and metric data uses tabular figures so numbers align cleanly down columns.
      style: TpTypography.body.toTextStyle(tabular: numeric).copyWith(
        color: theme.text.primary,
      ),
      textAlign: isNumeric ? TextAlign.right : TextAlign.left,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );

    // Provide a tooltip on hover for long text (e.g. process names) that might truncate.
    if (!numeric && text.length > 14) {
      return Tooltip(
        message: text,
        waitDuration: const Duration(milliseconds: 500),
        child: content,
      );
    }
    return content;
  }

  /// Pattern matching numeric values, percentages, currencies, or metric speeds (e.g. "1.2M/s").
  static final RegExp _kNumericPattern = RegExp(
    r'^[+-]?[$€¥£]?\d+(?:[.,]\d+)*(?:\s*(?:%|[a-zA-Z/°]+(?:\s*/\s*[a-zA-Z/°]+)*))?$',
  );

  /// Whether a cell string represents numeric, currency, percentage, or metric data.
  static bool _isNumeric(String text) {
    final String s = text.trim();
    if (s.isEmpty) {
      return false;
    }
    return _kNumericPattern.hasMatch(s);
  }

  /// Detect which columns contain predominantly numeric/metric data across rows.
  static List<bool> _detectNumericColumns(DialogItem item) {
    final List<bool> result = List<bool>.filled(item.colCount, false);
    for (int c = 0; c < item.colCount; c++) {
      int numericCount = 0;
      int totalCount = 0;
      for (final List<String> row in item.cells) {
        if (c < row.length) {
          final String val = row[c].trim();
          if (val.isNotEmpty && val != '-' && val != '?') {
            totalCount++;
            if (_isNumeric(val)) {
              numericCount++;
            }
          }
        }
      }
      result[c] = totalCount > 0 && (numericCount / totalCount) >= 0.5;
    }
    return result;
  }

  /// Allocate flexible column widths based on content lengths, giving text
  /// columns (like process names) proportionally more space than compact numbers.
  static List<int> _computeColumnFlexes(DialogItem item, List<bool> numericCols) {
    if (item.colCount <= 1) return const <int>[1];

    final List<int> flexes = List<int>.filled(item.colCount, 1);
    for (int c = 0; c < item.colCount; c++) {
      int maxLen = c < item.columns.length ? item.columns[c].length : 0;
      for (final List<String> row in item.cells) {
        if (c < row.length) {
          maxLen = math.max(maxLen, row[c].length);
        }
      }
      if (c < numericCols.length && numericCols[c]) {
        flexes[c] = maxLen > 14 ? 2 : 1;
      } else {
        if (maxLen > 22) {
          flexes[c] = 4;
        } else if (maxLen > 14) {
          flexes[c] = 3;
        } else if (maxLen > 8) {
          flexes[c] = 2;
        } else {
          flexes[c] = 1;
        }
      }
    }
    return flexes;
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
