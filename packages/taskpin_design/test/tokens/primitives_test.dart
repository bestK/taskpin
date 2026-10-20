// Primitive values are the docs/VISUAL_SPEC.md §1 tables, verbatim.

import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin_design/taskpin_design.dart';

void main() {
  group('dark primitives match the spec table', () {
    test('surfaces', () {
      expect(TpPrimitives.darkBgWindow, const Color(0xFF1C1E22));
      expect(TpPrimitives.darkBgCard, const Color(0xFF24262B));
      expect(TpPrimitives.darkBgCardSecondary, const Color(0xFF2A2D33));
      expect(TpPrimitives.darkBgFlyout, const Color(0xFF2C2E34));
    });

    test('strokes', () {
      expect(TpPrimitives.darkStrokeCard, const Color(0x33FFFFFF));
      expect(TpPrimitives.darkStrokeDivider, const Color(0x26FFFFFF));
    });

    test('controls', () {
      expect(TpPrimitives.darkControlFill, const Color(0x0FFFFFFF));
      expect(TpPrimitives.darkControlFillHover, const Color(0x15FFFFFF));
      expect(TpPrimitives.darkControlFillPressed, const Color(0x08FFFFFF));
      expect(
          TpPrimitives.darkControlFillInputActive, const Color(0xB31E1E1E));
      expect(TpPrimitives.darkControlStroke, const Color(0x12FFFFFF));
      expect(TpPrimitives.darkControlStrokeBottom, const Color(0x18FFFFFF));
      expect(TpPrimitives.darkControlStrokeStrong, const Color(0x8BFFFFFF));
    });

    test('subtle, text, accent, status', () {
      expect(TpPrimitives.darkSubtleHover, const Color(0x0FFFFFFF));
      expect(TpPrimitives.darkSubtlePressed, const Color(0x0AFFFFFF));
      expect(TpPrimitives.darkTextPrimary, const Color(0xFFFFFFFF));
      expect(TpPrimitives.darkTextSecondary, const Color(0xC5FFFFFF));
      expect(TpPrimitives.darkTextTertiary, const Color(0x87FFFFFF));
      expect(TpPrimitives.darkTextDisabled, const Color(0x5DFFFFFF));
      expect(TpPrimitives.darkAccentFill, const Color(0xFF4C8DFF));
      expect(TpPrimitives.darkAccentFillHover, const Color(0xFF5C99FF));
      expect(TpPrimitives.darkAccentOnFill, const Color(0xFFFFFFFF));
      expect(TpPrimitives.darkAccentText, const Color(0xFF7FB0FF));
      expect(TpPrimitives.darkStatusSuccess, const Color(0xFF5BD08A));
      expect(TpPrimitives.darkStatusCaution, const Color(0xFFF5C542));
      expect(TpPrimitives.darkStatusCritical, const Color(0xFFFF8A80));
      expect(TpPrimitives.darkStatusNeutral, const Color(0xFF9AA0A8));
    });

    test('focus inner ring', () {
      expect(TpPrimitives.darkFocusInner, const Color(0xB3000000));
    });
  });

  group('light primitives match the spec table', () {
    test('surfaces', () {
      // Cooler and slightly darker than the spec's original #F6F6F3; see
      // the EYE COMFORT note in primitives.dart. Cards stay white so they
      // keep an edge against the ground.
      expect(TpPrimitives.lightBgWindow, const Color(0xFFEDEEF0));
      expect(TpPrimitives.lightBgCard, const Color(0xFFFFFFFF));
      expect(TpPrimitives.lightBgCardSecondary, const Color(0xFFF3F4F6));
      expect(TpPrimitives.lightBgFlyout, const Color(0xFFFFFFFF));
    });

    test('controls', () {
      expect(TpPrimitives.lightControlFill, const Color(0xB3FFFFFF));
      expect(TpPrimitives.lightControlFillHover, const Color(0x80F9F9F9));
      expect(TpPrimitives.lightControlFillPressed, const Color(0x4DF9F9F9));
      expect(TpPrimitives.lightControlFillInputActive, const Color(0xFFFFFFFF));
      expect(TpPrimitives.lightControlStroke, const Color(0x0F000000));
      expect(TpPrimitives.lightControlStrokeBottom, const Color(0x29000000));
      expect(TpPrimitives.lightControlStrokeStrong, const Color(0x72000000));
    });

    test('text, accent, status', () {
      expect(TpPrimitives.lightTextPrimary, const Color(0xE4000000));
      expect(TpPrimitives.lightTextSecondary, const Color(0x9E000000));
      expect(TpPrimitives.lightTextTertiary, const Color(0x72000000));
      expect(TpPrimitives.lightTextDisabled, const Color(0x5C000000));
      // Desaturated from the spec's #2457D6 so a primary button stops
      // reading as an alarm on a light page; white on it is still 6.5:1.
      expect(TpPrimitives.lightAccentFill, const Color(0xFF2C5FA8));
      expect(TpPrimitives.lightAccentFillHover, const Color(0xFF24508F));
      expect(TpPrimitives.lightAccentOnFill, const Color(0xFFFFFFFF));
      expect(TpPrimitives.lightAccentText, const Color(0xFF2C5FA8));
      expect(TpPrimitives.lightStatusSuccess, const Color(0xFF1E7F4F));
      expect(TpPrimitives.lightStatusCaution, const Color(0xFFB07800));
      expect(TpPrimitives.lightStatusCritical, const Color(0xFFB42318));
      expect(TpPrimitives.lightStatusNeutral, const Color(0xFF868A93));
    });

    test('focus inner ring', () {
      expect(TpPrimitives.lightFocusInner, const Color(0xB3FFFFFF));
    });
  });

  test('smoke is 4D000000 in both themes', () {
    expect(TpPrimitives.smoke, const Color(0x4D000000));
  });
}
