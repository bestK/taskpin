// Shadows (docs/VISUAL_SPEC.md §3.4). Cards have no shadow.

import 'package:flutter/painting.dart';

import 'primitives.dart';

/// Shadow values for floating surfaces.
class TpElevation {
  const TpElevation._();

  /// Menus, dropdowns, tooltips: `0 8 16`.
  static List<BoxShadow> flyout({required bool isDark}) => <BoxShadow>[
        BoxShadow(
          color: TpPrimitives.black.withValues(alpha: isDark ? 0.26 : 0.14),
          offset: const Offset(0, 8),
          blurRadius: 16,
        ),
      ];

  /// Dialogs: `0 32 64`.
  static List<BoxShadow> dialog({required bool isDark}) => <BoxShadow>[
        BoxShadow(
          color: TpPrimitives.black.withValues(alpha: isDark ? 0.37 : 0.18),
          offset: const Offset(0, 32),
          blurRadius: 64,
        ),
      ];
}
