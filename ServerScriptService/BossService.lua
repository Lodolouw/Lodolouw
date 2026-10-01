--[[
	BossService  (ModuleScript, parent: ServerScriptService, name: "BossService")

	The bosses of the Spire. The server decides everything that matters here -
	where the boss is, what it does, when an attack lands and who it hits - and
	publishes it as attributes on the boss model. Every player's BossClient
	draws the body and the warnings from those same attributes, stamped with the
	server's clock, so what you see coming is exactly what hits you.

	An encounter's life:
	    Dormant    sunk in the pit. Walk within WakeRange (or hit it) and it rises.
	    Waking     rising out of the pool. Can't be hurt.
	    Fighting   the fight. Picks a target, chooses an attack by distance, recovers.
	    Transition the shell breaking at half health. Can't be hurt.
	    Resetting  everyone in the arena died or left: it sinks back and heals.
	    Dead       killed. Rewards are paid; it returns once the arena is empty.

	EACH BOSS HAS ITS OWN FILE in ServerScriptService/Bosses, named after its
	short name in Config.Bosses (Oozark.lua, Tuber.lua...). This file is what
	every boss shares: the life above, picking targets, publishing actions,
	timing, hitting players, the surface-boss brain (choose an attack that
	suits the distance, do it, breathe), moving and turning, shock rings and
	burning puddles, the phase change, rewards. A boss file adds its attacks,
	and can replace or add to the shared parts through hooks:
	    Oozark (the slime) fights on the surface: it only adds its attacks.
	    Tuber (the cactus) brings its own brain - two whole fights, one per
	        health bar - its own every-frame step, and extras for building,
	        resetting, dying and the phase change (so do Kaze, Revvington
	        and Gridlock; Burrowmore uses the shared brain with his own attacks).
	To add a boss: copy Bosses/_Template.lua (and ReplicatedStorage/BossBodies/
	_Template.lua for its body), give it a Config.Bosses entry and an arena.

	ONE FIGHT PER ARENA COPY. Everyone going up a floor gets a copy of its
	arena of their own (ArenaPool), and every copy has its own encounter here:
	built when the copy appears (its "BossHome" part), taken down when it goes.
	Who's in a fight is who's in that copy (the player's SpireArena attribute
	matches the copy's ArenaId) - the targets, the hits, the health it wakes
	with for a party, the reset when they're gone, the rewards. With no copies
	in play (no ArenaPool: the tests) it's one fight per floor, as it was.

	Attributes on the boss model, for BossClient:
	    State, Phase, Health, MaxHealth, Moving
	    Action, ActionId, ActionStart (server time), ActA/ActB/ActC (positions),
	    ActN (a number), ActK (how many of the ActA..C slots are filled so far)
	    (and whatever each boss's own file adds: see the top of each)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local BossService = {}

local CombatService = nil
local PlayerService = nil
local BossEvent = nil
local encounters = {} -- [BossHome part] = encounter (one per arena copy)
local primary = {} -- [floorId] = the encounter in the floor's first arena
local running = {} -- every encounter, in the order built (each frame steps them in this order)

local STAND_HEIGHT = 3 -- a standing character's root is about this far off the floor
local PLAYER_RADIUS = 1.5 -- how wide a character is, for hits
-- positions an action publishes as it goes (globs, rings, hops): room for a barrage
-- Each boss's own file (ServerScriptService/Bosses/<its short name>): its
-- attacks, and the hooks that change how it fights. Loaded once, here; one
-- that's missing or broken is reported in the Output and only that boss is
-- left out - the others still work.
local bossModules = {} -- [short name] = the boss's module, or false
for _, def in pairs(Config.Bosses or {}) do
	local folder = script.Parent:FindFirstChild("Bosses")
	local file = folder and folder:FindFirstChild(def.Short)
	local ok, result = false, "no file named " .. tostring(def.Short) .. " in ServerScriptService > Bosses"
	if file then
		ok, result = pcall(require, file)
	end
	if ok and type(result) == "table" then
		bossModules[def.Short] = result
	else
		bossModules[def.Short] = false
		warn("[BossService] " .. tostring(def.Short) .. " is left out: " .. tostring(result))
	end
end
local function bossModule(def)
	return bossModules[def.Short] or nil
end

local SLOTS = { "ActA", "ActB", "ActC", "Act4", "Act5", "Act6", "Act7", "Act8", "Act9", "Act10", "Act11", "Act12", "Act13", "Act14", "Act15", "Act16", "Act17", "Act18", "Act19", "Act20", "Act21", "Act22", "Act23", "Act24" }

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local function now()
	return Workspace:GetServerTimeNow()
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDistance(a, b)
	return flat(a - b).Magnitude
end

local function unitOr(v, fallback)
	return v.Magnitude > 0.01 and v.Unit or fallback
end

local function rootOf(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if hum and root and hum.Health > 0 then
		return root
	end
	return nil
end

-- turns `current` toward `want` (both flat unit vectors) by at most `maxRadians`
local function turnToward(current, want, maxRadians)
	local a = math.atan2(current.X, current.Z)
	local b = math.atan2(want.X, want.Z)
	local diff = (b - a + math.pi) % (2 * math.pi) - math.pi
	local turned = a + math.clamp(diff, -maxRadians, maxRadians)
	return Vector3.new(math.sin(turned), 0, math.cos(turned))
end

local function floorInfo(floorId)
	for _, f in ipairs(Config.Spire.Floors) do
		if f.id == floorId then
			return f
		end
	end
	return nil
end

-- Is this player in this encounter's arena copy? (No copy given - no
-- ArenaPool, as in the tests - means the floor's first arena.)
local function inArena(E, p)
	local id = p:GetAttribute("SpireArena")
	if id == nil or E.arenaId == nil then
		return primary[E.floor] == E
	end
	return id == E.arenaId
end

-- the players fighting in this arena right now, alive
local function fightersIn(E)
	local list = {}
	for _, p in ipairs(CombatService.PlayersInArena(E.floor)) do
		if inArena(E, p) and CombatService.IsFighting(p) and rootOf(p) then
			list[#list + 1] = p
		end
	end
	return list
end

-- everyone standing in this arena, alive or not
local function presentIn(E)
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("SpireFloor") == E.floor and inArena(E, p) then
			list[#list + 1] = p
		end
	end
	return list
end

-- The arena model a part belongs to (the top-level model in Workspace).
local function arenaRoot(inst)
	local a = inst
	while a and a.Parent and a.Parent ~= Workspace do
		a = a.Parent
	end
	return (a and a.Parent == Workspace) and a or nil
end

-- Is this part of the world built in this encounter's arena copy? (For a
-- boss looking up its arena's pillars, rocks, thrones: never another copy's.)
local function inArenaModel(E, inst)
	return E.arena == nil or (inst ~= nil and inst:IsDescendantOf(E.arena))
end

-- This encounter's arena model, if it carries `attr` - or, failing that, the
-- last model on its floor that does (the old way, before copies).
local function arenaWith(E, attr)
	if E.arena and E.arena:GetAttribute(attr) ~= nil then
		return E.arena
	end
	local found = nil
	for _, c in ipairs(Workspace:GetChildren()) do
		if c:IsA("Model") and c:GetAttribute("Floor") == E.floor and c:GetAttribute(attr) ~= nil and not c:GetAttribute("Boss") then
			found = c
		end
	end
	return found
end

-- A folder in Workspace for this encounter's props (TuberProps...): one per
-- arena copy (its ArenaId on it, for the screens), made the first time it's
-- asked for, and taken away with the encounter.
local function propFolder(E, name)
	E.folders = E.folders or {}
	local f = E.folders[name]
	if f and f.Parent then
		return f
	end
	f = Instance.new("Folder")
	f.Name = name
	if E.arenaId then
		f:SetAttribute("ArenaId", E.arenaId)
	end
	f.Parent = Workspace
	E.folders[name] = f
	return f
end

----------------------------------------------------------------------
-- Publishing what the boss is doing
----------------------------------------------------------------------
local function setState(E, state)
	E.state = state
	E.model:SetAttribute("State", state)
end

-- Starts a new action. Returns its start time (server clock) - everything in
-- the action is timed from that one moment, on the server and on every screen.
local function setAction(E, name, number)
	E.actionId = E.actionId + 1
	local m = E.model
	for _, key in ipairs(SLOTS) do
		m:SetAttribute(key, nil)
	end
	m:SetAttribute("ActK", 0)
	m:SetAttribute("ActN", number)
	m:SetAttribute("Action", name)
	local t0 = now()
	m:SetAttribute("ActionStart", t0)
	m:SetAttribute("ActionId", E.actionId) -- last, so the rest is in place when clients see it
	return t0
end

-- Fills the next position slot of the current action (a glob's landing spot,
-- a ring under someone's feet...). Clients draw each one as it arrives.
local function setSlot(E, index, position)
	E.model:SetAttribute(SLOTS[index], position)
	E.model:SetAttribute("ActK", index)
end

local function setMoving(E, moving)
	if E.moving ~= moving then
		E.moving = moving
		E.model:SetAttribute("Moving", moving)
	end
end

local function place(E)
	local center = E.pos + Vector3.new(0, E.height / 2, 0)
	E.root.CFrame = CFrame.lookAt(center, center + E.facing)
end

----------------------------------------------------------------------
-- Timing: every wait checks the encounter wasn't reset or killed meanwhile
----------------------------------------------------------------------
local function valid(E, token)
	return E.token == token
end

local function waitUntil(E, token, t)
	while now() < t do
		if not valid(E, token) then
			return false
		end
		task.wait()
	end
	return valid(E, token)
end

----------------------------------------------------------------------
-- Stone: nothing that comes up out of the ground can come up through it.
-- (An arena marks its stone platforms with the "DunePlatform" tag. None
-- does at the moment - a floor with none is unaffected.)
----------------------------------------------------------------------
local function findStones(floorId, arena)
	local list = {}
	for _, pm in ipairs(CollectionService:GetTagged("DunePlatform")) do
		if pm:GetAttribute("Floor") == floorId and (arena == nil or pm:IsDescendantOf(arena)) then
			local slab = pm:FindFirstChild("PlatformSlab")
			local center = slab and slab.Position
			if not center then
				local ok, cf = pcall(function()
					return pm:GetPivot()
				end)
				center = ok and cf and cf.Position or nil
			end
			if center then
				list[#list + 1] = { center = center, radius = pm:GetAttribute("Radius") or 10, model = pm }
			end
		end
	end
	return list
end

-- the stone platform a spot is on, if it's on one (a shattered one is just sand)
local function stoneUnder(E, pos)
	for _, st in ipairs(E.stones or {}) do
		if not st.broken and flatDistance(pos, st.center) <= st.radius then
			return st
		end
	end
	return nil
end

-- the nearest sand beside a stone, `extra` studs out from its edge, on the side
-- toward `toward`
local function besideStone(E, st, pos, toward, extra)
	local out = flat(pos - st.center)
	if out.Magnitude < 0.5 then
		out = flat(toward - st.center)
	end
	out = unitOr(out, Vector3.new(0, 0, 1))
	local spot = st.center + out * (st.radius + extra)
	return Vector3.new(spot.X, E.floorY, spot.Z)
end

----------------------------------------------------------------------
-- Hitting players
----------------------------------------------------------------------
local function knockbackFrom(center, root, strength, lift)
	local away = unitOr(flat(root.Position - center), Vector3.new(0, 0, 1))
	return away * strength + Vector3.new(0, lift or strength * 0.35, 0)
end

-- Everyone within `radius` of `center` (on the ground plane) takes the hit
-- once. Returns how many it landed on. fromBelow = it comes up out of the
-- ground, so anyone standing on stone is out of its reach.
local function hitArea(E, center, radius, damage, knockback, already, fromBelow)
	local landed = 0
	for _, p in ipairs(fightersIn(E)) do
		if not (already and already[p]) then
			local root = rootOf(p)
			if root and flatDistance(root.Position, center) <= radius + PLAYER_RADIUS
				and not (fromBelow and stoneUnder(E, root.Position)) then
				if already then
					already[p] = true
				end
				if CombatService.DamagePlayer(p, damage, center, knockbackFrom(center, root, knockback or 0)) then
					landed = landed + 1
				end
			end
		end
	end
	return landed
end

----------------------------------------------------------------------
-- Health, phases, recovery
----------------------------------------------------------------------
local function healthShare(E)
	local max = E.model:GetAttribute("MaxHealth") or 1
	return (E.model:GetAttribute("Health") or 0) / math.max(max, 1)
end

-- how long this recovery really lasts: faster in phase two, faster again when desperate
-- (and quicker on a harder Spire: its tier's pace)
local function recovery(E, seconds)
	local def = E.def
	local pace = E.pace or 1
	if E.phase >= 2 then
		if healthShare(E) <= def.DesperateAt then
			return seconds * def.DesperateRecovery * pace
		end
		return seconds * def.Phase2Recovery * pace
	end
	return seconds * pace
end

----------------------------------------------------------------------
-- Choosing who to fight and what to do
----------------------------------------------------------------------
local function pickTarget(E)
	local list = fightersIn(E)
	if #list == 0 then
		return nil
	end
	-- stick with the current target a while, so it commits to someone
	if E.target and table.find(list, E.target) and now() - E.targetSince < 6 then
		return E.target
	end
	local best, bestDist = nil, math.huge
	for _, p in ipairs(list) do
		local d = flatDistance(rootOf(p).Position, E.pos)
		if d < bestDist then
			best, bestDist = p, d
		end
	end
	if best ~= E.target then
		E.target, E.targetSince = best, now()
	end
	return best
end

local function targetPosition(E)
	local root = E.target and rootOf(E.target)
	return root and flat(root.Position) + Vector3.new(0, E.floorY, 0) or nil
end

-- A weighted pick among the attacks that suit this distance. The same attack
-- is less likely twice running and never three times.
local function chooseAttack(E, distance)
	local options, total = {}, 0
	for name, a in pairs(E.def.Attacks) do
		if a.Phase <= E.phase and distance >= a.Range[1] and distance <= a.Range[2] then
			local w = a.Weight
			if E.history[1] == name then
				w = (E.history[2] == name) and 0 or w * 0.4
			end
			if w > 0 then
				options[#options + 1] = { name, w }
				total = total + w
			end
		end
	end
	table.sort(options, function(x, y)
		return x[1] < y[1] -- a stable order, so the pick depends only on the roll
	end)
	if total <= 0 then
		return nil
	end
	local roll = E.rng:NextNumber() * total
	for _, o in ipairs(options) do
		roll = roll - o[2]
		if roll <= 0 then
			return o[1]
		end
	end
	return options[#options][1]
end

----------------------------------------------------------------------
-- The fight's big moments
----------------------------------------------------------------------
-- The shell breaks at half health: untouchable while it happens, everyone near
-- is thrown back, and phase two begins.
local function breakShell(E, token)
	local def = E.def
	E.phase = 2
	E.model:SetAttribute("Phase", 2)
	E.model:SetAttribute("MinHealth", nil)
	E.model:SetAttribute("Invulnerable", true)
	E.track, E.chase, E.motion, E.sweep = false, false, nil, nil
	if E.boss.onBreak then
		E.boss.onBreak(E) -- (the boss's own extras: see its file)
	end
	setState(E, "Transition")
	local t0 = setAction(E, "Break", def.BreakTime)
	if not waitUntil(E, token, t0 + def.BreakTime * 0.35) then
		return false
	end
	for _, p in ipairs(fightersIn(E)) do
		local root = rootOf(p)
		if root and flatDistance(root.Position, E.pos) <= def.BreakReach then
			CombatService.Shove(p, knockbackFrom(E.pos, root, def.BreakShove, 26))
		end
	end
	if not waitUntil(E, token, t0 + def.BreakTime) then
		return false
	end
	E.model:SetAttribute("Invulnerable", false)
	setState(E, "Fighting")
	return true
end

-- The fight itself: pick a target, pick an attack that suits the distance,
-- do it, breathe, repeat.
local function brain(E, token)
	while valid(E, token) and E.state ~= "Dead" do
		if E.phase == 1 and healthShare(E) <= E.def.PhaseAt + 1e-6 then
			if not breakShell(E, token) then
				return
			end
		end
		local target = pickTarget(E)
		local aimAt = target and targetPosition(E)
		if not aimAt then
			E.chase, E.track = false, false
			task.wait(0.2)
		else
			local name = chooseAttack(E, flatDistance(aimAt, E.pos))
			if not name then
				-- nothing reaches from here: close in for a moment and think again
				E.chase, E.track = true, true
				task.wait(0.35)
			else
				E.chase = false
				E.history = { name, E.history[1] }
				E.boss.Attacks[name](E, token) -- (the boss's own attacks: see its file)
				if not valid(E, token) then
					return
				end
				-- breathe, drifting after them
				local b = E.def.Breather[E.phase] or E.def.Breather[1]
				E.chase, E.track = true, true
				E.model:SetAttribute("Action", "Idle")
				local pause = b[1] + E.rng:NextNumber() * (b[2] - b[1])
				waitUntil(E, token, now() + pause)
			end
		end
	end
end

local function makeTarget(E, on)
	if on then
		CollectionService:AddTag(E.model, "CombatTarget")
	else
		CollectionService:RemoveTag(E.model, "CombatTarget")
	end
end

-- Which brain an encounter runs: the boss's own (Tuber has two whole fights,
-- one per health bar), or the shared surface-boss brain above
local function runBrain(E, token)
	if E.boss.brain then
		E.boss.brain(E, token)
	else
		brain(E, token)
	end
end

local function wake(E)
	if E.state ~= "Dormant" then
		return
	end
	E.token = E.token + 1
	local token = E.token
	local def = E.def
	-- which Spire they came up: Normal, or a harder tier (SpireService puts
	-- it on each player). The floor takes that tier's level - so its health,
	-- its props and what a win pays all follow - and the tier makes it
	-- tougher and quicker still (Config.Spire.Tiers)
	local tierId = nil
	for _, p in ipairs(fightersIn(E)) do
		tierId = tierId or p:GetAttribute("SpireTier")
	end
	local tier = Config.spireTier(tierId)
	E.tier = tier.id
	E.pace = tier.pace or 1
	E.floorDef = Config.spireFloorFor(E.floor, tier.id) or E.floorDef
	E.model:SetAttribute("Tier", tier.id ~= "Normal" and tier.id or nil)
	-- health for this fight: its punch count at the floor's recommended power,
	-- scaled up for every extra player here when it wakes
	local rec = math.max(1, Config.powerForLevel((E.floorDef and E.floorDef.level) or 1))
	local party = math.max(1, #fightersIn(E))
	local maxHealth = math.floor(rec * def.HealthPunches * (1 + def.PartyScale * (party - 1)) * Config.spireTierHealth(E.floor, tier.id))
	E.model:SetAttribute("MaxHealth", maxHealth)
	E.model:SetAttribute("Health", maxHealth)
	E.model:SetAttribute("MinHealth", math.floor(maxHealth * def.PhaseAt)) -- the phase shield
	E.model:SetAttribute("Invulnerable", true)
	E.model:SetAttribute("Phase", 1)
	E.phase = 1
	E.history = {}
	E.participants = {}
	makeTarget(E, true)
	setState(E, "Waking")
	local t0 = setAction(E, "Wake", def.WakeTime)
	task.spawn(function()
		if not waitUntil(E, token, t0 + def.WakeTime) then
			return
		end
		E.model:SetAttribute("Invulnerable", false)
		setState(E, "Fighting")
		runBrain(E, token)
	end)
end

-- back to sleep: everyone who was fighting it is dead or gone
local function reset(E)
	E.token = E.token + 1
	local token = E.token
	E.waves, E.puddles = {}, {}
	E.motion, E.sweep, E.track, E.chase, E.target = nil, nil, false, false, nil
	if E.boss.onReset then
		E.boss.onReset(E) -- (e.g. Tuber: every wall, turret and buddy he left around swept away)
	end
	E.model:SetAttribute("Invulnerable", true)
	makeTarget(E, false)
	setState(E, "Resetting")
	local t0 = setAction(E, "Reset", 2)
	task.spawn(function()
		if not waitUntil(E, token, t0 + 2) then
			return
		end
		E.pos = E.home
		E.facing = E.homeFacing
		place(E)
		if E.boss.onHome then
			E.boss.onHome(E) -- (home again)
		end
		local max = E.model:GetAttribute("MaxHealth") or 1
		E.model:SetAttribute("Health", max)
		E.model:SetAttribute("Phase", 1)
		E.phase = 1
		E.model:SetAttribute("Invulnerable", false)
		setState(E, "Dormant")
		setAction(E, "Dormant", nil)
	end)
end

local function die(E)
	if E.state == "Dead" then
		return
	end
	E.token = E.token + 1
	E.waves, E.puddles = {}, {}
	E.motion, E.sweep, E.track, E.chase = nil, nil, false, false
	if E.boss.onDie then
		E.boss.onDie(E)
	end
	E.model:SetAttribute("Invulnerable", true)
	E.model:SetAttribute("Health", 0)
	makeTarget(E, false)
	setState(E, "Dead")
	setAction(E, "Death", nil)
	E.deadAt = now()
	-- everyone in the arena when it falls shares the win: so many LEVELS'
	-- worth of Power at the floor's recommended level (its Reward; a harder
	-- tier's floors are closer together, so its reward share is smaller)
	local level = (E.floorDef and E.floorDef.level) or 1
	local share = Config.spireTier(E.tier).reward or 1
	for _, p in ipairs(presentIn(E)) do
		local levels = E.def.Reward.Power
		local first = false
		if PlayerService and PlayerService.RecordBossKill then
			first = PlayerService.RecordBossKill(p, E.floor, E.tier)
		end
		if first then
			levels = levels + E.def.Reward.FirstClear
		end
		local gained = Config.levelsWorth(level, levels * share)
		-- a BOSS RUSH ticket (the shop's) on a boss you'd beaten before: more
		-- Power (ShopService.Rush says how much, and uses the ticket)
		local rush = 1
		if not first and BossService.WinHook then
			local ok, m = pcall(BossService.WinHook, p, E.floor)
			rush = ok and tonumber(m) or 1
		end
		gained = math.floor(gained * rush)
		if PlayerService and PlayerService.AddPower then
			PlayerService.AddPower(p, gained)
		end
		if BossEvent then
			BossEvent:FireClient(p, "Victory", E.floor, gained, first)
		end
	end
end

----------------------------------------------------------------------
-- Every frame: movement, facing, and the attacks that live in the world
----------------------------------------------------------------------
local function stepMovement(E, dt)
	local def = E.def
	local t = now()
	if E.motion then
		-- a lunge or a hop: exactly where the clients are drawing it
		local m = E.motion
		local u = math.clamp((t - m.t0) / math.max(m.t1 - m.t0, 1e-3), 0, 1)
		E.pos = m.from:Lerp(m.to, u)
		setMoving(E, false)
	elseif E.chase and E.target then
		local aim = targetPosition(E)
		local keep = def.Size / 2 + 5 -- stop short of standing on them
		if aim then
			local gap = flat(aim - E.pos)
			local speed = (def.MoveSpeed[E.phase] or def.MoveSpeed[1]) / (E.pace or 1)
			if gap.Magnitude > keep then
				local step = math.min(speed * dt, gap.Magnitude - keep)
				E.pos = E.pos + gap.Unit * step
				setMoving(E, true)
			else
				setMoving(E, false)
			end
		end
	else
		setMoving(E, false)
	end
	-- it never leaves the colosseum floor
	local fromHome = flat(E.pos - E.home)
	if fromHome.Magnitude > def.Leash then
		E.pos = Vector3.new(E.home.X, E.floorY, E.home.Z) + fromHome.Unit * def.Leash
	end
	E.pos = Vector3.new(E.pos.X, E.floorY, E.pos.Z)
	if E.boss.onMove then
		E.boss.onMove(E, dt) -- (the boss's own say in where it can stand: e.g. Kaze walks round pillars)
	end

	-- turning: lined up on its target while it winds up, frozen once it commits
	if E.track and E.target then
		local aim = targetPosition(E)
		if aim then
			local want = flat(aim - E.pos)
			if want.Magnitude > 0.5 then
				local rate = math.rad(def.TurnSpeed[E.phase] or def.TurnSpeed[1])
				E.facing = turnToward(E.facing, want.Unit, rate * dt)
			end
		end
	end
	place(E)

	-- a lunge runs over anyone in its path
	if E.sweep then
		hitArea(E, E.pos, E.sweep.radius, E.sweep.damage, E.sweep.knockback, E.sweep.hit, E.sweep.fromBelow)
	end
end

-- The wave is a ring growing outward. A player is caught if the ring's band
-- passed over them this frame and they weren't high enough to clear it - so
-- a jump at the right moment beats it, and so does a roll's invincibility.
-- It's a wall, not a one-time thing: touch it again later (say, backing
-- into it) and it hurts again - just not twice within WAVE_REHIT seconds.
local WAVE_REHIT = 1
local function stepWaves(E)
	if #E.waves == 0 then
		return
	end
	local t = now()
	local list = fightersIn(E)
	for i = #E.waves, 1, -1 do
		local w = E.waves[i]
		local age = t - w.t0
		if age > w.reach / w.speed then
			table.remove(E.waves, i)
		elseif age >= 0 then
			local r = w.start + w.speed * age
			local half = w.thickness / 2
			for _, p in ipairs(list) do
				if t - (w.hit[p] or -math.huge) >= WAVE_REHIT then
					local root = rootOf(p)
					if root then
						local d = flatDistance(root.Position, w.origin)
						if d >= w.lastR - half - PLAYER_RADIUS and d <= r + half + PLAYER_RADIUS then
							local above = root.Position.Y - (E.floorY + STAND_HEIGHT)
							if above < w.height * 0.8 and not CombatService.IsInvulnerable(p) then
								w.hit[p] = t
								CombatService.DamagePlayer(p, w.damage, w.origin, knockbackFrom(w.origin, root, w.knockback))
							elseif above < w.height * 0.8 and not w.dodged then
								w.dodged = true -- ("Dodged!" once for a roll through it)
								CombatService.DamagePlayer(p, w.damage, w.origin)
							end
						end
					end
				end
			end
			w.lastR = r
		end
	end
end

-- Puddles burn anyone standing in them, a little at a time. Standing where
-- several overlap burns no faster than standing in one: three globs landing on
-- the same spot is a bad place to be, not three times the damage.
local function stepPuddles(E)
	if #E.puddles == 0 then
		return
	end
	local t = now()
	for i = #E.puddles, 1, -1 do
		if t > E.puddles[i].untilT then
			table.remove(E.puddles, i)
		end
	end
	if #E.puddles == 0 then
		return
	end
	E.burnedAt = E.burnedAt or {}
	for _, p in ipairs(fightersIn(E)) do
		local root = rootOf(p)
		if root and root.Position.Y - (E.floorY + STAND_HEIGHT) < 2 then
			for _, pd in ipairs(E.puddles) do
				if flatDistance(root.Position, pd.pos) <= pd.radius then
					if t - (E.burnedAt[p] or -math.huge) >= pd.tick then
						E.burnedAt[p] = t
						CombatService.DamagePlayer(p, pd.damage, pd.pos, nil, true)
					end
					break -- one puddle's worth, however many you're in
				end
			end
		end
	end
end

-- Waking up, resetting when everyone's gone, and coming back after a kill.
local function stepWatch(E)
	local t = now()
	if t < E.nextWatch then
		return
	end
	E.nextWatch = t + 0.2
	if E.state == "Dormant" then
		for _, p in ipairs(fightersIn(E)) do
			local root = rootOf(p)
			if root and flatDistance(root.Position, E.home) <= E.def.WakeRange then
				wake(E)
				return
			end
		end
	elseif E.state == "Waking" or E.state == "Fighting" or E.state == "Transition" then
		if #fightersIn(E) == 0 then
			E.emptySince = E.emptySince or t
			if t - E.emptySince >= 3 then
				E.emptySince = nil
				reset(E)
			end
		else
			E.emptySince = nil
		end
	elseif E.state == "Dead" then
		if #presentIn(E) == 0 then
			E.emptySince = E.emptySince or t
			if t - E.emptySince >= 5 then
				E.emptySince = nil
				reset(E) -- sinks the corpse's pool and brings it back, asleep
			end
		else
			E.emptySince = nil
		end
	end
end

----------------------------------------------------------------------
-- Setting an encounter up
----------------------------------------------------------------------
local function build(floorId, homePart)
	local def = Config.Bosses[floorId]
	if not def then
		return nil
	end
	local boss = bossModule(def)
	if not boss then
		return nil -- (no file for it in Bosses: warned once, and the other bosses carry on)
	end
	-- which arena copy: its id names the boss of every copy after the first
	local arena = arenaRoot(homePart)
	local arenaId = arena and arena:GetAttribute("ArenaId")
	local name = "Boss_" .. def.Short
	if arenaId and primary[floorId] then
		name = name .. "_" .. arenaId
	end
	local old = Workspace:FindFirstChild(name)
	if old then
		old:Destroy()
	end

	local home = homePart.Position
	local floorY = home.Y
	local height = def.Size * 0.85

	local model = Instance.new("Model")
	model.Name = name
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- every client always has it
	end)
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(def.Size, height, def.Size)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root

	model:SetAttribute("Boss", true)
	model:SetAttribute("Floor", floorId)
	model:SetAttribute("DisplayName", def.Name)
	model:SetAttribute("HitRadius", def.Size / 2)
	model:SetAttribute("NoBar", true)
	model:SetAttribute("StudioFair", def.StudioFairFight == true)
	model:SetAttribute("Health", 1)
	model:SetAttribute("MaxHealth", 1)
	model:SetAttribute("Phase", 1)
	model:SetAttribute("Moving", false)
	if arenaId then
		model:SetAttribute("ArenaId", arenaId) -- (which copy's boss this is: see ReplicatedStorage/Arenas)
	end

	local onHit = Instance.new("BindableEvent")
	onHit.Name = "OnHit"
	onHit.Parent = model

	local towardGate = homePart:GetAttribute("Facing")
	local E = {
		floor = floorId,
		def = def,
		floorDef = floorInfo(floorId),
		model = model,
		root = root,
		home = Vector3.new(home.X, floorY, home.Z),
		homeFacing = typeof(towardGate) == "Vector3" and unitOr(flat(towardGate), Vector3.new(0, 0, 1)) or Vector3.new(0, 0, 1),
		floorY = floorY,
		height = height,
		state = "Dormant",
		phase = 1,
		token = 0,
		actionId = 0,
		history = {},
		waves = {},
		puddles = {},
		participants = {},
		nextWatch = 0,
		rng = Random.new(),
		arena = arena, -- the arena copy it lives in
		arenaId = arenaId,
		stones = findStones(floorId, arena),
		boss = boss, -- its own file: its attacks, and the hooks it adds (see Bosses/)
	}
	E.pos = E.home
	E.facing = E.homeFacing
	if not primary[floorId] then
		primary[floorId] = E
	end
	place(E)
	model.Parent = Workspace
	CollectionService:AddTag(model, "Boss")
	setState(E, "Dormant")
	setAction(E, "Dormant", nil)

	if boss.onBuild then
		boss.onBuild(E) -- (e.g. Tuber: the arena's rocks, and where you can punch him)
	end

	onHit.Event:Connect(function(player, damage, killed)
		if typeof(player) == "Instance" and player:IsA("Player") then
			E.participants[player] = true
		end
		if E.state == "Dormant" then
			wake(E)
		elseif killed and E.state ~= "Dead" then
			die(E)
		elseif E.phase == 1 and E.state == "Fighting" and healthShare(E) <= E.def.PhaseAt + 1e-6 then
			-- The shell has cracked: it breaks right now, whatever it was doing.
			-- (Health is held at the threshold until then, so the break always
			-- plays - one huge hit can't skip straight into phase two.)
			E.token = E.token + 1
			local token = E.token
			task.spawn(function()
				if breakShell(E, token) then
					runBrain(E, token)
				end
			end)
		end
		local _ = damage
	end)
	return E
end

----------------------------------------------------------------------
-- The kit: the shared helpers every boss file gets (Boss.init(kit))
----------------------------------------------------------------------
local function makeKit()
	return {
		CombatService = CombatService,
		PlayerService = PlayerService,
		STAND_HEIGHT = STAND_HEIGHT,
		PLAYER_RADIUS = PLAYER_RADIUS,
		SLOTS = SLOTS,
		-- small helpers
		now = now,
		flat = flat,
		flatDistance = flatDistance,
		unitOr = unitOr,
		rootOf = rootOf,
		turnToward = turnToward,
		floorInfo = floorInfo,
		fightersIn = fightersIn,
		presentIn = presentIn,
		-- its own arena copy: is a player in it, is a part of the world in
		-- it, the arena model, a folder for its props
		inArena = inArena,
		inArenaModel = inArenaModel,
		arenaWith = arenaWith,
		propFolder = propFolder,
		-- publishing what it's doing, for every screen
		setState = setState,
		setAction = setAction,
		setSlot = setSlot,
		setMoving = setMoving,
		place = place,
		-- timing (every wait checks the fight wasn't reset or won meanwhile)
		valid = valid,
		waitUntil = waitUntil,
		-- the stone platforms
		findStones = findStones,
		stoneUnder = stoneUnder,
		besideStone = besideStone,
		-- hitting players
		knockbackFrom = knockbackFrom,
		hitArea = hitArea,
		-- health, recovering, targets
		healthShare = healthShare,
		recovery = recovery,
		pickTarget = pickTarget,
		targetPosition = targetPosition,
		chooseAttack = chooseAttack,
		makeTarget = makeTarget,
		-- the phase change at half health
		breakShell = breakShell,
		-- the shared every-frame steps, for a boss with its own step that still
		-- wants some of them (moving and turning, the waves, the puddles)
		stepMovement = stepMovement,
		stepWaves = stepWaves,
		stepPuddles = stepPuddles,
	}
end

----------------------------------------------------------------------
-- Start
----------------------------------------------------------------------
function BossService.Start(combatService, playerService)
	CombatService = combatService
	PlayerService = playerService

	-- every boss file gets the shared helpers (now that the services are here)
	for _, boss in pairs(bossModules) do
		if boss and boss.init then
			boss.init(makeKit())
		end
	end

	local old = ReplicatedStorage:FindFirstChild("BossRemotes")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "BossRemotes"
	BossEvent = Instance.new("RemoteEvent")
	BossEvent.Name = "BossEvent" -- server -> client: "Victory", floor, powerGained, firstClear
	BossEvent.Parent = folder
	folder.Parent = ReplicatedStorage

	-- Every arena marks where its boss lives with a "BossHome" part: one
	-- encounter each - and one more whenever an arena copy appears
	-- (ArenaPool), taken down again when it goes
	local function add(homePart)
		local floorId = homePart:GetAttribute("Floor")
		if floorId and Config.Bosses[floorId] and not encounters[homePart] then
			local E = build(floorId, homePart)
			encounters[homePart] = E
			if E then
				table.insert(running, E)
			end
		end
	end
	for _, homePart in ipairs(CollectionService:GetTagged("BossHome")) do
		add(homePart)
	end
	CollectionService:GetInstanceAddedSignal("BossHome"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("BossHome"):Connect(function(homePart)
		local E = encounters[homePart]
		if not E then
			return
		end
		encounters[homePart] = nil
		local i = table.find(running, E)
		if i then
			table.remove(running, i)
		end
		E.token = E.token + 1 -- (every attack still running stops)
		if E.boss.onDestroy then
			pcall(E.boss.onDestroy, E) -- (the boss's own tidying: see its file)
		end
		for _, f in pairs(E.folders or {}) do
			f:Destroy()
		end
		makeTarget(E, false)
		E.state = "Gone"
		E.model:Destroy()
		if primary[E.floor] == E then
			primary[E.floor] = nil
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		for _, E in ipairs(table.clone(running)) do
			if E.state == "Gone" then
				continue -- (taken down by something earlier this frame)
			end
			if E.boss.step then
				-- a boss with its own every-frame step (Tuber). Protected: if it
				-- ever errors, the other bosses and the rest of the frame carry on
				local ok, err = pcall(function()
					if E.state ~= "Dormant" and E.state ~= "Dead" then
						E.boss.step(E, dt)
					end
				end)
				if not ok and not E.stepWarned then
					E.stepWarned = true
					warn("[BossService] " .. E.def.Short .. " step failed: " .. tostring(err))
				end
			elseif E.state ~= "Dormant" and E.state ~= "Dead" then
				stepMovement(E, dt)
				stepWaves(E)
				stepPuddles(E)
			end
			stepWatch(E)
		end
	end)
end

-- For tests and tools: the live encounter in a floor's first arena, and the
-- one in an arena copy (by its ArenaId).
function BossService.Encounter(floorId)
	return primary[floorId]
end
function BossService.EncounterIn(arenaId)
	for _, E in ipairs(running) do
		if E.arenaId == arenaId then
			return E
		end
	end
	return nil
end

-- For tests: each boss's attacks by name (its short name in Config), so a
-- test can run one right now. (_Attacks: the first boss's.)
BossService._BossAttacks = {}
for short, boss in pairs(bossModules) do
	if boss then
		BossService._BossAttacks[short] = boss.Attacks
	end
end
BossService._Attacks = BossService._BossAttacks.Oozark

return BossService
