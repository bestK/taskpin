CC = gcc
CXX = g++
RC = windres
VERSION := $(strip $(shell cat version.txt))

SRC_DIR = src
LIB_DIR = lib
LUA_DIR = lib/lua

MODE ?= dev
CFLAGS = -std=c99 -O2 -Wall -Wextra -DUNICODE -D_UNICODE -DWIN32_LEAN_AND_MEAN -DTASKPIN_VERSION=\"$(VERSION)\" -I$(LIB_DIR) -I$(SRC_DIR)
CXXFLAGS = -std=c++17 -O2 -Wall -Wextra -DUNICODE -D_UNICODE -DWIN32_LEAN_AND_MEAN -DTASKPIN_VERSION=\"$(VERSION)\" -I$(LIB_DIR) -I$(SRC_DIR) -Ithird_party/imgui -Ithird_party/imgui/backends
ifeq ($(MODE),dev)
CFLAGS += -DDEV_MODE
CXXFLAGS += -DDEV_MODE
endif
CFLAGS_LUA = -O2 -DLUA_COMPAT_5_3 -DWIN32_LEAN_AND_MEAN
LDFLAGS = -static -mwindows -Wl,--subsystem,windows -municode -lwinhttp -luser32 -lshell32 -lgdi32 -ldwmapi -ld3d11 -ld3dcompiler_47 -ldxgi -limm32 -lole32 -lshlwapi -lcomctl32 -lcomdlg32 -liphlpapi -lmsimg32
TARGET = taskpin.exe

SRCS = $(SRC_DIR)/main.c $(SRC_DIR)/expression.c $(SRC_DIR)/edit_dialog.c \
       $(SRC_DIR)/settings_dialog.c $(SRC_DIR)/main_window.c $(SRC_DIR)/bar_window.c \
       $(SRC_DIR)/market_dialog.c
UI_SRCS = $(SRC_DIR)/ui_window.cpp \
          $(SRC_DIR)/ui_host.cpp \
          $(SRC_DIR)/ui_main_view.cpp \
          $(SRC_DIR)/ui_settings_view.cpp \
          $(SRC_DIR)/ui_market_view.cpp \
          $(SRC_DIR)/ui_edit_view.cpp
IMGUI_SRCS = third_party/imgui/imgui.cpp third_party/imgui/imgui_draw.cpp \
             third_party/imgui/imgui_tables.cpp third_party/imgui/imgui_widgets.cpp \
             third_party/imgui/backends/imgui_impl_win32.cpp \
             third_party/imgui/backends/imgui_impl_dx11.cpp
LIB_SRCS = $(LIB_DIR)/appbar.c $(LIB_DIR)/fetcher.c $(LIB_DIR)/config.c \
           $(LIB_DIR)/json.c $(LIB_DIR)/cJSON.c $(LIB_DIR)/scripting.c $(LIB_DIR)/base64.c \
           $(LIB_DIR)/update.c $(LIB_DIR)/httputil.c $(LIB_DIR)/sysinfo.c \
           $(LIB_DIR)/script_dialog.c $(LIB_DIR)/image.c $(LIB_DIR)/i18n.c
LUA_SRCS = $(wildcard $(LUA_DIR)/*.c)

OBJS = $(SRCS:.c=.o) $(LIB_SRCS:.c=.o) taskpin_res.o
UI_OBJS = $(UI_SRCS:.cpp=.o) $(IMGUI_SRCS:.cpp=.o)
LUA_OBJS = $(LUA_SRCS:.c=.o)

all: $(TARGET)

$(TARGET): $(OBJS) $(UI_OBJS) $(LUA_OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LDFLAGS)

$(SRC_DIR)/%.o: $(SRC_DIR)/%.c
	$(CC) $(CFLAGS) -c -o $@ $<

$(LIB_DIR)/%.o: $(LIB_DIR)/%.c
	$(CC) $(CFLAGS) -c -o $@ $<

$(LUA_DIR)/%.o: $(LUA_DIR)/%.c
	$(CC) $(CFLAGS_LUA) -c -o $@ $<

$(SRC_DIR)/%.o: $(SRC_DIR)/%.cpp
	$(CXX) $(CXXFLAGS) -c -o $@ $<

third_party/imgui/%.o: third_party/imgui/%.cpp
	$(CXX) $(CXXFLAGS) -c -o $@ $<

third_party/imgui/backends/%.o: third_party/imgui/backends/%.cpp
	$(CXX) $(CXXFLAGS) -c -o $@ $<

taskpin_res.o: taskpin.rc taskpin.ico
	$(RC) -o $@ $<

clean:
	rm -f $(SRC_DIR)/*.o $(LIB_DIR)/*.o $(LUA_DIR)/*.o third_party/imgui/*.o third_party/imgui/backends/*.o $(TARGET) taskpin_res.o

.PHONY: all clean
