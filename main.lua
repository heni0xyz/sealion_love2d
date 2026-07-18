local Multiplier = 50
local VIRTUAL_H = 512
local COLUMN_W = 640
local scale = 1
local visibleW = 640
local columnOffsetX = 0

local function recalcScale()
    local realW, realH = love.graphics.getDimensions()
    scale = realH / VIRTUAL_H
    visibleW = realW / scale
    columnOffsetX = (visibleW - COLUMN_W) / 2
end

function love.resize(w, h)
    recalcScale()
end

local function drawTiled(image, y, startX, endX, offset)
    offset = offset or 0
    local iw = image:getWidth()
    local firstX = math.floor((startX - offset) / iw) * iw + offset
    for tx = firstX, endX, iw do
        love.graphics.draw(image, tx, y)
    end
end

local font
local sealion, sealion_eat, player
local grass, background, clouds, orange, bomb
local points = 0
local speed = 5 * Multiplier
local cloudSpeed = 0.2 * Multiplier
local x, y = 160, 352
local cloudX = 0
local food = {}

local spawnTimer = 0
local spawnInterval = 2

local eatTimer = nil
local eatDuration = 0.5

local joystick = nil

local function getJoystick()
    if not love.joystick then return nil end
    local list = love.joystick.getJoysticks()
    return list[1]
end

local function rumble(big, small)
    if not joystick then return end
    pcall(function() joystick:setVibration(big / 255, small / 255) end)
end

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
    local foodX = math.random(0, COLUMN_W - 64)
    local foodSpeed = math.random(3, 4) * Multiplier

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
    if isMoveLeft() then
        x = math.max(0, x - speed * dt)
    end
    if isMoveRight() then
        x = math.min(COLUMN_W - 160, x + speed * dt)
    end

    spawnTimer = spawnTimer + dt
    if spawnTimer >= spawnInterval then
        spawnFood()
        spawnTimer = 0
    end

    cloudX = cloudX + cloudSpeed * dt
    local cloudsW = clouds:getWidth()
    if cloudX >= cloudsW then
        cloudX = cloudX - cloudsW
    end

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

    if eatTimer then
        eatTimer = eatTimer + dt
        if eatTimer >= eatDuration then
            player = sealion
            rumble(0, 0)
            eatTimer = nil
        end
    end
end

function love.draw(screen)
    if screen == "bottom" then
        love.graphics.clear(0, 0, 0)
        return
    end

    recalcScale()

    love.graphics.push()
    love.graphics.scale(scale, scale)

    drawTiled(background, 0, 0, visibleW)

    local pw, ph = player:getDimensions()
    love.graphics.draw(player, columnOffsetX + x, y, 0, 160 / pw, 160 / ph)

    love.graphics.print("Points: " .. points, 10, 10)
    if player == sealion_eat then
        local yummyX = math.min(columnOffsetX + x + 160, visibleW - 80)
        love.graphics.print("yummy!", yummyX, y)
    end

    drawTiled(clouds, 0, 0, visibleW, cloudX)

    for _, v in ipairs(food) do
        love.graphics.draw(v.item, columnOffsetX + v.x, v.y)
    end

    love.graphics.draw(grass, columnOffsetX, 448)

    love.graphics.pop()
end