--- aerospace module for sending commands to the AeroSpace window manager server
-- @module Aerospace
-- @copyright 2025
-- @license MIT

local socket_lib           = require("socket")
local unix                 = require("socket.unix")
local json                 = require("dkjson")

local DEFAULT              = {
	SOCK_FMT    = "/tmp/bobko.aerospace-%s.sock",
	TIMEOUT     = 5,
	DRAIN_TO    = 0.05,
	RETRIES     = 50,
	RETRY_DELAY = 0.1,
}
local ERR                  = {
	SOCKET   = "socket error",
	NOT_INIT = "socket not connected",
	JSON     = "failed to decode JSON",
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
	return conn
end

local function stdout(raw)
	local doc = decode(raw)
	if type(doc) ~= "table" or doc.stdout == nil then
		error(ERR.JSON .. ": missing stdout field")
	end
	return doc.stdout
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

local PAYLOAD_TMPL = '{"command":"","args":%s,"stdin":""}\n'
function Aerospace:_query(args, want_json)
	if not self:is_initialized() then error(ERR.NOT_INIT) end
	local payload = PAYLOAD_TMPL:format(encode(args))
	local _, err = self.fd:send(payload)
	if err then error(ERR.SOCKET .. ": " .. err) end

	self.fd:settimeout(0)
	local buf, wait = "", DEFAULT.TIMEOUT

	while true do
		local r = socket_lib.select({self.fd}, nil, wait)
		if not r or #r == 0 then break end

		local chunk, _, partial = self.fd:receive(8192)
		local data = chunk or partial
		if not data or #data == 0 then break end

		buf = buf .. data

		-- Try early exit: if buf starts with '{' and ends with '}' it's likely complete
		local first = buf:byte(1)
		if first == 0x7B then                          -- '{'
			local last = buf:byte(#buf)
			if last == 0x7D or last == 0x0A then       -- '}' or '\n'
				break
			end
		end

		wait = DEFAULT.DRAIN_TO
	end

	self.fd:settimeout(DEFAULT.TIMEOUT)
	if #buf == 0 then error(ERR.SOCKET .. ": timeout") end

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