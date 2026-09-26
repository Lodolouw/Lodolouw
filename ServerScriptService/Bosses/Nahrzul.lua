--[[
	Nahrzul  (ModuleScript, parent: ServerScriptService > Bosses, name: "Nahrzul")

	Floor 2's boss: Nahrzul, Devourer of the Dunes (Config.Bosses[2], Body =
	"Worm") - "Mireworm" in older code. It doesn't fight like a surface boss at
	all, so its whole way of fighting lives here: it swims under the sand and
	hunts by sound, bursts up to strike (ambush, breach, coil, devour, tail
	lash, tremor, and undermine in phase two), cracks the stone platforms, and
	in phase two opens a whirlpool in the pit. BossService still runs the
	encounter itself: waking up, the phase change at half health, resetting,
	dying and the rewards - and calls the hooks at the bottom of this file.

	HOW A BOSS FILE WORKS (see _Template.lua for a new one):
	  * BossService finds this file by the boss's short name in Config
	    (Short = "Nahrzul") and calls Boss.init(kit) once, handing over the
	    shared helpers (setAction, waitUntil, hitArea, fightersIn, ...).
	  * The hooks it provides (all optional for a boss):
	      Boss.Attacks           its attacks by name (tests run them one at a time)
	      Boss.brain(E, token)   its own way of fighting (instead of the
	                             shared surface-boss brain)
	      Boss.step(E, dt)       every frame (instead of the shared movement,
	                             waves and puddles)
	      Boss.onBuild(E) / onReset(E) / onHome(E) / onDie(E) / onBreak(E)
	                             extras when it's built, starts resetting, is
	                             back home asleep, dies, and when its armour
	                             cracks at half health
	  * Attributes it publishes for each player's screen (BossClient +
	    ReplicatedStorage/BossBodies/Nahrzul): Submerged, ActT, PosT, Odo,
	    Humps, RumbleT / RumbleP, as well as the shared ones.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Boss = {}

-- The shared helpers it uses, from BossService (see Boss.init)
local CombatService
local now, flat, flatDistance, unitOr, rootOf, turnToward, fightersIn
local setAction, setSlot, setMoving, place, valid, waitUntil
local stoneUnder, besideStone, knockbackFrom, hitArea, healthShare, recovery
local targetPosition, makeTarget, breakShell
local PLAYER_RADIUS, SLOTS

function Boss.init(kit)
	CombatService = kit.CombatService
	now, flat, flatDistance, unitOr, rootOf, turnToward, fightersIn = kit.now, kit.flat, kit.flatDistance, kit.unitOr, kit.rootOf, kit.turnToward, kit.fightersIn
	setAction, setSlot, setMoving, place, valid, waitUntil = kit.setAction, kit.setSlot, kit.setMoving, kit.place, kit.valid, kit.waitUntil
	stoneUnder, besideStone, knockbackFrom, hitArea, healthShare, recovery = kit.stoneUnder, kit.besideStone, kit.knockbackFrom, kit.hitArea, kit.healthShare, kit.recovery
	targetPosition, makeTarget, breakShell = kit.targetPosition, kit.makeTarget, kit.breakShell
	PLAYER_RADIUS, SLOTS = kit.PLAYER_RADIUS, kit.SLOTS
end

----------------------------------------------------------------------
-- Its half-finished business
----------------------------------------------------------------------
-- Mireworm's half-finished business (a coil closing, a tail mid-sweep...),
-- dropped when the fight turns, it dies or it goes back to sleep. Does nothing
-- for Gloomgut.
local function clearWorm(E)
	if not E.worm then
		return
	end
	E.swim, E.coil, E.lash, E.circle = nil, nil, nil, nil
	E.model:SetAttribute("ActT", nil)
end

----------------------------------------------------------------------
-- MIREWORM: THE HUNTER UNDER THE SAND  (any boss with Body = "Worm")
----------------------------------------------------------------------
-- Gloomgut fights on the surface and trades blows with you. Mireworm doesn't:
-- it swims under the sand and comes up to strike. Wherever you can see it -
-- its head, its body, the ridge of its back through the sand - you can punch
-- it (its whole body is its hitbox: see bodyNear). Its fight goes round and
-- round like this:
--
--     hunt (under the sand)  ->  strike  ->  up out of the sand  ->  dive
--
-- * It hunts whoever is making the most noise (see listen below).
-- * While it hunts under the sand, the ground bucks round its ridge and hurts
--   (the rumble: stepRumble).
-- * In phase two the caved-in seal becomes a whirlpool, and it starts
--   bursting up through the platforms people hide on.
-- None of Gloomgut's attacks are used; its own are in WormAttacks below.
local WormAttacks = {}

-- Out of the sand (true) or under it (false). Either way you can punch it:
-- its head and neck when it's up, the ridge of its back through the sand
-- when it's under - and all through a dive.
local function surface(E, up)
	E.under = not up
	E.model:SetAttribute("Submerged", not up)
	E.model:SetAttribute("Invulnerable", false)
	makeTarget(E, true)
end

-- setAction, plus clearing the worm's own extra timing attribute
local function wormAction(E, name, number)
	E.model:SetAttribute("ActT", nil)
	E.diving, E.lie, E.coilRest = nil, nil, nil -- (each move's hitbox: see bodyNear)
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

-- Head-first back under the sand: it arches over and plunges into the sand a
-- little way in front of it (DIVE_AHEAD - never into stone), its body pouring
-- in after its head, and it carries on from there. You can still land a hit
-- in the first half.
local DIVE_AHEAD = 18
local HUMP_EVERY = 62 -- (studs it swims between arches of its back: see growHumps)
local function wormDive(E, token)
	local H = E.def.Hunt
	E.track, E.motion, E.swim = false, nil, nil
	local into = sandSpot(E, E.pos + E.facing * DIVE_AHEAD, E.pos, 4)
	local t0 = wormAction(E, "Dive", H.DiveTime)
	setSlot(E, 1, into) -- (every screen draws it plunging in here)
	E.diving = { from = E.pos, to = into, t0 = t0, T = H.DiveTime }
	E.lastHump = (E.odo or 0) - HUMP_EVERY * 0.5 -- (its back arches up soon after it goes under)
	E.motion = { from = E.pos, to = into, t0 = t0, t1 = t0 + H.DiveTime }
	if not waitUntil(E, token, t0 + H.DiveTime * 0.5) then
		return false
	end
	surface(E, false)
	local ok = waitUntil(E, token, t0 + H.DiveTime)
	E.motion = nil
	return ok
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
	E.lie, E.humpsUntil = nil, t0 + tell -- (its back arches as it lines up, under the sand)
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
	-- (lying in its trench: its hitbox is its body along the trench - see bodyNear)
	E.lie = { A = A, dir = dir, len = flatDistance(A, B), BL = a.BodyLength, slide = last and a.Slide or a.Slide * 0.5 }
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
	E.lie.slideAt = now()
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
	-- it circles you under the sand (every screen draws it where it really is)
	E.circle = { C = C, r = a.Radius, t0 = t0, speed = math.pi * 2 * 0.94 / a.Tell }
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.circle = nil
	E.pos = C
	E.coil = { center = C, t0 = t0 + a.Tell, a = a, next = {} }
	if not waitUntil(E, token, t0 + a.Tell + a.Close) then
		return
	end
	E.coil = nil
	hitArea(E, C, a.Crush + a.Wall / 2, a.Damage, a.Knockback)
	E.coilRest = { C = C, r = a.Crush, g = a.Wall + 2 } -- (lying coiled: see bodyNear)
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
			anchor = anchor, from = f, to = g, lastU = 0,
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

-- Where the tail is, `u` of the way through its sweep, at `x` of the way out
-- along it (0 = where it comes up out of the sand, 1 = its tip). It's a whip:
-- the sweep eases in and out, and the far end trails behind - most in the
-- middle of the swing - then catches up as the swing ends. (BossClient draws
-- exactly this curve - lashAngle there - so what hits you is what you see.
-- The trailing never makes any part of it swing backwards.)
local function lashAngle(from, to, u, x)
	u = math.clamp(u, 0, 1)
	local span = to - from
	local trail = 0.13 * math.abs(span) * x ^ 1.6 * (4 * u * (1 - u)) ^ 2
	return from + span * (u * u * (3 - 2 * u)) - ((span >= 0) and trail or -trail)
end

-- Every frame of a tail lash: anyone the tail swept past since last frame is
-- hit, unless they jumped over it. (Where the tail was is worked out at YOUR
-- distance from where it comes up, so its trailing tip is exactly as late
-- reaching you as it looks.)
local function stepLash(E, t)
	local L = E.lash
	local u = (t - L.t0) / L.time
	if u < 0 then
		return
	end
	u = math.min(u, 1)
	local u0 = L.lastU or 0
	L.lastU = u
	local spin = (L.to >= L.from) and 1 or -1
	for _, p in ipairs(fightersIn(E)) do
		if not L.hit[p] then
			local root = rootOf(p)
			local off = flat(root.Position - L.anchor)
			local d = off.Magnitude
			local above = feetAbove(E, root)
			if d <= L.reach + PLAYER_RADIUS and above < L.height * 0.8 then
				local x = math.min(d / L.reach, 1)
				local a1 = lashAngle(L.from, L.to, u0, x)
				local yaw = lashAngle(L.from, L.to, u, x)
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
	E.circle = { C = center, r = st.radius + 8, t0 = t0, speed = 3.2 } -- (round under the platform)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.circle = nil
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

-- ITS BODY, FOR PUNCHES. You can hit whatever of it you can see, where you
-- see it - and nothing else. So for each thing it does, its hitbox is the
-- shape BossClient draws it in:
--   * swimming: only the arches of its back breaking the sand. Where those
--     arches come up is decided HERE (growHumps) and sent to every screen
--     ("Humps", in "Odo" - how far it has swum), so what you see is exactly
--     what you can hit. Its body under the sand between them can't be hit.
--   * up out of the sand (bursting up, its armour cracking): its body
--     standing out of the hole
--   * diving: the arc from the hole it stood in to the one it plunges into,
--     emptying as it pours in
--   * lying in its trench after a breach: its body along the trench,
--     shortening as it slides away
--   * lying coiled: the ring, and its head in the middle
--   * the tail lash: just its tail, whipping round (lashAngle)
-- When none of it is showing, there's nothing to hit.
local BODY_LEN, HUMP_LEN = 100, 38 -- (the same as BossClient's: nose to tail, one arch)

-- the path its head has come along, measured in studs swum (its "odometer")
local function trackBody(E)
	local tr = E.trail
	local last = tr and tr[#tr]
	if not last or (last.p - E.pos).Magnitude > 40 then
		E.trail = { { p = E.pos, d = 0 } } -- (it came up somewhere else: start afresh)
		E.humps, E.lastHump, E.odo = {}, nil, 0
		return
	end
	E.odo = last.d + (E.pos - last.p).Magnitude
	if E.odo - last.d >= 2 then
		tr[#tr + 1] = { p = E.pos, d = E.odo }
		while #tr > 2 and E.odo - tr[2].d > BODY_LEN + HUMP_LEN do
			table.remove(tr, 1)
		end
	end
end

-- where the path was `odo` studs into it (on the sand)
local function trailPoint(E, odo)
	local tr = E.trail
	if odo >= (tr[#tr].d) then
		return E.pos
	end
	for i = #tr, 2, -1 do
		if tr[i - 1].d <= odo then
			local a, b = tr[i - 1], tr[i]
			return a.p:Lerp(b.p, (odo - a.d) / math.max(b.d - a.d, 1e-3))
		end
	end
	return tr[1].p
end

-- Arches of its back as it swims: a new one every so often (more often when
-- it's closing in), fixed where they come up - its body threads through each.
local function growHumps(E, t)
	E.humps = E.humps or {}
	local odo = E.odo or 0
	local changed = false
	for i = #E.humps, 1, -1 do
		if odo - E.humps[i] > BODY_LEN + HUMP_LEN then
			table.remove(E.humps, i)
			changed = true
		end
	end
	local act = E.model:GetAttribute("Action")
	local every = nil
	if E.under then
		if act == "Burrow" then
			every = HUMP_EVERY
		elseif act == "Ambush" and E.model:GetAttribute("ActA") == nil then
			every = 42 -- (racing after you)
		elseif act == "Breach" and t < (E.humpsUntil or 0) then
			every = 30 -- (lining up to leap)
		elseif act == "Coil" and E.circle then
			every = 24 -- (circling you)
		elseif act == "Undermine" and E.circle then
			every = 26 -- (circling under the platform)
		end
	end
	if every and odo - (E.lastHump or -math.huge) >= every then
		E.lastHump = odo
		E.humps[#E.humps + 1] = odo + 1
		changed = true
	end
	if changed then
		local list = {}
		for i, h in ipairs(E.humps) do
			list[i] = string.format("%.1f", h)
		end
		E.model:SetAttribute("Humps", table.concat(list, ","))
	end
end

-- the nearest point to `from` on the flat line a-b
local function nearestOn(a, b, from)
	local ab = flat(b - a)
	local len = ab.Magnitude
	if len < 0.01 then
		return a
	end
	return a + ab / len * math.clamp(flat(from - a):Dot(ab / len), 0, len)
end

local function bodyNear(E, from)
	local t = now()
	local act = E.model:GetAttribute("Action")
	local best, bestGap, radius = nil, math.huge, 0
	local function consider(point, r)
		local gap = flatDistance(from, point) - r
		if gap < bestGap then
			best, bestGap, radius = Vector3.new(point.X, E.floorY + 3, point.Z), gap, r
		end
	end
	local thick = E.def.Size * 0.32 -- (half its girth)
	if act == "Erupt" or act == "Break" then
		consider(nearestOn(E.pos, E.pos + E.facing * 10, from), thick)
	elseif act == "Dive" and E.diving then
		local D = E.diving
		local k = (t - D.t0) / D.T
		if k < 0.75 then
			consider(nearestOn(D.from, D.to, from), thick * 0.9)
		elseif k < 1 then
			consider(D.to, thick * 0.7)
		end
	elseif act == "Breach" and E.lie then
		local L = E.lie
		local head = L.len
		if L.slideAt then
			head = L.len + math.clamp((t - L.slideAt) / L.slide, 0, 1) * (L.BL + 12)
		end
		local x0, x1 = math.max(head - L.BL, 0), math.min(head, L.len)
		if x1 > x0 then
			consider(nearestOn(L.A + L.dir * x0, L.A + L.dir * x1, from), thick * 0.9)
		end
	elseif act == "Coil" and E.coilRest and not E.coil then
		local c = E.coilRest
		local off = flat(from - c.C)
		local dir = off.Magnitude > 0.01 and off.Unit or E.facing
		consider(c.C + dir * c.r, c.g / 2)
		consider(c.C, c.g * 0.6) -- (its head, struck down in the middle)
	elseif act == "TailLash" and E.lash then
		local L = E.lash
		local u = math.clamp((t - L.t0) / L.time, 0, 1)
		for i = 1, 10 do
			local x = i / 10
			local yaw = lashAngle(L.from, L.to, u, x)
			consider(L.anchor + Vector3.new(math.sin(yaw), 0, math.cos(yaw)) * (x * L.reach), x < 0.35 and 5 or 2.5)
		end
	end
	-- the arches of its back, where they break the sand (only the middle of
	-- each arch is above it)
	if E.under and E.trail and E.humps then
		local odo = E.odo or 0
		for _, h in ipairs(E.humps) do
			local lo = math.max(h + HUMP_LEN / 6, odo - BODY_LEN)
			local hi = math.min(h + HUMP_LEN * 5 / 6, odo)
			local x = lo
			while x <= hi do
				consider(trailPoint(E, x), thick * 0.8)
				x = x + 3
			end
		end
	end
	if not best then
		return E.pos - Vector3.new(0, 1000, 0), 0 -- (nothing of it showing: nothing to hit)
	end
	return best, radius
end

local function stepWorm(E, dt)
	local def = E.def
	local t = now()
	watchFeet(E, t)
	listen(E, dt)
	if E.circle then
		-- circling a spot under the sand: from wherever it was, out (or in) onto
		-- the circle over a moment, and round
		local c = E.circle
		if not c.ang0 then
			local off = flat(E.pos - c.C)
			c.ang0 = off.Magnitude > 1 and math.atan2(off.X, off.Z) or math.atan2(E.facing.X, E.facing.Z)
			c.r0 = off.Magnitude
		end
		local e = t - c.t0
		local k = math.clamp(e / 0.3, 0, 1)
		local r = c.r0 + (c.r - c.r0) * (k * k * (3 - 2 * k))
		local ang = c.ang0 + e * c.speed
		E.pos = c.C + Vector3.new(math.sin(ang), 0, math.cos(ang)) * r
		E.facing = Vector3.new(math.cos(ang), 0, -math.sin(ang))
		setMoving(E, true)
	elseif E.motion then
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
	trackBody(E)
	growHumps(E, t)
	stepRumble(E, t)
	-- where it is, for every screen: 30 times a second is plenty (each screen
	-- glides it smoothly between these - see glideWorm in BossClient - and
	-- every hit here uses E.pos itself, every frame), with the moment it was
	-- there. A jump (it came up somewhere else) goes out at once.
	local jumped = E.placedPos and (E.pos - E.placedPos).Magnitude > 4
	if jumped or t - (E.placedAt or -1) >= 1 / 30 then
		E.placedAt, E.placedPos = t, E.pos
		place(E)
		E.model:SetAttribute("Odo", E.odo or 0) -- (before the time: screens read both together)
		E.model:SetAttribute("PosT", t)
	end
	if E.coil then
		stepCoil(E, t)
	end
	if E.lash then
		stepLash(E, t)
	end
	stepWhirlpool(E, t)
end

----------------------------------------------------------------------
-- The hooks BossService calls (see the top of this file)
----------------------------------------------------------------------
Boss.Attacks = WormAttacks
Boss.brain = wormBrain
Boss.step = stepWorm

-- when it's built: it starts under the sand, and its whole body is its hitbox
function Boss.onBuild(E)
	local model, def, floorId, floorY = E.model, E.def, E.floor, E.floorY
	E.under = true
	E.noise = {}
	model:SetAttribute("IFrames", def.IFrames) -- (CombatService: hits shrugged off after each one)
	-- its whole body is its hitbox, not just its middle (see bodyNear)
	if CombatService and CombatService.SetTargetShape then
		CombatService.SetTargetShape(model, function(from)
			return bodyNear(E, from)
		end)
	end
	-- the pit at the middle (the whirlpool in phase two)
	for _, h in ipairs(CollectionService:GetTagged("DuneSinkhole")) do
		if h:GetAttribute("Floor") == floorId and h:IsA("BasePart") then
			E.sink = Vector3.new(h.Position.X, floorY, h.Position.Z)
		end
	end
end

-- going back to sleep: every platform whole again, and it forgets everything it heard
function Boss.onReset(E)
	clearWorm(E)
	restoreStones(E)
	E.noise, E.pitAt, E.trail, E.humps = {}, {}, nil, {}
	E.model:SetAttribute("Humps", "")
end

-- home again, asleep: every screen puts it there
function Boss.onHome(E)
	E.model:SetAttribute("PosT", now())
end

function Boss.onDie(E)
	clearWorm(E)
	E.model:SetAttribute("Submerged", false)
end

-- its armour cracks at half health (it's always out of the sand when this
-- happens: you only hurt it out there)
function Boss.onBreak(E)
	clearWorm(E)
	E.under = false
	E.model:SetAttribute("Submerged", false)
end

return Boss
