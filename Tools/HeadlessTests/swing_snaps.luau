--!nocheck
-- Snapshots of what flies off the SWINGS (ReplicatedStorage/WeaponFX: the
-- swing themes' bits, the Secrets' waves and eyes), from the real game code: a
-- cut drawn in front of the player with each weapon, and a moment later every
-- part it threw, as JSON (the same as abilities_film.luau's). The crescents
-- (Trails) aren't parts, so they're not in it. render_swings.py draws them.
--
--   luau swing_snaps.luau > swings.txt
--   python3 render_swings.py swings.txt ../../Docs/weapons/swing_effects.png
--   luau swing_snaps.luau -a GooGloves,AcidScythe > swings.txt     (other weapons)
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Instance, Vector3, CFrame = M.Instance, M.Vector3, M.CFrame
local Players = M.services.Players
local RunService = M.services.RunService
local ReplicatedStorage = M.services.ReplicatedStorage
local realPrint = print
math.randomseed(5)

local args = { ... }
local KEYS = { "HonourBlade", "AnchorFists", "NoQuarter", "PitStopSabre", "WheelieWrecker", "VictoryLap" }
if args[1] then
	KEYS = string.split(args[1], ",")
end
local AFTER = 0.22 -- (seconds after the cut ends)

-- tweens that really play (the pretend Roblox jumps them to the end)
local tweens = {}
local function easeOf(style, dir, u)
	local st, d = tostring(style or ""), tostring(dir or "")
	local function out(x)
		if string.find(st, "Linear") then
			return x
		elseif string.find(st, "Back") then
			return 1 + 2.70158 * (x - 1) ^ 3 + 1.70158 * (x - 1) ^ 2
		elseif string.find(st, "Sine") then
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
	elseif ta == "Vector3" or ta == "CFrame" or ta == "Color3" then
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
		if tw.inst.Parent ~= nil then
			for key, to in pairs(tw.to) do
				pcall(function()
					tw.inst[key] = lerpAny(tw.from[key], to, k)
				end)
			end
		end
		if u >= 1 then
			table.remove(tweens, i)
		end
	end
end

-- the player: an R6 body standing at (0, 3, 0), facing -Z
local function part(model, name, size, cf)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Parent = model
	return p
end
local function motor(name, parent, p0, p1, c0, c1)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0, m.Part1 = p0, p1
	m.C0, m.C1 = c0, c1
	m.Transform = CFrame.new()
	m.Parent = parent
	return m
end
local char = Instance.new("Model")
char.Name = "Me"
local AT = Vector3.new(0, 3, 0)
local hrp = part(char, "HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(AT))
local torso = part(char, "Torso", Vector3.new(2, 2, 1), CFrame.new(AT))
local arm = part(char, "Right Arm", Vector3.new(1, 2, 1), CFrame.new(AT + Vector3.new(1.5, 0, 0)))
local larm = part(char, "Left Arm", Vector3.new(1, 2, 1), CFrame.new(AT + Vector3.new(-1.5, 0, 0)))
local rleg = part(char, "Right Leg", Vector3.new(1, 2, 1), CFrame.new(AT + Vector3.new(0.5, -2, 0)))
local lleg = part(char, "Left Leg", Vector3.new(1, 2, 1), CFrame.new(AT + Vector3.new(-0.5, -2, 0)))
local head = part(char, "Head", Vector3.new(2, 1, 1), CFrame.new(AT + Vector3.new(0, 1.5, 0)))
local hum = Instance.new("Humanoid")
hum.MaxHealth, hum.Health = 100, 100
hum.MoveDirection = Vector3.new(0, 0, 0)
hum.Parent = char
motor("Right Shoulder", torso, torso, arm, CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
motor("Left Shoulder", torso, torso, larm, CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
motor("Right Hip", torso, torso, rleg, CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
motor("Left Hip", torso, torso, lleg, CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
motor("Neck", torso, torso, head, CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
motor("RootJoint", hrp, hrp, torso, CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
char.Parent = M.workspace
local me = Instance.new("Player")
me.Name = "Me"
me.UserId = 1
me.Parent = Players
Players.LocalPlayer = me
me.Character = char
M.players = { me }
local animator = Instance.new("Animator")
animator.Parent = hum
animator.GetPlayingAnimationTracks = function()
	return {}
end
me:SetAttribute("SpireFloor", 10)

local Info = mount.require(mount.module("ReplicatedStorage/WeaponModelInfo.lua"))
local WeaponFX = mount.require(mount.module("ReplicatedStorage/WeaponFX.lua"))
WeaponFX.start()

local t = 0
local function step(seconds)
	local stop = t + seconds
	while t < stop - 1e-9 do
		t += 1 / 60
		M.run(t)
		stepTweens()
		RunService.Stepped:Fire(t, 1 / 60)
		RunService.Heartbeat:Fire(1 / 60)
	end
end

-- a stand-in for each weapon's imported model (a part per mesh and the
-- markers, as test_voxelhold makes them)
local folder = Instance.new("Folder")
folder.Name = "WeaponModels"
folder.Parent = ReplicatedStorage
local function fakeModel(key)
	local info = Info[key]
	local m = Instance.new("Model")
	m.Name = key
	local i = 0
	for name in pairs(info.Parts) do
		i += 1
		local p = Instance.new("Part")
		p.Name = name
		p.Size = Vector3.new(0.3, 0.2, 0.5)
		p.CFrame = CFrame.new(0.1 * (i % 3) - 0.1, -0.05 * (i % 4), 0.4 * i)
		p.Parent = m
	end
	for name, w in pairs({ GripMark = Vector3.new(0, 0, 0), TipMark = Vector3.new(0, 0, info.Tip), UpMark = Vector3.new(0, -info.Up, 0) }) do
		local p = Instance.new("Part")
		p.Name = name
		p.Size = Vector3.new(0.08, 0.08, 0.08)
		p.CFrame = CFrame.new(w)
		p.Parent = m
	end
	return m
end

local function num(x)
	return string.format("%.3f", x)
end
local function dumpPart(p)
	local c = { p.CFrame:GetComponents() }
	local col = p.Color
	local shape = tostring(p.Shape or "")
	local sh = string.find(shape, "Ball") and "Ball" or string.find(shape, "Cylinder") and "Cylinder" or "Block"
	local cs = {}
	for i = 1, 12 do
		cs[i] = num(c[i])
	end
	realPrint(string.format('{"cf":[%s],"s":[%s,%s,%s],"col":[%d,%d,%d],"t":%s,"m":"%s","sh":"%s","c":"Part"}',
		table.concat(cs, ","), num(p.Size.X), num(p.Size.Y), num(p.Size.Z),
		math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5),
		num(p.Transparency), string.find(tostring(p.Material or ""), "Neon") and "Neon" or "Plastic", sh))
end

for _, key in ipairs(KEYS) do
	local src = fakeModel(key)
	src.Parent = folder
	me:SetAttribute("Weapon", key)
	step(0.3)
	local h = WeaponFX._held[me]
	local fx = h and h.trails and h.trails.fx
	if fx then
		-- the cut: the weapon swept across in front of you, left to right,
		-- the way a flat forehand goes, over 14 frames of real time (only
		-- Heartbeat - what flies - runs meanwhile: the game's own loop, on
		-- Stepped, would end the cut)
		local function at(a)
			return CFrame.new(AT) * CFrame.Angles(0, math.rad(a), 0) * CFrame.new(0, 0.3, -1.6) * CFrame.Angles(math.rad(8), 0, 0)
		end
		fx.part.CFrame = at(80)
		WeaponFX._swingFx(h, true, true)
		for f = 1, 14 do
			fx.part.CFrame = at(80 - f * 160 / 14)
			WeaponFX._swingFx(h, true, false)
			t += 1 / 60
			M.run(t)
			stepTweens()
			RunService.Heartbeat:Fire(1 / 60)
		end
		WeaponFX._swingFx(h, false, false)
		step(AFTER)
	end
	realPrint("SNAP " .. key)
	for _, p in ipairs(char:GetChildren()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			dumpPart(p)
		end
	end
	local goo = M.workspace:FindFirstChild("SwingGoo")
	for _, p in ipairs(goo and goo:GetDescendants() or {}) do
		if p:IsA("BasePart") and p.Transparency < 0.98 and p.Name ~= "SwingSound" then
			dumpPart(p)
		end
	end
	realPrint("END")
	-- (clear it all away before the next)
	step(3)
	if goo then
		goo:ClearAllChildren()
	end
	tweens = {}
	me:SetAttribute("Weapon", nil)
	src:Destroy()
	step(0.2)
end
realPrint("DONE")
