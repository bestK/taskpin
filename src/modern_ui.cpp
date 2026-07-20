/*
 * TaskPin 管理窗口的现代 UI 层。
 *
 * Dear ImGui 只负责交互和绘制，配置、脚本执行以及任务栏窗口仍由原有
 * C 模块管理。这样管理窗口可以独立演进，同时不改变配置文件格式。
 */
extern "C" {
#include "ui.h"
}

#include "imgui.h"
#include "backends/imgui_impl_dx11.h"
#include "backends/imgui_impl_win32.h"

/* Dear ImGui 为避免后端头文件强依赖 windows.h，要求应用自行声明该函数。 */
extern IMGUI_IMPL_API LRESULT ImGui_ImplWin32_WndProcHandler(
    HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam);

#include <d3d11.h>
#include <dwmapi.h>
#include <cstdio>

#ifndef TASKPIN_VERSION
#define TASKPIN_VERSION "dev"
#endif

#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

static HWND g_ui_hwnd = NULL;
static ID3D11Device *g_d3d_device = NULL;
static ID3D11DeviceContext *g_d3d_context = NULL;
static IDXGISwapChain *g_swap_chain = NULL;
static ID3D11RenderTargetView *g_render_target = NULL;
static bool g_imgui_ready = false;
static bool g_ui_class_registered = false;
static int g_selected_item = -1;

/* Uber black/white duet — DESIGN.md tokens */
static const ImVec4 kPrimary = ImVec4(0.0f, 0.0f, 0.0f, 1.0f);
static const ImVec4 kOnPrimary = ImVec4(1.0f, 1.0f, 1.0f, 1.0f);
static const ImVec4 kCanvas = ImVec4(1.0f, 1.0f, 1.0f, 1.0f);
static const ImVec4 kCanvasSoft = ImVec4(0.937f, 0.937f, 0.937f, 1.0f);   /* #EFEFEF */
static const ImVec4 kCanvasSofter = ImVec4(0.953f, 0.953f, 0.953f, 1.0f); /* #F3F3F3 */
static const ImVec4 kBorder = ImVec4(0.886f, 0.886f, 0.886f, 1.0f);       /* #E2E2E2 */
static const ImVec4 kText = ImVec4(0.0f, 0.0f, 0.0f, 1.0f);
static const ImVec4 kBody = ImVec4(0.369f, 0.369f, 0.369f, 1.0f);         /* #5E5E5E */
static const ImVec4 kMuted = ImVec4(0.686f, 0.686f, 0.686f, 1.0f);        /* #AFAFAF */
static const ImVec4 kDanger = ImVec4(0.706f, 0.137f, 0.094f, 1.0f);       /* #B42318 */
static const ImVec4 kDangerSoft = ImVec4(0.996f, 0.894f, 0.886f, 1.0f);   /* #FEE4E2 */
static const ImVec4 kBlackElevated = ImVec4(0.157f, 0.157f, 0.157f, 1.0f);

static ImU32 color_u32(const ImVec4 &color) {
    return ImGui::ColorConvertFloat4ToU32(color);
}

static const char *wide_to_utf8(const WCHAR *source, char *dest, int capacity) {
    if (!dest || capacity <= 0) return "";
    dest[0] = '\0';
    if (!source || !source[0]) return dest;

    int length = WideCharToMultiByte(CP_UTF8, 0, source, -1, dest, capacity, NULL, NULL);
    if (length <= 0) {
        dest[0] = '?';
        dest[1 < capacity ? 1 : 0] = '\0';
    } else {
        dest[capacity - 1] = '\0';
    }
    return dest;
}

static void cleanup_render_target(void) {
    if (g_render_target) {
        g_render_target->Release();
        g_render_target = NULL;
    }
}

static bool create_render_target(void) {
    if (!g_swap_chain) return false;
    ID3D11Texture2D *back_buffer = NULL;
    HRESULT hr = g_swap_chain->GetBuffer(0, __uuidof(ID3D11Texture2D),
        reinterpret_cast<void **>(&back_buffer));
    if (FAILED(hr) || !back_buffer) return false;

    hr = g_d3d_device->CreateRenderTargetView(back_buffer, NULL, &g_render_target);
    back_buffer->Release();
    return SUCCEEDED(hr);
}

static void cleanup_d3d(void) {
    cleanup_render_target();
    if (g_swap_chain) {
        g_swap_chain->Release();
        g_swap_chain = NULL;
    }
    if (g_d3d_context) {
        g_d3d_context->Release();
        g_d3d_context = NULL;
    }
    if (g_d3d_device) {
        g_d3d_device->Release();
        g_d3d_device = NULL;
    }
}

static bool create_d3d_device(HWND hwnd) {
    DXGI_SWAP_CHAIN_DESC swap_desc = {};
    swap_desc.BufferCount = 2;
    swap_desc.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    swap_desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    swap_desc.OutputWindow = hwnd;
    swap_desc.SampleDesc.Count = 1;
    swap_desc.Windowed = TRUE;
    swap_desc.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

    D3D_FEATURE_LEVEL levels[] = {
        D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_0
    };
    D3D_FEATURE_LEVEL feature_level = D3D_FEATURE_LEVEL_10_0;
    UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
#ifdef _DEBUG
    flags |= D3D11_CREATE_DEVICE_DEBUG;
#endif

    HRESULT hr = D3D11CreateDeviceAndSwapChain(
        NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, flags,
        levels, sizeof(levels) / sizeof(levels[0]), D3D11_SDK_VERSION,
        &swap_desc, &g_swap_chain, &g_d3d_device, &feature_level,
        &g_d3d_context);
    if (FAILED(hr)) {
        cleanup_d3d();
        hr = D3D11CreateDeviceAndSwapChain(
            NULL, D3D_DRIVER_TYPE_WARP, NULL, flags,
            levels, sizeof(levels) / sizeof(levels[0]), D3D11_SDK_VERSION,
            &swap_desc, &g_swap_chain, &g_d3d_device, &feature_level,
            &g_d3d_context);
    }
    return SUCCEEDED(hr) && create_render_target();
}

static void setup_imgui_style(void) {
    ImGuiStyle &style = ImGui::GetStyle();
    style.WindowPadding = ImVec2(0.0f, 0.0f);
    style.FramePadding = ImVec2(14.0f, 8.0f);
    style.CellPadding = ImVec2(12.0f, 10.0f);
    style.ItemSpacing = ImVec2(12.0f, 10.0f);
    style.ItemInnerSpacing = ImVec2(8.0f, 6.0f);
    style.ScrollbarSize = 10.0f;
    style.GrabMinSize = 10.0f;
    style.WindowBorderSize = 0.0f;
    style.ChildBorderSize = 0.0f;
    style.PopupBorderSize = 1.0f;
    style.FrameBorderSize = 0.0f;
    style.WindowRounding = 0.0f;
    style.ChildRounding = 16.0f;   /* rounded.xl cards */
    style.FrameRounding = 999.0f;  /* pill signature */
    style.PopupRounding = 16.0f;
    style.ScrollbarRounding = 999.0f;
    style.GrabRounding = 999.0f;

    ImVec4 *colors = style.Colors;
    colors[ImGuiCol_Text] = kText;
    colors[ImGuiCol_TextDisabled] = kMuted;
    colors[ImGuiCol_WindowBg] = kCanvas;
    colors[ImGuiCol_ChildBg] = kCanvas;
    colors[ImGuiCol_PopupBg] = kCanvas;
    colors[ImGuiCol_Border] = kBorder;
    colors[ImGuiCol_FrameBg] = kCanvasSoft;
    colors[ImGuiCol_FrameBgHovered] = kBorder;
    colors[ImGuiCol_FrameBgActive] = kBorder;
    colors[ImGuiCol_TitleBg] = kCanvas;
    colors[ImGuiCol_TitleBgActive] = kCanvas;
    colors[ImGuiCol_MenuBarBg] = kCanvas;
    colors[ImGuiCol_ScrollbarBg] = kCanvas;
    colors[ImGuiCol_ScrollbarGrab] = kBorder;
    colors[ImGuiCol_ScrollbarGrabHovered] = kMuted;
    colors[ImGuiCol_ScrollbarGrabActive] = kPrimary;
    colors[ImGuiCol_CheckMark] = kPrimary;
    colors[ImGuiCol_SliderGrab] = kPrimary;
    colors[ImGuiCol_SliderGrabActive] = kBlackElevated;
    colors[ImGuiCol_Button] = kCanvasSoft;
    colors[ImGuiCol_ButtonHovered] = kBorder;
    colors[ImGuiCol_ButtonActive] = ImVec4(0.82f, 0.82f, 0.82f, 1.0f);
    colors[ImGuiCol_Header] = kCanvasSoft;
    colors[ImGuiCol_HeaderHovered] = kBorder;
    colors[ImGuiCol_HeaderActive] = kBorder;
    colors[ImGuiCol_Separator] = kBorder;
    colors[ImGuiCol_SeparatorHovered] = kMuted;
    colors[ImGuiCol_SeparatorActive] = kPrimary;
}

static void center_window(HWND hwnd, int width, int height) {
    HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info = {};
    info.cbSize = sizeof(info);
    if (!GetMonitorInfoW(monitor, &info)) return;
    int x = info.rcWork.left + (info.rcWork.right - info.rcWork.left - width) / 2;
    int y = info.rcWork.top + (info.rcWork.bottom - info.rcWork.top - height) / 2;
    SetWindowPos(hwnd, NULL, x, y, width, height,
        SWP_NOZORDER | SWP_NOACTIVATE);
}

static void set_window_light_mode(HWND hwnd) {
    BOOL enabled = FALSE;
    DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE,
        &enabled, sizeof(enabled));
}

static void draw_pill(const char *label, const ImVec4 &bg, const ImVec4 &fg,
    const ImVec2 &size) {
    ImGui::PushStyleColor(ImGuiCol_Button, bg);
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, bg);
    ImGui::PushStyleColor(ImGuiCol_ButtonActive, bg);
    ImGui::PushStyleColor(ImGuiCol_Text, fg);
    ImGui::PushStyleVar(ImGuiStyleVar_FrameRounding, 999.0f);
    ImGui::Button(label, size);
    ImGui::PopStyleVar();
    ImGui::PopStyleColor(4);
}

static bool draw_primary_button(const char *label, const ImVec2 &size) {
    ImGui::PushStyleColor(ImGuiCol_Button, kPrimary);
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, kBlackElevated);
    ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0.08f, 0.08f, 0.08f, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_Text, kOnPrimary);
    ImGui::PushStyleVar(ImGuiStyleVar_FrameRounding, 999.0f);
    bool pressed = ImGui::Button(label, size);
    ImGui::PopStyleVar();
    ImGui::PopStyleColor(4);
    return pressed;
}

static bool draw_subtle_button(const char *label, const ImVec2 &size) {
    ImGui::PushStyleColor(ImGuiCol_Button, kCanvasSoft);
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, kBorder);
    ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0.82f, 0.82f, 0.82f, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_Text, kText);
    ImGui::PushStyleVar(ImGuiStyleVar_FrameRounding, 999.0f);
    bool pressed = ImGui::Button(label, size);
    ImGui::PopStyleVar();
    ImGui::PopStyleColor(4);
    return pressed;
}

static bool draw_danger_button(const char *label, const ImVec2 &size) {
    ImGui::PushStyleColor(ImGuiCol_Button, kDangerSoft);
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0.98f, 0.82f, 0.80f, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0.96f, 0.74f, 0.72f, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_Text, kDanger);
    ImGui::PushStyleVar(ImGuiStyleVar_FrameRounding, 999.0f);
    bool pressed = ImGui::Button(label, size);
    ImGui::PopStyleVar();
    ImGui::PopStyleColor(4);
    return pressed;
}

static void draw_badge(const char *text, const ImVec4 &background,
    const ImVec4 &foreground) {
    ImGui::PushStyleColor(ImGuiCol_Button, background);
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, background);
    ImGui::PushStyleColor(ImGuiCol_ButtonActive, background);
    ImGui::PushStyleColor(ImGuiCol_Text, foreground);
    ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(10.0f, 4.0f));
    ImGui::PushStyleVar(ImGuiStyleVar_FrameRounding, 999.0f);
    ImGui::SmallButton(text);
    ImGui::PopStyleVar(2);
    ImGui::PopStyleColor(4);
}

static int count_pinned_items(void) {
    int count = 0;
    for (int i = 0; i < g_cfg.count; i++)
        if (g_cfg.items[i].pinned) count++;
    return count;
}

static void draw_section_label(const char *label) {
    ImGui::TextColored(kBody, "%s", label);
}

static void draw_item_row(int index) {
    PinItem *item = &g_cfg.items[index];
    char name[CFG_MAX_NAME * 3];
    char meta[96];
    wide_to_utf8(item->name, name, sizeof(name));

    const char *type = item->type == ITEM_TYPE_LUA ? "Lua" : "URL";
    std::snprintf(meta, sizeof(meta), "%s  ·  %lus%s", type,
        static_cast<unsigned long>(item->interval_ms / 1000),
        item->pinned ? "  ·  live" : "");

    ImGui::PushID(index);
    ImVec2 row_pos = ImGui::GetCursorScreenPos();
    bool selected = g_selected_item == index;
    if (ImGui::Selectable("##item", selected, ImGuiSelectableFlags_None,
            ImVec2(0.0f, 72.0f))) {
        g_selected_item = index;
    }
    if (ImGui::IsItemHovered() && ImGui::IsMouseDoubleClicked(ImGuiMouseButton_Left)) {
        show_edit_dialog(g_ui_hwnd, index);
        modern_ui_refresh();
    }

    ImDrawList *draw_list = ImGui::GetWindowDrawList();
    float row_width = ImGui::GetContentRegionAvail().x;
    ImVec2 row_end(row_pos.x + row_width, row_pos.y + 72.0f);

    /* Soft selected fill */
    if (selected) {
        draw_list->AddRectFilled(
            ImVec2(row_pos.x + 10.0f, row_pos.y + 4.0f),
            ImVec2(row_end.x - 10.0f, row_end.y - 4.0f),
            color_u32(kCanvasSoft), 12.0f);
    }

    /* Left accent bar for pinned items */
    if (item->pinned) {
        draw_list->AddRectFilled(
            ImVec2(row_pos.x + 14.0f, row_pos.y + 18.0f),
            ImVec2(row_pos.x + 17.0f, row_pos.y + 54.0f),
            color_u32(kPrimary), 2.0f);
    }

    draw_list->PushClipRect(row_pos, row_end, true);
    draw_list->AddText(ImVec2(row_pos.x + 28.0f, row_pos.y + 16.0f),
        color_u32(kText), name);
    draw_list->AddText(ImVec2(row_pos.x + 28.0f, row_pos.y + 42.0f),
        color_u32(item->pinned ? kText : kBody), meta);
    draw_list->PopClipRect();
    draw_list->AddLine(
        ImVec2(row_pos.x + 28.0f, row_pos.y + 71.0f),
        ImVec2(row_end.x - 16.0f, row_pos.y + 71.0f),
        color_u32(kBorder));
    ImGui::PopID();
}

static void rebuild_bars(void) {
    bars_destroy_all();
    bars_create_all();
    modern_ui_refresh();
}

static void open_add_dialog(void) {
    int old_count = g_cfg.count;
    show_edit_dialog(g_ui_hwnd, -1);
    if (g_cfg.count > old_count) g_selected_item = g_cfg.count - 1;
    modern_ui_refresh();
}

static void open_edit_dialog(void) {
    if (g_selected_item < 0 || g_selected_item >= g_cfg.count) return;
    show_edit_dialog(g_ui_hwnd, g_selected_item);
    modern_ui_refresh();
}

static void delete_selected_item(void) {
    if (g_selected_item < 0 || g_selected_item >= g_cfg.count) return;

    WCHAR prompt[CFG_MAX_NAME + 64];
    wsprintfW(prompt, L"Delete item \"%s\"?", g_cfg.items[g_selected_item].name);
    if (MessageBoxW(g_ui_hwnd, prompt, L"TaskPin",
            MB_OKCANCEL | MB_ICONWARNING | MB_DEFBUTTON2) != IDOK) {
        return;
    }

    BOOL was_pinned = g_cfg.items[g_selected_item].pinned;
    for (int i = g_selected_item; i < g_cfg.count - 1; i++)
        g_cfg.items[i] = g_cfg.items[i + 1];
    g_cfg.count--;
    if (g_selected_item >= g_cfg.count) g_selected_item = g_cfg.count - 1;
    config_save(&g_cfg);
    if (was_pinned) rebuild_bars();
    modern_ui_refresh();
}

static void toggle_pin_selected(void) {
    if (g_selected_item < 0 || g_selected_item >= g_cfg.count) return;
    g_cfg.items[g_selected_item].pinned = !g_cfg.items[g_selected_item].pinned;
    config_save(&g_cfg);
    rebuild_bars();
}

static void draw_taskbar_preview(const PinItem *item, const char *name) {
    ImGui::PushStyleColor(ImGuiCol_ChildBg, kCanvasSoft);
    ImGui::PushStyleVar(ImGuiStyleVar_ChildRounding, 16.0f);
    ImGui::BeginChild("preview", ImVec2(0.0f, 100.0f), true,
        ImGuiWindowFlags_NoScrollbar);
    draw_section_label("TASKBAR PREVIEW");

    ImVec2 child_pos = ImGui::GetWindowPos();
    float rail_width = ImGui::GetWindowWidth() - 40.0f;
    ImVec2 rail_pos(child_pos.x + 20.0f, child_pos.y + 42.0f);
    ImVec2 rail_end(rail_pos.x + rail_width, rail_pos.y + 40.0f);
    ImDrawList *draw_list = ImGui::GetWindowDrawList();
    draw_list->AddRectFilled(rail_pos, rail_end, color_u32(kCanvas), 12.0f);
    draw_list->AddRect(rail_pos, rail_end, color_u32(kBorder), 12.0f);
    draw_list->AddCircleFilled(
        ImVec2(rail_pos.x + 16.0f, rail_pos.y + 20.0f),
        4.0f, color_u32(item->pinned ? kPrimary : kMuted));

    const char *state = item->pinned ? "Live" : "Idle";
    ImVec2 state_size = ImGui::CalcTextSize(state);
    float state_x = rail_end.x - 16.0f - state_size.x;
    draw_list->AddText(ImVec2(state_x, rail_pos.y + 12.0f),
        color_u32(item->pinned ? kText : kBody), state);
    draw_list->PushClipRect(
        ImVec2(rail_pos.x + 30.0f, rail_pos.y),
        ImVec2(state_x - 12.0f, rail_end.y), true);
    draw_list->AddText(ImVec2(rail_pos.x + 30.0f, rail_pos.y + 12.0f),
        color_u32(kText), name);
    draw_list->PopClipRect();
    ImGui::EndChild();
    ImGui::PopStyleVar();
    ImGui::PopStyleColor();
}

static void draw_header(void) {
    ImGui::PushStyleColor(ImGuiCol_ChildBg, kCanvas);
    ImGui::BeginChild("header", ImVec2(0.0f, 92.0f), false,
        ImGuiWindowFlags_NoScrollbar);
    ImDrawList *draw_list = ImGui::GetWindowDrawList();
    ImVec2 mark(ImGui::GetWindowPos().x + 28.0f, ImGui::GetWindowPos().y + 26.0f);

    /* Black TP mark — brand monogram */
    draw_list->AddRectFilled(mark, ImVec2(mark.x + 36.0f, mark.y + 36.0f),
        color_u32(kPrimary), 8.0f);
    draw_list->AddText(ImVec2(mark.x + 7.0f, mark.y + 9.0f),
        color_u32(kOnPrimary), "TP");

    ImGui::SetCursorPos(ImVec2(80.0f, 24.0f));
    ImGui::TextColored(kText, "TaskPin");
    ImGui::SetCursorPos(ImVec2(80.0f, 50.0f));
    ImGui::TextColored(kBody, "Pin live signals  ·  v%s", TASKPIN_VERSION);

    float action_width = 360.0f;
    float action_x = ImGui::GetWindowWidth() - action_width - 28.0f;
    if (action_x < 330.0f) action_x = 330.0f;
    ImGui::SetCursorPos(ImVec2(action_x, 28.0f));
    if (draw_subtle_button("Market", ImVec2(96.0f, 38.0f)))
        show_market_dialog(g_ui_hwnd);
    ImGui::SameLine(0.0f, 8.0f);
    if (draw_subtle_button("Settings", ImVec2(104.0f, 38.0f)))
        show_settings_dialog(g_ui_hwnd);
    ImGui::SameLine(0.0f, 8.0f);
    if (draw_primary_button("+  New signal", ImVec2(140.0f, 38.0f)))
        open_add_dialog();

    /* Bottom hairline */
    ImVec2 hp = ImGui::GetWindowPos();
    float hw = ImGui::GetWindowWidth();
    float hh = ImGui::GetWindowHeight();
    draw_list->AddLine(
        ImVec2(hp.x, hp.y + hh - 1.0f),
        ImVec2(hp.x + hw, hp.y + hh - 1.0f),
        color_u32(kBorder));

    ImGui::EndChild();
    ImGui::PopStyleColor();
}

static void draw_sidebar(void) {
    ImGui::PushStyleColor(ImGuiCol_ChildBg, kCanvas);
    ImGui::PushStyleVar(ImGuiStyleVar_ChildRounding, 0.0f);
    ImGui::BeginChild("sidebar", ImVec2(310.0f, 0.0f), false);

    ImGui::SetCursorPos(ImVec2(24.0f, 22.0f));
    ImGui::TextColored(kText, "Signals");
    ImGui::SameLine(ImGui::GetWindowWidth() - 56.0f);
    char count_buf[8];
    std::snprintf(count_buf, sizeof(count_buf), "%d", g_cfg.count);
    draw_pill(count_buf, kCanvasSoft, kText, ImVec2(36.0f, 24.0f));

    ImGui::SetCursorPos(ImVec2(24.0f, 56.0f));
    draw_section_label("ALL ITEMS");
    ImGui::SameLine(0.0f, 10.0f);
    char live_buf[24];
    std::snprintf(live_buf, sizeof(live_buf), "%d live", count_pinned_items());
    ImGui::TextColored(kBody, "%s", live_buf);

    if (g_cfg.count == 0) {
        ImGui::SetCursorPos(ImVec2(24.0f, 110.0f));
        ImGui::TextColored(kText, "No signals yet");
        ImGui::SetCursorPos(ImVec2(24.0f, 136.0f));
        ImGui::TextColored(kBody, "Add a Lua script or URL endpoint.");
        ImGui::SetCursorPos(ImVec2(24.0f, 176.0f));
        if (draw_primary_button("+  New signal", ImVec2(-24.0f, 40.0f)))
            open_add_dialog();
    } else {
        ImGui::SetCursorPosY(86.0f);
        for (int i = 0; i < g_cfg.count; i++) draw_item_row(i);
    }

    /* Right hairline */
    ImDrawList *draw_list = ImGui::GetWindowDrawList();
    ImVec2 sp = ImGui::GetWindowPos();
    float sh = ImGui::GetWindowHeight();
    float sw = ImGui::GetWindowWidth();
    draw_list->AddLine(
        ImVec2(sp.x + sw - 1.0f, sp.y),
        ImVec2(sp.x + sw - 1.0f, sp.y + sh),
        color_u32(kBorder));

    ImGui::EndChild();
    ImGui::PopStyleVar();
    ImGui::PopStyleColor();
}

static void draw_stat(const char *label, const char *value) {
    ImGui::TableNextColumn();
    ImGui::TextColored(kBody, "%s", label);
    ImGui::TextColored(kText, "%s", value);
}

static void draw_detail(void) {
    ImGui::PushStyleColor(ImGuiCol_ChildBg, kCanvas);
    ImGui::BeginChild("detail", ImVec2(0.0f, 0.0f), false);
    ImGui::SetCursorPos(ImVec2(32.0f, 26.0f));

    if (g_selected_item < 0 || g_selected_item >= g_cfg.count) {
        draw_section_label("WORKSPACE");
        ImGui::Spacing();
        ImGui::TextColored(kText, "No signal selected");
        ImGui::TextColored(kBody, "Create a signal to populate this desk.");
        ImGui::Spacing();
        if (draw_primary_button("+  New signal", ImVec2(156.0f, 40.0f)))
            open_add_dialog();
        ImGui::EndChild();
        ImGui::PopStyleColor();
        return;
    }

    PinItem *item = &g_cfg.items[g_selected_item];
    char name[CFG_MAX_NAME * 3];
    char source[CFG_MAX_URL * 3];
    char interval[64];
    char position[64];
    char width[64];
    wide_to_utf8(item->name, name, sizeof(name));
    wide_to_utf8(item->type == ITEM_TYPE_LUA ? item->lua_path : item->url,
        source, sizeof(source));
    std::snprintf(interval, sizeof(interval), "%lu ms",
        static_cast<unsigned long>(item->interval_ms));
    std::snprintf(position, sizeof(position), "%d, %d", item->bar_x, item->bar_y);
    std::snprintf(width, sizeof(width), "%d px",
        item->bar_width > 0 ? item->bar_width : g_cfg.width);

    draw_section_label("SELECTED SIGNAL");
    ImGui::Spacing();
    ImGui::TextColored(kText, "%s", name);
    ImGui::Spacing();
    draw_badge(item->type == ITEM_TYPE_LUA ? "Lua" : "URL",
        kCanvasSoft, kText);

    ImGui::Spacing();
    if (draw_subtle_button("Edit", ImVec2(84.0f, 36.0f))) open_edit_dialog();
    ImGui::SameLine(0.0f, 8.0f);
    if (item->pinned) {
        if (draw_subtle_button("Unpin", ImVec2(92.0f, 36.0f)))
            toggle_pin_selected();
    } else {
        if (draw_primary_button("Pin", ImVec2(92.0f, 36.0f)))
            toggle_pin_selected();
    }
    ImGui::SameLine(0.0f, 8.0f);
    if (draw_danger_button("Delete", ImVec2(88.0f, 36.0f)))
        delete_selected_item();

    ImGui::Dummy(ImVec2(0.0f, 22.0f));
    draw_taskbar_preview(item, name);

    ImGui::Dummy(ImVec2(0.0f, 18.0f));
    ImGui::PushStyleColor(ImGuiCol_ChildBg, item->pinned ? kPrimary : kCanvasSoft);
    ImGui::PushStyleVar(ImGuiStyleVar_ChildRounding, 16.0f);
    ImGui::BeginChild("state", ImVec2(0.0f, 72.0f), true);
    ImGui::SetCursorPos(ImVec2(20.0f, 14.0f));
    ImGui::TextColored(item->pinned ? kOnPrimary : kText,
        item->pinned ? "Live on taskbar" : "Not pinned");
    ImGui::SetCursorPos(ImVec2(20.0f, 40.0f));
    ImGui::TextColored(item->pinned ? ImVec4(0.8f, 0.8f, 0.8f, 1.0f) : kBody,
        item->pinned ? "Refreshing on schedule" : "Ready to pin");
    ImGui::EndChild();
    ImGui::PopStyleVar();
    ImGui::PopStyleColor();

    ImGui::Dummy(ImVec2(0.0f, 20.0f));
    draw_section_label("SIGNAL PROFILE");
    ImGui::Spacing();
    if (ImGui::BeginTable("stats", 2, ImGuiTableFlags_SizingStretchProp)) {
        draw_stat("Source type",
            item->type == ITEM_TYPE_LUA ? "Lua script" : "HTTP endpoint");
        draw_stat("Refresh", interval);
        draw_stat("Position", position);
        draw_stat("Bar width", width);
        ImGui::EndTable();
    }

    ImGui::Dummy(ImVec2(0.0f, 20.0f));
    draw_section_label("SOURCE");
    ImGui::PushStyleColor(ImGuiCol_ChildBg, kCanvasSoft);
    ImGui::PushStyleVar(ImGuiStyleVar_ChildRounding, 12.0f);
    ImGui::BeginChild("source", ImVec2(0.0f, 68.0f), true);
    ImGui::SetCursorPos(ImVec2(14.0f, 14.0f));
    ImGui::PushStyleColor(ImGuiCol_Text, kBody);
    ImGui::TextWrapped("%s", source);
    ImGui::PopStyleColor();
    ImGui::EndChild();
    ImGui::PopStyleVar();
    ImGui::PopStyleColor();
    ImGui::EndChild();
    ImGui::PopStyleColor();
}

static void render_ui(void) {
    if (!g_imgui_ready || !g_render_target) return;

    ImGui_ImplDX11_NewFrame();
    ImGui_ImplWin32_NewFrame();
    ImGui::NewFrame();

    ImGuiIO &io = ImGui::GetIO();
    ImGui::SetNextWindowPos(ImVec2(0.0f, 0.0f));
    ImGui::SetNextWindowSize(io.DisplaySize);
    ImGui::Begin("TaskPin", NULL,
        ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove |
        ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoBringToFrontOnFocus);

    draw_header();
    ImGui::BeginChild("body", ImVec2(0.0f, 0.0f), false);
    draw_sidebar();
    ImGui::SameLine(0.0f, 0.0f);
    draw_detail();
    ImGui::EndChild();
    ImGui::End();

    ImGui::Render();
    const float clear_color[4] = {
        kCanvas.x, kCanvas.y, kCanvas.z, kCanvas.w
    };
    g_d3d_context->OMSetRenderTargets(1, &g_render_target, NULL);
    g_d3d_context->ClearRenderTargetView(g_render_target, clear_color);
    ImGui_ImplDX11_RenderDrawData(ImGui::GetDrawData());
    g_swap_chain->Present(1, 0);
}

static LRESULT CALLBACK modern_ui_wnd_proc(HWND hwnd, UINT msg,
    WPARAM wp, LPARAM lp) {
    if (g_imgui_ready && ImGui_ImplWin32_WndProcHandler(hwnd, msg, wp, lp))
        return 1;

    switch (msg) {
    case WM_SIZE:
        if (g_swap_chain && wp != SIZE_MINIMIZED &&
            LOWORD(lp) > 0 && HIWORD(lp) > 0) {
            cleanup_render_target();
            g_swap_chain->ResizeBuffers(0, LOWORD(lp), HIWORD(lp),
                DXGI_FORMAT_UNKNOWN, 0);
            create_render_target();
        }
        return 0;
    case WM_ERASEBKGND:
        return 1;
    case WM_GETMINMAXINFO: {
        MINMAXINFO *limits = reinterpret_cast<MINMAXINFO *>(lp);
        limits->ptMinTrackSize.x = 920;
        limits->ptMinTrackSize.y = 620;
        return 0;
    }
    case WM_TIMER:
        if (wp == IDT_UI_FRAME) {
            InvalidateRect(hwnd, NULL, FALSE);
            return 0;
        }
        break;
    case WM_PAINT: {
        PAINTSTRUCT ps;
        BeginPaint(hwnd, &ps);
        render_ui();
        EndPaint(hwnd, &ps);
        return 0;
    }
    case WM_CLOSE:
        KillTimer(hwnd, IDT_UI_FRAME);
        ShowWindow(hwnd, SW_HIDE);
        return 0;
    case WM_DESTROY:
        KillTimer(hwnd, IDT_UI_FRAME);
        if (g_imgui_ready) {
            ImGui_ImplDX11_Shutdown();
            ImGui_ImplWin32_Shutdown();
            ImGui::DestroyContext();
            g_imgui_ready = false;
        }
        cleanup_d3d();
        g_ui_hwnd = NULL;
        g_main_hwnd = NULL;
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

static bool register_ui_class(void) {
    if (g_ui_class_registered) return true;
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.style = CS_OWNDC;
    wc.lpfnWndProc = modern_ui_wnd_proc;
    wc.hInstance = g_hinst;
    wc.hCursor = LoadCursorW(NULL, IDC_ARROW);
    wc.hIcon = LoadIconW(NULL, IDI_APPLICATION);
    wc.hIconSm = wc.hIcon;
    wc.lpszClassName = L"TaskPinModernClass";
    if (!RegisterClassExW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
        return false;
    g_ui_class_registered = true;
    return true;
}

static bool create_ui_window(void) {
    if (!register_ui_class()) return false;
    ImGui_ImplWin32_EnableDpiAwareness();

    g_ui_hwnd = CreateWindowExW(
        WS_EX_APPWINDOW,
        L"TaskPinModernClass", L"TaskPin",
        WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN | WS_CLIPSIBLINGS,
        CW_USEDEFAULT, CW_USEDEFAULT, 1160, 760,
        NULL, NULL, g_hinst, NULL);
    if (!g_ui_hwnd) return false;
    g_main_hwnd = g_ui_hwnd;
    center_window(g_ui_hwnd, 1160, 760);
    set_window_light_mode(g_ui_hwnd);

    if (!create_d3d_device(g_ui_hwnd)) {
        cleanup_d3d();
        DestroyWindow(g_ui_hwnd);
        g_ui_hwnd = NULL;
        g_main_hwnd = NULL;
        return false;
    }

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO &io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
    if (!io.Fonts->AddFontFromFileTTF(
            "C:\\Windows\\Fonts\\segoeui.ttf", 16.0f, NULL,
            io.Fonts->GetGlyphRangesDefault())) {
        io.Fonts->AddFontDefault();
    }
    setup_imgui_style();
    ImGui_ImplWin32_Init(g_ui_hwnd);
    ImGui_ImplDX11_Init(g_d3d_device, g_d3d_context);
    g_imgui_ready = true;
    return true;
}

extern "C" void modern_ui_show(void) {
    if (!g_ui_hwnd && !create_ui_window()) {
        MessageBoxW(NULL, L"Unable to initialize the modern UI.", L"TaskPin",
            MB_OK | MB_ICONERROR);
        return;
    }
    if (g_selected_item >= g_cfg.count) g_selected_item = g_cfg.count - 1;
    ShowWindow(g_ui_hwnd, SW_SHOW);
    SetForegroundWindow(g_ui_hwnd);
    SetTimer(g_ui_hwnd, IDT_UI_FRAME, 16, NULL);
    InvalidateRect(g_ui_hwnd, NULL, FALSE);
}

extern "C" void modern_ui_refresh(void) {
    if (g_selected_item >= g_cfg.count) g_selected_item = g_cfg.count - 1;
    if (g_ui_hwnd) InvalidateRect(g_ui_hwnd, NULL, FALSE);
}

extern "C" void modern_ui_shutdown(void) {
    if (g_ui_hwnd) {
        DestroyWindow(g_ui_hwnd);
        g_ui_hwnd = NULL;
        g_main_hwnd = NULL;
    } else if (g_imgui_ready) {
        ImGui_ImplDX11_Shutdown();
        ImGui_ImplWin32_Shutdown();
        ImGui::DestroyContext();
        g_imgui_ready = false;
        cleanup_d3d();
    }
}
