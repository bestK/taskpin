#ifndef TASKPIN_APPBAR_H
#define TASKPIN_APPBAR_H

#include <windows.h>

/* Embed hwnd into the Windows taskbar as a child window.
   Returns TRUE on success. width = desired pixel width. */
BOOL appbar_embed(HWND hwnd, int width, int cfg_x, int cfg_y);

/* Remove from taskbar (restore parent) before destroy */
void appbar_remove(HWND hwnd);

#endif