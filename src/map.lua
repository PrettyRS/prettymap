local WorldMap = require("src/world_map")
local Controls = require("src/controls")
local Helpers = require("src/map_helpers")
local TileRenderer = require("src/tile_renderer")
local PlayerTracking = require("src/player_tracking")
local MapOverlays = require("src/map_overlays")

local MapView = {}
MapView.__index = MapView

local ZOOM_LEVELS = { 1, 2, 4, 8, 16, 32, 64, 128, 192 }
local MIN_ZOOM_INDEX = 6
local MAPSQUARE_SIZE = 64
local DRAG_THRESHOLD = 5
local NULL_TILE_COLOUR = 0x000000FF
local EDGE_MARKER_SIZE = MapOverlays.EDGE_MARKER_SIZE
local clamp = Helpers.Clamp
local rounded = Helpers.Rounded

local INVALIDATION = {
    viewport_position = { tiles = true, edgeMarkers = true, notify = true },
    scale = {
        destroyTiles = true, tiles = true, player = true, sprites = true,
        drawing = true, edgeMarkers = true, notify = true,
    },
    plane = {
        destroyTiles = true, tiles = true, player = true, sprites = true,
        drawing = true, edgeMarkers = true, notify = true,
    },
    tile_contents = { tiles = true },
    player_position = { player = true, edgeMarkers = true },
    overlay_geometry = { edgeMarkers = true },
}

local TILE_METHODS = { "SetIconsVisible", "GetIconsVisible" }
local PLAYER_METHODS = {
    "SetPlayerPosition", "ClearPlayerPosition", "SetShowPlayerMarker",
    "GetShowPlayerMarker", "SetTrackPlayer", "GetTrackPlayer", "CentreOnPlayer",
}
local OVERLAY_METHODS = {
    "CreateCanvas", "DestroyCanvas", "CreateOverlayLayer", "DestroyOverlayLayer",
    "GetViewportSize", "AddViewChangeListener", "RemoveViewChangeListener",
    "CreateSprite", "DestroySprite", "CreateEdgeMarker", "CreateMarker",
    "SetDrawCallback", "Redraw",
}

local function optionalCallback(options, name)
    local callback = options[name]
    assert(callback == nil or type(callback) == "function", name .. " must be a function")
    return callback
end

function MapView.new(parent, options)
    options = options or {}
    assert(type(options) == "table", "options must be a table")
    local onClick = optionalCallback(options, "onClick")
    local self = setmetatable({
        clickListeners = {},
        drawCallback = optionalCallback(options, "onDraw"),
        viewportWidth = Helpers.PositiveInteger(options.width or 500, "width"),
        viewportHeight = Helpers.PositiveInteger(options.height or 460, "height"),
        zoomIndex = MIN_ZOOM_INDEX,
        zoomLevelMinimum = MIN_ZOOM_INDEX,
        maximumZoomIndex = #ZOOM_LEVELS,
        plane = clamp(Helpers.Integer(options.plane or 0, "plane"), 0, 3),
        onError = optionalCallback(options, "onError"),
        onZoomChanged = optionalCallback(options, "onZoomChanged"),
        onPlaneChanged = optionalCallback(options, "onPlaneChanged"),
        showPlayerMarker = options.showPlayerMarker == true,
        showIcons = options.showIcons == true,
        trackPlayer = false,
        tileSprites = {},
        iconTileSprites = {},
        customCanvases = {},
        customSprites = {},
        customOverlays = {},
        viewChangeListeners = {},
        edgeMarkers = {},
        customMarkers = {},
        map = WorldMap,
    }, MapView)
    self.tiles = Helpers.BindMethods(self, TileRenderer, TILE_METHODS)
    self.player = Helpers.BindMethods(self, PlayerTracking, PLAYER_METHODS)
    self.overlays = Helpers.BindMethods(self, MapOverlays, OVERLAY_METHODS)

    self.root = ui.Layer.new(parent)
    self.root:SetPos(options.x or 0, options.y or 0)
    self.root:SetSize(self.viewportWidth, self.viewportHeight)
    self.root.clickthrough = false

    self.viewport = ui.Layer.new(self.root)
    self.viewport:SetSize(0, 0, 1.0, 1.0)
    self.viewport.clickthrough = true

    self.background = ui.Rectangle.new(self.viewport)
    self.background.fill = true
    self.background.rgba = NULL_TILE_COLOUR
    self.background.clickthrough = true

    -- Stable parent layers define render order. Children never need to rebuild
    -- z-order while the map is dragged or the player moves.
    self.tileLayer = ui.Layer.new(self.viewport)
    self.iconTileLayer = ui.Layer.new(self.viewport)
    self.playerLayer = ui.Layer.new(self.viewport)
    self.mapOverlayLayer = ui.Layer.new(self.viewport)
    self.screenOverlayLayer = ui.Layer.new(self.root)
    self.screenMarkerLayer = ui.Layer.new(self.root)
    self.chromeLayer = ui.Layer.new(self.root)
    for _, layer in ipairs({ self.tileLayer, self.iconTileLayer, self.playerLayer,
        self.mapOverlayLayer }) do
        layer.clickthrough = true
    end
    for _, layer in ipairs({ self.screenOverlayLayer, self.screenMarkerLayer,
        self.chromeLayer }) do
        layer:SetSize(0, 0, 1.0, 1.0)
        layer.clickthrough = true
    end

    self.playerMarker = ui.Canvas.new(self.playerLayer)
    self.playerMarker.clickthrough = true

    self.border = ui.Canvas.new(self.chromeLayer)
    self.border:SetSize(0, 0, 1.0, 1.0)
    self.border:AddOutline(0, 0, self.viewportWidth, self.viewportHeight, 2, 0xB99B5FFF)
    self.border.clickthrough = true

    self.playerEdgeMarker = ui.Sprite.new(self.screenMarkerLayer)
    self.playerEdgeMarker:SetSize(EDGE_MARKER_SIZE, EDGE_MARKER_SIZE)
    self.playerEdgeMarker.clickthrough = true
    self.playerEdgeMarker.hidden = true
    self.playerEdgeMarkerHitbox = ui.Layer.new(self.screenMarkerLayer)
    self.playerEdgeMarkerHitbox:SetSize(EDGE_MARKER_SIZE, EDGE_MARKER_SIZE)
    self.playerEdgeMarkerHitbox.clickthrough = false
    self.playerEdgeMarkerHitbox.hidden = true
    self.playerEdgeMarkerHitbox:Subscribe(ui.Hook.ONCLICK, function()
        if self.playerCoordinate then
            self:CentreOn(self.playerCoordinate)
        end
        return false
    end)

    self.root:Subscribe(ui.Hook.ONCLICK, function(_, x, y)
        self.drag = {
            x = x,
            y = y,
            scrollX = self.viewport.scrollX or 0,
            scrollY = self.viewport.scrollY or 0,
            moved = false,
        }
        return false
    end)
    self.root:Subscribe(ui.Hook.ONHOLD, function(_, x, y)
        if not self.drag then return false end
        local deltaX = x - self.drag.x
        local deltaY = y - self.drag.y
        if math.abs(deltaX) >= DRAG_THRESHOLD or math.abs(deltaY) >= DRAG_THRESHOLD then
            self.drag.moved = true
        end
        if self.drag.moved then
            self:_SetScroll(self.drag.scrollX - deltaX, self.drag.scrollY - deltaY)
        end
        return false
    end)
    self.root:Subscribe(ui.Hook.ONRELEASE, function(_, x, y)
        local drag = self.drag
        self.drag = nil
        if drag and not drag.moved then self:_ClickAt(x, y) end
        return false
    end)
    self.root:Subscribe(ui.Hook.ONDRAGCOMPLETE, function()
        self.drag = nil
        return false
    end)
    self.root:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, delta)
        if delta < 0 then
            self:SetZoom(self.zoomIndex + 1)
        elseif delta > 0 then
            self:SetZoom(self.zoomIndex - 1)
        end
        return false
    end)

    if onClick then self:AddClickListener(onClick) end
    self:_ApplyZoom(Helpers.Integer(options.zoom or MIN_ZOOM_INDEX, "zoom"))
    if options.showFloorControls == true then
        self.floorControls = Controls.Floor(self.chromeLayer, self)
    end
    if options.showZoomControls == true then
        self.zoomControls = Controls.Zoom(self.chromeLayer, self)
    end
    if options.showRegionControls == true then
        self.regionControls = Controls.Region(self.chromeLayer, self)
    end
    if options.trackPlayer == true then
        PlayerTracking.SetTrackPlayer(self, true)
    else
        PlayerTracking._RefreshPlayerUpdates(self)
    end
    return self
end

function MapView:_ReportError(message, logWithoutHandler)
    if not self.onError then
        if logWithoutHandler then print("PrettyMap: " .. tostring(message)) end
        return
    end
    local succeeded, callbackError = pcall(self.onError, message, self)
    if not succeeded then
        print("PrettyMap onError callback failed: " .. tostring(callbackError))
    end
end

function MapView:_InvokeCallback(name, callback, ...)
    if not callback then return true end
    local succeeded, callbackError = pcall(callback, ...)
    if not succeeded then
        self:_ReportError(name .. " callback failed: " .. tostring(callbackError), true)
    end
    return succeeded
end

function MapView:_RefreshView(category)
    local work = assert(INVALIDATION[category], "unknown view invalidation: " .. tostring(category))
    if work.destroyTiles then
        TileRenderer._DestroyTiles(self)
        self.tileLevel = nil
    end
    if work.tiles then TileRenderer._RefreshTiles(self) end
    if work.player then PlayerTracking._DrawPlayer(self) end
    if work.sprites then MapOverlays._RefreshCustomSprites(self) end
    if work.drawing then MapOverlays._DrawCustomOverlay(self) end
    if work.edgeMarkers then MapOverlays._DrawEdgeMarkers(self) end
    if work.notify then MapOverlays._NotifyViewChanged(self) end
end

function MapView:_SetScroll(x, y, deferRefresh)
    local maxX = math.max(0, self.contentWidth - self.viewportWidth)
    local maxY = math.max(0, self.contentHeight - self.viewportHeight)
    local nextX = rounded(clamp(x, 0, maxX))
    local nextY = rounded(clamp(y, 0, maxY))
    if (self.viewport.scrollX or 0) == nextX
        and (self.viewport.scrollY or 0) == nextY then return false end
    self.viewport:SetScrollPos(nextX, nextY)
    if not deferRefresh then self:_RefreshView("viewport_position") end
    return true
end

function MapView:_ApplyZoom(index, centreNormalX, centreNormalY, scaleOverride)
    local fitScale = math.min(
        self.viewportWidth / WorldMap.width,
        self.viewportHeight / WorldMap.height
    )
    index = clamp(index, MIN_ZOOM_INDEX, #ZOOM_LEVELS)
    if self.mapWidth and self.zoomIndex == index and self.scaleOverride == scaleOverride then
        return false
    end
    local oldScrollX = self.viewport.scrollX or 0
    local oldScrollY = self.viewport.scrollY or 0
    if centreNormalX == nil and self.mapWidth then
        centreNormalX = (oldScrollX + self.viewportWidth / 2 - self.mapOffsetX) / self.mapWidth
        centreNormalY = (oldScrollY + self.viewportHeight / 2 - self.mapOffsetY) / self.mapHeight
    end
    centreNormalX = clamp(centreNormalX or 0.5, 0, 1)
    centreNormalY = clamp(centreNormalY or 0.5, 0, 1)

    self.zoomIndex = index
    self.scaleOverride = scaleOverride
    self.currentScale = scaleOverride or fitScale * ZOOM_LEVELS[self.zoomIndex]
    self.mapWidth = rounded(WorldMap.width * self.currentScale)
    self.mapHeight = rounded(WorldMap.height * self.currentScale)
    self.contentWidth = math.max(self.viewportWidth, self.mapWidth)
    self.contentHeight = math.max(self.viewportHeight, self.mapHeight)
    self.mapOffsetX = rounded((self.contentWidth - self.mapWidth) / 2)
    self.mapOffsetY = rounded((self.contentHeight - self.mapHeight) / 2)

    self.viewport:SetScrollSize(self.contentWidth, self.contentHeight)
    self.background:SetSize(self.contentWidth, self.contentHeight)
    self.playerMarker:SetSize(self.contentWidth, self.contentHeight)
    for _, layer in ipairs({ self.tileLayer, self.iconTileLayer, self.playerLayer,
        self.mapOverlayLayer }) do
        layer:SetSize(self.contentWidth, self.contentHeight)
    end
    for _, canvas in ipairs(self.customCanvases) do
        canvas:SetSize(self.contentWidth, self.contentHeight)
    end
    self:_SetScroll(
        self.mapOffsetX + centreNormalX * self.mapWidth - self.viewportWidth / 2,
        self.mapOffsetY + centreNormalY * self.mapHeight - self.viewportHeight / 2,
        true
    )
    self:_RefreshView("scale")
    if self.onZoomChanged then
        self:_InvokeCallback("onZoomChanged", self.onZoomChanged,
            self.zoomIndex, self.maximumZoomIndex, self:GetZoomLevelCount())
    end
    if self.zoomControls then self.zoomControls:Refresh() end
    return true
end

function MapView:SetZoom(index)
    Helpers.Integer(index, "zoom")
    return self:_ApplyZoom(index)
end

function MapView:ZoomIn()
    self:SetZoom(self.zoomIndex + 1)
end

function MapView:ZoomOut()
    self:SetZoom(self.zoomIndex - 1)
end

function MapView:GetZoom()
    return self.zoomIndex, self.zoomLevelMinimum, self.maximumZoomIndex
end

function MapView:GetZoomLevelCount()
    return self.maximumZoomIndex - self.zoomLevelMinimum + 1
end

function MapView:SetPlane(level)
    level = clamp(Helpers.Integer(level or 0, "plane"), 0, 3)
    if self.plane == level then return true end
    self.plane = level
    self.reportedMissingImage = false
    self:_RefreshView("plane")
    if self.floorControls then self.floorControls:Refresh() end
    self:_InvokeCallback("onPlaneChanged", self.onPlaneChanged, level, self)
    return true
end

function MapView:GetPlane()
    return self.plane
end

function MapView:_ClickAt(x, y)
    if not self.imageAvailable then return end
    local mapX = (self.viewport.scrollX or 0) + x - self.mapOffsetX
    local mapY = (self.viewport.scrollY or 0) + y - self.mapOffsetY
    local worldX, worldZ, level = WorldMap.FromPixel(
        mapX, mapY, self.mapWidth, self.mapHeight, WorldMap, self.plane)
    if not worldX then return end
    local coordinate = Helpers.NewCoordGrid(worldX, worldZ, level)
    for _, callback in pairs(self.clickListeners) do
        self:_InvokeCallback("onClick", callback, coordinate, WorldMap.id, self)
    end
end

function MapView:CentreOn(coordinate)
    local x, z, level = Helpers.CoordGridValues(coordinate)
    if not WorldMap.Contains(x, z, level) then return false end
    local pixelX, pixelY = WorldMap.ToPixel(x, z, self.mapWidth, self.mapHeight)
    self:_SetScroll(
        self.mapOffsetX + pixelX - self.viewportWidth / 2,
        self.mapOffsetY + pixelY - self.viewportHeight / 2
    )
    return true
end

function MapView:ShowCoordinate(coordinate)
    local x, z, level = Helpers.CoordGridValues(coordinate)
    if not WorldMap.Contains(x, z, level) then return false end
    self:SetPlane(level)
    return self:CentreOn(coordinate)
end

function MapView:AddClickListener(callback)
    if type(callback) ~= "function" then return nil end
    local token = {}
    self.clickListeners[token] = callback
    return token
end

function MapView:RemoveClickListener(token)
    self.clickListeners[token] = nil
end

function MapView:WorldToCanvas(coordinate)
    local x, z, level = Helpers.CoordGridValues(coordinate)
    if level ~= self.plane then return nil, nil end
    local pixelX, pixelY = WorldMap.ToPixel(
        x, z, self.mapWidth, self.mapHeight, WorldMap, level)
    if not pixelX then return nil, nil end
    return rounded(self.mapOffsetX + pixelX), rounded(self.mapOffsetY + pixelY)
end

function MapView:WorldToScreen(coordinate)
    local canvasX, canvasY = self:WorldToCanvas(coordinate)
    if not canvasX then return nil, nil end
    return canvasX - (self.viewport.scrollX or 0),
        canvasY - (self.viewport.scrollY or 0)
end

function MapView:ScreenToCanvas(x, y)
    return x + (self.viewport.scrollX or 0),
        y + (self.viewport.scrollY or 0)
end

function MapView:ZoomToMapSquare(coordinate)
    local x, z, level = Helpers.CoordGridValues(coordinate)
    if not WorldMap.Contains(x, z, level) then return false end
    self:SetPlane(level)
    local targetScale = math.min(
        self.viewportWidth / MAPSQUARE_SIZE,
        self.viewportHeight / MAPSQUARE_SIZE
    )
    local fitScale = math.min(
        self.viewportWidth / WorldMap.width,
        self.viewportHeight / WorldMap.height
    )
    local targetMultiplier = targetScale / fitScale
    local nearestIndex, nearestDistance = 1, math.huge
    for index, multiplier in ipairs(ZOOM_LEVELS) do
        local distance = math.abs(multiplier - targetMultiplier)
        if distance < nearestDistance then
            nearestIndex, nearestDistance = index, distance
        end
    end
    self:_ApplyZoom(nearestIndex, nil, nil, targetScale)
    return self:CentreOn(coordinate)
end

function MapView:Destroy()
    if not self.root then return false end
    self.trackPlayer = false
    self.showPlayerMarker = false
    PlayerTracking._RefreshPlayerUpdates(self)
    TileRenderer._DestroyTiles(self)
    for _, marker in ipairs(self.edgeMarkers) do
        marker.map = nil
        marker.component = nil
        marker.hitbox = nil
    end
    for _, marker in ipairs(self.customMarkers) do
        marker.map = nil
        marker.component = nil
        marker.hitbox = nil
    end
    if self.regionControls then
        self.regionControls:Destroy()
        self.regionControls = nil
    end
    if self.root then self.root:Destroy() self.root = nil end
    self.background = nil
    self.playerMarker = nil
    self.playerCoordinate = nil
    self.playerEdgeMarker = nil
    self.playerEdgeMarkerHitbox = nil
    self.border = nil
    self.viewport = nil
    self.tileLayer = nil
    self.iconTileLayer = nil
    self.playerLayer = nil
    self.mapOverlayLayer = nil
    self.screenOverlayLayer = nil
    self.screenMarkerLayer = nil
    self.chromeLayer = nil
    self.tileSprites = {}
    self.iconTileSprites = {}
    self.customCanvases = {}
    self.customSprites = {}
    self.customOverlays = {}
    self.viewChangeListeners = {}
    self.edgeMarkers = {}
    self.customMarkers = {}
    self.clickListeners = {}
    self.tiles = nil
    self.player = nil
    self.overlays = nil
    return true
end

return MapView
