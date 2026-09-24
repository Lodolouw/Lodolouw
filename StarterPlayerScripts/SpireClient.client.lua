--[[
	SpireClient  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "SpireClient")

	The Spire's menus and travel effects:
	  * the Spire menu (opened by the "Enter" prompt at the Spire's doors):
	    pick a floor, see its boss, the recommended level and your level,
	    then ENTER
	  * a fade to black while you travel, then a big area title card as you
	    arrive ("GLOOMGUT'S HOLLOW")
	  * a Leave button while you're in an arena, and a "Leave?" check when you
	    touch the fog gate

	The server (SpireService) decides whether you may travel and moves you.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local SpireRemotes = ReplicatedStorage:WaitForChild("SpireRemotes")
local SpireEvent = SpireRemotes:WaitForChild("SpireEvent")
local SpireTravel = SpireRemotes:WaitForChild("SpireTravel")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RGB = Color3.fromRGB
local SERIF = Enum.Font.Garamond
local BOLD = Enum.Font.FredokaOne
local C = {
	bg = RGB(14, 12, 20),
	panel = RGB(24, 20, 32),
	row = RGB(38, 32, 50),
	rowHover = RGB(52, 44, 68),
	rim = RGB(120, 100, 150),
	gold = RGB(230, 200, 130),
	pale = RGB(225, 220, 235),
	dim = RGB(150, 140, 165),
	red = RGB(235, 90, 90),
	green = RGB(120, 230, 110),
	glow = RGB(90, 150, 255),
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
local function corner(r)
	return create("UICorner", { CornerRadius = UDim.new(0, r) })
end
local function stroke(thickness, color, transparency)
	return create("UIStroke", {
		Thickness = thickness,
		Color = color or RGB(0, 0, 0),
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
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

-- short message line (for "you can't travel right now" etc.)
local message = label({
	Name = "Message",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 120),
	Size = UDim2.fromOffset(700, 36),
	Text = "",
	TextSize = 26,
	TextColor3 = C.red,
	TextTransparency = 1,
	ZIndex = 60,
	Parent = root,
}, {})
local messageStroke = textStroke(2.5)
messageStroke.Transparency = 1
messageStroke.Parent = message
local messageToken = 0
local function showMessage(text)
	messageToken = messageToken + 1
	local token = messageToken
	message.Text = text
	message.TextTransparency = 0
	messageStroke.Transparency = 0.2 -- the outline doesn't fade with the text on its own
	task.delay(2.4, function()
		if token == messageToken then
			tween(message, 0.5, { TextTransparency = 1 })
			tween(messageStroke, 0.5, { Transparency = 1 })
		end
	end)
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

local function travel(action, floorId)
	if travelling then
		return
	end
	travelling = true
	arrivedInfo = nil
	fadeTo(0, 0.45)
	local ok, success, reason = pcall(function()
		return SpireTravel:InvokeServer(action, floorId)
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
-- The Spire menu
----------------------------------------------------------------------
local menu = create("Frame", {
	Name = "SpireMenu",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(780, 470),
	BackgroundColor3 = C.panel,
	BackgroundTransparency = 0.05,
	Visible = false,
	ZIndex = 50,
	Parent = root,
}, {
	corner(14),
	stroke(3, C.rim, 0.2),
	create("UIGradient", {
		Color = ColorSequence.new(RGB(40, 32, 54), RGB(16, 14, 22)),
		Rotation = 90,
	}),
})
local menuTitle = label({
	Position = UDim2.fromOffset(0, 14),
	Size = UDim2.new(1, 0, 0, 56),
	Font = SERIF,
	Text = "THE SPIRE",
	TextSize = 54,
	TextColor3 = C.gold,
	ZIndex = 51,
	Parent = menu,
})
textStroke(2).Parent = menuTitle
label({
	Position = UDim2.fromOffset(0, 68),
	Size = UDim2.new(1, 0, 0, 24),
	Font = SERIF,
	Text = "Choose a floor. Each one holds a boss.",
	TextSize = 22,
	TextColor3 = C.dim,
	ZIndex = 51,
	Parent = menu,
})
local closeBtn = create("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 12),
	Size = UDim2.fromOffset(44, 44),
	BackgroundColor3 = C.row,
	Text = "X",
	Font = BOLD,
	TextSize = 26,
	TextColor3 = C.pale,
	AutoButtonColor = true,
	ZIndex = 52,
	Parent = menu,
}, { corner(10), stroke(2, C.rim, 0.4) })

-- floor list on the left
local list = create("Frame", {
	Position = UDim2.fromOffset(24, 108),
	Size = UDim2.fromOffset(250, 338),
	BackgroundTransparency = 1,
	ZIndex = 51,
	Parent = menu,
}, {
	create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
})

-- details on the right
local detail = create("Frame", {
	Position = UDim2.fromOffset(296, 108),
	Size = UDim2.fromOffset(460, 338),
	BackgroundColor3 = C.bg,
	BackgroundTransparency = 0.2,
	ZIndex = 51,
	Parent = menu,
}, { corner(12), stroke(2, C.rim, 0.5) })
local dFloor = label({
	Position = UDim2.fromOffset(20, 14),
	Size = UDim2.new(1, -40, 0, 24),
	Font = SERIF,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "FLOOR 1",
	TextSize = 22,
	TextColor3 = C.dim,
	ZIndex = 52,
	Parent = detail,
})
local dBoss = label({
	Position = UDim2.fromOffset(20, 40),
	Size = UDim2.new(1, -40, 0, 64),
	Font = SERIF,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
	TextSize = 34,
	ZIndex = 52,
	Parent = detail,
})
textStroke(1.5).Parent = dBoss
local dArea = label({
	Position = UDim2.fromOffset(20, 104),
	Size = UDim2.new(1, -40, 0, 24),
	Font = SERIF,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
	TextSize = 22,
	TextColor3 = C.gold,
	ZIndex = 52,
	Parent = detail,
})
local dBlurb = label({
	Position = UDim2.fromOffset(20, 136),
	Size = UDim2.new(1, -40, 0, 80),
	Font = SERIF,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Text = "",
	TextSize = 21,
	TextColor3 = C.dim,
	ZIndex = 52,
	Parent = detail,
})
local dLevel = label({
	Position = UDim2.fromOffset(20, 222),
	Size = UDim2.new(1, -40, 0, 26),
	TextXAlignment = Enum.TextXAlignment.Left,
	RichText = true,
	Text = "",
	TextSize = 22,
	ZIndex = 52,
	Parent = detail,
})
textStroke(2).Parent = dLevel
local enterBtn = create("TextButton", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.fromOffset(300, 58),
	BackgroundColor3 = RGB(70, 40, 100),
	Text = "ENTER",
	Font = SERIF,
	TextSize = 36,
	TextColor3 = C.pale,
	AutoButtonColor = true,
	ZIndex = 53,
	Parent = detail,
}, {
	corner(12),
	stroke(3, C.gold, 0.2),
	create("UIGradient", { Color = ColorSequence.new(RGB(120, 80, 170), RGB(60, 30, 90)), Rotation = 90 }),
})

local selected = 1
local floorButtons = {}

local function myLevel()
	local ls = player:FindFirstChild("leaderstats")
	local lv = ls and ls:FindFirstChild("Level")
	return lv and lv.Value or 1
end

-- A floor opens once the boss on the floor below it is beaten (every open
-- floor is free to enter in Studio, so you can test). Returns the boss you
-- still have to beat, or nil if you can go in.
local function lockedBy(f)
	if not (Config.Spire.RequirePrevious and f.id > 1) or RunService:IsStudio() then
		return nil
	end
	if (player:GetAttribute("SpireCleared") or 0) >= f.id - 1 then
		return nil
	end
	local below = Config.Spire.Floors[f.id - 1]
	return below and below.boss and string.match(below.boss, "^[^,]+") or "the floor below"
end

local function renderDetail()
	local f = Config.Spire.Floors[selected]
	if not f then
		return
	end
	dFloor.Text = "FLOOR " .. f.id
	dBoss.Text = f.open and f.boss or "Sealed"
	dBoss.TextColor3 = f.open and f.color or C.dim
	dArea.Text = f.open and f.area or ""
	dBlurb.Text = f.blurb
	local lv = myLevel()
	local color = lv >= f.level and "#78e66e" or "#eb5a5a"
	dLevel.Text = string.format('Recommended: Lv. %d    You: <font color="%s">Lv. %d</font>', f.level, color, lv)
	if f.id <= (player:GetAttribute("SpireCleared") or 0) then
		dLevel.Text = dLevel.Text .. '    <font color="#ebc86e">DEFEATED</font>'
	end
	local lock = f.open and lockedBy(f)
	if lock then
		dLevel.Text = string.format('<font color="#eb5a5a">Defeat %s first</font>    Recommended: Lv. %d', lock, f.level)
	end
	local canEnter = f.open and not lock
	enterBtn.Active = canEnter
	enterBtn.AutoButtonColor = canEnter
	enterBtn.Text = canEnter and "ENTER" or (lock and "LOCKED" or "SEALED")
	enterBtn.TextTransparency = canEnter and 0 or 0.5
	for i, b in ipairs(floorButtons) do
		b.BackgroundColor3 = (i == selected) and C.rowHover or C.row
		b:FindFirstChildOfClass("UIStroke").Transparency = (i == selected) and 0 or 0.6
	end
end

for i, f in ipairs(Config.Spire.Floors) do
	local b = create("TextButton", {
		LayoutOrder = i,
		Size = UDim2.new(1, 0, 0, 72),
		BackgroundColor3 = C.row,
		Text = "",
		AutoButtonColor = true,
		ZIndex = 52,
		Parent = list,
	}, { corner(10), stroke(2, f.open and f.color or C.rim, 0.6) })
	label({
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -28, 0, 24),
		Font = SERIF,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = (f.open and "" or "🔒  ") .. "Floor " .. f.id,
		TextSize = 24,
		TextColor3 = f.open and C.pale or C.dim,
		ZIndex = 53,
		Parent = b,
	})
	label({
		Position = UDim2.fromOffset(14, 36),
		Size = UDim2.new(1, -28, 0, 28),
		Font = SERIF,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		Text = f.open and f.area or "Sealed",
		TextSize = 20,
		TextColor3 = f.open and f.color or C.dim,
		ZIndex = 53,
		Parent = b,
	})
	-- "DEFEATED" once you've killed this floor's boss (PlayerService keeps the
	-- highest floor you've cleared on the SpireCleared attribute)
	label({
		Name = "Defeated",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 10),
		Size = UDim2.fromOffset(110, 20),
		Font = SERIF,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "DEFEATED",
		TextSize = 17,
		TextColor3 = Color3.fromRGB(235, 200, 110),
		Visible = false,
		ZIndex = 53,
		Parent = b,
	})
	b.Activated:Connect(function()
		selected = i
		renderDetail()
	end)
	floorButtons[i] = b
end

local function renderCleared()
	local cleared = player:GetAttribute("SpireCleared") or 0
	for i, b in ipairs(floorButtons) do
		local tag = b:FindFirstChild("Defeated")
		if tag then
			tag.Visible = Config.Spire.Floors[i].id <= cleared
		end
	end
end
renderCleared()
player:GetAttributeChangedSignal("SpireCleared"):Connect(function()
	renderCleared()
	renderDetail() -- beating a boss unlocks the next floor
end)

local function openMenu()
	if travelling then
		return
	end
	renderDetail()
	menu.Visible = true
	menu.Size = UDim2.fromOffset(740, 440)
	tween(menu, 0.18, { Size = UDim2.fromOffset(780, 470) }, Enum.EasingStyle.Back)
end
local function closeMenu()
	menu.Visible = false
end
closeBtn.Activated:Connect(closeMenu)
enterBtn.Activated:Connect(function()
	local f = Config.Spire.Floors[selected]
	if not (f and f.open) or lockedBy(f) then
		return
	end
	closeMenu()
	task.spawn(travel, "enter", f.id)
end)

----------------------------------------------------------------------
-- In the arena: a Leave button, and a check at the fog gate
----------------------------------------------------------------------
local confirm = create("Frame", {
	Name = "ConfirmLeave",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(460, 200),
	BackgroundColor3 = C.panel,
	Visible = false,
	ZIndex = 55,
	Parent = root,
}, { corner(14), stroke(3, C.rim, 0.2) })
local confirmText = label({
	Position = UDim2.fromOffset(20, 24),
	Size = UDim2.new(1, -40, 0, 70),
	Font = SERIF,
	Text = "Leave the arena and return to the Spire's doors?",
	TextSize = 28,
	ZIndex = 56,
	Parent = confirm,
})
local function dialogButton(text, x, color)
	return create("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(x, 0, 1, -20),
		Size = UDim2.fromOffset(170, 52),
		BackgroundColor3 = color,
		Text = text,
		Font = SERIF,
		TextSize = 28,
		TextColor3 = C.pale,
		AutoButtonColor = true,
		ZIndex = 56,
		Parent = confirm,
	}, { corner(10), stroke(2, C.gold, 0.4) })
end
local yesBtn = dialogButton("Leave", 0.28, RGB(90, 40, 60))
local noBtn = dialogButton("Stay", 0.72, C.row)

local function askLeave()
	if travelling or not player:GetAttribute("SpireFloor") then
		return
	end
	local f = Config.Spire.Floors[player:GetAttribute("SpireFloor")]
	confirmText.Text = "Leave " .. (f and f.area or "the arena") .. " and return to the Spire's doors?"
	confirm.Visible = true
end
yesBtn.Activated:Connect(function()
	confirm.Visible = false
	task.spawn(travel, "leave")
end)
noBtn.Activated:Connect(function()
	confirm.Visible = false
end)

local leaveBtn = create("TextButton", {
	Name = "LeaveArena",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 118),
	Size = UDim2.fromOffset(210, 44),
	BackgroundColor3 = C.panel,
	BackgroundTransparency = 0.15,
	Text = "Leave Arena",
	Font = SERIF,
	TextSize = 24,
	TextColor3 = C.pale,
	AutoButtonColor = true,
	Visible = false,
	ZIndex = 40,
	Parent = root,
}, { corner(10), stroke(2, C.rim, 0.3) })
leaveBtn.Activated:Connect(askLeave)

local function onFloorChanged()
	local inArena = player:GetAttribute("SpireFloor") ~= nil
	leaveBtn.Visible = inArena
	if not inArena then
		confirm.Visible = false
	end
end
player:GetAttributeChangedSignal("SpireFloor"):Connect(onFloorChanged)
onFloorChanged()

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
	end
end)

-- Escape / B closes the menu or the dialog
UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
		if confirm.Visible then
			confirm.Visible = false
		elseif menu.Visible then
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
		return menu.Visible
	end
	return confirm.Visible
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
		local margin = (kind == activeKind or kind == dismissedKind) and 2 or 0
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
		if activeKind == "Menu" and menu.Visible then
			closeMenu()
		elseif activeKind == "Leave" and confirm.Visible then
			confirm.Visible = false
		end
		activeKind = nil
		dismissedKind = nil
	end
end)
