CC = gcc
RC = windres
CFLAGS = -std=c99 -O2 -Wall -Wextra -DUNICODE -D_UNICODE -DWIN32_LEAN_AND_MEAN
LDFLAGS = -mwindows -municode -lwinhttp -luser32 -lshell32 -lgdi32 -lshlwapi -lcomctl32
TARGET = taskpin.exe
SRCS = main.c appbar.c fetcher.c config.c json.c
OBJS = $(SRCS:.c=.o) taskpin_res.o

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

taskpin_res.o: taskpin.rc taskpin.ico
	$(RC) -o $@ $<

clean:
	del /Q $(OBJS) $(TARGET) 2>nul || true

.PHONY: all clean