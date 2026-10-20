// Bar events survive a Riverpod rebuild.
//
// THE BUG: `BarNotifier.build()` runs again on the SAME Notifier instance when
// a watched dependency changes. Riverpod disposes the previous build's
// listeners first, which called `_stop()` — that cancelled the `taskpin/bar`
// event subscription but left `_started = true`. `_startEvents()` therefore
// returned early on every later reconcile and nothing ever re-subscribed.
//
// Symptom the user saw: Shift+wheel moved a taskbar bar, then it jumped back
// about a second later. Native had moved it and reported the new x; the report
// went nowhere, Dart never wrote `bar_x`, and the next script refresh re-sent
// the bar as auto-tiled, which native snapped back to its tiled slot.
//
// The fix is one line — `_started = false` in `_stop()` — and this test is the
// tripwire for it. It drives the real notifier through a rebuild and asserts
// that events still arrive afterwards.

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin/core/bar/bar_channel.dart';
import 'package:taskpin/core/bar/bar_controller.dart';
import 'package:taskpin/core/config/config_providers.dart';
import 'package:taskpin/core/config/config_repository.dart';
import 'package:taskpin/core/config/config_schema.dart';
import 'package:taskpin/core/engine/engine_provider.dart';
import 'package:taskpin_engine/taskpin_engine.dart';

/// Keeps the engine out of this test. The controller only needs to know that
/// the engine has not resolved; the event path runs regardless.
List<Override> _noEngine() => <Override>[
      engineProvider.overrideWith(
        // A never-completing future keeps the provider in `loading`, which is
        // all the controller needs; but it also blocks dispose, so it is
        // completed on teardown by the container being disposed first.
        (FutureProviderRef<EngineApi> ref) =>
            Future<EngineApi>.delayed(const Duration(days: 1)),
      ),
    ];

void main() {
  test('a wheel event still arrives after the notifier rebuilds', () async {
    final RecordingBarApi api = RecordingBarApi();
    final Directory dir = Directory.systemTemp.createTempSync('tp_resub');
    addTearDown(() => dir.deleteSync(recursive: true));
    final ConfigRepository repository = ConfigRepository(
      paths: ConfigPaths(
        baseDir: dir.path,
        configFile: '${dir.path}/config.json',
        scriptsDir: dir.path,
        portable: false,
      ),
    );
    addTearDown(repository.flush);

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        barApiProvider.overrideWithValue(api),
        configRepositoryProvider.overrideWithValue(repository),
        initialConfigProvider.overrideWithValue(
          TaskPinConfig(
            items: <PinItem>[
              PinItem(name: 'clock', pinned: true, luaPath: 'clock.lua'),
            ],
          ),
        ),
        // The engine is not needed for the event path; an unresolved provider
        // would make the notifier report "engine not ready" and still start
        // the event loop, which is all this test cares about.
        ..._noEngine(),
      ],
    );
    addTearDown(container.dispose);

    // First build: subscribe. The reconcile is debounced 250 ms.
    container.read(barControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // Force a rebuild of the SAME notifier (this is what a config change to a
    // watched dependency does). The dispose of the first build cancels the
    // subscription.
    container.invalidate(barControllerProvider);
    container.read(barControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 400));

    api.emit(BarWheelEvent(0, delta: 0, shift: true, width: 55, x: 900));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // The config write is the observable proof that the event was delivered
    // and routed all the way to `_onWheel`: a Shift+wheel persists bar_x.
    final TaskPinConfig config = container.read(configProvider);
    expect(config.items.first.barX, 900,
        reason: 'the wheel event never reached the controller after rebuild');
  });
}
