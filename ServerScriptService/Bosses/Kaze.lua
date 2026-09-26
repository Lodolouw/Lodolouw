--[[
	Kaze  (ModuleScript, parent: ServerScriptService > Bosses, name: "Kaze")

	Floor 4's boss: Kaze, the Headband Hero (Config.Bosses[4]) - a wandering
	martial artist who fights like a fighting-game character. He has his own
	brain (Boss.brain), because a fighter thinks about more than distance:

	  THE KI METER  three bars (the blue meter at the bottom of your screen).
	                It fills when his hits land on you, when you punch thin
	                air near him (CombatService.OnWhiff), a little all the
	                time, and fast while he meditates. Each SPECIAL costs a
	                bar; a full meter means his SUPER.
	  CANCELS       he can cut a move short into another: a punch string into
	                a special, a fake charge into a dash, a hop back out of a
	                special that missed, and (round 2) one special straight into
	                another. Each costs one of the cancels he has this round;
	                when they run out he's TIRED - wide open - then they refill.
	  CHARGING      now and then he holds a special before letting it go: the
	                longer, the bigger. Punch him while he glows to break it.

	His moves (the numbers are in Config.Bosses[4].Attacks):
	  PUNCH STRING   jab, straight, heavy - each stepping in; may cancel into a special
	  DASH IN        a dash at you, straight into a punch string
	  KAZE-BLAST!    a ball of ki along the floor: jump it or roll it (a pillar stops it)
	  RISING DRAGON! a spinning uppercut straight up: back off, punish the landing
	  TORNADO KICK!  spins across the dojo along a lane: roll through, or get out of it
	  KI FOCUS       meditates, his meter shooting up: rush him and break it
	  FAKE CHARGE    looks like a Kaze-Blast charging... cancels into a dash in
	  SUPER!         (full meter) leaps to the middle and sweeps a giant beam
	                 round the red fan: hide behind a pillar, get out of the
	                 fan, or roll through it. The pillars it hits crumble.
	  TIRED          out of cancels: hands on his knees, panting (free hits)
	  STAGGER        his charge or focus broken by your punches
	 ROUND 2 (half health): the meter fills twice as fast, he chains specials,
	 has more cancels and stays tired longer - and the pillars are back.

	KI FLARE: once a round (Config's SuperAt: at 70% health, then at 25%),
	his meter flares straight to MAX - every round has at least one Super.

	Published on his model (besides BossService's own): Ki (the meter, 0-300),
	Cancels (how many he has left), CancelAt / CancelKind (the moment and
	kind of his last cancel - every screen flashes white), WhiffAt (you fed
	his meter by missing), KiHitAt (a punch knocked his meter down while he
	charged or meditated), KiFlareAt (his meter flared to MAX). Each move publishes its spots with setSlot (see
	each one below) and, for a special, how long he charged it in ActN.

	The four pillars are the arena's (DojoBuilder, tagged "DojoPillar"): this
	file breaks them (the beam) and mends them (round 2, or a reset).
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Boss = {}

-- The shared helpers these moves use, from BossService (see Boss.init)
local now, flat, flatDistance, unitOr, rootOf, fightersIn
local setAction, setSlot, waitUntil, valid, hitArea, recovery, targetPosition, healthShare, knockbackFrom
local pickTarget, breakShell, stepMovement
local CombatService, PLAYER_RADIUS, STAND_HEIGHT

local live = {} -- [E] = true: every Kaze fight there is (your missed punches feed them)
local whiffHooked = false

----------------------------------------------------------------------
-- Little helpers
----------------------------------------------------------------------
-- a pair { not charged, fully charged } at charge `k` (0-1); a plain number stays as it is
local function byCharge(v, k)
	if type(v) == "table" then
		return v[1] + (v[2] - v[1]) * k
	end
	return v
end

-- a pair { round 1, round 2 } for the round he's in
local function byRound(E, v)
	if type(v) == "table" then
		return v[E.phase] or v[1]
	end
	return v
end

local function ground(E)
	return Vector3.new(E.pos.X, E.floorY, E.pos.Z)
end

-- how far he can go from `from` along `dir` before leaving the circle of
-- radius `r` round the middle of the dojo
local function toEdge(E, from, dir, r)
	local o = flat(from - E.home)
	local b = o:Dot(dir)
	local c = o:Dot(o) - r * r
	local disc = b * b - c
	if disc < 0 then
		return 0
	end
	return math.max(0, -b + math.sqrt(disc))
end

-- how far from `from` along `dir` to the dojo's walls (the floor is a square)
local function toWall(E, from, dir)
	local half = E.half or 62
	local best = math.huge
	local o = from - E.home
	for _, axis in ipairs({ "X", "Z" }) do
		local d = dir[axis]
		if math.abs(d) > 1e-4 then
			local wallAt = (d > 0) and half or -half
			local t = (wallAt - o[axis]) / d
			if t >= 0 and t < best then
				best = t
			end
		end
	end
	return best == math.huge and 0 or best
end

-- How high he is `e` seconds into a jump: up fast (slowing at the top) for
-- `rise` of the `air` seconds, held for `hang` more, then down faster and
-- faster. (BossBodies/Kaze draws him with exactly the same sum.)
local function jumpHeight(e, air, rise, height, hang)
	hang = hang or 0
	if e <= 0 then
		return 0
	end
	local up = air * rise
	if e < up then
		local u = e / up
		return height * (1 - (1 - u) * (1 - u))
	end
	if e < up + hang then
		return height
	end
	local v = math.min((e - up - hang) / math.max(air - up, 1e-3), 1)
	return height * (1 - v * v)
end

local function airHeight(E, t)
	local arc = E.arc
	if not arc then
		return 0
	end
	return jumpHeight(t - arc.t0, arc.air, arc.rise, arc.height, arc.hang)
end

----------------------------------------------------------------------
-- The pillars (cover from the beam and his fireballs)
----------------------------------------------------------------------
local function findPillars(E)
	local list = {}
	for _, pm in ipairs(CollectionService:GetTagged("DojoPillar")) do
		if pm:GetAttribute("Floor") == E.floor then
			local core = pm:FindFirstChild("PillarCore") or pm.PrimaryPart
			if core then
				local c = core.Position
				table.insert(list, {
					model = pm,
					center = Vector3.new(c.X, E.floorY, c.Z),
					radius = pm:GetAttribute("Radius") or 3.5,
					index = pm:GetAttribute("Index") or (#list + 1),
					broken = false,
				})
			end
		end
	end
	table.sort(list, function(a, b)
		return a.index < b.index
	end)
	return list
end

-- a pillar smashed (its heap of rubble shows) or whole again
local function setPillarBroken(pl, broken)
	pl.broken = broken
	local pm = pl.model
	if not (pm and pm.Parent) then
		return
	end
	pm:SetAttribute("Broken", broken)
	for _, d in ipairs(pm:GetDescendants()) do
		if d:IsA("BasePart") then
			if d:GetAttribute("Whole") then
				d.Transparency = broken and 1 or (d:GetAttribute("BaseTransparency") or 0)
				d.CanCollide = (not broken) and d:GetAttribute("BaseCollide") ~= false
			elseif d:GetAttribute("Rubble") then
				d.Transparency = broken and 0 or 1
			end
		elseif d:IsA("PointLight") then
			d.Enabled = not broken
		end
	end
end

local function mendPillars(E)
	for _, pl in ipairs(E.pillars or {}) do
		if pl.broken or (pl.model and pl.model:GetAttribute("Broken")) then
			setPillarBroken(pl, false)
		end
	end
end

-- The first standing pillar in the way from `a` to `b` (on the ground plane),
-- and how far along the way its edge is - or nil if the way is clear. `pad`
-- makes the pillars that much fatter (for something wide, like a fireball).
local function pillarInWay(E, a, b, pad)
	local d = flat(b - a)
	local len = d.Magnitude
	if len < 1e-3 then
		return nil
	end
	local dir = d / len
	local best, bestAt = nil, math.huge
	for _, pl in ipairs(E.pillars or {}) do
		if not pl.broken then
			local rel = flat(pl.center - a)
			local along = rel:Dot(dir)
			local r = pl.radius + (pad or 0)
			if along > 0 then
				local side = (rel - dir * along).Magnitude
				if side < r then
					local edge = along - math.sqrt(r * r - side * side)
					if edge < len and edge < bestAt then
						best, bestAt = pl, math.max(0, edge)
					end
				end
			end
		end
	end
	return best, best and bestAt or nil
end

-- a lane from `from` along `dir`, `want` long, cut short by the edge of his
-- ground (`r` round the middle) and by any pillar (fattened by `pad`)
local function laneLength(E, from, dir, want, r, pad)
	local len = math.min(want, toEdge(E, from, dir, r))
	local pl, at = pillarInWay(E, from, from + dir * len, pad)
	if pl then
		len = math.min(len, math.max(0, at - 0.5))
	end
	return len, pl
end

----------------------------------------------------------------------
-- The ki meter and the cancels
----------------------------------------------------------------------
local function kiMax(E)
	return E.def.Ki.Bar * E.def.Ki.Bars
end

local function publishKi(E)
	local shown = math.floor(E.ki + 0.5)
	if shown ~= E.kiShown then
		E.kiShown = shown
		E.model:SetAttribute("Ki", shown)
	end
end

-- adds to his meter (round 2 fills it Phase2 times as fast, unless `plain`)
local function gainKi(E, amount, plain)
	local mult = (not plain and E.phase >= 2) and (E.def.Ki.Phase2 or 1) or 1
	E.ki = math.clamp((E.ki or 0) + amount * mult, 0, kiMax(E))
	publishKi(E)
end

local function bars(E)
	return math.floor((E.ki or 0) / E.def.Ki.Bar + 1e-6)
end

local function spendBar(E)
	gainKi(E, -E.def.Ki.Bar, true)
end

local function setCancels(E, n)
	E.cancels = n
	E.model:SetAttribute("Cancels", n)
end

-- he cuts a move short: one cancel gone, and every screen flashes white
local function cancelNow(E, kind)
	setCancels(E, math.max(0, (E.cancels or 0) - 1))
	E.model:SetAttribute("CancelKind", kind)
	E.model:SetAttribute("CancelAt", now())
end

-- his hits landing fill his meter
local function landed(E, n)
	if n > 0 then
		gainKi(E, E.def.Ki.Hit * n)
	end
	return n
end

----------------------------------------------------------------------
-- Hitting players
----------------------------------------------------------------------
-- A punch: everyone within `reach` in front of him (a wedge `arc` degrees
-- wide round the way he faces) - and anyone right up against him.
local function hitFront(E, reach, arc, damage, knockback)
	local cosHalf = math.cos(math.rad(arc / 2))
	local n = 0
	for _, p in ipairs(fightersIn(E)) do
		local root = rootOf(p)
		if root then
			local off = flat(root.Position - E.pos)
			local d = off.Magnitude
			local above = root.Position.Y - (E.floorY + STAND_HEIGHT)
			if above < 9 and d <= reach + PLAYER_RADIUS and (d < E.def.Size / 2 + PLAYER_RADIUS or off.Unit:Dot(E.facing) >= cosHalf) then
				if CombatService.DamagePlayer(p, damage, E.pos, knockbackFrom(E.pos, root, knockback)) then
					n = n + 1
				end
			end
		end
	end
	return landed(E, n)
end

-- The rising uppercut: everyone within `radius` of him and below his fist
-- (it catches you in the air too), once each.
local function hitRising(E, radius, damage, knockback, struck)
	local n = 0
	local top = E.floorY + STAND_HEIGHT + airHeight(E, now()) + 9
	for _, p in ipairs(fightersIn(E)) do
		if not struck[p] then
			local root = rootOf(p)
			if root and flatDistance(root.Position, E.pos) <= radius + PLAYER_RADIUS and root.Position.Y <= top then
				struck[p] = true
				if CombatService.DamagePlayer(p, damage, E.pos, knockbackFrom(E.pos, root, knockback, knockback * 0.8)) then
					n = n + 1
				end
			end
		end
	end
	return landed(E, n)
end

----------------------------------------------------------------------
-- Waiting while he charges or meditates: your punches can break it
----------------------------------------------------------------------
-- Like waitUntil, but it stops early - returning "broken" - if punches broke
-- his charge (or focus) meanwhile.
local function waitGuarded(E, token, t)
	while now() < t do
		if not valid(E, token) then
			return false
		end
		if E.guardBroken then
			return "broken"
		end
		task.wait()
	end
	if not valid(E, token) then
		return false
	end
	return E.guardBroken and "broken" or true
end

-- STAGGER: his charge or focus broken - reeling, open
local function stagger(E, token)
	local C = E.def.Charge
	E.charging, E.focusing, E.guardBroken = false, false, false
	E.track, E.chase, E.motion, E.arc = false, false, nil, nil
	local t0 = setAction(E, "Stagger", C.Stagger)
	waitUntil(E, token, t0 + C.Stagger)
end

-- The charge at the start of a special (only when `hold` > 0): he glows,
-- humming higher. Returns true when he lets go, false if the fight moved on,
-- "broken" if your punches broke it (he's staggered by then).
local function charge(E, token, t0, hold)
	if hold <= 0 then
		return true
	end
	E.charging, E.guardHits, E.guardBroken = true, 0, false
	local r = waitGuarded(E, token, t0 + hold)
	E.charging = false
	if r == "broken" then
		stagger(E, token)
		return "broken"
	end
	return r
end

-- how charged a special is (0-1), from how long he held it
local function chargeLevel(E, hold)
	return math.clamp((hold or 0) / E.def.Charge.Time[2], 0, 1)
end

----------------------------------------------------------------------
-- The moves (each needs an entry of the same name in Config's Attacks)
----------------------------------------------------------------------
local Attacks = {}
Boss.Attacks = Attacks
local SPECIALS = { KazeBlast = true, RisingDragon = true, TornadoKick = true }

-- A DASH toward `toward`, stopping short of it (and of any pillar): slot 1
-- = where he starts, slot 2 = where he stops. No hit of its own.
local function dash(E, token, toward)
	local D = E.def.Movement.Dash
	local from = ground(E)
	local dir = unitOr(flat(toward - from), E.facing)
	local want = math.min(D.Distance, math.max(0, flatDistance(toward, from) - (E.def.Size / 2 + 4)))
	local len = laneLength(E, from, dir, want, E.def.Leash, 2)
	local to = from + dir * len
	E.track, E.chase = false, false
	E.facing = dir
	local t0 = setAction(E, "Dash", nil)
	setSlot(E, 1, from)
	setSlot(E, 2, to)
	E.motion = { from = from, to = to, t0 = t0, t1 = t0 + D.Time }
	if not waitUntil(E, token, t0 + D.Time) then
		return false
	end
	E.motion = nil
	E.pos = to
	return true
end

-- A HOP BACK away from his target (out of a special that missed): slot 1 =
-- take-off, slot 2 = landing.
local function backHop(E, token)
	local H = E.def.Movement.BackHop
	local from = ground(E)
	local aim = targetPosition(E)
	local away = aim and unitOr(flat(from - aim), -E.facing) or -E.facing
	local len = laneLength(E, from, away, H.Distance, E.def.Leash, 2)
	local to = from + away * len
	E.track, E.chase = false, false
	local t0 = setAction(E, "BackHop", nil)
	setSlot(E, 1, from)
	setSlot(E, 2, to)
	E.arc = { t0 = t0, air = H.Time, rise = 0.5, height = H.Height, hang = 0 }
	E.motion = { from = from, to = to, t0 = t0, t1 = t0 + H.Time }
	if not waitUntil(E, token, t0 + H.Time) then
		return false
	end
	E.motion, E.arc = nil, nil
	E.pos = to
	return true
end

-- Which special suits this distance (for a cancel or a chain), not `except`
local function pickSpecial(E, except)
	local aim = targetPosition(E)
	local d = aim and flatDistance(aim, E.pos) or 20
	local order
	if d <= 11 then
		order = { "RisingDragon", "TornadoKick", "KazeBlast" }
	elseif d <= 40 then
		order = (E.rng:NextNumber() < 0.5) and { "TornadoKick", "KazeBlast" } or { "KazeBlast", "TornadoKick" }
	else
		order = { "KazeBlast", "TornadoKick" }
	end
	for _, name in ipairs(order) do
		if name ~= except then
			return name
		end
	end
	return nil
end

-- After a special: in round 2 he may CHAIN straight into another special;
-- if it missed he may HOP BACK out of it; otherwise he stands there open
-- until `t1` + `rec` (your chance). Both cost a cancel.
local function afterSpecial(E, token, name, t1, rec, missed)
	if not valid(E, token) then
		return
	end
	local chain = byRound(E, E.def.Chain) or 0
	if not E.chaining and chain > 0 and (E.cancels or 0) > 0 and bars(E) >= 1 and E.rng:NextNumber() < chain then
		local nextMove = pickSpecial(E, name)
		if nextMove then
			cancelNow(E, "Chain")
			E.chaining = true
			Attacks[nextMove](E, token, { chained = true })
			E.chaining = false
			return
		end
	end
	if missed and (E.cancels or 0) > 0 and E.rng:NextNumber() < (E.def.Movement.BackHop.Chance or 0) then
		cancelNow(E, "BackHop")
		if backHop(E, token) then
			waitUntil(E, token, now() + 0.25)
		end
		return
	end
	waitUntil(E, token, t1 + rec)
end

-- PUNCH STRING: jab, straight, heavy. Before each hit he slides a step in
-- toward you, turning to face you until a blink before it lands (slot i =
-- the spot straight ahead his fist aims at, so every screen draws the wedge
-- exactly where it hits). After the first or second hit he may CANCEL into
-- a special - more likely if the hit landed.
function Attacks.PunchString(E, token, opts)
	opts = opts or {}
	local a = E.def.Attacks.PunchString
	E.track, E.chase = true, false
	local t0 = setAction(E, "PunchString", nil)
	local t = t0
	for i = 1, 3 do
		local tHit = t + a.Tells[i]
		local from = ground(E)
		local aim = targetPosition(E)
		local dir = aim and unitOr(flat(aim - from), E.facing) or E.facing
		local want = aim and math.min(a.Step, math.max(0, flatDistance(aim, from) - (E.def.Size / 2 + 2.5))) or a.Step
		local len = laneLength(E, from, dir, want, E.def.Leash, 1)
		local to = from + dir * len
		E.motion = { from = from, to = to, t0 = t + a.Tells[i] * 0.3, t1 = tHit - 0.05 }
		if not waitUntil(E, token, tHit - 0.12) then
			return
		end
		E.track = false
		setSlot(E, i, ground(E) + E.facing * a.Reach)
		if not waitUntil(E, token, tHit) then
			return
		end
		E.motion = nil
		E.pos = to
		local hits = hitFront(E, a.Reach, a.Arc, a.Damage[i], a.Knockback[i])
		if i < 3 and not opts.noCancel and (E.cancels or 0) > 0 then
			local chance = a.CancelChance * ((hits > 0) and 1.4 or 0.6)
			if bars(E) >= 1 then
				-- into a special
				if E.rng:NextNumber() < chance then
					local special = pickSpecial(E, nil)
					if special then
						cancelNow(E, "String")
						Attacks[special](E, token, { fromString = true })
						return
					end
				end
			elseif E.rng:NextNumber() < chance * 0.5 then
				-- (no ki for a special: into a hop back instead, out of your reach)
				cancelNow(E, "BackHop")
				if backHop(E, token) then
					waitUntil(E, token, now() + 0.2)
				end
				return
			end
		end
		E.track = true
		t = tHit
	end
	waitUntil(E, token, t + recovery(E, a.Recovery))
end

-- DASH IN: a dash at you, then a punch string
function Attacks.DashIn(E, token)
	local aim = targetPosition(E) or (ground(E) + E.facing * 12)
	if not dash(E, token, aim) then
		return
	end
	Attacks.PunchString(E, token)
end

-- KAZE-BLAST!: a ball of ki rolled along the floor. ActN = how long he
-- charged it. He turns to face you until just before he lets go; slot 1 =
-- where the ball starts, slot 2 = where it stops (a wall, or a pillar it
-- bursts on). It hits whoever it rolls over - unless they jump it or roll.
function Attacks.KazeBlast(E, token, opts)
	opts = opts or {}
	local a = E.def.Attacks.KazeBlast
	local hold = opts.hold or 0
	E.track, E.chase = true, false
	local t0 = setAction(E, "KazeBlast", hold)
	local c = charge(E, token, t0, hold)
	if c ~= true then
		return
	end
	local k = chargeLevel(E, hold)
	local tR = t0 + hold + a.Tell
	if not waitUntil(E, token, tR - 0.12) then
		return
	end
	E.track = false
	if not waitUntil(E, token, tR) then
		return
	end
	spendBar(E)
	local radius, height = byCharge(a.Radius, k), byCharge(a.Height, k)
	local speed = byCharge(a.Speed, k)
	local damage, knock = byCharge(a.Damage, k), byCharge(a.Knockback, k)
	local dir = E.facing
	local from = ground(E) + dir * (E.def.Size / 2 + 1)
	local len = math.min(a.Reach, toWall(E, from, dir) + 2)
	local pl, at = pillarInWay(E, from, from + dir * len, radius * 0.5)
	if pl then
		len = math.max(1, at or len)
	end
	local to = from + dir * len
	setSlot(E, 1, from)
	setSlot(E, 2, to)
	local launch = tR
	task.spawn(function()
		local struck = {}
		while valid(E, token) do
			local gone = (now() - launch) * speed
			if gone > len then
				return
			end
			local p = from + dir * math.max(gone, 0)
			for _, pl2 in ipairs(fightersIn(E)) do
				if not struck[pl2] then
					local root = rootOf(pl2)
					if root and flatDistance(root.Position, p) <= radius + PLAYER_RADIUS
						and root.Position.Y - (E.floorY + STAND_HEIGHT) < height * 0.8 then
						struck[pl2] = true
						if CombatService.DamagePlayer(pl2, damage, p, knockbackFrom(p, root, knock)) then
							landed(E, 1)
						end
					end
				end
			end
			task.wait()
		end
	end)
	-- (whether it'll hit isn't known yet: he never hops back out of a blast)
	afterSpecial(E, token, "KazeBlast", tR, recovery(E, a.Recovery), false)
end

-- RISING DRAGON!: a crouch (the red ring round him fills in), then a
-- spinning uppercut straight up, drifting a little toward you. ActN = how
-- long he charged it; slot 1 = take-off, slot 2 = landing. The rising fist
-- hurts for a.Active seconds; then he falls and lands - open.
function Attacks.RisingDragon(E, token, opts)
	opts = opts or {}
	local a = E.def.Attacks.RisingDragon
	local hold = opts.hold or 0
	E.track, E.chase = true, false
	local t0 = setAction(E, "RisingDragon", hold)
	local c = charge(E, token, t0, hold)
	if c ~= true then
		return
	end
	local k = chargeLevel(E, hold)
	local tA = t0 + hold + a.Tell
	if not waitUntil(E, token, tA) then
		return
	end
	E.track = false
	spendBar(E)
	local radius, height, air = byCharge(a.Radius, k), byCharge(a.Height, k), byCharge(a.Air, k)
	local damage, knock = byCharge(a.Damage, k), byCharge(a.Knockback, k)
	local A = ground(E)
	local aim = targetPosition(E)
	local dir = aim and unitOr(flat(aim - A), E.facing) or E.facing
	local fwd = aim and math.min(a.Forward, flatDistance(aim, A)) or a.Forward
	local len = laneLength(E, A, dir, fwd, E.def.Leash, 1)
	local B = A + dir * len
	E.facing = dir
	setSlot(E, 1, A)
	setSlot(E, 2, B)
	E.arc = { t0 = tA, air = air, rise = 0.42, height = height, hang = 0 }
	E.motion = { from = A, to = B, t0 = tA, t1 = tA + air }
	local struck, hits = {}, 0
	while now() < tA + a.Active do
		if not valid(E, token) then
			return
		end
		hits = hits + hitRising(E, radius, damage, knock, struck)
		task.wait()
	end
	if not waitUntil(E, token, tA + air) then
		return
	end
	E.motion, E.arc = nil, nil
	E.pos = B
	afterSpecial(E, token, "RisingDragon", tA + air, recovery(E, byCharge(a.Recovery, k)), hits == 0)
end

-- TORNADO KICK!: a hop, and he spins across the dojo along a lane. ActN =
-- how long he charged it. The lane follows the way he faces until Commit of
-- the wind-up, then locks: slot 1 = from, slot 2 = to (cut short by the edge
-- of his ground or a pillar). Anyone he spins into is hit (once).
function Attacks.TornadoKick(E, token, opts)
	opts = opts or {}
	local a = E.def.Attacks.TornadoKick
	local hold = opts.hold or 0
	E.track, E.chase = true, false
	local t0 = setAction(E, "TornadoKick", hold)
	local c = charge(E, token, t0, hold)
	if c ~= true then
		return
	end
	local k = chargeLevel(E, hold)
	local tR = t0 + hold
	if not waitUntil(E, token, tR + a.Tell * a.Commit) then
		return
	end
	E.track = false
	local from = ground(E)
	local dir = E.facing
	local len = laneLength(E, from, dir, byCharge(a.Distance, k), E.def.Leash, a.Radius * 0.6)
	if len < 8 then
		-- (no room to spin that way: a Kaze-Blast instead)
		Attacks.KazeBlast(E, token, { chained = opts.chained })
		return
	end
	local to = from + dir * len
	local speed = byCharge(a.Speed, k)
	local travel = len / speed
	setSlot(E, 1, from)
	setSlot(E, 2, to)
	local start = tR + a.Tell
	if not waitUntil(E, token, start) then
		return
	end
	spendBar(E)
	local damage, knock = byCharge(a.Damage, k), byCharge(a.Knockback, k)
	E.arc = { t0 = start, air = travel + 0.2, rise = 0.12, height = a.Hop, hang = travel * 0.75 }
	E.motion = { from = from, to = to, t0 = start, t1 = start + travel }
	local struck, hits = {}, 0
	while now() < start + travel do
		if not valid(E, token) then
			return
		end
		hits = hits + landed(E, hitArea(E, E.pos, a.Radius, damage, knock, struck))
		task.wait()
	end
	E.motion = nil
	E.pos = to
	if not waitUntil(E, token, start + travel + 0.2) then
		return
	end
	E.arc = nil
	afterSpecial(E, token, "TornadoKick", start + travel + 0.2, recovery(E, a.Recovery), hits == 0)
end

-- KI FOCUS: feet planted, "HAAAA..." - his meter shoots up. Every punch you
-- land knocks it down; Charge.Breaks of them break it (he staggers). He
-- stops early if the meter's full. ActN = the longest he'll meditate.
function Attacks.KiFocus(E, token)
	local a = E.def.Attacks.KiFocus
	E.track, E.chase = false, false
	local t0 = setAction(E, "KiFocus", a.Time)
	E.focusing, E.guardHits, E.guardBroken = true, 0, false
	local last = now()
	while now() < t0 + a.Time do
		if not valid(E, token) then
			E.focusing = false
			return
		end
		if E.guardBroken then
			stagger(E, token)
			return
		end
		local t = now()
		gainKi(E, E.def.Ki.Focus * (t - last))
		last = t
		if E.ki >= kiMax(E) then
			break
		end
		task.wait()
	end
	E.focusing = false
end

-- FAKE CHARGE: charges exactly like a Kaze-Blast (ActN = how long)... then
-- cancels it with a white flash into a dash and a punch string. With no
-- cancel left to fake with, it's a real Kaze-Blast.
function Attacks.FakeCharge(E, token)
	local a = E.def.Attacks.FakeCharge
	if (E.cancels or 0) <= 0 then
		Attacks.KazeBlast(E, token, {})
		return
	end
	local hold = a.Hold[1] + E.rng:NextNumber() * (a.Hold[2] - a.Hold[1])
	E.track, E.chase = true, false
	local t0 = setAction(E, "FakeCharge", hold)
	if charge(E, token, t0, hold) ~= true then
		return
	end
	cancelNow(E, "Fake")
	Attacks.DashIn(E, token)
end

-- Is someone in the beam right now? The beam runs from `origin` along `dir`,
-- Length long and Width wide. A standing pillar between the beam's source
-- and a player shields them.
local function beamHits(E, origin, dir, a, struck)
	for _, p in ipairs(fightersIn(E)) do
		if not struck[p] then
			local root = rootOf(p)
			if root then
				local rel = flat(root.Position - origin)
				local along = rel:Dot(dir)
				local across = (rel - dir * along).Magnitude
				if along > 0 and along <= a.Length and across <= a.Width / 2 + PLAYER_RADIUS then
					if not pillarInWay(E, origin, root.Position, 0) then
						struck[p] = true
						if CombatService.DamagePlayer(p, a.Damage, origin, knockbackFrom(origin, root, a.Knockback)) then
							landed(E, 1)
						end
					end
				end
			end
		end
	end
end

-- SUPER!: he leaps to the middle of the dojo (slot 1), glows and turns to
-- follow you while the red fan on the floor follows too - until Lock of the
-- wind-up, when the fan's middle is fixed (slot 2) and which way the beam
-- will sweep (ActN: +1 or -1). Then the beam sweeps across the fan. It takes
-- his whole meter. Every standing pillar inside the fan crumbles once it's
-- passed. Then he's exhausted (a long opening).
function Attacks.Super(E, token)
	local a = E.def.Attacks.Super
	E.lastSuper = now()
	E.track, E.chase = false, false
	local t0 = setAction(E, "Super", nil)
	local center = Vector3.new(E.home.X, E.floorY, E.home.Z)
	local from = ground(E)
	setSlot(E, 1, center)
	E.arc = { t0 = t0, air = a.Leap, rise = 0.5, height = 12, hang = 0 }
	E.motion = { from = from, to = center, t0 = t0, t1 = t0 + a.Leap }
	if not waitUntil(E, token, t0 + a.Leap) then
		return
	end
	E.motion, E.arc = nil, nil
	E.pos = center
	E.track = true
	E.supering = true
	if not waitUntil(E, token, t0 + a.Tell * a.Lock) then
		E.supering = false
		return
	end
	E.track = false
	local aim = targetPosition(E)
	local dir = aim and unitOr(flat(aim - center), E.facing) or E.facing
	E.facing = dir
	local sign = (E.rng:NextNumber() < 0.5) and -1 or 1
	E.model:SetAttribute("ActN", sign)
	setSlot(E, 2, center + dir * 20)
	local tF = t0 + a.Tell
	if not waitUntil(E, token, tF) then
		E.supering = false
		return
	end
	gainKi(E, -kiMax(E), true)
	local half = math.rad(a.Sweep / 2)
	local base = math.atan2(dir.X, dir.Z)
	local struck = {}
	while now() < tF + a.SweepTime do
		if not valid(E, token) then
			E.supering = false
			return
		end
		local u = math.clamp((now() - tF) / a.SweepTime, 0, 1)
		local ang = base + sign * (-half + 2 * half * u)
		local beam = Vector3.new(math.sin(ang), 0, math.cos(ang))
		E.facing = beam
		beamHits(E, center, beam, a, struck)
		task.wait()
	end
	-- the pillars the beam swept over crumble
	for _, pl in ipairs(E.pillars or {}) do
		if not pl.broken then
			local rel = flat(pl.center - center)
			local d = rel.Magnitude
			local diff = (math.atan2(rel.X, rel.Z) - base + math.pi) % (2 * math.pi) - math.pi
			local spread = (d > 0.1) and math.asin(math.min(1, pl.radius / d)) or math.pi
			if d <= a.Length + pl.radius and math.abs(diff) <= half + spread then
				setPillarBroken(pl, true)
			end
		end
	end
	E.supering = false
	waitUntil(E, token, tF + a.SweepTime + recovery(E, a.Recovery))
end

-- TIRED: out of cancels - hands on his knees, panting (not a move he
-- chooses: it comes on its own). ActN = how long. Then his cancels refill.
local function tired(E, token)
	local T = byRound(E, E.def.Tired)
	E.track, E.chase = false, false
	local t0 = setAction(E, "Tired", T)
	if not waitUntil(E, token, t0 + T) then
		return false
	end
	setCancels(E, byRound(E, E.def.Cancels))
	return true
end

----------------------------------------------------------------------
-- His brain
----------------------------------------------------------------------
-- A weighted pick among his moves that suit this distance and his meter.
-- (Specials need a bar; meditating is likelier with an empty meter and
-- pointless with a full one; the same move is less likely twice running.)
local function choose(E, dist, aim)
	local options, total = {}, 0
	local haveBar = bars(E) >= 1
	local full = (E.ki or 0) >= kiMax(E) - 1e-6
	local blocked = aim and pillarInWay(E, ground(E), aim, 1) ~= nil
	for name, a in pairs(E.def.Attacks) do
		local w = a.Weight or 0
		if dist < a.Range[1] or dist > a.Range[2] then
			w = 0
		end
		if SPECIALS[name] and not haveBar then
			w = 0
		end
		if name == "KiFocus" then
			if full then
				w = 0
			elseif not haveBar then
				w = w * 2
			elseif bars(E) >= 2 then
				w = w + 1.5 -- (nearly there: he wants his Super)
			end
		elseif name == "FakeCharge" and (E.cancels or 0) <= 0 then
			w = 0
		elseif blocked and (name == "KazeBlast" or name == "TornadoKick") then
			w = w * 0.3 -- (a pillar's in the way)
		end
		if E.history[1] == name then
			w = (E.history[2] == name) and 0 or w * 0.4
		end
		if w > 0 then
			options[#options + 1] = { name, w }
			total = total + w
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

-- One go round: think, move, breathe. Returns false once this fight is over
-- (reset, killed, or the break at half health has taken over).
local function cycle(E, token)
	if E.phase == 1 and healthShare(E) <= E.def.PhaseAt + 1e-6 then
		if not breakShell(E, token) then
			return false
		end
	end
	local target = pickTarget(E)
	local aim = target and targetPosition(E)
	if not aim then
		E.chase, E.track = false, false
		task.wait(0.2)
		return valid(E, token)
	end
	if (E.cancels or 0) <= 0 then
		return tired(E, token) and valid(E, token)
	end
	-- the KI FLARE: once a round, low enough on health, his meter flares to MAX
	E.flared = E.flared or {}
	local flareAt = byRound(E, E.def.SuperAt)
	if flareAt and not E.flared[E.phase] and healthShare(E) <= flareAt + 1e-6 then
		E.flared[E.phase] = true
		gainKi(E, kiMax(E), true)
		E.model:SetAttribute("KiFlareAt", now())
		E.lastSuper = nil -- (and nothing stops the Super it's for)
	end
	local name
	local S = E.def.Attacks.Super
	if (E.ki or 0) >= kiMax(E) - 1e-6 and now() - (E.lastSuper or -math.huge) >= (S.Cooldown or 0) then
		name = "Super"
	else
		name = choose(E, flatDistance(aim, E.pos), aim)
	end
	if not name then
		-- nothing suits: close in for a moment and think again
		E.chase, E.track = true, true
		waitUntil(E, token, now() + 0.3)
		return valid(E, token)
	end
	E.history = { name, E.history[1] }
	local opts = {}
	if SPECIALS[name] and E.rng:NextNumber() < byRound(E, E.def.Charge.Chance) then
		local C = E.def.Charge
		opts.hold = C.Time[1] + E.rng:NextNumber() * (C.Time[2] - C.Time[1])
	end
	Attacks[name](E, token, opts)
	if not valid(E, token) then
		return false
	end
	if (E.cancels or 0) <= 0 then
		if not tired(E, token) then
			return false
		end
	end
	-- breathe: his stance, shuffling after you
	local b = byRound(E, E.def.Breather)
	E.chase, E.track = true, true
	setAction(E, "Idle", nil)
	waitUntil(E, token, now() + b[1] + E.rng:NextNumber() * (b[2] - b[1]))
	return valid(E, token)
end

local function clearMoves(E)
	E.charging, E.focusing, E.guardBroken, E.chaining, E.supering = false, false, false, false, false
	E.motion, E.arc, E.sweep = nil, nil, nil
end

-- Kaze's fight: round and round the cycle. Each go is protected: if anything
-- in one move ever errors, it's reported once in the Output and he carries on
-- with his next move, instead of freezing mid-fight.
function Boss.brain(E, token)
	clearMoves(E)
	if E.cancels == nil then
		setCancels(E, byRound(E, E.def.Cancels))
	end
	while valid(E, token) and E.state ~= "Dead" do
		local ok, result = pcall(cycle, E, token)
		if not ok then
			if not E.warnedError then
				E.warnedError = true
				warn("[BossService] " .. E.def.Short .. " hit an error and carried on: " .. tostring(result))
			end
			clearMoves(E)
			task.wait(0.3)
		elseif not result then
			return
		end
	end
end

----------------------------------------------------------------------
-- Every frame: moving (BossService's own), and a trickle of ki
----------------------------------------------------------------------
local NO_TRICKLE = { Tired = true, Stagger = true, KiFocus = true, Super = true }
function Boss.step(E, dt)
	stepMovement(E, dt)
	if E.state == "Fighting" and not NO_TRICKLE[E.model:GetAttribute("Action") or ""] then
		gainKi(E, E.def.Ki.Passive * dt)
	end
end

-- He can't walk through a pillar: walking into one, he steps round it
-- (toward whichever side his target is on).
function Boss.onMove(E, dt)
	if E.motion then
		return -- (a dash or a spin: its lane already stops short of the pillars)
	end
	local keep = E.def.Size / 2 * 0.8
	for _, pl in ipairs(E.pillars or {}) do
		if not pl.broken then
			local off = flat(E.pos - pl.center)
			local need = pl.radius + keep
			if off.Magnitude < need then
				local out = unitOr(off, -E.facing)
				local pos = pl.center + out * need
				-- (sidestep round it, toward the side his target is on)
				local aim = E.chase and targetPosition(E)
				if aim then
					local tangent = Vector3.new(-out.Z, 0, out.X)
					local side = flat(aim - pl.center):Dot(tangent) >= 0 and 1 or -1
					local speed = byRound(E, E.def.MoveSpeed)
					pos = pos + tangent * side * speed * dt * 0.8
				end
				E.pos = Vector3.new(pos.X, E.floorY, pos.Z)
			end
		end
	end
end

----------------------------------------------------------------------
-- Your punches: missing feeds his meter; hitting him while he charges or
-- meditates knocks it down (and a couple break it)
----------------------------------------------------------------------
local function onWhiff(player, position)
	if typeof(position) ~= "Vector3" then
		return
	end
	for E in pairs(live) do
		if E.state == "Fighting" and player:GetAttribute("SpireFloor") == E.floor
			and flatDistance(position, E.pos) <= E.def.Ki.WhiffRange then
			gainKi(E, E.def.Ki.Whiff)
			E.model:SetAttribute("WhiffAt", now())
		end
	end
end

local function onPunched(E, damage)
	if (tonumber(damage) or 0) <= 0 then
		return
	end
	if E.charging or E.focusing then
		E.guardHits = (E.guardHits or 0) + 1
		gainKi(E, -E.def.Ki.FocusHit, true)
		E.model:SetAttribute("KiHitAt", now())
		if E.guardHits >= E.def.Charge.Breaks then
			E.guardBroken = true
		end
	end
end

----------------------------------------------------------------------
-- Hooks (see BossService: they run at these moments)
----------------------------------------------------------------------
function Boss.init(kit)
	now, flat, flatDistance, unitOr, rootOf, fightersIn = kit.now, kit.flat, kit.flatDistance, kit.unitOr, kit.rootOf, kit.fightersIn
	setAction, setSlot, waitUntil, valid = kit.setAction, kit.setSlot, kit.waitUntil, kit.valid
	hitArea, recovery, targetPosition, healthShare, knockbackFrom = kit.hitArea, kit.recovery, kit.targetPosition, kit.healthShare, kit.knockbackFrom
	pickTarget, breakShell, stepMovement = kit.pickTarget, kit.breakShell, kit.stepMovement
	CombatService, PLAYER_RADIUS, STAND_HEIGHT = kit.CombatService, kit.PLAYER_RADIUS, kit.STAND_HEIGHT
	-- your missed punches (only if this CombatService can tell us about them)
	if not whiffHooked and CombatService and type(CombatService.OnWhiff) == "function" then
		whiffHooked = true
		CombatService.OnWhiff(onWhiff)
	end
end

-- Built: the pillars found, his meter empty, and CombatService told where
-- his body really is (high in a Rising Dragon he's out of your reach)
function Boss.onBuild(E)
	E.pillars = findPillars(E)
	local arena = nil
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("Floor") == E.floor and child:GetAttribute("Half") then
			arena = child
		end
	end
	E.half = arena and arena:GetAttribute("Half") or 62
	E.ki, E.kiShown = 0, nil
	publishKi(E)
	setCancels(E, E.def.Cancels[1])
	live[E] = true
	CombatService.SetTargetShape(E.model, function(_from)
		local up = airHeight(E, now())
		return Vector3.new(E.pos.X, E.floorY + up + E.height / 2, E.pos.Z), E.def.Size / 2
	end)
	local onHit = E.model:FindFirstChild("OnHit")
	if onHit then
		onHit.Event:Connect(function(_player, damage)
			onPunched(E, damage)
		end)
	end
end

-- Everyone left or died: meditating at home again, the pillars whole, his
-- meter empty
function Boss.onReset(E)
	clearMoves(E)
	E.ki = 0
	publishKi(E)
	setCancels(E, E.def.Cancels[1])
	E.lastSuper, E.flared = nil, nil
	mendPillars(E)
end

-- ROUND 2: the pillars are back, and he has more cancels (his meter carries over)
function Boss.onBreak(E)
	clearMoves(E)
	setCancels(E, byRound(E, E.def.Cancels))
	mendPillars(E)
end

function Boss.onDie(E)
	clearMoves(E)
	E.ki = 0
	publishKi(E)
end

-- (for tests and BossBodies: the same jump sum, and the pillar sums)
Boss.jumpHeight = jumpHeight
Boss._pillarInWay = pillarInWay
Boss._tired = tired
Boss._stagger = stagger

return Boss
