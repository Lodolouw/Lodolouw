--[[
	A tiny pretend Roblox for ServerSmokeTest.luau: just the services,
	instances, values and task scheduler the server scripts use, with a
	clock the test moves forward by hand (mock.advance).
]]

-- A tiny stand-in for the bits of Roblox the server scripts use
local clock = 1000000
local realOs = os
local os = setmetatable({ clock = function() return clock end }, { __index = realOs })
local queue = {} -- { at, co, args }
local function schedule(at, co, ...)
	table.insert(queue, { at = at, co = co, args = table.pack(...) })
end
local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		error(debug.traceback(co, tostring(err)), 0)
	end
end
task = {
	spawn = function(fn, ...)
		local co = type(fn) == "thread" and fn or coroutine.create(fn)
		resume(co, ...)
		return co
	end,
	defer = function(fn, ...)
		schedule(clock, coroutine.create(fn), ...)
	end,
	delay = function(t, fn, ...)
		schedule(clock + (t or 0), coroutine.create(fn), ...)
	end,
	wait = function(t)
		local co = coroutine.running()
		schedule(clock + (t or 0), co)
		return coroutine.yield()
	end,
}
local function runQueue()
	local again = true
	while again do
		again = false
		table.sort(queue, function(a, b) return a.at < b.at end)
		for i, item in ipairs(queue) do
			if item.at <= clock then
				table.remove(queue, i)
				resume(item.co, table.unpack(item.args, 1, item.args.n))
				again = true
				break
			end
		end
	end
end
warn = function(...)
	print("WARN", ...)
end

-- values
Vector3 = {}
Vector3.__index = Vector3
function Vector3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3)
end
Vector3.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vector3.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
Vector3.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X ^ 2 + v.Y ^ 2 + v.Z ^ 2) end
	return rawget(Vector3, k)
end
Vector2 = {
	new = function(x, y)
		return { X = x, Y = y, Magnitude = math.sqrt(x * x + y * y) }
	end,
}
CFrame = {}
CFrame.__index = CFrame
local function cf(p) return setmetatable({ Position = p }, CFrame) end
function CFrame.new(x, y, z)
	if type(x) == "table" then return cf(x) end
	return cf(Vector3.new(x or 0, y or 0, z or 0))
end
function CFrame.lookAt(at) return cf(at) end
function CFrame.Angles() return cf(Vector3.new()) end
CFrame.__mul = function(a, b) return cf(a.Position + b.Position) end
Color3 = { fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255 } end }
Enum = setmetatable({}, { __index = function(_, k)
	return setmetatable({}, { __index = function(_, k2) return k .. "." .. k2 end })
end })
Random = { new = function()
	return {
		NextNumber = function() return math.random() end,
		NextInteger = function(_, a, b) return math.random(a, b) end,
	}
end }

-- signals and instances
local function signal()
	local s = { fns = {} }
	function s:Connect(fn) table.insert(self.fns, fn); return { Disconnect = function() end } end
	function s:Fire(...) for _, fn in ipairs(self.fns) do task.spawn(fn, ...) end end
	return s
end
local Instance_ = {}
local function newInstance(className, name)
	local inst = { ClassName = className, Name = name or className, _children = {}, _attrs = {}, _parent = nil }
	function inst:SetAttribute(k, v) self._attrs[k] = v end
	function inst:GetAttribute(k) return self._attrs[k] end
	function inst:FindFirstChild(n)
		for _, c in ipairs(self._children) do if c.Name == n then return c end end
		return nil
	end
	function inst:WaitForChild(n) return assert(self:FindFirstChild(n), "no child " .. n) end
	function inst:GetChildren() return table.clone(self._children) end
	function inst:IsA(c) return self.ClassName == c or (c == "BasePart" and self.ClassName == "Part") end
	function inst:Destroy() end
	return setmetatable(inst, {
		__index = function(t, k)
			if k == "Parent" then return rawget(t, "_parent") end
			return nil
		end,
		__newindex = function(t, k, v)
			if k == "Parent" then
				local old = rawget(t, "_parent")
				if old then
					local i = table.find(old._children, t)
					if i then table.remove(old._children, i) end
				end
				rawset(t, "_parent", v)
				if v then table.insert(v._children, t) end
				return
			end
			rawset(t, k, v)
		end,
	})
end
Instance = { new = function(className)
	local inst = newInstance(className)
	if className == "RemoteEvent" then
		inst.OnServerEvent = signal()
		inst.fired = {}
		function inst:FireClient(player, payload) table.insert(self.fired, { player = player, payload = payload }) end
		function inst:FireAllClients(payload) table.insert(self.fired, { all = true, payload = payload }) end
	end
	return inst
end }
typeof = function(v)
	if type(v) == "table" and getmetatable(v) == Vector3 then return "Vector3" end
	return type(v)
end

-- services
local services = {}
local ReplicatedStorage = newInstance("ReplicatedStorage")
services.ReplicatedStorage = ReplicatedStorage
services.ServerScriptService = newInstance("ServerScriptService")
local Players = newInstance("Players")
Players.PlayerAdded = signal()
Players.PlayerRemoving = signal()
function Players:GetPlayers()
	local list = {}
	for _, c in ipairs(self._children) do table.insert(list, c) end
	return list
end
services.Players = Players
local RunService = { Heartbeat = signal() }
function RunService:IsStudio() return true end
services.RunService = RunService
local function encode(v)
	local t = type(v)
	if t == "nil" then return "null" end
	if t == "boolean" then return tostring(v) end
	if t == "number" then return string.format("%.17g", v) end
	if t == "string" then return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", string.byte(c)) end) .. '"' end
	if #v > 0 or next(v) == nil then
		local parts = {}
		for _, x in ipairs(v) do table.insert(parts, encode(x)) end
		return "[" .. table.concat(parts, ",") .. "]"
	end
	local parts = {}
	for k, x in pairs(v) do table.insert(parts, encode(tostring(k)) .. ":" .. encode(x)) end
	return "{" .. table.concat(parts, ",") .. "}"
end
services.HttpService = { JSONEncode = function(_, v) return encode(v) end }
local stores = {}
services.DataStoreService = { GetDataStore = function(_, name)
	stores[name] = stores[name] or { data = {} }
	local store = stores[name]
	return {
		GetAsync = function(_, key) return store.data[key] and table.clone(store.data[key]) end,
		UpdateAsync = function(_, key, fn) store.data[key] = fn(store.data[key]) end,
	}
end }
game = {
	GetService = function(_, name) return assert(services[name], "no service " .. name) end,
	BindToClose = function() end,
}
workspace = { GetServerTimeNow = function() return clock end }

-- player
function makePlayer(userId, name)
	local p = newInstance("Player", name)
	p.UserId = userId
	p.DisplayName = name
	p.CharacterAdded = signal()
	local char = newInstance("Model", name)
	local root = newInstance("Part", "HumanoidRootPart")
	root.Position = Vector3.new(0, 0, 0)
	root.Parent = char
	function char:PivotTo(c) root.Position = c.Position end
	p.Character = char
	p.root = root
	function p:Kick(msg) print("KICK", msg) end
	function p:IsFriendsWith() return false end
	return p
end

mock = {
	ReplicatedStorage = ReplicatedStorage,
	ServerScriptService = services.ServerScriptService,
	Players = Players,
	RunService = RunService,
	newInstance = newInstance,
	stores = stores,
	now = function() return clock end,
	advance = function(seconds, step)
		step = step or 0.1
		local target = clock + seconds
		while clock < target - 1e-9 do
			local dt = math.min(step, target - clock)
			clock += dt
			runQueue()
			for _, fn in ipairs(RunService.Heartbeat.fns) do fn(dt) end
			runQueue()
		end
	end,
	runQueue = runQueue,
}
