// The manager window shell: nav rail on the left, routed page on the right.
//
// The rail has no background and no divider and sits on the window colour
// (docs/VISUAL_SPEC.md section 5.1). It is 240 wide, and collapses to a 48 wide
// icon rail when the window is narrower than 900.
//
// The taskbar bars are native windows, not widgets. Nothing here draws them.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:taskpin_design/taskpin_design.dart';

import '../../core/bar/bar_controller.dart';
import '../../core/bar/bar_source.dart' show resolveScriptPath;
import '../../core/config/config_providers.dart';
import '../../core/config/config_schema.dart';
import '../../features/signals/widgets/item_status.dart';
import '../../ui/widgets/title_bar.dart';
import '../l10n.dart';
import 'routes.dart';

/// Window width below which the rail collapses to icons.
const double kRailCollapseWidth = 900;

/// App theme mode. Defaults to following the system.
final StateProvider<ThemeMode> appThemeModeProvider =
    StateProvider<ThemeMode>((Ref ref) => ThemeMode.system);

/// The shell frame.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  /// The current location, from `GoRouterState.uri.path`.
  final String location;

  /// The routed page.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TaskPinTheme theme = TaskPinTheme.of(context);
    final String section = AppRoutes.sectionOf(location);

    final TaskPinConfig config = ref.watch(configProvider);
    final Map<int, BarSnapshot> bars =
        ref.watch(barControllerProvider.select((BarState s) => s.bars));
    final int errorCount = countItemsWithErrors(config.items, bars, _baseDir(ref));

    return Scaffold(
      backgroundColor: theme.bg.window,
      body: Column(
        children: <Widget>[
          // The window has no system caption (windows/runner/win32_window.cpp
          // removes it in WM_NCCALCSIZE), so this bar IS the caption: dragging,
          // double-click to maximize and the three window buttons all live
          // here. It sits above the shell, spanning the full width, so the
          // buttons align with the window edge rather than the page.
          const TitleBar(),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool collapsed = constraints.maxWidth < kRailCollapseWidth;
                return TpAppShell(
            rail: Padding(
              // Same top as the page content (24), so the first item and the page
              // title share a line.
              padding: const EdgeInsets.only(top: TpSpacing.s24),
              child: TpNavRail(
                selectedRoute: section,
                collapsed: collapsed,
                onSelect: (String route) => context.go(route),
                destinations: <TpNavDestination>[
                  TpNavDestination(
                    label: context.l10n.navProjects,
                    icon: TpIcons.signals,
                    route: AppRoutes.signals,
                    badgeCount: config.items.length,
                  ),
                  TpNavDestination(
                    label: context.l10n.marketTitle,
                    icon: TpIcons.market,
                    route: AppRoutes.market,
                  ),
                  TpNavDestination(
                    label: context.l10n.navLogs,
                    icon: TpIcons.diagnostics,
                    route: AppRoutes.diagnostics,
                    badgeCount: errorCount,
                    badgeCritical: true,
                  ),
                ],
                footerDestinations: <TpNavDestination>[
                  TpNavDestination(
                    label: context.l10n.mainSettings,
                    icon: TpIcons.settings,
                    route: AppRoutes.settings,
                  ),
                ],
              ),
            ),
            child: TpToastHost(child: child),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _baseDir(WidgetRef ref) {
    try {
      return ref.read(configRepositoryProvider).paths.baseDir;
    } on Object {
      return '';
    }
  }
}

/// Number of items that cannot run: a missing or unset script, an unset URL,
/// or a script error reported by the bar controller.
int countItemsWithErrors(
  List<PinItem> items,
  Map<int, BarSnapshot> bars,
  String baseDir,
) {
  int count = 0;
  for (int i = 0; i < items.length; i++) {
    final SignalStatus status = SignalStatus.of(
      items[i],
      pathExists: (String p) {
        try {
          return File(resolveScriptPath(p, baseDir)).existsSync();
        } on Object {
          return false;
        }
      },
    );
    final String? error = bars[i]?.error;
    if (!status.isRunnable || (error != null && error.isNotEmpty)) {
      count++;
    }
  }
  return count;
}
