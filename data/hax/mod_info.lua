-- =============================================================================
-- mod_info.lua - 模组信息面板
-- =============================================================================
-- 显示已激活模组列表、API版本、构建类型等
-- API: ModGetActiveModIDs, ModIsEnabled, ModGetAPIVersion, GameIsBetaBuild
-- =============================================================================

local _mi_cached_mods = nil

-- 获取已激活的模组列表
local function get_active_mods()
  if _mi_cached_mods then return _mi_cached_mods end
  local mods = {}
  local ok, ids = pcall(ModGetActiveModIDs)
  if ok and ids then
    for _, id in ipairs(ids) do
      table.insert(mods, id)
    end
  end
  _mi_cached_mods = mods
  return mods
end

-- 获取API版本
local function get_api_version()
  local ok, ver = pcall(ModGetAPIVersion)
  if ok and ver then return tostring(ver) end
  return "?"
end

-- 检查是否为Beta构建
local function is_beta()
  local ok, result = pcall(GameIsBetaBuild)
  if ok and result then return "是" end
  return "否"
end

-- 检查是否为开发版
local function is_dev_build()
  local ok, result = pcall(DebugGetIsDevBuild)
  if ok and result then return "是" end
  return "否"
end

-- 检查特定模组是否启用
local function check_mod_enabled(mod_id)
  if not mod_id or mod_id == "" then return end
  local ok, enabled = pcall(ModIsEnabled, mod_id)
  if ok then
    GamePrint(mod_id .. ": " .. (enabled and "已启用" or "未启用"))
  else
    GamePrint("无法检查模组: " .. mod_id)
  end
end

-- =============================================================================
-- UI 面板
-- =============================================================================

mod_info_panel = Panel{function() return T("panel_mod_info") end, function()
  breadcrumbs(1, 0)
  GuiLayoutBeginVertical(gui, 1, 11)

  -- 游戏环境信息
  GuiText(gui, 0, 0, "---- 环境信息 ----")
  GuiText(gui, 0, 0, "API 版本: " .. get_api_version())
  GuiText(gui, 0, 0, "Beta 构建: " .. is_beta())
  -- GuiText(gui, 0, 0, "开发版: " .. is_dev_build()) -- DebugGetIsDevBuild 可能在发布版不可用

  -- 当前运行的Lua环境信息
  GuiText(gui, 0, 0, " ")
  GuiText(gui, 0, 0, "---- 已加载模块 ----")
  GuiText(gui, 0, 0, "cheatgui 版本: 1.7.3")
  GuiText(gui, 0, 0, "键盘支持: " .. (_keyboard_present and "是" or "否"))

  -- 已激活模组列表
  GuiText(gui, 0, 0, " ")
  GuiText(gui, 0, 0, "---- 已激活模组 ----")

  local mods = get_active_mods()
  if #mods == 0 then
    GuiText(gui, 0, 0, "(无模组或无法读取)")
  else
    GuiText(gui, 0, 0, "共 " .. #mods .. " 个模组:")
    for _, mod_id in ipairs(mods) do
      -- 标记当前模组
      local marker = (mod_id == "cheatgui" or mod_id:lower():find("cheatgui")) and " (*)" or ""
      GuiText(gui, 0, 0, "  " .. mod_id .. marker)
    end
  end

  -- 刷新按钮
  GuiText(gui, 0, 0, " ")
  if GuiButton(gui, 0, 0, "[刷新列表]", next_id()) then
    _mi_cached_mods = nil
    GamePrint("模组列表已刷新")
  end

  GuiLayoutEnd(gui)
end}
