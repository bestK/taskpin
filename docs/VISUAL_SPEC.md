# TaskPin 视觉规范

版本 2.0 · 2026-10-16 · 取代 1.0（Aurora）

方向：**Windows 11 原生**。管理窗口照 Windows 设置的样子做，任务栏条照任务栏自身的样子做。macOS 用同一套结构，换成系统字体和系统色。

原则只有三条：

1. 像系统的一部分。用系统字体、系统色、系统控件尺寸，不加品牌装饰。
2. 少即是多。一屏一个主操作；能用一行文字说清的，不用卡片、徽标、图标堆。
3. 数字不动。会变的数字一律等宽数字（tabular figures）。

依据见文末"参考"。数值以 WinUI 3 默认主题资源为准，本文与代码冲突时以代码为准并同步修改本文。

---

## 1. 颜色

### 1.1 主题

跟随系统深浅色，设置里可改为"浅色 / 深色 / 使用系统设置"。

默认以**浅色**为准（Windows 浅色任务栏是出厂默认），深色是对应镜像。色值取自设计稿，覆盖 §1.2 的 WinUI 默认值。

### 1.2 色板（WinUI 默认值）

| Token | 深色 | 浅色 | 用途 |
|---|---|---|---|
| `bg/window` | `#1C1E22` | `#F6F6F3` | 窗口底色（Mica 不可用时的实色） |
| `bg/card` | `#24262B` | `#FFFFFF` | 设置卡片、列表分组底色 |
| `bg/cardSecondary` | `#2A2D33` | `#F4F4F1` | 卡片内的次级区域 |
| `bg/flyout` | `#2C2E34` | `#FFFFFF` | 菜单、下拉、tooltip、对话框 |
| `stroke/card` | `#33FFFFFF` | `#E6E4DE` | 卡片描边 1px |
| `stroke/divider` | `#26FFFFFF` | `#EAE8E2` | 分隔线 1px |
| `control/fill` | `#0FFFFFFF` | `#B3FFFFFF` | 按钮、输入框静止底色 |
| `control/fillHover` | `#15FFFFFF` | `#80F9F9F9` | 悬停 |
| `control/fillPressed` | `#08FFFFFF` | `#4DF9F9F9` | 按下 |
| `control/fillInputActive` | `#B31E1E1E` | `#FFFFFF` | 输入框获得焦点时 |
| `control/stroke` | `#12FFFFFF` | `#0F000000` | 按钮、输入框描边 |
| `control/strokeBottom` | `#18FFFFFF` | `#29000000` | 按钮底边（制造轻微立体感） |
| `control/strokeStrong` | `#8BFFFFFF` | `#72000000` | 输入框底边、复选框、开关关闭态描边 |
| `subtle/hover` | `#0FFFFFFF` | `#09000000` | 无边框元素（列表行、导航项、图标按钮）悬停 |
| `subtle/pressed` | `#0AFFFFFF` | `#06000000` | 无边框元素按下 |
| `text/primary` | `#FFFFFF` | `#E4000000` | 正文、标题 |
| `text/secondary` | `#C5FFFFFF` | `#9E000000` | 说明文字 |
| `text/tertiary` | `#87FFFFFF` | `#72000000` | 占位符、次要元信息 |
| `text/disabled` | `#5DFFFFFF` | `#5C000000` | 禁用 |
| `smoke` | `#4D000000` | `#4D000000` | 模态对话框遮罩 |
| `nav/active` | `#16181D` | `#16181D` | 导航选中项实心底 |
| `bg/taskbar` | `#16181D` | `#16181D` | 管理窗口里的任务栏模拟条 |
| `stroke/strong` | `#4A4F57` | `#C9C6BE` | 卡片悬停描边 |

### 1.3 强调色

先固定用 Windows 默认蓝，后续版本再读取系统强调色。

| Token | 深色 | 浅色 | 用途 |
|---|---|---|---|
| `accent/fill` | `#4C8DFF` | `#2457D6` | 主按钮、开关打开、选中指示条 |
| `accent/fillHover` | `#5C99FF` | `#1E4BB8` | 主按钮悬停（强调色 90% 不透明，同 WinUI） |
| `accent/onFill` | `#000000` | `#FFFFFF` | 强调色上的文字 |
| `accent/text` | `#7FB0FF` | `#2457D6` | 链接文字 |

注意：两套主题的主按钮都是**蓝底白字**。深色主题不要改用浅蓝底黑字。

### 1.4 状态色

只用于状态，不用于装饰。

| Token | 深色 | 浅色 | 含义 |
|---|---|---|---|
| `status/success` | `#5BD08A` | `#1E7F4F` | 正常运行、已安装 |
| `status/caution` | `#F5C542` | `#B07800` | 数据过期、需要管理员权限 |
| `status/critical` | `#FF8A80` | `#B42318` | 脚本出错、请求失败 |
| `status/neutral` | `#9AA0A8` | `#868A93` | 未固定、已暂停 |

### 1.5 规则

- 一屏最多一个 `accent/fill` 按钮。
- 不用渐变、不用发光、不用彩色阴影。
- 导航选中态：`nav/active` 实心底 + 白色文字，不用指示条。
- 状态只用"小圆点 + 文字"表达，不给整行或整卡上色。

---

## 2. 字体

### 2.1 字族

| 用途 | Windows | macOS |
|---|---|---|
| 界面 | `Segoe UI Variable` → `Segoe UI` → `Microsoft YaHei UI` | `SF Pro` → `PingFang SC` |
| 代码、路径、表达式 | `Cascadia Mono` → `Consolas` | `SF Mono` → `Menlo` |

全部使用系统自带字体，**不打包** Inter / JetBrains Mono。

### 2.2 字阶（Windows 11 type ramp）

| Token | 字号/行高 | 字重 | 用途 |
|---|---|---|---|
| `caption` | 12/16 | 400 | 卡片说明、时间、徽标 |
| `body` | 14/20 | 400 | 正文、控件文字、列表主文字 |
| `bodyStrong` | 14/20 | 600 | 分组标题、列表中需要强调的名称 |
| `bodyLarge` | 18/24 | 400 | 极少用 |
| `subtitle` | 20/28 | 600 | 对话框标题 |
| `title` | 28/36 | 600 | 页面标题 |
| `mono` | 13/20 | 400 | 代码、路径 |

规则：

- 只用 400 和 600 两种字重，不用 700，不用斜体。
- 最小字号：常规 12，半粗 14 以下不用。任何地方都不出现 9、10、11 号字。
- 句首大写（英文），不用全大写标题，不加字距。
- 会变化的数字加 `FontFeature.tabularFigures()`。

---

## 3. 尺寸、间距、圆角

### 3.1 间距（4 的倍数）

| 场景 | 值 |
|---|---|
| 相邻按钮之间 | 8 |
| 标签与下方控件之间 | 8 |
| 两个内容块之间 | 12 |
| 表面内边距（卡片、对话框） | 16 |
| 设置卡片之间 | 4 |
| 分组标题与上一组之间 | 30（上）/ 6（下） |
| 页面左右边距 | 窗口宽 < 1000 时 24，否则 36 |
| 页面顶部边距 | 24（与导航顶部对齐） |
| 页面内容最大宽度 | 1000 |

### 3.2 控件高度

| 控件 | 高度 |
|---|---|
| 按钮、输入框、下拉框 | 32 |
| 开关 | 40 × 20 |
| 列表行（单行） | 40 |
| 列表行（双行：名称 + 说明） | 60 |
| 设置卡片 | 最小 68 |
| 导航项 | 40（上下各留 2） |
| 标题栏 | 32 |

### 3.3 圆角

| 元素 | 圆角 |
|---|---|
| 按钮、输入框、下拉框、tooltip、列表行悬停底 | 4 |
| 卡片、菜单、对话框、窗口 | 8 |
| 开关、徽标 | 全圆 |
| 贴边或最大化的窗口 | 0 |

### 3.4 阴影

卡片**没有**阴影，只有 1px `stroke/card`。

| 层级 | 阴影 | 用于 |
|---|---|---|
| 菜单、下拉、tooltip | `0 8 16 rgba(0,0,0,.14)` 浅色 / `.26` 深色 | 浮层 |
| 对话框 | `0 32 64 rgba(0,0,0,.18)` 浅色 / `.37` 深色 | 模态 |

### 3.5 动效

| 场景 | 时长 | 曲线 |
|---|---|---|
| 悬停、按下的颜色变化 | 83ms | 线性 |
| 展开、淡入 | 167ms | `cubic(0, 0, 0, 1)` |
| 页面切换、对话框 | 250ms | `cubic(0, 0, 0, 1)` |

系统关闭动画时（`MediaQuery.disableAnimations`）全部取消。数值刷新没有动画。

---

## 4. 图标

- Windows：系统字体 `Segoe Fluent Icons`（Win10 回退 `Segoe MDL2 Assets`），不打包图标字体。
- macOS：Material Symbols Outlined（现有依赖）。
- 统一通过 `TpIcons` 映射，组件里不直接写码位。
- 尺寸：按钮内、导航 16；设置卡片左侧 20；空状态 48。
- 颜色：跟随所在文字颜色。

常用码位（Segoe Fluent Icons）：

| 含义 | 码位 | 含义 | 码位 |
|---|---|---|---|
| 添加 | `E710` | 删除 | `E74D` |
| 复制 | `E8C8` | 运行 | `E768` |
| 固定 | `E718` | 取消固定 | `E77A` |
| 设置 | `E713` | 商店/市场 | `E719` |
| 日志 | `E9F9` | 更多 | `E712` |
| 返回 | `E72B` | 右箭头 | `E76C` |
| 搜索 | `E721` | 刷新 | `E72C` |
| 文件夹 | `E838` | 外部链接 | `E8A7` |
| 错误 | `E783` | 警告 | `E7BA` |

---

## 5. 管理窗口

### 5.1 整体结构

```
┌────────────────────────────────────────────────────────────┐
│ ◧ TaskPin                                       ─  □  ✕   │ 标题栏 32
├──────────────┬─────────────────────────────────────────────┤
│              │                                             │
│ ▍▣ 项目      │  项目                          [+ 添加]      │ title 28
│   ▣ 插件市场 │                                             │
│   ▣ 日志     │  ┌───────────────────────────────────────┐  │
│              │  │ ● Rich        rich_text_demo.lua  ⓘ  ⚪│  │ 60
│              │  ├───────────────────────────────────────┤  │
│              │  │ ● Clock       hud_clock.lua       ⓘ  ⚪│  │
│              │  └───────────────────────────────────────┘  │
│              │                                             │
│   ⚙ 设置     │                                             │
└──────────────┴─────────────────────────────────────────────┘
  导航 240
```

- 窗口默认 1200 × 760，最小 880 × 600；启动时等首帧渲染完成再显示窗口，不出现白屏。
- 窗口底色 `bg/window`；Windows 11 上开启 Mica（不支持时退回实色）。
- 左侧导航宽 240，窗口宽 < 900 时折叠为 48 的图标栏。导航没有背景色、没有分隔线，直接放在窗口底上。
- 导航顶部内边距 = 内容区顶部边距 = 24，第一个导航项与页面标题在同一水平线上。
- 导航项：图标 16 + `body` 文字，高 40，圆角 8，左右内边距 12；悬停 `subtle/hover`；**选中 = `nav/active` 实心底（深色 `#16181D`、浅色 `#16181D`）+ 白色文字**，不用指示条。
- 导航项右侧计数徽标：`caption` 数字，有计数时显示。日志页的徽标为错误数，非零时底色 `status/critical`、白字。
- 导航顺序：**项目、插件市场、日志**；**设置**固定在底部（无计数）。
- 删除：顶部"TASKBAR DOCK"条、侧栏底部的状态卡、Logo 方块、标语文字。版本号移到设置页的"关于"。

### 5.2 页面结构

每页：

```
页面标题（title 28）                      [次操作] [主操作]
↕ 24
内容（最大宽 1000）
```

进入下一级时，标题变成面包屑：`项目 › Rich`，点"项目"返回。**不使用左右分栏的主从布局**，详情是单独一页。

### 5.3 项目页（列表）

页头（§5.2）下面是四块，顺序固定：

**1. 状态行**（标题下一行，`body`）：`● 3 运行中　● 3 异常　○ 2 已停止`，圆点 8 用对应状态色。搜索框（宽 320，占位符"搜索项目或脚本"）放在标题行右侧、主按钮左边。

**2. 任务栏预览**：一行 `caption` 标题"任务栏预览 · N 个插件"，右侧"拖动调整顺序"提示（配置里没有位置字段，暂不显示位置下拉）。下面是深色任务栏模拟条（`bg/taskbar` `#16181D`，高 56，圆角 8，左右内边距 16）：
- 左端每个已固定插件一个拖拽占位方块 24×24（`#2A2D33`，圆角 4），可拖动排序。
- 中间并排渲染每个已固定项目的真实输出（图标 + 文字，保留脚本颜色），段间 1px `#2A2D33` 竖线，左右各 12。
- 右端画系统托盘示意：网络、音量图标和时钟（`caption`，`#C9CDD3`），让用户看清插件在任务栏中的实际位置。
- 点任一块进入该项目详情。

**3. 异常提示条**（有异常时才出现）：整宽，圆角 8，底色 `status/critical` 的 8% 淡色，左侧 `status/critical` 图标 16 + `body` 文字"N 个项目找不到脚本文件，可能已被移动或删除。"，右侧普通按钮"批量重新定位"。

**4. 分组列表**：按状态分三组，每组一个 `caption` 分组标题（运行中 / 需要处理 / 已停止），下面是卡片网格：
- **运行中**：2 列卡片（窗口窄于 1000 时 1 列），间距 16。每张卡片：名称 `bodyStrong` + 状态徽标（`status/success` 淡底、`status/success` 字，`caption`，圆角 4）＋ 右侧开关和"更多"；第二行 `caption text/secondary`：`文件名 · 每 5 秒 · 2 秒前更新`；第三行是深色迷你任务栏条（`bg/taskbar`，高 36，圆角 6），左侧标签"任务栏显示"（`caption`，`#9AA0A8`），右侧项目输出。
- **需要处理**：单列卡片，每行：左侧 `status/critical` 文件图标 16，名称 `body`，第二行错误摘要 `status/critical`；右侧普通按钮"重新选择" + 删除图标按钮。
- **已停止**：2 列卡片，比运行中更矮：左侧 40×40 圆角 8 的字母块（名称首字母，底色取名称哈希生成的低饱和色），名称 `body`，第二行 `caption text.secondary`（文件名 · 间隔）；右侧开关和"更多"。
- 整卡可点击进入详情；悬停时卡片描边变 `stroke/strong`。
- 每张卡片的"更多"菜单：复制、删除。
- 空列表：`TpEmptyState`"还没有项目" + 主按钮"添加项目"。
- 不要：类型徽标、"PINNED" 徽标、筛选 chip、列表行里再套方框。

### 5.4 项目详情页

标题 `项目 › 名称`，右上角按钮：`运行`（次按钮）。

内容自上而下，全部用设置卡片（§6.1）：

1. **预览**：一张卡片，内放一条模拟任务栏（底色取当前任务栏深/浅色，高 48），渲染脚本输出；右侧显示上次运行耗时和时间。打开页面即自动运行一次。出错时卡片下方显示错误信息（`mono`，可复制）。
2. **常规**（分组标题）
   - 名称 —— 输入框
   - 类型 —— 下拉：Lua 脚本 / URL
   - 刷新间隔 —— 数字框 + 单位下拉
   - 固定到任务栏 —— 开关
3. **数据源**
   - Lua：脚本文件 —— 路径文字 + `浏览` `打开文件夹` 按钮
   - URL：地址、请求头（可展开卡片）、取值表达式
4. **参数**（仅当脚本声明 `@param`）—— 每个参数一张卡片
5. **外观**（可展开卡片，默认收起）—— 宽度、背景色、X/Y 位置
6. **点击行为** —— 下拉：无 / 打开链接 / 弹出窗口
7. **删除项目** —— 卡片，右侧"删除"按钮（普通按钮，点击后弹确认对话框）

修改即保存，不提供"保存"按钮。

### 5.5 插件市场

- 页头：标题"插件市场"，副标题 `body text.secondary`："N 个插件 · 已安装 M 个 · 来源：官方仓库"；右侧普通按钮"管理来源" + 刷新图标按钮。
- 标题行下方左侧：分段筛选"全部 N / 已安装 M / 未安装 K"（高 32，圆角 8，选中项白底 `stroke/card` 描边）；右侧搜索框（宽 320，占位符"搜索插件名称或描述"）。
- 结果：3 列网格（窗口窄于 1000 时 2 列，窄于 760 时 1 列），间距 16。每张卡片：
  - 第一行：40×40 圆角 8 字母块（名称首字母，底色取名称哈希生成的低饱和色）+ 名称 `bodyStrong` + 描述 `caption text.secondary`（无描述时显示"暂无描述"）。
  - 第二行：深色迷你任务栏条（`bg/taskbar`，高 36，圆角 6），左侧"任务栏"标签，右侧示例输出（来自 manifest 的 preview 字段；没有则显示脚本名）。
  - 第三行：左侧来源名 `caption text.tertiary`；右侧未安装 → 主按钮"安装"；安装中 → 进度环；已安装 → `status/success` 文字"已安装" + 普通按钮"打开"。
- 使用代理时在筛选行下方显示一行 `caption`："已通过 gh-proxy 加速"。

### 5.6 日志

- 上方：每个项目一行（名称、状态、上次耗时、上次成功时间、错误次数）。
- 下方：日志文本，`mono` 12/18，`bg/cardSecondary` 底，自动滚到底，右上角"复制""清空"。

### 5.7 设置

照 Windows 设置页：

```
设置（title）

外观（bodyStrong）
┌ 🎨 应用主题              [使用系统设置 ▾] ┐
┌ 文 语言                  [简体中文     ▾] ┐

任务栏默认值
┌ ↔ 默认宽度    新项目使用    [200] px      ┐
┌ A 字号                      [9  ] pt      ┐
┌ ■ 文字颜色                  [■ #FFFFFF]   ┐
┌ ■ 背景                      [跟随任务栏 ▾]┐
┌ ⇆ 文字过长时滚动             [开关]        ┐

更新
┌ ⟳ 自动检查更新               [开关]        ┐
┌   当前版本 1.6.8             [检查更新]    ┐

插件来源
┌ ⊞ 来源列表 (1)                     ⌄     ┐  可展开

关于
┌ ◧ TaskPin 1.6.8                    ⌄     ┐  可展开：GitHub、反馈、许可
```

---

## 6. 组件

### 6.1 设置卡片（SettingsCard）

| 属性 | 值 |
|---|---|
| 最小高度 | 68 |
| 内边距 | 16 |
| 圆角 | 4（连续的一组卡片之间间距 4） |
| 底色 / 描边 | `bg/card` / `stroke/card` |
| 左侧图标 | 20，右侧留 20 |
| 标题 | `body` `text/primary` |
| 说明 | `caption` `text/secondary` |
| 右侧控件 | 右对齐，最小宽 120 |
| 窄于 476 时 | 控件换行到标题下方 |
| 可点击卡片 | 悬停 `control/fillHover`，右侧显示 `›` |
| 可展开卡片 | 右侧 `⌄`，子项缩进 48，子项之间用 `stroke/divider` |

### 6.2 按钮

| 类型 | 底色 | 文字 | 描边 |
|---|---|---|---|
| 主按钮 | `accent/fill`，悬停 `accent/fillHover` | `accent/onFill` | 无 |
| 普通按钮 | `control/fill`，悬停 `control/fillHover`，按下 `control/fillPressed` | `text/primary` | `control/stroke`，底边 `control/strokeBottom` |
| 文字按钮 | 透明，悬停 `subtle/hover` | `accent/text` | 无 |
| 图标按钮 | 透明，悬停 `subtle/hover` | `text/primary` | 无，尺寸 32×32 |

高 32，左右内边距 12，圆角 4，文字 `body`。危险操作用普通按钮，靠确认对话框把关，不用红色按钮。

### 6.3 输入框、下拉框

- 高 32，圆角 4，底色 `control/fill`，四边 `control/stroke`，底边 1px `control/strokeStrong`。
- 焦点：底色 `control/fillInputActive`，底边变为 2px `accent/fill`。
- 错误：底边 2px `status/critical`，下方 `caption` 错误文字。
- 占位符 `text/tertiary`。

### 6.4 开关

40×20，关：透明底 + 1px `control/strokeStrong` 描边 + `text/secondary` 色圆点；开：`accent/fill` 底 + `accent/onFill` 色圆点。右侧不加"开/关"文字。

### 6.5 列表分组

一张卡片（`bg/card`，`stroke/card`，圆角 8），内部行之间 1px `stroke/divider`，行左右内边距 16。

### 6.6 对话框

宽 448，圆角 8，底色 `bg/flyout`，遮罩 `smoke`，内边距 24；标题 `subtitle`；底部按钮区底色 `bg/cardSecondary`，按钮右对齐，主按钮在左、取消在右（Windows 顺序）。

### 6.7 菜单、tooltip

- 菜单：圆角 8，底色 `bg/flyout`，项高 32，悬停 `subtle/hover`。
- tooltip：圆角 4，`caption`，延迟 500ms。

### 6.8 InfoBar（页内提示）

圆角 4，高 ≥ 48，左侧状态图标 + 标题（`bodyStrong`）+ 说明（`body`），底色为对应状态色 12% 透明度。用于"无法连接网络""配置版本过高"等。

### 6.9 空状态

居中：图标 48（`text/tertiary`）、一行 `body` 说明、一个主按钮。例："还没有项目" + `添加项目`。

### 6.10 焦点

键盘焦点：外 2px `text/primary` + 内 1px 反色，圆角跟随控件。只在键盘操作时显示。

---

## 7. 任务栏条

### 7.1 外观

条要看起来像任务栏上本来就有的东西，参照系统时钟和任务栏按钮。

| 项 | Windows 11 | Windows 10 | macOS |
|---|---|---|---|
| 高度 | 任务栏高（48） | 任务栏高（40） | 24 |
| 背景 | **透明**，透出任务栏 | 透明 | 透明 |
| 默认文字色 | 跟随任务栏：深色 `#FFFFFF`，浅色 `#E4000000` | 同左 | 系统菜单栏文字色 |
| 字体 | Segoe UI Variable 12px（=9pt，与时钟一致） | Segoe UI 12px | SF Pro 13 |
| 左右内边距 | 8 | 8 | 6 |
| 悬停 | 内缩 4 的圆角 4 底，深色 `#0FFFFFFF`，浅色 `#09000000` | 无圆角整块 | 系统高亮 |
| 按下 | 悬停底色降为 `#0AFFFFFF` / `#06000000` | 同左 | 系统 |
| 图标 | 16 | 16 | 16 |
| 行数 | 最多 2 | 最多 2 | 1 |

- 用户在设置或项目外观里指定了背景色时，才画背景；否则透明（需 layered 子窗口）。
- 脚本 `font()` 指定的颜色原样使用；未指定的用默认文字色。
- 浅色任务栏上，脚本颜色对比度 < 3:1 时，在详情页预览卡片下方提示"在浅色任务栏上可能看不清"。只提示，不改色。

### 7.2 状态指示

照 Windows 11 任务栏"运行中应用"下方的小横条：

| 状态 | 指示 |
|---|---|
| 正常 | 无 |
| 首次加载中 | 内容 55% 不透明 |
| 刷新中（已有结果） | 无变化 |
| 数据过期（超过 2 倍间隔未更新） | 底部居中 3×16 圆角横条，`status/caution` |
| 出错 | 同上，`status/critical`；保留上次结果；没有结果时显示项目名 |
| 需要管理员权限 | 同上，`status/caution`；悬停 tooltip 说明，点击弹确认 |

错误详情只在 tooltip（最多 3 行）和管理窗口里出现，任务栏上不显示报错文字。

### 7.3 分段

- 两段之间画 1×14 竖线，颜色：深色任务栏 `#33FFFFFF`，浅色 `#1F000000`，左右各 6。
- 分段规则：`icon()` 开启新段并带上紧随的文本；以空白开头的文本开启新段（空白由竖线代替）；其余拼在当前段。
- 项目外观里可关闭分隔线。

### 7.4 溢出

内容超宽：Windows 跑马灯（30px/s，两端停 1.5s；系统关闭动画时改为末尾省略号）；macOS 省略号。

---

## 8. 脚本弹窗

| 模式 | 规格 |
|---|---|
| 普通（默认） | 系统窗口，标题栏 32，Mica 底，内边距 16，默认宽 360 |
| 无边框（`borderless`） | 圆角 8，底色 `bg/flyout` × `opacity`，1px `control/stroke` 描边，浮层阴影；Shift+拖动、Shift+滚轮缩放、Esc 关闭 |

内容项：

| 类型 | 规格 |
|---|---|
| 文字 | `body` `text/primary`；脚本颜色/字号覆盖 |
| 分隔线 | 1px `stroke/divider`，上下 8 |
| 表格 | 表头 `caption` `text/secondary`；行高 32；数字列右对齐、等宽数字；行间 `stroke/divider`；可点击行悬停 `subtle/hover` |
| 图片 | 等比缩放不超出内容宽，圆角 4 |
| 按钮 | 普通按钮；脚本指定背景色时文字取黑或白中对比度高的一个 |
| 网页 | 圆角 4 裁切 |

---

## 9. 文案

- 全中文界面（英文界面同理全英文），不混用。
- 不写宣传语、比喻、技术栈名。删除："Avionics Telemetry Deck"、"TASKBAR DOCK"、"LIVE TASKBAR CALIBRATION STAGE"、"CALIBRATION CONSOLE"、"Direct2D Native Engine"等。
- 说明文字一句话，说清"这个设置做什么"。不写"Master layout, default geometry…"这类罗列。
- 中文与英文、数字之间加空格（"每 5 秒"），单位紧跟数字（"200 px" 例外按控件习惯）。
- 按钮用动词：添加、运行、安装、删除、检查更新。

| 旧 | 新 |
|---|---|
| Signals | 项目 |
| Market | 插件市场 |
| Diagnostics | 日志 |
| Duplicate | 复制 |
| Run | 运行 |
| PINNED / 固定（徽标） | 删除徽标，用开关"固定到任务栏" |
| Lua 脚本（徽标） | 删除徽标，类型只在详情页显示 |
| Pick a signal on the left… | 删除（不再有空的右栏） |
| 请先选择一个项目 | 删除 |

---

## 10. 无障碍

- 正文对比度 ≥ 4.5:1，控件边界 ≥ 3:1（WinUI 默认值已满足；`text/tertiary` 只用于占位符和可省略信息）。
- 所有可点元素可用 Tab 到达，Enter/空格触发，Esc 关闭浮层。
- 图标按钮必须有 tooltip。
- 状态同时用颜色和文字表达。
- 系统关闭动画时不播放任何动画（含跑马灯、GIF）。

---

## 11. 实施

| 阶段 | 内容 | 位置 |
|---|---|---|
| A | 按本文替换 token、字体、图标映射；按 §6 重做组件；更新测试 | `packages/taskpin_design` |
| B | 按 §5 重做窗口结构和四个页面；按 §9 改文案（走 ARB） | `lib/app`、`lib/features`、`lib/l10n` |
| C | 按 §7 改原生任务栏条：透明背景、跟随任务栏深浅色、悬停圆角、底部状态横条、分段规则 | `native/win`、`native/mac` |
| D | 按 §8 调整弹窗 | `lib/features/dialogs` |

旧版 1.0（Aurora）的 token 全部废弃，不保留兼容。

---

## 参考

- Windows 字体与字阶：https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/typography
- 圆角：https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/geometry
- 间距：https://learn.microsoft.com/en-us/windows/apps/design/basics/content-basics
- 材质（Mica / Acrylic / Smoke）：https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/materials
- 设置页规范：https://learn.microsoft.com/en-us/windows/apps/design/app-settings/guidelines-for-app-settings
- SettingsCard 默认值：https://github.com/CommunityToolkit/Windows/blob/main/components/SettingsControls/src/SettingsCard/SettingsCard.xaml
- WinUI 主题色值：https://github.com/microsoft/microsoft-ui-xaml/blob/winui2/main/dev/CommonStyles/Common_themeresources_any.xaml
- 同类工具：TrafficMonitor（https://github.com/zhongyang219/TrafficMonitor/wiki/Taskbar-Window）、Stats（https://github.com/exelban/stats）、SwiftBar（https://github.com/swiftbar/SwiftBar）
