--[[
	Gridlock  (ModuleScript, parent: ServerScriptService > Bosses, name: "Gridlock")

	Floor 6's boss: Gridlock, the Final Beat (Config.Bosses[6]) - the last
	LEVEL. A giant neon cube with a demon's grin, fighting ON THE BEAT in an
	arena that fights too. He has his own brain (Boss.brain) and his own
	every-frame step (Boss.step). The grid, the beat, the tile patterns and his
	motion are shared sums: ReplicatedStorage/BeatGrid.

	THE BEAT: Config's Bpm. It starts with the level (the start of the wake,
	when the music starts) and every move is counted in beats from it: its
	warning, the moment it hurts, how long he's open.

	THE LEVEL ATTACKS: tile patterns light up and spike on the beat (a square
	where he'll land, a ring round it, rows marching out, checkers, stripes...).
	Each is published for every screen as a few numbers (Tiles1..Tiles12 and
	TilesK: see spawnTiles) and remembered here to hit whoever stands on a lit
	tile when it spikes (jump it, roll through it, or be somewhere else).

	His FORMS (changing through a portal every few moves; the numbers are in
	Config.Bosses[6]):
	  CUBE   HOP SLAM (a square lights up, he hops onto it, then a ring of
	         spikes), SPIKE ROWS (rows march out from him along the straight
	         lines - round 2: the diagonals too), STOMP CHAIN (round 2: three
	         hop slams, one a beat)
	  SHIP   BOMB RUN (a lane of tiles through you, a bomb a beat along it),
	         SWOOP (a lane that follows you, locks, and he dives down it)
	  UFO    UFO SLAM (bursting after you, the circle under him follows you,
	         locks... SLAM - then stuck), ORB RAIN (orbs onto lit tiles)
	  WAVE   ZIG-ZAG (a dotted zig-zag through you; he zooms along it leaving
	         a wall of light)
	  any    TILE PATTERN: the level itself - checkers, stripes, rings, halves
	THE DROP (every few moves, and first thing in round 2): he rises to the
	middle while the music builds, then every tile spikes except the jump pads
	(stand on one: it throws you up) - then he crashes down, STUNNED.
	ROUND 2 (half health): GRAVITY FLIP! He falls UP to the ceiling grid; now
	and then he flips again. On the ceiling he does CEILING DROPS (the square
	under him follows you, locks, and he drops onto it - then he's stuck).
	THE JUMP PADS: step on one and it throws you up (CombatService.Launch).

	Published on his model (besides BossService's own): his move (MoveK,
	MoveT0, MoveT1, MoveA, MoveB, MoveH, MoveN, MoveE, MoveF, then MoveId -
	see BeatGrid), Form, Gravity, BeatStart and Bpm, the tile patterns, each
	move's spots in its slots (ActN = the beat the move counts from), and
	PadAt / PadIndex (a pad just threw someone up).
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BeatGrid = require(ReplicatedStorage:WaitForChild("BeatGrid"))

local Boss = {}

-- The shared helpers these moves use, from BossService (see Boss.init)
local now, flat, flatDistance, unitOr, rootOf, fightersIn
local setAction, setSlot, waitUntil, valid, recovery, targetPosition, healthShare, knockbackFrom
local pickTarget, breakShell, place, hitArea
local CombatService, PLAYER_RADIUS, STAND_HEIGHT
local K -- the whole kit (for its arena-copy helpers)

local FORMS = { "Cube", "Ship", "Ufo", "Wave" }
local PATTERN_SLOTS = 12 -- (the newest patterns, round and round these attributes)
-- half his size each way, per form (his real shape, for hits both ways)
local HALF = {
	Cube = Vector3.new(5, 5, 5),
	Ship = Vector3.new(5.5, 2.6, 5.5),
	Ufo = Vector3.new(6.5, 2.6, 6.5),
	Wave = Vector3.new(4, 2.2, 4),
}
local SLAM_HEIGHT = 12 -- (a landing's square is this tall: you can't jump over him landing on you)

----------------------------------------------------------------------
-- Little helpers
----------------------------------------------------------------------
local function byRound(E, v)
	if type(v) == "table" then
		return v[E.phase] or v[1]
	end
	return v
end

-- THE BEAT
local function beatLen(E)
	return BeatGrid.beatLen(E.def.Bpm)
end
local function beatTime(E, k)
	return BeatGrid.beatTime(E.beat0 or now(), E.def.Bpm, k)
end
-- the next beat at least `lead` seconds from now (so every screen hears of a
-- move in time), as its number
local function nextBeat(E, lead)
	return BeatGrid.beatAfter(E.beat0 or now(), E.def.Bpm, now() + (lead or 0.05))
end
-- how many beats he's open for, in the round he's in (round 2: less)
local function recBeats(E, n)
	return math.max(0, math.floor(recovery(E, n) + 0.5))
end

-- THE GRID
local function tileSpot(E, i, j)
	local c = BeatGrid.tileCenter(E.grid, i, j)
	return Vector3.new(c.X, E.floorY, c.Z)
end
-- the tile nearest a spot, kept inside his reach (Leash) from the middle
local function gridTile(E, pos)
	local g = E.grid
	local r = math.floor(E.def.Leash / g.size)
	local i = math.floor((pos.X - g.center.X) / g.size + g.half + 0.5)
	local j = math.floor((pos.Z - g.center.Z) / g.size + g.half + 0.5)
	return math.clamp(i, g.mid - r, g.mid + r), math.clamp(j, g.mid - r, g.mid + r)
end
-- the tile under a spot anywhere on the grid (its edge tiles too)
local function anyTile(E, pos)
	local g = E.grid
	local i = math.floor((pos.X - g.center.X) / g.size + g.half + 0.5)
	local j = math.floor((pos.Z - g.center.Z) / g.size + g.half + 0.5)
	return math.clamp(i, 0, g.n - 1), math.clamp(j, 0, g.n - 1)
end
-- a spot kept within his reach of the middle (a square)
local function pullIn(E, p)
	local c = E.grid.center
	local r = E.def.Leash
	return Vector3.new(math.clamp(p.X, c.X - r, c.X + r), E.floorY, math.clamp(p.Z, c.Z - r, c.Z + r))
end
-- from `p` toward `to`, but at most `most` studs (and never nearer than `keep`)
local function stepToward(p, to, most, keep)
	local d = flat(to - p)
	local len = d.Magnitude - (keep or 0)
	if len <= 0.01 then
		return p
	end
	return p + d.Unit * math.min(len, most)
end
-- is a spot on the runway (the drop spikes that too: nobody hides there)?
local function onRunway(E, pos)
	local a, b = E.runA, E.runB
	if not (a and b) then
		return false
	end
	return pos.X >= math.min(a.X, b.X) and pos.X <= math.max(a.X, b.X) and pos.Z >= math.min(a.Z, b.Z) and pos.Z <= math.max(a.Z, b.Z)
end

-- his form and which way is down for him
local function setForm(E, form)
	E.form = form
	E.model:SetAttribute("Form", form)
end
local function setGravity(E, g)
	E.gravity = g
	E.model:SetAttribute("Gravity", g)
end
-- how high his bottom is when he hangs from the ceiling
local function ceilingAlt(E)
	return (E.ceiling or E.def.Ceiling) - E.def.Size
end
-- his usual height above the tiles in a form (the cube on the ceiling: up there)
local function formHeight(E, form)
	form = form or E.form
	if form == "Cube" and E.gravity == -1 then
		return ceilingAlt(E)
	end
	return E.def.Forms[form].Height
end

----------------------------------------------------------------------
-- His motion (see BeatGrid.motion)
----------------------------------------------------------------------
-- where he is right now: his spot on the floor, and his height
local function here(E)
	if not E.move then
		return Vector3.new(E.pos.X, E.floorY, E.pos.Z), 0
	end
	local p, h = BeatGrid.motion(E.move, now())
	return Vector3.new(p.X, E.floorY, p.Z), h
end

local function publishMove(E, m)
	E.moveId = (E.moveId or 0) + 1
	E.move = m
	BeatGrid.writeMove(E.model, m, E.moveId)
end

local function holdMove(E, t0, t1, face)
	local p, h = here(E)
	local a = Vector3.new(p.X, h, p.Z)
	return { kind = "Hold", t0 = t0, t1 = t1, a = a, b = a, f = face or E.facing }
end
-- n hops from where he is to `to`, ending `toH` high, each `arc` high
local function hopMove(E, t0, t1, to, toH, arc, n, face)
	local p, h = here(E)
	return { kind = "Hop", t0 = t0, t1 = t1, a = Vector3.new(p.X, h, p.Z), b = Vector3.new(to.X, toH, to.Z), h = arc, n = n or 1,
		f = face or unitOr(flat(to - p), E.facing) }
end
local function flyMove(E, t0, t1, to, toH, ease, bob, n, face)
	local p, h = here(E)
	return { kind = "Fly", t0 = t0, t1 = t1, a = Vector3.new(p.X, h, p.Z), b = Vector3.new(to.X, toH, to.Z), h = bob or 0, n = n or 1,
		ease = ease or "io", f = face or unitOr(flat(to - p), E.facing) }
end
local function fallMove(E, t0, t1, toH)
	local p, h = here(E)
	return { kind = "Fall", t0 = t0, t1 = t1, a = Vector3.new(p.X, h, p.Z), b = Vector3.new(p.X, toH, p.Z), f = E.facing }
end

-- a move to its end; false if the fight moved on meanwhile
local function runMove(E, token, m)
	publishMove(E, m)
	return waitUntil(E, token, m.t1)
end
-- stay where he is until `t`
local function holdUntil(E, token, t)
	local s = now()
	if t > s then
		publishMove(E, holdMove(E, s, t))
	end
	return waitUntil(E, token, t)
end

----------------------------------------------------------------------
-- The level: tile patterns
----------------------------------------------------------------------
-- A tile attack: `p` = { kind, a, b, c, d, warn, hit, len, height } (see
-- BeatGrid). Published for every screen, and remembered here to hit whoever
-- is on one of its tiles (or, a "Trail", on its line) while it hurts.
local function spawnTiles(E, p, damage, knockback)
	E.patK = (E.patK or 0) + 1
	local text = BeatGrid.encode(p)
	E.model:SetAttribute("Tiles" .. ((E.patK - 1) % PATTERN_SLOTS + 1), text)
	E.model:SetAttribute("TilesK", E.patK)
	p = BeatGrid.decode(text) -- (exactly the numbers the screens get)
	local rec = { kind = p.kind, t0 = beatTime(E, p.hit), t1 = beatTime(E, p.hit + p.len), height = p.height,
		damage = damage, knockback = knockback, struck = {} }
	if p.kind == "Trail" then
		local c = E.grid.center
		rec.a = Vector3.new(c.X + p.a, E.floorY, c.Z + p.b)
		rec.b = Vector3.new(c.X + p.c, E.floorY, c.Z + p.d)
		rec.width = E.def.Attacks.ZigZag.Width
	else
		rec.set = {}
		for _, t in ipairs(BeatGrid.tiles(E.grid, p.kind, p.a, p.b, p.c, p.d)) do
			rec.set[BeatGrid.key(E.grid, t[1], t[2])] = true
		end
		rec.runway = p.kind == "Drop"
	end
	table.insert(E.patterns, rec)
end

local function tilesP(kind, a, b, c, d, warnAt, hitAt, len, height)
	return { kind = kind, a = a, b = b, c = c, d = d, warn = warnAt, hit = hitAt, len = len, height = height }
end

-- every frame: whoever is on a tile (or a trail) while it hurts, and not
-- above its spikes, is hit (once per pattern)
local function stepPatterns(E)
	if #E.patterns == 0 then
		return
	end
	local t = now()
	local list = nil
	for i = #E.patterns, 1, -1 do
		local pt = E.patterns[i]
		if t > pt.t1 then
			table.remove(E.patterns, i)
		elseif t >= pt.t0 then
			list = list or fightersIn(E)
			for _, p in ipairs(list) do
				local root = not pt.struck[p] and rootOf(p)
				if root then
					local pos = root.Position
					local inside, from = false, nil
					if pt.set then
						local ti, tj = BeatGrid.tileOf(E.grid, pos)
						if ti and pt.set[BeatGrid.key(E.grid, ti, tj)] then
							inside, from = true, tileSpot(E, ti, tj)
						elseif pt.runway and onRunway(E, pos) then
							inside, from = true, Vector3.new(pos.X, E.floorY, pos.Z + 1)
						end
					else
						local d, q = BeatGrid.segDistance(pos, pt.a, pt.b)
						if d <= pt.width / 2 + PLAYER_RADIUS then
							inside, from = true, q
						end
					end
					if inside and pos.Y - (E.floorY + STAND_HEIGHT) < pt.height * 0.8 then
						pt.struck[p] = true
						CombatService.DamagePlayer(p, pt.damage, from, knockbackFrom(from, root, pt.knockback, pt.knockback * 0.6))
					end
				end
			end
		end
	end
end

-- running into people (the swoop, the zig-zag): anyone touching his body
local function stepContact(E)
	local c = E.contact
	if not c or E.state ~= "Fighting" then
		return
	end
	if c.below and (E.alt or 0) > c.below then
		return -- (still too high up to touch anyone)
	end
	local half = HALF[E.form] or HALF.Cube
	local center = E.pos + Vector3.new(0, half.Y, 0)
	for _, p in ipairs(fightersIn(E)) do
		local root = not c.struck[p] and rootOf(p)
		if root then
			local rel = root.Position - center
			local nearest = center + Vector3.new(math.clamp(rel.X, -half.X, half.X), math.clamp(rel.Y, -half.Y, half.Y), math.clamp(rel.Z, -half.Z, half.Z))
			if (root.Position - nearest).Magnitude <= PLAYER_RADIUS + 0.8 then
				c.struck[p] = true
				CombatService.DamagePlayer(p, c.damage, E.pos, knockbackFrom(E.pos, root, c.knockback))
			end
		end
	end
end

-- THE JUMP PADS: anyone standing on one is thrown up (a moment between throws)
local function stepPads(E)
	if not (CombatService and CombatService.Launch) or not E.padSpots then
		return
	end
	local t = now()
	E.padUntil = E.padUntil or {}
	for _, p in ipairs(fightersIn(E)) do
		local root = rootOf(p)
		if root and t >= (E.padUntil[p] or 0) and root.Position.Y - (E.floorY + STAND_HEIGHT) < 1.5 then
			for k, spot in ipairs(E.padSpots) do
				if flatDistance(root.Position, spot) <= BeatGrid.PAD_RADIUS then
					E.padUntil[p] = t + E.def.Pads.Cooldown
					CombatService.Launch(p, Vector3.new(0, E.def.Pads.Power, 0))
					E.model:SetAttribute("PadIndex", k)
					E.model:SetAttribute("PadAt", t)
					break
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

-- HOP SLAM (cube): the square he'll land on (3 x 3 tiles) lights up at once -
-- slot 1 = its middle; he crouches, hops on the last beat of the Tell (the
-- whole hop is published now) and lands on it - then a ring of spikes pops
-- up round it on the next beat.
function Attacks.HopSlam(E, token)
	local a = E.def.Attacks.HopSlam
	local k0 = nextBeat(E, 0.12)
	setAction(E, "HopSlam", k0)
	local ti, tj = gridTile(E, targetPosition(E) or E.pos)
	local L = tileSpot(E, ti, tj)
	setSlot(E, 1, L)
	local tLand = beatTime(E, k0 + a.Tell)
	publishMove(E, hopMove(E, beatTime(E, k0 + a.Tell - 1), tLand, L, 0, E.def.Forms.Cube.HopHeight * 1.8, 1))
	spawnTiles(E, tilesP("Square", ti, tj, 1, 0, k0, k0 + a.Tell, 0.5, SLAM_HEIGHT), a.Damage, a.Knockback)
	spawnTiles(E, tilesP("Ring", ti, tj, a.Ring, 0, k0 + a.Tell, k0 + a.Tell + 1, 0.5, a.Height), a.SpikeDamage, a.SpikeKnockback)
	if not waitUntil(E, token, tLand) then
		return
	end
	holdUntil(E, token, beatTime(E, k0 + a.Tell + recBeats(E, a.Recovery)))
end

-- SPIKE ROWS (cube): he settles onto his tile with a stomp (slot 1) on the
-- beat the Tell ends, and rows of spikes march out from it, a tile a beat,
-- along the four straight lines (round 2: the diagonals too), each row lit a
-- beat before it spikes.
function Attacks.SpikeRows(E, token)
	local a = E.def.Attacks.SpikeRows
	local k0 = nextBeat(E, 0.12)
	setAction(E, "SpikeRows", k0)
	local ti, tj = gridTile(E, here(E))
	local L = tileSpot(E, ti, tj)
	setSlot(E, 1, L)
	publishMove(E, hopMove(E, beatTime(E, k0 + a.Tell - 1), beatTime(E, k0 + a.Tell), L, 0, 4, 1, E.facing))
	local diag = byRound(E, a.Diagonals) and 1 or 0
	for d = 1, a.Rows do
		local hit = k0 + a.Tell + d - 1
		spawnTiles(E, tilesP("Cross", ti, tj, d, diag, hit - 1, hit, 0.5, a.Height), a.Damage, a.Knockback)
	end
	if not waitUntil(E, token, beatTime(E, k0 + a.Tell + a.Rows - 1)) then
		return
	end
	holdUntil(E, token, beatTime(E, k0 + a.Tell + a.Rows - 1 + recBeats(E, a.Recovery)))
end

-- STOMP CHAIN (cube, round 2): Hops hop slams, one a beat: each square (3 x 3
-- tiles, slot h) is lit as he takes off for it; the last one's ring of spikes
-- pops up on the beat after it.
function Attacks.StompChain(E, token)
	local a = E.def.Attacks.StompChain
	local k0 = nextBeat(E, 0.12)
	setAction(E, "StompChain", k0)
	for h = 1, a.Hops do
		local ti, tj = gridTile(E, targetPosition(E) or E.pos)
		local L = tileSpot(E, ti, tj)
		setSlot(E, h, L)
		local tA, tB = beatTime(E, k0 + h - 1), beatTime(E, k0 + h)
		publishMove(E, hopMove(E, tA, tB, L, 0, E.def.Forms.Cube.HopHeight * 1.4, 1))
		spawnTiles(E, tilesP("Square", ti, tj, 1, 0, k0 + h - 1, k0 + h, 0.5, SLAM_HEIGHT), a.Damage, a.Knockback)
		if h == a.Hops then
			spawnTiles(E, tilesP("Ring", ti, tj, a.Ring, 0, k0 + h, k0 + h + 1, 0.5, a.Height), a.SpikeDamage, a.SpikeKnockback)
		end
		if not waitUntil(E, token, tB) then
			return
		end
	end
	holdUntil(E, token, beatTime(E, k0 + a.Hops + recBeats(E, a.Recovery)))
end

-- CEILING DROP (round 2, hanging from the ceiling): a hop a beat along the
-- ceiling after you (the square under him follows you) until the Lock; then
-- the square stays (slot 1) and he drops onto it at the end of the Tell - a
-- slam, a ring of spikes on the next beat - and he's stuck a moment before
-- falling back up.
function Attacks.CeilingDrop(E, token)
	local a = E.def.Attacks.CeilingDrop
	local cube = E.def.Forms.Cube
	local k0 = nextBeat(E, 0.12)
	setAction(E, "CeilingDrop", k0)
	local top = ceilingAlt(E)
	publishMove(E, holdMove(E, now(), beatTime(E, k0)))
	for b = 0, a.Lock - 1 do
		if not waitUntil(E, token, beatTime(E, k0 + b)) then
			return
		end
		local ti, tj = gridTile(E, stepToward(here(E), targetPosition(E) or E.pos, cube.Hop * E.grid.size))
		publishMove(E, hopMove(E, beatTime(E, k0 + b), beatTime(E, k0 + b + 1), tileSpot(E, ti, tj), top, -cube.HopHeight, 1))
	end
	if not waitUntil(E, token, beatTime(E, k0 + a.Lock)) then
		return
	end
	local ti, tj = gridTile(E, here(E))
	local L = tileSpot(E, ti, tj)
	setSlot(E, 1, L)
	local tLand = beatTime(E, k0 + a.Tell)
	publishMove(E, fallMove(E, beatTime(E, k0 + a.Tell - 0.5), tLand, 0))
	spawnTiles(E, tilesP("Square", ti, tj, 1, 0, k0 + a.Lock, k0 + a.Tell, 0.5, SLAM_HEIGHT), a.Damage, a.Knockback)
	spawnTiles(E, tilesP("Ring", ti, tj, a.Ring, 0, k0 + a.Tell, k0 + a.Tell + 1, 0.5, a.Height), a.SpikeDamage, a.SpikeKnockback)
	if not waitUntil(E, token, tLand) then
		return
	end
	-- stuck in the floor a moment (hit him!), then he falls back up
	if not holdUntil(E, token, beatTime(E, k0 + a.Tell + math.max(1, recBeats(E, a.Stuck)))) then
		return
	end
	runMove(E, token, fallMove(E, now(), now() + beatLen(E), top))
end

-- BOMB RUN (ship): a lane of tiles from beside him, through you, on across
-- the grid (slots 1..: each tile), lit at once; he lines up, then flies
-- along it, a bomb bursting on each tile as he passes over it (tile m on
-- beat k0 + Tell + m - 1).
function Attacks.BombRun(E, token)
	local a = E.def.Attacks.BombRun
	local k0 = nextBeat(E, 0.12)
	setAction(E, "BombRun", k0)
	local p, h = here(E)
	local si, sj = anyTile(E, p)
	local ai, aj = anyTile(E, targetPosition(E) or E.home)
	local di, dj = ai - si, aj - sj
	if di == 0 and dj == 0 then
		local f = E.facing
		di, dj = math.floor(f.X + 0.5), math.floor(f.Z + 0.5)
		if di == 0 and dj == 0 then
			di = 1
		end
	end
	local steps = math.max(math.abs(di), math.abs(dj))
	local ux, uz = di / steps, dj / steps
	local lane = {}
	for m = 1, a.Bombs do
		local i = math.floor(si + ux * m + 0.5)
		local j = math.floor(sj + uz * m + 0.5)
		if i < 0 or j < 0 or i >= E.grid.n or j >= E.grid.n then
			break
		end
		lane[#lane + 1] = { i, j }
	end
	if #lane == 0 then
		lane[1] = { ai, aj }
	end
	for m, t in ipairs(lane) do
		setSlot(E, m, tileSpot(E, t[1], t[2]))
		spawnTiles(E, tilesP("Tile", t[1], t[2], 0, 0, k0, k0 + a.Tell + m - 1, 0.5, a.Height), a.Damage, a.Knockback)
	end
	local last = tileSpot(E, lane[#lane][1], lane[#lane][2])
	local dir = unitOr(flat(last - p), E.facing)
	-- (hovering, turned along the lane, until the last beat of the Tell; then along it)
	local tGo = beatTime(E, k0 + a.Tell - 1)
	local tEnd = beatTime(E, k0 + a.Tell - 1 + #lane)
	publishMove(E, flyMove(E, tGo, tEnd, last, h, "lin", 0, 1, dir))
	if not waitUntil(E, token, tEnd) then
		return
	end
	holdUntil(E, token, beatTime(E, k0 + a.Tell - 1 + #lane + recBeats(E, a.Recovery)))
end

-- SWOOP (ship): the red lane (slot 1 = where he dives from, slot 2 = where it
-- ends) aims at you, then aims again as it locks (slot 3 = locked) a Lock
-- before the end of the Tell; then he dives down it (a beat, coming down as
-- he goes, running into anyone low enough to touch), skims the tiles for a
-- beat (your chance) and climbs away.
function Attacks.Swoop(E, token)
	local a = E.def.Attacks.Swoop
	local ship = E.def.Forms.Ship
	local k0 = nextBeat(E, 0.12)
	setAction(E, "Swoop", k0)
	local function aimLane()
		local p = here(E)
		local aim = targetPosition(E) or E.home
		local dir = unitOr(flat(aim - p), E.facing)
		local to = pullIn(E, p + dir * (flatDistance(aim, p) + 20))
		setSlot(E, 1, p)
		setSlot(E, 2, to)
		return to, unitOr(flat(to - p), dir)
	end
	local to, dir = aimLane()
	publishMove(E, holdMove(E, now(), beatTime(E, k0 + a.Tell - a.Lock), dir))
	if not waitUntil(E, token, beatTime(E, k0 + a.Tell - a.Lock)) then
		return
	end
	to, dir = aimLane()
	setSlot(E, 3, to)
	local tD0, tD1 = beatTime(E, k0 + a.Tell), beatTime(E, k0 + a.Tell + 1)
	publishMove(E, flyMove(E, tD0, tD1, to, 1.2, "lin", 0, 1, dir))
	if not waitUntil(E, token, tD0) then
		return
	end
	E.contact = { damage = a.Damage, knockback = a.Knockback, struck = {}, below = 5 }
	if not waitUntil(E, token, tD1) then
		E.contact = nil
		return
	end
	E.contact = nil
	-- skimming (low and slow: hit him), then up and away
	local tS = beatTime(E, k0 + a.Tell + 1 + a.Skim)
	if not runMove(E, token, flyMove(E, tD1, tS, pullIn(E, to + dir * 8), 1.2, "out", 0, 1, dir)) then
		return
	end
	if not runMove(E, token, flyMove(E, tS, tS + beatLen(E), pullIn(E, here(E) + dir * 6), ship.Height, "out", 0, 1, dir)) then
		return
	end
	holdUntil(E, token, now() + beatLen(E) * recBeats(E, a.Recovery))
end

-- UFO SLAM (UFO): a burst a beat after you, each a little higher (the circle
-- under him follows you), until the Lock; then it stays (slot 1) and he
-- slams down onto it on the last half beat of the Tell - then he's stuck.
function Attacks.UfoSlam(E, token)
	local a = E.def.Attacks.UfoSlam
	local ufo = E.def.Forms.Ufo
	local k0 = nextBeat(E, 0.12)
	setAction(E, "UfoSlam", k0)
	publishMove(E, holdMove(E, now(), beatTime(E, k0)))
	for b = 0, a.Lock - 1 do
		if not waitUntil(E, token, beatTime(E, k0 + b)) then
			return
		end
		local to = pullIn(E, stepToward(here(E), targetPosition(E) or E.home, 14))
		publishMove(E, hopMove(E, beatTime(E, k0 + b), beatTime(E, k0 + b + 1), to, ufo.Height + 2 * (b + 1), ufo.Burst, 1))
	end
	if not waitUntil(E, token, beatTime(E, k0 + a.Lock)) then
		return
	end
	local L = here(E)
	setSlot(E, 1, L)
	local tLand = beatTime(E, k0 + a.Tell)
	publishMove(E, fallMove(E, beatTime(E, k0 + a.Tell - 0.5), tLand, 0))
	if not waitUntil(E, token, tLand) then
		return
	end
	hitArea(E, L, a.Radius, a.Damage, a.Knockback)
	if not holdUntil(E, token, beatTime(E, k0 + a.Tell + math.max(1, recBeats(E, a.Stuck)))) then
		return
	end
	runMove(E, token, flyMove(E, now(), now() + beatLen(E), here(E), ufo.Height, "out"))
end

-- ORB RAIN (UFO): Orbs orbs onto tiles round you (slots 1..: the tiles; the
-- first right under you), one a beat, each tile lit Warn beats before its
-- orb lands; he bobs in place, a burst a beat.
function Attacks.OrbRain(E, token)
	local a = E.def.Attacks.OrbRain
	local ufo = E.def.Forms.Ufo
	local k0 = nextBeat(E, 0.12)
	setAction(E, "OrbRain", k0)
	local ci, cj = anyTile(E, targetPosition(E) or E.home)
	local used = {}
	for m = 1, a.Orbs do
		local i, j = ci, cj
		if m > 1 then
			for _ = 1, 16 do
				i = math.clamp(ci + E.rng:NextInteger(-a.Spread, a.Spread), 0, E.grid.n - 1)
				j = math.clamp(cj + E.rng:NextInteger(-a.Spread, a.Spread), 0, E.grid.n - 1)
				if not used[BeatGrid.key(E.grid, i, j)] then
					break
				end
			end
		end
		used[BeatGrid.key(E.grid, i, j)] = true
		local land = k0 + a.Warn + m - 1
		setSlot(E, m, tileSpot(E, i, j))
		spawnTiles(E, tilesP("Tile", i, j, 0, 0, land - a.Warn, land, 0.5, a.Height), a.Damage, a.Knockback)
	end
	local beats = a.Warn + a.Orbs - 1
	local p = here(E)
	if not runMove(E, token, hopMove(E, beatTime(E, k0), beatTime(E, k0 + beats), p, ufo.Height, 1.5, beats, E.facing)) then
		return
	end
	holdUntil(E, token, beatTime(E, k0 + beats + 0.5 + recBeats(E, a.Recovery)))
end

-- ZIG-ZAG (wave): Legs straight legs at 45 degrees, from him through you and
-- on (slots 1..Legs + 1: the corners, shown dotted at once); he zooms along
-- them, one leg a beat from the end of the Tell, running into anyone he
-- touches, and every leg he's done becomes a wall of light for Trail beats.
function Attacks.ZigZag(E, token)
	local a = E.def.Attacks.ZigZag
	local k0 = nextBeat(E, 0.12)
	setAction(E, "ZigZag", k0)
	local p, h = here(E)
	local aim = targetPosition(E) or E.home
	local dir = unitOr(flat(aim - p), E.facing)
	local to = pullIn(E, p + dir * math.max(flatDistance(aim, p) + 24, a.Legs * 10))
	local len = flatDistance(to, p)
	local m = { kind = "Zig", t0 = beatTime(E, k0 + a.Tell), t1 = beatTime(E, k0 + a.Tell + a.Legs), a = Vector3.new(p.X, h, p.Z),
		b = Vector3.new(to.X, h, to.Z), h = len / (2 * a.Legs), n = a.Legs, f = unitOr(flat(to - p), dir) }
	local pts = BeatGrid.zigPoints(m)
	for k, q in ipairs(pts) do
		setSlot(E, k, Vector3.new(q.X, E.floorY, q.Z))
	end
	local c = E.grid.center
	for k = 1, a.Legs do
		local q0, q1 = pts[k], pts[k + 1]
		spawnTiles(E, { kind = "Trail", a = q0.X - c.X, b = q0.Z - c.Z, c = q1.X - c.X, d = q1.Z - c.Z, warn = k0,
			hit = k0 + a.Tell + k, len = a.Trail, height = a.Height }, a.Damage, a.Knockback)
	end
	publishMove(E, m)
	if not waitUntil(E, token, m.t0) then
		return
	end
	E.contact = { damage = a.Damage, knockback = a.Knockback, struck = {} }
	if not waitUntil(E, token, m.t1) then
		E.contact = nil
		return
	end
	E.contact = nil
	holdUntil(E, token, beatTime(E, k0 + a.Tell + a.Legs + recBeats(E, a.Recovery)))
end

-- TILE PATTERN (any form): the level itself. A pair of patterns that
-- together cover the grid (the dark tiles and the light ones, odd rows and
-- even rows...): the first lights up now and spikes after the Tell, the
-- other lights up as it does and spikes a Tell later - Cycles in all. ActN =
-- the beat it counts from; slot 1 holds which pair (X) it is. He dances on
-- the spot.
local PAIRS = {
	{ { "Checker", 0, 0 }, { "Checker", 1, 0 } },
	{ { "Stripes", 0, 0 }, { "Stripes", 0, 1 } },
	{ { "Stripes", 1, 0 }, { "Stripes", 1, 1 } },
	{ { "Rings", 0, 0 }, { "Rings", 1, 0 } },
	{ { "Halves", 0, 0 }, { "Halves", 1, 0 } },
	{ { "Halves", 2, 0 }, { "Halves", 3, 0 } },
}
function Attacks.TilePattern(E, token)
	local a = E.def.Attacks.TilePattern
	local k0 = nextBeat(E, 0.12)
	setAction(E, "TilePattern", k0)
	local pick = E.rng:NextInteger(1, #PAIRS)
	setSlot(E, 1, Vector3.new(pick, 0, 0))
	local cycles = byRound(E, a.Cycles)
	for cyc = 0, cycles - 1 do
		local pp = PAIRS[pick][cyc % 2 + 1]
		spawnTiles(E, tilesP(pp[1], pp[2], pp[3], 0, 0, k0 + a.Tell * cyc, k0 + a.Tell * (cyc + 1), 0.5, a.Height), a.Damage, a.Knockback)
	end
	local beats = a.Tell * cycles + 1
	local p, h = here(E)
	local m
	if E.form == "Cube" then
		m = hopMove(E, beatTime(E, k0), beatTime(E, k0 + beats), p, h, (E.gravity == -1) and -2.5 or 2.5, beats, E.facing)
	else
		m = flyMove(E, beatTime(E, k0), beatTime(E, k0 + beats), p, h, "lin", 1, beats, E.facing)
	end
	runMove(E, token, m)
end

----------------------------------------------------------------------
-- The moves that aren't attacks: THE DROP, a portal, a gravity flip
----------------------------------------------------------------------
local Moves = {}
Boss.Moves = Moves

-- THE DROP: he rises to the middle of the grid, Rise high (two beats), while
-- the music builds (DROP IN 3... 2... 1...); every tile but the jump pads -
-- and the runway - lights up and spikes on beat k0 + Build. Then he crashes
-- down into the middle and he's STUNNED (a new action) for Stun beats.
function Moves.Drop(E, token)
	local d = E.def.Drop
	local k0 = nextBeat(E, 0.12)
	setAction(E, "Drop", k0)
	publishMove(E, flyMove(E, beatTime(E, k0), beatTime(E, k0 + 2), E.home, d.Rise, "io", 0, 1, E.homeFacing))
	spawnTiles(E, tilesP("Drop", 0, 0, 0, 0, k0 + 1, k0 + d.Build, 0.5, d.Height), d.Damage, d.Knockback)
	if not waitUntil(E, token, beatTime(E, k0 + d.Build)) then
		return
	end
	-- the crash (the level's gravity is back to normal)
	setGravity(E, 1)
	local tDown = beatTime(E, k0 + d.Build + 0.5)
	publishMove(E, fallMove(E, now(), tDown, 0))
	if not waitUntil(E, token, tDown) then
		return
	end
	setAction(E, "Stunned", k0 + d.Build + 0.5)
	if not holdUntil(E, token, beatTime(E, k0 + d.Build + 0.5 + d.Stun)) then
		return
	end
	local h = formHeight(E)
	if h > 0.1 then
		runMove(E, token, flyMove(E, now(), now() + beatLen(E), here(E), h, "out", 0, 1, E.facing))
	end
end

-- A PORTAL: a new form (any but this one - ActN = which, the number of it in
-- FORMS). The portal stands two tiles ahead of him, toward you (slot 1); he
-- flies through it over two beats, rising or falling to the new form's
-- height, and changes as he passes through (on the first beat).
function Moves.Portal(E, token)
	local k0 = nextBeat(E, 0.12)
	local options = {}
	for _, f in ipairs(FORMS) do
		if f ~= E.form then
			options[#options + 1] = f
		end
	end
	local new = options[E.rng:NextInteger(1, #options)]
	setAction(E, "Portal", table.find(FORMS, new))
	local p = here(E)
	local dir = unitOr(flat((targetPosition(E) or E.home) - p), E.facing)
	local gate = pullIn(E, p + dir * 16)
	local beyond = pullIn(E, p + dir * 28)
	setSlot(E, 1, gate)
	publishMove(E, flyMove(E, beatTime(E, k0), beatTime(E, k0 + 2), beyond, E.def.Forms[new].Height, "io", 0, 1, dir))
	if not waitUntil(E, token, beatTime(E, k0 + 1)) then
		return
	end
	setForm(E, new)
	waitUntil(E, token, beatTime(E, k0 + 2))
end

-- A GRAVITY FLIP (round 2, the cube): a gravity portal where he stands (slot
-- 1; ActN = which way is down afterwards: -1 = the ceiling); a beat later he
-- falls up to the ceiling grid - or back down to the floor, where he lands
-- with a slam (the square round him).
function Moves.Flip(E, token)
	local k0 = nextBeat(E, 0.12)
	local up = E.gravity ~= -1
	setAction(E, "Flip", up and -1 or 1)
	local p = here(E)
	setSlot(E, 1, p)
	publishMove(E, holdMove(E, now(), beatTime(E, k0)))
	if not waitUntil(E, token, beatTime(E, k0)) then
		return
	end
	setGravity(E, up and -1 or 1)
	if not up then
		local ti, tj = gridTile(E, p)
		spawnTiles(E, tilesP("Square", ti, tj, 1, 0, k0, k0 + 1, 0.5, SLAM_HEIGHT), E.def.Attacks.HopSlam.Damage, E.def.Attacks.HopSlam.Knockback)
	end
	runMove(E, token, fallMove(E, beatTime(E, k0), beatTime(E, k0 + 1), up and ceilingAlt(E) or 0))
end

----------------------------------------------------------------------
-- Getting about between moves: `beats` beats, on the beat
----------------------------------------------------------------------
-- (the heading from `aim` to `p`, the way BeatGrid's sums count it)
local function headingFrom(aim, p)
	local d = flat(p - aim)
	return math.atan2(d.X, d.Z)
end

local roamSide = 1
local function roam(E, token, beats)
	local k0 = nextBeat(E, 0.08)
	local t0, t1 = beatTime(E, k0), beatTime(E, k0 + beats)
	local aim = targetPosition(E) or E.home
	local p, h = here(E)
	local m
	if E.form == "Cube" then
		-- hops toward a spot about two tiles from you (along the floor, or the ceiling)
		local want = aim + unitOr(flat(p - aim), E.facing) * E.grid.size * 2.5
		local ti, tj = gridTile(E, stepToward(p, want, E.def.Forms.Cube.Hop * E.grid.size * beats))
		local top = (E.gravity == -1)
		m = hopMove(E, t0, t1, tileSpot(E, ti, tj), top and ceilingAlt(E) or 0, (top and -1 or 1) * E.def.Forms.Cube.HopHeight, beats)
	elseif E.form == "Ship" then
		-- a sweep round you, a good way off
		roamSide = -roamSide
		local ang = headingFrom(aim, p) + roamSide * math.rad(40 + 20 * beats)
		local to = pullIn(E, aim + Vector3.new(math.sin(ang), 0, math.cos(ang)) * 28)
		m = flyMove(E, t0, t1, to, E.def.Forms.Ship.Height, "io", E.def.Forms.Ship.Wobble, beats)
	elseif E.form == "Ufo" then
		-- bursts toward you (never right on top of you)
		m = hopMove(E, t0, t1, pullIn(E, stepToward(p, aim, 12 * beats, 12)), E.def.Forms.Ufo.Height, E.def.Forms.Ufo.Burst, beats, unitOr(flat(aim - p), E.facing))
	else
		-- the wave: a little zig-zag about you
		roamSide = -roamSide
		local ang = headingFrom(aim, p) + roamSide * math.rad(70)
		local to = pullIn(E, aim + Vector3.new(math.sin(ang), 0, math.cos(ang)) * 24)
		m = { kind = "Zig", t0 = t0, t1 = t1, a = Vector3.new(p.X, h, p.Z), b = Vector3.new(to.X, E.def.Forms.Wave.Height, to.Z),
			h = math.min(flatDistance(to, p) / (2 * math.max(beats, 1)), 8), n = math.max(beats, 1), f = unitOr(flat(to - p), E.facing) }
	end
	publishMove(E, m)
	return waitUntil(E, token, t1)
end

----------------------------------------------------------------------
-- His brain
----------------------------------------------------------------------
-- a weighted pick among the moves that suit his form, where he hangs from
-- and how far off you are
local function choose(E, aim)
	local d = flatDistance(aim, E.pos)
	local options, total = {}, 0
	for name, a in pairs(E.def.Attacks) do
		local w = a.Weight or 0
		if (a.Phase or 1) > E.phase or d < a.Range[1] or d > a.Range[2] then
			w = 0
		end
		if a.Form and a.Form ~= E.form then
			w = 0
		end
		if a.Gravity and a.Gravity ~= (E.gravity or 1) then
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
	if E.pendingDrop then
		-- (round 2 starts with THE DROP)
		E.pendingDrop = false
		E.sinceDrop = 0
		Moves.Drop(E, token)
		if not valid(E, token) then
			return false
		end
	end
	local target = pickTarget(E)
	local aim = target and targetPosition(E)
	if not aim then
		holdUntil(E, token, now() + 0.25)
		return valid(E, token)
	end
	if E.sinceDrop >= byRound(E, E.def.DropEvery) then
		E.sinceDrop = 0
		Moves.Drop(E, token)
	elseif E.gravity == -1 and E.sinceFlip >= E.def.FlipEvery then
		E.sinceFlip = 0
		Moves.Flip(E, token) -- (back down)
	elseif E.gravity ~= -1 and E.sinceForm >= byRound(E, E.def.FormEvery) then
		E.sinceForm = 0
		Moves.Portal(E, token)
	elseif E.phase >= 2 and E.gravity ~= -1 and E.form == "Cube" and E.sinceFlip >= E.def.FlipEvery then
		E.sinceFlip = 0
		Moves.Flip(E, token) -- (up to the ceiling)
	else
		local name = choose(E, aim)
		if name then
			E.history = { name, E.history[1] }
			Attacks[name](E, token)
			E.sinceDrop += 1
			E.sinceForm += 1
			E.sinceFlip += 1
		else
			roam(E, token, 1)
		end
	end
	if not valid(E, token) then
		return false
	end
	E.contact = nil
	-- a breather: getting about, on the beat
	local b = byRound(E, E.def.Breather)
	local beats = b[1] + E.rng:NextInteger(0, math.max(0, b[2] - b[1]))
	if beats > 0 then
		setAction(E, "Idle", nil)
		roam(E, token, beats)
	end
	return valid(E, token)
end

local function freeze(E)
	E.contact = nil
	if E.move then
		publishMove(E, holdMove(E, now(), now() + 0.05))
	end
end

-- Gridlock's fight: round and round the cycle, each go protected (an error
-- in one move is reported once and he carries on with the next)
function Boss.brain(E, token)
	E.contact = nil
	if E.phase == 1 then
		-- THE LEVEL STARTS: the beat counts from the start of the wake (when
		-- the music starts), set once a fight - not again after round 2 begins
		local wakeAt = (E.model:GetAttribute("Action") == "Wake") and E.model:GetAttribute("ActionStart") or now()
		E.beat0 = (tonumber(wakeAt) or now()) + (E.def.BeatOffset or 0)
		E.model:SetAttribute("BeatStart", E.beat0)
		E.model:SetAttribute("Bpm", E.def.Bpm)
		E.sinceDrop, E.sinceForm, E.sinceFlip = 0, 0, 0
		E.pendingDrop = false
		E.history = {}
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
-- Every frame: exactly where his move puts him, the level hurting people,
-- running into people, and the jump pads
----------------------------------------------------------------------
function Boss.step(E, dt)
	if E.move then
		local p, h = BeatGrid.motion(E.move, now())
		E.alt = h
		E.pos = Vector3.new(p.X, E.floorY + h, p.Z)
		if E.move.f and E.move.f.Magnitude > 0.01 then
			E.facing = E.move.f
		end
	end
	place(E)
	stepPatterns(E)
	stepContact(E)
	stepPads(E)
	local _ = dt
end

----------------------------------------------------------------------
-- Hooks (see BossService: they run at these moments)
----------------------------------------------------------------------
function Boss.init(kit)
	K = kit
	now, flat, flatDistance, unitOr, rootOf, fightersIn = kit.now, kit.flat, kit.flatDistance, kit.unitOr, kit.rootOf, kit.fightersIn
	setAction, setSlot, waitUntil, valid = kit.setAction, kit.setSlot, kit.waitUntil, kit.valid
	recovery, targetPosition, healthShare, knockbackFrom = kit.recovery, kit.targetPosition, kit.healthShare, kit.knockbackFrom
	pickTarget, breakShell, place, hitArea = kit.pickTarget, kit.breakShell, kit.place, kit.hitArea
	CombatService, PLAYER_RADIUS, STAND_HEIGHT = kit.CombatService, kit.PLAYER_RADIUS, kit.STAND_HEIGHT
end

-- back to how he starts: a cube, the right way up, standing still, nothing lit
local function tidy(E)
	E.patterns = {}
	E.contact = nil
	setForm(E, "Cube")
	setGravity(E, 1)
end

-- Built: the grid found (GridBuilder's model), the pads and the runway, and
-- CombatService told his real shape (a box round whatever form he's in)
function Boss.onBuild(E)
	local arena = K.arenaWith(E, "Tiles") -- (his own arena copy)
	local center = arena and arena:GetAttribute("Center") or E.home
	E.grid = BeatGrid.grid(Vector3.new(center.X, E.floorY, center.Z), arena and arena:GetAttribute("Tiles") or 15, arena and arena:GetAttribute("TileSize") or 8)
	E.ceiling = arena and arena:GetAttribute("Ceiling") or E.def.Ceiling
	E.runA = arena and arena:GetAttribute("RunwayA") or nil
	E.runB = arena and arena:GetAttribute("RunwayB") or nil
	E.padSpots = {}
	for _, t in ipairs(BeatGrid.pads(E.grid)) do
		E.padSpots[#E.padSpots + 1] = tileSpot(E, t[1], t[2])
	end
	tidy(E)
	publishMove(E, holdMove(E, now(), now() + 0.05, E.homeFacing))
	CombatService.SetTargetShape(E.model, function(from)
		local half = HALF[E.form] or HALF.Cube
		local center3 = E.pos + Vector3.new(0, half.Y, 0)
		local rel = from - center3
		return center3 + Vector3.new(math.clamp(rel.X, -half.X, half.X), math.clamp(rel.Y, -half.Y, half.Y), math.clamp(rel.Z, -half.Z, half.Z)), 0.6
	end)
end

-- Everyone left or died: he stops where he is (BossService brings him home)
function Boss.onReset(E)
	freeze(E)
	E.patterns = {}
end

-- Home again: a cube in the middle, the right way up
function Boss.onHome(E)
	tidy(E)
	publishMove(E, { kind = "Hold", t0 = now(), t1 = now() + 0.05, a = Vector3.new(E.home.X, 0, E.home.Z), b = Vector3.new(E.home.X, 0, E.home.Z), f = E.homeFacing })
end

-- ROUND 2 (half health): GRAVITY FLIP! Whatever form he's in he's a cube
-- again, and as the shell bursts he falls UP to the ceiling. Round 2 begins
-- with THE DROP.
function Boss.onBreak(E)
	E.patterns = {}
	E.contact = nil
	local t = now()
	local hit = t + E.def.BreakTime * 0.35
	setForm(E, "Cube")
	publishMove(E, fallMove(E, hit, hit + 0.6, ceilingAlt(E)))
	setGravity(E, -1)
	E.pendingDrop = true
	E.sinceFlip = 0
	E.sinceForm = 0
end

function Boss.onDie(E)
	freeze(E)
	E.patterns = {}
end

return Boss
