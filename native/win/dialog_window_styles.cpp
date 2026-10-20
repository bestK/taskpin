// dialog_window_styles.cpp — the Windows half of the `taskpin/window` channel.
//
// Flutter has no API for "no title bar", "hide from Alt+Tab", "let clicks
// through", "be 70% opaque" or "start a system window drag", so a script dialog
// needs these four Win32 effects from native code.
//
// Behaviour parity is against `lib/script_dialog.c`, which is the reference
// implementation of exactly these effects for the GDI dialog:
//
//   borderless   WS_POPUP + WS_EX_TOOLWINDOW            lib/script_dialog.c:78-83
//   clickthrough WM_NCHITTEST -> HTTRANSPARENT          lib/script_dialog.c:623-624
//   opacity      WS_EX_LAYERED + SetLayeredWindowAttributes
//                                                       lib/script_dialog.c:84-85, 101-104
//   shift+drag   WM_NCHITTEST -> HTCAPTION              lib/script_dialog.c:621-622
//   shift+scroll SetWindowPos(..., SWP_NOMOVE|SWP_NOZORDER), w>=80 h>=40
//                                                       lib/script_dialog.c:592-602
//
// Two deliberate differences from the C layer, both forced by the fact that the
// window belongs to Flutter rather than to us:
//
//   1. clickthrough uses WS_EX_TRANSPARENT, not HTTRANSPARENT. The C layer could
//      answer the hit test itself because it owned the WndProc; we do not, and
//      WS_EX_TRANSPARENT is the documented spelling for "input falls through".
//   2. the drag is begun with ReleaseCapture + WM_NCLBUTTONDOWN rather than by
//      returning HTCAPTION from a hit test, for the same reason.
//
// BUILDING
//   Two configurations, so the window logic is verifiable without the Flutter
//   runner (which does not exist in this repo yet — Phase 0 owns `windows/`):
//
//     TASKPIN_DIALOG_STYLES_SELFTEST   compile + run the clamp/centering maths
//                                      with no window and no Flutter
//     TASKPIN_FLUTTER_PLUGIN           the MethodChannel registration, needs
//                                      flutter/plugin_registrar_windows.h
//
//   See the self-test at the bottom of this file.

#include "dialog_window_styles.h"

#include <windows.h>
#include <commctrl.h>
#include <dwmapi.h>

#include <algorithm>
#include <cstdint>

// ─── the pure logic, factored out so it can be tested without a window ──────

namespace taskpin {
namespace dialog {

/// Minimum window size after a Shift+scroll resize.
/// `lib/script_dialog.c:599-600`: `if (w < 80) w = 80; if (h < 40) h = 40;`
constexpr int kMinWidth = 80;
constexpr int kMinHeight = 40;

/// The size a window should become after a resize by (dx, dy).
///
/// Extracted from the Win32 call so the clamp is unit-testable. Note the C
/// behaviour is that BOTH axes move by the same step — a Shift+scroll grows
/// width and height together (`lib/script_dialog.c:596-601`) — so callers pass
/// the same delta twice, and this function does not try to be clever about it.
struct Size {
  int width;
  int height;
};

inline Size clamp_resize(int width, int height, int dx, int dy) {
  return Size{
      std::max(kMinWidth, width + dx),
      std::max(kMinHeight, height + dy),
  };
}

/// Where a window of (w, h) goes when the caller asks to be centred.
///
/// Matches the C layer, which centres on the PRIMARY monitor using
/// `GetSystemMetrics(SM_CXSCREEN/SM_CYSCREEN)` (`lib/script_dialog.c:91-94`).
/// That ignores the taskbar and any per-monitor DPI, so a dialog can overlap the
/// taskbar on a small screen — kept for parity rather than "fixed" here,
/// because moving every existing user's dialog is a visible change.
struct Point {
  int x;
  int y;
};

inline Point centred(int screenWidth, int screenHeight, int width, int height) {
  return Point{(screenWidth - width) / 2, (screenHeight - height) / 2};
}

/// Whether a request needs the window to become layered.
///
/// `lib/script_dialog.c:84-85`: `if (spec->clickthrough || spec->opacity < 255)
/// exstyle |= WS_EX_LAYERED;` — i.e. clickthrough forces layering even at full
/// opacity, because `WS_EX_TRANSPARENT` only does what we want on a layered
/// window.
inline bool needs_layered(bool clickthrough, int opacity) {
  return clickthrough || opacity < 255;
}

/// Clamp an alpha the way `SetLayeredWindowAttributes` expects.
inline BYTE clamp_alpha(int alpha) {
  if (alpha < 0) {
    return 0;
  }
  if (alpha > 255) {
    return 255;
  }
  return static_cast<BYTE>(alpha);
}

}  // namespace dialog
}  // namespace taskpin

// ─── the Win32 effects ─────────────────────────────────────────────────────

namespace {

/// Re-apply the frame after a style change.
///
/// `WS_EX_LAYERED` and the caption bits are read by the window manager when it
/// recomputes the non-client area, which only happens on `SWP_FRAMECHANGED`.
/// Without this the window keeps its old frame until something else resizes it.
void refresh_frame(HWND hwnd) {
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
}

LONG_PTR get_ex_style(HWND hwnd) {
  return GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
}

void set_ex_style_bits(HWND hwnd, LONG_PTR bits, bool on) {
  const LONG_PTR before = get_ex_style(hwnd);
  const LONG_PTR after = on ? (before | bits) : (before & ~bits);
  if (after == before) {
    return;
  }
  SetWindowLongPtrW(hwnd, GWL_EXSTYLE, after);
  refresh_frame(hwnd);
}

void set_style_bits(HWND hwnd, LONG_PTR bits, bool on) {
  const LONG_PTR before = GetWindowLongPtrW(hwnd, GWL_STYLE);
  const LONG_PTR after = on ? (before | bits) : (before & ~bits);
  if (after == before) {
    return;
  }
  SetWindowLongPtrW(hwnd, GWL_STYLE, after);
  refresh_frame(hwnd);
}

// ─── frameless-but-resizable ───────────────────────────────────────────────
//
// `WS_THICKFRAME` is what makes a window resizable by dragging its edges, but
// it also makes Windows draw a non-client frame — the white band that appeared
// around the dialog once resize was restored.
//
// The fix is the standard frameless-window recipe: keep the style (so the hit
// test still reports the resize borders) and answer `WM_NCCALCSIZE` by telling
// Windows the client area is the WHOLE window. Nothing is drawn, and the
// invisible border the user grabs is `SM_CXSIZEFRAME` wide.
//
// Installed as a subclass rather than by replacing the WndProc: the dialog
// window belongs to `desktop_multi_window`'s `FlutterWindow`, which has its own
// message handling we must not disturb.
constexpr UINT_PTR kFramelessSubclassId = 0xD1A106;

LRESULT CALLBACK FramelessProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp,
                               UINT_PTR, DWORD_PTR) {
  if (msg == WM_NCCALCSIZE && wp) {
    // wParam TRUE: lp points at NCCALCSIZE_PARAMS. Leaving the proposed rect
    // untouched means "the client covers the whole window", and returning 0
    // without calling DefWindowProc is the documented way to do that.
    return 0;
  }
  return DefSubclassProc(hwnd, msg, wp, lp);
}

void install_frameless(HWND hwnd) {
  if (hwnd == nullptr) return;
  DWORD_PTR existing = 0;
  if (GetWindowSubclass(hwnd, &FramelessProc, kFramelessSubclassId, &existing)) {
    return;  // already installed
  }
  SetWindowSubclass(hwnd, &FramelessProc, kFramelessSubclassId, 0);
  refresh_frame(hwnd);
}


}  // namespace

/// Remove the title bar and frame; hide from the taskbar and Alt+Tab.
///
/// C parity: `WS_POPUP` (no chrome) + `WS_EX_TOOLWINDOW` (no taskbar button, no
/// Alt+Tab entry) — `lib/script_dialog.c:78-83`. The Flutter window already
/// exists with its own style, so instead of replacing the style wholesale the
/// caption and sizing frame are stripped, which is the same end state without
/// discarding the bits the embedder needs.
void tp_dialog_set_borderless(HWND hwnd, bool borderless) {
  if (hwnd == nullptr) {
    return;
  }
  // Only the CAPTION and the menu go: `WS_THICKFRAME` STAYS.
  //
  // `WS_THICKFRAME` without `WS_CAPTION` is what makes a borderless window
  // resizable by dragging its edges, and it is the style Windows uses for
  // borderless-but-resizable windows generally. Stripping it (as this did
  // originally) left the dialog with no caption AND no resize border, so the
  // only way to change its size was the Shift+scroll path — and that path was
  // itself gated on the script's `borderless` flag.
  //
  // The 1 px DWM frame margin below is what makes the resize border invisible:
  // the user grabs an edge that is not drawn.
  set_style_bits(hwnd, WS_CAPTION | WS_SYSMENU, !borderless);
  set_ex_style_bits(hwnd, WS_EX_TOOLWINDOW, borderless);
  set_ex_style_bits(hwnd, WS_EX_APPWINDOW, !borderless);
  // Strip the frame Windows would draw for WS_THICKFRAME while keeping the
  // style, so the edges stay draggable. See `FramelessProc`.
  install_frameless(hwnd);

  // ROUNDED CORNERS AND A SHADOW.
  //
  // The dialog paints its own rounded surface (`DialogView` uses
  // `TpRadius.overlay`), but a plain borderless window is a rectangle, so the
  // corners were being squared off by the window edge and the panel had no
  // shadow — it sat flat on the desktop instead of floating.
  //
  // Win11 has a first-class answer (`DWMWA_WINDOW_CORNER_PREFERENCE`), applied
  // here. Win10 ignores the attribute and gets only the shadow, which is the
  // same fallback the rest of the app uses (see the title bar's note about
  // Windows 10 having no Mica).
  //
  // Round corners only.
  //
  // `DwmExtendFrameIntoClientArea` was here to give DWM a frame to hang the
  // shadow off, but it FIGHTS `WM_NCCALCSIZE` returning 0: DWM treats the 1 px
  // margin as part of the client area and composites into it, while Flutter
  // paints the same pixels. The two alternate on every repaint, which is what
  // made the dialog flicker while scrolling.
  //
  // The corner preference alone is enough: Win11 rounds the window without any
  // frame extension, and the window keeps the shadow DWM gives every top-level
  // window that has not opted out of it.
  if (borderless) {
    const DWORD corner = 2;  // DWMWCP_ROUND
    DwmSetWindowAttribute(hwnd, 33 /* DWMWA_WINDOW_CORNER_PREFERENCE */,
                          &corner, sizeof(corner));
  }
}

/// Let mouse input fall through to the window beneath.
///
/// `WS_EX_TRANSPARENT` requires `WS_EX_LAYERED` to be present, which is why
/// `needs_layered` treats clickthrough as forcing it.
void tp_dialog_set_clickthrough(HWND hwnd, bool clickthrough) {
  if (hwnd == nullptr) {
    return;
  }
  if (clickthrough) {
    set_ex_style_bits(hwnd, WS_EX_LAYERED, true);
  }
  set_ex_style_bits(hwnd, WS_EX_TRANSPARENT, clickthrough);
}

/// Set the window's alpha.
///
/// C parity: `SetLayeredWindowAttributes(hwnd, 0, alpha, LWA_ALPHA)` with
/// `WS_EX_LAYERED` ensured first (`lib/script_dialog.c:101-104`).
void tp_dialog_set_opacity(HWND hwnd, int alpha) {
  if (hwnd == nullptr) {
    return;
  }
  set_ex_style_bits(hwnd, WS_EX_LAYERED, true);
  SetLayeredWindowAttributes(hwnd, 0, taskpin::dialog::clamp_alpha(alpha),
                             LWA_ALPHA);
}

/// Ask the host to composite the dialog over the desktop.
///
/// HONEST LIMITATION: this enables the layered style, which is the precondition
/// for per-pixel alpha, but it does NOT by itself give a transparent Flutter
/// window. Flutter's Windows embedder presents an opaque surface unless the
/// runner opts into a transparent background when it creates the engine
/// (`FlutterDesktopEngineProperties` / a DirectComposition swapchain), and the
/// runner is Phase 0's file. So on a build where the runner has not opted in,
/// `transparent_bg` degrades to "no fill painted" — which is what the Dart side
/// does when the flag is set — rather than to real see-through compositing.
void tp_dialog_set_transparent_background(HWND hwnd, bool transparent) {
  if (hwnd == nullptr) {
    return;
  }
  set_ex_style_bits(hwnd, WS_EX_LAYERED, transparent);
}

/// Begin a system window drag from the pointer's current position.
///
/// C parity: `WM_NCHITTEST` -> `HTCAPTION` (`lib/script_dialog.c:621-622`).
/// Synthesising the non-client press achieves the same thing from outside the
/// window procedure, and is the standard way to make a Flutter surface
/// draggable. `ReleaseCapture` first, or the drag would be attributed to the
/// control that currently holds capture.
void tp_dialog_begin_drag(HWND hwnd) {
  if (hwnd == nullptr) {
    return;
  }
  ReleaseCapture();
  SendMessageW(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
}

/// Grow the window by a delta, clamped.
///
/// C parity: `SetWindowPos(hwnd, NULL, 0, 0, w, h, SWP_NOMOVE | SWP_NOZORDER)`
/// after the 80x40 clamp (`lib/script_dialog.c:596-601`).
void tp_dialog_resize_by(HWND hwnd, int dx, int dy) {
  if (hwnd == nullptr) {
    return;
  }
  RECT r{};
  if (!GetWindowRect(hwnd, &r)) {
    return;
  }
  const taskpin::dialog::Size next = taskpin::dialog::clamp_resize(
      r.right - r.left, r.bottom - r.top, dx, dy);
  SetWindowPos(hwnd, nullptr, 0, 0, next.width, next.height,
               SWP_NOMOVE | SWP_NOZORDER);
}

/// Position and size the window, adjusting for its own chrome.
///
/// `x` or `y` of -1 means "centre on the primary screen" — the C layer's
/// `(screen - window) / 2` (`lib/script_dialog.c:91-94`).
///
/// The requested width/height are the CLIENT size, so the outer frame is grown
/// by `AdjustWindowRectEx` for whatever chrome the window currently has. That is
/// what `show_script_dialog` does (`lib/script_dialog.c:86-88`), and it is what
/// makes a script's `width = 200, height = 80` mean an 80 px-tall content area
/// rather than an 80 px-tall window with 30 px of it eaten by the title bar.
void tp_dialog_set_frame(HWND hwnd, int x, int y, int width, int height) {
  if (hwnd == nullptr || width <= 0 || height <= 0) {
    return;
  }
  RECT box{0, 0, width, height};
  AdjustWindowRectEx(&box, static_cast<DWORD>(GetWindowLongPtrW(hwnd, GWL_STYLE)),
                     FALSE,
                     static_cast<DWORD>(get_ex_style(hwnd)));
  const int frameW = box.right - box.left;
  const int frameH = box.bottom - box.top;

  int left = x;
  int top = y;
  if (left < 0 || top < 0) {
    const taskpin::dialog::Point p = taskpin::dialog::centred(
        GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN), frameW,
        frameH);
    if (left < 0) {
      left = p.x;
    }
    if (top < 0) {
      top = p.y;
    }
  }
  // Restore first: `desktop_multi_window` creates its window with the runner's
  // default placement, and a window in the maximized state ignores the size in
  // `SetWindowPos` — the call succeeded and the window stayed at 1936x1056 (the
  // maximized frame on a 1920x1080 screen) instead of the spec's 360x240.
  if (IsZoomed(hwnd) || IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  }
  SetWindowPos(hwnd, HWND_TOP, left, top, frameW, frameH,
               SWP_NOACTIVATE | SWP_NOCOPYBITS);
}

/// Close the window.
void tp_dialog_close(HWND hwnd) {
  if (hwnd != nullptr) {
    PostMessageW(hwnd, WM_CLOSE, 0, 0);
  }
}

// ─── the Flutter plugin wrapper ────────────────────────────────────────────
//
// Needs the Flutter headers, which come from the runner that Phase 0 creates.
// Guarded so the rest of this file compiles (and self-tests) without them.

#ifdef TASKPIN_FLUTTER_PLUGIN

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

int int_arg(const EncodableMap& args, const char* key, int fallback) {
  const auto it = args.find(EncodableValue(key));
  if (it == args.end()) {
    return fallback;
  }
  if (const auto* v = std::get_if<int32_t>(&it->second)) {
    return *v;
  }
  if (const auto* v = std::get_if<int64_t>(&it->second)) {
    return static_cast<int>(*v);
  }
  return fallback;
}

/// UTF-8 string arg. Flutter encodes a Dart `String` as UTF-8 bytes in a
/// `std::string`.
std::string string_arg(const EncodableMap& args, const char* key) {
  const auto it = args.find(EncodableValue(key));
  if (it == args.end()) {
    return std::string();
  }
  if (const auto* s = std::get_if<std::string>(&it->second)) {
    return *s;
  }
  return std::string();
}

/// UTF-8 -> UTF-16, for the Win32 W APIs.
std::wstring widen(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  const int n = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                    static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring out(static_cast<size_t>(n), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      out.data(), n);
  return out;
}

bool bool_arg(const EncodableMap& args, const char* key, bool fallback) {
  const auto it = args.find(EncodableValue(key));
  if (it == args.end()) {
    return fallback;
  }
  if (const auto* v = std::get_if<bool>(&it->second)) {
    return *v;
  }
  return fallback;
}

/// Resolve the HWND for the engine that is calling.
///
/// The registrar's view is the Flutter CHILD window inside the dialog's frame.
/// Moving or restyling that child does nothing visible: the top-level window
/// the user sees is its ancestor. `desktop_multi_window` creates the dialog as
/// `FlutterWindow` (a `Win32Window`) and puts the Flutter view inside it, so
/// the frame to move is the ROOT.
///
/// Using the view handle directly was the bug that made `setFrame` "succeed"
/// while the window stayed 800x600: every call went to a child that has no
/// frame of its own.
HWND hwnd_for(flutter::PluginRegistrarWindows* registrar) {
  HWND view = registrar->GetView()->GetNativeWindow();
  if (view == nullptr) {
    return nullptr;
  }
  HWND root = GetAncestor(view, GA_ROOT);
  return root != nullptr ? root : view;
}

class DialogWindowStylesPlugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
        registrar->messenger(), "taskpin/window",
        &flutter::StandardMethodCodec::GetInstance());

    channel->SetMethodCallHandler(
        [registrar](const flutter::MethodCall<EncodableValue>& call,
                    std::unique_ptr<flutter::MethodResult<EncodableValue>>
                        result) {
          const HWND hwnd = hwnd_for(registrar);
          const std::string& method = call.method_name();
          const auto* args =
              call.arguments() ? std::get_if<EncodableMap>(call.arguments())
                               : nullptr;
          const EncodableMap empty;
          const EncodableMap& a = args ? *args : empty;

          if (method == "setBorderless") {
            tp_dialog_set_borderless(hwnd, bool_arg(a, "borderless", false));
          } else if (method == "setClickthrough") {
            tp_dialog_set_clickthrough(hwnd, bool_arg(a, "clickthrough", false));
          } else if (method == "setOpacity") {
            tp_dialog_set_opacity(hwnd, int_arg(a, "alpha", 255));
          } else if (method == "setTransparentBackground") {
            tp_dialog_set_transparent_background(
                hwnd, bool_arg(a, "transparent", false));
          } else if (method == "setFrame") {
            tp_dialog_set_frame(hwnd, int_arg(a, "x", -1), int_arg(a, "y", -1),
                                int_arg(a, "width", 400),
                                int_arg(a, "height", 300));
          } else if (method == "setTitle") {
            // The window is created by `desktop_multi_window` with an EMPTY
            // title, so Windows falls back to the window class name and the
            // caption reads "FLUTTERVIEW". The dialog's own title comes from
            // the spec, which only Dart knows.
            const std::wstring title = widen(string_arg(a, "title"));
            SetWindowTextW(hwnd, title.c_str());
          } else if (method == "beginDrag") {
            tp_dialog_begin_drag(hwnd);
          } else if (method == "setHeight") {
            // Grow or shrink the window so the content fits.
            //
            // A script declares `height = 260` without knowing how tall its
            // own table will be; a seven-row table does not fit, and the last
            // rows were simply unreachable (the scrollbar is suppressed).
            // Dart measures the rendered content and asks for the height it
            // actually needs, clamped here to the work area so a runaway
            // table cannot produce a window taller than the screen.
            const int want = int_arg(a, "height", -1);
            if (want > 0) {
              RECT wr{};
              if (GetWindowRect(hwnd, &wr)) {
                RECT client{};
                GetClientRect(hwnd, &client);
                const int chrome = (wr.bottom - wr.top) - client.bottom;
                int height = want + chrome;
                const int maxH = GetSystemMetrics(SM_CYSCREEN) * 4 / 5;
                if (height > maxH) height = maxH;
                if (height > 0 && height != (wr.bottom - wr.top)) {
                  SetWindowPos(hwnd, nullptr, 0, 0, wr.right - wr.left, height,
                               SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
                }
              }
            }
          } else if (method == "resizeBy") {
            tp_dialog_resize_by(hwnd, int_arg(a, "dx", 0),
                                int_arg(a, "dy", 0));
          } else if (method == "close") {
            tp_dialog_close(hwnd);
          } else if (method == "hide") {
            // Hide, do NOT destroy.
            //
            // `DialogWindowHost` reuses one window (and its Flutter engine) for
            // every dialog; that reuse is what makes reopening instant. The
            // dialog's own X button used to call `close`, which posts
            // `WM_CLOSE` and tears the engine down — so every reopen paid the
            // full cold start (native window + engine + Dart isolate).
            ShowWindow(hwnd, SW_HIDE);
          } else if (method == "show") {
            // Show the SAME window the host hid, and RAISE it.
            //
            // `desktop_multi_window`'s `window_show` calls `ShowWindow` on the
            // handle it recorded at create time, which is not the root window
            // this channel resolves (see `hwnd_for`) — so a dialog hidden here
            // and shown through the plugin stayed invisible: `ShowWindow`
            // succeeded, on the wrong HWND, and the second open did nothing.
            // Hiding and showing both go through this channel so they always
            // agree on which window they mean.
            //
            // RAISING MATTERS AS MUCH AS SHOWING. A second click on a bar
            // whose dialog is already up must bring it to the front: the user
            // clicked because they could not see it (another app is covering
            // it), and "nothing happened" is indistinguishable from "the
            // dialog never opened". `SW_SHOW` alone does nothing to an
            // already-visible window, and `SetForegroundWindow` can be refused
            // by the foreground lock when our process is not the active one.
            //
            // So: un-minimise, set topmost, then drop the topmost flag again.
            // The topmost round-trip is the standard way to raise a window
            // from a background process — it does not need foreground rights,
            // and because the flag is removed immediately the dialog does not
            // stay above everything (that would be wrong for a normal panel).
            if (IsIconic(hwnd)) {
              ShowWindow(hwnd, SW_RESTORE);
            } else {
              ShowWindow(hwnd, SW_SHOW);
            }
            SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
            SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
            SetForegroundWindow(hwnd);
          } else {
            result->NotImplemented();
            return;
          }
          result->Success();
        });
  }
};

}  // namespace

/// Entry point the runner calls, alongside the generated plugin registrant.
void TaskpinDialogWindowStylesRegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  DialogWindowStylesPlugin::RegisterWithRegistrar(registrar);
}

#endif  // TASKPIN_FLUTTER_PLUGIN

// ─── self-test ─────────────────────────────────────────────────────────────
//
// Compile and run with no Flutter and no window:
//
//   /d/mingw64/bin/g++ -std=c++17 -DTASKPIN_DIALOG_STYLES_SELFTEST
//     -o native/win/build/dialog_styles_selftest.exe
//     native/win/dialog_window_styles.cpp
//
// It covers the clamp/centering maths and the layering decision — the parts
// that are wrong silently if they are wrong. The Win32 calls themselves need a
// live window and a runner, and are not covered here.

#ifdef TASKPIN_DIALOG_STYLES_SELFTEST

#include <cstdio>

namespace {

int g_pass = 0;
int g_fail = 0;

void check(const char* name, int expected, int actual) {
  if (expected == actual) {
    ++g_pass;
    std::printf("  PASS  %s\n", name);
  } else {
    ++g_fail;
    std::printf("  FAIL  %s\n        expected: %d\n        actual:   %d\n",
                name, expected, actual);
  }
}

}  // namespace

int main() {
  using namespace taskpin::dialog;

  std::printf("== clamp_resize ==\n");
  check("grow both axes", 220, clamp_resize(200, 80, 20, 20).width);
  check("grow both axes (h)", 100, clamp_resize(200, 80, 20, 20).height);
  check("shrink both axes", 180, clamp_resize(200, 80, -20, -20).width);
  // lib/script_dialog.c:599-600
  check("width floor is 80", 80, clamp_resize(85, 80, -20, 0).width);
  check("height floor is 40", 40, clamp_resize(200, 45, 0, -20).height);
  check("floor does not overshoot", 80, clamp_resize(80, 40, -100, -100).width);

  std::printf("== centred ==\n");
  check("1920x1080 / 400x300 -> x", 760, centred(1920, 1080, 400, 300).x);
  check("1920x1080 / 400x300 -> y", 390, centred(1920, 1080, 400, 300).y);
  check("odd remainder truncates", 1, centred(5, 5, 2, 2).x);

  std::printf("== needs_layered (lib/script_dialog.c:84-85) ==\n");
  check("clickthrough forces layered", 1, needs_layered(true, 255));
  check("translucent forces layered", 1, needs_layered(false, 254));
  check("opaque and solid: no layered", 0, needs_layered(false, 255));
  check("opacity 0 still layered", 1, needs_layered(false, 0));

  std::printf("== clamp_alpha ==\n");
  check("in range", 180, clamp_alpha(180));
  check("negative -> 0", 0, clamp_alpha(-1));
  check("over 255 -> 255", 255, clamp_alpha(300));

  std::printf("\n%d passed, %d failed\n", g_pass, g_fail);
  return g_fail == 0 ? 0 : 1;
}

#endif  // TASKPIN_DIALOG_STYLES_SELFTEST
