local WorldMap = require("src/world_map")
local Resources = require("src/resources")
local Helpers = require("src/map_helpers")

local TileRenderer = {}
local clamp = Helpers.Clamp
local rounded = Helpers.Rounded

function TileRenderer:_DestroyTileSet(tileSet)
    for key, tile in pairs(tileSet) do
        tile.sprite:Destroy()
        Resources.Unload(tile.resource)
        tileSet[key] = nil
    end
end

function TileRenderer:_DestroyTiles()
    TileRenderer._DestroyTileSet(self, self.tileSprites)
    TileRenderer._DestroyTileSet(self, self.iconTileSprites)
    self.tileViewportKey = nil
end

function TileRenderer:_TileBounds(level, atlasX, atlasZ)
    local left = rounded(self.mapOffsetX + atlasX * level.span * self.currentScale)
    local right = rounded(self.mapOffsetX + (atlasX + 1) * level.span * self.currentScale)
    local top = rounded(self.mapOffsetY
        + (WorldMap.maxZ - (atlasZ + 1) * level.span) * self.currentScale)
    local bottom = rounded(self.mapOffsetY
        + (WorldMap.maxZ - atlasZ * level.span) * self.currentScale)
    return left, top, right - left, bottom - top
end

function TileRenderer:_RefreshTiles()
    if not self.viewport or not self.currentScale then return end
    local level = WorldMap.LevelForScale(self.currentScale)
    if self.tileLevel ~= level then
        TileRenderer._DestroyTiles(self)
        self.tileLevel = level
    end

    local scrollX = self.viewport.scrollX or 0
    local scrollY = self.viewport.scrollY or 0
    local worldLeft = clamp((scrollX - self.mapOffsetX) / self.currentScale, 0, WorldMap.maxX)
    local worldRight = clamp(
        (scrollX + self.viewportWidth - self.mapOffsetX) / self.currentScale,
        0,
        WorldMap.maxX
    )
    local worldNorth = clamp(
        WorldMap.maxZ - (scrollY - self.mapOffsetY) / self.currentScale,
        WorldMap.minZ,
        WorldMap.maxZ
    )
    local worldSouth = clamp(
        WorldMap.maxZ - (scrollY + self.viewportHeight - self.mapOffsetY) / self.currentScale,
        WorldMap.minZ,
        WorldMap.maxZ
    )
    local minAtlasX = math.floor(worldLeft / level.span)
    local maxAtlasX = math.floor(math.max(worldLeft, worldRight - 0.001) / level.span)
    local minAtlasZ = math.floor(worldSouth / level.span)
    local maxAtlasZ = math.floor(math.max(worldSouth, worldNorth - 0.001) / level.span)
    local viewportKey = string.format("%s:%d:%s:%d:%d:%d:%d:%s", level.folder,
        self.plane, tostring(self.currentScale), minAtlasX, maxAtlasX, minAtlasZ,
        maxAtlasZ, tostring(self.showIcons))
    -- A completed reconciliation is cacheable even when no image exists.
    if self.tileViewportKey == viewportKey then return end
    self.tileViewportKey = viewportKey
    self.tileReconciliationCount = (self.tileReconciliationCount or 0) + 1

    local required = {}
    local requiredIcons = {}
    local loadFailure = nil

    local function refreshTile(tileSet, availability, resourceFolder, keyPrefix, atlasX, atlasZ)
        local availabilityKey = string.format("%d:%d:%d", self.plane, atlasX, atlasZ)
        local availableResource = availability and availability[availabilityKey]
        if not availableResource then return end
        local key = keyPrefix .. level.folder .. ":" .. availabilityKey
        local requiredSet = tileSet == self.tileSprites and required or requiredIcons
        requiredSet[key] = true
        local tile = tileSet[key]
        if not tile then
            local filename
            if type(availableResource) == "string" then
                filename = availableResource
            elseif tileSet == self.iconTileSprites then
                filename = string.format("icon_%d_%d_%d.png", self.plane, atlasX, atlasZ)
            else
                filename = string.format("%d_%d_%d.png", self.plane, atlasX, atlasZ)
            end
            local resourceName = string.format("%s/%s/%s", resourceFolder, level.folder, filename)
            local resource, resourceError = Resources.Image(resourceName)
            if not resource and not loadFailure then loadFailure = resourceError end
            if resource then
                local parent = tileSet == self.iconTileSprites
                    and self.iconTileLayer or self.tileLayer
                local sprite = ui.Sprite.new(parent)
                sprite.sprite = resource
                sprite.clickthrough = true
                local x, y, width, height = TileRenderer._TileBounds(
                    self, level, atlasX, atlasZ)
                sprite:SetPos(x, y)
                sprite:SetSize(width, height)
                tile = { sprite = sprite, resource = resource }
                tileSet[key] = tile
            end
        end
    end

    for atlasZ = minAtlasZ, maxAtlasZ do
        for atlasX = minAtlasX, maxAtlasX do
            refreshTile(self.tileSprites, level.available, "maps", "", atlasX, atlasZ)
            if self.showIcons then
                refreshTile(self.iconTileSprites, level.icons, "map_icons", "icons:", atlasX, atlasZ)
            end
        end
    end

    for key, tile in pairs(self.tileSprites) do
        if not required[key] then
            tile.sprite:Destroy()
            Resources.Unload(tile.resource)
            self.tileSprites[key] = nil
        end
    end
    for key, tile in pairs(self.iconTileSprites) do
        if not requiredIcons[key] then
            tile.sprite:Destroy()
            Resources.Unload(tile.resource)
            self.iconTileSprites[key] = nil
        end
    end

    self.imageAvailable = next(self.tileSprites) ~= nil
    if not self.imageAvailable and not self.reportedMissingImage then
        self.reportedMissingImage = true
        self:_ReportError(loadFailure
            or "No rendered map tiles are available in this area and floor.")
    elseif self.imageAvailable then
        self.reportedMissingImage = false
    end
end

function TileRenderer:SetIconsVisible(visible)
    visible = visible == true
    if self.showIcons == visible then return end
    self.showIcons = visible
    self.tileViewportKey = nil
    if not visible then
        TileRenderer._DestroyTileSet(self, self.iconTileSprites)
    else
        self:_RefreshView("tile_contents")
    end
end

function TileRenderer:GetIconsVisible()
    return self.showIcons
end

return TileRenderer
