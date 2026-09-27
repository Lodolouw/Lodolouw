--[[
	BeatGrid  (ModuleScript, parent: ReplicatedStorage, name: "BeatGrid")

	The sums behind Gridlock's level (floor 6), shared by the server
	(ServerScriptService/Bosses/Gridlock.lua) and every player's screen
	(ReplicatedStorage/BossBodies/Gridlock.lua), so everyone sees exactly what
	will hit them, and when:
	  * THE GRID: the floor is Tiles x Tiles square tiles, Size studs each,
	    round the arena's middle (GridBuilder builds it). A tile is (i, j), both
	    counted from 0; i runs along +X, j along +Z.
	  * THE BEAT: everything lands on it. Beat k is at beat0 + k * 60 / Bpm.
	  * PATTERNS: which tiles light up and spike - rows marching out from him,
	    a ring, checkers, stripes... - each made from a few numbers, so the
	    server only publishes those numbers and every screen makes the same tiles.
	  * HIS MOTION: where he is at any moment of a hop, a flight or a fall.
	    Every screen uses the same sums as the server.
]]

local BeatGrid = {}

local function clamp(x, a, b)
	return math.max(a, math.min(b, x))
end

----------------------------------------------------------------------
-- The grid
----------------------------------------------------------------------
-- the grid round `center` (a point on the tiles' top): `tiles` across, each
-- `size` studs
function BeatGrid.grid(center, tiles, size)
	return { center = center, n = tiles, size = size, half = (tiles - 1) / 2, mid = math.floor(tiles / 2) }
end

-- the middle of tile (i, j), on the tiles' top
function BeatGrid.tileCenter(g, i, j)
	return Vector3.new(g.center.X + (i - g.half) * g.size, g.center.Y, g.center.Z + (j - g.half) * g.size)
end

-- the tile a spot is over (nil if it's off the grid)
function BeatGrid.tileOf(g, pos)
	local i = math.floor((pos.X - g.center.X) / g.size + g.half + 0.5)
	local j = math.floor((pos.Z - g.center.Z) / g.size + g.half + 0.5)
	if i < 0 or j < 0 or i >= g.n or j >= g.n then
		return nil, nil
	end
	return i, j
end

-- a tile as one number (for sets of tiles)
function BeatGrid.key(g, i, j)
	return i * g.n + j
end

-- THE JUMP PADS: the tiles that have one, out from the middle tile (GridBuilder
-- puts a pad on each; THE DROP spikes every tile but these)
BeatGrid.PADS = { { -4, -4 }, { 4, -4 }, { -4, 4 }, { 4, 4 }, { 0, -5 }, { 0, 5 }, { -5, 0 }, { 5, 0 } }
BeatGrid.PAD_RADIUS = 3.2 -- (step inside this, round a pad's middle, and it throws you up)

function BeatGrid.pads(g)
	local list = {}
	for _, o in ipairs(BeatGrid.PADS) do
		list[#list + 1] = { g.mid + o[1], g.mid + o[2] }
	end
	return list
end

function BeatGrid.padSet(g)
	local set = {}
	for _, p in ipairs(BeatGrid.pads(g)) do
		set[BeatGrid.key(g, p[1], p[2])] = true
	end
	return set
end

----------------------------------------------------------------------
-- The beat
----------------------------------------------------------------------
function BeatGrid.beatLen(bpm)
	return 60 / math.max(bpm or 120, 30)
end

-- the moment of beat `k` (it can be a fraction: 2.5 is halfway to beat 3)
function BeatGrid.beatTime(beat0, bpm, k)
	return beat0 + k * BeatGrid.beatLen(bpm)
end

-- the number of the first beat at or after moment `t`
function BeatGrid.beatAfter(beat0, bpm, t)
	return math.ceil((t - beat0) / BeatGrid.beatLen(bpm) - 1e-4)
end

-- how far through its beat moment `t` is (0 right on the beat, nearly 1 just before the next)
function BeatGrid.beatPhase(beat0, bpm, t)
	local x = (t - beat0) / BeatGrid.beatLen(bpm)
	return x - math.floor(x)
end

----------------------------------------------------------------------
-- Patterns: which tiles
----------------------------------------------------------------------
local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local DIAGS = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

-- The tiles of a pattern, as a list of { i, j } (always in the same order):
--   Tile     a, b = the tile
--   Square   a, b = the middle tile; c = how far out (every tile inside)
--   Ring     a, b = the middle tile; c = how far out (just the square ring)
--   Cross    a, b = the middle tile; c = which row out (1, 2, 3...) along the
--            four straight lines; d = 1: along the diagonals too
--   Checker  a = 0 or 1 (which colour of a chessboard)
--   Stripes  a = 0: rows (along X), 1: columns (along Z); b = 0 or 1 (which)
--   Rings    a = 0 or 1: every other square ring round the middle
--   Halves   a = 0-3: the half of the grid on one side of the middle line
--            (-X, +X, -Z, +Z; the middle line itself is left safe)
--   Drop     every tile except the jump pads
-- ("Trail" patterns aren't tiles: see BeatGrid.segDistance.)
function BeatGrid.tiles(g, kind, a, b, c, d)
	local out = {}
	local n = g.n
	local function add(i, j)
		if i >= 0 and j >= 0 and i < n and j < n then
			out[#out + 1] = { i, j }
		end
	end
	a, b, c, d = a or 0, b or 0, c or 0, d or 0
	if kind == "Tile" then
		add(a, b)
	elseif kind == "Square" or kind == "Ring" then
		for i = a - c, a + c do
			for j = b - c, b + c do
				if kind == "Square" or math.max(math.abs(i - a), math.abs(j - b)) == c then
					add(i, j)
				end
			end
		end
	elseif kind == "Cross" then
		for _, dir in ipairs(DIRS) do
			add(a + dir[1] * c, b + dir[2] * c)
		end
		if d == 1 then
			for _, dir in ipairs(DIAGS) do
				add(a + dir[1] * c, b + dir[2] * c)
			end
		end
	elseif kind == "Checker" then
		for i = 0, n - 1 do
			for j = 0, n - 1 do
				if (i + j) % 2 == a then
					add(i, j)
				end
			end
		end
	elseif kind == "Stripes" then
		for i = 0, n - 1 do
			for j = 0, n - 1 do
				if ((a == 0) and j or i) % 2 == b then
					add(i, j)
				end
			end
		end
	elseif kind == "Rings" then
		for i = 0, n - 1 do
			for j = 0, n - 1 do
				if math.max(math.abs(i - g.mid), math.abs(j - g.mid)) % 2 == a then
					add(i, j)
				end
			end
		end
	elseif kind == "Halves" then
		for i = 0, n - 1 do
			for j = 0, n - 1 do
				local v = (a < 2) and i or j
				if (a % 2 == 0 and v < g.mid) or (a % 2 == 1 and v > g.mid) then
					add(i, j)
				end
			end
		end
	elseif kind == "Drop" then
		local pads = BeatGrid.padSet(g)
		for i = 0, n - 1 do
			for j = 0, n - 1 do
				if not pads[BeatGrid.key(g, i, j)] then
					add(i, j)
				end
			end
		end
	end
	return out
end

-- how far a flat spot is from the segment a-b (for the wave's wall of light),
-- and the nearest point on it
function BeatGrid.segDistance(p, a, b)
	local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local ap = Vector3.new(p.X - a.X, 0, p.Z - a.Z)
	local len2 = ab:Dot(ab)
	local u = (len2 > 1e-6) and clamp(ap:Dot(ab) / len2, 0, 1) or 0
	local q = Vector3.new(a.X + ab.X * u, a.Y, a.Z + ab.Z * u)
	return Vector3.new(p.X - q.X, 0, p.Z - q.Z).Magnitude, q
end

----------------------------------------------------------------------
-- Patterns as they're published: one string each
----------------------------------------------------------------------
-- A pattern: { kind, a, b, c, d, warn, hit, len, height } - the tiles (see
-- BeatGrid.tiles; for a "Trail", a b = one end and c d = the other, studs
-- from the grid's middle), the beat its warning shows from, the beat it
-- hurts from, how many beats it hurts for, and how tall its spikes are.
local FIELDS = { "kind", "a", "b", "c", "d", "warn", "hit", "len", "height" }

local function short(x)
	local s = string.format("%.3f", x)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	if s == "-0" then
		s = "0"
	end
	return s
end

function BeatGrid.encode(p)
	local parts = { tostring(p.kind) }
	for k = 2, #FIELDS do
		parts[k] = short(tonumber(p[FIELDS[k]]) or 0)
	end
	return table.concat(parts, ",")
end

function BeatGrid.decode(s)
	if type(s) ~= "string" then
		return nil
	end
	local p = {}
	local k = 0
	for piece in string.gmatch(s, "[^,]+") do
		k = k + 1
		local name = FIELDS[k]
		if not name then
			break
		end
		p[name] = (k == 1) and piece or (tonumber(piece) or 0)
	end
	if k < #FIELDS then
		return nil
	end
	return p
end

----------------------------------------------------------------------
-- His motion
----------------------------------------------------------------------
local function ease(kind, u)
	if kind == "in" then
		return u * u
	elseif kind == "out" then
		return 1 - (1 - u) * (1 - u)
	elseif kind == "io" then
		return u * u * (3 - 2 * u)
	end
	return u
end
BeatGrid.ease = ease

-- The corners of a zig-zag move (the wave's path): n legs from a to b,
-- swinging `h` studs out to one side and then the other (the first leg
-- starts on the line, the last ends on it). a and b's Y is his height.
function BeatGrid.zigPoints(m)
	local n = math.max(1, math.floor(m.n or 1))
	local d = Vector3.new(m.b.X - m.a.X, 0, m.b.Z - m.a.Z)
	local side = (d.Magnitude > 1e-3) and Vector3.new(-d.Unit.Z, 0, d.Unit.X) or Vector3.new(1, 0, 0)
	local pts = {}
	for k = 0, n do
		local s = 0
		if k > 0 and k < n then
			s = (k % 2 == 1) and 1 or -1
		end
		pts[k + 1] = m.a:Lerp(m.b, k / n) + side * (m.h or 0) * s
	end
	return pts
end

-- Where a move puts him at moment `t`: his spot on the floor (Y = 0), his
-- HEIGHT above the tiles, and how far through the move he is (0-1). A move:
--   { kind, t0, t1, a, b, h, n, ease, f }
--   kind "Hold" (still at a), "Hop" (a to b in n hops, each up `h` and back
--   down - the cube's hop; a negative h dips down - a hop along the
--   ceiling), "Fly" (a to b, `ease`, bobbing `h` up and down n times),
--   "Fall" (a to b, faster and faster: dropping out of the sky, or falling up
--   to the ceiling), "Zig" (a to b in n straight legs, swinging h out to the
--   sides - the wave: see BeatGrid.zigPoints).
--   a and b are spots whose Y is his height above the tiles there; f is the
--   way he faces.
function BeatGrid.motion(m, t)
	local u = clamp((t - m.t0) / math.max(m.t1 - m.t0, 1e-3), 0, 1)
	local kind = m.kind
	if kind == "Hold" then
		return Vector3.new(m.a.X, 0, m.a.Z), m.a.Y, u
	end
	local n = math.max(1, math.floor(m.n or 1))
	if kind == "Zig" then
		local pts = BeatGrid.zigPoints(m)
		local x = u * n
		local k = math.min(math.floor(x), n - 1)
		local p = pts[k + 1]:Lerp(pts[k + 2], x - k)
		return Vector3.new(p.X, 0, p.Z), p.Y, u
	end
	local e = u
	if kind == "Fall" then
		e = u * u
	elseif kind == "Fly" then
		e = ease(m.ease, u)
	end
	local p = m.a:Lerp(m.b, e)
	local y = p.Y
	if kind == "Hop" then
		local x = u * n
		local v = x - math.min(math.floor(x), n - 1)
		y = y + (m.h or 0) * 4 * v * (1 - v)
	elseif kind == "Fly" and (m.h or 0) ~= 0 then
		y = y + m.h * math.sin(u * math.pi * 2 * n)
	end
	return Vector3.new(p.X, 0, p.Z), y, u
end

-- The move published on his model (the server writes it; nil if none yet)
function BeatGrid.readMove(model)
	local k = model:GetAttribute("MoveK")
	local a, b = model:GetAttribute("MoveA"), model:GetAttribute("MoveB")
	if type(k) ~= "string" or typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" then
		return nil
	end
	local f = model:GetAttribute("MoveF")
	return {
		kind = k,
		t0 = model:GetAttribute("MoveT0") or 0,
		t1 = model:GetAttribute("MoveT1") or 0,
		a = a,
		b = b,
		h = model:GetAttribute("MoveH") or 0,
		n = model:GetAttribute("MoveN") or 1,
		ease = model:GetAttribute("MoveE") or "lin",
		f = typeof(f) == "Vector3" and f or nil,
		id = model:GetAttribute("MoveId") or 0,
	}
end

function BeatGrid.writeMove(model, m, id)
	model:SetAttribute("MoveK", m.kind)
	model:SetAttribute("MoveT0", m.t0)
	model:SetAttribute("MoveT1", m.t1)
	model:SetAttribute("MoveA", m.a)
	model:SetAttribute("MoveB", m.b)
	model:SetAttribute("MoveH", m.h or 0)
	model:SetAttribute("MoveN", m.n or 1)
	model:SetAttribute("MoveE", m.ease or "lin")
	if m.f then
		model:SetAttribute("MoveF", m.f)
	end
	model:SetAttribute("MoveId", id) -- last, so the rest is in place when a screen sees it
end

return BeatGrid
