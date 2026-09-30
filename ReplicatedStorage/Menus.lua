--[[
	Menus  (ModuleScript, parent: ReplicatedStorage, name: "Menus")

	THE NEW GUI's MENUS, on your screen (Previews/gui_windows_sketch.html).
	See-through: the world blurs and dims behind, and the menu floats over it
	- a big title top left, its tabs down the left side, your money top right
	and a red X. One menu at a time; Esc closes it, and so does going into a
	fight. Every client script that has a menu defines it here, so they all
	share one screen:

	  Menus.define(name, def)    a menu. def = {
	                                Title = "Shop", Color = WindowKit colour,
	                                Tabs = { { Key = "Featured", Label = "Featured", Icon = "Featured" }, ... },
	                                render = function(page, tab, api) ... end,
	                                        -- draws tab `tab` into `page` (a
	                                        -- scrolling frame, emptied first)
	                                tick = function(dt, api) ... end (optional,
	                                        4 times a second while it's open),
	                             }
	  Menus.open(name, tab)      open a menu (at a tab); false if it can't be
	  Menus.close()
	  Menus.current()            the open menu's name and tab (or nil)
	  Menus.go(name, tab)        open a menu, or one of the older windows
	                             other scripts open themselves:
	  Menus.external[name] = fn(tab)   (Gear, Weapons, Stats, Arcade)
	  Menus.state                the latest save snapshot (StateUpdate)
	  Menus.onState(fn)          fn(state) with every snapshot
	  Menus.act(name, arg, done) ask the server (the Action remote); shows its
	                             answer, then done(ok, msg) if given
	  Menus.toast(text, kind)    a message at the top of the screen
	  Menus.redraw()             draw the open menu again

	The api a menu's render gets: { state, act, toast, go, close, redraw,
	width (the page's width in pixels), K (WindowKit), Config, tab } and the
	page helpers, each adding the next thing down the page: section(text,
	sub), block(height), grid(count, cellW, cellH, gap), words(text, height),
	button(parent, text, color, props).
	While a menu is open the player has the attribute MenuOpen = its name
	(on this screen only): the lobby's buttons hide, and the server's
	messages show here instead of behind the veil.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local K = require(ReplicatedStorage:WaitForChild("WindowKit"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local C = K.COLORS

local Menus = {}
Menus.defs = {}
Menus.external = {}
Menus.state = nil

local player = Players.LocalPlayer
local listeners = {}
local gui, root, toastHost, page, titleLabel, tabsHost, coinText, tokenText
local openName, openTab = nil, nil
local scale = 1
local RAIL, TOP, SIDE, MONEY_W = 96, 120, 36, 230

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

-- on in a Spire arena, in the Colosseum, and in the intro: no menus then
local function inFight()
	return player:GetAttribute("SpireFloor") ~= nil or player:GetAttribute("Colosseum") == true or player:GetAttribute("Intro") ~= nil
end

----------------------------------------------------------------------
-- toasts (the top of the screen, above the veil)
----------------------------------------------------------------------
local function ensureGui()
	if gui and gui.Parent then
		return
	end
	local playerGui = player:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild("Menus")
	if old then
		old:Destroy()
	end
	gui = new("ScreenGui", {
		Name = "Menus",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 30,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	gui:SetAttribute("RetroSkip", true) -- (RetroUI leaves the new look alone)
	root = new("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false }, gui)
	local uiScale = new("UIScale", {}, root)
	toastHost = new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 24),
		Size = UDim2.fromOffset(760, 200),
		BackgroundTransparency = 1,
		ZIndex = 60,
	}, gui)
	new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, toastHost)
	local toastScale = new("UIScale", {}, toastHost)
	local function fit()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		scale = math.clamp(cam.ViewportSize.Y / 1000, 0.5, 1.1)
		uiScale.Scale = scale
		toastScale.Scale = scale
		root.Size = UDim2.fromScale(1 / scale, 1 / scale)
	end
	fit()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			fit()
			if openName then
				Menus.redraw()
			end
		end)
	end

	-- the veil: the world dimmed (and blurred: Lighting's MenuBlur)
	new("Frame", { Name = "Veil", BackgroundColor3 = C.Ink, BackgroundTransparency = 0.45, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Active = true }, root)
	-- the title, big, top left (just right of the tabs)
	titleLabel = K.big(root, {
		Name = "Title",
		Text = "",
		TextScaled = false,
		TextSize = 64,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(SIDE + RAIL + 28, 26),
		Size = UDim2.fromOffset(700, 70),
		ZIndex = 5,
		Edge = 4,
	})
	-- the tabs down the left side
	tabsHost = new("Frame", { Name = "Tabs", BackgroundTransparency = 1, Position = UDim2.fromOffset(SIDE, TOP), Size = UDim2.new(0, RAIL + 10, 1, -TOP - 20), ZIndex = 5 }, root)
	new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, tabsHost)
	-- your money, top right (the token's + goes to the shop's tokens)
	local money = new("Frame", { Name = "Money", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 28), Size = UDim2.fromOffset(MONEY_W, 120), ZIndex = 5 }, root)
	new("UIListLayout", { Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder }, money)
	local function moneyRow(kind, order)
		local row = new("Frame", { Name = kind, BackgroundTransparency = 1, Size = UDim2.fromOffset(MONEY_W, 48), LayoutOrder = order, ZIndex = 5 }, money)
		local t = K.big(row, { Name = "Amount", Text = "0", TextScaled = false, TextSize = 36, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, -56, 1, 0), ZIndex = 6 })
		local pic = (kind == "Coins" and K.coin or K.token)(row, 44, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), ZIndex = 6 })
		pic.Name = kind == "Coins" and "Coin" or "Token"
		return t, row
	end
	coinText = moneyRow("Coins", 1)
	local tokenRow
	tokenText, tokenRow = moneyRow("Tokens", 2)
	tokenText.Size = UDim2.new(1, -104, 1, 0)
	local plus = K.button(tokenRow, "+", C.Pink, { Name = "Plus", Font = K.FONT, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -54, 0.5, 0), Size = UDim2.fromOffset(40, 40), ZIndex = 7 })
	plus.Activated:Connect(function()
		Menus.go("Shop", "Tokens")
	end)
	-- the red X, top right of the page
	local x = K.x(root, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24 - MONEY_W - 24, 0, 30), Size = UDim2.fromOffset(60, 60), ZIndex = 8 })
	x.Activated:Connect(function()
		Menus.close()
	end)
	-- the page: everything below the title, right of the tabs
	page = new("ScrollingFrame", {
		Name = "Page",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(SIDE + RAIL + 28, TOP),
		Size = UDim2.new(1, -(SIDE + RAIL + 28) - 24 - MONEY_W - 24, 1, -TOP - 24),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = C.White,
		ZIndex = 5,
	}, root)
	gui.Parent = playerGui
end

local toastOrder = 0
function Menus.toast(text, kind)
	if type(text) ~= "string" or text == "" then
		return
	end
	ensureGui()
	toastOrder = toastOrder + 1
	local color = C.Green
	if kind == "bad" then
		color = C.Red
	elseif kind == "info" then
		color = C.Blue
	elseif kind == "rare" then
		color = C.Gold
	end
	local t = new("TextLabel", {
		Name = "Toast",
		LayoutOrder = toastOrder,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = color,
		Font = K.FONT,
		Text = text,
		TextColor3 = C.White,
		TextSize = 24,
		TextStrokeTransparency = 0.3,
		ZIndex = 61,
	}, toastHost)
	K.outline(t, C.Ink, 3)
	new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, t)
	local live = {}
	for _, c in ipairs(toastHost:GetChildren()) do
		if c:IsA("TextLabel") then
			table.insert(live, c)
		end
	end
	if #live > 3 then
		table.sort(live, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		live[1]:Destroy()
	end
	task.delay(kind == "rare" and 4.5 or 2.6, function()
		if t.Parent then
			t:Destroy()
		end
	end)
end

----------------------------------------------------------------------
-- asking the server
----------------------------------------------------------------------
function Menus.act(name, arg, done)
	task.spawn(function()
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local action = remotes and remotes:FindFirstChild("Action")
		local ok, success, msg = false, false, nil
		if action then
			ok, success, msg = pcall(function()
				return action:InvokeServer(name, arg)
			end)
		end
		if not ok then
			Menus.toast("Couldn't reach the server.", "bad")
			success, msg = false, nil
		elseif type(msg) == "string" then
			Menus.toast(msg, success and "good" or "bad")
		end
		if done then
			done(success, msg)
		end
	end)
end

----------------------------------------------------------------------
-- drawing the open menu
----------------------------------------------------------------------
local function money()
	local s = Menus.state
	if coinText and s then
		coinText.Text = Config.format(tonumber(s.Coins) or 0)
		tokenText.Text = tostring(tonumber(s.Tokens) or 0)
	end
end

-- the page's width, in the menus' pixels (the screen's width over its scale)
function Menus.pageWidth()
	local cam = workspace.CurrentCamera
	local w = cam and cam.ViewportSize.X / scale or 1600
	return math.max(420, w - (SIDE + RAIL + 28) - 24 - MONEY_W - 24 - 24)
end

local function api()
	local a = {
		state = Menus.state,
		act = Menus.act,
		toast = Menus.toast,
		go = Menus.go,
		close = Menus.close,
		redraw = Menus.redraw,
		width = Menus.pageWidth() - 24,
		K = K,
		Config = Config,
		tab = openTab,
	}
	-- PAGE HELPERS: each adds the next thing down the page (in order)
	local order = 0
	local function nextOrder()
		order = order + 1
		return order
	end
	-- a heading in big white words, with small words beside it
	function a.section(text, sub)
		local f = new("Frame", { Name = "Section", BackgroundTransparency = 1, Size = UDim2.fromOffset(a.width, 44), LayoutOrder = nextOrder(), ZIndex = 6 }, page)
		K.big(f, { Name = "Heading", Text = text, TextScaled = false, TextSize = 32, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 40), ZIndex = 7 })
		if sub then
			K.big(f, { Name = "Sub", Text = sub, TextScaled = false, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.new(1, 0, 0, 40), ZIndex = 7, Edge = 2 })
		end
		new("Frame", { Name = "Rule", BackgroundColor3 = C.White, BackgroundTransparency = 0.65, BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, -3), Size = UDim2.new(1, 0, 0, 3), ZIndex = 6 }, f)
		return f
	end
	-- a see-through strip the width of the page, `height` tall, for anything
	function a.block(height)
		return new("Frame", { Name = "Block", BackgroundTransparency = 1, Size = UDim2.fromOffset(a.width, height), LayoutOrder = nextOrder(), ZIndex = 6 }, page)
	end
	-- a grid for `count` cells of cellW x cellH (as many across as fit);
	-- returns the frame to put the cells in (each is laid out in order)
	function a.grid(count, cellW, cellH, gap)
		gap = gap or 14
		local across = math.max(1, math.floor((a.width + gap) / (cellW + gap)))
		local rows = math.max(1, math.ceil(count / across))
		local f = new("Frame", { Name = "Grid", BackgroundTransparency = 1, Size = UDim2.fromOffset(a.width, rows * (cellH + gap)), LayoutOrder = nextOrder(), ZIndex = 6 }, page)
		new("UIGridLayout", { CellSize = UDim2.fromOffset(cellW, cellH), CellPadding = UDim2.fromOffset(gap, gap), SortOrder = Enum.SortOrder.LayoutOrder }, f)
		return f, across
	end
	-- words on the page (wrapped), `height` tall
	function a.words(text, height, color)
		local f = a.block(height or 30)
		K.big(f, { Name = "Words", Text = text, TextScaled = false, TextSize = 20, TextWrapped = true, TextColor3 = color or C.White, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.fromScale(1, 1), ZIndex = 7, Edge = 2 })
		return f
	end
	-- a chunky button in the round font (Font = FredokaOne), with its shadow
	function a.button(parent, text, color, props)
		local b = K.button(parent, text, color, props)
		b.Font = K.FONT
		return b
	end
	return a
end

function Menus.redraw()
	local def = openName and Menus.defs[openName]
	if not def or not page then
		return
	end
	titleLabel.Text = def.Title or openName
	money()
	-- the tabs
	for _, c in ipairs(tabsHost:GetChildren()) do
		if not c:IsA("UIListLayout") then
			c:Destroy()
		end
	end
	for i, t in ipairs(def.Tabs or {}) do
		local b = K.tab(tabsHost, t.Icon or t.Key, t.Label or t.Key, { LayoutOrder = i, ZIndex = 6 })
		b.Name = "Tab_" .. t.Key
		K.tabOn(b, t.Key == openTab)
		b.Activated:Connect(function()
			if openTab ~= t.Key then
				openTab = t.Key
				page.CanvasPosition = Vector2.new()
				Menus.redraw()
			end
		end)
	end
	-- the page (kept where it was scrolled to)
	local scroll = page.CanvasPosition
	for _, c in ipairs(page:GetChildren()) do
		c:Destroy()
	end
	new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 24), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 16) }, page)
	new("UIListLayout", { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, page)
	local ok, err = pcall(def.render, page, openTab, api())
	if not ok then
		warn("[Menus] " .. tostring(openName) .. " couldn't be drawn: " .. tostring(err))
	end
	page.CanvasPosition = scroll
end

local blur = nil
local function setBlur(on)
	if on then
		if not blur or not blur.Parent then
			blur = Lighting:FindFirstChild("MenuBlur") or new("BlurEffect", { Name = "MenuBlur", Size = 0 }, Lighting)
		end
		TweenService:Create(blur, TweenInfo.new(0.2), { Size = 14 }):Play()
	elseif blur and blur.Parent then
		local b = blur
		blur = nil
		b:Destroy()
	end
end

function Menus.current()
	return openName, openTab
end

function Menus.open(name, tab)
	local def = Menus.defs[name]
	if not def then
		return false
	end
	if inFight() then
		Menus.toast("Not now - you're in a fight!", "bad")
		return false
	end
	ensureGui()
	local first = def.Tabs and def.Tabs[1] and def.Tabs[1].Key or nil
	local valid = false
	for _, t in ipairs(def.Tabs or {}) do
		valid = valid or t.Key == tab
	end
	local wasOpen = openName
	openName, openTab = name, valid and tab or first
	root.Visible = true
	if not wasOpen then
		setBlur(true)
	end
	page.CanvasPosition = Vector2.new()
	player:SetAttribute("MenuOpen", name)
	Menus.redraw()
	if def.opened then
		pcall(def.opened, api())
	end
	return true
end

function Menus.close()
	if not openName then
		return
	end
	local def = Menus.defs[openName]
	openName, openTab = nil, nil
	if root then
		root.Visible = false
	end
	setBlur(false)
	player:SetAttribute("MenuOpen", nil)
	if def and def.closed then
		pcall(def.closed)
	end
end

function Menus.define(name, def)
	Menus.defs[name] = def
end

-- a menu here, or an older window another script opens itself
function Menus.go(name, tab)
	if Menus.defs[name] then
		return Menus.open(name, tab)
	end
	local fn = Menus.external[name]
	if fn then
		Menus.close()
		task.spawn(fn, tab)
		return true
	end
	Menus.toast("Coming soon!", "info")
	return false
end

function Menus.onState(fn)
	table.insert(listeners, fn)
	if Menus.state then
		task.spawn(fn, Menus.state)
	end
end

----------------------------------------------------------------------
-- listening
----------------------------------------------------------------------
local started = false
local function start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
		if not remotes then
			return
		end
		local update = remotes:WaitForChild("StateUpdate", 30)
		if not update then
			return
		end
		update.OnClientEvent:Connect(function(data)
			Menus.state = data
			for _, fn in ipairs(listeners) do
				task.spawn(fn, data)
			end
			if openName then
				Menus.redraw()
			end
		end)
		-- (the server's messages show here while a menu covers the lobby's)
		local notify = remotes:WaitForChild("Notify", 30)
		if notify then
			notify.OnClientEvent:Connect(function(text, kind)
				if openName then
					Menus.toast(text, kind)
				end
			end)
		end
		local req = remotes:FindFirstChild("RequestState")
		if req then
			req:FireServer()
		end
	end)
	-- a fight starting closes the menu
	for _, attr in ipairs({ "SpireFloor", "Colosseum", "Intro" }) do
		player:GetAttributeChangedSignal(attr):Connect(function()
			if inFight() then
				Menus.close()
			end
		end)
	end
	-- passes, VIP and the like change what the shop shows
	player.AttributeChanged:Connect(function(attr)
		if openName and (string.sub(attr, 1, 5) == "Pass_" or attr == "VIP" or attr == "NoPaidRandom") then
			Menus.redraw()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.Escape and openName then
			Menus.close()
		end
	end)
	-- the menus' clocks (the free gift, the shop's refresh)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		if acc < 0.25 then
			return
		end
		local step = acc
		acc = 0
		local def = openName and Menus.defs[openName]
		if def and def.tick then
			local ok, err = pcall(def.tick, step, api())
			if not ok then
				warn("[Menus] tick: " .. tostring(err))
			end
		end
	end)
end
if RunService.IsClient == nil or RunService:IsClient() then
	start()
end

return Menus
