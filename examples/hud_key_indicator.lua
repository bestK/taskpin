-- hud_key_indicator.lua - 实时按键指示器 HUD
-- @realtime
-- 类似 OBS 按键显示器，桌面悬浮显示当前按下的按键

sys.watch_keys(
    "ctrl", "shift", "alt",
    "space", "enter", "tab", "escape", "backspace", "delete",
    "up", "down", "left", "right",
    "lclick", "rclick",
    "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
    "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
    "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12"
)

local FADE_TIME = 2.0
local MAX_HISTORY = 8

if not _G._keys or not _G._keys.history then
    _G._keys = { history = {} }
end
local state = _G._keys
local now = os.clock()

local display_names = {
    ctrl = "Ctrl", shift = "Shift", alt = "Alt",
    space = "Space", enter = "⏎", tab = "Tab",
    escape = "Esc", backspace = "⌫", delete = "Del",
    up = "↑", down = "↓", left = "←", right = "→",
    lclick = "LMB", rclick = "RMB",
}

local modifiers = { "ctrl", "shift", "alt" }
local trigger_keys = {
    "a","b","c","d","e","f","g","h","i","j","k","l","m",
    "n","o","p","q","r","s","t","u","v","w","x","y","z",
    "0","1","2","3","4","5","6","7","8","9",
    "f1","f2","f3","f4","f5","f6","f7","f8","f9","f10","f11","f12",
    "space", "enter", "tab", "escape", "backspace", "delete",
    "up", "down", "left", "right",
    "lclick", "rclick",
}

-- 检测修饰键当前状态
local active_mods = {}
for _, mod in ipairs(modifiers) do
    if sys.key_pressed(mod) then
        active_mods[#active_mods + 1] = display_names[mod]
    end
end

-- 用 key_triggered 捕捉快速按键
for _, key in ipairs(trigger_keys) do
    if sys.key_triggered(key) then
        local label = display_names[key] or string.upper(key)
        if #active_mods > 0 then
            label = table.concat(active_mods, "+") .. "+" .. label
        end
        table.insert(state.history, 1, { text = label, time = now })
        if #state.history > MAX_HISTORY then
            table.remove(state.history)
        end
    end
end

-- 清理过期历史
while #state.history > 0 and (now - state.history[#state.history].time) > FADE_TIME do
    table.remove(state.history)
end

-- 构建显示文本
local show_text = ""
local alpha = 30
if #state.history > 0 then
    local parts = {}
    for i = math.min(#state.history, 5), 1, -1 do
        parts[#parts + 1] = state.history[i].text
    end
    show_text = table.concat(parts, "  ")
    local age = now - state.history[1].time
    if age < 0.5 then
        alpha = 230
    else
        alpha = math.max(30, math.floor(230 * (1.0 - (age - 0.5) / (FADE_TIME - 0.5))))
    end
end

local bar
if show_text ~= "" then
    bar = font("⌨ " .. show_text, "#00FF88", 9)
else
    bar = font("⌨ ...", "#666666", 9)
end

local hud_content = {}
if show_text ~= "" then
    hud_content[1] = { type = "text", value = show_text, color = "#00FF88", size = 20, bold = true }
else
    hud_content[1] = { type = "text", value = "Waiting...", color = "#555555", size = 14 }
end

local hud_w, hud_h = 320, 60

local hud = dialog({
    title = "Key Indicator",
    width = hud_w, height = hud_h,
    refresh = 50,
    borderless = true,
    clickthrough = true,
    opacity = 150,
    transparent_bg = false,
    content = hud_content
})

return bar, true, hud
