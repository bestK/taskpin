CC = gcc
RC = windres
VERSION = $(strip $(file < version.txt))

SRC_DIR = src
LIB_DIR = lib
LUA_DIR = lib/lua

CFLAGS = -std=c99 -O2 -Wall -Wextra -DUNICODE -D_UNICODE -DWIN32_LEAN_AND_MEAN -DTASKPIN_VERSION=\"$(VERSION)\" -I$(LIB_DIR) -I$(SRC_DIR)
CFLAGS_LUA = -O2 -DLUA_COMPAT_5_3 -DWIN32_LEAN_AND_MEAN
LDFLAGS = -static -mwindows -municode -lwinhttp -luser32 -lshell32 -lgdi32 -lshlwapi -lcomctl32 -lcomdlg32 -liphlpapi -lmsimg32 -lole32 -lwininet
TARGET = taskpin.exe

SRCS = $(SRC_DIR)/main.c $(SRC_DIR)/expression.c $(SRC_DIR)/edit_dialog.c \
       $(SRC_DIR)/settings_dialog.c $(SRC_DIR)/main_window.c $(SRC_DIR)/bar_window.c \
       $(SRC_DIR)/market_dialog.c
LIB_SRCS = $(LIB_DIR)/appbar.c $(LIB_DIR)/fetcher.c $(LIB_DIR)/config.c \
           $(LIB_DIR)/json.c $(LIB_DIR)/scripting.c $(LIB_DIR)/base64.c \
           $(LIB_DIR)/update.c $(LIB_DIR)/httputil.c $(LIB_DIR)/sysinfo.c \
           $(LIB_DIR)/script_dialog.c $(LIB_DIR)/image.c $(LIB_DIR)/event.c \
           $(LIB_DIR)/logger.c
LUA_SRCS = $(wildcard $(LUA_DIR)/*.c)

OBJS = $(SRCS:.c=.o) $(LIB_SRCS:.c=.o) taskpin_res.o
LUA_OBJS = $(LUA_SRCS:.c=.o)

all: $(TARGET)

$(TARGET): $(OBJS) $(LUA_OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

$(SRC_DIR)/%.o: $(SRC_DIR)/%.c
	$(CC) $(CFLAGS) -c -o $@ $<

$(LIB_DIR)/%.o: $(LIB_DIR)/%.c
	$(CC) $(CFLAGS) -c -o $@ $<

$(LUA_DIR)/%.o: $(LUA_DIR)/%.c
	$(CC) $(CFLAGS_LUA) -c -o $@ $<

taskpin_res.o: taskpin.rc taskpin.ico
	$(RC) -o $@ $<

clean:
	rm -f $(SRC_DIR)/*.o $(LIB_DIR)/*.o $(LUA_DIR)/*.o $(TARGET) taskpin_res.o

.PHONY: all clean