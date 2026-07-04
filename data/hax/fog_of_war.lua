-- =============================================================================
-- fog_of_war.lua - 战争迷雾控制面板
-- =============================================================================
-- 查看迷雾覆盖率、一键清除全图迷雾、设置自定义迷雾值
-- API: GameGetFogOfWar, GameSetFogOfWar, GameGetFogOfWarBilinear
-- =============================================================================

local fog_value = 0.0

-- 获取当前迷雾值
local function get_fog_value()
  local ok, val = pcall(GameGetFogOfWar)
  if ok and val then
    fog_value = tonumber(val) or 0.0
    return fog_value
  end
  return nil
end

-- 设置迷雾
local function set_fog_value(val)
  local ok, _ = pcall(GameSetFogOfWar, val)
  if ok then
    fog_value = val
    GamePrint("迷雾设置为: " .. string.format("%.2f", val))
  else
    GamePrint("设置迷雾失败")
  end
end

-- 清除全部迷雾
local function clear_fog()
  set_fog_value(1.0)
end

-- 恢复迷雾
local function restore_fog()
  set_fog_value(0.0)
end

-- 半透明迷雾
local function half_fog()
  set_fog_value(0.5)
end

-- =============================================================================
-- UI 面板
-- =============================================================================

fog_of_war_panel = Panel{function() return T("panel_fog_of_war") end, function()
  breadcrumbs(1, 0)
  GuiLayoutBeginVertical(gui, 1, 11)

  -- 当前迷雾状态
  local current_fog = get_fog_value()
  local fog_pct = (current_fog or 0) * 100
  GuiText(gui, 0, 0, "当前迷雾: " .. (current_fog and string.format("%.2f", current_fog) or "?")
    .. " (" .. string.format("%.0f", fog_pct) .. "%)")

  -- 迷雾等级指示（进度条模拟）
  local bar_width = 20
  local filled = math.floor((current_fog or 0) * bar_width)
  local bar = "["
  for i = 1, bar_width do
    bar = bar .. (i <= filled and "#" or "-")
  end
  bar = bar .. "]"
  GuiText(gui, 0, 0, bar)

  GuiText(gui, 0, 0, " ")
  GuiText(gui, 0, 0, "---- 快速操作 ----")

  -- 操作按钮
  GuiLayoutBeginHorizontal(gui, 0, 0)
  if GuiButton(gui, 0, 0, "[全图可见 (1.0)]", next_id()) then
    clear_fog()
  end
  GuiLayoutEnd(gui)

  GuiLayoutBeginHorizontal(gui, 0, 0)
  if GuiButton(gui, 0, 0, "[半透明 (0.5)]", next_id()) then
    half_fog()
  end
  GuiLayoutEnd(gui)

  GuiLayoutBeginHorizontal(gui, 0, 0)
  if GuiButton(gui, 0, 0, "[恢复迷雾 (0.0)]", next_id()) then
    restore_fog()
  end
  GuiLayoutEnd(gui)

  GuiText(gui, 0, 0, " ")
  GuiText(gui, 0, 0, "---- 自定义 ----")

  -- 自定义值按钮
  GuiLayoutBeginHorizontal(gui, 0, 0)
  if GuiButton(gui, 0, 0, "[0.25]", next_id()) then set_fog_value(0.25) end
  if GuiButton(gui, 0, 0, "[0.50]", next_id()) then set_fog_value(0.50) end
  if GuiButton(gui, 0, 0, "[0.75]", next_id()) then set_fog_value(0.75) end
  if GuiButton(gui, 0, 0, "[0.90]", next_id()) then set_fog_value(0.90) end
  GuiLayoutEnd(gui)

  -- 刷新
  GuiText(gui, 0, 0, " ")
  if GuiButton(gui, 0, 0, "[刷新当前值]", next_id()) then
    get_fog_value()
  end

  GuiLayoutEnd(gui)
end}
