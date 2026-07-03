-- =============================================================================
-- gun_builder.lua - 法杖构建器模块
-- =============================================================================
-- 程序化生成自定义法杖，可配置法力、槽位、散射、施法延迟等所有属性。
-- 先加载空法杖模板，再通过 ComponentSetValue 逐个覆盖参数。
-- =============================================================================

dofile("data/scripts/gun/procedural/gun_procedural.lua")

-- 在指定坐标生成自定义法杖
-- @param x, y  生成坐标
-- @param gun   法杖属性表，包含以下可选字段：
--   deck_capacity      - 法术槽位数量
--   actions_per_round  - 每轮施法数量（多重施法）
--   reload_time        - 充能时间
--   shuffle_deck_when_empty - 法术空时是否乱序
--   fire_rate_wait     - 射击间隔
--   spread_degrees     - 散射角度
--   speed_multiplier   - 弹丸速度倍率
--   mana_charge_speed  - 法力回复速度
--   mana_max           - 最大法力值
--   always_casts       - 始终施放法术列表
function build_gun(x, y, gun)
  local entity_id = EntityLoad("data/hax/wand_empty.xml", x, y)  -- 加载空法杖模板
	local ability_comp = EntityGetFirstComponent( entity_id, "AbilityComponent" )

  -- 为所有属性设置默认值（未指定时使用）
  gun.cost = gun.cost or 0
  gun.deck_capacity = gun.deck_capacity or 5           -- 法术槽位
  gun.actions_per_round = gun.actions_per_round or 1   -- 多重施法
  gun.reload_time = gun.reload_time or 30              -- 充能时间
  gun.shuffle_deck_when_empty = gun.shuffle_deck_when_empty or 0  -- 是否乱序(0=否)
  gun.fire_rate_wait = gun.fire_rate_wait or 30        -- 射击间隔
  gun.spread_degrees = gun.spread_degrees or 0         -- 散射度
  gun.speed_multiplier = gun.speed_multiplier or 1     -- 弹丸速度倍率
  gun.prob_unshuffle = gun.prob_unshuffle or 0.1
  gun.prob_draw_many = gun.prob_draw_many or 0.15
  gun.mana_charge_speed = gun.mana_charge_speed or 10000  -- 法力回复速度
  gun.mana_max = gun.mana_max or 10000                    -- 最大法力值
  gun.force_unshuffle = gun.force_unshuffle or 1

  local name = "HAXXXX"

  -- 设置法杖基础属性
  ComponentSetValue( ability_comp, "ui_name", name )
  ComponentObjectSetValue( ability_comp, "gun_config", "actions_per_round", gun["actions_per_round"] )
  ComponentObjectSetValue( ability_comp, "gun_config", "reload_time", gun["reload_time"] )
  ComponentObjectSetValue( ability_comp, "gun_config", "deck_capacity", gun["deck_capacity"] )
  ComponentObjectSetValue( ability_comp, "gun_config", "shuffle_deck_when_empty", gun["shuffle_deck_when_empty"] )
  ComponentObjectSetValue( ability_comp, "gunaction_config", "fire_rate_wait", gun["fire_rate_wait"] )
  ComponentObjectSetValue( ability_comp, "gunaction_config", "spread_degrees", gun["spread_degrees"] )
  ComponentObjectSetValue( ability_comp, "gunaction_config", "speed_multiplier", gun["speed_multiplier"] )
  ComponentSetValue( ability_comp, "mana_charge_speed", gun["mana_charge_speed"])
  ComponentSetValue( ability_comp, "mana_max", gun["mana_max"])
  ComponentSetValue( ability_comp, "mana", gun["mana_max"])  -- 当前法力 = 最大法力
  
  -- 将始终施放法术添加到法杖（这些法术不会消耗槽位，每次施法自动触发）
  local always_casts = gun["always_casts"] or {gun["always_cast"]} or {}
  for _, spell_id in ipairs(always_casts) do
    AddGunActionPermanent( entity_id, spell_id )
  end

  -- 设置法杖外观精灵
  local wand = GetWand( gun )
  SetWandSprite( entity_id, ability_comp, wand.file, wand.grip_x, wand.grip_y, (wand.tip_x - wand.grip_x), (wand.tip_y - wand.grip_y) )
end