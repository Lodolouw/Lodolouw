--[[
	DunesBuilder  (ModuleScript, parent: ServerScriptService, name: "DunesBuilder")

	Builds the Spire's second floor: THE SUNKEN DUNES, Mireworm's arena.

	An old colosseum the desert swallowed whole. You come in through a sandstone
	gate cut into the canyon wall and step out onto a wide, flat bowl of sand -
	the arena floor, buried long ago - ringed by the tops of its old arches poking
	out of the dunes. Beyond them the dunes climb to towering striped canyon
	cliffs, with sand pouring off their lips. Across from the gate a half-buried
	temple and two seated colossi watch the pit. On the floor: five cracked stone
	platforms (the only ground the worm can't come up through), toppled pillars
	to hide behind, the ribcage and skull of something the worm killed long ago,
	and in the very middle, a sunken stone seal with the sand swirling round it -
	the spot that caves in when the fight turns.

	Everything the fight will need is marked for BossService/BossClient:
	  * "ArenaSpawn"   where you arrive (in this model, Floor = 2)
	  * "ArenaExit"    the Leave prompt on the gate's golden fog
	  * "BossHome"     the centre of the pit, Floor = 2
	  * "DunePlatform" each stone platform (a Model; Radius attribute). In the
	    fight BossService can crack them and shatter them (Cracks / Broken)
	  * "DuneThumper"  the three bronze thumpers round the edge (a Model with a
	    "Strike" prompt): strike one and the worm charges at the sound
	  * "DuneSinkhole" the centre that collapses in phase 2 (Radius attribute)
	  * "DuneEdgeWall" the invisible walls round the sand you fight on
	  * the model itself carries Floor, Center, SandRadius (how far out the worm
	    can burrow) and Storm (how hard the sand blows: 0..1, read by the
	    ArenaAmbience script on each player's screen)

	Main calls DunesBuilder.Build() once at startup, right after the lobby.
	The dunes and the floor you fight on are smooth Terrain sand (so the worm
	can tear craters in the floor); everything else is ordinary Parts.
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
local SINK_R = 34 -- the stone seal in the middle that caves in
local GATE_R = 180 -- the gate, cut into the south cliff
local CLIFF_R = 238 -- the canyon wall
local WIND = V3(1, 0, 0.35).Unit -- which way the sand blows

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

----------------------------------------------------------------------
-- Helpers (the same kinds of little builders as the lobby's)
----------------------------------------------------------------------
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

-- A block stretched along the line from a to b (for bones, branches, ribs)
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
-- angle 0 is south (+Z, the gate); pi is north (the temple)
local function onRing(r, a, y)
	return CENTER + V3(math.sin(a) * r, y, math.cos(a) * r)
end
local function facingCentre(p)
	return CFrame.lookAt(p, V3(CENTER.X, p.Y, CENTER.Z))
end
local function wrap(a) -- to -pi..pi
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- small decoration: no collisions, no raycasts, no shadow
local DECOR = { CanCollide = false, CanQuery = false, CastShadow = false }
-- big scenery nobody can reach: no collisions or raycasts, but it does shade
local SCENERY = { CanCollide = false, CanQuery = false }

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
			terrain:FillBall(pos, radius, Mat.Sand)
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
	-- One great disc of sand, top at y = 0, reaching under the dunes and cliffs.
	-- It's Terrain, like the dunes, so the two meet without a seam - and so
	-- Mireworm can really tear it up in the fight: BossClient opens craters,
	-- trenches and the phase-two pit in it on each player's screen (and fills
	-- them back in). 16 studs thick, lined up with Terrain's 4-stud grid so the
	-- top is perfectly flat. (If Terrain isn't available, a plain Part instead.)
	local made = false
	if terrain then
		made = pcall(function()
			terrain:FillCylinder(CFrame.new(at(0, -8, 0)), 16, 280, Mat.Sand)
		end)
	end
	if not made then
		cylinder("SandFloor", 12, 560, CFrame.new(at(0, -6, 0)), SAND, Mat.Sand)
	end

	-- Ripples blown into the sand: rows of long low streaks lying across the wind,
	-- each row wandering a little, so the floor reads as sand rather than a plate.
	local across = V3(-WIND.Z, 0, WIND.X)
	for row = -12, 12 do
		for seg = -8, 8 do
			local t = seg * 17.5
			local wob = math.sin(t * 0.045 + row * 1.7) * 3
			local slope = math.cos(t * 0.045 + row * 1.7) * 3 * 0.045 -- the wobble's steepness
			local p = CENTER + WIND * (row * 11.5 + wob) + across * t
			local d = (p - CENTER).Magnitude
			if d < FIGHT_R - 5 and d > SINK_R + 8 and rnd() > 0.12 then
				local dir = (across + WIND * slope).Unit
				local shade = SAND_DARK:Lerp(SAND, 0.25 + rnd() * 0.35)
				part("SandRipple", V3(0.9 + rnd() * 0.6, 0.12, 15 + rnd() * 3), CFrame.lookAt(p + V3(0, 0.03, 0), p + V3(0, 0.03, 0) + dir),
					shade, Mat.Sand, DECOR)
			end
		end
	end

	-- scattered pale patches, where the wind has scoured the surface
	for _ = 1, 18 do
		local a, r = rnd() * math.pi * 2, 45 + rnd() * 95
		local p = onRing(r, a, 0.04)
		ellipsoid("SandScour", V3(10 + rnd() * 14, 0.1, 4 + rnd() * 5), CFrame.lookAt(p, p + WIND) * CFrame.Angles(0, math.pi / 2, 0),
			SAND:Lerp(SAND_LIGHT, 0.6), Mat.Sand, DECOR)
	end
end

----------------------------------------------------------------------
-- The seal at the centre (what caves in when the fight turns)
----------------------------------------------------------------------
local function buildSinkhole()
	-- the buried arena's old central dais, its paving just breaking the sand
	for ring, info in ipairs({ { SINK_R, 26, 7.5 }, { SINK_R * 0.62, 16, 5.5 } }) do
		local r, n, len = info[1], info[2], info[3]
		for i = 0, n - 1 do
			if rnd() > 0.28 then -- some are gone, or under the sand
				local a = (i + 0.5) / n * math.pi * 2
				local p = onRing(r + (rnd() - 0.5) * 1.5, a, 0.1)
				part("SealTile", V3(len, 0.4, 2.6), facingCentre(p) * CFrame.Angles(math.rad((rnd() - 0.5) * 8), 0, math.rad((rnd() - 0.5) * 6)),
					ring == 1 and STONE_DARK or STONE, Mat.Sandstone, DECOR)
			end
		end
	end
	-- the seal itself: a worn round stone carved with a coiled worm
	cylinder("SealStone", 0.35, 14, CFrame.new(at(0, 0.12, 0)), STONE_DARK, Mat.Sandstone, DECOR)
	cylinder("SealRing", 0.4, 9, CFrame.new(at(0, 0.16, 0)), STONE_DEEP, Mat.Sandstone, DECOR)
	for i = 0, 17 do
		local t = i / 17
		local a = t * math.pi * 3.2
		local r = 0.8 + t * 3.4
		cylinder("SealCoil", 0.2, 1.1 - t * 0.4, CFrame.new(onRing(r, a, 0.36)), SHADOW, Mat.Sandstone, DECOR)
	end
	-- the sand already circles it: three arms of darker sand spiralling in
	for arm = 0, 2 do
		for j = 0, 9 do
			local t0, t1 = j / 10, (j + 1) / 10
			local function pt(t)
				local r = SINK_R + 6 - t * (SINK_R - 4)
				local a = arm / 3 * math.pi * 2 + t * 2.4
				return onRing(r, a, 0.06)
			end
			local a, b = pt(t0), pt(t1)
			part("SandSwirl", V3(1.4 - t0 * 0.6, 0.1, (b - a).Magnitude + 0.6), CFrame.lookAt((a + b) / 2, b),
				SAND_DARK:Lerp(STONE_DEEP, 0.2), Mat.Sand, DECOR)
		end
	end

	local sink = anchorPart("Sinkhole", CFrame.new(at(0, 0, 0)))
	sink:SetAttribute("Floor", 2)
	sink:SetAttribute("Radius", SINK_R)
	CollectionService:AddTag(sink, "DuneSinkhole")
end

----------------------------------------------------------------------
-- The five stone platforms (the worm can't come up through stone)
----------------------------------------------------------------------
local function buildPlatforms()
	local spots = {
		{ a = 0.62, r = 76, size = 20 },
		{ a = 1.84, r = 70, size = 18 },
		{ a = 3.45, r = 78, size = 22 },
		{ a = 4.55, r = 72, size = 18 },
		{ a = 5.62, r = 80, size = 20 },
	}
	for i, s in ipairs(spots) do
		local pm = Instance.new("Model")
		pm.Name = "DunePlatform" .. i
		local base = onRing(s.r, s.a, 0)
		local cf = CFrame.new(base) * CFrame.Angles(0, s.a + (rnd() - 0.5) * 0.5, 0)
		local w, d = s.size, s.size * 0.8
		-- a low step all the way round, then the slab: you walk up, no jump needed
		part("PlatformStep", V3(w + 4, 0.8, d + 4), cf * CFrame.new(0, 0.4, 0), STONE_DARK, Mat.Sandstone, nil, pm)
		part("PlatformSlab", V3(w, 1.7, d), cf * CFrame.new(0, 0.85, 0), STONE, Mat.Sandstone, nil, pm)
		-- worn edges: a darker lip along two sides
		part("PlatformLip", V3(w, 0.3, 1.2), cf * CFrame.new(0, 1.72, -d / 2 + 0.6), STONE_DARK, Mat.Sandstone, DECOR, pm)
		part("PlatformLip", V3(1.2, 0.3, d), cf * CFrame.new(w / 2 - 0.6, 1.72, 0), STONE_DARK, Mat.Sandstone, DECOR, pm)
		-- cracks across the top
		for _ = 1, 3 do
			local p = cf * CFrame.new((rnd() - 0.5) * w * 0.7, 1.72, (rnd() - 0.5) * d * 0.7)
			part("PlatformCrack", V3(0.3, 0.06, 3 + rnd() * 5), p * CFrame.Angles(0, rnd() * math.pi, 0), SHADOW, Mat.Sandstone, DECOR, pm)
		end
		-- a faded carving in the middle
		cylinder("PlatformGlyph", 0.08, w * 0.45, cf * CFrame.new(0, 1.72, 0), STONE_DARK:Lerp(STONE, 0.4), Mat.Sandstone, DECOR, pm)
		cylinder("PlatformGlyph", 0.1, w * 0.3, cf * CFrame.new(0, 1.73, 0), STONE, Mat.Sandstone, DECOR, pm)
		-- a broken column stump on one corner: a bit of cover
		local cx, cz = (rnd() > 0.5 and 1 or -1) * (w / 2 - 2.4), (rnd() > 0.5 and 1 or -1) * (d / 2 - 2.4)
		local ch = 4 + rnd() * 4
		cylinder("PlatformColumn", ch, 3.2, cf * CFrame.new(cx, 1.7 + ch / 2, cz), STONE, Mat.Sandstone, nil, pm)
		cylinder("PlatformColumnBase", 0.8, 4, cf * CFrame.new(cx, 2.1, cz), STONE_DARK, Mat.Sandstone, nil, pm)
		-- sand drifted up one side
		wedge("PlatformDrift", V3(w * 0.7, 1.7, 6), cf * CFrame.new(0, 0.85, d / 2 + 3) * CFrame.Angles(0, math.pi, 0),
			SAND, Mat.Sand, nil, pm)
		pm:SetAttribute("Floor", 2)
		pm:SetAttribute("Radius", s.size / 2 + 2)
		pm:SetAttribute("Top", 1.7)
		CollectionService:AddTag(pm, "DunePlatform")
		pm.Parent = m
	end
end

----------------------------------------------------------------------
-- The thumpers: bronze gongs the old arena's keepers used to call the worm.
-- Each stands straight out behind a platform, so the worm charging at one
-- from the middle of the arena runs into the stone on the way.
----------------------------------------------------------------------
local THUMPER_ANGLES = { 0.62, 3.45, 5.62 } -- the same angles as platforms 1, 3 and 5
local THUMPER_R = 112
local BRONZE = RGB(176, 120, 58)
local BRONZE_DARK = RGB(120, 78, 38)

local function buildThumpers()
	for i, a in ipairs(THUMPER_ANGLES) do
		local tm = Instance.new("Model")
		tm.Name = "DuneThumper" .. i
		local p = onRing(THUMPER_R, a, 0)
		local cf = facingCentre(p) -- -Z looks at the middle of the arena
		local base = cylinder("ThumperBase", 1.2, 9, cf * CFrame.new(0, 0.6, 0), STONE_DARK, Mat.Sandstone, nil, tm)
		-- two posts and a lintel: the frame the gong hangs in
		for _, sx in ipairs({ -1, 1 }) do
			part("ThumperPost", V3(1.6, 10, 1.6), cf * CFrame.new(sx * 4.8, 6, 0), STONE, Mat.Sandstone, nil, tm)
			part("ThumperPostCap", V3(2.2, 0.8, 2.2), cf * CFrame.new(sx * 4.8, 11.2, 0), STONE_DARK, Mat.Sandstone, DECOR, tm)
		end
		part("ThumperLintel", V3(12.4, 1.2, 1.8), cf * CFrame.new(0, 10.6, 0), STONE_DARK, Mat.Sandstone, nil, tm)
		-- the gong, facing the pit, on two chains
		local drumAt = cf * CFrame.new(0, 5.6, 0)
		local drum = rod("ThumperDrum", (drumAt * CFrame.new(0, 0, 0.45)).Position, (drumAt * CFrame.new(0, 0, -0.45)).Position, 7.6,
			BRONZE, Mat.Metal, nil, tm)
		rod("ThumperRim", (drumAt * CFrame.new(0, 0, 0.3)).Position, (drumAt * CFrame.new(0, 0, -0.3)).Position, 8.2, BRONZE_DARK, Mat.Metal, DECOR, tm)
		-- the coiled worm on its face glows: what the client flashes when it's struck
		local glow = rod("ThumperGlow", (drumAt * CFrame.new(0, 0, -0.4)).Position, (drumAt * CFrame.new(0, 0, -0.56)).Position, 2.6,
			RGB(255, 196, 96), Mat.Neon, DECOR, tm)
		local light = Instance.new("PointLight")
		light.Color = RGB(255, 190, 110)
		light.Range = 12
		light.Brightness = 0.8
		light.Parent = glow
		for _, sx in ipairs({ -1, 1 }) do
			beam("ThumperChain", (cf * CFrame.new(sx * 2.2, 10, 0)).Position, (cf * CFrame.new(sx * 2.2, 9.1, 0)).Position, 0.3, SHADOW, Mat.Metal, DECOR, tm)
		end
		-- the beater, leaning on a post
		beam("ThumperBeater", (cf * CFrame.new(6.4, 0.4, -1.6)).Position, (cf * CFrame.new(5.4, 6.4, -1.2)).Position, 0.5, RGB(96, 70, 48), Mat.Wood, DECOR, tm)
		ball("ThumperBeaterHead", 1.5, cf * CFrame.new(5.35, 6.7, -1.2), RGB(150, 110, 70), Mat.Fabric, DECOR, tm)
		-- sand drifted against the base
		wedge("ThumperDrift", V3(8, 1, 3), cf * CFrame.new(0, 0.5, 5.8) * CFrame.Angles(0, math.pi, 0), SAND, Mat.Sand, DECOR, tm)

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Strike"
		prompt.ObjectText = "Thumper"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.RequiresLineOfSight = false
		prompt.Parent = drum

		tm.PrimaryPart = base
		tm:SetAttribute("Floor", 2)
		CollectionService:AddTag(tm, "DuneThumper")
		tm.Parent = m
	end
end

----------------------------------------------------------------------
-- Toppled pillars on the floor (cover from the sand spit)
----------------------------------------------------------------------
local function buildPillars()
	local spots = { { 0.95, 112 }, { 2.95, 118 }, { 4.0, 108 }, { 5.15, 116 }, { 1.45, 128 }, { 3.9, 132 } }
	for i, s in ipairs(spots) do
		local base = onRing(s[2], s[1], 0)
		local standing = i <= 4
		if standing then
			-- a column still standing, leaning, half buried
			local h = 18 + rnd() * 12
			local lean = CFrame.Angles(math.rad((rnd() - 0.5) * 22), rnd() * math.pi * 2, math.rad((rnd() - 0.5) * 22))
			local cf = CFrame.new(base) * lean
			cylinder("SandPillar", h, 6, cf * CFrame.new(0, h / 2 - 3, 0), STONE, Mat.Sandstone)
			cylinder("SandPillarBand", 1.2, 6.8, cf * CFrame.new(0, h * 0.55, 0), STONE_DARK, Mat.Sandstone)
			-- the break at the top
			for _ = 1, 3 do
				part("SandPillarBreak", V3(2.4, 1.6 + rnd() * 2.4, 2), cf * CFrame.new((rnd() - 0.5) * 3, h - 3 + 0.6, (rnd() - 0.5) * 3)
					* CFrame.Angles(rnd() * 0.4, rnd() * 3, rnd() * 0.4), STONE, Mat.Sandstone)
			end
		end
		-- a fallen drum or two lying beside it
		for j = 1, standing and 1 or 2 do
			local fa = rnd() * math.pi * 2
			local fp = base + V3(math.cos(fa) * (5 + j * 6), 2.2, math.sin(fa) * (5 + j * 6))
			part("FallenDrum", V3(6 + rnd() * 4, 5.6, 5.6), CFrame.new(fp) * CFrame.Angles(0, fa, math.rad((rnd() - 0.5) * 10)),
				STONE:Lerp(STONE_DARK, rnd() * 0.5), Mat.Sandstone, { Shape = Enum.PartType.Cylinder })
		end
		-- sand heaped round its foot
		ellipsoid("SandHeap", V3(14, 3, 12), CFrame.new(base + V3(0, -0.4, 0)) * CFrame.Angles(0, rnd() * 3, 0), SAND, Mat.Sand, DECOR)
	end
end

----------------------------------------------------------------------
-- The ribcage and skull of something the worm killed long ago
----------------------------------------------------------------------
local function buildCarcass()
	local A, R = 2.25, 100
	local mid = onRing(R, A, 0)
	local along = V3(math.cos(A), 0, -math.sin(A)) -- round the ring: the spine's direction
	local out = V3(math.sin(A), 0, math.cos(A)) -- away from the centre
	local SPINE = 58

	-- the backbone, just breaking the sand
	for i = 0, 11 do
		local t = i / 11 - 0.5
		local p = mid + along * (t * SPINE) + V3(0, 0.6 - math.abs(t) * 0.8, 0)
		local s = 3.6 - math.abs(t) * 1.6
		part("Vertebra", V3(s, s * 0.8, s * 1.1), CFrame.lookAt(p, p + along) * CFrame.Angles(rnd() * 0.2, 0, rnd() * 0.2), BONE_DARK, Mat.Limestone, DECOR)
		part("VertebraSpine", V3(0.9, s * 0.9, 1.4), CFrame.lookAt(p, p + along) * CFrame.new(0, s * 0.7, 0) * CFrame.Angles(math.rad(-20), 0, 0), BONE, Mat.Limestone, DECOR)
	end

	-- the ribs: great curved tusks rising out of the sand on both sides and
	-- arching in over the spine, the biggest in the middle
	for i = 0, 8 do
		local t = i / 8 - 0.5
		local root = mid + along * (t * (SPINE - 12))
		local big = 1 - math.abs(t) * 1.2
		local w, h = 12 + 8 * big, 14 + 12 * big
		for _, side in ipairs({ -1, 1 }) do
			if not (i == 7 and side == 1) then -- one snapped off
				local sideDir = out * side
				local prev = nil
				local N = 7
				for k = 0, N do
					local phi = -math.pi / 2 + (k / N) * (math.pi / 2 + math.pi * 0.36)
					local p = root + sideDir * (w * math.cos(phi)) + V3(0, h * (math.sin(phi) + 1) / 2 - 1.5, 0) + along * (math.sin(phi) * 1.2)
					if prev then
						local thick = 2.2 - (k / N) * 1.3
						beam("Rib", prev, p, thick, BONE:Lerp(BONE_DARK, k / N * 0.6), Mat.Limestone)
					end
					prev = p
				end
			end
		end
	end

	-- the skull, nose down in the sand at the head end, jaws open
	local headAt = mid + along * (SPINE / 2 + 12) + V3(0, 3, 0)
	local hcf = CFrame.lookAt(headAt, headAt + along + V3(0, -0.35, 0))
	ellipsoid("Skull", V3(15, 11, 22), hcf, BONE, Mat.Limestone)
	ellipsoid("SkullBrow", V3(16, 5, 9), hcf * CFrame.new(0, 3.5, 2), BONE_DARK, Mat.Limestone)
	for _, sx in ipairs({ -1, 1 }) do
		ellipsoid("EyeSocket", V3(3.4, 3, 3), hcf * CFrame.new(sx * 5, 1.5, -4.5), SHADOW, Mat.Slate, DECOR)
		-- horns sweeping back
		local hp = hcf * CFrame.new(sx * 5.5, 4.5, 4)
		local prev = hp.Position
		for k = 1, 5 do
			local p = (hcf * CFrame.new(sx * (5.5 + k * 1.6), 4.5 + k * 2.2 - k * k * 0.25, 4 + k * 3.2)).Position
			beam("SkullHorn", prev, p, 2.2 - k * 0.35, BONE_DARK:Lerp(STONE_DEEP, k / 6), Mat.Limestone)
			prev = p
		end
	end
	-- the lower jaw lying open, and a row of fangs
	part("SkullJaw", V3(11, 2.4, 16), hcf * CFrame.new(0, -6, -3) * CFrame.Angles(math.rad(16), 0, 0), BONE_DARK, Mat.Limestone)
	for k = 0, 5 do
		local x = (k - 2.5) * 1.9
		part("SkullFang", V3(0.9, 3.4, 0.9), hcf * CFrame.new(x, -4.2, -9.5 + math.abs(x) * 0.4) * CFrame.Angles(math.rad(12), 0, 0), BONE, Mat.Limestone, DECOR)
	end
	-- sand piled round the skull
	ellipsoid("SandHeap", V3(24, 4, 22), CFrame.new(onSand(headAt, 1.2)), SAND, Mat.Sand, DECOR)
end

----------------------------------------------------------------------
-- The arena's old arches, poking out of the dunes all the way round
----------------------------------------------------------------------
local function buildArcade()
	local N = 30
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
	local cf = facingCentre(pos) -- looks out over the pit (-Z is forward)
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
	local tcf = facingCentre(tp) -- -Z faces the pit
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
	local gcf = CFrame.lookAt(gp, at(0, 0, 0)) -- -Z faces the pit
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
	-- the worm's sign over the door: a coiled ring
	local sign = gcf * CFrame.new(0, 33.5, -4.1)
	part("GateSigil", V3(0.5, 6.4, 6.4), sign * CFrame.Angles(0, math.pi / 2, 0), STONE_DEEP, Mat.Sandstone, merge(DECOR, { Shape = Enum.PartType.Cylinder }))
	for k = 0, 13 do
		local t = k / 13
		local a = t * math.pi * 3
		local r = 0.6 + t * 2.4
		part("GateSigilCoil", V3(0.3, 0.8, 0.8), sign * CFrame.new(math.cos(a) * r, math.sin(a) * r, -0.3) * CFrame.Angles(0, math.pi / 2, 0),
			RGB(250, 200, 110), Mat.Neon, merge(DECOR, { Shape = Enum.PartType.Cylinder }))
	end
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

	-- where you arrive: just inside the gate, looking out over the pit
	local spawnP = onRing(GATE_R - 14, 0, 3)
	local arrive = anchorPart("ArenaSpawn", CFrame.lookAt(spawnP, V3(CENTER.X, spawnP.Y, CENTER.Z)))
	CollectionService:AddTag(arrive, "ArenaSpawn")
end

----------------------------------------------------------------------
-- Things lying about: bones, broken urns, lost weapons, dead trees, rocks
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

local function deadTree(p, s)
	local q = p
	local dir = V3((rnd() - 0.5) * 0.4, 1, (rnd() - 0.5) * 0.4).Unit
	local th = 1.6 * s
	local function branch(from, d, len, thick, depth)
		local to = from + d * len
		beam("DeadBranch", from, to, thick, RGB(92, 76, 64), Mat.Wood, SCENERY)
		if depth > 0 then
			for _ = 1, 2 do
				local nd = (d + V3((rnd() - 0.5) * 1.3, 0.25, (rnd() - 0.5) * 1.3)).Unit
				branch(to, nd, len * 0.65, thick * 0.6, depth - 1)
			end
		end
	end
	local trunkTop = q + dir * 7 * s
	beam("DeadTrunk", q - V3(0, 1, 0), trunkTop, th, RGB(84, 68, 56), Mat.Wood, SCENERY)
	branch(trunkTop, (dir + V3(0.6, 0.2, 0)).Unit, 5 * s, th * 0.6, 2)
	branch(trunkTop, (dir + V3(-0.5, 0.3, 0.4)).Unit, 4.5 * s, th * 0.55, 2)
end

local function buildDebris()
	-- the fallen of earlier fights, round the edge of the floor
	for i = 0, 29 do
		local a = (i + rnd() * 0.8) / 30 * math.pi * 2
		local r = 118 + rnd() * 28
		local p = onRing(r, a, 0)
		if math.abs(wrap(a)) > 0.12 then
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
		end
	end
	-- sandstone boulders half sunk at the foot of the dunes
	for i = 0, 25 do
		local a = (i + rnd() * 0.7) / 26 * math.pi * 2
		if math.abs(wrap(a)) > 0.25 then
			local s = 3 + rnd() * 6
			local p = onRing(146 + rnd() * 6, a, s * 0.15)
			part("DuneRock", V3(s * 1.4, s, s * 1.1), CFrame.new(p) * CFrame.Angles(rnd() * 0.5, rnd() * 3, rnd() * 0.5),
				STRATA[1 + math.floor(rnd() * #STRATA)], Mat.Sandstone)
		end
	end
	-- a few dead trees clinging to the dunes
	for i = 0, 6 do
		local a = (i + 0.3 + rnd() * 0.4) / 7 * math.pi * 2
		if math.abs(wrap(a)) > 0.45 and math.abs(wrap(a - math.pi)) > 0.6 then
			deadTree(onSand(onRing(170 + rnd() * 14, a, 0), 0.5), 1.1 + rnd() * 0.6)
		end
	end
	-- braziers round the floor's edge: warm light as the sun goes
	for _, a in ipairs({ 0.55, -0.55, 1.55, -1.7, 2.62, -2.55 }) do
		brazier(onRing(144, a, 0), 1.25)
	end
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
	-- Where Mireworm lies buried: under the seal, facing the gate you come in by.
	-- BossService builds the boss itself on this spot.
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

	-- Terrain for the dunes: clear the space first (a rebuild shouldn't stack
	-- sand on sand), and colour the sand to match the floor
	terrain = nil
	pcall(function()
		terrain = Workspace.Terrain
	end)
	if terrain then
		pcall(function()
			terrain:FillBlock(CFrame.new(at(0, 70, 0)), V3(720, 220, 720), Mat.Air)
			terrain:SetMaterialColor(Mat.Sand, SAND)
		end)
	end

	-- each piece on its own, so one mistake can't leave the whole arena missing
	local pieces = {
		{ "Dunes", buildDunes }, -- first: other pieces sit things on top of the sand
		{ "Floor", buildFloor },
		{ "Seal at the centre", buildSinkhole },
		{ "Platforms", buildPlatforms },
		{ "Thumpers", buildThumpers },
		{ "Pillars", buildPillars },
		{ "Ribcage and skull", buildCarcass },
		{ "Old arches", buildArcade },
		{ "Canyon cliffs", buildCliffs },
		{ "Sandfalls", function()
			for _, a in ipairs({ 1.2, -1.42, 2.55, -2.3 }) do
				sandfall(a)
			end
		end },
		{ "Temple and colossi", buildTemple },
		{ "Gate", buildGate },
		{ "Things lying about", buildDebris },
		{ "Blowing sand", buildWind },
		{ "Walls and markers", buildBounds },
	}
	local failed = 0
	for _, piece in ipairs(pieces) do
		local ok, err = pcall(piece[2])
		if not ok then
			failed = failed + 1
			warn("[DunesBuilder] '" .. piece[1] .. "' failed to build: " .. tostring(err))
		end
	end

	m:SetAttribute("Floor", 2)
	m:SetAttribute("Center", CENTER)
	m:SetAttribute("SandRadius", FIGHT_R - 4) -- how far out the worm can burrow
	m:SetAttribute("Storm", 0.35) -- how hard the sand blows (0..1): a breeze until the fight
	m.Parent = Workspace
	if failed == 0 then
		print("[DunesBuilder] The Sunken Dunes built OK")
	end
	return m
end

return DunesBuilder
