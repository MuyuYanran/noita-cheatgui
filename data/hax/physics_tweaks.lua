-- =============================================================================
-- physics_tweaks.lua - 物理与运动参数面板
-- =============================================================================
-- 修改玩家重力 (pixel_gravity) 和移动速度 (run_velocity)。
-- 两者都是 CharacterPlatformingComponent 的字段。
-- run_velocity 是 LensValue<float>，需要用 ComponentObjectSetValue2 写入。
-- =============================================================================

-- =============================================================================
-- 组件访问辅助函数
-- =============================================================================

local function get_player_plat_comp()
  local player = get_player()
  if not player then return nil end
  local ok, comp = pcall(EntityGetFirstComponent, player, "CharacterPlatformingComponent")
  if ok and comp then return comp end
  return nil
end

-- =============================================================================
-- 自定义数值输入控件
-- =============================================================================
-- 点击数值 → 键盘编辑 → 回车确认，模仿 create_numerical 的交互模式
--
-- 字段：
--   value    -- 当前数值
--   text     -- 编辑中的临时文本
--   editing  -- 是否正在键盘输入
--   step     -- +/- 按钮的步进
--   on_change(value) -- 数值改变时回调
--   on_gain_focus() / on_lose_focus() / on_hit_enter()
--   display_val() -- 编辑时返回 "xxx_" 文本，否则返回 nil

local function number_input(initial_value, step)
  local self = {
    value = initial_value or 0,
    text = "",
    editing = false,
    step = step or 1,
    on_change = nil,
  }
  self.on_gain_focus = function()
    self.editing = true
    self.text = string.format("%.0f", self.value)
  end
  self.on_lose_focus = function()
    self.editing = false
    local num = tonumber(self.text)
    if num and num ~= self.value then
      self.value = num
      if self.on_change then self.on_change(num) end
    end
  end
  self.on_hit_enter = function()
    self.editing = false
    local num = tonumber(self.text)
    if num then
      self.value = num
      if self.on_change then self.on_change(num) end
    end
    set_type_target(nil)
  end
  self.display_val = function()
    if self.editing then return self.text .. "_" end
    return nil
  end
  return self
end

-- 渲染数值输入行：标签 [-减] [显示值] [+加]
local function render_num_input(ni, label, row_id)
  GuiLayoutBeginHorizontal(gui, 0, 0)

  GuiText(gui, 0, 0, label)

  -- [- 减按钮]
  if GuiButton(gui, 0, 0, "[-]", next_id(row_id * 100 + 1)) then
    ni.value = ni.value - ni.step
    if ni.on_change then ni.on_change(ni.value) end
  end

  -- 显示值 / 输入框（点击编辑）
  if GuiButton(gui, 0, 0, (ni:display_val() or string.format("%.0f", ni.value)), next_id(row_id * 100 + 2)) then
    if ni.editing then
      set_type_target(nil)
    else
      ni:on_gain_focus()
      set_type_target(ni)
    end
  end

  -- [+ 加按钮]
  if GuiButton(gui, 0, 0, "[+]", next_id(row_id * 100 + 3)) then
    ni.value = ni.value + ni.step
    if ni.on_change then ni.on_change(ni.value) end
  end

  GuiLayoutEnd(gui)
end

-- 同步更新 number_input 的显示状态（关闭编辑、清空文本、解除焦点）
local function sync_ni(ni, val)
  ni.value = val
  ni.text = ""
  ni.editing = false
  set_type_target(nil)
end

-- =============================================================================
-- 重力控制 (CharacterPlatformingComponent.pixel_gravity)
-- =============================================================================
-- 游戏实际默认 ~350 (用户报告)。组件元数据范围 0-1000。

local GRAVITY_DEFAULT = 350

local function get_current_gravity()
  local comp = get_player_plat_comp()
  if not comp then return nil end
  local ok, val = pcall(ComponentGetValue2, comp, "pixel_gravity")
  if ok and val then return tonumber(val) end
  return nil
end

local gravity_ni = number_input(GRAVITY_DEFAULT, 50)

local function apply_gravity(val)
  local comp = get_player_plat_comp()
  if not comp then
    GamePrint("无法获取玩家平台组件!")
    return
  end
  local ok, _ = pcall(ComponentSetValue2, comp, "pixel_gravity", val)
  if ok then
    GamePrint(string.format("重力设置为: %.0f (%.2fx 默认)", val, val / GRAVITY_DEFAULT))
  else
    GamePrint("设置重力失败")
  end
end

gravity_ni.on_change = function(val)
  apply_gravity(val)
  sync_ni(gravity_ni, val)
end

-- =============================================================================
-- 移动速度控制 (CharacterPlatformingComponent.run_velocity, LensValue<float>)
-- =============================================================================
-- 游戏实际默认 ~95 (用户报告)。需要通过 ComponentObjectSetValue2 写入。

local SPEED_DEFAULT = 95

local function get_current_speed()
  local comp = get_player_plat_comp()
  if not comp then return nil end
  local ok, val = pcall(ComponentGetValue2, comp, "run_velocity", "value")
  if ok and val then return tonumber(val) end
  -- 备用：直接 get
  local ok2, val2 = pcall(ComponentObjectGetValue2, comp, "run_velocity", "value")
  if ok2 and val2 then return tonumber(val2) end
  return nil
end

local function apply_speed(val)
  local comp = get_player_plat_comp()
  if not comp then
    GamePrint("无法获取玩家平台组件!")
    return
  end
  -- run_velocity 是 LensValue<float>，直接调用 ComponentSetValue2
  local ok, err = pcall(ComponentSetValue2, comp, "run_velocity", val)
  if ok then
    GamePrint(string.format("移动速度设置为: %.0f (%.2fx 默认)", val, val / SPEED_DEFAULT))
  else
    GamePrint("设置移动速度失败: " .. tostring(err))
  end
end

local speed_ni = number_input(SPEED_DEFAULT, 10)

speed_ni.on_change = function(val)
  apply_speed(val)
  sync_ni(speed_ni, val)
end

-- =============================================================================
-- UI 面板
-- =============================================================================

physics_tweaks_panel = Panel{function() return T("panel_physics") end, function()
  breadcrumbs(1, 0)
  GuiLayoutBeginVertical(gui, 1, 11)

  -- ====== 重力 ======
  GuiText(gui, 0, 0, "---- " .. (T("physics_gravity") or "重力") .. " (pixel_gravity, 默认 350) ----")

  local current_gravity = get_current_gravity()
  if current_gravity then
    GuiText(gui, 0, 0, string.format("当前: %.0f (%.2fx 默认)", current_gravity, current_gravity / GRAVITY_DEFAULT))
  else
    GuiText(gui, 0, 0, "当前: 无法读取")
  end

  -- 预设按钮
  GuiLayoutBeginHorizontal(gui, 0, 0)
  if GuiButton(gui, 0, 0, "[月球 56 (0.16x)]", next_id()) then apply_gravity(56); sync_ni(gravity_ni, 56) end
  if GuiButton(gui, 0, 0, "[火星 133 (0.38x)]", next_id()) then apply_gravity(133); sync_ni(gravity_ni, 133) end
  GuiLayoutEnd(gui)

  GuiLayoutBeginHorizontal(gui, 0, 0)
  if GuiButton(gui, 0, 0, "[地球 350 (1.0x)]", next_id()) then apply_gravity(350); sync_ni(gravity_ni, 350) end
  if GuiButton(gui, 0, 0, "[两倍 700 (2.0x)]", next_id()) then apply_gravity(700); sync_ni(gravity_ni, 700) end
  GuiLayoutEnd(gui)

  GuiLayoutBeginHorizontal(gui, 0, 0)
  if GuiButton(gui, 0, 0, "[零重力 0]", next_id()) then apply_gravity(0); sync_ni(gravity_ni, 0) end
  if GuiButton(gui, 0, 0, "[反转 -175]", next_id()) then apply_gravity(-175); sync_ni(gravity_ni, -175) end
  GuiLayoutEnd(gui)

  -- 自定义输入
  render_num_input(gravity_ni, (T("physics_custom_gravity") or "自定义: "), 10)

  GuiText(gui, 0, 0, " ")

  -- ====== 移动速度 ======
  GuiText(gui, 0, 0, "---- " .. (T("physics_move_speed") or "移动速度") .. " (run_velocity, 默认 95) ----")

  local current_speed = get_current_speed()
  if current_speed then
    GuiText(gui, 0, 0, string.format("当前: %.0f (%.2fx 默认)", current_speed, current_speed / SPEED_DEFAULT))
  else
    GuiText(gui, 0, 0, "当前: 无法读取 (LensValue 字段)")
  end

  -- 预设按钮
  GuiLayoutBeginHorizontal(gui, 0, 0)
  if GuiButton(gui, 0, 0, "[慢 50]", next_id()) then apply_speed(50); sync_ni(speed_ni, 50) end
  if GuiButton(gui, 0, 0, "[默认 95]", next_id()) then apply_speed(95); sync_ni(speed_ni, 95) end
  if GuiButton(gui, 0, 0, "[快 150]", next_id()) then apply_speed(150); sync_ni(speed_ni, 150) end
  GuiLayoutEnd(gui)

  GuiLayoutBeginHorizontal(gui, 0, 0)
  if GuiButton(gui, 0, 0, "[超快 250]", next_id()) then apply_speed(250); sync_ni(speed_ni, 250) end
  if GuiButton(gui, 0, 0, "[光速 500]", next_id()) then apply_speed(500); sync_ni(speed_ni, 500) end
  if GuiButton(gui, 0, 0, "[传送到月亮 1000]", next_id()) then apply_speed(1000); sync_ni(speed_ni, 1000) end
  GuiLayoutEnd(gui)

  -- 自定义输入
  render_num_input(speed_ni, (T("physics_custom_speed") or "自定义: "), 20)

  GuiLayoutEnd(gui)
end}
