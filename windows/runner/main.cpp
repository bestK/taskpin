// TaskPin — Windows runner.
//
// This is the stock Flutter 3.47.7 runner with two local changes:
//
//   1. The window title is "TaskPin" rather than the project name.
//   2. The manager window is sized for the management UI (1200x760) instead of
//      the template's 1280x720. The minimum size (800x560) is enforced in
//      win32_window.cpp.
//
// IMPORTANT: this window is ONLY the manager UI. The taskbar bars are NOT
// children of it. Each pinned item is a separate native WS_POPUP window created
// by `native/win/bar_window.cpp` and re-parented into `Shell_TrayWnd`; this
// process never hosts them. See docs/FLUTTER_REWRITE_PLAN.md, "Windows 任务栏条：
// 原生 Direct2D 表面" for why (the Flutter engine's swapchain is bound to this
// HWND and the runner's WndProc assumes it is a root window).
//
// The engine static library (`taskpin_engine`) and the bar library
// (`taskpin_bar`) are linked in by windows/CMakeLists.txt. Nothing here needs to
// call into them yet — Phase 3 (FFI) and Phase 7 (MethodChannel) own that.

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1200, 760);
  if (!window.Create(L"TaskPin", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
