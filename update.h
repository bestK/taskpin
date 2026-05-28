#ifndef TASKPIN_UPDATE_H
#define TASKPIN_UPDATE_H

#include <windows.h>

#define TASKPIN_VERSION "1.2.0"

/* Background thread: check GitHub for new version, prompt user if available. */
DWORD WINAPI check_update_thread(LPVOID param);

#endif