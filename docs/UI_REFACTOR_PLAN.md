# TaskPin UI 重构计划（项目页 + 插件市场 + 自绘标题栏）

> 2026-10-19 · 依据用户提供的《TaskPin UI 重构规范》
>
> 本文是实施计划，不是设计规范。视觉规范见 `docs/VISUAL_SPEC.md`；两者冲突时以本文为准，并在同一次提交里同步 VISUAL_SPEC。
>
> 约束（已与用户确认）：**不打包字体、不新增依赖、沿用 Riverpod、设计值放在 `packages/taskpin_design`**。

---

## 0. 结论摘要

| 项 | 决定 |
|---|---|
| 状态管理 | Riverpod，沿用 `configProvider`（`ConfigNotifier`）与 `barControllerProvider`（快照在 `BarState.bars`，按 item index 索引） |
| 设计值 | 改在 `packages/taskpin_design`，**不**新建 `lib/ui/theme/` |
| 页面目录 | 新建 `lib/ui/widgets/`、`lib/ui/pages/{projects,market}/`，替换现有 `lib/features/signals`、`lib/features/market` |
| 字体 | 全部系统字体，`pubspec.yaml` 不加 fonts |
| 图标 | 沿用 `TpIcons`（Windows：Segoe Fluent Icons，其他平台 Material） |
| 标题栏 | 无依赖：Windows 原生 `WM_NCCALCSIZE` + `WM_NCHITTEST` + 一条 MethodChannel；macOS 原生 `titlebarAppearsTransparent` + `titleVisibility = .hidden` + `fullSizeContentView`（不引入 `window_manager`） |
| 拖拽排序 | 只重排项目顺序（已有 `moveItem`），**不加 `bar_order` 字段**；原生需按新顺序重排，见 §7 |
| 市场预览文字 | `MarketScript` 加可选 `previewText`；manifest 无此字段时整条隐藏 |

---

## 1. 现状核对

| 规范要求 | 现状 | 处理 |
|---|---|---|
| Riverpod | 已是 Riverpod（`flutter_riverpod ^2.6.1`） | 沿用 |
| `TaskPinColors extends ThemeExtension` | `TaskPinTheme` 已是 ThemeExtension，含颜色/间距/圆角/排版 | 改色值，不新建 |
| 禁裸色值 | 已有 `packages/taskpin_design/test/no_raw_colors_test.dart`（只扫描该包的 `lib/`）、`test/no_token_alpha_override_test.dart` | 保留并新增一条只扫描 `lib/ui/` 的测试，见 §3.1 |
| 系统字体 | `typography.dart` 已用 Segoe UI Variable 优先、Microsoft YaHei UI 回退 | 保持 Segoe UI 优先、YaHei 只作 CJK 回退（按字形回退，避免拉丁字母/数字用 YaHei） |
| 等宽字体 | 现用 Cascadia Mono → Consolas | 保持系统字体（不打包 JetBrains Mono） |
| 自绘标题栏 | 无，使用系统标题栏 | 新增（见 §5） |
| `lastUpdated` | `BarSnapshot.updatedAt` 已有 | 直接用 |
| `missingScript` | `lib/core/scripts/script_files.dart` 已有统一判断 | 直接用 |
| `barOrder` | 无；左右位置由 `bar_x` 决定，负值自动排到托盘左侧 | 不加字段，见 §7 |
| `previewText` | manifest 与 `MarketScript` 均无 | 加可选字段，见 §8 |
| 最小窗口 | 880×600（`win32_window.cpp`） | 改 800×560 |
| 平台文案 | 无 | 新增 `PlatformLabels` |

---

## 2. 文件改动清单

### 2.1 新增

```
lib/ui/widgets/title_bar.dart          Windows 自绘标题栏 + macOS 红绿灯留白
lib/ui/widgets/platform_labels.dart    任务栏/菜单栏、托盘左侧/状态栏左侧、快捷键
lib/ui/widgets/tp_switch.dart          40×22 自绘开关，热区 52×44
lib/ui/widgets/search_field.dart       带快捷键提示与聚焦
lib/ui/widgets/segmented_filter.dart   全部 / 已安装 / 未安装
lib/ui/widgets/bar_preview.dart        任务栏 / 菜单栏模拟条 + 横向拖拽排序
lib/ui/widgets/error_banner.dart       异常提示 + 批量重新定位
lib/ui/widgets/status_dot.dart         8px 圆点 / 空心圆点
lib/ui/widgets/pill.dart               胶囊标签
lib/ui/pages/projects/projects_page.dart
lib/ui/pages/projects/running_card.dart
lib/ui/pages/projects/stopped_card.dart
lib/ui/pages/projects/missing_script_list.dart
lib/ui/pages/market/market_page.dart
lib/ui/pages/market/plugin_card.dart
lib/core/window/main_window_channel.dart  Dart 侧窗口按钮/状态 channel，channel 名 `taskpin/main_window`（不要叫 window_channel.dart，会与对话框的同名文件混淆）
native/win/taskpin_window_plugin.cpp      窗口按钮、最大化状态、拖动区域
```

### 2.2 修改

| 文件 | 改动 |
|---|---|
| `packages/taskpin_design/lib/src/tokens/primitives.dart` | 色板换成规范值（§3） |
| `.../tokens/semantic.dart` | 新增 `segmentBg`、`successBg/Fg`、`dangerBg/Fg`、`barBg`、`barOutput`、`chip*`、`barMuted`、5 组图标底色 |
| `.../tokens/spacing.dart` | 页面内边距 32/28/32/40、区块 20、网格 10–12、热区 44 |
| `.../tokens/radius.dart` | 卡片 12、控件 8、小按钮 7、胶囊 10 |
| `.../tokens/typography.dart` | 新增 15/500、13/400、12 mono；正文字族改为系统字体优先 |
| `.../components/shell.dart` | 导航宽 216、页头 28/700 + 13 摘要 + Wrap 操作区 |
| `.../components/forms.dart` | 输入框/分段控件按新尺寸与色值 |
| `.../components/feedback.dart` | 按钮圆角 8、主色新值 |
| `lib/app/shell/app_shell.dart` | 接入 TitleBar、216 导航、新页面 |
| `lib/app/shell/routes.dart` | `/projects`、`/market` 指向新页面；`/signals` 重定向到 `/projects`；`/signals/:id` 重定向到 `/projects/:id`（保留 id，不要落到列表页） |
| `lib/main.dart` | 窗口初始化（无依赖方式，见 §5） |
| `lib/core/market/market_models.dart`、`manifest.dart` | 可选 `previewText` |
| `lib/l10n/app_zh.arb`、`app_en.arb` | 新页面全部文案（含 PlatformLabels 的键） |
| `windows/runner/win32_window.cpp` | `WM_NCCALCSIZE`、`WM_NCHITTEST`、`WM_GETMINMAXINFO`、最小尺寸 800×560、最大化状态通知 |
| `windows/runner/flutter_window.cpp` | 注册 `taskpin/main_window` channel；对 Flutter 子窗口做消息拦截（见 §5.1） |
| `windows/CMakeLists.txt` | 编入 `native/win/taskpin_window_plugin.cpp`（同时把 `native/win/dialog_window_styles.cpp` 加入 `BAR_SOURCES`，否则对话框的 `taskpin/window` 在 Windows 上无人应答） |
| `macos/Runner/MainFlutterWindow.swift` | `titlebarAppearsTransparent`、隐藏标题、左侧 72px 由 Flutter 留白 |
| `docs/VISUAL_SPEC.md` | 色板、尺寸、页面结构同步 |

### 2.3 删除（迁移完成后）

`lib/features/signals/signals_list_page.dart`、`lib/features/market/market_page.dart`，以及仅被它们使用的 `lib/features/signals/widgets/taskbar_preview.dart`。

注意：`item_labels.dart` 仍被保留的 `signals_editor_page.dart` 引用，**不能删**；`avatar.dart` 被 `market_page.dart` 引用（`market_page.dart` 自己也会被替换，但新的市场页仍要显示首字母头像），因此也不能删——要么保留，要么先移到 `lib/ui/widgets/avatar.dart` 再改引用。`signals_editor_page.dart`、`settings_page.dart` 保留并适配新 token。

---

## 3. 设计值（改 `packages/taskpin_design`）

### 3.1 颜色

| Token | Light | Dark（随系统发布，必须完整） |
|---|---|---|
| `bg` | `#F6F6F3` | `#1C1E22` |
| `surface` | `#FFFFFF` | `#24262B` |
| `border` | `#E2E2DC` | `#33373D` |
| `borderStrong` | `#DCDCD5` | `#3F444C` |
| `segmentBg` | `#EAEAE4` | `#2A2D33` |
| `text` | `#16181D` | `#F2F3F5` |
| `textSecondary` | `#5E6470` | `#B7BCC5` |
| `textMuted` | `#8A8F99` | `#8A8F99` |
| `primary` | `#2457D6` | `#4C8DFF` |
| `success` / `successBg` / `successFg` | `#1E7F4F` / `#E3F2EA` / `#155C39` | `#5BD08A` / `#1B3327` / `#A7E7C4` |
| `danger` / `dangerBg` / `dangerFg` | `#B42318` / `#FDECEA` / `#7A1A12` | `#FF8A80` / `#3A1F1D` / `#FFC9C3` |
| `barBg` | `#1F2228` | `#1F2228` |
| `chipBg` / `chipBorder` / `chipText` / `barMuted` | `#2A2E36` / `#3A3F4A` / `#F2F3F5` / `#9AA0AA` | 同左 |
| `barOutput` | `#D7F5E3` | `#B9EBCF` |
| 图标底色 1–5（底/字） | `#E6EDFC`/`#1A3F9E`、`#E3F2EA`/`#155C39`、`#FBEBDD`/`#8A3F0C`、`#EFEAF8`/`#4B2E8A`、`#EFEFEA`/`#3A3F4A` | `#1B2A45`/`#9DBBFF`、`#17342A`/`#8FDDB2`、`#3A2A1A`/`#F0B27A`、`#2A2340`/`#C3B0F0`、`#2A2D33`/`#B7BCC5` |

规范未给 `accent/onFill`：主按钮文字用 `accent/onFill` token（两主题均为 `#FFFFFF`），不写字面量。

**深色不是"预留"**：`appThemeModeProvider` 默认 `ThemeMode.system`（`lib/app/shell/app_shell.dart`），深色值会真实发布，因此 §3.1 的 Dark 列必须补全（上表已补五组图标底色与 `barOutput`），不能留"深色底对应降明度"这类描述。

**裸色值约束**：现有 `packages/taskpin_design/test/no_raw_colors_test.dart` 只扫描该包自己的 `lib/`，不会覆盖应用代码。§3 在 `lib/ui/` 里引入的 `#C42B1C`、`#D7F5E3`、`#FFFFFF` 一律做成 token（`danger` / `barOutput` / `accent/onFill`），并新增 `test/ui/no_raw_colors_ui_test.dart`，**只扫描 `lib/ui/`**。不要把范围扩到整个 `lib/`：`lib/features/signals/widgets/color_picker_popup.dart:260` 已有 `Color(0x00000000)`/`Color(0xFF000000)`（颜色选择器的渐变端点），全量扫描会误报。

### 3.2 字体与尺寸

- 正文：Windows `Segoe UI` → `Microsoft YaHei UI`（**拉丁字母和数字用 Segoe UI，YaHei 只作 CJK 回退**；Flutter 按字形逐个回退，所以不能把 YaHei 放第一位，否则英文/数字也变成 YaHei 字形）；macOS `SF Pro` → `PingFang SC`。字号 12/13/15/28。
- 等宽：Windows `Cascadia Mono` → `Consolas`；macOS `SF Mono` → `Menlo`。12/13。封装 `TextStyle.mono` 扩展。
- 圆角：卡片 12、按钮/输入框 8、小按钮 7、胶囊 10。
- 页面内边距 `fromLTRB(32, 28, 32, 40)`，区块间距 20，网格间距 10–12，交互热区 ≥ 44。

---

## 4. 平台文案 `PlatformLabels`

| 键 | Windows | macOS |
|---|---|---|
| `barName` | 任务栏 | 菜单栏 |
| `position` | 托盘左侧 | 状态栏左侧 |
| `searchShortcut` | Ctrl K | ⌘K |

实现为 `PlatformLabels.of(context)`（按 `defaultTargetPlatform`），文案走 ARB，不硬编码。

---

## 5. 自绘标题栏（无依赖）

### 5.1 Windows

**关键约束**：Flutter 的内容不是主窗口本身，而是 `SetChildContent` 创建的**子窗口**（`windows/runner/flutter_window.cpp:52`，`Win32Window::SetChildContent` 里 `SetParent`）。鼠标消息先命中这个子窗口，主窗口的 `WndProc` 返回 `HTCAPTION` **对 Flutter 表面上的拖动无效**。

1. **子窗口消息拦截**（`FlutterWindow::MessageHandler`，或对 `flutter_controller_->view()->GetNativeWindow()` 子类化）：
   - `WM_NCHITTEST`：把客户区坐标换算到主窗口后，顶部 36 逻辑像素（按 DPI 换算）内返回 `HTTRANSPARENT`，让命中测试落回父窗口；**右侧三个按钮区域除外**（返回 `HTCLIENT`，点击交给 Flutter）。其余区域 `HTCLIENT`。
   - 为什么必须拦：`Win32Window::SetChildContent` 用 `SetParent` 把 Flutter view 变成主窗口的子窗口（`flutter_window.cpp:52`），鼠标消息先到子窗口；只改主窗口的 `WndProc` 时，Flutter 表面上的拖动、双击、Snap 全部不生效。
2. `Win32Window::MessageHandler` 增加：
   - `WM_NCCALCSIZE`：**不要无条件返回 0**。标准做法是先调用 `DefWindowProc`，再只把顶边按 frame 高度内缩（`wParam == TRUE` 时改 `rgrc[0].top += frameHeight`），左右下边框保留。无条件返回 0 会让最大化时客户区每边溢出约 8px（右上角按钮被裁掉），并且丢掉可拖拽的调整边框。
   - `WM_NCHITTEST`：顶部 36 逻辑像素内返回 `HTCAPTION`；最大化时同区域；排除右侧三个按钮区域。
   - **Snap Layouts（决策：实现）**：Win11 悬停最大化按钮弹出贴边布局，要求该按钮矩形内返回 `HTMAXBUTTON`。子窗口在这些区域不返回 `HTTRANSPARENT`，改由父窗口返回 `HTMAXBUTTON`；最大化按钮的点击因此由原生处理（`WM_NCLBUTTONDOWN` → `toggleMaximize`），Flutter 只负责画图标，不接收该区域的点击。接受这个取舍，换取 Snap Layouts。
   - `WM_GETMINMAXINFO`：最小尺寸改 800×560 客户区。
   - `WM_SIZE` 后通过 channel 发送 `maximized` 状态。
3. `native/win/taskpin_window_plugin.cpp`：注册 **`taskpin/main_window`**（`taskpin/window` 已被对话框窗口占用：`lib/features/dialogs/window_channel.dart` + `native/win/dialog_window_styles.cpp`），方法 `minimize`、`toggleMaximize`、`close`、`isMaximized`；事件 `maximizedChanged`。
4. Flutter `TitleBar`：
   - 高 36，背景 `bg`，底部 1px `border`。
   - 左：应用图标 16 + “TaskPin”（13/500）。
   - 右：最小化、最大化/还原、关闭，各 46×36；悬停背景 `segmentBg`，关闭悬停 `theme.danger`（token，不写 `#C42B1C`）+ `accent/onFill` 图标。
   - 双击标题栏切换最大化（Flutter 侧识别 `onDoubleTap` 后调用 channel）。
   - 拖动由原生 `HTCAPTION` 承担（经上面的子窗口 `HTTRANSPARENT` 落回父窗口），Flutter 不再处理。

### 5.2 macOS

- `MainFlutterWindow`：`titleVisibility = .hidden`、`titlebarAppearsTransparent = true`、`styleMask.insert(.fullSizeContentView)`。
- Flutter `TitleBar` 高 36：左侧留 72 红绿灯位，中间显示 “TaskPin”（13/500，`textSecondary`），右侧不放按钮。
- 窗口按钮 channel（`taskpin/main_window`）在 macOS 返回 `unimplemented`，Flutter 侧据此不渲染右侧按钮。这样 §0 的"不新增依赖"成立，不需要 `window_manager` 的 `TitleBarStyle`。

### 5.3 风险

- 去掉系统标题栏后，Windows 10 的窗口圆角/阴影需 `DWM` 处理；不做则直角 + 无阴影，可接受。
- 全屏、贴边吸附（Aero Snap）依赖 `WM_NCCALCSIZE` 返回值正确；实现后需手工验证拖动到屏幕边缘。
- 拖动/双击/Snap 都依赖 §5.1 的子窗口 `HTTRANSPARENT` 拦截。漏掉这一步的典型症状是：按钮能点、标题栏拖不动，且 `WM_NCHITTEST` 看起来"写了却没生效"。
- 若 channel 未就绪（例如测试环境），`TitleBar` 隐藏右侧按钮，不崩溃。

---

## 6. 项目页 `ProjectsPage`

结构按规范逐条实现，要点：

| 区块 | 实现 |
|---|---|
| 页头摘要 | 圆点 8 + 「N 运行中」「N 异常」，空心圆 + 「N 已停止」；右侧 `SearchField`（≥220，后缀 Ctrl K/⌘K，注册 `SingleActivator`）+ 主按钮 |
| BarPreview | 标题 `{barName}预览 · N 个插件`；右侧「拖动调整顺序」+ 位置下拉（文案 `位置：{position}`，下拉只显示当前平台可选项；**不写配置新字段**——位置仍由既有 `bar_x` 决定，见 §7） |
| 模拟条 | Windows 52 高圆角 10；左侧 4 个 30px 占位块 → Spacer → 插件块 → 1px 分隔 → 托盘（上箭头、wifi、两行时间日期）。macOS 32 高：苹果占位 + 应用菜单占位 → Spacer → 插件块 → 状态图标 → 时间 |
| 插件块 | 高 36（macOS 24），`chipBg` + `chipBorder`，圆角 6，等宽 12，左 6 点拖拽手柄 |
| 排序 | `ReorderableListView`（横向），提交后调用 `configProvider.moveItem(from, to)`。**目前没有任何测试覆盖 `moveItem`**（`test/` 下不存在），需新增；且当前重排不会改变任务栏上的实际顺序，见 §7 |
| ErrorBanner | 存在 missingScript 时显示；`dangerBg`/`dangerFg`；右侧描边按钮「批量重新定位」：目录选择 → 按文件名匹配 → 逐个更新 `luaPath` |
| 分组标题 | 12 `textSecondary`，letterSpacing 0.5 |
| 运行中 | 自适应网格最小列宽 360；卡片见规范；输出框 `barBg`、等宽 13、`barOutput` token（深色 `#B9EBCF` / 浅色 `#D7F5E3`），单行横向滚动 |
| 需要处理 | 单个 surface 卡片内多行，1px 分隔；无开关 |
| 已停止 | 自适应网格最小列宽 280；36px 首字母块（底色按索引循环 5 组之一） |
| TPSwitch | 40×22、热区 52×44、150ms、`Semantics(toggled:)`；切换后卡片换组，外层 `AnimatedSwitcher` |

相对时间：`Timer.periodic(1s)` 只重建显示相对时间的 `Text`（`ValueListenableBuilder`），不重建整卡。

---

## 7. 拖拽排序与 `bar_order`

规范要求新增 `bar_order` 持久化。现状：任务栏左右位置由 `PinItem.barX` 决定（`lib/core/bar/bar_controller.dart:231`：`barX >= 0 ? barX : -1 - offset`），自动位置按 `config.items` 的顺序累加宽度。

**决定**：不新增字段。拖拽排序重排 `config.items` 中已固定项目的相对顺序；`bar_x >= 0` 的手动定位不受影响。理由：

1. `bar_order` 与 `bar_x` 语义重叠，两者同时存在时以谁为准没有答案。
2. `moveItem` 已保存并触发重新布局，零新增字段、零迁移。
3. 旧版本读取新配置时不会遇到未知字段。

**但现有实现不会真的换位**（这是缺陷，不是已实现行为）：

- Dart 对自动定位的条发 `x = -1 - offset`（`bar_controller.dart:231`），而原生 `BarWindow::SetGeometry` 只在 `x >= 0` 时移动（`native/win/bar_window.cpp:277`），负值被忽略。
- 原生自动 X 只在**首次嵌入**时按创建顺序计算一次（`native/win/bar_channel.cpp` 的 `AutoX` / `order_`），`setSpans` 对已存在的条不再重排。
- 所以重排后必须显式让原生按新顺序重算：要么 Dart 对自动定位的条发**绝对 x**（自己按 `items` 顺序累加宽度），要么给 `taskpin/bar` 增加 `reorder(barIds)` 并让原生按新顺序重算 `AutoX` 后 `SetWindowPos`。推荐后者，宽度/钳制规则留在原生一处。

**Windows 顺序方向**：`items[0]` 是**最右边**（最靠近托盘）的条——`AutoX` 从托盘左缘向左累加宽度。因此：

- 预览条必须**反向渲染**（预览从左到右是 `items[last] … items[0]`），否则预览和任务栏左右颠倒。
- `ReorderableListView` 的 `oldIndex/newIndex` 是**预览顺序**，而 `moveItem` 的索引是**完整 item 列表**；预览只含 pinned 项，必须做索引映射（预览第 k 项 → `pinnedIndices[k]`），再调用 `moveItem(pinnedIndices[old], pinnedIndices[new])`。当前 `signals_list_page.dart` 已做这个映射，但没做反向渲染。

**取舍**：如果产品坚持“拖拽只改预览顺序、不改列表顺序”，则需要新增 `bar_order` 并定义 `bar_x >= 0` 时的优先级。此项待确认，默认按上表执行。

---

## 8. 市场预览文字

- `MarketScript` 新增 `previewText`（可选，空字符串表示无）。
- `manifest.dart` 解析 `preview` 或 `preview_text`（取存在者）。
- 卡片预览条：`previewText` 为空时整条隐藏（不占位）。
- `bestK/taskpin-plugins` 的 manifest 需另行补字段；本仓库不修改插件仓库。

---

## 9. 状态管理接入

| 数据 | 来源 | 用法 |
|---|---|---|
| 项目列表、固定、删除、重排 | `configProvider` | `watch` 读取，调用 `togglePinned` / `removeItemAt` / `moveItem` / `save` |
| 实时输出、更新时间、错误 | `barControllerProvider`（`BarState.bars`） | `watch` 单条快照（按 item index 索引）；输出为空时显示占位。**没有 `barSnapshotsProvider`** |
| 脚本缺失 | `lib/core/scripts/script_files.dart` | 复用 `scriptInstallState` |
| 市场列表 | `marketCatalogProvider` | 沿用；过滤在页面内做 |
| 安装 | `marketInstallProvider` | 沿用，安装中/失败状态已有 |
| 主题 | `appThemeModeProvider` | 沿用；默认跟随系统 |

不新增 provider，除非 §5 的窗口状态需要：`windowStateProvider`（是否最大化），仅用于标题栏图标切换。

**快照按 index 索引的副作用**：`barControllerProvider` 内部的 `_lastResult`、`_inFlight`、`_lastPushed`、`_geometry` 都以 item index 为 key（`bar_controller.dart`）。`moveItem` 之后，旧 index 上的输出会短暂显示在**另一个 item** 的卡片上，直到下一次刷新覆盖。UI 侧不能把「index → 输出」当作稳定身份：重排后应清空/重建这些映射，或改用稳定 id（当前配置没有 id，最小改动是在 `_reconcile` 检测到 items 顺序变化时清空 `_lastPushed` 并立即重跑）。

---

## 10. 分阶段实施

| 阶段 | 内容 | 验证 |
|---|---|---|
| **A. Token** | 改 `packages/taskpin_design` 的颜色/尺寸/字阶；补 `TextStyle.mono`；更新受影响的既有组件与测试 | `flutter test`（设计包）全过；`flutter analyze` 0 error |
| **B. 基础组件** | `TpSwitch`、`SearchField`、`SegmentedFilter`、`StatusDot`、`Pill`、`PlatformLabels`，各带 widget 测试 | 组件测试全过；150% 文字缩放不溢出 |
| **C. 标题栏** | 原生 `WM_NCCALCSIZE`/`WM_NCHITTEST`、channel、`TitleBar`；macOS 隐藏标题 | 实机：拖动、双击最大化、贴边吸附、三按钮、macOS 红绿灯不重叠 |
| **D. 项目页** | `ProjectsPage` + 卡片 + `BarPreview` + `ErrorBanner`；删除旧列表页 | widget 测试：分组、排序（含反向渲染与 index 映射）、开关换组、批量重定位；实机确认重排后任务栏顺序真的变化 |
| **E. 市场页** | `MarketPage` + `PluginCard` + `previewText`；删除旧市场页 | widget 测试：筛选、搜索防抖、安装状态、等高卡片 |
| **F. 收尾** | 路由重定向、ARB 清理、删除死代码、同步 `VISUAL_SPEC.md` | 全量测试；`flutter build windows`；两平台冒烟 |

每阶段独立可运行；A 完成前不开始 B（组件依赖新 token）。

---

## 11. 测试清单

| 测试 | 覆盖 |
|---|---|
| `test/ui/tp_switch_test.dart` | 开/关外观、150ms 动画、Semantics、热区 ≥44 |
| `test/ui/search_field_test.dart` | 快捷键聚焦、后缀文案按平台 |
| `test/ui/segmented_filter_test.dart` | 选中态、数量、切换回调 |
| `test/ui/bar_preview_test.dart` | 两平台尺寸、拖拽回调、溢出滚动、无插件时占位 |
| `test/ui/projects_page_test.dart` | 三组划分、切换后换组、缺失脚本进“需要处理”、批量重定位调用 |
| `test/ui/market_page_test.dart` | 筛选、防抖搜索、安装中/已安装/失败、`previewText` 为空隐藏 |
| `test/ui/title_bar_test.dart` | 平台分支、最大化图标、channel 未就绪时不崩溃 |
| 新增 | `test/ui/no_raw_colors_ui_test.dart`：只扫描 `lib/ui/`，禁止 `Color(0x...)`。**不要**把范围扩到整个 `lib/`——`lib/features/signals/widgets/color_picker_popup.dart:260` 已有 `Color(0x00000000)`/`Color(0xFF000000)`，会误报 |
| 既有 | `packages/taskpin_design/test/no_raw_colors_test.dart`（只覆盖设计包 `lib/`）、`no_token_alpha_override_test`、配置往返测试保持通过 |

---

## 12. 风险与未决

1. **去系统标题栏的兼容性**：Windows 10 无 Mica、贴边吸附、高 DPI 下 `WM_NCHITTEST` 的 36px 换算需实机验证；`WM_NCCALCSIZE` 必须按 §5.1 保留左右下边框，否则最大化溢出且不能拖边缩放。回退方案：保留系统标题栏，仅加一层 Flutter 工具栏。
2. **等宽字体**：不打包后 Windows 10 可能没有 Cascadia Mono（需 Win10 1809+ / 终端安装），回退 Consolas；macOS 回退 Menlo。字形宽度与设计稿有差异。
3. **`bar_order` / 实际重排**：见 §7。默认不新增字段，但原生当前忽略自动定位条的 x 且只在首次嵌入时算一次 `AutoX`，必须补 `reorder` 或改发绝对 x，否则拖拽只改配置不改任务栏。需产品确认。
4. **托盘示意图**：Windows 任务栏托盘图标随系统版本与用户设置变化，模拟条只画上箭头、wifi 和时钟，不做像素级还原。
5. **macOS 未在本机验证**：`MainFlutterWindow` 改动需在 mac 上跑一次；CI 只做构建。
6. **设置页与详情页**：本次不改结构，只适配新 token；它们与新页面会短暂并存于不同视觉细节，阶段 F 统一。
