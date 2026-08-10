package.path = "./?.lua;./?/init.lua;" .. package.path

local function component()
    local value = {
        hooks = {},
        text = {},
        containerSprite = {},
        width = 0,
        height = 0,
    }
    function value:SetPos(x, y) self.x, self.y = x, y end
    function value:SetSize(width, height) self.width, self.height = width, height end
    function value:Setup() self.setup = true end
    function value:Subscribe(hook, callback) self.hooks[hook] = callback end
    function value:MoveToFront() self.movedToFront = true end
    function value:Add(label, id) self.entry = { label = label, id = id } return true end
    function value:Select(id) self.selectedID = id return true end
    function value:Destroy() self.destroyed = true end
    return value
end

ui = {
    Layer = { new = function() return component() end },
    Rectangle = { new = function() return component() end },
    Text = { new = function() return component() end },
    ComboField = { new = function() return component() end },
    InputField = { new = function() return component() end },
    Margin = { new = function() return {} end },
    Hook = {
        ONCLICK = "click",
        ONMOUSEOVER = "mouseover",
        ONMOUSELEAVE = "mouseleave",
        ONCONTENTCHANGED = "content_changed",
        ONSCROLLWHEEL = "scrollwheel",
    },
    TextContentVisibilityMode = { VISIBLE = 1 },
    InputFieldFilterMode = { NONE = 1 },
    InputFieldKeyHandlingMode = { DEFAULT = 1 },
    InputFieldActionResult = {
        CONTENT_CHANGE = 1,
        SUBMIT = 2,
        SUBMIT_ON_ESCAPE = 3,
        SUBMIT_ON_FOCUS_LOSS = 4,
    },
    AlignMode = { CENTRE = 1 },
}
id = {
    StyleSheet = { COMBO_DEFAULT = 1, INPUT_DEFAULT = 2 },
    Font = { MUSEO_SANS_15PT_REGULAR = 1 },
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

local centred, zoomed = {}, {}
local map = {
    GetZoom = function() return 9, 6, 9 end,
    SetZoom = function(_, index)
        zoomed[#zoomed + 1] = index
        return true
    end,
    ShowCoordinate = function(_, coordinate)
        centred[#centred + 1] = coordinate
        return true
    end,
}

local RegionPicker = require("src/region_picker")
local picker = RegionPicker.new(component(), map)

assert(picker.root.x == 4 and picker.root.y == 4
    and picker.root.width == 180 and picker.root.height == 32,
    "the picker should occupy the map's upper-left control slot")
assert(picker.shell.stylesheetID == id.StyleSheet.COMBO_DEFAULT
    and picker.input.stylesheetID == id.StyleSheet.INPUT_DEFAULT,
    "the picker should retain native ComboBox styling")
assert(picker.regions[1].label == "Runescape Surface"
    and picker.regions[2].label == "Havenhythe"
    and picker.regions[3].label == "Anachronia"
    and picker.regions[4].label == "Braindeath isle"
    and picker.regions[5].label == "Ancient cavern"
    and picker.regions[6].label == "Ardougne Underground"
    and picker.regions[39].label == "Zanaris"
    and #picker.regions == 39,
    "explicitly ordered surface entries should precede underground entries")
for index = 6, #picker.regions do
    assert(picker.regions[index - 1].label < picker.regions[index].label,
        "underground entries should be sorted alphabetically")
end

local function regionByID(entryID)
    for _, region in ipairs(picker.regions) do
        if region.id == entryID then return region end
    end
end

local correctedCentres = {
    [5] = { 2623, 9695 },
    [6] = { 2411, 4451 },
    [15] = { 2720, 9535 },
    [16] = { 2505, 10256 },
    [19] = { 2879, 9759 },
    [23] = { 3359, 9407 },
    [26] = { 3034, 9576 },
    [33] = { 1764, 5350 },
    [34] = { 2207, 5663 },
    [36] = { 3520, 9824 },
    [39] = { 2975, 1631 },
}
for entryID, coordinate in pairs(correctedCentres) do
    local region = regionByID(entryID)
    assert(region.x == coordinate[1] and region.z == coordinate[2],
        region.label .. " should target the rendered area's interior")
end

picker.button.hooks[ui.Hook.ONCLICK]()
assert(picker.open and not picker.dropdown.hidden and picker.dropdown.movedToFront,
    "opening should render the popup above the map")
assert(picker.dropdown.height == 194
    and not picker.rows[1].root.hidden
    and not picker.rows[8].root.hidden
    and picker.rows[9].root.hidden
    and not picker.scrollTrack.hidden
    and not picker.scrollThumb.hidden
    and picker.scrollThumb.height >= 16,
    "the popup should show an eight-row viewport and scroll indicator")
local initialThumbY = picker.scrollThumb.y
picker.rows[1].root.hooks[ui.Hook.ONSCROLLWHEEL](picker.rows[1].root, 1)
assert(picker.scrollOffset == 1
    and picker.rows[1].root.hidden
    and not picker.rows[9].root.hidden
    and picker.scrollThumb.y > initialThumbY,
    "positive wheel movement should scroll down and move the indicator")
picker.rows[2].root.hooks[ui.Hook.ONSCROLLWHEEL](picker.rows[2].root, -1)
assert(picker.scrollOffset == 0 and picker.scrollThumb.y == initialThumbY,
    "negative wheel movement should scroll back up")
picker.input.hooks[ui.Hook.ONCONTENTCHANGED](
    picker.input, ui.InputFieldActionResult.CONTENT_CHANGE, "anach"
)
assert(not picker.rows[3].root.hidden
    and picker.rows[1].root.hidden
    and picker.rows[2].root.hidden
    and picker.rows[4].root.hidden,
    "typing should filter region rows")
assert(picker.dropdown.height == 26,
    "a filtered popup should shrink to the matching rows")
assert(picker.scrollTrack.hidden and picker.scrollThumb.hidden,
    "the scroll indicator should hide when every match fits")

picker.rows[3].root.hooks[ui.Hook.ONCLICK]()
assert(not picker.open and picker.dropdown.hidden
    and picker.selectedID == 3 and picker.selectedLabel == "Anachronia",
    "clicking a row should select it and close the popup")
assert(centred[1].x == 5430 and centred[1].z == 2330 and centred[1].level == 0,
    "selection should centre the map on the region")
assert(zoomed[1] == 8,
    "selection should set the map to displayed zoom level three")
assert(picker:Select(7)
    and centred[2].x == 2822 and centred[2].z == 10087
    and centred[2].level == 2,
    "underground selections should retain their world-map plane")

local root, dropdown = picker.root, picker.dropdown
picker:Destroy()
assert(root.destroyed and dropdown.destroyed and picker.map == nil,
    "the PrettyMap-owned picker should destroy its own native trees")

print("region picker tests passed")
