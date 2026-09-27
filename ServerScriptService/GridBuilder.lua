--[[
	GridBuilder  (ModuleScript, parent: ServerScriptService, name: "GridBuilder")

	Builds the Spire's sixth floor: THE FINAL BEAT, Gridlock's arena - the
	last level.

	A square grid of dark tiles floating in a purple void, glowing lines
	between them (a neon slab just under the tiles shows through the gaps -
	the screens pulse it on the beat). Eight yellow JUMP PADS on it; high
	above, the CEILING GRID Gridlock hangs from in round 2, held up by four
	black pillars. You arrive on a short runway through a big portal (south).
	Round about, far off: giant black spikes, spinning saw blades, floating
	blocks, neon frames, chains, stars, and a red glow in the abyss far below.
	Everything is chunky and 8-bit, in the game's 32 colours.

	THE GRID: TILES x TILES tiles, SIZE studs each, round CENTER (the same
	sums as ReplicatedStorage/BeatGrid, which the fight uses to light tiles up
	and spike them). The pads are on BeatGrid.PADS' tiles.

	Everything the fight needs is marked for SpireService / BossService:
	  * "ArenaSpawn"   where you arrive: on the runway (in this model, Floor = 6)
	  * "ArenaExit"    the Leave prompt on the portal (switched off on your
	                   screen), plus a walk-up box (AutoOpenZone, Spire = "Leave")
	  * "BossHome"     the middle of the grid, Floor = 6, facing the runway
	  * "GridWall"     the invisible walls round the grid and the runway
	  * "JumpPad"      each pad (Floor = 6) - Bosses/Gridlock throws you up off it
	  * "GridUnder"    the neon under the tiles (the screens pulse it)
	  * "GridBackdrop" a model of the far-off scenery (the screens turn it upside
	                   down for the gravity flip); inside it "GridSaw" models spin
	                   and "GridSpin" frames turn
	  * the model itself carries Floor = 6, Center, Tiles, TileSize, Ceiling,
	    and the runway (RunwayA / RunwayB: two opposite corners)

	Main calls GridBuilder.Build() once at startup, after the speedway and
	before BossService (which parks Gridlock on his BossHome).
]]

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BeatGrid = require(ReplicatedStorage:WaitForChild("BeatGrid"))

local GridBuilder = {}

local V3 = Vector3.new
local RGB = Color3.fromRGB
local Mat = Enum.Material

----------------------------------------------------------------------
-- Layout (+Z is south: the runway and the portal)
----------------------------------------------------------------------
local CENTER = V3(2600, 0, -2600) -- well away from the lobby and the other floors
local TILES = 15 -- the grid is TILES x TILES tiles...
local SIZE = 8 -- ...each SIZE studs across (120 studs in all)
local HALF = TILES * SIZE / 2 -- (60: from the middle to the grid's edge)
local CEILING = 44 -- the ceiling grid, studs above the tiles
local RUN_W, RUN_L = 16, 20 -- the runway: wide, long (south of the grid)

----------------------------------------------------------------------
-- Palette (the game's 32 colours)
----------------------------------------------------------------------
local INK = RGB(24, 20, 37)
local NIGHT = RGB(38, 43, 68)
local NAVY = RGB(58, 68, 102)
local PURPLE = RGB(104, 56, 108)
local MAGENTA = RGB(181, 80, 136)
local HOT = RGB(255, 0, 68)
local ORANGE = RGB(247, 118, 34)
local YELLOW = RGB(254, 231, 97)
local GOLD = RGB(254, 174, 52)
local CYAN = RGB(44, 232, 245)
local GREEN = RGB(99, 199, 77)
local WHITE = RGB(255, 255, 255)

----------------------------------------------------------------------
-- Helpers (the same kinds of little builders as the other arenas')
----------------------------------------------------------------------
local seed = 20260929
local function rnd()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

local m -- the arena model, set by Build()

local DECOR = { CanCollide = false, CanQuery = false, CastShadow = false }
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

local NEON = { Material = Mat.Neon, CanCollide = false, CanQuery = false, CastShadow = false }

local function wedge(name, size, cf, color, extra, parent)
	local p = Instance.new("WedgePart")
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

-- Upright cylinder: `cf` is the centre, the axis points up
local function cylinder(name, height, d, cf, color, extra, parent)
	return part(name, V3(height, d, d), cf * CFrame.Angles(0, 0, math.pi / 2), color, merge(extra, { Shape = Enum.PartType.Cylinder }), parent)
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

local function pulse(p, speed, lo, hi)
	p:SetAttribute("PulseSpeed", speed)
	p:SetAttribute("PulseMin", lo)
	p:SetAttribute("PulseMax", hi)
	p:SetAttribute("Phase", rnd() * 360)
	CollectionService:AddTag(p, "Pulse")
end

local function at(x, y, z)
	return CENTER + V3(x, y, z)
end

-- words on a board (a SurfaceGui on its front face)
local function signText(board, text, color, face, bg)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignText"
	gui.Face = face or Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(board.Size.X * 40, board.Size.Y * 40)
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = bg and 0 or 1
	label.BackgroundColor3 = bg or INK
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

-- a block stretched from a to b (a neon edge, a chain link...)
local function beam(name, a, b, thick, color, extra, parent)
	local d = b - a
	local len = d.Magnitude
	if len < 0.01 then
		return nil
	end
	local up = (math.abs(d.Unit.Y) > 0.95) and V3(1, 0, 0) or V3(0, 1, 0)
	return part(name, V3(thick, thick, len), CFrame.lookAt((a + b) / 2, b, up), color, extra, parent)
end

----------------------------------------------------------------------
-- The grid: the tiles, the neon under them, the rim, the pads
----------------------------------------------------------------------
local function buildGrid()
	local g = BeatGrid.grid(at(0, 0, 0), TILES, SIZE)
	-- the tiles (a faint chessboard: the darker and the lighter), their tops at
	-- the grid's height
	for i = 0, TILES - 1 do
		for j = 0, TILES - 1 do
			local c = BeatGrid.tileCenter(g, i, j)
			part("Tile", V3(SIZE - 0.5, 1, SIZE - 0.5), CFrame.new(c + V3(0, -0.5, 0)), ((i + j) % 2 == 0) and INK or NIGHT)
		end
	end
	-- the neon just under them: it shows through every gap as a glowing line
	local under = part("GridUnder", V3(TILES * SIZE + 0.6, 0.5, TILES * SIZE + 0.6), CFrame.new(at(0, -0.55, 0)), PURPLE,
		{ Material = Mat.Neon, CanCollide = false, CanQuery = false, CastShadow = false })
	CollectionService:AddTag(under, "GridUnder")
	-- the floor under that (solid: nothing falls through a gap)
	part("GridBase", V3(TILES * SIZE + 1, 2, TILES * SIZE + 1), CFrame.new(at(0, -1.8, 0)), INK)
	-- the rim round the edge: a neon red line, then a black frame
	for _, s in ipairs({ -1, 1 }) do
		part("GridRim", V3(TILES * SIZE + 2, 0.5, 1), CFrame.new(at(0, 0.05, s * (HALF + 0.5))), HOT, NEON)
		part("GridRim", V3(1, 0.5, TILES * SIZE + 2), CFrame.new(at(s * (HALF + 0.5), 0.05, 0)), HOT, NEON)
		part("GridFrame", V3(TILES * SIZE + 12, 3, 5), CFrame.new(at(0, -1.4, s * (HALF + 3.5))), INK)
		part("GridFrame", V3(5, 3, TILES * SIZE + 12), CFrame.new(at(s * (HALF + 3.5), -1.4, 0)), INK)
		part("GridFrameEdge", V3(TILES * SIZE + 12, 0.4, 0.5), CFrame.new(at(0, -2.9, s * (HALF + 6))), MAGENTA, NEON)
		part("GridFrameEdge", V3(0.5, 0.4, TILES * SIZE + 12), CFrame.new(at(s * (HALF + 6), -2.9, 0)), MAGENTA, NEON)
	end
	-- under the grid: a stepped black underside, lit from below
	for k = 1, 3 do
		local w = TILES * SIZE + 8 - k * 22
		part("GridUnderside", V3(w, 6, w), CFrame.new(at(0, -3 - k * 6, 0)), (k % 2 == 0) and NIGHT or INK, SCENERY)
	end
	part("GridCore", V3(10, 10, 10), CFrame.new(at(0, -26, 0)) * CFrame.Angles(0, math.rad(45), 0), HOT, NEON)
	-- the jump pads
	for k, pd in ipairs(BeatGrid.pads(g)) do
		local c = BeatGrid.tileCenter(g, pd[1], pd[2])
		local pad = Instance.new("Model")
		pad.Name = "JumpPad"
		pad.Parent = m
		local plate = cylinder("PadPlate", 0.5, BeatGrid.PAD_RADIUS * 2, CFrame.new(c + V3(0, 0.25, 0)), YELLOW, merge(DECOR, { Material = Mat.Neon }), pad)
		cylinder("PadRing", 0.4, BeatGrid.PAD_RADIUS * 2 + 1.2, CFrame.new(c + V3(0, 0.12, 0)), GOLD, DECOR, pad)
		-- an arrow pointing up (two blocks leaning together, over a stem)
		part("PadArrow", V3(0.8, 2, 0.8), CFrame.new(c + V3(0, 1.4, 0)), WHITE, merge(DECOR, { Material = Mat.Neon }), pad)
		for _, s in ipairs({ -1, 1 }) do
			part("PadArrow", V3(0.7, 1.4, 0.7), CFrame.new(c + V3(s * 0.45, 2.3, 0)) * CFrame.Angles(0, 0, s * 0.7), WHITE, merge(DECOR, { Material = Mat.Neon }), pad)
		end
		pad.PrimaryPart = plate
		pad:SetAttribute("Floor", 6)
		pad:SetAttribute("Tile", V3(pd[1], 0, pd[2]))
		pad:SetAttribute("Index", k)
		CollectionService:AddTag(pad, "JumpPad")
	end
end

----------------------------------------------------------------------
-- The ceiling grid, up high, on four black pillars
----------------------------------------------------------------------
local function buildCeiling()
	local y = CEILING
	local frame = HALF + 2
	for _, s in ipairs({ -1, 1 }) do
		part("CeilingEdge", V3(frame * 2 + 2, 1.4, 1.4), CFrame.new(at(0, y, s * frame)), MAGENTA, NEON)
		part("CeilingEdge", V3(1.4, 1.4, frame * 2 + 2), CFrame.new(at(s * frame, y, 0)), MAGENTA, NEON)
	end
	-- its lines: over every third line between the tiles (thin, so you can
	-- see up through it)
	for k = 1, math.floor(TILES / 3) - 1 do
		local x = -HALF + k * 3 * SIZE
		part("CeilingLine", V3(0.6, 0.6, frame * 2), CFrame.new(at(x, y, 0)), PURPLE, merge(NEON, { Transparency = 0.25 }))
		part("CeilingLine", V3(frame * 2, 0.6, 0.6), CFrame.new(at(0, y, x)), PURPLE, merge(NEON, { Transparency = 0.25 }))
	end
	-- the pillars at the corners (black, neon edges), from the abyss up past the ceiling
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local c = at(sx * (HALF + 9), 0, sz * (HALF + 9))
			local h = CEILING + 36
			part("CornerPillar", V3(8, h, 8), CFrame.new(c + V3(0, h / 2 - 30, 0)), INK, SCENERY)
			for _, ex in ipairs({ -1, 1 }) do
				for _, ez in ipairs({ -1, 1 }) do
					part("PillarEdge", V3(0.6, h, 0.6), CFrame.new(c + V3(ex * 4, h / 2 - 30, ez * 4)), HOT, NEON)
				end
			end
			-- a glowing cap, and the arm out to the ceiling frame
			part("PillarCap", V3(9, 2, 9), CFrame.new(c + V3(0, h - 29, 0)), HOT, NEON)
			beam("CeilingArm", c + V3(-sx * 4, CEILING, -sz * 4), at(sx * frame, CEILING, sz * frame), 1.2, NIGHT, SCENERY)
		end
	end
end

----------------------------------------------------------------------
-- The runway and the portal (where you arrive, and the way out)
----------------------------------------------------------------------
local function buildRunway()
	local z0, z1 = HALF + 1, HALF + 1 + RUN_L
	local zc = (z0 + z1) / 2
	part("Runway", V3(RUN_W, 1, RUN_L + 2), CFrame.new(at(0, -0.5, zc)), NIGHT)
	for k = 0, math.floor(RUN_L / SIZE) do
		part("RunwayLine", V3(RUN_W, 0.3, 0.4), CFrame.new(at(0, -0.02, z0 + k * SIZE)), PURPLE, NEON)
	end
	for _, s in ipairs({ -1, 1 }) do
		part("RunwayEdge", V3(0.6, 0.6, RUN_L + 2), CFrame.new(at(s * (RUN_W / 2 - 0.3), 0.1, zc)), CYAN, NEON)
		part("RunwaySide", V3(2, 3, RUN_L + 2), CFrame.new(at(s * (RUN_W / 2 + 1), -1.5, zc)), INK)
		-- chevrons along the sides pointing at the grid (GO this way)
		for k = 0, 2 do
			local z = z0 + 4 + k * 6
			for _, t in ipairs({ -1, 1 }) do
				part("RunwayChevron", V3(0.5, 0.3, 2.2), CFrame.new(at(s * (RUN_W / 2 - 2.2) + t * 0.7, 0.05, z)) * CFrame.Angles(0, t * 0.8, 0),
					GREEN, NEON)
			end
		end
	end
	-- the portal at the far end: a tall oval ring of green blocks (the way you
	-- came, and the way out)
	local pc = at(0, 11, z1 - 2)
	local N = 20
	for i = 0, N - 1 do
		local a = (i + 0.5) / N * math.pi * 2
		local p = pc + V3(math.sin(a) * 7.5, math.cos(a) * 11, 0)
		local seg = part("PortalRing", V3(2.8, 2.2, 2), CFrame.lookAt(p, p + V3(0, 0, 1)) * CFrame.Angles(0, 0, -a), GREEN, NEON)
		if i % 2 == 0 then
			pulse(seg, 1.4, 0, 0.35)
		end
	end
	-- (its middle is open - sparkles, no glass - so your camera can look
	-- through it when you arrive)
	local swirl = part("PortalCore", V3(12, 18, 0.4), CFrame.new(pc), CYAN, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	local fe = Instance.new("ParticleEmitter")
	fe.Rate = 10
	fe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	fe.Color = ColorSequence.new(GREEN, CYAN)
	fe.LightEmission = 0.8
	fe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
	fe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	fe.Lifetime = NumberRange.new(1, 2)
	fe.Speed = NumberRange.new(1, 3)
	fe.Parent = swirl
	local exit = Instance.new("ProximityPrompt")
	exit.ActionText = "Leave"
	exit.ObjectText = "Portal"
	exit.HoldDuration = 0.4
	exit.MaxActivationDistance = 14
	exit.KeyboardKeyCode = Enum.KeyCode.E
	exit.GamepadKeyCode = Enum.KeyCode.ButtonX
	exit.RequiresLineOfSight = false
	exit.Parent = swirl
	CollectionService:AddTag(exit, "ArenaExit")
	autoZone(CFrame.new(at(0, 4, z1 - 4)), V3(RUN_W - 2, 8, 5), "Spire", "Leave")
	-- a sign over it: the level's name
	local sign = part("LevelSign", V3(26, 4, 1), CFrame.new(at(0, 26, z1 - 2)), INK)
	signText(sign, "THE FINAL BEAT", HOT, Enum.NormalId.Front)
	signText(sign, "THE FINAL BEAT", HOT, Enum.NormalId.Back)
	-- where you arrive: on the runway, looking at the grid
	local arrive = anchorPart("ArenaSpawn", CFrame.lookAt(at(0, 3, z1 - 9), at(0, 3, 0)))
	CollectionService:AddTag(arrive, "ArenaSpawn")
end

----------------------------------------------------------------------
-- The void round about (one model: the screens flip it for the gravity flip)
----------------------------------------------------------------------
local function buildBackdrop()
	local back = Instance.new("Model")
	back.Name = "Backdrop"
	back.Parent = m
	CollectionService:AddTag(back, "GridBackdrop")

	-- GIANT SPIKES in a ring far out: black triangles, neon edges
	local N = 16
	for i = 0, N - 1 do
		local a = (i + rnd() * 0.4) / N * math.pi * 2
		local r = 190 + rnd() * 60
		local h = 40 + rnd() * 50
		local w = h * 0.9
		local base = at(math.sin(a) * r, -20, math.cos(a) * r)
		local face = CFrame.lookAt(base, at(0, -20, 0)) -- (the triangle faces the grid)
		-- (two wedges back to back make a triangle, point up: each wedge is tall
		-- at its back, so both backs meet in the middle)
		wedge("Spike", V3(6, h, w / 2), face * CFrame.new(-w / 4, h / 2, 0) * CFrame.Angles(0, math.pi / 2, 0), INK, SCENERY, back)
		wedge("Spike", V3(6, h, w / 2), face * CFrame.new(w / 4, h / 2, 0) * CFrame.Angles(0, -math.pi / 2, 0), INK, SCENERY, back)
		local tip = face * V3(0, h, -3.2)
		beam("SpikeEdge", face * V3(-w / 2, 0, -3.2), tip, 1.4, (i % 3 == 0) and ORANGE or HOT, NEON, back)
		beam("SpikeEdge", face * V3(w / 2, 0, -3.2), tip, 1.4, (i % 3 == 0) and ORANGE or HOT, NEON, back)
	end

	-- FLOATING BLOCKS (the level's blocks): black cubes in a glowing shell
	for i = 1, 14 do
		local a = rnd() * math.pi * 2
		local r = 110 + rnd() * 90
		local s = 10 + rnd() * 14
		local p = at(math.sin(a) * r, -10 + rnd() * 90, math.cos(a) * r)
		local cf = CFrame.new(p) * CFrame.Angles(0, rnd() * math.pi, 0)
		part("FloatBlock", V3(s, s, s), cf, INK, SCENERY, back)
		local glow = part("FloatGlow", V3(s + 1.2, s + 1.2, s + 1.2), cf, (i % 2 == 0) and MAGENTA or CYAN, merge(NEON, { Transparency = 0.86 }), back)
		CollectionService:AddTag(glow, "GridPulse")
	end

	-- SAW BLADES, spinning (each its own model: the screens turn them)
	for i = 1, 6 do
		local a = (i - 0.5) / 6 * math.pi * 2 + 0.3
		local r = 150 + (i % 2) * 40
		local p = at(math.sin(a) * r, 10 + (i % 3) * 22, math.cos(a) * r)
		local face = CFrame.lookAt(p, at(0, p.Y - CENTER.Y, 0))
		local saw = Instance.new("Model")
		saw.Name = "Saw"
		saw.Parent = back
		local d = 18 + (i % 3) * 6
		local disc = part("SawDisc", V3(1.4, d, d), face * CFrame.Angles(0, math.pi / 2, 0), NAVY, merge(SCENERY, { Shape = Enum.PartType.Cylinder }), saw)
		part("SawHub", V3(1.8, d * 0.3, d * 0.3), face * CFrame.Angles(0, math.pi / 2, 0), HOT, merge(NEON, { Shape = Enum.PartType.Cylinder }), saw)
		for k = 0, 9 do
			local ang = k / 10 * math.pi * 2
			local tooth = face * CFrame.Angles(0, 0, ang) * CFrame.new(0, d / 2 + 1, 0)
			wedge("SawTooth", V3(1.2, 3, 3), tooth, WHITE, SCENERY, saw)
		end
		saw.PrimaryPart = disc
		CollectionService:AddTag(saw, "GridSaw")
	end

	-- NEON FRAMES (squares and triangles) turning slowly, far off
	for i = 1, 8 do
		local a = (i + 0.5) / 8 * math.pi * 2
		local r = 230
		local p = at(math.sin(a) * r, 40 + (i % 4) * 18, math.cos(a) * r)
		local frame = Instance.new("Model")
		frame.Name = "Frame"
		frame.Parent = back
		local cf = CFrame.lookAt(p, at(0, p.Y - CENTER.Y, 0))
		local sides = (i % 2 == 0) and 4 or 3
		local rad = 16 + (i % 3) * 5
		local corners = {}
		for k = 0, sides - 1 do
			local ang = k / sides * math.pi * 2
			corners[k + 1] = cf * V3(math.sin(ang) * rad, math.cos(ang) * rad, 0)
		end
		local first = nil
		for k = 1, sides do
			local b = beam("FrameEdge", corners[k], corners[k % sides + 1], 1.3, (i % 3 == 0) and YELLOW or ((i % 3 == 1) and CYAN or MAGENTA), NEON, frame)
			first = first or b
		end
		frame.PrimaryPart = first
		CollectionService:AddTag(frame, "GridSpin")
	end

	-- CHAINS hanging out of the dark at the corners
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local top = at(sx * (HALF + 26), 110, sz * (HALF + 26))
			for k = 0, 11 do
				local p = top - V3(0, k * 3.2, 0)
				local turn = (k % 2 == 0) and 0 or math.pi / 2
				part("ChainLink", V3(0.8, 3.4, 2.2), CFrame.new(p) * CFrame.Angles(0, turn, 0), NAVY, SCENERY, back)
			end
			part("ChainWeight", V3(5, 5, 5), CFrame.new(top - V3(0, 12 * 3.2 + 2, 0)) * CFrame.Angles(0, math.rad(45), 0), INK, SCENERY, back)
		end
	end

	-- STARS: little neon squares all over the sky
	for i = 1, 70 do
		local a = rnd() * math.pi * 2
		local r = 260 + rnd() * 120
		local p = at(math.sin(a) * r, -40 + rnd() * 240, math.cos(a) * r)
		local s = 0.8 + rnd() * 1.6
		local star = part("Star", V3(s, s, s), CFrame.new(p) * CFrame.Angles(0, rnd() * 3, math.rad(45)),
			(i % 4 == 0) and CYAN or ((i % 4 == 1) and MAGENTA or WHITE), NEON, back)
		if i % 3 == 0 then
			pulse(star, 0.5 + rnd(), 0, 0.6)
		end
	end

	-- HIS FACE in the northern sky: huge, faint, grinning down at the grid
	local fc = at(0, 120, -330)
	local fcf = CFrame.lookAt(fc, at(0, 60, 0))
	local FACE = merge(NEON, { Transparency = 0.55 })
	for _, s in ipairs({ -1, 1 }) do
		-- angry eyes: slanted bars, a bright middle
		part("SkyEye", V3(34, 9, 1), fcf * CFrame.new(s * 30, 22, 0) * CFrame.Angles(0, 0, s * -0.3), HOT, FACE, back)
		part("SkyPupil", V3(10, 6, 1), fcf * CFrame.new(s * 28, 20, -0.5), YELLOW, FACE, back)
		-- horns
		part("SkyHorn", V3(8, 26, 1), fcf * CFrame.new(s * 44, 56, 0) * CFrame.Angles(0, 0, s * 0.5), HOT, FACE, back)
	end
	-- the grin: a jagged row of teeth
	for k = -4, 4 do
		local up = (k % 2 == 0) and 4 or -4
		part("SkyTooth", V3(9, 10, 1), fcf * CFrame.new(k * 8.5, -26 + up, 0) * CFrame.Angles(0, 0, math.rad(45)), (k % 2 == 0) and WHITE or HOT, FACE, back)
	end

	-- PILLARS OF LIGHT far out, and the red glow of the abyss far below
	for i = 0, 7 do
		local a = (i + 0.5) / 8 * math.pi * 2
		local p = at(math.sin(a) * 140, 20, math.cos(a) * 140)
		local light = part("LightPillar", V3(3, 220, 3), CFrame.new(p), (i % 2 == 0) and MAGENTA or PURPLE, merge(NEON, { Transparency = 0.6 }), back)
		pulse(light, 0.6, 0.45, 0.8)
	end
	part("Abyss", V3(900, 2, 900), CFrame.new(at(0, -140, 0)), RGB(162, 38, 51), merge(NEON, { Transparency = 0.35 }), back)
	for i = 1, 16 do
		local a = rnd() * math.pi * 2
		local r = 80 + rnd() * 160
		local s = 6 + rnd() * 12
		part("Debris", V3(s, s, s), CFrame.new(at(math.sin(a) * r, -50 - rnd() * 70, math.cos(a) * r)) * CFrame.Angles(rnd() * 3, rnd() * 3, rnd() * 3),
			(i % 3 == 0) and NIGHT or INK, SCENERY, back)
	end
end

----------------------------------------------------------------------
-- The walls round the grid and the runway, and the marks the boss will use
----------------------------------------------------------------------
local function wallPiece(cf, size)
	local w = part("EdgeWall", size, cf, WHITE, { Transparency = 1, CanQuery = false, CastShadow = false })
	CollectionService:AddTag(w, "GridWall")
	return w
end

local function buildBounds()
	local H = 80
	local e = HALF + 1
	-- round the grid (the south side has the runway's gap)
	wallPiece(CFrame.new(at(0, H / 2, -e)), V3(e * 2 + 2, H, 2))
	wallPiece(CFrame.new(at(-e, H / 2, 0)), V3(2, H, e * 2 + 2))
	wallPiece(CFrame.new(at(e, H / 2, 0)), V3(2, H, e * 2 + 2))
	for _, sx in ipairs({ -1, 1 }) do
		local x0, x1 = sx * RUN_W / 2, sx * e
		wallPiece(CFrame.new(at((x0 + x1) / 2, H / 2, e)), V3(math.abs(x1 - x0), H, 2))
	end
	-- round the runway, and behind the portal
	local z0, z1 = HALF + 1, HALF + 1 + RUN_L
	for _, sx in ipairs({ -1, 1 }) do
		wallPiece(CFrame.new(at(sx * (RUN_W / 2 + 1), H / 2, (z0 + z1) / 2)), V3(2, H, RUN_L + 2))
	end
	wallPiece(CFrame.new(at(0, H / 2, z1 + 1)), V3(RUN_W + 4, H, 2))
	-- Where Gridlock waits: the middle of the grid, facing the runway
	local home = anchorPart("BossHome", CFrame.new(at(0, 0, 0)))
	home:SetAttribute("Floor", 6)
	home:SetAttribute("Facing", V3(0, 0, 1))
	CollectionService:AddTag(home, "BossHome")
end

----------------------------------------------------------------------
-- Public
----------------------------------------------------------------------
function GridBuilder.Build()
	local old = Workspace:FindFirstChild("GridArena")
	if old then
		old:Destroy()
	end
	m = Instance.new("Model")
	m.Name = "GridArena"
	seed = 20260929 -- (the same "random" every time it's built)

	local pieces = {
		{ "Grid", buildGrid },
		{ "Ceiling", buildCeiling },
		{ "Runway and portal", buildRunway },
		{ "Backdrop", buildBackdrop },
		{ "Walls and markers", buildBounds },
	}
	local failed = 0
	for _, piece in ipairs(pieces) do
		local ok, err = pcall(piece[2])
		if not ok then
			failed = failed + 1
			warn("[GridBuilder] '" .. piece[1] .. "' failed to build: " .. tostring(err))
		end
	end

	m:SetAttribute("Floor", 6)
	m:SetAttribute("Center", CENTER)
	m:SetAttribute("Tiles", TILES)
	m:SetAttribute("TileSize", SIZE)
	m:SetAttribute("Ceiling", CEILING)
	m:SetAttribute("RunwayA", at(-RUN_W / 2, 0, HALF))
	m:SetAttribute("RunwayB", at(RUN_W / 2, 0, HALF + 1 + RUN_L))
	m.Parent = Workspace
	if failed == 0 then
		print("[GridBuilder] The Final Beat built OK")
	end
	return m
end

GridBuilder.Center = CENTER
GridBuilder.Tiles = TILES
GridBuilder.TileSize = SIZE
GridBuilder.Ceiling = CEILING

return GridBuilder
