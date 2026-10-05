--[[
	World  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "World")

	Draws everything alive in the world, on your own screen: every plot's
	plants and fruit, every Thing (eyes, arms, lid), every Thinglet (growing,
	wandering, looking at you, with its name tag), the weather, and little
	effects like fruit hopping into your basket.

	It reads the plot attributes the server keeps in ReplicatedStorage.Plots,
	so all players see the same garden and yard - but the animation runs
	here, which keeps it smooth on phones and costs the server nothing.
]]

local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Rules = require(ReplicatedStorage:WaitForChild("Rules"))
local Looks = require(ReplicatedStorage:WaitForChild("Looks"))
local UI = require(ReplicatedStorage:WaitForChild("UI"))

local remoteFolder = ReplicatedStorage:WaitForChild("Remotes")
local HarvestedRemote = remoteFolder:WaitForChild("Harvested") :: RemoteEvent
local HatchedRemote = remoteFolder:WaitForChild("Hatched") :: RemoteEvent
local FxRemote = remoteFolder:WaitForChild("Fx") :: RemoteEvent
local plotsFolder = ReplicatedStorage:WaitForChild("Plots")

local player = Players.LocalPlayer
local W = Config.World

local LETTER_MUT = { N = "", F = "Frozen", L = "Glowing", G = "Gold" }
local FRUIT_SCALE = { Tomato = 1.1, Chili = 1.1, Eyeberry = 1.1, Glowshroom = 1.3, Pumpkin = 1.7, MoonMelon = 1.7 }
local ANIMATE_RANGE = 170 -- studs from the camera; further away things stand still

local visuals = Instance.new("Folder")
visuals.Name = "LocalWorld"
visuals.Parent = workspace
local thingletFolder = Instance.new("Folder")
thingletFolder.Name = "Thinglets"
thingletFolder.Parent = visuals

local plots = {} -- [i] = see setupPlot

local function now()
	return workspace:GetServerTimeNow()
end

local function decode(json)
	if type(json) ~= "string" or json == "" then
		return {}
	end
	local ok, result = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	return ok and type(result) == "table" and result or {}
end

local function tween(instance, seconds, goal, style, direction)
	local t = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

----------------------------------------------------------------------
-- Plants and fruit
----------------------------------------------------------------------
local function placeFruit(plant, index, cropId, letter)
	local holder = plant.model.PrimaryPart
	local attachment = holder and holder:FindFirstChild("Fruit" .. index)
	if not holder or not attachment or not attachment:IsA("Attachment") then
		return nil
	end
	local fruit = Looks.fruit(cropId, LETTER_MUT[letter] or "", false)
	local scale = FRUIT_SCALE[cropId] or 1
	fruit:ScaleTo(scale * 0.2)
	fruit:PivotTo(holder.CFrame * CFrame.new(attachment.Position) * CFrame.Angles(0, index * 2.1, 0))
	fruit.Parent = plant.model
	-- pop in
	task.spawn(function()
		for step = 1, 8 do
			if not fruit.Parent then
				return
			end
			local k = step / 8
			local bounce = 1 + math.sin(k * math.pi) * 0.25
			fruit:ScaleTo(scale * math.max(0.2, k) * bounce)
			task.wait(1 / 30)
		end
		if fruit.Parent then
			fruit:ScaleTo(scale)
		end
	end)
	return fruit
end

local function updatePlants(p)
	local list = decode(p.folder:GetAttribute("Plants"))
	for spot = 1, #W.PlantSpots do
		local entry = list[spot]
		local plant = p.plants[spot]
		if not entry or type(entry.c) ~= "string" then
			if plant then
				plant.model:Destroy()
				p.plants[spot] = nil
			end
		else
			if not plant or plant.crop ~= entry.c then
				if plant then
					plant.model:Destroy()
				end
				local model = Looks.plant(entry.c)
				model:PivotTo(p.cf * CFrame.new(W.PlantSpots[spot] + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, spot * 1.3, 0))
				model.Parent = p.root
				plant = { crop = entry.c, model = model, fruit = {} }
				p.plants[spot] = plant
			end
			local letters = type(entry.f) == "string" and entry.f or ""
			for index = 1, Config.Garden.FruitCap do
				local letter = string.sub(letters, index, index)
				local current = plant.fruit[index]
				if (current and current.letter or "") ~= letter then
					if current then
						current.model:Destroy()
					end
					plant.fruit[index] = nil
					if letter ~= "" then
						local model = placeFruit(plant, index, entry.c, letter)
						if model then
							plant.fruit[index] = { letter = letter, model = model }
						end
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- The Thing
----------------------------------------------------------------------
local function buildThing(p)
	if p.thing then
		p.thing.model:Destroy()
	end
	local size = p.folder:GetAttribute("ThingSize") or 1
	local model, parts = Looks.thing(size, p.hatchCF)
	model.Parent = p.root
	p.thing = {
		model = model,
		parts = parts,
		size = size,
		lidAngle = parts.openAngle,
		nextBlink = os.clock() + 1 + math.random() * 3,
		blinkUntil = 0,
		squintUntil = 0,
		flashUntil = 0,
		nextRattle = os.clock() + 3 + math.random() * 5,
		rattleUntil = 0,
		chompStart = 0,
	}
end

local function setLid(thing, angle)
	local lidCF = thing.parts.hinge * CFrame.Angles(math.rad(angle), 0, 0) * thing.parts.lidOffset
	thing.parts.lid.CFrame = lidCF
	for _, plank in ipairs(thing.parts.lidPlanks) do
		plank.CFrame = lidCF * CFrame.new(plank:GetAttribute("LidOffset") or 0, 0.28, 0)
	end
end

local function chomp(p, perfect)
	local thing = p.thing
	if not thing then
		return
	end
	local t = os.clock()
	thing.chompStart = t
	thing.squintUntil = t + 0.35
	if perfect then
		thing.flashUntil = t + 0.25
	end
	-- crumbs
	local crumbs = Instance.new("Part")
	crumbs.Anchored = true
	crumbs.CanCollide = false
	crumbs.CanQuery = false
	crumbs.Transparency = 1
	crumbs.Size = Vector3.new(1, 1, 1)
	crumbs.CFrame = p.hatchCF * CFrame.new(0, 0.5, 0)
	crumbs.Parent = visuals
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 220, 160))
	emitter.Size = NumberSequence.new(0.35, 0)
	emitter.Speed = NumberRange.new(8, 14)
	emitter.SpreadAngle = Vector2.new(40, 40)
	emitter.Lifetime = NumberRange.new(0.4, 0.7)
	emitter.Acceleration = Vector3.new(0, -40, 0)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Rate = 0
	emitter.Parent = crumbs
	emitter:Emit(perfect and 24 or 12)
	task.delay(1, function()
		crumbs:Destroy()
	end)
end

-- An arm shoots up to catch the food just before it lands
local function armCatch(p, delay)
	local thing = p.thing
	if not thing or #thing.parts.arms == 0 then
		return
	end
	local arm = thing.parts.arms[math.random(1, #thing.parts.arms)]
	local hole = Config.Thing.Sizes[thing.size].hole
	task.delay(math.max(0, delay), function()
		if not arm.part.Parent then
			return
		end
		local up = p.hatchCF * CFrame.new(arm.side * hole * 0.15, hole * 0.35, -hole * 0.1) * CFrame.Angles(0, 0, arm.side * 0.4)
		tween(arm.part, 0.1, { CFrame = up }, Enum.EasingStyle.Back)
		task.wait(0.22)
		if arm.part.Parent then
			tween(arm.part, 0.25, { CFrame = arm.hidden }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end)
end

local function floatingText(position, text, color, size, rise)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	anchor.Parent = visuals
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(240, 60)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = anchor
	gui.Parent = anchor
	local label = UI.label(gui, { Size = UDim2.fromScale(1, 1), Text = text, TextColor3 = color or UI.Colors.Text })
	local constraint = label:FindFirstChildOfClass("UITextSizeConstraint")
	if constraint then
		constraint.MaxTextSize = size or 36
	end
	tween(anchor, 0.9, { Position = position + Vector3.new(0, rise or 5, 0) })
	task.delay(0.5, function()
		tween(label, 0.4, { TextTransparency = 1 })
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			tween(stroke, 0.4, { Transparency = 1 })
		end
	end)
	task.delay(1, function()
		anchor:Destroy()
	end)
end
UI.on("FloatingText", floatingText)

local function burp(p, rarity)
	local thing = p.thing
	if not thing then
		return
	end
	thing.chompStart = os.clock()
	thing.squintUntil = os.clock() + 0.6
	floatingText(p.hatchCF.Position + Vector3.new(0, 4, 0), "BURP!", Config.Thing.EyeColor, 44, 6)
	UI.sound("Burp")
	-- the egg pops out onto the lawn
	local egg = Looks.egg(rarity)
	egg:ScaleTo(2.6)
	local from = p.hatchCF * CFrame.new(0, -1, 0)
	local to = p.hatchCF * CFrame.new(0, 0, -11)
	egg:PivotTo(from)
	egg.Parent = visuals
	task.spawn(function()
		local duration = 0.55
		local start = os.clock()
		while os.clock() - start < duration do
			local k = (os.clock() - start) / duration
			local position = from.Position:Lerp(to.Position, k) + Vector3.new(0, math.sin(k * math.pi) * 7, 0)
			egg:PivotTo(CFrame.new(position) * CFrame.Angles(k * 6, 0, k * 2))
			RunService.RenderStepped:Wait()
		end
		egg:PivotTo(to)
		for i = 1, 6 do
			egg:PivotTo(to * CFrame.Angles(0, 0, math.sin(i * 1.7) * 0.25))
			task.wait(0.08)
		end
		egg:Destroy()
	end)
end

local function animateThing(p, t, camPos)
	local thing = p.thing
	if not thing then
		return
	end
	local parts = thing.parts
	local owner = p.folder:GetAttribute("Owner") or 0
	local asleep = owner == 0

	-- the lid: open, slams on a chomp, rattles now and then; shut when nobody lives here
	local angle = parts.openAngle
	if asleep then
		angle = 0
	else
		local since = t - thing.chompStart
		if since < 0.35 then
			angle = parts.openAngle - math.sin(since / 0.35 * math.pi) * 60
		elseif t > thing.nextRattle then
			thing.rattleUntil = t + 0.5
			thing.nextRattle = t + 4 + math.random() * 6
		end
		if t < thing.rattleUntil then
			angle += math.sin(t * 50) * 6
		end
	end
	if math.abs(angle - thing.lidAngle) > 0.05 then
		thing.lidAngle = angle
		setLid(thing, angle)
	end

	-- eyes: blink, squint, look at the nearest player
	if t > thing.nextBlink then
		thing.blinkUntil = t + 0.12
		thing.nextBlink = t + 2 + math.random() * 4
	end
	local open = 1
	if asleep then
		open = 0.08
	elseif t < thing.blinkUntil then
		open = 0.12
	elseif t < thing.squintUntil then
		open = 0.35
	end
	local target = camPos
	local mine = player.Character and player.Character:FindFirstChild("Head")
	local nearest, nearestDistance = nil, 60
	for _, other in ipairs(Players:GetPlayers()) do
		local head = other.Character and other.Character:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			local distance = (head.Position - p.hatchCF.Position).Magnitude
			if distance < nearestDistance or (head == mine and distance < 60) then
				nearest, nearestDistance = head, distance
				if head == mine then
					break
				end
			end
		end
	end
	if nearest then
		target = nearest.Position
	end
	local flash = t < thing.flashUntil
	for i, eye in ipairs(parts.eyes) do
		local s = eye.size
		eye.part.Size = Vector3.new(s, s * 1.15 * open, s)
		eye.part.Color = flash and Color3.fromRGB(255, 255, 255) or Config.Thing.EyeColor
		local pupil = parts.pupils[i]
		pupil.Transparency = open < 0.3 and 1 or 0
		local eyePosition = eye.home.Position
		local direction = (target - eyePosition)
		if direction.Magnitude > 0.01 then
			direction = direction.Unit
		else
			direction = Vector3.yAxis
		end
		pupil.CFrame = CFrame.new(eyePosition + direction * s * 0.42 * math.max(open, 0.3))
	end
end

----------------------------------------------------------------------
-- Thinglets
----------------------------------------------------------------------
local function makeTag(t, mine)
	local def = Config.Thinglets[t.record.kind]
	local rarity = Config.Rarities[def.rarity]
	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.Size = UDim2.fromOffset(170, 52)
	gui.LightInfluence = 0
	gui.MaxDistance = mine and 140 or 80
	gui.Adornee = t.model.PrimaryPart
	gui.Parent = t.model
	local name = (t.record.mut and t.record.mut ~= "" and (t.record.mut .. " ") or "") .. def.name
	UI.label(gui, { Name = "Name", Size = UDim2.fromScale(1, 0.48), Text = name, TextColor3 = rarity.color })
	local income = UI.label(gui, { Name = "Income", Size = UDim2.fromScale(1, 0.38), Position = UDim2.fromScale(0, 0.48), Text = "", TextColor3 = UI.Colors.Gold })
	local barBack = UI.new("Frame", {
		Name = "Bar", Size = UDim2.new(0.6, 0, 0, 6), Position = UDim2.new(0.2, 0, 0.9, 0),
		BackgroundColor3 = Color3.fromRGB(30, 20, 40), BorderSizePixel = 0,
	}, gui)
	UI.corner(barBack, UDim.new(1, 0))
	local fill = UI.new("Frame", { Size = UDim2.fromScale(0.25, 1), BackgroundColor3 = UI.Colors.Good, BorderSizePixel = 0 }, barBack)
	UI.corner(fill, UDim.new(1, 0))
	t.tag = { gui = gui, income = income, bar = barBack, fill = fill }
end

local function refreshThinglet(t, serverNow)
	local height = Rules.height(t.record, serverNow)
	if math.abs(height - t.height) > 0.03 then
		t.height = height
		t.model:ScaleTo(height)
	end
	t.tag.gui.StudsOffsetWorldSpace = Vector3.new(0, t.height * (t.record.kind == "Moonmoth" and 1.5 or 1.05) + 1.4, 0)
	t.tag.income.Text = "+" .. Rules.short(Rules.income(t.record, serverNow)) .. "/s"
	local progress = Rules.progress(t.record, serverNow)
	t.tag.bar.Visible = progress < 1
	t.tag.fill.Size = UDim2.fromScale(progress, 1)
end

local function updateYard(p)
	local list = decode(p.folder:GetAttribute("Yard"))
	local seen = {}
	local mine = (p.folder:GetAttribute("Owner") or 0) == player.UserId
	for _, r in ipairs(list) do
		if type(r.id) == "string" and Config.Thinglets[r.k] then
			seen[r.id] = true
			local slot = W.YardSlots[r.slot] or W.YardSlots[1]
			local home = p.cf * CFrame.new(slot)
			local t = p.thinglets[r.id]
			if not t then
				local record = { kind = r.k, mut = r.m, born = r.b, start = r.s }
				local model = Looks.thinglet(r.k, r.m, true)
				model:SetAttribute("ThingletId", r.id)
				model:SetAttribute("Plot", p.index)
				local height = Rules.height(record, now())
				model:ScaleTo(height)
				model:PivotTo(home)
				model.Parent = thingletFolder
				t = { id = r.id, record = record, model = model, home = home, height = height, seed = math.random() * 100 }
				makeTag(t, mine)
				refreshThinglet(t, now())
				p.thinglets[r.id] = t
				-- grow in from nothing
				task.spawn(function()
					for step = 1, 10 do
						if not model.Parent then
							return
						end
						model:ScaleTo(t.height * (0.1 + 0.9 * step / 10) * (1 + math.sin(step / 10 * math.pi) * 0.2))
						task.wait(1 / 30)
					end
					if model.Parent then
						model:ScaleTo(t.height)
					end
				end)
			else
				t.home = home
			end
		end
	end
	for id, t in pairs(p.thinglets) do
		if not seen[id] then
			local position = t.model:GetPivot().Position
			t.model:Destroy()
			p.thinglets[id] = nil
			floatingText(position + Vector3.new(0, 2, 0), "poof!", UI.Colors.Dim, 28, 3)
		end
	end
end

local IDLE = {}
-- each returns: height offset (share of its height), pitch, roll
IDLE.Blorp = function(t, s)
	return math.abs(math.sin(t * 4 + s)) * 0.12, 0, 0
end
IDLE.Sizzle = function(t, s)
	return 0, 0, math.sin(t * 8 + s) * 0.08
end
IDLE.Peeper = function(t, s)
	return math.abs(math.sin(t * 2 + s)) * 0.04, 0, 0
end
IDLE.Glumcap = function(t, s)
	return 0, 0, math.sin(t * 1.2 + s) * 0.1
end
IDLE.Gourdo = function(t, s)
	return math.abs(math.sin(t * 2 + s)) * 0.04, 0, math.sin(t * 2 + s) * 0.05
end
IDLE.Mishmash = function(t, s)
	return 0, math.sin(t * 5 + s) * 0.08, math.cos(t * 4 + s) * 0.08
end
IDLE.Moonmoth = function(t, s)
	return 0.35 + math.sin(t * 2 + s) * 0.08, 0, math.sin(t * 1.3 + s) * 0.15
end
IDLE.LilThing = function(t, s)
	return math.sin(t * 1.5 + s) * 0.04, 0, math.sin(t * 3 + s) * 0.05
end

local function animateThinglet(t, clock, heads)
	local s = t.seed
	local h = t.height
	local wander = 1.2 + h * 0.18
	local local_ = Vector3.new(math.sin(clock * 0.21 + s) * wander, 0, math.cos(clock * 0.17 + s * 1.7) * wander)
	local position = (t.home * CFrame.new(local_)).Position
	-- look at the nearest player close by, otherwise where it's wandering
	local lookAt
	local nearest = 26 + h
	for _, head in ipairs(heads) do
		local d = (head - position).Magnitude
		if d < nearest then
			nearest = d
			lookAt = head
		end
	end
	if not lookAt then
		local ahead = Vector3.new(math.cos(clock * 0.21 + s) * 0.21 * wander, 0, -math.sin(clock * 0.17 + s * 1.7) * 0.17 * wander)
		lookAt = position + (t.home.Rotation * ahead) * 10
	end
	local idle = IDLE[t.record.kind] or IDLE.Blorp
	local lift, pitch, roll = idle(clock, s)
	local flat = Vector3.new(lookAt.X, position.Y, lookAt.Z)
	local facing
	if (flat - position).Magnitude > 0.05 then
		facing = CFrame.lookAt(position, flat)
	else
		facing = CFrame.new(position)
	end
	t.model.PrimaryPart.CFrame = facing * CFrame.new(0, lift * h, 0) * CFrame.Angles(pitch, 0, roll)
end

----------------------------------------------------------------------
-- Plots
----------------------------------------------------------------------
local function setupPlot(folder)
	local index = folder:GetAttribute("Index")
	if type(index) ~= "number" or plots[index] then
		return
	end
	local cf = Rules.plotCFrame(index)
	local root = Instance.new("Folder")
	root.Name = "Plot" .. index
	root.Parent = visuals
	local p = {
		index = index,
		folder = folder,
		cf = cf,
		hatchCF = cf * CFrame.new(W.Hatch),
		root = root,
		plants = {},
		thinglets = {},
	}
	plots[index] = p
	buildThing(p)
	updatePlants(p)
	updateYard(p)
	folder:GetAttributeChangedSignal("Plants"):Connect(function()
		updatePlants(p)
	end)
	folder:GetAttributeChangedSignal("Yard"):Connect(function()
		updateYard(p)
	end)
	folder:GetAttributeChangedSignal("ThingSize"):Connect(function()
		buildThing(p)
	end)
	folder:GetAttributeChangedSignal("Owner"):Connect(function()
		-- the tags of your own Thinglets show from further away
		for id, t in pairs(p.thinglets) do
			t.model:Destroy()
			p.thinglets[id] = nil
		end
		updateYard(p)
	end)
end

for _, folder in ipairs(plotsFolder:GetChildren()) do
	setupPlot(folder)
end
plotsFolder.ChildAdded:Connect(function(folder)
	task.wait()
	setupPlot(folder)
end)

local function myPlot()
	for _, p in pairs(plots) do
		if p.folder:GetAttribute("Owner") == player.UserId then
			return p
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Messages from the server and the other client scripts
----------------------------------------------------------------------
FxRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or payload.type ~= "chomp" then
		return
	end
	local p = plots[payload.plot]
	local mine = myPlot()
	if p and p ~= mine then
		chomp(p, payload.perfect)
	end
end)

UI.on("Chomp", function(perfect)
	local p = myPlot()
	if p then
		chomp(p, perfect)
	end
end)

UI.on("ArmCatch", function(delay)
	local p = myPlot()
	if p then
		armCatch(p, delay)
	end
end)

HatchedRemote.OnClientEvent:Connect(function(info)
	local p = myPlot()
	local def = type(info) == "table" and Config.Thinglets[info.kind]
	if p and def then
		burp(p, def.rarity)
	end
end)

-- fruit hop from the plant into your basket
HarvestedRemote.OnClientEvent:Connect(function(picked)
	local p = myPlot()
	if not p or type(picked) ~= "table" then
		return
	end
	local count = 0
	for _, entry in ipairs(picked) do
		local spot = W.PlantSpots[entry.spot]
		if spot then
			for i = 1, #entry.fruit do
				count += 1
				local n = count
				local letter = string.sub(entry.fruit, i, i)
				local delay = n * 0.06
				task.delay(delay, function()
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if not root or not root:IsA("BasePart") then
						return
					end
					local fruit = Looks.fruit(entry.crop, LETTER_MUT[letter] or "", false)
					fruit:ScaleTo(FRUIT_SCALE[entry.crop] or 1)
					local from = (p.cf * CFrame.new(spot + Vector3.new(0, 2, 0))).Position
					fruit:PivotTo(CFrame.new(from))
					fruit.Parent = visuals
					UI.sound("Pop", 0.6, 1 + math.min(n, 10) * 0.05)
					local duration = 0.45
					local start = os.clock()
					while os.clock() - start < duration do
						local k = (os.clock() - start) / duration
						local to = root.Position + Vector3.new(0, 1, 0)
						local position = from:Lerp(to, k) + Vector3.new(0, math.sin(k * math.pi) * 5, 0)
						fruit:PivotTo(CFrame.new(position) * CFrame.Angles(k * 5, k * 3, 0))
						fruit:ScaleTo((FRUIT_SCALE[entry.crop] or 1) * (1 - k * 0.6))
						RunService.RenderStepped:Wait()
					end
					fruit:Destroy()
				end)
			end
		end
	end
	UI.fire("Harvested", picked)
end)

-- Tap a Thinglet to see its card
local tapStart = nil
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		tapStart = { position = input.Position, time = os.clock() }
	end
end)
UserInputService.InputEnded:Connect(function(input, processed)
	if processed or not tapStart then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local moved = (Vector2.new(input.Position.X, input.Position.Y) - Vector2.new(tapStart.position.X, tapStart.position.Y)).Magnitude
	local quick = os.clock() - tapStart.time < 0.35
	tapStart = nil
	if moved > 12 or not quick then
		return
	end
	local camera = workspace.CurrentCamera
	local ray = camera:ScreenPointToRay(input.Position.X, input.Position.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { thingletFolder }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 300, params)
	if not hit then
		return
	end
	local model = hit.Instance:FindFirstAncestorOfClass("Model")
	while model and model.Parent ~= thingletFolder do
		model = model:FindFirstAncestorOfClass("Model")
	end
	if not model then
		return
	end
	local p = plots[model:GetAttribute("Plot")]
	local t = p and p.thinglets[model:GetAttribute("ThingletId")]
	if t then
		UI.fire("ThingletTapped", {
			id = t.id,
			record = t.record,
			mine = (p.folder:GetAttribute("Owner") or 0) == player.UserId,
			ownerName = p.folder:GetAttribute("OwnerName") or "",
		})
	end
end)

----------------------------------------------------------------------
-- Weather
----------------------------------------------------------------------
local defaultLight = {
	ClockTime = Lighting.ClockTime,
	Brightness = Lighting.Brightness,
	OutdoorAmbient = Lighting.OutdoorAmbient,
	Ambient = Lighting.Ambient,
}
local snowPart = nil

local function setWeather(id)
	if snowPart then
		snowPart:Destroy()
		snowPart = nil
	end
	-- the server sets Lighting once; remember it before we change it
	if id == "" then
		local sky = Lighting:FindFirstChildOfClass("Sky")
		if sky then
			sky.MoonAngularSize = 11
		end
		tween(Lighting, 3, {
			ClockTime = defaultLight.ClockTime,
			Brightness = defaultLight.Brightness,
			OutdoorAmbient = defaultLight.OutdoorAmbient,
			Ambient = defaultLight.Ambient,
		})
	elseif id == "FullMoon" then
		local sky = Lighting:FindFirstChildOfClass("Sky")
		if sky then
			sky.MoonAngularSize = 30 -- a big moon (the default is 11)
		end
		tween(Lighting, 3, {
			ClockTime = 0,
			Brightness = 1.2,
			OutdoorAmbient = Color3.fromRGB(110, 95, 170),
			Ambient = Color3.fromRGB(90, 80, 140),
		})
	elseif id == "Snow" then
		tween(Lighting, 3, {
			ClockTime = defaultLight.ClockTime,
			Brightness = 1.8,
			OutdoorAmbient = Color3.fromRGB(170, 190, 220),
		})
		local part = Instance.new("Part")
		part.Name = "Snow"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.Transparency = 1
		part.Size = Vector3.new(160, 1, 160)
		part.Parent = visuals
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		emitter.Size = NumberSequence.new(0.35)
		emitter.Rate = 160
		emitter.Lifetime = NumberRange.new(5, 7)
		emitter.Speed = NumberRange.new(8, 12)
		emitter.SpreadAngle = Vector2.new(15, 15)
		emitter.EmissionDirection = Enum.NormalId.Bottom
		emitter.Parent = part
		snowPart = part
	end
end

task.defer(function()
	-- let the server's lighting arrive first
	task.wait(1)
	defaultLight = {
		ClockTime = Lighting.ClockTime,
		Brightness = Lighting.Brightness,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		Ambient = Lighting.Ambient,
	}
	setWeather(ReplicatedStorage:GetAttribute("Weather") or "")
	ReplicatedStorage:GetAttributeChangedSignal("Weather"):Connect(function()
		setWeather(ReplicatedStorage:GetAttribute("Weather") or "")
	end)
end)

----------------------------------------------------------------------
-- Every frame
----------------------------------------------------------------------
local refreshTimer = 0
RunService.RenderStepped:Connect(function(dt)
	local camera = workspace.CurrentCamera
	local camPos = camera.CFrame.Position
	local clock = os.clock()
	if snowPart then
		snowPart.CFrame = CFrame.new(camPos + Vector3.new(0, 40, 0))
	end

	local heads = {}
	for _, other in ipairs(Players:GetPlayers()) do
		local head = other.Character and other.Character:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			table.insert(heads, head.Position)
		end
	end

	refreshTimer += dt
	local refresh = refreshTimer >= 1
	if refresh then
		refreshTimer = 0
	end
	local serverNow = now()

	for _, p in pairs(plots) do
		local near = (p.cf.Position - camPos).Magnitude < ANIMATE_RANGE + 60
		if near then
			animateThing(p, clock, camPos)
		end
		for _, t in pairs(p.thinglets) do
			if refresh then
				refreshThinglet(t, serverNow)
			end
			if near and (t.home.Position - camPos).Magnitude < ANIMATE_RANGE then
				animateThinglet(t, clock, heads)
			end
		end
	end
end)
