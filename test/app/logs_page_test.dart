// The Logs page shows the same rows the top-nav badge counts. A project with a
// broken config, or whose last bar run failed, appears on the page and the
// badge shows the same number.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:taskpin/app/shell/routes.dart';
import 'package:taskpin/core/bar/bar_channel.dart';
import 'package:taskpin/core/bar/bar_controller.dart';
import 'package:taskpin/core/config/config_providers.dart';
import 'package:taskpin/core/config/config_repository.dart';
import 'package:taskpin/core/config/config_schema.dart';
import 'package:taskpin/core/engine/engine_provider.dart';
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

/// A bar controller whose state is fixed by the test.
class _FixedBars extends BarNotifier {
  _FixedBars(this._state);

  final BarState _state;

  @override
  BarState build() => _state;
}

PinItem _url(String name, {bool pinned = false}) => PinItem(
      type: PinItemType.url,
      name: name,
      url: 'https://api.example.com/v1/price',
      intervalMs: 5000,
      pinned: pinned,
    );

BarSnapshot _failedRun(int index, String error, DateTime at) => BarSnapshot(
      itemIndex: index,
      width: 120,
      x: -1,
      state: BarItemState.error,
      spanCount: 0,
      text: '',
      updatedAt: at,
      error: error,
    );

Future<void> _pump(
  WidgetTester tester,
  TaskPinConfig config,
  BarState bars, {
  String location = AppRoutes.diagnostics,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final GoRouter router = buildRouter();
  router.go(location);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        configRepositoryProvider.overrideWithValue(_MemoryRepository()),
        initialConfigProvider.overrideWithValue(config),
        barControllerProvider.overrideWith(() => _FixedBars(bars)),
        engineProvider.overrideWith((Ref ref) async {
          throw StateError('engine disabled in tests');
        }),
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
}

void main() {
  group('logs page and badge', () {
    testWidgets('a failed run shows on the page and the badge counts it', (
      WidgetTester tester,
    ) async {
      final TaskPinConfig config = TaskPinConfig(
        items: <PinItem>[_url('Price', pinned: true)],
        sources: <String>['bestK/taskpin-plugins'],
      );
      final BarState bars = BarState(
        bars: <int, BarSnapshot>{
          0: _failedRun(0, 'HTTP 503 from api.example.com', DateTime.now()),
        },
      );
      await _pump(tester, config, bars);

      // The page row: project name and the script's message.
      expect(find.text('Price'), findsOneWidget);
      expect(find.text('HTTP 503 from api.example.com'), findsOneWidget);
      expect(find.text('暂无日志'), findsNothing);

      // The badge on the Logs tab carries the same count as the rows.
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('with nothing failing, the page shows the empty state', (
      WidgetTester tester,
    ) async {
      final TaskPinConfig config = TaskPinConfig(
        items: <PinItem>[_url('Price', pinned: true)],
        sources: <String>['bestK/taskpin-plugins'],
      );
      await _pump(tester, config, const BarState());

      expect(find.text('暂无日志'), findsOneWidget);
      expect(find.text('1'), findsNothing);
    });
  });
}
