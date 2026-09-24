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
	PrestigeShrine = "* The shrine hums softly. Starting over has never looked so bright.",
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
				cube.part.CFrame = c * CFrame.new(cube.offset)
			end
		end
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
