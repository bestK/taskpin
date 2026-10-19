// Migration tests: legacy Windows JSON, legacy Windows INI, and the macOS
// Swift schema, all unifying onto the Windows schema.
//
// NOTE: not yet executed — the Dart SDK is not installed in this working copy.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin/core/config/config_repository.dart';
import 'package:taskpin/core/config/config_schema.dart';
import 'package:taskpin/core/config/migration.dart';

/// Reads and decodes a fixture. Throws (rather than using `expect`) so it is
/// safe to call from `setUpAll`, where a failed matcher is reported as an error
/// rather than a test failure.
Map<String, dynamic> _readJson(String relativePath) {
  final file = File(relativePath);
  if (!file.existsSync()) {
    throw StateError('missing fixture: $relativePath');
  }
  return (jsonDecode(file.readAsStringSync(encoding: utf8)) as Map)
      .cast<String, dynamic>();
}

/// Creates a temp "install" containing a copy of [fixture], and returns a
/// repository pointed at it.
Future<({Directory dir, ConfigPaths paths, File config})> _stage(
    String fixture) async {
  final tmp = await Directory.systemTemp.createTemp('taskpin-migrate-');
  final config = File('${tmp.path}${Platform.pathSeparator}config.json');
  config.writeAsBytesSync(File(fixture).readAsBytesSync());
  final paths = ConfigPaths(
    baseDir: tmp.path,
    configFile: config.path,
    scriptsDir: '${tmp.path}${Platform.pathSeparator}scripts',
    portable: true,
  );
  return (dir: tmp, paths: paths, config: config);
}

void main() {
  group('origin detection', () {
    test('the golden config is already unified', () {
      expect(detectConfigOrigin(_readJson('test/config/golden_config.json')),
          ConfigOrigin.unified);
    });

    test('a document missing the newer fields is windowsV1Json', () {
      expect(
        detectConfigOrigin(_readJson('test/config/fixtures/config_legacy_v1.json')),
        ConfigOrigin.windowsV1Json,
      );
    });

    test('the Swift document is macosSwift', () {
      expect(
        detectConfigOrigin(_readJson('test/config/fixtures/config_macos_legacy.json')),
        ConfigOrigin.macosSwift,
      );
    });

    test('a UUID item id alone is enough to spot the Swift schema', () {
      expect(
        detectConfigOrigin(<String, dynamic>{
          'items': <dynamic>[
            <String, dynamic>{'id': '3F2504E0-4F89-11D3-9A0C-0305E82C3301'},
          ],
        }),
        ConfigOrigin.macosSwift,
      );
    });

    test('the unknown-keys fixture is unified (it has the full field set)', () {
      expect(
        detectConfigOrigin(
            _readJson('test/config/fixtures/config_unknown_keys.json')),
        ConfigOrigin.unified,
      );
    });
  });

  group('(a) Windows version-1 JSON -> unified', () {
    test('fills the newer fields and keeps the rest', () {
      final raw = _readJson('test/config/fixtures/config_legacy_v1.json');
      final cfg = migrateConfig(raw, origin: ConfigOrigin.windowsV1Json);

      // Fields the old document lacked take the C defaults.
      expect(cfg.sources, <String>['bestK/taskpin-plugins']);
      expect(cfg.scrollEnabled, isTrue);
      for (final item in cfg.items) {
        expect(item.barX, -1);
        expect(item.barY, -1);
        expect(item.barBgColor, kColorUseGlobal);
        expect(item.dlgX, -1);
        expect(item.dlgW, 0);
      }

      // Fields it had are carried through.
      expect(cfg.width, 200);
      expect(cfg.logLevel, 3);
      expect(cfg.items, hasLength(2));
      expect(cfg.items[0].name, 'old lua item');
      expect(cfg.items[0].pinned, isTrue);
      expect(cfg.items[0].params.single.key, 'TOKEN');
      expect(cfg.items[0].params.single.label, '令牌');
      expect(cfg.items[1].fieldExpr, r'$.value');
    });

    test('the migrated document is now detected as unified (idempotent)', () {
      final raw = _readJson('test/config/fixtures/config_legacy_v1.json');
      final cfg = migrateConfig(raw, origin: ConfigOrigin.windowsV1Json);
      expect(detectConfigOrigin(cfg.toJson()), ConfigOrigin.unified);
    });

    test('migrating in place writes config.v1.json with the original bytes',
        () async {
      final staged = await _stage('test/config/fixtures/config_legacy_v1.json');
      addTearDown(() => staged.dir.delete(recursive: true));

      final originalBytes = File('test/config/fixtures/config_legacy_v1.json')
          .readAsBytesSync();

      final outcome =
          await ConfigMigrator(paths: staged.paths).migrateIfNeeded();

      expect(outcome, isA<Migrated>());
      final migrated = outcome as Migrated;
      expect(migrated.from, ConfigOrigin.windowsV1Json);
      expect(migrated.backupPath, endsWith('config.v1.json'));

      // The backup is the untouched original.
      expect(File(migrated.backupPath!).readAsBytesSync(), originalBytes);

      // The live config is now unified and re-reads cleanly.
      final reloaded = await ConfigRepository(paths: staged.paths).load();
      expect(reloaded.items, hasLength(2));
      expect(reloaded.sources, <String>['bestK/taskpin-plugins']);
    });

    test('a second pass does not clobber the existing backup', () async {
      final staged = await _stage('test/config/fixtures/config_legacy_v1.json');
      addTearDown(() => staged.dir.delete(recursive: true));

      final backupPath = '${staged.dir.path}${Platform.pathSeparator}config.v1.json';
      final originalBytes = File('test/config/fixtures/config_legacy_v1.json')
          .readAsBytesSync();

      await ConfigMigrator(paths: staged.paths).migrateIfNeeded();
      expect(File(backupPath).readAsBytesSync(), originalBytes);

      // Corrupt the backup, then migrate again: the backup must be untouched
      // because the config is already unified.
      File(backupPath).writeAsStringSync('sentinel');
      final second = await ConfigMigrator(paths: staged.paths).migrateIfNeeded();

      expect(second, isA<AlreadyUnified>());
      expect(File(backupPath).readAsStringSync(), 'sentinel',
          reason: 'the first backup is the truest original; never overwrite it');
    });
  });

  group('(b) macOS Swift schema -> unified', () {
    late TaskPinConfig cfg;

    setUpAll(() {
      cfg = migrateConfig(
        _readJson('test/config/fixtures/config_macos_legacy.json'),
        origin: ConfigOrigin.macosSwift,
      );
    });

    test('the UUID id and paramType are dropped', () {
      expect(cfg.items, hasLength(2));
      expect(cfg.items[0].extra, isEmpty);
      expect(cfg.items[0].params.single.extra, isEmpty);
    });

    test('the string type enum becomes the int', () {
      expect(cfg.items[0].type, PinItemType.lua);
      expect(cfg.items[1].type, PinItemType.url);
    });

    test('camelCase keys become snake_case', () {
      final item = cfg.items[0];
      expect(item.name, 'mac clock');
      expect(item.intervalMs, 1000);
      expect(item.clickEnabled, isTrue);
      expect(item.clickUrl, 'https://example.com');
      expect(item.luaPath, '~/.taskpin/scripts/clock.lua');
      expect(item.pinned, isTrue);
      expect(item.params.single.key, 'TZ');
      expect(item.params.single.value, 'UTC+8');
      expect(item.params.single.label, '时区');

      final api = cfg.items[1];
      expect(api.reqHeaders, 'x-api-key:abc');
      expect(api.fieldExpr, r'$.subscriptionTitle $$.currentUsage');
    });

    test('the bar and dialog fields take the unified defaults', () {
      for (final item in cfg.items) {
        expect(item.barWidth, 0);
        expect(item.barX, -1);
        expect(item.barY, -1);
        expect(item.barBgColor, kColorUseGlobal);
        expect(item.dlgX, -1);
        expect(item.dlgY, -1);
        expect(item.dlgW, 0);
        expect(item.dlgH, 0);
      }
    });

    test('root-level globals map across, with the C defaults for the rest', () {
      expect(cfg.fontSize, 12);
      expect(cfg.scrollEnabled, isTrue);
      expect(cfg.sources, <String>['bestK/taskpin-plugins']);
      // Not present in the Swift schema.
      expect(cfg.width, 320);
      expect(cfg.posX, -1);
      expect(cfg.posY, -1);
      expect(cfg.logLevel, 0);
    });

    test('RGB hex is swapped into COLORREF byte order', () {
      // macOS "FF8000" is R=FF G=80 B=00 (RGB). As a COLORREF that is
      // 0x000080FF, i.e. "0080FF". An implementation that forgot the swap
      // would produce "FF8000" and fail here — which is the point: both of the
      // mac defaults in the real Swift source are byte-symmetric, so nothing
      // else would ever catch the mistake.
      expect(cfg.fontColor, '0080FF');

      // "1E1E1E" is symmetric, so it is unchanged apart from the alpha prefix
      // that bg_color always carries.
      expect(cfg.bgColor, '001E1E1E');
    });

    test('the migrated document is detected as unified', () {
      expect(detectConfigOrigin(cfg.toJson()), ConfigOrigin.unified);
    });

    test('it round-trips once migrated', () {
      final once = cfg.toJson();
      expect(TaskPinConfig.fromJson(once).toJson(), equals(once));
    });
  });

  group('(c) Windows config.ini -> unified', () {
    /// Builds a UTF-16LE-with-BOM INI body, which is what
    /// `WritePrivateProfileStringW` produces.
    List<int> utf16le(String text) {
      final out = <int>[0xFF, 0xFE];
      for (final unit in text.codeUnits) {
        out.add(unit & 0xFF);
        out.add((unit >> 8) & 0xFF);
      }
      return out;
    }

    const iniText = '''
[Global]
width=200
count=2
selected=1
pos_x=-1
pos_y=-1
font_size=9
font_color=FFFFFF
bg_color=000000
scroll_enabled=1
log_level=3
[Item_0]
type=1
name=
url=http://localhost:8080/status
interval_ms=5000
field_expr_b64=
click_enabled=0
click_url=
lua_path=scripts\\a.lua
param_count=1
param_key_0=TOKEN
param_val_0=abc
param_lbl_0=令牌
pinned=0
bar_width=0
bar_x=-1
bar_y=-1
bar_bg_color=FFFFFFFF
dlg_x=-1
dlg_y=-1
dlg_w=0
dlg_h=0
[Item_1]
type=0
name=api
url=http://localhost:8080/status
interval_ms=5000
field_expr_b64=JC52YWx1ZQ==
click_enabled=1
click_url=https://example.com
lua_path=
param_count=0
pinned=0
bar_width=130
bar_x=1314
bar_y=-1
bar_bg_color=FFFFFFFF
dlg_x=0
dlg_y=0
dlg_w=0
dlg_h=0
[Sources]
count=1
source_0=bestK/taskpin-plugins
''';

    test('parses the UTF-16LE INI that the C layer writes', () {
      final ini = IniDocument.parse(utf16le(iniText));
      expect(ini.getInt('Global', 'width', 0), 200);
      expect(ini.getInt('Global', 'count', 0), 2);
      expect(ini.getString('Item_1', 'name', ''), 'api');
      expect(ini.getString('Sources', 'source_0', ''), 'bestK/taskpin-plugins');
    });

    test('base64 fields are decoded', () {
      final ini = IniDocument.parse(utf16le(iniText));
      // "JC52YWx1ZQ==" is base64 for "$.value"
      expect(ini.getBase64('Item_1', 'field_expr_b64'), r'$.value');
      expect(ini.getBase64('Item_0', 'field_expr_b64'), '');
    });

    test('converts to the unified schema', () {
      final cfg = migrateIni(IniDocument.parse(utf16le(iniText)));

      expect(cfg.width, 200);
      expect(cfg.logLevel, 3);
      expect(cfg.items, hasLength(2));

      expect(cfg.items[0].type, PinItemType.lua);
      expect(cfg.items[0].luaPath, r'scripts\a.lua');
      expect(cfg.items[0].params.single.key, 'TOKEN');
      expect(cfg.items[0].params.single.label, '令牌');

      expect(cfg.items[1].type, PinItemType.url);
      expect(cfg.items[1].name, 'api');
      expect(cfg.items[1].fieldExpr, r'$.value');
      expect(cfg.items[1].clickEnabled, isTrue);
      expect(cfg.items[1].clickUrl, 'https://example.com');
      expect(cfg.items[1].barWidth, 130);
      expect(cfg.items[1].barX, 1314);
    });

    test('the legacy `selected` index becomes the pinned item (config.c:282-292)',
        () {
      final cfg = migrateIni(IniDocument.parse(utf16le(iniText)));
      // Neither item sets pinned=1, so `selected=1` wins.
      expect(cfg.items[0].pinned, isFalse);
      expect(cfg.items[1].pinned, isTrue);
    });

    test('an explicit pinned flag beats the legacy selected index', () {
      final withPinned =
          iniText.replaceFirst('pinned=0', 'pinned=1').replaceFirst('selected=1', 'selected=0');
      final cfg = migrateIni(IniDocument.parse(utf16le(withPinned)));
      expect(cfg.items[0].pinned, isTrue);
      expect(cfg.items[1].pinned, isFalse);
    });

    test('migrating a config.ini renames it to config.ini.bak (config.c:352-355)',
        () async {
      final tmp = await Directory.systemTemp.createTemp('taskpin-ini-');
      addTearDown(() => tmp.delete(recursive: true));

      final sep = Platform.pathSeparator;
      final iniFile = File('${tmp.path}${sep}config.ini');
      final iniBytes = utf16le(iniText);
      iniFile.writeAsBytesSync(iniBytes);

      final paths = ConfigPaths(
        baseDir: tmp.path,
        configFile: '${tmp.path}${sep}config.json',
        scriptsDir: '${tmp.path}${sep}scripts',
        portable: true,
      );

      final outcome = await ConfigMigrator(paths: paths).migrateIfNeeded();
      expect(outcome, isA<Migrated>());
      expect((outcome as Migrated).from, ConfigOrigin.windowsIni);
      expect(outcome.backupPath, endsWith('config.ini.bak'));
      expect(File(outcome.backupPath!).readAsBytesSync(), iniBytes);

      final reloaded = await ConfigRepository(paths: paths).load();
      expect(reloaded.items, hasLength(2));
      expect(reloaded.items[1].pinned, isTrue);
    });
  });

  group('ConfigPaths.resolve', () {
    test('macOS uses ~/.taskpin/config.json', () {
      final paths = ConfigPaths.resolve(
        executablePath: '/Applications/TaskPin.app/Contents/MacOS/TaskPin',
        environment: <String, String>{'HOME': '/Users/someone'},
        isWindows: false,
        isMacOS: true,
      );
      expect(paths.portable, isFalse);
      expect(paths.baseDir, endsWith('.taskpin'));
      expect(paths.configFile, endsWith('config.json'));
      expect(paths.scriptsDir, endsWith('scripts'));
    });

    test('Windows falls back to %APPDATA%\\TaskPin when there is no portable config',
        () async {
      final tmp = await Directory.systemTemp.createTemp('taskpin-paths-');
      addTearDown(() => tmp.delete(recursive: true));

      final exeDir = Directory('${tmp.path}${Platform.pathSeparator}app')
        ..createSync(recursive: true);
      final appData = '${tmp.path}${Platform.pathSeparator}roaming';

      final paths = ConfigPaths.resolve(
        executablePath: '${exeDir.path}${Platform.pathSeparator}taskpin.exe',
        environment: <String, String>{'APPDATA': appData},
        isWindows: true,
        isMacOS: false,
      );

      expect(paths.portable, isFalse);
      expect(paths.baseDir, endsWith('TaskPin'));
      expect(paths.baseDir, startsWith(appData));
    });

    test('Windows prefers a writable exe-sibling config.json (portable mode)',
        () async {
      final tmp = await Directory.systemTemp.createTemp('taskpin-paths-');
      addTearDown(() => tmp.delete(recursive: true));

      final exeDir = Directory('${tmp.path}${Platform.pathSeparator}app')
        ..createSync(recursive: true);
      File('${exeDir.path}${Platform.pathSeparator}config.json').writeAsStringSync('{}');

      final paths = ConfigPaths.resolve(
        executablePath: '${exeDir.path}${Platform.pathSeparator}taskpin.exe',
        environment: <String, String>{
          'APPDATA': '${tmp.path}${Platform.pathSeparator}roaming',
        },
        isWindows: true,
        isMacOS: false,
      );

      expect(paths.portable, isTrue);
      expect(paths.baseDir, exeDir.path);
    });

    test('Windows uses an existing roaming config when there is no portable one',
        () async {
      final tmp = await Directory.systemTemp.createTemp('taskpin-paths-');
      addTearDown(() => tmp.delete(recursive: true));

      final exeDir = Directory('${tmp.path}${Platform.pathSeparator}app')
        ..createSync(recursive: true);
      final appData = '${tmp.path}${Platform.pathSeparator}roaming';
      final roaming = Directory('${appData}${Platform.pathSeparator}TaskPin')
        ..createSync(recursive: true);
      File('${roaming.path}${Platform.pathSeparator}config.json').writeAsStringSync('{}');

      final paths = ConfigPaths.resolve(
        executablePath: '${exeDir.path}${Platform.pathSeparator}taskpin.exe',
        environment: <String, String>{'APPDATA': appData},
        isWindows: true,
        isMacOS: false,
      );

      expect(paths.portable, isFalse);
      expect(paths.baseDir, roaming.path);
    });
  });

  group('ConfigRepository', () {
    test('debounces and coalesces writes', () async {
      final tmp = await Directory.systemTemp.createTemp('taskpin-repo-');
      addTearDown(() => tmp.delete(recursive: true));

      final paths = ConfigPaths(
        baseDir: tmp.path,
        configFile: '${tmp.path}${Platform.pathSeparator}config.json',
        scriptsDir: '${tmp.path}${Platform.pathSeparator}scripts',
        portable: true,
      );
      final repo = ConfigRepository(
        paths: paths,
        debounce: const Duration(milliseconds: 30),
      );

      final cfg = TaskPinConfig();
      repo.save(cfg);
      cfg.width = 100;
      repo.save(cfg);
      cfg.width = 250;
      repo.save(cfg);

      expect(repo.hasPendingWrite, isTrue);
      expect(File(paths.configFile).existsSync(), isFalse,
          reason: 'nothing is written until the debounce elapses');

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(File(paths.configFile).existsSync(), isTrue);

      // The debounced write is not awaited by anyone; flush() makes the test
      // deterministic (it is a no-op when the write already landed, thanks to
      // the byte-identical guard).
      await repo.flush();

      final reloaded = await ConfigRepository(paths: paths).load();
      expect(reloaded.width, 250,
          reason: 'the three rapid saves coalesced into the last one');
    });

    test('flush writes immediately', () async {
      final tmp = await Directory.systemTemp.createTemp('taskpin-repo-');
      addTearDown(() => tmp.delete(recursive: true));

      final paths = ConfigPaths(
        baseDir: tmp.path,
        configFile: '${tmp.path}${Platform.pathSeparator}config.json',
        scriptsDir: '${tmp.path}${Platform.pathSeparator}scripts',
        portable: true,
      );
      final repo = ConfigRepository(
        paths: paths,
        debounce: const Duration(seconds: 30),
      );

      repo.save(TaskPinConfig(width: 321));
      await repo.flush();

      expect(File(paths.configFile).existsSync(), isTrue);
      final reloaded = await ConfigRepository(paths: paths).load();
      expect(reloaded.width, 321);
    });

    test('writes atomically and leaves no .tmp behind', () async {
      final tmp = await Directory.systemTemp.createTemp('taskpin-repo-');
      addTearDown(() => tmp.delete(recursive: true));

      final paths = ConfigPaths(
        baseDir: tmp.path,
        configFile: '${tmp.path}${Platform.pathSeparator}config.json',
        scriptsDir: '${tmp.path}${Platform.pathSeparator}scripts',
        portable: true,
      );
      final repo = ConfigRepository(paths: paths, debounce: Duration.zero);

      repo.save(TaskPinConfig(width: 1));
      await repo.flush();
      repo.save(TaskPinConfig(width: 2));
      await repo.flush();

      expect(File('${paths.configFile}.tmp').existsSync(), isFalse);
      final reloaded = await ConfigRepository(paths: paths).load();
      expect(reloaded.width, 2);
    });

    test('load creates an in-memory default when no file exists', () async {
      final tmp = await Directory.systemTemp.createTemp('taskpin-repo-');
      addTearDown(() => tmp.delete(recursive: true));

      final paths = ConfigPaths(
        baseDir: tmp.path,
        configFile: '${tmp.path}${Platform.pathSeparator}config.json',
        scriptsDir: '${tmp.path}${Platform.pathSeparator}scripts',
        portable: true,
      );

      final cfg = await ConfigRepository(paths: paths).load();
      expect(cfg.width, 320);
      expect(cfg.items, isEmpty);
      expect(cfg.sources, <String>['bestK/taskpin-plugins']);
    });

    test('loading a real config.json is not treated as a migration', () async {
      final staged = await _stage('test/config/golden_config.json');
      addTearDown(() => staged.dir.delete(recursive: true));

      final repo = ConfigRepository(paths: staged.paths);
      final cfg = await repo.load();

      expect(cfg.items, hasLength(8));
      expect(
        File('${staged.dir.path}${Platform.pathSeparator}config.v1.json')
            .existsSync(),
        isFalse,
        reason: 'an already-unified file must not be backed up or rewritten',
      );
    });
  });
}
