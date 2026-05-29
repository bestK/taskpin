# TaskPin

[中文](README.md)

A Windows taskbar-embedded information display tool. Pure C + Win32 API + Lua 5.4, single file ~450KB, zero external dependencies.

![preview](docs/preview.png)

## Features

- **Taskbar Embedding** — Window embedded directly inside the bottom taskbar
- **Multi-Bar Support** — Pin multiple items simultaneously, each with independent display and refresh
- **Dual Item Modes** — URL mode (HTTP GET + Lua/template processing) or Lua File mode (script handles everything)
- **Rich Text Rendering** — `font(text, color, size, align)` with per-segment color, size, left/right/center alignment, 2-line display
- **System Monitor API** — Built-in `sys.cpu/memory/disk/battery/net_speed` functions
- **Lua 5.4 Scripting** — Built-in `json.decode`, `http.get/post/put/delete` (with session cookies)
- **@param Declarations** — Scripts declare parameters in header comments, UI auto-generates input fields
- **Custom Headers** — URL mode supports multiline request headers
- **Template Engine** — `$.path` JSONPath interpolation + full Lua code, auto fallback
- **Click to Open** — Scripts return 3 values: display text, clickable flag, URL
- **Mouse Wheel Adjust** — Hover on bar: scroll to resize width, Shift+scroll to move horizontally
- **Auto Scroll** — Long text scrolls horizontally (can be disabled)
- **Silent Auto-Update** — Detects new version, downloads, replaces exe, restarts automatically
- **Per-Item Appearance** — Each item can have its own width, position, background color
- **Configurable Appearance** — Font size/color, background color, position, width (global defaults)
- **Start with Windows** — One-click toggle in Settings

## Quick Start

1. Download the [latest release](https://github.com/bestK/taskpin/releases/latest)
2. Run `taskpin.exe`
3. Double-click the taskbar strip to open the management window
4. Add an item (URL or Lua File type)
5. Click "Pin to Bar" to select which item to display

## Building

Requires MinGW-w64 (gcc) + GNU Make:

```bash
make
```

## Project Structure

```
main.c          Main window / message loop / edit dialog / settings
appbar.c/h      Taskbar embedding (SetParent)
fetcher.c/h     WinHTTP async fetch (URL mode)
httputil.c/h    Unified sync HTTP module
scripting.c/h   Lua engine wrapper + built-in http/json
update.c/h      Auto-update check + silent replace
config.c/h      INI read/write (UTF-16LE)
json.c/h        Lightweight JSON parser + JSONPath
base64.c/h      Base64 encode/decode
lua/            Lua 5.4 source
examples/       Example Lua scripts
```

## Example Scripts

| File | Description |
|------|-------------|
| [`example.lua`](examples/example.lua) | Getting started: HTTP request + JSON parsing + parameter declarations |
| [`newapi_balance.lua`](examples/newapi_balance.lua) | Display AI API account balance in taskbar |
| [`rich_text_demo.lua`](examples/rich_text_demo.lua) | font() rich text demo: colors, multi-line, alignment |
| [`zentao_task.lua`](examples/zentao_task.lua) | Zentao project management: pending task count with detail popup |
| [`oracle_sessions.lua`](examples/oracle_sessions.lua) | Oracle database session monitor, multi-instance, color alerts |
| [`system_monitor.lua`](examples/system_monitor.lua) | System monitor: network speed + CPU + memory using sys.* API |
| [`net_monitor.lua`](examples/net_monitor.lua) | Network process monitor: active connections with traffic per process |
| [`claude_status.lua`](examples/claude_status.lua) | Claude Code real-time status indicator, reads session JSONL files |

### Usage

1. Open the TaskPin management window, click **Add**
2. Select **Lua File** type, choose a script from `examples/`
3. If the script has `@param` declarations, fill in the parameters
4. Click **Pin to Bar** to display it in the taskbar

## Documentation

- [Lua API 参考（中文）](docs/LUA_API.md)
- [Lua API Reference (English)](docs/LUA_API_EN.md)

## Tech Stack

- Pure C (C99), Win32 API
- Lua 5.4 (statically linked)
- Zero third-party dependencies
- Linked libs: winhttp, user32, shell32, gdi32, shlwapi, comctl32, comdlg32