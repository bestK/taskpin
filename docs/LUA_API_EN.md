# TaskPin Lua Script API

TaskPin provides the following built-in APIs for Lua scripts.

## Script Return Values

Scripts control the taskbar display via `return`:

```lua
-- Return 1: display text (string or font() span) [required]
-- Return 2: clickable flag (boolean) [optional]
-- Return 3: click URL (string) [optional]

return "Hello World", true, "https://example.com"
```

---

## font(text, color, size, align)

Creates a rich text span with custom color, font size, and alignment.

| Parameter | Type | Description |
|-----------|------|-------------|
| text | string | Display text (required). Pass `"\n"` for line break |
| color | string\|nil | Color in `"#RGB"` or `"#RRGGBB"` format, nil for default |
| size | number\|nil | Font size in points, nil for default |
| align | string\|nil | Alignment: `"left"` (default), `"right"`, `"center"` |

**Returns**: A span object. Use `..` to concatenate multiple spans.

```lua
-- Single line, multiple colors
return font("CPU:", "#888", 8) .. font("45%", "#FF0000", 14)

-- Two lines
return font("Line1", "#FFF", 9) .. font("\n") .. font("Line2", "#0F0", 9)

-- Left-right layout
return font("Status OK", "#0F0", 9) .. font("12:30", "#888", 9, "right")

-- Two lines with alignment
return font("CPU: 45%", "#0F0", 9) .. font("12:30", "#888", 8, "right")
    .. font("\n")
    .. font("MEM: 72%", "#FA0", 9) .. font("05/28", "#888", 8, "right")
```

**Limits**: Max 2 lines (bar height is 40px), max 32 spans.

---

## icon(source, width, height, align)

Creates an image span for embedding in the taskbar. Supports local file paths, URLs, data URIs (base64), and animated GIFs.

| Parameter | Type | Description |
|-----------|------|-------------|
| source | string | Image source: relative/absolute path, URL, or `data:image/png;base64,...` |
| width | number\|nil | Display width in px, default 16 |
| height | number\|nil | Display height in px, default 16 |
| align | string\|nil | Alignment: `"left"` (default), `"right"`, `"center"` |

**Returns**: A span object. Use `..` to concatenate with other spans.

```lua
-- Local PNG
return icon("examples/logo.png", 16, 16) .. font(" Hello", "#FFF", 9)

-- Animated GIF (plays automatically with refresh interval)
return icon("spinner.gif", 14, 14) .. font(" Loading", "#AAA", 8)

-- Inline base64
return icon("data:image/png;base64,iVBOR...", 16, 16)
```

---

## dialog(spec)

Creates a popup dialog shown on click. Used as the 3rd return value from a script.

| Parameter | Type | Description |
|-----------|------|-------------|
| spec | table | Dialog configuration table |

**spec fields**:

| Field | Type | Description |
|-------|------|-------------|
| title | string | Window title |
| width | number | Window width in px, default 400 |
| height | number | Window height in px, default 300 |
| refresh | number | Auto-refresh interval in seconds, 0 or omit to disable |
| borderless | boolean | No title bar / no border / no scrollbar, default false |
| clickthrough | boolean | Mouse clicks pass through (for HUD overlays), default false |
| x | number | Window X position in px, -1 or omit for auto positioning |
| y | number | Window Y position in px, -1 or omit for auto positioning |
| opacity | number | Window opacity 0-255 (0=fully transparent, 255=opaque), default 255 |
| transparent_bg | boolean | Transparent background (no window fill), default false |
| content | table | Array of content items (max 8) |

**Borderless mode**:
- Hold Shift + drag to move the window
- Hold Shift + scroll wheel to resize
- Press ESC while hovering to close
- Hidden from taskbar and Alt+Tab

**content item types**:

| type | Fields | Description |
|------|--------|-------------|
| `"text"` | value, color, size, bold, image, image_width, image_height | Text line (optional inline image) |
| `"image"` | source, width, height, src_x, src_y, src_w, src_h | Standalone image block (supports sprite sheet cropping) |
| `"hr"` | — | Horizontal separator |
| `"table"` | columns, rows | Table (max 6 columns × 24 rows) |
| `"button"` | value, cmd, url, color, bg, size | Clickable button |

**Image + text example**:

```lua
{ type = "text", value = "Claude Code", color = "#D97757", size = 12,
  image = "claude.png", image_width = 16, image_height = 16 },
{ type = "image", source = "logo.png", width = 64, height = 64 },
```

**Sprite sheet cropping** (extract sub-region from a larger image):

```lua
{ type = "image", source = "sprites.png",
  src_x = 64, src_y = 0, src_w = 32, src_h = 32,  -- source crop region
  width = 96, height = 96 },                         -- display size
```

**Button example**:

```lua
{ type = "button", value = "Open Page", url = "https://example.com",
  color = "#FFFFFF", bg = "#336699", size = 10 },
{ type = "button", value = "Run Command", cmd = "notepad.exe",
  color = "#FFF", bg = "#444", size = 10 },
```

```lua
local info = dialog({
    title = "Status",
    width = 320, height = 200,
    refresh = 5,
    content = {
        { type = "text", value = "Title", color = "#FF8800", size = 12, bold = true },
        { type = "hr" },
        { type = "text", value = "Content line", color = "#CCCCCC", size = 10 },
        { type = "table", columns = {"Name", "Value"},
          rows = {{"CPU", "45%"}, {"MEM", "72%"}} },
    }
})

return font("Status", "#0F0", 9), true, info
```

**HUD overlay example**:

```lua
local hud = dialog({
    width = 200, height = 80,
    refresh = 1,
    borderless = true,
    clickthrough = true,
    opacity = 180,
    content = {
        { type = "text", value = os.date("%H:%M:%S"), color = "#FFFFFF", size = 24, bold = true },
    }
})

return font("Clock", "#FFF", 9), true, hud
```

---

## button(text, cmd, bg, color, size)

Creates a clickable button span for the taskbar or dialog. Clicking executes a command or opens a URL.

| Parameter | Type | Description |
|-----------|------|-------------|
| text | string | Button text (required) |
| cmd | string\|nil | Command or URL to execute on click |
| bg | string\|nil | Background color in `"#RRGGBB"` format |
| color | string\|nil | Text color in `"#RRGGBB"` format |
| size | number\|nil | Font size in points |

**Returns**: A span object. Use `..` to concatenate with other spans.

```lua
return font("Status: OK", "#0F0", 9) .. button("Open", "https://example.com", "#333", "#FFF", 9)
```

---

## log(...)

Writes to the script log. Accepts any number of arguments, separated by tabs in output.

```lua
log("request started", url)
local data = json.decode(http.get(url))
log("result:", data.status, data.message)
```

---

## json.decode(str)

Parses a JSON string into a Lua table.

```lua
local data = json.decode(response)
print(data.name)       -- access object fields
print(data[1].id)      -- access array elements
```

## json.encode(value [, pretty])

Encodes a Lua table into a JSON string.

| Parameter | Type | Description |
|-----------|------|-------------|
| value | any | Lua value to encode (table, string, number, etc.) |
| pretty | boolean\|nil | Whether to format with indentation, default false |

**Returns**: JSON string.

```lua
local t = { name = "test", value = 42, tags = {"a", "b"} }
local str = json.encode(t)          -- compact output
local pretty = json.encode(t, true)  -- formatted output
```

---

## http.get(url [, body, headers])

Sends a synchronous HTTP GET request.

| Parameter | Type | Description |
|-----------|------|-------------|
| url | string | Request URL |
| body | string\|nil | Request body (rarely used for GET) |
| headers | string\|nil | Custom headers, separated by `\r\n` |

**Returns**: Response body as string, or nil on failure.

```lua
local body = http.get("http://localhost:8080/api/status")
local data = json.decode(body)
return data.message
```

## http.post(url [, body, headers])

Sends an HTTP POST request.

```lua
local resp = http.post(
    "http://localhost:8080/api/action",
    '{"cmd":"start"}',
    "Content-Type: application/json"
)
```

## http.put(url [, body, headers])

Sends an HTTP PUT request. Same usage as `http.post`.

## http.delete(url [, body, headers])

Sends an HTTP DELETE request. Same usage as `http.post`.

---

## sys.cpu()

Returns current CPU usage (0-100 integer). First call returns 0 (needs two samples to compute delta).

```lua
local cpu = sys.cpu()  -- 45
```

## sys.memory()

Returns memory usage info table.

| Field | Type | Description |
|-------|------|-------------|
| total_mb | number | Total physical memory (MB) |
| used_mb | number | Used memory (MB) |
| percent | number | Usage percentage (0-100) |

```lua
local mem = sys.memory()
-- mem.total_mb = 16384, mem.used_mb = 8192, mem.percent = 50
```

## sys.disk(drive)

Returns disk usage info table.

| Parameter | Type | Description |
|-----------|------|-------------|
| drive | string | Drive letter, e.g. `"C:"` (optional, defaults to `"C:"`) |

| Return Field | Type | Description |
|--------------|------|-------------|
| total_gb | number | Total capacity (GB) |
| free_gb | number | Free space (GB) |
| percent | number | Used percentage (0-100) |

## sys.battery()

Returns battery status table. Returns percent=-1 on desktops without battery.

| Return Field | Type | Description |
|--------------|------|-------------|
| percent | number | Battery level (0-100), -1 if no battery |
| charging | boolean | Whether AC power is connected |
| seconds_left | number | Remaining seconds, -1 if unknown |

## sys.uptime()

Returns system uptime in seconds.

## sys.process_count()

Returns current number of running processes.

## sys.net()

Returns cumulative network byte counters.

| Return Field | Type | Description |
|--------------|------|-------------|
| recv_bytes | number | Total bytes received |
| send_bytes | number | Total bytes sent |

## sys.net_speed()

Returns real-time network speed (bytes/sec). Requires two calls with interval to compute delta.

| Return Field | Type | Description |
|--------------|------|-------------|
| download | number | Download speed (bytes/sec) |
| upload | number | Upload speed (bytes/sec) |

```lua
local net = sys.net_speed()
-- net.download = 1048576 (1MB/s), net.upload = 51200 (50KB/s)
```

## sys.net_processes()

Returns a list of processes with active TCP connections (ESTABLISHED only), including real-time I/O rates. Requires two calls with interval to compute speed.

**Returns**: Array table, each entry contains:

| Field | Type | Description |
|-------|------|-------------|
| pid | number | Process ID |
| name | string | Process name (e.g. `"chrome.exe"`) |
| connections | number | Number of active connections |
| download | number | Read speed (bytes/sec) |
| upload | number | Write speed (bytes/sec) |

```lua
local procs = sys.net_processes()
for _, p in ipairs(procs) do
    print(p.name, p.connections, p.download, p.upload)
end
```

## sys.file_mtime(path)

Returns the file's last modification time as a Unix timestamp (seconds). Returns nil if the file does not exist.

| Parameter | Type | Description |
|-----------|------|-------------|
| path | string | File path |

```lua
local mtime = sys.file_mtime("C:\\Users\\me\\data.txt")
local age = os.time() - mtime  -- seconds since last modification
```

## sys.find_newest(dir, ext)

Recursively searches a directory and returns the path of the most recently modified file matching the given extension. Returns nil if no match is found.

| Parameter | Type | Description |
|-----------|------|-------------|
| dir | string | Root directory to search |
| ext | string | File extension including dot (e.g. `".jsonl"`) |

```lua
local newest = sys.find_newest("C:\\logs", ".log")
-- returns full path of the most recently modified .log file
```

## sys.read_file(path)

Reads entire file content as a string. Automatically skips UTF-8 BOM. Returns nil if file does not exist, empty string for empty files.

| Parameter | Type | Description |
|-----------|------|-------------|
| path | string | File path |

**Returns**: File content string, or nil on failure.

```lua
local content = sys.read_file("C:\\config\\settings.json")
if content then
    local cfg = json.decode(content)
end
```

## sys.write_file(path, content)

Writes a string to a file (overwrites existing content).

| Parameter | Type | Description |
|-----------|------|-------------|
| path | string | File path |
| content | string | Content to write |

**Returns**: boolean, true on success.

```lua
local ok = sys.write_file("C:\\temp\\output.txt", "Hello World")
```

## sys.exe_path()

Returns the full path to the TaskPin executable.

```lua
local path = sys.exe_path()
-- "C:\\Program Files\\TaskPin\\taskpin.exe"
```

## sys.version()

Returns the TaskPin version string.

```lua
local ver = sys.version()  -- "1.4.1"
```

## sys.screen_width()

Returns the primary screen width in pixels.

```lua
local w = sys.screen_width()  -- 1920
```

## sys.screen_height()

Returns the primary screen height in pixels.

```lua
local h = sys.screen_height()  -- 1080
```

## sys.mouse_x()

Returns the current mouse X coordinate (screen pixels).

```lua
local mx = sys.mouse_x()
```

## sys.mouse_y()

Returns the current mouse Y coordinate (screen pixels).

```lua
local my = sys.mouse_y()
```

## sys.window_at(x, y)

Returns the top-level window handle (integer) at the specified screen coordinates. Automatically skips the desktop and TaskPin's own windows. Returns nil if no window is found.

| Parameter | Type | Description |
|-----------|------|-------------|
| x | number | Screen X coordinate |
| y | number | Screen Y coordinate |

**Returns**: Window handle (integer), or nil if no window.

```lua
local hwnd = sys.window_at(500, 300)
if hwnd then
    sys.move_window(hwnd, 0, 5)  -- push down 5px
end
```

## sys.move_window(hwnd, dx, dy)

Moves a window by the specified pixel offset (relative movement).

| Parameter | Type | Description |
|-----------|------|-------------|
| hwnd | number | Window handle (from `sys.window_at`) |
| dx | number | Horizontal offset (positive=right, negative=left) |
| dy | number | Vertical offset (positive=down, negative=up) |

**Returns**: boolean, true on success.

```lua
local hwnd = sys.window_at(sys.mouse_x(), sys.mouse_y())
if hwnd then
    sys.move_window(hwnd, 10, 0)  -- push right 10px
end
```

---

## Global Variables

| Variable | Description |
|----------|-------------|
| `response` | Raw HTTP response text (available in URL mode Template expressions) |
| `args` | Parameter table (key-value) configured by user (available in Lua File mode) |
| `event` | External event table (nil when no event), contains source, name, and parameter fields |

```lua
-- Access parameters in Lua File mode
local server = args.server or "localhost"
local port = args.port or "8080"
```

### event Global Variable

When an external process sends an event via IPC, the `event` table becomes available. Scripts should call `event.clear()` after handling the event.

| Field | Type | Description |
|-------|------|-------------|
| source | string | Event source identifier |
| name | string | Event name |
| clear | function | Call `event.clear()` to clear the current event |
| ... | any | JSON parameter fields from the event are merged into the table |

```lua
if event then
    log("received event:", event.source, event.name)
    if event.name == "refresh" then
        -- handle refresh event
    end
    event.clear()
end
```

---

## Script Declarations

Declare metadata in the script file header using `-- @xxx` comments. TaskPin recognizes them automatically:

| Declaration | Type | Description |
|-------------|------|-------------|
| `@param key type desc` | — | Declare a script parameter, auto-generates input field in UI |
| `@name text` | string | Script display name (overrides auto-naming) |
| `@refresh ms` | number | Refresh interval in milliseconds, overrides default |
| `@bar_width px` | number | Taskbar display width in pixels |
| `@version ver` | string | Script version |
| `@require ver` | string | Minimum TaskPin version required (shows warning if not met) |

**Auto-naming rule**: If no `@name` is present, TaskPin extracts "Description" from the first comment line `-- file.lua - Description`.

```lua
-- system_monitor.lua - System Monitor
-- @name System Monitor
-- @refresh 1000
-- @bar_width 120
-- @version 1.0.0
-- @require 1.4.0
-- @param server string Server address
-- @param port number Port number

local resp = http.get("http://" .. args.server .. ":" .. args.port .. "/status")
```