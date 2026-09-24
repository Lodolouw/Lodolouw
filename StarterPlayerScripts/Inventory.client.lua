--[[
	Inventory  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "Inventory")

	Your GEAR: the bag, what you're wearing, and opening treasure chests.

	  * The GEAR button (under the four buttons on the left, or press G) opens
	    your bag. A red badge on it counts your unopened chests.
	  * Left: you, with your four slots (Weapon, Helmet, Chest, Boots), your
	    total stats and any set bonus you've unlocked.
	  * Right: your items as a grid - tabs for each slot and for CHESTS, and a
	    sort button (rarity / level / newest).
	  * Point at an item for its card: rarity, level, every stat with its
	    range and how it compares to what you're wearing (green up, red down),
	    its set and its lore. Click it to select it (double-click wears it):
	    WEAR / TAKE OFF, LOCK (so it can't be salvaged by accident) and
	    SALVAGE for coins (asks twice).
	  * Opening a chest plays its reveal: it shakes, light the colour of what's
	    inside leaks out of the cracks, and it bursts - longer and grander the
	    rarer the item. A SECRET goes quiet and dark first.

	The server does everything (rolls, wearing, salvaging); this only shows it
	and asks. Tuning for items is in ReplicatedStorage.Items.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Items = require(ReplicatedStorage:WaitForChild("Items"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Action = Remotes:WaitForChild("Action")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local RGB = Color3.fromRGB
local BLACK, WHITE, INK = RGB(0, 0, 0), RGB(255, 255, 255), RGB(24, 20, 37)
local PANEL, SLOT, SLOT_HOVER = RGB(12, 10, 20), RGB(30, 28, 46), RGB(46, 44, 70)
local GREY, DIM = RGB(139, 155, 180), RGB(90, 105, 136)
local GOLD, RED, GREEN = RGB(254, 174, 52), RGB(228, 59, 68), RGB(99, 199, 77)
local FONT = Enum.Font.Arcade
local TITLE_FACE = nil
pcall(function()
	TITLE_FACE = Font.new("rbxasset://fonts/families/PressStart2P.json")
end)

local SOUNDS = {
	Hover = "UI Blip",
	Click = "UI Blip",
	Equip = "dummy punch",
	Salvage = "coin2",
	Shake = "UI Blip",
	Reveal = "Victory Is Ours (a) Sting",
}

----------------------------------------------------------------------
-- Little helpers
----------------------------------------------------------------------
local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do
		i[k] = v
	end
	i.Parent = parent
	return i
end
local function tween(inst, t, props, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
local function sound(key, volume, pitch)
	local t = SOUNDS[key] and SoundService:FindFirstChild(SOUNDS[key])
	if t and t:IsA("Sound") then
		local s = t:Clone()
		s.Volume = t.Volume * (volume or 1)
		s.PlaybackSpeed = pitch or 1
		s.Parent = SoundService
		s:Play()
		task.delay(4, function()
			s:Destroy()
		end)
	end
end
local function text(parent, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = WHITE,
		TextSize = 20,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	for k, v in pairs(props) do
		l[k] = v
	end
	return l
end
local function box(parent, props, edge, thickness)
	local f = new("Frame", { BackgroundColor3 = PANEL, BorderSizePixel = 0 }, parent)
	for k, v in pairs(props) do
		f[k] = v
	end
	new("UIStroke", { Color = edge or WHITE, Thickness = thickness or 3, LineJoinMode = Enum.LineJoinMode.Miter, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	return f
end
local function button(parent, label, color, props)
	local b = new("TextButton", {
		BackgroundColor3 = color or SLOT,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = FONT,
		Text = label,
		TextColor3 = WHITE,
		TextSize = 20,
	}, parent)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	new("UIStroke", { Color = WHITE, Thickness = 2, LineJoinMode = Enum.LineJoinMode.Miter, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	local sc = new("UIScale", {}, b)
	b.MouseEnter:Connect(function()
		tween(sc, 0.08, { Scale = 1.06 })
		sound("Hover", 0.25, 1.3)
	end)
	b.MouseLeave:Connect(function()
		tween(sc, 0.1, { Scale = 1 })
	end)
	b.MouseButton1Down:Connect(function()
		tween(sc, 0.05, { Scale = 0.94 })
	end)
	b.MouseButton1Up:Connect(function()
		tween(sc, 0.18, { Scale = 1.06 }, Enum.EasingStyle.Back)
	end)
	return b
end

-- rarity colours (SECRET shimmers through every colour: see the loop below)
local rainbow = setmetatable({}, { __mode = "k" }) -- [instance] = property
local function rarityColor(rarity)
	return Items.RarityById[rarity].color
end
local function paintRarity(inst, prop, rarity)
	inst[prop] = rarityColor(rarity)
	if rarity == "Secret" then
		rainbow[inst] = prop
	else
		rainbow[inst] = nil
	end
end

----------------------------------------------------------------------
-- Pixel icons: one per slot, drawn in each item's own colours
----------------------------------------------------------------------
local ICONS = {
	Weapon = {
		"..........OO", ".........OWO", "........OWMO", ".......OWMO.", "......OWMO..", ".....OWMO...",
		"..O.OWMO....", "..OAOMO.....", "...OAO......", "..OAOAO.....", ".OAO..O.....", ".OO.........",
	},
	Helmet = {
		"...OOOOOO...", "..OMMMMMMO..", ".OMWMMMMMMO.", ".OMWMMMMMMO.", "OMMMMMMMMMMO", "OMMOOOOOOMMO",
		"OMO......OMO", "OMO.AAAA.OMO", "OMMO....OMMO", ".OMO....OMO.", "..OO....OO..", "............",
	},
	Chest = {
		".OOO....OOO.", "OMMMOOOOMMMO", "OMMMMAAMMMMO", "OMWMMAAMMMMO", ".OMMMAAMMMO.", ".OMWMAAMMMO.",
		".OMMMAAMMMO.", ".OMMMMMMMMO.", ".OMMMMMMMMO.", ".OAAAAAAAAO.", "..OOOOOOOO..", "............",
	},
	Boots = {
		"............", "..OOOO......", "..OMMO......", "..OWMO......", "..OMMO......", "..OMMO......",
		"..OMMOOOO...", "..OMMMMMMO..", ".OMMMMMMMMO.", ".OAAAAAAAAO.", ".OOOOOOOOOO.", "............",
	},
	Treasure = {
		"............", "..OOOOOOOO..", ".OMMMMMMMMO.", "OMMWMMMMMMMO", "OAAAAAAAAAAO", "OMMMMOOMMMMO",
		"OMMMMOYOMMMO", "OMMMMMOMMMMO", "OMMMMMMMMMMO", "OAAAAAAAAAAO", ".OOOOOOOOOO.", "............",
	},
}
local iconCache = {}
-- a finished pixel icon (built once per look, then copied)
local function icon(kind, main, accent)
	local key = kind .. tostring(main) .. tostring(accent)
	local proto = iconCache[key]
	if not proto then
		local rows = ICONS[kind]
		local ink = { O = INK, M = main, A = accent, W = WHITE, Y = RGB(254, 231, 97) }
		proto = new("Frame", { Name = "Icon", BackgroundTransparency = 1, Size = UDim2.fromScale(0.78, 0.78), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		new("UIAspectRatioConstraint", { AspectRatio = 1 }, proto)
		for y = 1, #rows do
			for x = 1, #rows[y] do
				local c = ink[string.sub(rows[y], x, x)]
				if c then
					new("Frame", {
						BorderSizePixel = 0,
						BackgroundColor3 = c,
						Size = UDim2.fromScale(1 / 12 + 0.004, 1 / 12 + 0.004),
						Position = UDim2.fromScale((x - 1) / 12, (y - 1) / 12),
						ZIndex = 3,
					}, proto)
				end
			end
		end
		iconCache[key] = proto
	end
	return proto:Clone()
end
local function itemIcon(def)
	return icon(def.slot, def.tint[1], def.tint[2])
end
local function chestIcon(floor)
	local def = Config.Bosses[floor]
	return icon("Treasure", RGB(184, 111, 80), (def and def.Color) or GOLD)
end

----------------------------------------------------------------------
-- State from the server
----------------------------------------------------------------------
local data = nil
local redraw -- (set below)
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
local gui = new("ScreenGui", { Name = "Inventory", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 40 }, playerGui)
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

-- the GEAR button, under the four on the left
local gearBtn = new("TextButton", {
	Name = "GearButton",
	AutoButtonColor = false,
	BackgroundColor3 = RGB(58, 68, 102),
	BorderSizePixel = 0,
	Position = UDim2.new(0, 16, 0.44, 127),
	Size = UDim2.fromOffset(234, 64),
	Text = "",
}, scaler)
new("UIStroke", { Color = INK, Thickness = 4, LineJoinMode = Enum.LineJoinMode.Miter, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, gearBtn)
local gearFace = new("Frame", { BackgroundColor3 = RGB(90, 105, 136), BorderSizePixel = 0, Position = UDim2.fromOffset(5, 4), Size = UDim2.new(1, -10, 1, -11) }, gearBtn)
local gearIcon = icon("Chest", RGB(192, 203, 220), GOLD)
gearIcon.Size = UDim2.fromOffset(44, 44)
gearIcon.Position = UDim2.new(0, 34, 0.5, 0)
gearIcon.Parent = gearFace
text(gearFace, { Text = "GEAR", TextSize = 32, Position = UDim2.fromOffset(66, 0), Size = UDim2.new(1, -110, 1, 0), TextStrokeTransparency = 0, TextStrokeColor3 = INK })
text(gearFace, { Text = "[G]", TextSize = 16, TextColor3 = RGB(192, 203, 220), Position = UDim2.new(1, -46, 0, 0), Size = UDim2.fromOffset(40, 50), TextXAlignment = Enum.TextXAlignment.Right })
local badge = new("TextLabel", {
	BackgroundColor3 = RED,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(1, -4, 0, 4),
	Size = UDim2.fromOffset(34, 34),
	Font = FONT,
	TextSize = 20,
	TextColor3 = WHITE,
	Text = "0",
	Visible = false,
	ZIndex = 5,
}, gearBtn)
new("UIStroke", { Color = WHITE, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, badge)
local badgeScale = new("UIScale", {}, badge)
local gearScale = new("UIScale", {}, gearBtn)

-- the window: Minecraft Dungeons-style - it takes the whole screen: a deep,
-- warm dark backdrop, you standing big in a spotlight on the left with your
-- gear floating round you, your items in the middle, and the item you're
-- looking at, huge, on the right. No boxes - everything floats.
local WOOD, WOOD_DARK, WOOD_EDGE = RGB(46, 30, 34), RGB(30, 20, 24), RGB(150, 110, 60)
local TILE, TILE_HOVER = RGB(52, 36, 40), RGB(84, 60, 62)
local dim = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = BLACK, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 1 }, scaler)
local win = new("Frame", { BackgroundColor3 = RGB(40, 22, 26), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 2, Active = true }, scaler)
new("UIGradient", { Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, RGB(74, 36, 40)), ColorSequenceKeypoint.new(0.55, RGB(38, 22, 28)), ColorSequenceKeypoint.new(1, RGB(16, 10, 14)) }) }, win)
local winScale = new("UIScale", {}, win)
-- faint pixel blocks drifting in the backdrop, and a dark vignette at the edges
do
	local rnd = Random.new(11)
	for _ = 1, 26 do
		local size = rnd:NextInteger(40, 120)
		new("Frame", {
			BorderSizePixel = 0,
			BackgroundColor3 = rnd:NextNumber() < 0.5 and RGB(90, 48, 52) or RGB(20, 12, 16),
			BackgroundTransparency = 0.82 + rnd:NextNumber() * 0.12,
			Position = UDim2.new(rnd:NextNumber(), -size / 2, rnd:NextNumber(), -size / 2),
			Size = UDim2.fromOffset(size, size),
			ZIndex = 2,
		}, win)
	end
	for _, v in ipairs({ { 0, 0, 1, 0.16, 90, false }, { 0, 0.84, 1, 0.16, 90, true }, { 0, 0, 0.1, 1, 0, false }, { 0.9, 0, 0.1, 1, 0, true } }) do
		local f = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = BLACK, Position = UDim2.fromScale(v[1], v[2]), Size = UDim2.fromScale(v[3], v[4]), ZIndex = 2 }, win)
		new("UIGradient", { Rotation = v[5], Transparency = NumberSequence.new(v[6] and 1 or 0.35, v[6] and 0.35 or 1) }, f)
	end
end

-- the top bar: your coins, the title, and the way out
local topBar = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 70), ZIndex = 3 }, win)
local coinIcon = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = GOLD, Position = UDim2.fromOffset(40, 22), Size = UDim2.fromOffset(26, 26), Rotation = 45, ZIndex = 4 }, topBar)
new("UIStroke", { Color = INK, Thickness = 3 }, coinIcon)
local coinText = text(topBar, { Text = "0", TextSize = 30, TextColor3 = GOLD, Position = UDim2.fromOffset(80, 16), Size = UDim2.fromOffset(240, 40), ZIndex = 4, TextStrokeTransparency = 0.4, TextStrokeColor3 = INK })
local title = text(topBar, { Text = "INVENTORY", TextSize = 30, TextColor3 = WHITE, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.22), Size = UDim2.fromOffset(400, 40), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
if TITLE_FACE then
	title.FontFace = TITLE_FACE
	title.TextSize = 24
end
local bagCount = text(topBar, { Text = "0/60", TextSize = 20, TextColor3 = GREY, Position = UDim2.new(1, -330, 0, 20), Size = UDim2.fromOffset(240, 30), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 })
local closeBtn = button(topBar, "X", RGB(30, 20, 24), { Position = UDim2.new(1, -74, 0, 14), Size = UDim2.fromOffset(46, 46), TextSize = 28, ZIndex = 5 })

-- LEFT: you, big, in a spotlight
local left = new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 30, 0, 80), Size = UDim2.new(0.36, -30, 1, -100), ZIndex = 3 }, win)
local spot = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = RGB(255, 210, 160), BackgroundTransparency = 0.9, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.7, 0.7), SizeConstraint = Enum.SizeConstraint.RelativeXX, ZIndex = 3 }, left)
new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, spot)
new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.6, 0.7), NumberSequenceKeypoint.new(1, 1) }) }, spot)
local shadow = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = BLACK, BackgroundTransparency = 0.55, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.7), Size = UDim2.new(0.34, 0, 0, 34), ZIndex = 3 }, left)
new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, shadow)
local view = new("ViewportFrame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.02), Size = UDim2.fromScale(0.62, 0.7), Ambient = RGB(190, 170, 170), LightColor = RGB(255, 236, 210), LightDirection = Vector3.new(-0.6, -1, -0.8), ZIndex = 4 }, left)
local viewCam = new("Camera", { FieldOfView = 30 }, view)
view.CurrentCamera = viewCam
local world = new("WorldModel", {}, view)
local avatar, avatarAngle = nil, 0
local function buildAvatar()
	world:ClearAllChildren()
	avatar = nil
	pcall(function()
		local char = player.Character
		if not char then
			return
		end
		local was = char.Archivable
		char.Archivable = true
		local copy = char:Clone()
		char.Archivable = was
		if not copy then
			return
		end
		for _, d in ipairs(copy:GetDescendants()) do
			if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") or d:IsA("ParticleEmitter") or d:IsA("BillboardGui") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		copy:PivotTo(CFrame.new())
		copy.Parent = world
		avatar = copy
	end)
end
-- the four slots float round you, two each side
local SLOT_AT = {
	Weapon = UDim2.new(0, 0, 0.08, 0),
	Helmet = UDim2.new(0, 0, 0.3, 0),
	Chest = UDim2.new(1, -104, 0.08, 0),
	Boots = UDim2.new(1, -104, 0.3, 0),
}
local wornSlots = {}
-- the level and power badges, like MCD's hexagons
local function badgeBox(pos, label, color)
	local b = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = RGB(24, 16, 20), AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Size = UDim2.fromOffset(92, 92), Rotation = 45, ZIndex = 4 }, left)
	new("UIStroke", { Color = color, Thickness = 3 }, b)
	local inner = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Size = UDim2.fromOffset(110, 92), ZIndex = 5 }, left)
	text(inner, { Text = label, TextSize = 14, TextColor3 = GREY, Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
	return text(inner, { Text = "0", TextSize = 34, TextColor3 = color, Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 44), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
end
local levelText = badgeBox(UDim2.new(0, 56, 0.58, 0), "LEVEL", RGB(254, 231, 97))
local powerText = badgeBox(UDim2.new(1, -56, 0.58, 0), "POWER", RGB(44, 232, 245))
local statsBox = new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 10, 0.76, 0), Size = UDim2.new(1, -20, 0, 80), ZIndex = 4 }, left)
new("UIGridLayout", { CellSize = UDim2.new(0.33, -6, 0, 24), CellPadding = UDim2.fromOffset(6, 4), SortOrder = Enum.SortOrder.LayoutOrder }, statsBox)
local setsBox = text(left, { Text = "", TextSize = 16, TextColor3 = GREEN, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 10, 0.92, 0), Size = UDim2.new(1, -20, 0, 40), ZIndex = 4 })

-- MIDDLE: your items
local middle = new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0.36, 10, 0, 80), Size = UDim2.new(0.3, -10, 1, -100), ZIndex = 3 }, win)
local tabs = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48), ZIndex = 3 }, middle)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center, HorizontalAlignment = Enum.HorizontalAlignment.Center }, tabs)
local grid = new("ScrollingFrame", {
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, 60),
	Size = UDim2.new(1, 0, 1, -110),
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = WOOD_EDGE,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 3,
}, middle)
new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 8) }, grid)
local gridLayout = new("UIGridLayout", { CellSize = UDim2.fromOffset(112, 112), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, grid)
local status = text(middle, { Text = "", TextSize = 17, TextColor3 = GREY, Position = UDim2.new(0, 4, 1, -44), Size = UDim2.new(1, -8, 0, 40), ZIndex = 3, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center })

-- RIGHT: the item you're looking at, big
local right = new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0.66, 20, 0, 80), Size = UDim2.new(0.34, -60, 1, -100), ZIndex = 3 }, win)
local detail = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -70), ZIndex = 3 }, right)
local actions = new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 1, -60), Size = UDim2.new(1, 0, 0, 56), ZIndex = 3 }, right)
local wearBtn = button(actions, "WEAR", GREEN, { Size = UDim2.new(0.34, -6, 0, 52), Visible = false, ZIndex = 4, TextSize = 22 })
local lockBtn = button(actions, "LOCK", RGB(30, 20, 24), { Position = UDim2.new(0.34, 0, 0, 0), Size = UDim2.new(0.3, -6, 0, 52), Visible = false, ZIndex = 4, TextSize = 20 })
local salvageBtn = button(actions, "SALVAGE", RGB(122, 30, 40), { Position = UDim2.new(0.64, 0, 0, 0), Size = UDim2.new(0.36, 0, 0, 52), Visible = false, ZIndex = 4, TextSize = 18 })

----------------------------------------------------------------------
-- The item card
----------------------------------------------------------------------
local function worn(uid)
	for _, slot in ipairs(Items.Slots) do
		if data and data.Gear[slot] == uid then
			return slot
		end
	end
	return nil
end
local function line(parent, s, color, size, order, wrap)
	return text(parent, {
		Text = s,
		TextColor3 = color or WHITE,
		TextSize = size or 18,
		Size = UDim2.new(1, 0, 0, (size or 18) + 2),
		AutomaticSize = wrap and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
		TextWrapped = wrap or false,
		LayoutOrder = order,
		ZIndex = 51,
	})
end
local function fillCard(card, uid)
	for _, c in ipairs(card:GetChildren()) do
		if c:IsA("TextLabel") or (c:IsA("Frame") and c.Name == "Row") then
			c:Destroy()
		end
	end
	local rec = data.Items[uid]
	local def = rec and Items.ById[rec.id]
	if not def then
		return
	end
	local rarity = Items.RarityById[def.rarity]
	local _, stars, perfect = Items.quality(def, rec.r)
	local o = 0
	local function nextOrder()
		o = o + 1
		return o
	end
	local name = line(card, (perfect and "* " or "") .. def.name, rarity.color, 24, nextOrder(), true)
	paintRarity(name, "TextColor3", def.rarity)
	local sub = string.upper(def.rarity) .. "  " .. string.upper(def.slot) .. "   LV " .. def.level
	line(card, sub, (Items.gearLevel(data) >= def.level) and GREY or RED, 16, nextOrder())
	line(card, string.rep("\u{2605}", stars) .. string.rep("\u{2606}", 3 - stars) .. (perfect and "   PERFECT" or ""), GOLD, 18, nextOrder())
	line(card, " ", WHITE, 6, nextOrder())
	-- the stats, against what you wear in that slot
	local wornUid = data.Gear[def.slot]
	local wornRec = wornUid ~= uid and wornUid and data.Items[wornUid]
	for _, s in ipairs(Items.Stats) do
		local range = def.stats[s.id]
		local v = rec.r[s.id]
		local other = wornRec and (wornRec.r[s.id] or 0)
		if range or (other and other > 0) then
			local row = new("Frame", { Name = "Row", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = nextOrder(), ZIndex = 51 }, card)
			text(row, { Text = v and Items.formatStat(s.id, v) or ("  " .. s.label), TextColor3 = v and WHITE or DIM, TextSize = 18, Size = UDim2.new(0.62, 0, 1, 0), ZIndex = 51 })
			text(row, { Text = range and ("[" .. range[1] .. "-" .. range[2] .. "]") or "", TextColor3 = DIM, TextSize = 14, Position = UDim2.fromScale(0.6, 0), Size = UDim2.new(0.22, 0, 1, 0), ZIndex = 51 })
			if other then
				local diff = (v or 0) - other
				if diff ~= 0 then
					text(row, {
						Text = (diff > 0 and "\u{25B2}+" or "\u{25BC}") .. tostring(diff),
						TextColor3 = diff > 0 and GREEN or RED,
						TextSize = 16,
						Position = UDim2.fromScale(0.8, 0),
						Size = UDim2.new(0.2, 0, 1, 0),
						TextXAlignment = Enum.TextXAlignment.Right,
						ZIndex = 51,
					})
				end
			end
		end
	end
	-- the set
	if def.set then
		local set = Items.Sets[def.set]
		local _, sets = Items.gearStats(data)
		local have = sets[def.set] or 0
		line(card, " ", WHITE, 6, nextOrder())
		line(card, set.name .. " Set (" .. have .. "/4 worn)", GREEN, 17, nextOrder())
		for _, b in ipairs(set.bonuses) do
			local parts = {}
			for stat, v in pairs(b.stats) do
				table.insert(parts, Items.formatStat(stat, v))
			end
			table.sort(parts)
			line(card, " " .. b.need .. " pieces: " .. table.concat(parts, ", "), have >= b.need and GREEN or DIM, 15, nextOrder(), true)
		end
	end
	line(card, " ", WHITE, 6, nextOrder())
	line(card, def.lore, GREY, 15, nextOrder(), true)
	if rec.lock then
		line(card, "LOCKED", GOLD, 14, nextOrder())
	end
	return rarity
end

----------------------------------------------------------------------
-- The detail panel (right)
----------------------------------------------------------------------
local selected = nil
local hovered = nil
local tab = "All"
local sortMode = 1
local SORTS = { "RARITY", "LEVEL", "NEWEST" }
local lastClick = { uid = nil, at = 0 }
local salvageArmed = nil

local function setStatus(s, color)
	status.Text = s or ""
	status.TextColor3 = color or GREY
end

-- a quick number for how strong your worn gear is, all stats together
local function gearPower(d)
	local t = Items.gearStats(d)
	return math.floor(t.Damage * 2 + t.Crit * 3 + t.Health * 0.5 + t.Defense * 3 + t.Power)
end

local function renderDetail(uid)
	detail:ClearAllChildren()
	local rec = uid and data and data.Items[uid]
	local def = rec and Items.ById[rec.id]
	if not def then
		text(detail, { Text = "* Point at an item\n  to look at it.", TextSize = 20, TextColor3 = DIM, Size = UDim2.new(1, 0, 0, 80), TextWrapped = true, ZIndex = 4 })
		return
	end
	local rarity = Items.RarityById[def.rarity]
	local _, stars, perfect = Items.quality(def, rec.r)
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, detail)
	local o = 0
	local function nextO()
		o = o + 1
		return o
	end
	-- the big icon
	local top = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 170), LayoutOrder = nextO(), ZIndex = 4 }, detail)
	-- the item itself, huge and floating, with a glow of its rarity behind it
	local glow = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = rarity.color, BackgroundTransparency = 0.8, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(170, 170), ZIndex = 4 }, top)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, glow)
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }) }, glow)
	local frame = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(160, 160), ZIndex = 5 }, top)
	local big = itemIcon(def)
	for _, px in ipairs(big:GetDescendants()) do
		if px:IsA("Frame") then
			px.ZIndex = 6
		end
	end
	big.Parent = frame
	-- name, rarity chip, level, stars
	local name = text(detail, { Text = string.upper(def.name), TextSize = 30, TextWrapped = true, Size = UDim2.new(1, 0, 0, 30), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextO(), ZIndex = 4, TextStrokeTransparency = 0.3, TextStrokeColor3 = INK })
	if TITLE_FACE then
		name.FontFace = TITLE_FACE
		name.TextSize = 22
	end
	paintRarity(name, "TextColor3", def.rarity)
	local chipRow = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = nextO(), ZIndex = 4 }, detail)
	local chip = new("TextLabel", { BorderSizePixel = 0, Font = FONT, Text = string.upper(def.rarity), TextSize = 14, TextColor3 = INK, Size = UDim2.fromOffset(96, 22), ZIndex = 5 }, chipRow)
	paintRarity(chip, "BackgroundColor3", def.rarity)
	text(chipRow, { Text = string.upper(def.slot) .. "  LV " .. def.level, TextSize = 15, TextColor3 = (Items.gearLevel(data) >= def.level) and GREY or RED, Position = UDim2.fromOffset(104, 0), Size = UDim2.new(1, -104, 1, 0), ZIndex = 5 })
	text(detail, { Text = string.rep("\u{2605}", stars) .. string.rep("\u{2606}", 3 - stars) .. (perfect and "  PERFECT" or ""), TextSize = 18, TextColor3 = GOLD, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = nextO(), ZIndex = 4 })
	-- each stat with a bar showing how good its roll is (and vs. what you wear)
	local wornUid = data.Gear[def.slot]
	local wornRec = wornUid ~= uid and wornUid and data.Items[wornUid]
	for _, s in ipairs(Items.Stats) do
		local range = def.stats[s.id]
		if range then
			local v = rec.r[s.id]
			local row = new("Frame", { Name = "Row", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = nextO(), ZIndex = 4 }, detail)
			text(row, { Text = Items.formatStat(s.id, v), TextSize = 17, Size = UDim2.new(0.75, 0, 0, 18), ZIndex = 5 })
			if wornRec then
				local diff = v - (wornRec.r[s.id] or 0)
				if diff ~= 0 then
					text(row, { Text = (diff > 0 and "\u{25B2}+" or "\u{25BC}") .. diff, TextSize = 15, TextColor3 = diff > 0 and GREEN or RED, Position = UDim2.fromScale(0.72, 0), Size = UDim2.new(0.28, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5 })
				end
			end
			local track = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = RGB(24, 16, 20), Position = UDim2.fromOffset(0, 21), Size = UDim2.new(1, -44, 0, 8), ZIndex = 5 }, row)
			local span = range[2] - range[1]
			local q = span > 0 and (v - range[1]) / span or 1
			local fill = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = q >= 0.9 and GOLD or WHITE, Size = UDim2.new(0, 0, 1, 0), ZIndex = 6 }, track)
			tween(fill, 0.35, { Size = UDim2.new(math.max(q, 0.04), 0, 1, 0) })
			text(row, { Text = range[1] .. "-" .. range[2], TextSize = 12, TextColor3 = DIM, Position = UDim2.new(1, -40, 0, 17), Size = UDim2.fromOffset(40, 14), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5 })
		end
	end
	-- the set, like enchantments
	if def.set then
		local set = Items.Sets[def.set]
		local _, sets = Items.gearStats(data)
		local have = sets[def.set] or 0
		text(detail, { Text = string.upper(set.name) .. " SET  " .. have .. "/4", TextSize = 15, TextColor3 = GREEN, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = nextO(), ZIndex = 4 })
		for _, b in ipairs(set.bonuses) do
			local parts = {}
			for stat, v in pairs(b.stats) do
				table.insert(parts, Items.formatStat(stat, v))
			end
			table.sort(parts)
			text(detail, { Text = b.need .. ": " .. table.concat(parts, ", "), TextSize = 14, TextColor3 = have >= b.need and GREEN or DIM, TextWrapped = true, Size = UDim2.new(1, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextO(), ZIndex = 4 })
		end
	end
	text(detail, { Text = def.lore, TextSize = 14, TextColor3 = GREY, TextWrapped = true, Size = UDim2.new(1, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextO(), ZIndex = 4 })
end

local function refreshBar()
	local rec = selected and data and data.Items[selected]
	local def = rec and Items.ById[rec.id]
	wearBtn.Visible, lockBtn.Visible, salvageBtn.Visible = def ~= nil, def ~= nil, def ~= nil
	if not def then
		return
	end
	wearBtn.Text = worn(selected) and "OFF" or "WEAR"
	wearBtn.BackgroundColor3 = worn(selected) and SLOT or GREEN
	lockBtn.Text = rec.lock and "UNLOCK" or "LOCK"
	local coins = math.floor(Items.RarityById[def.rarity].salvage * def.floor)
	salvageBtn.Text = salvageArmed == selected and ("+" .. Config.format(coins) .. "?") or "SALVAGE"
end

-- what the right panel shows: what you point at, else what you picked
local function showDetail()
	renderDetail(hovered or selected)
end
local function hideTip()
	hovered = nil
	showDetail()
end

----------------------------------------------------------------------
-- The tiles
----------------------------------------------------------------------
local function slotFrame(parent, def, uid)
	local b = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = TILE, BorderSizePixel = 0, ZIndex = 4 }, parent)
	local edge = new("UIStroke", { Thickness = 3, LineJoinMode = Enum.LineJoinMode.Miter, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	local sc = new("UIScale", {}, b)
	local base = TILE
	if def then
		paintRarity(edge, "Color", def.rarity)
		local ic = itemIcon(def)
		for _, px in ipairs(ic:GetDescendants()) do
			if px:IsA("Frame") then
				px.ZIndex = 6
			end
		end
		ic.Parent = b
		local rec = data.Items[uid]
		local _, stars, perfect = Items.quality(def, rec.r)
		if stars > 0 then
			text(b, { Text = string.rep("\u{2605}", stars), TextSize = 13, TextColor3 = GOLD, Position = UDim2.new(0, 5, 1, -17), Size = UDim2.fromOffset(46, 14), ZIndex = 7 })
		end
		if perfect then
			new("UIGradient", { Color = ColorSequence.new(RGB(255, 255, 255), RGB(254, 231, 97)), Rotation = 45 }, edge)
		end
		if rec.lock then
			text(b, { Text = "L", TextSize = 14, TextColor3 = GOLD, Position = UDim2.new(1, -16, 0, 3), Size = UDim2.fromOffset(12, 14), ZIndex = 7 })
		end
		if worn(uid) then
			local eq = new("TextLabel", { BorderSizePixel = 0, BackgroundColor3 = GREEN, Font = FONT, Text = "E", TextSize = 13, TextColor3 = INK, Position = UDim2.new(1, -20, 1, -20), Size = UDim2.fromOffset(16, 16), ZIndex = 7 }, b)
			eq.Name = "Worn"
		end
		if Items.RarityById[def.rarity].rank >= Items.RarityById.Legendary.rank then
			base = Items.RarityById[def.rarity].color:Lerp(TILE, 0.78)
			b.BackgroundColor3 = base
		end
	else
		edge.Color = RGB(74, 52, 56)
		-- an empty tile: a faint cross, like an empty slot
		for _, r in ipairs({ 45, -45 }) do
			new("Frame", { BorderSizePixel = 0, BackgroundColor3 = RGB(74, 52, 56), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1.1, 0, 0, 3), Rotation = r, ZIndex = 4 }, b)
		end
		b.ClipsDescendants = true
	end
	b.MouseEnter:Connect(function()
		tween(sc, 0.08, { Scale = 1.07 }, Enum.EasingStyle.Back)
		b.BackgroundColor3 = TILE_HOVER
		if uid then
			sound("Hover", 0.2, 1.4)
			hovered = uid
			showDetail()
		end
	end)
	b.MouseLeave:Connect(function()
		tween(sc, 0.1, { Scale = (selected == uid and uid) and 1.04 or 1 })
		b.BackgroundColor3 = base
		if uid and hovered == uid then
			hovered = nil
			showDetail()
		end
	end)
	return b, sc, edge
end

-- the chests tab: a tile per boss's chest
local openChest -- (set below)
local function chestCard(floor, count)
	local card = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = TILE, BorderSizePixel = 0, LayoutOrder = floor, ZIndex = 4 }, grid)
	new("UIStroke", { Color = GOLD, Thickness = 3, LineJoinMode = Enum.LineJoinMode.Miter, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	local ic = chestIcon(floor)
	for _, px in ipairs(ic:GetDescendants()) do
		if px:IsA("Frame") then
			px.ZIndex = 6
		end
	end
	ic.Parent = card
	text(card, { Text = "x" .. count, TextSize = 18, TextColor3 = GOLD, Position = UDim2.new(1, -44, 1, -22), Size = UDim2.fromOffset(40, 18), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 7 })
	local sc = new("UIScale", {}, card)
	card.MouseEnter:Connect(function()
		tween(sc, 0.08, { Scale = 1.07 }, Enum.EasingStyle.Back)
		sound("Hover", 0.2, 1.4)
		setStatus(Items.chestName(floor) .. " - click to open!", GOLD)
	end)
	card.MouseLeave:Connect(function()
		tween(sc, 0.1, { Scale = 1 })
	end)
	return card
end

local function sortedItems()
	local list = {}
	for uid, rec in pairs(data.Items) do
		local def = Items.ById[rec.id]
		if def and (tab == "All" or def.slot == tab) then
			table.insert(list, { uid = uid, rec = rec, def = def })
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = Items.RarityById[a.def.rarity].rank, Items.RarityById[b.def.rarity].rank
		if sortMode == 2 and a.def.level ~= b.def.level then
			return a.def.level > b.def.level
		elseif sortMode == 3 and a.rec.t ~= b.rec.t then
			return a.rec.t > b.rec.t
		end
		if ra ~= rb then
			return ra > rb
		end
		if a.def.order ~= b.def.order then
			return a.def.order < b.def.order
		end
		return a.uid < b.uid
	end)
	return list
end

-- the tabs: pixel icons, like Minecraft Dungeons'
local tabButtons = {}
local function drawTabs()
	for _, b in ipairs(tabButtons) do
		b:Destroy()
	end
	table.clear(tabButtons)
	local chests = 0
	for _, n in pairs(data and data.Chests or {}) do
		chests = chests + n
	end
	local defs = { "All", "Weapon", "Helmet", "Chest", "Boots", "Chests" }
	for i, id in ipairs(defs) do
		local on = tab == id
		local b = button(tabs, id == "All" and "ALL" or "", on and TILE_HOVER or WOOD_DARK, { LayoutOrder = i, Size = UDim2.fromOffset(id == "Chests" and 62 or 46, 42), TextSize = 16, ZIndex = 4, TextColor3 = on and GOLD or WHITE })
		b:FindFirstChildOfClass("UIStroke").Color = on and GOLD or RGB(74, 52, 56)
		if id ~= "All" then
			local ic = id == "Chests" and icon("Treasure", RGB(184, 111, 80), GOLD) or icon(id, on and RGB(192, 203, 220) or GREY, on and GOLD or DIM)
			ic.Size = UDim2.fromOffset(30, 30)
			ic.Position = UDim2.new(0, id == "Chests" and 20 or 23, 0.5, 0)
			for _, px in ipairs(ic:GetDescendants()) do
				if px:IsA("Frame") then
					px.ZIndex = 6
				end
			end
			ic.Parent = b
		end
		if id == "Chests" and chests > 0 then
			text(b, { Text = tostring(chests), TextSize = 15, TextColor3 = RGB(254, 231, 97), Position = UDim2.new(1, -22, 0, 2), Size = UDim2.fromOffset(20, 16), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 7 })
		end
		b.MouseEnter:Connect(function()
			setStatus(({ All = "Everything", Weapon = "Weapons", Helmet = "Helmets", Chest = "Chestplates", Boots = "Boots", Chests = "Treasure chests" })[id])
		end)
		b.Activated:Connect(function()
			if tab ~= id then
				tab = id
				selected = nil
				sound("Click", 0.4, 1.1)
				redraw()
			end
		end)
		table.insert(tabButtons, b)
	end
	local sortBtn = button(tabs, SORTS[sortMode], WOOD_DARK, { LayoutOrder = 20, Size = UDim2.fromOffset(62, 42), TextSize = 12, ZIndex = 4 })
	sortBtn:FindFirstChildOfClass("UIStroke").Color = RGB(74, 52, 56)
	sortBtn.MouseEnter:Connect(function()
		setStatus("Sort by: " .. SORTS[sortMode])
	end)
	sortBtn.Activated:Connect(function()
		sortMode = sortMode % #SORTS + 1
		sound("Click", 0.4, 1.2)
		redraw()
	end)
	table.insert(tabButtons, sortBtn)
end

local function drawLeft()
	for _, f in pairs(wornSlots) do
		f:Destroy()
	end
	table.clear(wornSlots)
	for _, slot in ipairs(Items.Slots) do
		local uid = data.Gear[slot]
		local rec = uid and data.Items[uid]
		local def = rec and Items.ById[rec.id]
		local b = slotFrame(left, def, def and uid)
		b.Position = SLOT_AT[slot]
		b.Size = UDim2.fromOffset(104, 104)
		if not def then
			local ghost = icon(slot, RGB(74, 52, 56), RGB(74, 52, 56))
			ghost.Parent = b
		end
		b.Activated:Connect(function()
			if def then
				selected = uid
				sound("Click", 0.4)
				redraw()
			end
		end)
		wornSlots[slot] = b
	end
	levelText.Text = tostring(Config.levelFromPower(data.Power or 0))
	powerText.Text = tostring(gearPower(data))
	for _, c in ipairs(statsBox:GetChildren()) do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	local total, sets = Items.gearStats(data)
	for _, s in ipairs(Items.Stats) do
		local v = total[s.id]
		text(statsBox, {
			Text = Items.formatStat(s.id, v) .. ((s.cap and v >= s.cap) and " MAX" or ""),
			TextSize = 15,
			TextColor3 = v > 0 and WHITE or DIM,
			LayoutOrder = s.order,
			ZIndex = 4,
		})
	end
	local setLines = {}
	for setId, n in pairs(sets) do
		local set = Items.Sets[setId]
		if set and n >= 2 then
			table.insert(setLines, set.name .. " " .. n .. "/4")
		end
	end
	setsBox.Text = #setLines > 0 and ("SET: " .. table.concat(setLines, ", ")) or ""
end

function redraw()
	if not data or not win.Visible then
		return
	end
	drawTabs()
	drawLeft()
	for _, c in ipairs(grid:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	bagCount.Text = Items.count(data) .. "/" .. Items.BagSize .. " ITEMS"
	coinText.Text = Config.format(data.Coins or 0)
	bagCount.TextColor3 = Items.count(data) >= Items.BagSize and RED or GREY
	if tab == "Chests" then
		local any = false
		for key, n in pairs(data.Chests) do
			local floor = tonumber(key)
			if floor and n > 0 then
				any = true
				chestCard(floor, n).Activated:Connect(function()
					task.spawn(openChest, floor)
				end)
			end
		end
		if not any then
			setStatus("* No chests. Beat a boss in the Spire to earn one!")
		end
	else
		local list = sortedItems()
		for i, e in ipairs(list) do
			local b, sc, edge = slotFrame(grid, e.def, e.uid)
			b.LayoutOrder = i
			if selected == e.uid then
				sc.Scale = 1.04
				edge.Thickness = 5
				local mark = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, 3), Position = UDim2.new(0, 0, 1, 3), ZIndex = 7 }, b)
				mark.Name = "Selected"
			end
			b.Activated:Connect(function()
				local now = os.clock()
				if lastClick.uid == e.uid and now - lastClick.at < 0.35 then
					-- double-click: wear it (or take it off)
					lastClick.uid = nil
					selected = e.uid
					local slot = worn(e.uid)
					local ok, msg
					if slot then
						ok, msg = ask("UnequipSlot", slot)
					else
						ok, msg = ask("EquipItem", e.uid)
					end
					if ok then
						sound("Equip", 0.8)
					else
						setStatus(msg, RED)
					end
					return
				end
				lastClick.uid, lastClick.at = e.uid, now
				selected = e.uid
				salvageArmed = nil
				sound("Click", 0.4)
				setStatus("")
				redraw()
			end)
		end
		for i = #list + 1, math.max(#list, 16) do
			slotFrame(grid, nil, nil).LayoutOrder = i
		end
		if #list == 0 then
			setStatus(tab == "All" and "* Your bag is empty. Open a chest!" or "* Nothing for this slot yet.")
		end
	end
	showDetail()
	refreshBar()
end

-- the buttons under the item
wearBtn.Activated:Connect(function()
	if not selected then
		return
	end
	local slot = worn(selected)
	local ok, msg
	if slot then
		ok, msg = ask("UnequipSlot", slot)
	else
		ok, msg = ask("EquipItem", selected)
	end
	if ok then
		sound("Equip", 0.8)
		local def = Items.ById[data.Items[selected] and data.Items[selected].id or ""]
		local w = def and wornSlots[def.slot]
		if w then
			local s = w:FindFirstChildOfClass("UIScale")
			if s then
				s.Scale = 1.3
				tween(s, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		end
		setStatus(slot and "Taken off." or "Wearing it!", slot and GREY or GREEN)
	else
		setStatus(msg, RED)
	end
end)
lockBtn.Activated:Connect(function()
	if selected then
		local ok, msg = ask("LockItem", selected)
		if ok then
			sound("Click", 0.5, 0.8)
		else
			setStatus(msg, RED)
		end
	end
end)
salvageBtn.Activated:Connect(function()
	if not selected then
		return
	end
	if salvageArmed ~= selected then
		salvageArmed = selected
		setStatus("Click again to salvage it for coins.", GOLD)
		refreshBar()
		task.delay(2.5, function()
			if salvageArmed then
				salvageArmed = nil
				refreshBar()
			end
		end)
		return
	end
	salvageArmed = nil
	local ok, msg = ask("SalvageItem", selected)
	if ok then
		sound("Salvage", 0.8)
		setStatus("Salvaged for " .. Config.format(msg) .. " coins.", GOLD)
		selected = nil
	else
		setStatus(msg, RED)
	end
	refreshBar()
end)

-- your avatar turns slowly while the window is open
RunService.RenderStepped:Connect(function(dt)
	if win.Visible and avatar then
		avatarAngle = avatarAngle + dt * 0.6
		local c = CFrame.new(0, 0.4, 0)
		viewCam.CFrame = CFrame.lookAt((c * CFrame.Angles(0, math.sin(avatarAngle * 0.5) * 0.6, 0) * CFrame.new(0, 0.8, 12)).Position, c.Position)
	end
end)

----------------------------------------------------------------------
-- Opening and closing the window
----------------------------------------------------------------------
local function openWindow()
	if win.Visible then
		return
	end
	win.Visible, dim.Visible = true, true
	buildAvatar()
	winScale.Scale = 1.04
	tween(winScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Quad)
	dim.BackgroundTransparency = 1
	tween(dim, 0.2, { BackgroundTransparency = 0.5 })
	sound("Click", 0.5, 0.9)
	-- straight to the chests if any are waiting
	local waiting = 0
	for _, n in pairs(data and data.Chests or {}) do
		waiting = waiting + n
	end
	if waiting > 0 then
		tab = "Chests"
	end
	selected = nil
	setStatus("")
	redraw()
end
local function closeWindow()
	if not win.Visible then
		return
	end
	hideTip()
	tween(winScale, 0.12, { Scale = 0.9 })
	tween(dim, 0.12, { BackgroundTransparency = 1 })
	task.delay(0.12, function()
		win.Visible, dim.Visible = false, false
	end)
end
gearBtn.Activated:Connect(function()
	tween(gearScale, 0.05, { Scale = 0.92 })
	task.delay(0.05, function()
		tween(gearScale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	if win.Visible then
		closeWindow()
	else
		openWindow()
	end
end)
gearBtn.MouseEnter:Connect(function()
	tween(gearScale, 0.08, { Scale = 1.05 })
	sound("Hover", 0.25, 1.3)
end)
gearBtn.MouseLeave:Connect(function()
	tween(gearScale, 0.1, { Scale = 1 })
end)
closeBtn.Activated:Connect(closeWindow)
dim.Activated:Connect(closeWindow)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.G then
		if win.Visible then
			closeWindow()
		else
			openWindow()
		end
	elseif input.KeyCode == Enum.KeyCode.Escape then
		closeWindow()
	end
end)

----------------------------------------------------------------------
-- THE CHEST REVEAL
----------------------------------------------------------------------
local revealing = false
function openChest(floor)
	if revealing then
		return
	end
	revealing = true
	hideTip()
	local ok, result = ask("OpenChest", floor)
	if not ok then
		setStatus(result, RED)
		revealing = false
		return
	end
	local rec = result.item
	local def = Items.ById[rec.id]
	local rarity = Items.RarityById[def.rarity]
	local rank = rarity.rank
	local secret = rarity.secret
	local color = rarity.color

	local over = new("Frame", { BackgroundColor3 = BLACK, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 60, Active = true }, scaler)
	tween(over, 0.25, { BackgroundTransparency = secret and 0 or 0.25 })
	-- the chest
	local holder = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(220, 220), ZIndex = 62 }, over)
	local chestArt = chestIcon(floor)
	chestArt.Size = UDim2.fromScale(1, 1)
	chestArt.Parent = holder
	for _, px in ipairs(chestArt:GetDescendants()) do
		if px:IsA("Frame") then
			px.ZIndex = 63
		end
	end
	local holderScale = new("UIScale", { Scale = 0 }, holder)
	tween(holderScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	-- light rays behind it, in the colour of what's inside
	local rays = {}
	for i = 1, 8 do
		local r = new("Frame", {
			BorderSizePixel = 0,
			BackgroundColor3 = secret and WHITE or color,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(14, 260),
			Rotation = i * 45,
			ZIndex = 61,
		}, over)
		table.insert(rays, r)
	end
	local label = text(over, { Text = Items.chestName(floor), TextSize = 26, TextColor3 = GOLD, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 140), Size = UDim2.fromOffset(600, 30), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 64 })

	task.wait(0.35)
	-- the build-up: longer, harder shaking, and the light leaking out, the rarer it is
	local shakes = 3 + rank * 2
	local interval = math.max(0.05, 0.16 - rank * 0.012)
	if secret then
		label.Text = "* ..."
		label.TextColor3 = WHITE
		task.wait(1.2)
		label.Text = "* something stirs inside."
		task.wait(1)
	end
	for i = 1, shakes do
		local k = i / shakes
		holder.Position = UDim2.new(0.5, math.random(-6, 6) * (0.4 + k), 0.5, math.random(-4, 4) * (0.4 + k))
		holder.Rotation = math.random(-6, 6) * k
		sound("Shake", 0.3, 0.9 + k * 0.8)
		for j, r in ipairs(rays) do
			r.BackgroundTransparency = 1 - math.min(0.75, k * (rank >= 4 and 0.9 or 0.5))
			r.Rotation = j * 45 + i * 3
		end
		if rank >= 5 and i == math.floor(shakes * 0.6) then
			-- the good stuff: a beat of slow motion before it bursts
			task.wait(0.35)
		end
		task.wait(interval)
	end
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Rotation = 0

	-- the burst
	local flash = new("Frame", { BackgroundColor3 = secret and WHITE or color:Lerp(WHITE, 0.5), BackgroundTransparency = 0, Size = UDim2.fromScale(1, 1), ZIndex = 70 }, over)
	tween(flash, 0.5, { BackgroundTransparency = 1 })
	holder.Visible = false
	for _, r in ipairs(rays) do
		tween(r, 0.6, { Size = UDim2.fromOffset(20, 520), BackgroundTransparency = rank >= 4 and 0.4 or 0.7 })
	end
	-- pixel sparks
	for i = 1, 10 + rank * 4 do
		local a = math.random() * math.pi * 2
		local d = 120 + math.random() * 220
		local sq = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = (i % 3 == 0) and WHITE or (secret and Color3.fromHSV(math.random(), 0.6, 1) or color), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(10, 10), ZIndex = 66 }, over)
		tween(sq, 0.7, { Position = UDim2.new(0.5, math.cos(a) * d, 0.5, math.sin(a) * d), BackgroundTransparency = 1, Size = UDim2.fromOffset(4, 4) })
	end
	if rank >= 5 then
		sound("Reveal", 0.8)
	end

	-- the item card
	local card = box(over, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 150), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 72 }, color, 5)
	paintRarity(card:FindFirstChildOfClass("UIStroke"), "Color", def.rarity)
	new("UIPadding", { PaddingTop = UDim.new(0, 120), PaddingBottom = UDim.new(0, 70), PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }, card)
	new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, card)
	local big = itemIcon(def)
	big.AnchorPoint = Vector2.new(0.5, 0)
	big.Position = UDim2.new(0.5, 0, 0, -106)
	big.Size = UDim2.fromOffset(100, 100)
	local bigHolder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 0, ZIndex = 73 }, card)
	big.Parent = bigHolder
	for _, px in ipairs(big:GetDescendants()) do
		if px:IsA("Frame") then
			px.ZIndex = 74
		end
	end
	data.Items[result.uid] = data.Items[result.uid] or rec -- (the snapshot may still be on its way)
	fillCard(card, result.uid)
	for _, c in ipairs(card:GetDescendants()) do
		if c:IsA("TextLabel") then
			c.ZIndex = 74
		elseif c:IsA("Frame") and c.Name == "Row" then
			c.ZIndex = 74
		end
	end
	local rarityTag = text(over, { Text = string.upper(def.rarity) .. "!", TextSize = rank >= 5 and 44 or 32, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.5, -200), Size = UDim2.fromOffset(600, 50), ZIndex = 75, TextStrokeTransparency = 0, TextStrokeColor3 = INK })
	if TITLE_FACE then
		rarityTag.FontFace = TITLE_FACE
	end
	paintRarity(rarityTag, "TextColor3", def.rarity)
	label.Visible = false
	local cardScale = new("UIScale", { Scale = 0.2 }, card)
	tween(cardScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	local tagScale = new("UIScale", { Scale = 2.5 }, rarityTag)
	tween(tagScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)

	-- WEAR / KEEP
	local done = false
	local btnRow = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(300, 46), ZIndex = 75 }, card)
	local wear = button(btnRow, "WEAR", GREEN, { Size = UDim2.fromOffset(140, 44), ZIndex = 76 })
	local keep = button(btnRow, "KEEP", SLOT, { Position = UDim2.fromOffset(160, 0), Size = UDim2.fromOffset(140, 44), ZIndex = 76 })
	local canWear = Items.gearLevel(data) >= def.level
	if not canWear then
		wear.Text = "LV " .. def.level
		wear.BackgroundColor3 = SLOT
		wear.TextColor3 = DIM
	end
	local function finish()
		if done then
			return
		end
		done = true
		tween(over, 0.2, { BackgroundTransparency = 1 })
		tween(cardScale, 0.18, { Scale = 0 })
		tween(tagScale, 0.18, { Scale = 0 })
		task.delay(0.22, function()
			over:Destroy()
			revealing = false
			redraw()
		end)
	end
	wear.Activated:Connect(function()
		if canWear then
			local okE = ask("EquipItem", result.uid)
			if okE then
				sound("Equip", 0.8)
			end
		end
		finish()
	end)
	keep.Activated:Connect(finish)
end

----------------------------------------------------------------------
-- Keeping up with the server
----------------------------------------------------------------------
-- a fingerprint of everything the bag shows: the snapshot arrives many
-- times a second while you train, but the bag only redraws when this changes
local function fingerprint(d)
	local parts = {}
	for uid, rec in pairs(d.Items) do
		table.insert(parts, uid .. (rec.lock and "L" or ""))
	end
	table.sort(parts)
	for _, slot in ipairs(Items.Slots) do
		table.insert(parts, slot .. "=" .. tostring(d.Gear[slot]))
	end
	for key, n in pairs(d.Chests) do
		table.insert(parts, "c" .. key .. "=" .. n)
	end
	table.insert(parts, "lv" .. tostring(Items.gearLevel(d)))
	return table.concat(parts, ",")
end
local lastPrint = nil
local lastChests = nil
local function onState(d)
	data = d
	data.Items = data.Items or {}
	data.Gear = data.Gear or {}
	data.Chests = data.Chests or {}
	local chests = 0
	for _, n in pairs(data.Chests) do
		chests = chests + n
	end
	badge.Visible = chests > 0
	badge.Text = tostring(chests)
	if lastChests and chests > lastChests then
		-- a new chest: the button jumps
		gearScale.Scale = 1.25
		tween(gearScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Elastic)
	end
	lastChests = chests
	local print_ = fingerprint(data)
	if print_ ~= lastPrint and not revealing then
		lastPrint = print_
		redraw()
	end
end
Remotes:WaitForChild("StateUpdate").OnClientEvent:Connect(onState)
local req = Remotes:FindFirstChild("RequestState")
if req then
	req:FireServer()
end
