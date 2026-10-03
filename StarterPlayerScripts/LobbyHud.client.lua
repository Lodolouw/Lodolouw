--[[
	LobbyHud  (LocalScript, parent: StarterPlayerScripts)

	THE NEW LOBBY SCREEN (Previews/gui_windows_sketch.html, screen 1), in the
	new look (WindowKit), over the old HUD's level bar and heart:
	  * LEFT: four big picture buttons - SHOP, BAG, ARCADE, INDEX - with red
	    badges for what's waiting
	  * BOTTOM LEFT: your coins and tokens (the token's + opens the shop)
	  * TOP MIDDLE: your NEXT GOAL and how far away it is - and a glowing
	    trail on the ground and a beam of light lead you there. You walk
	    there and choose yourself: there's no FIGHT button.
	  * RIGHT: the FREE GIFT's clock (tap it when it's ready), REWARDS and
	    SETTINGS, then today's quest (fold it away with _)
	  * BY THE LEVEL BAR: "2X XP" and the like while a boost or pass is on
	  * BOTTOM RIGHT: the corner bonuses - more XP for time in this server
	    and for friends in it with you
	It hides in fights, in the intro and while a menu is open. The buttons
	open the menus (ReplicatedStorage/Menus); the old HUD's buttons are
	hidden while Config.NewHud is on.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
if Config.NewHud == false then
	return
end
local K = require(ReplicatedStorage:WaitForChild("WindowKit"))
local Menus = require(ReplicatedStorage:WaitForChild("Menus"))
local C = K.COLORS
local R = Config.Rewards

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
-- (Roblox's player list sits in the top right, where the gift / rewards /
-- settings buttons and today's quest are now: it's hidden)
pcall(function()
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

local ui = {} -- the pieces, by name (keeps this script's locals few)
local state, stateAt = nil, 0 -- the latest snapshot, and os.clock() when it came

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props or {}) do
		i[k] = v
	end
	if parent then
		i.Parent = parent
	end
	return i
end

-- "4:05" / "1:02:03"
local function clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	local h, m, s = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

----------------------------------------------------------------------
-- the screen
----------------------------------------------------------------------
do
	local old = playerGui:FindFirstChild("LobbyHud")
	if old then
		old:Destroy()
	end
end
local gui = new("ScreenGui", {
	Name = "LobbyHud",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 6,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
gui:SetAttribute("RetroSkip", true) -- (RetroUI leaves the new look alone)
local root = new("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)
do
	local uiScale = new("UIScale", {}, root)
	local function fit()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local s = math.clamp(cam.ViewportSize.Y / 1000, 0.5, 1.1)
		uiScale.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	fit()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
end

----------------------------------------------------------------------
-- LEFT: the picture buttons
----------------------------------------------------------------------
do
	local SIZE, GAP = 108, 16
	local left = new("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 20, 0.44, 0),
		Size = UDim2.fromOffset(SIZE * 2 + GAP, SIZE * 2 + GAP),
	}, root)
	ui.buttons = left
	local list = {
		{ "Shop", C.Gold, "SHOP", 0, 0 },
		{ "Bag", C.Teal, "BAG", 1, 0 },
		{ "Arcade", C.Pink, "ARCADE", 0, 1 },
		{ "Index", C.Purple, "INDEX", 1, 1 },
	}
	for _, b in ipairs(list) do
		local button, api = K.pic(left, {
			Name = b[1],
			Color = b[2],
			Icon = b[1],
			Label = b[3],
			Size = SIZE,
			Position = UDim2.fromOffset(b[4] * (SIZE + GAP), b[5] * (SIZE + GAP)),
		})
		ui[b[1]] = api
		button.Activated:Connect(function()
			if b[1] == "Arcade" then
				local open = ReplicatedStorage:FindFirstChild("ArcadeOpen")
				if open and open:IsA("BindableEvent") then
					open:Fire()
				end
			elseif b[1] == "Bag" and not Menus.defs.Bag then
				Menus.go("Weapons")
			else
				Menus.go(b[1])
			end
		end)
	end
end

----------------------------------------------------------------------
-- BOTTOM LEFT: your coins and tokens
----------------------------------------------------------------------
do
	local host = new("Frame", {
		Name = "Money",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 20, 1, -20),
		Size = UDim2.fromOffset(290, 124),
	}, root)
	new("UIListLayout", { Padding = UDim.new(0, 10), VerticalAlignment = Enum.VerticalAlignment.Bottom, SortOrder = Enum.SortOrder.LayoutOrder }, host)
	local function row(kind, order)
		local r = new("Frame", {
			Name = kind,
			BackgroundColor3 = C.Ink,
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(kind == "Tokens" and 230 or 260, 56),
			LayoutOrder = order,
		}, host)
		K.outline(r, C.Ink, 3)
		local pic = (kind == "Coins" and K.coin or K.token)(r, 48, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 4, 0.5, 0), ZIndex = 2 })
		pic.Name = kind == "Coins" and "Coin" or "Token"
		local t = K.big(r, {
			Name = "Amount",
			Text = "0",
			TextScaled = false,
			TextSize = 36,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(60, 0),
			Size = UDim2.new(1, kind == "Tokens" and -110 or -66, 1, 0),
			ZIndex = 2,
		})
		local pop = new("UIScale", {}, t)
		return t, r, pop
	end
	ui.coins, ui.coinRow, ui.coinPop = row("Coins", 1)
	ui.tokens, ui.tokenRow, ui.tokenPop = row("Tokens", 2)
	local plus = K.button(ui.tokenRow, "+", C.Pink, {
		Name = "Plus",
		Font = K.FONT,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(40, 40),
		ZIndex = 3,
	})
	plus.Activated:Connect(function()
		Menus.go("Shop", "Tokens")
	end)
end

----------------------------------------------------------------------
-- TOP MIDDLE: the next goal
----------------------------------------------------------------------
do
	local face, holder = K.card(root, {
		Name = "NextGoal",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 66),
		Size = UDim2.fromOffset(500, 84),
		Visible = false,
	})
	ui.goal = holder
	ui.goalScale = new("UIScale", { Scale = 0.8 }, holder) -- (a bit smaller: it covered a lot of the view)
	ui.goalIcon = K.icon(face, "Spire", { Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(62, 62), ZIndex = 3 })
	ui.goalKicker = K.label(face, {
		Name = "Kicker",
		Text = "NEXT GOAL",
		Font = K.TITLE_FONT,
		TextScaled = false,
		TextSize = 13,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(84, 10),
		Size = UDim2.new(1, -190, 0, 18),
		ZIndex = 3,
	})
	ui.goalText = K.label(face, {
		Name = "Goal",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(84, 30),
		Size = UDim2.new(1, -190, 0, 30),
		ZIndex = 3,
	})
	ui.goalSub = K.label(face, {
		Name = "Sub",
		Text = "",
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(84, 58),
		Size = UDim2.new(1, -190, 0, 20),
		ZIndex = 3,
	})
	ui.goalFar = K.label(face, {
		Name = "Distance",
		Text = "",
		TextColor3 = C.Blue,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0, 30),
		Size = UDim2.fromOffset(96, 40),
		ZIndex = 3,
	})
	-- a little GUIDE ON / OFF switch in the card's corner, under the distance:
	-- the trail and the light to the goal (saved with your settings:
	-- SettingsMenu follows "GuideOff")
	local guideBtn = K.button(face, "GUIDE: ON", C.Green, { Name = "GuideToggle", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -10), Size = UDim2.fromOffset(92, 22), ZIndex = 6 })
	local function showGuide()
		local off = player:GetAttribute("GuideOff") == true
		guideBtn.Text = off and "GUIDE: OFF" or "GUIDE: ON"
		guideBtn.BackgroundColor3 = off and C.Off or C.Green
	end
	showGuide()
	player:GetAttributeChangedSignal("GuideOff"):Connect(showGuide)
	guideBtn.Activated:Connect(function()
		player:SetAttribute("GuideOff", (not player:GetAttribute("GuideOff")) or nil)
	end)
	-- THE NEW PLAYER PATH's progress: a pip per step under the card (lit up
	-- to the one you're on) - and an arrow that bobs beside a lobby button
	-- when that's where the step is (the BAG)
	local pips = new("Frame", { Name = "PathPips", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 8), Size = UDim2.fromOffset(300, 14), Visible = false }, ui.goal)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, pips)
	ui.pathPips, ui.pathPip = pips, {}
	for i = 1, Config.Path and #Config.Path.Steps or 0 do
		local pip = new("Frame", { Name = "Pip" .. i, LayoutOrder = i, BackgroundColor3 = C.Off, BorderSizePixel = 0, Size = UDim2.fromOffset(48, 12) }, pips)
		K.outline(pip, C.Ink, 2)
		ui.pathPip[i] = pip
	end
	ui.pathArrow = K.label(ui.buttons, {
		Name = "PathArrow",
		Text = "< HERE!",
		Font = K.TITLE_FONT,
		TextScaled = false,
		TextSize = 22,
		TextColor3 = C.Yellow,
		TextStrokeTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(170, 40),
		Visible = false,
		ZIndex = 20,
	})
	-- (tapping it: for a goal with no place to walk to, it opens the thing)
	local tap = new("TextButton", { Name = "Tap", Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4 }, face)
	tap.Activated:Connect(function()
		if ui.goalOpen then
			Menus.go(ui.goalOpen)
		end
	end)
end

----------------------------------------------------------------------
-- RIGHT: the free gift, rewards, settings; today's quest
----------------------------------------------------------------------
do
	local row = new("Frame", {
		Name = "Corner",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 16), -- (the top right corner, out of the way)
		Size = UDim2.fromOffset(3 * 88 + 2 * 14, 88),
	}, root)
	ui.corner = row
	local function small(name, color, icon, label, i)
		local b, api = K.pic(row, { Name = name, Color = color, Icon = icon, Label = label, Size = 88, Position = UDim2.fromOffset(i * (88 + 14), 0) })
		if api.label then
			api.label.TextScaled = true
		end
		return b, api
	end
	local gift, giftApi = small("Gift", C.Gold, "Gift", "--:--", 0)
	ui.gift = giftApi
	gift.Activated:Connect(function()
		if ui.giftReady then
			Menus.act("RewardGift")
		elseif ui.giftLeft then
			Menus.toast("Your free gift is ready in " .. clock(ui.giftLeft) .. " - keep playing!", "info")
		else
			Menus.toast("That's all the free gifts for today - more tomorrow!", "info")
		end
	end)
	local rewards, rewardsApi = small("Rewards", C.Green, "Rewards", "REWARDS", 1)
	ui.rewards = rewardsApi
	rewards.Activated:Connect(function()
		Menus.go("Rewards")
	end)
	local settings = small("Settings", C.Slate, "Settings", "SETTINGS", 2)
	settings.Activated:Connect(function()
		Menus.go("Settings")
	end)
	-- (and to their left, your party: PartyMenu - a little count while you're in one)
	local party, partyApi = small("Party", C.Blue, "Friends", "PARTY", -1)
	party.Activated:Connect(function()
		Menus.go("Party")
	end)
	local function partyLabel()
		local lead = player:GetAttribute("PartyLeader")
		local n = 0
		if lead then
			for _, p in ipairs(Players:GetPlayers()) do
				if p:GetAttribute("PartyLeader") == lead then
					n += 1
				end
			end
		end
		if partyApi.label then
			partyApi.label.Text = lead and ("PARTY " .. n .. "/4") or "PARTY"
		end
	end
	local function watchParty(p)
		p:GetAttributeChangedSignal("PartyLeader"):Connect(partyLabel)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		watchParty(p)
	end
	Players.PlayerAdded:Connect(watchParty)
	Players.PlayerRemoving:Connect(function()
		task.defer(partyLabel)
	end)

	-- today's quest (blue: quests)
	local face, holder = K.card(root, {
		Name = "Quest",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 16 + 88 + 22),
		Size = UDim2.fromOffset(3 * 88 + 2 * 14, 150),
	})
	ui.quest = holder
	local bar = new("Frame", { Name = "Bar", BackgroundColor3 = C.Blue, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 34), ZIndex = 3 }, face)
	new("Frame", { Name = "Rule", BackgroundColor3 = C.Ink, BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 3), ZIndex = 3 }, bar)
	K.label(bar, {
		Text = "TODAY'S QUEST",
		Font = K.TITLE_FONT,
		TextScaled = false,
		TextSize = 13,
		TextColor3 = C.White,
		TextStrokeTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -50, 1, 0),
		ZIndex = 4,
	})
	local fold = new("TextButton", {
		Name = "Fold",
		Text = "_",
		Font = K.TITLE_FONT,
		TextSize = 14,
		TextColor3 = C.Ink,
		AutoButtonColor = false,
		BackgroundColor3 = C.Paper,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -7, 0.5, 0),
		Size = UDim2.fromOffset(24, 24),
		ZIndex = 4,
	}, bar)
	K.outline(fold, C.Ink, 2.5)
	ui.questText = K.label(face, { Name = "Text", Text = "", TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Position = UDim2.fromOffset(12, 44), Size = UDim2.new(1, -24, 0, 30), ZIndex = 3 })
	ui.questMeter = K.meter(face, { Name = "Meter", Color = C.Blue, Position = UDim2.fromOffset(12, 80), Size = UDim2.new(1, -24, 0, 24), ZIndex = 3 })
	ui.questTime = K.label(face, {
		Name = "Time",
		Text = "",
		Font = K.TITLE_FONT,
		TextScaled = false,
		TextSize = 11,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(12, 114),
		Size = UDim2.new(1, -100, 0, 24),
		ZIndex = 3,
	})
	ui.questReward = K.label(face, {
		Name = "Reward",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -44, 0, 112),
		Size = UDim2.fromOffset(60, 28),
		ZIndex = 3,
	})
	K.token(face, 26, { Name = "RewardToken", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 113), ZIndex = 3 })
	ui.questFolded = false
	fold.Activated:Connect(function()
		ui.questFolded = not ui.questFolded
		holder.Size = UDim2.fromOffset(3 * 88 + 2 * 14, ui.questFolded and 37 or 150)
		fold.Text = ui.questFolded and "+" or "_"
	end)
end

----------------------------------------------------------------------
-- BY THE LEVEL BAR: boosts and passes on; BOTTOM RIGHT: the corner bonuses
----------------------------------------------------------------------
do
	local boosts = new("Frame", {
		Name = "Boosts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, 336, 1, -16 - 23),
		Size = UDim2.fromOffset(300, 32),
	}, root)
	new("UIListLayout", { Padding = UDim.new(0, 8), FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, boosts)
	ui.boostXP = K.chip(boosts, "2X XP", C.Pink, { Name = "XP", LayoutOrder = 1, Visible = false })
	ui.boostCoins = K.chip(boosts, "2X COINS", C.Gold, { Name = "Coins", LayoutOrder = 2, Visible = false })
	ui.boostLuck = K.chip(boosts, "LUCK", C.Green, { Name = "Luck", LayoutOrder = 3, Visible = false })

	local bonuses = new("Frame", {
		Name = "Bonuses",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -58),
		Size = UDim2.fromOffset(150, 76),
	}, root)
	new("UIListLayout", { Padding = UDim.new(0, 10), FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder }, bonuses)
	local tip = K.card(root, { Name = "BonusTip", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -144), Size = UDim2.fromOffset(330, 70), Visible = false, ZIndex = 8 })
	local tipText = K.label(tip, { Text = "", TextWrapped = true, Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 1, -12), ZIndex = 10 })
	local function bonus(name, icon, order, words)
		local b = new("TextButton", { Name = name, Text = "", BackgroundTransparency = 1, Size = UDim2.fromOffset(64, 76), LayoutOrder = order }, bonuses)
		K.icon(b, icon, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(46, 46), ZIndex = 2 })
		local t = K.big(b, { Name = "Amount", Text = "+0%", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, 12, 0, 28), ZIndex = 2 })
		local function show()
			tipText.Text = words
			tip.Parent.Visible = true
		end
		b.MouseEnter:Connect(show)
		b.MouseLeave:Connect(function()
			tip.Parent.Visible = false
		end)
		b.Activated:Connect(function()
			if tip.Parent.Visible then
				tip.Parent.Visible = false
			else
				show()
			end
		end)
		return t, b
	end
	ui.playBonus, ui.playButton = bonus("Playtime", "Playtime", 1, string.format("+%d%% XP for every %d minutes you stay in this server (up to +%d%%).", R.Playtime.PerStep, R.Playtime.StepMinutes, R.Playtime.Max))
	ui.friendBonus, ui.friendButton = bonus("Friends", "Friends", 2, string.format("+%d%% XP for each Roblox friend in this server with you (up to +%d%%) - more if they're VIP.", R.Friends.PerFriend, R.Friends.Max))
	-- (a touch screen: Roblox's jump button has the bottom-right corner - 70
	-- pixels across on a small screen, 120 on a big one, 95 / 170 in from
	-- the right - so the bonuses step to its left, a little higher)
	local function placeBonuses()
		local UIS = game:GetService("UserInputService")
		local cam = workspace.CurrentCamera
		local sc = root:FindFirstChildOfClass("UIScale")
		local s = math.max(sc and sc.Scale or 1, 0.05)
		if UIS and UIS.TouchEnabled and not UIS.KeyboardEnabled and cam then
			local vs = cam.ViewportSize
			local jumpLeft = math.min(vs.X, vs.Y) <= 500 and 95 or 170
			local x = -(jumpLeft + 10) / s
			bonuses.Position = UDim2.new(1, x, 1, -78)
			tip.Parent.Position = UDim2.new(1, x, 1, -164)
		else
			bonuses.Position = UDim2.new(1, -20, 1, -58)
			tip.Parent.Position = UDim2.new(1, -20, 1, -144)
		end
	end
	placeBonuses()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			task.defer(placeBonuses) -- (after the screen's own scale has followed)
		end)
	end
end

----------------------------------------------------------------------
-- WHAT'S NEXT: the goal, and where it is in the lobby
----------------------------------------------------------------------
-- the walk-up box for a place in the lobby (LobbyBuilder / ArcadeBuilder
-- make them): "Spire", "Arcade", "Quests"
local function zoneFor(place)
	for _, z in ipairs(CollectionService:GetTagged("AutoOpenZone")) do
		if z:IsA("BasePart") and z.Parent then
			if place == "Spire" and z:GetAttribute("Spire") == "Menu" then
				return z
			elseif z:GetAttribute("Activity") == place then
				return z
			end
		end
	end
	return nil
end

-- the next goal for data `d`: { text, sub, icon, place (walk there) or open (a menu) }
local function nextGoal(d)
	if not d then
		return nil
	end
	-- THE NEW PLAYER PATH comes first, step by step (Config.Path; the server
	-- moves you on when it sees the step done)
	local P = type(d.Path) == "table" and d.Path or nil
	local steps = Config.Path and Config.Path.Steps or {}
	local at = P and not P.done and tonumber(P.step) or 0
	if steps[at] then
		local s = steps[at]
		local open = s.Open
		if open == "Bag" and not Menus.defs.Bag then
			open = "Weapons"
		end
		return { text = s.Text, sub = s.Sub, icon = s.Icon, place = s.Place, open = open, point = s.Point, path = at, total = #steps }
	end
	local q = type(d.Quests) == "table" and d.Quests or {}
	local list = type(q.list) == "table" and q.list or {}
	local picked = q.pick and list[q.pick]
	local def = picked and Config.QuestById[picked.id]
	if def and not picked.claimed and (picked.n or 0) >= def.goal then
		return { text = "Hand in your quest", sub = "at the Quest Board", icon = "Goals", place = "Quests" }
	end
	local tokens = tonumber(d.Tokens) or 0
	if tokens > 0 then
		return { text = "Spin at the Arcade", sub = tokens == 1 and "You have a token to spin!" or ("You have " .. tokens .. " tokens to spin!"), icon = "Arcade", place = "Arcade" }
	end
	if not q.pick and #list > 0 then
		return { text = "Pick a quest", sub = "at the Quest Board - it pays a token", icon = "Goals", place = "Quests" }
	end
	local level = Config.levelFromPower(tonumber(d.Power) or 0)
	local cleared = type(d.Cleared) == "table" and d.Cleared or {}
	-- the first boss not beaten, tier by tier (Normal, then Nightmare...)
	for _, t in ipairs(Config.Spire.Tiers or { { id = "Normal" } }) do
		local normal = t.id == "Normal"
		for _, f in ipairs(Config.Spire.Floors) do
			local key = normal and tostring(f.id) or (t.id .. ":" .. f.id)
			if f.open ~= false and (tonumber(cleared[key]) or 0) <= 0 then
				local short = string.match(f.boss, "^([^,]+)") or f.boss
				local need = Config.spireLevel and Config.spireLevel(f.id, t.id) or f.level
				local where = (normal and "Floor " or (t.name .. " ")) .. f.id
				if level + 5 >= need then
					return { text = "Climb the Spire · " .. where, sub = "Beat " .. short, icon = "Spire", place = "Spire" }
				end
				-- (the Colosseum is the Spire's ground floor: the trail leads to the Spire)
				return { text = "Train in the Colosseum", sub = "Spire ground floor · Lv " .. need .. " for " .. where .. " (you're Lv " .. level .. ")", icon = "Weapons", place = "Spire" }
			end
		end
	end
	return { text = "Every boss beaten!", sub = "Even on Doom! Beat them again for more", icon = "Bosses", place = "Spire" }
end
ui.nextGoal = nextGoal

-- THE TRAIL: glowing dashes on the ground from your feet towards the goal,
-- a pulse running along them, and a beam of light standing on the goal
local DASHES = 10
local trail = { dashes = {} }
do
	local folder = workspace:FindFirstChild("GuideTrail")
	if folder then
		folder:Destroy()
	end
	folder = new("Folder", { Name = "GuideTrail" }, workspace)
	trail.folder = folder
	for i = 1, DASHES do
		trail.dashes[i] = new("Part", {
			Name = "Dash",
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Material = Enum.Material.Neon,
			Color = C.Yellow,
			Size = Vector3.new(0.8, 0.15, 2.2),
			Transparency = 1,
		}, folder)
	end
	trail.beam = new("Part", {
		Name = "Beam",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.Neon,
		Color = C.Yellow,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(44, 1.6, 1.6),
		Transparency = 1,
	}, folder)
end

local function hideTrail()
	for _, dash in ipairs(trail.dashes) do
		dash.Transparency = 1
	end
	trail.beam.Transparency = 1
end

local function ground(pos, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), params)
	return hit and hit.Position or nil
end

----------------------------------------------------------------------
-- keeping it up to date
----------------------------------------------------------------------
local function inFight()
	return player:GetAttribute("SpireFloor") ~= nil or player:GetAttribute("Colosseum") == true or player:GetAttribute("Intro") ~= nil
end
local function shown()
	return not inFight() and player:GetAttribute("MenuOpen") == nil
end

local function bump(pop)
	pop.Scale = 1.25
	task.delay(0.12, function()
		pop.Scale = 1
	end)
end

-- the badges and numbers (on every snapshot)
local function render()
	local d = state
	if not d then
		return
	end
	local coins, tokens = tonumber(d.Coins) or 0, tonumber(d.Tokens) or 0
	if ui.lastCoins and coins > ui.lastCoins then
		bump(ui.coinPop)
	end
	if ui.lastTokens and tokens > ui.lastTokens then
		bump(ui.tokenPop)
	end
	ui.lastCoins, ui.lastTokens = coins, tokens
	ui.coins.Text = Config.format(coins)
	ui.tokens.Text = tostring(tokens)

	ui.Arcade.badge(tokens > 0 and tokens or nil)
	-- the Index: weapons found but not claimed, collector levels reached
	local rw = type(d.Rewards) == "table" and d.Rewards or {}
	local idx = type(rw.index) == "table" and rw.index or {}
	local waiting = 0
	for id in pairs(type(d.Weapons) == "table" and type(d.Weapons.own) == "table" and d.Weapons.own or {}) do
		if Config.Weapons.List[id] and not idx[id] then
			waiting = waiting + 1
		end
	end
	ui.Index.badge(waiting > 0 and waiting or nil)
	-- the shop: the starter pack, once your first boss is down and it's not bought
	local cleared = type(d.Cleared) == "table" and d.Cleared or {}
	local starter = type(d.Shop) == "table" and d.Shop.starter
	ui.Shop.badge((not starter and (tonumber(cleared["1"]) or 0) > 0) and "!" or nil)
	-- rewards: today's login, the newest update's gift
	local count = 0
	if rw.streakDay ~= Config.questDay() then
		count = count + 1
	end
	local newest = R.Updates[1]
	if newest and not (type(rw.updates) == "table" and rw.updates[newest.Id]) then
		count = count + 1
	end
	ui.rewards.badge(count > 0 and count or nil)
	-- the goal
	ui.goalData = nextGoal(d)
end

-- the clocks, the quest, the boosts, the bonuses (4 times a second)
local function tick()
	root.Visible = shown()
	local d = state
	if not d then
		return
	end
	local since = os.clock() - stateAt
	-- the free gift
	local rw = type(d.Rewards) == "table" and d.Rewards or {}
	local need = R.GiftMinutes * 60
	if (tonumber(rw.giftsToday) or 0) >= R.GiftsPerDay and (tonumber(rw.giftPlay) or 0) < need then
		ui.giftReady, ui.giftLeft = false, nil
		ui.gift.label.Text = "TOMORROW"
		ui.gift.badge(nil)
	else
		local left = need - (tonumber(rw.giftPlay) or 0) - since
		ui.giftReady = left <= 0
		ui.giftLeft = math.max(0, left)
		ui.gift.label.Text = ui.giftReady and "READY!" or clock(left)
		ui.gift.badge(ui.giftReady and "!" or nil)
	end
	-- today's quest
	local q = type(d.Quests) == "table" and d.Quests or {}
	local list = type(q.list) == "table" and q.list or {}
	local picked = q.pick and list[q.pick]
	local def = picked and Config.QuestById[picked.id]
	ui.quest.Visible = #list > 0
	ui.questTime.Text = "NEW IN " .. clock(Config.nextQuestTime() - os.time())
	ui.questReward.Text = "+" .. Config.Quests.Tokens
	if not def then
		ui.questText.Text = "Pick one at the Quest Board!"
		ui.questMeter:set(0, #list .. " to choose from")
	elseif picked.claimed then
		ui.questText.Text = "Done! Well played."
		ui.questMeter:set(1, "HANDED IN")
	else
		local n = math.min(def.goal, tonumber(picked.n) or 0)
		ui.questText.Text = Config.questText(def)
		ui.questMeter:set(n / def.goal, n >= def.goal and "HAND IT IN!" or (n .. " / " .. def.goal))
	end
	-- boosts and passes
	local b = type(d.Boosts) == "table" and d.Boosts or {}
	local function boost(chip, key, pass, words)
		local left = (tonumber(b[key]) or 0) - since
		local has = player:GetAttribute(pass) == true
		chip.Visible = left > 0 or has
		K.chipText(chip, left > 0 and (words .. " " .. clock(left)) or words)
	end
	boost(ui.boostXP, "XP", "Pass_DoubleXP", "2X XP")
	boost(ui.boostCoins, "Coins", "Pass_DoubleCoins", "2X COINS")
	local luckPass = player:GetAttribute("Pass_Luck3") and "+200%" or player:GetAttribute("Pass_Luck2") and "+100%" or player:GetAttribute("Pass_Luck1") and "+50%" or nil
	local luckLeft = (tonumber(b.Luck) or 0) - since
	ui.boostLuck.Visible = luckPass ~= nil or luckLeft > 0
	K.chipText(ui.boostLuck, "LUCK " .. (luckPass or ("+50% " .. clock(luckLeft))))
	-- the corner bonuses
	ui.playBonus.Text = "+" .. (player:GetAttribute("PlayBonus") or 0) .. "%"
	ui.friendBonus.Text = "+" .. (player:GetAttribute("FriendBonus") or 0) .. "%"
	-- the goal card
	local g = ui.goalData
	ui.goal.Visible = g ~= nil
	if g then
		ui.goalText.Text = g.text
		ui.goalSub.Text = g.sub or ""
		ui.goalOpen = g.open
		-- the path: its step on the card, the pips, and a pop when it moves on
		ui.goalKicker.Text = g.path and ("NEW PLAYER PATH  ·  STEP " .. g.path .. " OF " .. g.total) or "NEXT GOAL"
		ui.goalKicker.TextColor3 = g.path and C.Pink or C.Muted
		ui.pathPips.Visible = g.path ~= nil
		for i, pip in ipairs(ui.pathPip) do
			pip.BackgroundColor3 = (g.path and i < g.path) and C.Green or (i == g.path and C.Yellow or C.Off)
		end
		if g.path and ui.lastPathStep and g.path ~= ui.lastPathStep then
			ui.goalScale.Scale = 1
			task.delay(0.18, function()
				ui.goalScale.Scale = 0.8
			end)
		end
		ui.lastPathStep = g.path
		if ui.goalIconKey ~= g.icon then
			ui.goalIconKey = g.icon
			local old = ui.goalIcon
			ui.goalIcon = K.icon(old.Parent, g.icon, { Position = old.Position, Size = old.Size, ZIndex = old.ZIndex })
			old:Destroy()
		end
	end
end

-- the trail and the distance (every frame)
local phase = 0
local function follow(dt)
	local g = ui.goalData
	-- the path's arrow, bobbing beside the button it means
	local target = g and g.point and shown() and ui.buttons:FindFirstChild(g.point)
	ui.pathArrow.Visible = target ~= nil
	if target then
		-- (beside it, in the buttons' own frame: right of the button, level with its middle)
		local bob = math.abs(math.sin(os.clock() * 5)) * 10
		local w, h = target.Size.X.Offset, target.Size.Y.Offset
		ui.pathArrow.Position = target.Position + UDim2.fromOffset(w + 10 + bob, h / 2)
	end
	local zone = g and g.place and shown() and zoneFor(g.place) or nil
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (zone and hrp) or player:GetAttribute("GuideOff") then
		hideTrail()
		if zone and hrp then -- (guide off: still says how far)
			ui.goalFar.Text = math.floor(Vector3.new(zone.Position.X - hrp.Position.X, 0, zone.Position.Z - hrp.Position.Z).Magnitude) .. "m"
			return
		end
		ui.goalFar.Text = ""
		return
	end
	local from, to = hrp.Position, zone.Position
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local dist = flat.Magnitude
	ui.goalFar.Text = math.floor(dist) .. "m"
	-- the beam stands on the goal
	trail.beam.CFrame = CFrame.new(to.X, to.Y - zone.Size.Y / 2 + 22, to.Z) * CFrame.Angles(0, 0, math.pi / 2)
	-- (soft: a guide, not a floodlight - short and thin, so from high up it
	-- doesn't streak across the view - and gone once you're close)
	trail.beam.Transparency = dist < 30 and 1 or 0.9
	if dist < 14 then
		for _, dash in ipairs(trail.dashes) do
			dash.Transparency = 1
		end
		return
	end
	local dir = flat.Unit
	phase = (phase + dt * 0.9) % 1
	local ignore = { trail.folder, char }
	for i, dash in ipairs(trail.dashes) do
		local along = 3 + i * 3.4
		local at = along < dist - 5 and ground(from + dir * along, ignore) or nil
		if at then
			dash.CFrame = CFrame.lookAt(at + Vector3.new(0, 0.1, 0), at + Vector3.new(0, 0.1, 0) + dir)
			-- (a bright pulse runs away from you along the dashes)
			local wave = (phase - i / DASHES) % 1
			dash.Transparency = 0.1 + 0.6 * wave + (i / DASHES) * 0.25
		else
			dash.Transparency = 1
		end
	end
end

Menus.onState(function(d)
	state, stateAt = d, os.clock()
	render()
	tick()
end)
player:GetAttributeChangedSignal("MenuOpen"):Connect(tick)
for _, attr in ipairs({ "SpireFloor", "Colosseum", "Intro" }) do
	player:GetAttributeChangedSignal(attr):Connect(tick)
end
do
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		follow(dt)
		acc = acc + dt
		if acc >= 0.25 then
			acc = 0
			tick()
		end
	end)
end

-- the older windows the buttons open (their own scripts register them too;
-- these are the fallbacks while they load)
Menus.external.Arcade = Menus.external.Arcade or function()
	local open = ReplicatedStorage:FindFirstChild("ArcadeOpen")
	if open and open:IsA("BindableEvent") then
		open:Fire()
	end
end

gui.Parent = playerGui
tick()
