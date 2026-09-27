--[[
	DunesBuilder  (ModuleScript, parent: ServerScriptService, name: "DunesBuilder")

	Builds the Spire's second floor: THE SUNKEN DUNES, Tuber's cactus desert.

	An old colosseum the desert swallowed whole, where a garden of cacti has
	grown up since. You come in through a sandstone gate cut into the canyon
	wall and step out onto a wide, flat bowl of sand - the arena floor, buried
	long ago - ringed by the tops of its old arches poking out of the dunes.
	Beyond them the dunes climb to towering striped canyon cliffs, with sand
	pouring off their lips. Across from the gate a half-buried temple and two
	seated colossi watch the bowl.

	Cacti stand all over the floor and up the dunes: tall saguaros, squat
	barrels, prickly pears and little lumpy tuberlings. In the very middle is a
	tiny garden where TUBER sleeps - a chubby, potato-shaped stack of cactus.
	When he has lost 30% of his health he rips every cactus in the arena out of
	the ground and becomes THE BRUTE, THE CACTUS KING, a giant cactus golem, and
	the desert's animals come to watch round 2. Seven chunky sandstone rocks on
	the floor are the only things in the way: his rolling cactus balls bounce
	off them, and his needles stop at them.

	Everything the fight needs is marked for BossService/BossClient:
	  * "ArenaSpawn"   where you arrive (in this model, Floor = 2)
	  * "ArenaExit"    the Leave prompt on the gate's golden fog
	  * "BossHome"     the centre of the bowl, in Tuber's garden (Floor = 2)
	  * "DesertRock"   each rock: a Model with Floor, Index (1-7), Radius (its
	    flat footprint, a circle round its middle - what things bounce off) and
	    Height (how high its top is above the floor); its PrimaryPart is the
	    "RockCore" in its middle. You can stand on them.
	  * "DuneCactus"   each cactus: a Model with Floor, Index (1 is the nearest
	    the middle), Kind ("Saguaro", "Barrel", "Pear" or "Tuberling") and Delay
	    (0 for the nearest up to 1 for the farthest: when it flies to the
	    Brute); its PrimaryPart is the "CactusBase" at its foot. Nothing on a
	    cactus can be bumped into or hit by a raycast.
	  * "DuneLookout"  an invisible part where an animal stands to watch round
	    2: Floor, Kind ("Camel", "Meerkat", "Vulture" or "Lizard") and Index. It
	    sits exactly on the ground (or branch) the animal stands on, facing the
	    middle.
	  * "DuneEdgeWall" the invisible walls round the sand you fight on
	  * the model itself carries Floor, Center, FightRadius (how far out the
	    invisible wall stands) and Storm (how hard the sand blows: 0..1, read by
	    the ArenaAmbience script on each player's screen)

	Main calls DunesBuilder.Build() once at startup, right after the lobby.
	The dunes are smooth Terrain sand; the floor you fight on and everything
	else is ordinary Parts. Every "random" choice comes from our own dice,
	which roll the same numbers every time, so every server builds the very
	same arena.
]]

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local DunesBuilder = {}

local V3 = Vector3.new
local RGB = Color3.fromRGB
local Mat = Enum.Material

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------
local CENTER = V3(2600, 0, 2600) -- well away from the lobby and Gloomgut's Hollow
local FIGHT_R = 150 -- the flat sand you fight on (the invisible wall stands here)
local GARDEN_R = 12 -- Tuber's little garden in the very middle (kept clear)
local GATE_R = 180 -- the gate, cut into the south cliff
local CLIFF_R = 238 -- the canyon wall
local WIND = V3(1, 0, 0.35).Unit -- which way the sand blows
local ARCH_SLOTS = 30 -- the old arches stand in 30 even places round the ring
local EDGE_BRAZIERS = { 0.55, -0.55, 1.55, -1.7, 2.62, -2.55 } -- round the floor's edge

-- The seven rocks on the floor: { angle, how far from the centre, Radius }
-- (angles as in onRing below: 0 is the gate, pi the temple)
local ROCKS = {
	{ 0.55, 58, 6 },
	{ 1.55, 96, 8 },
	{ 2.45, 64, 5.5 },
	{ 3.30, 104, 7.5 },
	{ 4.20, 70, 6.5 },
	{ 5.00, 110, 8 },
	{ 5.75, 84, 5.5 },
}

-- Where the animals come to watch round 2 (see buildLookouts). The camels and
-- meerkats stand in the gaps between the old arches - gap k is the one
-- between arch k-1 and arch k - so nothing hides them from the fight.
local CAMEL_GAPS = { 5, 11, 18, 24 }
local MEERKAT_GAPS = { 3, 8, 20, 26 }
local LIZARD_ANGLES = { 1.30, 4.36, 5.52 } -- on low rocks at the floor's edge
local TREE_ANGLES = { 0.86, 2.02, 4.70, 5.25 } -- dead trees up on the dunes
local VULTURE_TREES = { 1, 2, 3 } -- (which of those trees a vulture sits in)

----------------------------------------------------------------------
-- Palette
----------------------------------------------------------------------
local SAND = RGB(226, 190, 130)
local SAND_DARK = RGB(204, 166, 108)
local SAND_LIGHT = RGB(240, 212, 160)
local STONE = RGB(214, 172, 114) -- sandstone
local STONE_DARK = RGB(178, 134, 86)
local STONE_DEEP = RGB(146, 102, 64)
local STRATA = {
	RGB(224, 180, 120),
	RGB(204, 146, 92),
	RGB(186, 122, 78),
	RGB(232, 198, 144),
	RGB(168, 106, 70),
	RGB(214, 160, 104),
}
local BONE = RGB(236, 226, 202)
local BONE_DARK = RGB(204, 190, 158)
local CLOTH = { RGB(128, 40, 46), RGB(70, 58, 120), RGB(160, 96, 42) }
local FIRE_LIGHT = RGB(255, 170, 90)
local FOG_GOLD = RGB(255, 224, 158)
local SHADOW = RGB(46, 34, 26)
-- the cacti (and Tuber) - the same bright 8-bit greens
local CACTUS_GREEN = RGB(99, 199, 77)
local CACTUS_MID = RGB(62, 137, 72)
local CACTUS_DEEP = RGB(38, 92, 66)
local SPINE = RGB(234, 212, 170)
local FLOWER_PINK = RGB(246, 117, 122)
local FLOWER_YELLOW = RGB(254, 231, 97)
local TILLED = RGB(184, 140, 90) -- dug-over sand in Tuber's garden
local TILLED_DARK = RGB(156, 114, 72)
local PEBBLES = { STONE_DARK, STONE_DEEP, RGB(170, 160, 146) }
local SCRUB = { RGB(138, 142, 84), RGB(112, 120, 70), RGB(160, 150, 92) }
local TUMBLE = { RGB(150, 112, 70), RGB(122, 90, 58) }

----------------------------------------------------------------------
-- Helpers (the same kinds of little builders as the lobby's)
----------------------------------------------------------------------
-- Our own dice: the same "random" numbers every time, from the same start.
-- Build() starts them again for each piece of the arena (see the bottom).
local seed = 20260924
local function rnd()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
local function between(a, b)
	return a + (b - a) * rnd()
end

local m -- the arena model, set by Build()

local function part(name, size, cf, color, material, extra, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Mat.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if extra then
		for k, v in pairs(extra) do
			p[k] = v
		end
	end
	p.Parent = parent or m
	return p
end

local function merge(a, b)
	local out = {}
	for k, v in pairs(a or {}) do
		out[k] = v
	end
	for k, v in pairs(b or {}) do
		out[k] = v
	end
	return out
end

local function ball(name, d, cf, color, material, extra, parent)
	return part(name, V3(d, d, d), cf, color, material, merge(extra, { Shape = Enum.PartType.Ball }), parent)
end

-- A stretched sphere. (A Ball part always renders round at its smallest side,
-- so anything egg-shaped is a block with a sphere mesh in it.)
local function ellipsoid(name, size, cf, color, material, extra, parent)
	local p = part(name, size, cf, color, material, extra, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Upright cylinder: `cf` is the centre, the axis points up
local function cylinder(name, height, d, cf, color, material, extra, parent)
	return part(name, V3(height, d, d), cf * CFrame.Angles(0, 0, math.pi / 2), color, material,
		merge(extra, { Shape = Enum.PartType.Cylinder }), parent)
end

-- A cylinder lying along the line from a to b
local function rod(name, a, b, d, color, material, extra, parent)
	local len = (b - a).Magnitude
	return part(name, V3(len, d, d), CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), color, material,
		merge(extra, { Shape = Enum.PartType.Cylinder }), parent)
end

-- A block stretched along the line from a to b (for bones, branches, twigs)
local function beam(name, a, b, thick, color, material, extra, parent)
	local len = (b - a).Magnitude
	return part(name, V3(thick, thick, len + thick * 0.4), CFrame.lookAt((a + b) / 2, b), color, material, extra, parent)
end

-- A WedgePart. Roblox wedges are full height at their back (+Z) and slope down
-- to nothing at their front (-Z).
local function wedge(name, size, cf, color, material, extra, parent)
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Material = material or Mat.SmoothPlastic
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	if extra then
		for k, v in pairs(extra) do
			w[k] = v
		end
	end
	w.Parent = parent or m
	return w
end

local function anchorPart(name, cf, parent)
	return part(name, V3(1, 1, 1), cf, RGB(255, 255, 255), Mat.SmoothPlastic, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	}, parent)
end

local function pulse(p, speed, lo, hi)
	p:SetAttribute("PulseSpeed", speed)
	p:SetAttribute("PulseMin", lo)
	p:SetAttribute("PulseMax", hi)
	p:SetAttribute("Phase", rnd() * 360)
	CollectionService:AddTag(p, "Pulse")
end

-- walking into this box opens the "Leave?" check (SpireClient watches these)
local function autoZone(cf, size, attr, value)
	local z = part("AutoOpenZone", size, cf, RGB(255, 255, 255), Mat.SmoothPlastic, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	z:SetAttribute(attr, value)
	CollectionService:AddTag(z, "AutoOpenZone")
	return z
end

local function at(x, y, z)
	return CENTER + V3(x, y, z)
end
-- angle 0 is south (+Z, the gate); pi/2 is east; pi is north (the temple)
local function onRing(r, a, y)
	return CENTER + V3(math.sin(a) * r, y, math.cos(a) * r)
end
local function facingCentre(p)
	return CFrame.lookAt(p, V3(CENTER.X, p.Y, CENTER.Z))
end
local function wrap(a) -- to -pi..pi
	return (a + math.pi) % (2 * math.pi) - math.pi
end
-- the angle of the gap between old arch k-1 and arch k (see buildArcade)
local function archGap(k)
	return k / ARCH_SLOTS * math.pi * 2
end

-- small decoration: no collisions, no raycasts, no shadow
local DECOR = { CanCollide = false, CanQuery = false, CastShadow = false }
-- big scenery nobody can reach: no collisions or raycasts, but it does shade
local SCENERY = { CanCollide = false, CanQuery = false }
-- a rock you can stand on: solid, and seen by raycasts (so the game can tell
-- you're standing on something), but touching it does nothing
local ROCK = { CanCollide = true, CanQuery = true, CanTouch = false }
-- every part of a cactus: the boss's own script rips the cacti out and flies
-- them away, so nothing on one can be bumped into, stood on or hit by a raycast
local CACTUS = { CanCollide = false, CanQuery = false, CanTouch = false }

----------------------------------------------------------------------
-- Room on the floor: what's already standing where
----------------------------------------------------------------------
-- Each thing we put down marks its spot (a circle), so later things can keep
-- clear of it: cacti don't grow inside rocks, bones don't lie under cacti.
local taken = {} -- { middle, radius, is it one of the seven rocks? }
local function reserve(p, radius, rock)
	taken[#taken + 1] = { p, radius, rock }
end
-- is there room here for something reaching `need` studs out - and, near one
-- of the seven rocks, `rockGap` studs clear of it?
local function clearOf(p, need, rockGap)
	for _, t in ipairs(taken) do
		local dx, dz = p.X - t[1].X, p.Z - t[1].Z
		local gap = math.sqrt(dx * dx + dz * dz) - t[2]
		if gap < need or (t[3] and gap < (rockGap or 0)) then
			return false
		end
	end
	return true
end
-- the way in from the gate: the strip you walk down from the door to the floor
local function inGateLane(p)
	local off = p - CENTER
	return off.Z > 30 and math.abs(off.X) < 23
end

----------------------------------------------------------------------
-- The dunes (Terrain) - and a record of them, so things can be set on top
----------------------------------------------------------------------
local terrain = nil
local dunes = {} -- { centre, radius } for every sand ball, to work out heights

-- The way in from the gate stays clear: no sand may spill into this lane
-- (measured from the centre: the gate is due south, +Z).
local LANE_HALF, LANE_NEAR, LANE_FAR = 16, FIGHT_R - 12, GATE_R + 20

local function sandBall(pos, radius)
	local rel = pos - CENTER
	local nx = math.clamp(rel.X, -LANE_HALF, LANE_HALF)
	local nz = math.clamp(rel.Z, LANE_NEAR, LANE_FAR)
	local gap = math.sqrt((rel.X - nx) ^ 2 + (rel.Z - nz) ^ 2)
	if math.abs(pos.Y) < radius then
		local reach = math.sqrt(radius * radius - pos.Y * pos.Y) -- how far it spreads at the floor
		if reach > gap - 1 then
			-- shrink it until its foot stops short of the lane
			if gap - 1 <= 0 then
				return
			end
			radius = math.sqrt((gap - 1) ^ 2 + pos.Y * pos.Y)
		end
	end
	dunes[#dunes + 1] = { pos, radius }
	if terrain then
		pcall(function()
			terrain:FillBall(pos, radius - 2, Mat.Sand) -- (its surface shows 2 studs further out)
		end)
	end
end

-- the height of the sand at (x, z): the arena floor is 0, the dunes rise off it
local function sandHeight(x, z)
	local h = 0
	for _, d in ipairs(dunes) do
		local c, r = d[1], d[2]
		local dx, dz = x - c.X, z - c.Z
		local flat2 = dx * dx + dz * dz
		if flat2 < r * r then
			local top = c.Y + math.sqrt(r * r - flat2)
			if top > h then
				h = top
			end
		end
	end
	return h
end
local function onSand(p, sink) -- the same spot, sitting on the sand (sunk in a little)
	return V3(p.X, sandHeight(p.X, p.Z) - (sink or 0), p.Z)
end
-- the lowest and highest the sand gets under a patch w wide and d deep
-- (centred on p, turned to face the middle): so whatever stands there sits in
-- the slope, rather than floating over it or sinking out of sight
local function sandUnder(p, w, d)
	local f = facingCentre(V3(p.X, 0, p.Z))
	local lo, hi = math.huge, -math.huge
	for _, sx in ipairs({ -0.5, 0, 0.5 }) do
		for _, sz in ipairs({ -0.5, 0, 0.5 }) do
			local q = (f * CFrame.new(sx * w, 0, sz * d)).Position
			local h = sandHeight(q.X, q.Z)
			lo = math.min(lo, h)
			hi = math.max(hi, h)
		end
	end
	return lo, hi
end

local function buildDunes()
	-- a sand ball whose skirt reaches the floor exactly `toe` studs from the centre
	local function duneTouching(a, r, cy, toe)
		local radius = math.sqrt((r - toe) ^ 2 + cy * cy)
		sandBall(onRing(r, a, cy), radius)
	end
	-- the first rise: its foot lines the edge of the fighting floor, under the arches
	for i = 0, 59 do
		local a = (i + rnd() * 0.5) / 60 * math.pi * 2
		local w = wrap(a)
		if math.abs(w) > 0.2 then -- leave the way to the gate open
			local north = math.abs(wrap(a - math.pi)) < 0.32 -- lower in front of the temple
			local cy = north and -24 or (-18 - rnd() * 5)
			duneTouching(a, 190 + rnd() * 10, cy, 151 + rnd() * 3)
		end
	end
	-- the big dunes behind, climbing up the cliffs
	for i = 0, 43 do
		local a = (i + rnd() * 0.6) / 44 * math.pi * 2
		if math.abs(wrap(a)) > 0.36 then
			local north = math.abs(wrap(a - math.pi)) < 0.3
			sandBall(onRing(226 + rnd() * 12, a, north and -12 or (-4 + rnd() * 10)), 48 + rnd() * 12)
		end
	end
	-- crests, so the skyline of sand isn't one smooth ring
	for i = 0, 15 do
		local a = (i + rnd() * 0.8) / 16 * math.pi * 2
		if math.abs(wrap(a)) > 0.45 and math.abs(wrap(a - math.pi)) > 0.4 then
			sandBall(onRing(204 + rnd() * 10, a, 2 + rnd() * 6), 22 + rnd() * 10)
		end
	end
end

----------------------------------------------------------------------
-- The floor you fight on
----------------------------------------------------------------------
local function buildFloor()
	-- One great disc of sand, top at exactly y = 0 (where Tuber, the cacti, the
	-- rocks and everything else stand), reaching under the dunes and cliffs.
	-- It's a Part, not Terrain: Terrain rounds its surface to its own grid, and
	-- in the game a Terrain floor came out 2 studs too high - everything looked
	-- sunk in it. (The dunes are still Terrain: their feet dip under this.)
	cylinder("SandFloor", 12, 560, CFrame.new(at(0, -6, 0)), SAND, Mat.Sand)

	-- Ripples blown into the sand: rows of long low streaks lying across the wind,
	-- each row wandering a little, so the floor reads as sand rather than a plate.
	-- They reach right in toward the middle, but stop short of Tuber's garden.
	-- (Everything flat on the floor is thick and mostly buried, poking out a
	-- quarter of a stud: paper-thin parts flicker against the floor.)
	local across = V3(-WIND.Z, 0, WIND.X)
	for row = -12, 12 do
		for seg = -8, 8 do
			local t = seg * 17.5
			local wob = math.sin(t * 0.045 + row * 1.7) * 3
			local slope = math.cos(t * 0.045 + row * 1.7) * 3 * 0.045 -- the wobble's steepness
			local p = CENTER + WIND * (row * 11.5 + wob) + across * t
			local d = (p - CENTER).Magnitude
			local dir = (across + WIND * slope).Unit
			-- the nearest it comes to the middle (a streak is up to 18 long)
			local off = p - CENTER
			local nearest = (off + dir * math.clamp(-off:Dot(dir), -9, 9)).Magnitude
			if d < FIGHT_R - 5 and nearest > GARDEN_R and rnd() > 0.12 then
				local shade = SAND_DARK:Lerp(SAND, 0.25 + rnd() * 0.35)
				part("SandRipple", V3(0.9 + rnd() * 0.6, 0.7, 15 + rnd() * 3), CFrame.lookAt(p + V3(0, -0.1, 0), p + V3(0, -0.1, 0) + dir),
					shade, Mat.Sand, DECOR)
			end
		end
	end

	-- scattered pale patches, where the wind has scoured the surface (the
	-- biggest is 24 long, so none starts nearer the middle than the garden)
	for _ = 1, 18 do
		local a, r = rnd() * math.pi * 2, 26 + rnd() * 114
		local p = onRing(r, a, 0)
		ellipsoid("SandScour", V3(10 + rnd() * 14, 0.6, 4 + rnd() * 5), CFrame.lookAt(p, p + WIND) * CFrame.Angles(0, math.pi / 2, 0),
			SAND:Lerp(SAND_LIGHT, 0.6), Mat.Sand, DECOR)
	end
end

----------------------------------------------------------------------
-- The seven rocks on the floor (the only things in the fight's way)
----------------------------------------------------------------------
-- Chunky sandstone outcrops, 5 to 9 studs tall with flat tops you can stand
-- on. Each is a small Model tagged "DesertRock": its Radius is the circle its
-- footprint fits inside (the boss's rolling cactus balls bounce off that
-- circle and his needles stop at it), and every block of it is kept inside
-- that circle, so what you see is what they hit.
local function buildRocks()
	for i, spot in ipairs(ROCKS) do
		local a, dist, R = spot[1], spot[2], spot[3]
		local c = onRing(dist, a, 0)
		local H = between(5.4, 6.2) + (R - 5.5) * 0.9 -- the top: the bigger ones are taller
		local frame = CFrame.new(c) * CFrame.Angles(0, rnd() * math.pi / 2, 0)
		local rm = Instance.new("Model")
		rm.Name = "DesertRock" .. i
		-- one block: w by d across, its top `top` above the floor, standing at
		-- (x, z) from the rock's middle and turned by `turn`. If a corner would
		-- poke out of the rock's circle, the block shrinks in toward the middle.
		local function block(name, w, d, top, x, z, turn, color)
			local far = 0
			for _, sx in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local lx, lz = sx * w / 2, sz * d / 2
					local cx = x + lx * math.cos(turn) + lz * math.sin(turn)
					local cz = z - lx * math.sin(turn) + lz * math.cos(turn)
					far = math.max(far, math.sqrt(cx * cx + cz * cz))
				end
			end
			local k = math.min(1, (R - 0.2) / far)
			w, d, x, z = w * k, d * k, x * k, z * k
			-- (its foot sunk a stud into the sand, so it sits in it, not on it)
			return part(name, V3(w, top + 1, d), frame * CFrame.new(x, (top - 1) / 2, z) * CFrame.Angles(0, turn, 0), color, Mat.Sandstone, ROCK, rm)
		end
		-- the tall block in the middle, with the flat top...
		local core = block("RockCore", R * 1.0, R * 0.95, H, 0, 0, 0, STONE)
		-- ...standing on a wide, low one turned the other way (a step up)...
		block("RockBlock", R * 1.38, R * 1.32, H * between(0.34, 0.44), 0, 0, 0.42, STONE_DARK)
		-- ...and lumps huddled round it, each a different height
		block("RockBlock", R * 0.5, R * 0.95, H * between(0.64, 0.8), R * 0.66, R * between(-0.1, 0.1), between(-0.2, 0.2), STRATA[4])
		block("RockBlock", R * 0.9, R * 0.46, H * between(0.2, 0.3), R * between(-0.1, 0.1), -R * 0.66, between(-0.2, 0.2), STRATA[5])
		block("RockBlock", R * 0.46, R * 0.85, H * between(0.48, 0.6), -R * 0.66, R * between(-0.1, 0.1), between(-0.2, 0.2), STRATA[1])
		rm.PrimaryPart = core
		rm:SetAttribute("Floor", 2)
		rm:SetAttribute("Index", i)
		rm:SetAttribute("Radius", R)
		rm:SetAttribute("Height", H)
		CollectionService:AddTag(rm, "DesertRock")
		rm.Parent = m
		reserve(c, R, true)
	end
end

----------------------------------------------------------------------
-- The arena's old arches, poking out of the dunes all the way round
----------------------------------------------------------------------
local function buildArcade()
	local N = ARCH_SLOTS
	for i = 0, N - 1 do
		local a = (i + 0.5) / N * math.pi * 2
		local w = wrap(a)
		local skip = math.abs(w) < 0.3 or math.abs(wrap(a - math.pi)) < 0.36 -- the gate and the temple view
		if not skip and rnd() > 0.12 then
			local r = 157 + rnd() * 3
			local base = onRing(r, a, -6)
			local cf = facingCentre(base) * CFrame.Angles(math.rad((rnd() - 0.5) * 5), 0, math.rad((rnd() - 0.5) * 6))
			local span, pierH = 10, 20 + rnd() * 3
			local broken = rnd() < 0.3
			for _, sx in ipairs({ -1, 1 }) do
				local h = (broken and sx == 1) and pierH * (0.5 + rnd() * 0.25) or pierH
				part("ArcadePier", V3(4, h, 5), cf * CFrame.new(sx * (span / 2 + 2), h / 2, 0), STONE:Lerp(STONE_DARK, rnd() * 0.4), Mat.Sandstone, SCENERY)
				part("ArcadeImpost", V3(5, 1.2, 6), cf * CFrame.new(sx * (span / 2 + 2), h - 0.6, 0), STONE_DARK, Mat.Sandstone, SCENERY)
			end
			if not broken then
				-- a round arch made of voussoir blocks
				local r0 = span / 2 + 1
				for k = 0, 6 do
					local th = (k + 0.5) / 7 * math.pi
					local p = cf * CFrame.new(math.cos(th) * r0, pierH + math.sin(th) * r0, 0)
					part("ArcadeArch", V3(2.2, 2.6, 5), p * CFrame.Angles(0, 0, th - math.pi / 2), STONE, Mat.Sandstone, SCENERY)
				end
				part("ArcadeCornice", V3(span + 9, 2, 6), cf * CFrame.new(0, pierH + r0 + 1.6, 0), STONE_DARK, Mat.Sandstone, SCENERY)
			end
		end
	end
end

----------------------------------------------------------------------
-- The canyon: striped cliffs all the way round, and spires of rock
----------------------------------------------------------------------
-- The rock is laid down in bands that run level all the way round the canyon,
-- like real sandstone: every cliff shares the same band heights and colours,
-- and each band steps back a little from the one below, so the walls read as
-- one striped, terraced canyon instead of a heap of separate blocks.
local BANDS = { -- { height, colour }
	{ 30, RGB(184, 120, 76) },
	{ 14, RGB(214, 160, 104) },
	{ 11, RGB(234, 200, 146) },
	{ 18, RGB(202, 144, 92) },
	{ 9, RGB(170, 108, 70) },
	{ 17, RGB(226, 182, 122) },
	{ 13, RGB(196, 134, 86) },
	{ 20, RGB(232, 194, 138) },
	{ 12, RGB(206, 150, 98) },
	{ 10, RGB(180, 116, 74) },
}
local BAND_BOTTOM = -24

-- One stack of bands. `out` is the direction away from the arena: higher bands
-- step back that way. Returns the height of the top.
local function bandedStack(base, width, depth, bands, yaw, out, extra)
	local y = BAND_BOTTOM
	for j = 1, bands do
		local info = BANDS[(j - 1) % #BANDS + 1]
		local h = info[1]
		local back = out * ((j - 1) * 1.7 + (rnd() - 0.5) * 0.8)
		local cf = CFrame.new(base.X + back.X, y + h / 2, base.Z + back.Z) * CFrame.Angles(0, yaw, 0)
		local color = info[2]:Lerp(RGB(150, 96, 62), rnd() * 0.08)
		part("CliffStrata", V3(width, h + 0.05, depth), cf, color, Mat.Sandstone, extra)
		y = y + h
	end
	return y
end

local function buildCliffs()
	local N = 60
	local chord = 2 * CLIFF_R * math.sin(math.pi / N)
	for i = 0, N - 1 do
		local a = i / N * math.pi * 2
		local nearGate = math.abs(wrap(a)) < 0.42
		local r = nearGate and 214 or CLIFF_R
		local base = onRing(r, a, 0)
		-- the skyline rises and falls in long swells, with the odd notch
		local swell = 0.5 + 0.5 * math.sin(a * 3 + 1.1) * math.cos(a * 2 - 0.4)
		local bands = nearGate and (6 + math.floor(rnd() * 2)) or (7 + math.floor(swell * 3.2 + rnd() * 1.3))
		local out = (base - CENTER).Unit
		local topY = bandedStack(base, chord * 1.25, 34, bands, a, out, SCENERY)
		-- a weathered top: low flat slabs, not cubes
		for _ = 1, math.floor(rnd() * 2.5) do
			local p = onRing(r + bands * 1.7 + rnd() * 8, a + (rnd() - 0.5) * 0.05, topY + 1.5)
			part("CliffCap", V3(10 + rnd() * 14, 3 + rnd() * 3, 8 + rnd() * 8), CFrame.new(p)
				* CFrame.Angles(math.rad((rnd() - 0.5) * 6), a + (rnd() - 0.5) * 0.4, math.rad((rnd() - 0.5) * 6)),
				BANDS[(bands) % #BANDS + 1][2], Mat.Sandstone, SCENERY)
		end
	end
	-- hoodoos: tall weathered rock spires standing out in front of the walls
	for i = 0, 11 do
		local a = (i + 0.4 + rnd() * 0.3) / 12 * math.pi * 2
		if math.abs(wrap(a)) > 0.5 and math.abs(wrap(a - math.pi)) > 0.55 then
			local p = onRing(212 + rnd() * 10, a, 0)
			local foot = onSand(p, 4)
			local y = foot.Y
			local w = 9 + rnd() * 5
			local layers = 4 + math.floor(rnd() * 3)
			for j = 1, layers do
				local h = 6 + rnd() * 5
				local s = w * (1 - j / (layers + 2)) * (0.85 + rnd() * 0.3)
				part("Hoodoo", V3(s, h, s * 0.9), CFrame.new(foot.X + (rnd() - 0.5) * 1.5, y + h / 2, foot.Z + (rnd() - 0.5) * 1.5)
					* CFrame.Angles(0, rnd() * 3, 0), STRATA[1 + (j + i) % #STRATA], Mat.Sandstone, SCENERY)
				y = y + h
			end
			part("HoodooCap", V3(w * 0.9, 3, w * 0.8), CFrame.new(foot.X, y + 1.5, foot.Z) * CFrame.Angles(0.1, rnd() * 3, 0.08), STONE_DEEP, Mat.Sandstone, SCENERY)
		end
	end
end

----------------------------------------------------------------------
-- Sand pouring off the cliffs
----------------------------------------------------------------------
local function sandfall(a)
	local lipR = CLIFF_R - 8
	local lip = onRing(lipR, a, 0)
	local topY = 104
	local footY = sandHeight(lip.X, lip.Z)
	local footR = lipR
	local h = topY - footY
	local cf = facingCentre(V3(lip.X, footY + h / 2, lip.Z))
	-- the notch it pours through
	for _, sx in ipairs({ -1, 1 }) do
		part("SandfallCrag", V3(10, 18, 14), cf * CFrame.new(sx * 9, h / 2 + 4, 4) * CFrame.Angles(0, sx * 0.2, sx * 0.1), STRATA[2], Mat.Sandstone, SCENERY)
	end
	local sheet = part("Sandfall", V3(9, h, 1.2), cf, SAND_LIGHT, Mat.SmoothPlastic, merge(DECOR, { Transparency = 0.3 }))
	part("SandfallVeil", V3(13, h - 4, 0.6), cf * CFrame.new(0, -2, -1.2), SAND_LIGHT, Mat.SmoothPlastic, merge(DECOR, { Transparency = 0.72 }))
	-- grains streaming down the sheet
	local grains = Instance.new("ParticleEmitter")
	grains.Name = "Grains"
	grains.Color = ColorSequence.new(SAND_LIGHT, SAND)
	grains.LightInfluence = 1
	grains.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 2.6) })
	grains.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	grains.Lifetime = NumberRange.new(1.2, 2)
	grains.Speed = NumberRange.new(2, 6)
	grains.Acceleration = V3(0, -30, 0)
	grains.EmissionDirection = Enum.NormalId.Front
	grains.Rate = 18
	grains.Parent = sheet
	-- a plume of dust where it lands
	local plumeAt = anchorPart("SandfallPlume", CFrame.new(V3(lip.X, footY + 1, lip.Z) + (CENTER - lip).Unit * 3))
	plumeAt.Size = V3(12, 1, 8)
	local plume = Instance.new("ParticleEmitter")
	plume.Color = ColorSequence.new(SAND_LIGHT)
	plume.LightInfluence = 1
	plume.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 16) })
	plume.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	plume.Lifetime = NumberRange.new(2.5, 4)
	plume.Speed = NumberRange.new(3, 7)
	plume.SpreadAngle = Vector2.new(50, 50)
	plume.Acceleration = WIND * 3
	plume.EmissionDirection = Enum.NormalId.Top
	plume.Shape = Enum.ParticleEmitterShape.Box
	plume.Rate = 7
	plume.Parent = plumeAt
	-- a cone of sand building up under it
	sandBall(V3(lip.X, footY - 8, lip.Z) + (CENTER - lip).Unit * 4, 14)
	return footR
end

----------------------------------------------------------------------
-- The half-buried temple and its two seated colossi (across from the gate)
----------------------------------------------------------------------
local function colossus(pos, broken)
	local cf = facingCentre(pos) -- looks out over the bowl (-Z is forward)
	local S = STONE
	local D = STONE_DARK
	local function blk(name, size, x, y, z, color, rot)
		part(name, size, cf * CFrame.new(x, y, z) * (rot or CFrame.new()), color or S, Mat.Sandstone, SCENERY)
	end
	blk("ColossusThrone", V3(22, 30, 16), 0, 15, 8, D)
	blk("ColossusThroneTop", V3(24, 3, 17), 0, 31.5, 8, S)
	blk("ColossusPlinth", V3(26, 6, 30), 0, 3, 0, D)
	for _, sx in ipairs({ -1, 1 }) do
		blk("ColossusFoot", V3(6.5, 3, 9), sx * 5, 7.5, -11)
		blk("ColossusShin", V3(5.6, 18, 6), sx * 5, 17, -10)
		blk("ColossusThigh", V3(6, 6.4, 19), sx * 5, 28.5, -3)
		if not (broken and sx == 1) then
			blk("ColossusForearm", V3(4.6, 4.2, 14), sx * 5.2, 33.8, -4)
			blk("ColossusHand", V3(5.4, 3.6, 5.4), sx * 5.2, 33.2, -11.5)
		end
		blk("ColossusUpperArm", V3(4.8, 14, 5.2), sx * 11.2, 40, 3)
	end
	blk("ColossusTorso", V3(18, 20, 10), 0, 42, 4)
	blk("ColossusChest", V3(20, 5, 11), 0, 49.5, 4, D)
	blk("ColossusCollar", V3(15, 3, 9), 0, 53, 4, S)
	blk("ColossusNeck", V3(6, 4, 6), 0, 56, 4)
	-- the head, in a striped headdress
	blk("ColossusHead", V3(10, 12, 10), 0, 63, 3)
	blk("ColossusHeaddress", V3(13, 4, 11.5), 0, 70, 3.5, D)
	for _, sx in ipairs({ -1, 1 }) do
		blk("ColossusLappet", V3(3, 13, 7), sx * 6.5, 60, 4, D)
		blk("ColossusEye", V3(2.4, 0.8, 0.4), sx * 2.4, 64.5, -2.05, SHADOW)
	end
	blk("ColossusNose", V3(1.6, 3.2, 1.6), 0, 62, -2.3)
	blk("ColossusMouth", V3(3.6, 0.5, 0.4), 0, 59.2, -2.05, SHADOW)
	blk("ColossusBeard", V3(2.6, 5, 2.6), 0, 55.5, -1.5, D)
	if broken then
		-- the fallen forearm lies at its feet
		part("ColossusRubble", V3(4.6, 4.2, 14), cf * CFrame.new(12, 3, -18) * CFrame.Angles(0.3, 0.7, 1.4), S, Mat.Sandstone, SCENERY)
	end
	-- sand drifted up to its knees
	sandBall(pos + (CENTER - pos).Unit * 10 + V3(0, -10, 0), 22)
end

local function buildTemple()
	local tp = onRing(208, math.pi, 0)
	local tcf = facingCentre(tp) -- -Z faces the bowl
	local function blk(name, size, x, y, z, color, extra)
		return part(name, size, tcf * CFrame.new(x, y, z), color or STONE, Mat.Sandstone, extra or SCENERY)
	end
	-- the temple's back wall, set into the cliff, and its dark doorway
	blk("TempleWall", V3(70, 62, 8), 0, 25, 8, STONE_DARK)
	blk("TempleDoorFrame", V3(20, 34, 2), 0, 11, 3.4, STONE_DEEP)
	blk("TempleDoor", V3(14, 30, 1), 0, 9, 2.6, SHADOW)
	-- six columns (one broken), their feet lost in the sand
	for i = 0, 5 do
		local x = (i - 2.5) * 11
		if i == 4 then
			cylinder("TempleColumn", 26, 5.6, tcf * CFrame.new(x, 7, -4), STONE, Mat.Sandstone, SCENERY)
			part("TempleColumnDrum", V3(7, 5.6, 5.6), tcf * CFrame.new(x + 8, 20, -14) * CFrame.Angles(0.2, 0.9, 0.1), STONE, Mat.Sandstone,
				merge(SCENERY, { Shape = Enum.PartType.Cylinder }))
		else
			cylinder("TempleColumn", 52, 5.6, tcf * CFrame.new(x, 20, -4), STONE, Mat.Sandstone, SCENERY)
			blk("TempleCapital", V3(7.4, 2.6, 7.4), x, 47.3, -4, STONE_DARK)
			cylinder("TempleColumnBand", 1, 6.2, tcf * CFrame.new(x, 36, -4), STONE_DARK, Mat.Sandstone, SCENERY)
		end
	end
	-- architrave and frieze, cracked where the broken column let it sag
	blk("TempleArchitrave", V3(70, 5, 9), 0, 51, -4)
	blk("TempleFrieze", V3(70, 4, 8), 0, 55.5, -3.5, STONE_DARK)
	for i = 0, 8 do
		blk("TempleFriezeCarving", V3(3.2, 2.2, 0.4), (i - 4) * 7.5, 55.5, -7.6, STONE_DEEP)
	end
	-- the pediment: two wedges back to back
	for _, sx in ipairs({ -1, 1 }) do
		wedge("TemplePediment", V3(8, 14, 35), tcf * CFrame.new(sx * 17.5, 64.5, -3.5) * CFrame.Angles(0, -sx * math.pi / 2, 0), STONE, Mat.Sandstone, SCENERY)
	end
	blk("TempleCrest", V3(4, 3, 9), 0, 72, -3.5, STONE_DARK)
	-- the sand has climbed a good way up
	sandBall(tp + V3(0, -26, -16), 36)

	colossus(onRing(202, math.pi + 0.36, 0), false)
	colossus(onRing(202, math.pi - 0.36, 0), true)
end

----------------------------------------------------------------------
-- The gate: how you come in, and the way out
----------------------------------------------------------------------
local function brazier(pos, scale)
	scale = scale or 1
	cylinder("BrazierStand", 4 * scale, 1.2 * scale, CFrame.new(pos + V3(0, 2 * scale, 0)), STONE_DARK, Mat.Sandstone)
	cylinder("BrazierFoot", 0.8 * scale, 3 * scale, CFrame.new(pos + V3(0, 0.4 * scale, 0)), STONE_DEEP, Mat.Sandstone)
	local bowl = cylinder("BrazierBowl", 1.4 * scale, 3.6 * scale, CFrame.new(pos + V3(0, 4.6 * scale, 0)), RGB(96, 70, 48), Mat.Metal)
	local fire = Instance.new("Fire")
	fire.Size = 5 * scale
	fire.Heat = 9
	fire.Color = RGB(255, 140, 50)
	fire.SecondaryColor = RGB(255, 210, 110)
	fire.Parent = bowl
	local light = Instance.new("PointLight")
	light.Color = FIRE_LIGHT
	light.Range = 18 * scale
	light.Brightness = 1.4
	light.Parent = bowl
	return bowl
end

local function buildGate()
	local gp = onRing(GATE_R, 0, 0)
	local gcf = CFrame.lookAt(gp, at(0, 0, 0)) -- -Z faces the bowl
	local function blk(name, size, x, y, z, color, extra)
		return part(name, size, gcf * CFrame.new(x, y, z), color or STONE, Mat.Sandstone, extra)
	end
	-- two great tapering pylons
	for _, sx in ipairs({ -1, 1 }) do
		blk("GatePylon", V3(9, 13, 8), sx * 11, 6.5, 0, STONE_DARK)
		blk("GatePylon", V3(8, 12, 7.2), sx * 11, 19, 0)
		blk("GatePylon", V3(7, 10, 6.4), sx * 11, 30, 0, STONE_DARK)
		blk("GatePylonCap", V3(9, 2.4, 8), sx * 11, 36.2, 0)
		-- carved bands on the faces
		for _, y in ipairs({ 9, 22 }) do
			blk("GateBand", V3(8.4, 0.8, 0.3), sx * 11, y, -3.8, STONE_DEEP, DECOR)
		end
	end
	blk("GateLintel", V3(31, 5, 8), 0, 33.5, 0)
	blk("GateCornice", V3(34, 2, 9), 0, 37, 0, STONE_DARK)
	-- Tuber's sign over the door: a little cactus with a flower on its head,
	-- inside a golden ring
	local sign = gcf * CFrame.new(0, 33.5, -4.1)
	local facePit = CFrame.Angles(0, math.pi / 2, 0) -- (turns a disc to face the bowl)
	part("GateSign", V3(0.4, 6.4, 6.4), sign * facePit, RGB(250, 200, 110), Mat.Neon, merge(DECOR, { Shape = Enum.PartType.Cylinder }))
	part("GateSignField", V3(0.3, 5.2, 5.2), sign * CFrame.new(0, 0, -0.25) * facePit, STONE_DEEP, Mat.Sandstone,
		merge(DECOR, { Shape = Enum.PartType.Cylinder }))
	local function emblem(name, w, h, x, y, color, z)
		part(name, V3(w, h, 0.3), sign * CFrame.new(x, y, z or -0.5), color, Mat.SmoothPlastic, DECOR)
	end
	-- (laid edge to edge, like pixels)
	emblem("GateSignCactus", 0.9, 3.4, 0, -0.3, CACTUS_GREEN) -- the trunk
	emblem("GateSignCactus", 0.5, 0.55, -0.7, -0.55, CACTUS_GREEN) -- its arms: out, then up
	emblem("GateSignCactus", 0.55, 1.325, -1.225, -0.1625, CACTUS_GREEN)
	emblem("GateSignCactus", 0.5, 0.55, 0.7, -0.05, CACTUS_GREEN)
	emblem("GateSignCactus", 0.55, 1.325, 1.225, 0.3375, CACTUS_GREEN)
	emblem("GateSignFlower", 0.9, 0.5, 0, 1.65, FLOWER_PINK) -- the flower on its head
	emblem("GateSignFlower", 0.3, 0.3, 0, 1.65, FLOWER_YELLOW, -0.6)
	emblem("GateSignSand", 1.8, 0.35, 0, -2.175, SAND) -- the sand it grows in
	-- behind the fog: the dark passage back, and solid rock so nobody walks through
	blk("GatePassage", V3(14, 30, 1), 0, 15, 3.5, SHADOW)
	blk("GateBack", V3(34, 40, 10), 0, 20, 9, STONE_DARK)

	-- the golden fog in the doorway: the way out
	local fog = blk("FogWall", V3(13, 28, 0.6), 0, 14, 0, FOG_GOLD, { Transparency = 0.45, CanCollide = false, CastShadow = false })
	fog.Material = Mat.Neon
	pulse(fog, 0.4, 0.35, 0.6)
	local fe = Instance.new("ParticleEmitter")
	fe.Rate = 8
	fe.Color = ColorSequence.new(RGB(255, 236, 190))
	fe.LightEmission = 0.4
	fe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 6) })
	fe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	fe.Lifetime = NumberRange.new(2, 3)
	fe.Speed = NumberRange.new(0.5, 1.5)
	fe.Parent = fog
	local exit = Instance.new("ProximityPrompt")
	exit.ActionText = "Leave"
	exit.ObjectText = "Sand Gate"
	exit.HoldDuration = 0.4
	exit.MaxActivationDistance = 14
	exit.KeyboardKeyCode = Enum.KeyCode.E
	exit.GamepadKeyCode = Enum.KeyCode.ButtonX
	exit.RequiresLineOfSight = false
	exit.Parent = fog
	CollectionService:AddTag(exit, "ArenaExit")
	autoZone(gcf * CFrame.new(0, 4, -3), V3(16, 8, 6), "Spire", "Leave")

	-- the passage in: canyon walls either side, from the gate out to the floor
	local passageLen = GATE_R - FIGHT_R - 2 -- ends right at the edge of the floor
	for _, sx in ipairs({ -1, 1 }) do
		for j = 0, 2 do
			local z = -4 - j * (passageLen / 3) - passageLen / 6
			local base = (gcf * CFrame.new(sx * 32, 0, z)).Position
			bandedStack(base, 36, passageLen / 3 + 3, 6 - j + math.floor(rnd() * 2), math.atan2(gcf.LookVector.X, gcf.LookVector.Z), gcf.RightVector * sx, nil)
		end
		-- a banner on a pole at the passage mouth, torn by the wind
		local pole = (gcf * CFrame.new(sx * 13, 0, -passageLen + 6)).Position
		cylinder("BannerPole", 14, 0.5, CFrame.new(pole + V3(0, 7, 0)), RGB(96, 70, 48), Mat.Wood)
		part("BannerBar", V3(0.3, 0.3, 3.4), CFrame.new(pole + V3(0, 13.4, 0)) * (gcf - gcf.Position), RGB(96, 70, 48), Mat.Wood, DECOR)
		-- the cloth hangs off the bar along the wall, torn short at the bottom
		part("Banner", V3(0.15, 6, 2.8), CFrame.new(pole + V3(0, 10.2, 0)) * (gcf - gcf.Position) * CFrame.new(-sx * 0.2, 0, 0), CLOTH[1], Mat.Fabric, DECOR)
		part("BannerTatter", V3(0.15, 2.2, 1.1), CFrame.new(pole + V3(0, 6.1, 0)) * (gcf - gcf.Position) * CFrame.new(-sx * 0.2, 0, 0.7), CLOTH[1], Mat.Fabric, DECOR)
	end
	-- braziers flanking the door
	for _, sx in ipairs({ -1, 1 }) do
		brazier((gcf * CFrame.new(sx * 8, 0, -7)).Position, 1)
	end
	-- the old paved way from the gate, mostly under the sand now
	for k = 0, 9 do
		local p = (gcf * CFrame.new((rnd() - 0.5) * 3, 0.06, -6 - k * 4.5)).Position
		if rnd() > 0.2 then
			part("GatePaving", V3(8 + rnd() * 3, 0.3, 3.6), CFrame.new(p) * (gcf - gcf.Position) * CFrame.Angles(0, (rnd() - 0.5) * 0.12, 0),
				STONE_DARK:Lerp(STONE, rnd()), Mat.Sandstone, DECOR)
		end
	end

	-- where you arrive: just inside the gate, looking out over the bowl
	local spawnP = onRing(GATE_R - 14, 0, 3)
	local arrive = anchorPart("ArenaSpawn", CFrame.lookAt(spawnP, V3(CENTER.X, spawnP.Y, CENTER.Z)))
	CollectionService:AddTag(arrive, "ArenaSpawn")
end

----------------------------------------------------------------------
-- Things lying about: bones, broken urns, lost weapons, boulders
----------------------------------------------------------------------
local function bone(p, len, yaw)
	local dir = V3(math.cos(yaw), 0, math.sin(yaw))
	local a, b = p - dir * len / 2, p + dir * len / 2
	rod("Bone", a, b, 0.7, BONE, Mat.Limestone, DECOR)
	for _, e in ipairs({ a, b }) do
		ball("BoneKnob", 1.2, CFrame.new(e), BONE_DARK, Mat.Limestone, DECOR)
	end
end

local function skull(p, yaw)
	local cf = CFrame.new(p + V3(0, 0.6, 0)) * CFrame.Angles(0, yaw, math.rad((rnd() - 0.5) * 30))
	ellipsoid("SmallSkull", V3(1.9, 1.7, 2.3), cf, BONE, Mat.Limestone, DECOR)
	for _, sx in ipairs({ -1, 1 }) do
		ellipsoid("SmallSkullEye", V3(0.5, 0.5, 0.3), cf * CFrame.new(sx * 0.45, 0.15, -1.05), SHADOW, Mat.Slate, DECOR)
	end
end

local function urn(p, broken)
	local color = RGB(176, 104, 64):Lerp(RGB(150, 90, 60), rnd())
	if broken then
		-- lying on its side, a shard beside it
		part("UrnBody", V3(2.6, 2.2, 2.2), CFrame.new(p + V3(0, 0.9, 0)) * CFrame.Angles(0, rnd() * 3, math.rad(8)), color, Mat.Slate,
			merge(DECOR, { Shape = Enum.PartType.Cylinder }))
		part("UrnShard", V3(1.2, 0.2, 0.9), CFrame.new(p + V3(1.8, 0.1, 0.6)) * CFrame.Angles(0.2, rnd() * 3, 0.1), color, Mat.Slate, DECOR)
	else
		ellipsoid("UrnBody", V3(2.4, 2.8, 2.4), CFrame.new(p + V3(0, 1.2, 0)), color, Mat.Slate, DECOR)
		cylinder("UrnNeck", 0.9, 1.2, CFrame.new(p + V3(0, 2.8, 0)), color, Mat.Slate, DECOR)
		cylinder("UrnLip", 0.3, 1.7, CFrame.new(p + V3(0, 3.25, 0)), color, Mat.Slate, DECOR)
	end
end

local function lostSpear(p, withBanner)
	local lean = CFrame.Angles(math.rad((rnd() - 0.5) * 40), rnd() * math.pi * 2, math.rad((rnd() - 0.5) * 40))
	local cf = CFrame.new(p) * lean
	part("SpearShaft", V3(0.3, 9, 0.3), cf * CFrame.new(0, 3.5, 0), RGB(110, 80, 56), Mat.Wood, DECOR)
	part("SpearHead", V3(0.5, 1.4, 0.2), cf * CFrame.new(0, 8.6, 0), RGB(120, 110, 100), Mat.Metal, DECOR)
	if withBanner then
		part("SpearRag", V3(0.15, 3.4, 2.2), cf * CFrame.new(0, 6.6, 1.2), CLOTH[1 + math.floor(rnd() * #CLOTH)], Mat.Fabric, DECOR)
	end
end

local function lostShield(p)
	part("Shield", V3(0.4, 4, 4), CFrame.new(p + V3(0, 1.2, 0)) * CFrame.Angles(0, rnd() * 3, math.rad(60 + rnd() * 20)),
		RGB(120, 96, 70), Mat.Wood, merge(DECOR, { Shape = Enum.PartType.Cylinder }))
end

-- A dead tree: a crooked trunk splitting into branches, then twigs. Gives back
-- the tip of every twig - the very top of it, where a bird could perch - with
-- the way the twig points.
local function deadTree(p, s)
	local q = p
	local dir = V3((rnd() - 0.5) * 0.4, 1, (rnd() - 0.5) * 0.4).Unit
	local th = 1.6 * s
	local tips = {}
	local function branch(from, d, len, thick, depth)
		local to = from + d * len
		local b = beam("DeadBranch", from, to, thick, RGB(92, 76, 64), Mat.Wood, SCENERY)
		if depth > 0 then
			for _ = 1, 2 do
				local nd = (d + V3((rnd() - 0.5) * 1.3, 0.25, (rnd() - 0.5) * 1.3)).Unit
				branch(to, nd, len * 0.65, thick * 0.6, depth - 1)
			end
		else
			tips[#tips + 1] = { at = to + b.CFrame.UpVector * (thick / 2), dir = d }
		end
	end
	local trunkTop = q + dir * 7 * s
	beam("DeadTrunk", q - V3(0, 1, 0), trunkTop, th, RGB(84, 68, 56), Mat.Wood, SCENERY)
	branch(trunkTop, (dir + V3(0.6, 0.2, 0)).Unit, 5 * s, th * 0.6, 2)
	branch(trunkTop, (dir + V3(-0.5, 0.3, 0.4)).Unit, 4.5 * s, th * 0.55, 2)
	return tips
end

local function buildDebris()
	-- the fallen of earlier fights, round the edge of the floor (but never
	-- under a cactus or against a rock)
	for i = 0, 29 do
		local a = (i + rnd() * 0.8) / 30 * math.pi * 2
		local r = 118 + rnd() * 28
		local p = onRing(r, a, 0)
		if math.abs(wrap(a)) > 0.12 and clearOf(p, 5, 4) then
			local kind = i % 6
			if kind == 0 then
				bone(p, 3 + rnd() * 2, rnd() * math.pi)
				skull(p + V3(2, 0, 1), rnd() * 6)
			elseif kind == 1 then
				urn(p, rnd() > 0.5)
			elseif kind == 2 then
				lostSpear(p, rnd() > 0.4)
			elseif kind == 3 then
				lostShield(p)
				bone(p + V3(-2, 0, 1.5), 2.5, rnd() * math.pi)
			elseif kind == 4 then
				urn(p, false)
				urn(p + V3(2.6, 0, 1), true)
			else
				skull(p, rnd() * 6)
			end
			reserve(p, 2.5)
		end
	end
	-- sandstone boulders half sunk at the foot of the dunes (clear of the
	-- lizards' rocks and the meerkats' mounds)
	for i = 0, 25 do
		local a = (i + rnd() * 0.7) / 26 * math.pi * 2
		if math.abs(wrap(a)) > 0.25 then
			local s = 3 + rnd() * 6
			local p = onRing(146 + rnd() * 6, a, s * 0.15)
			if clearOf(p, s * 0.8) then
				part("DuneRock", V3(s * 1.4, s, s * 1.1), CFrame.new(p) * CFrame.Angles(rnd() * 0.5, rnd() * 3, rnd() * 0.5),
					STRATA[1 + math.floor(rnd() * #STRATA)], Mat.Sandstone)
			end
		end
	end
	-- braziers round the floor's edge: warm light as the sun goes
	for _, a in ipairs(EDGE_BRAZIERS) do
		brazier(onRing(144, a, 0), 1.25)
	end
end

----------------------------------------------------------------------
-- The watchers: dead trees, and where the desert's animals come to watch
----------------------------------------------------------------------
-- When Tuber turns into THE BRUTE, the desert comes to see: camels up on the
-- dunes, meerkats on little mounds, vultures in the dead trees and lizards on
-- the rocks at the floor's edge. The boss's own script brings the animals (on
-- each player's screen); all this builds is where they stand. Each spot is an
-- invisible "DuneLookout" part sitting exactly on the ground (or twig) the
-- animal stands on, facing the middle. They're all close enough in, and high
-- enough, to see from the fight: the camels stand above the tops of the old
-- arches, and nothing is far out where round 2's sandstorm would hide it.
local function buildLookouts()
	local count = 0
	local function lookout(kind, p)
		count = count + 1
		local spot = anchorPart(kind .. "Lookout", facingCentre(p))
		spot:SetAttribute("Floor", 2)
		spot:SetAttribute("Kind", kind)
		spot:SetAttribute("Index", count)
		CollectionService:AddTag(spot, "DuneLookout")
	end

	-- CAMELS: on flat sandstone ledges jutting out of the dunes, each above the
	-- arch tops, in a gap between two arches
	for _, k in ipairs(CAMEL_GAPS) do
		local c = onRing(184, archGap(k), 0)
		local lo, hi = sandUnder(c, 7, 10)
		local top = math.max(31, hi + 1) -- (clear of the sand, even where the dune lies a stud higher)
		local f = facingCentre(V3(c.X, 0, c.Z))
		part("CamelLedge", V3(7, 1.6, 10), f * CFrame.new(0, top - 0.8, 0), STONE, Mat.Sandstone, SCENERY)
		-- the banded rock under the ledge, down into the dune (a stripe or two)
		local depth = (top - 1.6) - (lo - 2)
		if depth > 0.5 then
			local n = math.clamp(math.ceil(depth / 7), 1, 2)
			local h = depth / n
			for j = 1, n do
				local y = top - 1.6 - (j - 0.5) * h
				part("CamelLedgeRock", V3(6.2 + j * 0.8, h + 0.05, 9.2 + j * 0.8), f * CFrame.new(0, y, 0.4 * j),
					BANDS[j + 1][2], Mat.Sandstone, SCENERY)
			end
		end
		lookout("Camel", V3(c.X, top, c.Z))
		reserve(c, 7)
	end

	-- MEERKATS: on knobbly little mounds of sandstone just outside the wall,
	-- each in a gap between two arches
	for _, k in ipairs(MEERKAT_GAPS) do
		local c = onRing(153, archGap(k), 0)
		local lo, hi = sandUnder(c, 5, 5)
		local top = math.max(2.6, hi + 1.4)
		local f = facingCentre(V3(c.X, 0, c.Z)) * CFrame.Angles(0, between(-0.3, 0.3), 0)
		local bottom = lo - 1.5
		part("MeerkatMound", V3(5, top - 1.1 - bottom, 4.6), f * CFrame.new(0, (top - 1.1 + bottom) / 2, 0), STRATA[4], Mat.Sandstone, SCENERY)
		local ox, oz = between(-0.4, 0.4), between(-0.4, 0.4)
		part("MeerkatMound", V3(3.4, 1.1, 3.2), f * CFrame.new(ox, top - 0.55, oz), STONE, Mat.Sandstone, SCENERY)
		lookout("Meerkat", (f * CFrame.new(ox, top, oz)).Position)
		reserve(c, 3.5)
	end

	-- VULTURES: dead trees clinging to the dunes, and a vulture on the best
	-- twig of three of them (high up, and not pointing straight at the sky)
	local trees = {}
	for i, a in ipairs(TREE_ANGLES) do
		local foot = onSand(onRing(172 + rnd() * 8, a + between(-0.03, 0.03), 0), 0.5)
		trees[i] = deadTree(foot, 1.25 + rnd() * 0.45)
		reserve(foot, 5)
	end
	for _, i in ipairs(VULTURE_TREES) do
		local best, bestScore = nil, -math.huge
		for _, tip in ipairs(trees[i]) do
			local score = tip.at.Y - math.max(0, tip.dir.Y - 0.55) * 12
			if score > bestScore then
				best, bestScore = tip, score
			end
		end
		lookout("Vulture", best.at)
	end

	-- LIZARDS: on low, flat rocks at the very edge of the floor, warm in the sun
	-- (right at the wall: no nearer the middle than 146)
	for _, a in ipairs(LIZARD_ANGLES) do
		local c = onRing(149, a, 0)
		local f = facingCentre(c) * CFrame.Angles(0, between(-0.4, 0.4), 0)
		local top = between(1.8, 2.4)
		part("DuneRock", V3(4.2, top + 1, 3.4), f * CFrame.new(0, (top - 1) / 2, 0), STRATA[1 + math.floor(rnd() * #STRATA)], Mat.Sandstone)
		part("DuneRock", V3(2.4, 1.6, 2.2), f * CFrame.new(1.9, 0.4, 1.0) * CFrame.Angles(0, 0.5, 0), STRATA[1 + math.floor(rnd() * #STRATA)], Mat.Sandstone)
		lookout("Lizard", (f * CFrame.new(-0.4, top, 0)).Position)
		reserve(c, 3.5)
	end
end

----------------------------------------------------------------------
-- The cacti (every one of them flies into THE BRUTE)
----------------------------------------------------------------------
-- Blocky 8-bit cacti in four kinds. Each is a small Model tagged "DuneCactus"
-- whose PrimaryPart, "CactusBase", is a dark block at the foot. When Tuber
-- turns into the Brute, the boss's own script rips them all out of the ground
-- and flies them into him, the nearest first. So:
--   * nothing on a cactus collides or takes raycasts (see CACTUS above)
--   * no single part is 14 studs tall or more: the retro restyler would dress
--     a part that tall like a pillar, and its dressing would be left floating
--     in the air when the cactus flies away. Tall saguaros are stacks of
--     shorter blocks instead.
local function cactusPart(cm, name, size, cf, color)
	return part(name, size, cf, color, Mat.SmoothPlastic, CACTUS, cm)
end
-- a tiny pale spine poking out of a block's side (a block w by d across, the
-- spine `y` up it, on one of its four sides)
local function spine(cm, frame, w, d, y)
	local side = math.floor(rnd() * 4)
	local along = between(-0.3, 0.3)
	local off = side < 2 and V3((side == 0 and 1 or -1) * w / 2, y, along * d) or V3(along * w, y, (side == 2 and 1 or -1) * d / 2)
	cactusPart(cm, "CactusSpine", V3(0.3, 0.3, 0.3), frame * CFrame.new(off), SPINE)
end

-- SAGUARO: the tall one, 11-18 studs, with one or two arms bent up at the elbow
local function saguaro(cm, frame, flower)
	local W = between(2.2, 2.8)
	local H = between(11, 17.5) -- (and a flower on top makes 18)
	local base = cactusPart(cm, "CactusBase", V3(W + 0.6, 0.8, W + 0.6), frame * CFrame.new(0, 0.1, 0), CACTUS_DEEP)
	-- the trunk: two blocks, one on the other (each under 10 studs)
	local split = H * between(0.46, 0.52)
	cactusPart(cm, "CactusTrunk", V3(W, split - 0.3, W), frame * CFrame.new(0, (split + 0.3) / 2, 0), CACTUS_GREEN)
	cactusPart(cm, "CactusTrunk", V3(W - 0.3, H - split + 0.05, W - 0.3), frame * CFrame.new(0, (split + H) / 2, 0), CACTUS_GREEN)
	-- the arms: out sideways, then straight up. A second arm grows on the
	-- other side, or round at a right angle (so from every side you see one)
	local arms = (H > 12 and rnd() < 0.8) and 2 or 1
	local turns = { 0, rnd() < 0.5 and math.pi or math.pi / 2 * (rnd() < 0.5 and 1 or -1) }
	for k = 1, arms do
		local aw = W * between(0.62, 0.72)
		local out = between(1.7, 2.5)
		local ya = H * (k == 1 and between(0.34, 0.46) or between(0.5, 0.6))
		local up = math.min(between(3.6, 6.4), H - 1.2 - ya - aw / 2)
		local edge = W / 2 + out -- (the arm's outside edge)
		local armFrame = frame * CFrame.Angles(0, turns[k], 0)
		cactusPart(cm, "CactusArm", V3(out + 0.3, aw, aw), armFrame * CFrame.new(edge - (out + 0.3) / 2, ya, 0), CACTUS_GREEN)
		cactusPart(cm, "CactusArm", V3(aw, aw + up, aw), armFrame * CFrame.new(edge - aw / 2, ya + up / 2, 0), CACTUS_GREEN)
	end
	if arms == 1 then
		local y = between(1.5, H - 1.5)
		local w = y < split and W or W - 0.3
		spine(cm, frame, w, w, y)
	end
	if flower then
		cactusPart(cm, "CactusFlower", V3(0.9, 0.5, 0.9), frame * CFrame.new(0, H + 0.2, 0), flower)
	end
	return base
end

-- BARREL: short and squat, 3-4 studs, with dark ribs down its sides
local function barrel(cm, frame, flower)
	local w = between(2.8, 3.4)
	local h = between(3.0, 3.5)
	local base = cactusPart(cm, "CactusBase", V3(w + 0.5, 0.7, w + 0.5), frame * CFrame.new(0, 0.05, 0), CACTUS_DEEP)
	cactusPart(cm, "CactusBody", V3(w, h - 0.8, w), frame * CFrame.new(0, 0.3 + (h - 0.8) / 2, 0), CACTUS_GREEN)
	cactusPart(cm, "CactusCrown", V3(w - 0.9, 0.55, w - 0.9), frame * CFrame.new(0, h - 0.275, 0), CACTUS_GREEN)
	-- (two thin slabs through the body, a little wider than it: stripes on all four sides)
	cactusPart(cm, "CactusRib", V3(0.35, h - 1.1, w + 0.1), frame * CFrame.new(0, 0.45 + (h - 1.1) / 2, 0), CACTUS_MID)
	cactusPart(cm, "CactusRib", V3(w + 0.1, h - 1.1, 0.35), frame * CFrame.new(0, 0.45 + (h - 1.1) / 2, 0), CACTUS_MID)
	spine(cm, frame, w, w, between(1, h - 1))
	if flower then
		cactusPart(cm, "CactusFlower", V3(1.1, 0.45, 1.1), frame * CFrame.new(0, h + 0.2, 0), flower)
	end
	return base
end

-- PEAR (prickly pear): flat paddle-shaped pads growing out of each other at
-- angles, 5-7 studs, maybe with flowers on their rims
local function pear(cm, frame, flower)
	local base = cactusPart(cm, "CactusBase", V3(2.2, 0.8, 1.5), frame * CFrame.new(0, 0.1, 0), CACTUS_DEEP)
	local pads = {}
	-- a pad standing on `foot` (the middle of its bottom edge)
	local function pad(foot, w, h)
		local cf = foot * CFrame.new(0, h / 2, 0)
		cactusPart(cm, "CactusPad", V3(w, h, 0.65), cf, CACTUS_GREEN)
		pads[#pads + 1] = { cf = cf, w = w, h = h }
		return cf
	end
	local first = pad(frame * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(between(-8, 8))), 2.8, 3.1)
	for _, sx in ipairs({ -1, 1 }) do
		local foot = first * CFrame.new(sx * 0.7, 3.1 / 2 - 0.4, 0)
		pad(foot * CFrame.Angles(0, math.rad(between(-40, 40)), math.rad(-sx * between(18, 34))), between(2.1, 2.5), between(2.3, 2.8))
	end
	if rnd() < 0.5 then
		local under = pads[2 + math.floor(rnd() * 2)]
		pad(under.cf * CFrame.new(0, under.h / 2 - 0.35, 0) * CFrame.Angles(0, math.rad(between(50, 90)), math.rad(between(-15, 15))), 1.8, 2.0)
	end
	cactusPart(cm, "CactusSpine", V3(0.3, 0.3, 0.3), first * CFrame.new(between(-0.8, 0.8), between(-0.6, 0.8), (rnd() < 0.5 and 1 or -1) * 0.33), SPINE)
	if flower then
		for n = 1, 1 + math.floor(rnd() * 2) do
			local p = pads[#pads - n + 1]
			cactusPart(cm, "CactusFlower", V3(0.6, 0.5, 0.6), p.cf * CFrame.new(between(-0.3, 0.3) * p.w, p.h / 2 + 0.2, 0), flower)
		end
	end
	return base
end

-- TUBERLING: a little lumpy potato of a cactus, 2-3 studs (one of Tuber's
-- family), sometimes two or three in a huddle (`n` of them)
local LUMPS = { { 0, 0, 1 }, { 1.6, 0.5, 0.72 }, { -1.1, 1.3, 0.66 } } -- { x, z, size }
local function tuberling(cm, frame, flower, n)
	local base = cactusPart(cm, "CactusBase", n == 1 and V3(2.5, 0.5, 2.3) or V3(4.4, 0.5, 4.0), frame * CFrame.new(0, -0.05, 0), CACTUS_DEEP)
	local main, mainSize = frame, 1 -- (the biggest lump: where its flower and spines go)
	for k = 1, n do
		local s = LUMPS[k][3] * between(0.9, 1.12)
		local lf = frame * CFrame.new(LUMPS[k][1], 0, LUMPS[k][2]) * CFrame.Angles(0, between(-0.6, 0.6), 0)
		local color = k == 1 and CACTUS_GREEN or CACTUS_GREEN:Lerp(CACTUS_MID, 0.35)
		-- a chubby block, and a smaller one on top a little off-centre to round
		-- it off (lumpy, like a potato)
		cactusPart(cm, "Tuberling", V3(2.0 * s, 1.5 * s, 1.8 * s), lf * CFrame.new(0, 0.1 + 0.75 * s, 0), color)
		cactusPart(cm, "Tuberling", V3(1.3 * s, 0.7 * s, 1.2 * s), lf * CFrame.new(between(-0.15, 0.15) * s, 0.1 + 1.8 * s, between(-0.1, 0.1) * s), color)
		if k == 1 then
			main, mainSize = lf, s
		end
	end
	for _ = 1, (n == 1) and 2 or 1 do
		spine(cm, main, 2.0 * mainSize, 1.8 * mainSize, between(0.5, 1.4) * mainSize)
	end
	if flower then
		cactusPart(cm, "CactusFlower", V3(0.6, 0.35, 0.6), main * CFrame.new(0, 0.25 + 2.15 * mainSize, 0), flower)
	end
	return base
end

local CACTUS_KINDS = { Saguaro = saguaro, Barrel = barrel, Pear = pear, Tuberling = tuberling }
local FLOWER_CHANCE = { Saguaro = 0.4, Barrel = 0.6, Pear = 0.5, Tuberling = 0.35 }
local HUDDLES = { 3, 1, 2, 1, 2 } -- how many tuberlings in each huddle, in turn
-- which kind goes in each spot, going round: 16 on the floor, 12 on the dunes
local RING_KINDS = { "Saguaro", "Pear", "Barrel", "Saguaro", "Tuberling", "Pear", "Saguaro", "Barrel",
	"Tuberling", "Saguaro", "Pear", "Saguaro", "Barrel", "Pear", "Tuberling", "Saguaro" }
local DUNE_KINDS = { "Saguaro", "Pear", "Saguaro", "Barrel", "Saguaro", "Tuberling",
	"Saguaro", "Pear", "Saguaro", "Barrel", "Saguaro", "Pear" }

local function buildCacti()
	local grown = {} -- { model, how far from the middle }
	local huddles = 0
	local function grow(kind, foot)
		local cm = Instance.new("Model")
		cm.Name = kind .. "Cactus"
		local frame = CFrame.new(foot) * CFrame.Angles(0, rnd() * math.pi * 2, 0)
		local flower = nil
		if rnd() < FLOWER_CHANCE[kind] then
			flower = rnd() < 0.5 and FLOWER_PINK or FLOWER_YELLOW
		end
		local huddle = nil -- (only tuberlings grow in huddles)
		if kind == "Tuberling" then
			huddles = huddles + 1
			huddle = HUDDLES[(huddles - 1) % #HUDDLES + 1]
		end
		cm.PrimaryPart = CACTUS_KINDS[kind](cm, frame, flower, huddle)
		cm:SetAttribute("Floor", 2)
		cm:SetAttribute("Kind", kind)
		local dx, dz = foot.X - CENTER.X, foot.Z - CENTER.Z
		grown[#grown + 1] = { cm, math.sqrt(dx * dx + dz * dz) }
		reserve(foot, 3)
	end

	-- on the floor you fight on: one in each of 16 slices going round, not too
	-- near the middle, well clear of the rocks, and out of the way in. (If its
	-- slice is too crowded, it looks a little further round, and further out.)
	for i, kind in ipairs(RING_KINDS) do
		for try = 1, 40 do
			local spread = try <= 20 and 0.45 or 1.2
			local a = (i - 0.5 + between(-spread, spread)) / #RING_KINDS * math.pi * 2
			local r
			if try > 20 then
				r = between(42, 138)
			elseif i % 2 == 0 then
				r = between(42, 92) -- (every other one nearer the middle)
			else
				r = between(86, 138)
			end
			local p = onRing(r, a, 0)
			if not inGateLane(p) and clearOf(p, 8, 13) then
				grow(kind, p)
				break
			end
		end
	end
	-- up the dune slopes behind the arches (not by the gate or the temple)
	for i, kind in ipairs(DUNE_KINDS) do
		local side = (i % 2 == 0) and 1 or -1
		local slot = math.ceil(i / 2) -- 1 to 6 up each side
		for _ = 1, 30 do
			local a = side * (0.45 + (slot - 0.5 + between(-0.45, 0.45)) / 6 * (math.pi - 1.0))
			local p = onRing(between(165, 192), a, 0)
			if clearOf(p, 7) then
				-- (its foot a little way into the sand: the real dune's surface can
				-- lie a stud off the sand balls we worked it out from)
				local lo = sandUnder(p, 3, 3)
				grow(kind, V3(p.X, lo - 0.9, p.Z))
				break
			end
		end
	end

	-- numbered from the middle outward: the near ones fly to the Brute first
	if #grown == 0 then
		return
	end
	table.sort(grown, function(x, y)
		return x[2] < y[2]
	end)
	local near, far = grown[1][2], grown[#grown][2]
	for i, g in ipairs(grown) do
		local cm = g[1]
		cm:SetAttribute("Index", i)
		cm:SetAttribute("Delay", math.floor((g[2] - near) / math.max(far - near, 1) * 1000 + 0.5) / 1000)
		CollectionService:AddTag(cm, "DuneCactus")
		cm.Parent = m
	end
end

----------------------------------------------------------------------
-- Tuber's garden: where he sleeps, in the very middle
----------------------------------------------------------------------
-- Just a little patch of dug-over sand, a ring of pebbles and a few tiny
-- flowers, all lying flat (lower than a stud), so nothing hides Tuber himself
-- sitting in the middle. (BossService builds him on BossHome, right here.)
local function buildGarden()
	cylinder("GardenPatch", 0.6, 8.4, CFrame.new(at(0, 0, 0)), TILLED, Mat.Sand, DECOR)
	-- furrows raked across it
	local rake = CFrame.new(at(0, 0.15, 0)) * CFrame.Angles(0, 0.4, 0)
	for _, x in ipairs({ -2.85, -0.95, 0.95, 2.85 }) do
		local len = 2 * math.sqrt(4.2 * 4.2 - x * x) - 1
		part("GardenFurrow", V3(0.5, 0.5, len), rake * CFrame.new(x, 0, 0), TILLED_DARK, Mat.Sand, DECOR)
	end
	-- a ring of little pebbles round it
	for k = 0, 9 do
		local a = (k + between(-0.2, 0.2)) / 10 * math.pi * 2
		local h = between(0.3, 0.45)
		local p = onRing(5.4 + between(-0.25, 0.25), a, h / 2 + 0.14)
		part("GardenPebble", V3(between(0.5, 0.8), h, between(0.5, 0.8)), CFrame.new(p) * CFrame.Angles(0, rnd() * math.pi, 0),
			PEBBLES[1 + math.floor(rnd() * #PEBBLES)], Mat.Slate, DECOR)
	end
	-- and a few tiny flowers just outside the pebbles
	for k = 0, 4 do
		local a = (k + 0.3 + between(-0.15, 0.15)) / 5 * math.pi * 2
		local p = onRing(6.9 + between(-0.4, 0.4), a, 0)
		part("GardenStem", V3(0.2, 0.5, 0.2), CFrame.new(p + V3(0, 0.25, 0)), CACTUS_MID, Mat.SmoothPlastic, DECOR)
		part("GardenFlower", V3(0.5, 0.25, 0.5), CFrame.new(p + V3(0, 0.6, 0)) * CFrame.Angles(0, rnd() * math.pi, 0),
			k % 2 == 0 and FLOWER_PINK or FLOWER_YELLOW, Mat.SmoothPlastic, DECOR)
	end
end

----------------------------------------------------------------------
-- A few desert touches: flowers, scrub, cow skulls, tumbleweeds
----------------------------------------------------------------------
-- All just decoration, and all out toward the edge, so the middle of the
-- fight stays clear.
local function scrub(p)
	local s = between(0.8, 1.3)
	local cf = CFrame.new(p) * CFrame.Angles(0, rnd() * math.pi, 0)
	part("Scrub", V3(2 * s, 0.8 * s, 1.7 * s), cf * CFrame.new(0, 0.3 * s, 0), SCRUB[1 + math.floor(rnd() * #SCRUB)], Mat.SmoothPlastic, DECOR)
	part("Scrub", V3(1.2 * s, 0.7 * s, 1.1 * s), cf * CFrame.new(0.3 * s, 0.85 * s, -0.1 * s) * CFrame.Angles(0, 0.7, 0),
		SCRUB[1 + math.floor(rnd() * #SCRUB)], Mat.SmoothPlastic, DECOR)
end

local function desertFlowers(p)
	local cf = CFrame.new(p) * CFrame.Angles(0, rnd() * math.pi, 0)
	local pinkFirst = rnd() < 0.5
	part("FlowerLeaves", V3(1.3, 0.35, 1.0), cf * CFrame.new(0, 0.15, 0), CACTUS_MID, Mat.SmoothPlastic, DECOR)
	part("DesertFlower", V3(0.5, 0.3, 0.5), cf * CFrame.new(-0.35, 0.45, 0.1), pinkFirst and FLOWER_PINK or FLOWER_YELLOW, Mat.SmoothPlastic, DECOR)
	part("DesertFlower", V3(0.45, 0.3, 0.45), cf * CFrame.new(0.4, 0.5, -0.2), pinkFirst and FLOWER_YELLOW or FLOWER_PINK, Mat.SmoothPlastic, DECOR)
end

-- a cow skull bleaching in the sun: a long face and two horns
local function cowSkull(p, yaw)
	local cf = CFrame.new(p) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(-6), 0, math.rad((rnd() - 0.5) * 14))
	part("CowSkull", V3(1.9, 1.0, 1.5), cf * CFrame.new(0, 0.45, 0.2), BONE, Mat.Limestone, DECOR)
	part("CowSkullSnout", V3(1.1, 0.75, 1.9), cf * CFrame.new(0, 0.35, -1.3), BONE, Mat.Limestone, DECOR)
	for _, sx in ipairs({ -1, 1 }) do
		part("CowSkullEye", V3(0.45, 0.35, 0.2), cf * CFrame.new(sx * 0.7, 0.62, -0.56), SHADOW, Mat.Slate, DECOR)
		beam("CowSkullHorn", (cf * CFrame.new(sx * 0.85, 0.75, 0.3)).Position, (cf * CFrame.new(sx * 2.4, 1.6, 0)).Position, 0.34,
			BONE_DARK, Mat.Limestone, DECOR)
	end
end

-- a tumbleweed: a tangle of dry twigs, each one cutting across a curve of
-- the ball's outside (so together they make a round, see-through clump)
local TUMBLE_CIRCLES = { V3(1, 0, 0), V3(0, 1, 0), V3(0, 0, 1), V3(1, 1, 0).Unit, V3(0, 1, 1).Unit, V3(1, 0, 1).Unit }
local function tumbleweed(p, size)
	local c = p + V3(0, size / 2 - 0.15, 0)
	local rad = size / 2
	local spin = CFrame.Angles(rnd() * math.pi, rnd() * math.pi, 0) -- (each one tumbled differently)
	for k, axis in ipairs(TUMBLE_CIRCLES) do
		-- a circle round the ball, and a twig across a third of it
		local n = spin * axis
		local u = n:Cross(math.abs(n.Y) < 0.9 and V3(0, 1, 0) or V3(1, 0, 0)).Unit
		local v = n:Cross(u)
		local t = rnd() * math.pi * 2
		local a = (u * math.cos(t) + v * math.sin(t)) * rad
		local b = (u * math.cos(t + 1.9) + v * math.sin(t + 1.9)) * rad
		beam("Tumbleweed", c + a, c + b, 0.18, TUMBLE[1 + k % 2], Mat.Wood, DECOR)
	end
end

local function buildTouches()
	-- somewhere free out toward the edge of the floor (nil if nowhere was found)
	local function freeSpot(rMin, rMax, need, aMin, aMax)
		for _ = 1, 20 do
			local p = onRing(between(rMin, rMax), between(aMin or 0, aMax or math.pi * 2), 0)
			if not inGateLane(p) and clearOf(p, need, need) then
				reserve(p, need)
				return p
			end
		end
		return nil
	end
	-- (a tumbleweed will be caught against the second rock, on its downwind side)
	local rock = ROCKS[2]
	local caught = onRing(rock[2], rock[1], 0) + WIND * (rock[3] + 1.4)
	reserve(caught, 1.5)
	-- little desert flowers and clumps of dry scrub
	for i = 1, 9 do
		local p = freeSpot(96, 144, 1.5)
		if p then
			if i % 3 == 0 then
				desertFlowers(p)
			else
				scrub(p)
			end
		end
	end
	-- cow skulls
	for _ = 1, 3 do
		local p = freeSpot(118, 144, 2.5)
		if p then
			cowSkull(p, rnd() * math.pi * 2)
		end
	end
	-- tumbleweeds: two blown up against the edge downwind, and the one caught
	-- against the rock
	for _ = 1, 2 do
		local p = freeSpot(141, 145, 2, 0.95, 1.5)
		if p then
			tumbleweed(p, between(2.6, 3.4))
		end
	end
	tumbleweed(caught, 2.8)
end

----------------------------------------------------------------------
-- Blowing sand (everyone sees these; the heavier storm near your camera is
-- drawn by ArenaAmbience on your own screen)
----------------------------------------------------------------------
local function buildWind()
	-- sand snaking across the floor
	local drift = anchorPart("GroundDrift", CFrame.lookAt(at(0, 0.6, 0), at(0, 0.6, 0) + WIND))
	drift.Size = V3(260, 1, 260)
	local d = Instance.new("ParticleEmitter")
	d.Name = "Drift"
	d.Color = ColorSequence.new(SAND_LIGHT, SAND)
	d.LightInfluence = 1
	d.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.8) })
	d.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.72), NumberSequenceKeypoint.new(1, 1) })
	d.Lifetime = NumberRange.new(2, 3.5)
	d.Speed = NumberRange.new(14, 22)
	d.SpreadAngle = Vector2.new(8, 2)
	d.EmissionDirection = Enum.NormalId.Front
	d.Shape = Enum.ParticleEmitterShape.Box
	d.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	d.Rate = 40
	d.Parent = drift
	-- sand streaming off the dune crests
	for i = 0, 9 do
		local a = (i + 0.5) / 10 * math.pi * 2
		if math.abs(wrap(a)) > 0.4 then
			local p = onSand(onRing(196, a, 0))
			local crest = anchorPart("CrestWisp", CFrame.lookAt(p + V3(0, 2, 0), p + V3(0, 2, 0) + WIND))
			crest.Size = V3(30, 2, 6)
			local w = Instance.new("ParticleEmitter")
			w.Color = ColorSequence.new(SAND_LIGHT)
			w.LightInfluence = 1
			w.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 7) })
			w.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) })
			w.Lifetime = NumberRange.new(2, 3)
			w.Speed = NumberRange.new(10, 16)
			w.SpreadAngle = Vector2.new(10, 10)
			w.EmissionDirection = Enum.NormalId.Front
			w.Shape = Enum.ParticleEmitterShape.Box
			w.Rate = 6
			w.Parent = crest
		end
	end
end

----------------------------------------------------------------------
-- The walls round the fight, and the marks the boss will use
----------------------------------------------------------------------
local function buildBounds()
	local N = 48
	for i = 0, N - 1 do
		local a = (i + 0.5) / N * math.pi * 2
		if math.abs(wrap(a)) > 0.1 then -- the gap is the way to the gate
			local p = onRing(FIGHT_R, a, 30)
			local wall = part("EdgeWall", V3(2 * FIGHT_R * math.sin(math.pi / N) + 0.5, 60, 2), CFrame.lookAt(p, p + V3(math.sin(a), 0, math.cos(a))),
				RGB(255, 255, 255), Mat.SmoothPlastic, { Transparency = 1, CanQuery = false, CastShadow = false })
			CollectionService:AddTag(wall, "DuneEdgeWall")
		end
	end
	-- Where Tuber sleeps: in his garden in the middle, facing the gate you come
	-- in by. BossService builds the boss itself on this spot.
	local home = anchorPart("BossHome", CFrame.new(at(0, 0, 0)))
	home:SetAttribute("Floor", 2)
	home:SetAttribute("Facing", V3(0, 0, 1))
	CollectionService:AddTag(home, "BossHome")
end

----------------------------------------------------------------------
-- Public
----------------------------------------------------------------------
function DunesBuilder.Build()
	local old = Workspace:FindFirstChild("DuneArena")
	if old then
		old:Destroy()
	end
	m = Instance.new("Model")
	m.Name = "DuneArena"
	dunes = {}
	taken = {}
	seed = 20260924 -- the dice start from the same place every time
	-- the braziers round the floor's edge will stand here (see buildDebris), so
	-- nothing else is put on their spots
	for _, a in ipairs(EDGE_BRAZIERS) do
		reserve(onRing(144, a, 0), 3)
	end

	-- Terrain for the dunes: clear the space first (a rebuild shouldn't stack
	-- sand on sand), and colour the sand to match the floor
	terrain = nil
	pcall(function()
		terrain = Workspace.Terrain
	end)
	if terrain then
		-- (in pieces: one giant clear can fail, and any sand already saved in
		-- the place would then stay - burying the whole arena)
		for x = -300, 300, 120 do
			for z = -300, 300, 120 do
				local ok = pcall(function()
					terrain:FillBlock(CFrame.new(at(x, 70, z)), V3(120, 220, 120), Mat.Air)
				end)
				if not ok then
					warn("[DunesBuilder] couldn't clear the old sand at " .. tostring(at(x, 0, z)))
				end
			end
		end
		pcall(function()
			terrain:SetMaterialColor(Mat.Sand, SAND)
		end)
	end

	-- each piece on its own, so one mistake can't leave the whole arena missing.
	-- Each has its own number, and rolls its own dice from that number: so
	-- changing one piece never reshuffles the others. (The order matters where
	-- a piece keeps clear of what's already there.)
	local pieces = {
		{ 0, "Dunes", buildDunes }, -- first: other pieces sit things on top of the sand
		-- (number 0 rolls the very dice the dunes always rolled, so they haven't moved)
		{ 1, "Floor", buildFloor },
		{ 2, "Old arches", buildArcade },
		{ 3, "Canyon cliffs", buildCliffs },
		{ 4, "Sandfalls", function()
			for _, a in ipairs({ 1.2, -1.42, 2.55, -2.3 }) do
				sandfall(a)
			end
		end },
		{ 5, "Temple and colossi", buildTemple }, -- (the last to heap up sand)
		{ 6, "Gate", buildGate },
		{ 7, "Rocks", buildRocks },
		{ 8, "Dead trees and lookouts", buildLookouts },
		{ 9, "Cacti", buildCacti }, -- keeps clear of the rocks and lookouts
		{ 10, "Tuber's garden", buildGarden },
		{ 11, "Things lying about", buildDebris }, -- keeps clear of all of those
		{ 12, "Desert touches", buildTouches },
		{ 13, "Blowing sand", buildWind },
		{ 14, "Walls and markers", buildBounds },
	}
	local failed = 0
	for _, piece in ipairs(pieces) do
		seed = 20260924 + piece[1] * 7919
		local ok, err = pcall(piece[3])
		if not ok then
			failed = failed + 1
			warn("[DunesBuilder] '" .. piece[2] .. "' failed to build: " .. tostring(err))
		end
	end

	m:SetAttribute("Floor", 2)
	m:SetAttribute("Center", CENTER)
	m:SetAttribute("FightRadius", FIGHT_R) -- how far out the invisible wall stands
	m:SetAttribute("Storm", 0.35) -- how hard the sand blows (0..1): a breeze until the fight
	m.Parent = Workspace
	if failed == 0 then
		print("[DunesBuilder] The Sunken Dunes built OK")
	end
	-- Everything here stands on y = 0. If Terrain sand ends up over the floor
	-- (old sand saved in the place that the clear couldn't reach), say so in
	-- the Output.
	if terrain then
		task.delay(1, function()
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { terrain }
			local highest = -math.huge
			for _, off in ipairs({ V3(0, 0, 0), V3(40, 0, 0), V3(-40, 0, 0), V3(0, 0, 40), V3(0, 0, -40) }) do
				local hit = Workspace:Raycast(at(off.X, 150, off.Z), V3(0, -200, 0), params)
				if hit then
					highest = math.max(highest, hit.Position.Y - CENTER.Y)
				end
			end
			if highest > 0.25 then
				warn(string.format("[DunesBuilder] there's Terrain sand %.1f studs above the floor: everything will look sunk in it."
					.. " Is there old Terrain saved in the place round %s?", highest, tostring(CENTER)))
			end
		end)
	end
	return m
end

return DunesBuilder
