# TaskPin Lua Script API

TaskPin 为 Lua 脚本提供以下内置 API，可在脚本中直接使用。

## 脚本返回值

脚本通过 `return` 控制任务栏显示内容：

```lua
-- 返回值 1: 显示文本（字符串或 font() span）
-- 返回值 2: 是否可点击（boolean，可选）
-- 返回值 3: 点击打开的 URL（string，可选）

return "Hello World", true, "https://example.com"
```

---

## font(text, color, size, align)

创建富文本段落，支持自定义颜色、字号和对齐方式。

| 参数 | 类型 | 说明 |
|------|------|------|
| text | string | 显示文本（必填）。传 `"\n"` 表示换行 |
| color | string\|nil | 颜色，格式 `"#RGB"` 或 `"#RRGGBB"`，nil 用默认色 |
| size | number\|nil | 字号（pt），nil 用默认 |
| align | string\|nil | 对齐：`"left"`（默认）、`"right"`、`"center"` |

**返回值**: span 对象，支持 `..` 拼接。

```lua
-- 单行多色
return font("CPU:", "#888", 8) .. font("45%", "#FF0000", 14)

-- 两行
return font("Line1", "#FFF", 9) .. font("\n") .. font("Line2", "#0F0", 9)

-- 左右分栏
return font("状态正常", "#0F0", 9) .. font("12:30", "#888", 9, "right")

-- 两行 + 左右对齐
return font("CPU: 45%", "#0F0", 9) .. font("12:30", "#888", 8, "right")
    .. font("\n")
    .. font("MEM: 72%", "#FA0", 9) .. font("05/28", "#888", 8, "right")
```

**限制**: 最多 2 行（bar 高度 40px），最多 32 个 span。

---

## json.decode(str)

解析 JSON 字符串为 Lua table。

```lua
local data = json.decode(response)
print(data.name)       -- 访问对象字段
print(data[1].id)      -- 访问数组元素
```

---

## http.get(url [, body, headers])

发送 HTTP GET 请求（同步阻塞）。

| 参数 | 类型 | 说明 |
|------|------|------|
| url | string | 请求 URL |
| body | string\|nil | 请求体（GET 通常不用） |
| headers | string\|nil | 自定义请求头，多个用 `\r\n` 分隔 |

**返回值**: 响应体字符串，失败返回 nil。

```lua
local body = http.get("http://localhost:8080/api/status")
local data = json.decode(body)
return data.message
```

## http.post(url [, body, headers])

发送 HTTP POST 请求。

```lua
local resp = http.post(
    "http://localhost:8080/api/action",
    '{"cmd":"start"}',
    "Content-Type: application/json"
)
```

## http.put(url [, body, headers])

发送 HTTP PUT 请求。用法同 `http.post`。

## http.delete(url [, body, headers])

发送 HTTP DELETE 请求。用法同 `http.post`。

---

## sys.cpu()

返回当前 CPU 使用率（0-100 整数）。首次调用返回 0（需要两次采样计算差值）。

```lua
local cpu = sys.cpu()  -- 45
```

## sys.memory()

返回内存使用信息表。

| 字段 | 类型 | 说明 |
|------|------|------|
| total_mb | number | 物理内存总量 (MB) |
| used_mb | number | 已使用内存 (MB) |
| percent | number | 使用百分比 (0-100) |

```lua
local mem = sys.memory()
-- mem.total_mb = 16384, mem.used_mb = 8192, mem.percent = 50
```

## sys.disk(drive)

返回磁盘使用信息表。

| 参数 | 类型 | 说明 |
|------|------|------|
| drive | string | 盘符，如 `"C:"` (可选，默认 `"C:"`) |

| 返回字段 | 类型 | 说明 |
|----------|------|------|
| total_gb | number | 总容量 (GB) |
| free_gb | number | 可用空间 (GB) |
| percent | number | 已用百分比 (0-100) |

```lua
local d = sys.disk("D:")
-- d.total_gb = 500.0, d.free_gb = 120.5, d.percent = 75
```

## sys.battery()

返回电池状态表。台式机无电池时 percent 为 -1。

| 返回字段 | 类型 | 说明 |
|----------|------|------|
| percent | number | 电量百分比 (0-100)，无电池为 -1 |
| charging | boolean | 是否正在充电 |
| seconds_left | number | 剩余秒数，未知为 -1 |

## sys.uptime()

返回系统运行时间（秒）。

```lua
local up = sys.uptime()  -- 86400 (1天)
```

## sys.process_count()

返回当前系统进程数。

## sys.net()

返回网络累计字节数表。

| 返回字段 | 类型 | 说明 |
|----------|------|------|
| recv_bytes | number | 累计接收字节 |
| send_bytes | number | 累计发送字节 |

## sys.net_speed()

返回实时网络速率（bytes/sec）。需要两次调用间隔才能计算差值。

| 返回字段 | 类型 | 说明 |
|----------|------|------|
| download | number | 下载速率 (bytes/sec) |
| upload | number | 上传速率 (bytes/sec) |

```lua
local net = sys.net_speed()
-- net.download = 1048576 (1MB/s), net.upload = 51200 (50KB/s)
```

---

## 全局变量

| 变量 | 说明 |
|------|------|
| `response` | URL 模式下，HTTP 响应原始文本（仅在 Template 表达式中可用） |
| `args` | Lua File 模式下，用户配置的参数表（key-value） |

```lua
-- 在 Lua File 模式中访问参数
local server = args.server or "localhost"
local port = args.port or "8080"
```

---

## 脚本参数声明

在脚本文件头部用注释声明参数，TaskPin 会自动生成输入框：

```lua
-- @param server string 服务器地址
-- @param port number 端口号
-- @param token string API Token

local resp = http.get("http://" .. args.server .. ":" .. args.port .. "/status")
```