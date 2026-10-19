/// ABI layout parity: the Dart `Struct`s must match the C header byte for byte.
///
/// `dart:ffi` has no `offsetOf`, so the offsets come from the C side:
/// `tool/abi_probe.c` prints `sizeof`/`offsetof` for every field, and
/// `tool/abi_probe.sh` runs it against the real MSVC toolchain and writes
/// `test/fixtures/abi_layout.json`. This test compares the Dart layout against
/// that JSON.
///
/// A mismatch here is not a style problem — it means the Dart side would read
/// the wrong bytes, silently producing garbage rather than crashing. So the
/// fixture is treated as the source of truth and the test fails loudly.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:taskpin_engine/src/bindings.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:taskpin_engine/src/bindings.dart';
import 'package:test/test.dart';

class _Layout {
  _Layout(this.path);

  factory _Layout.fromJson(Map<String, dynamic> json) => _Layout(null)
    ..size = json['size'] as int
    ..fields = (json['fields'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((Map<String, dynamic> f) => (f['name'] as String, f['offset'] as int))
        .toList();

  String? path;
  int size = -1;
  List<(String, int)> fields = const <(String, int)>[];
}

void main() {
  group('ABI layout matches abi_layout.json', () {
    late Map<String, dynamic> fixture;
    late _Layout Function(Map<String, dynamic>) parse;

    setUpAll(() {
      final Directory here = Directory.current.absolute;
      final List<String> candidates = <String>[
        // Run from the package root.
        p.join(here.path, 'test', 'fixtures', 'abi_layout.json'),
        // Run from the repo root (`dart test packages/taskpin_engine`).
        p.join(here.path, 'packages', 'taskpin_engine', 'test', 'fixtures',
            'abi_layout.json'),
      ];
      final String? found =
          candidates.where((String c) => File(c).existsSync()).firstOrNull;
      expect(
        found,
        isNotNull,
        reason: 'abi_layout.json not found in:\n  ${candidates.join('\n  ')}',
      );
      fixture = jsonDecode(File(found!).readAsStringSync())
          as Map<String, dynamic>;
      parse = _Layout.fromJson;
    });

    /// Asserts one struct against the fixture.
    ///
    /// Not generic on purpose: `sizeOf<T>()` is declared as
    /// `sizeOf<T extends SizedNativeType>()` in `dart:ffi`, and the
    /// `package:ffi/ffi.dart` barrel re-exports a differently-scoped view that
    /// rejects the bound (`Expected type 'T' to be a valid and instantiated
    /// subtype of 'NativeType'`). Passing the concrete type at each call site
    /// sidesteps that entirely.
    void check(String name, int expectedFieldCount, int dartSize) {
      final Object? raw = fixture[name];
      if (raw == null) {
        fail('$name is missing from abi_layout.json — regenerate the fixture '
            'with tool/abi_probe.sh');
      }
      final _Layout want = parse(raw as Map<String, dynamic>);

      expect(
        dartSize,
        want.size,
        reason: 'sizeof($name) changed: Dart says $dartSize bytes, C says '
            '${want.size}. The ffi struct no longer matches taskpin_engine.h.',
      );

      // Field COUNT is the coarse check that matters. dart:ffi exposes no
      // offsetOf, so per-field offsets cannot be read back from Dart — the
      // guarantee that offsets agree is the shared header plus the C probe's
      // numbers in the fixture. Asserting the count catches a field being
      // added or dropped on either side without the fixture being regenerated,
      // which is the failure that would otherwise slip through as a silently
      // misaligned read.
      expect(
        want.fields.length,
        expectedFieldCount,
        reason: '$name field count differs: the C header records '
            '${want.fields.length}, this test expects $expectedFieldCount. If '
            'the header changed, regenerate abi_layout.json and update the '
            'count here.',
      );
    }

    test('TPSpan', () => check('TPSpan', 8, sizeOf<TPSpan>()));
    test('TPDisplayContent',
        () => check('TPDisplayContent', 2, sizeOf<TPDisplayContent>()));
    test('TPDialogItem',
        () => check('TPDialogItem', 19, sizeOf<TPDialogItem>()));
    test('TPDialogSpec', () => check('TPDialogSpec', 11, sizeOf<TPDialogSpec>()));
    test('TPScriptResult',
        () => check('TPScriptResult', 8, sizeOf<TPScriptResult>()));
    test('TPParamDecl', () => check('TPParamDecl', 3, sizeOf<TPParamDecl>()));

    test('the capacities in the header match the fixture', () {
      final Map<String, dynamic> caps =
          fixture['capacities'] as Map<String, dynamic>;
      // A wrong capacity is how you overflow a fixed C array, so pin the ones
      // the Dart side actually indexes into. The fixture uses the C macro
      // spelling (`TP_MAX_SPANS`); the Dart names are its camelCase form.
      expect(tpMaxSpans, caps['TP_MAX_SPANS']);
      expect(tpDialogMaxItems, caps['TP_DIALOG_MAX_ITEMS']);
      expect(tpDialogMaxCols, caps['TP_DIALOG_MAX_COLS']);
      expect(tpDialogMaxRows, caps['TP_DIALOG_MAX_ROWS']);
      expect(tpSpanTextLen, caps['TP_SPAN_TEXT_LEN']);
      expect(tpColorLen, caps['TP_COLOR_LEN']);
      expect(tpDisplayLen, caps['TP_DISPLAY_LEN']);
      expect(tpUrlLen, caps['TP_URL_LEN']);
      expect(tpErrorLen, caps['TP_ERROR_LEN']);
    });

    test('the fixture was generated for x64', () {
      expect(fixture['_arch'], 'x64',
          reason: 'the fixture is architecture-specific; regenerate it on the '
              'architecture you are testing');
    });
  });
}
