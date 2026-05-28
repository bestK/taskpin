-- System monitor: Network + CPU + Memory on taskbar
-- Uses sys.* built-in API + font() rich text
-- Recommended bar_width: 250+

local cpu = sys.cpu() or 0
local mem = sys.memory() or {}
local net = sys.net_speed() or {}

local function fmt_speed(bytes)
    bytes = bytes or 0
    if bytes > 1048576 then return string.format("%.1fM/s", bytes / 1048576) end
    if bytes > 1024 then return string.format("%.1fK/s", bytes / 1024) end
    return string.format("%dB/s", bytes)
end

local mem_pct = mem.percent or 0

return font("↑: ", "#888", 9) .. font(fmt_speed(net.upload), "#81C784", 9)
    .. font("CPU: " .. cpu .. "%", nil, 9, "right")
    .. font("\n")
    .. font("↓: ", "#888", 9) .. font(fmt_speed(net.download), "#4FC3F7", 9)
    .. font("内存: " .. mem_pct .. "%", nil, 9, "right")