-- =============================================================================
-- alchemy.lua - 炼金术配方推算模块
-- =============================================================================
-- 复现了 Noita 游戏内 LC（活性混合物）和 AP（炼金前体）的计算逻辑。
-- 通过世界种子推算出当前世界的炼金术配方所需的材料组合。
-- =============================================================================

-- 伪随机数生成器：复现 Noita 内置的 PRNG 算法
local function hax_prng_next(v)
  local hi = math.floor(v / 127773.0)
  local lo = v % 127773
  v = 16807 * lo - 2836 * hi
  if v <= 0 then
    v = v + 2147483647
  end
  return v
end

-- Fisher-Yates 洗牌算法：根据种子打乱数组顺序
local function shuffle(arr, seed)
  local v = math.floor(seed / 2) + 0x30f6
  v = hax_prng_next(v)
  for i = #arr, 1, -1 do
    v = hax_prng_next(v)
    local fidx = v / 2^31
    local target = math.floor(fidx * i) + 1
    arr[i], arr[target] = arr[target], arr[i]
  end
end

-- 液体材料列表（炼金术配方中前三种材料的候选池）
local LIQUIDS = {"acid",
"alcohol",
"blood",
"blood_fungi",
"blood_worm",
"cement",
"lava",
"magic_liquid_berserk",
"magic_liquid_charm",
"magic_liquid_faster_levitation",
"magic_liquid_faster_levitation_and_movement",
"magic_liquid_invisibility",
"magic_liquid_mana_regeneration",
"magic_liquid_movement_faster",
"magic_liquid_protection_all",
"magic_liquid_teleportation",
"magic_liquid_unstable_polymorph",
"magic_liquid_unstable_teleportation",
"magic_liquid_worm_attractor",
"material_confusion",
"mud",
"oil",
"poison",
"radioactive_liquid",
"swamp",
"urine"  ,
"water",
"water_ice",
"water_swamp",
"magic_liquid_random_polymorph"}

-- 固体/有机材料列表（炼金术配方中第四种材料的候选池）
local ORGANICS = {"bone",
"brass",
"coal",
"copper",
"diamond",
"fungi",
"gold",
"grass",
"gunpowder",
"gunpowder_explosive",
"rotten_meat",
"sand",
"silver",
"slime",
"snow",
"soil",
"wax",
"honey"}

-- 浅拷贝数组（因为 random_material 会修改原数组）
local function copy_arr(arr)
  local ret = {}
  for k, v in pairs(arr) do ret[k] = v end
  return ret
end

-- 从材料列表中随机选取一个材料（不重复选取，最多尝试 1000 次）
local function random_material(v, mats)
  for _ = 1, 1000 do
    v = hax_prng_next(v)
    local rval = v / 2^31
    local sel_idx = math.floor(#mats * rval) + 1
    local selection = mats[sel_idx]
    if selection then
      mats[sel_idx] = false  -- 标记为已使用，避免重复
      return v, selection
    end
  end
end

-- 生成一个随机炼金术配方
-- 从液体列表中选 3 种，有机列表中选 1 种，打乱前 3 个顺序作为配方
local function random_recipe(rand_state, seed)
  local liqs = copy_arr(LIQUIDS)
  local orgs = copy_arr(ORGANICS)
  local m1, m2, m3, m4 = "?", "?", "?", "?"
  rand_state, m1 = random_material(rand_state, liqs)   -- 第1种液体
  rand_state, m2 = random_material(rand_state, liqs)   -- 第2种液体
  rand_state, m3 = random_material(rand_state, liqs)   -- 第3种液体
  rand_state, m4 = random_material(rand_state, orgs)   -- 有机材料
  local combo = {m1, m2, m3, m4}

  rand_state = hax_prng_next(rand_state)
  local prob = 10 + math.floor((rand_state / 2^31) * 91)  -- 生成概率 10%-100%
  rand_state = hax_prng_next(rand_state)

  shuffle(combo, seed)  -- 用种子打乱，使配方与种子绑定
  return rand_state, {combo[1], combo[2], combo[3]}, prob  -- 返回前3种 + 概率
end

-- 对外接口：获取当前世界的炼金术配方
-- 返回：lc_combo（LC材料组合）, ap_combo（AP材料组合）, lc_prob（LC概率）, ap_prob（AP概率）
function get_alchemy()
  local seed = tonumber(StatsGetValue("world_seed"))  -- 获取世界种子
  local rand_state = math.floor(seed * 0.17127000 + 1323.59030000)

  -- 跳过前6次随机数，与游戏内逻辑保持一致
  for i = 1, 6 do
    rand_state = hax_prng_next(rand_state)
  end

  local lc_combo, ap_combo = {"?"}, {"?"}
  rand_state, lc_combo, lc_prob = random_recipe(rand_state, seed)  -- LC（活性混合物）
  rand_state, ap_combo, ap_prob = random_recipe(rand_state, seed)  -- AP（炼金前体）

  return lc_combo, ap_combo, lc_prob, ap_prob
end