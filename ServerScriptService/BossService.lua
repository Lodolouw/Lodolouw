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

	Attributes on the boss model, for BossClient:
	    State, Phase, Health, MaxHealth, Moving
	    Action, ActionId, ActionStart (server time), ActA/ActB/ActC (positions),
	    ActN (a number), ActK (how many of the ActA..C slots are filled so far)
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
local encounters = {} -- [floorId] = encounter

local STAND_HEIGHT = 3 -- a standing character's root is about this far off the floor
local PLAYER_RADIUS = 1.5 -- how wide a character is, for hits
-- positions an action publishes as it goes (globs, rings, hops): room for a barrage
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

-- the players fighting on this floor right now, alive
local function fightersIn(E)
	local list = {}
	for _, p in ipairs(CombatService.PlayersInArena(E.floor)) do
		if CombatService.IsFighting(p) and rootOf(p) then
			list[#list + 1] = p
		end
	end
	return list
end

-- everyone standing in this floor's arena, alive or not
local function presentIn(E)
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("SpireFloor") == E.floor then
			list[#list + 1] = p
		end
	end
	return list
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
-- (The Sunken Dunes' five platforms are tagged "DunePlatform"; a floor with
-- none - Gloomgut's - is unaffected.)
----------------------------------------------------------------------
local function findStones(floorId)
	local list = {}
	for _, pm in ipairs(CollectionService:GetTagged("DunePlatform")) do
		if pm:GetAttribute("Floor") == floorId then
			local slab = pm:FindFirstChild("PlatformSlab")
			local center = slab and slab.Position
			if not center then
				local ok, cf = pcall(function()
					return pm:GetPivot()
				end)
				center = ok and cf and cf.Position or nil
			end
			if center then
				list[#list + 1] = { center = center, radius = pm:GetAttribute("Radius") or 10 }
			end
		end
	end
	return list
end

-- the stone platform a spot is on, if it's on one
local function stoneUnder(E, pos)
	for _, st in ipairs(E.stones or {}) do
		if flatDistance(pos, st.center) <= st.radius then
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
local function recovery(E, seconds)
	local def = E.def
	if E.phase >= 2 then
		if healthShare(E) <= def.DesperateAt then
			return seconds * def.DesperateRecovery
		end
		return seconds * def.Phase2Recovery
	end
	return seconds
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
-- The attacks
----------------------------------------------------------------------
local Attacks = {}

-- Rears up, wobbles at the top, drops its whole bulk where it stands.
function Attacks.Slam(E, token)
	local a = E.def.Attacks.Slam
	E.track = true
	local t0 = setAction(E, "Slam", a.Radius)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.track = false
	hitArea(E, E.pos, a.Radius, a.Damage, a.Knockback)
	waitUntil(E, token, t0 + a.Tell + recovery(E, a.Recovery))
end

-- Flattens, then pushes a wall of slime outward along the floor. The wall is
-- tracked every frame (see stepWaves) so it hits exactly as it's drawn.
function Attacks.Wave(E, token)
	local a = E.def.Attacks.Wave
	E.track = true
	local t0 = setAction(E, "Wave", a.Speed)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.track = false
	setSlot(E, 1, E.pos)
	table.insert(E.waves, {
		origin = E.pos,
		start = E.def.Size / 2, -- it rolls out from under the body's edge
		t0 = t0 + a.Tell,
		speed = a.Speed,
		reach = a.Reach,
		thickness = a.Thickness,
		height = a.Height,
		damage = a.Damage,
		knockback = a.Knockback,
		lastR = E.def.Size / 2,
		hit = {},
	})
	waitUntil(E, token, t0 + a.Tell + recovery(E, a.Recovery))
end

-- Roots itself and spits globs at where you're standing. Each lands after a
-- flight, hits around where it lands, and leaves a burning puddle.
function Attacks.Spit(E, token)
	local a = E.def.Attacks.Spit
	E.track = true
	local t0 = setAction(E, "Spit", a.Flight)
	for i = 1, a.Globs do
		local spitAt = t0 + a.Tell + (i - 1) * a.Gap
		if not waitUntil(E, token, spitAt) then
			return
		end
		-- The barrage: the first glob goes where you're standing, the next where
		-- you're heading, and the rest spray around you in a widening circle, so
		-- stepping aside isn't enough - you have to read the markers and move
		-- through the gaps. In a party it takes turns on everyone.
		local list = fightersIn(E)
		local victim = (#list > 1) and list[((i - 1) % #list) + 1] or E.target
		local root = victim and rootOf(victim)
		local aim
		if root then
			local here = flat(root.Position) + Vector3.new(0, E.floorY, 0)
			local vel = flat(root.AssemblyLinearVelocity)
			if i == 1 then
				aim = here
			elseif i == 2 then
				aim = here + vel * a.Flight -- where you'll be if you keep going
			else
				local spread = a.Spread * math.sqrt(E.rng:NextNumber())
				local ang = E.rng:NextNumber() * math.pi * 2
				aim = here + vel * a.Flight * 0.5 + Vector3.new(math.cos(ang) * spread, 0, math.sin(ang) * spread)
			end
		else
			aim = E.pos + E.facing * 20
		end
		-- never off the edge of the fighting floor
		local off = flat(aim - E.home)
		if off.Magnitude > E.def.Leash + 30 then
			aim = E.home + off.Unit * (E.def.Leash + 30)
		end
		aim = Vector3.new(aim.X, E.floorY, aim.Z)
		setSlot(E, i, aim)
		task.spawn(function()
			if waitUntil(E, token, spitAt + a.Flight) then
				hitArea(E, aim, a.Radius, a.Damage, 18)
				if stoneUnder(E, aim) then
					return -- it lands on stone: nothing for it to sink into
				end
				table.insert(E.puddles, {
					pos = aim,
					radius = a.Puddle,
					untilT = now() + a.PuddleTime,
					nextTick = now() + a.PuddleTick,
					tick = a.PuddleTick,
					damage = a.PuddleDamage,
				})
			end
		end)
	end
	E.track = false
	waitUntil(E, token, t0 + a.Tell + (a.Globs - 1) * a.Gap + recovery(E, a.Recovery))
end

-- Leans back, then hurls itself at where you were when it committed.
-- (Mireworm does it underground: it dives in the second half of the tell and
-- can't be hit until it bursts back out at the far end.)
function Attacks.Lunge(E, token)
	local a = E.def.Attacks.Lunge
	local burrows = E.def.Body == "Worm"
	E.track = true
	local t0 = setAction(E, "Lunge", nil)
	if burrows then
		if not waitUntil(E, token, t0 + a.Tell * 0.6) then
			return
		end
		E.model:SetAttribute("Invulnerable", true) -- under the sand
	end
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.track = false
	local from = E.pos
	local aim = targetPosition(E) or (from + E.facing * a.MaxDistance)
	local offset = flat(aim - from)
	local distance = math.min(offset.Magnitude, a.MaxDistance)
	local dir = unitOr(offset, E.facing)
	local to = from + dir * distance
	-- never out past its leash
	local fromHome = flat(to - E.home)
	if fromHome.Magnitude > E.def.Leash then
		to = E.home + fromHome.Unit * E.def.Leash
	end
	-- you're on stone: it can't come up under you, so it comes up beside it
	local stone = burrows and stoneUnder(E, to)
	if stone then
		to = besideStone(E, stone, to, from, 6)
	end
	local travel = math.max(0.25, flatDistance(to, from) / a.Speed)
	E.facing = dir
	E.model:SetAttribute("ActN", travel)
	setSlot(E, 1, from)
	setSlot(E, 2, to)
	local start = now()
	local struck = {}
	E.motion = { from = from, to = to, t0 = start, t1 = start + travel }
	E.sweep = { radius = E.def.Size / 2 + 0.5, damage = a.Damage, knockback = a.Knockback, hit = struck, fromBelow = burrows }
	if not waitUntil(E, token, start + travel) then
		return
	end
	E.motion, E.sweep = nil, nil
	E.pos = to
	if burrows then
		E.model:SetAttribute("Invulnerable", false) -- out of the sand: fair game again
	end
	-- the landing splashes anyone it didn't already run through
	hitArea(E, to, a.Splash, a.Damage, a.Knockback, struck, burrows)
	waitUntil(E, token, start + travel + recovery(E, a.Recovery))
end

-- Phase two: three slams in a row, hopping after you between them, each with
-- a tighter radius. The roll's cooldown makes this just about dodgeable.
function Attacks.TripleSlam(E, token)
	local a = E.def.Attacks.TripleSlam
	E.track = true
	local t0 = setAction(E, "TripleSlam", a.Gap)
	setSlot(E, 1, E.pos)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.track = false
	hitArea(E, E.pos, a.Radii[1], a.Damage, a.Knockback)
	for i = 2, 3 do
		local from = E.pos
		local aim = targetPosition(E) or from
		local step = flat(aim - from)
		if step.Magnitude > a.Hop then
			step = step.Unit * a.Hop
		end
		local to = from + step
		if flat(to - E.home).Magnitude > E.def.Leash then
			to = from
		end
		E.facing = unitOr(step, E.facing)
		setSlot(E, i, to)
		local landAt = t0 + a.Tell + (i - 1) * a.Gap
		E.motion = { from = from, to = to, t0 = now(), t1 = landAt }
		if not waitUntil(E, token, landAt) then
			return
		end
		E.motion = nil
		E.pos = to
		hitArea(E, to, a.Radii[i], a.Damage, a.Knockback)
	end
	waitUntil(E, token, t0 + a.Tell + 2 * a.Gap + recovery(E, a.Recovery))
end

-- Phase two: rings bloom under the players' feet one after another and erupt
-- after a fuse. Standing still - or stopping to drink - gets you hit.
function Attacks.Wail(E, token)
	local a = E.def.Attacks.Wail
	E.track = true
	local t0 = setAction(E, "Wail", a.Fuse)
	for i = 1, a.Rings do
		local bloomAt = t0 + a.Tell + (i - 1) * a.Gap
		if not waitUntil(E, token, bloomAt) then
			return
		end
		-- the first ring is for its target; the rest go round the party
		local list = fightersIn(E)
		if E.target and table.find(list, E.target) then
			table.remove(list, table.find(list, E.target))
			table.insert(list, 1, E.target)
		end
		local victim = list[((i - 1) % math.max(#list, 1)) + 1]
		local root = victim and rootOf(victim)
		local at = root and (flat(root.Position) + Vector3.new(0, E.floorY, 0)) or (E.pos + E.facing * 15)
		-- it can't come up through stone: it erupts on the sand beside it
		local stone = stoneUnder(E, at)
		if stone then
			at = besideStone(E, stone, at, E.pos, a.Radius * 0.8)
		end
		setSlot(E, i, at)
		task.spawn(function()
			if waitUntil(E, token, bloomAt + a.Fuse) then
				hitArea(E, at, a.Radius, a.Damage, a.Knockback, nil, true)
			end
		end)
	end
	E.track = false
	waitUntil(E, token, t0 + a.Tell + (a.Rings - 1) * a.Gap + a.Fuse + recovery(E, a.Recovery))
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
				Attacks[name](E, token)
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

local function wake(E)
	if E.state ~= "Dormant" then
		return
	end
	E.token = E.token + 1
	local token = E.token
	local def = E.def
	-- health for this fight: its punch count at the floor's recommended power,
	-- scaled up for every extra player here when it wakes
	local rec = math.max(1, Config.powerForLevel((E.floorDef and E.floorDef.level) or 1))
	local party = math.max(1, #fightersIn(E))
	local maxHealth = math.floor(rec * def.HealthPunches * (1 + def.PartyScale * (party - 1)))
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
		brain(E, token)
	end)
end

-- back to sleep: everyone who was fighting it is dead or gone
local function reset(E)
	E.token = E.token + 1
	local token = E.token
	E.waves, E.puddles = {}, {}
	E.motion, E.sweep, E.track, E.chase, E.target = nil, nil, false, false, nil
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
	E.model:SetAttribute("Invulnerable", true)
	E.model:SetAttribute("Health", 0)
	makeTarget(E, false)
	setState(E, "Dead")
	setAction(E, "Death", nil)
	E.deadAt = now()
	-- everyone in the arena when it falls shares the win
	local rec = math.max(1, Config.powerForLevel((E.floorDef and E.floorDef.level) or 1))
	for _, p in ipairs(presentIn(E)) do
		local gained = math.floor(rec * E.def.Reward.Power)
		local first = false
		if PlayerService and PlayerService.RecordBossKill then
			first = PlayerService.RecordBossKill(p, E.floor)
		end
		if first then
			gained = gained + math.floor(rec * E.def.Reward.FirstClear)
		end
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
			local speed = def.MoveSpeed[E.phase] or def.MoveSpeed[1]
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
				if not w.hit[p] then
					local root = rootOf(p)
					if root then
						local d = flatDistance(root.Position, w.origin)
						if d >= w.lastR - half - PLAYER_RADIUS and d <= r + half + PLAYER_RADIUS then
							local above = root.Position.Y - (E.floorY + STAND_HEIGHT)
							if above < w.height * 0.8 then
								w.hit[p] = true
								CombatService.DamagePlayer(p, w.damage, w.origin, knockbackFrom(w.origin, root, w.knockback))
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
	local old = Workspace:FindFirstChild("Boss_" .. def.Short)
	if old then
		old:Destroy()
	end

	local home = homePart.Position
	local floorY = home.Y
	local height = def.Size * 0.85

	local model = Instance.new("Model")
	model.Name = "Boss_" .. def.Short
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
		stones = findStones(floorId),
	}
	E.pos = E.home
	E.facing = E.homeFacing
	place(E)
	model.Parent = Workspace
	CollectionService:AddTag(model, "Boss")
	setState(E, "Dormant")
	setAction(E, "Dormant", nil)

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
					brain(E, token)
				end
			end)
		end
		local _ = damage
	end)
	return E
end

----------------------------------------------------------------------
-- Start
----------------------------------------------------------------------
function BossService.Start(combatService, playerService)
	CombatService = combatService
	PlayerService = playerService

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

	-- LobbyBuilder marks where each boss lives with a "BossHome" part
	for _, homePart in ipairs(CollectionService:GetTagged("BossHome")) do
		local floorId = homePart:GetAttribute("Floor")
		if floorId and Config.Bosses[floorId] and not encounters[floorId] then
			encounters[floorId] = build(floorId, homePart)
		end
	end

	RunService.Heartbeat:Connect(function(dt)
		for _, E in pairs(encounters) do
			if E.state ~= "Dormant" and E.state ~= "Dead" then
				stepMovement(E, dt)
				stepWaves(E)
				stepPuddles(E)
			end
			stepWatch(E)
		end
	end)
end

-- For tests and tools: the live encounter on a floor.
function BossService.Encounter(floorId)
	return encounters[floorId]
end

-- For tests: run one attack by name right now.
BossService._Attacks = Attacks

return BossService
