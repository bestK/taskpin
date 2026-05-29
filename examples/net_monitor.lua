-- Net Monitor: show top processes with active network connections
-- Uses sys.net_processes() + dialog() for detailed view
-- Recommended bar_width: 200+

local procs = sys.net_processes() or {}

local function fmt_speed(bytes)
    bytes = bytes or 0
    if bytes > 1048576 then return string.format("%.1fM/s", bytes / 1048576) end
    if bytes > 1024 then return string.format("%.1fK/s", bytes / 1024) end
    return string.format("%dB/s", math.floor(bytes))
end

-- Sort by download speed descending
table.sort(procs, function(a, b) return (a.download or 0) > (b.download or 0) end)

-- Build dialog table rows (top 15)
local rows = {}
for i = 1, math.min(#procs, 15) do
    local p = procs[i]
    rows[i] = { p.name or "?", tostring(p.connections or 0), fmt_speed(p.download), fmt_speed(p.upload) }
end

local detail = dialog({
    title = "Network Activity",
    width = 440, height = 380,
    refresh = 2,
    content = {
        { type = "text", value = "Active Connections (" .. #procs .. " processes)", color = "#4FC3F7", size = 11, bold = true },
        { type = "hr" },
        { type = "table",
          columns = {"Process", "Conn", "Download", "Upload"},
          rows = rows
        },
    }
})

-- Bar: compact summary
local total_dl, total_ul = 0, 0
for _, p in ipairs(procs) do
    total_dl = total_dl + (p.download or 0)
    total_ul = total_ul + (p.upload or 0)
end

local bar_text = font("↓" .. fmt_speed(total_dl), "#4FC3F7", 9)
    .. font(" ↑" .. fmt_speed(total_ul), "#81C784", 9)
    .. font(" [" .. #procs .. "]", "#888", 8)

return bar_text, true, detail