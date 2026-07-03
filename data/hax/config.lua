-- config.lua - Persistent user preferences for cheatgui
-- Uses Noita's GlobalsSetValue/GlobalsGetValue (survives game restarts)
-- All values stored as strings, converted to proper types on load.

_config = {
    -- Namespace prefix for Globals keys to avoid conflicts
    prefix = "cheatgui.config.",

    -- Default values (used when no saved value exists)
    defaults = {
        language            = "zh",
        show_localized_names = true,
    },
}

-- Load all config values from Globals into _config.values
function _config:load()
    if self.values then return end  -- Already loaded
    self.values = {}
    for key, default in pairs(self.defaults) do
        self.values[key] = self:_read(key, default)
    end
end

-- Save a single value immediately
function _config:set(key, value)
    self.values[key] = value
    GlobalsSetValue(self.prefix .. key, tostring(value))
end

-- Get a value (returns default if not loaded/not found)
function _config:get(key)
    if not self.values then return self.defaults[key] end
    local v = self.values[key]
    if v ~= nil then return v end
    return self.defaults[key]
end

-- Save all current values
function _config:save_all()
    for key, value in pairs(self.values) do
        GlobalsSetValue(self.prefix .. key, tostring(value))
    end
end

-- Internal: read a single value from Globals with type conversion
function _config:_read(key, default)
    local raw = GlobalsGetValue(self.prefix .. key)
    if raw == nil or raw == "" then return default end
    -- Convert string to match the type of the default value
    if type(default) == "boolean" then
        return (raw == "true")
    elseif type(default) == "number" then
        return tonumber(raw) or default
    end
    return raw  -- string
end
