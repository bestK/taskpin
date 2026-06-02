-- desktop_goose.lua
-- @name Desktop Goose
-- @refresh 50
-- @bar_width 100
-- @require 1.4.0

-- GitHub 代理检测（只执行一次）
if _G._goose_sprite == nil then
    local function is_china()
        local geo = http.get("https://api.ip.sb/geoip")
        if not geo then return false end
        local info = json.decode(geo)
        return info and info.country_code == "CN"
    end
    local proxy = is_china() and "https://gh-proxy.com/" or ""
    _G._goose_sprite = proxy .. "https://raw.githubusercontent.com/bestK/taskpin-plugins/master/goose_sprites.png"
end
local sprite_sheet = _G._goose_sprite

local frame_w = 32
local frame_h = 32

local goose_w = 96
local goose_h = 96

--------------------------------------------------
-- 动画定义 (row = sprite sheet 行号, frames = 该行帧数)
-- 精灵表每帧 32x32, 18组动画:
-- 0: 起身(右)  1: 起身(左)
-- 2: 跳跃(右)  3: 跳跃(左)
-- 4: 转身/站立(右)  5: 转身/站立(左)
-- 6: 行走(右)  7: 行走(左)
-- 8: 张望坐姿(右)  9: 张望坐姿(左)
-- 10: 坐下(右)  11: 坐下(左)
-- 12: 飞行(右, 含起飞降落)  13: 飞行(左, 含起飞降落)
-- 14: 睡觉(右, 含入睡起床)  15: 睡觉(左, 含入睡起床)
-- 16: 进食(右)  17: 进食(左)
--------------------------------------------------

local ANIM = {
    standup_right  = { row = 0,  frames = 4 },
    standup_left   = { row = 1,  frames = 4 },
    jump_right     = { row = 2,  frames = 6 },
    jump_left      = { row = 3,  frames = 6 },
    turn_right     = { row = 4,  frames = 4 },
    turn_left      = { row = 5,  frames = 4 },
    walk_right     = { row = 6,  frames = 4 },
    walk_left      = { row = 7,  frames = 4 },
    look_right     = { row = 8,  frames = 3 },
    look_left      = { row = 9,  frames = 3 },
    sit_right      = { row = 10, frames = 4 },
    sit_left       = { row = 11, frames = 4 },
    fly_right      = { row = 12, frames = 15 },
    fly_left       = { row = 13, frames = 15 },
    sleep_right    = { row = 14, frames = 9 },
    sleep_left     = { row = 15, frames = 9 },
    eat_right      = { row = 16, frames = 9 },
    eat_left       = { row = 17, frames = 9 },
}

--------------------------------------------------
-- 初始化
--------------------------------------------------

if not _G._goose then

    math.randomseed(os.time())

    _G._goose = {
        x = math.floor(sys.screen_width() / 2),
        y = math.floor(sys.screen_height() / 2),

        vx = 0,
        vy = 0,

        dir = 1,

        state = "idle",
        state_timer = 0,

        frame_counter = 0,
    }
end

local g = _G._goose

--------------------------------------------------
-- 屏幕
--------------------------------------------------

local sw = sys.screen_width()
local sh = sys.screen_height()

local mx = sys.mouse_x()
local my = sys.mouse_y()

--------------------------------------------------
-- 参数
--------------------------------------------------

local walk_speed = 2
local run_speed = 5

--------------------------------------------------
-- 状态更新
--------------------------------------------------

g.state_timer = (g.state_timer or 0) + 1
g.frame_counter = (g.frame_counter or 0) + 1

--------------------------------------------------
-- idle
--------------------------------------------------

if g.state == "idle" then

    g.vx = 0
    g.vy = 0

    if g.state_timer > 60 then

        local r = math.random(100)

        if r <= 45 then

            local angle = math.random() * math.pi * 2

            g.vx = math.cos(angle) * walk_speed
            g.vy = math.sin(angle) * walk_speed

            g.state = "walk"

        elseif r <= 65 then

            g.state = "peck"

        elseif r <= 80 then

            g.state = "sleep"

        elseif r <= 100 then

            g.state = "chase"

        end

        g.state_timer = 0
    end

elseif g.state == "walk" then

    if g.state_timer > 80 then
        g.state = "idle"
        g.state_timer = 0
    end

elseif g.state == "peck" then

    g.vx = 0
    g.vy = 0

    if g.state_timer > 30 then
        g.state = "idle"
        g.state_timer = 0
    end

elseif g.state == "sleep" then

    g.vx = 0
    g.vy = 0

    if g.state_timer > 100 then
        g.state = "idle"
        g.state_timer = 0
    end

elseif g.state == "chase" then

    local dx = mx - g.x
    local dy = my - g.y

    local dist = math.sqrt(dx * dx + dy * dy)

    if dist > 10 then

        g.vx = dx / dist * run_speed
        g.vy = dy / dist * run_speed

    else

        g.vx = 0
        g.vy = 0
    end

    if dist < 30 or g.state_timer > 120 then

        g.state = "idle"
        g.state_timer = 0
    end
end

--------------------------------------------------
-- 更新位置
--------------------------------------------------

g.x = g.x + g.vx
g.y = g.y + g.vy

--------------------------------------------------
-- 屏幕边界
--------------------------------------------------

if g.x < 0 then
    g.x = 0
    g.vx = -g.vx
end

if g.y < 0 then
    g.y = 0
    g.vy = -g.vy
end

if g.x > sw - goose_w then
    g.x = sw - goose_w
    g.vx = -g.vx
end

if g.y > sh - goose_h then
    g.y = sh - goose_h
    g.vy = -g.vy
end

--------------------------------------------------
-- 朝向
--------------------------------------------------

if g.vx > 0.1 then
    g.dir = 1
elseif g.vx < -0.1 then
    g.dir = -1
end

--------------------------------------------------
-- 动画选择
--------------------------------------------------

local anim

if g.state == "walk" then

    anim = g.dir > 0 and ANIM.walk_right or ANIM.walk_left

elseif g.state == "chase" then

    anim = g.dir > 0 and ANIM.fly_right or ANIM.fly_left

elseif g.state == "sleep" then

    anim = g.dir > 0 and ANIM.sleep_right or ANIM.sleep_left

elseif g.state == "peck" then

    anim = g.dir > 0 and ANIM.eat_right or ANIM.eat_left

else

    anim = g.dir > 0 and ANIM.sit_right or ANIM.sit_left

end

--------------------------------------------------
-- 当前帧
--------------------------------------------------

local frame = math.floor(g.frame_counter / 4) % anim.frames

local sx = frame * frame_w
local sy = anim.row * frame_h

--------------------------------------------------
-- 状态文字
--------------------------------------------------

local state_text = {
    idle = "发呆",
    walk = "散步",
    chase = "追鼠标",
    peck = "啄地",
    sleep = "睡觉"
}

local bar = font(
    state_text[g.state] or "",
    "#FFFFFF",
    9
)

--------------------------------------------------
-- 显示鹅
--------------------------------------------------

local goose = dialog({
    title = "Goose",
    width = goose_w,
    height = goose_h,

    x = math.floor(g.x),
    y = math.floor(g.y),

    borderless = true,
    transparent_bg = true,
    opacity = 255,

    refresh = 50,

    content = {
        {
            type = "image",
            source = sprite_sheet,

            src_x = sx,
            src_y = sy,
            src_w = frame_w,
            src_h = frame_h,

            width = goose_w,
            height = goose_h
        }
    }
})

return bar, true, goose