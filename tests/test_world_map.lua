package.path = "./?.lua;./?/init.lua;" .. package.path

local WorldMap = require("src/world_map")

local function close(actual, expected, tolerance, message)
    assert(math.abs(actual - expected) <= tolerance,
        string.format("%s: expected %s, got %s", message, expected, actual))
end

assert(WorldMap.id == -1 and WorldMap.width == 12800 and WorldMap.height == 12800)
assert(WorldMap.Contains(3200, 3200, 0))
assert(WorldMap.Contains(12000, 11000, 3))
assert(not WorldMap.Contains(-1, 3200, 0))
assert(not WorldMap.Contains(3200, 12800, 0))
assert(not WorldMap.Contains(3200, 3200, 4))

local pixelX, pixelY = WorldMap.ToPixel(3200, 9600)
local worldX, worldZ, level = WorldMap.FromPixel(pixelX, pixelY, nil, nil, nil, 2)
close(worldX, 3200, 1, "x round trip")
close(worldZ, 9600, 1, "z round trip")
assert(level == 2)

assert(WorldMap.LevelForScale(0.04).folder == "z1",
    "scales below the supported zoom range should reuse the smallest retained level")
assert(WorldMap.LevelForScale(0.5).folder == "z1")
assert(WorldMap.LevelForScale(2).folder == "z1")
assert(WorldMap.LevelForScale(8).folder == "z3")

local invalidX, invalidZ = WorldMap.FromPixel(-1, 0)
assert(invalidX == nil and invalidZ == nil)

print("world map coordinate tests passed")
