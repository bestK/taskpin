#ifndef TASKPIN_EVENT_H
#define TASKPIN_EVENT_H

#include <windows.h>

#define EVENT_SOURCE_LEN  128
#define EVENT_NAME_LEN    128
#define EVENT_JSON_LEN    2048
#define COPYDATA_EVENT_ID 0x5450

typedef struct {
    char source[EVENT_SOURCE_LEN];
    char name[EVENT_NAME_LEN];
    char params_json[EVENT_JSON_LEN];
    BOOL active;
} TaskPinEvent;

extern TaskPinEvent g_event;

void event_init(void);
void event_set(const char *source, const char *name, const char *json);
void event_clear(void);
void event_push_lua(void *L);
void event_send_ipc(const char *source, const char *name, const char *json);
void event_receive(const void *data, int len);
void event_get_response_file(char *out, int out_size);

#endif
