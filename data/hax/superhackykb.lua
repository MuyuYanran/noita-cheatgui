-- =============================================================================
-- superhackykb.lua - 键盘输入支持模块
-- =============================================================================
-- 通过 LuaJIT FFI 直接调用 SDL2.dll 获取键盘状态，实现游戏内文本输入过滤功能。
-- 仅在拥有 FFI 支持（即请求了无 API 限制权限）时可用。
-- 扫描码 0-283 对应 SDL2 的标准键盘布局。
-- =============================================================================

print("Loading hacky KB?")

-- 防止重复加载
if _hacky_keyboard_defined then
  return
end
_hacky_keyboard_defined = true

-- 默认的 hack_type（无键盘时返回空字符串）
hack_type = function()
  return ""
end

-- 检查是否支持 FFI（需要 request_no_api_restrictions 权限）
if not require then
  print("No require? Urgh.")
  return
end

local ffi = require('ffi')
if not ffi then
  print("No FFI? Well that's a pain.")
  return
end

_keyboard_present = true  -- 标记键盘可用

-- 声明 SDL2 键盘 API
ffi.cdef([[
  const uint8_t* SDL_GetKeyboardState(int* numkeys);
  uint32_t SDL_GetKeyFromScancode(uint32_t scancode);
  char* SDL_GetScancodeName(uint32_t scancode);
  char* SDL_GetKeyName(uint32_t key);
]])
_SDL = ffi.load('SDL2.dll')

-- 扫描码 → 按键名称映射表
local code_to_a = {}
-- Shift 键的扫描码列表（用于检测 Shift 是否被按下）
local shifts = {}

-- 初始化键盘映射：遍历所有可能的扫描码（SDL2 最大 284）
for i = 0, 284 do
  local keycode = _SDL.SDL_GetKeyFromScancode(i)
  if keycode > 0 then
    local keyname = ffi.string(_SDL.SDL_GetKeyName(keycode))
    if keyname and #keyname > 0 then
      code_to_a[i] = keyname:lower()
      if keyname:lower():find("shift") then
        table.insert(shifts, i)
      end
    end
  end
end

-- 上一帧的按键状态（用于检测按键"按下"事件而非"按住"状态）
local prev_state = {}
for i = 0, 284 do
  prev_state[i] = 0
end

-- 更新键盘状态，返回新按下的按键列表和 Shift 是否被按住
function hack_update_keys()
  local keys = _SDL.SDL_GetKeyboardState(nil)
  local pressed = {}
  -- 从扫描码 1 开始，跳过 "UNKNOWN"
  for scancode = 1, 284 do 
    -- 按键状态 > 0 表示按下，prev_state <= 0 表示之前没按（检测新按下事件）
    if keys[scancode] > 0 and prev_state[scancode] <= 0 then
      pressed[#pressed+1] = code_to_a[scancode]
    end
    prev_state[scancode] = keys[scancode]
  end
  -- 检测 Shift 是否被按住
  local shift_held = false
  for _, shiftcode in ipairs(shifts) do
    if keys[shiftcode] > 0 then
      shift_held = true
      break
    end
  end
  return pressed, shift_held
end

-- 特殊按键替换映射（如 space → 空格字符）
local REPLACEMENTS = {
  space = " "
}

-- 处理键盘输入：根据新按下的键修改输入字符串
-- @param current_str  当前的输入字符串
-- @param no_shift      是否需要按 Shift 才接受输入
-- @return 更新后的字符串, 是否按下了回车
hack_type = function(current_str, no_shift)
  local pressed, shift_held = hack_update_keys()
  local hit_enter = false
  for _, key in ipairs(pressed) do
    if (no_shift or shift_held) and REPLACEMENTS[key] then
      current_str = current_str .. REPLACEMENTS[key]  -- 替换键（如空格）
    elseif (no_shift or shift_held) and (#key == 1) then
      current_str = current_str .. key  -- 单字符键
    elseif key == "backspace" then
      current_str = current_str:sub(1,-2)  -- 退格删除
    elseif key == "enter" or key == "return" then
      hit_enter = true  -- 回车确认
    end
  end
  return current_str, hit_enter
end

print("Hacky KB loaded?")