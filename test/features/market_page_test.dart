// The plugin market page, against a fake source. No test here uses the network:
// `httpFetcherProvider` and `marketInChinaProvider` are overridden.

import 'dart:io';

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
import 'package:taskpin/core/net/http_providers.dart';
import 'package:taskpin/features/market/market_page.dart' show kMarketCardHeight;
import 'package:taskpin/features/market/market_providers.dart';
import 'package:taskpin/features/signals/widgets/avatar.dart';
import 'package:taskpin/l10n/app_localizations.dart';
import 'package:taskpin_design/taskpin_design.dart';

import '../support/fakes.dart';

const String _repo = 'bestK/taskpin-plugins';

const String _manifest = '''
{
  "scripts": [
    {"name": "Docker", "file": "docker_status.lua", "description": "Container status"},
    {"name": "Crypto", "file": "crypto_price.lua", "description": "Coin prices"}
  ]
}
''';

const String _script = '''
-- @refresh 5000
return "ok"
''';

/// A repository that never writes config.json.
class _MemoryRepository extends ConfigRepository {
  _MemoryRepository(String scriptsDir)
      : super(
          paths: ConfigPaths(
            baseDir: scriptsDir,
            configFile: '$scriptsDir${Platform.pathSeparator}config.json',
            scriptsDir: scriptsDir,
            portable: false,
          ),
        );

  @override
  void save(TaskPinConfig cfg) {}

  @override
  Future<void> flush() async {}
}

class _IdleBars extends BarNotifier {
  @override
  BarState build() => const BarState();
}

FakeFetcher _fakeSource() {
  final FakeFetcher f = FakeFetcher();
  f.onText('$_repo/master/manifest.json', _manifest);
  f.onBytes('$_repo/master/docker_status.lua', _script.codeUnits);
  f.onBytes('$_repo/master/crypto_price.lua', _script.codeUnits);
  return f;
}

late Directory _tmp;

Future<GoRouter> _pump(
  WidgetTester tester, {
  required FakeFetcher fetcher,
  TaskPinConfig? config,
  bool inChina = false,
}) async {
  _tmp = Directory.systemTemp.createTempSync('taskpin_market_test');
  addTearDown(() {
    try {
      _tmp.deleteSync(recursive: true);
    } on Object {
      // Best effort.
    }
  });

  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final GoRouter router = buildRouter();
  router.go(AppRoutes.market);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        configRepositoryProvider.overrideWithValue(
          _MemoryRepository('${_tmp.path}${Platform.pathSeparator}scripts'),
        ),
        initialConfigProvider.overrideWithValue(
          config ?? TaskPinConfig(sources: <String>[_repo]),
        ),
        barControllerProvider.overrideWith(_IdleBars.new),
        engineProvider.overrideWith((Ref ref) async {
          throw StateError('engine disabled in tests');
        }),
        httpFetcherProvider.overrideWithValue(fetcher),
        marketInChinaProvider.overrideWith((Ref ref) async => inChina),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('zh'),
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: TaskPinTheme.dark().toThemeData(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Finder _button(String label) => find.widgetWithText(TpButton, label);

void main() {
  testWidgets('lists the scripts of the source', (WidgetTester tester) async {
    await _pump(tester, fetcher: _fakeSource());

    expect(find.text('插件市场'), findsWidgets);
    expect(find.byType(TpListGroup), findsNothing);
    expect(find.text('Docker'), findsOneWidget);
    expect(find.text('Container status'), findsOneWidget);
    expect(find.text('Crypto'), findsOneWidget);
    expect(_button('安装'), findsNWidgets(2));
    expect(find.text('已安装'), findsNothing);
    expect(_button('管理来源'), findsOneWidget);
    // Subtitle counts and the source name appear once per card footer.
    expect(find.text('2 个插件 · 已安装 0 个 · 来源：$_repo'), findsOneWidget);
    expect(find.text(_repo), findsNWidgets(2));
    // One letter avatar per card.
    expect(find.byType(TpAvatar), findsNWidgets(2));
    // Not behind the proxy: no proxy line.
    expect(find.text('已通过 gh-proxy 加速'), findsNothing);
  });

  testWidgets('shows the proxy line when gh-proxy is in use', (
    WidgetTester tester,
  ) async {
    final FakeFetcher fetcher = _fakeSource();
    await _pump(tester, fetcher: fetcher, inChina: true);
    expect(find.text('已通过 gh-proxy 加速'), findsOneWidget);
    expect(fetcher.requestedUrls.first, contains('gh-proxy'));
  });

  testWidgets('one grid across all sources, each card names its source', (
    WidgetTester tester,
  ) async {
    final FakeFetcher fetcher = _fakeSource();
    fetcher.onText(
      'other/plugins/master/manifest.json',
      '{"scripts":[{"name":"Weather","file":"weather.lua","description":"Forecast"}]}',
    );
    await _pump(
      tester,
      fetcher: fetcher,
      config: TaskPinConfig(sources: <String>[_repo, 'other/plugins']),
    );
    expect(find.text(_repo), findsNWidgets(2));
    expect(find.text('other/plugins'), findsOneWidget);
    expect(find.text('Weather'), findsOneWidget);
    expect(find.textContaining('来源：$_repo、other/plugins'), findsOneWidget);
  });

  testWidgets('grid is three columns wide and one column narrow', (
    WidgetTester tester,
  ) async {
    await _pump(tester, fetcher: _fakeSource());
    final double dockerLeft = tester.getTopLeft(find.text('Docker')).dx;
    final double cryptoLeft = tester.getTopLeft(find.text('Crypto')).dx;
    expect(cryptoLeft, greaterThan(dockerLeft));

    // 560 window minus the 48 icon rail leaves one column.
    tester.view.physicalSize = const Size(560, 900);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Crypto')).dx,
      tester.getTopLeft(find.text('Docker')).dx,
    );
    expect(
      tester.getTopLeft(find.text('Crypto')).dy,
      greaterThan(tester.getTopLeft(find.text('Docker')).dy),
    );
  });

  testWidgets('cards with and without a description have the same height', (
    WidgetTester tester,
  ) async {
    final FakeFetcher fetcher = _fakeSource();
    fetcher.onText(
      '$_repo/master/manifest.json',
      '{"scripts":['
          '{"name":"Docker","file":"docker_status.lua","description":"Container status"},'
          '{"name":"Crypto","file":"crypto_price.lua"}'
          ']}',
    );
    await _pump(tester, fetcher: fetcher);

    final Size withDescription =
        tester.getSize(find.byType(TpSurface).first);
    final Size withoutDescription =
        tester.getSize(find.byType(TpSurface).last);
    expect(withDescription.height, withoutDescription.height);
    expect(withDescription.height, kMarketCardHeight);
    // The missing description falls back to the localized placeholder.
    expect(find.text('暂无描述'), findsOneWidget);
  });

  testWidgets('an item pointing at a missing file is not installed', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      fetcher: _fakeSource(),
      config: TaskPinConfig(
        sources: <String>[_repo],
        items: <PinItem>[
          PinItem(
            type: PinItemType.lua,
            name: 'Trending',
            luaPath: '${_tmp.path}\\moved-away\\docker_status.lua',
          ),
        ],
      ),
    );

    // The project list reports this item as 找不到脚本文件; the market must not
    // call the plugin 已安装 on the strength of the name alone.
    expect(find.text('已安装'), findsNothing);
    expect(_button('安装'), findsNWidgets(2));
    expect(find.text('2 个插件 · 已安装 0 个 · 来源：$_repo'), findsOneWidget);
  });

  testWidgets('filter segments switch between installed and not installed', (
    WidgetTester tester,
  ) async {
    await _pump(tester, fetcher: _fakeSource());
    expect(find.text('全部 2'), findsOneWidget);
    expect(find.text('已安装 0'), findsOneWidget);
    expect(find.text('未安装 2'), findsOneWidget);

    await tester.tap(find.text('已安装 0'));
    await tester.pump();
    expect(find.text('没有匹配的插件'), findsNothing);
    expect(find.text('来源中没有插件'), findsOneWidget);

    await tester.tap(find.text('未安装 2'));
    await tester.pump();
    expect(find.text('Docker'), findsOneWidget);
    expect(find.text('Crypto'), findsOneWidget);
  });

  testWidgets('search filters by name and description', (
    WidgetTester tester,
  ) async {
    await _pump(tester, fetcher: _fakeSource());

    await tester.enterText(find.byType(TextField), 'docker');
    await tester.pump();
    expect(find.text('Docker'), findsOneWidget);
    expect(find.text('Crypto'), findsNothing);

    // Description match.
    await tester.enterText(find.byType(TextField), 'coin');
    await tester.pump();
    expect(find.text('Docker'), findsNothing);
    expect(find.text('Crypto'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('Docker'), findsNothing);
    expect(find.text('没有匹配的插件'), findsOneWidget);
  });

  testWidgets('install flips the row to installed and adds the item', (
    WidgetTester tester,
  ) async {
    final FakeFetcher fetcher = _fakeSource();
    final GoRouter router = await _pump(tester, fetcher: fetcher);

    await tester.tap(_button('安装').first);
    await tester.pump();

    // Real file IO runs outside the fake clock.
    for (int i = 0; i < 20 && find.text('已安装').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    expect(find.text('已安装'), findsOneWidget);
    expect(_button('安装'), findsOneWidget);
    expect(_button('打开'), findsOneWidget);
    expect(fetcher.countMatching('docker_status.lua'), 1);
    expect(
      File('${_tmp.path}${Platform.pathSeparator}scripts'
              '${Platform.pathSeparator}docker_status.lua')
          .existsSync(),
      isTrue,
    );

    // The item is in the config; Open goes to its detail page.
    await tester.tap(_button('打开'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/signals/0');
  });

  testWidgets('a failed fetch shows an InfoBar and Retry reloads', (
    WidgetTester tester,
  ) async {
    final FakeFetcher fetcher = _fakeSource()..offline = true;
    await _pump(tester, fetcher: fetcher);

    expect(find.byType(TpInfoBar), findsOneWidget);
    expect(find.text('无法加载插件列表'), findsOneWidget);
    expect(find.textContaining('无法连接网络'), findsOneWidget);
    expect(find.text('Docker'), findsNothing);

    fetcher.offline = false;
    await tester.tap(_button('重试'));
    await tester.pumpAndSettle();
    expect(find.byType(TpInfoBar), findsNothing);
    expect(find.text('Docker'), findsOneWidget);
    expect(find.text('Crypto'), findsOneWidget);
  });

  testWidgets('the source dialog disables Add at 8 sources', (
    WidgetTester tester,
  ) async {
    final List<String> eight = <String>[
      for (int i = 0; i < 8; i++) 'user$i/plugins',
    ];
    await _pump(
      tester,
      fetcher: _fakeSource(),
      config: TaskPinConfig(sources: eight),
    );

    await tester.tap(_button('管理来源'));
    await tester.pumpAndSettle();
    expect(find.text('最多支持 8 个源'), findsOneWidget);
    expect(find.text('user7/plugins'), findsWidgets);

    final TpButton add = tester.widget<TpButton>(_button('添加'));
    expect(add.enabled, isFalse);
  });

  testWidgets('the source dialog adds and removes a source', (
    WidgetTester tester,
  ) async {
    await _pump(tester, fetcher: _fakeSource());

    await tester.tap(_button('管理来源'));
    await tester.pumpAndSettle();
    expect(find.text('最多支持 8 个源'), findsNothing);

    await tester.enterText(find.byType(TextField).last, 'a/b');
    await tester.tap(_button('添加'));
    await tester.pumpAndSettle();
    expect(find.text('a/b'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'bad input');
    await tester.tap(_button('添加'));
    await tester.pumpAndSettle();
    expect(find.text('格式应为 user/repo。'), findsOneWidget);

    // Remove the first source (the icon button's tooltip is 删除).
    await tester.tap(find.byTooltip('删除').first);
    await tester.pumpAndSettle();
    expect(find.text(_repo), findsNothing);
    expect(find.text('a/b'), findsOneWidget);
  });
}
