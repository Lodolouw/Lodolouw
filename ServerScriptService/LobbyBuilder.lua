--[[
	LobbyBuilder  (ModuleScript, parent: ServerScriptService, name: "LobbyBuilder")

	Builds the whole starter lobby out of Parts when the server starts:
	  * toy-brick island, paths, walls, trees, lamps
	  * Sell Shop, Upgrade Shop (mushroom house), Armory (blacksmith forge), Prestige Shrine
	  * Training Yard: six practice-dummy pads with multiplier signs
	  * the castle gate, and the stairs and bridge up to the Spire (the boss floors)

	Coordinates: the island is 240x240 studs centred on (0,0,0), ground top at y = 0.
	North is -Z. Spawn is south of the shrine, the training yard is at the south end.

	Everything animated is tagged "FX" (see LobbyFX). Prompts are tagged "PanelPrompt"
	(see PlayerService). Dummies are tagged "Dummy", multiplier signs "ZoneSign".
]]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local InsertService = game:GetService("InsertService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local LobbyBuilder = {}

local FONT = Enum.Font.FredokaOne
local V3 = Vector3.new
local RGB = Color3.fromRGB
local Mat = Enum.Material

----------------------------------------------------------------------
-- Small building helpers
----------------------------------------------------------------------
local function part(parent, name, size, cf, color, material, extra)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Mat.Plastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if extra then
		for k, v in pairs(extra) do
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function ball(parent, name, diameter, cf, color, material, extra)
	local e = { Shape = Enum.PartType.Ball }
	if extra then
		for k, v in pairs(extra) do
			e[k] = v
		end
	end
	return part(parent, name, V3(diameter, diameter, diameter), cf, color, material, e)
end

-- Upright cylinder: `cf` is the desired centre/orientation, the axis points up.
local function cylinder(parent, name, height, diameter, cf, color, material, extra)
	local e = { Shape = Enum.PartType.Cylinder }
	if extra then
		for k, v in pairs(extra) do
			e[k] = v
		end
	end
	return part(parent, name, V3(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.pi / 2), color, material, e)
end

-- Flat disc whose faces point along local Z (like a coin standing on its edge)
local function discZ(parent, name, thickness, diameter, cf, color, material, extra)
	local e = { Shape = Enum.PartType.Cylinder }
	if extra then
		for k, v in pairs(extra) do
			e[k] = v
		end
	end
	return part(parent, name, V3(thickness, diameter, diameter), cf * CFrame.Angles(0, math.pi / 2, 0), color, material, e)
end

local function folder(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function anchorPart(parent, name, cf)
	return part(parent, name, V3(1, 1, 1), cf, RGB(255, 255, 255), Mat.SmoothPlastic, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
end

-- Mark a part for the client-side animator (spin / bob / orbit)
local function fx(p, attrs)
	for k, v in pairs(attrs) do
		p:SetAttribute(k, v)
	end
	CollectionService:AddTag(p, "FX")
end

local function addPrompt(parent, panel, action, object, distance)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = 0
	pp.MaxActivationDistance = distance or 14
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.GamepadKeyCode = Enum.KeyCode.ButtonX
	pp.RequiresLineOfSight = false
	pp:SetAttribute("Panel", panel)
	pp.Parent = parent
	CollectionService:AddTag(pp, "PanelPrompt")
	return pp
end

-- An invisible box: walking into it opens that station's menu on your
-- screen, and walking out closes it again (the HUD / SpireClient watch these).
local function autoZone(parent, cf, size, attr, value)
	local z = part(parent, "AutoOpenZone", size, cf, RGB(255, 255, 255), Mat.SmoothPlastic, {
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

local function billboard(adornee, name, size, maxDistance)
	local bb = Instance.new("BillboardGui")
	bb.Name = name
	bb.Adornee = adornee
	bb.Size = size
	bb.MaxDistance = maxDistance or 220
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.Parent = adornee
	return bb
end

local function billLabel(parent, name, text, color, pos, size)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = pos
	l.Size = size
	l.Font = FONT
	l.Text = text
	l.TextColor3 = color
	l.TextScaled = true
	l.Parent = parent
	local s = Instance.new("UIStroke")
	s.Thickness = 3
	s.Color = RGB(20, 20, 40)
	s.Parent = l
	return l
end

-- A floating two-line sign: big title + small subtitle. `maxDistance` defaults
-- to a short read range so signs only show up once you're actually near that
-- station - without it every sign stays visible across the whole island and
-- they all pile up on top of each other from a distance.
--
-- Sized in studs (UDim2.fromScale on a BillboardGui = studs), not screen
-- pixels, so it behaves like a real sign: readable up close, smaller the
-- further away you are - instead of staying the same huge size on screen
-- from anywhere. `width` is the old pixel width; 340 maps to 14 studs wide.
local SIGN_STUDS_PER_PIXEL = 14 / 340

local function titleSign(parent, cf, title, subtitle, titleColor, width, maxDistance)
	local anchor = anchorPart(parent, "SignAnchor", cf)
	local studsWide = (width or 340) * SIGN_STUDS_PER_PIXEL
	local bb = billboard(anchor, "Sign", UDim2.fromScale(studsWide, studsWide * 0.35), maxDistance or 85)
	-- (in the game's look: a black box with a thick white border)
	local box = Instance.new("Frame")
	box.Name = "Box"
	box.BackgroundColor3 = RGB(12, 10, 20)
	box.BackgroundTransparency = 0.15
	box.Size = UDim2.fromScale(1, 1)
	box.ZIndex = 0
	box.Parent = bb
	local edge = Instance.new("UIStroke")
	edge.Color = RGB(255, 255, 255)
	edge.Thickness = 3
	edge.Parent = box
	-- (just the name: the old line of text under it is gone)
	bb.Size = UDim2.fromScale(studsWide, studsWide * 0.22)
	billLabel(bb, "Title", title, titleColor, UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.8))
	return anchor
end

-- A blocky shopkeeper. Faces local +Z of `origin`. Assumes the floor top is at y = 0.8.
local function npc(parent, origin, x, z, shirt, hatColor)
	local m = Instance.new("Model")
	m.Name = "Shopkeeper"
	m.Parent = parent
	local skin = RGB(255, 214, 170)
	part(m, "Legs", V3(3, 3, 1.8), origin * CFrame.new(x, 2.3, z), RGB(60, 70, 110))
	part(m, "Torso", V3(3.6, 3.4, 2), origin * CFrame.new(x, 5.5, z), shirt)
	part(m, "ArmL", V3(1, 3.2, 1.2), origin * CFrame.new(x - 2.4, 5.4, z), skin)
	part(m, "ArmR", V3(1, 3.2, 1.2), origin * CFrame.new(x + 2.4, 5.4, z), skin)
	local head = part(m, "Head", V3(2.8, 2.8, 2.8), origin * CFrame.new(x, 8.6, z), skin)
	local face = Instance.new("Decal")
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Back -- local +Z
	face.Parent = head
	if hatColor then
		part(m, "HatBrim", V3(3.6, 0.6, 3.6), origin * CFrame.new(x, 10.3, z), hatColor)
		part(m, "HatTop", V3(2.4, 1.8, 2.4), origin * CFrame.new(x, 11.5, z), hatColor)
	end
	return m
end

-- Real Roblox avatar shopkeepers, loaded from models the developer uploaded
-- (InsertService can load models owned by the game's creator). Loaded in
-- the background so the lobby doesn't wait on the network. If a model can't
-- be loaded (offline, wrong id, not accessible), `fallback` builds the old
-- blocky shopkeeper instead, so a shop is never left empty.
--
-- `height` (optional) forces that exact height in studs - handy for
-- things that aren't people, like the toad.
-- `turn` (optional) spins the model in degrees if it faces the wrong way:
-- -90 = quarter turn to its right, 90 = to its left, 180 = turn around.
--
-- Easiest way to use ANY model (even one you don't own): put a copy in
-- ServerStorage named "ToadNPC", "BlacksmithNPC" or "ShopkeeperNPC" - if
-- that's there, it's used instead of loading the id below.
local NPC_MODELS = {
	Toad = { id = 4816047695, height = 4.5, turn = -90 }, -- a real toad, by the mushroom house (Upgrade Shop)
	Smith = { id = 106244394777485 }, -- Armory (blacksmith forge)
	Shopkeeper = { id = 91467356738952 }, -- Sell Shop
}

-- Shopkeepers are resized to about this many studs tall if their model is
-- much bigger or smaller (a normal Roblox avatar is ~5-6).
local NPC_HEIGHT = 6.5

-- `cframe` = where to stand and which way to face; `floorY` = the world
-- height of the floor there, so the feet land exactly on it.
local function avatarNPC(parent, info, name, cframe, floorY, fallback)
	local assetId = info.id
	local targetHeight = info.height or NPC_HEIGHT
	task.spawn(function()
		local ok, container
		-- 1) a copy placed in ServerStorage wins (works for any model)
		local override = ServerStorage:FindFirstChild(name .. "NPC")
		if override then
			ok, container = true, override:Clone()
		end
		-- 2) otherwise load it by id. A model uploaded moments ago can still
		-- be under review, so try a few times before giving up.
		for attempt = 1, 4 do
			if ok and container then
				break -- already have it (from ServerStorage)
			end
			ok, container = pcall(function()
				return InsertService:LoadAsset(assetId)
			end)
			if ok and container then
				break
			end
			if attempt < 4 then
				task.wait(5)
			end
		end

		-- Prefer a proper character (a Model with a Humanoid). If there isn't
		-- one - e.g. the model is a mesh or a rig without a Humanoid - use the
		-- whole model anyway as a statue-style shopkeeper.
		local rig
		if ok and container then
			if container:FindFirstChildOfClass("Humanoid") then
				rig = container
			else
				for _, d in ipairs(container:GetDescendants()) do
					if d:IsA("Model") and d:FindFirstChildOfClass("Humanoid") then
						rig = d
						break
					end
				end
			end
			if not rig and container:FindFirstChildWhichIsA("BasePart", true) then
				rig = container
			end
		end
		if not rig then
			warn("[LobbyBuilder] Couldn't load the " .. name .. " model (" .. tostring(assetId) .. "), using the blocky one instead. "
				.. (ok and "The model has no parts in it." or tostring(container)))
			if fallback then
				fallback()
			end
			return
		end

		rig.Name = name
		for _, d in ipairs(rig:GetDescendants()) do
			if d:IsA("Script") or d:IsA("LocalScript") then
				d:Destroy() -- a shopkeeper doesn't need any code of its own
			elseif d:IsA("BasePart") then
				d.Anchored = true -- stand still, never fall over
			end
		end
		local hum = rig:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end

		-- Resize anything that isn't roughly character-sized (e.g. a model
		-- uploaded at a huge scale) to NPC_HEIGHT studs tall.
		local _, rawSize = rig:GetBoundingBox()
		if info.height or rawSize.Y > NPC_HEIGHT * 1.15 or rawSize.Y < NPC_HEIGHT * 0.6 then
			pcall(function()
				rig:ScaleTo(rig:GetScale() * targetHeight / rawSize.Y)
			end)
		end

		rig:PivotTo(cframe * CFrame.Angles(0, math.rad(info.turn or 0), 0))
		local boxCf, boxSize = rig:GetBoundingBox()
		local feet = boxCf.Position.Y - boxSize.Y / 2
		rig:PivotTo(rig:GetPivot() + Vector3.new(0, floorY - feet, 0))
		rig.Parent = parent
		if container ~= rig then
			container:Destroy()
		end
		print("[LobbyBuilder] " .. name .. " loaded" .. (hum and "" or " (no Humanoid - placed as a statue)"))
	end)
end

-- Where a shopkeeper stands: (x, z) in the station's own coordinates,
-- turned round to face the customer (characters look down their -Z).
local function facingCustomer(O, x, z)
	return O * CFrame.new(x, 0, z) * CFrame.Angles(0, math.pi, 0)
end

----------------------------------------------------------------------
-- Lighting
----------------------------------------------------------------------
local function setupLighting()
	Lighting.ClockTime = 15.5
	Lighting.Brightness = 1.5
	Lighting.Ambient = RGB(70, 74, 96)
	Lighting.OutdoorAmbient = RGB(78, 82, 104)

	for _, n in ipairs({ "LobbyAtmosphere", "LobbyBloom", "LobbyColor" }) do
		local old = Lighting:FindFirstChild(n)
		if old then
			old:Destroy()
		end
	end

	local atmo = Instance.new("Atmosphere")
	atmo.Name = "LobbyAtmosphere"
	atmo.Density = 0.26
	atmo.Offset = 0.15
	atmo.Color = RGB(176, 190, 220)
	atmo.Decay = RGB(110, 116, 136)
	atmo.Glare = 0
	atmo.Haze = 0.4
	atmo.Parent = Lighting

	-- Kept low: with this many Neon parts around the lobby (dummy edges, signs,
	-- coins, beams) a strong bloom stacks up fast and washes the whole scene
	-- out white, which is exactly what made everything look "too bright."
	-- Turned down further still since it was still reading as too vibrant
	-- even after the first pass.
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "LobbyBloom"
	bloom.Intensity = 0.16
	bloom.Size = 18
	bloom.Threshold = 1.9
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "LobbyColor"
	cc.Saturation = -0.1
	cc.Contrast = 0.02
	cc.Parent = Lighting
end

----------------------------------------------------------------------
-- Ground, walls, decoration
----------------------------------------------------------------------
local WALL_HEIGHT = 46
-- The castle reaches further south than it's wide, to hold the training
-- yard's raised second tier: its south wall sits this much beyond the
-- other three (which stay 118 studs out from the middle).
local SOUTH_EXT = 56
local SOUTH_WALL = 118 + SOUTH_EXT
local SOUTH_GATE_HALF = 16 -- half the width of the gap for the south gatehouse

-- A tall stone castle wall segment between two points: crenellated merlons
-- along the top, and moss/ivy climbing the inner face. Much taller than a
-- normal starter-lobby wall on purpose, and mossy stone instead of clean
-- brick so it reads as an old, overgrown castle rather than a toy one.
local function wall(parent, name, a, b)
	local center = (a + b) / 2
	local dx = math.abs(b.X - a.X)
	local dz = math.abs(b.Z - a.Z)
	local alongX = dx > dz
	local length = alongX and dx or dz
	local stone = RGB(142, 144, 150)
	local stoneDark = RGB(110, 112, 118)
	local moss = RGB(96, 150, 74)

	local size = alongX and V3(length, WALL_HEIGHT, 6) or V3(6, WALL_HEIGHT, length)
	part(parent, name, size, CFrame.new(center.X, WALL_HEIGHT / 2, center.Z), stone, Mat.Cobblestone)

	-- Crenellated top
	local mCount = math.floor(length / 8)
	for i = 0, mCount - 1 do
		local offset = -length / 2 + 4 + i * 8
		local pos = alongX and V3(center.X + offset, WALL_HEIGHT + 2.5, center.Z) or V3(center.X, WALL_HEIGHT + 2.5, center.Z + offset)
		part(parent, name .. "_Merlon" .. i, V3(4.5, 5, 4.5), CFrame.new(pos), stoneDark, Mat.Cobblestone)
	end

	-- Moss patches climbing the inner face (the side facing the lobby)
	local innerZ = alongX and (center.Z - (center.Z / math.abs(center.Z)) * 4) or center.Z
	local innerX = (not alongX) and (center.X - (center.X / math.abs(center.X)) * 4) or center.X
	local mossCount = math.floor(length / 14)
	for i = 0, mossCount - 1 do
		local offset = -length / 2 + 7 + i * 14
		local h = 3 + (i % 4) * 6
		local mx = alongX and (center.X + offset) or innerX
		local mz = alongX and innerZ or (center.Z + offset)
		ball(parent, name .. "_Moss" .. i, 5 + (i % 3), CFrame.new(mx, h, mz), moss, Mat.LeafyGrass, {
			CanCollide = false,
		})
	end

	-- A few longer ivy strands hanging from the top
	local ivyCount = math.floor(length / 26)
	for i = 0, ivyCount - 1 do
		local offset = -length / 2 + 13 + i * 26
		local len = 14 + (i % 3) * 6
		local ix = alongX and (center.X + offset) or innerX
		local iz = alongX and innerZ or (center.Z + offset)
		part(parent, name .. "_Ivy" .. i, V3(0.6, len, 0.6), CFrame.new(ix, WALL_HEIGHT - len / 2, iz), moss, Mat.Grass, {
			CanCollide = false,
			CanQuery = false,
		})
	end
end

-- THE tree of the game: a chunky leafy tree built from blocks (every leafy
-- tree in the lobby and on the island is this one, at different sizes, so
-- they all match), and a matching blocky bush
local VT_TRUNK, VT_LEAF, VT_LEAF2, VT_LEAF3 = RGB(115, 62, 57), RGB(99, 199, 77), RGB(62, 137, 72), RGB(38, 92, 66)
local function voxelTree(m, x, z, s, y0)
	y0 = y0 or 0
	part(m, "Trunk", V3(2.4, 9, 2.4) * s, CFrame.new(x, y0 + 4.5 * s, z), VT_TRUNK, Mat.Wood)
	part(m, "Root", V3(4, 1, 1.2) * s, CFrame.new(x, y0 + 0.5 * s, z), VT_TRUNK, Mat.Wood)
	part(m, "Root", V3(1.2, 1, 4) * s, CFrame.new(x, y0 + 0.5 * s, z), VT_TRUNK, Mat.Wood)
	part(m, "Branch", V3(1.2, 4, 1.2) * s, CFrame.new(x + 1.6 * s, y0 + 8.5 * s, z) * CFrame.Angles(0, 0, math.rad(-35)), VT_TRUNK, Mat.Wood)
	part(m, "Canopy", V3(12, 6, 12) * s, CFrame.new(x, y0 + 11 * s, z), VT_LEAF2, Mat.Grass)
	part(m, "CanopyTop", V3(9, 4, 9) * s, CFrame.new(x - 0.5 * s, y0 + 15.5 * s, z + 0.5 * s), VT_LEAF, Mat.Grass)
	part(m, "CanopyCrown", V3(5, 2, 5) * s, CFrame.new(x + 0.5 * s, y0 + 18.2 * s, z - 0.5 * s), VT_LEAF, Mat.Grass)
	for _, o in ipairs({ { 5, 9.5, 2 }, { -5, 10, -2 }, { 1.5, 9, -5 }, { -2, 9.5, 5 } }) do
		part(m, "CanopyLump", V3(6, 4, 6) * s, CFrame.new(x + o[1] * s, y0 + o[2] * s, z + o[3] * s), (o[1] > 0) and VT_LEAF2 or VT_LEAF3, Mat.Grass)
	end
	for _, o in ipairs({ { 3, 14, 3 }, { -3.5, 13.5, -2 } }) do
		part(m, "CanopyLight", V3(3, 2, 3) * s, CFrame.new(x + o[1] * s, y0 + o[2] * s, z + o[3] * s), VT_LEAF, Mat.Grass)
	end
end
local function voxelBush(m, x, z, s, y0)
	y0 = y0 or 0
	part(m, "Bush", V3(3.4, 2.4, 3.4) * s, CFrame.new(x, y0 + 1.2 * s, z), VT_LEAF2, Mat.Grass, { CanCollide = false })
	part(m, "Bush", V3(2.4, 1.8, 2.4) * s, CFrame.new(x + 1 * s, y0 + 2.6 * s, z - 0.4 * s), VT_LEAF, Mat.Grass, { CanCollide = false })
	part(m, "Bush", V3(2, 1.6, 2) * s, CFrame.new(x - 1.4 * s, y0 + 1.1 * s, z + 1.2 * s), VT_LEAF3, Mat.Grass, { CanCollide = false })
end

local function tree(parent, x, z, s)
	voxelTree(parent, x, z, (s or 1) * 0.95)
end

-- A small warm lantern rather than a bright streetlamp - Neon parts glow at
-- full brightness regardless of the scene's lighting settings, so a big one
-- reads as a little flashbulb up close. Kept small and dim on purpose for a
-- cozy look instead of a lit-up road.
local function lamp(parent, x, z)
	-- A street lantern: a stepped stone foot, a dark iron post with gold
	-- collars, and a little lantern on top - a glowing core inside a cage of
	-- four bars, under a stepped roof with a gold finial. Kept small and warm
	-- on purpose: Neon glows at full brightness whatever the lighting, so a
	-- big one reads as a flashbulb up close.
	local m = Instance.new("Model")
	m.Name = "Lamp"
	m.Parent = parent
	local stoneDark, iron, gold = RGB(96, 100, 116), RGB(52, 54, 68), RGB(214, 170, 70)
	part(m, "Foot", V3(2.6, 0.8, 2.6), CFrame.new(x, 0.4, z), stoneDark, Mat.Slate)
	part(m, "Foot2", V3(1.9, 0.6, 1.9), CFrame.new(x, 1.1, z), RGB(130, 134, 150), Mat.Slate)
	part(m, "Post", V3(1, 9.6, 1), CFrame.new(x, 6.2, z), iron, Mat.Metal)
	for _, y in ipairs({ 3.2, 10.4 }) do
		part(m, "Collar", V3(1.5, 0.4, 1.5), CFrame.new(x, y, z), gold, Mat.Metal, { CanCollide = false })
	end
	part(m, "LanternFloor", V3(2.3, 0.3, 2.3), CFrame.new(x, 11.15, z), iron, Mat.Metal)
	for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		part(m, "LanternBar", V3(0.3, 1.9, 0.3), CFrame.new(x + c[1] * 0.95, 12.25, z + c[2] * 0.95), iron, Mat.Metal, { CanCollide = false })
	end
	local bulb = part(m, "Bulb", V3(1.3, 1.5, 1.3), CFrame.new(x, 12.2, z), RGB(255, 208, 130), Mat.Neon, { CanCollide = false })
	part(m, "Roof", V3(2.7, 0.4, 2.7), CFrame.new(x, 13.4, z), iron, Mat.Metal)
	part(m, "Roof2", V3(1.8, 0.4, 1.8), CFrame.new(x, 13.8, z), iron, Mat.Metal)
	part(m, "Finial", V3(0.7, 0.7, 0.7), CFrame.new(x, 14.35, z) * CFrame.Angles(0, math.rad(45), 0), gold, Mat.Metal, { CanCollide = false })
	local light = Instance.new("PointLight")
	light.Range = 15
	light.Brightness = 0.75
	light.Color = RGB(255, 200, 130)
	light.Parent = bulb
end

local TREES = {
	{ 60, -100, 1.1 }, { 88, -92, 0.9 }, { -52, -30, 1 }, { -100, -30, 1 },
	{ -104, 20, 1 }, { -40, 30, 0.9 }, { 98, 60, 1 }, { 50, 164, 0.9 },
}

local LAMPS = {
	{ -12, -30 }, { 12, -30 }, { -12, -66 }, { 12, -66 },
	{ 40, 11 }, { 70, 11 }, { -40, -11 }, { -66, -11 },
	{ 11, 60 }, { -11, 110 }, { 11, 110 }, { -11, 150 }, { 11, 150 },
}

local function buildGround(parent)
	local g = folder(parent, "Ground")

	part(g, "Island", V3(236, 6, 236 + SOUTH_EXT), CFrame.new(0, -3, SOUTH_EXT / 2), RGB(96, 192, 84), Mat.Plastic, {
		TopSurface = Enum.SurfaceType.Studs,
	})

	-- Paths: warm cobblestone with a low brick curb along each side. Split
	-- into pieces that start and stop at the buildings (instead of running
	-- underneath them), with gaps in the curbs wherever two paths meet so
	-- the joins are seamless. Path tops sit just under the plaza's outer
	-- ring so overlapping surfaces never flicker.
	local PATH_COLOR = RGB(208, 192, 162)
	local CURB_COLOR = RGB(146, 118, 92)
	local pathRects = {} -- (every paved rectangle, for the rim round them all)
	local function pathSlab(name, x0, z0, x1, z1)
		part(g, name, V3(x1 - x0, 0.55, z1 - z0), CFrame.new((x0 + x1) / 2, 0.275, (z0 + z1) / 2), PATH_COLOR, Mat.Cobblestone)
		table.insert(pathRects, { x0, z0, x1, z1 })
	end
	-- (the rim is worked out automatically round the outline of all the
	-- paths together, so it opens by itself wherever two paths meet)
	local function curbAlongX() end
	local function curbAlongZ() end

	-- The floorplan: the fountain plaza in the middle, a wide avenue north
	-- to the Grand Keep (and through it to the Spire), the road east to the
	-- forge in the Gear Hall, west to the Pet Sanctuary, south past the
	-- Sell Shop and the colosseum to the south gate.
	local Y = Config.Yard
	-- north: the avenue to the keep, and the floor of the passage through it
	pathSlab("PathToGate", -9, -74, 9, -17) -- (tucked under the plaza's edge: no grass gaps)
	curbAlongZ(-74, -23.5, -9.5)
	curbAlongZ(-74, -23.5, 9.5)
	pathSlab("StairLanding", -12, -112, 12, -74)
	-- east: to the forge's front door
	pathSlab("PathEastWest", 17, -8, 80, 8)
	pathSlab("PathToForge", 62, -19, 80, -8)
	curbAlongX(23.5, 80, 8.5)
	curbAlongX(23.5, 61.5, -8.5)
	-- west: to the Pet Sanctuary garden
	pathSlab("PathEastWest", -88, -8, -17, 8)
	pathSlab("PathForgeSide", -88, -58, -72, -8)
	curbAlongX(-88, -23.5, 8.5)
	curbAlongX(-71.5, -23.5, -8.5)
	-- south: past the spawn to the south gate, with branches to the Sell
	-- Shop and into the colosseum
	pathSlab("PathToYard", -8, 17, 8, SOUTH_WALL) -- (right up to the gate's paving)
	pathSlab("PathEastWest", 8, 38, 29, 52)
	pathSlab("PathEastWest", -12, 84, -8, 96)
	curbAlongZ(23.5, 37.5, 8.5)
	curbAlongZ(52.5, 93.5, 8.5) -- (a gap where the farm path joins)
	curbAlongZ(98.5, SOUTH_WALL - 3, 8.5)
	curbAlongZ(23.5, 83.5, -8.5)
	curbAlongZ(96.5, SOUTH_WALL - 3, -8.5)

	-- Central plaza rings (outer ring in the same stone as the paths)
	cylinder(g, "PlazaOuter", 0.6, 46, CFrame.new(0, 0.3, 0), PATH_COLOR, Mat.Cobblestone)
	-- brick border round the plaza, open where the paths come in
	-- The rim: a low brick curb all round the outline of the paths and the
	-- plaza together. Worked out on a 1-stud grid: every square next to the
	-- paving (but not paved itself) gets curb, then neighbouring squares
	-- are joined into long pieces. Where paths meet there's no gap in the
	-- paving, so no curb - every junction opens up by itself.
	do
		local NOCURB = { { 7, 88, 20, 104 } } -- (the farm path leaves the south road here: no rim)
		local PLAZA_R = 23.2
		local X0, X1, Z0, Z1 = -118, 118, -112, SOUTH_WALL - 1
		local function paved(x, z)
			if x * x + z * z < PLAZA_R * PLAZA_R then
				return true
			end
			for _, r in ipairs(pathRects) do
				if x > r[1] and x < r[3] and z > r[2] and z < r[4] then
					return true
				end
			end
			return false
		end
		local function noCurb(x, z)
			for _, r in ipairs(NOCURB) do
				if x > r[1] and x < r[3] and z > r[2] and z < r[4] then
					return true
				end
			end
			return false
		end
		local NX, NZ = X1 - X0, Z1 - Z0
		local grid = {}
		for j = 1, NZ do
			local row = {}
			for i = 1, NX do
				row[i] = paved(X0 + i - 0.5, Z0 + j - 0.5)
			end
			grid[j] = row
		end
		local function isCurb(i, j)
			if grid[j][i] or noCurb(X0 + i - 0.5, Z0 + j - 0.5) then
				return false
			end
			for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
				local r = grid[j + d[2]]
				if r and r[i + d[1]] then
					return true
				end
			end
			return false
		end
		local open = {}
		for j = 1, NZ + 1 do
			local runs = {}
			if j <= NZ then
				local i = 1
				while i <= NX do
					if isCurb(i, j) then
						local k = i
						while k + 1 <= NX and isCurb(k + 1, j) do
							k = k + 1
						end
						runs[i .. ":" .. k] = { i, k }
						i = k + 1
					else
						i = i + 1
					end
				end
			end
			local nextOpen = {}
			for key, r in pairs(runs) do
				nextOpen[key] = { r[1], r[2], open[key] and open[key][3] or j }
			end
			for key, o in pairs(open) do
				if not runs[key] then
					local x0, x1 = X0 + o[1] - 1, X0 + o[2]
					local z0, z1 = Z0 + o[3] - 1, Z0 + j - 1
					part(g, "Curb", V3(x1 - x0, 0.9, z1 - z0), CFrame.new((x0 + x1) / 2, 0.45, (z0 + z1) / 2), CURB_COLOR, Mat.Brick)
				end
			end
			open = nextOpen
		end
	end
	cylinder(g, "PlazaMid", 0.7, 38, CFrame.new(0, 0.35, 0), RGB(232, 214, 178), Mat.Plastic)
	cylinder(g, "PlazaInner", 0.8, 30, CFrame.new(0, 0.4, 0), RGB(214, 190, 148), Mat.Plastic)
	-- gold tiles set round the middle ring, and pointing out the four ways
	for i = 0, 31 do
		local a = (i + 0.5) / 32 * math.pi * 2
		part(g, "PlazaInlay", V3(1.2, 0.1, 1.2), CFrame.new(math.cos(a) * 16.9, 0.72, math.sin(a) * 16.9) * CFrame.Angles(0, -a, 0), RGB(214, 170, 70), Mat.Metal, { CanCollide = false })
	end
	for i = 0, 3 do
		local a = i * math.pi / 2
		for k = 0, 2 do
			local r = 20.2 + k * 1.2
			part(g, "PlazaPointer", V3(1.2 - k * 0.3, 0.1, 1.2 - k * 0.3), CFrame.new(math.cos(a + math.pi / 4) * r, 0.62, math.sin(a + math.pi / 4) * r) * CFrame.Angles(0, math.rad(45), 0), RGB(214, 170, 70), Mat.Metal, { CanCollide = false })
		end
	end

	-- Training yard slab, under all the pads
	local first, last = Config.zonePosition(1), Config.zonePosition(#Config.Zones)
	local halfW = Y.PerRow * Y.Spacing / 2
	part(g, "YardSlab", V3(halfW * 2, 0.6, last.Z - first.Z + Y.PadSize + 6), CFrame.new(Y.CenterX or 0, 0.3, (first.Z + last.Z) / 2), RGB(86, 96, 122), Mat.Plastic, {
		TopSurface = Enum.SurfaceType.Studs,
	})

	-- Boundary walls (the north wall has a gap for the bridge to the Spire)
	wall(g, "WallNorthW", V3(-120, 0, -118), V3(-16, 0, -118))
	wall(g, "WallNorthE", V3(16, 0, -118), V3(120, 0, -118))
	-- (the south wall has a gap too: the new south gatehouse and drawbridge)
	wall(g, "WallSouthW", V3(-120, 0, SOUTH_WALL), V3(-SOUTH_GATE_HALF, 0, SOUTH_WALL))
	wall(g, "WallSouthE", V3(SOUTH_GATE_HALF, 0, SOUTH_WALL), V3(120, 0, SOUTH_WALL))
	wall(g, "WallWest", V3(-118, 0, -120), V3(-118, 0, SOUTH_WALL + 2))
	wall(g, "WallEast", V3(118, 0, -120), V3(118, 0, SOUTH_WALL + 2))

	-- Each wall's crenellation spacing is worked out along its own length, so
	-- the merlon pattern doesn't necessarily land exactly where two walls
	-- meet - leaving a gap of open sky right at the corner. Drop an explicit
	-- merlon at each of the four corners to close that up.
	for i, c in ipairs({ { -119, -119 }, { 119, -119 }, { -119, SOUTH_WALL + 1 }, { 119, SOUTH_WALL + 1 } }) do
		part(g, "WallCornerMerlon" .. i, V3(7, 6, 7), CFrame.new(c[1], WALL_HEIGHT + 3, c[2]), RGB(110, 112, 118), Mat.Cobblestone)
	end

	local decor = folder(parent, "Decor")
	for _, t in ipairs(TREES) do
		tree(decor, t[1], t[2], t[3])
	end
	for _, l in ipairs(LAMPS) do
		lamp(decor, l[1], l[2])
	end

	-- Spawn
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = V3(12, 0.3, 12)
	spawn.CFrame = CFrame.new(0, 0.55, 34)
	spawn.Color = RGB(60, 220, 255)
	spawn.Material = Mat.Neon
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = g
end

----------------------------------------------------------------------
-- Decorations: castle dressing + nature
----------------------------------------------------------------------
-- Everything below is placed at fixed spots that were checked against the
-- paths, shops, training yard and gate, so nothing blocks where players walk.
-- A tiny seeded random is only used for small variations (rock tilt, flower
-- colours), so the lobby looks the same every time the server starts.
local seed = 1337
local function rnd()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

local STONE = RGB(138, 140, 146)
local STONE_DARK = RGB(108, 110, 116)
local WOOD = RGB(150, 105, 65)
local GOLD = RGB(235, 190, 70)
local BANNER_RED = RGB(170, 45, 50)
local BANNER_BLUE = RGB(45, 75, 165)
local ROOF_RED = RGB(196, 58, 52)

-- A pointed cone roof, built from stacked discs that shrink to a point
-- (Roblox has no cone shape). Alternate rings are a shade darker, like rows
-- of roof tiles, and a gold finial sits on the tip. `base` is the centre of
-- the bottom of the cone.
local function coneRoof(parent, base, radius, height, color, steps)
	steps = steps or 12
	local h = height / steps
	local dark = color:Lerp(RGB(0, 0, 0), 0.18)
	for i = 0, steps - 1 do
		local d = radius * 2 * (1 - i / steps)
		cylinder(parent, "Roof" .. i, h + 0.05, math.max(d, 0.6), CFrame.new(base + V3(0, h * (i + 0.5), 0)), (i % 2 == 0) and color or dark, Mat.SmoothPlastic)
	end
	ball(parent, "RoofTip", math.max(1.2, radius * 0.14), CFrame.new(base + V3(0, height + 0.3, 0)), GOLD, Mat.Metal)
end

-- Round tower on a wall corner: stone body with a band, crenellated top,
-- a pointed roof made of stacked shrinking discs, arrow slits facing the
-- lobby, and a flag on top.
local function cornerTower(parent, x, z, roofColor)
	local m = Instance.new("Model")
	m.Name = "CornerTower"
	m.Parent = parent
	local H = WALL_HEIGHT + 14
	cylinder(m, "Body", H, 20, CFrame.new(x, H / 2, z), STONE, Mat.Cobblestone)
	cylinder(m, "BandLow", 1.4, 21.4, CFrame.new(x, H * 0.3, z), STONE_DARK, Mat.Cobblestone)
	cylinder(m, "BandHigh", 1.4, 21.4, CFrame.new(x, H * 0.7, z), STONE_DARK, Mat.Cobblestone)
	cylinder(m, "Ledge", 2, 23, CFrame.new(x, H + 1, z), STONE_DARK, Mat.Cobblestone)
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		part(m, "Merlon" .. i, V3(3.2, 4, 3.2), CFrame.new(x + math.cos(a) * 10, H + 4, z + math.sin(a) * 10) * CFrame.Angles(0, -a, 0), STONE_DARK, Mat.Cobblestone)
	end
	-- a tall pointed cone roof (red, like a storybook castle), overhanging a little
	coneRoof(m, V3(x, H + 2.5, z), 12.5, 30, roofColor)
	cylinder(m, "FlagPole", 8, 0.5, CFrame.new(x, H + 36, z), RGB(70, 60, 50), Mat.Wood)
	part(m, "Flag", V3(0.3, 3, 5), CFrame.new(x, H + 38.5, z + 2.6), roofColor, Mat.Fabric)
	-- arrow slits on the side facing the middle of the lobby
	local inward = V3(-x, 0, -z).Unit
	for _, y in ipairs({ H * 0.45, H * 0.85 }) do
		local p = V3(x, y, z) + inward * 10
		part(m, "Slit", V3(1.4, 5, 0.6), CFrame.lookAt(p, p + inward), RGB(28, 28, 36), Mat.SmoothPlastic)
	end
end

-- A hanging cloth banner on the inner face of a wall. `facing` points into
-- the lobby.
local function banner(parent, pos, facing, color)
	local m = Instance.new("Model")
	m.Name = "Banner"
	m.Parent = parent
	local cf = CFrame.lookAt(pos, pos + facing)
	part(m, "Rod", V3(8, 0.6, 0.6), cf * CFrame.new(0, 8.3, -0.3), RGB(90, 70, 40), Mat.Wood)
	part(m, "Cloth", V3(6, 16, 0.3), cf * CFrame.new(0, 0, -0.2), color, Mat.Fabric)
	part(m, "Trim", V3(6, 1, 0.35), cf * CFrame.new(0, -7.6, -0.25), GOLD, Mat.Fabric)
	part(m, "Emblem", V3(2.6, 2.6, 0.4), cf * CFrame.new(0, 2, -0.4) * CFrame.Angles(0, 0, math.rad(45)), GOLD, Mat.SmoothPlastic)
	part(m, "EmblemCore", V3(1.2, 1.2, 0.45), cf * CFrame.new(0, 2, -0.45) * CFrame.Angles(0, 0, math.rad(45)), color, Mat.SmoothPlastic)
end

-- A torch in an iron bracket on a wall, with real fire (Roblox's Fire
-- flickers on its own) and a warm light.
local function wallTorch(parent, pos, facing)
	local m = Instance.new("Model")
	m.Name = "WallTorch"
	m.Parent = parent
	local cf = CFrame.lookAt(pos, pos + facing)
	part(m, "Plate", V3(1.8, 2.4, 0.4), cf * CFrame.new(0, 0, -0.2), RGB(50, 48, 56), Mat.Metal)
	part(m, "Bracket", V3(0.8, 0.8, 2.2), cf * CFrame.new(0, 0, -1.3), RGB(50, 48, 56), Mat.Metal)
	part(m, "Stick", V3(0.7, 3, 0.7), cf * CFrame.new(0, 1.3, -2.4), RGB(100, 70, 40), Mat.Wood)
	local head = part(m, "Head", V3(1.2, 1, 1.2), cf * CFrame.new(0, 3.2, -2.4), RGB(60, 40, 30), Mat.Wood)
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 6
	fire.Color = RGB(255, 140, 40)
	fire.SecondaryColor = RGB(255, 220, 90)
	fire.Parent = head
	local light = Instance.new("PointLight")
	light.Range = 16
	light.Brightness = 1.1
	light.Color = RGB(255, 170, 90)
	light.Parent = head
end

-- Stone post with a gold cap, for chains to hang between
local function chainPost(parent, x, z)
	part(parent, "ChainPost", V3(1.8, 5, 1.8), CFrame.new(x, 2.5, z), STONE_DARK, Mat.Cobblestone)
	ball(parent, "ChainPostCap", 2, CFrame.new(x, 5.4, z), GOLD, Mat.SmoothPlastic)
end

-- A sagging iron chain between two points, built link by link (each link
-- turned 90 degrees from the last, like a real chain).
local function chain(parent, a, b, sag)
	local d = b - a
	local n = math.max(2, math.floor(d.Magnitude / 1.05))
	local dir = V3(d.X, 0, d.Z).Unit
	for i = 0, n do
		local t = i / n
		local p = a + d * t - V3(0, sag * 4 * t * (1 - t), 0)
		local cf = CFrame.lookAt(p, p + dir) * CFrame.Angles(0, 0, (i % 2 == 0) and 0 or math.pi / 2)
		part(parent, "ChainLink", V3(0.3, 0.7, 1.3), cf, RGB(58, 58, 68), Mat.Metal, {
			CanCollide = false,
			CanQuery = false,
		})
	end
end

-- Wooden fence along a straight line (x or z axis): posts every ~6 studs
-- with two rails between them.
local function fence(parent, a, b)
	local d = b - a
	local len = d.Magnitude
	local sections = math.max(1, math.floor(len / 6 + 0.5))
	local alongX = math.abs(d.X) > math.abs(d.Z)
	for i = 0, sections do
		local p = a + d * (i / sections)
		part(parent, "FencePost", V3(0.9, 4, 0.9), CFrame.new(p.X, 2, p.Z), WOOD, Mat.WoodPlanks)
		ball(parent, "FencePostTop", 1.1, CFrame.new(p.X, 4.1, p.Z), WOOD, Mat.WoodPlanks)
	end
	local mid = a + d / 2
	local railSize = alongX and V3(len, 0.45, 0.35) or V3(0.35, 0.45, len)
	for _, y in ipairs({ 1.4, 3 }) do
		part(parent, "FenceRail", railSize, CFrame.new(mid.X, y, mid.Z), RGB(170, 122, 78), Mat.WoodPlanks)
	end
end

-- A small cluster of tilted grey boulders, sometimes with moss on top
local function rocks(parent, x, z, s)
	local m = Instance.new("Model")
	m.Name = "Rocks"
	m.Parent = parent
	local grey = { RGB(118, 122, 130), RGB(132, 136, 144), RGB(104, 108, 116) }
	local count = 2 + math.floor(rnd() * 2)
	for i = 1, count do
		local size = V3(4 + rnd() * 2, 2.6 + rnd() * 1.6, 3.4 + rnd() * 2) * (s * (i == 1 and 1 or 0.6))
		local ox, oz = (i == 1) and 0 or (rnd() - 0.5) * 5 * s, (i == 1) and 0 or (rnd() - 0.5) * 5 * s
		local cf = CFrame.new(x + ox, size.Y * 0.35, z + oz) * CFrame.Angles(math.rad((rnd() - 0.5) * 20), rnd() * math.pi, math.rad((rnd() - 0.5) * 20))
		part(m, "Rock", size, cf, grey[1 + (i - 1) % 3], Mat.Slate)
		if i == 1 and rnd() < 0.6 then
			part(m, "Moss", V3(size.X * 0.8, 0.5, size.Z * 0.8), cf * CFrame.new(0, size.Y / 2, 0), RGB(96, 150, 74), Mat.LeafyGrass, { CanCollide = false })
		end
	end
end

-- A round bush made of 2-3 overlapping green balls
local function bush(parent, x, z, s)
	voxelBush(parent, x, z, s)
end

-- A patch of little flowers: coloured blooms nestled in a couple of leafy
-- clumps. (No separate stems - from player height they're barely visible and
-- they doubled the part count.)
local FLOWER_COLORS = { RGB(255, 110, 140), RGB(255, 220, 90), RGB(170, 120, 255), RGB(255, 255, 255), RGB(255, 150, 70) }
local function flowers(parent, x, z, r)
	local m = Instance.new("Model")
	m.Name = "Flowers"
	m.Parent = parent
	r = r or 3
	for _ = 1, 2 do
		local a, d = rnd() * math.pi * 2, rnd() * r * 0.5
		part(m, "Leaf", V3(2, 0.8, 1.6), CFrame.new(x + math.cos(a) * d, 0.4, z + math.sin(a) * d) * CFrame.Angles(0, a, 0), VT_LEAF2, Mat.Grass, { CanCollide = false })
	end
	for _ = 1, 6 do
		local a, d = rnd() * math.pi * 2, rnd() * r
		part(m, "Bloom", V3(0.7, 0.7, 0.7), CFrame.new(x + math.cos(a) * d, 0.95, z + math.sin(a) * d), FLOWER_COLORS[1 + math.floor(rnd() * #FLOWER_COLORS)], Mat.SmoothPlastic, { CanCollide = false })
	end
end

-- Extra tree styles so the lobby isn't all the same tree
local function pineTree(parent, x, z, s)
	voxelTree(parent, x, z, s * 0.85)
end

local function roundTree(parent, x, z, s)
	voxelTree(parent, x, z, s * 0.9)
end

local function blossomTree(parent, x, z, s)
	voxelTree(parent, x, z, s * 0.85)
end

local NEW_TREES = {
	{ pineTree, 60, -88, 1 }, { roundTree, 76, -104, 0.9 }, { blossomTree, 96, -76, 0.9 },
	{ pineTree, -60, 24, 1 }, { roundTree, -86, 30, 0.9 }, { blossomTree, -30, -40, 0.9 },
	{ blossomTree, 28, -40, 0.9 }, { pineTree, 90, 22, 0.9 }, { roundTree, 92, 60, 0.9 },
	{ pineTree, 96, 150, 0.9 }, { blossomTree, 62, 160, 0.9 }, { pineTree, -30, 164, 0.8 },
	{ roundTree, -100, 152, 0.9 },
}

local ROCKS = {
	{ -108, -40, 1 }, { 96, -10, 0.9 }, { 26, -100, 0.9 }, { -64, 40, 0.8 },
	{ 90, 150, 0.9 }, { -104, 160, 0.9 }, { 20, 160, 0.8 },
}

local BUSHES = {
	{ -30, 16, 0.8 }, { 30, 16, 0.8 }, { -20, -30, 0.7 }, { 20, -30, 0.7 },
	{ 34, -58, 0.9 }, { -108, 0, 1 }, { 96, 36, 0.9 }, { 24, 66, 0.8 },
	{ -24, 44, 0.8 }, { 76, 160, 0.9 }, { -60, 160, 0.9 },
}

local FLOWER_PATCHES = {
	{ -40, 18 }, { 40, 24 }, { -28, -14 }, { 28, -14 }, { -95, 12 },
	{ 12, 150 }, { 60, 150 }, { 80, 150 }, { 50, 160 }, { -80, 40 },
}

local function buildDecor(parent)
	local d = folder(parent, "CastleAndNature")

	-- Castle: towers on the four corners (red/blue roofs alternating)
	cornerTower(d, -112, -112, ROOF_RED)
	cornerTower(d, 112, -112, ROOF_RED)
	cornerTower(d, -112, SOUTH_WALL - 6, ROOF_RED)
	cornerTower(d, 112, SOUTH_WALL - 6, ROOF_RED)

	-- Banners and torches on the inside of each wall. Inner faces sit 3
	-- studs in from each wall's centre line.
	local N, S, W, E = -114.6, SOUTH_WALL - 3.4, -114.6, 114.6
	for i, x in ipairs({ -100, -80, 80, 100 }) do
		banner(d, V3(x, 32, N), V3(0, 0, 1), i % 2 == 0 and BANNER_BLUE or BANNER_RED)
	end
	for i, x in ipairs({ -90, -50, 50, 90 }) do
		banner(d, V3(x, 32, S), V3(0, 0, -1), i % 2 == 0 and BANNER_RED or BANNER_BLUE)
	end
	for _, x in ipairs({ -72, -56, 56, 72 }) do -- clear of the gate towers
		wallTorch(d, V3(x, 16, N), V3(0, 0, 1))
	end
	for _, x in ipairs({ -68, -40, 40, 68 }) do
		wallTorch(d, V3(x, 16, S), V3(0, 0, -1))
	end
	for _, z in ipairs({ -65, -5, 35, 85, 125, 155 }) do
		wallTorch(d, V3(W, 16, z), V3(1, 0, 0))
		wallTorch(d, V3(E, 16, z), V3(-1, 0, 0))
	end

	for _, t in ipairs(NEW_TREES) do
		t[1](d, t[2], t[3], t[4])
	end
	for _, r in ipairs(ROCKS) do
		rocks(d, r[1], r[2], r[3])
	end
	for _, b in ipairs(BUSHES) do
		bush(d, b[1], b[2], b[3])
	end
	for _, f in ipairs(FLOWER_PATCHES) do
		flowers(d, f[1], f[2], 3)
	end
end

----------------------------------------------------------------------
-- Sell Shop (west side, faces east)
----------------------------------------------------------------------
local function buildSellShop(parent)
	-- The Sell Shop: a market stall. Timber posts, a striped awning with a
	-- scalloped edge, lanterns hanging at the front, a panelled back wall with
	-- shelves of loot crates (each with its gem glowing on top) and potion
	-- bottles, sacks of goods, barrels brimming with ore, an open treasure
	-- chest spilling gold, and brass scales on the counter. The counter is
	-- kept low and the shopkeeper stands on a step behind it, so you see him.
	-- Faces the plaza (local +Z).
	local m = folder(parent, "SellShop")
	local O = CFrame.new(Config.Stations.Sell) * CFrame.Angles(0, math.rad(Config.StationTurn.Sell or 90), 0)
	local wood = RGB(150, 106, 68)
	local timber = RGB(120, 80, 50)
	local woodDark = RGB(96, 64, 42)
	local red, white = RGB(226, 62, 68), RGB(252, 246, 236)
	local coinGold = RGB(255, 205, 60)
	local deco = { CanCollide = false } -- (little things you don't bump into)

	-- Floor, with a darker trim round its edge
	part(m, "FloorTrim", V3(27, 0.5, 21), O * CFrame.new(0, 0.25, 0), woodDark, Mat.Wood)
	part(m, "Floor", V3(26, 0.8, 20), O * CFrame.new(0, 0.4, 0), wood, Mat.WoodPlanks)

	-- Back wall: plaster above, wooden panelling below
	part(m, "BackWall", V3(24, 17, 1.5), O * CFrame.new(0, 9.3, -8), RGB(240, 228, 200))
	part(m, "Wainscot", V3(23.6, 5, 0.4), O * CFrame.new(0, 3.3, -7.1), RGB(168, 120, 76), Mat.WoodPlanks, deco)
	part(m, "WainscotRail", V3(23.6, 0.5, 0.6), O * CFrame.new(0, 5.9, -7), timber, Mat.Wood, deco)
	for _, sx in ipairs({ -11.5, 11.5 }) do
		part(m, "PostBack", V3(1.6, 15, 1.6), O * CFrame.new(sx, 8.3, -8), timber, Mat.Wood)
		part(m, "PostFront", V3(1.6, 15, 1.6), O * CFrame.new(sx, 8.3, 8), timber, Mat.Wood)
		part(m, "PostFoot", V3(2.2, 1, 2.2), O * CFrame.new(sx, 1.3, 8), woodDark, Mat.Wood, deco)
		part(m, "PostCap", V3(2.2, 0.6, 2.2), O * CFrame.new(sx, 15.9, 8), coinGold, Mat.Metal, deco)
	end

	-- Striped awning, and a scalloped edge hanging along its front
	for i = 1, 10 do
		local x = -10.8 + (i - 1) * 2.4
		local c = (i % 2 == 1) and red or white
		part(m, "Awning" .. i, V3(2.4, 0.7, 18), O * CFrame.new(x, 15.4, 0.5) * CFrame.Angles(math.rad(12), 0, 0), c)
		-- (the awning's front edge sits at y 13.5, z 9.3)
		part(m, "Scallop", V3(2.4, 1, 0.3), O * CFrame.new(x, 12.75, 9.35), c, Mat.SmoothPlastic, deco)
		part(m, "ScallopTip", V3(1.4, 0.5, 0.3), O * CFrame.new(x, 12, 9.35), c, Mat.SmoothPlastic, deco)
	end

	-- Lanterns hanging from the front posts
	for _, sx in ipairs({ -11.5, 11.5 }) do
		local dir = sx > 0 and 1 or -1
		part(m, "LanternArm", V3(2, 0.3, 0.3), O * CFrame.new(sx + dir * 1.2, 11.6, 8.9), woodDark, Mat.Wood, deco)
		part(m, "LanternCap", V3(1.4, 0.35, 1.4), O * CFrame.new(sx + dir * 2, 10.9, 8.9), RGB(50, 50, 62), Mat.Metal, deco)
		local lantern = part(m, "Lantern", V3(1, 1.3, 1), O * CFrame.new(sx + dir * 2, 10.05, 8.9), RGB(255, 208, 130), Mat.Neon, deco)
		part(m, "LanternBase", V3(1.3, 0.3, 1.3), O * CFrame.new(sx + dir * 2, 9.3, 8.9), RGB(50, 50, 62), Mat.Metal, deco)
		local light = Instance.new("PointLight")
		light.Color = RGB(255, 200, 130)
		light.Range = 12
		light.Brightness = 0.8
		light.Parent = lantern
	end

	-- Counter: low enough to see the shopkeeper over it, with planked panels
	part(m, "CounterFront", V3(20, 3.2, 3), O * CFrame.new(0, 2.4, 5.5), RGB(168, 120, 76), Mat.WoodPlanks)
	local top = part(m, "Counter", V3(21.5, 0.7, 4.4), O * CFrame.new(0, 4.35, 5.5), RGB(204, 150, 98), Mat.WoodPlanks)
	for _, px in ipairs({ -10, -3.4, 3.4, 10 }) do
		part(m, "CounterPlank", V3(0.6, 3.2, 0.3), O * CFrame.new(px, 2.4, 7.05), woodDark, Mat.Wood, deco)
	end
	part(m, "CounterTrim", V3(21.5, 0.25, 0.25), O * CFrame.new(0, 4.05, 7.75), coinGold, Mat.Metal, deco)
	-- the step the shopkeeper stands on
	part(m, "KeeperStep", V3(10, 0.6, 5), O * CFrame.new(0, 1.1, 0.5), woodDark, Mat.Wood)

	-- Coin stacks on the counter
	local COUNTER_TOP = 4.7
	local stacks = { { -7, 4 }, { -4.6, 3 }, { 7.4, 5 } }
	for i, st in ipairs(stacks) do
		for k = 1, st[2] do
			cylinder(m, "Coin" .. i .. "_" .. k, 0.4, 2.4, O * CFrame.new(st[1], COUNTER_TOP + 0.2 + (k - 1) * 0.42, 5.4), coinGold, Mat.Metal, deco)
		end
	end
	-- Brass scales, weighing a gem against a coin
	local brass = RGB(214, 170, 70)
	local SX = 3.2
	cylinder(m, "ScaleBase", 0.3, 1.8, O * CFrame.new(SX, COUNTER_TOP + 0.15, 5.2), brass, Mat.Metal, deco)
	part(m, "ScalePost", V3(0.3, 2.6, 0.3), O * CFrame.new(SX, COUNTER_TOP + 1.6, 5.2), brass, Mat.Metal, deco)
	part(m, "ScaleBeam", V3(3.6, 0.25, 0.25), O * CFrame.new(SX, COUNTER_TOP + 2.9, 5.2) * CFrame.Angles(0, 0, math.rad(6)), brass, Mat.Metal, deco)
	for _, side in ipairs({ -1, 1 }) do
		local py = COUNTER_TOP + 1.5 + side * 0.18
		part(m, "ScaleString", V3(0.08, 1.3, 0.08), O * CFrame.new(SX + side * 1.7, py + 0.75, 5.2), brass, Mat.Metal, deco)
		cylinder(m, "ScalePan", 0.15, 1.4, O * CFrame.new(SX + side * 1.7, py, 5.2), brass, Mat.Metal, deco)
	end
	part(m, "ScaleGem", V3(0.6, 0.6, 0.6), O * CFrame.new(SX - 1.7, COUNTER_TOP + 1.7, 5.2) * CFrame.Angles(math.rad(45), 0, math.rad(45)), RGB(44, 232, 245), Mat.Neon, deco)
	cylinder(m, "ScaleCoin", 0.2, 0.9, O * CFrame.new(SX + 1.7, COUNTER_TOP + 1.8, 5.2), coinGold, Mat.Metal, deco)

	-- Shelf of loot crates: wooden crates banded in each loot's colour, the
	-- loot's gem glowing on top
	part(m, "Shelf", V3(18, 1, 2.5), O * CFrame.new(0, 7.5, -6.4), wood, Mat.WoodPlanks)
	for i, mat in ipairs(Config.Materials) do
		local x = -6 + (i - 1) * 4
		part(m, "Crate" .. i, V3(3, 2.6, 2.2), O * CFrame.new(x, 9.3, -6.4), RGB(168, 120, 76), Mat.WoodPlanks)
		part(m, "CrateBand", V3(3.1, 0.5, 2.3), O * CFrame.new(x, 9.3, -6.4), mat.color, Mat.SmoothPlastic, deco)
		part(m, "CrateGem", V3(0.9, 0.9, 0.9), O * CFrame.new(x, 11.2, -6.4) * CFrame.Angles(math.rad(45), math.rad(20), math.rad(45)), mat.color, Mat.Neon, deco)
	end
	-- a higher shelf of potion bottles
	part(m, "PotionShelf", V3(16, 0.5, 1.8), O * CFrame.new(0, 13, -6.9), wood, Mat.WoodPlanks, deco)
	local POTIONS = { RGB(228, 59, 68), RGB(44, 232, 245), RGB(99, 199, 77), RGB(181, 80, 136), RGB(254, 174, 52), RGB(0, 153, 219) }
	for i, c in ipairs(POTIONS) do
		local x = -6.25 + (i - 1) * 2.5
		local h = (i % 2 == 0) and 1.6 or 1.2
		cylinder(m, "Potion", h, 0.9, O * CFrame.new(x, 13.25 + h / 2, -6.9), c, Mat.Neon, { CanCollide = false, Transparency = 0.15 })
		cylinder(m, "PotionNeck", 0.5, 0.4, O * CFrame.new(x, 13.25 + h + 0.25, -6.9), RGB(192, 203, 220), Mat.Glass, deco)
		cylinder(m, "PotionCork", 0.3, 0.45, O * CFrame.new(x, 13.25 + h + 0.6, -6.9), RGB(184, 111, 80), Mat.Wood, deco)
	end

	-- Sacks of goods behind the counter, tied at the top
	for i, sp in ipairs({ { -9, -3.5, 2.8 }, { -7.2, -5, 2.3 }, { 9.2, -4, 2.6 } }) do
		ball(m, "Sack", sp[3], O * CFrame.new(sp[1], 0.8 + sp[3] * 0.42, sp[2]), RGB(196, 170, 120), Mat.Fabric, deco)
		cylinder(m, "SackTie", 0.35, 0.8, O * CFrame.new(sp[1], 0.8 + sp[3] * 0.85, sp[2]), RGB(120, 80, 50), Mat.Fabric, deco)
		if i == 1 then
			ball(m, "SackCoins", 1.4, O * CFrame.new(sp[1], 0.8 + sp[3] * 0.95, sp[2]), coinGold, Mat.Metal, deco)
		end
	end

	-- Barrels brimming with ore at the front corners
	for bi, bx in ipairs({ -12.6, 12.6 }) do
		local B = O * CFrame.new(bx, 0.8, 10.6)
		cylinder(m, "Barrel", 3, 2.6, B * CFrame.new(0, 1.5, 0), RGB(150, 100, 60), Mat.WoodPlanks)
		for _, by in ipairs({ 0.5, 2.5 }) do
			cylinder(m, "BarrelBand", 0.3, 2.75, B * CFrame.new(0, by, 0), RGB(58, 58, 66), Mat.Metal, deco)
		end
		for k = 1, 5 do
			local mat = Config.Materials[((k + bi) % #Config.Materials) + 1]
			local a = k / 5 * math.pi * 2
			part(m, "Ore", V3(0.8, 0.8, 0.8), B * CFrame.new(math.cos(a) * 0.6, 3.1 + (k % 2) * 0.3, math.sin(a) * 0.6) * CFrame.Angles(a, a * 2, 0), mat.color, Mat.Neon, deco)
		end
	end

	-- An open treasure chest spilling coins, out front on the left
	local C = O * CFrame.new(-8.4, 0.8, 11) * CFrame.Angles(0, math.rad(20), 0)
	part(m, "Chest", V3(3.2, 1.8, 2.2), C * CFrame.new(0, 0.9, 0), RGB(140, 90, 52), Mat.WoodPlanks, deco)
	for _, bx in ipairs({ -1.1, 1.1 }) do
		part(m, "ChestBand", V3(0.3, 1.9, 2.3), C * CFrame.new(bx, 0.9, 0), coinGold, Mat.Metal, deco)
	end
	part(m, "ChestLid", V3(3.2, 0.4, 2.2), C * CFrame.new(0, 2.6, -1.4) * CFrame.Angles(math.rad(-70), 0, 0), RGB(140, 90, 52), Mat.WoodPlanks, deco)
	local hoard = part(m, "ChestGold", V3(2.8, 0.8, 1.9), C * CFrame.new(0, 1.75, 0), coinGold, Mat.Neon, deco)
	part(m, "ChestGoldTop", V3(1.8, 0.5, 1.2), C * CFrame.new(-0.2, 2.35, 0.1), coinGold, Mat.Neon, deco)
	local glow = Instance.new("PointLight")
	glow.Color = coinGold
	glow.Range = 9
	glow.Brightness = 1
	glow.Parent = hoard
	for k = 1, 4 do
		local a = k * 1.7
		cylinder(m, "SpiltCoin", 0.2, 0.9, C * CFrame.new(math.cos(a) * 2.4, 0.1, 1.3 + math.sin(a) * 0.8) * CFrame.Angles(0, 0, math.rad(8 * k)), coinGold, Mat.Metal, deco)
	end

	avatarNPC(m, NPC_MODELS.Shopkeeper, "Shopkeeper", facingCustomer(O, 0, 0.5), 1.4, function()
		npc(m, O * CFrame.new(0, 0.6, 0), 0, 0.5, RGB(206, 60, 60), RGB(250, 240, 220))
	end)

	-- Sign + spinning coin
	titleSign(m, O * CFrame.new(0, 21.5, 2), "SELL SHOP", "Turn loot into coins", RGB(255, 214, 80), 340, 80)
	-- a pixel-art coin floating above it: gold cubes with a darker rim, a
	-- shine and a notched middle, bobbing (in step with the Upgrade arrow)
	local COIN = {
		"...OOOO...",
		".OOYYYYOO.",
		".OYWYYYyO.",
		"OYWYYYYYyO",
		"OYYYddYYyO",
		"OYYYddYYyO",
		"OYYYYYYYyO",
		".OYYYYYyO.",
		".OOyyyyOO.",
		"...OOOO...",
	}
	local INK = { O = RGB(184, 111, 80), Y = RGB(254, 231, 97), y = RGB(254, 174, 52), W = RGB(255, 255, 255), d = RGB(214, 150, 40) }
	local cube = 0.8
	for y, row in ipairs(COIN) do
		for x = 1, #row do
			local c = INK[string.sub(row, x, x)]
			if c then
				local px = part(m, "CoinPixel", V3(cube, cube, cube), O * CFrame.new((x - 5.5) * cube, 28.5 + (5.5 - y) * cube, 2), c, Mat.Neon, { CanCollide = false, CanQuery = false })
				fx(px, { BobAmp = 0.7, BobSpeed = 1.8 })
			end
		end
	end

	-- Glowing welcome mat
	part(m, "Mat", V3(12, 0.3, 6), O * CFrame.new(0, 0.45, 14), RGB(80, 230, 130), Mat.Neon, { Transparency = 0.35, CanCollide = false })

	addPrompt(top, "Sell", "Sell Loot", "Sell Shop", 14)
	autoZone(m, O * CFrame.new(0, 4, 12), V3(22, 8, 12), "Panel", "Sell")
end

----------------------------------------------------------------------
-- Upgrade Shop (east side, faces west)
----------------------------------------------------------------------
local function buildUpgradeShop(parent)
	-- The Upgrade Shop: a mushroom house. Round stone-and-brick stem with
	-- timber beams, a big stepped red cap with white spots and a floppy tip,
	-- glowing windows, an arched door, a little mushroom annex on the side,
	-- plants and lanterns. The shopkeeper stands at a counter out front.
	-- Faces the plaza (local +Z = towards the middle of the lobby).
	local m = folder(parent, "UpgradeShop")
	local O = CFrame.new(Config.Stations.Upgrades) * CFrame.Angles(0, math.rad(Config.StationTurn.Upgrades or -90), 0)
	local STEM_Z, STEM_R = -3, 9 -- stem centre (local z) and radius
	local capRed, capRedDark = RGB(204, 50, 44), RGB(184, 40, 36)
	local white = RGB(250, 246, 236)
	local timber = RGB(96, 64, 42)

	local function world(x, y, z)
		return (O * CFrame.new(x, y, z)).Position
	end
	-- a CFrame on the stem's surface at `deg` degrees round from the front,
	-- facing outwards
	local function onStem(deg, y, out)
		local a = math.rad(deg)
		local dir = V3(math.sin(a), 0, math.cos(a))
		local pos = V3(0, y, STEM_Z) + dir * (STEM_R + (out or 0))
		return O * CFrame.lookAt(pos, pos + dir)
	end

	-- Round cobblestone base
	cylinder(m, "Base", 0.8, 27, O * CFrame.new(0, 0.4, -1), RGB(150, 146, 140), Mat.Cobblestone)

	-- Stem: darker stone bottom band, brick walls, timber beams
	cylinder(m, "StemBase", 3, STEM_R * 2 + 0.6, O * CFrame.new(0, 2.3, STEM_Z), RGB(112, 108, 104), Mat.Cobblestone)
	cylinder(m, "Stem", 15, STEM_R * 2, O * CFrame.new(0, 8.3, STEM_Z), RGB(176, 150, 124), Mat.Brick)
	cylinder(m, "StemBand", 0.8, STEM_R * 2 + 0.5, O * CFrame.new(0, 11, STEM_Z), timber, Mat.Wood)
	for i = 0, 7 do
		local deg = 22.5 + i * 45
		part(m, "StemBeam", V3(0.9, 14, 0.5), onStem(deg, 8.3, 0.1), timber, Mat.Wood)
	end

	-- Arched door, a little to the left of the counter
	local doorCf = onStem(-38, 0, 0.15)
	discZ(m, "DoorArch", 0.4, 6.4, doorCf * CFrame.new(0, 5.4, 0), RGB(112, 108, 104), Mat.Cobblestone)
	discZ(m, "DoorTop", 0.5, 5, doorCf * CFrame.new(0, 5.4, -0.1), RGB(120, 76, 44), Mat.WoodPlanks)
	part(m, "Door", V3(5, 4.6, 0.5), doorCf * CFrame.new(0, 3.1, -0.1), RGB(120, 76, 44), Mat.WoodPlanks)
	ball(m, "DoorKnob", 0.5, doorCf * CFrame.new(1.6, 3.3, -0.45), GOLD, Mat.Metal)

	-- Glowing windows
	local function window(deg, y, w, h)
		local cf = onStem(deg, y, 0.2)
		part(m, "WindowFrame", V3(w + 0.8, h + 0.8, 0.4), cf, timber, Mat.Wood)
		local glass = part(m, "WindowGlow", V3(w, h, 0.45), cf * CFrame.new(0, 0, -0.05), RGB(255, 206, 120), Mat.Neon, { Transparency = 0.15 })
		part(m, "WindowBarV", V3(0.25, h, 0.5), cf * CFrame.new(0, 0, -0.1), timber, Mat.Wood)
		part(m, "WindowBarH", V3(w, 0.25, 0.5), cf * CFrame.new(0, 0, -0.1), timber, Mat.Wood)
		local light = Instance.new("PointLight")
		light.Color = RGB(255, 200, 120)
		light.Range = 9
		light.Brightness = 0.7
		light.Parent = glass
	end
	window(38, 6.5, 2.6, 3.2)
	window(0, 12.8, 2.4, 2.2)
	window(95, 7, 2.4, 3)
	window(-100, 7, 2.4, 3)

	-- Mushroom cap: cream underside, then stepped red tiers
	cylinder(m, "CapUnderside", 0.6, 33, O * CFrame.new(0, 15.3, STEM_Z), RGB(236, 220, 192), Mat.SmoothPlastic)
	local tiers = { { 34, 2, 16.6 }, { 31, 2.4, 18.8 }, { 27, 2.4, 21 }, { 22, 2.4, 23.2 }, { 16, 2.4, 25.3 }, { 10, 2.2, 27.2 } }
	for i, t in ipairs(tiers) do
		cylinder(m, "Cap" .. i, t[2], t[1], O * CFrame.new(0, t[3], STEM_Z), (i % 2 == 1) and capRed or capRedDark, Mat.SmoothPlastic)
	end
	-- floppy tip leaning over to one side
	ball(m, "CapTip1", 5.5, O * CFrame.new(1.6, 29, STEM_Z + 0.8), capRed, Mat.SmoothPlastic)
	ball(m, "CapTip2", 3.6, O * CFrame.new(3.6, 30.6, STEM_Z + 1.6), capRedDark, Mat.SmoothPlastic)
	ball(m, "CapTip3", 2.2, O * CFrame.new(5.2, 31.2, STEM_Z + 2.2), capRed, Mat.SmoothPlastic)
	-- white spots sitting on the tiers
	local spots = { { 1, 20, 3.4 }, { 1, 110, 3 }, { 1, 200, 3.4 }, { 1, 290, 2.8 }, { 2, 65, 3 }, { 2, 160, 2.6 },
		{ 2, 250, 3.2 }, { 2, 340, 2.6 }, { 3, 20, 2.8 }, { 3, 120, 3 }, { 3, 230, 2.6 }, { 4, 80, 2.6 }, { 4, 300, 2.4 }, { 5, 190, 2.2 } }
	for _, sp in ipairs(spots) do
		local t = tiers[sp[1]]
		local a = math.rad(sp[2])
		local r = t[1] / 2 - sp[3] / 2 - 0.6
		cylinder(m, "Spot", 0.3, sp[3], O * CFrame.new(math.sin(a) * r, t[3] + t[2] / 2 + 0.1, STEM_Z + math.cos(a) * r), white, Mat.SmoothPlastic)
	end
	-- leaves hanging off the edge of the cap
	for _, deg in ipairs({ 25, 75, 150, 210, 285, 330 }) do
		local a = math.rad(deg)
		ball(m, "HangingLeaves", 2.6, O * CFrame.new(math.sin(a) * 16.4, 15.2, STEM_Z + math.cos(a) * 16.4), RGB(70, 150, 66), Mat.LeafyGrass, { CanCollide = false })
	end

	-- Little mushroom annex on the left side
	local AX, AZ = -19.5, -1
	cylinder(m, "AnnexBase", 0.6, 9, O * CFrame.new(AX, 0.3, AZ), RGB(150, 146, 140), Mat.Cobblestone)
	cylinder(m, "AnnexStem", 6, 7, O * CFrame.new(AX, 3.8, AZ), RGB(176, 150, 124), Mat.Brick)
	for i, t in ipairs({ { 11, 1.6, 7.4 }, { 8.4, 1.6, 8.8 }, { 5, 1.4, 10 } }) do
		cylinder(m, "AnnexCap" .. i, t[2], t[1], O * CFrame.new(AX, t[3], AZ), (i % 2 == 1) and capRed or capRedDark, Mat.SmoothPlastic)
	end
	cylinder(m, "AnnexSpot", 0.3, 1.8, O * CFrame.new(AX + 2.2, 8.3, AZ + 2), white, Mat.SmoothPlastic)
	cylinder(m, "AnnexSpot", 0.3, 1.4, O * CFrame.new(AX - 1.5, 9.6, AZ - 1), white, Mat.SmoothPlastic)
	local annexWin = part(m, "AnnexWindow", V3(1.8, 1.8, 0.4), O * CFrame.new(AX, 4.6, AZ + 3.55), RGB(255, 206, 120), Mat.Neon, { Transparency = 0.15 })

	-- The toad sits right in the middle, out front of the stem, facing the
	-- path. Players teleporting in land a few studs in front of him, on the
	-- welcome mat (Hud's station spot, local z = 13). The "Open Upgrades"
	-- prompt hangs on an invisible marker right by him.
	local top = anchorPart(m, "PromptSpot", O * CFrame.new(0, 3, 9.5))
	avatarNPC(m, NPC_MODELS.Toad, "Toad", facingCustomer(O, 0, 8.6), Config.Stations.Upgrades.Y + 0.8, function()
		npc(m, O, 0, 8.6, RGB(90, 160, 90), RGB(200, 50, 44))
	end)

	-- Crate and sack by the annex
	part(m, "Crate", V3(3, 3, 3), O * CFrame.new(-9, 2.3, 7), RGB(160, 112, 70), Mat.WoodPlanks)
	ball(m, "Sack", 2.8, O * CFrame.new(-11.2, 1.9, 8.6), RGB(196, 170, 120), Mat.Fabric)

	-- Plants round the base, flowers by the door, lanterns at the front
	for _, deg in ipairs({ 120, 165, 205, 250 }) do
		local a = math.rad(deg)
		local w = world(math.sin(a) * 10.5, 0, STEM_Z + math.cos(a) * 10.5)
		bush(m, w.X, w.Z, 0.7)
	end
	local fw = world(-7.5, 0, 8.5)
	flowers(m, fw.X, fw.Z, 1.8)
	for _, lx in ipairs({ -7.5, 7.5 }) do
		part(m, "LanternPost", V3(0.6, 5, 0.6), O * CFrame.new(lx, 2.5, 13.5), RGB(60, 60, 74), Mat.Metal)
		local lantern = part(m, "Lantern", V3(1.2, 1.4, 1.2), O * CFrame.new(lx, 5.6, 13.5), RGB(255, 208, 130), Mat.Neon)
		part(m, "LanternCap", V3(1.6, 0.4, 1.6), O * CFrame.new(lx, 6.5, 13.5), RGB(50, 50, 62), Mat.Metal)
		local light = Instance.new("PointLight")
		light.Color = RGB(255, 200, 130)
		light.Range = 10
		light.Brightness = 0.7
		light.Parent = lantern
	end

	-- A pixel-art arrow floating above the cap, pointing up: chunky green
	-- cubes with a light edge, bobbing (and a small glow under it)
	local ARROW = {
		"...L...",
		"..LGG..",
		".LGGGG.",
		"LGGGGGG",
		"..LGG..",
		"..LGG..",
		"..LGG..",
	}
	local green, light = RGB(99, 199, 77), RGB(190, 240, 140)
	local cube = 1.1
	for y, row in ipairs(ARROW) do
		for x = 1, #row do
			local ch = string.sub(row, x, x)
			if ch ~= "." then
				local p = part(m, "ArrowPixel", V3(cube, cube, cube), O * CFrame.new((x - 4) * cube, 38 + (#ARROW - y) * cube, STEM_Z), ch == "L" and light or green, Mat.Neon, { CanCollide = false, CanQuery = false })
				fx(p, { BobAmp = 0.8, BobSpeed = 2 })
			end
		end
	end

	titleSign(m, O * CFrame.new(0, 46, STEM_Z), "UPGRADES", "Spend coins to grow stronger", RGB(120, 200, 255), 340, 90)
	part(m, "Mat", V3(10, 0.3, 4), O * CFrame.new(0, 0.95, 11.6), RGB(90, 170, 255), Mat.Neon, { Transparency = 0.35, CanCollide = false })

	addPrompt(top, "Upgrades", "Open Upgrades", "Upgrade Shop", 14)
	autoZone(m, O * CFrame.new(0, 4, 12), V3(16, 8, 10), "Panel", "Upgrades")
end

----------------------------------------------------------------------
-- Talisman Workbench (north, faces south)
----------------------------------------------------------------------
local function buildCraftBench(parent)
	-- The Armory: a blacksmith's forge. Stone workshop with a half-timbered
	-- frame, red tiled gable roof and chimney, an arched door, a glowing
	-- furnace, an anvil with a talisman being forged above it, a quench
	-- barrel, weapon rack and a bit of fence. Faces south, towards the plaza.
	local m = folder(parent, "CraftBench")
	local O = CFrame.new(Config.Stations.Craft)
	local stone = RGB(176, 168, 156)
	local stoneDark = RGB(140, 132, 122)
	local timber = RGB(92, 62, 40)
	local iron = RGB(58, 58, 66)
	local tileA, tileB = RGB(188, 88, 58), RGB(166, 74, 48)

	-- a straight beam from p1 to p2 (local coords), for rafters and braces
	local function beam(name, p1, p2, thick, color, mat)
		local a, b = (O * CFrame.new(p1)).Position, (O * CFrame.new(p2)).Position
		local len = (b - a).Magnitude
		local mid = a + (b - a) / 2
		return part(m, name, V3(thick, thick, len), CFrame.lookAt(mid, b), color or timber, mat or Mat.Wood)
	end

	-- Cobblestone platform
	part(m, "BaseTrim", V3(35, 0.6, 31), O * CFrame.new(0, 0.3, -3), stoneDark, Mat.Cobblestone)
	part(m, "Base", V3(34, 1, 30), O * CFrame.new(0, 0.5, -3), RGB(196, 186, 170), Mat.Cobblestone)

	-- Stone room at the back (walls up to the eaves at y=12)
	local EAVE_Y, RIDGE_Y, HALF_W = 12, 20.5, 16
	part(m, "BackWall", V3(28, 11, 2), O * CFrame.new(0, 6.5, -17), stone, Mat.Cobblestone)
	part(m, "SideWallL", V3(2, 11, 13), O * CFrame.new(-13, 6.5, -11), stone, Mat.Cobblestone)
	part(m, "SideWallR", V3(2, 11, 13), O * CFrame.new(13, 6.5, -11), stone, Mat.Cobblestone)
	part(m, "FrontWallL", V3(11, 11, 2), O * CFrame.new(-8.5, 6.5, -5), stone, Mat.Cobblestone)
	part(m, "FrontWallR", V3(11, 11, 2), O * CFrame.new(8.5, 6.5, -5), stone, Mat.Cobblestone)
	part(m, "OverDoor", V3(6, 3, 2), O * CFrame.new(0, 10.5, -5), stone, Mat.Cobblestone)

	-- Arched wooden door
	discZ(m, "DoorArchStone", 0.4, 7.6, O * CFrame.new(0, 8, -3.8), stoneDark, Mat.Cobblestone)
	discZ(m, "DoorArchWood", 0.5, 6, O * CFrame.new(0, 8, -3.7), RGB(110, 72, 44), Mat.WoodPlanks)
	part(m, "Door", V3(6, 7, 0.5), O * CFrame.new(0, 4.5, -3.7), RGB(110, 72, 44), Mat.WoodPlanks)
	for _, dx in ipairs({ -1.5, 1.5 }) do
		part(m, "DoorPlankLine", V3(0.2, 9.5, 0.55), O * CFrame.new(dx, 5.6, -3.65), RGB(80, 52, 32), Mat.Wood)
	end
	ball(m, "DoorHandle", 0.6, O * CFrame.new(2, 5, -3.35), GOLD, Mat.Metal)

	-- Half-timbering on the outside of the side walls
	for _, sx in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -16.5, -11, -5.5 }) do
			part(m, "Timber", V3(0.5, 11, 0.9), O * CFrame.new(sx * 14.05, 6.5, z), timber, Mat.Wood)
		end
		beam("TimberBrace", V3(sx * 14.1, 1.5, -16.5), V3(sx * 14.1, 11.5, -11), 0.7)
		beam("TimberBrace", V3(sx * 14.1, 1.5, -5.5), V3(sx * 14.1, 11.5, -11), 0.7)
		part(m, "WallPlate", V3(0.9, 0.9, 30), O * CFrame.new(sx * 14.5, EAVE_Y, -3), timber, Mat.Wood)
		-- front posts holding up the roof over the open workshop, with knee braces
		part(m, "FrontPost", V3(1.2, 11, 1.2), O * CFrame.new(sx * 14.5, 6.5, 11), timber, Mat.Wood)
		beam("KneeBrace", V3(sx * 14.5, 8.5, 11), V3(sx * 14.5, 11.6, 7), 0.7)
	end

	-- Stone filling both gables under the roof - over the back wall, and over
	-- the front wall of the stone room (so there's no open triangle between
	-- the wall and the roof). Each is a solid triangle that follows the roof's
	-- slope exactly: two wedges meeting under the ridge, on a low band where
	-- the walls stop short of the roof's full width.
	local function gable(z)
		local rise, run = RIDGE_Y - EAVE_Y, HALF_W
		local wallHalf = 14 -- the walls reach 14 studs either side
		local lift = rise * (run - wallHalf) / run -- the roof's height over the wall's ends
		part(m, "GableBand", V3(wallHalf * 2, lift, 2), O * CFrame.new(0, EAVE_Y + lift / 2, z), stone, Mat.Cobblestone)
		local h = rise - lift
		for _, side in ipairs({ -1, 1 }) do
			-- (a wedge's upright face is at its local +Z, its slope running down
			-- to -Z: so +Z points in to the middle, and the low tip out to the side)
			local w = Instance.new("WedgePart")
			w.Name = "Gable"
			w.Anchored = true
			w.Size = V3(2, h, wallHalf)
			w.CFrame = O * CFrame.fromMatrix(V3(side * wallHalf / 2, EAVE_Y + lift + h / 2, z), V3(0, 0, side), V3(0, 1, 0), V3(-side, 0, 0))
			w.Color = stone
			w.Material = Mat.Cobblestone
			w.TopSurface = Enum.SurfaceType.Smooth
			w.BottomSurface = Enum.SurfaceType.Smooth
			w.Parent = m
		end
	end
	gable(-17)
	gable(-5)
	-- a little round attic window glowing in the front gable
	discZ(m, "AtticWindowFrame", 0.4, 3.4, O * CFrame.new(0, 15.6, -3.9), timber, Mat.Wood)
	local attic = discZ(m, "AtticWindow", 0.45, 2.6, O * CFrame.new(0, 15.6, -3.85), RGB(255, 206, 120), Mat.Neon, { Transparency = 0.15 })
	part(m, "AtticWindowBar", V3(0.25, 2.6, 0.5), O * CFrame.new(0, 15.6, -3.8), timber, Mat.Wood)
	part(m, "AtticWindowBar", V3(2.6, 0.25, 0.5), O * CFrame.new(0, 15.6, -3.8), timber, Mat.Wood)
	local atticLight = Instance.new("PointLight")
	atticLight.Color = RGB(255, 200, 120)
	atticLight.Range = 8
	atticLight.Brightness = 0.6
	atticLight.Parent = attic

	-- Red tiled gable roof: rows of overlapping tile strips on each slope
	local run, rise = HALF_W, RIDGE_Y - EAVE_Y
	local slopeLen = math.sqrt(run * run + rise * rise)
	for _, side in ipairs({ -1, 1 }) do
		local down = V3(side * run / slopeLen, -rise / slopeLen, 0)
		for k = 0, 4 do
			local d = 1.9 + k * 3.7
			local c = V3(0, RIDGE_Y + 0.35 + k * 0.05, -3) + down * d
			local wc = (O * CFrame.new(c)).Position
			part(m, "RoofTiles", V3(31, 0.7, 4.3), CFrame.lookAt(wc, wc + down), (k % 2 == 0) and tileA or tileB, Mat.Slate)
		end
		-- front and back rafters
		for _, z in ipairs({ 11.6, -17.6 }) do
			beam("Rafter", V3(side * (run + 0.8), EAVE_Y - 0.4, z), V3(0, RIDGE_Y, z), 0.9)
		end
		-- front truss struts
		beam("Strut", V3(0, EAVE_Y + 0.5, 11.6), V3(side * 8, (EAVE_Y + RIDGE_Y) / 2, 11.6), 0.7)
	end
	part(m, "RidgeCap", V3(2.2, 1, 31.6), O * CFrame.new(0, RIDGE_Y + 0.6, -3), RGB(140, 60, 40), Mat.Slate)
	part(m, "TieBeam", V3(2 * run + 1, 0.9, 0.9), O * CFrame.new(0, EAVE_Y, 11.6), timber, Mat.Wood)
	part(m, "KingPost", V3(0.9, rise, 0.9), O * CFrame.new(0, EAVE_Y + rise / 2, 11.6), timber, Mat.Wood)

	-- Chimney with smoke
	part(m, "Chimney", V3(4, 14, 4), O * CFrame.new(-8, 19, -13), stoneDark, Mat.Cobblestone)
	local cap = part(m, "ChimneyCap", V3(5, 1, 5), O * CFrame.new(-8, 26.5, -13), RGB(110, 104, 96), Mat.Cobblestone)
	local smoke = Instance.new("Smoke")
	smoke.Color = RGB(150, 150, 150)
	smoke.Opacity = 0.15
	smoke.RiseVelocity = 4
	smoke.Size = 3
	smoke.Parent = cap

	-- Furnace with a glowing mouth and real fire
	part(m, "Furnace", V3(7, 6, 4), O * CFrame.new(8.5, 4, -2), stoneDark, Mat.Cobblestone)
	part(m, "FurnaceTop", V3(5, 1.5, 3.4), O * CFrame.new(8.5, 7.75, -2.3), stoneDark, Mat.Cobblestone)
	part(m, "FurnaceMouth", V3(3.8, 3, 0.3), O * CFrame.new(8.5, 3.6, 0.05), RGB(24, 18, 16), Mat.SmoothPlastic)
	local glowPart = part(m, "FurnaceGlow", V3(3, 2.2, 0.3), O * CFrame.new(8.5, 3.4, 0.1), RGB(255, 130, 40), Mat.Neon)
	local furnaceLight = Instance.new("PointLight")
	furnaceLight.Color = RGB(255, 140, 60)
	furnaceLight.Range = 18
	furnaceLight.Brightness = 2
	furnaceLight.Parent = glowPart
	local fireHolder = part(m, "FurnaceFire", V3(1, 1, 1), O * CFrame.new(8.5, 3.2, -1.2), RGB(0, 0, 0), Mat.SmoothPlastic, {
		Transparency = 1,
		CanCollide = false,
	})
	local fire = Instance.new("Fire")
	fire.Size = 2.5
	fire.Heat = 3
	fire.Color = RGB(255, 120, 30)
	fire.SecondaryColor = RGB(255, 210, 80)
	fire.Parent = fireHolder
	for i, c in ipairs({ { 12.8, 1.2 }, { 13.4, 2.6 }, { 12.3, 2.9 } }) do
		ball(m, "Coal" .. i, 1.3, O * CFrame.new(c[1], 1.5, c[2]), RGB(34, 34, 38), Mat.Slate)
	end

	-- Anvil (the station itself) with a talisman being forged above it
	part(m, "AnvilBase", V3(2.6, 1.6, 2), O * CFrame.new(-6, 1.8, 3.5), iron, Mat.Metal)
	part(m, "AnvilWaist", V3(1.4, 1.4, 1.2), O * CFrame.new(-6, 3.3, 3.5), iron, Mat.Metal)
	local anvilTop = part(m, "AnvilTop", V3(4.4, 1.2, 2), O * CFrame.new(-6, 4.6, 3.5), RGB(78, 80, 92), Mat.Metal)
	part(m, "AnvilHorn", V3(1.4, 0.8, 1), O * CFrame.new(-8.9, 4.7, 3.5), RGB(78, 80, 92), Mat.Metal)

	local tal = part(m, "TalismanDisc", V3(0.4, 2.6, 2.6), O * CFrame.new(-6, 8, 3.5) * CFrame.Angles(0, math.rad(90), 0), RGB(255, 205, 60), Mat.Metal, {
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
	})
	local gem = ball(m, "TalismanGem", 1.1, O * CFrame.new(-6, 8, 3.5), RGB(80, 230, 255), Mat.Neon, { CanCollide = false })
	fx(tal, { SpinSpeed = 70, BobAmp = 0.4, BobSpeed = 1.6 })
	fx(gem, { SpinSpeed = 70, BobAmp = 0.4, BobSpeed = 1.6 })
	local glow = Instance.new("PointLight")
	glow.Color = RGB(120, 220, 255)
	glow.Range = 10
	glow.Brightness = 1
	glow.Parent = gem

	-- Quench barrel
	cylinder(m, "Barrel", 3.2, 3, O * CFrame.new(-12, 2.6, 6.5), RGB(130, 88, 54), Mat.WoodPlanks)
	cylinder(m, "BarrelWater", 0.2, 2.6, O * CFrame.new(-12, 4.25, 6.5), RGB(70, 130, 190), Mat.Glass, { Transparency = 0.2 })
	for _, y in ipairs({ 1.8, 3.4 }) do
		cylinder(m, "BarrelBand", 0.3, 3.1, O * CFrame.new(-12, y, 6.5), iron, Mat.Metal)
	end

	-- Weapon rack against the wall, left of the door
	part(m, "RackBar", V3(5, 0.4, 0.4), O * CFrame.new(-10.5, 6.5, -3.6), timber, Mat.Wood)
	for i, x in ipairs({ -12.3, -10.5, -8.7 }) do
		part(m, "SwordBlade" .. i, V3(0.3, 4.2, 0.8), O * CFrame.new(x, 3.6, -3.4), RGB(200, 204, 214), Mat.Metal)
		part(m, "SwordGuard" .. i, V3(1.6, 0.3, 0.4), O * CFrame.new(x, 5.8, -3.4), GOLD, Mat.Metal)
		part(m, "SwordGrip" .. i, V3(0.35, 1.2, 0.35), O * CFrame.new(x, 6.6, -3.4), RGB(90, 56, 34), Mat.Wood)
	end

	-- Crate of gold ingots
	part(m, "Crate", V3(3, 3, 3), O * CFrame.new(12, 2.5, 7), RGB(160, 112, 70), Mat.WoodPlanks)
	for i, x in ipairs({ 11.2, 12.8 }) do
		part(m, "Ingot" .. i, V3(1.4, 0.5, 0.7), O * CFrame.new(x, 4.25, 7), GOLD, Mat.Metal)
	end
	part(m, "Ingot3", V3(1.4, 0.5, 0.7), O * CFrame.new(12, 4.75, 7), GOLD, Mat.Metal)

	-- A little fence down the right side
	local c = Config.Stations.Craft
	fence(m, V3(c.X + 17.5, 0, c.Z - 4), V3(c.X + 17.5, 0, c.Z + 10))

	-- The blacksmith (your uploaded Smith model), standing behind the anvil.
	-- If it can't load, the old blocky smith with apron and hammer appears.
	avatarNPC(m, NPC_MODELS.Smith, "Blacksmith", facingCustomer(O, -6, -0.5), Config.Stations.Craft.Y + 1, function()
		local smithBase = O * CFrame.new(0, 0.2, 0) -- npc() expects the floor top at y=0.8; ours is 1.0
		local smith = npc(m, smithBase, -6, -0.5, RGB(150, 60, 50))
		smith.Name = "Blacksmith"
		part(smith, "Apron", V3(3.2, 4.2, 0.3), smithBase * CFrame.new(-6, 4.8, 0.55), RGB(84, 58, 38), Mat.Fabric)
		part(smith, "HammerHandle", V3(0.45, 3, 0.45), smithBase * CFrame.new(-3.6, 4.4, 0.2), RGB(100, 70, 40), Mat.Wood)
		part(smith, "HammerHead", V3(1.4, 1.1, 1.1), smithBase * CFrame.new(-3.6, 6.1, 0.2), iron, Mat.Metal)
		part(smith, "Beard", V3(2.2, 1.4, 0.4), smithBase * CFrame.new(-6, 7.8, 0.95), RGB(120, 70, 40), Mat.Fabric)
	end)

	titleSign(m, O * CFrame.new(0, 31, -3), "ARMORY", "The blacksmith forges your talismans", RGB(255, 150, 90), 380, 85)

	addPrompt(anvilTop, "Craft", "Forge Talismans", "Blacksmith", 16)
	autoZone(m, O * CFrame.new(-2, 5, 6), V3(24, 10, 14), "Panel", "Craft")
end

----------------------------------------------------------------------
-- Prestige Shrine (dead centre of the lobby)
----------------------------------------------------------------------
local function buildShrine(parent)
	local m = folder(parent, "PrestigeShrine")
	local O = CFrame.new(Config.Stations.Prestige)

	cylinder(m, "Tier1", 1.2, 24, O * CFrame.new(0, 1.0, 0), RGB(200, 190, 176), Mat.Marble)
	cylinder(m, "Tier2", 1.2, 17.5, O * CFrame.new(0, 2.2, 0), RGB(236, 226, 206), Mat.Marble)
	local tier3 = cylinder(m, "Tier3", 1.2, 11, O * CFrame.new(0, 3.4, 0), RGB(255, 200, 60), Mat.Metal)

	for k = 0, 3 do
		local a = math.rad(45 + k * 90)
		local px, pz = math.cos(a) * 10, math.sin(a) * 10
		part(m, "Pillar" .. k, V3(2.4, 13, 2.4), CFrame.new(px, 8.1, pz), RGB(228, 218, 200), Mat.Marble)
		part(m, "PillarCap" .. k, V3(3.4, 1, 3.4), CFrame.new(px, 15.1, pz), RGB(255, 200, 60), Mat.Neon, { Transparency = 0.15 })
	end

	-- Floating crystal + orbiting orbs + light beam
	local crystal = part(m, "Crystal", V3(4.4, 4.4, 4.4), CFrame.new(0, 12, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35)), RGB(214, 110, 255), Mat.Neon, { CanCollide = false })
	fx(crystal, { SpinSpeed = 50, BobAmp = 0.9, BobSpeed = 1.5 })
	local light = Instance.new("PointLight")
	light.Color = RGB(214, 110, 255)
	light.Range = 34
	light.Brightness = 2
	light.Parent = crystal

	local orbCenter = V3(0, 12, 0)
	for k = 1, 3 do
		local phase = (k - 1) * 120
		local a = math.rad(phase)
		local orb = ball(m, "Orb" .. k, 1.5, CFrame.new(orbCenter + V3(math.cos(a) * 6.5, 0, math.sin(a) * 6.5)), RGB(255, 210, 70), Mat.Neon, { CanCollide = false })
		fx(orb, { OrbitRadius = 6.5, OrbitSpeed = 70, OrbitCenter = orbCenter, Phase = phase, BobAmp = 0.5, BobSpeed = 2.4 })
	end

	cylinder(m, "Beam", 22, 1.6, CFrame.new(0, 15, 0), RGB(255, 170, 240), Mat.Neon, { Transparency = 0.7, CanCollide = false, CanQuery = false })

	-- The temple round it: gold rims on the steps, rune tiles set in the
	-- lowest step, each pillar on a stepped plinth with a gold band, fluting
	-- and a capital, lintels joining the pillar tops into a square frame
	-- with cloth hangings, and a ring of gold runes turning over the crystal.
	local marble, marbleDark, gold, cloth = RGB(236, 226, 206), RGB(196, 186, 172), RGB(255, 200, 60), RGB(181, 80, 136)
	local deco = { CanCollide = false }
	cylinder(m, "Tier1Rim", 0.3, 24.4, O * CFrame.new(0, 1.55, 0), gold, Mat.Metal, deco)
	cylinder(m, "Tier2Rim", 0.3, 17.9, O * CFrame.new(0, 2.75, 0), gold, Mat.Metal, deco)
	for i = 0, 11 do
		local a = math.rad(i * 30 + 15)
		part(m, "RuneTile", V3(1.2, 0.2, 1.2), O * CFrame.new(math.cos(a) * 10.4, 1.65, math.sin(a) * 10.4) * CFrame.Angles(0, -a, 0), (i % 2 == 0) and gold or RGB(214, 110, 255), Mat.Neon, deco)
	end
	for k = 0, 3 do
		local a = math.rad(45 + k * 90)
		local px, pz = math.cos(a) * 10, math.sin(a) * 10
		part(m, "Plinth", V3(4, 1, 4), CFrame.new(px, 2.1, pz), marbleDark, Mat.Marble)
		part(m, "Plinth2", V3(3.2, 0.6, 3.2), CFrame.new(px, 2.9, pz), marble, Mat.Marble)
		part(m, "PillarBand", V3(2.8, 0.4, 2.8), CFrame.new(px, 3.9, pz), gold, Mat.Metal, deco)
		for _, f in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			part(m, "Flute", V3(f[1] ~= 0 and 0.2 or 0.5, 9, f[2] ~= 0 and 0.2 or 0.5), CFrame.new(px + f[1] * 1.2, 9, pz + f[2] * 1.2), marbleDark, Mat.Marble, deco)
		end
		part(m, "Capital", V3(3.6, 0.8, 3.6), CFrame.new(px, 14.2, pz), marbleDark, Mat.Marble)
	end
	-- lintels round the top, with a gold trim, and hangings between the pillars
	local L = math.cos(math.rad(45)) * 10
	for _, e in ipairs({ { 0, L, true }, { 0, -L, true }, { L, 0, false }, { -L, 0, false } }) do
		local size = e[3] and V3(L * 2 + 3.4, 1.2, 1.6) or V3(1.6, 1.2, L * 2 + 3.4)
		part(m, "Lintel", size, CFrame.new(e[1], 16.2, e[2]), marble, Mat.Marble)
		part(m, "LintelTrim", size + V3(0.1, -0.9, 0.1), CFrame.new(e[1], 15.75, e[2]), gold, Mat.Metal, deco)
		local hang = e[3] and V3(4, 3.6, 0.2) or V3(0.2, 3.6, 4)
		part(m, "Hanging", hang, CFrame.new(e[1], 13.8, e[2]), cloth, Mat.Fabric, deco)
		part(m, "HangingTrim", hang + V3(0.05, -3.3, 0.05), CFrame.new(e[1], 12.1, e[2]), gold, Mat.Metal, deco)
	end
	for k = 1, 8 do
		local phase = (k - 1) * 45
		local ra = math.rad(phase)
		local rune = part(m, "Rune" .. k, V3(0.7, 0.7, 0.7), CFrame.new(math.cos(ra) * 4.5, 18.4, math.sin(ra) * 4.5) * CFrame.Angles(math.rad(45), 0, math.rad(45)), gold, Mat.Neon, deco)
		fx(rune, { OrbitRadius = 4.5, OrbitSpeed = 35, OrbitCenter = V3(0, 18.4, 0), Phase = phase, SpinSpeed = 90 })
	end


	addPrompt(tier3, "Stats", "Stat Points", "Shrine of Growth", 18)
	autoZone(m, O * CFrame.new(0, 5, 0), V3(16, 10, 16), "Panel", "Stats")
end

----------------------------------------------------------------------
-- Training yard: six practice dummies, each cooler than the last
----------------------------------------------------------------------
local LOOKS = {
	{ torsoMat = Mat.Fabric, torso = RGB(218, 188, 114), headMat = Mat.Fabric, head = RGB(202, 170, 106), postMat = Mat.WoodPlanks, post = RGB(122, 84, 50) },
	{ torsoMat = Mat.Metal, torso = RGB(150, 162, 182), headMat = Mat.DiamondPlate, head = RGB(132, 144, 164), postMat = Mat.Metal, post = RGB(88, 96, 112) },
	{ torsoMat = Mat.Ice, torso = RGB(168, 232, 255), headMat = Mat.Ice, head = RGB(190, 240, 255), postMat = Mat.Ice, post = RGB(210, 244, 255) },
	{ torsoMat = Mat.Basalt, torso = RGB(58, 46, 48), headMat = Mat.Basalt, head = RGB(70, 54, 54), postMat = Mat.Slate, post = RGB(44, 38, 42) },
	{ torsoMat = Mat.Slate, torso = RGB(38, 26, 66), headMat = Mat.Slate, head = RGB(30, 22, 54), postMat = Mat.Metal, post = RGB(34, 30, 48) },
	{ torsoMat = Mat.Metal, torso = RGB(255, 214, 92), headMat = Mat.Metal, head = RGB(255, 226, 130), postMat = Mat.Metal, post = RGB(236, 190, 70) },
	-- the upper tier
	{ torsoMat = Mat.SmoothPlastic, torso = RGB(90, 200, 70), headMat = Mat.SmoothPlastic, head = RGB(130, 235, 95), postMat = Mat.Metal, post = RGB(52, 72, 56) }, -- Ooze
	{ torsoMat = Mat.Sandstone, torso = RGB(220, 180, 110), headMat = Mat.Sandstone, head = RGB(236, 204, 136), postMat = Mat.Wood, post = RGB(140, 100, 64) }, -- Dune
	{ torsoMat = Mat.Glass, torso = RGB(255, 140, 210), headMat = Mat.Glass, head = RGB(255, 186, 232), postMat = Mat.Marble, post = RGB(214, 150, 200) }, -- Crystal
	{ torsoMat = Mat.Metal, torso = RGB(60, 80, 124), headMat = Mat.Metal, head = RGB(84, 112, 164), postMat = Mat.Metal, post = RGB(40, 50, 80) }, -- Storm
	{ torsoMat = Mat.Slate, torso = RGB(170, 32, 32), headMat = Mat.Slate, head = RGB(204, 44, 40), postMat = Mat.Basalt, post = RGB(60, 22, 22) }, -- Dragon
	{ torsoMat = Mat.SmoothPlastic, torso = RGB(40, 30, 92), headMat = Mat.SmoothPlastic, head = RGB(64, 44, 134), postMat = Mat.Metal, post = RGB(26, 20, 48) }, -- Cosmic
}

-- Small neon bits circling a point (animated client-side)
local function orbiters(parent, count, radius, speed, center, color, size, shard)
	for k = 1, count do
		local phase = (k - 1) * (360 / count)
		local a = math.rad(phase)
		local pos = center + V3(math.cos(a) * radius, 0, math.sin(a) * radius)
		local p
		if shard then
			p = part(parent, "Orbiter" .. k, V3(size, size, size), CFrame.new(pos) * CFrame.Angles(math.rad(45), 0, math.rad(45)), color, Mat.Neon, { CanCollide = false })
		else
			p = ball(parent, "Orbiter" .. k, size, CFrame.new(pos), color, Mat.Neon, { CanCollide = false })
		end
		fx(p, {
			OrbitRadius = radius,
			OrbitSpeed = speed,
			OrbitCenter = center,
			Phase = phase,
			SpinSpeed = 120,
			BobAmp = 0.5,
			BobSpeed = 2 + k * 0.3,
		})
	end
end

local function buildDummy(dummy, zi, zone, O)
	local look = LOOKS[zi]
	local col = zone.color
	local dark = RGB(48, 52, 70)
	local y0 = 1.1 -- top of the pad

	cylinder(dummy, "Pedestal", 1.2, 9, O * CFrame.new(0, y0 + 0.6, 0), dark, Mat.Metal)
	cylinder(dummy, "PedestalGlow", 0.3, 10.4, O * CFrame.new(0, y0 + 0.15, 0), col, Mat.Neon, { Transparency = 0.25 })
	local yb = y0 + 1.2

	-- Body (this sub-model is what the client shakes when you hit it)
	local body = Instance.new("Model")
	body.Name = "Body"
	body.Parent = dummy

	part(body, "Post", V3(1.6, 9, 1.6), O * CFrame.new(0, yb + 4.5, 0), look.post, look.postMat)
	local torso = part(body, "Torso", V3(5, 5.6, 3.2), O * CFrame.new(0, yb + 6.6, 0), look.torso, look.torsoMat)
	local head = part(body, "Head", V3(3.2, 3.2, 3.2), O * CFrame.new(0, yb + 11.2, 0), look.head, look.headMat)
	part(body, "Arms", V3(11, 1.2, 1.2), O * CFrame.new(0, yb + 8.2, -0.2), look.post, look.postMat)
	part(body, "EyeL", V3(0.7, 0.7, 0.3), O * CFrame.new(-0.85, yb + 11.5, 1.65), col, Mat.Neon)
	part(body, "EyeR", V3(0.7, 0.7, 0.3), O * CFrame.new(0.85, yb + 11.5, 1.65), col, Mat.Neon)
	-- a pixel face: cross little brows and a stitched grin (it's smug)
	for _, sx in ipairs({ -1, 1 }) do
		part(body, "Brow", V3(0.9, 0.25, 0.3), O * CFrame.new(sx * 0.85, yb + 12.15, 1.66) * CFrame.Angles(0, 0, math.rad(sx * 14)), RGB(24, 20, 37), Mat.SmoothPlastic, { CanCollide = false })
	end
	for k = -2, 2 do
		part(body, "Grin", V3(0.35, 0.3, 0.3), O * CFrame.new(k * 0.38, yb + 10.35 + ((math.abs(k) == 2) and 0.2 or 0), 1.66), RGB(24, 20, 37), Mat.SmoothPlastic, { CanCollide = false })
	end

	-- Bullseye on the chest
	local chest = O * CFrame.new(0, yb + 6.8, 1.65)
	local function disc(name, thick, dia, c, material, zoff)
		discZ(body, name, thick, dia, chest * CFrame.new(0, 0, zoff), c, material)
	end
	disc("Ring", 0.3, 3.8, col, Mat.Neon, 0)
	disc("RingInner", 0.35, 2.5, dark, Mat.Metal, 0.02)
	disc("RingCore", 0.4, 1.2, col, Mat.Neon, 0.04)

	body.PrimaryPart = torso

	-- Hit burst (the client calls :Emit on this)
	local burst = Instance.new("ParticleEmitter")
	burst.Name = "HitBurst"
	burst.Enabled = false
	burst.Rate = 0
	burst.Color = ColorSequence.new(col, RGB(255, 255, 255))
	burst.LightEmission = 1
	burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) })
	burst.Lifetime = NumberRange.new(0.35, 0.7)
	burst.Speed = NumberRange.new(14, 24)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Drag = 4
	burst.Parent = torso

	-- Tier-specific flair
	local orbitCenter = (O * CFrame.new(0, yb + 7, 0)).Position

	if zi == 3 then
		for k = 1, 5 do
			local a = math.rad(k * 72)
			local pos = V3(math.cos(a) * 5.4, yb + 2.4, math.sin(a) * 5.4)
			local axis = V3(math.sin(a), 0, -math.cos(a))
			part(dummy, "Shard" .. k, V3(1.3, 5.5, 1.3), O * CFrame.new(pos) * CFrame.fromAxisAngle(axis, math.rad(18)), RGB(180, 236, 255), Mat.Ice, { Transparency = 0.15 })
		end
	elseif zi == 4 then
		local fire = Instance.new("Fire")
		fire.Size = 6
		fire.Heat = 8
		fire.Color = col
		fire.SecondaryColor = RGB(255, 200, 60)
		fire.Parent = head
		local l = Instance.new("PointLight")
		l.Color = col
		l.Range = 24
		l.Brightness = 1.5
		l.Parent = torso
		orbiters(dummy, 3, 6.5, 80, orbitCenter, col, 1.1, false)
	elseif zi == 5 then
		local rise = Instance.new("ParticleEmitter")
		rise.Name = "VoidMist"
		rise.Rate = 14
		rise.Color = ColorSequence.new(RGB(190, 120, 255), RGB(50, 20, 100))
		rise.LightEmission = 0.8
		rise.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
		rise.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		rise.Lifetime = NumberRange.new(1.6, 2.4)
		rise.Speed = NumberRange.new(3, 6)
		rise.SpreadAngle = Vector2.new(25, 25)
		rise.Parent = torso
		local l = Instance.new("PointLight")
		l.Color = col
		l.Range = 26
		l.Brightness = 1.6
		l.Parent = torso
		orbiters(dummy, 4, 7.5, 70, orbitCenter, col, 1.3, true)
	elseif zi == 6 then
		local halo = cylinder(dummy, "Halo", 0.35, 6.5, O * CFrame.new(0, yb + 14.4, 0), col, Mat.Neon, { CanCollide = false })
		fx(halo, { BobAmp = 0.4, BobSpeed = 1.8 })
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = col
		sparkles.Parent = torso
		local l = Instance.new("PointLight")
		l.Color = col
		l.Range = 30
		l.Brightness = 2
		l.Parent = torso
		cylinder(dummy, "Beam", 40, 1.4, O * CFrame.new(0, yb + 20, 0), col, Mat.Neon, { Transparency = 0.75, CanCollide = false, CanQuery = false })
		orbiters(dummy, 5, 8.5, 110, orbitCenter, RGB(255, 245, 200), 1.4, false)
	elseif zi >= 7 then
		-- the upper tier: every one glows in its colour...
		local l = Instance.new("PointLight")
		l.Color = col
		l.Range = 26
		l.Brightness = 1.6
		l.Parent = torso
		if zi == 7 then
			-- Ooze (Gloomgut's slime): a puddle round its feet, slime dripping
			-- off its arms, bubbles floating round it
			cylinder(dummy, "SlimePuddle", 0.25, 12, O * CFrame.new(0, y0 + 0.2, 0), RGB(90, 220, 70), Mat.Neon, { Transparency = 0.35, CanCollide = false })
			for _, dx in ipairs({ -4.6, -2.4, 2.8, 4.8 }) do
				local len = 1.2 + math.abs(dx) * 0.3
				part(body, "SlimeDrip", V3(0.6, len, 0.6), O * CFrame.new(dx, yb + 8.2 - 0.6 - len / 2, -0.2), RGB(120, 255, 90), Mat.Neon, { CanCollide = false })
			end
			orbiters(dummy, 4, 6.5, 50, orbitCenter, RGB(160, 255, 120), 1.2, false)
		elseif zi == 8 then
			-- Dune (Mireworm's sands): a sand swirl round it, and a little
			-- sandworm arching out of the ground behind it
			for k = 0, 6 do
				local t = k / 6
				local pos = V3(-4 + t * 8, yb + 1 + math.sin(t * math.pi) * 9, -3.5)
				ball(dummy, "WormArc", 2.4 - t * 0.9, O * CFrame.new(pos), (k % 2 == 0) and RGB(196, 150, 96) or RGB(170, 124, 80), Mat.Sandstone, { CanCollide = false })
			end
			orbiters(dummy, 6, 7, 60, orbitCenter, RGB(240, 200, 130), 1.1, true)
		elseif zi == 9 then
			-- Crystal: pink crystal spires round its base
			for k = 1, 6 do
				local a = math.rad(k * 60)
				local pos = V3(math.cos(a) * 5.4, yb + 2.2, math.sin(a) * 5.4)
				local axis = V3(math.sin(a), 0, -math.cos(a))
				local h = 3.5 + (k % 3) * 1.5
				part(dummy, "Crystal" .. k, V3(1.2, h, 1.2), O * CFrame.new(pos) * CFrame.fromAxisAngle(axis, math.rad(16)), RGB(255, 150, 220), Mat.Neon, { Transparency = 0.2 })
			end
			orbiters(dummy, 4, 7.5, 70, orbitCenter, RGB(255, 200, 240), 1.2, true)
		elseif zi == 10 then
			-- Storm: a zigzag bolt of lightning over its head, sparks whirling fast
			local pts = { V3(0, 13.5, 0), V3(1.2, 15.2, 0), V3(-0.8, 16.6, 0), V3(1, 18.4, 0), V3(-0.4, 20, 0) }
			for k = 1, #pts - 1 do
				local a, b = O * CFrame.new(pts[k] + V3(0, yb, 0)), O * CFrame.new(pts[k + 1] + V3(0, yb, 0))
				local mid = (a.Position + b.Position) / 2
				part(dummy, "Bolt", V3(0.5, 0.5, (b.Position - a.Position).Magnitude), CFrame.lookAt(mid, b.Position), RGB(200, 240, 255), Mat.Neon, { CanCollide = false })
			end
			orbiters(dummy, 6, 7, 200, orbitCenter, RGB(160, 220, 255), 0.8, true)
		elseif zi == 11 then
			-- Dragon: horns, wings and fire from its head
			for _, sx in ipairs({ -1, 1 }) do
				part(body, "Horn", V3(0.6, 2.4, 0.6), O * CFrame.new(sx * 1.2, yb + 13.4, 0) * CFrame.Angles(0, 0, math.rad(-sx * 20)), RGB(240, 220, 180), Mat.SmoothPlastic)
				part(body, "Wing", V3(5.5, 4, 0.3), O * CFrame.new(sx * 4.6, yb + 9.4, -2) * CFrame.Angles(0, math.rad(sx * 25), math.rad(sx * 18)), RGB(120, 20, 24), Mat.SmoothPlastic, { CanCollide = false })
			end
			local fire = Instance.new("Fire")
			fire.Size = 6
			fire.Heat = 9
			fire.Color = col
			fire.SecondaryColor = RGB(255, 200, 60)
			fire.Parent = head
			orbiters(dummy, 3, 7, 90, orbitCenter, RGB(255, 140, 60), 1.2, true)
		elseif zi == 12 then
			-- Cosmic: a ring of starlight round it, little planets orbiting,
			-- and a beam of light into the sky
			local ring = cylinder(dummy, "StarRing", 0.3, 9, O * CFrame.new(0, yb + 7, 0) * CFrame.Angles(math.rad(20), 0, 0), RGB(200, 180, 255), Mat.Neon, { CanCollide = false, Transparency = 0.2 })
			fx(ring, { SpinSpeed = 30 })
			orbiters(dummy, 3, 9, 50, orbitCenter, RGB(255, 180, 120), 1.8, false)
			orbiters(dummy, 5, 6, 130, orbitCenter + V3(0, 3, 0), RGB(255, 255, 255), 0.6, true)
			cylinder(dummy, "Beam", 40, 1.4, O * CFrame.new(0, yb + 20, 0), col, Mat.Neon, { Transparency = 0.75, CanCollide = false, CanQuery = false })
		end
	end
end

local function buildYard(parent)
	local yard = folder(parent, "TrainingYard")
	local pad = Config.Yard.PadSize
	local Y = Config.Yard

	-- The upper tier: a raised stone terrace behind the first row, for the
	-- pads past the first PerRow, with a grand staircase across its whole
	-- front (shallow half-stud steps, easy to walk up), a low crenellated
	-- parapet round its back and sides, and braziers at its front corners.
	if #Config.Zones > Y.PerRow and Y.TierHeight > 0 then
		local c2 = Config.zonePosition(Y.PerRow + 1)
		local H = Y.TierHeight
		local halfW = (Y.PerRow / 2) * Y.Spacing - Y.Spacing / 2 + pad / 2 + 10 -- the pads, plus a margin
		local front, back = c2.Z - pad / 2 - 8, c2.Z + pad / 2 + 12
		local stone, stoneDark, trim = RGB(150, 146, 156), RGB(112, 108, 120), RGB(214, 170, 70)
		part(yard, "Terrace", V3(halfW * 2, H, back - front), CFrame.new(0, H / 2, (front + back) / 2), stone, Mat.Slate)
		part(yard, "TerraceTop", V3(halfW * 2, 0.3, back - front), CFrame.new(0, H + 0.15, (front + back) / 2), RGB(96, 106, 132), Mat.Slate)
		part(yard, "TerraceTrim", V3(halfW * 2 + 0.4, 0.4, 0.6), CFrame.new(0, H + 0.2, front - 0.1), trim, Mat.Metal, { CanCollide = false })
		-- the grand staircase
		local steps = math.floor(H / 0.5)
		local depth = 0.95
		for k = 1, steps do
			local h = k * 0.5
			local z = front - (steps - k + 0.5) * depth
			part(yard, "Stair", V3(halfW * 2, h, depth + 0.02), CFrame.new(0, h / 2, z), (k % 2 == 0) and stone or stoneDark, Mat.Slate)
		end
		-- the parapet: back and sides, with merlons
		local function parapet(a, b)
			local mid, len = (a + b) / 2, (b - a).Magnitude
			local alongX = math.abs(b.X - a.X) > math.abs(b.Z - a.Z)
			part(yard, "Parapet", alongX and V3(len, 1.6, 1.2) or V3(1.2, 1.6, len), CFrame.new(mid.X, H + 1.1, mid.Z), stoneDark, Mat.Slate)
			for t = 2, len - 2, 5 do
				local p = a + (b - a).Unit * t
				part(yard, "ParapetMerlon", V3(1.6, 1.2, 1.6), CFrame.new(p.X, H + 2.5, p.Z), stone, Mat.Slate)
			end
		end
		-- (a gap in the middle of the back, with steps down to the south gate)
		parapet(V3(-halfW, 0, back - 0.6), V3(-10, 0, back - 0.6))
		parapet(V3(10, 0, back - 0.6), V3(halfW, 0, back - 0.6))
		for k = 1, math.floor(H / 0.5) do
			local h = k * 0.5
			local z = back + (math.floor(H / 0.5) - k + 0.5) * 0.95
			part(yard, "BackStair", V3(20, h, 0.97), CFrame.new(0, h / 2, z), (k % 2 == 0) and stone or stoneDark, Mat.Slate)
		end
		parapet(V3(-halfW + 0.6, 0, front + 2), V3(-halfW + 0.6, 0, back - 0.6))
		parapet(V3(halfW - 0.6, 0, front + 2), V3(halfW - 0.6, 0, back - 0.6))
		-- braziers at the front corners, burning
		for _, sx in ipairs({ -1, 1 }) do
			local bx, bz = sx * (halfW - 3), front + 2.5
			part(yard, "BrazierBase", V3(3, 1, 3), CFrame.new(bx, H + 0.5, bz), stoneDark, Mat.Slate)
			part(yard, "BrazierPost", V3(1.4, 5, 1.4), CFrame.new(bx, H + 3.5, bz), stone, Mat.Slate)
			local bowl = cylinder(yard, "BrazierBowl", 1.2, 3.6, CFrame.new(bx, H + 6.6, bz), RGB(58, 58, 66), Mat.Metal)
			local fire = Instance.new("Fire")
			fire.Size = 5
			fire.Heat = 8
			fire.Color = RGB(255, 140, 40)
			fire.SecondaryColor = RGB(255, 220, 90)
			fire.Parent = bowl
			local light = Instance.new("PointLight")
			light.Color = RGB(255, 170, 90)
			light.Range = 24
			light.Brightness = 1.4
			light.Parent = bowl
		end
	end

	for zi, zone in ipairs(Config.Zones) do
		local c = Config.zonePosition(zi)
		local col = zone.color
		local gy = c.Y -- the ground this pad stands on

		-- The pad players stand on
		part(yard, "Pad" .. zi, V3(pad, 0.5, pad), CFrame.new(c.X, gy + 0.85, c.Z), RGB(44, 48, 66), Mat.Metal)
		part(yard, "PadGlow" .. zi, V3(pad - 4, 0.15, pad - 4), CFrame.new(c.X, gy + 1.175, c.Z), col, Mat.Neon, { Transparency = 0.4 })
		local edge = pad / 2 - 0.5
		part(yard, "EdgeN" .. zi, V3(pad, 0.2, 1), CFrame.new(c.X, gy + 1.2, c.Z - edge), col, Mat.Neon, { CanCollide = false })
		part(yard, "EdgeS" .. zi, V3(pad, 0.2, 1), CFrame.new(c.X, gy + 1.2, c.Z + edge), col, Mat.Neon, { CanCollide = false })
		part(yard, "EdgeW" .. zi, V3(1, 0.2, pad - 2), CFrame.new(c.X - edge, gy + 1.2, c.Z), col, Mat.Neon, { CanCollide = false })
		part(yard, "EdgeE" .. zi, V3(1, 0.2, pad - 2), CFrame.new(c.X + edge, gy + 1.2, c.Z), col, Mat.Neon, { CanCollide = false })

		-- The dummy stands at the back of its pad, facing north (toward the player)
		local dz = c.Z + 6
		local dummy = Instance.new("Model")
		dummy.Name = "Dummy" .. zi
		dummy:SetAttribute("ZoneIndex", zi)
		dummy.Parent = yard
		local O = CFrame.new(c.X, gy, dz) * CFrame.Angles(0, math.pi, 0)
		buildDummy(dummy, zi, zone, O)
		CollectionService:AddTag(dummy, "Dummy")

		-- Multiplier sign: a black box with a white border (the game's look),
		-- sized in studs so it's readable up close without filling the screen.
		-- Kept to a short MaxDistance on purpose: the pads sit only 32 studs
		-- apart, so you only ever see the sign for the pad you're near.
		local anchor = anchorPart(yard, "SignAnchor" .. zi, CFrame.new(c.X, gy + 21, dz))
		local bb = billboard(anchor, "ZoneSign", UDim2.fromScale(300 * SIGN_STUDS_PER_PIXEL, 150 * SIGN_STUDS_PER_PIXEL), 50)
		bb:SetAttribute("ZoneIndex", zi)
		local box = Instance.new("Frame")
		box.Name = "Box"
		box.BackgroundColor3 = RGB(12, 10, 20)
		box.BackgroundTransparency = 0.15
		box.Size = UDim2.fromScale(1, 1)
		box.ZIndex = 0
		box.Parent = bb
		local boxEdge = Instance.new("UIStroke")
		boxEdge.Color = RGB(255, 255, 255)
		boxEdge.Thickness = 3
		boxEdge.Parent = box
		billLabel(bb, "Mult", "x" .. Config.formatMult(zone.mult), col, UDim2.fromScale(0.05, 0.04), UDim2.fromScale(0.9, 0.46))
		billLabel(bb, "Name", zone.name, RGB(255, 255, 255), UDim2.fromScale(0.05, 0.5), UDim2.fromScale(0.9, 0.24))
		local status = billLabel(bb, "Status", zone.level <= 1 and "UNLOCKED" or ("Needs Level " .. zone.level), RGB(120, 255, 160), UDim2.fromScale(0.05, 0.74), UDim2.fromScale(0.9, 0.22))
		status.Name = "Status"
		CollectionService:AddTag(bb, "ZoneSign")
	end
end

----------------------------------------------------------------------
-- Castle gate (north wall, where the stairs to the Spire leave the lobby)
----------------------------------------------------------------------
-- A big gatehouse between two round towers: a tall pointed archway with the
-- iron portcullis pulled up into it, a row of little arches above, and
-- overhanging battlements (machicolations) on top. The stairs to the
-- Spire's bridge run straight through the archway.
local GATE_STONE = RGB(142, 144, 150)
local GATE_DARK = RGB(104, 106, 114)
local GATE_IRON = RGB(40, 40, 46)
local GATE_Z0, GATE_Z1 = -125, -111 -- back and front (lobby side) faces
local GATE_HALF_W = 22
local GATE_H = 56
local ARCH_HALF = 14 -- half the opening's width
local ARCH_SPRING = 16 -- where the arch starts to curve
local ARCH_R = 22 -- pointed arch: two arcs of this radius

-- Height of the pointed arch's underside at x (nil outside the opening)
local function gateArchY(x)
	local ax = math.abs(x)
	if ax >= ARCH_HALF then
		return nil
	end
	local cx = ARCH_R - ARCH_HALF -- the arc for this side is centred on the other side
	return ARCH_SPRING + math.sqrt(ARCH_R * ARCH_R - (ax + cx) * (ax + cx))
end

local function gateTower(parent, x)
	local z = (GATE_Z0 + GATE_Z1) / 2
	local H = GATE_H + 8
	local R = 12
	cylinder(parent, "TowerBody", H, R * 2, CFrame.new(x, H / 2, z), GATE_STONE, Mat.Cobblestone)
	cylinder(parent, "TowerPlinth", 5, R * 2 + 2, CFrame.new(x, 2.5, z), GATE_DARK, Mat.Cobblestone)
	-- overhanging top: corbels, then a wider parapet with merlons
	for i = 0, 17 do
		local a = i / 18 * math.pi * 2
		local dir = V3(math.cos(a), 0, math.sin(a))
		local p = V3(x, H - 2.2, z) + dir * (R + 0.6)
		part(parent, "Corbel", V3(1.6, 3, 1.8), CFrame.lookAt(p, p + dir), GATE_DARK, Mat.Cobblestone)
		if i % 2 == 0 then
			local mp = V3(x, H + 4.6, z) + dir * (R + 0.4)
			part(parent, "Merlon", V3(3.4, 3.6, 2), CFrame.lookAt(mp, mp + dir), GATE_DARK, Mat.Cobblestone)
		end
	end
	cylinder(parent, "TowerParapet", 3, R * 2 + 3, CFrame.new(x, H + 1.3, z), GATE_STONE, Mat.Cobblestone)
	cylinder(parent, "TowerRoof", 0.4, R * 2 + 1, CFrame.new(x, H + 2.9, z), GATE_DARK, Mat.Slate)
	-- small arched windows, mostly on the side facing the lobby
	for _, w in ipairs({ { 0.5, 20 }, { 0.2, 36 }, { 0.8, 36 }, { 0.5, 50 }, { -0.1, 26 }, { 1.1, 26 } }) do
		local a = math.pi / 2 + (w[1] - 0.5) * 1.6 -- spread round the front
		local dir = V3(math.cos(a), 0, math.sin(a))
		local p = V3(x, w[2], z) + dir * (R + 0.05)
		local cf = CFrame.lookAt(p, p + dir)
		part(parent, "Window", V3(1.4, 3.6, 0.3), cf, RGB(26, 26, 34), Mat.SmoothPlastic)
		cylinder(parent, "WindowTop", 0.3, 1.4, cf * CFrame.new(0, 1.8, 0) * CFrame.Angles(0, 0, -math.pi / 2) * CFrame.Angles(0, math.pi / 2, 0), RGB(26, 26, 34), Mat.SmoothPlastic)
	end
end

local function buildCastleGate(parent)
	local m = folder(parent, "CastleGate")
	local depth = GATE_Z1 - GATE_Z0
	local zc = (GATE_Z0 + GATE_Z1) / 2

	-- solid sides of the gatehouse
	for _, sx in ipairs({ -1, 1 }) do
		local w = GATE_HALF_W - ARCH_HALF
		part(m, "GateSide", V3(w, GATE_H, depth), CFrame.new(sx * (ARCH_HALF + w / 2), GATE_H / 2, zc), GATE_STONE, Mat.Cobblestone)
		part(m, "GatePlinth", V3(w + 1, 4, depth + 1), CFrame.new(sx * (ARCH_HALF + w / 2), 2, zc), GATE_DARK, Mat.Cobblestone)
	end
	-- stone above the pointed arch, in thin vertical slices that follow the curve
	local SLICE = 1
	for x0 = -ARCH_HALF, ARCH_HALF - SLICE, SLICE do
		local xm = x0 + SLICE / 2
		local bottom = math.min(gateArchY(x0 + 0.001) or ARCH_SPRING, gateArchY(x0 + SLICE - 0.001) or ARCH_SPRING)
		part(m, "GateArchFill", V3(SLICE + 0.02, GATE_H - bottom, depth), CFrame.new(xm, (GATE_H + bottom) / 2, zc), GATE_STONE, Mat.Cobblestone)
	end
	-- the arch ring (voussoirs) on both faces, in darker stone
	for _, face in ipairs({ GATE_Z1 + 0.4, GATE_Z0 - 0.4 }) do
		for _, sx in ipairs({ -1, 1 }) do
			part(m, "Jamb", V3(2, ARCH_SPRING, 1.2), CFrame.new(sx * (ARCH_HALF + 1), ARCH_SPRING / 2, face), GATE_DARK, Mat.Cobblestone)
			local N = 9
			for k = 0, N - 1 do
				local function pt(t) -- t: 0 at the spring, 1 at the point
					local cx = ARCH_R - ARCH_HALF
					local a0 = math.atan2(0, -ARCH_R) -- start angle (pointing outwards)
					local a1 = math.atan2(math.sqrt(ARCH_R * ARCH_R - cx * cx), -cx)
					local a = a0 + (a1 - a0) * t
					local r = ARCH_R + 1
					return V3(sx * (-cx - math.cos(a) * r) * -1, ARCH_SPRING + math.sin(a) * r, face)
				end
				local p0, p1 = pt(k / N), pt((k + 1) / N)
				local mid = (p0 + p1) / 2
				local dir = (p1 - p0).Unit
				local len = (p1 - p0).Magnitude + 0.3
				part(m, "Voussoir", V3(2.2, 1.4, len), CFrame.lookAt(mid, mid + dir, V3(0, 0, 1)), GATE_DARK, Mat.Cobblestone)
			end
		end
	end

	-- the portcullis, pulled up so only its spiked bottom shows in the arch
	local PORT_BOTTOM = 29
	local pz = zc
	for x = -12, 12, 2 do
		local top = gateArchY(x)
		if top and top > PORT_BOTTOM + 1 then
			part(m, "PortcullisBar", V3(0.7, top - PORT_BOTTOM + 1, 0.7), CFrame.new(x, (top + 1 + PORT_BOTTOM) / 2, pz), GATE_IRON, Mat.Metal)
			part(m, "PortcullisSpike", V3(0.5, 1.4, 0.5), CFrame.new(x, PORT_BOTTOM - 0.6, pz), GATE_IRON, Mat.Metal)
		end
	end
	for _, y in ipairs({ PORT_BOTTOM + 0.5, PORT_BOTTOM + 3.5 }) do
		local halfSpan = 0
		for x = 0, ARCH_HALF, 0.25 do
			local top = gateArchY(x)
			if top and top > y then
				halfSpan = x
			end
		end
		part(m, "PortcullisRail", V3(halfSpan * 2, 0.6, 0.6), CFrame.new(0, y, pz), GATE_IRON, Mat.Metal)
	end

	-- lobby-side decoration: a row of small blind arches above the gate
	local face = GATE_Z1 + 0.3
	for i = -3, 3 do
		local x = i * 4.6
		part(m, "BlindArch", V3(2.4, 3.4, 0.4), CFrame.new(x, 43, face), GATE_DARK, Mat.SmoothPlastic)
		discZ(m, "BlindArchTop", 0.4, 2.4, CFrame.new(x, 44.7, face), GATE_DARK, Mat.SmoothPlastic)
	end
	part(m, "StringCourse", V3(GATE_HALF_W * 2 + 1, 1, 1.2), CFrame.new(0, 40.4, face + 0.3), GATE_DARK, Mat.Cobblestone)
	-- machicolations and merlons along the top, both faces
	for _, side in ipairs({ { GATE_Z1, 1 }, { GATE_Z0, -1 } }) do
		local z, out = side[1], side[2]
		part(m, "Parapet", V3(GATE_HALF_W * 2 + 2, 4, 2), CFrame.new(0, GATE_H + 1, z + out * 0.6), GATE_STONE, Mat.Cobblestone)
		for x = -GATE_HALF_W + 1.5, GATE_HALF_W - 1.5, 3 do
			part(m, "Corbel", V3(1.4, 2.6, 1.8), CFrame.new(x, GATE_H - 2.2, z + out * 0.6), GATE_DARK, Mat.Cobblestone)
		end
		for x = -GATE_HALF_W + 2, GATE_HALF_W - 2, 5 do
			part(m, "Merlon", V3(3, 3.4, 2), CFrame.new(x, GATE_H + 4.7, z + out * 0.6), GATE_DARK, Mat.Cobblestone)
		end
	end
	-- torches either side of the archway on the lobby side
	for _, sx in ipairs({ -1, 1 }) do
		wallTorch(m, V3(sx * 18, 14, GATE_Z1), V3(0, 0, 1))
		banner(m, V3(sx * 18, 30, GATE_Z1 + 0.1), V3(0, 0, 1), sx < 0 and BANNER_RED or BANNER_BLUE)
	end

	gateTower(m, -(GATE_HALF_W + 10))
	gateTower(m, GATE_HALF_W + 10)
end

----------------------------------------------------------------------
-- The Spire (north, behind the castle wall)
----------------------------------------------------------------------
-- A stone staircase leaves the lobby through the gap in the north wall and
-- climbs a rocky hill to a tall, dark spire: spiked ledges, a glowing blue
-- rune halfway up and a blue flame burning in a crown of turrets on top.
-- It's tall enough to be seen over the walls from everywhere in the lobby.
-- Only the outside is built for now: the door is where the boss floors
-- will start later.
local SPIRE_STONE = RGB(92, 80, 78)
local SPIRE_DARK = RGB(58, 52, 58)
local SPIRE_METAL = RGB(46, 44, 52)
local SPIRE_GLOW = RGB(90, 150, 255)
local HILL_ROCK = { RGB(88, 84, 92), RGB(102, 96, 102), RGB(76, 72, 80) }

local STAIR_Z0 = -112 -- first step (inside the wall gap)
local STAIR_STEPS = 34
local STAIR_RISE = 0.6 -- shallow, comfortable steps
local STAIR_TREAD = 3.2
local STAIR_HALF_W = 12
local SPIRE_BASE_Y = STAIR_STEPS * STAIR_RISE -- 20.4, the top of the bridge / hilltop
local SPIRE_Z = -316 -- centre of the tower, out past the bridge
local SPIRE_ROCK_R = 88 -- radius of the crag it stands on

-- Height of the stair line at a given z (0 at the bottom step)
local function stairHeightAt(z)
	return math.clamp((STAIR_Z0 - z) / STAIR_TREAD * STAIR_RISE, 0, SPIRE_BASE_Y)
end

-- A spike: a long thin block with a smaller tip, pointing along `dir`
local function spike(parent, base, dir, len, thick, color)
	-- (straight up needs its own case: lookAt can't aim exactly along the up axis)
	local cf = math.abs(dir.Y) > 0.999 and CFrame.new(base) * CFrame.Angles(math.pi / 2, 0, 0) or CFrame.lookAt(base, base + dir)
	part(parent, "Spike", V3(thick, thick, len * 0.65), cf * CFrame.new(0, 0, -len * 0.325), color, Mat.Slate)
	part(parent, "SpikeTip", V3(thick * 0.55, thick * 0.55, len * 0.45), cf * CFrame.new(0, 0, -len * 0.775), color, Mat.Slate)
end

-- A torch post on the stair railing. `t` goes 0 -> 1 up the stairs and
-- fades the fire from warm orange to the spire's cold blue.
local function stairTorch(parent, x, z, t)
	local top = stairHeightAt(z)
	part(parent, "RailPost", V3(2, 6 + 2, 2), CFrame.new(x, top + 2, z), SPIRE_DARK, Mat.Slate)
	part(parent, "RailPostCap", V3(2.6, 0.8, 2.6), CFrame.new(x, top + 6.4, z), SPIRE_METAL, Mat.Metal)
	local bowl = part(parent, "TorchBowl", V3(1.8, 1, 1.8), CFrame.new(x, top + 7.3, z), SPIRE_METAL, Mat.Metal)
	local fire = Instance.new("Fire")
	fire.Size = 4
	fire.Heat = 7
	fire.Color = RGB(255, 140, 40):Lerp(RGB(70, 120, 255), t)
	fire.SecondaryColor = RGB(255, 220, 90):Lerp(RGB(170, 210, 255), t)
	fire.Parent = bowl
	local light = Instance.new("PointLight")
	light.Range = 18
	light.Brightness = 1.3
	light.Color = RGB(255, 170, 90):Lerp(SPIRE_GLOW, t)
	light.Parent = bowl
end

local function buildSpire(parent)
	local m = folder(parent, "Spire")
	local B = SPIRE_BASE_Y

	-- Sign over the foot of the stairs
	titleSign(m, CFrame.new(0, 18, -113), "THE SPIRE", "Climb the stairs", RGB(150, 190, 255), 340, 140)

	-- The bridge: one long, gentle flight of wide shallow steps that starts
	-- in the castle gateway and climbs all the way across the chasm on
	-- dark stone arches, levelling out just before the Spire's rock. Built
	-- in the same dark slate as the tower, with the blight creeping along
	-- it the closer it gets.
	local W = STAIR_HALF_W
	local BR_STONE = RGB(74, 68, 76)
	local BR_TRIM = RGB(44, 42, 50)
	local BR_DECK = RGB(98, 92, 96)
	local BR_MOSS = { RGB(44, 62, 38), RGB(56, 50, 66), RGB(38, 52, 34) }
	local DECK_T = 2.6
	local zStairTop = STAIR_Z0 - STAIR_STEPS * STAIR_TREAD
	local zRock = SPIRE_Z + SPIRE_ROCK_R - 3 -- where the deck runs into the hilltop
	local function underside(z) -- a little above the true underside, so fills tuck into the steps
		return stairHeightAt(z) - DECK_T + 0.6
	end
	local noCol = { CanCollide = false, CanQuery = false, CastShadow = false }

	-- the steps (each one is also the deck above the arches)
	for i = 1, STAIR_STEPS do
		local top = i * STAIR_RISE
		local z = STAIR_Z0 - (i - 0.5) * STAIR_TREAD
		local bottom = (z > -119) and -2 or (top - DECK_T)
		part(m, "Step", V3(W * 2, top - bottom, STAIR_TREAD + 0.02), CFrame.new(0, (top + bottom) / 2, z),
			(i % 2 == 0) and BR_DECK or RGB(92, 86, 90), Mat.Cobblestone)
	end
	-- level landing at the top, into the rock
	local deckLen = zStairTop - zRock
	part(m, "BridgeDeck", V3(W * 2, DECK_T, deckLen), CFrame.new(0, B - DECK_T / 2, (zStairTop + zRock) / 2), BR_DECK, Mat.Cobblestone)

	-- arches all the way across, from the edge of the castle's rock
	local BODY_HALF = W + 2
	local PIER = 4.5
	local PIER_BOTTOM = -200 -- the piers vanish into the mist far below
	local zStart, zEnd = -121, zRock
	local ARCHES = 6
	local span = (zStart - zEnd) / ARCHES
	local archR = (span - PIER) / 2
	for k = 0, ARCHES do
		local z = zStart - k * span
		-- pier (the first one is the abutment against the castle's cliff)
		local pierTop = underside(z)
		local pw = (k == 0 or k == ARCHES) and PIER * 2 or PIER
		part(m, "Pier", V3(BODY_HALF * 2, pierTop - PIER_BOTTOM, pw), CFrame.new(0, (pierTop + PIER_BOTTOM) / 2, z - ((k == 0) and pw / 2 - PIER / 2 or 0)), BR_STONE, Mat.Slate)
		for _, sx in ipairs({ -1, 1 }) do
			part(m, "Buttress", V3(2.6, pierTop - 6 - PIER_BOTTOM, PIER + 2), CFrame.new(sx * (BODY_HALF + 1.3), (pierTop - 6 + PIER_BOTTOM) / 2, z), BR_TRIM, Mat.Slate)
			spike(m, V3(sx * (BODY_HALF + 1.3), pierTop - 6, z), V3(sx * 0.3, 1, 0).Unit, 5, 2.2, BR_TRIM)
		end
		if k < ARCHES then
			local zA = z
			local cz = zA - span / 2
			local crownY = underside(zA) - 1.6
			local springY = crownY - archR
			local SEG = 10
			for j = 0, SEG - 1 do
				local a0, a1 = math.pi * j / SEG, math.pi * (j + 1) / SEG
				local am = (a0 + a1) / 2
				local pz, py = cz + math.cos(am) * archR, springY + math.sin(am) * archR
				local segLen = 2 * archR * math.sin(math.pi / SEG / 2) + 0.35
				part(m, "ArchRing", V3(BODY_HALF * 2 + 0.4, 1.6, segLen), CFrame.new(0, py, pz) * CFrame.Angles(-(am - math.pi / 2), 0, 0), BR_TRIM, Mat.Slate)
				local fillBottom = py + 0.5
				local fillTop = underside(pz)
				if fillTop - fillBottom > 0.2 then
					part(m, "Spandrel", V3(BODY_HALF * 2, fillTop - fillBottom, segLen + 0.1), CFrame.new(0, (fillTop + fillBottom) / 2, pz), BR_STONE, Mat.Slate)
				end
			end
			-- the part of each pier below the arch is the pier itself; hang some vines from the crown
			if k >= 2 then
				for n = 1, k - 1 do
					local vx = (n - k / 2) * 5 + (rnd() - 0.5) * 2
					local top = V3(vx, crownY - 0.6, cz + (rnd() - 0.5) * 3)
					local len = 5 + rnd() * 8
					part(m, "ArchVine", V3(0.45, len, 0.45), CFrame.new(top - V3(0, len / 2, 0)), RGB(34, 46, 30), Mat.Wood, noCol)
					ball(m, "ArchVineLeaves", 1.6 + rnd(), CFrame.new(top - V3(0, len * 0.5, 0)), BR_MOSS[1 + math.floor(rnd() * 3)], Mat.LeafyGrass, noCol)
				end
			end
		end
	end

	-- parapets: sloped along the steps, level along the landing
	local function sloped(x, h, w, yOff, color, name)
		local a, b = V3(x, yOff, STAIR_Z0), V3(x, B + yOff, zStairTop)
		part(m, name, V3(w, h, (b - a).Magnitude + 0.4), CFrame.lookAt((a + b) / 2, b), color, Mat.Slate)
		part(m, name, V3(w, h, deckLen), CFrame.new(x, B + yOff, (zStairTop + zRock) / 2), color, Mat.Slate)
	end
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (W + 0.9)
		sloped(x, 3.2, 1.8, 1.6, BR_STONE, "Parapet")
		sloped(x, 0.7, 2.4, 3.5, BR_TRIM, "ParapetCap")
		sloped(sx * (BODY_HALF + 0.2), 1.2, 1.2, -DECK_T - 0.3, BR_TRIM, "Cornice")
		-- merlons along the top
		for z = STAIR_Z0 - 2, zRock + 2, -4.5 do
			part(m, "ParapetMerlon", V3(2.2, 1.6, 2.2), CFrame.new(x, stairHeightAt(z) + 4.6, z), BR_TRIM, Mat.Slate)
		end
		-- torches every so often, warm by the castle and cold blue near the Spire
		for z = STAIR_Z0 - 1, zRock + 4, -16 do
			stairTorch(m, x, z, math.clamp((STAIR_Z0 - z) / (STAIR_Z0 - zRock), 0, 1))
		end
		-- moss and leaves creeping along it, thicker towards the Spire
		for z = STAIR_Z0 - 20, zRock, -3 do
			local f = (STAIR_Z0 - z) / (STAIR_Z0 - zRock)
			if rnd() < f * 0.7 then
				local top = stairHeightAt(z) + 3.9
				part(m, "BridgeMoss", V3(2.6, 0.5, 2 + rnd() * 3), CFrame.new(x, top + 0.2, z) * CFrame.Angles(0, (rnd() - 0.5) * 0.3, 0), BR_MOSS[1 + math.floor(rnd() * 3)], Mat.LeafyGrass, noCol)
				if rnd() < 0.4 then
					ball(m, "BridgeLeaves", 1.6 + rnd() * 1.6, CFrame.new(x + sx * 1, top + 0.8, z), BR_MOSS[1 + math.floor(rnd() * 3)], Mat.LeafyGrass, noCol)
				end
				if rnd() < 0.25 then
					local vl = 4 + rnd() * 7
					part(m, "BridgeVine", V3(0.4, vl, 0.4), CFrame.new(sx * (BODY_HALF + 0.9), top - 4 - vl / 2, z), RGB(34, 46, 30), Mat.Wood, noCol)
				end
			end
		end
	end

	-- The rock the Spire stands on: a wide crag with cliffs all round
	local hill = folder(m, "Rock")
	cylinder(hill, "Hilltop", B + 30, SPIRE_ROCK_R * 2, CFrame.new(0, (B - 30) / 2 - 0.2, SPIRE_Z), HILL_ROCK[1], Mat.Slate)
	local nCliff = 34
	for i = 0, nCliff - 1 do
		local a = i / nCliff * math.pi * 2
		local r = SPIRE_ROCK_R - 2 + rnd() * 3
		local top = B - 3 + rnd() * 5
		local bottom = -26 - rnd() * 24
		local nearBridge = math.cos(a) > 0.95
		if nearBridge then
			top = B - 6 -- keep the bridge's arrival clear
		end
		local cf = CFrame.new(math.sin(a) * r, (top + bottom) / 2, SPIRE_Z + math.cos(a) * r) * CFrame.Angles(math.rad((rnd() - 0.5) * 8), a + (rnd() - 0.5) * 0.4, math.rad((rnd() - 0.5) * 8))
		part(hill, "Cliff", V3(12 + rnd() * 6, top - bottom, 8 + rnd() * 4), cf, HILL_ROCK[1 + math.floor(rnd() * 3)], Mat.Slate)
		if not nearBridge and rnd() < 0.6 then
			local h = 4 + rnd() * 8
			local cf2 = CFrame.new(math.sin(a) * (r - 2), B + h / 2 - 1, SPIRE_Z + math.cos(a) * (r - 2)) * CFrame.Angles(math.rad((rnd() - 0.5) * 16), rnd() * math.pi, math.rad((rnd() - 0.5) * 16))
			part(hill, "Crag", V3(6 + rnd() * 5, h, 5 + rnd() * 4), cf2, HILL_ROCK[1 + math.floor(rnd() * 3)], Mat.Slate)
		end
	end
	-- paved court in front of the gate
	cylinder(m, "Court", 0.6, SPIRE_ROCK_R * 2 - 6, CFrame.new(0, B + 0.1, SPIRE_Z), RGB(96, 90, 92), Mat.Cobblestone)

	-- The tower: a huge, dark, stepped fortress that tapers as it climbs,
	-- growing out of the rock like part of the mountain. Heavy fins brace
	-- every tier, overhanging battlements ring each step, only a few blue
	-- slits glow in the walls, and a broken crown of jagged shards holds the
	-- blue flame at the top.
	local t = folder(m, "Tower")
	local y = B + 0.4
	local ROCK = RGB(66, 62, 70)
	local ROCK2 = RGB(78, 72, 78)
	local TRIM = RGB(44, 42, 50)
	local WINDOW = RGB(90, 150, 255)

	local function faceDir(k)
		local a = k * math.pi / 6
		return V3(math.sin(a), 0, math.cos(a))
	end
	-- solid 12-sided block (three squares turned 30 degrees apart)
	local function dodec(name, y0, h, ap, color, mat)
		for k = 0, 2 do
			part(t, name, V3(ap * 2, h, ap * 2), CFrame.new(0, y0 + h / 2, SPIRE_Z) * CFrame.Angles(0, k * math.pi / 6, 0), color, mat)
		end
	end
	-- rough stone blocks stuck onto the walls so no face is clean
	local function roughen(y0, h, ap, count, skipFront)
		for _ = 1, count do
			local k = math.floor(rnd() * 12)
			if not (skipFront and (k == 0 or k == 11 or k == 1)) then
				local dir = faceDir(k + (rnd() - 0.5) * 0.7)
				local size = V3(3 + rnd() * 7, 3 + rnd() * 8, 2 + rnd() * 2.5)
				local p = V3(0, y0 + 2 + rnd() * (h - 4), SPIRE_Z) + dir * (ap + size.Z * 0.2)
				part(t, "Outcrop", size, CFrame.lookAt(p, p + dir) * CFrame.Angles(math.rad((rnd() - 0.5) * 20), 0, math.rad((rnd() - 0.5) * 20)), (rnd() < 0.5) and ROCK or ROCK2, Mat.Slate)
			end
		end
	end
	-- a glowing slit window
	local function slit(k, ap, cy, h)
		local dir = faceDir(k)
		local p = V3(0, cy, SPIRE_Z) + dir * (ap + 0.12)
		local cf = CFrame.lookAt(p, p + dir)
		part(t, "SlitFrame", V3(2.8, h + 1.4, 0.5), cf * CFrame.new(0, 0, 0.1), TRIM, Mat.Slate)
		part(t, "Slit", V3(1.2, h, 0.3), cf * CFrame.new(0, 0, -0.2), WINDOW, Mat.Neon, { Transparency = 0.1 })
		part(t, "SlitTop", V3(0.85, 0.85, 0.3), cf * CFrame.new(0, h / 2, -0.2) * CFrame.Angles(0, 0, math.pi / 4), WINDOW, Mat.Neon, { Transparency = 0.1 })
	end
	-- overhanging battlements: a wider ring on brackets with merlons on top
	local function battlement(y0, ap)
		dodec("Battlement", y0, 3, ap, TRIM, Mat.Slate)
		for k = 0, 11 do
			local dir = faceDir(k)
			for _, off in ipairs({ -0.3, 0.3 }) do
				local side = V3(dir.Z, 0, -dir.X)
				local bp = V3(0, y0 - 1.6, SPIRE_Z) + dir * (ap - 1.8) + side * off * ap * 0.5
				part(t, "Bracket", V3(1.6, 3, 3.2), CFrame.lookAt(bp, bp + dir), TRIM, Mat.Slate)
			end
			local w = 2 * ap * math.tan(math.pi / 12)
			local mp = V3(0, y0 + 3 + 1.6, SPIRE_Z) + dir * (ap - 1)
			for _, off in ipairs({ -0.28, 0.28 }) do
				part(t, "Merlon", V3(w * 0.3, 3.2, 2), CFrame.lookAt(mp, mp + dir) * CFrame.new(off * w, 0, 0), TRIM, Mat.Slate)
			end
		end
	end
	-- heavy sloping fins bracing a tier
	local function fins(y0, h, apBottom, apTop, thick, skipFront)
		for i = 0, 5 do
			local k = i * 2 + 1 -- between the flat faces
			if not (skipFront and (i == 0 or i == 5)) then
				local dir = V3(math.sin(k * math.pi / 12), 0, math.cos(k * math.pi / 12))
				local foot = V3(0, y0, SPIRE_Z) + dir * (apBottom + 4)
				local head = V3(0, y0 + h, SPIRE_Z) + dir * (apTop + 1)
				local len = (head - foot).Magnitude
				part(t, "Fin", V3(thick * 1.5, thick * 2.2, len), CFrame.lookAt((foot + head) / 2, head) * CFrame.new(0, -thick * 0.3, 0), ROCK2, Mat.Slate)
				part(t, "FinCap", V3(thick + 0.8, 2, 4), CFrame.new(head + V3(0, 1, 0)) * CFrame.Angles(0, math.atan2(dir.X, dir.Z), 0), TRIM, Mat.Slate)
				spike(t, head + V3(0, 2, 0), (dir * 0.3 + V3(0, 1, 0)).Unit, 7, thick * 0.5, TRIM)
			end
		end
	end

	-- The base flares out into the rock
	local baseTiers = { { 42, 4 }, { 39, 4 }, { 36, 4 }, { 33.5, 4 } }
	local by = y
	for _, bt in ipairs(baseTiers) do
		dodec("Base", by, bt[2], bt[1], ROCK, Mat.Slate)
		by = by + bt[2]
	end
	-- crags heaped round the foot, leaning in (the front stays open)
	for i = 0, 27 do
		local a = (i + rnd() * 0.6) / 28 * math.pi * 2
		if math.cos(a) < 0.82 then
			local dir = V3(math.sin(a), 0, math.cos(a))
			local h = 10 + rnd() * 18
			local p = V3(0, y + h / 2 - 2, SPIRE_Z) + dir * (38 + rnd() * 6)
			local cf = CFrame.lookAt(p, p + dir) * CFrame.Angles(math.rad(-10 - rnd() * 12), 0, math.rad((rnd() - 0.5) * 16))
			part(t, "FootCrag", V3(8 + rnd() * 8, h, 6 + rnd() * 5), cf, (rnd() < 0.5) and ROCK or HILL_ROCK[1], Mat.Slate)
		end
	end

	-- the tiers: { height, apothem, fin thickness }
	local tiers = {
		{ h = 42, ap = 30, fin = 5 },
		{ h = 36, ap = 24.5, fin = 4 },
		{ h = 32, ap = 19.5, fin = 3.2 },
		{ h = 26, ap = 15, fin = 0 },
	}
	local ty = by
	local tierInfo = {}
	for i, tr in ipairs(tiers) do
		dodec("Shaft", ty, tr.h, tr.ap, (i % 2 == 1) and ROCK or ROCK2, Mat.Slate)
		roughen(ty, tr.h, tr.ap, 22 - i * 3, i == 1)
		-- a thin band of darker stone round the middle
		dodec("Band", ty + tr.h * 0.45, 1.4, tr.ap + 0.4, TRIM, Mat.Slate)
		if tr.fin > 0 then
			fins(ty, tr.h, tr.ap, tr.ap - 1, tr.fin, i == 1)
		end
		-- only a few glowing slits, scattered
		for _, k in ipairs(i == 1 and { 3, 6, 9 } or (i == 2 and { 0, 2, 5, 8, 10 } or (i == 3 and { 1, 4, 7, 11 } or { 0, 3, 6, 9 }))) do
			slit(k, tr.ap, ty + tr.h * (0.62 + ((k * 7) % 3) * 0.08), 4 + (i == 4 and 3 or 0))
		end
		tierInfo[i] = { y0 = ty, h = tr.h, ap = tr.ap }
		ty = ty + tr.h
		if i < #tiers then
			battlement(ty, tr.ap + 2.4)
			ty = ty + 3
		end
	end

	-- Broken crown: jagged shards of different heights round the top
	local cy = ty
	dodec("CrownFloor", cy, 2, 17, TRIM, Mat.Slate)
	for i = 0, 15 do
		local a = (i + 0.5) / 16 * math.pi * 2
		local dir = V3(math.sin(a), 0, math.cos(a))
		local h = 8 + ((i * 5) % 7) * 3 + rnd() * 4
		local p = V3(0, cy + 2 + h / 2 - 0.5, SPIRE_Z) + dir * 15
		local cf = CFrame.lookAt(p, p + dir) * CFrame.Angles(math.rad(-8 - rnd() * 10), 0, math.rad((rnd() - 0.5) * 10))
		part(t, "CrownShard", V3(3.4 + rnd() * 2, h, 2.6), cf, (i % 2 == 0) and ROCK or ROCK2, Mat.Slate)
		spike(t, (cf * CFrame.new(0, h / 2, 0)).Position, (dir * 0.3 + V3(0, 1, 0)).Unit, 4 + rnd() * 3, 1.6, TRIM)
	end

	-- the blue flame burning above the crown, held in iron claws
	local fc = V3(0, cy + 14, SPIRE_Z)
	cylinder(t, "FlamePedestal", 8, 8, CFrame.new(fc - V3(0, 10, 0)), TRIM, Mat.Slate)
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		local out = V3(math.sin(a), 0, math.cos(a))
		local p1 = fc - V3(0, 6, 0) + out * 3
		local p2 = fc + out * 6
		local p3 = fc + V3(0, 6, 0) + out * 3.4
		part(t, "Claw", V3(1.3, 1.3, (p2 - p1).Magnitude), CFrame.lookAt((p1 + p2) / 2, p2), SPIRE_METAL, Mat.Metal)
		part(t, "ClawTip", V3(0.9, 0.9, (p3 - p2).Magnitude), CFrame.lookAt((p2 + p3) / 2, p3), SPIRE_METAL, Mat.Metal)
	end
	local orb = ball(t, "FlameOrb", 7, CFrame.new(fc), SPIRE_GLOW, Mat.Neon, { Transparency = 0.1, CanCollide = false })
	local flame = Instance.new("Fire")
	flame.Size = 16
	flame.Heat = 18
	flame.Color = RGB(70, 120, 255)
	flame.SecondaryColor = RGB(190, 220, 255)
	flame.Parent = orb
	local wisps = Instance.new("ParticleEmitter")
	wisps.Rate = 26
	wisps.Color = ColorSequence.new(RGB(170, 205, 255), RGB(70, 110, 255))
	wisps.LightEmission = 1
	wisps.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 0) })
	wisps.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	wisps.Lifetime = NumberRange.new(1.5, 2.5)
	wisps.Speed = NumberRange.new(7, 12)
	wisps.SpreadAngle = Vector2.new(18, 18)
	wisps.EmissionDirection = Enum.NormalId.Top
	wisps.Parent = orb
	local glow = Instance.new("PointLight")
	glow.Range = 60
	glow.Brightness = 3
	glow.Color = SPIRE_GLOW
	glow.Parent = orb

	-- Evil nature: the tower is being swallowed by something growing. Dark
	-- roots climb out of the rock, thorny vines wind up every tier, gnarled
	-- dead trees sprout from the ledges, blighted moss creeps over the
	-- stone, strands of vine hang from the battlements, brambles choke the
	-- foot, and glowing mushrooms and spores give off a sickly light.
	-- (The soft glow of the mushrooms and seed pods is animated by LobbyFX.)
	local BARK = RGB(48, 38, 34)
	local VINE = RGB(34, 46, 30)
	local LEAF = { RGB(40, 56, 34), RGB(58, 44, 70), RGB(30, 42, 28) }
	local MOSS = { RGB(44, 62, 38), RGB(56, 50, 66), RGB(38, 52, 34) }
	local SHROOM = { RGB(160, 90, 255), RGB(80, 220, 200), RGB(190, 120, 255) }
	local POD = RGB(170, 100, 255)
	local function pulse(p, speed, lo, hi)
		p:SetAttribute("PulseSpeed", speed)
		p:SetAttribute("PulseMin", lo)
		p:SetAttribute("PulseMax", hi)
		p:SetAttribute("Phase", rnd() * 360)
		CollectionService:AddTag(p, "Pulse")
	end
	local noCol = { CanCollide = false, CanQuery = false, CastShadow = false }
	-- wall apothem at a height (for things that hug the tower)
	local function wallApAt(h)
		local yy = y
		for _, bt in ipairs(baseTiers) do
			if h < yy + bt[2] then
				return bt[1]
			end
			yy = yy + bt[2]
		end
		for _, ti in ipairs(tierInfo) do
			if h < ti.y0 + ti.h + 3 then
				return ti.ap
			end
		end
		return 17
	end
	-- only the doorway itself and the rune above it are kept clear
	local function blocksGate(a, h)
		return math.cos(a) > 0.96 and h < tierInfo[1].y0 + tierInfo[1].h + 3
	end
	local function thorn(base, d, len, thick, color) -- one-part spike, for small thorns
		part(t, "Thorn", V3(thick, thick, len), CFrame.lookAt(base, base + d) * CFrame.new(0, 0, -len / 2), color, Mat.Wood, noCol)
	end
	local function leafClump(pos, s)
		ball(t, "LeafClump", s, CFrame.new(pos), LEAF[1 + math.floor(rnd() * 3)], Mat.LeafyGrass, noCol)
	end

	-- The entrance: a raised platform up a flight of steps, a towering gate
	-- facade with three pointed arches set one inside the other, a light
	-- leaking through the crack of the great doors, flanking gate towers,
	-- torn banners, two hooded guardian statues holding swords, obelisks
	-- with blue flames lining the approach and glowing rune stones leading
	-- up to the door.
	local FZ = SPIRE_Z + baseTiers[1][1] + 10 -- front face of the gate facade (its arches sit in front of the flared base)
	local GZ = FZ
	local PLAT_H = 3.6
	local gy = y + PLAT_H -- floor level at the doors
	local FACADE_HALF = 18
	local FACADE_H = 52
	local BANNER = RGB(60, 34, 74)

	-- platform and steps
	part(t, "GatePlatform", V3(44, PLAT_H, 12), CFrame.new(0, y + PLAT_H / 2, FZ + 4), TRIM, Mat.Slate)
	for s = 1, 3 do
		local h = PLAT_H - s * PLAT_H / 3
		if h > 0.05 then
			part(t, "GateStep", V3(36 - s * 2, h, 2.2), CFrame.new(0, y + h / 2, FZ + 10 + s * 2 - 1), (s % 2 == 0) and ROCK or TRIM, Mat.Slate)
		end
	end

	-- the facade, in layers: each layer has a pointed opening a bit smaller
	-- than the one in front, so the arches step inwards like a tunnel
	local function pointedY(x, hw, spring)
		local ax = math.abs(x)
		if ax >= hw then
			return nil
		end
		local R = hw * 1.6
		local c = R - hw
		return spring + math.sqrt(R * R - (ax + c) * (ax + c))
	end
	local function archLayer(zFront, depth, hw, spring, color)
		local zc = zFront - depth / 2
		local sideW = FACADE_HALF - hw
		for _, sx in ipairs({ -1, 1 }) do
			part(t, "FacadeSide", V3(sideW, FACADE_H, depth), CFrame.new(sx * (hw + sideW / 2), gy + FACADE_H / 2, zc), color, Mat.Slate)
		end
		for x0 = -hw, hw - 1, 1 do
			local bottom = math.min(pointedY(x0 + 0.001, hw, spring) or spring, pointedY(x0 + 0.999, hw, spring) or spring)
			part(t, "FacadeArch", V3(1.02, FACADE_H - (bottom - gy), depth), CFrame.new(x0 + 0.5, (gy + FACADE_H + bottom) / 2, zc), color, Mat.Slate)
		end
	end
	archLayer(FZ, 2.5, 12, gy + 22, ROCK2)
	archLayer(FZ - 2.5, 2.5, 10, gy + 20, TRIM)
	archLayer(FZ - 5, 2.5, 8, gy + 18, ROCK2)
	-- solid mass behind, tying the facade into the tower
	part(t, "FacadeBack", V3(FACADE_HALF * 2, FACADE_H, 22), CFrame.new(0, gy + FACADE_H / 2, FZ - 7.5 - 11), ROCK, Mat.Slate)
	part(t, "FacadeUnder", V3(FACADE_HALF * 2, PLAT_H, 28), CFrame.new(0, y + PLAT_H / 2, FZ - 14), TRIM, Mat.Slate)

	-- the great doors fill the innermost arch
	local DZ = FZ - 7.5
	for x0 = -8, 7, 1 do
		local top = math.min(pointedY(x0 + 0.001, 8, gy + 18) or gy, pointedY(x0 + 0.999, 8, gy + 18) or gy)
		part(t, "GateDoor", V3(1.02, top - gy, 0.8), CFrame.new(x0 + 0.5, (gy + top) / 2, DZ + 0.4), (x0 % 2 == 0) and RGB(52, 38, 32) or RGB(58, 42, 36), Mat.WoodPlanks)
	end
	for _, bh in ipairs({ 4, 10, 16, 22 }) do
		local hwAt = 8
		if bh > 18 then
			hwAt = 8 - (bh - 18) * 0.9
		end
		part(t, "DoorBand", V3(hwAt * 2 - 0.6, 0.7, 0.3), CFrame.new(0, gy + bh, DZ + 0.95), SPIRE_METAL, Mat.Metal)
	end
	for _, sx in ipairs({ -1, 1 }) do
		cylinder(t, "DoorRing", 0.3, 2.2, CFrame.new(sx * 1.8, gy + 11, DZ + 1.05) * CFrame.Angles(math.pi / 2, 0, 0), SPIRE_METAL, Mat.Metal)
	end
	-- light leaking through the crack between the doors
	local crack = part(t, "DoorCrack", V3(0.35, 28, 0.3), CFrame.new(0, gy + 14, DZ + 0.9), SPIRE_GLOW, Mat.Neon, { CanCollide = false })
	pulse(crack, 0.6, 0, 0.35)
	local crackLight = Instance.new("SpotLight")
	crackLight.Face = Enum.NormalId.Front
	crackLight.Range = 30
	crackLight.Angle = 70
	crackLight.Brightness = 3
	crackLight.Color = SPIRE_GLOW
	crackLight.Parent = crack
	local doorGlow = part(t, "DoorGlowFloor", V3(10, 0.1, 12), CFrame.new(0, gy + 0.06, DZ + 6), SPIRE_GLOW, Mat.Neon, { CanCollide = false, CanQuery = false, Transparency = 0.8 })
	pulse(doorGlow, 0.6, 0.72, 0.9)
	t:FindFirstChild("GateDoor"):SetAttribute("Destination", "The Spire's boss floors")

	-- rune above the arches, battlements and a jagged crest on top
	local R = CFrame.new(0, gy + 45, FZ)
	discZ(t, "RuneFrame", 1.2, 11, R * CFrame.new(0, 0, 0.4), TRIM, Mat.Slate)
	discZ(t, "RuneRing", 0.4, 9, R * CFrame.new(0, 0, 1.1), SPIRE_METAL, Mat.Metal)
	local rune = discZ(t, "RuneGlow", 0.4, 7.6, R * CFrame.new(0, 0, 1.3), SPIRE_GLOW, Mat.Neon)
	discZ(t, "RuneCore", 0.4, 3.6, R * CFrame.new(0, 0, 1.5), RGB(200, 225, 255), Mat.Neon)
	for k = 0, 7 do
		local len = (k % 2 == 0) and 4.6 or 3
		part(t, "RuneSpike", V3(1.6, len, 1), R * CFrame.new(0, 0, 0.6) * CFrame.Angles(0, 0, k * math.pi / 4) * CFrame.new(0, 5.5 + len / 2 - 0.6, 0), TRIM, Mat.Slate)
	end
	pulse(rune, 0.5, 0, 0.3)
	local runeLight = Instance.new("PointLight")
	runeLight.Range = 34
	runeLight.Brightness = 2.2
	runeLight.Color = SPIRE_GLOW
	runeLight.Parent = rune
	part(t, "FacadeTop", V3(FACADE_HALF * 2 + 2, 3, 30), CFrame.new(0, gy + FACADE_H + 1.5, FZ - 14), TRIM, Mat.Slate)
	for i = -4, 4 do
		part(t, "FacadeMerlon", V3(2.6, 3.4, 2), CFrame.new(i * 4, gy + FACADE_H + 4.7, FZ + 0.2), TRIM, Mat.Slate)
	end
	spike(t, V3(0, gy + FACADE_H + 3, FZ - 4), V3(0, 1, 0.15).Unit, 18, 3.4, TRIM)
	for _, sx in ipairs({ -1, 1 }) do
		spike(t, V3(sx * 9, gy + FACADE_H + 3, FZ - 4), V3(sx * 0.25, 1, 0.15).Unit, 11, 2.6, TRIM)
	end

	-- gate towers on both sides, with spiked roofs and glowing slits
	for _, sx in ipairs({ -1, 1 }) do
		local tx = sx * (FACADE_HALF + 6)
		local TH = FACADE_H + 18
		part(t, "GateTower", V3(12, TH, 22), CFrame.new(tx, y + TH / 2, FZ - 10), ROCK, Mat.Slate)
		part(t, "GateTowerFoot", V3(14, 8, 24), CFrame.new(tx, y + 4, FZ - 9.5), TRIM, Mat.Slate)
		part(t, "GateTowerTop", V3(14.6, 3, 24.6), CFrame.new(tx, y + TH + 1.5, FZ - 10), TRIM, Mat.Slate)
		for _, cz in ipairs({ -1, 1 }) do
			for _, cx in ipairs({ -1, 1 }) do
				part(t, "GateTowerMerlon", V3(3, 3.4, 3), CFrame.new(tx + cx * 5.8, y + TH + 4.7, FZ - 10 + cz * 10.8), TRIM, Mat.Slate)
			end
		end
		for j = 0, 4 do
			local w = 10 - j * 2
			part(t, "GateTowerRoof", V3(w, 4, w + 1), CFrame.new(tx, y + TH + 5 + j * 4, FZ - 10) * CFrame.Angles(0, math.pi / 4 * (j % 2), 0), TRIM, Mat.Slate)
		end
		spike(t, V3(tx, y + TH + 24, FZ - 10), V3(0, 1, 0), 10, 1.4, TRIM)
		for _, sy in ipairs({ 22, 42, 60 }) do
			local p = V3(tx, y + sy, FZ + 1.05)
			part(t, "GateTowerSlit", V3(1.2, 5, 0.3), CFrame.new(p), WINDOW, Mat.Neon, { Transparency = 0.1 })
			part(t, "GateTowerSlitFrame", V3(2.6, 6.4, 0.4), CFrame.new(p - V3(0, 0, 0.2)), TRIM, Mat.Slate)
		end
		-- a torn banner hanging between tower and arches
		local bx = sx * 15
		part(t, "BannerRod", V3(7, 0.6, 0.6), CFrame.new(bx, gy + 42, FZ + 0.8), SPIRE_METAL, Mat.Metal)
		part(t, "Banner", V3(5.4, 18, 0.25), CFrame.new(bx, gy + 32.6, FZ + 0.6), BANNER, Mat.Fabric, noCol)
		for j = -1, 1 do
			local tl = 2 + ((j + 2) % 3) * 1.4
			part(t, "BannerTatter", V3(1.6, tl, 0.25), CFrame.new(bx + j * 1.9, gy + 23.6 - tl / 2, FZ + 0.6) * CFrame.Angles(0, 0, j * 0.08), BANNER, Mat.Fabric, noCol)
		end
		discZ(t, "BannerSigil", 0.3, 2.6, CFrame.new(bx, gy + 36, FZ + 0.8), SPIRE_GLOW, Mat.Neon)
	end

	-- hooded guardian statues flanking the steps, hands on planted swords
	local function guardian(x, z)
		local base = V3(x, y, z)
		local STONE = RGB(84, 80, 88)
		part(t, "StatuePedestal", V3(8, 5, 8), CFrame.new(base + V3(0, 2.5, 0)), TRIM, Mat.Slate)
		part(t, "StatuePedestalTop", V3(9, 1, 9), CFrame.new(base + V3(0, 5.5, 0)), ROCK2, Mat.Slate)
		local f = base + V3(0, 6, 0)
		-- robe, widening to the ground
		part(t, "StatueRobe", V3(6, 4, 4.6), CFrame.new(f + V3(0, 2, 0)), STONE, Mat.Slate)
		part(t, "StatueRobe", V3(5.2, 5, 3.8), CFrame.new(f + V3(0, 6.5, 0)), STONE, Mat.Slate)
		part(t, "StatueChest", V3(5.8, 4.4, 3.4), CFrame.new(f + V3(0, 11, 0)), STONE, Mat.Slate)
		part(t, "StatueShoulders", V3(7.6, 1.8, 3.8), CFrame.new(f + V3(0, 13.4, 0)), STONE, Mat.Slate)
		-- hood with a dark face and two faint blue eyes
		part(t, "StatueHood", V3(3.8, 4.2, 3.8), CFrame.new(f + V3(0, 16, -0.2)), STONE, Mat.Slate)
		part(t, "StatueHoodPoint", V3(2.6, 2.6, 2.6), CFrame.new(f + V3(0, 18.2, -0.6)) * CFrame.Angles(0.5, 0.785, 0.5), STONE, Mat.Slate)
		part(t, "StatueFace", V3(2.4, 2.6, 0.4), CFrame.new(f + V3(0, 15.7, 1.75)), RGB(14, 12, 18), Mat.SmoothPlastic)
		for _, ex in ipairs({ -0.55, 0.55 }) do
			part(t, "StatueEye", V3(0.45, 0.25, 0.2), CFrame.new(f + V3(ex, 16, 1.98)), SPIRE_GLOW, Mat.Neon)
		end
		-- arms reaching down to the sword hilt
		for _, s in ipairs({ -1, 1 }) do
			local sh = f + V3(s * 3.2, 12.6, 0.2)
			local hand = f + V3(s * 0.8, 9.6, 2.6)
			part(t, "StatueArm", V3(1.5, 1.5, (hand - sh).Magnitude + 0.6), CFrame.lookAt((sh + hand) / 2, hand), STONE, Mat.Slate)
		end
		part(t, "StatueHands", V3(2.6, 1.6, 1.6), CFrame.new(f + V3(0, 9.6, 2.7)), STONE, Mat.Slate)
		-- the sword, point down in front
		part(t, "SwordPommel", V3(1, 1, 1), CFrame.new(f + V3(0, 11, 2.8)), SPIRE_METAL, Mat.Metal)
		part(t, "SwordGrip", V3(0.6, 2.2, 0.6), CFrame.new(f + V3(0, 9.6, 2.8)), RGB(40, 30, 26), Mat.Wood)
		part(t, "SwordGuard", V3(4.4, 0.7, 0.8), CFrame.new(f + V3(0, 8.3, 2.8)), SPIRE_METAL, Mat.Metal)
		part(t, "SwordBlade", V3(1.1, 8.4, 0.4), CFrame.new(f + V3(0, 3.9, 2.8)), RGB(120, 124, 136), Mat.Metal)
		-- moss creeping over it
		part(t, "StatueMoss", V3(3, 0.5, 2.4), CFrame.new(f + V3(-1.2, 13.4 + 0.9, 0)) * CFrame.Angles(0, 0.4, 0.1), MOSS[1], Mat.LeafyGrass, noCol)
		part(t, "StatueMoss", V3(3.6, 2.4, 0.4), CFrame.new(f + V3(1.4, 2.6, 2.35)), MOSS[2], Mat.LeafyGrass, noCol)
	end
	guardian(-24, FZ + 16)
	guardian(24, FZ + 16)

	-- obelisks with blue flames lining the approach
	for i, z in ipairs({ FZ + 22, FZ + 28 }) do
		for _, sx in ipairs({ -1, 1 }) do
			local x = sx * 13
			local H = 16 - i * 2
			part(t, "ObeliskBase", V3(4, 2, 4), CFrame.new(x, y + 1, z), TRIM, Mat.Slate)
			part(t, "Obelisk", V3(2.6, H, 2.6), CFrame.new(x, y + 2 + H / 2, z), ROCK2, Mat.Slate)
			part(t, "ObeliskTop", V3(3.4, 1, 3.4), CFrame.new(x, y + 2.5 + H, z), TRIM, Mat.Slate)
			local bowl = cylinder(t, "ObeliskBowl", 1.2, 3.6, CFrame.new(x, y + 3.6 + H, z), SPIRE_METAL, Mat.Metal)
			local fire = Instance.new("Fire")
			fire.Size = 6
			fire.Heat = 10
			fire.Color = RGB(70, 120, 255)
			fire.SecondaryColor = RGB(170, 210, 255)
			fire.Parent = bowl
			local light = Instance.new("PointLight")
			light.Range = 22
			light.Brightness = 1.8
			light.Color = SPIRE_GLOW
			light.Parent = bowl
			discZ(t, "ObeliskRune", 0.3, 1.6, CFrame.new(x, y + 2 + H * 0.6, z + 1.35), SPIRE_GLOW, Mat.Neon)
		end
	end

	-- glowing rune stones leading to the doors (the glow runs towards the gate)
	local nRunes = 0
	for z = FZ + 32, FZ + 12, -2.5 do
		nRunes = nRunes + 1
		local stone = part(t, "RuneStone", V3(1.8, 0.12, 1.8), CFrame.new(0, y + 0.47, z) * CFrame.Angles(0, math.pi / 4, 0), SPIRE_GLOW, Mat.Neon, { CanCollide = false, CanQuery = false })
		pulse(stone, 0.6, 0, 0.7)
		stone:SetAttribute("Phase", nRunes * 40)
	end
	for s = 1, 2 do
		local stone = part(t, "RuneStone", V3(1.8, 0.12, 1.8), CFrame.new(0, y + PLAT_H - s * PLAT_H / 3 + 0.07, FZ + 10 + s * 2 - 1) * CFrame.Angles(0, math.pi / 4, 0), SPIRE_GLOW, Mat.Neon, { CanCollide = false, CanQuery = false })
		pulse(stone, 0.6, 0, 0.7)
		stone:SetAttribute("Phase", (nRunes + s) * 40)
	end

	-- low mist rolling out of the doorway
	local gateMist = anchorPart(t, "GateMist", CFrame.new(0, gy + 1, DZ + 3))
	gateMist.Size = V3(14, 1, 4)
	local gm = Instance.new("ParticleEmitter")
	gm.Rate = 5
	gm.Color = ColorSequence.new(RGB(150, 130, 210), RGB(90, 110, 200))
	gm.LightEmission = 0.4
	gm.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 8) })
	gm.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.7), NumberSequenceKeypoint.new(1, 1) })
	gm.Lifetime = NumberRange.new(4, 6)
	gm.Speed = NumberRange.new(2, 4)
	gm.EmissionDirection = Enum.NormalId.Front
	gm.SpreadAngle = Vector2.new(30, 5)
	gm.Parent = gateMist

	-- the prompt that opens the Spire menu, and where you come back to
	local entrance = anchorPart(t, "SpireEntrance", CFrame.new(0, gy + 5, DZ + 3))
	local enterPrompt = Instance.new("ProximityPrompt")
	enterPrompt.ActionText = "Enter"
	enterPrompt.ObjectText = "The Spire"
	enterPrompt.HoldDuration = 0
	enterPrompt.MaxActivationDistance = 16
	enterPrompt.KeyboardKeyCode = Enum.KeyCode.E
	enterPrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	enterPrompt.RequiresLineOfSight = false
	enterPrompt.Parent = entrance
	CollectionService:AddTag(enterPrompt, "SpireEntrance")
	-- the whole approach counts: from the doors, over the platform and down the
	-- steps to the first obelisks
	autoZone(t, CFrame.new(0, y + 6, (DZ + FZ + 21) / 2), V3(30, 16, (FZ + 21) - DZ), "Spire", "Menu")
	-- (just outside the menu zone, so the menu doesn't pop straight back up when you return)
	local back = anchorPart(t, "SpireReturn", CFrame.lookAt(V3(0, y + 3, FZ + 25), V3(0, y + 3, FZ + 40)))
	CollectionService:AddTag(back, "SpireReturn")

	-- the same kind of marker the shops have: a bobbing arrow pointing at the
	-- doors, a sign, and a glowing mat to stand on
	local arrowColor = RGB(120, 190, 255)
	local ashaft = part(t, "ArrowShaft", V3(2.2, 5, 1.6), CFrame.new(0, gy + 26, DZ + 4), arrowColor, Mat.Neon, { CanCollide = false })
	local ahead = part(t, "ArrowHead", V3(4.6, 4.6, 1.6), CFrame.new(0, gy + 22, DZ + 4) * CFrame.Angles(0, 0, math.rad(45)), arrowColor, Mat.Neon, { CanCollide = false })
	fx(ashaft, { SpinSpeed = 40, BobAmp = 0.8, BobSpeed = 2 })
	fx(ahead, { SpinSpeed = 40, BobAmp = 0.8, BobSpeed = 2 })
	titleSign(t, CFrame.new(0, gy + 33, DZ + 5), "THE SPIRE", "Enter to face its bosses", RGB(150, 190, 255), 340, 110)
	part(t, "Mat", V3(12, 0.3, 5), CFrame.new(0, gy + 0.15, DZ + 4), RGB(90, 170, 255), Mat.Neon, { Transparency = 0.35, CanCollide = false })

	-- Glowing mushrooms in little clusters
	local function mushrooms(pos, count, s)
		for _ = 1, count do
			local p = pos + V3((rnd() - 0.5) * 3 * s, 0, (rnd() - 0.5) * 3 * s)
			local h = (0.8 + rnd() * 1.6) * s
			local lean = CFrame.Angles((rnd() - 0.5) * 0.5, 0, (rnd() - 0.5) * 0.5)
			local base = CFrame.new(p) * lean
			part(t, "ShroomStem", V3(0.35 * s, h, 0.35 * s), base * CFrame.new(0, h / 2, 0), RGB(200, 190, 210), Mat.SmoothPlastic, noCol)
			local d = (1 + rnd() * 1.4) * s
			local cap = cylinder(t, "ShroomCap", 0.45 * s, d, base * CFrame.new(0, h + 0.1, 0), SHROOM[1 + math.floor(rnd() * 3)], Mat.Neon, { CanCollide = false, CanQuery = false, CastShadow = false, Transparency = 0.15 })
			pulse(cap, 0.35 + rnd() * 0.3, 0.05, 0.5)
		end
	end

	-- Roots: thick dark roots climbing out of the rock and up the walls
	local function root(a0, sway, topH, thick)
		local N = 10
		local prev
		for j = 0, N do
			local f = j / N
			local h = y - 1 + f * topH
			local a = a0 + sway * f + 0.18 * math.sin(f * 9 + a0 * 3)
			local th = thick * (1 - 0.7 * f)
			local r = (j == 0) and 47 or wallApAt(h) + th * 0.35
			local p = V3(math.sin(a) * r, h, SPIRE_Z + math.cos(a) * r)
			if prev then
				part(t, "Root", V3(th, th, (p - prev).Magnitude + th * 0.3), CFrame.lookAt((p + prev) / 2, p), BARK, Mat.Wood, { CastShadow = false })
			end
			ball(t, "RootKnot", th * 1.12, CFrame.new(p), BARK, Mat.Wood, { CastShadow = false })
			if j > 1 and j < N and j % 2 == 0 then
				local out = V3(math.sin(a), 0, math.cos(a))
				thorn(p, (out + V3(0, 0.6, 0)).Unit, th * 2, th * 0.4, BARK)
				if rnd() < 0.4 then
					leafClump(p + out * th * 0.6, th * 1.4)
				end
			end
			if j == 2 and rnd() < 0.8 then
				mushrooms(p + V3(0, th * 0.5, 0), 3, 0.9)
			end
			prev = p
		end
	end
	local rootAngles = { 0.45, -0.45, 0.95, -0.95, 1.5, -1.5, 2.1, -2.1, 2.7, -2.7, 3.14 }
	for i, a in ipairs(rootAngles) do
		local frontSide = math.abs(a) < 1
		root(a + (rnd() - 0.5) * 0.15, (a > 0 and 1 or -1) * (frontSide and 0.35 or 0.7), frontSide and 42 or (55 + (i % 3) * 26), 4.2 + (i % 2) * 1.4)
	end

	-- Ivy curtains draped down the walls from every ledge
	local function curtain(a, topY, ap, w, h)
		local dir = V3(math.sin(a), 0, math.cos(a))
		local p = V3(0, topY - h / 2, SPIRE_Z) + dir * (ap + 0.35)
		local cf = CFrame.lookAt(p, p + dir)
		local col = LEAF[1 + math.floor(rnd() * 3)]
		part(t, "Ivy", V3(w, h, 0.6), cf, col, Mat.LeafyGrass, noCol)
		-- ragged bottom edge
		for _, j in ipairs({ -1, 1 }) do
			local dh = 2 + rnd() * 5
			part(t, "IvyFringe", V3(w * 0.4, dh, 0.55), cf * CFrame.new(j * w * (0.2 + rnd() * 0.1), -h / 2 - dh / 2 + 0.4, 0.05), col, Mat.LeafyGrass, noCol)
		end
	end
	for i, ti in ipairs(tierInfo) do
		local topY = ti.y0 + ti.h
		for n = 0, 9 do
			local a = (n + rnd() * 0.8) / 10 * math.pi * 2
			local h = 7 + rnd() * (ti.h * 0.55)
			if not blocksGate(a, topY - h) then
				curtain(a, topY, ti.ap, 4 + rnd() * 5, h)
			end
		end
	end
	-- and down the cliffs of the rock (seen from the bridge)
	for n = 0, 13 do
		local a = (n + rnd() * 0.6) / 14 * math.pi * 2
		if math.cos(a) < 0.93 then
			local dir = V3(math.sin(a), 0, math.cos(a))
			local p = V3(0, B - 8, SPIRE_Z) + dir * (SPIRE_ROCK_R + 2.2)
			part(t, "CliffIvy", V3(7 + rnd() * 6, 16 + rnd() * 10, 0.8), CFrame.lookAt(p, p + dir), LEAF[1 + math.floor(rnd() * 3)], Mat.LeafyGrass, noCol)
		end
	end

	-- Thorny vines winding up each tier, with leaf clumps
	for i, ti in ipairs(tierInfo) do
		for _ = 1, (i <= 2) and 3 or 2 do
			local a0 = rnd() * math.pi * 2
			local turn = (rnd() < 0.5 and 1 or -1) * (1 + rnd() * 0.8)
			local N = 12
			local prev
			for j = 0, N do
				local f = j / N
				local a = a0 + turn * f
				local h = ti.y0 + 1 + f * (ti.h - 1) + math.sin(f * 11) * 1.2
				local out = V3(math.sin(a), 0, math.cos(a))
				local p = V3(0, h, SPIRE_Z) + out * (ti.ap + 0.5)
				if prev and not blocksGate(a, h) then
					part(t, "Vine", V3(0.8, 0.8, (p - prev).Magnitude + 0.3), CFrame.lookAt((p + prev) / 2, p), VINE, Mat.Wood, noCol)
					if j % 3 == 0 then
						leafClump(p + out * 0.6, 1.8 + rnd() * 1.2)
					elseif j % 4 == 1 then
						thorn(p, (out + V3(0, 0.4, 0)).Unit, 1.4, 0.3, VINE)
					end
				end
				prev = p
			end
		end
	end

	-- Moss: patches on the walls, thick along the battlement tops
	for i, ti in ipairs(tierInfo) do
		for _ = 1, 14 - i * 2 do
			local k = math.floor(rnd() * 12)
			local dir = faceDir(k + (rnd() - 0.5) * 0.6)
			local a = math.atan2(dir.X, dir.Z)
			local h = ti.y0 + rnd() * ti.h
			if not blocksGate(a, h) then
				local p = V3(0, h, SPIRE_Z) + dir * (ti.ap + 0.15)
				part(t, "Moss", V3(4 + rnd() * 7, 3 + rnd() * 6, 0.5), CFrame.lookAt(p, p + dir) * CFrame.Angles(0, 0, rnd()), MOSS[1 + math.floor(rnd() * 3)], Mat.LeafyGrass, noCol)
			end
		end
		if i < #tierInfo then
			local topY = ti.y0 + ti.h + 3
			for n = 0, 11 do
				local a = (n + rnd() * 0.5) / 12 * math.pi * 2
				local dir = V3(math.sin(a), 0, math.cos(a))
				local p = V3(0, topY + 0.3, SPIRE_Z) + dir * (ti.ap + 1.2)
				part(t, "LedgeMoss", V3(4 + rnd() * 4, 0.8, 3 + rnd() * 1.5), CFrame.lookAt(p, p + dir), MOSS[1 + math.floor(rnd() * 3)], Mat.LeafyGrass, noCol)
				if n % 2 == 0 then
					leafClump(p + V3(0, 1.4, 0) + dir * 1.2, 3 + rnd() * 3)
				end
				if rnd() < 0.3 then
					mushrooms(p + V3(0, 0.4, 0), 2, 0.8)
				end
			end
		end
	end

	-- Vines hanging from the battlements, some with glowing seed pods
	for i, ti in ipairs(tierInfo) do
		if i < #tierInfo then
			for n = 1, 8 do
				local a = (n + rnd() * 0.6) / 8 * math.pi * 2 + i
				local out = V3(math.sin(a), 0, math.cos(a))
				local top = V3(0, ti.y0 + ti.h - 0.6, SPIRE_Z) + out * (ti.ap + 2.8)
				local len = 8 + rnd() * 14
				if not blocksGate(a, top.Y - len) then
					local prev = top
					for j = 1, 4 do
						local p = top + V3(math.sin(j * 1.7 + n) * 0.6, -len * j / 4, 0) + out * (0.25 * j)
						part(t, "HangingVine", V3(0.45, 0.45, (p - prev).Magnitude + 0.2), CFrame.lookAt((p + prev) / 2, p), VINE, Mat.Wood, noCol)
						if j % 2 == 1 then
							leafClump(p + out * 0.3, 1.3 + rnd())
						end
						prev = p
					end
					if rnd() < 0.55 then
						local pod = ball(t, "SeedPod", 1.1, CFrame.new(prev), POD, Mat.Neon, { CanCollide = false, CastShadow = false })
						pulse(pod, 0.5, 0.05, 0.5)
					end
				end
			end
		end
	end

	-- Gnarled dead trees growing out of the ledges and the rock
	local function evilTree(base, out, s)
		local up = V3(0, 1, 0)
		local p = base
		local dir = (out * 0.8 + up * 0.6).Unit
		local th = 1.9 * s
		for j = 1, 6 do
			local len = (3.4 - j * 0.2) * s
			dir = (dir + up * 0.35 + V3((rnd() - 0.5) * 0.5, 0, (rnd() - 0.5) * 0.5)).Unit
			local p2 = p + dir * len
			part(t, "TreeTrunk", V3(th, th, len + th * 0.7), CFrame.lookAt((p + p2) / 2, p2), BARK, Mat.Wood, { CastShadow = false })
			if j >= 3 then
				local side = V3(-dir.Z, 0, dir.X) * ((j % 2 == 0) and 1 or -1)
				local bd = (side + dir * 0.6 + up * 0.3).Unit
				local bp = p2
				local bth = th * 0.55
				for b = 1, 2 do
					local bl = (2.6 - b * 0.5) * s
					bd = (bd + up * 0.25 + V3((rnd() - 0.5) * 0.6, 0, (rnd() - 0.5) * 0.6)).Unit
					local bp2 = bp + bd * bl
					part(t, "TreeBranch", V3(bth, bth, bl + 0.2), CFrame.lookAt((bp + bp2) / 2, bp2), BARK, Mat.Wood, noCol)
					bp = bp2
					bth = bth * 0.7
				end
				thorn(bp, bd, 1.5 * s, bth, BARK)
				if rnd() < 0.65 then
					leafClump(bp, (2.2 + rnd() * 2) * s)
				end
			end
			p = p2
			th = th * 0.82
		end
		thorn(p, dir, 2 * s, th, BARK)
		leafClump(p, 2.6 * s)
	end
	for i, ti in ipairs(tierInfo) do
		if i < #tierInfo then
			for n = 0, 3 do
				local a = (n + rnd() * 0.8) / 4 * math.pi * 2
				if math.cos(a) < 0.9 then
					local out = V3(math.sin(a), 0, math.cos(a))
					evilTree(V3(0, ti.y0 + ti.h + 3, SPIRE_Z) + out * (ti.ap + 1), out, 1.1 - i * 0.12)
				end
			end
		end
	end
	for _, a in ipairs({ 0.75, -0.75, 1.5, -1.5, 2.3, -2.3, 3.0 }) do
		local out = V3(math.sin(a), 0, math.cos(a))
		evilTree(V3(0, y, SPIRE_Z) + out * (math.abs(a) < 1 and 40 or 50), out, math.abs(a) < 1 and 1.5 or 1.9)
	end
	-- a small tree clinging to each gate tower
	for _, sx in ipairs({ -1, 1 }) do
		evilTree(V3(sx * (FACADE_HALF + 12.5), y + 36, FZ - 6), V3(sx, 0, 0.3).Unit, 0.8)
	end

	-- Brambles and mushrooms choking the foot of the tower
	for n = 0, 21 do
		local a = (n + rnd() * 0.7) / 22 * math.pi * 2
		if math.abs(math.sin(a)) > 0.3 or math.cos(a) < 0 then -- not on the path to the gate
			local out = V3(math.sin(a), 0, math.cos(a))
			local p = V3(0, y + 0.8, SPIRE_Z) + out * (44 + rnd() * 12)
			for _ = 1, 3 do
				ball(t, "Bramble", 2.6 + rnd() * 2.4, CFrame.new(p + V3((rnd() - 0.5) * 3.5, rnd() * 1.4, (rnd() - 0.5) * 3.5)), LEAF[1 + math.floor(rnd() * 3)], Mat.LeafyGrass, noCol)
			end
			for _ = 1, 3 do
				local d = (V3(rnd() - 0.5, 0.5 + rnd() * 0.5, rnd() - 0.5)).Unit
				thorn(p + V3(0, 1, 0), d, 2.6, 0.3, BARK)
			end
			if rnd() < 0.7 then
				mushrooms(V3(p.X, y + 0.1, p.Z) + out * 2.5, 3, 1.1)
			end
		end
	end
	-- vines and mushrooms round the entrance
	for _, sx in ipairs({ -1, 1 }) do
		mushrooms(V3(sx * 29, y + 0.1, FZ + 14), 5, 1.2)
		mushrooms(V3(sx * 19, y + 0.1, FZ + 19), 3, 0.9)
		local p = V3(sx * (FACADE_HALF + 9.6), y + 48, FZ + 1.3) -- outer half of the tower, clear of its windows
		part(t, "GateIvy", V3(4.6, 30, 0.6), CFrame.lookAt(p, p + V3(0, 0, 1)), LEAF[1 + math.floor(rnd() * 3)], Mat.LeafyGrass, noCol)
		for j = 0, 2 do
			leafClump(V3(sx * (12 + j * 2.5), gy + FACADE_H + 1 + rnd() * 2, FZ + 0.5), 3 + rnd() * 2)
		end
	end
	-- the growth creeps onto the end of the bridge
	for _, sx in ipairs({ -1, 1 }) do
		for j = 0, 3 do
			local z = SPIRE_Z + SPIRE_ROCK_R - 2 + j * 5
			leafClump(V3(sx * (STAIR_HALF_W + 1), B + 3.5 + rnd(), z), 2.4 + rnd() * 1.6)
			if j < 2 then
				mushrooms(V3(sx * (STAIR_HALF_W - 1.5), B + 0.05, z + 1), 2, 0.8)
			end
		end
	end

	-- Spores drifting in the air round the tower
	local spores = anchorPart(t, "Spores", CFrame.new(0, y + 60, SPIRE_Z))
	spores.Size = V3(80, 120, 80)
	local se = Instance.new("ParticleEmitter")
	se.Rate = 14
	se.Color = ColorSequence.new(RGB(190, 130, 255), RGB(110, 230, 210))
	se.LightEmission = 1
	se.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.1) })
	se.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.2), NumberSequenceKeypoint.new(1, 1) })
	se.Lifetime = NumberRange.new(6, 10)
	se.Speed = NumberRange.new(0.5, 1.5)
	se.SpreadAngle = Vector2.new(180, 180)
	se.Shape = Enum.ParticleEmitterShape.Box
	se.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	se.Parent = spores

	-- Broken rocks drifting round the crown
	for n = 0, 7 do
		local ry = cy + 6 + rnd() * 16
		local rock = part(t, "DriftRock", V3(2 + rnd() * 3, 2 + rnd() * 3, 2 + rnd() * 3), CFrame.new(0, ry, SPIRE_Z) * CFrame.Angles(rnd() * 3, rnd() * 3, rnd() * 3), ROCK2, Mat.Slate, { CanCollide = false })
		fx(rock, {
			OrbitRadius = 24 + rnd() * 10,
			OrbitSpeed = (n % 2 == 0) and 8 or -6,
			OrbitCenter = V3(0, ry, SPIRE_Z),
			Phase = n * 45,
			BobAmp = 1.5,
			BobSpeed = 0.6 + rnd() * 0.4,
			SpinSpeed = 20,
		})
	end


	-- a slow purple mist drifting round the foot of the tower
	local mist = anchorPart(m, "Mist", CFrame.new(0, B + 3, SPIRE_Z))
	mist.Size = V3(100, 1, 100)
	local e = Instance.new("ParticleEmitter")
	e.Rate = 6
	e.Color = ColorSequence.new(RGB(150, 120, 200), RGB(90, 80, 150))
	e.LightEmission = 0.3
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 12) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.75), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(6, 9)
	e.Speed = NumberRange.new(0.5, 1.5)
	e.SpreadAngle = Vector2.new(180, 10)
	e.Parent = mist
end

----------------------------------------------------------------------
-- Rock under the castle and the Spire
----------------------------------------------------------------------
-- The castle sits on top of a mountain: rocky cliffs drop away beneath the
-- walls (and beneath the Spire's crag across the chasm), getting wider as
-- they go down, until they vanish into layers of mist.
local SEA_Y = -20 -- the surface of the sea round the castle's island
local ISLAND_FLOOR = SEA_Y - 20 -- the sea floor: rock is only built down to here
local ROCK_TOP = { RGB(112, 104, 100), RGB(98, 94, 96), RGB(124, 116, 110) }
local ROCK_DEEP = { RGB(96, 102, 116), RGB(86, 92, 106), RGB(106, 112, 126) }

local function rockColor(depth01)
	local i = 1 + math.floor(rnd() * 3)
	return ROCK_TOP[i]:Lerp(ROCK_DEEP[i], math.clamp(depth01, 0, 1))
end

-- A craggy cliff block, tilted a little
local function crag(parent, pos, size, yaw, color)
	local cf = CFrame.new(pos) * CFrame.Angles(math.rad((rnd() - 0.5) * 14), yaw, math.rad((rnd() - 0.5) * 14))
	part(parent, "Cliff", size, cf, color, Mat.Slate, { CastShadow = false })
end

local LAYER_H = 24

-- A round mountain under a round top (the Spire's crag)
local function roundMountain(parent, cx, cz, radius, topY, spread)
	local layers = math.ceil((topY - ISLAND_FLOOR) / LAYER_H) + 1
	for L = 0, layers - 1 do
		local y1 = topY - L * LAYER_H
		local r = radius + spread * L ^ 1.3
		local depth01 = L / (layers - 1)
		cylinder(parent, "MountainCore", LAYER_H + 4, r * 2, CFrame.new(cx, y1 - LAYER_H / 2, cz), rockColor(depth01), Mat.Slate, { CastShadow = false })
		local n = math.max(10, math.floor(2 * math.pi * r / 20))
		for i = 0, n - 1 do
			local a = (i + rnd() * 0.5) / n * math.pi * 2
			local dir = V3(math.sin(a), 0, math.cos(a))
			local h = LAYER_H + 4 + rnd() * 12
			crag(parent, V3(cx, y1 - h / 2 + rnd() * 3, cz) + dir * (r + rnd() * 4 - 1), V3(16 + rnd() * 10, h, 7 + rnd() * 8), a, rockColor(depth01))
		end
	end
end

-- Big hard boulders piled against the outside foot of the castle walls, so
-- the walls grow out of the rock instead of sitting on a green ledge.
local WALL_OUTER = 121 -- outside face of the boundary walls
local function wallFootRocks(parent)
	local function boulder(pos, size, yaw)
		-- (reach all the way down into the grass below, so no rock hangs in the air)
		local top = pos.Y + size.Y / 2
		local bottom = -15.5
		pos = V3(pos.X, (top + bottom) / 2, pos.Z)
		size = V3(size.X, top - bottom, size.Z)
		local cf = CFrame.new(pos) * CFrame.Angles(math.rad((rnd() - 0.5) * 8), yaw, math.rad((rnd() - 0.5) * 8))
		part(parent, "WallRock", size, cf, rockColor(rnd() * 0.25), Mat.Slate, { CastShadow = false })
		if rnd() < 0.25 then
			part(parent, "WallRockMoss", V3(size.X * 0.7, 0.6, size.Z * 0.7), cf * CFrame.new(0, size.Y / 2, 0), RGB(96, 150, 74), Mat.LeafyGrass, { CanCollide = false, CastShadow = false })
		end
	end
	-- a row along each side of the square
	for side = 0, 3 do
		local alongX = side % 2 == 0
		local out = (side < 2) and 1 or -1
		local isNorth = alongX and out < 0
		local isSouth = alongX and out > 0
		local shift = isSouth and SOUTH_EXT or 0 -- (the south wall sits further out)
		local t = -WALL_OUTER - 4
		local tEnd = alongX and (WALL_OUTER + 4) or (WALL_OUTER + SOUTH_EXT + 4)
		while t < tEnd do
			local w = 9 + rnd() * 7
			local skip = (isNorth and math.abs(t) < 17) -- the stairs' abutment goes out here
				or (isSouth and math.abs(t) < 40) -- the south gatehouse and drawbridge
			if not skip then
				local h = 8 + rnd() * 7
				local d = 6 + rnd() * 5
				local o = WALL_OUTER + d * 0.35 + rnd() * 2
				local y = -2 + rnd() * 3
				local pos = alongX and V3(t, y, out * o + shift) or V3(out * o, y, t)
				boulder(pos, alongX and V3(w, h, d) or V3(d, h, w), (rnd() - 0.5) * 0.6)
				-- a smaller rock tumbled in front of every other one
				if rnd() < 0.55 then
					local s2 = 3.5 + rnd() * 3.5
					local o2 = o + d * 0.5 + rnd() * 1.5
					local pos2 = alongX and V3(t + (rnd() - 0.5) * w * 0.6, -3 + rnd() * 2, out * o2 + shift) or V3(out * o2, -3 + rnd() * 2, t + (rnd() - 0.5) * w * 0.6)
					boulder(pos2, V3(s2 * 1.3, s2, s2), rnd() * math.pi)
				end
			end
			t = t + w * 0.7
		end
	end
	-- round the outside half of the two gate towers
	for _, tx in ipairs({ -32, 32 }) do
		for i = 0, 9 do
			local a = math.pi * 1.15 + (i + 0.5) / 10 * math.pi * 0.7 -- the side facing away from the lobby
			local dir = V3(math.cos(a), 0, math.sin(a))
			local h = 7 + rnd() * 6
			boulder(V3(tx, -2 + rnd() * 2.5, -118) + dir * (12.5 + rnd() * 2), V3(8 + rnd() * 5, h, 6 + rnd() * 4), -a + math.pi / 2)
		end
	end
end

----------------------------------------------------------------------
-- The castle rebuild: Grand Keep, turrets, south gatehouse,
-- the paved landing and stairs outside the south gate
----------------------------------------------------------------------
-- Gives the castle the storybook personality of the reference pictures:
-- red cone roofs on every tower, a Grand Keep rising over the Spire gate,
-- little turrets hanging off the outside of the walls, and a gatehouse on
-- the south side, opening onto cosy stairs down to the island.
local KEEP_STONE = RGB(150, 146, 160)
local KEEP_DARK = RGB(104, 100, 116)
local WATER = RGB(64, 136, 214)

-- just outside the south wall: the castle's rock ends here, and the paved
-- landing in front of the south gate reaches out to GATE_LANDING_Z
local CASTLE_ROCK_S = SOUTH_WALL + 12
local GATE_LANDING_Z = SOUTH_WALL + 16
local TERRACE1_TOP = -14 -- the first green terrace below the castle (see the island)

-- A Grand Keep built up over the Spire gate: the gate towers grow a second,
-- narrower storey with tall cone roofs, and a great hall with a steep red
-- roof and a glowing rose window bridges between them over the archway.
-- (Later its hall becomes the Auction House.)
local function buildKeep(parent)
	local m = folder(parent, "GrandKeep")
	local zc = (GATE_Z0 + GATE_Z1) / 2
	local base = GATE_H + 8 + 3 -- the top of the gate towers' parapets
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (GATE_HALF_W + 10)
		local h = 24
		cylinder(m, "KeepTowerUpper", h, 18, CFrame.new(x, base + h / 2, zc), KEEP_STONE, Mat.Cobblestone)
		cylinder(m, "KeepTowerBand", 1.2, 19.4, CFrame.new(x, base + h * 0.55, zc), KEEP_DARK, Mat.Cobblestone)
		-- windows looking over the lobby, glowing warm at night
		for _, a in ipairs({ -0.5, 0, 0.5 }) do
			local dir = V3(math.sin(a), 0, math.cos(a))
			local p = V3(x, base + 12, zc) + dir * 9
			part(m, "KeepWindow", V3(1.6, 4, 0.4), CFrame.lookAt(p, p + dir), RGB(255, 200, 110), Mat.Neon)
		end
		coneRoof(m, V3(x, base + h, zc), 11.5, 34, ROOF_RED, 14)
		cylinder(m, "FlagPole", 8, 0.5, CFrame.new(x, base + h + 38, zc), RGB(70, 60, 50), Mat.Wood)
		part(m, "Flag", V3(0.3, 3.4, 6), CFrame.new(x, base + h + 40.5, zc + 3.1), sx < 0 and BANNER_RED or BANNER_BLUE, Mat.Fabric)
	end
	-- the great hall between the towers, sitting on top of the gate
	local hallY0, hallH = GATE_H + 6, 20
	local halfW = GATE_HALF_W - 1
	part(m, "Hall", V3(halfW * 2, hallH, GATE_Z1 - GATE_Z0), CFrame.new(0, hallY0 + hallH / 2, zc), KEEP_STONE, Mat.Cobblestone)
	part(m, "HallBand", V3(halfW * 2 + 0.6, 1, GATE_Z1 - GATE_Z0 + 0.6), CFrame.new(0, hallY0 + hallH, zc), KEEP_DARK, Mat.Cobblestone)
	-- steep red roof, ridge running east-west
	local roofH, run = 18, (GATE_Z1 - GATE_Z0) / 2 + 1
	for _, s in ipairs({ -1, 1 }) do
		local w = Instance.new("WedgePart")
		w.Name = "HallRoof"
		w.Anchored = true
		w.Size = V3(halfW * 2 + 2, roofH, run)
		w.CFrame = CFrame.fromMatrix(V3(0, hallY0 + hallH + roofH / 2, zc + s * run / 2), V3(-s, 0, 0), V3(0, 1, 0), V3(0, 0, -s))
		w.Color = ROOF_RED
		w.Material = Mat.SmoothPlastic
		w.TopSurface = Enum.SurfaceType.Smooth
		w.BottomSurface = Enum.SurfaceType.Smooth
		w.Parent = m
	end
	-- a little spire on the ridge, and the rose window facing the lobby
	coneRoof(m, V3(0, hallY0 + hallH + roofH - 4, zc), 3, 16, ROOF_RED, 8)
	local face = GATE_Z1 + 0.25
	discZ(m, "RoseRing", 0.5, 11, CFrame.new(0, hallY0 + 10, face), KEEP_DARK, Mat.Cobblestone)
	discZ(m, "RoseWindow", 0.6, 8.6, CFrame.new(0, hallY0 + 10, face), RGB(90, 170, 255), Mat.Neon)
	for i = 0, 3 do
		part(m, "RoseSpoke", V3(0.5, 8.6, 0.7), CFrame.new(0, hallY0 + 10, face) * CFrame.Angles(0, 0, i * math.pi / 4), KEEP_DARK, Mat.Cobblestone)
	end
	for _, sx in ipairs({ -1, 1 }) do
		part(m, "HallWindow", V3(2, 6, 0.5), CFrame.new(sx * 13, hallY0 + 9, face), RGB(255, 200, 110), Mat.Neon)
		banner(m, V3(sx * 7, hallY0 + 4, face + 0.1), V3(0, 0, 1), sx < 0 and BANNER_RED or BANNER_BLUE)
	end
end

-- A little turret hanging off the outside of a wall, on stepped corbels,
-- with its own cone roof. `out` points away from the castle.
local function bartizan(parent, pos, out)
	local m = Instance.new("Model")
	m.Name = "Turret"
	m.Parent = parent
	local c = pos + out * 5
	for i = 0, 3 do
		cylinder(m, "Corbel" .. i, 1.6, 3 + i * 2.2, CFrame.new(c + V3(0, 26 + i * 1.6, 0)), STONE_DARK, Mat.Cobblestone)
	end
	cylinder(m, "Body", 16, 10, CFrame.new(c + V3(0, 40, 0)), STONE, Mat.Cobblestone)
	cylinder(m, "Ledge", 1.2, 11.4, CFrame.new(c + V3(0, 48.6, 0)), STONE_DARK, Mat.Cobblestone)
	part(m, "Slit", V3(1, 4, 0.5), CFrame.lookAt(c + V3(0, 40, 0) + out * 5, c + V3(0, 40, 0) + out * 6), RGB(28, 28, 36), Mat.SmoothPlastic)
	coneRoof(m, c + V3(0, 49.2, 0), 6.5, 15, ROOF_RED, 9)
end

-- The south gatehouse: a round arch in the south wall between two big
-- round towers with cone roofs and the portcullis pulled up.
local function buildSouthGate(parent)
	local m = folder(parent, "SouthGate")
	local z = SOUTH_WALL
	local depth = 10
	local H = WALL_HEIGHT + 4
	local SPRING, R = 16, 12 -- the arch: straight sides up to SPRING, then a half circle
	local function archTop(x)
		if math.abs(x) >= R then
			return nil
		end
		return SPRING + math.sqrt(R * R - x * x)
	end
	-- the piers either side of the arch
	for _, sx in ipairs({ -1, 1 }) do
		local w = SOUTH_GATE_HALF - R
		part(m, "GatePier", V3(w + 0.2, H, depth), CFrame.new(sx * (R + w / 2), H / 2, z), STONE, Mat.Cobblestone)
	end
	-- stone above the arch, in thin slices that follow the curve
	for x0 = -R, R - 1 do
		local bottom = math.min(archTop(x0 + 0.001) or SPRING, archTop(x0 + 0.999) or SPRING)
		part(m, "GateArchFill", V3(1.02, H - bottom, depth), CFrame.new(x0 + 0.5, (H + bottom) / 2, z), STONE, Mat.Cobblestone)
	end
	-- the arch ring on both faces
	for _, face in ipairs({ z - depth / 2 - 0.3, z + depth / 2 + 0.3 }) do
		for k = 0, 11 do
			local a0, a1 = k / 12 * math.pi, (k + 1) / 12 * math.pi
			local p0 = V3(math.cos(a0) * (R + 1), SPRING + math.sin(a0) * (R + 1), face)
			local p1 = V3(math.cos(a1) * (R + 1), SPRING + math.sin(a1) * (R + 1), face)
			local mid = (p0 + p1) / 2
			part(m, "Voussoir", V3(2.2, 1.4, (p1 - p0).Magnitude + 0.3), CFrame.lookAt(mid, mid + (p1 - p0).Unit, V3(0, 0, 1)), STONE_DARK, Mat.Cobblestone)
		end
		for _, sx in ipairs({ -1, 1 }) do
			part(m, "Jamb", V3(2, SPRING, 1.2), CFrame.new(sx * (R + 1), SPRING / 2, face), STONE_DARK, Mat.Cobblestone)
		end
		-- merlons along the top
		for x = -SOUTH_GATE_HALF + 2, SOUTH_GATE_HALF - 2, 5 do
			part(m, "Merlon", V3(3, 3.4, 2), CFrame.new(x, H + 1.7, face), STONE_DARK, Mat.Cobblestone)
		end
	end
	-- the portcullis, raised: only its spiked bottom shows
	local PB = SPRING + 5
	for x = -10, 10, 2 do
		local top = archTop(x)
		if top and top > PB + 1 then
			part(m, "PortcullisBar", V3(0.7, top - PB + 1, 0.7), CFrame.new(x, (top + 1 + PB) / 2, z), GATE_IRON, Mat.Metal)
			part(m, "PortcullisSpike", V3(0.5, 1.4, 0.5), CFrame.new(x, PB - 0.6, z), GATE_IRON, Mat.Metal)
		end
	end
	part(m, "PortcullisRail", V3(R * 2 - 2, 0.6, 0.6), CFrame.new(0, PB + 0.5, z), GATE_IRON, Mat.Metal)
	-- a shield over the arch on the outside
	discZ(m, "Crest", 0.6, 7, CFrame.new(0, SPRING + R + 6, z + depth / 2 + 0.4), BANNER_RED, Mat.SmoothPlastic)
	discZ(m, "CrestStar", 0.7, 3, CFrame.new(0, SPRING + R + 6, z + depth / 2 + 0.5), GOLD, Mat.Metal)

	-- the two big towers
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (SOUTH_GATE_HALF + 10)
		local TH = WALL_HEIGHT + 16
		cylinder(m, "GateTower", TH + 8, 20, CFrame.new(x, TH / 2 - 4, z), STONE, Mat.Cobblestone)
		cylinder(m, "GateTowerPlinth", 12, 23, CFrame.new(x, -2, z), STONE_DARK, Mat.Cobblestone)
		cylinder(m, "GateTowerBand", 1.4, 21.4, CFrame.new(x, TH * 0.6, z), STONE_DARK, Mat.Cobblestone)
		cylinder(m, "GateTowerLedge", 2, 23, CFrame.new(x, TH + 1, z), STONE_DARK, Mat.Cobblestone)
		for i = 0, 9 do
			local a = i / 10 * math.pi * 2
			part(m, "Merlon", V3(3.2, 4, 3.2), CFrame.new(x + math.cos(a) * 10, TH + 4, z + math.sin(a) * 10) * CFrame.Angles(0, -a, 0), STONE_DARK, Mat.Cobblestone)
		end
		coneRoof(m, V3(x, TH + 2.5, z), 12.5, 32, ROOF_RED, 14)
		cylinder(m, "FlagPole", 8, 0.5, CFrame.new(x, TH + 38, z), RGB(70, 60, 50), Mat.Wood)
		part(m, "Flag", V3(0.3, 3, 5), CFrame.new(x, TH + 40.5, z + 2.6), sx < 0 and BANNER_BLUE or BANNER_RED, Mat.Fabric)
		-- torches and banners on both faces, beside the arch
		wallTorch(m, V3(sx * 14.5, 12, z + depth / 2), V3(0, 0, 1))
		wallTorch(m, V3(sx * 14.5, 12, z - depth / 2), V3(0, 0, -1))
		banner(m, V3(x, 30, z + 10.1), V3(0, 0, 1), sx < 0 and BANNER_BLUE or BANNER_RED)
	end
	titleSign(m, CFrame.new(0, SPRING + R + 13, z + depth / 2 + 1), "Beach", nil, RGB(120, 200, 255), 300, 90)
end


-- The Grand Keep's main building, south of the Spire gate: two tall stone
-- wings with a wide vaulted passage between them (the walk to the Spire),
-- two big front towers with cone roofs, and one long red roof over it all.
-- (The wings become the Auction House later.)
local function buildGreatHall(parent)
	local m = folder(parent, "GreatHall")
	local z0, z1 = -110, -74 -- back and front
	local zc, depth = (z0 + z1) / 2, z1 - z0
	local H = 34
	local PASS = 12 -- half the passage's width
	for _, sx in ipairs({ -1, 1 }) do
		local xa, xb = sx * PASS, sx * 40
		local xc, w = (xa + xb) / 2, math.abs(xb - xa)
		part(m, "Wing", V3(w, H, depth), CFrame.new(xc, H / 2, zc), KEEP_STONE, Mat.Cobblestone)
		part(m, "WingPlinth", V3(w + 1, 3, depth + 1), CFrame.new(xc, 1.5, zc), KEEP_DARK, Mat.Cobblestone)
		part(m, "WingBand", V3(w + 0.6, 1, depth + 0.6), CFrame.new(xc, 18, zc), KEEP_DARK, Mat.Cobblestone)
		-- tall glowing windows on the front, and a banner between them
		for _, t in ipairs({ 0.3, 0.7 }) do
			local x = xa + (xb - xa) * t
			part(m, "HallWindow", V3(3, 8, 0.4), CFrame.new(x, 25, z1 + 0.2), RGB(255, 200, 110), Mat.Neon)
			part(m, "HallWindowSill", V3(4, 0.6, 1), CFrame.new(x, 20.7, z1 + 0.5), KEEP_DARK, Mat.Cobblestone)
		end
		banner(m, V3(sx * 26, 12, z1 + 0.1), V3(0, 0, 1), sx < 0 and BANNER_RED or BANNER_BLUE)
		-- the front towers
		local tx = sx * 42
		cylinder(m, "FrontTower", H + 16, 16, CFrame.new(tx, (H + 16) / 2, z1), KEEP_STONE, Mat.Cobblestone)
		cylinder(m, "FrontTowerBand", 1.2, 17.4, CFrame.new(tx, H * 0.6, z1), KEEP_DARK, Mat.Cobblestone)
		cylinder(m, "FrontTowerLedge", 1.6, 18, CFrame.new(tx, H + 16.8, z1), KEEP_DARK, Mat.Cobblestone)
		coneRoof(m, V3(tx, H + 17.5, z1), 10, 28, ROOF_RED, 12)
		wallTorch(m, V3(sx * (PASS + 2.5), 10, z1), V3(0, 0, 1))
	end
	-- the passage's vault and the arch over its front
	part(m, "PassageRoof", V3(PASS * 2 + 0.2, H - 24, depth), CFrame.new(0, 24 + (H - 24) / 2, zc), KEEP_STONE, Mat.Cobblestone)
	for k = 0, 11 do
		local a0, a1 = k / 12 * math.pi, (k + 1) / 12 * math.pi
		local R = PASS
		local p0 = V3(math.cos(a0) * R, 12 + math.sin(a0) * R, z1 + 0.4)
		local p1 = V3(math.cos(a1) * R, 12 + math.sin(a1) * R, z1 + 0.4)
		local mid = (p0 + p1) / 2
		part(m, "Voussoir", V3(2.2, 1.4, (p1 - p0).Magnitude + 0.3), CFrame.lookAt(mid, mid + (p1 - p0).Unit, V3(0, 0, 1)), KEEP_DARK, Mat.Cobblestone)
		-- (fill the corners above the round arch)
		local x = -R + (k + 0.5) * (2 * R / 12)
		local top = 12 + math.sqrt(math.max(0, R * R - x * x))
		part(m, "ArchFill", V3(2 * R / 12 + 0.02, 24 - top, 1.2), CFrame.new(x, (top + 24) / 2, z1 - 0.4), KEEP_STONE, Mat.Cobblestone)
	end
	-- one long red roof along the whole keep
	local roofH, run = 16, depth / 2 + 1
	for _, s in ipairs({ -1, 1 }) do
		local w = Instance.new("WedgePart")
		w.Name = "KeepRoof"
		w.Anchored = true
		w.Size = V3(82, roofH, run)
		w.CFrame = CFrame.fromMatrix(V3(0, H + roofH / 2, zc + s * run / 2), V3(-s, 0, 0), V3(0, 1, 0), V3(0, 0, -s))
		w.Color = ROOF_RED
		w.Material = Mat.SmoothPlastic
		w.TopSurface = Enum.SurfaceType.Smooth
		w.BottomSurface = Enum.SurfaceType.Smooth
		w.Parent = m
	end
	-- dormer spirelets along the ridge
	for _, x in ipairs({ -24, 0, 24 }) do
		coneRoof(m, V3(x, H + roofH - 3, zc), 2.6, 12, ROOF_RED, 7)
	end
	titleSign(m, CFrame.new(0, 30, z1 + 2), "The Spire", nil, RGB(140, 180, 255), 300, 90)
end

-- The fountain in the middle of the plaza, in pixel-art style: a round
-- basin rimmed with chunky stone blocks, blue water with light ripples, a
-- stepped plinth, and on it a stone angel - a Roblox character with
-- feathered wings - holding up a jug that pours water into the basin.
local function buildFountain(parent)
	local m = Instance.new("Model")
	m.Name = "Fountain"
	m.Parent = parent
	local STONE, STONE2, STONE3 = RGB(192, 203, 220), RGB(139, 155, 180), RGB(90, 105, 136)
	local WATER_C, RIPPLE = RGB(0, 153, 219), RGB(44, 232, 245)
	local nc = { CanCollide = false }
	local R = 9.5
	-- the basin: water, and a rim of stone blocks all round
	cylinder(m, "BasinFloor", 1.4, R * 2, CFrame.new(0, 0.7, 0), STONE3, Mat.Slate)
	cylinder(m, "Water", 0.3, R * 2 - 1.5, CFrame.new(0, 1.55, 0), WATER_C, Mat.SmoothPlastic, { CanCollide = false })
	-- ripples drifting out across the basin, fading as they go (LobbyFX)
	for i = 0, 13 do
		local a = i / 14 * math.pi * 2 + (i % 2) * 0.2
		local dir = V3(math.cos(a), 0, math.sin(a))
		local p = dir * 3.2 + V3(0, 1.72, 0)
		local rip = part(m, "Ripple", V3(1.4, 0.1, 0.35), CFrame.lookAt(p, p + V3(-dir.Z, 0, dir.X)), RIPPLE, Mat.SmoothPlastic, nc)
		rip:SetAttribute("WaveMode", "drift")
		rip:SetAttribute("WaveDir", dir)
		rip:SetAttribute("WaveAmp", 4.6)
		rip:SetAttribute("WaveSpeed", 0.4)
		rip:SetAttribute("Phase", (i % 3) * 120 + i * 17)
		CollectionService:AddTag(rip, "Wave")
	end
	local N = 20
	for i = 0, N - 1 do
		local a = i / N * math.pi * 2
		local cf = CFrame.new(math.cos(a) * (R - 0.6), 0, math.sin(a) * (R - 0.6)) * CFrame.Angles(0, -a + math.pi / 2, 0)
		local len = 2 * math.pi * (R - 0.6) / N + 0.25
		part(m, "RimBlock", V3(len, 2.6, 1.6), cf * CFrame.new(0, 1.3, 0), (i % 2 == 0) and STONE or STONE2, Mat.Slate)
		part(m, "RimTop", V3(len + 0.05, 0.4, 2), cf * CFrame.new(0, 2.8, 0.1), STONE, Mat.Slate)
		part(m, "RimLip", V3(len, 0.3, 0.4), cf * CFrame.new(0, 2.45, -0.95), STONE3, Mat.Slate, nc)
	end
	-- the stepped plinth
	part(m, "Plinth1", V3(4.4, 1.6, 4.4), CFrame.new(0, 2.2, 0), STONE2, Mat.Slate)
	part(m, "Plinth2", V3(3.4, 1.4, 3.4), CFrame.new(0, 3.7, 0), STONE, Mat.Slate)
	part(m, "Plinth3", V3(3.8, 0.4, 3.8), CFrame.new(0, 4.6, 0), STONE2, Mat.Slate)
	-- the angel: a stone Roblox character (legs, torso, arms, blocky head)
	local S = 1.25 -- (a little bigger than life)
	local base = CFrame.new(0, 4.8, 0) * CFrame.Angles(0, math.rad(180), 0) -- (faces south, towards the spawn)
	local function b(name, size, x, y, z, color, extra)
		return part(m, name, size * S, base * CFrame.new(x * S, y * S, z * S), color or STONE, Mat.Slate, extra or nc)
	end
	b("AngelLegL", V3(1, 2, 1), -0.5, 1, 0)
	b("AngelLegR", V3(1, 2, 1), 0.5, 1, 0, STONE2)
	b("AngelTorso", V3(2, 2, 1), 0, 3, 0)
	b("AngelRobe", V3(2.2, 0.4, 1.2), 0, 2.2, 0, STONE2)
	b("AngelHead", V3(1.2, 1.2, 1.2), 0, 4.6, 0)
	b("AngelFace", V3(0.8, 0.15, 0.1), 0, 4.55, -0.62, STONE3)
	b("AngelHalo", V3(1.5, 0.15, 1.5), 0, 5.55, 0, RGB(254, 231, 97))
	-- arms raised up to the sky
	for _, side in ipairs({ -1, 1 }) do
		local shoulder = base * CFrame.new(side * 1.5 * S, 4 * S, 0)
		part(m, "AngelArm", V3(1, 2, 1) * S, shoulder * CFrame.Angles(0, 0, side * math.rad(155)) * CFrame.new(0, -1 * S, 0), (side < 0) and STONE or STONE2, Mat.Slate, nc)
	end
	-- feathered wings, spread out behind: stepped rows of flat blocks
	for _, side in ipairs({ -1, 1 }) do
		for k = 0, 3 do
			local len = 3.2 - k * 0.55
			local cf = base * CFrame.new(side * (1.2 + len / 2) * S, (4.6 - k * 0.75) * S, 0.8 * S) * CFrame.Angles(0, 0, side * math.rad(18 - k * 4))
			part(m, "Wing", V3(len, 0.7, 0.4) * S, cf, (k % 2 == 0) and STONE or STONE2, Mat.Slate, nc)
		end
		part(m, "WingTip", V3(0.8, 1.4, 0.4) * S, base * CFrame.new(side * 4.3 * S, 5.4 * S, 0.8 * S), STONE, Mat.Slate, nc)
	end
	-- four little jets bubbling up round the foot of the plinth
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		local p = V3(math.cos(a) * 3.6, 1.7, math.sin(a) * 3.6)
		fx(part(m, "Jet", V3(0.5, 1.6, 0.5), CFrame.new(p + V3(0, 0.8, 0)), RIPPLE, Mat.SmoothPlastic, { CanCollide = false, Transparency = 0.2 }), { BobAmp = 0.35, BobSpeed = 6, Phase = i * 90 })
		local jet = anchorPart(m, "JetSpray", CFrame.new(p + V3(0, 1.6, 0)))
		jet.Size = V3(0.6, 0.2, 0.6)
		local e = Instance.new("ParticleEmitter")
		e.Rate = 10
		e.Color = ColorSequence.new(RGB(210, 240, 255))
		e.Size = NumberSequence.new(0.45, 0.2)
		e.Lifetime = NumberRange.new(0.5, 0.7)
		e.Speed = NumberRange.new(3, 4)
		e.SpreadAngle = Vector2.new(15, 15)
		e.Acceleration = V3(0, -18, 0)
		e.EmissionDirection = Enum.NormalId.Top
		e.Parent = jet
	end
end

-- The Pet Sanctuary (north-west): a fenced flower garden round a tall
-- round tower with a cone roof. (Pets come later - the tower is waiting.)
local function buildPetSanctuary(parent)
	local m = folder(parent, "PetSanctuary")
	local x0, x1, z0, z1 = -110, -60, -108, -58
	part(m, "GardenLawn", V3(x1 - x0, 0.3, z1 - z0), CFrame.new((x0 + x1) / 2, 0.15, (z0 + z1) / 2), RGB(110, 200, 96), Mat.Grass)
	fence(m, V3(x1, 0, z0), V3(x1, 0, z1))
	fence(m, V3(x0 + 2, 0, z1), V3(-89, 0, z1)) -- the front, with a gap for the path
	fence(m, V3(-71, 0, z1), V3(x1, 0, z1))
	local tx, tz = -80, -86
	cylinder(m, "Tower", 44, 18, CFrame.new(tx, 22, tz), RGB(200, 190, 170), Mat.Cobblestone)
	cylinder(m, "TowerBand", 1.2, 19.4, CFrame.new(tx, 26, tz), RGB(150, 120, 90), Mat.Cobblestone)
	cylinder(m, "TowerLedge", 1.6, 20, CFrame.new(tx, 44.8, tz), RGB(150, 120, 90), Mat.Cobblestone)
	coneRoof(m, V3(tx, 45.5, tz), 11, 30, RGB(214, 90, 140), 12)
	part(m, "TowerDoor", V3(5, 8, 0.6), CFrame.new(tx + 3, 4, tz + 9.1) * CFrame.Angles(0, math.rad(20), 0), RGB(110, 70, 44), Mat.WoodPlanks)
	for _, y in ipairs({ 18, 32 }) do
		part(m, "TowerWindow", V3(2, 3.6, 0.4), CFrame.new(tx + 3, y, tz + 9.1) * CFrame.Angles(0, math.rad(20), 0), RGB(255, 200, 110), Mat.Neon)
	end
	-- ivy on the tower
	for i = 0, 5 do
		local a = i * 1.1
		local len = 10 + (i % 3) * 6
		part(m, "Ivy", V3(1, len, 0.5), CFrame.new(tx + math.cos(a) * 9.1, 40 - len / 2, tz + math.sin(a) * 9.1) * CFrame.Angles(0, -a + math.pi / 2, 0), RGB(80, 150, 70), Mat.Grass, { CanCollide = false })
	end
	for _, f in ipairs({ { -100, -70 }, { -70, -104 }, { -100, -84 }, { -104, -64 }, { -66, -66 }, { -82, -100 } }) do
		flowers(m, f[1], f[2], 4)
	end
	blossomTree(m, -102, -98, 0.8)
	bush(m, -106, -104, 0.9)
	titleSign(m, CFrame.new(-80, 12, z1 + 2), "Pet Sanctuary", nil, RGB(255, 150, 200), 320, 70)
end

-- The Farm Colosseum (south-west): for now the practice dummies stand in a
-- fenced farm field with hay bales, until the real colosseum is built.
local function buildFarmField(parent)
	local m = folder(parent, "FarmField")
	local Y = Config.Yard
	local first, last = Config.zonePosition(1), Config.zonePosition(#Config.Zones)
	local x0, x1 = -112, (Y.CenterX or 0) + Y.PerRow * Y.Spacing / 2 - 0.5
	local z0, z1 = first.Z - Y.PadSize / 2 - 6, last.Z + Y.PadSize / 2 + 6
	fence(m, V3(x0, 0, z0), V3(x1, 0, z0))
	fence(m, V3(x0, 0, z1), V3(x1, 0, z1))
	fence(m, V3(x1, 0, z0), V3(x1, 0, 84))
	fence(m, V3(x1, 0, 96), V3(x1, 0, z1))
	local HAY = RGB(222, 190, 90)
	for _, h in ipairs({ { x1 - 3, 80 }, { x1 - 3, 100 }, { x0 + 4, z0 + 4 }, { x0 + 4, z1 - 4 }, { x1 - 4, z1 - 4 } }) do
		part(m, "HayBale", V3(4, 3, 3), CFrame.new(h[1], 1.5, h[2]), HAY, Mat.Grass)
		part(m, "HayBand", V3(4.1, 3.1, 0.4), CFrame.new(h[1], 1.5, h[2]), RGB(150, 110, 60), Mat.Fabric, { CanCollide = false })
	end
	part(m, "HayTop", V3(4, 3, 3), CFrame.new(x1 - 3, 4.5, 80), HAY, Mat.Grass)
	titleSign(m, CFrame.new(x1, 13, 90), "Training Field", nil, RGB(255, 220, 110), 320, 80)
end

-- A stream down the east side of the castle: it springs from a grotto in
-- rocks in the north-east corner, runs past the forge and turns its
-- waterwheel, and drains away through a grated culvert in the south-east.
local function buildRiver(parent)
	local m = folder(parent, "River")
	local x0, x1 = 102, 114
	local zN, zS = -100, 157
	part(m, "RiverWater", V3(x1 - x0, 0.35, zS - zN), CFrame.new((x0 + x1) / 2, 0.22, (zN + zS) / 2), WATER, Mat.SmoothPlastic, {
		Transparency = 0.15, CanCollide = false, CanQuery = false,
	})
	for i = 0, math.floor((zS - zN) / 14) do
		local z = zN + i * 14 + 7
		part(m, "RiverRipple", V3(3, 0.05, 0.4), CFrame.new(x0 + 3 + (i % 3) * 3, 0.42, z), RGB(190, 225, 255), Mat.SmoothPlastic, { CanCollide = false, CanQuery = false })
	end
	-- the bank stones along the castle side
	for z = zN + 2, zS - 2, 6 do
		if math.abs(z - 0) > 9 then
			part(m, "BankStone", V3(1.6, 1 + rnd() * 0.6, 5.6), CFrame.new(x0 - 0.6, 0.5, z), rockColor(0.05), Mat.Slate)
		end
	end
	-- the grotto: rocks round a spring pouring out of the north wall
	for i = 0, 6 do
		local a = i / 6 * math.pi
		part(m, "GrottoRock", V3(6, 5 + rnd() * 6, 5), CFrame.new(108 + math.cos(a) * 9, 2, -104 + math.sin(a) * 3) * CFrame.Angles(0, rnd() * math.pi, 0), rockColor(0.1), Mat.Slate)
	end
	part(m, "Spring", V3(8, 10, 1), CFrame.new(108, 5, -101), RGB(150, 205, 255), Mat.SmoothPlastic, { Transparency = 0.3, CanCollide = false, CanQuery = false })
	-- where it drains away underground, through a grate in a stone culvert
	part(m, "Culvert", V3(x1 - x0 + 3, 5, 3), CFrame.new((x0 + x1) / 2, 2.5, zS + 1.5), STONE_DARK, Mat.Cobblestone)
	for x = x0 + 1, x1 - 1, 2 do
		part(m, "GrateBar", V3(0.5, 3.6, 0.5), CFrame.new(x, 1.8, zS - 0.2), GATE_IRON, Mat.Metal)
	end
	-- the forge's waterwheel
	local wz = Config.Stations.Craft.Z
	local wx = 108
	part(m, "WheelAxle", V3(12, 1, 1), CFrame.new(wx - 4, 8, wz), RGB(70, 50, 34), Mat.Wood)
	for _, dx in ipairs({ -2, 2 }) do
		part(m, "WheelRim", V3(0.8, 16, 16), CFrame.new(wx + dx, 8, wz), RGB(120, 84, 50), Mat.WoodPlanks, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	end
	part(m, "WheelHub", V3(4.4, 12, 12), CFrame.new(wx, 8, wz), WATER, Mat.SmoothPlastic, { Shape = Enum.PartType.Cylinder, Transparency = 1, CanCollide = false })
	for i = 0, 7 do
		local a = i / 8 * math.pi
		part(m, "WheelPaddle", V3(4.6, 15.6, 0.6), CFrame.new(wx, 8, wz) * CFrame.Angles(a, 0, 0), RGB(150, 104, 62), Mat.WoodPlanks, { CanCollide = false })
	end
end

-- The farm (south-east of the plaza): built chunky and blocky like the rest
-- of the castle, in the game's pixel palette. A half-timbered cottage with a
-- stepped tile roof and a smoking chimney, long rows of crops in tilled
-- soil, a windmill, a chicken coop, a well, a scarecrow, barrels, crates and
-- hay, big leafy trees, and a chunky wooden fence open to the road.
local FARM = {
	CREAM = RGB(234, 212, 170), TIMBER = RGB(115, 62, 57), DARK = RGB(62, 39, 49),
	WOOD = RGB(184, 111, 80), TAN = RGB(228, 166, 114), ROOF = RGB(190, 74, 47), ROOF2 = RGB(162, 38, 51),
	STONE = RGB(139, 155, 180), STONE2 = RGB(90, 105, 136), LEAF = RGB(99, 199, 77), LEAF2 = RGB(62, 137, 72),
	LEAF3 = RGB(38, 92, 66), SOIL = RGB(115, 62, 57), RIDGE = RGB(184, 111, 80), DIRT = RGB(228, 166, 114),
	ORANGE = RGB(247, 118, 34), GOLD = RGB(254, 174, 52), YELLOW = RGB(254, 231, 97), RED = RGB(228, 59, 68),
	BLUE = RGB(18, 78, 137), GLOW = RGB(254, 231, 97), WHITE = RGB(255, 255, 255),
}

local function farmFence(m, a, b)
	local d = b - a
	local len = d.Magnitude
	local n = math.max(1, math.floor(len / 4 + 0.5))
	for i = 0, n do
		local p = a + d * (i / n)
		part(m, "FencePost", V3(1.1, 3.8, 1.1), CFrame.new(p.X, 1.9, p.Z), FARM.TIMBER, Mat.WoodPlanks)
		part(m, "FenceCap", V3(1.4, 0.4, 1.4), CFrame.new(p.X, 3.95, p.Z), FARM.WOOD, Mat.WoodPlanks)
	end
	local mid = a + d / 2
	local alongX = math.abs(d.X) > math.abs(d.Z)
	for _, y in ipairs({ 1.5, 3 }) do
		part(m, "FenceRail", alongX and V3(len, 0.6, 0.5) or V3(0.5, 0.6, len), CFrame.new(mid.X, y, mid.Z), FARM.WOOD, Mat.WoodPlanks)
	end
end

-- a big leafy tree made of chunky blocks
local function farmTree(m, x, z, s, y0)
	voxelTree(m, x, z, s, y0)
end

local function blockBush(m, x, z, s, y0)
	voxelBush(m, x, z, s, y0)
end

-- one crop plant, standing on soil whose top is at height y
local function farmCrop(m, kind, x, y, z)
	local nc = { CanCollide = false }
	if kind == "cabbage" then
		part(m, "Leaves", V3(1.9, 0.35, 0.9), CFrame.new(x, y + 0.2, z), FARM.LEAF2, Mat.Grass, nc)
		part(m, "Leaves", V3(0.9, 0.35, 1.9), CFrame.new(x, y + 0.2, z), FARM.LEAF2, Mat.Grass, nc)
		part(m, "Head", V3(1.2, 1, 1.2), CFrame.new(x, y + 0.8, z), FARM.LEAF, Mat.Grass, nc)
	elseif kind == "carrot" then
		part(m, "Carrot", V3(0.8, 0.4, 0.8), CFrame.new(x, y + 0.2, z), FARM.ORANGE, Mat.SmoothPlastic, nc)
		for i = -1, 1 do
			part(m, "Leaf", V3(0.3, 1.3, 0.3), CFrame.new(x + i * 0.3, y + 0.95, z) * CFrame.Angles(0, 0, -i * 0.35), FARM.LEAF, Mat.Grass, nc)
		end
	elseif kind == "turnip" then
		part(m, "Turnip", V3(0.9, 0.55, 0.9), CFrame.new(x, y + 0.27, z), FARM.CREAM, Mat.SmoothPlastic, nc)
		part(m, "TurnipTop", V3(0.6, 0.2, 0.6), CFrame.new(x, y + 0.6, z), RGB(181, 80, 136), Mat.SmoothPlastic, nc)
		for i = -1, 1, 2 do
			part(m, "Leaf", V3(0.35, 1.2, 0.35), CFrame.new(x, y + 1.2, z + i * 0.25) * CFrame.Angles(i * 0.4, 0, 0), FARM.LEAF2, Mat.Grass, nc)
		end
	elseif kind == "wheat" then
		for i = 0, 3 do
			local ox, oz = (i % 2 - 0.5) * 0.7, (math.floor(i / 2) - 0.5) * 0.7
			local h = 2.2 + (i % 3) * 0.3
			part(m, "Stalk", V3(0.25, h, 0.25), CFrame.new(x + ox, y + h / 2, z + oz), FARM.GOLD, Mat.Grass, nc)
			part(m, "Ear", V3(0.45, 0.9, 0.45), CFrame.new(x + ox, y + h + 0.3, z + oz), FARM.YELLOW, Mat.Grass, nc)
		end
	elseif kind == "pumpkin" then
		part(m, "Pumpkin", V3(1.9, 1.3, 1.7), CFrame.new(x, y + 0.65, z), FARM.ORANGE, Mat.SmoothPlastic)
		part(m, "PumpkinLobe", V3(2.1, 1.1, 1.2), CFrame.new(x, y + 0.6, z), FARM.ORANGE, Mat.SmoothPlastic, nc)
		part(m, "PumpkinLobe", V3(1.2, 1.1, 2.1), CFrame.new(x, y + 0.6, z), FARM.ORANGE, Mat.SmoothPlastic, nc)
		part(m, "Stem", V3(0.35, 0.6, 0.35), CFrame.new(x, y + 1.55, z), FARM.LEAF2, Mat.Wood, nc)
		part(m, "Leaf", V3(1.3, 0.25, 1.3), CFrame.new(x + 1.2, y + 0.15, z + 0.8) * CFrame.Angles(0, 0.5, 0), FARM.LEAF2, Mat.Grass, nc)
	elseif kind == "tomato" then
		part(m, "Stake", V3(0.25, 3.4, 0.25), CFrame.new(x, y + 1.7, z), FARM.WOOD, Mat.Wood, nc)
		part(m, "Vine", V3(1.1, 1.1, 1.1), CFrame.new(x, y + 0.9, z), FARM.LEAF2, Mat.Grass, nc)
		part(m, "Vine", V3(0.9, 1, 0.9), CFrame.new(x, y + 2.1, z), FARM.LEAF, Mat.Grass, nc)
		for _, t in ipairs({ { 0.5, 1.2, 0.4 }, { -0.5, 1.8, -0.3 }, { 0.4, 2.5, -0.4 } }) do
			part(m, "Tomato", V3(0.5, 0.5, 0.5), CFrame.new(x + t[1], y + t[2], z + t[3]), FARM.RED, Mat.SmoothPlastic, nc)
		end
	elseif kind == "berry" then
		part(m, "BerryBush", V3(1.6, 1.3, 1.6), CFrame.new(x, y + 0.65, z), FARM.LEAF2, Mat.Grass, nc)
		part(m, "BerryBushTop", V3(1.1, 0.6, 1.1), CFrame.new(x, y + 1.5, z), FARM.LEAF, Mat.Grass, nc)
		for _, b in ipairs({ { 0.82, 0.8, 0.3 }, { -0.82, 0.6, -0.4 }, { 0.2, 1.1, 0.82 }, { -0.3, 0.9, -0.82 } }) do
			part(m, "Berry", V3(0.4, 0.4, 0.4), CFrame.new(x + b[1], y + b[2], z + b[3]), FARM.BLUE, Mat.SmoothPlastic, nc)
		end
	else -- a young sprout
		part(m, "Sprout", V3(0.3, 0.8, 0.3), CFrame.new(x - 0.2, y + 0.4, z) * CFrame.Angles(0, 0, 0.4), FARM.LEAF, Mat.Grass, nc)
		part(m, "Sprout", V3(0.3, 0.8, 0.3), CFrame.new(x + 0.2, y + 0.4, z) * CFrame.Angles(0, 0, -0.4), FARM.LEAF, Mat.Grass, nc)
	end
end

-- a field of tilled soil with rows of crops running east-west
local function farmField(m, x0, x1, z0, rows, skip)
	local depth = #rows * 3.5 + 1
	part(m, "Soil", V3(x1 - x0, 0.5, depth), CFrame.new((x0 + x1) / 2, 0.25, z0 + depth / 2), FARM.SOIL, Mat.Ground)
	for i, kind in ipairs(rows) do
		local z = z0 + 0.5 + (i - 0.5) * 3.5
		part(m, "SoilRidge", V3(x1 - x0 - 1, 0.35, 1.9), CFrame.new((x0 + x1) / 2, 0.67, z), FARM.RIDGE, Mat.Ground, { CanCollide = false })
		for x = x0 + 1.8, x1 - 1.8, 3 do
			if not (skip and skip(x, z)) then
				farmCrop(m, kind, x, 0.85, z)
			end
		end
	end
end

-- a barrel, a crate and a hay bale
local function farmBarrel(m, x, z)
	part(m, "Barrel", V3(2, 2.6, 2), CFrame.new(x, 1.3, z), FARM.WOOD, Mat.WoodPlanks)
	for _, y in ipairs({ 0.6, 2 }) do
		part(m, "BarrelBand", V3(2.1, 0.3, 2.1), CFrame.new(x, y, z), RGB(58, 68, 102), Mat.Metal, { CanCollide = false })
	end
	part(m, "BarrelLid", V3(1.7, 0.15, 1.7), CFrame.new(x, 2.65, z), FARM.TIMBER, Mat.WoodPlanks, { CanCollide = false })
end
local function farmCrate(m, x, y, z, turn)
	local cf = CFrame.new(x, y + 1.1, z) * CFrame.Angles(0, turn or 0, 0)
	part(m, "Crate", V3(2.2, 2.2, 2.2), cf, FARM.TAN, Mat.WoodPlanks)
	part(m, "CrateBand", V3(2.3, 0.4, 2.3), cf, FARM.WOOD, Mat.WoodPlanks, { CanCollide = false })
	part(m, "CrateEdge", V3(0.4, 2.3, 2.3), cf, FARM.WOOD, Mat.WoodPlanks, { CanCollide = false })
end
local function farmHay(m, x, y, z, turn)
	local cf = CFrame.new(x, y + 1.1, z) * CFrame.Angles(0, turn or 0, 0)
	part(m, "HayBale", V3(3.4, 2.2, 2.2), cf, FARM.YELLOW, Mat.Grass)
	for _, dx in ipairs({ -0.9, 0.9 }) do
		part(m, "HayBand", V3(0.3, 2.3, 2.3), cf * CFrame.new(dx, 0, 0), FARM.WOOD, Mat.Fabric, { CanCollide = false })
	end
	part(m, "HayTuft", V3(1, 0.3, 0.6), cf * CFrame.new(0.3, 1.2, -0.3), FARM.GOLD, Mat.Grass, { CanCollide = false })
end

-- The cottage. `O` is its centre on the ground; local +Z is the front.
local function farmCottage(m, O)
	local W, D, WALL_TOP, RIDGE = 10, 7, 11.2, 19.6 -- half width, half depth, heights
	local function p(name, size, x, y, z, color, mat, extra)
		return part(m, name, size, O * CFrame.new(x, y, z), color, mat or Mat.SmoothPlastic, extra)
	end
	local nc = { CanCollide = false }
	p("Plinth", V3(W * 2 + 0.8, 1.2, D * 2 + 0.8), 0, 0.6, 0, FARM.STONE2, Mat.Slate)
	p("Walls", V3(W * 2, WALL_TOP - 1.2, D * 2), 0, (WALL_TOP + 1.2) / 2, 0, FARM.CREAM, Mat.Plastic)
	p("Attic", V3(W * 2, 1.2, D * 2), 0, WALL_TOP + 0.6, 0, FARM.CREAM, Mat.Plastic)

	-- the timber frame on all four walls
	local function beam(x0, y0, z0, x1, y1, z1)
		local a, b = V3(x0, y0, z0), V3(x1, y1, z1)
		local mid, len = (a + b) / 2, (b - a).Magnitude
		part(m, "Timber", V3(0.6, 0.6, len + 0.3), O * CFrame.lookAt(mid, b), FARM.TIMBER, Mat.WoodPlanks, nc)
	end
	for _, sz in ipairs({ -1, 1 }) do
		local z = sz * (D + 0.15)
		for _, y in ipairs({ 1.5, 8.6, WALL_TOP - 0.2 }) do
			beam(-W - 0.15, y, z, W + 0.15, y, z)
		end
		for _, x in ipairs({ -W, -0.5, W }) do
			part(m, "Post", V3(0.6, WALL_TOP - 1.2, 0.6), O * CFrame.new(x, (WALL_TOP + 1.2) / 2, z), FARM.TIMBER, Mat.WoodPlanks, nc)
		end
		-- diagonal braces in the corner panels
		beam(-W, 1.5, z, -W + 3, 8.6, z)
		beam(W, 1.5, z, W - 3, 8.6, z)
		beam(-0.5, 8.6, z, -3.5, WALL_TOP - 0.2, z)
		beam(-0.5, 8.6, z, 2.5, WALL_TOP - 0.2, z)
	end
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (W + 0.15)
		for _, y in ipairs({ 1.5, 8.6, WALL_TOP - 0.2 }) do
			beam(x, y, -D - 0.15, x, y, D + 0.15)
		end
		part(m, "Post", V3(0.6, WALL_TOP - 1.2, 0.6), O * CFrame.new(x, (WALL_TOP + 1.2) / 2, 0), FARM.TIMBER, Mat.WoodPlanks, nc)
		beam(x, 1.5, -D, x, 8.6, -D + 3)
		beam(x, 1.5, D, x, 8.6, D - 3)
		-- the gable: a plaster triangle in two wedges, with a king post and a little window
		local rise = RIDGE - 0.7 - WALL_TOP
		for _, s in ipairs({ -1, 1 }) do
			local w = Instance.new("WedgePart")
			w.Name = "Gable"
			w.Anchored = true
			w.Size = V3(0.8, rise, D)
			w.CFrame = O * CFrame.fromMatrix(V3(sx * W, WALL_TOP + rise / 2, s * D / 2), V3(-s, 0, 0), V3(0, 1, 0), V3(0, 0, -s))
			w.Color = FARM.CREAM
			w.Material = Mat.Plastic
			w.TopSurface = Enum.SurfaceType.Smooth
			w.BottomSurface = Enum.SurfaceType.Smooth
			w.Parent = m
		end
		part(m, "KingPost", V3(0.6, rise - 0.6, 0.6), O * CFrame.new(x, WALL_TOP + (rise - 0.6) / 2, 0), FARM.TIMBER, Mat.WoodPlanks, nc)
		p("GableWindow", V3(0.3, 1.8, 1.8), sx * (W + 0.2), WALL_TOP + 2.6, 2.2, FARM.GLOW, Mat.Neon, nc)
		p("GableWindowFrame", V3(0.25, 2.4, 2.4), sx * (W + 0.1), WALL_TOP + 2.6, 2.2, FARM.TIMBER, Mat.WoodPlanks, nc)
	end

	-- the roof: rows of tiles stepping down from the ridge like pixel art
	for _, s in ipairs({ -1, 1 }) do
		for k = 0, 7 do
			local top = RIDGE - k * 1.2
			p("RoofTiles", V3(W * 2 + 2.4, 1.4, 1.7), 0, top - 0.7, s * (k * 1.25 + 0.85), (k % 2 == 0) and FARM.ROOF or FARM.ROOF2, Mat.Slate)
		end
	end
	p("RidgeCap", V3(W * 2 + 2.8, 0.8, 1.4), 0, RIDGE + 0.3, 0, FARM.DARK, Mat.Slate)
	-- the chimney, with smoke
	p("Chimney", V3(2.6, 11, 2.6), -6, WALL_TOP + 5.5, -3, FARM.STONE, Mat.Cobblestone)
	p("ChimneyBand", V3(2.9, 0.6, 2.9), -6, WALL_TOP + 7, -3, FARM.STONE2, Mat.Cobblestone, nc)
	local cap = p("ChimneyCap", V3(3.2, 0.6, 3.2), -6, WALL_TOP + 11.3, -3, FARM.STONE2, Mat.Cobblestone)
	local smoke = Instance.new("Smoke")
	smoke.Color = RGB(230, 230, 235)
	smoke.Opacity = 0.2
	smoke.RiseVelocity = 3
	smoke.Size = 1.5
	smoke.Parent = cap

	-- the front: a door on the right, a big window on the left
	local FZ = D + 0.2
	p("DoorFrame", V3(4.4, 7.2, 0.4), 4, 1.2 + 3.6, FZ, FARM.TIMBER, Mat.WoodPlanks, nc)
	p("Door", V3(3.4, 6.4, 0.3), 4, 1.2 + 3.2, FZ + 0.1, FARM.WOOD, Mat.WoodPlanks, nc)
	for _, dx in ipairs({ -0.85, 0.85 }) do
		p("DoorPlank", V3(0.15, 6.2, 0.1), 4 + dx, 1.2 + 3.2, FZ + 0.3, FARM.TIMBER, Mat.WoodPlanks, nc)
	end
	p("DoorKnob", V3(0.35, 0.35, 0.3), 5.2, 4.2, FZ + 0.35, FARM.GOLD, Mat.Metal, nc)
	p("DoorStep", V3(4.6, 0.5, 1.6), 4, 0.25, D + 1.2, FARM.STONE, Mat.Slate)
	p("DoorMat", V3(3, 0.1, 1.4), 4, 0.55, D + 1.2, RGB(181, 80, 136), Mat.Fabric, nc)
	p("LanternArm", V3(0.3, 0.3, 1), 6.9, 7, FZ + 0.5, FARM.DARK, Mat.Metal, nc)
	p("Lantern", V3(0.8, 1, 0.8), 6.9, 6.4, FZ + 1, FARM.GLOW, Mat.Neon, nc)
	local function window(x, y, z, face)
		local o = CFrame.new(x, y, z) * CFrame.Angles(0, face, 0)
		local function w(name, size, lx, ly, lz, color, mat)
			part(m, name, size, O * o * CFrame.new(lx, ly, lz), color, mat or Mat.WoodPlanks, nc)
		end
		w("WindowFrame", V3(4, 3.6, 0.35), 0, 0, 0, FARM.TIMBER)
		w("WindowGlass", V3(3.2, 2.8, 0.3), 0, 0, 0.1, FARM.GLOW, Mat.Neon)
		w("WindowBar", V3(0.3, 2.8, 0.35), 0, 0, 0.2, FARM.TIMBER)
		w("WindowBar", V3(3.2, 0.3, 0.35), 0, 0, 0.2, FARM.TIMBER)
		for _, sx in ipairs({ -1, 1 }) do
			w("Shutter", V3(1.3, 3.4, 0.25), sx * 2.8, 0, 0.1, FARM.LEAF2)
			w("ShutterSlat", V3(1.1, 0.2, 0.3), sx * 2.8, 0.6, 0.15, FARM.LEAF3)
			w("ShutterSlat", V3(1.1, 0.2, 0.3), sx * 2.8, -0.6, 0.15, FARM.LEAF3)
		end
		w("FlowerBox", V3(4.2, 0.8, 0.9), 0, -2.2, 0.4, FARM.WOOD)
		for i = -1, 1 do
			w("BoxLeaves", V3(1.2, 0.5, 0.7), i * 1.3, -1.6, 0.4, FARM.LEAF2, Mat.Grass)
			w("BoxFlower", V3(0.55, 0.55, 0.55), i * 1.3 + 0.2, -1.2, 0.45, ({ FARM.RED, FARM.YELLOW, RGB(246, 117, 122) })[i + 2], Mat.SmoothPlastic)
		end
	end
	window(-4.5, 5.4, FZ, 0)
	window(-4.5, 5.4, -FZ, math.pi)
	window(4.5, 5.4, -FZ, math.pi)
end

local function buildFarm(parent)
	local m = folder(parent, "Farm")
	-- the windmill, in the south-east corner of the farm
	local x, z = 86, 128
	for i = 0, 3 do
		cylinder(m, "MillBody", 7, 16 - i * 2, CFrame.new(x, 3.5 + i * 7, z), FARM.CREAM, Mat.Plastic)
		cylinder(m, "MillBand", 0.6, 16.4 - i * 2, CFrame.new(x, 7 + i * 7, z), FARM.TAN, Mat.Plastic)
	end
	coneRoof(m, V3(x, 28, z), 7, 12, FARM.ROOF, 8)
	part(m, "MillDoor", V3(4, 6, 0.5), CFrame.new(x, 3, z - 7.9), FARM.WOOD, Mat.WoodPlanks)
	part(m, "MillDoorFrame", V3(4.8, 6.6, 0.3), CFrame.new(x, 3.3, z - 7.8), FARM.TIMBER, Mat.WoodPlanks)
	part(m, "MillWindow", V3(1.6, 2, 0.4), CFrame.new(x, 15, z - 6.2), FARM.GLOW, Mat.Neon)
	-- the sails: a model of their own, turned slowly round the hub on
	-- every player's screen by LobbyFX (tagged "Rotor")
	local sails = Instance.new("Model")
	sails.Name = "MillSails"
	sails.Parent = m
	local hub = CFrame.new(x, 22, z - 6.5)
	sails.PrimaryPart = part(sails, "MillHub", V3(2, 2, 1.6), hub, FARM.DARK, Mat.Wood)
	for i = 0, 3 do
		local c = hub * CFrame.Angles(0, 0, i * math.pi / 2 + 0.3) * CFrame.new(0, 8, -0.4)
		part(sails, "MillArm", V3(0.7, 16, 0.5), c, FARM.TIMBER, Mat.Wood, { CanCollide = false })
		part(sails, "MillSail", V3(3.4, 11, 0.2), c * CFrame.new(2, 1.5, 0), FARM.WHITE, Mat.Fabric, { CanCollide = false })
		for k = -1, 1 do
			part(sails, "MillSlat", V3(3.6, 0.25, 0.3), c * CFrame.new(2, 1.5 + k * 3.6, 0.1), FARM.TIMBER, Mat.Wood, { CanCollide = false })
		end
	end
	part(m, "MillAxle", V3(1, 1, 2), CFrame.new(x, 22, z - 5.2), FARM.DARK, Mat.Wood)
	sails:SetAttribute("RotorSpeed", 45) -- degrees per second...
	sails:SetAttribute("RotorStep", 15) -- ...in 15-degree jumps, like sprite frames
	CollectionService:AddTag(sails, "Rotor")

	-- the dirt path from the road to the cottage, and the yard in front of it
	-- (a worn dirt track in a few shades, with trodden patches, pebbles and
	-- grass tufts at its ragged edges; where it leaves the cobbled road, loose
	-- cobbles scatter into the dirt and thin out, so the two blend together)
	do
		local SHADES = { FARM.DIRT, FARM.DIRT, RGB(232, 183, 150), RGB(194, 133, 105) }
		local COBBLE = { RGB(139, 155, 180), RGB(192, 203, 220), RGB(160, 170, 192) }
		local nc = { CanCollide = false, CanQuery = false }
		local up, down = 0, 0
		for x = 8, 62, 1.5 do
			up = math.clamp(up + (rnd() - 0.5) * 0.9, -0.6, 1)
			down = math.clamp(down + (rnd() - 0.5) * 0.9, -0.6, 1)
			local zN, zS = 93.5 - up, 98.5 + down
			part(m, "FarmPath", V3(1.55, 0.3, zS - zN), CFrame.new(x + 0.75, 0.15, (zN + zS) / 2), SHADES[1 + math.floor(rnd() * #SHADES)], Mat.Ground, nc)
			if rnd() < 0.35 then
				part(m, "PathPatch", V3(1.2 + rnd() * 1.5, 0.3, 1 + rnd() * 1.5), CFrame.new(x + 0.75, 0.19, zN + 1 + rnd() * (zS - zN - 2)), RGB(184, 111, 80), Mat.Ground, nc)
			end
			if rnd() < 0.4 then
				local s2 = 0.3 + rnd() * 0.35
				part(m, "PathPebble", V3(s2, 0.25, s2), CFrame.new(x + rnd() * 1.5, 0.35, zN + 0.5 + rnd() * (zS - zN - 1)), (rnd() < 0.5) and RGB(115, 62, 57) or RGB(234, 212, 170), Mat.Slate, nc)
			end
			for _, ez in ipairs({ zN, zS }) do
				if rnd() < 0.4 then
					local h = 0.5 + rnd() * 0.5
					part(m, "PathTuft", V3(0.35, h, 0.35), CFrame.new(x + rnd() * 1.5, h / 2, ez + (rnd() - 0.5) * 0.8), (rnd() < 0.5) and FARM.LEAF or FARM.LEAF2, Mat.Grass, nc)
				end
			end
			-- loose cobbles near the road, fewer the further in you go
			local fade = 1 - (x - 8.5) / 11
			for _ = 1, 3 do
				if rnd() < fade * 0.8 then
					local c = 1.2 + rnd() * 0.7
					part(m, "PathCobble", V3(c, 0.2, c * (0.8 + rnd() * 0.4)), CFrame.new(x + rnd() * 1.5, 0.36, zN + 0.6 + rnd() * (zS - zN - 1.2)) * CFrame.Angles(0, (rnd() - 0.5) * 0.4, 0), COBBLE[1 + math.floor(rnd() * #COBBLE)], Mat.Slate, nc)
				end
			end
		end
		part(m, "FarmYard", V3(15, 0.3, 26), CFrame.new(71.5, 0.15, 93), FARM.DIRT, Mat.Ground)
		for _ = 1, 12 do
			part(m, "PathPatch", V3(1.5 + rnd() * 2.5, 0.3, 1.2 + rnd() * 2), CFrame.new(65 + rnd() * 13, 0.19, 81 + rnd() * 24), (rnd() < 0.5) and RGB(184, 111, 80) or RGB(232, 183, 150), Mat.Ground, nc)
		end
	end
	for _, s in ipairs({ { 30, 93.2 }, { 44, 98.9 }, { 57, 93.1 } }) do
		part(m, "PathPebble", V3(1, 0.2, 0.7), CFrame.new(s[1], 0.35, s[2]), FARM.STONE, Mat.Slate, { CanCollide = false })
	end

	-- the cottage, facing west down the path
	farmCottage(m, CFrame.new(86, 0, 93) * CFrame.Angles(0, math.rad(-90), 0))
	farmBarrel(m, 77.4, 100.8)
	farmBarrel(m, 77.4, 103)
	farmCrate(m, 77.5, 0, 85.2, 0.1)
	farmCrate(m, 77.3, 2.2, 85.4, -0.2)
	farmCrate(m, 75.1, 0, 84.8, 0.4)
	-- the shipping bin
	part(m, "ShippingBin", V3(3, 2.6, 4.4), CFrame.new(74.5, 1.3, 90), FARM.WOOD, Mat.WoodPlanks)
	part(m, "BinLid", V3(3.4, 0.5, 4.8), CFrame.new(74.5, 2.85, 90), FARM.TIMBER, Mat.WoodPlanks)
	part(m, "BinBand", V3(3.1, 0.4, 4.5), CFrame.new(74.5, 1.8, 90), RGB(58, 68, 102), Mat.Metal, { CanCollide = false })
	-- the well
	local wx, wz = 70, 84
	part(m, "WellBase", V3(5.6, 2.4, 5.6), CFrame.new(wx, 1.2, wz), FARM.STONE, Mat.Cobblestone)
	for _, e in ipairs({ { 0, 2.5, 5.8, 0.8 }, { 0, -2.5, 5.8, 0.8 }, { 2.5, 0, 0.8, 5.8 }, { -2.5, 0, 0.8, 5.8 } }) do
		part(m, "WellRim", V3(e[3], 0.6, e[4]), CFrame.new(wx + e[1], 2.7, wz + e[2]), FARM.STONE2, Mat.Cobblestone)
	end
	part(m, "WellWater", V3(4.2, 0.2, 4.2), CFrame.new(wx, 2.55, wz), RGB(0, 153, 219), Mat.SmoothPlastic, { CanCollide = false })
	for _, d in ipairs({ -2.5, 2.5 }) do
		part(m, "WellPost", V3(0.6, 5.4, 0.6), CFrame.new(wx, 5.4, wz + d), FARM.TIMBER, Mat.Wood)
	end
	part(m, "WellCrank", V3(0.4, 0.4, 6), CFrame.new(wx, 6.4, wz), FARM.TIMBER, Mat.Wood)
	part(m, "WellRope", V3(0.15, 2, 0.15), CFrame.new(wx, 5.3, wz), FARM.CREAM, Mat.Fabric, { CanCollide = false })
	part(m, "WellBucket", V3(0.9, 0.9, 0.9), CFrame.new(wx, 3.9, wz), FARM.WOOD, Mat.WoodPlanks, { CanCollide = false })
	for _, s in ipairs({ -1, 1 }) do
		for k = 0, 1 do
			part(m, "WellRoof", V3(3.6 - k * 1.2, 0.8, 7), CFrame.new(wx + s * (0.9 + k * 1.2), 8.4 - k * 0.8, wz), (k == 0) and FARM.ROOF or FARM.ROOF2, Mat.Slate)
		end
	end
	part(m, "WellRidge", V3(1.2, 0.6, 7.4), CFrame.new(wx, 8.9, wz), FARM.DARK, Mat.Slate)

	-- the crop fields
	farmField(m, 24, 62, 76, { "cabbage", "carrot", "turnip", "berry" })
	farmField(m, 24, 62, 102, { "tomato", "wheat", "wheat", "sprout" }, function(cx, cz)
		return math.abs(cx - 43) < 2.5 and cz > 106 and cz < 112
	end)
	farmField(m, 24, 56, 120, { "pumpkin", "pumpkin", "sprout", "cabbage" })

	-- the scarecrow, in the wheat, looking down the path
	local sc = CFrame.new(43, 0, 109.25) * CFrame.Angles(0, math.rad(-90), 0)
	local function s(name, size, x2, y2, z2, color, mat)
		part(m, name, size, sc * CFrame.new(x2, y2, z2), color, mat or Mat.Fabric, { CanCollide = false })
	end
	s("ScarecrowPost", V3(0.6, 8.4, 0.6), 0, 4.2, 0, FARM.TIMBER, Mat.Wood)
	s("ScarecrowArms", V3(6.4, 0.5, 0.5), 0, 6, 0, FARM.TIMBER, Mat.Wood)
	s("ScarecrowShirt", V3(2, 2.6, 1.2), 0, 5.4, 0, FARM.BLUE)
	s("ScarecrowSleeves", V3(5.4, 0.9, 0.9), 0, 6, 0, FARM.BLUE)
	s("ScarecrowPatch", V3(0.8, 0.8, 0.2), 0.4, 5, 0.65, FARM.RED)
	s("ScarecrowRope", V3(2.1, 0.3, 1.3), 0, 4.3, 0, FARM.TAN)
	for _, sx in ipairs({ -1, 1 }) do
		s("Straw", V3(0.5, 0.9, 0.7), sx * 2.9, 5.7, 0, FARM.YELLOW, Mat.Grass)
	end
	s("ScarecrowHead", V3(1.8, 1.8, 1.8), 0, 7.8, 0, FARM.YELLOW, Mat.Grass)
	s("ScarecrowEye", V3(0.35, 0.35, 0.2), -0.4, 8, 0.92, FARM.DARK, Mat.SmoothPlastic)
	s("ScarecrowEye", V3(0.35, 0.35, 0.2), 0.4, 8, 0.92, FARM.DARK, Mat.SmoothPlastic)
	s("ScarecrowMouth", V3(0.9, 0.2, 0.2), 0, 7.4, 0.92, FARM.DARK, Mat.SmoothPlastic)
	s("HatBrim", V3(3, 0.3, 3), 0, 8.85, 0, FARM.WOOD)
	s("HatTop", V3(1.8, 1.2, 1.8), 0, 9.6, 0, FARM.WOOD)
	s("HatBand", V3(1.9, 0.3, 1.9), 0, 9.2, 0, FARM.RED)

	-- the chicken coop and its chickens
	local coop = CFrame.new(70, 0, 112) * CFrame.Angles(0, math.rad(-90), 0)
	local function c(name, size, x2, y2, z2, color, mat, extra)
		part(m, name, size, coop * CFrame.new(x2, y2, z2), color, mat or Mat.WoodPlanks, extra)
	end
	c("CoopLegs", V3(6.6, 1, 7.6), 0, 0.5, 0, FARM.TIMBER, Mat.Wood)
	c("Coop", V3(6, 4.4, 7), 0, 3.2, 0, FARM.WOOD)
	for k = -1, 1 do
		c("CoopPlank", V3(6.1, 0.2, 0.2), 0, 2 + (k + 1) * 1.4, 3.55, FARM.TIMBER, Mat.WoodPlanks, { CanCollide = false })
	end
	for _, sd in ipairs({ -1, 1 }) do
		for k = 0, 2 do
			c("CoopRoof", V3(7.4, 0.8, 1.6), 0, 7.2 - k * 0.8, sd * (0.8 + k * 1.3), (k % 2 == 0) and FARM.ROOF or FARM.ROOF2, Mat.Slate)
		end
	end
	c("CoopDoor", V3(1.8, 2.4, 0.3), -1.4, 2.6, 3.55, FARM.DARK, Mat.SmoothPlastic, { CanCollide = false })
	c("CoopRamp", V3(1.8, 0.3, 3), -1.4, 0.8, 4.9, FARM.TIMBER, Mat.WoodPlanks)
	c("CoopWindow", V3(1.4, 1.2, 0.3), 1.6, 3.4, 3.55, FARM.GLOW, Mat.Neon, { CanCollide = false })
	for i, h in ipairs({ { 64, 105.5, 0.4 }, { 67.5, 104.8, 2.2 }, { 75.5, 108.5, 4 }, { 76.5, 115, 1 }, { 65, 119.5, 3 }, { 70.5, 120.5, 5.2 } }) do
		local cf = CFrame.new(h[1], 0, h[2]) * CFrame.Angles(0, h[3], 0)
		local body = (i % 3 == 0) and FARM.WOOD or FARM.WHITE
		part(m, "ChickenBody", V3(1.4, 1.2, 1.8), cf * CFrame.new(0, 0.9, 0), body, Mat.SmoothPlastic)
		part(m, "ChickenHead", V3(0.8, 0.9, 0.8), cf * CFrame.new(0, 1.8, -0.9), body, Mat.SmoothPlastic, { CanCollide = false })
		part(m, "ChickenComb", V3(0.3, 0.4, 0.5), cf * CFrame.new(0, 2.4, -0.9), FARM.RED, Mat.SmoothPlastic, { CanCollide = false })
		part(m, "ChickenBeak", V3(0.3, 0.25, 0.4), cf * CFrame.new(0, 1.8, -1.45), FARM.GOLD, Mat.SmoothPlastic, { CanCollide = false })
		part(m, "ChickenTail", V3(0.8, 0.8, 0.4), cf * CFrame.new(0, 1.4, 1), body, Mat.SmoothPlastic, { CanCollide = false })
		part(m, "ChickenLegs", V3(0.6, 0.3, 0.3), cf * CFrame.new(0, 0.15, 0), FARM.GOLD, Mat.SmoothPlastic, { CanCollide = false })
	end
	farmHay(m, 97, 0, 110, 0)
	farmHay(m, 97, 0, 113.6, 0.08)
	farmHay(m, 97, 2.2, 111.8, 1.57)

	-- trees and bushes
	farmTree(m, 95, 76.5, 0.9)
	farmTree(m, 64, 139, 0.85)
	blockBush(m, 21.5, 139, 1)
	blockBush(m, 97, 140, 0.9)
	blockBush(m, 21.5, 76, 0.9)

	-- a few sunflowers either side of the entrance, facing the road: pixel
	-- flowers with a plus of petals, corner petals and a brown middle
	for _, zz in ipairs({ 86, 89.5, 102.5, 106 }) do
		local h = 5 + (zz % 2) * 0.8
		local nc = { CanCollide = false }
		part(m, "SunflowerStem", V3(0.35, h, 0.35), CFrame.new(20.8, h / 2, zz), FARM.LEAF2, Mat.Grass, nc)
		part(m, "SunflowerLeaf", V3(0.3, 0.3, 1.2), CFrame.new(20.8, h * 0.45, zz + 0.55), FARM.LEAF, Mat.Grass, nc)
		part(m, "SunflowerLeaf", V3(0.3, 0.3, 1.2), CFrame.new(20.8, h * 0.62, zz - 0.55), FARM.LEAF, Mat.Grass, nc)
		part(m, "SunflowerPetals", V3(0.25, 2, 0.7), CFrame.new(20.6, h, zz), FARM.YELLOW, Mat.SmoothPlastic, nc)
		part(m, "SunflowerPetals", V3(0.25, 0.7, 2), CFrame.new(20.6, h, zz), FARM.YELLOW, Mat.SmoothPlastic, nc)
		for _, d in ipairs({ { 0.55, 0.55 }, { -0.55, 0.55 }, { 0.55, -0.55 }, { -0.55, -0.55 } }) do
			part(m, "SunflowerPetals", V3(0.22, 0.45, 0.45), CFrame.new(20.62, h + d[1], zz + d[2]), FARM.GOLD, Mat.SmoothPlastic, nc)
		end
		part(m, "SunflowerMiddle", V3(0.3, 0.8, 0.8), CFrame.new(20.45, h, zz), FARM.TIMBER, Mat.SmoothPlastic, nc)
	end

	-- the fence, with an open gap where the path comes in from the road
	farmFence(m, V3(18, 0, 72), V3(100, 0, 72))
	farmFence(m, V3(18, 0, 144), V3(100, 0, 144))
	farmFence(m, V3(100, 0, 72), V3(100, 0, 144))
	farmFence(m, V3(18, 0, 72), V3(18, 0, 92.6))
	farmFence(m, V3(18, 0, 99.4), V3(18, 0, 144))
end


----------------------------------------------------------------------
-- The island and the sea
----------------------------------------------------------------------
-- The castle stands in the middle of an island in the sea. The island's
-- shape is "organised chaos": an oval pushed out into peninsulas and
-- pulled in into bays by a few overlapping waves, laid out in chunky
-- 6-stud steps like pixel art. Grass all round the castle's rock, a ring
-- of sandy beach (wide in the cove south of the castle, where the mushroom
-- house stands by a wooden pier), rocky stretches of coast, light
-- shallows you can wade in, and the open sea twinkling beyond - with
-- sailboats, little islets (one with a lighthouse) and a village of
-- cottages among the trees. The Spire stands on its own islet, reached by
-- the bridge. Anyone who falls into the deep sea is washed back to spawn.
local ISLE = {
	GRASS = RGB(99, 199, 77), GRASS2 = RGB(62, 137, 72), DIRT = RGB(184, 111, 80), ROCK = RGB(139, 155, 180),
	ROCK2 = RGB(90, 105, 136), ROCK3 = RGB(58, 68, 102), SAND = RGB(234, 212, 170), SAND2 = RGB(228, 166, 114),
	SEA = RGB(0, 153, 219), SHALLOW = RGB(44, 232, 245), FOAM = RGB(255, 255, 255),
}
local ISLE_CX, ISLE_CZ = 0, 50 -- the middle of the island's oval
local CELL = 6 -- the size of one "pixel" of the island
local GRID_X0, GRID_X1, GRID_Z0, GRID_Z1 = -420, 420, -420, 520
local BEACH_TOP = SEA_Y + 1.5
local STAIR_HALF = 7 -- half the width of the stairs down to the beach
local PATH_END_X = -18 -- where the path from the gate reaches the cove (and the pier)
local SPIRE_ISLE_Z = -316

-- how far the castle's rectangle is from (x, z) (0 inside it)
local function castleRectDist(x, z)
	local dx = math.max(math.abs(x) - 128, 0)
	local dz = math.max(-128 - z, z - 199, 0)
	return math.sqrt(dx * dx + dz * dz)
end
-- how far out from the middle, in direction th, to be m studs clear of the castle
local function castleNeed(th, m)
	local lo, hi = 0, 700
	for _ = 1, 26 do
		local mid = (lo + hi) / 2
		if castleRectDist(ISLE_CX + math.cos(th) * mid, ISLE_CZ + math.sin(th) * mid) < m then
			lo = mid
		else
			hi = mid
		end
	end
	return hi
end
local function angleDiff(a, b)
	return math.atan2(math.sin(a - b), math.cos(a - b))
end
-- the oval: wider to the south, where there's more room
local function isleBase(th)
	local dx, dz = math.cos(th), math.sin(th)
	local b = (dz < 0) and 205 or 310
	return 1 / math.sqrt((dx / 262) ^ 2 + (dz / b) ^ 2)
end
-- peninsulas (+) and bays (-): direction (0 = east, pi/2 = south), width, size
local ISLE_FEATURES = {
	{ 0.15, 0.22, 70 }, { 0.95, 0.16, -60 }, { 1.55, 0.3, 30 }, { 2.25, 0.2, 75 }, { 2.85, 0.14, -55 },
	{ -2.55, 0.2, 45 }, { -2.05, 0.16, -30 }, { -0.75, 0.18, -40 }, { -0.35, 0.12, 30 }, { 3.3, 0.1, 25 },
}
local function isleBumps(th)
	local t = 0
	for _, f in ipairs(ISLE_FEATURES) do
		t = t + f[3] * math.exp(-(angleDiff(th, f[1]) / f[2]) ^ 2)
	end
	return t
end
local function isleWobble(th)
	return 1 + 0.07 * math.sin(2 * th + 1.3) + 0.06 * math.sin(3 * th + 0.4) + 0.045 * math.sin(5 * th + 2.1) + 0.03 * math.sin(9 * th + 0.7)
end
-- the sandy cove west of the pier: the grass steps back there, the beach doesn't
local function isleCove(th)
	return -58 * math.exp(-(angleDiff(th, 1.78) / 0.2) ^ 2)
end
-- the edge of the grass, the beach and the shallows in every direction,
-- worked out once into tables (one entry per quarter of a degree)
local BINS = 1440
local EDGE_GRASS, EDGE_BEACH, EDGE_SHALLOW = {}, {}, {}
for i = 0, BINS - 1 do
	local th = -math.pi + (i + 0.5) / BINS * 2 * math.pi
	local grass0 = math.max(castleNeed(th, 24 + 6 * math.sin(5 * th + 1)), isleBase(th) * isleWobble(th) + isleBumps(th))
	EDGE_GRASS[i] = math.max(castleNeed(th, 20), grass0 + isleCove(th))
	local south = math.exp(-((th - 1.45) / 0.3) ^ 2)
	EDGE_BEACH[i] = grass0 + 16 + 16 * (0.5 + 0.5 * math.sin(4 * th + 0.9)) + 7 * math.sin(7 * th + 2.5) + 30 * south
	EDGE_SHALLOW[i] = EDGE_BEACH[i] + 16 + 12 * (0.5 + 0.5 * math.sin(3 * th + 1.7))
end
local function edgeBin(th)
	return math.clamp(math.floor((th + math.pi) / (2 * math.pi) * BINS), 0, BINS - 1)
end
local function spireBeachR(t)
	return 100 + 7 * math.sin(3 * t + 0.5) + 4 * math.sin(5 * t + 2)
end

-- what's at (x, z): 3 = grass, 2 = beach, 1 = shallows, 0 = open sea
local function isleLevel(x, z)
	local th = math.atan2(z - ISLE_CZ, x - ISLE_CX)
	local r = math.sqrt((x - ISLE_CX) ^ 2 + (z - ISLE_CZ) ^ 2)
	local i = edgeBin(th)
	local L = 0
	if r < EDGE_GRASS[i] then
		L = 3
	elseif r < EDGE_BEACH[i] and z > -186 + 4 * math.sin(x * 0.045 + 1) then
		L = 2 -- (the north shore stops short of the Spire's islet, along a wavy line)
	elseif r < EDGE_SHALLOW[i] and z > -199 + 3 * math.sin(x * 0.06 + 2) then
		L = 1
	end
	-- the Spire's islet
	local ts = math.atan2(z - SPIRE_ISLE_Z, x)
	local rs = math.sqrt(x * x + (z - SPIRE_ISLE_Z) ^ 2)
	local sb = spireBeachR(ts)
	if rs < sb then
		L = math.max(L, 2)
	elseif rs < sb + 12 + 5 * math.sin(4 * ts + 1) then
		L = math.max(L, 1)
	end
	return L
end

-- is (x, z) on (or right beside) the stairs and pier down to the beach?
local function nearStairs(x, z)
	return z > SOUTH_WALL + 2 and math.abs(x) < STAIR_HALF + 22
end
-- the mushroom house's patch of the cove (it's 40 x 42, facing east)
local function nearMushroomHouse(x, z)
	local st = Config.Stations.Upgrades
	return math.abs(x - st.X) < 26 and z > st.Z - 22 and z < st.Z + 30
end
-- the village cottages: x, z, which way they face
local ISLE_HOUSES = {
	{ 284, 106, 90, RGB(190, 74, 47) }, { 196, 158, 90, RGB(162, 38, 51) }, { -224, 226, -90, RGB(18, 78, 137) },
	{ -204, 282, 0, RGB(190, 74, 47) }, { 152, 10, 90, RGB(190, 74, 47) }, { 160, 82, 90, RGB(18, 78, 137) },
	{ -164, -2, -90, RGB(162, 38, 51) }, { 48, 318, 0, RGB(162, 38, 51) },
}
local function nearHouse(x, z, d)
	for _, h in ipairs(ISLE_HOUSES) do
		if math.abs(x - h[1]) < d and math.abs(z - h[2]) < d then
			return true
		end
	end
	return false
end

-- a palm tree: a leaning trunk of little blocks, coconuts, and drooping
-- fronds made of flat blocks
local function palmTree(m, x, y, z, s, lean)
	local dir = V3(math.cos(lean), 0, math.sin(lean))
	local at = V3(x, y, z)
	local offs = { 0, 0.12, 0.3, 0.55, 0.85, 1.2, 1.6 }
	for i = 1, 7 do
		local p = at + dir * offs[i] * s * 1.6 + V3(0, (i - 0.5) * 1.5 * s, 0)
		part(m, "PalmTrunk", V3(1.2, 1.55, 1.2) * s, CFrame.new(p) * CFrame.Angles(0, lean, 0), (i % 2 == 0) and RGB(194, 133, 105) or RGB(184, 111, 80), Mat.Wood)
	end
	local top = at + dir * offs[7] * s * 1.6 + V3(0, 7 * 1.5 * s + 0.2 * s, 0)
	for i = 0, 2 do
		local a = i * 2.1
		part(m, "Coconut", V3(0.8, 0.8, 0.8) * s, CFrame.new(top + V3(math.cos(a) * 0.7 * s, -0.7 * s, math.sin(a) * 0.7 * s)), RGB(115, 62, 57), Mat.Wood, { CanCollide = false })
	end
	for i = 0, 5 do
		local a = i * math.pi / 3 + lean * 0.5
		local base = CFrame.new(top) * CFrame.Angles(0, a, 0)
		local green = (i % 2 == 0) and ISLE.GRASS or ISLE.GRASS2
		part(m, "Frond", V3(1.5, 0.3, 4.2) * s, base * CFrame.new(0, 0.3 * s, -2 * s) * CFrame.Angles(0.22, 0, 0), green, Mat.Grass, { CanCollide = false })
		part(m, "FrondTip", V3(1.2, 0.3, 3.4) * s, base * CFrame.new(0, -0.75 * s, -5.3 * s) * CFrame.Angles(-0.5, 0, 0), green, Mat.Grass, { CanCollide = false })
	end
	part(m, "PalmCrown", V3(1.6, 0.8, 1.6) * s, CFrame.new(top), ISLE.GRASS2, Mat.Grass, { CanCollide = false })
end

-- a little cottage on the hillside: cream walls, dark beams, a stepped red
-- roof and a chimney. `cf` is the middle of its floor; it faces local +Z.
local function isleHouse(m, cf, roof)
	local function p(name, size, x, y, z, color, mat, extra)
		return part(m, name, size, cf * CFrame.new(x, y, z), color, mat or Mat.Plastic, extra)
	end
	local nc = { CanCollide = false }
	p("HousePlinth", V3(9, 1, 7.6), 0, 0.5, 0, ISLE.ROCK2, Mat.Slate)
	p("HouseWalls", V3(8, 6, 6.6), 0, 4, 0, RGB(234, 212, 170))
	for _, x in ipairs({ -4, 4 }) do
		for _, z in ipairs({ -3.3, 3.3 }) do
			p("HouseBeam", V3(0.5, 6.2, 0.5), x, 4, z, RGB(115, 62, 57), Mat.WoodPlanks, nc)
		end
	end
	p("HouseBeam", V3(8.4, 0.5, 6.9), 0, 6.9, 0, RGB(115, 62, 57), Mat.WoodPlanks, nc)
	for _, s in ipairs({ -1, 1 }) do
		for k = 0, 3 do
			p("HouseRoof", V3(9.4, 1, 1.4), 0, 10.6 - k * 1, s * (0.6 + k * 1.05), (k % 2 == 0) and roof or roof:Lerp(RGB(0, 0, 0), 0.2), Mat.Slate)
		end
	end
	p("HouseAttic", V3(8, 2.4, 4.6), 0, 8.2, 0, RGB(234, 212, 170))
	p("HouseChimney", V3(1.4, 4, 1.4), 2.4, 10.4, -1.2, ISLE.ROCK, Mat.Cobblestone)
	p("HouseDoor", V3(1.8, 3.2, 0.3), -1.6, 2.6, 3.35, RGB(184, 111, 80), Mat.WoodPlanks, nc)
	p("HouseWindow", V3(1.6, 1.4, 0.3), 1.8, 4.2, 3.35, RGB(254, 231, 97), Mat.Neon, nc)
	p("HouseWindowFrame", V3(2, 1.8, 0.2), 1.8, 4.2, 3.3, RGB(115, 62, 57), Mat.WoodPlanks, nc)
end

-- a small islet out at sea: a stack of rock, a grassy top, a ring of sand
-- and light shallows round it, and a tree or two
local function islet(m, cx, cz, r, top, trees)
	local function ring(name, rad, y0, y1, color, mat, extra)
		for k = 0, 2 do
			part(m, name, V3(rad * 2, y1 - y0, rad * 2), CFrame.new(cx, (y0 + y1) / 2, cz) * CFrame.Angles(0, k * math.pi / 6, 0), color, mat, extra)
		end
	end
	ring("IsletShallows", r + 16, SEA_Y + 0.2, SEA_Y + 0.35, ISLE.SHALLOW, Mat.SmoothPlastic, { CanCollide = false, CastShadow = false })
	ring("IsletSand", r + 7, ISLAND_FLOOR, SEA_Y + 1.2, ISLE.SAND, Mat.Sand, { CastShadow = false })
	ring("IsletRock", r, ISLAND_FLOOR, top - 1.2, ISLE.ROCK, Mat.Slate, { CastShadow = false })
	ring("IsletTop", r + 0.4, top - 1.2, top, ISLE.GRASS, Mat.Grass, { CastShadow = false })
	for i = 1, trees do
		local a = rnd() * math.pi * 2
		local d = rnd() * r * 0.45
		farmTree(m, cx + math.cos(a) * d, cz + math.sin(a) * d, 0.55 + rnd() * 0.3, top)
	end
	for _ = 1, 3 do
		local a = rnd() * math.pi * 2
		local s = 3 + rnd() * 3
		part(m, "IsletBoulder", V3(s * 1.3, s, s), CFrame.new(cx + math.cos(a) * (r + 4), SEA_Y + 1 + s * 0.3, cz + math.sin(a) * (r + 4)) * CFrame.Angles(0, rnd() * 3, 0), ISLE.ROCK2, Mat.Slate)
	end
end

-- a little sailboat, bobbing on the waves (LobbyFX moves it)
local function sailboat(m, x, z, yaw, sail, phase)
	local cf = CFrame.new(x, SEA_Y, z) * CFrame.Angles(0, yaw, 0)
	local bob = { BobAmp = 0.35, BobSpeed = 1.3, Phase = phase }
	local function p(name, size, lx, ly, lz, color, mat)
		fx(part(m, name, size, cf * CFrame.new(lx, ly, lz), color, mat or Mat.WoodPlanks, { CanCollide = false }), bob)
	end
	p("Hull", V3(3, 1.4, 8), 0, 0.3, 0, RGB(184, 111, 80))
	p("HullBow", V3(2, 1.4, 2), 0, 0.3, -4.2, RGB(184, 111, 80))
	p("HullTrim", V3(3.2, 0.4, 8.2), 0, 1.1, 0, RGB(115, 62, 57))
	p("Deck", V3(2.4, 0.2, 7.4), 0, 1.05, 0, RGB(228, 166, 114))
	p("Mast", V3(0.4, 10, 0.4), 0, 6, -0.5, RGB(115, 62, 57), Mat.Wood)
	p("Boom", V3(0.3, 0.3, 4.6), 0, 2.4, 1.6, RGB(115, 62, 57), Mat.Wood)
	p("Sail", V3(0.2, 7.4, 4.2), 0.25, 6.2, 1.5, RGB(255, 255, 255), Mat.Fabric)
	p("SailStripe", V3(0.25, 1, 4.2), 0.3, 5, 1.5, sail, Mat.Fabric)
	p("Flag", V3(0.1, 0.6, 1.2), 0, 11.2, -0.1, sail, Mat.Fabric)
end

local function buildIsland(parent)
	local m = folder(parent, "IslandAndSea")
	local shadow = { CastShadow = false }

	-- the castle's rock: under the walls
	part(m, "IslandRock", V3(256, -6 - ISLAND_FLOOR, CASTLE_ROCK_S + 128), CFrame.new(0, (ISLAND_FLOOR - 6) / 2, (CASTLE_ROCK_S - 128) / 2), ISLE.ROCK2, Mat.Slate, shadow)
	wallFootRocks(m)

	-- the island, one pixel (CELL studs) at a time: work out what every
	-- cell is, then join neighbouring cells of the same kind into as few
	-- big blocks as possible
	local NX = math.floor((GRID_X1 - GRID_X0) / CELL)
	local NZ = math.floor((GRID_Z1 - GRID_Z0) / CELL)
	local grid = {}
	local function cellPos(i, j)
		return GRID_X0 + (i - 0.5) * CELL, GRID_Z0 + (j - 0.5) * CELL
	end
	for j = 1, NZ do
		local row = {}
		for i = 1, NX do
			local x, z = cellPos(i, j)
			local L = isleLevel(x, z)
			-- (no need for grass under the castle's rock, or sand under the Spire's)
			if L == 3 and math.abs(x) < 125 and z > -125 and z < CASTLE_ROCK_S - 3 then
				L = -1
			elseif L == 2 and (x * x + (z - SPIRE_ISLE_Z) ^ 2) < 86 * 86 then
				L = -1
			end
			row[i] = L
		end
		grid[j] = row
	end
	local LAYERS = {
		[3] = { name = "Grass", top = TERRACE1_TOP, capT = 1.4, body = ISLE.DIRT, cap = ISLE.GRASS },
		[2] = { name = "Beach", top = BEACH_TOP, capT = 1, body = ISLE.SAND2, cap = ISLE.SAND },
		[1] = { name = "ShallowBed", top = SEA_Y - 3, capT = 0.6, body = ISLE.SAND2, cap = ISLE.SAND2 },
	}
	for L, lay in pairs(LAYERS) do
		local open = {}
		local function close(key, info, jEnd)
			local x0 = GRID_X0 + (info.i0 - 1) * CELL
			local x1 = GRID_X0 + info.i1 * CELL
			local z0 = GRID_Z0 + (info.j0 - 1) * CELL
			local z1 = GRID_Z0 + jEnd * CELL
			local cx, cz, w, d = (x0 + x1) / 2, (z0 + z1) / 2, x1 - x0, z1 - z0
			local bodyH = lay.top - lay.capT - ISLAND_FLOOR
			part(m, lay.name, V3(w, bodyH, d), CFrame.new(cx, ISLAND_FLOOR + bodyH / 2, cz), lay.body, Mat.Slate, shadow)
			part(m, lay.name .. "Top", V3(w, lay.capT, d), CFrame.new(cx, lay.top - lay.capT / 2, cz), lay.cap, Mat.Grass, shadow)
			if L == 1 then
				part(m, "Shallows", V3(w, 0.15, d), CFrame.new(cx, SEA_Y + 0.2, cz), ISLE.SHALLOW, Mat.SmoothPlastic, {
					Transparency = 0.15, CanCollide = false, CanQuery = false, CastShadow = false,
				})
			end
			_ = key
		end
		for j = 1, NZ + 1 do
			local runs = {}
			local row = grid[j]
			if row then
				local i = 1
				while i <= NX do
					if row[i] == L then
						local k = i
						while k + 1 <= NX and row[k + 1] == L do
							k = k + 1
						end
						runs[i .. ":" .. k] = { i0 = i, i1 = k }
						i = k + 1
					else
						i = i + 1
					end
				end
			end
			local nextOpen = {}
			for key, run in pairs(runs) do
				local was = open[key]
				nextOpen[key] = { i0 = run.i0, i1 = run.i1, j0 = was and was.j0 or j }
			end
			for key, info in pairs(open) do
				if not runs[key] then
					close(key, info, j - 1)
				end
			end
			open = nextOpen
		end
	end
	local function levelAtCell(x, z)
		local i = math.floor((x - GRID_X0) / CELL) + 1
		local j = math.floor((z - GRID_Z0) / CELL) + 1
		local row = grid[j]
		local L = row and row[i]
		if L == -1 then
			return isleLevel(x, z)
		end
		return L or 0
	end

	-- rocky stretches of coast, and white foam lapping at the beach
	for j = 2, NZ - 1 do
		for i = 2, NX - 1 do
			if grid[j][i] == 2 then
				local x, z = cellPos(i, j)
				local wet = grid[j][i - 1] == 1 or grid[j][i + 1] == 1 or grid[j - 1][i] == 1 or grid[j + 1][i] == 1
					or grid[j][i - 1] == 0 or grid[j][i + 1] == 0 or grid[j - 1][i] == 0 or grid[j + 1][i] == 0
				if wet and not nearMushroomHouse(x, z) then
					local th = math.atan2(z - ISLE_CZ, x - ISLE_CX)
					local rocky = (math.sin(3 * th + 0.3) > 0.55 or math.sin(5 * th + 2) > 0.85) and not nearStairs(x, z)
					if rocky and rnd() < 0.8 then
						for _ = 1, 1 + math.floor(rnd() * 2) do
							local s = 2.5 + rnd() * 3.5
							local p = V3(x + (rnd() - 0.5) * CELL, BEACH_TOP - 1 + s * 0.35, z + (rnd() - 0.5) * CELL)
							part(m, "CoastRock", V3(s * 1.3, s, s * 1.1), CFrame.new(p) * CFrame.Angles(math.rad((rnd() - 0.5) * 20), rnd() * 3, math.rad((rnd() - 0.5) * 20)), (rnd() < 0.5) and ISLE.ROCK2 or ISLE.ROCK3, Mat.Slate)
						end

					end
				end
			end
		end
	end

	-- The waves: smooth rings of white foam following the whole coastline
	-- (not the pixel steps of the beach, the true curve under them). Each
	-- ring starts out in the deep blue and the whole ring rolls in together,
	-- breaking on the sand and fading - then loops. Two rings, half a cycle
	-- apart, so there's always a wave on its way. LobbyFX moves them.
	local function waveRing(center, radiusAt, gap, skipAt)
		for ring = 0, 1 do
			local n = 0
			local th = -math.pi
			while th < math.pi do
				local function at(a, off)
					local r = radiusAt(a) + (off or 0)
					return V3(center.X + math.cos(a) * r, SEA_Y + 0.4, center.Z + math.sin(a) * r)
				end
				local p0 = at(th)
				local step = 2 / math.max(radiusAt(th), 1)
				local p1 = at(th + step)
				local mid = (p0 + p1) / 2
				local tangent = (p1 - p0).Unit
				local inward = V3(tangent.Z, 0, -tangent.X)
				if inward:Dot(center - mid) < 0 then
					inward = -inward
				end
				-- (uneven: broken into sets with gaps, each stretch arriving at its own
				-- moment and from its own distance, like real surf)
				local broken = math.sin(th * 23 + ring * 2.1) > 0.55 or math.sin(th * 9 + ring) > 0.8
				local myGap = gap * (0.8 + 0.25 * math.sin(th * 5 + ring * 1.7) + 0.1 * math.sin(th * 17))
				local myPhase = ring * 180 + 55 * math.sin(th * 7 + ring) + 35 * math.sin(th * 13 + 2)
				if not (skipAt and skipAt(mid)) and not broken and rnd() > 0.2 then
					-- chunky square blocks of foam, snapped to a pixel grid, a bit
					-- ragged, with little bubbles trailing behind
					local function blob(p, size, tr)
						local q = V3(math.floor(p.X / 0.5 + 0.5) * 0.5, SEA_Y + 0.4, math.floor(p.Z / 0.5 + 0.5) * 0.5)
						local foam = part(m, "Foam", V3(size, 0.25, size), CFrame.new(q), ISLE.FOAM, Mat.SmoothPlastic, {
							CanCollide = false, CanQuery = false, CastShadow = false, Transparency = tr,
						})
						foam:SetAttribute("WaveMode", "drift")
						foam:SetAttribute("WaveDir", inward)
						foam:SetAttribute("WaveAmp", myGap)
						foam:SetAttribute("WaveSpeed", 0.1)
						foam:SetAttribute("Phase", myPhase)
						CollectionService:AddTag(foam, "Wave")
					end
					local start = mid - inward * myGap
					blob(start + inward * ((rnd() - 0.5) * 1.6), 1.2 + math.floor(rnd() * 4) * 0.4, 0)
					for _ = 1, math.floor(rnd() * 3) do
						blob(start - inward * (1 + rnd() * 3) + tangent * ((rnd() - 0.5) * 3), 0.5 + rnd() * 0.6, 0.15 + rnd() * 0.3)
					end
					n = n + 1
				end
				th = th + step
			end
		end
	end
	-- round the main island (where the beach meets the water)...
	waveRing(V3(ISLE_CX, 0, ISLE_CZ), function(a)
		return EDGE_BEACH[edgeBin(a)] + 1
	end, 26, function(p)
		-- (not across the channel to the Spire, where the beach stops short)
		return p.Z < -175
	end)
	-- ...and round the Spire's islet
	waveRing(V3(0, 0, SPIRE_ISLE_Z), function(a)
		return spireBeachR(a) + 1
	end, 18)

	-- the sea: one big flat sheet (four, as parts can't be bigger than 2048)
	for _, t in ipairs({ { -750, -835 }, { 750, -835 }, { -750, 615 }, { 750, 615 } }) do
		part(m, "Sea", V3(1500, 1, 1450), CFrame.new(t[1], SEA_Y - 0.5, t[2]), ISLE.SEA, Mat.SmoothPlastic, {
			CanCollide = false, CanQuery = false, CastShadow = false,
		})
	end
	-- sparkles on the water, twinkling in and out
	for _ = 1, 130 do
		local a = rnd() * math.pi * 2
		local d = 150 + rnd() * 650
		local x, z = math.cos(a) * d, ISLE_CZ + math.sin(a) * d
		if isleLevel(x, z) == 0 then
			local w = 1.5 + rnd() * 3.5
			local sp = part(m, "Sparkle", V3(w, 0.1, 0.5), CFrame.new(x, SEA_Y + 0.08, z), ISLE.FOAM, Mat.SmoothPlastic, { CanCollide = false, CanQuery = false, CastShadow = false })
			sp:SetAttribute("PulseSpeed", 0.35 + rnd() * 0.5)
			sp:SetAttribute("PulseMin", 0.1)
			sp:SetAttribute("PulseMax", 1)
			sp:SetAttribute("Phase", rnd() * 360)
			CollectionService:AddTag(sp, "Pulse")
		end
	end

	-- little "~" wave crests out on the sea, drifting in towards the island
	-- and fading in and out as they go, like the water in old 8-bit games
	for _ = 1, 150 do
		local a = rnd() * math.pi * 2
		local d = 110 + rnd() * 600
		local x, z = math.cos(a) * d, ISLE_CZ + math.sin(a) * d
		if isleLevel(x, z) == 0 and isleLevel(x - math.cos(a) * 16, z - math.sin(a) * 16) == 0 then
			local dir = V3(-math.cos(a), 0, -math.sin(a)) -- (towards the island)
			local at = V3(x, SEA_Y + 0.1, z)
			local cf = CFrame.lookAt(at, at + dir)
			local phase, speed = rnd() * 360, 0.08 + rnd() * 0.05
			for k, piece in ipairs({ { V3(5.5, 0.2, 1), CFrame.new() }, { V3(2.8, 0.2, 1), CFrame.new(3.8, 0, 1) } }) do
				local crest = part(m, "WaveCrest", piece[1], cf * piece[2], ISLE.FOAM, Mat.SmoothPlastic, {
					CanCollide = false, CanQuery = false, CastShadow = false, Transparency = (k - 1) * 0.2,
				})
				crest:SetAttribute("WaveMode", "drift")
				crest:SetAttribute("WaveDir", dir)
				crest:SetAttribute("WaveAmp", 14)
				crest:SetAttribute("WaveSpeed", speed)
				crest:SetAttribute("Phase", phase)
				CollectionService:AddTag(crest, "Wave")
			end
		end
	end

	-- the Spire's islet: its crag goes down into the sea, with rocks round it
	roundMountain(m, 0, SPIRE_Z, SPIRE_ROCK_R + 2, -26, 4)
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2 + rnd() * 0.2
		local s = 3.5 + rnd() * 4.5
		part(m, "SpireBoulder", V3(s * 1.4, s, s * 1.1), CFrame.new(math.sin(a) * (90 + rnd() * 5), BEACH_TOP - 0.5 + s * 0.3, SPIRE_Z + math.cos(a) * (90 + rnd() * 5)) * CFrame.Angles(0, rnd() * 3, math.rad((rnd() - 0.5) * 16)), (rnd() < 0.5) and ISLE.ROCK2 or ISLE.ROCK3, Mat.Slate)
	end

	-- stone stairs from the drawbridge down to the grass, a sandy path to the
	-- beach with a few steps down, and a wooden pier out over the water
	local STEP_C, STEP_C2, WALL_C = RGB(192, 203, 220), RGB(139, 155, 180), RGB(90, 105, 136)
	local function flight(xc, zStart, yTop, yBottom, maxRise, tread)
		local n = math.ceil((yTop - yBottom) / maxRise)
		local rise = (yTop - yBottom) / n
		for i = 1, n - 1 do
			local top = yTop - i * rise
			local z = zStart + (i - 0.5) * tread
			part(m, "BeachStair", V3(STAIR_HALF * 2, top - yBottom + 1, tread + 0.02), CFrame.new(xc, (top + yBottom - 1) / 2, z), (i % 2 == 0) and STEP_C or STEP_C2, Mat.Slate)
		end
		local zEnd = zStart + (n - 1) * tread
		for _, sx in ipairs({ -1, 1 }) do
			local x = xc + sx * (STAIR_HALF + 0.6)
			local a, b = V3(x, yTop + 0.8, zStart), V3(x, yBottom + 0.8 + rise, zEnd)
			part(m, "StairWall", V3(1.2, 2.4, (b - a).Magnitude + 1.2), CFrame.lookAt((a + b) / 2, b), WALL_C, Mat.Slate)
		end
		return zEnd
	end
	-- The way down from the south gate, made to feel cosy: a paved landing
	-- outside the gate with lanterns and flower boxes, then wide, shallow
	-- steps of warm cream stone in two gentle flights with a resting landing
	-- between them, low stone walls with a wooden handrail either side,
	-- lanterns, flowers and bushes at the bottom.
	local zAt
	do
		local HW = 9 -- half the width of the stairs
		local CREAM, CREAM2, EDGE = RGB(234, 212, 170), RGB(232, 183, 150), RGB(194, 133, 105)
		local STONE, STONE2, WOOD, WOOD2 = RGB(139, 155, 180), RGB(90, 105, 136), RGB(184, 111, 80), RGB(115, 62, 57)
		local GLOW = RGB(254, 231, 97)
		local nc = { CanCollide = false }
		local base = TERRACE1_TOP
		local function lantern(x, y, z)
			part(m, "LanternPost", V3(0.8, 4.4, 0.8), CFrame.new(x, y + 2.2, z), WOOD2, Mat.Wood)
			part(m, "LanternBox", V3(1.3, 1.3, 1.3), CFrame.new(x, y + 5, z), GLOW, Mat.Neon)
			part(m, "LanternRoof", V3(1.8, 0.4, 1.8), CFrame.new(x, y + 5.85, z), WOOD2, Mat.Wood)
			part(m, "LanternFoot", V3(1.4, 0.6, 1.4), CFrame.new(x, y + 0.3, z), STONE2, Mat.Slate)
		end
		local function flowerBox(x, y, z, alongZ)
			part(m, "FlowerBox", alongZ and V3(1.4, 0.8, 3.4) or V3(3.4, 0.8, 1.4), CFrame.new(x, y + 0.4, z), WOOD, Mat.WoodPlanks)
			part(m, "FlowerLeaves", alongZ and V3(1.1, 0.5, 3) or V3(3, 0.5, 1.1), CFrame.new(x, y + 1, z), ISLE.GRASS2, Mat.Grass, nc)
			for k = -1, 1 do
				local c = ({ RGB(228, 59, 68), RGB(254, 231, 97), RGB(246, 117, 122) })[k + 2]
				local o = alongZ and V3(0, 0, k * 1) or V3(k * 1, 0, 0)
				part(m, "Flower", V3(0.55, 0.55, 0.55), CFrame.new(V3(x, y + 1.45, z) + o), c, Mat.SmoothPlastic, nc)
			end
		end
		-- the landing outside the gate, paved, level with the gateway
		local z0, z1 = SOUTH_WALL, GATE_LANDING_Z
		part(m, "GateLanding", V3(HW * 2 + 8, -0.4 - base, z1 - z0), CFrame.new(0, (base - 0.4) / 2, (z0 + z1) / 2), STONE, Mat.Slate)
		part(m, "GateLandingPaving", V3(HW * 2 + 8, 0.4, z1 - z0), CFrame.new(0, -0.2, (z0 + z1) / 2), CREAM, Mat.Slate)
		for x = -HW - 1, HW + 1, 4 do
			part(m, "PavingLine", V3(0.2, 0.42, z1 - z0), CFrame.new(x, -0.2, (z0 + z1) / 2), CREAM2, Mat.Slate, nc)
		end
		for _, sx in ipairs({ -1, 1 }) do
			local x = sx * (HW + 3.4)
			local w0 = SOUTH_WALL + 6 -- (clear of the gateway's piers)
			part(m, "LandingWall", V3(1.2, 2.2, z1 - w0), CFrame.new(x, 1.1, (w0 + z1) / 2), STONE, Mat.Slate)
			part(m, "LandingWallCap", V3(1.6, 0.4, z1 - w0 + 0.4), CFrame.new(x, 2.4, (w0 + z1) / 2), STONE2, Mat.Slate)
			flowerBox(x, 2.6, w0 + 3, true)
			lantern(sx * (HW + 1.5), 0, z1 - 1.2)
		end
		-- two flights of wide, shallow steps
		local RISE, TREAD, STEPS = 0.5, 1.4, 13
		local function stairFlight(zStart, yTop)
			for i = 1, STEPS do
				local top = yTop - i * RISE
				local za = zStart + (i - 1) * TREAD
				part(m, "GateStair", V3(HW * 2 + 2.4, top - base, TREAD + 0.02), CFrame.new(0, (top + base) / 2, za + TREAD / 2), (i % 2 == 0) and CREAM or CREAM2, Mat.Slate)
				part(m, "GateStairEdge", V3(HW * 2, 0.14, 0.3), CFrame.new(0, top + 0.05, za + TREAD - 0.15), EDGE, Mat.Slate, nc)
				-- solid stone along both sides, closing off the ends of the steps
				for _, sx in ipairs({ -1, 1 }) do
					part(m, "StairSide", V3(1.4, top - base - 0.02, TREAD + 0.04), CFrame.new(sx * (HW + 0.65), (top - 0.02 + base) / 2, za + TREAD / 2), STONE, Mat.Slate)
					-- a few darker stones set into the side wall
					if top - base > 3 and rnd() < 0.45 then
						local by = base + 1 + rnd() * (top - base - 2.5)
						part(m, "SideBrick", V3(0.3, 1 + rnd() * 0.6, 1.6 + rnd() * 1.4), CFrame.new(sx * (HW + 1.45), by, za + TREAD / 2), STONE2, Mat.Slate, nc)
					end
				end
			end
			local zEnd = zStart + STEPS * TREAD
			local yEnd = yTop - STEPS * RISE
			for _, sx in ipairs({ -1, 1 }) do
				local x = sx * (HW + 0.6)
				local a, b = V3(x, yTop + 1.1, zStart), V3(x, yEnd + 1.1, zEnd)
				local len = (b - a).Magnitude
				part(m, "StairWall", V3(1.2, 2.2, len + 1), CFrame.lookAt((a + b) / 2, b), STONE, Mat.Slate)
				part(m, "StairWallCap", V3(1.6, 0.4, len + 1.2), CFrame.lookAt((a + b) / 2 + V3(0, 1.3, 0), b + V3(0, 1.3, 0)), STONE2, Mat.Slate)
				-- the wooden handrail on little posts
				local ra, rb = a + V3(0, 3, 0), b + V3(0, 3, 0)
				part(m, "Handrail", V3(0.5, 0.4, len), CFrame.lookAt((ra + rb) / 2, rb), WOOD, Mat.WoodPlanks)
				for k = 0, 3 do
					local p = a:Lerp(b, (k + 0.5) / 4)
					part(m, "HandrailPost", V3(0.35, 1.8, 0.35), CFrame.new(p + V3(0, 2.2, 0)), WOOD2, Mat.Wood, nc)
				end
			end
			return zEnd, yEnd
		end
		local zA, yA = stairFlight(z1, 0)
		-- the resting landing, with a lantern and flowers either side
		local restLen = 8
		part(m, "RestLanding", V3(HW * 2 + 2.4, yA - base, restLen), CFrame.new(0, (yA + base) / 2, zA + restLen / 2), CREAM, Mat.Slate)
		for x = -HW, HW, 3 do
			part(m, "PavingLine", V3(0.2, 0.02, restLen), CFrame.new(x, yA + 0.01, zA + restLen / 2), CREAM2, Mat.Slate, nc)
		end
		for _, sx in ipairs({ -1, 1 }) do
			local x = sx * (HW + 0.6)
			-- (stone down the sides, like the flights)
			part(m, "RestSide", V3(1.4, yA - base - 0.02, restLen + 0.04), CFrame.new(sx * (HW + 0.65), (yA - 0.02 + base) / 2, zA + restLen / 2), STONE, Mat.Slate)
			for k = 0, 1 do
				part(m, "SideBrick", V3(0.3, 1.2, 2.2), CFrame.new(sx * (HW + 1.45), base + 1.5 + k * 2.6, zA + 2 + k * 3.5), STONE2, Mat.Slate, nc)
			end
			part(m, "RestWall", V3(1.2, 2.2, restLen + 1), CFrame.new(x, yA + 1.1, zA + restLen / 2), STONE, Mat.Slate)
			part(m, "RestWallCap", V3(1.6, 0.4, restLen + 1.2), CFrame.new(x, yA + 2.4, zA + restLen / 2), STONE2, Mat.Slate)
			flowerBox(x, yA + 2.6, zA + restLen / 2 - 1.5, true)
			lantern(sx * (HW - 1), yA, zA + restLen / 2 + 2)
		end
		local zB = stairFlight(zA + restLen, yA)
		-- bushes and flowers along the foot of the stairs' sides
		for _, sx in ipairs({ -1, 1 }) do
			for z = z1 + 3, zB - 6, 9 do
				blockBush(m, sx * (HW + 3.2 + rnd() * 1.5), z + rnd() * 3, 0.8 + rnd() * 0.4, base)
			end
		end
		-- at the bottom: lanterns, bushes and flowers either side
		for _, sx in ipairs({ -1, 1 }) do
			lantern(sx * (HW + 3), base, zB + 1.5)
			blockBush(m, sx * (HW + 6.5), zB - 3, 1, base)
			blockBush(m, sx * (HW + 5.5), zB - 12, 0.8, base)
			for _ = 1, 6 do
				local fx, fz = sx * (HW + 5) + (rnd() - 0.5) * 5, zB + 4 + (rnd() - 0.5) * 5
				part(m, "FlowerStem", V3(0.25, 0.8, 0.25), CFrame.new(fx, base + 0.4, fz), ISLE.GRASS2, Mat.Grass, nc)
				part(m, "Flower", V3(0.6, 0.6, 0.6), CFrame.new(fx, base + 0.95, fz), FLOWER_COLORS[1 + math.floor(rnd() * #FLOWER_COLORS)], Mat.SmoothPlastic, nc)
			end
		end
		zAt = zB
	end
	local xEnd = PATH_END_X -- where the path reaches the cove
	local zGrassEnd = zAt
	while levelAtCell(xEnd, zGrassEnd + 1) == 3 do
		zGrassEnd = zGrassEnd + 1
	end
	-- the path across the grass: a worn dirt track that goes where you'd
	-- walk - straight down from the gate, bowing out a little, then sweeping
	-- round towards the cove and the pier in one easy bend. Its edges come
	-- and go a little, with darker trodden patches, pebbles and the odd flat
	-- stone, and grass tufts creeping in from the sides. Rows 1.5 studs deep.
	do
		local z0, z1 = zAt, zGrassEnd
		local L = z1 - z0
		-- the middle line: a smooth curve (a Bezier) from the stairs to the cove
		local P = { V3(0, 0, z0), V3(4, 0, z0 + 0.42 * L), V3(xEnd + 10, 0, z0 + 0.72 * L), V3(xEnd, 0, z1) }
		local line = {}
		for k = 0, 400 do
			local t = k / 400
			local u = 1 - t
			table.insert(line, P[1] * (u * u * u) + P[2] * (3 * u * u * t) + P[3] * (3 * u * t * t) + P[4] * (t * t * t))
		end
		local function midX(z)
			for k = 2, #line do
				if line[k].Z >= z then
					local a, b = line[k - 1], line[k]
					local f = (z - a.Z) / math.max(b.Z - a.Z, 1e-6)
					return a.X + (b.X - a.X) * f
				end
			end
			return xEnd
		end
		local DIRT, DIRT2 = RGB(184, 111, 80), RGB(194, 133, 105)
		local nc = { CanCollide = false, CanQuery = false }
		local left, right = 0, 0 -- how far each edge wanders in or out
		local y = TERRACE1_TOP + 0.15
		local z = z0
		while z < z1 do
			local zc = z + 0.75
			local cx = midX(zc)
			left = math.clamp(left + (rnd() - 0.5) * 1, -1.2, 1.5)
			right = math.clamp(right + (rnd() - 0.5) * 1, -1.2, 1.5)
			-- a good wide track, opening out as it reaches the steps to the beach
			local t = (zc - z0) / L
			local half = 7 + math.clamp((t - 0.75) / 0.25, 0, 1) * 1.2
			local xL, xR = cx - half - left, cx + half + right
			-- (only on grass - the island's, or the patch round the top of the
			-- beach steps - never hanging out over the sand)
			local function onGrass(x)
				return levelAtCell(x, zc) == 3 or (zc > z1 - 14 and math.abs(x - xEnd) < STAIR_HALF + 7)
			end
			while xL < xR - 1 and not onGrass(xL + 0.5) do
				xL = xL + 0.5
			end
			while xR > xL + 1 and not onGrass(xR - 0.5) do
				xR = xR - 0.5
			end
			if xR - xL > 1.5 then
				part(m, "BeachPath", V3(xR - xL, 0.3, 1.55), CFrame.new((xL + xR) / 2, y, zc), DIRT, Mat.Ground, nc)
				if rnd() < 0.3 and xR - xL > 5 then
					local pw = 1.5 + rnd() * 2.5
					part(m, "PathPatch", V3(pw, 0.3, 1.2 + rnd() * 1.2), CFrame.new(xL + pw / 2 + 0.5 + rnd() * math.max(0, xR - xL - pw - 1), y + 0.04, zc), DIRT2, Mat.Ground, nc)
				end
				if rnd() < 0.45 then
					local s2 = 0.35 + rnd() * 0.4
					part(m, "PathPebble", V3(s2, 0.25, s2), CFrame.new(xL + 0.5 + rnd() * (xR - xL - 1), y + 0.2, z + rnd() * 1.5), (rnd() < 0.5) and RGB(232, 183, 150) or RGB(115, 62, 57), Mat.Slate, nc)
				end
				if rnd() < 0.05 then
					part(m, "PathStone", V3(2 + rnd() * 1.5, 0.3, 1.4 + rnd()), CFrame.new(cx + (rnd() - 0.5) * 4, y + 0.1, zc) * CFrame.Angles(0, (rnd() - 0.5) * 0.6, 0), RGB(234, 212, 170), Mat.Slate, nc)
				end
				for _, ex in ipairs({ xL, xR }) do
					if rnd() < 0.35 and levelAtCell(ex, zc) == 3 then
						for k = 0, 1 + math.floor(rnd() * 2) do
							local h = 0.5 + rnd() * 0.6
							part(m, "PathTuft", V3(0.35, h, 0.35), CFrame.new(ex + (rnd() - 0.5) * 1.2, TERRACE1_TOP + h / 2, z + rnd() * 1.5), (k % 2 == 0) and ISLE.GRASS or ISLE.GRASS2, Mat.Grass, nc)
						end
					end
				end
			end
			z = z + 1.5
		end
	end
	-- where the path drops to the beach: steps edged with wooden logs, the
	-- treads packed dirt, with the grassy bank carried down either side
	do
		local n = 6
		local rise = (TERRACE1_TOP - BEACH_TOP) / n
		local TREAD, HALF = 1.6, 8 -- (as wide as the path where it arrives)
		local nc = { CanCollide = false }
		-- fill in the grass round the top of the steps, so the island's
		-- slanting pixel edge doesn't leave a bite of sand beside them
		local padZ0 = zGrassEnd - 14
		local padW = HALF * 2 + 14
		part(m, "GrassShoulder", V3(padW, TERRACE1_TOP - 1.4 - BEACH_TOP + 1, zGrassEnd - padZ0), CFrame.new(xEnd, (TERRACE1_TOP - 1.4 + BEACH_TOP - 1) / 2, (padZ0 + zGrassEnd) / 2), ISLE.DIRT, Mat.Ground)
		part(m, "GrassShoulderTop", V3(padW, 1.4, zGrassEnd - padZ0), CFrame.new(xEnd, TERRACE1_TOP - 0.7, (padZ0 + zGrassEnd) / 2), ISLE.GRASS, Mat.Grass)
		for i = 1, n - 1 do
			local top = TERRACE1_TOP - i * rise
			local za = zGrassEnd + (i - 1) * TREAD
			part(m, "LogStep", V3(HALF * 2, top - BEACH_TOP + 0.5, TREAD + 0.02), CFrame.new(xEnd, (top + BEACH_TOP - 0.5) / 2, za + TREAD / 2), RGB(184, 111, 80), Mat.Ground)
			part(m, "LogStepEdge", V3(HALF * 2, 0.6, 0.6), CFrame.new(xEnd, top - 0.1, za + TREAD - 0.3), RGB(115, 62, 57), Mat.Wood, nc)
			for _, sx in ipairs({ -1, 1 }) do
				part(m, "LogStepPeg", V3(0.5, 0.9, 0.5), CFrame.new(xEnd + sx * (HALF - 0.6), top + 0.05, za + TREAD + 0.05), RGB(62, 39, 49), Mat.Wood, nc)
				-- the bank either side, stepping down with the steps
				local bankTop = top + 1.2
				part(m, "StepBank", V3(2.4, bankTop - 1 - BEACH_TOP, TREAD + 0.04), CFrame.new(xEnd + sx * (HALF + 1.2), (bankTop - 1 + BEACH_TOP) / 2, za + TREAD / 2), ISLE.DIRT, Mat.Ground)
				part(m, "StepBankTop", V3(2.6, 1, TREAD + 0.06), CFrame.new(xEnd + sx * (HALF + 1.2), bankTop - 0.5, za + TREAD / 2), ISLE.GRASS, Mat.Grass)
				if rnd() < 0.6 then
					part(m, "PathTuft", V3(0.35, 0.8, 0.35), CFrame.new(xEnd + sx * (HALF + 0.6 + rnd()), bankTop + 0.4, za + rnd() * TREAD), ISLE.GRASS2, Mat.Grass, nc)
				end
			end
		end
		zAt = zGrassEnd + (n - 1) * TREAD
	end
	local zBeachEnd = zAt
	while levelAtCell(xEnd, zBeachEnd + 1) == 2 do
		zBeachEnd = zBeachEnd + 1
	end
	for _, sx in ipairs({ -1, 1 }) do
		local x = xEnd + sx * (STAIR_HALF + 2.5)
		part(m, "PierLampPost", V3(0.8, 6, 0.8), CFrame.new(x, BEACH_TOP + 3, zAt + 1), RGB(115, 62, 57), Mat.Wood)
		part(m, "PierLamp", V3(1.2, 1.2, 1.2), CFrame.new(x, BEACH_TOP + 6.4, zAt + 1), RGB(254, 231, 97), Mat.Neon)
		part(m, "PierLampCap", V3(1.6, 0.4, 1.6), CFrame.new(x, BEACH_TOP + 7.2, zAt + 1), RGB(62, 39, 49), Mat.Metal)
	end
	local p0, p1 = zBeachEnd - 10, zBeachEnd + 36
	local deckY = SEA_Y + 2.2
	part(m, "Pier", V3(8, 0.6, p1 - p0), CFrame.new(xEnd, deckY, (p0 + p1) / 2), RGB(184, 111, 80), Mat.WoodPlanks)
	for z = p0 + 2, p1, 4 do
		part(m, "PierPlankLine", V3(8.1, 0.62, 0.2), CFrame.new(xEnd, deckY, z), RGB(115, 62, 57), Mat.WoodPlanks, { CanCollide = false })
	end
	for z = p0 + 1, p1 - 1, 8 do
		for _, sx in ipairs({ -1, 1 }) do
			part(m, "PierPost", V3(0.9, 7, 0.9), CFrame.new(xEnd + sx * 3.8, deckY - 2.6, z), RGB(115, 62, 57), Mat.Wood)
			part(m, "PierRail", V3(0.3, 1.8, 0.3), CFrame.new(xEnd + sx * 3.8, deckY + 1.1, z), RGB(115, 62, 57), Mat.Wood)
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		part(m, "PierRailBar", V3(0.3, 0.3, p1 - p0), CFrame.new(xEnd + sx * 3.8, deckY + 1.8, (p0 + p1) / 2), RGB(184, 111, 80), Mat.WoodPlanks)
	end
	part(m, "PierCrate", V3(2, 2, 2), CFrame.new(xEnd + 2.2, deckY + 1.3, p1 - 3) * CFrame.Angles(0, 0.3, 0), RGB(228, 166, 114), Mat.WoodPlanks)
	part(m, "PierBarrel", V3(1.8, 2.2, 1.8), CFrame.new(xEnd - 2.3, deckY + 1.4, p1 - 5), RGB(184, 111, 80), Mat.WoodPlanks)

	-- the village: cottages among the trees
	for _, h in ipairs(ISLE_HOUSES) do
		isleHouse(m, CFrame.new(h[1], TERRACE1_TOP, h[2]) * CFrame.Angles(0, math.rad(h[3]), 0), h[4])
	end
	-- trees: palms on the beach and along the shore, leafy trees further in
	local planted, tries = 0, 0
	while planted < 150 and tries < 4000 do
		tries = tries + 1
		local x = GRID_X0 + rnd() * (GRID_X1 - GRID_X0)
		local z = -200 + rnd() * 660
		local L = levelAtCell(x, z)
		local ok = (L == 2 or L == 3) and castleRectDist(x, z) > 12 and not nearStairs(x, z) and not nearMushroomHouse(x, z)
			and not nearHouse(x, z, 13) and not (math.abs(x) < 24 and z < -110)
		if ok and L == 2 then
			-- (not right at the water's edge)
			ok = levelAtCell(x + 6, z) >= 2 and levelAtCell(x - 6, z) >= 2 and levelAtCell(x, z + 6) >= 2 and levelAtCell(x, z - 6) >= 2
				and (x * x + (z - SPIRE_ISLE_Z) ^ 2) > 95 * 95
		end
		if ok then
			planted = planted + 1
			local nearShore = L == 2 or levelAtCell(x + 18, z) < 3 or levelAtCell(x - 18, z) < 3 or levelAtCell(x, z + 18) < 3 or levelAtCell(x, z - 18) < 3
			local y = (L == 2) and BEACH_TOP or TERRACE1_TOP
			if nearShore and rnd() < 0.85 then
				palmTree(m, x, y, z, 1.25 + rnd() * 0.4, rnd() * math.pi * 2)
			elseif rnd() < 0.75 then
				farmTree(m, x, z, 0.6 + rnd() * 0.4, y)
			else
				blockBush(m, x, z, 0.9 + rnd() * 0.6, y)
			end
		end
	end

	-- islets out at sea, one with a lighthouse, and boats sailing between
	islet(m, -470, -140, 26, SEA_Y + 12, 2)
	islet(m, 520, 190, 34, SEA_Y + 14, 2)
	islet(m, -360, 560, 20, SEA_Y + 9, 1)
	islet(m, 380, -480, 24, SEA_Y + 10, 1)
	do
		local lx, lz, base = 520, 190, SEA_Y + 14
		for k = 0, 5 do
			cylinder(m, "Lighthouse", 5, 9 - k * 0.5, CFrame.new(lx + 12, base + 2.5 + k * 5, lz - 8), (k % 2 == 0) and ISLE.FOAM or RGB(228, 59, 68), Mat.Plastic)
		end
		cylinder(m, "LighthouseDeck", 0.8, 8.5, CFrame.new(lx + 12, base + 30.4, lz - 8), RGB(58, 68, 102), Mat.Metal)
		local lamp = cylinder(m, "LighthouseLamp", 3.4, 5, CFrame.new(lx + 12, base + 32.5, lz - 8), RGB(254, 231, 97), Mat.Neon)
		lamp:SetAttribute("PulseSpeed", 0.5)
		lamp:SetAttribute("PulseMin", 0)
		lamp:SetAttribute("PulseMax", 0.45)
		CollectionService:AddTag(lamp, "Pulse")
		coneRoof(m, V3(lx + 12, base + 34.2, lz - 8), 3.6, 5, RGB(190, 74, 47), 5)
	end
	sailboat(m, -430, 30, 0.6, RGB(228, 59, 68), 0)
	sailboat(m, 380, -150, -0.9, RGB(18, 78, 137), 120)
	sailboat(m, 150, 540, 2.2, RGB(254, 174, 52), 240)
	sailboat(m, -220, -330, 1.3, RGB(62, 137, 72), 60)

	-- falling in the deep sea washes you back to the spawn
	local spawnAt = CFrame.new(0, 4, 34)
	local function washBack(hit)
		local char = hit and hit.Parent
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if hum and root and hum.Health > 0 and not char:GetAttribute("WashedBack") then
			char:SetAttribute("WashedBack", true)
			root.AssemblyLinearVelocity = Vector3.zero
			root.CFrame = spawnAt
			task.delay(1, function()
				char:SetAttribute("WashedBack", nil)
			end)
		end
	end
	for _, t in ipairs({ { -750, -835 }, { 750, -835 }, { -750, 615 }, { 750, 615 } }) do
		local splash = part(m, "SeaReturn", V3(1500, 2, 1450), CFrame.new(t[1], SEA_Y - 6, t[2]), RGB(255, 255, 255), Mat.SmoothPlastic, {
			Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false,
		})
		splash.Touched:Connect(washBack)
	end
	-- (and as a last safety net, anything far below is caught too)
	local kill = part(m, "VoidKillZone", V3(2048, 4, 2048), CFrame.new(0, -240, -60), RGB(255, 255, 255), Mat.SmoothPlastic, {
		Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false,
	})
	kill.Touched:Connect(washBack)
end

local function buildCastle(parent)
	local m = folder(parent, "Castle")
	buildKeep(m)
	buildSouthGate(m)
	-- turrets hanging off the outside of the walls
	for _, z in ipairs({ -50, 30, 110 }) do
		bartizan(m, V3(-121, 0, z), V3(-1, 0, 0))
		bartizan(m, V3(121, 0, z), V3(1, 0, 0))
	end
	for _, x in ipairs({ -70, 70 }) do
		bartizan(m, V3(x, 0, SOUTH_WALL + 3), V3(0, 0, 1))
	end
	for _, x in ipairs({ -76, 76 }) do
		bartizan(m, V3(x, 0, -121), V3(0, 0, -1))
	end
	buildGreatHall(m)
	buildFountain(m)
	buildPetSanctuary(m)
	buildFarmField(m)
	buildRiver(m)
	buildFarm(m)
end

----------------------------------------------------------------------
-- Gloomgut's Hollow: the Spire's first boss arena (floor 1)
----------------------------------------------------------------------
-- Built far away from the lobby on its own floating island; the Spire menu
-- teleports you here. A huge round colosseum floor with rings of towering
-- ancient pillars, taken over by slime: glowing slime runs in channels cut
-- into the floor, pools in the boss pit at the centre, drips down every
-- pillar, pours off a cliff as a waterfall and fills a moat round the
-- floor. Beyond the moat grows a lush, colourful fantasy wilderness. You
-- arrive at a fog gate on the south side, which is also the way out.
local ARENA_CENTER = V3(0, 0, 2600)
local SLIME = RGB(105, 210, 70)
local SLIME_DEEP = RGB(70, 170, 60)
local ARENA_STONE = RGB(150, 156, 160)
local ARENA_STONE_DARK = RGB(112, 118, 124)
local CANOPY = { RGB(70, 170, 80), RGB(200, 80, 170), RGB(240, 150, 60), RGB(60, 190, 170), RGB(120, 200, 70) }

local function buildSlimeArena()
	local old = Workspace:FindFirstChild("SlimeArena")
	if old then
		old:Destroy()
	end
	local m = Instance.new("Model")
	m.Name = "SlimeArena"
	local C = ARENA_CENTER
	local function at(x, y, z)
		return C + V3(x, y, z)
	end
	local function onRing(r, a, y)
		return C + V3(math.sin(a) * r, y, math.cos(a) * r)
	end
	local noCol = { CanCollide = false, CanQuery = false, CastShadow = false }
	local function slimeGlow(p, speed)
		p:SetAttribute("PulseSpeed", speed or 0.5)
		p:SetAttribute("PulseMin", 0.05)
		p:SetAttribute("PulseMax", 0.35)
		p:SetAttribute("Phase", rnd() * 360)
		CollectionService:AddTag(p, "Pulse")
	end
	-- a flat ring made of short segments (for bands and channels on the floor)
	local function ringBand(name, r, width, y, thick, color, mat, segs, extra)
		for i = 0, segs - 1 do
			local a = (i + 0.5) / segs * math.pi * 2
			local p = onRing(r, a, y)
			local len = 2 * r * math.sin(math.pi / segs) + 0.3
			part(m, name, V3(len, thick, width), CFrame.lookAt(p, p + V3(math.cos(a), 0, -math.sin(a))) * CFrame.Angles(0, math.pi / 2, 0), color, mat, extra)
		end
	end

	-- The island and its rocky underside, sinking into its own mist.
	--
	-- The edge is the part you actually stand next to, so it can't read as a
	-- disc someone cut out with scissors. The ground is a clean circle, but
	-- everything around its rim is deliberately not: rock breaks through the
	-- grass at different heights, chunks of turf hang out past the edge, and the
	-- underside starts flush with the top and tapers away beneath it, so there's
	-- no flat cut face anywhere along the silhouette.
	cylinder(m, "ArenaGround", 8, 400, CFrame.new(at(0, -4, 0)), RGB(96, 196, 86), Mat.Grass)
	local under = { { 400, -6, -30 }, { 348, -30, -60 }, { 266, -60, -96 }, { 166, -96, -132 }, { 72, -132, -164 } }
	for i, u in ipairs(under) do
		cylinder(m, "ArenaUnderside", u[2] - u[3], u[1], CFrame.new(at(0, (u[2] + u[3]) / 2, 0)), rockColor(i / #under), Mat.Slate, { CastShadow = false })
	end

	-- Rock breaking through the rim. Evenly spaced blocks of a similar size read
	-- as a fence, so these come in clusters with gaps between them, and every
	-- few are a big fang that drops well below the rest.
	-- only: nothing can walk into it and nothing needs testing against it
	-- all of this sits beyond the invisible wall at the edge, so it is scenery
	local RIM_DECOR = { CanCollide = false, CanQuery = false, CastShadow = false }
	local function taperR(depth) -- roughly where the island's underside sits at this depth
		return math.max(70, 199 - math.max(0, depth - 5) * 0.86)
	end
	local rimAngles = {}
	for i = 0, 29 do
		local base = (i + rnd() * 0.5) / 30 * math.pi * 2
		if rnd() > 0.12 then -- a few gaps where the bare cliff shows through
			for _ = 1, 1 + math.floor(rnd() * 3) do -- a cluster, not a single tooth
				rimAngles[#rimAngles + 1] = base + (rnd() - 0.5) * 0.11
			end
		end
	end
	for _, a in ipairs(rimAngles) do
		local fang = rnd() < 0.18
		local h = fang and (46 + rnd() * 30) or (13 + rnd() * 24)
		local top = 2.2 - rnd() * 4.5 -- some stand proud of the grass, some sit under it
		local r = 196 + rnd() * 8
		local p = onRing(r, a, top - h / 2)
		part(m, "RimCrag", V3(9 + rnd() * 24, h, 8 + rnd() * 9), CFrame.new(p)
			* CFrame.Angles(math.rad(3 + rnd() * 12), a, math.rad((rnd() - 0.5) * 22)),
			rockColor(rnd() * 0.4), Mat.Slate, RIM_DECOR)
	end
	-- turf hanging out over the drop, so the grass line isn't a drawn circle
	for i = 0, 47 do
		local a = (i + rnd() * 0.8) / 48 * math.pi * 2
		local out = 2 + rnd() * 7
		local p = onRing(199 + out * 0.5, a, -1 - rnd() * 0.6)
		part(m, "RimTurf", V3(12 + rnd() * 18, 2.6 + rnd() * 1.8, 7 + out), CFrame.new(p)
			* CFrame.Angles(math.rad(-2 - rnd() * 5), a, math.rad((rnd() - 0.5) * 8)),
			RGB(92, 190, 82):Lerp(RGB(74, 158, 68), rnd()), Mat.Grass, RIM_DECOR)
	end
	-- boulders and broken slabs resting against the slope below, half buried in
	-- it rather than hanging in mid-air, thinning out as the mist takes over
	for _ = 1, 54 do
		local a = rnd() * math.pi * 2
		local depth = 8 + rnd() * rnd() * 54 -- most of them near the top
		local size = 6 + rnd() * 15
		local p = onRing(taperR(depth) + size * 0.25, a, -depth)
		if rnd() < 0.4 then
			ball(m, "RimBoulder", size, CFrame.new(p), rockColor(0.25 + depth / 90), Mat.Slate, RIM_DECOR)
		else
			part(m, "RimSlab", V3(size * 1.7, size * 0.65, size), CFrame.new(p)
				* CFrame.Angles(math.rad((rnd() - 0.5) * 46), a + (rnd() - 0.5) * 0.6, math.rad((rnd() - 0.5) * 46)),
				rockColor(0.25 + depth / 90), Mat.Slate, RIM_DECOR)
		end
	end
	-- and a few slabs breaking the rings where the underside steps in
	for _ = 1, 26 do
		local a = rnd() * math.pi * 2
		local step = ({ 30, 60, 96 })[1 + math.floor(rnd() * 3)]
		local size = 10 + rnd() * 18
		local p = onRing(taperR(step) + size * 0.2, a, -step + (rnd() - 0.5) * 10)
		part(m, "RimSlab", V3(size * 1.5, size * 0.8, size * 0.9), CFrame.new(p)
			* CFrame.Angles(math.rad((rnd() - 0.5) * 30), a, math.rad((rnd() - 0.5) * 30)),
			rockColor(0.4 + step / 140), Mat.Slate, RIM_DECOR)
	end
	-- invisible walls at the edge so nobody walks off the island
	for i = 0, 23 do
		local a = (i + 0.5) / 24 * math.pi * 2
		local p = onRing(192, a, 20)
		part(m, "EdgeWall", V3(52, 40, 2), CFrame.lookAt(p, p + V3(math.sin(a), 0, math.cos(a))), RGB(255, 255, 255), Mat.SmoothPlastic, {
			Transparency = 1, CanQuery = false, CastShadow = false,
		})
	end
	-- Mist below: the island sits in a sea of cloud. Two see-through layers
	-- over a solid cloud floor, with big soft cloud puffs heaped round the
	-- island's edge so there's never a hard line where the island ends.
	local MIST = RGB(214, 220, 232)
	for _, layer in ipairs({ { -24, 0.72 }, { -44, 0.45 } }) do
		part(m, "ArenaMist", V3(2048, 1, 2048), CFrame.new(at(0, layer[1], 0)), MIST, Mat.SmoothPlastic, {
			Transparency = layer[2], CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
		})
	end
	part(m, "ArenaCloudFloor", V3(2048, 1, 2048), CFrame.new(at(0, -64, 0)), MIST, Mat.SmoothPlastic, {
		CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
	})
	for i = 0, 43 do
		local a = (i + rnd() * 0.6) / 44 * math.pi * 2
		local size = 34 + rnd() * 30
		ball(m, "CloudPuff", size, CFrame.new(onRing(205 + rnd() * 30, a, -30 - rnd() * 18)), RGB(232, 236, 244), Mat.SmoothPlastic, {
			Transparency = 0.15 + rnd() * 0.2, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
		})
	end
	local underFog = anchorPart(m, "UnderFog", CFrame.new(at(0, -20, 0)))
	underFog.Size = V3(460, 10, 460)
	local uf = Instance.new("ParticleEmitter")
	uf.Rate = 6
	uf.Color = ColorSequence.new(RGB(235, 240, 248))
	uf.LightEmission = 0.1
	uf.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 50), NumberSequenceKeypoint.new(1, 90) })
	uf.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.6), NumberSequenceKeypoint.new(1, 1) })
	uf.Lifetime = NumberRange.new(16, 24)
	uf.Speed = NumberRange.new(0.5, 2)
	uf.SpreadAngle = Vector2.new(180, 8)
	uf.Shape = Enum.ParticleEmitterShape.Box
	uf.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	uf.Parent = underFog
	-- A wall of mist all the way round, so the lobby (and anything else out
	-- there) can't be seen from the arena. One ring of panels that meet
	-- exactly edge to edge (no overlaps, so no darker stripes), in a soft,
	-- muted blue-grey so it doesn't glare like a white sky.
	local WALL_R, WALL_SEGS = 300, 72
	local wallBottom, wallTop = -66, 420
	local apothem = WALL_R * math.cos(math.pi / WALL_SEGS)
	local chord = 2 * WALL_R * math.sin(math.pi / WALL_SEGS)
	for i = 0, WALL_SEGS - 1 do
		local a = (i + 0.5) / WALL_SEGS * math.pi * 2
		local p = onRing(apothem, a, (wallBottom + wallTop) / 2)
		part(m, "MistWall", V3(chord, wallTop - wallBottom, 1), CFrame.lookAt(p, p + V3(math.sin(a), 0, math.cos(a))), RGB(118, 128, 148), Mat.SmoothPlastic, {
			Transparency = 0.08, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
			Reflectance = 0,
		})
	end
	-- soft drifting fog just inside the wall, so its edge doesn't look flat
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local fogP = anchorPart(m, "EdgeFog", CFrame.new(onRing(262, a, 20)))
		fogP.Size = V3(200, 60, 40)
		local fe = Instance.new("ParticleEmitter")
		fe.Rate = 3
		fe.Color = ColorSequence.new(RGB(230, 236, 246))
		fe.LightEmission = 0.1
		fe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 40), NumberSequenceKeypoint.new(1, 70) })
		fe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.75), NumberSequenceKeypoint.new(1, 1) })
		fe.Lifetime = NumberRange.new(14, 20)
		fe.Speed = NumberRange.new(0.5, 2)
		fe.SpreadAngle = Vector2.new(180, 10)
		fe.Shape = Enum.ParticleEmitterShape.Box
		fe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		fe.Parent = fogP
	end

	-- The colosseum floor: stone rings, slime channels, the boss pit
	cylinder(m, "FloorRim", 1, 192, CFrame.new(at(0, 0.5, 0)), ARENA_STONE_DARK, Mat.Slate)
	cylinder(m, "Floor", 1.2, 184, CFrame.new(at(0, 0.6, 0)), ARENA_STONE, Mat.Slate)
	ringBand("FloorBand", 89, 3, 1.3, 0.2, ARENA_STONE_DARK, Mat.Slate, 40)
	ringBand("FloorBand", 34, 3, 1.3, 0.2, ARENA_STONE_DARK, Mat.Slate, 20)
	ringBand("SlimeChannel", 62, 2.4, 1.28, 0.2, SLIME, Mat.Neon, 36, { Transparency = 0.15, CanCollide = false })
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		local p = onRing(62, a, 1.29)
		local ch = part(m, "SlimeChannel", V3(2.2, 0.2, 52), CFrame.lookAt(p, p + V3(math.sin(a), 0, math.cos(a))), SLIME, Mat.Neon, { Transparency = 0.15, CanCollide = false })
		if i % 3 == 0 then
			slimeGlow(ch, 0.4)
		end
		-- darker stone "spokes" between the channels, like the reference's radiating lines
		local b = a + math.pi / 12
		local q = onRing(62, b, 1.3)
		part(m, "FloorSpoke", V3(1.4, 0.2, 52), CFrame.lookAt(q, q + V3(math.sin(b), 0, math.cos(b))), ARENA_STONE_DARK, Mat.Slate)
	end
	-- the boss pit: a raised stone lip round a bubbling pool of slime
	cylinder(m, "PitRim", 2.2, 62, CFrame.new(at(0, 1.1, 0)), ARENA_STONE_DARK, Mat.Slate)
	cylinder(m, "PitLip", 0.6, 64, CFrame.new(at(0, 2.3, 0)), RGB(90, 96, 102), Mat.Slate)
	local pool = cylinder(m, "SlimePool", 0.4, 57, CFrame.new(at(0, 2.3, 0)), SLIME, Mat.Neon, { Transparency = 0.1, CanCollide = false })
	slimeGlow(pool, 0.3)
	cylinder(m, "SlimePoolDeep", 0.4, 40, CFrame.new(at(0, 2.35, 0)), SLIME_DEEP, Mat.Neon, { Transparency = 0.2, CanCollide = false })
	local poolLight = Instance.new("PointLight")
	poolLight.Range = 40
	poolLight.Brightness = 1.5
	poolLight.Color = SLIME
	poolLight.Parent = pool
	for i = 1, 7 do
		local b = ball(m, "SlimeBubble", 1.5 + rnd() * 2.5, CFrame.new(at((rnd() - 0.5) * 40, 2.6, (rnd() - 0.5) * 40)), SLIME, Mat.Neon, { Transparency = 0.25, CanCollide = false })
		fx(b, { BobAmp = 0.6, BobSpeed = 1 + rnd(), Phase = i * 50 })
	end
	local bubbles = anchorPart(m, "PoolBubbles", CFrame.new(at(0, 2.6, 0)))
	bubbles.Size = V3(44, 1, 44)
	local be = Instance.new("ParticleEmitter")
	be.Rate = 10
	be.Color = ColorSequence.new(RGB(190, 255, 150), SLIME)
	be.LightEmission = 0.6
	be.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.6) })
	be.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	be.Lifetime = NumberRange.new(1, 2)
	be.Speed = NumberRange.new(2, 5)
	be.SpreadAngle = Vector2.new(20, 20)
	be.EmissionDirection = Enum.NormalId.Top
	be.Parent = bubbles

	-- Slime moat round the floor, crossed by three stone bridges
	ringBand("Moat", 126, 14, 0.25, 0.5, SLIME, Mat.Neon, 60, { Transparency = 0.35, CanCollide = false })
	ringBand("MoatBank", 118.5, 1.6, 0.6, 1.2, ARENA_STONE_DARK, Mat.Slate, 60)
	ringBand("MoatBank", 133.5, 1.6, 0.6, 1.2, ARENA_STONE_DARK, Mat.Slate, 60)
	for _, a in ipairs({ 0, math.pi / 2 * 1.3, -math.pi / 2 * 1.3 }) do
		local p = onRing(126, a, 1.2)
		local cf = CFrame.lookAt(p, p + V3(math.sin(a), 0, math.cos(a)))
		part(m, "Bridge", V3(12, 1, 22), cf, ARENA_STONE, Mat.Slate)
		for _, sx in ipairs({ -1, 1 }) do
			part(m, "BridgeRail", V3(1, 2.4, 22), cf * CFrame.new(sx * 6.2, 1.5, 0), ARENA_STONE_DARK, Mat.Slate)
		end
		part(m, "BridgeArch", V3(8, 1.2, 12), cf * CFrame.new(0, -0.6, 0), ARENA_STONE_DARK, Mat.Slate)
	end
	-- the stretch between the floor and the moat: paved walks out to the bridges
	for _, a in ipairs({ 0, math.pi / 2 * 1.3, -math.pi / 2 * 1.3 }) do
		local p = onRing(104, a, 0.5)
		part(m, "Walk", V3(12, 1, 28), CFrame.lookAt(p, p + V3(math.sin(a), 0, math.cos(a))), ARENA_STONE_DARK, Mat.Slate)
	end

	-- Pillars: an inner ring just outside the floor, and giants further out
	local function pillar(p, h, d, broken)
		local base = p
		part(m, "PillarPlinth", V3(d + 4, 4, d + 4), CFrame.new(base + V3(0, 2, 0)), ARENA_STONE_DARK, Mat.Slate)
		part(m, "PillarPlinth", V3(d + 2.4, 2, d + 2.4), CFrame.new(base + V3(0, 5, 0)), ARENA_STONE, Mat.Slate)
		local shaftH = broken and h * (0.35 + rnd() * 0.25) or h
		cylinder(m, "PillarShaft", shaftH, d, CFrame.new(base + V3(0, 6 + shaftH / 2, 0)), ARENA_STONE, Mat.Slate)
		for _, f in ipairs({ 0.25, 0.6 }) do
			if f * h < shaftH then
				cylinder(m, "PillarBand", 1.2, d + 0.8, CFrame.new(base + V3(0, 6 + h * f, 0)), ARENA_STONE_DARK, Mat.Slate)
			end
		end
		local topY = 6 + shaftH
		if broken then
			-- jagged break and a fallen drum lying beside it
			for j = 1, 3 do
				part(m, "PillarBreak", V3(d * 0.5, 2 + rnd() * 3, d * 0.4), CFrame.new(base + V3((rnd() - 0.5) * d * 0.5, topY + 1, (rnd() - 0.5) * d * 0.5)) * CFrame.Angles(rnd() * 0.4, rnd() * 3, rnd() * 0.4), ARENA_STONE, Mat.Slate)
			end
			local fa = rnd() * math.pi * 2
			local fp = base + V3(math.cos(fa) * (d + 6), d / 2, math.sin(fa) * (d + 6))
			part(m, "FallenDrum", V3(d * 2.2, d, d), CFrame.new(fp) * CFrame.Angles(0, fa, 0), ARENA_STONE, Mat.Slate, { Shape = Enum.PartType.Cylinder })
		else
			part(m, "PillarCapital", V3(d + 3, 2.4, d + 3), CFrame.new(base + V3(0, topY + 1.2, 0)), ARENA_STONE_DARK, Mat.Slate)
			part(m, "PillarCapital", V3(d + 5, 1.6, d + 5), CFrame.new(base + V3(0, topY + 3.2, 0)), ARENA_STONE, Mat.Slate)
			topY = topY + 4
		end
		-- slime oozing over the top and dripping down
		local cap = ball(m, "SlimeCap", d * 0.9, CFrame.new(base + V3(0, topY + d * 0.15, 0)), SLIME, Mat.Neon, { Transparency = 0.2, CanCollide = false })
		slimeGlow(cap, 0.4)
		for j = 1, 3 do
			local a = rnd() * math.pi * 2
			local len = 6 + rnd() * (shaftH * 0.5)
			local out = V3(math.cos(a), 0, math.sin(a))
			part(m, "SlimeDrip", V3(0.9, len, 0.5), CFrame.new(base + out * (d / 2 + 0.1) + V3(0, topY - len / 2, 0)) * CFrame.Angles(0, -a + math.pi / 2, 0), SLIME, Mat.Neon, { Transparency = 0.15, CanCollide = false, CastShadow = false })
			ball(m, "SlimeDrop", 1.4, CFrame.new(base + out * (d / 2 + 0.3) + V3(0, topY - len, 0)), SLIME, Mat.Neon, { Transparency = 0.15, CanCollide = false })
		end
		-- the pool at the foot, set in a stone kerb so the slime sits in a basin
		-- instead of ending in a hard line drawn on the grass
		local poolD = d + 7 + rnd() * 5
		local poolAt = base + V3((rnd() - 0.5) * 0.8, 0, (rnd() - 0.5) * 0.8)
		-- A stone apron under the slime, and kerb stones standing round its edge, so
		-- the pool is held in a basin instead of ending in a glowing line drawn on
		-- the grass. The stones stand proud of the slime; the slime laps over the
		-- apron between them.
		cylinder(m, "PoolRim", 1.0, poolD + 5, CFrame.new(poolAt + V3(0, 0.4, 0)), ARENA_STONE_DARK, Mat.Slate)
		local pool = cylinder(m, "SlimePuddle", 0.6, poolD + 1.5, CFrame.new(poolAt + V3(0, 0.75, 0)), SLIME, Mat.Neon, { Transparency = 0.25, CanCollide = false })
		local kerbR = (poolD + 5) / 2 - 1.1
		local kerbN = math.max(10, math.floor(kerbR * 1.2))
		for k = 0, kerbN - 1 do
			local ka = (k + 0.5) / kerbN * math.pi * 2
			local out = V3(math.cos(ka), 0, math.sin(ka))
			local kp = poolAt + out * kerbR + V3(0, 1.05, 0)
			part(m, "PoolKerb", V3(2 * kerbR * math.sin(math.pi / kerbN) + 0.4, 1.1 + rnd() * 0.5, 2.2), CFrame.lookAt(kp, kp + out)
				* CFrame.Angles(math.rad((rnd() - 0.5) * 6), 0, math.rad((rnd() - 0.5) * 8)), ARENA_STONE, Mat.Slate, { CanCollide = false, CastShadow = false })
		end
		slimeGlow(pool, 0.35)
	end
	for i = 0, 11 do
		local a = (i + 0.5) / 12 * math.pi * 2
		pillar(onRing(106, a, 0), 64, 6, i % 4 == 1)
	end
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2 + math.pi / 8
		pillar(onRing(152, a, 0), 118, 13, false)
	end

	-- Slime waterfall pouring off a cliff into the moat.
	--
	-- The whole thing is built off two numbers: where the cliff's front face is,
	-- and how high the lip is. The rock steps back as it rises but its face stays
	-- on that one plane, so the falling slime can sit flush against it from lip to
	-- pool instead of hanging in the air in front of a cliff that leans away.
	local wfBase = onRing(170, math.pi, 0)
	local WF_FACE = 11 -- the front of the cliff, in studs toward the arena
	local WF_POOL = 0.4 -- the surface of the pool it lands in
	local WF_WIDE = 15 -- how wide the fall itself is
	local WF_TIERS, WF_TIER_H, WF_STEP, WF_FOOT = 7, 10, 9.5, 5
	-- the lip is wherever the top tier actually ends up, not a number typed in
	-- next to it that can drift when the cliff changes
	local WF_TOP = WF_FOOT + (WF_TIERS - 1) * WF_STEP + WF_TIER_H / 2

	-- the cliff: tiers that all share one front face, getting narrower with height
	for j = 0, WF_TIERS - 1 do
		local w = 46 - j * 3.5
		local depth = 16 + j * 2 -- it thickens backwards, never forwards
		local y = WF_FOOT + j * WF_STEP
		part(m, "WaterfallCliff", V3(w, WF_TIER_H, depth), CFrame.new(wfBase + V3(0, y, WF_FACE - depth / 2)),
			rockColor(0.15 + j / 9), Mat.Slate)
	end
	-- shoulders either side of the lip, flush with the same face, so the slime
	-- pours through a notch instead of over a plain ledge
	for _, side in ipairs({ -1, 1 }) do
		local w = 9 + rnd() * 5
		local h = 14 + rnd() * 8
		local depth = 13
		part(m, "WaterfallCrag", V3(w, h, depth), CFrame.new(wfBase + V3(side * (WF_WIDE / 2 + w / 2 - 1), WF_TOP + h / 2 - 4, WF_FACE - depth / 2))
			* CFrame.Angles(0, side * (0.05 + rnd() * 0.07), side * math.rad(3)), rockColor(0.2), Mat.Slate)
	end
	-- and a couple of boulders at the foot, where the pool has undercut it
	for _, side in ipairs({ -1, 1 }) do
		ball(m, "WaterfallCrag", 12 + rnd() * 6, CFrame.new(wfBase + V3(side * (13 + rnd() * 5), 2 + rnd() * 2, WF_FACE + 3 + rnd() * 3)),
			rockColor(0.35), Mat.Slate, { CanCollide = false, CastShadow = false })
	end

	-- the lip: a slab that overhangs the face, so the slime leaves the rock
	-- cleanly instead of dribbling down it
	part(m, "SlimeFallEdge", V3(WF_WIDE + 3, 1.6, 6), CFrame.new(wfBase + V3(0, WF_TOP + 0.8, WF_FACE + 1.4)),
		SLIME, Mat.Neon, { Transparency = 0.1, CanCollide = false, CastShadow = false })
	-- the sheet itself: dead vertical, hugging the face from the lip to the pool
	local fallHeight = WF_TOP - WF_POOL
	local fall = part(m, "SlimeFall", V3(WF_WIDE, fallHeight, 1.2), CFrame.new(wfBase + V3(0, WF_POOL + fallHeight / 2, WF_FACE + 1.5)),
		SLIME, Mat.Neon, { Transparency = 0.2, CanCollide = false, CastShadow = false })
	slimeGlow(fall, 0.9)
	-- a thinner, paler sheet just in front of it reads as spray down the face
	part(m, "SlimeFallVeil", V3(WF_WIDE + 4, fallHeight - 6, 0.6), CFrame.new(wfBase + V3(0, WF_POOL + 3 + fallHeight / 2, WF_FACE + 2.4)),
		RGB(200, 250, 170), Mat.Neon, { Transparency = 0.72, CanCollide = false, CastShadow = false })

	-- the pool it lands in, then the stream out of it into the moat
	local poolCentre = wfBase + V3(0, WF_POOL, WF_FACE + 7)
	cylinder(m, "SlimePuddle", 0.6, 26, CFrame.new(poolCentre), SLIME, Mat.Neon, { Transparency = 0.25, CanCollide = false, CastShadow = false })
	cylinder(m, "SlimePuddle", 0.7, 15, CFrame.new(poolCentre + V3(0, 0.15, 0)), SLIME, Mat.Neon, { Transparency = 0.12, CanCollide = false, CastShadow = false })
	local streamFrom, streamTo = poolCentre + V3(0, 0, 8), onRing(133, math.pi, 0.35)
	part(m, "SlimeStream", V3(11, 0.5, (streamTo - streamFrom).Magnitude + 6), CFrame.lookAt((streamFrom + streamTo) / 2, streamTo),
		SLIME, Mat.Neon, { Transparency = 0.12, CanCollide = false, CastShadow = false })

	local splash = anchorPart(m, "FallSplash", CFrame.new(wfBase + V3(0, 1.2, WF_FACE + 3)))
	splash.Size = V3(WF_WIDE, 1, 4)
	local se = Instance.new("ParticleEmitter")
	se.Rate = 25
	se.Color = ColorSequence.new(RGB(210, 255, 180), SLIME)
	se.LightEmission = 0.5
	se.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
	se.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	se.Lifetime = NumberRange.new(1, 2)
	se.Speed = NumberRange.new(4, 9)
	se.SpreadAngle = Vector2.new(50, 50)
	se.EmissionDirection = Enum.NormalId.Top
	se.Parent = splash

	-- Lush fantasy wilderness beyond the moat
	local function fantasyTree(p, s)
		local dir = (V3(rnd() - 0.5, 1.4, rnd() - 0.5)).Unit
		local th = 3 * s
		local q = p
		for j = 1, 6 do
			local len = 5 * s
			dir = (dir + V3(math.sin(j * 1.3) * 0.4, 0.2, math.cos(j * 1.1) * 0.4)).Unit
			local q2 = q + dir * len
			part(m, "FTreeTrunk", V3(th, th, len + th * 0.6), CFrame.lookAt((q + q2) / 2, q2), RGB(110, 80, 60), Mat.Wood, { CastShadow = false })
			q = q2
			th = th * 0.86
		end
		local col = CANOPY[1 + math.floor(rnd() * #CANOPY)]
		ball(m, "FTreeCanopy", 18 * s, CFrame.new(q + V3(0, 3 * s, 0)), col, Mat.LeafyGrass, { CastShadow = false })
		for j = 1, 4 do
			local a = j / 4 * math.pi * 2 + rnd()
			local off = V3(math.cos(a) * 8 * s, (rnd() - 0.2) * 4 * s, math.sin(a) * 8 * s)
			ball(m, "FTreeCanopy", (10 + rnd() * 5) * s, CFrame.new(q + off), col:Lerp(RGB(255, 255, 255), rnd() * 0.15), Mat.LeafyGrass, { CastShadow = false })
			-- hanging vines
			local vl = (6 + rnd() * 8) * s
			part(m, "FTreeVine", V3(0.5, vl, 0.5), CFrame.new(q + off - V3(0, 4 * s + vl / 2, 0)), RGB(80, 160, 70), Mat.LeafyGrass, noCol)
		end
	end
	for i = 0, 15 do
		local a = (i + 0.5) / 16 * math.pi * 2 + (rnd() - 0.5) * 0.15
		if math.abs(math.cos(a) + 1) > 0.2 and math.abs(math.cos(a) - 1) > 0.05 then -- keep the falls and the gate clear
			local r = (i % 2 == 0) and (174 + rnd() * 8) or (143 + rnd() * 6)
			fantasyTree(onRing(r, a, 0), (i % 2 == 0) and (0.95 + rnd() * 0.4) or (0.6 + rnd() * 0.25))
		end
	end
	-- giant mushrooms (red with white spots, and small glowing orange ones)
	local function bigMushroom(p, s)
		cylinder(m, "MushStem", 6 * s, 2.2 * s, CFrame.new(p + V3(0, 3 * s, 0)), RGB(240, 230, 210), Mat.SmoothPlastic)
		cylinder(m, "MushCap", 2.4 * s, 9 * s, CFrame.new(p + V3(0, 6.6 * s, 0)), RGB(220, 50, 50), Mat.SmoothPlastic)
		cylinder(m, "MushCap", 1.6 * s, 6 * s, CFrame.new(p + V3(0, 8.4 * s, 0)), RGB(220, 50, 50), Mat.SmoothPlastic)
		for j = 1, 4 do
			local a = j / 4 * math.pi * 2 + rnd()
			ball(m, "MushSpot", 1.2 * s, CFrame.new(p + V3(math.cos(a) * 3.2 * s, 7.8 * s, math.sin(a) * 3.2 * s)), RGB(255, 250, 240), Mat.SmoothPlastic, noCol)
		end
	end
	local function glowShrooms(p)
		for j = 1, 3 do
			local q = p + V3((rnd() - 0.5) * 4, 0, (rnd() - 0.5) * 4)
			local h = 1 + rnd() * 1.5
			part(m, "GlowStem", V3(0.4, h, 0.4), CFrame.new(q + V3(0, h / 2, 0)), RGB(250, 240, 220), Mat.SmoothPlastic, noCol)
			local cap = cylinder(m, "GlowCap", 0.5, 1.4 + rnd(), CFrame.new(q + V3(0, h + 0.2, 0)), RGB(255, 170, 60), Mat.Neon, { CanCollide = false, CastShadow = false })
			slimeGlow(cap, 0.3)
		end
	end
	for i = 0, 19 do
		local a = (i + rnd() * 0.6) / 20 * math.pi * 2
		if math.cos(a) < 0.93 and math.cos(a) > -0.9 then
			local p = onRing(145 + rnd() * 40, a, 0)
			if i % 3 == 0 then
				bigMushroom(p, 0.9 + rnd() * 0.7)
			else
				glowShrooms(p)
			end
		end
	end
	-- crystals
	for i = 0, 5 do
		local a = (i + 0.3) / 6 * math.pi * 2 + 0.4
		local p = onRing(160 + rnd() * 20, a, 0)
		for j = 1, 4 do
			local h = 4 + rnd() * 7
			local tilt = CFrame.Angles((rnd() - 0.5) * 0.8, rnd() * 3, (rnd() - 0.5) * 0.8)
			part(m, "Crystal", V3(1.4, h, 1.4), CFrame.new(p + V3((rnd() - 0.5) * 3, h * 0.4, (rnd() - 0.5) * 3)) * tilt, (j % 2 == 0) and RGB(120, 160, 255) or RGB(190, 120, 255), Mat.Glass, { Transparency = 0.2 })
		end
	end
	-- flowers and bushes scattered over the grass (arena ground is at y = 0, like the lobby)
	for i = 0, 29 do
		local a = (i + rnd()) / 30 * math.pi * 2
		local p = onRing(140 + rnd() * 48, a, 0)
		if i % 3 == 0 then
			bush(m, p.X, p.Z, 0.8 + rnd() * 0.5)
		else
			flowers(m, p.X, p.Z, 3 + rnd() * 2)
		end
	end
	-- fireflies / floating slime motes
	local motes = anchorPart(m, "Motes", CFrame.new(at(0, 18, 0)))
	motes.Size = V3(300, 30, 300)
	local me = Instance.new("ParticleEmitter")
	me.Rate = 30
	me.Color = ColorSequence.new(RGB(210, 255, 150), RGB(255, 220, 120))
	me.LightEmission = 1
	me.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0.15) })
	me.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.1), NumberSequenceKeypoint.new(1, 1) })
	me.Lifetime = NumberRange.new(5, 9)
	me.Speed = NumberRange.new(0.5, 1.5)
	me.SpreadAngle = Vector2.new(180, 180)
	me.Shape = Enum.ParticleEmitterShape.Box
	me.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	me.Parent = motes

	-- The fog gate on the south side: where you arrive, and the way out
	local gateP = onRing(176, 0, 0)
	local gcf = CFrame.lookAt(gateP, at(0, 0, 0)) -- faces the arena
	for _, sx in ipairs({ -1, 1 }) do
		part(m, "FogGatePillar", V3(5, 26, 5), gcf * CFrame.new(sx * 10, 13, 0), ARENA_STONE_DARK, Mat.Slate)
		part(m, "FogGateCap", V3(6.4, 2, 6.4), gcf * CFrame.new(sx * 10, 27, 0), ARENA_STONE, Mat.Slate)
		ball(m, "FogGateSlime", 3.4, gcf * CFrame.new(sx * 10, 28.6, 0), SLIME, Mat.Neon, { Transparency = 0.2, CanCollide = false })
	end
	part(m, "FogGateLintel", V3(26, 3, 5), gcf * CFrame.new(0, 26.5, 0), ARENA_STONE, Mat.Slate)
	local fog = part(m, "FogWall", V3(15, 24, 0.6), gcf * CFrame.new(0, 12, 0), RGB(235, 240, 255), Mat.Neon, { Transparency = 0.45, CanCollide = false })
	slimeGlow(fog, 0.4)
	fog:SetAttribute("PulseMin", 0.35)
	fog:SetAttribute("PulseMax", 0.6)
	local fe = Instance.new("ParticleEmitter")
	fe.Rate = 8
	fe.Color = ColorSequence.new(RGB(240, 245, 255))
	fe.LightEmission = 0.4
	fe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 6) })
	fe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	fe.Lifetime = NumberRange.new(2, 3)
	fe.Speed = NumberRange.new(0.5, 1.5)
	fe.Parent = fog
	local exit = Instance.new("ProximityPrompt")
	exit.ActionText = "Leave"
	exit.ObjectText = "Fog Gate"
	exit.HoldDuration = 0.4
	exit.MaxActivationDistance = 14
	exit.KeyboardKeyCode = Enum.KeyCode.E
	exit.GamepadKeyCode = Enum.KeyCode.ButtonX
	exit.RequiresLineOfSight = false
	exit.Parent = fog
	CollectionService:AddTag(exit, "ArenaExit")
	autoZone(m, gcf * CFrame.new(0, 4, -3), V3(16, 8, 6), "Spire", "Leave")
	-- dirt path from the gate to the south bridge
	local pathFrom, pathTo = onRing(172, 0, 0.1), onRing(136, 0, 0.1)
	part(m, "GatePath", V3(10, 0.4, (pathTo - pathFrom).Magnitude), CFrame.lookAt((pathFrom + pathTo) / 2, pathTo), RGB(196, 160, 110), Mat.Ground)
	-- arrival point, just inside the gate, facing the pit
	local spawnP = onRing(166, 0, 3.5)
	local spawnCF = CFrame.lookAt(spawnP, V3(C.X, spawnP.Y, C.Z))
	local arrive = anchorPart(m, "ArenaSpawn", spawnCF)
	CollectionService:AddTag(arrive, "ArenaSpawn")
	m:SetAttribute("Floor", 1)

	-- Where Gloomgut sleeps: sunk in the pit at the centre, facing the gate you
	-- come in through. BossService builds the boss itself on this spot.
	local home = anchorPart(m, "BossHome", CFrame.new(at(0, 1.2, 0)))
	home:SetAttribute("Floor", 1)
	home:SetAttribute("Facing", V3(0, 0, 1))
	CollectionService:AddTag(home, "BossHome")

	-- One flat floor to fight on: an invisible plate covers the whole arena at
	-- the height of the paved floor, and the flat decoration on it is made
	-- no-clip. It all still looks the same, but you can't trip on the rings,
	-- the channels, the pit lip, the moat or the plants - while real
	-- structures (pillars and their bases, fallen blocks, the big mushrooms,
	-- trees, the gate and the island's rim) stay solid.
	local FLAT_R = 146
	local FLATTEN = {
		FloorBand = true, FloorSpoke = true, SlimeChannel = true,
		PitRim = true, PitLip = true, SlimePool = true, SlimePoolDeep = true, SlimeBubble = true,
		Moat = true, MoatBank = true, Walk = true,
		-- the bridge decks and their rails are left out on purpose: they are
		-- structures you stand on and lean against, so they have to stay solid
		BridgeArch = true, GatePath = true,
		SlimePuddle = true, SlimeDrip = true, SlimeDrop = true, SlimeCap = true, SlimeStream = true,
		Bloom = true, Leaf = true, Leaves = true,
		GlowStem = true, GlowCap = true, MushSpot = true, FTreeVine = true,
	}
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") and p.CanCollide and FLATTEN[p.Name] then
			local d = (Vector3.new(p.Position.X, 0, p.Position.Z) - Vector3.new(C.X, 0, C.Z)).Magnitude
			if d <= FLAT_R + 20 then
				p.CanCollide = false
			end
		end
	end
	cylinder(m, "ArenaFloorPlate", 2, FLAT_R * 2, CFrame.new(at(0, 0.2, 0)), RGB(255, 255, 255), Mat.SmoothPlastic, {
		Transparency = 1,
		CanQuery = true,
		CastShadow = false,
	})

	m.Parent = Workspace
end

----------------------------------------------------------------------
-- Public
----------------------------------------------------------------------
function LobbyBuilder.Build()
	setupLighting()

	for _, name in ipairs({ "Baseplate", "SpawnLocation", "Lobby" }) do
		local old = Workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	local lobby = Instance.new("Model")
	lobby.Name = "Lobby"
	lobby.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	-- (always drawn in full detail, never swapped for a blurry far-away version)
	pcall(function()
		lobby.LevelOfDetail = Enum.ModelLevelOfDetail.Disabled
	end)

	-- Each piece is built on its own: if one of them hits an error, the
	-- rest of the lobby still appears and the game still starts, and the
	-- Output window says exactly which piece failed and why - instead of
	-- one mistake leaving the whole world empty.
	local pieces = {
		{ "Ground and walls", buildGround },
		{ "Sell Shop", buildSellShop },
		{ "Upgrade Shop", buildUpgradeShop },
		{ "Armory (blacksmith)", buildCraftBench },
		-- (the Prestige Shrine is gone: the plaza is open paving now)
		{ "Training Yard", buildYard },
		{ "The Spire", buildSpire },
		{ "Castle gate", buildCastleGate },
		{ "Castle (keep, south gate, moat, farm)", buildCastle },
		{ "Island and sea", buildIsland },
		{ "Slime arena (Spire floor 1)", buildSlimeArena },
		{ "Castle and nature decorations", buildDecor },
	}
	local failed = 0
	for _, piece in ipairs(pieces) do
		local ok, err = pcall(piece[2], lobby)
		if not ok then
			failed = failed + 1
			warn("[LobbyBuilder] '" .. piece[1] .. "' failed to build: " .. tostring(err))
		end
	end

	-- Leaves aren't solid: you can't stand on a tree's canopy, and (more
	-- importantly) the camera doesn't treat it as a wall. Solid leaves over
	-- your head made the camera zoom right into your head, which hides it.
	local LEAVES = {
		LeavesLow = true, LeavesTop = true, Crown = true, CrownSide = true, CrownTop = true,
		Blossom = true, BlossomSide = true, BlossomTop = true, Canopy = true, CanopyTop = true,
		CanopyCrown = true, CanopyLump = true, CanopyLight = true,
	}
	for _, d in ipairs(lobby:GetDescendants()) do
		if d:IsA("BasePart") and (LEAVES[d.Name] or string.match(d.Name, "^Needles%d+$")) then
			d.CanCollide = false
		end
	end
	if failed == 0 then
		print("[LobbyBuilder] Lobby built OK")
	end

	lobby.Parent = Workspace
	return lobby
end

return LobbyBuilder
