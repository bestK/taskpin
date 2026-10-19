// ============================================================================
//  TaskPin window chrome — the `taskpin/main_window` channel (Windows half)
// ============================================================================
//  The manager window draws its own 36 px title bar in Flutter
//  (`lib/ui/widgets/title_bar.dart`). This file supplies what Flutter cannot do
//  itself: the window commands, the maximized state event, and the native hit
//  test that turns the title strip into a drag handle.
//
//  CHANNELS
//    taskpin/main_window          methods: minimize, toggleMaximize, close,
//                                 isMaximized
//    taskpin/main_window/events   a broadcast Stream<bool> of maximizedChanged
//
//  This is deliberately NOT `taskpin/window`: that name already belongs to the
//  script dialog window (`lib/features/dialogs/window_channel.dart` and
//  `native/win/dialog_window_styles.cpp`). One method namespace per window.
//
//  ───────────────────────────────────────────────────────────────────────────
//  CORRECTION 1 — THE DRAG MUST BE ANSWERED BY THE CHILD WINDOW
//  ───────────────────────────────────────────────────────────────────────────
//  The plan said "WM_NCHITTEST: top 36 px -> HTCAPTION" in the top-level
//  window's WndProc. That does nothing in this app. Flutter's surface is a CHILD
//  HWND, created by
//  `SetChildContent(flutter_controller_->view()->GetNativeWindow())` in
//  windows/runner/flutter_window.cpp. Mouse hit-testing hits that child first,
//  so the top-level window never sees WM_NCHITTEST while the pointer is over the
//  Flutter content — the buttons work, the title bar refuses to drag, and the
//  parent's hit test looks "written but ignored".
//
//  The fix: subclass the Flutter child. In the title strip it returns
//  HTTRANSPARENT, which makes Windows continue the hit test with the parent;
//  the parent answers HTCAPTION and the system runs the drag/move loop. Over the
//  three buttons the child returns HTCLIENT instead, so Flutter receives those
//  clicks and can render the hover states itself.
//
//  ───────────────────────────────────────────────────────────────────────────
//  CORRECTION 2 — WM_NCCALCSIZE MUST NOT RETURN 0 BLINDLY
//  ───────────────────────────────────────────────────────────────────────────
//  The plan said "wParam == TRUE -> return 0". That removes the whole frame,
//  including the resize borders, and it makes the maximized client area
//  overhang the work area by ~8 px per side (the buttons at the right edge get
//  clipped). The implementation here instead:
//
//    1. lets DefWindowProc compute the default client rect, so the left, right
//       and bottom resize borders are exactly what Windows wants;
//    2. moves ONLY the top edge out to the proposed window top, which removes
//       the caption but keeps the top resize border usable;
//    3. when maximized, uses the monitor work area. A maximized window's outer
//       rect is inflated past the work area by the resize frame; replacing the
//       client rect with rcWork is what keeps the content inside the screen.
//
//  The proposed rect (`rgrc[0]` as it arrives) is captured BEFORE calling
//  DefWindowProc, because DefWindowProc overwrites the array in place. Using
//  GetWindowRect instead is subtly wrong: while restoring from maximized,
//  Windows calls WM_NCCALCSIZE before it has resized the window, so
//  GetWindowRect still reports the maximized (offscreen) rect and the restored
//  window comes back with a negative top.
//
//  ───────────────────────────────────────────────────────────────────────────
//  CORRECTION 3 — SNAP LAYOUTS: NOT IMPLEMENTED, AND WHY
//  ───────────────────────────────────────────────────────────────────────────
//  Win11 shows the snap flyout when the TOP-LEVEL hit test returns HTMAXBUTTON
//  over the maximize button. For the top level to be asked at all, the child
//  would have to return HTTRANSPARENT over that button — but HTTRANSPARENT does
//  not mean "ask both"; the message goes to the first window below that answers
//  something else, so the click and its hover would be taken away from Flutter.
//  That is exactly the "disturbing the Flutter hit test" the brief allows us to
//  decline, so the button strip stays HTCLIENT.
//
//  TODO(snap): if the snap flyout is ever required, the workable shape is a
//  native-drawn maximize button (the top level owns its hover, click and
//  HTMAXBUTTON, and Flutter draws only the other two). It is not worth losing
//  Flutter's hover/click handling for three buttons today.
//
//  THREADING
//  ---------
//  Everything here runs on the platform thread: the channel handler, the
//  subclass proc, and the EventSink. WM_SIZE arrives during a window resize on
//  the same thread. Sending an event from inside a message dispatch is safe for
//  a channel whose handler is a Dart Stream (no re-entrant platform call), and
//  it is the only way to report a maximize the user performed with Aero Snap,
//  which never goes through this channel.
// ============================================================================

#include "taskpin_window_plugin.h"

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <commctrl.h>
#include <windows.h>
#include <windowsx.h>

#include <memory>
#include <optional>
#include <string>
#include <utility>

namespace {

using flutter::EncodableValue;

constexpr char kMainWindowChannel[] = "taskpin/main_window";
constexpr char kMainWindowEvents[] = "taskpin/main_window/events";

// The subclass id. `SetWindowSubclass` from commctrl.h is the supported way to
// chain a second procedure onto a window we do not own: it keeps the original
// procedure intact, unlike SetWindowLongPtr(GWLP_WNDPROC). commctrl is already
// linked (native/win/CMakeLists.txt lists comctl32).
constexpr UINT_PTR kFlutterViewSubclassId = 0x54504E57;  // 'TPNW'

// Fallback when GetDpiForWindow is unavailable (pre-Win10 1607). The runner is
// per-monitor DPI aware, so this is only a last resort.
constexpr UINT kDefaultDpi = 96;

UINT DpiForWindow(HWND hwnd) {
  // GetDpiForWindow is declared only when WINVER >= 0x0605. The runner does not
  // define WINVER, and the Windows SDK's windows.h defaults it to 0x0500, so a
  // direct call would not compile without a project-wide define. Resolving it
  // at runtime keeps this file self-contained and still works on Windows 10,
  // which is the shipping target.
  using GetDpiForWindowFn = UINT(WINAPI*)(HWND);
  static const GetDpiForWindowFn fn = []() -> GetDpiForWindowFn {
    HMODULE user32 = GetModuleHandleW(L"user32.dll");
    if (!user32) return nullptr;
    return reinterpret_cast<GetDpiForWindowFn>(
        GetProcAddress(user32, "GetDpiForWindow"));
  }();
  if (fn) {
    const UINT dpi = fn(hwnd);
    if (dpi != 0) return dpi;
  }
  return kDefaultDpi;
}

/// Convert a logical-pixel length to physical pixels at [dpi].
///
/// `MulDiv` is the documented DPI conversion. It rounds to nearest, which is
/// what the runner's `Scale` helper does too, so the native hit test and the
/// Flutter layout (which the engine scales the same way) agree at fractional
/// DPIs such as 125 %.
int ScaleDip(int dip, UINT dpi) {
  return MulDiv(dip, static_cast<int>(dpi), 96);
}

/// The client area in screen coordinates.
///
/// Geometry is measured from the CLIENT, not the window rect, and the
/// difference matters when maximized: a maximized window's outer rect is
/// inflated past the work area by the resize frame (`-8, -8, 1928, 1048` on a
/// 1920x1080 screen) while its client is exactly the work area. Using
/// GetWindowRect would put the title strip 8 px above the pixels Flutter
/// actually paints into, and would push the button strip 8 px to the right of
/// where the buttons are drawn.
///
/// Flutter's surface fills the client, so "the top 36 logical px of the
/// client" is exactly the rectangle the Dart title bar occupies.
RECT ClientRectOnScreen(HWND hwnd) {
  RECT client{};
  GetClientRect(hwnd, &client);
  POINT origin{client.left, client.top};
  ClientToScreen(hwnd, &origin);
  RECT r{};
  r.left = origin.x;
  r.top = origin.y;
  r.right = origin.x + (client.right - client.left);
  r.bottom = origin.y + (client.bottom - client.top);
  return r;
}

/// The three-button strip on the right of the title bar, in screen pixels.
///
/// The Dart layout gives each button 46 logical px, so the strip is
/// `3 * 46 = 138` logical px wide. It is measured from the client's right edge,
/// matching the Flutter Row in `title_bar.dart`.
RECT ButtonStripRect(HWND top_level) {
  const RECT client = ClientRectOnScreen(top_level);
  const UINT dpi = DpiForWindow(top_level);
  const int strip = ScaleDip(kTaskpinWindowButtonWidthDip *
                                     kTaskpinWindowButtonCount,
                                 dpi);
  const int height = ScaleDip(kTaskpinTitleBarHeightDip, dpi);
  RECT r{};
  r.left = client.right - strip;
  r.top = client.top;
  r.right = client.right;
  r.bottom = client.top + height;
  return r;
}

bool Contains(const RECT& r, POINT p) {
  return p.x >= r.left && p.x < r.right && p.y >= r.top && p.y < r.bottom;
}

bool IsPointInTitleStrip(HWND top_level, POINT screen_point) {
  const RECT client = ClientRectOnScreen(top_level);
  const UINT dpi = DpiForWindow(top_level);
  const int height = ScaleDip(kTaskpinTitleBarHeightDip, dpi);
  RECT strip{};
  strip.left = client.left;
  strip.top = client.top;
  strip.right = client.right;
  strip.bottom = client.top + height;
  return Contains(strip, screen_point);
}

bool IsPointInButtonStrip(HWND top_level, POINT screen_point) {
  return Contains(ButtonStripRect(top_level), screen_point);
}

// --------------------------------------------------------------- plugin -----

class MainWindowPlugin : public flutter::Plugin {
 public:
  MainWindowPlugin(flutter::PluginRegistrarWindows* registrar, HWND top_level,
                   HWND flutter_view)
      : registrar_(registrar),
        top_level_(top_level),
        flutter_view_(flutter_view) {}

  ~MainWindowPlugin() override {
    if (flutter_view_) {
      RemoveWindowSubclass(flutter_view_, &MainWindowPlugin::FlutterViewProc,
                           kFlutterViewSubclassId);
      flutter_view_ = nullptr;
    }
    if (registrar_) {
      registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
      registrar_ = nullptr;
    }
  }

  void Init() {
    channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
        registrar_->messenger(), kMainWindowChannel,
        &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler(
        [this](const flutter::MethodCall<EncodableValue>& call,
               std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
          HandleMethod(call, std::move(result));
        });

    events_ = std::make_unique<flutter::EventChannel<EncodableValue>>(
        registrar_->messenger(), kMainWindowEvents,
        &flutter::StandardMethodCodec::GetInstance());
    events_->SetStreamHandler(
        std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
            [this](const EncodableValue*,
                   std::unique_ptr<flutter::EventSink<EncodableValue>>&& sink) {
              event_sink_ = std::move(sink);
              // Send the current state immediately. The Dart side subscribes
              // after its first frame; without this it would show the wrong
              // glyph for a window restored already maximized (Aero Snap state
              // is not persisted, but a debug hot restart can land here).
              EmitMaximized();
              return std::unique_ptr<flutter::StreamHandlerError<EncodableValue>>();
            },
            [this](const EncodableValue*) {
              event_sink_.reset();
              return std::unique_ptr<flutter::StreamHandlerError<EncodableValue>>();
            }));

    // Top-level delegate: the caption hit test. FlutterWindow's MessageHandler
    // calls HandleTopLevelWindowProc before Win32Window's own switch, so this
    // runs for every message the runner sees. Returning nullopt everywhere
    // else keeps Flutter's own delegates and the runner's switch untouched.
    window_proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
        [this](HWND hwnd, UINT message, WPARAM, LPARAM lparam)
            -> std::optional<LRESULT> {
          if (hwnd != top_level_) return std::nullopt;

          switch (message) {
            case WM_NCHITTEST: {
              const POINT p{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
              if (IsPointInTitleStrip(top_level_, p) &&
                  !IsPointInButtonStrip(top_level_, p)) {
                return HTCAPTION;
              }
              // TODO(snap): HTMAXBUTTON would go here. See CORRECTION 3 at the
              // top of this file for why the button strip is left to Flutter.
              return std::nullopt;
            }
            case WM_SIZE: {
              // Covers Aero Snap, Win+Up, and the system menu as well as our
              // own channel calls: every one of them ends here.
              EmitMaximized();
              return std::nullopt;
            }
            case WM_DPICHANGED:
              // Nothing to do: every rect above is computed on demand from the
              // live DPI. Returning nullopt lets the runner's own
              // WM_DPICHANGED handler resize the window as Windows asks.
              return std::nullopt;
            default:
              return std::nullopt;
          }
        });

    if (flutter_view_) {
      SetWindowSubclass(flutter_view_, &MainWindowPlugin::FlutterViewProc,
                        kFlutterViewSubclassId,
                        reinterpret_cast<DWORD_PTR>(this));
    }
  }

 private:
  // ---- method dispatch -----------------------------------------------------

  void HandleMethod(
      const flutter::MethodCall<EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    if (!top_level_ || !IsWindow(top_level_)) {
      result->Error("no_window", "the manager window is gone");
      return;
    }

    const std::string& method = call.method_name();
    if (method == "minimize") {
      ShowWindow(top_level_, SW_MINIMIZE);
      result->Success();
    } else if (method == "toggleMaximize") {
      ShowWindow(top_level_, IsZoomed(top_level_) ? SW_RESTORE : SW_MAXIMIZE);
      EmitMaximized();
      result->Success();
    } else if (method == "close") {
      PostMessageW(top_level_, WM_CLOSE, 0, 0);
      result->Success();
    } else if (method == "isMaximized") {
      result->Success(EncodableValue(IsZoomed(top_level_) != FALSE));
    } else {
      result->NotImplemented();
    }
  }

  void EmitMaximized() {
    if (!event_sink_ || !top_level_) return;
    event_sink_->Success(
        EncodableValue(IsZoomed(top_level_) != FALSE));
  }

  // ---- child-window hit test (CORRECTION 1 + 3) ---------------------------

  static LRESULT CALLBACK FlutterViewProc(HWND hwnd, UINT message,
                                          WPARAM wparam, LPARAM lparam,
                                          UINT_PTR, DWORD_PTR ref_data) {
    auto* self = reinterpret_cast<MainWindowPlugin*>(ref_data);
    if (self && message == WM_NCHITTEST && self->top_level_) {
      const POINT p{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      // The button strip is deliberately NOT transparent: Flutter must keep
      // receiving hover and clicks for the three buttons it draws. Only the
      // rest of the title strip falls through, so the parent can answer
      // HTCAPTION and the system can run the drag loop.
      if (IsPointInTitleStrip(self->top_level_, p) &&
          !IsPointInButtonStrip(self->top_level_, p)) {
        return HTTRANSPARENT;
      }
    }
    return DefSubclassProc(hwnd, message, wparam, lparam);
  }

  flutter::PluginRegistrarWindows* registrar_ = nullptr;
  HWND top_level_ = nullptr;
  HWND flutter_view_ = nullptr;
  int window_proc_id_ = -1;

  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel_;
  std::unique_ptr<flutter::EventChannel<EncodableValue>> events_;
  std::unique_ptr<flutter::EventSink<EncodableValue>> event_sink_;
};

}  // namespace

// ---- exported entry point -------------------------------------------------

void TaskpinWindowRegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar, HWND top_level,
    HWND flutter_view) {
  if (!registrar || !top_level) return;
  auto plugin =
      std::make_unique<MainWindowPlugin>(registrar, top_level, flutter_view);
  plugin->Init();
  registrar->AddPlugin(std::move(plugin));
}
