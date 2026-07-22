# Design: ImGui Script Dialog + Legacy Cleanup + UI Theme

**Date:** 2026-07-22  
**Branch context:** `feat/windows-ui`  
**Status:** Approved for implementation planning  

## 1. Goals

1. **Script Dialog** (Lua `dialog{}` / `DialogSpec`): migrate from Win32 GDI (`lib/script_dialog.c`) to **ImGui + `UiWindow`**, preserving Lua API and runtime behavior.
2. **Legacy cleanup:** remove unused Win32 management dialogs (`edit_dialog.c`, `settings_dialog.c`, `market_dialog.c`); management UI already lives in `ui_*_view.cpp`.
3. **Configurable theme:** `light` / `dark` / `system`, applied to management UI and Script Dialog.

## 2. Non-Goals

- Do not change taskbar bar painting (remains GDI).
- Do not extend Dialog DSL (no new item types or fields).
- Do not support multiple simultaneous Script Dialog instances (keep singleton semantics of `s_dialog_hwnd`).
- Do not require opening the main host window solely to show a Script Dialog.

## 3. Current State

| Surface | Implementation | Notes |
|---------|----------------|-------|
| Main list, Settings, Market, Edit | `ui_host` + `ui_*_view` + `UiWindow` (D3D11 + ImGui) | Active path |
| Old management dialogs | `src/edit_dialog.c`, `settings_dialog.c`, `market_dialog.c` | Still in Makefile; superseded by ImGui views |
| Script Dialog | `lib/script_dialog.c` (GDI, dark hard-coded) | Opened from `bar_window.c` on `CLICK_DIALOG` |
| Theme config | None | Only bar `font_color` / `bg_color` exist |

Management dialogs already use independent windows (`ui_window_run_modal`). Script Dialog is the remaining GDI dialog path.

## 4. Architecture

```
bar click CLICK_DIALOG
        │
        ▼
  show_script_dialog()          ← C API unchanged (script_dialog.h)
        │
        ▼
  UiWindow (own HWND; share D3D from host if available, else create own)
        │
        ▼
  ui_script_dialog draw loop    ← ImGui maps DialogSpec items
        │
  refresh timer → re-run Lua → update DialogSpec → next frame
```

### Layers

| Layer | Responsibility |
|-------|----------------|
| `script_dialog.h` | Public C API: `script_dialog_init`, `show_script_dialog` (signatures unchanged) |
| Implementation (C++ with `extern "C"`) | Window lifecycle, singleton, timers, bridge to ImGui draw |
| `ui_window.*` | Create flags for borderless / layered opacity / clickthrough; frame loop |
| `ui_theme.*` | Resolve light/dark/system; apply ImGui style + clear color |
| Deleted | `edit_dialog.c`, `settings_dialog.c`, `market_dialog.c` |

### Device sharing

1. Prefer `ui_host_window()` shared D3D device when host exists.
2. If host not created, Script Dialog creates its **own** D3D device (`share_device = NULL`). Do not force-show the main window.

## 5. API Compatibility

- `DialogSpec` / `DialogItem` in `scripting.h`: **unchanged**.
- Lua `dialog({...})` and docs remain behavior-compatible.
- Flags preserved: `borderless`, `clickthrough`, `opacity` (0–255), `refresh` (seconds).
- Singleton: if a Script Dialog already exists, foreground it; do not open a second instance.

## 6. Theme

### Config

- Add `int ui_theme` to `TaskPinConfig`:
  - `0` = light  
  - `1` = dark  
  - `2` = system (read `HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize\AppsUseLightTheme`; on failure default light)
- Persist in existing config load/save.
- Settings UI: dropdown “界面主题 / UI theme” (i18n keys).

### Apply

- `ui_theme_resolved()` → final light or dark.
- `ui_theme_apply(...)` → set ImGui style colors and clear RGBA.
- Apply on window create and when theme changes (settings save → refresh host + open script dialog style on next frame).

### Palettes

- **Light:** existing `ui_common.h` classic tool chrome tokens.
- **Dark:** near current script dialog (`~#1E1E1E` bg, `~#DCDCDC` text, zebra rows, slightly lighter button face).

### Script Dialog colors

- Global theme sets defaults (bg, text, table, separators).
- Per-item `color` / `bg_color` when not `0xFFFFFFFF` **override** theme for that item.

## 7. Script Dialog Behavior (ImGui)

### Window flags (via extended `ui_window_create` / create_ex)

| Flag | Behavior |
|------|----------|
| Normal | `WS_OVERLAPPEDWINDOW`, scroll inside ImGui, `WS_EX_TOPMOST` |
| `borderless` | `WS_POPUP`; Shift+drag move; Shift+wheel resize; Esc closes (preserve existing Esc-when-cursor-over-window or keydown semantics) |
| `clickthrough` | `WS_EX_LAYERED` + hit-test transparent (`HTTRANSPARENT`); mouse passes through; ImGui does not receive clicks |
| `opacity` | Layered alpha via `SetLayeredWindowAttributes` |

### Item mapping

| Type | ImGui |
|------|-------|
| `DI_TEXT` | `Text` / `TextColored`; optional inline image + text |
| `DI_HR` | `Separator` |
| `DI_TABLE` | `BeginTable`; row “Open” runs `row_urls` / `row_cmds` (same ShellExecute / cmd as today) |
| `DI_IMG` | ImGui `Image` from D3D SRV |
| `DI_BUTTON` | `Button`; click runs `url` / `cmd` |

### Refresh

- If `spec.refresh > 0`, timer re-executes Lua for the dialog’s script path/params.
- On success with `click_action == CLICK_DIALOG` and non-empty items, replace `DialogSpec` and redraw.
- On failure, keep previous spec; do not close the window.

### Images and GIF

- Load via existing `image_load` / `image_is_animated`.
- Convert current-frame `HBITMAP` to `ID3D11ShaderResourceView` (helper e.g. `ui_texture_from_hbitmap`).
- **Animated GIF:** each UI frame call `image_load` (time-based frame); upload GPU texture **only when frame index or bitmap pointer changes**.
- Keep ~16 ms frame timer while dialog is open (same as other `UiWindow`s).
- Release all dialog-owned SRVs on destroy.

## 8. Legacy Cleanup

### Delete

- `src/edit_dialog.c`
- `src/settings_dialog.c`
- `src/market_dialog.c`

### Adjust

- Makefile: remove those three from `SRCS`.
- `ui.h`: remove `show_edit_dialog` / `show_settings_dialog` / `show_market_dialog` declarations and any edit-dialog-only control IDs that nothing else needs (verify with grep).
- Keep `main_window.c` thin wrappers (`listview_populate` → `modern_ui_refresh`, `show_main_window` → `modern_ui_show`) for bar entry points.

### Unchanged behavior

- `ui_edit_view.cpp`, `ui_settings_view.cpp`, `ui_market_view.cpp` logic; only theme apply integration.

## 9. Expected File Changes

### Add

- `src/ui_theme.h`, `src/ui_theme.cpp`
- Script dialog ImGui implementation (e.g. `src/ui_script_dialog.cpp` with `extern "C"` exports, or rewrite `lib/script_dialog` as C++ and update Makefile)
- Optional texture helper colocated with UI (e.g. in `ui_window` or small `ui_texture` unit)

### Modify

- `lib/config.h`, `lib/config.c` — `ui_theme`
- `src/ui_window.h`, `src/ui_window.cpp` — create flags + borderless/layered handling
- `src/ui_settings_view.cpp` — theme control
- `src/ui_common.h` — light tokens remain; dark tokens live in theme module (avoid dual sources of truth)
- `src/ui_host.cpp` / views — apply theme on frames / after settings
- `Makefile` — new objects; drop legacy dialogs
- i18n strings for theme labels

### Remove

- Three legacy `*_dialog.c` files

### Docs (optional follow-up)

- Note in LUA API that dialog is ImGui-backed; API fields unchanged.

## 10. Error Handling

| Case | Behavior |
|------|----------|
| D3D / window create fails | Fail quietly or MessageBox once; no crash (match current alloc-fail silence where appropriate) |
| Lua refresh fails | Keep last good `DialogSpec` |
| Image load fails | Skip draw for that image (same as GDI path) |
| url/cmd launch fails | No error dialog (same as today) |
| System theme registry fail | Default light |

## 11. Testing

1. DSL items: text / hr / table / img / button; colored text/buttons.
2. `examples/hud_clock.lua`: borderless + clickthrough + opacity + refresh.
3. Table row Open: url and cmd.
4. Singleton: repeated bar clicks only foreground existing dialog.
5. Theme light/dark/system; management + script dialog; restart persistence.
6. Animated GIF inside script dialog continues to animate.
7. Legacy `.c` files gone from link; edit/settings/market still work via ImGui.
8. `make clean && make` succeeds.

## 12. Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| `clickthrough` vs ImGui input | Full-window transparent hit-test; no mouse to ImGui (HUD display-only) |
| Binary size / deps | Already links ImGui + D3D11; no new libraries |
| HBITMAP → D3D complexity | Single helper; update texture only on frame change for GIF |
| Hidden references to old dialogs | Full-repo grep before delete; strip `ui.h` declarations |

## 13. Acceptance Criteria

- [ ] Lua `dialog{}` behavior matches current product without script changes.
- [ ] `hud_clock` and typical table dialogs work as today (including special window flags).
- [ ] Theme three modes work and persist across restart.
- [ ] Animated images animate in Script Dialog.
- [ ] Legacy Win32 management dialog sources removed from tree and build.
- [ ] Clean release build succeeds.

## 14. Implementation Order (for planning skill)

1. Theme config + `ui_theme` + settings UI + apply on host/modals.
2. Extend `ui_window` create flags (borderless / opacity / clickthrough).
3. Texture-from-HBITMAP + GIF-aware upload.
4. Reimplement Script Dialog on ImGui; keep C API; wire from bar.
5. Delete legacy dialogs; Makefile / `ui.h` cleanup.
6. Verification against testing checklist.
