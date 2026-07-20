#ifndef TASKPIN_UI_WINDOW_H
#define TASKPIN_UI_WINDOW_H

/*
 * One real Win32 window = one D3D11 swap chain = one ImGui context.
 * Used for main host and for independent dialog windows.
 */

#include <windows.h>
#include <d3d11.h>
#include "imgui.h"

struct UiWindow {
    HWND hwnd;
    ID3D11Device *device;
    ID3D11DeviceContext *context;
    IDXGISwapChain *swap;
    ID3D11RenderTargetView *rtv;
    ImGuiContext *imgui;
    bool class_registered;
    bool frame_open;
    bool rendering;
    bool done;          /* set true to exit modal loop */
    bool accepted;      /* OK pressed */
    void *user;         /* page-specific state */
    const char *class_name;
    const WCHAR *title_w;
};

/* Create a top-level window. Shares D3D device from `share` if non-NULL. */
bool ui_window_create(UiWindow *w, HWND parent, const WCHAR *class_name,
    const WCHAR *title, int width, int height, UiWindow *share_device);

void ui_window_destroy(UiWindow *w);

/* Begin/end one ImGui frame for this window. Returns false if skipped.
 * pad: content window padding (default UI_PAD via callers). */
bool ui_window_begin_frame(UiWindow *w, float pad_x, float pad_y);
void ui_window_end_frame(UiWindow *w, const float clear_rgba[4]);

/* Modal loop: disable parent, pump messages until w->done. */
void ui_window_run_modal(UiWindow *w, HWND parent,
    void (*draw_fn)(UiWindow *w));

/* Center on nearest monitor / parent. */
void ui_window_center(HWND hwnd, int width, int height);

#endif
