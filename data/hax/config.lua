-- =============================================================================
-- config.lua - CheatGUI 持久化用户偏好配置模块
-- =============================================================================
-- 使用 Noita 的 GlobalsSetValue / GlobalsGetValue API 实现持久化存储。
-- 配置值在游戏重启后仍然保留，以字符串形式存储，读取时自动转换回原始类型。
-- =============================================================================

_config = {
    -- 命名空间前缀，用于 Globals 键名，避免与其他模组的键冲突
    prefix = "cheatgui.config.",

    -- 默认值（当没有已保存的配置值时使用）
    defaults = {
        language            = "zh",    -- 界面语言："zh" 中文 / "en" 英文
        show_localized_names = true,   -- 是否显示游戏本地化名称
    },
}

-- 从 Globals 加载所有配置值到 _config.values 中
-- 首次调用时加载并缓存，后续调用直接返回（避免重复读取）
function _config:load()
    if self.values then return end  -- 已加载，跳过
    self.values = {}
    for key, default in pairs(self.defaults) do
        self.values[key] = self:_read(key, default)
    end
end

-- 立即保存单个配置值（同时写入内存和 Globals，确保持久化）
function _config:set(key, value)
    self.values[key] = value
    GlobalsSetValue(self.prefix .. key, tostring(value))
end

-- 获取一个配置值（未加载或未找到时返回默认值）
function _config:get(key)
    if not self.values then return self.defaults[key] end
    local v = self.values[key]
    if v ~= nil then return v end
    return self.defaults[key]
end

-- 保存所有当前值到 Globals（批量持久化）
function _config:save_all()
    for key, value in pairs(self.values) do
        GlobalsSetValue(self.prefix .. key, tostring(value))
    end
end

-- 内部方法：从 Globals 读取单个值，并根据默认值类型自动转换
-- GlobalsSetValue 只能存储字符串，所以读取时需要还原类型
function _config:_read(key, default)
    local raw = GlobalsGetValue(self.prefix .. key)
    if raw == nil or raw == "" then return default end
    -- 根据默认值的类型，将字符串转换回正确的类型
    if type(default) == "boolean" then
        return (raw == "true")        -- 布尔值：字符串 "true" → true
    elseif type(default) == "number" then
        return tonumber(raw) or default  -- 数值：字符串转数字
    end
    return raw  -- 字符串：直接返回
end
