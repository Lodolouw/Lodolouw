--[[
	DojoBuilder  (ModuleScript, parent: ServerScriptService, name: "DojoBuilder")

	Builds the Spire's fourth floor: THE ROOFTOP DOJO, Kaze's arena.

	A wooden dojo floor on the very top of a mountain, high above a sea of
	clouds, at sunset. You come up a stone stairway through a red gate onto
	a big square floor of planks with a red border and a swirling wind
	emblem in the middle, where Kaze sits meditating on his mat. Four stone
	lantern PILLARS stand on the floor round him - in the fight they're
	cover from his giant beam (and his fireballs), and the beam breaks them.
	Behind him is the dojo hall ("KAZE DOJO" over the door) with a gong and
	training posts; round the edges, paper lanterns on ropes, cherry trees
	shedding petals, and nothing but a long drop into the clouds. Far off,
	other peaks poke out of the clouds and a huge orange sun sinks.
	Everything is chunky and 8-bit, in the game's 32 colours.

	Everything the fight needs is marked for SpireService / BossService:
	  * "ArenaSpawn"   where you arrive (in this model, Floor = 4)
	  * "ArenaExit"    the Leave prompt on the gate's fog (switched off on your
	                   screen), plus a walk-up box (AutoOpenZone, Spire = "Leave")
	  * "BossHome"     the middle of the floor, Floor = 4, facing the gate
	  * "DojoEdgeWall" the invisible walls round the floor you fight on
	  * "DojoPillar"   the four pillars (models): Floor = 4, Radius = how thick
	                   they are for the beam's shadow, Broken = true once the
	                   beam has smashed one (Bosses/Kaze.lua breaks and mends
	                   them). Each part says what it is: Whole parts are the
	                   pillar standing, Rubble parts the heap it leaves.
	  * the model itself carries Floor = 4, Center (the middle of the floor)
	    and Half (how far out from the middle the walls stand)

	Main calls DojoBuilder.Build() once at startup, after the Glimmer Dig and
	before BossService (which puts Kaze on his BossHome).
	The floor you fight on is one solid, flat slab: the planks, the border and
	the emblem drawn on it are paper-thin and can't be tripped on.
]]

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local DojoBuilder = {}

local V3 = Vector3.new
local RGB = Color3.fromRGB
local Mat = Enum.Material

----------------------------------------------------------------------
-- Layout (+Z is south: the gate; Kaze sits in the middle facing it)
----------------------------------------------------------------------
local CENTER = V3(2600, 0, 0) -- well away from the lobby and the other floors
local DECK = 64 -- the wooden floor goes this far out from the middle (a square)
local FIGHT = 62 -- the invisible walls stand this far out (the fight's edge)
local PILLAR_AT = 27 -- the four pillars stand at (+-this, +-this)
local PILLAR_R = 3.5 -- how thick a pillar is (for the beam's shadow)
local GAP = 8 -- half the width of the way in from the gate
local LANDING_Z = 88 -- the stone landing runs from the floor's edge out to here
local GATE_Z = 82 -- the red gate
local SPAWN_Z = 72 -- where you arrive
local ROCK = -2 -- the top of the mountain round the floor (the floor is a step up from it)

----------------------------------------------------------------------
-- Palette (the game's 32 colours)
----------------------------------------------------------------------
local WOOD = RGB(194, 133, 105)
local WOOD_LIGHT = RGB(228, 166, 114)
local WOOD_DARK = RGB(184, 111, 80)
local WOOD_DEEP = RGB(115, 62, 57)
local BARK = RGB(62, 39, 49)
local STONE = RGB(139, 155, 180)
local STONE_DARK = RGB(90, 105, 136)
local STONE_DEEP = RGB(58, 68, 102)
local RED = RGB(228, 59, 68)
local RED_DARK = RGB(162, 38, 51)
local INK = RGB(24, 20, 37)
local WHITE = RGB(255, 255, 255)
local PAPER = RGB(234, 212, 170)
local GOLD = RGB(254, 174, 52)
local GOLD_LIGHT = RGB(254, 231, 97)
local ORANGE = RGB(247, 118, 34)
local PINK = RGB(246, 117, 122)
local PINK_DEEP = RGB(181, 80, 136)
local GRASS = RGB(99, 199, 77)
local GRASS_DARK = RGB(62, 137, 72)
local TATAMI = RGB(234, 212, 170)
local TATAMI_EDGE = RGB(38, 92, 66)
local ROOF = RGB(58, 68, 102)
local ROOF_DARK = RGB(38, 43, 68)
local SNOW = RGB(192, 203, 220)
local MOUNTAIN = RGB(90, 105, 136)
local MOUNTAIN_DEEP = RGB(104, 56, 108)
local FOG = RGB(255, 240, 235)
local LANTERN_GLOW = RGB(254, 231, 97)

----------------------------------------------------------------------
-- Helpers (the same kinds of little builders as the dig's)
----------------------------------------------------------------------
local seed = 20260927
local function rnd()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
local function pick(list)
	return list[math.floor(rnd() * #list) + 1]
end

local m -- the arena model, set by Build()

-- small decoration: no collisions, no raycasts, no shadow
local DECOR = { CanCollide = false, CanQuery = false, CastShadow = false }
-- big scenery nobody can reach: no collisions or raycasts, but it does shade
local SCENERY = { CanCollide = false, CanQuery = false }

local function part(name, size, cf, color, extra, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Mat.SmoothPlastic
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

-- Upright cylinder: `cf` is the centre, the axis points up
local function cylinder(name, height, d, cf, color, extra, parent)
	return part(name, V3(height, d, d), cf * CFrame.Angles(0, 0, math.pi / 2), color, merge(extra, { Shape = Enum.PartType.Cylinder }), parent)
end

-- A WedgePart. Roblox wedges are full height at their back (+Z) and slope down
-- to nothing at their front (-Z).
local function wedge(name, size, cf, color, extra, parent)
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Material = Mat.SmoothPlastic
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
	return part(name, V3(1, 1, 1), cf, WHITE, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	}, parent)
end

-- a slow glow in and out (LobbyFX animates anything tagged "Pulse")
local function pulse(p, speed, lo, hi)
	p:SetAttribute("PulseSpeed", speed)
	p:SetAttribute("PulseMin", lo)
	p:SetAttribute("PulseMax", hi)
	p:SetAttribute("Phase", rnd() * 360)
	CollectionService:AddTag(p, "Pulse")
end

-- walking into this box opens the "Leave?" check (SpireClient watches these)
local function autoZone(cf, size, attr, value)
	local z = part("AutoOpenZone", size, cf, WHITE, {
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
-- angle 0 is south (+Z, the gate); pi is north
local function onRing(r, a, y)
	return CENTER + V3(math.sin(a) * r, y, math.cos(a) * r)
end
local function facingCentre(p)
	return CFrame.lookAt(p, V3(CENTER.X, p.Y, CENTER.Z))
end

-- a warm light (the lanterns)
local function light(p, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = p
	return l
end

-- words on a board (a SurfaceGui on its front face)
local function signText(board, text, color, face)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignText"
	gui.Face = face or Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(board.Size.X * 50, board.Size.Y * 50)
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.Font = Enum.Font.Arcade
	pcall(function()
		label.FontFace = Font.new("rbxasset://fonts/families/PressStart2P.json")
	end)
	label.Parent = gui
	gui.Parent = board
	return gui
end

-- A pixel picture LYING ON THE FLOOR: each cell of `grid` (a function
-- (col, row) -> colour or nil) is one square, `pixel` studs wide. Runs of the
-- same colour along a row are joined into one block, so it's only a handful
-- of parts. `centre` is its middle, on the floor.
local function floorArt(name, n, grid, pixel, centre, thick)
	for row = 1, n do
		local col = 1
		while col <= n do
			local c = grid(col, row)
			if c then
				local col2 = col
				while col2 < n and grid(col2 + 1, row) == c do
					col2 = col2 + 1
				end
				local cx = ((col + col2) / 2 - (n + 1) / 2) * pixel
				local cz = (row - (n + 1) / 2) * pixel
				local t = thick or 0.12
				part(name, V3((col2 - col + 1) * pixel, t, pixel), CFrame.new(centre + V3(cx, t / 2, cz)), c, DECOR)
				col = col2 + 1
			else
				col = col + 1
			end
		end
	end
end

----------------------------------------------------------------------
-- The floor you fight on
----------------------------------------------------------------------
local function buildDeck()
	-- one solid slab, its top at y = 0
	part("DojoFloor", V3(DECK * 2, 4, DECK * 2), CFrame.new(at(0, -2, 0)), WOOD_LIGHT)
	-- planks: every other one a shade darker, running north-south (thin, on
	-- top; the dark ones sit a hair higher than the joints so nothing flickers)
	local W = 4
	local n = DECK * 2 / W
	for i = 0, n - 1 do
		local x = -DECK + (i + 0.5) * W
		if i % 2 == 1 then
			part("Plank", V3(W, 0.06, DECK * 2), CFrame.new(at(x, 0.03, 0)), WOOD, DECOR)
		end
		-- the ends of the boards: short dark lines across each plank, staggered
		local z = -DECK + ((i * 37) % 29) + 3
		while z < DECK - 2 do
			part("PlankJoint", V3(W - 0.3, 0.1, 0.3), CFrame.new(at(x, 0.05, z)), WOOD_DARK, DECOR)
			z = z + 26 + ((i * 13) % 7)
		end
	end
	-- the red border round the fight
	local B = FIGHT - 3
	for _, s in ipairs({ -1, 1 }) do
		part("Border", V3(B * 2 + 2.4, 0.14, 2.4), CFrame.new(at(0, 0.07, s * B)), RED, DECOR)
		part("Border", V3(2.4, 0.14, B * 2 + 2.4), CFrame.new(at(s * B, 0.07, 0)), RED, DECOR)
		part("BorderInner", V3(B * 2 - 3.6, 0.12, 0.6), CFrame.new(at(0, 0.06, s * (B - 2.4))), RED_DARK, DECOR)
		part("BorderInner", V3(0.6, 0.12, B * 2 - 3.6), CFrame.new(at(s * (B - 2.4), 0.06, 0)), RED_DARK, DECOR)
	end
	-- the deck's edge: a darker beam all round, and the ends of the joists
	for _, s in ipairs({ -1, 1 }) do
		part("DeckEdge", V3(DECK * 2 + 1, 1.2, 1), CFrame.new(at(0, -0.6, s * (DECK + 0.5))), WOOD_DEEP)
		part("DeckEdge", V3(1, 1.2, DECK * 2 + 1), CFrame.new(at(s * (DECK + 0.5), -0.6, 0)), WOOD_DEEP)
	end

	-- THE WIND EMBLEM in the middle: a ring with a spiral inside it, in reds
	local N = 33
	local mid = (N + 1) / 2
	local function grid(col, row)
		local x, y = col - mid, row - mid
		local r = math.sqrt(x * x + y * y)
		if r >= 14.2 and r <= 16.2 then
			return RED_DARK
		end
		if r <= 12.8 and r >= 1.2 then
			-- the spiral: two turns out from the middle
			local a = math.atan2(y, x)
			for turnN = 0, 2 do
				local want = (a + math.pi + turnN * 2 * math.pi) / (4 * math.pi) * 12.5
				if math.abs(r - want) <= 1.05 then
					return RED
				end
			end
		end
		return nil
	end
	floorArt("Emblem", N, grid, 1, at(0, 0, 0), 0.1)

	-- where Kaze meditates: a tatami mat
	part("Tatami", V3(9, 0.3, 6), CFrame.new(at(0, 0.15, 0)), TATAMI)
	for _, s in ipairs({ -1, 1 }) do
		part("TatamiEdge", V3(9.1, 0.34, 0.5), CFrame.new(at(0, 0.17, s * 2.8)), TATAMI_EDGE, DECOR)
	end
	part("TatamiWeave", V3(0.2, 0.32, 5.4), CFrame.new(at(-1.5, 0.16, 0)), WOOD_LIGHT, DECOR)
	part("TatamiWeave", V3(0.2, 0.32, 5.4), CFrame.new(at(1.5, 0.16, 0)), WOOD_LIGHT, DECOR)

	-- a few scuffs and knots in the boards (not near the pillars)
	for _ = 1, 26 do
		local x, z = (rnd() * 2 - 1) * (FIGHT - 6), (rnd() * 2 - 1) * (FIGHT - 6)
		local nearPillar = math.abs(math.abs(x) - PILLAR_AT) < 6 and math.abs(math.abs(z) - PILLAR_AT) < 6
		if not nearPillar and math.sqrt(x * x + z * z) > 18 then
			local s = 0.6 + rnd() * 0.8
			part("Knot", V3(s, 0.09, s * 0.7), CFrame.new(at(x, 0.045, z)) * CFrame.Angles(0, rnd() * 3, 0), WOOD_DEEP, DECOR)
		end
	end
end

----------------------------------------------------------------------
-- The four stone lantern pillars (cover from the beam)
----------------------------------------------------------------------
-- a part that's part of the pillar standing (hidden when it breaks)
local function wholePart(pm, name, size, cf, color, extra)
	local p = part(name, size, cf, color, extra, pm)
	p:SetAttribute("Whole", true)
	p:SetAttribute("BaseTransparency", p.Transparency)
	p:SetAttribute("BaseCollide", p.CanCollide)
	return p
end

-- a chunk of the heap it leaves (hidden until it breaks)
local function rubblePart(pm, name, size, cf, color)
	local p = part(name, size, cf, color, merge(DECOR, { Transparency = 1 }), pm)
	p:SetAttribute("Rubble", true)
	return p
end

local function buildPillar(index, x, z)
	local pm = Instance.new("Model")
	pm.Name = "DojoPillar" .. index
	pm.Parent = m
	local base = at(x, 0, z)
	-- the plinth stays, even broken (a stump to stand beside)
	part("PillarPlinth", V3(7.6, 1.2, 7.6), CFrame.new(base + V3(0, 0.6, 0)), STONE_DARK, nil, pm)
	part("PillarPlinthTop", V3(6.8, 0.4, 6.8), CFrame.new(base + V3(0, 1.4, 0)), STONE, nil, pm)
	-- the shaft: two square blocks turned against each other make it eight-sided
	local core = wholePart(pm, "PillarCore", V3(5.4, 10, 5.4), CFrame.new(base + V3(0, 6.6, 0)), STONE)
	wholePart(pm, "PillarShaft", V3(5.4, 10, 5.4), CFrame.new(base + V3(0, 6.6, 0)) * CFrame.Angles(0, math.rad(45), 0), STONE_DARK)
	wholePart(pm, "PillarBand", V3(6.2, 0.6, 6.2), CFrame.new(base + V3(0, 4, 0)), STONE_DEEP, DECOR)
	wholePart(pm, "PillarBand", V3(6.2, 0.6, 6.2), CFrame.new(base + V3(0, 9.4, 0)), STONE_DEEP, DECOR)
	-- the lantern: a red wooden frame, glowing paper windows on all four sides
	wholePart(pm, "LanternSill", V3(7.2, 0.8, 7.2), CFrame.new(base + V3(0, 12, 0)), STONE)
	wholePart(pm, "LanternBox", V3(5.6, 3.6, 5.6), CFrame.new(base + V3(0, 14.2, 0)), RED_DARK)
	local glowParts = {}
	for k = 0, 3 do
		local a = k * math.pi / 2
		local out = V3(math.sin(a), 0, math.cos(a))
		local wcf = CFrame.lookAt(base + V3(0, 14.2, 0) + out * 2.82, base + V3(0, 14.2, 0) + out * 4)
		local win = wholePart(pm, "LanternWindow", V3(3.4, 2.4, 0.1), wcf, LANTERN_GLOW, merge(DECOR, { Material = Mat.Neon }))
		table.insert(glowParts, win)
		wholePart(pm, "LanternBar", V3(0.3, 2.5, 0.12), wcf * CFrame.new(0, 0, -0.02), RED_DARK, DECOR)
		wholePart(pm, "LanternBar", V3(3.5, 0.3, 0.12), wcf * CFrame.new(0, 0, -0.02), RED_DARK, DECOR)
	end
	pulse(glowParts[1], 0.5, 0, 0.25)
	light(glowParts[1], RGB(255, 190, 110), 16, 0.9)
	-- the stepped roof and its knob
	wholePart(pm, "PillarRoof", V3(8.6, 0.9, 8.6), CFrame.new(base + V3(0, 16.45, 0)), ROOF)
	wholePart(pm, "PillarRoof", V3(6.4, 0.8, 6.4), CFrame.new(base + V3(0, 17.3, 0)), ROOF_DARK)
	wholePart(pm, "PillarRoof", V3(3.6, 0.8, 3.6), CFrame.new(base + V3(0, 18.1, 0)), ROOF)
	wholePart(pm, "PillarKnob", V3(1.2, 1.4, 1.2), CFrame.new(base + V3(0, 19.2, 0)), GOLD)
	-- (the eaves' corners curl up: a little block at each)
	for k = 0, 3 do
		local a = math.pi / 4 + k * math.pi / 2
		local c = base + V3(math.sin(a) * 5.6, 16.9, math.cos(a) * 5.6)
		wholePart(pm, "PillarEave", V3(1, 0.6, 1), CFrame.new(c) * CFrame.Angles(0, a, 0), ROOF_DARK, DECOR)
	end

	-- what's left when the beam smashes it: a jagged stump and a heap of stone
	rubblePart(pm, "PillarStump", V3(5, 2.6, 5), CFrame.new(base + V3(0, 2.9, 0)) * CFrame.Angles(0, 0.3, 0.06), STONE)
	rubblePart(pm, "PillarStump", V3(3.2, 1.4, 3.6), CFrame.new(base + V3(0.6, 4.5, -0.4)) * CFrame.Angles(0.2, 0.9, 0.15), STONE_DARK)
	for k = 1, 7 do
		local a = k / 7 * math.pi * 2 + rnd()
		local r = 4.6 + rnd() * 2.2
		local s = 1.2 + rnd() * 1.4
		rubblePart(pm, "PillarRubble", V3(s, s * 0.7, s * 1.1), CFrame.new(base + V3(math.sin(a) * r, s * 0.35, math.cos(a) * r)) * CFrame.Angles(rnd(), rnd() * 3, rnd()),
			(k % 3 == 0) and RED_DARK or ((k % 2 == 0) and STONE or STONE_DARK))
	end

	pm.PrimaryPart = core
	pm:SetAttribute("Floor", 4)
	pm:SetAttribute("Radius", PILLAR_R)
	pm:SetAttribute("Index", index)
	pm:SetAttribute("Broken", false)
	CollectionService:AddTag(pm, "DojoPillar")
	return pm
end

local function buildPillars()
	buildPillar(1, -PILLAR_AT, -PILLAR_AT)
	buildPillar(2, PILLAR_AT, -PILLAR_AT)
	buildPillar(3, -PILLAR_AT, PILLAR_AT)
	buildPillar(4, PILLAR_AT, PILLAR_AT)
end

----------------------------------------------------------------------
-- The mountain top under the dojo, the sea of clouds, the far peaks, the sun
----------------------------------------------------------------------
local function crag(center, w, h, color)
	-- a craggy lump of rock: a few overlapping blocks
	for k = 1, 3 do
		local s = w * (1 - (k - 1) * 0.22)
		part("Crag", V3(s * (0.8 + rnd() * 0.4), h * (1 - (k - 1) * 0.25), s * (0.8 + rnd() * 0.4)),
			CFrame.new(center + V3((rnd() - 0.5) * w * 0.3, -(k - 1) * h * 0.15, (rnd() - 0.5) * w * 0.3)) * CFrame.Angles(0, rnd() * 3, 0),
			(k % 2 == 1) and color or STONE_DEEP, SCENERY)
	end
end

local function buildMountain()
	-- the summit plateau the deck sits on: stone with a grassy fringe
	part("Summit", V3(DECK * 2 + 34, 6, DECK * 2 + 34), CFrame.new(at(0, -5, 0)), STONE_DARK, SCENERY)
	for _, s in ipairs({ -1, 1 }) do
		part("SummitGrass", V3(DECK * 2 + 30, 0.4, 12), CFrame.new(at(0, -1.8, s * (DECK + 9))), GRASS_DARK, DECOR)
		part("SummitGrass", V3(12, 0.4, DECK * 2 + 6), CFrame.new(at(s * (DECK + 9), -1.8, 0)), GRASS_DARK, DECOR)
	end
	-- the peak falling away below, wider and wider, in rough steps
	local layers = {
		{ y = -14, half = 96, h = 14, color = STONE },
		{ y = -30, half = 118, h = 20, color = STONE_DARK },
		{ y = -52, half = 142, h = 26, color = STONE },
		{ y = -80, half = 170, h = 32, color = STONE_DEEP },
	}
	for li, L in ipairs(layers) do
		part("Peak", V3(L.half * 2, L.h, L.half * 2), CFrame.new(at(0, L.y, 0)) * CFrame.Angles(0, li * 0.2, 0), L.color, SCENERY)
		-- crags round its edge so it isn't a clean box
		local count = 10 + li * 3
		for k = 0, count - 1 do
			local a = (k + rnd() * 0.5) / count * math.pi * 2
			local p = onRing(L.half * (1.0 + rnd() * 0.12), a, L.y + L.h * 0.2)
			crag(p, 18 + rnd() * 16, L.h * (0.8 + rnd() * 0.6), L.color)
		end
	end
	-- (snow on the upper crags)
	for k = 0, 11 do
		local a = (k + rnd()) / 12 * math.pi * 2
		local p = onRing(90 + rnd() * 8, a, -8)
		part("SnowCap", V3(10 + rnd() * 6, 1.2, 8 + rnd() * 6), CFrame.new(p) * CFrame.Angles(0, rnd() * 3, 0), SNOW, DECOR)
	end

	-- THE SEA OF CLOUDS below: a solid haze far down, and on it an even field
	-- of flat, blocky clouds (sunset-pink on top), with puffs here and there
	part("CloudHaze", V3(1400, 4, 1400), CFrame.new(at(0, -64, 0)), FOG, DECOR)
	local CELL = 56
	for gx = -11, 11 do
		for gz = -11, 11 do
			local cx, cz = gx * CELL, gz * CELL
			local r = math.sqrt(cx * cx + cz * cz)
			if r > 150 and r < 640 and rnd() < 0.72 then
				local w, d = CELL * (0.7 + rnd() * 0.5), CELL * (0.6 + rnd() * 0.5)
				local y = -52 + math.floor(rnd() * 3) * 2
				local p0 = at(cx + (rnd() - 0.5) * 16, y, cz + (rnd() - 0.5) * 16)
				part("CloudSea", V3(w, 5, d), CFrame.new(p0), WHITE, DECOR)
				if rnd() < 0.55 then
					part("CloudSeaTop", V3(w * 0.6, 3, d * 0.55), CFrame.new(p0 + V3((rnd() - 0.5) * w * 0.3, 3.8, (rnd() - 0.5) * d * 0.3)),
						(rnd() < 0.4) and PINK or FOG, DECOR)
				end
				if rnd() < 0.25 then
					part("CloudPuff", V3(w * 0.3, 5, d * 0.3), CFrame.new(p0 + V3((rnd() - 0.5) * w * 0.4, 7, (rnd() - 0.5) * d * 0.4)), WHITE, DECOR)
				end
			end
		end
	end
	-- a ring of cloud hugging the mountain itself
	for k = 0, 17 do
		local a = (k + rnd() * 0.5) / 18 * math.pi * 2
		local p = onRing(132 + rnd() * 20, a, -40 + rnd() * 6)
		local s = 40 + rnd() * 30
		part("CloudCollar", V3(s * 1.4, 7, s), CFrame.new(p) * CFrame.Angles(0, math.floor(a / (math.pi / 2) + 0.5) * math.pi / 2, 0), WHITE, DECOR)
	end

	-- FAR PEAKS poking out of the clouds (purple in the evening light), snowy tops
	for i = 0, 13 do
		local a = (i + rnd() * 0.5) / 14 * math.pi * 2
		local p = onRing(380 + rnd() * 160, a, -60)
		local w = 70 + rnd() * 70
		local h = 90 + rnd() * 90
		local mcf = facingCentre(p)
		part("FarPeak", V3(w, h * 0.55, 40), mcf * CFrame.new(0, h * 0.275, 0), (i % 2 == 0) and MOUNTAIN or MOUNTAIN_DEEP, SCENERY)
		part("FarPeak", V3(w * 0.6, h * 0.3, 36), mcf * CFrame.new(rnd() * 8, h * 0.7, 0), MOUNTAIN, SCENERY)
		part("FarPeakSnow", V3(w * 0.32, h * 0.16, 34), mcf * CFrame.new(rnd() * 5, h * 0.92, 0), SNOW, SCENERY)
		if i == 3 or i == 9 then
			-- a tiny pagoda on top of this one
			local top = mcf * CFrame.new(0, h * 1.0 + 2, 0)
			for k = 0, 3 do
				local s = 16 - k * 3.4
				part("FarPagoda", V3(s * 0.7, 3, s * 0.7), top * CFrame.new(0, k * 5, 0), RED_DARK, SCENERY)
				part("FarPagodaRoof", V3(s, 1.4, s), top * CFrame.new(0, k * 5 + 2.2, 0), ROOF_DARK, SCENERY)
			end
		end
	end

	-- THE SUN, huge and low in the west, striped by thin clouds
	local sunPos = at(-640, 60, 160)
	local scf = CFrame.lookAt(sunPos, at(0, 60, 0))
	part("SunHalo", V3(190, 190, 1), scf * CFrame.new(0, 0, 2), ORANGE, merge(DECOR, { Material = Mat.Neon, Transparency = 0.55 }))
	cylinder("Sun", 1, 130, scf * CFrame.Angles(math.pi / 2, 0, 0), GOLD, merge(DECOR, { Material = Mat.Neon }))
	for k = 1, 4 do
		part("SunStripe", V3(170 - k * 18, 4 + k, 1.4), scf * CFrame.new((rnd() - 0.5) * 30, -18 - k * 12, -2), (k % 2 == 0) and PINK or PINK_DEEP, DECOR)
	end

	-- little blocky clouds up in the sky
	for _ = 1, 10 do
		local a = rnd() * math.pi * 2
		local p = onRing(200 + rnd() * 260, a, 90 + rnd() * 60)
		local s = 14 + rnd() * 12
		local yaw = CFrame.Angles(0, rnd() * 3, 0)
		part("SkyCloud", V3(s * 2, s * 0.4, s), CFrame.new(p) * yaw, WHITE, DECOR)
		part("SkyCloud", V3(s, s * 0.35, s * 0.7), CFrame.new(p + V3(0, s * 0.35, 0)) * yaw * CFrame.new(s * 0.2, 0, 0), PINK, DECOR)
	end
end

----------------------------------------------------------------------
-- The gate and the way in (south)
----------------------------------------------------------------------
local function buildGate()
	-- the stone landing between the floor and the gate
	part("Landing", V3(GAP * 2 + 6, 4, LANDING_Z - DECK + 2), CFrame.new(at(0, -2, (DECK + LANDING_Z) / 2)), STONE)
	for z = DECK + 3, LANDING_Z - 2, 4 do
		part("LandingSlab", V3(GAP * 2 + 5, 0.1, 0.3), CFrame.new(at(0, 0.05, z)), STONE_DARK, DECOR)
	end
	-- stairs going down behind the gate, into the cloud
	for k = 1, 12 do
		part("Stair", V3(GAP * 2 + 4, 1.4, 3), CFrame.new(at(0, -0.7 - k * 1.4, LANDING_Z + 1.5 + (k - 1) * 3)), (k % 2 == 0) and STONE or STONE_DARK, SCENERY)
	end
	-- stone lanterns either side of the landing
	for _, sx in ipairs({ -1, 1 }) do
		local p = at(sx * (GAP + 5), 0, DECK + 10)
		part("TouroBase", V3(3, 2, 3), CFrame.new(p + V3(0, ROCK / 2, 0)), STONE_DEEP)
		part("TouroFoot", V3(2.4, 1, 2.4), CFrame.new(p + V3(0, 0.5, 0)), STONE_DARK)
		part("TouroPost", V3(1.2, 3.4, 1.2), CFrame.new(p + V3(0, 2.7, 0)), STONE)
		part("TouroBox", V3(2.4, 2, 2.4), CFrame.new(p + V3(0, 5.4, 0)), STONE_DARK)
		local glow = part("TouroGlow", V3(1.6, 1.2, 2.5), CFrame.new(p + V3(0, 5.4, 0)), LANTERN_GLOW, merge(DECOR, { Material = Mat.Neon }))
		pulse(glow, 0.6, 0, 0.3)
		light(glow, RGB(255, 190, 110), 14, 0.8)
		part("TouroRoof", V3(3.6, 0.7, 3.6), CFrame.new(p + V3(0, 6.75, 0)), ROOF_DARK)
		part("TouroKnob", V3(0.8, 0.8, 0.8), CFrame.new(p + V3(0, 7.5, 0)), STONE)
	end

	-- THE RED GATE (a torii): two red posts, a black-topped beam across the
	-- top with its ends swept up, a second beam under it, a plaque between
	local gcf = CFrame.lookAt(at(0, 0, GATE_Z), at(0, 0, 0)) -- (-Z faces the dojo)
	local function blk(name, size, x, y, z, color, extra)
		return part(name, size, gcf * CFrame.new(x, y, z), color or RED, extra)
	end
	for _, sx in ipairs({ -1, 1 }) do
		blk("ToriiFoot", V3(3.4, 1.6, 3.4), sx * 10.5, 0.8, 0, INK)
		blk("ToriiPost", V3(2.4, 20, 2.4), sx * 10.5, 10.8, 0)
	end
	blk("ToriiNuki", V3(26, 1.6, 1.6), 0, 16, 0) -- the lower beam
	blk("ToriiKasagi", V3(31, 1.8, 2.8), 0, 21.4, 0) -- the top beam
	blk("ToriiKasagiTop", V3(33, 1, 3.2), 0, 22.8, 0, INK)
	for _, sx in ipairs({ -1, 1 }) do
		-- (the swept-up ends)
		blk("ToriiTip", V3(2.4, 1.2, 3.2), sx * 16.4, 23.6, 0, INK)
	end
	local plaque = blk("ToriiPlaque", V3(4.6, 4.4, 0.6), 0, 18.7, -0.2, INK)
	blk("ToriiPlaqueFace", V3(3.8, 3.6, 0.1), 0, 18.7, -0.55, GOLD, DECOR)
	signText(plaque, "KAZE", RED_DARK, Enum.NormalId.Front)

	-- behind the gate: an invisible wall, so nobody walks down the stairs
	blk("GateBack", V3(30, 26, 2), 0, 13, 4.5, WHITE, { Transparency = 1, CastShadow = false })

	-- the fog in the gateway: the way out
	local fog = blk("FogWall", V3(18.6, 15, 0.6), 0, 7.6, 0, FOG, { Transparency = 0.45, CanCollide = false, CastShadow = false, Material = Mat.Neon })
	pulse(fog, 0.4, 0.35, 0.6)
	local fe = Instance.new("ParticleEmitter")
	fe.Rate = 8
	fe.Color = ColorSequence.new(RGB(255, 240, 235))
	fe.LightEmission = 0.4
	fe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 6) })
	fe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	fe.Lifetime = NumberRange.new(2, 3)
	fe.Speed = NumberRange.new(0.5, 1.5)
	fe.Parent = fog
	local exit = Instance.new("ProximityPrompt")
	exit.ActionText = "Leave"
	exit.ObjectText = "Dojo Gate"
	exit.HoldDuration = 0.4
	exit.MaxActivationDistance = 14
	exit.KeyboardKeyCode = Enum.KeyCode.E
	exit.GamepadKeyCode = Enum.KeyCode.ButtonX
	exit.RequiresLineOfSight = false
	exit.Parent = fog
	CollectionService:AddTag(exit, "ArenaExit")
	autoZone(gcf * CFrame.new(0, 4, -3), V3(16, 8, 6), "Spire", "Leave")

	-- a sign by the landing: THE ROOFTOP DOJO
	local sp = at(GAP + 4.5, ROCK, DECK + 5)
	local signCF = CFrame.lookAt(sp, sp + V3(-0.3, 0, 1))
	part("SignPost", V3(0.7, 6.4, 0.7), signCF * CFrame.new(0, 3.2, 0), WOOD_DEEP)
	local board = part("SignBoard", V3(6.4, 2.4, 0.4), signCF * CFrame.new(0, 6.6, 0), WOOD_LIGHT)
	part("SignTrim", V3(6.8, 0.3, 0.45), signCF * CFrame.new(0, 7.85, 0), WOOD_DEEP, DECOR)
	signText(board, "THE ROOFTOP\nDOJO", BARK, Enum.NormalId.Front)

	-- where you arrive: on the landing, looking at the dojo
	local arrive = anchorPart("ArenaSpawn", CFrame.lookAt(at(0, 3, SPAWN_Z), at(0, 3, 0)))
	CollectionService:AddTag(arrive, "ArenaSpawn")
end

----------------------------------------------------------------------
-- The dojo hall (north), its gong and the training things round it
----------------------------------------------------------------------
local function buildHall()
	local z0 = -(DECK + 6) -- its front
	local depth, width, wallH = 30, 76, 14
	local zc = z0 - depth / 2
	-- a stone foundation
	part("HallFoundation", V3(width + 6, 5, depth + 6), CFrame.new(at(0, -1.5, zc)), STONE_DARK, SCENERY)
	part("HallStep", V3(30, 1, 5), CFrame.new(at(0, 0.5, z0 + 3.5)), STONE, SCENERY)
	-- the floor and the walls: white paper panels in a dark wooden grid
	part("HallFloor", V3(width, 1, depth), CFrame.new(at(0, 1.5, zc)), WOOD_DEEP, SCENERY)
	part("HallBack", V3(width, wallH, 1), CFrame.new(at(0, 2 + wallH / 2, zc - depth / 2)), PAPER, SCENERY)
	for _, sx in ipairs({ -1, 1 }) do
		part("HallSide", V3(1, wallH, depth), CFrame.new(at(sx * width / 2, 2 + wallH / 2, zc)), PAPER, SCENERY)
	end
	-- the front: paper walls either side of an open doorway
	local door = 22
	local side = (width - door) / 2
	for _, sx in ipairs({ -1, 1 }) do
		local cx = sx * (door / 2 + side / 2)
		part("HallFront", V3(side, wallH, 0.6), CFrame.new(at(cx, 2 + wallH / 2, z0)), PAPER, SCENERY)
		-- the lattice over the paper
		for k = 1, 4 do
			local x = cx - side / 2 + k * side / 5
			part("Lattice", V3(0.3, wallH, 0.2), CFrame.new(at(x, 2 + wallH / 2, z0 + 0.4)), WOOD_DEEP, DECOR)
		end
		for y = 5, 13, 4 do
			part("Lattice", V3(side, 0.3, 0.2), CFrame.new(at(cx, y, z0 + 0.4)), WOOD_DEEP, DECOR)
		end
	end
	-- the dark inside, seen through the doorway, with a hanging scroll
	part("HallInside", V3(door, wallH, 0.4), CFrame.new(at(0, 2 + wallH / 2, zc - depth / 2 + 1.2)), INK, SCENERY)
	part("Scroll", V3(4, 8, 0.2), CFrame.new(at(0, 9, zc - depth / 2 + 1.5)), PAPER, DECOR)
	part("ScrollInk", V3(1.2, 5, 0.1), CFrame.new(at(0, 9, zc - depth / 2 + 1.62)), INK, DECOR)
	part("ScrollRod", V3(4.8, 0.4, 0.4), CFrame.new(at(0, 13.1, zc - depth / 2 + 1.5)), WOOD_DEEP, DECOR)
	-- red posts along the front
	for k = 0, 6 do
		local x = -width / 2 + k * width / 6
		part("HallPost", V3(1.6, wallH + 1, 1.6), CFrame.new(at(x, 2 + (wallH + 1) / 2, z0 + 1)), RED)
	end
	part("HallBeam", V3(width + 2, 1.4, 1.8), CFrame.new(at(0, 2 + wallH + 0.7, z0 + 1)), RED_DARK)
	-- THE ROOF: stepped tiles, the eaves swept up at the corners
	local roofY = 2 + wallH + 1.4
	local steps = { { w = width + 16, d = depth + 14, h = 2.4, c = ROOF }, { w = width + 6, d = depth + 6, h = 3, c = ROOF_DARK },
		{ w = width - 6, d = depth - 4, h = 3, c = ROOF }, { w = width - 20, d = depth - 14, h = 2.6, c = ROOF_DARK },
		{ w = width - 36, d = 6, h = 2.4, c = ROOF } }
	local y = roofY
	for _, s in ipairs(steps) do
		part("HallRoof", V3(s.w, s.h, s.d), CFrame.new(at(0, y + s.h / 2, zc)), s.c, SCENERY)
		y = y + s.h
	end
	part("RoofRidge", V3(width - 30, 1.4, 2), CFrame.new(at(0, y + 0.7, zc)), INK, SCENERY)
	for _, sx in ipairs({ -1, 1 }) do
		part("RoofFin", V3(2, 3, 2), CFrame.new(at(sx * (width - 30) / 2, y + 1.5, zc)), GOLD, SCENERY)
		for _, sz in ipairs({ -1, 1 }) do
			wedge("EaveTip", V3(3, 2.6, 6), CFrame.new(at(sx * ((width + 16) / 2 - 1.5), roofY + 2.4 + 1.3, zc + sz * ((depth + 14) / 2 - 3)))
				* CFrame.Angles(0, (sx > 0) and -math.pi / 2 or math.pi / 2, 0), ROOF_DARK, SCENERY)
		end
	end
	-- the sign over the doorway: KAZE DOJO
	local board = part("HallSign", V3(18, 4, 0.6), CFrame.new(at(0, 2 + wallH - 1.2, z0 + 1.9)), INK)
	part("HallSignFrame", V3(19, 4.8, 0.4), CFrame.new(at(0, 2 + wallH - 1.2, z0 + 1.6)), GOLD, DECOR)
	signText(board, "KAZE DOJO", GOLD_LIGHT, Enum.NormalId.Front)
	-- round paper lanterns hanging from the beam
	for _, x in ipairs({ -30, -18, 18, 30 }) do
		local p = at(x, 2 + wallH - 2.2, z0 + 2.4)
		part("LanternCord", V3(0.2, 1.4, 0.2), CFrame.new(p + V3(0, 1.9, 0)), INK, DECOR)
		local lamp = part("HallLantern", V3(2.2, 2.8, 2.2), CFrame.new(p), RED, merge(DECOR, { Material = Mat.Neon }))
		part("HallLanternCap", V3(1.4, 0.4, 1.4), CFrame.new(p + V3(0, 1.5, 0)), INK, DECOR)
		part("HallLanternCap", V3(1.4, 0.4, 1.4), CFrame.new(p - V3(0, 1.5, 0)), INK, DECOR)
		pulse(lamp, 0.5, 0, 0.3)
	end

	-- THE GONG, in its wooden frame, beside the hall
	local g = at(-(width / 2 + 12), ROCK, z0 - 4)
	for _, sx in ipairs({ -1, 1 }) do
		part("GongPost", V3(1.4, 16, 1.4), CFrame.new(g + V3(sx * 7, 8, 0)), WOOD_DEEP)
	end
	part("GongBeam", V3(17, 1.6, 1.8), CFrame.new(g + V3(0, 16.2, 0)), RED_DARK)
	part("GongBeamTop", V3(18.4, 0.8, 2.2), CFrame.new(g + V3(0, 17.4, 0)), INK)
	for _, sx in ipairs({ -1, 1 }) do
		part("GongCord", V3(0.2, 3, 0.2), CFrame.new(g + V3(sx * 2.4, 14, 0)), INK, DECOR)
	end
	-- (a disc on its edge, facing the floor: a cylinder's round faces point along its X)
	local face = CFrame.new(g + V3(0, 8.4, 0)) * CFrame.Angles(0, math.pi / 2, 0)
	part("GongRim", V3(0.9, 10.8, 10.8), face * CFrame.new(0.05, 0, 0), ORANGE, merge(DECOR, { Shape = Enum.PartType.Cylinder }))
	part("Gong", V3(1.0, 10, 10), face, GOLD, merge(DECOR, { Shape = Enum.PartType.Cylinder }))
	part("GongBoss", V3(1.3, 3, 3), face, GOLD_LIGHT, merge(DECOR, { Shape = Enum.PartType.Cylinder }))
	part("GongMallet", V3(0.4, 5, 0.4), CFrame.new(g + V3(4, 2.6, 2)) * CFrame.Angles(0, 0, 0.3), WOOD_DEEP, DECOR)
	part("GongMalletHead", V3(1.4, 1.4, 1.4), CFrame.new(g + V3(4.7, 5, 2)), RED_DARK, DECOR)

	-- TRAINING THINGS on the plateau: wooden posts wrapped in rope, a wooden
	-- dummy with arms, a rack of staffs, a stack of tiles someone split
	local east = at(width / 2 + 10, ROCK, z0 - 2)
	for k = 0, 2 do
		local p = east + V3(k * 5, 0, (k % 2) * 3)
		part("Makiwara", V3(1.4, 6, 1.4), CFrame.new(p + V3(0, 3, 0)), WOOD)
		part("MakiwaraRope", V3(1.6, 1.6, 1.6), CFrame.new(p + V3(0, 4.6, 0)), PAPER, DECOR)
		part("MakiwaraRope", V3(1.6, 0.3, 1.6), CFrame.new(p + V3(0, 3.6, 0)), WOOD_DEEP, DECOR)
	end
	local dummy = at(-(DECK + 8), ROCK, -40)
	part("DummyPost", V3(2, 7, 2), CFrame.new(dummy + V3(0, 3.5, 0)), WOOD_DARK)
	part("DummyHead", V3(1.4, 1.4, 1.4), CFrame.new(dummy + V3(0, 7.7, 0)), WOOD_DARK)
	for k, yy in ipairs({ 5.4, 4.6, 3 }) do
		local a = (k == 2) and 0 or ((k == 1) and 0.5 or -0.5)
		part("DummyArm", V3(0.5, 0.5, 2.6), CFrame.new(dummy + V3(0, yy, 0)) * CFrame.Angles(0, a + math.pi, 0) * CFrame.new(0, 0, -1.8), WOOD_DEEP, DECOR)
	end
	local rack = at(DECK + 8, ROCK, -44)
	part("RackFoot", V3(1.6, 0.8, 8), CFrame.new(rack + V3(0, 0.4, 0)), WOOD_DEEP)
	part("RackBar", V3(0.6, 0.6, 8), CFrame.new(rack + V3(0, 5, 0)), WOOD_DEEP)
	for k = 0, 3 do
		part("Staff", V3(0.35, 7, 0.35), CFrame.new(rack + V3(-0.5, 3.6, -3 + k * 2)) * CFrame.Angles(0, 0, 0.12), (k % 2 == 0) and WOOD or WOOD_LIGHT, DECOR)
	end
	local tiles = at(-(DECK + 10), ROCK, -24)
	for _, sx in ipairs({ -1, 1 }) do
		part("TileBlock", V3(1.4, 2.4, 1.4), CFrame.new(tiles + V3(sx * 2.2, 1.2, 0)), STONE_DARK, DECOR)
	end
	for k = 0, 4 do
		local split = k >= 3
		for _, sx in ipairs(split and { -1, 1 } or { 0 }) do
			local w = split and 2.3 or 5.8
			part("Tile", V3(w, 0.35, 2.4), CFrame.new(tiles + V3(sx * 1.6, 2.6 + k * 0.45, 0)) * CFrame.Angles(0, 0, split and sx * -0.25 or 0),
				(k % 2 == 0) and RED_DARK or ORANGE, DECOR)
		end
	end

	-- tall banners (nobori) along the back of the floor, red and white
	for k = 0, 5 do
		local x = -50 + k * 20
		if math.abs(x) > 14 then
			local p = at(x, 0, -(DECK + 2.5))
			part("BannerPole", V3(0.5, 14, 0.5), CFrame.new(p + V3(0, 7, 0)), INK, DECOR)
			part("BannerArm", V3(0.3, 0.3, 3), CFrame.new(p + V3(0, 13.6, 1.5)), INK, DECOR)
			local red = k % 2 == 0
			part("Banner", V3(0.15, 10, 2.8), CFrame.new(p + V3(0, 8.4, 1.6)), red and RED or WHITE, DECOR)
			part("BannerMark", V3(0.2, 1.8, 1.8), CFrame.new(p + V3(0, 10.4, 1.6)) * CFrame.Angles(math.rad(45), 0, 0), red and WHITE or RED, DECOR)
			part("BannerMark", V3(0.2, 1.2, 1.2), CFrame.new(p + V3(0, 7, 1.6)), red and WHITE or RED, DECOR)
		end
	end
end

----------------------------------------------------------------------
-- The edges: railings, lanterns on ropes, cherry trees
----------------------------------------------------------------------
local function buildEdges()
	-- a low wooden railing along the east and west edges, and the north
	for _, sx in ipairs({ -1, 1 }) do
		for k = 0, 16 do
			local z = -DECK + 2 + k * (DECK * 2 - 4) / 16
			part("RailPost", V3(0.8, 3, 0.8), CFrame.new(at(sx * (DECK - 0.6), 1.5, z)), RED_DARK, DECOR)
		end
		part("Rail", V3(0.6, 0.5, DECK * 2 - 3), CFrame.new(at(sx * (DECK - 0.6), 2.9, 0)), RED, DECOR)
		part("Rail", V3(0.4, 0.3, DECK * 2 - 3), CFrame.new(at(sx * (DECK - 0.6), 1.6, 0)), RED_DARK, DECOR)
	end
	for k = 0, 16 do
		local x = -DECK + 2 + k * (DECK * 2 - 4) / 16
		part("RailPost", V3(0.8, 3, 0.8), CFrame.new(at(x, 1.5, -(DECK - 0.6))), RED_DARK, DECOR)
	end
	part("Rail", V3(DECK * 2 - 3, 0.5, 0.6), CFrame.new(at(0, 2.9, -(DECK - 0.6))), RED, DECOR)
	-- the south edge: railing either side of the way in
	for _, sx in ipairs({ -1, 1 }) do
		local x0, x1 = sx * (GAP + 1), sx * (DECK - 1)
		part("Rail", V3(math.abs(x1 - x0), 0.5, 0.6), CFrame.new(at((x0 + x1) / 2, 2.9, DECK - 0.6)), RED, DECOR)
		for k = 0, 7 do
			local x = x0 + (x1 - x0) * k / 7
			part("RailPost", V3(0.8, 3, 0.8), CFrame.new(at(x, 1.5, DECK - 0.6)), RED_DARK, DECOR)
		end
	end

	-- paper lanterns strung on ropes between tall posts, east and west
	for _, sx in ipairs({ -1, 1 }) do
		local posts = {}
		for k = 0, 4 do
			local z = -48 + k * 24
			local p = at(sx * (DECK + 4), 0, z)
			part("LanternPole", V3(0.8, 15, 0.8), CFrame.new(p + V3(0, 5.5, 0)), WOOD_DEEP, DECOR)
			part("LanternPoleCap", V3(1.2, 0.6, 1.2), CFrame.new(p + V3(0, 13.3, 0)), INK, DECOR)
			posts[#posts + 1] = p + V3(0, 12.6, 0)
		end
		for k = 1, #posts - 1 do
			local a, b = posts[k], posts[k + 1]
			-- the rope sags between the posts: three pieces
			local pts = {}
			for j = 0, 3 do
				local u = j / 3
				pts[j] = a:Lerp(b, u) - V3(0, 2.2 * 4 * u * (1 - u), 0)
			end
			for j = 0, 2 do
				local p, q = pts[j], pts[j + 1]
				part("LanternRope", V3(0.2, 0.2, (q - p).Magnitude + 0.1), CFrame.lookAt((p + q) / 2, q), INK, DECOR)
			end
			for j = 1, 2 do
				local p = pts[j] - V3(0, 1.6, 0)
				local lamp = part("RopeLantern", V3(1.6, 2, 1.6), CFrame.new(p), ((k + j) % 2 == 0) and RED or WHITE, merge(DECOR, { Material = Mat.Neon }))
				part("RopeLanternCap", V3(1.1, 0.3, 1.1), CFrame.new(p + V3(0, 1.1, 0)), INK, DECOR)
				pulse(lamp, 0.4 + rnd() * 0.3, 0, 0.3)
			end
		end
	end

	-- CHERRY TREES round the summit, shedding petals
	local function cherry(p, s, petals)
		-- a gnarled trunk: two leaning pieces
		local lean = rnd() * math.pi * 2
		local tilt = CFrame.Angles(0, lean, 0.18)
		local t1 = CFrame.new(p) * tilt * CFrame.new(0, 3.5 * s, 0)
		part("CherryTrunk", V3(1.8 * s, 7 * s, 1.8 * s), t1, BARK, SCENERY)
		local top = (t1 * CFrame.new(0, 3.5 * s, 0)).Position
		local t2 = CFrame.new(top) * CFrame.Angles(0, lean + 2.2, 0.35) * CFrame.new(0, 2.5 * s, 0)
		part("CherryBranch", V3(1.2 * s, 5 * s, 1.2 * s), t2, BARK, SCENERY)
		local crown = (t2 * CFrame.new(0, 2.2 * s, 0)).Position
		-- the blossom: big pink blocks, a lighter one on top, a few white specks
		part("Blossom", V3(9 * s, 4 * s, 8 * s), CFrame.new(crown) * CFrame.Angles(0, rnd(), 0), PINK, SCENERY)
		part("Blossom", V3(6.5 * s, 3 * s, 6 * s), CFrame.new(crown + V3(1 * s, 2.8 * s, 0.5 * s)) * CFrame.Angles(0, rnd(), 0), WHITE, SCENERY)
		part("Blossom", V3(5 * s, 3 * s, 5 * s), CFrame.new(crown + V3(-3.5 * s, -1 * s, 1.5 * s)) * CFrame.Angles(0, rnd(), 0), PINK_DEEP, SCENERY)
		part("Blossom", V3(4.5 * s, 2.6 * s, 4 * s), CFrame.new(crown + V3(3 * s, -0.6 * s, -2.5 * s)) * CFrame.Angles(0, rnd(), 0), PINK, SCENERY)
		if petals then
			local e = Instance.new("ParticleEmitter")
			e.Name = "Petals"
			e.Color = ColorSequence.new(PINK, WHITE)
			e.LightInfluence = 0.6
			e.Size = NumberSequence.new(0.35)
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0.2), NumberSequenceKeypoint.new(1, 1) })
			e.Lifetime = NumberRange.new(4, 6)
			e.Speed = NumberRange.new(1, 3)
			e.Acceleration = V3(3, -1.5, 1)
			e.Rotation = NumberRange.new(0, 360)
			e.RotSpeed = NumberRange.new(-90, 90)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Rate = 3
			e.Parent = part("PetalCloud", V3(8 * s, 3 * s, 8 * s), CFrame.new(crown), PINK, merge(DECOR, { Transparency = 1 }))
		end
		-- fallen petals on the ground under it
		for _ = 1, 4 do
			local q = p + V3((rnd() - 0.5) * 10 * s, 0.05, (rnd() - 0.5) * 10 * s)
			part("FallenPetals", V3(1.4 + rnd(), 0.08, 1 + rnd()), CFrame.new(q) * CFrame.Angles(0, rnd() * 3, 0), PINK, DECOR)
		end
	end
	local spots = {
		{ -76, -60, 1.3, true }, { 76, -58, 1.2, true }, { -78, 30, 1.1, false }, { 78, 34, 1.3, true },
		{ -70, 74, 1.2, true }, { 72, 76, 1.1, false }, { -82, -12, 1.0, false }, { 84, -8, 1.0, false },
	}
	for _, s in ipairs(spots) do
		cherry(at(s[1], -1.6, s[2]), s[3], s[4])
	end

	-- stone lanterns at the floor's four corners (on the rock, just outside)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local p = at(sx * (DECK + 6), -1.6, sz * (DECK + 6))
			part("CornerFoot", V3(3, 1.4, 3), CFrame.new(p + V3(0, 0.7, 0)), STONE_DARK, SCENERY)
			part("CornerPost", V3(1.5, 4.5, 1.5), CFrame.new(p + V3(0, 3.6, 0)), STONE, SCENERY)
			part("CornerBox", V3(3, 2.4, 3), CFrame.new(p + V3(0, 7, 0)), STONE_DARK, SCENERY)
			local glow = part("CornerGlow", V3(2.2, 1.4, 3.1), CFrame.new(p + V3(0, 7, 0)), LANTERN_GLOW, merge(DECOR, { Material = Mat.Neon }))
			pulse(glow, 0.5, 0, 0.3)
			part("CornerRoof", V3(4.6, 0.9, 4.6), CFrame.new(p + V3(0, 8.65, 0)), ROOF_DARK, SCENERY)
			part("CornerKnob", V3(1, 1, 1), CFrame.new(p + V3(0, 9.6, 0)), STONE, SCENERY)
		end
	end
	-- a few mossy rocks and bamboo on the plateau
	for _ = 1, 14 do
		local x = (rnd() < 0.5 and -1 or 1) * (DECK + 6 + rnd() * 10)
		local z = (rnd() * 2 - 1) * (DECK + 8)
		local s = 1.5 + rnd() * 2.5
		part("Rock", V3(s * 1.3, s, s), CFrame.new(at(x, -1.6 + s * 0.4, z)) * CFrame.Angles(0, rnd() * 3, rnd() * 0.3), pick({ STONE, STONE_DARK }), SCENERY)
		part("Moss", V3(s * 1.1, 0.3, s * 0.8), CFrame.new(at(x, -1.6 + s * 0.9, z)), GRASS, DECOR)
	end
	for k = 0, 9 do
		local x = -(DECK + 12) + (k % 2) * 2.2
		local z = 14 + k * 2.6
		local h = 12 + rnd() * 6
		part("Bamboo", V3(0.7, h, 0.7), CFrame.new(at(x, -1.6 + h / 2, z)) * CFrame.Angles(0, 0, (rnd() - 0.5) * 0.1), GRASS, SCENERY)
		part("BambooLeaves", V3(3, 1.2, 1.4), CFrame.new(at(x + 1, -1.6 + h, z)) * CFrame.Angles(0, rnd() * 3, 0.3), GRASS_DARK, DECOR)
	end
end

----------------------------------------------------------------------
-- The walls round the fight, and the marks the boss will use
----------------------------------------------------------------------
local function wall(cf, size)
	local w = part("EdgeWall", size, cf, WHITE, { Transparency = 1, CanQuery = false, CastShadow = false })
	CollectionService:AddTag(w, "DojoEdgeWall")
	return w
end

local function buildBounds()
	local H = 60
	-- north, east and west: whole walls
	wall(CFrame.new(at(0, H / 2, -FIGHT - 1)), V3(FIGHT * 2 + 4, H, 2))
	wall(CFrame.new(at(-FIGHT - 1, H / 2, 0)), V3(2, H, FIGHT * 2 + 4))
	wall(CFrame.new(at(FIGHT + 1, H / 2, 0)), V3(2, H, FIGHT * 2 + 4))
	-- south: either side of the way in from the gate
	for _, sx in ipairs({ -1, 1 }) do
		local x0, x1 = sx * GAP, sx * (FIGHT + 2)
		wall(CFrame.new(at((x0 + x1) / 2, H / 2, FIGHT + 1)), V3(math.abs(x1 - x0), H, 2))
		-- the landing's sides, out to the gate
		local z0, z1 = FIGHT, GATE_Z + 3
		wall(CFrame.new(at(sx * (GAP + 1), H / 2, (z0 + z1) / 2)), V3(2, H, z1 - z0))
	end
	-- Where Kaze meditates: the middle of the floor, facing the gate you come in
	-- by. BossService builds Kaze himself on this spot.
	local home = anchorPart("BossHome", CFrame.new(at(0, 0, 0)))
	home:SetAttribute("Floor", 4)
	home:SetAttribute("Facing", V3(0, 0, 1))
	CollectionService:AddTag(home, "BossHome")
end

----------------------------------------------------------------------
-- Public
----------------------------------------------------------------------
function DojoBuilder.Build()
	local old = Workspace:FindFirstChild("DojoArena")
	if old then
		old:Destroy()
	end
	m = Instance.new("Model")
	m.Name = "DojoArena"
	seed = 20260927 -- (the same "random" every time it's built)

	-- each piece on its own, so one mistake can't leave the whole arena missing
	local pieces = {
		{ "Floor", buildDeck },
		{ "Pillars", buildPillars },
		{ "Mountain and sky", buildMountain },
		{ "Gate", buildGate },
		{ "Hall", buildHall },
		{ "Edges and trees", buildEdges },
		{ "Walls and markers", buildBounds },
	}
	local failed = 0
	for _, piece in ipairs(pieces) do
		local ok, err = pcall(piece[2])
		if not ok then
			failed = failed + 1
			warn("[DojoBuilder] '" .. piece[1] .. "' failed to build: " .. tostring(err))
		end
	end

	m:SetAttribute("Floor", 4)
	m:SetAttribute("Center", CENTER)
	m:SetAttribute("Half", FIGHT) -- (how far out the walls are: the floor is a square)
	m.Parent = Workspace
	if failed == 0 then
		print("[DojoBuilder] The Rooftop Dojo built OK")
	end
	return m
end

-- (for Bosses/Kaze.lua and the tests: where things are)
DojoBuilder.Center = CENTER
DojoBuilder.Fight = FIGHT
DojoBuilder.PillarAt = PILLAR_AT
DojoBuilder.PillarRadius = PILLAR_R

return DojoBuilder
