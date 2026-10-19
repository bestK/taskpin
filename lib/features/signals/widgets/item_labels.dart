// Text helpers for one project: display name, source label, interval label.
//
// Shared by the project list and the detail page so both show the same text.

import 'package:taskpin_design/taskpin_design.dart';

import '../../../app/l10n.dart';
import '../../../core/config/config_schema.dart';
import 'item_status.dart';

/// Maps the Flutter-free status enum to the design system's state kind.
///
/// No `default:` branch, so a new `TpStateKind` is a compile error here.
TpStateKind tpStateKind(TpStateKindLike like) {
  switch (like) {
    case TpStateKindLike.success:
      return TpStateKind.success;
    case TpStateKindLike.warning:
      return TpStateKind.caution;
    case TpStateKindLike.danger:
      return TpStateKind.critical;
    case TpStateKindLike.info:
      return TpStateKind.info;
    case TpStateKindLike.neutral:
      return TpStateKind.neutral;
  }
}

/// Where an item's data comes from, in one short string.
///
/// A Lua item gives the script's file name. A URL item gives the host, or the
/// raw string when it has no host.
String itemSourceLabel(PinItem item) {
  if (item.type == PinItemType.lua) {
    final String path = item.luaPath.trim();
    if (path.isEmpty) return '';
    final List<String> parts =
        path.split(RegExp(r'[\\/]')).where((String s) => s.isNotEmpty).toList();
    return parts.isEmpty ? path : parts.last;
  }
  final String url = item.url.trim();
  if (url.isEmpty) return '';
  final Uri? parsed = Uri.tryParse(url);
  if (parsed == null || parsed.host.isEmpty) return url;
  return parsed.host;
}

/// The name to show for an item.
///
/// `name` is often empty in existing configs, so an empty name falls back to
/// the source label, then to a numbered label.
String itemDisplayName(PinItem item, int index, AppLocalizations l10n) {
  final String name = item.name.trim();
  if (name.isNotEmpty) return name;

  final String source = itemSourceLabel(item);
  if (source.isNotEmpty) return source;
  return item.type == PinItemType.lua
      ? l10n.projectFallbackLua(index + 1)
      : l10n.projectFallbackUrl(index + 1);
}

/// "every 5 s" in the current language. Uses the largest unit that divides the
/// interval evenly.
String itemIntervalLabel(int intervalMs, AppLocalizations l10n) {
  final int ms = intervalMs > 0 ? intervalMs : 5000;
  if (ms % Duration.millisecondsPerHour == 0) {
    return l10n.projectIntervalHour(ms ~/ Duration.millisecondsPerHour);
  }
  if (ms % Duration.millisecondsPerMinute == 0) {
    return l10n.projectIntervalMin(ms ~/ Duration.millisecondsPerMinute);
  }
  if (ms % Duration.millisecondsPerSecond == 0) {
    return l10n.projectIntervalSec(ms ~/ Duration.millisecondsPerSecond);
  }
  return l10n.projectIntervalMs(ms);
}

/// The text for a config-level problem, or null when there is none.
String? itemConfigProblem(SignalStatus status, AppLocalizations l10n) {
  switch (status.reason) {
    case SignalStatusReason.scriptUnset:
      return l10n.statusScriptUnset;
    case SignalStatusReason.scriptMissing:
      return l10n.statusScriptMissing;
    case SignalStatusReason.urlUnset:
      return l10n.statusUrlUnset;
    case SignalStatusReason.pinned:
    case SignalStatusReason.notPinned:
      return null;
  }
}
