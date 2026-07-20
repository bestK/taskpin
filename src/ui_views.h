#ifndef TASKPIN_UI_VIEWS_H
#define TASKPIN_UI_VIEWS_H

#include <windows.h>
#include "ui_window.h"

/* Main list view (drawn by host each frame) */
void ui_main_view_draw(int *selected_item);
void ui_main_process_deferred(void);

/* Independent modal windows — each owns its own HWND */
void ui_settings_show(HWND parent, UiWindow *share_device);
void ui_market_show(HWND parent, UiWindow *share_device);
void ui_edit_show(HWND parent, UiWindow *share_device, int item_index, int *selected_item);

/* Main host device window (for sharing D3D device with dialogs) */
UiWindow *ui_host_window(void);

#endif
