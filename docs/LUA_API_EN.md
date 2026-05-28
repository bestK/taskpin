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

## json.decode(str)

Parses a JSON string into a Lua table.

```lua
local data = json.decode(response)
print(data.name)       -- access object fields
print(data[1].id)      -- access array elements
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

---

## Global Variables

| Variable | Description |
|----------|-------------|
| `response` | Raw HTTP response text (available in URL mode Template expressions) |
| `args` | Parameter table (key-value) configured by user (available in Lua File mode) |

```lua
-- Access parameters in Lua File mode
local server = args.server or "localhost"
local port = args.port or "8080"
```

---

## Script Parameter Declarations

Declare parameters in the script file header using comments. TaskPin will auto-generate input fields in the UI:

```lua
-- @param server string Server address
-- @param port number Port number
-- @param token string API Token

local resp = http.get("http://" .. args.server .. ":" .. args.port .. "/status")
```