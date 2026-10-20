// The bar background: "no colour chosen" means "follow the taskbar".
//
// THE BUG this covers: the config default for `bar_bg_color` (and for the
// global `bg_color`) is "FFFFFFFF", meaning "use the default". Dart passed it
// through the COLORREF -> ARGB conversion, which turned it into opaque WHITE,
// and the native renderer dutifully painted a white rectangle. On a dark
// taskbar that is a bright block; on a light taskbar it is indistinguishable
// from the shell, which hid the mistake on some machines.
//
// The fix sends 0xFFFFFFFF as a sentinel instead, which native resolves by
// sampling the taskbar's own pixels (`kColorFollowTaskbar`). These tests pin
// the Dart half of that contract.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin/core/bar/bar_channel.dart';
import 'package:taskpin/core/bar/bar_controller.dart';
import 'package:taskpin/core/config/config_providers.dart';
import 'package:taskpin/core/config/config_repository.dart';
import 'package:taskpin/core/config/config_schema.dart';
import 'package:taskpin/core/engine/engine_provider.dart';
import 'package:taskpin_engine/taskpin_engine.dart';

import 'dart:async';
import 'dart:io';

/// Keeps the engine provider in `loading` without leaving a pending timer.
///
/// A `Future.delayed` (even a long one) is a pending timer, and `flutter_test`
/// refuses to finish a test that still has one. A `Completer` that is never
/// completed has no timer at all; it is closed by the container's dispose.
List<Override> _noEngine() {
  final Completer<EngineApi> pending = Completer<EngineApi>();
  return <Override>[
    engineProvider.overrideWith((FutureProviderRef<EngineApi> ref) => pending.future),
  ];
}

/// Drives the real controller until the first bar's style has been sent, then
/// returns it.
Future<BarStyleSpec> _styleFor({
  required PinItem item,
  String? globalBg,
}) async {
  final RecordingBarApi api = RecordingBarApi();
  final Directory dir = Directory.systemTemp.createTempSync('tp_bg');
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
          items: <PinItem>[item],
          bgColor: globalBg ?? 'FFFFFFFF',
        ),
      ),
      ..._noEngine(),
    ],
  );
  addTearDown(container.dispose);

  container.read(barControllerProvider);
  // A plain `test`, not `testWidgets`: the controller starts periodic refresh
  // timers, and `testWidgets` asserts that no timer is still pending when the
  // test body returns. Real async here lets the debounce resolve normally.
  await Future<void>.delayed(const Duration(milliseconds: 400));

  expect(api.styles.containsKey(0), isTrue,
      reason: 'the controller never sent a style for bar 0');
  return api.styles[0]!;
}

void main() {
  test('an item with no colour follows the taskbar', () async {
    final BarStyleSpec style = await _styleFor(
      item: PinItem(name: 'clock', pinned: true, luaPath: 'clock.lua'),
    );

    // The sentinel, NOT 0xFFFFFFFF-as-white. They are the same integer; what
    // matters is that this is the value native interprets as "sample the
    // shell", which is why the constant is named for the intent.
    expect(style.background, kFollowTaskbarArgb);
  });

  test('a global colour of the default also follows the taskbar', () async {
    final BarStyleSpec style = await _styleFor(
      item: PinItem(name: 'clock', pinned: true, luaPath: 'clock.lua'),
      globalBg: kColorUseGlobal,
    );
    expect(style.background, kFollowTaskbarArgb);
  });

  test('an explicit item colour is converted, not followed', () async {
    // "FF0000" is a COLORREF: 0x00BBGGRR, so it means BLUE. That inversion is
    // the historical on-disk format and is preserved on purpose (see
    // docs/FLUTTER_REWRITE_PLAN.md, "设置页颜色输入会 R/B 互换").
    final BarStyleSpec style = await _styleFor(
      item: PinItem(
        name: 'clock',
        pinned: true,
        luaPath: 'clock.lua',
        barBgColor: 'FF0000',
      ),
    );
    expect(style.background, 0xFF0000FF);
    expect(style.background, isNot(kFollowTaskbarArgb));
  });

  test('an explicit global colour applies to items that defer to it', () async {
    final BarStyleSpec style = await _styleFor(
      item: PinItem(name: 'clock', pinned: true, luaPath: 'clock.lua'),
      globalBg: '00FF00',
    );
    // COLORREF 0x00FF00 -> green, opaque.
    expect(style.background, 0xFF00FF00);
  });

  test('the shipped global default "00000000" follows the taskbar', () async {
    // Every config.json written by the C layer carries this value. It is
    // opaque black in the old renderer — the bug — and must read as "unset"
    // here so existing installs pick up the taskbar colour with no migration.
    final BarStyleSpec style = await _styleFor(
      item: PinItem(name: 'clock', pinned: true, luaPath: 'clock.lua'),
      globalBg: '00000000',
    );
    expect(style.background, kFollowTaskbarArgb);
  });
}
