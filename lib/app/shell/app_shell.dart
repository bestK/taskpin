// The manager window shell: the caption strip, the centered top navigation,
// then the routed page.
//
// The stage world has no sidebar. Navigation is a row of words centred in a
// 52 px bar under the title bar, the way a product site names its sections;
// the page below is free to open with a full-width stage.
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
import '../../features/dialogs/inline_dialog_layer.dart';
import '../../ui/widgets/title_bar.dart';
import '../l10n.dart';
import 'routes.dart';

/// App theme mode. Defaults to following the system.
final StateProvider<ThemeMode> appThemeModeProvider =
    StateProvider<ThemeMode>((Ref ref) => ThemeMode.dark); // TEMP-SHOT

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
    final int errorCount =
        countItemsWithErrors(config.items, bars, _baseDir(ref));

    return _withInlineDialogs(
      Scaffold(
        backgroundColor: theme.bg.window,
        body: Column(
          children: <Widget>[
            // The window has no system caption (windows/runner/win32_window.cpp
            // removes it in WM_NCCALCSIZE), so this bar IS the caption:
            // dragging, double-click to maximize and the three window buttons
            // all live here.
            const TitleBar(),
            TpTopNav(
              selectedRoute: section,
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
                TpNavDestination(
                  label: context.l10n.mainSettings,
                  icon: TpIcons.settings,
                  route: AppRoutes.settings,
                ),
              ],
            ),
            Expanded(child: TpToastHost(child: child)),
          ],
        ),
      ),
    );
  }

  /// The shell plus the inline-dialog layer.
  ///
  /// The layer goes OUTSIDE the `Scaffold` so it covers the self-drawn title
  /// bar too: a modal dialog that leaves the window buttons clickable is not
  /// modal. It is a `Stack`, not a route, because a script dialog is a
  /// transient panel over whatever page is showing, and navigating away should
  /// not silently dismiss it (`DialogController.close` is the only closer).
  static Widget _withInlineDialogs(Widget shell) => Stack(
        fit: StackFit.expand,
        children: <Widget>[
          shell,
          const InlineDialogLayer(),
        ],
      );

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
