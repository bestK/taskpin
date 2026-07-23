#include "config.h"
#include "cJSON.h"
#include <shlwapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---------- path helpers ---------- */

static const WCHAR kJsonFile[] = L"config.json";
static const WCHAR kIniFile[]  = L"config.ini";

void config_get_path(WCHAR *buf, DWORD len) {
    GetModuleFileNameW(NULL, buf, len);
    PathRemoveFileSpecW(buf);
    PathAppendW(buf, kJsonFile);
}

static void config_get_ini_path(WCHAR *buf, DWORD len) {
    GetModuleFileNameW(NULL, buf, len);
    PathRemoveFileSpecW(buf);
    PathAppendW(buf, kIniFile);
}

/* ---------- wide/utf8 conversion helpers ---------- */

static void wchar_to_utf8(const WCHAR *w, char *out, int out_size) {
    if (!w || !w[0]) { out[0] = '\0'; return; }
    WideCharToMultiByte(CP_UTF8, 0, w, -1, out, out_size, NULL, NULL);
}

static void utf8_to_wchar(const char *u, WCHAR *out, int out_count) {
    if (!u || !u[0]) { out[0] = L'\0'; return; }
    MultiByteToWideChar(CP_UTF8, 0, u, -1, out, out_count);
}

/* Read a cJSON string field into a WCHAR buffer */
static void json_read_wstr(const cJSON *obj, const char *key, WCHAR *dst, int dst_count, const WCHAR *def) {
    const cJSON *item = cJSON_GetObjectItem(obj, key);
    if (cJSON_IsString(item) && item->valuestring) {
        utf8_to_wchar(item->valuestring, dst, dst_count);
    } else if (def) {
        lstrcpynW(dst, def, dst_count);
    } else {
        dst[0] = L'\0';
    }
}

static int json_read_int(const cJSON *obj, const char *key, int def) {
    const cJSON *item = cJSON_GetObjectItem(obj, key);
    if (cJSON_IsNumber(item)) return item->valueint;
    return def;
}

static BOOL json_read_bool(const cJSON *obj, const char *key, BOOL def) {
    const cJSON *item = cJSON_GetObjectItem(obj, key);
    if (cJSON_IsBool(item)) return cJSON_IsTrue(item) ? TRUE : FALSE;
    return def;
}

static COLORREF json_read_color(const cJSON *obj, const char *key, COLORREF def) {
    const cJSON *item = cJSON_GetObjectItem(obj, key);
    if (cJSON_IsString(item) && item->valuestring) {
        WCHAR tmp[16];
        utf8_to_wchar(item->valuestring, tmp, 16);
        return (COLORREF)wcstoul(tmp, NULL, 16);
    }
    return def;
}

/* Add a WCHAR string to a cJSON object as UTF-8 */
static void json_add_wstr(cJSON *obj, const char *key, const WCHAR *w) {
    char utf8[CFG_MAX_EXPR * 3];
    wchar_to_utf8(w, utf8, sizeof(utf8));
    cJSON_AddStringToObject(obj, key, utf8);
}

static void json_add_color(cJSON *obj, const char *key, COLORREF c, int with_alpha) {
    char buf[16];
    if (with_alpha)
        sprintf(buf, "%08X", (unsigned int)c);
    else
        sprintf(buf, "%06X", (unsigned int)(c & 0xFFFFFF));
    cJSON_AddStringToObject(obj, key, buf);
}

/* ---------- JSON loading ---------- */

static void config_load_json(TaskPinConfig *cfg, const char *json_str) {
    cJSON *root = cJSON_Parse(json_str);
    if (!root) return;

    /* global section */
    cJSON *global = cJSON_GetObjectItem(root, "global");
    if (global) {
        cfg->width    = json_read_int(global, "width", 320);
        cfg->pos_x    = json_read_int(global, "pos_x", -1);
        cfg->pos_y    = json_read_int(global, "pos_y", -1);
        cfg->font_size = json_read_int(global, "font_size", 9);
        cfg->font_color = json_read_color(global, "font_color", 0x00FFFFFF);
        cfg->bg_color   = json_read_color(global, "bg_color", 0xFFFFFFFF);
        cfg->scroll_enabled = json_read_bool(global, "scroll_enabled", TRUE);
        cfg->log_level = json_read_int(global, "log_level", 0);
    }

    /* items array */
    cJSON *items = cJSON_GetObjectItem(root, "items");
    if (cJSON_IsArray(items)) {
        int n = cJSON_GetArraySize(items);
        if (n > CFG_MAX_ITEMS) n = CFG_MAX_ITEMS;
        cfg->count = n;
        for (int i = 0; i < n; i++) {
            cJSON *jitem = cJSON_GetArrayItem(items, i);
            PinItem *it = &cfg->items[i];

            it->type = json_read_int(jitem, "type", ITEM_TYPE_URL);
            json_read_wstr(jitem, "name", it->name, CFG_MAX_NAME, L"Untitled");
            json_read_wstr(jitem, "url", it->url, CFG_MAX_URL, L"");
            json_read_wstr(jitem, "req_headers", it->req_headers, CFG_MAX_URL, L"");
            it->interval_ms = (DWORD)json_read_int(jitem, "interval_ms", 5000);
            json_read_wstr(jitem, "field_expr", it->field_expr, CFG_MAX_EXPR, L"");
            it->click_enabled = json_read_bool(jitem, "click_enabled", FALSE);
            json_read_wstr(jitem, "click_url", it->click_url, CFG_MAX_URL, L"");
            json_read_wstr(jitem, "lua_path", it->lua_path, CFG_MAX_PATH, L"");
            it->pinned = json_read_bool(jitem, "pinned", FALSE);
            it->bar_width = json_read_int(jitem, "bar_width", 0);
            it->bar_x = json_read_int(jitem, "bar_x", -1);
            it->bar_y = json_read_int(jitem, "bar_y", -1);
            it->bar_bg_color = json_read_color(jitem, "bar_bg_color", 0xFFFFFFFF);
            it->dlg_x = json_read_int(jitem, "dlg_x", -1);
            it->dlg_y = json_read_int(jitem, "dlg_y", -1);
            it->dlg_w = json_read_int(jitem, "dlg_w", 0);
            it->dlg_h = json_read_int(jitem, "dlg_h", 0);

            /* params */
            cJSON *params = cJSON_GetObjectItem(jitem, "params");
            if (cJSON_IsArray(params)) {
                int pc = cJSON_GetArraySize(params);
                if (pc > CFG_MAX_PARAMS) pc = CFG_MAX_PARAMS;
                it->param_count = pc;
                for (int j = 0; j < pc; j++) {
                    cJSON *p = cJSON_GetArrayItem(params, j);
                    json_read_wstr(p, "key", it->params[j].key, CFG_MAX_PARAM_KEY, L"");
                    json_read_wstr(p, "value", it->params[j].value, CFG_MAX_PARAM_VAL, L"");
                    json_read_wstr(p, "label", it->params[j].label, CFG_MAX_NAME, L"");
                }
            }
        }
    }

    /* sources */
    cJSON *sources = cJSON_GetObjectItem(root, "sources");
    if (cJSON_IsArray(sources)) {
        int sc = cJSON_GetArraySize(sources);
        if (sc > CFG_MAX_SOURCES) sc = CFG_MAX_SOURCES;
        cfg->source_count = sc;
        for (int i = 0; i < sc; i++) {
            cJSON *s = cJSON_GetArrayItem(sources, i);
            if (cJSON_IsString(s) && s->valuestring) {
                utf8_to_wchar(s->valuestring, cfg->sources[i], CFG_MAX_NAME);
            }
        }
    }

    /* Default source if none configured */
    if (cfg->source_count == 0) {
        lstrcpyW(cfg->sources[0], L"bestK/taskpin-plugins");
        cfg->source_count = 1;
    }

    cJSON_Delete(root);
}

/* ---------- INI loading (for backward-compat migration) ---------- */

#include "base64.h"  /* needed only within config_load_ini */

static void config_load_ini(TaskPinConfig *cfg) {
    WCHAR path[CFG_MAX_PATH];
    config_get_ini_path(path, CFG_MAX_PATH);
    static const WCHAR kGlobal[] = L"Global";

    cfg->width    = GetPrivateProfileIntW(kGlobal, L"width", 320, path);
    cfg->count    = GetPrivateProfileIntW(kGlobal, L"count", 0, path);
    cfg->pos_x    = GetPrivateProfileIntW(kGlobal, L"pos_x", -1, path);
    cfg->pos_y    = GetPrivateProfileIntW(kGlobal, L"pos_y", -1, path);
    cfg->font_size = GetPrivateProfileIntW(kGlobal, L"font_size", 9, path);

    WCHAR color_buf[16];
    GetPrivateProfileStringW(kGlobal, L"font_color", L"FFFFFF", color_buf, 16, path);
    cfg->font_color = (COLORREF)wcstoul(color_buf, NULL, 16);
    GetPrivateProfileStringW(kGlobal, L"bg_color", L"FFFFFFFF", color_buf, 16, path);
    cfg->bg_color = (COLORREF)wcstoul(color_buf, NULL, 16);
    cfg->scroll_enabled = GetPrivateProfileIntW(kGlobal, L"scroll_enabled", 1, path);
    cfg->log_level = GetPrivateProfileIntW(kGlobal, L"log_level", 0, path);

    if (cfg->count > CFG_MAX_ITEMS) cfg->count = CFG_MAX_ITEMS;

    for (int i = 0; i < cfg->count; i++) {
        WCHAR sec[32];
        wsprintfW(sec, L"Item_%d", i);

        cfg->items[i].type = GetPrivateProfileIntW(sec, L"type", ITEM_TYPE_URL, path);
        GetPrivateProfileStringW(sec, L"name", L"Untitled",
            cfg->items[i].name, CFG_MAX_NAME, path);
        GetPrivateProfileStringW(sec, L"url", L"http://localhost:8080/status",
            cfg->items[i].url, CFG_MAX_URL, path);

        /* req_headers stored as base64 */
        WCHAR hdr_b64[CFG_MAX_URL];
        GetPrivateProfileStringW(sec, L"req_headers_b64", L"", hdr_b64, CFG_MAX_URL, path);
        cfg->items[i].req_headers[0] = L'\0';
        if (hdr_b64[0]) {
            char b64a[CFG_MAX_URL];
            WideCharToMultiByte(CP_UTF8, 0, hdr_b64, -1, b64a, CFG_MAX_URL, NULL, NULL);
            int dec_len = 0;
            char *decoded = base64_decode(b64a, &dec_len);
            if (decoded) {
                MultiByteToWideChar(CP_UTF8, 0, decoded, dec_len,
                    cfg->items[i].req_headers, CFG_MAX_URL);
                cfg->items[i].req_headers[
                    dec_len < CFG_MAX_URL ? dec_len : CFG_MAX_URL-1] = L'\0';
                free(decoded);
            }
        }

        cfg->items[i].interval_ms = (DWORD)GetPrivateProfileIntW(sec, L"interval_ms", 5000, path);

        /* field_expr stored as base64 in INI */
        WCHAR b64w[CFG_MAX_EXPR];
        GetPrivateProfileStringW(sec, L"field_expr_b64", L"", b64w, CFG_MAX_EXPR, path);
        cfg->items[i].field_expr[0] = L'\0';
        if (b64w[0]) {
            char b64a[CFG_MAX_EXPR];
            WideCharToMultiByte(CP_UTF8, 0, b64w, -1, b64a, CFG_MAX_EXPR, NULL, NULL);
            int dec_len = 0;
            char *decoded = base64_decode(b64a, &dec_len);
            if (decoded) {
                MultiByteToWideChar(CP_UTF8, 0, decoded, dec_len,
                    cfg->items[i].field_expr, CFG_MAX_EXPR);
                cfg->items[i].field_expr[
                    dec_len < CFG_MAX_EXPR ? dec_len : CFG_MAX_EXPR-1] = L'\0';
                free(decoded);
            }
        }

        cfg->items[i].click_enabled = GetPrivateProfileIntW(sec, L"click_enabled", 0, path);
        GetPrivateProfileStringW(sec, L"click_url", L"",
            cfg->items[i].click_url, CFG_MAX_URL, path);
        GetPrivateProfileStringW(sec, L"lua_path", L"",
            cfg->items[i].lua_path, CFG_MAX_PATH, path);

        /* Load params */
        cfg->items[i].param_count = GetPrivateProfileIntW(sec, L"param_count", 0, path);
        if (cfg->items[i].param_count > CFG_MAX_PARAMS)
            cfg->items[i].param_count = CFG_MAX_PARAMS;
        cfg->items[i].pinned = GetPrivateProfileIntW(sec, L"pinned", 0, path);
        cfg->items[i].bar_width = GetPrivateProfileIntW(sec, L"bar_width", 0, path);
        cfg->items[i].bar_x = GetPrivateProfileIntW(sec, L"bar_x", -1, path);
        cfg->items[i].bar_y = GetPrivateProfileIntW(sec, L"bar_y", -1, path);
        WCHAR bg_buf[16];
        GetPrivateProfileStringW(sec, L"bar_bg_color", L"FFFFFFFF", bg_buf, 16, path);
        cfg->items[i].bar_bg_color = (COLORREF)wcstoul(bg_buf, NULL, 16);
        cfg->items[i].dlg_x = GetPrivateProfileIntW(sec, L"dlg_x", -1, path);
        cfg->items[i].dlg_y = GetPrivateProfileIntW(sec, L"dlg_y", -1, path);
        cfg->items[i].dlg_w = GetPrivateProfileIntW(sec, L"dlg_w", 0, path);
        cfg->items[i].dlg_h = GetPrivateProfileIntW(sec, L"dlg_h", 0, path);
        for (int j = 0; j < cfg->items[i].param_count; j++) {
            WCHAR pk[32], pv[32], pl[32];
            wsprintfW(pk, L"param_key_%d", j);
            wsprintfW(pv, L"param_val_%d", j);
            wsprintfW(pl, L"param_lbl_%d", j);
            GetPrivateProfileStringW(sec, pk, L"",
                cfg->items[i].params[j].key, CFG_MAX_PARAM_KEY, path);
            GetPrivateProfileStringW(sec, pv, L"",
                cfg->items[i].params[j].value, CFG_MAX_PARAM_VAL, path);
            GetPrivateProfileStringW(sec, pl, L"",
                cfg->items[i].params[j].label, CFG_MAX_NAME, path);
        }
    }

    /* Backward compat: if no item has pinned flag, use legacy 'selected' */
    BOOL any_pinned = FALSE;
    for (int i = 0; i < cfg->count; i++) {
        if (cfg->items[i].pinned) { any_pinned = TRUE; break; }
    }
    if (!any_pinned) {
        int legacy_sel = GetPrivateProfileIntW(kGlobal, L"selected", -1, path);
        if (legacy_sel >= 0 && legacy_sel < cfg->count) {
            cfg->items[legacy_sel].pinned = TRUE;
        }
    }

    /* Load plugin market sources */
    cfg->source_count = GetPrivateProfileIntW(L"Sources", L"count", 0, path);
    if (cfg->source_count > CFG_MAX_SOURCES) cfg->source_count = CFG_MAX_SOURCES;
    for (int i = 0; i < cfg->source_count; i++) {
        WCHAR key[32];
        wsprintfW(key, L"source_%d", i);
        GetPrivateProfileStringW(L"Sources", key, L"", cfg->sources[i], CFG_MAX_NAME, path);
    }
    /* Default source if none configured */
    if (cfg->source_count == 0) {
        lstrcpyW(cfg->sources[0], L"bestK/taskpin-plugins");
        cfg->source_count = 1;
    }
}

/* ---------- config_load ---------- */

void config_load(TaskPinConfig *cfg) {
    memset(cfg, 0, sizeof(TaskPinConfig));
    for (int i = 0; i < CFG_MAX_ITEMS; i++) {
        cfg->items[i].dlg_x = -1;
        cfg->items[i].dlg_y = -1;
    }

    /* Try config.json first */
    WCHAR json_path[CFG_MAX_PATH];
    config_get_path(json_path, CFG_MAX_PATH);

    char json_path_a[CFG_MAX_PATH * 3];
    wchar_to_utf8(json_path, json_path_a, sizeof(json_path_a));

    FILE *f = fopen(json_path_a, "rb");
    if (f) {
        fseek(f, 0, SEEK_END);
        long sz = ftell(f);
        fseek(f, 0, SEEK_SET);
        if (sz > 0) {
            char *buf = (char *)malloc((size_t)sz + 1);
            if (buf) {
                fread(buf, 1, (size_t)sz, f);
                buf[sz] = '\0';
                fclose(f);
                config_load_json(cfg, buf);
                free(buf);
                return;
            }
        }
        fclose(f);
    }

    /* Fallback: check for config.ini and migrate */
    WCHAR ini_path[CFG_MAX_PATH];
    config_get_ini_path(ini_path, CFG_MAX_PATH);
    if (PathFileExistsW(ini_path)) {
        config_load_ini(cfg);
        /* Migrate: save as JSON */
        config_save(cfg);
        /* Rename ini to .bak */
        WCHAR bak_path[CFG_MAX_PATH];
        lstrcpynW(bak_path, ini_path, CFG_MAX_PATH);
        lstrcatW(bak_path, L".bak");
        MoveFileW(ini_path, bak_path);
        return;
    }

    /* Neither exists: use defaults */
    cfg->width = 320;
    cfg->pos_x = -1;
    cfg->pos_y = -1;
    cfg->font_size = 9;
    cfg->font_color = 0x00FFFFFF;
    cfg->bg_color = 0xFFFFFFFF;
    cfg->scroll_enabled = TRUE;
    cfg->log_level = 0;
    cfg->count = 0;
    lstrcpyW(cfg->sources[0], L"bestK/taskpin-plugins");
    cfg->source_count = 1;
}

/* ---------- config_save ---------- */

void config_save(const TaskPinConfig *cfg) {
    cJSON *root = cJSON_CreateObject();
    if (!root) return;

    cJSON_AddNumberToObject(root, "version", 1);

    /* global */
    cJSON *global = cJSON_AddObjectToObject(root, "global");
    cJSON_AddNumberToObject(global, "width", cfg->width);
    cJSON_AddNumberToObject(global, "pos_x", cfg->pos_x);
    cJSON_AddNumberToObject(global, "pos_y", cfg->pos_y);
    cJSON_AddNumberToObject(global, "font_size", cfg->font_size);
    json_add_color(global, "font_color", cfg->font_color, 0);
    json_add_color(global, "bg_color", cfg->bg_color, 1);
    cJSON_AddBoolToObject(global, "scroll_enabled", cfg->scroll_enabled ? 1 : 0);
    cJSON_AddNumberToObject(global, "log_level", cfg->log_level);

    /* items */
    cJSON *items = cJSON_AddArrayToObject(root, "items");
    for (int i = 0; i < cfg->count; i++) {
        const PinItem *it = &cfg->items[i];
        cJSON *jitem = cJSON_CreateObject();

        cJSON_AddNumberToObject(jitem, "type", it->type);
        json_add_wstr(jitem, "name", it->name);
        json_add_wstr(jitem, "url", it->url);
        json_add_wstr(jitem, "req_headers", it->req_headers);
        cJSON_AddNumberToObject(jitem, "interval_ms", (double)it->interval_ms);
        json_add_wstr(jitem, "field_expr", it->field_expr);
        cJSON_AddBoolToObject(jitem, "click_enabled", it->click_enabled ? 1 : 0);
        json_add_wstr(jitem, "click_url", it->click_url);
        json_add_wstr(jitem, "lua_path", it->lua_path);
        cJSON_AddBoolToObject(jitem, "pinned", it->pinned ? 1 : 0);
        cJSON_AddNumberToObject(jitem, "bar_width", it->bar_width);
        cJSON_AddNumberToObject(jitem, "bar_x", it->bar_x);
        cJSON_AddNumberToObject(jitem, "bar_y", it->bar_y);
        json_add_color(jitem, "bar_bg_color", it->bar_bg_color, 1);
        cJSON_AddNumberToObject(jitem, "dlg_x", it->dlg_x);
        cJSON_AddNumberToObject(jitem, "dlg_y", it->dlg_y);
        cJSON_AddNumberToObject(jitem, "dlg_w", it->dlg_w);
        cJSON_AddNumberToObject(jitem, "dlg_h", it->dlg_h);

        /* params */
        if (it->param_count > 0) {
            cJSON *params = cJSON_AddArrayToObject(jitem, "params");
            for (int j = 0; j < it->param_count; j++) {
                cJSON *p = cJSON_CreateObject();
                json_add_wstr(p, "key", it->params[j].key);
                json_add_wstr(p, "value", it->params[j].value);
                json_add_wstr(p, "label", it->params[j].label);
                cJSON_AddItemToArray(params, p);
            }
        }

        cJSON_AddItemToArray(items, jitem);
    }

    /* sources */
    cJSON *sources = cJSON_AddArrayToObject(root, "sources");
    for (int i = 0; i < cfg->source_count; i++) {
        char utf8[CFG_MAX_NAME * 3];
        wchar_to_utf8(cfg->sources[i], utf8, sizeof(utf8));
        cJSON_AddItemToArray(sources, cJSON_CreateString(utf8));
    }

    /* Serialize to string */
    char *printed = cJSON_Print(root);
    cJSON_Delete(root);
    if (!printed) return;

    /* Atomic write: write to .tmp then rename */
    WCHAR json_path[CFG_MAX_PATH];
    config_get_path(json_path, CFG_MAX_PATH);

    WCHAR tmp_path[CFG_MAX_PATH];
    lstrcpynW(tmp_path, json_path, CFG_MAX_PATH);
    lstrcatW(tmp_path, L".tmp");

    char tmp_path_a[CFG_MAX_PATH * 3];
    wchar_to_utf8(tmp_path, tmp_path_a, sizeof(tmp_path_a));

    FILE *f = fopen(tmp_path_a, "wb");
    if (f) {
        size_t len = strlen(printed);
        fwrite(printed, 1, len, f);
        fclose(f);
        /* Replace original with tmp (atomic on NTFS) */
        MoveFileExW(tmp_path, json_path, MOVEFILE_REPLACE_EXISTING);
    }

    cJSON_free(printed);
}
