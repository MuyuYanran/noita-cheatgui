-- =============================================================================
-- material_converter.lua - 材料转化工具
-- =============================================================================
-- 全局/区域材料转化。包括：万材成金、指定材料替换、区域转化
-- API: ConvertMaterialEverywhere, ConvertMaterialOnAreaInstantly,
--      ConvertEverythingToGold, EntityConvertToMaterial
-- =============================================================================

-- 常用材料预设
local MATERIAL_PRESETS = {
  {"水→金", "water", "gold"},
  {"水→血", "water", "blood"},
  {"血→金", "blood", "gold"},
  {"土→金", "soil", "gold"},
  {"岩→金", "rock_static", "gold"},
  {"水→岩浆", "water", "lava"},
  {"水→毒", "water", "radioactive_liquid"},
  {"水→酸", "water", "acid"},
  {"水→油", "water", "oil"},
  {"水→蒸汽", "water", "steam"},
  {"煤→钻石", "coal", "diamond"},
  {"水→酒", "water", "alcohol"},
  {"空气→烟", "air", "smoke"},
  {"空气→熔岩", "air", "lava"},
  {"水→不冻液", "water", "blood_cold"},
  {"水→加速液", "water", "magic_liquid_faster_levitation"},
  {"水→混沌变形", "water", "magic_liquid_polymorph"},
  {"水→不稳变形", "water", "magic_liquid_unstable_polymorph"},
  {"水→传送液", "water", "magic_liquid_teleportation"},
  {"水→生命灵药", "water", "magic_liquid_hp_regeneration"},
}

local mc_src_material = "water"
local mc_dst_material = "gold"
local mc_area_enabled = false
local mc_area_x, mc_area_y = 0, 0
local mc_area_radius = 100

-- 预设源材料列表（用于按钮选择）
local MC_SRC_OPTIONS = {
  "water", "blood", "soil", "sand", "coal", "rock_static", "lava", "air",
  "oil", "alcohol", "acid", "radioactive_liquid", "swamp", "snow",
  "ice_static", "mud", "fungus", "toxic_sludge",
}

-- 预设目标材料列表
local MC_DST_OPTIONS = {
  "gold", "diamond", "blood", "water", "lava", "oil", "alcohol",
  "magic_liquid_hp_regeneration", "magic_liquid_faster_levitation",
  "magic_liquid_mana_regeneration", "magic_liquid_protection_all",
  "magic_liquid_polymorph", "magic_liquid_teleportation",
  "magic_liquid_movement_faster", "magic_liquid_worm_attractor",
  "magic_liquid_charm", "magic_liquid_random_polymorph",
  "magic_liquid_berserk", "magic_liquid_invisibility",
  "radioactive_liquid", "acid", "toxic_sludge", "swamp",
  "steam", "smoke", "fire", "concrete_static",
  "glass", "plastic", "slime", "cheese", "meat",
}

-- 执行全局转化
local function do_global_convert(src, dst)
  GamePrint("转化中: " .. src .. " → " .. dst)
  local ok, _ = pcall(ConvertMaterialEverywhere, src, dst)
  if ok then
    GamePrint("全局转化完成!")
  else
    GamePrint("转化失败: " .. tostring(src) .. " → " .. tostring(dst))
  end
end

-- 执行区域转化
local function do_area_convert()
  if mc_area_x and mc_area_y then
    local ok, _ = pcall(ConvertMaterialOnAreaInstantly,
      mc_src_material, mc_dst_material,
      mc_area_x - mc_area_radius, mc_area_y - mc_area_radius,
      mc_area_x + mc_area_radius, mc_area_y + mc_area_radius, true)
    if ok then
      GamePrint("区域转化完成!")
    else
      GamePrint("区域转化失败")
    end
  end
end

-- 万物成金
local function do_everything_to_gold()
  GamePrint("释放万物成金...")
  local ok, _ = pcall(ConvertEverythingToGold, get_player_pos())
  if ok then
    GamePrint("万物成金!")
  else
    GamePrint("万物成金失败")
  end
end

-- 将玩家实体转化为材料
local function do_entity_to_material(material)
  local player = get_player()
  if not player then return end
  local ok, _ = pcall(EntityConvertToMaterial, player, material)
  if ok then
    GamePrint("已转化为: " .. material)
  else
    GamePrint("实体转化失败")
  end
end

-- =============================================================================
-- UI 面板
-- =============================================================================

local function build_mc_ui()
  GuiLayoutBeginVertical(gui, 1, 11)

  -- 源材料
  GuiText(gui, 0, 0, "源材料:")
  local src_rows_per_col = math.ceil(#MC_SRC_OPTIONS / 3)
  GuiLayoutBeginHorizontal(gui, 1, 14)
  local pos = 1
  for col = 1, 3 do
    GuiLayoutBeginVertical(gui, (col - 1) * 13 + 1, 0)
    for row = 1, src_rows_per_col do
      if pos <= #MC_SRC_OPTIONS then
        local mat = MC_SRC_OPTIONS[pos]
        local marker = (mc_src_material == mat) and "(*)" or ""
        if GuiButton(gui, 0, 0, marker .. mat, next_id()) then
          mc_src_material = mat
        end
        pos = pos + 1
      end
    end
    GuiLayoutEnd(gui)
  end
  GuiLayoutEnd(gui)

  GuiText(gui, 0, 0, " ")
  GuiText(gui, 0, 0, "目标材料:")

  local dst_rows_per_col = math.ceil(#MC_DST_OPTIONS / 3)
  GuiLayoutBeginHorizontal(gui, 1, 39)
  pos = 1
  for col = 1, 3 do
    GuiLayoutBeginVertical(gui, (col - 1) * 18 + 1, 0)
    for row = 1, dst_rows_per_col do
      if pos <= #MC_DST_OPTIONS then
        local mat = MC_DST_OPTIONS[pos]
        local marker = (mc_dst_material == mat) and "(*)" or ""
        if GuiButton(gui, 0, 0, marker .. mat, next_id()) then
          mc_dst_material = mat
        end
        pos = pos + 1
      end
    end
    GuiLayoutEnd(gui)
  end
  GuiLayoutEnd(gui)

  GuiText(gui, 0, 0, " ")
  GuiText(gui, 0, 0, "---- 操作 ----")

  -- 转化按钮
  GuiLayoutBeginHorizontal(gui, 1, 80)
  if GuiButton(gui, 0, 0, "[全局转化: " .. mc_src_material .. " -> " .. mc_dst_material .. "]", next_id()) then
    do_global_convert(mc_src_material, mc_dst_material)
  end
  GuiLayoutEnd(gui)

  GuiLayoutBeginHorizontal(gui, 1, 82)
  if GuiButton(gui, 0, 0, "[万物成金!]", next_id()) then
    do_everything_to_gold()
  end
  GuiLayoutEnd(gui)

  -- 区域转化
  GuiText(gui, 0, 0, " ")
  GuiText(gui, 0, 0, "---- 区域转化 ----")

  GuiLayoutBeginHorizontal(gui, 1, 86)
  if GuiButton(gui, 0, 0, "[获取区域中心]", next_id()) then
    mc_area_x, mc_area_y = get_player_pos()
    mc_area_x, mc_area_y = math.floor(mc_area_x), math.floor(mc_area_y)
    GamePrint("区域中心: (" .. mc_area_x .. ", " .. mc_area_y .. ")")
  end
  GuiLayoutEnd(gui)

  GuiLayoutBeginHorizontal(gui, 1, 88)
  GuiText(gui, 0, 0, "中心: (" .. tostring(mc_area_x) .. ", " .. tostring(mc_area_y) .. ")")
  GuiLayoutEnd(gui)

  GuiLayoutBeginHorizontal(gui, 1, 90)
  if GuiButton(gui, 0, 0, "[区域转化 (半径" .. tostring(mc_area_radius) .. ")]", next_id()) then
    do_area_convert()
  end
  GuiLayoutEnd(gui)

  -- 半径调整
  GuiLayoutBeginHorizontal(gui, 1, 92)
  GuiText(gui, 0, 0, "半径:")
  if GuiButton(gui, 5, 0, "[50]", next_id()) then mc_area_radius = 50 end
  if GuiButton(gui, 8, 0, "[100]", next_id()) then mc_area_radius = 100 end
  if GuiButton(gui, 12, 0, "[200]", next_id()) then mc_area_radius = 200 end
  if GuiButton(gui, 16, 0, "[500]", next_id()) then mc_area_radius = 500 end
  GuiLayoutEnd(gui)

  -- 预设组合
  GuiText(gui, 0, 0, " ")
  GuiText(gui, 0, 0, "---- 预设 ----")
  for idx, preset in ipairs(MATERIAL_PRESETS) do
    local label, src, dst = unpack(preset)
    if #MATERIAL_PRESETS <= 10 then
      if GuiButton(gui, 0, 0, "[" .. label .. "]", next_id()) then
        do_global_convert(src, dst)
      end
    else
      -- 对超过10个的预设，用三列布局
      -- 保持简单：一次性显示所有
      if GuiButton(gui, 0, 0, "[" .. label .. "]", next_id()) then
        do_global_convert(src, dst)
      end
    end
  end

  -- 玩家实体转化（危险操作）
  GuiText(gui, 0, 0, " ")
  GuiText(gui, 0, 0, "---- 实体转化（危险！） ----")
  GuiLayoutBeginHorizontal(gui, 1, 96)
  if GuiButton(gui, 0, 0, "[自身→金]", next_id()) then do_entity_to_material("gold") end
  if GuiButton(gui, 0, 0, "[自身→钻石]", next_id()) then do_entity_to_material("diamond") end
  GuiLayoutEnd(gui)

  GuiLayoutEnd(gui)
end

material_converter_panel = Panel{function() return T("panel_material_conv") end, function()
  breadcrumbs(1, 0)
  build_mc_ui()
end}
