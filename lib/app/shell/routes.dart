// The manager window's routing table.
//
// One `ShellRoute` wraps every page in `AppShell`. Destinations: `/signals`
// (project list), `/signals/:id` (project detail), `/market`, `/settings`,
// `/diagnostics`, and a debug-only `/gallery`.
//
// The detail page is its own page, not a pane beside the list. The id is an
// index into `TaskPinConfig.items`: the config has no per-item id field.

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:taskpin_design/taskpin_design.dart';

import '../../core/app/app_providers.dart';
import '../../features/market/market_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/signals/signals_editor_page.dart';
import '../../features/signals/signals_list_page.dart';
import '../l10n.dart';
import '../pages/placeholder_page.dart';
import 'app_shell.dart';

/// Route paths, in one place.
class AppRoutes {
  const AppRoutes._();

  static const String root = '/';
  static const String signals = '/signals';
  static const String market = '/market';
  static const String settings = '/settings';
  static const String diagnostics = '/diagnostics';
  static const String gallery = '/gallery';

  /// `/signals/3`.
  static String signal(int index) => '$signals/$index';

  /// The first path segment of [location], for highlighting the rail.
  /// `/signals/3` selects the project destination.
  static String sectionOf(String location) {
    final String trimmed =
        location.startsWith('/') ? location.substring(1) : location;
    final int slash = trimmed.indexOf('/');
    final String head = slash < 0 ? trimmed : trimmed.substring(0, slash);
    return '/$head';
  }
}

/// The router. Built once by `TaskPinApp`.
GoRouter buildRouter() {
  return GoRouter(
    // The updater raises its confirm dialog through this key. `MaterialApp.router`
    // delegates its navigator to the router, so the key must be set here (not on
    // MaterialApp, which ignores `navigatorKey` when `routerConfig` is used).
    navigatorKey: appNavigatorKey,
    initialLocation: AppRoutes.signals,
    // `/` is not a page; send it to the default destination so a cold start
    // never shows an error screen.
    redirect: (BuildContext context, GoRouterState state) =>
        state.uri.path == AppRoutes.root ? AppRoutes.signals : null,
    routes: <RouteBase>[
      ShellRoute(
        builder: (BuildContext context, GoRouterState state, Widget child) =>
            AppShell(location: state.uri.path, child: child),
        routes: <RouteBase>[
          GoRoute(
            path: AppRoutes.signals,
            builder: (BuildContext context, GoRouterState state) =>
                const SignalsListPage(),
            routes: <RouteBase>[
              GoRoute(
                // Relative to the parent: `/signals/:id`.
                path: ':id',
                builder: (BuildContext context, GoRouterState state) {
                  final int index =
                      int.tryParse(state.pathParameters['id'] ?? '') ?? -1;
                  return SignalsEditorPage(
                    key: ValueKey<int>(index),
                    index: index,
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.market,
            builder: (BuildContext context, GoRouterState state) =>
                const MarketPage(),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (BuildContext context, GoRouterState state) =>
                const SettingsPage(),
          ),
          GoRoute(
            path: AppRoutes.diagnostics,
            builder: (BuildContext context, GoRouterState state) =>
                PlaceholderPage(
              title: context.l10n.navLogs,
              message: context.l10n.logsEmpty,
              icon: TpIcons.diagnostics,
            ),
          ),
          // Debug-only: the design system gallery.
          if (kDebugMode)
            GoRoute(
              path: AppRoutes.gallery,
              builder: (BuildContext context, GoRouterState state) =>
                  const _GalleryPage(),
            ),
        ],
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) => Scaffold(
      body: TpErrorState(
        title: context.l10n.pageNotFound,
        message: state.uri.path,
        detail: state.error?.toString(),
        onRetry: () => context.go(AppRoutes.signals),
        retryLabel: context.l10n.pageGoProjects,
      ),
    ),
  );
}

/// Wraps the gallery in the theme's window background.
class _GalleryPage extends StatelessWidget {
  const _GalleryPage();

  @override
  Widget build(BuildContext context) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    return ColoredBox(color: theme.bg.window, child: const TaskPinGallery());
  }
}
