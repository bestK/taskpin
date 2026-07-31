/*
 * Plugin market — independent Win32 modal window.
 */
extern "C" {
#include "ui.h"
#include "httputil.h"
}

#include "ui_views.h"
#include "ui_window.h"
#include "ui_common.h"
#include <cstring>

#define MKT_MAX_SCRIPTS 64

struct MarketScript {
    char name[128];
    char file[256];
    char description[256];
    char author[64];
    char version[32];
};

struct MarketState {
    bool geo_checked;
    bool is_china;
    char source_input[CFG_MAX_NAME * 3];
    int  source_sel;
    MarketScript scripts[MKT_MAX_SCRIPTS];
    int  script_count;
    int  script_sel;
    char status[128];
    bool need_geo;
    bool need_fetch;
    bool need_download;
    WCHAR fetch_repo[CFG_MAX_NAME];
};

static void set_status(MarketState *s, const char *text) {
    std::snprintf(s->status, sizeof(s->status), "%s", text ? text : "");
}

static void check_geo(MarketState *s) {
    if (s->geo_checked) return;
    s->geo_checked = true;
    char *resp = http_request_sync(L"https://api.ip.sb/geoip", L"GET",
        NULL, NULL, NULL, 0);
    if (!resp) return;
    JsonNode *root = json_parse(resp);
    if (root) {
        for (JsonNode *c = root->children; c; c = c->next) {
            if (c->key && strcmp(c->key, "country_code") == 0 &&
                c->str_val && strcmp(c->str_val, "CN") == 0) {
                s->is_china = true;
                break;
            }
        }
        json_free(root);
    }
    free(resp);
}

static void build_raw_url(MarketState *s, WCHAR *out, int out_size,
    const WCHAR *repo, const char *file) {
    if (s->is_china)
        _snwprintf(out, out_size,
            L"https://gh-proxy.com/https://raw.githubusercontent.com/%s/master/%S",
            repo, file);
    else
        _snwprintf(out, out_size,
            L"https://raw.githubusercontent.com/%s/master/%S", repo, file);
}

static void fetch_scripts(MarketState *s, const WCHAR *repo) {
    s->script_count = 0;
    s->script_sel = -1;
    set_status(s, tr8("market.fetching"));

    char repo8[256];
    WideCharToMultiByte(CP_UTF8, 0, repo, -1, repo8, 256, NULL, NULL);

    WCHAR url[512];
    build_raw_url(s, url, 512, repo, "manifest.json");
    char *resp = http_request_sync(url, L"GET", NULL, NULL, NULL, 0);

    if (resp) {
        JsonNode *root = json_parse(resp);
        if (root) {
            JsonNode *scripts = NULL;
            for (JsonNode *c = root->children; c; c = c->next) {
                if (c->key && strcmp(c->key, "scripts") == 0 && c->type == JSON_ARRAY) {
                    scripts = c;
                    break;
                }
            }
            if (scripts) {
                for (JsonNode *node = scripts->children;
                     node && s->script_count < MKT_MAX_SCRIPTS; node = node->next) {
                    MarketScript *ms = &s->scripts[s->script_count];
                    memset(ms, 0, sizeof(*ms));
                    for (JsonNode *f = node->children; f; f = f->next) {
                        if (!f->key || !f->str_val) continue;
                        if (strcmp(f->key, "name") == 0) strncpy(ms->name, f->str_val, 127);
                        else if (strcmp(f->key, "file") == 0) strncpy(ms->file, f->str_val, 255);
                        else if (strcmp(f->key, "description") == 0) strncpy(ms->description, f->str_val, 255);
                        else if (strcmp(f->key, "author") == 0) strncpy(ms->author, f->str_val, 63);
                        else if (strcmp(f->key, "version") == 0) strncpy(ms->version, f->str_val, 31);
                    }
                    if (ms->file[0]) s->script_count++;
                }
                json_free(root);
                free(resp);
                std::snprintf(s->status, sizeof(s->status),
                    tr8("market.script_count"), s->script_count);
                return;
            }
            json_free(root);
        }
        free(resp);
    }

    wsprintfW(url, L"https://api.github.com/repos/%s/contents/", repo);
    resp = http_request_sync(url, L"GET", NULL,
        L"User-Agent: TaskPin\r\nAccept: application/vnd.github.v3+json\r\n",
        NULL, 0);
    if (resp) {
        JsonNode *root = json_parse(resp);
        if (root && root->type == JSON_ARRAY) {
            for (JsonNode *item = root->children;
                 item && s->script_count < MKT_MAX_SCRIPTS; item = item->next) {
                char *name = NULL;
                for (JsonNode *f = item->children; f; f = f->next) {
                    if (f->key && strcmp(f->key, "name") == 0 && f->str_val)
                        name = f->str_val;
                }
                if (!name) continue;
                int len = (int)strlen(name);
                if (len < 5 || strcmp(name + len - 4, ".lua") != 0) continue;
                MarketScript *ms = &s->scripts[s->script_count];
                memset(ms, 0, sizeof(*ms));
                strncpy(ms->name, name, 127);
                strncpy(ms->file, name, 255);
                strncpy(ms->author, repo8, 63);
                s->script_count++;
            }
            json_free(root);
        }
        free(resp);
    }
    std::snprintf(s->status, sizeof(s->status),
        tr8("market.script_count"), s->script_count);
}

static void download_selected(MarketState *s) {
    if (s->script_sel < 0 || s->script_sel >= s->script_count) {
        set_status(s, tr8("market.select_script_first"));
        return;
    }
    WCHAR repo[CFG_MAX_NAME] = {0};
    if (s->source_sel >= 0 && s->source_sel < g_cfg.source_count)
        lstrcpynW(repo, g_cfg.sources[s->source_sel], CFG_MAX_NAME);
    else
        ui_utf8_to_wide(s->source_input, repo, CFG_MAX_NAME);
    if (!repo[0]) return;

    MarketScript *ms = &s->scripts[s->script_sel];
    WCHAR url[512];
    build_raw_url(s, url, 512, repo, ms->file);

    set_status(s, tr8("market.downloading"));
    char *content = http_request_sync(url, L"GET", NULL, NULL, NULL, 0);
    if (!content) {
        set_status(s, tr8("market.download_failed"));
        return;
    }

    WCHAR dir[MAX_PATH];
    GetModuleFileNameW(NULL, dir, MAX_PATH);
    WCHAR *slash = wcsrchr(dir, L'\\');
    if (slash) *(slash + 1) = L'\0';
    lstrcatW(dir, L"scripts");
    CreateDirectoryW(dir, NULL);

    WCHAR filepath[MAX_PATH];
    wsprintfW(filepath, L"%s\\%S", dir, ms->file);
    FILE *f = _wfopen(filepath, L"wb");
    if (f) {
        fwrite(content, 1, strlen(content), f);
        fclose(f);

        /* Add (or update) a list item pointing at the downloaded script so it
         * shows up in the main window immediately. */
        int existing = -1;
        for (int i = 0; i < g_cfg.count; i++) {
            if (g_cfg.items[i].type == ITEM_TYPE_LUA &&
                lstrcmpiW(g_cfg.items[i].lua_path, filepath) == 0) {
                existing = i;
                break;
            }
        }

        if (existing < 0 && g_cfg.count >= CFG_MAX_ITEMS) {
            set_status(s, tr8("market.download_success"));
            free(content);
            return;
        }

        PinItem *it;
        if (existing >= 0) {
            it = &g_cfg.items[existing];
        } else {
            it = &g_cfg.items[g_cfg.count];
            memset(it, 0, sizeof(*it));
            it->bar_x = -1;
            it->bar_y = -1;
            it->bar_bg_color = 0xFFFFFFFF;
            g_cfg.count++;
        }

        it->type = ITEM_TYPE_LUA;
        lstrcpynW(it->lua_path, filepath, CFG_MAX_PATH);
        /* Name from manifest, fall back to file name. */
        if (ms->name[0])
            MultiByteToWideChar(CP_UTF8, 0, ms->name, -1, it->name, CFG_MAX_NAME);
        else
            MultiByteToWideChar(CP_UTF8, 0, ms->file, -1, it->name, CFG_MAX_NAME);

        int refresh_ms = script_parse_refresh(it->lua_path);
        if (refresh_ms < 1000) refresh_ms = 5000;
        it->interval_ms = (DWORD)refresh_ms;

        /* Seed @param declarations with empty values, preserving any the user
         * already filled in when re-downloading an existing script. */
        ScriptParamDecl decls[CFG_MAX_PARAMS];
        memset(decls, 0, sizeof(decls));
        int ndecls = script_parse_params(it->lua_path, decls, CFG_MAX_PARAMS);
        ParamEntry old[CFG_MAX_PARAMS];
        int old_count = it->param_count;
        memcpy(old, it->params, sizeof(old));
        memset(it->params, 0, sizeof(it->params));
        for (int i = 0; i < ndecls; i++) {
            MultiByteToWideChar(CP_UTF8, 0, decls[i].key, -1,
                it->params[i].key, CFG_MAX_PARAM_KEY);
            MultiByteToWideChar(CP_UTF8, 0, decls[i].label, -1,
                it->params[i].label, CFG_MAX_NAME);
            for (int j = 0; j < old_count; j++) {
                if (lstrcmpW(old[j].key, it->params[i].key) == 0) {
                    lstrcpynW(it->params[i].value, old[j].value, CFG_MAX_PARAM_VAL);
                    break;
                }
            }
        }
        it->param_count = ndecls;

        config_save(&g_cfg);
        modern_ui_refresh();
        set_status(s, tr8("market.download_success"));
    } else {
        set_status(s, tr8("market.save_failed"));
    }
    free(content);
}

static void process_deferred(MarketState *s) {
    if (s->need_geo) {
        s->need_geo = false;
        check_geo(s);
    }
    if (s->need_fetch) {
        s->need_fetch = false;
        if (s->fetch_repo[0]) fetch_scripts(s, s->fetch_repo);
    }
    if (s->need_download) {
        s->need_download = false;
        download_selected(s);
    }
}

static void queue_fetch(MarketState *s) {
    s->fetch_repo[0] = L'\0';
    if (s->source_sel >= 0 && s->source_sel < g_cfg.source_count)
        lstrcpynW(s->fetch_repo, g_cfg.sources[s->source_sel], CFG_MAX_NAME);
    else
        ui_utf8_to_wide(s->source_input, s->fetch_repo, CFG_MAX_NAME);
    if (s->fetch_repo[0]) {
        s->need_fetch = true;
        set_status(s, tr8("market.fetching"));
    }
}

static void draw_market(UiWindow *w) {
    MarketState *s = (MarketState *)w->user;

    /* Toolbar: source combo + edit + Add/Del/Refresh */
    {
        ImGui::SetNextItemWidth(220.0f);
        if (ImGui::BeginCombo("##src", s->source_input[0] ? s->source_input : "(source)")) {
            for (int i = 0; i < g_cfg.source_count; i++) {
                char src[CFG_MAX_NAME * 3];
                ui_wide_to_utf8(g_cfg.sources[i], src, sizeof(src));
                bool sel = (i == s->source_sel);
                if (ImGui::Selectable(src, sel)) {
                    s->source_sel = i;
                    std::snprintf(s->source_input, sizeof(s->source_input), "%s", src);
                }
                if (sel) ImGui::SetItemDefaultFocus();
            }
            ImGui::EndCombo();
        }
        ImGui::SameLine(0, UI_GAP_SM);
        ImGui::SetNextItemWidth(150.0f);
        ImGui::InputTextWithHint("##src_edit", "user/repo",
            s->source_input, sizeof(s->source_input));
        ImGui::SameLine(0, UI_GAP_SM);
        if (ui_btn_sm(tr8("market.add"))) {
            if (g_cfg.source_count >= CFG_MAX_SOURCES) {
                set_status(s, tr8("market.max_sources"));
            } else if (!s->source_input[0]) {
                set_status(s, tr8("market.enter_repo"));
            } else {
                WCHAR wsrc[CFG_MAX_NAME];
                ui_utf8_to_wide(s->source_input, wsrc, CFG_MAX_NAME);
                bool exists = false;
                for (int i = 0; i < g_cfg.source_count; i++) {
                    if (lstrcmpiW(g_cfg.sources[i], wsrc) == 0) { exists = true; break; }
                }
                if (!exists) {
                    lstrcpynW(g_cfg.sources[g_cfg.source_count], wsrc, CFG_MAX_NAME);
                    g_cfg.source_count++;
                    config_save(&g_cfg);
                    s->source_sel = g_cfg.source_count - 1;
                    lstrcpynW(s->fetch_repo, wsrc, CFG_MAX_NAME);
                    s->need_fetch = true;
                    set_status(s, tr8("market.fetching"));
                }
            }
        }
        ImGui::SameLine(0, UI_GAP_SM);
        if (ui_btn_sm(tr8("market.del"))) {
            if (s->source_sel >= 0 && s->source_sel < g_cfg.source_count) {
                for (int i = s->source_sel; i < g_cfg.source_count - 1; i++)
                    lstrcpyW(g_cfg.sources[i], g_cfg.sources[i + 1]);
                g_cfg.source_count--;
                config_save(&g_cfg);
                if (s->source_sel >= g_cfg.source_count)
                    s->source_sel = g_cfg.source_count - 1;
                s->script_count = 0;
                if (s->source_sel >= 0)
                    ui_wide_to_utf8(g_cfg.sources[s->source_sel],
                        s->source_input, sizeof(s->source_input));
                else
                    s->source_input[0] = '\0';
                set_status(s, tr8("market.source_deleted"));
            }
        }
        ImGui::SameLine(0, UI_GAP_SM);
        if (ui_btn(tr8("market.refresh")))
            queue_fetch(s);
    }

    ui_section_gap();

    /* Script table */
    float table_h = ui_body_height();
    if (ImGui::BeginTable("mkt", 4, ui_table_flags(), ImVec2(0.0f, table_h))) {
        ImGui::TableSetupScrollFreeze(0, 1);
        ImGui::TableSetupColumn(tr8("market.col_name"),
            ImGuiTableColumnFlags_WidthFixed, 120.0f);
        ImGui::TableSetupColumn(tr8("market.col_description"),
            ImGuiTableColumnFlags_WidthStretch);
        ImGui::TableSetupColumn(tr8("market.col_author"),
            ImGuiTableColumnFlags_WidthFixed, 100.0f);
        ImGui::TableSetupColumn(tr8("market.col_version"),
            ImGuiTableColumnFlags_WidthFixed, 60.0f);
        ImGui::TableHeadersRow();

        for (int i = 0; i < s->script_count; i++) {
            MarketScript *ms = &s->scripts[i];
            ImGui::TableNextRow();
            ImGui::PushID(i);
            ImGui::TableSetColumnIndex(0);
            bool selected = (s->script_sel == i);
            if (ImGui::Selectable(ms->name[0] ? ms->name : ms->file, selected,
                    ImGuiSelectableFlags_SpanAllColumns))
                s->script_sel = i;
            if (ImGui::IsItemHovered() &&
                ImGui::IsMouseDoubleClicked(ImGuiMouseButton_Left)) {
                s->script_sel = i;
                s->need_download = true;
                set_status(s, tr8("market.downloading"));
            }
            ImGui::TableSetColumnIndex(1);
            ImGui::TextUnformatted(ms->description);
            ImGui::TableSetColumnIndex(2);
            ImGui::TextUnformatted(ms->author);
            ImGui::TableSetColumnIndex(3);
            ImGui::TextUnformatted(ms->version);
            ImGui::PopID();
        }
        ImGui::EndTable();
    }

    /* Footer: Download + status + Close */
    ui_footer_begin("mkt_footer");
    if (ui_btn(tr8("market.download"), UI_BTN_W_WIDE)) {
        s->need_download = true;
        set_status(s, tr8("market.downloading"));
    }
    ImGui::SameLine(0, UI_GAP);
    ImGui::AlignTextToFramePadding();
    ImGui::TextColored(Theme::TextSecondary, "%s", s->status);

    float close_x = ImGui::GetWindowWidth() - UI_BTN_W - UI_PAD;
    if (close_x > ImGui::GetCursorPosX() + UI_GAP) {
        ImGui::SameLine(close_x);
        if (ui_btn(tr8("market.cancel")))
            w->done = true;
    }
    ui_footer_end();

    if (ImGui::IsKeyPressed(ImGuiKey_Escape))
        w->done = true;

    process_deferred(s);
}

void ui_market_show(HWND parent, UiWindow *share_device) {
    MarketState state = {};
    state.source_sel = 0;
    state.script_sel = -1;
    set_status(&state, tr8("market.initial_status"));
    state.need_geo = true;
    if (g_cfg.source_count > 0) {
        ui_wide_to_utf8(g_cfg.sources[0], state.source_input, sizeof(state.source_input));
        lstrcpynW(state.fetch_repo, g_cfg.sources[0], CFG_MAX_NAME);
        state.need_fetch = true;
        set_status(&state, tr8("market.fetching"));
    }

    UiWindow win = {};
    if (!ui_window_create(&win, parent, L"TaskPinMarketClass",
            ui_title("market.title", L"Plugin Market"), 640, 440, share_device))
        return;
    win.user = &state;
    ui_window_run_modal(&win, parent, draw_market);
    ui_window_destroy(&win);
}
