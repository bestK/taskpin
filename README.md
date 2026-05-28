# TaskPin

[English](README_EN.md)

Windows 任务栏嵌入信息显示工具。纯 C + Win32 API + Lua 5.4，单文件 ~450KB，零外部依赖。

![preview](docs/preview.png)

## 功能

- **任务栏嵌入** — 窗口直接嵌入底部任务栏内部
- **双模式 Item** — URL 模式（HTTP GET + Lua/模板处理）或 Lua 文件模式（脚本全权控制）
- **Lua 5.4 脚本引擎** — 内置 `json.decode`、`http.get/post/put/delete`（带 session cookie）
- **@param 声明** — 脚本头部声明参数，UI 自动生成输入框，填一次永久生效
- **自定义请求头** — URL 模式支持多行 Headers
- **模板引擎** — `$.path` JSONPath 插值 + 完整 Lua 代码，自动 fallback
- **点击跳转** — 脚本 return 三个值：显示文本、是否可点击、跳转 URL
- **自动滚动** — 文字超出宽度时横向滚动（可关闭）
- **静默自动更新** — 检测新版本后下载替换重启，中国用户走 gh-proxy
- **可配置外观** — 字体大小/颜色、背景色、位置、宽度
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

- `examples/example.lua` — 基础 HTTP + JSON 演示
- `examples/zentao_task.lua` — 禅道未完成任务监控
- `examples/newapi_balance.lua` — NewAPI/OneAPI 余额查询
- `examples/oracle_sessions.lua` — Oracle Exporter 会话监控

## 技术栈

- 纯 C (C99)，Win32 API
- Lua 5.4（静态链接）
- 零第三方依赖
- 链接库：winhttp, user32, shell32, gdi32, shlwapi, comctl32, comdlg32