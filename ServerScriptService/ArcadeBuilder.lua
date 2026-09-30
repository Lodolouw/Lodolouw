--[[
	ArcadeBuilder  (ModuleScript, parent: ServerScriptService, name: "ArcadeBuilder")

	THE ARCADE, where the forge used to be (north-east of the fountain, at
	Config.Stations.Arcade): an open-front pavilion - purple toy-brick walls,
	a canopy over the machines (the middle stays open to the sky), and an
	entrance arch facing the path with ARCADE in thin neon tubes, chasing
	bulbs round the opening and the giant token turning on top.
	LobbyBuilder calls ArcadeBuilder.Build(lobby).

	Inside:
	  * the MACHINES: one arcade cabinet per weapon pack in a curve round the
	    back, turned to the entrance (Config.Arcade.Machines), each painted
	    like its boss with a topper (Oozark's slime, a shovel, a tyre, a
	    banana, a pencil), on a plinth in its colour under a spotlight
	  * the TOKEN MACHINE (the Robux shop, later) just inside, beside the arch
	  * the PRIZE PEDESTAL in the open middle (the Slime machine's Secret
	    weapon floats and turns over it: ArcadeClient puts it there)
	  * the BIG WINS scoreboard on the back wall (ArcadeClient writes the
	    lobby's latest Legendary-or-better spins on it)
	  * a walk-in box over the whole floor (AutoOpenZone, Activity =
	    "Arcade"): walking in opens the Arcade menu (ArcadeClient)

	Tagged for the screens: each cabinet is a Model tagged "ArcadeCabinet"
	(attribute Machine = the pack's id) with a
	"Screen" and a "Marquee" part;
	the pedestal "ArcadePrize" (Machine); the board "ArcadeWins"; the token
	machine "ArcadeTokens". Everything is in the lobby's palette (RetroWorld).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local ArcadeBuilder = {}

local V3 = Vector3.new
local RGB = Color3.fromRGB
local Mat = Enum.Material
local FONT = Enum.Font.FredokaOne

-- the palette (Endesga 32, like everything in the lobby)
local INK = RGB(24, 20, 37)
local NIGHT = RGB(38, 43, 68)
local SLATE = RGB(58, 68, 102)
local PURPLE = RGB(104, 56, 108)
local MAGENTA = RGB(181, 80, 136)
local PINK = RGB(255, 0, 68)
local CYAN = RGB(44, 232, 245)
local YELLOW = RGB(254, 231, 97)
local GOLD = RGB(254, 174, 52)
local ORANGE = RGB(247, 118, 34)
local GREEN = RGB(99, 199, 77)
local WHITE = RGB(255, 255, 255)
local STEEL = RGB(192, 203, 220)
local BROWN = RGB(115, 62, 57)

local function part(parent, name, size, cf, color, material, extra)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Mat.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(extra or {}) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

local function neon(parent, name, size, cf, color, extra)
	local e = { CastShadow = false }
	for k, v in pairs(extra or {}) do
		e[k] = v
	end
	return part(parent, name, size, cf, color, Mat.Neon, e)
end

local function ball(parent, name, d, cf, color, material)
	return part(parent, name, V3(d, d, d), cf, color, material, { Shape = Enum.PartType.Ball })
end

-- a disc standing on its edge, its round faces along `cf`'s look
local function disc(parent, name, thick, d, cf, color, material)
	return part(parent, name, V3(thick, d, d), cf * CFrame.Angles(0, math.pi / 2, 0), color, material, { Shape = Enum.PartType.Cylinder })
end

local function folder(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- a SurfaceGui on one face that glows by itself (not lit by the sun)
local function screenGui(p, face, pixelsPerStud)
	local g = Instance.new("SurfaceGui")
	g.Name = "Gui"
	g.Face = face or Enum.NormalId.Front
	g.LightInfluence = 0
	g.Brightness = 1.6
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = pixelsPerStud or 40
	g.ResetOnSpawn = false
	g.Parent = p
	return g
end

local function label(parent, name, text, color, pos, size, extra)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = pos
	l.Size = size
	l.Font = FONT
	l.Text = text
	l.TextColor3 = color
	l.TextScaled = true
	for k, v in pairs(extra or {}) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

----------------------------------------------------------------------
-- A cabinet. `cf`: the middle of its foot on the floor, facing its players
-- (its look). `machine`: Config.Arcade.Machines[id] (nil under a cover).
----------------------------------------------------------------------
local TOPPERS = {}

-- Oozark's slime on top, with his eyes
function TOPPERS.Slime(m, top)
	ball(m, "TopperSlime", 2.4, top * CFrame.new(0, 1.1, 0.2), GREEN)
	ball(m, "TopperSlimeDrip", 1.2, top * CFrame.new(1.1, 0.4, -0.2), GREEN)
	for _, x in ipairs({ -0.5, 0.5 }) do
		ball(m, "TopperEye", 0.7, top * CFrame.new(x, 1.5, -0.8), WHITE)
		ball(m, "TopperPupil", 0.35, top * CFrame.new(x, 1.5, -1.12), INK)
	end
end

-- Burrowmore's shovel, stuck in at an angle
function TOPPERS.Knight(m, top)
	local c = top * CFrame.new(0, 1.8, 0) * CFrame.Angles(0, 0, math.rad(-18))
	part(m, "TopperHandle", V3(0.35, 3.2, 0.35), c, BROWN)
	part(m, "TopperGrip", V3(1.1, 0.3, 0.35), c * CFrame.new(0, 1.6, 0), BROWN)
	part(m, "TopperBlade", V3(1.3, 1.5, 0.25), c * CFrame.new(0, -1.9, 0), STEEL, Mat.Metal)
end

-- a racing tyre on its edge
function TOPPERS.Speedway(m, top)
	disc(m, "TopperTyre", 1.0, 2.6, top * CFrame.new(0, 1.3, 0), INK)
	disc(m, "TopperHub", 1.1, 1.1, top * CFrame.new(0, 1.3, 0), STEEL, Mat.Metal)
end

-- Kongo's banana
function TOPPERS.Jungle(m, top)
	local c = top * CFrame.new(0, 1.2, 0)
	part(m, "TopperBanana", V3(1.2, 0.7, 0.7), c, YELLOW)
	part(m, "TopperBanana", V3(1.1, 0.65, 0.65), c * CFrame.new(-1.0, 0.35, 0) * CFrame.Angles(0, 0, math.rad(35)), YELLOW)
	part(m, "TopperBanana", V3(1.1, 0.65, 0.65), c * CFrame.new(1.0, 0.35, 0) * CFrame.Angles(0, 0, math.rad(-35)), YELLOW)
	part(m, "TopperStalk", V3(0.3, 0.4, 0.3), c * CFrame.new(1.55, 0.8, 0), BROWN)
end

-- Scribble's pencil
function TOPPERS.Canvas(m, top)
	local c = top * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0, math.rad(60))
	part(m, "TopperPencil", V3(0.6, 2.6, 0.6), c, YELLOW)
	part(m, "TopperEraser", V3(0.62, 0.5, 0.62), c * CFrame.new(0, 1.5, 0), RGB(246, 117, 122))
	part(m, "TopperTip", V3(0.4, 0.5, 0.4), c * CFrame.new(0, -1.5, 0), RGB(234, 212, 170))
	part(m, "TopperLead", V3(0.18, 0.25, 0.18), c * CFrame.new(0, -1.85, 0), INK)
end

local function cabinet(parent, cf, id, machine, pack)
	local m = Instance.new("Model")
	m.Name = "Cabinet_" .. id
	local body = machine and machine.Body or SLATE
	local side = machine and machine.Side or NIGHT
	local light = machine and machine.Light or STEEL
	-- (in the cabinet's own space: -Z is its front)
	local function at(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	local foot = part(m, "Foot", V3(4.6, 0.6, 3.6), at(0, 0.3, 0), INK)
	local shell = part(m, "Body", V3(4.4, 7.2, 3.4), at(0, 4.2, 0), body)
	m.PrimaryPart = shell
	-- the sides, in the pack's second colour, with a glowing edge at the front
	for _, x in ipairs({ -2.25, 2.25 }) do
		part(m, "SideArt", V3(0.12, 6.8, 3.2), at(x, 4.2, 0.05), side)
		neon(m, "SideGlow", V3(0.16, 6.8, 0.16), at(x, 4.2, -1.66), light)
	end
	-- the coin door, two glowing token slots
	part(m, "CoinDoor", V3(1.8, 1.7, 0.12), at(0, 2.0, -1.74), INK)
	for _, x in ipairs({ -0.4, 0.4 }) do
		neon(m, "CoinSlot", V3(0.3, 0.6, 0.12), at(x, 2.2, -1.8), ORANGE)
	end
	-- the control deck: a joystick and two buttons
	part(m, "Deck", V3(4.6, 0.6, 1.4), at(0, 4.1, -2.4), side)
	part(m, "DeckEdge", V3(4.6, 0.15, 0.15), at(0, 4.45, -3.05), INK)
	part(m, "Stick", V3(0.2, 0.7, 0.2), at(-1.2, 4.7, -2.4), INK)
	ball(m, "StickBall", 0.55, at(-1.2, 5.1, -2.4), PINK)
	neon(m, "ButtonA", V3(0.5, 0.2, 0.5), at(0.6, 4.45, -2.4), CYAN)
	neon(m, "ButtonB", V3(0.5, 0.2, 0.5), at(1.4, 4.45, -2.3), YELLOW)
	-- the lever on the right side (as you face it), like a slot machine's (ArcadeClient pulls
	-- it when someone spins): a hub, an arm and a red ball on top
	part(m, "LeverHub", V3(0.4, 0.7, 0.7), at(-2.42, 4.6, -0.7), INK)
	part(m, "LeverArm", V3(0.18, 2.0, 0.18), at(-2.5, 5.6, -0.7), STEEL)
	ball(m, "LeverBall", 0.62, at(-2.5, 6.65, -0.7), PINK)
	-- the screen, in a black bezel (ArcadeClient draws on it)
	part(m, "Bezel", V3(3.9, 2.9, 0.2), at(0, 6.0, -1.72), INK)
	local screen = part(m, "Screen", V3(3.3, 2.3, 0.1), at(0, 6.0, -1.86), RGB(18, 78, 137), Mat.SmoothPlastic, { CastShadow = false })
	local g = screenGui(screen, Enum.NormalId.Front, 60)
	local bg = Instance.new("Frame")
	bg.Name = "Back"
	bg.BackgroundColor3 = INK
	bg.BorderSizePixel = 0
	bg.Size = UDim2.fromScale(1, 1)
	bg.Parent = g
	label(bg, "Title", string.upper(pack and pack.Id or id), light, UDim2.fromScale(0.05, 0.12), UDim2.fromScale(0.9, 0.36))
	label(bg, "Status", machine and "INSERT TOKEN" or "COMING SOON", WHITE, UDim2.fromScale(0.1, 0.6), UDim2.fromScale(0.8, 0.24))
	-- the marquee over the screen: the pack's name, lit
	local marquee = part(m, "Marquee", V3(4.6, 1.4, 1.3), at(0, 8.5, -1.05), light, Mat.SmoothPlastic, { CastShadow = false })
	local mg = screenGui(marquee, Enum.NormalId.Front, 40)
	label(mg, "Name", string.upper(pack and pack.Id or id), INK, UDim2.fromScale(0.04, 0.08), UDim2.fromScale(0.92, 0.84))
	neon(m, "MarqueeGlow", V3(4.6, 0.18, 1.3), at(0, 9.29, -1.05), light)
	part(m, "Hood", V3(4.4, 1.4, 2.1), at(0, 8.5, 0.65), body)
	if machine and TOPPERS[id] then
		TOPPERS[id](m, at(0, 9.2, 0.2))
	end
	m:SetAttribute("Machine", id)
	CollectionService:AddTag(m, "ArcadeCabinet")
	m.Parent = parent
	return m, screen, foot
end

-- makes a finished model `s` times bigger round `pivot` (a spot on the floor
-- under it, so it stays standing there); its screens' words grow with it
local function scaleModel(model, pivot, s)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local rel = pivot:ToObjectSpace(d.CFrame)
			d.Size = d.Size * s
			d.CFrame = pivot * (rel - rel.Position + rel.Position * s)
		end
	end
end

-- the machines (and the token machine) are built this much bigger than
-- their parts below say (I asked for them 1.5x bigger)
local MACHINE_SCALE = 1.5

----------------------------------------------------------------------
-- The whole building. Everything is laid out round the entrance's middle
-- line (CX), which lines up with the path from the road; the anchor
-- (Config.Stations.Arcade) stays where it was.
----------------------------------------------------------------------
local FT = 1.8 -- the floor's top (two steps up from the path)
local CX = -4 -- the entrance's middle, lined up with the path
local X0, X1 = -28, 20 -- the floor's sides (48 wide)
local Z0, Z1 = -22, 18 -- its back and front (40 deep)
local WALL_T = 1.5
local WALL_TOP = 33 -- the back wall and the tall ends of the side walls
local CANOPY_Y = 30.5 -- the canopy's underside
local CANOPY_FRONT = -3 -- the canopy covers the machines, back to here
local PLINTH_H = 0.8
local WALL = PURPLE -- the walls (the palette's purple)
local TRIM = NIGHT -- their base, caps and corner posts

-- a thin neon tube from (x0, y0) to (x1, y1) on a flat face `f` (x across, y up)
local function tube(parent, name, f, x0, y0, x1, y1, t, color)
	local dx, dy = x1 - x0, y1 - y0
	local len = math.sqrt(dx * dx + dy * dy) + t
	return neon(parent, name, V3(len, t, t), f * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, 0) * CFrame.Angles(0, 0, math.atan2(dy, dx)), color)
end

-- the letters of the ARCADE sign as tube strokes (0..1 across and up)
local LETTERS = {
	A = { { 0, 0, 0.5, 1 }, { 0.5, 1, 1, 0 }, { 0.22, 0.42, 0.78, 0.42 } },
	R = { { 0, 0, 0, 1 }, { 0, 1, 0.7, 1 }, { 0.7, 1, 1, 0.8 }, { 1, 0.8, 1, 0.7 }, { 1, 0.7, 0.7, 0.5 }, { 0.7, 0.5, 0, 0.5 }, { 0.45, 0.5, 1, 0 } },
	C = { { 1, 1, 0.3, 1 }, { 0.3, 1, 0, 0.75 }, { 0, 0.75, 0, 0.25 }, { 0, 0.25, 0.3, 0 }, { 0.3, 0, 1, 0 } },
	D = { { 0, 0, 0, 1 }, { 0, 1, 0.6, 1 }, { 0.6, 1, 1, 0.7 }, { 1, 0.7, 1, 0.3 }, { 1, 0.3, 0.6, 0 }, { 0.6, 0, 0, 0 } },
	E = { { 0, 0, 0, 1 }, { 0, 1, 1, 1 }, { 0, 0.5, 0.8, 0.5 }, { 0, 0, 1, 0 } },
}

local function light(parent, class, props)
	local l = Instance.new(class)
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

-- a chasing bulb (ArcadeClient lights them in turn)
local function bulb(parent, cf, index)
	local b = ball(parent, "Bulb", 0.5, cf, GOLD, Mat.Neon)
	b.CastShadow = false
	b.CanCollide = false
	b:SetAttribute("Index", index)
	CollectionService:AddTag(b, "ArcadeBulb")
	return b
end

-- the arcade token's two faces: a purple middle with a star
local function tokenFaces(coin)
	for _, face in ipairs({ Enum.NormalId.Left, Enum.NormalId.Right }) do
		local g = screenGui(coin, face, 30)
		local f = Instance.new("Frame")
		f.BackgroundColor3 = PURPLE
		f.Size = UDim2.fromScale(0.78, 0.78)
		f.Position = UDim2.fromScale(0.11, 0.11)
		f.Parent = g
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = f
		label(f, "Star", "★", YELLOW, UDim2.fromScale(0.1, 0.05), UDim2.fromScale(0.8, 0.8))
	end
end

-- where the five machines stand: a gentle curve round the back, each turned
-- to look at the entrance (x, z, turn)
local function machineSpots(count)
	local spots = {}
	local cx, cz, r = CX, 5, 22 -- (the curve's middle and radius)
	local look = V3(CX, 0, 14) -- (they all look at this spot, just inside the arch)
	local stepA = math.rad(26)
	for i = 1, count do
		local a = (i - (count + 1) / 2) * stepA
		local x, z = cx + math.sin(a) * r, cz - math.cos(a) * r
		table.insert(spots, { x = x, z = z, look = look })
	end
	return spots
end
ArcadeBuilder.machineSpots = machineSpots

function ArcadeBuilder.Build(parent)
	local A = Config.Arcade
	local m = folder(parent, "Arcade")
	local O = CFrame.new(Config.Stations.Arcade)
	local function at(x, y, z)
		return O * CFrame.new(x, y, z)
	end
	local W, D = X1 - X0, Z1 - Z0
	local deco = { CanCollide = false }

	-- THE FLOOR: dark arcade carpet with little neon shapes, a glowing trim
	-- all round, and two steps up from the path
	part(m, "ArcadeFloor", V3(W, FT, D), at(CX, FT / 2, (Z0 + Z1) / 2), INK, Mat.Fabric)
	do
		local sx = CX - 9 -- (the steps: as wide as the path)
		part(m, "ArcadeStep", V3(18, 1.4, 2), at(CX, 0.7, Z1 + 1), NIGHT)
		part(m, "ArcadeStep", V3(18, 1.0, 2), at(CX, 0.5, Z1 + 3), NIGHT)
		neon(m, "StepGlow", V3(18, 0.12, 0.25), at(CX, 1.46, Z1 + 0.125), CYAN, deco)
		neon(m, "StepGlow", V3(18, 0.12, 0.25), at(CX, 1.06, Z1 + 2.125), CYAN, deco)
		-- a glowing line along the floor's front edge, either side of the steps
		neon(m, "FloorEdgeGlow", V3(sx - X0, 0.3, 0.12), at((X0 + sx) / 2, FT - 0.4, Z1 + 0.06), MAGENTA, deco)
		neon(m, "FloorEdgeGlow", V3(X1 - (CX + 9), 0.3, 0.12), at((CX + 9 + X1) / 2, FT - 0.4, Z1 + 0.06), MAGENTA, deco)
	end
	-- the trim round the carpet (inside the walls, and across the arch)
	do
		local y = FT + 0.06
		local inX0, inX1 = X0 + WALL_T + 0.25, X1 - WALL_T - 0.25
		local backZ, frontZ = Z0 + WALL_T + 0.25, Z1 - WALL_T
		neon(m, "FloorTrim", V3(inX1 - inX0, 0.12, 0.5), at((inX0 + inX1) / 2, y, backZ + 0.25), MAGENTA, deco)
		neon(m, "FloorTrim", V3(0.5, 0.12, frontZ - backZ - 0.5), at(inX0 + 0.25, y, (backZ + frontZ) / 2 + 0.25), MAGENTA, deco)
		neon(m, "FloorTrim", V3(0.5, 0.12, frontZ - backZ - 0.5), at(inX1 - 0.25, y, (backZ + frontZ) / 2 + 0.25), MAGENTA, deco)
		neon(m, "FloorTrim", V3((CX - 11) - inX0, 0.12, 0.5), at((inX0 + CX - 11) / 2, y, frontZ - 0.25), CYAN, deco)
		neon(m, "FloorTrim", V3(inX1 - (CX + 11), 0.12, 0.5), at((CX + 11 + inX1) / 2, y, frontZ - 0.25), CYAN, deco)
		neon(m, "FloorTrim", V3(16, 0.12, 0.5), at(CX, y, Z1 - 0.3), CYAN, deco)
	end

	local spots = machineSpots(5)

	-- the carpet's pattern: little neon diamonds, dashes and dots, kept off
	-- the machines' plinths, the pedestal and the token machine
	do
		local keepOff = { { CX, 2, 7.5 }, { CX - 15, 11, 6 } }
		for _, s in ipairs(spots) do
			table.insert(keepOff, { s.x, s.z, 6 })
		end
		local colors = { CYAN, YELLOW, MAGENTA, GREEN }
		local n = 0
		for row = 0, 7 do
			local z = Z0 + 4 + row * 4.6
			for col = 0, 9 do
				local x = X0 + 4 + col * 4.8 + (row % 2) * 2.4
				local free = x < X1 - 3.5 and z < Z1 - 3
				for _, k in ipairs(keepOff) do
					if (x - k[1]) ^ 2 + (z - k[2]) ^ 2 < k[3] ^ 2 then
						free = false
					end
				end
				if free then
					n += 1
					local c = colors[(n + row) % #colors + 1]
					local kind = (n * 7 + row) % 3
					local e = { CanCollide = false, CastShadow = false, Transparency = 0.25 }
					if kind == 0 then
						neon(m, "CarpetShape", V3(0.9, 0.1, 0.9), at(x, FT + 0.05, z) * CFrame.Angles(0, math.rad(45), 0), c, e)
					elseif kind == 1 then
						neon(m, "CarpetShape", V3(1.6, 0.1, 0.35), at(x, FT + 0.05, z) * CFrame.Angles(0, math.rad(35 + row * 20), 0), c, e)
					else
						e.Shape = Enum.PartType.Cylinder
						neon(m, "CarpetShape", V3(0.1, 0.9, 0.9), at(x, FT + 0.05, z) * CFrame.Angles(0, 0, math.pi / 2), c, e)
					end
				end
			end
		end
	end

	-- THE WALLS: purple toy-brick walls on a dark base with a dark cap - the
	-- back wall and two side walls that step down to a low wall at the front
	do
		-- a run of wall from (a) to (b) along X or Z, up to `top`
		local function run(name, x0, z0, x1, z1, top, low)
			local alongX = (x1 - x0) > (z1 - z0)
			local len = alongX and (x1 - x0) or (z1 - z0)
			local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
			local function size(t, h)
				return alongX and V3(len, h, t) or V3(t, h, len)
			end
			if low then
				part(m, name, size(WALL_T, top - 0.6), at(cx, (top - 0.6) / 2, cz), WALL)
				part(m, name .. "Cap", size(WALL_T + 0.4, 0.6), at(cx, top - 0.3, cz), TRIM)
				return
			end
			part(m, name .. "Base", size(WALL_T + 0.5, 2.6), at(cx, 1.3, cz), TRIM)
			part(m, name, size(WALL_T, top - 3.8), at(cx, 2.6 + (top - 3.8) / 2, cz), WALL)
			part(m, name .. "Cap", size(WALL_T + 0.4, 1.2), at(cx, top - 0.6, cz), TRIM)
		end
		local bz = Z0 + WALL_T / 2
		local lx, rx = X0 + WALL_T / 2, X1 - WALL_T / 2
		run("BackWall", X0, Z0, X1, Z0 + WALL_T, WALL_TOP)
		for _, x in ipairs({ lx, rx }) do
			run("SideWall", x - WALL_T / 2, Z0 + WALL_T, x + WALL_T / 2, CANOPY_FRONT, WALL_TOP)
			run("SideWallStep", x - WALL_T / 2, CANOPY_FRONT, x + WALL_T / 2, 3, FT + 13)
			run("SideWallLow", x - WALL_T / 2, 3, x + WALL_T / 2, Z1, FT + 3.2, true)
		end
		run("FrontWallLow", X0 + WALL_T, Z1 - WALL_T, CX - 11, Z1, FT + 3.2, true)
		run("FrontWallLow", CX + 11, Z1 - WALL_T, X1 - WALL_T, Z1, FT + 3.2, true)
		-- chunky corner posts, and blocks along the top like the castle's
		for _, c in ipairs({ { X0 + 1, Z0 + 1, WALL_TOP + 1.6 }, { X1 - 1, Z0 + 1, WALL_TOP + 1.6 }, { X0 + 1, Z1 - 1, FT + 5 }, { X1 - 1, Z1 - 1, FT + 5 } }) do
			part(m, "CornerPost", V3(3, c[3], 3), at(c[1], c[3] / 2, c[2]), TRIM)
			part(m, "CornerCap", V3(3.4, 0.6, 3.4), at(c[1], c[3] + 0.3, c[2]), GOLD)
		end
		for i = 0, 7 do
			part(m, "WallBlock", V3(2.6, 1.6, WALL_T + 0.4), at(X0 + 6 + i * 5.1, WALL_TOP + 0.8, bz), WALL)
		end
		for _, x in ipairs({ lx, rx }) do
			for i = 0, 2 do
				part(m, "WallBlock", V3(WALL_T + 0.4, 1.6, 2.6), at(x, WALL_TOP + 0.8, Z0 + 6.5 + i * 5.2), WALL)
			end
		end
		-- neon tubes along the walls, inside (and one outside, facing the road)
		local tz = Z0 + WALL_T + 0.1
		neon(m, "WallTube", V3(W - 2 * WALL_T - 0.4, 0.3, 0.3), at(CX, 22, tz), MAGENTA, deco)
		neon(m, "WallTube", V3(W - 2 * WALL_T - 0.4, 0.3, 0.3), at(CX, FT + 3.4, tz), CYAN, deco)
		for _, x in ipairs({ X0 + WALL_T + 0.1, X1 - WALL_T - 0.1 }) do
			neon(m, "WallTube", V3(0.3, 0.3, CANOPY_FRONT - Z0 - WALL_T - 0.2), at(x, 22, (Z0 + WALL_T + CANOPY_FRONT) / 2), MAGENTA, deco)
			neon(m, "WallTube", V3(0.3, 0.3, 3 - Z0 - WALL_T - 0.2), at(x, FT + 3.4, (Z0 + WALL_T + 3) / 2), CYAN, deco)
			neon(m, "WallTube", V3(0.3, 20, 0.3), at(x, FT + 12, CANOPY_FRONT - 0.3), MAGENTA, deco)
		end
		neon(m, "WallTube", V3(0.3, 0.3, CANOPY_FRONT - Z0 - 3), at(X0 - 0.1, 24, (Z0 + 3 + CANOPY_FRONT) / 2), MAGENTA, deco)
	end

	-- THE CANOPY over the machines (the middle stays open to the sky), glowing
	-- purple underneath, with a small spotlight on each machine
	local canopy = folder(m, "Canopy")
	do
		local inX0, inX1 = X0 + WALL_T, X1 - WALL_T
		local cz0 = Z0 + WALL_T
		local cw, cd = inX1 - inX0, CANOPY_FRONT - cz0
		part(canopy, "Canopy", V3(cw, 1.5, cd), at(CX, CANOPY_Y + 0.75, (cz0 + CANOPY_FRONT) / 2), TRIM)
		part(canopy, "CanopyFascia", V3(cw, 2.4, 0.8), at(CX, CANOPY_Y + 0.5, CANOPY_FRONT - 0.4), WALL)
		neon(canopy, "CanopyGlow", V3(cw, 0.3, 0.2), at(CX, CANOPY_Y - 0.4, CANOPY_FRONT - 0.9), MAGENTA, deco)
		neon(canopy, "CanopyGlow", V3(cw, 0.3, 0.2), at(CX, CANOPY_Y + 1.4, CANOPY_FRONT - 0.9), MAGENTA, deco)
		-- soft purple light panels under it
		for _, z in ipairs({ cz0 + 4, CANOPY_FRONT - 5 }) do
			local strip = neon(canopy, "CanopyLight", V3(cw - 8, 0.2, 0.6), at(CX, CANOPY_Y - 0.1, z), PURPLE, { CanCollide = false, Transparency = 0.2 })
			light(strip, "PointLight", { Color = MAGENTA, Range = 30, Brightness = 1.2, Shadows = false })
		end
		-- drifting sparkles under the canopy
		local zone = part(canopy, "SparkleZone", V3(cw - 6, 1, cd - 4), at(CX, 20, (cz0 + CANOPY_FRONT) / 2), WHITE, Mat.SmoothPlastic, {
			Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
		})
		light(zone, "ParticleEmitter", {
			Name = "Sparkles",
			Rate = 5,
			Lifetime = NumberRange.new(3, 5),
			Speed = NumberRange.new(0.4, 1.2),
			SpreadAngle = Vector2.new(180, 180),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
			Color = ColorSequence.new(RGB(255, 190, 240), CYAN),
			LightEmission = 1,
		})
	end

	-- THE MACHINES: the launch packs in a curve round the back, in floor
	-- order from left to right, each on a plinth in its pack's colour
	local packs = {}
	for _, p in ipairs(Config.Weapons.Packs or {}) do
		if A.Machines[p.Id] then
			table.insert(packs, p)
		end
	end
	table.sort(packs, function(a, b)
		return a.Floor < b.Floor
	end)
	spots = machineSpots(#packs)
	for i, p in ipairs(packs) do
		local s, mc = spots[i], A.Machines[p.Id]
		local base = CFrame.lookAt(at(s.x, 0, s.z).Position, (O * CFrame.new(s.look)).Position)
		local cf = base + V3(0, FT + PLINTH_H, 0)
		part(m, "Plinth", V3(8.4, PLINTH_H, 6.8), cf * CFrame.new(0, -PLINTH_H / 2, -0.5), mc.Body)
		neon(m, "PlinthGlow", V3(8.4, 0.2, 0.2), cf * CFrame.new(0, -0.25, -3.95), mc.Light, deco)
		local cab, screen = cabinet(m, cf, p.Id, mc, p)
		scaleModel(cab, cf, MACHINE_SCALE)
		-- its spotlight, hanging from the canopy and pointing at its screen
		local lampPos = (cf * CFrame.new(0, 0, -5.5)).Position
		lampPos = V3(lampPos.X, CANOPY_Y - 1.4, lampPos.Z)
		part(canopy, "SpotRod", V3(0.3, 1, 0.3), CFrame.new(lampPos + V3(0, 0.9, 0)), INK, nil, deco)
		local lamp = part(canopy, "SpotLamp", V3(1, 1, 1.2), CFrame.lookAt(lampPos, screen.Position), INK, nil, deco)
		neon(canopy, "SpotLens", V3(0.7, 0.7, 0.1), lamp.CFrame * CFrame.new(0, 0, -0.62), WHITE, deco)
		light(lamp, "SpotLight", { Face = Enum.NormalId.Front, Angle = 38, Range = 30, Brightness = 2, Color = mc.Light, Shadows = false })
	end

	-- THE ENTRANCE ARCH facing the path: chunky posts, a lintel with the
	-- ARCADE sign in thin neon tubes, bulbs chasing round the opening, and
	-- the giant token turning on top (seen from the fountain)
	do
		local ARCH_H = FT + 12 -- (the opening's top)
		local LIN_TOP = ARCH_H + 4.5
		local fz = Z1 + 0.2 -- (the posts' front)
		for _, sx in ipairs({ -1, 1 }) do
			local x = CX + sx * 9.5
			part(m, "ArchBase", V3(4, 2.6, 4), at(x, 1.3, Z1 - 1.4), TRIM)
			part(m, "ArchPost", V3(3, ARCH_H - 2.6, 3.2), at(x, 2.6 + (ARCH_H - 2.6) / 2, Z1 - 1.4), WALL)
			neon(m, "ArchGlow", V3(0.25, ARCH_H - 3.2, 0.25), at(CX + sx * 8.1, 2.9 + (ARCH_H - 3.2) / 2, fz + 0.05), CYAN, deco)
		end
		part(m, "ArchLintel", V3(24, LIN_TOP - ARCH_H, 3.8), at(CX, (ARCH_H + LIN_TOP) / 2, Z1 - 1.5), WALL)
		part(m, "ArchBand", V3(24.6, 0.8, 4.2), at(CX, ARCH_H + 0.4, Z1 - 1.5), TRIM)
		part(m, "ArchBand", V3(24.6, 0.8, 4.2), at(CX, LIN_TOP + 0.4, Z1 - 1.5), TRIM)
		part(m, "ArchCrown", V3(10, 1.4, 3), at(CX, LIN_TOP + 1.5, Z1 - 1.5), WALL)
		for _, sx in ipairs({ -1, 1 }) do
			part(m, "ArchCrownStep", V3(3, 0.7, 3), at(CX + sx * 6.5, LIN_TOP + 1.15, Z1 - 1.5), WALL)
		end
		-- the sign: a dark board on the lintel, the word in thin tubes
		local signZ = Z1 + 0.4 + 0.15
		local signY = (ARCH_H + 0.8 + LIN_TOP) / 2
		part(m, "SignBoard", V3(16.4, 3.1, 0.3), at(CX, signY, signZ), INK)
		for _, dy in ipairs({ -1.6, 1.6 }) do
			neon(m, "SignEdge", V3(16.6, 0.14, 0.14), at(CX, signY + dy, signZ + 0.1), CYAN, deco)
		end
		local face = at(CX, signY, signZ + 0.2)
		local word, lw, lh, gap = "ARCADE", 1.6, 2.0, 0.65
		local x = -(#word * lw + (#word - 1) * gap) / 2
		for i = 1, #word do
			for _, s in ipairs(LETTERS[string.sub(word, i, i)]) do
				tube(m, "SignLetter", face, x + s[1] * lw, -lh / 2 + s[2] * lh, x + s[3] * lw, -lh / 2 + s[4] * lh, 0.22, MAGENTA)
			end
			x += lw + gap
		end
		-- the bulbs: up the left post, along the lintel, down the right post
		local n = 0
		for i = 0, 7 do
			n += 1
			bulb(m, at(CX - 8.6, FT + 1 + i * 1.45, fz + 0.2), n)
		end
		for i = 0, 10 do
			n += 1
			bulb(m, at(CX - 8 + i * 1.6, ARCH_H + 1.05, Z1 + 0.65), n)
		end
		for i = 7, 0, -1 do
			n += 1
			bulb(m, at(CX + 8.6, FT + 1 + i * 1.45, fz + 0.2), n)
		end
		-- THE GIANT TOKEN on top, turning (LobbyFX spins it)
		part(m, "TokenPad", V3(0.6, 4, 4), at(CX, LIN_TOP + 2.5, Z1 - 1.5) * CFrame.Angles(0, 0, math.pi / 2), GOLD, nil, { Shape = Enum.PartType.Cylinder })
		local coin = disc(m, "GiantToken", 0.9, 7, at(CX, LIN_TOP + 7, Z1 - 1.5), GOLD, Mat.SmoothPlastic)
		coin.CastShadow = false
		tokenFaces(coin)
		coin:SetAttribute("SpinSpeed", 70)
		coin:SetAttribute("BobAmp", 0.6)
		coin:SetAttribute("BobSpeed", 1.6)
		CollectionService:AddTag(coin, "FX")
		light(coin, "PointLight", { Color = GOLD, Range = 14, Brightness = 1, Shadows = false })
	end

	-- THE TOKEN MACHINE, just inside beside the arch: gold, a big glowing coin
	-- slot (the Robux shop, later)
	do
		local tcf = at(CX - 15, FT + 0.4, 11) * CFrame.Angles(0, math.rad(-70), 0)
		local t = Instance.new("Model")
		t.Name = "TokenMachine"
		local shell = part(t, "Body", V3(4.4, 7.6, 3.4), tcf * CFrame.new(0, 4.6, 0), GOLD)
		t.PrimaryPart = shell
		part(t, "Foot", V3(4.6, 0.8, 3.6), tcf * CFrame.new(0, 0.4, 0), INK)
		part(t, "Face", V3(3.6, 5.6, 0.2), tcf * CFrame.new(0, 4.6, -1.75), PURPLE)
		disc(t, "BigSlot", 0.3, 2.2, tcf * CFrame.new(0, 5.6, -1.9), INK)
		neon(t, "SlotGlow", V3(0.4, 1.4, 0.2), tcf * CFrame.new(0, 5.6, -2.0), YELLOW)
		part(t, "Tray", V3(2.6, 0.5, 1.0), tcf * CFrame.new(0, 2.4, -2.1), INK)
		local sign = part(t, "Marquee", V3(4.6, 1.4, 1.3), tcf * CFrame.new(0, 9.1, -1.05), YELLOW, Mat.SmoothPlastic, { CastShadow = false })
		label(screenGui(sign, Enum.NormalId.Front, 40), "Name", "TOKENS", INK, UDim2.fromScale(0.04, 0.08), UDim2.fromScale(0.92, 0.84))
		neon(t, "MarqueeGlow", V3(4.6, 0.18, 1.3), tcf * CFrame.new(0, 9.89, -1.05), YELLOW)
		local g = screenGui(part(t, "Screen", V3(3.0, 1.2, 0.1), tcf * CFrame.new(0, 3.6, -1.9), INK), Enum.NormalId.Front, 60)
		label(g, "Text", "GET TOKENS", YELLOW, UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.8))
		scaleModel(t, tcf, MACHINE_SCALE)
		CollectionService:AddTag(t, "ArcadeTokens")
		t.Parent = m
		part(m, "TokenPlinth", V3(8.4, 0.4, 7.2), tcf * CFrame.new(0, -0.2, -0.4), NIGHT)
	end

	-- THE PRIZE PEDESTAL in the open middle: the Slime machine's Secret weapon
	-- turns over it, in a cone of light
	do
		local px, pz = CX, 2
		local up = CFrame.Angles(0, 0, math.pi / 2) -- (a cylinder standing up)
		part(m, "PrizeStep", V3(0.8, 11, 11), at(px, FT + 0.4, pz) * up, TRIM, nil, { Shape = Enum.PartType.Cylinder })
		neon(m, "PrizeStepGlow", V3(0.16, 11.3, 11.3), at(px, FT + 0.55, pz) * up, CYAN, { Shape = Enum.PartType.Cylinder, CanCollide = false })
		local top = FT + 0.8 + 4
		local base = part(m, "PrizeBase", V3(4, 7, 7), at(px, top - 2, pz) * up, PURPLE, Mat.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
		neon(m, "PrizeRing", V3(0.3, 7.4, 7.4), at(px, top - 0.1, pz) * up, YELLOW, { Shape = Enum.PartType.Cylinder })
		local beam = neon(m, "PrizeBeam", V3(0.2, 6, 6), at(px, top + 0.1, pz) * up, WHITE, { Shape = Enum.PartType.Cylinder, Transparency = 0.6 })
		-- the cone of light rising from it, in steps
		for i, c in ipairs({ { 6, 2.6, 0.84 }, { 4.6, 2.4, 0.88 }, { 3.2, 2.2, 0.92 } }) do
			local y0 = top + 0.2 + (i - 1) * 2.6
			neon(m, "PrizeCone", V3(c[2], c[1], c[1]), at(px, y0 + c[2] / 2, pz) * up, YELLOW, {
				Shape = Enum.PartType.Cylinder, Transparency = c[3], CanCollide = false, CanQuery = false,
			})
		end
		light(beam, "PointLight", { Color = YELLOW, Range = 16, Brightness = 1.5, Shadows = false })
		light(beam, "ParticleEmitter", {
			Name = "Sparkles",
			Rate = 4,
			Lifetime = NumberRange.new(2, 3),
			Speed = NumberRange.new(1, 2),
			SpreadAngle = Vector2.new(20, 20),
			EmissionDirection = Enum.NormalId.Right, -- (the cylinder's end: up)
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
			Color = ColorSequence.new(YELLOW, WHITE),
			LightEmission = 1,
		})
		base:SetAttribute("Machine", "Slime")
		CollectionService:AddTag(base, "ArcadePrize")
	end

	-- THE BIG WINS board: a scoreboard on the back wall, over the machines
	-- and under the canopy, with a frame of chasing bulbs
	do
		local WY, WZ = 26.6, Z0 + WALL_T
		part(m, "WinsFrame", V3(27.4, 8.2, 0.5), at(CX, WY, WZ + 0.25), TRIM)
		local board = part(m, "WinsBoard", V3(26, 6.8, 0.4), at(CX, WY, WZ + 0.7), INK)
		for _, dy in ipairs({ -3.75, 3.75 }) do
			neon(m, "WinsEdge", V3(27.4, 0.3, 0.3), at(CX, WY + dy, WZ + 0.65), YELLOW, deco)
		end
		for i = 0, 11 do
			bulb(m, at(CX - 12.65 + i * 2.3, WY + 4.3, WZ + 0.4), 40 + i)
			bulb(m, at(CX - 12.65 + i * 2.3, WY - 4.3, WZ + 0.4), 60 - i)
		end
		local g = screenGui(board, Enum.NormalId.Back, 30) -- (its back faces into the room)
		label(g, "Title", "BIG WINS", YELLOW, UDim2.fromScale(0.3, 0.04), UDim2.fromScale(0.4, 0.26))
		label(g, "Lines", "Spin a LEGENDARY or better to get your name up here!", WHITE, UDim2.fromScale(0.04, 0.34), UDim2.fromScale(0.92, 0.6), {
			TextWrapped = true,
		})
		CollectionService:AddTag(board, "ArcadeWins")
	end

	-- walking in (anywhere inside the walls) opens the Arcade menu (ArcadeClient)
	local zone = part(m, "AutoOpenZone", V3(W - 2 * WALL_T, 14, Z1 + 0.2 - (Z0 + WALL_T)), at(CX, FT + 7, (Z0 + WALL_T + Z1 + 0.2) / 2), WHITE, Mat.SmoothPlastic, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	zone:SetAttribute("Activity", "Arcade")
	CollectionService:AddTag(zone, "AutoOpenZone")
	return m
end

return ArcadeBuilder
