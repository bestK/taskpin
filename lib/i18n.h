#ifndef TASKPIN_I18N_H
#define TASKPIN_I18N_H

#include <windows.h>

/* Initialize i18n system. Call once at startup.
   Detects user language and loads the corresponding lang JSON file.
   Falls back to English if the language file is not found. */
void i18n_init(void);

/* Translate a key to localized wide string.
   Returns the translated string, or the key itself if not found. */
const WCHAR *tr(const char *key);

/* Get current language code (e.g. "zh-CN", "en-US") */
const char *i18n_lang(void);

#endif
