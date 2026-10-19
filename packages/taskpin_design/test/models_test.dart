// Model tests: the bar span ABI mirror and the @param declaration shape.
//
// `TpBarSpan` mirrors the `TPSpan` C struct field-for-field. These tests pin
// the parts that are a contract with the native side: the align integer
// values, the wire colour format, and the newline/line-grouping behaviour.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin_design/taskpin_design.dart';

void main() {
  group('TpSpanAlign', () {
    test('integer values match the C ABI', () {
      // 0 left / 1 right / 2 center — do not reorder.
      expect(TpSpanAlign.left.abiValue, 0);
      expect(TpSpanAlign.right.abiValue, 1);
      expect(TpSpanAlign.center.abiValue, 2);
    });

    test('fromAbi round-trips', () {
      for (final TpSpanAlign a in TpSpanAlign.values) {
        expect(TpSpanAlign.fromAbi(a.abiValue), a);
      }
    });

    test('fromAbi falls back to left for unknown values', () {
      // Matches the native renderers' default branch.
      expect(TpSpanAlign.fromAbi(-1), TpSpanAlign.left);
      expect(TpSpanAlign.fromAbi(99), TpSpanAlign.left);
    });
  });

  group('TpBarSpan', () {
    test('defaults match the ABI sentinels', () {
      const TpBarSpan span = TpBarSpan();
      expect(span.text, '');
      expect(span.color, isNull); // "" in C
      expect(span.fontSize, 0); // 0 = default in C
      expect(span.align, TpSpanAlign.left);
      expect(span.newline, isFalse);
      expect(span.isImage, isFalse);
      expect(span.imageWidth, 0);
      expect(span.imageHeight, 0);
    });

    test('colorWire emits #RRGGBB', () {
      const TpBarSpan span = TpBarSpan(color: Color(0xFF3FB950));
      expect(span.colorWire, '#3fb950');
    });

    test('colorWire is empty when there is no override', () {
      // The C side uses "" to mean "use the token default".
      expect(const TpBarSpan().colorWire, '');
    });

    test('colorWire ignores the alpha channel', () {
      // The ABI is #RRGGBB; a translucent override would silently lose its
      // alpha rather than mis-encode.
      const TpBarSpan span = TpBarSpan(color: Color(0x803FB950));
      expect(span.colorWire, '#3fb950');
    });

    test('parseWireColor reads #RRGGBB as opaque', () {
      final Color? c = TpBarSpan.parseWireColor('#3FB950');
      expect(c, isNotNull);
      expect(c!.toARGB32(), 0xFF3FB950);
    });

    test('parseWireColor rejects malformed input', () {
      expect(TpBarSpan.parseWireColor(''), isNull);
      expect(TpBarSpan.parseWireColor('3FB950'), isNull);
      expect(TpBarSpan.parseWireColor('#FFF'), isNull);
      expect(TpBarSpan.parseWireColor('#ZZZZZZ'), isNull);
    });

    test('parseWireColor round-trips through colorWire', () {
      const List<String> wires = <String>['#000000', '#FFFFFF', '#3FB950'];
      for (final String wire in wires) {
        final Color? parsed = TpBarSpan.parseWireColor(wire);
        expect(parsed, isNotNull);
        final TpBarSpan span = TpBarSpan(color: parsed);
        expect(span.colorWire, wire.toLowerCase());
      }
    });

    test('copyWith replaces only what it is given', () {
      const TpBarSpan base = TpBarSpan(text: 'CPU', fontSize: 12);
      final TpBarSpan next = base.copyWith(align: TpSpanAlign.right);
      expect(next.text, 'CPU');
      expect(next.fontSize, 12);
      expect(next.align, TpSpanAlign.right);
    });

    test('copyWith can clear a colour override', () {
      // Needed by SpanInspector: "back to default" is a real state, and
      // passing null would mean "leave unchanged".
      const TpBarSpan base = TpBarSpan(color: Color(0xFF3FB950));
      expect(base.copyWith(clearColor: true).color, isNull);
    });
  });

  group('TpBarContent', () {
    test('groups spans into lines on the newline flag', () {
      const TpBarContent content = TpBarContent(
        spans: <TpBarSpan>[
          TpBarSpan(text: 'A'),
          TpBarSpan(text: 'B'),
          TpBarSpan(text: 'C', newline: true),
        ],
      );

      expect(content.lineCount, 2);
      expect(content.lines[0].map((TpBarSpan s) => s.text).toList(), <String>['A', 'B']);
      expect(content.lines[1].map((TpBarSpan s) => s.text).toList(), <String>['C']);
    });

    test('the first span never starts a new line', () {
      // Otherwise a leading newline would render an empty first line.
      const TpBarContent content = TpBarContent(
        spans: <TpBarSpan>[TpBarSpan(text: 'A', newline: true)],
      );
      expect(content.lineCount, 1);
    });

    test('an empty content has no lines', () {
      const TpBarContent content = TpBarContent();
      expect(content.isEmpty, isTrue);
      expect(content.lineCount, 0);
    });

    test('plainText joins lines and spaces', () {
      const TpBarContent content = TpBarContent(
        spans: <TpBarSpan>[
          TpBarSpan(text: 'CPU'),
          TpBarSpan(text: '42%'),
          TpBarSpan(text: 'MEM', newline: true),
          TpBarSpan(text: '12GB'),
        ],
      );
      expect(content.plainText, 'CPU 42%\nMEM 12GB');
    });

    test('clamps to the 32-span ABI limit', () {
      final TpBarContent content = TpBarContent(
        spans: List<TpBarSpan>.generate(
          40,
          (int i) => TpBarSpan(text: '$i'),
        ),
      );

      expect(content.spans.length, 40);
      expect(content.clamped().spans.length, TpBarContent.maxSpans);
      expect(TpBarContent.maxSpans, 32);
    });

    test('clamping a short list returns it unchanged', () {
      const TpBarContent content = TpBarContent(
        spans: <TpBarSpan>[TpBarSpan(text: 'A')],
      );
      expect(identical(content.clamped(), content), isTrue);
    });
  });

  group('TpParamType', () {
    test('wire names match the @param header tokens', () {
      expect(TpParamType.string.wireName, 'string');
      expect(TpParamType.number.wireName, 'number');
      expect(TpParamType.boolean.wireName, 'boolean');
      expect(TpParamType.color.wireName, 'color');
      expect(TpParamType.path.wireName, 'path');
    });

    test('fromWire is case-insensitive and trims', () {
      expect(TpParamType.fromWire(' NUMBER '), TpParamType.number);
      expect(TpParamType.fromWire('Boolean'), TpParamType.boolean);
    });

    test('fromWire degrades unknown types to string', () {
      // A typo in a script header must not stop the script running.
      expect(TpParamType.fromWire('widget'), TpParamType.string);
      expect(TpParamType.fromWire(''), TpParamType.string);
    });
  });

  group('TpParamDecl and TpParamValue', () {
    test('displayLabel falls back to the key', () {
      const TpParamDecl d = TpParamDecl(
        key: 'USER_ID',
        type: TpParamType.number,
        label: '',
      );
      expect(d.displayLabel, 'USER_ID');
    });

    test('displayLabel prefers the declared label', () {
      const TpParamDecl d = TpParamDecl(
        key: 'USER_ID',
        type: TpParamType.number,
        label: 'User ID',
      );
      expect(d.displayLabel, 'User ID');
    });

    test('numberValue parses and degrades to null', () {
      const TpParamDecl decl = TpParamDecl(
        key: 'K',
        type: TpParamType.number,
        label: 'K',
      );
      expect(const TpParamValue(decl: decl, value: '42').numberValue, 42);
      expect(const TpParamValue(decl: decl, value: '3.5').numberValue, 3.5);
      // A malformed value shows an error rather than crashing the page.
      expect(const TpParamValue(decl: decl, value: 'abc').numberValue, isNull);
      expect(const TpParamValue(decl: decl, value: '').numberValue, isNull);
    });

    test('booleanValue accepts the usual truthy spellings', () {
      const TpParamDecl decl = TpParamDecl(
        key: 'K',
        type: TpParamType.boolean,
        label: 'K',
      );
      for (final String truthy in <String>['true', 'TRUE', '1', 'yes', 'on']) {
        expect(
          TpParamValue(decl: decl, value: truthy).booleanValue,
          isTrue,
          reason: '$truthy should be true',
        );
      }
      for (final String falsy in <String>['false', '0', 'no', 'off', '']) {
        expect(
          TpParamValue(decl: decl, value: falsy).booleanValue,
          isFalse,
          reason: '$falsy should be false',
        );
      }
    });

    test('key proxies the declaration', () {
      const TpParamValue v = TpParamValue(
        decl: TpParamDecl(
          key: 'TOKEN',
          type: TpParamType.string,
          label: 'Token',
        ),
      );
      expect(v.key, 'TOKEN');
    });
  });

  group('TpColorHex', () {
    test('serialises to uppercase AARRGGBB', () {
      expect(TpColorHex.toWire(const Color(0xFF3FB950)), 'FF3FB950');
      expect(TpColorHex.toWire(const Color(0x00000000)), '00000000');
    });

    test('can omit the alpha channel', () {
      expect(
        TpColorHex.toWire(const Color(0xFF3FB950), withAlpha: false),
        '3FB950',
      );
    });

    test('parses AARRGGBB and RRGGBB, with or without a hash', () {
      expect(TpColorHex.fromWire('FF3FB950')!.toARGB32(), 0xFF3FB950);
      expect(TpColorHex.fromWire('3FB950')!.toARGB32(), 0xFF3FB950);
      expect(TpColorHex.fromWire('#3fb950')!.toARGB32(), 0xFF3FB950);
      expect(TpColorHex.fromWire('  3FB950  ')!.toARGB32(), 0xFF3FB950);
    });

    test('rejects malformed input', () {
      expect(TpColorHex.fromWire(''), isNull);
      expect(TpColorHex.fromWire('GGGGGG'), isNull);
      expect(TpColorHex.fromWire('12345'), isNull);
    });

    test('round-trips the real config value', () {
      // config.json has bar_bg_color "FFFFFFFF" (inherit) and
      // bg_color "00000000" (transparent). Both must survive.
      expect(TpColorHex.toWire(TpColorHex.fromWire('FFFFFFFF')!), 'FFFFFFFF');
      expect(TpColorHex.toWire(TpColorHex.fromWire('00000000')!), '00000000');
    });

    test('recognises the inherit sentinel', () {
      expect(TpColorHex.isInherit('FFFFFFFF'), isTrue);
      expect(TpColorHex.isInherit('ffffffff'), isTrue);
      expect(TpColorHex.isInherit('FF3FB950'), isFalse);
      // Note: this is why the sentinel is dangerous — it collides with opaque
      // white. The plan's format is frozen, so this is documented, not fixed.
      expect(kColorInherit, 'FFFFFFFF');
    });

    test('detects full transparency', () {
      // The case that makes the native bar switch to a layered window.
      expect(TpColorHex.isTransparent(const Color(0x00000000)), isTrue);
      expect(TpColorHex.isTransparent(const Color(0x01000000)), isFalse);
      expect(TpColorHex.isTransparent(const Color(0xFF000000)), isFalse);
    });
  });
}
