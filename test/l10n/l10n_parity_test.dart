// i18n parity test.
//
// The ARB files must have the same keys in both languages, and must still
// contain every key migrated from `lang/{en-US,zh-CN}.json`. New keys are
// allowed, so the test checks "legacy keys are a subset", not equality.
//
// The `lang/*.json` files are read-only here.
//
// Run with: flutter test test/l10n

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `main.col_name` -> `mainColName`.
///
/// This is a deliberate re-implementation of the algorithm in
/// `tool/migrate_lang.py:camel_case`. The duplication is the point: if the tool
/// and the test disagree, the test fails, which is exactly the check we want.
/// Keep the two in step.
String camelCase(String dotted) {
  final segments = dotted.split('.');
  final parts = <String>[];
  for (final segment in segments) {
    final words = segment.split('_');
    final tail = words.skip(1).map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1));
    parts.add(words.first + tail.join());
  }
  return parts.first +
      parts.skip(1).map((s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1)).join();
}

Map<String, String> readLangJson(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: 'missing source file: $path');
  final decoded = jsonDecode(file.readAsStringSync(encoding: utf8)) as Map;
  return decoded.map((k, v) => MapEntry(k as String, v as String));
}

Map<String, String> readArb(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue,
      reason: 'missing generated ARB: $path — run '
          '`python -X utf8 tool/migrate_lang.py`');
  final decoded = jsonDecode(file.readAsStringSync(encoding: utf8)) as Map;
  // Metadata entries (`@key`, with a map value) are read by `readArbMeta`.
  return {
    for (final e in decoded.entries)
      if (e.value is String) e.key as String: e.value as String,
  };
}

/// The `@key` metadata entries of an ARB file.
Map<String, Object?> readArbMeta(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync(encoding: utf8)) as Map;
  return {
    for (final e in decoded.entries)
      if ((e.key as String).startsWith('@') && e.key != '@@locale')
        e.key as String: e.value,
  };
}

/// The five keys whose values carry printf-style placeholders. gen-l10n does
/// not understand `%s`/`%d`, so these are copied verbatim and formatted at the
/// call site. Pinned here so the decision cannot change silently.
const printfKeys = <String>{
  'barUpdateAvailable',
  'marketOverwriteConfirm',
  'marketScriptCount',
  'scriptingVersionRequired',
  'webviewErrDownloadFailed',
};

void main() {
  const enSourcePath = 'lang/en-US.json';
  const zhSourcePath = 'lang/zh-CN.json';
  const enArbPath = 'lib/l10n/app_en.arb';
  const zhArbPath = 'lib/l10n/app_zh.arb';

  late Map<String, String> enSource;
  late Map<String, String> zhSource;
  late Map<String, String> enArb;
  late Map<String, String> zhArb;

  setUpAll(() {
    enSource = readLangJson(enSourcePath);
    zhSource = readLangJson(zhSourcePath);
    enArb = readArb(enArbPath);
    zhArb = readArb(zhArbPath);
  });

  group('source language files', () {
    test('en-US.json has 99 keys', () {
      expect(enSource, hasLength(99));
    });

    test('zh-CN.json has 99 keys', () {
      expect(zhSource, hasLength(99));
    });

    test('the two sources have identical key sets', () {
      expect(enSource.keys.toSet(), equals(zhSource.keys.toSet()));
    });
  });

  group('generated ARB files', () {
    test('app_en.arb declares the en locale', () {
      expect(enArb['@@locale'], 'en');
    });

    test('app_zh.arb declares the zh locale', () {
      expect(zhArb['@@locale'], 'zh');
    });

    test('@@locale is the first key, so generated diffs stay stable', () {
      expect(enArb.keys.first, '@@locale');
      expect(zhArb.keys.first, '@@locale');
    });

    test('each ARB contains the 99 legacy keys', () {
      final expected = enSource.keys.map(camelCase).toSet();
      expect(expected, hasLength(99));
      expect(enArb.keys.toSet().containsAll(expected), isTrue);
      expect(zhArb.keys.toSet().containsAll(expected), isTrue);
    });

    test('en and zh ARB key sets are identical', () {
      expect(enArb.keys.toSet(), equals(zhArb.keys.toSet()));
    });

    test('legacy keys are a subset of both ARB key sets', () {
      final legacy = enSource.keys.map(camelCase).toSet();
      final enKeys = enArb.keys.where((k) => k != '@@locale').toSet();
      final zhKeys = zhArb.keys.where((k) => k != '@@locale').toSet();

      expect(legacy.difference(enKeys), isEmpty,
          reason: 'keys missing from app_en.arb');
      expect(legacy.difference(zhKeys), isEmpty,
          reason: 'keys missing from app_zh.arb');
      expect(enKeys, equals(zhKeys));
    });

    test('placeholder metadata in en matches zh', () {
      final en = readArbMeta(enArbPath);
      final zh = readArbMeta(zhArbPath);
      expect(en.keys.toSet(), equals(zh.keys.toSet()));
      for (final key in en.keys) {
        expect(zh[key], equals(en[key]), reason: 'placeholders of $key differ');
      }
    });

    test('camelCase conversion is collision-free', () {
      final names = enSource.keys.map(camelCase).toList();
      expect(names.toSet(), hasLength(names.length),
          reason: 'a collision would silently merge two keys');
    });
  });

  group('values are preserved verbatim', () {
    test('every en ARB value matches its source string', () {
      for (final entry in enSource.entries) {
        final key = camelCase(entry.key);
        expect(enArb[key], equals(entry.value),
            reason: 'app_en.arb[$key] must be byte-identical to '
                'lang/en-US.json[${entry.key}]');
      }
    });

    test('every zh ARB value matches its source string', () {
      for (final entry in zhSource.entries) {
        final key = camelCase(entry.key);
        expect(zhArb[key], equals(entry.value),
            reason: 'app_zh.arb[$key] must be byte-identical to '
                'lang/zh-CN.json[${entry.key}]');
      }
    });

    test('Chinese text is not mangled', () {
      expect(zhArb['mainColName'], '名称');
      expect(zhArb['mainColInterval'], '刷新间隔');
      expect(zhArb['settingsAutoStart'], '开机自启动');
      // Non-BMP/emoji content survives too.
      expect(zhArb['elevateBlocked'], contains('⚠️'));
      expect(enArb['elevateBlocked'], contains('⚠️'));
    });

    test('embedded newlines are preserved', () {
      expect(enArb['marketEnterRepo'], contains('\n'));
      expect(zhArb['marketEnterRepo'], contains('\n'));
      expect(enArb['webviewErrDownloadFailed']!.split('\n'), hasLength(3));
    });

    test('no value is empty', () {
      for (final entry in enArb.entries) {
        if (entry.key == '@@locale') continue;
        expect(entry.value, isNotEmpty, reason: 'app_en.arb[${entry.key}]');
      }
      for (final entry in zhArb.entries) {
        if (entry.key == '@@locale') continue;
        expect(entry.value, isNotEmpty, reason: 'app_zh.arb[${entry.key}]');
      }
    });
  });

  group('printf placeholders', () {
    test('exactly the expected five keys carry printf placeholders', () {
      final printfPattern = RegExp(r'%[sd]');
      final found = <String>{};
      for (final entry in enArb.entries) {
        if (entry.key == '@@locale') continue;
        if (printfPattern.hasMatch(entry.value) ||
            printfPattern.hasMatch(zhArb[entry.key] ?? '')) {
          found.add(entry.key);
        }
      }
      expect(found, equals(printfKeys),
          reason: 'gen-l10n does not understand %s/%d, so these keys generate '
              'plain String getters and call sites format them in Dart. If '
              'this set changes, the Phase 5 decision about ICU placeholders '
              'has drifted.');
    });

    test('a value with braces declares its placeholders', () {
      final meta = readArbMeta(enArbPath);
      for (final arb in <Map<String, String>>[enArb, zhArb]) {
        for (final entry in arb.entries) {
          if (entry.key == '@@locale') continue;
          if (entry.value.contains('{') || entry.value.contains('}')) {
            expect(meta.containsKey('@${entry.key}'), isTrue,
                reason: '${entry.key} has braces but no @${entry.key} metadata');
          }
        }
      }
    });
  });

  group('coverage of the original namespaces', () {
    test('every namespace is represented', () {
      final namespaces = enSource.keys.map((k) => k.split('.').first).toSet();
      expect(
        namespaces,
        containsAll(<String>[
          'main',
          'confirm',
          'edit',
          'settings',
          'market',
          'bar',
          'scripting',
          'app',
          'webview',
          'elevate',
        ]),
      );
    });

    test('specific plan-called-out keys are present', () {
      // The plan mentions elevate.* keys must be kept.
      expect(enArb.keys, containsAll(<String>[
        'elevateBlocked',
        'elevateDescDefault',
        'elevateRestartConfirm',
        'elevateDialogTitle',
      ]));
      // webview.* keys are referenced by Phase 9.
      expect(enArb.keys, containsAll(<String>[
        'webviewDragHint',
        'webviewErrNoRuntime',
        'webviewErrDownloadFailed',
      ]));
      // the dotted-name keys, to prove the camelCase mapping.
      expect(enArb, containsPair('mainColName', 'Name'));
      expect(zhArb, containsPair('mainColName', '名称'));
    });
  });
}
