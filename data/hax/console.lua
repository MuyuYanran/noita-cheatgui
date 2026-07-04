-- =============================================================================
-- console.lua - Web 远程控制台模块 (v2.0)
-- =============================================================================
-- 提供 WebSocket 服务器 + HTTP 静态文件服务器，允许通过浏览器连接
-- 到 Noita 并执行 Lua 代码，获得类似开发者控制台的交互体验。
-- 
-- 架构：
--   WebSocket 服务器 → 端口 9777（接收和执行 Lua 代码）
--   HTTP 服务器      → 端口 8777（提供 Web 前端页面）
--   Token 认证        → 确保仅 localhost 可连接
-- 
-- 新增 v2.0:
--   - pcall 包裹 _socket_update 防止轮询异常崩服
--   - get_server_info() 返回结构化状态信息（端口/Token/客户端/运行时长）
--   - 优雅断开：关闭客户端时发送 "SYS> Connection closed by server"
--   - 客户端连接/断开时 GamePrint 通知
--   - console_env 新增: clear(), uptime(), whoami(), list_players()
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
    local ok, result = pcall(loadfile, fn)
    if not ok then
      error("loadfile failed for " .. fn .. ": " .. tostring(result))
    end
    -- Noita 的 loadfile 可能把错误信息作为函数返回（已知 bug）
    if type(result) == "string" then
      error(fn .. ": " .. result)
    end
    if type(result) ~= "function" then
      error(fn .. ": loadfile returned unexpected type: " .. type(result))
    end
    setfenv(result, console_env)
    return result()
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

  -- clear: 清屏（发送 50 行空行）
  function console_env.clear()
    for _ = 1, 50 do
      console_env.send("")
    end
    return UNPRINTABLE_RESULT
  end

  -- uptime: 显示服务器运行时长和连接信息
  function console_env.uptime()
    local info = get_server_info and get_server_info() or {}
    if not info.running then
      console_env.print("Server not running.")
      return UNPRINTABLE_RESULT
    end
    local s = info.uptime_seconds or 0
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    local sec = s % 60
    console_env.print(("Uptime: %02d:%02d:%02d"):format(h, m, sec))
    console_env.print(("Clients: %d authorized, %d unauth (total connections: %d)")
      :format(info.clients_authorized or 0, info.clients_unauth or 0, info.total_connections or 0))
    console_env.print(("Ports: WS=9777, HTTP=%s"):format(info.http_running and "8777" or "OFF"))
    return UNPRINTABLE_RESULT
  end

  -- whoami: 显示当前客户端身份信息
  function console_env.whoami()
    console_env.print("Address: " .. (client.addr or "unknown"))
    console_env.print("Authorized: " .. tostring(client.authorized))
    console_env.print("Messages in: " .. (client.stat_in or 0))
    console_env.print("Messages out: " .. (client.stat_out or 0))
    local connected = os.time() - (client.connect_time or os.time())
    console_env.print("Connected for: " .. connected .. " seconds")
    return UNPRINTABLE_RESULT
  end

  -- list_players: 列出当前游戏中的玩家实体
  function console_env.list_players()
    local players = EntityGetWithTag("player_unit")
    if not players or #players == 0 then
      console_env.print("No player entities found.")
      return UNPRINTABLE_RESULT
    end
    console_env.print("Player entities: " .. #players)
    for i, p in ipairs(players) do
      local x, y = EntityGetTransform(p)
      local hp = nil
      local dm = EntityGetFirstComponentIncludingDisabled(p, "DamageModelComponent")
      if dm then
        local ok, val = pcall(ComponentGetValue2, dm, "hp")
        if ok then hp = val end
      end
      console_env.print(("%d: id=%d pos=(%d,%d) hp=%s"):format(i, p, x or 0, y or 0, tostring(hp or "?")))
    end
    return UNPRINTABLE_RESULT
  end

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
local server_start_time = nil  -- 服务器启动时间（用于 uptime 计算）
local total_conn_count = 0     -- 累计连接数
local STAT_AUTH_EXPIRATION = 6*3600  -- Token 过期时间: 6 小时

-- Token 文件路径（相对于 Noita 工作目录）
local TOKEN_FN = "mods/cheatgui/token.json"

-- 读取文件的辅助函数
local function read_raw_file(filename)
  local ok, f = pcall(io.open, filename)
  if not ok or not f then return nil end
  local res = f:read("*a")
  f:close()
  return res
end

-- 写入文件的辅助函数（安全版，不会因权限/磁盘问题崩溃）
local function write_raw_file(filename, data)
  local ok, f = pcall(io.open, filename, "w")
  if not ok or not f then
    print("CheatGUI: Cannot write " .. filename .. ": " .. tostring(f))
    return
  end
  f:write(data)
  f:close()
end

-- =============================================================================
-- Token 管理
-- =============================================================================

local auth_token = nil
local function generate_token()
  print("CheatGUI webconsole: generating new token.")
  auth_token = lib_pollnet.nanoid()
  write_raw_file(TOKEN_FN, JSON:encode_pretty{
    token = auth_token,
    expiration = os.time() + STAT_AUTH_EXPIRATION
  })
  return auth_token
end

-- 获取当前有效 Token（过期则重新生成）
local function get_token()
  if not auth_token then
    if not JSON then dofile_once("data/hax/lib/json.lua") end
    local tdata = read_raw_file(TOKEN_FN)
    if tdata then 
      local ok, decoded = pcall(JSON.decode, JSON, tdata)
      if ok and decoded then tdata = decoded else tdata = nil end
      if tdata then
        print("Got existing token: " .. tdata.token .. " (expires: " .. tdata.expiration .. ")")
      end
    end
    if tdata and tdata.token and tdata.expiration and (tdata.expiration > os.time()) then
      auth_token = tdata.token  -- Token 仍有效
    else
      if tdata then
        print("Token expired or invalid: " .. tostring(tdata.expiration) .. " vs " .. os.time())
      else 
        print("No token; generating new.")
      end
      auth_token = generate_token()
    end
  end
  return auth_token
end

-- 公开：获取当前 token（供 cheatgui.lua 面板显示）
function get_console_token()
  if not ws_server_socket then return nil end
  return get_token()
end

-- =============================================================================
-- 客户端生命周期管理
-- =============================================================================

-- 优雅关闭客户端（发送告别消息后断开）
local function graceful_close_client(client, reason)
  reason = reason or "Connection closed by server"
  if client.sock then
    local ok = pcall(client.sock.send, client.sock, "SYS> " .. reason)
    if not ok then print("CheatGUI: failed to send disconnect notice") end
    client.sock:close()
    client.sock = nil
  end
  ws_clients[client.addr] = nil
end

-- 关闭客户端（旧接口兼容）
local function close_client(client)
  graceful_close_client(client)
end

-- 向客户端发送消息
local function client_send(client, msg)
  if client.sock then
    client.stat_out = (client.stat_out or 0) + 1
    local ok = pcall(client.sock.send, client.sock, msg)
    if not ok then
      graceful_close_client(client, "Send error")
    end
  else
    graceful_close_client(client, "Socket already closed")
  end
end

-- 新客户端连接回调
local function on_new_client(sock, addr)
  print("CheatGUI: New console client: " .. addr)
  -- 如果已有同地址连接，先踢掉旧连接
  if ws_clients[addr] and ws_clients[addr].sock then
    ws_clients[addr].sock:close()
  end
  local new_client = {
    addr = addr, sock = sock,
    authorized = false,
    close = close_client,
    send = client_send,
    stat_in = 0, stat_out = 0,
    connect_time = os.time(),
  }
  new_client.console_env = make_console_env(new_client)
  ws_clients[addr] = new_client
  total_conn_count = total_conn_count + 1
end

-- =============================================================================
-- 服务器生命周期
-- =============================================================================

-- 启动控制台监听：打开 WebSocket 服务器和 HTTP 服务器
function listen_console_connections()
  lib_pollnet.link()
  if not ws_server_socket then
    local ok, err = pcall(lib_pollnet.listen_ws, "127.0.0.1:9777", SCRATCH_SIZE)
    if not ok or not err then
      GamePrint("CheatGUI: Failed to start WS server: " .. tostring(err))
      return nil
    end
    ws_server_socket = err
    ws_server_socket:on_connection(on_new_client)
    -- HTTP 服务器也带上 pcall
    local ok2, hserv = pcall(lib_pollnet.serve_http, "127.0.0.1:8777", "mods/cheatgui/www")
    if ok2 then
      http_server = hserv
    else
      print("CheatGUI: HTTP server failed: " .. tostring(hserv))
      -- HTTP 失败不影响 WS（虽然前端无法加载，但可手动打开文件）
    end
    server_start_time = os.time()
    GamePrint("Console server started: ws://127.0.0.1:9777, http://127.0.0.1:8777")
  end
  return get_token()
end

-- 获取所有活跃连接
function get_console_connections()
  return ws_clients
end

-- 获取服务器信息（供 cheatgui 面板显示）
function get_server_info()
  if not ws_server_socket then
    return { running = false }
  end
  local authorized_count = 0
  local unauth_count = 0
  for _, c in pairs(ws_clients) do
    if c.authorized then authorized_count = authorized_count + 1
    elseif c.sock then unauth_count = unauth_count + 1 end
  end
  return {
    running = true,
    ws_port = 9777,
    http_port = 8777,
    token = get_token(),
    clients_total = authorized_count + unauth_count,
    clients_authorized = authorized_count,
    clients_unauth = unauth_count,
    total_connections = total_conn_count,
    uptime_seconds = os.time() - (server_start_time or os.time()),
    http_running = (http_server ~= nil),
  }
end

-- 关闭所有控制台连接和服务器
function close_console_connections()
  print("CheatGUI: Shutting down console server...")
  -- 通知所有客户端服务器即将关闭
  for _, client in pairs(ws_clients) do
    if client.sock then
      local ok = pcall(client.sock.send, client.sock, "SYS> Server shutting down. Goodbye!")
      if ok then client.sock:close() end
    end
  end
  ws_clients = {}
  if ws_server_socket then
    pcall(ws_server_socket.close, ws_server_socket)
    ws_server_socket = nil
  end
  if http_server then
    pcall(http_server.close, http_server)
    http_server = nil
  end
  server_start_time = nil
  GamePrint("Console server stopped.")
end

-- 向所有控制台广播消息
function send_all_consoles(msg)
  for _, client in pairs(ws_clients) do
    if client.sock and client.authorized then
      client:send("SYS> " .. msg)
    end
  end
end

-- =============================================================================
-- 客户端认证与消息处理
-- =============================================================================

-- 客户端认证检查：仅允许 localhost + 有效 Token
local function check_authorization(client, msg)
  if not is_localhost(client.addr) then
    client.sock:send("SYS> UNAUTHORIZED: NOT LOCALHOST! Only localhost connections allowed.")
    client.sock:close()
    client.sock = nil
    print("CheatGUI: Rejected non-localhost connection from " .. client.addr)
    return
  end

  if msg:find(get_token()) then
    client.authorized = true
    client.sock:send("SYS> AUTHORIZED -- Welcome to Noita Console!")
    client.sock:send("SYS> Type 'help(\"function_name?\")' or just 'function_name?' with trailing ? for API docs.")
    client.sock:send("SYS> Built-in commands: help(fn), clear(), uptime(), print_table(t), reload_utils(), whoami(), list_players()")
    GamePrint("Console client connected: " .. client.addr)
  else
    client.sock:send("SYS> UNAUTHORIZED: INVALID TOKEN. Check the token displayed in the CheatGUI console panel.")
    client.sock:close()
    client.sock = nil
    print("CheatGUI: Rejected client with invalid token: " .. client.addr)
  end
end

-- 处理客户端消息：编译并执行 Lua 代码，返回结果
local function _handle_client_message(client, msg)
  if not client.authorized then
    return check_authorization(client, msg)
  end

  if not msg or msg == "" then return end

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
  setfenv(f, client.console_env)
  local happy, retval = _collect(pcall(f))
  if happy then
    if retval ~= UNPRINTABLE_RESULT then
      client:send("RES> " .. tostring(retval))
    end
  else
    client:send("ERR> " .. tostring(retval))
  end
end

-- =============================================================================
-- 轮询更新（每帧由 cheatgui.lua 调用）
-- =============================================================================

local count = 0
-- 记录：用于检测是否已发送过错误通知
local _last_ws_error = nil

function _socket_update()
  if not ws_server_socket then return end

  -- 轮询 WebSocket 服务器（pcall 包裹，防止意外异常崩服）
  local happy, msg = pcall(ws_server_socket.poll, ws_server_socket)
  if not happy then
    local err_msg = tostring(msg)
    if _last_ws_error ~= err_msg then
      print("CheatGUI: WS server poll error: " .. err_msg)
      _last_ws_error = err_msg
    end
    return -- 单次错误不改动服务器状态，下次帧再试
  end
  if msg == false then
    -- WS socket 正常关闭（poll 返回 false）
    print("CheatGUI: WS server socket closed.")
    close_console_connections()
    return
  end
  _last_ws_error = nil -- 恢复正常

  -- 轮询所有客户端
  for addr, client in pairs(ws_clients) do
    if client.sock then
      local happy, msg = pcall(client.sock.poll, client.sock)
      if not happy then
        -- 客户端断连
        print("CheatGUI: Client disconnected (" .. addr .. "): " .. tostring(msg))
        client.sock:close()
        client.sock = nil
        ws_clients[addr] = nil
        if client.authorized then
          GamePrint("Console client disconnected: " .. addr)
        end
      elseif msg then
        _handle_client_message(client, msg)
      end
    else
      ws_clients[addr] = nil
    end
  end

  -- HTTP 服务器每 60 帧轮询一次（降低开销）
  if (count % 60 == 0) and http_server then
    local happy, errmsg = pcall(http_server.poll, http_server)
    if not happy then
      print("CheatGUI: HTTP server error: " .. tostring(errmsg))
      pcall(http_server.close, http_server)
      http_server = nil
    end
  end

  count = count + 1
end