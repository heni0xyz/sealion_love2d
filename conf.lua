-- conf.lua
--
-- This only controls the DESKTOP LOVE window (useful for testing on your
-- PC before deploying to the 3DS). On real 3DS hardware, LÖVE Potion uses
-- the console's actual fixed resolution instead - it doesn't read
-- t.window.width/height. main.lua handles that difference itself: it
-- reads the real screen size at runtime (love.graphics.getDimensions())
-- and scales the game to fit, whether that's 640x512 on your desktop,
-- 800x240, 400x240, or anything else.
--
-- Feel free to set width/height below to whatever you want to preview at
-- on desktop - try 800, 240 to preview the 3DS top-screen 3D framebuffer
-- size, or 400, 240 for the plain 2D top screen size.

function love.conf(t)
    t.window.title = "Sealion Game (LOVE2D port)"
    t.window.width = 640
    t.window.height = 512
    t.window.resizable = true -- resizable on desktop so you can test different target sizes live
    t.console = false -- set true on Windows if you want a debug console
end