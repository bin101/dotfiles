--- aerospace module for sending commands to the AeroSpace window manager server
-- @module Aerospace
-- @copyright 2025
-- @license MIT

local socket_lib           = require("socket")
local unix                 = require("socket.unix")
local json                 = require("dkjson")

local DEFAULT              = {
	SOCK_FMT         = "/tmp/bobko.aerospace-%s.sock",
	TIMEOUT          = 5,
	RETRIES          = 50,
	RETRY_DELAY      = 0.1,
	PROTOCOL_VERSION = 1,
}
local ERR                  = {
	SOCKET   = "socket error",
	NOT_INIT = "socket not connected",
	JSON     = "failed to decode JSON",
	PROTO    = "protocol version mismatch",
}

local encode               = json.encode

local function decode(str)
	local val, _, err = json.decode(str)
	if err then error(ERR.JSON .. ": " .. err) end
	return val
end

local function connect(path)
	local conn = unix()
	local ok, err = conn:connect(path)
	if not ok then
		conn:close()
		error("cannot connect to " .. path .. ": " .. tostring(err))
	end
	conn:settimeout(DEFAULT.TIMEOUT)

	-- v0.21 handshake: send our protocol version, read back server version
	local _, serr = conn:send(string.pack("<I4", DEFAULT.PROTOCOL_VERSION))
	if serr then conn:close(); error(ERR.SOCKET .. ": handshake send: " .. serr) end

	local raw, rerr = conn:receive(4)
	if not raw or #raw < 4 then
		conn:close()
		error(ERR.SOCKET .. ": handshake recv: " .. tostring(rerr))
	end
	local srv_ver = string.unpack("<I4", raw)
	if srv_ver ~= DEFAULT.PROTOCOL_VERSION then
		conn:close()
		error(ERR.PROTO .. " (client=" .. DEFAULT.PROTOCOL_VERSION ..
		      " server=" .. srv_ver .. "). Restart AeroSpace.")
	end

	return conn
end

local function stdout(raw)
	local doc = decode(raw)
	if type(doc) ~= "table" or doc.stdout == nil then
		error(ERR.JSON .. ": missing stdout field")
	end
	if doc.exitCode ~= 0 and doc.stderr and #doc.stderr > 0 then
		error("aerospace error (exit " .. tostring(doc.exitCode) .. "): " .. doc.stderr)
	end
	return doc.stdout
end

-- Read exactly `n` bytes from `conn`, assembling partial reads.
local function recvn(conn, n)
	local buf = ""
	while #buf < n do
		local chunk, err, partial = conn:receive(n - #buf)
		local data = chunk or partial
		if not data or #data == 0 then
			error(ERR.SOCKET .. ": connection closed while reading (" .. tostring(err) .. ")")
		end
		buf = buf .. data
	end
	return buf
end

local Aerospace = {}; Aerospace.__index = Aerospace

function Aerospace.new(path)
	if not path then
		local username = os.getenv("USER") or "unknown"
		path = DEFAULT.SOCK_FMT:format(username)
	end

	local fd, last_err
	for _ = 1, DEFAULT.RETRIES do
		local ok, res = pcall(connect, path)
		if ok then fd = res; break end
		last_err = res
		socket_lib.sleep(DEFAULT.RETRY_DELAY)
	end
	if not fd then error("could not connect after retries: " .. tostring(last_err)) end

	return setmetatable({ sockPath = path, fd = fd }, Aerospace)
end

function Aerospace:close()
	if self.fd then
		self.fd:close(); self.fd = nil
	end
end

Aerospace.__gc = Aerospace.close

function Aerospace:reconnect()
	self:close(); self.fd = connect(self.sockPath)
end

function Aerospace:is_initialized() return self.fd ~= nil end

-- v0.21 framing: {"args":...,"stdin":"","windowId":null,"workspace":null}
local PAYLOAD_TMPL = '{"args":%s,"stdin":"","windowId":null,"workspace":null}'
function Aerospace:_query(args, want_json)
	if not self:is_initialized() then error(ERR.NOT_INIT) end

	-- Send: 4-byte LE length prefix + JSON body
	local payload = PAYLOAD_TMPL:format(encode(args))
	local frame   = string.pack("<I4", #payload) .. payload
	local _, serr = self.fd:send(frame)
	if serr then error(ERR.SOCKET .. ": " .. serr) end

	-- Receive: 4-byte LE length prefix, then exactly that many bytes
	self.fd:settimeout(DEFAULT.TIMEOUT)
	local lenraw = recvn(self.fd, 4)
	local bodylen = string.unpack("<I4", lenraw)
	if bodylen == 0 then error(ERR.SOCKET .. ": server sent empty response") end
	local buf = recvn(self.fd, bodylen)

	local out = stdout(buf)
	return want_json and decode(out) or out
end

local function passthrough(self, argtbl, as_json, cb)
	local res = self:_query(argtbl, as_json)
	return cb and cb(res) or res
end

function Aerospace:list_modes(current_only, cb)
	local args = current_only and { "list-modes", "--current" } or { "list-modes" }
	return passthrough(self, args, false, cb)
end

function Aerospace:list_apps(cb)
	return passthrough(self, { "list-apps", "--json" }, true, cb)
end

function Aerospace:list_workspaces_all(cb)
	return passthrough(self, {
		"list-workspaces", "--all",
		"--format", "%{workspace-is-focused}%{workspace-is-visible}%{workspace}%{monitor-appkit-nsscreen-screens-id}",
		"--json" }, true, cb)
end

function Aerospace:list_workspaces_focused(cb)
	return passthrough(self, { "list-workspaces", "--focused" }, false, cb)
end

function Aerospace:list_windows(space, cb)
	return passthrough(self, { "list-windows", "--workspace", space, "--json" }, false, cb)
end

function Aerospace:list_window_focused(cb)
	return passthrough(self, { "list-windows", "--focused", "--json" }, false, cb)
end

function Aerospace:workspace(ws)
	return self:_query({ "workspace", ws }, false)
end

function Aerospace:list_windows_all(cb)
	return passthrough(self, {
		"list-windows", "--all", "--json",
		"--format", "%{window-id}%{app-name}%{window-title}%{workspace}" }, true, cb)
end

return Aerospace