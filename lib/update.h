#ifndef TASKPIN_UPDATE_H
#define TASKPIN_UPDATE_H

#include <windows.h>

#ifndef TASKPIN_VERSION
#define TASKPIN_VERSION "0.0.0"
#endif

/* Background thread: check GitHub for new version, prompt user if available. */
DWORD WINAPI check_update_thread(LPVOID param);

#endif