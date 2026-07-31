-- zeeho.lua - Zeeho 电动车状态监控
-- @param VIN string 车架号
-- @refresh 30000
-- bar_width 推荐: 200+

local vin = args.VIN or ""
local url = "https://zeeho.linkof.link/api/" .. vin .. "/summary.json"

local resp = http.get(url)
if not resp then
    return font("Zeeho 离线", "#FF3333", 9), false, ""
end

local d = json.decode(resp)
if not d or not d.has_data then
    return font("Zeeho 无数据", "#888888", 9), false, ""
end

-- SOC + 充电状态
local soc = d.soc or 0
local soc_color
if soc >= 60 then soc_color = "#33CC33"
elseif soc >= 30 then soc_color = "#FFAA00"
else soc_color = "#FF3333"
end

local range = d.range_km or 0

-- 接口给的是瓦特，上千转 kW 保留一位，避免 bar 上出现 1109.6W 这种长串
local function fmt_power(w)
    w = w or 0
    if w >= 1000 then
        return string.format("%.1fkW", w / 1000)
    end
    return string.format("%.0fW", w)
end

-- 去掉 ⚡ 后，功率读数本身就是 bar 上唯一的充电信号，
-- 因此充电中即使读数为 0 也要显示，不再回落到续航
local power_text = d.is_charging and fmt_power(d.charge_power) or nil

-- 胎压
local fp = d.front_tire_pressure or "-"
local rp = d.rear_tire_pressure or "-"

-- Bar: 上下两行布局
-- 右上槽位二选一：充电时给功率，否则给续航
local right_text, right_color = range .. "km", "#FFFFFF"
if power_text then
    right_text, right_color = power_text, "#4FC3F7"
end

local bar = font(tostring(soc) .. "%", soc_color, 9)
    .. font(" " .. right_text, right_color, 8,"right")
    .. font("\n")
    .. font("F:" .. fp, "#FFFFFF", 8)
    .. font(" R:" .. rp, "#FFFFFF", 8,"right")

-- Dialog: 行表按状态拼装，充电功率行只在充电时插入
local rows = {
    { "电量 SOC", tostring(soc) .. "%" },
    { "续航里程", tostring(range) .. " km" },
    { "充电状态", d.is_charging and "充电中" or "未充电" },
}
if power_text then
    table.insert(rows, { "充电功率", power_text })
end
for _, r in ipairs({
    { "前胎压", fp .. " bar / " .. (d.front_tire_temp or "-") .. "°C" },
    { "后胎压", rp .. " bar / " .. (d.rear_tire_temp or "-") .. "°C" },
    { "总里程", string.format("%.1f km", d.total_km or 0) },
    { "更新时间", d.refresh_time or "-" },
}) do
    table.insert(rows, r)
end

local info = dialog({
    title = "Zeeho " .. (d.vehicle_name or ""),
    width = 320, height = 260,
    refresh = 30,
    content = {
        { type = "text", value = d.vehicle_name or "Zeeho", color = "#4FC3F7", size = 12, bold = true },
        { type = "hr" },
        { type = "table", columns = { "项目", "数值" }, rows = rows },
    }
})

return bar, true, info