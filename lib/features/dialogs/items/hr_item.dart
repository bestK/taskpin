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
      // VISUAL_SPEC §8: the rule sits 8 px above and below. The dialog adds no
      // gap next to a rule, so this padding is the whole spacing on each side.
      padding: EdgeInsets.symmetric(vertical: TpSpacing.s8),
      child: TpDivider(),
    );
  }
}
