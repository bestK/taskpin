// Riverpod wiring for the config layer.
//
// `ConfigRepository` is created once in `main()` (it must resolve paths and run
// migration before the first frame) and injected here. `configProvider` is the
// live, mutable view the UI reads and writes; every mutation saves through the
// repository's debounce, so a rapid sequence of edits (dragging a bar width,
// typing in a field) coalesces into one write.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config_repository.dart';
import 'config_schema.dart';

/// Overridden in `main()` with the instance that already ran migration.
final Provider<ConfigRepository> configRepositoryProvider =
    Provider<ConfigRepository>((Ref ref) {
  throw UnimplementedError(
    'configRepositoryProvider must be overridden in main() — the repository '
    'resolves paths and runs migration before the first frame.',
  );
});

/// Overridden in `main()` with the config loaded before `runApp`.
final Provider<TaskPinConfig> initialConfigProvider =
    Provider<TaskPinConfig>((Ref ref) {
  throw UnimplementedError('initialConfigProvider must be overridden in main()');
});

/// The live config.
///
/// The model classes are deliberately mutable (their fields mirror the C
/// structs, which the C layer mutates in place). Mutating through the notifier
/// keeps persistence in one place: call a method here rather than writing to a
/// `PinItem` field directly, or the change will not be saved.
final NotifierProvider<ConfigNotifier, TaskPinConfig> configProvider =
    NotifierProvider<ConfigNotifier, TaskPinConfig>(ConfigNotifier.new);

class ConfigNotifier extends Notifier<TaskPinConfig> {
  @override
  TaskPinConfig build() => ref.watch(initialConfigProvider);

  ConfigRepository get _repository => ref.read(configRepositoryProvider);

  /// Persists the current state and tells listeners it changed. Call after
  /// mutating.
  ///
  /// The model is mutated in place, so `state` keeps the same identity and
  /// Riverpod would not notify on its own.
  void save() {
    _repository.save(state);
    ref.notifyListeners();
  }

  int addItem(PinItem item) {
    state.items.add(item);
    save();
    return state.items.length - 1;
  }

  void removeItemAt(int index) {
    if (index < 0 || index >= state.items.length) return;
    state.items.removeAt(index);
    save();
  }

  /// Moves the item at [from] to sit at [to], then saves. Used by the
  /// taskbar preview's drag reorder.
  void moveItem(int from, int to) {
    final int n = state.items.length;
    if (from < 0 || from >= n || to < 0 || to >= n || from == to) return;
    final PinItem item = state.items.removeAt(from);
    state.items.insert(to, item);
    save();
  }

  /// Toggles the pinned flag, which is what makes a bar appear in the taskbar.
  void togglePinned(int index) {
    if (index < 0 || index >= state.items.length) return;
    state.items[index].pinned = !state.items[index].pinned;
    save();
  }

  /// Applies [mutate] to the item at [index], then saves. The usual way to edit
  /// a field without forgetting persistence.
  void editItem(int index, void Function(PinItem) mutate) {
    if (index < 0 || index >= state.items.length) return;
    mutate(state.items[index]);
    save();
  }

  /// Applies [mutate] to the global settings block, then saves.
  void editGlobal(void Function(TaskPinConfig) mutate) {
    mutate(state);
    save();
  }

  /// Writes any pending debounced change immediately. Call before the window
  /// closes so an edit made in the last 500 ms is not lost.
  Future<void> flush() => _repository.flush();
}
