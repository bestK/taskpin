#ifndef TASKPIN_LOGGER_H
#define TASKPIN_LOGGER_H

#define LOG_OFF   0
#define LOG_ERROR 1
#define LOG_INFO  2
#define LOG_DEBUG 3

extern int g_log_level;

void logger_init(int level);
void logger_write_impl(int level, const char *file, int line, const char *func, const char *fmt, ...);

#define logger_write(level, ...) logger_write_impl(level, __FILE__, __LINE__, __func__, __VA_ARGS__)

#endif
