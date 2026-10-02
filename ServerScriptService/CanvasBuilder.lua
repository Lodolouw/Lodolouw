--[[
	CanvasBuilder  (ModuleScript, parent: ServerScriptService, name: "CanvasBuilder")

	Builds the Spire's ninth floor: THE CANVAS, Scribble's arena.

	You're inside a computer. The fight is on a giant sheet of graph paper -
	white, with pale blue grid lines and bolder blue ones cutting it into big
	squares, a red margin line down one side, and a few pencil doodles in the
	corners. The paper is the canvas of a paint program, and the program's
	window is all round it: a grey bevelled frame, the title bar standing up
	behind the north edge ("SCRIBBLE.EXE", with its minimise, maximise and
	close buttons), a toolbar of giant tools down the west side (a pencil, an
	eraser, a paint bucket, a brush and the text tool) and giant colour
	swatches like pillars down the east side. The way out is a giant red [X]
	close button in the south edge. The window floats over a bright blue
	computer desktop far below: giant folders, a text file, "My Computer"
	and the recycle bin (Scribble ends up in it), the taskbar with its START
	button along the horizon, and a giant mouse pointer resting in the sky.
	Everything is chunky and 8-bit, in the game's 32 colours.

	The paper's shape comes from ReplicatedStorage/CanvasPlan (the same
	numbers Scribble's moves and every screen use).

	Everything the fight needs is marked for SpireService / BossService:
	  * "ArenaSpawn"       where you arrive (in this model, Floor = 9)
	  * "ArenaExit"        the Leave prompt on the [X] close button, plus a
	                       walk-up box in front of it (AutoOpenZone, Spire = "Leave")
	  * "BossHome"         the middle of the paper, Floor = 9, facing the door
	  * "CanvasEdgeWall"   the invisible walls round the paper
	  * the model itself carries Floor = 9, Center (the middle of the paper),
	    FightRadius (how far out the paper goes each way: it's square) and
	    Bin (the top of the recycle bin's opening: where Scribble's body file
	    throws him at the end)

	Main calls CanvasBuilder.Build() once at startup, after the other floors
	and before BossService (which puts Scribble on his BossHome). The floor
	you fight on - the paper - is one solid, flat Part whose top is exactly
	y = 0 (not Terrain: Terrain rounds its surface to its own grid).
]]

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CanvasPlan = require(ReplicatedStorage:WaitForChild("CanvasPlan"))

local CanvasBuilder = {}

local V3 = Vector3.new
local RGB = Color3.fromRGB
local Mat = Enum.Material

----------------------------------------------------------------------
-- Layout (+Z is south: the door; Scribble faces it)
----------------------------------------------------------------------
-- (every arena has its own spot, 2600 studs apart: see the handoff notes)
local CENTER = V3(-5200, 0, 0)
local HALF = CanvasPlan.Half -- the paper goes this far out each way
local FRAME = 8 -- the window's grey frame round the paper, this wide
local EDGE = HALF + FRAME -- the window's outside edge
local DOOR_HALF = CanvasPlan.DoorHalf
local DOOR_H = 13 -- how tall the [X] door is
local SPAWN_Z = HALF - 6 -- where you arrive
local DESK_Y = -26 -- the computer desktop, far below the window

----------------------------------------------------------------------
-- Palette (the game's 32 colours)
----------------------------------------------------------------------
local PAPER = RGB(255, 255, 255)
local FINE_LINE = RGB(192, 203, 220)
local BOLD_LINE = RGB(0, 153, 219)
local MARGIN = RGB(228, 59, 68)
local PENCIL_GREY = RGB(90, 105, 136)
local SILVER = RGB(192, 203, 220)
local STEEL = RGB(139, 155, 180)
local SLATE = RGB(90, 105, 136)
local DUSK = RGB(58, 68, 102)
local NAVY = RGB(18, 78, 137)
local BLUE = RGB(0, 153, 219)
local SKY = RGB(44, 232, 245)
local WHITE = RGB(255, 255, 255)
local INK = RGB(24, 20, 37)
local RED = RGB(228, 59, 68)
local RED_DARK = RGB(162, 38, 51)
local ORANGE = RGB(247, 118, 34)
local GOLD = RGB(254, 174, 52)
local YELLOW = RGB(254, 231, 97)
local GREEN = RGB(99, 199, 77)
local GREEN_DARK = RGB(62, 137, 72)
local PINK = RGB(246, 117, 122)
local PURPLE = RGB(104, 56, 108)
local MAGENTA = RGB(181, 80, 136)
local WOOD = RGB(228, 166, 114)
local WOOD_DARK = RGB(184, 111, 80)

----------------------------------------------------------------------
-- Helpers (the same kinds of little builders as the other floors')
----------------------------------------------------------------------
local seed = 20261201
local function rnd()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
local function between(a, b)
	return a + (b - a) * rnd()
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

-- a block stretched from a to b (a pencil line, a stick), `w` wide and `h` tall
local function beam(name, a, b, w, h, color, extra, parent)
	local len = (b - a).Magnitude
	return part(name, V3(w, h or w, math.max(len, 0.05)), CFrame.lookAt((a + b) / 2, b), color, extra, parent)
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

-- words on a board (a SurfaceGui on one of its faces)
local function signText(board, text, color, face, align)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignText"
	gui.Face = face or Enum.NormalId.Front
	local w, h = board.Size.X, board.Size.Y
	if gui.Face == Enum.NormalId.Left or gui.Face == Enum.NormalId.Right then
		w = board.Size.Z
	elseif gui.Face == Enum.NormalId.Top or gui.Face == Enum.NormalId.Bottom then
		h = board.Size.Z
	end
	gui.CanvasSize = Vector2.new(w * 50, h * 50)
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.TextXAlignment = align or Enum.TextXAlignment.Center
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
-- a frame at `p` whose front (-Z) faces the middle of the paper
local function facingCentre(p)
	local flat = V3(CENTER.X, p.Y, CENTER.Z)
	if (flat - p).Magnitude < 0.01 then
		return CFrame.new(p)
	end
	return CFrame.lookAt(p, flat)
end

-- a flat pencil line on the paper (a hair above it), from a to b (x, z from
-- the middle)
local LINE_Y = 0.03
local function penLine(name, x0, z0, x1, z1, w, color)
	return beam(name, at(x0, LINE_Y, z0), at(x1, LINE_Y, z1), w, 0.04, color, DECOR)
end

----------------------------------------------------------------------
-- The paper: the floor you fight on, its grid, the margin, a few doodles
----------------------------------------------------------------------
local function buildPaper()
	-- THE PAPER: one solid slab, top at exactly y = 0
	part("CanvasPaper", V3(HALF * 2, 4, HALF * 2), CFrame.new(at(0, -2, 0)), PAPER)
	-- the grid: thin pale lines every Fine studs, bold blue ones every Cell
	-- studs (the Paint Bucket's squares)
	local fine, cell = CanvasPlan.Fine, CanvasPlan.Cell
	for k = -HALF + fine, HALF - fine, fine do
		local bold = (k % cell) == 0
		local w = bold and 0.4 or 0.16
		local color = bold and BOLD_LINE or FINE_LINE
		local y = bold and LINE_Y + 0.01 or LINE_Y -- (the bold lines sit over the thin ones)
		part(bold and "GridBold" or "GridLine", V3(w, 0.04, HALF * 2), CFrame.new(at(k, y, 0)), color, DECOR)
		part(bold and "GridBold" or "GridLine", V3(HALF * 2, 0.04, w), CFrame.new(at(0, y, k)), color, DECOR)
	end
	-- the red margin line down the west side, like notebook paper
	part("MarginLine", V3(0.35, 0.05, HALF * 2), CFrame.new(at(CanvasPlan.Margin, LINE_Y + 0.02, 0)), MARGIN, DECOR)

	-- A FEW DOODLES in pencil, near the corners (out of the way of the fight's
	-- warnings, which land in the middle of the squares)
	-- a sun in the north-west corner: a circle of short strokes and rays
	local sx, sz = -54, -54
	for k = 0, 11 do
		local a0, a1 = k / 12 * math.pi * 2, (k + 1) / 12 * math.pi * 2
		penLine("DoodleSun", sx + math.cos(a0) * 3, sz + math.sin(a0) * 3, sx + math.cos(a1) * 3, sz + math.sin(a1) * 3, 0.3, PENCIL_GREY)
		if k % 2 == 0 then
			penLine("DoodleRay", sx + math.cos(a0) * 4, sz + math.sin(a0) * 4, sx + math.cos(a0) * 5.6, sz + math.sin(a0) * 5.6, 0.3, PENCIL_GREY)
		end
	end
	-- a little house in the north-east corner
	local hx, hz = 52, -52
	penLine("DoodleHouse", hx - 3, hz + 3, hx + 3, hz + 3, 0.3, PENCIL_GREY)
	penLine("DoodleHouse", hx - 3, hz + 3, hx - 3, hz - 1, 0.3, PENCIL_GREY)
	penLine("DoodleHouse", hx + 3, hz + 3, hx + 3, hz - 1, 0.3, PENCIL_GREY)
	penLine("DoodleHouse", hx - 3.8, hz - 0.6, hx, hz - 4.4, 0.3, PENCIL_GREY)
	penLine("DoodleHouse", hx + 3.8, hz - 0.6, hx, hz - 4.4, 0.3, PENCIL_GREY)
	penLine("DoodleHouse", hx - 0.8, hz + 3, hx - 0.8, hz + 0.8, 0.3, PENCIL_GREY)
	penLine("DoodleHouse", hx + 0.8, hz + 3, hx + 0.8, hz + 0.8, 0.3, PENCIL_GREY)
	penLine("DoodleHouse", hx - 0.8, hz + 0.8, hx + 0.8, hz + 0.8, 0.3, PENCIL_GREY)
	-- a smiley in the south-west corner (in blue pen, like him)
	local fx, fz = -53, 50
	for k = 0, 11 do
		local a0, a1 = k / 12 * math.pi * 2, (k + 1) / 12 * math.pi * 2
		penLine("DoodleSmiley", fx + math.cos(a0) * 3.4, fz + math.sin(a0) * 3.4, fx + math.cos(a1) * 3.4, fz + math.sin(a1) * 3.4, 0.3, BLUE)
	end
	penLine("DoodleSmiley", fx - 1.2, fz - 1.4, fx - 1.2, fz - 0.6, 0.35, BLUE)
	penLine("DoodleSmiley", fx + 1.2, fz - 1.4, fx + 1.2, fz - 0.6, 0.35, BLUE)
	penLine("DoodleSmiley", fx - 1.8, fz + 0.8, fx, fz + 1.8, 0.3, BLUE)
	penLine("DoodleSmiley", fx, fz + 1.8, fx + 1.8, fz + 0.8, 0.3, BLUE)
	-- and a star in the south-east corner, by the door
	local tx, tz = 50, 52
	local pts = {}
	for k = 0, 4 do
		local a = -math.pi / 2 + k * math.pi * 2 * 2 / 5
		pts[k + 1] = { tx + math.cos(a) * 3.4, tz + math.sin(a) * 3.4 }
	end
	for k = 1, 5 do
		local a, b = pts[k], pts[k % 5 + 1]
		penLine("DoodleStar", a[1], a[2], b[1], b[2], 0.3, PENCIL_GREY)
	end
end

----------------------------------------------------------------------
-- The program's window round the paper: the frame, the title bar
----------------------------------------------------------------------
local function buildWindow()
	-- THE FRAME: a grey border all round, bevelled like an old window: pale on
	-- the inside edge, dark on the outside
	local t = FRAME
	for _, side in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
		local dx, dz = side[1], side[2]
		local along = dx == 0 -- (a north or south side runs along x)
		local len = EDGE * 2
		local mid = V3(dx * (HALF + t / 2), 0, dz * (HALF + t / 2))
		local size = along and V3(len, 4.6, t) or V3(t, 4.6, len)
		-- (its top stands 0.6 over the paper; SOLID - the way to the [X] door
		-- crosses it, and as scenery you fell straight through it there)
		part("WindowFrame", size, CFrame.new(at(mid.X, 0.6 - 2.3, mid.Z)), SILVER, { CanQuery = false })
		-- the pale inner bevel and the dark outer one
		local inner = V3(dx * (HALF + 0.6), 0.7, dz * (HALF + 0.6))
		part("FrameBevel", along and V3(HALF * 2 + 1.2, 0.2, 1.2) or V3(1.2, 0.2, HALF * 2 + 1.2), CFrame.new(at(inner.X, inner.Y, inner.Z)), WHITE, DECOR)
		local outer = V3(dx * (EDGE - 0.6), 0.7, dz * (EDGE - 0.6))
		part("FrameBevel", along and V3(len, 0.2, 1.2) or V3(1.2, 0.2, len), CFrame.new(at(outer.X, outer.Y, outer.Z)), SLATE, DECOR)
	end
	-- the window's drop shadow on the desktop far below
	part("WindowShadow", V3(EDGE * 2, 0.2, EDGE * 2), CFrame.new(at(9, DESK_Y + 0.15, 9)), NAVY, DECOR)
	-- and the window's underside (it's a thick slab, floating)
	-- (solid too: nothing on the window falls through it)
	part("WindowUnder", V3(EDGE * 2 - 0.4, 3, EDGE * 2 - 0.4), CFrame.new(at(0, -5.5, 0)), STEEL, { CanQuery = false })

	-- THE TITLE BAR: standing up behind the north edge, navy, with the
	-- program's name and a little pencil icon, and its three buttons
	local z = -(EDGE + 1.2)
	local y0, th = 6, 18 -- (it stands on posts, its bottom this high, this tall)
	local yc = y0 + th / 2
	part("TitleBar", V3(EDGE * 2 + 4, th, 2.4), CFrame.new(at(0, yc, z)), NAVY, SCENERY)
	part("TitleBarShine", V3(EDGE * 2 + 4, 1.6, 2.5), CFrame.new(at(0, y0 + th - 0.8, z)), BLUE, DECOR)
	part("TitleBarBase", V3(EDGE * 2 + 4, 1.2, 2.6), CFrame.new(at(0, y0 + 0.6, z)), DUSK, DECOR)
	for _, sx in ipairs({ -1, 0, 1 }) do
		part("TitleBarPost", V3(3, y0, 2.4), CFrame.new(at(sx * (EDGE - 4), y0 / 2, z)), DUSK, SCENERY)
	end
	local label = part("TitleText", V3(84, 10, 0.2), CFrame.new(at(-14, yc + 0.2, z + 1.25)) * CFrame.Angles(0, math.pi, 0), NAVY, DECOR)
	signText(label, "SCRIBBLE.EXE", WHITE, Enum.NormalId.Front, Enum.TextXAlignment.Left)
	-- the program's icon: a little pencil
	local ix = -EDGE + 6
	part("TitleIconBody", V3(7, 2.2, 0.4), CFrame.new(at(ix, yc, z + 1.35)) * CFrame.Angles(0, 0, math.rad(35)), GOLD, DECOR)
	part("TitleIconTip", V3(2, 1.6, 0.4), CFrame.new(at(ix + 3.6, yc + 2.5, z + 1.35)) * CFrame.Angles(0, 0, math.rad(35)), WOOD, DECOR)
	part("TitleIconRubber", V3(1.6, 2.2, 0.4), CFrame.new(at(ix - 3.3, yc - 2.4, z + 1.35)) * CFrame.Angles(0, 0, math.rad(35)), PINK, DECOR)
	-- minimise, maximise, close
	local buttons = { { "_", SILVER, INK }, { "[]", SILVER, INK }, { "X", RED, WHITE } }
	for k, b in ipairs(buttons) do
		local bx = EDGE - 2 - (4 - k) * 11 + 5.5
		part("TitleButton", V3(9.6, 9.6, 1), CFrame.new(at(bx, yc, z + 1.5)), b[2], SCENERY)
		part("TitleButtonShade", V3(9.6, 0.9, 1.05), CFrame.new(at(bx, yc - 4.35, z + 1.5)), b[2] == RED and RED_DARK or SLATE, DECOR)
		local face = part("TitleButtonGlyph", V3(7.5, 7.5, 0.2), CFrame.new(at(bx, yc + 0.3, z + 2.05)) * CFrame.Angles(0, math.pi, 0), b[2], DECOR)
		signText(face, b[1], b[3], Enum.NormalId.Front)
	end
end

----------------------------------------------------------------------
-- The toolbar (west) and the colour swatches (east)
----------------------------------------------------------------------
-- A PENCIL standing on its rubber: pink rubber, a steel band, a long yellow
-- six-sided body, the bare wood cone and the lead tip at the top
local function giantPencil(p, h)
	local body = h * 0.62
	part("PencilRubber", V3(3.4, h * 0.12, 3.4), CFrame.new(p + V3(0, h * 0.06, 0)), PINK, SCENERY)
	part("PencilBand", V3(3.6, h * 0.07, 3.6), CFrame.new(p + V3(0, h * 0.155, 0)), STEEL, SCENERY)
	local y0 = h * 0.19
	part("PencilBody", V3(3.4, body, 2.2), CFrame.new(p + V3(0, y0 + body / 2, 0)), GOLD, SCENERY)
	part("PencilBody", V3(2.2, body, 3.4), CFrame.new(p + V3(0, y0 + body / 2, 0)), YELLOW, SCENERY)
	part("PencilStripe", V3(0.3, body, 3.45), CFrame.new(p + V3(0.6, y0 + body / 2, 0)), ORANGE, DECOR)
	local c0 = y0 + body
	part("PencilWood", V3(2.6, h * 0.08, 2.6), CFrame.new(p + V3(0, c0 + h * 0.04, 0)), WOOD, SCENERY)
	part("PencilWood", V3(1.6, h * 0.07, 1.6), CFrame.new(p + V3(0, c0 + h * 0.115, 0)), WOOD_DARK, SCENERY)
	part("PencilLead", V3(0.8, h * 0.05, 0.8), CFrame.new(p + V3(0, c0 + h * 0.175, 0)), DUSK, SCENERY)
end

-- AN ERASER: a big pink block with a blue paper sleeve, leaning
local function giantEraser(p, s)
	local cf = CFrame.new(p + V3(0, s * 0.45, 0)) * CFrame.Angles(0, 0.4, math.rad(12))
	part("EraserBlock", V3(s * 1.6, s * 0.8, s), cf, PINK, SCENERY)
	part("EraserSleeve", V3(s * 0.8, s * 0.84, s * 1.04), cf * CFrame.new(s * 0.35, 0, 0), BLUE, SCENERY)
	part("EraserStripe", V3(s * 0.12, s * 0.86, s * 1.06), cf * CFrame.new(s * 0.05, 0, 0), WHITE, DECOR)
	part("EraserCrumbs", V3(s * 0.5, 0.3, s * 0.3), CFrame.new(p + V3(-s * 1.1, 0.15, s * 0.3)), PINK, DECOR)
end

-- A PAINT BUCKET tipped over, red paint spilling out
local function giantBucket(p, s)
	local cf = CFrame.new(p + V3(0, s * 0.5, 0)) * CFrame.Angles(0, -0.5, math.rad(-18))
	part("BucketBody", V3(s, s, s), cf, STEEL, SCENERY)
	part("BucketRim", V3(s * 1.12, s * 0.14, s * 1.12), cf * CFrame.new(0, s * 0.5, 0), SILVER, SCENERY)
	part("BucketPaint", V3(s * 0.9, s * 0.12, s * 0.9), cf * CFrame.new(0, s * 0.52, 0), RED, DECOR)
	part("BucketHandle", V3(s * 1.2, s * 0.12, s * 0.12), cf * CFrame.new(0, s * 0.9, 0), SLATE, DECOR)
	part("BucketSpill", V3(s * 1.6, 0.3, s * 1.1), CFrame.new(p + V3(s * 0.9, 0.15, s * 0.2)), RED, DECOR)
	part("BucketDrip", V3(s * 0.3, s * 0.5, s * 0.2), cf * CFrame.new(s * 0.35, s * 0.3, s * 0.56), RED, DECOR)
end

-- A BRUSH standing up in the air: wooden handle, steel band, rainbow bristles
local function giantBrush(p, h)
	part("BrushHandle", V3(1.4, h * 0.6, 1.4), CFrame.new(p + V3(0, h * 0.3, 0)), WOOD_DARK, SCENERY)
	part("BrushBand", V3(2.6, h * 0.14, 1.8), CFrame.new(p + V3(0, h * 0.67, 0)), SILVER, SCENERY)
	local cols = { RED, ORANGE, YELLOW, GREEN, BLUE }
	for k, c in ipairs(cols) do
		part("BrushBristles", V3(0.5, h * 0.24, 1.6), CFrame.new(p + V3(-1.1 + (k - 1) * 0.55, h * 0.86, 0)), c, SCENERY)
	end
end

-- THE TEXT TOOL: a giant black letter A
local function giantLetter(p, h)
	local w = h * 0.7
	beam("LetterA", p + V3(-w / 2, 0, 0), p + V3(0, h, 0), 2, 2, INK, SCENERY)
	beam("LetterA", p + V3(w / 2, 0, 0), p + V3(0, h, 0), 2, 2, INK, SCENERY)
	part("LetterA", V3(w * 0.55, 1.6, 2), CFrame.new(p + V3(0, h * 0.38, 0)), INK, SCENERY)
end

local function buildTools()
	-- the toolbar: a long grey panel standing along the west frame, and the
	-- tools on it
	local x = -(EDGE + 6)
	part("Toolbar", V3(10, 3, HALF * 2 + 10), CFrame.new(at(x, -1.5, 0)), SILVER, SCENERY)
	part("ToolbarEdge", V3(0.8, 3.1, HALF * 2 + 10), CFrame.new(at(x + 5, -1.5, 0)), SLATE, DECOR)
	-- a little square "button" under each tool, like a toolbar's
	local tools = {
		{ -44, function(p) giantBrush(p, 18) end },
		{ -22, function(p) giantBucket(p, 7) end },
		{ 0, function(p) giantPencil(p, 30) end },
		{ 22, function(p) giantEraser(p, 7) end },
		{ 44, function(p) giantLetter(p, 14) end },
	}
	for _, tool in ipairs(tools) do
		local p = at(x, 0, tool[1])
		part("ToolButton", V3(9, 0.4, 9), CFrame.new(p + V3(0, 0.2, 0)), tool[1] == 0 and SKY or WHITE, DECOR)
		tool[2](p + V3(0, 0.4, 0))
	end
end

local function buildSwatches()
	-- the colour swatches: square pillars down the east side, each with a dark
	-- outline at its foot and top, the "current colour" (blue, his ink) a bit
	-- taller
	local x = EDGE + 6
	part("SwatchPanel", V3(10, 3, HALF * 2 + 10), CFrame.new(at(x, -1.5, 0)), SILVER, SCENERY)
	local colours = { INK, WHITE, RED, ORANGE, YELLOW, GREEN, SKY, BLUE, PURPLE, PINK }
	local n = #colours
	for k, c in ipairs(colours) do
		local z = -HALF + 6 + (k - 1) * (HALF * 2 - 12) / (n - 1)
		local tall = c == BLUE and 18 or 13
		local p = at(x, 0, z)
		part("SwatchOutline", V3(6.4, 0.8, 6.4), CFrame.new(p + V3(0, 0.4, 0)), INK, SCENERY)
		part("Swatch", V3(5.6, tall, 5.6), CFrame.new(p + V3(0, 0.8 + tall / 2, 0)), c, SCENERY)
		part("SwatchOutline", V3(6.4, 0.6, 6.4), CFrame.new(p + V3(0, 0.8 + tall + 0.3, 0)), INK, SCENERY)
	end
end

----------------------------------------------------------------------
-- The desktop far below: the icons, the taskbar, the mouse pointer
----------------------------------------------------------------------
-- an icon's name under it: white letters on a navy tag at its foot, a
-- little in front of it, facing the paper (`p` is the icon's foot)
local function iconLabel(p, text, width)
	local toward = V3(CENTER.X - p.X, 0, CENTER.Z - p.Z)
	toward = toward.Magnitude > 0.01 and toward.Unit or V3(0, 0, 1)
	local h = math.max(3, width * 0.12)
	local tag = part("IconLabel", V3(width, h, 0.4), facingCentre(p + toward * (width * 0.45) + V3(0, h / 2 + 0.2, 0)), NAVY, SCENERY)
	signText(tag, text, WHITE, Enum.NormalId.Front)
end

-- A FOLDER: a yellow box with a tab, standing up, facing the paper
local function folder(p, s, name)
	local cf = facingCentre(p + V3(0, s * 0.4, 0))
	part("FolderBack", V3(s * 1.3, s * 0.8, s * 0.3), cf, ORANGE, SCENERY)
	part("FolderTab", V3(s * 0.5, s * 0.14, s * 0.3), cf * CFrame.new(-s * 0.36, s * 0.46, 0), ORANGE, SCENERY)
	part("FolderFront", V3(s * 1.3, s * 0.66, s * 0.3), cf * CFrame.new(0, -s * 0.07, -s * 0.2) * CFrame.Angles(math.rad(-10), 0, 0), GOLD, SCENERY)
	part("FolderPaper", V3(s * 1.1, s * 0.3, s * 0.1), cf * CFrame.new(0, s * 0.36, -s * 0.05), WHITE, DECOR)
	iconLabel(p, name, s * 1.3)
end

-- A TEXT FILE: a white page with lines on it and a folded corner
local function textFile(p, s, name)
	local cf = facingCentre(p + V3(0, s * 0.55, 0))
	part("FilePage", V3(s * 0.8, s * 1.1, s * 0.2), cf, WHITE, SCENERY)
	part("FileCorner", V3(s * 0.2, s * 0.2, s * 0.22), cf * CFrame.new(s * 0.3, s * 0.45, -0.02), SILVER, DECOR)
	for k = 1, 5 do
		part("FileLine", V3(s * 0.56, s * 0.05, s * 0.22), cf * CFrame.new(-0.02 * s, s * (0.3 - k * 0.14), -0.02), STEEL, DECOR)
	end
	iconLabel(p, name, s * 1.4)
end

-- MY COMPUTER: a chunky old monitor with a blue screen, on a little stand
local function computer(p, s, name)
	local cf = facingCentre(p + V3(0, s * 0.65, 0))
	part("MonitorCase", V3(s * 1.3, s, s * 0.8), cf, SILVER, SCENERY)
	part("MonitorScreen", V3(s * 1.05, s * 0.75, 0.2), cf * CFrame.new(0, 0.03 * s, -s * 0.41), BLUE, DECOR)
	part("MonitorShine", V3(s * 0.3, s * 0.1, 0.22), cf * CFrame.new(-s * 0.3, s * 0.27, -s * 0.42), SKY, DECOR)
	part("MonitorStand", V3(s * 0.8, s * 0.15, s * 0.6), cf * CFrame.new(0, -s * 0.58, 0), STEEL, SCENERY)
	iconLabel(p, name, s * 1.6)
end

-- THE RECYCLE BIN: an open-topped grey bin with ribs and the recycling
-- arrows - Scribble gets crumpled up and thrown in here at the end. Returns
-- the middle of its opening.
local function recycleBin(p, s)
	local base = p + V3(0, s * 0.6, 0)
	local cf = facingCentre(base)
	local w, h = s, s * 1.2
	local wall = s * 0.1
	-- four walls round an open top (so there's somewhere for him to land)
	part("BinWall", V3(w, h, wall), cf * CFrame.new(0, 0, -w / 2 + wall / 2), SILVER, SCENERY)
	part("BinWall", V3(w, h, wall), cf * CFrame.new(0, 0, w / 2 - wall / 2), SILVER, SCENERY)
	part("BinWall", V3(wall, h, w), cf * CFrame.new(-w / 2 + wall / 2, 0, 0), SILVER, SCENERY)
	part("BinWall", V3(wall, h, w), cf * CFrame.new(w / 2 - wall / 2, 0, 0), SILVER, SCENERY)
	part("BinFloor", V3(w, wall, w), cf * CFrame.new(0, -h / 2 + wall / 2, 0), STEEL, SCENERY)
	part("BinRim", V3(w * 1.08, s * 0.08, w * 1.08), cf * CFrame.new(0, h / 2, 0), STEEL, DECOR)
	for k = -1, 1 do
		part("BinRib", V3(s * 0.06, h * 0.8, wall * 1.2), cf * CFrame.new(k * w * 0.3, -h * 0.05, -w / 2), STEEL, DECOR)
	end
	-- the recycling arrows: a green triangle of three bars on the front
	for k = 0, 2 do
		local a = k / 3 * math.pi * 2
		local c = cf * CFrame.new(math.sin(a) * s * 0.18, math.cos(a) * s * 0.18 + h * 0.1, -w / 2 - wall * 0.6) * CFrame.Angles(0, 0, -a + math.pi / 2)
		part("BinArrow", V3(s * 0.32, s * 0.07, 0.3), c, GREEN, DECOR)
	end
	-- a few scrunched-up papers already in it
	for k = 1, 4 do
		local q = base + V3(between(-w * 0.25, w * 0.25), h / 2 - s * 0.12, between(-w * 0.25, w * 0.25))
		part("BinPaper", V3(s * 0.2, s * 0.2, s * 0.2), CFrame.new(q) * CFrame.Angles(rnd() * 3, rnd() * 3, 0), WHITE, DECOR)
	end
	iconLabel(p, "RECYCLE BIN", s * 1.5)
	return base + V3(0, h / 2, 0)
end

local function buildDesktop()
	-- THE DESKTOP: a huge bright blue plane far below the window
	part("Desktop", V3(1000, 2, 1000), CFrame.new(at(0, DESK_Y - 1, 0)), BLUE, SCENERY)
	-- a faint lighter glow in the middle, like a wallpaper
	part("DesktopGlow", V3(420, 0.2, 420), CFrame.new(at(0, DESK_Y + 0.05, 0)) * CFrame.Angles(0, math.rad(45), 0), SKY, DECOR)
	-- the icons, standing round the window
	local y = DESK_Y + 0.2
	folder(at(-170, y, -120), 50, "HOMEWORK")
	folder(at(-210, y, 40), 42, "NEW FOLDER")
	textFile(at(-160, y, 170), 42, "DOODLES.TXT")
	computer(at(210, y, 80), 42, "MY COMPUTER")
	folder(at(170, y, 200), 38, "NEW FOLDER (2)")
	local binTop = recycleBin(at(130, y, -130), 44)
	m:SetAttribute("Bin", binTop)
	-- THE TASKBAR along the horizon to the south: a long grey bar with the
	-- green START button and a clock
	local tz = 320
	local ty = DESK_Y + 22 -- (its top clears the window's frame from where you stand)
	part("Taskbar", V3(900, 44, 6), CFrame.new(at(0, ty, tz)), SILVER, SCENERY)
	part("TaskbarTop", V3(900, 2, 6.2), CFrame.new(at(0, ty + 21, tz)), WHITE, DECOR)
	local start = part("StartButton", V3(80, 30, 2), CFrame.new(at(370, ty, tz - 3.6)), GREEN, SCENERY)
	part("StartShade", V3(80, 3, 2.1), CFrame.new(at(370, ty - 13.5, tz - 3.6)), GREEN_DARK, DECOR)
	signText(start, "START", WHITE, Enum.NormalId.Front)
	local clock = part("TaskbarClock", V3(70, 24, 2), CFrame.new(at(-380, ty, tz - 3.6)), STEEL, SCENERY)
	signText(clock, "12:00", INK, Enum.NormalId.Front)
	-- open windows on the taskbar
	for k, name in ipairs({ "SCRIBBLE.EXE", "PAINT", "MUSIC" }) do
		local tab = part("TaskbarTab", V3(100, 24, 2), CFrame.new(at(240 - (k - 1) * 110, ty, tz - 3.6)), k == 1 and WHITE or SILVER, SCENERY)
		signText(tab, name, INK, Enum.NormalId.Front)
	end
	-- A GIANT MOUSE POINTER resting in the sky to the north-west: a white arrow
	-- with a black outline, tipped over
	local tip = at(-150, 55, -170)
	local cf = CFrame.new(tip) * CFrame.Angles(0, math.rad(35), math.rad(-25))
	local function arrowBlock(x, y, w, h, color)
		part("SkyCursor", V3(w, h, 3), cf * CFrame.new(x + w / 2, -(y + h / 2), 0), color, SCENERY)
	end
	-- (drawn row by row, like the pixel arrow it is: 3 studs a pixel)
	local rows = { 1, 2, 3, 4, 5, 6, 7, 8, 5, 3, 2 }
	for r, n in ipairs(rows) do
		arrowBlock(0, (r - 1) * 3, n * 3, 3, INK)
		if n > 2 and r < #rows - 1 then
			arrowBlock(3, (r - 1) * 3, (n - 2) * 3, 3, WHITE)
		end
	end
	arrowBlock(9, 33, 6, 12, INK) -- the pointer's tail
	arrowBlock(10.5, 33, 3, 10.5, WHITE)
end

----------------------------------------------------------------------
-- The [X] door, the walls round the paper, and the marks the boss will use
----------------------------------------------------------------------
local function buildDoor()
	local z = HALF + 3
	-- THE CLOSE BUTTON: a giant red square with a white X, in the south frame
	local door = part("CloseButton", V3(DOOR_HALF * 2 - 1, DOOR_H, 2), CFrame.new(at(0, DOOR_H / 2, z)), RED, SCENERY)
	part("CloseButtonShade", V3(DOOR_HALF * 2 - 1, 1, 2.1), CFrame.new(at(0, 0.5, z)), RED_DARK, DECOR)
	part("CloseButtonShine", V3(DOOR_HALF * 2 - 1, 0.8, 2.1), CFrame.new(at(0, DOOR_H - 0.4, z)), PINK, DECOR)
	-- the white X, facing the paper (two crossed bars)
	for _, a in ipairs({ math.rad(45), math.rad(-45) }) do
		part("CloseX", V3(9, 1.8, 0.4), CFrame.new(at(0, DOOR_H / 2, z - 1.1)) * CFrame.Angles(0, 0, a), WHITE, DECOR)
	end
	-- a grey frame round it, and the word over it
	for _, sx in ipairs({ -1, 1 }) do
		part("DoorPost", V3(1.2, DOOR_H + 2, 2.6), CFrame.new(at(sx * (DOOR_HALF + 0.1), (DOOR_H + 2) / 2, z)), SLATE, SCENERY)
	end
	part("DoorLintel", V3(DOOR_HALF * 2 + 1.4, 1.4, 2.6), CFrame.new(at(0, DOOR_H + 1.3, z)), SLATE, SCENERY)
	local sign = part("CloseSign", V3(16, 3, 0.4), CFrame.new(at(0, DOOR_H + 3.8, z - 1)), NAVY, SCENERY)
	signText(sign, "CLOSE", WHITE, Enum.NormalId.Front)
	local outside = part("CloseSignOut", V3(16, 3, 0.4), CFrame.new(at(0, DOOR_H + 3.8, z + 1)) * CFrame.Angles(0, math.pi, 0), NAVY, SCENERY)
	signText(outside, "THE CANVAS", WHITE, Enum.NormalId.Front)
	-- the way out: the Leave prompt on the button (switched off on screens)
	-- and the walk-up box in front of it
	local exit = Instance.new("ProximityPrompt")
	exit.ActionText = "Leave"
	exit.ObjectText = "Close Button"
	exit.HoldDuration = 0.4
	exit.MaxActivationDistance = 14
	exit.KeyboardKeyCode = Enum.KeyCode.E
	exit.GamepadKeyCode = Enum.KeyCode.ButtonX
	exit.RequiresLineOfSight = false
	exit.Parent = door
	CollectionService:AddTag(exit, "ArenaExit")
	autoZone(CFrame.new(at(0, 4, HALF + 0.6)), V3(DOOR_HALF * 2 - 2, 8, 3.4), "Spire", "Leave")
	-- where you arrive: just inside the door, looking at him
	local arrive = anchorPart("ArenaSpawn", CFrame.lookAt(at(0, 3, SPAWN_Z), at(0, 3, 0)))
	CollectionService:AddTag(arrive, "ArenaSpawn")
end

local function wall(cf, size)
	local w = part("EdgeWall", size, cf, WHITE, { Transparency = 1, CanQuery = false, CastShadow = false })
	CollectionService:AddTag(w, "CanvasEdgeWall")
	return w
end

local function buildBounds()
	local H = 60
	local r = HALF + 1
	-- round the paper (the south side leaves the way to the door open)
	wall(CFrame.new(at(0, H / 2, -r)), V3(r * 2 + 2, H, 2))
	wall(CFrame.new(at(-r, H / 2, 0)), V3(2, H, r * 2 + 2))
	wall(CFrame.new(at(r, H / 2, 0)), V3(2, H, r * 2 + 2))
	for _, sx in ipairs({ -1, 1 }) do
		local x0, x1 = DOOR_HALF, r + 1
		wall(CFrame.new(at(sx * (x0 + x1) / 2, H / 2, r)), V3(x1 - x0, H, 2))
		-- the sides of the way to the door
		wall(CFrame.new(at(sx * (DOOR_HALF + 1), H / 2, HALF + 2)), V3(2, H, 4))
	end
	-- and right behind the door (past it is the window's edge, and a long drop)
	wall(CFrame.new(at(0, H / 2, HALF + 4.4)), V3(DOOR_HALF * 2 + 2, H, 1))
	-- Where Scribble stands at the start: the middle of the paper, facing the
	-- door you come in by. BossService puts Scribble himself on this spot.
	local home = anchorPart("BossHome", CFrame.new(at(0, 0, 0)))
	home:SetAttribute("Floor", 9)
	home:SetAttribute("Facing", V3(0, 0, 1))
	CollectionService:AddTag(home, "BossHome")
end

----------------------------------------------------------------------
-- Public
----------------------------------------------------------------------
function CanvasBuilder.Build()
	local old = Workspace:FindFirstChild("CanvasArena")
	if old then
		old:Destroy()
	end
	m = Instance.new("Model")
	m.Name = "CanvasArena"
	seed = 20261201 -- (the same "random" every time it's built)

	-- each piece on its own, so one mistake can't leave the whole arena missing
	local pieces = {
		{ "Paper", buildPaper },
		{ "Window", buildWindow },
		{ "Tools", buildTools },
		{ "Swatches", buildSwatches },
		{ "Desktop", buildDesktop },
		{ "Door", buildDoor },
		{ "Walls and markers", buildBounds },
	}
	local failed = 0
	for _, piece in ipairs(pieces) do
		local ok, err = pcall(piece[2])
		if not ok then
			failed = failed + 1
			warn("[CanvasBuilder] '" .. piece[1] .. "' failed to build: " .. tostring(err))
		end
	end

	m:SetAttribute("Floor", 9)
	m:SetAttribute("Center", CENTER)
	m:SetAttribute("FightRadius", HALF) -- how far out the paper goes each way (it's square)
	m.Parent = Workspace
	if failed == 0 then
		print("[CanvasBuilder] The Canvas built OK")
	end
	return m
end

CanvasBuilder.Center = CENTER
CanvasBuilder.FightRadius = HALF

return CanvasBuilder
