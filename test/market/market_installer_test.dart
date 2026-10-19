// The market installer: the anti-regression test for the bug in commit 4f5165c.
//
// ─────────────────────────────────────────────────────────────────────────────
// WHAT IS BEING PINNED
// ─────────────────────────────────────────────────────────────────────────────
// The old market's download wrote the `.lua` into `scripts/` and never touched
// the config, so nothing appeared in the item list and `config.json` was
// unchanged — while the status line already read `market.download_success`
// ("下载并添加成功"). The button lied.
//
// `4f5165c` fixed it in `src/ui_market_view.cpp` (the ImGui view, not
// `src/market_dialog.c`, which still has the bug). The invariant below is the
// one that fix established, and the one this suite exists to keep:
//
//     outcome is `installed` or `updated`
//       => the item IS in the config
//       AND the config WAS persisted
//
// The `persist` callback is a counter, so "was persisted" is asserted directly
// rather than inferred.
//
// Files are written to a real temp directory (this is a `dart:io` test, not a
// Flutter widget test), and removed in tearDown.

import 'dart:convert';
import 'dart:io';

import 'package:taskpin/core/config/config_schema.dart';
import 'package:taskpin/core/market/market_installer.dart';
import 'package:taskpin/core/market/market_models.dart';
import 'package:test/test.dart';

import '../support/fakes.dart';

void main() {
  late Directory tempDir;
  late String scriptsDir;
  late FakeFetcher fetcher;
  late int persistCount;
  late TaskPinConfig config;
  late MarketInstaller installer;

  const String scriptBody = '''
-- docker_status.lua - Docker 容器状态监控
-- @param DOCKER_HOST string Docker Host
-- @param TIMEOUT number 超时秒数
-- @refresh 5000

return font("Docker", "#4FC3F7")
''';

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('taskpin_market_test_');
    scriptsDir = '${tempDir.path}${Platform.pathSeparator}scripts';
    fetcher = FakeFetcher();
    persistCount = 0;
    config = TaskPinConfig();
    installer = MarketInstaller(
      scriptsDir: scriptsDir,
      fetcher: fetcher,
      persist: () async => persistCount++,
      inChina: false,
    );
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  MarketScript script({String file = 'docker_status.lua', String name = 'Docker'}) =>
      MarketScript(
        name: name,
        file: file,
        description: 'Docker 容器状态监控',
        author: 'bestK',
        version: '1.0',
        sourceRepo: 'bestK/taskpin-plugins',
      );

  /// Registers the download for [file] with [body].
  ///
  /// The body is UTF-8 encoded, NOT `codeUnits`. `codeUnits` yields UTF-16 code
  /// units, so any character above U+00FF (every CJK glyph in `scriptBody`)
  /// becomes a value > 255 that `writeAsBytes` truncates to a single byte. The
  /// file on disk then holds invalid UTF-8, `readAsString` throws, and the
  /// `@param` parse silently yields nothing — which looked like an installer
  /// bug but was this harness mangling the fixture.
  void serve(String file, String body) {
    fetcher.onBytes('/$file', utf8.encode(body));
  }

  group('the invariant: item added AND config saved', () {
    test('a first install writes the file, adds the item, and persists', () async {
      serve('docker_status.lua', scriptBody);

      final InstallResult result = await installer.install(script(), config);

      expect(result.outcome, InstallOutcome.installed);
      expect(result.configChanged, isTrue);
      expect(result.fileWritten, isTrue);

      // The file is on disk, in scripts/, under its own name.
      final File onDisk = File(result.filePath);
      expect(onDisk.existsSync(), isTrue);
      expect(onDisk.readAsStringSync(), scriptBody);
      expect(onDisk.parent.path, scriptsDir);

      // The item is in the config...
      expect(config.items, hasLength(1));
      final PinItem item = config.items.single;
      expect(item.type, PinItemType.lua);
      expect(item.luaPath, result.filePath);
      expect(item.name, 'Docker');

      // ...and the config was persisted. This is the assertion the old market
      // would have failed.
      expect(persistCount, 1, reason: 'the config MUST be saved on install');
      expect(result.itemIndex, 0);
    });

    test('the item defaults match the C fix', () async {
      serve('docker_status.lua', scriptBody);
      await installer.install(script(), config);

      final PinItem item = config.items.single;
      expect(item.barX, -1);
      expect(item.barY, -1);
      expect(item.barBgColor, kColorUseGlobal);
      expect(item.pinned, isFalse, reason: 'installing does not pin');
    });

    test('a script with no @refresh gets the 5000 ms default', () async {
      serve('plain.lua', '-- plain.lua\nreturn font("x")\n');
      await installer.install(script(file: 'plain.lua'), config);
      expect(config.items.single.intervalMs, 5000);
    });

    test('a script with @refresh gets that value', () async {
      serve('docker_status.lua', scriptBody);
      await installer.install(script(), config);
      expect(config.items.single.intervalMs, 5000);
    });

    test('a @refresh below the 1000 ms floor becomes 5000', () async {
      // `if (refresh_ms < 1000) refresh_ms = 5000;` in the C fix.
      serve('fast.lua', '-- @refresh 200\nreturn font("x")\n');
      await installer.install(script(file: 'fast.lua'), config);
      expect(config.items.single.intervalMs, 5000);
    });

    test('a @refresh of exactly 1000 is kept', () async {
      serve('fast.lua', '-- @refresh 1000\nreturn font("x")\n');
      await installer.install(script(file: 'fast.lua'), config);
      expect(config.items.single.intervalMs, 1000);
    });
  });

  group('@param seeding', () {
    test('declarations become params with empty values', () async {
      serve('docker_status.lua', scriptBody);
      await installer.install(script(), config);

      final List<ParamEntry> params = config.items.single.params;
      expect(params, hasLength(2));
      expect(params[0].key, 'DOCKER_HOST');
      expect(params[0].label, 'Docker Host');
      expect(params[0].value, '');
      expect(params[1].key, 'TIMEOUT');
      expect(params[1].label, '超时秒数');
    });

    test('re-downloading PRESERVES a value the user already filled in', () async {
      // The C fix's `old[]`/`memcpy` dance exists so an updated script does not
      // silently wipe a saved API token. This is that guarantee.
      serve('docker_status.lua', scriptBody);
      await installer.install(script(), config);

      config.items.single.params[0].value = 'tcp://192.168.1.10:2375';
      config.items.single.params[1].value = '30';

      // Re-download, now with an extra declaration and the values in place.
      const String updated = '''
-- docker_status.lua
-- @param DOCKER_HOST string Docker Host
-- @param TIMEOUT number 超时秒数
-- @param NEW_KEY string 新参数
-- @refresh 5000
return font("Docker")
''';
      serve('docker_status.lua', updated);
      final InstallResult result = await installer.install(script(), config);

      expect(result.outcome, InstallOutcome.updated);
      final List<ParamEntry> params = config.items.single.params;
      expect(params, hasLength(3));
      expect(params[0].key, 'DOCKER_HOST');
      expect(params[0].value, 'tcp://192.168.1.10:2375',
          reason: 'the user-filled value must survive a re-download');
      expect(params[1].key, 'TIMEOUT');
      expect(params[1].value, '30');
      expect(params[2].key, 'NEW_KEY');
      expect(params[2].value, '');
    });

    test('a removed declaration drops the param (declarations drive the form)', () async {
      serve('docker_status.lua', scriptBody);
      await installer.install(script(), config);
      expect(config.items.single.params, hasLength(2));

      serve('docker_status.lua', '-- @param DOCKER_HOST string Docker Host\nreturn font("x")\n');
      await installer.install(script(), config);
      expect(config.items.single.params, hasLength(1));
    });

    test('no declarations means an EMPTY params list, which serialises as absent', () async {
      // `lib/config.c:417` omits `params` entirely when empty, and five of the
      // eight items in the real config.json rely on that.
      serve('plain.lua', '-- plain.lua\nreturn font("x")\n');
      await installer.install(script(file: 'plain.lua'), config);
      expect(config.items.single.params, isEmpty);
      expect(config.items.single.toJson().containsKey('params'), isFalse);
    });
  });

  group('re-installing the same script', () {
    test('updates in place instead of adding a second item', () async {
      serve('docker_status.lua', scriptBody);
      final InstallResult first = await installer.install(script(), config);
      final InstallResult second = await installer.install(script(), config);

      expect(first.outcome, InstallOutcome.installed);
      expect(second.outcome, InstallOutcome.updated);
      expect(config.items, hasLength(1), reason: 'no duplicate entry');
      expect(second.itemIndex, 0);
      expect(persistCount, 2);
    });

    test('matches on basename, so a different install directory still updates', () async {
      // The C fix compares the full path with lstrcmpiW, which misses when the
      // same script was installed portable vs roaming.
      serve('docker_status.lua', scriptBody);
      await installer.install(script(), config);

      final MarketInstaller otherDir = MarketInstaller(
        scriptsDir: '${tempDir.path}${Platform.pathSeparator}other',
        fetcher: fetcher,
        persist: () async => persistCount++,
        inChina: false,
      );
      final InstallResult result = await otherDir.install(script(), config);

      expect(result.outcome, InstallOutcome.updated);
      expect(config.items, hasLength(1));
      expect(config.items.single.luaPath, contains('other'));
    });

    test('matching is case-insensitive on the filename', () async {
      serve('Docker_Status.LUA', scriptBody);
      await installer.install(script(file: 'Docker_Status.LUA'), config);
      serve('docker_status.lua', scriptBody);
      final InstallResult result = await installer.install(script(), config);
      expect(result.outcome, InstallOutcome.updated);
      expect(config.items, hasLength(1));
    });

    test('a URL-mode item pointing at the same path is NOT matched', () async {
      // Only Lua items are candidates, matching the C `type == ITEM_TYPE_LUA`.
      config.items.add(PinItem(type: PinItemType.url, luaPath: 'docker_status.lua'));
      serve('docker_status.lua', scriptBody);
      await installer.install(script(), config);
      expect(config.items, hasLength(2));
      expect(config.items.last.type, PinItemType.lua);
    });
  });

  group('failure paths change nothing', () {
    test('a download failure writes no file and adds no item', () async {
      fetcher.onFailure('/docker_status.lua');

      final InstallResult result = await installer.install(script(), config);

      expect(result.outcome, InstallOutcome.downloadFailed);
      expect(result.configChanged, isFalse);
      expect(result.fileWritten, isFalse);
      expect(config.items, isEmpty);
      expect(persistCount, 0, reason: 'nothing changed, so nothing is saved');
      expect(Directory(scriptsDir).existsSync(), isFalse);
    });

    test('an empty response body is a download failure', () async {
      fetcher.onBytes('/docker_status.lua', <int>[]);
      final InstallResult result = await installer.install(script(), config);
      expect(result.outcome, InstallOutcome.downloadFailed);
      expect(config.items, isEmpty);
    });

    test('a 404 is a download failure', () async {
      fetcher.onText('/docker_status.lua', 'Not Found', status: 404);
      final InstallResult result = await installer.install(script(), config);
      expect(result.outcome, InstallOutcome.downloadFailed);
      expect(config.items, isEmpty);
    });

    test('an entry whose file is not .lua is refused before any request', () async {
      final InstallResult result =
          await installer.install(script(file: 'readme.md'), config);
      expect(result.outcome, InstallOutcome.downloadFailed);
      expect(fetcher.callCount, 0, reason: 'no point downloading it');
      expect(persistCount, 0);
    });
  });

  group('the secondary bug: a full item list', () {
    test('at CFG_MAX_ITEMS the file is saved but the outcome is itemLimitReached', () async {
      // The C code returns early and still reports `market.download_success`,
      // telling the user an install worked when nothing was added. We report
      // honestly instead.
      while (config.items.length < ConfigLimits.maxItems) {
        config.items.add(PinItem(type: PinItemType.url, name: 'filler'));
      }
      expect(config.items, hasLength(64));

      serve('docker_status.lua', scriptBody);
      final InstallResult result = await installer.install(script(), config);

      expect(result.outcome, InstallOutcome.itemLimitReached);
      expect(result.configChanged, isFalse, reason: 'nothing was added');
      expect(result.fileWritten, isTrue, reason: 'the download did land on disk');
      expect(persistCount, 0, reason: 'the config did not change, so it is not saved');
      expect(File(result.filePath).existsSync(), isTrue);
      expect(config.items, hasLength(ConfigLimits.maxItems));
    });

    test('a full list still updates an EXISTING item', () async {
      // The limit only blocks ADDING; updating an entry already in the list is
      // not a new item and must still work.
      serve('docker_status.lua', scriptBody);
      await installer.install(script(), config);
      while (config.items.length < ConfigLimits.maxItems) {
        config.items.add(PinItem(type: PinItemType.url, name: 'filler'));
      }

      final InstallResult result = await installer.install(script(), config);
      expect(result.outcome, InstallOutcome.updated);
      expect(result.configChanged, isTrue);
      expect(persistCount, 2);
    });
  });

  group('URL construction', () {
    test('downloads from raw.githubusercontent.com when not in China', () async {
      serve('docker_status.lua', scriptBody);
      await installer.install(script(), config);
      expect(
        fetcher.requestedUrls.single,
        'https://raw.githubusercontent.com/bestK/taskpin-plugins/master/docker_status.lua',
      );
    });

    test('goes through gh-proxy.com when in China', () async {
      final MarketInstaller cn = MarketInstaller(
        scriptsDir: scriptsDir,
        fetcher: fetcher,
        persist: () async => persistCount++,
        inChina: true,
      );
      serve('docker_status.lua', scriptBody);
      await cn.install(script(), config);
      expect(
        fetcher.requestedUrls.single,
        'https://gh-proxy.com/https://raw.githubusercontent.com/'
        'bestK/taskpin-plugins/master/docker_status.lua',
      );
    });
  });

  group('naming', () {
    test('the manifest name is used when present', () async {
      serve('docker_status.lua', scriptBody);
      await installer.install(script(name: 'Docker 状态'), config);
      expect(config.items.single.name, 'Docker 状态');
    });

    test('the filename is the fallback when the manifest has no name', () async {
      // API-fallback entries have no name, so this is the common case there.
      serve('docker_status.lua', scriptBody);
      await installer.install(script(name: ''), config);
      expect(config.items.single.name, 'docker_status.lua');
    });
  });
}
