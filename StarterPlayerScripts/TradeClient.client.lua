--[[
	TradeClient  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "TradeClient")

	TRADING on your screen, in the window look (ReplicatedStorage/WindowKit).
	The server decides everything (TradeService); this only shows it and asks.

	  * Sit at one of the lobby's picnic benches: alone, a little line says
	    you're waiting. When someone sits across from you, the trade window
	    opens for you both.
	  * The window: your side and theirs, each with up to 4 slots. Under them,
	    every weapon you can trade (its picture, name and rarity colour): tap
	    one to put it in, tap it in your slot to take it back. Their slots
	    change as they do.
	  * ACCEPT: each side shows when that player has accepted. When you both
	    have, "Trading in 3...2...1" - and any change to either side stops
	    it. CANCEL stops the trade and stands you up.
	  * After a trade: "Trade complete!" with what you got.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local K = require(ReplicatedStorage:WaitForChild("WindowKit"))
local Pictures = require(ReplicatedStorage:WaitForChild("Pictures")) -- (the uploaded pictures, fast)
local C = K.COLORS
local W = Config.Weapons
local TR = Config.Trade or { MaxSlots = 4 }

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Action = Remotes:WaitForChild("Action")
local TradeEvent = ReplicatedStorage:WaitForChild("TradeEvent")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local AssetIds = nil
pcall(function()
	AssetIds = require(ReplicatedStorage:WaitForChild("AssetIds", 5))
end)

local RANK = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5, Secret = 6 }

local trade = nil -- the trade as the server last showed it (nil: none)
local data = nil -- the latest snapshot of your data from the server
local endsAt = nil -- os.clock() when the countdown ends (nil: no countdown)
local UI = {} -- the screen's pieces

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
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

local function rarityColor(r)
	return (Config.Arcade and Config.Arcade.Colors and Config.Arcade.Colors[r]) or C.Slate
end

-- the weapon's picture (its icon once uploaded, else a stand-in)
local function picture(parent, id, size, props)
	local icons = type(AssetIds) == "table" and AssetIds.Icons or nil
	local n = icons and icons[id]
	local p
	if n then
		p = new("ImageLabel", { Name = "Picture", BackgroundTransparency = 1, Image = Pictures.url(n), ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromOffset(size, size) }, parent)
	else
		p = K.icon(parent, "Weapons", { Name = "Picture", Size = UDim2.fromOffset(size, size) })
	end
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	return p
end

-- asks the server (the Action remote); shows its answer on the status line
local function ask(name, arg)
	local ok, a, b = pcall(function()
		return Action:InvokeServer(name, arg)
	end)
	if not ok then
		a, b = false, "Couldn't reach the server."
	end
	if UI.status then
		UI.status.Text = type(b) == "string" and b or ""
		UI.status.TextColor3 = a and C.Green or C.Red
	end
	return a, b
end

----------------------------------------------------------------------
-- The screen
----------------------------------------------------------------------
local gui = new("ScreenGui", { Name = "Trade", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 44, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
gui:SetAttribute("RetroSkip", true)
local scaler = new("Frame", { Name = "Scaler", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)
local uiScale = new("UIScale", {}, scaler)
-- (smaller on a small screen: it always fits, on a phone too)
local function fit()
	local cam = Workspace.CurrentCamera
	if cam then
		local size = cam.ViewportSize
		local s = math.clamp(math.min(size.Y / 720, size.X / 980), 0.4, 1.1)
		uiScale.Scale = s
		scaler.Size = UDim2.fromScale(1 / s, 1 / s)
	end
end
fit()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
end

-- the little line while you sit and wait
-- (a small light card with a dark outline, not a big dark bar)
UI.hint = K.chip(scaler, "", C.White, {
	Name = "Hint",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -170),
	Size = UDim2.fromOffset(40, 34),
	Font = Enum.Font.FredokaOne,
	TextSize = 20,
	TextColor3 = C.Ink,
	TextStrokeTransparency = 1,
	Visible = false,
	ZIndex = 5,
})
new("UICorner", { CornerRadius = UDim.new(0, 8) }, UI.hint)
-- a short message (the trade stopped, a weapon came out of it)
UI.toast = K.big(scaler, { Name = "Toast", Text = "", TextScaled = false, TextSize = 28, TextWrapped = true, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 90), Size = UDim2.fromOffset(760, 70), Visible = false, ZIndex = 30 })
local toastId = 0
local function toast(text, color)
	toastId = toastId + 1
	local mine = toastId
	UI.toast.Text = text or ""
	UI.toast.TextColor3 = color or C.White
	UI.toast.Visible = text ~= nil and text ~= ""
	task.delay(4, function()
		if toastId == mine then
			UI.toast.Visible = false
		end
	end)
end

-- the window
do
	local SLOT_W, SLOT_H = 96, 120
	local parts = K.window(scaler, {
		Name = "TradeWindow",
		Title = "TRADE",
		Color = C.Orange,
		BarHeight = 44,
		Buttons = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(920, 660),
		Visible = false,
		ZIndex = 10,
	})
	UI.win, UI.title = parts.frame, parts.title
	local top = parts.top
	-- one side of the table: a panel with a coloured strip, its name, its
	-- ACCEPTED chip and four slots
	local function side(name, x, color)
		local p = K.panel(parts.frame, { Name = name, Position = UDim2.fromOffset(x, top + 14), Size = UDim2.fromOffset(430, 196), ZIndex = 12 }, color, 36)
		local who = K.label(p, { Name = "Who", Text = "", Font = K.TITLE_FONT, TextScaled = false, TextSize = 16, TextColor3 = C.White, TextStrokeTransparency = 0, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -150, 0, 36), ZIndex = 14 })
		local ready = K.chip(p, "NOT READY", C.Slate, { Name = "Ready", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0, 18), ZIndex = 14 })
		local slots = {}
		for i = 1, TR.MaxSlots do
			local s = new("TextButton", {
				Name = "Slot" .. i,
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = C.Sunken,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(12 + (i - 1) * (SLOT_W + 8), 48),
				Size = UDim2.fromOffset(SLOT_W, SLOT_H),
				ZIndex = 13,
			}, p)
			K.outline(s, C.Ink, 3)
			slots[i] = s
		end
		return { panel = p, who = who, ready = ready, slots = slots }
	end
	UI.mine = side("YourSide", 20, C.Blue)
	UI.theirs = side("TheirSide", 470, C.Pink)
	-- the countdown, big, between the sides and your weapons
	UI.count = K.big(parts.frame, { Name = "Countdown", Text = "", TextScaled = false, TextSize = 30, Position = UDim2.fromOffset(20, top + 214), Size = UDim2.new(1, -40, 0, 36), ZIndex = 14 })
	UI.pickLabel = K.label(parts.frame, { Name = "PickLabel", Text = "YOUR WEAPONS - tap one to put it in", Font = K.TITLE_FONT, TextScaled = false, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(24, top + 250), Size = UDim2.new(1, -48, 0, 22), ZIndex = 12 })
	UI.inventory = new("ScrollingFrame", {
		Name = "Inventory",
		BackgroundColor3 = C.Panel,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(20, top + 276),
		Size = UDim2.new(1, -40, 0, 250),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 10,
		ScrollBarImageColor3 = C.Ink,
		ZIndex = 12,
	}, parts.frame)
	K.outline(UI.inventory, C.Ink, 3)
	new("UIGridLayout", { CellSize = UDim2.fromOffset(120, 150), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder }, UI.inventory)
	new("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }, UI.inventory)
	UI.status = K.label(parts.frame, { Name = "Status", Text = "", TextScaled = false, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(24, 660 - 62), Size = UDim2.new(1, -440, 0, 44), TextWrapped = true, ZIndex = 12 })
	UI.accept = K.button(parts.frame, "ACCEPT", C.Green, { Name = "Accept", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -224, 1, -16), Size = UDim2.fromOffset(190, 54), ZIndex = 13 })
	UI.cancel = K.button(parts.frame, "CANCEL", C.Red, { Name = "Cancel", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -16), Size = UDim2.fromOffset(180, 54), ZIndex = 13 })
end

-- the window after a trade: what you got
do
	local parts = K.window(scaler, {
		Name = "TradeDone",
		Title = "TRADE COMPLETE!",
		Color = C.Green,
		BarHeight = 44,
		Buttons = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(620, 330),
		Visible = false,
		ZIndex = 20,
	})
	UI.done = parts.frame
	UI.doneWords = K.label(parts.frame, { Name = "Words", Text = "", TextScaled = false, TextSize = 22, TextWrapped = true, Position = UDim2.fromOffset(20, parts.top + 10), Size = UDim2.new(1, -40, 0, 30), ZIndex = 22 })
	UI.doneList = new("Frame", { Name = "Got", BackgroundTransparency = 1, Position = UDim2.fromOffset(20, parts.top + 46), Size = UDim2.new(1, -40, 0, 150), ZIndex = 22 }, parts.frame)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, UI.doneList)
	UI.doneOk = K.button(parts.frame, "OK", C.Green, { Name = "Ok", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(160, 50), ZIndex = 23 })
	UI.doneOk.Activated:Connect(function()
		UI.done.Visible = false
	end)
end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------
-- a weapon in a slot (or an empty slot)
local function fillSlot(slot, id)
	for _, c in ipairs(slot:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	slot:SetAttribute("Weapon", id)
	local def = id and W.List[id]
	if not def then
		slot.BackgroundColor3 = C.Sunken
		return
	end
	slot.BackgroundColor3 = rarityColor(def.Rarity)
	picture(slot, id, 70, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), ZIndex = 14 })
	K.big(slot, { Name = "WeaponName", Text = def.Name, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.new(1, -8, 0, 30), ZIndex = 15, Edge = 2 })
end

local function drawSide(s, list, ok, name)
	s.who.Text = name
	K.chipText(s.ready, ok and "ACCEPTED" or "NOT READY")
	s.ready.BackgroundColor3 = ok and C.Green or C.Slate
	for i, slot in ipairs(s.slots) do
		fillSlot(slot, list[i])
	end
end

-- every weapon you can put in (rarest first)
local function drawInventory()
	for _, c in ipairs(UI.inventory:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local own = data and type(data.Weapons) == "table" and type(data.Weapons.own) == "table" and data.Weapons.own or {}
	local offered = {}
	for _, id in ipairs(trade and trade.mine or {}) do
		offered[id] = true
	end
	local held = player:GetAttribute("Weapon")
	local ids = {}
	for id in pairs(own) do
		if Config.tradeable(id) then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a, b)
		local ra, rb = RANK[W.List[a].Rarity] or 0, RANK[W.List[b].Rarity] or 0
		if ra ~= rb then
			return ra > rb
		end
		return W.List[a].Name < W.List[b].Name
	end)
	if #ids == 0 then
		K.label(UI.inventory, { Name = "Empty", Text = "No weapons to trade yet - spin the Arcade's machines!", TextScaled = false, TextSize = 20, Size = UDim2.fromOffset(800, 40), ZIndex = 13 })
		return
	end
	for i, id in ipairs(ids) do
		local def = W.List[id]
		local face, holder = K.card(UI.inventory, { Name = id, LayoutOrder = i, ZIndex = 13 }, rarityColor(def.Rarity))
		K.label(face, { Name = "Rarity", Text = string.upper(def.Rarity), Font = K.TITLE_FONT, TextScaled = false, TextSize = 10, TextColor3 = C.White, TextStrokeTransparency = 0, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 0, 14), ZIndex = 15 })
		picture(face, id, 74, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 24), ZIndex = 15 })
		K.big(face, { Name = "WeaponName", Text = def.Name, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -10, 0, 30), ZIndex = 15, Edge = 2 })
		-- (in your hand, or in the trade already: shown, but dimmed with a tag)
		local tag = id == held and "IN HAND" or (offered[id] and "IN TRADE" or nil)
		if tag then
			new("Frame", { Name = "Dim", BackgroundColor3 = C.Ink, BackgroundTransparency = 0.45, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 16 }, face)
			K.chip(face, tag, id == held and C.Green or C.Violet, { Name = "Tag", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), ZIndex = 17 })
		end
		holder:SetAttribute("Weapon", id)
		local tap = new("TextButton", { Name = "Tap", Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 18 }, face)
		tap.Activated:Connect(function()
			if trade and not offered[id] then
				ask("TradeOffer", { trade = trade.id, weapon = id })
			end
		end)
	end
end

local function redraw()
	if not trade then
		return
	end
	UI.title.Text = "TRADE WITH " .. string.upper(tostring(trade.name))
	drawSide(UI.mine, trade.mine, trade.meOk, "YOU")
	drawSide(UI.theirs, trade.theirs, trade.themOk, string.upper(tostring(trade.name)))
	UI.accept.Text = trade.meOk and "UNDO" or "ACCEPT"
	UI.accept.BackgroundColor3 = trade.meOk and C.Slate or C.Green
	drawInventory()
end

-- taps on your own slots take that weapon back out
for _, slot in ipairs(UI.mine.slots) do
	slot.Activated:Connect(function()
		local id = slot:GetAttribute("Weapon")
		if trade and id then
			ask("TradeRemove", { trade = trade.id, weapon = id })
		end
	end)
end
UI.accept.Activated:Connect(function()
	if trade then
		ask("TradeAccept", { trade = trade.id, on = not trade.meOk })
	end
end)
UI.cancel.Activated:Connect(function()
	ask("TradeCancel", {})
end)

-- the countdown ticks down here (the server swaps when it's really over)
RunService.Heartbeat:Connect(function()
	if trade and endsAt then
		local left = math.max(1, math.ceil(endsAt - os.clock()))
		UI.count.Text = "Trading in " .. left .. "..."
	elseif trade then
		UI.count.Text = (trade.meOk and not trade.themOk) and ("Waiting for " .. tostring(trade.name) .. " to accept") or ""
	end
end)

----------------------------------------------------------------------
-- What the server says
----------------------------------------------------------------------
local function closeMenus()
	local ok, Menus = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Menus", 1))
	end)
	if ok and type(Menus) == "table" and Menus.current and Menus.current() then
		Menus.close()
	end
end

TradeEvent.OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "State" and type(a) == "table" then
		local opening = trade == nil or trade.id ~= a.id
		trade = a
		endsAt = type(a.countdown) == "number" and (os.clock() + a.countdown) or nil
		if opening then
			UI.status.Text = ""
			UI.done.Visible = false
			UI.hint.Visible = false
			closeMenus()
		end
		UI.win.Visible = true
		redraw()
	elseif kind == "Hint" then
		local text = type(a) == "string" and a or nil
		if text then
			K.chipText(UI.hint, text)
		end
		UI.hint.Visible = text ~= nil and trade == nil
	elseif kind == "Note" then
		toast(a, C.Yellow)
	elseif kind == "Closed" then
		trade, endsAt = nil, nil
		UI.win.Visible = false
		toast(a, C.White)
	elseif kind == "Done" then
		trade, endsAt = nil, nil
		UI.win.Visible = false
		local got = type(a) == "table" and a or {}
		local names = {}
		for _, c2 in ipairs(UI.doneList:GetChildren()) do
			if c2:IsA("GuiObject") then
				c2:Destroy()
			end
		end
		for i, id in ipairs(got) do
			local def = W.List[id]
			if def then
				table.insert(names, def.Name)
				local face = K.card(UI.doneList, { Name = id, LayoutOrder = i, Size = UDim2.fromOffset(120, 150), ZIndex = 22 }, rarityColor(def.Rarity))
				picture(face, id, 80, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), ZIndex = 24 })
				K.big(face, { Name = "WeaponName", Text = def.Name, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -10, 0, 30), ZIndex = 24, Edge = 2 })
			end
		end
		local from = tostring(c or "them")
		UI.doneWords.Text = #names > 0 and ("You got from " .. from .. ": " .. table.concat(names, ", ")) or ("You gave " .. from .. " a present!")
		UI.done.Visible = true
		toast("Trade complete! You got: " .. (#names > 0 and table.concat(names, ", ") or "nothing"), C.Green)
	end
end)

-- new data from the server, or a new weapon in your hand: draw it again
Remotes:WaitForChild("StateUpdate").OnClientEvent:Connect(function(d)
	data = d
	if trade then
		drawInventory()
	end
end)
player:GetAttributeChangedSignal("Weapon"):Connect(function()
	if trade then
		drawInventory()
	end
end)
local req = Remotes:FindFirstChild("RequestState")
if req then
	req:FireServer()
end
