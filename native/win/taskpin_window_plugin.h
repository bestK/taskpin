// ============================================================================
//  TaskPin window chrome — the `taskpin/main_window` channel (Windows half)
// ============================================================================
//  The manager window draws its own 36 px title bar in Flutter
//  (`lib/ui/widgets/title_bar.dart`). This file supplies the two things Flutter
//  cannot do itself:
//
//    1. the window commands (minimize / maximize / close) over
//       `taskpin/main_window`, and the `maximizedChanged` event over
//       `taskpin/main_window/events`;
//    2. the native hit test that makes the title strip drag the window.
//
//  NAMING: this is NOT `taskpin/window`. That channel already belongs to the
//  script dialog window (`lib/features/dialogs/window_channel.dart`,
//  `native/win/dialog_window_styles.cpp`). Two windows with different needs
//  must not share one method namespace.
//
//  WHY THE HIT TEST LIVES IN THE CHILD WINDOW (docs/UI_REFACTOR_PLAN.md §5,
//  correction 1): Flutter's content is a CHILD HWND, created by
//  `SetChildContent(flutter_controller_->view()->GetNativeWindow())` in
//  windows/runner/flutter_window.cpp. Mouse hit-testing hits that child first,
//  so returning HTCAPTION from the top-level window's WndProc never runs while
//  the pointer is over the Flutter surface. The child is therefore subclassed:
//  it answers HTTRANSPARENT for the title strip, which makes Windows continue
//  the hit test with the parent, and the parent answers HTCAPTION. The three
//  window buttons are deliberately excluded from that strip so Flutter keeps
//  receiving their clicks.
// ============================================================================
#ifndef TASKPIN_WINDOW_PLUGIN_H
#define TASKPIN_WINDOW_PLUGIN_H

#include <windows.h>

// Forward-declared rather than included, so the runner can use the entry point
// below without pulling the Flutter C++ wrapper into win32_window.cpp. The
// definition sees the identical type through plugin_registrar_windows.h.
namespace flutter {
class PluginRegistrarWindows;
}

// Title bar geometry, in logical pixels at 96 DPI. These must agree with
// `kTitleBarHeight` / `kTitleBarButtonWidth` in
// `lib/ui/widgets/title_bar.dart`: the Dart layout puts the buttons exactly
// here, and the native hit test leaves exactly this strip to Flutter.
constexpr int kTaskpinTitleBarHeightDip = 36;
constexpr int kTaskpinWindowButtonWidthDip = 46;
constexpr int kTaskpinWindowButtonCount = 3;

/// Registers the channel pair and installs the child-window hit-test subclass.
///
/// [top_level] is the runner's Win32Window handle; [flutter_view] is the child
/// HWND hosting Flutter (`FlutterView::GetNativeWindow()`). Both must outlive
/// the plugin, which the registrar owns. Must be called on the platform thread,
/// after the Flutter view has been re-parented into [top_level].
void TaskpinWindowRegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar,
                                        HWND top_level,
                                        HWND flutter_view);

#endif  // TASKPIN_WINDOW_PLUGIN_H
