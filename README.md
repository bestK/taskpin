# TaskPin

Windows 任务栏嵌入工具，纯 C + Win32 API 实现。将自定义信息直接显示在任务栏内部。

## 功能

- 嵌入 Windows 底部任务栏（SetParent 到 Shell_TrayWnd）
- 多项目管理，每个项目独立配置 API URL 和刷新间隔
- 定时 HTTP GET 拉取远程接口（WinHTTP，独立线程）
- 模板引擎：支持 JSONPath 插值（`车辆:$.name 速度:$.speed km/h`）
- 点击跳转：单击任务栏文字用浏览器打开模板渲染后的 URL
- 编辑对话框内 Load 按钮加载响应结构为 TreeView，点击节点插入路径
- 可配置字体大小/颜色/背景色/位置/宽度
- 配置持久化 UTF-16LE config.ini

## 编译

需要 MinGW-w64 (gcc) 环境：

```bash
make
```

输出 `taskpin.exe`，单文件零依赖。

## 配置

首次运行自动生成 `config.ini`（UTF-16LE 编码），可在 Settings 对话框中调整显示参数。

## 项目结构

```
main.c        主窗口/消息循环/编辑对话框/设置对话框
appbar.c/h    任务栏嵌入（SetParent）
fetcher.c/h   WinHTTP 异步拉取
config.c/h    INI 读写（UTF-16LE）
json.c/h      轻量 JSON 解析 + JSONPath
taskpin.rc    资源文件（图标）
taskpin.ico   应用图标
Makefile      MinGW 编译脚本
```

## 技术栈

- 纯 C (C99)，Win32 API
- 零第三方依赖
- 链接库：winhttp, user32, shell32, gdi32, shlwapi, comctl32