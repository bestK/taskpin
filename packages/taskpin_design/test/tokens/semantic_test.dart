// Semantic roles: completeness, wiring and contrast in both themes.

import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin_design/taskpin_design.dart';

/// Alpha-composites [fg] over [bg], giving the colour the eye sees.
Color _over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

/// WCAG contrast ratio between two colours.
double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final MapEntry<String, TpSemanticColors> theme
      in <String, TpSemanticColors>{
    'dark': TpSemantic.dark,
    'light': TpSemantic.light,
  }.entries) {
    group('${theme.key} semantic layer', () {
      final TpSemanticColors c = theme.value;

      test('every documented role is wired', () {
        expect(c.bg.window, isNotNull);
        expect(c.bg.card, isNotNull);
        expect(c.bg.cardSecondary, isNotNull);
        expect(c.bg.flyout, isNotNull);
        expect(c.stroke.card, isNotNull);
        expect(c.stroke.divider, isNotNull);
        expect(c.control.fill, isNotNull);
        expect(c.control.fillHover, isNotNull);
        expect(c.control.fillPressed, isNotNull);
        expect(c.control.fillInputActive, isNotNull);
        expect(c.control.stroke, isNotNull);
        expect(c.control.strokeBottom, isNotNull);
        expect(c.control.strokeStrong, isNotNull);
        expect(c.subtle.hover, isNotNull);
        expect(c.subtle.pressed, isNotNull);
        expect(c.text.primary, isNotNull);
        expect(c.text.secondary, isNotNull);
        expect(c.text.tertiary, isNotNull);
        expect(c.text.disabled, isNotNull);
        expect(c.accent.fill, isNotNull);
        expect(c.accent.fillHover, isNotNull);
        expect(c.accent.onFill, isNotNull);
        expect(c.accent.text, isNotNull);
        expect(c.status.success, isNotNull);
        expect(c.status.caution, isNotNull);
        expect(c.status.critical, isNotNull);
        expect(c.status.neutral, isNotNull);
        expect(c.smoke, isNotNull);
        expect(c.focusInner, isNotNull);
      });

      test('focus outer is text.primary', () {
        expect(c.focusOuter, c.text.primary);
      });

      test('info status is accent text', () {
        expect(c.status.info, c.accent.text);
        expect(c.status.colorOf(TpStateKind.info), c.accent.text);
      });

      test('subtleOf is the base colour at 12 % alpha', () {
        for (final TpStateKind k in TpStateKind.values) {
          final Color base = c.status.colorOf(k);
          final Color subtle = c.status.subtleOf(k);
          expect(subtle.a, closeTo(0.12, 0.005), reason: k.name);
          expect(subtle.r, closeTo(base.r, 0.005), reason: k.name);
          expect(subtle.g, closeTo(base.g, 0.005), reason: k.name);
          expect(subtle.b, closeTo(base.b, 0.005), reason: k.name);
        }
      });

      test('subtleOf takes an explicit alpha', () {
        final Color base = c.status.colorOf(TpStateKind.critical);
        final Color subtle = c.status.subtleOf(TpStateKind.critical, alpha: 0.08);
        expect(subtle.a, closeTo(0.08, 0.005));
        expect(subtle.r, closeTo(base.r, 0.005));
      });

      test('text emphasis descends', () {
        final Color bg = _over(c.bg.window, c.bg.window);
        final double p = _contrast(_over(c.text.primary, bg), bg);
        final double s = _contrast(_over(c.text.secondary, bg), bg);
        final double t = _contrast(_over(c.text.tertiary, bg), bg);
        expect(p, greaterThan(s));
        expect(s, greaterThan(t));
      });

      test('primary text clears WCAG AA on the window', () {
        final Color bg = c.bg.window;
        expect(_contrast(_over(c.text.primary, bg), bg), greaterThanOrEqualTo(4.5));
      });

      test('secondary text clears 4.5:1 on the window', () {
        final Color bg = c.bg.window;
        expect(_contrast(_over(c.text.secondary, bg), bg),
            greaterThanOrEqualTo(4.5));
      });

      test('onFill text is legible on the accent fill', () {
        final Color fill = _over(c.accent.fill, c.bg.window);
        // The spec fixes white text on both accent fills. Dark #4C8DFF is
        // 3.2:1, below AA for small text but required by the palette, so the
        // bar is the 3:1 control threshold here.
        expect(_contrast(c.accent.onFill, fill), greaterThanOrEqualTo(3.0));
      });

      test('focus inner ring differs from the window', () {
        final Color bg = c.bg.window;
        expect(_over(c.focusInner, bg), isNot(bg));
      });
    });
  }

  test('dark and light are distinct on the window and the accent', () {
    expect(TpSemantic.dark.bg.window, isNot(TpSemantic.light.bg.window));
    expect(TpSemantic.dark.accent.fill, isNot(TpSemantic.light.accent.fill));
  });

  test('both themes use white text on the accent fill', () {
    expect(TpSemantic.dark.accent.onFill, const Color(0xFFFFFFFF));
    expect(TpSemantic.dark.accent.fill, const Color(0xFF4C8DFF));
    expect(TpSemantic.light.accent.onFill, const Color(0xFFFFFFFF));
    expect(TpSemantic.light.accent.fill, const Color(0xFF2C5FA8));
  });

  test('of() resolves by brightness', () {
    expect(TpSemantic.of(true).bg.window, TpSemantic.dark.bg.window);
    expect(TpSemantic.of(false).bg.window, TpSemantic.light.bg.window);
  });

  test('TpStateKind has exactly the five spec kinds', () {
    expect(
      TpStateKind.values.map((TpStateKind k) => k.name).toList(),
      <String>['success', 'caution', 'critical', 'neutral', 'info'],
    );
  });
}
