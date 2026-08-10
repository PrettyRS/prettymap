local WorldMap = require("src/world_map")
local Helpers = require("src/map_helpers")

local MapOverlays = { EDGE_MARKER_SIZE = 32 }
local VERTICAL_EDGE_MARKER_WIDTH = 16
local DIAGONAL_SECTOR_LIMIT = 1 + math.sqrt(2)

local function createMarkerHandle(map, collection, options, configure)
    local marker = {
        map = map,
        coordinate = options.coordinate
            and Helpers.CopyCoordGrid(options.coordinate)
            or nil,
    }
    configure(marker)
    marker.component = ui.Sprite.new(map.screenMarkerLayer)
    marker.component.clickthrough = true
    marker.hitbox = ui.Layer.new(map.screenMarkerLayer)
    marker.hitbox.clickthrough = options.clickthrough == true
    marker.hitbox.hidden = true
    marker.hitbox:Subscribe(ui.Hook.ONCLICK, function()
        if marker.map and marker.coordinate then
            marker.map:CentreOn(marker.coordinate)
        end
        return false
    end)

    function marker:SetPosition(coordinate)
        if not self.map then return false end
        self.coordinate = Helpers.CopyCoordGrid(coordinate)
        self.map:_RefreshView("overlay_geometry")
        return true
    end

    function marker:Clear()
        self.coordinate = nil
        if self.component then self.component.hidden = true end
        if self.hitbox then self.hitbox.hidden = true end
    end

    function marker:Destroy()
        if not self.map then return false end
        local owner = self.map
        self.map = nil
        Helpers.RemoveValue(collection(owner), self)
        if self.component then self.component:Destroy() self.component = nil end
        if self.hitbox then self.hitbox:Destroy() self.hitbox = nil end
        return true
    end

    collection(map)[#collection(map) + 1] = marker
    return marker
end

function MapOverlays:_ConfigureEdgeMarker(
    marker, screenX, screenY, cardinalSprite, diagonalSprite, hitbox)
    local centreX = self.viewportWidth / 2
    local centreY = self.viewportHeight / 2
    local deltaX = screenX - centreX
    local deltaY = screenY - centreY
    local absX = math.abs(deltaX)
    local absY = math.abs(deltaY)
    if absX == 0 and absY == 0 then
        marker.hidden = true
        if hitbox then hitbox.hidden = true end
        return
    end

    local diagonal = absX > 0 and absY > 0
        and absX <= absY * DIAGONAL_SECTOR_LIMIT
        and absY <= absX * DIAGONAL_SECTOR_LIMIT
    local vertical = not diagonal and absY > absX
    local markerWidth = vertical and VERTICAL_EDGE_MARKER_WIDTH
        or MapOverlays.EDGE_MARKER_SIZE
    local markerHeight = MapOverlays.EDGE_MARKER_SIZE
    if marker.width ~= markerWidth or marker.height ~= markerHeight then
        marker:SetSize(markerWidth, markerHeight)
    end

    local horizontalScale = math.huge
    if absX > 0 then horizontalScale = (centreX - markerWidth / 2 - 3) / absX end
    local verticalScale = math.huge
    if absY > 0 then verticalScale = (centreY - markerHeight / 2 - 3) / absY end
    local scale = math.min(horizontalScale, verticalScale)
    local x = Helpers.Rounded(centreX + deltaX * scale - markerWidth / 2)
    local y = Helpers.Rounded(centreY + deltaY * scale - markerHeight / 2)
    marker:SetPos(x, y)
    if hitbox then
        if hitbox.width ~= MapOverlays.EDGE_MARKER_SIZE
            or hitbox.height ~= MapOverlays.EDGE_MARKER_SIZE then
            hitbox:SetSize(MapOverlays.EDGE_MARKER_SIZE, MapOverlays.EDGE_MARKER_SIZE)
        end
        hitbox:SetPos(
            Helpers.Rounded(x + markerWidth / 2 - MapOverlays.EDGE_MARKER_SIZE / 2),
            Helpers.Rounded(y + markerHeight / 2 - MapOverlays.EDGE_MARKER_SIZE / 2))
    end

    marker.rotationDegrees = 0
    marker.isFlippedHorizontally = false
    marker.isFlippedVertical = false
    if diagonal then
        marker.spriteID = diagonalSprite
        marker.isFlippedHorizontally = deltaX < 0
        marker.isFlippedVertical = deltaY > 0
    else
        marker.spriteID = cardinalSprite
        if absX >= absY then
            marker.isFlippedHorizontally = deltaX < 0
        else
            marker.rotationDegrees = 270
            if deltaY > 0 then
                marker.isFlippedHorizontally = true
            end
        end
    end
    marker.hidden = false
    if hitbox then
        hitbox.hidden = false
    end
end

function MapOverlays:_DrawEdgeMarker(
    marker, coordinate, cardinalSprite, diagonalSprite, hitbox)
    marker.hidden = true
    if hitbox then hitbox.hidden = true end
    if not coordinate or coordinate.level ~= self.plane or not self.mapWidth then return end
    local pixelX, pixelY = WorldMap.ToPixel(
        coordinate.x, coordinate.z, self.mapWidth, self.mapHeight, WorldMap, coordinate.level)
    if not pixelX then return end
    local screenX = self.mapOffsetX + pixelX - (self.viewport.scrollX or 0)
    local screenY = self.mapOffsetY + pixelY - (self.viewport.scrollY or 0)
    if screenX >= 0 and screenX < self.viewportWidth
        and screenY >= 0 and screenY < self.viewportHeight then
        return
    end
    MapOverlays._ConfigureEdgeMarker(self,
        marker, screenX, screenY, cardinalSprite, diagonalSprite, hitbox)
end

function MapOverlays:_DrawEdgeMarkers()
    if self.playerEdgeMarker then
        if self.showPlayerMarker then
            MapOverlays._DrawEdgeMarker(self, self.playerEdgeMarker, self.playerCoordinate,
                id.Sprite.YOU_ARE_HERE_ICON_1,
                id.Sprite.YOU_ARE_HERE_ICON_2, self.playerEdgeMarkerHitbox)
        else
            self.playerEdgeMarker.hidden = true
            self.playerEdgeMarkerHitbox.hidden = true
        end
    end
    for _, marker in ipairs(self.edgeMarkers) do
        if marker.component then
            MapOverlays._DrawEdgeMarker(self, marker.component, marker.coordinate,
                marker.cardinalSprite, marker.diagonalSprite, marker.hitbox)
        end
    end
    for _, marker in ipairs(self.customMarkers) do
        if marker.component then MapOverlays._DrawCustomMarker(self, marker) end
    end
end

function MapOverlays:CreateCanvas(options)
    options = options or {}
    assert(type(options) == "table", "options must be a table")
    local canvas = ui.Canvas.new(self.mapOverlayLayer)
    canvas:SetSize(self.contentWidth, self.contentHeight)
    canvas.clickthrough = options.clickthrough ~= false
    self.customCanvases[#self.customCanvases + 1] = canvas
    return canvas
end

function MapOverlays:DestroyCanvas(canvas)
    if not Helpers.RemoveValue(self.customCanvases, canvas) then return false end
    if self.drawCanvas == canvas then
        self.drawCanvas = nil
        self.drawCallback = nil
    end
    canvas:Destroy()
    return true
end

function MapOverlays:CreateOverlayLayer()
    local overlay = ui.Layer.new(self.screenOverlayLayer)
    overlay:SetSize(0, 0, 1.0, 1.0)
    overlay.clickthrough = true
    self.customOverlays[#self.customOverlays + 1] = overlay
    return overlay
end

function MapOverlays:DestroyOverlayLayer(overlay)
    if not Helpers.RemoveValue(self.customOverlays, overlay) then return false end
    overlay:Destroy()
    return true
end

function MapOverlays:GetViewportSize()
    return self.viewportWidth, self.viewportHeight
end

function MapOverlays:AddViewChangeListener(callback)
    if type(callback) ~= "function" then return nil end
    local token = {}
    self.viewChangeListeners[token] = callback
    return token
end

function MapOverlays:RemoveViewChangeListener(token)
    self.viewChangeListeners[token] = nil
end

function MapOverlays:_NotifyViewChanged()
    for _, callback in pairs(self.viewChangeListeners) do
        self:_InvokeCallback("view change", callback, self)
    end
end

function MapOverlays:CreateSprite(options)
    options = options or {}
    assert(type(options) == "table", "options must be a table")
    local sprite = ui.Sprite.new(self.mapOverlayLayer)
    local width = Helpers.PositiveInteger(options.width or options.size or 32, "sprite width")
    local height = Helpers.PositiveInteger(options.height or options.size or 32, "sprite height")
    sprite:SetSize(width, height)
    if options.spriteID then sprite.spriteID = options.spriteID end
    if options.sprite then sprite.sprite = options.sprite end
    if options.colour then sprite.rgba = options.colour end
    sprite.clickthrough = options.clickthrough ~= false
    -- Copy all position inputs so later mutation of the caller's options table
    -- cannot silently alter the retained sprite.
    local record = {
        component = sprite,
        coordinate = options.coordinate
            and Helpers.CopyCoordGrid(options.coordinate)
            or nil,
        offsetX = options.offsetX or 0,
        offsetY = options.offsetY or 0,
        canvasX = options.canvasX or 0,
        canvasY = options.canvasY or 0,
    }
    self.customSprites[#self.customSprites + 1] = record
    MapOverlays._RefreshCustomSprite(self, record)
    return sprite
end

function MapOverlays:DestroySprite(sprite)
    for index = #self.customSprites, 1, -1 do
        if self.customSprites[index].component == sprite then
            table.remove(self.customSprites, index)
            sprite:Destroy()
            return true
        end
    end
    return false
end

function MapOverlays:CreateEdgeMarker(options)
    options = options or {}
    assert(type(options) == "table", "options must be a table")
    local marker = createMarkerHandle(self, function(map) return map.edgeMarkers end,
        options, function(value)
            value.cardinalSprite = assert(options.cardinalSprite, "cardinalSprite is required")
            value.diagonalSprite = assert(options.diagonalSprite, "diagonalSprite is required")
        end)
    marker.component:SetSize(MapOverlays.EDGE_MARKER_SIZE, MapOverlays.EDGE_MARKER_SIZE)
    marker.hitbox:SetSize(MapOverlays.EDGE_MARKER_SIZE, MapOverlays.EDGE_MARKER_SIZE)
    self:_RefreshView("overlay_geometry")
    return marker
end

function MapOverlays:_DrawCustomMarker(marker)
    local component = marker.component
    local hitbox = marker.hitbox
    component.hidden = true
    hitbox.hidden = true
    local coordinate = marker.coordinate
    if not coordinate or coordinate.level ~= self.plane or not self.mapWidth then return end

    local pixelX, pixelY = WorldMap.ToPixel(
        coordinate.x, coordinate.z, self.mapWidth, self.mapHeight, WorldMap, coordinate.level)
    if not pixelX then return end
    local screenX = self.mapOffsetX + pixelX - (self.viewport.scrollX or 0)
    local screenY = self.mapOffsetY + pixelY - (self.viewport.scrollY or 0)
    local centreX = self.viewportWidth / 2
    local centreY = self.viewportHeight / 2
    local halfSize = marker.size / 2

    if screenX < 0 or screenX >= self.viewportWidth
        or screenY < 0 or screenY >= self.viewportHeight then
        local deltaX = screenX - centreX
        local deltaY = screenY - centreY
        local absX = math.abs(deltaX)
        local absY = math.abs(deltaY)
        local horizontalScale = math.huge
        if absX > 0 then horizontalScale = (centreX - halfSize - 3) / absX end
        local verticalScale = math.huge
        if absY > 0 then verticalScale = (centreY - halfSize - 3) / absY end
        local scale = math.min(horizontalScale, verticalScale)
        screenX = centreX + deltaX * scale
        screenY = centreY + deltaY * scale
    end

    local x = Helpers.Rounded(screenX - halfSize)
    local y = Helpers.Rounded(screenY - halfSize)
    component:SetPos(x, y)
    hitbox:SetPos(x, y)
    component.hidden = false
    hitbox.hidden = false
end

function MapOverlays:CreateMarker(options)
    options = options or {}
    assert(type(options) == "table", "options must be a table")
    local marker = createMarkerHandle(self, function(map) return map.customMarkers end,
        options, function(value)
            value.size = Helpers.PositiveInteger(options.size or 32, "marker size")
            value.spriteID = assert(options.spriteID, "spriteID is required")
        end)
    marker.component.spriteID = marker.spriteID
    marker.component:SetSize(marker.size, marker.size)
    marker.component.rotationDegrees = 0
    marker.component.isFlippedHorizontally = false
    marker.component.isFlippedVertical = false
    marker.hitbox:SetSize(marker.size, marker.size)
    self:_RefreshView("overlay_geometry")
    return marker
end

function MapOverlays:_RefreshCustomSprite(record)
    local sprite = record.component
    if record.coordinate then
        local x, y = self:WorldToCanvas(record.coordinate)
        sprite.hidden = x == nil
        if x then sprite:SetPos(x + record.offsetX, y + record.offsetY) end
    else
        sprite.hidden = false
        sprite:SetPos(record.canvasX, record.canvasY)
    end
end

function MapOverlays:_RefreshCustomSprites()
    for _, record in ipairs(self.customSprites) do
        MapOverlays._RefreshCustomSprite(self, record)
    end
end

function MapOverlays:SetDrawCallback(callback)
    assert(callback == nil or type(callback) == "function", "callback must be a function")
    self.drawCallback = callback
    if callback and not self.drawCanvas then
        self.drawCanvas = MapOverlays.CreateCanvas(self)
    end
    if not callback and self.drawCanvas then self.drawCanvas:Clear() end
    MapOverlays._DrawCustomOverlay(self)
end

function MapOverlays:Redraw()
    MapOverlays._DrawCustomOverlay(self)
end

function MapOverlays:_DrawCustomOverlay()
    if not self.drawCallback then return end
    if not self.drawCanvas then self.drawCanvas = MapOverlays.CreateCanvas(self) end
    self.drawCanvas:Clear()
    self:_InvokeCallback("onDraw", self.drawCallback, self.drawCanvas, self)
end

return MapOverlays
