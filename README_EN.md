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

- `examples/example.lua` — Basic HTTP + JSON demo
- `examples/zentao_task.lua` — Zentao task monitor
- `examples/newapi_balance.lua` — NewAPI/OneAPI balance query
- `examples/oracle_sessions.lua` — Oracle Exporter session monitor

## Tech Stack

- Pure C (C99), Win32 API
- Lua 5.4 (statically linked)
- Zero third-party dependencies
- Linked libs: winhttp, user32, shell32, gdi32, shlwapi, comctl32, comdlg32