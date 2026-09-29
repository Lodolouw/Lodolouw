--!nocheck
-- Headless test of OWNING WEAPONS (the server side): equipping only what you
-- own, the weapon in your hand and every weapon's mastery kept in the save
-- (data.Weapons), and the held weapon going back in your hand when you join.
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Instance, Vector3, CFrame = M.Instance, M.Vector3, M.CFrame
local Players = M.services.Players
local RunService = M.services.RunService

RunService.IsStudio = function()
	return true
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

-- a saved player who owns the Iron Sword (mastery 3's worth) and was holding it
local startPoints = Config.masteryPointsFor(3)
local data = {
	Power = Config.powerForLevel(30), Stats = {}, Items = {}, Gear = {},
	Weapons = { own = { IronSword = startPoints }, hold = "IronSword" },
}
local actions, dirty = {}, 0
local PlayerService = {
	GetData = function()
		return data
	end,
	AddAction = function(name, fn)
		actions[name] = fn
	end,
	MarkDirty = function()
		dirty += 1
	end,
}

local me = Instance.new("Player")
me.Name = "Tester"
me.UserId = 1001
me.Parent = Players
M.players = { me }

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
step(1)

-- joining: the held weapon is back in your hand, at its saved mastery
check(me:GetAttribute("Weapon") == "IronSword", "the held weapon goes back in your hand on join")
check(me:GetAttribute("Mastery") == 3, "its saved mastery shows (got " .. tostring(me:GetAttribute("Mastery")) .. ")")

-- equipping
check(actions.EquipWeapon ~= nil, "there's an EquipWeapon action")
local ok = actions.EquipWeapon(me, data, nil)
check(ok and me:GetAttribute("Weapon") == nil and data.Weapons.hold == nil, "nil puts the weapon away (fists), and that's saved")
ok = actions.EquipWeapon(me, data, "Voidstar")
check(not ok and me:GetAttribute("Weapon") == nil, "you can't equip a weapon you don't own")
ok = actions.EquipWeapon(me, data, "NoSuchThing")
check(not ok, "or one that doesn't exist")
ok = actions.EquipWeapon(me, data, 42)
check(not ok, "or a number")
ok = actions.EquipWeapon(me, data, "IronSword")
check(ok and me:GetAttribute("Weapon") == "IronSword" and data.Weapons.hold == "IronSword", "equipping one you own works, and is saved")

-- mastery goes into the save (DEV: Mastery +25 uses the same path as hits)
local before = dirty
actions.DevMastery(me, data)
check(data.Weapons.own.IronSword == Config.masteryPointsFor(25), "mastery is written into the save (got " .. tostring(data.Weapons.own.IronSword) .. ")")
check(dirty > before, "and the player's screen is told")

-- a dev test weapon you don't own: mastery for this session only, never saved as held
actions.DevNextWeapon(me, data) -- IronSword -> EmberCleaver
check(me:GetAttribute("Weapon") == "EmberCleaver", "the dev button can still hold a test sword")
check(data.Weapons.hold == "IronSword", "an unowned test sword isn't saved as held")
actions.DevMastery(me, data)
check(data.Weapons.own.EmberCleaver == nil, "and its mastery isn't saved as owning it")

if fails == 0 then
	print("PASS weapon save")
else
	print(fails .. " failures")
end
