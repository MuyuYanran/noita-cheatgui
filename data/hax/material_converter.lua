-- =============================================================================
-- material_converter.lua - 材料转化工具 (v3)
-- =============================================================================
-- 全局/区域材料转化。包括：万材成金、指定材料替换、区域转化
-- API: ConvertMaterialEverywhere, ConvertMaterialOnAreaInstantly,
--      ConvertEverythingToGold, EntityConvertToMaterial
-- UX: 双列布局（左右各一栏）+ i18n + 短名映射，避免硬编码 y 导致堆叠
-- =============================================================================

-- 常用材料预设 (en_label, zh_label, src, dst)
local MATERIAL_PRESETS = {
  {"water->gold",       "水->金",    "water",  "gold"},
  {"water->blood",      "水->血",    "water",  "blood"},
  {"blood->gold",       "血->金",    "blood",  "gold"},
  {"soil->gold",        "土->金",    "soil",   "gold"},
  {"rock->gold",        "岩->金",    "rock_static", "gold"},
  {"water->lava",       "水->岩浆",  "water",  "lava"},
  {"water->poison",     "水->毒液",  "water",  "radioactive_liquid"},
  {"water->acid",       "水->酸",    "water",  "acid"},
  {"water->oil",        "水->油",    "water",  "oil"},
  {"water->steam",      "水->蒸汽",  "water",  "steam"},
  {"coal->diamond",     "煤->钻石",  "coal",   "diamond"},
  {"water->alcohol",    "水->酒",    "water",  "alcohol"},
  {"air->smoke",        "空->烟",    "air",    "smoke"},
  {"air->lava",         "空->岩浆",  "air",    "lava"},
  {"water->cold_blood", "水->冷血",  "water",  "blood_cold"},
  {"water->faster",     "水->加速",  "water",  "magic_liquid_faster_levitation"},
  {"water->polymorph",  "水->变形",  "water",  "magic_liquid_polymorph"},
  {"water->unstable",   "水->不稳",  "water",  "magic_liquid_unstable_polymorph"},
  {"water->teleport",   "水->传送",  "water",  "magic_liquid_teleportation"},
  {"water->hp_regen",   "水->灵药",  "water",  "magic_liquid_hp_regeneration"},
}

-- 短名映射：长材料ID -> 短英文显示名
local MAT_SHORT_EN = {
  ["rock_static"] = "rock",
  ["ice_static"] = "ice",
  ["concrete_static"] = "concrete",
  ["glass"] = "glass",
  ["plastic"] = "plastic",
  ["radioactive_liquid"] = "poison",
  ["toxic_sludge"] = "toxic",
  ["magic_liquid_hp_regeneration"] = "hp_regen",
  ["magic_liquid_faster_levitation"] = "faster",
  ["magic_liquid_mana_regeneration"] = "mana",
  ["magic_liquid_protection_all"] = "protect",
  ["magic_liquid_polymorph"] = "polymorph",
  ["magic_liquid_teleportation"] = "teleport",
  ["magic_liquid_movement_faster"] = "swift",
  ["magic_liquid_worm_attractor"] = "worm",
  ["magic_liquid_charm"] = "charm",
  ["magic_liquid_random_polymorph"] = "rand_poly",
  ["magic_liquid_berserk"] = "berserk",
  ["magic_liquid_invisibility"] = "invis",
  ["magic_liquid_unstable_polymorph"] = "unstable",
  ["blood_cold"] = "cold_blood",
}

-- 中文材料名映射
local MAT_SHORT_ZH = {
  ["water"] = "水",
  ["blood"] = "血",
  ["oil"] = "油",
  ["alcohol"] = "酒",
  ["acid"] = "酸",
  ["lava"] = "岩浆",
  ["steam"] = "蒸汽",
  ["smoke"] = "烟",
  ["sand"] = "沙",
  ["soil"] = "土",
  ["coal"] = "煤",
  ["snow"] = "雪",
  ["ice_static"] = "冰",
  ["mud"] = "泥",
  ["fungus"] = "菌",
  ["swamp"] = "沼泽",
  ["rock_static"] = "岩石",
  ["concrete_static"] = "混凝土",
  ["glass"] = "玻璃",
  ["plastic"] = "塑料",
  ["slime"] = "史莱姆",
  ["cheese"] = "奶酪",
  ["meat"] = "肉",
  ["gold"] = "金",
  ["diamond"] = "钻石",
  ["fire"] = "火",
  ["air"] = "空气",
  ["radioactive_liquid"] = "毒液",
  ["toxic_sludge"] = "毒泥",
  ["blood_cold"] = "冷血",
  ["magic_liquid_hp_regeneration"] = "生命灵药",
  ["magic_liquid_faster_levitation"] = "加速液",
  ["magic_liquid_mana_regeneration"] = "法力灵药",
  ["magic_liquid_protection_all"] = "护盾液",
  ["magic_liquid_polymorph"] = "混沌变形",
  ["magic_liquid_teleportation"] = "传送液",
  ["magic_liquid_movement_faster"] = "迅捷液",
  ["magic_liquid_worm_attractor"] = "蠕虫液",
  ["magic_liquid_charm"] = "魅惑液",
  ["magic_liquid_random_polymorph"] = "随机变形",
  ["magic_liquid_berserk"] = "狂暴液",
  ["magic_liquid_invisibility"] = "隐身液",
  ["magic_liquid_unstable_polymorph"] = "不稳变形",
}

-- 显示材料名（根据当前语言）
local function short_mat(m)
  if not m then return "?" end
  if _i18n.language == "zh" then
    return MAT_SHORT_ZH[m] or MAT_SHORT_EN[m] or m
  else
    return MAT_SHORT_EN[m] or m
  end
end

-- State
local mc_src_material = "water"
local mc_dst_material = "gold"
local mc_area_x, mc_area_y = 0, 0
local mc_area_radius = 100

-- 分页状态
local mc_src_page = 1
local mc_dst_page = 1
local mc_preset_page = 1
local MC_SRC_PAGE_SIZE = 6
local MC_DST_PAGE_SIZE = 8
local MC_PRESET_PAGE_SIZE = 6
local MC_COLS = 2  -- 2 列网格（更窄以容纳长材料名）

-- 预设源材料列表
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

-- =============================================================================
-- Actions
-- =============================================================================
local function to_mat_type(v)
  if type(v) == "number" then return v end
  return CellFactory_GetType(v)
end

local function do_global_convert(src, dst)
  GamePrint("Converting: " .. src .. " -> " .. dst)
  local ok = pcall(ConvertMaterialEverywhere, to_mat_type(src), to_mat_type(dst))
  if ok then
    GamePrint("Global convert done!")
  else
    GamePrint("Convert failed: " .. tostring(src) .. " -> " .. tostring(dst))
  end
end

local function do_area_convert()
  if mc_area_x and mc_area_y then
    local ok = pcall(ConvertMaterialOnAreaInstantly,
      mc_area_x - mc_area_radius, mc_area_y - mc_area_radius,
      mc_area_radius * 2, mc_area_radius * 2,
      to_mat_type(mc_src_material), to_mat_type(mc_dst_material),
      true, false)
    if ok then
      GamePrint("Area convert done!")
    else
      GamePrint("Area convert failed")
    end
  end
end

local function do_everything_to_gold()
  GamePrint("Everything to gold...")
  local ok = pcall(ConvertEverythingToGold)
  if ok then
    GamePrint("Everything to gold!")
  else
    GamePrint("Everything-to-gold failed")
  end
end

local function do_entity_to_material(material)
  local player = get_player()
  if not player then return end
  local ok = pcall(EntityConvertToMaterial, player, material)
  if ok then
    GamePrint("Converted to: " .. material)
  else
    GamePrint("Entity convert failed")
  end
end

-- =============================================================================
-- UI helpers
-- =============================================================================

-- 通用分页材料网格（带当前选中标记）
-- 使用 upvalue-style: 直接读写模块级 state 变量,避免 Lua 闭包限制
local function render_mat_grid(options, get_page, set_page, page_size, selected, on_select)
  local total = #options
  local total_pages = math.max(1, math.ceil(total / page_size))
  local page = get_page()
  if page > total_pages then set_page(total_pages); page = total_pages end
  if page < 1 then set_page(1); page = 1 end

  local start = (page - 1) * page_size + 1
  local end_idx = math.min(start + page_size - 1, total)
  local items = end_idx - start + 1
  local rows = math.ceil(items / MC_COLS)

  for row = 1, rows do
    GuiLayoutBeginHorizontal(gui, 0, 0)
    for col = 1, MC_COLS do
      local idx = start + (row - 1) * MC_COLS + (col - 1)
      if idx <= end_idx then
        local mat = options[idx]
        local marker = (selected == mat) and "[*]" or ""
        if GuiButton(gui, 0, 0, marker .. short_mat(mat), next_id()) then
          on_select(mat)
        end
      else
        GuiText(gui, 0, 0, "  ")
      end
    end
    GuiLayoutEnd(gui)
  end
end

-- 分页控制按钮行
local function render_page_nav(get_page, set_page, total_pages, prev_label, next_label)
  local page = get_page()
  GuiLayoutBeginHorizontal(gui, 0, 0)
  if page > 1 then
    if GuiButton(gui, 0, 0, prev_label, next_id()) then
      set_page(page - 1)
    end
  end
  GuiText(gui, 0, 0, " " .. page .. "/" .. total_pages .. " ")
  if page < total_pages then
    if GuiButton(gui, 0, 0, next_label, next_id()) then
      set_page(page + 1)
    end
  end
  GuiLayoutEnd(gui)
end

-- 计算分页信息
local function calc_pages(total, size)
  return math.max(1, math.ceil(total / size))
end

-- =============================================================================
-- Left column: source materials + actions + area convert
-- =============================================================================
local function build_mc_left()
  GuiLayoutBeginVertical(gui, 1, 11)
  GuiText(gui, 0, 0, T("mc_title_src") .. " " .. short_mat(mc_src_material))

  local src_total = #MC_SRC_OPTIONS
  local src_pages = calc_pages(src_total, MC_SRC_PAGE_SIZE)
  render_mat_grid(MC_SRC_OPTIONS,
    function() return mc_src_page end,
    function(v) mc_src_page = v end,
    MC_SRC_PAGE_SIZE,
    mc_src_material, function(m) mc_src_material = m end)
  render_page_nav(
    function() return mc_src_page end,
    function(v) mc_src_page = v end,
    src_pages, T("page_prev_arrow") .. " src", "src " .. T("page_next_arrow"))

  GuiText(gui, 0, 0, " ")
  GuiText(gui, 0, 0, T("mc_title_actions"))
  GuiLayoutBeginHorizontal(gui, 0, 0)
  if GuiButton(gui, 0, 0,
      T("mc_btn_global"):format(short_mat(mc_src_material), short_mat(mc_dst_material)),
      next_id()) then
    do_global_convert(mc_src_material, mc_dst_material)
  end
  GuiLayoutEnd(gui)

  GuiLayoutBeginHorizontal(gui, 0, 0)
  if GuiButton(gui, 0, 0, T("mc_btn_everything_gold"), next_id()) then
    do_everything_to_gold()
  end
  GuiLayoutEnd(gui)

  GuiText(gui, 0, 0, " ")
  GuiText(gui, 0, 0, T("mc_title_area"))

  GuiLayoutBeginHorizontal(gui, 0, 0)
  if GuiButton(gui, 0, 0, T("mc_btn_get_center"), next_id()) then
    mc_area_x, mc_area_y = get_player_pos()
    mc_area_x, mc_area_y = math.floor(mc_area_x), math.floor(mc_area_y)
    GamePrint(T("mc_lbl_center"):format(mc_area_x, mc_area_y))
  end
  GuiLayoutEnd(gui)

  GuiText(gui, 0, 0, T("mc_lbl_center"):format(mc_area_x, mc_area_y))

  GuiLayoutBeginHorizontal(gui, 0, 0)
  if GuiButton(gui, 0, 0, T("mc_btn_area"):format(mc_area_radius), next_id()) then
    do_area_convert()
  end
  GuiLayoutEnd(gui)

  GuiLayoutBeginHorizontal(gui, 0, 0)
  GuiText(gui, 0, 0, T("mc_lbl_radius"))
  if GuiButton(gui, 0, 0, "50", next_id()) then mc_area_radius = 50 end
  if GuiButton(gui, 0, 0, "100", next_id()) then mc_area_radius = 100 end
  if GuiButton(gui, 0, 0, "200", next_id()) then mc_area_radius = 200 end
  if GuiButton(gui, 0, 0, "500", next_id()) then mc_area_radius = 500 end
  GuiLayoutEnd(gui)

  GuiLayoutEnd(gui)
end

-- =============================================================================
-- Right column: target materials + presets + entity convert
-- =============================================================================
local function build_mc_right()
  GuiLayoutBeginVertical(gui, 280, 11, true)
  GuiText(gui, 0, 0, T("mc_title_dst") .. " " .. short_mat(mc_dst_material))

  local dst_total = #MC_DST_OPTIONS
  local dst_pages = calc_pages(dst_total, MC_DST_PAGE_SIZE)
  render_mat_grid(MC_DST_OPTIONS,
    function() return mc_dst_page end,
    function(v) mc_dst_page = v end,
    MC_DST_PAGE_SIZE,
    mc_dst_material, function(m) mc_dst_material = m end)
  render_page_nav(
    function() return mc_dst_page end,
    function(v) mc_dst_page = v end,
    dst_pages, T("page_prev_arrow") .. " dst", "dst " .. T("page_next_arrow"))

  GuiText(gui, 0, 0, " ")
  GuiText(gui, 0, 0, T("mc_title_presets"))

  -- 预设网格 (显示 label)
  local preset_total = #MATERIAL_PRESETS
  local preset_pages = calc_pages(preset_total, MC_PRESET_PAGE_SIZE)
  if mc_preset_page > preset_pages then mc_preset_page = preset_pages end
  if mc_preset_page < 1 then mc_preset_page = 1 end

  local p_start = (mc_preset_page - 1) * MC_PRESET_PAGE_SIZE + 1
  local p_end = math.min(p_start + MC_PRESET_PAGE_SIZE - 1, preset_total)
  local p_items = p_end - p_start + 1
  local p_rows = math.ceil(p_items / MC_COLS)

  for row = 1, p_rows do
    GuiLayoutBeginHorizontal(gui, 0, 0)
    for col = 1, MC_COLS do
      local idx = p_start + (row - 1) * MC_COLS + (col - 1)
      if idx <= p_end then
        local preset = MATERIAL_PRESETS[idx]
        local label = (_i18n.language == "zh") and preset[2] or preset[1]
        if GuiButton(gui, 0, 0, "[" .. label .. "]", next_id()) then
          do_global_convert(preset[3], preset[4])
        end
      else
        GuiText(gui, 0, 0, "  ")
      end
    end
    GuiLayoutEnd(gui)
  end
  render_page_nav(
    function() return mc_preset_page end,
    function(v) mc_preset_page = v end,
    preset_pages, T("page_prev_arrow") .. " preset", "preset " .. T("page_next_arrow"))

  GuiText(gui, 0, 0, " ")
  GuiText(gui, 0, 0, T("mc_title_entity"))
  GuiLayoutBeginHorizontal(gui, 0, 0)
  local self_gold_lbl = (_i18n.language == "zh") and "[自身->金]" or "[self->gold]"
  local self_diamond_lbl = (_i18n.language == "zh") and "[自身->钻石]" or "[self->diamond]"
  if GuiButton(gui, 0, 0, self_gold_lbl, next_id()) then do_entity_to_material("gold") end
  if GuiButton(gui, 0, 0, self_diamond_lbl, next_id()) then do_entity_to_material("diamond") end
  GuiLayoutEnd(gui)

  GuiLayoutEnd(gui)
end

-- =============================================================================
-- Panel
-- =============================================================================
material_converter_panel = Panel{function() return T("panel_material_conv") end, function()
  breadcrumbs(1, 0)
  build_mc_left()
  build_mc_right()
end}
