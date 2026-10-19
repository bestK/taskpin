#include "flutter_window.h"

#include <optional>

#include <flutter/plugin_registrar.h>
#include <flutter/plugin_registrar_windows.h>

#include "flutter/generated_plugin_registrant.h"

// TaskPin's own native plugin: the `taskpin/bar` MethodChannel that drives the
// taskbar bars. Hand-registered rather than generated because it lives in
// `native/win/` (not in a pub package), so `flutter pub get` has no way to
// discover it. It is a no-op unless its native source was compiled with
// TASKPIN_FLUTTER_PLUGIN, which `native/win/CMakeLists.txt` sets whenever the
// Flutter targets exist — i.e. always, in this build.
#include "../../native/win/bar_channel.h"

// TaskPin's manager-window chrome: the `taskpin/main_window` MethodChannel and
// event stream (window buttons + maximized state) plus the child-window hit
// test that makes the self-drawn title bar draggable. Unlike `taskpin/bar`,
// this registration is intentionally manager-only: it is wired into the
// runner's own FlutterWindow below, and dialog windows are created by
// `desktop_multi_window` with its own window class and engine, so they never
// reach this code. That is what we want — a dialog has no custom title bar.
#include "../../native/win/taskpin_window_plugin.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  // TaskPin's native bar plugin. `GetRegistrarForPlugin` returns the C handle
  // and the manager wraps it — the same two-step
  // `desktop_multi_window` uses (windows/desktop_multi_window_plugin.cpp:114).
  // Constructing a `PluginRegistrarWindows` by hand instead would make a second
  // wrapper for one registrar, which the header calls undefined behaviour.
  FlutterDesktopPluginRegistrarRef registrar_ref =
      flutter_controller_->engine()->GetRegistrarForPlugin("TaskPinBar");
  flutter::PluginRegistrarWindows* registrar =
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar_ref);
  TaskpinBarRegisterWithRegistrar(registrar);

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Manager-window chrome, registered next to the bar channel above and for
  // the same reason (a hand-written native plugin living outside a pub
  // package). It must run AFTER SetChildContent: the plugin subclasses the
  // Flutter child window, and before `SetParent` that HWND is still a
  // top-level window of the engine, not our child.
  TaskpinWindowRegisterWithRegistrar(registrar, GetHandle(),
                                     flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
