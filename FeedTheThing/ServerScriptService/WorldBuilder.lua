--[[
	WorldBuilder  (ModuleScript, parent: ServerScriptService, name: "WorldBuilder")

	Builds the world from scripts: grassy terrain, a round plaza in the middle,
	and 8 plots in a ring around it. Each plot has a little house, a hatch pit
	(the Thing lives down there), 10 garden beds and a lawn for Thinglets.

	Only the parts that never move are built here. The Thing, the plants,
	the fruit and the Thinglets are drawn by each player's own client
	(StarterPlayerScripts/World), which keeps the server light and the
	animations smooth on phones.
]]

local WorldBuilder = {}

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Rules = require(ReplicatedStorage:WaitForChild("Rules"))

local W = Config.World
local plots = {} -- [i] = { cframe, hatchCF, beds = {}, sign = TextLabel, signSub = TextLabel }
local worldFolder

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in pairs(props) do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function wedge(props, parent)
	local p = Instance.new("WedgePart")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in pairs(props) do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

----------------------------------------------------------------------
-- Ground, plaza, light
----------------------------------------------------------------------
local function buildGround()
	local terrain = workspace.Terrain
	terrain:Clear()
	pcall(function()
		(terrain :: any).Decoration = false -- no grass blades: cheaper on phones
	end)
	terrain:SetMaterialColor(Enum.Material.Grass, W.Grass)
	local extent = (W.RingRadius + W.PlotDepth) * 2 + 120
	terrain:FillBlock(CFrame.new(0, -8, 0), Vector3.new(extent, 16, extent), Enum.Material.Grass)
end

local function buildPlaza()
	local folder = Instance.new("Folder")
	folder.Name = "Plaza"
	folder.Parent = worldFolder

	local stone = Color3.fromRGB(215, 205, 190)
	part({
		Name = "PlazaFloor", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, W.PlazaRadius * 2, W.PlazaRadius * 2),
		CFrame = CFrame.new(0, -0.4, 0) * UPRIGHT,
		Color = stone, Material = Enum.Material.Pavement,
	}, folder)
	part({
		Name = "PlazaRing", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.05, W.PlazaRadius * 0.5, W.PlazaRadius * 0.5),
		CFrame = CFrame.new(0, -0.4, 0) * UPRIGHT,
		Color = Color3.fromRGB(170, 120, 210), Material = Enum.Material.Pavement,
	}, folder)

	-- paths out to every plot
	for i = 1, W.Plots do
		local cf = Rules.plotCFrame(i)
		local front = cf * CFrame.new(0, 0, -W.PlotDepth / 2) -- the plot's front edge (-Z faces the plaza)
		local inner = CFrame.lookAt(Vector3.zero, cf.Position).LookVector * (W.PlazaRadius - 2)
		local length = (front.Position - inner).Magnitude
		part({
			Name = "Path", Size = Vector3.new(10, 1, length),
			CFrame = CFrame.lookAt((front.Position + inner) / 2, front.Position) * CFrame.new(0, -0.45, 0),
			Color = stone, Material = Enum.Material.Pavement,
		}, folder)
	end

	-- the welcome sign
	local post = Color3.fromRGB(120, 80, 50)
	local signCF = CFrame.new(0, 0, -W.PlazaRadius + 10)
	part({ Name = "SignPost", Size = Vector3.new(1, 12, 1), CFrame = signCF * CFrame.new(-9, 6, 0), Color = post, Material = Enum.Material.Wood }, folder)
	part({ Name = "SignPost", Size = Vector3.new(1, 12, 1), CFrame = signCF * CFrame.new(9, 6, 0), Color = post, Material = Enum.Material.Wood }, folder)
	local board = part({ Name = "SignBoard", Size = Vector3.new(22, 7, 1), CFrame = signCF * CFrame.new(0, 9, 0) * CFrame.Angles(0, math.pi, 0), Color = Color3.fromRGB(70, 40, 90), Material = Enum.Material.Wood }, folder)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(440, 140)
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Config.Font
		label.TextScaled = true
		label.TextColor3 = Config.Thing.EyeColor
		label.Text = "FEED THE THING\nin the Basement"
		label.Parent = gui
	end

	-- lamps
	for i = 1, 4 do
		local angle = (i - 1) / 4 * math.pi * 2 + math.pi / 8 -- between the paths, not on them
		local at = Vector3.new(math.sin(angle), 0, math.cos(angle)) * (W.PlazaRadius - 6)
		part({ Name = "LampPost", Size = Vector3.new(0.8, 10, 0.8), CFrame = CFrame.new(at + Vector3.new(0, 5, 0)), Color = Color3.fromRGB(60, 50, 70) }, folder)
		part({ Name = "Lamp", Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 2.4, 2.4), CFrame = CFrame.new(at + Vector3.new(0, 10.6, 0)), Color = Color3.fromRGB(255, 235, 170), Material = Enum.Material.Neon }, folder)
	end

	-- trees between the plots
	for i = 1, W.Plots do
		local angle = (i - 0.5) / W.Plots * math.pi * 2
		for _, radius in ipairs({ W.RingRadius - 10, W.RingRadius + 60 }) do
			local at = Vector3.new(math.sin(angle), 0, math.cos(angle)) * radius
			part({ Name = "Trunk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(8, 2, 2), CFrame = CFrame.new(at + Vector3.new(0, 4, 0)) * UPRIGHT, Color = Color3.fromRGB(120, 80, 50), Material = Enum.Material.Wood }, folder)
			part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(9, 9, 9), CFrame = CFrame.new(at + Vector3.new(0, 10, 0)), Color = Color3.fromRGB(80, 170, 75) }, folder)
			part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(6, 6, 6), CFrame = CFrame.new(at + Vector3.new(1.5, 13.5, -1)), Color = Color3.fromRGB(95, 190, 85) }, folder)
		end
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlazaSpawn"
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = CFrame.new(0, 0.5, 0)
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = folder
end

local function setLighting()
	Lighting.ClockTime = 14
	Lighting.Brightness = 2.2
	Lighting.GlobalShadows = true
	Lighting.Ambient = Color3.fromRGB(110, 100, 120)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 140, 160)
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.25
		atmosphere.Haze = 0.6
		atmosphere.Color = Color3.fromRGB(220, 225, 255)
		atmosphere.Decay = Color3.fromRGB(170, 150, 210)
		atmosphere.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("BloomEffect") then
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.6
		bloom.Size = 20
		bloom.Threshold = 1.6
		bloom.Parent = Lighting
	end
end

----------------------------------------------------------------------
-- One plot
----------------------------------------------------------------------
local function buildHouse(cf, color, folder)
	local h = W.House
	local base = cf * CFrame.new(h)
	local roof = Color3.fromRGB(150, 70, 90)
	local trim = Color3.fromRGB(250, 245, 235)
	part({ Name = "Walls", Size = Vector3.new(24, 13, 14), CFrame = base * CFrame.new(0, 6.5, 0), Color = color }, folder)
	-- a gable roof from two wedges
	wedge({ Name = "Roof", Size = Vector3.new(26, 7, 8), CFrame = base * CFrame.new(0, 16.5, -4), Color = roof }, folder)
	wedge({ Name = "Roof", Size = Vector3.new(26, 7, 8), CFrame = base * CFrame.new(0, 16.5, 4) * CFrame.Angles(0, math.pi, 0), Color = roof }, folder)
	part({ Name = "Chimney", Size = Vector3.new(2.5, 6, 2.5), CFrame = base * CFrame.new(7, 18, 2), Color = Color3.fromRGB(170, 90, 80), Material = Enum.Material.Brick }, folder)
	-- the front (facing the hatch and the plaza) is the -Z face
	part({ Name = "Door", Size = Vector3.new(4.5, 8, 0.4), CFrame = base * CFrame.new(0, 4, -7.1), Color = Color3.fromRGB(120, 75, 50), Material = Enum.Material.Wood }, folder)
	part({ Name = "Knob", Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6), CFrame = base * CFrame.new(1.5, 4, -7.4), Color = Color3.fromRGB(255, 205, 60), Material = Enum.Material.Metal }, folder)
	for _, x in ipairs({ -7.5, 7.5 }) do
		part({ Name = "WindowFrame", Size = Vector3.new(5, 4.6, 0.3), CFrame = base * CFrame.new(x, 7.5, -7.05), Color = trim }, folder)
		part({ Name = "Window", Size = Vector3.new(4, 3.6, 0.3), CFrame = base * CFrame.new(x, 7.5, -7.15), Color = Color3.fromRGB(170, 215, 255), Material = Enum.Material.Glass, Transparency = 0.2 }, folder)
	end
end

local function buildPit(hatchCF, folder)
	local size, depth = W.PitSize, W.PitDepth
	-- carve the terrain a little wider than the pit; the rim covers the edge
	workspace.Terrain:FillBlock(hatchCF * CFrame.new(0, -depth / 2 + 1, 0), Vector3.new(size + 6, depth + 4, size + 6), Enum.Material.Air)
	local dark = Config.Thing.PitColor
	part({ Name = "PitFloor", Size = Vector3.new(size, 1, size), CFrame = hatchCF * CFrame.new(0, -depth - 0.5, 0), Color = dark }, folder)
	for _, s in ipairs({
		{ Vector3.new(size, depth, 1), Vector3.new(0, -depth / 2, -size / 2 - 0.5) },
		{ Vector3.new(size, depth, 1), Vector3.new(0, -depth / 2, size / 2 + 0.5) },
		{ Vector3.new(1, depth, size + 2), Vector3.new(-size / 2 - 0.5, -depth / 2, 0) },
		{ Vector3.new(1, depth, size + 2), Vector3.new(size / 2 + 0.5, -depth / 2, 0) },
	}) do
		part({ Name = "PitWall", Size = s[1], CFrame = hatchCF * CFrame.new(s[2]), Color = dark }, folder)
	end
	-- a lawn rim round the hole, hiding the carved terrain's rough edge
	local rim = 4
	local lawn = W.Lawn
	for _, s in ipairs({
		{ Vector3.new(size + rim * 2, 1, rim), Vector3.new(0, -0.5, -(size / 2 + rim / 2)) },
		{ Vector3.new(size + rim * 2, 1, rim), Vector3.new(0, -0.5, size / 2 + rim / 2) },
		{ Vector3.new(rim, 1, size), Vector3.new(-(size / 2 + rim / 2), -0.5, 0) },
		{ Vector3.new(rim, 1, size), Vector3.new(size / 2 + rim / 2, -0.5, 0) },
	}) do
		part({ Name = "Rim", Size = s[1], CFrame = hatchCF * CFrame.new(s[2]), Color = lawn, Material = Enum.Material.Grass }, folder)
	end
	-- you can walk over the hole, and see straight through
	part({ Name = "HatchFloor", Size = Vector3.new(size, 1, size), CFrame = hatchCF * CFrame.new(0, -0.5, 0), Transparency = 1, CanQuery = false }, folder)
end

local function buildFence(cf, folder)
	local white = Color3.fromRGB(250, 248, 240)
	local halfW, halfD = W.PlotWidth / 2, W.PlotDepth / 2
	local function fenceLine(from, to)
		local length = (to - from).Magnitude
		local mid = (from + to) / 2
		local along = CFrame.lookAt(mid, to)
		part({ Name = "Rail", Size = Vector3.new(0.4, 0.5, length), CFrame = along * CFrame.new(0, 2.2, 0), Color = white, CanCollide = false }, folder)
		part({ Name = "Rail", Size = Vector3.new(0.4, 0.5, length), CFrame = along * CFrame.new(0, 1.1, 0), Color = white, CanCollide = false }, folder)
		local posts = math.floor(length / 10)
		for i = 0, posts do
			local at = from:Lerp(to, i / posts)
			part({ Name = "Post", Size = Vector3.new(0.7, 3, 0.7), CFrame = CFrame.new(at + Vector3.new(0, 1.5, 0)), Color = white, CanCollide = false }, folder)
		end
	end
	local function world(x, z)
		return (cf * CFrame.new(x, 0, z)).Position
	end
	fenceLine(world(-halfW, -halfD), world(-halfW, halfD))
	fenceLine(world(halfW, -halfD), world(halfW, halfD))
	fenceLine(world(-halfW, halfD), world(halfW, halfD))
end

local function buildSign(cf, folder)
	local signCF = cf * CFrame.new(-W.PlotWidth / 2 + 8, 0, -W.PlotDepth / 2 + 2)
	local wood = Color3.fromRGB(120, 80, 50)
	part({ Name = "SignPost", Size = Vector3.new(0.8, 7, 0.8), CFrame = signCF * CFrame.new(-4, 3.5, 0), Color = wood, Material = Enum.Material.Wood }, folder)
	part({ Name = "SignPost", Size = Vector3.new(0.8, 7, 0.8), CFrame = signCF * CFrame.new(4, 3.5, 0), Color = wood, Material = Enum.Material.Wood }, folder)
	-- the board's Front face looks at the plaza (the plot's LookVector)
	local board = part({ Name = "SignBoard", Size = Vector3.new(11, 4.5, 0.6), CFrame = signCF * CFrame.new(0, 6, 0), Color = Color3.fromRGB(250, 240, 220), Material = Enum.Material.Wood }, folder)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(330, 135)
	gui.Parent = board
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -10, 0.62, 0)
	title.Position = UDim2.fromOffset(5, 4)
	title.BackgroundTransparency = 1
	title.Font = Config.Font
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(70, 40, 90)
	title.Text = "Free plot"
	title.Parent = gui
	local sub = title:Clone()
	sub.Size = UDim2.new(1, -10, 0.32, 0)
	sub.Position = UDim2.new(0, 5, 0.64, 0)
	sub.TextColor3 = Color3.fromRGB(150, 90, 170)
	sub.Text = ""
	sub.Parent = gui
	return title, sub
end

local function buildBeds(cf, folder)
	local beds = {}
	for i, spot in ipairs(W.PlantSpots) do
		local bed = part({
			Name = "Bed" .. i, Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 6.5, 6.5),
			CFrame = cf * CFrame.new(spot + Vector3.new(0, 0.05, 0)) * UPRIGHT,
			Color = W.Dirt, Material = Enum.Material.Ground, CanCollide = false,
		}, folder)
		beds[i] = bed
	end
	return beds
end

local function buildPlot(i)
	local cf = Rules.plotCFrame(i)
	local folder = Instance.new("Folder")
	folder.Name = "Plot" .. i
	folder.Parent = worldFolder

	-- a slightly brighter lawn so you can see where your plot is (it stops
	-- short of the hatch pit's rim, so you can still see down into it)
	local lawnBack = W.Hatch.Z - W.PitSize / 2 - 4
	local lawnLength = lawnBack + W.PlotDepth / 2
	part({
		Name = "Lawn", Size = Vector3.new(W.PlotWidth, 1, lawnLength),
		CFrame = cf * CFrame.new(0, -0.45, lawnBack - lawnLength / 2),
		Color = W.Lawn, Material = Enum.Material.Grass, CanCollide = false,
	}, folder)

	local hatchCF = cf * CFrame.new(W.Hatch)
	buildPit(hatchCF, folder)
	buildHouse(cf, W.HouseColors[(i - 1) % #W.HouseColors + 1], folder)
	buildFence(cf, folder)
	local beds = buildBeds(cf, folder)
	local title, sub = buildSign(cf, folder)

	plots[i] = { cframe = cf, hatchCF = hatchCF, beds = beds, sign = title, signSub = sub }
	WorldBuilder.setPlotsOwned(i, 0)
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------
function WorldBuilder.build()
	worldFolder = workspace:FindFirstChild("World")
	if worldFolder then
		worldFolder:Destroy()
	end
	worldFolder = Instance.new("Folder")
	worldFolder.Name = "World"
	worldFolder.Parent = workspace

	buildGround()
	buildPlaza()
	for i = 1, W.Plots do
		buildPlot(i)
	end
	setLighting()
end

function WorldBuilder.plot(i)
	return plots[i]
end

-- Beds you own look like dirt; the rest are faded until you buy them
function WorldBuilder.setPlotsOwned(i, owned)
	local plot = plots[i]
	if not plot then
		return
	end
	for spot, bed in ipairs(plot.beds) do
		if spot <= owned then
			bed.Color = W.Dirt
			bed.Transparency = 0
		else
			bed.Color = Color3.fromRGB(95, 160, 80)
			bed.Transparency = 0.35
		end
	end
end

function WorldBuilder.setSign(i, title, subtitle)
	local plot = plots[i]
	if plot then
		plot.sign.Text = title
		plot.signSub.Text = subtitle or ""
	end
end

return WorldBuilder
