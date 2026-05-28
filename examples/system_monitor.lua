-- System monitor: CPU + Memory + Network on taskbar
-- Uses sys.* built-in API

local cpu = sys.cpu()
local mem = sys.memory()
local net = sys.net_speed()

local cpu_color = cpu > 80 and "#FF0000" or (cpu > 50 and "#FFAA00" or "#00FF00")
local mem_color = mem.percent > 80 and "#FF0000" or (mem.percent > 60 and "#FFAA00" or "#00FF00")

local function fmt_speed(bytes)
    if bytes > 1048576 then return string.format("%.1fMB/s", bytes / 1048576) end
    if bytes > 1024 then return string.format("%.0fKB/s", bytes / 1024) end
    return string.format("%.0fB/s", bytes)
end

return font("CPU ", "#888", 8) .. font(cpu .. "%", cpu_color, 11)
    .. font("MEM " .. mem.percent .. "%", mem_color, 9, "right")
    .. font("\n")
    .. font("↓" .. fmt_speed(net.download), "#4FC3F7", 8)
    .. font(" ↑" .. fmt_speed(net.upload), "#81C784", 8)
    .. font(mem.used_mb .. "/" .. mem.total_mb .. "MB", "#888", 8, "right")