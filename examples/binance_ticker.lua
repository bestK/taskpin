-- binance_ticker.lua - 币安实时币价 (WebSocket)
-- @realtime
-- @bar_width 160

-- 可追踪的交易对 (小写)
local SYMBOLS = { "btcusdt", "ethusdt", "solusdt" }
local LABELS  = { "BTC", "ETH", "SOL" }

-- 建立 WebSocket 连接
if not _G._bn then
    local streams = {}
    for _, s in ipairs(SYMBOLS) do
        streams[#streams + 1] = s .. "@miniTicker"
    end
    local url = "wss://stream.binance.com:9443/stream?streams=" .. table.concat(streams, "/")
    _G._bn = websocket.connect(url, { reconnect = true })
    _G._bn_prices = {}
    _G._bn_changes = {}
end

local ws = _G._bn
if not ws then
    return font("BN 连接失败", "#FF3333", 9), false
end

-- 消费所有积压消息，保持最新价格
for i = 1, 32 do
    local msg = ws:recv()
    if not msg then break end
    local ok, d = pcall(json.decode, msg)
    if ok and d and d.data then
        local sym = string.lower(d.data.s or "")
        local price = tonumber(d.data.c)
        local open  = tonumber(d.data.o)
        if price then
            _G._bn_prices[sym] = price
            if open and open > 0 then
                _G._bn_changes[sym] = (price - open) / open * 100
            end
        end
    end
end

-- 格式化价格
local function fmt_price(p)
    if not p then return "---" end
    if p >= 1000 then return string.format("%.0f", p) end
    if p >= 1 then return string.format("%.2f", p) end
    return string.format("%.4f", p)
end

-- 构建 bar 显示 (选第一个有数据的币种)
local bar_sym = SYMBOLS[1]
local bar_label = LABELS[1]
local bar_price = _G._bn_prices[bar_sym]
local bar_chg = _G._bn_changes[bar_sym]

local chg_color = "#888888"
local chg_text = ""
if bar_chg then
    if bar_chg >= 0 then
        chg_color = "#4CAF50"
        chg_text = string.format("+%.1f%%", bar_chg)
    else
        chg_color = "#F44336"
        chg_text = string.format("%.1f%%", bar_chg)
    end
end

local connected = ws:is_connected()
local bar
if not bar_price then
    bar = font(connected and "等待行情..." or "连接中...", "#888888", 9)
else
    bar = font(bar_label .. " ", "#888888", 8)
        .. font(fmt_price(bar_price), "#FFFFFF", 10)
        .. font(" " .. chg_text, chg_color, 8)
end

-- 构建 dialog 详情表格
local rows = {}
for i, sym in ipairs(SYMBOLS) do
    local p = _G._bn_prices[sym]
    local c = _G._bn_changes[sym]
    local price_str = fmt_price(p)
    local chg_str = "---"
    if c then
        chg_str = (c >= 0 and "+" or "") .. string.format("%.2f%%", c)
    end
    rows[#rows + 1] = { LABELS[i], price_str, chg_str }
end

local info = dialog({
    title = "Binance Realtime",
    width = 340, height = 220,
    refresh = 1,
    content = {
        { type = "text", value = "币安实时行情", color = "#F0B90B", size = 12, bold = true },
        { type = "text", value = connected and "● 已连接" or "○ 重连中...",
          color = connected and "#4CAF50" or "#FF6600", size = 9 },
        { type = "hr" },
        { type = "table",
          columns = { "币种", "价格(USDT)", "24h涨跌" },
          col_widths = { 60, 120, 80 },
          rows = rows },
    }
})

return bar, true, info