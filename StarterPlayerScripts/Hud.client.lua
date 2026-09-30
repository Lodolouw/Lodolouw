--[[
	Hud  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "Hud")

	Builds the whole GUI from code (no assets needed):
	  * left 2x2 buttons: Upgrades, Backpack, Armory (talismans), Prestige (with % badge)
	  * bottom-left: Arcade Tokens (click: the Arcade's menu) / coins / level
	  * top hint banner, bottom goal bar
	  * bottom middle: THE HEART (your health) - with the potion (flasks) and
	    the lightning bolt (stamina) either side of it in a fight - drawn by
	    ReplicatedStorage/Vitals
	  * panels: Upgrade Shop, Sell Shop / Backpack, Talisman Workbench, Prestige

	The server owns all data; this script only displays it and sends requests.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Vitals = require(ReplicatedStorage:WaitForChild("Vitals")) -- the heart, the potion and the lightning bolt
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local FONT = Enum.Font.FredokaOne
local RGB = Color3.fromRGB

local C = {
	panel = RGB(30, 32, 58),
	panelDark = RGB(20, 22, 42),
	row = RGB(44, 47, 82),
	ink = RGB(12, 12, 28),
	gold = RGB(255, 208, 70),
	green = RGB(70, 210, 110),
	red = RGB(240, 80, 90),
	blue = RGB(70, 160, 255),
	orange = RGB(255, 150, 60),
	dim = RGB(160, 165, 200),
	off = RGB(84, 88, 116),
	white = Color3.new(1, 1, 1),
}

-- Built-in placeholder sounds - swap for your own asset ids later.
local PING_SOUND = "rbxasset://sounds/electronicpingshort.wav" -- bright "ting", used pitched-up/down
local HIT_SOUND = "rbxasset://sounds/snap.mp3" -- percussive "thump", used for impacts

local state = nil -- latest snapshot from the server
local stats = nil -- Config.stats(state)

----------------------------------------------------------------------
-- UI helpers
----------------------------------------------------------------------
local function create(className, props, children)
	local inst = Instance.new(className)
	local parent = props.Parent
	for k, v in pairs(props) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = inst
		end
	end
	inst.Parent = parent
	return inst
end

local function corner(r)
	return create("UICorner", { CornerRadius = UDim.new(0, r) })
end

-- outline around a frame / button
local function border(thickness, color)
	return create("UIStroke", {
		Thickness = thickness,
		Color = color or C.ink,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

-- outline around text
local function stroke(thickness, color)
	return create("UIStroke", {
		Thickness = thickness,
		Color = color or C.ink,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	})
end

local function gradient(colors, rotation)
	local keys = {}
	local n = #colors
	for i, c in ipairs(colors) do
		keys[i] = ColorSequenceKeypoint.new((i - 1) / math.max(n - 1, 1), c)
	end
	return create("UIGradient", { Color = ColorSequence.new(keys), Rotation = rotation or 90 })
end

local function text(props, children)
	local p = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = FONT,
		TextColor3 = C.white,
		TextSize = 20,
		Text = "",
	}
	for k, v in pairs(props) do
		p[k] = v
	end
	return create("TextLabel", p, children)
end

local function button(props, children)
	local p = {
		BorderSizePixel = 0,
		Font = FONT,
		TextColor3 = C.white,
		TextSize = 22,
		Text = "",
		AutoButtonColor = true,
		BackgroundColor3 = C.green,
	}
	for k, v in pairs(props) do
		p[k] = v
	end
	local kids = { corner(12), stroke(2) }
	if children then
		for _, c in ipairs(children) do
			table.insert(kids, c)
		end
	end
	return create("TextButton", p, kids)
end

local function paint(btn, enabled, color)
	btn.BackgroundColor3 = enabled and color or C.off
	btn.AutoButtonColor = enabled
	btn.TextTransparency = enabled and 0 or 0.35
end

local function tween(inst, seconds, props, style, direction)
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local t = TweenService:Create(inst, info, props)
	t:Play()
	return t
end

-- The mix's three volume groups (Config.Audio), made once in SoundService and
-- shared by every script that plays anything.
local function soundGroup(name)
	local SS = game:GetService("SoundService")
	local g = SS:FindFirstChild(name)
	if not (g and g:IsA("SoundGroup")) then
		g = Instance.new("SoundGroup")
		g.Name = name
		g.Parent = SS
	end
	local audio = Config.Audio or {}
	g.Volume = audio[name] or 1
	return g
end

local function playSound(id, volume, speed)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.5
	s.PlaybackSpeed = speed or 1
	s.SoundGroup = soundGroup("UI")
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 3)
	return s
end

-- Plays a Sound instance already sitting under SoundService by name (e.g. a
-- coin sound the developer dropped in there) instead of a hardcoded asset id
-- - clones it so overlapping buys/sells don't cut each other off, and falls
-- back to the placeholder ping if it's ever renamed or missing.
local function playNamedSound(name, volume, speed)
	local template = SoundService:FindFirstChild(name)
	if not template or not template:IsA("Sound") then
		return playSound(PING_SOUND, volume, speed)
	end
	local s = template:Clone()
	s.Volume = volume or template.Volume
	s.PlaybackSpeed = speed or template.PlaybackSpeed
	s.SoundGroup = soundGroup("UI")
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 5)
	return s
end

-- Plays a short sequence of pitched notes off one sound asset, so different
-- actions get a recognizable little "motif" instead of one flat ping. A note
-- with `soundName` plays a SoundService instance by name (see playNamedSound)
-- instead of the raw asset id in `sound`.
local function playChime(notes)
	for _, n in ipairs(notes) do
		task.delay(n.delay or 0, function()
			if n.soundName then
				playNamedSound(n.soundName, n.volume or 0.5, n.speed or 1)
			else
				playSound(n.sound or PING_SOUND, n.volume or 0.5, n.speed or 1)
			end
		end)
	end
end

-- The coin sound the developer dropped into SoundService for buying/selling.
local COIN_SOUND = "coin2"

-- One motif per action, so buying, selling, crafting and prestiging each feel distinct.
local ACTION_CHIMES = {
	BuyUpgrade = { { speed = 1.05, volume = 0.55, soundName = COIN_SOUND } },
	Sell = {
		{ speed = 1.1, volume = 0.5, soundName = COIN_SOUND },
		{ delay = 0.06, speed = 1.35, volume = 0.45, soundName = COIN_SOUND },
		{ delay = 0.12, speed = 1.6, volume = 0.4, soundName = COIN_SOUND },
	},
	Craft = {
		{ speed = 0.85, volume = 0.5, sound = HIT_SOUND },
		{ delay = 0.05, speed = 1.3, volume = 0.4 },
		{ delay = 0.16, speed = 1.75, volume = 0.35 },
	},
	Equip = { { speed = 1.2, volume = 0.45 } },
	Unequip = { { speed = 0.8, volume = 0.4 } },
	Prestige = {
		{ speed = 1.0, volume = 0.6, sound = HIT_SOUND },
		{ delay = 0.12, speed = 1.19, volume = 0.55 },
		{ delay = 0.24, speed = 1.4, volume = 0.55 },
		{ delay = 0.4, speed = 1.68, volume = 0.6 },
	},
}

local function playActionChime(name)
	playChime(ACTION_CHIMES[name] or { { speed = 1, volume = 0.45 } })
end

-- The ding the developer dropped into SoundService. Plays when you level up.
-- If you rename the sound in SoundService, change the name here to match.
local COMBO_DING_SOUND = "Minecraft Sound Successful Bow Hit Ding"

-- The punch animations (CombatClient swings them in a fight; the same two are
-- warmed up here as soon as you spawn - see warmAnimations below).
local PUNCH_ANIMATION_IDS = {
	"140534557983022", -- Punch 1
	"128188028965818", -- Punch 2
}

local punchTracks = {} -- [animationId] = AnimationTrack, for the current Animator
local punchAnimator = nil

local function getPunchTrack(animationId)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	if punchAnimator ~= animator then
		-- new character (respawned) - old tracks belong to the old one
		punchTracks = {}
		punchAnimator = animator
	end
	local track = punchTracks[animationId]
	if not track then
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. animationId
		track = animator:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Action2 -- above the run animation
		track.Looped = false
		punchTracks[animationId] = track
	end
	return track
end

-- Animations arrive cold: the first couple of plays are Roblox still fetching
-- and compiling them, which is why early swings look wrong and later ones look
-- right. Load them and run each through silently as soon as you spawn.
local function warmAnimations()
	local ready, assets = {}, {}
	for _, id in ipairs(PUNCH_ANIMATION_IDS) do
		local track = getPunchTrack(id)
		if track then
			ready[#ready + 1] = track
			if track.Animation then
				assets[#assets + 1] = track.Animation
			end
		end
	end
	local runAnim = Instance.new("Animation")
	runAnim.AnimationId = "rbxassetid://77081121019941" -- the run cycle, see below
	assets[#assets + 1] = runAnim
	pcall(function()
		ContentProvider:PreloadAsync(assets) -- yields until they're really here
	end)
	for _, track in ipairs(ready) do
		pcall(function()
			track:Play(0, 0.0001, 1) -- no blend, no weight: nothing shows
		end)
	end
	task.wait(0.1)
	for _, track in ipairs(ready) do
		if track.IsPlaying then
			track:Stop(0)
		end
	end
end

local function warmSoon()
	task.spawn(function()
		for _ = 1, 20 do
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and hum:FindFirstChildOfClass("Animator") then
				warmAnimations()
				return
			end
			task.wait(0.25)
		end
	end)
end
warmSoon()
player.CharacterAdded:Connect(warmSoon)

----------------------------------------------------------------------
-- Root GUI (scales with screen height so it works on phones too)
----------------------------------------------------------------------
local old = playerGui:FindFirstChild("BossGrowHud")
if old then
	old:Destroy()
end

local gui = create("ScreenGui", {
	Name = "BossGrowHud",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 5,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

local root = create("Frame", {
	Name = "Root",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	Parent = gui,
})
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

----------------------------------------------------------------------
-- Toasts
----------------------------------------------------------------------
local toastHost = create("Frame", {
	Name = "Toasts",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -130), -- just above the HP bar
	Size = UDim2.fromOffset(700, 220),
	BackgroundTransparency = 1,
	ZIndex = 30,
	Parent = root,
}, {
	create("UIListLayout", {
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local toastOrder = 0
local liveToasts = {}

local function toast(message, kind)
	if type(message) ~= "string" then
		return
	end
	toastOrder = toastOrder + 1
	local color = C.green
	if kind == "bad" then
		color = C.red
	elseif kind == "info" then
		color = C.blue
	elseif kind == "rare" then
		color = RGB(200, 130, 20) -- someone pulled something big from a chest
	end
	local t = create("TextLabel", {
		LayoutOrder = toastOrder,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = color,
		Font = FONT,
		Text = message,
		TextColor3 = C.white,
		TextSize = 22,
		ZIndex = 30,
		Parent = toastHost,
	}, {
		corner(14),
		border(3),
		create("UIPadding", {
			PaddingLeft = UDim.new(0, 16),
			PaddingRight = UDim.new(0, 16),
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8),
		}),
	})
	table.insert(liveToasts, t)
	if #liveToasts > 4 then
		local first = table.remove(liveToasts, 1)
		first:Destroy()
	end
	task.delay(kind == "rare" and 5 or 2.4, function()
		if t.Parent then
			tween(t, 0.3, { BackgroundTransparency = 1, TextTransparency = 1 })
			Debris:AddItem(t, 0.35)
		end
	end)
end

----------------------------------------------------------------------
-- Server requests
----------------------------------------------------------------------
local function doAction(name, arg)
	task.spawn(function()
		local ok, success, message = pcall(function()
			return Remotes.Action:InvokeServer(name, arg)
		end)
		if not ok then
			toast("Couldn't reach the server.", "bad")
			return
		end
		if message then
			toast(message, success and "ok" or "bad")
		end
		if success and message then
			playActionChime(name)
		end
	end)
end

----------------------------------------------------------------------
-- Panel framework
----------------------------------------------------------------------
local panelHost = create("Frame", {
	Name = "Panels",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 20,
	Parent = root,
})

local panels = {}
local currentKey = nil
local openPanel -- assigned below

local function closePanels()
	for _, p in pairs(panels) do
		p.frame.Visible = false
	end
	currentKey = nil
end

local function makePanel(key, title, accent, height)
	local frame = create("Frame", {
		Name = key,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(680, height),
		BackgroundColor3 = C.panel,
		Visible = false,
		ZIndex = 20,
		Parent = panelHost,
	}, {
		corner(20),
		border(5, accent),
		create("UIScale", { Name = "Pop" }),
	})

	local header = create("Frame", {
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -20, 0, 52),
		BackgroundColor3 = accent,
		Parent = frame,
	}, { corner(14), border(3) })

	local titleLabel = text({
		Size = UDim2.fromScale(1, 1),
		Text = title,
		TextSize = 30,
		Parent = header,
	}, { stroke(3) })

	local close = button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(38, 38),
		Text = "X",
		TextSize = 22,
		BackgroundColor3 = C.red,
		Parent = header,
	})
	close.Activated:Connect(closePanels)

	local body = create("ScrollingFrame", {
		Position = UDim2.fromOffset(14, 72),
		Size = UDim2.new(1, -28, 1, -86),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = frame,
	}, {
		create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		create("UIPadding", { PaddingRight = UDim.new(0, 6) }),
	})

	local p = { key = key, frame = frame, body = body, title = titleLabel, mode = key }
	panels[key] = p
	return p
end

openPanel = function(name, force)
	local key = name
	if name == "Backpack" then
		key = "Sell" -- Backpack and Sell Shop share one panel
	end
	local p = panels[key]
	if not p then
		return
	end
	if not force and currentKey == key and p.mode == name then
		closePanels()
		return
	end
	closePanels()
	p.mode = name
	if p.onOpen then
		p.onOpen(name)
	end
	local pop = p.frame:FindFirstChild("Pop")
	if pop then
		pop.Scale = 0.88
	end
	p.frame.Visible = true
	currentKey = key
	if pop then
		tween(pop, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	if state and p.refresh then
		p.refresh()
	end
end

----------------------------------------------------------------------
-- HUD: left buttons
----------------------------------------------------------------------
-- Big square buttons in a 2x2 grid:  Upgrades | Backpack
--                                     Armory   | Prestige
local BUTTON_SIZE = 112
local BUTTON_GAP = 10

-- Picture icons for the four buttons. Upload each PNG to Roblox (View >
-- Asset Manager > Images > Bulk Import), right-click it > Copy ID, and paste
-- it between the quotes as "rbxassetid://123456789". Any left empty keep
-- their emoji icon.
local BUTTON_ICON_IMAGES = {
	Upgrades = "rbxassetid://109878847284339",
	Backpack = "rbxassetid://125324688627530",
	Armory = "",
	Prestige = "rbxassetid://115477290507288",
}

-- Coin picture, used for the coin counter, prices and the SELL ALL button.
-- Upload icon_coin.png the same way and paste its id here. Until then a
-- simple drawn gold coin is used instead. (The 🪙 emoji doesn't show up in
-- Roblox's font, which is why the coin counter looked empty.)
local COIN_ICON_IMAGE = ""

-- Makes a coin icon `size` pixels big inside `parent`; `props` can set
-- Position/AnchorPoint etc.
local function coinIcon(parent, size, props)
	-- (the living coin, once its pictures are uploaded: ReplicatedStorage/MoneyIcons)
	local living = require(game:GetService("ReplicatedStorage"):WaitForChild("MoneyIcons")).make(parent, "Coin", size, props)
	if living then
		living.ZIndex = 3
		return living
	end
	local icon
	if COIN_ICON_IMAGE ~= "" then
		icon = create("ImageLabel", {
			Name = "Coin",
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 1,
			Image = COIN_ICON_IMAGE,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 3,
			Parent = parent,
		})
	else
		icon = create("Frame", {
			Name = "Coin",
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = C.gold,
			ZIndex = 3,
			Parent = parent,
		}, { corner(math.floor(size / 2)), border(2, RGB(150, 90, 10)) })
		text({
			Size = UDim2.fromScale(1, 1),
			Text = "$",
			TextSize = math.floor(size * 0.7),
			TextColor3 = RGB(170, 100, 0),
			ZIndex = 4,
			Parent = icon,
		})
	end
	for k, v in pairs(props or {}) do
		icon[k] = v
	end
	return icon
end

local leftCol = create("Frame", {
	Name = "LeftButtons",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 16, 0.44, 0),
	Size = UDim2.fromOffset(BUTTON_SIZE * 2 + BUTTON_GAP, BUTTON_SIZE * 2 + BUTTON_GAP),
	BackgroundTransparency = 1,
	Parent = root,
}, {
	create("UIGridLayout", {
		CellSize = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
		CellPadding = UDim2.fromOffset(BUTTON_GAP, BUTTON_GAP),
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

-- Each shop's counter/back-wall sits behind its station's raw position (see
-- LobbyBuilder), so teleporting straight to Config.Stations.X lands the
-- player behind the counter, clipped into the shelving. These are the same
-- shop CFrames/rotations as LobbyBuilder, pushed forward past the counter to
-- the customer side and turned 180° to face back in at it.
local STATION_APPROACH = {
	Upgrades = CFrame.new(Config.Stations.Upgrades) * CFrame.Angles(0, math.rad(Config.StationTurn.Upgrades or -90), 0) * CFrame.new(0, 0, 13) * CFrame.Angles(0, math.pi, 0), -- (in front of the toad)
	Backpack = CFrame.new(Config.Stations.Sell) * CFrame.Angles(0, math.rad(Config.StationTurn.Sell or 90), 0) * CFrame.new(0, 0, 11) * CFrame.Angles(0, math.pi, 0),
	Craft = CFrame.new(Config.Stations.Craft) * CFrame.new(0, 0, 9) * CFrame.Angles(0, math.pi, 0),
	Prestige = CFrame.new(Config.Stations.Prestige) * CFrame.new(0, 0, 12) * CFrame.Angles(0, math.pi, 0),
}

-- Moves the player's own character to just in front of a station, facing it
-- (keeping their current height), so opening a shop/prestige panel from
-- anywhere in the lobby always leaves them close enough to actually use it -
-- instead of opening the panel, trying to buy, and getting a "walk up to the
-- X first!" rejection because they were still standing somewhere else.
local function teleportToStation(targetCFrame)
	local character = player.Character
	if not character or not targetCFrame then
		return
	end
	local currentCF = character:GetPivot()
	local pos = targetCFrame.Position
	character:PivotTo(CFrame.new(pos.X, currentCF.Position.Y, pos.Z) * targetCFrame.Rotation)
end

local function hudButton(name, icon, colors, order, panelName, stationCFrame)
	-- Layers, outside in:
	--   black outline -> dark rim (a deep shade of the button colour, a bit
	--   thicker at the bottom so it looks raised) -> bright face -> shine.
	local rimColor = colors[#colors]:Lerp(Color3.new(0, 0, 0), 0.5)
	local b = create("TextButton", {
		Name = name,
		LayoutOrder = order,
		BackgroundColor3 = rimColor,
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Parent = leftCol,
	}, { corner(14), border(4), create("UIScale", { Name = "Pop" }) })

	local face = create("Frame", {
		Name = "Face",
		Position = UDim2.fromOffset(6, 5),
		Size = UDim2.new(1, -12, 1, -13),
		BackgroundColor3 = colors[1],
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = b,
	}, {
		corner(10),
		gradient(colors, 90),
		-- thin dark line where the face meets the rim, for a crisp inset edge
		create("UIStroke", {
			Thickness = 1.5,
			Color = rimColor:Lerp(Color3.new(0, 0, 0), 0.35),
			Transparency = 0.2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})

	-- glossy highlight across the top of the face, fading out downwards
	create("Frame", {
		Name = "Shine",
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.new(1, -6, 0.45, 0),
		BackgroundColor3 = C.white,
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
		Parent = face,
	}, {
		corner(8),
		create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.05, 1) }),
	})

	local imageId = BUTTON_ICON_IMAGES[name]
	if imageId and imageId ~= "" then
		create("ImageLabel", {
			Name = "Icon",
			ZIndex = 2,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 4),
			Size = UDim2.new(0.74, 0, 0.66, 0),
			BackgroundTransparency = 1,
			Image = imageId,
			ScaleType = Enum.ScaleType.Fit,
			Parent = b,
		})
	else
		text({
			Name = "Icon",
			ZIndex = 2,
			Position = UDim2.fromOffset(0, 2),
			Size = UDim2.new(1, 0, 0.7, 0),
			Text = icon,
			TextSize = 60,
			Parent = b,
		})
	end
	text({
		Name = "Label",
		ZIndex = 3,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, 0, 0, 30),
		Text = name,
		TextSize = 24,
		Parent = b,
	}, { stroke(3) })

	-- grow a little on hover, squash-and-bounce on click
	local pop = b:FindFirstChild("Pop")
	b.MouseEnter:Connect(function()
		tween(pop, 0.12, { Scale = 1.06 })
	end)
	b.MouseLeave:Connect(function()
		tween(pop, 0.12, { Scale = 1 })
	end)
	b.Activated:Connect(function()
		pop.Scale = 0.9
		tween(pop, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
		if stationCFrame then
			teleportToStation(stationCFrame)
		end
		openPanel(panelName)
	end)
	return b
end

-- (Upgrades, Backpack and Armory have no buttons any more: walk up to the
-- Upgrade Shop, the Sell Shop or the forge to use them. The GEAR button sits
-- beside STATS - Inventory makes it.)
local prestigeBtn = hudButton("Stats", "⭐", { RGB(255, 226, 100), RGB(255, 140, 40) }, 4, "Stats") -- your stat points, from anywhere

local badge = text({
	Name = "Badge",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 8, 0, -8),
	Size = UDim2.fromOffset(48, 24),
	BackgroundTransparency = 0,
	BackgroundColor3 = C.red,
	Text = "0%",
	TextSize = 18,
	ZIndex = 5, -- above the button's label/icon
	Parent = prestigeBtn,
}, { corner(12), border(2.5) })

----------------------------------------------------------------------
-- HUD: bottom-left stats
----------------------------------------------------------------------
local statCol = create("Frame", {
	Name = "Stats",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 16, 1, -16),
	Size = UDim2.fromOffset(270, 180),
	BackgroundTransparency = 1,
	Parent = root,
}, {
	create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
	}),
})

-- Each stat: a big icon sitting on the left end of a dark strip that fades
-- out to the right, with a big outlined number on top.
local function statRow(icon, order, color)
	local row = create("Frame", {
		LayoutOrder = order,
		Size = UDim2.fromOffset(270, 56),
		BackgroundTransparency = 1,
		Parent = statCol,
	})
	create("Frame", {
		Name = "Strip",
		Position = UDim2.fromOffset(26, 8),
		Size = UDim2.new(1, -26, 1, -16),
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Parent = row,
	}, {
		corner(8),
		create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.65, 0.25),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	-- `icon` is "COIN", "TOKEN", an uploaded image id ("rbxassetid://..."), an
	-- emoji, or nil (no picture: the words say it, like "LV 256")
	if icon == nil then
		-- (nothing)
	elseif icon == "COIN" then
		coinIcon(row, 48, { Position = UDim2.fromOffset(4, 4) })
	elseif icon == "TOKEN" and require(game:GetService("ReplicatedStorage"):WaitForChild("MoneyIcons")).make(row, "Token", 48, { Position = UDim2.fromOffset(4, 4), ZIndex = 2 }) then
		-- (the living Holo token, once uploaded: ReplicatedStorage/MoneyIcons)
	elseif icon == "TOKEN" then
		-- an Arcade Token: a purple coin with a gold rim and a star (as on the Arcade)
		local rim = create("Frame", {
			Name = "Token",
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.fromOffset(48, 48),
			BackgroundColor3 = C.gold,
			ZIndex = 2,
			Parent = row,
		}, { corner(24), border(3) })
		local face = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.72, 0.72),
			BackgroundColor3 = RGB(104, 56, 108),
			ZIndex = 3,
			Parent = rim,
		}, { corner(18) })
		text({ Size = UDim2.fromScale(1, 1), Text = "★", TextSize = 24, TextColor3 = RGB(254, 231, 97), ZIndex = 4, Parent = face })
	elseif string.sub(icon, 1, 13) == "rbxassetid://" then
		create("ImageLabel", {
			Size = UDim2.fromOffset(52, 52),
			Position = UDim2.fromOffset(2, 2),
			BackgroundTransparency = 1,
			Image = icon,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 2,
			Parent = row,
		})
	else
		text({ Size = UDim2.fromOffset(56, 56), Text = icon, TextSize = 44, ZIndex = 2, Parent = row })
	end
	return text({
		Position = UDim2.fromOffset(icon and 66 or 40, 0),
		Size = UDim2.new(1, icon and -70 or -44, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 36,
		TextColor3 = color or C.white,
		ZIndex = 2,
		Parent = row,
	}, { stroke(3) }), row
end

-- your Arcade Tokens (the backpack's count used to be here): click it for the
-- Arcade's menu (ArcadeClient listens on ReplicatedStorage.ArcadeOpen)
local tokenText, tokenRow = statRow("TOKEN", 1, RGB(254, 231, 97))
do
	local click = create("TextButton", {
		Name = "OpenArcade",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = tokenRow,
	})
	click.Activated:Connect(function()
		local open = ReplicatedStorage:FindFirstChild("ArcadeOpen")
		if open and open:IsA("BindableEvent") then
			open:Fire()
		end
	end)
end
local coinText = statRow("COIN", 2, C.gold)
local prestigeText = statRow(nil, 3, RGB(254, 231, 97)) -- your level ("LV 256": no picture needed)

----------------------------------------------------------------------
-- HUD: hint banner, goal bar, right-side controls
----------------------------------------------------------------------
-- Hint: white text on a dark strip that fades out at both ends
-- (kept narrow enough to stay clear of the player list in the top right)
local hintBanner = create("Frame", {
	Name = "HintBanner",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 56),
	Size = UDim2.fromOffset(620, 52),
	BackgroundColor3 = C.ink,
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
	Parent = root,
}, {
	create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.22, 0),
			NumberSequenceKeypoint.new(0.78, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}),
})

local hint = text({
	Name = "Hint",
	Size = UDim2.fromScale(1, 1),
	Text = "Loading...",
	TextSize = 26,
	TextWrapped = true,
	Parent = hintBanner,
}, { stroke(3) })

-- Goal bar: chunky gold bar, goal on the left, progress numbers on the right
local barBack = create("Frame", {
	Name = "GoalBar",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.fromOffset(640, 46),
	BackgroundColor3 = RGB(46, 38, 22),
	BackgroundTransparency = 0.1,
	Parent = root,
}, { corner(10), border(4) })

local barFill = create("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = C.gold,
	BorderSizePixel = 0,
	Parent = barBack,
}, { corner(10), gradient({ RGB(255, 238, 120), RGB(255, 196, 40), RGB(255, 150, 20) }, 90) })

local barLabel = text({
	Position = UDim2.fromOffset(16, 0),
	Size = UDim2.new(0.62, -16, 1, 0),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextSize = 24,
	ZIndex = 2,
	Parent = barBack,
}, { stroke(3) })

local barText = text({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 0),
	Size = UDim2.new(0.38, -16, 1, 0),
	TextXAlignment = Enum.TextXAlignment.Right,
	TextSize = 24,
	ZIndex = 2,
	Parent = barBack,
}, { stroke(3) })

-- Your HP is THE HEART (see below, once we can find your character); your
-- Power sits beside it.
local powerText

-- Finding your character means searching through its parts, and several loops
-- below want it on every frame. Look it up once and keep it until you respawn.
local cachedChar, cachedHum, cachedRoot, cachedAnimator
local function characterBits()
	local char = player.Character
	if char ~= cachedChar then
		cachedChar = char
		cachedHum = char and char:FindFirstChildOfClass("Humanoid") or nil
		cachedRoot = char and char:FindFirstChild("HumanoidRootPart") or nil
		cachedAnimator = nil
	end
	if cachedHum and not cachedAnimator then
		cachedAnimator = cachedHum:FindFirstChildOfClass("Animator") -- it arrives a moment later
	end
	if cachedChar and not cachedRoot then
		cachedRoot = cachedChar:FindFirstChild("HumanoidRootPart")
	end
	return cachedHum, cachedRoot, cachedChar, cachedAnimator
end

-- THE HEART: your health is the red liquid inside a pixel-art heart, just
-- above the level bar - and in a fight the potion (your flasks) sits on its
-- left and the lightning bolt (your stamina) on its right. All three are
-- drawn by ReplicatedStorage/Vitals (CombatClient tells it about the fight);
-- it hands back the words either side of the heart, and your Power goes in
-- the one on the right. Tuning: Config.Heart and Config.Vitals.
do
	local vitals = Vitals.start({
		root = root,
		text = text,
		stroke = stroke,
		character = function()
			return (characterBits())
		end,
	})
	powerText = vitals.powerText
end

-- Big "LEVEL UP!" popup in the upper middle of the screen
local levelUpLabel = text({
	Name = "LevelUp",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.3),
	Size = UDim2.fromOffset(700, 90),
	TextSize = 64,
	TextColor3 = C.gold,
	Visible = false,
	ZIndex = 40,
	Parent = root,
}, { stroke(5), create("UIScale", { Name = "Pop" }) })
local levelUpToken = 0

----------------------------------------------------------------------
-- Panel: Upgrade Shop
----------------------------------------------------------------------
local upgradeRows = {}
do
	local p = makePanel("Upgrades", "UPGRADE SHOP", RGB(70, 150, 255), 500)
	for i, def in ipairs(Config.Upgrades) do
		local row = create("Frame", {
			LayoutOrder = i,
			Size = UDim2.new(1, -10, 0, 86),
			BackgroundColor3 = C.row,
			Parent = p.body,
		}, { corner(14) })
		text({
			Position = UDim2.fromOffset(10, 11),
			Size = UDim2.fromOffset(64, 64),
			BackgroundTransparency = 0,
			BackgroundColor3 = def.color,
			Text = def.icon,
			TextSize = 36,
			Parent = row,
		}, { corner(14), border(2.5) })
		text({
			Position = UDim2.fromOffset(88, 8),
			Size = UDim2.new(1, -270, 0, 28),
			Text = def.name,
			TextSize = 24,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		text({
			Position = UDim2.fromOffset(88, 36),
			Size = UDim2.new(1, -270, 0, 20),
			Text = def.desc,
			TextSize = 16,
			TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		local lvl = text({
			Position = UDim2.fromOffset(88, 58),
			Size = UDim2.new(1, -270, 0, 20),
			TextSize = 16,
			TextColor3 = C.green,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		local buy = button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(150, 54),
			Parent = row,
		})
		buy.Activated:Connect(function()
			doAction("BuyUpgrade", def.id)
		end)
		local coin = coinIcon(buy, 30, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0) })
		upgradeRows[def.id] = { lvl = lvl, buy = buy, coin = coin }
	end

	p.refresh = function()
		for _, def in ipairs(Config.Upgrades) do
			local ui = upgradeRows[def.id]
			local level = state.Upgrades[def.id] or 0
			ui.lvl.Text = "Lv. " .. level .. "/" .. def.maxLevel .. "   |   " .. def.effect(level)
			if level >= def.maxLevel then
				ui.buy.Text = "MAX"
				ui.coin.Visible = false
				paint(ui.buy, false, C.green)
			else
				local cost = Config.upgradeCost(def, level)
				ui.buy.Text = "    " .. Config.format(cost) -- room on the left for the coin picture
				ui.coin.Visible = true
				paint(ui.buy, state.Coins >= cost, C.green)
			end
		end
	end
end

----------------------------------------------------------------------
-- Panel: Sell Shop / Backpack (one panel, two modes)
----------------------------------------------------------------------
local sellUI = { rows = {} }
do
	local p = makePanel("Sell", "SELL SHOP", RGB(255, 190, 60), 540)
	sellUI.note = text({
		LayoutOrder = 0,
		Size = UDim2.new(1, -10, 0, 26),
		TextSize = 18,
		TextColor3 = C.dim,
		Parent = p.body,
	})
	sellUI.info = text({
		LayoutOrder = 1,
		Size = UDim2.new(1, -10, 0, 30),
		TextSize = 22,
		Parent = p.body,
	}, { stroke(2.5) })
	sellUI.all = button({
		LayoutOrder = 2,
		Size = UDim2.new(1, -10, 0, 58),
		BackgroundColor3 = C.green,
		Text = "SELL ALL",
		TextSize = 26,
		Parent = p.body,
	})
	sellUI.all.Activated:Connect(function()
		doAction("Sell", "All")
	end)

	for i, m in ipairs(Config.Materials) do
		local row = create("Frame", {
			LayoutOrder = 10 + i,
			Size = UDim2.new(1, -10, 0, 64),
			BackgroundColor3 = C.row,
			Parent = p.body,
		}, { corner(12) })
		create("Frame", {
			Position = UDim2.fromOffset(12, 14),
			Size = UDim2.fromOffset(36, 36),
			BackgroundColor3 = m.color,
			Parent = row,
		}, { corner(18), border(2.5) })
		text({
			Position = UDim2.fromOffset(62, 6),
			Size = UDim2.new(1, -230, 0, 26),
			Text = m.name,
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		local detail = text({
			Position = UDim2.fromOffset(62, 34),
			Size = UDim2.new(1, -230, 0, 22),
			TextSize = 16,
			TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		local btn = button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(110, 44),
			BackgroundColor3 = C.gold,
			Text = "SELL",
			Parent = row,
		})
		btn.Activated:Connect(function()
			doAction("Sell", m.id)
		end)
		sellUI.rows[m.id] = { detail = detail, btn = btn }
	end

	p.onOpen = function(mode)
		local selling = (mode == "Sell")
		p.title.Text = selling and "SELL SHOP" or "BACKPACK"
		sellUI.all.Visible = selling
		for _, r in pairs(sellUI.rows) do
			r.btn.Visible = selling
		end
		sellUI.note.Text = selling and "" or "Visit the Sell Shop to cash in your loot!"
	end

	p.refresh = function()
		local count = Config.lootCount(state)
		sellUI.info.Text = "Backpack " .. count .. "/" .. stats.capacity .. "   |   Coin bonus x" .. Config.formatMult(stats.coinMult)
		local total = 0
		for _, m in ipairs(Config.Materials) do
			local n = state.Loot[m.id] or 0
			total = total + n * m.sell
			local ui = sellUI.rows[m.id]
			ui.detail.Text = "x" .. n .. "   |   " .. Config.format(m.sell) .. " coins each   |   worth " .. Config.format(n * m.sell * stats.coinMult) .. " coins"
			paint(ui.btn, n > 0, C.gold)
		end
		sellUI.all.Text = "SELL ALL   " .. Config.format(total * stats.coinMult) .. " coins"
		paint(sellUI.all, total > 0, C.green)
	end
end

----------------------------------------------------------------------
-- Panel: Talisman Workbench
----------------------------------------------------------------------
local craftUI = { rows = {} }

local function colorize(str, ok)
	local hex = ok and "#7CFF9B" or "#FF6B6B"
	return '<font color="' .. hex .. '">' .. str .. "</font>"
end

local function canCraft(t)
	if state.Coins < t.cost.coins then
		return false
	end
	for matId, need in pairs(t.cost.materials) do
		if (state.Loot[matId] or 0) < need then
			return false
		end
	end
	return true
end

do
	local p = makePanel("Craft", "ARMORY", RGB(230, 90, 60), 580)
	craftUI.slots = text({
		LayoutOrder = 0,
		Size = UDim2.new(1, -10, 0, 30),
		TextSize = 22,
		Parent = p.body,
	}, { stroke(2.5) })

	for i, t in ipairs(Config.Talismans) do
		local row = create("Frame", {
			LayoutOrder = i,
			Size = UDim2.new(1, -10, 0, 92),
			BackgroundColor3 = C.row,
			Parent = p.body,
		}, { corner(14) })
		text({
			Position = UDim2.fromOffset(10, 14),
			Size = UDim2.fromOffset(64, 64),
			BackgroundTransparency = 0,
			BackgroundColor3 = t.color,
			Text = t.icon,
			TextSize = 34,
			Parent = row,
		}, { corner(32), border(2.5) })
		text({
			Position = UDim2.fromOffset(88, 6),
			Size = UDim2.new(1, -250, 0, 26),
			Text = t.name,
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		text({
			Position = UDim2.fromOffset(88, 32),
			Size = UDim2.new(1, -250, 0, 20),
			Text = t.desc,
			TextSize = 16,
			TextColor3 = C.gold,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		local recipe = text({
			Position = UDim2.fromOffset(88, 54),
			Size = UDim2.new(1, -250, 0, 34),
			TextSize = 15,
			RichText = true,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = row,
		})
		local btn = button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(130, 52),
			Parent = row,
		})
		btn.Activated:Connect(function()
			doAction(btn:GetAttribute("Action") or "Craft", t.id)
		end)
		craftUI.rows[t.id] = { recipe = recipe, btn = btn }
	end

	p.refresh = function()
		craftUI.slots.Text = "Equipped " .. Config.equippedCount(state) .. "/" .. Config.TalismanSlots .. "   |   Craft, then equip!"
		for _, t in ipairs(Config.Talismans) do
			local ui = craftUI.rows[t.id]
			if state.Owned[t.id] then
				if state.Equipped[t.id] then
					ui.recipe.Text = colorize("Equipped", true)
					ui.btn.Text = "UNEQUIP"
					ui.btn:SetAttribute("Action", "Unequip")
					paint(ui.btn, true, C.orange)
				else
					ui.recipe.Text = colorize("Owned - not equipped", true)
					ui.btn.Text = "EQUIP"
					ui.btn:SetAttribute("Action", "Equip")
					paint(ui.btn, true, C.blue)
				end
			else
				local parts = {}
				for _, m in ipairs(Config.Materials) do
					local need = t.cost.materials[m.id]
					if need then
						local have = state.Loot[m.id] or 0
						table.insert(parts, colorize(m.name .. " " .. have .. "/" .. need, have >= need))
					end
				end
				table.insert(parts, colorize(Config.format(t.cost.coins) .. " coins", state.Coins >= t.cost.coins))
				ui.recipe.Text = table.concat(parts, "  |  ")
				ui.btn.Text = "CRAFT"
				ui.btn:SetAttribute("Action", "Craft")
				paint(ui.btn, canCraft(t), C.green)
			end
		end
	end
end

----------------------------------------------------------------------
-- Panel: Stats (spend the points each level gives you, Blox Fruits style)
----------------------------------------------------------------------
local prestigeUI = {}
do
	local p = makePanel("Stats", "STATS", RGB(255, 190, 60), 560)
	prestigeUI.level = text({
		LayoutOrder = 1,
		Size = UDim2.new(1, -10, 0, 44),
		TextSize = 30,
		TextColor3 = C.gold,
		Parent = p.body,
	}, { stroke(3) })
	local rows = {}
	for i, st in ipairs(Config.StatPoints.Stats) do
		local row = create("Frame", {
			LayoutOrder = 1 + i,
			Size = UDim2.new(1, -10, 0, 78),
			BackgroundColor3 = C.row,
			Parent = p.body,
		}, { corner(12), border(3, st.color) })
		local name = text({
			Position = UDim2.fromOffset(16, 6),
			Size = UDim2.new(1, -250, 0, 34),
			TextSize = 26,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = st.color,
			Parent = row,
		}, { stroke(2.5) })
		local effect = text({
			Position = UDim2.fromOffset(16, 40),
			Size = UDim2.new(1, -250, 0, 28),
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = C.dim,
			Parent = row,
		})
		local function plus(label, n, x)
			local b = button({
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, x, 0.5, 0),
				Size = UDim2.fromOffset(n == 1 and 64 or 84, 52),
				Text = label,
				TextSize = 24,
				Parent = row,
			})
			b.Activated:Connect(function()
				doAction("SpendStat", { stat = st.id, n = n })
			end)
			return b
		end
		rows[st.id] = { name = name, effect = effect, one = plus("+1", 1, -104), ten = plus("+10", 10, -12) }
	end
	local reset = button({
		LayoutOrder = 10,
		Size = UDim2.new(1, -10, 0, 50),
		Text = "RESET POINTS (FREE)",
		TextSize = 22,
		Parent = p.body,
	})
	local confirmUntil = 0
	reset.Activated:Connect(function()
		if os.clock() >= confirmUntil then
			confirmUntil = os.clock() + 3
			reset.Text = "TAP AGAIN TO RESET"
			task.delay(3.1, function()
				reset.Text = "RESET POINTS (FREE)"
			end)
			return
		end
		confirmUntil = 0
		reset.Text = "RESET POINTS (FREE)"
		doAction("ResetStats")
	end)

	p.refresh = function()
		local left = Config.statPointsLeft(state)
		prestigeUI.level.Text = "Level " .. Config.levelFromPower(state.Power) .. "   -   " .. left .. " point" .. (left == 1 and "" or "s") .. " to spend"
		local bonus = Config.statBonus(state)
		for _, st in ipairs(Config.StatPoints.Stats) do
			local r = rows[st.id]
			local pts = (state.Stats and state.Stats[st.id]) or 0
			r.name.Text = st.name .. "  " .. pts
			local v = bonus[st.gives]
			r.effect.Text = "+" .. (math.floor(v * 10 + 0.5) / 10) .. st.desc
			paint(r.one, left >= 1, st.color)
			paint(r.ten, left >= 1, st.color)
		end
		paint(reset, Config.statPointsSpent(state) > 0, C.red)
	end
end

----------------------------------------------------------------------
-- Rendering
----------------------------------------------------------------------
local function renderHint()
	-- in a Spire arena the lobby's advice is noise: the fight has the top of the
	-- screen (the boss's name and health bar live there)
	hintBanner.Visible = Config.NewHud == false and player:GetAttribute("SpireFloor") == nil and not player:GetAttribute("Colosseum")
	if not state then
		hint.Text = "Loading..."
		return
	end
	local message
	local tokens = tonumber(state.Tokens) or 0
	-- (the Sell Shop is gone, so there's no "sell your loot" any more)
	if tokens > 0 then
		message = tokens == 1 and "You have an Arcade Token! Spin it at the Arcade for a weapon!"
			or ("You have " .. tokens .. " Arcade Tokens! Spin them at the Arcade for weapons!")
	elseif Config.statPointsLeft(state) > 0 then
		message = "You have " .. Config.statPointsLeft(state) .. " stat points! Spend them in STATS."
	else
		-- (you grow by fighting in the Colosseum)
		message = "Enter the Colosseum and beat dummies to grow stronger!"
	end
	hint.Text = message
end

local function renderBars()
	-- level bar: fills up from this level to the next
	local level = Config.levelFromPower(state.Power)
	local fromPower = Config.powerForLevel(level)
	local toPower = Config.powerForLevel(level + 1)
	barFill.Size = UDim2.fromScale(math.clamp((state.Power - fromPower) / math.max(toPower - fromPower, 1), 0, 1), 1)
	barLabel.Text = "Lv. " .. level
	barText.Text = Config.format(state.Power) .. " / " .. Config.format(toPower)

	-- the STATS button's badge: points waiting to be spent
	local left = Config.statPointsLeft(state)
	badge.Visible = left > 0
	badge.Text = tostring(left)
	badge.BackgroundColor3 = C.green
end

local function renderStats()
	tokenText.Text = tostring(tonumber(state.Tokens) or 0)
	coinText.Text = Config.format(state.Coins)
	powerText.Text = "Power: " .. Config.format(state.Power)
	prestigeText.Text = "LV " .. Config.levelFromPower(state.Power)
end

local function renderAll()
	if not state then
		return
	end
	stats = Config.stats(state)
	renderStats()
	renderBars()
	renderHint()
	local p = currentKey and panels[currentKey]
	if p and p.refresh then
		p.refresh()
	end
end

player:GetAttributeChangedSignal("SpireFloor"):Connect(renderHint)
player:GetAttributeChangedSignal("Colosseum"):Connect(renderHint)

----------------------------------------------------------------------
-- Move speed fix
----------------------------------------------------------------------
-- Your character is moved by a ControllerManager that Roblox creates on this
-- client. Its BaseMoveSpeed (default 16) is what actually sets how fast you
-- move - Humanoid.WalkSpeed, which the server sets from your Swift Boots
-- upgrade, is ignored by it. So every frame, copy WalkSpeed across. Cheap:
-- it only writes when the two differ.
local cachedManager = nil

RunService.Heartbeat:Connect(function()
	local hum, _, char = characterBits()
	if not hum or not char then
		return
	end
	if not (cachedManager and cachedManager:IsDescendantOf(char)) then
		cachedManager = char:FindFirstChildWhichIsA("ControllerManager", true)
		if not cachedManager then
			return
		end
	end
	if cachedManager.BaseMoveSpeed ~= hum.WalkSpeed then
		cachedManager.BaseMoveSpeed = hum.WalkSpeed
	end
end)

----------------------------------------------------------------------
-- Run animation
----------------------------------------------------------------------
-- Plays whenever you're actually moving on the ground. It checks your real
-- speed every frame instead of waiting for Humanoid.Running, which doesn't
-- fire reliably on a ControllerManager character like yours. The faster you
-- move (Swift Boots!), the faster the legs cycle, so it never looks like
-- you're sliding.
local RUN_ANIMATION_ID = "77081121019941"
local RUN_MIN_SPEED = 2 -- studs/sec before the run starts
local RUN_REFERENCE_SPEED = 16 -- plays at normal speed when moving this fast
local RUN_MAX_RATE = 2 -- never cycle the legs faster than 2x

local runTrack = nil
local runAnimator = nil

RunService.Heartbeat:Connect(function()
	local hum, root, char, animator = characterBits()
	if not (hum and root and char and animator) or hum.Health <= 0 then
		if runTrack and runTrack.IsPlaying then
			runTrack:Stop(0.1)
		end
		return
	end

	if runAnimator ~= animator then
		-- first time, or you respawned: load the animation on this character
		runAnimator = animator
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. RUN_ANIMATION_ID
		runTrack = animator:LoadAnimation(anim)
		runTrack.Priority = Enum.AnimationPriority.Action -- over the default walk, under punches
		runTrack.Looped = true
	end

	-- only on the ground, so jumping/falling still show their own animations
	local onGround
	if cachedManager and cachedManager:IsDescendantOf(char) and cachedManager.ActiveController then
		onGround = cachedManager.ActiveController:IsA("GroundController")
	else
		onGround = hum.FloorMaterial ~= Enum.Material.Air
	end

	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude

	if onGround and speed >= RUN_MIN_SPEED then
		if not runTrack.IsPlaying then
			runTrack:Play(0.15)
		end
		runTrack:AdjustSpeed(math.clamp(speed / RUN_REFERENCE_SPEED, 0.8, RUN_MAX_RATE))
	elseif runTrack.IsPlaying then
		runTrack:Stop(0.15)
	end
end)

----------------------------------------------------------------------
-- Remotes
----------------------------------------------------------------------
-- Big popup + ding when you level up.
-- Only fires going up - prestige drops your level, that's not a level up.
local function onLevelUp(oldLevel, newLevel)
	levelUpToken = levelUpToken + 1
	local mine = levelUpToken
	levelUpLabel.Text = "LEVEL UP!   Lv. " .. newLevel
	levelUpLabel.TextTransparency = 0
	local s = levelUpLabel:FindFirstChildOfClass("UIStroke")
	if s then
		s.Transparency = 0
	end
	levelUpLabel.Visible = true
	local pop = levelUpLabel:FindFirstChild("Pop")
	pop.Scale = 0.4
	tween(pop, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	playNamedSound(COMBO_DING_SOUND, 0.7, 1.2)
	task.delay(1.3, function()
		if levelUpToken ~= mine then
			return
		end
		tween(levelUpLabel, 0.4, { TextTransparency = 1 })
		if s then
			tween(s, 0.4, { Transparency = 1 })
		end
		task.delay(0.45, function()
			if levelUpToken == mine then
				levelUpLabel.Visible = false
			end
		end)
	end)
end

Remotes.StateUpdate.OnClientEvent:Connect(function(data)
	local oldLevel = state and Config.levelFromPower(state.Power)
	state = data
	renderAll()
	if oldLevel then
		local newLevel = Config.levelFromPower(state.Power)
		if newLevel > oldLevel then
			onLevelUp(oldLevel, newLevel)
		end
	end
end)

Remotes.Notify.OnClientEvent:Connect(function(message, kind)
	-- (while a new menu covers the screen, it shows the message itself: Menus)
	if player:GetAttribute("MenuOpen") then
		return
	end
	toast(message, kind)
end)

-- THE NEW LOBBY SCREEN (LobbyHud) has its own buttons, money and next goal:
-- the old left buttons, stats strip and hint line hide while Config.NewHud
-- is on. STATS opens from its button through ReplicatedStorage/Menus.
if Config.NewHud ~= false then
	leftCol.Visible = false
	statCol.Visible = false
	hintBanner.Visible = false
end
do
	local ok, Menus = pcall(require, ReplicatedStorage:WaitForChild("Menus", 5))
	if ok and type(Menus) == "table" then
		Menus.external.Stats = function()
			openPanel("Stats", true)
		end
	end
end

Remotes.OpenPanel.OnClientEvent:Connect(function(name)
	openPanel(name, true)
end)

----------------------------------------------------------------------
-- Menus open by themselves at each shop
----------------------------------------------------------------------
-- Every shop has an invisible "AutoOpenZone" box in front of it (made by
-- LobbyBuilder). Walk into one and that shop's menu pops up; walk out and it
-- closes. If you close it yourself while still standing there, it stays
-- closed until you step out and come back. Menus you opened with the HUD
-- buttons (like the Backpack) are left alone.
local autoZones = {}
local function addAutoZone(zone)
	if zone:IsA("BasePart") and zone:GetAttribute("Panel") then
		autoZones[zone] = zone:GetAttribute("Panel")
	end
end
for _, z in ipairs(CollectionService:GetTagged("AutoOpenZone")) do
	addAutoZone(z)
end
CollectionService:GetInstanceAddedSignal("AutoOpenZone"):Connect(addAutoZone)
CollectionService:GetInstanceRemovedSignal("AutoOpenZone"):Connect(function(z)
	autoZones[z] = nil
end)

-- the old "press E" prompts aren't needed any more: hide them on this screen
local function hidePrompt(prompt)
	if prompt:IsA("ProximityPrompt") then
		prompt.Enabled = false
	end
end
for _, pr in ipairs(CollectionService:GetTagged("PanelPrompt")) do
	hidePrompt(pr)
end
CollectionService:GetInstanceAddedSignal("PanelPrompt"):Connect(hidePrompt)

local ZONE_EXIT_MARGIN = 2 -- studs of slack before a menu closes, so it doesn't flicker at the edge
local function insideZone(zone, pos, margin)
	local rel = zone.CFrame:PointToObjectSpace(pos)
	local half = zone.Size / 2
	return math.abs(rel.X) <= half.X + margin and math.abs(rel.Y) <= half.Y + margin and math.abs(rel.Z) <= half.Z + margin
end

local autoPanel = nil -- the menu this system opened (and may close)
local dismissedPanel = nil -- closed by hand while standing in its zone
local lastZoneCheck = 0
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now - lastZoneCheck < 0.1 then
		return
	end
	lastZoneCheck = now
	local _, hrp = characterBits()
	if not hrp then
		return
	end
	local pos = hrp.Position
	local here = nil
	-- stay in the current zone using the slightly bigger exit box
	if autoPanel or dismissedPanel then
		for zone, panel in pairs(autoZones) do
			if (panel == autoPanel or panel == dismissedPanel) and zone.Parent and insideZone(zone, pos, ZONE_EXIT_MARGIN) then
				here = panel
				break
			end
		end
	end
	if not here then
		for zone, panel in pairs(autoZones) do
			if zone.Parent and insideZone(zone, pos, 0) then
				here = panel
				break
			end
		end
	end

	if here then
		if autoPanel == here and currentKey ~= here then
			-- they closed it themselves: leave it closed until they step out
			dismissedPanel = here
			autoPanel = nil
		elseif autoPanel ~= here and dismissedPanel ~= here then
			if currentKey == here then
				autoPanel = here -- already open (e.g. from a HUD button): close it when they leave
			elseif currentKey == nil or currentKey == autoPanel then
				openPanel(here, true)
				autoPanel = here
			end
		end
	else
		if autoPanel and currentKey == autoPanel then
			closePanels()
		end
		autoPanel = nil
		dismissedPanel = nil
	end
end)

----------------------------------------------------------------------
-- THE DEV CONSOLE: test buttons for you (Studio, or the game's owner in the
-- real game - see Config.isDev; the server checks every button again). A
-- small DEV button bottom-right opens and closes it, so the screen stays
-- clean while you play.
----------------------------------------------------------------------
do
	local devCol = create("Frame", {
		Name = "DevTools",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -52),
		Size = UDim2.fromOffset(150, 456),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	}, {
		create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	-- play the intro (Oozlet) again, from the start
	local replay = button({
		LayoutOrder = 5,
		Size = UDim2.fromOffset(150, 36),
		Text = "DEV: Replay Intro",
		TextSize = 16,
		BackgroundColor3 = RGB(62, 137, 72),
		Parent = devCol,
	})
	replay.Activated:Connect(function()
		doAction("DevReplayIntro")
	end)
	-- the weapon test: hold the test sword (again: back to fists), and level its
	-- mastery up a quarter at a time (25, 50, 75, 100, then back to 1)
	for i, what in ipairs({ { "DEV: Test Sword", "DevTestWeapon" }, { "DEV: Mastery +25", "DevMastery" }, { "DEV: Next Sword", "DevNextWeapon" }, { "DEV: All Weapons", "DevAllWeapons" } }) do
		local b = button({
			LayoutOrder = 6 + i,
			Size = UDim2.fromOffset(150, 36),
			Text = what[1],
			TextSize = 16,
			BackgroundColor3 = RGB(104, 56, 108),
			Parent = devCol,
		})
		b.Activated:Connect(function()
			doAction(what[2])
		end)
	end
	local DEV_LABELS = { Tokens = "DEV: +10 Tokens", Loot = "DEV: +Loot", Coins = "DEV: +Coins", Power = "DEV: +Power", MaxUpgrades = "DEV: Max Upgrades" }
	for i, kind in ipairs({ "Tokens", "Loot", "Coins", "Power", "MaxUpgrades" }) do
		local b = button({
			LayoutOrder = i - 1,
			Size = UDim2.fromOffset(150, 36),
			Text = DEV_LABELS[kind],
			TextSize = 16,
			BackgroundColor3 = RGB(96, 96, 124),
			Parent = devCol,
		})
		b.Activated:Connect(function()
			doAction("DevGive", kind)
		end)
	end
	-- SET LEVEL: type a level, press the button (the server sets your Power
	-- to that level's and refunds your stat points)
	local levelRow = create("Frame", {
		LayoutOrder = 6,
		Size = UDim2.fromOffset(150, 36),
		BackgroundTransparency = 1,
		Parent = devCol,
	})
	local levelBox = create("TextBox", {
		Size = UDim2.fromOffset(52, 36),
		BackgroundColor3 = RGB(24, 20, 37),
		BorderSizePixel = 0,
		Font = FONT,
		PlaceholderText = "Lv",
		Text = "",
		TextSize = 18,
		TextColor3 = RGB(255, 255, 255),
		ClearTextOnFocus = true,
		Parent = levelRow,
	}, { corner(8) })
	local setLevel = button({
		Position = UDim2.fromOffset(58, 0),
		Size = UDim2.fromOffset(92, 36),
		Text = "Set Level",
		TextSize = 16,
		BackgroundColor3 = RGB(18, 78, 137),
		Parent = levelRow,
	})
	local function applyLevel()
		local n = tonumber(levelBox.Text)
		if n then
			doAction("DevSetLevel", math.floor(n))
		else
			toast("Type a level number first.", "bad")
		end
	end
	setLevel.Activated:Connect(applyLevel)
	levelBox.FocusLost:Connect(function(enter)
		if enter then
			applyLevel()
		end
	end)
	local toggle = button({
		Name = "DevToggle",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(70, 30),
		Text = "DEV",
		TextSize = 16,
		BackgroundColor3 = RGB(162, 38, 51),
		Visible = false,
		Parent = root,
	})
	local open = false
	local function showDev()
		local dev = RunService:IsStudio() or player:GetAttribute("Dev") == true
		toggle.Visible = dev
		devCol.Visible = dev and open
	end
	toggle.Activated:Connect(function()
		open = not open
		showDev()
	end)
	showDev()
	player:GetAttributeChangedSignal("Dev"):Connect(showDev)
end

-- Ask for the first snapshot (listeners above are already connected)
Remotes.RequestState:FireServer()
