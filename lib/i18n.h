#ifndef TASKPIN_I18N_H
#define TASKPIN_I18N_H

#include <windows.h>

#ifdef __cplusplus
extern "C" {
#endif

void i18n_init(void);
const WCHAR *tr(const char *key);
const char *i18n_lang(void);

#ifdef __cplusplus
}
#endif

#endif
