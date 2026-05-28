-- System monitor: Network + CPU + Memory on taskbar
-- Uses sys.* built-in API + font() rich text
-- Recommended bar_width: 250+

local cpu = sys.cpu()
local mem = sys.memory()
local net = sys.net_speed()

local function fmt_speed(bytes)
    if bytes > 1048576 then return string.format("%.1fM/s", bytes / 1048576) end
    if bytes > 1024 then return string.format("%.1fK/s", bytes / 1024) end
    return string.format("%dB/s", bytes)
end

return font("↑: ", "#888", 9) .. font(fmt_speed(net.upload), "#81C784", 9)
    .. font("CPU: " .. cpu .. "%", nil, 9, "right")
    .. font("\n")
    .. font("↓: ", "#888", 9) .. font(fmt_speed(net.download), "#4FC3F7", 9)
    .. font("内存: " .. mem.percent .. "%", nil, 9, "right")