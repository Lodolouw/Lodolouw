--[[
	Hud  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "Hud")

	Everything on screen except the throw pad:
	  * coins (top centre) with coins per second, and the weather
	  * three big buttons on the left: Shop, Dex, Upgrades
	  * the panels they open
	  * the hatch reveal, "Welcome back", "Your yard is full", a Thinglet's
	    card, the size-up banner, server announcements, and first-time hints

	Built for phones first: big buttons, few of them, nothing in the corners
	Roblox uses (top bar, thumbstick, jump button).
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Rules = require(ReplicatedStorage:WaitForChild("Rules"))
local Looks = require(ReplicatedStorage:WaitForChild("Looks"))
local UI = require(ReplicatedStorage:WaitForChild("UI"))

local remoteFolder = ReplicatedStorage:WaitForChild("Remotes")
local StateRemote = remoteFolder:WaitForChild("State") :: RemoteEvent
local NotifyRemote = remoteFolder:WaitForChild("Notify") :: RemoteEvent
local HatchedRemote = remoteFolder:WaitForChild("Hatched") :: RemoteEvent
local ActionRemote = remoteFolder:WaitForChild("Action") :: RemoteFunction

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local C = UI.Colors

local state = nil
local displayCoins = 0

local function tween(instance, seconds, goal, style, direction)
	local t = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function serverNow()
	return workspace:GetServerTimeNow()
end

local function act(name, a, b)
	local ok, result = pcall(function()
		return ActionRemote:InvokeServer(name, a, b)
	end)
	if not ok or type(result) ~= "table" then
		return { ok = false, msg = "Couldn't reach the server. Try again!" }
	end
	return result
end

local function rarityColor(kind)
	local def = Config.Thinglets[kind]
	return def and Config.Rarities[def.rarity].color or C.Text
end

local function thingletName(kind, mut)
	local def = Config.Thinglets[kind]
	local name = def and def.name or "?"
	if mut and mut ~= "" then
		return mut .. " " .. name
	end
	return name
end

----------------------------------------------------------------------
-- Screen
----------------------------------------------------------------------
local gui = UI.new("ScreenGui", {
	Name = "Hud", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 10, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)
local overlayGui = UI.new("ScreenGui", {
	Name = "HudOverlay", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 20, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

-- a drawn gold coin
local function coinIcon(parent, size, position)
	return UI.icon(parent, "coin", { Size = UDim2.fromOffset(size, size), Position = position or UDim2.new() })
end

local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Money, bottom left (big italic numbers, like the genre's hits)
local moneyBox = UI.new("Frame", {
	Name = "Money", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -12),
	Size = UDim2.fromOffset(300, 92), BackgroundTransparency = 1,
}, gui)
local coinsBox = moneyBox
coinIcon(moneyBox, 54, UDim2.fromOffset(0, 36))
local coinsLabel = UI.number(moneyBox, {
	Size = UDim2.fromOffset(240, 56), Position = UDim2.fromOffset(62, 36), Text = "0",
	TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Colors.Gold,
})
local incomeLabel = UI.number(moneyBox, {
	Size = UDim2.fromOffset(240, 30), Position = UDim2.fromOffset(62, 4), Text = "+0/s",
	TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 255, 255),
})
local coinsLimit = coinsLabel:FindFirstChildOfClass("UITextSizeConstraint")
if coinsLimit then
	coinsLimit.MaxTextSize = 52
end

-- The weather timer, bottom right (above the jump button on phones)
local weatherBox = UI.new("Frame", {
	Name = "Weather", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, touchOnly and -170 or -14),
	Size = UDim2.fromOffset(330, 54), BackgroundTransparency = 1,
}, gui)
local weatherIconHolder = UI.new("Frame", {
	AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -262, 0.5, 0), Size = UDim2.fromOffset(50, 50), BackgroundTransparency = 1,
}, weatherBox)
local weatherIconKind = nil
local weatherChip = UI.number(weatherBox, {
	AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(256, 44),
	Text = "", TextXAlignment = Enum.TextXAlignment.Right,
})
local function setWeatherIcon(kind)
	if kind == weatherIconKind then
		return
	end
	weatherIconKind = kind
	weatherIconHolder:ClearAllChildren()
	UI.icon(weatherIconHolder, kind)
end

-- The title banner across the top; announcements and weather show in it too
local banner = UI.new("Frame", {
	Name = "Banner", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4),
	Size = UDim2.new(0.6, 0, 0, 58), BackgroundColor3 = Color3.fromRGB(10, 20, 45), BackgroundTransparency = 0.45,
}, gui)
UI.new("UISizeConstraint", { MaxSize = Vector2.new(820, 58) }, banner)
UI.new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0),
		NumberSequenceKeypoint.new(0.8, 0), NumberSequenceKeypoint.new(1, 1),
	}),
}, banner)
local bannerLabel = UI.number(banner, { Size = UDim2.new(1, -40, 1, -6), Position = UDim2.fromOffset(20, 3), Text = "Feed the Thing!" })
local bannerToken = 0
local function showBanner(text, color, seconds)
	bannerToken += 1
	local token = bannerToken
	bannerLabel.Text = text
	bannerLabel.TextColor3 = color or UI.Colors.Text
	UI.pop(bannerLabel, 0.15)
	task.delay(seconds or 5, function()
		if token == bannerToken then
			bannerLabel.Text = "Feed the Thing!"
			bannerLabel.TextColor3 = UI.Colors.Text
		end
	end)
end

-- Toasts (small messages), under the banner
local toastList = UI.new("Frame", {
	Name = "Toasts", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 68),
	Size = UDim2.fromOffset(520, 140), BackgroundTransparency = 1,
}, gui)
UI.new("UIListLayout", {
	HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
}, toastList)
local toastOrder = 0
local function toast(text, color, seconds)
	toastOrder += 1
	local box = UI.new("Frame", {
		LayoutOrder = toastOrder, Size = UDim2.fromOffset(500, 38), BackgroundColor3 = Color3.fromRGB(10, 20, 45), BackgroundTransparency = 0.35,
	}, toastList)
	UI.corner(box, UDim.new(0, 12))
	local label = UI.label(box, { Size = UDim2.new(1, -16, 1, -6), Position = UDim2.fromOffset(8, 3), Text = text, TextColor3 = color or C.Text })
	UI.pop(box, 0.12)
	local children = toastList:GetChildren()
	local boxes = {}
	for _, child in ipairs(children) do
		if child:IsA("Frame") then
			table.insert(boxes, child)
		end
	end
	if #boxes > 3 then
		boxes[1]:Destroy()
	end
	task.delay(seconds or 4, function()
		if box.Parent then
			tween(box, 0.3, { BackgroundTransparency = 1 })
			tween(label, 0.3, { TextTransparency = 1 })
			task.wait(0.3)
			box:Destroy()
		end
	end)
end
UI.on("Toast", toast)

----------------------------------------------------------------------
-- Side buttons: Shop and Index on the left, Daily and Upgrades on the right
----------------------------------------------------------------------
local function sideColumn(name, anchorX, positionX, width)
	local column = UI.new("Frame", {
		Name = name, AnchorPoint = Vector2.new(anchorX, 0.5), Position = UDim2.new(positionX, anchorX == 0 and 14 or -14, 0.47, 0),
		Size = UDim2.fromOffset(width, 2 * 86), BackgroundTransparency = 1,
	}, gui)
	UI.new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = anchorX == 0 and Enum.HorizontalAlignment.Left or Enum.HorizontalAlignment.Right }, column)
	-- shrink on short screens so they stay clear of the thumbstick and jump button
	local scale = UI.new("UIScale", { Scale = 1 }, column)
	local function fit()
		local camera = workspace.CurrentCamera
		local height = camera and camera.ViewportSize.Y or 720
		scale.Scale = math.clamp(height * 0.5 / (2 * 86), 0.6, 1)
	end
	fit()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
	return column
end
local leftBar = sideColumn("LeftButtons", 0, 0, 200)
local rightBar = sideColumn("RightButtons", 1, 1, 80)

local sideButtons = {}
-- wide = a long button with an icon and a word (left); else a square icon button (right)
local function sideButton(name, label, order, icon, color, wide, onClick)
	local parent = wide and leftBar or rightBar
	local button = UI.button(parent, "", {
		Name = name, LayoutOrder = order, Size = wide and UDim2.fromOffset(196, 74) or UDim2.fromOffset(76, 76), BackgroundColor3 = color,
	}, onClick)
	if wide then
		UI.icon(button, icon, { Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(6, 1) })
		local text = UI.label(button, {
			Size = UDim2.new(1, -74, 0, 46), Position = UDim2.fromOffset(66, 8), Text = label, TextXAlignment = Enum.TextXAlignment.Left,
		})
		local limit = text:FindFirstChildOfClass("UITextSizeConstraint")
		if limit then
			limit.MaxTextSize = 40
		end
		local stroke = text:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Thickness = 3
		end
	else
		UI.icon(button, icon, { Size = UDim2.fromScale(0.86, 0.86), Position = UDim2.fromScale(0.07, 0.04) })
	end
	local dot = UI.badge(button)
	local hint = UI.label(button, {
		Size = UDim2.fromOffset(220, 30), AnchorPoint = Vector2.new(wide and 0 or 1, 0.5),
		Position = wide and UDim2.new(1, 14, 0.5, 0) or UDim2.new(0, -14, 0.5, 0), Text = "",
		TextXAlignment = wide and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right, TextColor3 = C.Gold, Visible = false,
	})
	sideButtons[name] = { button = button, dot = dot, hint = hint }
	return button
end

----------------------------------------------------------------------
-- Panels (one open at a time)
----------------------------------------------------------------------
local openPanel = nil
local panels = {}

local function makePanel(name, title, width, height, headerColor)
	local frame = UI.new("Frame", {
		Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(width, height), BackgroundColor3 = C.Panel, Visible = false, ZIndex = 20,
		Active = true, -- taps on the panel don't fall through to the throw pad
	}, gui)
	UI.chunky(frame, C.Panel, UDim.new(0, 18), 4)
	UI.fit(frame, width, height)
	local header = UI.new("Frame", {
		Name = "Header", Size = UDim2.new(1, 0, 0, 70), BackgroundColor3 = headerColor or C.Green, ZIndex = 21,
	}, frame)
	UI.chunky(header, nil, UDim.new(0, 18), 4)
	local titleLabel = UI.label(header, { Size = UDim2.new(1, -120, 0, 44), Position = UDim2.fromOffset(18, 4), Text = title, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22 })
	local titleStroke = titleLabel:FindFirstChildOfClass("UIStroke")
	if titleStroke then
		titleStroke.Thickness = 3
	end
	local subtitle = UI.label(header, { Size = UDim2.new(1, -120, 0, 20), Position = UDim2.fromOffset(18, 46), Text = "", TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22 })
	local close = UI.button(frame, "", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(54, 54), BackgroundColor3 = C.Red, ZIndex = 24,
	}, function()
		frame.Visible = false
		openPanel = nil
	end)
	close.Text = "X"
	local body = UI.new("ScrollingFrame", {
		Name = "Body", Position = UDim2.fromOffset(12, 80), Size = UDim2.new(1, -24, 1, -92),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 21,
	}, frame)
	panels[name] = { frame = frame, title = titleLabel, subtitle = subtitle, body = body, close = close }
	return panels[name]
end

local function showPanel(name)
	for other, panel in pairs(panels) do
		if other ~= name then
			panel.frame.Visible = false
		end
	end
	local panel = panels[name]
	if openPanel == name then
		panel.frame.Visible = false
		openPanel = nil
		return
	end
	openPanel = name
	panel.frame.Visible = true
	UI.pop(panel.frame, 0.08)
	UI.fire("PanelOpened", name)
end

----------------------------------------------------------------------
-- Generic "are you sure?" dialog
----------------------------------------------------------------------
local function confirm(text, yesText, onYes)
	local back = UI.new("TextButton", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Text = "", AutoButtonColor = false, ZIndex = 60,
	}, overlayGui)
	local box = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(400, 200), BackgroundColor3 = C.Panel, ZIndex = 61, Active = true,
	}, back)
	UI.fit(box, 400, 200)
	UI.chunky(box, C.Panel, UDim.new(0, 18), 4)
	UI.label(box, { Size = UDim2.new(1, -30, 0, 90), Position = UDim2.fromOffset(15, 15), Text = text, ZIndex = 62 })
	UI.button(box, yesText, { Position = UDim2.new(0.5, 8, 1, -72), Size = UDim2.fromOffset(170, 56), BackgroundColor3 = C.Bad, ZIndex = 62 }, function()
		back:Destroy()
		onYes()
	end)
	UI.button(box, "Keep it", { Position = UDim2.new(0.5, -178, 1, -72), Size = UDim2.fromOffset(170, 56), BackgroundColor3 = C.Grey, ZIndex = 62 }, function()
		back:Destroy()
	end)
end

----------------------------------------------------------------------
-- Shop
----------------------------------------------------------------------
local shop = makePanel("Shop", "Seed Shop", 560, 470, C.Green)
local shopRows = {}

local function buySeed(cropId, replace)
	local result = act("buySeed", cropId, replace)
	if result.needReplace then
		confirm(result.msg, "Replace", function()
			buySeed(cropId, true)
		end)
		return
	end
	if result.ok then
		UI.sound("Buy")
		toast(result.msg, C.Good, 2.5)
	else
		UI.sound("Error", 0.6)
		toast(result.msg, C.Bad, 2.5)
	end
end

for i, crop in ipairs(Config.Crops) do
	local row = UI.new("Frame", {
		Name = crop.id, Size = UDim2.new(1, -8, 0, 86), Position = UDim2.fromOffset(0, (i - 1) * 94),
		BackgroundColor3 = C.PanelLight, ZIndex = 22,
	}, shop.body)
	UI.corner(row, UDim.new(0, 14))
	local stroke = UI.stroke(row, 3)
	UI.viewport(row, Looks.fruit(crop.id, "", false), { Size = UDim2.fromOffset(72, 72), Position = UDim2.fromOffset(8, 7), ZIndex = 23 })
	UI.label(row, {
		Size = UDim2.new(1, -270, 0, 32), Position = UDim2.fromOffset(88, 6), Text = crop.name,
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Config.Rarities[crop.rarity].color, ZIndex = 23,
	})
	local def = Config.Thinglets[crop.thinglet]
	local info = UI.label(row, {
		Size = UDim2.new(1, -270, 0, 20), Position = UDim2.fromOffset(88, 38),
		Text = string.format("%s coins a toss  |  regrows in %ds", Rules.short(crop.coins), crop.regrow),
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Dim, ZIndex = 23,
	})
	local stockLabel = UI.label(row, {
		Size = UDim2.new(1, -270, 0, 20), Position = UDim2.fromOffset(88, 60), Text = "",
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Dim, ZIndex = 23,
	})
	local buy = UI.button(row, Rules.short(crop.seed), {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(150, 60), ZIndex = 23,
	}, function()
		buySeed(crop.id, false)
	end)
	coinIcon(buy, 22, UDim2.fromOffset(8, 19)).ZIndex = 24
	shopRows[crop.id] = { row = row, stroke = stroke, stock = stockLabel, buy = buy, info = info, def = def }
end

local function refreshShop()
	if not state then
		return
	end
	shop.subtitle.Text = "New stock in " .. Rules.clock((state.restockAt or 0) - serverNow())
	for _, crop in ipairs(Config.Crops) do
		local r = shopRows[crop.id]
		local left = state.stock and state.stock[crop.id] or 0
		if left < 0 then
			r.stock.Text = "Always in stock"
		elseif left == 0 then
			r.stock.Text = string.format("Sold out  (in stock %d%% of restocks)", math.floor(crop.stockChance * 100))
		else
			r.stock.Text = string.format("%d in stock!  (in stock %d%% of restocks)", left, math.floor(crop.stockChance * 100))
		end
		if crop.id == Config.SecretFood then
			r.stock.Text ..= "  Always on the hour"
		end
		local canBuy = left ~= 0 and state.coins >= crop.seed
		r.buy.BackgroundColor3 = canBuy and C.Good or C.Grey
	end
end

----------------------------------------------------------------------
-- Upgrades
----------------------------------------------------------------------
local upgrades = makePanel("Upgrades", "Upgrades", 520, 420, C.Orange)
local function upgradeRow(order, title, onBuy)
	local row = UI.new("Frame", {
		Size = UDim2.new(1, -8, 0, 92), Position = UDim2.fromOffset(0, (order - 1) * 100), BackgroundColor3 = C.PanelLight, ZIndex = 22,
	}, upgrades.body)
	UI.corner(row, UDim.new(0, 14))
	UI.stroke(row, 3)
	local titleLabel = UI.label(row, { Size = UDim2.new(1, -190, 0, 34), Position = UDim2.fromOffset(14, 8), Text = title, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23 })
	local sub = UI.label(row, { Size = UDim2.new(1, -190, 0, 22), Position = UDim2.fromOffset(14, 46), Text = "", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Dim, ZIndex = 23 })
	local button
	if onBuy then
		button = UI.button(row, "", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(160, 60), ZIndex = 23 }, onBuy)
	end
	return { row = row, title = titleLabel, sub = sub, button = button }
end

local function upgradeAction(name)
	local result = act(name)
	if result.ok then
		UI.sound("Buy")
		toast(result.msg, C.Good, 2.5)
	else
		UI.sound("Error", 0.6)
		toast(result.msg, C.Bad, 2.5)
	end
end
local plotRow = upgradeRow(1, "Garden plots", function()
	upgradeAction("buyPlot")
end)
local yardRow = upgradeRow(2, "Yard space", function()
	upgradeAction("buyYard")
end)
local thingRow = upgradeRow(3, "Your Thing", nil)
local thingBarBack = UI.new("Frame", {
	Size = UDim2.new(1, -28, 0, 12), Position = UDim2.new(0, 14, 1, -20), BackgroundColor3 = Color3.fromRGB(25, 15, 40), ZIndex = 23,
}, thingRow.row)
UI.corner(thingBarBack, UDim.new(1, 0))
local thingBar = UI.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Config.Thing.EyeColor, ZIndex = 24 }, thingBarBack)
UI.corner(thingBar, UDim.new(1, 0))
local friendRow = upgradeRow(4, "Friend bonus", nil)

local function refreshUpgrades()
	if not state then
		return
	end
	plotRow.sub.Text = string.format("%d of %d plots", state.plots, Config.Garden.MaxPlots)
	if state.plots >= Config.Garden.MaxPlots then
		plotRow.button.Text = "MAX"
		plotRow.button.BackgroundColor3 = C.Grey
	else
		local price = Config.Garden.PlotPrices[state.plots + 1]
		plotRow.button.Text = Rules.short(price)
		plotRow.button.BackgroundColor3 = state.coins >= price and C.Good or C.Grey
	end
	yardRow.sub.Text = string.format("%d of %d Thinglets (room for %d)", state.yardCount, Config.Yard.MaxCap, state.yardCap)
	if state.yardCap >= Config.Yard.MaxCap then
		yardRow.button.Text = "MAX"
		yardRow.button.BackgroundColor3 = C.Grey
	else
		local price = Config.Yard.Prices[state.yardCap + 1]
		yardRow.button.Text = Rules.short(price)
		yardRow.button.BackgroundColor3 = state.coins >= price and C.Good or C.Grey
	end
	local sizes = Config.Thing.Sizes
	local size = sizes[state.size]
	thingRow.title.Text = string.format("Your Thing: Size %d, %s", state.size, size.name)
	local nextSize = sizes[state.size + 1]
	if nextSize then
		local k = (state.growth - size.growth) / (nextSize.growth - size.growth)
		thingBar.Size = UDim2.fromScale(math.clamp(k, 0, 1), 1)
		thingRow.sub.Text = "Grows by eating. Next: " .. nextSize.name .. " (" .. math.floor(k * 100) .. "%)"
	else
		thingBar.Size = UDim2.fromScale(1, 1)
		thingRow.sub.Text = "Fully grown!"
	end
	local friends = math.floor((state.friendBonus or 0) * 100 + 0.5)
	friendRow.title.Text = "Friend bonus: +" .. friends .. "%"
	friendRow.sub.Text = "+10% coins for every friend here (up to +30%)"
end

----------------------------------------------------------------------
-- Dex
----------------------------------------------------------------------
local dex = makePanel("Dex", "Thinglet Index", 600, 500, C.Cyan)
UI.new("UIGridLayout", {
	CellSize = UDim2.fromOffset(170, 196), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, dex.body)
local dexCards = {}
for i, kind in ipairs(Config.ThingletOrder) do
	local def = Config.Thinglets[kind]
	local card = UI.new("Frame", { Name = kind, LayoutOrder = i, BackgroundColor3 = C.PanelLight, ZIndex = 22 }, dex.body)
	UI.corner(card, UDim.new(0, 14))
	local stroke = UI.stroke(card, 3, Config.Rarities[def.rarity].color)
	local view = UI.viewport(card, nil, { Size = UDim2.new(1, -16, 0, 96), Position = UDim2.fromOffset(8, 6), ZIndex = 23 })
	local name = UI.label(card, { Size = UDim2.new(1, -10, 0, 26), Position = UDim2.fromOffset(5, 102), Text = "???", ZIndex = 23 })
	local hint = UI.label(card, { Size = UDim2.new(1, -12, 0, 40), Position = UDim2.fromOffset(6, 128), Text = def.hint, TextColor3 = C.Dim, TextWrapped = true, ZIndex = 23 })
	local dots = {}
	for j, look in ipairs({ "Normal", "Frozen", "Glowing", "Gold" }) do
		local color = look == "Normal" and C.Text or (Rules.mutation(look) and Rules.mutation(look).color or C.Text)
		local dot = UI.new("Frame", {
			Size = UDim2.fromOffset(18, 18), Position = UDim2.new(0.5, -48 + (j - 1) * 26, 1, -24), BackgroundColor3 = color, BackgroundTransparency = 0.8, ZIndex = 23,
		}, card)
		UI.corner(dot, UDim.new(1, 0))
		UI.stroke(dot, 2)
		dots[look] = dot
	end
	dexCards[kind] = { card = card, stroke = stroke, view = view, name = name, hint = hint, dots = dots, known = nil }
end

local function refreshDex()
	if not state then
		return
	end
	local found, total = 0, #Config.ThingletOrder * 4
	for _, kind in ipairs(Config.ThingletOrder) do
		local def = Config.Thinglets[kind]
		local entry = state.dex and state.dex[kind]
		local c = dexCards[kind]
		local known = entry ~= nil
		if c.known ~= known then
			c.known = known
			local model = Looks.thinglet(kind, nil, false)
			if not known then
				Looks.silhouette(model)
			end
			UI.setViewportModel(c.view, model, 205)
		end
		c.name.Text = known and def.name or "???"
		c.name.TextColor3 = known and Config.Rarities[def.rarity].color or C.Text
		c.hint.Text = known and (def.rarity .. "  |  " .. Rules.short(def.cps) .. "/s grown") or def.hint
		for look, dot in pairs(c.dots) do
			local has = entry and entry[look] == true
			dot.BackgroundTransparency = has and 0 or 0.8
			if has then
				found += 1
			end
		end
	end
	dex.subtitle.Text = string.format("Discovered %d of %d looks", found, total)
end

----------------------------------------------------------------------
-- Daily: today's craving, its bonus egg, and the other "come back" perks
----------------------------------------------------------------------
local daily = makePanel("Daily", "Daily Craving", 480, 380, C.Red)
local dailyView = UI.viewport(daily.body, nil, { Size = UDim2.fromOffset(120, 120), Position = UDim2.fromOffset(4, 4), ZIndex = 22 })
local dailyTitle = UI.label(daily.body, { Size = UDim2.new(1, -140, 0, 36), Position = UDim2.fromOffset(132, 10), Text = "", TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22 })
local dailyBarBack = UI.new("Frame", { Size = UDim2.new(1, -150, 0, 26), Position = UDim2.fromOffset(134, 54), BackgroundColor3 = Color3.fromRGB(20, 40, 80), ZIndex = 22 }, daily.body)
UI.corner(dailyBarBack, UDim.new(1, 0))
UI.stroke(dailyBarBack, 3)
local dailyBar = UI.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Gold, ZIndex = 23 }, dailyBarBack)
UI.corner(dailyBar, UDim.new(1, 0))
local dailyCount = UI.label(dailyBarBack, { Size = UDim2.fromScale(1, 1), Text = "", ZIndex = 24 })
UI.label(daily.body, { Size = UDim2.new(1, -140, 0, 24), Position = UDim2.fromOffset(132, 88), Text = "Reward: a bonus egg that is always mutated!", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Gold, ZIndex = 22 })
local dailyPerks = UI.label(daily.body, {
	Size = UDim2.new(1, -16, 0, 120), Position = UDim2.fromOffset(8, 140), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22, Text = "",
})
local dailyFood = nil
local function refreshDaily()
	if not state or not state.daily then
		return
	end
	local d = state.daily
	local crop = Rules.crop(d.food)
	if crop and d.food ~= dailyFood then
		dailyFood = d.food
		UI.setViewportModel(dailyView, Looks.fruit(d.food, "", false), 200)
	end
	daily.subtitle.Text = "New craving in " .. Rules.clock((d.resetAt or 0) - serverNow())
	if d.done then
		dailyTitle.Text = "Done for today!"
		dailyBar.Size = UDim2.fromScale(1, 1)
		dailyCount.Text = "Bonus egg hatched"
	else
		dailyTitle.Text = crop and ("Feed it " .. d.need .. " " .. crop.name) or ""
		dailyBar.Size = UDim2.fromScale(math.clamp(d.fed / math.max(1, d.need), 0, 1), 1)
		dailyCount.Text = d.fed .. " / " .. d.need
	end
	local friends = math.floor((state.friendBonus or 0) * 100 + 0.5)
	dailyPerks.Text = "Your Thinglets earn for up to 1 hour while you're away.\n"
		.. "Play with friends: +10% coins each (up to +30%). Now: +" .. friends .. "%"
end

-- the buttons themselves
sideButton("Shop", "Shop", 1, "sprout", C.Green, true, function()
	showPanel("Shop")
	refreshShop()
end)
sideButton("Dex", "Index", 2, "book", C.Cyan, true, function()
	showPanel("Dex")
	refreshDex()
end)
sideButton("Daily", "Daily", 1, "egg", C.Red, false, function()
	showPanel("Daily")
	refreshDaily()
end)
sideButton("Upgrades", "Upgrades", 2, "upgrade", C.Orange, false, function()
	showPanel("Upgrades")
	refreshUpgrades()
end)

----------------------------------------------------------------------
-- Popups: Thinglet card, welcome back, yard full, size up
----------------------------------------------------------------------
local function modal(width, height)
	local back = UI.new("TextButton", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5, Text = "", AutoButtonColor = false, ZIndex = 40,
	}, overlayGui)
	local box = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(width, height), BackgroundColor3 = C.Panel, ZIndex = 41,
		Active = true, -- taps inside the box don't fall through to the backdrop
	}, back)
	UI.chunky(box, C.Panel, UDim.new(0, 18), 4)
	UI.fit(box, width, height)
	return back, box
end

local cardOpen = nil
local function showCard(info)
	if cardOpen then
		cardOpen:Destroy()
	end
	local record = info.record
	local def = Config.Thinglets[record.kind]
	if not def then
		return
	end
	local back, box = modal(380, 400)
	cardOpen = back
	back.Activated:Connect(function()
		back:Destroy()
	end)
	local view = UI.viewport(box, Looks.thinglet(record.kind, record.mut, false), { Size = UDim2.new(1, -40, 0, 150), Position = UDim2.fromOffset(20, 12), ZIndex = 42 })
	view.ZIndex = 42
	UI.label(box, { Size = UDim2.new(1, -30, 0, 38), Position = UDim2.fromOffset(15, 166), Text = thingletName(record.kind, record.mut), TextColor3 = rarityColor(record.kind), ZIndex = 42 })
	local owner = info.mine and "Yours" or (info.ownerName ~= "" and (info.ownerName .. "'s") or "")
	UI.label(box, { Size = UDim2.new(1, -30, 0, 24), Position = UDim2.fromOffset(15, 204), Text = def.rarity .. "  |  " .. owner, TextColor3 = C.Dim, ZIndex = 42 })
	local incomeLine = UI.label(box, { Size = UDim2.new(1, -30, 0, 26), Position = UDim2.fromOffset(15, 232), Text = "", TextColor3 = C.Gold, ZIndex = 42 })
	local growLine = UI.label(box, { Size = UDim2.new(1, -30, 0, 24), Position = UDim2.fromOffset(15, 260), Text = "", TextColor3 = C.Dim, ZIndex = 42 })
	local function refresh()
		local t = serverNow()
		incomeLine.Text = string.format("+%s/s now  (+%s/s grown)", Rules.rate(Rules.income(record, t)), Rules.rate(Rules.fullIncome(record)))
		local progress = Rules.progress(record, t)
		if progress >= 1 then
			growLine.Text = "Fully grown!"
		else
			local left = (record.born or t) + def.grow - t
			growLine.Text = string.format("%d%% grown, full size in %s", math.floor(progress * 100), Rules.clock(left))
		end
	end
	refresh()
	task.spawn(function()
		while back.Parent do
			task.wait(1)
			if back.Parent then
				refresh()
			end
		end
	end)
	if info.mine then
		local price = Rules.sellPrice(record)
		local armed = false
		local sell
		sell = UI.button(box, "Sell for " .. Rules.short(price), {
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(240, 60), BackgroundColor3 = C.Bad, ZIndex = 42,
		}, function()
			if Rules.rarityRank(def.rarity) >= Config.Yard.ConfirmRank and not armed then
				armed = true
				sell.Text = "Tap again to sell"
				return
			end
			local result = act("sell", info.id)
			back:Destroy()
			if result.ok then
				UI.sound("Coin")
				toast(result.msg, C.Gold, 2.5)
			else
				toast(result.msg, C.Bad, 2.5)
			end
		end)
	end
end
UI.on("ThingletTapped", showCard)

local function showWelcome(coins, away)
	local back, box = modal(420, 280)
	UI.label(box, { Size = UDim2.new(1, -30, 0, 44), Position = UDim2.fromOffset(15, 16), Text = "Welcome back!", TextColor3 = Config.Thing.EyeColor, ZIndex = 42 })
	UI.label(box, { Size = UDim2.new(1, -30, 0, 28), Position = UDim2.fromOffset(15, 66), Text = "While you were away, your Thinglets earned", TextColor3 = C.Dim, ZIndex = 42 })
	coinIcon(box, 40, UDim2.new(0.5, -110, 0, 108)).ZIndex = 42
	UI.label(box, { Size = UDim2.fromOffset(200, 50), Position = UDim2.new(0.5, -60, 0, 103), Text = "+" .. Rules.short(coins), TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 42 })
	if away > Config.Offline.MaxSeconds then
		UI.label(box, { Size = UDim2.new(1, -30, 0, 20), Position = UDim2.fromOffset(15, 158), Text = "(they earn for up to 1 hour while you're away)", TextColor3 = C.Dim, ZIndex = 42 })
	end
	UI.button(box, "Collect", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(220, 62), ZIndex = 42 }, function()
		back:Destroy()
		UI.sound("Coin")
		UI.pop(coinsBox, 0.25)
	end)
end

local yardFullInfo = nil
local yardFullOpen = nil
local revealing = false
local function showYardFull()
	local info = yardFullInfo
	if not info or yardFullOpen or revealing then
		return
	end
	local back, box = modal(560, 330)
	yardFullOpen = back
	UI.label(box, { Size = UDim2.new(1, -30, 0, 40), Position = UDim2.fromOffset(15, 12), Text = "Your yard is full!", ZIndex = 42 })
	-- "Later" closes it so you can buy yard space; tossing asks again
	UI.button(box, "Later", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(100, 44), BackgroundColor3 = C.PanelLight, ZIndex = 43,
	}, function()
		back:Destroy()
		yardFullOpen = nil
	end)
	UI.label(box, { Size = UDim2.new(1, -30, 0, 22), Position = UDim2.fromOffset(15, 52), Text = "Get more yard space in Upgrades.", TextColor3 = C.Dim, ZIndex = 42 })
	local function side(x, title, kind, mut, buttonText, color, choice, rank)
		UI.label(box, { Size = UDim2.fromOffset(250, 24), Position = UDim2.fromOffset(x, 84), Text = title, TextColor3 = C.Dim, ZIndex = 42 })
		UI.viewport(box, Looks.thinglet(kind, mut, false), { Size = UDim2.fromOffset(250, 110), Position = UDim2.fromOffset(x, 108), ZIndex = 42 })
		UI.label(box, { Size = UDim2.fromOffset(250, 26), Position = UDim2.fromOffset(x, 216), Text = thingletName(kind, mut), TextColor3 = rarityColor(kind), ZIndex = 42 })
		local armed = false
		local button
		button = UI.button(box, buttonText, { Position = UDim2.fromOffset(x + 15, 250), Size = UDim2.fromOffset(220, 60), BackgroundColor3 = color, ZIndex = 42 }, function()
			if rank >= Config.Yard.ConfirmRank and not armed then
				armed = true
				button.Text = "Tap again to sell it"
				return
			end
			local result = act("yardChoice", choice)
			back:Destroy()
			yardFullOpen = nil
			-- the server may already have asked about the next egg: keep that one
			if result.ok and yardFullInfo == info then
				yardFullInfo = nil
			end
			if result.ok and result.msg ~= "" then
				UI.sound("Coin")
				toast(result.msg, C.Gold, 2.5)
			end
			if yardFullInfo then
				showYardFull()
			end
		end)
	end
	local newDef = Config.Thinglets[info.kind]
	local oldDef = Config.Thinglets[info.weakestKind]
	side(20, "New", info.kind, info.mut, "Sell new +" .. Rules.short(info.sellNew), C.Bad, "sellNew", newDef and Rules.rarityRank(newDef.rarity) or 0)
	if oldDef then
		side(290, "Weakest in your yard", info.weakestKind, info.weakestMut, "Swap it +" .. Rules.short(info.sellWeakest), C.Good, "swap", Rules.rarityRank(oldDef.rarity))
	end
end
UI.on("ShowYardFull", function()
	if yardFullInfo then
		showYardFull()
	else
		act("askYardFull") -- the server sends it again
	end
end)

local function showSizeUp(size, name, grew)
	local banner = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.32), Size = UDim2.fromOffset(560, 150),
		BackgroundColor3 = Color3.fromRGB(30, 15, 45), BackgroundTransparency = 0.1, ZIndex = 30,
	}, overlayGui)
	UI.corner(banner, UDim.new(0, 24))
	UI.stroke(banner, 4, Config.Thing.EyeColor)
	UI.fit(banner, 560, 150)
	UI.label(banner, { Size = UDim2.new(1, -20, 0, 54), Position = UDim2.fromOffset(10, 10), Text = "YOUR THING GREW!", TextColor3 = Config.Thing.EyeColor, ZIndex = 31 })
	UI.label(banner, { Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(10, 66), Text = "Size " .. size .. ": " .. name, ZIndex = 31 })
	UI.label(banner, { Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 104), Text = grew, TextColor3 = C.Dim, ZIndex = 31 })
	UI.sound("SizeUp")
	UI.fire("CameraShake", 0.5)
	task.delay(3.2, function()
		banner:Destroy()
	end)
	if size == 2 then
		task.delay(3.4, function()
			toast("The belly holds 5 now. What you feed it decides what hatches!", Config.Thing.EyeColor, 7)
		end)
	end
end

----------------------------------------------------------------------
-- The hatch reveal
----------------------------------------------------------------------
local revealQueue = {}

local function playReveal(info)
	revealing = true
	local def = Config.Thinglets[info.kind]
	local rarity = Config.Rarities[def.rarity]
	local rank = Rules.rarityRank(def.rarity)
	local slow = info.newLook or rank >= 3
	local back = UI.new("TextButton", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 5, 20), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 50,
	}, overlayGui)
	tween(back, 0.25, { BackgroundTransparency = 0.35 })
	-- everything sits on a 520 x 520 stage that shrinks to fit small screens
	local stage = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(520, 520),
		BackgroundTransparency = 1, ZIndex = 51,
	}, back)
	UI.fit(stage, 520, 520)
	local glow = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(260, 220), Size = UDim2.fromOffset(300, 300),
		BackgroundColor3 = rarity.color, BackgroundTransparency = 1, ZIndex = 51,
	}, stage)
	UI.corner(glow, UDim.new(1, 0))
	local view = UI.viewport(stage, nil, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(260, 220), Size = UDim2.fromOffset(320, 320), ZIndex = 52,
	})
	local title = UI.label(stage, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(260, 0), Size = UDim2.fromOffset(500, 40), ZIndex = 53,
		Text = info.source == "daily" and "Daily craving bonus egg!" or "A new egg!", TextColor3 = C.Dim,
	})
	local nameLabel = UI.label(stage, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(260, 390), Size = UDim2.fromOffset(500, 56), ZIndex = 53, Text = "", TextColor3 = rarity.color,
	})
	local subLabel = UI.label(stage, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(260, 450), Size = UDim2.fromOffset(500, 30), ZIndex = 53, Text = "", TextColor3 = C.Dim,
	})

	local skip = false
	local canSkip = false
	back.Activated:Connect(function()
		if canSkip then
			skip = true
		end
	end)
	task.delay(1, function()
		canSkip = true
	end)
	local function wait(seconds)
		local start = os.clock()
		while os.clock() - start < seconds and not skip do
			RunService.RenderStepped:Wait()
		end
	end

	-- 1. the egg wobbles
	local egg = Looks.egg(def.rarity)
	UI.setViewportModel(view, egg, 180)
	local eggPivot = egg:GetPivot()
	local wobbleTime = slow and 1.2 or 0.6
	local start = os.clock()
	while os.clock() - start < wobbleTime and not skip do
		local k = (os.clock() - start) / wobbleTime
		egg:PivotTo(eggPivot * CFrame.Angles(0, 0, math.sin(k * 30) * 0.25 * k))
		RunService.RenderStepped:Wait()
	end

	-- 2. crack! a flash, then (for something new) its shadow first
	UI.sound("Crack")
	glow.BackgroundTransparency = 0.1
	tween(glow, 0.5, { BackgroundTransparency = 0.55 })
	if info.newKind and slow and not skip then
		local shadow = Looks.silhouette(Looks.thinglet(info.kind, nil, false))
		UI.setViewportModel(view, shadow, 200)
		nameLabel.Text = "???"
		nameLabel.TextColor3 = C.Text
		wait(0.7)
	end

	-- 3. the reveal
	local model = Looks.thinglet(info.kind, info.mut, false)
	UI.setViewportModel(view, model, 200)
	nameLabel.Text = thingletName(info.kind, info.mut)
	nameLabel.TextColor3 = info.mut and Rules.mutation(info.mut) and Rules.mutation(info.mut).color or rarity.color
	local sub = string.upper(def.rarity) .. "  |  +" .. Rules.short(Rules.fullIncome({ kind = info.kind, mut = info.mut })) .. "/s when grown"
	if info.newLook then
		sub = "NEW!  " .. sub
	end
	subLabel.Text = sub
	title.Text = info.newKind and "You discovered a new Thinglet!" or title.Text
	UI.pop(nameLabel, 0.5)
	UI.sound(rank >= 3 and "HatchRare" or "Hatch")
	if rank >= 3 or info.mut == "Gold" then
		UI.fire("CameraShake", 0.4)
	end
	local pivot = model:GetPivot()
	local spinStart = os.clock()
	local showFor = slow and 1.6 or 0.9
	while os.clock() - spinStart < showFor and not skip do
		model:PivotTo(pivot * CFrame.Angles(0, (os.clock() - spinStart) * 1.5, 0))
		RunService.RenderStepped:Wait()
	end
	back:Destroy()
	revealing = false
	if info.pending then
		showYardFull()
	end
end

local function nextReveal()
	if revealing or #revealQueue == 0 then
		return
	end
	local info = table.remove(revealQueue, 1)
	task.spawn(function()
		playReveal(info)
		nextReveal()
	end)
end

HatchedRemote.OnClientEvent:Connect(function(info)
	if type(info) ~= "table" or not Config.Thinglets[info.kind] then
		return
	end
	table.insert(revealQueue, info)
	-- give the egg a moment to pop out of the hatch first
	task.delay(info.source == "daily" and 0 or 0.7, nextReveal)
end)

----------------------------------------------------------------------
-- Messages from the server
----------------------------------------------------------------------
NotifyRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	if payload.type == "announce" then
		showBanner(payload.text, payload.color, 6)
		UI.sound("Announce", 0.5)
	elseif payload.type == "weather" then
		showBanner(payload.text, Color3.fromRGB(200, 230, 255), 8)
	elseif payload.type == "welcome" then
		showWelcome(payload.coins or 0, payload.away or 0)
	elseif payload.type == "yardFull" then
		yardFullInfo = payload
		-- if its egg is still to be revealed, the reveal opens this when it ends
		if not revealing and #revealQueue == 0 then
			task.delay(0.1, showYardFull)
		end
	elseif payload.type == "sizeUp" then
		showSizeUp(payload.size, payload.name, payload.grew)
	end
end)

----------------------------------------------------------------------
-- Camera shake (a small, short wobble)
----------------------------------------------------------------------
UI.on("CameraShake", function(strength)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local start = os.clock()
	local duration = 0.25
	while os.clock() - start < duration do
		local k = 1 - (os.clock() - start) / duration
		humanoid.CameraOffset = Vector3.new((math.random() - 0.5), (math.random() - 0.5), 0) * strength * k
		RunService.RenderStepped:Wait()
	end
	humanoid.CameraOffset = Vector3.zero
end)

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local lastHatches = nil
local function refreshHints()
	if not state then
		return
	end
	-- first hint after the first hatch: buy a Chili seed
	local shopHint = sideButtons.Shop.hint
	local hasChili = false
	for _, crop in ipairs(state.plants or {}) do
		if crop == "Chili" then
			hasChili = true
		end
	end
	local chili = Rules.crop("Chili")
	local showChili = (state.stats.hatches or 0) >= 1 and not hasChili and chili ~= nil and state.coins >= chili.seed
	shopHint.Visible = showChili
	shopHint.Text = "Buy a Chili seed!"
	shopRows.Chili.stroke.Color = showChili and C.Gold or C.Stroke
	shopRows.Chili.stroke.Thickness = showChili and 4 or 2

	-- red dots: something you can afford
	local affordable = false
	for _, crop in ipairs(Config.Crops) do
		local left = state.stock and state.stock[crop.id] or 0
		if left ~= 0 and state.coins >= crop.seed and Rules.cropRank(crop.id) > 2 then
			affordable = true
		end
	end
	sideButtons.Shop.dot.Visible = affordable or showChili
	local plotPrice = Config.Garden.PlotPrices[state.plots + 1]
	local yardPrice = Config.Yard.Prices[state.yardCap + 1]
	sideButtons.Upgrades.dot.Visible = (plotPrice ~= nil and state.coins >= plotPrice) or (yardPrice ~= nil and state.coins >= yardPrice and state.yardCount >= state.yardCap)
	sideButtons.Daily.dot.Visible = state.daily ~= nil and not state.daily.done and (state.stats.hatches or 0) >= 1
	if lastHatches and state.stats.hatches > lastHatches then
		sideButtons.Dex.dot.Visible = true
	end
	lastHatches = state.stats.hatches
end

-- the seed stand at the end of the street opens the shop too
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt.Name == "SeedShopPrompt" and openPanel ~= "Shop" then
		showPanel("Shop")
		refreshShop()
	end
end)

UI.on("PanelOpened", function(name)
	if name == "Dex" then
		sideButtons.Dex.dot.Visible = false
	end
end)

StateRemote.OnClientEvent:Connect(function(newState)
	if type(newState) ~= "table" then
		return
	end
	local first = state == nil
	state = newState
	UI.state = newState
	if first then
		displayCoins = state.coins
	end
	incomeLabel.Text = "+" .. Rules.rate(state.income or 0) .. "/s"
	refreshHints()
	if openPanel == "Shop" then
		refreshShop()
	elseif openPanel == "Upgrades" then
		refreshUpgrades()
	elseif openPanel == "Dex" then
		refreshDex()
	elseif openPanel == "Daily" then
		refreshDaily()
	end
end)

-- coins count up smoothly; the shop timer and weather chip tick
local tick = 0
RunService.RenderStepped:Connect(function(dt)
	if state then
		local target = state.coins
		if math.abs(target - displayCoins) < 1 then
			displayCoins = target
		else
			displayCoins += (target - displayCoins) * math.min(1, dt * 8)
		end
		coinsLabel.Text = Rules.short(displayCoins)
	end
	tick += dt
	if tick >= 0.5 then
		tick = 0
		if openPanel == "Shop" then
			refreshShop()
		end
		if openPanel == "Daily" then
			refreshDaily()
		end
		-- "Snow in 2m 31s", or "Full Moon! 1m 05s left"
		local now = serverNow()
		local current, changeAt = Rules.weatherAt(now)
		local left = math.max(0, math.floor(changeAt - now))
		local timeText = left >= 60 and string.format("%dm %02ds", left // 60, left % 60) or (left .. "s")
		if current then
			weatherChip.Text = current.name .. "! " .. timeText .. " left"
			setWeatherIcon(current.id == "Snow" and "snow" or "moon")
		else
			local coming = Rules.weatherAt(changeAt + 1)
			weatherChip.Text = (coming and coming.name or "Weather") .. " in " .. timeText
			setWeatherIcon("sun")
		end
	end
end)
