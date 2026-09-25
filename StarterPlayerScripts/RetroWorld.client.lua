--[[
	RetroWorld  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "RetroWorld")

	The lobby in the game's modern-retro look, to match the screens (RetroUI):

	  * THE PALETTE - every colour in the lobby snapped to the same 32-colour
	    pixel-art palette the menus use, so the world and the screens match
	  * FLAT COLOUR - realistic textures (cobblestone, slate, metal, planks...)
	    become clean flat colour: the low-poly look of modern retro 3D games
	    (Pokemon Let's Go, A Short Hike)
	  * PIXEL MOTES - little glowing cubes drifting up around you, moving in
	    steps like a sprite would (Stardew Valley / Celeste)
	  * THE SAVE STAR - a spinning pixel star over the spawn (Undertale)
	  * FLAVOUR TEXT - walk up to a shop, the shrine, the yard or the Spire and
	    a black box types a line about it at the bottom of the screen, with
	    a blip a letter (Undertale)
	  * A WARMER, PUNCHIER GRADE - only while you're in the lobby
	  * DETAIL - stone courses and chunky stones on the castle walls, pixel
	    flames and smoke in place of the old fire effects, grass and flowers
	    on the lawns, glowing pylons and sparks round the training pads,
	    sparks at the shrine, voxel clouds and flocks of birds circling the
	    island, and a beacon of light rising from the Spire's peak

	SAFE BY DESIGN: all of it happens on your own screen only, and it only ever
	changes how things LOOK - colours and materials. Nothing is moved, nothing
	is made solid or non-solid, no prompt or pad is touched, and everything it
	adds can't be bumped into, clicked or stood on. The people (shopkeepers,
	the blacksmith) and the training dummies are left exactly as they are, and
	so are the boss arenas (they aren't part of the lobby). Config.Retro.World
	switches each piece; On = false turns all of it off.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local R = Config.Retro or {}
local W = R.World or {}
if R.On == false or W.On == false then
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local RGB = Color3.fromRGB
local V3 = Vector3.new

-- in the lobby = not on a floor of the Spire
local function inLobby()
	local f = player:GetAttribute("SpireFloor")
	return f == nil or f == 0
end

----------------------------------------------------------------------
-- The palette (the same one as the menus: Endesga 32)
----------------------------------------------------------------------
local PALETTE = {
	RGB(190, 74, 47), RGB(215, 118, 67), RGB(234, 212, 170), RGB(228, 166, 114),
	RGB(184, 111, 80), RGB(115, 62, 57), RGB(62, 39, 49), RGB(162, 38, 51),
	RGB(228, 59, 68), RGB(247, 118, 34), RGB(254, 174, 52), RGB(254, 231, 97),
	RGB(99, 199, 77), RGB(62, 137, 72), RGB(38, 92, 66), RGB(25, 60, 62),
	RGB(18, 78, 137), RGB(0, 153, 219), RGB(44, 232, 245), RGB(255, 255, 255),
	RGB(192, 203, 220), RGB(139, 155, 180), RGB(90, 105, 136), RGB(58, 68, 102),
	RGB(38, 43, 68), RGB(24, 20, 37), RGB(255, 0, 68), RGB(104, 56, 108),
	RGB(181, 80, 136), RGB(246, 117, 122), RGB(232, 183, 150), RGB(194, 133, 105),
}
local snapCache = {}
local function snap(c)
	local key = math.floor(c.R * 255 + 0.5) * 65536 + math.floor(c.G * 255 + 0.5) * 256 + math.floor(c.B * 255 + 0.5)
	local hit = snapCache[key]
	if hit then
		return hit
	end
	local best, bestD = c, math.huge
	for _, p in ipairs(PALETTE) do
		local dr, dg, db = c.R - p.R, c.G - p.G, c.B - p.B
		local d = dr * dr * 0.3 + dg * dg * 0.59 + db * db * 0.11
		if d < bestD then
			best, bestD = p, d
		end
	end
	snapCache[key] = best
	return best
end

----------------------------------------------------------------------
-- The lobby's look: palette colours and flat materials
----------------------------------------------------------------------
-- the realistic textures that become flat colour (Neon, Glass, Ice and the
-- smooth ones stay as they are)
local FLATTEN = {
	[Enum.Material.Slate] = true, [Enum.Material.Cobblestone] = true, [Enum.Material.Metal] = true,
	[Enum.Material.Wood] = true, [Enum.Material.WoodPlanks] = true, [Enum.Material.Brick] = true,
	[Enum.Material.Grass] = true, [Enum.Material.LeafyGrass] = true, [Enum.Material.Fabric] = true,
	[Enum.Material.Marble] = true, [Enum.Material.Basalt] = true, [Enum.Material.Ground] = true,
	[Enum.Material.DiamondPlate] = true, [Enum.Material.Concrete] = true, [Enum.Material.Granite] = true,
	[Enum.Material.Pebble] = true, [Enum.Material.Rock] = true, [Enum.Material.Sandstone] = true,
	[Enum.Material.CorrodedMetal] = true, [Enum.Material.Limestone] = true, [Enum.Material.Mud] = true,
}

-- left exactly as they are: anything belonging to a person (a shopkeeper, the
-- blacksmith, a player) and the training dummies
local function leaveAlone(p)
	local node = p.Parent
	while node and node ~= Workspace do
		if node:IsA("Model") and node:FindFirstChildOfClass("Humanoid") then
			return true
		end
		if CollectionService:HasTag(node, "Dummy") then
			return true
		end
		node = node.Parent
	end
	return CollectionService:HasTag(p, "Dummy")
end

local function restyle(p)
	if not p:IsA("BasePart") or p:GetAttribute("RetroSkip") or leaveAlone(p) then
		return
	end
	if W.Palette ~= false then
		local c = snap(p.Color)
		if c ~= p.Color then
			p.Color = c
		end
	end
	if W.Flat ~= false and FLATTEN[p.Material] then
		p.Material = Enum.Material.SmoothPlastic
	end
end

-- through the whole lobby a few hundred parts a frame (so it never hitches)
local function restyleAll(root)
	local list = root:GetDescendants()
	local i = 0
	while i < #list do
		for _ = 1, 300 do
			i = i + 1
			local p = list[i]
			if not p then
				break
			end
			pcall(restyle, p)
		end
		task.wait()
	end
end

----------------------------------------------------------------------
-- Our own things in the world: can't be touched, clicked or stood on
----------------------------------------------------------------------
local mine = Instance.new("Folder")
mine.Name = "RetroWorld"
mine.Parent = Workspace

local function ghost(size, color, material)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("RetroSkip", true)
	return p
end

local function myRoot()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

----------------------------------------------------------------------
-- Pixel motes: glowing cubes drifting up around you, moving in steps
----------------------------------------------------------------------
local motes = {}
local MOTE_COLORS = { RGB(254, 231, 97), RGB(254, 174, 52), RGB(246, 117, 122), RGB(44, 232, 245), RGB(255, 255, 255), RGB(99, 199, 77) }
local moteFolder = Instance.new("Folder")
moteFolder.Name = "Motes"
local function placeMote(m, around, fresh)
	local a = math.random() * math.pi * 2
	local d = 6 + math.random() * 54
	m.pos = around + V3(math.cos(a) * d, fresh and (1 + math.random() * 10) or (0.5 + math.random() * 2), math.sin(a) * d)
	m.vel = V3((math.random() - 0.5) * 0.8, 0.6 + math.random() * 0.9, (math.random() - 0.5) * 0.8)
	m.life = 6 + math.random() * 8
end
for i = 1, (W.Motes or 36) do
	local size = (i % 5 == 0) and 0.45 or 0.3
	local m = { part = ghost(V3(size, size, size), MOTE_COLORS[(i % #MOTE_COLORS) + 1]), phase = math.random() * 10 }
	m.part.Parent = moteFolder
	motes[i] = m
end

----------------------------------------------------------------------
-- The save star over the spawn: a pixel star, turning in steps
----------------------------------------------------------------------
local STAR = {
	"...Y...",
	"...Y...",
	"..YWY..",
	"YYWWWYY",
	"..YWY..",
	"...Y...",
	"...Y...",
}
local star = nil -- { center, cubes = { {part, offset} } }
local function buildStar(at)
	local cubes = {}
	local s = 0.7
	for y = 1, #STAR do
		for x = 1, #STAR[y] do
			local ch = string.sub(STAR[y], x, x)
			if ch ~= "." then
				local p = ghost(V3(s, s, s), ch == "W" and RGB(255, 255, 255) or RGB(254, 231, 97))
				p.Parent = mine
				table.insert(cubes, { part = p, offset = V3((x - 4) * s, (4 - y) * s, 0) })
			end
		end
	end
	local glow = Instance.new("PointLight")
	glow.Color = RGB(254, 231, 97)
	glow.Range = 14
	glow.Brightness = 1.2
	glow.Parent = cubes[math.ceil(#cubes / 2)].part
	star = { center = at, cubes = cubes }
end

----------------------------------------------------------------------
-- Flavour text: a black box that types a line when you walk up to things
----------------------------------------------------------------------
local LINES = {
	LobbySpawn = "* The castle bustles with heroes-to-be. You feel ready to GROW.",
	SellShop = "* The merchant counts coins with a grin. Your pack feels heavy.",
	UpgradeShop = "* A cozy mushroom house. It smells like fresh bread... and ambition.",
	CraftBench = "* The forge is warm. Somewhere, a hammer is waiting just for you.",
	PrestigeShrine = "* The shrine hums softly. You feel your strength waiting to grow.",
	TrainingYard = "* The dummies stand ready. They don't feel a thing. Probably.",
	Spire = "* The Spire looms over the castle. Something at the top wants to be beaten.",
	CastleGate = "* The old gate is shut tight. Not yet...",
}
for k, v in pairs(W.Lines or {}) do
	LINES[k] = v
end

local gui = Instance.new("ScreenGui")
gui.Name = "RetroFlavour"
gui.ResetOnSpawn = false
gui.DisplayOrder = 20
gui:SetAttribute("RetroSkip", true) -- (it has its own look)
gui.Parent = playerGui
local scaler = Instance.new("Frame")
scaler.BackgroundTransparency = 1
scaler.Size = UDim2.fromScale(1, 1)
scaler.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = scaler
local function fitScreen()
	local cam = Workspace.CurrentCamera
	if cam then
		local s = math.clamp(cam.ViewportSize.Y / 1000, 0.5, 1.1)
		uiScale.Scale = s
		scaler.Size = UDim2.fromScale(1 / s, 1 / s)
	end
end
fitScreen()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitScreen)
end

local box = Instance.new("Frame")
box.AnchorPoint = Vector2.new(0.5, 1)
box.Position = UDim2.new(0.5, 0, 1, -150)
box.Size = UDim2.fromOffset(660, 92)
box.BackgroundColor3 = RGB(0, 0, 0)
box.BorderSizePixel = 0
box.Visible = false
box.Parent = scaler
local border = Instance.new("UIStroke")
border.Color = RGB(255, 255, 255)
border.Thickness = 4
border.LineJoinMode = Enum.LineJoinMode.Miter
border.Parent = box
local pop = Instance.new("UIScale")
pop.Parent = box
local line = Instance.new("TextLabel")
line.BackgroundTransparency = 1
line.Position = UDim2.fromOffset(20, 14)
line.Size = UDim2.new(1, -40, 1, -28)
line.Font = Enum.Font.Arcade
line.TextSize = 26
line.TextColor3 = RGB(255, 255, 255)
line.TextXAlignment = Enum.TextXAlignment.Left
line.TextYAlignment = Enum.TextYAlignment.Top
line.TextWrapped = true
line.Text = ""
line.Parent = box

local voice = nil
local function blip()
	if voice == nil then
		voice = false
		local t = R.TypeBlip and SoundService:FindFirstChild(R.TypeBlip)
		if t and t:IsA("Sound") then
			voice = t:Clone()
			voice.Volume = t.Volume * 0.5
			voice.Parent = SoundService
		end
	end
	if voice then
		voice.TimePosition = 0
		voice:Play()
	end
end

local saying = nil -- { key, started, letters, shown, until }
local lastSaid = {}
local function say(key, text)
	saying = { key = key, started = os.clock(), letters = utf8.len(text) or #text, shown = 0, hideAt = math.huge }
	line.Text = text
	line.MaxVisibleGraphemes = 0
	box.Visible = true
	pop.Scale = 0.85
	TweenService:Create(pop, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	lastSaid[key] = os.clock()
end
local function hush()
	saying = nil
	box.Visible = false
end

-- the places it talks about: each is the middle of what was built there
local spots = {}
local function findSpots(lobby)
	for key in pairs(LINES) do
		local thing = lobby:FindFirstChild(key, true)
		if thing then
			local sum, n, lo, hi = V3(), 0, nil, nil
			local parts = thing:IsA("BasePart") and { thing } or thing:GetDescendants()
			for _, p in ipairs(parts) do
				if p:IsA("BasePart") then
					sum = sum + p.Position
					n = n + 1
					lo = lo and V3(math.min(lo.X, p.Position.X), 0, math.min(lo.Z, p.Position.Z)) or V3(p.Position.X, 0, p.Position.Z)
					hi = hi and V3(math.max(hi.X, p.Position.X), 0, math.max(hi.Z, p.Position.Z)) or V3(p.Position.X, 0, p.Position.Z)
				end
			end
			if n > 0 then
				local reach = math.clamp((hi - lo).Magnitude * 0.35, 10, 34)
				table.insert(spots, { key = key, at = sum / n, reach = reach })
			end
		end
	end
end

----------------------------------------------------------------------
-- The lobby's grade: a touch warmer and punchier, only in the lobby
----------------------------------------------------------------------
local grade = nil
if W.Grade ~= false then
	grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "RetroWorldGrade"
	grade.Saturation = 0.14
	grade.Contrast = 0.06
	grade.TintColor = RGB(255, 250, 242)
	grade.Parent = Lighting
end

----------------------------------------------------------------------
-- DETAIL: the lobby dressed up - far more to look at, all in the same
-- chunky pixel style, and all of it things you can't touch
----------------------------------------------------------------------
local D = W.Detail or {}
local rng = Random.new(9241) -- (the same "random" on every screen: everyone sees the same lobby)
local detail = Instance.new("Folder")
detail.Name = "Detail"
detail.Parent = mine
local steppers = {} -- the moving detail: each is run 12 times a second
local moveParts, moveCFs = {}, {}
local function move(p, cf)
	moveParts[#moveParts + 1] = p
	moveCFs[#moveCFs + 1] = cf
end
-- everything that moved this step, in one go
local function flushMoves()
	if #moveParts == 0 then
		return
	end
	local ok = pcall(function()
		Workspace:BulkMoveTo(moveParts, moveCFs, Enum.BulkMoveMode.FireCFrameChanged)
	end)
	if not ok then
		for i, p in ipairs(moveParts) do
			p.CFrame = moveCFs[i]
		end
	end
	table.clear(moveParts)
	table.clear(moveCFs)
end
local function block(size, color, material, transparency)
	local p = ghost(size, color, material or Enum.Material.SmoothPlastic)
	p.Transparency = transparency or 0
	p.Parent = detail
	return p
end
local function spread()
	return rng:NextNumber() - 0.5
end

local GRASS = { RGB(99, 199, 77), RGB(62, 137, 72), RGB(38, 92, 66) }

-- the palette's greys, dark to light: the stone's shading steps
local GREYS = {
	RGB(24, 20, 37), RGB(38, 43, 68), RGB(58, 68, 102), RGB(90, 105, 136),
	RGB(139, 155, 180), RGB(192, 203, 220), RGB(255, 255, 255),
}
local function shadesOf(c)
	local best, bestD = 4, math.huge
	for i, g in ipairs(GREYS) do
		local d = (c.R - g.R) ^ 2 + (c.G - g.G) ^ 2 + (c.B - g.B) ^ 2
		if d < bestD then
			best, bestD = i, d
		end
	end
	return GREYS[math.max(best - 1, 1)], GREYS[math.min(best + 1, #GREYS)]
end

-- THE CASTLE WALLS: a dark stone plinth, lines of brick courses, a light
-- ledge along the top, and chunky stones standing out of the face
local function stoneWall(w)
	local size, at = w.Size, w.Position
	local alongX = size.X > size.Z
	local length = alongX and size.X or size.Z
	local half = (alongX and size.Z or size.X) / 2
	-- (the face you see: the side toward the middle of the island)
	local n = alongX and V3(0, 0, at.Z > 0 and -1 or 1) or V3(at.X > 0 and -1 or 1, 0, 0)
	local along = alongX and V3(1, 0, 0) or V3(0, 0, 1)
	local face = at - V3(0, size.Y / 2, 0) + n * half
	local dark, light = shadesOf(w.Color)
	local function slab(u, y, len, h, depth, color)
		local p = block(alongX and V3(len, h, depth) or V3(depth, h, len), color)
		p.CFrame = CFrame.new(face + along * u + V3(0, y, 0) + n * (depth / 2 - 0.05))
	end
	slab(0, 2, length, 4, 0.8, dark)
	for y = 9, size.Y - 5, 7 do
		slab(0, y, length, 0.35, 0.3, dark)
	end
	slab(0, size.Y - 0.8, length, 1.2, 0.9, light)
	for _ = 1, math.floor(length / 5) do
		slab(spread() * (length - 6), 6 + rng:NextNumber() * (size.Y - 12), 2.5 + rng:NextNumber() * 2.5,
			1.6 + rng:NextNumber() * 1.4, 0.45 + rng:NextNumber() * 0.3, rng:NextNumber() < 0.6 and dark or light)
	end
	-- The moss: the round green blobs the builder puts along the wall (the
	-- same size, stepping up in the same staircase every few studs) are
	-- hidden, and moss grows naturally instead: ragged patches of pixel moss
	-- at random spots, most of them low down where it's damp, some bunched
	-- into little colonies, with strands trailing down from a few.
	local mossName = "^" .. w.Name .. "_Moss%d+$"
	for _, blob in ipairs(w.Parent:GetChildren()) do
		if blob:IsA("BasePart") and string.match(blob.Name, mossName) then
			blob.Transparency = 1
		end
	end
	local function patch(u, y, reach)
		for _ = 1, rng:NextInteger(4, 10) do
			local sz = 0.6 + rng:NextNumber() * 1.3
			slab(u + spread() * reach * 2, y + spread() * reach * 1.2, sz, sz * (0.5 + rng:NextNumber() * 0.7),
				0.25, GRASS[rng:NextInteger(1, #GRASS)])
		end
		if rng:NextNumber() < 0.4 then
			local len = 1.5 + rng:NextNumber() * 5
			slab(u + spread() * reach, y - len / 2 - 0.4, 0.4, len, 0.2, GRASS[rng:NextInteger(2, #GRASS)])
		end
	end
	for _ = 1, math.floor(length / 22) do
		local u = spread() * (length - 8)
		-- (low heights far more likely: the square of a random number leans low)
		local y = 4 + (rng:NextNumber() ^ 2) * (size.Y - 10)
		local reach = 1.5 + rng:NextNumber() * 2.5
		patch(u, y, reach)
		-- sometimes a smaller patch or two grows nearby
		for _ = 1, (rng:NextNumber() < 0.45) and rng:NextInteger(1, 2) or 0 do
			patch(u + spread() * 14, math.max(3, y + spread() * 8), reach * 0.6)
		end
	end
end

-- CHUNKY STONES on the sides of a stone block (the forge's walls, its
-- chimney and furnace): little stones standing out of each face, in the
-- stone's darker and lighter shades
local function studStones(p, density)
	local cf, size = p.CFrame, p.Size
	local dark, light = shadesOf(p.Color)
	local faces = {
		{ cf.RightVector, size.X / 2, cf.LookVector, size.Z },
		{ -cf.RightVector, size.X / 2, cf.LookVector, size.Z },
		{ cf.LookVector, size.Z / 2, cf.RightVector, size.X },
		{ -cf.LookVector, size.Z / 2, cf.RightVector, size.X },
	}
	for _, f in ipairs(faces) do
		local n, half, along, width = f[1], f[2], f[3], f[4]
		for _ = 1, math.floor(width * size.Y / (density or 10)) do
			local w, h = 1.2 + rng:NextNumber() * 1.6, 0.8 + rng:NextNumber() * 0.9
			if w < width - 1 and h < size.Y - 1 then
				local depth = 0.2 + rng:NextNumber() * 0.2
				local at = cf.Position + n * (half + depth / 2 - 0.05) + along * (spread() * (width - w - 0.6)) + cf.UpVector * (spread() * (size.Y - h - 0.6))
				block(V3(w, h, depth), rng:NextNumber() < 0.6 and dark or light).CFrame = CFrame.lookAt(at, at + n)
			end
		end
	end
end
local FORGE_STONE = { BackWall = true, SideWallL = true, SideWallR = true, FrontWallL = true, FrontWallR = true, Chimney = true, Furnace = true }

-- PIXEL FLAMES in place of the old smoky fire: a stack of glowing cubes
-- that flickers, in the fire's own colours (the blue ones stay blue)
local flames = {}
local function pixelFlame(fire)
	local holder = fire.Parent
	if not (holder and holder:IsA("BasePart")) or leaveAlone(holder) or not fire.Enabled then
		return
	end
	local s = math.clamp(fire.Size / 3, 0.5, 5)
	local c1, c2 = snap(fire.Color), snap(fire.SecondaryColor)
	local f = { at = holder.Position + V3(0, holder.Size.Y / 2, 0), s = s, cubes = {} }
	for i, spec in ipairs({ { 0.9, c1, 0.35 }, { 0.7, c1, 0.95 }, { 0.55, c2, 1.45 }, { 0.38, c2, 1.9 }, { 0.22, RGB(255, 255, 255), 2.25 } }) do
		local w = spec[1] * s
		table.insert(f.cubes, { part = block(V3(w, w, w), spec[2], Enum.Material.Neon), h = spec[3] * s, i = i })
	end
	fire.Enabled = false
	fire:GetPropertyChangedSignal("Enabled"):Connect(function()
		if fire.Enabled then
			fire.Enabled = false
		end
	end)
	table.insert(flames, f)
end
table.insert(steppers, function()
	for _, f in ipairs(flames) do
		for _, c in ipairs(f.cubes) do
			local j = 0.12 * f.s * (c.i / 3)
			local up = (math.random() < 0.3) and 0.18 * f.s or 0
			move(c.part, CFrame.new(f.at + V3(math.random(-1, 1) * j, c.h + up, math.random(-1, 1) * j)))
			if c.i == 5 then
				c.part.Transparency = math.random() < 0.35 and 1 or 0
			end
		end
	end
end)

-- PIXEL SMOKE: grey cubes that puff out, grow and fade as they rise
local smokes = {}
local function pixelSmoke(sm)
	local holder = sm.Parent
	if not (holder and holder:IsA("BasePart")) or leaveAlone(holder) or not sm.Enabled then
		return
	end
	sm.Enabled = false
	local puff = { at = holder.Position + V3(0, holder.Size.Y / 2, 0), bits = {} }
	for i = 1, 5 do
		puff.bits[i] = { part = block(V3(1, 1, 1), snap(sm.Color), nil, 0.3), t = i / 5, dx = spread() }
	end
	table.insert(smokes, puff)
end
table.insert(steppers, function(_, step)
	for _, puff in ipairs(smokes) do
		for _, b in ipairs(puff.bits) do
			b.t = b.t + step / 4
			if b.t > 1 then
				b.t, b.dx = b.t - 1, spread()
			end
			local size = 1 + b.t * 2.6
			b.part.Size = V3(size, size, size)
			b.part.Transparency = 0.25 + b.t * 0.75
			move(b.part, CFrame.new(puff.at + V3(b.dx * 2 + b.t * 3, b.t * 12, b.dx)))
		end
	end
end)

-- RISING SPARKS: little glowing cubes floating up from a spot and fading
local risers = {}
local function sparks(center, radius, fromY, toY, colors, count, size)
	for i = 1, count do
		table.insert(risers, {
			part = block(V3(size, size, size), colors[(i % #colors) + 1], Enum.Material.Neon),
			center = center, radius = radius, fromY = fromY, toY = toY,
			t = rng:NextNumber(), speed = 0.25 + rng:NextNumber() * 0.25, off = V3(spread(), 0, spread()) * 2 * radius,
		})
	end
end
table.insert(steppers, function(_, step)
	for _, r in ipairs(risers) do
		r.t = r.t + step * r.speed
		if r.t > 1 then
			r.t = 0
			r.off = V3(spread(), 0, spread()) * 2 * r.radius
		end
		r.part.Transparency = r.t > 0.7 and (r.t - 0.7) / 0.3 or 0
		move(r.part, CFrame.new(r.center + r.off + V3(0, r.fromY + (r.toY - r.fromY) * r.t, 0)))
	end
end)

-- THE TRAINING PADS: a glowing pylon at each corner, and sparks in the pad's colour
local pylons = {}
local function dressPad(glow)
	local c, color = glow.Position, snap(glow.Color)
	local half = glow.Size.X / 2 + 3.2
	local _, lightStone = shadesOf(RGB(90, 105, 136))
	for _, k in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		local base = V3(c.X + k[1] * half, c.Y - 0.3, c.Z + k[2] * half)
		block(V3(1.6, 3, 1.6), RGB(58, 68, 102)).CFrame = CFrame.new(base + V3(0, 1.5, 0))
		block(V3(2, 0.5, 2), lightStone).CFrame = CFrame.new(base + V3(0, 3.2, 0))
		table.insert(pylons, { part = block(V3(0.9, 0.9, 0.9), color, Enum.Material.Neon), at = base + V3(0, 4.4, 0), phase = rng:NextNumber() * 6 })
	end
	sparks(c, glow.Size.X / 2 - 1, 0.5, 9, { color, RGB(255, 255, 255) }, 6, 0.35)
end
table.insert(steppers, function(now)
	for _, p in ipairs(pylons) do
		local bob = math.floor((math.sin(now * 2.5 + p.phase) + 1) * 2) * 0.12
		move(p.part, CFrame.new(p.at + V3(0, bob, 0)) * CFrame.Angles(0, math.floor(now * 4) * math.pi / 8, 0))
	end
end)

-- GRASS AND FLOWERS: little pixel tufts across the lawns
local PETALS = { RGB(246, 117, 122), RGB(254, 231, 97), RGB(255, 255, 255), RGB(44, 232, 245), RGB(181, 80, 136) }
local function plantGrass(lobby)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { lobby }
	for i = 1, (D.Grass or 320) do
		local x, z = spread() * 224, spread() * 224
		local hit = Workspace:Raycast(V3(x, 40, z), V3(0, -60, 0), params)
		local c = hit and hit.Instance.Color
		-- (only on the grass: flat, at ground level and green)
		if hit and hit.Normal.Y > 0.9 and hit.Position.Y < 3 and c.G > c.R * 1.15 and c.G > c.B * 1.1 then
			local at = hit.Position
			if rng:NextNumber() < 0.25 then
				block(V3(0.2, 0.8, 0.2), GRASS[2]).CFrame = CFrame.new(at + V3(0, 0.4, 0))
				block(V3(0.5, 0.5, 0.5), PETALS[rng:NextInteger(1, #PETALS)]).CFrame = CFrame.new(at + V3(0, 0.95, 0))
			else
				for _ = 1, rng:NextInteger(2, 3) do
					local h = 0.5 + rng:NextNumber() * 0.7
					local w = 0.3 + rng:NextNumber() * 0.2
					block(V3(w, h, w), GRASS[rng:NextInteger(1, #GRASS)]).CFrame = CFrame.new(at + V3(spread() * 0.9, h / 2, spread() * 0.9))
				end
			end
		end
		if i % 40 == 0 then
			task.wait()
		end
	end
end

-- VOXEL CLOUDS drifting slowly round the island
local clouds = {}
local function makeClouds(center)
	for _ = 1, (D.Clouds or 14) do
		local cl = { center = center, ang = rng:NextNumber() * math.pi * 2, r = 170 + rng:NextNumber() * 200, y = 85 + rng:NextNumber() * 70, speed = 0.006 + rng:NextNumber() * 0.01, cubes = {} }
		for j = 1, rng:NextInteger(5, 9) do
			local size = V3(10 + rng:NextNumber() * 14, 6 + rng:NextNumber() * 6, 10 + rng:NextNumber() * 14)
			table.insert(cl.cubes, {
				part = block(size, j % 3 == 0 and RGB(192, 203, 220) or RGB(255, 255, 255)),
				off = V3(spread() * 30, size.Y / 2 + rng:NextNumber() * 6, spread() * 18),
			})
		end
		table.insert(clouds, cl)
	end
end
table.insert(steppers, function(now)
	for _, cl in ipairs(clouds) do
		local a = cl.ang + now * cl.speed
		local frame = CFrame.new(cl.center + V3(math.cos(a) * cl.r, cl.y, math.sin(a) * cl.r)) * CFrame.Angles(0, -a, 0)
		for _, c in ipairs(cl.cubes) do
			move(c.part, frame * CFrame.new(c.off))
		end
	end
end)

-- BIRDS: little flocks flapping round over the castle in V-formations
local flocks = {}
local function makeBirds(center)
	for f = 1, (D.Birds or 3) do
		local flock = { center = center, r = 60 + f * 28, y = 58 + f * 12, speed = ((f % 2 == 0) and -1 or 1) * (0.1 + f * 0.02), phase = f * 2.1, members = {} }
		for b = 1, 5 do
			local rank = math.ceil((b - 1) / 2)
			table.insert(flock.members, {
				body = block(V3(0.9, 0.6, 1.6), RGB(38, 43, 68)),
				w1 = block(V3(1.8, 0.2, 0.9), RGB(58, 68, 102)),
				w2 = block(V3(1.8, 0.2, 0.9), RGB(58, 68, 102)),
				slot = V3(((b % 2 == 0) and 1 or -1) * rank * 3, 0, rank * 3),
				flap = rng:NextInteger(0, 3),
			})
		end
		table.insert(flocks, flock)
	end
end
table.insert(steppers, function(now)
	for i, fl in ipairs(flocks) do
		local a = fl.phase + now * fl.speed
		local pos = fl.center + V3(math.cos(a) * fl.r, fl.y + math.sin(now * 0.5 + i) * 3, math.sin(a) * fl.r)
		local heading = V3(-math.sin(a), 0, math.cos(a)) * (fl.speed > 0 and 1 or -1)
		local frame = CFrame.lookAt(pos, pos + heading)
		for _, m in ipairs(fl.members) do
			local cf = frame * CFrame.new(m.slot)
			local up = (math.floor(now * 6) + m.flap) % 2 == 0 and 0.55 or -0.35
			move(m.body, cf)
			move(m.w1, cf * CFrame.new(-1.2, 0, 0) * CFrame.Angles(0, 0, -up))
			move(m.w2, cf * CFrame.new(1.2, 0, 0) * CFrame.Angles(0, 0, up))
		end
	end
end)

-- THE SPIRE'S BEACON: a pillar of light from its peak into the sky, with
-- runes turning round it - you can see where the bosses are from anywhere
local beacon = nil
local function raiseBeacon(spire)
	local top, glowColor = nil, RGB(44, 232, 245)
	for _, p in ipairs(spire:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local y = p.Position.Y + p.Size.Y / 2
			if not top or y > top.Y then
				top = V3(p.Position.X, y, p.Position.Z)
			end
			if p.Material == Enum.Material.Neon then
				glowColor = p.Color
			end
		end
	end
	if not top then
		return
	end
	glowColor = snap(glowColor)
	local function pillar(width, transparency)
		local p = block(V3(420, width, width), glowColor, Enum.Material.Neon, transparency)
		p.Shape = Enum.PartType.Cylinder
		p.CFrame = CFrame.new(top + V3(0, 210, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		return p
	end
	beacon = { core = pillar(3, 0.45), halo = pillar(8, 0.85), top = top, runes = {} }
	for i = 1, 10 do
		beacon.runes[i] = block(V3(1.3, 1.3, 1.3), i % 2 == 0 and glowColor or RGB(255, 255, 255), Enum.Material.Neon)
	end
end
table.insert(steppers, function(now)
	if not beacon then
		return
	end
	local pulse = math.floor(now * 3) % 2 == 0
	beacon.core.Transparency = pulse and 0.4 or 0.5
	local turn = math.floor(now * 6) * (math.pi / 24)
	for i, r in ipairs(beacon.runes) do
		local a = turn + i / #beacon.runes * math.pi * 2
		local bob = math.floor(math.sin(now * 2 + i) * 2 + 0.5) * 0.3
		move(r, CFrame.new(beacon.top + V3(math.cos(a) * 9, 5 + bob, math.sin(a) * 9)) * CFrame.Angles(0, -a, math.pi / 4))
	end
end)

-- THE PATHS: cobblestones. The slab turns to dark mortar and rows of
-- cobbles are laid on it, staggered like real paving, each a little
-- different in size and shade, with moss in some of the gaps; the curbs go
-- dark stone. (Paper-thin and not solid: walking on it is unchanged.)
local PATHS = {
	PathEastWest = true, PathToForge = true, PathRoadToPlaza = true, PathForgeSide = true,
	PathBehindForge = true, PathToGate = true, StairLanding = true, PathToYard = true,
}
local COBBLES = { RGB(139, 155, 180), RGB(192, 203, 220), RGB(139, 155, 180), RGB(160, 170, 192) }
local function cobble(slab)
	local size, top = slab.Size, slab.Position.Y + slab.Size.Y / 2
	slab.Color = RGB(58, 68, 102) -- (the thin mortar lines between them)
	local cell = 2.2
	local hx, hz = size.X / 2 - 0.05, size.Z / 2 - 0.05
	local nx, nz = math.ceil(size.X / cell) + 1, math.ceil(size.Z / cell)
	for iz = 0, nz - 1 do
		local shift = (iz % 2 == 0) and 0 or cell / 2
		-- (cobbles at the ends and the sides are cut to fit, so the whole path
		-- is paved right up to its edges with no bare strips)
		local z0 = math.max(-hz, -size.Z / 2 + iz * cell + 0.08)
		local z1 = math.min(hz, -size.Z / 2 + (iz + 1) * cell - 0.08)
		for ix = -1, nx - 1 do
			local x0 = math.max(-hx, -size.X / 2 + ix * cell + shift + 0.08)
			local x1 = math.min(hx, -size.X / 2 + (ix + 1) * cell + shift - 0.08)
			if x1 - x0 > 0.3 and z1 - z0 > 0.3 then
				local at = V3(slab.Position.X + (x0 + x1) / 2, top + 0.04, slab.Position.Z + (z0 + z1) / 2)
				if rng:NextNumber() < 0.025 then
					block(V3(x1 - x0, 0.1, z1 - z0), GRASS[rng:NextInteger(1, #GRASS)]).CFrame = CFrame.new(at)
				else
					local w, d = x1 - x0 - rng:NextNumber() * 0.1, z1 - z0 - rng:NextNumber() * 0.1
					block(V3(w, 0.08, d), COBBLES[rng:NextInteger(1, #COBBLES)]).CFrame = CFrame.new(at)
				end
			end
		end
		if iz % 8 == 7 then
			task.wait()
		end
	end
end

-- THE PLAZA: the same cobbles, laid round the shrine on each of its three
-- rings at that ring's own height, leaving the gold inlay ring and the gold
-- pointers showing through
local function cobblePlaza(ground)
	local rings = {}
	for _, n in ipairs({ "PlazaInner", "PlazaMid", "PlazaOuter" }) do
		local d = ground:FindFirstChild(n)
		if d then
			d.Color = RGB(58, 68, 102)
			table.insert(rings, { r = d.Size.Y / 2, top = d.Position.Y + d.Size.X / 2 })
		end
	end
	if #rings == 0 then
		return
	end
	local c = ground:FindFirstChild("PlazaInner") or ground:FindFirstChild("PlazaOuter")
	local center = c.Position
	local cell = 2.2
	local outer = rings[#rings].r
	-- (the middle is paved too, unless something stands there)
	local innerGap = ground.Parent:FindFirstChild("PrestigeShrine") and 12.6
		or (ground.Parent:FindFirstChild("Fountain", true) and 10.5)
		or -1
	for iz = -math.ceil(outer / cell), math.ceil(outer / cell) do
		local shift = (iz % 2 == 0) and 0 or cell / 2
		for ix = -math.ceil(outer / cell), math.ceil(outer / cell) do
			local x, z = ix * cell + shift, iz * cell
			local r = math.sqrt(x * x + z * z)
			local ang = math.deg(math.atan2(z, x)) % 90
			local onPointer = r > 19.4 and math.abs(ang - 45) < 7
			if r > innerGap and r < outer - 1 and not (r > 16.1 and r < 17.7) and not onPointer then
				local top
				for _, ring in ipairs(rings) do
					if r < ring.r - 0.4 then
						top = ring.top
						break
					end
				end
				if top then
					local at = V3(center.X + x, top + 0.04, center.Z + z)
					local w, d = cell - 0.16 - rng:NextNumber() * 0.1, cell - 0.16 - rng:NextNumber() * 0.1
					block(V3(w, 0.08, d), COBBLES[rng:NextInteger(1, #COBBLES)]).CFrame = CFrame.new(at)
				end
			end
		end
	end
end

-- all of it, once the lobby's here
local function dressLobby(lobby)
	if D.On == false then
		return
	end
	local ground = lobby:FindFirstChild("Ground")
	if ground and D.Walls ~= false then
		for _, w in ipairs(ground:GetChildren()) do
			if w:IsA("BasePart") and string.match(w.Name, "^Wall%a+$") then
				pcall(stoneWall, w)
			end
		end
	end
	local ground0 = lobby:FindFirstChild("Ground")
	if ground0 and D.Paths ~= false then
		pcall(cobblePlaza, ground0)
		for _, p in ipairs(ground0:GetChildren()) do
			if p:IsA("BasePart") then
				if PATHS[p.Name] then
					pcall(cobble, p)
				elseif p.Name == "Curb" or p.Name == "PlazaCurb" then
					p.Color = RGB(58, 68, 102)
				end
			end
		end
	end
	local forge = lobby:FindFirstChild("CraftBench")
	if forge and D.Walls ~= false then
		for _, p in ipairs(forge:GetChildren()) do
			if p:IsA("BasePart") and FORGE_STONE[p.Name] then
				pcall(studStones, p, 9)
			end
		end
	end
	if D.Flames ~= false then
		for _, d in ipairs(lobby:GetDescendants()) do
			if d:IsA("Fire") then
				pcall(pixelFlame, d)
			elseif d:IsA("Smoke") then
				pcall(pixelSmoke, d)
			end
		end
	end
	local yard = lobby:FindFirstChild("TrainingYard")
	if yard and D.Pads ~= false then
		for _, p in ipairs(yard:GetChildren()) do
			if p:IsA("BasePart") and string.match(p.Name, "^PadGlow%d+$") then
				pcall(dressPad, p)
			end
		end
	end
	-- (the shrine and its sparks are gone: the plaza is plain paving)
	local center = V3(0, 0, -10)
	makeClouds(center)
	makeBirds(center)
	local spire = lobby:FindFirstChild("Spire")
	if spire and D.Beacon ~= false then
		pcall(raiseBeacon, spire)
	end
	if (D.Grass or 320) > 0 then
		plantGrass(lobby)
	end
end


----------------------------------------------------------------------
-- THE DUMMIES TALK BACK (like Undertale's): stand on a pad and its dummy
-- mocks you in a little black speech box, typed out with a blip
----------------------------------------------------------------------
local TAUNTS = {
	Straw = { "* Is that a punch or a gentle suggestion?", "* I'm made of straw and I'm STILL not scared.", "* Hit me harder. I dare you. Politely." },
	Iron = { "* Clang. That's the sound of you trying.", "* I've been hit harder by a breeze.", "* Iron will. Iron body. Iron... bored." },
	Frost = { "* Brr. Your punches give me chills. Of boredom.", "* Chill out. You'll hurt yourself.", "* Ice to meet you. Nice try though." },
	Ember = { "* You're not so hot, are you?", "* Careful, you'll get burned. Mostly your pride.", "* I've seen bigger sparks from a birthday candle." },
	Void = { "* ...", "* The void stares back. It's unimpressed.", "* Your hits echo into nothing. Like your jokes." },
	Celestial = { "* The stars laugh at your technique.", "* Divine. Radiant. Not you, me.", "* Keep going. The heavens need a comedy show." },
	Ooze = { "* Squish! Oh wait, that was you slipping.", "* I'm slime. I bounce back. Can you?", "* You'll never get this goo off your gloves." },
	Dune = { "* You hit like sand. Scattered.", "* A worm told me about you. He wasn't impressed.", "* Time is running out. Like sand. Get it?" },
	Crystal = { "* Crystal clear: you need more training.", "* Don't crack under pressure. I won't.", "* So shiny. So unbreakable. So ME." },
	Storm = { "* Lightning never strikes twice. You barely struck once.", "* That's shocking. Shockingly weak.", "* Thunder! ...oh that was just your stomach." },
	Dragon = { "* Rawr. That means 'try harder' in dragon.", "* I've had lunches tougher than you.", "* Kneel, snack. I mean, hero." },
	Cosmic = { "* In the vastness of space... you're still small.", "* I've seen galaxies born. Your punch? Not so much.", "* The universe is infinite. So is my patience." },
}
local LOCKED = { "* Aww. Come back when you're bigger.", "* You need Level %d to touch me. Bye bye!", "* Too soon, tiny hero. Level %d first." }

local function bubbleFor(head)
	local bb = Instance.new("BillboardGui")
	bb.Name = "DummyTalk"
	bb.Size = UDim2.fromScale(15, 3.6)
	-- (beside its head, not above it: above is where its multiplier sign hangs)
	bb.StudsOffset = V3(9, 0.5, 0)
	bb.MaxDistance = 70
	bb.LightInfluence = 0
	bb.Enabled = false
	bb:SetAttribute("RetroSkip", true)
	local box = Instance.new("Frame")
	box.Size = UDim2.fromScale(1, 1)
	box.BackgroundColor3 = RGB(0, 0, 0)
	box.Parent = bb
	local edge = Instance.new("UIStroke")
	edge.Color = RGB(255, 255, 255)
	edge.Thickness = 3
	edge.Parent = box
	local txt = Instance.new("TextLabel")
	txt.BackgroundTransparency = 1
	txt.Position = UDim2.fromScale(0.04, 0.1)
	txt.Size = UDim2.fromScale(0.92, 0.8)
	txt.Font = Enum.Font.Arcade
	txt.TextScaled = true
	txt.TextWrapped = true
	txt.TextXAlignment = Enum.TextXAlignment.Left
	txt.TextColor3 = RGB(255, 255, 255)
	txt.Parent = box
	bb.Adornee = head
	bb.Parent = mine
	return bb, txt
end

local talkers = {} -- zone index -> { bb, txt }
local talking = nil -- { zi, text, start, letters, until }
local nextTalk, lastZone = 0, 0
local function speak(zi, text)
	local t = talkers[zi]
	if not t then
		return
	end
	if talking and talking.zi ~= zi and talkers[talking.zi] then
		talkers[talking.zi].bb.Enabled = false
		if talkers[talking.zi].sign then
			talkers[talking.zi].sign.Enabled = true
		end
	end
	t.txt.Text = text
	t.txt.MaxVisibleGraphemes = 0
	t.bb.Enabled = true
	if t.sign then
		t.sign.Enabled = false -- (the sign steps aside while it talks; the banner shows its multiplier)
	end
	talking = { zi = zi, start = os.clock(), letters = utf8.len(text) or #text, shown = 0, hideAt = math.huge }
end
local function findTalkers(lobby)
	local yard = lobby:FindFirstChild("TrainingYard")
	for zi = 1, #Config.Zones do
		local d = yard and yard:FindFirstChild("Dummy" .. zi)
		local head = d and d:FindFirstChild("Head", true)
		if head then
			local bb, txt = bubbleFor(head)
			local anchor = yard:FindFirstChild("SignAnchor" .. zi)
			talkers[zi] = { bb = bb, txt = txt, sign = anchor and anchor:FindFirstChild("ZoneSign") }
		end
	end
end
local function stepTalk(now)
	local zi = player:GetAttribute("CurrentZone") or 0
	local zone = Config.Zones[zi]
	if zi ~= lastZone then
		lastZone = zi
		nextTalk = now + 0.4 -- (it notices you almost at once)
	end
	if zone and talkers[zi] and now >= nextTalk and not (talking and now < talking.hideAt) then
		local line
		local stats = player:FindFirstChild("leaderstats")
		local lv = stats and stats:FindFirstChild("Level")
		if lv and lv.Value < zone.level then
			line = string.format(LOCKED[math.random(#LOCKED)], zone.level)
		else
			local list = TAUNTS[zone.id] or TAUNTS.Straw
			line = list[math.random(#list)]
		end
		speak(zi, line)
		nextTalk = now + 9 + math.random() * 6
	end
	if talking then
		local t = talkers[talking.zi]
		local want = math.min(talking.letters, math.floor((now - talking.start) * 30))
		if want > talking.shown then
			talking.shown = want
			t.txt.MaxVisibleGraphemes = want
			if want % 2 == 0 then
				blip()
			end
			if want >= talking.letters then
				t.txt.MaxVisibleGraphemes = -1
				talking.hideAt = now + 3.5
			end
		end
		if now > talking.hideAt or (zi ~= talking.zi) then
			t.bb.Enabled = false
			if t.sign then
				t.sign.Enabled = true
			end
			talking = nil
		end
	end
end
----------------------------------------------------------------------
-- Go
----------------------------------------------------------------------
local lobby = Workspace:WaitForChild("Lobby", 60)
if not lobby then
	return
end
task.spawn(restyleAll, lobby)
lobby.DescendantAdded:Connect(function(d)
	task.defer(function()
		pcall(restyle, d)
	end)
end)
if W.Flavour ~= false then
	findSpots(lobby)
end
task.spawn(dressLobby, lobby)

-- THE BOSS ARENAS get the same look: palette colours, flat materials and
-- pixel flames (only how they look, only on your screen - the fights and
-- everything you stand on are untouched). They may arrive a little later
-- (they stream in), so each is dressed whenever it appears, bit by bit.
local ARENAS = { SlimeArena = true, DuneArena = true }
-- ARENA DETAIL: dripping slime or sand-crust on the pillars, moss and
-- stones round their feet, grass or dry tufts on the ground, and the air
-- full of drifting spores or dust. The same "random" on every screen.
local function arenaDetail(arena, slime)
	local cf, size = arena:GetBoundingBox()
	local center = cf.Position
	local floorY = center.Y - size.Y / 2
	local accent = slime and RGB(120, 255, 90) or RGB(234, 212, 170)
	local deep = slime and RGB(62, 137, 72) or RGB(184, 111, 80)
	-- the pillars: every tall part, round or square
	local pillars = {}
	for _, p in ipairs(arena:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 0.5 then
			local round = p:IsA("Part") and p.Shape == Enum.PartType.Cylinder
			local h = round and p.Size.X or p.Size.Y
			local r = round and p.Size.Y / 2 or math.min(p.Size.X, p.Size.Z) / 2
			if h >= 14 and r >= 1.5 and r <= 9 and (round or p.Size.Y > p.Size.X * 2) then
				table.insert(pillars, { part = p, h = h, r = r })
			end
		end
	end
	for i, pl in ipairs(pillars) do
		if i > 80 then
			break
		end
		local c = pl.part.Position
		local bottom, top = c.Y - pl.h / 2, c.Y + pl.h / 2
		-- streaks running down from the top (glowing slime, or sand crust)
		for _ = 1, rng:NextInteger(3, 6) do
			local a = rng:NextNumber() * math.pi * 2
			local dir = V3(math.cos(a), 0, math.sin(a))
			local len = 2 + rng:NextNumber() * pl.h * 0.45
			local at = V3(c.X, top - len / 2 - rng:NextNumber() * 2, c.Z) + dir * (pl.r + 0.1)
			block(V3(0.5 + rng:NextNumber() * 0.4, len, 0.3), rng:NextNumber() < 0.6 and accent or deep, slime and Enum.Material.Neon or nil, slime and 0.15 or 0).CFrame = CFrame.lookAt(at, at + dir)
			if slime then
				block(V3(0.7, 0.7, 0.4), accent, Enum.Material.Neon).CFrame = CFrame.lookAt(at - V3(0, len / 2 + 0.3, 0), at - V3(0, len / 2 + 0.3, 0) + dir)
			end
		end
		-- chunky stones standing out, and moss round the foot
		for _ = 1, rng:NextInteger(4, 8) do
			local a = rng:NextNumber() * math.pi * 2
			local dir = V3(math.cos(a), 0, math.sin(a))
			local at = V3(c.X, bottom + 2 + rng:NextNumber() * (pl.h - 4), c.Z) + dir * (pl.r + 0.15)
			local dark, light = shadesOf(pl.part.Color)
			block(V3(1 + rng:NextNumber() * 1.4, 0.7 + rng:NextNumber() * 0.8, 0.35), rng:NextNumber() < 0.6 and dark or light).CFrame = CFrame.lookAt(at, at + dir)
		end
		for _ = 1, rng:NextInteger(3, 6) do
			local a = rng:NextNumber() * math.pi * 2
			local d = pl.r + 0.3 + rng:NextNumber() * 1.2
			local w = 0.5 + rng:NextNumber() * 0.8
			block(V3(w, 0.4 + rng:NextNumber() * 0.8, w), slime and GRASS[rng:NextInteger(1, #GRASS)] or deep).CFrame =
				CFrame.new(V3(c.X + math.cos(a) * d, bottom + 0.3, c.Z + math.sin(a) * d))
		end
	end
	-- the ground: grass, flowers and little mushrooms (or dry desert tufts)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { arena, Workspace:FindFirstChildOfClass("Terrain") }
	local reach = math.min(size.X, size.Z) / 2
	for i = 1, (D.ArenaGrass or 260) do
		local a, d = rng:NextNumber() * math.pi * 2, math.sqrt(rng:NextNumber()) * reach
		local from = V3(center.X + math.cos(a) * d, center.Y + size.Y / 2 + 5, center.Z + math.sin(a) * d)
		local hit = Workspace:Raycast(from, V3(0, -(size.Y + 30), 0), params)
		if hit and hit.Normal.Y > 0.85 then
			local at = hit.Position
			local c = hit.Instance:IsA("BasePart") and hit.Instance.Color or RGB(0, 0, 0)
			local green = c.G > c.R * 1.1 and c.G > c.B
			if slime and green then
				local roll = rng:NextNumber()
				if roll < 0.15 then
					-- a little pixel mushroom
					block(V3(0.3, 0.8, 0.3), RGB(234, 212, 170)).CFrame = CFrame.new(at + V3(0, 0.4, 0))
					block(V3(1, 0.4, 1), rng:NextNumber() < 0.5 and RGB(228, 59, 68) or RGB(181, 80, 136)).CFrame = CFrame.new(at + V3(0, 0.95, 0))
				elseif roll < 0.3 then
					block(V3(0.2, 0.8, 0.2), GRASS[2]).CFrame = CFrame.new(at + V3(0, 0.4, 0))
					block(V3(0.5, 0.5, 0.5), PETALS[rng:NextInteger(1, #PETALS)]).CFrame = CFrame.new(at + V3(0, 0.95, 0))
				else
					for _ = 1, rng:NextInteger(2, 3) do
						local h, w = 0.5 + rng:NextNumber() * 0.7, 0.3 + rng:NextNumber() * 0.2
						block(V3(w, h, w), GRASS[rng:NextInteger(1, #GRASS)]).CFrame = CFrame.new(at + V3(spread() * 0.9, h / 2, spread() * 0.9))
					end
				end
			elseif not slime and rng:NextNumber() < 0.45 then
				-- dry desert tufts on the sand
				for _ = 1, rng:NextInteger(2, 4) do
					local h = 0.4 + rng:NextNumber() * 0.9
					block(V3(0.25, h, 0.25), rng:NextNumber() < 0.5 and RGB(194, 133, 105) or RGB(228, 166, 114)).CFrame =
						CFrame.new(at + V3(spread() * 1.2, h / 2, spread() * 1.2)) * CFrame.Angles(spread() * 0.6, 0, spread() * 0.6)
				end
			end
		end
		if i % 40 == 0 then
			task.wait()
		end
	end
	-- the air: spores (or dust) drifting up all over the arena
	sparks(V3(center.X, floorY, center.Z), reach * 0.85, 1, 26, slime and { accent, RGB(200, 255, 150), RGB(255, 255, 255) } or { accent, RGB(254, 231, 97), RGB(255, 255, 255) }, D.ArenaMotes or 70, 0.35)
	-- bubbles rising out of the slime pools
	if slime then
		for _, p in ipairs(arena:GetDescendants()) do
			if p:IsA("BasePart") and p.Name == "SlimePool" then
				sparks(p.Position, p.Size.Y * 0.4, 0.3, 5, { accent, RGB(200, 255, 150) }, 16, 0.6)
			end
		end
	end
end

local function dressArena(arena)
	if W.Arenas == false then
		return
	end
	restyleAll(arena)
	-- The detail goes in only once the arena has really arrived: an arena that
	-- hasn't streamed in yet is an empty model, and an empty model says it
	-- sits at 0,0,0 - the middle of the lobby's plaza - so its dust would all
	-- pile up there in one tall column. Wait until it has size, then dress it.
	if D.On ~= false then
		task.spawn(function()
			for _ = 1, 600 do -- (keeps looking for up to 10 minutes)
				local ok, _, size = pcall(function()
					return arena:GetBoundingBox()
				end)
				local count = 0
				for _, d in ipairs(arena:GetDescendants()) do
					if d:IsA("BasePart") then
						count = count + 1
						if count > 50 then
							break
						end
					end
				end
				if ok and size and size.Magnitude > 60 and count > 50 then
					pcall(arenaDetail, arena, arena.Name == "SlimeArena")
					return
				end
				task.wait(1)
			end
		end)
	end
	if D.Flames ~= false then
		for _, d in ipairs(arena:GetDescendants()) do
			if d:IsA("Fire") then
				pcall(pixelFlame, d)
			elseif d:IsA("Smoke") then
				pcall(pixelSmoke, d)
			end
		end
	end
	arena.DescendantAdded:Connect(function(d)
		task.defer(function()
			pcall(restyle, d)
			if d:IsA("Fire") then
				pcall(pixelFlame, d)
			end
		end)
	end)
end
for _, c in ipairs(Workspace:GetChildren()) do
	if ARENAS[c.Name] then
		task.spawn(dressArena, c)
	end
end
Workspace.ChildAdded:Connect(function(c)
	if ARENAS[c.Name] then
		task.spawn(dressArena, c)
	end
end)
if W.DummyTalk ~= false then
	task.spawn(findTalkers, lobby)
end
local spawnPad = lobby:FindFirstChild("LobbySpawn", true)
if W.SaveStar ~= false and spawnPad and spawnPad:IsA("BasePart") then
	buildStar(spawnPad.Position + V3(0, 7.5, 0))
end

local stepClock, stepAt = 0, 0
RunService.RenderStepped:Connect(function(dt)
	local here = inLobby()
	if grade then
		grade.Enabled = here
	end
	local moteHome = (here and #motes > 0) and mine or nil
	if moteFolder.Parent ~= moteHome then
		moteFolder.Parent = moteHome
	end
	if not here then
		if saying then
			hush()
		end
		-- (in an arena: its pixel flames still flicker)
		stepClock = stepClock + dt
		if stepClock - stepAt >= 1 / 12 then
			stepAt = stepClock
			local step = 1 / 12
			for k = 1, 3 do -- (the flames, the smoke and the rising sparks)
				steppers[k](os.clock(), step)
			end
			flushMoves()
		end
		return
	end
	local hrp = myRoot()
	local now = os.clock()

	-- the motes and the star move in steps, 12 a second, like sprites
	stepClock = stepClock + dt
	if stepClock - stepAt >= 1 / 12 then
		local step = stepClock - stepAt
		stepAt = stepClock
		if hrp then
			local around = V3(hrp.Position.X, hrp.Position.Y - 3, hrp.Position.Z)
			for _, m in ipairs(motes) do
				if not m.pos then
					placeMote(m, around, true)
				end
				m.life = m.life - step
				m.pos = m.pos + m.vel * step + V3(math.sin(now * 1.3 + m.phase) * 0.06, 0, math.cos(now * 1.1 + m.phase) * 0.06)
				local off = m.pos - around
				if m.life <= 0 or V3(off.X, 0, off.Z).Magnitude > 70 or off.Y > 18 then
					placeMote(m, around, false)
				end
				-- (snapped to a quarter-stud grid: pixel steps)
				local p = m.pos
				m.part.CFrame = CFrame.new(math.floor(p.X * 4) / 4, math.floor(p.Y * 4) / 4, math.floor(p.Z * 4) / 4)
				m.part.Transparency = (math.sin(now * 2 + m.phase * 3) > 0.75) and 0.6 or 0
			end
		end
		if star then
			local turn = math.floor(now * 8) * (math.pi / 8) -- a sixteenth of a turn at a time
			local bob = math.floor(math.sin(now * 2) * 3 + 0.5) * 0.15
			local c = CFrame.new(star.center + V3(0, bob, 0)) * CFrame.Angles(0, turn, 0)
			for _, cube in ipairs(star.cubes) do
				move(cube.part, c * CFrame.new(cube.offset))
			end
		end
		-- and all the moving detail
		for _, fn in ipairs(steppers) do
			fn(now, step)
		end
		flushMoves()
	end

	-- flavour text: the nearest place you've walked up to that hasn't
	-- spoken for a while
	if hrp and #spots > 0 then
		local pos = V3(hrp.Position.X, 0, hrp.Position.Z)
		if saying then
			local spot
			for _, s in ipairs(spots) do
				if s.key == saying.key then
					spot = s
				end
			end
			local far = spot and (pos - V3(spot.at.X, 0, spot.at.Z)).Magnitude > spot.reach * 1.6
			if far or now > saying.hideAt then
				hush()
			end
		end
		-- (not while the title screen is still up)
		if not saying and not playerGui:FindFirstChild("RetroTitle") then
			for _, s in ipairs(spots) do
				local d = (pos - V3(s.at.X, 0, s.at.Z)).Magnitude
				if d < s.reach and now - (lastSaid[s.key] or -1e9) > (W.Repeat or 150) then
					say(s.key, LINES[s.key])
					break
				end
			end
		end
	end
	stepTalk(now)
	if saying then
		local want = math.min(saying.letters, math.floor((now - saying.started) * (R.TypeSpeed or 40)))
		if want > saying.shown then
			saying.shown = want
			line.MaxVisibleGraphemes = want
			if want % 2 == 0 then
				blip() -- (a blip every other letter)
			end
			if want >= saying.letters then
				line.MaxVisibleGraphemes = -1
				saying.hideAt = now + 4
			end
		end
	end
end)
