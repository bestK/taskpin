#ifndef TASKPIN_HOTKEY_H
#define TASKPIN_HOTKEY_H

#include <windows.h>

#ifdef __cplusplus
extern "C" {
#endif

#define HOTKEY_MAX 16
#define HOTKEY_ID_BASE 0x7000

typedef struct {
    UINT mod;
    UINT vk;
    HWND owner;
    int  bar_index;
    int  id;
    BOOL registered;
} HotkeyEntry;

void hotkey_init(void);
void hotkey_shutdown(void);

/* Parse "@hotkey Ctrl+Shift+T" style string. Returns TRUE on success. */
BOOL hotkey_parse(const char *str, UINT *out_mod, UINT *out_vk);

/* Register a hotkey for a bar. Returns assigned hotkey ID or 0 on failure. */
int  hotkey_register(HWND hwnd, int bar_index, UINT mod, UINT vk);

/* Unregister all hotkeys for a bar. */
void hotkey_unregister_bar(int bar_index);

/* Get the selection from the currently focused window.
   Backs up clipboard, simulates Ctrl+C, reads result, restores clipboard.
   Caller must free out_text. out_files is a null-terminated array (caller frees each + array). */
typedef struct {
    int   type;          /* 0=none, 1=text, 2=files, 3=image */
    char *text;          /* UTF-8 text (caller frees) */
    WCHAR **files;       /* null-terminated file path array (caller frees each + array) */
    int   file_count;
    char  image_path[MAX_PATH]; /* temp png path if image */
} SelectionResult;

void hotkey_get_selection(SelectionResult *result);
void hotkey_free_selection(SelectionResult *result);

#ifdef __cplusplus
}
#endif

#endif
