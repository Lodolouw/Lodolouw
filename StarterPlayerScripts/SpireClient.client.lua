--[[
	SpireClient  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "SpireClient")

	The Spire's menus and travel effects:
	  * the Spire menu (walk up to the Spire's doors): one of the
	    see-through menus (ReplicatedStorage/Menus), like the Bag and the
	    Index - the floors as cards, and the one you pick, big: its boss,
	    the recommended level and yours, then ENTER
	  * a fade to black while you travel, then a big area title card as you
	    arrive ("GLOOMGUT'S HOLLOW")
	  * a Leave button while you're in an arena, and a "Leave?" check when you
	    touch the fog gate (both in the new look: WindowKit)
	  * THE GROUND FLOOR, at the top of the list: the Colosseum, the Spire's
	    training grounds (TRAIN takes you down into it from the doors). It
	    trains you for your next floor - below that floor's level, it pays
	    extra XP - and a floor you're under-levelled for offers TRAIN FIRST
	    beside ENTER.

	The server (SpireService) decides whether you may travel and moves you.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Arenas = require(ReplicatedStorage:WaitForChild("Arenas"))
local K = require(ReplicatedStorage:WaitForChild("WindowKit"))
local Menus = require(ReplicatedStorage:WaitForChild("Menus"))
local KC = K.COLORS
local SpireRemotes = ReplicatedStorage:WaitForChild("SpireRemotes")
local SpireEvent = SpireRemotes:WaitForChild("SpireEvent")
local SpireTravel = SpireRemotes:WaitForChild("SpireTravel")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RGB = Color3.fromRGB
local SERIF = Enum.Font.Garamond
local BOLD = Enum.Font.FredokaOne
local C = { -- (the area title card's colours)
	gold = RGB(230, 200, 130),
	pale = RGB(225, 220, 235),
}

----------------------------------------------------------------------
-- Small UI helpers
----------------------------------------------------------------------
local function create(className, props, children)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end
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
local function textStroke(thickness)
	return create("UIStroke", { Thickness = thickness, Color = RGB(0, 0, 0), Transparency = 0.2 })
end
local function label(props)
	local p = {
		BackgroundTransparency = 1,
		Font = BOLD,
		TextColor3 = C.pale,
		TextScaled = false,
		TextWrapped = true,
	}
	for k, v in pairs(props) do
		p[k] = v
	end
	return create("TextLabel", p)
end
local function tween(inst, seconds, props, style, dir)
	local t = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

----------------------------------------------------------------------
-- Root GUI (scales with the screen like the main HUD)
----------------------------------------------------------------------
local old = playerGui:FindFirstChild("SpireHud")
if old then
	old:Destroy()
end
local gui = create("ScreenGui", {
	Name = "SpireHud",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 20,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})
local root = create("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
local uiScale = create("UIScale", { Parent = root })
local function updateScale()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local s = math.clamp(cam.ViewportSize.Y / 1000, 0.5, 1.1)
	uiScale.Scale = s
	root.Size = UDim2.fromScale(1 / s, 1 / s)
end
updateScale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end

-- black screen for travelling (covers everything, including the main HUD)
local fader = create("Frame", {
	Name = "Fader",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = RGB(0, 0, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 100,
	Visible = false,
	Parent = gui,
})

-- a short message ("you can't travel right now" etc.): a toast at the top
-- of the screen, like every other menu's
local function showMessage(text)
	Menus.toast(text, "bad")
end

----------------------------------------------------------------------
-- Area title card ("GLOOMGUT'S HOLLOW"), Souls style
----------------------------------------------------------------------
local title = create("Frame", {
	Name = "AreaTitle",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.36),
	Size = UDim2.fromOffset(900, 150),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 90,
	Parent = root,
})
local titleText = label({
	Size = UDim2.new(1, 0, 0, 90),
	Position = UDim2.fromOffset(0, 22),
	Font = SERIF,
	Text = "",
	TextSize = 78,
	TextColor3 = C.pale,
	ZIndex = 91,
	Parent = title,
})
textStroke(2).Parent = titleText
local titleSub = label({
	Size = UDim2.new(1, 0, 0, 30),
	Position = UDim2.fromOffset(0, 112),
	Font = SERIF,
	Text = "",
	TextSize = 28,
	TextColor3 = C.gold,
	ZIndex = 91,
	Parent = title,
})
textStroke(1.5).Parent = titleSub
local titleLines = {}
for i, y in ipairs({ 14, 108 }) do
	titleLines[i] = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.fromOffset(0, 2),
		BackgroundColor3 = C.gold,
		BorderSizePixel = 0,
		ZIndex = 91,
		Parent = title,
	}, {
		create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
end

local titleToken = 0
local function showTitle(area, sub)
	titleToken = titleToken + 1
	local token = titleToken
	titleText.Text = string.upper(area)
	titleSub.Text = sub or ""
	titleText.TextTransparency = 1
	titleSub.TextTransparency = 1
	for _, l in ipairs(titleLines) do
		l.Size = UDim2.fromOffset(0, 2)
	end
	title.Visible = true
	tween(titleText, 1.2, { TextTransparency = 0 })
	tween(titleSub, 1.6, { TextTransparency = 0 })
	for _, l in ipairs(titleLines) do
		tween(l, 1.4, { Size = UDim2.fromOffset(640, 2) })
	end
	task.delay(3.6, function()
		if token ~= titleToken then
			return
		end
		tween(titleText, 1.2, { TextTransparency = 1 })
		tween(titleSub, 1.2, { TextTransparency = 1 })
		for _, l in ipairs(titleLines) do
			tween(l, 1.2, { Size = UDim2.fromOffset(0, 2) })
		end
		task.delay(1.3, function()
			if token == titleToken then
				title.Visible = false
			end
		end)
	end)
end

----------------------------------------------------------------------
-- Travel (fade out, ask the server, fade back in)
----------------------------------------------------------------------
local travelling = false
local arrivedInfo = nil -- set by the server's "Arrived" message

local function fadeTo(transparency, seconds)
	fader.Visible = true
	local t = tween(fader, seconds, { BackgroundTransparency = transparency }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	task.wait(seconds)
	if transparency >= 1 then
		fader.Visible = false
	end
	return t
end

local function travel(action, floorId, tierId)
	if travelling then
		return
	end
	travelling = true
	arrivedInfo = nil
	fadeTo(0, 0.45)
	local ok, success, reason = pcall(function()
		return SpireTravel:InvokeServer(action, floorId, tierId)
	end)
	if ok and success then
		task.wait(0.35) -- let the new area load in behind the black screen
		local info = arrivedInfo
		fadeTo(1, 0.8)
		if info then
			showTitle(info.area, info.sub)
		end
	else
		fadeTo(1, 0.4)
		showMessage(ok and (reason or "You can't travel right now.") or "Something went wrong.")
	end
	travelling = false
end

----------------------------------------------------------------------
-- The Spire menu: one of the see-through menus (ReplicatedStorage/Menus),
-- like the Bag and the Index. The floors as cards - the ground floor (the
-- Colosseum) and floors 1 to 10 - and the one picked, big: its boss, its
-- area, what it's like, the level it wants and yours, and ENTER.
----------------------------------------------------------------------
local selected = 1 -- (0: the ground floor, the Colosseum)

local function myLevel()
	local ls = player:FindFirstChild("leaderstats")
	local lv = ls and ls:FindFirstChild("Level")
	if lv then
		return lv.Value
	end
	local s = Menus.state
	return (s and Config.levelFromPower) and Config.levelFromPower(tonumber(s.Power) or 0) or 1
end

-- the Spire being looked at: Normal, or a harder tier (the menu's tabs:
-- Config.Spire.Tiers)
local viewTier = "Normal"
local function tierDef()
	return Config.spireTier(viewTier)
end
local function clearedUpTo()
	return player:GetAttribute(Config.spireClearedKey(viewTier)) or 0
end
-- a floor's recommended level on the tier being looked at
local function levelFor(f)
	return Config.spireLevel(f.id, viewTier)
end

-- A floor opens once the boss on the floor below it is beaten - on the same
-- tier, and a harder tier only once the one before it is beaten to the top
-- (devs can enter any open floor when Config.Spire.DevSkip is on). Returns
-- what you still have to beat, or nil if you can go in.
local function devSkip()
	return Config.Spire.DevSkip == true and (RunService:IsStudio() or player:GetAttribute("Dev") == true)
end
local function lockedBy(f)
	if devSkip() then
		return nil
	end
	local cleared = Config.spireCleared(player)
	if not Config.spireTierOpen(cleared, viewTier) then
		local _, i = Config.spireTier(viewTier)
		local before = Config.Spire.Tiers[i - 1]
		return "the whole Spire on " .. (before and before.name or "the tier before")
	end
	if not (Config.Spire.RequirePrevious and f.id > 1) or clearedUpTo() >= f.id - 1 then
		return nil
	end
	local below = Config.Spire.Floors[f.id - 1]
	return below and below.boss and string.match(below.boss, "^[^,]+") or "the floor below"
end

local function shortName(f)
	return string.match(f.boss or "", "^([^,]+)") or f.boss or "?"
end

-- what a floor is to you: "sealed", "locked" (and by whom), "beaten",
-- "low" (not beaten, and you're under its level) or "ready"
local function floorState(f)
	if not f.open then
		return "sealed"
	end
	local lock = lockedBy(f)
	if lock then
		return "locked", lock
	end
	if f.id <= clearedUpTo() then
		return "beaten"
	end
	if myLevel() < levelFor(f) then
		-- (under its level: locked until you get there - Config.Spire.LevelLock)
		return (Config.Spire.LevelLock and not devSkip()) and "level" or "low"
	end
	return "ready"
end
local STATE_CHIP = {
	sealed = { "SEALED", KC.Slate },
	locked = { "LOCKED", KC.Slate },
	beaten = { "BEATEN", KC.Green },
	low = { "TOO LOW", KC.Red },
	level = { "LOCKED", KC.Red },
	ready = { "READY", KC.Pink },
}

-- who picks the floor: nil (you're on your own), or your party
local function partyInfo()
	local lead = player:GetAttribute("PartyLeader")
	if not lead then
		return nil
	end
	local n, leaderName = 0, nil
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("PartyLeader") == lead then
			n += 1
			if p.UserId == lead then
				leaderName = p.Name
			end
		end
	end
	return { leading = lead == player.UserId, count = n, leader = leaderName or "your leader" }
end

local trainNow -- (below)

-- words on a card, white with an ink edge
local function words(parent, name, text, size, x, y, w, h, props)
	local l = K.big(parent, {
		Name = name,
		Text = text,
		TextScaled = false,
		TextSize = size,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.new(1, w, 0, h),
		ZIndex = 9,
		Edge = size >= 30 and 3 or 2,
	})
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

-- THE PICKED FLOOR, big (in `holder`, w x h)
local function drawDetail(holder, w, h, api)
	local f = selected > 0 and Config.Spire.Floors[selected] or nil
	local state, lock = "ready", nil
	if f then
		state, lock = floorState(f)
	end
	local open = f == nil or (state ~= "sealed" and state ~= "locked" and state ~= "level")
	-- (a floor locked only by your level still shows its boss: it's what you're training for)
	local shown = open or state == "level"
	local face = K.card(holder, { Name = "Detail", Size = UDim2.fromOffset(w, h), ZIndex = 7 }, f and (shown and f.color or KC.Slate) or KC.Orange)
	K.shine(face, 0.12).ZIndex = 8
	local party = partyInfo()
	local y = 18
	if not f then
		-- the ground floor: the Colosseum, training you for your next floor
		local bonus, nextF = Config.colosseumCatchUp(myLevel(), Config.spireCleared(player))
		local pct = math.floor(bonus * 100 + 0.5)
		K.chip(face, "GROUND FLOOR", KC.Ink, { Name = "FloorChip", Position = UDim2.fromOffset(20, y), ZIndex = 9 })
		K.chip(face, pct > 0 and ("+" .. pct .. "% XP") or "TRAINING", pct > 0 and KC.Green or KC.Blue, { Name = "State", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, y), ZIndex = 9 })
		words(face, "BossName", "The Colosseum", 46, 20, y + 42, -40, 56)
		words(face, "Area", "The training grounds", 26, 20, y + 100, -40, 32, { TextColor3 = KC.Yellow })
		words(face, "Blurb", "Waves of dummies, always your level, and the Straw King every 5th wave. Train here for the floor above: below its level, every win pays more XP.", 20, 20, y + 140, -40, 76)
		local row = y + 226
		if nextF then
			local c = K.chip(face, "TRAINING FOR: " .. (nextF.tier and (Config.spireTier(nextF.tier).name .. " ") or "") .. string.upper(shortName(nextF)) .. " LV " .. nextF.level, KC.Ink, { Name = "TrainingFor", Position = UDim2.fromOffset(20, row), ZIndex = 9 })
			K.chip(face, "YOU LV " .. myLevel(), myLevel() >= nextF.level and KC.Green or KC.Red, { Name = "You", Position = UDim2.new(0, 20 + c.Size.X.Offset + 10, 0, row), ZIndex = 9 })
		else
			K.chip(face, "YOU LV " .. myLevel(), KC.Green, { Name = "You", Position = UDim2.fromOffset(20, row), ZIndex = 9 })
		end
		if party then
			words(face, "Party", "Parties don't go in together yet: you go in on your own.", 18, 20, row + 44, -40, 26)
		end
		local b = api.button(face, "TRAIN", KC.Green, { Name = "Train", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -20), Size = UDim2.fromOffset(240, 62), ZIndex = 10 })
		b.Activated:Connect(function()
			task.spawn(trainNow)
		end)
		return face
	end
	local fc = K.chip(face, "FLOOR " .. f.id, KC.Ink, { Name = "FloorChip", Position = UDim2.fromOffset(20, y), ZIndex = 9 })
	if viewTier ~= "Normal" then
		K.chip(face, tierDef().name, tierDef().color, { Name = "TierChip", Position = UDim2.new(0, 20 + fc.Size.X.Offset + 10, 0, y), ZIndex = 9 })
	end
	local sc = STATE_CHIP[state]
	K.chip(face, sc[1], sc[2], { Name = "State", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, y), ZIndex = 9 })
	local name = words(face, "BossName", shown and f.boss or "Sealed", 46, 20, y + 42, -40, 104, { TextScaled = true })
	new("UITextSizeConstraint", { MaxTextSize = 46, MinTextSize = 22 }, name)
	words(face, "Area", shown and (f.area or "") or "", 26, 20, y + 150, -40, 32, { TextColor3 = KC.Yellow })
	-- the level it wants, and yours (under the blurb)
	local row = math.min(h - 150, y + 188 + 120)
	words(face, "Blurb", f.blurb or "", 21, 20, y + 188, -40, row - (y + 188) - 10)
	local lv = myLevel()
	local rec = K.chip(face, (Config.Spire.LevelLock and "NEEDS LV " or "RECOMMENDED LV ") .. levelFor(f), KC.Ink, { Name = "Recommended", Position = UDim2.fromOffset(20, row), ZIndex = 9 })
	K.chip(face, "YOU LV " .. lv, lv >= levelFor(f) and KC.Green or KC.Red, { Name = "You", Position = UDim2.new(0, 20 + rec.Size.X.Offset + 10, 0, row), ZIndex = 9 })
	-- and what's in the way, or who's coming
	local note = nil
	if state == "locked" then
		note = "Beat " .. tostring(lock) .. " first."
	elseif state == "sealed" then
		note = "This floor isn't open yet."
	elseif party and not party.leading then
		note = party.leader .. " (your party's leader) picks the floor."
	elseif party then
		note = "Your party of " .. party.count .. " comes with you."
	elseif state == "low" then
		note = "Too low! Train in the Colosseum first: it pays extra XP."
	elseif state == "level" then
		note = "Locked until Lv " .. levelFor(f) .. "! Train in the Colosseum to get there."
	end
	if note then
		words(face, "Note", note, 18, 20, row + 38, -40, 26)
	end
	-- the buttons
	local canGo = open and not (party and not party.leading)
	local label = canGo and "ENTER" or (state == "locked" and "LOCKED" or (state == "level" and ("LV " .. levelFor(f))) or (state == "sealed" and "SEALED" or "LEADER PICKS"))
	local enter = api.button(face, label, canGo and KC.Green or KC.Off, { Name = "Enter", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -20), Size = UDim2.fromOffset(240, 62), ZIndex = 10 })
	enter.Active = canGo
	if state == "locked" then
		K.icon(face, "Lock", { Name = "Lock", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -270, 1, -20), Size = UDim2.fromOffset(62, 62), ZIndex = 10 })
	end
	enter.Activated:Connect(function()
		if not canGo then
			return
		end
		Menus.close()
		task.spawn(travel, "enter", f.id, viewTier ~= "Normal" and viewTier or nil)
	end)
	if state == "low" or state == "level" then
		local train = api.button(face, "TRAIN FIRST", KC.Gold, { Name = "TrainFirst", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -276, 1, -20), Size = UDim2.fromOffset(240, 62), ZIndex = 10 })
		train.Activated:Connect(function()
			task.spawn(trainNow)
		end)
	end
	return face
end

-- THE FLOORS, as cards (the ground floor first): tap one to look at it
local CARD_W, CARD_H, CARD_GAP = 196, 128, 12
local function drawCards(holder, across, api)
	new("UIGridLayout", { CellSize = UDim2.fromOffset(CARD_W, CARD_H), CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP), SortOrder = Enum.SortOrder.LayoutOrder }, holder)
	local function card(id, top, name, sub, color, chip, chipColor, locked)
		local face = K.card(holder, { Name = id == 0 and "GroundFloor" or ("Floor" .. id), LayoutOrder = id, ZIndex = 7 }, color)
		local bar = new("Frame", { Name = "Bar", BackgroundColor3 = KC.Ink, BackgroundTransparency = 0.35, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 30), ZIndex = 8 }, face)
		K.label(bar, { Text = top, Font = K.TITLE_FONT, TextScaled = false, TextSize = 13, TextColor3 = KC.White, TextStrokeTransparency = 0, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -44, 1, 0), ZIndex = 9 })
		if locked then
			-- locked: the card dimmed, a big padlock over it
			new("Frame", { Name = "Dim", BackgroundColor3 = KC.Ink, BackgroundTransparency = 0.45, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 10 }, face)
			K.icon(face, "Lock", { Name = "Lock", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 4), Size = UDim2.fromOffset(56, 56), ZIndex = 11 })
		end
		K.big(face, { Name = "Boss", Text = name, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(10, 36), Size = UDim2.new(1, -20, 0, 30), ZIndex = 9 })
		K.big(face, { Name = "Area", Text = sub, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(10, 68), Size = UDim2.new(1, -20, 0, 18), ZIndex = 9, Edge = 2 })
		if chip then
			K.chip(face, chip, chipColor, { Name = "State", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -8), ZIndex = 9 })
		end
		if selected == id then
			-- (the one picked: a thick yellow edge)
			local edge = face:FindFirstChildOfClass("UIStroke")
			if edge then
				edge.Color = KC.Yellow
				edge.Thickness = 5
			end
			face:SetAttribute("Picked", true)
		end
		local tap = new("TextButton", { Name = "Tap", Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 12 }, face)
		tap.Activated:Connect(function()
			if selected ~= id then
				selected = id
				Menus.redraw()
			end
		end)
	end
	local bonus = Config.colosseumCatchUp(myLevel(), Config.spireCleared(player))
	local pct = math.floor(bonus * 100 + 0.5)
	card(0, "GROUND FLOOR", "The Colosseum", "Training", KC.Orange, pct > 0 and ("+" .. pct .. "% XP") or "TRAIN", pct > 0 and KC.Green or KC.Blue, false)
	for _, f in ipairs(Config.Spire.Floors) do
		local state = floorState(f)
		local reach = state ~= "sealed" and state ~= "locked" and state ~= "level"
		local chip, chipColor = nil, nil
		if state == "beaten" then
			chip, chipColor = "BEATEN", KC.Green
		elseif state == "level" then
			chip, chipColor = "LV " .. levelFor(f), KC.Red -- (the level it opens at)
		elseif reach then
			chip, chipColor = "LV " .. levelFor(f), state == "low" and KC.Red or KC.Pink
		else
			chip, chipColor = "LV " .. levelFor(f), KC.Slate
		end
		card(f.id, "FLOOR " .. f.id, f.open and shortName(f) or "Sealed", f.open and (f.area or "") or "", reach and f.color or KC.Well, chip, chipColor, not reach)
	end
end

Menus.define("Spire", {
	Title = "The Spire",
	Color = KC.Pink,
	-- a tab for each Spire: Normal, then the harder tiers
	Tabs = {
		{ Key = "Normal", Label = "Normal", Icon = "Spire" },
		{ Key = "Nightmare", Label = "Nightmare", Icon = "Bolt" },
		{ Key = "Eclipse", Label = "Eclipse", Icon = "BossRush" },
		{ Key = "Doom", Label = "Doom", Icon = "Bosses" },
	},
	render = function(page, tab, api)
		viewTier = Config.spireTier(tab).id
		local t = tierDef()
		local beaten = math.min(clearedUpTo(), #Config.Spire.Floors)
		if t.id == "Normal" then
			api.section("Choose a floor", beaten .. " / " .. #Config.Spire.Floors .. " beaten")
		else
			api.section(t.name .. " · Lv " .. Config.spireLevel(1, t.id) .. "-" .. Config.spireLevel(#Config.Spire.Floors, t.id), beaten .. " / " .. #Config.Spire.Floors .. " beaten")
			local open = Config.spireTierOpen(Config.spireCleared(player), t.id) or devSkip()
			local _, i = Config.spireTier(t.id)
			local before = Config.Spire.Tiers[i - 1]
			api.words((t.blurb or "") .. (open and "" or ("  Beat the whole Spire on " .. before.name .. " to open it.")), 30, open and KC.White or KC.Yellow)
		end
		local count = #Config.Spire.Floors + 1
		local across = 3
		local cardsW = across * CARD_W + (across - 1) * CARD_GAP
		local rows = math.ceil(count / across)
		local cardsH = rows * CARD_H + (rows - 1) * CARD_GAP
		if api.width >= cardsW + 24 + 520 then
			-- wide: the cards on the left, the picked floor on the right
			local block = api.block(cardsH + 10)
			local cards = new("Frame", { Name = "Floors", BackgroundTransparency = 1, Size = UDim2.fromOffset(cardsW, cardsH), ZIndex = 6 }, block)
			drawCards(cards, across, api)
			local side = new("Frame", { Name = "Picked", BackgroundTransparency = 1, Position = UDim2.fromOffset(cardsW + 24, 0), Size = UDim2.fromOffset(math.min(760, api.width - cardsW - 24 - 6), cardsH), ZIndex = 6 }, block)
			drawDetail(side, side.Size.X.Offset, cardsH, api)
		else
			-- narrow: the picked floor on top, the cards under it
			local block = api.block(470)
			drawDetail(block, math.min(760, api.width - 6), 460, api)
			across = math.max(1, math.floor((api.width + CARD_GAP) / (CARD_W + CARD_GAP)))
			rows = math.ceil(count / across)
			local cards = api.block(rows * (CARD_H + CARD_GAP))
			cards.Name = "Floors"
			drawCards(cards, across, api)
		end
	end,
})

-- (it follows what you've beaten, your party and your level while it's open)
local function redrawSpire()
	if Menus.current() == "Spire" then
		Menus.redraw()
	end
end
for _, t in ipairs(Config.Spire.Tiers) do
	player:GetAttributeChangedSignal(Config.spireClearedKey(t.id)):Connect(redrawSpire)
end
local function watchParty(p)
	p:GetAttributeChangedSignal("PartyLeader"):Connect(redrawSpire)
end
for _, p in ipairs(Players:GetPlayers()) do
	watchParty(p)
end
Players.PlayerAdded:Connect(watchParty)

local function openMenu()
	if travelling then
		return
	end
	-- (it opens on the boss you're up to: the next one not beaten, on the
	-- lowest tier not finished - or Doom's top floor once everything is)
	local nextF = Config.nextSpireFloor(Config.spireCleared(player))
	viewTier = nextF and nextF.tier or (nextF and "Normal") or "Doom"
	local upTo = nextF and nextF.id or #Config.Spire.Floors
	while upTo > 1 and not Config.Spire.Floors[upTo].open do
		upTo = upTo - 1
	end
	selected = upTo
	-- (the new player path sends you to the Colosseum first: it opens there)
	local pathStep = player:GetAttribute("PathStep")
	if pathStep == "Colosseum" or pathStep == "Clear" then
		selected = 0
	end
	Menus.open("Spire", viewTier)
end
local function closeMenu()
	if Menus.current() == "Spire" then
		Menus.close()
	end
end
-- into the Colosseum (its own quick fade takes you there: LobbyActivities)
trainNow = function()
	closeMenu()
	if travelling then
		return
	end
	travelling = true
	local ok, success, reason = pcall(function()
		return SpireTravel:InvokeServer("colosseum")
	end)
	travelling = false
	if not (ok and success) then
		showMessage(ok and (reason or "You can't go in right now.") or "Something went wrong.")
	end
end
-- (the lobby's goal card has a FIGHT! button for the new player path: it
-- fires ReplicatedStorage.ColosseumGo, no walk to the Spire's doors needed)
do
	local go = ReplicatedStorage:FindFirstChild("ColosseumGo")
	if not go then
		go = Instance.new("BindableEvent")
		go.Name = "ColosseumGo"
		go.Parent = ReplicatedStorage
	end
	go.Event:Connect(function()
		task.spawn(trainNow)
	end)
end

----------------------------------------------------------------------
-- In the arena: a Leave button, and a check at the fog gate (in the new
-- look: its own screen, which RetroUI leaves alone)
----------------------------------------------------------------------
local oldWindows = playerGui:FindFirstChild("SpireWindows")
if oldWindows then
	oldWindows:Destroy()
end
local winGui = create("ScreenGui", {
	Name = "SpireWindows",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 21,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})
winGui:SetAttribute("RetroSkip", true)
local winRoot = create("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = winGui })
local winScale = create("UIScale", { Parent = winRoot })
local function fitWindows()
	winScale.Scale = uiScale.Scale
	winRoot.Size = root.Size
end
fitWindows()
uiScale:GetPropertyChangedSignal("Scale"):Connect(fitWindows)

local confirm, confirmHolder = K.card(winRoot, {
	Name = "ConfirmLeave",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(520, 240),
	Visible = false,
	ZIndex = 55,
}, KC.Paper)
local confirmBar = new("Frame", { Name = "Bar", BackgroundColor3 = KC.Pink, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 46), ZIndex = 57 }, confirm)
new("Frame", { BackgroundColor3 = KC.Ink, BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 3), ZIndex = 57 }, confirmBar)
K.label(confirmBar, { Name = "Title", Text = "LEAVE THE ARENA?", Font = K.TITLE_FONT, TextScaled = false, TextSize = 18, TextColor3 = KC.White, TextStrokeTransparency = 0, Size = UDim2.fromScale(1, 1), ZIndex = 58 })
local confirmText = K.label(confirm, {
	Name = "Words",
	Position = UDim2.fromOffset(24, 62),
	Size = UDim2.new(1, -48, 0, 70),
	Text = "Leave the arena and return to the Spire's doors?",
	TextScaled = false,
	TextSize = 24,
	TextWrapped = true,
	ZIndex = 58,
})
local yesBtn = K.button(confirm, "LEAVE", KC.Red, { Name = "Leave", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0.5, 10, 1, -22), Size = UDim2.fromOffset(200, 56), ZIndex = 59 })
local noBtn = K.button(confirm, "STAY", KC.Slate, { Name = "Stay", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(0.5, -10, 1, -22), Size = UDim2.fromOffset(200, 56), ZIndex = 59 })
local function showConfirm(on)
	confirmHolder.Visible = on
end

-- (the boss of your arena is awake: you can't walk out on a fight - your own
-- copy of the floor's arena: ReplicatedStorage/Arenas)
local function fightOn(floorId)
	for _, boss in ipairs(game:GetService("CollectionService"):GetTagged("Boss")) do
		local state = boss:GetAttribute("State")
		if boss:GetAttribute("Floor") == floorId and Arenas.isMine(player, boss)
			and (state == "Waking" or state == "Fighting" or state == "Transition") then
			return true
		end
	end
	return false
end

local function askLeave()
	if travelling or not player:GetAttribute("SpireFloor") then
		return
	end
	if fightOn(player:GetAttribute("SpireFloor")) then
		showMessage("You can't leave in the middle of a fight!")
		return
	end
	local f = Config.Spire.Floors[player:GetAttribute("SpireFloor")]
	confirmText.Text = "Leave " .. (f and f.area or "the arena") .. " and return to the Spire's doors?"
	showConfirm(true)
end
yesBtn.Activated:Connect(function()
	showConfirm(false)
	task.spawn(travel, "leave")
end)
noBtn.Activated:Connect(function()
	showConfirm(false)
end)

local leaveBtn = K.button(winRoot, "LEAVE ARENA", KC.Slate, {
	Name = "LeaveArena",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 118),
	Size = UDim2.fromOffset(230, 48),
	Visible = false,
	ZIndex = 40,
})
leaveBtn.Activated:Connect(askLeave)

-- (shown in the arena only while there's no fight on: it would sit on the
-- boss's health bar, and you can't leave mid-fight anyway - it comes back
-- once the boss is beaten or asleep again)
local function onFloorChanged()
	local floorId = player:GetAttribute("SpireFloor")
	local inArena = floorId ~= nil
	leaveBtn.Visible = inArena and not fightOn(floorId)
	if not inArena then
		showConfirm(false)
	end
end
player:GetAttributeChangedSignal("SpireFloor"):Connect(onFloorChanged)
onFloorChanged()
task.spawn(function()
	while true do
		task.wait(0.25)
		onFloorChanged()
	end
end)

----------------------------------------------------------------------
-- Messages from the server
----------------------------------------------------------------------
SpireEvent.OnClientEvent:Connect(function(kind, a, b)
	if kind == "OpenMenu" then
		openMenu()
	elseif kind == "Arrived" then
		local sub = nil
		if b then
			sub = b
		end
		arrivedInfo = { area = a or "", sub = sub }
		if not travelling then
			showTitle(arrivedInfo.area, arrivedInfo.sub)
		end
	elseif kind == "ConfirmLeave" then
		askLeave()
	elseif kind == "Message" and type(a) == "string" then
		showMessage(a)
	end
end)

-- Escape / B closes the "Leave?" check (Esc closes the menu itself: Menus)
UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
		if confirmHolder.Visible then
			showConfirm(false)
		elseif input.KeyCode == Enum.KeyCode.ButtonB then
			closeMenu()
		end
	end
end)

----------------------------------------------------------------------
-- Open by walking up (like the shops)
----------------------------------------------------------------------
-- The mat at the Spire's doors and the fog gate in the arena each have an
-- invisible "AutoOpenZone" box (made by LobbyBuilder). Step in and the menu
-- (or the "Leave?" check) pops up; step out and it goes away. Close it
-- yourself and it stays closed until you step out and back in.
local zones = {}
local function addZone(z)
	if z:IsA("BasePart") and z:GetAttribute("Spire") then
		zones[z] = z:GetAttribute("Spire")
	end
end
for _, z in ipairs(CollectionService:GetTagged("AutoOpenZone")) do
	addZone(z)
end
CollectionService:GetInstanceAddedSignal("AutoOpenZone"):Connect(addZone)
CollectionService:GetInstanceRemovedSignal("AutoOpenZone"):Connect(function(z)
	zones[z] = nil
end)
-- the old "press E" prompts aren't needed any more
local function hidePrompt(prompt)
	if prompt:IsA("ProximityPrompt") then
		prompt.Enabled = false
	end
end
for _, tag in ipairs({ "SpireEntrance", "ArenaExit" }) do
	for _, pr in ipairs(CollectionService:GetTagged(tag)) do
		hidePrompt(pr)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(hidePrompt)
end

local function inside(zone, pos, margin)
	local rel = zone.CFrame:PointToObjectSpace(pos)
	local half = zone.Size / 2
	return math.abs(rel.X) <= half.X + margin and math.abs(rel.Y) <= half.Y + margin and math.abs(rel.Z) <= half.Z + margin
end
local function isShown(kind)
	if kind == "Menu" then
		return Menus.current() == "Spire"
	end
	return confirmHolder.Visible
end

local activeKind = nil -- what walking in opened
local dismissedKind = nil
local lastCheck = 0
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now - lastCheck < 0.1 or travelling then
		return
	end
	lastCheck = now
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local here = nil
	for zone, kind in pairs(zones) do
		-- (once it's open - or closed by hand - you have to walk clearly away,
		-- 5 studs past the box, before it counts as leaving: no flicker at the edge)
		local margin = (kind == activeKind or kind == dismissedKind) and 5 or 0
		if zone.Parent and inside(zone, hrp.Position, margin) then
			here = kind
			break
		end
	end
	if here then
		if activeKind == here and not isShown(here) then
			dismissedKind = here -- closed by hand
			activeKind = nil
		elseif activeKind ~= here and dismissedKind ~= here then
			if here == "Menu" then
				openMenu()
			else
				askLeave()
			end
			if isShown(here) then
				activeKind = here
			end
		end
	else
		if activeKind == "Menu" and isShown("Menu") then
			closeMenu()
		elseif activeKind == "Leave" and confirmHolder.Visible then
			showConfirm(false)
		end
		activeKind = nil
		dismissedKind = nil
	end
end)
