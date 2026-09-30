--[[
	ArcadeClient  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "ArcadeClient")

	THE ARCADE on your screen (the spins themselves are decided by the
	server: ArcadeService; the numbers: Config.Arcade; the building:
	ArcadeBuilder), drawn in the old-computer window look
	(ReplicatedStorage/WindowKit).

	  * THE MENU: walk into the Arcade and it opens (once - close it and it
	    stays closed until you walk out and back in), or press the ROLL
	    button on the left, or your token counter. One card per machine on
	    the left; the one you pick shows its six weapons with their real odds,
	    which ones you own, the pity bar ("a Legendary or better in 12
	    spins"), your first spin's promise, and SPIN x1 / SPIN x10. A machine
	    you haven't opened says whose boss opens it; outside the lobby you
	    can look but not spin.
	  * THE SPIN: the camera flies beside that machine, your token flicks
	    from your hand into its coin slot and its lever comes down; then the
	    camera flies right up to the machine's own screen, where a strip of
	    weapon tiles (filled using the real odds) races past and slows down
	    onto what the server already picked - the view rumbling while it
	    races, going still in the silence, and jolting on the landing (a
	    Legendary or better rattles the whole machine). Tap to skip. The landing gets
	    bigger with the rarity: a blip for a Common, flashing lights for an
	    Epic, a full-screen reveal for a Legendary or better, rainbows for a
	    Secret. Then your weapon turns in 3D, with EQUIP / SPIN AGAIN / DONE.
	    Ten at once: a quick spin onto the best, then all ten in a grid.
	  * THE MUSIC: the Arcade has its own 8-bit song (the lobby's steps aside
	    while you're in there, in the menu or spinning). While the strip
	    spins the song plays faster, like a slot machine's, over a drum roll
	    that builds; just before it lands everything drops out (a heartbeat
	    instead, when it's landing on a Legendary or better), then the
	    landing: a plink for a Common up to the jackpots - glass smashing,
	    alarm bells and a shower of coins - and the song comes back. It all
	    follows the server's real result: no fake near-misses.
	  * FOR EVERYONE: when anyone spins, that machine's screen lights up and
	    their result floats over it (and you hear it, if you're near); a
	    Secret puts a banner on every screen, with its jackpot; the BIG WINS
	    board at the back lists the lobby's latest Legendary-or-better
	    spins; the Slime machine's Secret weapon turns over the prize
	    pedestal.
	  * THE TOKEN MACHINE: walk up to it for "Get Tokens" (the Robux shop,
	    later; for now it says where free tokens come from).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local A = Config.Arcade
local W = Config.Weapons
if not A then
	return
end
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Action = Remotes:WaitForChild("Action")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- the weapons' icons (their real pictures, uploaded: AssetIds.Icons)
local AssetIds = nil
pcall(function()
	AssetIds = require(ReplicatedStorage:WaitForChild("AssetIds", 5))
end)
-- a weapon's icon as an image, or nil if it hasn't been uploaded yet
local function iconFor(def, id, size)
	local icons = type(AssetIds) == "table" and AssetIds.Icons
	local n = icons and ((def and def.Model and icons[def.Model]) or icons[id])
	if not n then
		return nil
	end
	size = size or 150
	return "rbxthumb://type=Asset&id=" .. tostring(n) .. "&w=" .. size .. "&h=" .. size
end

-- (every icon starts downloading as soon as you join, not the first time
-- it's shown - otherwise the strip and the cards sit blank for a moment)
task.spawn(function()
	local icons = type(AssetIds) == "table" and AssetIds.Icons
	if not icons then
		return
	end
	local list = {}
	for _, n in pairs(icons) do
		table.insert(list, "rbxthumb://type=Asset&id=" .. tostring(n) .. "&w=150&h=150")
	end
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync(list)
	end)
end)

local WeaponFX = nil -- (for the weapons in 3D: loaded when first needed)
local function weaponFX()
	if WeaponFX == nil then
		local ok, mod = pcall(function()
			return require(ReplicatedStorage:WaitForChild("WeaponFX", 5))
		end)
		WeaponFX = ok and mod or false
	end
	return WeaponFX or nil
end

local RGB = Color3.fromRGB
local FONT = Enum.Font.FredokaOne
local INK = RGB(24, 20, 37)
local NIGHT = RGB(38, 43, 68)
local SLATE = RGB(58, 68, 102)
local PURPLE = RGB(104, 56, 108)
local MAGENTA = RGB(181, 80, 136)
local YELLOW = RGB(254, 231, 97)
local GOLD = RGB(254, 174, 52)
local GREEN = RGB(99, 199, 77)
local RED = RGB(228, 59, 68)
local WHITE = RGB(255, 255, 255)
local GREY = RGB(139, 155, 180)
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, RGB(255, 0, 68)),
	ColorSequenceKeypoint.new(0.2, RGB(247, 118, 34)),
	ColorSequenceKeypoint.new(0.4, RGB(254, 231, 97)),
	ColorSequenceKeypoint.new(0.6, RGB(99, 199, 77)),
	ColorSequenceKeypoint.new(0.8, RGB(44, 232, 245)),
	ColorSequenceKeypoint.new(1, RGB(181, 80, 136)),
})

local TILE_SIZE = 150 -- a weapon tile on the spinning strip and in the grid of ten
local state = nil -- the latest snapshot of your data from the server
local busy = false -- a spin is being asked for or shown
local inArcade = false -- you're standing in the Arcade (the walk-in zones, at the bottom)
local pullLever -- (the machine's lever: below)

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
local function tween(inst, t, props, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
local function text(parent, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = WHITE,
		TextScaled = true,
		TextStrokeColor3 = INK,
		TextStrokeTransparency = 0.4,
	}, parent)
	for k, v in pairs(props) do
		l[k] = v
	end
	return l
end
local function stroke(parent, color, thickness)
	return new("UIStroke", { Color = color or WHITE, Thickness = thickness or 3, LineJoinMode = Enum.LineJoinMode.Miter, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end
local function corner(parent, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, parent)
end
-- a round purple token with a gold rim and a star
local function tokenIcon(parent, size, props)
	local f = new("Frame", { Size = UDim2.fromOffset(size, size), BackgroundColor3 = GOLD, BorderSizePixel = 0 }, parent)
	corner(f, math.floor(size / 2))
	stroke(f, INK, math.max(2, size / 16))
	local inner = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.72, 0.72), BackgroundColor3 = PURPLE, BorderSizePixel = 0 }, f)
	corner(inner, math.floor(size / 2))
	text(inner, { Text = "★", TextColor3 = YELLOW, Size = UDim2.fromScale(1, 1), TextStrokeTransparency = 1 })
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	return f
end
local function rarityColor(rarity)
	return A.Colors[rarity] or WHITE
end
-- a Secret's name (or border) runs through the rainbow
local rainbows = {} -- [UIGradient] = true (turned every frame)
local function rainbow(parent)
	local g = new("UIGradient", { Color = RAINBOW }, parent)
	rainbows[g] = true
	return g
end

-- a rarity's gem: a diamond in its colour (a Secret's runs through the
-- rainbow), for a weapon whose model isn't to hand (the strip's tiles)
local function gem(parent, rarity, size, props)
	local g = new("Frame", {
		Name = "Gem",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		Rotation = 45,
		BackgroundColor3 = rarityColor(rarity),
		BorderSizePixel = 0,
	}, parent)
	stroke(g, INK, math.max(2, size / 14))
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.36, 0.36), Size = UDim2.fromScale(0.3, 0.3), BackgroundColor3 = WHITE, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = (props and props.ZIndex or 1) + 1 }, g)
	if rarity == "Secret" then
		rainbow(g)
	end
	for k, v in pairs(props or {}) do
		g[k] = v
	end
	return g
end

local function squash(s)
	return string.lower((string.gsub(tostring(s), "[%s_%-]", "")))
end
-- a Sound in SoundService by name (the first of `names` that's there), or
-- nil (not the copies playing: they're marked)
local function findSound(names)
	for _, name in ipairs(type(names) == "table" and names or { names }) do
		local want = squash(name)
		for _, s in ipairs(SoundService:GetChildren()) do
			if s:IsA("Sound") and squash(s.Name) == want and not s:GetAttribute("ArcadeCopy") then
				return s
			end
		end
	end
	return nil
end
-- plays a sound from SoundService by name (the first of `names` that's
-- there; silent if none): the same wherever you are, or from a part in the
-- world (`at`: quieter the further away you are). `from`: start this many
-- seconds in. Returns the copy that's playing.
local function play(names, pitch, volume, from, at)
	local s = findSound(names)
	if not s then
		return nil
	end
	local c = s:Clone()
	c:SetAttribute("ArcadeCopy", true)
	c.Looped = false
	c.PlaybackSpeed = (tonumber(s.PlaybackSpeed) or 1) * (pitch or 1)
	c.Volume = (tonumber(s.Volume) or 0.5) * (volume or 1)
	if from and from > 0 then
		c.TimePosition = from
	end
	if at then
		c.RollOffMode = Enum.RollOffMode.InverseTapered
		c.RollOffMinDistance = 14
		c.RollOffMaxDistance = 130
	end
	c.Parent = at or SoundService
	c:Play()
	c.Ended:Connect(function()
		c:Destroy()
	end)
	task.delay(12, function()
		c:Destroy()
	end)
	return c
end
-- stops a sound that play() started (fading it out over `seconds`)
local function hush(c, seconds)
	if not (c and c.Parent) then
		return
	end
	if seconds and seconds > 0 then
		tween(c, seconds, { Volume = 0 })
		task.delay(seconds, function()
			c:Destroy()
		end)
	else
		c:Destroy()
	end
end
-- what you hear when a spin lands, by rarity (Config.Arcade.LandSounds: up
-- to the jackpots; the older sounds until those are uploaded)
local landSounds
do
	local LAND_OLD = {
		Common = { "Orb Land", "UI Blip" },
		Rare = { "Orb Land", "UI Blip" },
		Epic = { "Level Complete", "Orb Land" },
		Legendary = { "Legendary Reveal", "Level Complete" },
		Mythic = { "Legendary Reveal", "Level Complete" },
		Secret = { "Legendary Reveal", "Level Complete" },
	}
	function landSounds(rarity)
		local list = {}
		local new = (A.LandSounds or {})[rarity]
		if new then
			table.insert(list, new)
		end
		for _, name in ipairs(LAND_OLD[rarity] or LAND_OLD.Common) do
			table.insert(list, name)
		end
		return list
	end
end

local function inLobby()
	local f = player:GetAttribute("SpireFloor")
	return (f == nil or f == 0) and not player:GetAttribute("Colosseum") and not player:GetAttribute("Intro")
end

local function tokens()
	return state and tonumber(state.Tokens) or 0
end

-- the machines in the order they stand: the launch packs by floor, then the covered ones
local MACHINES = {}
do
	local packs = {}
	for _, p in ipairs(W.Packs or {}) do
		if A.Machines[p.Id] then
			table.insert(packs, p)
		end
	end
	table.sort(packs, function(a, b)
		return a.Floor < b.Floor
	end)
	for _, p in ipairs(packs) do
		table.insert(MACHINES, { id = p.Id, pack = p, machine = A.Machines[p.Id] })
	end
	for _, s in ipairs(A.Soon or {}) do
		table.insert(MACHINES, { id = s.Id, soon = s })
	end
end
local function machineEntry(id)
	for _, e in ipairs(MACHINES) do
		if e.id == id then
			return e
		end
	end
	return nil
end

-- the weapons of a machine, Common first
local function dropsOf(id)
	local out = {}
	for _, rarity in ipairs(A.Order) do
		local wid = Config.arcadeWeapon(id, rarity)
		if wid then
			table.insert(out, { id = wid, rarity = rarity, def = W.List[wid] })
		end
	end
	return out
end

local function ownedLevel(id)
	local own = state and state.Weapons and state.Weapons.own
	local points = own and own[id]
	if points == nil then
		return nil
	end
	return (Config.masteryLevel(points))
end

-- a weapon, in 3D, standing up: its voxel model (or nothing yet, if the
-- server hasn't loaded it)
local function weaponModel(def)
	local fx = weaponFX()
	if not (fx and fx.buildVoxel and def) then
		return nil
	end
	local ok, model, handle = pcall(fx.buildVoxel, def, false)
	if not ok or not model or not handle then
		return nil
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide, d.CanTouch, d.CanQuery = false, false, false
		elseif d:IsA("Trail") or d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
	model.PrimaryPart = handle
	return model
end

-- (a held weapon's tip points down its handle's -Z; this turns it to point
-- up) Where the middle of the standing weapon is from its handle, and how
-- big it is - for turning it round its middle.
local STAND = CFrame.Angles(math.rad(90), 0, 0)
local function standInfo(model)
	model:PivotTo(STAND)
	local box, size = model:GetBoundingBox()
	return box.Position, size
end
-- the weapon standing with its middle at `centre`, turned `angle` round
local function standAt(model, centre, offset, angle)
	model:PivotTo(CFrame.new(centre) * CFrame.Angles(0, angle, 0) * CFrame.new(-offset) * STAND)
end

----------------------------------------------------------------------
-- The screen
----------------------------------------------------------------------
local gui = new("ScreenGui", { Name = "Arcade", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 43, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
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

-- THE ROLL BUTTON: a square beside WEAPONS (the left buttons' empty corner)
local rollBtn = new("TextButton", {
	Name = "RollButton",
	AutoButtonColor = false,
	BackgroundColor3 = NIGHT,
	BorderSizePixel = 0,
	Position = UDim2.new(0, 16 + 112 + 10, 0.44, 5),
	Size = UDim2.fromOffset(112, 112),
	Text = "",
}, scaler)
stroke(rollBtn, INK, 4)
local rollScale = new("UIScale", {}, rollBtn)
do
	local face = new("Frame", { BackgroundColor3 = MAGENTA, BorderSizePixel = 0, Position = UDim2.fromOffset(6, 5), Size = UDim2.new(1, -12, 1, -13) }, rollBtn)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(RGB(255, 90, 170), RGB(104, 56, 108)) }, face)
	tokenIcon(face, 50, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10) })
	text(face, { Text = "Roll", TextScaled = false, TextSize = 22, Position = UDim2.new(0, 0, 1, -30), Size = UDim2.new(1, 0, 0, 28), TextStrokeTransparency = 0 }) -- (like WEAPONS)
end
local rollBadge = text(rollBtn, {
	Name = "Badge",
	Text = "0",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 8, 0, -8),
	Size = UDim2.fromOffset(44, 26),
	BackgroundTransparency = 0,
	BackgroundColor3 = GOLD,
	TextColor3 = INK,
	TextStrokeTransparency = 1,
	ZIndex = 5,
	Visible = false,
})
corner(rollBadge, 12)
stroke(rollBadge, INK, 2.5)

-- THE WINDOW, in the old-computer window look (ReplicatedStorage/WindowKit):
-- a lavender window with a magenta title bar and a hard shadow, over a
-- purple grid
local WK = require(ReplicatedStorage:WaitForChild("WindowKit"))
local WC = WK.COLORS
local dim = WK.backdrop(scaler, { Name = "Dim", Visible = false, ZIndex = 1 })
local win, closeBtn
do
	local parts = WK.window(scaler, {
		Name = "Window",
		Title = "THE ARCADE",
		Icon = tokenIcon(nil, 32),
		Color = WC.Magenta,
		BarHeight = 44,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(980, 680),
		ZIndex = 1,
		Visible = false,
	})
	win, closeBtn = parts.frame, parts.close
end
local winScale = new("UIScale", {}, win)
-- the toolbar: your tokens (like an address bar) and GET TOKENS
local tokenPill = WK.panel(win, { Name = "Tokens", Position = UDim2.fromOffset(20, 60), Size = UDim2.fromOffset(280, 46), ZIndex = 3 })
tokenIcon(tokenPill, 36, { Position = UDim2.fromOffset(6, 5), ZIndex = 4 })
WK.label(tokenPill, { Text = "ARCADE TOKENS", Font = WK.TITLE_FONT, TextScaled = false, TextSize = 11, TextColor3 = WC.Muted, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(52, 5), Size = UDim2.new(1, -60, 0, 14), ZIndex = 4 })
local tokenText = WK.label(tokenPill, { Text = "0", Font = WK.TITLE_FONT, TextScaled = false, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(52, 20), Size = UDim2.new(1, -60, 0, 22), ZIndex = 4 })
local getBtn = WK.button(win, "+ GET TOKENS", WC.Teal, { Name = "GetTokens", Position = UDim2.fromOffset(316, 60), Size = UDim2.fromOffset(230, 46), ZIndex = 4 })
WK.label(win, { -- (a note beside them)
	Text = "Every drop's real chance is shown. No tricks!",
	TextColor3 = WC.Muted,
	TextXAlignment = Enum.TextXAlignment.Right,
	Position = UDim2.new(1, -420, 0, 70),
	Size = UDim2.fromOffset(400, 26),
	ZIndex = 3,
})
-- the status bar along the bottom: the rules, or what just happened
local footer = new("Frame", { Name = "StatusBar", BackgroundColor3 = WC.Sunken, BorderSizePixel = 0, Position = UDim2.new(0, 12, 1, -44), Size = UDim2.new(1, -24, 0, 32), ZIndex = 3 }, win)
WK.outline(footer, WC.Ink, 2)
footer = WK.label(footer, {
	Text = "The odds shown are the real chances. Your first spin is Rare or better, and a Legendary or better is guaranteed within "
		.. A.Pity .. " spins on a machine.",
	TextColor3 = WC.Muted,
	Position = UDim2.fromOffset(12, 5),
	Size = UDim2.new(1, -24, 1, -10),
	ZIndex = 4,
})

-- the machines, down the left
local list = new("ScrollingFrame", {
	Name = "Machines",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(20, 120),
	Size = UDim2.fromOffset(282, 506),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 10,
	ScrollBarImageColor3 = WC.Magenta,
	ZIndex = 3,
}, win)
new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)

-- the chosen machine, on the right: a box with a strip in the machine's colour
local detail = WK.panel(win, { Name = "Detail", Position = UDim2.fromOffset(318, 120), Size = UDim2.fromOffset(642, 506), ZIndex = 3 }, GREEN, 42)
local detailStrip = detail:FindFirstChild("Strip")
local dTitle = WK.label(detail, { Text = "", Font = WK.TITLE_FONT, TextColor3 = WHITE, TextStrokeTransparency = 0, TextScaled = false, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -32, 0, 42), ZIndex = 5 })
local dSub = WK.label(detail, { Text = "", TextColor3 = WC.Muted, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(16, 50), Size = UDim2.new(1, -32, 0, 22), ZIndex = 4 })
local rows = {}
for i = 1, 6 do
	local r = new("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, Position = UDim2.fromOffset(14, 80 + (i - 1) * 44), Size = UDim2.fromOffset(614, 38), ZIndex = 4 }, detail)
	WK.outline(r, WC.Ink, 2)
	local bar = new("Frame", { BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromOffset(10, 38), ZIndex = 5 }, r)
	rows[i] = {
		frame = r,
		bar = bar,
		rarity = WK.label(r, { Font = WK.TITLE_FONT, BackgroundTransparency = 0, Position = UDim2.fromOffset(18, 6), Size = UDim2.fromOffset(112, 26), ZIndex = 5 }),
		icon = new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Position = UDim2.fromOffset(138, 1), Size = UDim2.fromOffset(36, 36), ScaleType = Enum.ScaleType.Fit, ZIndex = 5, Visible = false }, r),
		gem = new("Frame", { Name = "Gem", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(156, 19), Size = UDim2.fromOffset(16, 16), Rotation = 45, BorderSizePixel = 0, ZIndex = 5 }, r),
		name = WK.label(r, { Position = UDim2.fromOffset(182, 6), Size = UDim2.fromOffset(170, 26), TextScaled = false, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 }),
		kind = WK.label(r, { Position = UDim2.fromOffset(354, 8), Size = UDim2.fromOffset(80, 22), TextScaled = false, TextSize = 16, TextColor3 = WC.Muted, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 }),
		odds = WK.label(r, { Position = UDim2.fromOffset(432, 6), Size = UDim2.fromOffset(62, 26), TextScaled = false, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5 }),
		owned = WK.label(r, { Position = UDim2.fromOffset(500, 8), Size = UDim2.fromOffset(106, 22), TextScaled = false, TextSize = 15, TextColor3 = RGB(46, 140, 46), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5 }),
	}
	rows[i].pillEdge = WK.outline(rows[i].rarity, WC.Ink, 2)
	new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }, rows[i].rarity)
	stroke(rows[i].gem, INK, 2)
end
local pityLabel = WK.label(detail, { Text = "", Position = UDim2.fromOffset(16, 344), Size = UDim2.new(1, -32, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
local pityBar = WK.progress(detail, { Name = "Pity", Color = WC.Magenta, Position = UDim2.fromOffset(16, 366), Size = UDim2.new(1, -32, 0, 20), ZIndex = 4 })
local pityBack = pityBar.frame
local firstLabel = WK.label(detail, { Text = "★ YOUR FIRST SPIN IS RARE OR BETTER! ★", Font = WK.TITLE_FONT, BackgroundTransparency = 0, BackgroundColor3 = WC.Orange, TextColor3 = WHITE, TextStrokeTransparency = 0, Position = UDim2.fromOffset(16, 392), Size = UDim2.new(1, -32, 0, 26), ZIndex = 4, Visible = false })
WK.outline(firstLabel, WC.Ink, 2)
new("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5) }, firstLabel)
local spin1 = WK.button(detail, "SPIN x1", WC.Magenta, { Name = "Spin1", Position = UDim2.fromOffset(16, 436), Size = UDim2.fromOffset(294, 56), ZIndex = 5 })
local spin10 = WK.button(detail, "SPIN x10", WC.Violet, { Name = "Spin10", Position = UDim2.fromOffset(326, 436), Size = UDim2.fromOffset(294, 56), ZIndex = 5 })
-- (ten cost less than ten ones: the ribbon says how many are free)
local freeTag = text(spin10, { Name = "Free", Text = "1 FREE!", Font = WK.TITLE_FONT, TextScaled = false, TextSize = 14, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 24, 0, -16), Size = UDim2.fromOffset(122, 28), Rotation = 8,
	BackgroundTransparency = 0, BackgroundColor3 = YELLOW, TextColor3 = INK, TextStrokeTransparency = 1, ZIndex = 7 })
stroke(freeTag, INK, 2.5)
local lockLabel = WK.label(detail, { Text = "", BackgroundTransparency = 0, BackgroundColor3 = WC.Sunken, Position = UDim2.fromOffset(16, 436), Size = UDim2.fromOffset(604, 56), ZIndex = 5, Visible = false })
WK.outline(lockLabel, WC.Ink, 2)
new("UIPadding", { PaddingTop = UDim.new(0.22, 0), PaddingBottom = UDim.new(0.22, 0), PaddingLeft = UDim.new(0.03, 0), PaddingRight = UDim.new(0.03, 0) }, lockLabel)
-- what just happened, in the status bar (over the rules while it's showing)
local message = WK.label(win, { Text = "", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -39), Size = UDim2.new(1, -48, 0, 22), TextColor3 = WHITE, TextStrokeTransparency = 0, ZIndex = 6 })

local selected = MACHINES[1] and MACHINES[1].id or nil
local cards = {} -- [id] = the card on the left

local function say(textValue, color)
	message.Text = textValue or ""
	message.TextColor3 = color or WHITE
	message.TextTransparency, message.TextStrokeTransparency = 0, 0
	footer.Visible = (textValue or "") == ""
	local mine = textValue
	task.delay(3.5, function()
		if message.Text == mine then
			tween(message, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
			task.delay(0.4, function()
				if message.Text == mine then
					footer.Visible = true
				end
			end)
		end
	end)
end

----------------------------------------------------------------------
-- Filling the menu in
----------------------------------------------------------------------
local refresh -- (below)

for i, e in ipairs(MACHINES) do
	local color = e.machine and e.machine.Light or GREY
	-- (a little window: a strip in the machine's colour with its name; the
	-- button itself is see-through, holding the face and its hard shadow)
	local card = new("TextButton", { Name = e.id, Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.new(1, -14, 0, 84), LayoutOrder = i, ZIndex = 4 }, list)
	new("Frame", { Name = "Shadow", BackgroundColor3 = WC.Ink, BorderSizePixel = 0, Position = UDim2.fromOffset(5, 5), Size = UDim2.new(1, -5, 1, -5), ZIndex = 4 }, card)
	local face = new("Frame", { Name = "Face", BackgroundColor3 = WC.Panel, BorderSizePixel = 0, Size = UDim2.new(1, -5, 1, -5), ZIndex = 5 }, card)
	local edge = WK.outline(face, WC.Ink, 3)
	local strip = new("Frame", { Name = "Strip", BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 30), ZIndex = 6 }, face)
	new("Frame", { BackgroundColor3 = WC.Ink, BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 2), ZIndex = 6 }, strip)
	local name = WK.label(face, { Text = string.upper(e.id), Font = WK.TITLE_FONT, TextColor3 = WHITE, TextStrokeTransparency = 0, TextScaled = false, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 0, 30), ZIndex = 7 })
	local sub = WK.label(face, { Text = "", TextColor3 = WC.Muted, TextScaled = false, TextSize = 18, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(10, 36), Size = UDim2.new(1, -20, 0, 36), ZIndex = 6 })
	cards[e.id] = { card = card, face = face, edge = edge, name = name, sub = sub }
	card.Activated:Connect(function()
		selected = e.id
		play({ "UI Blip" }, 1.1, 0.6)
		refresh()
	end)
end

refresh = function()
	local t = tokens()
	tokenText.Text = tostring(t)
	rollBadge.Text = tostring(t)
	rollBadge.Visible = t > 0
	local spins = state and state.Arcade and tonumber(state.Arcade.spins) or 0
	for _, e in ipairs(MACHINES) do
		local c = cards[e.id]
		if e.soon then
			c.sub.Text = "Coming soon"
		else
			local open = Config.arcadeOpen(state or {}, e.id)
			c.sub.Text = open and (e.machine.Price .. (e.machine.Price == 1 and " token a spin" or " tokens a spin")) or ("Beat " .. e.pack.Boss .. " to open")
		end
		local picked = e.id == selected
		c.edge.Color = picked and WC.Magenta or WC.Ink
		c.edge.Thickness = picked and 4 or 3
		c.face.BackgroundColor3 = picked and RGB(255, 232, 250) or WC.Panel
	end
	local e = machineEntry(selected)
	if not e then
		return
	end
	local light = e.machine and e.machine.Light or GREY
	dTitle.Text = string.upper(e.id) .. " MACHINE"
	if detailStrip then
		detailStrip.BackgroundColor3 = light
	end
	if e.soon then
		dSub.Text = e.soon.Boss .. "'s pack - coming in an update!"
	else
		dSub.Text = e.pack.Boss .. "'s pack  -  Spire floor " .. e.pack.Floor
	end
	local drops = e.soon and {} or dropsOf(e.id)
	for i, r in ipairs(rows) do
		local d = drops[i]
		r.frame.Visible = d ~= nil
		if d then
			local col = rarityColor(d.rarity)
			r.bar.BackgroundColor3 = col
			r.rarity.Text = string.upper(d.rarity)
			-- (a pill in its colour: white words on the strong colours)
			r.rarity.BackgroundColor3 = col
			local strong = d.rarity == "Rare" or d.rarity == "Epic" or d.rarity == "Mythic"
			r.rarity.TextColor3 = strong and WHITE or INK
			r.rarity.TextStrokeTransparency = strong and 0 or 1
			if d.rarity == "Secret" and not r.rainbow then
				r.rainbow = rainbow(r.pillEdge) -- (its outline runs through the rainbow)
				r.pillEdge.Thickness = 3
			elseif d.rarity ~= "Secret" and r.rainbow then
				r.pillEdge.Thickness = 2
				rainbows[r.rainbow] = nil
				r.rainbow:Destroy()
				r.rainbow = nil
			end
			r.name.Text = d.def and d.def.Name or d.id
			local icon = iconFor(d.def, d.id)
			r.icon.Image = icon or ""
			r.icon.Visible = icon ~= nil
			r.gem.Visible = icon == nil
			r.gem.BackgroundColor3 = col
			r.kind.Text = d.def and d.def.Type or ""
			r.odds.Text = tostring(A.Odds[d.rarity] or 0) .. "%"
			local lv = ownedLevel(d.id)
			r.owned.Text = lv and ("OWNED Lv " .. lv) or ""
		end
	end
	local pity = state and state.Arcade and state.Arcade.pity and tonumber(state.Arcade.pity[e.id]) or 0
	local left = math.max(1, A.Pity - pity)
	pityLabel.Visible = not e.soon
	pityBack.Visible = not e.soon
	pityLabel.Text = "A LEGENDARY OR BETTER IN " .. left .. (left == 1 and " SPIN" or " SPINS") .. " (at most)"
	pityBar:set(pity / A.Pity)
	firstLabel.Visible = not e.soon and spins == 0
	-- what the buttons can do
	local open, why = false, nil
	if e.soon then
		why = "COMING SOON"
	else
		open, why = Config.arcadeOpen(state or {}, e.id)
		if open and not inLobby() then
			open, why = false, "Go to the Arcade in the lobby to spin!"
		end
	end
	spin1.Visible, spin10.Visible = open, open
	lockLabel.Visible = not open
	lockLabel.Text = why or ""
	if open then
		local m = e.machine
		spin1.Text = "SPIN x1\n" .. m.Price .. (m.Price == 1 and " TOKEN" or " TOKENS")
		spin10.Text = "SPIN x10\n" .. m.Ten .. " TOKENS"
		local free = math.floor((m.Price * 10 - m.Ten) / m.Price)
		freeTag.Visible = free > 0
		freeTag.Text = free .. " FREE!"
		spin1.BackgroundColor3 = t >= m.Price and WC.Magenta or WC.Off
		spin10.BackgroundColor3 = t >= m.Ten and WC.Violet or WC.Off
	end
end

local function openMenu()
	if player:GetAttribute("Intro") then
		return false
	end
	if not win.Visible then
		win.Visible, dim.Visible = true, true
		winScale.Scale = 0.85
		tween(winScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		play({ "UI Blip" }, 1, 0.7)
	end
	refresh()
	return true
end
local function closeMenu()
	win.Visible, dim.Visible = false, false
end
closeBtn.Activated:Connect(closeMenu)
dim.Activated:Connect(closeMenu)
rollBtn.Activated:Connect(function()
	rollScale.Scale = 0.9
	tween(rollScale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	if win.Visible then
		closeMenu()
	else
		openMenu()
	end
end)
rollBtn.MouseEnter:Connect(function()
	tween(rollScale, 0.12, { Scale = 1.06 })
end)
rollBtn.MouseLeave:Connect(function()
	tween(rollScale, 0.12, { Scale = 1 })
end)

-- where tokens come from (the Robux shop goes here later)
local function showTokens()
	openMenu()
	say("Quests give a token every " .. (Config.Quests.Hours or 6) .. " hours, and every boss gives tokens the first time you beat it. Token packs are coming soon!", GOLD)
end
getBtn.Activated:Connect(showTokens)

-- anything else can open the menu (the HUD's token counter does)
do
	local signal = ReplicatedStorage:FindFirstChild("ArcadeOpen")
	if not signal then
		signal = Instance.new("BindableEvent")
		signal.Name = "ArcadeOpen"
		signal.Parent = ReplicatedStorage
	end
	signal.Event:Connect(function(page)
		if page == "Tokens" then
			showTokens()
		else
			openMenu()
		end
	end)
end

----------------------------------------------------------------------
-- The machines in the world (everyone's screen)
----------------------------------------------------------------------
local cabinets = {} -- [machine id] = { model, screen, back, title, status, marquee }
local function trackCabinet(m)
	if not m:IsA("Model") then
		return
	end
	local id = m:GetAttribute("Machine")
	local screen = m:FindFirstChild("Screen")
	local gui2 = screen and screen:FindFirstChildOfClass("SurfaceGui")
	local back = gui2 and gui2:FindFirstChild("Back")
	cabinets[id] = {
		model = m,
		soon = m:GetAttribute("Soon") == true,
		screen = screen,
		back = back,
		title = back and back:FindFirstChild("Title"),
		status = back and back:FindFirstChild("Status"),
		marquee = m:FindFirstChild("Marquee"),
		flashUntil = 0,
	}
end
for _, m in ipairs(CollectionService:GetTagged("ArcadeCabinet")) do
	trackCabinet(m)
end
CollectionService:GetInstanceAddedSignal("ArcadeCabinet"):Connect(trackCabinet)

-- what each machine's screen says when nobody's spinning (yours: locked or not)
local function attract(c, id, blink)
	if not c.status or not c.back or os.clock() < c.flashUntil then
		return
	end
	c.back.BackgroundColor3 = INK
	if c.soon then
		return
	end
	local open = Config.arcadeOpen(state or {}, id)
	if open then
		c.status.Text = blink and "INSERT TOKEN" or ""
		c.status.TextColor3 = WHITE
	else
		c.status.Text = "LOCKED"
		c.status.TextColor3 = RED
	end
end

-- somebody's result floating up over their machine
local function floatOver(c, line, color, isSecret)
	local anchor = c.marquee or c.screen
	if not anchor then
		return
	end
	local bb = new("BillboardGui", { Name = "ArcadeWin", Size = UDim2.fromScale(12, 2.2), StudsOffset = Vector3.new(0, 3.2, 0), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 160, Adornee = anchor }, anchor)
	local l = text(bb, { Text = line, Size = UDim2.fromScale(1, 1), TextColor3 = color, TextStrokeTransparency = 0 })
	if isSecret then
		rainbow(l)
	end
	tween(bb, 4, { StudsOffset = Vector3.new(0, 6.5, 0) }, Enum.EasingStyle.Linear)
	task.delay(3, function()
		tween(l, 1, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
	task.delay(4.1, function()
		bb:Destroy()
	end)
end

-- the banner on every screen when anyone spins a Secret
-- (a little window, its title bar running through the rainbow)
local banner, bannerText
do
	local parts = WK.window(scaler, { Name = "SecretBanner", Title = "★ SECRET! ★", Color = WHITE, BarHeight = 36, TitleSize = 16, Buttons = false, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -130), Size = UDim2.fromOffset(820, 90), ZIndex = 20 })
	banner = parts.frame
	banner.Active = false
	rainbow(parts.bar)
	parts.title.TextXAlignment = Enum.TextXAlignment.Center
	parts.title.Position, parts.title.Size = UDim2.fromOffset(16, 0), UDim2.new(1, -32, 0, 36)
	bannerText = WK.label(banner, { Text = "", Position = UDim2.fromOffset(16, 45), Size = UDim2.new(1, -32, 0, 36), ZIndex = 23 })
end
local function secretBanner(line, mine)
	bannerText.Text = line
	banner.Position = UDim2.new(0.5, 0, 0, -130)
	tween(banner, 0.5, { Position = UDim2.new(0.5, 0, 0, 18) }, Enum.EasingStyle.Back)
	if not mine then -- (with its jackpot, straight to the smash; yours you heard already)
		play({ (A.LandSounds or {}).Secret or "Jackpot Secret", "Legendary Reveal", "Level Complete" }, 1, 0.7, findSound((A.LandSounds or {}).Secret or "Jackpot Secret") and 0.6 or 0)
	end
	task.delay(6, function()
		if bannerText.Text == line then
			tween(banner, 0.4, { Position = UDim2.new(0.5, 0, 0, -130) })
		end
	end)
end

-- the best of a list of results ({ id, rarity })
local RANK = {}
for i, r in ipairs(A.Order) do
	RANK[r] = i
end
local function best(list)
	local top = nil
	for _, r in ipairs(list or {}) do
		if not top or (RANK[r.rarity] or 0) > (RANK[top.rarity] or 0) then
			top = r
		end
	end
	return top
end

-- the lobby hears about every spin (the server's "ArcadeEvent", hooked up
-- below once it's there)
local event = nil
-- A spin on a machine, as the lobby sees it: its screen flashes through the
-- rarities, lands on the result, and the result floats up over it (a
-- Secret: a banner on every screen too). Two spins on one machine take turns.
-- Somebody else's is heard from their machine too (ticking, then what they
-- landed: a jackpot rings out across the Arcade); yours isn't - you've
-- just heard it.
local function announce(c, name, top, mine)
	local def = W.List[top.id]
	local weaponName = def and def.Name or top.id
	local color = rarityColor(top.rarity)
	local rank = RANK[top.rarity] or 1
	local from = not mine and c.screen or nil
	c.flashUntil = os.clock() + 6
	if not mine then
		pullLever(c)
	end
	for i = 1, 14 do
		if c.back then
			c.back.BackgroundColor3 = rarityColor(A.Order[(i % #A.Order) + 1])
			if c.status then
				c.status.Text = "SPINNING!"
				c.status.TextColor3 = WHITE
			end
		end
		if from and i % 2 == 1 then
			play({ "Roll Tick", "UI Blip" }, 0.9 + i * 0.03, 0.4, nil, from)
		end
		task.wait(0.09)
	end
	if from and top.rarity ~= "Secret" then -- (a Secret's is the banner's)
		play(landSounds(top.rarity), 1, rank >= 4 and 0.9 or 0.6, nil, from)
	end
	if c.back then
		c.back.BackgroundColor3 = INK
		if c.status then
			c.status.Text = string.upper(top.rarity) .. "!"
			c.status.TextColor3 = color
		end
	end
	floatOver(c, tostring(name) .. ": " .. string.upper(top.rarity) .. " " .. weaponName .. "!", color, top.rarity == "Secret")
	if top.rarity == "Secret" then
		secretBanner("★ " .. tostring(name) .. " just spun a SECRET: " .. weaponName .. "! ★", mine)
	end
	c.flashUntil = os.clock() + 4 -- (the result stays up a while)
end
local function onRoll(userId, name, machineId, shown)
	local c = cabinets[machineId]
	local top = best(shown)
	if not (c and c.back and top) then
		return
	end
	-- (yours shows once your own spin has played; everyone else's straight away)
	task.delay(userId == player.UserId and 4 or 0, function()
		c.queue = c.queue or {}
		table.insert(c.queue, { name = name, top = top, mine = userId == player.UserId })
		if c.playing then
			return
		end
		c.playing = true
		while #c.queue > 0 do
			local e = table.remove(c.queue, 1)
			announce(c, e.name, e.top, e.mine)
			if #c.queue > 0 then
				task.wait(1.6) -- (a moment on each result before the next)
			end
		end
		c.playing = false
	end)
end
-- THE BIG WINS board: the lobby's latest Legendary-or-better spins (kept by
-- the server on the ArcadeEvent: "name|rarity|weapon;...")
local function showWins()
	local raw = event and event:GetAttribute("BigWins")
	if type(raw) ~= "string" or raw == "" then
		return
	end
	local lines = {}
	for entry in string.gmatch(raw, "[^;]+") do
		local who, rarity, wid = string.match(entry, "^(.-)|(.-)|(.-)$")
		local def = wid and W.List[wid]
		if who then
			table.insert(lines, who .. "  -  " .. string.upper(rarity) .. " " .. (def and def.Name or tostring(wid)))
		end
	end
	for _, board in ipairs(CollectionService:GetTagged("ArcadeWins")) do
		local g = board:FindFirstChildOfClass("SurfaceGui")
		local l = g and g:FindFirstChild("Lines")
		if l then
			l.Text = table.concat(lines, "\n")
		end
	end
end
local function hookEvent(ev)
	if event or not ev then
		return
	end
	event = ev
	ev.OnClientEvent:Connect(function(kind, ...)
		if kind == "Roll" then
			onRoll(...)
		end
	end)
	ev:GetAttributeChangedSignal("BigWins"):Connect(showWins)
	showWins()
end
hookEvent(ReplicatedStorage:FindFirstChild("ArcadeEvent"))
if not event then
	task.spawn(function()
		hookEvent(ReplicatedStorage:WaitForChild("ArcadeEvent", 120))
	end)
end

-- THE PRIZE PEDESTAL: the machine's Secret weapon turns over it
local prizes = {} -- [pedestal] = { model, base }
local function placePrize(base)
	if prizes[base] and prizes[base].model and prizes[base].model.Parent then
		return
	end
	local id = Config.arcadeWeapon(base:GetAttribute("Machine") or "Slime", "Secret")
	local def = id and W.List[id]
	local model = weaponModel(def)
	if not model then
		return
	end
	model.Name = "PrizeWeapon"
	local offset, size = standInfo(model)
	model.Parent = Workspace
	prizes[base] = { model = model, base = base, offset = offset, size = size }
	if not base:FindFirstChild("PrizeSign") then
		local bb = new("BillboardGui", { Name = "PrizeSign", Size = UDim2.fromScale(9, 2.4), StudsOffset = Vector3.new(0, 7.5, 0), LightInfluence = 0, MaxDistance = 90, Adornee = base }, base)
		local top = text(bb, { Text = "SECRET", Size = UDim2.fromScale(1, 0.5), TextStrokeTransparency = 0 })
		rainbow(top)
		text(bb, { Text = def.Name .. "  -  " .. tostring(A.Odds.Secret) .. "%", Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(1, 0.5), TextStrokeTransparency = 0 })
	end
end
local function tryPrizes()
	for _, base in ipairs(CollectionService:GetTagged("ArcadePrize")) do
		placePrize(base)
	end
end
tryPrizes()
CollectionService:GetInstanceAddedSignal("ArcadePrize"):Connect(placePrize)
task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("WeaponModels", 60)
	if folder then
		folder.ChildAdded:Connect(function()
			task.defer(tryPrizes)
		end)
		tryPrizes()
	end
end)

-- THE TOKEN MACHINE: "Get Tokens"
local function hookTokenMachine(m)
	local body = m:IsA("Model") and m:FindFirstChild("Body")
	if not body or body:FindFirstChildOfClass("ProximityPrompt") then
		return
	end
	local pp = new("ProximityPrompt", { ActionText = "Get Tokens", ObjectText = "Token Machine", HoldDuration = 0, MaxActivationDistance = 12, RequiresLineOfSight = false }, body)
	pp.Triggered:Connect(showTokens)
end
for _, m in ipairs(CollectionService:GetTagged("ArcadeTokens")) do
	hookTokenMachine(m)
end
CollectionService:GetInstanceAddedSignal("ArcadeTokens"):Connect(hookTokenMachine)

-- the lights: bulbs chasing round the roof, the screens blinking, the
-- prize turning, Secret names running through the rainbow
local bulbs = {}
local function trackBulb(b)
	if b:IsA("BasePart") then
		bulbs[b] = b:GetAttribute("Index") or 0
	end
end
for _, b in ipairs(CollectionService:GetTagged("ArcadeBulb")) do
	trackBulb(b)
end
CollectionService:GetInstanceAddedSignal("ArcadeBulb"):Connect(trackBulb)

local lightClock, step = 0, 0
RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	for g in pairs(rainbows) do
		if g.Parent then
			g.Offset = Vector2.new(math.sin(t * 1.5) * 0.4, 0)
			g.Rotation = (t * 40) % 360
		else
			rainbows[g] = nil
		end
	end
	for base, p in pairs(prizes) do
		if p.model and p.model.Parent and base.Parent then
			-- (the pedestal is a cylinder on its side: its height is its X)
			local centre = base.Position + Vector3.new(0, base.Size.X / 2 + 1 + p.size.Y / 2 + math.sin(t * 1.6) * 0.3, 0)
			standAt(p.model, centre, p.offset, t * 0.9)
		end
	end
	lightClock = lightClock + dt
	if lightClock < 0.12 then
		return
	end
	lightClock = 0
	step = step + 1
	for b, i in pairs(bulbs) do
		if b.Parent then
			b.Color = ((i + step) % 3 == 0) and YELLOW or GOLD
			b.Transparency = ((i + step) % 3 == 0) and 0 or 0.35
		else
			bulbs[b] = nil
		end
	end
	local blink = (step % 10) < 6
	for id, c in pairs(cabinets) do
		if c.model.Parent then
			attract(c, id, blink)
		else
			cabinets[id] = nil
		end
	end
end)

----------------------------------------------------------------------
-- THE SPIN
----------------------------------------------------------------------
local show = new("Frame", { Name = "Show", BackgroundColor3 = RGB(0, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 10, Active = true }, scaler)
local flash = new("Frame", { Name = "Flash", BackgroundColor3 = WHITE, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 30 }, show)
-- THE MACHINE'S OWN SCREEN: the spin plays on the machine itself (a
-- SurfaceGui laid over its Screen - only on your screen), and the camera
-- flies right up to it. Its title bar is in the machine's colour; the strip
-- races across the middle; under it, what it landed on.
local SCR = {}
SCR.gui = new("SurfaceGui", { Name = "ArcadeSpinScreen", Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.FixedSize, CanvasSize = Vector2.new(860, 600), LightInfluence = 0, Brightness = 1.6, ZOffset = 2, ResetOnSpawn = false, Enabled = false }, playerGui)
SCR.frame = new("Frame", { Name = "Screen", BackgroundColor3 = INK, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, SCR.gui)
SCR.bar = new("Frame", { Name = "TitleBar", BackgroundColor3 = GREEN, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 96), ZIndex = 2 }, SCR.frame)
new("Frame", { BackgroundColor3 = WC.Ink, BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 6), ZIndex = 2 }, SCR.bar)
SCR.title = text(SCR.bar, { Text = "", Font = WK.TITLE_FONT, Position = UDim2.fromOffset(24, 18), Size = UDim2.new(1, -48, 1, -36), TextStrokeTransparency = 0, ZIndex = 3 })
local window = new("Frame", { Name = "Strip", Position = UDim2.fromOffset(40, 200), Size = UDim2.fromOffset(780, 180), BackgroundColor3 = NIGHT, BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 2 }, SCR.frame)
WK.outline(window, WC.Ink, 4)
local strip = new("Frame", { Name = "Tiles", BackgroundTransparency = 1, Size = UDim2.fromOffset(10, 180), ZIndex = 3 }, window)
new("Frame", { Name = "Marker", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(6, 180), BackgroundColor3 = YELLOW, BorderSizePixel = 0, ZIndex = 6 }, window)
do
	local markerTop = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 190), Size = UDim2.fromOffset(32, 32), Rotation = 45, BackgroundColor3 = YELLOW, BorderSizePixel = 0, ZIndex = 6 }, SCR.frame)
	stroke(markerTop, INK, 3)
end
SCR.status = text(SCR.frame, { Name = "Status", Text = "", Font = WK.TITLE_FONT, Position = UDim2.fromOffset(30, 420), Size = UDim2.new(1, -60, 0, 110), TextColor3 = YELLOW, TextStrokeTransparency = 0, ZIndex = 2 })
local skipHint = text(show, { Text = "TAP TO SKIP", Font = WK.TITLE_FONT, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), Size = UDim2.fromOffset(300, 24), TextColor3 = WHITE, TextStrokeTransparency = 0, ZIndex = 12 })
-- the reveal card: a window whose title bar says the rarity, in its colour
local card, cardBar, cardRarity, cardClose
do
	local parts = WK.window(show, { Name = "Card", Title = "", Color = WHITE, BarHeight = 50, TitleSize = 24, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(560, 560), ZIndex = 20, Visible = false })
	card, cardBar, cardRarity, cardClose = parts.frame, parts.bar, parts.title, parts.close
end
local cardEdgeRainbow = nil
local cardScale = new("UIScale", {}, card)
-- (the rays shine out from behind the window)
local rays = new("Frame", { Name = "Rays", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.38), Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 1, ZIndex = 19 }, card)
for i = 1, 10 do
	new("Frame", { Name = "Ray", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(34, 900), Rotation = i * 18, BackgroundColor3 = YELLOW, BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = 19 }, rays)
end
local cardRarityRainbow = nil
local view = new("ViewportFrame", { Name = "View", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 64), Size = UDim2.fromOffset(280, 260), BackgroundTransparency = 1, ZIndex = 23, LightColor = WHITE, Ambient = RGB(200, 200, 210) }, card)
local viewCam = new("Camera", { FieldOfView = 40 }, view)
view.CurrentCamera = viewCam
local cardGem = nil -- (the rarity's gem, while the weapon's model isn't to hand)
local cardName = WK.label(card, { Text = "", Position = UDim2.fromOffset(20, 330), Size = UDim2.new(1, -40, 0, 46), ZIndex = 23 })
local cardType = WK.label(card, { Text = "", Position = UDim2.fromOffset(20, 378), Size = UDim2.new(1, -40, 0, 24), TextColor3 = WC.Muted, ZIndex = 23 })
local cardNote = WK.label(card, { Text = "", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 412), Size = UDim2.fromOffset(400, 38), BackgroundTransparency = 0, BackgroundColor3 = GREEN, TextColor3 = WHITE, TextStrokeTransparency = 0, ZIndex = 23 })
WK.outline(cardNote, WC.Ink, 2.5)
new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, cardNote)
local CARD_BUTTON = { TextScaled = false, TextSize = 14, Size = UDim2.fromOffset(164, 62), ZIndex = 24 }
local function cardButton(label, color, x)
	local b = WK.button(card, label, color, CARD_BUTTON)
	b.Position = UDim2.fromOffset(x, 474)
	return b
end
local equipBtn = cardButton("EQUIP", WC.Teal, 20)
local againBtn = cardButton("SPIN AGAIN", WC.Magenta, 198)
local doneBtn = cardButton("DONE", nil, 376)
-- ten at once: a grid, in a window of its own
local grid, gridTitle, gridClose
do
	local parts = WK.window(show, { Name = "Grid", Title = "", Color = WC.Violet, BarHeight = 48, TitleSize = 20, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48), Size = UDim2.fromOffset(900, 540), ZIndex = 20, Visible = false })
	grid, gridTitle, gridClose = parts.frame, parts.title, parts.close
end
-- (five across, two down: each tile has what it gave under it, in the gap)
local gridCells = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(31, 70), Size = UDim2.fromOffset(838, 364), ZIndex = 22 }, grid)
new("UIGridLayout", { CellSize = UDim2.fromOffset(TILE_SIZE, TILE_SIZE), CellPadding = UDim2.fromOffset(22, 34), SortOrder = Enum.SortOrder.LayoutOrder }, gridCells)
local gridAgain = WK.button(grid, "SPIN x10 AGAIN", WC.Magenta, { Position = UDim2.new(0.5, -310, 1, -82), Size = UDim2.fromOffset(300, 60), ZIndex = 23 })
local gridDone = WK.button(grid, "DONE", nil, { Position = UDim2.new(0.5, 10, 1, -82), Size = UDim2.fromOffset(300, 60), ZIndex = 23 })

local TILE, GAP = TILE_SIZE, 12
local skipping = false
local lastRoll = nil -- { machine, count, results }

local function tileFor(parent, wid, rarity, x)
	local def = W.List[wid]
	local col = rarityColor(rarity)
	local f = new("Frame", { Position = UDim2.fromOffset(x, 15), Size = UDim2.fromOffset(TILE, TILE), BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 14 }, parent)
	corner(f, 10)
	local edge = stroke(f, col, 5)
	if rarity == "Secret" then
		rainbow(edge)
	end
	text(f, { Text = string.upper(rarity), Position = UDim2.fromOffset(6, 4), Size = UDim2.new(1, -12, 0, 18), TextColor3 = col, ZIndex = 15 })
	local icon = iconFor(def, wid)
	if icon then
		new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = icon, ScaleType = Enum.ScaleType.Fit, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(TILE / 2, 61), Size = UDim2.fromOffset(84, 84), ZIndex = 15 }, f)
	else
		gem(f, rarity, 46, { Position = UDim2.fromOffset(TILE / 2, 61), ZIndex = 15 })
	end
	text(f, { Text = def and def.Name or wid, Position = UDim2.fromOffset(6, 104), Size = UDim2.new(1, -12, 0, 26), ZIndex = 15, TextWrapped = true })
	text(f, { Text = def and string.upper(def.Type) or "", Position = UDim2.fromOffset(6, 130), Size = UDim2.new(1, -12, 0, 14), TextColor3 = GREY, TextStrokeTransparency = 1, ZIndex = 15 })
	return f
end

-- a random weapon from the machine by its real odds (the strip's filler)
local fillRng = Random.new()
local function randomDrop(machineId)
	local x = fillRng:NextNumber() * 100
	for _, r in ipairs(A.Order) do
		x = x - (A.Odds[r] or 0)
		if x < 0 then
			return Config.arcadeWeapon(machineId, r), r
		end
	end
	return Config.arcadeWeapon(machineId, "Common"), "Common"
end

----------------------------------------------------------------------
-- THE MUSIC (Config.Arcade.Music; the sounds are made by
-- Tools/Sounds/arcade_sfx.py). The Arcade's own song plays while you're in
-- the Arcade, in its menu or spinning (the lobby's song fades out under it).
-- A spin: the song plays faster while the strip races, over a drum roll
-- that builds; everything drops out just before it lands (into a heartbeat,
-- when it's landing on a Legendary or better); then the landing's sound, and
-- the song comes back once that's rung out. All of it follows the result
-- the server already picked - nothing is faked.
----------------------------------------------------------------------
local MUSIC = A.Music or {}
local CUE = {
	riser = 3.3, -- Spin Riser's length (timed to end as everything goes quiet)
	quiet = 0.45, -- seconds of silence before the strip lands...
	heart = 1.6, -- ...or of heartbeat, when it's a Legendary or better
	secretLead = 0.6, -- (Jackpot Secret's swell starts this long before the landing)
	volume = { Common = 0.7, Rare = 0.8, Epic = 0.9, Legendary = 1, Mythic = 1, Secret = 1 },
	hold = { Common = 0.7, Rare = 1.2, Epic = 1.8, Legendary = 3.6, Mythic = 4.4, Secret = 5.8 }, -- (then the song)
}

local tune = {
	sound = nil, -- the song playing (a copy of Music.Song)
	playing = false,
	level = 0, -- how loud it is now (0 to 1)
	speed = 1, -- how fast
	spinning = false, -- the strip is racing: faster
	cut = false, -- dropped out (it's about to land)
	quietUntil = 0, -- silent until then (a landing ringing out)
	duck = 0, -- how far the lobby's song is turned down
	ducked = false,
	last = nil, -- the last spin's cue
}
do
	local songTemplate, songLooked = nil, -10
	local function songSound()
		if songTemplate and songTemplate.Parent then
			return songTemplate
		end
		if os.clock() - songLooked > 2 then -- (until it's uploaded, a look every 2 seconds)
			songLooked = os.clock()
			songTemplate = findSound(MUSIC.Song or "Arcade Theme")
		end
		return songTemplate
	end
	local function musicGroup()
		local g = SoundService:FindFirstChild("ArcadeMusic")
		if not (g and g:IsA("SoundGroup")) then
			g = Instance.new("SoundGroup")
			g.Name = "ArcadeMusic"
			g.Volume = (Config.Audio and Config.Audio.Music) or 0.7
			g.Parent = SoundService
		end
		return g
	end
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		local template = songSound()
		local want = template ~= nil and inLobby() and not player:GetAttribute("Intro") and (inArcade or win.Visible or show.Visible)
		if want and not tune.sound then
			tune.sound = template:Clone()
			tune.sound.Name = "ArcadeSongPlaying"
			tune.sound:SetAttribute("ArcadeCopy", true)
			tune.sound.Looped = true
			tune.sound.Volume = 0
			tune.sound.SoundGroup = musicGroup()
			tune.sound.Parent = SoundService
			tune.sound:Play()
			tune.playing = true
		end
		local silent = tune.cut or now < tune.quietUntil
		local goal = (want and not silent) and 1 or 0
		local rate = goal > tune.level and 1.2 or (silent and 12 or 1.6) -- (in over a second; out fast when it drops out)
		tune.level = tune.level + (goal - tune.level) * math.min(1, dt * rate)
		if silent then
			tune.speed = 1 -- (it comes back at its own speed)
		else
			local fast = tune.spinning and (MUSIC.SpinSpeed or 1.25) or 1
			tune.speed = tune.speed + (fast - tune.speed) * math.min(1, dt * 3)
		end
		local s = tune.sound
		if s then
			s.Volume = (tonumber(template and template.Volume) or 0.5) * (MUSIC.Volume or 0.6) * tune.level
			s.PlaybackSpeed = (tonumber(template and template.PlaybackSpeed) or 1) * tune.speed
			if not want and tune.level < 0.01 and tune.playing then
				s:Pause() -- (it carries on where it left off next time)
				tune.playing = false
			elseif want and not tune.playing then
				s:Resume()
				tune.playing = true
			end
		end
		-- the lobby's song (the "Music" SoundGroup) steps aside while ours is on
		local duckGoal = (want and s) and 1 or 0
		tune.duck = tune.duck + (duckGoal - tune.duck) * math.min(1, dt * 1.5)
		local lobby = SoundService:FindFirstChild("Music")
		if lobby and lobby:IsA("SoundGroup") then
			local full = (Config.Audio and Config.Audio.Music) or 1
			if tune.duck > 0.01 then
				lobby.Volume = full * (1 - tune.duck)
				tune.ducked = true
			elseif tune.ducked then
				lobby.Volume = full
				tune.ducked = false
			end
		end
	end)
end

-- (the sounds start downloading as soon as you join: a jackpot that's still
-- loading when it lands would come in late)
task.spawn(function()
	task.wait(3)
	local list = {}
	local names = { MUSIC.Song or "Arcade Theme", MUSIC.Riser or "Spin Riser", MUSIC.Heartbeat or "Heartbeat", "Token Clunk", "Roll Tick" }
	for _, name in pairs(A.LandSounds or {}) do
		table.insert(names, name)
	end
	for _, name in ipairs(names) do
		local snd = findSound(name)
		if snd then
			table.insert(list, snd)
		end
	end
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync(list)
	end)
end)

-- a spin's music, timed from when it lands (`seconds` from now): faster,
-- with the drum roll building under it
local function spinCue(top, seconds)
	if tune.last then
		hush(tune.last.sting, 0.3) -- (the last landing, if it's still ringing)
	end
	local cue = { rarity = top.rarity, rank = RANK[top.rarity] or 1 }
	cue.big = cue.rank >= 4
	cue.quiet = cue.big and CUE.heart or CUE.quiet
	cue.lead = (top.rarity == "Secret" and findSound((A.LandSounds or {}).Secret or "Jackpot Secret")) and CUE.secretLead or 0
	tune.spinning, tune.cut = true, false
	local run = seconds - cue.quiet
	if run > 0.3 then
		cue.riser = play({ MUSIC.Riser or "Spin Riser" }, 1, 0.7, math.max(0, CUE.riser - run))
	end
	tune.last = cue
	return cue
end
-- as the strip goes (`left`: seconds until it lands): the silence, the
-- heartbeat, and a Secret's jackpot starting early (its swell)
local function cueAt(cue, left)
	if not cue.quieted and left <= cue.quiet then
		cue.quieted = true
		tune.cut = true
		hush(cue.riser, 0.06)
		if cue.big then
			cue.heart = play({ MUSIC.Heartbeat or "Heartbeat" }, 1, 1, math.max(0, CUE.heart - left))
		end
	end
	if cue.lead > 0 and not cue.sting and left <= cue.lead then
		cue.sting = play(landSounds(cue.rarity), 1, CUE.volume[cue.rarity], math.max(0, cue.lead - left))
	end
end
-- it's landed (`skipped`: tapped through): its sound, then the song again
-- once that's rung out
local function landCue(cue, skipped)
	tune.spinning, tune.cut = false, false
	tune.quietUntil = os.clock() + (CUE.hold[cue.rarity] or 1)
	if skipped then
		hush(cue.riser)
		hush(cue.heart)
	end
	if not cue.sting then
		cue.sting = play(landSounds(cue.rarity), 1, CUE.volume[cue.rarity], cue.lead)
	end
end

-- THE CAMERA during a spin: it glides from shot to shot (rig.shot) and
-- shakes (rig.kick: a jolt that dies away; rig.floor: a steady rumble), and
-- its view can punch in (rig.punch: degrees narrower, springing back)
local rig = { on = false, shake = 0, floor = 0, punch = 0 }
function rig.shot(goal, seconds)
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	if not rig.on then
		rig.on, rig.saved, rig.fov = true, cam.CameraType, cam.FieldOfView
		cam.CameraType = Enum.CameraType.Scriptable
		rig.base = cam.CFrame
	end
	rig.from, rig.to, rig.t0, rig.dur = rig.base, goal, os.clock(), math.max(seconds or 0, 1e-3)
end
function rig.kick(amount)
	rig.shake = math.max(rig.shake, amount)
end
RunService.RenderStepped:Connect(function(dt)
	local cam = Workspace.CurrentCamera
	if not (rig.on and cam and rig.to) then
		return
	end
	local u = math.clamp((os.clock() - rig.t0) / rig.dur, 0, 1)
	local k = u < 0.5 and 2 * u * u or 1 - (-2 * u + 2) ^ 2 / 2 -- (easing in and out)
	rig.base = rig.from:Lerp(rig.to, k)
	rig.shake = math.max(rig.floor, rig.shake * math.exp(-6 * dt))
	local a, t = rig.shake, os.clock()
	cam.CFrame = rig.base * CFrame.new(math.noise(t * 17, 1.5) * a, math.noise(t * 17, 7.5) * a, 0) * CFrame.Angles(0, 0, math.noise(t * 11, 3.5) * a * 0.12)
	if rig.fov then
		rig.punch = rig.punch * math.exp(-5 * dt)
		cam.FieldOfView = rig.fov - rig.punch
	end
end)
local function cameraBack()
	local cam = Workspace.CurrentCamera
	if rig.on and cam then
		cam.CameraType = (rig.saved == nil or rig.saved == Enum.CameraType.Scriptable) and Enum.CameraType.Custom or rig.saved
		if rig.fov then
			cam.FieldOfView = rig.fov
		end
	end
	rig.on, rig.to, rig.shake, rig.floor, rig.punch = false, nil, 0, 0, 0
end
-- the shots: beside the machine (on its lever side), watching the token go in; then right up
-- to its screen (`near`: closer still), filling most of the view
function rig.insertShot(c, target)
	local s = c.screen
	local focus = target:Lerp(s.Position, 0.35)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and (root.Position - target).Magnitude < 30 then
		focus = focus:Lerp(root.Position, 0.35)
	end
	rig.shot(CFrame.lookAt(focus + s.CFrame.LookVector * 14 - s.CFrame.RightVector * 7 + Vector3.new(0, 3, 0), focus), 0.35)
end
function rig.screenShot(c, near, seconds)
	local s = c.screen
	local dist = s.Size.Y / 0.85 / 2 / math.tan(math.rad(35)) * (near or 1)
	rig.shot(CFrame.lookAt(s.Position + s.CFrame.LookVector * dist, s.Position), seconds or 0.45)
end

-- THE LEVER on the machine's side, pulled down and springing back (for
-- anyone's spin: every screen pulls it itself)
function pullLever(c)
	local hub, arm, knob = c.model:FindFirstChild("LeverHub"), c.model:FindFirstChild("LeverArm"), c.model:FindFirstChild("LeverBall")
	if not (hub and arm and knob) or c.pulling then
		return
	end
	c.pulling = true
	local pivot = hub.CFrame
	local armHome, knobHome = pivot:ToObjectSpace(arm.CFrame), pivot:ToObjectSpace(knob.CFrame)
	task.spawn(function()
		local function set(a) -- (tipped `a` towards the front)
			local r = pivot * CFrame.Angles(-a, 0, 0)
			arm.CFrame, knob.CFrame = r * armHome, r * knobHome
		end
		local t0 = os.clock()
		while os.clock() - t0 < 0.62 and arm.Parent do
			local t = os.clock() - t0
			local a
			if t < 0.2 then
				a = (t / 0.2) ^ 2 * math.rad(75) -- down
			elseif t < 0.26 then
				a = math.rad(75) -- (clunk)
			else
				local u = (t - 0.26) / 0.36
				a = math.rad(75) * (1 - u) + math.sin(u * math.pi) * math.rad(-8) -- back up, a little past
			end
			set(a)
			RunService.RenderStepped:Wait()
		end
		set(0)
		c.pulling = false
	end)
	task.delay(0.2, function()
		play({ "Token Clunk", "UI Blip" }, 0.6, 0.5, nil, c.screen)
	end)
end

-- YOUR ARM flicking the token (an R6 body's right shoulder, only on your screen)
local function armFlick(char)
	local torso = char and char:FindFirstChild("Torso")
	local shoulder = torso and torso:FindFirstChild("Right Shoulder")
	if not (shoulder and shoulder:IsA("Motor6D")) then
		return
	end
	local WIND, RELEASE = CFrame.Angles(0, math.rad(-20), math.rad(165)), CFrame.Angles(0, math.rad(10), math.rad(75))
	local t0 = os.clock()
	local conn
	conn = RunService.Stepped:Connect(function()
		local t = os.clock() - t0
		if t > 0.32 or not shoulder.Parent then
			conn:Disconnect()
			return
		end
		local pose, w
		if t < 0.1 then
			pose, w = WIND, t / 0.1
		elseif t < 0.16 then
			pose, w = WIND:Lerp(RELEASE, (t - 0.1) / 0.06), 1
		else
			pose, w = RELEASE, 1 - (t - 0.16) / 0.16
		end
		shoulder.Transform = shoulder.Transform:Lerp(pose, math.clamp(w, 0, 1))
	end)
end

-- THE TOKEN: flicked from your hand (or, from further off, tossed in from
-- where you're watching) in an arc into the coin slot, where it clunks.
-- Returns once it's in (straight away if you tap to skip).
local function throwToken(c, target)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local cam = Workspace.CurrentCamera
	local from
	if root and (root.Position - target).Magnitude < 30 then
		armFlick(char)
		task.wait(0.15) -- (the arm winds up and lets go)
		local arm = char:FindFirstChild("Right Arm") or char:FindFirstChild("RightHand")
		from = arm and (arm.CFrame * CFrame.new(0, -1, 0)).Position or root.Position + Vector3.new(0, 1.5, 0)
	else
		from = cam and (cam.CFrame * CFrame.new(1.5, -1.5, -3)).Position or target + Vector3.new(0, 6, 8)
	end
	local coin = new("Part", { Name = "ThrownToken", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.16, 0.9, 0.9), Color = GOLD, Material = Enum.Material.SmoothPlastic, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }, Workspace)
	new("PointLight", { Color = GOLD, Range = 6, Brightness = 2 }, coin)
	local height = math.max(2, (target - from).Magnitude * 0.25)
	local t0 = os.clock()
	while not skipping do
		local u = math.clamp((os.clock() - t0) / 0.28, 0, 1)
		local p = from:Lerp(target, u) + Vector3.new(0, height * 4 * u * (1 - u), 0)
		coin.CFrame = CFrame.new(p) * CFrame.Angles(0, os.clock() * 9, os.clock() * 14)
		if u >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
	coin:Destroy()
	play({ "Token Clunk", "UI Blip" }, 1, 1)
	local slot = c.model:FindFirstChild("CoinSlot")
	if slot then -- (the slot lights up as it takes it)
		local was = slot.Color
		slot.Color = WHITE
		task.delay(0.25, function()
			slot.Color = was
		end)
	end
end

-- the whole machine rattling (only here: it jumps back after)
local function rattle(c, seconds, amount)
	local m = c.model
	if c.rattling or not m then
		return
	end
	c.rattling = true
	local home = m:GetPivot()
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < seconds and m.Parent do
			local f = 1 - (os.clock() - t0) / seconds
			m:PivotTo(home * CFrame.new((math.random() - 0.5) * amount * f, (math.random() - 0.5) * amount * f * 0.5, 0) * CFrame.Angles(0, 0, (math.random() - 0.5) * amount * 0.06 * f))
			RunService.RenderStepped:Wait()
		end
		m:PivotTo(home)
		c.rattling = false
	end)
end

local function endShow()
	show.Visible = false
	card.Visible = false
	grid.Visible = false
	for _, ch in ipairs(view:GetChildren()) do
		if ch ~= viewCam then
			ch:Destroy()
		end
	end
	cameraBack()
	SCR.gui.Enabled = false
	tune.spinning, tune.cut = false, false
	busy = false
	openMenu()
end

-- the strip races past and slows onto `result` (the music following it:
-- `cue`); returns when it's landed, and whether it was tapped through
local function runStrip(machineId, result, seconds, cue)
	for _, ch in ipairs(strip:GetChildren()) do
		ch:Destroy()
	end
	local count, landOn = 46, 40
	for i = 1, count do
		local wid, rarity
		if i == landOn then
			wid, rarity = result.id, result.rarity
		else
			wid, rarity = randomDrop(machineId)
		end
		tileFor(strip, wid, rarity, (i - 1) * (TILE + GAP))
	end
	strip.Size = UDim2.fromOffset(count * (TILE + GAP), 180)
	local centre = window.Size.X.Offset / 2
	local startX = centre - (2 * (TILE + GAP) + TILE / 2)
	-- (it can stop anywhere on the tile, not always dead centre)
	local endX = centre - ((landOn - 1) * (TILE + GAP) + TILE / 2) + fillRng:NextNumber(-TILE * 0.3, TILE * 0.3)
	strip.Position = UDim2.fromOffset(startX, 0)
	local t0 = os.clock()
	local lastTile = nil
	while true do
		local u = math.clamp((os.clock() - t0) / seconds, 0, 1)
		if skipping then
			u = 1
		elseif cue then
			cueAt(cue, seconds - (os.clock() - t0))
		end
		local k = 1 - (1 - u) ^ 4 -- (fast, then slowing right down)
		local x = startX + (endX - startX) * k
		strip.Position = UDim2.fromOffset(x, 0)
		local under = math.floor((centre - x) / (TILE + GAP)) + 1
		rig.floor = (skipping or (cue and cue.quieted)) and 0 or 0.035 * (1 - u) -- (it goes still for the silence)
		if under ~= lastTile then
			lastTile = under
			if not skipping then
				play({ "Roll Tick", "UI Blip" }, 0.9 + 0.4 * u, 0.5)
				if not (cue and cue.quieted) then
					rig.kick(0.03 + 0.05 * (1 - u))
				end
			end
		end
		if u >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
	return skipping
end

local function flashScreen(color, alpha)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = alpha or 0.2
	tween(flash, 0.6, { BackgroundTransparency = 1 })
end

-- GLASS SMASHING (a Legendary or better landing, in time with its jackpot):
-- a white flash and the machine's screen bursting into shards
local shatter
do
	local shardRng = Random.new()
	function shatter(color)
		flashScreen(WHITE, 0)
		for i = 1, 28 do
			local size = shardRng:NextInteger(10, 36)
			local shard = new("Frame", {
				Name = "Shard",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, shardRng:NextInteger(-300, 300), 0.42, shardRng:NextInteger(-110, 110)),
				Size = UDim2.fromOffset(size, math.floor(size * shardRng:NextNumber(0.25, 0.9))),
				Rotation = shardRng:NextInteger(0, 359),
				BackgroundColor3 = (i % 3 == 0) and color or WHITE,
				BackgroundTransparency = 0.05,
				BorderSizePixel = 0,
				ZIndex = 29,
			}, show)
			local angle = shardRng:NextNumber(0, math.pi * 2)
			local reach = shardRng:NextNumber(220, 620)
			local p = shard.Position
			tween(shard, 0.8, {
				Position = UDim2.new(0.5, p.X.Offset + math.cos(angle) * reach, 0.42, p.Y.Offset + math.sin(angle) * reach + 160),
				Rotation = shard.Rotation + shardRng:NextInteger(-540, 540),
				BackgroundTransparency = 1,
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			task.delay(0.85, function()
				shard:Destroy()
			end)
		end
	end
end

-- the big reveal of one result
local function reveal(result, machineId, count)
	local def = W.List[result.id]
	local col = rarityColor(result.rarity)
	local rank = RANK[result.rarity] or 1
	card.Visible = true
	cardScale.Scale = 0.3
	tween(cardScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	cardBar.BackgroundColor3 = col
	if cardEdgeRainbow then
		cardEdgeRainbow:Destroy()
		cardEdgeRainbow = nil
	end
	if cardRarityRainbow then
		cardRarityRainbow:Destroy()
		cardRarityRainbow = nil
	end
	cardRarity.Text = string.upper(result.rarity) .. "!"
	if result.rarity == "Secret" then
		cardEdgeRainbow = rainbow(cardBar) -- (its title bar runs through the rainbow)
	end
	cardName.Text = def and def.Name or result.id
	cardType.Text = (def and def.Type or "") .. (def and def.Ability and def.Ability.Name and ("  -  F: " .. def.Ability.Name) or "")
	if result.new then
		cardNote.Text = "NEW WEAPON!"
		cardNote.BackgroundColor3 = GREEN
	elseif result.refund then
		cardNote.Text = "Already mastered: +1 TOKEN back"
		cardNote.BackgroundColor3 = GOLD
	else
		cardNote.Text = "You have it: +" .. tostring(result.mastery or 0) .. " MASTERY"
		cardNote.BackgroundColor3 = RGB(0, 153, 219)
	end
	-- the weapon itself, turning (or its type's icon, if its model isn't here yet)
	for _, ch in ipairs(view:GetChildren()) do
		if ch ~= viewCam then
			ch:Destroy()
		end
	end
	local model = weaponModel(def)
	if cardGem then
		cardGem:Destroy()
		cardGem = nil
	end
	if not model then
		local icon = iconFor(def, result.id, 420)
		if icon then
			cardGem = new("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = icon, ScaleType = Enum.ScaleType.Fit, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 194), Size = UDim2.fromOffset(230, 230), ZIndex = 23 }, card)
		else
			cardGem = gem(card, result.rarity, 120, { Position = UDim2.new(0.5, 0, 0, 194), ZIndex = 23 })
		end
	end
	if model then
		local offset, size = standInfo(model)
		model.Parent = view
		local reach = math.max(size.X, size.Y, size.Z)
		viewCam.CFrame = CFrame.lookAt(Vector3.new(0, 0, reach * 1.6), Vector3.new(0, 0, 0))
		task.spawn(function()
			while model.Parent and card.Visible do
				standAt(model, Vector3.new(), offset, os.clock() * 1.2)
				RunService.RenderStepped:Wait()
			end
		end)
	end
	-- the bigger the rarity, the bigger the moment
	rays.Visible = rank >= 3
	for _, r in ipairs(rays:GetChildren()) do
		r.BackgroundColor3 = col
	end
	-- (its sound played as the strip landed: landCue)
	if rank >= 4 then
		flashScreen(col, 0.1)
		show.BackgroundTransparency = 0.25
	elseif rank == 3 then
		flashScreen(col, 0.45)
	end
	if rank >= 3 then
		task.spawn(function()
			-- flashing lights round the card
			for i = 1, (rank >= 5 and 16 or 8) do
				if not card.Visible then
					break
				end
				cardBar.BackgroundColor3 = (i % 2 == 0) and col or WHITE
				task.wait(0.12)
			end
			cardBar.BackgroundColor3 = col
		end)
	end
	-- the buttons
	local canEquip = def and W.Types[def.Type] and player:GetAttribute("Weapon") ~= result.id
	equipBtn.Visible = canEquip and true or false
	local m = A.Machines[machineId]
	local price = m and (count == 10 and m.Ten or m.Price) or 0
	againBtn.Text = tokens() >= price and "SPIN AGAIN" or "GET TOKENS"
end

-- (a spin that didn't happen: back to the menu, saying why)
local function refused(why)
	busy = false
	if show.Visible then
		endShow()
	end
	say(why, RED)
	play({ "UI Blip" }, 0.7, 0.6)
end

local function roll(machineId, count)
	if busy then
		return
	end
	local m = A.Machines[machineId]
	if not m then
		return
	end
	local price = count == 10 and m.Ten or m.Price
	if tokens() < price then
		refused("You need " .. price .. (price == 1 and " token" or " tokens") .. " for that. Quests give a token every " .. (Config.Quests.Hours or 6) .. " hours!")
		return
	end
	busy = true
	local ok, success, answer = pcall(function()
		return Action:InvokeServer("ArcadeRoll", { machine = machineId, count = count })
	end)
	if not ok or not success or type(answer) ~= "table" then
		refused(ok and tostring(answer or "Couldn't spin.") or "Couldn't reach the server.")
		return
	end
	-- the server has already decided: from here on it's only the show
	if state then
		state.Tokens = answer.tokens
		state.Arcade = state.Arcade or { pity = {} }
		state.Arcade.spins = answer.spins
		state.Arcade.pity = state.Arcade.pity or {}
		state.Arcade.pity[machineId] = answer.pity
		state.Weapons = state.Weapons or { own = {} }
		for _, r in ipairs(answer.results or {}) do
			if r.new then
				state.Weapons.own[r.id] = state.Weapons.own[r.id] or 0
			end
		end
	end
	lastRoll = { machine = machineId, count = count, results = answer.results or {} }
	closeMenu()
	busy = true
	skipping = false -- (a tap from here on skips the strip)
	local e = machineEntry(machineId)
	local light = e and e.machine and e.machine.Light or GREEN
	local c = cabinets[machineId]
	SCR.bar.BackgroundColor3 = light
	SCR.title.Text = string.upper(machineId) .. " MACHINE"
	SCR.status.Text, SCR.status.TextColor3 = count == 10 and "x10  GOOD LUCK!" or "GOOD LUCK!", YELLOW
	for _, ch in ipairs(strip:GetChildren()) do
		ch:Destroy()
	end
	SCR.gui.Adornee = c and c.screen or nil
	SCR.gui.Enabled = true
	show.Visible, show.BackgroundTransparency = true, 1
	skipHint.Visible = true -- (a tap from here on skips to the landing)
	card.Visible, grid.Visible = false, false
	local top = best(answer.results) or (answer.results or {})[1]
	if not top then
		endShow()
		return
	end
	-- the token goes in, the lever comes down, and the camera flies up to
	-- the machine's screen
	if c and c.screen then
		local slot = c.model:FindFirstChild("CoinSlot")
		local target = slot and slot.Position or (c.screen.Position - Vector3.new(0, 5, 0))
		rig.insertShot(c, target)
		local t0 = os.clock()
		while not skipping and os.clock() - t0 < 0.3 do
			task.wait()
		end
		throwToken(c, target)
		pullLever(c)
		t0 = os.clock()
		while not skipping and os.clock() - t0 < 0.12 do
			task.wait()
		end
		rig.screenShot(c, 1, skipping and 0.01 or 0.45)
	else
		play({ "Token Clunk", "UI Blip" }, 1, 1)
	end
	local seconds = count == 10 and 2.2 or 3.8
	if c and c.screen and not skipping then -- (and slowly closer as it spins)
		task.delay(0.45, function()
			if rig.on and busy and not skipping then
				rig.screenShot(c, 0.8, seconds - 0.45)
			end
		end)
	end
	local cue = spinCue(top, seconds)
	local skipped = runStrip(machineId, top, seconds, cue)
	landCue(cue, skipped)
	-- the landing: the machine says what it is, the view jolts (harder the
	-- rarer), and a Legendary or better smashes the glass and rattles it
	local rank = RANK[top.rarity] or 1
	SCR.status.Text, SCR.status.TextColor3 = string.upper(top.rarity) .. "!", rarityColor(top.rarity)
	rig.floor = 0
	rig.kick(({ 0.06, 0.1, 0.18, 0.35, 0.5, 0.7 })[rank] or 0.1)
	rig.punch = ({ 0, 2, 4, 8, 11, 15 })[rank] or 0
	if rank >= 4 then
		shatter(rarityColor(top.rarity))
		if c then
			rattle(c, 0.7, 0.45)
		end
	end
	skipHint.Visible = false
	task.wait(rank >= 4 and 0.8 or 0.5) -- (a moment on the machine's screen before the card)
	show.BackgroundTransparency = 0.5
	if count == 10 then
		-- a Legendary or better still gets its moment first
		if (RANK[top.rarity] or 0) >= 4 then
			reveal(top, machineId, count)
			equipBtn.Visible, againBtn.Visible = false, false
			doneBtn.Text = "SEE ALL 10"
			doneBtn.Position = UDim2.fromOffset(198, 474)
			doneBtn.BackgroundColor3, doneBtn.TextColor3, doneBtn.TextStrokeTransparency = WC.Orange, WHITE, 0
			local waiting = true
			local conn = doneBtn.Activated:Connect(function()
				waiting = false
			end)
			local conn2 = cardClose.Activated:Connect(function()
				waiting = false
			end)
			local t0 = os.clock()
			while waiting and os.clock() - t0 < 6 do
				task.wait(0.05)
			end
			conn:Disconnect()
			conn2:Disconnect()
			card.Visible = false
			againBtn.Visible = true
			doneBtn.Text = "DONE"
			doneBtn.Position = UDim2.fromOffset(376, 474)
			doneBtn.BackgroundColor3, doneBtn.TextColor3, doneBtn.TextStrokeTransparency = WC.Face, INK, 1
		end
		for _, ch in ipairs(gridCells:GetChildren()) do
			if not ch:IsA("UIGridLayout") then
				ch:Destroy()
			end
		end
		grid.Visible = true
		local newCount = 0
		for i, r in ipairs(answer.results) do
			local cell = tileFor(gridCells, r.id, r.rarity, 0)
			cell.LayoutOrder = i
			local note = r.new and "NEW!" or (r.refund and "+1 TOKEN" or ("+" .. tostring(r.mastery or 0) .. " MASTERY"))
			newCount = newCount + (r.new and 1 or 0)
			local tag = text(cell, { Text = note, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 5), Size = UDim2.fromOffset(128, 24), BackgroundTransparency = 0, BackgroundColor3 = r.new and GREEN or SLATE, ZIndex = 16 })
			corner(tag, 6)
			local sc = new("UIScale", { Scale = 0.2 }, cell)
			tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			play({ "UI Blip", "Orb Land" }, 1 + i * 0.05, 0.5)
			task.wait(0.09)
		end
		gridTitle.Text = "10 SPINS  -  " .. newCount .. (newCount == 1 and " NEW WEAPON" or " NEW WEAPONS")
		gridAgain.Text = tokens() >= (e and e.machine and e.machine.Ten or 0) and "SPIN x10 AGAIN" or "GET TOKENS"
	else
		reveal(top, machineId, count)
	end
end

-- tap to skip the strip
UserInputService.InputBegan:Connect(function(input)
	if show.Visible and skipHint.Visible and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
		skipping = true
	end
end)

spin1.Activated:Connect(function()
	task.spawn(roll, selected, 1)
end)
spin10.Activated:Connect(function()
	task.spawn(roll, selected, 10)
end)
equipBtn.Activated:Connect(function()
	local top = lastRoll and best(lastRoll.results)
	if not top then
		return
	end
	local ok, success, msg = pcall(function()
		return Action:InvokeServer("EquipWeapon", top.id)
	end)
	cardNote.Text = ok and tostring(msg or "") or "Couldn't reach the server."
	cardNote.BackgroundColor3 = (ok and success) and GREEN or RED
	if ok and success then
		equipBtn.Visible = false
	end
end)
local function again()
	if not lastRoll then
		return
	end
	local m = A.Machines[lastRoll.machine]
	local price = m and (lastRoll.count == 10 and m.Ten or m.Price) or math.huge
	if tokens() < price then
		endShow()
		showTokens()
		return
	end
	card.Visible, grid.Visible = false, false
	busy = false
	local machineId, count = lastRoll.machine, lastRoll.count
	cameraBack()
	task.spawn(roll, machineId, count)
end
againBtn.Activated:Connect(again)
gridAgain.Activated:Connect(again)
doneBtn.Activated:Connect(function()
	if doneBtn.Text == "DONE" then
		endShow()
	end
end)
cardClose.Activated:Connect(function() -- (the window's X: DONE, or on to the grid)
	if doneBtn.Text == "DONE" then
		endShow()
	end
end)
gridDone.Activated:Connect(endShow)
gridClose.Activated:Connect(endShow)

----------------------------------------------------------------------
-- Your data
----------------------------------------------------------------------
local StateUpdate = Remotes:WaitForChild("StateUpdate")
StateUpdate.OnClientEvent:Connect(function(d)
	if type(d) == "table" then
		state = d
		refresh()
	end
end)
local request = Remotes:FindFirstChild("RequestState")
if request then
	request:FireServer()
end
refresh()
for _, attr in ipairs({ "SpireFloor", "Colosseum", "Intro" }) do
	player:GetAttributeChangedSignal(attr):Connect(function()
		rollBtn.Visible = not player:GetAttribute("Intro")
		if win.Visible then
			refresh()
		end
	end)
end
rollBtn.Visible = not player:GetAttribute("Intro")

----------------------------------------------------------------------
-- Walk in and it opens (the same way as the Quest Board: LobbyActivities)
----------------------------------------------------------------------
do
	local zones = {}
	local function addZone(z)
		if z:IsA("BasePart") and z:GetAttribute("Activity") == "Arcade" then
			zones[z] = true
		end
	end
	for _, z in ipairs(CollectionService:GetTagged("AutoOpenZone")) do
		addZone(z)
	end
	CollectionService:GetInstanceAddedSignal("AutoOpenZone"):Connect(addZone)
	local function inside(zone, pos, margin)
		local rel = zone.CFrame:PointToObjectSpace(pos)
		local half = zone.Size / 2
		return math.abs(rel.X) <= half.X + margin and math.abs(rel.Y) <= half.Y + margin and math.abs(rel.Z) <= half.Z + margin
	end
	local here, opened, settle = false, false, true
	player.CharacterAdded:Connect(function()
		settle = true
	end)
	local lastLook = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastLook < 0.15 then
			return
		end
		lastLook = now
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root or player:GetAttribute("Intro") then
			here, settle = false, true
			inArcade = false
			return
		end
		local isIn = false
		for z in pairs(zones) do
			if z.Parent and inside(z, root.Position, here and 2 or 0) then
				isIn = true
				break
			end
		end
		inArcade = isIn -- (for the music)
		if settle then
			-- (arriving inside it - a respawn - doesn't pop it open)
			settle = false
			here = isIn
			opened = isIn
			return
		end
		if isIn and not here then
			here = true
			if not opened then
				opened = openMenu()
			end
		elseif not isIn and here then
			here = false
			opened = false
			if win.Visible and not busy then
				closeMenu()
			end
		end
	end)
end
