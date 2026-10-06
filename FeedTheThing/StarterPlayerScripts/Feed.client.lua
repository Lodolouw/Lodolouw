--[[
	Feed  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "Feed")

	The core action. Near your hatch, the food bar shows at the bottom of
	the screen: your six foods with their prices (Tomato is free) and a big
	FEED button. Pick a food, tap FEED (or hold it), the food flies into the
	hatch and the Thing burps out an egg onto one of your nests.
	PC: click, or press E to feed; 1-6 pick a food.

	Above the bar: the chance of each rarity with the food you picked (better
	food, better chances). Over the hatch: your nests and how close the
	Thing is to its next size.
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
local FeedRemote = remoteFolder:WaitForChild("Feed") :: RemoteEvent
local FeedResultRemote = remoteFolder:WaitForChild("FeedResult") :: RemoteEvent
local StateRemote = remoteFolder:WaitForChild("State") :: RemoteEvent
local plotsFolder = ReplicatedStorage:WaitForChild("Plots")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local W = Config.World
local C = UI.Colors

local state = nil
local selected = Config.Crops[1].id
local lastThrow = 0
local inRange = false
-- Feeds the latest State doesn't include yet, so the coins and nests count
-- them the moment you feed: { food, price, result }. One leaves this list
-- when it's rejected, or when a State arrives after its (accepted) result.
local unconfirmed = {}
local awaitingResult = {} -- the same entries, oldest first, until their FeedResult arrives

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

-- coins and eggs, counting the feeds still on their way to the server
local function coinsLeft()
	local coins = state and state.coins or 0
	for _, entry in ipairs(unconfirmed) do
		coins -= entry.price
	end
	return coins
end

local function eggsNow()
	return (state and state.eggs or 0) + #unconfirmed
end

local function nestsNow()
	return state and state.nests or Config.Eggs.StartNests
end

local function hex(color)
	return string.format("#%02X%02X%02X", math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255))
end

-- 0.927 -> "93%", 0.012 -> "1.2%", 0.0002 -> "0.02%"
local function percent(x)
	local p = x * 100
	if p >= 10 then
		return string.format("%d%%", math.floor(p + 0.5))
	elseif p >= 1 then
		return (string.gsub(string.format("%.1f%%", p), "%.0%%", "%%"))
	elseif p >= 0.1 then
		return string.format("%.1f%%", p)
	end
	return string.format("%.2f%%", p)
end

----------------------------------------------------------------------
-- Screen GUI: the food bar, the FEED button, the odds, messages
----------------------------------------------------------------------
local gui = UI.new("ScreenGui", {
	Name = "FeedGui", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 5, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local SLOT_W, SLOT_H, SLOT_GAP = 72, 84, 8
local PAD = 104
local STACK_W = #Config.Crops * (SLOT_W + SLOT_GAP) + 10 + PAD
local STACK_H = 168
-- everything sits in one stack at the bottom that shrinks on small
-- screens (a phone in landscape is ~330 tall)
local stack = UI.new("Frame", {
	Name = "Stack",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -8),
	Size = UDim2.fromOffset(STACK_W, STACK_H),
	BackgroundTransparency = 1,
	Visible = false,
}, gui)
local stackScale = UI.new("UIScale", { Scale = 1 }, stack)
local function fitStack()
	local camera = workspace.CurrentCamera
	local size = camera and camera.ViewportSize or Vector2.new(1280, 720)
	stackScale.Scale = math.clamp(math.min(size.Y * 0.42 / STACK_H, (size.X - 24) / STACK_W), 0.55, 1)
end
fitStack()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitStack)
end

-- the odds with the food you picked, and how long its egg takes
local oddsBox = UI.new("Frame", {
	Name = "Odds", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -PAD - 8),
	Size = UDim2.new(1, -PAD - 10, 0, 50), BackgroundColor3 = C.Well, BackgroundTransparency = 0.15,
}, stack)
UI.corner(oddsBox, UDim.new(0, 10))
UI.stroke(oddsBox, 3)
local oddsLabel = UI.label(oddsBox, {
	Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(8, 2), Text = "", RichText = true,
})
local eggLabel = UI.label(oddsBox, {
	Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 28), Text = "", TextColor3 = C.Dim,
})

-- the six foods
local bar = UI.new("Frame", {
	Name = "Foods", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -(PAD - SLOT_H) / 2),
	Size = UDim2.fromOffset(#Config.Crops * (SLOT_W + SLOT_GAP), SLOT_H), BackgroundTransparency = 1,
}, stack)
UI.new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, SLOT_GAP), SortOrder = Enum.SortOrder.LayoutOrder,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
}, bar)

-- the FEED button
local pad = UI.new("TextButton", {
	Name = "Feed",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, 0, 1, 0),
	Size = UDim2.fromOffset(PAD, PAD),
	BackgroundColor3 = C.Good,
	Text = "",
	AutoButtonColor = false,
}, stack)
UI.chunky(pad, nil, UDim.new(1, 0), 5)
local padScale = UI.new("UIScale", { Scale = 1 }, pad)
local padIcon = UI.viewport(pad, nil, { Size = UDim2.fromScale(0.5, 0.5), Position = UDim2.fromScale(0.25, 0.08), ZIndex = 2 })
UI.label(pad, { Size = UDim2.new(1, -8, 0, 30), Position = UDim2.new(0, 4, 0.52, 0), Text = "FEED", ZIndex = 3 })
local padHint = UI.label(pad, {
	AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(220, 28), Position = UDim2.new(0.5, 0, 0, -6), Text = "Tap to feed it!",
	TextColor3 = C.Gold, ZIndex = 3, Visible = false,
})

local messageLabel = UI.label(gui, {
	Name = "Message",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(480, 34),
	Text = "",
	TextTransparency = 1,
})

local messageToken, lastMessage, lastMessageAt = 0, "", 0
local function showMessage(text, color)
	-- the same message again, straight away (holding FEED): don't flicker
	if text == lastMessage and os.clock() - lastMessageAt < 1.5 then
		return
	end
	lastMessage, lastMessageAt = text, os.clock()
	messageToken += 1
	local token = messageToken
	messageLabel.Text = text
	messageLabel.TextColor3 = color or C.Text
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
UI.on("FeedMessage", showMessage)

----------------------------------------------------------------------
-- The food bar
----------------------------------------------------------------------
local slots = {} -- [crop id] = { button, stroke, price, coin, fill, ... }

local function refreshOdds()
	local crop = Rules.crop(selected)
	if not crop then
		return
	end
	local odds = Rules.hatchOdds(selected, state and state.luck or 0)
	local parts = {}
	for _, rarity in ipairs(Config.RarityOrder) do
		table.insert(parts, string.format('<font color="%s">%s %s</font>', hex(Config.Rarities[rarity].color), rarity, percent(odds[rarity])))
	end
	oddsLabel.Text = table.concat(parts, "  ")
	local speed = state and Rules.upgradeEffect(state, "speed") or 1
	local luck = state and state.luck or 0
	local seconds = Rules.eggSeconds(selected, speed, false)
	local text = crop.name .. ": its egg hatches in " .. (seconds == math.floor(seconds) and tostring(seconds) or string.format("%.1f", seconds)) .. "s"
	if luck > 0 then
		text ..= "   |   Luck +" .. math.floor(luck * 100 + 0.5) .. "%"
	end
	eggLabel.Text = text
end

local padFood = nil
local function selectFood(cropId)
	selected = cropId
	for id, slot in pairs(slots) do
		local on = id == selected
		slot.stroke.Color = on and Color3.fromRGB(255, 255, 255) or C.Stroke
		slot.stroke.Thickness = on and 5 or 3
		slot.button.Size = on and UDim2.fromOffset(SLOT_W, SLOT_H) or UDim2.fromOffset(SLOT_W, SLOT_H - 8)
	end
	if padFood ~= cropId then
		padFood = cropId
		UI.setViewportModel(padIcon, Looks.fruit(cropId, "", false), 200)
	end
	refreshOdds()
end

local function refreshBar()
	local coins = coinsLeft()
	for _, crop in ipairs(Config.Crops) do
		local slot = slots[crop.id]
		local affordable = coins >= crop.price
		slot.price.TextColor3 = affordable and C.Text or Color3.fromRGB(255, 120, 110)
		slot.button.BackgroundColor3 = affordable and C.PanelLight or C.Well
		-- saving up: how close you are
		slot.fillBack.Visible = not affordable
		slot.fill.Size = UDim2.fromScale(math.clamp(coins / math.max(1, crop.price), 0, 1), 1)
	end
	local crop = Rules.crop(selected)
	local price = crop and crop.price or 0
	pad.BackgroundColor3 = (coins >= price and eggsNow() < nestsNow()) and C.Good or C.Grey
end

for i, crop in ipairs(Config.Crops) do
	local button = UI.new("TextButton", {
		Name = crop.id,
		LayoutOrder = i,
		Size = UDim2.fromOffset(SLOT_W, SLOT_H - 8),
		BackgroundColor3 = C.PanelLight,
		Text = "",
		AutoButtonColor = false,
	}, bar)
	UI.corner(button, UDim.new(0, 10))
	local stroke = UI.stroke(button, 3)
	UI.label(button, {
		Size = UDim2.fromOffset(18, 16), Position = UDim2.fromOffset(5, 3), Text = tostring(i),
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Dim, ZIndex = 3,
	})
	UI.viewport(button, Looks.fruit(crop.id, "", false), {
		AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(50, 44), Position = UDim2.new(0.5, 0, 0, 4), ZIndex = 2,
	})
	local coin = UI.icon(button, "coin", {
		Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 4, 1, -7), Visible = crop.price > 0,
	})
	local price = UI.number(button, {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, crop.price > 0 and 21 or 2, 1, -3),
		Size = UDim2.new(1, crop.price > 0 and -23 or -4, 0, 24), Text = crop.price > 0 and Rules.short(crop.price) or "FREE", ZIndex = 3,
	})
	local fillBack = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2), Size = UDim2.new(1, -12, 0, 4),
		BackgroundColor3 = Color3.fromRGB(40, 25, 20), BorderSizePixel = 0, ZIndex = 3, Visible = false,
	}, button)
	UI.corner(fillBack, UDim.new(1, 0))
	local fill = UI.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Gold, BorderSizePixel = 0, ZIndex = 4 }, fillBack)
	UI.corner(fill, UDim.new(1, 0))
	button.Activated:Connect(function()
		UI.sound("Click", 0.4)
		selectFood(crop.id)
		refreshBar()
		UI.pop(button, 0.15)
	end)
	slots[crop.id] = { button = button, stroke = stroke, price = price, coin = coin, fill = fill, fillBack = fillBack }
end

----------------------------------------------------------------------
-- Over the hatch: your nests and the Thing's size
----------------------------------------------------------------------
local hatchAnchor = Instance.new("Part")
hatchAnchor.Name = "HatchAnchor"
hatchAnchor.Anchored = true
hatchAnchor.CanCollide = false
hatchAnchor.CanQuery = false
hatchAnchor.Transparency = 1
hatchAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
hatchAnchor.Parent = workspace

local hatchGui = UI.new("BillboardGui", {
	Name = "HatchInfo",
	Adornee = hatchAnchor,
	Size = UDim2.fromScale(16, 5.5),
	LightInfluence = 0,
	AlwaysOnTop = true,
	MaxDistance = 90,
	Enabled = false,
	ResetOnSpawn = false,
}, playerGui)
local nestsLabel = UI.label(hatchGui, { Size = UDim2.fromScale(1, 0.45), Text = "Feed me!", TextColor3 = Config.Thing.EyeColor })
-- how close the Thing is to its next size (it grows by eating)
local sizeBack = UI.new("Frame", {
	Size = UDim2.fromScale(0.84, 0.36), Position = UDim2.fromScale(0.08, 0.56), BackgroundColor3 = Color3.fromRGB(25, 15, 40),
}, hatchGui)
UI.corner(sizeBack, UDim.new(1, 0))
UI.stroke(sizeBack, 2.5)
local sizeFill = UI.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Config.Thing.EyeColor, BackgroundTransparency = 0.25 }, sizeBack)
UI.corner(sizeFill, UDim.new(1, 0))
local sizeText = UI.label(sizeBack, { Size = UDim2.fromScale(0.96, 0.9), Position = UDim2.fromScale(0.02, 0.05), Text = "", ZIndex = 2 })

local function refreshHatchInfo()
	if not state then
		return
	end
	local sizes = Config.Thing.Sizes
	local size = sizes[state.size or 1] or sizes[1]
	local nextSize = sizes[(state.size or 1) + 1]
	if nextSize then
		local k = math.clamp((state.growth - size.growth) / (nextSize.growth - size.growth), 0, 1)
		sizeFill.Size = UDim2.fromScale(k, 1)
		sizeText.Text = size.name .. "  >  " .. nextSize.name .. "  " .. math.floor(k * 100) .. "%"
	else
		sizeFill.Size = UDim2.fromScale(1, 1)
		sizeText.Text = size.name .. ": fully grown!"
	end
	local used, total = eggsNow(), nestsNow()
	if (state.stats and state.stats.feeds or 0) == 0 and used == 0 then
		nestsLabel.Text = "Feed me!"
		nestsLabel.TextColor3 = Config.Thing.EyeColor
	else
		nestsLabel.Text = string.format("Nests: %d / %d", math.min(used, total), total)
		nestsLabel.TextColor3 = used >= total and C.Gold or C.Text
	end
end

----------------------------------------------------------------------
-- Feeding
----------------------------------------------------------------------
local function showResult(result)
	local cf = hatchCF()
	if not cf then
		return
	end
	if not result.ok then
		if result.reason and result.reason ~= "" then
			showMessage(result.reason, C.Bad)
			UI.sound("Error", 0.6)
		end
		return
	end
	local words = { "CHOMP!", "YUM!", "GULP!", "NOM!", "CRUNCH!" }
	UI.fire("FloatingText", cf.Position + Vector3.new(math.random(-3, 3), 6, 0), words[math.random(1, #words)], Color3.fromRGB(255, 255, 255), 30, 5)
end

local function feed()
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
	local crop = Rules.crop(selected)
	if not crop then
		return
	end
	if eggsNow() >= nestsNow() then
		showMessage("Your nests are full! Wait for an egg to hatch.", C.Gold)
		UI.pop(nestsLabel, 0.3)
		return
	end
	if coinsLeft() < crop.price then
		showMessage("Not enough coins for a " .. crop.name .. "!", C.Bad)
		UI.sound("Error", 0.5)
		return
	end
	lastThrow = os.clock()
	local entry = { food = crop.id, price = crop.price, landed = false, result = nil }
	table.insert(unconfirmed, entry)
	table.insert(awaitingResult, entry)
	FeedRemote:FireServer(crop.id)
	UI.sound("Throw", 0.6)
	padScale.Scale = 0.85
	tween(padScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	refreshBar()
	refreshHatchInfo()

	-- the food flies in an arc into the hatch, with a streak behind it
	local fruit = Looks.fruit(crop.id, "", true)
	fruit:ScaleTo(1.4)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.9, 0)
	a0.Parent = fruit.PrimaryPart
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 0.2, 0)
	a1.Parent = fruit.PrimaryPart
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.25
	trail.Color = ColorSequence.new(crop.color)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.LightEmission = 0.5
	trail.FaceCamera = true
	trail.Parent = fruit.PrimaryPart
	local from = root.Position + root.CFrame.RightVector * 1.2 + Vector3.new(0, 1.5, 0)
	local to = cf.Position + Vector3.new(0, -1, 0)
	local height = 5 + (from - to).Magnitude * 0.12
	fruit:PivotTo(CFrame.new(from))
	fruit.Parent = workspace
	local flight = Config.Feed.FlightTime
	if math.random() < 0.35 then
		UI.fire("ArmCatch", flight - 0.12) -- now and then an arm shoots up to catch it
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
		UI.fire("Chomp")
		UI.sound("Chomp", 0.8, 0.95 + math.random() * 0.1)
		entry.landed = true
		if entry.result then
			showResult(entry.result)
		end
	end)
end

FeedResultRemote.OnClientEvent:Connect(function(result)
	if type(result) ~= "table" then
		return
	end
	-- match it to the oldest feed still waiting for its answer
	local entry = table.remove(awaitingResult, 1)
	if not entry then
		return
	end
	entry.result = result
	if not result.ok then
		-- turned down: nothing was spent
		local i = table.find(unconfirmed, entry)
		if i then
			table.remove(unconfirmed, i)
		end
		refreshBar()
		refreshHatchInfo()
	end
	if entry.landed or not result.ok then
		showResult(result)
	end
end)

-- Tap the FEED button, or hold it to keep feeding
local holding = nil
pad.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		holding = input
		tween(padScale, 0.08, { Scale = 0.92 })
		feed()
		task.spawn(function()
			task.wait(0.4)
			while holding == input do
				feed()
				task.wait(0.3)
			end
		end)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if not holding then
		return
	end
	local same = input == holding
		or (holding.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1)
	if same then
		holding = nil
		tween(padScale, 0.12, { Scale = 1 }, Enum.EasingStyle.Back)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonR2 then
		feed()
		return
	end
	local numbers = {
		[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
		[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
	}
	-- the number keys match the numbers on the food bar
	local crop = Config.Crops[numbers[input.KeyCode] or 0]
	if crop then
		selectFood(crop.id)
		refreshBar()
	end
end)

----------------------------------------------------------------------
-- State from the server
----------------------------------------------------------------------
StateRemote.OnClientEvent:Connect(function(newState)
	if type(newState) ~= "table" then
		return
	end
	state = newState
	UI.state = newState
	-- feeds already answered are counted in this State now
	for i = #unconfirmed, 1, -1 do
		if unconfirmed[i].result then
			table.remove(unconfirmed, i)
		end
	end
	refreshBar()
	refreshOdds()
	refreshHatchInfo()
	padHint.Visible = (state.stats and state.stats.feeds or 0) == 0
end)
selectFood(selected)

----------------------------------------------------------------------
-- Every frame: are you close enough to feed?
----------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	local cf = hatchCF()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local close = false
	if cf and root and root:IsA("BasePart") then
		local d = Vector2.new(root.Position.X - cf.Position.X, root.Position.Z - cf.Position.Z).Magnitude
		close = d <= Config.Feed.Range
	end
	inRange = close and state ~= nil
	stack.Visible = inRange
	hatchGui.Enabled = cf ~= nil and state ~= nil
	if cf then
		local size = Config.Thing.Sizes[state and state.size or 1]
		hatchAnchor.CFrame = cf * CFrame.new(0, 7 + size.hole * 0.35, 0)
	end
end)
