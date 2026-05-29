# TaskPin macOS

macOS 版使用 SwiftUI + MenuBarExtra 实现，Lua 5.4 引擎通过 C bridging header 集成。

## 构建要求

- macOS 14.0+
- Xcode 15+
- Swift 5.9+

## 项目结构

```
src/macos/
├── TaskPinApp.swift       App 入口 (MenuBarExtra)
├── StatusBarView.swift    菜单栏显示 (icon + text)
├── PopoverView.swift      弹出面板 (dialog 渲染)
├── ScriptEngine.swift     Lua 引擎封装 + 脚本执行
└── LuaBridge/             C bridging (复用 lib/ 层)
```

## 共享代码 (lib/)

以下模块通过 bridging header 直接复用：
- `lib/lua/` — Lua 5.4 源码
- `lib/json.c/h` — JSON 解析
- `lib/scripting.c/h` — Lua API 注册 (font/icon/dialog/log)
- `lib/base64.c/h` — Base64 编解码

## 平台差异

| 功能 | Windows (Win32) | macOS (SwiftUI) |
|------|----------------|-----------------|
| 显示位置 | 任务栏嵌入 | 菜单栏 (MenuBarExtra) |
| 弹出面板 | GDI 自绘窗口 | NSPopover + SwiftUI |
| HTTP | WinHTTP | URLSession |
| 系统监控 | Win32 API | sysctl / IOKit |
| 文件选择 | GetOpenFileName | NSOpenPanel |
| 进程执行 | CreateProcessW | Process (Foundation) |
