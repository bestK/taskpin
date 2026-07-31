/*
 * Independent Win32 + D3D11 + ImGui window helper.
 */
extern "C" {
#include "ui.h"
}

#include "ui_window.h"
#include "ui_common.h"

#include "backends/imgui_impl_dx11.h"
#include "backends/imgui_impl_win32.h"

extern IMGUI_IMPL_API LRESULT ImGui_ImplWin32_WndProcHandler(
    HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam);

#include <dwmapi.h>

#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

static void cleanup_rtv(UiWindow *w) {
    if (w->rtv) { w->rtv->Release(); w->rtv = NULL; }
}

static bool create_rtv(UiWindow *w) {
    if (!w->swap) return false;
    ID3D11Texture2D *bb = NULL;
    HRESULT hr = w->swap->GetBuffer(0, __uuidof(ID3D11Texture2D),
        reinterpret_cast<void **>(&bb));
    if (FAILED(hr) || !bb) return false;
    hr = w->device->CreateRenderTargetView(bb, NULL, &w->rtv);
    bb->Release();
    return SUCCEEDED(hr);
}

void ui_window_center(HWND hwnd, int width, int height) {
    HMONITOR mon = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info = {};
    info.cbSize = sizeof(info);
    if (!GetMonitorInfoW(mon, &info)) return;
    int x = info.rcWork.left + (info.rcWork.right - info.rcWork.left - width) / 2;
    int y = info.rcWork.top + (info.rcWork.bottom - info.rcWork.top - height) / 2;
    SetWindowPos(hwnd, NULL, x, y, width, height, SWP_NOZORDER | SWP_NOACTIVATE);
}

static void set_light_mode(HWND hwnd) {
    BOOL enabled = FALSE;
    DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE,
        &enabled, sizeof(enabled));
}

/* Style is applied via Theme::Apply() at end of ui_window_create() */

static LRESULT CALLBACK ui_window_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    UiWindow *w = reinterpret_cast<UiWindow *>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (w && w->imgui) {
        ImGuiContext *prev = ImGui::GetCurrentContext();
        ImGui::SetCurrentContext(w->imgui);
        if (ImGui_ImplWin32_WndProcHandler(hwnd, msg, wp, lp)) {
            ImGui::SetCurrentContext(prev);
            return 1;
        }
        ImGui::SetCurrentContext(prev);
    }

    switch (msg) {
    case WM_NCCREATE: {
        CREATESTRUCTW *cs = reinterpret_cast<CREATESTRUCTW *>(lp);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, (LONG_PTR)cs->lpCreateParams);
        return TRUE;
    }
    case WM_SIZE:
        if (w && w->swap && wp != SIZE_MINIMIZED &&
            LOWORD(lp) > 0 && HIWORD(lp) > 0) {
            cleanup_rtv(w);
            w->swap->ResizeBuffers(0, LOWORD(lp), HIWORD(lp),
                DXGI_FORMAT_UNKNOWN, 0);
            create_rtv(w);
        }
        return 0;
    case WM_ERASEBKGND:
        return 1;
    case WM_CLOSE:
        if (w) w->done = true;
        ShowWindow(hwnd, SW_HIDE);
        return 0;
    case WM_DESTROY:
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

bool ui_window_create(UiWindow *w, HWND parent, const WCHAR *class_name,
    const WCHAR *title, int width, int height, UiWindow *share) {
    memset(w, 0, sizeof(*w));
    w->class_name = NULL;
    w->title_w = title;

    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.style = CS_OWNDC | CS_DBLCLKS;
    wc.lpfnWndProc = ui_window_proc;
    wc.hInstance = g_hinst;
    wc.hCursor = LoadCursorW(NULL, IDC_ARROW);
    wc.hIcon = LoadIconW(NULL, IDI_APPLICATION);
    wc.hIconSm = wc.hIcon;
    wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
    wc.lpszClassName = class_name;
    if (!RegisterClassExW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
        return false;

    DWORD style;
    DWORD ex;
    if (parent) {
        /* Owned modal dialog — match classic Win32 dialog chrome. */
        style = WS_POPUP | WS_CAPTION | WS_SYSMENU | WS_THICKFRAME |
            WS_CLIPCHILDREN | WS_CLIPSIBLINGS;
        ex = WS_EX_DLGMODALFRAME | WS_EX_WINDOWEDGE;
    } else {
        /* Top-level app window. */
        style = WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN | WS_CLIPSIBLINGS;
        ex = WS_EX_APPWINDOW;
    }

    /* Never pass a null/empty title to CreateWindow — caption would be blank. */
    const WCHAR *safe_title = (title && title[0]) ? title : L"TaskPin";

    w->hwnd = CreateWindowExW(ex, class_name, safe_title, style,
        CW_USEDEFAULT, CW_USEDEFAULT, width, height,
        parent, NULL, g_hinst, w);
    if (!w->hwnd) return false;

    /* Force caption text again (owned/popup windows sometimes drop it). */
    SetWindowTextW(w->hwnd, safe_title);
    set_light_mode(w->hwnd);
    ui_window_center(w->hwnd, width, height);

    if (share && share->device) {
        w->device = share->device;
        w->context = share->context;
        w->device->AddRef();
        w->context->AddRef();

        DXGI_SWAP_CHAIN_DESC sd = {};
        sd.BufferCount = 2;
        sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
        sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
        sd.OutputWindow = w->hwnd;
        sd.SampleDesc.Count = 1;
        sd.Windowed = TRUE;
        sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

        IDXGIDevice *dxgi_dev = NULL;
        IDXGIAdapter *adapter = NULL;
        IDXGIFactory *factory = NULL;
        HRESULT hr = w->device->QueryInterface(__uuidof(IDXGIDevice),
            reinterpret_cast<void **>(&dxgi_dev));
        if (SUCCEEDED(hr)) hr = dxgi_dev->GetAdapter(&adapter);
        if (SUCCEEDED(hr)) hr = adapter->GetParent(__uuidof(IDXGIFactory),
            reinterpret_cast<void **>(&factory));
        if (SUCCEEDED(hr))
            hr = factory->CreateSwapChain(w->device, &sd, &w->swap);
        if (dxgi_dev) dxgi_dev->Release();
        if (adapter) adapter->Release();
        if (factory) factory->Release();
        if (FAILED(hr) || !create_rtv(w)) {
            ui_window_destroy(w);
            return false;
        }
    } else {
        DXGI_SWAP_CHAIN_DESC sd = {};
        sd.BufferCount = 2;
        sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
        sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
        sd.OutputWindow = w->hwnd;
        sd.SampleDesc.Count = 1;
        sd.Windowed = TRUE;
        sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

        D3D_FEATURE_LEVEL levels[] = {
            D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_0
        };
        D3D_FEATURE_LEVEL fl = D3D_FEATURE_LEVEL_10_0;
        UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
        HRESULT hr = D3D11CreateDeviceAndSwapChain(
            NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, flags,
            levels, 2, D3D11_SDK_VERSION,
            &sd, &w->swap, &w->device, &fl, &w->context);
        if (FAILED(hr)) {
            hr = D3D11CreateDeviceAndSwapChain(
                NULL, D3D_DRIVER_TYPE_WARP, NULL, flags,
                levels, 2, D3D11_SDK_VERSION,
                &sd, &w->swap, &w->device, &fl, &w->context);
        }
        if (FAILED(hr) || !create_rtv(w)) {
            ui_window_destroy(w);
            return false;
        }
    }

    /* Own ImGui context — independent of the main window. */
    ImGuiContext *prev = ImGui::GetCurrentContext();
    w->imgui = ImGui::CreateContext();
    ImGui::SetCurrentContext(w->imgui);
    ImGuiIO &io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
    io.IniFilename = NULL;

    /*
     * Font: Microsoft YaHei for Chinese UI, Segoe UI as Latin fallback.
     * Use full Chinese range for complete coverage.
     */
    ImFontConfig cfg;
    cfg.OversampleH = 2;
    cfg.OversampleV = 1;
    cfg.PixelSnapH = true;
    cfg.RasterizerMultiply = 1.1f;
    const ImWchar *ranges = io.Fonts->GetGlyphRangesChineseFull();
    const float font_size = 14.0f;

    /* Primary: YaHei (standard Windows Chinese UI face). */
    bool font_ok = false;
    const char *primary[] = {
        "C:\\Windows\\Fonts\\msyh.ttc",
        "C:\\Windows\\Fonts\\msyh.ttf",
        NULL
    };
    for (int i = 0; primary[i]; i++) {
        if (GetFileAttributesA(primary[i]) == INVALID_FILE_ATTRIBUTES)
            continue;
        if (io.Fonts->AddFontFromFileTTF(primary[i], font_size, &cfg, ranges)) {
            font_ok = true;
            break;
        }
    }

    /* Fallback chain if YaHei missing. */
    if (!font_ok) {
        const char *fallback[] = {
            "C:\\Windows\\Fonts\\Deng.ttf",
            "C:\\Windows\\Fonts\\segoeui.ttf",
            NULL
        };
        for (int i = 0; fallback[i]; i++) {
            if (GetFileAttributesA(fallback[i]) == INVALID_FILE_ATTRIBUTES)
                continue;
            if (io.Fonts->AddFontFromFileTTF(fallback[i], font_size, &cfg, ranges)) {
                font_ok = true;
                break;
            }
        }
    }
    if (!font_ok)
        io.Fonts->AddFontDefault();

    Theme::Apply();
    ImGui_ImplWin32_Init(w->hwnd);
    ImGui_ImplDX11_Init(w->device, w->context);
    ImGui::SetCurrentContext(prev);
    return true;
}

void ui_window_destroy(UiWindow *w) {
    if (!w) return;
    if (w->imgui) {
        ImGuiContext *prev = ImGui::GetCurrentContext();
        ImGui::SetCurrentContext(w->imgui);
        ImGui_ImplDX11_Shutdown();
        ImGui_ImplWin32_Shutdown();
        ImGui::DestroyContext(w->imgui);
        ImGui::SetCurrentContext(prev);
        w->imgui = NULL;
    }
    cleanup_rtv(w);
    if (w->swap) { w->swap->Release(); w->swap = NULL; }
    if (w->context) { w->context->Release(); w->context = NULL; }
    if (w->device) { w->device->Release(); w->device = NULL; }
    if (w->hwnd) {
        DestroyWindow(w->hwnd);
        w->hwnd = NULL;
    }
}

bool ui_window_begin_frame(UiWindow *w, float pad_x, float pad_y) {
    if (!w || !w->imgui || !w->rtv || w->rendering) return false;
    w->rendering = true;

    w->prev_ctx = ImGui::GetCurrentContext();
    ImGui::SetCurrentContext(w->imgui);
    ImGui_ImplDX11_NewFrame();
    ImGui_ImplWin32_NewFrame();
    ImGui::NewFrame();
    w->frame_open = true;

    ImGuiIO &io = ImGui::GetIO();
    ImGui::SetNextWindowPos(ImVec2(0, 0));
    ImGui::SetNextWindowSize(io.DisplaySize);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(pad_x, pad_y));
    ImGui::Begin("##content", NULL,
        ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove |
        ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoBringToFrontOnFocus |
        ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse);
    return true;
}

void ui_window_end_frame(UiWindow *w, const float clear_rgba[4]) {
    if (!w || !w->frame_open) return;
    ImGui::End();
    ImGui::PopStyleVar(); /* WindowPadding from begin_frame */
    ImGui::Render();
    w->frame_open = false;

    w->context->OMSetRenderTargets(1, &w->rtv, NULL);
    w->context->ClearRenderTargetView(w->rtv, clear_rgba);
    ImGui_ImplDX11_RenderDrawData(ImGui::GetDrawData());
    w->swap->Present(1, 0);
    w->rendering = false;

    /* Restore whatever context was active before begin_frame. A nested render
     * (e.g. host WM_TIMER firing inside GetOpenFileNameW's message loop) would
     * otherwise leave GImGui pointing at the wrong context mid-frame. */
    ImGui::SetCurrentContext(w->prev_ctx);
    w->prev_ctx = NULL;
}

void ui_window_run_modal(UiWindow *w, HWND parent,
    void (*draw_fn)(UiWindow *w)) {
    if (!w || !w->hwnd || !draw_fn) return;

    w->done = false;
    w->accepted = false;
    if (parent) EnableWindow(parent, FALSE);

    ShowWindow(w->hwnd, SW_SHOW);
    SetForegroundWindow(w->hwnd);
    SetTimer(w->hwnd, IDT_UI_FRAME, 16, NULL);

    const float clear[4] = {Theme::BgBase.x, Theme::BgBase.y, Theme::BgBase.z, Theme::BgBase.w};
    MSG msg;
    while (!w->done && GetMessageW(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);

        bool should_draw = false;
        if (msg.message == WM_TIMER && msg.hwnd == w->hwnd &&
            msg.wParam == IDT_UI_FRAME)
            should_draw = true;
        else if (msg.hwnd == w->hwnd || !msg.hwnd) {
            if ((msg.message >= WM_MOUSEFIRST && msg.message <= WM_MOUSELAST) ||
                (msg.message >= WM_KEYFIRST && msg.message <= WM_KEYLAST) ||
                msg.message == WM_PAINT || msg.message == WM_SIZE)
                should_draw = true;
        }

        if (should_draw && !w->rendering && IsWindowVisible(w->hwnd)) {
            if (ui_window_begin_frame(w, UI_PAD, UI_PAD)) {
                draw_fn(w);
                ui_window_end_frame(w, clear);
            }
        }
    }

    KillTimer(w->hwnd, IDT_UI_FRAME);
    if (parent) {
        EnableWindow(parent, TRUE);
        SetForegroundWindow(parent);
    }
}
