// A letter avatar with a deterministic, name-hash fill.
//
// Shared by the project cards and the market cards so one name always has the
// same colour in both places.

import 'package:flutter/material.dart';
import 'package:taskpin_design/taskpin_design.dart';

/// 40 x 40 by default; the stopped project card and the market card both use
/// that size. The letter is the first character of [name], upper-cased.
class TpAvatar extends StatelessWidget {
  const TpAvatar({super.key, required this.name, this.size = 40});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: TpAvatarColor.fillFor(name),
        borderRadius: TpRadius.card,
      ),
      child: Text(
        TpAvatarColor.letterFor(name),
        style: TpTypography.bodyStrong.toTextStyle().copyWith(
              color: TpAvatarColor.text,
            ),
      ),
    );
  }
}
