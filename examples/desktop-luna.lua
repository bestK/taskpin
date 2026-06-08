-- desktop-luna.lua
-- @name Desktop Luna
-- @realtime
-- @bar_width 100
-- @require 1.4.0

local sprite_walk   = "sprite-sheet/luna/walk.png"
local sprite_attack = "sprite-sheet/luna/attack.png"

local SHEET_SIZE = 1254
local COLS = 5
local ROWS = 5
local FRAME_SIZE = math.floor(SHEET_SIZE / COLS)

local luna_w = 250
local luna_h = 250

--------------------------------------------------
-- 动画定义
-- walk.png rows:
--   0: ↖ 左上行走
--   1: ↑  正上行走
--   2: ↗ 右上行走
--   3: ← 左行走
--   4: → 右行走
-- attack.png rows:
--   0: 举杖蓄力
--   1: 突刺
--   2: 魔法弧波
--   3: 魔法盾
--   4: 杖旋 + 射线
--------------------------------------------------

local ANIM = {
    idle        = { sheet = "walk",   row = 1, frames = 5, speed = 6 },
    walk_left   = { sheet = "walk",   row = 3, frames = 5, speed = 4 },
    walk_right  = { sheet = "walk",   row = 4, frames = 5, speed = 4 },
    walk_up     = { sheet = "walk",   row = 1, frames = 5, speed = 4 },
    walk_ul     = { sheet = "walk",   row = 0, frames = 5, speed = 4 },
    walk_ur     = { sheet = "walk",   row = 2, frames = 5, speed = 4 },
    atk_thrust = { sheet = "attack", row = 1, frames = 5, speed = 3 },
    atk_wave   = { sheet = "attack", row = 2, frames = 5, speed = 3 },
    atk_shield = { sheet = "attack", row = 3, frames = 5, speed = 3 },
    atk_spin   = { sheet = "attack", row = 4, frames = 5, speed = 3 },
}

--------------------------------------------------
-- 初始化
--------------------------------------------------

if not _G._luna then
    math.randomseed(os.time())
    _G._luna = {
        x = math.floor(sys.screen_width() / 2),
        y = math.floor(sys.screen_height() / 2),
        vx = 0,
        vy = 0,
        state = "idle",
        state_timer = 0,
        frame_tick = 0,
        atk_index = 1,
    }
end

local L = _G._luna

local sw = sys.screen_width()
local sh = sys.screen_height()
local mx = sys.mouse_x()
local my = sys.mouse_y()

local walk_speed = 2.5
local run_speed  = 5

--------------------------------------------------
-- 状态机
--------------------------------------------------

L.state_timer = L.state_timer + 1
L.frame_tick  = L.frame_tick + 1

if L.state == "idle" then
    L.vx = 0
    L.vy = 0
    if L.state_timer > 40 then
        local r = math.random(100)
        if r <= 30 then
            local angle = math.random() * math.pi * 2
            L.vx = math.cos(angle) * walk_speed
            L.vy = math.sin(angle) * walk_speed
            L.state = "walk"
        elseif r <= 50 then
            L.state = "chase"
        elseif r <= 90 then
            L.state = "attack"
            L.atk_index = math.random(4)
            L.atk_start_tick = L.frame_tick
        else
            -- 继续 idle
        end
        L.state_timer = 0
    end

elseif L.state == "walk" then
    if L.state_timer > 90 then
        L.state = "idle"
        L.state_timer = 0
    end

elseif L.state == "chase" then
    local dx = mx - (L.x + luna_w / 2)
    local dy = my - (L.y + luna_h / 2)
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist > 10 then
        L.vx = dx / dist * run_speed
        L.vy = dy / dist * run_speed
    else
        L.vx = 0
        L.vy = 0
    end
    if dist < 40 or L.state_timer > 130 then
        L.state = "idle"
        L.state_timer = 0
    end

elseif L.state == "attack" then
    L.vx = 0
    L.vy = 0
    local elapsed = L.frame_tick - (L.atk_start_tick or 0)
    if elapsed >= 5 * 3 then
        L.state = "idle"
        L.state_timer = 0
    end
end

--------------------------------------------------
-- 位置更新 + 屏幕约束
--------------------------------------------------

L.x = L.x + L.vx
L.y = L.y + L.vy

if L.x < 0 then L.x = 0; L.vx = -L.vx end
if L.y < 0 then L.y = 0; L.vy = -L.vy end
if L.x > sw - luna_w then L.x = sw - luna_w; L.vx = -L.vx end
if L.y > sh - luna_h then L.y = sh - luna_h; L.vy = -L.vy end

--------------------------------------------------
-- 动画选择
--------------------------------------------------

local anim

if L.state == "attack" then
    local atk_names = { "atk_thrust", "atk_wave", "atk_shield", "atk_spin" }
    anim = ANIM[atk_names[L.atk_index]]
elseif L.state == "walk" or L.state == "chase" then
    local ax = math.abs(L.vx)
    local ay = math.abs(L.vy)
    if ay > ax * 1.5 then
        anim = ANIM.walk_up
    elseif ax > ay * 1.5 then
        anim = L.vx > 0 and ANIM.walk_right or ANIM.walk_left
    else
        if L.vy < 0 then
            anim = L.vx > 0 and ANIM.walk_ur or ANIM.walk_ul
        else
            anim = L.vx > 0 and ANIM.walk_right or ANIM.walk_left
        end
    end
else
    anim = ANIM.idle
end

--------------------------------------------------
-- 帧计算
--------------------------------------------------

local frame
if L.state == "attack" then
    local elapsed = L.frame_tick - (L.atk_start_tick or 0)
    frame = math.min(math.floor(elapsed / anim.speed), anim.frames - 1)
else
    frame = math.floor(L.frame_tick / anim.speed) % anim.frames
end
local sx = frame * FRAME_SIZE
local sy = anim.row * FRAME_SIZE

local sheet = anim.sheet == "attack" and sprite_attack or sprite_walk

--------------------------------------------------
-- 状态栏
--------------------------------------------------

local state_label = {
    idle = "待机",
    walk = "漫步",
    chase = "追踪",
    attack = "施法",
}

local bar = font(state_label[L.state] or "", "#C8A2E8", 9)

--------------------------------------------------
-- 渲染
--------------------------------------------------

local luna = dialog({
    title = "Luna",
    width = luna_w,
    height = luna_h,
    x = math.floor(L.x),
    y = math.floor(L.y),
    borderless = true,
    transparent_bg = true,
    opacity = 255,
    refresh = 50,
    content = {
        {
            type = "image",
            source = sheet,
            src_x = sx,
            src_y = sy,
            src_w = FRAME_SIZE,
            src_h = FRAME_SIZE,
            width = luna_w,
            height = luna_h,
        }
    }
})

return bar, true, luna