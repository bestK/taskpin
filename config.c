#include "config.h"
#include <shlwapi.h>
#include <stdio.h>

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

    if (cfg->count > CFG_MAX_ITEMS) cfg->count = CFG_MAX_ITEMS;

    for (int i = 0; i < cfg->count; i++) {
        WCHAR sec[32];
        wsprintfW(sec, L"Item_%d", i);

        GetPrivateProfileStringW(sec, L"name", L"Untitled",
            cfg->items[i].name, CFG_MAX_NAME, path);
        GetPrivateProfileStringW(sec, L"url", L"http://localhost:8080/status",
            cfg->items[i].url, CFG_MAX_URL, path);
        cfg->items[i].interval_ms = (DWORD)GetPrivateProfileIntW(sec, L"interval_ms", 5000, path);
        GetPrivateProfileStringW(sec, L"field_expr", L"",
            cfg->items[i].field_expr, CFG_MAX_EXPR, path);
        cfg->items[i].click_enabled = GetPrivateProfileIntW(sec, L"click_enabled", 0, path);
        GetPrivateProfileStringW(sec, L"click_url", L"",
            cfg->items[i].click_url, CFG_MAX_URL, path);
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

    for (int i = 0; i < cfg->count; i++) {
        WCHAR sec[32];
        wsprintfW(sec, L"Item_%d", i);

        WritePrivateProfileStringW(sec, L"name", cfg->items[i].name, path);
        WritePrivateProfileStringW(sec, L"url", cfg->items[i].url, path);

        wsprintfW(tmp, L"%u", cfg->items[i].interval_ms);
        WritePrivateProfileStringW(sec, L"interval_ms", tmp, path);

        WritePrivateProfileStringW(sec, L"field_expr", cfg->items[i].field_expr, path);

        wsprintfW(tmp, L"%d", cfg->items[i].click_enabled ? 1 : 0);
        WritePrivateProfileStringW(sec, L"click_enabled", tmp, path);
        WritePrivateProfileStringW(sec, L"click_url", cfg->items[i].click_url, path);
    }
}