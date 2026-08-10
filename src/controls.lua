local Controls = {}
local RegionPicker = require("src/region_picker")

local TEXT_COLOUR = 0xE7D7B0FF
local BORDER_SIZE = 4
local PANEL_BACKGROUND_ALPHA = 0.82

local SPRITES = {
    panel = {
        content = id.Sprite.RS3_HUD_WINDOW_CONTENT_TILE,
        top = id.Sprite.RS3_HUD_WINDOW_TOP_TILE,
        bottom = id.Sprite.RS3_HUD_WINDOW_BOTTOM_TILE,
        side = id.Sprite.RS3_HUD_WINDOW_SIDE_TILE,
        cornerTop = id.Sprite.RS3_HUD_WINDOW_CORNER_TOP,
        cornerBottom = id.Sprite.RS3_HUD_WINDOW_CORNER_BOTTOM,
    },
    floorDown = {
        disabled = id.Sprite.RS3_ICON_DIRECTION_DESCEND_32PX_4,
        neutral = id.Sprite.RS3_ICON_DIRECTION_DESCEND_32PX_2,
        active = id.Sprite.RS3_ICON_DIRECTION_DESCEND_32PX_3,
    },
    floorUp = {
        disabled = id.Sprite.RS3_ICON_DIRECTION_ASCEND_32PX_4,
        neutral = id.Sprite.RS3_ICON_DIRECTION_ASCEND_32PX_2,
        active = id.Sprite.RS3_ICON_DIRECTION_ASCEND_32PX_3,
    },
    zoomOut = {
        disabled = id.Sprite.RS3_BTN_DECREASE_DISABLED,
        neutral = id.Sprite.RS3_BTN_DECREASE_ACTIVE,
        active = id.Sprite.RS3_BTN_DECREASE_OVER,
    },
    zoomIn = {
        disabled = id.Sprite.RS3_BTN_INCREASE_DISABLED,
        neutral = id.Sprite.RS3_BTN_INCREASE_ACTIVE,
        active = id.Sprite.RS3_BTN_INCREASE_OVER,
    },
}

local function button(parent, states, action, x, size)
    local control = {
        disabled = false,
        hovered = false,
        pressed = false,
        action = action,
    }
    control.root = ui.Sprite.new(parent)
    control.root:SetPos(x, 0)
    control.root:SetSize(size, size)

    function control:Refresh()
        self.root.enabled = not self.disabled
        self.root.clickthrough = self.disabled
        if self.disabled then
            self.root.spriteID = states.disabled
        elseif self.hovered or self.pressed then
            self.root.spriteID = states.active
        else
            self.root.spriteID = states.neutral
        end
    end

    function control:SetDisabled(disabled)
        self.disabled = disabled == true
        self.hovered = false
        self.pressed = false
        self:Refresh()
    end

    control.root:Subscribe(ui.Hook.ONMOUSEOVER, function()
        if control.disabled then return false end
        control.hovered = true
        control:Refresh()
        return true
    end)
    control.root:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        control.hovered = false
        control.pressed = false
        control:Refresh()
        return true
    end)
    control.root:Subscribe(ui.Hook.ONCLICK, function()
        if control.disabled then return false end
        control.pressed = true
        control:Refresh()
        return false
    end)
    control.root:Subscribe(ui.Hook.ONRELEASE, function()
        local activate = control.pressed and not control.disabled
        control.pressed = false
        control:Refresh()
        if activate then control.action() end
        return false
    end)
    control:Refresh()
    return control
end

local function panel(parent, y, height)
    local surface = {}
    local function decoration(spriteID)
        local value = ui.Sprite.new(surface.root)
        value.spriteID = spriteID
        value.clickthrough = true
        return value
    end

    surface.root = ui.Layer.new(parent)
    surface.root:SetPos(-84, y, 1.0)
    surface.root:SetSize(80, height)
    surface.root.clickthrough = false

    surface.background = decoration(SPRITES.panel.content)
    surface.background:SetPos(BORDER_SIZE, BORDER_SIZE)
    surface.background:SetSize(-BORDER_SIZE * 2, -BORDER_SIZE * 2, 1.0, 1.0)
    surface.background.isTiling = true
    surface.background.alpha = PANEL_BACKGROUND_ALPHA
    surface.background.clickthrough = false

    surface.top = decoration(SPRITES.panel.top)
    surface.top:SetPos(BORDER_SIZE, 0)
    surface.top:SetSize(-BORDER_SIZE * 2, BORDER_SIZE, 1.0)
    surface.top.isTiling = true

    surface.bottom = decoration(SPRITES.panel.bottom)
    surface.bottom:SetPos(BORDER_SIZE, -BORDER_SIZE, 0, 1.0)
    surface.bottom:SetSize(-BORDER_SIZE * 2, BORDER_SIZE, 1.0)
    surface.bottom.isTiling = true

    surface.left = decoration(SPRITES.panel.side)
    surface.left:SetPos(0, BORDER_SIZE)
    surface.left:SetSize(BORDER_SIZE, -BORDER_SIZE * 2, 0, 1.0)
    surface.left.isTiling = true

    surface.right = decoration(SPRITES.panel.side)
    surface.right:SetPos(-BORDER_SIZE, BORDER_SIZE, 1.0)
    surface.right:SetSize(BORDER_SIZE, -BORDER_SIZE * 2, 0, 1.0)
    surface.right.isTiling = true
    surface.right.isFlippedHorizontally = true

    surface.topLeft = decoration(SPRITES.panel.cornerTop)
    surface.topLeft:SetSize(BORDER_SIZE, BORDER_SIZE)

    surface.topRight = decoration(SPRITES.panel.cornerTop)
    surface.topRight:SetPos(-BORDER_SIZE, 0, 1.0)
    surface.topRight:SetSize(BORDER_SIZE, BORDER_SIZE)
    surface.topRight.isFlippedHorizontally = true

    surface.bottomLeft = decoration(SPRITES.panel.cornerBottom)
    surface.bottomLeft:SetPos(0, -BORDER_SIZE, 0, 1.0)
    surface.bottomLeft:SetSize(BORDER_SIZE, BORDER_SIZE)

    surface.bottomRight = decoration(SPRITES.panel.cornerBottom)
    surface.bottomRight:SetPos(-BORDER_SIZE, -BORDER_SIZE, 1.0, 1.0)
    surface.bottomRight:SetSize(BORDER_SIZE, BORDER_SIZE)
    surface.bottomRight.isFlippedHorizontally = true

    surface.container = ui.Layer.new(surface.root)
    surface.container:SetPos(BORDER_SIZE, BORDER_SIZE)
    surface.container:SetSize(-BORDER_SIZE * 2, -BORDER_SIZE * 2, 1.0, 1.0)
    surface.container.clickthrough = false
    surface.container.enabled = true

    return surface
end

local function label(parent, x, width, height)
    local value = ui.Text.new(parent)
    value:SetPos(x, 0)
    value:SetSize(width, height)
    value.font = id.Font.MUSEO_SANS_15PT_REGULAR
    value.rgba = TEXT_COLOUR
    value.isShadowed = true
    value.alignHorizontal = ui.AlignMode.CENTRE
    value.alignVertical = ui.AlignMode.CENTRE
    value.clickthrough = true
    return value
end

function Controls.Floor(parent, map)
    local control = { surface = panel(parent, 4, 32) }
    control.root = control.surface.root
    control.down = button(control.surface.container, SPRITES.floorDown, function()
        map:SetPlane(map:GetPlane() - 1)
    end, 0, 24)
    control.text = label(control.surface.container, 24, 24, 24)
    control.up = button(control.surface.container, SPRITES.floorUp, function()
        map:SetPlane(map:GetPlane() + 1)
    end, 48, 24)
    function control:Refresh()
        local floor = map:GetPlane()
        self.text.content = tostring(floor)
        self.down:SetDisabled(floor <= 0)
        self.up:SetDisabled(floor >= 3)
    end
    control:Refresh()
    return control
end

function Controls.Zoom(parent, map)
    local control = { surface = panel(parent, 40, 31) }
    control.root = control.surface.root
    control.out = button(control.surface.container, SPRITES.zoomOut, function() map:ZoomOut() end, 0, 23)
    control.text = label(control.surface.container, 23, 26, 23)
    control.inside = button(control.surface.container, SPRITES.zoomIn, function() map:ZoomIn() end, 49, 23)
    function control:Refresh()
        local index, minimum, maximum = map:GetZoom()
        self.text.content = tostring(index - minimum + 1)
        self.out:SetDisabled(index <= minimum)
        self.inside:SetDisabled(index >= maximum)
    end
    control:Refresh()
    return control
end

function Controls.Region(parent, map)
    return RegionPicker.new(parent, map)
end

return Controls
