// Schema-level tests for the config model.
//
// Covers the C defaults from `lib/config.c:config_load_json` /
// `config_load`, the `bar_bg_color` sentinel, the two color widths, the
// deliberately-dropped `realtime` field, and the color byte-order helpers.
//
// NOTE: the Flutter/Dart SDK is not installed in this working copy yet (the
// SDK cache under D:\flutter is still downloading), so these tests are written
// but not yet executed. Run them with:
//
//     flutter test test/config
//
// They import package:flutter_test for consistency with the rest of the app;
// if this layer is ever split into a pure-Dart package, swap the import for
// package:test — nothing else here depends on Flutter.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin/core/config/config_schema.dart';

void main() {
  group('TaskPinConfig defaults', () {
    test('an empty document yields the C defaults', () {
      final cfg = TaskPinConfig.fromJson(<String, dynamic>{});

      // lib/config.c:360-370
      expect(cfg.version, 1);
      expect(cfg.width, 320);
      expect(cfg.posX, -1);
      expect(cfg.posY, -1);
      expect(cfg.fontSize, 9);
      expect(cfg.fontColor, 'FFFFFF');
      expect(cfg.bgColor, 'FFFFFFFF');
      expect(cfg.scrollEnabled, isTrue);
      expect(cfg.logLevel, 0);
      expect(cfg.items, isEmpty);
      expect(cfg.count, 0);
    });

    test('sources defaults to the plugin repo when absent (config.c:166-169)',
        () {
      final cfg = TaskPinConfig.fromJson(<String, dynamic>{});
      expect(cfg.sources, <String>['bestK/taskpin-plugins']);
      expect(cfg.sourceCount, 1);
    });

    test('count and sourceCount are derived, never stored', () {
      final cfg = TaskPinConfig(
        items: [PinItem(), PinItem(), PinItem()],
        sources: ['a/b', 'c/d'],
      );
      expect(cfg.count, 3);
      expect(cfg.sourceCount, 2);

      final json = cfg.toJson();
      expect(json.containsKey('count'), isFalse,
          reason: 'config.h count is derived; config_save never writes it');
      expect(json.containsKey('source_count'), isFalse,
          reason: 'config.h source_count is derived');
    });

    test('root key order matches config_save', () {
      final json = TaskPinConfig().toJson();
      expect(json.keys.toList(),
          <String>['version', 'global', 'items', 'sources']);
    });

    test('global key order matches config_save', () {
      final json = TaskPinConfig().toJson();
      expect((json['global'] as Map).keys.toList(), <String>[
        'width',
        'pos_x',
        'pos_y',
        'font_size',
        'font_color',
        'bg_color',
        'scroll_enabled',
        'log_level',
      ]);
    });
  });

  group('PinItem defaults', () {
    test('an empty item object yields the C defaults', () {
      final item = PinItem.fromJson(<String, dynamic>{});
      expect(item.type, PinItemType.url);
      expect(item.name, 'Untitled',
          reason: 'config.c:117 uses L"Untitled" when name is absent');
      expect(item.intervalMs, 5000);
      expect(item.barWidth, 0);
      expect(item.barX, -1);
      expect(item.barY, -1);
      expect(item.barBgColor, kColorUseGlobal);
      expect(item.dlgX, -1);
      expect(item.dlgY, -1);
      expect(item.dlgW, 0);
      expect(item.dlgH, 0);
      expect(item.pinned, isFalse);
      expect(item.paramCount, 0);
    });

    test('an explicit empty name is preserved, not replaced by Untitled', () {
      final item = PinItem.fromJson(<String, dynamic>{'name': ''});
      expect(item.name, '');
    });

    test('item key order matches config_save', () {
      final json = PinItem().toJson();
      expect(json.keys.toList(), PinItem.wireOrder,
          reason: 'params is appended only when non-empty');
    });

    test('params is omitted entirely when empty (config.c:417)', () {
      final json = PinItem().toJson();
      expect(json.containsKey('params'), isFalse,
          reason: 'config_save guards on `if (it->param_count > 0)`; emitting '
              '[] would break round-trip equality with real files');

      final withParams = PinItem(params: [ParamEntry(key: 'K', value: 'V')]);
      expect(withParams.toJson()['params'], isA<List<dynamic>>());
    });

    test('numbers stay integers, never 5000.0', () {
      final json = PinItem().toJson();
      expect(json['interval_ms'], isA<int>());
      expect(json['bar_x'], isA<int>());
      expect(json['dlg_h'], isA<int>());
    });
  });

  group('realtime is dropped', () {
    test('the model exposes no realtime field', () {
      final item = PinItem();
      final json = item.toJson();
      expect(json.containsKey('realtime'), isFalse);
    });

    test('a stray realtime key in an old file is discarded, not preserved', () {
      final item = PinItem.fromJson(<String, dynamic>{
        'name': 'x',
        'realtime': true,
      });
      expect(item.extra.containsKey('realtime'), isFalse,
          reason: 'realtime is a known-dead key; round-tripping it forever '
              'would resurrect a field the plan deletes');
      expect(item.toJson().containsKey('realtime'), isFalse);
    });
  });

  group('bar_bg_color sentinel', () {
    test('FFFFFFFF means "use the global bg", not white', () {
      expect(ConfigColor.isUseGlobal('FFFFFFFF'), isTrue);
      expect(ConfigColor.isUseGlobal('00FFFFFF'), isFalse,
          reason: 'an explicit white would be 00FFFFFF in COLORREF order');
      expect(ConfigColor.isUseGlobal('FFFFFF'), isFalse,
          reason: 'the 6-digit form is not the sentinel');
    });

    test('the default is the sentinel', () {
      expect(PinItem().barBgColor, kColorUseGlobal);
      expect(PinItem.fromJson(<String, dynamic>{}).barBgColor, kColorUseGlobal);
    });
  });

  group('color encoding', () {
    test('format widths match json_add_color', () {
      // global.font_color is written with %06X (config.c:387 -> with_alpha=0)
      expect(ConfigColor.format6(0xFFFFFFFF), 'FFFFFF');
      expect(ConfigColor.format6(0x00FFFFFF), 'FFFFFF');
      // bg_color and bar_bg_color are written with %08X
      expect(ConfigColor.format8(0xFFFFFFFF), 'FFFFFFFF');
      expect(ConfigColor.format8(0x00000000), '00000000');
      expect(ConfigColor.format8(0x1E1E1E), '001E1E1E');
    });

    test('tryParse mirrors wcstoul(s, NULL, 16)', () {
      expect(ConfigColor.tryParse('FFFFFFFF'), 0xFFFFFFFF);
      expect(ConfigColor.tryParse('ff0000'), 0xFF0000);
      expect(ConfigColor.tryParse('0xFFFFFF'), 0xFFFFFF);
      expect(ConfigColor.tryParse('  FFFFFF  '), 0xFFFFFF);
      expect(ConfigColor.tryParse(''), isNull);
      expect(ConfigColor.tryParse(null), isNull);
      expect(ConfigColor.tryParse('zzz'), isNull);
    });

    test('COLORREF is BGR, so FF0000 is blue', () {
      // The on-disk value is a Win32 COLORREF (0x00BBGGRR).
      final colorref = ConfigColor.tryParse('FF0000')!;
      final argb = ConfigColor.colorrefToArgb(colorref);

      // 0x00FF0000 -> r=0x00 g=0x00 b=0xFF -> opaque blue.
      expect(argb, 0xFF0000FF,
          reason: 'this is the documented trap: a config hex of FF0000 '
              'renders BLUE, while a Lua font("#FF0000") renders RED because '
              'lib/scripting.c:149-160 builds it with RGB(r,g,b)');
    });

    test('colorrefToArgb and argbToColorref round-trip', () {
      for (final value in <int>[0x00000000, 0x00FFFFFF, 0x00FF0000, 0x00123456]) {
        expect(ConfigColor.argbToColorref(ConfigColor.colorrefToArgb(value)),
            value);
      }
    });
  });

  group('limits mirror config.h', () {
    test('the numeric limits match the header', () {
      expect(ConfigLimits.maxUrl, 1024);
      expect(ConfigLimits.maxName, 128);
      expect(ConfigLimits.maxExpr, 4096);
      expect(ConfigLimits.maxPath, 512);
      expect(ConfigLimits.maxItems, 64);
      expect(ConfigLimits.maxParams, 16);
      expect(ConfigLimits.maxParamKey, 64);
      expect(ConfigLimits.maxParamVal, 2048);
      expect(ConfigLimits.maxSources, 8);
    });

    test('maxBars comes from ui.h, not config.h', () {
      // src/ui.h:49, enforced by src/bar_window.c:445
      expect(ConfigLimits.maxBars, 16);
      expect(ConfigLimits.maxBars, lessThan(ConfigLimits.maxItems),
          reason: 'config.h allows 64 items but the bar layer only pins 16');
    });

    test('the model does not truncate to the limits', () {
      final long = 'x' * (ConfigLimits.maxName + 10);
      final item = PinItem.fromJson(<String, dynamic>{'name': long});
      expect(item.name.length, long.length,
          reason: 'truncation is data loss and belongs at the bar/engine '
              'boundary, not in the model');
    });
  });

  group('type coercion mirrors the C typed readers', () {
    test('a wrong-typed value behaves like an absent one', () {
      final item = PinItem.fromJson(<String, dynamic>{
        'name': 42,
        'interval_ms': 'fast',
        'pinned': 'yes',
      });
      expect(item.name, 'Untitled');
      expect(item.intervalMs, 5000);
      expect(item.pinned, isFalse);
    });

    test('a double is accepted for an int field', () {
      expect(PinItem.fromJson(<String, dynamic>{'interval_ms': 1000.0}).intervalMs,
          1000);
    });

    test('params that is not a list is ignored', () {
      expect(PinItem.fromJson(<String, dynamic>{'params': 'nope'}).paramCount, 0);
    });
  });

  group('unknown keys', () {
    test('are preserved at root, global, item and param level', () {
      final cfg = TaskPinConfig.fromJson(<String, dynamic>{
        'version': 1,
        'rootExtra': 1,
        'global': <String, dynamic>{'width': 200, 'globalExtra': 'g'},
        'items': <dynamic>[
          <String, dynamic>{
            'name': 'n',
            'itemExtra': true,
            'params': <dynamic>[
              <String, dynamic>{'key': 'K', 'paramExtra': <int>[1, 2]},
            ],
          },
        ],
        'sources': <String>['a/b'],
      });

      final json = cfg.toJson();
      expect(json['rootExtra'], 1);
      expect((json['global'] as Map)['globalExtra'], 'g');
      expect((json['items'] as List).first['itemExtra'], isTrue);
      expect(
        ((json['items'] as List).first['params'] as List).first['paramExtra'],
        <int>[1, 2],
      );
    });

    test('an unknown key can never shadow a known one', () {
      final cfg = TaskPinConfig(
        extra: <String, dynamic>{'width': 99999},
        width: 200,
      );
      final json = cfg.toJson();
      expect((json['global'] as Map)['width'], 200);
      expect(json['width'], 99999,
          reason: 'the stray root "width" is written back at the root, where '
              'it is inert, rather than clobbering global.width');
    });
  });

  group('serialization', () {
    test('toJsonString pretty-prints with tabs like cJSON_Print', () {
      final text = TaskPinConfig().toJsonString();
      expect(text, contains('\t'));
      expect(jsonDecode(text), isA<Map<String, dynamic>>());
    });

    test('serializing twice is byte-stable', () {
      final cfg = TaskPinConfig(
        items: [PinItem(name: 'a'), PinItem(name: 'b', barBgColor: '00FF0000')],
        sources: ['bestK/taskpin-plugins'],
      );
      expect(cfg.toJsonString(), cfg.toJsonString());
    });

    test('a non-object root is a format error', () {
      expect(
        () => TaskPinConfig.fromJsonString('[1,2,3]', path: 'x.json'),
        throwsA(isA<ConfigFormatError>()),
      );
    });

    test('invalid JSON is a format error', () {
      expect(
        () => TaskPinConfig.fromJsonString('{oops', path: 'x.json'),
        throwsA(isA<ConfigFormatError>()),
      );
    });

    test('a future version is refused', () {
      expect(
        () => TaskPinConfig.fromJsonString('{"version":2}', path: 'x.json'),
        throwsA(isA<ConfigVersionError>()),
      );
      // ...but can be read when the guard is explicitly disabled.
      expect(
        TaskPinConfig.fromJsonString('{"version":2}',
                path: 'x.json', enforceVersion: false)
            .version,
        2,
      );
    });
  });
}
