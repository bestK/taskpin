/*
 * Settings — independent Win32 modal window.
 *
 * Layout:
 *   [ form fields, label column UI_LABEL_W_WIDE ]
 *   [ checkboxes ]
 *   [ centered OK / Cancel ]
 */
extern "C" {
#include "ui.h"
}

#include "ui_views.h"
#include "ui_window.h"
#include "ui_common.h"

struct SettingsState {
    int  font_size;
    char font_color[16];
    char bg_color[16];
    int  width;
    int  pos_x;
    int  pos_y;
    bool autostart;
    bool scroll;
};

static bool registry_autostart_enabled(void) {
    HKEY hk;
    bool enabled = false;
    if (RegOpenKeyExW(HKEY_CURRENT_USER,
            L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
            0, KEY_READ, &hk) == ERROR_SUCCESS) {
        if (RegQueryValueExW(hk, L"TaskPin", NULL, NULL, NULL, NULL) == ERROR_SUCCESS)
            enabled = true;
        RegCloseKey(hk);
    }
    return enabled;
}

static void set_registry_autostart(bool want) {
    HKEY hk;
    if (RegOpenKeyExW(HKEY_CURRENT_USER,
            L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
            0, KEY_SET_VALUE, &hk) != ERROR_SUCCESS)
        return;
    if (want) {
        WCHAR exe_path[MAX_PATH];
        GetModuleFileNameW(NULL, exe_path, MAX_PATH);
        RegSetValueExW(hk, L"TaskPin", 0, REG_SZ,
            (BYTE *)exe_path, (DWORD)((lstrlenW(exe_path) + 1) * sizeof(WCHAR)));
    } else {
        RegDeleteValueW(hk, L"TaskPin");
    }
    RegCloseKey(hk);
}

static void apply_settings(SettingsState *s) {
    if (s->font_size < 6) s->font_size = 6;
    if (s->font_size > 72) s->font_size = 72;
    if (s->width < 50) s->width = 50;

    g_cfg.font_size = s->font_size;
    g_cfg.font_color = (COLORREF)strtoul(s->font_color, NULL, 16);
    g_cfg.bg_color = (COLORREF)strtoul(s->bg_color, NULL, 16);
    g_cfg.width = s->width;
    g_cfg.pos_x = s->pos_x;
    g_cfg.pos_y = s->pos_y;
    g_cfg.scroll_enabled = s->scroll ? TRUE : FALSE;
    config_save(&g_cfg);
    set_registry_autostart(s->autostart);

    if (g_font) DeleteObject(g_font);
    int fh = -MulDiv(g_cfg.font_size, 96, 72);
    g_font = CreateFontW(fh, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Segoe UI");

    bars_destroy_all();
    bars_create_all();
}

static void draw_settings(UiWindow *w) {
    SettingsState *s = (SettingsState *)w->user;
    const float lw = UI_LABEL_W_WIDE;

    ui_field_int(tr8("settings.font_size"), &s->font_size, lw, 80.0f);
    ui_field_text(tr8("settings.font_color"), s->font_color, sizeof(s->font_color), lw);
    ui_field_text(tr8("settings.bg_color"), s->bg_color, sizeof(s->bg_color), lw);
    ui_field_int(tr8("settings.width"), &s->width, lw, 80.0f);
    ui_field_int(tr8("settings.pos_x"), &s->pos_x, lw, 80.0f);
    ui_field_int(tr8("settings.pos_y"), &s->pos_y, lw, 80.0f);

    ui_section_gap();
    ui_field_check(tr8("settings.auto_start"), &s->autostart);
    ui_field_check(tr8("settings.auto_scroll"), &s->scroll);

    ui_section_sep();
    int r = ui_ok_cancel(tr8("settings.ok"), tr8("settings.cancel"));
    if (r == 1) {
        apply_settings(s);
        w->accepted = true;
        w->done = true;
    } else if (r == 2) {
        w->done = true;
    }
    if (ImGui::IsKeyPressed(ImGuiKey_Escape))
        w->done = true;
}

void ui_settings_show(HWND parent, UiWindow *share_device) {
    SettingsState state = {};
    state.font_size = g_cfg.font_size;
    std::snprintf(state.font_color, sizeof(state.font_color), "%06X",
        (unsigned)(g_cfg.font_color & 0xFFFFFF));
    std::snprintf(state.bg_color, sizeof(state.bg_color), "%06X",
        (unsigned)(g_cfg.bg_color & 0xFFFFFF));
    state.width = g_cfg.width;
    state.pos_x = g_cfg.pos_x;
    state.pos_y = g_cfg.pos_y;
    state.scroll = g_cfg.scroll_enabled ? true : false;
    state.autostart = registry_autostart_enabled();

    UiWindow win = {};
    if (!ui_window_create(&win, parent, L"TaskPinSettingsClass",
            ui_title("settings.title", L"Settings"), 480, 440, share_device))
        return;
    win.user = &state;
    ui_window_run_modal(&win, parent, draw_settings);
    ui_window_destroy(&win);
}
