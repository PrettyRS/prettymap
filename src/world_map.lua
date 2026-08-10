local tileData = require("data/map_tiles")

local WorldMap = {
    id = -1,
    name = "Complete RuneScape map",
    width = 12800,
    height = 12800,
    minX = 0,
    minZ = 0,
    maxX = 12800,
    maxZ = 12800,
    levels = tileData.levels,
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

function WorldMap.Get()
    return WorldMap
end

function WorldMap.Contains(x, z, level)
    return x >= WorldMap.minX and x < WorldMap.maxX
        and z >= WorldMap.minZ and z < WorldMap.maxZ
        and (level == nil or (level >= 0 and level <= 3))
end

function WorldMap.ToPixel(x, z, width, height, _, level)
    if not WorldMap.Contains(x, z, level) then return nil, nil end
    width = width or WorldMap.width
    height = height or WorldMap.height
    return (x - WorldMap.minX) * width / WorldMap.width,
        (WorldMap.maxZ - z - 1) * height / WorldMap.height
end

function WorldMap.FromPixel(pixelX, pixelY, width, height, _, level)
    width = width or WorldMap.width
    height = height or WorldMap.height
    if pixelX < 0 or pixelY < 0 or pixelX >= width or pixelY >= height then
        return nil, nil, nil
    end
    local x = math.floor(WorldMap.minX + pixelX * WorldMap.width / width)
    local z = math.floor(WorldMap.maxZ - pixelY * WorldMap.height / height - 1)
    return clamp(x, WorldMap.minX, WorldMap.maxX - 1),
        clamp(z, WorldMap.minZ, WorldMap.maxZ - 1),
        level or 0
end

function WorldMap.LevelForScale(scale)
    local best = WorldMap.levels[1]
    local bestDistance = math.huge
    for _, level in ipairs(WorldMap.levels) do
        local distance = math.abs(math.log(scale / level.nativeScale))
        if distance < bestDistance then
            best = level
            bestDistance = distance
        end
    end
    return best
end

return WorldMap
