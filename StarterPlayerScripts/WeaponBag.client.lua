--[[
	WeaponBag  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "WeaponBag")

	Your WEAPONS: every weapon you own, and which one is in your hand.

	  * The WEAPONS button (under STATS on the left, or press B) opens it.
	  * One card per weapon: its name and rarity colour, its type, its mastery
	    (level and a bar to the next one) and its ability. EQUIP puts it in
	    your hand; FISTS puts it away.

	The server owns everything (data.Weapons, the "EquipWeapon" action); this
	only shows it and asks. This becomes the BAG of the new screen later.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Action = Remotes:WaitForChild("Action")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local W = Config.Weapons

local RGB = Color3.fromRGB
local WHITE, INK = RGB(255, 255, 255), RGB(24, 20, 37)
local PANEL, CARD, CARD_HOLD = RGB(30, 20, 70), RGB(40, 32, 84), RGB(58, 46, 120)
local GREY, GOLD, GREEN, RED = RGB(205, 212, 232), RGB(254, 174, 52), RGB(99, 199, 77), RGB(228, 59, 68)
local FONT = Enum.Font.GothamBold

-- each rarity's colour (the Arcade Machine uses the same ones)
local RARITY = {
	Common = RGB(170, 175, 190),
	Uncommon = RGB(99, 199, 77),
	Rare = RGB(70, 160, 255),
	Epic = RGB(170, 90, 240),
	Legendary = RGB(254, 174, 52),
	Mythic = RGB(240, 60, 70),
	Secret = RGB(255, 255, 255), -- (drawn as a rainbow)
	Event = RGB(44, 232, 245),
}
local RARITY_ORDER = { Secret = 1, Mythic = 2, Event = 3, Legendary = 4, Epic = 5, Rare = 6, Uncommon = 7, Common = 8 }

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do
		i[k] = v
	end
	i.Parent = parent
	return i
end
local function tween(inst, t, props, style)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
local function text(parent, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = WHITE,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeColor3 = INK,
		TextStrokeTransparency = 0.5,
	}, parent)
	for k, v in pairs(props) do
		l[k] = v
	end
	return l
end
local function stroke(parent, color, thickness)
	return new("UIStroke", { Color = color or WHITE, Thickness = thickness or 3, LineJoinMode = Enum.LineJoinMode.Miter, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end
local function button(parent, label, color, props)
	local b = new("TextButton", { BackgroundColor3 = color, BorderSizePixel = 0, AutoButtonColor = false, Font = FONT, Text = label, TextColor3 = WHITE, TextSize = 20 }, parent)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	stroke(b, WHITE, 2)
	local sc = new("UIScale", {}, b)
	b.MouseEnter:Connect(function()
		tween(sc, 0.1, { Scale = 1.06 })
	end)
	b.MouseLeave:Connect(function()
		tween(sc, 0.1, { Scale = 1 })
	end)
	return b
end
local function ask(name, arg)
	local ok, a, b = pcall(function()
		return Action:InvokeServer(name, arg)
	end)
	if not ok then
		return false, "Couldn't reach the server."
	end
	return a, b
end

----------------------------------------------------------------------
-- The screen
----------------------------------------------------------------------
local gui = new("ScreenGui", { Name = "WeaponBag", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 41, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
gui:SetAttribute("RetroSkip", true)
local scaler = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)
local uiScale = new("UIScale", {}, scaler)
local function fit()
	local cam = Workspace.CurrentCamera
	if cam then
		local s = math.clamp(cam.ViewportSize.Y / 1000, 0.5, 1.1)
		uiScale.Scale = s
		scaler.Size = UDim2.fromScale(1 / s, 1 / s)
	end
end
fit()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
end

-- the WEAPONS button: a square under STATS, like the HUD's own
local openBtn = new("TextButton", {
	Name = "WeaponsButton",
	AutoButtonColor = false,
	BackgroundColor3 = RGB(38, 43, 68),
	BorderSizePixel = 0,
	Position = UDim2.new(0, 16, 0.44, 5),
	Size = UDim2.fromOffset(112, 112),
	Text = "",
}, scaler)
stroke(openBtn, INK, 4)
local face = new("Frame", { BackgroundColor3 = RGB(200, 90, 60), BorderSizePixel = 0, Position = UDim2.fromOffset(6, 5), Size = UDim2.new(1, -12, 1, -13) }, openBtn)
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(RGB(255, 150, 90), RGB(150, 50, 50)) }, face)
do -- a little pixel sword
	local blade = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = RGB(225, 232, 245), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 38), Size = UDim2.fromOffset(12, 52), Rotation = 45 }, face)
	stroke(blade, INK, 3)
	local guard = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = GOLD, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, -14, 0, 54), Size = UDim2.fromOffset(28, 8), Rotation = 45 }, face)
	stroke(guard, INK, 3)
end
text(face, { Text = "Weapons", TextSize = 22, Position = UDim2.new(0, 0, 1, -30), Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0 })
local openScale = new("UIScale", {}, openBtn)

-- the window
local dim = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = RGB(0, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 1 }, scaler)
local win = new("Frame", { BackgroundColor3 = PANEL, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(900, 620), Visible = false, ZIndex = 2, Active = true }, scaler)
stroke(win, WHITE, 4)
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(RGB(72, 36, 120), RGB(20, 14, 50)) }, win)
local winScale = new("UIScale", {}, win)
text(win, { Text = "WEAPONS", TextSize = 34, Position = UDim2.fromOffset(28, 18), Size = UDim2.fromOffset(400, 44), ZIndex = 3 })
local status = text(win, { Text = "", TextSize = 18, TextColor3 = GREY, Position = UDim2.new(0, 28, 1, -44), Size = UDim2.new(1, -56, 0, 30), ZIndex = 3 })
local fistsBtn = button(win, "FISTS", RGB(70, 60, 110), { Position = UDim2.new(1, -250, 0, 20), Size = UDim2.fromOffset(150, 44), ZIndex = 3 })
local closeBtn = button(win, "X", RGB(20, 16, 44), { Position = UDim2.new(1, -76, 0, 18), Size = UDim2.fromOffset(48, 48), TextSize = 26, ZIndex = 3 })
local list = new("ScrollingFrame", {
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(24, 80),
	Size = UDim2.new(1, -48, 1, -134),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 8,
	ZIndex = 3,
}, win)
new("UIGridLayout", { CellSize = UDim2.fromOffset(410, 150), CellPadding = UDim2.fromOffset(14, 14), SortOrder = Enum.SortOrder.LayoutOrder }, list)
new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4) }, list)

local data = nil

-- the weapons' icons (their real pictures, uploaded: AssetIds.Icons)
local AssetIds = nil
pcall(function()
	AssetIds = require(ReplicatedStorage:WaitForChild("AssetIds", 5))
end)
local function iconFor(def, id)
	local icons = type(AssetIds) == "table" and AssetIds.Icons
	local n = icons and ((def and def.Model and icons[def.Model]) or icons[id])
	return n and ("rbxthumb://type=Asset&id=" .. tostring(n) .. "&w=150&h=150") or nil
end

local function setStatus(msg, good)
	status.Text = msg or ""
	status.TextColor3 = good == false and RED or (good and GREEN or GREY)
end

-- one weapon's card
local function card(id, def, points, holding, order)
	local color = RARITY[def.Rarity] or RARITY.Common
	local c = new("Frame", { BackgroundColor3 = holding and CARD_HOLD or CARD, BorderSizePixel = 0, LayoutOrder = order, ZIndex = 3 }, list)
	local edge = stroke(c, color, holding and 4 or 3)
	if def.Rarity == "Secret" then
		new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, RGB(255, 80, 80)),
				ColorSequenceKeypoint.new(0.33, RGB(255, 230, 80)),
				ColorSequenceKeypoint.new(0.66, RGB(80, 220, 255)),
				ColorSequenceKeypoint.new(1, RGB(220, 90, 255)),
			}),
		}, edge)
	end
	-- the rarity stripe down the left
	new("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.new(0, 10, 1, 0), ZIndex = 4 }, c)
	-- its icon, top right (once the icons are uploaded)
	local icon = iconFor(def, id)
	if icon then
		new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = icon, ScaleType = Enum.ScaleType.Fit, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 6), Size = UDim2.fromOffset(84, 84), ZIndex = 4 }, c)
	end
	text(c, { Text = def.Name, TextSize = 24, Position = UDim2.fromOffset(24, 10), Size = UDim2.new(1, icon and -130 or -40, 0, 30), ZIndex = 4, TextTruncate = Enum.TextTruncate.AtEnd })
	text(c, { Text = string.upper(def.Rarity) .. "  ·  " .. def.Type, TextSize = 16, TextColor3 = color, Position = UDim2.fromOffset(24, 40), Size = UDim2.new(1, -40, 0, 20), ZIndex = 4 })
	local ability = def.Ability and def.Ability.Name or "No ability"
	text(c, { Text = "F: " .. ability, TextSize = 16, TextColor3 = GREY, Position = UDim2.fromOffset(24, 62), Size = UDim2.new(1, -40, 0, 20), ZIndex = 4 })
	-- mastery
	local level, into = Config.masteryLevel(points)
	text(c, { Text = "Mastery " .. level, TextSize = 16, TextColor3 = level >= W.MasteryMax and GOLD or WHITE, Position = UDim2.fromOffset(24, 90), Size = UDim2.fromOffset(140, 20), ZIndex = 4 })
	local bar = new("Frame", { BackgroundColor3 = RGB(20, 16, 44), BorderSizePixel = 0, Position = UDim2.fromOffset(24, 116), Size = UDim2.fromOffset(200, 12), ZIndex = 4 }, c)
	stroke(bar, INK, 2)
	new("Frame", { BackgroundColor3 = level >= W.MasteryMax and GOLD or RGB(70, 160, 255), BorderSizePixel = 0, Size = UDim2.fromScale(math.clamp(into, 0, 1), 1), ZIndex = 5 }, bar)
	-- equip
	if not W.Types[def.Type] then
		text(c, { Text = "SOON", TextSize = 20, TextColor3 = GREY, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -14), Size = UDim2.fromOffset(140, 40), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 })
	elseif holding then
		text(c, { Text = "IN HAND", TextSize = 20, TextColor3 = GREEN, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -14), Size = UDim2.fromOffset(140, 40), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 })
	else
		local b = button(c, "EQUIP", RGB(60, 150, 70), { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -14), Size = UDim2.fromOffset(130, 44), ZIndex = 4 })
		b.Activated:Connect(function()
			setStatus("...")
			local ok, msg = ask("EquipWeapon", id)
			setStatus(msg, ok)
		end)
	end
end

local function redraw()
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local weapons = data and data.Weapons
	if not weapons then
		return
	end
	local held = player:GetAttribute("Weapon")
	local ids = {}
	for id in pairs(weapons.own or {}) do
		if W.List[id] then
			table.insert(ids, id)
		end
	end
	-- rarest first, then by name
	table.sort(ids, function(a, b)
		local ra, rb = RARITY_ORDER[W.List[a].Rarity] or 9, RARITY_ORDER[W.List[b].Rarity] or 9
		if ra ~= rb then
			return ra < rb
		end
		return W.List[a].Name < W.List[b].Name
	end)
	for i, id in ipairs(ids) do
		card(id, W.List[id], weapons.own[id] or 0, id == held, i)
	end
	fistsBtn.Visible = held ~= nil
end

local function openWindow()
	if win.Visible then
		return
	end
	win.Visible, dim.Visible = true, true
	winScale.Scale = 1.04
	tween(winScale, 0.2, { Scale = 1 })
	dim.BackgroundTransparency = 1
	tween(dim, 0.2, { BackgroundTransparency = 0.5 })
	setStatus("")
	redraw()
end
local function closeWindow()
	if not win.Visible then
		return
	end
	tween(winScale, 0.12, { Scale = 0.9 })
	tween(dim, 0.12, { BackgroundTransparency = 1 })
	task.delay(0.12, function()
		win.Visible, dim.Visible = false, false
	end)
end

openBtn.Activated:Connect(function()
	tween(openScale, 0.05, { Scale = 0.92 })
	task.delay(0.05, function()
		tween(openScale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	if win.Visible then
		closeWindow()
	else
		openWindow()
	end
end)
closeBtn.Activated:Connect(closeWindow)
dim.Activated:Connect(closeWindow)
fistsBtn.Activated:Connect(function()
	local ok, msg = ask("EquipWeapon", nil)
	setStatus(msg, ok)
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.B then
		if win.Visible then
			closeWindow()
		else
			openWindow()
		end
	elseif input.KeyCode == Enum.KeyCode.Escape then
		closeWindow()
	end
end)

-- a new weapon in hand, or new data from the server: draw it again
player:GetAttributeChangedSignal("Weapon"):Connect(function()
	if win.Visible then
		redraw()
	end
end)
Remotes:WaitForChild("StateUpdate").OnClientEvent:Connect(function(d)
	data = d
	if win.Visible then
		redraw()
	end
end)
local req = Remotes:FindFirstChild("RequestState")
if req then
	req:FireServer()
end
