package.path = "./?.lua;./?/init.lua;" .. package.path

local loadCount = 0
local unloadCount = 0
local image = {
    Load = function()
        loadCount = loadCount + 1
        return "success"
    end,
    Unload = function()
        unloadCount = unloadCount + 1
    end,
    path = "resources/maps/example.png",
}

Plugin = { resources = { ["world_map.png"] = image } }
local Resources = require("src/resources")
assert(Resources.WorldMap() == image)
assert(loadCount == 1, "the map image should be explicitly loaded")
Resources.Unload(image)
assert(unloadCount == 1)

Plugin.resources = { images = { world_map = image } }
assert(Resources.WorldMap() == image, "nested image resources should be supported")
Resources.Unload(image)

Plugin.resources = { maps = { z3 = { tile_2_4 = image } } }
assert(Resources.Image("maps/z3/tile_2_4.png") == image,
    "deeply nested map tiles should be supported")
Resources.Unload(image)

local iconImage = {
    Load = function() return "success" end,
    path = "resources/map_icons/z3/icon_0_2_4.png",
}
Plugin.resources = {
    maps = { z3 = { ["0_2_4"] = image } },
    map_icons = { z3 = { icon_0_2_4 = iconImage } },
}
assert(Resources.Image("map_icons/z3/icon_0_2_4.png") == iconImage,
    "icon resources should resolve independently from same-coordinate base tiles")
Resources.Unload(iconImage)

local failedImage = {
    Load = function() return "errorDecode" end,
    path = "resources/maps/z3/broken.png",
}
Plugin.resources = { maps = { z3 = { broken = failedImage } } }
local failedResource, loadError = Resources.Image("maps/z3/broken.png")
assert(failedResource == nil and loadError:find("errorDecode", 1, true),
    "failed image loads should return the documented failure result")

Plugin.resources = {
    maps = {
        z1 = { ["0_0_4"] = image },
        z3 = {},
    },
}
local missingResource, missingError = Resources.Image("maps/z3/0_0_4.png")
assert(missingResource == nil and missingError:find("not found", 1, true),
    "a missing tile must not fall back to a same-named tile in another folder")

local sharedLoadCount, sharedUnloadCount = 0, 0
local shared = {
    Load = function() sharedLoadCount = sharedLoadCount + 1 return "success" end,
    Unload = function() sharedUnloadCount = sharedUnloadCount + 1 end,
    path = "resources/maps/z1/shared.png",
}
Plugin.resources = { first = shared, second = shared }
assert(Resources.Image("first.png") == shared)
assert(Resources.Image("second.png") == shared)
assert(sharedLoadCount == 1,
    "canonical aliases should load their shared image handle once")
Resources.Unload(shared)
assert(sharedUnloadCount == 0,
    "a shared image should remain loaded while another alias owns it")
Resources.Unload(shared)
assert(sharedUnloadCount == 1,
    "a shared image should unload after its final reference is released")

Plugin.resources = {}
assert(Resources.WorldMap() == nil, "a missing image should not throw")

print("resource loading tests passed")
