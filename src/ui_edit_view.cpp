/*
 * Edit / Add item — independent Win32 modal window.
 */
extern "C" {
#include "ui.h"
#include "fetcher.h"
}

#include "ui_views.h"
#include "ui_window.h"
#include "ui_common.h"
#include <cstring>
#include <cstdlib>

struct JsonTreeNode {
    char label[256];
    char path[512];
    int  child_begin;
    int  child_count;
};

enum { MAX_TREE_NODES = 2048 };

struct EditState {
    int  item_index; /* <0 add */
    int *selected_item;

    int  type;
    char name[CFG_MAX_NAME * 3];
    char url[CFG_MAX_URL * 3];
    char headers[CFG_MAX_URL * 3];
    char lua_path[CFG_MAX_PATH * 3];
    int  interval;
    char expr[CFG_MAX_EXPR * 3];
    char preview[FETCH_BUF_SIZE * 3];
    bool click_enabled;
    char click_url[CFG_MAX_URL * 3];
    int  bar_width;
    int  bar_x;
    int  bar_y;
    char bar_bg[16];

    ScriptParamDecl param_decls[CFG_MAX_PARAMS];
    char param_vals[CFG_MAX_PARAMS][CFG_MAX_PARAM_VAL * 3];
    int  param_count;

    char cached_response[FETCH_BUF_SIZE];
    JsonNode *json_root;
    JsonTreeNode tree[MAX_TREE_NODES];
    int tree_count;

    int  pending_browse; /* 1=lua, 2+=param */
    bool pending_load;
};

static void free_json(EditState *s) {
    if (s->json_root) {
        json_free(s->json_root);
        s->json_root = NULL;
    }
    s->tree_count = 0;
}

static int tree_add_node(EditState *s, const char *label, const char *path) {
    if (s->tree_count >= MAX_TREE_NODES) return -1;
    int idx = s->tree_count++;
    std::snprintf(s->tree[idx].label, sizeof(s->tree[idx].label), "%s", label);
    std::snprintf(s->tree[idx].path, sizeof(s->tree[idx].path), "%s", path);
    s->tree[idx].child_begin = 0;
    s->tree[idx].child_count = 0;
    return idx;
}

static void tree_build_children(EditState *s, JsonNode *node, const char *path_buf, int parent_idx) {
    if (!node || parent_idx < 0) return;
    if (!(node->type == JSON_OBJECT || node->type == JSON_ARRAY)) return;

    int begin = s->tree_count;
    for (JsonNode *c = node->children; c; c = c->next) {
        char label[256];
        char child_path[512];
        if (node->type == JSON_OBJECT && c->key) {
            std::snprintf(child_path, sizeof(child_path), "%s.%s", path_buf, c->key);
            char val_str[128];
            json_node_to_string(c, val_str, 128);
            std::snprintf(label, sizeof(label), "%s: %s", c->key, val_str);
        } else {
            int idx = 0;
            for (JsonNode *t = node->children; t && t != c; t = t->next) idx++;
            std::snprintf(child_path, sizeof(child_path), "%s[%d]", path_buf, idx);
            char val_str[128];
            json_node_to_string(c, val_str, 128);
            std::snprintf(label, sizeof(label), "[%d]: %s", idx, val_str);
        }
        int child_idx = tree_add_node(s, label, child_path);
        if (child_idx >= 0 && (c->type == JSON_OBJECT || c->type == JSON_ARRAY))
            tree_build_children(s, c, child_path, child_idx);
    }
    s->tree[parent_idx].child_begin = begin;
    s->tree[parent_idx].child_count = s->tree_count - begin;
}

static void rebuild_tree(EditState *s) {
    s->tree_count = 0;
    free_json(s);
    s->json_root = json_parse(s->cached_response);
    if (s->json_root) {
        int root = tree_add_node(s, "$", "$");
        tree_build_children(s, s->json_root, "$", root);
        return;
    }
    char *p = s->cached_response;
    int idx = 0;
    while (p && *p && s->tree_count < MAX_TREE_NODES) {
        char *sep = strchr(p, '|');
        char label[256];
        char path[32];
        if (sep) {
            int flen = (int)(sep - p);
            if (flen > 200) flen = 200;
            std::snprintf(label, sizeof(label), "[%d]: %.*s", idx, flen, p);
        } else {
            std::snprintf(label, sizeof(label), "[%d]: %.200s", idx, p);
        }
        std::snprintf(path, sizeof(path), "%d", idx);
        tree_add_node(s, label, path);
        p = sep ? sep + 1 : NULL;
        idx++;
    }
}

static void update_preview(EditState *s) {
    s->preview[0] = '\0';
    if (!s->cached_response[0]) return;

    WCHAR wexpr[CFG_MAX_EXPR];
    WCHAR wpreview[FETCH_BUF_SIZE];
    ui_utf8_to_wide(s->expr, wexpr, CFG_MAX_EXPR);
    wpreview[0] = L'\0';

    if (s->expr[0]) {
        ScriptResult sr;
        memset(&sr, 0, sizeof(sr));
        if (script_exec(s->expr, s->cached_response, &sr)) {
            lstrcpynW(wpreview, sr.display, FETCH_BUF_SIZE);
        } else {
            extract_fields(s->cached_response, wexpr, wpreview, FETCH_BUF_SIZE);
        }
    } else {
        MultiByteToWideChar(CP_UTF8, 0, s->cached_response, -1, wpreview, FETCH_BUF_SIZE);
    }
    ui_wide_to_utf8(wpreview, s->preview, sizeof(s->preview));
}

static void load_response(EditState *s) {
    WCHAR wurl[CFG_MAX_URL];
    WCHAR whdr[CFG_MAX_URL];
    ui_utf8_to_wide(s->url, wurl, CFG_MAX_URL);
    ui_utf8_to_wide(s->headers, whdr, CFG_MAX_URL);

    FetchContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    lstrcpynW(ctx.url, wurl, 1024);
    lstrcpynW(ctx.headers, whdr, 1024);
    fetcher_thread(&ctx);

    if (ctx.success)
        memcpy(s->cached_response, ctx.result, FETCH_BUF_SIZE);
    else
        std::snprintf(s->cached_response, sizeof(s->cached_response), "[fetch error]");

    rebuild_tree(s);
    update_preview(s);
}

static void reload_params(EditState *s) {
    WCHAR wpath[CFG_MAX_PATH];
    ui_utf8_to_wide(s->lua_path, wpath, CFG_MAX_PATH);
    memset(s->param_decls, 0, sizeof(s->param_decls));
    for (int i = 0; i < CFG_MAX_PARAMS; i++) s->param_vals[i][0] = '\0';
    s->param_count = script_parse_params(wpath, s->param_decls, CFG_MAX_PARAMS);

    if (s->item_index >= 0 && s->item_index < g_cfg.count) {
        PinItem *it = &g_cfg.items[s->item_index];
        for (int i = 0; i < s->param_count; i++) {
            WCHAR wkey[64];
            MultiByteToWideChar(CP_UTF8, 0, s->param_decls[i].key, -1, wkey, 64);
            for (int j = 0; j < it->param_count; j++) {
                if (lstrcmpW(it->params[j].key, wkey) == 0) {
                    ui_wide_to_utf8(it->params[j].value, s->param_vals[i],
                        sizeof(s->param_vals[i]));
                    break;
                }
            }
        }
    }
}

static void browse_lua(EditState *s, HWND owner) {
    WCHAR file[MAX_PATH] = {0};
    OPENFILENAMEW ofn;
    memset(&ofn, 0, sizeof(ofn));
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = owner;
    ofn.lpstrFilter = L"Lua Scripts (*.lua)\0*.lua\0All Files\0*.*\0";
    ofn.lpstrFile = file;
    ofn.nMaxFile = MAX_PATH;
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST;
    if (GetOpenFileNameW(&ofn)) {
        ui_wide_to_utf8(file, s->lua_path, sizeof(s->lua_path));
        reload_params(s);
    }
}

static void browse_param(EditState *s, HWND owner, int index) {
    WCHAR file[MAX_PATH] = {0};
    OPENFILENAMEW ofn;
    memset(&ofn, 0, sizeof(ofn));
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = owner;
    ofn.lpstrFilter = L"All Files\0*.*\0Text Files (*.txt)\0*.txt\0";
    ofn.lpstrFile = file;
    ofn.nMaxFile = MAX_PATH;
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST;
    if (GetOpenFileNameW(&ofn))
        ui_wide_to_utf8(file, s->param_vals[index], sizeof(s->param_vals[index]));
}

static void draw_json_tree_node(EditState *s, int idx) {
    if (idx < 0 || idx >= s->tree_count) return;
    JsonTreeNode *n = &s->tree[idx];
    ImGuiTreeNodeFlags flags = ImGuiTreeNodeFlags_OpenOnArrow |
        ImGuiTreeNodeFlags_SpanAvailWidth;
    if (n->child_count == 0)
        flags |= ImGuiTreeNodeFlags_Leaf | ImGuiTreeNodeFlags_NoTreePushOnOpen;

    ImGui::PushID(idx);
    bool open = ImGui::TreeNodeEx(n->label, flags);
    if (ImGui::IsItemClicked()) {
        size_t len = strlen(s->expr);
        if (len + strlen(n->path) + 1 < sizeof(s->expr)) {
            std::snprintf(s->expr + len, sizeof(s->expr) - len, "%s", n->path);
            update_preview(s);
        }
    }
    if (open && n->child_count > 0) {
        for (int i = 0; i < n->child_count; i++)
            draw_json_tree_node(s, n->child_begin + i);
        ImGui::TreePop();
    }
    ImGui::PopID();
}

static bool apply_item(EditState *s) {
    PinItem *it = NULL;
    if (s->item_index >= 0) {
        it = &g_cfg.items[s->item_index];
    } else {
        if (g_cfg.count >= CFG_MAX_ITEMS) return false;
        it = &g_cfg.items[g_cfg.count];
        memset(it, 0, sizeof(*it));
        it->bar_x = -1;
        it->bar_y = -1;
        it->bar_bg_color = 0xFFFFFFFF;
        g_cfg.count++;
        if (s->selected_item) *s->selected_item = g_cfg.count - 1;
    }

    it->type = s->type;
    ui_utf8_to_wide(s->name, it->name, CFG_MAX_NAME);
    ui_utf8_to_wide(s->url, it->url, CFG_MAX_URL);
    ui_utf8_to_wide(s->headers, it->req_headers, CFG_MAX_URL);
    it->interval_ms = (DWORD)(s->interval < 1000 ? 1000 : s->interval);
    ui_utf8_to_wide(s->expr, it->field_expr, CFG_MAX_EXPR);
    it->click_enabled = s->click_enabled ? TRUE : FALSE;
    ui_utf8_to_wide(s->click_url, it->click_url, CFG_MAX_URL);
    ui_utf8_to_wide(s->lua_path, it->lua_path, CFG_MAX_PATH);

    it->param_count = s->param_count;
    for (int i = 0; i < s->param_count && i < CFG_MAX_PARAMS; i++) {
        MultiByteToWideChar(CP_UTF8, 0, s->param_decls[i].key, -1,
            it->params[i].key, CFG_MAX_PARAM_KEY);
        MultiByteToWideChar(CP_UTF8, 0, s->param_decls[i].label, -1,
            it->params[i].label, CFG_MAX_NAME);
        ui_utf8_to_wide(s->param_vals[i], it->params[i].value, CFG_MAX_PARAM_VAL);
    }

    int refresh_ms = script_parse_refresh(it->lua_path);
    if (refresh_ms > 0) {
        if (refresh_ms < 1000) refresh_ms = 1000;
        it->interval_ms = (DWORD)refresh_ms;
    }

    it->bar_width = s->bar_width;
    it->bar_x = s->bar_x;
    it->bar_y = s->bar_y;
    it->bar_bg_color = (COLORREF)strtoul(s->bar_bg, NULL, 16);

    config_save(&g_cfg);
    listview_populate();
    if (it->pinned) {
        bars_destroy_all();
        bars_create_all();
    }
    return true;
}

static void draw_edit(UiWindow *w) {
    EditState *s = (EditState *)w->user;
    const float lw = UI_LABEL_W;

    /* Row 1: Type + Name */
    {
        const char *types[] = { tr8("edit.type_url"), tr8("edit.type_lua") };
        ImGui::AlignTextToFramePadding();
        ImGui::TextUnformatted(tr8("edit.type"));
        ImGui::SameLine(lw + UI_PAD);
        ImGui::SetNextItemWidth(120.0f);
        ImGui::Combo("##type", &s->type, types, 2);

        ImGui::SameLine(0, UI_GAP_LG);
        ImGui::TextUnformatted(tr8("edit.name"));
        ImGui::SameLine(0, UI_GAP_SM);
        ImGui::SetNextItemWidth(-UI_PAD);
        ImGui::InputText("##name", s->name, sizeof(s->name));
    }

    ui_section_sep();

    if (s->type == ITEM_TYPE_URL) {
        bool load_click = false;
        ui_field_text_with_button(tr8("edit.url"), s->url, sizeof(s->url),
            tr8("edit.load"), &load_click, lw, 60.0f);
        if (load_click) s->pending_load = true;

        ui_field_multiline(tr8("edit.headers"), s->headers, sizeof(s->headers),
            48.0f, lw);
        ui_field_int(tr8("edit.interval"), &s->interval, lw, 100.0f);

        ImGui::TextUnformatted(tr8("edit.response_structure"));
        ImGui::BeginChild("tree", ImVec2(0, 130), true);
        if (s->tree_count == 0)
            ImGui::TextColored(Theme::TextSecondary, "%s", tr8("edit.load"));
        else
            draw_json_tree_node(s, 0);
        ImGui::EndChild();

        ImGui::TextUnformatted(tr8("edit.template"));
        ImGui::InputTextMultiline("##expr", s->expr, sizeof(s->expr),
            ImVec2(0, 56));
        if (ImGui::IsItemDeactivatedAfterEdit())
            update_preview(s);

        ui_field_begin(tr8("edit.preview"), lw);
        ImGui::InputText("##preview", s->preview, sizeof(s->preview),
            ImGuiInputTextFlags_ReadOnly);

        ui_field_check(tr8("edit.enable_click_url"), &s->click_enabled);
        ui_field_text(tr8("edit.click_url"), s->click_url, sizeof(s->click_url), lw);
    } else {
        bool browse = false;
        {
            ImGui::AlignTextToFramePadding();
            ImGui::TextUnformatted(tr8("edit.lua_file"));
            ImGui::SameLine(lw + UI_PAD);
            float avail = ImGui::GetContentRegionAvail().x - UI_PAD;
            float btn_w = 30.0f;
            float input_w = avail - btn_w - UI_GAP_SM;
            if (input_w < 40.0f) input_w = 40.0f;
            ImGui::SetNextItemWidth(input_w);
            ImGui::InputText("##luapath", s->lua_path, sizeof(s->lua_path));
            if (ImGui::IsItemDeactivatedAfterEdit())
                reload_params(s);
            ImGui::SameLine(0, UI_GAP_SM);
            if (ImGui::Button("...##luabrowse", ImVec2(btn_w, 0)))
                browse = true;
        }
        if (browse) s->pending_browse = 1;

        ui_field_int(tr8("edit.interval"), &s->interval, lw, 100.0f);

        if (s->param_count > 0) {
            ui_section_gap();
            ImGui::TextUnformatted(tr8("edit.params"));
            for (int i = 0; i < s->param_count; i++) {
                ImGui::PushID(i);
                const char *label = s->param_decls[i].label[0]
                    ? s->param_decls[i].label : s->param_decls[i].key;
                bool is_file = (strcmp(s->param_decls[i].type, "file") == 0);
                if (is_file) {
                    bool pb = false;
                    ui_field_text_with_button(label, s->param_vals[i],
                        sizeof(s->param_vals[i]), "...", &pb, lw, 30.0f);
                    if (pb) s->pending_browse = i + 2;
                } else {
                    ui_field_text(label, s->param_vals[i],
                        sizeof(s->param_vals[i]), lw);
                }
                ImGui::PopID();
            }
        }
    }

    ui_section_sep();

    /* Bar geometry row — compact inline fields */
    ui_inline_int(tr8("edit.bar_w"), &s->bar_width, 60.0f);
    ImGui::SameLine(0, UI_GAP);
    ui_inline_int(tr8("edit.bar_x"), &s->bar_x, 60.0f);
    ImGui::SameLine(0, UI_GAP);
    ui_inline_int(tr8("edit.bar_y"), &s->bar_y, 60.0f);
    ImGui::SameLine(0, UI_GAP);
    ui_inline_text(tr8("edit.bar_bg"), s->bar_bg, sizeof(s->bar_bg), 90.0f);

    ui_section_sep();
    int r = ui_ok_cancel(tr8("edit.ok"), tr8("edit.cancel"));
    if (r == 1) {
        apply_item(s);
        free_json(s);
        w->accepted = true;
        w->done = true;
    } else if (r == 2) {
        free_json(s);
        w->done = true;
    }
    if (ImGui::IsKeyPressed(ImGuiKey_Escape)) {
        free_json(s);
        w->done = true;
    }

    if (s->pending_load) {
        s->pending_load = false;
        load_response(s);
    }
    if (s->pending_browse != 0) {
        int kind = s->pending_browse;
        s->pending_browse = 0;
        if (kind == 1)
            browse_lua(s, w->hwnd);
        else if (kind >= 2)
            browse_param(s, w->hwnd, kind - 2);
    }
}

void ui_edit_show(HWND parent, UiWindow *share_device, int item_index, int *selected_item) {
    EditState state;
    memset(&state, 0, sizeof(state));
    state.item_index = item_index;
    state.selected_item = selected_item;
    state.interval = 5000;
    state.bar_x = -1;
    state.bar_y = -1;
    std::snprintf(state.bar_bg, sizeof(state.bar_bg), "FFFFFFFF");
    std::snprintf(state.url, sizeof(state.url), "http://localhost:8080/status");
    state.type = ITEM_TYPE_LUA;

    if (item_index >= 0 && item_index < g_cfg.count) {
        PinItem *it = &g_cfg.items[item_index];
        state.type = it->type;
        ui_wide_to_utf8(it->name, state.name, sizeof(state.name));
        ui_wide_to_utf8(it->url, state.url, sizeof(state.url));
        ui_wide_to_utf8(it->req_headers, state.headers, sizeof(state.headers));
        ui_wide_to_utf8(it->lua_path, state.lua_path, sizeof(state.lua_path));
        state.interval = (int)it->interval_ms;
        ui_wide_to_utf8(it->field_expr, state.expr, sizeof(state.expr));
        state.click_enabled = it->click_enabled ? true : false;
        ui_wide_to_utf8(it->click_url, state.click_url, sizeof(state.click_url));
        state.bar_width = it->bar_width;
        state.bar_x = it->bar_x;
        state.bar_y = it->bar_y;
        std::snprintf(state.bar_bg, sizeof(state.bar_bg), "%08X", (unsigned)it->bar_bg_color);
        if (it->type == ITEM_TYPE_LUA && it->lua_path[0])
            reload_params(&state);
    }

    UiWindow win = {};
    const WCHAR *title = (item_index >= 0)
        ? ui_title("edit.title_edit", L"Edit Item")
        : ui_title("edit.title_add", L"Add Item");
    if (!ui_window_create(&win, parent, L"TaskPinEditClass", title,
            900, 720, share_device))
        return;
    win.user = &state;
    ui_window_run_modal(&win, parent, draw_edit);
    free_json(&state);
    ui_window_destroy(&win);
}
