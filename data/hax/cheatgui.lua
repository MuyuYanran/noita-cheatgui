-- =============================================================================
-- cheatgui.lua - CheatGUI 中文分支 主 GUI 文件
-- =============================================================================
-- 版本：1.6.0
-- 
-- 架构概览：
--   1. 依赖加载     → 加载所需库和模块（dofile_once + 普通 dofile）
--   2. 工具函数     → 安全包装、GUI ID 管理、键盘输入处理
--   3. 面板系统     → Panel 构造器、面板栈（导航前进/后退）、面包屑
--   4. GUI 组件     → 网格布局、分页、过滤/排序、数值输入、单选按钮
--   5. 面板定义     → 法杖构建、传送、生命/金币、法术/天赋/药水/法杖/物品
--   6. 功能面板     → 真菌转化、控制台、设置、其它（作弊按钮）
--   7. 信息组件     → 实时统计显示（时间、击杀、坐标等）
--   8. 主循环       → _cheat_gui_main() 每帧驱动 GUI 渲染
-- =============================================================================

dofile_once("data/scripts/lib/coroutines.lua")
dofile_once("data/scripts/lib/utilities.lua")
dofile_once("data/scripts/perks/perk.lua")
dofile_once("data/scripts/gun/gun_actions.lua")
dofile_once("data/hax/materials.lua")
dofile_once("data/hax/alchemy.lua")
dofile_once("data/hax/spawnables.lua")
dofile_once("data/hax/special_spawnables.lua")
dofile_once("data/hax/fungal.lua")
dofile_once("data/hax/gun_builder.lua")
dofile_once("data/hax/superhackykb.lua")
dofile_once("data/hax/utils.lua")
dofile_once("data/hax/i18n.lua")
dofile_once("data/hax/config.lua")

-- =============================================================================
-- 工具函数：国际化、安全包装
-- =============================================================================

-- 快速翻译函数（i18n 缩写）
local function T(key) return _i18n:t(key) end
local function TF(key, ...) return _i18n:tf(key, ...) end

-- 安全包装：避免 nil/空值传入底层 C++ API 引发崩溃
local function safe_game_text(key, ...)
  if not key or key == "" then return "" end
  local ok, text = pcall(GameTextGet, key, ...)
  if not ok or not text then return key end
  return text
end

local function safe_biome_name(x, y)
  local ok, name = pcall(BiomeMapGetName, x, y)
  if not ok or not name or name == "" then return "?" end
  return name
end

-- 延迟求值：如果 v 是函数则调用它，否则直接返回。用于支持动态文本（i18n 切换）
local function resolve_str(v)
  if type(v) == "function" then return v() else return v end
end

-- =============================================================================
-- 版本与初始化
-- =============================================================================

local CHEATGUI_VERSION = "1.6.0"
local CHEATGUI_TITLE = TF("title_version", CHEATGUI_VERSION)
local console_connected = false

if _keyboard_present then
  -- 拥有 FFI 支持（request_no_api_restrictions），加载 Web 控制台模块
  dofile_once("data/hax/console.lua")
else
  -- 无键盘支持，标题添加后缀标记
  CHEATGUI_TITLE = CHEATGUI_TITLE .. T("title_no_keyboard_suffix")
end

local created_gui = false

-- =============================================================================
-- GUI ID 管理
-- =============================================================================
-- Noita 的 GuiButton 需要唯一 ID。使用自增计数器分配 ID。
-- 每帧通过 reset_id() 重置，防止 ID 溢出。
-- =============================================================================

local _next_available_id = 100
local function reset_id()
  _next_available_id = 100
end
local function next_id(n)
  n = n or 1
  local ret = _next_available_id
  _next_available_id = _next_available_id + n
  return ret
end

-- =============================================================================
-- 键盘输入处理
-- =============================================================================
-- 通过 hack_type() 接收用户实时键盘输入，用于搜索过滤框的文本输入。
-- _type_target: 当前活跃的文本输入目标（点击聚焦）
-- _shift_target: 默认文本输入目标（Shift + 打字激活）
-- =============================================================================

local _type_target = nil
local _shift_target = nil

local function handle_typing()
  local type_target = _type_target
  local req_shift = false
  if type_target == nil then 
    type_target = _shift_target
    req_shift = true
  end
  if not type_target then return end
  local prev_val = type_target.value
  local hit_enter = false
  type_target.value, hit_enter = hack_type(prev_val, not req_shift)
  if (prev_val ~= type_target.value) and (type_target.on_change) then
    type_target:on_change()
  end
  if hit_enter and (type_target.on_hit_enter) then
    type_target:on_hit_enter()
  end
end

local function set_type_target(target)
  if not _keyboard_present then return end
  if _type_target and _type_target.on_lose_focus then
    _type_target:on_lose_focus()
  end
  _type_target = target
  if _type_target and _type_target.on_gain_focus then
    _type_target:on_gain_focus()
  end
end

local function set_type_default(target)
  _shift_target = target
end

-- =============================================================================
-- GUI 创建与面板系统
-- =============================================================================
-- Panel 构造器：将 name 和 func 组合为一个面板对象。
-- panel_stack: 面板导航栈，支持前进/后退/跳转。
-- =============================================================================

if not _cheat_gui then
  print("Creating cheat GUI")
  _cheat_gui = GuiCreate()
  _gui_frame_function = nil
  created_gui = true
else
  print("Reloading onto existing GUI")
end

local gui = _cheat_gui

local closed_panel, perk_panel, cards_panel, menu_panel, flasks_panel
local wands_panel, builder_panel, always_cast_panel, teleport_panel, info_panel
local health_panel, money_panel, spawn_panel, console_panel

-- Panel 构造器
local function Panel(options)
  if not options.name then
    options.name = options[1]
  end
  -- 保存原始 name 引用（可能是函数），用于动态解析（i18n 切换）
  options._name_src = options.name
  if not options.func then
    options.func = options[2]
  end
  return options
end

-- 面板栈：模拟面包屑导航
local panel_stack = {}
local _active_panel = nil

local function _change_active_panel(panel)
  if panel == _active_panel then return end
  set_type_default(nil)
  set_type_target(nil)
  _gui_frame_function = panel.func
end

local function prev_panel()
  if #panel_stack < 2 then
    _change_active_panel(closed_panel)
    panel_stack = {}
  else
    -- 弹出最后一个面板
    panel_stack[#panel_stack] = nil
    _change_active_panel(panel_stack[#panel_stack])
  end
end

local function jump_back_panel(idx)
  if #panel_stack <= idx then return end
  for i = idx+1, #panel_stack do
    panel_stack[i] = nil
  end
  _change_active_panel(panel_stack[#panel_stack])
end

local function enter_panel(panel)
  panel_stack[#panel_stack+1] = panel
  _change_active_panel(panel)
end

local function hide_gui()
  _change_active_panel(closed_panel)
end

local function goto_subpanel(panel)
  panel_stack = {}
  enter_panel(menu_panel)
  enter_panel(panel)
end

local function show_gui()
  if #panel_stack == 0 then
    enter_panel(menu_panel)
  else
    _change_active_panel(panel_stack[#panel_stack])
  end
end

local function breadcrumbs(x, y)
  GuiLayoutBeginHorizontal(gui, x, y)
  if GuiButton( gui, 0, 0, "[-]", next_id()) then
    hide_gui()
  end
  for idx, panel in ipairs(panel_stack) do
    if GuiButton( gui, 0, 0, resolve_str(panel._name_src) .. ">", next_id()) then
      jump_back_panel(idx)
    end
  end
  GuiLayoutEnd(gui)
  GuiLayoutBeginHorizontal( gui, x, y+3)
  if #panel_stack > 1 and GuiButton( gui, 0, 0, T("back"), next_id()) then
    prev_panel()
  end
  GuiLayoutEnd( gui )
end

-- =============================================================================
-- 信息小部件系统
-- =============================================================================
-- 小部件显示在 CheatGUI 最小化后的信息栏上。
-- _info_widgets: 当前激活的小部件
-- _all_info_widgets: 所有可用小部件（用于设置面板的开关列表）
-- =============================================================================

local _info_widgets = {}
local _sorted_info_widgets = {}
local _all_info_widgets = {}

local function _update_info_widgets()
  _sorted_info_widgets = {}
  for wname, widget in pairs(_info_widgets) do
    table.insert(_sorted_info_widgets, {wname, widget})
  end
  table.sort(_sorted_info_widgets, function(a, b)
    return a[1] < b[1]
  end)
end

local function add_info_widget(wname, w)
  _info_widgets[wname] = w
  _update_info_widgets()
end

local function remove_info_widget(wname)
  _info_widgets[wname] = nil
  _update_info_widgets()
end

local function register_widget(wname, w)
  table.insert(_all_info_widgets, {wname, w})
end

-- =============================================================================
-- 关闭状态面板（CheatGUI 最小化时显示）
-- 显示信息小部件数据和一个 [+] 按钮来展开完整菜单
-- =============================================================================
closed_panel = Panel{"[+]", function()
  GuiLayoutBeginHorizontal( gui, 1, 0 )
  if GuiButton( gui, 0, 0, "[+]", next_id() ) then
    show_gui()
  end
  GuiLayoutEnd( gui )
  local col_pos = 5
  for idx, winfo in ipairs(_sorted_info_widgets) do
    local wname, widget = unpack(winfo)
    GuiLayoutBeginHorizontal(gui, col_pos, 0)
    local text = widget:text()
    if idx > 1 then text = "| " .. text end
    if GuiButton( gui, 0, 0, text, next_id() ) then
      widget:on_click()
    end
    GuiLayoutEnd( gui )
    col_pos = col_pos + (widget.width or 10)
  end
end}

local function wrap_spawn(path)
  return function() spawn_item(path) end
end

local function maybe_call(s_or_f, opt)
  if type(s_or_f) == 'function' then 
    return s_or_f(opt)
  else
    return s_or_f
  end
end

local function get_option_text(opt)
  return maybe_call(opt.text or opt[1], opt)
end

-- =============================================================================
-- GUI 布局组件
-- =============================================================================
-- grid_layout: 将选项列表排列为多列网格（每列 28 个）
-- wrap_paginate: 为列表添加分页 + 搜索过滤 + 排序功能
-- create_radio: 单选框组件
-- create_numerical: 数值输入组件（带 +/- 增量按钮和直接键入）
-- =============================================================================

local function grid_layout(options, col_width, callback)
  local num_options = #options
  local col_size = 28
  local ncols = math.ceil(num_options / col_size)
  local xoffset = col_width or 25
  local xpos = 5
  local opt_pos = 1
  for col = 1, ncols do
    if not options[opt_pos] then break end
    GuiLayoutBeginVertical( gui, xpos, 11 )
    for row = 1, col_size do
      if not options[opt_pos] then break end
      local opt = options[opt_pos]
      local text = get_option_text(opt)
      if GuiButton( gui, 0, 0, text, next_id() ) then
        (callback or opt.f or opt[2])(opt)
      end
      opt_pos = opt_pos + 1
    end
    GuiLayoutEnd( gui)
    xpos = xpos + xoffset
  end
end

local function grid_panel(title, options, col_width, callback)
  breadcrumbs(1, 0)
  grid_layout(options, col_width, callback)
end

local function filter_options(options, str)
  local ret = {}
  for _, opt in ipairs(options) do
    local text = maybe_call(opt.text, opt):lower()
    if text:find(str) then
      table.insert(ret, opt)
    end
  end
  return ret
end

local function create_radio(title, options, default, x_spacing)
  if not default then default = options[1][2] end
  local selected = default --1
  -- for i, v in ipairs(options) do
  --   if v[2] == default then selected = i end
  -- end
  local wrapper = {
    index = selected, 
    value = options[selected][2],
    reset = function(_self)
      _self.index = default
      _self.value = options[default][2]
    end
  }
  return function(xpos, ypos)
    GuiLayoutBeginHorizontal(gui, xpos, ypos)
    GuiText(gui, 0, 0, resolve_str(title))
    GuiLayoutEnd(gui)
    GuiLayoutBeginHorizontal(gui, xpos+(x_spacing or 12), ypos)
    for idx, option in ipairs(options) do
      local text = resolve_str(option[1])
      if idx == wrapper.index then text = "[" .. text .. "]" end
      if GuiButton( gui, 0, 0, text, next_id() ) then
        wrapper.index = idx
        wrapper.value = option[2]
      end
    end
    GuiLayoutEnd(gui)
  end, wrapper
end

local function alphabetize(options, do_it)
  if not do_it then return options end
  local keys = {}
  for idx, opt in ipairs(options) do
    keys[idx] = {get_option_text(opt):lower(), opt}
  end
  table.sort(keys, function(a, b) return a[1] < b[1] end)
  local sorted = {}
  for idx, v in ipairs(keys) do
    sorted[idx] = v[2]
  end
  return sorted
end

local alphabetize_widget, alphabetize_val = create_radio(function() return T("alphabetize") end, {
  {function() return T("yes") end, true}, {function() return T("no") end, false}
}, 2, 16)

local function breakup_pages(options, page_size)
  local pages = {}
  local npages = math.ceil(#options / page_size)
  local opt_pos = 1
  for page = 1, npages do
    if not options[opt_pos] then break end
    pages[page] = {}
    for idx = 1, page_size do
      if not options[opt_pos] then break end
      table.insert(pages[page], options[opt_pos])
      opt_pos = opt_pos + 1
    end
  end
  return pages
end

local function wrap_paginate(title, options, page_size, callback)
  page_size = page_size or 28*4
  local cur_page = 1
  local pages = breakup_pages(options, page_size)

  local prev_alphabetize = false
  local filtered_set = options
  local filter_thing = {
    value = "", on_change = function(_self)
      filtered_set = alphabetize(
        filter_options(options, _self.value), 
        alphabetize_val.value
      )
    end
  }
  return function(force_refilter)
    if force_refilter or (prev_alphabetize ~= alphabetize_val.value) then
      force_refilter = true
      pages = breakup_pages(
        alphabetize(options, alphabetize_val.value), page_size
      )
    end
    prev_alphabetize = alphabetize_val.value
    set_type_default(filter_thing)
    local filter_str = filter_thing.value
    local filter_text = T("filter_placeholder")
    if filter_str and (filter_str ~= "") then
      filter_text = filter_str
    end

    if _keyboard_present then
      GuiLayoutBeginVertical( gui, 61, 0)
      GuiText(gui, 0, 0, T("filter_label"))
      GuiLayoutEnd( gui )
      GuiLayoutBeginVertical( gui, 61 + 11, 0 )
      if GuiButton( gui, 0, 0, filter_text, next_id() ) then
        filter_thing.value = ""
      end
      GuiLayoutEnd( gui)
    end
    alphabetize_widget(31, 0)

    if (not filter_str) or (filter_str == "") then
      grid_panel(title, pages[cur_page], nil, callback)
      if cur_page > 1 then
        GuiLayoutBeginHorizontal(gui, 46, 96)
        if GuiButton( gui, 0, 0, T("page_prev_arrow"), next_id() ) then
          cur_page = cur_page - 1
        end
        GuiLayoutEnd(gui)
      end
      if #pages > 1 then
        GuiLayoutBeginHorizontal(gui, 48, 96)
        GuiText( gui, 0, 0, ("%d/%d"):format(cur_page, #pages))
        GuiLayoutEnd(gui)
      end
      if cur_page < #pages then
        GuiLayoutBeginHorizontal(gui, 51, 96)
        if GuiButton( gui, 0, 0, T("page_next_arrow"), next_id() ) then
          cur_page = cur_page + 1
        end
        GuiLayoutEnd(gui)
      end
    else
      if force_refilter then
        filtered_set = alphabetize(
          filter_options(options, filter_str), 
          alphabetize_val.value
        )
      end
      grid_panel(title, filtered_set, nil, callback)
    end
  end
end

local num_types = {
  float = {function(x) return x end, "%0.2f", 1.0},
  int = {function(x) return round(x) end, "%d", 1.0},
  frame = {function(x) return round(x) end, "%0.2f", 1.0/60.0},
  mills = {function(x) return round(x) end, "%0.2f", 1.0/1000.0},
  hearts = {function(x) return x end, "%d", 25.0}
}

local function create_numerical(title, increments, default, kind)
  local validate, fstr, multiplier = unpack(num_types[kind or "float"])

  local text_wrapper = {
    value = "",
    on_change = function(_self)
      -- 呃？占位回调
    end,
    on_gain_focus = function(_self)
      _self.has_focus = true
      _self.value = _self.numeric:display_val()
    end,
    set_value = function(_self)
      local temp = tonumber(_self.value)
      if temp then
        _self.numeric.value = validate(temp / multiplier)
      end
    end,
    on_lose_focus = function(_self)
      _self.has_focus = false
      _self:set_value()
    end,
    on_hit_enter = function(_self)
      _self:set_value()
      set_type_target(nil)
    end,
    display_val = function(_self)
      if not _self.has_focus then return nil end
      return _self.value .. "_"
    end
  }

  local wrapper = {
    text = text_wrapper,
    value = default or 0.0,
    display_val = function(_self)
      return fstr:format(_self.value * multiplier)
    end,
    temp_val = "",
    reset = function(_self)
      _self.value = default
    end
  }

  text_wrapper.numeric = wrapper

  return function(xpos, ypos)
    GuiLayoutBeginHorizontal(gui, xpos, ypos)
      GuiText(gui, 0, 0, resolve_str(title))
    GuiLayoutEnd(gui)
    GuiLayoutBeginHorizontal(gui, xpos + 12, ypos)
      for idx = #increments, 1, -1 do
        local s = "[" .. string.rep("-", idx) .. "]"
        if GuiButton( gui, 0, 0, s, next_id() ) then
          wrapper.value = wrapper.value - increments[idx]
        end
      end
      if GuiButton(gui, 0, 0, "" .. (text_wrapper:display_val() or wrapper:display_val()), next_id() ) then
        if text_wrapper.has_focus then
          set_type_target(nil)
        else
          set_type_target(text_wrapper)
        end
      end
      for idx = 1, #increments do
        local s = "[" .. string.rep("+", idx) .. "]"
        if GuiButton( gui, 0, 0, s, next_id() ) then
          wrapper.value = wrapper.value + increments[idx]
        end
      end
    GuiLayoutEnd(gui)
  end, wrapper
end

local localization_widget, localization_val = create_radio(function() return T("show_localized_names") end, {
  {function() return T("yes") end, true}, {function() return T("no") end, false}
}, 1, 16)

local shuffle_widget, shuffle_val = create_radio(function() return T("wb_shuffle") end, {
  {function() return T("yes") end, true}, {function() return T("no") end, false}
}, 2)

local mana_widget, mana_val = create_numerical(function() return T("wb_mana") end, {50, 500}, 300, 'int')
local mana_rec_widget, mana_rec_val = create_numerical(function() return T("wb_mana_recharge") end, {10, 100}, 100, 'int')
local slots_widget, slots_val = create_numerical(function() return T("wb_slots") end, {1, 5}, 5, 'int')
local multi_widget, multi_val = create_numerical(function() return T("wb_multicast") end, {1}, 1, 'int')
local reload_widget, reload_val = create_numerical(function() return T("wb_reload") end, {1, 10}, 30, 'frame')
local delay_widget, delay_val = create_numerical(function() return T("wb_delay") end, {1, 10}, 30, 'frame')
local spread_widget, spread_val = create_numerical(function() return T("wb_spread") end, {0.1, 1}, 0.0, 'float')
local speed_widget, speed_val = create_numerical(function() return T("wb_speed") end, {0.01, 0.1}, 1.0, 'float')

-- =============================================================================
-- 法杖构建器面板
-- =============================================================================
-- 提供法杖所有属性的配置控件：洗牌、法力、槽位、多重施法、充能、延迟、散射、速度
-- 以及始终施法法术选择（最多 10 个）
-- =============================================================================

--local always_cast_choice = nil
local MAX_ALWAYS_CASTS=10 -- 最多10个始终施法法术
local always_cast_index = 1
local always_casts = {}
local function compact_always_casts()
  local new_always_casts = {}
  for idx = 1, MAX_ALWAYS_CASTS do
    if always_casts[idx] then
      table.insert(new_always_casts, always_casts[idx])
    end
  end
  always_casts = new_always_casts
end

local builder_widgets = {
  {shuffle_widget, shuffle_val},
  {mana_widget, mana_val},
  {mana_rec_widget, mana_rec_val},
  {slots_widget, slots_val},
  {multi_widget, multi_val},
  {reload_widget, reload_val},
  {delay_widget, delay_val},
  {spread_widget, spread_val},
  {speed_widget, speed_val}
}

builder_panel = Panel{function() return T("panel_wand_builder") end, function()
  breadcrumbs(1, 0)

  for idx, widget in ipairs(builder_widgets) do
    widget[1](1, 8 + idx*4)
  end

  GuiLayoutBeginVertical(gui, 1, 48)
  for idx = 1, MAX_ALWAYS_CASTS do
    local label = T("wb_always_cast")
    if idx > 1 then label = TF("wb_always_cast_n", idx) end
    if GuiButton( gui, 0, 0, label .. ": " .. (always_casts[idx] or T("wb_none")), next_id() ) then
      always_cast_index = idx
      enter_panel(always_cast_panel)
    end
    if not always_casts[idx] then break end
  end
  if GuiButton( gui, 0, 0, T("wb_reset_all"), next_id() ) then
    for _, widget in ipairs(builder_widgets) do
      widget[2]:reset()
    end
    always_casts = {}
    always_cast_index=1
  end
  if GuiButton( gui, 0, 4, T("wb_spawn_wand"), next_id() ) then
    local x, y = get_player_pos()
    local gun = {
      deck_capacity = slots_val.value,
      actions_per_round = multi_val.value,
      reload_time = reload_val.value,
      shuffle_deck_when_empty = (shuffle_val.value and 1) or 0,
      fire_rate_wait = delay_val.value,
      spread_degrees = spread_val.value,
      speed_multiplier = speed_val.value,
      mana_max = mana_val.value,
      mana_charge_speed = mana_rec_val.value,
      always_casts = always_casts --always_cast_choice
    }
    build_gun(x, y, gun)
  end
  GuiLayoutEnd(gui)
end}

local xpos_widget, xpos_val = create_numerical(function() return T("tp_x") end, {100, 1000, 10000}, 0, 'int')
local ypos_widget, ypos_val = create_numerical(function() return T("tp_y") end, {100, 1000, 10000}, 0, 'int')

-- =============================================================================
-- 传送面板
-- =============================================================================
-- 支持：自定义坐标传送、圣山快速传送（自动扫描）、独立区域传送（生物群系扫描）、
-- 硬编码位置传送（魔球/精粹/BOSS/精粹吞噬者/世界结构）
-- =============================================================================

-- 传送面板折叠状态记忆
_tp_collapsed = _tp_collapsed or {}

local function tp_section_header(key, label)
  local collapsed = _tp_collapsed[key] or false
  local icon = collapsed and "[+] " or "[-] "
  if GuiButton(gui, 0, 0, icon .. label, next_id()) then
    _tp_collapsed[key] = not collapsed
  end
  return collapsed
end

-- ── 上次传送位置跟踪 ──────────────────────────────────
local _last_tp_x, _last_tp_y = nil, nil
local function do_teleport(x, y)
  local player = get_player()
  if not player or not EntityGetIsAlive(player) then
    GamePrint(T("tp_no_player"))
    return
  end
  x = tonumber(x)
  y = tonumber(y)
  if not x or not y then
    GamePrint(T("tp_invalid_coords"))
    return
  end
  local cur_x, cur_y = get_player_pos()
  _last_tp_x, _last_tp_y = math.floor(tonumber(cur_x) or 0), math.floor(tonumber(cur_y) or 0)
  EntitySetTransform(player, x, y)
end

-- ── 圣山快速传送（保持原有逻辑） ──────────────────────
local SPECIAL_LOCATIONS = {
  ["$biome_lava"] = {x=2300}
}

local quick_teleports = nil
local function find_quick_teleports()
  if quick_teleports then return quick_teleports end
  quick_teleports = {}
  local temp_mountains = {}
  local prev_biome = "?"
  for y = 0, 15000, 500 do
    local cur_biome = safe_biome_name(0, y)
    if cur_biome == "$biome_holymountain" then
      temp_mountains[prev_biome] = y
    else
      prev_biome = cur_biome
    end
  end
  local function refine_position(y0)
    for y = y0, y0+500, 10 do
      local cur_biome = safe_biome_name(0, y)
      if cur_biome ~= "$biome_holymountain" then
        return y-10, cur_biome
      end
    end
    return y0, "?"
  end
  for biome, y in pairs(temp_mountains) do
    local teleport_y, next_biome = refine_position(y)
    teleport_y = teleport_y-200
    local teleport_x = -200
    if next_biome and SPECIAL_LOCATIONS[next_biome] then
      teleport_x = SPECIAL_LOCATIONS[next_biome].x or teleport_x
      teleport_y = SPECIAL_LOCATIONS[next_biome].y or teleport_y
    end
    local label = safe_game_text(next_biome)
    if not label or label == "" or label == "?" then label = biome end
    table.insert(quick_teleports, {label, teleport_x, teleport_y})
  end
  table.sort(quick_teleports, function(a, b) return a[3] < b[3] end)
  return quick_teleports
end

-- ── 独立生物群系扫描 ──────────────────────────────────
-- 这些地点是独立的生物群系，可通过 BiomeMapGetName 沿垂直线扫描发现
-- config: {search_x, biome_names:{string}, y_min, y_max, step, offset_x, offset_y}
local SCANNABLE_AREAS = {
  {search_x=-14000, biome_names={"$biome_lake"},                     y_min=0,   y_max=1000,  step=100, offset_x=0,    offset_y=-50},
  {search_x=-3665,  biome_names={"$biome_lukkimonster"},             y_min=7000,y_max=9000,  step=100, offset_x=0,    offset_y=-100},
  {search_x=9706,   biome_names={"$biome_wizardcave"},               y_min=12000,y_max=13500,step=100, offset_x=0,    offset_y=-100},
  {search_x=12350,  biome_names={"$biome_powerplant"},               y_min=7500,y_max=9000,  step=100, offset_x=0,    offset_y=-100},
  {search_x=-3150,  biome_names={"$biome_ancientlab"},               y_min=500, y_max=1500,  step=100, offset_x=0,    offset_y=-100},
  {search_x=9740,   biome_names={"$biome_tower"},                    y_min=8500,y_max=10000, step=100, offset_x=0,    offset_y=-100},
  {search_x=260,    biome_names={"$biome_moon"},                     y_min=-26500,y_max=-25500,step=100,offset_x=0,   offset_y=-100},
  {search_x=235,    biome_names={"$biome_hell","$biome_hell_moon"},  y_min=-38000,y_max=-37000,step=100,offset_x=0,  offset_y=-100},
  {search_x=13188,  biome_names={"$biome_thicket"},                  y_min=3800,y_max=5000,  step=100, offset_x=0,    offset_y=-100},
  {search_x=-2600,  biome_names={"$biome_wandcave"},                 y_min=3300,y_max=4200,  step=100, offset_x=0,    offset_y=-100},
  {search_x=6241,   biome_names={"$biome_boss_arena","$biome_finalcave","$biome_the_end"}, y_min=14500,y_max=15500,step=100,offset_x=0,offset_y=-200},
}

local scanned_areas = nil
local function find_scanned_areas()
  if scanned_areas then return scanned_areas end
  scanned_areas = {}

  for _, cfg in ipairs(SCANNABLE_AREAS) do
    local found_biome, found_y = nil, nil
    -- 粗略扫描
    for y = cfg.y_min, cfg.y_max, cfg.step do
      local biome = safe_biome_name(cfg.search_x, y)
      for _, name in ipairs(cfg.biome_names) do
        if biome == name then
          found_biome = biome
          found_y = y
          break
        end
      end
      if found_biome then break end
    end
    if found_biome then
      -- 细化: 找到生物群系的底部
      local exit_y = found_y
      for y = found_y, found_y + 1000, 10 do
        local cur = safe_biome_name(cfg.search_x, y)
        local still_in_biome = false
        for _, name in ipairs(cfg.biome_names) do
          if cur == name then still_in_biome = true; break end
        end
        if not still_in_biome then
          exit_y = y - 10
          break
        end
      end
      local tp_x = cfg.search_x + (cfg.offset_x or 0)
      local tp_y = exit_y + (cfg.offset_y or -200)
      table.insert(scanned_areas, {safe_game_text(found_biome), tp_x, tp_y})
    end
  end
  table.sort(scanned_areas, function(a, b) return a[3] < b[3] end)
  return scanned_areas
end

-- ── 硬编码位置 ────────────────────────────────────────
-- 这些是生物群系内的结构、实体生成点，无法通过 BiomeMapGetName 精确定位
-- 标签名使用 GameTextGet 尝试获取游戏内名称，否则使用 i18n key 回退

-- 辅助函数: 生成带本地化名称的标签
local function loc_label(key, fallback, x, y)
  local name = safe_game_text(key)
  if not name or name == "" or name == key then name = T(fallback) end
  return name, x, y
end

-- 主世界内部结构
local FIXED_WORLD = {
  -- {game_text_key, i18n_fallback, x, y}
  {"$biome_pyramid",         "tp_loc_pyramid",           8900,  -320},
  {"$biome_snowcastle",          "tp_loc_frozen_vault",      -10000, 360},
  {"",                       "tp_loc_floating_island",   774,   -1197},
  {"$biome_pyramid",         "tp_loc_pyramid_top",       9980,  -1170},
  {"",                       "tp_loc_tree_top",          -1470, -1300},
  {"$biome_lake",            "tp_loc_lake_hut",          -14070, 90},
  {"",                       "tp_loc_sky_shop",          3350,  -13100},
  {"$biome_tower",           "tp_loc_tower_wand",        9980,  4340},
  {"",                       "tp_loc_snow_eye",          -2440, -210},
  {"",                       "tp_loc_notes",             -3330, 3350},
  {"",                       "tp_loc_gatling_wand",      16130, 10000},
  {"",                       "tp_loc_moon_radar",        16130, 3345},
  {"",                       "tp_loc_perk_altar",        14050, 7550},
  {"",                       "tp_loc_dark_altar",        3840,  15590},
}

-- 魔球
local FIXED_ORBS = {
  {"tp_orb_lake",        4354,  763},
  {"tp_orb_2",          -10010, 2827},
  {"tp_orb_4",           9955,  2819},
  {"tp_orb_5",          -4375,  3867},
  {"tp_orb_6",          -4859,  8973},
  {"tp_orb_7",           4343,  814},
  {"tp_orb_8",           -255,   16147},
  {"tp_orb_9",          -8957,  14609},
  {"tp_orb_10",          10476, 16148},
}

-- 精粹
local FIXED_ESSENCES = {
  {"tp_essence_earth",   16129, -1786},
  {"tp_essence_water",  -5376,  16644},
  {"tp_essence_alcohol",-14080, 13564},
  {"tp_essence_fire",   -14051, 324},
  {"tp_essence_air",    -13054, -5368},
}

-- BOSS
local FIXED_BOSSES = {
  {"tp_boss_final",      3500,  13060},
  {"tp_boss_lake",      -13955, 9975},
  {"tp_boss_powerplant", 13780, 11000},
  {"tp_boss_forgotten", -11555, 13185},
  {"tp_boss_dragon",     15115, 18635},
  {"tp_boss_alchemist", -4870,  890},
}

-- 精粹吞噬者
local FIXED_EATERS = {
  {"tp_eater_snow",     -6880,  -165},
  {"tp_eater_desert",   12575,  0},
}

-- 辅助：绘制固定坐标按钮列表（使用 i18n key 作为标签）
local function draw_tp_button_list(list)
  for _, entry in ipairs(list) do
    local label, x, y
    if #entry == 4 then
      -- {game_text_key, i18n_fallback, x, y} 格式
      local gtk, fallback = entry[1], entry[2]
      label, x, y = loc_label(gtk, fallback, entry[3], entry[4])
    else
      -- {i18n_key, x, y} 格式
      label, x, y = T(entry[1]), entry[2], entry[3]
    end
    if GuiButton(gui, 0, 0, TF("tp_quick_teleport_format", label, x, y), next_id()) then
      GamePrint(TF("tp_log_teleport", x, y))
      do_teleport(x, y)
    end
  end
end

-- 辅助：绘制扫描结果按钮列表
local function draw_scanned_button_list(list)
  for _, loc in ipairs(list) do
    local label, x, y = loc[1], loc[2], loc[3]
    if GuiButton(gui, 0, 0, TF("tp_quick_teleport_format", label, x, y), next_id()) then
      GamePrint(TF("tp_log_teleport", x, y))
      do_teleport(x, y)
    end
  end
end

-- ── 传送面板 ──────────────────────────────────────────
teleport_panel = Panel{function() return T("panel_teleport") end, function()
  xpos_widget(1, 12)
  ypos_widget(1, 16)

  breadcrumbs(1, 0)

  GuiLayoutBeginVertical(gui, 1, 20)
  -- 基础传送操作
  if GuiButton(gui, 0, 0, T("tp_get_pos"), next_id()) then
    local x, y = get_player_pos()
    xpos_val.value, ypos_val.value = math.floor(x), math.floor(y)
  end
  if GuiButton(gui, 0, 0, T("tp_zero_pos"), next_id()) then
    xpos_val.value, ypos_val.value = 0, 0
  end
  if GuiButton(gui, 0, 0, T("tp_teleport"), next_id()) then
    GamePrint(TF("tp_log_teleport", xpos_val.value, ypos_val.value))
    do_teleport(xpos_val.value, ypos_val.value)
  end

  -- 上一次传送
  if _last_tp_x and _last_tp_y then
    GuiText(gui, 0, 0, " ")
    if GuiButton(gui, 0, 0, TF("tp_quick_teleport_format", T("tp_last_pos"), _last_tp_x, _last_tp_y), next_id()) then
      GamePrint(TF("tp_log_teleport", _last_tp_x, _last_tp_y))
      do_teleport(_last_tp_x, _last_tp_y)
    end
  end

  -- 分组以两列网格平铺，减少纵向长度
  local function draw_section(key, label, list, is_scanned)
    if not tp_section_header(key, label) then
      if is_scanned then
        draw_scanned_button_list(list)
      else
        draw_tp_button_list(list)
      end
    end
  end

  local holy_mountains = find_quick_teleports()
  local scanned = find_scanned_areas()

  local section_defs = {
    {key = "holy_mountain", label = T("tp_section_holy_mountain"), list = holy_mountains, scanned = true,  cond = #holy_mountains > 0},
    {key = "scanned",       label = T("tp_section_scanned"),       list = scanned,       scanned = true,  cond = #scanned > 0},
    {key = "world",         label = T("tp_section_world"),         list = FIXED_WORLD,   scanned = false, cond = true},
    {key = "orbs",          label = T("tp_section_orbs"),          list = FIXED_ORBS,    scanned = false, cond = true},
    {key = "essences",      label = T("tp_section_essences"),      list = FIXED_ESSENCES,scanned = false, cond = true},
    {key = "bosses",        label = T("tp_section_bosses"),        list = FIXED_BOSSES,  scanned = false, cond = true},
    {key = "eaters",        label = T("tp_section_eaters"),        list = FIXED_EATERS,  scanned = false, cond = true},
  }

  local visible_sections = {}
  for _, sec in ipairs(section_defs) do
    if sec.cond then
      table.insert(visible_sections, sec)
    end
  end

  -- 基础操作之后结束外层纵向布局，分类以独立纵列绝对定位
  GuiLayoutEnd(gui)

  local max_cols = 2

  local col_width = 45
  local col_start_y = 40
  local columns = {}
  for i = 1, max_cols do columns[i] = {} end
  for i, sec in ipairs(visible_sections) do
    local col = ((i - 1) % max_cols) + 1
    table.insert(columns[col], sec)
  end

  for col_idx, col_sections in ipairs(columns) do
    if #col_sections == 0 then break end
    local x = 1 + (col_idx - 1) * col_width
    GuiLayoutBeginVertical(gui, x, col_start_y)
    for _, sec in ipairs(col_sections) do
      GuiText(gui, 0, 0, " ")
      draw_section(sec.key, sec.label, sec.list, sec.scanned)
    end
    GuiLayoutEnd(gui)
  end


end}

local cur_hp_widget, cur_hp_val = create_numerical(function() return T("hp_hp") end, {1, 4}, 4, 'hearts')
local max_hp_widget, max_hp_val = create_numerical(function() return T("hp_max_hp") end, {1, 4}, 4, 'hearts')

-- =============================================================================
-- 生命面板
-- =============================================================================
health_panel = Panel{function() return T("panel_health") end, function()
  cur_hp_widget(1, 12)
  max_hp_widget(1, 16)

  breadcrumbs(1, 0)

  GuiLayoutBeginVertical(gui, 1, 20)
  if GuiButton( gui, 0, 0, T("hp_get"), next_id() ) then
    cur_hp_val.value, max_hp_val.value = get_health()
  end
  if GuiButton( gui, 0, 0, T("hp_apply"), next_id() ) then
    set_health(cur_hp_val.value, max_hp_val.value)
  end
  GuiText(gui, 0, 0, " ") -- spacer
  GuiText(gui, 0, 0, T("hp_separator"))
  if GuiButton( gui, 0, 0, T("hp_add_25"), next_id() ) then
    cur_hp_val.value, max_hp_val.value = get_health()
    cur_hp_val.value, max_hp_val.value = cur_hp_val.value+1, max_hp_val.value+1
    set_health(cur_hp_val.value, max_hp_val.value)
  end
  if GuiButton( gui, 0, 0, T("hp_add_100"), next_id() ) then
    cur_hp_val.value, max_hp_val.value = get_health()
    cur_hp_val.value, max_hp_val.value = cur_hp_val.value+4, max_hp_val.value+4
    set_health(cur_hp_val.value, max_hp_val.value)
  end
  GuiLayoutEnd(gui)
end}

local money_widget, money_val = create_numerical(function() return T("gold_label") end, {10, 100, 1000}, 0, 'int')

-- =============================================================================
-- 金币面板
-- =============================================================================
money_panel = Panel{function() return T("panel_gold") end, function()
  money_widget(1, 12)
  breadcrumbs(1, 0)

  GuiLayoutBeginVertical(gui, 1, 20)
  if GuiButton( gui, 0, 0, T("gold_get"), next_id() ) then
    money_val.value = get_money()
  end
  if GuiButton( gui, 0, 0, T("gold_set"), next_id() ) then
    set_money(money_val.value)
  end
  GuiText(gui, 0, 0, " ") -- spacer
  GuiText(gui, 0, 0, T("gold_separator"))
  if GuiButton( gui, 0, 0, T("gold_add_100"), next_id() ) then
    money_val.value = get_money()+100
    set_money(money_val.value)
  end
  if GuiButton( gui, 0, 0, T("gold_add_500"), next_id() ) then
    money_val.value = get_money()+500
    set_money(money_val.value)
  end
  if GuiButton( gui, 0, 0, T("gold_add_2000"), next_id() ) then
    money_val.value = get_money()+2000
    set_money(money_val.value)
  end
  GuiLayoutEnd(gui)
end}

-- =============================================================================
-- 列表构建器：法术 / 天赋 / 药水 / 法杖 / 物品
-- =============================================================================
-- 遍历游戏数据构建选项列表，是一次性构建，避免每帧重复创建。
-- 每个选项包含：text（显示名称，支持本地化）、id、f（点击回调）等字段。
-- =============================================================================

-- 根据 localize_val 返回内部 ID 或本地化名称
local function localized_name(thing)
  if not localization_val.value then return thing.id end
  -- 优先查 i18n 实体翻译 → 游戏 ui_name → 原始 id
  local i18n_name = _i18n:t_entity(thing.id)
  if i18n_name then return i18n_name end
  return thing.ui_name or thing.id
end

local function spawn_spell_button(card)
  local x, y = get_player_pos()
  GamePrint(TF("log_spawn", card.id))
  CreateItemActionEntity( card.id, x, y )
end

local function set_always_cast(card)
  always_casts[always_cast_index] = (card and card.id) or nil
  compact_always_casts()
  prev_panel()
end

local spell_options = {}
local always_cast_options = {
  {
    text = function() return T("none") end,
    f = function()
      set_always_cast(nil)
    end
  }
}

for idx, card in ipairs(actions) do
  local ui_name = resolve_localized_name(card.name)
  local id = card.id:lower()
  if (not ui_name) or (ui_name == "") then ui_name = id end
  spell_options[idx] = {
    text = localized_name,
    id = id, ui_name = ui_name,
    f = spawn_spell_button
  }
  always_cast_options[idx+1] = {
    text = localized_name,
    id = id, ui_name = ui_name,
    f = set_always_cast
  }
end

local function spawn_perk_button(perk)
  GamePrint(TF("log_spawn", perk.id))
  spawn_perk(perk.id, get_player())
end

local perk_options = {}
for idx, perk in ipairs(perk_list) do
  perk_options[idx] = {
    text = localized_name, 
    id = perk.id,
    ui_name = resolve_localized_name(perk.ui_name, perk.id), 
    f = spawn_perk_button
  }
end

local quantity_widget, quantity_val = create_numerical(function() return T("flask_quantity") end, {100, 1000}, 1000, 'mills')
local container_widget, container_val = create_radio(function() return T("flask_container") end, {
  {function() return T("flask_potion") end, "potion"}, {function() return T("flask_pouch") end, "pouch"}
}, 1)

local function spawn_potion_button(potion)
  GamePrint(TF("log_spawn_potion", potion.id))
  spawn_potion(potion.id, quantity_val.value, container_val.value)
end

local potion_options = {}
for idx, matinfo in ipairs(materials_list) do
  local material, translated_material = unpack(matinfo)
  if material:sub(1,1) ~= "-" then
    potion_options[idx] = {
      text = localized_name, 
      ui_name = translated_material, id = material,
      f = spawn_potion_button
    }
  else
    potion_options[idx] = {text = material, f = function() end}
  end
end

local wand_options = {}
for i = 1, 5 do
  wand_options[i] = {
    TF("wand_level_fmt", i),
    wrap_spawn("data/entities/items/wand_level_0" .. i .. ".xml")
  }
end
table.insert(wand_options, {function() return T("wand_haxx") end, wrap_spawn("data/hax/wand_hax.xml")})

local tourist_mode_on = false
local function toggle_tourist_mode()
  tourist_mode_on = not tourist_mode_on
  set_tourist_mode(tourist_mode_on)
  GamePrint(TF("tourist_log", tostring(tourist_mode_on)))
end

local function open_console()
  local auth_token = listen_console_connections()
  console_connected = true
  os.execute("start http://localhost:8777/index.html?token=" .. (auth_token or "none"))
end

local seedval = "?"
SetRandomSeed(0, 0)
seedval = tostring(Random() * 2^31)

local LC, AP, LC_prob, AP_prob = get_alchemy()

local function format_combo(combo, prob, localize)
  local ret = {}
  for idx, mat in ipairs(combo) do
    ret[idx] = (localize and localize_material(mat)) or mat
  end
  return table.concat(ret, ", ") .. " (" .. prob .. "%)"
end

local alchemy_combos = {
  AP = {
    [false]=format_combo(AP, AP_prob, false),
    [true]=format_combo(AP, AP_prob, true)
  },
  LC = {
    [false]=format_combo(LC, LC_prob, false),
    [true]=format_combo(LC, LC_prob, true)
  }
}

local extra_buttons = {}
function register_cheat_button(title, f)
  table.insert(extra_buttons, {title, f})
end

local function draw_extra_buttons()
  for _, button in ipairs(extra_buttons) do
    local title, f = button[1], button[2]
    if type(title) == 'function' then title = title() end
    if f then
      if GuiButton( gui, 0, 0, title, next_id() ) then
        f()
      end
    else
      GuiText( gui, 0, 0, title)
    end
  end
end

local function wrap_localized(f)
  local prev_localization = false
  return function()
    localization_widget(31, 3)
    local localization_changed = (prev_localization ~= localization_val.value)
    prev_localization = localization_val.value
    if localization_changed then
      _config:set("show_localized_names", localization_val.value)
    end
    f(localization_changed)
  end
end

local _flask_base = wrap_localized(wrap_paginate(T("flask_select"), potion_options))
local function flask_panel_func()
  quantity_widget(61, 3)
  container_widget(31, 6)
  _flask_base()
end

local gui_grid_ref_panel = Panel{function() return T("panel_gui_grid_ref") end, function()
  breadcrumbs(1, 0)
  for row = 0, 100, 10 do
    for col = 0, 100, 10 do
      GuiLayoutBeginHorizontal(gui, col, row)
      GuiText(gui, 0, 0, ("(%d,%d)"):format(col, row))
      GuiLayoutEnd(gui)
    end
  end
end}

local function spawn_item_button(item)
  GamePrint(TF("log_spawn", item.path))
  spawn_item(item.path)
end

-- 将特殊生成物合并到基础生成列表中
for _, v in ipairs(special_spawnables) do
  table.insert(spawn_list, v)
end

-- 生成物品选项列表
local spawn_options = {}
for idx, item in ipairs(spawn_list) do
  spawn_options[idx] = {
    text = localized_name,
    path = item.path,
    id = item.xml,
    ui_name = item.name, 
    f = spawn_item_button
  }
end

-- =============================================================================
-- 面板定义（法术/天赋/药水/法杖/物品 列表）
-- =============================================================================
-- 使用 wrap_localized 包装以支持本地化名称切换时的刷新。
-- 使用 wrap_paginate 包装以支持分页 + 搜索过滤 + 排序。
-- =============================================================================

always_cast_panel = Panel{function() return T("panel_always_cast") end, wrap_localized(wrap_paginate(T("spell_select_short"), always_cast_options))}
cards_panel = Panel{function() return T("panel_spells") end, wrap_localized(wrap_paginate(T("spell_select"), spell_options))}
perk_panel = Panel{function() return T("panel_perks") end, wrap_localized(wrap_paginate(T("perk_select"), perk_options))}
flasks_panel = Panel{function() return T("panel_flasks") end, flask_panel_func}
spawn_panel = Panel{function() return T("panel_items") end, wrap_localized(wrap_paginate(T("item_select"), spawn_options))}

wands_panel = Panel{function() return T("panel_wands") end, function()
  grid_panel(T("wand_select"), wand_options)
end}

-- =============================================================================
-- 信息组件面板（开关小部件显示）
-- =============================================================================
info_panel = Panel{function() return T("panel_widgets") end, function()
  breadcrumbs(1, 0)
  GuiLayoutBeginVertical(gui, 1, 11)
  for idx, winfo in ipairs(_all_info_widgets) do
    local wname, w = unpack(winfo)
    local enabled = _info_widgets[wname] ~= nil
    local text = w:text()
    if enabled then
      if GuiButton(gui, 0, 0, "[*] " .. text, next_id() ) then
        remove_info_widget(wname)
      end
    else
      if GuiButton(gui, 0, 0, "[ ] " .. text, next_id() ) then
        GamePrint(TF("widget_add_info", wname))
        add_info_widget(wname, w)
      end
    end
  end
  GuiLayoutEnd(gui)
end}

-- =============================================================================
-- 真菌转化面板
-- =============================================================================
-- 显示未来三次真菌转化结果，可选择自定义材料组合并强制触发转化。
-- =============================================================================

local fungal_conv = {from="blood", to="blood"}
local fungal_index

local function choose_fungal_material(mat)
  fungal_conv[fungal_index] = mat.id
  prev_panel()
end

local fungal_material_panel = Panel{function() return T("panel_shift_material") end, 
  wrap_localized(wrap_paginate(T("material_select"), potion_options, nil, choose_fungal_material))}

local function predict_nth_shift(n)
  local shift_from, shift_to = fungal_predict_transform(n or 0)
  if shift_from and shift_to then
    return tostring((shift_from or "?")) .. " -> " 
        .. tostring((shift_to or "?"))
  else
    return T("fungal_no_effect")
  end
end

local fungal_panel = Panel{function() return T("panel_fungal") end, function()
  breadcrumbs(1, 0)
  GuiLayoutBeginVertical(gui, 1, 12)
  GuiText(gui, 0, 0, T("fungal_next_shift") .. predict_nth_shift(0))
  GuiText(gui, 0, 0, T("fungal_next_shift1") .. predict_nth_shift(1))
  GuiText(gui, 0, 0, T("fungal_next_shift2") .. predict_nth_shift(2))
  if GuiButton( gui, 0, 0, T("fungal_from") .. fungal_conv.from, next_id() ) then
    fungal_index = "from"
    enter_panel(fungal_material_panel)
  end
  if GuiButton( gui, 0, 0, T("fungal_to") .. fungal_conv.to, next_id() ) then
    fungal_index = "to"
    enter_panel(fungal_material_panel)
  end
  if GuiButton( gui, 0, 0, T("fungal_force"), next_id()) then
    GamePrint(TF("fungal_would_convert", fungal_conv.from, fungal_conv.to))
    fungal_force_convert(fungal_conv.from, fungal_conv.to)
  end
  GuiLayoutEnd(gui)
end}


-- =============================================================================
-- 控制台面板（Web 远程控制台管理）
-- =============================================================================
console_panel = Panel{function() return T("panel_console") end, function()
  breadcrumbs(1, 0)
  GuiLayoutBeginVertical(gui, 1, 11)
  if console_connected then
    if GuiButton( gui, 0, 0, T("console_close_host"), next_id() ) then
      close_console_connections()
      console_connected = false
    end
  else
    if GuiButton( gui, 0, 0, T("console_open_host"), next_id() ) then
      listen_console_connections()
      console_connected = true
    end
  end
  if GuiButton( gui, 0, 0, T("console_open_new"), next_id() ) then
    open_console()
  end
  GuiText(gui, 0, 0, " ") -- spacer
  GuiText(gui, 0, 0, T("console_separator"))
  local conns = get_console_connections()
  local sorted_conns = {}
  for addr, client in pairs(conns) do
    table.insert(sorted_conns, addr)
  end
  table.sort(sorted_conns)
  for _, addr in ipairs(sorted_conns) do
    local conn = conns[addr] or {stat_out=-1, stat_in=-1}
    local text = TF("console_conn_format", addr, conn.stat_in or 0, conn.stat_out or 0)
    if GuiButton( gui, 0, 0, text, next_id() ) then
      if conns[addr] then conns[addr]:close() end
    end
  end
  GuiLayoutEnd(gui)
end}

local lang_widget, lang_val = create_radio(function() return T("settings_language") end, {
  {function() return T("lang_en") end, "en"}, {function() return T("lang_zh") end, "zh"}
}, (_i18n.language == "zh" and 2 or 1))

-- =============================================================================
-- 设置面板
-- =============================================================================
-- 从持久化配置加载用户偏好并应用到界面。
-- 可设置：界面语言（中文/English）
-- =============================================================================

-- 从永久配置加载用户偏好，覆盖默认值
_config:load()
_i18n.language = _config:get("language")
lang_val.value = _i18n.language
lang_val.index = (_i18n.language == "zh") and 2 or 1

localization_val.value = _config:get("show_localized_names")
localization_val.index = localization_val.value and 1 or 2

local settings_panel = Panel{function() return T("panel_settings") end, function()
  breadcrumbs(1, 0)
  GuiLayoutBeginVertical(gui, 1, 11)
  lang_widget(1, 11)
  if lang_val.value ~= _i18n.language then
    _i18n.language = lang_val.value
    _config:set("language", lang_val.value)
  end
  GuiLayoutEnd(gui)
end}

-- =============================================================================
-- 其它面板（作弊按钮集合）
-- =============================================================================
-- 通过 register_cheat_button 注册的按钮显示在此面板中。
-- =============================================================================
other_panel = Panel{function() return T("panel_other") end, function()
  breadcrumbs(1, 0)
  GuiLayoutBeginVertical( gui, 1, 11 )
  draw_extra_buttons()
  GuiLayoutEnd(gui)
end}

local main_panels = {
  perk_panel, cards_panel, flasks_panel, wands_panel, spawn_panel,
  builder_panel, health_panel, money_panel,
  teleport_panel, fungal_panel, info_panel, other_panel, gui_grid_ref_panel,
  settings_panel
}



if _keyboard_present then table.insert(main_panels, console_panel) end

local function draw_main_panels()
  for idx, panel in ipairs(main_panels) do
    if GuiButton( gui, 0, 0, resolve_str(panel._name_src) .. "->", next_id() ) then
      enter_panel(panel)
    end
  end
end

menu_panel = Panel{CHEATGUI_TITLE, function()
  breadcrumbs(1, 0)
  GuiLayoutBeginVertical( gui, 1, 11 )
  draw_main_panels()
  GuiLayoutEnd(gui)
end}


-- =============================================================================
-- 作弊按钮注册
-- =============================================================================
-- 各作弊功能按钮：编辑法杖、刷新法术、治疗、结束致幻、重置真菌计时、
-- 观光模式、生成魔球、解锁进度
-- =============================================================================

register_cheat_button(function() return T("extra_edit_wands") end, function()
  spawn_perk("EDIT_WANDS_EVERYWHERE", get_player())
end)


register_cheat_button(function() return T("extra_spell_refresh") end, function()
  GameRegenItemActionsInPlayer(get_player())
end)

register_cheat_button(function() return T("extra_full_heal") end, function() quick_heal() end)

register_cheat_button(function() return T("extra_end_trip") end, function()
  EntityRemoveIngestionStatusEffect(get_player(), "TRIP" )
end)

register_cheat_button(function() return T("extra_reset_timer") end, function()
  GlobalsSetValue("fungal_shift_last_frame", "-1000000")
end)

register_cheat_button(function()
  local mode_name = T("tourist_mode_name")
  if tourist_mode_on then
    return TF("tourist_disable_fmt", mode_name)
  else
    return TF("tourist_enable_fmt", mode_name)
  end
end, toggle_tourist_mode)

register_cheat_button(function() return T("extra_spawn_orbs") end, function()
  local x, y = get_player_pos()
  for i = 0, 13 do
    EntityLoad(("data/entities/items/orbs/orb_%02d.xml"):format(i), x+(i*15), y - (i*5))
  end
end)

-- ====== 解锁所有进展（天赋、法术、敌人图鉴） ======
-- 说明：Noita 的「进展」不是用 UnlockItem / KILLED_ 这种 flag 记录，而是：
--  - 法术：需要把对应 action_id 的 persistent flag 设为 action_<id>（ID 必须小写）
--  - 天赋：需要把 persistent flag 设为 perk_picked_<id>（ID 必须小写）
--  - 敌人：需要真正加载敌人实体并调用 StatsLogPlayerKill(eid) 记录击杀
--    优先从 data/ui_gfx/animal_icons/_list.txt 读取 184 个敌人 ID，
--    再按常见 XML 目录路径尝试加载实体；读取失败则回退到已知路径列表

-- 敌人实体常见目录：按此顺序尝试 EntityLoad
local enemy_search_dirs = {
  "data/entities/animals/",
  "data/entities/animals/crypt/",
  "data/entities/animals/drunk/",
  "data/entities/animals/easter/",
  "data/entities/animals/ending_placeholder/",
  "data/entities/animals/illusions/",
  "data/entities/animals/lukki/",
  "data/entities/animals/maggot_tiny/",
  "data/entities/animals/parallel/alchemist/",
  "data/entities/animals/parallel/tentacles/",
  "data/entities/animals/rainforest/",
  "data/entities/animals/robobase/",
  "data/entities/animals/special/",
  "data/entities/animals/the_end/",
  "data/entities/animals/vault/",
  "data/entities/animals/boss_alchemist/",
  "data/entities/animals/boss_centipede/",
  "data/entities/animals/boss_fish/",
  "data/entities/animals/boss_gate/",
  "data/entities/animals/boss_ghost/",
  "data/entities/animals/boss_limbs/",
  "data/entities/animals/boss_pit/",
  "data/entities/animals/boss_robot/",
  "data/entities/animals/boss_wizard/",
  "data/entities/animals/apparition/",
  "data/entities/buildings/",
}

-- _list.txt 动态读取失败时的兜底列表（来自 Dextrome 已验证的完整路径）
local known_enemy_paths = {
  -- 根目录动物
  "data/entities/animals/acidshooter.xml",
  "data/entities/animals/acidshooter_weak.xml",
  "data/entities/animals/alchemist.xml",
  "data/entities/animals/ant.xml",
  "data/entities/animals/assassin.xml",
  "data/entities/animals/barfer.xml",
  "data/entities/animals/basebot_hidden.xml",
  "data/entities/animals/basebot_neutralizer.xml",
  "data/entities/animals/basebot_sentry.xml",
  "data/entities/animals/basebot_soldier.xml",
  "data/entities/animals/bat.xml",
  "data/entities/animals/bigbat.xml",
  "data/entities/animals/bigfirebug.xml",
  "data/entities/animals/bigzombie.xml",
  "data/entities/animals/bigzombiehead.xml",
  "data/entities/animals/bigzombietorso.xml",
  "data/entities/animals/blob.xml",
  "data/entities/animals/bloodcrystal_physics.xml",
  "data/entities/animals/bloom.xml",
  "data/entities/animals/coward.xml",
  "data/entities/animals/chest_leggy.xml",
  "data/entities/animals/chest_mimic.xml",
  "data/entities/animals/crystal_physics.xml",
  "data/entities/animals/darkghost.xml",
  "data/entities/animals/deer.xml",
  "data/entities/animals/drone.xml",
  "data/entities/animals/drone_lasership.xml",
  "data/entities/animals/drone_physics.xml",
  "data/entities/animals/drone_shield.xml",
  "data/entities/animals/duck.xml",
  "data/entities/animals/eel.xml",
  "data/entities/animals/elk.xml",
  "data/entities/animals/enlightened_alchemist.xml",
  "data/entities/animals/ethereal_being.xml",
  "data/entities/animals/failed_alchemist.xml",
  "data/entities/animals/failed_alchemist_b.xml",
  "data/entities/animals/firebug.xml",
  "data/entities/animals/firemage.xml",
  "data/entities/animals/firemage_weak.xml",
  "data/entities/animals/fireskull.xml",
  "data/entities/animals/fireskull_weak.xml",
  "data/entities/animals/fish.xml",
  "data/entities/animals/fish_large.xml",
  "data/entities/animals/flamer.xml",
  "data/entities/animals/fly.xml",
  "data/entities/animals/friend.xml",
  "data/entities/animals/frog.xml",
  "data/entities/animals/frog_big.xml",
  "data/entities/animals/fungus.xml",
  "data/entities/animals/fungus_big.xml",
  "data/entities/animals/fungus_giga.xml",
  "data/entities/animals/fungus_tiny.xml",
  "data/entities/animals/gazer.xml",
  "data/entities/animals/ghost.xml",
  "data/entities/animals/ghoul.xml",
  "data/entities/animals/giant.xml",
  "data/entities/animals/giantshooter.xml",
  "data/entities/animals/giantshooter_weak.xml",
  "data/entities/animals/goblin_bomb.xml",
  "data/entities/animals/healerdrone_physics.xml",
  "data/entities/animals/icemage.xml",
  "data/entities/animals/icer.xml",
  "data/entities/animals/iceskull.xml",
  "data/entities/animals/lasershooter.xml",
  "data/entities/animals/longleg.xml",
  "data/entities/animals/lurker.xml",
  "data/entities/animals/maggot.xml",
  "data/entities/animals/maggot_tiny.xml",
  "data/entities/animals/mimic_physics.xml",
  "data/entities/animals/miner.xml",
  "data/entities/animals/miner_chef.xml",
  "data/entities/animals/miner_fire.xml",
  "data/entities/animals/miner_santa.xml",
  "data/entities/animals/miner_weak.xml",
  "data/entities/animals/miniblob.xml",
  "data/entities/animals/missilecrab.xml",
  "data/entities/animals/monk.xml",
  "data/entities/animals/necrobot.xml",
  "data/entities/animals/necrobot_super.xml",
  "data/entities/animals/necromancer.xml",
  "data/entities/animals/necromancer_shop.xml",
  "data/entities/animals/necromancer_super.xml",
  "data/entities/animals/pebble_physics.xml",
  "data/entities/animals/phantom_a.xml",
  "data/entities/animals/phantom_b.xml",
  "data/entities/animals/playerghost.xml",
  "data/entities/animals/rat.xml",
  "data/entities/animals/roboguard.xml",
  "data/entities/animals/roboguard_big.xml",
  "data/entities/animals/scorpion.xml",
  "data/entities/animals/shaman.xml",
  "data/entities/animals/sheep.xml",
  "data/entities/animals/sheep_bat.xml",
  "data/entities/animals/sheep_fly.xml",
  "data/entities/animals/shooterflower.xml",
  "data/entities/animals/shotgunner.xml",
  "data/entities/animals/shotgunner_weak.xml",
  "data/entities/animals/skullfly.xml",
  "data/entities/animals/skullrat.xml",
  "data/entities/animals/skycrystal_physics.xml",
  "data/entities/animals/skygazer.xml",
  "data/entities/animals/slimeshooter.xml",
  "data/entities/animals/slimeshooter_nontoxic.xml",
  "data/entities/animals/slimeshooter_weak.xml",
  "data/entities/animals/sniper.xml",
  "data/entities/animals/spearbot.xml",
  "data/entities/animals/spitmonster.xml",
  "data/entities/animals/statue.xml",
  "data/entities/animals/statue_physics.xml",
  "data/entities/animals/tank.xml",
  "data/entities/animals/tank_rocket.xml",
  "data/entities/animals/tank_super.xml",
  "data/entities/animals/tentacler.xml",
  "data/entities/animals/tentacler_small.xml",
  "data/entities/animals/thundermage.xml",
  "data/entities/animals/thundermage_big.xml",
  "data/entities/animals/thunderskull.xml",
  "data/entities/animals/turret_left.xml",
  "data/entities/animals/turret_right.xml",
  "data/entities/animals/ultimate_killer.xml",
  "data/entities/animals/wand_ghost.xml",
  "data/entities/animals/wand_ghost_charmed.xml",
  "data/entities/animals/wizard_dark.xml",
  "data/entities/animals/wizard_hearty.xml",
  "data/entities/animals/wizard_homing.xml",
  "data/entities/animals/wizard_neutral.xml",
  "data/entities/animals/wizard_poly.xml",
  "data/entities/animals/wizard_returner.xml",
  "data/entities/animals/wizard_swapper.xml",
  "data/entities/animals/wizard_tele.xml",
  "data/entities/animals/wizard_twitchy.xml",
  "data/entities/animals/wizard_weaken.xml",
  "data/entities/animals/wolf.xml",
  "data/entities/animals/worm.xml",
  "data/entities/animals/worm_big.xml",
  "data/entities/animals/worm_end.xml",
  "data/entities/animals/worm_skull.xml",
  "data/entities/animals/worm_tiny.xml",
  "data/entities/animals/wraith.xml",
  "data/entities/animals/wraith_glowing.xml",
  "data/entities/animals/wraith_storm.xml",
  "data/entities/animals/zombie.xml",
  "data/entities/animals/zombie_weak.xml",

  -- 子目录变体
  "data/entities/animals/crypt/acidshooter.xml",
  "data/entities/animals/crypt/barfer.xml",
  "data/entities/animals/crypt/crystal_physics.xml",
  "data/entities/animals/crypt/enlightened_alchemist.xml",
  "data/entities/animals/crypt/failed_alchemist.xml",
  "data/entities/animals/crypt/maggot.xml",
  "data/entities/animals/crypt/necromancer.xml",
  "data/entities/animals/crypt/phantom_a.xml",
  "data/entities/animals/crypt/phantom_b.xml",
  "data/entities/animals/crypt/skullfly.xml",
  "data/entities/animals/crypt/skullrat.xml",
  "data/entities/animals/crypt/tentacler.xml",
  "data/entities/animals/crypt/tentacler_small.xml",
  "data/entities/animals/crypt/thundermage.xml",
  "data/entities/animals/crypt/wizard_dark.xml",
  "data/entities/animals/crypt/wizard_neutral.xml",
  "data/entities/animals/crypt/wizard_poly.xml",
  "data/entities/animals/crypt/wizard_returner.xml",
  "data/entities/animals/crypt/wizard_tele.xml",
  "data/entities/animals/crypt/worm.xml",
  "data/entities/animals/crypt/worm_skull.xml",

  "data/entities/animals/drunk/miner.xml",
  "data/entities/animals/drunk/miner_chef.xml",
  "data/entities/animals/drunk/miner_fire.xml",
  "data/entities/animals/drunk/miner_weak.xml",
  "data/entities/animals/drunk/scavenger_clusterbomb.xml",
  "data/entities/animals/drunk/scavenger_glue.xml",
  "data/entities/animals/drunk/scavenger_grenade.xml",
  "data/entities/animals/drunk/scavenger_heal.xml",
  "data/entities/animals/drunk/scavenger_invis.xml",
  "data/entities/animals/drunk/scavenger_leader.xml",
  "data/entities/animals/drunk/scavenger_mine.xml",
  "data/entities/animals/drunk/scavenger_poison.xml",
  "data/entities/animals/drunk/scavenger_shield.xml",
  "data/entities/animals/drunk/scavenger_smg.xml",
  "data/entities/animals/drunk/shotgunner.xml",
  "data/entities/animals/drunk/shotgunner_weak.xml",
  "data/entities/animals/drunk/sniper.xml",

  "data/entities/animals/easter/sniper.xml",
  "data/entities/animals/ending_placeholder/boss_dragon_endcrystal.xml",

  "data/entities/animals/illusions/acidshooter.xml",
  "data/entities/animals/illusions/dark_alchemist.xml",
  "data/entities/animals/illusions/enlightened_alchemist.xml",
  "data/entities/animals/illusions/scavenger_grenade.xml",
  "data/entities/animals/illusions/scavenger_mine.xml",
  "data/entities/animals/illusions/shaman.xml",
  "data/entities/animals/illusions/tank.xml",
  "data/entities/animals/illusions/tentacler.xml",
  "data/entities/animals/illusions/thundermage.xml",
  "data/entities/animals/illusions/wizard_swapper.xml",
  "data/entities/animals/illusions/worm_big.xml",

  "data/entities/animals/lukki/lukki.xml",
  "data/entities/animals/lukki/lukki_creepy.xml",
  "data/entities/animals/lukki/lukki_creepy_long.xml",
  "data/entities/animals/lukki/lukki_dark.xml",
  "data/entities/animals/lukki/lukki_longleg.xml",
  "data/entities/animals/lukki/lukki_tiny.xml",

  "data/entities/animals/maggot_tiny/maggot_tiny.xml",
  "data/entities/animals/parallel/alchemist/parallel_alchemist.xml",
  "data/entities/animals/parallel/tentacles/parallel_tentacles.xml",

  "data/entities/animals/rainforest/bloom.xml",
  "data/entities/animals/rainforest/coward.xml",
  "data/entities/animals/rainforest/flamer.xml",
  "data/entities/animals/rainforest/fly.xml",
  "data/entities/animals/rainforest/fungus.xml",
  "data/entities/animals/rainforest/scavenger_clusterbomb.xml",
  "data/entities/animals/rainforest/scavenger_grenade.xml",
  "data/entities/animals/rainforest/scavenger_heal.xml",
  "data/entities/animals/rainforest/scavenger_leader.xml",
  "data/entities/animals/rainforest/scavenger_mine.xml",
  "data/entities/animals/rainforest/scavenger_poison.xml",
  "data/entities/animals/rainforest/scavenger_smg.xml",
  "data/entities/animals/rainforest/shooterflower.xml",
  "data/entities/animals/rainforest/sniper.xml",

  "data/entities/animals/robobase/drone_lasership.xml",
  "data/entities/animals/robobase/drone_shield.xml",
  "data/entities/animals/robobase/healerdrone_physics.xml",
  "data/entities/animals/robobase/monk.xml",
  "data/entities/animals/robobase/tank_super.xml",
  "data/entities/animals/robobase/turret_left.xml",
  "data/entities/animals/robobase/turret_right.xml",

  "data/entities/animals/special/minipit.xml",

  "data/entities/animals/the_end/bloodcrystal_physics.xml",
  "data/entities/animals/the_end/gazer.xml",
  "data/entities/animals/the_end/skycrystal_physics.xml",
  "data/entities/animals/the_end/skygazer.xml",
  "data/entities/animals/the_end/spearbot.xml",
  "data/entities/animals/the_end/spitmonster.xml",
  "data/entities/animals/the_end/worm_end.xml",
  "data/entities/animals/the_end/worm_skull.xml",

  "data/entities/animals/vault/acidshooter.xml",
  "data/entities/animals/vault/assassin.xml",
  "data/entities/animals/vault/bigzombie.xml",
  "data/entities/animals/vault/blob.xml",
  "data/entities/animals/vault/coward.xml",
  "data/entities/animals/vault/drone_physics.xml",
  "data/entities/animals/vault/firemage.xml",
  "data/entities/animals/vault/flamer.xml",
  "data/entities/animals/vault/healerdrone_physics.xml",
  "data/entities/animals/vault/icer.xml",
  "data/entities/animals/vault/lasershooter.xml",
  "data/entities/animals/vault/maggot.xml",
  "data/entities/animals/vault/missilecrab.xml",
  "data/entities/animals/vault/roboguard.xml",
  "data/entities/animals/vault/scavenger_glue.xml",
  "data/entities/animals/vault/scavenger_grenade.xml",
  "data/entities/animals/vault/scavenger_heal.xml",
  "data/entities/animals/vault/scavenger_leader.xml",
  "data/entities/animals/vault/scavenger_mine.xml",
  "data/entities/animals/vault/scavenger_smg.xml",
  "data/entities/animals/vault/sniper.xml",
  "data/entities/animals/vault/tank.xml",
  "data/entities/animals/vault/tank_rocket.xml",
  "data/entities/animals/vault/tank_super.xml",
  "data/entities/animals/vault/tentacler.xml",
  "data/entities/animals/vault/tentacler_small.xml",
  "data/entities/animals/vault/thundermage.xml",
  "data/entities/animals/vault/thunderskull.xml",
  "data/entities/animals/vault/turret_left.xml",
  "data/entities/animals/vault/turret_right.xml",
  "data/entities/animals/vault/wizard_dark.xml",

  -- BOSS
  "data/entities/animals/boss_alchemist/boss_alchemist.xml",
  "data/entities/animals/boss_alchemist/enlightened_alchemist_boss.xml",
  "data/entities/animals/boss_centipede/boss_centipede.xml",
  "data/entities/animals/boss_dragon.xml",
  "data/entities/animals/boss_fish/fish_giga.xml",
  "data/entities/animals/boss_gate/gate_monster_a.xml",
  "data/entities/animals/boss_gate/gate_monster_b.xml",
  "data/entities/animals/boss_gate/gate_monster_c.xml",
  "data/entities/animals/boss_gate/gate_monster_d.xml",
  "data/entities/animals/boss_ghost/boss_ghost.xml",
  "data/entities/animals/boss_limbs/boss_limbs.xml",
  "data/entities/animals/boss_pit/boss_pit.xml",
  "data/entities/animals/boss_robot/boss_robot.xml",
  "data/entities/animals/boss_wizard/boss_wizard.xml",

  -- 其他
  "data/entities/animals/apparition/playerghost.xml",
  "data/entities/buildings/snowcrystal.xml",
  "data/entities/buildings/hpcrystal.xml",
}

-- 通过 XML 路径加载并记录击杀
local function unlock_enemy(xml_path)
  local ok, eid = pcall(EntityLoad, xml_path, 0, 0)
  if ok and eid and eid ~= 0 then
    pcall(StatsLogPlayerKill, eid)
    pcall(EntityKill, eid)
  end
end

-- 通过敌人名称在所有已知目录中尝试加载
local function unlock_enemy_by_name(name)
  for _, dir in ipairs(enemy_search_dirs) do
    local path = dir .. name .. ".xml"
    local ok, eid = pcall(EntityLoad, path, 0, 0)
    if ok and eid and eid ~= 0 then
      pcall(StatsLogPlayerKill, eid)
      pcall(EntityKill, eid)
      return true
    end
  end
  return false
end

register_cheat_button(function() return T("extra_unlock_progress") end, function()
  GamePrint("正在解锁所有进展...")

  -- 1) 解锁全部法术（法术图鉴 + 可解锁法术）
  --    Noita 内部 action_id 统一小写，必须转小写才能正确匹配进度系统
  local spell_count = 0
  for _, card in ipairs(actions) do
    local id = card.id:lower()
    pcall(UnlockItem, id)
    local ok = pcall(AddFlagPersistent, "action_" .. id)
    if ok then spell_count = spell_count + 1 end
  end
  GamePrint("已解锁法术: " .. spell_count)

  -- 2) 解锁全部天赋（天赋图鉴）
  --    Noita 内部 perk_id 统一小写，必须转小写才能正确匹配进度系统
  local perk_count = 0
  for _, perk in ipairs(perk_list) do
    local ok = pcall(AddFlagPersistent, "perk_picked_" .. perk.id:lower())
    if ok then perk_count = perk_count + 1 end
  end
  GamePrint("已解锁天赋: " .. perk_count)

  -- 3) 解锁全部敌人击杀（敌人图鉴）
  --    优先从 data/ui_gfx/animal_icons/_list.txt 读取准确的 184 个敌人 ID
  --    通过遍历常见 XML 目录路径来加载对应实体，确保 184/184 全覆盖
  local enemy_count = 0
  local enemy_names_from_list = {}

  -- 尝试动态读取游戏内置的 _list.txt
  local ok_list, list_content = pcall(ModTextFileGetContent, "data/ui_gfx/animal_icons/_list.txt")
  if ok_list and list_content then
    for line in list_content:gmatch("[^\r\n]+") do
      local name = line:match("^(.-)%.png$")
      if name and #name > 0 then
        enemy_names_from_list[#enemy_names_from_list + 1] = name
        if unlock_enemy_by_name(name) then
          enemy_count = enemy_count + 1
        end
      end
    end
  end

  -- 如果动态读取失败（_list.txt 无法访问），回退到已知路径列表
  if #enemy_names_from_list == 0 then
    GamePrint("_list.txt 无法读取，使用已知道路列表...")
    for _, xml_path in ipairs(known_enemy_paths) do
      pcall(unlock_enemy, xml_path)
      enemy_count = enemy_count + 1
    end
  end

  GamePrint("已解锁敌人击杀: " .. enemy_count)

  GamePrintImportant("解锁所有进展", "天赋/法术/敌人图鉴已全部解锁！")
end)

enter_panel(menu_panel)


-- =============================================================================
-- 信息小部件注册（显示在最小化状态栏）
-- =============================================================================
-- 包括：游玩时间、探索区域、金币、红心、物品、射击数、踢击数、
-- 击杀数、伤害、帧数、坐标、炼金术配方（LC/AP）
-- =============================================================================

local function StatsWidget(dispname, keyname, extra_pad)
  local width = math.ceil(#dispname * 0.9) + (extra_pad or 3)
  return {
    text = function()
      return TF("widget_stat_fmt", dispname, StatsGetValue(keyname) or "?")
    end,
    on_click = function()
      goto_subpanel(info_panel)
    end,
    width = width
  }
end

register_widget("playtime", StatsWidget(T("widget_playtime"), "playtime_str", 6))
register_widget("visited", StatsWidget(T("widget_visited"), "places_visited"))
register_widget("gold", StatsWidget(T("widget_gold"), "gold_all"))
register_widget("hearts", StatsWidget(T("widget_hearts"), "heart_containers"))
register_widget("items", StatsWidget(T("widget_items"), "items"))
register_widget("projectiles", StatsWidget(T("widget_shot"), "projectiles_shot", 3))
register_widget("kicks", StatsWidget(T("widget_kicked"), "kicks"))
register_widget("kills", StatsWidget(T("widget_kills"), "enemies_killed"))
register_widget("damage", StatsWidget(T("widget_damage"), "damage_taken"))
register_widget("frame", {
  text = function()
    return TF("widget_frame_fmt", GameGetFrameNum())
  end,
  on_click = function()
    goto_subpanel(info_panel)
  end,
  width = 16
})

register_widget("position", {
  text = function()
    local x, y = get_player_pos()
    return TF("widget_position_fmt", x, y)
  end,
  on_click = function()
    goto_subpanel(info_panel)
  end,
  width = 15
})

local localize_alchemy = false

for _, recipe in ipairs{"LC", "AP"} do
  local maxwidth = math.max(
    #(alchemy_combos[recipe][true]), 
    #(alchemy_combos[recipe][false])
  )

  register_widget(recipe, {
    text = function()
      return TF("widget_alchemy_fmt", recipe, alchemy_combos[recipe][localize_alchemy])
    end,
    on_click = function()
      localize_alchemy = not localize_alchemy
    end,
    width = math.ceil(maxwidth * 0.75)
  })
end

-- =============================================================================
-- 主渲染循环（每帧由 OnWorldPostUpdate 调用）
-- =============================================================================
-- 1. GuiStartFrame() 启动一个新的 GUI 帧
-- 2. reset_id() 重置按钮 ID 计数器
-- 3. handle_typing() 处理键盘输入
-- 4. 执行当前活跃面板的渲染函数
-- 5. 驱动协程和 WebSocket 服务器
-- =============================================================================
function _cheat_gui_main()
  if gui ~= nil then
    GuiStartFrame( gui )  -- 开始 GUI 帧
  end

  if _gui_frame_function ~= nil then
    reset_id()            -- 重置按钮 ID
    handle_typing()       -- 处理键盘输入
    local happy, errstr = pcall(_gui_frame_function)  -- 安全执行面板函数
    if not happy then
      print("Gui error: " .. errstr)
      GamePrint(TF("log_gui_error", errstr))
      if console_connected then
        send_all_consoles(errstr .. ":" .. debug.traceback())
      end
      hide_gui()  -- 出错时隐藏 GUI，避免反复崩溃
    end
  end

  wake_up_waiting_threads(1) -- 驱动协程（来自 coroutines.lua）
  if console_connected and _socket_update then _socket_update() end  -- 驱动 WebSocket
end

hide_gui()