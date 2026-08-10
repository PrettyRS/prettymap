package.path = "./?.lua;./?/init.lua;" .. package.path

local loadedNames = {}
local unloaded = 0
local logicCallbacks = {}
Event = {
    Logic = {
        Subscribe = function(name, callback) logicCallbacks[name] = callback end,
        Unsubscribe = function(name) logicCallbacks[name] = nil end,
    },
}
local trackedPlayer
Player = {
    IsAvailable = function() return trackedPlayer ~= nil end,
    GetEntity = function() return trackedPlayer end,
}
local inRegion = false
local regionSource
World = {
    IsAvailable = function() return trackedPlayer ~= nil end,
    IsRegion = function() return inRegion end,
    GetRegionSourceForCoordGrid = function() return regionSource end,
}
CoordGrid = {
    new = function(level, mapSquareX, mapSquareZ, localX, localZ)
        return {
            x = mapSquareX * 64 + localX,
            z = mapSquareZ * 64 + localZ,
            level = level,
            mapSquareX = mapSquareX,
            mapSquareZ = mapSquareZ,
            localX = localX,
            localZ = localZ,
        }
    end,
}
local function coord(x, z, level)
    return CoordGrid.new(level, x // 64, z // 64, x % 64, z % 64)
end
package.loaded["src/resources"] = {
    Image = function(name)
        loadedNames[#loadedNames + 1] = name
        return { name = name }
    end,
    Unload = function() unloaded = unloaded + 1 end,
}

local function component()
    local value = {
        scrollX = 0,
        scrollY = 0,
        text = {},
        containerSprite = {},
    }
    function value:SetPos(x, y)
        self.x, self.y = x, y
        self.positionUpdates = (self.positionUpdates or 0) + 1
    end
    function value:SetSize(width, height) self.width, self.height = width, height end
    function value:SetScrollSize(width, height) self.scrollWidth, self.scrollHeight = width, height end
    function value:SetScrollPos(x, y) self.scrollX, self.scrollY = x, y end
    function value:Subscribe(hook, callback) self[hook] = callback end
    function value:MoveToFront() end
    function value:Setup() end
    function value:Add(label, entryID) self.entry = { label, entryID } return true end
    function value:Select(entryID) self.selectedID = entryID return true end
    function value:Destroy() self.destroyed = true end
    function value:Clear() self.triangles, self.lines, self.sprites = 0, 0, {} end
    function value:AddOutline(x, y, width, height, thickness, colour)
        self.outlines = self.outlines or {}
        self.outlines[#self.outlines + 1] = {
            x = x, y = y, width = width, height = height,
            thickness = thickness, colour = colour,
        }
    end
    function value:AddTriangle() self.triangles = (self.triangles or 0) + 1 end
    function value:AddLine() self.lines = (self.lines or 0) + 1 end
    function value:AddSprite(x, y, width, height, spriteID, colour)
        self.sprites = self.sprites or {}
        self.sprites[#self.sprites + 1] = {
            x = x, y = y, width = width, height = height,
            spriteID = spriteID, colour = colour,
        }
    end
    return value
end

ui = {
    Hook = {
        ONCLICK = "click",
        ONHOLD = "hold",
        ONRELEASE = "release",
        ONDRAGCOMPLETE = "drag_complete",
        ONSCROLLWHEEL = "wheel",
        ONMOUSEOVER = "mouseover",
        ONMOUSELEAVE = "mouseleave",
        ONCONTENTCHANGED = "content_changed",
    },
    Layer = { new = component },
    Rectangle = { new = component },
    Sprite = { new = component },
    Canvas = { new = component },
    Text = { new = component },
    ComboField = { new = component },
    InputField = { new = component },
    Margin = { new = function() return {} end },
    AlignMode = { CENTRE = 1 },
    TextContentVisibilityMode = { VISIBLE = 1 },
    InputFieldFilterMode = { NONE = 1 },
    InputFieldKeyHandlingMode = { DEFAULT = 1 },
    InputFieldActionResult = {
        SUBMIT = 1,
        SUBMIT_ON_ESCAPE = 2,
        SUBMIT_ON_FOCUS_LOSS = 3,
    },
}

id = {
    Sprite = setmetatable({
        YOU_ARE_HERE_ICON_0 = 317,
        YOU_ARE_HERE_ICON_1 = 1690,
        YOU_ARE_HERE_ICON_2 = 1691,
        YOU_ARE_HERE_ICON_3 = 1692,
        YOU_ARE_HERE_ICON_4 = 1693,
        YOU_ARE_HERE_ICON_5 = 1694,
        CLUE_SCROLL_ICON = 8123,
    }, { __index = function(_, key) return key end }),
    Font = { MUSEO_SANS_15PT_REGULAR = 1 },
    StyleSheet = { COMBO_DEFAULT = 1, INPUT_DEFAULT = 2 },
}

local selectedCoordinate
local MapView = require("src/map")
local TileRenderer = require("src/tile_renderer")
local MapOverlays = require("src/map_overlays")
assert(not pcall(MapView.new, component(), { width = 0 }),
    "invalid viewport dimensions should fail before creating Client API components")
assert(not pcall(MapView.new, component(), { onDraw = true }),
    "invalid callback options should fail before creating Client API components")
local view = MapView.new(component(), {
    width = 516,
    height = 434,
    onClick = function(coordinate)
        selectedCoordinate = coordinate
    end,
})
assert(view.SetIconsVisible == nil and view.SetPlayerPosition == nil
    and view.CreateMarker == nil and view.Redraw == nil,
    "module-owned APIs must not be copied onto the map as compatibility methods")
assert(view.tiles and view.player and view.overlays,
    "module-owned APIs should be exposed through explicit namespaces")

assert(view.background.fill == true and view.background.rgba == 0x000000FF,
    "undefined map pixels should reveal a black null-tile background")
assert(view.background.width == view.contentWidth
    and view.background.height == view.contentHeight,
    "the black fallback should cover the scrollable atlas layer")
assert(#view.border.outlines == 1
    and view.border.outlines[1].width == 516
    and view.border.outlines[1].height == 434
    and view.border.outlines[1].thickness == 2
    and view.border.outlines[1].colour == 0xB99B5FFF,
    "the map canvas should retain its gold border")
assert(#loadedNames >= 1 and loadedNames[1]:find("maps/z1/0_", 1, true))
assert(view.imageAvailable)
assert(view.map.id == -1)
assert(view.zoomIndex == 6 and view.zoomLevelMinimum == 6,
    "the map should start at the minimum useful zoom level")
assert(view.maximumZoomIndex == 9 and view:GetZoomLevelCount() == 4,
    "zoom bounds and usable zoom count should be unambiguous")
assert(view.floorControls == nil and view.zoomControls == nil,
    "the frameless map should not create controls unless requested")
assert(view.tiles:GetIconsVisible() == false,
    "map icons should be opt-in by default")
assert(view.player:GetShowPlayerMarker() == false,
    "the player marker should expose its initial visibility")

local northEdgeMarker = component()
local northEdgeHitbox = component()
MapOverlays._ConfigureEdgeMarker(view, northEdgeMarker, 258, -100,
    id.Sprite.YOU_ARE_HERE_ICON_1, id.Sprite.YOU_ARE_HERE_ICON_2,
    northEdgeHitbox)
local southEdgeMarker = component()
MapOverlays._ConfigureEdgeMarker(view, southEdgeMarker, 258, 534,
    id.Sprite.YOU_ARE_HERE_ICON_1, id.Sprite.YOU_ARE_HERE_ICON_2)
assert(northEdgeMarker.width == 16 and northEdgeMarker.height == 32
    and northEdgeMarker.rotationDegrees == 270
    and not northEdgeMarker.isFlippedHorizontally
    and not northEdgeMarker.isFlippedVertical,
    "the north edge marker should use a narrow native-sprite allocation")
assert(northEdgeHitbox.width == 32 and northEdgeHitbox.height == 32
    and northEdgeHitbox.x + northEdgeHitbox.width / 2
        == northEdgeMarker.x + northEdgeMarker.width / 2
    and northEdgeHitbox.y + northEdgeHitbox.height / 2
        == northEdgeMarker.y + northEdgeMarker.height / 2,
    "the north edge marker should retain a centered square click area")
assert(southEdgeMarker.width == 16 and southEdgeMarker.height == 32
    and southEdgeMarker.rotationDegrees == northEdgeMarker.rotationDegrees
    and southEdgeMarker.isFlippedHorizontally
    and not southEdgeMarker.isFlippedVertical,
    "the south edge marker should mirror the native north orientation")

for _, name in ipairs(loadedNames) do
    assert(not name:find("map_icons/", 1, true),
        "disabled map icons should not load icon resources")
end

local tilePositionUpdates = 0
for _, tile in pairs(view.tileSprites) do
    tilePositionUpdates = tilePositionUpdates + tile.sprite.positionUpdates
end
TileRenderer._RefreshTiles(view)
local unchangedPositionUpdates = 0
for _, tile in pairs(view.tileSprites) do
    unchangedPositionUpdates = unchangedPositionUpdates + tile.sprite.positionUpdates
end
assert(unchangedPositionUpdates == tilePositionUpdates,
    "unchanged atlas bounds should skip redundant tile reconciliation")

local initialPlane, initialAtlasX, initialAtlasZ = loadedNames[1]:match(
    "maps/z1/(%d+)_(%d+)_(%d+)%.png")
local initialAvailabilityKey = string.format(
    "%s:%s:%s", initialPlane, initialAtlasX, initialAtlasZ)
local z1 = view.map.levels[1]
local initialAvailability = z1.available[initialAvailabilityKey]
z1.available[initialAvailabilityKey] = "shared_atlas.png"
TileRenderer._DestroyTiles(view)
view.tileLevel = nil
local aliasLoadStart = #loadedNames + 1
TileRenderer._RefreshTiles(view)
local aliasLoaded = false
for index = aliasLoadStart, #loadedNames do
    if loadedNames[index] == "maps/z1/shared_atlas.png" then aliasLoaded = true end
end
assert(aliasLoaded, "manifest aliases should load a shared canonical atlas resource")
z1.available[initialAvailabilityKey] = initialAvailability
TileRenderer._DestroyTiles(view)
view.tileLevel = nil
TileRenderer._RefreshTiles(view)

z1.icons = z1.icons or {}
z1.icons[initialAvailabilityKey] = true
local iconLoadStart = #loadedNames + 1
view.tiles:SetIconsVisible(true)
assert(view.tiles:GetIconsVisible() == true)
local iconLoaded = false
for index = iconLoadStart, #loadedNames do
    local expectedIconName = "map_icons/z1/icon_" .. initialPlane .. "_"
        .. initialAtlasX .. "_" .. initialAtlasZ .. ".png"
    if loadedNames[index] == expectedIconName then iconLoaded = true end
end
assert(iconLoaded, "enabling map icons should load the visible icon atlas")
local unloadBeforeIconsOff = unloaded
view.tiles:SetIconsVisible(false)
assert(view.tiles:GetIconsVisible() == false and unloaded > unloadBeforeIconsOff,
    "disabling map icons should unload their resources")
z1.icons[initialAvailabilityKey] = nil

view:SetZoom(1)
assert(view.zoomIndex == 6, "zooming out should stop at level 6")

view:SetZoom(8)
assert(view.zoomIndex == 8)
assert(#loadedNames > 1 and loadedNames[#loadedNames]:find("maps/z3/0_", 1, true))
local visibleTileCount = 0
for _ in pairs(view.tileSprites) do visibleTileCount = visibleTileCount + 1 end
assert(visibleTileCount <= 4, "only viewport-intersecting detail atlases should stay loaded")
assert(unloaded >= 1, "changing detail levels should unload old atlas images")

view.player:SetPlayerPosition(coord(3200, 3200, 0))
assert(#view.playerMarker.sprites == 0,
    "the player marker should be hidden by default")
view.player:SetShowPlayerMarker(true)
assert(#view.playerMarker.sprites == 1
    and view.playerMarker.sprites[1].spriteID == id.Sprite.YOU_ARE_HERE_ICON_0,
    "the player's tile should draw the you-are-here player sprite")
assert(not view.playerEdgeMarker.hidden
    and view.playerEdgeMarker.spriteID == id.Sprite.YOU_ARE_HERE_ICON_2,
    "an off-screen diagonal player should use the player diagonal arrow")
local originalCentreOn = view.CentreOn
local centredOn
view.CentreOn = function(_, coordinate)
    centredOn = coordinate
    return true
end
view.playerEdgeMarkerHitbox.click()
view.CentreOn = originalCentreOn
assert(view.playerEdgeMarker.clickthrough == true
    and view.playerEdgeMarkerHitbox.clickthrough == false
    and centredOn.x == 3200 and centredOn.z == 3200 and centredOn.level == 0,
    "clicking the player edge marker should centre on the player")
local markerUpdateEventID = view.trackingEventID
assert(markerUpdateEventID and logicCallbacks[markerUpdateEventID],
    "a visible player marker should subscribe to live player updates")
local markerX = view.playerMarker.sprites[1].x
local markerScrollX = view.viewport.scrollX
local markerScrollY = view.viewport.scrollY
trackedPlayer = {
    isValid = true,
    coordGrid = { x = 3201, z = 3200, level = 0 },
}
logicCallbacks[markerUpdateEventID]()
assert(view.playerCoordinate.x == 3201
    and view.playerCoordinate.z == 3200
    and view.playerMarker.sprites[1].x ~= markerX,
    "the visible player marker should move with the player when tracking is disabled")
assert(view.player:GetTrackPlayer() == false
    and view.viewport.scrollX == markerScrollX
    and view.viewport.scrollY == markerScrollY,
    "marker-only updates should not move the camera")

assert(view:ZoomToMapSquare(coord(3200, 3200, 0)))
local mapsquarePixels = 64 * view.mapWidth / view.map.width
assert(math.abs(mapsquarePixels - 434) <= 1,
    "center on player should frame one mapsquare at the viewport height")
local WorldMap = require("src/world_map")
local playerPixelX, playerPixelY = WorldMap.ToPixel(
    3200, 3200, view.mapWidth, view.mapHeight, view.map, 0)
local playerScreenX = view.mapOffsetX + playerPixelX - view.viewport.scrollX
local playerScreenY = view.mapOffsetY + playerPixelY - view.viewport.scrollY
assert(math.abs(playerScreenX - 258) <= 1 and math.abs(playerScreenY - 217) <= 1,
    "center on player should place the occupied tile in the viewport center")
assert(view.playerEdgeMarker.hidden,
    "the player edge arrow should hide when the player tile is visible")

local edgeMarker = view.overlays:CreateEdgeMarker({
    coordinate = coord(12000, 3200, 0),
    cardinalSprite = id.Sprite.YOU_ARE_HERE_ICON_4,
    diagonalSprite = id.Sprite.YOU_ARE_HERE_ICON_5,
})
assert(not edgeMarker.component.hidden
    and edgeMarker.component.spriteID == id.Sprite.YOU_ARE_HERE_ICON_4,
    "consumers should be able to add generic off-screen edge markers")
centredOn = nil
originalCentreOn = view.CentreOn
view.CentreOn = function(_, coordinate)
    centredOn = coordinate
    return true
end
edgeMarker.hitbox.click()
view.CentreOn = originalCentreOn
assert(edgeMarker.component.clickthrough == true
    and edgeMarker.hitbox.clickthrough == false
    and centredOn.x == 12000 and centredOn.z == 3200 and centredOn.level == 0,
    "clicking a destination edge marker should centre on its retained coordinate")
MapOverlays._ConfigureEdgeMarker(view, edgeMarker.component, 258, -100,
    edgeMarker.cardinalSprite, edgeMarker.diagonalSprite, edgeMarker.hitbox)
assert(edgeMarker.component.width == 16 and edgeMarker.component.height == 32
    and edgeMarker.component.spriteID == id.Sprite.YOU_ARE_HERE_ICON_4
    and edgeMarker.component.rotationDegrees == 270
    and not edgeMarker.component.isFlippedHorizontally,
    "destination edge markers should use the corrected north allocation")
assert(edgeMarker.hitbox.width == 32 and edgeMarker.hitbox.height == 32
    and edgeMarker.hitbox.x + edgeMarker.hitbox.width / 2
        == edgeMarker.component.x + edgeMarker.component.width / 2,
    "destination north markers should retain a centered square click area")
MapOverlays._ConfigureEdgeMarker(view, edgeMarker.component, 258, 534,
    edgeMarker.cardinalSprite, edgeMarker.diagonalSprite, edgeMarker.hitbox)
assert(edgeMarker.component.width == 16 and edgeMarker.component.height == 32
    and edgeMarker.component.spriteID == id.Sprite.YOU_ARE_HERE_ICON_4
    and edgeMarker.component.rotationDegrees == 270
    and edgeMarker.component.isFlippedHorizontally,
    "destination edge markers should use the corrected south allocation")
edgeMarker:Clear()
assert(edgeMarker.component.hidden)
local edgeComponent = edgeMarker.component
assert(edgeMarker:Destroy() and edgeComponent.destroyed
    and edgeMarker.hitbox == nil
    and #view.edgeMarkers == 0 and not edgeMarker:Destroy(),
    "destroying an edge marker should release its retained map record")

local clueMarker = view.overlays:CreateMarker({
    coordinate = coord(12000, 3200, 0),
    spriteID = id.Sprite.CLUE_SCROLL_ICON,
})
assert(not clueMarker.component.hidden
    and clueMarker.component.spriteID == id.Sprite.CLUE_SCROLL_ICON
    and clueMarker.component.rotationDegrees == 0
    and not clueMarker.component.isFlippedHorizontally
    and not clueMarker.component.isFlippedVertical,
    "custom markers should cling to the edge without transforming their sprite")
centredOn = nil
originalCentreOn = view.CentreOn
view.CentreOn = function(_, coordinate)
    centredOn = coordinate
    return true
end
clueMarker.hitbox.click()
view.CentreOn = originalCentreOn
assert(centredOn.x == 12000 and centredOn.z == 3200 and centredOn.level == 0,
    "clicking a custom marker should centre on its retained coordinate")
assert(clueMarker:SetPosition(coord(3200, 12000, 0))
    and clueMarker.component.rotationDegrees == 0
    and not clueMarker.component.isFlippedHorizontally
    and not clueMarker.component.isFlippedVertical,
    "custom markers should remain untransformed on every map edge")
clueMarker:Clear()
assert(clueMarker.component.hidden and clueMarker.hitbox.hidden)
local clueComponent = clueMarker.component
local clueHitbox = clueMarker.hitbox
assert(clueMarker:Destroy() and clueComponent.destroyed and clueHitbox.destroyed
    and #view.customMarkers == 0 and not clueMarker:Destroy(),
    "destroying a custom marker should release both retained components")

view:_ClickAt(258, 217)
assert(selectedCoordinate ~= nil and selectedCoordinate.level == 0)
assert(view.pinX == nil, "clicks must not create destination state in PrettyMap")

local drawCount = 0
view.overlays:SetDrawCallback(function(canvas, map)
    local x, y = map:WorldToCanvas(coord(3200, 3200, 0))
    if x then canvas:AddSprite(x, y, 16, 16, 9001, 0xFFFFFFFF) end
    drawCount = drawCount + 1
end)
assert(drawCount == 1 and #view.drawCanvas.sprites == 1,
    "consumer drawing should render through the retained overlay canvas")
view:SetZoom(7)
assert(drawCount == 2, "consumer drawing should refresh after zoom changes")
local customSpriteOptions = {
    coordinate = coord(3200, 3200, 0),
    spriteID = 9002,
    size = 16,
}
local customSprite = view.overlays:CreateSprite(customSpriteOptions)
local normalizedSpriteX = customSprite.x
customSpriteOptions.coordinate.x = 12000
MapOverlays._RefreshCustomSprites(view)
assert(customSprite.x == normalizedSpriteX,
    "retained sprites should use normalized options instead of caller-owned tables")
local spriteX = customSprite.x
view:SetZoom(8)
assert(customSprite.x ~= spriteX and not customSprite.hidden,
    "world-positioned sprites should follow map zoom changes")
view:SetPlane(1)
assert(customSprite.hidden, "world-positioned sprites should respect the viewed floor")
view:SetPlane(0)

local disposableCanvas = view.overlays:CreateCanvas()
local disposableOverlay = view.overlays:CreateOverlayLayer()
local disposableSprite = view.overlays:CreateSprite({ canvasX = 10, canvasY = 10 })
assert(view.overlays:DestroyCanvas(disposableCanvas) and disposableCanvas.destroyed)
assert(view.overlays:DestroyOverlayLayer(disposableOverlay) and disposableOverlay.destroyed)
assert(view.overlays:DestroySprite(disposableSprite) and disposableSprite.destroyed,
    "custom component removal should destroy and untrack each component")

local callbackErrors = {}
view.onError = function(message) callbackErrors[#callbackErrors + 1] = message end
local failingToken = view:AddClickListener(function() error("consumer failure") end)
local callbackAfterFailure = 0
local healthyToken = view:AddClickListener(function()
    callbackAfterFailure = callbackAfterFailure + 1
end)
view:_ClickAt(258, 217)
assert(#callbackErrors == 1 and callbackErrors[1]:find("consumer failure", 1, true)
    and callbackAfterFailure == 1,
    "consumer callback failures should be reported without stopping other callbacks")
view:RemoveClickListener(failingToken)
view:RemoveClickListener(healthyToken)

local extraClicks = 0
local token = view:AddClickListener(function() extraClicks = extraClicks + 1 end)
view:_ClickAt(258, 217)
assert(extraClicks == 1)
view:RemoveClickListener(token)
view:_ClickAt(258, 217)
assert(extraClicks == 1, "click listeners should be removable")

view:SetPlane(1)
assert(#view.playerMarker.sprites == 0,
    "the player marker should hide on another floor")
view:SetPlane(0)
assert(#view.playerMarker.sprites == 1)
view:Destroy()
assert(logicCallbacks[markerUpdateEventID] == nil,
    "destroying a marker-only map should unsubscribe live player updates")
assert(view:Destroy() == false, "map destruction should be idempotent")

local controlledView = MapView.new(component(), {
    width = 516,
    height = 434,
    showFloorControls = true,
    showZoomControls = true,
    showRegionControls = true,
})
assert(controlledView.floorControls and controlledView.zoomControls
    and controlledView.regionControls,
    "floor, zoom, and region controls should be independently opt-in UI")
local overlay = controlledView.overlays:CreateOverlayLayer()
local viewChanges = 0
local viewChangeToken = controlledView.overlays:AddViewChangeListener(function()
    viewChanges = viewChanges + 1
end)
controlledView:_SetScroll(20, 20)
assert(overlay.width == 0 and overlay.height == 0 and viewChanges == 1,
    "screen-space overlays should fill the viewport and follow view changes")
controlledView.overlays:RemoveViewChangeListener(viewChangeToken)
local floorSurface = controlledView.floorControls.surface
assert(floorSurface.background.spriteID == "RS3_HUD_WINDOW_CONTENT_TILE"
    and floorSurface.background.isTiling
    and floorSurface.background.alpha == 0.82,
    "controls should restore the tiled PrettyUI HUD background sprite")
assert(floorSurface.root.clickthrough == false
    and floorSurface.container.enabled == true
    and floorSurface.container.clickthrough == false,
    "control sprites should use PrettyUI's enabled inset content hierarchy")
assert(floorSurface.top.spriteID == "RS3_HUD_WINDOW_TOP_TILE"
    and floorSurface.bottom.spriteID == "RS3_HUD_WINDOW_BOTTOM_TILE"
    and floorSurface.left.spriteID == "RS3_HUD_WINDOW_SIDE_TILE"
    and floorSurface.right.spriteID == "RS3_HUD_WINDOW_SIDE_TILE"
    and floorSurface.topLeft.spriteID == "RS3_HUD_WINDOW_CORNER_TOP"
    and floorSurface.topRight.spriteID == "RS3_HUD_WINDOW_CORNER_TOP"
    and floorSurface.bottomLeft.spriteID == "RS3_HUD_WINDOW_CORNER_BOTTOM"
    and floorSurface.bottomRight.spriteID == "RS3_HUD_WINDOW_CORNER_BOTTOM",
    "controls should restore all PrettyUI border and corner sprites")
controlledView:SetPlane(3)
assert(controlledView.floorControls.text.content == "3"
    and controlledView.floorControls.up.disabled,
    "external floor changes should refresh integrated controls")
controlledView:SetZoom(9)
assert(controlledView.zoomControls.text.content == "4"
    and controlledView.zoomControls.inside.disabled,
    "external zoom changes should refresh integrated controls")
local regionControl = controlledView.regionControls
assert(regionControl.root.x == 4 and regionControl.root.y == 4
    and regionControl.regions[1].label == "Runescape Surface"
    and regionControl.regions[4].label == "Braindeath isle"
    and regionControl.regions[5].label == "Ancient cavern"
    and regionControl.regions[39].label == "Zanaris"
    and #regionControl.regions == 39,
    "the integrated region picker should retain its position and explicit order")
local originalShowCoordinate = controlledView.ShowCoordinate
local selectedRegionCoordinate
controlledView.ShowCoordinate = function(_, coordinate)
    selectedRegionCoordinate = coordinate
    return true
end
assert(regionControl:Select(3)
    and selectedRegionCoordinate.x == 5430
    and selectedRegionCoordinate.z == 2330
    and selectedRegionCoordinate.level == 0
    and controlledView:GetZoom() == 8,
    "the integrated region picker should zoom and centre its owning map")
controlledView.ShowCoordinate = originalShowCoordinate
trackedPlayer = {
    isValid = true,
    coordGrid = { x = 12805, z = 12806, level = 0 },
}
inRegion = true
regionSource = { x = 3304, z = 3400, level = 1 }
controlledView.player:SetTrackPlayer(true)
assert(controlledView.player:GetTrackPlayer()
    and controlledView.playerCoordinate.x == 3309
    and controlledView.playerCoordinate.z == 3406
    and controlledView:GetPlane() == 1,
    "player tracking should use the corresponding source tile inside an instance")
local trackingEventID = controlledView.trackingEventID
assert(logicCallbacks[trackingEventID],
    "player tracking should subscribe to a per-map logic event")
trackedPlayer.coordGrid = { x = 12806, z = 12807, level = 0 }
regionSource = { x = 3304, z = 3400, level = 2 }
logicCallbacks[trackingEventID]()
assert(controlledView.playerCoordinate.x == 3310
    and controlledView.playerCoordinate.z == 3407
    and controlledView:GetPlane() == 2,
    "instance tracking should preserve the player's tile offset within the source zone")
local trackedScreenX, trackedScreenY = controlledView:WorldToScreen(coord(3310, 3407, 2))
assert(math.abs(trackedScreenX - 258) <= 1
    and math.abs(trackedScreenY - 217) <= 1,
    "camera tracking should centre on the mapped source coordinate")
controlledView.player:SetTrackPlayer(false)
assert(not controlledView.player:GetTrackPlayer()
    and logicCallbacks[trackingEventID] == nil,
    "disabling player tracking should unsubscribe its logic event")
controlledView.player:SetShowPlayerMarker(false)
assert(controlledView.player:GetShowPlayerMarker() == false,
    "player marker visibility should be available through the public API")
controlledView.player:SetTrackPlayer(true)
local destroyTrackingEventID = controlledView.trackingEventID
local retainedMarker = controlledView.overlays:CreateEdgeMarker({
    cardinalSprite = id.Sprite.YOU_ARE_HERE_ICON_4,
    diagonalSprite = id.Sprite.YOU_ARE_HERE_ICON_5,
})
controlledView:Destroy()
assert(logicCallbacks[destroyTrackingEventID] == nil,
    "destroying a tracked map should unsubscribe its logic event")
assert(regionControl.root == nil and regionControl.dropdown == nil,
    "destroying a map should destroy its self-owned region picker")
assert(retainedMarker.map == nil and retainedMarker.component == nil
    and retainedMarker:SetPosition(coord(3200, 3200, 0)) == false,
    "destroying a map should invalidate retained edge-marker handles")
inRegion = false
regionSource = nil

print("map view tests passed")
