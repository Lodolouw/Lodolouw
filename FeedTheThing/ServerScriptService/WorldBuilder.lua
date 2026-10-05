--[[
	WorldBuilder  (ModuleScript, parent: ServerScriptService, name: "WorldBuilder")

	Puts the world together.

	The map itself - the street, the plots, houses, fences, trees, the seed
	stand and the two tunnels - is a model made in Blender (FeedTheThing/Blender,
	exported as FeedTheThing_Map.fbx). Import it into Studio, name it "Map"
	and put it in ServerStorage (see the README). This script then:
	  * lines it up by its three marker blocks (so the import's size and
	    position don't matter), and makes it glow where it should
	  * adds invisible floors, walls and house blocks to walk on and bump into
	    (cheaper and more reliable than mesh collisions on phones)
	  * adds the parts that change while you play: the dirt in each planter,
	    the name sign over each plot, the seed stand's "Shop" prompt

	No Map yet? It builds a plain stand-in from blocks, so the game still runs.

	The Thing, the plants, the fruit and the Thinglets are drawn by each
	player's own client (StarterPlayerScripts/World).
]]

local WorldBuilder = {}

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Rules = require(ReplicatedStorage:WaitForChild("Rules"))

local W = Config.World

-- the street's layout (the same sums as build_map.py)
local HALF_ROAD = W.RoadWidth / 2
local SIDEWALK_OUT = HALF_ROAD + W.SidewalkWidth
local PLOT_FRONT = SIDEWALK_OUT + W.FrontYard
local PLOT_BACK = PLOT_FRONT + W.PlotDepth
local MAP_Z = PLOT_BACK + W.BackYard
local STREET_X = (W.PlotsPerSide - 1) / 2 * W.PlotSpacing + W.PlotWidth / 2
local ROAD_X = STREET_X + W.RoadPastPlots
local MAP_X = ROAD_X + W.PlazaLength
local PLAZA_Z = W.PlazaHalfWidth
local STAND_X = -(MAP_X - 16) -- the seed stand, facing down the street...
local STAND_Z = W.StandZ -- ...beside the west tunnel

-- where build_map.py put its three marker blocks
local MARKERS = {
	MapOrigin = Vector3.new(0, -30, 0),
	MapMarkX = Vector3.new(100, -30, 0),
	MapMarkZ = Vector3.new(0, -30, 100),
}

local plots = {} -- [i] = { cframe, hatchCF, dirt = {}, sign = {...} }
local worldFolder
local hasMap = false

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Material = Enum.Material.Plastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

-- A block to stand on or bump into. Invisible when the Blender map is
-- there; a simple coloured stand-in when it isn't.
local function solid(name, cf, size, color, parent, studs)
	local p = part({
		Name = name,
		CFrame = cf,
		Size = size,
		Color = color,
		CanTouch = false,
		Transparency = hasMap and 1 or 0,
		CastShadow = not hasMap,
	}, parent)
	if hasMap then
		p.CanQuery = false
	elseif studs and W.Studs then
		p.TopSurface = Enum.SurfaceType.Studs
	end
	return p
end

-- a solid whose top is at `top`, covering x0..x1 and z0..z1
local function slab(name, x0, x1, z0, z1, top, thickness, color, parent, studs)
	return solid(name, CFrame.new((x0 + x1) / 2, top - thickness / 2, (z0 + z1) / 2),
		Vector3.new(math.abs(x1 - x0), thickness, math.abs(z1 - z0)), color, parent, studs)
end

----------------------------------------------------------------------
-- The Blender map
----------------------------------------------------------------------
-- Uploaded models (Config.AssetIds) load by themselves, no Studio import needed
local function loadAsset(id, label)
	if not id or id <= 0 then
		return nil
	end
	local ok, result = pcall(function()
		return game:GetService("InsertService"):LoadAsset(id)
	end)
	if not ok then
		warn("[WorldBuilder] Couldn't load the " .. label .. " (asset " .. id .. "): " .. tostring(result))
		return nil
	end
	return result
end

local function findMapTemplate()
	-- the uploaded map wins (upload.bat keeps it up to date), so an old
	-- import lying around can't sneak in instead
	local id = Config.AssetIds and Config.AssetIds.Map
	local loaded = loadAsset(id, "map")
	if loaded then
		print("[WorldBuilder] Using the uploaded map (asset " .. id .. ")")
		return loaded
	end
	for _, container in ipairs({ ServerStorage, ReplicatedStorage, workspace }) do
		local map = container:FindFirstChild("Map")
		if map and map:IsA("Model") then
			print("[WorldBuilder] Using the imported map " .. map:GetFullName())
			return map
		end
	end
	-- still named after the file? find it by its marker
	for _, container in ipairs({ ServerStorage, workspace }) do
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Model") and child:FindFirstChild("MapOrigin", true) then
				print("[WorldBuilder] Using the imported map " .. child:GetFullName())
				return child
			end
		end
	end
	return nil
end

-- Copies of the map or props imported into Workspace by hand show up as a
-- second, crooked map. Take them out of the game (only while it runs:
-- the place itself is untouched) and say where they are.
local LEFTOVER_MARKS = { "MapOrigin", "MapMarkX", "House1", "Plot1", "Arch", "TunnelEast", "Truck_Origin", "Truck_Body" }
local function removeLeftovers()
	for _, child in ipairs(workspace:GetChildren()) do
		if child ~= worldFolder and (child:IsA("Model") or child:IsA("Folder")) then
			for _, mark in ipairs(LEFTOVER_MARKS) do
				if child:FindFirstChild(mark, true) then
					warn("[WorldBuilder] Took an old copy of the map out of this test: Workspace." .. child.Name
						.. ". Delete it from Workspace in Studio so it's gone for good (the game loads the map by itself).")
					child:Destroy()
					break
				end
			end
		end
	end
end

local function markerPosition(model, name)
	local marker = model:FindFirstChild(name, true)
	if marker and marker:IsA("BasePart") then
		return marker.Position
	end
	return nil
end

-- Scale, turn and move the imported map so its markers land where
-- build_map.py put them. Works whatever size/place Studio imported it at.
local function alignMap(model)
	local o, x, z = markerPosition(model, "MapOrigin"), markerPosition(model, "MapMarkX"), markerPosition(model, "MapMarkZ")
	if not (o and x and z) then
		warn("[WorldBuilder] The map has no MapOrigin/MapMarkX/MapMarkZ blocks, so it's used where it stands.")
		return
	end
	local distance = (x - o).Magnitude
	if distance > 0.0001 and math.abs(distance - 100) > 0.01 then
		model:ScaleTo(model:GetScale() * 100 / distance)
		o, x, z = markerPosition(model, "MapOrigin"), markerPosition(model, "MapMarkX"), markerPosition(model, "MapMarkZ")
	end
	local ax = (x - o).Unit
	local az = (z - o).Unit
	local up = az:Cross(ax)
	if up.Y < 0.5 then
		warn("[WorldBuilder] The map looks flipped or tipped over. Re-export it with build_map.py's settings (see the README).")
	end
	local current = CFrame.fromMatrix(o, ax, up.Unit)
	local target = CFrame.fromMatrix(MARKERS.MapOrigin, Vector3.xAxis, Vector3.yAxis)
	model:PivotTo(target * current:Inverse() * model:GetPivot())
	for name in pairs(MARKERS) do
		local marker = model:FindFirstChild(name, true)
		if marker then
			marker:Destroy()
		end
	end
end

local function prepareMap(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false -- the invisible solids below do the colliding
			d.CanTouch = false
			-- objects named Glow_RRGGBB glow in that colour
			local hex = string.match(d.Name, "^Glow_(%x%x%x%x%x%x)")
			if hex then
				d.Material = Enum.Material.Neon
				d.Color = Color3.fromHex(hex)
				d.CastShadow = false
			end
		end
	end
end

local function placeMap()
	local template = findMapTemplate()
	if not template then
		return false
	end
	local map = template
	if template:IsDescendantOf(ServerStorage) or template:IsDescendantOf(ReplicatedStorage) then
		map = template:Clone()
	end
	map.Name = "Map"
	map.Parent = worldFolder
	local ok, err = pcall(alignMap, map)
	if not ok then
		warn("[WorldBuilder] Couldn't line up the map: " .. tostring(err))
	end
	prepareMap(map)
	return true
end

-- The pieces the map should have. Anything Roblox didn't import is listed
-- in Output, so it's easy to see what went wrong.
local MAP_PIECES = {
	"Grass", "Lawn", "Road", "Sidewalk", "Plaza", "Wall", "WallTop", "StreetProps", "Trees", "Hedges",
	"SeedStand", "TunnelEast", "TunnelWest", "TunnelSignEast", "TunnelSignWest", "House1", "Plot1",
}
local function checkMap(map)
	local missing = {}
	for _, name in ipairs(MAP_PIECES) do
		local piece = map:FindFirstChild(name, true)
		if not piece then
			table.insert(missing, name)
		elseif piece:IsA("BasePart") and piece.Transparency > 0 then
			warn(string.format("[WorldBuilder] Map piece %s is see-through (Transparency %.2f)", name, piece.Transparency))
		end
	end
	if #missing > 0 then
		warn("[WorldBuilder] Roblox didn't import these map pieces: " .. table.concat(missing, ", "))
	end
	return missing
end

-- A tunnel built from blocks, for when the map came without its own: a
-- dark hole in the wall that gets darker further in, and the sign above.
local function buildTunnelStandIn(s, title, textColor)
	local folder = Instance.new("Folder")
	folder.Name = (s > 0 and "TunnelEast" or "TunnelWest") .. "StandIn"
	folder.Parent = worldFolder
	local half = W.TunnelRadius + 2.5 -- the hole in the wall
	local height = W.WallHeight + 1
	local base = Color3.fromRGB(150, 135, 175)
	local bands = { { 0, 3, 0.55 }, { 3, 8, 0.35 }, { 8, 15, 0.2 }, { 15, 24, 0.1 }, { 24, 40, 0.04 } }
	local function block(name, cf, size, color)
		return part({
			Name = name, CFrame = cf, Size = size, Color = color, Material = Enum.Material.SmoothPlastic,
			CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false,
		}, folder)
	end
	for _, band in ipairs(bands) do
		local x = s * (MAP_X + (band[1] + band[2]) / 2)
		local length = band[2] - band[1]
		local color = Color3.new(base.R * band[3], base.G * band[3], base.B * band[3])
		block("Roof", CFrame.new(x, height + 0.5, 0), Vector3.new(length, 1, half * 2 + 2), color)
		block("Floor", CFrame.new(x, 0, 0), Vector3.new(length, 0.4, half * 2), color)
		for _, side in ipairs({ 1, -1 }) do
			block("Side", CFrame.new(x, height / 2, side * (half + 0.5)), Vector3.new(length, height, 1), color)
		end
	end
	block("End", CFrame.new(s * (MAP_X + 40.5), height / 2, 0), Vector3.new(1, height + 1, half * 2 + 2), Color3.new(0, 0, 0))

	local sign = block("Sign", CFrame.new(s * (MAP_X - 1), W.WallHeight + 4, 0), Vector3.new(1.4, 8, 47), Color3.fromRGB(75, 40, 110))
	local gui = Instance.new("SurfaceGui")
	gui.Face = s > 0 and Enum.NormalId.Left or Enum.NormalId.Right -- the side facing the street
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Config.Font
	label.Text = title
	label.TextScaled = true
	label.TextColor3 = textColor
	label.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.18, 0)
	padding.PaddingBottom = UDim.new(0.18, 0)
	padding.Parent = label
end

----------------------------------------------------------------------
-- Floors, walls and blocks (invisible with the map, a stand-in without)
----------------------------------------------------------------------
local function plotXs()
	local xs, seen = {}, {}
	for i = 1, W.Plots do
		local x = Rules.plotCFrame(i).Position.X
		if not seen[x] then
			seen[x] = true
			table.insert(xs, x)
		end
	end
	table.sort(xs)
	return xs
end

local function buildSolids()
	local folder = Instance.new("Folder")
	folder.Name = "Solids"
	folder.Parent = worldFolder
	local grass = W.Grass

	-- the ground outside the plots, in bands across the map
	local gaps, previous = {}, -MAP_X
	for _, x in ipairs(plotXs()) do
		table.insert(gaps, { previous, x - W.PlotWidth / 2 })
		previous = x + W.PlotWidth / 2
	end
	table.insert(gaps, { previous, MAP_X })
	local bands = {
		{ -MAP_Z, -PLOT_BACK, nil }, { -PLOT_BACK, -PLOT_FRONT, gaps }, { -PLOT_FRONT, PLOT_FRONT, nil },
		{ PLOT_FRONT, PLOT_BACK, gaps }, { PLOT_BACK, MAP_Z, nil },
	}
	for _, band in ipairs(bands) do
		for _, span in ipairs(band[3] or { { -MAP_X, MAP_X } }) do
			if span[2] - span[1] > 0.01 then
				slab("Ground", span[1], span[2], band[1], band[2], 0, 4, grass, folder, true)
			end
		end
	end

	-- the street
	slab("Road", -ROAD_X, ROAD_X, -HALF_ROAD, HALF_ROAD, 0.2, 1, W.Road, folder, false)
	for _, s in ipairs({ 1, -1 }) do
		slab("Sidewalk", -ROAD_X, ROAD_X, s * HALF_ROAD, s * SIDEWALK_OUT, 0.4, 1, W.Sidewalk, folder, true)
		slab("Plaza", s * ROAD_X, s * MAP_X, -PLAZA_Z, PLAZA_Z, 0.2, 1, W.Sidewalk, folder, true)
	end

	-- the walls round the map (tall enough that nobody hops out)
	local h = W.WallHeight + 12
	for _, s in ipairs({ 1, -1 }) do
		solid("Wall", CFrame.new(0, h / 2, s * (MAP_Z + 2)), Vector3.new(MAP_X * 2 + 8, h, 4), W.WallA, folder, false)
		solid("Wall", CFrame.new(s * (MAP_X + 2), h / 2, 0), Vector3.new(4, h, MAP_Z * 2 + 8), W.WallB, folder, false)
	end

	-- the seed stand's counter and the pillars either side of each tunnel
	-- (the wall above stops anyone walking into a tunnel)
	solid("SeedStand", CFrame.new(STAND_X, 2, STAND_Z), Vector3.new(4, 3.6, 16), Color3.fromRGB(175, 100, 50), folder, false)
	for _, s in ipairs({ 1, -1 }) do
		for _, side in ipairs({ 1, -1 }) do
			solid("TunnelPillar", CFrame.new(s * (MAP_X - 1.5), 4.5, side * (W.TunnelRadius + 2)), Vector3.new(3, 9, 4), Color3.fromRGB(225, 160, 95), folder, false)
		end
	end
	return folder
end

----------------------------------------------------------------------
-- One plot: its ground (with a hole for the hatch), house block, planter
-- dirt and name sign
----------------------------------------------------------------------
local function buildPlotSolids(i, cf, folder)
	local hx, hz = W.Hatch.X, W.Hatch.Z
	local h = W.PitSize / 2
	local hw, hd = W.PlotWidth / 2, W.PlotDepth / 2
	for _, r in ipairs({
		{ -hw, hx - h, -hd, hd }, { hx + h, hw, -hd, hd },
		{ hx - h, hx + h, -hd, hz - h }, { hx - h, hx + h, hz + h, hd },
	}) do
		local centre = Vector3.new((r[1] + r[2]) / 2, -2, (r[3] + r[4]) / 2)
		solid("Lawn", cf * CFrame.new(centre), Vector3.new(r[2] - r[1], 4, r[4] - r[3]), W.Lawn, folder, true)
	end
	-- walk over the hatch, see straight through it
	part({
		Name = "HatchFloor", Size = Vector3.new(W.PitSize, 1, W.PitSize), CFrame = cf * CFrame.new(hx, -0.5, hz),
		Transparency = 1, CanQuery = false, CanTouch = false,
	}, folder)
	-- the house
	solid("House", cf * CFrame.new(W.House + Vector3.new(0, 9, 0)), Vector3.new(24, 18, 14), W.HouseColors[(i - 1) % #W.HouseColors + 1], folder, false)

	if not hasMap then
		-- stand-in pit and hatch frame
		local dark = Config.Thing.PitColor
		local hatchCF = cf * CFrame.new(W.Hatch)
		part({ Name = "PitFloor", Size = Vector3.new(W.PitSize, 1, W.PitSize), CFrame = hatchCF * CFrame.new(0, -W.PitDepth - 0.5, 0), Color = dark, CanCollide = false }, folder)
		for _, s in ipairs({
			{ Vector3.new(W.PitSize + 2.8, 0.6, 1.4), Vector3.new(0, 0.3, -(h + 0.7)) },
			{ Vector3.new(W.PitSize + 2.8, 0.6, 1.4), Vector3.new(0, 0.3, h + 0.7) },
			{ Vector3.new(1.4, 0.6, W.PitSize), Vector3.new(-(h + 0.7), 0.3, 0) },
			{ Vector3.new(1.4, 0.6, W.PitSize), Vector3.new(h + 0.7, 0.3, 0) },
		}) do
			part({ Name = "HatchFrame", Size = s[1], CFrame = hatchCF * CFrame.new(s[2]), Color = Color3.fromRGB(110, 65, 40), Material = Enum.Material.Wood }, folder)
		end
		for _, s in ipairs({
			{ Vector3.new(W.PitSize, W.PitDepth, 1), Vector3.new(0, -W.PitDepth / 2, -h - 0.5) },
			{ Vector3.new(W.PitSize, W.PitDepth, 1), Vector3.new(0, -W.PitDepth / 2, h + 0.5) },
			{ Vector3.new(1, W.PitDepth, W.PitSize + 2), Vector3.new(-h - 0.5, -W.PitDepth / 2, 0) },
			{ Vector3.new(1, W.PitDepth, W.PitSize + 2), Vector3.new(h + 0.5, -W.PitDepth / 2, 0) },
		}) do
			part({ Name = "PitWall", Size = s[1], CFrame = hatchCF * CFrame.new(s[2]), Color = dark, CanCollide = false }, folder)
		end
	end
end

-- the dirt in each planter box: shown once you own that plot spot
local function buildDirt(cf, folder)
	local dirt = {}
	for spot, position in ipairs(W.PlantSpots) do
		dirt[spot] = part({
			Name = "Dirt" .. spot,
			Size = Vector3.new(6, 0.3, 6),
			CFrame = cf * CFrame.new(position + Vector3.new(0, 0.45, 0)),
			Color = W.Dirt,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
		}, folder)
		if W.Studs then
			dirt[spot].TopSurface = Enum.SurfaceType.Studs
		end
	end
	return dirt
end

-- a floating sign over the gate: the owner's avatar, name and Thing size
local function buildSign(cf, folder)
	local anchor = part({
		Name = "SignAnchor", Size = Vector3.new(1, 1, 1), CFrame = cf * CFrame.new(0, 16, -W.PlotDepth / 2 + 2),
		Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false,
	}, folder)
	local gui = Instance.new("BillboardGui")
	gui.Name = "OwnerSign"
	gui.Size = UDim2.fromScale(20, 5)
	gui.LightInfluence = 0
	gui.MaxDistance = 200
	gui.Adornee = anchor
	gui.Parent = anchor

	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.Size = UDim2.fromScale(0.25, 1)
	avatar.BackgroundColor3 = Color3.fromRGB(40, 30, 60)
	avatar.Image = ""
	avatar.Visible = false
	avatar.Parent = gui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.Parent = avatar
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = avatar
	local ring = Instance.new("UIStroke")
	ring.Thickness = 3
	ring.Color = Color3.fromRGB(255, 255, 255)
	ring.Parent = avatar

	local function label(name, position, size, color)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = position
		l.Size = size
		l.Font = Config.Font
		l.TextScaled = true
		l.TextColor3 = color
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Text = ""
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = Color3.fromRGB(20, 12, 32)
		stroke.Parent = l
		l.Parent = gui
		return l
	end
	local title = label("Title", UDim2.fromScale(0.28, 0.02), UDim2.fromScale(0.72, 0.6), Color3.fromRGB(255, 255, 255))
	local sub = label("Sub", UDim2.fromScale(0.28, 0.62), UDim2.fromScale(0.72, 0.36), Color3.fromRGB(215, 255, 90))
	return { title = title, sub = sub, avatar = avatar }
end

local function buildPlot(i, solids)
	local cf = Rules.plotCFrame(i)
	local folder = Instance.new("Folder")
	folder.Name = "Plot" .. i
	folder.Parent = worldFolder
	buildPlotSolids(i, cf, solids)
	plots[i] = {
		cframe = cf,
		hatchCF = cf * CFrame.new(W.Hatch),
		dirt = buildDirt(cf, folder),
		sign = buildSign(cf, folder),
		userId = 0,
	}
	WorldBuilder.setPlotsOwned(i, 0)
	WorldBuilder.setSign(i, "Free plot", "", 0)
end

local function buildShopPrompt()
	local spot = part({
		Name = "SeedShopSpot", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(STAND_X + 3.5, 3, STAND_Z),
		Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false,
	}, worldFolder)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SeedShopPrompt"
	prompt.ActionText = "Open the shop"
	prompt.ObjectText = "Seed Stand"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = spot
end

local function setLighting()
	Lighting.ClockTime = 14
	Lighting.Brightness = 3
	Lighting.GlobalShadows = true
	Lighting.Ambient = Color3.fromRGB(120, 115, 130)
	Lighting.OutdoorAmbient = Color3.fromRGB(165, 160, 175)
	Lighting.EnvironmentDiffuseScale = 0.5
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.18
		atmosphere.Haze = 0.2
		atmosphere.Color = Color3.fromRGB(205, 225, 255)
		atmosphere.Decay = Color3.fromRGB(150, 180, 230)
		atmosphere.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("ColorCorrectionEffect") then
		local grade = Instance.new("ColorCorrectionEffect")
		grade.Saturation = 0.12
		grade.Contrast = 0.05
		grade.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("BloomEffect") then
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.5
		bloom.Size = 18
		bloom.Threshold = 1.7
		bloom.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("Sky") then
		Instance.new("Sky").Parent = Lighting -- the default sky (it has the moon for Full Moon nights)
	end
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------
function WorldBuilder.build()
	-- a new place comes with a Baseplate and a SpawnLocation: they'd cover
	-- the hatch pits and spawn people in the wrong spot, so clear them
	-- (only while the game runs - your saved place keeps them)
	for _, child in ipairs(workspace:GetChildren()) do
		if (child.Name == "Baseplate" and child:IsA("BasePart")) or child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end
	workspace.Terrain:Clear()

	local old = workspace:FindFirstChild("World")
	if old then
		old:Destroy()
	end
	worldFolder = Instance.new("Folder")
	worldFolder.Name = "World"
	worldFolder.Parent = workspace

	-- the props (delivery truck...) for every client, in ReplicatedStorage.Props.
	-- The uploaded ones win over an import.
	local props = loadAsset(Config.AssetIds and Config.AssetIds.Props, "props")
	if props then
		local imported = ReplicatedStorage:FindFirstChild("Props")
		if imported then
			imported:Destroy()
		end
		props.Name = "Props"
		props.Parent = ReplicatedStorage
	end
	-- an old import named "Assets" clashes with the Assets module: rename it
	for _, child in ipairs(ReplicatedStorage:GetChildren()) do
		if child.Name == "Assets" and not child:IsA("ModuleScript") then
			if ReplicatedStorage:FindFirstChild("Props") then
				child:Destroy()
			else
				child.Name = "Props"
			end
		end
	end
	hasMap = placeMap()
	removeLeftovers()
	if not hasMap then
		warn("[WorldBuilder] No Blender map found, so you're seeing simple stand-in blocks. Import "
			.. "FeedTheThing/Blender/Export/FeedTheThing_Map.fbx, name it \"Map\" and put it in ServerStorage (see the README).")
	else
		local map = worldFolder:FindFirstChild("Map")
		local missing = map and checkMap(map) or {}
		if table.find(missing, "TunnelEast") then
			buildTunnelStandIn(1, "FEED THE THING", Color3.fromRGB(190, 255, 70))
		end
		if table.find(missing, "TunnelWest") then
			buildTunnelStandIn(-1, "SEED EXPRESS", Color3.fromRGB(255, 215, 60))
		end
	end
	local solids = buildSolids()
	for i = 1, W.Plots do
		buildPlot(i, solids)
	end
	buildShopPrompt()
	setLighting()
end

function WorldBuilder.plot(i)
	return plots[i]
end

-- Planters you own get dirt; the rest stay empty until you buy them
function WorldBuilder.setPlotsOwned(i, owned)
	local plot = plots[i]
	if not plot then
		return
	end
	for spot, dirt in ipairs(plot.dirt) do
		dirt.Transparency = spot <= owned and 0 or 1
	end
end

-- The sign over the gate. userId > 0 shows that player's avatar.
function WorldBuilder.setSign(i, title, subtitle, userId)
	local plot = plots[i]
	if not plot then
		return
	end
	plot.sign.title.Text = title
	plot.sign.sub.Text = subtitle or ""
	userId = userId or 0
	local gui = plot.sign.title.Parent
	if gui and gui:IsA("BillboardGui") then
		gui.Enabled = userId > 0
	end
	if userId == plot.userId then
		return
	end
	plot.userId = userId
	plot.sign.avatar.Visible = false
	plot.sign.avatar.Image = ""
	if userId > 0 then
		task.spawn(function()
			local ok, image = pcall(function()
				return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
			end)
			if ok and plot.userId == userId then
				plot.sign.avatar.Image = image
				plot.sign.avatar.Visible = true
			end
		end)
	end
end

return WorldBuilder
