# TaskPin

[English](README_EN.md)

Windows 任务栏嵌入信息显示工具。纯 C + Win32 API + Lua 5.4，单文件 ~450KB，零外部依赖。

![preview](docs/preview.png)

## 功能

- **任务栏嵌入** — 窗口直接嵌入底部任务栏内部
- **多 Bar 支持** — 同时 Pin 多个 item，各自独立显示、独立刷新
- **双模式 Item** — URL 模式（HTTP GET + Lua/模板处理）或 Lua 文件模式（脚本全权控制）
- **富文本渲染** — `font(text, color, size, align)` 支持多色、多字号、左右对齐、双行显示
- **系统监控 API** — 内置 `sys.cpu/memory/disk/battery/net_speed` 等函数
- **Lua 5.4 脚本引擎** — 内置 `json.decode`、`http.get/post/put/delete`（带 session cookie）
- **@param 声明** — 脚本头部声明参数，UI 自动生成输入框，填一次永久生效
- **自定义请求头** — URL 模式支持多行 Headers
- **模板引擎** — `$.path` JSONPath 插值 + 完整 Lua 代码，自动 fallback
- **点击跳转** — 脚本 return 三个值：显示文本、是否可点击、跳转 URL
- **鼠标滚轮调整** — hover 在 bar 上滚轮调宽度，Shift+滚轮调水平位置
- **自动滚动** — 文字超出宽度时横向滚动（可关闭）
- **静默自动更新** — 检测新版本后下载替换重启，中国用户走 gh-proxy
- **Per-Item 外观** — 每个 item 可独立配置宽度、坐标、背景色
- **可配置外观** — 字体大小/颜色、背景色、位置、宽度（全局默认值）
- **开机自启** — Settings 一键开关

## 快速开始

1. 下载 [最新 Release](https://github.com/bestK/taskpin/releases/latest)
2. 运行 `taskpin.exe`
3. 双击任务栏嵌入条打开管理窗口
4. Add 添加 item（URL 或 Lua File 类型）
5. Pin to Bar 选中要显示的 item

## 编译

需要 MinGW-w64 (gcc) + GNU Make：

```bash
make
```

## 项目结构

```
main.c          主窗口/消息循环/编辑对话框/设置对话框
appbar.c/h      任务栏嵌入（SetParent）
fetcher.c/h     WinHTTP 异步拉取（URL 模式）
httputil.c/h    统一同步 HTTP 模块
scripting.c/h   Lua 引擎封装 + http/json 内置函数
update.c/h      自动更新检查 + 静默替换
config.c/h      INI 读写（UTF-16LE）
json.c/h        轻量 JSON 解析 + JSONPath
base64.c/h      Base64 编解码
lua/            Lua 5.4 源码
examples/       示例 Lua 脚本
```

## 示例脚本

| 文件 | 说明 |
|------|------|
| [`example.lua`](examples/example.lua) | 入门示例，演示基本的 HTTP 请求 + JSON 解析 + 参数声明 |
| [`newapi_balance.lua`](examples/newapi_balance.lua) | 查询 AI API 账户余额并显示在任务栏 |
| [`rich_text_demo.lua`](examples/rich_text_demo.lua) | font() 富文本演示：多色、多行、左右对齐 |
| [`zentao_task.lua`](examples/zentao_task.lua) | 禅道项目管理：显示待办任务数，点击查看详情 |
| [`oracle_sessions.lua`](examples/oracle_sessions.lua) | Oracle 数据库会话监控，多实例支持，颜色预警 |
| [`system_monitor.lua`](examples/system_monitor.lua) | 系统监控：网速 + CPU + 内存，纯 sys.* API |
| [`net_monitor.lua`](examples/net_monitor.lua) | 网络进程监控：显示有活跃连接的进程及流量 |
| [`claude_status.lua`](examples/claude_status.lua) | Claude Code 实时状态指示器，读 session 文件判断工作状态 |

### 使用方式

1. 打开 TaskPin 管理窗口，点击 **Add**
2. 类型选择 **Lua File**，选择 `examples/` 下的脚本文件
3. 如果脚本有 `@param` 声明，填写对应参数
4. 点击 **Pin to Bar** 即可在任务栏显示

## 文档

- [Lua API 参考（中文）](docs/LUA_API.md)
- [Lua API Reference (English)](docs/LUA_API_EN.md)

## 技术栈

- 纯 C (C99)，Win32 API
- Lua 5.4（静态链接）
- 零第三方依赖
- 链接库：winhttp, user32, shell32, gdi32, shlwapi, comctl32, comdlg32