# TaskPin Flutter 重写 + 全新 UI 设计（分阶段派发 agy 实现）

## 实施状态（2026-10-19 核对）

本文是 2026-10 的派发计划，多数阶段已落地。下表按仓库现状（`lib/`、`packages/`、`native/`、`windows/`、`macos/`、`.github/workflows/`）核对，**不是**计划目标：

| 阶段 | 状态 | 依据 / 缺口 |
|---|---|---|
| 0 脚手架、i18n、CI | 部分 | Flutter 两平台工程、`lib/l10n`、`tool/migrate_lang.py` 已就绪；CI 只有 `release.yml`（tag/手动触发），计划里的 push 构建 `build.yml` 没有建 |
| 1 配置模型 + 迁移 | 已完成 | `lib/core/config/{config_schema,config_repository,migration}.dart` + `test/config/` |
| 2 统一 C 引擎 | 部分 | Windows 侧完整；`tp_http_mac.m` / `tp_sysinfo_mac.m` 仍是 `#error` 桩；无 `test/engine/golden/*.json`（只有 `engine_run_test.dart` 与 `run_engine_tests.sh`）；计划里的 `tp_image.c` 不存在 |
| 3 Dart FFI + isolate | 已完成 | `packages/taskpin_engine/lib/src/{bindings,engine_isolate,engine_api}.dart` |
| 4 设计系统 | 已完成 | `packages/taskpin_design`（token + 组件）；`/gallery` 路由在 `lib/app/shell/routes.dart`，gallery 本体在 `packages/taskpin_design/lib/src/gallery/`；未提交 golden 图片 |
| 5 Shell + Signals 列表/编辑器 | 已完成 | `lib/app/shell/`、`lib/features/signals/` |
| 6 DialogSpec 弹窗窗口 | **部分** | Dart 渲染完整；Windows 原生 `taskpin/window` 未编入、未注册（见下），边框/穿透/透明度静默失效 |
| 7 Windows 原生条 | 部分 | `bar_window` / `bar_render_d2d` / `bar_embed` / `bar_channel` 已存在；自动重排从未生效（见下） |
| 8 macOS 菜单栏 + popover | 部分（未在本机验证） | `native/mac/{StatusItemView,StatusItemPlugin,PopoverHost}.swift`；需在 mac 上实机验收 |
| 9 WebView2 / WKWebView | 未开始 | 只有 `lib/features/dialogs/items/webview_item.dart` 占位；`native/` 下无 webview host |
| 10 插件市场 | 已完成 | `lib/core/market/`、`lib/features/market/` + 测试 |
| 11 自动更新 + 提权 | 部分 | `lib/core/update/`、`lib/core/elevate/` + 测试；计划里的 `native/win/relaunch_helper.cpp` 不存在（替换/重启在 Dart 里完成）；版本比较语义待产品决策（见下） |
| 12 打包、发布、迁移文档 | 部分 | `release.yml` 已改成 Flutter 产物；`docs/MIGRATION.md`、`docs/FLUTTER_ARCH.md` 不存在 |
| 13 删除旧实现 | 未开始 | `src/`、`third_party/`、`Makefile`、`Package.swift` 仍在；`lib/` 根目录还有 C 源与 `.o` |

> 阶段编号沿用本文，实施细节以 `docs/UI_REFACTOR_PLAN.md`（UI）与 `docs/VISUAL_SPEC.md` 2.0（视觉）为准。

## Context

TaskPin 把 Lua 脚本的渲染结果"钉"进 Windows 任务栏（macOS 为菜单栏）：脚本返回富文本 span（`font()` / `icon()`）和可选的点击弹窗 spec，宿主把一个小窗口 `SetParent` 进 `Shell_TrayWnd` 显示。

重写动机：

- **三套 UI 实现并存、互不复用**：Windows 任务栏条是 Win32/GDI 手绘（`src/bar_window.c`），管理窗口是 Dear ImGui + D3D11（`src/ui_*.cpp`），弹窗又是一套 GDI 自绘（`lib/script_dialog.c`）；macOS 整份是 SwiftUI（`src/macos/`）。任何 UI 改动要写 2~3 遍。
- **UI 不成体系**：`src/ui_theme.h` 是 Darcula/Discord 混搭暗色，`DESIGN.md` 的 Uber 黑白规范只落地了一部分，任务栏条本身还是 GDI `TextOutW` 像素级排版（对齐、滚动、双行全靠手算坐标）。
- **两份实现已经漂移**：Lua 引擎有两份（`lib/scripting.c` 宽字符 / `src/clua_bridge/taskpin_lua.c` UTF-8），后者缺 `align` 和 `newline`，导致 macOS 的菜单栏只保留第一个 span 的颜色（`StatusBarManager.swift:95-123`）；配置也是两套不兼容的 schema（见下）。
- **平台能力硬编码**：`lib/appbar.c` 直接 `SetParent` 进任务栏，`lib/sysinfo.c` 全是 Win32。

目标：用 Flutter 重写整套应用（Windows + macOS），UI 全部重新设计，**完整保留** Lua 脚本 API 与语义、配置迁移、插件市场、自动更新、任务栏/菜单栏嵌入。

## 已确认的决策

| 项 | 决策 |
|---|---|
| 派发方式 | Antigravity `agy` CLI（headless），逐阶段派发 |
| 目标平台 | Windows + macOS，同步推进 |
| UI 设计 | 由 Claude 重新设计（新 token + 组件语言） |
| **任务栏条渲染** | **混合：条用原生 C++（Direct2D + DirectWrite）重写，管理窗口/编辑/设置/市场/脚本弹窗全部 Flutter** |
| macOS 菜单栏条 | 原生 `NSStatusItem` + 自定义 `NSView`（Core Text），与 Windows 共用同一套 MethodChannel 契约 |
| 配置 | 新格式 + 自动迁移（旧文件备份为 `config.v1.json`） |
| 代码布局 | 新目录并行，功能对齐后再删旧实现 |
| 产物体积 | 接受体积回归，README 宣传口径同步改 |
| WebView2 | 要，作为独立阶段实现 |
| Lua 编辑器 | 纯文本 + 行号（不做语法高亮/补全） |
| Windows 配置位置 | exe 同级优先（便携），否则 `%APPDATA%\TaskPin\` |
| 脚本提权 | 重新实现（`elevate.*` i18n key 保留） |
| 旧代码清理 | 末尾阶段统一删除 |

### agy 调用方式（已实测）

`agy` 在 `C:\Users\WIN10\AppData\Local\agy\bin\agy.exe`，版本 1.3.5，**不在 shell PATH 中**，用绝对路径调用：

```
& "$env:LOCALAPPDATA\agy\bin\agy.exe" --mode accept-edits --dangerously-skip-permissions `
  --add-dir D:\workspace\taskpin --output-format json --print-timeout 0 -p "<phase prompt>"
```

- flag 必须在 `-p` 之前（CLI 把 `-p` 的下一个参数当 prompt）。
- 修复轮次用 `--conversation <id>` 或 `-c` 接同一会话，避免重复喂上下文。
- **先验证**：旧版（1.0.6）有 `agy -p` 在非 TTY / stdout 重定向时挂起不输出的报告（[issue #318](https://github.com/google-antigravity/antigravity-cli/issues/318)）。1.3.5 未验证 —— 派发 Phase 0 之前先跑一个 trivial 任务（"读 README.md 输出标题"）确认能正常返回。

### 第 0 步（批准后立即执行）

把本计划复制到仓库：`docs/FLUTTER_REWRITE_PLAN.md`，让后续派发给 `agy` 的每个阶段 prompt 都能用 `--add-dir D:\workspace\taskpin` 直接引用它作为上下文（例如"按 docs/FLUTTER_REWRITE_PLAN.md 的 Phase 4 执行"），而不是每次把长 prompt 重贴一遍。

### 环境前置（Phase 0 前必须补齐）

| 依赖 | 现状 | 动作 |
|---|---|---|
| Flutter SDK | **未安装** | 装 stable，`flutter doctor` 通过 |
| MSVC C++ 工具链 | **缺** —— 只有 `BuildTools/Common7`，无 `VC/` 目录 | VS Installer 勾选"使用 C++ 的桌面开发"（Flutter Windows 桌面**强制要求 MSVC**，不能只用 MinGW） |
| CMake / Ninja | `D:\CMake\bin\cmake.exe`、`D:\mingw64\bin\ninja.exe` | 已有，Flutter 会自带 CMake 亦可 |
| Xcode | 不在本机 | macOS 阶段需在 mac 上跑，或交给 CI |

## 现状架构速查（重写需覆盖的全部行为）

### 入口与生命周期
`src/main.c` — `wWinMain`：单实例 mutex → `config_load` → `i18n_init` → `script_init` → 注册 `TaskPinBarClass` → `bars_create_all()` → `modern_ui_show()` → 后台更新检查线程 → 消息循环。

### 任务栏条（核心）
- `src/bar_window.c` — 每个 `pinned` item 一个 `WS_POPUP` 窗口（`MAX_BARS` 16）；`WM_PAINT` 手绘 span（图片 `AlphaBlend`，文本 `TextOutW`，双行/左右对齐靠累加坐标）；`WM_TIMER` 驱动刷新/跑马灯/动画；滚轮改宽度、Shift+滚轮改 X 位置并落盘；右键菜单 Unpin/Manage/Exit；单击触发 `show_script_dialog()` 或开 URL；双击开管理窗口。
- `lib/appbar.c` — `FindWindowW("Shell_TrayWnd")` → `SetParent`，去 `WS_POPUP` 加 `WS_CHILD`；`cfg_x < 0` 时自动定位到 `TrayNotifyWnd` 左侧。

### Lua 引擎（必须完整保留）
- API：`font()` / `icon()` / `dialog()` / `json.decode` / `http.get|post|put|delete` / `sys.*` / `log`；span 用 `..` 拼接（`l_span_concat`）。
- 返回约定：`return <display>, <clickable:bool>, <click_url|dialog_spec>`。
- 头注释：`-- @param <key> <type> <label>`、`-- @refresh <ms>`（`script_parse_params` / `script_parse_refresh`）。
- 数据结构：`DisplaySpan` / `DisplayContent`（max 32 span、2 行）、`DialogSpec`（`DI_TEXT|DI_HR|DI_TABLE|DI_IMG|DI_BUTTON`，max 8 items / 6 列 × 24 行）。
- `lib/sysinfo.c` 全是 Win32：`GetSystemTimes`、`GlobalMemoryStatusEx`、`GetDiskFreeSpaceExW`、`GetSystemPowerStatus`、`CreateToolhelp32Snapshot`、`GetTcpTable`、`GetProcessIoCounters`、`GetIfTable`。
- 文档 `docs/LUA_API.md` / `LUA_API_EN.md` 是 API 契约，重写后必须一致，否则同步改文档。

### 配置（两套已漂移，必须统一）
- Windows：`lib/config.c` + `config.json`（exe 同级），`PinItem`/`TaskPinConfig`，颜色存 `"AARRGGBB"`（`"FFFFFFFF"` = 用全局默认）。
- macOS：`~/.taskpin/config.json`，Swift `Codable`，**schema 不兼容** —— UUID `id`、camelCase、缺 `bar_x/y`/`bar_bg_color`/`dlg_*`。
- 统一到 Windows schema，macOS 旧文件检测后转换。

### 插件市场
`src/market_dialog.c` — 源是 `sources[]` 里的 `user/repo`；先取 `manifest.json`，失败退到 GitHub API `contents/`；`.lua` 下载到 exe 同级 `scripts/`。国内走 `gh-proxy.com` 前缀（`api.ip.sb/geoip` 判 `country_code=CN`）。

### 自动更新
`lib/update.c` — 拉 `raw.githubusercontent.com/bestK/taskpin/master/version.txt`，**字符串比较**（非 semver，必须保持，否则老用户升级行为变化）。注意：这条约束只约束**服务存量用户的 C 更新器**；新客户端是否照抄见 Phase 11 的"更新语义（待产品确认）"；确认后下载 `releases/latest/download/taskpin-x64.exe` 到 temp，写 `.bat`（等待→覆盖→重启→自删）后 `ExitProcess`。

### 其他既有行为
- i18n：`lang/{en-US,zh-CN}.json`，99 key（`main.*`/`edit.*`/`settings.*`/`market.*`/`bar.*`/`webview.*`/`elevate.*`/`scripting.*`）。
- 提权：`elevate.*` 四个 key 还在，但实现代码已不在源码中 —— 需按 key 语义重新实现。
- `PinItem.realtime` 字段存在但从未被读取（死字段）—— 计划中删除。
- 跑马灯滚动、Shift+drag/滚轮操作 borderless 窗口（`lib/script_dialog.c`）。

### 已核实的既有缺陷（重写时修复，非移植）

1. **4 个被示例脚本引用但零实现的 Lua API** —— `sys.is_china()`、`sys.gh_proxy()`、`sys.watch_keys()`、`webview` 类型。在 `lib/`、`src/` 和现有 `taskpin.exe` 里都搜不到符号，说明这些示例脚本**现在就是坏的**。已确认全部补齐（`is_china`/`gh_proxy` 可复用 `lib/update.c` 和 `src/market_dialog.c` 里已有的 `api.ip.sb` geo-IP 逻辑）。注：`examples/` 实际是 16 个 `.lua`（非计划原先写的 19）。
2. **macOS `l_font` 参数判断错误** —— `src/clua_bridge/taskpin_lua.c` 的守卫导致 `font("a", "#fff")` **静默丢掉颜色**。`lib/scripting.c` 是对的。移植到统一引擎时自动修复，已加回归测试。
3. **设置页颜色输入会 R/B 互换** —— `src/settings_dialog.c:140` 和 `src/ui_settings_view.cpp:64` 把用户输入的 hex 直接喂给 `wcstoul`，但格式是 `0x00BBGGRR`，所以输入 `FF0000`（想表达红色）实际得到蓝色。读写本身自洽（不是往返 bug），但 UI 有真实可用性缺陷。新 UI 要修展示（真彩色选择器 + 正确标注格式），**磁盘格式必须保持兼容**。
4. **`params` 为空时省略而非空数组** —— `lib/config.c:417` 的 `if (it->param_count > 0)`。8 个真实 item 里有 5 个没有 `params` 键。新配置层序列化必须沿用，否则往返不等。
5. **`sources: []` 不可往返** —— `lib/config.c:166-169` 在加载时注入 `["bestK/taskpin-plugins"]`。
6. **`version` 字段不在 C 结构体里** —— `lib/config.c:379` 硬编码 `1` 且从不读取。
7. **`CFG_MAX_ITEMS 64` vs `MAX_BARS 16`** —— 配置允许 64 个可 pin item，条层只支持 16（`src/ui.h:49`）。不一致需统一。

### 构建与发布
- `Makefile`：MinGW-w64，`MODE=dev|release`，版本取自 `version.txt`，静态链接，产物 `taskpin.exe`。
- `Package.swift`：SwiftPM，macOS 14+。
- `.github/workflows/release.yml`：macos-14 出 `TaskPin.app`+`install.command`+zip；windows-latest 走 MSYS2 `make MODE=release`，出 zip 和 `taskpin-x64.exe`；`release` job 仅 tag 时发布并校验 tag == `v$(cat version.txt)`。

**发布资产名不能变**：`taskpin-x64.exe`、`TaskPin-windows.zip`、`TaskPin-macos.zip` —— 老版本靠这些名字自动更新。

---

## 目标架构

### 仓库布局

仓库根目录就是 Flutter 应用（`version.txt` / `lang/` / `examples/` / `scripts/` 已在这，CI 依赖这些路径）：

```
pubspec.yaml  version.txt  l10n.yaml
lib/
  main.dart                        窗口引导、引擎初始化、DI
  app/  shell/{app_shell,routes}.dart, windows/dialog_window.dart
  features/  signals/ dialogs/ market/ settings/
  core/  config/{config_schema,config_repository,migration}.dart
         engine/{engine_provider,engine_run}.dart
         bar/{bar_controller,bar_channel,bar_source}.dart
         update/update_service.dart   market/{manifest,github_api,gh_proxy}.dart
         l10n/（ARB 在 lib/l10n/）
packages/
  taskpin_design/     设计 token + 组件库（纯 Dart，无平台依赖）
  taskpin_engine/     C ABI 的 Dart 封装（ffi + isolate）
native/
  engine/            统一 Lua 引擎（C）：taskpin_engine.h（唯一 ABI）
                     taskpin_lua.c  tp_http_{win,mac}  tp_sysinfo_{win,mac}  tp_image.c  lua/
  win/               原生条 + 窗口控制（C++）：bar_window / bar_render_d2d / bar_embed
                     bar_channel.cpp（MethodChannel）  dialog_window_styles.cpp（taskpin/window）
  mac/               StatusItemView.swift  StatusItemPlugin.swift  PopoverHost.swift
                     DialogWindowStyles.swift
lang/ examples/ scripts/ docs/        保留
src/ lib/ third_party/imgui/ Package.swift Makefile    迁移完成后删除
```

### 状态管理：Riverpod 2.6.1（手写 provider，无 riverpod_generator）

**实际实现**：`flutter_riverpod ^2.6.1`，全部是手写的 `Provider` / `NotifierProvider`，没有使用 `@riverpod` 注解。`pubspec.yaml` 的 dev_dependencies 注释说明了原因：`riverpod_generator`/`riverpod_lint`/`custom_lint` 会把 `analyzer` 钉在 ^6/^7，与 `test`（经 `flutter_test` 的 `matcher 0.12.20`）冲突。若以后要 codegen，先解决这个依赖冲突。

选 Riverpod 而非 Bloc：本应用是"多个独立定时器产出脚本结果 → 汇成少数派生视图"的形态，`StreamProvider.family` + 编译期 DI 天然契合，且不依赖 widget tree 即可测试。

- `configProvider` — `NotifierProvider`，负责加载/保存/迁移，写入防抖 + 原子替换
- `engineProvider` — FFI 引擎句柄
- `scriptResultsProvider` — `StreamProvider.family<ScriptResult, ItemId>`，每个 pinned item 一条流
- `barStateProvider` — 汇总推给原生条
- `marketProvider` / `updateProvider`

路由用 `go_router` + `ShellRoute`（nav rail）：`/signals`、`/signals/:id`、`/market`、`/settings`、`/diagnostics`；二级窗口走独立顶层路由。

### Lua 引擎：dart:ffi（不用 MethodChannel）

macOS 侧的 `src/clua_bridge/taskpin_lua.h` 已经是扁平 UTF-8 C ABI over POD structs，正是 `dart:ffi` 想要的形状 —— 把它扩成唯一 ABI，Windows 侧移植过去，比重新实现 20k 行 Lua 胶水便宜得多。

- **Isolate 模型**：Lua 单线程有状态（`g_L`）。用一个专用 isolate 独占引擎，`SendPort` 收发。UI isolate 绝不直接调 FFI。C 侧本来就是每 item 同步执行，串行化与现有语义一致，还白拿背压。ABI 从第一天就设计成 handle-based（`tp_engine_create()` 返回不透明句柄），即使 v1 只跑 N=1，后续要 N=2 分流慢 HTTP 时不用改 ABI。
- **ABI 要点**（在 `taskpin_lua.h` 基础上扩展，不另发明）：

```c
typedef struct {
  char text[512];   // 文本，或 is_image 时的图片源
  char color[16];   // "#RRGGBB" 或 "" = 默认
  int  font_size;   // 0 = 默认
  int  align;       // 0 left / 1 right / 2 center   ← 新增
  int  newline;     // 1 = 另起一行                  ← 新增
  int  is_image, img_w, img_h;
} TPSpan;

typedef struct {
  TPDisplayContent rich;
  char display[2048];      // 纯文本兜底
  int  clickable, click_action;   // 0=url 1=dialog
  char click_url[1024];
  TPDialogSpec dialog;
  char error[1024];        // 新增：Lua 错误单独出，不再塞进 display
} TPScriptResult;

TPEngine* tp_engine_create(void);
void      tp_engine_destroy(TPEngine*);
int  tp_execute_file(TPEngine*, const char* utf8_path, const char* args_json, TPScriptResult*);
int  tp_execute_template(TPEngine*, const char* lua_code, const char* response_raw, TPScriptResult*);
int  tp_parse_params(const char* path, TPParamDecl* out, int max);   // 从 Swift/C 两处收归一处
int  tp_parse_refresh(const char* path);
void tp_set_log_callback(TPEngine*, void (*cb)(int, const char*, void*), void*);
```

`error` 字段是刻意改进：现在 Lua 报错被写进 `result->display` 然后**渲染进任务栏**（`lib/scripting.c`），所以条上会出现裸 stack trace。新设计里错误走 item 的错误态 UI。

- **看门狗**：`lua_sethook` 设指令预算（如 5000 万条 → 报错）。现在 `while true do end` 会永久挂死工作线程，这是实打实的健壮性修复。

### C 库的构建方式

不要 `DynamicLibrary.open` 外部 DLL —— 静态链进 app，保住"单产物、零运行时依赖"的精神。

- **Windows**：`native/engine` + `native/win` 编成 STATIC 库，从 `windows/CMakeLists.txt` 用 `add_subdirectory` 链进 runner。**runner 本身必须 MSVC**（Flutter Windows embedder 要求），所以引擎也用 MSVC 编，不要在同一二进制里混工具链 —— 把 WinHTTP / IP Helper 两处 `#ifdef` 改成 MSVC-clean C。引擎不定义 `UNICODE`（ABI 是 UTF-8）。
- **macOS**：`native/engine` 编成静态库链进 app bundle，走 CocoaPods podspec（Flutter macOS runner 已用 CocoaPods，比加 SwiftPM target 摩擦小）。`tp_http_mac.m` 用 `NSURLSession` 同步（信号量），与 WinHTTP 的阻塞契约一致。
- Lua 保持 vendored（`lib/lua` 已在仓库），不依赖系统 Lua；`LUA_COMPAT_5_3` 必须保留，示例脚本可能依赖它。

### Windows 任务栏条：原生 Direct2D 表面

**不重父化 Flutter 窗口**，理由：

- Flutter 引擎的 DXGI swapchain 绑在那个 HWND 上，runner 的 `WndProc` 假定自己是 root window（`WM_SIZE`/`WM_DPICHANGED`/`WM_ACTIVATEAPP`）。把它变成别的进程窗口的 `WS_CHILD` 是未支持路径，Flutter 升级可能静默破坏。
- **成本**：一个条一个 Flutter 引擎。16 个条的上限、实际 3~8 个 pinned item，就是几百 MB RSS 和 N 个 raster 线程，只为渲染 40px 高的东西。
- **explorer 重启**：`Shell_TrayWnd` 被销毁时子窗口一起没。GDI 条重建很简单，N 个 Flutter 引擎窗口恢复是真正的难题。
- 跨进程子窗口的合成/z-order 是未定义行为，任务栏 hover/自动隐藏时会有重绘残影。
- 新的 windowing multi-view（`--enable-windowing`）是"官方路径"且能把成本降到单引擎，但仍是 feature-flag 且**不解决"别的进程的子窗口"这个真正的拦路虎**。

**方案**：`native/win` 每个 pinned item 一个子窗口

- `CreateWindowExW(WS_EX_TOOLWINDOW, ...)` → `SetParent(hwnd, Shell_TrayWnd)` → 去 `WS_POPUP` 加 `WS_CHILD` → `SetWindowPos` 到 `TrayNotifyWnd` 左侧。算法沿用 `lib/appbar.c` 并加固。
- 用 **Direct2D + DirectWrite** 而非 GDI。这是实质升级：DirectWrite 给正确的 CJK 字体回退和**彩色 emoji**（GDI 做不到），以及逐字形 alpha 和真正的次像素控制 —— GDI `TextOutW` 正是现在条看起来"平"的原因。
- Dart 通过 **MethodChannel**（`taskpin/bar`）驱动：`setSpans(barId, spans)` / `setGeometry` / `setStyle`；native → Dart 事件 `onClick` / `onWheel` / `onContextMenu` / `onHoverChange`。条用 channel 不用 FFI：载荷小且低频（≤ 几 Hz），native→Dart 从插件 registrar 在 UI 线程发很简单，而从 Win32 消息循环回调进 Dart 才是脆弱的部分。FFI 留给引擎。
- **explorer 重启自愈**：`SetWinEventHook(EVENT_OBJECT_CREATE)` 监听任务栏，或 2 秒轮询 `FindWindowW("Shell_TrayWnd")` 句柄变化后重新嵌入。**现在没有这个逻辑**，是潜在 bug。
- **多显示器**：`FindWindowW("Shell_TrayWnd")` 只找主任务栏，副屏是 `Shell_SecondaryTrayWnd`。把目标做成参数。
- **透明**：现在 `bg_color = 00000000` 被喂给 `CreateSolidBrush`，所谓"透明"其实是黑色。子窗口不能真正穿透；要真透明得 `WS_EX_LAYERED` + `UpdateLayeredWindow`（Win8+ 支持子窗口），即渲染到 DIB/`ID2D1Bitmap` 再 blit。**明确取舍**：默认不透明子窗口，仅当 `bg_color` alpha < 255 时走 layered。

### macOS 菜单栏条：原生 NSStatusItem + 自定义 NSView

Flutter **无法**渲染进 `NSStatusItem`（状态栏按钮是系统拥有的 layer-backed NSView，Flutter 需要自己的 `NSWindow`/`NSView` + Metal layer + `FlutterViewController`）。镜像 Windows 的设计：原生 `NSStatusItem` + 自定义 `NSView`，Core Text 绘制，共用同一个 `taskpin/bar` channel 契约 —— Dart 侧 `BarController` 两端一致，只有 native painter 不同。

这同时**修掉一个真实缺陷**：现在 `StatusBarManager.updateStatusItem` 只设一个 `attributedTitle` 和一个 `button.image`，脚本返回 `font("A",red)..font("B",green)` 会丢掉除第一个颜色外的全部。自定义 view 绘制完整 span 列表是严格改进。

菜单栏高 24pt：**最多一行**，字号钳制，超长省略号截断。macOS 的脚本弹窗仍用 Flutter（`NSPopover` + `FlutterViewController`，或用无边框 `NSWindow` 做 HUD）；`borderless`/`clickthrough`/`opacity` 映射到 `NSWindow` 的 `level`/`ignoresMouseEvents`/`alphaValue`/`styleMask`，比现在折腾 `WS_EX_*` 干净。

### 引擎/UI 边界

| 关注点 | 位置 | 理由 |
|---|---|---|
| Lua VM、`font`/`icon`/`dialog`/`json`/`log`/`sys.*` | **C**（`native/engine`） | 精确保持语义，已写好，FFI 友好 |
| `http.*` | **C**（`tp_http_win.c` / `tp_http_mac.m`） | `http.get` 是**阻塞**的且在 Lua 调用帧内。路由到 Dart 需要从非 Dart 线程同步重入 Dart VM，脆弱且慢 |
| sysinfo | **C**（`tp_sysinfo_*`） | 从 `lib/sysinfo.c` + `taskpin_lua.c` 移植；唯一需要 `windows.h` / IP Helper 的地方 |
| **条**的图片解码 | **C**（`stb_image` + GIF） | 条是原生表面，必须本地解码；沿用现有缓存/动画逻辑 |
| **弹窗**的图片解码 | **Dart** | `Image.file`/`Image.network`/`Image.memory` 免费拿到 PNG/GIF/动图；在 C 里重解码再交给 Flutter 是浪费。`data:` URI 在 Dart 里 base64 解 |
| 原生条表面 / 窗口嵌入 | **C++ / Swift** | Win32 / AppKit |
| 配置加载/保存/迁移、管理 UI、弹窗 UI、市场 UI、i18n | **Dart** | 重写的意义所在 |
| 市场抓取（manifest / GitHub API / gh-proxy） | **Dart**（`http` 包） | 纯 HTTP+JSON，无 C 收益，更好测，能用真正的 TLS/代理处理 |
| 自动更新 | **Dart** + Windows 小原生辅助 | 下载/比版本/原子写用 Dart 简单；"替换正在运行的 exe"那套 detached batch（`lib/update.c:98-125`）保留，由 Dart 调起。macOS 替换 `.app` 内文件后重启 |

**原则**：条在 60fps 需要的东西、或在 Lua 调用帧内的东西，留在原生；其余全 Dart。

---

## UI 重设计方案 —— "Aurora"（已废弃，仅作历史记录）

> **已被取代**：`docs/VISUAL_SPEC.md` 2.0（Windows 11 原生方向）取代本节的暗色 "Aurora" 语言，随后 `docs/UI_REFACTOR_PLAN.md` 取代 2.0 的实施细节。本节保留只用于理解早期决策。
>
> 两处已改变的决定：
> - **字体**：不再内置 Inter / JetBrains Mono。全部使用系统字体（Windows `Segoe UI` / `Cascadia Mono`，macOS `SF Pro` / `SF Mono`），`pubspec.yaml` 不加 `fonts`。
> - **主题**：不再是"暗色优先"。跟随系统，浅色为基准，深色为镜像（`VISUAL_SPEC.md` 2.0 §1）。
> - 组件清单里的 `lucide_icons` 也没有引入；图标沿用 `TpIcons`（Windows 用 Segoe Fluent Icons）。

暗色优先、克制、高信噪比的系统。刻意不是 Uber 黑白、不是 ImGui、不是 Darcula。组织理念：**监控工具应该像仪表盘，而不是文档。** 因此：深中性底色、单一强调色、语义色只用于状态、所有出现指标的地方用等宽表格数字、偏大的圆角营造柔和的仪器感。

### 色彩（三层：primitive → semantic → component）

Primitive（暗）：`neutral.0 #0B0D10`、`100 #0E1116`、`200 #14171C`、`300 #1B1F26`、`400 #232A33`、`500 #333C48`、`600 #4A5361`、`700 #6B7686`、`800 #A2ACBA`、`900 #E6EAF0`。
强调色 `iris.400 #5B8DEF`、`iris.500 #4C7FE0`、`iris.600 #3D6BC7`、`iris.subtle #16233A`。
语义：`success #3FB950`、`warning #D29922`、`danger #F85149`、`info #58A6FF`，各配 12% alpha 的 `*.subtle` 填充。

Semantic（暗）：`bg/base|raised|overlay|inset`；`border/subtle|strong|focus`；`text/primary|secondary|tertiary|disabled|onAccent`；`state/success|warning|danger|info|neutral`。
浅色主题是一等公民的镜像（canvas `#FFFFFF`、raised `#F7F8FA`、inset `#F1F3F5`、text `#12161C`）—— 任务栏本身可以是浅色的。

### 字体

内置 **Inter**（UI）+ **JetBrains Mono**（代码/脚本/key），所有指标显示加 `fontFeatures: [tabularFigures]`。
**条用系统字体**（Segoe UI Variable / SF Pro）以匹配 shell —— 不把 Inter 强加到任务栏上。

字阶：`display 28/36 ·700`、`title 20/28 ·600`、`headline 16/24 ·600`、`body 14/20 ·400`、`bodyStrong 14/20 ·500`、`label 13/18 ·500`、`caption 12/16 ·400`、`micro 11/14 ·500`（大写 eyebrow，+0.4 tracking）、`mono 13/20`。

### 间距 / 圆角 / 高度 / 动效

- **间距**（4px 基准）：`2 4 6 8 12 16 20 24 32 40 48`
- **圆角**：`xs 4 · sm 6 · md 8 · lg 12 · xl 16 · pill 999`；卡片 `lg`、输入 `md`、chip `pill`、浮层 `xl`
- **高度**：`0` 平（列表）、`1` `0 1 2 rgba(0,0,0,.32)`（卡片）、`2` `0 4 12 rgba(0,0,0,.36)`（popover）、`3` `0 12 32 rgba(0,0,0,.44)` + `scrim rgba(6,8,11,.56)`（模态）
- **动效**：`fast 120ms` / `base 180ms` / `slow 240ms`；曲线 `standard cubic(0.2,0,0,1)`、`decelerate cubic(0,0,0,1)`、列表重排用 spring。尊重 `MediaQuery.disableAnimations`
- **焦点环**：2px `border/focus` + 2px offset，所有可交互元素都要。现在 ImGui 和 Win32 条**完全没有键盘焦点体系**，这是新增能力

### 组件清单

`packages/taskpin_design`，每个组件配 golden 测试 + `/gallery` 路由（debug-only）里的条目，让 agent 不用起整个应用就能目视验证：

- **Shell**：`AppShell`、`NavRail`（图标+文字，可折叠）、`PageHeader`、`Toolbar`、`SplitPane`
- **Data**：`SignalCard`（名称、类型徽标、来源、间隔、实时状态点、sparkline 槽位）、`SignalGrid`（给重度用户的密集表格）、`MarketCard`、`SourceChip`、`KeyValueList`
- **Status**：`StatusDot`、`StatusPill`（running/stale/error/paused）、`IntervalBadge`、`RelativeTime`、`Sparkline`
- **Forms**：`TextField`、`TextArea`、`NumberField`、`IntervalField`（值 + 单位下拉）、`ColorField`（色块 + hex + alpha）、`Select`、`Switch`、`SegmentedControl`、`ParamField`（由 `@param` 声明驱动）、`PathPicker`、`HeaderListEditor`（对应 `req_headers`）
- **Feedback**：`Toast`/`ToastHost`、`InlineBanner`、`ConfirmDialog`、`EmptyState`、`ErrorState`、`Skeleton`、`ProgressBar`、`Tooltip`
- **Code**：`LuaEditor`（等宽 + 行号）、`ResponsePreview`、`ExpressionEditor`（`$.path`，可从实时响应补全）
- **Bar 专用**：`BarPreviewStrip`（在 Flutter 里渲染**同一个** span 模型，pin 之前在管理窗口里就能看到条的样子）、`SpanInspector`（逐 span 覆盖颜色/字号/对齐）、`DialogSpecPreview`
- **图标**：UI 用 `lucide_icons`；条用脚本 `icon()` 返回的图

### 条的视觉语言 —— "segments"

现在是"深色矩形 + 各自着色、无结构的文字段"。新语言：

- 条是一组横向 **segment**，每个 = 可选图标 + 标签 + 可选值，垂直居中
- **分隔线**：segment 之间 1×14px、20% alpha 的竖线，左右 6px 间距。这是把"绿字挨着红字"变成可读读数的关键
- **状态条**：最左侧 2px 通高竖条，用 item 状态色（running 透明 / error danger / stale warning）。状态一眼可见，且不用碰脚本自己的颜色
- **指标用表格数字**，值变化时不会抖动 —— 现在 `CPU: 9%` → `CPU: 100%` 会让右边所有东西位移
- **Hover**：`bar/bgHover` 填充 + 上下 1px `bar/hairline` 内描边，替代现在突兀的 `RGB(39,39,39)` 换色
- **状态**：loading = 55% 不透明 + shimmer；error = danger 状态条 + `!` 字形；stale = `now - lastUpdate > 2×interval` 时 warning 状态条（新增，便宜且确实有用）
- **尺寸**：Windows 高 = 任务栏高（Win11 @100% 是 48，Win10 是 40），内边距 8 横 / 6 竖，图标 16，圆角 0（任务栏段是方的）。macOS 高 24，内边距 6 横，圆角 6，**最多一行**

原生渲染器必须遵守的 bar token：`bar/bg`、`bar/bgHover`、`bar/hairline`、`bar/separator`、`bar/state.{running,error,stale}`、`bar/icon`、`bar/label`、`bar/value` + 上面的尺寸。**这个列表要短且冻结** —— 每个 token 都在 C++/Swift 里重复一份。

---

## 分阶段派发（每阶段 = 一次 agy 运行）

每阶段必须产出**可运行、可验证**的产物，且不依赖后续阶段才能测试。Phase 0 必须先做；之后 2/3 与 4 可并行；5 依赖 1+3+4；6 依赖 5；7 与 8 在 3+6 之后相互独立；9/10/11 在 5 之后可并行；12 依赖 7+8+9+10；13 最后。

### Phase 0 — 脚手架、i18n 迁移、CI 骨架
- **交付**：Flutter 应用在两个平台能构建并启动空窗口；`lang/*.json` 迁到 ARB 零丢 key；CI 在 push 时构建两平台（不发布）
- **文件**：`pubspec.yaml`、`lib/main.dart`、`windows/`、`macos/`、`l10n.yaml`、`lib/l10n/app_{en,zh}.arb`、`tool/migrate_lang.py`、`.github/workflows/build.yml`、改 `release.yml`（实际只改了 `release.yml`，没有新增 `build.yml`）
- **验收**：CI 上 `flutter build windows` 与 `flutter build macos` 成功；测试断言 `app_en.arb` key 集合 == `app_zh.arb` key 集合 == 从原 `lang/en-US.json` 解析出的 99 个 key；`version.txt` 原样读进 About 页

### Phase 1 — 配置模型 + 兼容 + 迁移
- **交付**：Dart 配置层，读写与 Windows `config.json` **逐字段兼容**
- **文件**：`lib/core/config/{config_schema,config_repository,migration}.dart`、`test/config/golden_config.json`、`test/config/roundtrip_test.dart`
- **验收**：加载仓库里真实的 `config.json`（8 个 item、`sources:["bestK/taskpin-plugins"]`、`bar_bg_color:"FFFFFFFF"`、`$.subscriptionTitle $$.currentUsage` 的 `field_expr`）→ 序列化 → 与输入**逐字段 JSON 相等**（key 顺序与 tab 无关）；未知 key 往返保留；`version > 1` 时明确报错拒绝。迁移路径：Windows 优先 exe 同级，缺失则 `%APPDATA%\TaskPin\`（首次从 exe 同级拷 `config.json` + `scripts/`）；macOS 检测 `~/.taskpin/config.json` 的旧 Swift schema（UUID `id`、camelCase）并转换，旧文件备份为 `config.v1.json`

### Phase 2 — 统一 C 引擎
- **交付**：`native/engine` 在 MSVC 与 Clang 下编成静态库；CLI 夹具 `taskpin_engine_cli` 能跑任意脚本并打印 `TPScriptResult` 的 JSON
- **文件**：`native/engine/taskpin_engine.h`、`taskpin_lua.c`、`tp_http_{win,mac}.*`、`tp_sysinfo_{win,mac}.*`、`CMakeLists.txt`、podspec、`tool/engine_cli.c`、`test/engine/golden/*.json`（`tp_image.c` 最终没有单独存在：条的图片解码在 `native/win/bar_image.cpp`）
- **验收**：CLI 跑通 `examples/` 全部 16 个 + `scripts/` 5 个脚本并输出 JSON。**基线捕获步骤**：先用**当前 Windows 二进制**跑同样的脚本存成 golden，新引擎输出必须在 `spans[]`、`clickable`、`click_action`、`click_url` 和 dialog `items[]` 上与之一致（确定性脚本：`rich_text_demo`、冻结时钟的 `hud_clock`、打桩 sysinfo 的 `system_monitor`）。`align`/`newline` 存在且正确。`tp_parse_params` 在每个示例上与 Swift 解析器一致。看门狗：`while true do end` 在 2 秒内返回错误而非挂死。HTTP GET/POST/PUT/DELETE 对本地测试服务器通过

### Phase 3 — Dart FFI + 引擎 isolate
- **交付**：`packages/taskpin_engine` 通过 isolate 暴露 `EngineApi`；Phase 2 的 golden JSON 测试从 Dart 侧跑通
- **文件**：`packages/taskpin_engine/lib/{bindings,engine_isolate,engine_api,models}.dart`、`test/engine/ffi_golden_test.dart`
- **验收**：Phase 2 golden 经 Dart 层通过；无 FFI 调用发生在 UI isolate（用测试断言 `EngineApi` 只能经 isolate port 触达）；struct 布局用 `sizeOf`/`offsetOf` 断言，ABI 变更会响亮失败而不是静默损坏内存

### Phase 4 — 设计系统
- **交付**：`packages/taskpin_design` 全套 token 与上文组件，加 `/gallery` 路由在暗/浅两主题渲染每个组件
- **文件**：`packages/taskpin_design/lib/**`、`packages/taskpin_design/test/**`、gallery 本体 `packages/taskpin_design/lib/src/gallery/`（`/gallery` 路由在 `lib/app/shell/routes.dart`）
- **验收**：`flutter test --update-goldens` 为每个组件在双主题生成并提交 golden；token 测试断言 token 文件之外没有裸 `Color(0x...)`（用 lint/测试强制）；`disableAnimations == true` 时无过渡渲染；每个可交互组件可键盘聚焦且有可见焦点环

### Phase 5 — 管理窗口 Shell + Signals 列表 + 编辑器
- **交付**：管理窗口：nav rail、Signals 列表、master-detail 编辑器、实时预览、pin/unpin、带确认的删除 —— 全部接真实 config + 引擎
- **文件**：`lib/app/shell/**`、`lib/features/signals/**`、`lib/core/bar/bar_controller.dart`
- **验收**：`PinItem` 每个字段可编辑并往返落盘到 `config.json`（type、name、url、req_headers、field_expr、interval_ms、click_enabled、click_url、lua_path、params、pinned、bar_width、bar_x/y、bar_bg_color、dlg_x/y/w/h）；`@param` 字段由引擎解析器自动生成而非手维护；"Test" 按钮在 isolate 里跑脚本并内联渲染结果与错误；加 item → 编辑 → pin → 重启应用，状态保持；widget 测试驱动完整的 add→edit→pin→delete 流程

### Phase 6 — DialogSpec → Flutter 弹窗窗口
- **交付**：点击条/弹窗后打开 Flutter 窗口，渲染 `text`/`hr`/`table`/`image`/`button`，支持 `borderless`、`clickthrough`、`opacity`、`refresh` 及逐行 `url`/`cmd`
- **文件**：`lib/features/dialogs/**`、`lib/app/windows/dialog_window.dart`、`native/win/dialog_window_styles.cpp`、`native/mac/DialogWindowStyles.swift`
- **验收**：每种 `DialogItemType` 都渲染，每种一个 golden；`borderless=true` → 无边框，Shift+drag 移动、Shift+滚轮缩放、ESC 关闭（对齐 `lib/script_dialog.c:592-629`）；`clickthrough=true` → 点击穿透（原生测试验证）；`opacity` 映射到 `SetLayeredWindowAttributes`/`alphaValue`；`refresh` 按间隔重跑脚本并原地更新；表格行 `url` 开浏览器、`cmd` 执行

> **状态：未完成（Windows）**。`native/win/dialog_window_styles.cpp` 不在任何 `CMakeLists.txt` 里（`native/win/CMakeLists.txt` 的 `BAR_SOURCES` 没有它），`TaskpinDialogWindowStylesRegisterWithRegistrar` 也从未被调用；而 `lib/features/dialogs/window_channel.dart:245` 的 `platformHasDialogWindowStyles` 在 Windows 上返回 `true`，`dialog_window.dart` 也直接构造 `MethodChannelDialogWindowApi`。结果：`borderless` / `clickthrough` / `opacity` / `transparentBg` 在 Windows 上**静默无效**（`MissingPluginException` 被吞掉），没有报错。
>
> 修复：把该文件加入 `native/win/CMakeLists.txt` 的 `BAR_SOURCES`，并在 `windows/runner/flutter_window.cpp` 的 `OnCreate` 里与 `TaskpinBarRegisterWithRegistrar` 并列调用 `TaskpinDialogWindowStylesRegisterWithRegistrar(registrar)`。完成前，Phase 6 不能算完成。

### Phase 7 — Windows 原生条
- **交付**：pinned item 作为活的 Direct2D 条嵌入 `Shell_TrayWnd`，支持滚轮改宽、Shift+滚轮移位、hover、点击 → 弹窗/URL、右键菜单、跑马灯、explorer 重启后自愈
- **文件**：`native/win/{bar_window,bar_render_d2d,bar_embed,bar_channel}.cpp`、`lib/core/bar/bar_controller.dart`
- **已知缺陷（重排）**：自动定位的条从未真正换过位。Dart 发 `x = -1 - offset`（`bar_controller.dart`），原生 `BarWindow::SetGeometry` 忽略 `x < 0`（`native/win/bar_window.cpp`），而自动 X 只在首次嵌入时按创建顺序算一次（`native/win/bar_channel.cpp` 的 `AutoX`/`order_`）。这是**真实缺陷**，不是待移植行为；修复方式见 `docs/UI_REFACTOR_PLAN.md` §7。
- **验收**：(a) 条出现在任务栏内托盘左侧，Win10 与 Win11、底部任务栏、100% 与 150% DPI 都正常。(b) 富 span 逐 span 颜色/字号/对齐正确，双行布局正确；一个彩色 emoji span 渲染成彩色（GDI 基线做不到，这证明 DirectWrite 接上了）。(c) 滚轮改宽 5px、钳制 50–800 并落盘；Shift+滚轮移动 X 并钳制在任务栏内。(d) 双击开管理窗口；右键出 Unpin/Manage/Exit。(e) kill 并重启 `explorer.exe` 后 5 秒内重新嵌入。(f) 3 个 pinned 条的 idle RSS 比基础应用高 < 30MB（这个数字就是不用 3 个 Flutter 引擎的理由）。(g) 脚本报错时显示错误状态条，**不**把 Lua traceback 打进任务栏

### Phase 8 — macOS 状态栏项 + popover
- **交付**：原生 `StatusItemView` 在菜单栏渲染完整 span 列表；点击开 Flutter 承载的 popover
- **文件**：`native/mac/{StatusItemView,StatusItemPlugin,PopoverHost}.swift`，共用 `bar_controller.dart`
- **验收**：脚本返回 3 个不同颜色的 span，3 个颜色都渲染出来（针对当前"只保留一色"行为的回归测试）；图标 span 16pt，仅当源为单色时做 template 着色；popover 点击打开、内容匹配 dialog spec、点击外部关闭；最多一行，超长省略号截断而非裁切；`bar.setSpans` 与 Windows 用**同一个 channel 契约**（由共享的 Dart 侧测试替身断言）

### Phase 9 — WebView2 / WKWebView 弹窗项
- **交付**：dialog 支持 `{type="webview", url=..., width=..., height=...}`；Windows 用 WebView2、macOS 用 WKWebView；`scripts/webview_demo.lua` 可直接跑通
- **文件**：`lib/features/dialogs/items/webview_item.dart`（当前是占位，Phase 9 换成真实 host）、`native/win/webview2_host.cpp`、`native/mac/WebViewHost.swift`（两者均尚未创建）
- **验收**：`webview_demo.lua` 渲染出远程页面；`borderless`/`transparent_bg` 下正确合成；WebView2 运行时缺失时显示 `webview.err_no_runtime` 的本地化文案（不再像现在那样去下载 `WebView2Loader.dll`）；`webview.drag_hint` 的 Shift 拖拽提示在 borderless 模式显示

### Phase 10 — 插件市场
- **交付**：市场页：源管理、搜索、安装、已安装状态识别
- **文件**：`lib/features/market/**`、`lib/core/market/{manifest,github_api,gh_proxy}.dart`
- **验收**：经 `manifest.json` 抓取 `bestK/taskpin-plugins` 成功；无 manifest 的仓库走 GitHub contents API 兜底并返回同样的脚本列表；geo-IP 打 `api.ip.sb/geoip`，判为 CN 时所有 GitHub URL 走 `gh-proxy.com`（URL 构造器单测，不打网络）；安装下载到 `scripts/`、新建指向它的 item 并保存 config —— 与 `mkt_download_script` 行为一致；8 个源上限有本地化提示；搜索按 name+description 过滤

### Phase 11 — 自动更新 + 提权
- **交付**：启动时 + 每 30 分钟静默检查更新、比版本、下载、替换、重启，双平台；`elevate.*` 提权流程重新实现
- **文件**：`lib/core/update/update_service.dart`、`lib/core/elevate/elevate_service.dart`（原计划的 `native/win/relaunch_helper.cpp` 实际没有落地，替换/重启由 Dart 侧完成）
- **验收**：版本比较保持**字符串比较**语义（非 semver），老安装行为不变，用测试钉死；Windows 下载 `taskpin-x64.exe`、写 detached batch、退出、以新版本回来（本地 HTTP 服务器提供 bump 过的 `version.txt` + 假 exe 验证）；macOS 替换 `.app` 内文件后重启，bundle 不可写时退化为打开 release 页；geo-IP 判 CN 时走代理；更新前询问用户（保持现在的 `MB_YESNO` 行为）。提权：脚本声明需要管理员时，条上显示 `elevate.blocked` 文案，点击弹 `elevate.restart_confirm` 确认框，确认后以管理员重启自身

> **更新语义（待产品确认，未定）**：上面"保持字符串比较"的理由只对**C 版存量用户**成立——服务这些用户的是旧 C 更新器，不是新客户端。新客户端自己再做 `strcmp` 会把 `1.10.0 < 1.6.8` 这个 bug 一起带进未来。
>
> 建议（**尚未拍板**）：
> 1. Flutter 版以 **2.0.0** 发布——对旧客户端的 `strcmp` 来说 `"2.0.0" > "1.6.8"`，存量用户仍能收到更新；同时任何 `1.x` 后续版本（如 `1.10.0`）也不会被 `2.0.0` 客户端按字符串比较误判。
> 2. 新客户端内部改用**真正的版本号比较**（逐段数字），`version_compare.dart` 的注释与测试随之改写。
>
> 这两条互相依赖，需产品确认后再动 `lib/core/update/version_compare.dart` 与 `version.txt`；确认前维持现状。

### Phase 12 — 打包、发布、迁移文档
- **交付**：与现发布形态一致的产物 + 迁移指南
- **文件**：`.github/workflows/release.yml`、`docs/MIGRATION.md`、`docs/FLUTTER_ARCH.md`、`README.md` / `README_CN.md`
- **状态：部分**。`release.yml` 已改成 Flutter 产物（Windows zip 含 exe + `flutter_windows.dll` + `data/`，`taskpin-x64.exe` 仍是 exe 的副本）；`docs/MIGRATION.md`、`docs/FLUTTER_ARCH.md` 尚不存在。
- **验收**：`v$(cat version.txt)` tag 产出 `TaskPin-macos.zip`、`TaskPin-windows.zip`、`taskpin-x64.exe`（**更新器资产名不得变**，老安装依赖它）；Windows zip 含 `examples/`、`lang/`、`scripts/` 和完整 Flutter 运行时（不再是"单个 exe"）；macOS zip 含 `TaskPin.app` + `install.command`；现有 v1.6.8 安装带着 `config.json` 和 `scripts/` 升级到 Flutter 版后所有 item 完好；README 的体积宣传口径更新为**实测数字**（预期 15–20MB，参照 BaoCode 的 18.9MB），删掉"450KB / 零运行时依赖"这类已不成立的表述

### Phase 13 — 删除旧实现
- **前置步骤（必须先做，否则删 `lib/` 会直接断构建）**：
  1. 把 `lib/lua/` 移到 `native/lua/`（`native/engine/CMakeLists.txt` 当前硬编码 `TP_LUA_DIR = ${TP_REPO_ROOT}/lib/lua`，改路径即可）。
  2. 把 `lib/stb_image.h` 移到 `native/third_party/stb/`（`native/win/bar_image.cpp:21` 的 `#include "lib/stb_image.h"` 与 `native/win/CMakeLists.txt` 的 `TASKPIN_ROOT` include 一起改）。
  3. 清掉 `lib/` 根目录的遗留 C 源（`appbar.c`、`config.c`、`scripting.c`、`stb_image.h` 等）与 `.o`（`lib/*.o` 13 个、`lib/lua/*.o` 32 个）、`src/*.o`。Dart 不会读它们，但它们在 `lib/` 下会让人以为还在用。
- **交付**：删除 `src/`、`lib/`（已迁走的部分）、`third_party/imgui`、`Package.swift`、`Makefile`、`WebView2Loader.dll`、根目录的 `.o`/`.exe`/日志残留；`docs/` 里留迁移对照表
- **验收**：仓库里不再有 C/ImGui/SwiftUI 的 UI 代码；`git grep` 确认没有对已删文件的引用；CI 两平台仍绿；release 流程不受影响

---

## 验证方式

1. **每个阶段的验收标准就是验证脚本** —— 派发 agy 时把该阶段的验收条目原样作为 prompt 的一部分，要求它自己跑通并附证据（命令 + 输出）。
2. **引擎一致性靠 golden**：Phase 2 的基线必须用**当前已构建的 `taskpin.exe`** 跑出来（本机有 `taskpin.exe` 1.9MB 可直接用），存进 `test/engine/golden/`，之后所有引擎改动都跑这个回归。
3. **条的行为靠实机**：Phase 7/8 必须在真机上验证 —— 起应用、看任务栏/菜单栏、改 DPI、重启 explorer、多显示器。这些无法靠单元测试覆盖。
4. **UI 靠 golden + `/gallery`**：组件级 golden 在 CI 跑；整体观感在 `/gallery` 路由目视检查。
5. **端到端**：装旧版 v1.6.8（带真实 config 和 scripts）→ 用新版覆盖 → 确认所有 item 完好、条正常显示、市场能装插件、更新检查正常。

## 风险

**高**

1. **条不可能是 Flutter，而条就是整个产品。** 全部押在原生 D2D/CoreText 渲染器做得好不好上。如果预期是"字面意义上一切都是 Flutter widget"，那这个需求在任务栏/菜单栏上不可满足 —— 这一点需要明确签字确认（已通过决策确认：混合方案）。
2. **产物体积回归（约 7 倍，实测口径）。** 现状：`taskpin.exe` 1.83MB，windows zip 总计 2.8MB（exe + examples + lang + scripts）。Flutter 桌面 release 应用约 15–20MB。参照系：[BaoCode](https://github.com/baocode-dev/baocode)（同为 Flutter 桌面，含完整编辑器和终端）Windows 安装包 18.9MB、macOS dmg 15.6–17.2MB。所以预期落到 **15–20MB**，README 的"单文件 450KB / 零运行时依赖"叙事要改（顺带一提，README 现在的 450KB 与实测 1.83MB 本就不符，这个口径本来就需要修）。这是定位变化，不只是技术变化（已接受）。
3. **explorer 重启 / 多显示器现在是坏的**，必须修复而非移植。要留预算。
4. **跨进程子窗口重父化是未文档化行为。** 现在能用，但 Windows 更新以前破坏过这类技巧。用 explorer 监听 + 优雅降级（退化为贴在任务栏上方的置顶小窗口）兜底。
5. **Lua 引擎 ABI 统一是真正的移植而非拷贝**：`lib/scripting.c` 是宽字符、`taskpin_lua.c` 是 UTF-8，且后者缺 `align`/`newline`。低估这块是最可能的进度滑点。

**中**

6. **Lua 内阻塞 HTTP + 单引擎 isolate** 意味着一慢全慢。handle-based ABI 允许 N 个引擎，但默认值要定。建议 N=2（realtime 类 item 一个，其余一个）并实测。
7. **Direct2D vs 保留 GDI**：D2D 换来彩色 emoji、更好的字体回退和真 alpha，代价是更大的原生模块和 device-lost 处理路径。推荐做，但是工作量。
8. **`field_expr` 是 Lua 代码 *或* `$.path` 模板**（`lib/expression.c`）自动识别。启发式必须逐字保留，否则现有 URL 模式 item 全坏。
9. **macOS 配置 schema 不兼容**（UUID `id`、camelCase）—— Phase 1 必须定死统一到 Windows schema 并迁移。
10. **代码签名**：现在是 `codesign -s -`（ad-hoc）+ `install.command` 里的 `xattr -cr`。Flutter 应用在 macOS 上对未签名/未公证更敏感（Gatekeeper + Flutter framework 自带的 dylib）。可能需要真签名，或至少写清楚绕过方式。

## 待定（不阻塞开工，可在对应阶段前定）

- **引擎默认实例数**：N=1 还是 N=2（realtime 分流）—— Phase 3 后按实测决定
- **体积预算**：装完多大可接受 —— 决定能否内置 Inter/JetBrains Mono，以及要不要做 tree-shaking 优化
- **`realtime` 字段**：`lib/config.h:49` 存在但从未读取，计划中删除（若其实有未完成意图，需要指出）
