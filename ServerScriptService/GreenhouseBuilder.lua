--[[
	GreenhouseBuilder  (ModuleScript, parent: ServerScriptService, name: "GreenhouseBuilder")

	Builds the Spire's eighth floor: THE GLASSHOUSE GARDEN, Petalina's arena.

	A giant old-fashioned greenhouse: a low brick wall with tall glass walls
	on top in white frames, and a glass roof rising to a ridge, with a little
	glass lantern on top. Sunlight streams in. Inside is a round garden:
	paved paths - a ring round the middle, four straight paths out to the
	edge, and a ring round the outside - and between them four big raised
	flower beds full of tulips, daisies and little bushes. Petalina grows
	out of a mound of roots in the very middle. Potted palms, stacks of
	flowerpots, watering cans and a wheelbarrow fill the corners; baskets of
	flowers hang from the roof; butterflies flit about. Outside: a lawn,
	hedges, trees and a white picket fence. You come in through the glass
	doors in the south wall. Everything is chunky and 8-bit, in the game's
	32 colours.

	The garden's shape comes from ReplicatedStorage/GardenPlan (the same
	numbers Petalina's moves and every screen use).

	Everything the fight needs is marked for SpireService / BossService:
	  * "ArenaSpawn"       where you arrive (in this model, Floor = 8)
	  * "ArenaExit"        the Leave prompt on the glass doors, plus a walk-up
	                       box (AutoOpenZone, Spire = "Leave")
	  * "BossHome"         the middle of the garden, Floor = 8, facing the door
	  * "GardenEdgeWall"   the invisible walls round the round garden you fight in
	  * "GardenThorn"      round 2's brambles (models: Floor = 8, Delay, Up):
	                       built hidden in the soil of the flower beds, and
	                       grown up out of it on each player's screen when she
	                       turns evil (her body file does that)
	  * "GardenButterfly"  the butterflies (models: Floor = 8, Index) - her body
	                       file makes them flit about
	  * the model itself carries Floor = 8, Center (the middle of the garden)
	    and FightRadius (how far out the invisible wall stands)

	Main calls GreenhouseBuilder.Build() once at startup, after the other
	floors and before BossService (which puts Petalina on her BossHome).
	The floor you fight on - the paving - is one solid, flat Part whose top
	is exactly y = 0 (not Terrain: Terrain rounds its surface to its own
	grid). The flower beds stand a little above it (you step up onto them).
]]

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GardenPlan = require(ReplicatedStorage:WaitForChild("GardenPlan"))

local GreenhouseBuilder = {}

local V3 = Vector3.new
local RGB = Color3.fromRGB
local Mat = Enum.Material

----------------------------------------------------------------------
-- Layout (+Z is south: the door; Petalina faces it)
----------------------------------------------------------------------
-- (every arena has its own spot, 2600 studs apart: see the handoff notes)
local CENTER = V3(5200, 0, 0)
local FIGHT_R = GardenPlan.Edge -- the invisible wall stands this far out
local HALF = GardenPlan.Walls -- the glass walls stand this far out each way
local PATH_HALF = GardenPlan.PathHalf
local BED_UP = GardenPlan.BedUp
local EAVE = 25 -- how high the glass walls go
local RIDGE = 50 -- how high the roof's ridge is
local BAY = 12 -- the glass walls' panes are this wide
local DOOR_HALF = 6 -- half the doorway's width
local DOOR_H = 12 -- how tall the doors are
local SPAWN_Z = 61 -- where you arrive

----------------------------------------------------------------------
-- Palette (the game's 32 colours)
----------------------------------------------------------------------
local PAVE = RGB(234, 212, 170)
local PAVE_DARK = RGB(194, 133, 105)
local SOIL = RGB(115, 62, 57)
local SOIL_DARK = RGB(62, 39, 49)
local BRICK = RGB(190, 74, 47)
local BRICK_DARK = RGB(162, 38, 51)
local GLASS = RGB(192, 203, 220)
local FRAME = RGB(255, 255, 255)
local GRASS = RGB(99, 199, 77)
local GRASS_DARK = RGB(62, 137, 72)
local GRASS_DEEP = RGB(38, 92, 66)
local WOOD = RGB(184, 111, 80)
local WOOD_LIGHT = RGB(228, 166, 114)
local BARK = RGB(115, 62, 57)
local CLAY = RGB(215, 118, 67)
local STONE = RGB(139, 155, 180)
local STONE_DARK = RGB(90, 105, 136)
local WATER = RGB(0, 153, 219)
local WHITE = RGB(255, 255, 255)
local INK = RGB(24, 20, 37)
local RED = RGB(228, 59, 68)
local ORANGE = RGB(247, 118, 34)
local GOLD = RGB(254, 174, 52)
local YELLOW = RGB(254, 231, 97)
local PINK = RGB(246, 117, 122)
local MAGENTA = RGB(181, 80, 136)
local PURPLE = RGB(104, 56, 108)
local SKY = RGB(44, 232, 245)
local BLOOMS = { RED, ORANGE, YELLOW, PINK, MAGENTA, PURPLE, WHITE, SKY }

----------------------------------------------------------------------
-- Helpers (the same kinds of little builders as the other floors')
----------------------------------------------------------------------
local seed = 20261101
local function rnd()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
local function between(a, b)
	return a + (b - a) * rnd()
end
local function pick(list)
	return list[math.floor(rnd() * #list) + 1]
end

local m -- the arena model, set by Build()

-- small decoration: no collisions, no raycasts, no shadow
local DECOR = { CanCollide = false, CanQuery = false, CastShadow = false }
-- big scenery nobody can reach: no collisions or raycasts, but it does shade
local SCENERY = { CanCollide = false, CanQuery = false }
-- the glass: see-through, and it doesn't shade the garden
local GLASSY = { Transparency = 0.62, Material = Mat.Glass, CastShadow = false }

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

-- a block stretched from a to b (a beam, a chain, a stem), `w` thick
local function beam(name, a, b, w, color, extra, parent)
	local len = (b - a).Magnitude
	return part(name, V3(w, w, math.max(len, 0.05)), CFrame.lookAt((a + b) / 2, b), color, extra, parent)
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
-- angle 0 is south (+Z, the door); pi/2 is east
local function onRing(r, a, y)
	return CENTER + V3(math.sin(a) * r, y or 0, math.cos(a) * r)
end
-- a frame at `p` whose front (-Z) faces the middle of the garden
local function facingCentre(p)
	local flat = V3(CENTER.X, p.Y, CENTER.Z)
	if (flat - p).Magnitude < 0.01 then
		return CFrame.new(p)
	end
	return CFrame.lookAt(p, flat)
end
local function wrap(a)
	return (a + math.pi) % (math.pi * 2) - math.pi
end

-- how wide (in angle) the way out to the door is, at the garden's edge
local GAP_ANGLE = math.asin((PATH_HALF + 1) / FIGHT_R)

-- the four quarters' mirror signs, for the flower beds
local QUARTERS = { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }

----------------------------------------------------------------------
-- The floor: the paving you fight on, her mound, the raised flower beds
----------------------------------------------------------------------
local function buildFloor()
	-- THE PAVING: one solid slab under the whole greenhouse, top at exactly
	-- y = 0. The paths are simply the paving between the beds.
	part("GardenFloor", V3(HALF * 2 + 2, 4, HALF * 2 + 2), CFrame.new(at(0, -2, 0)), PAVE)
	-- darker paving stones set in a ring round the outside path's inner edge
	-- and along the straight paths' edges: a hair up, and nothing touches them
	for k = 0, 47 do
		local a = (k + 0.5) / 48 * math.pi * 2
		local p = onRing(GardenPlan.Outer + 1.2, a, 0.03)
		part("PathKerb", V3(2 * (GardenPlan.Outer + 1.2) * math.tan(math.pi / 48) - 0.3, 0.1, 1.2), facingCentre(p), PAVE_DARK, DECOR)
	end
	-- HER MOUND: a low mound of dark soil in the middle, roots creeping out
	cylinder("RootMound", 3, GardenPlan.Mound * 2, CFrame.new(at(0, 0.8 - 1.5, 0)), SOIL_DARK)
	cylinder("RootMoundTop", 2, GardenPlan.Mound * 2 - 3, CFrame.new(at(0, 1.1 - 1, 0)), SOIL)
	for k = 0, 7 do
		local a = (k + 0.3) / 8 * math.pi * 2 + between(-0.15, 0.15)
		local r0, r1 = between(1.5, 2.5), GardenPlan.Mound + between(1.5, 4)
		beam("Root", onRing(r0, a, 1.2), onRing(r1, a + between(-0.2, 0.2), 0.25), between(0.9, 1.4), BARK, DECOR)
	end
end

-- THE FLOWER BEDS: raised soil, built from strips so their curved edges
-- step like pixels (GardenPlan.bedStrips - the same strips her thorns hurt
-- on). Tulips, daisies and little bushes grow in them; round 2's brambles
-- are hidden in the soil, waiting.
local function flower(p)
	local kind = rnd()
	if kind < 0.55 then
		-- a tulip: a stem and a bloom
		local h = between(1.2, 2)
		part("FlowerStem", V3(0.3, h, 0.3), CFrame.new(p + V3(0, h / 2, 0)), GRASS_DARK, DECOR)
		part("FlowerLeaf", V3(0.9, 0.2, 0.4), CFrame.new(p + V3(0.3, h * 0.35, 0)) * CFrame.Angles(0, rnd() * 3, 0.4), GRASS, DECOR)
		part("FlowerBloom", V3(0.9, 0.9, 0.9), CFrame.new(p + V3(0, h + 0.3, 0)) * CFrame.Angles(0, rnd() * 3, 0), pick(BLOOMS), DECOR)
	elseif kind < 0.8 then
		-- a daisy: white petals round a yellow middle
		local h = between(0.8, 1.4)
		part("FlowerStem", V3(0.25, h, 0.25), CFrame.new(p + V3(0, h / 2, 0)), GRASS_DARK, DECOR)
		part("DaisyPetals", V3(1.3, 0.2, 1.3), CFrame.new(p + V3(0, h, 0)) * CFrame.Angles(0, rnd() * 3, 0), WHITE, DECOR)
		part("DaisyMiddle", V3(0.5, 0.3, 0.5), CFrame.new(p + V3(0, h + 0.1, 0)), YELLOW, DECOR)
	else
		-- a little round bush
		local s = between(1.4, 2.2)
		part("BedBush", V3(s, s * 0.7, s), CFrame.new(p + V3(0, s * 0.3, 0)) * CFrame.Angles(0, rnd() * 3, 0), pick({ GRASS, GRASS_DARK }), DECOR)
	end
end

-- one bramble clump for round 2, hidden in the soil. `r` = how far from her
-- (the thorns creep outward from her mound)
local SINK = 4.5
local function thornClump(p, r)
	local clump = Instance.new("Model")
	clump.Name = "ThornClump"
	local base = CFrame.new(p - V3(0, SINK, 0)) * CFrame.Angles(0, rnd() * math.pi * 2, 0)
	local stems = math.floor(between(3, 5))
	local first
	for k = 1, stems do
		local a = k / stems * math.pi * 2
		local h = between(2.2, 3.4)
		local lean = between(0.3, 0.6)
		local cf = base * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 0.6) * CFrame.Angles(lean, 0, 0) * CFrame.new(0, h / 2, 0)
		local stem = part("Bramble", V3(0.55, h, 0.55), cf, (k % 2 == 0) and PURPLE or SOIL_DARK, DECOR, clump)
		first = first or stem
		-- sharp red thorns sticking out of it
		part("Thorn", V3(0.3, 0.3, 0.9), cf * CFrame.new(0, h * 0.15, -0.4), RED, DECOR, clump)
		part("Thorn", V3(0.9, 0.3, 0.3), cf * CFrame.new(0.4, -h * 0.2, 0), RED, DECOR, clump)
	end
	clump.PrimaryPart = first
	clump:SetAttribute("Floor", 8)
	clump:SetAttribute("Up", SINK) -- how far up it grows
	-- when it grows, after she turns evil: nearest her first
	clump:SetAttribute("Delay", 0.15 + math.clamp((r - GardenPlan.Inner) / (GardenPlan.Outer - GardenPlan.Inner), 0, 1) * 1.4 + rnd() * 0.15)
	CollectionService:AddTag(clump, "GardenThorn")
	clump.Parent = m
	return clump
end

local function buildBeds()
	local strips = GardenPlan.bedStrips()
	for _, q in ipairs(QUARTERS) do
		local sx, sz = q[1], q[2]
		for _, s in ipairs(strips) do
			local w, d = s.x1 - s.x0, s.z1 - s.z0
			local cx, cz = sx * (s.x0 + s.x1) / 2, sz * (s.z0 + s.z1) / 2
			-- the soil: its top BED_UP above the paving, mostly sunk into it
			part("FlowerBed", V3(w, 1.4, d), CFrame.new(at(cx, BED_UP - 0.7, cz)), SOIL)
		end
	end
	-- flowers and brambles on a grid over the beds (each only where there's
	-- bed under it, a little way in from the edge)
	local function onBed(dx, dz, margin)
		for _, ox in ipairs({ -margin, 0, margin }) do
			for _, oz in ipairs({ -margin, 0, margin }) do
				if GardenPlan.safe(dx + ox, dz + oz) then
					return false
				end
			end
		end
		return true
	end
	local n = 0
	for gx = -52, 52, 4.2 do
		for gz = -52, 52, 4.2 do
			local dx, dz = gx + between(-1.2, 1.2), gz + between(-1.2, 1.2)
			if onBed(dx, dz, 0.8) and rnd() < 0.62 then
				flower(at(dx, BED_UP, dz))
			end
		end
	end
	for gx = -52, 52, 6.4 do
		for gz = -52, 52, 6.4 do
			local dx, dz = gx + between(-1.5, 1.5), gz + between(-1.5, 1.5)
			if onBed(dx, dz, 1.4) then
				n = n + 1
				thornClump(at(dx, BED_UP, dz), math.sqrt(dx * dx + dz * dz))
			end
		end
	end
	return n
end

----------------------------------------------------------------------
-- The greenhouse: brick base, glass walls in white frames, the glass roof
----------------------------------------------------------------------
-- one straight wall, from corner a to corner b (each on the floor), with
-- a doorway in the middle if `door`
local function glassWall(a, b, door)
	local along = (b - a).Unit
	local len = (b - a).Magnitude
	local out = V3(along.Z, 0, -along.X) -- (not needed for the shape: a plain side)
	local _ = out
	local function spot(t, y)
		return a + along * t + V3(0, y, 0)
	end
	local function cfAt(t, y)
		local p = spot(t, y)
		return CFrame.lookAt(p, p + along)
	end
	local mid = len / 2
	-- the brick base (with a gap for the doorway)
	local pieces = door and { { 0, mid - DOOR_HALF }, { mid + DOOR_HALF, len } } or { { 0, len } }
	for _, pc in ipairs(pieces) do
		local l = pc[2] - pc[1]
		part("BrickBase", V3(1.6, 3.2, l), cfAt((pc[1] + pc[2]) / 2, 1.6), BRICK)
		part("BrickCap", V3(2, 0.5, l), cfAt((pc[1] + pc[2]) / 2, 3.45), BRICK_DARK, SCENERY)
	end
	-- white posts, a pane of glass between each pair
	local bays = math.floor(len / BAY + 0.5)
	local bay = len / bays
	for i = 0, bays do
		part("FramePost", V3(0.9, EAVE, 0.9), cfAt(i * bay, EAVE / 2), FRAME, SCENERY)
	end
	for i = 0, bays - 1 do
		local t = (i + 0.5) * bay
		local isDoor = door and math.abs(t - mid) < bay / 2
		if isDoor then
			-- the doorway: glass over the door
			part("Transom", V3(0.4, EAVE - DOOR_H - 0.6, bay - 0.9), cfAt(t, (DOOR_H + EAVE) / 2 + 0.3), GLASS, merge(GLASSY, { CanCollide = true }))
		else
			part("WallPane", V3(0.4, EAVE - 3.7, bay - 0.9), cfAt(t, (3.7 + EAVE) / 2), GLASS, merge(GLASSY, { CanCollide = true }))
		end
	end
	-- white rails along it
	for _, y in ipairs({ 3.7, 14.5 }) do
		part("FrameRail", V3(0.7, 0.6, len), cfAt(mid, y), FRAME, SCENERY)
	end
	part("EaveBeam", V3(1.4, 1.2, len + 1.4), cfAt(mid, EAVE), FRAME, SCENERY)
end

local function buildGlasshouse()
	local c = {
		at(-HALF, 0, HALF), at(HALF, 0, HALF), at(HALF, 0, -HALF), at(-HALF, 0, -HALF),
	}
	-- (the south wall - the door's - runs west to east)
	glassWall(c[1], c[2], true)
	glassWall(c[2], c[3], false)
	glassWall(c[3], c[4], false)
	glassWall(c[4], c[1], false)

	-- THE ROOF: two slopes of glass up to a ridge running east-west
	local run = math.sqrt(HALF * HALF + (RIDGE - EAVE) ^ 2)
	for _, sz in ipairs({ 1, -1 }) do
		local eave = sz * HALF
		local down = V3(0, EAVE - RIDGE, eave).Unit
		local bays = math.floor(HALF * 2 / BAY + 0.5)
		local bay = HALF * 2 / bays
		for i = 0, bays - 1 do
			local x = -HALF + (i + 0.5) * bay
			local mid = at(x, (EAVE + RIDGE) / 2, eave / 2)
			part("RoofPane", V3(bay - 0.9, 0.4, run - 0.8), CFrame.lookAt(mid, mid + down), GLASS, merge(GLASSY, { CanCollide = true }))
		end
		for i = 0, bays do
			local x = -HALF + i * bay
			beam("Rafter", at(x, RIDGE + 0.4, 0), at(x, EAVE + 0.4, eave), 0.8, FRAME, SCENERY)
		end
		for _, k in ipairs({ 1 / 3, 2 / 3 }) do
			local y, z = RIDGE + (EAVE - RIDGE) * k + 0.4, eave * k
			beam("Purlin", at(-HALF, y, z), at(HALF, y, z), 0.6, FRAME, SCENERY)
		end
	end
	beam("RidgeBeam", at(-HALF - 0.7, RIDGE + 0.5, 0), at(HALF + 0.7, RIDGE + 0.5, 0), 1.4, FRAME, SCENERY)
	-- the gable ends: stepped glass (like pixels), white trim on each step
	local steps = 5
	local stepH = (RIDGE - EAVE) / steps
	for _, sx in ipairs({ -1, 1 }) do
		for i = 0, steps - 2 do
			local halfW = HALF * (1 - (i + 1) / steps)
			local y = EAVE + (i + 0.5) * stepH
			part("GablePane", V3(0.4, stepH - 0.3, halfW * 2), CFrame.new(at(sx * HALF, y, 0)), GLASS, merge(GLASSY, { CanCollide = true }))
			part("GableTrim", V3(0.8, 0.5, halfW * 2 + 0.8), CFrame.new(at(sx * HALF, EAVE + (i + 1) * stepH, 0)), FRAME, SCENERY)
		end
		part("GablePost", V3(0.8, RIDGE - EAVE, 0.8), CFrame.new(at(sx * HALF, (EAVE + RIDGE) / 2, 0)), FRAME, SCENERY)
	end
	-- a little glass lantern on the ridge, with a flower weathervane
	local lb = at(0, RIDGE + 0.8, 0)
	part("LanternBase", V3(22, 1, 12), CFrame.new(lb), FRAME, SCENERY)
	for _, sx in ipairs({ -1, 1 }) do
		part("LanternPane", V3(0.4, 5, 11), CFrame.new(lb + V3(sx * 10.5, 3, 0)), GLASS, merge(GLASSY, { CanCollide = true }))
	end
	for _, sz in ipairs({ -1, 1 }) do
		part("LanternPane", V3(20.2, 5, 0.4), CFrame.new(lb + V3(0, 3, sz * 5.5)), GLASS, merge(GLASSY, { CanCollide = true }))
	end
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			part("LanternPost", V3(0.8, 5, 0.8), CFrame.new(lb + V3(sx * 10.6, 3, sz * 5.6)), FRAME, SCENERY)
		end
	end
	part("LanternRoof", V3(23, 1.2, 13), CFrame.new(lb + V3(0, 6.1, 0)), FRAME, SCENERY)
	part("LanternRoofTop", V3(16, 1, 8), CFrame.new(lb + V3(0, 7.2, 0)), FRAME, SCENERY)
	part("VanePole", V3(0.4, 5, 0.4), CFrame.new(lb + V3(0, 10.2, 0)), INK, SCENERY)
	for k = 0, 4 do
		local a = k / 5 * math.pi * 2
		part("VanePetal", V3(0.3, 1.2, 0.8), CFrame.new(lb + V3(0, 12.8, 0)) * CFrame.Angles(a, 0, 0) * CFrame.new(0, 0.8, 0), PINK, SCENERY)
	end
	part("VaneMiddle", V3(0.5, 0.7, 0.7), CFrame.new(lb + V3(0, 12.8, 0)), YELLOW, SCENERY)

	-- sunbeams slanting down through the glass (faint, and they don't touch
	-- each other or the glass)
	local sun = V3(0.35, -1, 0.25).Unit
	for _, spot in ipairs({ V3(-44, 0, -30), V3(40, 0, -42), V3(-30, 0, 40), V3(46, 0, 28) }) do
		local foot = at(spot.X, 0, spot.Z)
		local top = foot - sun * 34
		local shaft = beam("Sunbeam", top, foot, 5, YELLOW, merge(DECOR, { Transparency = 0.9, Material = Mat.Neon }))
		shaft.CastShadow = false
	end
end

----------------------------------------------------------------------
-- Inside: the corners, hanging baskets, butterflies
----------------------------------------------------------------------
local function pot(p, s, plant)
	part("PotBody", V3(2.4 * s, 2 * s, 2.4 * s), CFrame.new(p + V3(0, s, 0)), CLAY, SCENERY)
	part("PotRim", V3(2.8 * s, 0.5 * s, 2.8 * s), CFrame.new(p + V3(0, 2 * s, 0)), BRICK, SCENERY)
	part("PotSoil", V3(2.2 * s, 0.2, 2.2 * s), CFrame.new(p + V3(0, 2.15 * s, 0)), SOIL_DARK, DECOR)
	if plant == "palm" then
		local top = p + V3(0, 2 * s + 7 * s, 0)
		beam("PalmTrunk", p + V3(0, 2 * s, 0), top, 0.8 * s, WOOD, SCENERY)
		for k = 0, 6 do
			local a = k / 7 * math.pi * 2
			local tip = top + V3(math.cos(a) * 4 * s, -1.6 * s, math.sin(a) * 4 * s)
			beam("PalmFrond", top, tip, 0.9 * s, (k % 2 == 0) and GRASS or GRASS_DARK, DECOR)
		end
	elseif plant == "fern" then
		for k = 0, 5 do
			local a = k / 6 * math.pi * 2 + 0.3
			local base = p + V3(0, 2.2 * s, 0)
			beam("FernLeaf", base, base + V3(math.cos(a) * 2.2 * s, 1.4 * s, math.sin(a) * 2.2 * s), 0.6 * s, GRASS_DARK, DECOR)
		end
	elseif plant == "flowers" then
		for k = 1, 4 do
			local o = V3(between(-0.7, 0.7) * s, 2.4 * s + between(0, 0.6), between(-0.7, 0.7) * s)
			part("PotBloom", V3(0.8, 0.8, 0.8), CFrame.new(p + o), pick(BLOOMS), DECOR)
		end
	end
end

local function buildInside()
	-- the corners (outside the round garden): potted palms, stacks of pots,
	-- a potting table, watering cans, a wheelbarrow, sacks of compost
	for _, q in ipairs(QUARTERS) do
		local sx, sz = q[1], q[2]
		pot(at(sx * 62, 0, sz * 62), 1.6, "palm")
		pot(at(sx * 54, 0, sz * 64), 1, "fern")
		pot(at(sx * 64, 0, sz * 54), 1, "flowers")
		pot(at(sx * 58, 0, sz * 67), 0.8, "flowers")
		pot(at(sx * 67, 0, sz * 58), 0.8, "fern")
		-- a stack of empty pots
		for k = 0, 2 do
			part("StackedPot", V3(1.6 - k * 0.1, 0.9, 1.6 - k * 0.1), CFrame.new(at(sx * 68, 0.45 + k * 0.7, sz * 66)), CLAY, SCENERY)
		end
	end
	-- a potting table in the north-west corner
	local tb = at(-60, 0, -52)
	part("TableTop", V3(10, 0.6, 4), CFrame.new(tb + V3(0, 3.4, 0)), WOOD_LIGHT, SCENERY)
	for _, sx in ipairs({ -4.4, 4.4 }) do
		for _, sz in ipairs({ -1.6, 1.6 }) do
			part("TableLeg", V3(0.5, 3.1, 0.5), CFrame.new(tb + V3(sx, 1.55, sz)), WOOD, SCENERY)
		end
	end
	for k = -2, 2 do
		part("SeedTray", V3(1.6, 0.4, 2.4), CFrame.new(tb + V3(k * 1.9, 3.9, 0)), SOIL, DECOR)
		part("Seedling", V3(0.3, 0.6, 0.3), CFrame.new(tb + V3(k * 1.9, 4.3, 0.4)), GRASS, DECOR)
	end
	-- watering cans
	for _, spot in ipairs({ at(56, 0, -63), at(-63, 0, 50) }) do
		part("CanBody", V3(1.6, 1.6, 2.2), CFrame.new(spot + V3(0, 0.8, 0)), SKY, SCENERY)
		beam("CanSpout", spot + V3(0, 1, -1), spot + V3(0, 2.2, -2.4), 0.3, SKY, DECOR)
		part("CanHandle", V3(0.3, 0.9, 1.4), CFrame.new(spot + V3(0, 2, 0.4)), SKY, DECOR)
	end
	-- a wheelbarrow of compost in the south-east corner
	local wb = at(58, 0, 60)
	part("BarrowTub", V3(3, 1.4, 4), CFrame.new(wb + V3(0, 1.6, 0)), RED, SCENERY)
	part("BarrowSoil", V3(2.6, 0.3, 3.4), CFrame.new(wb + V3(0, 2.3, 0)), SOIL_DARK, DECOR)
	cylinder("BarrowWheel", 0.5, 1.6, CFrame.new(wb + V3(0, 0.8, -2.6)) * CFrame.Angles(0, 0, math.pi / 2), INK, SCENERY)
	for _, sx in ipairs({ -1, 1 }) do
		beam("BarrowHandle", wb + V3(sx * 1.2, 2, 1.8), wb + V3(sx * 1.4, 2.2, 4.6), 0.3, WOOD, DECOR)
	end
	-- sacks of compost
	for k = 0, 2 do
		part("CompostSack", V3(2.4, 1.2, 1.6), CFrame.new(at(-58 + k * 2.6, 0.6, 62)) * CFrame.Angles(0, between(-0.3, 0.3), 0), WOOD_LIGHT, SCENERY)
	end
	-- benches along the east and west walls
	for _, sx in ipairs({ -1, 1 }) do
		local bp = at(sx * 69, 0, 20)
		part("BenchSeat", V3(2, 0.4, 7), CFrame.new(bp + V3(0, 1.8, 0)), WOOD_LIGHT, SCENERY)
		part("BenchBack", V3(0.4, 1.6, 7), CFrame.new(bp + V3(sx * 0.9, 2.8, 0)), WOOD_LIGHT, SCENERY)
		for _, sz in ipairs({ -3, 3 }) do
			part("BenchLeg", V3(1.6, 1.6, 0.4), CFrame.new(bp + V3(0, 0.8, sz)), INK, SCENERY)
		end
	end
	-- baskets of flowers hanging from the roof in the corners (out of the
	-- way of your camera over the garden)
	for k = 0, 7 do
		local q = QUARTERS[math.floor(k / 2) + 1]
		local off = (k % 2 == 0) and V3(52, 0, 64) or V3(64, 0, 52)
		local p = at(q[1] * off.X, 19, q[2] * off.Z)
		local roofY = EAVE + (RIDGE - EAVE) * (1 - math.abs(p.Z - CENTER.Z) / HALF)
		beam("BasketChain", p + V3(0, 1, 0), V3(p.X, CENTER.Y + roofY - 0.3, p.Z), 0.2, INK, DECOR)
		part("Basket", V3(2.4, 1.2, 2.4), CFrame.new(p), WOOD, DECOR)
		for j = 0, 3 do
			local o = V3(math.cos(j * 1.6) * 0.8, 0.9, math.sin(j * 1.6) * 0.8)
			part("BasketBloom", V3(0.8, 0.8, 0.8), CFrame.new(p + o), pick(BLOOMS), DECOR)
		end
		for j = 0, 2 do
			local o = V3(math.cos(j * 2.1) * 1.1, -0.6 - j * 0.4, math.sin(j * 2.1) * 1.1)
			part("BasketTrail", V3(0.4, 1.4, 0.4), CFrame.new(p + o), GRASS, DECOR)
		end
	end
	-- butterflies (her body file makes them flit about)
	for k = 1, 8 do
		local fly = Instance.new("Model")
		fly.Name = "Butterfly"
		local a = k / 8 * math.pi * 2
		local p = onRing(between(24, 48), a, between(7, 13))
		local col = pick({ YELLOW, SKY, ORANGE, WHITE, MAGENTA })
		local body = part("ButterflyBody", V3(0.25, 0.25, 0.9), CFrame.new(p), INK, DECOR, fly)
		part("ButterflyWing", V3(0.9, 0.1, 0.8), CFrame.new(p + V3(-0.55, 0, 0)), col, DECOR, fly)
		part("ButterflyWing", V3(0.9, 0.1, 0.8), CFrame.new(p + V3(0.55, 0, 0)), col, DECOR, fly)
		fly.PrimaryPart = body
		fly:SetAttribute("Floor", 8)
		fly:SetAttribute("Index", k)
		CollectionService:AddTag(fly, "GardenButterfly")
		fly.Parent = m
	end
end

----------------------------------------------------------------------
-- Outside: the lawn, the way to the door, hedges, trees, the fence
----------------------------------------------------------------------
local function tree(p, s)
	part("TreeTrunk", V3(1.4 * s, 6 * s, 1.4 * s), CFrame.new(p + V3(0, 3 * s, 0)), WOOD, SCENERY)
	part("TreeLeaves", V3(7 * s, 4 * s, 7 * s), CFrame.new(p + V3(0, 7.5 * s, 0)), GRASS_DARK, SCENERY)
	part("TreeLeavesTop", V3(4.6 * s, 3 * s, 4.6 * s), CFrame.new(p + V3(0, 10.5 * s, 0)), GRASS, SCENERY)
end

local function buildOutside()
	-- the lawn all round (a hair under the greenhouse's floor)
	cylinder("Lawn", 4, 760, CFrame.new(at(0, -2.3, 0)), GRASS)
	-- a gravel path from the door out to the south
	part("OutsidePath", V3(DOOR_HALF * 2 + 4, 4, 90), CFrame.new(at(0, -2.2, HALF + 45)), PAVE)
	-- hedges along the greenhouse's sides, with gaps, and topiary balls
	for _, sx in ipairs({ -1, 1 }) do
		part("Hedge", V3(3, 3, 110), CFrame.new(at(sx * (HALF + 8), 1.5 - 0.3, 0)), GRASS_DEEP, SCENERY)
		for _, sz in ipairs({ -60, 60 }) do
			part("Topiary", V3(4, 4, 4), CFrame.new(at(sx * (HALF + 8), 4.6, sz)), GRASS_DARK, SCENERY)
			part("TopiaryTop", V3(2.6, 2.6, 2.6), CFrame.new(at(sx * (HALF + 8), 7.6, sz)), GRASS, SCENERY)
		end
	end
	part("Hedge", V3(110, 3, 3), CFrame.new(at(0, 1.2, -(HALF + 8))), GRASS_DEEP, SCENERY)
	-- flower borders either side of the way in
	for _, sx in ipairs({ -1, 1 }) do
		part("Border", V3(3, 0.6, 60), CFrame.new(at(sx * (DOOR_HALF + 5), -0.1, HALF + 38)), SOIL, SCENERY)
		for k = 0, 11 do
			flower(at(sx * (DOOR_HALF + 5) + between(-0.8, 0.8), 0.2, HALF + 10 + k * 5))
		end
	end
	-- trees round the garden
	for k = 0, 17 do
		local a = (k + 0.5) / 18 * math.pi * 2
		if math.abs(wrap(a)) > 0.25 then
			local r = between(110, 150)
			tree(onRing(r, a, -0.3), between(1.2, 1.8))
		end
	end
	-- a white picket fence round it all (gap at the south for the path)
	local N = 44
	for k = 0, N - 1 do
		local a = (k + 0.5) / N * math.pi * 2
		if math.abs(wrap(a)) > 0.12 then
			local p = onRing(200, a, 1.2)
			local len = 2 * 200 * math.tan(math.pi / N)
			part("FenceRail", V3(len, 0.4, 0.3), facingCentre(p + V3(0, 0.6, 0)), WHITE, SCENERY)
			part("FenceRail", V3(len, 0.4, 0.3), facingCentre(p - V3(0, 0.4, 0)), WHITE, SCENERY)
			for j = -2, 2 do
				local q = facingCentre(p) * CFrame.new(j * len / 5, 0.3, 0)
				part("Picket", V3(0.5, 3, 0.3), q, WHITE, SCENERY)
			end
		end
	end
	-- a little pond with a stone rim, west of the door
	local pond = at(-40, 0, HALF + 34)
	cylinder("PondRim", 0.6, 18, CFrame.new(pond + V3(0, 0, 0)), STONE, SCENERY)
	cylinder("PondWater", 0.6, 15, CFrame.new(pond + V3(0, 0.1, 0)), WATER, SCENERY)
	cylinder("LilyPad", 0.2, 2.4, CFrame.new(pond + V3(2, 0.45, -1.5)), GRASS, DECOR)
	cylinder("LilyPad", 0.2, 2, CFrame.new(pond + V3(-3, 0.45, 2)), GRASS, DECOR)
	part("LilyBloom", V3(0.8, 0.6, 0.8), CFrame.new(pond + V3(2, 0.8, -1.5)), PINK, DECOR)
	-- far hills
	for k = 0, 11 do
		local a = (k + 0.5) / 12 * math.pi * 2
		local r = between(300, 360)
		local h = between(30, 60)
		part("Hill", V3(between(90, 140), h, between(70, 110)), facingCentre(onRing(r, a, h / 2 - 6)), pick({ GRASS_DARK, GRASS_DEEP }), SCENERY)
	end
end

----------------------------------------------------------------------
-- The door, the walls round the fight, and the marks the boss will use
----------------------------------------------------------------------
local function buildDoor()
	local z = HALF - 0.8
	-- two glass doors in white frames (closed: the way out is the "Leave?" check)
	local leaves = {}
	for _, sx in ipairs({ -1, 1 }) do
		local c = at(sx * DOOR_HALF / 2, DOOR_H / 2, z)
		local leaf = part("DoorGlass", V3(DOOR_HALF - 0.6, DOOR_H - 0.6, 0.4), CFrame.new(c), GLASS, merge(GLASSY, { Transparency = 0.5 }))
		table.insert(leaves, leaf)
		part("DoorFrameSide", V3(0.5, DOOR_H, 0.6), CFrame.new(c + V3(-sx * (DOOR_HALF / 2 - 0.25), 0, 0)), FRAME, SCENERY)
		part("DoorFrameSide", V3(0.5, DOOR_H, 0.6), CFrame.new(c + V3(sx * (DOOR_HALF / 2 - 0.25), 0, 0)), FRAME, SCENERY)
		part("DoorRail", V3(DOOR_HALF, 0.5, 0.6), CFrame.new(c + V3(0, 0, 0)), FRAME, SCENERY)
		part("DoorHandle", V3(0.3, 1.2, 0.8), CFrame.new(c + V3(-sx * (DOOR_HALF / 2 - 1), 0.2, 0)), GOLD, DECOR)
	end
	part("DoorHead", V3(DOOR_HALF * 2 + 1, 0.8, 0.9), CFrame.new(at(0, DOOR_H + 0.1, z)), FRAME, SCENERY)
	part("DoorStep", V3(DOOR_HALF * 2 + 2, 0.3, 3), CFrame.new(at(0, 0.02, HALF + 1)), STONE_DARK, DECOR)
	-- the sign over the doors (inside, so you see it from the garden)
	local board = part("GardenSign", V3(20, 3, 0.5), CFrame.new(at(0, DOOR_H + 3, z - 0.8)) * CFrame.Angles(0, math.pi, 0), WOOD_LIGHT, SCENERY)
	signText(board, "THE GLASSHOUSE GARDEN", MAGENTA, Enum.NormalId.Front)
	for _, sx in ipairs({ -1, 1 }) do
		part("SignFlower", V3(1.2, 1.2, 0.5), CFrame.new(at(sx * 10.8, DOOR_H + 3, z - 1.1)), PINK, DECOR)
		part("SignFlowerMiddle", V3(0.5, 0.5, 0.3), CFrame.new(at(sx * 10.8, DOOR_H + 3, z - 1.4)), YELLOW, DECOR)
	end
	-- and outside
	local outside = part("GardenSignOut", V3(20, 3, 0.5), CFrame.new(at(0, DOOR_H + 3, z + 0.8)), WOOD_LIGHT, SCENERY)
	signText(outside, "THE GLASSHOUSE GARDEN", MAGENTA, Enum.NormalId.Back)
	-- the way out: the Leave prompt on the doors (switched off on screens)
	-- and the walk-up box in front of them
	local exit = Instance.new("ProximityPrompt")
	exit.ActionText = "Leave"
	exit.ObjectText = "Greenhouse Door"
	exit.HoldDuration = 0.4
	exit.MaxActivationDistance = 14
	exit.KeyboardKeyCode = Enum.KeyCode.E
	exit.GamepadKeyCode = Enum.KeyCode.ButtonX
	exit.RequiresLineOfSight = false
	exit.Parent = leaves[1]
	CollectionService:AddTag(exit, "ArenaExit")
	autoZone(CFrame.new(at(0, 4, z - 3.2)), V3(DOOR_HALF * 2, 8, 5), "Spire", "Leave")
	-- where you arrive: inside the doors, looking at her
	local arrive = anchorPart("ArenaSpawn", CFrame.lookAt(at(0, 3, SPAWN_Z), at(0, 3, 0)))
	CollectionService:AddTag(arrive, "ArenaSpawn")
end

local function wall(cf, size)
	local w = part("EdgeWall", size, cf, WHITE, { Transparency = 1, CanQuery = false, CastShadow = false })
	CollectionService:AddTag(w, "GardenEdgeWall")
	return w
end

local function buildBounds()
	local H = 60
	-- round the garden, in straight pieces (leaving the way to the door open)
	local N = 48
	local len = 2 * (FIGHT_R + 1) * math.tan(math.pi / N) + 0.6
	for k = 0, N - 1 do
		local a = (k + 0.5) / N * math.pi * 2
		if math.abs(wrap(a)) > GAP_ANGLE then
			local p = onRing(FIGHT_R + 1, a, H / 2)
			wall(facingCentre(p), V3(len, H, 2))
		end
	end
	-- the way to the door's sides
	local z0 = FIGHT_R * math.cos(GAP_ANGLE) - 2
	local z1 = HALF
	for _, sx in ipairs({ -1, 1 }) do
		wall(CFrame.new(at(sx * (PATH_HALF + 1), H / 2, (z0 + z1) / 2)), V3(2, H, z1 - z0))
	end
	-- Where Petalina grows: the middle of the garden, facing the door you come
	-- in by. BossService puts Petalina herself on this spot.
	local home = anchorPart("BossHome", CFrame.new(at(0, 0, 0)))
	home:SetAttribute("Floor", 8)
	home:SetAttribute("Facing", V3(0, 0, 1))
	CollectionService:AddTag(home, "BossHome")
end

----------------------------------------------------------------------
-- Public
----------------------------------------------------------------------
function GreenhouseBuilder.Build()
	local old = Workspace:FindFirstChild("GreenhouseArena")
	if old then
		old:Destroy()
	end
	m = Instance.new("Model")
	m.Name = "GreenhouseArena"
	seed = 20261101 -- (the same "random" every time it's built)

	-- each piece on its own, so one mistake can't leave the whole arena missing
	local pieces = {
		{ "Floor", buildFloor },
		{ "Flower beds", buildBeds },
		{ "Glasshouse", buildGlasshouse },
		{ "Inside", buildInside },
		{ "Outside", buildOutside },
		{ "Door", buildDoor },
		{ "Walls and markers", buildBounds },
	}
	local failed = 0
	for _, piece in ipairs(pieces) do
		local ok, err = pcall(piece[2])
		if not ok then
			failed = failed + 1
			warn("[GreenhouseBuilder] '" .. piece[1] .. "' failed to build: " .. tostring(err))
		end
	end

	m:SetAttribute("Floor", 8)
	m:SetAttribute("Center", CENTER)
	m:SetAttribute("FightRadius", FIGHT_R) -- how far out the invisible wall stands
	m.Parent = Workspace
	if failed == 0 then
		print("[GreenhouseBuilder] The Glasshouse Garden built OK")
	end
	return m
end

GreenhouseBuilder.Center = CENTER
GreenhouseBuilder.FightRadius = FIGHT_R

return GreenhouseBuilder
