--[[
  Ported from Enceladus (PS2 homebrew Lua) to LOVE2D.

  Original used a single `while true do ... Screen.flip() end` loop that ran
  once per PAL vblank (~50Hz). LOVE2D instead calls love.load() once,
  then love.update(dt) and love.draw() every frame at whatever framerate
  the machine achieves. To keep gameplay speed identical regardless of
  framerate, every "per frame" constant from the original (speed, cloudSpeed,
  food fall speed) has been converted to a "per second" value (multiplied
  by the original ~50fps PAL refresh rate) and is now scaled by dt.

  Put your original image assets (SL.png, SL2.png, GRASS.PNG, BG.PNG,
  CLOUDS.PNG, ORANGE.PNG, BOMB.PNG) in the same folder as this file.
  NOTE: LOVE2D on Linux/macOS is case-sensitive about filenames - make sure
  the actual files match the case used below exactly.
--]]

local PAL_FPS = 50 -- original fixed vblank rate, used to convert old per-frame values to per-second

--[[
  RESOLUTION SCALING
  All game logic below still uses the original 640x512 coordinate space
  (so collision boxes, the grass y=448 placement, etc. all keep working
  unmodified). At draw time we stretch that 640x512 "virtual screen" to
  completely fill whatever the real screen size is - 800x240 (3DS top
  screen 3D framebuffer), 400x240 (3DS top screen 2D), a desktop window,
  or anything else. This is a full stretch (separate X/Y scale factors),
  NOT an aspect-preserving letterbox, so there are no black bars and the
  whole framebuffer is always used - the image will look squashed/stretched
  on screens with a very different aspect ratio than 640x512, since nothing
  is cropped or padded.
--]]
local VIRTUAL_W, VIRTUAL_H = 640, 512
local scaleX, scaleY = 1, 1

local function recalcScale()
    local realW, realH = love.graphics.getDimensions()
    scaleX = realW / VIRTUAL_W
    scaleY = realH / VIRTUAL_H
end

-- Fires on desktop LOVE when the window is resized. Not guaranteed to fire
-- on console, so love.load() also calls recalcScale() once directly.
function love.resize(w, h)
    recalcScale()
end

-- assets / state (populated in love.load)
local font
local sealion, sealion_eat, player
local grass, background, clouds, orange, bomb
local points = 0
local speed = 5 * PAL_FPS       -- was 5 px/frame -> 250 px/sec
local cloudSpeed = 0.2 * PAL_FPS -- was 0.2 px/frame -> 10 px/sec
local x, y = 160, 352
local cloudX = 0
local food = {}

local spawnTimer = 0      -- counts up in seconds, replaces Timer.new()/getTime()
local spawnInterval = 2   -- was 2000000 microseconds = 2 seconds

local eatTimer = nil      -- replaces timer2; nil when not active
local eatDuration = 0.5   -- was 500000 microseconds = 0.5 seconds

-- joystick reference for rumble (Pads.rumble equivalent)
local joystick = nil

local function getJoystick()
    if not love.joystick then return nil end
    local list = love.joystick.getJoysticks()
    return list[1]
end

-- Enceladus: Pads.rumble(0, 255, 255) uses big/small motor 0-255 amplitude
-- LOVE2D: joystick:setVibration(left, right, [duration]) expects 0-1 floats
-- Wrapped in pcall: not every device/console has a vibration motor
-- (original 3DS has none; New 3DS only via the Rumble Pak accessory).
local function rumble(big, small)
    if not joystick then return end
    pcall(function() joystick:setVibration(big / 255, small / 255) end)
end

-- The 3DS has no physical keyboard, so movement checks both keyboard
-- (for desktop LOVE testing) and gamepad D-Pad/Circle Pad (for LOVE Potion
-- on console). LOVE Potion maps 3DS buttons through love.joystick as a
-- standard gamepad ("dpleft"/"dpright"); double check LOVE Potion's current
-- input docs if these names don't match what you see on your build.
local function isMoveLeft()
    if love.keyboard and love.keyboard.isDown and love.keyboard.isDown("left", "a") then
        return true
    end
    if joystick then
        local ok, down = pcall(function() return joystick:isGamepadDown("dpleft") end)
        if ok and down then return true end
    end
    return false
end

local function isMoveRight()
    if love.keyboard and love.keyboard.isDown and love.keyboard.isDown("right", "d") then
        return true
    end
    if joystick then
        local ok, down = pcall(function() return joystick:isGamepadDown("dpright") end)
        if ok and down then return true end
    end
    return false
end

local function spawnFood()
    local availableFood = {
        { food = orange, value = 50 },
        { food = bomb,   value = -100 },
    }
    local chosenFood = availableFood[math.random(1, #availableFood)]
    local foodX = math.random(0, 576)
    local foodSpeed = math.random(3, 4) * PAL_FPS -- was 3-4 px/frame -> per second

    table.insert(food, {
        item = chosenFood.food,
        x = foodX,
        y = 0,
        speed = foodSpeed,
        value = chosenFood.value,
    })
end

local function givePoint(amount)
    if amount < 0 then
        rumble(255, 255)
    else
        rumble(255, 0)
    end
    points = points + amount
end

function love.load()
    love.window.setTitle("Sealion Game")
    math.randomseed(os.time())

    joystick = getJoystick()

    -- Font.fmLoad() -> use LOVE2D's built-in default font at a reasonable size
    font = love.graphics.newFont(16)
    love.graphics.setFont(font)

    sealion     = love.graphics.newImage("sl.png")
    sealion_eat = love.graphics.newImage("sl2.png")
    player      = sealion

    grass      = love.graphics.newImage("grass.png")
    background = love.graphics.newImage("bg.png")
    clouds     = love.graphics.newImage("clouds.png")
    orange     = love.graphics.newImage("orange.png")
    bomb       = love.graphics.newImage("bomb.png")

    recalcScale()
end

function love.update(dt)
    -- Pads.check(pad, PAD_LEFT / PAD_RIGHT) -> keyboard/gamepad equivalent
    if isMoveLeft() then
        x = math.max(0, x - speed * dt)
    end
    if isMoveRight() then
        x = math.min(480, x + speed * dt)
    end

    -- food spawn timer (replaces Timer.new()/Timer.getTime())
    spawnTimer = spawnTimer + dt
    if spawnTimer >= spawnInterval then
        spawnFood()
        spawnTimer = 0
    end

    -- cloud scroll
    cloudX = cloudX + cloudSpeed * dt
    if cloudX >= 640 then
        cloudX = 0
    end

    -- falling food + collision
    for i = #food, 1, -1 do
        local v = food[i]
        v.y = v.y + v.speed * dt

        local pw, ph = 160, 160
        local fw, fh = 64, 64

        if v.x < x + pw and v.x + fw > x and v.y < y + ph - 32 and v.y + fh > y + 32 then
            givePoint(v.value)
            player = sealion_eat
            eatTimer = 0
            table.remove(food, i)
        elseif v.y >= 512 then
            table.remove(food, i)
        end
    end

    -- "yummy" face timer (replaces timer2)
    if eatTimer then
        eatTimer = eatTimer + dt
        if eatTimer >= eatDuration then
            player = sealion
            rumble(0, 0)
            eatTimer = nil
        end
    end
end

function love.draw()
    love.graphics.push()
    love.graphics.scale(scaleX, scaleY)

    -- Everything from here down is drawn in the original 640x512
    -- coordinate space, unchanged from the original PS2 code's math.
    love.graphics.draw(background, 0, 0)

    -- Graphics.drawScaleImage(player, x, y, 160, 160) scaled the sprite to a
    -- 160x160 box; LOVE2D draw() takes scale multipliers, not target pixel
    -- sizes, so we compute the multiplier from the image's real dimensions.
    local pw, ph = player:getDimensions()
    love.graphics.draw(player, x, y, 0, 160 / pw, 160 / ph)

    love.graphics.print("Points: " .. points, 10, 10)
    if player == sealion_eat then
        love.graphics.print("yummy!", math.min(x + 160, 560), y)
    end

    love.graphics.draw(clouds, cloudX - 640, 0)
    love.graphics.draw(clouds, cloudX, 0)

    for _, v in ipairs(food) do
        love.graphics.draw(v.item, v.x, v.y)
    end

    love.graphics.draw(grass, 0, 448)

    love.graphics.pop()
end