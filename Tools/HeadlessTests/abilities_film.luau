--!nocheck
-- Films the weapon abilities' EFFECTS from the real game code (ReplicatedStorage/
-- MoveFX, the moves: ReplicatedStorage/Moves): each ability of a pack used in
-- turn by a player standing among dummies, moving the way the move says (the
-- dash, the leap). Tweens really play out here (the pretend Roblox usually
-- jumps them to the end), so every frame is what you'd see. Prints, 30 times
-- a second: FRAME (film time, the ability, its own time, where the player is
-- and faces) and every effect part; STATIC (the floor and dummies) once.
-- render_abilities.py films it, drawing the player posed by the ability's
-- own animation (Tools/Animations/abilities.py).
--
--   luau abilities_film.luau > abilities_film.txt
--   python3 render_abilities.py abilities_film.txt ../../Docs/animations/slime_abilities_fx.mp4
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Instance, Vector3, CFrame = M.Instance, M.Vector3, M.CFrame
local Players = M.services.Players
local RunService = M.services.RunService
local task = M.task
local realPrint = print
math.randomseed(3)

local PACK = { "GooGloves", "Jellyblade", "GelatinHammer", "OozeDaggers", "AcidScythe", "GelatinousEdge" }

----------------------------------------------------------------------
-- tweens that really play (numbers, Vector3s, CFrames, Color3s)
----------------------------------------------------------------------
local tweens = {}
local function easeOf(style, dir, u)
	local s = tostring(style or "")
	local d = tostring(dir or "")
	local function out(x)
		if string.find(s, "Linear") then
			return x
		elseif string.find(s, "Back") then
			local c1 = 1.70158
			local c3 = c1 + 1
			return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
		elseif string.find(s, "Sine") then
			return math.sin(x * math.pi / 2)
		end
		return 1 - (1 - x) * (1 - x) -- (Quad)
	end
	if string.find(d, "InOut") then
		return u < 0.5 and (1 - out(1 - 2 * u)) / 2 or (1 + out(2 * u - 1)) / 2
	elseif string.find(d, "In") and not string.find(d, "Out") then
		return 1 - out(1 - u)
	end
	return out(u)
end
local function lerpAny(a, b, k)
	local ta = M.typeof(a)
	if type(a) == "number" then
		return a + (b - a) * k
	elseif ta == "Vector3" then
		return a:Lerp(b, k)
	elseif ta == "CFrame" then
		return a:Lerp(b, k)
	elseif ta == "Color3" then
		return a:Lerp(b, k)
	end
	return k >= 1 and b or a
end
M.services.TweenService.Create = function(_, inst, info, props)
	local time = (type(info) == "table" and (info.Time or info[1])) or 0.3
	local style = type(info) == "table" and (info.EasingStyle or info[2]) or nil
	local dir = type(info) == "table" and (info.EasingDirection or info[3]) or nil
	local obj = { Completed = { Connect = function() end } }
	function obj.Play()
		local from = {}
		for k in pairs(props) do
			from[k] = inst[k]
		end
		table.insert(tweens, { inst = inst, from = from, to = props, t0 = M.now(), time = math.max(time, 1e-3), style = style, dir = dir })
	end
	function obj.Cancel() end
	return obj
end
local function stepTweens()
	local now = M.now()
	for i = #tweens, 1, -1 do
		local tw = tweens[i]
		local u = math.clamp((now - tw.t0) / tw.time, 0, 1)
		local k = easeOf(tw.style, tw.dir, u)
		if tw.inst.Parent ~= nil or tw.inst.ClassName == "UIScale" then
			for key, to in pairs(tw.to) do
				local ok = pcall(function()
					tw.inst[key] = lerpAny(tw.from[key], to, k)
				end)
				if not ok then
					tw.inst[key] = to
				end
			end
		end
		if u >= 1 then
			table.remove(tweens, i)
		end
	end
end

-- a floor under everything
M.raycast = function(origin, dir)
	if dir.Y < 0 and origin.Y >= 0 and origin.Y + dir.Y <= 0 then
		return { Position = Vector3.new(origin.X, 0, origin.Z), Normal = Vector3.new(0, 1, 0) }
	end
	return nil
end

----------------------------------------------------------------------
-- the player, the dummies
----------------------------------------------------------------------
local function body(name, at)
	local char = Instance.new("Model")
	char.Name = name
	local function part(n, size, off)
		local p = Instance.new("Part")
		p.Name = n
		p.Size = size
		p.CFrame = CFrame.new(at + off)
		p.Parent = char
		return p
	end
	part("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0))
	part("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0))
	part("Head", Vector3.new(2, 1, 1), Vector3.new(0, 1.5, 0))
	part("Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.5, 0, 0))
	part("Left Arm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 0, 0))
	part("Right Leg", Vector3.new(1, 2, 1), Vector3.new(0.5, -2, 0))
	part("Left Leg", Vector3.new(1, 2, 1), Vector3.new(-0.5, -2, 0))
	local hum = Instance.new("Humanoid")
	hum.MoveDirection = Vector3.new(0, 0, 0)
	hum.Parent = char
	char.Parent = M.workspace
	return char
end
local me = Instance.new("Player")
me.Name = "Me"
me.UserId = 1
me.Parent = Players
Players.LocalPlayer = me
local char = body("Me", Vector3.new(0, 3, 0))
me.Character = char
local pg = Instance.new("PlayerGui")
pg.Parent = me
M.players = { me }

local MoveFX = mount.require(mount.module("ReplicatedStorage/MoveFX.lua"))
local Moves = mount.require(mount.module("ReplicatedStorage/Moves.lua"))

-- put the whole body where the root is (the renderer draws it posed)
local function place(cf)
	for _, p in ipairs(char:GetChildren()) do
		if p:IsA("BasePart") then
			local off = ({ Head = Vector3.new(0, 1.5, 0), ["Right Arm"] = Vector3.new(1.5, 0, 0), ["Left Arm"] = Vector3.new(-1.5, 0, 0),
				["Right Leg"] = Vector3.new(0.5, -2, 0), ["Left Leg"] = Vector3.new(-0.5, -2, 0) })[p.Name] or Vector3.new()
			p.CFrame = cf * CFrame.new(off)
		end
	end
end

local function num(x)
	return string.format("%.3f", x)
end
local function dumpPart(p)
	local cf = p.CFrame
	local c = { cf:GetComponents() }
	local col = p.Color
	local shape = tostring(p.Shape or "")
	local sh = string.find(shape, "Ball") and "Ball" or string.find(shape, "Cylinder") and "Cylinder" or "Block"
	local mat = tostring(p.Material or "")
	realPrint(string.format('{"cf":[%s],"s":[%s,%s,%s],"col":[%d,%d,%d],"t":%s,"m":"%s","sh":"%s","c":"Part"}',
		table.concat((function()
			local t = {}
			for i = 1, 12 do
				t[i] = num(c[i])
			end
			return t
		end)(), ","),
		num(p.Size.X), num(p.Size.Y), num(p.Size.Z),
		math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5),
		num(p.Transparency), string.find(mat, "Neon") and "Neon" or "Plastic", sh))
end

-- the dummies (a row in front) and the floor
local dummies = {}
realPrint("STATIC")
do
	local floor = Instance.new("Part")
	floor.Size = Vector3.new(90, 1, 90)
	floor.CFrame = CFrame.new(0, -0.5, -8)
	floor.Color = M.Color3.fromRGB(88, 96, 120)
	dumpPart(floor)
	for _, spot in ipairs({ Vector3.new(0, 2.5, -12), Vector3.new(-5, 2.5, -9), Vector3.new(5, 2.5, -9) }) do
		local d = Instance.new("Part")
		d.Size = Vector3.new(2.4, 5, 2.4)
		d.CFrame = CFrame.new(spot)
		d.Color = M.Color3.fromRGB(190, 74, 47)
		dumpPart(d)
		table.insert(dummies, spot)
	end
end
realPrint("END")

local t = 0
local FPS = 30
local function frame(id, since, root)
	local look = root.LookVector
	realPrint(string.format("FRAME %s %s %s %s %s %s %s", num(t), id, num(since), num(root.Position.X), num(root.Position.Y), num(root.Position.Z),
		num(math.atan2(-look.X, -look.Z))))
	local f = M.workspace:FindFirstChild("MoveFX")
	if f then
		for _, p in ipairs(f:GetDescendants()) do
			if p:IsA("BasePart") and p.Transparency < 0.98 then
				dumpPart(p)
			elseif p:IsA("TextLabel") then
				-- the words that pop up (a BillboardGui over a part)
				local holder = p.Parent and p.Parent.Parent
				local sc = p:FindFirstChildOfClass("UIScale")
				if holder and holder:IsA("BasePart") and (p.TextTransparency or 0) < 0.98 then
					local c = p.TextColor3
					realPrint(string.format("TEXT %s %s %s %d %d %d %s %s %s", num(holder.Position.X), num(holder.Position.Y), num(holder.Position.Z),
						math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5),
						num(sc and sc.Scale or 1), num(p.TextTransparency or 0), p.Text))
				end
			end
		end
	end
	-- a flash over the whole screen
	for _, g in ipairs(pg:GetChildren()) do
		local fr = g:FindFirstChildOfClass("Frame")
		if fr then
			local c = fr.BackgroundColor3
			realPrint(string.format("FLASH %d %d %d %s", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5),
				num(1 - (fr.BackgroundTransparency or 1))))
		end
	end
	realPrint("END")
end

local timers = {}
local function after(dt, fn)
	table.insert(timers, { at = t + dt, fn = fn })
end
local function run(seconds, id, t0)
	local stop = t + seconds
	local dt = 1 / 60
	local n = 0
	while t < stop - 1e-9 do
		t += dt
		n += 1
		M.run(t)
		for i = #timers, 1, -1 do
			if t >= timers[i].at then
				local fn = timers[i].fn
				table.remove(timers, i)
				fn()
			end
		end
		stepTweens()
		RunService.Heartbeat:Fire(dt)
		if n % 2 == 0 then
			frame(id, t - t0, char.HumanoidRootPart.CFrame)
		end
	end
end

for _, id in ipairs(PACK) do
	local move = Moves.of(id)
	local start = CFrame.new(0, 3, 0)
	place(start)
	local t0 = t
	realPrint("ABILITY " .. id .. " " .. num(t))
	-- the moves' movement (what CombatClient does): along the way and there when its time's up
	for _, s in ipairs(move.Steps) do
		if s.Move then
			local m = s.Move
			after(s.At or 0, function()
				local root = char.HumanoidRootPart
				local from = root.Position
				local dir = Vector3.new(0, 0, -1)
				local dist = m.Distance or 8
				if m.ToTarget then
					local p = dummies[1]
					local flat = Vector3.new(p.X - from.X, 0, p.Z - from.Z)
					dir = flat.Unit
					dist = math.clamp(flat.Magnitude - (m.StopShort or 3), 0, dist * 1.4)
				end
				local up = m.Kind == "Dash" and 0 or (m.Up or 4)
				local n = 12
				for k = 1, n do
					after((m.Time or 0.3) * k / n, function()
						local u = k / n
						local h = up > 0 and 4 * up * (u - u * u) or 0
						place(CFrame.lookAt(from + dir * dist * u + Vector3.new(0, h, 0), from + dir * (dist * u + 1) + Vector3.new(0, h, 0)))
					end)
				end
			end)
		end
		if s.Pick then
			after((s.At or 0) + 0.05, function()
				MoveFX.told(me, id, 1, table.find(move.Steps, s), dummies[1])
			end)
		end
	end
	MoveFX.begin(me, id, 0, true)
	local last = 0
	for _, s in ipairs(move.Steps) do
		last = math.max(last, s.At or 0)
	end
	run(math.max(move.Time, last) + 1.6, id, t0)
	-- (a gap between them, everything cleared away)
	local f = M.workspace:FindFirstChild("MoveFX")
	if f then
		f:ClearAllChildren()
	end
	tweens = {}
end
realPrint("DONE " .. num(t))
