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

## icon(source, width, height, align)

创建图片段落，可嵌入任务栏显示。支持本地文件路径、URL、data URI（base64）和 GIF 动画。

| 参数 | 类型 | 说明 |
|------|------|------|
| source | string | 图片来源：相对/绝对路径、URL 或 `data:image/png;base64,...` |
| width | number\|nil | 显示宽度（px），默认 16 |
| height | number\|nil | 显示高度（px），默认 16 |
| align | string\|nil | 对齐：`"left"`（默认）、`"right"`、`"center"` |

**返回值**: span 对象，支持 `..` 拼接。

```lua
-- 本地 PNG
return icon("examples/logo.png", 16, 16) .. font(" Hello", "#FFF", 9)

-- GIF 动画（配合刷新间隔自动播放）
return icon("spinner.gif", 14, 14) .. font(" Loading", "#AAA", 8)

-- base64 内嵌
return icon("data:image/png;base64,iVBOR...", 16, 16)
```

---

## dialog(spec)

创建点击弹出的对话框。作为脚本第 3 个返回值使用。

| 参数 | 类型 | 说明 |
|------|------|------|
| spec | table | 对话框配置表 |

**spec 字段**:

| 字段 | 类型 | 说明 |
|------|------|------|
| title | string | 窗口标题 |
| width | number | 窗口宽度（px），默认 400 |
| height | number | 窗口高度（px），默认 300 |
| refresh | number | 自动刷新间隔（秒），0 或不填则不刷新 |
| borderless | boolean | 无标题栏/无边框/无滚动条模式，默认 false |
| clickthrough | boolean | 鼠标点击穿透（配合 borderless 做 HUD），默认 false |
| x | number | 窗口 X 坐标（px），-1 或不填为自动定位 |
| y | number | 窗口 Y 坐标（px），-1 或不填为自动定位 |
| opacity | number | 窗口透明度 0-255（0=全透明，255=不透明），默认 255 |
| transparent_bg | boolean | 透明背景（窗口内容区域无底色），默认 false |
| content | table | 内容项数组（最多 8 项） |

**borderless 模式**：
- 按住 Shift 拖动窗口位置
- 按住 Shift + 滚轮调整窗口大小
- 鼠标悬停时按 ESC 关闭窗口
- 不会出现在任务栏和 Alt+Tab 列表中

**content 项类型**:

| type | 字段 | 说明 |
|------|------|------|
| `"text"` | value, color, size, bold, image, image_width, image_height | 文本行（可选内嵌图片） |
| `"image"` | source, width, height, src_x, src_y, src_w, src_h | 独立图片块（支持精灵表裁切） |
| `"hr"` | — | 水平分隔线 |
| `"table"` | columns, col_widths, rows, height, wrap | 表格（最多 6 列 × 24 行） |
| `"button"` | value, cmd, url, lua, color, bg_color, size, width, height, align | 可点击按钮 |

**table 布局字段**:

| 字段 | 类型 | 说明 |
|------|------|------|
| columns | table | 列名数组 |
| col_widths | table\|nil | 列宽数组（px），`0` 或不填表示自动分配剩余宽度 |
| rows | table | 行数据数组 |
| height | number\|nil | 行高（px），默认自动计算 |
| wrap | boolean\|nil | 单元格文本自动换行，默认 false |

```lua
{ type = "table",
  columns = { "Name", "Status", "Detail" },
  col_widths = { 80, 60, 0 },  -- 前两列固定宽度，第三列自动填充
  height = 24,                   -- 行高 24px
  wrap = true,                   -- 长文本自动换行
  rows = { {"app.exe", "Running", "Some long description..."} }
}
```

**button 布局字段**:

| 字段 | 类型 | 说明 |
|------|------|------|
| width | number\|nil | 按钮宽度（px），默认自适应文字 |
| height | number\|nil | 按钮高度（px），默认自适应 |
| align | string\|nil | 对齐：`"left"`（默认）、`"center"`、`"right"`、`"inline"` |

```lua
{ type = "button", value = "居中按钮", url = "https://example.com",
  color = "#FFF", bg_color = "#336699", size = 10,
  width = 200, height = 36, align = "center" },
```

**图文混排示例**：

```lua
{ type = "text", value = "Claude Code", color = "#D97757", size = 12,
  image = "claude.png", image_width = 16, image_height = 16 },
{ type = "image", source = "logo.png", width = 64, height = 64 },
```

**精灵表裁切**（从大图中取子区域显示）：

```lua
{ type = "image", source = "sprites.png",
  src_x = 64, src_y = 0, src_w = 32, src_h = 32,  -- 源图裁切区域
  width = 96, height = 96 },                         -- 显示尺寸
```

**按钮示例**：

```lua
{ type = "button", value = "打开网页", url = "https://example.com",
  color = "#FFFFFF", bg_color = "#336699", size = 10 },
{ type = "button", value = "执行命令", cmd = "notepad.exe",
  color = "#FFF", bg_color = "#444", size = 10 },
{ type = "button", value = "执行Lua", lua = "sys.notify('hi', 'hello')",
  color = "#FFF", bg_color = "#C62828", size = 10 },
```

**表格行按钮**：

table 的 rows 中每行可添加 `lua`/`cmd`/`url` + `btn_text` 字段，行尾自动显示操作按钮：

```lua
{ type = "table", columns = {"进程", "CPU"},
  rows = {
    { "chrome.exe", "12%", lua = "sys.kill(1234)", btn_text = "Kill" },
    { "README.md", "", url = "https://...", btn_text = "Open" },
  }
}
```

```lua
local info = dialog({
    title = "状态",
    width = 320, height = 200,
    refresh = 5,
    content = {
        { type = "text", value = "标题", color = "#FF8800", size = 12, bold = true },
        { type = "hr" },
        { type = "text", value = "内容行", color = "#CCCCCC", size = 10 },
        { type = "table", columns = {"名称", "值"},
          rows = {{"CPU", "45%"}, {"MEM", "72%"}} },
    }
})

return font("Status", "#0F0", 9), true, info
```

**HUD 悬浮窗示例**：

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

创建可点击按钮 span，用于任务栏或对话框中。点击后执行指定命令或打开 URL。

| 参数 | 类型 | 说明 |
|------|------|------|
| text | string | 按钮文本（必填） |
| cmd | string\|nil | 点击执行的命令或 URL |
| bg | string\|nil | 背景色，格式 `"#RRGGBB"` |
| color | string\|nil | 文字色，格式 `"#RRGGBB"` |
| size | number\|nil | 字号（pt） |

**返回值**: span 对象，支持 `..` 拼接。

```lua
return font("Status: OK", "#0F0", 9) .. button("Open", "https://example.com", "#333", "#FFF", 9)
```

---

## input(name, placeholder, width, height, bg_color, color, border_color)

创建可输入文本框 span，用于任务栏中。配合 button 使用，按钮 response 中用 `{name}` 占位符引用输入框的值。

| 参数 | 类型 | 说明 |
|------|------|------|
| name | string | 输入框标识名（必填），用于 response 中 `{name}` 绑定 |
| placeholder | string\|nil | 占位提示文字 |
| width | number\|nil | 宽度（px），默认 120 |
| height | number\|nil | 高度（px），默认 22 |
| bg_color | string\|nil | 背景色，格式 `"#RRGGBB"` |
| color | string\|nil | 文字色，格式 `"#RRGGBB"` |
| border_color | string\|nil | 边框色，格式 `"#RRGGBB"` |

**返回值**: span 对象，支持 `..` 拼接。

按钮的 response 字段中，`{name}` 会在点击时被替换为对应输入框的内容（自动 JSON 转义）。

```lua
bar = font("Search: ", "#FFF", 9)
    .. input("query", "Enter keyword...", 150, 22, "#222", "#FFF", "#555")
    .. button(" Go ", nil, "#1565C0", "#FFF", 8)

-- button's response field can reference {query}
```

---

## log(...)

写入脚本日志（等同 `log.info(...)`）。接受任意数量参数，用制表符分隔输出。

## log.info(...) / log.debug(...) / log.error(...)

按级别写入日志，自动附带调用文件名和行号。

| 函数 | 级别 | 说明 |
|------|------|------|
| `log.info(...)` | INF | 一般信息 |
| `log.debug(...)` | DBG | 调试信息（需开启 debug 日志级别） |
| `log.error(...)` | ERR | 错误信息 |

日志输出格式：`[时间][级别][文件名:行号] 内容`

```lua
log.info("请求开始", url)
log.debug("响应内容", data)
log.error("连接失败", err)
log("简写等同 info")
```

---

## json.decode(str)

解析 JSON 字符串为 Lua table。

```lua
local data = json.decode(response)
print(data.name)       -- 访问对象字段
print(data[1].id)      -- 访问数组元素
```

## json.encode(value [, pretty])

将 Lua table 编码为 JSON 字符串。

| 参数 | 类型 | 说明 |
|------|------|------|
| value | any | 要编码的 Lua 值（table、string、number 等） |
| pretty | boolean\|nil | 是否格式化输出（缩进），默认 false |

**返回值**: JSON 字符串。

```lua
local t = { name = "test", value = 42, tags = {"a", "b"} }
local str = json.encode(t)         -- 紧凑输出
local pretty = json.encode(t, true) -- 格式化输出
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

## websocket.connect(url [, options])

创建 WebSocket 连接。连接建立后由独立线程接收消息，Lua 侧通过 `ws:recv()` 非阻塞获取。

| 参数 | 类型 | 说明 |
|------|------|------|
| url | string | WebSocket 地址，支持 `ws://` 和 `wss://` |
| options | table\|nil | 可选配置表 |

**options 字段**:

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| reconnect | boolean | true | 断线自动重连（指数退避 1s~30s） |
| headers | string\|nil | nil | 自定义请求头，`\r\n` 分隔 |

**返回值**: WebSocket 连接对象，失败返回 `nil`（当 reconnect=false 且连接失败时）。

```lua
-- 基本连接（自动重连）
local ws = websocket.connect("wss://example.com/stream")

-- 带配置
local ws = websocket.connect("wss://api.example.com/ws", {
    reconnect = true,
    headers = "Authorization: Bearer token123\r\nX-Custom: value"
})
```

**生命周期**: 连接绑定到创建它的脚本（bar），bar 移除时自动关闭。建议使用 `_G` 全局变量保持连接跨刷新周期存活。

---

## ws:send(data)

发送文本消息。

| 参数 | 类型 | 说明 |
|------|------|------|
| data | string | 要发送的内容 |

**返回值**: `true` 成功，`false` 失败（未连接）。

```lua
ws:send("hello")
ws:send(json.encode({ type = "subscribe", channel = "ticker" }))
```

---

## ws:recv()

非阻塞接收消息。从内部队列取出一条消息，队列为空返回 `nil`。

**返回值**: 消息字符串或 `nil`。

```lua
local msg = ws:recv()
if msg then
    local data = json.decode(msg)
    -- 处理数据...
end
```

**队列**: 最多缓存 32 条消息，溢出时丢弃最旧的。

---

## ws:close()

主动关闭连接并释放资源。

```lua
ws:close()
```

---

## ws:is_connected()

检查连接状态。

**返回值**: `true` 已连接，`false` 未连接/重连中。

```lua
if ws:is_connected() then
    ws:send("ping")
end
```

---

## ws:set_reconnect(enabled)

动态开启/关闭自动重连。

| 参数 | 类型 | 说明 |
|------|------|------|
| enabled | boolean | `true` 开启，`false` 关闭 |

```lua
ws:set_reconnect(false)  -- 断开后不再重连
```

---

## WebSocket 使用示例

推荐配合 `@realtime` 声明使用，50ms 轮询确保消息及时显示：

```lua
-- @realtime
-- @bar_width 150

if not _G._ws then
    _G._ws = websocket.connect("wss://stream.example.com/data")
end

local ws = _G._ws
local msg = ws:recv()
if msg then
    _G._last = json.decode(msg)
end

local d = _G._last
if not d then
    return font(ws:is_connected() and "等待数据" or "连接中...", "#888", 9), true
end

return font(d.price, "#4FC3F7", 12), true
```

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

## sys.net_processes()

返回当前有活跃 TCP 连接的进程列表（仅 ESTABLISHED 状态），含实时 I/O 速率。需要两次调用间隔才能计算速率。

**返回值**: 数组 table，每项包含：

| 字段 | 类型 | 说明 |
|------|------|------|
| pid | number | 进程 ID |
| name | string | 进程名（如 `"chrome.exe"`） |
| path | string | 进程完整路径 |
| connections | number | 活跃连接数 |
| download | number | 读取速率 (bytes/sec) |
| upload | number | 写入速率 (bytes/sec) |

```lua
local procs = sys.net_processes()
for _, p in ipairs(procs) do
    print(p.name, p.connections, p.download, p.upload)
end
```

## sys.top_processes(mode, limit)

返回按 CPU 或内存排序的进程列表。需要两次调用间隔才能计算 CPU 使用率。

| 参数 | 类型 | 说明 |
|------|------|------|
| mode | string | `"cpu"` 按 CPU 排序，`"mem"` 按内存排序（默认 `"cpu"`） |
| limit | number | 返回数量上限（默认 15，最大 128） |

**返回值**: 数组 table，每项包含：

| 字段 | 类型 | 说明 |
|------|------|------|
| pid | number | 进程 ID |
| name | string | 进程名 |
| path | string | 进程完整路径 |
| cpu | number | CPU 使用率百分比 (0-100) |
| mem_mb | number | 内存占用 (MB) |

```lua
local top_cpu = sys.top_processes("cpu", 10)
local top_mem = sys.top_processes("mem", 5)
```

## sys.watch_keys(...)

注册需要监听的按键。只有注册过的键才会被 `key_pressed` / `key_triggered` / `key_combo` 检测到。

支持传入字符串名称或数字虚拟键码，可传多个参数或 table。

**可用键名**（大小写不敏感）：

| 分类 | 键名 |
|------|------|
| 鼠标 | `lclick`, `rclick`, `mclick` |
| 方向 | `up`, `down`, `left`, `right` |
| 功能 | `space`, `enter`, `esc`, `tab`, `backspace`, `delete`, `insert` |
| 修饰 | `shift`, `ctrl`, `alt` |
| 导航 | `home`, `end`, `pageup`, `pagedown` |
| F键 | `f1` - `f12` |
| 字母 | `a` - `z` |
| 数字 | `0` - `9` |

```lua
sys.watch_keys("space", "up", "lclick")
sys.watch_keys("ctrl", "shift", "s")
```

## sys.key_pressed(key)

检测按键当前是否被按住。参数为键名字符串或数字虚拟键码。

```lua
if sys.key_pressed("shift") then ... end
```

## sys.key_triggered(key)

检测按键是否刚被按下（边沿触发）。读取后自动清除，不会重复触发。适合游戏跳跃、菜单确认等一次性动作。

```lua
if sys.key_triggered("space") then jump() end
```

## sys.key_combo(expr)

检测组合键表达式。用 `+` 连接多个键，前面的键检测"按住"，最后一个键检测"刚按下"。

```lua
if sys.key_combo("ctrl+s") then save() end
if sys.key_combo("ctrl+shift+a") then select_all() end
if sys.key_combo("shift+lclick") then special_click() end
```

## sys.file_mtime(path)

返回文件最后修改时间（Unix 时间戳，秒）。文件不存在返回 nil。

| 参数 | 类型 | 说明 |
|------|------|------|
| path | string | 文件路径 |

```lua
local mtime = sys.file_mtime("C:\\Users\\me\\data.txt")
local age = os.time() - mtime  -- 距上次修改的秒数
```

## sys.find_newest(dir, ext)

递归搜索目录，返回指定扩展名中最新修改的文件路径。未找到返回 nil。

| 参数 | 类型 | 说明 |
|------|------|------|
| dir | string | 搜索根目录 |
| ext | string | 文件扩展名，含点号（如 `".jsonl"`） |

```lua
local newest = sys.find_newest("C:\\logs", ".log")
-- 返回最近修改的 .log 文件完整路径
```

## sys.read_file(path)

读取文件全部内容为字符串。自动跳过 UTF-8 BOM。文件不存在返回 nil，空文件返回空串。

| 参数 | 类型 | 说明 |
|------|------|------|
| path | string | 文件路径 |

**返回值**: 文件内容字符串，失败返回 nil。

```lua
local content = sys.read_file("C:\\config\\settings.json")
if content then
    local cfg = json.decode(content)
end
```

## sys.write_file(path, content)

将字符串写入文件（覆盖写入）。

| 参数 | 类型 | 说明 |
|------|------|------|
| path | string | 文件路径 |
| content | string | 写入内容 |

**返回值**: boolean，写入成功返回 true。

```lua
local ok = sys.write_file("C:\\temp\\output.txt", "Hello World")
```

## sys.exe_path()

返回 TaskPin 可执行文件的完整路径。

```lua
local path = sys.exe_path()
-- "C:\\Program Files\\TaskPin\\taskpin.exe"
```

## sys.version()

返回 TaskPin 版本号字符串。

```lua
local ver = sys.version()  -- "1.4.2"
```

## sys.screen_width()

返回主屏幕宽度（像素）。

```lua
local w = sys.screen_width()  -- 1920
```

## sys.screen_height()

返回主屏幕高度（像素）。

```lua
local h = sys.screen_height()  -- 1080
```

## sys.mouse_x()

返回鼠标当前 X 坐标（屏幕像素）。

```lua
local mx = sys.mouse_x()
```

## sys.mouse_y()

返回鼠标当前 Y 坐标（屏幕像素）。

```lua
local my = sys.mouse_y()
```

## sys.window_at(x, y)

返回指定屏幕坐标处的顶层窗口句柄（整数）。自动跳过桌面和 TaskPin 自身窗口。无窗口时返回 nil。

| 参数 | 类型 | 说明 |
|------|------|------|
| x | number | 屏幕 X 坐标 |
| y | number | 屏幕 Y 坐标 |

**返回值**: 窗口句柄（整数），无窗口返回 nil。

```lua
local hwnd = sys.window_at(500, 300)
if hwnd then
    sys.move_window(hwnd, 0, 5)  -- 向下推 5px
end
```

## sys.move_window(hwnd, dx, dy)

将窗口相对移动指定像素偏移量。

| 参数 | 类型 | 说明 |
|------|------|------|
| hwnd | number | 窗口句柄（由 `sys.window_at` 获取） |
| dx | number | 水平偏移（正=右，负=左） |
| dy | number | 垂直偏移（正=下，负=上） |

**返回值**: boolean，成功返回 true。

```lua
local hwnd = sys.window_at(sys.mouse_x(), sys.mouse_y())
if hwnd then
    sys.move_window(hwnd, 10, 0)  -- 向右推 10px
end
```

## sys.window_rect(hwnd)

返回窗口的位置和尺寸。

| 参数 | 类型 | 说明 |
|------|------|------|
| hwnd | number | 窗口句柄 |

**返回值**: table `{x, y, w, h}`，无效句柄返回 nil。

```lua
local hwnd = sys.window_at(500, 300)
if hwnd then
    local r = sys.window_rect(hwnd)
    log(r.x, r.y, r.w, r.h)
end
```

## sys.window_title(hwnd)

返回窗口标题文本。

| 参数 | 类型 | 说明 |
|------|------|------|
| hwnd | number | 窗口句柄 |

**返回值**: string，无效句柄返回 nil。

```lua
local hwnd = sys.active_window()
local title = sys.window_title(hwnd)  -- "Visual Studio Code"
```

## sys.window_list()

返回当前所有可见窗口列表。自动排除桌面和 TaskPin 自身窗口。

**返回值**: 数组 table，每项含 `{hwnd, title}`。

```lua
local wins = sys.window_list()
for _, w in ipairs(wins) do
    log(w.hwnd, w.title)
end
```

## sys.active_window()

返回当前前台窗口句柄。

**返回值**: 窗口句柄（整数），无前台窗口返回 nil。

```lua
local hwnd = sys.active_window()
```

## sys.is_fullscreen()

检测当前前台窗口是否为全屏模式。

**返回值**: boolean。

```lua
if sys.is_fullscreen() then
    return ""  -- 全屏时隐藏
end
```

## sys.clipboard()

读取系统剪贴板文本内容。

**返回值**: string，剪贴板为空或无文本时返回 nil。

```lua
local text = sys.clipboard()
```

## sys.set_clipboard(text)

将文本写入系统剪贴板。

| 参数 | 类型 | 说明 |
|------|------|------|
| text | string | 写入内容 |

**返回值**: boolean，成功返回 true。

```lua
sys.set_clipboard("Hello from TaskPin")
```

## sys.shell(cmd)

打开文件或执行命令（非阻塞）。等同于双击文件或在运行对话框中输入命令。

| 参数 | 类型 | 说明 |
|------|------|------|
| cmd | string | 文件路径、URL 或命令 |

**返回值**: boolean，成功返回 true。

```lua
sys.shell("https://github.com")            -- 打开网页
sys.shell("C:\\Windows\\notepad.exe")       -- 启动程序
sys.shell("C:\\Users\\me\\document.pdf")    -- 打开文件
```

## sys.notify(title, msg)

显示系统托盘通知气泡。

| 参数 | 类型 | 说明 |
|------|------|------|
| title | string | 通知标题 |
| msg | string | 通知内容 |

**返回值**: boolean。

```lua
sys.notify("TaskPin", "CPU 使用率超过 90%!")
```

## sys.resize_window(hwnd, w, h)

调整窗口大小（不移动位置）。

| 参数 | 类型 | 说明 |
|------|------|------|
| hwnd | number | 窗口句柄 |
| w | number | 新宽度（px） |
| h | number | 新高度（px） |

**返回值**: boolean，成功返回 true。

```lua
local hwnd = sys.active_window()
sys.resize_window(hwnd, 800, 600)
```

## sys.topmost_window(hwnd, on)

设置或取消窗口置顶。

| 参数 | 类型 | 说明 |
|------|------|------|
| hwnd | number | 窗口句柄 |
| on | boolean | true=置顶，false=取消置顶 |

**返回值**: boolean，成功返回 true。

```lua
local hwnd = sys.active_window()
sys.topmost_window(hwnd, true)  -- 置顶
```

## sys.is_running(name)

判断指定名称的进程是否正在运行。

| 参数 | 类型 | 说明 |
|------|------|------|
| name | string | 进程名（如 `"chrome.exe"`） |

**返回值**: boolean。

```lua
if sys.is_running("docker.exe") then
    return font("Docker: ON", "#0F0", 9)
else
    return font("Docker: OFF", "#F00", 9)
end
```

## sys.process_list()

返回所有进程列表。

**返回值**: 数组 table，每项含 `{pid, name}`。

```lua
local procs = sys.process_list()
for _, p in ipairs(procs) do
    log(p.pid, p.name)
end
```

## sys.kill(pid)

结束指定 PID 的进程。

| 参数 | 类型 | 说明 |
|------|------|------|
| pid | number | 进程 ID |

**返回值**: boolean，成功返回 true。

```lua
sys.kill(1234)
```

## sys.volume()

返回当前系统音量（0-100 整数）。获取失败返回 -1。

```lua
local vol = sys.volume()  -- 75
```

## sys.set_volume(n)

设置系统音量。

| 参数 | 类型 | 说明 |
|------|------|------|
| n | number | 音量值 (0-100) |

**返回值**: boolean，成功返回 true。

```lua
sys.set_volume(50)
```

## sys.is_muted()

检测系统是否静音。

**返回值**: boolean。

```lua
if sys.is_muted() then
    return font("MUTED", "#F00", 9)
end
```

## sys.wifi_name()

返回当前连接的 WiFi 名称。未连接 WiFi 时返回 nil。

**返回值**: string 或 nil。

```lua
local ssid = sys.wifi_name()  -- "MyNetwork"
```

## sys.is_connected()

检测是否有网络连接。

**返回值**: boolean。

```lua
if not sys.is_connected() then
    return font("OFFLINE", "#F00", 9)
end
```

## sys.is_dark_mode()

检测系统是否为深色模式。

**返回值**: boolean。

```lua
local color = sys.is_dark_mode() and "#FFF" or "#000"
return font("Hello", color, 9)
```

## sys.monitor_count()

返回显示器数量。

```lua
local n = sys.monitor_count()  -- 2
```

## sys.monitor_rect(n)

返回第 n 个显示器的区域（1-based）。

| 参数 | 类型 | 说明 |
|------|------|------|
| n | number | 显示器序号（从 1 开始） |

**返回值**: table `{x, y, w, h}`，无效序号返回 nil。

```lua
local m = sys.monitor_rect(2)
-- m.x = 1920, m.y = 0, m.w = 2560, m.h = 1440
```

## sys.env(name)

读取环境变量。

| 参数 | 类型 | 说明 |
|------|------|------|
| name | string | 环境变量名 |

**返回值**: string，不存在返回 nil。

```lua
local home = sys.env("USERPROFILE")
local path = sys.env("PATH")
```

## sys.is_china()

检测当前网络是否位于中国大陆（通过 ip.sb 接口判断）。结果在整个会话中缓存，只请求一次。

**返回值**: boolean。

```lua
if sys.is_china() then
    -- 使用代理地址
end
```

## sys.gh_proxy(url)

根据地区自动为 GitHub URL 添加代理前缀。如果不在中国则原样返回。

| 参数 | 类型 | 说明 |
|------|------|------|
| url | string | GitHub 原始 URL |

**返回值**: string，处理后的 URL。

```lua
local sprite = sys.gh_proxy("https://raw.githubusercontent.com/user/repo/master/img.png")
-- 中国: "https://gh-proxy.com/https://raw.githubusercontent.com/..."
-- 其他: "https://raw.githubusercontent.com/..."
```

---

## 全局变量

| 变量 | 说明 |
|------|------|
| `response` | URL 模式下，HTTP 响应原始文本（仅在 Template 表达式中可用） |
| `args` | Lua File 模式下，用户配置的参数表（key-value） |
| `event` | 外部事件表（无事件时为 nil），含 source、name 及参数字段 |

```lua
-- 在 Lua File 模式中访问参数
local server = args.server or "localhost"
local port = args.port or "8080"
```

### event 全局变量

当外部通过 IPC 发送事件时，`event` 表可用。脚本处理完事件后应调用 `event.clear()` 清除。

| 字段 | 类型 | 说明 |
|------|------|------|
| source | string | 事件来源标识 |
| name | string | 事件名称 |
| clear | function | 调用 `event.clear()` 清除当前事件 |
| ... | any | 事件附带的 JSON 参数字段会合并到表中 |

```lua
if event then
    log("收到事件:", event.source, event.name)
    if event.name == "refresh" then
        -- 处理刷新事件
    end
    event.clear()
end
```

---

## 脚本声明

在脚本文件头部用 `-- @xxx` 注释声明元数据，TaskPin 会自动识别：

| 声明 | 类型 | 说明 |
|------|------|------|
| `@param key type desc` | — | 声明脚本参数，自动生成输入框 |
| `@name text` | string | 脚本显示名称（覆盖自动命名） |
| `@refresh ms` | number | 刷新间隔（毫秒），覆盖默认值 |
| `@realtime` | — | 实时模式，脚本在 GUI 线程同步执行（50ms 刷新），适用于游戏/动画 |
| `@bar_width px` | number | 任务栏显示宽度（像素） |
| `@version ver` | string | 脚本版本号 |
| `@require ver` | string | 最低 TaskPin 版本要求（不满足时显示提示） |

**自动命名规则**：若无 `@name`，TaskPin 从首行注释 `-- file.lua - 描述` 中提取"描述"作为名称。

```lua
-- system_monitor.lua - 系统监控
-- @name 系统监控
-- @refresh 1000
-- @bar_width 120
-- @version 1.0.0
-- @require 1.4.0
-- @param server string 服务器地址
-- @param port number 端口号

local resp = http.get("http://" .. args.server .. ":" .. args.port .. "/status")
```

---

## sys.language()

返回用户系统语言标识（如 `"zh-CN"`、`"en-US"`）。

```lua
local lang = sys.language()  -- "zh-CN"
```

## sys.find_window(title)

按窗口标题查找窗口，返回位置和大小信息。未找到返回 nil。

| 参数 | 类型 | 说明 |
|------|------|------|
| title | string | 窗口标题（精确匹配） |

**返回值**: table `{x, y, w, h, visible}` 或 nil。

```lua
local win = sys.find_window("记事本")
if win then
    log("位置: " .. win.x .. "," .. win.y .. " 大小: " .. win.w .. "x" .. win.h)
end
```

## sys.window_list()

列出所有可见窗口及其位置信息。

**返回值**: table 数组，每项包含 `{title, x, y, w, h}`。

```lua
local windows = sys.window_list()
for _, w in ipairs(windows) do
    log(w.title .. " at " .. w.x .. "," .. w.y)
end
```

## sys.window_collision(x, y, w, h)

检测指定矩形区域是否与其他窗口重叠，返回碰撞信息和方向。

| 参数 | 类型 | 说明 |
|------|------|------|
| x | number | 矩形左上角 X |
| y | number | 矩形左上角 Y |
| w | number | 矩形宽度 |
| h | number | 矩形高度 |

**返回值**: table，`hit=false` 时无碰撞；`hit=true` 时包含碰撞详情。

| 字段 | 说明 |
|------|------|
| hit | boolean，是否碰撞 |
| direction | 碰撞方向：`"left"`, `"right"`, `"top"`, `"bottom"` |
| window | 碰撞窗口标题 |
| x, y, w, h | 碰撞窗口的位置和大小 |

```lua
local col = sys.window_collision(L.x, L.y, 200, 200)
if col.hit then
    if col.direction == "right" then L.vx = -math.abs(L.vx) end
    if col.direction == "left" then L.vx = math.abs(L.vx) end
    if col.direction == "bottom" then L.vy = -math.abs(L.vy) end
    if col.direction == "top" then L.vy = math.abs(L.vy) end
end
```