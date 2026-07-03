-- =============================================================================
-- init.lua - CheatGUI 模组入口点
-- =============================================================================
-- Noita 在加载模组时首先执行此文件。
-- 
-- 主要职责：
--   1. 保存运行环境（cheatgui_stash）：将 _G 保存下来，以便在没有 API 限制
--      的沙箱环境中仍能访问 ModTextFileGetContent 等关键函数。
--   2. 注册事件回调：OnWorldPostUpdate 驱动 GUI 渲染循环，
--      OnPlayerSpawned 加载作弊菜单主逻辑。
--   3. 通过 dofile("data/hax/cheatgui.lua") 加载完整的作弊菜单。
-- =============================================================================

-- 保存运行环境（主要是为了保留 ModTextFileGetContent 等被 Noita 限制的函数）
cheatgui_stash = {}
for k, v in pairs(_G) do
  cheatgui_stash[k] = v
end

-- 每帧更新回调：驱动 GUI 主循环
function OnWorldPostUpdate() 
  if _cheat_gui_main then _cheat_gui_main() end
end

-- 玩家生成回调：加载作弊菜单主逻辑
function OnPlayerSpawned( player_entity )
  print("OnPlayerSpawned require check:")
  if not require then
    print("NO require.")
  else
    print("YES require.")
  end
  dofile("data/hax/cheatgui.lua")  -- 加载主 GUI 文件
end
