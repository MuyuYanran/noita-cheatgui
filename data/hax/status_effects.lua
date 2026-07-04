-- =============================================================================
-- status_effects.lua - 状态效果管理面板
-- =============================================================================
-- 查看/添加/移除玩家状态效果（无敌、隐形、混乱、变形、护盾等）
-- API:
--   GetGameEffectLoadTo(entity, name, always_load_new) -- 用枚举名添加
--   GameGetGameEffect(entity, name) -> component_id     -- 按名字查询
--   EntityGetComponent(entity, "GameEffectComponent")   -- 列出所有效果组件
--   EntityRemoveComponent(entity, comp_id)              -- 移除单个效果
--   EntityRemoveIngestionStatusEffect(entity, name)     -- 仅对中毒类有效
--   移除：通过对玩家上每个 GameEffectComponent 调用 EntityRemoveComponent
--   名字查映射用本地表 EFFECT_DISPLAY；找不到时回退到 "EFFECT_<NAME>"
-- =============================================================================

-- 常用状态效果列表（枚举名 -> 显示名）
-- 显示名优先查 EFFECT_DISPLAY 表；UNKNOWN 时显示 "EFFECT_<NAME>"
local KNOWN_EFFECTS = {
  "PROTECTION_ALL",       -- 全伤害免疫
  "PROTECTION_FIRE",      -- 火焰免疫
  "PROTECTION_RADIOACTIVITY", -- 辐射免疫
  "PROTECTION_EXPLOSION", -- 爆炸免疫
  "PROTECTION_MELEE",     -- 近战免疫
  "PROTECTION_PROJECTILE",-- 弹丸免疫
  "PROTECTION_ELECTRICITY", -- 电击免疫
  "PROTECTION_FREEZE",    -- 冰冻免疫
  "INVISIBILITY",         -- 隐形
  "BERSERK",              -- 狂暴
  "WET",                  -- 潮湿
  "OILY",                 -- 油污
  "REGENERATION",         -- 再生
  "FASTER_LEVITATION",    -- 快速悬浮
  "FASTER_MOVEMENT",      -- 快速移动
  "HOMING_SHOOTER",       -- 追踪射击
  "DAMAGE_BOOST",         -- 伤害增强
  "GRAVITY",              -- 重力场
  "NEAR_SIGHT",           -- 近视
  "TWITCHY",              -- 抽搐
  "POISON_BLIND",         -- 致盲中毒
  "WORM_ATTRACTOR",       -- 蠕虫吸引
  "WORM_DETRACTOR",       -- 蠕虫排斥
  "MANA_REGENERATION",    -- 法力再生
  "RAINBOW_FARTS",        -- 彩虹屁
  "ELECTRIFIED",          -- 带电
  "FREEZING",             -- 冰冻
  "CHARM",                -- 魅惑
  "CONFUSION",            -- 混乱
  "FOOD_POISONING",       -- 食物中毒
  "WEAKNESS",             -- 虚弱
  "TELEPORTITIS",         -- 传送症
  "PERSONAL_RAINCLOUD",   -- 个人雨云
  "PERSONAL_THUNDERSTORM",-- 个人雷暴
  "ON_FIRE",              -- 着火
  "TRIP",                 -- 致幻
  "ENERGY_SHIELD",        -- 能量护盾
  "DAMAGE_BOOST_ALL",     -- 全伤害增强
  "MORPHINE",             -- 麻醉
  "STUN",                 -- 眩晕
  "SAVING_GRACE",         -- 救赎恩典
  "EXTRA_LIFE",           -- 额外生命
  "PERMANENT_SHIELD",     -- 永久护盾
  "REVENGE_BULLET",       -- 复仇弹丸
  "REVENGE_EXPLOSION",    -- 复仇爆炸
  "EGG_TEMP",             -- 蛋温度
  "MUMMY_TEMP",           -- 木乃伊温度
  "GLUE",                 -- 胶水
}

-- 效果枚举名 → 显示名（中英文都覆盖）
-- 取自 Noita 实际 UI 中"活跃状态效果"列表显示的中文名
local EFFECT_DISPLAY = {
  PROTECTION_ALL            = { en = "All Damage Immunity",       zh = "全伤害免疫" },
  PROTECTION_FIRE           = { en = "Fire Immunity",             zh = "火焰免疫" },
  PROTECTION_RADIOACTIVITY  = { en = "Radioactivity Immunity",    zh = "辐射免疫" },
  PROTECTION_EXPLOSION      = { en = "Explosion Immunity",        zh = "爆炸免疫" },
  PROTECTION_MELEE          = { en = "Melee Immunity",            zh = "近战免疫" },
  PROTECTION_PROJECTILE     = { en = "Projectile Immunity",       zh = "弹丸免疫" },
  PROTECTION_ELECTRICITY    = { en = "Electricity Immunity",      zh = "电击免疫" },
  PROTECTION_FREEZE         = { en = "Freeze Immunity",           zh = "冰冻免疫" },
  INVISIBILITY              = { en = "Invisibility",              zh = "隐形" },
  BERSERK                   = { en = "Berserk",                   zh = "狂暴" },
  WET                       = { en = "Wet",                       zh = "潮湿" },
  OILY                      = { en = "Oily",                      zh = "油污" },
  REGENERATION              = { en = "Regeneration",              zh = "再生" },
  FASTER_LEVITATION         = { en = "Faster Levitation",         zh = "快速悬浮" },
  FASTER_MOVEMENT           = { en = "Faster Movement",           zh = "快速移动" },
  HOMING_SHOOTER            = { en = "Homing Shots",              zh = "追踪弹" },
  DAMAGE_BOOST              = { en = "Damage Boost",              zh = "伤害增强" },
  GRAVITY                   = { en = "Gravity Field",             zh = "重力场" },
  NEAR_SIGHT                = { en = "Near Sight",                zh = "近视" },
  TWITCHY                   = { en = "Twitchy",                   zh = "抽搐" },
  POISON_BLIND              = { en = "Poison/Blind",              zh = "致盲中毒" },
  WORM_ATTRACTOR            = { en = "Worm Attractor",            zh = "蠕虫吸引" },
  WORM_DETRACTOR            = { en = "Worm Detractor",            zh = "蠕虫排斥" },
  MANA_REGENERATION         = { en = "Mana Regeneration",         zh = "法力再生" },
  RAINBOW_FARTS             = { en = "Rainbow Farts",             zh = "彩虹屁" },
  ELECTRIFIED               = { en = "Electrified",               zh = "带电" },
  FREEZING                  = { en = "Freezing",                  zh = "冰冻" },
  CHARM                     = { en = "Charm",                     zh = "魅惑" },
  CONFUSION                 = { en = "Confusion",                 zh = "混乱" },
  FOOD_POISONING            = { en = "Food Poisoning",            zh = "食物中毒" },
  WEAKNESS                  = { en = "Weakness",                  zh = "虚弱" },
  TELEPORTITIS              = { en = "Teleportitis",              zh = "传送症" },
  PERSONAL_RAINCLOUD        = { en = "Personal Raincloud",        zh = "个人雨云" },
  PERSONAL_THUNDERSTORM     = { en = "Personal Thunderstorm",     zh = "个人雷暴" },
  ON_FIRE                   = { en = "On Fire",                   zh = "着火" },
  TRIP                      = { en = "Tripping",                  zh = "致幻" },
  ENERGY_SHIELD             = { en = "Energy Shield",             zh = "能量护盾" },
  DAMAGE_BOOST_ALL          = { en = "All Damage Boost",          zh = "全伤害增强" },
  MORPHINE                  = { en = "Morphine",                  zh = "麻醉" },
  STUN                      = { en = "Stun",                      zh = "眩晕" },
  SAVING_GRACE              = { en = "Saving Grace",              zh = "救赎恩典" },
  EXTRA_LIFE                = { en = "Extra Life",                zh = "额外生命" },
  PERMANENT_SHIELD          = { en = "Permanent Shield",          zh = "永久护盾" },
  REVENGE_BULLET            = { en = "Revenge Bullet",            zh = "复仇弹丸" },
  REVENGE_EXPLOSION         = { en = "Revenge Explosion",         zh = "复仇爆炸" },
  EGG_TEMP                  = { en = "Egg Temperature",           zh = "蛋温度" },
  MUMMY_TEMP                = { en = "Mummy Temperature",         zh = "木乃伊温度" },
  GLUE                      = { en = "Glue",                      zh = "胶水" },
}

-- 取当前语言的显示名
local function effect_display(name)
  local entry = EFFECT_DISPLAY[name]
  if entry then
    local lang = (_i18n and _i18n.language) or "zh"
    return entry[lang] or entry.zh or entry.en or name
  end
  return "EFFECT_" .. name
end

-- 分离负面效果（用于一键清除）
local NEGATIVE_EFFECTS = {
  "POISON_BLIND", "ON_FIRE", "FREEZING", "WET", "STUN",
  "CONFUSION", "FOOD_POISONING", "WEAKNESS", "WORM_ATTRACTOR",
  "GLUE", "TELEPORTITIS", "NEAR_SIGHT", "TWITCHY",
  "PERSONAL_RAINCLOUD", "PERSONAL_THUNDERSTORM",
}

-- =============================================================================
-- 添加 / 移除 状态效果
-- =============================================================================

-- 添加状态效果：使用 GetGameEffectLoadTo（用枚举名而非 XML 路径）
local function add_effect(effect_name)
  local player = get_player()
  if not player then return end
  local ok, comp_id, effect_eid = pcall(GetGameEffectLoadTo, player, effect_name, true)
  if ok and comp_id and comp_id ~= 0 then
    GamePrint("已添加: " .. effect_name)
  else
    GamePrint("添加失败: " .. effect_name .. (ok and "" or (" (" .. tostring(comp_id) .. ")")))
  end
end

-- 移除状态效果：
-- Noita 状态效果多以子实体形式挂在玩家下；EntityGetAllComponents 不会递归子实体。
-- 正确做法：通过 GameGetGameEffect(entity, name) 拿到 component_id，
-- 再用 ComponentGetEntity(comp) 找到拥有者实体，最后 EntityRemoveComponent/EntityKill。
local function remove_effect(effect_name)
  local player = get_player()
  if not player then return end
  local removed = 0

  -- 部分摄入类效果（食物中毒/中毒）可能不注册为 GameEffectComponent，先走 ingestion 通道
  local ok_ingest = pcall(EntityRemoveIngestionStatusEffect, player, effect_name)
  if ok_ingest then removed = removed + 1 end

  -- 通用通道：用 GameGetGameEffect 查询（递归子实体），然后删除其所在实体上的组件
  while true do
    local ok, comp = pcall(GameGetGameEffect, player, effect_name)
    if not ok or not comp or comp == 0 then break end
    local ok2, owner = pcall(ComponentGetEntity, comp)
    if ok2 and owner and owner ~= 0 then
      local ok3 = pcall(EntityRemoveComponent, owner, comp)
      if ok3 then
        removed = removed + 1
      else
        break
      end
    else
      break
    end
  end

  if removed > 0 then
    GamePrint("已移除: " .. effect_name .. " (×" .. removed .. ")")
  else
    GamePrint("未找到效果: " .. effect_name)
  end
end

-- 移除所有负面效果
local function remove_all_negative()
  local player = get_player()
  if not player then return end
  local total = 0
  for _, effect in ipairs(NEGATIVE_EFFECTS) do
    -- ingestion 通道
    local ok_ingest = pcall(EntityRemoveIngestionStatusEffect, player, effect)
    if ok_ingest then total = total + 1 end
    -- GameEffect 通道
    while true do
      local ok, comp = pcall(GameGetGameEffect, player, effect)
      if not ok or not comp or comp == 0 then break end
      local ok2, owner = pcall(ComponentGetEntity, comp)
      if ok2 and owner and owner ~= 0 then
        local ok3 = pcall(EntityRemoveComponent, owner, comp)
        if ok3 then
          total = total + 1
        else
          break
        end
      else
        break
      end
    end
  end
  GamePrint("已移除负面效果 × " .. total)
end

-- =============================================================================
-- 活跃效果列表
-- =============================================================================

-- 用 GameGetGameEffectCount/GameGetGameEffect 查询（会递归玩家子实体）。
-- 返回 { name = 枚举名, count = 叠加数量 } 的列表。
local function get_active_effects()
  local player = get_player()
  if not player then return {} end

  local counts = {}
  for _, name in ipairs(KNOWN_EFFECTS) do
    local ok, cnt = pcall(GameGetGameEffectCount, player, name)
    if ok and cnt and cnt > 0 then
      counts[name] = cnt
    end
  end

  -- 也额外检查不在 KNOWN_EFFECTS 里的 GameEffectComponent（按子实体组件兜底）
  local ok, comps = pcall(EntityGetAllComponents, player)
  if ok and comps then
    for _, comp in ipairs(comps) do
      local ok2, type_name = pcall(ComponentGetTypeName, comp)
      if ok2 and type_name == "GameEffectComponent" then
        local ok3, effect_val = pcall(ComponentGetValue2, comp, "effect", "name")
        if ok3 and type(effect_val) == "string" and effect_val ~= "" and not counts[effect_val] then
          counts[effect_val] = (counts[effect_val] or 0) + 1
        end
      end
    end
  end

  local list = {}
  for name, cnt in pairs(counts) do
    table.insert(list, {name = name, count = cnt})
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

-- =============================================================================
-- UI 面板
-- =============================================================================

local active_page = 1
local page_size = 20

local function build_effect_buttons()
  local total_pages = math.ceil(#KNOWN_EFFECTS / page_size)
  local start_idx = (active_page - 1) * page_size + 1
  local end_idx = math.min(start_idx + page_size - 1, #KNOWN_EFFECTS)

  GuiLayoutBeginVertical(gui, 1, 11)

  -- 活跃状态效果
  local active = get_active_effects()
  local total_active = 0
  for _, e in ipairs(active) do total_active = total_active + e.count end
  GuiText(gui, 0, 0, "活跃状态效果 (" .. total_active .. "):")
  if #active == 0 then
    GuiText(gui, 0, 0, "  (无)")
  else
    for _, e in ipairs(active) do
      GuiLayoutBeginHorizontal(gui, 0, 0)
      local count_str = (e.count > 1) and (" × " .. e.count) or ""
      GuiText(gui, 0, 0, "  " .. effect_display(e.name) .. count_str)
      if GuiButton(gui, 0, 0, "[X]", next_id()) then
        remove_effect(e.name)
      end
      GuiLayoutEnd(gui)
    end
  end

  GuiText(gui, 0, 0, " ")
  GuiText(gui, 0, 0, "---- 添加效果 ----")

  -- 快速添加按钮
  GuiLayoutBeginHorizontal(gui, 0, 0)
  if GuiButton(gui, 0, 0, "[无敌]", next_id()) then add_effect("PROTECTION_ALL") end
  if GuiButton(gui, 0, 0, "[隐形]", next_id()) then add_effect("INVISIBILITY") end
  if GuiButton(gui, 0, 0, "[追踪]", next_id()) then add_effect("HOMING_SHOOTER") end
  if GuiButton(gui, 0, 0, "[传病]", next_id()) then add_effect("TELEPORTITIS") end
  GuiLayoutEnd(gui)

  -- 一键清除负面
  if GuiButton(gui, 0, 0, "[清除所有负面效果]", next_id()) then
    remove_all_negative()
  end

  GuiText(gui, 0, 0, " ")

  -- 效果列表（分页）
  for i = start_idx, end_idx do
    local name = KNOWN_EFFECTS[i]
    local label = "[添加] " .. name .. "  —  " .. effect_display(name)
    if GuiButton(gui, 0, 0, label, next_id()) then
      add_effect(name)
    end
  end

  -- 分页控制
  if total_pages > 1 then
    GuiLayoutBeginHorizontal(gui, 0, 0)
    if active_page > 1 then
      if GuiButton(gui, 0, 0, "<-", next_id()) then
        active_page = active_page - 1
      end
    end
    GuiText(gui, 0, 0, " " .. active_page .. "/" .. total_pages .. " ")
    if active_page < total_pages then
      if GuiButton(gui, 0, 0, "->", next_id()) then
        active_page = active_page + 1
      end
    end
    GuiLayoutEnd(gui)
  end

  GuiLayoutEnd(gui)
end

status_effects_panel = Panel{function() return T("panel_status_effects") end, function()
  breadcrumbs(1, 0)
  build_effect_buttons()
end}
