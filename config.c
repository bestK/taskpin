#include "config.h"
#include "base64.h"
#include <shlwapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const WCHAR kGlobal[] = L"Global";
static const WCHAR kFile[]   = L"config.ini";

void config_get_path(WCHAR *buf, DWORD len) {
    GetModuleFileNameW(NULL, buf, len);
    PathRemoveFileSpecW(buf);
    PathAppendW(buf, kFile);
}

void config_load(TaskPinConfig *cfg) {
    WCHAR path[CFG_MAX_PATH];
    config_get_path(path, CFG_MAX_PATH);

    cfg->width    = GetPrivateProfileIntW(kGlobal, L"width", 320, path);
    cfg->selected = GetPrivateProfileIntW(kGlobal, L"selected", -1, path);
    cfg->count    = GetPrivateProfileIntW(kGlobal, L"count", 0, path);
    cfg->pos_x    = GetPrivateProfileIntW(kGlobal, L"pos_x", -1, path);
    cfg->pos_y    = GetPrivateProfileIntW(kGlobal, L"pos_y", -1, path);
    cfg->font_size = GetPrivateProfileIntW(kGlobal, L"font_size", 9, path);

    WCHAR color_buf[16];
    GetPrivateProfileStringW(kGlobal, L"font_color", L"FFFFFF", color_buf, 16, path);
    cfg->font_color = (COLORREF)wcstoul(color_buf, NULL, 16);
    GetPrivateProfileStringW(kGlobal, L"bg_color", L"000000", color_buf, 16, path);
    cfg->bg_color = (COLORREF)wcstoul(color_buf, NULL, 16);
    cfg->scroll_enabled = GetPrivateProfileIntW(kGlobal, L"scroll_enabled", 1, path);

    if (cfg->count > CFG_MAX_ITEMS) cfg->count = CFG_MAX_ITEMS;

    for (int i = 0; i < cfg->count; i++) {
        WCHAR sec[32];
        wsprintfW(sec, L"Item_%d", i);

        cfg->items[i].type = GetPrivateProfileIntW(sec, L"type", ITEM_TYPE_URL, path);
        GetPrivateProfileStringW(sec, L"name", L"Untitled",
            cfg->items[i].name, CFG_MAX_NAME, path);
        GetPrivateProfileStringW(sec, L"url", L"http://localhost:8080/status",
            cfg->items[i].url, CFG_MAX_URL, path);
        cfg->items[i].interval_ms = (DWORD)GetPrivateProfileIntW(sec, L"interval_ms", 5000, path);

        /* field_expr stored as base64 in INI */
        WCHAR b64w[CFG_MAX_EXPR];
        GetPrivateProfileStringW(sec, L"field_expr_b64", L"",
            b64w, CFG_MAX_EXPR, path);
        cfg->items[i].field_expr[0] = L'\0';
        if (b64w[0]) {
            char b64a[CFG_MAX_EXPR];
            WideCharToMultiByte(CP_UTF8, 0, b64w, -1, b64a, CFG_MAX_EXPR, NULL, NULL);
            int dec_len = 0;
            char *decoded = base64_decode(b64a, &dec_len);
            if (decoded) {
                MultiByteToWideChar(CP_UTF8, 0, decoded, dec_len, cfg->items[i].field_expr, CFG_MAX_EXPR);
                cfg->items[i].field_expr[dec_len < CFG_MAX_EXPR ? dec_len : CFG_MAX_EXPR-1] = L'\0';
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
}

void config_save(const TaskPinConfig *cfg) {
    WCHAR path[CFG_MAX_PATH];
    config_get_path(path, CFG_MAX_PATH);

    /* Ensure file exists with UTF-16LE BOM so WritePrivateProfileStringW uses Unicode */
    HANDLE hf = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    BOOL need_bom = FALSE;
    if (hf == INVALID_HANDLE_VALUE) {
        need_bom = TRUE;
    } else {
        BYTE bom[2] = {0};
        DWORD rd = 0;
        ReadFile(hf, bom, 2, &rd, NULL);
        CloseHandle(hf);
        if (rd < 2 || bom[0] != 0xFF || bom[1] != 0xFE)
            need_bom = TRUE;
    }
    if (need_bom) {
        hf = CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, 0, NULL);
        if (hf != INVALID_HANDLE_VALUE) {
            BYTE bom[2] = {0xFF, 0xFE};
            DWORD wr;
            WriteFile(hf, bom, 2, &wr, NULL);
            CloseHandle(hf);
        }
    }

    /* Clear old items by deleting sections beyond current count */
    for (int i = cfg->count; i < CFG_MAX_ITEMS; i++) {
        WCHAR sec[32];
        wsprintfW(sec, L"Item_%d", i);
        WritePrivateProfileStringW(sec, NULL, NULL, path);
    }

    WCHAR tmp[32];
    wsprintfW(tmp, L"%d", cfg->width);
    WritePrivateProfileStringW(kGlobal, L"width", tmp, path);

    wsprintfW(tmp, L"%d", cfg->selected);
    WritePrivateProfileStringW(kGlobal, L"selected", tmp, path);

    wsprintfW(tmp, L"%d", cfg->count);
    WritePrivateProfileStringW(kGlobal, L"count", tmp, path);

    wsprintfW(tmp, L"%d", cfg->pos_x);
    WritePrivateProfileStringW(kGlobal, L"pos_x", tmp, path);

    wsprintfW(tmp, L"%d", cfg->pos_y);
    WritePrivateProfileStringW(kGlobal, L"pos_y", tmp, path);

    wsprintfW(tmp, L"%d", cfg->font_size);
    WritePrivateProfileStringW(kGlobal, L"font_size", tmp, path);

    wsprintfW(tmp, L"%06X", cfg->font_color & 0xFFFFFF);
    WritePrivateProfileStringW(kGlobal, L"font_color", tmp, path);

    wsprintfW(tmp, L"%06X", cfg->bg_color & 0xFFFFFF);
    WritePrivateProfileStringW(kGlobal, L"bg_color", tmp, path);

    wsprintfW(tmp, L"%d", cfg->scroll_enabled ? 1 : 0);
    WritePrivateProfileStringW(kGlobal, L"scroll_enabled", tmp, path);

    for (int i = 0; i < cfg->count; i++) {
        WCHAR sec[32];
        wsprintfW(sec, L"Item_%d", i);

        wsprintfW(tmp, L"%d", cfg->items[i].type);
        WritePrivateProfileStringW(sec, L"type", tmp, path);
        WritePrivateProfileStringW(sec, L"name", cfg->items[i].name, path);
        WritePrivateProfileStringW(sec, L"url", cfg->items[i].url, path);

        wsprintfW(tmp, L"%u", cfg->items[i].interval_ms);
        WritePrivateProfileStringW(sec, L"interval_ms", tmp, path);

        /* Encode field_expr as base64 */
        if (cfg->items[i].field_expr[0]) {
            char utf8[CFG_MAX_EXPR * 3];
            int u8len = WideCharToMultiByte(CP_UTF8, 0, cfg->items[i].field_expr, -1,
                utf8, sizeof(utf8), NULL, NULL);
            if (u8len > 0) u8len--; /* exclude NUL */
            char *b64 = base64_encode(utf8, u8len);
            if (b64) {
                WCHAR b64w[CFG_MAX_EXPR * 4];
                MultiByteToWideChar(CP_UTF8, 0, b64, -1, b64w, CFG_MAX_EXPR * 4);
                WritePrivateProfileStringW(sec, L"field_expr_b64", b64w, path);
                free(b64);
            }
        } else {
            WritePrivateProfileStringW(sec, L"field_expr_b64", L"", path);
        }

        wsprintfW(tmp, L"%d", cfg->items[i].click_enabled ? 1 : 0);
        WritePrivateProfileStringW(sec, L"click_enabled", tmp, path);
        WritePrivateProfileStringW(sec, L"click_url", cfg->items[i].click_url, path);
        WritePrivateProfileStringW(sec, L"lua_path", cfg->items[i].lua_path, path);

        /* Save params */
        WCHAR pc[16];
        wsprintfW(pc, L"%d", cfg->items[i].param_count);
        WritePrivateProfileStringW(sec, L"param_count", pc, path);
        for (int j = 0; j < cfg->items[i].param_count; j++) {
            WCHAR pk[32], pv[32], pl[32];
            wsprintfW(pk, L"param_key_%d", j);
            wsprintfW(pv, L"param_val_%d", j);
            wsprintfW(pl, L"param_lbl_%d", j);
            WritePrivateProfileStringW(sec, pk, cfg->items[i].params[j].key, path);
            WritePrivateProfileStringW(sec, pv, cfg->items[i].params[j].value, path);
            WritePrivateProfileStringW(sec, pl, cfg->items[i].params[j].label, path);
        }
    }
}