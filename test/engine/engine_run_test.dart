// The engine-result -> design-model conversion and the args-JSON builder.
//
// These are the two seams between `packages/taskpin_engine` (FFI models) and
// `packages/taskpin_design` (the bar preview model). The rule under test is the
// one the engine's ABI exists to enforce: a Lua error is carried in
// `ScriptResult.error` and must NOT be turned into bar spans.

import 'dart:convert';

import 'package:taskpin/core/config/config_schema.dart';
import 'package:taskpin/core/engine/engine_run.dart';
import 'package:taskpin_design/taskpin_design.dart';
import 'package:taskpin_engine/taskpin_engine.dart'
    show
        ClickAction,
        DialogSpec,
        ScriptResult,
        Span,
        SpanAlign;
import 'package:test/test.dart';

Span span({
  String text = 'hi',
  String color = '',
  int fontSize = 0,
  SpanAlign align = SpanAlign.left,
  bool newline = false,
  bool isImage = false,
}) =>
    Span(
      text: text,
      color: color,
      fontSize: fontSize,
      align: align,
      newline: newline,
      isImage: isImage,
      imageWidth: 0,
      imageHeight: 0,
    );

ScriptResult result({
  bool ok = true,
  String error = '',
  String display = '',
  List<Span> spans = const <Span>[],
}) =>
    ScriptResult(
      ok: ok,
      error: error,
      display: display,
      spans: spans,
      clickable: false,
      clickAction: ClickAction.url,
      clickUrl: '',
      dialog: DialogSpec.empty,
    );

void main() {
  group('barSpanFromEngine', () {
    test('copies text, size, align and newline', () {
      final TpBarSpan s = barSpanFromEngine(span(
        text: 'CPU',
        fontSize: 11,
        align: SpanAlign.right,
        newline: true,
      ));
      expect(s.text, 'CPU');
      expect(s.fontSize, 11);
      expect(s.align, TpSpanAlign.right);
      expect(s.newline, isTrue);
    });

    test('a "#RRGGBB" colour becomes a Color; empty becomes null', () {
      expect(barSpanFromEngine(span(color: '#4FC3F7')).color, isNotNull);
      expect(barSpanFromEngine(span(color: '')).color, isNull);
      // Malformed is treated as "no colour", not black.
      expect(barSpanFromEngine(span(color: 'not-a-colour')).color, isNull);
    });

    test('an image span carries its source and isImage flag', () {
      final TpBarSpan s = barSpanFromEngine(
        span(text: 'https://x/y.png', isImage: true),
      );
      expect(s.isImage, isTrue);
      expect(s.text, 'https://x/y.png');
    });
  });

  group('barContentFromResult', () {
    test('rich spans are preferred and converted in order', () {
      final TpBarContent c = barContentFromResult(result(spans: <Span>[
        span(text: 'A'),
        span(text: 'B'),
      ]));
      expect(c.spans.map((TpBarSpan s) => s.text).toList(), <String>['A', 'B']);
    });

    test('a plain string return lands in a single span', () {
      final TpBarContent c = barContentFromResult(result(display: 'CN'));
      expect(c.spans, hasLength(1));
      expect(c.spans.single.text, 'CN');
    });

    test('an empty result yields empty content', () {
      expect(barContentFromResult(result()).isEmpty, isTrue);
    });

    test('a Lua ERROR is never turned into bar content', () {
      // `ok == false` with an `error` but no spans: the preview must be empty,
      // NOT the error text. That is the whole point of the `error` field.
      final TpBarContent c = barContentFromResult(result(
        ok: false,
        error: 'attempt to index a nil value',
      ));
      expect(c.isEmpty, isTrue,
          reason: 'the Lua error must not be painted onto the bar');
    });

    test('a failed run keeps its PARTIAL output, separate from the error', () {
      // The engine leaves whatever the failed run produced; the host shows the
      // error alongside it, not instead of the partial spans.
      final TpBarContent c = barContentFromResult(result(
        ok: false,
        error: 'boom',
        spans: <Span>[span(text: 'partial')],
      ));
      expect(c.spans.single.text, 'partial');
    });
  });

  group('argsJsonFromParams', () {
    test('maps keys to values', () {
      final String json = argsJsonFromParams(<ParamEntry>[
        ParamEntry(key: 'VIN', value: 'abc'),
        ParamEntry(key: 'TIMEOUT', value: '30'),
      ]);
      expect(jsonDecode(json), <String, String>{'VIN': 'abc', 'TIMEOUT': '30'});
    });

    test('an empty list yields an empty string (the engine binds no args)', () {
      expect(argsJsonFromParams(<ParamEntry>[]), '');
    });

    test('a blank key is dropped rather than emitting invalid JSON', () {
      final String json = argsJsonFromParams(<ParamEntry>[
        ParamEntry(key: '  ', value: 'x'),
        ParamEntry(key: 'K', value: 'v'),
      ]);
      expect(jsonDecode(json), <String, String>{'K': 'v'});
    });

    test('values are JSON-encoded, so quotes and CJK survive', () {
      final String json = argsJsonFromParams(<ParamEntry>[
        ParamEntry(key: 'NAME', value: 'a "quoted" 名字'),
      ]);
      expect(jsonDecode(json)['NAME'], 'a "quoted" 名字');
    });
  });
}
