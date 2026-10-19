// TaskPin — application entry point.
//
// This ONE `main` serves both engines: the manager window and each script
// dialog. `desktop_multi_window` starts a child engine on the same Dart entry
// point (its Windows `FlutterWindow::OnCreate` calls
// `set_dart_entrypoint_arguments(["multi_window", id, windowArgument])`), so the
// branch happens here rather than in a separate entry point.
//
// Responsibilities, in order:
//   1. Bind the Flutter engine.
//   2. Decide which window this engine is (manager vs dialog).
//   3. Manager only: single-instance guard, load config (with migration), bring
//      up the manager shell and start the update loop.
//   4. Dialog only: hand off to `dialogWindowMain`, which renders nothing but
//      the dialog.
//
// The taskbar bars are NOT widgets: they are native child windows of
// Shell_TrayWnd, driven over a MethodChannel by `core/bar`. Nothing in this
// file touches them directly — see docs/FLUTTER_REWRITE_PLAN.md ("Windows
// 任务栏条：原生 Direct2D 表面") for why.

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskpin_design/taskpin_design.dart';

import 'app/shell/app_shell.dart';
import 'app/shell/routes.dart';
import 'app/startup.dart';
import 'app/windows/dialog_window.dart';
import 'core/app/single_instance.dart';
import 'core/bar/bar_controller.dart';
import 'core/config/config_providers.dart';
import 'core/config/config_repository.dart';
import 'core/config/config_schema.dart';
import 'l10n/app_localizations.dart';

import 'dart:io';

/// Writes a line to the debug boot log, but ONLY in a debug build.
///
/// This was an unconditional `C:\Users\WIN10\taskpin_boot.txt` write left in from
/// an earlier bring-up session. An absolute per-user path hard-coded into a
/// shipped startup path is not acceptable, so it is gated on [kDebugMode] and
/// switched to the standard `debugPrint` sink — a release build writes no file.
void _bootLog(String message) {
  if (kDebugMode) {
    debugPrint('taskpin.boot: $message');
  }
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Which window is this engine? `dialogWindowArguments` returns non-null ONLY
  // for a window the manager created as a dialog; the manager window's argument
  // string is empty and decodes to "unknown". This must run before any manager
  // setup (config load, single-instance guard), because a dialog is a secondary
  // engine that must NOT take the single-instance lock or touch the config.
  DialogWindowArguments? dialog;
  try {
    dialog = await dialogWindowArguments();
  } catch (_) {
    // A failure here means "cannot tell"; treat this as the manager window,
    // which is the correct default for the first engine.
    dialog = null;
  }

  if (dialog != null) {
    // A dialog window. Render only the dialog and return.
    await dialogWindowMain(dialog, args);
    return;
  }

  await _managerMain(args);
}

/// The manager window's startup. See the file header.
Future<void> _managerMain(List<String> args) async {
  try {
    _bootLog('manager started: args=$args');

    FlutterError.onError = (FlutterErrorDetails details) {
      _bootLog('FLUTTER ERROR: ${details.exceptionAsString()}\n${details.stack}');
    };

    // Single-instance guard. Ports `src/main.c:16-22` (CreateMutexW + check
    // ERROR_ALREADY_EXISTS). A second launch exits immediately so it cannot
    // create a second set of taskbar bars. The guard must outlive `main` for the
    // process's lifetime — `runApp` never returns, so a local held here is
    // enough; the OS releases the mutex when the process exits.
    final SingleInstanceGuard guard = SingleInstanceGuard.acquire();
    if (!guard.acquired) {
      // Another TaskPin owns the machine. Exit quietly, like the C build.
      exit(0);
    }

    // Load config up front. This also runs migration, so a v1 config on disk is
    // upgraded (with a backup) before any UI reads it.
    final ConfigRepository repository =
        ConfigRepository(paths: ConfigPaths.resolve());
    final TaskPinConfig config = await repository.load();
    _bootLog('config loaded: ${config.items.length} items, paths=${repository.paths}');

    runApp(
      ProviderScope(
        overrides: <Override>[
          configRepositoryProvider.overrideWithValue(repository),
          initialConfigProvider.overrideWithValue(config),
          // The bar controller's host seams. It cannot open a URL, open a
          // dialog window or quit the process itself without dragging
          // `dart:io`, the multi-window plugin and the router into a provider
          // that tests must be able to construct, so the three effects are
          // injected here instead.
          //
          // Exit mirrors the C layer: the right-click menu's Exit ends the
          // process (`src/bar_window.c` -> `PostQuitMessage`). The single
          // instance mutex is released by the OS on exit, so no cleanup is
          // needed.
          exitRequestProvider.overrideWithValue(() => exit(0)),
        ],
        child: const TaskPinApp(),
      ),
    );
    _bootLog('runApp completed');
  } catch (e, st) {
    _bootLog('STARTUP EXCEPTION: $e\n$st');
  }
}

class TaskPinApp extends ConsumerWidget {
  const TaskPinApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode mode = ref.watch(appThemeModeProvider);
    final bool dark = switch (mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        View.of(context).platformDispatcher.platformBrightness ==
            Brightness.dark,
    };

    // The window is shown on the first rendered frame. Until the localization
    // delegates load, MaterialApp paints nothing, so that frame would be a blank
    // surface. The colour behind it makes it the window colour instead.
    return ColoredBox(
      color: (dark ? TaskPinTheme.dark() : TaskPinTheme.light()).bg.window,
      child: _buildApp(mode),
    );
  }

  Widget _buildApp(ThemeMode mode) {
    // Both themes are built eagerly: the manager window can be dark while the
    // taskbar it manages is light, and the gallery switches at runtime.
    return MaterialApp.router(
      title: 'TaskPin',
      debugShowCheckedModeBanner: false,
      theme: TaskPinTheme.light().toThemeData(),
      darkTheme: TaskPinTheme.dark().toThemeData(),
      themeMode: mode,

      // Localization. The strings come from `lib/l10n/app_{en,zh}.arb`, which
      // `tool/migrate_lang.py` generates from `lang/{en-US,zh-CN}.json`.
      //
      // `AppLocalizations` is normally emitted by `flutter gen-l10n`. In this
      // environment the Flutter tool could not run, so it was emitted by
      // `tool/gen_l10n_fallback.dart` instead. The class name, file names and
      // member names are identical either way, so switching to the real
      // generator changes nothing here — see that script's header.
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      // Follow the OS language, but only for the two locales that ship strings.
      localeResolutionCallback: (Locale? locale, Iterable<Locale> supported) {
        if (locale == null) return supported.first;
        for (final Locale s in supported) {
          if (s.languageCode == locale.languageCode) return s;
        }
        return supported.first;
      },

      routerConfig: buildRouter(),

      // Starts the update loop after the first frame. `builder` wraps the
      // router's output, so the loop has a mounted navigator (through
      // `appNavigatorKey`) to raise its confirm dialog through.
      builder: (BuildContext context, Widget? child) =>
          AppStartup(child: child ?? const SizedBox.shrink()),
    );
  }
}