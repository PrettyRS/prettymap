local WorldMap = require("src/world_map")
local Helpers = require("src/map_helpers")

local PlayerTracking = {}
local PLAYER_MARKER_SIZE = 32
local PLAYER_MARKER_OFFSET = PLAYER_MARKER_SIZE / 2
local INSTANCE_ZONE_SIZE = 8
local DISPATCHER_ID = "prettymap_player_updates"
local interestedMaps = {}
local dispatcherSubscribed = false

local function playerMapCoordinate(coordinate)
    if not World.IsAvailable() or not World.IsRegion() then
        return coordinate
    end
    local source = World.GetRegionSourceForCoordGrid(coordinate)
    if not source then
        return coordinate
    end
    return Helpers.NewCoordGrid(
        source.x + (coordinate.x % INSTANCE_ZONE_SIZE),
        source.z + (coordinate.z % INSTANCE_ZONE_SIZE),
        source.level)
end

local function readPlayerCoordinate()
    if not Player.IsAvailable() then return nil end
    local player = Player.GetEntity()
    local coordinate = player and player.isValid and player.coordGrid or nil
    if not coordinate then return nil end
    return playerMapCoordinate(coordinate)
end

local function dispatchPlayerUpdate()
    local coordinate = readPlayerCoordinate()
    for map in pairs(interestedMaps) do
        if map.root then
            local moved = not Helpers.CoordGridsEqual(map.playerCoordinate, coordinate)
            if coordinate == nil then
                PlayerTracking.ClearPlayerPosition(map)
            else
                PlayerTracking.SetPlayerPosition(map, coordinate)
            end
            if map.trackPlayer and moved and coordinate then map:ShowCoordinate(coordinate) end
        end
    end
end

function PlayerTracking:_DrawPlayer()
    if not self.playerMarker then return end
    self.playerMarker:Clear()
    local coordinate = self.playerCoordinate
    if not self.showPlayerMarker or not coordinate or coordinate.level ~= self.plane then return end
    local pixelX, pixelY = WorldMap.ToPixel(
        coordinate.x, coordinate.z, self.mapWidth, self.mapHeight, WorldMap, coordinate.level)
    if not pixelX then return end
    local x = Helpers.Rounded(self.mapOffsetX + pixelX)
    local y = Helpers.Rounded(self.mapOffsetY + pixelY)
    self.playerMarker:AddSprite(
        x - PLAYER_MARKER_OFFSET,
        y - PLAYER_MARKER_OFFSET,
        PLAYER_MARKER_SIZE,
        PLAYER_MARKER_SIZE,
        id.Sprite.YOU_ARE_HERE_ICON_0,
        0xFFFFFFFF
    )
end

function PlayerTracking:SetPlayerPosition(coordinate)
    local x, z, level = Helpers.CoordGridValues(coordinate)
    local current = self.playerCoordinate
    if current and current.x == x and current.z == z and current.level == level then return end
    self.playerCoordinate = Helpers.NewCoordGrid(x, z, level)
    self:_RefreshView("player_position")
end

function PlayerTracking:ClearPlayerPosition()
    if not self.playerCoordinate then return end
    self.playerCoordinate = nil
    self:_RefreshView("player_position")
end

function PlayerTracking:SetShowPlayerMarker(visible)
    self.showPlayerMarker = visible == true
    PlayerTracking._RefreshPlayerUpdates(self)
    self:_RefreshView("player_position")
end

function PlayerTracking:GetShowPlayerMarker()
    return self.showPlayerMarker
end

function PlayerTracking:_UpdateTrackedPlayer()
    local coordinate = readPlayerCoordinate()
    if coordinate == nil then
        PlayerTracking.ClearPlayerPosition(self)
        return false
    end
    local moved = not Helpers.CoordGridsEqual(self.playerCoordinate, coordinate)
    PlayerTracking.SetPlayerPosition(self, coordinate)
    if self.trackPlayer and moved then self:ShowCoordinate(coordinate) end
    return true
end

function PlayerTracking:_RefreshPlayerUpdates()
    local needsUpdates = self.showPlayerMarker or self.trackPlayer
    if needsUpdates and not interestedMaps[self] then
        interestedMaps[self] = true
        self.trackingEventID = DISPATCHER_ID
        if not dispatcherSubscribed then
            Event.Logic.Subscribe(DISPATCHER_ID, dispatchPlayerUpdate)
            dispatcherSubscribed = true
        end
    elseif not needsUpdates and interestedMaps[self] then
        interestedMaps[self] = nil
        self.trackingEventID = nil
        if dispatcherSubscribed and next(interestedMaps) == nil then
            Event.Logic.Unsubscribe(DISPATCHER_ID)
            dispatcherSubscribed = false
        end
    end
end

function PlayerTracking:SetTrackPlayer(enabled)
    enabled = enabled == true
    if self.trackPlayer == enabled then return end
    self.trackPlayer = enabled
    PlayerTracking._RefreshPlayerUpdates(self)
    if enabled then PlayerTracking._UpdateTrackedPlayer(self) end
end

function PlayerTracking:GetTrackPlayer()
    return self.trackPlayer
end

function PlayerTracking:CentreOnPlayer(options)
    options = options or {}
    assert(type(options) == "table", "options must be a table")
    local coordinate = readPlayerCoordinate()
    if coordinate == nil then return false end
    PlayerTracking.SetPlayerPosition(self, coordinate)
    if options.zoomToMapSquare == true then
        return self:ZoomToMapSquare(coordinate)
    end
    return self:ShowCoordinate(coordinate)
end

return PlayerTracking
