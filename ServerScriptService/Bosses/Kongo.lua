--[[
	Kongo  (ModuleScript, parent: ServerScriptService > Bosses, name: "Kongo")

	Floor 7's boss: Kongo, the Jungle Brawler (Config.Bosses[7]) - a big,
	cocky gorilla in a red tie who fights up close with the moves from his
	games. A brawl on flat ground: every move has a wind-up you can read, a
	way to dodge it, and a moment afterwards when he's open. He fights on the
	surface, so BossService's shared brain runs him (it picks a move that
	suits the distance - from Config.Bosses[7].Attacks - knuckle-walks after
	you, turns to face you, goes into ROUND 2 at half health, resets, dies,
	pays out). This file is his moves:

	  GIANT PUNCH     winds his arm round like a windmill - the longer he winds,
	                  the further the red lane reaches - then throws himself
	                  down it fist-first. Miss, and he's TIRED (a big opening).
	                  Round 2: a full wind-up shakes the ground where it lands.
	  HAND SLAP       slaps the ground again and again: each slap sends a
	                  shockwave rolling out along the floor - jump them.
	  ROLLING ATTACK  curls into a ball and rolls down a red lane, bouncing once
	                  off the edge of the clearing. Dizzy after.
	  SPINNING KONG   arms out like a helicopter, spins and drifts after you
	                  (the red ring round him hurts). Dizzy after.
	  HEADBUTT        a quick, short lunge head-first.
	  BARREL THROW    heaves barrels over his head and throws them rolling
	                  along the floor at you - jump them.
	  TNT             lobs TNT barrels onto red circles: they explode.
	  CHEST POUND     showing off ("OOH OOH!"): nothing hurts - hit him!
	 round 2:
	  CARGO THROW     lunges and GRABS whoever's in front of him, and hurls them.
	  COMBO           no breathers: slaps, straight into a roll, straight into
	                  a quick Giant Punch.

	Everything is published for each player's screen (BossClient +
	ReplicatedStorage/BossBodies/Kongo): the move's name and start time
	(setAction, with its number in ActN), and the spots it fills in as it goes
	(setSlot) - each move below says which slot is what.
]]

local Boss = {}

-- The shared helpers these moves use, from BossService (see Boss.init)
local now, flat, flatDistance, unitOr, rootOf, fightersIn
local setAction, setSlot, waitUntil, valid, hitArea, recovery, targetPosition, knockbackFrom
local CombatService, PLAYER_RADIUS, STAND_HEIGHT

function Boss.init(kit)
	now, flat, flatDistance, unitOr, rootOf, fightersIn = kit.now, kit.flat, kit.flatDistance, kit.unitOr, kit.rootOf, kit.fightersIn
	setAction, setSlot, waitUntil, valid = kit.setAction, kit.setSlot, kit.waitUntil, kit.valid
	hitArea, recovery, targetPosition, knockbackFrom = kit.hitArea, kit.recovery, kit.targetPosition, kit.knockbackFrom
	CombatService, PLAYER_RADIUS, STAND_HEIGHT = kit.CombatService, kit.PLAYER_RADIUS, kit.STAND_HEIGHT
end

----------------------------------------------------------------------
-- Little helpers
----------------------------------------------------------------------
-- a number for this round: a { round 1, round 2 } pair, or just a number
local function perRound(E, v)
	if type(v) == "table" then
		return v[math.min(E.phase, #v)]
	end
	return v
end

local function lerp(a, b, u)
	return a + (b - a) * u
end

-- a spot pulled in to within `r` of the middle of the clearing, on the floor
local function inside(E, pos, r)
	local off = flat(pos - E.home)
	if off.Magnitude > r then
		off = off.Unit * r
	end
	return Vector3.new(E.home.X + off.X, E.floorY, E.home.Z + off.Z)
end

-- where he stands, on the floor
local function ground(E)
	return Vector3.new(E.pos.X, E.floorY, E.pos.Z)
end

-- how far he can go from `from` along `dir` before crossing the circle of
-- radius `r` round the middle of the clearing
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

-- the way to his target (or the way he's facing, if there's nobody)
local function aimDir(E, from)
	local aim = targetPosition(E)
	return aim and unitOr(flat(aim - from), E.facing) or E.facing, aim
end

-- Everyone within `reach` in front of him (a wedge `arc` degrees wide,
-- centred on the way he faces) - and anyone right up against him. Returns
-- the players it caught (without hurting them: the move decides what happens).
local function inArc(E, reach, arc)
	local cosHalf = math.cos(math.rad(arc / 2))
	local list = {}
	for _, p in ipairs(fightersIn(E)) do
		local root = rootOf(p)
		if root then
			local off = flat(root.Position - E.pos)
			local d = off.Magnitude
			if d <= reach + PLAYER_RADIUS and (d < E.def.Size / 2 + PLAYER_RADIUS or off.Unit:Dot(E.facing) >= cosHalf) then
				table.insert(list, { player = p, root = root, d = d })
			end
		end
	end
	table.sort(list, function(x, y)
		return x.d < y.d
	end)
	return list
end

-- a shockwave ring along the floor from `origin`, starting at `t0` (see
-- BossService's stepWaves: jump it, or roll through it)
local function addWave(E, origin, t0, speed, reach, thickness, height, damage, knockback)
	table.insert(E.waves, {
		origin = origin,
		start = 2,
		t0 = t0,
		speed = speed,
		reach = reach,
		thickness = thickness,
		height = height,
		damage = damage,
		knockback = knockback,
		lastR = 2,
		hit = {},
	})
end

-- A lunge along a straight line from `from` to `to`, starting at `start`,
-- running over anyone in the way (each hit once; radius nil = hurting nobody).
-- Returns false if the fight moved on meanwhile, and the players it hit.
local function lunge(E, token, from, to, start, travel, radius, damage, knockback)
	local hit = {}
	E.facing = unitOr(flat(to - from), E.facing)
	E.motion = { from = from, to = to, t0 = start, t1 = start + travel }
	if radius then
		E.sweep = { radius = radius, damage = damage, knockback = knockback, hit = hit }
	end
	local ok = waitUntil(E, token, start + travel)
	E.motion, E.sweep = nil, nil
	if ok then
		E.pos = to
	end
	return ok, hit
end

----------------------------------------------------------------------
-- The moves (each needs an entry of the same name in Config's Attacks)
----------------------------------------------------------------------
local Attacks = {}
Boss.Attacks = Attacks

-- GIANT PUNCH. setAction's number = how long he winds up (every screen draws
-- the lane growing with it). Slot 1 = where he starts, slot 2 = where his
-- lunge ends (both set when the lane locks). Slot 3 = the same end again if
-- he MISSED (he's tired: a big opening). Slot 4 = where the ground shakes
-- (round 2, a full wind-up). `wind` = a set wind-up (the combo's quick one).
local function giantPunch(E, token, wind)
	local a = E.def.Attacks.GiantPunch
	wind = wind or lerp(a.Wind[1], a.Wind[2], E.rng:NextNumber())
	local charge = math.clamp((wind - a.Wind[1]) / math.max(a.Wind[2] - a.Wind[1], 1e-3), 0, 1)
	E.track = true
	local t0 = setAction(E, "GiantPunch", wind)
	if not waitUntil(E, token, t0 + wind * a.Commit) then
		return false
	end
	E.track = false
	local from = ground(E)
	local dir, aim = aimDir(E, from)
	local want = lerp(a.Reach[1], a.Reach[2], charge)
	if aim then
		-- (no further than just past you: he doesn't overshoot a close target by much)
		want = math.min(want, flatDistance(aim, from) + 6)
	end
	local len = math.max(4, math.min(want, toEdge(E, from, dir, E.def.Leash)))
	local to = from + dir * len
	E.facing = dir
	setSlot(E, 1, from)
	setSlot(E, 2, to)
	if not waitUntil(E, token, t0 + wind) then
		return false
	end
	local start = t0 + wind
	local ok, hit = lunge(E, token, from, to, start, len / a.Speed, a.Width, lerp(a.Damage[1], a.Damage[2], charge),
		lerp(a.Knockback[1], a.Knockback[2], charge))
	if not ok then
		return false
	end
	local landed = next(hit) ~= nil
	local land = start + len / a.Speed
	if E.phase >= 2 and wind >= a.Big then
		-- the ground shakes where his fist hits
		local spot = to + dir * (E.def.Size * 0.5)
		setSlot(E, 4, spot)
		addWave(E, spot, land, a.WaveSpeed, a.WaveReach, a.WaveThickness, a.WaveHeight, a.WaveDamage, 30)
	end
	if not landed then
		setSlot(E, 3, to) -- (every screen: he's tired)
	end
	return waitUntil(E, token, land + recovery(E, landed and a.Recovery or a.Tired))
end

function Attacks.GiantPunch(E, token)
	giantPunch(E, token, nil)
end

-- HAND SLAP. setAction's number = how many slaps. Slot 1 = where the
-- shockwaves start (the floor between his hands, in front of him). Slap k
-- lands at Tell + (k - 1) * Gap.
local function handSlap(E, token, slaps)
	local a = E.def.Attacks.HandSlap
	slaps = slaps or perRound(E, a.Slaps)
	E.track = true
	local t0 = setAction(E, "HandSlap", slaps)
	if not waitUntil(E, token, t0 + a.Tell - 0.15) then
		return false
	end
	E.track = false
	local origin = ground(E) + E.facing * (E.def.Size * 0.45)
	setSlot(E, 1, origin)
	for k = 1, slaps do
		local slapAt = t0 + a.Tell + (k - 1) * a.Gap
		if not waitUntil(E, token, slapAt) then
			return false
		end
		addWave(E, origin, slapAt, a.Speed, a.Reach, a.Thickness, a.Height, a.Damage, a.Knockback)
	end
	return waitUntil(E, token, t0 + a.Tell + (slaps - 1) * a.Gap + recovery(E, a.Recovery))
end

function Attacks.HandSlap(E, token)
	handSlap(E, token, nil)
end

-- ROLLING ATTACK. Slot 1 = where he starts rolling, slot 2 = where he
-- bounces off the edge (or stops, if he doesn't reach it), slot 3 = where he
-- stops after a bounce. ActN (set when the lane locks) = how long he rolls.
local function roll(E, token)
	local a = E.def.Attacks.Roll
	E.track = true
	local t0 = setAction(E, "Roll", nil)
	if not waitUntil(E, token, t0 + a.Tell * a.Commit) then
		return false
	end
	E.track = false
	local R = E.def.Leash
	local from = ground(E)
	local dir = aimDir(E, from)
	local room = toEdge(E, from, dir, R)
	local len1 = math.min(a.Distance, room)
	local mid = from + dir * len1
	local to, len2 = nil, 0
	if room < a.Distance and len1 > 1 then
		-- bounce off the edge: the way reflected about the edge's normal there
		local n = unitOr(flat(mid - E.home), -dir)
		local dir2 = unitOr(dir - n * (2 * dir:Dot(n)), -dir)
		len2 = math.min(a.Distance - len1, toEdge(E, mid - n * 0.5, dir2, R))
		if len2 > 2 then
			to = mid + dir2 * len2
		else
			len2 = 0
		end
	end
	local t1, t2 = len1 / a.Speed, len2 / a.Speed
	E.facing = dir
	E.model:SetAttribute("ActN", t1 + t2)
	setSlot(E, 1, from)
	setSlot(E, 2, mid)
	if to then
		setSlot(E, 3, to)
	end
	if not waitUntil(E, token, t0 + a.Tell) then
		return false
	end
	-- one set of hits for the whole roll (bounce and all): each player once
	local start = t0 + a.Tell
	E.motion = { from = from, to = mid, t0 = start, t1 = start + t1 }
	local hit = {}
	E.sweep = { radius = a.Width, damage = a.Damage, knockback = a.Knockback, hit = hit }
	if not waitUntil(E, token, start + t1) then
		return false
	end
	E.pos = mid
	if to then
		E.facing = unitOr(flat(to - mid), E.facing)
		E.motion = { from = mid, to = to, t0 = start + t1, t1 = start + t1 + t2 }
		if not waitUntil(E, token, start + t1 + t2) then
			return false
		end
		E.pos = to
	end
	E.motion, E.sweep = nil, nil
	return waitUntil(E, token, start + t1 + t2 + recovery(E, a.Recovery))
end

function Attacks.Roll(E, token)
	roll(E, token)
end

-- SPINNING KONG. setAction's number = how long he spins (after the Tell). No
-- slots: the red ring round him goes wherever he goes.
function Attacks.Spin(E, token)
	local a = E.def.Attacks.Spin
	E.track = true
	local t0 = setAction(E, "Spin", a.Time)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	E.track = false
	local tEnd = t0 + a.Tell + a.Time
	local last = now()
	local batchAt = -math.huge
	local struck = {}
	while now() < tEnd do
		if not valid(E, token) then
			return
		end
		local t = now()
		local dt = math.min(t - last, 0.1)
		last = t
		-- drifting after his target
		local aim = targetPosition(E)
		if aim then
			local off = flat(aim - E.pos)
			if off.Magnitude > 1 then
				local step = math.min(a.Speed * dt, off.Magnitude - 1)
				E.pos = inside(E, E.pos + off.Unit * step, E.def.Leash)
			end
		end
		-- clobbering anyone inside the ring (again every Rehit seconds)
		if t - batchAt >= a.Rehit then
			batchAt = t
			struck = {}
		end
		hitArea(E, E.pos, a.Radius, a.Damage, a.Knockback, struck)
		task.wait()
	end
	waitUntil(E, token, tEnd + recovery(E, a.Recovery))
end

-- HEADBUTT. Slot 1 = where he starts, slot 2 = where he stops (set a moment
-- before he goes, when his head's all the way back).
function Attacks.Headbutt(E, token)
	local a = E.def.Attacks.Headbutt
	E.track = true
	local t0 = setAction(E, "Headbutt", nil)
	if not waitUntil(E, token, t0 + a.Tell * 0.6) then
		return
	end
	E.track = false
	local from = ground(E)
	local dir = aimDir(E, from)
	local len = math.max(2, math.min(a.Distance, toEdge(E, from, dir, E.def.Leash)))
	local to = from + dir * len
	E.facing = dir
	setSlot(E, 1, from)
	setSlot(E, 2, to)
	if not waitUntil(E, token, t0 + a.Tell) then
		return
	end
	local ok = lunge(E, token, from, to, t0 + a.Tell, a.Time, a.Width, a.Damage, a.Knockback)
	if ok then
		waitUntil(E, token, t0 + a.Tell + a.Time + recovery(E, a.Recovery))
	end
end

-- BARREL THROW. setAction's number = how many barrels. Barrel k is thrown at
-- Tell + (k - 1) * Gap, aimed at you then; its start and end are slots 2k-1
-- and 2k. Each rolls along the floor at Speed and hits whoever it touches -
-- unless they're jumping over it (or rolling through it).
function Attacks.Barrel(E, token)
	local a = E.def.Attacks.Barrel
	local count = perRound(E, a.Barrels)
	E.track = true
	local t0 = setAction(E, "Barrel", count)
	for k = 1, count do
		local throwAt = t0 + a.Tell + (k - 1) * a.Gap
		if not waitUntil(E, token, throwAt - 0.12) then
			return
		end
		local dir = aimDir(E, E.pos)
		E.facing = dir
		local from = ground(E) + dir * (E.def.Size / 2 + 1.5)
		local len = math.max(8, math.min(a.Reach, toEdge(E, from, dir, E.def.Leash + 6)))
		local to = from + dir * len
		setSlot(E, 2 * k - 1, from)
		setSlot(E, 2 * k, to)
		if not waitUntil(E, token, throwAt) then
			return
		end
		task.spawn(function()
			local struck = {}
			while valid(E, token) do
				local gone = (now() - throwAt) * a.Speed
				if gone > len then
					return
				end
				local p = from + dir * math.max(gone, 0)
				for _, pl in ipairs(fightersIn(E)) do
					if not struck[pl] then
						local root = rootOf(pl)
						if root and flatDistance(root.Position, p) <= a.Radius + PLAYER_RADIUS
							and root.Position.Y - (E.floorY + STAND_HEIGHT) < a.Height * 0.8 then
							struck[pl] = true
							CombatService.DamagePlayer(pl, a.Damage, p, knockbackFrom(p, root, a.Knockback))
						end
					end
				end
				task.wait()
			end
		end)
	end
	E.track = false
	waitUntil(E, token, t0 + a.Tell + (count - 1) * a.Gap + recovery(E, a.Recovery))
end

-- TNT. setAction's number = how many. TNT k is lobbed at Tell + (k - 1) *
-- Gap and lands Flight later on slot k (the first where you are, the next
-- where you're heading), exploding round it.
function Attacks.TNT(E, token)
	local a = E.def.Attacks.TNT
	local count = perRound(E, a.Count)
	E.track = true
	local t0 = setAction(E, "TNT", count)
	for k = 1, count do
		local throwAt = t0 + a.Tell + (k - 1) * a.Gap
		if not waitUntil(E, token, throwAt) then
			return
		end
		local root = E.target and rootOf(E.target)
		local aim = targetPosition(E) or (ground(E) + E.facing * 24)
		if root and k > 1 then
			aim = aim + flat(root.AssemblyLinearVelocity) * 0.6 -- (where you'll be if you keep going)
		end
		aim = inside(E, aim, E.def.Leash + 6)
		E.facing = unitOr(flat(aim - E.pos), E.facing)
		setSlot(E, k, aim)
		task.spawn(function()
			if waitUntil(E, token, throwAt + a.Flight) then
				hitArea(E, aim, a.Radius, a.Damage, a.Knockback)
			end
		end)
	end
	E.track = false
	waitUntil(E, token, t0 + a.Tell + (count - 1) * a.Gap + a.Flight * 0.5 + recovery(E, a.Recovery))
end

-- CHEST POUND: showing off. Nothing hurts - it's your chance.
function Attacks.Pound(E, token)
	local a = E.def.Attacks.Pound
	E.track = true
	local t0 = setAction(E, "Pound", a.Time)
	waitUntil(E, token, t0 + a.Time)
end

-- CARGO THROW (round 2). Slot 1 = the spot in front of him he grabs at
-- (when he commits), slot 2 = whoever he caught (where they were) - they're
-- scooped up and hurled forward, high and far. Miss, and he stumbles (longer
-- open).
function Attacks.CargoThrow(E, token)
	local a = E.def.Attacks.CargoThrow
	E.track = true
	local t0 = setAction(E, "CargoThrow", nil)
	if not waitUntil(E, token, t0 + a.Tell * 0.6) then
		return
	end
	E.track = false
	local from = ground(E)
	setSlot(E, 1, from + E.facing * a.Reach)
	-- a little lunge forward as he grabs
	local step = math.min(3, toEdge(E, from, E.facing, E.def.Leash))
	if not waitUntil(E, token, t0 + a.Tell - 0.12) then
		return
	end
	local ok = lunge(E, token, from, from + E.facing * step, t0 + a.Tell - 0.12, 0.12, nil, 0, 0)
	if not ok then
		return
	end
	local caught = inArc(E, a.Reach, a.Arc)[1]
	if caught then
		setSlot(E, 2, flat(caught.root.Position) + Vector3.new(0, E.floorY, 0))
		local throw = E.facing * a.Throw + Vector3.new(0, a.Lift, 0)
		CombatService.DamagePlayer(caught.player, a.Damage, ground(E), throw)
	end
	waitUntil(E, token, t0 + a.Tell + recovery(E, caught and a.Recovery or a.Recovery + 0.8))
end

-- COMBO (round 2): a couple of slaps, straight into a roll, straight into a
-- quick Giant Punch - no breathers in between. (Each part is its own move on
-- every screen.)
function Attacks.Combo(E, token)
	local a = E.def.Attacks.Combo
	if not handSlap(E, token, a.Slaps) then
		return
	end
	if not roll(E, token) then
		return
	end
	giantPunch(E, token, a.Wind)
end

----------------------------------------------------------------------
-- Hooks (see BossService: they run at these moments)
----------------------------------------------------------------------
-- ROUND 2 starts mid-move: any shockwave still rolling out stops (nothing
-- hurts while he rages)
function Boss.onBreak(E)
	E.waves = {}
end

function Boss.onReset(E)
	E.waves = {}
end

-- (for tests: a Giant Punch with a set wind-up)
Boss._giantPunch = giantPunch

return Boss
