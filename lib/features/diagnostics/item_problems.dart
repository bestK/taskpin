// Projects that cannot run right now. This one list feeds both the Logs badge in
// the top nav and the Logs page, so the number and the rows always agree.
//
// Two sources, both already in the app: a broken config (missing or unset
// script, no URL), from `SignalStatus`, and the last run's error on a bar
// snapshot, from `BarNotifier`. The engine's `EngineLog` stream has no consumer
// in the manager, so engine logs are not part of this list.

import 'dart:io';

import '../../app/l10n.dart';
import '../../core/bar/bar_controller.dart';
import '../../core/bar/bar_source.dart' show resolveScriptPath;
import '../../core/config/config_schema.dart';
import '../signals/widgets/item_labels.dart';
import '../signals/widgets/item_status.dart';

/// One project that cannot run, with the text the Logs page shows for it.
class ItemProblem {
  const ItemProblem({
    required this.index,
    required this.name,
    required this.message,
    this.updatedAt,
  });

  /// Index in `config.items`, which is also the bar id.
  final int index;

  /// The display name, as the project list shows it.
  final String name;

  /// The full text: the config problem (with its path) or the run's error.
  final String message;

  /// When the failing run finished. Null for a config problem, which has no
  /// time of its own.
  final DateTime? updatedAt;
}

/// Every project that cannot run, newest failure first.
///
/// Failures with a time come first, newest first. Config problems have no time
/// and follow in config order.
List<ItemProblem> collectItemProblems(
  List<PinItem> items,
  Map<int, BarSnapshot> bars,
  String baseDir,
  AppLocalizations l10n,
) {
  final List<ItemProblem> out = <ItemProblem>[];
  for (int i = 0; i < items.length; i++) {
    final PinItem item = items[i];
    final SignalStatus status = SignalStatus.of(
      item,
      pathExists: (String p) {
        try {
          return File(resolveScriptPath(p, baseDir)).existsSync();
        } on Object {
          return false;
        }
      },
    );
    final String? problem = itemConfigProblem(status, l10n);
    final BarSnapshot? snapshot = bars[i];
    final String? error = snapshot?.error;
    final bool hasError = error != null && error.isNotEmpty;
    if (problem == null && !hasError) continue;

    final String detail = status.detail == null ? '' : ': ${status.detail}';
    out.add(
      ItemProblem(
        index: i,
        name: itemDisplayName(item, i, l10n),
        message: problem == null ? error! : '$problem$detail',
        updatedAt: problem == null ? snapshot?.updatedAt : null,
      ),
    );
  }
  out.sort(_newestFirst);
  return out;
}

int _newestFirst(ItemProblem a, ItemProblem b) {
  final DateTime? x = a.updatedAt;
  final DateTime? y = b.updatedAt;
  if (x == null && y == null) return a.index.compareTo(b.index);
  if (x == null) return 1;
  if (y == null) return -1;
  return y.compareTo(x);
}
