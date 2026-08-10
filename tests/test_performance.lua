package.path = "./?.lua;./?/init.lua;" .. package.path

local subscriptions, unsubscriptions = 0, 0
local logicCallbacks = {}
Event = { Logic = {
    Subscribe = function(name, callback)
        subscriptions = subscriptions + 1
        logicCallbacks[name] = callback
    end,
    Unsubscribe = function(name)
        unsubscriptions = unsubscriptions + 1
        logicCallbacks[name] = nil
    end,
} }
local playerReads = 0
local trackedPlayer = { isValid = true, coordGrid = { x = 3200, z = 3200, level = 0 } }
Player = {
    IsAvailable = function() return true end,
    GetEntity = function() playerReads = playerReads + 1 return trackedPlayer end,
}
World = {
    IsAvailable = function() return true end,
    IsRegion = function() return false end,
}
CoordGrid = {
    new = function(level, mapSquareX, mapSquareZ, localX, localZ)
        return {
            x = mapSquareX * 64 + localX,
            z = mapSquareZ * 64 + localZ,
            level = level,
        }
    end,
}

local loads, unloads = 0, 0
package.loaded["src/resources"] = {
    Image = function(name) loads = loads + 1 return { name = name } end,
    Unload = function() unloads = unloads + 1 end,
}

local mutations, destroys, restacks = 0, 0, 0
local function component()
    local value = { scrollX = 0, scrollY = 0 }
    function value:SetPos(x, y) self.x, self.y = x, y mutations = mutations + 1 end
    function value:SetSize(w, h) self.width, self.height = w, h mutations = mutations + 1 end
    function value:SetScrollSize(w, h) self.scrollWidth, self.scrollHeight = w, h mutations = mutations + 1 end
    function value:SetScrollPos(x, y) self.scrollX, self.scrollY = x, y mutations = mutations + 1 end
    function value:Subscribe(hook, callback) self[hook] = callback end
    function value:MoveToFront() restacks = restacks + 1 end
    function value:Destroy() self.destroyed = true destroys = destroys + 1 end
    function value:Clear() self.sprites = {} end
    function value:AddOutline() end
    function value:AddSprite(...) self.sprites = self.sprites or {} self.sprites[#self.sprites + 1] = {...} end
    return value
end
ui = {
    Hook = { ONCLICK = "click", ONHOLD = "hold", ONRELEASE = "release",
        ONDRAGCOMPLETE = "dragcomplete", ONSCROLLWHEEL = "wheel",
        ONMOUSEOVER = "mouseover", ONMOUSELEAVE = "mouseleave" },
    Layer = { new = component }, Rectangle = { new = component },
    Sprite = { new = component }, Canvas = { new = component }, Text = { new = component },
    AlignMode = { CENTRE = 1 },
}
id = {
    Sprite = setmetatable({ YOU_ARE_HERE_ICON_0 = 1, YOU_ARE_HERE_ICON_1 = 2,
        YOU_ARE_HERE_ICON_2 = 3 }, { __index = function(_, key) return key end }),
    Font = { MUSEO_SANS_15PT_REGULAR = 1 },
}

local MapView = require("src/map")
local TileRenderer = require("src/tile_renderer")
local first = MapView.new(component(), { width = 516, height = 434 })
local currentZoom = first:GetZoom()
local beforeLoads, beforeUnloads = loads, unloads
local beforeMutations, beforeDestroys = mutations, destroys
assert(first:SetZoom(currentZoom) == false)
assert(loads == beforeLoads and unloads == beforeUnloads
    and mutations == beforeMutations and destroys == beforeDestroys,
    "setting the current zoom must perform no resource or component mutations")
first:SetZoom(999)
beforeLoads, beforeUnloads = loads, unloads
beforeMutations, beforeDestroys = mutations, destroys
assert(first:SetZoom(999) == false)
assert(loads == beforeLoads and unloads == beforeUnloads
    and mutations == beforeMutations and destroys == beforeDestroys,
    "a zoom request clamped at the maximum must be a no-op")
first:SetZoom(-999)
beforeLoads, beforeUnloads = loads, unloads
beforeMutations, beforeDestroys = mutations, destroys
assert(first:SetZoom(-999) == false)
assert(loads == beforeLoads and unloads == beforeUnloads
    and mutations == beforeMutations and destroys == beforeDestroys,
    "a zoom request clamped at the minimum must be a no-op")

-- Cache completion independently from image availability.
for key in pairs(first.tileSprites) do first.tileSprites[key] = nil end
first.imageAvailable = false
local reconciliations = first.tileReconciliationCount
TileRenderer._RefreshTiles(first)
assert(first.tileReconciliationCount == reconciliations,
    "an unchanged tileless viewport must not reconcile repeatedly")

first.player:SetShowPlayerMarker(true)
local second = MapView.new(component(), { width = 516, height = 434, showPlayerMarker = true })
assert(subscriptions == 1 and first.trackingEventID == second.trackingEventID,
    "multiple maps must share one player logic subscription")
local readsBeforeTick = playerReads
logicCallbacks[first.trackingEventID]()
assert(playerReads == readsBeforeTick + 1,
    "the shared dispatcher must read the player only once per logic tick")
assert(restacks == 0,
    "stable parent layers must avoid runtime z-order reconstruction")
first:Destroy()
assert(unsubscriptions == 0 and logicCallbacks[second.trackingEventID],
    "destroying one map must retain the shared player subscription")
second:Destroy()
assert(unsubscriptions == 1 and next(logicCallbacks) == nil,
    "destroying the final interested map must unsubscribe the dispatcher")

print("map performance regression tests passed")
