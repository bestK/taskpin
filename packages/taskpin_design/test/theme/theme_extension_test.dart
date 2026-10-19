// TaskPinTheme: construction, lookup, lerp and the ThemeData bridge.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin_design/taskpin_design.dart';

void main() {
  group('construction', () {
    test('dark and light are wired to their semantic layers', () {
      final TaskPinTheme dark = TaskPinTheme.dark();
      final TaskPinTheme light = TaskPinTheme.light();
      expect(dark.brightness, Brightness.dark);
      expect(light.brightness, Brightness.light);
      expect(dark.bg.window, TpSemantic.dark.bg.window);
      expect(light.bg.window, TpSemantic.light.bg.window);
      expect(dark.accent.fill, TpSemantic.dark.accent.fill);
      expect(light.accent.fill, TpSemantic.light.accent.fill);
    });

    test('focus outer is text.primary in both themes', () {
      expect(TaskPinTheme.dark().focusOuter, TaskPinTheme.dark().text.primary);
      expect(
          TaskPinTheme.light().focusOuter, TaskPinTheme.light().text.primary);
    });

    test('focus inner differs per theme', () {
      expect(TaskPinTheme.dark().focusInner, const Color(0xB3000000));
      expect(TaskPinTheme.light().focusInner, const Color(0xB3FFFFFF));
    });

    test('bar palette and platform are carried through', () {
      final TaskPinTheme t = TaskPinTheme.dark(barPlatform: TpBarPlatform.macOS);
      expect(t.barPlatform, TpBarPlatform.macOS);
      expect(t.barColors, const TpBarColors());
    });
  });

  group('copyWith', () {
    test('replaces only the given groups', () {
      final TaskPinTheme base = TaskPinTheme.dark();
      final TaskPinTheme copy = base.copyWith(smoke: const Color(0x01000000));
      expect(copy.smoke, const Color(0x01000000));
      expect(copy.bg.window, base.bg.window);
      expect(copy.brightness, base.brightness);
    });
  });

  group('lerp', () {
    test('t = 0 and t = 1 return the endpoints', () {
      final TaskPinTheme dark = TaskPinTheme.dark();
      final TaskPinTheme light = TaskPinTheme.light();
      expect(dark.lerp(light, 0).bg.window, dark.bg.window);
      expect(dark.lerp(light, 1).bg.window, light.bg.window);
    });

    test('colours interpolate at the midpoint', () {
      final TaskPinTheme dark = TaskPinTheme.dark();
      final TaskPinTheme light = TaskPinTheme.light();
      final Color mid = dark.lerp(light, 0.5).bg.window;
      expect(mid, isNot(dark.bg.window));
      expect(mid, isNot(light.bg.window));
    });

    test('brightness snaps at the midpoint', () {
      final TaskPinTheme dark = TaskPinTheme.dark();
      final TaskPinTheme light = TaskPinTheme.light();
      expect(dark.lerp(light, 0.4).brightness, Brightness.dark);
      expect(dark.lerp(light, 0.6).brightness, Brightness.light);
    });

    test('null other returns this', () {
      final TaskPinTheme dark = TaskPinTheme.dark();
      expect(identical(dark.lerp(null, 0.5), dark), isTrue);
    });
  });

  group('lookup', () {
    testWidgets('of() reads the extension from the tree', (WidgetTester tester) async {
      late TaskPinTheme found;
      await tester.pumpWidget(MaterialApp(
        theme: TaskPinTheme.light().toThemeData(),
        home: Builder(builder: (BuildContext context) {
          found = TaskPinTheme.of(context);
          return const SizedBox();
        }),
      ));
      expect(found.isDark, isFalse);
    });

    testWidgets('of() falls back to dark when the extension is absent',
        (WidgetTester tester) async {
      late TaskPinTheme found;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (BuildContext context) {
          found = TaskPinTheme.of(context);
          return const SizedBox();
        }),
      ));
      expect(found.isDark, isTrue);
    });
  });

  group('ThemeData bridge', () {
    test('uses the UI family and fallback chain', () {
      final ThemeData data = TaskPinTheme.dark().toThemeData();
      expect(data.textTheme.bodyMedium?.fontFamily, 'Segoe UI Variable Text');
      expect(data.textTheme.bodyMedium?.fontFamilyFallback, TpFontFamily.uiFallback);
    });

    test('scaffold ground is bg.window', () {
      final TaskPinTheme t = TaskPinTheme.light();
      expect(t.toThemeData().scaffoldBackgroundColor, t.bg.window);
    });

    test('carries the extension', () {
      final TaskPinTheme t = TaskPinTheme.dark();
      expect(t.toThemeData().extension<TaskPinTheme>(), isNotNull);
    });
  });

  group('helpers', () {
    test('stateColor maps every kind', () {
      final TaskPinTheme t = TaskPinTheme.dark();
      expect(t.stateColor(TpStateKind.success), t.status.success);
      expect(t.stateColor(TpStateKind.caution), t.status.caution);
      expect(t.stateColor(TpStateKind.critical), t.status.critical);
      expect(t.stateColor(TpStateKind.neutral), t.status.neutral);
      expect(t.stateColor(TpStateKind.info), t.accent.text);
    });

    test('stateSubtle is 12 % alpha', () {
      final TaskPinTheme t = TaskPinTheme.light();
      for (final TpStateKind k in TpStateKind.values) {
        expect(t.stateSubtle(k).a, closeTo(0.12, 0.005), reason: k.name);
      }
    });

    test('textColor maps every role', () {
      final TaskPinTheme t = TaskPinTheme.dark();
      expect(t.textColor(TpTextRole.primary), t.text.primary);
      expect(t.textColor(TpTextRole.secondary), t.text.secondary);
      expect(t.textColor(TpTextRole.tertiary), t.text.tertiary);
      expect(t.textColor(TpTextRole.disabled), t.text.disabled);
      expect(t.textColor(TpTextRole.onAccent), t.accent.onFill);
    });

    test('taskbarPreview follows the brightness', () {
      expect(TaskPinTheme.dark().taskbarPreview, const Color(0xFF1C1C1C));
      expect(TaskPinTheme.light().taskbarPreview, const Color(0xFFEEEEEE));
    });

    test('metricStyle is mono with tabular figures', () {
      final TextStyle s = TaskPinTheme.dark().metricStyle;
      expect(s.fontFamily, 'Cascadia Mono');
      expect(s.fontFeatures, isNotNull);
    });
  });
}
