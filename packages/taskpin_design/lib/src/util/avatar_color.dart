// Deterministic letter-avatar colours.
//
// The same name always gets the same fill, so an item keeps one identity colour
// across the project list and the market grid. Eight muted fills from the token
// layer; the text colour is fixed dark because every fill is a light pastel.

import 'dart:ui' show Color;

import '../tokens/primitives.dart';

/// Fill and text colour for a name's letter avatar.
class TpAvatarColor {
  const TpAvatarColor._();

  /// The fill for [name]. Empty names use the first slot.
  static Color fillFor(String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return TpPrimitives.avatarFills.first;
    int hash = 0;
    for (final int unit in trimmed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return TpPrimitives.avatarFills[hash % TpPrimitives.avatarFills.length];
  }

  /// The text colour on [fillFor].
  static Color get text => TpPrimitives.avatarText;

  /// The letter shown in the avatar: the first character, upper-cased.
  static String letterFor(String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }
}
