<p align="center">
  <img src="docs/preview.png" alt="TaskPin" width="600">
</p>

<h1 align="center">TaskPin</h1>

<p align="center">
  Pin anything to your Windows taskbar.<br>
  Pure C + Lua scripted, single file 450KB, zero dependencies.
</p>

<p align="center">
  <a href="https://github.com/bestK/taskpin/releases/latest">Download</a> |
  <a href="README.md">中文</a> |
  <a href="docs/LUA_API_EN.md">API Docs</a> |
  <a href="https://github.com/bestK/taskpin-plugins">Plugin Market</a>
</p>

---

## What it does

Write a Lua script, TaskPin displays the result in your taskbar:

```lua
-- Monitor Claude Code working status
return icon("claude.png", 16, 16) .. font(" thinking", "#FFAA00", 9)
```

```lua
-- System resources at a glance
local cpu = sys.cpu()
local mem = sys.memory().percent
return font("CPU:" .. cpu .. "%", "#0F0", 9) .. font(" MEM:" .. mem .. "%", "#FA0", 9)
```

```lua
-- AI API balance
local r = json.decode(http.get("https://api.example.com/balance"))
return font("$" .. r.balance, "#4FC3F7", 10)
```

Click to open a detail panel — supports images, tables, and transparent HUD overlays:

```lua
return bar, true, dialog({
    borderless = true, opacity = 200,
    content = {
        { type = "text", value = "Claude Code", image = "claude.png", image_width = 16, image_height = 16 },
        { type = "table", columns = {"Metric", "Value"}, rows = {{"CPU", "45%"}, {"MEM", "8GB"}} },
    }
})
```

## Features

| | |
|---|---|
| **Taskbar embedded** | Lives inside the taskbar, no desktop space wasted |
| **Lua scripted** | Display anything — built-in HTTP, JSON, system monitoring APIs |
| **Plugin market** | Browse and download community scripts in one click |
| **Rich text + images** | Multi-color text, PNG/GIF animation, alignment, two-line display |
| **Popup dialogs** | Click to expand detail panels with images, tables, HUD overlays |
| **Multiple bars** | Pin multiple scripts side by side, each refreshes independently |
| **Zero dependencies** | Pure C + Win32 API + Lua 5.4 statically linked, single file ~450KB |
| **Auto update** | Silent version check, download, replace, and restart |

## Quick Start

1. Download the [latest release](https://github.com/bestK/taskpin/releases/latest)
2. Run `taskpin.exe`
3. Double-click the taskbar strip → management window opens
4. Click **Market** to browse plugins, or **Add** to add scripts manually
5. **Pin to Bar** to display

## Example Scripts

| Script | Purpose |
|--------|---------|
| [`claude_status`](examples/claude_status.lua) | Claude Code real-time working status |
| [`system_monitor`](examples/system_monitor.lua) | CPU + memory + network speed |
| [`net_monitor`](examples/net_monitor.lua) | Network process traffic monitor |
| [`hud_clock`](examples/hud_clock.lua) | Desktop floating clock (transparent + clickthrough) |
| [`newapi_balance`](examples/newapi_balance.lua) | AI API balance query |
| [`zentao_task`](examples/zentao_task.lua) | Zentao pending tasks |
| [`oracle_sessions`](examples/oracle_sessions.lua) | Oracle database session monitor |

More scripts at the [plugin repository](https://github.com/bestK/taskpin-plugins).

## Write a script

```lua
-- @param city string City name
-- @refresh 60000

local r = json.decode(http.get("https://wttr.in/" .. args.city .. "?format=j1"))
local temp = r.current_condition[1].temp_C
local desc = r.current_condition[1].weatherDesc[1].value

return font(temp .. "°C " .. desc, "#4FC3F7", 9), true, dialog({
    title = args.city,
    width = 280, height = 120,
    content = {
        { type = "text", value = args.city .. " " .. temp .. "°C", size = 14, bold = true },
        { type = "text", value = desc, color = "#AAAAAA", size = 10 },
    }
})
```

`@param` declares UI input fields, `@refresh` sets the interval. That's it.

## Documentation

- [Lua API 参考（中文）](docs/LUA_API.md)
- [Lua API Reference (English)](docs/LUA_API_EN.md)

## Build

```bash
# MinGW-w64 + GNU Make
make
```

## License

[MIT](LICENSE)
