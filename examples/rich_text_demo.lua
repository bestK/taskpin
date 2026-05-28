-- Rich text demo: colored multi-line status with alignment
-- Usage: select this as a Lua script item in TaskPin
--
-- font(text, color, size, align)
--   color: "#RGB" or "#RRGGBB" or nil for default
--   size:  point size or nil for default
--   align: "left" (default) | "right" | "center"

local time = os.date("%H:%M:%S")
local date = os.date("%m/%d")

return font("TIME ", "#888888", 8) .. font(time, "#00FF00", 12)
    .. font(date, "#FFAA00", 9, "right")
    .. font("\n")
    .. font("DATE ", "#888888", 8) .. font(date, "#FFAA00", 12)
    .. font(time, "#666666", 9, "right")