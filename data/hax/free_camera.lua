-- =============================================================================
-- free_camera.lua - 自由摄像机控制
-- =============================================================================
-- 允许解除相机锁定、自由移动视角观察地图
-- API: GameSetCameraFree, GameSetCameraPos, GameGetCameraPos
-- =============================================================================

local camera_free = false
local camera_x, camera_y = 0, 0
local camera_speed = 5
local camera_speed_base = 5

-- 摄像机速度数值控件
local cam_speed_widget, cam_speed_val

-- 懒加载数值控件（需要在 cheatgui.lua 的全局上下文中创建）
local function ensure_speed_widget()
  if not cam_speed_widget then
    cam_speed_widget, cam_speed_val = create_numerical("Speed", {1, 10, 100}, 5, "int")
  end
end

-- 切换自由摄像机
local function toggle_free_camera()
  camera_free = not camera_free
  if camera_free then
    local ok, cx, cy = pcall(GameGetCameraPos)
    if ok and cx and cy then
      camera_x, camera_y = cx, cy
    else
      local px, py = get_player_pos()
      camera_x, camera_y = px or 0, py or 0
    end
  end
  pcall(GameSetCameraFree, camera_free)
  GamePrint(camera_free and "自由摄像机: 启用" or "自由摄像机: 禁用")
end

-- 移动摄像机
local function move_camera(dx, dy)
  local speed = camera_speed
  if camera_free then
    camera_x = camera_x + dx * speed
    camera_y = camera_y + dy * speed
    pcall(GameSetCameraPos, camera_x, camera_y)
  end
end

-- 重置到玩家位置
local function reset_camera_to_player()
  local px, py = get_player_pos()
  if px and py then
    camera_x, camera_y = px, py
    if camera_free then
      pcall(GameSetCameraPos, camera_x, camera_y)
    end
    GamePrint("摄像机已重置到玩家位置")
  end
end

-- 按指定坐标传送摄像机
local function camera_goto(x, y)
  camera_x, camera_y = x or camera_x, y or camera_y
  if camera_free then
    pcall(GameSetCameraPos, camera_x, camera_y)
  end
end

-- =============================================================================
-- UI 面板
-- =============================================================================

free_camera_panel = Panel{function() return T("panel_free_camera") end, function()
  ensure_speed_widget()
  breadcrumbs(1, 0)

  GuiLayoutBeginVertical(gui, 1, 11)

  -- 摄像机开关
  local status_text = camera_free and "[禁用自由摄像机]" or "[启用自由摄像机]"
  if GuiButton(gui, 0, 0, status_text, next_id()) then
    toggle_free_camera()
  end

  -- 当前摄像机位置
  if camera_free then
    GuiText(gui, 0, 0, "摄像机: (" .. math.floor(camera_x) .. ", " .. math.floor(camera_y) .. ")")
  else
    local px, py = get_player_pos()
    GuiText(gui, 0, 0, "玩家: (" .. math.floor(px or 0) .. ", " .. math.floor(py or 0) .. ")")
  end

  -- 速度控件
  cam_speed_widget(1, 18)
  camera_speed = cam_speed_val.value

  GuiText(gui, 0, 0, " ")
  GuiText(gui, 0, 0, "---- 方向移动 ----")

  -- 方向键布局 (3x3 网格)
  --        [上]
  -- [左]  [玩家] [右]
  --        [下]
  
  GuiLayoutBeginHorizontal(gui, 1, 38)
  GuiText(gui, 4, 0, " ")
  if GuiButton(gui, 0, 0, "[^]", next_id()) then move_camera(0, -1) end
  GuiLayoutEnd(gui)

  GuiLayoutBeginHorizontal(gui, 1, 40)
  if GuiButton(gui, 0, 0, "[<]", next_id()) then move_camera(-1, 0) end
  GuiText(gui, 2, 0, " ")
  if GuiButton(gui, 0, 0, "[>]", next_id()) then move_camera(1, 0) end
  GuiLayoutEnd(gui)

  GuiLayoutBeginHorizontal(gui, 1, 42)
  GuiText(gui, 4, 0, " ")
  if GuiButton(gui, 0, 0, "[v]", next_id()) then move_camera(0, 1) end
  GuiLayoutEnd(gui)

  GuiText(gui, 0, 0, " ")

  -- 额外操作
  if GuiButton(gui, 0, 0, "[重置到玩家位置]", next_id()) then
    reset_camera_to_player()
  end

  -- 快速跳转到关键位置
  GuiText(gui, 0, 0, " ")
  GuiText(gui, 0, 0, "---- 快速跳转 ----")
  if GuiButton(gui, 0, 0, "[0, 0]", next_id()) then camera_goto(0, 0) end
  if GuiButton(gui, 0, 0, "[表层]", next_id()) then camera_goto(0, -500) end
  if GuiButton(gui, 0, 0, "[矿山]", next_id()) then camera_goto(0, 1500) end
  if GuiButton(gui, 0, 0, "[煤坑]", next_id()) then camera_goto(0, 2500) end
  if GuiButton(gui, 0, 0, "[金字塔]", next_id()) then camera_goto(8900, -320) end
  if GuiButton(gui, 0, 0, "[冻结密室]", next_id()) then camera_goto(-10000, 360) end
  if GuiButton(gui, 0, 0, "[地狱]", next_id()) then camera_goto(0, -37500) end

  GuiLayoutEnd(gui)

  -- 持续移动提示
  if camera_free then
    GuiLayoutBeginHorizontal(gui, 1, 94)
    GuiText(gui, 0, 0, "提示: 使用方向按钮移动摄像机，关闭面板后摄像机保持自由模式")
    GuiLayoutEnd(gui)
  end
end}
