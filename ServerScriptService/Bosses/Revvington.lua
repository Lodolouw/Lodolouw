--[[
	Revvington  (ModuleScript, parent: ServerScriptService > Bosses, name: "Revvington")

	Floor 5's boss: Speedy Revvington, King of the Speedway (Config.Bosses[5])
	- a cocky orange muscle car in a DRIVE-BY DUEL. Like a knight on horseback: he
	charges at you, drives past swinging his tail, rears up, skids round and
	charges again. He has his own brain (Boss.brain) and his own every-frame
	step (Boss.step): he never walks - everything he does is DRIVING, a chain
	of segments (lines, arcs, skid turns on the spot) published with
	ReplicatedStorage/CarPath, so every screen draws him exactly where he is.

	His moves (the numbers are in Config.Bosses[5].Attacks):
	  CHARGE        skids round to face you, revs (the red lane follows you,
	                then locks), roars down it past you, brakes and turns
	                round slowly (your chance). Into the tyre wall: CRASH, dizzy.
	                TURBO: twice in a row.
	  TAIL WHIP     drives by close beside you and whips his tail round at you
	  WHEELIE SLAM  (you're in front, close) rears up and slams down; a shock
	                ring rolls out (jump it)
	  HONK          (in front) a blast of sound that throws you back
	  BACKFIRE      (behind him) BANG - fire behind him, burning puddles
	  SIDE BUMP     (beside him) hops sideways at you - BONK!
	  DONUTS        showing off for the crowd: free hits
	  BURNOUT RING  (TURBO) circles you leaving a ring of fire, then dashes
	                through the middle at you
	  CRUISE        between moves: circling you like a shark, or driving off to
	                get room - harmless (you can't walk through him, though)

	His body is a box (Config's Car: Length x Width x Height) round his middle,
	facing the way he faces: his hits (the car running into you) and yours
	(CombatService.SetTargetShape: the nearest point of the box) both use it.
	Everything round the track uses the arena's shape (a capsule: every spot
	within Edge of the line from x = -Spine to +Spine; SpeedwayBuilder).

	Published on his model (besides BossService's own): the segment he's
	driving (SegK, SegT0, SegDur, SegA, SegB, SegC, SegE, SegBack, SegId -
	see CarPath), each move's spots in its slots (see each move), and
	RaceStart (the moment of GO!, for the race clock on players' screens).
	A drive whose start matters (a charge, the drive-by, the ring, the dash)
	is published a moment BEFORE it starts: CarPath keeps him still until
	then, and every screen already has it when he sets off.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CarPath = require(ReplicatedStorage:WaitForChild("CarPath"))

local Boss = {}

-- The shared helpers these moves use, from BossService (see Boss.init)
local now, flat, flatDistance, unitOr, rootOf, fightersIn
local setAction, setSlot, waitUntil, valid, recovery, targetPosition, healthShare, knockbackFrom
local pickTarget, breakShell, place, stepWaves, stepPuddles
local CombatService, PLAYER_RADIUS, STAND_HEIGHT

----------------------------------------------------------------------
-- Little helpers
----------------------------------------------------------------------
-- a pair { round 1, TURBO } for the round he's in
local function byRound(E, v)
	if type(v) == "table" then
		return v[E.phase] or v[1]
	end
	return v
end

local function ground(E)
	return Vector3.new(E.pos.X, E.floorY, E.pos.Z)
end

-- the way to his right, from the way he faces
local function rightOf(dir)
	return Vector3.new(-dir.Z, 0, dir.X)
end

-- THE TRACK'S SHAPE: how far a spot is from the line down the track's
-- middle (x from -Spine to +Spine, through the centre)
local function spineDist(E, p)
	local rel = p - E.center
	local x = math.clamp(rel.X, -E.spine, E.spine)
	return Vector3.new(rel.X - x, 0, rel.Z).Magnitude
end

-- a spot pulled in to within `r` of that line (on the floor)
local function pullIn(E, p, r)
	local rel = p - E.center
	local x = math.clamp(rel.X, -E.spine, E.spine)
	local off = Vector3.new(rel.X - x, 0, rel.Z)
	if off.Magnitude > r then
		off = off.Unit * r
	end
	return Vector3.new(E.center.X + x + off.X, E.floorY, E.center.Z + off.Z)
end

-- how far he can go from `from` along `dir` before he's further than `r`
-- from the line (the track's shape has no dents, so a halving search finds it)
local function toEdge(E, from, dir, r)
	if spineDist(E, from) > r then
		return 0
	end
	local lo, hi = 0, 600
	for _ = 1, 32 do
		local mid = (lo + hi) / 2
		if spineDist(E, from + dir * mid) <= r then
			lo = mid
		else
			hi = mid
		end
	end
	return lo
end

-- where the target is from him: how far, and Front / Side / Rear
local function relOf(E, aim)
	local off = flat(aim - E.pos)
	local d = off.Magnitude
	local c = d > 0.01 and off.Unit:Dot(E.facing) or 1
	local where = "Side"
	if c >= math.cos(math.rad(55)) then
		where = "Front"
	elseif c <= math.cos(math.rad(125)) then
		where = "Rear"
	end
	return d, where
end

----------------------------------------------------------------------
-- Driving: segments (see ReplicatedStorage/CarPath)
----------------------------------------------------------------------
local function setSeg(E, seg)
	E.segId = (E.segId or 0) + 1
	E.seg = seg
	CarPath.write(E.model, seg, E.segId)
end

-- stand still where he is (a spin that doesn't turn), from `t`
local function holdSeg(E, t, dur)
	return { kind = "Spin", t0 = t, dur = dur or 0.05, a = ground(E), b = Vector3.new(CarPath.angleOf(E.facing), 0, 0), c = Vector3.new(), ease = "lin" }
end

-- drives a segment to its end; false if the fight moved on meanwhile
local function run(E, token, seg)
	setSeg(E, seg)
	return waitUntil(E, token, seg.t0 + seg.dur)
end

-- a skid round on the spot to face `dir`, at `rateDeg` degrees a second
-- (sliding `slide` studs as he goes); returns the segment and how long it takes
local function spinSeg(E, t0, dir, rateDeg, slide, least)
	local h0 = CarPath.angleOf(E.facing)
	local turn = CarPath.turnBetween(h0, CarPath.angleOf(dir))
	local dur = math.max(least or 0.2, math.abs(turn) / math.rad(rateDeg))
	return { kind = "Spin", t0 = t0, dur = dur, a = ground(E), b = Vector3.new(h0, turn, 0), c = slide or Vector3.new(), ease = "io" }, dur
end

-- a straight drive to `to` whose top speed is `speed` (the time it takes
-- depends on how it speeds up or slows down: `ease`)
local function lineSeg(E, t0, to, speed, ease)
	local from = ground(E)
	local len = flatDistance(to, from)
	local k = 1
	if ease == "in" or ease == "out" then
		k = 2
	elseif ease == "io" then
		k = 1.5
	end
	local dur = math.max(0.12, len / math.max(speed, 1) * k)
	return { kind = "Line", t0 = t0, dur = dur, a = from, b = Vector3.new(to.X, E.floorY, to.Z), c = Vector3.new(), ease = ease or "lin", h = CarPath.angleOf(E.facing) }, dur
end

-- skid round to face `dir` (if he isn't already) at the round's spin rate
local function faceTo(E, token, dir, mult)
	local turn = math.abs(CarPath.turnBetween(CarPath.angleOf(E.facing), CarPath.angleOf(dir)))
	if turn < math.rad(6) then
		return true
	end
	local seg = spinSeg(E, now(), dir, byRound(E, E.def.Drive.SpinRate) * (mult or 1))
	return run(E, token, seg)
end

-- stand still (revving, recovering...) until `t`
local function holdUntil(E, token, t)
	local s = now()
	if t > s then
		setSeg(E, holdSeg(E, s, t - s))
	end
	return waitUntil(E, token, t)
end

----------------------------------------------------------------------
-- Hitting players
----------------------------------------------------------------------
-- The car running into people: anyone inside his body's box (and not
-- jumping clear over it) is hit once per `contact`, thrown off to the side
-- he hit them from and on in the way he's going.
local function carHits(E, contact)
	local car = E.def.Car
	local fwd = E.facing
	local right = rightOf(fwd)
	for _, p in ipairs(fightersIn(E)) do
		if not contact.struck[p] then
			local root = rootOf(p)
			if root then
				local rel = flat(root.Position - E.pos)
				local above = root.Position.Y - (E.floorY + STAND_HEIGHT)
				if math.abs(rel:Dot(fwd)) <= car.Length / 2 + PLAYER_RADIUS and math.abs(rel:Dot(right)) <= car.Width / 2 + PLAYER_RADIUS
					and above < car.Height then
					contact.struck[p] = true
					local side = (rel:Dot(right) >= 0) and right or -right
					local push = unitOr(side * 0.7 + fwd * 0.7, side) * contact.knockback + Vector3.new(0, contact.knockback * 0.35, 0)
					CombatService.DamagePlayer(p, contact.damage, E.pos, push)
				end
			end
		end
	end
end

-- everyone within `reach` of `origin` in a cone `arc` degrees wide round `dir`
local function hitCone(E, origin, dir, reach, arc, damage, knockback, struck)
	local cosHalf = math.cos(math.rad(arc / 2))
	for _, p in ipairs(fightersIn(E)) do
		if not (struck and struck[p]) then
			local root = rootOf(p)
			if root then
				local off = flat(root.Position - origin)
				local d = off.Magnitude
				if d <= reach + PLAYER_RADIUS and (d < 2 or off.Unit:Dot(dir) >= cosHalf) then
					if struck then
						struck[p] = true
					end
					CombatService.DamagePlayer(p, damage, origin, knockbackFrom(origin, root, knockback))
				end
			end
		end
	end
end

-- everyone within `radius` of `center` on the `side` half (and a little over the line)
local function hitHalf(E, center, side, radius, damage, knockback, struck)
	for _, p in ipairs(fightersIn(E)) do
		if not (struck and struck[p]) then
			local root = rootOf(p)
			if root then
				local off = flat(root.Position - center)
				if off.Magnitude <= radius + PLAYER_RADIUS and off:Dot(side) > -2.5 then
					if struck then
						struck[p] = true
					end
					CombatService.DamagePlayer(p, damage, center, knockbackFrom(center, root, knockback))
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- The moves (each needs an entry of the same name in Config's Attacks)
----------------------------------------------------------------------
local Attacks = {}
Boss.Attacks = Attacks

-- After a charge or a dash: brake in a skid (sliding on, turning part of the
-- way round), then turn round slowly to face you: his opening. `crash` =
-- he hit the tyre wall instead: dizzy for CrashStun first.
local function stopAndTurn(E, token, a, dir, crash)
	local t = now()
	if crash then
		E.contact = nil
		if not holdUntil(E, token, t + a.CrashStun) then
			return false
		end
	else
		local slide = math.min(a.BrakeSlide, toEdge(E, ground(E), dir, E.def.Leash))
		local aim = targetPosition(E) or (ground(E) - dir * 20)
		local want = unitOr(flat(aim - E.pos), -dir)
		local h0 = CarPath.angleOf(E.facing)
		local full = CarPath.turnBetween(h0, CarPath.angleOf(want))
		local part = math.clamp(full, -math.rad(70), math.rad(70))
		setSeg(E, { kind = "Spin", t0 = t, dur = a.Brake, a = ground(E), b = Vector3.new(h0, part, 0), c = dir * slide, ease = "out" })
		if not waitUntil(E, token, t + a.Brake) then
			return false
		end
		E.contact = nil
	end
	-- the slow turn round to face you
	local aim = targetPosition(E) or (ground(E) - E.facing * 20)
	local want = unitOr(flat(aim - E.pos), -E.facing)
	local T = recovery(E, byRound(E, a.TurnAround))
	local h0 = CarPath.angleOf(E.facing)
	local s = now()
	setSeg(E, { kind = "Spin", t0 = s, dur = T, a = ground(E), b = Vector3.new(h0, CarPath.turnBetween(h0, CarPath.angleOf(want)), 0), c = Vector3.new(), ease = "io" })
	return waitUntil(E, token, s + T)
end

-- CHARGE (once): skids round to face you while he revs, the red lane
-- following you until Lock of the Tell (short skids to keep facing you),
-- then it locks: slot 1 = where he starts, slot 2 = where he stops, slot 3
-- = the same again if that's the tyre wall (a crash). At the end of the
-- Tell he roars down it. Returns false if the fight moved on.
local function chargeOnce(E, token, a)
	local T = byRound(E, a.Tell)
	local t0 = setAction(E, "Charge", nil)
	local tLock = t0 + T * a.Lock
	local rate = byRound(E, E.def.Drive.SpinRate) * 1.6
	-- following you with the lane while he revs
	while now() < tLock - 0.02 do
		if not valid(E, token) then
			return false
		end
		local aim = targetPosition(E)
		local want = aim and unitOr(flat(aim - E.pos), E.facing) or E.facing
		local s = now()
		local step = math.max(0.05, math.min(0.15, tLock - s))
		local h0 = CarPath.angleOf(E.facing)
		local turn = CarPath.turnBetween(h0, CarPath.angleOf(want))
		-- (turning as fast as he must to be facing you by the lock, in short skids)
		local most = math.max(math.rad(rate), math.abs(turn) / math.max(tLock - s, 0.05)) * step
		setSeg(E, { kind = "Spin", t0 = s, dur = step, a = ground(E), b = Vector3.new(h0, math.clamp(turn, -most, most), 0), c = Vector3.new(), ease = "lin" })
		if not waitUntil(E, token, s + step) then
			return false
		end
	end
	-- locked: the lane is fixed
	local from = ground(E)
	local aim = targetPosition(E) or (from + E.facing * 40)
	local dir = E.facing
	local want = flatDistance(aim, from) + a.Overshoot
	local room = toEdge(E, from, dir, E.def.Leash)
	local len = math.min(want, room)
	local crash = room <= want + 0.01
	if len < 14 then
		-- (no room to charge that way: he honks instead)
		setSeg(E, holdSeg(E, now(), 0.1))
		Attacks.Honk(E, token)
		return false
	end
	local to = from + dir * len
	setSlot(E, 1, from)
	setSlot(E, 2, to)
	if crash then
		setSlot(E, 3, to)
	end
	-- the run down the lane is published now, starting at the end of the Tell
	-- (until then CarPath keeps him where he is, facing down it): every screen
	-- has it before he goes, so he sets off exactly on time
	local speed = byRound(E, a.Speed)
	local seg = lineSeg(E, t0 + T, to, speed, "lin")
	setSeg(E, seg)
	if not waitUntil(E, token, t0 + T) then
		return false
	end
	-- GO: down the lane, running over anyone in it
	E.contact = { damage = a.Damage, knockback = a.Knockback, struck = {} }
	if not waitUntil(E, token, seg.t0 + seg.dur) then
		E.contact = nil
		return false
	end
	return stopAndTurn(E, token, a, dir, crash)
end

function Attacks.Charge(E, token)
	local a = E.def.Attacks.Charge
	for _ = 1, byRound(E, a.Charges) do
		if not chargeOnce(E, token, a) then
			return
		end
	end
end

-- TAIL WHIP: he skids round toward a spot just beside you (the whip spot)
-- while he revs (Tell), then drives there - slot 1 = where he starts, slot 2
-- = the whip spot, slot 3 = where you were (the whip swings that way) - and
-- as he gets there whips his tail round in a half-circle skid (Whip seconds)
-- at you. After it he's facing back where he came from.
function Attacks.TailWhip(E, token)
	local a = E.def.Attacks.TailWhip
	local t0 = setAction(E, "TailWhip", nil)
	local P0 = ground(E)
	local aim = targetPosition(E) or (P0 + E.facing * 30)
	local toT = unitOr(flat(aim - P0), E.facing)
	local right = rightOf(toT)
	local sideSign = (E.facing:Dot(right) >= 0) and 1 or -1
	local W = pullIn(E, aim + right * sideSign * a.Offset, E.def.Leash)
	local dir = unitOr(flat(W - P0), toT)
	local reach = flatDistance(W, P0)
	if reach < 10 then
		Attacks.SideBump(E, token)
		return
	end
	setSlot(E, 1, P0)
	setSlot(E, 2, W)
	setSlot(E, 3, Vector3.new(aim.X, E.floorY, aim.Z))
	-- skid round to face the way, revving
	local seg = spinSeg(E, t0, dir, math.max(byRound(E, E.def.Drive.SpinRate), math.deg(math.abs(CarPath.turnBetween(CarPath.angleOf(E.facing), CarPath.angleOf(dir)))) / (a.Tell * 0.7)))
	setSeg(E, seg)
	if not waitUntil(E, token, t0 + math.min(seg.dur, a.Tell)) then
		return
	end
	-- the drive-by is published now, starting at the end of the Tell (so
	-- every screen has it before he goes)
	local drive = lineSeg(E, math.max(now(), t0 + a.Tell), W, a.Speed, "lin")
	setSeg(E, drive)
	if not waitUntil(E, token, drive.t0) then
		return
	end
	-- drive by
	local struck = {}
	E.contact = { damage = a.Damage, knockback = a.Knockback * 0.7, struck = struck }
	if not waitUntil(E, token, drive.t0 + drive.dur) then
		E.contact = nil
		return
	end
	-- the whip: his nose swings away from you, so his tail comes round at you
	local tSide = unitOr(flat(Vector3.new(aim.X, E.floorY, aim.Z) - W), right * -sideSign)
	local h0 = CarPath.angleOf(E.facing)
	local turn = -((CarPath.turnBetween(h0, CarPath.angleOf(tSide)) >= 0) and 1 or -1) * math.pi
	local slide = dir * math.min(5, toEdge(E, W, dir, E.def.Leash))
	local tW = now()
	setSeg(E, { kind = "Spin", t0 = tW, dur = a.Whip, a = W, b = Vector3.new(h0, turn, 0), c = slide, ease = "out" })
	E.contact = nil
	while now() < tW + a.Whip do
		if not valid(E, token) then
			return
		end
		hitHalf(E, W + slide * 0.5, tSide, a.Radius, a.Damage, a.Knockback, struck)
		task.wait()
	end
	holdUntil(E, token, now() + recovery(E, byRound(E, a.Recovery)))
end

-- WHEELIE SLAM: he rears up on his back wheels (Tell) - slot 1 = the middle
-- of the red circle in front of him - then slams down: everyone in the
-- circle is hit, and a shock ring rolls out from it (jump it).
function Attacks.WheelieSlam(E, token)
	local a = E.def.Attacks.WheelieSlam
	local t0 = setAction(E, "WheelieSlam", nil)
	local center = ground(E) + E.facing * a.Ahead
	setSlot(E, 1, center)
	E.wheelie = true
	if not holdUntil(E, token, t0 + a.Tell) then
		E.wheelie = false
		return
	end
	E.wheelie = false
	-- (the ring keeps the moment it last hit each player: whoever the slam
	-- just hit isn't hit again by the ring straight away)
	local hitAt = {}
	local t = now()
	for _, p in ipairs(fightersIn(E)) do
		local root = rootOf(p)
		if root and flatDistance(root.Position, center) <= a.Radius + PLAYER_RADIUS then
			hitAt[p] = t
			CombatService.DamagePlayer(p, a.Damage, center, knockbackFrom(center, root, a.Knockback))
		end
	end
	table.insert(E.waves, {
		origin = center, t0 = t, start = a.Radius * 0.6, speed = a.WaveSpeed, reach = a.WaveReach, thickness = a.WaveThickness,
		height = a.WaveHeight, damage = a.WaveDamage, knockback = a.WaveKnockback, hit = hitAt, lastR = a.Radius * 0.6,
	})
	holdUntil(E, token, now() + recovery(E, byRound(E, a.Recovery)))
end

-- HONK: his cheeks puff (Tell), then HONK - everyone in the cone in front of
-- him is thrown back (a little damage)
function Attacks.Honk(E, token)
	local a = E.def.Attacks.Honk
	local t0 = setAction(E, "Honk", nil)
	if not holdUntil(E, token, t0 + a.Tell) then
		return
	end
	local nose = ground(E) + E.facing * (E.def.Car.Length / 2)
	hitCone(E, nose, E.facing, a.Reach, a.Arc, a.Damage, a.Knockback)
	holdUntil(E, token, now() + recovery(E, a.Recovery))
end

-- BACKFIRE: his pipes glow and rumble (Tell), then BANG - fire in a cone
-- behind him, and burning puddles along it (slots 1..Puddles: where)
function Attacks.Backfire(E, token)
	local a = E.def.Attacks.Backfire
	local t0 = setAction(E, "Backfire", nil)
	local back = -E.facing
	local tail = ground(E) + back * (E.def.Car.Length / 2)
	local spots = {}
	for i = 1, a.Puddles do
		local d = a.Reach * i / (a.Puddles + 0.5)
		local side = rightOf(back) * ((i % 2 == 0) and 2.5 or -2.5)
		spots[i] = pullIn(E, tail + back * d + side, E.def.Leash + 6)
		setSlot(E, i, spots[i])
	end
	if not holdUntil(E, token, t0 + a.Tell) then
		return
	end
	hitCone(E, tail, back, a.Reach, a.Arc, a.Damage, a.Knockback)
	local untilT = now() + a.PuddleTime
	for _, spot in ipairs(spots) do
		table.insert(E.puddles, { pos = spot, radius = a.PuddleRadius, untilT = untilT, damage = a.PuddleDamage, tick = a.PuddleTick })
	end
	holdUntil(E, token, now() + recovery(E, a.Recovery))
end

-- SIDE BUMP: he leans away (Tell) - slot 1 = the middle of the red half-circle
-- beside him, slot 2 = a spot out on that side - then hops sideways at you: BONK!
function Attacks.SideBump(E, token)
	local a = E.def.Attacks.SideBump
	local t0 = setAction(E, "SideBump", nil)
	local aim = targetPosition(E) or (ground(E) + rightOf(E.facing) * 5)
	local right = rightOf(E.facing)
	local side = (flat(aim - E.pos):Dot(right) >= 0) and right or -right
	local center = ground(E) + side * (E.def.Car.Width / 2)
	setSlot(E, 1, center)
	setSlot(E, 2, center + side * 10)
	if not holdUntil(E, token, t0 + a.Tell) then
		return
	end
	local hop = math.min(a.Hop, toEdge(E, ground(E), side, E.def.Leash))
	local s = now()
	setSeg(E, { kind = "Spin", t0 = s, dur = 0.2, a = ground(E), b = Vector3.new(CarPath.angleOf(E.facing), 0, 0), c = side * hop, ease = "out" })
	hitHalf(E, center + side * hop * 0.5, side, a.Radius, a.Damage, a.Knockback)
	if not waitUntil(E, token, s + 0.2) then
		return
	end
	holdUntil(E, token, now() + recovery(E, a.Recovery))
end

-- DONUTS: spinning on the spot for the crowd, twice round (free hits)
function Attacks.Donuts(E, token)
	local a = E.def.Attacks.Donuts
	local t0 = setAction(E, "Donuts", nil)
	local h0 = CarPath.angleOf(E.facing)
	local dir = (E.rng:NextNumber() < 0.5) and 1 or -1
	run(E, token, { kind = "Spin", t0 = t0, dur = a.Time, a = ground(E), b = Vector3.new(h0, dir * math.pi * 4, 0), c = Vector3.new(), ease = "io" })
end

-- BURNOUT RING (TURBO): he drives to the edge of a circle round you (slot 1
-- = its middle: where you were), revs (Tell), then laps it once, fast, the
-- flames coming up behind him as he goes (slots 2..Flames + 1, each as it's
-- lit), then turns in and dashes straight through the middle: slot
-- Flames + 2 = where the dash starts, Flames + 3 = where it stops.
function Attacks.BurnoutRing(E, token)
	local a = E.def.Attacks.BurnoutRing
	local t0 = setAction(E, "BurnoutRing", nil)
	local aim = targetPosition(E) or (ground(E) + E.facing * 30)
	local C = pullIn(E, aim, E.def.Leash - a.Radius)
	local out = unitOr(flat(E.pos - C), -E.facing)
	local a0 = CarPath.angleOf(out)
	local S = C + CarPath.dirOf(a0) * a.Radius
	-- which way round: the one his nose already points
	local tangentPlus = CarPath.dirOf(a0 + math.pi / 2)
	local sweep = ((E.facing:Dot(tangentPlus) >= 0) and 1 or -1) * math.pi * 2
	local tangent = (sweep > 0) and tangentPlus or -tangentPlus
	setSlot(E, 1, C)
	-- to the start of the ring, and round to face along it (all within the Tell)
	if flatDistance(S, E.pos) > 3 then
		if not faceTo(E, token, unitOr(flat(S - E.pos), E.facing), 1.6) then
			return
		end
		if not run(E, token, (lineSeg(E, now(), S, byRound(E, E.def.Drive.Cruise) * 1.3, "io"))) then
			return
		end
	end
	if not faceTo(E, token, tangent, 1.8) then
		return
	end
	-- the lap is published now, starting at the end of the Tell (and at least
	-- a moment from now), so every screen has it before he sets off
	local tL = math.max(now() + 0.15, t0 + a.Tell)
	setSeg(E, { kind = "Arc", t0 = tL, dur = a.Lap, a = C, b = Vector3.new(a.Radius, a0, sweep), c = Vector3.new(), ease = "lin" })
	if not waitUntil(E, token, tL) then
		return
	end
	-- the lap
	local struck = {}
	E.contact = { damage = a.Damage * 0.7, knockback = a.Knockback * 0.8, struck = struck }
	for k = 1, a.Flames do
		if not waitUntil(E, token, tL + a.Lap * k / a.Flames) then
			E.contact = nil
			return
		end
		local spot = C + CarPath.dirOf(a0 + sweep * (k - 0.5) / a.Flames) * a.Radius
		setSlot(E, k + 1, spot)
		table.insert(E.puddles, { pos = spot, radius = a.FlameRadius, untilT = now() + a.FlameTime, damage = a.FlameDamage, tick = a.FlameTick })
	end
	E.contact = nil
	-- turn in and dash through the middle
	local here = ground(E)
	local dir = unitOr(flat(C - here), -out)
	if not faceTo(E, token, dir, 2.5) then
		return
	end
	local len = math.min(a.Radius * 2 + 8, toEdge(E, ground(E), dir, E.def.Leash))
	local to = ground(E) + dir * len
	setSlot(E, a.Flames + 2, ground(E))
	setSlot(E, a.Flames + 3, to)
	-- (the dash is published now too, starting in a moment)
	local dash = lineSeg(E, now() + 0.35, to, a.DashSpeed, "lin")
	setSeg(E, dash)
	if not waitUntil(E, token, dash.t0) then
		return
	end
	E.contact = { damage = a.Damage, knockback = a.Knockback, struck = struck }
	if not waitUntil(E, token, dash.t0 + dash.dur) then
		E.contact = nil
		return
	end
	stopAndTurn(E, token, E.def.Attacks.Charge, dir, false)
end

----------------------------------------------------------------------
-- Driving between moves
----------------------------------------------------------------------
-- CRUISE: circling you like a shark (an arc round you), or driving off to
-- a spot a good way from you; then skidding round to face you. Harmless.
local function cruise(E, token)
	local aim = targetPosition(E)
	if not aim then
		return holdUntil(E, token, now() + 0.3)
	end
	local D = E.def.Drive
	local speed = byRound(E, D.Cruise)
	local d = flatDistance(aim, E.pos)
	setAction(E, "Cruise", nil)
	local circled = false
	if d > 26 and d < 62 and E.rng:NextNumber() < D.CircleChance then
		-- round you: an arc at the distance he's at (kept inside the track)
		local r = math.clamp(d, 30, 50)
		local a0 = CarPath.angleOf(flat(E.pos - aim))
		local amount = math.rad(60 + E.rng:NextNumber() * 60)
		for _, sgn in ipairs({ (E.rng:NextNumber() < 0.5) and 1 or -1 }) do
			for _, s in ipairs({ sgn, -sgn }) do
				if not circled then
					local ok = true
					for k = 0, 6 do
						local p = aim + CarPath.dirOf(a0 + s * amount * k / 6) * r
						if spineDist(E, p) > E.def.Leash then
							ok = false
						end
					end
					if ok then
						local start = aim + CarPath.dirOf(a0) * r
						if flatDistance(start, E.pos) > 2 then
							if not faceTo(E, token, unitOr(flat(start - E.pos), E.facing), 1.5) then
								return false
							end
							if not run(E, token, (lineSeg(E, now(), start, speed, "io"))) then
								return false
							end
						end
						if not faceTo(E, token, CarPath.dirOf(a0 + s * math.pi / 2), 1.5) then
							return false
						end
						local dur = amount * r / speed
						if not run(E, token, { kind = "Arc", t0 = now(), dur = dur, a = Vector3.new(aim.X, E.floorY, aim.Z), b = Vector3.new(r, a0, s * amount), c = Vector3.new(), ease = "lin" }) then
							return false
						end
						circled = true
					end
				end
			end
		end
	end
	if not circled then
		-- off to a spot about 45 from you: of eight round you, the best one ahead of him
		local best, bestScore = nil, -math.huge
		for k = 0, 7 do
			local p = pullIn(E, aim + CarPath.dirOf(k * math.pi / 4) * 45, E.def.Leash - 2)
			local toP = flat(p - E.pos)
			if toP.Magnitude > 18 then
				local score = toP.Unit:Dot(E.facing) * 2 - math.abs(flatDistance(p, aim) - 45) / 10
				if score > bestScore then
					best, bestScore = p, score
				end
			end
		end
		if best then
			if not faceTo(E, token, unitOr(flat(best - E.pos), E.facing), 1.3) then
				return false
			end
			if not run(E, token, (lineSeg(E, now(), best, speed, "io"))) then
				return false
			end
		end
	end
	local aim2 = targetPosition(E)
	if aim2 then
		return faceTo(E, token, unitOr(flat(aim2 - E.pos), E.facing), 1.2)
	end
	return true
end

----------------------------------------------------------------------
-- His brain
----------------------------------------------------------------------
-- a weighted pick among the moves that suit where you are from him
local function choose(E, aim)
	local d, where = relOf(E, aim)
	local options, total = {}, 0
	for name, a in pairs(E.def.Attacks) do
		local w = a.Weight or 0
		if (a.Phase or 1) > E.phase or d < a.Range[1] or d > a.Range[2] then
			w = 0
		end
		if a.Facing and a.Facing ~= where then
			w = 0
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

local function cycle(E, token)
	if E.phase == 1 and healthShare(E) <= E.def.PhaseAt + 1e-6 then
		if not breakShell(E, token) then
			return false
		end
	end
	local target = pickTarget(E)
	local aim = target and targetPosition(E)
	if not aim then
		holdUntil(E, token, now() + 0.2)
		return valid(E, token)
	end
	local name = choose(E, aim)
	if not name then
		if not cruise(E, token) then
			return false
		end
	else
		E.history = { name, E.history[1] }
		Attacks[name](E, token)
		if not valid(E, token) then
			return false
		end
		E.contact = nil
		if E.rng:NextNumber() < byRound(E, E.def.Drive.CruiseAfter) then
			if not cruise(E, token) then
				return false
			end
		end
	end
	-- breathe, turning to keep you in front of him
	local b = byRound(E, E.def.Breather)
	setAction(E, "Idle", nil)
	local pause = b[1] + E.rng:NextNumber() * (b[2] - b[1])
	local aim2 = targetPosition(E)
	local s = now()
	if aim2 then
		local seg, dur = spinSeg(E, s, unitOr(flat(aim2 - E.pos), E.facing), byRound(E, E.def.Drive.SpinRate) * 0.5, nil, 0.05)
		if dur <= pause then
			setSeg(E, seg)
		else
			setSeg(E, holdSeg(E, s, pause))
		end
	end
	waitUntil(E, token, s + pause)
	return valid(E, token)
end

local function freeze(E)
	E.contact, E.wheelie = nil, false
	setSeg(E, holdSeg(E, now(), 0.05))
end

-- Revvington's fight: round and round the cycle, each go protected (an
-- error in one move is reported once and he carries on with the next)
function Boss.brain(E, token)
	E.contact, E.wheelie = nil, false
	-- GO! The race clock starts now (every screen's clock counts from this) -
	-- not when he's back from TURBO (BossService starts his brain again then)
	if E.phase == 1 then
		E.model:SetAttribute("RaceStart", now())
	end
	while valid(E, token) and E.state ~= "Dead" do
		local ok, result = pcall(cycle, E, token)
		if not ok then
			if not E.warnedError then
				E.warnedError = true
				warn("[BossService] " .. E.def.Short .. " hit an error and carried on: " .. tostring(result))
			end
			freeze(E)
			task.wait(0.3)
		elseif not result then
			return
		end
	end
end

----------------------------------------------------------------------
-- Every frame: exactly where his segment puts him, and running people over
----------------------------------------------------------------------
function Boss.step(E, dt)
	if E.seg then
		local pos, dir = CarPath.eval(E.seg, now())
		E.pos = Vector3.new(pos.X, E.floorY, pos.Z)
		E.facing = dir
	end
	place(E)
	if E.contact and E.state == "Fighting" then
		carHits(E, E.contact)
	end
	stepWaves(E)
	stepPuddles(E)
	local _ = dt
end

----------------------------------------------------------------------
-- Hooks (see BossService: they run at these moments)
----------------------------------------------------------------------
function Boss.init(kit)
	now, flat, flatDistance, unitOr, rootOf, fightersIn = kit.now, kit.flat, kit.flatDistance, kit.unitOr, kit.rootOf, kit.fightersIn
	setAction, setSlot, waitUntil, valid = kit.setAction, kit.setSlot, kit.waitUntil, kit.valid
	recovery, targetPosition, healthShare, knockbackFrom = kit.recovery, kit.targetPosition, kit.healthShare, kit.knockbackFrom
	pickTarget, breakShell, place, stepWaves, stepPuddles = kit.pickTarget, kit.breakShell, kit.place, kit.stepWaves, kit.stepPuddles
	CombatService, PLAYER_RADIUS, STAND_HEIGHT = kit.CombatService, kit.PLAYER_RADIUS, kit.STAND_HEIGHT
end

-- Built: the track's shape found, parked on the start line, and
-- CombatService told his real shape (a box, not a ball)
function Boss.onBuild(E)
	local arena = nil
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("Floor") == E.floor and child:GetAttribute("Spine") then
			arena = child
		end
	end
	E.center = arena and arena:GetAttribute("Center") or E.home
	E.center = Vector3.new(E.center.X, E.floorY, E.center.Z)
	E.spine = arena and arena:GetAttribute("Spine") or 70
	E.edge = arena and arena:GetAttribute("Edge") or 62
	setSeg(E, holdSeg(E, now(), 0.05))
	local car = E.def.Car
	CombatService.SetTargetShape(E.model, function(from)
		local fwd = E.facing
		local right = rightOf(fwd)
		local rel = flat(from - E.pos)
		local x = math.clamp(rel:Dot(right), -car.Width / 2, car.Width / 2)
		local z = math.clamp(rel:Dot(fwd), -car.Length / 2, car.Length / 2)
		local p = E.pos + right * x + fwd * z
		return Vector3.new(p.X, E.floorY + (E.wheelie and 4.5 or 2.8), p.Z), 0.6
	end)
end

-- Everyone left or died: he stops where he is (BossService brings him home)
function Boss.onReset(E)
	freeze(E)
end

-- Home again: parked on the start line
function Boss.onHome(E)
	E.contact, E.wheelie = nil, false
	setSeg(E, holdSeg(E, now(), 0.05))
end

-- TURBO! (half health): he stops where he is for it
function Boss.onBreak(E)
	freeze(E)
end

function Boss.onDie(E)
	freeze(E)
end

-- (for tests: the track's shape sums)
Boss._spineDist = spineDist
Boss._cruise = cruise

return Boss
