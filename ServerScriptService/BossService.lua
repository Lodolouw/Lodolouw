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

	Two ways of fighting live in here:
	    Gloomgut (and any boss without Body = "Worm") fights on the surface:
	        brain() and the Attacks table.
	    Mireworm (Body = "Worm") hunts from under the sand: wormBrain() and the
	        WormAttacks table, further down. The two never share an attack.

	Attributes on the boss model, for BossClient:
	    State, Phase, Health, MaxHealth, Moving
	    Action, ActionId, ActionStart (server time), ActA/ActB/ActC (positions),
	    ActN (a number), ActK (how many of the ActA..C slots are filled so far)
	    Mireworm also: Submerged (under the sand), ActT (a second moment in an
	    action, server time), PosT (the server time of its current position),
	    RumbleT / RumbleP (when and where the sand last bucked round it)
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
function Attacks.Lunge(E, token)
	local a = E.def.Attacks.Lunge
	E.track = true
	local t0 = setAction(E, "Lunge", nil)
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
	local travel = math.max(0.25, flatDistance(to, from) / a.Speed)
	E.facing = dir
	E.model:SetAttribute("ActN", travel)
	setSlot(E, 1, from)
	setSlot(E, 2, to)
	local start = now()
	local struck = {}
	E.motion = { from = from, to = to, t0 = start, t1 = start + travel }
	E.sweep = { radius = E.def.Size / 2 + 0.5, damage = a.Damage, knockback = a.Knockback, hit = struck }
	if not waitUntil(E, token, start + travel) then
		return
	end
	E.motion, E.sweep = nil, nil
	E.pos = to
	-- the landing splashes anyone it didn't already run through
	hitArea(E, to, a.Splash, a.Damage, a.Knockback, struck)
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
-- Mireworm's half-finished business (a coil closing, a tail mid-sweep...),
-- dropped when the fight turns, it dies or it goes back to sleep. Does nothing
-- for Gloomgut.
local function clearWorm(E)
	if not E.worm then
		return
	end
	E.swim, E.coil, E.lash = nil, nil, nil
	E.model:SetAttribute("ActT", nil)
end

-- The shell breaks at half health: untouchable while it happens, everyone near
-- is thrown back, and phase two begins.
local function breakShell(E, token)
	local def = E.def
	E.phase = 2
	E.model:SetAttribute("Phase", 2)
	E.model:SetAttribute("MinHealth", nil)
	E.model:SetAttribute("Invulnerable", true)
	E.track, E.chase, E.motion, E.sweep = false, false, nil, nil
	if E.worm then
		-- (it's always out of the sand when this happens: you only hurt it out there)
		clearWorm(E)
		E.under = false
		E.model:SetAttribute("Submerged", false)
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

----------------------------------------------------------------------
-- MIREWORM: THE HUNTER UNDER THE SAND  (any boss with Body = "Worm")
----------------------------------------------------------------------
-- Gloomgut fights on the surface and trades blows with you. Mireworm doesn't:
-- it swims under the sand, where nothing can touch it, and only comes up to
-- strike. Its fight goes round and round like this:
--
--     hunt (under the sand)  ->  strike  ->  EXPOSED (hit it now!)  ->  dive
--
-- * It hunts whoever is making the most noise (see listen below).
-- * While it hunts under the sand, the ground bucks round its ridge and hurts
--   (the rumble: stepRumble).
-- * In phase two the caved-in seal becomes a whirlpool, and it starts
--   bursting up through the platforms people hide on.
-- None of Gloomgut's attacks are used; its own are in WormAttacks below.
local WormAttacks = {}

-- Out of the sand and punchable (true), or under it and untouchable (false).
-- Under the sand it isn't a target at all, so punches don't lock onto it.
local function surface(E, up)
	E.under = not up
	E.model:SetAttribute("Submerged", not up)
	E.model:SetAttribute("Invulnerable", not up)
	makeTarget(E, up)
end

-- setAction, plus clearing the worm's own extra timing attribute
local function wormAction(E, name, number)
	E.model:SetAttribute("ActT", nil)
	return setAction(E, name, number)
end

-- the same spot, kept on the sand it can reach (inside its leash)
local function inLeash(E, pos, margin)
	local off = flat(pos - E.home)
	local max = E.def.Leash - (margin or 0)
	if off.Magnitude > max then
		off = off.Unit * max
	end
	return Vector3.new(E.home.X + off.X, E.floorY, E.home.Z + off.Z)
end

-- a spot it can burst up at: never through stone (on the sand beside it instead)
local function sandSpot(E, pos, toward, extra)
	local st = stoneUnder(E, pos)
	if st then
		pos = besideStone(E, st, pos, toward, extra)
	end
	return inLeash(E, pos, 4)
end

-- How high a player's root sits above whatever they're standing on: R6 legs
-- are 2 studs; R15 bodies use their HipHeight. (So tall and small avatars
-- are judged right, not just the default size.)
local function standHeight(root)
	local hum = root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
	local half = root.Size.Y / 2
	if hum and hum.RigType == Enum.HumanoidRigType.R6 then
		return 2 + half
	end
	local hip = hum and tonumber(hum.HipHeight) or 0
	return (hip > 0 and hip or 2) + half
end

-- How each fighter really stands. Avatars - and the newer Roblox character
-- controllers - hold the body at different heights, so a height worked out
-- from HipHeight alone can be well off (and then someone standing right on
-- the sand looked "in the air" to the tremor and the rumble, and was never
-- hit). So every frame of the fight it watches each player: `rest` is how
-- high their root actually sits while they stand or walk on the sand, and
-- `leapAt` is the last moment they shot upward (a jump, or being thrown).
local function watchFeet(E, t)
	E.feet = E.feet or setmetatable({}, { __mode = "k" })
	for _, p in ipairs(fightersIn(E)) do
		local root = rootOf(p)
		if root then
			local f = E.feet[p]
			if not f then
				f = { rest = standHeight(root), leapAt = -math.huge }
				E.feet[p] = f
			end
			local vy = root.AssemblyLinearVelocity.Y
			if vy > 16 then
				f.leapAt = t
			end
			if math.abs(vy) < 0.5 and not stoneUnder(E, root.Position) then
				local h = root.Position.Y - E.floorY
				if h > 0.5 and h < 12 then
					f.rest = f.rest + (h - f.rest) * 0.02
				end
			end
		end
	end
end

local function feetOf(E, root)
	return E.feet and E.feet[Players:GetPlayerFromCharacter(root.Parent)]
end

-- how far above the floor a player's feet are (negative: down in a crater)
local function feetAbove(E, root)
	local f = feetOf(E, root)
	return root.Position.Y - (E.floorY + (f and f.rest or standHeight(root)))
end

-- Feet on the floor (not jumping). "In the air" = going up or coming down
-- fast, or having jumped a moment ago (so even the top of a jump, where
-- you're hardly moving, counts) - or clearly up on something, `above` studs
-- or more. Standing in a crater (below the floor) still counts as on it. On
-- stone you're 1.7 studs up, which the callers that care about stone check
-- for themselves.
local function grounded(E, root, above)
	local vy = root.AssemblyLinearVelocity.Y
	if vy > 7 or vy < -12 then
		return false
	end
	local f = feetOf(E, root)
	if f and now() - f.leapAt < 0.55 then
		return false
	end
	return feetAbove(E, root) < (above or 1.2) + 1.2
end

-- (Studio only) why someone didn't count as standing on the sand - printed
-- when a quake misses them, so a test shows exactly what it saw
local function offSandReason(E, root)
	if stoneUnder(E, root.Position) then
		return "standing on stone"
	end
	local vy = root.AssemblyLinearVelocity.Y
	if vy > 7 or vy < -12 then
		return string.format("in the air (moving %s at %.0f)", vy > 0 and "up" or "down", math.abs(vy))
	end
	local f = feetOf(E, root)
	if f and now() - f.leapAt < 0.55 then
		return "in the air (just jumped)"
	end
	return string.format("up on something, %.1f studs above the sand", feetAbove(E, root))
end

-- where along a ray from `origin` (flat direction `dir`) it crosses a circle
-- round the arena's middle: returns the distances in and out, or nil if it misses
local function rayCircle(E, origin, dir, radius)
	local rel = flat(origin - E.home)
	local b = rel:Dot(dir)
	local c = rel:Dot(rel) - radius * radius
	local disc = b * b - c
	if disc < 0 then
		return nil
	end
	local s = math.sqrt(disc)
	return -b - s, -b + s
end

-- Everyone within `halfWidth` of the line from a to b takes the hit, thrown
-- sideways off it (the breach: its whole body coming down along the sand).
local function hitLine(E, a, b, halfWidth, damage, knockback)
	local ab = flat(b - a)
	local len = ab.Magnitude
	local dir = unitOr(ab, E.facing)
	for _, p in ipairs(fightersIn(E)) do
		local root = rootOf(p)
		if root then
			local along = math.clamp(flat(root.Position - a):Dot(dir), 0, len)
			local closest = a + dir * along
			if flatDistance(root.Position, closest) <= halfWidth + PLAYER_RADIUS then
				CombatService.DamagePlayer(p, damage, closest, knockbackFrom(closest, root, knockback))
			end
		end
	end
end

----------------------------------------------------------------------
-- How it hunts: by sound
----------------------------------------------------------------------
-- Every frame each fighter makes some noise: running on sand is loud (rolling
-- is louder still - you're moving faster), moving on stone is quiet, standing
-- still or being in the air is silent. Noise fades over Hunt.NoiseFade seconds.
local function listen(E, dt)
	local H = E.def.Hunt
	local fade = math.exp(-dt / (H.NoiseFade or 2.5))
	local old = E.noise or {}
	local heard = {}
	for _, p in ipairs(fightersIn(E)) do
		local root = rootOf(p)
		local n = (old[p] or 0) * fade
		if root and grounded(E, root, 2.5) then
			local speed = flat(root.AssemblyLinearVelocity).Magnitude
			local loud = stoneUnder(E, root.Position) and (H.StoneNoise or 0.25) or 1
			n = n + (speed / 16) * loud * dt
		end
		heard[p] = n
	end
	E.noise = heard -- (anyone who left or died is forgotten)
end

-- Its quarry: the loudest fighter. It sticks with the one it's after unless
-- someone else is a lot louder; if nobody is making a sound at all it feels
-- for whoever is nearest.
local function pickQuarry(E)
	local list = fightersIn(E)
	if #list == 0 then
		E.target = nil
		return nil
	end
	local noise = E.noise or {}
	local loudest, loudN = nil, -1
	for _, p in ipairs(list) do
		if (noise[p] or 0) > loudN then
			loudest, loudN = p, noise[p] or 0
		end
	end
	local current = E.target
	local stillHere = current and table.find(list, current)
	if stillHere and (noise[current] or 0) * 1.5 + 0.2 >= loudN then
		return current
	end
	if loudN < 0.15 then
		if stillHere then
			return current
		end
		local bestD = math.huge
		for _, p in ipairs(list) do
			local d = flatDistance(rootOf(p).Position, E.pos)
			if d < bestD then
				loudest, bestD = p, d
			end
		end
	end
	E.target, E.targetSince = loudest, now()
	return loudest
end

----------------------------------------------------------------------
-- The stone platforms: they crack, and they can shatter
----------------------------------------------------------------------
local CRACK_GLOW = Color3.fromRGB(255, 120, 50)

-- remembers how a platform's part looked, so a reset can put it back
local function remember(st, p)
	st.saved = st.saved or {}
	if not st.saved[p] then
		st.saved[p] = { Transparency = p.Transparency, CanCollide = p.CanCollide, CanQuery = p.CanQuery, Material = p.Material, Color = p.Color }
	end
end

-- the cracks across its top glow like embers: this one is about to go
local function glowCracks(st)
	for _, p in ipairs(st.model:GetDescendants()) do
		if p:IsA("BasePart") and p.Name == "PlatformCrack" then
			remember(st, p)
			p.Material = Enum.Material.Neon
			p.Color = CRACK_GLOW
		end
	end
end

-- gone for the rest of the fight (BossClient throws the rubble about)
local function breakStone(E, st)
	if st.broken then
		return
	end
	st.broken = true
	st.model:SetAttribute("Broken", true)
	for _, p in ipairs(st.model:GetDescendants()) do
		if p:IsA("BasePart") then
			remember(st, p)
			p.Transparency = 1
			p.CanCollide = false
			p.CanQuery = false
		end
	end
end

-- every platform whole again (when it goes back to sleep)
local function restoreStones(E)
	for _, st in ipairs(E.stones or {}) do
		for p, saved in pairs(st.saved or {}) do
			if p.Parent then
				for prop, value in pairs(saved) do
					p[prop] = value
				end
			end
		end
		st.saved, st.broken, st.cracks = nil, false, 0
		st.model:SetAttribute("Broken", nil)
		st.model:SetAttribute("Cracks", nil)
	end
end

----------------------------------------------------------------------
-- Coming up, going down, and the hunt
----------------------------------------------------------------------
-- Bursts up out of the sand at `spot` and stays out for `seconds`, turning to
-- face its quarry: the window to punch it. (Whatever brought it up has already
-- done its damage.)
local function wormErupt(E, token, spot, seconds)
	E.motion, E.swim = nil, nil
	E.pos = spot
	local aim = targetPosition(E)
	if aim and flatDistance(aim, spot) > 1 then
		E.facing = unitOr(flat(aim - spot), E.facing)
	end
	local t0 = wormAction(E, "Erupt", seconds)
	setSlot(E, 1, spot)
	surface(E, true)
	E.track = true
	local ok = waitUntil(E, token, t0 + seconds)
	E.track = false
	return ok
end

-- Head-first back under the sand. You can still land a hit in the first half.
local function wormDive(E, token)
	local H = E.def.Hunt
	E.track, E.motion, E.swim = false, nil, nil
	local t0 = wormAction(E, "Dive", H.DiveTime)
	if not waitUntil(E, token, t0 + H.DiveTime * 0.5) then
		return false
	end
	surface(E, false)
	return waitUntil(E, token, t0 + H.DiveTime)
end

-- Swims after its quarry for a while (Hunt.Time), striking sooner if it gets
-- close.
local function wormHunt(E, token)
	local H = E.def.Hunt
	local span = H.Time[E.phase] or H.Time[1]
	local t0 = wormAction(E, "Burrow", nil)
	local untilT = t0 + span[1] + E.rng:NextNumber() * (span[2] - span[1])
	E.swim = { speed = H.SwimSpeed[E.phase] or H.SwimSpeed[1] }
	while now() < untilT do
		if not valid(E, token) then
			return false
		end
		pickQuarry(E)
		local aim = targetPosition(E)
		if aim and now() - t0 > 0.6 and flatDistance(aim, E.pos) <= H.StrikeRange then
			break
		end
		task.wait()
	end
	E.swim = nil
	return valid(E, token)
end

----------------------------------------------------------------------
-- Its attacks
----------------------------------------------------------------------
-- AMBUSH: the ridge races after you, then stops; the sand under you bulges for
-- Lock seconds (the mark) and it bursts up there. Anyone on stone is safe.
function WormAttacks.Ambush(E, token)
	local a = E.def.Attacks.Ambush
	local t0 = wormAction(E, "Ambush", nil)
	E.swim = { speed = a.StalkSpeed }
	while now() < t0 + a.StalkTime do
		if not valid(E, token) then
			return
		end
		local aim = targetPosition(E)
		if not aim or flatDistance(aim, E.pos) < 5 then
			break
		end
		task.wait()
	end
	E.swim = nil
	local aim = targetPosition(E) or E.pos
	local spot = sandSpot(E, aim, E.pos, a.Radius)
	local eruptAt = now() + a.Lock
	E.motion = { from = E.pos, to = spot, t0 = now(), t1 = eruptAt - 0.1 }
	E.model:SetAttribute("ActN", eruptAt) -- (before the slot: the client reads it when the slot arrives)
	setSlot(E, 1, spot)
	if not waitUntil(E, token, eruptAt) then
		return
	end
	E.motion = nil
	hitArea(E, spot, a.Radius, a.Damage, a.Knockback, nil, true)
	wormErupt(E, token, spot, recovery(E, a.Exposed))
end

-- Where a leap from A lands if it's aimed at `aim`: its head comes down
-- Overshoot studs PAST its quarry, so they end up under its body, not beside
-- its nose. Never off the sand; never shorter than a real leap.
local function breachLanding(E, A, aim)
	local a = E.def.Attacks.Breach
	local dir = unitOr(flat(aim - A), E.facing)
	local want = math.clamp(flatDistance(aim, A) + a.Overshoot, 55, a.Length)
	local _, tOut = rayCircle(E, A, dir, E.def.Leash)
	local len = math.max(math.min(want, tOut or 0), 0)
	return Vector3.new(A.X, E.floorY, A.Z) + dir * len, len
end

-- Where the first leap takes off: back along the line from its quarry, far
-- enough that it arcs right over them. Nil if there isn't room on the sand.
local function breachPlan(E)
	local aim = targetPosition(E)
	if not aim then
		return nil
	end
	local dir = unitOr(flat(aim - E.pos), E.facing)
	local leash = E.def.Leash - 6
	local A = aim - dir * math.clamp(flatDistance(aim, E.pos), 45, 80)
	if flat(A - E.home).Magnitude > leash then
		-- the take-off point is off the sand: start where the line comes onto it
		local tIn = rayCircle(E, A, dir, leash)
		if not tIn then
			return nil
		end
		A = A + dir * math.max(tIn, 0)
	end
	A = Vector3.new(A.X, E.floorY, A.Z)
	local B, len = breachLanding(E, A, aim)
	if len < 50 then
		return nil
	end
	return A, B
end

-- One leap. `from` = where it takes off (nil for the first: it swims round
-- behind its quarry first). While it's in the air the landing FOLLOWS its
-- quarry, until Lock of the way through - then it's committed (the strip
-- flashes on screen). Its body comes down along the last BodyLength studs of
-- the leap. The last leap leaves it stuck there, EXPOSED; a leap with another
-- to follow goes straight back under. Returns where it went under (nil if
-- the fight moved on).
local function breachLeap(E, token, from, tell, last)
	local a = E.def.Attacks.Breach
	local A, B
	if from then
		local aim = targetPosition(E)
		if not aim then
			return nil
		end
		A = from
		B = breachLanding(E, A, aim)
	else
		A, B = breachPlan(E)
		if not A then
			return nil
		end
	end
	E.facing = unitOr(flat(B - A), E.facing)
	local t0 = wormAction(E, "Breach", last and 1 or 0) -- (ActN: 1 = the last leap)
	setSlot(E, 1, A)
	setSlot(E, 2, B)
	E.motion = { from = E.pos, to = A, t0 = t0, t1 = t0 + tell * 0.8 }
	if not waitUntil(E, token, t0 + tell) then
		return nil
	end
	E.motion = nil
	-- out of the sand: anyone right on the take-off point is thrown
	hitArea(E, A, a.Launch, math.floor(a.Damage * 0.6), a.Knockback * 0.6, nil, true)
	local launch = t0 + tell
	local land = launch + a.Flight
	local lockAt = launch + a.Flight * a.Lock
	local sent = 0
	while now() < lockAt do
		if not valid(E, token) then
			return nil
		end
		local aim = targetPosition(E)
		if aim then
			B = breachLanding(E, A, aim)
			if now() - sent >= 0.05 then
				sent = now()
				E.model:SetAttribute(SLOTS[2], B) -- every screen redraws the strip where it's heading
			end
		end
		E.pos = A:Lerp(B, math.clamp((now() - launch) / a.Flight, 0, 1))
		task.wait()
	end
	-- committed
	E.model:SetAttribute(SLOTS[2], B)
	E.motion = { from = E.pos, to = B, t0 = now(), t1 = land }
	if not waitUntil(E, token, land) then
		return nil
	end
	E.motion = nil
	local dir = unitOr(flat(B - A), E.facing)
	E.facing = dir
	local tail = B - dir * math.min(a.BodyLength, flatDistance(A, B))
	hitLine(E, tail, B, a.Width / 2, a.Damage, a.Knockback)
	local slideAt
	if last then
		-- stuck: you can punch it where it came down nearest its quarry
		local aim = targetPosition(E) or B
		E.pos = tail + dir * math.clamp(flat(aim - tail):Dot(dir), 0, flatDistance(tail, B))
		surface(E, true)
		slideAt = land + recovery(E, a.Stuck)
	else
		E.pos = B
		slideAt = land + 0.2
	end
	E.model:SetAttribute("ActT", slideAt) -- when it starts sliding back under
	if not waitUntil(E, token, slideAt) then
		return nil
	end
	surface(E, false)
	local slid = now() + (last and a.Slide or a.Slide * 0.5)
	E.motion = { from = E.pos, to = B, t0 = now(), t1 = slid }
	if not waitUntil(E, token, slid) then
		return nil
	end
	E.motion = nil
	E.pos = B
	return B
end

-- BREACH: one leap in phase one; in phase two it goes straight back up for
-- another (Leaps), each one aimed at its quarry again.
function WormAttacks.Breach(E, token)
	local a = E.def.Attacks.Breach
	local leaps = (type(a.Leaps) == "table" and (a.Leaps[E.phase] or a.Leaps[1])) or 1
	local from = nil
	for i = 1, leaps do
		from = breachLeap(E, token, from, (i == 1) and a.Tell or a.ChainTell, i == leaps)
		if not from then
			return
		end
	end
end

-- COIL: it circles its quarry under the sand, then its body bursts up in a
-- CLOSED ring round them with its head reared overhead, and tightens. Its body
-- throws anyone who touches it back to the side they came from - only a roll
-- (untouchable for a moment) gets you through it. Whoever is still inside when
-- it closes is crushed as the head strikes down; then it lies coiled there,
-- EXPOSED, until it dives.
function WormAttacks.Coil(E, token)
	local a = E.def.Attacks.Coil
	local aim = targetPosition(E)
	if not aim then
		return
	end
	local C = inLeash(E, aim, a.Radius)
	local t0 = wormAction(E, "Coil", nil)
	setSlot(E, 1, C)
	-- (each screen draws it circling; here it just heads for the ring)
	local edge = C + unitOr(flat(E.pos - C), E.facing) * a.Radius
	E.motion = { from = E.pos, to = edge, t0 = t0, t1 = t0 + a.Tell * 0.5 }
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.motion = nil
	E.pos = C
	E.coil = { center = C, t0 = t0 + a.Tell, a = a, next = {} }
	if not waitUntil(E, token, t0 + a.Tell + a.Close) then
		return
	end
	E.coil = nil
	hitArea(E, C, a.Crush + a.Wall / 2, a.Damage, a.Knockback)
	surface(E, true)
	waitUntil(E, token, now() + recovery(E, a.Exposed))
end

-- How far out the coil is `t` seconds into its tightening: slow at first, so
-- there's time to line up a roll, then fast.
local function coilRadius(c, t)
	local u = math.clamp((t - c.t0) / c.a.Close, 0, 1)
	return c.a.Radius - (c.a.Radius - c.a.Crush) * u * u
end

-- Every frame of a coil: its body is a wall. Touch it and you're hurt and
-- thrown back to the side you were on (again, if you touch it again). Rolling
-- through it - untouchable for the length of the roll - is the way out.
local function stepCoil(E, t)
	local c = E.coil
	if t < c.t0 then
		return
	end
	local a = c.a
	local r = coilRadius(c, t)
	for _, p in ipairs(fightersIn(E)) do
		local root = rootOf(p)
		local off = flat(root.Position - c.center)
		local d = off.Magnitude
		if math.abs(d - r) <= a.Wall / 2 + PLAYER_RADIUS and t >= (c.next[p] or 0) and not CombatService.IsInvulnerable(p) then
			c.next[p] = t + 0.8
			local side = (d >= r) and 1 or -1 -- out if you were outside it, in if inside
			local push = unitOr(off, Vector3.new(0, 0, 1)) * side
			CombatService.DamagePlayer(p, a.WallDamage, root.Position, push * a.Knockback * 0.7 + Vector3.new(0, 16, 0))
		end
	end
end

-- DEVOUR: a sinkhole spins open under you and drags you toward its middle (the
-- drag happens on your own screen, in BossClient), then its maw bursts up out
-- of it. Anyone on stone is out of reach of both.
function WormAttacks.Devour(E, token)
	local a = E.def.Attacks.Devour
	local aim = targetPosition(E)
	if not aim then
		return
	end
	local C = inLeash(E, aim, 4)
	local t0 = wormAction(E, "Devour", nil)
	setSlot(E, 1, C)
	E.motion = { from = E.pos, to = C, t0 = t0, t1 = t0 + math.min(0.6, a.Tell * 0.5) }
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.motion = nil
	hitArea(E, C, a.Bite, a.Damage, a.Knockback, nil, true)
	wormErupt(E, token, C, recovery(E, a.Exposed))
end

-- TAIL LASH: its tail rips up out of the sand behind its quarry (behind the
-- way they're facing) and sweeps round in a wide arc. The worm itself stays
-- under - there's nothing to punch after this one.
function WormAttacks.TailLash(E, token)
	local a = E.def.Attacks.TailLash
	local root = E.target and rootOf(E.target)
	local aim = targetPosition(E)
	if not (root and aim) then
		return
	end
	local look = unitOr(flat(root.CFrame.LookVector), unitOr(flat(aim - E.pos), E.facing))
	local anchor = sandSpot(E, aim - look * a.Behind, aim, 4)
	local toQuarry = flat(aim - anchor)
	local mid = math.atan2(toQuarry.X, toQuarry.Z)
	local spin = (E.rng:NextNumber() < 0.5) and 1 or -1
	local half = math.rad(a.Sweep) / 2
	local from, to = mid - spin * half, mid + spin * half
	local t0 = wormAction(E, "TailLash", nil)
	setSlot(E, 1, anchor)
	setSlot(E, 2, Vector3.new(from, to, 0)) -- (not a place: the sweep's start and end angles)
	E.motion = { from = E.pos, to = anchor, t0 = t0, t1 = t0 + a.Tell * 0.6 }
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.motion = nil
	E.pos = anchor
	-- phase two: it sweeps straight back again (Sweeps)
	local sweeps = (type(a.Sweeps) == "table" and (a.Sweeps[E.phase] or a.Sweeps[1])) or 1
	local pause = a.Pause or 0.25
	for i = 1, sweeps do
		local s0 = t0 + a.Tell + (i - 1) * (a.Time + pause)
		local f, g = from, to
		if i % 2 == 0 then
			f, g = to, from
		end
		E.lash = {
			anchor = anchor, from = f, to = g, lastYaw = f,
			t0 = s0, time = a.Time,
			reach = a.Reach, width = a.Width, height = a.Height,
			damage = a.Damage, knockback = a.Knockback, hit = {},
		}
		if not waitUntil(E, token, s0 + a.Time + ((i < sweeps) and pause or 0)) then
			return
		end
	end
	E.lash = nil
	waitUntil(E, token, now() + 0.45) -- the tail drops back under
end

-- The tail's angle `u` of the way through its sweep (eased in and out; BossClient
-- uses exactly the same curve to draw it).
local function lashYaw(L, u)
	u = math.clamp(u, 0, 1)
	return L.from + (L.to - L.from) * (u * u * (3 - 2 * u))
end

-- Every frame of a tail lash: anyone the tail swept past since last frame is
-- hit, unless they jumped over it.
local function stepLash(E, t)
	local L = E.lash
	local u = (t - L.t0) / L.time
	if u < 0 then
		return
	end
	local yaw = lashYaw(L, u)
	local spin = (L.to >= L.from) and 1 or -1
	local a1 = L.lastYaw
	L.lastYaw = yaw
	for _, p in ipairs(fightersIn(E)) do
		if not L.hit[p] then
			local root = rootOf(p)
			local off = flat(root.Position - L.anchor)
			local d = off.Magnitude
			local above = feetAbove(E, root)
			if d <= L.reach + PLAYER_RADIUS and above < L.height * 0.8 then
				local ang = math.atan2(off.X, off.Z)
				local slack = (L.width / 2 + PLAYER_RADIUS) / math.max(d, 1)
				-- how far past the tail's last position you are, the way it's sweeping
				local past = ((ang - a1) * spin + slack) % (2 * math.pi)
				if past <= (yaw - a1) * spin + 2 * slack then
					L.hit[p] = true
					local sideways = Vector3.new(math.cos(ang), 0, -math.sin(ang)) * spin
					CombatService.DamagePlayer(p, L.damage, root.Position, sideways * L.knockback + Vector3.new(0, L.knockback * 0.3, 0))
				end
			end
		end
	end
end

-- TREMOR: it thrashes underground and the whole sand floor quakes, Quakes
-- times. Anyone on stone, or in the air at the moment of a quake, is fine.
function WormAttacks.Tremor(E, token)
	local a = E.def.Attacks.Tremor
	local t0 = wormAction(E, "Tremor", nil)
	for i = 1, a.Quakes do
		if not waitUntil(E, token, t0 + a.Tell + (i - 1) * a.Gap) then
			return
		end
		for _, p in ipairs(fightersIn(E)) do
			local root = rootOf(p)
			if root and not stoneUnder(E, root.Position) and grounded(E, root, 1.2) then
				CombatService.DamagePlayer(p, a.Damage, root.Position, Vector3.new(0, a.Knockback, 0))
			elseif root and RunService:IsStudio() then
				print(string.format("[Mireworm] tremor quake %d missed %s: %s", i, p.Name, offSandReason(E, root)))
			end
		end
	end
	waitUntil(E, token, t0 + a.Tell + (a.Quakes - 1) * a.Gap + 0.5)
end

-- UNDERMINE (phase two): its quarry is hiding on stone. It circles under the
-- platform while the cracks glow, then bursts up through it: the platform is
-- gone for the rest of the fight, and so is anyone still standing on it.
function WormAttacks.Undermine(E, token)
	local a = E.def.Attacks.Undermine
	local aim = targetPosition(E)
	local st = aim and stoneUnder(E, aim)
	if not st then
		return
	end
	local center = Vector3.new(st.center.X, E.floorY, st.center.Z)
	local t0 = wormAction(E, "Undermine", st.radius)
	setSlot(E, 1, center)
	glowCracks(st)
	local edge = center + unitOr(flat(E.pos - center), E.facing) * (st.radius + 8)
	E.motion = { from = E.pos, to = edge, t0 = t0, t1 = t0 + a.Tell * 0.3 }
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.motion = nil
	breakStone(E, st)
	hitArea(E, center, st.radius, a.Damage, a.Knockback)
	wormErupt(E, token, center, recovery(E, a.Exposed))
end

-- Which attack, for where its quarry is standing. A weighted pick, like
-- Gloomgut's: the same one is less likely twice running and never three times.
local function wormChoose(E)
	local aim = targetPosition(E)
	if not aim then
		return nil
	end
	local quarryOnSand = not stoneUnder(E, aim)
	local anyOnSand = false
	for _, p in ipairs(fightersIn(E)) do
		local root = rootOf(p)
		if root and not stoneUnder(E, root.Position) then
			anyOnSand = true
			break
		end
	end
	local options, total = {}, 0
	for name, a in pairs(E.def.Attacks) do
		local ok = WormAttacks[name] ~= nil and (a.Phase or 1) <= E.phase
		if ok and a.Sand and not quarryOnSand then
			ok = false -- it can't come up through stone
		end
		if ok and name == "Breach" then
			ok = breachPlan(E) ~= nil
		elseif ok and name == "Coil" then
			-- no room for a ring if a platform is in the way
			for _, st in ipairs(E.stones or {}) do
				if not st.broken and flatDistance(st.center, aim) < st.radius + a.Radius then
					ok = false
				end
			end
		elseif ok and name == "Tremor" then
			ok = anyOnSand
		elseif ok and name == "Undermine" then
			ok = not quarryOnSand
		end
		if ok then
			local w = a.Weight or 1
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
		return x[1] < y[1]
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

-- One go round the worm's cycle: (dive) -> hunt -> strike. Returns false once
-- this fight is over (reset, killed, or the break at half health has taken over).
local function wormCycle(E, token)
	if E.phase == 1 and healthShare(E) <= E.def.PhaseAt + 1e-6 then
		if not breakShell(E, token) then
			return false
		end
	end
	if not E.under then
		if not wormDive(E, token) then
			return false
		end
	end
	if not wormHunt(E, token) then
		return false
	end
	pickQuarry(E)
	local name = wormChoose(E)
	if name then
		E.history = { name, E.history[1] }
		WormAttacks[name](E, token)
	else
		task.wait(0.2)
	end
	return true
end

-- The worm's fight: round and round the cycle. Each go is protected: if
-- anything in one attack ever errors, it's reported once in the Output and the
-- worm simply carries on with its next move, instead of freezing mid-fight.
local function wormBrain(E, token)
	clearWorm(E)
	E.under = false -- it starts every fight, and phase two, out of the sand
	E.model:SetAttribute("Submerged", false)
	while valid(E, token) and E.state ~= "Dead" do
		local ok, result = pcall(wormCycle, E, token)
		if not ok then
			if not E.warnedError then
				E.warnedError = true
				warn("[BossService] " .. E.def.Short .. " hit an error and carried on: " .. tostring(result))
			end
			clearWorm(E, true)
			E.motion = nil
			task.wait(0.3)
		elseif not result then
			return
		end
	end
end

-- Which brain an encounter runs
local function runBrain(E, token)
	if E.worm then
		wormBrain(E, token)
	else
		brain(E, token)
	end
end

----------------------------------------------------------------------
-- The worm, every frame
----------------------------------------------------------------------
-- The whirlpool (phase two): the pull toward the pit is on each player's own
-- screen; the pit at the bottom burns, here.
local function stepWhirlpool(E, t)
	local W = E.def.Whirlpool
	if not W or E.phase < 2 or E.state ~= "Fighting" or not E.sink then
		return
	end
	E.pitAt = E.pitAt or {}
	for _, p in ipairs(fightersIn(E)) do
		local root = rootOf(p)
		if flatDistance(root.Position, E.sink) <= W.PitRadius and grounded(E, root, 2)
			and t - (E.pitAt[p] or -math.huge) >= W.PitTick then
			E.pitAt[p] = t
			CombatService.DamagePlayer(p, W.PitDamage, E.sink, nil, true)
		end
	end
end

-- Movement (swimming, or following a charge or a leap exactly), facing, and
-- the attacks that are live in the world.
-- THE RUMBLE: while it swims under the sand hunting, the ground bucks in a
-- ring round it every Rumble.Every seconds. Anyone standing on sand inside
-- Rumble.Radius is hurt and jolted up (in the air, or on stone, you're fine)
-- - so get away from where it went under, keep off its ridge, or jump as the
-- sand jumps. Every screen sees the sand jump (RumbleT / RumbleP). It holds
-- off for a moment after it goes under, so whoever was just punching it has
-- time to get clear - and it stops while it makes a move (the move is the
-- danger then).
local function stepRumble(E, t)
	local R = E.def.Rumble
	local action = E.model:GetAttribute("Action")
	local lurking = E.under and E.state == "Fighting" and action == "Burrow"
	if not lurking then
		E.lurking = false
		return
	end
	if not E.lurking then
		E.lurking = true
		E.nextRumble = math.max(E.nextRumble or 0, t + 0.6)
	end
	if not R or (R.Damage or 0) <= 0 or t < (E.nextRumble or 0) then
		return
	end
	E.nextRumble = t + (R.Every or 1.1)
	E.model:SetAttribute("RumbleP", E.pos) -- (before the time: screens read the spot when the time changes)
	E.model:SetAttribute("RumbleT", t)
	local kick = R.Knockback or 26
	for _, p in ipairs(fightersIn(E)) do
		local root = rootOf(p)
		if root and flatDistance(root.Position, E.pos) <= (R.Radius or 16) and not stoneUnder(E, root.Position) and grounded(E, root, 1.2) then
			CombatService.DamagePlayer(p, R.Damage, E.pos, knockbackFrom(E.pos, root, kick * 0.5, kick))
		end
	end
end

local function stepWorm(E, dt)
	local def = E.def
	local t = now()
	watchFeet(E, t)
	listen(E, dt)
	if E.motion then
		local m = E.motion
		local u = math.clamp((t - m.t0) / math.max(m.t1 - m.t0, 1e-3), 0, 1)
		E.pos = m.from:Lerp(m.to, u)
		setMoving(E, false)
	elseif E.swim then
		local aim = E.swim.to or targetPosition(E)
		local moved = false
		if aim then
			local gap = flat(aim - E.pos)
			if gap.Magnitude > 0.5 then
				local step = math.min(E.swim.speed * dt, gap.Magnitude)
				local rate = math.rad(def.TurnSpeed[E.phase] or def.TurnSpeed[1])
				E.facing = turnToward(E.facing, gap.Unit, rate * dt)
				if gap.Magnitude > 14 then
					-- far off: it swims the way it faces, so it curves after you
					E.pos = E.pos + E.facing * step
				else
					-- close: straight at you
					E.pos = E.pos + gap.Unit * step
				end
				moved = true
			end
		end
		-- it can't swim through stone: it slides round the edge
		for _, st in ipairs(E.stones or {}) do
			if not st.broken then
				local off = flat(E.pos - st.center)
				local minD = st.radius + 3
				if off.Magnitude < minD then
					E.pos = Vector3.new(st.center.X, E.floorY, st.center.Z) + unitOr(off, E.facing) * minD
				end
			end
		end
		setMoving(E, moved)
	else
		setMoving(E, false)
		-- out of the sand: it turns to keep facing its quarry
		local aim = E.track and targetPosition(E)
		if aim then
			local want = flat(aim - E.pos)
			if want.Magnitude > 0.5 then
				local rate = math.rad(def.TurnSpeed[E.phase] or def.TurnSpeed[1]) * 0.5
				E.facing = turnToward(E.facing, want.Unit, rate * dt)
			end
		end
	end
	if E.pos.X ~= E.pos.X or E.pos.Z ~= E.pos.Z then
		E.pos, E.motion, E.swim = E.home, nil, nil -- (a broken position: back to the middle)
	end
	E.pos = inLeash(E, E.pos, 0)
	stepRumble(E, t)
	place(E)
	-- the moment it was here (every screen glides it smoothly between these;
	-- see glideWorm in BossClient)
	E.model:SetAttribute("PosT", t)
	if E.coil then
		stepCoil(E, t)
	end
	if E.lash then
		stepLash(E, t)
	end
	stepWhirlpool(E, t)
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
		runBrain(E, token)
	end)
end

-- back to sleep: everyone who was fighting it is dead or gone
local function reset(E)
	E.token = E.token + 1
	local token = E.token
	E.waves, E.puddles = {}, {}
	E.motion, E.sweep, E.track, E.chase, E.target = nil, nil, false, false, nil
	if E.worm then
		-- every platform whole again, and it forgets everything it heard
		clearWorm(E)
		restoreStones(E)
		E.noise, E.pitAt = {}, {}
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
		if E.worm then
			E.model:SetAttribute("PosT", now()) -- (home again: every screen puts it there)
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
	if E.worm then
		clearWorm(E)
		E.model:SetAttribute("Submerged", false)
	end
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
	-- (the worm's is lower: most of it is under the sand, and you have to be able
	-- to punch it from down in a crater or the whirlpool's bowl)
	local height = def.Size * ((def.Body == "Worm") and 0.5 or 0.85)

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
		worm = def.Body == "Worm", -- fights from under the sand (wormBrain)
	}
	E.pos = E.home
	E.facing = E.homeFacing
	place(E)
	model.Parent = Workspace
	CollectionService:AddTag(model, "Boss")
	setState(E, "Dormant")
	setAction(E, "Dormant", nil)

	if E.worm then
		E.under = true
		E.noise = {}
		-- the pit at the middle (the whirlpool in phase two)
		for _, h in ipairs(CollectionService:GetTagged("DuneSinkhole")) do
			if h:GetAttribute("Floor") == floorId and h:IsA("BasePart") then
				E.sink = Vector3.new(h.Position.X, floorY, h.Position.Z)
			end
		end
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

	local wormWarned = false
	RunService.Heartbeat:Connect(function(dt)
		for _, E in pairs(encounters) do
			if E.worm then
				-- (protected: if anything in the worm's step ever errors, Gloomgut
				-- and the rest of the frame carry on regardless)
				local ok, err = pcall(function()
					if E.state ~= "Dormant" and E.state ~= "Dead" then
						stepWorm(E, dt)
					end
				end)
				if not ok and not wormWarned then
					wormWarned = true
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

-- For tests and tools: the live encounter on a floor.
function BossService.Encounter(floorId)
	return encounters[floorId]
end

-- For tests: run one attack by name right now.
BossService._Attacks = Attacks
BossService._WormAttacks = WormAttacks

return BossService
