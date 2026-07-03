-- =============================================================================
-- console.lua - Web 远程控制台模块
-- =============================================================================
-- 提供 WebSocket 服务器 + HTTP 静态文件服务器，允许通过浏览器连接
-- 到 Noita 并执行 Lua 代码，获得类似开发者控制台的交互体验。
-- 
-- 架构：
--   WebSocket 服务器 → 端口 9777（接收和执行 Lua 代码）
--   HTTP 服务器      → 端口 8777（提供 Web 前端页面）
--   Token 认证        → 确保仅 localhost 可连接
-- 
-- 依赖：pollnet.dll + lib/pollnet.lua + lib/json.lua
-- =============================================================================

dofile_once("data/hax/lib/pollnet.lua")
dofile_once("data/scripts/lib/coroutines.lua")

-- 这个空表作为特殊标记，抑制打印"RES>"类型的空返回值
-- （正常情况下，"[no value]"也会被打印出来）
local UNPRINTABLE_RESULT = {}

-- 字符串分割函数（来自 http://lua-users.org/wiki/SplitJoin）
local strfind = string.find
local tinsert = table.insert
local strsub = string.sub
local function strsplit(text, delimiter)
  local list = {}
  local pos = 1
  if strfind("", delimiter, 1) then -- 分隔符匹配空字符串会导致无限循环
    error("Delimiter matches empty string!")
  end
  while 1 do
    local first, last = strfind(text, delimiter, pos)
    if first then -- 找到了分隔符
      tinsert(list, strsub(text, pos, first-1))
      pos = last+1
    else
      tinsert(list, strsub(text, pos))  -- 最后一段
      break
    end
  end
  return list
end

-- 检查连接是否来自 localhost（安全限制）
local function is_localhost(addr)
  local parts = strsplit(addr, ":")
  return parts[1] == "127.0.0.1"
end

-- 重新加载 utils.lua 到控制台环境（使控制台可调用工具函数）
local function reload_utils(console_env)
  local env_utils, err = loadfile("data/hax/utils.lua")
  if type(env_utils) ~= "function" then
    console_env.print("Error loading utils: " .. tostring(err))
    return
  end
  setfenv(env_utils, console_env)
  local happy, err = pcall(env_utils)
  if not happy then
    console_env.print("Error executing utils: " .. tostring(err))
  end
  console_env.print("Utils loaded.")
end

-- 加载 API 帮助文档（支持 help() 命令查询函数说明）
local _help_info = nil
local function reload_help(fn)
  fn = fn or "tools_modding/lua_api_documentation.txt"
  local f, err = io.open(fn)
  if not f then error("Couldn't open " .. fn) end
  local res = f:read("*a")
  f:close()
  if not res then error("Couldn't read " .. fn) end
  _help_info = {}
  res = res:gsub("\r", "") -- 去除 Windows 回车符
  local lines = strsplit(res, "\n")
  for _, line in ipairs(lines) do
    local paren_idx = line:find("%(")
    if paren_idx then
      local funcname = line:sub(1, paren_idx-1)
      _help_info[funcname] = line
    end
  end
end

-- 获取指定函数的文档字符串
local function help_str(funcname)
  if not _help_info then reload_help() end
  return _help_info[funcname]
end

-- 将任意值转换为可打印的字符串表示
local function _strinfo(v)
  if v == nil then return "nil" end
  local vtype = type(v)
  if vtype == "number" then
    return ("%0.4f"):format(v)
  elseif vtype == "string" then
    return '"' .. v .. '"'
  elseif vtype == "boolean" then
    return tostring(v)
  else
    return ("[%s] %s"):format(vtype, tostring(v))
  end
end

-- 格式化多个参数为字符串（用于返回值显示）
local function strinfo(...)
  local frags = {}
  local nargs = select('#', ...)
  if nargs == 0 then
    return "[no value]"
  end
  if nargs == 1 and select(1, ...) == UNPRINTABLE_RESULT then
    return UNPRINTABLE_RESULT
  end
  for idx = 1, nargs do
    frags[idx] = _strinfo(select(idx, ...))
  end
  return table.concat(frags, ", ")
end

-- 创建 Tab 补全函数：根据输入的前缀在控制台环境中匹配可用函数/变量
local function make_complete(console_env)
  return function(s)
    local opts = {}

    local parts = strsplit(s, "%.") -- "." 是模式匹配特殊字符，需要转义
    local cur = console_env
    local prefix = ""
    -- 逐级解析点号分隔的路径
    for idx = 1, (#parts) - 1 do
      cur = cur[parts[idx]]
      if not cur then return UNPRINTABLE_RESULT end
      prefix = prefix .. parts[idx] .. "."
    end
    if type(cur) ~= "table" then return UNPRINTABLE_RESULT end
    local lastpart = parts[#parts]
    if not lastpart then return UNPRINTABLE_RESULT end
    -- 匹配以用户输入为前缀的键
    for k, _ in pairs(cur) do
      if k:find(lastpart) == 1 then
        table.insert(opts, k)
      end
    end
    if #opts > 0 then
      table.sort(opts)
      console_env.send("COM>" .. prefix .. " " .. table.concat(opts, ","))
    end
    return UNPRINTABLE_RESULT
  end
end

-- 创建每个客户端独立的控制台执行环境
-- 包含安全的 print/err_print/send 重写，以及工具函数注入
local function make_console_env(client)
  local console_env = {}
  -- 注入 getfenv() 中的所有内容（游戏 API 函数等）
  for k, v in pairs(getfenv()) do
    console_env[k] = v
  end
  -- 注入 cheatgui_stash 中的内容（如 ModTextFileGetContent 等）
  for k, v in pairs(cheatgui_stash) do
    if not console_env[k] then console_env[k] = v end
  end

  -- 重写 print：输出到客户端
  function console_env.print(...)
    local msg = table.concat({...}, " ")
    client:send("GAME> " .. msg)
    return UNPRINTABLE_RESULT
  end

  -- 错误打印
  function console_env.err_print(...)
    local msg = table.concat({...}, " ")
    client:send("ERR> " .. msg)
    return UNPRINTABLE_RESULT
  end

  -- 通用发送函数
  function console_env.send(msg)
    client:send(msg)
  end

  -- 打印表的键和值类型概览
  function console_env.print_table(t)
    local s = {}
    for k, v in pairs(t) do
      table.insert(s, k .. ": " .. type(v))
    end
    console_env.print(table.concat(s, "\n"))
  end

  -- 服务器端日志（不发给客户端）
  function console_env.log(...)
    local msg = table.concat({...}, " ")
    print(client.addr .. ": " .. msg)
  end

  -- info 命令：格式化打印参数的值
  function console_env.info(...)
    console_env.print(strinfo(...))
    return UNPRINTABLE_RESULT
  end

  -- 重写 dofile：在当前控制台环境中执行文件
  function console_env.dofile(fn)
    local s = loadfile(fn)
    if type(s) == 'string' then
      -- Noita 的 loadfile 有 bug：错误信息作为第一个返回值而非第二个
      error(fn .. ": " .. s)
    end
    setfenv(s, console_env)
    return s()
  end

  -- help 命令：查询 API 函数文档
  function console_env.help(funcname)
    console_env.send("HELP> " .. (help_str(funcname) or (funcname .. "-> [no help available]")))
    return UNPRINTABLE_RESULT
  end

  -- 注入常用工具
  console_env.complete = make_complete(console_env)  -- Tab 补全
  console_env.strinfo = strinfo
  console_env.help_str = help_str
  console_env.UNPRINTABLE_RESULT = UNPRINTABLE_RESULT
  
  reload_utils(console_env)  -- 加载工具函数

  return console_env
end

-- pcall 包装：成功时格式化返回值，失败时原样返回错误信息
local function _collect(happy, ...)
  if happy then
    return happy, strinfo(...)
  else
    return happy, ...
  end
end

-- =============================================================================
-- WebSocket / HTTP 服务器管理
-- =============================================================================

local SCRATCH_SIZE = 1000000 -- 接收缓冲区大小（1MB）
local ws_server_socket = nil   -- WebSocket 服务器 socket
local http_server = nil        -- HTTP 服务器
local ws_clients = {}          -- 活跃客户端表 (addr → client)

-- Token 文件路径和过期时间
local TOKEN_FN = "mods/cheatgui/token.json"
local TOKEN_EXPIRATION = 6*3600 -- 6 小时后过期

-- 读取文件的辅助函数
local function read_raw_file(filename)
  local f, err = io.open(filename)
  if not f then return nil end
  local res = f:read("*a")
  f:close()
  return res
end

-- 写入文件的辅助函数
local function write_raw_file(filename, data)
  local f, err = io.open(filename, "w")
  if not f then error("Couldn't write " .. filename .. ": " .. err) end
  f:write(data)
  f:close()
end

-- 认证 Token 管理
local auth_token = nil
local function generate_token()
  print("Cheatgui webconsole: generating new token.")
  auth_token = lib_pollnet.nanoid()
  write_raw_file(TOKEN_FN, JSON:encode_pretty{
    token = auth_token,
    expiration = os.time() + TOKEN_EXPIRATION
  })
  return auth_token
end

-- 获取当前有效 Token（过期则重新生成）
local function get_token()
  if not auth_token then
    if not JSON then dofile_once("data/hax/lib/json.lua") end
    local tdata = read_raw_file(TOKEN_FN)
    if tdata then 
      tdata = JSON:decode(tdata) 
      print("Got existing token: " .. tdata.token .. " -- " .. tdata.expiration)
    end
    if tdata and tdata.expiration and (tdata.expiration > os.time()) then
      auth_token = tdata.token  -- Token 仍有效
    else
      if tdata then
        print("Token expired? " .. tdata.expiration .. " vs. " .. os.time())
      else 
        print("No token; generating new.")
      end
      auth_token = generate_token()  -- 生成新 Token
    end
  end
  return auth_token
end

-- 关闭客户端连接
local function close_client(client)
  if client.sock then
    client.sock:close()
    client.sock = nil
  end
  ws_clients[client.addr] = nil
end

-- 向客户端发送消息
local function client_send(client, msg)
  if client.sock then
    client.stat_out = (client.stat_out or 0) + 1
    client.sock:send(msg)
  else
    client:close()
  end
end

-- 新客户端连接回调
local function on_new_client(sock, addr)
  print("New client: " .. addr)
  if ws_clients[addr] then ws_clients[addr].sock:close() end  -- 关闭旧连接
  local new_client = {
    addr = addr, sock = sock, 
    authorized = false,        -- 未认证
    close = close_client, 
    send = client_send, 
    stat_in=0, stat_out=0      -- 收发统计
  }
  new_client.console_env = make_console_env(new_client)
  ws_clients[addr] = new_client
end

-- 启动控制台监听：打开 WebSocket 服务器和 HTTP 服务器
function listen_console_connections()
  lib_pollnet.link()
  if not ws_server_socket then
    ws_server_socket = lib_pollnet.listen_ws("127.0.0.1:9777", SCRATCH_SIZE)
    ws_server_socket:on_connection(on_new_client)
    http_server = lib_pollnet.serve_http("127.0.0.1:8777", "mods/cheatgui/www")
  end
  return get_token()  -- 返回认证 Token
end

-- 获取所有活跃连接
function get_console_connections()
  return ws_clients
end

-- 关闭所有控制台连接和服务器
function close_console_connections()
  for _, sock in pairs(ws_clients) do sock:close() end
  ws_clients = {}
  if ws_server_socket then ws_server_socket:close() end
  ws_server_socket = nil
  if http_server then http_server:close() end
  http_server = nil
end

-- 向所有控制台广播消息
function send_all_consoles(msg)
  for _, sock in pairs(ws_clients) do
    sock:send("ERR>" .. msg)
  end
end

-- 客户端认证检查：仅允许 localhost + 有效 Token
local function check_authorization(client, msg)
  if not is_localhost(client.addr) then
    client.sock:send("SYS> UNAUTHORIZED: NOT LOCALHOST!")
    client.sock:close()
    client.sock = nil
    return
  end

  if msg:find(get_token()) then
    client.authorized = true
    client.sock:send("SYS> AUTHORIZED")
    GamePrint("Accepted console connection: " .. client.addr)
  else
    client.sock:send("SYS> UNAUTHORIZED: INVALID TOKEN")
    client.sock:close()
    client.sock = nil
  end
end

-- 处理客户端消息：编译并执行 Lua 代码，返回结果
local function _handle_client_message(client, msg)
  if not client.authorized then
    return check_authorization(client, msg)
  end

  client.stat_in = (client.stat_in or 0) + 1
  local f, err = nil, nil
  -- 单行代码：尝试前缀 "return " 以直接获取表达式值
  if not msg:find("\n") then
    f, err = loadstring("return " .. msg)
  end
  if not f then -- 多行代码或非表达式
    f, err = loadstring(msg)
    if not f then
      client:send("ERR> Parse error: " .. tostring(err))
      return
    end
  end
  setfenv(f, client.console_env)  -- 设置执行环境
  local happy, retval = _collect(pcall(f))
  if happy then
    if retval ~= UNPRINTABLE_RESULT then
      client:send("RES> " .. tostring(retval))
    end
  else
    client:send("ERR> " .. tostring(retval))
  end
end

-- 每帧调用：轮询服务器和客户端事件
local count = 0
function _socket_update()
  if not ws_server_socket then return end
  -- 轮询 WebSocket 服务器
  local happy, msg = ws_server_socket:poll()
  if not happy then
    print("Main WS server closed?")
    close_console_connections()
    return
  end

  -- 轮询所有客户端
  for addr, client in pairs(ws_clients) do
    if client.sock then
      local happy, msg = client.sock:poll()
      if not happy then
        print("Sock error: " .. tostring(msg))
        client.sock:close()
        client.sock = nil
        ws_clients[addr] = nil
      elseif msg then
        _handle_client_message(client, msg)  -- 处理收到的消息
      end
    else
      ws_clients[addr] = nil
    end
  end

  -- HTTP 服务器每 60 帧轮询一次（降低开销）
  if (count % 60 == 0) and http_server then
    local happy, errmsg = http_server:poll()
    if not happy then
      print("HTTP server closed: " .. tostring(errmsg))
      http_server:close()
      http_server = nil
    end
  end

  count = count + 1
end