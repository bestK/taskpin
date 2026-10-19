// Structure of the manager window: shell, project list, project detail,
// settings and the two stub pages. Runs against an in-memory config; the engine
// and the bar controller are replaced with fakes.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:taskpin/app/shell/routes.dart';
import 'package:taskpin/core/bar/bar_controller.dart';
import 'package:taskpin/core/config/config_providers.dart';
import 'package:taskpin/core/config/config_repository.dart';
import 'package:taskpin/core/config/config_schema.dart';
import 'package:taskpin/core/engine/engine_provider.dart';
import 'package:taskpin/features/signals/signals_editor_page.dart' show ClickMode;
import 'package:taskpin/features/signals/signals_list_page.dart'
    show kAttentionRowHeight, kRunningCardHeight, kStoppedCardHeight;
import 'package:taskpin/features/signals/widgets/avatar.dart';
import 'package:taskpin/l10n/app_localizations.dart';
import 'package:taskpin_design/taskpin_design.dart';

/// A repository that never touches the disk.
class _MemoryRepository extends ConfigRepository {
  _MemoryRepository()
      : super(
          paths: const ConfigPaths(
            baseDir: 'C:\\taskpin-test',
            configFile: 'C:\\taskpin-test\\config.json',
            scriptsDir: 'C:\\taskpin-test\\scripts',
            portable: false,
          ),
        );

  @override
  void save(TaskPinConfig cfg) {}

  @override
  Future<void> flush() async {}
}

/// A bar controller that does nothing.
class _IdleBars extends BarNotifier {
  @override
  BarState build() => const BarState();
}

PinItem _url(String name, {bool pinned = false, int intervalMs = 5000}) =>
    PinItem(
      type: PinItemType.url,
      name: name,
      url: 'https://api.example.com/v1/price',
      intervalMs: intervalMs,
      pinned: pinned,
    );

PinItem _lua(String name, {String path = r'C:\scripts\hud_clock.lua'}) =>
    PinItem(type: PinItemType.lua, name: name, luaPath: path, intervalMs: 5000);

Future<GoRouter> _pump(
  WidgetTester tester,
  TaskPinConfig config, {
  Size size = const Size(1400, 1000),
  String location = AppRoutes.signals,
  Brightness brightness = Brightness.dark,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final GoRouter router = buildRouter();
  router.go(location);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        configRepositoryProvider.overrideWithValue(_MemoryRepository()),
        initialConfigProvider.overrideWithValue(config),
        barControllerProvider.overrideWith(_IdleBars.new),
        engineProvider.overrideWith((Ref ref) async {
          throw StateError('engine disabled in tests');
        }),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('zh'),
        builder: textScale == 1
            ? null
            : (BuildContext context, Widget? child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(textScale)),
                  child: child ?? const SizedBox.shrink(),
                ),
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: brightness == Brightness.dark
            ? TaskPinTheme.dark().toThemeData()
            : TaskPinTheme.light().toThemeData(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

TaskPinConfig _config(List<PinItem> items) =>
    TaskPinConfig(items: items, sources: <String>['bestK/taskpin-plugins']);

void main() {
  group('shell', () {
    testWidgets('rail has four destinations and none of the old chrome', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _config(<PinItem>[_url('Price')]));

      expect(find.text('项目'), findsWidgets);
      expect(find.text('插件市场'), findsOneWidget);
      expect(find.text('日志'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);

      for (final String gone in <String>[
        'TASKBAR DOCK',
        'Avionics Telemetry Deck',
        'BARS IN TRAY',
        'DOCK STANDBY',
        'LIGHT',
        'DARK',
        'Direct2D Native Engine',
      ]) {
        expect(find.textContaining(gone), findsNothing, reason: gone);
      }
      expect(find.byType(TpTaskbarFlightStrip), findsNothing);
    });

    testWidgets('rail is 240 wide, and 48 below 900', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _config(<PinItem>[_url('Price')]));
      expect(tester.getSize(find.byType(TpNavRail)).width, 240);

      await _pump(
        tester,
        _config(<PinItem>[_url('Price')]),
        size: const Size(800, 700),
      );
      expect(tester.getSize(find.byType(TpNavRail)).width, 48);
    });

    testWidgets('nav item navigates', (WidgetTester tester) async {
      final GoRouter router = await _pump(tester, _config(<PinItem>[]));
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, AppRoutes.settings);
    });
  });

  group('project list', () {
    testWidgets('status groups, cards and the taskbar preview', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _config(<PinItem>[
          _url('Price', pinned: true),
          _lua('Clock', path: r'C:\nowhere\missing.lua'),
        ]),
      );

      expect(find.byType(TpListGroup), findsNothing);
      expect(find.byType(TpListRow), findsNothing);
      // One switch on the running card, one on the stopped card.
      expect(find.byType(TpSwitch), findsOneWidget);

      // Status line, group headers and the preview caption.
      expect(find.text('1 运行中'), findsOneWidget);
      expect(find.text('1 异常'), findsOneWidget);
      expect(find.text('0 已停止'), findsOneWidget);
      expect(find.text('运行中'), findsWidgets);
      expect(find.text('需要处理'), findsOneWidget);
      expect(find.text('任务栏预览 · 1 个插件'), findsOneWidget);
      expect(find.text('拖动调整顺序'), findsOneWidget);

      // Error banner and the attention row's problem text.
      expect(find.text('1 个项目找不到脚本文件，可能已被移动或删除。'), findsOneWidget);
      expect(find.text('找不到脚本文件'), findsOneWidget);

      for (final String gone in <String>['PINNED', 'PIN', 'Showing', 'All (']) {
        expect(find.textContaining(gone), findsNothing, reason: gone);
      }
      expect(find.byType(TpSourceChip), findsNothing);
      expect(find.byType(TpIntervalBadge), findsNothing);
      expect(find.byType(TpSplitPane), findsNothing);
    });

    testWidgets('stopped cards and attention rows have fixed heights', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _config(<PinItem>[
          _url('Stopped A'),
          _url('Stopped B'),
          _lua('Missing', path: r'C:\nowhere\missing.lua'),
        ]),
      );

      // Both stopped cards are the same height even though the meta line
      // differs (one has a relative time, one does not).
      final Finder cards = find.byType(TpAvatar);
      expect(cards, findsNWidgets(2));
      expect(
        tester.getSize(cards.first).height,
        tester.getSize(cards.last).height,
      );

      final Finder shells = find.ancestor(
        of: find.text('Stopped A'),
        matching: find.byType(AnimatedContainer),
      );
      // The outer card shell is the one constrained by the fixed height.
      final Finder card = shells.last;
      expect(tester.getSize(card).height, kStoppedCardHeight);

      final Finder attention = find.ancestor(
        of: find.text('Missing'),
        matching: find.byType(AnimatedContainer),
      );
      expect(tester.getSize(attention.first).height, kAttentionRowHeight);
    });

    for (final double scale in <double>[1, 1.5]) {
      testWidgets('project cards do not overflow at ${scale}x text', (
        WidgetTester tester,
      ) async {
        await _pump(
          tester,
          _config(<PinItem>[
            _url('Running', pinned: true),
            _url('Stopped'),
            _lua('Missing', path: r'C:\nowhere\missing.lua'),
          ]),
          textScale: scale,
        );
        expect(tester.takeException(), isNull);

        // The fixed heights hold at both scales.
        expect(
          tester
              .getSize(find
                  .ancestor(
                    of: find.text('Stopped'),
                    matching: find.byType(AnimatedContainer),
                  )
                  .last)
              .height,
          kStoppedCardHeight,
        );
        expect(
          tester
              .getSize(find
                  .ancestor(
                    of: find.text('Running'),
                    matching: find.byType(AnimatedContainer),
                  )
                  .last)
              .height,
          kRunningCardHeight,
        );
      });
    }

    testWidgets('interval is formatted in the largest whole unit', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _config(<PinItem>[
          _url('A', intervalMs: 500),
          _url('B', intervalMs: 120000),
          _url('C', intervalMs: 3600000),
        ]),
      );
      expect(find.textContaining('每 500 毫秒'), findsOneWidget);
      expect(find.textContaining('每 2 分钟'), findsOneWidget);
      expect(find.textContaining('每 1 小时'), findsOneWidget);
    });

    testWidgets('the search field is always in the header, 320 wide', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _config(<PinItem>[_url('P0')]));
      expect(find.byType(TpTextField), findsOneWidget);
      expect(
        tester.getSize(find.ancestor(
          of: find.byType(TpTextField),
          matching: find.byType(SizedBox),
        ).first).width,
        320,
      );
      expect(find.text('Ctrl K'), findsOneWidget);
    });

    testWidgets('search filters cards by name', (WidgetTester tester) async {
      await _pump(
        tester,
        _config(<PinItem>[_url('Price'), _url('Weather')]),
      );
      await tester.enterText(find.byType(TextField), 'wea');
      await tester.pump();
      expect(find.text('Weather'), findsOneWidget);
      expect(find.text('Price'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      expect(find.text('没有匹配的项目'), findsOneWidget);
    });

    testWidgets('the pin switch changes the item', (WidgetTester tester) async {
      final TaskPinConfig config = _config(<PinItem>[_url('Price')]);
      await _pump(tester, config);

      await tester.tap(find.byType(TpSwitch));
      await tester.pumpAndSettle();

      expect(config.items.single.pinned, isTrue);
      expect(tester.widget<TpSwitch>(find.byType(TpSwitch)).value, isTrue);
    });

    testWidgets('empty list shows the empty state with one add button', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _config(<PinItem>[]));

      expect(find.byType(TpEmptyState), findsOneWidget);
      expect(find.text('还没有项目'), findsOneWidget);
      expect(find.text('添加项目'), findsOneWidget);
      expect(find.text('添加'), findsNothing);
    });

    testWidgets('header has an add button when there are items', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _config(<PinItem>[_url('Price')]));
      expect(find.text('添加项目'), findsOneWidget);
    });

    testWidgets('more menu offers copy and delete', (
      WidgetTester tester,
    ) async {
      final TaskPinConfig config = _config(<PinItem>[_url('Price')]);
      await _pump(tester, config);

      await tester.tap(find.byIcon(TpIcons.more));
      await tester.pumpAndSettle();
      expect(find.text('复制'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);

      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();
      expect(config.items, hasLength(2));
    });

    testWidgets('delete asks for confirmation', (WidgetTester tester) async {
      final TaskPinConfig config = _config(<PinItem>[_url('Price')]);
      await _pump(tester, config);

      await tester.tap(find.byIcon(TpIcons.more));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.byType(TpConfirmDialog), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(config.items, hasLength(1));

      await tester.tap(find.byIcon(TpIcons.more));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(TpConfirmDialog),
        matching: find.text('删除'),
      ));
      await tester.pumpAndSettle();
      expect(config.items, isEmpty);
      expect(find.text('还没有项目'), findsOneWidget);
    });
  });

  group('project detail', () {
    testWidgets('row tap opens the detail page, full width, with breadcrumb', (
      WidgetTester tester,
    ) async {
      final GoRouter router =
          await _pump(tester, _config(<PinItem>[_url('Price')]));

      await tester.tap(find.text('Price'));
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/signals/0');
      expect(find.byType(TpBreadcrumb), findsOneWidget);
      expect(find.byType(TpListGroup), findsNothing);
      expect(find.byType(TpSplitPane), findsNothing);

      // 项目 > Price; the first segment goes back to the list.
      await tester.tap(find.descendant(
        of: find.byType(TpBreadcrumb),
        matching: find.text('项目'),
      ));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, AppRoutes.signals);
    });

    testWidgets('sections follow the spec order and there is no save button', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _config(<PinItem>[_url('Price')]),
        location: '/signals/0',
      );

      double y(String text) => tester.getTopLeft(find.text(text).first).dy;

      expect(find.text('运行'), findsOneWidget);
      expect(find.text('保存'), findsNothing);
      expect(find.text('预览'), findsOneWidget);

      final List<String> order = <String>[
        '预览',
        '常规',
        '数据源',
        '外观',
        '点击行为',
        '删除项目',
      ];
      for (int i = 1; i < order.length; i++) {
        expect(y(order[i]), greaterThan(y(order[i - 1])),
            reason: '${order[i]} should be below ${order[i - 1]}');
      }

      // General fields.
      expect(find.text('名称'), findsOneWidget);
      expect(find.text('类型'), findsOneWidget);
      expect(find.text('刷新间隔'), findsOneWidget);
      expect(find.text('固定到任务栏'), findsOneWidget);

      // URL data source.
      expect(find.text('地址'), findsOneWidget);
      expect(find.text('请求头'), findsOneWidget);
      expect(find.text('取值表达式'), findsOneWidget);
    });

    testWidgets('the preview strip sits on the taskbar colour, 48 high', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _config(<PinItem>[_url('Price')]),
        location: '/signals/0',
      );

      final TaskPinTheme theme = TaskPinTheme.of(
        tester.element(find.byType(TpBreadcrumb)),
      );
      final Finder bar = find.byWidgetPredicate(
        (Widget w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).color == theme.taskbarPreview,
      );
      expect(bar, findsOneWidget);
      expect(tester.getSize(bar).height, 48);
    });

    testWidgets('a failed run shows the error under the preview', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _config(<PinItem>[_url('Price')]),
        location: '/signals/0',
      );
      // The engine is disabled in tests, so the automatic run fails.
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.textContaining('engine disabled in tests'), findsOneWidget);
    });

    testWidgets('lua items show the script file card', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _config(<PinItem>[_lua('Clock')]),
        location: '/signals/0',
      );
      expect(find.text('脚本文件'), findsOneWidget);
      expect(find.text('请求头'), findsNothing);
    });

    testWidgets('click action maps onto click_enabled and click_url', (
      WidgetTester tester,
    ) async {
      final TaskPinConfig config = _config(<PinItem>[_url('Price')]);
      await _pump(tester, config, location: '/signals/0');

      Future<void> choose(String label) async {
        await tester.ensureVisible(find.byType(TpSelect<ClickMode>));
        await tester.tap(find.byType(TpSelect<ClickMode>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      expect(config.items.single.clickEnabled, isFalse);

      await choose('打开链接');
      expect(config.items.single.clickEnabled, isTrue);
      expect(find.text('链接地址'), findsOneWidget);

      config.items.single.clickUrl = 'https://example.com';
      await choose('弹出窗口');
      expect(config.items.single.clickEnabled, isTrue);
      expect(config.items.single.clickUrl, '');
      expect(find.text('链接地址'), findsNothing);

      await choose('无');
      expect(config.items.single.clickEnabled, isFalse);
    });

    testWidgets('delete project confirms, removes and returns to the list', (
      WidgetTester tester,
    ) async {
      final TaskPinConfig config = _config(<PinItem>[_url('Price')]);
      final GoRouter router =
          await _pump(tester, config, location: '/signals/0');

      final Finder deleteCard = find.ancestor(
        of: find.text('删除项目'),
        matching: find.byType(TpSettingsCard),
      );
      await tester.ensureVisible(deleteCard);
      await tester.tap(find.descendant(
        of: deleteCard,
        matching: find.byType(TpButton),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(TpConfirmDialog), findsOneWidget);

      await tester.tap(find.descendant(
        of: find.byType(TpConfirmDialog),
        matching: find.text('删除'),
      ));
      await tester.pumpAndSettle();

      expect(config.items, isEmpty);
      expect(router.routeInformationProvider.value.uri.path, AppRoutes.signals);
      expect(find.text('还没有项目'), findsOneWidget);
    });

    testWidgets('an unknown id returns to the list', (
      WidgetTester tester,
    ) async {
      final GoRouter router = await _pump(
        tester,
        _config(<PinItem>[_url('Price')]),
        location: '/signals/7',
      );
      expect(router.routeInformationProvider.value.uri.path, AppRoutes.signals);
    });
  });

  group('settings', () {
    testWidgets('sections, and none of the old chrome', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _config(<PinItem>[]),
        location: AppRoutes.settings,
      );

      for (final String title in <String>[
        '外观',
        '任务栏默认值',
        '更新',
        '插件来源',
        '关于',
      ]) {
        expect(find.text(title), findsWidgets, reason: title);
      }
      expect(find.text('应用主题'), findsOneWidget);
      expect(find.text('文字过长时滚动'), findsOneWidget);
      expect(find.textContaining('Quick'), findsNothing);
      expect(find.textContaining('Master layout'), findsNothing);
      expect(find.textContaining('GLOBAL'), findsNothing);
      expect(find.byType(TpSettingsCard), findsWidgets);
    });

    testWidgets('about expander holds the links', (WidgetTester tester) async {
      await _pump(
        tester,
        _config(<PinItem>[]),
        location: AppRoutes.settings,
      );
      final Finder about = find.ancestor(
        of: find.textContaining('TaskPin '),
        matching: find.byType(TpSettingsExpander),
      );
      await tester.ensureVisible(about.first);
      await tester.tap(find.textContaining('TaskPin ').last);
      await tester.pumpAndSettle();
      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('反馈'), findsOneWidget);
    });

    testWidgets('light theme builds the same page', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _config(<PinItem>[_url('Price')]),
        brightness: Brightness.light,
      );
      expect(find.text('Price'), findsOneWidget);
    });
  });

  group('logs page', () {
    testWidgets('logs', (WidgetTester tester) async {
      await _pump(
        tester,
        _config(<PinItem>[]),
        location: AppRoutes.diagnostics,
      );
      expect(find.text('暂无日志'), findsOneWidget);
    });
  });

  group('page frame', () {
    testWidgets('margin is 24 below 1000 px content width, 36 above', (
      WidgetTester tester,
    ) async {
      // 1000 + 240 rail = 1240 window: content area is exactly 1000.
      await _pump(
        tester,
        _config(<PinItem>[_url('Price')]),
        size: const Size(1239, 800),
      );
      final double narrow =
          tester.getTopLeft(find.text('任务栏预览 · 0 个插件')).dx -
              tester.getSize(find.byType(TpNavRail)).width;
      expect(narrow, 24);

      await _pump(
        tester,
        _config(<PinItem>[_url('Price')]),
        size: const Size(1500, 800),
      );
      final double wide =
          tester.getTopLeft(find.text('任务栏预览 · 0 个插件')).dx -
              tester.getSize(find.byType(TpNavRail)).width;
      expect(wide, 36);
    });

    testWidgets('content is at most 1000 wide', (WidgetTester tester) async {
      await _pump(
        tester,
        _config(<PinItem>[_url('Price')]),
        size: const Size(2200, 900),
      );
      expect(
        tester.getSize(find.ancestor(
          of: find.text('任务栏预览 · 0 个插件'),
          matching: find.byType(Column),
        ).first).width,
        1000,
      );
    });
  });

  group('narrow window', () {
    for (final String location in <String>[
      AppRoutes.signals,
      '/signals/0',
      '/signals/1',
      AppRoutes.settings,
    ]) {
      testWidgets('$location lays out at 560 px without overflow', (
        WidgetTester tester,
      ) async {
        await _pump(
          tester,
          _config(<PinItem>[
            _url('Price', pinned: true),
            _lua('Clock'),
          ]),
          size: const Size(560, 800),
          location: location,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
