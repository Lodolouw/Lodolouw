--[[
	Hud  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "Hud")

	Everything on screen except the food bar:
	  * coins (bottom left) with coins per second, and the weather
	  * two big buttons on the left: Upgrades and Index
	  * the panels they open
	  * the hatch reveal (big for something special, a small pop for the
	    rest), "Welcome back", a Thinglet's card, the size-up banner, the
	    coin truck and server announcements

	Built for phones first: big buttons, few of them, nothing in the corners
	Roblox uses (top bar, thumbstick, jump button).
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

-- Coins burst out of a spot in the world and fly into the counter
local function coinBurst(worldPosition, amount)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local screen, onScreen = camera:WorldToViewportPoint(worldPosition)
	if not onScreen then
		return
	end
	local inset = game:GetService("GuiService"):GetGuiInset()
	local from = Vector2.new(screen.X, screen.Y) - inset
	local target = coinsLabel.AbsolutePosition + Vector2.new(20, coinsLabel.AbsoluteSize.Y / 2)
	local count = math.clamp(math.floor(math.log10(math.max(amount, 1)) * 3) + 3, 3, 12)
	for i = 1, count do
		local coin = UI.icon(gui, "coin", {
			AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(from.X, from.Y), ZIndex = 30,
		})
		local burst = from + Vector2.new(math.random(-70, 70), math.random(-80, -10))
		task.spawn(function()
			local out = TweenService:Create(coin, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(burst.X, burst.Y) })
			out:Play()
			task.wait(0.25 + i * 0.03)
			local home = TweenService:Create(coin, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromOffset(target.X, target.Y), Size = UDim2.fromOffset(18, 18),
			})
			home:Play()
			home.Completed:Wait()
			coin:Destroy()
			UI.pop(coinsLabel, 0.12)
			UI.sound("Coin", 0.25, 1.3 + i * 0.03)
		end)
	end
end
UI.on("CoinBurst", coinBurst)

----------------------------------------------------------------------
-- Side buttons: Upgrades and Index, on the left
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
local leftBar = sideColumn("LeftButtons", 0, 0, 220)

local sideButtons = {}
-- wide = a long button with an icon and a word; else a square icon button
local function sideButton(name, label, order, icon, color, wide, onClick)
	local parent = leftBar
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
		Size = UDim2.fromOffset(260, 30), AnchorPoint = Vector2.new(wide and 0 or 1, 0.5),
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

-- headerHeight: a slimmer header for compact panels (default 70)
local function makePanel(name, title, width, height, headerColor, headerHeight)
	local h = headerHeight or 70
	local frame = UI.new("Frame", {
		Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(width, height), BackgroundColor3 = C.Panel, Visible = false, ZIndex = 20,
		Active = true, -- taps on the panel don't fall through to the throw pad
	}, gui)
	UI.chunky(frame, C.Panel, UDim.new(0, 18), 4)
	UI.studs(frame)
	UI.fit(frame, width, height)
	local header = UI.new("Frame", {
		Name = "Header", Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = headerColor or C.Green, ZIndex = 21,
	}, frame)
	UI.chunky(header, nil, UDim.new(0, 18), 4)
	local titleLabel = UI.label(header, {
		Size = UDim2.new(1, -120, 0, math.min(44, h - 12)), Position = UDim2.fromOffset(18, h < 70 and 6 or 4), Text = title,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22,
	})
	local titleStroke = titleLabel:FindFirstChildOfClass("UIStroke")
	if titleStroke then
		titleStroke.Thickness = 3
	end
	-- the subtitle: under the title, or on the right of a slim header
	local subtitle = h >= 70 and UI.label(header, {
		Size = UDim2.new(1, -120, 0, 20), Position = UDim2.fromOffset(18, 46), Text = "", TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22,
	}) or UI.label(header, {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -34, 0.5, 0), Size = UDim2.fromOffset(230, 24), Text = "",
		TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.Dim, ZIndex = 22,
	})
	local closeSize = h < 70 and 46 or 54
	local close = UI.button(frame, "", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(closeSize, closeSize), BackgroundColor3 = C.Red, ZIndex = 24,
	}, function()
		frame.Visible = false
		openPanel = nil
	end)
	close.Text = "X"
	local body = UI.new("ScrollingFrame", {
		Name = "Body", Position = UDim2.fromOffset(12, h + 10), Size = UDim2.new(1, -24, 1, -(h + 22)),
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
-- Every menu uses the same small cards in a 3-wide grid: compact panels,
-- so you still see the game around them
local CARD_W, CARD_H, GAP = 148, 164, 8
local COMPACT_W, COMPACT_H = 3 * CARD_W + 2 * GAP + 44, 2 * CARD_H + GAP + 86
local function cardGrid(body)
	UI.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(CARD_W, CARD_H), CellPadding = UDim2.fromOffset(GAP, GAP), SortOrder = Enum.SortOrder.LayoutOrder,
	}, body)
	UI.new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2), PaddingBottom = UDim.new(0, 6) }, body)
end

----------------------------------------------------------------------
-- Upgrades, incremental style: every upgrade has levels that cost more
-- each time. Buy one, ten or as many as you can afford. A small grid of
-- cards (icon, name, now -> next, price) so you still see the game.
-- (The rules and prices live in Rules / Config.Upgrades.)
----------------------------------------------------------------------
local upgrades = makePanel("Upgrades", "Upgrades", COMPACT_W, COMPACT_H, C.Accent, 56)
cardGrid(upgrades.body)

local refreshUpgrades -- (defined below)

-- x1 / x10 / MAX: how many levels a tap buys
local buyAmount = 1
local amountButtons = {}
local amountBar = UI.new("Frame", {
	AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -40, 0, 28), Size = UDim2.fromOffset(176, 36),
	BackgroundTransparency = 1, ZIndex = 23,
}, upgrades.frame)
UI.new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
	Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder,
}, amountBar)
for i, option in ipairs({ { 1, "x1" }, { 10, "x10" }, { 1000, "MAX" } }) do
	local amount = option[1]
	local button = UI.button(amountBar, option[2], { LayoutOrder = i, Size = UDim2.fromOffset(54, 36), ZIndex = 24 }, function()
		buyAmount = amount
		refreshUpgrades()
	end)
	amountButtons[amount] = button
end

local upgradeCards = {}

local function levelUpFlash(r, n)
	local flash = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Gold, BackgroundTransparency = 0.3, ZIndex = 30 }, r.card)
	UI.corner(flash, UDim.new(0, 12))
	tween(flash, 0.4, { BackgroundTransparency = 1 })
	task.delay(0.45, function()
		flash:Destroy()
	end)
	UI.pop(r.iconBox, 0.3)
	UI.pop(r.effect, 0.2)
	toast(n > 1 and (r.def.name .. " +" .. n .. " levels!") or (r.def.name .. " level up!"), C.Gold, 1.5)
end

local function buyUpgrade(id)
	local r = upgradeCards[id]
	local result = act("upgrade", id, buyAmount)
	if result.ok then
		UI.sound("Buy")
		levelUpFlash(r, result.n or 1)
	else
		UI.sound("Error", 0.6)
		toast(result.msg, C.Bad, 2)
	end
end

local function upgradeCard(def)
	local card = UI.new("Frame", { Name = def.id, BackgroundColor3 = C.PanelLight, ZIndex = 22 }, upgrades.body)
	UI.corner(card, UDim.new(0, 12))
	UI.stroke(card, 3)
	local iconBox = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(52, 52),
		BackgroundColor3 = C.Well, ZIndex = 23,
	}, card)
	UI.corner(iconBox, UDim.new(0, 10))
	UI.stroke(iconBox, 3)
	UI.icon(iconBox, def.icon, { Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1) })
	local name = UI.label(card, { Position = UDim2.fromOffset(6, 64), Size = UDim2.new(1, -12, 0, 24), Text = def.name, ZIndex = 23 })
	local effect = UI.label(card, { Position = UDim2.fromOffset(6, 89), Size = UDim2.new(1, -12, 0, 22), Text = "", RichText = true, ZIndex = 23 })
	local button = UI.button(card, "", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -16, 0, 42), ZIndex = 23,
	}, function()
		buyUpgrade(def.id)
	end)
	local coin = UI.icon(button, "coin", { Size = UDim2.fromOffset(24, 24), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 2, 0.5, 0) })
	local price = UI.number(button, {
		Position = UDim2.fromOffset(30, 0), Size = UDim2.new(1, -32, 1, 0), Text = "", ZIndex = 24,
	})
	upgradeCards[def.id] = {
		def = def, card = card, iconBox = iconBox, name = name, effect = effect,
		button = button, coin = coin, price = price,
	}
end
for _, def in ipairs(Config.Upgrades) do
	upgradeCard(def)
end

-- can you afford an upgrade right now? (the red dot on the button)
local function upgradeAffordable()
	if not state then
		return false
	end
	for _, def in ipairs(Config.Upgrades) do
		local cost = Rules.upgradeCost(def.id, Rules.upgradeLevel(state, def.id))
		if cost and state.coins >= cost then
			return true
		end
	end
	return false
end

function refreshUpgrades()
	if not state then
		return
	end
	for amount, button in pairs(amountButtons) do
		button.BackgroundColor3 = amount == buyAmount and C.Good or C.Well
	end
	for i, def in ipairs(Config.Upgrades) do
		local r = upgradeCards[def.id]
		local level = Rules.upgradeLevel(state, def.id)
		local max = Rules.upgradeMax(def.id)
		r.card.LayoutOrder = i
		if level >= max then
			r.effect.Text = Rules.upgradeShort(def.id, level)
			r.button.BackgroundColor3 = C.Gold
			r.coin.Visible = false
			r.price.Text = ""
			r.button.Text = "MAX"
		else
			local n, cost = Rules.upgradeBuy(def.id, level, state.coins, buyAmount)
			local priceNow = n > 0 and cost or Rules.upgradeCost(def.id, level)
			r.effect.Text = Rules.upgradeShort(def.id, level)
				.. '  <font color="#C8FF64">→ ' .. Rules.upgradeShort(def.id, math.min(max, level + math.max(n, 1))) .. "</font>"
			r.button.Text = ""
			r.coin.Visible = true
			r.price.Text = Rules.short(priceNow)
			r.button.BackgroundColor3 = n > 0 and C.Good or C.Well
		end
	end
end

----------------------------------------------------------------------
-- Dex: every Thinglet and its four looks. The ones you haven't found say
-- which food gives the best chance of them.
----------------------------------------------------------------------
-- the food most likely to hatch this kind (with no luck)
local function bestFood(kind)
	local def = Config.Thinglets[kind]
	local sameRarity = 0
	for _, other in pairs(Config.Thinglets) do
		if other.rarity == def.rarity and not other.secret then
			sameRarity += 1
		end
	end
	local best, bestChance = nil, -1
	for _, crop in ipairs(Config.Crops) do
		local chance
		if def.secret then
			chance = crop.secret or 0
		else
			local odds = Rules.hatchOdds(crop.id, 0)
			local favourite = Config.Thinglets[crop.thinglet]
			local share = 1 / sameRarity
			if favourite and favourite.rarity == def.rarity then
				share = crop.thinglet == kind and (Config.FavouriteChance + (1 - Config.FavouriteChance) / sameRarity)
					or (1 - Config.FavouriteChance) / sameRarity
			end
			chance = odds[def.rarity] * share
		end
		if chance > bestChance then
			best, bestChance = crop, chance
		end
	end
	return best
end

local function dexHint(kind)
	local def = Config.Thinglets[kind]
	local crop = bestFood(kind)
	if def.secret then
		return "A secret! Any egg might hold it..."
	end
	return crop and ("Most often from " .. crop.name) or ""
end

local dex = makePanel("Dex", "Thinglet Index", COMPACT_W, COMPACT_H, C.Cyan, 56)
cardGrid(dex.body)
local dexCards = {}
for i, kind in ipairs(Config.ThingletOrder) do
	local def = Config.Thinglets[kind]
	local card = UI.new("Frame", { Name = kind, LayoutOrder = i, BackgroundColor3 = C.PanelLight, ZIndex = 22 }, dex.body)
	UI.corner(card, UDim.new(0, 12))
	local stroke = UI.stroke(card, 3, Config.Rarities[def.rarity].color)
	local view = UI.viewport(card, nil, { Size = UDim2.new(1, -16, 0, 70), Position = UDim2.fromOffset(8, 4), ZIndex = 23 })
	local name = UI.label(card, { Size = UDim2.new(1, -10, 0, 22), Position = UDim2.fromOffset(5, 76), Text = "???", ZIndex = 23 })
	local hint = UI.label(card, {
		Size = UDim2.new(1, -12, 0, 34), Position = UDim2.fromOffset(6, 99), Text = dexHint(kind), TextColor3 = C.Dim, TextWrapped = true, ZIndex = 23,
	})
	local dots = {}
	for j, look in ipairs({ "Normal", "Frozen", "Glowing", "Gold" }) do
		local color = look == "Normal" and C.Text or (Rules.mutation(look) and Rules.mutation(look).color or C.Text)
		local dot = UI.new("Frame", {
			Size = UDim2.fromOffset(16, 16), Position = UDim2.new(0.5, -44 + (j - 1) * 24, 1, -22), BackgroundColor3 = color,
			BackgroundTransparency = 0.8, ZIndex = 23,
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
		c.hint.Text = known and (def.rarity .. "  |  " .. Rules.short(def.cps) .. "/s grown") or dexHint(kind)
		for look, dot in pairs(c.dots) do
			local has = entry and entry[look] == true
			dot.BackgroundTransparency = has and 0 or 0.8
			if has then
				found += 1
			end
		end
	end
	dex.subtitle.Text = string.format("Found %d of %d looks", found, total)
end

-- the buttons themselves
sideButton("Upgrades", "Upgrades", 1, "upgrade", C.Accent, true, function()
	showPanel("Upgrades")
	refreshUpgrades()
end)
sideButton("Dex", "Index", 2, "book", C.Cyan, true, function()
	showPanel("Dex")
	refreshDex()
end)

----------------------------------------------------------------------
-- Popups: Thinglet card, welcome back, size up
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
	UI.studs(box)
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

local function showWelcome(coins, away, eggs)
	local back, box = modal(420, 270)
	UI.label(box, { Size = UDim2.new(1, -30, 0, 44), Position = UDim2.fromOffset(15, 16), Text = "Welcome back!", TextColor3 = Config.Thing.EyeColor, ZIndex = 42 })
	UI.label(box, { Size = UDim2.new(1, -30, 0, 28), Position = UDim2.fromOffset(15, 66), Text = "While you were away, your Thinglets earned", TextColor3 = C.Dim, ZIndex = 42 })
	coinIcon(box, 40, UDim2.new(0.5, -110, 0, 104)).ZIndex = 42
	UI.label(box, { Size = UDim2.fromOffset(200, 50), Position = UDim2.new(0.5, -60, 0, 99), Text = "+" .. Rules.short(coins), TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 42 })
	local note = nil
	if eggs > 0 then
		note = eggs == 1 and "...and an egg is ready to hatch!" or ("...and " .. eggs .. " eggs are ready to hatch!")
	elseif away > Config.Offline.MaxSeconds then
		note = "(they earn for up to " .. math.floor(Config.Offline.MaxSeconds / 3600 + 0.5) .. " hours while you're away)"
	end
	if note then
		UI.label(box, { Size = UDim2.new(1, -30, 0, 22), Position = UDim2.fromOffset(15, 152), Text = note, TextColor3 = C.Dim, ZIndex = 42 })
	end
	UI.button(box, "Collect", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(220, 62), ZIndex = 42 }, function()
		back:Destroy()
		UI.sound("Coin")
		UI.pop(coinsBox, 0.25)
	end)
end

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
end

----------------------------------------------------------------------
-- Hatching. Something special (a new kind, a mutation, Epic or better)
-- gets the big reveal; everything else pops up small on the right, so
-- you can keep feeding.
----------------------------------------------------------------------
-- what happened in the yard, in words
local function outcome(info)
	if info.how == "replace" and info.soldKind then
		return "Took your " .. thingletName(info.soldKind, info.soldMut) .. "'s spot  +" .. Rules.short(info.sold or 0), C.Gold
	elseif info.how == "sell" then
		return "Yard full of better ones: sold  +" .. Rules.short(info.sold or 0), C.Dim
	end
	return "Off to your yard!", C.Dim
end

local popList = UI.new("Frame", {
	Name = "Hatches", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.42, 0),
	Size = UDim2.fromOffset(280, 3 * 82), BackgroundTransparency = 1,
}, gui)
UI.new("UIListLayout", {
	VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right,
	Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
}, popList)
local popOrder = 0

local function smallPop(info)
	local def = Config.Thinglets[info.kind]
	popOrder += 1
	local box = UI.new("Frame", {
		LayoutOrder = popOrder, Size = UDim2.fromOffset(270, 76), BackgroundColor3 = C.PanelLight,
	}, popList)
	UI.chunky(box, C.PanelLight, UDim.new(0, 14), 3)
	local stroke = box:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Config.Rarities[def.rarity].color
	end
	UI.viewport(box, Looks.thinglet(info.kind, info.mut, false), { Size = UDim2.fromOffset(66, 66), Position = UDim2.fromOffset(5, 5) })
	UI.label(box, {
		Size = UDim2.new(1, -84, 0, 30), Position = UDim2.fromOffset(76, 8), Text = thingletName(info.kind, info.mut),
		TextColor3 = rarityColor(info.kind), TextXAlignment = Enum.TextXAlignment.Left,
	})
	local text, color = outcome(info)
	UI.label(box, {
		Size = UDim2.new(1, -84, 0, 22), Position = UDim2.fromOffset(76, 42), Text = text, TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	UI.pop(box, 0.2)
	UI.sound("Hatch", 0.5)
	local boxes = {}
	for _, child in ipairs(popList:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(boxes, child)
		end
	end
	table.sort(boxes, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	if #boxes > 3 then
		boxes[1]:Destroy()
	end
	task.delay(2.2, function()
		if box.Parent then
			tween(box, 0.25, { BackgroundTransparency = 1 })
			task.wait(0.25)
			box:Destroy()
		end
	end)
end

local revealQueue = {}
local revealing = false

local function playReveal(info)
	revealing = true
	local def = Config.Thinglets[info.kind]
	local rarity = Config.Rarities[def.rarity]
	local rank = Rules.rarityRank(def.rarity)
	local crop = Rules.crop(info.food)
	local slow = info.newKind or rank >= 3
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
		Text = crop and ("Your " .. crop.name .. " egg is hatching!") or "Your egg is hatching!", TextColor3 = C.Dim,
	})
	local nameLabel = UI.label(stage, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(260, 390), Size = UDim2.fromOffset(500, 56), ZIndex = 53, Text = "", TextColor3 = rarity.color,
	})
	local subLabel = UI.label(stage, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(260, 446), Size = UDim2.fromOffset(500, 30), ZIndex = 53, Text = "", TextColor3 = C.Dim,
	})
	local outcomeLabel = UI.label(stage, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(260, 480), Size = UDim2.fromOffset(500, 26), ZIndex = 53, Text = "", TextColor3 = C.Dim,
	})

	local skip = false
	local canSkip = false
	back.Activated:Connect(function()
		if canSkip then
			skip = true
		end
	end)
	task.delay(0.6, function()
		canSkip = true
	end)
	local function wait(seconds)
		local start = os.clock()
		while os.clock() - start < seconds and not skip do
			RunService.RenderStepped:Wait()
		end
	end

	-- 1. the egg (speckled in its food's colour) wobbles
	local egg = Looks.egg(def.rarity, crop and crop.color)
	UI.setViewportModel(view, egg, 180)
	local eggPivot = egg:GetPivot()
	local wobbleTime = slow and 1.1 or 0.6
	local start = os.clock()
	while os.clock() - start < wobbleTime and not skip do
		local k = (os.clock() - start) / wobbleTime
		egg:PivotTo(eggPivot * CFrame.Angles(0, 0, math.sin(k * 30) * 0.25 * k))
		RunService.RenderStepped:Wait()
	end

	-- 2. crack! a flash in its rarity's colour, then (for something new) its shadow first
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
	local text, color = outcome(info)
	outcomeLabel.Text = text
	outcomeLabel.TextColor3 = color
	if info.newKind then
		title.Text = "You discovered a new Thinglet!"
	end
	UI.pop(nameLabel, 0.5)
	UI.sound(rank >= 3 and "HatchRare" or "Hatch")
	if rank >= 3 or info.mut == "Gold" then
		UI.fire("CameraShake", 0.4)
	end
	local pivot = model:GetPivot()
	local spinStart = os.clock()
	local showFor = slow and 1.6 or 1
	while os.clock() - spinStart < showFor and not skip do
		model:PivotTo(pivot * CFrame.Angles(0, (os.clock() - spinStart) * 1.5, 0))
		RunService.RenderStepped:Wait()
	end
	back:Destroy()
	revealing = false
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
	if info.newKind or info.newLook then
		sideButtons.Dex.dot.Visible = true
	end
	local def = Config.Thinglets[info.kind]
	local special = info.newKind or (info.mut ~= nil and info.mut ~= "") or Rules.rarityRank(def.rarity) >= Config.Eggs.BigReveal
	-- give the egg a moment to pop on its nest first
	task.delay(0.35, function()
		if special then
			table.insert(revealQueue, info)
			nextReveal()
		else
			smallPop(info)
		end
	end)
end)

----------------------------------------------------------------------
-- Messages from the server
----------------------------------------------------------------------
local function myLandingSpot()
	for _, folder in ipairs(ReplicatedStorage:WaitForChild("Plots"):GetChildren()) do
		if folder:GetAttribute("Owner") == player.UserId then
			local index = folder:GetAttribute("Index")
			if type(index) == "number" then
				return (Rules.plotCFrame(index) * CFrame.new(Config.Delivery.LandAt)).Position + Vector3.new(0, 1.5, 0)
			end
		end
	end
	return nil
end

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
		showWelcome(payload.coins or 0, payload.away or 0, payload.eggs or 0)
	elseif payload.type == "sizeUp" then
		showSizeUp(payload.size, payload.name, payload.grew)
	elseif payload.type == "truckComing" then
		toast("HONK! The coin truck is coming to your house!", C.Gold, 4)
	elseif payload.type == "tip" then
		toast("+" .. Rules.short(payload.coins or 0) .. " coins from the coin truck!", C.Gold, 3)
		local spot = myLandingSpot()
		if spot then
			coinBurst(spot, payload.coins or 1)
		end
		UI.sound("Coin")
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
local function refreshHints()
	if not state then
		return
	end
	-- red dot (and, until you've bought one, a hint): an upgrade you can afford
	local affordable = upgradeAffordable()
	local boughtAny = (state.yardCap or Config.Yard.StartCap) > Config.Yard.StartCap or next(state.upgrades or {}) ~= nil
	sideButtons.Upgrades.dot.Visible = affordable
	sideButtons.Upgrades.hint.Text = "Get more nests!"
	sideButtons.Upgrades.hint.Visible = affordable and not boughtAny
end

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
	if openPanel == "Upgrades" then
		refreshUpgrades()
	elseif openPanel == "Dex" then
		refreshDex()
	end
end)

-- coins count up smoothly; the weather chip ticks
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
