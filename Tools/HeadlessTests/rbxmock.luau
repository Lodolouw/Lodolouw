--!nocheck
-- A small pretend Roblox for headless tests: Vector3, CFrame, Color3, Enum,
-- Instances (parts, models, folders, events), services, a virtual clock with
-- task.wait / spawn / delay, and a flat sand floor for raycasts.
local M = {}

local sqrt, cos, sin, abs = math.sqrt, math.cos, math.sin, math.abs

----------------------------------------------------------------------
-- Virtual time and the task scheduler
----------------------------------------------------------------------
local now = 0
local heap = {}
local seqN = 0
M.errors = {}
M.writes = {} -- (how many CFrame / Transparency writes, for measuring how much moves)

local function hless(a, b)
	if a.t ~= b.t then
		return a.t < b.t
	end
	return a.seq < b.seq
end
local function hpush(item)
	seqN += 1
	item.seq = seqN
	table.insert(heap, item)
	local i = #heap
	while i > 1 do
		local p = i // 2
		if hless(heap[i], heap[p]) then
			heap[i], heap[p] = heap[p], heap[i]
			i = p
		else
			break
		end
	end
end
local function hpop()
	local top = heap[1]
	local last = table.remove(heap)
	if #heap > 0 then
		heap[1] = last
		local i = 1
		while true do
			local l, r = i * 2, i * 2 + 1
			local m = i
			if l <= #heap and hless(heap[l], heap[m]) then
				m = l
			end
			if r <= #heap and hless(heap[r], heap[m]) then
				m = r
			end
			if m == i then
				break
			end
			heap[i], heap[m] = heap[m], heap[i]
			i = m
		end
	end
	return top
end

local function report(co, err)
	local tb = debug.traceback(co, tostring(err))
	table.insert(M.errors, tb)
	print("!! ERROR in thread: " .. tb)
end

local function resume(co, ...)
	if coroutine.status(co) ~= "suspended" then
		return
	end
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		report(co, err)
	end
end

local task = {}
function task.wait(dt)
	dt = math.max(tonumber(dt) or 0, 1 / 60)
	local co = coroutine.running()
	hpush({ t = now + dt, co = co, start = now })
	return coroutine.yield()
end
function task.spawn(f, ...)
	local co = type(f) == "thread" and f or coroutine.create(f)
	resume(co, ...)
	return co
end
function task.delay(dt, f, ...)
	local args = table.pack(...)
	hpush({ t = now + math.max(tonumber(dt) or 0, 0), fn = f, args = args })
end
function task.defer(f, ...)
	local args = table.pack(...)
	hpush({ t = now, fn = f, args = args })
end
function task.cancel() end
M.task = task

function M.now()
	return now
end
-- runs everything scheduled up to time `untilT`
function M.run(untilT, onStep)
	while #heap > 0 and heap[1].t <= untilT do
		local item = hpop()
		now = item.t
		if item.co then
			resume(item.co, now - item.start)
		else
			local co = coroutine.create(item.fn)
			resume(co, table.unpack(item.args, 1, item.args.n))
		end
		if onStep then
			onStep(now)
		end
	end
	now = math.max(now, untilT)
end

----------------------------------------------------------------------
-- typeof
----------------------------------------------------------------------
local V3mt, CFmt, C3mt, EImt, Imt = {}, {}, {}, {}, {}
local function typeof(x)
	local mt = getmetatable(x)
	if mt == V3mt then
		return "Vector3"
	elseif mt == CFmt then
		return "CFrame"
	elseif mt == C3mt then
		return "Color3"
	elseif mt == EImt then
		return "EnumItem"
	elseif mt == Imt then
		return "Instance"
	elseif type(x) == "table" and rawget(x, "__type") then
		return rawget(x, "__type")
	end
	return type(x)
end
M.typeof = typeof

----------------------------------------------------------------------
-- Vector3
----------------------------------------------------------------------
local Vector3 = {}
local Vmethods = {}
local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3mt)
end
Vector3.new = v3
Vector3.zero = v3(0, 0, 0)
Vector3.one = v3(1, 1, 1)
Vector3.xAxis = v3(1, 0, 0)
Vector3.yAxis = v3(0, 1, 0)
Vector3.zAxis = v3(0, 0, 1)
V3mt.__index = function(v, k)
	if k == "Magnitude" then
		return sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return v3(v.X / m, v.Y / m, v.Z / m) -- (a zero vector gives NaN, like Roblox)
	end
	local f = Vmethods[k]
	if f then
		return f
	end
	error("Vector3 has no member '" .. tostring(k) .. "'", 2)
end
V3mt.__newindex = function()
	error("Vector3 is read-only", 2)
end
V3mt.__add = function(a, b)
	assert(getmetatable(a) == V3mt and getmetatable(b) == V3mt, "Vector3 + non-Vector3")
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3mt.__sub = function(a, b)
	assert(getmetatable(a) == V3mt and getmetatable(b) == V3mt, "Vector3 - non-Vector3")
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3mt.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	assert(getmetatable(a) == V3mt and getmetatable(b) == V3mt, "bad Vector3 multiply")
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3mt.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3mt.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3mt.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3mt.__tostring = function(v)
	return string.format("%.3f, %.3f, %.3f", v.X, v.Y, v.Z)
end
function Vmethods.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function Vmethods.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function Vmethods.Lerp(a, b, t)
	assert(getmetatable(b) == V3mt, "Vector3:Lerp needs a Vector3")
	return v3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
end
function Vmethods.Abs(a)
	return v3(abs(a.X), abs(a.Y), abs(a.Z))
end
function Vmethods.Min(a, b)
	return v3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
end
function Vmethods.Max(a, b)
	return v3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
end
function Vmethods.FuzzyEq(a, b, eps)
	return (a - b).Magnitude <= (eps or 1e-5)
end
M.Vector3 = Vector3

local function isNaNv(v)
	return v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z or abs(v.X) == math.huge or abs(v.Y) == math.huge or abs(v.Z) == math.huge
end
M.isNaNv = isNaNv

----------------------------------------------------------------------
-- CFrame (position + a 3x3 rotation, row by row like Roblox)
----------------------------------------------------------------------
local CFrame = {}
local CFmethods = {}
local function cf(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	return setmetatable({
		x = x, y = y, z = z,
		r00 = r00 or 1, r01 = r01 or 0, r02 = r02 or 0,
		r10 = r10 or 0, r11 = r11 or 1, r12 = r12 or 0,
		r20 = r20 or 0, r21 = r21 or 0, r22 = r22 or 1,
	}, CFmt)
end
local function fromAxes(p, right, up, back)
	return cf(p.X, p.Y, p.Z, right.X, up.X, back.X, right.Y, up.Y, back.Y, right.Z, up.Z, back.Z)
end
function CFrame.lookAt(at, target, up)
	up = up or v3(0, 1, 0)
	local look = (target - at)
	if look.Magnitude < 1e-9 then
		return cf(at.X, at.Y, at.Z)
	end
	look = look.Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(v3(0, 0, 1))
	end
	right = right.Unit
	local up2 = right:Cross(look)
	return fromAxes(at, right, up2, -look)
end
function CFrame.new(a, b, c, ...)
	if a == nil then
		return cf(0, 0, 0)
	end
	if getmetatable(a) == V3mt then
		if b ~= nil then
			return CFrame.lookAt(a, b)
		end
		return cf(a.X, a.Y, a.Z)
	end
	if select("#", ...) >= 9 then
		return cf(a, b, c, ...)
	end
	return cf(a, b, c)
end
local function rx(t)
	local c, s = cos(t), sin(t)
	return cf(0, 0, 0, 1, 0, 0, 0, c, -s, 0, s, c)
end
local function ry(t)
	local c, s = cos(t), sin(t)
	return cf(0, 0, 0, c, 0, s, 0, 1, 0, -s, 0, c)
end
local function rz(t)
	local c, s = cos(t), sin(t)
	return cf(0, 0, 0, c, -s, 0, s, c, 0, 0, 0, 1)
end
function CFrame.Angles(a, b, c)
	return rx(a or 0) * ry(b or 0) * rz(c or 0)
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.fromEulerAnglesYXZ(a, b, c)
	return ry(b or 0) * rx(a or 0) * rz(c or 0)
end
function CFrame.fromAxisAngle(axis, t)
	local u = axis.Unit
	local c, s = cos(t), sin(t)
	local C = 1 - c
	local x, y, z = u.X, u.Y, u.Z
	return cf(0, 0, 0,
		c + x * x * C, x * y * C - z * s, x * z * C + y * s,
		y * x * C + z * s, c + y * y * C, y * z * C - x * s,
		z * x * C - y * s, z * y * C + x * s, c + z * z * C)
end
function CFrame.fromMatrix(p, right, up, back)
	back = back or right:Cross(up)
	return fromAxes(p, right, up, back)
end
CFrame.identity = cf(0, 0, 0)
CFmt.__index = function(f, k)
	if k == "Position" or k == "p" then
		return v3(f.x, f.y, f.z)
	elseif k == "X" then
		return f.x
	elseif k == "Y" then
		return f.y
	elseif k == "Z" then
		return f.z
	elseif k == "LookVector" then
		return v3(-f.r02, -f.r12, -f.r22)
	elseif k == "RightVector" then
		return v3(f.r00, f.r10, f.r20)
	elseif k == "UpVector" then
		return v3(f.r01, f.r11, f.r21)
	elseif k == "Rotation" then
		return cf(0, 0, 0, f.r00, f.r01, f.r02, f.r10, f.r11, f.r12, f.r20, f.r21, f.r22)
	end
	local m = CFmethods[k]
	if m then
		return m
	end
	error("CFrame has no member '" .. tostring(k) .. "'", 2)
end
CFmt.__newindex = function()
	error("CFrame is read-only", 2)
end
local function rot(f, v)
	return v3(f.r00 * v.X + f.r01 * v.Y + f.r02 * v.Z, f.r10 * v.X + f.r11 * v.Y + f.r12 * v.Z, f.r20 * v.X + f.r21 * v.Y + f.r22 * v.Z)
end
CFmt.__mul = function(a, b)
	assert(getmetatable(a) == CFmt, "CFrame * : left side must be a CFrame")
	if getmetatable(b) == V3mt then
		local r = rot(a, b)
		return v3(r.X + a.x, r.Y + a.y, r.Z + a.z)
	end
	assert(getmetatable(b) == CFmt, "CFrame * : right side must be a CFrame or Vector3")
	local p = rot(a, v3(b.x, b.y, b.z))
	local out = cf(p.X + a.x, p.Y + a.y, p.Z + a.z,
		a.r00 * b.r00 + a.r01 * b.r10 + a.r02 * b.r20, a.r00 * b.r01 + a.r01 * b.r11 + a.r02 * b.r21, a.r00 * b.r02 + a.r01 * b.r12 + a.r02 * b.r22,
		a.r10 * b.r00 + a.r11 * b.r10 + a.r12 * b.r20, a.r10 * b.r01 + a.r11 * b.r11 + a.r12 * b.r21, a.r10 * b.r02 + a.r11 * b.r12 + a.r12 * b.r22,
		a.r20 * b.r00 + a.r21 * b.r10 + a.r22 * b.r20, a.r20 * b.r01 + a.r21 * b.r11 + a.r22 * b.r21, a.r20 * b.r02 + a.r21 * b.r12 + a.r22 * b.r22)
	-- (kept square and unit length, like Roblox's: otherwise rounding errors
	-- snowball over thousands of moves)
	local x = v3(out.r00, out.r10, out.r20)
	local y = v3(out.r01, out.r11, out.r21)
	local xm = x.Magnitude
	if xm > 0 then
		x = x / xm
		y = y - x * x:Dot(y)
		local ym = y.Magnitude
		if ym > 0 then
			y = y / ym
			local z = x:Cross(y)
			out.r00, out.r10, out.r20 = x.X, x.Y, x.Z
			out.r01, out.r11, out.r21 = y.X, y.Y, y.Z
			out.r02, out.r12, out.r22 = z.X, z.Y, z.Z
		end
	end
	return out
end
CFmt.__add = function(a, b)
	assert(getmetatable(a) == CFmt and getmetatable(b) == V3mt, "CFrame + needs a Vector3")
	return cf(a.x + b.X, a.y + b.Y, a.z + b.Z, a.r00, a.r01, a.r02, a.r10, a.r11, a.r12, a.r20, a.r21, a.r22)
end
CFmt.__sub = function(a, b)
	assert(getmetatable(a) == CFmt and getmetatable(b) == V3mt, "CFrame - needs a Vector3")
	return cf(a.x - b.X, a.y - b.Y, a.z - b.Z, a.r00, a.r01, a.r02, a.r10, a.r11, a.r12, a.r20, a.r21, a.r22)
end
CFmt.__eq = function(a, b)
	for _, k in ipairs({ "x", "y", "z", "r00", "r01", "r02", "r10", "r11", "r12", "r20", "r21", "r22" }) do
		if a[k] ~= b[k] then
			return false
		end
	end
	return true
end
CFmt.__tostring = function(f)
	return string.format("CF(%.2f, %.2f, %.2f)", f.x, f.y, f.z)
end
function CFmethods.Inverse(f)
	-- transpose the rotation; p' = -R^T p
	local t = cf(0, 0, 0, f.r00, f.r10, f.r20, f.r01, f.r11, f.r21, f.r02, f.r12, f.r22)
	local p = rot(t, v3(f.x, f.y, f.z))
	return cf(-p.X, -p.Y, -p.Z, t.r00, t.r01, t.r02, t.r10, t.r11, t.r12, t.r20, t.r21, t.r22)
end
function CFmethods.ToObjectSpace(a, b)
	return a:Inverse() * b
end
function CFmethods.ToWorldSpace(a, b)
	return a * b
end
function CFmethods.PointToObjectSpace(a, v)
	return a:Inverse() * v
end
function CFmethods.PointToWorldSpace(a, v)
	return a * v
end
function CFmethods.VectorToWorldSpace(a, v)
	return rot(a, v)
end
function CFmethods.VectorToObjectSpace(a, v)
	return rot(a:Inverse(), v)
end
function CFmethods.GetComponents(f)
	return f.x, f.y, f.z, f.r00, f.r01, f.r02, f.r10, f.r11, f.r12, f.r20, f.r21, f.r22
end
function CFmethods.Lerp(a, b, t)
	-- (rotation: blended and re-squared, good enough for tests)
	local p = a.Position:Lerp(b.Position, t)
	local r = a.RightVector:Lerp(b.RightVector, t)
	local u = a.UpVector:Lerp(b.UpVector, t)
	r = r.Unit
	local back = r:Cross(u).Unit
	u = back:Cross(r).Unit
	return fromAxes(p, r, u, back)
end
function CFmethods.isNaN(f)
	for _, k in ipairs({ "x", "y", "z", "r00", "r11", "r22" }) do
		local n = f[k]
		if n ~= n or abs(n) == math.huge then
			return true
		end
	end
	return false
end
M.CFrame = CFrame

----------------------------------------------------------------------
-- Color3, UDim2 and friends (just enough to hold values)
----------------------------------------------------------------------
local Color3 = {}
local function c3(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3mt)
end
Color3.new = c3
function Color3.fromRGB(r, g, b)
	return c3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
C3mt.__index = function(c, k)
	if k == "Lerp" then
		return function(a, b, t)
			return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
		end
	elseif k == "ToHex" then
		return function(a)
			return string.format("%02x%02x%02x", math.floor(a.R * 255 + 0.5), math.floor(a.G * 255 + 0.5), math.floor(a.B * 255 + 0.5))
		end
	end
	error("Color3 has no member " .. tostring(k), 2)
end
C3mt.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
M.Color3 = Color3

local function valueType(name)
	return {
		new = function(...)
			return { __type = name, ... }
		end,
	}
end
-- UDim2 (scale and offset on each axis, and they add up)
local U2mt = {}
local function udim2(xs, xo, ys, yo)
	return setmetatable({ __type = "UDim2", X = { Scale = xs or 0, Offset = xo or 0 }, Y = { Scale = ys or 0, Offset = yo or 0 } }, U2mt)
end
U2mt.__add = function(a, b)
	return udim2(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
U2mt.__sub = function(a, b)
	return udim2(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset)
end
U2mt.__eq = function(a, b)
	return a.X.Scale == b.X.Scale and a.X.Offset == b.X.Offset and a.Y.Scale == b.Y.Scale and a.Y.Offset == b.Y.Offset
end
U2mt.__tostring = function(u)
	return string.format("{%g,%g},{%g,%g}", u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset)
end
M.UDim2 = {
	new = function(xs, xo, ys, yo)
		for _, n in ipairs({ xs or 0, xo or 0, ys or 0, yo or 0 }) do
			assert(type(n) == "number" and n == n, "UDim2.new needs numbers")
		end
		return udim2(xs, xo, ys, yo)
	end,
	fromScale = function(x, y)
		assert(type(x) == "number" and type(y) == "number", "UDim2.fromScale needs two numbers")
		return udim2(x, 0, y, 0)
	end,
	fromOffset = function(x, y)
		assert(type(x) == "number" and type(y) == "number", "UDim2.fromOffset needs two numbers")
		return udim2(0, x, 0, y)
	end,
}
M.UDim = valueType("UDim")
M.Vector2 = valueType("Vector2")
M.NumberRange = valueType("NumberRange")
M.NumberSequence = valueType("NumberSequence")
M.NumberSequenceKeypoint = valueType("NumberSequenceKeypoint")
M.ColorSequence = valueType("ColorSequence")
M.ColorSequenceKeypoint = valueType("ColorSequenceKeypoint")
M.PhysicalProperties = valueType("PhysicalProperties")
M.TweenInfo = valueType("TweenInfo")

----------------------------------------------------------------------
-- Enum
----------------------------------------------------------------------
local enumCache = {}
local Enum = setmetatable({}, {
	__index = function(_, typeName)
		local t = enumCache[typeName]
		if not t then
			t = setmetatable({}, {
				__index = function(tt, itemName)
					local item = setmetatable({ EnumType = typeName, Name = itemName, Value = 0 }, EImt)
					rawset(tt, itemName, item)
					return item
				end,
			})
			enumCache[typeName] = t
		end
		return t
	end,
})
EImt.__tostring = function(e)
	return "Enum." .. e.EnumType .. "." .. e.Name
end
M.Enum = Enum

----------------------------------------------------------------------
-- Random (deterministic)
----------------------------------------------------------------------
local Random = {}
local Rmt = {}
Rmt.__index = Rmt
function Random.new(seed)
	seed = math.floor(tonumber(seed) or 12345) % 2147483647
	if seed <= 0 then
		seed = seed + 2147483646
	end
	return setmetatable({ s = seed }, Rmt)
end
function Rmt:_next()
	self.s = (self.s * 48271) % 2147483647
	return self.s / 2147483647
end
function Rmt:NextNumber(a, b)
	a, b = a or 0, b or 1
	return a + (b - a) * self:_next()
end
function Rmt:NextInteger(a, b)
	return math.floor(a + (b - a + 1) * self:_next())
end
M.Random = Random

----------------------------------------------------------------------
-- Signals
----------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ conns = {} }, Signal)
end
function Signal:Connect(fn)
	local c = { fn = fn, connected = true }
	table.insert(self.conns, c)
	c.Disconnect = function()
		c.connected = false
	end
	return c
end
Signal.connect = Signal.Connect
function Signal:Once(fn)
	local c
	c = self:Connect(function(...)
		c.Disconnect()
		fn(...)
	end)
	return c
end
function Signal:Fire(...)
	for _, c in ipairs(table.clone(self.conns)) do
		if c.connected then
			task.spawn(c.fn, ...)
		end
	end
end
function Signal:Wait()
	local co = coroutine.running()
	self:Once(function(...)
		resume(co, ...)
	end)
	return coroutine.yield()
end
M.Signal = Signal

----------------------------------------------------------------------
-- Instances
----------------------------------------------------------------------
local CLASS_PARENT = {
	Part = "BasePart", WedgePart = "BasePart", TrussPart = "BasePart", MeshPart = "BasePart", BasePart = "PVInstance",
	Model = "PVInstance", Workspace = "Model", PVInstance = "Instance",
	ParticleEmitter = "Instance", PointLight = "Light", SpotLight = "Light", Light = "Instance",
	Folder = "Instance", BindableEvent = "Instance", RemoteEvent = "Instance", RemoteFunction = "Instance",
	Humanoid = "Instance", ProximityPrompt = "Instance", Sound = "Instance", Attachment = "Instance",
	SpecialMesh = "Instance", Decal = "Instance", SurfaceGui = "LayerCollector", BillboardGui = "LayerCollector",
	LayerCollector = "Instance", TextLabel = "GuiObject", Frame = "GuiObject", GuiObject = "Instance",
	ModuleScript = "Instance", Script = "Instance", Player = "Instance", Players = "Instance",
	ControllerManager = "Instance", Beam = "Instance", Trail = "Instance",
}
local function isA(className, want)
	local c = className
	while c do
		if c == want then
			return true
		end
		c = CLASS_PARENT[c]
	end
	return want == "Instance"
end

local DEFAULTS = {
	Part = function()
		return {
			Size = v3(4, 1, 2), CFrame = cf(0, 0, 0), Color = c3(0.64, 0.64, 0.64), Transparency = 0,
			Anchored = false, CanCollide = true, CanQuery = true, CanTouch = true, CastShadow = true,
			Material = Enum.Material.Plastic, PivotOffset = cf(0, 0, 0), Shape = Enum.PartType.Block,
			AssemblyLinearVelocity = v3(0, 0, 0),
		}
	end,
	Model = function()
		return {}
	end,
	Humanoid = function()
		return { Health = 100, MaxHealth = 100, WalkSpeed = 16, HipHeight = 2, RigType = Enum.HumanoidRigType.R15 }
	end,
}

local all = setmetatable({}, { __mode = "k" })
local Instance = {}
local methods = {}
local SIGNAL_NAMES = {
	Event = true, OnServerEvent = true, OnClientEvent = true, Triggered = true, ChildAdded = true, ChildRemoved = true,
	DescendantAdded = true, DescendantRemoving = true, AncestryChanged = true, Destroying = true,
	CharacterAdded = true, CharacterRemoving = true, Died = true, HealthChanged = true, PlayerAdded = true,
	PlayerRemoving = true, Heartbeat = true, Stepped = true, RenderStepped = true, Touched = true,
	Activated = true, MouseButton1Click = true, MouseButton1Down = true, MouseButton1Up = true, MouseEnter = true,
	MouseLeave = true, InputBegan = true, InputEnded = true, InputChanged = true, Changed = true, FocusLost = true,
	Ended = true, Played = true, Loaded = true, SelectionGained = true, SelectionLost = true, TouchTap = true,
	PromptShown = true, PromptHidden = true, TriggerEnded = true, OnInvoke = true,
}

function Instance.new(className, parent)
	local o = setmetatable({
		__props = { ClassName = className, Name = className },
		__children = {},
		__attrs = {},
		__signals = {},
		__attrSignals = {},
		__propSignals = {},
	}, Imt)
	local d = DEFAULTS[className]
	if not d and isA(className, "BasePart") then
		d = DEFAULTS.Part
	end
	if d then
		for k, v in pairs(d()) do
			o.__props[k] = v
		end
	end
	all[o] = true
	if parent then
		o.Parent = parent
	end
	return o
end
M.Instance = Instance

Imt.__index = function(self, k)
	local props = rawget(self, "__props")
	local v = props[k]
	if v ~= nil then
		return v
	end
	if k == "Position" and props.CFrame then
		return props.CFrame.Position
	end
	if k == "Orientation" and props.CFrame then
		return v3(0, 0, 0)
	end
	local m = methods[k]
	if m then
		return m
	end
	if SIGNAL_NAMES[k] then
		local s = rawget(self, "__signals")[k]
		if not s then
			s = Signal.new()
			rawget(self, "__signals")[k] = s
		end
		return s
	end
	for _, c in ipairs(rawget(self, "__children")) do
		if c.__props.Name == k then
			return c
		end
	end
	if k == "Parent" or k == "PrimaryPart" or k == "Adornee" or k == "Character" then
		return nil
	end
	return nil
end

local function fireSignal(self, name, ...)
	local s = rawget(self, "__signals")[name]
	if s then
		s:Fire(...)
	end
end

local function removeFrom(list, item)
	for i, x in ipairs(list) do
		if x == item then
			table.remove(list, i)
			return
		end
	end
end

Imt.__newindex = function(self, k, v)
	local props = rawget(self, "__props")
	if k == "Parent" then
		local old = props.Parent
		if old == v then
			return
		end
		if rawget(self, "__destroyed") and v ~= nil then
			error("The Parent property of " .. tostring(props.Name) .. " is locked (destroyed)", 2)
		end
		if old then
			removeFrom(rawget(old, "__children"), self)
			fireSignal(old, "ChildRemoved", self)
		end
		props.Parent = v
		if v then
			table.insert(rawget(v, "__children"), self)
			fireSignal(v, "ChildAdded", self)
			local a = v
			while a do
				fireSignal(a, "DescendantAdded", self)
				a = rawget(a, "__props").Parent
			end
		end
		fireSignal(self, "AncestryChanged", self, v)
		return
	elseif k == "Position" and props.CFrame then
		local c = props.CFrame
		props.CFrame = cf(v.X, v.Y, v.Z, c.r00, c.r01, c.r02, c.r10, c.r11, c.r12, c.r20, c.r21, c.r22)
		return
	elseif k == "CFrame" then
		assert(getmetatable(v) == CFmt, "CFrame must be a CFrame")
		M.writes.CFrame = (M.writes.CFrame or 0) + 1
		if CFmethods.isNaN(v) then
			M.nanWrites = (M.nanWrites or 0) + 1
			print("!! NaN CFrame written to " .. tostring(props.Name))
		end
	elseif k == "Size" and isA(props.ClassName, "BasePart") then
		assert(getmetatable(v) == V3mt, "Size must be a Vector3")
		if isNaNv(v) then
			M.nanWrites = (M.nanWrites or 0) + 1
			print("!! NaN Size written to " .. tostring(props.Name))
		end
	elseif k == "Health" and props.ClassName == "Humanoid" then
		v = math.clamp(v, 0, props.MaxHealth or 100)
		local was = props.Health
		props.Health = v
		if v ~= was then
			fireSignal(self, "HealthChanged", v)
		end
		if was and was > 0 and v <= 0 then
			fireSignal(self, "Died")
		end
		return
	end
	props[k] = v
	local ps = rawget(self, "__propSignals")[k]
	if ps then
		ps:Fire()
	end
end
Imt.__tostring = function(self)
	return rawget(self, "__props").Name
end

function methods.GetChildren(self)
	return table.clone(rawget(self, "__children"))
end
function methods.GetDescendants(self)
	local out = {}
	local function walk(o)
		for _, c in ipairs(rawget(o, "__children")) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function methods.FindFirstChild(self, name, recursive)
	for _, c in ipairs(rawget(self, "__children")) do
		if c.__props.Name == name then
			return c
		end
	end
	if recursive then
		for _, c in ipairs(rawget(self, "__children")) do
			local f = methods.FindFirstChild(c, name, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function methods.WaitForChild(self, name)
	return methods.FindFirstChild(self, name)
end
function methods.FindFirstChildOfClass(self, className)
	for _, c in ipairs(rawget(self, "__children")) do
		if c.__props.ClassName == className then
			return c
		end
	end
	return nil
end
function methods.FindFirstChildWhichIsA(self, className, recursive)
	for _, c in ipairs(rawget(self, "__children")) do
		if isA(c.__props.ClassName, className) then
			return c
		end
	end
	if recursive then
		for _, c in ipairs(rawget(self, "__children")) do
			local f = methods.FindFirstChildWhichIsA(c, className, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function methods.FindFirstAncestor(self, name)
	local a = self.__props.Parent
	while a do
		if a.__props.Name == name then
			return a
		end
		a = a.__props.Parent
	end
	return nil
end
function methods.FindFirstAncestorWhichIsA(self, className)
	local a = self.__props.Parent
	while a do
		if isA(a.__props.ClassName, className) then
			return a
		end
		a = a.__props.Parent
	end
	return nil
end
methods.FindFirstAncestorOfClass = methods.FindFirstAncestorWhichIsA
function methods.IsA(self, className)
	return isA(self.__props.ClassName, className)
end
function methods.IsDescendantOf(self, other)
	local a = self.__props.Parent
	while a do
		if a == other then
			return true
		end
		a = a.__props.Parent
	end
	return false
end
function methods.GetFullName(self)
	local names = {}
	local a = self
	while a do
		table.insert(names, 1, a.__props.Name)
		a = a.__props.Parent
	end
	return table.concat(names, ".")
end
function methods.Destroy(self)
	if rawget(self, "__destroyed") then
		return
	end
	fireSignal(self, "Destroying")
	for _, c in ipairs(table.clone(rawget(self, "__children"))) do
		methods.Destroy(c)
	end
	self.Parent = nil
	rawset(self, "__destroyed", true)
	if M.onDestroy then
		M.onDestroy(self)
	end
end
function methods.ClearAllChildren(self)
	for _, c in ipairs(table.clone(rawget(self, "__children"))) do
		methods.Destroy(c)
	end
end
function methods.SetAttribute(self, name, value)
	assert(type(name) == "string", "attribute name must be a string")
	if typeof(value) == "Vector3" and isNaNv(value) then
		M.nanWrites = (M.nanWrites or 0) + 1
		print("!! NaN attribute " .. name)
	end
	if type(value) == "number" and (value ~= value) then
		M.nanWrites = (M.nanWrites or 0) + 1
		print("!! NaN attribute " .. name)
	end
	local attrs = rawget(self, "__attrs")
	local was = attrs[name]
	attrs[name] = value
	if was ~= value then
		local s = rawget(self, "__attrSignals")[name]
		if s then
			s:Fire()
		end
		if M.onAttribute then
			M.onAttribute(self, name, value, was)
		end
	end
end
function methods.GetAttribute(self, name)
	return rawget(self, "__attrs")[name]
end
function methods.GetAttributes(self)
	return table.clone(rawget(self, "__attrs"))
end
function methods.GetAttributeChangedSignal(self, name)
	local s = rawget(self, "__attrSignals")[name]
	if not s then
		s = Signal.new()
		rawget(self, "__attrSignals")[name] = s
	end
	return s
end
function methods.GetPropertyChangedSignal(self, name)
	local s = rawget(self, "__propSignals")[name]
	if not s then
		s = Signal.new()
		rawget(self, "__propSignals")[name] = s
	end
	return s
end
function methods.Clone(self)
	local map = {}
	local function copy(o)
		local n = Instance.new(o.__props.ClassName)
		map[o] = n
		for k, v in pairs(o.__props) do
			if k ~= "Parent" then
				n.__props[k] = v
			end
		end
		for k, v in pairs(rawget(o, "__attrs")) do
			rawget(n, "__attrs")[k] = v
		end
		for _, c in ipairs(rawget(o, "__children")) do
			local cc = copy(c)
			cc.__props.Parent = n
			table.insert(rawget(n, "__children"), cc)
		end
		return n
	end
	local root = copy(self)
	-- (references inside the copy point at the copied instances)
	for old, new in pairs(map) do
		for k, v in pairs(new.__props) do
			if k ~= "Parent" and typeof(v) == "Instance" and map[v] then
				new.__props[k] = map[v]
			end
		end
		local _ = old
	end
	return root
end
-- pivots: a part's is its CFrame; a model's is its PrimaryPart's (or its box's middle)
local function modelParts(m)
	local list = {}
	for _, d in ipairs(methods.GetDescendants(m)) do
		if isA(d.__props.ClassName, "BasePart") then
			table.insert(list, d)
		end
	end
	return list
end
function methods.GetBoundingBox(self)
	local lo = v3(math.huge, math.huge, math.huge)
	local hi = v3(-math.huge, -math.huge, -math.huge)
	for _, p in ipairs(modelParts(self)) do
		local c, s = p.__props.CFrame, p.__props.Size / 2
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local w = c * v3(s.X * sx, s.Y * sy, s.Z * sz)
					lo = lo:Min(w)
					hi = hi:Max(w)
				end
			end
		end
	end
	if lo.X == math.huge then
		return cf(0, 0, 0), v3(0, 0, 0)
	end
	local mid = (lo + hi) / 2
	return cf(mid.X, mid.Y, mid.Z), hi - lo
end
function methods.GetPivot(self)
	if isA(self.__props.ClassName, "BasePart") then
		return self.__props.CFrame * (self.__props.PivotOffset or cf(0, 0, 0))
	end
	local pp = self.__props.PrimaryPart
	if pp then
		return pp.__props.CFrame * (pp.__props.PivotOffset or cf(0, 0, 0))
	end
	if self.__props.WorldPivot then
		return self.__props.WorldPivot
	end
	local box = methods.GetBoundingBox(self)
	return box
end
function methods.PivotTo(self, target)
	assert(getmetatable(target) == CFmt, "PivotTo needs a CFrame")
	if CFmethods.isNaN(target) then
		M.nanWrites = (M.nanWrites or 0) + 1
		if (M.nanWrites or 0) < 3 then
			print("!! NaN PivotTo on " .. tostring(self.__props.Name) .. "\n" .. debug.traceback())
		end
	end
	local old = methods.GetPivot(self)
	local delta = target * old:Inverse()
	if isA(self.__props.ClassName, "BasePart") then
		self.CFrame = delta * self.__props.CFrame
		return
	end
	for _, p in ipairs(modelParts(self)) do
		p.__props.CFrame = delta * p.__props.CFrame
	end
	if not self.__props.PrimaryPart then
		self.__props.WorldPivot = target
	end
	if M.onPivot then
		M.onPivot(self, target)
	end
end
function methods.ScaleTo(self, s)
	self.__props.Scale = s
end
function methods.GetScale(self)
	return self.__props.Scale or 1
end
function methods.Emit() end
function methods.Play() end
function methods.Stop() end
function methods.Fire(self, ...)
	fireSignal(self, "Event", ...)
end
function methods.FireClient(self, player, ...)
	if M.onFireClient then
		M.onFireClient(self, player, ...)
	end
end
function methods.FireServer(self, ...)
	if M.onFireServer then
		M.onFireServer(self, ...)
	end
end
function methods.InvokeServer(self, ...)
	if M.onInvokeServer then
		return M.onInvokeServer(self, ...)
	end
	return false, "no server"
end
function methods.FireAllClients(self, ...)
	if M.onFireClient then
		M.onFireClient(self, nil, ...)
	end
end
function methods.TakeDamage(self, amount)
	self.Health = (self.__props.Health or 0) - amount
end
function methods.RequestStreamAroundAsync() end
function methods.GetPlayers(self)
	return table.clone(M.players)
end
function methods.GetServerTimeNow()
	return now
end
function methods.BulkMoveTo(self, parts, cfs, mode)
	assert(#parts == #cfs, "BulkMoveTo needs as many CFrames as parts")
	M.writes.Bulk = (M.writes.Bulk or 0) + 1
	for i, p in ipairs(parts) do
		p.CFrame = cfs[i]
	end
end
function methods.Raycast(self, origin, dir, params)
	return M.raycast and M.raycast(origin, dir, params) or nil
end
function methods.GetService(self, name)
	return M.services[name]
end
M.methods = methods

----------------------------------------------------------------------
-- Services
----------------------------------------------------------------------
M.players = {}
local game = Instance.new("DataModel")
game.Name = "game"
local workspace = Instance.new("Workspace")
workspace.Name = "Workspace"
workspace.Parent = game
M.game, M.workspace = game, workspace
M.services = { Workspace = workspace }
for _, name in ipairs({ "Players", "ReplicatedStorage", "ServerStorage", "ServerScriptService", "Lighting", "SoundService", "StarterPlayer" }) do
	local s = Instance.new(name)
	s.Name = name
	s.Parent = game
	M.services[name] = s
end

local tags = {}
local tagAdded, tagRemoved = {}, {}
local CollectionService = {}
function CollectionService:AddTag(inst, tag)
	tags[tag] = tags[tag] or {}
	if not tags[tag][inst] then
		tags[tag][inst] = true
		if tagAdded[tag] then
			tagAdded[tag]:Fire(inst)
		end
	end
end
function CollectionService:RemoveTag(inst, tag)
	if tags[tag] and tags[tag][inst] then
		tags[tag][inst] = nil
		if tagRemoved[tag] then
			tagRemoved[tag]:Fire(inst)
		end
	end
end
function CollectionService:HasTag(inst, tag)
	return tags[tag] ~= nil and tags[tag][inst] == true
end
function CollectionService:GetTagged(tag)
	local out = {}
	for inst in pairs(tags[tag] or {}) do
		if not rawget(inst, "__destroyed") then
			table.insert(out, inst)
		end
	end
	return out
end
function CollectionService:GetInstanceAddedSignal(tag)
	tagAdded[tag] = tagAdded[tag] or Signal.new()
	return tagAdded[tag]
end
function CollectionService:GetInstanceRemovedSignal(tag)
	tagRemoved[tag] = tagRemoved[tag] or Signal.new()
	return tagRemoved[tag]
end
M.services.CollectionService = CollectionService

M.services.Debris = {
	AddItem = function(_, inst, t)
		task.delay(t or 10, function()
			if inst and not rawget(inst, "__destroyed") then
				methods.Destroy(inst)
			end
		end)
	end,
}
M.services.RunService = {
	Heartbeat = Signal.new(),
	RenderStepped = Signal.new(),
	Stepped = Signal.new(),
	BindToRenderStep = function() end,
	UnbindFromRenderStep = function() end,
	IsStudio = function()
		return false
	end,
	IsServer = function()
		return true
	end,
}
M.services.TweenService = {
	Create = function(_, inst, info, props)
		assert(M.typeof(inst) == "Instance", "TweenService:Create needs an Instance")
		assert(type(props) == "table", "TweenService:Create needs a property table")
		return {
			Play = function()
				-- (jumps straight to the end)
				for k, v in pairs(props) do
					inst[k] = v
				end
			end,
			Cancel = function() end,
			Completed = Signal.new(),
		}
	end,
}
M.preloaded = {}
M.services.ContentProvider = {
	PreloadAsync = function(_, list)
		for _, a in ipairs(list) do
			table.insert(M.preloaded, a)
		end
	end,
}
M.RaycastParams = {
	new = function()
		return { FilterType = nil, FilterDescendantsInstances = {}, RespectCanCollide = false }
	end,
}

----------------------------------------------------------------------
-- An environment for running a real game script inside the pretend Roblox
----------------------------------------------------------------------
function M.env(extra)
	local e = {
		game = game, workspace = workspace, Workspace = workspace,
		Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Enum = Enum, Instance = Instance, Random = Random,
		UDim2 = M.UDim2, UDim = M.UDim, Vector2 = M.Vector2, NumberRange = M.NumberRange, NumberSequence = M.NumberSequence,
		NumberSequenceKeypoint = M.NumberSequenceKeypoint, ColorSequence = M.ColorSequence, ColorSequenceKeypoint = M.ColorSequenceKeypoint,
		PhysicalProperties = M.PhysicalProperties, TweenInfo = M.TweenInfo, RaycastParams = M.RaycastParams,
		task = task, typeof = typeof, warn = function(...)
			print("WARN:", ...)
			M.warnings = (M.warnings or 0) + 1
		end,
		print = print, pairs = pairs, ipairs = ipairs, next = next, select = select, type = type, tostring = tostring,
		tonumber = tonumber, pcall = pcall, xpcall = xpcall, error = error, assert = assert, setmetatable = setmetatable,
		getmetatable = getmetatable, rawget = rawget, rawset = rawset, rawequal = rawequal, unpack = table.unpack,
		math = math, string = string, table = table, coroutine = coroutine, utf8 = utf8, debug = debug, bit32 = bit32,
		os = { clock = function()
			return now
		end, time = function()
			return 1700000000 + math.floor(now)
		end },
		tick = function()
			return now
		end,
		time = function()
			return now
		end,
	}
	for k, v in pairs(extra or {}) do
		e[k] = v
	end
	return e
end

function M.load(source, name, env)
	local fn, err = loadstring(source, "=" .. name)
	if not fn then
		error("compile error in " .. name .. ": " .. tostring(err))
	end
	setfenv(fn, env)
	return fn
end

return M
