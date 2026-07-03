-- =============================================================================
-- materials.lua - 材料列表数据模块
-- =============================================================================
-- 在模组初始化时从 Noita 引擎获取所有可用材料，按类别（液体/固体/沙/气/火）
-- 分类整理成 materials_list 表，供 GUI 中材料选择界面使用。
-- =============================================================================

materials_list = {}

-- 默认名称获取函数：直接返回材料内部 ID
local get_name = function(mat)
  return mat
end

if not DebugGetIsDevBuild() then
  -- 非开发版本中，使用游戏本地化名称替换内部 ID
  -- （开发版本中 GameTextGet 会对未翻译的 key 发出警告，太吵了）
  get_name = function(mat)
    local n = GameTextGet("$mat_" .. mat)
    if n and n ~= "" then return n else return "[" .. mat .. "]" end
  end
end

-- 遍历所有材料类别，构建材料列表
-- 每类前插入分隔行 "---- 类别名 ----"
for _, category in ipairs{"Liquids", "Solids", "Sands", "Gases", "Fires"} do
  table.insert(materials_list, {"-- " .. category .. " --", "-- " .. category .. " --"})
  local mats = getfenv()["CellFactory_GetAll" .. category]()  -- 调用对应 C++ API
  table.sort(mats)  -- 按字母排序
  for _, mat in ipairs(mats) do
    table.insert(materials_list, {mat, get_name(mat)})  -- {内部ID, 显示名称}
  end
end

-- local getters = {
--   {"Fires", CellFactory_GetAllFires, 
--   CellFactory_GetAllGases,
--   CellFactory_GetAllSolids,
--   CellFactory_GetAllSands,
--   CellFactory_GetAllLiquids
-- }