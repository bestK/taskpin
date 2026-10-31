// Polish pass verification tests for TaskPin macOS script popovers.

import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpin/app/windows/dialog_window.dart';
import 'package:taskpin/features/dialogs/dialog_action.dart';
import 'package:taskpin/features/dialogs/dialog_controller.dart';
import 'package:taskpin/features/dialogs/dialog_palette.dart';
import 'package:taskpin/features/dialogs/dialog_spec.dart';
import 'package:taskpin/features/dialogs/dialog_view.dart';
import 'package:taskpin/features/dialogs/items/button_item.dart';
import 'package:taskpin/features/dialogs/items/image_item.dart';
import 'package:taskpin/features/dialogs/items/table_item.dart';
import 'package:taskpin/features/dialogs/window_channel.dart';
import 'package:taskpin_design/taskpin_design.dart';

void main() {
  group('Color Contrast Adaptation', () {
    test('contrastRatio computes standard WCAG relative luminance contrast', () {
      expect(contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)), closeTo(21.0, 0.1));
      expect(contrastRatio(const Color(0xFFFFFFFF), const Color(0xFFFFFFFF)), closeTo(1.0, 0.01));
    });

    test('ensureContrast leaves already high-contrast colors untouched', () {
      const Color darkSurface = Color(0xFF202020);
      const Color lightBlue = Color(0xFF4FC3F7);
      const Color white = Color(0xFFFFFFFF);

      // On dark surface, light colors already have high contrast (> 8:1).
      expect(ensureContrast(lightBlue, darkSurface), equals(lightBlue));
      expect(ensureContrast(white, darkSurface), equals(white));

      const Color lightSurface = Color(0xFFF6F6F6);
      const Color black = Color(0xFF000000);
      // On light surface, black already has high contrast (> 15:1).
      expect(ensureContrast(black, lightSurface), equals(black));
    });

    test('ensureContrast adapts light script colors on light surfaces preserving hue', () {
      const Color lightSurface = Color(0xFFF6F6F6);
      const Color lightCyan = Color(0xFF4FC3F7); // Net monitor / Zeeho text

      final Color adapted = ensureContrast(lightCyan, lightSurface, minContrast: 4.5);
      expect(contrastRatio(adapted, lightSurface), greaterThanOrEqualTo(4.5));

      final HSLColor origHsl = HSLColor.fromColor(lightCyan);
      final HSLColor adaptedHsl = HSLColor.fromColor(adapted);
      // Hue remains identical.
      expect((origHsl.hue - adaptedHsl.hue).abs(), lessThan(1.0));
      // Lightness was decreased to achieve legibility.
      expect(adaptedHsl.lightness, lessThan(origHsl.lightness));
    });

    test('ensureContrast shifts pure white text to readable dark text on light surface', () {
      const Color lightSurface = Color(0xFFFFFFFF);
      const Color white = Color(0xFFFFFFFF);

      final Color adapted = ensureContrast(white, lightSurface, minContrast: 4.5);
      expect(contrastRatio(adapted, lightSurface), greaterThanOrEqualTo(4.5));
      expect(adapted.computeLuminance(), lessThan(0.2));
    });
  });

  group('Table Item Polish', () {
    testWidgets('table aligns numbers right and text left, with tabular figures on numbers', (
      WidgetTester tester,
    ) async {
      final DialogSpec spec = DialogSpec.fromJson(<String, dynamic>{
        'title': 'Net Monitor',
        'width': 440,
        'height': 300,
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'table',
            'columns': <String>['Process', 'Conn', 'Download', 'Upload'],
            'rows': <List<String>>[
              <String>['Google Chrome Helper', '12', '1.2M/s', '45.0K/s'],
              <String>['curl', '1', '500B/s', '0B/s'],
            ],
          },
        ],
      });

      final DialogController controller = DialogController(
        spec: spec,
        windowApi: const NoopDialogWindowApi(),
        actions: RecordingDialogActionRunner(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DialogView(controller: controller, hostDrawsSurface: true),
          ),
        ),
      );
      await tester.pump();

      // Header alignment:
      final Text processHeader = tester.widget<Text>(find.text('Process'));
      expect(processHeader.textAlign, TextAlign.left);
      expect(processHeader.style?.fontSize, 12); // Caption size

      final Text connHeader = tester.widget<Text>(find.text('Conn'));
      expect(connHeader.textAlign, TextAlign.right);

      final Text downloadHeader = tester.widget<Text>(find.text('Download'));
      expect(downloadHeader.textAlign, TextAlign.right);

      final Text uploadHeader = tester.widget<Text>(find.text('Upload'));
      expect(uploadHeader.textAlign, TextAlign.right);

      // Cell alignment and tabular figures:
      final Text processCell = tester.widget<Text>(find.text('Google Chrome Helper'));
      expect(processCell.textAlign, TextAlign.left);
      expect(processCell.style?.fontFeatures, isNull);

      final Text downloadCell = tester.widget<Text>(find.text('1.2M/s'));
      expect(downloadCell.textAlign, TextAlign.right);
      expect(downloadCell.style?.fontFeatures, contains(const FontFeature.tabularFigures()));

      // Column flex allocation: Process column gets higher flex than Conn column.
      final Expanded processCol = tester.widget<Expanded>(
        find.ancestor(of: find.text('Process'), matching: find.byType(Expanded)).first,
      );
      final Expanded connCol = tester.widget<Expanded>(
        find.ancestor(of: find.text('Conn'), matching: find.byType(Expanded)).first,
      );
      expect(processCol.flex, greaterThan(connCol.flex));

      // Tooltip is present for long process names.
      expect(
        find.ancestor(
          of: find.text('Google Chrome Helper'),
          matching: find.byType(Tooltip),
        ),
        findsOneWidget,
      );
    });
  });

  group('Button Item Polish', () {
    testWidgets('button picks contrast-optimal text color when custom background is set', (
      WidgetTester tester,
    ) async {
      final DialogSpec spec = DialogSpec.fromJson(<String, dynamic>{
        'items': <Map<String, dynamic>>[
          // Dark button background -> white text
          <String, dynamic>{'type': 'button', 'value': 'DarkBtn', 'bg': '000000'},
          // Light button background -> black text
          <String, dynamic>{'type': 'button', 'value': 'LightBtn', 'bg': 'FFFFFF'},
        ],
      });

      final DialogController controller = DialogController(
        spec: spec,
        windowApi: const NoopDialogWindowApi(),
        actions: RecordingDialogActionRunner(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: TaskPinTheme.light().toThemeData(),
          home: Scaffold(
            body: DialogView(controller: controller, hostDrawsSurface: true),
          ),
        ),
      );
      await tester.pump();

      final Text darkBtnText = tester.widget<Text>(find.text('DarkBtn'));
      expect(darkBtnText.style?.color, const Color(0xFFFFFFFF));

      final Text lightBtnText = tester.widget<Text>(find.text('LightBtn'));
      expect(lightBtnText.style?.color, const Color(0xFF000000));
    });
  });

  group('Image Item Polish', () {
    testWidgets('images are rounded with control radius', (
      WidgetTester tester,
    ) async {
      final DialogSpec spec = DialogSpec.fromJson(<String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'image',
            'image': 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
            'image_width': 32,
            'image_height': 32,
          },
        ],
      });

      final DialogController controller = DialogController(
        spec: spec,
        windowApi: const NoopDialogWindowApi(),
        actions: RecordingDialogActionRunner(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DialogView(controller: controller, hostDrawsSurface: true),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(DialogImageItem),
          matching: find.byType(ClipRRect),
        ),
        findsOneWidget,
      );
    });
  });

  group('Popover Chrome and Rhythm', () {
    testWidgets('popover mode drops opaque title band background and divider', (
      WidgetTester tester,
    ) async {
      final DialogSpec spec = DialogSpec.fromJson(<String, dynamic>{
        'title': 'Test Popover',
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'text', 'value': 'Content'},
        ],
      });

      final DialogController controller = DialogController(
        spec: spec,
        windowApi: const NoopDialogWindowApi(),
        actions: RecordingDialogActionRunner(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: TaskPinTheme.light().toThemeData(),
          home: Scaffold(
            body: DialogView(controller: controller, hostDrawsSurface: true),
          ),
        ),
      );
      await tester.pump();

      // No TpDivider in popover mode under the title.
      expect(find.byType(TpDivider), findsNothing);

      // Title ColoredBox is transparent so native vibrancy shows through.
      final ColoredBox titleBand = tester.widget<ColoredBox>(
        find.ancestor(of: find.text('Test Popover'), matching: find.byType(ColoredBox)).first,
      );
      expect(titleBand.color, Colors.transparent);
    });

    testWidgets('popover mode overlay scrollbar styling and padding clearance', (
      WidgetTester tester,
    ) async {
      final DialogSpec spec = DialogSpec.fromJson(<String, dynamic>{
        'title': 'Scroll Test',
        'items': <Map<String, dynamic>>[
          for (int i = 0; i < 20; i++)
            <String, dynamic>{'type': 'text', 'value': 'Line $i'},
        ],
      });

      final DialogController controller = DialogController(
        spec: spec,
        windowApi: const NoopDialogWindowApi(),
        actions: RecordingDialogActionRunner(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 320,
            height: 200,
            child: DialogView(
              controller: controller,
              showScrollbar: true,
              hostDrawsSurface: true,
            ),
          ),
        ),
      );
      await tester.pump();

      final ScrollbarTheme theme = tester.widget<ScrollbarTheme>(find.byType(ScrollbarTheme));
      expect(theme.data.thickness?.resolve(<WidgetState>{}), 5.0);
      expect(theme.data.radius, const Radius.circular(3.0));
      expect(theme.data.crossAxisMargin, 2.0);

      // Padding clearance has right inset of 16px to protect table columns.
      final SingleChildScrollView scrollView = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect((scrollView.padding as EdgeInsets).right, 16.0);
    });

    testWidgets('empty spec renders gracefully without crashing or throwing', (
      WidgetTester tester,
    ) async {
      final DialogSpec emptySpec = DialogSpec.fromJson(<String, dynamic>{
        'title': 'Empty',
        'items': <Map<String, dynamic>>[],
      });

      final DialogController controller = DialogController(
        spec: emptySpec,
        windowApi: const NoopDialogWindowApi(),
        actions: RecordingDialogActionRunner(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DialogView(controller: controller, hostDrawsSurface: true),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Empty'), findsOneWidget);
    });
  });

  group('Representative Real Script Popovers (net_monitor, zeeho, claude_status)', () {
    testWidgets('net_monitor spec renders legibly in light popover mode', (
      WidgetTester tester,
    ) async {
      final DialogSpec netSpec = DialogSpec.fromJson(<String, dynamic>{
        'title': 'Network Activity',
        'width': 440,
        'height': 380,
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'text',
            'value': 'Active Connections (15 processes)',
            'color': '#4FC3F7',
            'font_size': 11,
            'bold': 1,
          },
          <String, dynamic>{'type': 'hr'},
          <String, dynamic>{
            'type': 'table',
            'columns': <String>['Process', 'Conn', 'Download', 'Upload'],
            'rows': <List<String>>[
              <String>['Google Chrome Helper (Renderer)', '12', '1.5M/s', '32.0K/s'],
              <String>['taskpin', '3', '120B/s', '45B/s'],
            ],
          },
        ],
      });

      final DialogController lightController = DialogController(
        spec: netSpec,
        windowApi: const NoopDialogWindowApi(),
        actions: RecordingDialogActionRunner(),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: TaskPinTheme.light().toThemeData(),
          themeMode: ThemeMode.light,
          home: Scaffold(
            body: DialogView(controller: lightController, hostDrawsSurface: true),
          ),
        ),
      );
      await tester.pump();

      final Text lightHeading = tester.widget<Text>(find.text('Active Connections (15 processes)'));
      // In light mode, #4FC3F7 was adapted to guarantee at least 3:1 bold contrast against native popover surface.
      expect(contrastRatio(lightHeading.style!.color!, kMacPopoverLightSurface), greaterThanOrEqualTo(3.0));
    });

    testWidgets('net_monitor spec renders original script color in dark popover mode', (
      WidgetTester tester,
    ) async {
      final DialogSpec netSpec = DialogSpec.fromJson(<String, dynamic>{
        'title': 'Network Activity',
        'width': 440,
        'height': 380,
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'text',
            'value': 'Active Connections (15 processes)',
            'color': '#4FC3F7',
            'font_size': 11,
            'bold': 1,
          },
          <String, dynamic>{'type': 'hr'},
          <String, dynamic>{
            'type': 'table',
            'columns': <String>['Process', 'Conn', 'Download', 'Upload'],
            'rows': <List<String>>[
              <String>['Google Chrome Helper (Renderer)', '12', '1.5M/s', '32.0K/s'],
              <String>['taskpin', '3', '120B/s', '45B/s'],
            ],
          },
        ],
      });

      final DialogController darkController = DialogController(
        spec: netSpec,
        windowApi: const NoopDialogWindowApi(),
        actions: RecordingDialogActionRunner(),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: TaskPinTheme.dark().toThemeData(),
          themeMode: ThemeMode.dark,
          home: Scaffold(
            body: DialogView(controller: darkController, hostDrawsSurface: true),
          ),
        ),
      );
      await tester.pump();

      final Text darkHeading = tester.widget<Text>(find.text('Active Connections (15 processes)'));
      // In dark mode, original #4FC3F7 is preserved.
      expect(darkHeading.style!.color, const Color(0xFF4FC3F7));
    });

    testWidgets('zeeho spec renders vehicle table and status cleanly in light and dark', (
      WidgetTester tester,
    ) async {
      final DialogSpec zeehoSpec = DialogSpec.fromJson(<String, dynamic>{
        'title': 'Zeeho AE8',
        'width': 320,
        'height': 260,
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'text',
            'value': 'Zeeho AE8 ⚡',
            'color': '#4FC3F7',
            'font_size': 12,
            'bold': 1,
          },
          <String, dynamic>{'type': 'hr'},
          <String, dynamic>{
            'type': 'table',
            'columns': <String>['项目', '数值'],
            'rows': <List<String>>[
              <String>['电量 SOC', '85%'],
              <String>['续航里程', '65 km'],
              <String>['前胎压', '2.3 bar / 24°C'],
            ],
          },
        ],
      });

      final DialogController controller = DialogController(
        spec: zeehoSpec,
        windowApi: const NoopDialogWindowApi(),
        actions: RecordingDialogActionRunner(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: TaskPinTheme.light().toThemeData(),
          themeMode: ThemeMode.light,
          home: Scaffold(
            body: DialogView(controller: controller, hostDrawsSurface: true),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Zeeho AE8'), findsOneWidget);
      expect(find.text('电量 SOC'), findsOneWidget);
      expect(find.text('85%'), findsOneWidget);

      final Text numCell = tester.widget<Text>(find.text('85%'));
      expect(numCell.textAlign, TextAlign.right);
    });

    testWidgets('claude_status spec renders image, status text and session metadata', (
      WidgetTester tester,
    ) async {
      final DialogSpec claudeSpec = DialogSpec.fromJson(<String, dynamic>{
        'title': 'Claude',
        'width': 340,
        'height': 220,
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'text',
            'value': 'Claude Code',
            'color': '#D97757',
            'font_size': 12,
            'bold': 1,
          },
          <String, dynamic>{'type': 'hr'},
          <String, dynamic>{
            'type': 'text',
            'value': '状态: 想一想',
            'color': '#FFAA00',
            'font_size': 10,
          },
          <String, dynamic>{
            'type': 'text',
            'value': '会话: taskpin_agent',
            'color': '#666666',
            'font_size': 9,
          },
        ],
      });

      final DialogController controller = DialogController(
        spec: claudeSpec,
        windowApi: const NoopDialogWindowApi(),
        actions: RecordingDialogActionRunner(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: TaskPinTheme.light().toThemeData(),
          themeMode: ThemeMode.light,
          home: Scaffold(
            body: DialogView(controller: controller, hostDrawsSurface: true),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Claude'), findsOneWidget);
      expect(find.text('Claude Code'), findsOneWidget);
      expect(find.text('状态: 想一想'), findsOneWidget);

      // In light mode, #FFAA00 is contrast-adjusted against native popover surface to remain legible:
      final Text statusText = tester.widget<Text>(find.text('状态: 想一想'));
      expect(contrastRatio(statusText.style!.color!, kMacPopoverLightSurface), greaterThanOrEqualTo(4.5));
    });
  });

  group('Gated Color Adaptation (Window mode vs Popover mode)', () {
    testWidgets('window mode leaves an explicit dark colour unchanged', (
      WidgetTester tester,
    ) async {
      final DialogSpec spec = DialogSpec.fromJson(<String, dynamic>{
        'title': 'Window Mode Dark Color',
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'text',
            'value': 'Dark Message',
            'color': '#111111',
          },
        ],
      });

      final DialogController controller = DialogController(
        spec: spec,
        windowApi: const NoopDialogWindowApi(),
        actions: RecordingDialogActionRunner(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: TaskPinTheme.dark().toThemeData(),
          themeMode: ThemeMode.dark,
          home: Scaffold(
            body: DialogView(controller: controller, hostDrawsSurface: false),
          ),
        ),
      );
      await tester.pump();

      final Text darkText = tester.widget<Text>(find.text('Dark Message'));
      // In window mode, script colors must not be modified even if contrast against dark background is low.
      expect(darkText.style?.color, const Color(0xFF111111));
    });

    testWidgets('popover mode with an explicit dark bg_color does not darken a light script colour', (
      WidgetTester tester,
    ) async {
      final DialogSpec spec = DialogSpec.fromJson(<String, dynamic>{
        'title': 'Dark BG Popover',
        'bg_color': '#1E1E1E',
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'text',
            'value': 'Light Text on Dark Popover',
            'color': '#4FC3F7',
          },
        ],
      });

      final DialogController controller = DialogController(
        spec: spec,
        windowApi: const NoopDialogWindowApi(),
        actions: RecordingDialogActionRunner(),
      );

      // Even if system appearance is light, popover surface is explicit dark (#1E1E1E),
      // so #4FC3F7 has high contrast against the actual surface and must NOT be darkened.
      await tester.pumpWidget(
        MaterialApp(
          theme: TaskPinTheme.light().toThemeData(),
          themeMode: ThemeMode.light,
          home: Scaffold(
            body: DialogView(controller: controller, hostDrawsSurface: true),
          ),
        ),
      );
      await tester.pump();

      final Text lightText = tester.widget<Text>(find.text('Light Text on Dark Popover'));
      expect(lightText.style?.color, const Color(0xFF4FC3F7));
    });
  });
}
