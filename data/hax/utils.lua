-- =============================================================================
-- utils.lua - 通用工具函数模块
-- =============================================================================
-- 提供常用的游戏操作工具函数，包括玩家操作、实体生成、组件调试等。
-- 同时是 Web 远程控制台的可用命令集。
-- =============================================================================

-- 获取玩家实体
function get_player()
  return EntityGetWithTag("player_unit")[1]
end

-- 获取玩家当前坐标
function get_player_pos()
  local player = get_player()
  if not player then return 0, 0 end
  return EntityGetTransform(player)
end

-- 启用/禁用实体的 AI 组件
function enable_ai(e, enabled)
  local ai = EntityGetFirstComponent(e, "AnimalAIComponent")
  if not ai then print("no ai??") end
  EntitySetComponentIsEnabled(e, ai, enabled)
end

-- 传送玩家到指定坐标
function teleport(x, y)
  EntitySetTransform(get_player(), x, y)
end

-- 获取玩家生命值（当前 HP, 最大 HP）
function get_health()
  local dm = EntityGetComponent(get_player(), "DamageModelComponent")[1]
  return ComponentGetValue(dm, "hp"), ComponentGetValue(dm, "max_hp")
end

-- 设置玩家生命值
function set_health(cur_hp, max_hp)
  local damagemodels = EntityGetComponent(get_player(), "DamageModelComponent")
  for _, damagemodel in ipairs(damagemodels or {}) do
    ComponentSetValue(damagemodel, "max_hp", max_hp)
    ComponentSetValue(damagemodel, "hp", cur_hp)
  end
end

-- 快速治疗：将当前生命设为最大生命
function quick_heal()
  local _, max_hp = get_health()
  set_health(max_hp, max_hp)
end

-- 设置金币数量
function set_money(amt)
  local wallet = EntityGetFirstComponent(get_player(), "WalletComponent")
  ComponentSetValue2(wallet, "money", amt)
end

-- 获取当前金币数量
function get_money()
  local wallet = EntityGetFirstComponent(get_player(), "WalletComponent")
  return ComponentGetValue2(wallet, "money")
end

-- 增减金币（不会低于 0）
function twiddle_money(delta)
  local wallet = EntityGetFirstComponent(get_player(), "WalletComponent")
  local current = ComponentGetValue2(wallet, "money")
  ComponentSetValue2(wallet, "money", math.max(0, current+delta))
end

-- 在玩家附近生成实体
-- @param ename    实体文件路径
-- @param offset_x 相对玩家的 X 偏移
-- @param offset_y 相对玩家的 Y 偏移
function spawn_entity(ename, offset_x, offset_y)
  local x, y = get_player_pos()
  x = x + (offset_x or 0)
  y = y + (offset_y or 0)
  return EntityLoad(ename, x, y)
end
spawn_item = spawn_entity  -- 别名

-- 清空实体容器内的所有材料
function empty_container_of_materials(idx)
  for _ = 1, 1000 do -- 安全上限，避免无限循环
    local material = GetMaterialInventoryMainMaterial(idx)
    if material <= 0 then break end
    local matname = CellFactory_GetName(material)
    AddMaterialInventoryMaterial(idx, matname, 0)
  end
end

-- 生成药水/粉末袋
-- @param material 材料名称
-- @param quantity 数量
-- @param kind     "potion"（药水瓶）或 "pouch"（粉末袋）
function spawn_potion(material, quantity, kind)
  local x, y = get_player_pos()
  quantity = quantity or 1000
  local entity
  if kind == nil or kind == "potion" then 
    entity = EntityLoad("data/entities/items/pickup/potion_empty.xml", x, y)
  else -- 粉末袋类型
    entity = EntityLoad("data/entities/items/pickup/powder_stash.xml", x, y)
    empty_container_of_materials(entity)  -- 清空默认内容
    quantity = quantity * 1.5  -- 粉末袋需要更多材料
  end
  AddMaterialInventoryMaterial(entity, material, quantity)
end

-- 生成天赋并可选自动拾取
-- @param perk_id             天赋 ID
-- @param auto_pickup_entity  如果提供，将天赋自动赋予该实体
function spawn_perk(perk_id, auto_pickup_entity)
  local x, y = get_player_pos()
  local perk_entity = perk_spawn(x, y - 8, perk_id)
  if auto_pickup_entity then
    perk_pickup(perk_entity, auto_pickup_entity, nil, true, false)
  end
end

-- 观光模式：将玩家设为 healer 阵营（敌人不攻击）
function set_tourist_mode(enabled)
  local herd = (enabled and "healer") or "player"
  GenomeSetHerdId(get_player(), herd)
end

-- 测试函数：打印 Hello
function hello()
  GamePrintImportant("Hello", "Hello")
  GamePrint("Hello")
  print("Hello")
end

-- 查找最近的指定标签实体
function get_closest_entity(px, py, tag)
  if not py then
    tag = px
    px, py = get_player_pos()  -- 仅传入一个参数时，以玩家位置为准
  end
  return EntityGetClosestWithTag( px, py, tag)
end

-- 获取鼠标指向的最近实体
function get_entity_mouse(tag)
  local mx, my = DEBUG_GetMouseWorld()
  return get_closest_entity(mx, my, tag or "hittable")
end

-- 打印组件基本信息（成员变量名和值）
function print_component_info(c)
  local frags = {"<" .. ComponentGetTypeName(c) .. ">"}
  local members = ComponentGetMembers(c)
  if not members then return end
  for k, v in pairs(members) do
    table.insert(frags, k .. ': ' .. tostring(v))
  end
  print(table.concat(frags, '\n'))
end

-- 获取组件的向量成员值
function get_vector_value(comp, member, kind)
  kind = kind or "float"
  local n = ComponentGetVectorSize( comp, member, kind )
  if not n then return nil end
  local ret = {};
  for i = 1, n do
    ret[i] = ComponentGetVectorValue(comp, member, kind, i-1) or "nil"
  end
  return ret
end

-- 格式化打印向量值
function print_vector_value(...)
  local v = get_vector_value(...)
  if not v then return nil end
  return "{" .. table.concat(v, ", ") .. "}"
end

-- 打印组件的完整信息（包括嵌套对象成员）
function print_detailed_component_info(c)
  local members = ComponentGetMembers(c)
  if not members then return end
  local frags = {}
  for k, v in pairs(members) do
    if (not v) or #v == 0 then
      -- 值为空时，尝试作为嵌套对象读取
      local mems = ComponentObjectGetMembers(c, k)
      if mems then
        table.insert(frags, k .. ">")
        for k2, v2 in pairs(mems) do
          table.insert(frags, "  " .. k2 .. ": " .. tostring(v2))
        end
      else
        v = print_vector_value(c, k)  -- 尝试读取为向量
      end
    end
    table.insert(frags, k .. ': ' .. tostring(v))
  end
  print(table.concat(frags, '\n'))
end

-- 打印实体的所有组件信息
function print_entity_info(e)
  local comps = EntityGetAllComponents(e)
  if not comps then
    print("Invalid entity?")
    return
  end
  for idx, comp in ipairs(comps) do
    print(comp, "-----------------")
    print_component_info(comp)
  end
end

-- 列出实体拥有的所有组件名称
function list_components(e)
  local comps = EntityGetAllComponents(e)
  if not comps then
    print("Invalid entity?")
    return
  end
  for idx, comp in ipairs(comps) do
    print(comp .. " : " .. ComponentGetTypeName(comp))
  end
end

-- 列出当前环境中的所有 C++ 导出函数（首字母大写即 API 函数）
function list_funcs(filter)
  local ff = {}
  for k, v in pairs(getfenv()) do
    local first_letter = k:sub(1,1)
    if first_letter:upper() == first_letter then
      if (not filter) or k:lower():find(filter:lower()) then
        table.insert(ff, k)
      end
    end
  end
  table.sort(ff)
  print(table.concat(ff, "\n"))
end

-- 获取实体的子实体信息
function get_child_info(e)
  local children = EntityGetAllChildren(e)
  for _, child in ipairs(children) do
    print(child, EntityGetName(child) or "[no name]")
  end
end

-- 在当前环境中执行指定的 Lua 文件
function do_here(fn)
  local f = loadfile(fn)
  if type(f) ~= "function" then
    print("Loading error; check logger.txt for details.")
  end
  setfenv(f, getfenv())
  f()
end

-- 四舍五入
function round(v)
  local upper = math.ceil(v)
  local lower = math.floor(v)
  if math.abs(v - upper) < math.abs(v - lower) then
    return upper
  else
    return lower
  end
end

-- 解析本地化名称：如果字符串以 "$" 开头，尝试从游戏中获取翻译
function resolve_localized_name(s, default)
  if s:sub(1,1) ~= "$" then return s end
  local rep = GameTextGet(s)
  if rep and rep ~= "" then return rep else return default or s end
end

-- 获取材料的本地化名称
function localize_material(mat)
  local n = GameTextGet("$mat_" .. mat)
  if n and n ~= "" then return n else return "[" .. mat .. "]" end
end