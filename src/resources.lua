local Resources = {}
local resolutionCache = {}
local missingPaths = {}
local referenceCounts = setmetatable({}, { __mode = "k" })
local cachedResourceRoot

local function resetResolutionCacheIfNeeded()
    local root = Plugin and Plugin.resources or nil
    if root ~= cachedResourceRoot then
        cachedResourceRoot = root
        resolutionCache = {}
        missingPaths = {}
    end
end

local function accessibleField(value, fieldName)
    local succeeded, field = pcall(function() return value[fieldName] end)
    return succeeded and field ~= nil
end

local function isPluginResource(value)
    local valueType = type(value)
    if value == nil or valueType == "number" or valueType == "string"
        or valueType == "boolean" then
        return false
    end
    if valueType == "userdata" then return true end
    return accessibleField(value, "Load")
        or accessibleField(value, "path")
        or accessibleField(value, "loaded")
        or accessibleField(value, "runtimeSprite")
end

local function direct(key)
    local succeeded, resource = pcall(function() return Plugin.resources[key] end)
    if succeeded and isPluginResource(resource) then return resource end
    return nil
end

local function nested(resourceName)
    local succeeded, resource = pcall(function()
        local node = Plugin.resources
        local parts = {}
        for part in resourceName:gmatch("[^/]+") do parts[#parts + 1] = part end
        for index, part in ipairs(parts) do
            local withoutExtension = part:gsub("%.png$", "")
            node = node[part] or node[withoutExtension]
            if node == nil then return nil end
        end
        return node
    end)
    if succeeded and isPluginResource(resource) then return resource end
    return nil
end

local function load(resource)
    local references = referenceCounts[resource]
    if references then
        referenceCounts[resource] = references + 1
        return resource
    end
    local succeeded, loadFunction = pcall(function() return resource.Load end)
    if not succeeded or type(loadFunction) ~= "function" then
        return nil, "Resource does not expose Load()."
    end

    local loaded, result = pcall(function() return resource:Load() end)
    if not loaded then
        return nil, "Resource Load() raised an error: " .. tostring(result)
    end

    local readLoaded, isLoaded = pcall(function() return resource.loaded end)
    if (readLoaded and isLoaded == true) or result == "success"
        or tostring(result) == "success" then
        referenceCounts[resource] = 1
        return resource
    end
    return nil, "Resource Load() failed: " .. tostring(result)
end

function Resources.Image(resourceName)
    if Plugin == nil or Plugin.resources == nil then return nil end
    resetResolutionCacheIfNeeded()

    if missingPaths[resourceName] then
        return nil, "Resource was not found: " .. resourceName
    end

    local withoutExtension = resourceName:gsub("%.png$", "")
    local resource = resolutionCache[resourceName]
    if resource == nil then
        resource = direct(resourceName)
            or direct(withoutExtension)
            or nested(resourceName)
            or nested(withoutExtension)
    end
    if resource == nil then
        missingPaths[resourceName] = true
        return nil, "Resource was not found: " .. resourceName
    end
    resolutionCache[resourceName] = resource
    return load(resource)
end

function Resources.Unload(resource)
    if resource == nil then return end
    local references = referenceCounts[resource]
    if references and references > 1 then
        referenceCounts[resource] = references - 1
        return
    end
    referenceCounts[resource] = nil
    local succeeded, unloadFunction = pcall(function() return resource.Unload end)
    if succeeded and type(unloadFunction) == "function" then
        pcall(function() resource:Unload() end)
    end
end

function Resources.WorldMap()
    local resource, resourceError = Resources.Image("world_map.png")
    if resource then return resource end
    if resourceError and not resourceError:find("not found", 1, true) then
        return nil, resourceError
    end
    return Resources.Image("images/world_map.png")
end

return Resources
