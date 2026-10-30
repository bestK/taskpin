// Primitive values are the stage world's colour table: a black ground, two
// near-black raised surfaces, hairlines, and the text/green/red set the whole
// UI is built from. Pinned here so a stray edit cannot quietly move the
// world.

import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin_design/taskpin_design.dart';

void main() {
  group('dark primitives match the spec table', () {
    test('surfaces', () {
      expect(TpPrimitives.darkBgWindow, const Color(0xFF000000));
      expect(TpPrimitives.darkBgCard, const Color(0xFF111113));
      expect(TpPrimitives.darkBgCardSecondary, const Color(0xFF1D1D20));
      expect(TpPrimitives.darkBgFlyout, const Color(0xFF1D1D20));
    });

    test('strokes', () {
      expect(TpPrimitives.darkStrokeCard, const Color(0xFF1D1D1F));
      expect(TpPrimitives.darkStrokeDivider, const Color(0xFF1D1D1F));
    });

    test('controls', () {
      expect(TpPrimitives.darkControlFill, const Color(0xFF1D1D1F));
      expect(TpPrimitives.darkControlFillHover, const Color(0xFF2A2A2E));
      expect(TpPrimitives.darkControlFillPressed, const Color(0xFF161618));
      expect(
          TpPrimitives.darkControlFillInputActive, const Color(0xFF111113));
      expect(TpPrimitives.darkControlStroke, const Color(0x00000000));
      expect(TpPrimitives.darkControlStrokeBottom, const Color(0x00000000));
      expect(TpPrimitives.darkControlStrokeStrong, const Color(0xFF39393D));
    });

    test('subtle, text, accent, status', () {
      expect(TpPrimitives.darkSubtleHover, const Color(0x14FFFFFF));
      expect(TpPrimitives.darkSubtlePressed, const Color(0x0AFFFFFF));
      expect(TpPrimitives.darkTextPrimary, const Color(0xFFF5F5F7));
      expect(TpPrimitives.darkTextSecondary, const Color(0xFFA1A1A6));
      expect(TpPrimitives.darkTextTertiary, const Color(0xFF86868B));
      expect(TpPrimitives.darkTextDisabled, const Color(0xFF515154));
      expect(TpPrimitives.darkAccentFill, const Color(0xFFF5F5F7));
      expect(TpPrimitives.darkAccentFillHover, const Color(0xFFFFFFFF));
      expect(TpPrimitives.darkAccentOnFill, const Color(0xFF000000));
      expect(TpPrimitives.darkAccentText, const Color(0xFF2997FF));
      expect(TpPrimitives.darkStatusSuccess, const Color(0xFF30D158));
      expect(TpPrimitives.darkStatusCaution, const Color(0xFFFFD60A));
      expect(TpPrimitives.darkStatusCritical, const Color(0xFFFF6961));
      expect(TpPrimitives.darkStatusNeutral, const Color(0xFF86868B));
    });

    test('focus inner ring', () {
      expect(TpPrimitives.darkFocusInner, const Color(0xFF000000));
    });
  });

  group('light primitives match the spec table', () {
    test('surfaces', () {
      // The light ground is the stage's pale counterpart: #F5F5F7 ground,
      // white cards.
      expect(TpPrimitives.lightBgWindow, const Color(0xFFF5F5F7));
      expect(TpPrimitives.lightBgCard, const Color(0xFFFFFFFF));
      expect(TpPrimitives.lightBgCardSecondary, const Color(0xFFF3F4F6));
      expect(TpPrimitives.lightBgFlyout, const Color(0xFFFFFFFF));
    });

    test('controls', () {
      expect(TpPrimitives.lightControlFill, const Color(0xFFFFFFFF));
      expect(TpPrimitives.lightControlFillHover, const Color(0xFFEDEDF0));
      expect(TpPrimitives.lightControlFillPressed, const Color(0x4DF9F9F9));
      expect(TpPrimitives.lightControlFillInputActive, const Color(0xFFFFFFFF));
      expect(TpPrimitives.lightControlStroke, const Color(0x00000000));
      expect(TpPrimitives.lightControlStrokeBottom, const Color(0x00000000));
      expect(TpPrimitives.lightControlStrokeStrong, const Color(0x72000000));
    });

    test('text, accent, status', () {
      expect(TpPrimitives.lightTextPrimary, const Color(0xFF1D1D1F));
      expect(TpPrimitives.lightTextSecondary, const Color(0xFF6E6E73));
      expect(TpPrimitives.lightTextTertiary, const Color(0x72000000));
      expect(TpPrimitives.lightTextDisabled, const Color(0x5C000000));
      expect(TpPrimitives.lightAccentFill, const Color(0xFF1D1D1F));
      expect(TpPrimitives.lightAccentFillHover, const Color(0xFF000000));
      expect(TpPrimitives.lightAccentOnFill, const Color(0xFFFFFFFF));
      expect(TpPrimitives.lightAccentText, const Color(0xFF0066CC));
      expect(TpPrimitives.lightStatusSuccess, const Color(0xFF248A3D));
      expect(TpPrimitives.lightStatusCaution, const Color(0xFFB07800));
      expect(TpPrimitives.lightStatusCritical, const Color(0xFFD70015));
      expect(TpPrimitives.lightStatusNeutral, const Color(0xFF868A93));
    });

    test('focus inner ring', () {
      expect(TpPrimitives.lightFocusInner, const Color(0xFFF5F5F7));
    });
  });

  test('smoke is a 60 % black scrim in both themes', () {
    expect(TpPrimitives.smoke, const Color(0x99000000));
  });
}
