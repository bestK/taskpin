// The `taskpin/window` channel for script dialogs — declaration.
//
// The implementation is `dialog_window_styles.cpp`. It was written in Phase 6
// but never added to a CMakeLists, so the channel did not exist in the shipped
// Windows build and every dialog opened at the OS default size with a system
// title bar.
//
// WHO REGISTERS IT. Not the runner's own window: a script dialog is created by
// `desktop_multi_window` with its own `FlutterWindow` and its own engine, so
// the runner's `OnCreate` never sees it. `windows/runner/flutter_window.cpp`
// installs a `WindowCreatedCallback` and calls this function for each child
// engine instead.
//
// NO FLUTTER INCLUDE HERE. `native/win` is also built standalone with MinGW for
// the bar demo harness, where the Flutter headers do not exist. The one type
// this header names is forward-declared, which is enough for a pointer
// parameter; the .cpp includes the real header under TASKPIN_FLUTTER_PLUGIN.
#ifndef TASKPIN_DIALOG_WINDOW_STYLES_H
#define TASKPIN_DIALOG_WINDOW_STYLES_H

namespace flutter {
class PluginRegistrarWindows;
}  // namespace flutter

/// Install the `taskpin/window` handler on `registrar`'s engine.
///
/// The channel is per-engine: it resolves its window from the registrar's
/// view, so the dialog that calls it is the one that moves.
///
/// Defined only when the library is built with TASKPIN_FLUTTER_PLUGIN (i.e. as
/// part of the Flutter runner). The runner is always such a build.
void TaskpinDialogWindowStylesRegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar);

#endif  // TASKPIN_DIALOG_WINDOW_STYLES_H
