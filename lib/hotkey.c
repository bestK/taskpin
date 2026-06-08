#include "hotkey.h"
#include "logger.h"
#include "image.h"
#include <stdlib.h>
#include <string.h>
#include <shellapi.h>

static HotkeyEntry g_hotkeys[HOTKEY_MAX];
static int g_hotkey_count = 0;

void hotkey_init(void) {
    memset(g_hotkeys, 0, sizeof(g_hotkeys));
    g_hotkey_count = 0;
}

void hotkey_shutdown(void) {
    for (int i = 0; i < g_hotkey_count; i++) {
        if (g_hotkeys[i].registered) {
            UnregisterHotKey(g_hotkeys[i].owner, g_hotkeys[i].id);
        }
    }
    g_hotkey_count = 0;
}

/* --- Parse hotkey string --- */

static UINT parse_vk(const char *key) {
    if (!key || !key[0]) return 0;
    if (strlen(key) == 1) {
        char c = key[0];
        if (c >= 'A' && c <= 'Z') return (UINT)c;
        if (c >= 'a' && c <= 'z') return (UINT)(c - 32);
        if (c >= '0' && c <= '9') return (UINT)c;
    }
    if (_stricmp(key, "Space") == 0) return VK_SPACE;
    if (_stricmp(key, "Enter") == 0) return VK_RETURN;
    if (_stricmp(key, "Tab") == 0) return VK_TAB;
    if (_stricmp(key, "Esc") == 0) return VK_ESCAPE;
    if (_stricmp(key, "Escape") == 0) return VK_ESCAPE;
    if (_stricmp(key, "Up") == 0) return VK_UP;
    if (_stricmp(key, "Down") == 0) return VK_DOWN;
    if (_stricmp(key, "Left") == 0) return VK_LEFT;
    if (_stricmp(key, "Right") == 0) return VK_RIGHT;
    if (key[0] == 'F' || key[0] == 'f') {
        int n = atoi(key + 1);
        if (n >= 1 && n <= 12) return VK_F1 + n - 1;
    }
    return 0;
}

BOOL hotkey_parse(const char *str, UINT *out_mod, UINT *out_vk) {
    if (!str || !str[0]) return FALSE;
    *out_mod = 0;
    *out_vk = 0;

    char buf[128];
    strncpy(buf, str, 127); buf[127] = '\0';

    char *token = strtok(buf, "+");
    char *last_token = NULL;
    while (token) {
        while (*token == ' ') token++;
        char *end = token + strlen(token) - 1;
        while (end > token && *end == ' ') *end-- = '\0';

        if (_stricmp(token, "Ctrl") == 0 || _stricmp(token, "Control") == 0)
            *out_mod |= MOD_CONTROL;
        else if (_stricmp(token, "Alt") == 0)
            *out_mod |= MOD_ALT;
        else if (_stricmp(token, "Shift") == 0)
            *out_mod |= MOD_SHIFT;
        else if (_stricmp(token, "Win") == 0)
            *out_mod |= MOD_WIN;
        else
            last_token = token;

        token = strtok(NULL, "+");
    }

    if (last_token) *out_vk = parse_vk(last_token);
    return (*out_vk != 0);
}

/* --- Register/Unregister --- */

int hotkey_register(HWND hwnd, int bar_index, UINT mod, UINT vk) {
    if (g_hotkey_count >= HOTKEY_MAX) return 0;
    int id = HOTKEY_ID_BASE + g_hotkey_count;

    if (!RegisterHotKey(hwnd, id, mod | MOD_NOREPEAT, vk)) {
        logger_write(LOG_ERROR, "hotkey register failed: mod=0x%x vk=0x%x err=%lu",
            mod, vk, GetLastError());
        return 0;
    }

    HotkeyEntry *e = &g_hotkeys[g_hotkey_count++];
    e->mod = mod;
    e->vk = vk;
    e->owner = hwnd;
    e->bar_index = bar_index;
    e->id = id;
    e->registered = TRUE;
    return id;
}

void hotkey_unregister_bar(int bar_index) {
    for (int i = g_hotkey_count - 1; i >= 0; i--) {
        if (g_hotkeys[i].bar_index == bar_index && g_hotkeys[i].registered) {
            UnregisterHotKey(g_hotkeys[i].owner, g_hotkeys[i].id);
            g_hotkeys[i].registered = FALSE;
            g_hotkeys[i] = g_hotkeys[--g_hotkey_count];
        }
    }
}

/* --- Selection capture --- */

static void backup_clipboard(HANDLE *hBackup, UINT *fmt) {
    *hBackup = NULL;
    *fmt = 0;
    if (!OpenClipboard(NULL)) return;

    if (IsClipboardFormatAvailable(CF_UNICODETEXT)) {
        *fmt = CF_UNICODETEXT;
        HANDLE h = GetClipboardData(CF_UNICODETEXT);
        if (h) {
            SIZE_T sz = GlobalSize(h);
            *hBackup = GlobalAlloc(GMEM_MOVEABLE, sz);
            if (*hBackup) {
                void *src = GlobalLock(h);
                void *dst = GlobalLock(*hBackup);
                if (src && dst) memcpy(dst, src, sz);
                GlobalUnlock(h);
                GlobalUnlock(*hBackup);
            }
        }
    } else if (IsClipboardFormatAvailable(CF_HDROP)) {
        *fmt = CF_HDROP;
        HANDLE h = GetClipboardData(CF_HDROP);
        if (h) {
            SIZE_T sz = GlobalSize(h);
            *hBackup = GlobalAlloc(GMEM_MOVEABLE, sz);
            if (*hBackup) {
                void *src = GlobalLock(h);
                void *dst = GlobalLock(*hBackup);
                if (src && dst) memcpy(dst, src, sz);
                GlobalUnlock(h);
                GlobalUnlock(*hBackup);
            }
        }
    }
    CloseClipboard();
}

static void restore_clipboard(HANDLE hBackup, UINT fmt) {
    if (!hBackup) return;
    if (!OpenClipboard(NULL)) { GlobalFree(hBackup); return; }
    EmptyClipboard();
    SetClipboardData(fmt, hBackup);
    CloseClipboard();
}

static void simulate_ctrl_c(void) {
    INPUT inputs[4] = {0};
    inputs[0].type = INPUT_KEYBOARD;
    inputs[0].ki.wVk = VK_CONTROL;
    inputs[1].type = INPUT_KEYBOARD;
    inputs[1].ki.wVk = 'C';
    inputs[2].type = INPUT_KEYBOARD;
    inputs[2].ki.wVk = 'C';
    inputs[2].ki.dwFlags = KEYEVENTF_KEYUP;
    inputs[3].type = INPUT_KEYBOARD;
    inputs[3].ki.wVk = VK_CONTROL;
    inputs[3].ki.dwFlags = KEYEVENTF_KEYUP;
    SendInput(4, inputs, sizeof(INPUT));
}

void hotkey_get_selection(SelectionResult *result) {
    memset(result, 0, sizeof(*result));

    HANDLE hBackup = NULL;
    UINT backup_fmt = 0;
    backup_clipboard(&hBackup, &backup_fmt);

    /* Clear clipboard before simulating copy */
    if (OpenClipboard(NULL)) { EmptyClipboard(); CloseClipboard(); }

    simulate_ctrl_c();
    Sleep(80);

    /* Read what was copied */
    if (!OpenClipboard(NULL)) {
        restore_clipboard(hBackup, backup_fmt);
        return;
    }

    if (IsClipboardFormatAvailable(CF_UNICODETEXT)) {
        HANDLE h = GetClipboardData(CF_UNICODETEXT);
        if (h) {
            WCHAR *wstr = (WCHAR *)GlobalLock(h);
            if (wstr && wstr[0]) {
                result->type = 1;
                int len = WideCharToMultiByte(CP_UTF8, 0, wstr, -1, NULL, 0, NULL, NULL);
                result->text = (char *)malloc(len);
                if (result->text)
                    WideCharToMultiByte(CP_UTF8, 0, wstr, -1, result->text, len, NULL, NULL);
            }
            GlobalUnlock(h);
        }
    } else if (IsClipboardFormatAvailable(CF_HDROP)) {
        HANDLE h = GetClipboardData(CF_HDROP);
        if (h) {
            HDROP hDrop = (HDROP)GlobalLock(h);
            if (hDrop) {
                int count = DragQueryFileW(hDrop, 0xFFFFFFFF, NULL, 0);
                if (count > 0) {
                    result->type = 2;
                    result->file_count = count;
                    result->files = (WCHAR **)calloc(count + 1, sizeof(WCHAR *));
                    for (int i = 0; i < count; i++) {
                        WCHAR path[MAX_PATH];
                        DragQueryFileW(hDrop, i, path, MAX_PATH);
                        result->files[i] = _wcsdup(path);
                    }
                }
            }
            GlobalUnlock(h);
        }
    } else if (IsClipboardFormatAvailable(CF_DIB) || IsClipboardFormatAvailable(CF_BITMAP)) {
        result->type = 3;
        /* Save bitmap to temp file */
        WCHAR tmp[MAX_PATH];
        GetTempPathW(MAX_PATH, tmp);
        lstrcatW(tmp, L"taskpin_selection.bmp");
        WideCharToMultiByte(CP_UTF8, 0, tmp, -1, result->image_path, MAX_PATH, NULL, NULL);
    }

    CloseClipboard();
    restore_clipboard(hBackup, backup_fmt);
}

void hotkey_free_selection(SelectionResult *result) {
    if (result->text) { free(result->text); result->text = NULL; }
    if (result->files) {
        for (int i = 0; i < result->file_count; i++) free(result->files[i]);
        free(result->files);
        result->files = NULL;
    }
}
