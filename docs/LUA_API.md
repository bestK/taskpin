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
| opacity | number | 窗口透明度 0-255（0=全透明，255=不透明），默认 255 |
| transparent_bg | boolean | 让宿主把弹窗合成到桌面上，而不是填充 `bg_color`，默认 false |
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
| `"image"` | source, width, height | 独立图片块 |
| `"hr"` | — | 水平分隔线 |
| `"table"` | columns, rows | 表格（最多 6 列 × 24 行） |
| `"webview"` | url, width, height | 内嵌网页（Windows 用 WebView2，macOS 用 WKWebView） |

**`webview` 项** —— 引擎只解析并透传 `url` / `width` / `height` 给宿主渲染。
配合 spec 上的 `transparent_bg` 可做无边框悬浮层。真正的渲染在
WebView2 / WKWebView 阶段落地，在此之前该项会被携带但不绘制。

```lua
local info = dialog({
    title = "WebView Demo",
    width = 580, height = 460,
    borderless = true,
    transparent_bg = true,
    refresh = 1000,
    content = {
        { type = "webview", url = "https://example.com", width = 580, height = 460 }
    }
})
```

**图文混排示例**：

```lua
{ type = "text", value = "Claude Code", color = "#D97757", size = 12,
  image = "claude.png", image_width = 16, image_height = 16 },
{ type = "image", source = "logo.png", width = 64, height = 64 },
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

## sys.net_processes()

返回当前有活跃 TCP 连接的进程列表（仅 ESTABLISHED 状态），含实时 I/O 速率。需要两次调用间隔才能计算速率。

**返回值**: 数组 table，每项包含：

| 字段 | 类型 | 说明 |
|------|------|------|
| pid | number | 进程 ID |
| name | string | 进程名（如 `"chrome.exe"`） |
| connections | number | 活跃连接数 |
| download | number | 读取速率 (bytes/sec) |
| upload | number | 写入速率 (bytes/sec) |

```lua
local procs = sys.net_processes()
for _, p in ipairs(procs) do
    print(p.name, p.connections, p.download, p.upload)
end
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

---

## 哪个"国家"？—— `sys.country()` 与 `sys.is_china()` 的区别

这是两个不同的问题，答案也可能不同。写脚本前先想清楚你要问哪一个：

| | `sys.country()` / `sys.language()` | `sys.is_china()` |
|---|---|---|
| 来源 | **操作系统区域设置** | **网络 geo-IP**（`api.ip.sb/geoip`） |
| 速度 | 瞬时 | 首次调用最多等一个 HTTP 超时 |
| 离线 | 始终可用 | 返回 `false` |
| 会不会不准 | 不会——如实反映设置 | 会——服务可能出错或被墙 |
| 缓存 | 不缓存（运行期不会变） | 缓存，每进程只查一次 |

真实后果：一个身在中国、但 Windows 设成 `en-US` 的用户，
`country() == "CN"`、`language() == "en-US"`；而断网时 `is_china()` 会返回
`false`。想知道机器怎么配置的，用 `country()`；想判断 GitHub 镜像是否有
用，用 `is_china()`。

---

## sys.country()

从**操作系统区域设置**读取当前电脑的国家/地区
（`GetUserDefaultGeoName`，失败时回退 `LOCALE_SISO3166CTRYNAME`），
返回 **ISO 3166-1 alpha-2** 代码。瞬时、离线可用、不走网络。
读不到时返回 `""`（不会返回 nil）。

```lua
local cc = sys.country()   -- "CN"、"US"、"JP" ...
```

## sys.language()

从**操作系统区域设置**读取当前电脑的 UI 语言
（`GetUserDefaultLocaleName`，失败时回退 `GetUserDefaultUILanguage`）。
瞬时、离线可用。失败时返回 `""`（不会返回 nil）。

```lua
local lang = sys.language()   -- "zh-CN"、"en-US" ...
```

## sys.is_china()

根据**网络 geo-IP 查询**（`api.ip.sb/geoip`，判断
`country_code == "CN"`）返回当前机器是否在中国。

结果在**进程生命周期内缓存** —— 无论脚本调用多少次，网络请求最多只发
一次。离线、服务不可达或结果不可解析时返回 `false`（不会超过 HTTP 超时
而卡住，也不会抛错）。因为它反映的是"网络观测到的位置"而非系统设置，
需要系统设置时请用 `sys.country()`。

```lua
if sys.is_china() then
    -- 这里访问 GitHub 慢/不通，走镜像
end
```

## sys.gh_proxy(url)

当 `sys.is_china()` 为真时，把 GitHub URL 改写成 `gh-proxy.com` 镜像地址；
否则原样返回。它已内联了 `is_china()` 判断，脚本无需自己判断。

只有 GitHub 的域名会被改写（`github.com`、`raw.githubusercontent.com`、
`api.github.com` 等）。`gh-proxy.com` 只能代理 GitHub，所以其他域名一律原样
返回；已经是代理地址的 URL 也不会被重复套一层。

| 参数 | 类型 | 说明 |
|------|------|------|
| url | string | 要改写的 URL |

**返回值**: string —— 镜像后的 URL，或原样返回的输入。

```lua
local url = "https://raw.githubusercontent.com/bestK/taskpin/master/examples/x.html"
url = sys.gh_proxy(url)
-- 在国内:   "https://gh-proxy.com/https://raw.githubusercontent.com/..."
-- 其他情况: 原样不变
```

## sys.watch_keys(name, ...)

声明脚本要监听的按键。键盘监听是**轮询式**的（`GetAsyncKeyState`），
不是全局钩子 —— 脚本运行时才读一次按键状态，不会往系统里装任何东西。

| 参数 | 类型 | 说明 |
|------|------|------|
| name | string | 一个或多个按键名（见下） |

**返回值**: 解析成功的按键名数组。无法识别的名字会被跳过，不会报错。

支持的按键名：`space`、`up`、`down`、`left`、`right`、`enter`/`return`、
`esc`/`escape`、`tab`、`shift`、`ctrl`、`alt`、`lclick`、`rclick`、`mclick`、
`a`–`z`、`0`–`9`、`f1`–`f12`。大小写不敏感。

## sys.key_pressed(name)

**电平状态** —— 该键当前是否正被按住。

## sys.key_triggered(name)

**上升沿** —— 在"上一次松开、这一次按下"的那次调用返回 `true`。
"按一下触发一次"用这个；"按住持续生效"用 `key_pressed`。两者对无法识别的
按键名都返回 `false`，且不会报错。

边沿状态会跨刷新保留，所以按间隔重复执行的脚本里 `key_triggered` 行为正确。

```lua
sys.watch_keys("space", "up", "lclick")

local jump = sys.key_triggered("space")
    or sys.key_triggered("up")
    or sys.key_triggered("lclick")
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