--[[
	Looks  (ModuleScript, parent: ReplicatedStorage, name: "Looks")

	Builds every model in the game: fruit, plants, Thinglets, eggs and the
	Thing's eyes, arms, teeth and horns. Thinglets and eggs come from the
	Blender art when it's loaded (see Assets); everything else, and the
	stand-ins until then, is built from plain Parts.
	The clients use it to draw the world, and the HUD uses it for icons.

	Thinglets are built 1 stud tall, standing on their "Root" part, facing -Z.
	Call model:ScaleTo(height) to make them any size. Every part is welded
	to the anchored Root, so moving Root.CFrame moves the whole Thinglet.
]]

local Looks = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

-- the Assets module (not an old props import that might share its name)
local function moduleNamed(name)
	for _, child in ipairs(ReplicatedStorage:GetChildren()) do
		if child.Name == name and child:IsA("ModuleScript") then
			return child
		end
	end
	return ReplicatedStorage:WaitForChild(name)
end
local Assets = require(moduleNamed("Assets"))

local WHITE = Color3.fromRGB(255, 255, 255)
local BLACK = Color3.fromRGB(25, 20, 30)

----------------------------------------------------------------------
-- Part helpers
----------------------------------------------------------------------
local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in pairs(props) do
		(p :: any)[key] = value
	end
	return p
end
Looks.part = part

-- An ellipsoid: a block with a sphere mesh, so it can be squashed
local function blob(size, color, props)
	local p = part({ Size = size, Color = color })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	if props then
		for key, value in pairs(props) do
			(p :: any)[key] = value
		end
	end
	return p
end
Looks.blob = blob

local function ball(diameter, color, props)
	local p = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(diameter, diameter, diameter), Color = color })
	if props then
		for key, value in pairs(props) do
			(p :: any)[key] = value
		end
	end
	return p
end

-- A cylinder standing up (Roblox cylinders lie along X, so turn it)
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)
local function cylinder(diameter, height, color, props)
	local p = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, diameter, diameter), Color = color })
	if props then
		for key, value in pairs(props) do
			(p :: any)[key] = value
		end
	end
	return p
end

local function lerpColor(a, b, t)
	return a:Lerp(b, t)
end

----------------------------------------------------------------------
-- Building a welded model: parts are placed relative to the model's base
-- (0,0,0 = bottom centre), then welded to an anchored Root.
----------------------------------------------------------------------
local Builder = {}
Builder.__index = Builder

local function newBuilder(name)
	local model = Instance.new("Model")
	model.Name = name
	local root = part({
		Name = "Root",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		CanQuery = false,
	})
	root.Parent = model
	model.PrimaryPart = root
	return setmetatable({ model = model, root = root, parts = {} }, Builder)
end

-- role: "Body" (takes mutation colours), "Eye" (left alone), "Accent" (glows when Glowing)
function Builder:add(p, cf, role, name)
	p.CFrame = cf
	p.Name = name or role or "Part"
	p:SetAttribute("Role", role or "Body")
	p.Parent = self.model
	table.insert(self.parts, p)
	return p
end

function Builder:finish(welded)
	for _, p in ipairs(self.parts) do
		if welded then
			p.Anchored = false
			p.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = self.root
			weld.Part1 = p
			weld.Parent = p
		end
	end
	return self.model
end

-- an eye: white ball with a dark pupil, looking along -Z
function Builder:eye(position, size, pupilColor)
	self:add(ball(size, WHITE), CFrame.new(position), "Eye", "EyeWhite")
	local pupil = ball(size * 0.5, pupilColor or BLACK)
	self:add(pupil, CFrame.new(position + Vector3.new(0, 0, -size * 0.32)), "Eye", "Pupil")
end

----------------------------------------------------------------------
-- Mutations: recolour the body, change the material, add sparkle
----------------------------------------------------------------------
local function sparkles(model, color, rate)
	local holder
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p:GetAttribute("Role") == "Body" then
			holder = p
			break
		end
	end
	if not holder then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Sparkle"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.8
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Parent = holder
end

function Looks.applyMutation(model, mutationId)
	if not mutationId or mutationId == "" then
		return
	end
	local mutation
	for _, m in ipairs(Config.Mutations) do
		if m.id == mutationId then
			mutation = m
		end
	end
	if not mutation then
		return
	end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "Root" then
			local role = p:GetAttribute("Role")
			if mutationId == "Frozen" then
				if role ~= "Eye" then
					p.Color = lerpColor(p.Color, mutation.color, 0.65)
					p.Material = Enum.Material.Ice
				end
			elseif mutationId == "Glowing" then
				if role == "Accent" then
					p.Color = mutation.color
					p.Material = Enum.Material.Neon
				elseif role ~= "Eye" then
					p.Color = lerpColor(p.Color, mutation.color, 0.35)
				end
			elseif mutationId == "Gold" then
				if role ~= "Eye" then
					p.Color = lerpColor(p.Color, mutation.color, 0.85)
					p.Material = Enum.Material.Foil
					p.Reflectance = 0.2
				end
			end
		end
	end
	sparkles(model, mutation.color, mutationId == "Gold" and 6 or 3)
	model:SetAttribute("Mutation", mutationId)
end

----------------------------------------------------------------------
-- Fruit (about 1 stud). Used on plants, in the toss and for icons.
----------------------------------------------------------------------
local LEAF = Color3.fromRGB(70, 170, 60)
local STEM = Color3.fromRGB(110, 75, 45)

local FRUIT = {}

FRUIT.Tomato = function(b)
	b:add(ball(1, Color3.fromRGB(235, 60, 55)), CFrame.new(0, 0.5, 0), "Body")
	b:add(blob(Vector3.new(0.5, 0.15, 0.5), LEAF), CFrame.new(0, 1, 0), "Accent", "Leaf")
	b:add(ball(0.22, Color3.fromRGB(255, 190, 180), { Transparency = 0.3 }), CFrame.new(0.22, 0.75, -0.3), "Eye", "Shine")
end

FRUIT.Chili = function(b)
	b:add(blob(Vector3.new(0.45, 0.45, 1.2), Color3.fromRGB(220, 35, 35)), CFrame.new(0, 0.4, 0) * CFrame.Angles(0.5, 0, 0.2), "Body")
	b:add(cylinder(0.14, 0.35, LEAF), CFrame.new(0, 0.75, 0.45) * UPRIGHT, "Accent", "Stem")
end

FRUIT.Eyeberry = function(b)
	b:add(ball(0.95, Color3.fromRGB(70, 95, 230), { Material = Enum.Material.Fabric }), CFrame.new(0, 0.48, 0), "Body")
	b:eye(Vector3.new(0, 0.55, -0.35), 0.42)
end

FRUIT.Glowshroom = function(b)
	b:add(cylinder(0.32, 0.6, Color3.fromRGB(240, 230, 210)), CFrame.new(0, 0.3, 0) * UPRIGHT, "Body", "Stalk")
	b:add(blob(Vector3.new(1, 0.55, 1), Color3.fromRGB(60, 220, 210), { Material = Enum.Material.Neon }), CFrame.new(0, 0.72, 0), "Accent", "Cap")
	b:add(ball(0.18, WHITE), CFrame.new(0.25, 0.9, -0.2), "Eye", "Spot")
end

FRUIT.Pumpkin = function(b)
	local orange = Color3.fromRGB(255, 140, 30)
	b:add(blob(Vector3.new(1.3, 0.95, 1.3), orange), CFrame.new(0, 0.48, 0), "Body")
	b:add(blob(Vector3.new(0.8, 1, 1.35), lerpColor(orange, BLACK, 0.12)), CFrame.new(0.28, 0.48, 0), "Body", "Ridge")
	b:add(blob(Vector3.new(0.8, 1, 1.35), lerpColor(orange, BLACK, 0.12)), CFrame.new(-0.28, 0.48, 0), "Body", "Ridge")
	b:add(cylinder(0.16, 0.3, STEM), CFrame.new(0, 1.05, 0) * UPRIGHT, "Accent", "Stem")
end

FRUIT.MoonMelon = function(b)
	b:add(ball(1.25, Color3.fromRGB(200, 245, 190)), CFrame.new(0, 0.62, 0), "Body")
	b:add(blob(Vector3.new(0.12, 1.28, 1.28), Color3.fromRGB(120, 230, 160), { Material = Enum.Material.Neon }), CFrame.new(0.25, 0.62, 0), "Accent", "Stripe")
	b:add(blob(Vector3.new(0.12, 1.28, 1.28), Color3.fromRGB(120, 230, 160), { Material = Enum.Material.Neon }), CFrame.new(-0.25, 0.62, 0), "Accent", "Stripe")
end

-- welded = true when it will be moved (tossed); false for plants and icons
function Looks.fruit(cropId, mutationId, welded)
	local b = newBuilder(cropId)
	local build = FRUIT[cropId] or FRUIT.Tomato
	build(b)
	local model = b:finish(welded)
	Looks.applyMutation(model, mutationId)
	return model
end

----------------------------------------------------------------------
-- Plants (no fruit). Each has 3 Attachments "Fruit1..3" in the Root
-- where its fruit hang or sit.
----------------------------------------------------------------------
local function fruitSpots(b, spots)
	for i, position in ipairs(spots) do
		local a = Instance.new("Attachment")
		a.Name = "Fruit" .. i
		a.Position = position
		a.Parent = b.root
	end
end

local function bush(b, color, height)
	b:add(blob(Vector3.new(3, height * 0.7, 3), color), CFrame.new(0, height * 0.35, 0), "Body", "Leaves")
	b:add(blob(Vector3.new(2.2, height * 0.6, 2.2), lerpColor(color, WHITE, 0.12)), CFrame.new(0.3, height * 0.62, -0.2), "Body", "Leaves")
	b:add(cylinder(0.4, height * 0.4, STEM), CFrame.new(0, height * 0.2, 0) * UPRIGHT, "Body", "Trunk")
end

local PLANT = {}
PLANT.Tomato = function(b)
	bush(b, Color3.fromRGB(70, 165, 65), 3)
	fruitSpots(b, { Vector3.new(-1.2, 1.4, -0.9), Vector3.new(1.1, 1.8, -0.8), Vector3.new(0.1, 2.3, -1.3) })
end
PLANT.Chili = function(b)
	bush(b, Color3.fromRGB(60, 150, 70), 3.2)
	fruitSpots(b, { Vector3.new(-1.2, 1.3, -0.8), Vector3.new(1.2, 1.6, -0.8), Vector3.new(0, 2.2, -1.3) })
end
PLANT.Eyeberry = function(b)
	bush(b, Color3.fromRGB(55, 120, 110), 3.4)
	fruitSpots(b, { Vector3.new(-1.2, 1.5, -1), Vector3.new(1.2, 1.9, -0.9), Vector3.new(0, 2.5, -1.3) })
end
PLANT.Glowshroom = function(b)
	b:add(blob(Vector3.new(4, 0.8, 4), Color3.fromRGB(90, 60, 45)), CFrame.new(0, 0.2, 0), "Body", "Mound")
	fruitSpots(b, { Vector3.new(-1, 0.5, -0.8), Vector3.new(1, 0.5, -0.6), Vector3.new(0, 0.5, 0.9) })
end
PLANT.Pumpkin = function(b)
	b:add(blob(Vector3.new(4.5, 0.5, 4.5), Color3.fromRGB(80, 160, 60)), CFrame.new(0, 0.2, 0), "Body", "Leaves")
	b:add(blob(Vector3.new(2, 0.9, 2), Color3.fromRGB(95, 180, 70)), CFrame.new(0, 0.4, 0.8), "Body", "Leaves")
	fruitSpots(b, { Vector3.new(-1.3, 0.1, -0.8), Vector3.new(1.3, 0.1, -0.8), Vector3.new(0, 0.1, -1.7) })
end
PLANT.MoonMelon = function(b)
	b:add(blob(Vector3.new(4.5, 0.5, 4.5), Color3.fromRGB(150, 200, 170)), CFrame.new(0, 0.2, 0), "Body", "Leaves")
	b:add(blob(Vector3.new(0.4, 2.4, 0.4), Color3.fromRGB(230, 250, 255), { Material = Enum.Material.Neon }), CFrame.new(0, 1.2, 1), "Accent", "Moonflower")
	fruitSpots(b, { Vector3.new(-1.4, 0.1, -0.7), Vector3.new(1.4, 0.1, -0.7), Vector3.new(0, 0.1, -1.8) })
end

function Looks.plant(cropId)
	local b = newBuilder(cropId .. "Plant")
	local build = PLANT[cropId] or PLANT.Tomato
	build(b)
	return b:finish(false)
end

----------------------------------------------------------------------
-- Thinglets, built 1 stud tall (the Root sits at their feet)
----------------------------------------------------------------------
local THINGLET = {}

THINGLET.Blorp = function(b)
	local red = Color3.fromRGB(235, 70, 70)
	b:add(blob(Vector3.new(1, 0.85, 1), red, { Material = Enum.Material.Glass, Transparency = 0.1 }), CFrame.new(0, 0.42, 0), "Body")
	b:eye(Vector3.new(0, 0.52, -0.38), 0.42)
	b:add(blob(Vector3.new(0.4, 0.1, 0.22), LEAF), CFrame.new(0.06, 0.88, 0) * CFrame.Angles(0, 0.4, 0.25), "Accent", "Leaf")
	b:add(ball(0.14, Color3.fromRGB(255, 200, 200), { Transparency = 0.3 }), CFrame.new(0.28, 0.7, -0.28), "Eye", "Shine")
end

THINGLET.Sizzle = function(b)
	local skin = Color3.fromRGB(240, 95, 50)
	b:add(blob(Vector3.new(0.7, 0.5, 1.05), skin), CFrame.new(0, 0.28, 0.1), "Body", "Belly")
	b:add(blob(Vector3.new(0.6, 0.5, 0.55), skin), CFrame.new(0, 0.5, -0.45), "Body", "Head")
	b:add(blob(Vector3.new(0.24, 0.2, 0.65), lerpColor(skin, BLACK, 0.1)), CFrame.new(0, 0.25, 0.78) * CFrame.Angles(-0.25, 0, 0), "Body", "Tail")
	b:eye(Vector3.new(-0.15, 0.62, -0.66), 0.18)
	b:eye(Vector3.new(0.15, 0.62, -0.66), 0.18)
	b:add(blob(Vector3.new(0.26, 0.38, 0.26), Color3.fromRGB(255, 150, 30), { Material = Enum.Material.Neon }), CFrame.new(0, 0.86, -0.4), "Accent", "Flame")
	b:add(blob(Vector3.new(0.14, 0.22, 0.14), Color3.fromRGB(255, 235, 90), { Material = Enum.Material.Neon }), CFrame.new(0, 0.82, -0.44), "Accent", "Flame")
end

THINGLET.Peeper = function(b)
	b:add(ball(1, Color3.fromRGB(95, 115, 235), { Material = Enum.Material.Fabric }), CFrame.new(0, 0.5, 0), "Body")
	b:eye(Vector3.new(0, 0.62, -0.42), 0.3)
	b:eye(Vector3.new(-0.27, 0.42, -0.38), 0.22)
	b:eye(Vector3.new(0.28, 0.4, -0.37), 0.2)
	b:add(blob(Vector3.new(0.2, 0.25, 0.2), Color3.fromRGB(150, 165, 255), { Material = Enum.Material.Fabric }), CFrame.new(0.15, 1.0, 0), "Accent", "Tuft")
end

THINGLET.Glumcap = function(b)
	b:add(cylinder(0.38, 0.6, Color3.fromRGB(240, 230, 210)), CFrame.new(0, 0.3, 0) * UPRIGHT, "Body", "Stalk")
	b:add(blob(Vector3.new(1, 0.5, 1), Color3.fromRGB(60, 190, 190)), CFrame.new(0, 0.74, 0) * CFrame.Angles(0, 0, 0.12), "Body", "Cap")
	for i, offset in ipairs({ Vector3.new(0.25, 0.92, -0.2), Vector3.new(-0.28, 0.86, 0.1), Vector3.new(0.05, 0.98, 0.25) }) do
		b:add(ball(0.12 + i * 0.02, Color3.fromRGB(190, 255, 250), { Material = Enum.Material.Neon }), CFrame.new(offset), "Accent", "Spot")
	end
	-- sleepy eyes: two little lines
	b:add(part({ Size = Vector3.new(0.12, 0.03, 0.03), Color = BLACK }), CFrame.new(-0.08, 0.42, -0.19), "Eye", "Lid")
	b:add(part({ Size = Vector3.new(0.12, 0.03, 0.03), Color = BLACK }), CFrame.new(0.08, 0.42, -0.19), "Eye", "Lid")
end

THINGLET.Gourdo = function(b)
	local orange = Color3.fromRGB(255, 140, 35)
	b:add(blob(Vector3.new(1, 0.82, 1), orange), CFrame.new(0, 0.46, 0), "Body")
	b:add(blob(Vector3.new(0.62, 0.84, 1.02), lerpColor(orange, BLACK, 0.1)), CFrame.new(0.2, 0.46, 0), "Body", "Ridge")
	b:add(blob(Vector3.new(0.62, 0.84, 1.02), lerpColor(orange, BLACK, 0.1)), CFrame.new(-0.2, 0.46, 0), "Body", "Ridge")
	b:add(cylinder(0.12, 0.22, STEM), CFrame.new(0, 0.95, 0) * UPRIGHT, "Accent", "Stem")
	b:add(ball(0.13, BLACK), CFrame.new(-0.18, 0.6, -0.47), "Eye", "Eye")
	b:add(ball(0.13, BLACK), CFrame.new(0.18, 0.6, -0.47), "Eye", "Eye")
	b:add(blob(Vector3.new(0.42, 0.1, 0.06), BLACK), CFrame.new(0, 0.38, -0.49), "Eye", "Grin")
	b:add(blob(Vector3.new(0.26, 0.12, 0.3), lerpColor(orange, BLACK, 0.3)), CFrame.new(-0.25, 0.05, -0.15), "Body", "Foot")
	b:add(blob(Vector3.new(0.26, 0.12, 0.3), lerpColor(orange, BLACK, 0.3)), CFrame.new(0.25, 0.05, -0.15), "Body", "Foot")
end

THINGLET.Mishmash = function(b)
	b:add(blob(Vector3.new(1, 0.88, 0.95), Color3.fromRGB(130, 90, 175)), CFrame.new(0, 0.44, 0), "Body")
	b:add(blob(Vector3.new(0.42, 0.42, 0.12), Color3.fromRGB(110, 200, 90)), CFrame.new(0.38, 0.4, -0.28) * CFrame.Angles(0, -0.6, 0), "Body", "Patch")
	b:eye(Vector3.new(-0.18, 0.56, -0.4), 0.32) -- a Blorp eye...
	b:eye(Vector3.new(0.2, 0.62, -0.38), 0.18) -- ...and a Peeper eye
	b:add(blob(Vector3.new(0.55, 0.22, 0.55), Color3.fromRGB(60, 190, 190)), CFrame.new(0.05, 0.92, 0) * CFrame.Angles(0, 0, -0.2), "Accent", "Cap")
	b:add(blob(Vector3.new(0.2, 0.3, 0.2), Color3.fromRGB(255, 150, 30), { Material = Enum.Material.Neon }), CFrame.new(0, 0.45, 0.5), "Accent", "Flame")
	b:add(part({ Size = Vector3.new(0.03, 0.4, 0.03), Color = BLACK }), CFrame.new(0.02, 0.35, -0.47), "Eye", "Stitch")
end

THINGLET.Moonmoth = function(b)
	local fuzz = Color3.fromRGB(245, 240, 225)
	local wing = Color3.fromRGB(200, 240, 190)
	b:add(blob(Vector3.new(0.34, 0.34, 0.85), fuzz, { Material = Enum.Material.Fabric }), CFrame.new(0, 0.5, 0.05), "Body", "Body")
	b:add(ball(0.36, fuzz, { Material = Enum.Material.Fabric }), CFrame.new(0, 0.6, -0.45), "Body", "Head")
	b:add(ball(0.13, Color3.fromRGB(60, 30, 90)), CFrame.new(-0.11, 0.65, -0.58), "Eye", "Eye")
	b:add(ball(0.13, Color3.fromRGB(60, 30, 90)), CFrame.new(0.11, 0.65, -0.58), "Eye", "Eye")
	b:add(blob(Vector3.new(0.8, 0.05, 0.62), wing), CFrame.new(-0.46, 0.66, 0) * CFrame.Angles(0, 0, 0.35), "Body", "Wing")
	b:add(blob(Vector3.new(0.8, 0.05, 0.62), wing), CFrame.new(0.46, 0.66, 0) * CFrame.Angles(0, 0, -0.35), "Body", "Wing")
	b:add(blob(Vector3.new(0.5, 0.06, 0.12), Color3.fromRGB(110, 200, 130)), CFrame.new(-0.5, 0.69, 0) * CFrame.Angles(0, 0, 0.35), "Accent", "Stripe")
	b:add(blob(Vector3.new(0.5, 0.06, 0.12), Color3.fromRGB(110, 200, 130)), CFrame.new(0.5, 0.69, 0) * CFrame.Angles(0, 0, -0.35), "Accent", "Stripe")
	b:add(blob(Vector3.new(0.04, 0.3, 0.04), Color3.fromRGB(255, 240, 150), { Material = Enum.Material.Neon }), CFrame.new(-0.08, 0.85, -0.5) * CFrame.Angles(-0.4, 0, 0.3), "Accent", "Antenna")
	b:add(blob(Vector3.new(0.04, 0.3, 0.04), Color3.fromRGB(255, 240, 150), { Material = Enum.Material.Neon }), CFrame.new(0.08, 0.85, -0.5) * CFrame.Angles(-0.4, 0, -0.3), "Accent", "Antenna")
end

THINGLET.LilThing = function(b)
	local dark = Color3.fromRGB(28, 16, 40)
	b:add(cylinder(1, 0.04, Color3.fromRGB(10, 5, 15)), CFrame.new(0, 0.02, 0) * UPRIGHT, "Body", "Puddle")
	b:add(blob(Vector3.new(0.7, 0.78, 0.7), dark), CFrame.new(0, 0.4, 0), "Body", "Shadow")
	b:add(blob(Vector3.new(0.15, 0.2, 0.08), Config.Thing.EyeColor, { Material = Enum.Material.Neon }), CFrame.new(-0.14, 0.55, -0.32), "Eye", "Eye")
	b:add(blob(Vector3.new(0.15, 0.2, 0.08), Config.Thing.EyeColor, { Material = Enum.Material.Neon }), CFrame.new(0.14, 0.55, -0.32), "Eye", "Eye")
	b:add(blob(Vector3.new(0.12, 0.45, 0.12), Config.Thing.SkinColor), CFrame.new(-0.42, 0.45, -0.05) * CFrame.Angles(0, 0, 0.5), "Body", "Arm")
	b:add(blob(Vector3.new(0.12, 0.45, 0.12), Config.Thing.SkinColor), CFrame.new(0.42, 0.5, -0.05) * CFrame.Angles(0, 0, -0.9), "Body", "Arm")
end

-- The Blender version of a creature or the egg (FeedTheThing/Blender/
-- build_creatures.py, loaded with the props), or nil if it isn't there yet
local function fromBlender(name, welded)
	local model = Assets.get(name)
	if not model or not model.PrimaryPart then
		return nil
	end
	local root = model.PrimaryPart
	model:SetAttribute("Blender", true)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p ~= root then
			p.CanQuery = true -- so you can tap it
			p.CastShadow = false
			if welded then
				p.Anchored = false
				p.Massless = true
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = p
				weld.Parent = p
			end
		end
	end
	return model
end

-- Is the Blender art loaded? (until then, the block-built stand-ins are used)
function Looks.hasBlenderArt()
	return Assets.get("Blorp") ~= nil
end

function Looks.thinglet(kind, mutationId, welded)
	local model = fromBlender(THINGLET[kind] and kind or "Blorp", welded ~= false)
	if not model then
		local b = newBuilder(kind)
		local build = THINGLET[kind] or THINGLET.Blorp
		build(b)
		model = b:finish(welded ~= false)
	end
	model.Name = kind
	Looks.applyMutation(model, mutationId)
	model:SetAttribute("Kind", kind)
	return model
end

-- The same model painted solid black, for "???" in the dex and the hatch reveal
function Looks.silhouette(model)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Color = Color3.fromRGB(20, 15, 30)
			p.Material = Enum.Material.SmoothPlastic
			p.Reflectance = 0
		elseif p:IsA("ParticleEmitter") then
			p:Destroy()
		end
	end
	return model
end

----------------------------------------------------------------------
-- Egg (1 stud tall), speckled in its rarity colour
----------------------------------------------------------------------
function Looks.egg(rarity)
	local color = Config.Rarities[rarity] and Config.Rarities[rarity].color or WHITE
	local model = fromBlender("Egg", true)
	if model then
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") and p:GetAttribute("Role") == "Accent" then
				p.Color = color -- the spots, in the rarity's colour
			end
		end
		return model
	end
	local b = newBuilder("Egg")
	b:add(blob(Vector3.new(0.78, 1, 0.78), Color3.fromRGB(250, 245, 230)), CFrame.new(0, 0.5, 0), "Body", "Shell")
	for i, offset in ipairs({ Vector3.new(0.2, 0.6, -0.3), Vector3.new(-0.25, 0.4, -0.27), Vector3.new(0.05, 0.25, -0.36), Vector3.new(-0.1, 0.78, -0.22) }) do
		b:add(ball(0.12 + (i % 2) * 0.05, color), CFrame.new(offset), "Accent", "Spot")
	end
	return b:finish(true)
end

----------------------------------------------------------------------
-- Stand-ins for the Blender props (used until FeedTheThing_Props.fbx is
-- imported as ReplicatedStorage.Assets). Same names and layout: facing -Z,
-- base at the pivot, wheels named Wheel*.
----------------------------------------------------------------------
function Looks.truck()
	local b = newBuilder("Truck")
	local red, cream = Color3.fromRGB(230, 55, 50), Color3.fromRGB(255, 245, 225)
	b:add(part({ Size = Vector3.new(5.4, 0.9, 11.2), Color = Color3.fromRGB(35, 35, 40) }), CFrame.new(0, 1.9, 0.3), "Body", "Chassis")
	b:add(part({ Size = Vector3.new(6, 4.8, 3.8), Color = red }), CFrame.new(0, 4.3, -3.8), "Body", "Cab")
	b:add(blob(Vector3.new(5.9, 2.8, 1.8), red), CFrame.new(0, 3.1, -5.5), "Body", "Nose")
	b:add(part({ Size = Vector3.new(4.8, 2, 0.3), Color = Color3.fromRGB(150, 210, 255), Material = Enum.Material.Glass }), CFrame.new(0, 5.2, -5.72), "Body", "Windshield")
	b:add(part({ Size = Vector3.new(6.2, 6, 7.6), Color = cream }), CFrame.new(0, 5, 2.4), "Body", "Cargo")
	b:add(part({ Size = Vector3.new(6.3, 0.7, 7.7), Color = Color3.fromRGB(80, 200, 70) }), CFrame.new(0, 2.65, 2.4), "Body", "Stripe")
	b:add(part({ Size = Vector3.new(6.4, 0.9, 0.8), Color = Color3.fromRGB(225, 230, 240) }), CFrame.new(0, 1.6, -6.25), "Body", "Bumper")
	b:add(part({ Size = Vector3.new(2.4, 0.5, 1), Color = Color3.fromRGB(255, 170, 40), Material = Enum.Material.Neon }), CFrame.new(0, 6.95, -3.8), "Accent", "RoofLight")
	for name, offset in pairs({ FL = Vector3.new(-2.85, 1.55, -3.8), FR = Vector3.new(2.85, 1.55, -3.8), BL = Vector3.new(-2.95, 1.55, 3.6), BR = Vector3.new(2.95, 1.55, 3.6) }) do
		b:add(part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.1, 3.1, 3.1), Color = Color3.fromRGB(35, 35, 40) }), CFrame.new(offset), "Body", "Wheel" .. name)
	end
	return b:finish(false)
end

function Looks.package()
	local b = newBuilder("Package")
	b:add(part({ Size = Vector3.new(2.6, 2.4, 2.6), Color = Color3.fromRGB(205, 150, 90) }), CFrame.new(0, 1.2, 0), "Body", "Box")
	b:add(part({ Size = Vector3.new(2.62, 0.05, 0.6), Color = Color3.fromRGB(235, 205, 140) }), CFrame.new(0, 2.42, 0), "Body", "Tape")
	return b:finish(false)
end

-- A little seed packet in the crop's colour (flies from the package into the planter)
function Looks.seedPacket(cropId)
	local color = Color3.fromRGB(120, 200, 80)
	for _, crop in ipairs(Config.Crops) do
		if crop.id == cropId then
			color = crop.color
		end
	end
	local b = newBuilder("SeedPacket")
	b:add(part({ Size = Vector3.new(1.3, 1.7, 0.15), Color = Color3.fromRGB(250, 248, 240) }), CFrame.new(0, 0.85, 0), "Body", "Paper")
	b:add(ball(0.8, color), CFrame.new(0, 0.95, -0.12), "Body", "Picture")
	return b:finish(false)
end

----------------------------------------------------------------------
-- The Thing (client side, per plot). Returns a model plus the moving
-- parts so the client can animate them. `hatchCF` is the centre of the
-- hatch at ground level; the opening is Config.Thing.Sizes[size].hole wide.
----------------------------------------------------------------------
function Looks.thing(sizeIndex, hatchCF)
	local size = Config.Thing.Sizes[sizeIndex]
	local hole = size.hole
	local pit = Config.World.PitSize
	local model = Instance.new("Model")
	model.Name = "Thing"
	local parts = { eyes = {}, pupils = {}, arms = {}, teeth = {}, lidPlanks = {} }

	local wood = Color3.fromRGB(140, 95, 60)
	local darkWood = Color3.fromRGB(100, 65, 40)

	-- (the pit and its wooden frame are part of the Blender map; the opening
	-- is always the full pit, and what's down there grows with the size)

	-- the cellar-door lid, hinged on the house side, lying open
	local lid = part({ Name = "Lid", Size = Vector3.new(pit, 0.5, pit), Color = darkWood, Material = Enum.Material.WoodPlanks, CanQuery = false })
	local hinge = hatchCF * CFrame.new(0, 0.6, pit / 2) -- the house-side edge of the opening, on top of the frame
	parts.hinge = hinge
	parts.lidOffset = CFrame.new(0, 0, -pit / 2) -- from the hinge to the lid's centre, when shut
	parts.openAngle = 150 -- degrees; 0 = shut. Open, it leans back towards the house
	lid.CFrame = hinge * CFrame.Angles(math.rad(parts.openAngle), 0, 0) * parts.lidOffset
	lid.Parent = model
	parts.lid = lid
	-- planks on the lid
	for k = -2, 2 do
		local plank = part({ Name = "LidPlank", Size = Vector3.new(0.3, 0.55, pit - 0.6), Color = wood, Material = Enum.Material.WoodPlanks, CanQuery = false })
		plank:SetAttribute("LidOffset", k * pit / 5)
		plank.CFrame = lid.CFrame * CFrame.new(k * pit / 5, 0.28, 0)
		plank.Parent = model
		table.insert(parts.lidPlanks, plank)
	end

	-- the darkness, so you can't see the bottom
	local dark = part({ Name = "Dark", Size = Vector3.new(pit - 0.2, 0.2, pit - 0.2), Color = Config.Thing.PitColor, CanQuery = false, Transparency = 0.15 })
	dark.CFrame = hatchCF * CFrame.new(0, -3.2, 0)
	dark.Parent = model

	-- eyes
	local eyeSize = hole * 0.2
	for i, side in ipairs({ -1, 1 }) do
		local eye = blob(Vector3.new(eyeSize, eyeSize * 1.15, eyeSize), Config.Thing.EyeColor, { Name = "Eye", Material = Enum.Material.Neon, CanQuery = false })
		local home = hatchCF * CFrame.new(side * hole * 0.18, -1.6, hole * 0.1)
		eye.CFrame = home
		eye.Parent = model
		local pupil = ball(eyeSize * 0.45, BLACK, { Name = "Pupil", CanQuery = false })
		pupil.CFrame = home * CFrame.new(0, eyeSize * 0.3, 0)
		pupil.Parent = model
		parts.eyes[i] = { part = eye, home = home, size = eyeSize }
		parts.pupils[i] = pupil
	end

	-- a grin of rounded teeth
	if size.teeth then
		for i = 1, 6 do
			local x = (i - 3.5) * hole * 0.07
			local y = -2.5 + math.abs(i - 3.5) * 0.12
			local tooth = blob(Vector3.new(hole * 0.06, hole * 0.08, hole * 0.06), Color3.fromRGB(245, 245, 230), { Name = "Tooth", Material = Enum.Material.Neon, CanQuery = false })
			tooth.CFrame = hatchCF * CFrame.new(x, y, -hole * 0.05)
			tooth.Parent = model
			table.insert(parts.teeth, tooth)
		end
	end

	-- horns peeking out of the corners
	if size.horns then
		for _, side in ipairs({ -1, 1 }) do
			for j = 1, 3 do
				local d = (4 - j) * 0.35 * hole / 12
				local horn = ball(d * 2, Color3.fromRGB(235, 225, 200), { Name = "Horn", CanQuery = false })
				horn.CFrame = hatchCF * CFrame.new(side * (hole * 0.38 + j * 0.25), -0.6 + j * 0.65, hole * 0.3)
				horn.Parent = model
			end
		end
	end

	-- glowing cracks in the lawn
	if size.cracks then
		for i = 1, 8 do
			local angle = i / 8 * math.pi * 2 + 0.3
			local length = 5 + (i % 3) * 2
			local crack = part({ Name = "Crack", Size = Vector3.new(0.35, 0.12, length), Color = Color3.fromRGB(190, 90, 255), Material = Enum.Material.Neon, CanQuery = false })
			crack.CFrame = hatchCF * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0.02, -(pit / 2 + length / 2 - 1))
			crack.Parent = model
		end
	end

	-- arms, hidden down in the dark until they catch something
	for i = 1, size.arms do
		local arm = blob(Vector3.new(hole * 0.09, hole * 0.6, hole * 0.09), Config.Thing.SkinColor, { Name = "Arm", CanQuery = false })
		local side = (i % 2 == 1) and -1 or 1
		local row = math.ceil(i / 2)
		-- below the darkness (at -3.2), so not even the tip shows
		local hidden = hatchCF * CFrame.new(side * hole * (0.28 + row * 0.06), -3.4 - hole * 0.3, -hole * 0.15 * row)
		arm.CFrame = hidden
		arm.Parent = model
		parts.arms[i] = { part = arm, hidden = hidden, side = side }
	end

	return model, parts
end

return Looks
