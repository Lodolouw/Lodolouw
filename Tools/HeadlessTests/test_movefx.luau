--!nocheck
-- Headless test of how weapon abilities LOOK (ReplicatedStorage/MoveFX): every
-- launch weapon's move played on your own screen (started when you press it)
-- and on someone else's (started when the server says), the spots the server
-- picks, every building block's moment (stacks, next hit, crit, lifesteal,
-- the specials) and every style's aura - checking that each effect really
-- draws something, nothing errors or warns, and it all cleans itself up.
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Instance, Vector3, CFrame = M.Instance, M.Vector3, M.CFrame
local Players = M.services.Players
local RunService = M.services.RunService
local task = M.task

local fails = 0
local function check(ok, msg)
	if not ok then
		fails += 1
		print("FAIL: " .. msg)
	end
end

-- a floor under everything (the effects sit on it)
M.raycast = function(origin, dir)
	if dir.Y < 0 and origin.Y >= 0 and origin.Y + dir.Y <= 0 then
		return { Position = Vector3.new(origin.X, 0, origin.Z), Normal = Vector3.new(0, 1, 0) }
	end
	return nil
end

local function body(name, at)
	local char = Instance.new("Model")
	char.Name = name
	local function part(n, size, cf)
		local p = Instance.new("Part")
		p.Name = n
		p.Size = size
		p.CFrame = cf
		p.Parent = char
		return p
	end
	part("HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(at))
	part("Torso", Vector3.new(2, 2, 1), CFrame.new(at))
	part("Head", Vector3.new(2, 1, 1), CFrame.new(at + Vector3.new(0, 1.5, 0)))
	part("Right Arm", Vector3.new(1, 2, 1), CFrame.new(at + Vector3.new(1.5, 0, 0)))
	part("Left Arm", Vector3.new(1, 2, 1), CFrame.new(at + Vector3.new(-1.5, 0, 0)))
	part("Right Leg", Vector3.new(1, 2, 1), CFrame.new(at + Vector3.new(0.5, -2, 0)))
	part("Left Leg", Vector3.new(1, 2, 1), CFrame.new(at + Vector3.new(-0.5, -2, 0)))
	local hum = Instance.new("Humanoid")
	hum.Parent = char
	char.Parent = M.workspace
	return char
end

local me = Instance.new("Player")
me.Name = "Me"
me.UserId = 1
me.Parent = Players
Players.LocalPlayer = me
me.Character = body("Me", Vector3.new(0, 3, 0))
local pg = Instance.new("PlayerGui")
pg.Parent = me
local other = Instance.new("Player")
other.Name = "Other"
other.UserId = 2
other.Parent = Players
other.Character = body("Other", Vector3.new(20, 3, 0))
M.players = { me, other }

local Moves = mount.require(mount.module("ReplicatedStorage/Moves.lua"))
local MoveFX = mount.require(mount.module("ReplicatedStorage/MoveFX.lua"))
local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))

local t = 0
local function step(seconds, each)
	local stop = t + seconds
	while t < stop - 1e-9 do
		t += 1 / 60
		M.run(t)
		RunService.Heartbeat:Fire(1 / 60)
		if each then
			each()
		end
	end
end
local function fxCount()
	local f = M.workspace:FindFirstChild("MoveFX")
	return f and #f:GetDescendants() or 0
end

local ids = {}
for _, pack in ipairs(Config.Weapons.Packs) do
	for _, id in ipairs(pack.Weapons) do
		table.insert(ids, id)
	end
end

local warned0 = M.warnings or 0
for _, id in ipairs(ids) do
	local move = Moves.of(id)
	for _, who in ipairs({ me, other }) do
		local own = who == me
		-- every Fx a step names must be a recipe
		for i, s in ipairs(move.Steps) do
			if s.Fx then
				check(MoveFX.RECIPES[id] and MoveFX.RECIPES[id][s.Fx] ~= nil, ("%s: step %d's effect %q is made"):format(id, i, s.Fx))
			end
		end
		if own then
			MoveFX.begin(me, id, 0, true)
		else
			MoveFX.told(other, id, 7, 0) -- (the server: their move started)
		end
		-- the server's word on any spot it picks
		for i, s in ipairs(move.Steps) do
			if s.Pick then
				local at = (who.Character.HumanoidRootPart.Position + Vector3.new(0, 0, -10))
				task.delay((s.At or 0) + 0.05, function()
					MoveFX.told(who, id, own and 3 or 7, i, at)
				end)
			end
		end
		local most = 0
		local last = 0
		for _, s in ipairs(move.Steps) do
			last = math.max(last, s.At or 0)
		end
		step(last + 0.6, function()
			most = math.max(most, fxCount())
		end)
		check(most > 0, id .. ": its effects draw something (" .. (own and "your screen" or "someone else's") .. ")")
		step(8)
	end
end
step(4)
check(fxCount() == 0, "every move's effects clean themselves up (" .. fxCount() .. " left)")

-- the building blocks' moments
for _, name in ipairs({ "Stacks", "NextHit", "Crit", "Lifesteal", "ChopWave", "Clones", "DashHit" }) do
	for _, id in ipairs({ "GooGloves", "ShovelHammer", "EraserHammer", "RelicDaggers", "JungleFang", "NoQuarter", "CopyPasteScythe", "VictoryLap" }) do
		MoveFX.told(me, id, 0, name, Vector3.new(0, 3, -6), Vector3.new(0, 3, 4))
	end
	local most = 0
	step(0.5, function()
		most = math.max(most, fxCount())
	end)
	check(most > 0, "the " .. name .. " moment draws something")
	step(2)
end
step(3)
check(fxCount() == 0, "the moments clean themselves up (" .. fxCount() .. " left)")

-- every style's aura
for name in pairs(MoveFX.STYLES) do
	local most = 0
	me:SetAttribute("SwingN", "1:1")
	step(1, function()
		MoveFX.aura(me, me.Character, name, 1 / 60)
		most = math.max(most, fxCount())
	end)
	check(most > 0, "the " .. name .. " aura gives off bits")
	step(3)
end
step(3)
check(fxCount() == 0, "the auras clean themselves up (" .. fxCount() .. " left)")

check(#M.errors == 0, #M.errors .. " errors")
check((M.warnings or 0) == warned0, ((M.warnings or 0) - warned0) .. " warnings from the effects")

if fails == 0 then
	print("PASS movefx")
else
	print(fails .. " failures")
end
