local Helpers = {}

function Helpers.Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

function Helpers.Rounded(value)
    return math.floor(value + 0.5)
end

function Helpers.RemoveValue(values, target)
    for index = #values, 1, -1 do
        if values[index] == target then
            table.remove(values, index)
            return true
        end
    end
    return false
end

function Helpers.Integer(value, name)
    assert(type(value) == "number" and value % 1 == 0,
        name .. " must be an integer")
    return value
end

function Helpers.PositiveInteger(value, name)
    Helpers.Integer(value, name)
    assert(value > 0, name .. " must be greater than zero")
    return value
end

function Helpers.CoordGridValues(coordinate, name)
    name = name or "coordinate"
    assert(coordinate ~= nil, name .. " must be a CoordGrid")
    local x = Helpers.Integer(coordinate.x, name .. ".x")
    local z = Helpers.Integer(coordinate.z, name .. ".z")
    local level = Helpers.Integer(coordinate.level, name .. ".level")
    return x, z, level
end

function Helpers.NewCoordGrid(x, z, level)
    x = Helpers.Integer(x, "coordinate.x")
    z = Helpers.Integer(z, "coordinate.z")
    level = Helpers.Integer(level, "coordinate.level")
    return CoordGrid.new(level, x // 64, z // 64, x % 64, z % 64)
end

function Helpers.CopyCoordGrid(coordinate, name)
    local x, z, level = Helpers.CoordGridValues(coordinate, name)
    return Helpers.NewCoordGrid(x, z, level)
end

function Helpers.CoordGridsEqual(left, right)
    if left == nil or right == nil then return left == right end
    return left.x == right.x and left.z == right.z and left.level == right.level
end

function Helpers.BindMethods(owner, source, names)
    assert(type(names) == "table", "an explicit method list is required")
    local api = {}
    for _, name in ipairs(names) do
        local method = source[name]
        assert(type(method) == "function", "missing map method: " .. tostring(name))
        api[name] = function(_, ...)
            return method(owner, ...)
        end
    end
    return api
end

return Helpers
