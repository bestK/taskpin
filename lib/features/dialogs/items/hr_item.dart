// A `DI_HR` item — a horizontal rule.
//
// C parity (`lib/script_dialog.c:219-229`): a 1 px line in `RGB(60,60,60)`
// drawn 6 px into the item's box, with 12 px of vertical advance. `TpDivider`
// is the design package's 1 px `border/subtle` rule, which is the same idea
// with the Aurora palette.

import 'package:flutter/widgets.dart';
import 'package:taskpin_design/taskpin_design.dart';

class DialogHrItem extends StatelessWidget {
  const DialogHrItem({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      // 6 px above (C: `line_y = y + 6`) and 6 px below, for the 12 px advance.
      padding: EdgeInsets.symmetric(vertical: TpSpacing.s6),
      child: TpDivider(),
    );
  }
}
