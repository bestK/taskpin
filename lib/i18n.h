#ifndef TASKPIN_I18N_H
#define TASKPIN_I18N_H

#include <windows.h>

#ifdef __cplusplus
extern "C" {
#endif

void i18n_init(void);

/* Wide string for Win32 window titles / MessageBox */
const WCHAR *tr(const char *key);

/* UTF-8 string for ImGui labels */
const char *tr8(const char *key);

const char *i18n_lang(void);

#ifdef __cplusplus
}
#endif

#endif
