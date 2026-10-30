// Corner radii (docs/VISUAL_SPEC.md §3.3).
//
// control 8: inputs, tooltips, list row hover. Buttons are pills.
// card 16: grouped surfaces, menus, dialogs.
// pill 999: buttons, switches, badges.
// Windows taskbar segments are square; those values live in `bar_tokens.dart`.

import 'dart:ui' show Radius;

import 'package:flutter/painting.dart';

/// Radius values and their `BorderRadius` forms.
class TpRadius {
  const TpRadius._();

  static const double controlValue = 8;
  static const double cardValue = 16;
  static const double overlayValue = 16;
  static const double windowValue = 8;

  /// The raised slab the stage strip sits on, and the segments inside it.
  static const double slabValue = 16;
  static const double segmentValue = 11;

  /// Fully rounded. Clamped by the renderer to half the shorter side.
  static const double pill = 999;

  /// Buttons, inputs, selects, tooltips, row hover.
  static const BorderRadius control =
      BorderRadius.all(Radius.circular(controlValue));

  /// Cards, list groups, menus, dialogs.
  static const BorderRadius card = BorderRadius.all(Radius.circular(cardValue));

  /// Menus, flyouts, dialogs. Same value as [card].
  static const BorderRadius overlay =
      BorderRadius.all(Radius.circular(overlayValue));

  /// Switches and badges.
  static const BorderRadius chip = BorderRadius.all(Radius.circular(pill));

  /// Stage slab.
  static const BorderRadius slab = BorderRadius.all(Radius.circular(slabValue));

  /// One segment on the stage slab.
  static const BorderRadius segment =
      BorderRadius.all(Radius.circular(segmentValue));

  /// No radius.
  static const BorderRadius none = BorderRadius.zero;

  /// Windows taskbar segment. Frozen — see `bar_tokens.dart`.
  static const double barWindows = 0;

  /// macOS menu-bar segment. Frozen — see `bar_tokens.dart`.
  static const double barMacOS = 6;
}
