// ============================================================================
//  TaskPin bar — the `taskpin/bar` MethodChannel (Flutter plugin wrapper)
// ============================================================================
//  The bridge between `lib/core/bar/` (Dart) and the Direct2D bar module.
//
//  WHY A CHANNEL AND NOT FFI (docs/FLUTTER_REWRITE_PLAN.md):
//    "条用 channel 不用 FFI：载荷小且低频（≤ 几 Hz），native→Dart 从插件
//     registrar 在 UI 线程发很简单，而从 Win32 消息循环回调进 Dart 才是脆弱
//     的部分。FFI 留给引擎。"
//
//  So this file is where that "fragile part" is handled. See the THREADING note
//  in bar_channel.cpp — the bar windows are created on the platform thread, and
//  every event is marshalled back onto it before it touches the channel.
//
//  Build configuration: compiled only when TASKPIN_FLUTTER_PLUGIN is defined,
//  which `native/win/CMakeLists.txt` does when the module is built as part of
//  the Flutter runner (the `flutter` target exists). A standalone MinGW build of
//  this directory therefore still works and simply omits the channel — the same
//  arrangement `dialog_window_styles.cpp` uses.
// ============================================================================
#ifndef TASKPIN_BAR_CHANNEL_H
#define TASKPIN_BAR_CHANNEL_H

// Forward-declared rather than included, so the RUNNER can see the entry point
// below without dragging the Flutter C++ headers in. `bar_channel.cpp` includes
// the real header and therefore sees the identical type.
namespace flutter {
class PluginRegistrarWindows;
}

/// Entry point the runner calls, alongside the generated plugin registrant.
///
/// Declared UNCONDITIONALLY on purpose. The runner is a separate CMake target
/// from `taskpin_bar` and does not share its `TASKPIN_FLUTTER_PLUGIN` define, so
/// guarding this declaration would make the runner fail with
/// "identifier not found" while the library compiled fine. The definition in
/// `bar_channel.cpp` is a no-op when the define is absent (the standalone MinGW
/// build of `native/win`), so the symbol always exists and always links.
///
/// Named in the same shape as `TaskpinDialogWindowStylesRegisterWithRegistrar`
/// (native/win/dialog_window_styles.cpp) so the runner's registration block
/// reads as one list.
void TaskpinBarRegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

#ifdef TASKPIN_FLUTTER_PLUGIN

#include <flutter/plugin_registrar_windows.h>

namespace taskpin {
namespace bar {

/// Register the `taskpin/bar` channel with the engine behind `registrar`.
///
/// The bars are owned by the plugin, which the registrar owns, so they are torn
/// down with the engine.
void BarChannelRegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

}  // namespace bar
}  // namespace taskpin

#endif  // TASKPIN_FLUTTER_PLUGIN

#endif  // TASKPIN_BAR_CHANNEL_H
