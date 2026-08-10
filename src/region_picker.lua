local Helpers = require("src/map_helpers")

local RegionPicker = {}
RegionPicker.__index = RegionPicker

local WIDTH = 180
local HEIGHT = 32
local BUTTON_WIDTH = 24
local ROW_HEIGHT = 24
local MAX_VISIBLE_ROWS = 8
local TEXT_COLOUR = 0xE9E5DDFF
local DISABLED_TEXT_COLOUR = 0x8B8882FF
local BACKGROUND_COLOUR = 0x171512E8
local BORDER_COLOUR = 0x716B61FF
local HOVER_COLOUR = 0x393530F2
local SELECTED_COLOUR = 0x4A4640FF
local SCROLL_TRACK_COLOUR = 0x302D29D0
local SCROLL_THUMB_COLOUR = 0x8F887EFF
local SCROLLBAR_WIDTH = 4
local SCROLLBAR_RIGHT = 3
local SCROLLBAR_MARGIN = 3
local MIN_THUMB_HEIGHT = 16

local REGIONS = {
    { label = "Runescape Surface", id = 1, order = 1, x = 3210, z = 3424 },
    { label = "Havenhythe", id = 2, order = 2, x = 3530, z = 1575 },
    { label = "Anachronia", id = 3, order = 3, x = 5430, z = 2330 },
    { label = "Braindeath isle", id = 4, order = 4, x = 2144, z = 5101 },
    { label = "Ardougne Underground", id = 5, x = 2623, z = 9695 },
    { label = "Zanaris", id = 6, x = 2411, z = 4451 },
    { label = "Troll Stronghold", id = 7, x = 2822, z = 10087, level = 2 },
    { label = "Yanille Dungeon", id = 8, x = 2580, z = 9522 },
    { label = "Tolna's Rift", id = 9, x = 3296, z = 9824 },
    { label = "Fremennik Dungeon", id = 10, x = 2751, z = 10016 },
    { label = "Wilderness Dungeons", id = 11, x = 3040, z = 10303 },
    { label = "White Wolf Mountain Underground", id = 12, x = 2879, z = 9919 },
    { label = "Stronghold of Safety", id = 13, x = 3168, z = 4256, level = 1 },
    { label = "TzHaar City", id = 14, x = 4682, z = 5130 },
    { label = "Karamja Underground", id = 15, x = 2720, z = 9535 },
    { label = "Miscellania Underground", id = 16, x = 2505, z = 10256 },
    { label = "God Wars Dungeon", id = 17, x = 2879, z = 5311 },
    { label = "Waterbirth Island Dungeon", id = 18, x = 2495, z = 10144 },
    { label = "Taverley Dungeon", id = 19, x = 2879, z = 9759 },
    { label = "Dwarven Mines", id = 20, x = 3040, z = 9824 },
    { label = "Kalphite Hive", id = 21, x = 3455, z = 9504 },
    { label = "Keldagrim", id = 22, x = 2879, z = 10176 },
    { label = "Pollnivneach Dungeon", id = 23, x = 3359, z = 9407 },
    { label = "Chaos Tunnels", id = 24, x = 3232, z = 5503 },
    { label = "Stronghold of Security", id = 25, x = 1888, z = 5216 },
    { label = "Asgarnian Ice Dungeon", id = 26, x = 3034, z = 9576 },
    { label = "Dorgesh-Kaan", id = 27, x = 2720, z = 5344 },
    { label = "Mos Le'Harmless cave", id = 28, x = 3775, z = 9407 },
    { label = "Ourania Altar", id = 29, x = 3296, z = 4832 },
    { label = "Lair of Tarn Razorlor", id = 30, x = 3168, z = 4564 },
    { label = "Misthalin Underground", id = 31, x = 3168, z = 9632 },
    { label = "Living Rock Caverns", id = 32, x = 3648, z = 5120 },
    { label = "Ancient cavern", id = 33, x = 1764, z = 5350 },
    { label = "Lava Flow Mine", id = 34, x = 2207, z = 5663 },
    { label = "Jadinko Lair", id = 35, x = 3040, z = 9248 },
    { label = "Morytania Underground", id = 36, x = 3520, z = 9824 },
    { label = "Ascension Dungeon", id = 37, x = 1087, z = 639, level = 1 },
    { label = "Grotworm Lair", id = 38, x = 1206, z = 6372 },
    { label = "Exiled Kalphite Hive", id = 39, x = 2975, z = 1631 },
}

local function sortedRegions()
    local result = {}
    for index, region in ipairs(REGIONS) do
        result[index] = region
    end
    table.sort(result, function(left, right)
        if left.order ~= nil or right.order ~= nil then
            if left.order == nil then return false end
            if right.order == nil then return true end
            if left.order ~= right.order then return left.order < right.order end
        end
        return left.label < right.label
    end)
    return result
end

local function rectangle(parent, colour)
    local value = ui.Rectangle.new(parent)
    value:SetSize(0, 0, 1.0, 1.0)
    value.fill = true
    value.rgba = colour
    value.clickthrough = true
    return value
end

local function frameEdge(parent, x, y, width, height, xAnchor, yAnchor,
    widthAnchor, heightAnchor)
    local value = ui.Rectangle.new(parent)
    value:SetPos(x, y, xAnchor or 0, yAnchor or 0)
    value:SetSize(width, height, widthAnchor or 0, heightAnchor or 0)
    value.fill = true
    value.rgba = BORDER_COLOUR
    value.clickthrough = true
    return value
end

function RegionPicker.new(parent, map)
    local self = setmetatable({
        map = map,
        regions = sortedRegions(),
        rows = {},
        open = false,
        selectedID = 1,
        selectedLabel = REGIONS[1].label,
        pendingContents = {},
        scrollOffset = 0,
    }, RegionPicker)

    self.root = ui.Layer.new(parent)
    self.root:SetPos(4, 4)
    self.root:SetSize(WIDTH, HEIGHT)
    self.root.clickthrough = false

    -- The native ComboField supplies the established frame and arrow styling;
    -- the PrettyMap-owned InputField and rows provide ordered filtering.
    self.shell = ui.ComboField.new(self.root)
    self.shell.stylesheetID = id.StyleSheet.COMBO_DEFAULT
    self.shell:SetSize(0, 0, 1.0, 1.0)
    self.shell.clickthrough = true
    self.shell:Add("", 0)
    self.shell:Select(0, false)

    self.input = ui.InputField.new(self.root)
    self.input.stylesheetID = id.StyleSheet.INPUT_DEFAULT
    self.input:SetSize(-BUTTON_WIDTH, 0, 1.0, 1.0)
    self.input:Setup(
        ui.TextContentVisibilityMode.VISIBLE,
        ui.InputFieldFilterMode.NONE,
        0
    )
    self.input.inputMode = ui.InputFieldKeyHandlingMode.DEFAULT
    self.input.contentMargin = ui.Margin.new(8, 3, 4, 0)
    self.input.text.font = id.Font.MUSEO_SANS_15PT_REGULAR
    self.input.text.rgba = TEXT_COLOUR
    self.input.text.isShadowed = true
    self.input.emptyTextRGBA = DISABLED_TEXT_COLOUR
    self.input.caretRGBA = 0xFFFFFFFF
    self.input.selectionHighlightRGBA = SELECTED_COLOUR
    self.input.containerSprite.alpha = 0

    self.button = ui.Layer.new(self.root)
    self.button:SetPos(-BUTTON_WIDTH, 0, 1.0, 0)
    self.button:SetSize(BUTTON_WIDTH, 0, 0, 1.0)
    self.button.clickthrough = false
    self.input:MoveToFront()
    self.button:MoveToFront()

    self.dropdown = ui.Layer.new(parent)
    self.dropdown:SetPos(4, 4 + HEIGHT)
    self.dropdown:SetSize(WIDTH, MAX_VISIBLE_ROWS * ROW_HEIGHT + 2)
    self.dropdown.clickthrough = false
    self.dropdown.hidden = true
    self.dropdownBackground = rectangle(self.dropdown, BACKGROUND_COLOUR)
    self.dropdownFrame = {
        frameEdge(self.dropdown, 0, 0, 0, 1, 0, 0, 1.0, 0),
        frameEdge(self.dropdown, 0, -1, 0, 1, 0, 1.0, 1.0, 0),
        frameEdge(self.dropdown, 0, 0, 1, 0, 0, 0, 0, 1.0),
        frameEdge(self.dropdown, -1, 0, 1, 0, 1.0, 0, 0, 1.0),
    }

    for index, region in ipairs(self.regions) do
        local row = { region = region, matches = true }
        row.root = ui.Layer.new(self.dropdown)
        row.root:SetPos(1, 1 + (index - 1) * ROW_HEIGHT)
        row.root:SetSize(-2, ROW_HEIGHT, 1.0, 0)
        row.root.clickthrough = false
        row.background = rectangle(row.root,
            region.id == self.selectedID and SELECTED_COLOUR or 0x00000000)
        row.label = ui.Text.new(row.root)
        row.label:SetPos(8, 0)
        row.label:SetSize(-14, ROW_HEIGHT, 1.0, 0)
        row.label.content = region.label
        row.label.font = id.Font.MUSEO_SANS_15PT_REGULAR
        row.label.rgba = TEXT_COLOUR
        row.label.isShadowed = true
        row.label.maxLines = 1
        row.label.alignVertical = ui.AlignMode.CENTRE
        row.label.clickthrough = true
        row.root:Subscribe(ui.Hook.ONMOUSEOVER, function()
            row.background.rgba = region.id == self.selectedID
                and SELECTED_COLOUR or HOVER_COLOUR
            return true
        end)
        row.root:Subscribe(ui.Hook.ONMOUSELEAVE, function()
            row.background.rgba = region.id == self.selectedID
                and SELECTED_COLOUR or 0x00000000
            return true
        end)
        row.root:Subscribe(ui.Hook.ONCLICK, function()
            self:Select(region.id)
            self:Close()
            return false
        end)
        row.root:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, delta)
            self:Scroll(delta)
            return false
        end)
        self.rows[index] = row
    end

    self.scrollTrack = rectangle(self.dropdown, SCROLL_TRACK_COLOUR)
    self.scrollTrack:SetPos(-SCROLLBAR_RIGHT - SCROLLBAR_WIDTH,
        SCROLLBAR_MARGIN, 1.0, 0)
    self.scrollThumb = rectangle(self.dropdown, SCROLL_THUMB_COLOUR)
    self.scrollThumb:SetPos(-SCROLLBAR_RIGHT - SCROLLBAR_WIDTH,
        SCROLLBAR_MARGIN, 1.0, 0)

    self.dropdown:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, delta)
        self:Scroll(delta)
        return false
    end)

    self.input:Subscribe(ui.Hook.ONCLICK, function()
        self:Open()
        return false
    end)
    self.button:Subscribe(ui.Hook.ONCLICK, function()
        if self.open then self:Close() else self:Open() end
        return false
    end)
    self.input:Subscribe(ui.Hook.ONCONTENTCHANGED, function(_, reason, content)
        for index, pending in ipairs(self.pendingContents) do
            if pending == content then
                for _ = 1, index do table.remove(self.pendingContents, 1) end
                return false
            end
        end
        if reason == ui.InputFieldActionResult.SUBMIT_ON_ESCAPE then
            self:Close()
            return false
        end
        if reason == ui.InputFieldActionResult.SUBMIT_ON_FOCUS_LOSS then
            if not self.dropdown.isMouseOver and not self.button.isMouseOver then
                self:Close()
            end
            return false
        end
        self:Filter(content)
        if reason == ui.InputFieldActionResult.SUBMIT then
            local firstMatch = self.matchingRows and self.matchingRows[1]
            if firstMatch then self:Select(firstMatch.region.id) end
            self:Close()
        elseif not self.open then
            self:Open(false)
        end
        return false
    end)

    self:SetInput(self.selectedLabel)
    return self
end

function RegionPicker:SetInput(value)
    local content = tostring(value or "")
    if self.input.content == content then return end
    self.pendingContents[#self.pendingContents + 1] = content
    self.input.content = content
end

function RegionPicker:Filter(value)
    local query = string.lower(tostring(value or ""))
    local matches = {}
    for _, row in ipairs(self.rows) do
        row.matches = query == ""
            or string.find(string.lower(row.region.label), query, 1, true) ~= nil
        row.root.hidden = true
        if row.matches then matches[#matches + 1] = row end
    end

    self.matchingRows = matches
    self.scrollOffset = math.max(0, math.min(
        self.scrollOffset,
        #matches - MAX_VISIBLE_ROWS
    ))
    local displayed = math.min(#matches, MAX_VISIBLE_ROWS)
    for index = 1, displayed do
        local row = matches[self.scrollOffset + index]
        row.root.hidden = false
        row.root:SetPos(1, 1 + (index - 1) * ROW_HEIGHT)
    end
    self.dropdown:SetSize(WIDTH, math.max(1, displayed * ROW_HEIGHT) + 2)
    self:_UpdateScrollbar(displayed)
end

function RegionPicker:_UpdateScrollbar(displayed)
    local matches = self.matchingRows or {}
    local visible = #matches > displayed and displayed > 0
    self.scrollTrack.hidden = not visible
    self.scrollThumb.hidden = not visible
    if not visible then return end

    local trackHeight = math.max(1,
        displayed * ROW_HEIGHT - SCROLLBAR_MARGIN * 2)
    local thumbHeight = math.max(MIN_THUMB_HEIGHT,
        math.floor(trackHeight * displayed / #matches + 0.5))
    local maximum = #matches - displayed
    local thumbTravel = math.max(0, trackHeight - thumbHeight)
    local thumbY = SCROLLBAR_MARGIN
        + math.floor(thumbTravel * self.scrollOffset / maximum + 0.5)

    self.scrollTrack:SetSize(SCROLLBAR_WIDTH, trackHeight)
    self.scrollThumb:SetPos(-SCROLLBAR_RIGHT - SCROLLBAR_WIDTH,
        thumbY, 1.0, 0)
    self.scrollThumb:SetSize(SCROLLBAR_WIDTH, thumbHeight)
    self.scrollTrack:MoveToFront()
    self.scrollThumb:MoveToFront()
end

function RegionPicker:Scroll(delta)
    local matches = self.matchingRows or {}
    local maximum = math.max(0, #matches - MAX_VISIBLE_ROWS)
    local direction = delta > 0 and 1 or (delta < 0 and -1 or 0)
    local nextOffset = math.max(0, math.min(maximum, self.scrollOffset + direction))
    if nextOffset == self.scrollOffset then return false end
    self.scrollOffset = nextOffset
    self:Filter(self.input.content)
    return true
end

function RegionPicker:Open(clearInput)
    self.open = true
    self.scrollOffset = 0
    if clearInput ~= false then self:SetInput("") end
    self:Filter(self.input.content)
    self.dropdown.hidden = false
    self.dropdown:MoveToFront()
end

function RegionPicker:Close()
    self.open = false
    self.dropdown.hidden = true
    self:SetInput(self.selectedLabel)
end

function RegionPicker:Select(entryID)
    local selected
    for _, row in ipairs(self.rows) do
        if row.region.id == entryID then selected = row.region end
    end
    if not selected then return false end
    self.selectedID = selected.id
    self.selectedLabel = selected.label
    for _, row in ipairs(self.rows) do
        row.background.rgba = row.region.id == self.selectedID
            and SELECTED_COLOUR or 0x00000000
    end
    self:SetInput(selected.label)
    local _, minimumZoom, maximumZoom = self.map:GetZoom()
    self.map:SetZoom(math.min(minimumZoom + 2, maximumZoom))
    self.map:ShowCoordinate(Helpers.NewCoordGrid(
        selected.x,
        selected.z,
        selected.level or 0
    ))
    return true
end

function RegionPicker:Destroy()
    self.map = nil
    if self.dropdown then self.dropdown:Destroy() self.dropdown = nil end
    if self.root then self.root:Destroy() self.root = nil end
    self.rows = {}
    self.matchingRows = {}
    self.pendingContents = {}
end

return RegionPicker
