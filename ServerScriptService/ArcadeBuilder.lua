--[[
	ArcadeBuilder  (ModuleScript, parent: ServerScriptService, name: "ArcadeBuilder")

	THE ARCADE, where the forge used to be (north-east of the fountain, at
	Config.Stations.Arcade): open to the sky - a checkered floor with glowing
	edges, and over the front a big pixel "ARCADE" sign on two posts, with
	blinking marquee bulbs along it and a giant spinning token over it, so it
	can be seen from the spawn. LobbyBuilder calls ArcadeBuilder.Build(lobby).

	Inside:
	  * the MACHINES: one arcade cabinet per weapon pack along the back
	    (Config.Arcade.Machines), each painted like its boss with a topper
	    (Oozark's slime, a shovel, a tyre, a banana, a pencil); the update
	    packs' machines join them when their packs come (the sides are open)
	  * the TOKEN MACHINE (the Robux shop, later) at the front right
	  * the PRIZE PEDESTAL in the middle (the Slime machine's Secret weapon
	    floats and turns over it: ArcadeClient puts it there)
	  * the BIG WINS board hanging at the back (ArcadeClient writes the
	    lobby's latest Legendary-or-better spins on it)
	  * a walk-in box over the whole floor (AutoOpenZone, Activity =
	    "Arcade"): walking in opens the Arcade menu (ArcadeClient)

	Tagged for the screens: each cabinet is a Model tagged "ArcadeCabinet"
	(attribute Machine = the pack's id) with a
	"Screen" and a "Marquee" part; the bulbs are tagged "ArcadeBulb" (Index);
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
-- The pixel letters of the sign (5 wide, 7 tall)
----------------------------------------------------------------------
local LETTERS = {
	A = { ".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#" },
	R = { "####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#" },
	C = { ".####", "#....", "#....", "#....", "#....", "#....", ".####" },
	D = { "####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####." },
	E = { "#####", "#....", "#....", "####.", "#....", "#....", "#####" },
}

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
-- The whole building
----------------------------------------------------------------------
function ArcadeBuilder.Build(parent)
	local A = Config.Arcade
	local m = folder(parent, "Arcade")
	local O = CFrame.new(Config.Stations.Arcade or Config.Stations.Craft)
	local function at(x, y, z)
		return O * CFrame.new(x, y, z)
	end
	local HALF = 20 -- the floor is 40 x 40 studs
	local SIGN_Y = 22.6 -- the middle of the ARCADE sign over the front

	-- THE FLOOR: dark with purple checks, glowing edges, a mat to the path
	part(m, "ArcadeFloor", V3(HALF * 2, 0.8, HALF * 2), at(0, 0.4, 0), INK)
	for i = 0, 7 do
		for j = 0, 7 do
			if (i + j) % 2 == 0 then
				part(m, "FloorCheck", V3(5, 0.1, 5), at(-17.5 + i * 5, 0.85, -17.5 + j * 5), PURPLE, Mat.SmoothPlastic, { CastShadow = false })
			end
		end
	end
	neon(m, "FloorGlow", V3(HALF * 2, 0.15, 0.4), at(0, 0.82, HALF - 0.2), CYAN)
	neon(m, "FloorGlow", V3(HALF * 2, 0.15, 0.4), at(0, 0.82, -HALF + 0.2), MAGENTA)
	neon(m, "FloorGlow", V3(0.4, 0.15, HALF * 2), at(-HALF + 0.2, 0.82, 0), MAGENTA)
	neon(m, "FloorGlow", V3(0.4, 0.15, HALF * 2), at(HALF - 0.2, 0.82, 0), MAGENTA)
	part(m, "EntryMat", V3(18, 0.6, 3), at(-4, 0.3, HALF + 1.5), NIGHT)

	-- NO ROOF: open to the sky (I asked for the roof gone). Two posts at the
	-- front corners hold up the sign.
	for _, px in ipairs({ -19.2, 19.2 }) do
		part(m, "SignPost", V3(1.6, SIGN_Y - 0.8, 1.6), at(px, 0.8 + (SIGN_Y - 0.8) / 2, HALF - 0.8), NIGHT)
		neon(m, "SignPostGlow", V3(0.3, SIGN_Y - 5.8, 0.3), at(px - 0.8 * math.sign(px), 0.8 + (SIGN_Y - 5.8) / 2 + 0.6, HALF - 0.8), CYAN)
	end

	-- THE SIGN over the front: ARCADE in pixel letters, a different colour each
	local signCf = at(0, SIGN_Y, HALF + 0.4)
	part(m, "SignBoard", V3(38, 9.2, 1), signCf, INK)
	neon(m, "SignEdge", V3(38.4, 0.4, 1.1), signCf * CFrame.new(0, 4.6, 0), CYAN)
	neon(m, "SignEdge", V3(38.4, 0.4, 1.1), signCf * CFrame.new(0, -4.6, 0), CYAN)
	neon(m, "SignEdge", V3(0.4, 9.2, 1.1), signCf * CFrame.new(-19, 0, 0), CYAN)
	neon(m, "SignEdge", V3(0.4, 9.2, 1.1), signCf * CFrame.new(19, 0, 0), CYAN)
	local word = "ARCADE"
	local colors = { CYAN, PINK, YELLOW, GREEN, ORANGE, MAGENTA }
	for li = 1, #word do
		local rows = LETTERS[string.sub(word, li, li)]
		local x0 = -17.5 + (li - 1) * 6
		for r, row in ipairs(rows) do
			for c = 1, 5 do
				if string.sub(row, c, c) == "#" then
					neon(m, "SignPixel", V3(0.9, 0.9, 0.4), signCf * CFrame.new(x0 + (c - 1) + 0.5, 3 - (r - 1), 0.62), colors[li])
				end
			end
		end
	end
	-- marquee bulbs along its top and bottom (ArcadeClient runs lights along them)
	local n = 0
	for _, y in ipairs({ -5.05, 5.05 }) do
		for x = -19, 19, 2 do
			n = n + 1
			local b = ball(m, "Bulb", 0.7, signCf * CFrame.new(x, y, 0.55), YELLOW, Mat.Neon)
			b.CastShadow = false
			b:SetAttribute("Index", n)
			CollectionService:AddTag(b, "ArcadeBulb")
		end
	end
	-- the giant token over it, turning (LobbyFX spins it)
	local coin = disc(m, "GiantToken", 0.9, 7, at(0, SIGN_Y + 9.2, HALF + 0.4), GOLD, Mat.SmoothPlastic)
	coin.CastShadow = false
	for _, face in ipairs({ Enum.NormalId.Left, Enum.NormalId.Right }) do
		local g = screenGui(coin, face, 30)
		local face2 = Instance.new("Frame")
		face2.BackgroundColor3 = PURPLE
		face2.Size = UDim2.fromScale(0.78, 0.78)
		face2.Position = UDim2.fromScale(0.11, 0.11)
		face2.Parent = g
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = face2
		label(face2, "Star", "★", YELLOW, UDim2.fromScale(0.1, 0.05), UDim2.fromScale(0.8, 0.8))
	end
	coin:SetAttribute("SpinSpeed", 70)
	coin:SetAttribute("BobAmp", 0.6)
	coin:SetAttribute("BobSpeed", 1.6)
	CollectionService:AddTag(coin, "FX")

	-- THE MACHINES: the launch packs along the back, in floor order
	local packs = {}
	for _, p in ipairs(Config.Weapons.Packs or {}) do
		if A.Machines[p.Id] then
			table.insert(packs, p)
		end
	end
	table.sort(packs, function(a, b)
		return a.Floor < b.Floor
	end)
	local spacing = 8
	local first = -spacing * (#packs - 1) / 2
	for i, p in ipairs(packs) do
		local cf = at(first + (i - 1) * spacing, 0.8, -14) * CFrame.Angles(0, math.pi, 0)
		scaleModel(cabinet(m, cf, p.Id, A.Machines[p.Id], p), cf, MACHINE_SCALE)
	end
	-- (the update packs' machines come with their packs: the sides stay open
	-- until then - covered ones there crowded the room)

	-- THE TOKEN MACHINE: gold, a big glowing coin slot (the Robux shop, later)
	do
		local tcf = at(16.5, 0.8, 8) * CFrame.Angles(0, math.pi / 2, 0)
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
	end

	-- THE PRIZE PEDESTAL: the Slime machine's Secret weapon turns over it
	do
		local base = part(m, "PrizeBase", V3(3, 5, 5), at(0, 0.8 + 1.5, 4) * CFrame.Angles(0, 0, math.pi / 2), NIGHT, Mat.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
		neon(m, "PrizeRing", V3(0.3, 5.3, 5.3), at(0, 3.9, 4) * CFrame.Angles(0, 0, math.pi / 2), YELLOW, { Shape = Enum.PartType.Cylinder })
		neon(m, "PrizeBeam", V3(0.2, 4.2, 4.2), at(0, 4.1, 4) * CFrame.Angles(0, 0, math.pi / 2), WHITE, { Shape = Enum.PartType.Cylinder, Transparency = 0.6 })
		base:SetAttribute("Machine", "Slime")
		CollectionService:AddTag(base, "ArcadePrize")
	end

	-- THE BIG WINS board, up on two posts at the back, over the machines
	do
		local WINS_Y, WZ = 23.5, -HALF + 1.4
		local board = part(m, "WinsBoard", V3(26, 6, 0.4), at(0, WINS_Y, WZ), INK)
		neon(m, "WinsEdge", V3(26.4, 0.35, 0.5), at(0, WINS_Y + 3.15, WZ), YELLOW)
		neon(m, "WinsEdge", V3(26.4, 0.35, 0.5), at(0, WINS_Y - 3.15, WZ), YELLOW)
		for _, x in ipairs({ -12, 12 }) do
			part(m, "WinsPost", V3(1, WINS_Y - 0.8, 1), at(x, 0.8 + (WINS_Y - 0.8) / 2, WZ - 0.7), NIGHT)
		end
		local g = screenGui(board, Enum.NormalId.Back, 30) -- (its back faces into the room)
		label(g, "Title", "BIG WINS", YELLOW, UDim2.fromScale(0.3, 0.04), UDim2.fromScale(0.4, 0.26))
		label(g, "Lines", "Spin a LEGENDARY or better to get your name up here!", WHITE, UDim2.fromScale(0.04, 0.34), UDim2.fromScale(0.92, 0.6), {
			TextWrapped = true,
		})
		CollectionService:AddTag(board, "ArcadeWins")
	end

	-- walking onto the floor opens the Arcade menu (ArcadeClient)
	local zone = part(m, "AutoOpenZone", V3(HALF * 2, 12, HALF * 2), at(0, 6.8, 0), WHITE, Mat.SmoothPlastic, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	zone:SetAttribute("Activity", "Arcade")
	CollectionService:AddTag(zone, "AutoOpenZone")

	-- and the giant token on the stream's bank, where the forge's waterwheel was
	ArcadeBuilder.BuildTokenStatue(m, O.X + 23.2, O.Z)
	return m
end

-- THE GIANT TOKEN by the stream (where the forge's waterwheel was): a stone
-- plinth on the bank with an arcade token turning on it
function ArcadeBuilder.BuildTokenStatue(parent, x, z)
	local m = folder(parent, "TokenStatue")
	part(m, "Plinth", V3(4, 3, 4), CFrame.new(x, 1.5, z), SLATE)
	part(m, "PlinthTop", V3(4.4, 0.4, 4.4), CFrame.new(x, 3.2, z), NIGHT)
	local coin = disc(m, "StatueToken", 0.8, 6, CFrame.new(x, 7, z) * CFrame.Angles(0, math.pi / 2, 0), GOLD, Mat.SmoothPlastic)
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
	coin:SetAttribute("SpinSpeed", 60)
	coin:SetAttribute("BobAmp", 0.4)
	CollectionService:AddTag(coin, "FX")
	return m
end

return ArcadeBuilder
