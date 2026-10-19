// Round-trip test: the REAL repository config.json must survive load -> save
// field-for-field.
//
// This is the acceptance test for docs/FLUTTER_REWRITE_PLAN.md Phase 1:
//
//   "加载仓库里真实的 config.json（8 个 item、sources:["bestK/taskpin-plugins"]、
//    bar_bg_color:"FFFFFFFF"、$.subscriptionTitle $$.currentUsage 的 field_expr）
//    → 序列化 → 与输入逐字段 JSON 相等（key 顺序与 tab 无关）；未知 key 往返保留；
//    version > 1 时明确报错拒绝。"
//
// The fixture `test/config/golden_config.json` is a byte copy of the repo's
// config.json (verified by tool/check_config_fixtures.py, which compares the
// two byte-for-byte). It is a copy rather than a reference because config.json
// is git-ignored:
//
//     .gitignore:19  config.json
//
// The fixture uses a different filename, so that pattern does NOT match it and
// it is committed with a plain `git add test/config/golden_config.json`.
// (`git check-ignore -v test/config/golden_config.json` exits 1.) Do not rename
// it to `config.json` — that would make it invisible to git.
//
// NOTE: not yet executed — the Dart SDK is not installed in this working copy.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin/core/config/config_repository.dart';
import 'package:taskpin/core/config/config_schema.dart';
import 'package:taskpin/core/config/migration.dart';

/// Reads and decodes a fixture, relative to the package root.
///
/// Throws (rather than using `expect`) so it is safe to call from `setUpAll`,
/// where a failed matcher is reported as an error rather than a test failure.
Map<String, dynamic> _readJson(String relativePath) {
  final file = File(relativePath);
  if (!file.existsSync()) {
    throw StateError('missing fixture: $relativePath');
  }
  return (jsonDecode(file.readAsStringSync(encoding: utf8)) as Map)
      .cast<String, dynamic>();
}

void main() {
  const goldenPath = 'test/config/golden_config.json';

  group('golden config.json round-trip', () {
    late Map<String, dynamic> original;
    late TaskPinConfig loaded;
    late Map<String, dynamic> reserialized;

    setUpAll(() {
      original = _readJson(goldenPath);
      loaded = TaskPinConfig.fromJson(original, path: goldenPath);
      reserialized = loaded.toJson();
    });

    test('parses without error and is not treated as legacy', () {
      expect(loaded.version, 1);
      expect(loaded.items, hasLength(8));
    });

    test('load -> save is field-for-field equal to the input', () {
      // Deep equality; key order and tab indentation are irrelevant.
      expect(reserialized, equals(original),
          reason: 'the whole point of Phase 1 is that the real file survives '
              'a load/save cycle unchanged');
    });

    test('the re-serialized text re-parses to the same document', () {
      final text = loaded.toJsonString();
      final reparsed = TaskPinConfig.fromJsonString(text, path: goldenPath);
      expect(reparsed.toJson(), equals(original));
    });

    test('the named acceptance values from the plan are present', () {
      // 8 items
      expect(loaded.count, 8);

      // sources: ["bestK/taskpin-plugins"]
      expect(loaded.sources, <String>['bestK/taskpin-plugins']);
      expect(loaded.sourceCount, 1);

      // bar_bg_color: "FFFFFFFF" on every item (the "use global" sentinel)
      for (final item in loaded.items) {
        expect(item.barBgColor, 'FFFFFFFF');
        expect(ConfigColor.isUseGlobal(item.barBgColor), isTrue);
      }

      // the $.subscriptionTitle $$.currentUsage field_expr, verbatim
      final apiItem = loaded.items[6];
      expect(apiItem.type, PinItemType.url);
      expect(apiItem.fieldExpr, r'$.subscriptionTitle $$.currentUsage');
      expect(apiItem.reqHeaders, 'x-api-key:sk-lkl123456');
      expect(apiItem.url,
          'http://150.136.126.228:18990/api/admin/credentials/4/balance');
      expect(apiItem.barWidth, 130);
      expect(apiItem.barX, 1314);
    });

    test('global values are carried through verbatim', () {
      expect(loaded.width, 200);
      expect(loaded.posX, -1);
      expect(loaded.posY, -1);
      expect(loaded.fontSize, 9);
      expect(loaded.fontColor, 'FFFFFF');
      expect(loaded.logLevel, 3);
      expect(loaded.scrollEnabled, isTrue);
      // NOTE: config.h comments claim 0xFFFFFFFF means transparent, but the
      // real file carries 00000000, which CreateSolidBrush renders as opaque
      // black. Preserved as-is; see the plan's note on the bar's transparency.
      expect(loaded.bgColor, '00000000');
    });

    test('the one named item is preserved', () {
      expect(loaded.items[7].name, 'zeeho');
      expect(loaded.items[7].type, PinItemType.lua);
      expect(loaded.items[7].intervalMs, 30000);
      expect(loaded.items[7].luaPath, endsWith(r'scripts\zeeho.lua'));
    });

    test('params are present on exactly the items that have them', () {
      // config.c:417 omits `params` when param_count == 0, so 5 of the 8 real
      // items have no `params` key at all. Re-emitting `"params": []` for those
      // would break the deep-equality assertion above; assert it explicitly so
      // the reason is obvious when it fails.
      final itemsJson = (reserialized['items'] as List).cast<Map>();

      expect(itemsJson[0].containsKey('params'), isTrue);
      expect(itemsJson[0]['params'], hasLength(3));
      expect(itemsJson[4].containsKey('params'), isTrue);
      expect(itemsJson[4]['params'], hasLength(2));

      for (final index in <int>[1, 2, 3, 5, 6, 7]) {
        expect(itemsJson[index].containsKey('params'), isFalse,
            reason: 'item $index has no params in the source file; emitting '
                'an empty list would not round-trip');
      }
    });

    test('params content is preserved including non-ASCII labels', () {
      final first = loaded.items[0];
      expect(first.paramCount, 3);
      expect(first.params[0].key, 'BASE_URL');
      expect(first.params[0].value, 'https://bobdong.cn');
      expect(first.params[0].label, 'API地址(如 https://api.example.com)');
      expect(first.params[1].key, 'TOKEN');
      expect(first.params[2].key, 'USER_ID');
    });

    test('no unknown keys are invented or lost', () {
      // The real file has no unknown keys; if this ever fails, the model has
      // started emitting a field the C writer would not.
      expect(loaded.extra, isEmpty);
      expect(loaded.globalExtra, isEmpty);
      for (final item in loaded.items) {
        expect(item.extra, isEmpty);
      }
      final itemKeys = PinItem.knownKeys;
      for (final itemJson in (original['items'] as List).cast<Map>()) {
        for (final key in itemJson.keys) {
          expect(itemKeys, contains(key),
              reason: 'config.json has an item key the model does not know: $key');
        }
      }
    });

    test('re-serializing is byte-stable', () {
      final first = loaded.toJsonString();
      final second =
          TaskPinConfig.fromJsonString(first, path: goldenPath).toJsonString();
      expect(second, first);
    });
  });

  group('unknown keys survive a round-trip', () {
    test('root, global, item and param level', () {
      const path = 'test/config/fixtures/config_unknown_keys.json';
      final original = _readJson(path);

      final loaded = TaskPinConfig.fromJson(original, path: path);
      final reserialized = loaded.toJson();

      expect(reserialized, equals(original),
          reason: 'unknown keys must be preserved field-for-field');

      // Spot-check that the preservation is not accidental.
      expect(reserialized['experimental_feature_flag'], 'keep me at the root');
      expect((reserialized['global'] as Map)['future_global_option'],
          <String, dynamic>{
        'nested': <int>[1, 2, 3]
      });
      final item = (reserialized['items'] as List).first as Map;
      expect(item['future_item_option'], isTrue);
      final param = (item['params'] as List).first as Map;
      expect(param['future_param_option'], 42);
    });
  });

  group('sources: [] is deliberately not round-trippable', () {
    test('an empty list becomes the default source (config.c:166-169)', () {
      const path = 'test/config/fixtures/config_empty_sources.json';
      final original = _readJson(path);
      expect(original['sources'], isEmpty);

      final loaded = TaskPinConfig.fromJson(original, path: path);
      expect(loaded.sources, <String>['bestK/taskpin-plugins']);

      // Documented divergence: the C loader injects the default, so a saved
      // file has one source. Asserting it here keeps the behaviour pinned.
      final reserialized = loaded.toJson();
      expect(reserialized['sources'], <String>['bestK/taskpin-plugins']);
      expect(reserialized, isNot(equals(original)));
    });
  });

  group('version > 1 is refused', () {
    test('loading throws ConfigVersionError', () {
      const path = 'test/config/fixtures/config_future_version.json';
      final original = _readJson(path);
      expect(original['version'], 2);

      expect(
        () => TaskPinConfig.fromJson(original, path: path),
        throwsA(isA<ConfigVersionError>()
            .having((e) => e.version, 'version', 2)
            .having((e) => e.path, 'path', path)),
      );
    });

    test('the error message names both versions', () {
      const path = 'test/config/fixtures/config_future_version.json';
      final error = ConfigVersionError(version: 2, path: path);
      expect(error.toString(), contains('version 2'));
      expect(error.toString(), contains('version 1'));
    });

    test('migration refuses and leaves the file untouched', () async {
      final tmp = await Directory.systemTemp.createTemp('taskpin-cfg-');
      addTearDown(() => tmp.delete(recursive: true));

      final source = File('test/config/fixtures/config_future_version.json');
      final target = File('${tmp.path}${Platform.pathSeparator}config.json');
      final originalBytes = source.readAsBytesSync();
      target.writeAsBytesSync(originalBytes);

      final migrator = ConfigMigrator(
        paths: ConfigPaths(
          baseDir: tmp.path,
          configFile: target.path,
          scriptsDir: '${tmp.path}${Platform.pathSeparator}scripts',
          portable: true,
        ),
      );

      await expectLater(migrator.migrateIfNeeded(), throwsA(isA<ConfigVersionError>()));

      expect(target.readAsBytesSync(), originalBytes,
          reason: 'a refused file must not be rewritten');
      expect(
        File('${tmp.path}${Platform.pathSeparator}config.v1.json').existsSync(),
        isFalse,
        reason: 'a refused file must not be backed up either',
      );
    });
  });
}
