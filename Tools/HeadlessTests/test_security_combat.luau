--!nocheck
-- Headless SECURITY test of combat, run like an exploiter would: the real
-- CombatService with a pretend player, sending what a modified client can.
--   * the swing of the string is the server's choice: asking for the
--     strongest swing every time gets swing 1
--   * swings can't come faster than each swing's own lock
--   * a hit only lands from where you could really have got to: standing far
--     off and blinking in for the instant the punch lands hits nothing
--   * a Spire boss in another copy of the arena can't be hit
--   * a hit that does no damage (an untouchable boss) earns no mastery
--   * spamming the remote is simply ignored past its budget
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


PlayerService.MarkDirty = function() end
step(1)
-- hold the Iron Sword (owned) through the real EquipWeapon action
data.Weapons = data.Weapons or { own = {} }
data.Weapons.own.IronSword = data.Weapons.own.IronSword or 0
if actions.EquipWeapon then
	actions.EquipWeapon(me, data, "IronSword")
end
step(0.3)
check(me:GetAttribute("Weapon") == "IronSword", "holding the Iron Sword")

----------------------------------------------------------------------
-- 1. The swing of the string is the server's
----------------------------------------------------------------------
do
	healAll()
	step(1.5) -- (the string has long ended)
	fire("Punch", nil, #SWINGS) -- asks for the finisher
	step(0.9)
	local n = tonumber(string.match(tostring(me:GetAttribute("SwingN") or ""), ":(%d+)$"))
	check(n == 1, "asking for the finisher after a pause gets swing 1 (" .. tostring(n) .. ")")
	-- spam swings far faster than the lock allows
	local before = tonumber(string.match(tostring(me:GetAttribute("SwingN") or ""), "^(%d+)")) or 0
	for _ = 1, 10 do
		fire("Punch", nil, 3)
		step(0.05)
	end
	local after = tonumber(string.match(tostring(me:GetAttribute("SwingN") or ""), "^(%d+)")) or 0
	local fastest = SWINGS[1].Lock
	for _, s in ipairs(SWINGS) do
		fastest = math.min(fastest, s.Lock)
	end
	local allowed = math.floor(0.5 / (fastest - 0.08)) + 1
	check(after - before <= allowed, "10 swings in half a second: only " .. allowed .. " at most go through (" .. (after - before) .. ")")
end

----------------------------------------------------------------------
-- 2. Blinking in for the hit
----------------------------------------------------------------------
do
	healAll()
	step(1.5)
	-- stand 40 studs away for a while, then blink right next to them as the swing lands
	hrp.CFrame = CFrame.new(0, 3, 40)
	step(1)
	fire("Punch", nil, 1)
	step(SWINGS[1].Lock * SWINGS[1].Contact - 0.04)
	hrp.CFrame = CFrame.new(0, 3, 0)
	step(0.2)
	hrp.CFrame = CFrame.new(0, 3, 40)
	check(lost(targets.FrontLeft) == 0 and lost(targets.FrontRight) == 0, "blinking in for the instant of the hit lands nothing")
	-- walking up the honest way does
	healAll()
	hrp.CFrame = CFrame.new(0, 3, 0)
	step(1.5)
	fire("Punch", nil, 1)
	step(0.9)
	check(lost(targets.FrontLeft) > 0 or lost(targets.FrontRight) > 0, "standing there for real, the swing lands")
end

----------------------------------------------------------------------
-- 3. Another copy's boss
----------------------------------------------------------------------
do
	healAll()
	me:SetAttribute("SpireArena", "copy-A")
	targets.FrontLeft:SetAttribute("ArenaId", "copy-B")
	targets.FrontRight:SetAttribute("ArenaId", "copy-A")
	step(1.5)
	fire("Punch", nil, 1)
	step(0.9)
	check(lost(targets.FrontLeft) == 0, "a boss in another copy of the arena can't be hit")
	check(lost(targets.FrontRight) > 0, "your own copy's can")
	targets.FrontLeft:SetAttribute("ArenaId", nil)
	targets.FrontRight:SetAttribute("ArenaId", nil)
end

----------------------------------------------------------------------
-- 4. No damage, no mastery
----------------------------------------------------------------------
do
	healAll()
	for _, m in pairs(targets) do
		m:SetAttribute("Invulnerable", true)
	end
	local before = data.Weapons.own.IronSword or 0
	step(1.5)
	for _ = 1, 4 do
		fire("Punch", nil, 1)
		step(1.0)
	end
	step(1)
	check((data.Weapons.own.IronSword or 0) == before, "swinging at an untouchable boss earns no mastery (" .. tostring(data.Weapons.own.IronSword) .. " vs " .. before .. ")")
	for _, m in pairs(targets) do
		m:SetAttribute("Invulnerable", nil)
	end
end

----------------------------------------------------------------------
-- 5. Spam
----------------------------------------------------------------------
do
	local n = #events
	for _ = 1, 500 do
		fire("Roll")
	end
	step(0.1)
	local denied = 0
	for i = n + 1, #events do
		denied += 1
	end
	check(denied <= 60, "500 rolls in a frame: the rest are ignored, not answered (" .. denied .. " replies)")
end

for _, e in ipairs(M.errors) do
	print("ERROR " .. tostring(e))
end
if fails == 0 then
	print("PASS  test_security_combat: server-picked swings, swing rate, blink-in hits, arena copies, no-damage mastery, spam")
else
	print("FAILED: " .. fails)
end
