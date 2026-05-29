#ifndef TASKPIN_UI_H
#define TASKPIN_UI_H

#include <windows.h>
#include <windowsx.h>
#include <commctrl.h>
#include <commdlg.h>
#include <shellapi.h>
#include <winhttp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "config.h"
#include "appbar.h"
#include "fetcher.h"
#include "json.h"
#include "scripting.h"
#include "script_dialog.h"
#include "update.h"

/* Timer IDs */
#define IDT_REFRESH        1
#define IDT_SCROLL         2
#define IDT_BORDER         3
#define IDT_ANIM           4
#define SCROLL_SPEED       2
#define SCROLL_INTERVAL    50
#define ANIM_INTERVAL      80

/* Menu IDs */
#define IDM_SHOW    3001
#define IDM_EXIT    3002
#define IDM_UNPIN   3003

/* Main window control IDs */
#define IDB_ADD     4001
#define IDB_DEL     4002
#define IDB_SELECT  4003
#define IDB_SETTINGS 4004
#define IDB_MARKET  4005
#define IDC_LIST    4010

/* Edit dialog control IDs */
#define IDE_NAME    5001
#define IDE_URL     5002
#define IDE_INT     5003
#define IDE_EXPR    5004
#define IDB_LOAD    5005
#define IDC_TREE    5006
#define IDC_PREVIEW 5007
#define IDB_OK      5008
#define IDB_CANCEL  5009

/* Bar instance (one per pinned item) */
#define MAX_BARS 16

typedef struct {
    HWND  hwnd;
    WCHAR lua_path[MAX_PATH];
    ParamEntry params[CFG_MAX_PARAMS];
    int   param_count;
    ScriptResult result;
    BOOL  success;
} LuaContext;

typedef struct {
    int item_index;
    HWND hwnd;
    WCHAR display[FETCH_BUF_SIZE];
    DisplayContent rich;
    ScriptResult script_result;
    int scroll_offset;
    int text_width;
    BOOL fetching;
    BOOL show_border;
    char last_response[FETCH_BUF_SIZE];
} BarInstance;

extern BarInstance g_bars[MAX_BARS];
extern int g_bar_count;

/* Shared global state */
extern TaskPinConfig g_cfg;
extern HFONT g_font;
extern HWND g_main_hwnd;
extern HWND g_listview;
extern HINSTANCE g_hinst;

/* expression.c */
void extract_fields(const char *raw, const WCHAR *expr, WCHAR *out, int out_size);

/* bar_window.c */
void start_fetch(BarInstance *bar);
void bars_create_all(void);
void bars_destroy_all(void);
LRESULT CALLBACK bar_wnd_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);

/* main_window.c */
void listview_populate(void);
void show_main_window(void);
LRESULT CALLBACK main_wnd_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);

/* edit_dialog.c */
void show_edit_dialog(HWND parent, int item_idx);

/* settings_dialog.c */
void show_settings_dialog(HWND parent);

/* market_dialog.c */
void show_market_dialog(HWND parent);

#endif