/*
 * Main management list: classic table + bottom action bar.
 * Settings / Market / Edit open as independent Win32 windows.
 *
 * Layout (per ui_common.h contract):
 *   [ table body, full width ]
 *   [ footer: Add Delete Pin | Settings Market     vX.Y ]
 */
extern "C" {
#include "ui.h"
}

#include "ui_views.h"
#include "ui_common.h"

/* ---- static state for confirm modal ---- */
static bool s_confirm_open = false;

enum MainAction {
    MAIN_ACT_NONE = 0,
    MAIN_ACT_ADD,
    MAIN_ACT_EDIT,
    MAIN_ACT_DELETE,
    MAIN_ACT_PIN,
    MAIN_ACT_SETTINGS,
    MAIN_ACT_MARKET
};

static MainAction g_act = MAIN_ACT_NONE;
static int g_act_edit = -1;
static bool g_confirm_delete = false;
static bool g_need_rebuild_bars = false;

/* Modal open deferred until after Present() so the main frame is closed. */
static MainAction g_open_act = MAIN_ACT_NONE;
static int g_open_edit = -1;
static int *g_open_sel = NULL;

static void request(MainAction act, int edit_index) {
    if (g_act != MAIN_ACT_NONE) return;
    g_act = act;
    g_act_edit = edit_index;
}

static void rebuild_bars(void) {
    bars_destroy_all();
    bars_create_all();
    modern_ui_refresh();
}

static void draw_table(int *selected_item) {
    float table_h = ui_body_height();

    if (!ImGui::BeginTable("items", 8, ui_table_flags(), ImVec2(0.0f, table_h)))
        return;

    ImGui::TableSetupScrollFreeze(0, 1);
    ImGui::TableSetupColumn(tr8("main.col_name"),     ImGuiTableColumnFlags_WidthFixed, 100.0f);
    ImGui::TableSetupColumn(tr8("main.col_type"),     ImGuiTableColumnFlags_WidthFixed, 50.0f);
    ImGui::TableSetupColumn(tr8("main.col_source"),   ImGuiTableColumnFlags_WidthStretch);
    ImGui::TableSetupColumn(tr8("main.col_interval"), ImGuiTableColumnFlags_WidthFixed, 80.0f);
    ImGui::TableSetupColumn(tr8("main.col_pin"),      ImGuiTableColumnFlags_WidthFixed, 40.0f);
    ImGui::TableSetupColumn(tr8("main.col_xy"),       ImGuiTableColumnFlags_WidthFixed, 70.0f);
    ImGui::TableSetupColumn(tr8("main.col_width"),    ImGuiTableColumnFlags_WidthFixed, 44.0f);
    ImGui::TableSetupColumn(tr8("main.col_bg"),       ImGuiTableColumnFlags_WidthFixed, 72.0f);
    ImGui::TableHeadersRow();

    for (int i = 0; i < g_cfg.count; i++) {
        PinItem *item = &g_cfg.items[i];
        char name[CFG_MAX_NAME * 3];
        char source[CFG_MAX_URL * 3];
        char interval[32];
        char xy[32];
        char width[16];
        char bg[16];

        ui_wide_to_utf8(item->name, name, sizeof(name));
        ui_wide_to_utf8(item->type == ITEM_TYPE_LUA ? item->lua_path : item->url,
            source, sizeof(source));
        std::snprintf(interval, sizeof(interval), "%u", (unsigned)item->interval_ms);
        std::snprintf(xy, sizeof(xy), "%d,%d", item->bar_x, item->bar_y);
        std::snprintf(width, sizeof(width), "%d", item->bar_width);
        std::snprintf(bg, sizeof(bg), "%08X", (unsigned)item->bar_bg_color);

        ImGui::TableNextRow();
        ImGui::PushID(i);
        ImGui::TableSetColumnIndex(0);
        bool selected = (*selected_item == i);
        if (ImGui::Selectable(name, selected,
                ImGuiSelectableFlags_SpanAllColumns | ImGuiSelectableFlags_AllowOverlap))
            *selected_item = i;
        if (ImGui::IsItemHovered() &&
            ImGui::IsMouseDoubleClicked(ImGuiMouseButton_Left))
            request(MAIN_ACT_EDIT, i);

        ImGui::TableSetColumnIndex(1);
        ImGui::TextUnformatted(item->type == ITEM_TYPE_LUA
            ? tr8("edit.type_lua") : tr8("edit.type_url"));
        ImGui::TableSetColumnIndex(2);
        ImGui::TextUnformatted(source[0] ? source : "—");
        ImGui::TableSetColumnIndex(3);
        ImGui::TextUnformatted(interval);
        ImGui::TableSetColumnIndex(4);
        ImGui::TextUnformatted(item->pinned ? "Y" : "");
        ImGui::TableSetColumnIndex(5);
        ImGui::TextUnformatted(xy);
        ImGui::TableSetColumnIndex(6);
        ImGui::TextUnformatted(width);
        ImGui::TableSetColumnIndex(7);
        ImGui::TextUnformatted(bg);
        ImGui::PopID();
    }
    ImGui::EndTable();
}

static void draw_footer(int *selected_item) {
    ui_footer_begin("main_footer");

    if (ui_btn(tr8("main.add")))
        request(MAIN_ACT_ADD, -1);
    ImGui::SameLine(0.0f, UI_GAP);
    if (ui_btn(tr8("main.delete")))
        request(MAIN_ACT_DELETE, -1);
    ImGui::SameLine(0.0f, UI_GAP);

    const char *pin_label = tr8("main.pin");
    if (*selected_item >= 0 && *selected_item < g_cfg.count &&
        g_cfg.items[*selected_item].pinned)
        pin_label = tr8("main.unpin");
    if (ui_btn(pin_label, UI_BTN_W_WIDE))
        request(MAIN_ACT_PIN, -1);
    ImGui::SameLine(0.0f, UI_GAP_LG);
    if (ui_btn(tr8("main.settings"), UI_BTN_W_WIDE))
        request(MAIN_ACT_SETTINGS, -1);
    ImGui::SameLine(0.0f, UI_GAP);
    if (ui_btn(tr8("main.market")))
        request(MAIN_ACT_MARKET, -1);

    char ver[32];
    std::snprintf(ver, sizeof(ver), "v%s", TASKPIN_VERSION);
    ui_footer_status(ver);

    ui_footer_end();
}

void ui_main_view_draw(int *selected_item) {
    draw_table(selected_item);
    draw_footer(selected_item);

    /* Convert click → deferred open / local flags (no modal yet). */
    if (g_act != MAIN_ACT_NONE) {
        MainAction act = g_act;
        int edit = g_act_edit;
        g_act = MAIN_ACT_NONE;
        g_act_edit = -1;

        switch (act) {
        case MAIN_ACT_ADD:
        case MAIN_ACT_EDIT:
        case MAIN_ACT_SETTINGS:
        case MAIN_ACT_MARKET:
            if (g_open_act == MAIN_ACT_NONE) {
                g_open_act = act;
                g_open_edit = edit;
                g_open_sel = selected_item;
            }
            break;
        case MAIN_ACT_DELETE:
            if (*selected_item >= 0 && *selected_item < g_cfg.count)
                g_confirm_delete = true;
            break;
        case MAIN_ACT_PIN:
            if (*selected_item >= 0 && *selected_item < g_cfg.count) {
                g_cfg.items[*selected_item].pinned =
                    !g_cfg.items[*selected_item].pinned;
                config_save(&g_cfg);
                g_need_rebuild_bars = true;
            }
            break;
        default:
            break;
        }
    }

    if (g_confirm_delete) {
        s_confirm_open = true;
        g_confirm_delete = false;
    }
    {
        char name[CFG_MAX_NAME * 3] = "";
        if (*selected_item >= 0 && *selected_item < g_cfg.count) {
            PinItem *it = &g_cfg.items[*selected_item];
            ui_wide_to_utf8(it->name, name, sizeof(name));
            if (!name[0]) {
                WCHAR *src = it->type == ITEM_TYPE_LUA ? it->lua_path : it->url;
                if (src[0]) {
                    WCHAR *slash = wcsrchr(src, L'\\');
                    if (!slash) slash = wcsrchr(src, L'/');
                    ui_wide_to_utf8(slash ? slash + 1 : src, name, sizeof(name));
                }
            }
        }
        int r = Theme::ConfirmModal(tr8("main.delete"),
            tr8("confirm.delete_desc"), name[0] ? name : NULL, &s_confirm_open);
        if (r == 1) {
            if (*selected_item >= 0 && *selected_item < g_cfg.count) {
                BOOL was_pinned = g_cfg.items[*selected_item].pinned;
                for (int i = *selected_item; i < g_cfg.count - 1; i++)
                    g_cfg.items[i] = g_cfg.items[i + 1];
                g_cfg.count--;
                if (*selected_item >= g_cfg.count)
                    *selected_item = g_cfg.count - 1;
                config_save(&g_cfg);
                if (was_pinned) g_need_rebuild_bars = true;
            }
        }
    }
}

void ui_main_process_deferred(void) {
    if (g_need_rebuild_bars) {
        g_need_rebuild_bars = false;
        rebuild_bars();
    }

    if (g_open_act == MAIN_ACT_NONE) return;

    MainAction act = g_open_act;
    int edit = g_open_edit;
    int *sel = g_open_sel;
    g_open_act = MAIN_ACT_NONE;
    g_open_edit = -1;
    g_open_sel = NULL;

    UiWindow *host = ui_host_window();
    HWND parent = host ? host->hwnd : g_main_hwnd;

    switch (act) {
    case MAIN_ACT_ADD:
        ui_edit_show(parent, host, -1, sel);
        break;
    case MAIN_ACT_EDIT:
        ui_edit_show(parent, host, edit, sel);
        break;
    case MAIN_ACT_SETTINGS:
        ui_settings_show(parent, host);
        break;
    case MAIN_ACT_MARKET:
        ui_market_show(parent, host);
        break;
    default:
        break;
    }
}
