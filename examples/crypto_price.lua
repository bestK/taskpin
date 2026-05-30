-- 加密货币价格监控
-- @param SYMBOLS string 币种 (逗号分隔, 如 BTC,ETH,SOL)
-- @param CURRENCY string 计价货币 (默认 USD)
-- @refresh 15000

local symbols_str = (args and args.SYMBOLS and args.SYMBOLS ~= "") and args.SYMBOLS or "BTC,ETH"
local currency = (args and args.CURRENCY and args.CURRENCY ~= "") and args.CURRENCY or "USD"

local symbols = {}
for s in symbols_str:gmatch("[^,]+") do
    symbols[#symbols + 1] = s:match("^%s*(.-)%s*$"):upper()
end

local ids_map = {
    BTC = "bitcoin", ETH = "ethereum", SOL = "solana", BNB = "binancecoin",
    XRP = "ripple", ADA = "cardano", DOGE = "dogecoin", DOT = "polkadot",
    MATIC = "matic-network", AVAX = "avalanche-2", LINK = "chainlink",
    UNI = "uniswap", ATOM = "cosmos", LTC = "litecoin", FIL = "filecoin",
}

local ids = {}
for _, s in ipairs(symbols) do
    ids[#ids + 1] = ids_map[s] or s:lower()
end

local url = "https://api.coingecko.com/api/v3/simple/price?ids=" .. table.concat(ids, ",") .. "&vs_currencies=" .. currency:lower() .. "&include_24hr_change=true"
local raw = http.get(url)
if not raw then
    return font("₿ --", "#888", 10), false
end

local data = json.decode(raw)
if not data or type(data) ~= "table" then
    return font("₿ --", "#888", 10), false
end

local function fmt_price(n)
    if not n then return "--" end
    if n >= 1000 then return string.format("$%.0f", n)
    elseif n >= 1 then return string.format("$%.2f", n)
    else return string.format("$%.4f", n) end
end

local function fmt_change(n)
    if not n then return "-- " end
    return string.format("%+.1f%%", n)
end

local first_id = ids[1]
local first_data = data[first_id]
local first_price = first_data and first_data[currency:lower()]
local first_change = first_data and first_data[currency:lower() .. "_24h_change"]
local bar_color = (first_change and first_change >= 0) and "#33CC33" or "#FF4444"

local bar = font(symbols[1] .. " " .. fmt_price(first_price), bar_color, 10)
    .. font(" " .. fmt_change(first_change), bar_color, 8)

local rows = {}
for i, s in ipairs(symbols) do
    local id = ids[i]
    local d = data[id]
    if d then
        local price = d[currency:lower()]
        local change = d[currency:lower() .. "_24h_change"]
        local c = (change and change >= 0) and "#33CC33" or "#FF4444"
        rows[#rows + 1] = { s, fmt_price(price), fmt_change(change) }
    else
        rows[#rows + 1] = { s, "--", "--" }
    end
end

local detail = dialog({
    title = "Crypto Prices",
    width = 360, height = 300,
    refresh = 15,
    bg_color = "#1a1a2e",
    content = {
        { type = "text", value = "Crypto Market (" .. currency .. ")", color = "#4FC3F7", size = 12, bold = true },
        { type = "hr" },
        { type = "table", columns = {"Coin", "Price", "24h"}, rows = rows },
    }
})

return bar, true, detail
