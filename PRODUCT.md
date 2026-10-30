# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

(Flutter desktop app for Windows; macOS planned. No native iOS/Android design language applies. The manager window is a Flutter surface with a self-drawn title bar.)

## Users

Developers who write small Lua scripts to pin live information to the Windows taskbar: AI tool status and API usage/balances, system resources, network traffic, task trackers, database sessions. They open the manager window occasionally to add, edit, pin, or troubleshoot a script; the rest of the time TaskPin runs in the background and the taskbar strip is the product.

## Product Purpose

TaskPin embeds one or more native strips inside the Windows taskbar. Each strip shows the output of a Lua script (coloured text, icons, PNG/GIF images, two-line layouts) and refreshes on its own interval. Clicking a strip can open a detail dialog (text, images, tables, borderless HUD overlays). Success is a script going from idea to a correct, glanceable strip with minimal friction, and staying correct without attention.

## Positioning

Lives inside the taskbar itself rather than on the desktop or in the tray, and is driven by a tiny Lua API (`font()`, `icon()`, `dialog()`, `http`, `json`, `sys`) with `@param` / `@refresh` headers that generate the configuration UI. Self-contained ~12 MB zip, no runtime to install.

## Operating Context

- Manager window: project list (`/signals`), project editor (`/signals/:id`: script, params, colours, refresh interval, pin state), plugin market (`/market`, community scripts from github.com/bestK/taskpin-plugins plus custom sources), settings (`/settings`), logs (`/diagnostics`, placeholder today).
- The taskbar strip is native Direct2D, not Flutter. The manager shows a simulated taskbar preview.
- Closing the manager hides it; the strips keep running. Exit is from the strip's right-click menu.
- UI is bilingual: Chinese (zh) and English (en), following the OS language.
- Light and dark themes, following the system by default; the Windows taskbar itself may be light or dark independently of the manager.

## Capabilities and Constraints

- Flutter desktop with Riverpod and go_router; the design system lives in `packages/taskpin_design` (tokens, theme, components, debug gallery at `/gallery`).
- Script dialogs are a separate Flutter engine window (`desktop_multi_window`).
- Strip colours are authored per item by the user; the manager must render arbitrary user colours legibly.
- Minimum window size 800×560; default 1200×760.
- System fonts only today (Segoe UI Variable / Microsoft YaHei UI, Cascadia Mono); no bundled font files.

## Brand Commitments

Name "TaskPin". Existing app mark in the title bar. No other binding visual commitments; the user has asked for a replacement visual style (2026-10-30), so the Win11-native look in docs/VISUAL_SPEC.md 2.0 is evidence, not authority.

## Evidence on Hand

- Real example scripts in `examples/` (claude_status, system_monitor, net_monitor, hud_clock, newapi_balance, zentao_task, oracle_sessions) and `examples/claude_status.gif`.
- `docs/preview.png` product screenshot; Lua API docs in `docs/LUA_API.md` / `docs/LUA_API_EN.md`.
- No user counts, testimonials, or benchmarks exist; do not invent them.

## Product Principles

1. The taskbar strip is the product; the manager exists to get a strip right and then get out of the way.
2. Show the real output: preview what the strip will actually render, with the user's colours, before pinning.
3. Script state (running, error, stale, unpinned) must be legible at a glance, with the error text one step away.
4. Respect a developer's time: dense, keyboard-friendly, no ceremony.
