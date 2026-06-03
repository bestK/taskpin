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
    return string.format("%dB/s", math.floor(bytes))
end

local mem_pct = mem.percent or 0

local cpu_procs = sys.top_processes("cpu", 8) or {}
local mem_procs = sys.top_processes("mem", 8) or {}
local net_procs = sys.net_processes() or {}

-- CPU top processes
local cpu_rows = {}
for i = 1, #cpu_procs do
    local p = cpu_procs[i]
    local pid = p.pid or 0
    local name = p.name or "?"
    cpu_rows[i] = { name, string.format("%.1f%%", p.cpu or 0),
        lua = 'sys.kill(' .. pid .. '); sys.notify("System Monitor", "已终止: ' .. name .. '")',
        btn_text = "Kill" }
end

-- Memory top processes
local mem_rows = {}
for i = 1, #mem_procs do
    local p = mem_procs[i]
    local pid = p.pid or 0
    local name = p.name or "?"
    mem_rows[i] = { name, tostring(p.mem_mb or 0) .. " MB",
        lua = 'sys.kill(' .. pid .. '); sys.notify("System Monitor", "已终止: ' .. name .. '")',
        btn_text = "Kill" }
end

-- Network processes
table.sort(net_procs, function(a, b) return (a.download or 0) > (b.download or 0) end)
local net_rows = {}
for i = 1, math.min(#net_procs, 8) do
    local p = net_procs[i]
    local pid = p.pid or 0
    local name = p.name or "?"
    net_rows[i] = { name, fmt_speed(p.download), fmt_speed(p.upload),
        lua = 'sys.kill(' .. pid .. '); sys.notify("System Monitor", "已终止: ' .. name .. '")',
        btn_text = "Kill" }
end

local info = dialog({
    title = "System Monitor",
    width = 440, height = 520,
    refresh = 2000,
    content = {
        { type = "text", value = "CPU: " .. cpu .. "%", color = "#FF8A65", size = 11, bold = true },
        { type = "table", columns = { "进程", "CPU" }, rows = cpu_rows },
        { type = "hr" },
        { type = "text", value = "内存: " .. mem_pct .. "% (" .. (mem.used_mb or 0) .. "/" .. (mem.total_mb or 0) .. " MB)", color = "#CE93D8", size = 11, bold = true },
        { type = "table", columns = { "进程", "内存" }, rows = mem_rows },
        { type = "hr" },
        { type = "text", value = "网络: ↓ " .. fmt_speed(net.download) .. "  ↑ " .. fmt_speed(net.upload), color = "#4FC3F7", size = 11, bold = true },
        { type = "table", columns = { "进程", "下载", "上传" }, rows = net_rows },
    }
})

local bar_text = font("↑: ", "#888", 9) .. font(fmt_speed(net.upload), "#81C784", 9)
    .. font("CPU: " .. cpu .. "%", nil, 9, "right")
    .. font("\n")
    .. font("↓: ", "#888", 9) .. font(fmt_speed(net.download), "#4FC3F7", 9)
    .. font("内存: " .. mem_pct .. "%", nil, 9, "right")

return bar_text, true, info