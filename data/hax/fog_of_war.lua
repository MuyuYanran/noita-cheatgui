-- =============================================================================
-- fog_of_war.lua - 战争迷雾控制面板
-- =============================================================================
-- API 签名（来自 lua_api_documentation.txt）:
--   GameGetFogOfWar(pos_x, pos_y) -> int [0-255]
--     返回迷雾覆盖率: 0=无雾(已揭示), 255=全雾(未揭示), -1=超出网格
--     "Larger value means more coverage" 指的是 **迷雾覆盖率**
--   GameSetFogOfWar(pos_x, pos_y, fog_of_war:int) -> bool [0-255]
--     0=揭示(清雾), 255=恢复迷雾(加雾)
--   GameGetFogOfWarBilinear(pos_x, pos_y) -> int
--
-- 关键组件:
--   WorldStateComponent.open_fog_of_war_everywhere (LensValue<bool>)
--     → 语义（用户实测验证）: true = 迷雾覆盖全图（有雾）; false = 迷雾不覆盖（揭示/无雾）
--     → 注意: 和 GameGetIsTrailerModeEnabled() 语义相反!
--       GameGetIsTrailerModeEnabled()=true 意味着 trailer mode 开启 = 全图可见
--       open_fog_of_war_everywhere=true 意味着 迷雾"开放/覆盖"全图 = 有雾遮挡
--     → 用 ComponentSetValue2 直接设置（同 physics_tweaks 的 LensValue 经验）
--   FogOfWarRadiusComponent.radius (float, default=256, max=1024)
--     → 玩家的迷雾揭示半径，越大移动时揭示范围越广
--
-- 已修复的常见错误:
--   1. GameGetFogOfWar/GameSetFogOfWar 无位置参数 → 完全无效
--   2. 用浮点 0-1 代替整数 0-255 → 完全无效
--   3. 值语义搞反: 255=加雾(恢复), 0=清雾(揭示), 不是反过来
--   4. LensValue<bool> 用 ComponentObjectSetValue2 不生效 → 改用 ComponentSetValue2
-- =============================================================================
local FOG_CLEAR  = 0    -- 无迷雾覆盖 = 已揭示/可见
local FOG_FULL   = 255  -- 全迷雾覆盖 = 未揭示/遮挡
local FOG_HALF   = 128  -- 半透明

local fog_reveal_everywhere = false
local fog_radius_override = nil

-- =============================================================================
-- 辅助函数
-- =============================================================================

-- 获取 WorldStateComponent
-- 尝试多种策略找到拥有此组件的实体
local function get_world_state_comp()
  -- 策略1: by tag "world_state"
  local entities = EntityGetWithTag("world_state")
  if entities and #entities > 0 then
    local ok, comp = pcall(EntityGetFirstComponent, entities[1], "WorldStateComponent")
    if ok and comp and comp ~= 0 then return comp end
  end
  -- 策略2: 尝试常见 entity name
  local named = EntityGetWithName("world_state")
  if named and named ~= 0 then
    local ok, comp = pcall(EntityGetFirstComponent, named, "WorldStateComponent")
    if ok and comp and comp ~= 0 then return comp end
  end
  return nil
end

-- 获取玩家的 FogOfWarRadiusComponent
local function get_player_fog_radius_comp()
  local player = get_player()
  if not player then return nil end
  local ok, comp = pcall(EntityGetFirstComponent, player, "FogOfWarRadiusComponent")
  if ok and comp and comp ~= 0 then return comp end
  return nil
end

-- 读取 open_fog_of_war_everywhere
-- 语义: true = 迷雾覆盖全图(有雾), false = 迷雾不覆盖(揭示)
-- 注意: GameGetIsTrailerModeEnabled() 语义相反! trailer=true 表示可见, 但 open_fog=true 表示有雾
-- 返回值含义: true = 当前有迷雾遮挡, false = 当前已揭示/无雾
local function read_fog_everywhere()
  local ws = get_world_state_comp()
  if ws then
    local ok, val = pcall(ComponentGetValue2, ws, "open_fog_of_war_everywhere")
    if ok and val ~= nil then return val end
  end
  return false  -- 默认无全图迷雾
end

-- 设置 open_fog_of_war_everywhere (LensValue<bool>)
-- 语义: enabled=true = 迷雾覆盖全图(恢复迷雾), enabled=false = 迷雾不覆盖(全图揭示)
-- 用 ComponentSetValue2 直接写入（经验: physics_tweaks 的 LensValue<float> 用此方法成功）
local function set_fog_everywhere(enabled)
  local ws = get_world_state_comp()
  if not ws then
    GamePrint(T("fog_err_no_world_state"))
    return false
  end
  -- LensValue<bool>: 直接 ComponentSetValue2
  local ok = pcall(ComponentSetValue2, ws, "open_fog_of_war_everywhere", enabled)
  if ok then
    fog_reveal_everywhere = enabled
    -- enabled=true = 有雾(恢复), enabled=false = 无雾(揭示)
    GamePrint(not enabled and T("fog_log_everywhere_on") or T("fog_log_everywhere_off"))
    return true
  else
    GamePrint(T("fog_err_set_fail"))
    return false
  end
end

-- 读取玩家位置的迷雾覆盖率
local function get_fog_at_player()
  local px, py = get_player_pos()
  local ok, val = pcall(GameGetFogOfWar, px, py)
  if ok and val ~= nil then
    return tonumber(val)  -- 0=已揭示, 255=全雾, -1=超出网格
  end
  return nil
end

-- 区域迷雾操作: 在玩家周围 grid 上设置 GameSetFogOfWar
-- fog_value: 0=揭示(清雾), 255=恢复迷雾(加雾); range: 像素范围; step: grid 步长
local function set_area_fog(range, fog_value, step)
  local px, py = get_player_pos()
  step = step or 8
  fog_value = math.floor(math.min(255, math.max(0, fog_value)))
  local count = 0
  for fx = px - range, px + range, step do
    for fy = py - range, py + range, step do
      local ok = pcall(GameSetFogOfWar, fx, fy, fog_value)
      if ok then count = count + 1 end
    end
  end
  local action = fog_value == FOG_CLEAR and T("fog_action_clear")
    or fog_value == FOG_FULL and T("fog_action_restore")
    or TF("fog_action_set", fog_value)
  GamePrint(TF("fog_log_area", action, range, count))
end

-- 设置玩家迷雾揭示半径
local function set_fog_radius(radius)
  local comp = get_player_fog_radius_comp()
  if not comp then
    GamePrint(T("fog_err_no_radius_comp"))
    return false
  end
  radius = math.min(1024, math.max(0, radius))
  local ok = pcall(ComponentSetValue2, comp, "radius", radius)
  if ok then
    fog_radius_override = radius
    GamePrint(TF("fog_log_radius_set", radius))
    return true
  else
    GamePrint(T("fog_err_set_fail"))
    return false
  end
end

-- 读取当前揭示半径
local function get_fog_radius()
  local comp = get_player_fog_radius_comp()
  if not comp then return nil end
  local ok, val = pcall(ComponentGetValue2, comp, "radius")
  if ok and val then return val end
  return nil
end

-- =============================================================================
-- UI 面板
-- =============================================================================

fog_of_war_panel = Panel{function() return T("panel_fog_of_war") end, function()
  breadcrumbs(1, 0)
  GuiLayoutBeginVertical(gui, 1, 11)

  -- ======== 当前状态 ========
  GuiText(gui, 0, 0, T("fog_title_status"))

  -- 全图揭示状态
  -- read_fog_everywhere: true = 迷雾覆盖全图(有雾), false = 已揭示(无雾)
  fog_reveal_everywhere = read_fog_everywhere()
  local everywhere_str = fog_reveal_everywhere
    and T("fog_state_off") or T("fog_state_on")  -- 有雾=揭示OFF, 无雾=揭示ON
  GuiText(gui, 0, 0, T("fog_lbl_everywhere") .. everywhere_str)

  -- 玩家位置迷雾覆盖率 (0=已揭示, 255=全雾)
  local fog_val = get_fog_at_player()
  if fog_val and fog_val >= 0 then
    -- 显示为"可见度百分比": coverage越低=越可见
    local visibility_pct = math.floor((255 - fog_val) * 100 / 255)
    GuiText(gui, 0, 0, TF("fog_lbl_at_player", fog_val, visibility_pct))
    -- 进度条 (# = 已揭示部分)
    local bar_width = 20
    local revealed = math.floor((255 - fog_val) / 255 * bar_width)
    local bar = "["
    for i = 1, bar_width do
      bar = bar .. (i <= revealed and "#" or "-")
    end
    bar = bar .. "]"
    GuiText(gui, 0, 0, bar)
  else
    GuiText(gui, 0, 0, T("fog_lbl_unknown"))
  end

  -- 揭示半径
  local radius = get_fog_radius()
  if radius then
    GuiText(gui, 0, 0, TF("fog_lbl_radius", math.floor(radius)))
  end

  GuiText(gui, 0, 0, " ")

  -- ======== 快速操作 ========
  GuiText(gui, 0, 0, T("fog_title_quick"))

  -- 全图揭示: open_fog_of_war_everywhere = false (关闭迷雾覆盖 = 全图可见)
  GuiLayoutBeginHorizontal(gui, 0, 0)
  if GuiButton(gui, 0, 0, "[" .. T("fog_btn_reveal_all") .. "]", next_id()) then
    set_fog_everywhere(false)
  end
  GuiLayoutEnd(gui)

  -- 恢复迷雾: open_fog_of_war_everywhere = true (开启迷雾覆盖 = 全图有雾)
  GuiLayoutBeginHorizontal(gui, 0, 0)
  if GuiButton(gui, 0, 0, "[" .. T("fog_btn_restore_all") .. "]", next_id()) then
    set_fog_everywhere(true)
  end
  GuiLayoutEnd(gui)

  GuiText(gui, 0, 0, " ")

  -- ======== 区域操作 ========
  GuiText(gui, 0, 0, T("fog_title_area"))

  -- 区域揭示 (fog_value=0 → 清除迷雾覆盖)
  GuiLayoutBeginHorizontal(gui, 0, 0)
  if GuiButton(gui, 0, 0, "[" .. T("fog_btn_reveal_near") .. "]", next_id()) then
    set_area_fog(256, FOG_CLEAR, 4)
  end
  if GuiButton(gui, 0, 0, "[" .. T("fog_btn_reveal_mid") .. "]", next_id()) then
    set_area_fog(512, FOG_CLEAR, 8)
  end
  if GuiButton(gui, 0, 0, "[" .. T("fog_btn_reveal_far") .. "]", next_id()) then
    set_area_fog(1024, FOG_CLEAR, 8)
  end
  GuiLayoutEnd(gui)

  -- 区域恢复迷雾 (fog_value=255 → 加满迷雾覆盖)
  GuiLayoutBeginHorizontal(gui, 0, 0)
  if GuiButton(gui, 0, 0, "[" .. T("fog_btn_fog_near") .. "]", next_id()) then
    set_area_fog(256, FOG_FULL, 4)
  end
  if GuiButton(gui, 0, 0, "[" .. T("fog_btn_fog_far") .. "]", next_id()) then
    set_area_fog(512, FOG_FULL, 8)
  end
  GuiLayoutEnd(gui)

  -- 半透明区域 (fog_value=128)
  GuiLayoutBeginHorizontal(gui, 0, 0)
  if GuiButton(gui, 0, 0, "[" .. T("fog_btn_half_near") .. "]", next_id()) then
    set_area_fog(256, FOG_HALF, 4)
  end
  if GuiButton(gui, 0, 0, "[" .. T("fog_btn_half_far") .. "]", next_id()) then
    set_area_fog(512, FOG_HALF, 8)
  end
  GuiLayoutEnd(gui)

  GuiText(gui, 0, 0, " ")

  -- ======== 揭示半径 ========
  GuiText(gui, 0, 0, T("fog_title_radius"))

  GuiLayoutBeginHorizontal(gui, 0, 0)
  if GuiButton(gui, 0, 0, "[" .. T("fog_btn_radius_256") .. "]", next_id()) then
    set_fog_radius(256)
  end
  if GuiButton(gui, 0, 0, "[" .. T("fog_btn_radius_512") .. "]", next_id()) then
    set_fog_radius(512)
  end
  if GuiButton(gui, 0, 0, "[" .. T("fog_btn_radius_1024") .. "]", next_id()) then
    set_fog_radius(1024)
  end
  GuiLayoutEnd(gui)

  GuiLayoutBeginHorizontal(gui, 0, 0)
  if GuiButton(gui, 0, 0, "[" .. T("fog_btn_radius_reset") .. "]", next_id()) then
    set_fog_radius(256)
    fog_radius_override = nil
  end
  GuiLayoutEnd(gui)

  GuiText(gui, 0, 0, " ")

  -- ======== 刷新 ========
  if GuiButton(gui, 0, 0, "[" .. T("fog_btn_refresh") .. "]", next_id()) then
    -- 面板每帧重绘，无需额外操作
  end

  GuiLayoutEnd(gui)
end}
