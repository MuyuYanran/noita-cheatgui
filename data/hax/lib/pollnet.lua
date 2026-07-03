-- =============================================================================
-- pollnet.lua - pollnet.dll 的 LuaJIT FFI 绑定
-- =============================================================================
-- 轻量级网络库的 Lua 封装，提供 WebSocket 客户端/服务器和 HTTP 服务功能。
-- 依赖：pollnet.dll（需放在 mods/cheatgui/bin/ 目录下）
-- 
-- 主要功能：
--   - WebSocket 客户端连接（open_ws）
--   - WebSocket 服务器（listen_ws）
--   - 静态 HTTP 文件服务器（serve_http）
--   - NanoID 生成器（nanoid）
-- 
-- 示例：连接到 Twitch 聊天室（见下方注释）
-- =============================================================================

--[[ 
pollnet 的 LuaJIT 绑定 --- 旧版示例代码
local pollnet = require("pollnet")
local async = require("async") -- 假设你拥有某种异步库
async.run(function()
  local url = "wss://irc-ws.chat.twitch.tv:443"
  local sock = pollnet.open_ws(url)
  sock:send("PASS doesntmatter")
  -- Twitch 匿名只读访问的特殊昵称
  local anon_user_name = "justinfan" .. math.random(1, 100000)
  local target_channel = "your_channel_name_here"
  sock:send("NICK " .. anon_user_name)
  sock:send("JOIN #" .. target_channel)
  
  while sock:poll() do
    local msg = sock:last_message()
    if msg then
      if msg == "PING :tmi.twitch.tv" then
        sock:send("PONG :tmi.twitch.tv")
      end
      print(msg) 
    end
    async.await_frames(1)
  end
  print("Socket closed: ", sock:last_message())
end)
]]--

local ffi = require("ffi")
-- 声明 pollnet C 函数接口
ffi.cdef[[
struct pnctx* pollnet_init();
struct pnctx* pollnet_get_or_init_static();
void pollnet_shutdown(struct pnctx* ctx);
unsigned int pollnet_open_ws(struct pnctx* ctx, const char* url);
void pollnet_close(struct pnctx* ctx, unsigned int handle);
void pollnet_close_all(struct pnctx* ctx);
void pollnet_send(struct pnctx* ctx, unsigned int handle, const char* msg);
unsigned int pollnet_update(struct pnctx* ctx, unsigned int handle);
int pollnet_get(struct pnctx* ctx, unsigned int handle, char* dest, unsigned int dest_size);
int pollnet_get_error(struct pnctx* ctx, unsigned int handle, char* dest, unsigned int dest_size);
unsigned int pollnet_get_connected_client_handle(struct pnctx* ctx, unsigned int handle);
unsigned int pollnet_listen_ws(struct pnctx* ctx, const char* addr);
unsigned int pollnet_serve_static_http(struct pnctx* ctx, const char* addr, const char* serve_dir);
unsigned int pollnet_serve_http(struct pnctx* ctx, const char* addr);
void pollnet_add_virtual_file(struct pnctx* ctx, unsigned int handle, const char* filename, const char* filedata, unsigned int filesize);
void pollnet_remove_virtual_file(struct pnctx* ctx, unsigned int handle, const char* filename);
int pollnet_get_nanoid(char* dest, unsigned int dest_size);
]]

local POLLNET_RESULT_CODES = {
  [0] = "invalid_handle",
  [1] = "closed",
  [2] = "opening",
  [3] = "nodata",
  [4] = "hasdata",
  [5] = "error",
  [6] = "newclient"
}

-- pollnet.dll 路径（相对于 Noita 安装目录）
local LIB_PATH = "mods/cheatgui/bin/pollnet.dll"

local pollnet = nil
local _ctx = nil  -- pollnet 上下文指针

-- 加载 pollnet.dll 并链接 FFI
local function link_pollnet(return_error)
  if pollnet then return end
  local happy, res = pcall(ffi.load, LIB_PATH)
  local err_msg = "Pollnet DLL missing or corrupt: " .. LIB_PATH
  if happy then
    pollnet = res
  elseif return_error then
    return err_msg .. ": " .. res
  else
    error(err_msg .. ": " .. res)
  end
end

-- 初始化 pollnet 上下文
local function init_ctx()
  if _ctx then return end
  if not pollnet then link_pollnet() end
  _ctx = ffi.gc(pollnet.pollnet_init(), pollnet.pollnet_shutdown)  -- 自动 GC
  assert(_ctx ~= nil)
end

-- 备用初始化：使用静态上下文（用于某些特殊情况）
local function init_ctx_hack_static()
  if _ctx then return end
  _ctx = pollnet.pollnet_get_or_init_static()
  assert(_ctx ~= nil)
  pollnet.pollnet_close_all(_ctx)
end

-- 关闭 pollnet 上下文
local function shutdown_ctx()
  if not _ctx then return end
  pollnet.pollnet_shutdown(ffi.gc(_ctx, nil))
  _ctx = nil
end

-- Socket 元表和方法
local socket_mt = {}
local function Socket()
  return setmetatable({}, {__index = socket_mt})
end

-- 内部方法：打开连接
function socket_mt:_open(scratch_size, opener, ...)
  init_ctx()
  if not _ctx then return end
  if self._socket then self:close() end
  if not scratch_size then scratch_size = 64000 end
  if type(opener) == "number" then
    self._socket = opener
  else
    self._socket = opener(_ctx, ...)
  end
  self._scratch = ffi.new("int8_t[?]", scratch_size)  -- 接收缓冲区
  self._scratch_size = scratch_size
  self._status = "unpolled"
  return self
end

-- 打开 WebSocket 客户端连接
function socket_mt:open_ws(url, scratch_size)
  return self:_open(scratch_size, pollnet.pollnet_open_ws, url)
end

-- 启动 HTTP 静态文件服务器
function socket_mt:serve_http(addr, dir, scratch_size)
  self.is_http_server = true
  if dir and dir ~= "" then
    return self:_open(scratch_size, pollnet.pollnet_serve_static_http, addr, dir)
  else
    return self:_open(scratch_size, pollnet.pollnet_serve_http, addr)
  end
end

-- 向 HTTP 服务器添加虚拟文件（内存中的文件，不从磁盘读取）
function socket_mt:add_virtual_file(filename, filedata)
  assert(filedata)
  local dsize = #filedata
  pollnet.pollnet_add_virtual_file(_ctx, self._socket, filename, filedata, dsize)
end

-- 从 HTTP 服务器移除虚拟文件
function socket_mt:remove_virtual_file(filename)
  pollnet.pollnet_remove_virtual_file(_ctx, self._socket, filename)
end

-- 启动 WebSocket 服务器监听
function socket_mt:listen_ws(addr, scratch_size)
  return self:_open(scratch_size, pollnet.pollnet_listen_ws, addr)
end

-- 设置新客户端连接回调
function socket_mt:on_connection(f)
  self._on_connection = f
  return self
end

-- 读取收到的消息
function socket_mt:_get_message()
  local msg_size = pollnet.pollnet_get(_ctx, self._socket, self._scratch, self._scratch_size)
  if msg_size > 0 then
    return ffi.string(self._scratch, msg_size)
  else
    return nil
  end
end

-- 轮询 socket 状态（每帧调用）
-- 返回 true/false 表示是否仍在运行，第二个返回值为消息内容
function socket_mt:poll()
  if not self._socket then 
    self._status = "invalid"
    return false, "invalid"
  end
  local res = POLLNET_RESULT_CODES[pollnet.pollnet_update(_ctx, self._socket)] or "error"
  self._status = res
  self._last_message = nil
  if res == "hasdata" then
    self._status = "open"
    self._last_message = self:_get_message()
    return true, self._last_message
  elseif res == "nodata" then
    self._status = "open"
    return true
  elseif res == "opening" then
    self._status = "opening"
    return true
  elseif res == "error" then
    self._last_message = self:error_msg()
    return false, self._last_message
  elseif res == "closed" then
    return false, "closed"
  elseif res == "newclient" then
    -- 新客户端连接：创建子 socket 并触发回调
    local client_addr = self:_get_message()
    local client_handle = pollnet.pollnet_get_connected_client_handle(_ctx, self._socket)
    assert(client_handle > 0)
    local client_sock = Socket():_open(self._scratch_size, client_handle)
    client_sock.parent = self
    client_sock.remote_addr = client_addr
    if self._on_connection then
      self._on_connection(client_sock, client_addr)
    else
      print("No connection handler! All incoming connections will be closed!")
      client_sock:close()
    end
    return true
  end
end

-- 获取上一条消息
function socket_mt:last_message()
  return self._last_message
end
-- 获取当前状态
function socket_mt:status()
  return self._status
end
-- 发送消息
function socket_mt:send(msg)
  assert(self._socket)
  pollnet.pollnet_send(_ctx, self._socket, msg)
end
-- 关闭连接
function socket_mt:close()
  assert(self._socket)
  pollnet.pollnet_close(_ctx, self._socket)
  self._socket = nil
end
-- 获取错误信息
function socket_mt:error_msg()
  if not self._socket then return "No socket!" end
  local msg_size = pollnet.pollnet_get_error(_ctx, self._socket, self._scratch, self._scratch_size)
  if msg_size > 0 then
    local smsg = ffi.string(self._scratch, msg_size)
    return smsg
  else
    return nil
  end
end

-- =============================================================================
-- 便捷构造器
-- =============================================================================

-- 创建 WebSocket 客户端连接
local function open_ws(url, scratch_size)
  return Socket():open_ws(url, scratch_size)
end

-- 创建 WebSocket 服务器
local function listen_ws(addr, scratch_size)
  return Socket():listen_ws(addr, scratch_size)
end

-- 创建 HTTP 服务器
local function serve_http(addr, dir, scratch_size)
  return Socket():serve_http(addr, dir, scratch_size)
end

-- 生成 NanoID（用于 Token 等唯一标识符）
local function get_nanoid()
  local _id_scratch = ffi.new("int8_t[?]", 128)
  local msg_size = pollnet.pollnet_get_nanoid(_id_scratch, 128)
  return ffi.string(_id_scratch, msg_size)
end

-- 导出模块
lib_pollnet = {
  init = init_ctx,
  link = link_pollnet,
  init_hack_static = init_ctx_hack_static,
  shutdown = shutdown_ctx, 
  open_ws = open_ws, 
  listen_ws = listen_ws,
  serve_http = serve_http,
  Socket = Socket,
  pollnet = pollnet,
  nanoid = get_nanoid,
}