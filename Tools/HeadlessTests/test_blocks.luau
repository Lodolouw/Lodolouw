--!nocheck
-- Headless test of ABILITY BUILDING BLOCKS on the server (CombatService,
-- "Ability building blocks"), with a pretend player standing among punchable
-- targets. It checks using an ability tells every screen and turns its aura
-- on; DamageUp and Lifesteal work and wear off; the cooldown; Shield eats the
-- first hit, Guard halves the next; a Burst hits round you; NextHit's Mark;
-- Stacks burst every third hit; and leaving the fight clears it all.
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Instance, Vector3, CFrame = M.Instance, M.Vector3, M.CFrame
local Players = M.services.Players
local RunService = M.services.RunService
local CollectionService = M.services.CollectionService
local task = M.task

RunService.IsStudio = function()
	return true -- (the dev buttons are for Studio)
end

local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local CombatService = mount.require(mount.module("ServerScriptService/CombatService.lua"))
local W = Config.Weapons

local fails = 0
local function check(ok, msg)
	if not ok then
		fails += 1
		print("FAIL: " .. msg)
	end
end

-- two made-up test weapons (swords, so they swing like the Iron Sword)
local RED = M.Color3.fromRGB(255, 60, 60)
W.List.TestFury = {
	Name = "Test Fury", Type = "Sword", Rarity = "Common",
	Ability = { Name = "Fury", Cooldown = 10, Cost = 10, Aura = RED, Effects = {
		{ Block = "DamageUp", Amount = 0.5, Time = 4 },
		{ Block = "Lifesteal", Amount = 0.05, Time = 4 },
		{ Block = "StaminaOnHit", Amount = 5, Time = 4 },
	} },
}
W.List.TestGuard = {
	Name = "Test Guard", Type = "Sword", Rarity = "Common",
	Passive = { { Block = "Stacks", Max = 3, Amount = 1.0 } },
	Ability = { Name = "Guard", Cooldown = 10, Cost = 10, Effects = {
		{ Block = "Shield", Time = 5 },
		{ Block = "Guard", Amount = 0.5, Time = 5 },
		{ Block = "NextHit", Amount = 1.0, Time = 5, Mark = 0.25, MarkTime = 3 },
		{ Block = "StaminaRefill", Amount = 1 },
	}, Burst = { Radius = 9, Damage = 1.0, Delay = 0.1 } },
}

local data = { Power = Config.powerForLevel(30), Stats = {}, Items = {}, Gear = {}, Weapons = { own = {}, hold = nil } }
local PlayerService = {
	GetData = function()
		return data
	end,
	AddAction = function() end,
	MarkDirty = function() end,
}

local me = Instance.new("Player")
me.Name = "Tester"
me.UserId = 1001
me.Parent = Players
M.players = { me }
local char = Instance.new("Model")
char.Name = "Tester"
local hrp = Instance.new("Part")
hrp.Name = "HumanoidRootPart"
hrp.Size = Vector3.new(2, 2, 1)
hrp.CFrame = CFrame.new(0, 3, 0)
hrp.Parent = char
local hum = Instance.new("Humanoid")
hum.MaxHealth = 100
hum.Health = 100
hum.WalkSpeed = 16
hum.Parent = char
char.Parent = M.workspace
me.Character = char

local t = 0
local function step(seconds)
	local stop = t + seconds
	while t < stop - 1e-9 do
		t += 1 / 60
		M.run(t)
		RunService.Heartbeat:Fire(1 / 60)
	end
end

CombatService.Start(PlayerService)
local remotes = M.services.ReplicatedStorage:FindFirstChild("CombatRemotes")
local action = remotes.CombatAction
local events = {}
remotes.CombatEvent.FireClient = function(self, player, kind, ...)
	table.insert(events, { kind = kind, args = { ... } })
end
me:SetAttribute("SpireFloor", 2)
step(0.2)

local function target(name, x, z)
	local m = Instance.new("Model")
	m.Name = name
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2, 4, 2)
	body.CFrame = CFrame.new(x, 3, z)
	body.Parent = m
	m.PrimaryPart = body
	m:SetAttribute("MaxHealth", 1e9)
	m:SetAttribute("Health", 1e9)
	m:SetAttribute("HitRadius", 1)
	m:SetAttribute("NoBar", true)
	m.Parent = M.workspace
	CollectionService:AddTag(m, "CombatTarget")
	return m
end
local dummy = target("Dummy", 0, -5)
step(0.1)
local function lost()
	local l = 1e9 - dummy:GetAttribute("Health")
	dummy:SetAttribute("Health", 1e9)
	return l
end
local function fire(...)
	action.OnServerEvent:Fire(me, ...)
end
local function swing()
	fire("Punch", nil, 1)
	step(0.9)
	return lost()
end
step(1)

----------------------------------------------------------------------
-- Fury: +50% damage, lifesteal, stamina back on hits, an aura
----------------------------------------------------------------------
CombatService.Equip(me, "TestFury")
local plain = swing()
check(plain > 0, "a plain swing hits (" .. plain .. ")")
hum.Health = 50
fire("Ability")
step(0.4)
check(me:GetAttribute("PowerN") ~= nil, "using it tells every screen (PowerN)")
check(me:GetAttribute("Aura") ~= nil and me:GetAttribute("AuraUntil") > M.workspace:GetServerTimeNow(), "the aura is on")
local boosted = swing()
local ratio = boosted / plain
check(ratio > 1.4 and ratio < 1.6, "DamageUp: the swing does +50% (x" .. string.format("%.2f", ratio) .. ")")
check(hum.Health > 50, "Lifesteal: the hit healed you (" .. hum.Health .. ")")
step(4)
local after = swing()
check(math.abs(after / plain - 1) < 0.05, "after 4 s it's worn off (x" .. string.format("%.2f", after / plain) .. ")")
fire("Ability")
step(0.4)
local deniedBefore = 0
for _, e in ipairs(events) do
	if e.kind == "Denied" then
		deniedBefore += 1
	end
end
check(deniedBefore >= 1, "it has a cooldown")

----------------------------------------------------------------------
-- Guard: a one-hit shield, a guard, a marking next hit, a burst, stacks
----------------------------------------------------------------------
step(10)
CombatService.Equip(me, "TestGuard")
step(0.1)
lost()
fire("Ability")
step(0.1)
check(me:GetAttribute("Shield") == true, "the shield is up")
step(0.2)
local burstHit = lost()
check(burstHit > 0, "the Burst hit the dummy round you (" .. burstHit .. ")")
hum.Health = 100
local ok = CombatService.DamagePlayer(me, 30, Vector3.new(0, 3, -5), 0)
check(not ok and hum.Health == 100, "Shield: the first hit does nothing")
check(me:GetAttribute("Shield") == nil, "and breaks it")
CombatService.DamagePlayer(me, 30, Vector3.new(0, 3, -5), 0)
check(math.abs(hum.Health - 85) < 1, "Guard: the next hit does half (" .. hum.Health .. ")")
-- (the burst already used the NextHit and marked the dummy)
check((dummy:GetAttribute("MarkedUntil") or 0) > M.workspace:GetServerTimeNow(), "NextHit's Mark: the dummy is marked")
-- stacks: Max 3, so the 3rd hit bursts for +100%
CombatService.Equip(me, "TestFury") -- (clear the stack count by swapping... stacks live on the fighter)
CombatService.Equip(me, "TestGuard")
step(4) -- (the mark wears off)
local s1 = swing()
local s2 = swing()
local s3 = swing()
check(me:GetAttribute("Stacks") ~= nil, "Stacks show on screen")
local lo = math.min(s1, s2)
check(math.max(s1, s2, s3) / lo > 1.8, "Stacks: one of every 3 hits bursts for double (" .. s1 .. ", " .. s2 .. ", " .. s3 .. ")")

-- leaving the fight clears it all
me:SetAttribute("SpireFloor", nil)
step(0.2)
check(me:GetAttribute("Aura") == nil and me:GetAttribute("Stacks") == nil and me:GetAttribute("Shield") == nil, "leaving the fight clears the effects")

if fails == 0 then
	print("PASS blocks")
else
	print(fails .. " failures")
end
