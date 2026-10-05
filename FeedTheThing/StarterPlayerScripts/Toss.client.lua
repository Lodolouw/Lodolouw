--[[
	Toss  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "Toss")

	The core action: near your hatch, a big throw pad appears at the bottom
	of the screen with your basket beside it. A ring pulses round the pad
	(and round the hatch); let go while it's small and gold for PERFECT.
	Tap or swipe up on the pad (PC: click it, or press E; 1-6 pick a food).

	Also draws, over your hatch: the belly slots, what the egg will hatch,
	the mutation odds and the craving bubble (tap it to pick that food).

	Every toss lands - there are no misses. The server judges PERFECT from
	the moment you let go, using the same clock as the ring you see.
]]

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
local TossRemote = remoteFolder:WaitForChild("Toss") :: RemoteEvent
local TossResultRemote = remoteFolder:WaitForChild("TossResult") :: RemoteEvent
local StateRemote = remoteFolder:WaitForChild("State") :: RemoteEvent
local plotsFolder = ReplicatedStorage:WaitForChild("Plots")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local W = Config.World

local state = nil
local selected = nil -- crop id
local lastThrow = 0
local inRange = false
-- Tosses the latest State doesn't include yet, so the basket counts drop the
-- moment you throw: { food, landed, result }. A toss leaves this list when
-- it's rejected, or when a State arrives after its (accepted) result.
local unconfirmed = {}
local awaitingResult = {} -- the same entries, oldest first, until their TossResult arrives

local VARIANTS = { "Gold", "Glowing", "Frozen", "Normal" }

local function tween(instance, seconds, goal, style)
	local t = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad), goal)
	t:Play()
	return t
end

local function myPlotIndex()
	for _, folder in ipairs(plotsFolder:GetChildren()) do
		if folder:GetAttribute("Owner") == player.UserId then
			return folder:GetAttribute("Index")
		end
	end
	return nil
end

local function hatchCF()
	local index = myPlotIndex()
	return index and Rules.plotCFrame(index) * CFrame.new(W.Hatch) or nil
end

local function count(cropId)
	if not state or not state.basket or not state.basket[cropId] then
		return 0
	end
	local total = 0
	for _, n in pairs(state.basket[cropId]) do
		total += n
	end
	for _, entry in ipairs(unconfirmed) do
		if entry.food == cropId then
			total -= 1
		end
	end
	return math.max(0, total)
end

local function bestVariant(cropId)
	local variants = state and state.basket and state.basket[cropId]
	if not variants then
		return ""
	end
	for _, key in ipairs(VARIANTS) do
		if (variants[key] or 0) > 0 then
			return key == "Normal" and "" or key
		end
	end
	return ""
end

local function hasMutated(cropId)
	local variants = state and state.basket and state.basket[cropId]
	if not variants then
		return false
	end
	return (variants.Gold or 0) + (variants.Glowing or 0) + (variants.Frozen or 0) > 0
end

----------------------------------------------------------------------
-- Screen GUI: throw pad, basket bar, messages
----------------------------------------------------------------------
local gui = UI.new("ScreenGui", {
	Name = "TossGui", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 5, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local PAD = 116
local STACK_HEIGHT = 250
-- the pad, the basket, the daily line and the combo sit in one stack at the
-- bottom that shrinks on short screens (a phone in landscape is ~330 tall)
local stack = UI.new("Frame", {
	Name = "Stack",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -8),
	Size = UDim2.fromOffset(520, STACK_HEIGHT),
	BackgroundTransparency = 1,
}, gui)
local stackScale = UI.new("UIScale", { Scale = 1 }, stack)
local function fitStack()
	local camera = workspace.CurrentCamera
	local height = camera and camera.ViewportSize.Y or 720
	stackScale.Scale = math.clamp(height * 0.55 / STACK_HEIGHT, 0.6, 1)
end
fitStack()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitStack)
end

local pad = UI.new("TextButton", {
	Name = "Pad",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -8),
	Size = UDim2.fromOffset(PAD, PAD),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	Text = "",
	AutoButtonColor = false,
	Visible = false,
}, stack)
UI.chunky(pad, nil, UDim.new(1, 0), 5)
local padScale = UI.new("UIScale", { Scale = 1 }, pad)

-- the pulsing ring around the pad
local ring = UI.new("Frame", {
	Name = "Ring",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(PAD + 40, PAD + 40),
	BackgroundTransparency = 1,
	ZIndex = 0,
}, pad)
UI.corner(ring, UDim.new(1, 0))
local ringStroke = UI.stroke(ring, 6, Color3.fromRGB(255, 255, 255))

local padIcon = UI.viewport(pad, nil, { Size = UDim2.fromScale(0.78, 0.78), Position = UDim2.fromScale(0.11, 0.06), ZIndex = 2 })
local padCount = UI.label(pad, {
	Size = UDim2.new(1, 0, 0, 28), Position = UDim2.new(0, 0, 1, -30), Text = "", ZIndex = 3,
})
local padEmpty = UI.label(pad, {
	Size = UDim2.fromScale(0.86, 0.5), Position = UDim2.fromScale(0.07, 0.25), Text = "Pick\nfruit!", ZIndex = 4, Visible = false,
})
local padHint = UI.label(pad, {
	Size = UDim2.new(1, 40, 0, 26), Position = UDim2.new(0, -20, 0, -30), Text = "", ZIndex = 3,
	TextColor3 = UI.Colors.Dim, Visible = false,
})

-- your foods, in a row above the pad
local basketBar = UI.new("Frame", {
	Name = "Basket",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -PAD - 26),
	Size = UDim2.fromOffset(6 * 70, 66),
	BackgroundTransparency = 1,
	Visible = false,
}, stack)
UI.new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, basketBar)

local dailyLabel = UI.number(stack, {
	Name = "Daily",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -PAD - 96),
	Size = UDim2.fromOffset(360, 24),
	TextColor3 = UI.Colors.Dim,
	Text = "",
	Visible = false,
})

local comboLabel = UI.number(stack, {
	Name = "Combo",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0.5, PAD / 2 + 16, 1, -42),
	Size = UDim2.fromOffset(170, 44),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = UI.Colors.Gold,
	Text = "",
})

local bigText = UI.number(gui, {
	Name = "Perfect",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.36),
	Size = UDim2.fromOffset(460, 80),
	TextColor3 = UI.Colors.Gold,
	Text = "",
	TextTransparency = 1,
})
local bigTextLimit = bigText:FindFirstChildOfClass("UITextSizeConstraint")
if bigTextLimit then
	bigTextLimit.MaxTextSize = 72
end

local messageLabel = UI.label(gui, {
	Name = "Message",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(420, 34),
	Text = "",
	TextTransparency = 1,
})

local messageToken = 0
local function showMessage(text, color)
	messageToken += 1
	local token = messageToken
	messageLabel.Text = text
	messageLabel.TextColor3 = color or UI.Colors.Text
	messageLabel.TextTransparency = 0
	local stroke = messageLabel:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
	end
	UI.pop(messageLabel, 0.15)
	task.delay(2, function()
		if token == messageToken then
			tween(messageLabel, 0.4, { TextTransparency = 1 })
			if stroke then
				tween(stroke, 0.4, { Transparency = 1 })
			end
		end
	end)
end
UI.on("TossMessage", showMessage)

local bigToken = 0
local function showBig(text, color)
	bigToken += 1
	local token = bigToken
	bigText.Text = text
	bigText.TextColor3 = color or UI.Colors.Gold
	bigText.TextTransparency = 0
	local stroke = bigText:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
	end
	UI.pop(bigText, 0.45)
	task.delay(0.7, function()
		if token == bigToken then
			tween(bigText, 0.3, { TextTransparency = 1 })
			if stroke then
				tween(stroke, 0.3, { Transparency = 1 })
			end
		end
	end)
end

----------------------------------------------------------------------
-- The basket bar
----------------------------------------------------------------------
local basketButtons = {} -- [crop id] = { button, count, sparkle, stroke }

local padIconKey = nil
local function selectFood(cropId)
	selected = cropId
	for id, b in pairs(basketButtons) do
		b.stroke.Color = id == selected and Color3.fromRGB(255, 255, 255) or UI.Colors.Stroke
		b.stroke.Thickness = id == selected and 4 or 3
	end
	local key = cropId and (cropId .. bestVariant(cropId)) or ""
	if key == padIconKey then
		return
	end
	padIconKey = key
	if cropId then
		UI.setViewportModel(padIcon, Looks.fruit(cropId, bestVariant(cropId), false), 200)
	else
		UI.setViewportModel(padIcon, nil)
	end
end

local function refreshBasket()
	local foods = {}
	for i, crop in ipairs(Config.Crops) do
		if count(crop.id) > 0 then
			table.insert(foods, crop.id)
		end
		local b = basketButtons[crop.id]
		if not b then
			local button = UI.new("TextButton", {
				Name = crop.id,
				LayoutOrder = i,
				Size = UDim2.fromOffset(62, 62),
				BackgroundColor3 = Color3.fromRGB(40, 42, 50),
				BackgroundTransparency = 0.25,
				Text = "",
				AutoButtonColor = false,
				Visible = false,
			}, basketBar)
			UI.corner(button, UDim.new(0, 8))
			local stroke = UI.stroke(button, 3)
			UI.label(button, {
				Size = UDim2.fromOffset(18, 16), Position = UDim2.fromOffset(4, 2), Text = tostring(i),
				TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(220, 220, 230),
			})
			UI.viewport(button, Looks.fruit(crop.id, "", false), { Size = UDim2.fromScale(0.9, 0.9), Position = UDim2.fromScale(0.05, 0.02) })
			local countLabel = UI.label(button, {
				Size = UDim2.new(1, -4, 0, 22), Position = UDim2.new(0, 0, 1, -22),
				TextXAlignment = Enum.TextXAlignment.Right, Text = "",
			})
			local sparkle = UI.new("Frame", {
				Size = UDim2.fromOffset(14, 14), Position = UDim2.fromOffset(4, 4),
				BackgroundColor3 = UI.Colors.Gold, Visible = false,
			}, button)
			UI.corner(sparkle, UDim.new(1, 0))
			UI.stroke(sparkle, 2)
			button.Activated:Connect(function()
				UI.sound("Click", 0.4)
				selectFood(crop.id)
				UI.pop(button, 0.15)
			end)
			b = { button = button, count = countLabel, sparkle = sparkle, stroke = stroke }
			basketButtons[crop.id] = b
		end
		local n = count(crop.id)
		b.button.Visible = n > 0
		b.count.Text = n > 0 and ("x" .. n) or ""
		b.sparkle.Visible = hasMutated(crop.id)
	end
	-- keep a food selected: the craving if you have it, else the rarest you have
	if not selected or count(selected) <= 0 then
		local pick = nil
		if state and state.craving ~= "" and count(state.craving) > 0 then
			pick = state.craving
		elseif #foods > 0 then
			pick = foods[#foods]
		end
		selectFood(pick)
	else
		selectFood(selected)
	end
	padCount.Text = selected and ("x" .. count(selected)) or ""
	padEmpty.Visible = selected == nil
	return #foods
end

----------------------------------------------------------------------
-- Over the hatch: belly, prediction, odds, craving bubble
----------------------------------------------------------------------
local bellyAnchor = Instance.new("Part")
bellyAnchor.Name = "BellyAnchor"
bellyAnchor.Anchored = true
bellyAnchor.CanCollide = false
bellyAnchor.CanQuery = false
bellyAnchor.Transparency = 1
bellyAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
bellyAnchor.Parent = workspace

local bellyGui = UI.new("BillboardGui", {
	Name = "Belly",
	Adornee = bellyAnchor,
	Size = UDim2.fromScale(18, 9),
	LightInfluence = 0,
	AlwaysOnTop = true,
	MaxDistance = 90,
	Enabled = false,
	ResetOnSpawn = false,
}, playerGui)

local predict = UI.label(bellyGui, { Size = UDim2.fromScale(1, 0.26), Text = "Feed me!", TextColor3 = Config.Thing.EyeColor })
local slotsRow = UI.new("Frame", { Size = UDim2.fromScale(1, 0.42), Position = UDim2.fromScale(0, 0.28), BackgroundTransparency = 1 }, bellyGui)
UI.new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0.02, 0),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, slotsRow)
local oddsLabel = UI.label(bellyGui, {
	Size = UDim2.fromScale(1, 0.22), Position = UDim2.fromScale(0, 0.74), Text = "", RichText = true, TextColor3 = UI.Colors.Dim,
})

local slots = {}
for i = 1, 5 do
	local slot = UI.new("Frame", {
		Name = "Slot" .. i,
		LayoutOrder = i,
		Size = UDim2.fromScale(0.17, 1),
		BackgroundColor3 = Color3.fromRGB(30, 20, 45),
		BackgroundTransparency = 0.15,
	}, slotsRow)
	UI.new("UIAspectRatioConstraint", { AspectRatio = 1 }, slot)
	UI.corner(slot, UDim.new(1, 0))
	local stroke = UI.stroke(slot, 3, UI.Colors.Stroke)
	local icon = UI.viewport(slot, nil, { Size = UDim2.fromScale(0.85, 0.85), Position = UDim2.fromScale(0.075, 0.075) })
	slots[i] = { frame = slot, stroke = stroke, icon = icon, food = nil, perfect = nil, mut = nil }
end

local cravingGui = UI.new("BillboardGui", {
	Name = "Craving",
	Adornee = bellyAnchor,
	Size = UDim2.fromScale(4.6, 4.6),
	StudsOffsetWorldSpace = Vector3.new(0, 5.6, 0),
	LightInfluence = 0,
	AlwaysOnTop = true,
	MaxDistance = 90,
	Enabled = false,
	Active = true,
	ResetOnSpawn = false,
}, playerGui)
local bubble = UI.new("TextButton", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(255, 250, 240),
	Text = "",
	AutoButtonColor = false,
}, cravingGui)
UI.corner(bubble, UDim.new(1, 0))
UI.stroke(bubble, 3)
local bubbleIcon = UI.viewport(bubble, nil, { Size = UDim2.fromScale(0.75, 0.75), Position = UDim2.fromScale(0.125, 0.06) })
UI.label(bubble, { Size = UDim2.fromScale(1, 0.32), Position = UDim2.fromScale(0, 0.72), Text = "x" .. Config.Toss.CravingMult, TextColor3 = UI.Colors.Gold })
local currentCraving = nil
bubble.Activated:Connect(function()
	if currentCraving and count(currentCraving) > 0 then
		selectFood(currentCraving)
		UI.pop(bubble, 0.2)
		UI.sound("Click", 0.5)
	end
end)

local function percent(x)
	return tostring(math.floor(x * 100 + 0.5)) .. "%"
end

local function hex(color)
	return string.format("#%02X%02X%02X", math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255))
end

local function refreshBelly()
	if not state then
		return
	end
	local capacity = state.bellyCap or 3
	for i, slot in ipairs(slots) do
		slot.frame.Visible = i <= capacity
		local item = state.belly[i]
		local food = item and item.f or nil
		local mut = item and item.m or nil
		local perfect = item and item.p or false
		if slot.food ~= food or slot.mut ~= mut then
			slot.food, slot.mut = food, mut
			UI.setViewportModel(slot.icon, food and Looks.fruit(food, mut or "", false) or nil, 200)
			if food then
				UI.pop(slot.frame, 0.3)
			end
		end
		slot.stroke.Color = perfect and UI.Colors.Gold or UI.Colors.Stroke
		slot.stroke.Thickness = perfect and 5 or 3
	end

	if #state.belly == 0 then
		predict.Text = "Feed me!"
		predict.TextColor3 = Config.Thing.EyeColor
	else
		local kind = Rules.resolveHatch(state.belly, capacity)
		local def = kind and Config.Thinglets[kind]
		if def and state.dex and state.dex[kind] then
			predict.Text = "Will hatch: " .. def.name
			predict.TextColor3 = Config.Rarities[def.rarity].color
		else
			predict.Text = "Will hatch: ???"
			predict.TextColor3 = UI.Colors.Text
		end
	end

	local odds = Rules.mutationOdds(state.belly, state.size or 1)
	local parts = {}
	for _, mutation in ipairs(Config.Mutations) do
		table.insert(parts, string.format('<font color="%s">%s %s</font>', hex(mutation.color), mutation.name, percent(odds[mutation.id] or 0)))
	end
	oddsLabel.Text = table.concat(parts, "   ")

	local craving = state.craving ~= "" and state.craving or nil
	if craving ~= currentCraving then
		currentCraving = craving
		if craving then
			UI.setViewportModel(bubbleIcon, Looks.fruit(craving, "", false), 200)
			UI.pop(bubble, 0.3)
		end
	end
end

----------------------------------------------------------------------
-- The ring around the hatch (12 glowing beads)
----------------------------------------------------------------------
local beads = {}
for i = 1, 12 do
	local bead = Instance.new("Part")
	bead.Name = "RingBead"
	bead.Shape = Enum.PartType.Ball
	bead.Size = Vector3.new(0.7, 0.7, 0.7)
	bead.Anchored = true
	bead.CanCollide = false
	bead.CanQuery = false
	bead.CastShadow = false
	bead.Material = Enum.Material.Neon
	bead.Transparency = 1
	bead.Parent = workspace
	beads[i] = bead
end

----------------------------------------------------------------------
-- Throwing
----------------------------------------------------------------------
local function showResult(result)
	local cf = hatchCF()
	if not cf then
		return
	end
	if not result.ok then
		if result.reason and result.reason ~= "slow" and result.reason ~= "bad" then
			showMessage(result.reason, UI.Colors.Bad)
			UI.sound("Error", 0.6)
		end
		return
	end
	local streak = result.streak or 0
	local color = UI.Colors.Gold
	if result.mut and result.mut ~= "" then
		local mutation = Rules.mutation(result.mut)
		color = mutation and mutation.color or color
	end
	UI.fire("FloatingText", cf.Position + Vector3.new(0, 3, 0), "+" .. Rules.short(result.coins), color, result.craving and 44 or 34, 6)
	UI.sound("Coin", 0.7, 1 + math.min(streak, 6) * 0.08)
	if result.perfect then
		showBig("PERFECT!", UI.Colors.Gold)
		UI.sound("Perfect", 0.8)
		UI.fire("CameraShake", 0.25)
	end
	if result.craving then
		if streak >= 2 then
			comboLabel.Text = "COMBO x" .. result.combo
			UI.sound("Combo", 0.7, 1 + streak * 0.1)
		else
			comboLabel.Text = "CRAVING x" .. Config.Toss.CravingMult
		end
		comboLabel.TextTransparency = 0
		UI.pop(comboLabel, 0.35)
	else
		comboLabel.Text = ""
	end
end

local function throwFood()
	if not state then
		return
	end
	local cf = hatchCF()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not cf or not root or not root:IsA("BasePart") then
		return
	end
	if not inRange then
		showMessage("Walk to your hatch to feed it!")
		return
	end
	if os.clock() - lastThrow < 0.22 then
		return
	end
	if (state.pending or 0) > 0 then
		UI.fire("ShowYardFull")
		return
	end
	if not selected or count(selected) <= 0 then
		refreshBasket()
		if not selected then
			showMessage("No food! Walk past your plants to pick some.")
			return
		end
	end
	local food = selected
	local mut = bestVariant(food)
	local release = workspace:GetServerTimeNow()
	local perfect = Rules.isPerfect(release)
	lastThrow = os.clock()
	local entry = { food = food, landed = false, result = nil }
	table.insert(unconfirmed, entry)
	table.insert(awaitingResult, entry)
	refreshBasket()
	TossRemote:FireServer(food, release)
	UI.sound("Throw", 0.6)
	padScale.Scale = 0.85
	tween(padScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)

	-- the food flies in an arc into the hatch
	local fruit = Looks.fruit(food, mut, false)
	fruit:ScaleTo(1.4)
	local from = root.Position + root.CFrame.RightVector * 1.2 + Vector3.new(0, 1.5, 0)
	local to = cf.Position + Vector3.new(0, -1, 0)
	local height = 5 + (from - to).Magnitude * 0.12
	fruit:PivotTo(CFrame.new(from))
	fruit.Parent = workspace
	local flight = Config.Toss.FlightTime
	if perfect then
		UI.fire("ArmCatch", flight - 0.12)
	end
	task.spawn(function()
		local start = os.clock()
		while os.clock() - start < flight do
			local k = (os.clock() - start) / flight
			local position = from:Lerp(to, k) + Vector3.new(0, math.sin(k * math.pi) * height, 0)
			fruit:PivotTo(CFrame.new(position) * CFrame.Angles(k * 9, k * 4, 0))
			RunService.RenderStepped:Wait()
		end
		fruit:Destroy()
		UI.fire("Chomp", perfect)
		UI.sound("Chomp", 0.8, 0.95 + math.random() * 0.1)
		entry.landed = true
		if entry.result then
			showResult(entry.result)
		end
	end)
end

TossResultRemote.OnClientEvent:Connect(function(result)
	if type(result) ~= "table" then
		return
	end
	-- match it to the oldest toss still waiting for its answer
	local entry = table.remove(awaitingResult, 1)
	if not entry then
		return
	end
	entry.result = result
	if not result.ok then
		-- rejected: the fruit is still yours
		local i = table.find(unconfirmed, entry)
		if i then
			table.remove(unconfirmed, i)
		end
		refreshBasket()
	end
	if entry.landed then
		showResult(result)
	end
end)

-- Tap or swipe up on the pad
local padInput = nil
pad.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		padInput = input
		tween(padScale, 0.08, { Scale = 0.92 })
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if not padInput then
		return
	end
	local same = input == padInput
		or (padInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1)
	if same then
		padInput = nil
		tween(padScale, 0.12, { Scale = 1 }, Enum.EasingStyle.Back)
		throwFood()
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonR2 then
		throwFood()
		return
	end
	local numbers = {
		[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
		[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
	}
	-- the number keys match the numbers on the basket slots
	local crop = Config.Crops[numbers[input.KeyCode] or 0]
	if crop and count(crop.id) > 0 then
		selectFood(crop.id)
	end
end)

----------------------------------------------------------------------
-- State from the server
----------------------------------------------------------------------
local function onState(newState)
	if type(newState) ~= "table" then
		return
	end
	state = newState
	UI.state = newState
	-- tosses already answered are counted in this State now
	for i = #unconfirmed, 1, -1 do
		if unconfirmed[i].result then
			table.remove(unconfirmed, i)
		end
	end
	refreshBasket()
	refreshBelly()
	local daily = state.daily
	if daily and daily.food ~= "" then
		local crop = Rules.crop(daily.food)
		if daily.done then
			dailyLabel.Text = "Daily craving done! New one tomorrow."
		elseif crop then
			dailyLabel.Text = string.format("Daily craving: feed %d/%d %s for a bonus egg", daily.fed, daily.need, crop.name)
		end
	end
	if (state.stats and state.stats.tosses or 0) == 0 then
		padHint.Text = "Tap to toss it in!"
		padHint.Visible = true
	else
		padHint.Visible = false
	end
end
StateRemote.OnClientEvent:Connect(onState)

----------------------------------------------------------------------
-- Every frame: the rings, and whether you're close enough to toss
----------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	local cf = hatchCF()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local close = false
	if cf and root and root:IsA("BasePart") then
		local d = Vector2.new(root.Position.X - cf.Position.X, root.Position.Z - cf.Position.Z).Magnitude
		close = d <= Config.Toss.Range
	end
	inRange = close and state ~= nil
	local hasFood = state ~= nil and (selected ~= nil and count(selected) > 0)

	pad.Visible = inRange
	basketBar.Visible = inRange
	dailyLabel.Visible = inRange and state ~= nil and state.daily ~= nil and state.daily.food ~= ""
	bellyGui.Enabled = cf ~= nil and state ~= nil
	cravingGui.Enabled = cf ~= nil and state ~= nil and currentCraving ~= nil and count(currentCraving) > 0
	if cf then
		local size = Config.Thing.Sizes[state and state.size or 1]
		bellyAnchor.CFrame = cf * CFrame.new(0, 7 + size.hole * 0.35, 0)
	end
	if comboLabel.Text ~= "" and os.clock() - lastThrow > Config.Toss.ComboTimeout then
		comboLabel.Text = ""
	end

	-- the ring: same clock as the server uses to judge PERFECT
	local t = workspace:GetServerTimeNow()
	local open = Rules.ringOpen(t)
	local perfect = Rules.isPerfect(t)
	local ringColor = perfect and UI.Colors.Gold or Color3.fromRGB(235, 225, 255)
	local ringSize = PAD + 12 + open * 46
	ring.Size = UDim2.fromOffset(ringSize, ringSize)
	ringStroke.Color = ringColor
	ringStroke.Thickness = perfect and 8 or 5
	ringStroke.Transparency = hasFood and 0 or 0.7

	local showBeads = inRange and hasFood and cf ~= nil
	if cf and showBeads then
		local size = Config.Thing.Sizes[state.size or 1]
		local radius = size.hole / 2 + 0.6 + open * 3.5
		for i, bead in ipairs(beads) do
			local angle = i / #beads * math.pi * 2
			bead.CFrame = cf * CFrame.new(math.cos(angle) * radius, 0.7, math.sin(angle) * radius)
			bead.Color = ringColor
			bead.Transparency = 0.1
		end
	else
		for _, bead in ipairs(beads) do
			bead.Transparency = 1
		end
	end
end)
