--[[
	World  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "World")

	Draws everything alive in the world, on your own screen: every Thing
	(eyes, arms, lid), every plot's nests and eggs (with their countdowns),
	every Thinglet (growing, wandering, looking at you, with its name tag),
	the weather, the coin truck, and little effects like the egg the Thing
	burps out and the poof when it hatches.

	It reads the plot attributes the server keeps in ReplicatedStorage.Plots,
	so all players see the same eggs and yards - but the animation runs
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
-- the Assets module (an old props import may also be called "Assets")
local function waitForModule(name)
	while true do
		for _, child in ipairs(ReplicatedStorage:GetChildren()) do
			if child.Name == name and child:IsA("ModuleScript") then
				return child
			end
		end
		ReplicatedStorage.ChildAdded:Wait()
	end
end
local Assets = require(waitForModule("Assets"))

local remoteFolder = ReplicatedStorage:WaitForChild("Remotes")
local HatchedRemote = remoteFolder:WaitForChild("Hatched") :: RemoteEvent
local FxRemote = remoteFolder:WaitForChild("Fx") :: RemoteEvent
local plotsFolder = ReplicatedStorage:WaitForChild("Plots")

local player = Players.LocalPlayer
local W = Config.World

local ANIMATE_RANGE = 170 -- studs from the camera; further away things stand still

local visuals = Instance.new("Folder")
visuals.Name = "LocalWorld"
visuals.Parent = workspace
local NEST_Y = 0.6 -- the top of the dirt in the planters
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

local function chomp(p)
	local thing = p.thing
	if not thing then
		return
	end
	local t = os.clock()
	thing.chompStart = t
	thing.squintUntil = t + 0.35
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
	emitter:Emit(12)
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

-- a glowing ring that spreads out over the ground (a rare hatch)
UI.on("Shockwave", function(position, color)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = color or Color3.fromRGB(255, 220, 60)
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.2, 4, 4)
	ring.CFrame = CFrame.new(position + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = visuals
	tween(ring, 0.45, { Size = Vector3.new(0.2, 26, 26), Transparency = 1 })
	task.delay(0.5, function()
		ring:Destroy()
	end)
end)

local function heardHere(position)
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - position).Magnitude < 80
end

local function poof(position, color, amount)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(1, 1, 1)
	holder.Position = position
	holder.Parent = visuals
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color or Color3.fromRGB(255, 255, 255))
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	emitter.Speed = NumberRange.new(6, 14)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Drag = 4
	emitter.Rate = 0
	emitter.Parent = holder
	emitter:Emit(amount or 20)
	task.delay(1.2, function()
		holder:Destroy()
	end)
end

----------------------------------------------------------------------
-- Nests and eggs. The Thing burps each egg onto a nest; it sits there
-- with its countdown, wobbling more and more, then pops and the Thinglet
-- hops out to the yard.
----------------------------------------------------------------------
local function nestCF(p, n)
	local spot = Config.Eggs.NestSpots[n]
	return spot and p.cf * CFrame.new(spot + Vector3.new(0, NEST_Y, 0)) or nil
end

local function updateNests(p)
	local count = math.min(p.folder:GetAttribute("Nests") or 0, #Config.Eggs.NestSpots)
	for n = 1, #Config.Eggs.NestSpots do
		local nest = p.nests[n]
		if n <= count and not nest then
			nest = Looks.nest()
			nest:PivotTo((nestCF(p, n) :: CFrame) * CFrame.Angles(0, n * 1.3, 0))
			nest.Parent = p.root
			p.nests[n] = nest
			if p.ready then
				-- a new nest (the Nests upgrade): it pops in
				poof(nest:GetPivot().Position + Vector3.new(0, 1, 0), Color3.fromRGB(225, 180, 95), 20)
			end
		elseif n > count and nest then
			nest:Destroy()
			p.nests[n] = nil
		end
	end
end

local function countdownTag(egg)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Countdown"
	gui.Size = UDim2.fromOffset(90, 34)
	gui.StudsOffsetWorldSpace = Vector3.new(0, Config.Eggs.Size + 1.2, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 70
	gui.Adornee = egg.model.PrimaryPart
	gui.Parent = egg.model
	egg.tag = gui
	egg.label = UI.number(gui, { Size = UDim2.fromScale(1, 1), Text = "" })
end

local function makeEgg(p, e)
	local crop = Rules.crop(e.f)
	local model = Looks.egg("Common", crop and crop.color)
	model:ScaleTo(Config.Eggs.Size)
	local egg = {
		id = e.id,
		nest = e.n,
		food = e.f,
		laid = e.l,
		ready = e.r,
		model = model,
		home = (nestCF(p, e.n) :: CFrame) * CFrame.new(0, 0.25, 0) * CFrame.Angles(0, math.random() * 6, 0),
		landed = false,
		seed = math.random() * 10,
	}
	model:PivotTo(egg.home)
	countdownTag(egg)
	return egg
end

local function arc(from, to, k, height)
	return from:Lerp(to, k) + Vector3.new(0, math.sin(k * math.pi) * height, 0)
end

-- BURP! The egg comes out of the hatch and lands on its nest. Waits until
-- just after the food has gone down (the owner's throw takes a moment).
local function burpEgg(p, egg)
	local at = (egg.laid or now()) + 0.7
	if at > now() then
		task.wait(at - now())
	end
	if not egg.model.Parent then
		return
	end
	local thing = p.thing
	if thing then
		thing.chompStart = os.clock()
		thing.squintUntil = os.clock() + 0.6
	end
	local from = p.hatchCF.Position + Vector3.new(0, 1, 0)
	if heardHere(from) then
		UI.sound("Burp", 0.8, 0.9 + math.random() * 0.2)
	end
	floatingText(from + Vector3.new(0, 3, 0), "BURP!", Config.Thing.EyeColor, 40, 5)
	local to = egg.home.Position
	local duration = 0.6
	local start = os.clock()
	while os.clock() - start < duration do
		if not egg.model.Parent then
			return
		end
		local k = (os.clock() - start) / duration
		egg.model:PivotTo(CFrame.new(arc(from, to, k, 8)) * CFrame.Angles(k * 6, 0, k * 2))
		RunService.RenderStepped:Wait()
	end
	if not egg.model.Parent then
		return
	end
	egg.model:PivotTo(egg.home)
	poof(to, Color3.fromRGB(225, 180, 95), 10)
	if heardHere(to) then
		UI.sound("Thud", 0.35, 1.4)
	end
	egg.landed = true
end

-- the egg pops: a flash of its food's colour (or, if it never hatched -
-- its owner left - it just goes)
local function popEgg(egg)
	local position = egg.model:GetPivot().Position + Vector3.new(0, Config.Eggs.Size * 0.5, 0)
	if now() >= egg.ready - 1 then
		local crop = Rules.crop(egg.food)
		poof(position, crop and crop.color or nil, 26)
		poof(position, Color3.fromRGB(255, 250, 235), 14)
		if heardHere(position) then
			UI.sound("Crack", 0.7)
		end
	end
	egg.model:Destroy()
end

local function updateEggs(p)
	local list = decode(p.folder:GetAttribute("Eggs"))
	local seen = {}
	for _, e in ipairs(list) do
		if type(e.id) == "string" and Rules.crop(e.f) and type(e.r) == "number" and nestCF(p, e.n) then
			seen[e.id] = true
			if not p.eggs[e.id] then
				local egg = makeEgg(p, e)
				p.eggs[e.id] = egg
				if p.ready and type(e.l) == "number" and now() - e.l < 2 then
					-- just laid: it hides in the Thing until the burp
					egg.model:PivotTo(p.hatchCF * CFrame.new(0, -6, 0))
					egg.model.Parent = p.root
					task.spawn(burpEgg, p, egg)
				else
					egg.landed = true
					egg.model.Parent = p.root
				end
			end
		end
	end
	for id, egg in pairs(p.eggs) do
		if not seen[id] then
			p.eggs[id] = nil
			popEgg(egg)
		end
	end
end

-- every frame, for the eggs near you: the countdown, and a wobble that
-- gets wilder as it's about to hatch
local function animateEgg(egg, t, clock)
	local left = egg.ready - t
	if egg.label then
		local seconds = math.max(0, math.ceil(left))
		egg.label.Text = seconds > 0 and (seconds .. "s") or "!"
		egg.label.TextColor3 = seconds <= 3 and UI.Colors.Gold or UI.Colors.Text
		egg.tag.Enabled = egg.landed
	end
	if not egg.landed then
		return
	end
	local shake = left < 3 and (1 - math.max(0, left) / 3) or 0
	local tilt = math.sin(clock * (6 + shake * 14) + egg.seed) * (0.04 + shake * 0.22)
	local hop = left < 1 and math.abs(math.sin(clock * 18)) * 0.3 or 0
	egg.model:PivotTo(egg.home * CFrame.new(0, hop, 0) * CFrame.Angles(tilt * 0.5, 0, tilt))
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
	-- the owner's Comfy yard upgrade and friend bonus (published on the plot)
	local p = plots[t.model:GetAttribute("Plot")]
	local mult = p and p.folder:GetAttribute("IncomeMult") or 1
	t.tag.income.Text = "+" .. Rules.rate(Rules.income(t.record, serverNow) * (tonumber(mult) or 1)) .. "/s"
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
				local fromNest = type(r.n) == "number" and nestCF(p, r.n)
				if p.ready and fromNest and type(r.b) == "number" and now() - r.b < 4 then
					-- just hatched: it hops out of its nest to its spot in the yard
					t.arriving = true
					task.spawn(function()
						local from = fromNest
						local to = home
						local hops = 4
						for hop = 1, hops do
							local a = from:Lerp(to, (hop - 1) / hops)
							local b = from:Lerp(to, hop / hops)
							for step = 1, 12 do
								if not model.Parent then
									return
								end
								local k = step / 12
								local position = a.Position:Lerp(b.Position, k) + Vector3.new(0, math.sin(k * math.pi) * (2 + t.height * 0.3), 0)
								model.PrimaryPart.CFrame = CFrame.lookAt(position, Vector3.new(b.Position.X, position.Y, b.Position.Z) + (b.Position - a.Position) * 0.01)
								task.wait(1 / 40)
							end
							UI.sound("Pop", 0.4, 0.8 + hop * 0.1)
						end
						t.arriving = false
					end)
				else
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
				end
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
		nests = {},
		eggs = {},
		thinglets = {},
	}
	plots[index] = p
	buildThing(p)
	updateNests(p)
	updateEggs(p)
	updateYard(p)
	p.ready = true
	folder:GetAttributeChangedSignal("Nests"):Connect(function()
		updateNests(p)
	end)
	folder:GetAttributeChangedSignal("Eggs"):Connect(function()
		updateEggs(p)
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

-- The Blender Thinglets load a moment after the game starts: once they're
-- there, swap out any block-built stand-ins
task.spawn(function()
	for _ = 1, 60 do
		if Looks.hasBlenderArt() then
			for _, p in pairs(plots) do
				local stale = false
				for id, t in pairs(p.thinglets) do
					if not t.model:GetAttribute("Blender") then
						t.model:Destroy()
						p.thinglets[id] = nil
						stale = true
					end
				end
				if stale then
					updateYard(p)
				end
			end
			return
		end
		task.wait(3)
	end
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
-- The coin truck: out of the tunnel, a stop, the throw, the bounce, and
-- the package bursts into coins
----------------------------------------------------------------------
local function runDelivery(payload)
	local p = plots[payload.plot]
	if not p or type(payload.start) ~= "number" then
		return
	end
	local D = Config.Delivery
	local times = Rules.deliveryTimes(payload.plot)
	local plotX, _, side = Rules.plotSpot(payload.plot)
	local laneZ = side * D.Lane
	local start = payload.start
	if now() - start > times.total then
		return -- joined too late to see it
	end
	if start > now() then
		task.wait(start - now())
	end

	local truck = Assets.get("Truck") or Looks.truck()
	local wheels, parts = {}, {}
	for _, d in ipairs(truck:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, { part = d, transparency = d.Transparency })
			if string.find(d.Name, "Wheel") then
				table.insert(wheels, { part = d, offset = d.CFrame })
			end
		end
	end
	-- headlights, so it lights up the tunnel walls on its way in and out
	local headlights = Instance.new("SpotLight")
	headlights.Face = Enum.NormalId.Front
	headlights.Angle = 70
	headlights.Range = 28
	headlights.Brightness = 0
	headlights.Color = Color3.fromRGB(255, 240, 200)
	headlights.Shadows = false
	-- exhaust puffs out of the back
	local puff = Instance.new("ParticleEmitter")
	puff.Color = ColorSequence.new(Color3.fromRGB(220, 220, 230))
	puff.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.6) })
	puff.Transparency = NumberSequence.new(0.2, 1)
	puff.Lifetime = NumberRange.new(0.5, 0.8)
	puff.Rate = 12
	puff.Speed = NumberRange.new(2, 3)
	puff.EmissionDirection = Enum.NormalId.Back
	puff.Parent = truck.PrimaryPart
	headlights.Parent = truck.PrimaryPart
	local shown = -1
	local function fade(visible)
		-- out of (and into) the dark: the truck fades in and out
		visible = math.floor(visible * 20 + 0.5) / 20
		if visible == shown then
			return
		end
		shown = visible
		for _, entry in ipairs(parts) do
			entry.part.Transparency = entry.transparency + (1 - entry.transparency) * (1 - visible)
		end
		puff.Enabled = visible > 0.6
		headlights.Brightness = 3 * visible
	end
	fade(Rules.truckVisible(D.StartX))
	truck.Parent = visuals

	local landCF = p.cf * CFrame.new(D.LandAt)
	local package, packageStart, honked, landed, opened = nil, nil, false, false, false
	local lastX, spin = D.StartX, 0
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		local t = now() - start
		-- the truck: out of the west tunnel, brake hard at the plot, then off
		-- into the east tunnel
		local x, phase, u = Rules.truckX(payload.plot, t)
		local lean = 0
		if phase == "drive" then
			if u > 0.65 then
				lean = math.sin((u - 0.65) / 0.35 * math.pi) * 0.14 -- the nose dips as it brakes
			end
		elseif phase == "stop" then
			lean = -math.sin(math.min(1, u / 0.35) * math.pi) * 0.05 -- and rocks back
			if not honked then
				honked = true
				if heardHere(Vector3.new(plotX, 10, laneZ)) then
					UI.sound("Honk", 0.8)
				end
				floatingText(Vector3.new(plotX, 10, laneZ), "HONK!", Color3.fromRGB(255, 220, 60), 40, 4)
			end
		else
			lean = -math.sin(math.min(1, u / 0.5) * math.pi) * 0.04 -- it squats as it pulls away
		end
		local speed = dt > 0 and (x - lastX) / dt or 0
		lastX = x
		spin += speed * dt / 1.55
		local bob = math.sin(t * 18) * 0.05 * math.min(1, math.abs(speed) / 30)
		local truckCF = CFrame.lookAt(Vector3.new(x, 0.2 + bob, laneZ), Vector3.new(x + 1, 0.2 + bob, laneZ)) * CFrame.Angles(-lean, 0, 0)
		if truck.Parent then
			truck:PivotTo(truckCF)
			for _, w in ipairs(wheels) do
				w.part.CFrame = truckCF * w.offset * CFrame.Angles(-spin, 0, 0)
			end
			fade(Rules.truckVisible(x))
			if x >= D.EndX then
				truck:Destroy() -- gone, deep in the tunnel
			end
		end

		-- the package: thrown off the back in a big lazy arc
		if t >= times.throwAt and not package then
			package = Assets.get("Package") or Looks.package()
			package.Parent = visuals
			packageStart = (truckCF * CFrame.new(0, 8.5, 2)).Position
			UI.sound("Throw", 0.7, 0.8)
		end
		if package and not landed then
			local k = math.clamp((t - times.throwAt) / D.Throw, 0, 1)
			local position = arc(packageStart, landCF.Position, k, 16)
			package:PivotTo(CFrame.new(position) * CFrame.Angles(k * 7, k * 3, k * 2))
			if k >= 1 then
				landed = true
				UI.sound("Thud", 0.8)
				poof(landCF.Position, Color3.fromRGB(200, 170, 120), 16)
			end
		end
		if landed and not opened then
			-- squash, bounce, wobble...
			local since = t - times.landAt
			local hop = since > 0.15 and since < 0.45 and math.sin((since - 0.15) / 0.3 * math.pi) * 1.6 or 0
			local squash = since < 0.15 and (1 - math.sin(since / 0.15 * math.pi) * 0.35) or 1
			package:PivotTo(landCF * CFrame.new(0, hop, 0) * CFrame.Angles(0, since * 2, math.sin(since * 30) * 0.08 * (1 - math.min(1, since))))
			package:ScaleTo(math.max(0.3, squash))
			-- ...then POP: it bursts into coins
			if since >= 0.55 then
				opened = true
				local burst = landCF.Position + Vector3.new(0, 1.2, 0)
				if heardHere(burst) then
					UI.sound("Poof", 0.8)
				end
				poof(burst, UI.Colors.Gold, 40)
				poof(burst, Color3.fromRGB(255, 250, 200), 16)
				floatingText(burst + Vector3.new(0, 3, 0), "COINS!", UI.Colors.Gold, 40, 5)
				package:Destroy()
			end
		end
		if (t > times.total + 1 and not truck.Parent) or t > times.total + 20 then
			connection:Disconnect()
			if truck.Parent then
				truck:Destroy()
			end
			if package and package.Parent then
				package:Destroy()
			end
		end
	end)
end

----------------------------------------------------------------------
-- Messages from the server and the other client scripts
----------------------------------------------------------------------
FxRemote.OnClientEvent:Connect(function(payload)
	if type(payload) == "table" and payload.type == "delivery" then
		task.spawn(runDelivery, payload)
	end
end)

-- your food went down the hatch
UI.on("Chomp", function()
	local p = myPlot()
	if p then
		chomp(p)
	end
end)

UI.on("ArmCatch", function(delay)
	local p = myPlot()
	if p then
		armCatch(p, delay)
	end
end)

-- Your egg hatched. A rare one sends a ring out over the lawn; one that
-- was sold straight away (your yard is full of better ones) turns into coins.
HatchedRemote.OnClientEvent:Connect(function(info)
	local p = myPlot()
	local def = type(info) == "table" and Config.Thinglets[info.kind]
	local cf = p and type(info.nest) == "number" and nestCF(p, info.nest)
	if not def or not cf then
		return
	end
	local position = cf.Position + Vector3.new(0, 1, 0)
	if Rules.rarityRank(def.rarity) >= 3 then
		UI.fire("Shockwave", position, Config.Rarities[def.rarity].color)
	end
	if info.how == "sell" then
		task.delay(0.3, function()
			UI.fire("CoinBurst", position, info.sold or 1)
		end)
	end
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

-- Weather keeps the game bright: it tints the world and adds particles
-- (a dark night made everything muddy, especially on phones).
local moonPart = nil
local weatherOffset = Vector3.new(0, 40, 0) -- where the particle sheet floats, from the camera

local function followerEmitter(props, offset)
	local part = Instance.new("Part")
	part.Name = "WeatherParticles"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(160, 1, 160)
	part.Parent = visuals
	local emitter = Instance.new("ParticleEmitter")
	for key, value in pairs(props) do
		(emitter :: any)[key] = value
	end
	emitter.Parent = part
	weatherOffset = offset
	return part
end

local function setWeather(id)
	if snowPart then
		snowPart:Destroy()
		snowPart = nil
	end
	if moonPart then
		moonPart:Destroy()
		moonPart = nil
	end
	local grade = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	local function tint(color)
		if grade then
			tween(grade, 3, { TintColor = color })
		end
	end
	if id == "" then
		tint(Color3.fromRGB(255, 255, 255))
		tween(Lighting, 3, {
			ClockTime = defaultLight.ClockTime,
			Brightness = defaultLight.Brightness,
			OutdoorAmbient = defaultLight.OutdoorAmbient,
			Ambient = defaultLight.Ambient,
		})
	elseif id == "FullMoon" then
		-- a magic purple afternoon with a giant moon and glowing motes rising
		tint(Color3.fromRGB(232, 218, 255))
		tween(Lighting, 3, { OutdoorAmbient = Color3.fromRGB(185, 165, 215) })
		local moon = Instance.new("Part")
		moon.Name = "Moon"
		moon.Shape = Enum.PartType.Ball
		moon.Size = Vector3.new(160, 160, 160)
		moon.Anchored = true
		moon.CanCollide = false
		moon.CanQuery = false
		moon.CanTouch = false
		moon.CastShadow = false
		moon.Material = Enum.Material.Neon
		moon.Color = Color3.fromRGB(235, 225, 255)
		moon.Position = Vector3.new(700, 520, -700)
		moon.Parent = visuals
		moonPart = moon
		snowPart = followerEmitter({
			Color = ColorSequence.new(Color3.fromRGB(200, 150, 255), Color3.fromRGB(150, 255, 190)),
			LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.4), NumberSequenceKeypoint.new(1, 0) }),
			Rate = 45,
			Lifetime = NumberRange.new(4, 6),
			Speed = NumberRange.new(1.5, 3),
			SpreadAngle = Vector2.new(25, 25),
			EmissionDirection = Enum.NormalId.Top,
		}, Vector3.new(0, -8, 0))
	elseif id == "Snow" then
		tint(Color3.fromRGB(228, 242, 255))
		tween(Lighting, 3, { OutdoorAmbient = Color3.fromRGB(185, 200, 225) })
		snowPart = followerEmitter({
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
			Size = NumberSequence.new(0.35),
			Rate = 160,
			Lifetime = NumberRange.new(5, 7),
			Speed = NumberRange.new(8, 12),
			SpreadAngle = Vector2.new(15, 15),
			EmissionDirection = Enum.NormalId.Bottom,
		}, Vector3.new(0, 40, 0))
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
		snowPart.CFrame = CFrame.new(camPos + weatherOffset)
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
			for _, egg in pairs(p.eggs) do
				animateEgg(egg, serverNow, clock)
			end
		end
		for _, t in pairs(p.thinglets) do
			if refresh then
				refreshThinglet(t, serverNow)
			end
			if near and not t.arriving and (t.home.Position - camPos).Magnitude < ANIMATE_RANGE then
				animateThinglet(t, clock, heads)
			end
		end
	end
end)
