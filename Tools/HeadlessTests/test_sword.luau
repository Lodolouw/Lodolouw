--!nocheck
-- Headless test of THE TEST SWORD on the server: the real CombatService (its
-- "Weapons" part), with a pretend player standing among punchable targets.
-- It checks fists are still fists, and that the Iron Sword's swings cut
-- every enemy in their arc (and nothing behind), hit harder with mastery,
-- keep their timing and stamina costs, and that the Whirlwind spins,
-- cools down and gets better at each mastery quarter.
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
local SWORD = W.List.IronSword
local SWINGS = W.Types.Sword.Swings

local fails = 0
local function check(ok, msg)
	if not ok then
		fails += 1
		print("FAIL: " .. msg)
	end
end

-- a pretend PlayerService: save data and the dev buttons' actions
local data = { Power = Config.powerForLevel(30) }
local actions = {}
local PlayerService = {
	GetData = function()
		return data
	end,
	AddAction = function(name, fn)
		actions[name] = fn
	end,
}

-- the player, standing at the middle facing -Z
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

-- what the server tells the player's screen
local events = {}
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
remotes.CombatEvent.OnClientEvent = remotes.CombatEvent.OnClientEvent -- (exists)
local origFire = remotes.CombatEvent.FireClient
remotes.CombatEvent.FireClient = function(self, player, kind, ...)
	table.insert(events, { kind = kind, args = { ... }, t = t })
end
local function eventsOf(kind)
	local n = 0
	for _, e in ipairs(events) do
		if e.kind == kind then
			n += 1
		end
	end
	return n
end

-- into an arena (floor 2's level decides how hard things hit)
me:SetAttribute("SpireFloor", 2)
step(0.2)
check(CombatService.IsFighting(me), "the player is fighting")

-- punchable targets: name, where (x, z), health
local targets = {}
local heard = {} -- [target] = what its OnHit was last fired with
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
	targets[name] = m
	-- (what a boss or the Colosseum would hear when it's hit)
	local onHit = Instance.new("BindableEvent")
	onHit.Name = "OnHit"
	onHit.Parent = m
	onHit.Event:Connect(function(...)
		heard[m] = table.pack(...)
	end)
	return m
end
local function lost(m)
	return 1e9 - m:GetAttribute("Health")
end
local function heal(m)
	m:SetAttribute("Health", 1e9)
end
local function healAll()
	for _, m in pairs(targets) do
		heal(m)
	end
end
target("FrontLeft", -4.5, -5) -- in front, off to the left (42 degrees, 6.7 studs away)
target("FrontRight", 4.5, -5) -- in front, off to the right
target("Behind", 0, 6) -- behind you
target("Far", 0, -11.5) -- straight ahead, 11.5 studs (edge at 10.5)
step(0.1)

local punch = CombatService.DamageAgainst(me, targets.FrontLeft) -- one plain punch, for comparison
local function fire(...)
	action.OnServerEvent:Fire(me, ...)
end
local function swingAndWait(n)
	fire("Punch", nil, n)
	step(0.9) -- (well past its lock)
end

----------------------------------------------------------------------
-- Fists: still one enemy per punch
----------------------------------------------------------------------
step(1) -- (the pretend clock starts at 0: a punch "too soon" after nothing)
fire("Punch", nil, 1)
step(0.6)
local hitByFist = 0
for _, m in pairs(targets) do
	if lost(m) > 0 then
		hitByFist += 1
	end
end
check(hitByFist == 1, "fists: a punch hits one enemy (" .. hitByFist .. ")")
check(me:GetAttribute("SwingN") == nil, "fists: no sword swings on anyone's screen")
healAll()

----------------------------------------------------------------------
-- DEV: Test Sword
----------------------------------------------------------------------
check(actions.DevTestWeapon and actions.DevMastery, "the dev buttons' actions are there")
local ok, msg = actions.DevTestWeapon(me, data)
check(ok and me:GetAttribute("Weapon") == "IronSword", "DEV: Test Sword puts the Iron Sword in your hand (" .. tostring(msg) .. ")")
check(me:GetAttribute("Mastery") == 1 and me:GetAttribute("MasteryProgress") == 0, "a fresh sword is mastery 1")

----------------------------------------------------------------------
-- Swings: every enemy in the arc, nothing behind
----------------------------------------------------------------------
step(1)
local hitsBefore = tonumber(string.match(tostring(targets.FrontLeft:GetAttribute("HitFx") or ""), "^(%d+)")) or 0
swingAndWait(1)
check(lost(targets.FrontLeft) > 0 and lost(targets.FrontRight) > 0, "a slash cuts both enemies in front")
check(lost(targets.Behind) == 0, "...but not the one behind you")
check(lost(targets.Far) == 0, "...nor the one out of reach")
check(math.abs(lost(targets.FrontLeft) - math.floor(punch * SWINGS[1].Damage)) <= 1,
	("a slash at mastery 1 hits as hard as a punch (%d vs %d)"):format(lost(targets.FrontLeft), punch))
local sn = me:GetAttribute("SwingN")
check(sn ~= nil and string.match(sn, ":1$"), "everyone's screen is told it's swing 1 (" .. tostring(sn) .. ")")
-- every screen sees each hit land ("HitFx" = "count:weight:x:z": the enemy
-- flashes and flinches away from you), and the enemy's own script hears
-- how hard and which way (the Colosseum knocks its dummies back with it)
local function hitFx(m)
	local n, w, x, z = string.match(tostring(m:GetAttribute("HitFx") or ""), "^(%d+):(%d+):([%-%d%.]+):([%-%d%.]+)$")
	return tonumber(n), tonumber(w), Vector3.new(tonumber(x) or 0, 0, tonumber(z) or 0)
end
local root0 = me.Character.HumanoidRootPart.Position
local n1, w1, d1 = hitFx(targets.FrontLeft)
local away = Vector3.new(-4.5 - root0.X, 0, -5 - root0.Z).Unit
check(n1 == hitsBefore + 1 and w1 == 1, ("a slash that lands shows on the enemy as a light hit (%s)"):format(tostring(targets.FrontLeft:GetAttribute("HitFx"))))
check((d1 - away).Magnitude < 0.05, ("...driving it straight away from you (%.2f, %.2f)"):format(d1.X, d1.Z))
check(targets.Behind:GetAttribute("HitFx") == nil, "...and nothing shows on an enemy it missed")
local h = heard[targets.FrontLeft]
check(h and h[1] == me and h[2] > 0 and h[3] == false and h[4] == 1 and M.typeof(h[5]) == "Vector3" and (h[5] - away).Magnitude < 0.05,
	"the enemy's own script hears who hit it, how hard, the weight and which way")
healAll()

-- the chop (swing 3): 1.5x, reaches a little further, narrower. (The server
-- picks the swing of the string - by the same rule as your screen - so the
-- chop comes by really throwing the string: 1, 2, then 3 in rhythm.)
local function chop()
	step(1.5) -- (any string before this has ended)
	fire("Punch", nil, 1)
	step(SWINGS[1].Lock + 0.02)
	fire("Punch", nil, 2)
	step(SWINGS[2].Lock + 0.02)
	healAll()
	for _, m in pairs(targets) do
		m:SetAttribute("HitFx", nil)
	end
	fire("Punch", nil, 3)
	step(0.9)
end
chop()
check(lost(targets.Far) > 0, "the chop reaches the enemy at 10.5 studs")
check(math.abs(lost(targets.Far) - math.floor(punch * SWINGS[3].Damage)) <= 1,
	("the chop hits 1.5x (%d vs %d)"):format(lost(targets.Far), math.floor(punch * 1.5)))
check(lost(targets.FrontLeft) == 0 and lost(targets.FrontRight) == 0, "the chop's arc is narrow (it misses the ones off to the sides)")
local nF, wF = hitFx(targets.Far)
check(nF == 1 and wF == 3, ("the chop, the finisher, lands as the heaviest hit (%s)"):format(tostring(targets.Far:GetAttribute("HitFx"))))
-- a blow that does nothing (it can't be hurt right now) doesn't make it flinch
targets.Far:SetAttribute("Invulnerable", true)
targets.Far:SetAttribute("HitFx", "1:3:0:0")
local function chopKeepFx()
	step(1.5)
	fire("Punch", nil, 1)
	step(SWINGS[1].Lock + 0.02)
	fire("Punch", nil, 2)
	step(SWINGS[2].Lock + 0.02)
	fire("Punch", nil, 3)
	step(0.9)
end
chopKeepFx()
check(hitFx(targets.Far) == 1, "a hit on an enemy that can't be hurt doesn't make it flinch")
targets.Far:SetAttribute("Invulnerable", nil)
healAll()

-- timing: a second swing too soon is ignored
step(1)
fire("Punch", nil, 1)
step(0.05)
fire("Punch", nil, 2)
step(1)
-- (one slash's worth - a touch over a punch now: the strings above built a
-- little mastery - and nowhere near two)
check(lost(targets.FrontLeft) >= punch * SWINGS[1].Damage - 1 and lost(targets.FrontLeft) < punch * SWINGS[1].Damage * 1.5,
	"a swing thrown too soon after the last is ignored (one hit, not two)")
healAll()

-- stamina: each slash costs 10 of your 100 - twelve in a row (too quick for
-- any to refill) and only ten get through
step(3) -- (full again)
local function swingCount()
	return tonumber(string.match(tostring(me:GetAttribute("SwingN")), "^(%d+):")) or 0
end
local before = swingCount()
for _ = 1, 12 do
	fire("Punch", nil, 1)
	step(0.45)
end
local done = swingCount() - before
-- (quick presses carry the string on - 1, 2, the finisher (dearer, and
-- slower to recover), 1, ... - so the count lands between all-slashes and
-- all-finishers; the point: stamina runs out, nowhere near all 12 get through)
local most = math.floor(Config.Combat.MaxStamina / SWINGS[1].Cost)
local fewest = math.floor(Config.Combat.MaxStamina / SWINGS[3].Cost)
check(done >= fewest - 1 and done <= most,
	("stamina: out of 12 quick slashes only %d to %d get through (%d did)"):format(fewest - 1, most, done))
step(3)

----------------------------------------------------------------------
-- Mastery: every enemy hit counts
----------------------------------------------------------------------
healAll()
step(3)
before = me:GetAttribute("Mastery")
for _ = 1, 8 do
	swingAndWait(1)
end
check(me:GetAttribute("Mastery") > before, ("hitting with it raises its mastery (now %d)"):format(me:GetAttribute("Mastery")))
check(eventsOf("Mastery") >= 1, "the screen hears about the new mastery level")

-- DEV: Mastery +25 goes up a quarter at a time, then back to 1
local seen = {}
for i = 1, 5 do
	local ok2, msg2 = actions.DevMastery(me, data)
	check(ok2, "DEV: Mastery +25 works (" .. tostring(msg2) .. ")")
	seen[i] = me:GetAttribute("Mastery")
end
check(seen[1] == 25 and seen[2] == 50 and seen[3] == 75 and seen[4] == 100 and seen[5] == 1,
	("mastery goes 25, 50, 75, 100, then back to 1 (%s)"):format(table.concat(seen, ", ")))

-- at 100 it hits 1.5x (the Common ceiling)
actions.DevMastery(me, data) -- 25
actions.DevMastery(me, data) -- 50
actions.DevMastery(me, data) -- 75
actions.DevMastery(me, data) -- 100
healAll()
step(3)
swingAndWait(1)
check(math.abs(lost(targets.FrontLeft) - math.floor(punch * 1.5)) <= 1,
	("at mastery 100 a slash hits 1.5x (%d vs %d)"):format(lost(targets.FrontLeft), math.floor(punch * 1.5)))
actions.DevMastery(me, data) -- back to 1

----------------------------------------------------------------------
-- The Whirlwind
----------------------------------------------------------------------
-- the Iron Sword is the starter: no ability, F does nothing
healAll()
step(3)
fire("Ability")
step(1.5)
check(SWORD.Ability == nil and lost(targets.Behind) == 0 and lost(targets.FrontLeft) == 0, "the Iron Sword (the starter) has no ability: F does nothing")
-- the other swords spin the Whirlwind
local SPIN = W.List.EmberCleaver
CombatService.Equip(me, "EmberCleaver")
local function spin()
	healAll()
	step(3)
	fire("Ability")
	step(1.5)
end
local tier1 = SPIN.Ability.Tiers[1]
events = {}
spin()
check(lost(targets.FrontLeft) > 0 and lost(targets.FrontRight) > 0 and lost(targets.Behind) > 0,
	"the Whirlwind cuts all round you, even behind")
check(lost(targets.Far) == 0, "...but not far away (it's close range)")
check(math.abs(lost(targets.Behind) - math.floor(punch * Config.weaponMultiplier(SPIN, 1) * tier1.Damage)) <= 1,
	("tier 1: one spin at 1.6x (%d vs %d)"):format(lost(targets.Behind), math.floor(punch * Config.weaponMultiplier(SPIN, 1) * tier1.Damage)))
check(eventsOf("Ability") == 1, "the screen is told the cooldown")
local an = me:GetAttribute("AbilityN")
check(an ~= nil and string.match(an, ":1$"), "everyone's screen is told to spin it (tier 1)")

-- the cooldown: again straight away is refused
healAll()
fire("Ability")
step(1)
check(lost(targets.Behind) == 0, "the Whirlwind can't be used again straight away")
check(eventsOf("Denied") >= 1, "...and the screen is told no")
step(SPIN.Ability.Cooldown)

-- mastery 50: two spins (each enemy cut twice)
actions.DevMastery(me, data) -- 25
actions.DevMastery(me, data) -- 50
step(SPIN.Ability.Cooldown)
spin()
local tier3 = SPIN.Ability.Tiers[3]
local mult50 = Config.weaponMultiplier(SPIN, 50)
check(math.abs(lost(targets.Behind) - 2 * math.floor(punch * mult50 * tier3.Damage)) <= 2,
	("mastery 50: two spins (%d vs %d)"):format(lost(targets.Behind), 2 * math.floor(punch * mult50 * tier3.Damage)))

-- no swinging mid-spin
step(SPIN.Ability.Cooldown)
healAll()
step(3)
fire("Ability")
step(0.1)
local mid = lost(targets.FrontLeft)
fire("Punch", nil, 1)
step(1.5)
local spinOnly = 2 * math.floor(punch * mult50 * tier3.Damage)
check(math.abs(lost(targets.FrontLeft) - spinOnly) <= 2, "a swing thrown mid-spin is ignored")
local _ = mid

-- mastery 75: the shockwave reaches the far one
actions.DevMastery(me, data) -- 75
step(SPIN.Ability.Cooldown)
spin()
check(lost(targets.Far) > 0, "mastery 75: the last spin's shockwave reaches further out")
-- mastery 100: three spins
actions.DevMastery(me, data) -- 100
step(SPIN.Ability.Cooldown)
spin()
local tier5 = SPIN.Ability.Tiers[5]
check(math.abs(lost(targets.Behind) - 3 * math.floor(punch * Config.weaponMultiplier(SPIN, 100) * tier5.Damage)) <= 3,
	("mastery 100: three spins (%d vs %d)"):format(lost(targets.Behind), 3 * math.floor(punch * Config.weaponMultiplier(SPIN, 100) * tier5.Damage)))
actions.DevMastery(me, data) -- (back to 1)
CombatService.Equip(me, "IronSword")

----------------------------------------------------------------------
-- Leaving mid-swing, and back to fists
----------------------------------------------------------------------
healAll()
step(3)
fire("Punch", nil, 1)
me:SetAttribute("SpireFloor", nil)
step(1)
check(lost(targets.FrontLeft) == 0, "leaving the arena mid-swing: it doesn't land")
check(not CombatService.IsFighting(me), "out of the fight")
me:SetAttribute("SpireFloor", 2)
step(0.5)
local ok3 = actions.DevTestWeapon(me, data)
check(ok3 and me:GetAttribute("Weapon") == nil and me:GetAttribute("Mastery") == nil, "DEV: Test Sword again: back to fists")
-- DEV: Next Sword: every sword in turn, then fists
do
	local seen = {}
	for i = 1, 5 do
		local fine, say = actions.DevNextWeapon(me, data)
		seen[i] = fine and (me:GetAttribute("Weapon") or "fists") or ("failed: " .. tostring(say))
	end
	local got = table.concat(seen, ",")
	check(got == "IronSword,EmberCleaver,Tidefang,Voidstar,fists", "DEV: Next Sword goes through every sword, then fists (" .. got .. ")")
end
healAll()
step(1)
fire("Punch", nil, 1)
step(0.6)
local n = 0
for _, m in pairs(targets) do
	if lost(m) > 0 then
		n += 1
	end
end
check(n == 1, "fists again: one enemy per punch (" .. n .. ")")
-- the Ability button does nothing with fists
healAll()
fire("Ability")
step(1)
check(lost(targets.Behind) == 0, "no weapon, no ability")

-- a bad swing number or a bad weapon id can't break anything
CombatService.Equip(me, "IronSword")
fire("Punch", nil, 99)
fire("Punch", nil, 0 / 0)
fire("Punch", "not an instance", -5)
step(1)
check(CombatService.Equip(me, "NoSuchWeapon") == false, "a weapon that doesn't exist can't be held")
if #M.errors > 0 then
	fails += 1
	print("FAIL: " .. #M.errors .. " script errors")
	for i = 1, math.min(3, #M.errors) do
		print(M.errors[i])
	end
end
if fails == 0 then
	print("PASS sword")
else
	print(fails .. " failures")
end
