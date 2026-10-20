// The bar controller: config + engine -> the real Windows taskbar.
//
// This is the piece that makes a pinned item actually appear. It:
//
//   1. watches `configProvider` for the pinned items,
//   2. runs each item's script through `engineProvider` (the engine is wired
//      already — this does not stub it),
//   3. converts the result to `TpBarSpan`s and pushes them over `taskpin/bar`,
//   4. handles the events that come back: click, wheel, right-click, hover.
//
// WHY THIS IS A CONTROLLER AND NOT A WIDGET. The bars are native child windows
// of `Shell_TrayWnd`, created by `native/win/bar_window.cpp`. Nothing in Flutter
// draws into the taskbar (see docs/FLUTTER_REWRITE_PLAN.md). So the "view" here
// is a side effect of state, and it has to run whether or not any widget is on
// screen — which is why the refresh loop is a provider, not a widget.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskpin_design/taskpin_design.dart';
import 'package:taskpin_engine/taskpin_engine.dart';

import '../config/config_providers.dart';
import '../config/config_schema.dart';
import '../engine/engine_provider.dart';
import '../../features/dialogs/dialog_spec.dart' as ui;
import '../../features/dialogs/dialog_spec_bridge.dart';
import '../../features/dialogs/inline_dialog_provider.dart';
import '../net/http_providers.dart';
import 'bar_channel.dart';
import 'bar_source.dart';

/// The wire, as a provider so tests can override it.
final Provider<BarApi> barApiProvider = Provider<BarApi>((Ref ref) {
  if (!platformHasBars) {
    return const NoopBarApi();
  }
  final MethodChannelBarApi api = MethodChannelBarApi();
  ref.onDispose(api.dispose);
  return api;
});

/// Whether the user has turned the taskbar bars off.
///
/// A kill switch matters because the bars are native windows in someone else's
/// process: if one misbehaves, the user needs a way to stop it without hunting
/// for the offending item. Persisted, because "off" has to survive a restart to
/// be useful as an escape hatch.
final StateProvider<bool> barsEnabledProvider =
    StateProvider<bool>((Ref ref) => true);

/// The wire value that means "paint the taskbar's own colour".
///
/// Deliberately the same bit pattern as the config's "no colour chosen"
/// default (`kColorUseGlobal`, "FFFFFFFF"), so no schema change is needed: a
/// config written by any earlier version already means this. The native
/// renderer resolves it by sampling the taskbar (`kColorFollowTaskbar`).
const int kFollowTaskbarArgb = 0xFFFFFFFF;

/// What the controller is currently showing.
///
/// A plain immutable snapshot rather than a diffable model: the only consumers
/// are the diagnostics page and tests, and a snapshot is what both want.
@immutable
class BarState {
  const BarState({
    this.bars = const <int, BarSnapshot>{},
    this.enabled = true,
    this.engineReady = false,
    this.lastError,
  });

  /// Keyed by bar id, which is the item's index in `config.items`.
  final Map<int, BarSnapshot> bars;

  final bool enabled;
  final bool engineReady;

  /// The most recent failure worth showing the user, or null.
  final String? lastError;

  BarState copyWith({
    Map<int, BarSnapshot>? bars,
    bool? enabled,
    bool? engineReady,
    String? lastError,
    bool clearError = false,
  }) => BarState(
    bars: bars ?? this.bars,
    enabled: enabled ?? this.enabled,
    engineReady: engineReady ?? this.engineReady,
    lastError: clearError ? null : (lastError ?? this.lastError),
  );

  @override
  String toString() =>
      'BarState(${bars.length} bars, enabled: $enabled, engine: $engineReady'
      '${lastError == null ? '' : ', error: $lastError'})';
}

/// One pinned bar's placement, derived from the config alone.
///
/// The native side owns the actual x of an auto bar (it alone knows where the
/// tray notify area is), so [x] is -1 for those and [autoIndex] is the key it
/// sorts by. Keeping this computation pure and top-level is what makes the
/// ordering testable without a taskbar.
@immutable
class BarPlacement {
  const BarPlacement({
    required this.itemIndex,
    required this.width,
    required this.autoIndex,
    required this.x,
    required this.offset,
  });

  /// Index in `config.items` — the bar id.
  final int itemIndex;

  /// The width sent to native (`bar_width` or the global width).
  final int width;

  /// The item's index among the PINNED items, or -1 when it is explicitly
  /// positioned (`bar_x >= 0`). Native sorts auto bars by this; explicit bars
  /// never participate in tiling.
  final int autoIndex;

  /// The explicit x, or -1 for an auto bar.
  final int x;

  /// The running `width + 2` total of the AUTO bars before this one. This is
  /// the same accumulator native `RelayoutAuto` uses, kept here so the
  /// ordering/offset rule is unit-tested on the Dart side too.
  final int offset;

  bool get isAuto => autoIndex >= 0;
}

/// Compute every pinned bar's placement, in config order.
///
/// Mirrors the native tiling: pinned items only, capped at
/// [ConfigLimits.maxBars], auto bars accumulate `width + 2` while explicit
/// bars contribute no offset (they sit where the user put them).
List<BarPlacement> computeBarPlacements(TaskPinConfig config) {
  final List<BarPlacement> out = <BarPlacement>[];
  int pinnedIndex = 0;
  int autoOffset = 0;

  for (int i = 0; i < config.items.length && out.length < ConfigLimits.maxBars; i++) {
    final PinItem item = config.items[i];
    if (!item.pinned) {
      continue;
    }
    final int width = item.barWidth > 0 ? item.barWidth : config.width;
    final bool auto = item.barX < 0;
    out.add(
      BarPlacement(
        itemIndex: i,
        width: width,
        autoIndex: auto ? pinnedIndex : -1,
        x: auto ? -1 : item.barX,
        offset: autoOffset,
      ),
    );
    if (auto) {
      autoOffset += width + 2;
    }
    pinnedIndex++;
  }
  return out;
}

/// The placement of [itemIndex], or null when it is not pinned (or is past the
/// bar cap).
BarPlacement? placementFor(TaskPinConfig config, int itemIndex) {
  for (final BarPlacement p in computeBarPlacements(config)) {
    if (p.itemIndex == itemIndex) {
      return p;
    }
  }
  return null;
}

/// One bar as the controller last pushed it.
@immutable
class BarSnapshot {
  const BarSnapshot({
    required this.itemIndex,
    required this.width,
    required this.x,
    required this.state,
    required this.spanCount,
    required this.text,
    this.content = const TpBarContent(),
    this.updatedAt,
    this.error,
  });

  final int itemIndex;
  final int width;
  final int x;
  final BarItemState state;
  final int spanCount;

  /// Plain-text rendering, for diagnostics and tests.
  final String text;

  /// The spans last pushed, so the project list can render the same output
  /// with the script's own colours.
  final TpBarContent content;

  /// When this snapshot was produced.
  final DateTime? updatedAt;

  /// The script's error, when it failed. Never rendered onto the bar itself —
  /// that is the behaviour this ABI was designed to stop (`ScriptResult.error`
  /// docs).
  final String? error;
}

/// The controller.
///
/// `build()` returns an empty state and the work is kicked off in a
/// `ref.listen` on the config, so the provider is inert until something reads
/// it. `barHostProvider` below is what keeps it alive.
final NotifierProvider<BarNotifier, BarState> barControllerProvider =
    NotifierProvider<BarNotifier, BarState>(BarNotifier.new);

class BarNotifier extends Notifier<BarState> {
  /// bar id -> the `PinItem` instance it was last built from, so a config
  /// change can tell "same item, new content" from "a different item now owns
  /// this id" (which is exactly what `moveItem` does, because bar ids are
  /// config indices).
  final Map<int, PinItem> _itemForBar = <int, PinItem>{};

  /// bar id -> the last width/x we pushed, so a native geometry report can be
  /// compared against it and a no-op change does not cause a config write.
  final Map<int, BarGeometrySnapshot> _geometry = <int, BarGeometrySnapshot>{};

  /// Items with a fetch in flight, so a slow item cannot pile up overlapping
  /// runs when its interval is shorter than its latency.
  ///
  /// Keyed by the item itself, not by its config index: `moveItem` renumbers
  /// indices, and an index-keyed set would either block the item that moved
  /// into it or let the same item run twice.
  final Set<PinItem> _inFlight = <PinItem>{};

  StreamSubscription<BarEvent>? _events;
  final List<Timer> _timers = <Timer>[];

  /// Set once, so `dispose()` can stop the event loop.
  bool _started = false;

  @override
  BarState build() {
    final bool enabled = ref.watch(barsEnabledProvider);
    // The engine is watched so a failure to load is visible in the state
    // rather than only in a log.
    final AsyncValue<EngineApi> engine = ref.watch(engineProvider);

    // A config change is the only thing that should re-push content, so the
    // whole loop is driven from here rather than from a widget build.
    ref.listen<TaskPinConfig>(configProvider, (TaskPinConfig? prev, TaskPinConfig next) {
      _schedule(next);
    });

    ref.onDispose(_stop);

    // Defer the first pass to after `build()` returns: a Notifier must not
    // mutate its own state while it is being constructed.
    Future<void>.microtask(() => _schedule(ref.read(configProvider)));

    return BarState(enabled: enabled, engineReady: engine.hasValue);
  }

  // ---- scheduling ---------------------------------------------------------

  /// Reconcile the set of bars with the config, then refresh their content.
  ///
  /// Debounced: `editItem` is called on every keystroke in the editor, and a
  /// rebuild per keystroke would spawn a script run per keystroke.
  Timer? _debounce;

  void _schedule(TaskPinConfig config) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_reconcile(config));
    });
  }

  Future<void> _reconcile(TaskPinConfig config) async {
    if (!ref.read(barsEnabledProvider)) {
      await _removeAll();
      return;
    }

    _startEvents();

    // ---- which bars should exist ----
    //
    // `ConfigLimits.maxBars` (16) is a real cap: `src/bar_window.c:445` stops
    // creating bars at that count, so a 17th pinned item silently never
    // appeared. Enforcing it here makes the truncation visible instead.
    //
    // The ordering key for auto tiling is the index among PINNED items, NOT
    // the config index: `moveItem` renumbers every config index, and a key
    // that changed on every reorder would not describe a stable order. The
    // placement helper is pure, so the rule is unit-tested.
    final List<BarPlacement> placements = computeBarPlacements(config);
    final Set<int> wantedSet = <int>{
      for (final BarPlacement p in placements) p.itemIndex,
    };

    final BarApi api = ref.read(barApiProvider);

    // Drop bars whose item was unpinned or deleted, and forget everything we
    // attributed to them — a stale snapshot under a re-used index is worse
    // than no snapshot.
    for (final int id in _itemForBar.keys.toList()) {
      if (!wantedSet.contains(id)) {
        await api.remove(id);
        _forgetBar(id);
      }
    }

    // Every item that is not pinned also loses its snapshot NOW, not on the
    // next content refresh: a reorder/pin/unpin is exactly when the UI would
    // otherwise show one card's result under another card's index.
    for (final int id in <int>{
      ..._lastPushed.keys,
      ..._lastResult.keys,
    }) {
      final bool stillPinned = id >= 0 &&
          id < config.items.length &&
          config.items[id].pinned &&
          _itemForBar.containsKey(id);
      if (!stillPinned) {
        _lastPushed.remove(id);
        _lastResult.remove(id);
      }
    }

    // ---- re-tile ----
    //
    // Auto bars get x = -1 plus their autoIndex; native sorts by that key and
    // re-tiles the whole set in one pass, so a change to any width, any
    // ordering key or the set itself moves every later bar. Explicit bars
    // (`bar_x >= 0`) send their exact x and are never touched by that pass.
    for (final BarPlacement p in placements) {
      final int index = p.itemIndex;
      final PinItem item = config.items[index];
      final int x = p.isAuto ? -1 : p.x;

      final bool isNew = !_itemForBar.containsKey(index);
      final bool itemChanged = !identical(_itemForBar[index], item);
      _itemForBar[index] = item;

      if (itemChanged) {
        // A different item now owns this id: nothing we remember about the old
        // one may be applied to it. (The native window itself is re-used —
        // only its content is stale, and the refresh below replaces it.)
        _lastPushed.remove(index);
        _lastResult.remove(index);
      }

      if (isNew) {
        await api.setStyle(index, _styleFor(item, config));
        // A placeholder so a bar appears immediately, before its first script
        // run finishes — otherwise a slow script means no bar at all for
        // several seconds, which reads as "pinning did nothing".
        await api.setSpans(
          index,
          <Map<String, dynamic>>[
            <String, dynamic>{'text': _label(item)},
          ],
          width: p.width,
          x: x,
          autoIndex: p.autoIndex,
          title: _label(item),
        );
      } else {
        await api.setGeometry(
          index,
          width: p.width,
          x: x,
          autoIndex: p.autoIndex,
        );
      }
      _geometry[index] = BarGeometrySnapshot(
        width: p.width,
        x: x,
        autoIndex: p.autoIndex,
      );
    }

    await _refreshContent(config);

    state = state.copyWith(
      enabled: true,
      engineReady: ref.read(engineProvider).hasValue,
      bars: _snapshot(config),
    );

    _restartTimers(config);
  }

  // ---- content ------------------------------------------------------------

  /// Run every pinned item's script and push the result.
  Future<void> _refreshContent(TaskPinConfig config) async {
    final AsyncValue<EngineApi> engineAsync = ref.read(engineProvider);
    final EngineApi? engine = engineAsync.valueOrNull;

    for (final int index in _itemForBar.keys.toList()) {
      if (index >= config.items.length) continue;
      final PinItem item = config.items[index];
      if (!item.pinned) continue;
      await _refreshOne(engine, item, index, config);
    }
  }

  /// One item, one script run.
  ///
  /// Everything written back is guarded by [_itemForBar] still mapping [index]
  /// to [item]: a run started before a reorder finishes after it, and its
  /// result must not be attributed to the item that now owns that index.
  Future<void> _refreshOne(
    EngineApi? engine,
    PinItem item,
    int index,
    TaskPinConfig config,
  ) async {
    if (_inFlight.contains(item)) return;
    _inFlight.add(item);
    try {
      final BarApi api = ref.read(barApiProvider);
      final TpBarContent content;
      bool failed;
      String? error;
      ScriptResult? result;

      if (engine == null) {
        // The engine is still coming up (or failed to load). Show the item's
        // name rather than an empty bar, and say why in the state.
        content = TpBarContent(
          spans: <TpBarSpan>[TpBarSpan(text: _label(item))],
        );
        failed = true;
        error = ref.read(engineProvider).error?.toString();
        state = state.copyWith(engineReady: false, lastError: error);
      } else {
        final ResolvedBarContent resolved = await resolveContent(
          engine: engine,
          item: item,
          fetcher: ref.read(httpFetcherProvider),
          baseDirectory: ref.read(configRepositoryProvider).paths.baseDir,
        );
        content = resolved.content;
        failed = resolved.failed;
        error = resolved.error;
        result = resolved.result;
      }

      // The config may have been reordered while the script ran. If this index
      // now belongs to another item, drop the result instead of drawing it
      // under the wrong card.
      if (!identical(_itemForBar[index], item)) {
        return;
      }
      if (result != null) {
        _lastResult[index] = result;
      }

      final BarGeometrySnapshot geometry = _geometryFor(item, index, config);

      final BarItemState itemState =
          failed ? BarItemState.error : BarItemState.running;
      await api.setStyle(index, _styleFor(item, config, state: itemState));
      await api.setSpans(
        index,
        contentToWire(content, defaultFontSize: _fontSizeFor(item, config)),
        width: geometry.width,
        x: geometry.x,
        autoIndex: geometry.autoIndex,
        title: _label(item),
      );

      // A reconcile may have run while the channel call was in flight, giving
      // this index to another item. Do not record this run as that item's.
      if (!identical(_itemForBar[index], item)) {
        return;
      }

      _lastPushed[index] = BarSnapshot(
        itemIndex: index,
        width: geometry.width,
        x: geometry.x,
        state: itemState,
        spanCount: content.spans.length,
        text: content.plainText,
        content: content,
        updatedAt: DateTime.now(),
        error: error,
      );
    } on Object catch (e) {
      // A single item must never take the loop down.
      if (!identical(_itemForBar[index], item)) return;
      final BarPlacement? placement = placementFor(config, index);
      _lastPushed[index] = BarSnapshot(
        itemIndex: index,
        width: _geometry[index]?.width ?? _widthFor(item, config),
        // An auto bar's x is native's to choose, so never report a made-up 0.
        x: _geometry[index]?.x ??
            ((placement != null && placement.isAuto) ? -1 : item.barX),
        state: BarItemState.error,
        spanCount: 0,
        text: '',
        updatedAt: DateTime.now(),
        error: e.toString(),
      );
    } finally {
      _inFlight.remove(item);
      _publishSnapshots();
    }
  }

  /// The geometry to send for [index].
  ///
  /// PLACEMENT MODE COMES FROM THE CONFIG, NOT FROM THE CACHE.
  ///
  /// The cache exists so a script refresh re-sends the width and x that are
  /// already on screen instead of recomputing them. It must not decide whether
  /// a bar is auto-tiled, because that decision is the user's and lives in
  /// `bar_x`:
  ///
  ///   Shift+wheel moves a bar by hand. Native records it (`m_auto_index = -1`)
  ///   and reports the new x; Dart writes `bar_x = x` and saves. The config
  ///   change schedules a reconcile, but until that runs, the periodic script
  ///   refresh still fires — and it used to read the cached geometry, which
  ///   was computed when the bar was still auto. That sent `autoIndex >= 0`
  ///   back to native, `SetAutoPlacement` turned the bar auto again, and the
  ///   next `RelayoutAuto()` snapped it back to its tiled position. The bar
  ///   appeared to jump home a fraction of a second after the wheel stopped.
  ///
  /// So: `bar_x` decides the mode, every time. The cache only supplies the
  /// width (which native owns while the user is wheeling) and the explicit x
  /// for a bar that is already explicit.
  BarGeometrySnapshot _geometryFor(
    PinItem item,
    int index,
    TaskPinConfig config,
  ) {
    final BarGeometrySnapshot? sent = _geometry[index];

    // An explicit bar stays explicit: its x is whatever is on screen (the
    // cache) or, before the first send, the config.
    if (item.barX >= 0) {
      return BarGeometrySnapshot(
        width: sent?.width ?? _widthFor(item, config),
        x: sent?.x ?? item.barX,
        autoIndex: -1,
      );
    }

    // An auto bar: native owns x, Dart owns the ordering key and width.
    final BarPlacement? p = placementFor(config, index);
    if (p != null) {
      return BarGeometrySnapshot(
        width: sent?.width ?? p.width,
        x: -1,
        autoIndex: p.autoIndex,
      );
    }
    return BarGeometrySnapshot(
      width: sent?.width ?? _widthFor(item, config),
      x: -1,
      autoIndex: -1,
    );
  }

  /// Copies the latest per-bar snapshots into [state] so listeners (the project
  /// list) see each refresh, not only the ones that reconcile the bar set.
  void _publishSnapshots() {
    try {
      state = state.copyWith(bars: _snapshot(ref.read(configProvider)));
    } on Object {
      // The notifier was disposed while a run was in flight.
    }
  }

  final Map<int, BarSnapshot> _lastPushed = <int, BarSnapshot>{};

  Map<int, BarSnapshot> _snapshot(TaskPinConfig config) {
    final Map<int, BarSnapshot> out = <int, BarSnapshot>{};
    for (final MapEntry<int, BarSnapshot> e in _lastPushed.entries) {
      if (_itemForBar.containsKey(e.key)) {
        out[e.key] = e.value;
      }
    }
    return out;
  }

  // ---- events -------------------------------------------------------------

  void _startEvents() {
    if (_started) return;
    _started = true;
    _events = ref.read(barApiProvider).events.listen(_onEvent);
  }

  void _onEvent(BarEvent event) {
    switch (event) {
      case BarClickEvent(:final int barId):
        unawaited(_onClick(barId));
      case BarWheelEvent():
        unawaited(_onWheel(event));
      case BarContextMenuEvent():
        unawaited(_onContextMenu(event));
      case BarHoverEvent():
        // Purely visual: the native side already repainted with
        // `bar/bgHover`. Nothing to do, but the event is part of the frozen
        // contract so it is deliberately handled rather than ignored.
        break;
    }
  }

  /// A left click opens the item's URL, or its dialog.
  ///
  /// Parity with `src/bar_window.c`: a click only acts when the script said it
  /// is clickable (`result.clickable`), and what it does is
  /// `result.click_action` — a URL via the shell, or a dialog window.
  Future<void> _onClick(int barId) async {
    final int? index = _indexFor(barId);
    if (index == null) return;
    final PinItem item = ref.read(configProvider).items[index];
    if (!item.clickEnabled) return;

    if (item.clickUrl.isNotEmpty) {
      await _openUrl(item.clickUrl);
      return;
    }

    // No URL configured: the script itself decides, and its dialog is the
    // click-through payload.
    final ScriptResult? result = _lastResult[index];
    if (result == null || !result.clickable) return;
    if (result.clickAction == ClickAction.dialog) {
      // Inline dialogs are the default presentation (see
      // `features/dialogs/inline_dialog_provider.dart` for why a second window
      // was abandoned). The seam stays: a test or an alternative host can
      // override `dialogOpenerProvider` and take the click instead.
      final DialogOpener? custom = ref.read(dialogOpenerProvider);
      if (custom != null) {
        custom(result.dialog, item.luaPath);
      } else {
        _openInlineDialog(result.dialog, item.luaPath);
      }
    } else if (result.clickUrl.isNotEmpty) {
      await _openUrl(result.clickUrl);
    }
  }

  /// Show [dialog] as an inline panel over the manager window.
  ///
  /// The engine's `DialogSpec` is a different type from the UI's (one mirrors
  /// the C ABI, the other is the renderer's model); the bridge converts.
  ///
  /// [luaPath] is what the panel re-runs on the spec's `@refresh` interval.
  void _openInlineDialog(DialogSpec spec, String luaPath) {
    final ui.DialogSpec? uiSpec = uiSpecFromEngine(spec);
    if (uiSpec == null) return;
    ref.read(inlineDialogProvider.notifier).open(uiSpec, luaPath: luaPath);
  }

  /// The wheel changed a bar's width or x. Persist it.
  ///
  /// The native side already moved the window (its own handler is the one that
  /// received the message, and it clamps 50..800 exactly as the C layer does),
  /// so this must NOT re-issue `setGeometry` — only write the config. That is
  /// why a native `onWheel` is allowed to carry `delta == 0`.
  ///
  /// A Shift+wheel is an explicit placement: persist the new x so the item
  /// becomes `bar_x >= 0` (native already stopped auto-tiling it). A plain
  /// wheel keeps the item's placement mode — and, for an auto bar, must NOT
  /// persist x = -1: the reported x is the tiled position, not a user choice.
  Future<void> _onWheel(BarWheelEvent event) async {
    final int? index = _indexFor(event.barId);
    if (index == null) return;

    final BarGeometrySnapshot? prev = _geometry[event.barId];
    final bool wasAuto = prev?.isAuto ?? false;
    // An auto bar's stored x is -1 (native owns it), so only the width can be
    // compared for a plain wheel on one.
    // A Shift+wheel that clamped at the same x still changes the placement
    // MODE (native stopped auto-tiling the bar), so it must be persisted even
    // though the geometry did not move.
    if (!event.shift &&
        prev != null &&
        prev.width == event.width &&
        (wasAuto || prev.x == event.x)) {
      return; // nothing actually changed; do not touch the config
    }
    _geometry[event.barId] = BarGeometrySnapshot(
      width: event.width,
      // Keep the invariant that an auto bar's stored x is -1: a native
      // report of its tiled position is not a position Dart chose.
      x: event.shift ? event.x : (wasAuto ? -1 : event.x),
      autoIndex: event.shift ? -1 : (prev?.autoIndex ?? -1),
    );

    final ConfigNotifier notifier = ref.read(configProvider.notifier);
    notifier.editItem(index, (PinItem i) {
      // The C layer persists BOTH on any wheel (`src/bar_window.c:392`), even
      // the axis that did not move, so the file stays a faithful record of
      // what is on screen. The exception is an auto bar's x: that is native's
      // tiled position, and writing it down would pin the bar there and take
      // it out of the tiling for good.
      i.barWidth = event.width;
      if (event.shift) {
        i.barX = event.x;
      } else if (i.barX >= 0) {
        i.barX = event.x;
      }
    });
    await notifier.flush();
  }

  /// Right click: Unpin / Manage Items... / Exit.
  Future<void> _onContextMenu(BarContextMenuEvent event) async {
    switch (event.action) {
      case BarMenuAction.unpin:
        final int? index = _indexFor(event.barId);
        if (index == null) return;
        final ConfigNotifier notifier = ref.read(configProvider.notifier);
        notifier.togglePinned(index);
        await notifier.flush();
      case BarMenuAction.manage:
        // The manager is the window the user is already in; a bar can be
        // right-clicked while it is minimised, so raise it.
        ref.read(managerRaiserProvider)?.call();
      case BarMenuAction.exit:
        ref.read(exitRequestProvider)?.call();
    }
  }

  /// The item index behind a bar id, or null when the bar is gone.
  int? _indexFor(int barId) {
    if (!_itemForBar.containsKey(barId)) return null;
    final TaskPinConfig config = ref.read(configProvider);
    if (barId < 0 || barId >= config.items.length) return null;
    return barId;
  }

  /// Forget everything keyed by [id] when its bar is torn down.
  ///
  /// Bar ids are config indices and are re-used: after an unpin + delete the
  /// next item can inherit an id that already has a snapshot, a script result
  /// and a geometry. Those would then be shown for the new card, so all three
  /// maps are cleared together.
  void _forgetBar(int id) {
    _itemForBar.remove(id);
    _geometry.remove(id);
    _lastPushed.remove(id);
    _lastResult.remove(id);
  }

  /// Open a URL, through the injected opener when one was provided.
  ///
  /// The seam exists so tests do not shell out; in the app `main()` installs
  /// [openUrlWithShell], which is the same `ShellExecuteW(..., L"open", ...)`
  /// behaviour the C layer has.
  Future<void> _openUrl(String url) async {
    final UrlOpener? opener = ref.read(urlOpenerProvider);
    if (opener != null) {
      await opener(url);
    } else {
      await openUrlWithShell(url);
    }
  }

  // ---- style / geometry helpers -------------------------------------------

  /// The configured width: `bar_width` when set, else the global `width`.
  ///
  /// `bar_width` of 0 means "use global" (`src/bar_window.c:453`), which is why
  /// this cannot just use the item's value.
  static int _widthFor(PinItem item, TaskPinConfig config) =>
      item.barWidth > 0 ? item.barWidth : config.width;

  /// The point size for spans that do not carry one.
  static int _fontSizeFor(PinItem item, TaskPinConfig config) =>
      config.fontSize > 0 ? config.fontSize : kBarDefaultFontSize;

  /// The item's `bar_bg_color`, as ARGB, or null when it means "use global".
  ///
  /// The config stores a Win32 COLORREF as a BGR hex string
  /// (`lib/config.c:78-85`), which is the opposite byte order from the ARGB the
  /// renderer wants — so this is the one place that conversion must happen.
  /// The item's background as an ARGB int, or null for the token default.
  ///
  /// "No colour chosen" is not the same as "white". The config default is
  /// `FFFFFFFF` (for the item and for the global), and the native renderer
  /// treats that value as a request to sample the taskbar's own colour — see
  /// `kColorFollowTaskbar` in `native/win/bar_tokens.h`. Passing it through
  /// `colorrefToArgb` would turn it into opaque white, which is how a bar
  /// could end up a bright rectangle on a dark taskbar.
  /// Whether a colour string means "nothing was chosen".
  ///
  /// `FFFFFFFF` is the documented sentinel. `00000000` is what the shipped
  /// `config.json` files actually contain at the global level: the C layer's
  /// default, written before the sentinel existed, and — despite the C
  /// comment calling it transparent — rendered as opaque black. Treating it
  /// as "unset" is what lets those existing installs start following the
  /// taskbar without a migration.
  static bool _isUnsetColor(String wire) {
    final String t = wire.trim().toUpperCase();
    return t == '00000000' || t == '0X00000000';
  }

  static int? _backgroundFor(PinItem item, TaskPinConfig config) {
    // The sentinel means different things at the two levels:
    //
    //   item  `FFFFFFFF` -> "defer to the global setting"
    //   global `FFFFFFFF` -> "no colour chosen" -> follow the taskbar
    //
    // The shipped config has exactly that pair (`bar_bg_color: "FFFFFFFF"`
    // everywhere, `bg_color: "00000000"`), so collapsing the two would
    // silently ignore a global colour the user did set.
    if (ConfigColor.isUseGlobal(item.barBgColor)) {
      // `00000000` is what the shipped configs carry and what the C layer
      // wrote for "not set" (the plan notes it is opaque black in practice,
      // which is the bug being fixed here). Treating it as "no colour" is
      // what makes the default follow the taskbar instead of painting black.
      if (ConfigColor.isUseGlobal(config.bgColor) ||
          _isUnsetColor(config.bgColor)) {
        return kFollowTaskbarArgb;
      }
      final int? global = ConfigColor.tryParse(config.bgColor);
      return global == null ? null : ConfigColor.colorrefToArgb(global);
    }

    final int? raw = ConfigColor.tryParse(item.barBgColor);
    if (raw == null) {
      return null;
    }
    return ConfigColor.colorrefToArgb(raw);
  }

  static BarStyleSpec _styleFor(
    PinItem item,
    TaskPinConfig config, {
    BarItemState state = BarItemState.none,
  }) => BarStyleSpec(
    background: _backgroundFor(item, config),
    fontSize: _fontSizeFor(item, config),
    state: state,
    scrollEnabled: config.scrollEnabled,
  );

  static String _label(PinItem item) =>
      item.name.trim().isNotEmpty ? item.name.trim() : 'TaskPin';

  // ---- lifecycle ----------------------------------------------------------

  /// Restart the per-item refresh timers from the config.
  ///
  /// Each item's interval is its own (`interval_ms`), and the native side has
  /// no business owning that: it is the Dart side that knows when a fetch is
  /// still in flight.
  void _restartTimers(TaskPinConfig config) {
    for (final Timer t in _timers) {
      t.cancel();
    }
    _timers.clear();

    for (final int index in _itemForBar.keys) {
      if (index >= config.items.length) continue;
      final PinItem item = config.items[index];
      if (!item.pinned) continue;
      final int ms = item.intervalMs > 0 ? item.intervalMs : 5000;
      _timers.add(
        Timer.periodic(Duration(milliseconds: ms), (_) {
          // Resolve the index at FIRE time: a reorder between two ticks
          // renumbers items, and a captured index would refresh whichever
          // item now owns it.
          final TaskPinConfig live = ref.read(configProvider);
          final int at = live.items.indexOf(item);
          if (at < 0 || !identical(_itemForBar[at], item)) return;
          unawaited(_refreshOne(
            ref.read(engineProvider).valueOrNull,
            item,
            at,
            live,
          ));
        }),
      );
    }
  }

  Future<void> _removeAll() async {
    if (_itemForBar.isEmpty) return;
    await ref.read(barApiProvider).removeAll();
    _itemForBar.clear();
    _geometry.clear();
    _lastPushed.clear();
    _lastResult.clear();
    _inFlight.clear();
    for (final Timer t in _timers) {
      t.cancel();
    }
    _timers.clear();
    state = state.copyWith(bars: const <int, BarSnapshot>{}, enabled: false);
  }

  void _stop() {
    _debounce?.cancel();
    _debounce = null;
    for (final Timer t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _events?.cancel();
    _events = null;
    // THE SUBSCRIPTION FLAG MUST BE CLEARED TOO.
    //
    // Riverpod re-runs `build()` on the SAME Notifier instance when a watched
    // dependency changes (it disposes the previous build's listeners first).
    // That dispose calls this method, which cancels the channel subscription.
    // Leaving `_started = true` then made `_startEvents()` return early on the
    // next reconcile, so nothing ever re-subscribed: wheel and click events
    // stopped arriving for the rest of the session.
    //
    // That is what made Shift+wheel "jump back": native moved the bar and
    // reported it, the report went nowhere, Dart never wrote `bar_x`, and the
    // next script refresh re-sent the bar as auto-tiled — which native then
    // snapped back to its tiled x.
    _started = false;
  }

  /// The last script result per item, kept for the click path (which needs
  /// `clickable` / `click_action`, neither of which is in [BarSnapshot]).
  final Map<int, ScriptResult> _lastResult = <int, ScriptResult>{};
}

/// A width/x pair plus the placement mode, so the controller can tell a real
/// geometry change from a report of the current position.
@immutable
class BarGeometrySnapshot {
  const BarGeometrySnapshot({
    required this.width,
    required this.x,
    this.autoIndex = -1,
  });

  final int width;

  /// The x we last sent, or -1 for an auto bar (native owns its x).
  final int x;

  /// The ordering key we last sent; -1 = explicitly positioned.
  final int autoIndex;

  bool get isAuto => autoIndex >= 0;

  @override
  bool operator ==(Object other) =>
      other is BarGeometrySnapshot &&
      other.width == width &&
      other.x == x &&
      other.autoIndex == autoIndex;

  @override
  int get hashCode => Object.hash(width, x, autoIndex);
}

// ---------------------------------------------------------------------------
// Host seams
//
// The controller cannot open a URL, raise a window or quit the app itself
// without dragging `dart:io`, `go_router` and the dialog window into a provider
// that tests must be able to construct. These three are the seams, overridden
// in `main()`.
// ---------------------------------------------------------------------------

/// Opens a URL in the user's default handler.
typedef UrlOpener = Future<void> Function(String url);

/// Opens (or re-raises) a dialog window for a script's `dialog` payload.
///
/// The argument is the ENGINE's `DialogSpec` (from `taskpin_engine`), because
/// that is what `ScriptResult` carries. Turning it into the UI's model is the
/// app layer's job — see `lib/features/dialogs/dialog_spec_bridge.dart`. The
/// two types are deliberately separate (one is an ABI mirror, the other a
/// UI model), and this provider is the seam where they meet.
/// [luaPath] is the script that produced the dialog, so the window can re-run
/// it on the spec's `@refresh` interval. Empty means "no refresh".
typedef DialogOpener = void Function(DialogSpec spec, String luaPath);

/// Raises the manager window.
typedef ManagerRaiser = void Function();

/// Quits the app.
typedef ExitRequester = void Function();

final Provider<UrlOpener?> urlOpenerProvider =
    Provider<UrlOpener?>((Ref ref) => null);

final Provider<DialogOpener?> dialogOpenerProvider =
    Provider<DialogOpener?>((Ref ref) => null);

final Provider<ManagerRaiser?> managerRaiserProvider =
    Provider<ManagerRaiser?>((Ref ref) => null);

final Provider<ExitRequester?> exitRequestProvider =
    Provider<ExitRequester?>((Ref ref) => null);

/// Keeps the controller alive for the whole app.
///
/// `barControllerProvider` is not `autoDispose`, but a `NotifierProvider` that
/// nothing watches is never built at all — so without this the bars would only
/// exist while the diagnostics page happened to be on screen. `main()` starts
/// this by reading it once.
final Provider<void> barHostProvider = Provider<void>((Ref ref) {
  ref.watch(barControllerProvider);
});

/// Open a URL the way the C layer does (`ShellExecuteW(..., L"open", ...)`).
///
/// Deliberately the same `cmd /c start` shape as
/// `features/dialogs/dialog_action.dart`, and for the same measured reasons —
/// see that file's comment on `_spawnDetached`.
Future<void> openUrlWithShell(String url) async {
  if (url.isEmpty) {
    return;
  }
  if (Platform.isWindows) {
    final Process p = await Process.start('cmd', <String>['/c', 'start', '', url]);
    unawaited(p.stdout.drain<void>());
    unawaited(p.stderr.drain<void>());
    unawaited(p.exitCode);
  } else if (Platform.isMacOS) {
    await Process.start('open', <String>[url], mode: ProcessStartMode.detached);
  } else {
    await Process.start('xdg-open', <String>[url], mode: ProcessStartMode.detached);
  }
}
