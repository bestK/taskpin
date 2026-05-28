CC = gcc
RC = windres
VERSION = $(strip $(file < version.txt))
CFLAGS = -std=c99 -O2 -Wall -Wextra -DUNICODE -D_UNICODE -DWIN32_LEAN_AND_MEAN -DTASKPIN_VERSION=\"$(VERSION)\"
CFLAGS_LUA = -O2 -DLUA_COMPAT_5_3 -DWIN32_LEAN_AND_MEAN
LDFLAGS = -mwindows -municode -lwinhttp -luser32 -lshell32 -lgdi32 -lshlwapi -lcomctl32 -lcomdlg32
TARGET = taskpin.exe

SRCS = main.c appbar.c fetcher.c config.c json.c scripting.c base64.c update.c httputil.c
OBJS = $(SRCS:.c=.o) taskpin_res.o

LUA_SRCS = $(wildcard lua/*.c)
LUA_OBJS = $(LUA_SRCS:.c=.o)

all: $(TARGET)

$(TARGET): $(OBJS) $(LUA_OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

lua/%.o: lua/%.c
	$(CC) $(CFLAGS_LUA) -c -o $@ $<

taskpin_res.o: taskpin.rc taskpin.ico
	$(RC) -o $@ $<

clean:
	del /Q *.o lua\*.o $(TARGET) 2>nul || true

.PHONY: all clean