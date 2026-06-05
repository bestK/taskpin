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

local charge_icon = d.is_charging and "⚡" or ""
local range = d.range_km or 0

-- 胎压
local fp = d.front_tire_pressure or "-"
local rp = d.rear_tire_pressure or "-"

-- Bar: 上下两行布局
local bar = font(charge_icon .. tostring(math.floor(soc)) .. "%", soc_color, 9)
    .. font(" " .. tostring(math.floor(range)) .. "km", "#FFFFFF", 8,"right")
    .. font("\n")
    .. font("F:" .. fp, "#FFFFFF", 8)
    .. font(" R:" .. rp, "#FFFFFF", 8,"right")

-- Dialog
local info = dialog({
    title = "Zeeho " .. (d.vehicle_name or ""),
    width = 320, height = 260,
    content = {
        { type = "text", value = (d.vehicle_name or "Zeeho") .. " " .. charge_icon, color = "#4FC3F7", size = 12, bold = true },
        { type = "hr" },
        { type = "table",
          columns = { "项目", "数值" },
          rows = {
            { "电量 SOC", tostring(math.floor(soc)) .. "%" },
            { "续航里程", tostring(math.floor(range)) .. " km" },
            { "充电状态", d.is_charging and "充电中" or "未充电" },
            { "前胎压", fp .. " bar / " .. (d.front_tire_temp or "-") .. "°C" },
            { "后胎压", rp .. " bar / " .. (d.rear_tire_temp or "-") .. "°C" },
            { "总里程", string.format("%.1f km", d.total_km or 0) },
            { "更新时间", d.refresh_time or "-" },
          }
        },
    }
})

return bar, true, info