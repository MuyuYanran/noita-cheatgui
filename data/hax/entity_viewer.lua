-- =============================================================================
-- entity_viewer.lua - 实体查看器面板
-- =============================================================================
-- 点击实体查看其所有组件及成员值，支持编辑字段
-- API: EntityGetAllComponents, ComponentGetMembers, ComponentGetValue2,
--      ComponentSetValue2, DEBUG_GetMouseWorld
-- UX:
--   - "捕获模式"：点击 [捕获鼠标指向实体] 后，在接下来 3 秒内把鼠标移到
--     世界中的目标上即可自动选中，无需同时点击按钮。
--   - 左列显示组件列表（紧凑），右列显示选中组件的成员详情。
--   - 组件分页、成员分页，防止复杂实体一屏放不下。
-- =============================================================================

local _ev_selected_entity = nil
local _ev_component_cache = {}
local _ev_expanded_component = nil
local _ev_editing_member = nil
local _ev_edit_value = ""
local _ev_selected_object_member = nil

-- 捕获模式状态
local _ev_capturing = false
local _ev_capture_end_frame = 0
local _ev_capture_tag = nil

-- 分页状态
local _ev_component_page = 1
local _ev_member_page = 1
local COMPONENT_PAGE_SIZE = 8
local MEMBER_PAGE_SIZE = 12

-- 安全读取帧号
local function get_frame_num()
  local ok, frame = pcall(GameGetFrameNum)
  if ok and frame then return tonumber(frame) or 0 end
  return 0
end

-- 选择鼠标位置的实体
local function select_entity_under_mouse(tag)
  local mx, my = DEBUG_GetMouseWorld()
  if not mx or not my then
    GamePrint("无法获取鼠标世界坐标")
    return
  end
  local eid = nil
  if tag and tag ~= "" then
    local ok, result = pcall(EntityGetClosestWithTag, mx, my, tag)
    if ok and result then eid = result end
  end
  if not eid then
    local ok, result = pcall(EntityGetClosest, mx, my)
    if ok and result then eid = result end
  end
  if eid and eid ~= 0 then
    _ev_selected_entity = eid
    _ev_component_cache = {}
    _ev_expanded_component = nil
    _ev_editing_member = nil
    _ev_selected_object_member = nil
    _ev_component_page = 1
    _ev_member_page = 1
    GamePrint("已选中实体: " .. tostring(eid))
  else
    GamePrint("鼠标位置未找到实体")
  end
end

-- 选择玩家实体
local function select_player()
  local player = get_player()
  if player then
    _ev_selected_entity = player
    _ev_component_cache = {}
    _ev_expanded_component = nil
    _ev_editing_member = nil
    _ev_selected_object_member = nil
    _ev_component_page = 1
    _ev_member_page = 1
    GamePrint("已选中玩家实体")
  end
end

-- 清除选中
local function clear_selection()
  _ev_selected_entity = nil
  _ev_component_cache = {}
  _ev_expanded_component = nil
  _ev_editing_member = nil
  _ev_selected_object_member = nil
  _ev_component_page = 1
  _ev_member_page = 1
end

-- 获取实体的所有组件信息
local function get_entity_components(eid)
  if _ev_component_cache[eid] then
    return _ev_component_cache[eid]
  end
  local comps = {}
  local ok, all_comps = pcall(EntityGetAllComponents, eid)
  if not ok or not all_comps then return comps end
  for _, comp in ipairs(all_comps or {}) do
    local ok2, type_name = pcall(ComponentGetTypeName, comp)
    if ok2 and type_name then
      table.insert(comps, {id = comp, type_name = type_name})
    end
  end
  _ev_component_cache[eid] = comps
  return comps
end

-- 获取组件成员
local function get_component_members(comp_id)
  local ok, members = pcall(ComponentGetMembers, comp_id)
  if not ok or not members then return {} end
  local result = {}
  for k, v in pairs(members) do
    if type(v) == "string" and #v > 0 then
      local ok2, val = pcall(ComponentGetValue2, comp_id, k)
      if ok2 then
        result[k] = tostring(val)
      else
        result[k] = "[err]"
      end
    else
      result[k] = tostring(v or "nil")
    end
  end
  return result
end

-- 设置组件成员值
local function set_component_member(comp_id, member, value_str)
  if not _ev_selected_entity then return end
  local val = tonumber(value_str) or value_str
  local ok, _ = pcall(ComponentSetValue2, comp_id, member, val)
  if ok then
    GamePrint("已设置: " .. member .. " = " .. tostring(val))
    _ev_component_cache = {}
  else
    GamePrint("设置失败: " .. member)
  end
end

-- =============================================================================
-- 渲染右侧成员详情
-- =============================================================================
local function render_component_details(comp_id, owner_entity)
  local ok_tn, type_name = pcall(ComponentGetTypeName, comp_id)
  local title = (ok_tn and type_name) or ("Component #" .. tostring(comp_id))
  GuiText(gui, 0, 0, "---- " .. title .. " ----")

  -- 启用/禁用
  GuiLayoutBeginHorizontal(gui, 0, 0)
  local ok_en, is_en = pcall(EntityGetComponentIsEnabled, owner_entity, comp_id)
  local en_text = (ok_en and is_en) and "[禁用组件]" or "[启用组件]"
  if GuiButton(gui, 0, 0, en_text, next_id()) then
    pcall(EntitySetComponentIsEnabled, owner_entity, comp_id, not is_en)
    _ev_component_cache = {}
  end
  if GuiButton(gui, 0, 0, "[全部折叠]", next_id()) then
    _ev_expanded_component = nil
    _ev_editing_member = nil
    _ev_member_page = 1
  end
  GuiLayoutEnd(gui)

  local members = get_component_members(comp_id)
  local sorted_keys = {}
  for k, _ in pairs(members) do table.insert(sorted_keys, k) end
  table.sort(sorted_keys)

  -- 成员分页
  local mem_total_pages = math.max(1, math.ceil(#sorted_keys / MEMBER_PAGE_SIZE))
  if _ev_member_page > mem_total_pages then _ev_member_page = mem_total_pages end
  if _ev_member_page < 1 then _ev_member_page = 1 end
  local mem_start = (_ev_member_page - 1) * MEMBER_PAGE_SIZE + 1
  local mem_end = math.min(mem_start + MEMBER_PAGE_SIZE - 1, #sorted_keys)

  for m_idx = mem_start, mem_end do
    local key = sorted_keys[m_idx]
    local value_str = members[key] or "nil"
    local edit_key = comp_id .. "." .. key
    local is_editing = (_ev_editing_member == edit_key)

    local display_value = value_str
    if #display_value > 40 then
      display_value = display_value:sub(1, 37) .. "..."
    end

    if is_editing then
      GuiLayoutBeginHorizontal(gui, 0, 0)
      GuiText(gui, 0, 0, key .. " = ")
      if GuiButton(gui, 0, 0, _ev_edit_value .. "_", next_id()) then
        set_component_member(comp_id, key, _ev_edit_value)
        _ev_editing_member = nil
        _ev_edit_value = ""
      end
      if GuiButton(gui, 0, 0, "[OK]", next_id()) then
        set_component_member(comp_id, key, _ev_edit_value)
        _ev_editing_member = nil
        _ev_edit_value = ""
      end
      GuiLayoutEnd(gui)

      local edit_target = {
        value = _ev_edit_value,
        on_change = function(self)
          _ev_edit_value = self.value
        end
      }
      set_type_target(edit_target)
    else
      GuiLayoutBeginHorizontal(gui, 0, 0)
      if GuiButton(gui, 0, 0, key .. " = " .. display_value, next_id()) then
        _ev_editing_member = edit_key
        _ev_edit_value = value_str
      end
      GuiLayoutEnd(gui)
    end
  end

  if #sorted_keys == 0 then
    GuiText(gui, 0, 0, "(无成员)")
  end

  -- 成员分页控制
  if mem_total_pages > 1 then
    GuiLayoutBeginHorizontal(gui, 0, 0)
    if _ev_member_page > 1 then
      if GuiButton(gui, 0, 0, "< 成员", next_id()) then
        _ev_member_page = _ev_member_page - 1
      end
    end
    GuiText(gui, 0, 0, " " .. _ev_member_page .. "/" .. mem_total_pages .. " ")
    if _ev_member_page < mem_total_pages then
      if GuiButton(gui, 0, 0, "成员 >", next_id()) then
        _ev_member_page = _ev_member_page + 1
      end
    end
    GuiLayoutEnd(gui)
  end
end

-- =============================================================================
-- UI 面板
-- =============================================================================

entity_viewer_panel = Panel{function() return T("panel_entity_viewer") end, function()
  breadcrumbs(1, 0)

  -- 捕获模式实时检查
  if _ev_capturing then
    local now = get_frame_num()
    if now >= _ev_capture_end_frame then
      _ev_capturing = false
      _ev_capture_tag = nil
      GamePrint("捕获模式结束")
    else
      select_entity_under_mouse(_ev_capture_tag)
      if _ev_selected_entity then
        _ev_capturing = false
        _ev_capture_tag = nil
      end
    end
  end

  -- ===================== 左列 (x=1) =====================
  GuiLayoutBeginVertical(gui, 1, 11)

  -- 选择工具
  GuiLayoutBeginHorizontal(gui, 0, 0)
  local capture_label = _ev_capturing
    and "[捕获中... " .. math.max(0, math.ceil((_ev_capture_end_frame - get_frame_num()) / 60)) .. "s]"
    or "[捕获鼠标指向实体]"
  if GuiButton(gui, 0, 0, capture_label, next_id()) then
    _ev_capturing = true
    _ev_capture_tag = nil
    _ev_capture_end_frame = get_frame_num() + 180  -- 3 秒
    GamePrint("捕获模式：请在 3 秒内将鼠标指向目标实体")
  end
  if GuiButton(gui, 0, 0, "[选中玩家]", next_id()) then
    select_player()
  end
  if _ev_selected_entity and GuiButton(gui, 0, 0, "[清除选中]", next_id()) then
    clear_selection()
  end
  GuiLayoutEnd(gui)

  -- 标签过滤
  GuiLayoutBeginHorizontal(gui, 0, 0)
  GuiText(gui, 0, 0, "tag:")
  if GuiButton(gui, 0, 0, "enemy", next_id()) then
    _ev_capturing = true; _ev_capture_tag = "enemy"; _ev_capture_end_frame = get_frame_num() + 180
    GamePrint("捕获模式 [enemy]：3 秒内指向敌人")
  end
  if GuiButton(gui, 0, 0, "item", next_id()) then
    _ev_capturing = true; _ev_capture_tag = "item"; _ev_capture_end_frame = get_frame_num() + 180
    GamePrint("捕获模式 [item]：3 秒内指向物品")
  end
  if GuiButton(gui, 0, 0, "hittable", next_id()) then
    _ev_capturing = true; _ev_capture_tag = "hittable"; _ev_capture_end_frame = get_frame_num() + 180
    GamePrint("捕获模式 [hittable]：3 秒内指向可命中目标")
  end
  if GuiButton(gui, 0, 0, "projectile", next_id()) then
    _ev_capturing = true; _ev_capture_tag = "projectile"; _ev_capture_end_frame = get_frame_num() + 180
    GamePrint("捕获模式 [projectile]：3 秒内指向投射物")
  end
  GuiLayoutEnd(gui)

  if _ev_capturing then
    GuiText(gui, 0, 0, "提示：移动鼠标到世界中的目标上即可自动选中")
  end

  if not _ev_selected_entity then
    GuiText(gui, 0, 0, " ")
    GuiText(gui, 0, 0, "提示: 点击 [捕获鼠标指向实体] 后将鼠标移到目标上")
    GuiText(gui, 0, 0, "或使用 tag 过滤来限定捕获类型")
    GuiLayoutEnd(gui)
    return
  end

  -- 选中实体信息
  local ok_alive, is_alive = pcall(EntityGetIsAlive, _ev_selected_entity)
  local alive_str = (ok_alive and is_alive) and "[存活]" or "[已死亡/无效]"
  GuiText(gui, 0, 0, "实体 ID: " .. tostring(_ev_selected_entity) .. " " .. alive_str)

  local ok_name, e_name = pcall(EntityGetName, _ev_selected_entity)
  if ok_name and e_name then
    GuiText(gui, 0, 0, "名称: " .. tostring(e_name))
  end

  local ok_tf, tx, ty = pcall(EntityGetTransform, _ev_selected_entity)
  if ok_tf and tx and ty then
    GuiText(gui, 0, 0, "坐标: (" .. math.floor(tx) .. ", " .. math.floor(ty) .. ")")
  end

  GuiText(gui, 0, 0, " ")
  GuiText(gui, 0, 0, "---- 组件列表 ----")

  -- 列出所有组件（分页）
  local comps = get_entity_components(_ev_selected_entity)
  if #comps == 0 then
    GuiText(gui, 0, 0, "(无组件或无法读取)")
  else
    local comp_total_pages = math.max(1, math.ceil(#comps / COMPONENT_PAGE_SIZE))
    if _ev_component_page > comp_total_pages then _ev_component_page = comp_total_pages end
    if _ev_component_page < 1 then _ev_component_page = 1 end

    local comp_start = (_ev_component_page - 1) * COMPONENT_PAGE_SIZE + 1
    local comp_end = math.min(comp_start + COMPONENT_PAGE_SIZE - 1, #comps)

    for idx = comp_start, comp_end do
      local comp = comps[idx]
      local is_expanded = (_ev_expanded_component == comp.id)
      local prefix = is_expanded and "[-] " or "[+] "
      if GuiButton(gui, 0, 0, prefix .. comp.type_name, next_id()) then
        if is_expanded then
          _ev_expanded_component = nil
          _ev_editing_member = nil
          _ev_member_page = 1
        else
          _ev_expanded_component = comp.id
          _ev_editing_member = nil
          _ev_member_page = 1
        end
      end
    end

    -- 组件分页控制
    if comp_total_pages > 1 then
      GuiLayoutBeginHorizontal(gui, 0, 0)
      if _ev_component_page > 1 then
        if GuiButton(gui, 0, 0, "< 组件", next_id()) then
          _ev_component_page = _ev_component_page - 1
        end
      end
      GuiText(gui, 0, 0, " " .. _ev_component_page .. "/" .. comp_total_pages .. " ")
      if _ev_component_page < comp_total_pages then
        if GuiButton(gui, 0, 0, "组件 >", next_id()) then
          _ev_component_page = _ev_component_page + 1
        end
      end
      GuiLayoutEnd(gui)
    end
  end

  GuiLayoutEnd(gui)  -- 左列结束

  -- ===================== 右列 (x=280, 绝对像素) =====================
  if _ev_expanded_component then
    GuiLayoutBeginVertical(gui, 280, 11, true)
    render_component_details(_ev_expanded_component, _ev_selected_entity)
    GuiLayoutEnd(gui)
  end
end}
