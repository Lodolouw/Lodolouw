--[[
	Hud  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "Hud")

	Builds the whole GUI from code (no assets needed):
	  * left 2x2 buttons: Upgrades, Backpack, Armory (talismans), Prestige (with % badge)
	  * bottom-left: backpack / coins / power
	  * top hint banner, bottom goal bar, right-side AUTO TRAIN button
	  * panels: Upgrade Shop, Sell Shop / Backpack, Talisman Workbench, Prestige
	  * click-to-train on the dummy pads, with hit effects and floating numbers
	  * live "UNLOCKED / needs X Power" text on the multiplier signs

	The server owns all data; this script only displays it and sends requests.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
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

-- Combo tracking (purely cosmetic - never changes Power, just makes hitting feel better)
-- Combo state. The server counts the combo (it boosts real Power, so it can't
-- be trusted to the client) and tells us the count + multiplier on every hit;
-- we just keep the latest values here for the sounds, popups and combo meter.
local combo = { count = 0, mult = 1, resetAt = 0 }
local COMBO_STEP = 10 -- a "milestone" popup fires every N consecutive hits

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

-- The dummy-hit sound the developer dropped into SoundService. Just this one
-- sound plays on a hit now - it used to be layered with a second "ting" on
-- top, but that stayed audible alongside the punch sound, which wasn't
-- wanted.
local DUMMY_PUNCH_SOUND = "dummy punch"

-- Pitch climbs a little with every hit in a combo, then drops back after the
-- 10-hit milestone and builds again - so a combo audibly "builds up" to its
-- payoff. It's the same sound played slightly faster, no extra asset needed.
local COMBO_PITCH_STEP = 0.035 -- per hit, so +31.5% by the 10th hit

-- The ding the developer dropped into SoundService. Plays when you reach a
-- new combo tier (x1.1, x1.25, x1.5, x2), a little higher for each tier, so
-- climbing the tiers sounds like going up a scale. If you rename the sound in
-- SoundService, change the name here to match.
local COMBO_DING_SOUND = "Minecraft Sound Successful Bow Hit Ding"
local COMBO_DING_PITCHES = { 1, 1.122, 1.26, 1.498 } -- tier 1-4: do, re, mi, sol

local function playComboDing(tierIndex)
	local pitch = COMBO_DING_PITCHES[math.min(tierIndex, #COMBO_DING_PITCHES)] or 1
	playNamedSound(COMBO_DING_SOUND, 0.6, pitch)
end

local function playImpactSound(power, comboCount)
	local jitter = (math.random() - 0.5)
	local buildUp = ((comboCount or 1) - 1) % COMBO_STEP * COMBO_PITCH_STEP
	local pitch = 0.85 + jitter * 0.06 + power * 0.03 + buildUp
	playNamedSound(DUMMY_PUNCH_SOUND, 0.4 + math.random() * 0.08, pitch)
end

-- Punch animation: alternates left/right each hit, like hitting a bag.
-- It plays the moment you click (not when the server replies), so the fist is
-- already swinging when the dummy reacts. If you're clicking faster than the
-- animation is long, it's sped up so one swing fits exactly between two hits
-- instead of being cut off halfway - that's what looked out of sync before.
local PUNCH_ANIMATION_IDS = {
	"140534557983022", -- Punch 1
	"128188028965818", -- Punch 2
}
local MAX_PUNCH_SPEED = 4 -- never speed a swing up more than this

local punchTracks = {} -- [animationId] = AnimationTrack, for the current Animator
local punchAnimator = nil
local punchIndex = 0
local lastPunchAt = 0

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

local function playPunch()
	local now = os.clock()
	local gap = now - lastPunchAt
	lastPunchAt = now

	punchIndex = punchIndex % #PUNCH_ANIMATION_IDS + 1
	local track = getPunchTrack(PUNCH_ANIMATION_IDS[punchIndex])
	if not track then
		return
	end

	-- stop the other hand's swing so the two don't blend into mush
	for _, other in pairs(punchTracks) do
		if other ~= track and other.IsPlaying then
			other:Stop(0.05)
		end
	end

	local speed = 1
	if track.Length > 0 and gap < track.Length then
		speed = math.clamp(track.Length / gap, 1, MAX_PUNCH_SPEED)
	end
	track:Play(0.05, 1, speed)
end

-- Face the dummy while punching. Your character is turned by a
-- ControllerManager, and the punch animations were making it spin in place.
-- So for a moment after each punch (only while you're not walking), point
-- it straight at the dummy on the pad you're standing on. Runs just after
-- Roblox's own movement controls each frame, so it gets the final say.
local FACE_DUMMY_SECONDS = 0.6
local DUMMY_OFFSET_Z = 6 -- dummies stand this far back on their pad (see LobbyBuilder)

RunService:BindToRenderStep("FaceDummyWhilePunching", Enum.RenderPriority.Input.Value + 1, function()
	if os.clock() - lastPunchAt > FACE_DUMMY_SECONDS then
		return
	end
	local zi = player:GetAttribute("CurrentZone") or 0
	if zi < 1 then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local manager = char and char:FindFirstChildWhichIsA("ControllerManager", true)
	if not (root and manager) then
		return
	end
	if manager.MovingDirection.Magnitude > 0.1 then
		return -- walking: let normal controls decide which way you face
	end
	local pad = Config.zonePosition(zi)
	local toDummy = Vector3.new(pad.X - root.Position.X, 0, pad.Z + DUMMY_OFFSET_Z - root.Position.Z)
	if toDummy.Magnitude < 0.5 then
		return
	end
	manager.FacingDirection = toDummy.Unit
end)

-- A tiny "camera punch" so a hit is felt, not just seen - a couple of studs of
-- kick that springs back out over a fraction of a second.
local function cameraPunch(strength)
	if player:GetAttribute("SpireFloor") then
		return -- in an arena the combat script owns the camera; two of us shaking it fight
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local kick = Vector3.new((math.random() - 0.5), math.random() * 0.6, 0) * strength
	hum.CameraOffset = kick
	tween(hum, 0.22, { CameraOffset = Vector3.new() }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

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
	Upgrades = CFrame.new(Config.Stations.Upgrades) * CFrame.Angles(0, math.rad(-90), 0) * CFrame.new(0, 0, 13) * CFrame.Angles(0, math.pi, 0), -- (in front of the toad)
	Backpack = CFrame.new(Config.Stations.Sell) * CFrame.Angles(0, math.rad(90), 0) * CFrame.new(0, 0, 11) * CFrame.Angles(0, math.pi, 0),
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
	-- `icon` is "COIN", an uploaded image id ("rbxassetid://..."), or an emoji
	if icon == "COIN" then
		coinIcon(row, 48, { Position = UDim2.fromOffset(4, 4) })
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
		Position = UDim2.fromOffset(66, 0),
		Size = UDim2.new(1, -70, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 36,
		TextColor3 = color or C.white,
		ZIndex = 2,
		Parent = row,
	}, { stroke(3) })
end

local capText = statRow(BUTTON_ICON_IMAGES.Backpack ~= "" and BUTTON_ICON_IMAGES.Backpack or "🎒", 1)
local coinText = statRow("COIN", 2, C.gold)
local prestigeText = statRow("⭐", 3, RGB(254, 231, 97)) -- your level

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
-- above the level bar. Take a hit and it sloshes, drops spill out over the
-- rim and the heart shakes; drink a flask and it pours back in; low on health
-- it beats and blinks red; and when it runs dry the heart cracks in two and
-- shatters (like the SOUL in Undertale) - and forms again when you're back.
-- The level is measured by how much of the heart is full, not how high:
-- half your health really is half the heart. Tuning: Config.Heart.
do
	local H = Config.Heart or {}
	local PX = H.Pixel or 5 -- screen pixels per pixel of the heart
	-- the heart: "O" its outline, "." inside (where the liquid goes)
	local SHAPE = {
		"  OOOO   OOOO  ",
		" O....O O....O ",
		"O......O......O",
		"O.............O",
		"O.............O",
		"O.............O",
		" O...........O ",
		"  O.........O  ",
		"   O.......O   ",
		"    O.....O    ",
		"     O...O     ",
		"      O.O      ",
		"       O       ",
	}
	local ROWS, COLS = #SHAPE, #SHAPE[1]
	local MID = (COLS + 1) / 2
	local OUTLINE = RGB(24, 20, 37)
	local GLASS = RGB(38, 43, 68)
	local LIQUID = RGB(228, 59, 68)
	local SURFACE = RGB(246, 117, 122)
	local DEEP = RGB(162, 38, 51)
	local BUBBLE = RGB(255, 190, 190)
	local HURT = RGB(255, 0, 68)
	local WHITE = RGB(255, 255, 255)
	local LOW = H.Low or 0.25 -- below this much health it beats and blinks
	local BASE_Y = -66

	local vessel = create("Frame", {
		Name = "HeartVessel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, BASE_Y),
		Size = UDim2.fromOffset(COLS * PX, ROWS * PX),
		BackgroundTransparency = 1,
		Parent = root,
	})
	local beat = create("UIScale", { Parent = vessel })
	-- (its own look: the retro restyler leaves every piece of it alone)
	local function own(inst)
		inst:SetAttribute("RetroSkip", true)
		return inst
	end
	own(vessel)
	-- two halves (split down a zigzag through the middle), for when it breaks
	local halves = {}
	for i = 1, 2 do
		halves[i] = own(create("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = vessel }))
	end
	local function pixel(parent, x, y, color, z)
		return own(create("Frame", {
			BorderSizePixel = 0,
			BackgroundColor3 = color,
			Position = UDim2.fromOffset((x - 1) * PX, (y - 1) * PX),
			Size = UDim2.fromOffset(PX, PX),
			ZIndex = z,
			Parent = parent,
		}))
	end

	-- every square of it; "layer" = how high a square sits above the bottom tip
	local bottomRow = 0
	for y = 1, ROWS do
		if string.find(SHAPE[y], ".", 1, true) then
			bottomRow = y
		end
	end
	local cells, outline, byCol, perLayer = {}, {}, {}, {}
	local LAYERS = 0
	for y = 1, ROWS do
		for x = 1, COLS do
			local ch = string.sub(SHAPE[y], x, x)
			if ch ~= " " then
				local half = (x < MID or (x == MID and y % 2 == 1)) and halves[1] or halves[2]
				if ch == "O" then
					table.insert(outline, pixel(half, x, y, OUTLINE, 3))
				else
					local c = { f = pixel(half, x, y, GLASS, 2), x = x, layer = bottomRow - y, color = GLASS }
					c.f.BackgroundTransparency = 0.15
					table.insert(cells, c)
					byCol[x] = byCol[x] or {}
					byCol[x][c.layer] = c
					perLayer[c.layer] = (perLayer[c.layer] or 0) + 1
					LAYERS = math.max(LAYERS, c.layer + 1)
				end
			end
		end
	end
	-- the shine on the glass
	for _, g in ipairs({ { 3, 3 }, { 4, 3 }, { 3, 4 } }) do
		pixel(halves[1], g[2], g[1], WHITE, 4).BackgroundTransparency = 0.45
	end

	-- how high the liquid stands (in layers) when `f` of the heart is full
	local function heightFor(f)
		local want = f * #cells
		for L = 0, LAYERS - 1 do
			local n = perLayer[L] or 0
			if want <= n then
				return L + (n > 0 and want / n or 0)
			end
			want = want - n
		end
		return LAYERS
	end

	-- the HP numbers on its left
	local hpText = text({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0.5, -(COLS * PX) / 2 - 10, 1, BASE_Y - ROWS * PX / 2),
		Size = UDim2.fromOffset(170, 30),
		RichText = true,
		Text = "",
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = root,
	}, { stroke(3) })
	-- your Power on its right
	powerText = text({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, (COLS * PX) / 2 + 10, 1, BASE_Y - ROWS * PX / 2),
		Size = UDim2.fromOffset(220, 30),
		Text = "Power: 0",
		TextSize = 22,
		TextColor3 = RGB(110, 190, 255),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = root,
	}, { stroke(3) })

	-- drops of it (spilled, poured in) and shards (when it breaks)
	local drops = {}
	local function drop(x, y, vx, vy, color, size, life, into)
		local f = own(create("Frame", {
			BorderSizePixel = 0,
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(size, size),
			Position = UDim2.fromOffset(x, y),
			ZIndex = 5,
			Parent = vessel,
		}))
		table.insert(drops, { f = f, x = x, y = y, vx = vx, vy = vy, age = 0, life = life, into = into })
	end
	local surfaceY -- (set every frame: where the top of the liquid is, in pixels)

	local shown, target = 1, 1 -- how full it's drawn / how full it should be
	local amp, clock, shake, flash = 0, 0, 0, 0
	local broken = nil -- seconds since it broke (nil: whole)
	local bubble = nil
	local nextBubble = 1
	local lastHum, lastText = nil, nil
	local outlineColor = OUTLINE

	local function spill(loss)
		local n = math.clamp(math.floor(loss * (H.Drops or 36) + 0.5), 3, H.MaxDrops or 12)
		for _ = 1, n do
			local x = (MID - 4 + math.random() * 8) * PX
			local side = math.random() < 0.5 and -1 or 1
			drop(x, surfaceY or PX * 3, side * (40 + math.random() * 70), -(90 + math.random() * 90),
				math.random() < 0.3 and SURFACE or LIQUID, PX * (0.6 + math.random() * 0.5), 0.9 + math.random() * 0.3)
		end
	end
	local function pour(gain)
		local n = math.clamp(math.floor(gain * 20 + 0.5), 3, 8)
		for i = 1, n do
			drop((MID - 0.5 + (math.random() - 0.5) * 1.2) * PX, -PX * (2 + i * 1.6), 0, 60, LIQUID, PX * 0.7, 2, true)
		end
	end
	local function shatter()
		broken = 0
		flash = 0.12
	end
	local function mend()
		broken = nil
		for i, h in ipairs(halves) do
			h.Visible = true
			h.Position = UDim2.fromOffset(0, 0)
		end
		shown = 0 -- (and it fills back up, poured in)
		pour(1)
	end

	RunService.RenderStepped:Connect(function(dt)
		dt = math.min(dt, 0.1)
		clock = clock + dt
		local hum = characterBits()
		if hum and hum.MaxHealth > 0 then
			local f = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
			local words = '<font color="#FEE761">HP</font> ' .. math.ceil(math.max(hum.Health, 0)) .. "/" .. math.floor(hum.MaxHealth)
			if words ~= lastText then
				lastText = words
				hpText.Text = words
			end
			if hum ~= lastHum then
				-- a new you (respawned): no spilling over the change
				lastHum = hum
				target = f
				if broken and f > 0 then
					mend()
				end
			elseif f < target - 0.001 then
				-- a hit: it sloshes, spills, shakes and flashes
				local loss = target - f
				target = f
				amp = math.min(H.Slosh or 1.6, amp + 0.5 + loss * 4)
				shake, flash = 1, 0.09
				spill(loss)
				if f <= 0 and not broken then
					shatter()
				end
			elseif f > target + 0.001 then
				local gain = f - target
				target = f
				if gain > 0.03 then
					pour(gain)
				end
				if broken and f > 0 then
					mend()
				end
			end
		end

		-- the level catches up: drains fast, fills slower
		if shown > target then
			shown = math.max(target, shown - dt * (H.Drain or 1.2))
		elseif shown < target then
			shown = math.min(target, shown + dt * (H.Fill or 0.5))
		end
		amp = amp * math.exp(-2.5 * dt)
		local h = heightFor(shown)
		surfaceY = (bottomRow + 1 - h) * PX

		-- the liquid, square by square (only the ones that change are touched)
		local calm = math.min(1, h * 2, (LAYERS - h) * 1.5)
		local tilt = amp * 0.6 * math.sin(clock * 6)
		local filled = {}
		for _, c in ipairs(cells) do
			local wave = amp * math.sin(c.x * 0.8 + clock * 9) + tilt * (c.x - MID) / MID + 0.12 * math.sin(c.x * 0.7 + clock * 3)
			filled[c] = h > 0.02 and c.layer + 0.5 < h + wave * calm
		end
		-- a bubble now and then, rising through it
		if not bubble and clock > nextBubble and h > 2 then
			local col = math.random(MID - 3, MID + 3)
			bubble = { x = col, layer = 0, t = 0 }
		end
		if bubble then
			bubble.t = bubble.t + dt
			if bubble.t > 0.12 then
				bubble.t = 0
				bubble.layer = bubble.layer + 1
			end
			local c = byCol[bubble.x] and byCol[bubble.x][bubble.layer]
			if not c or not filled[c] then
				bubble = nil
				nextBubble = clock + 0.8 + math.random() * 1.6
			end
		end
		for _, c in ipairs(cells) do
			local color = GLASS
			if filled[c] then
				local above = byCol[c.x][c.layer + 1]
				if not above or not filled[above] then
					color = SURFACE
				elseif c.layer <= 1 then
					color = DEEP
				else
					color = LIQUID
				end
				if bubble and bubble.x == c.x and bubble.layer == c.layer then
					color = BUBBLE
				end
			end
			if color ~= c.color then
				c.color = color
				c.f.BackgroundColor3 = color
				c.f.BackgroundTransparency = (color == GLASS) and 0.15 or 0
			end
		end

		-- the outline: a white flash when hit; beating and blinking red when low
		flash = math.max(0, flash - dt)
		local low = target > 0 and target < LOW and not broken
		local pulse = low and math.max(0, math.sin(clock * (target < LOW / 2 and 11 or 7))) ^ 6 or 0
		local want = flash > 0 and WHITE or (pulse > 0.3 and HURT or OUTLINE)
		if want ~= outlineColor then
			outlineColor = want
			for _, o in ipairs(outline) do
				o.BackgroundColor3 = want
			end
		end
		beat.Scale = 1 + 0.1 * pulse
		shake = math.max(0, shake - dt * 3.5)
		local sx, sy = (math.random() - 0.5) * 8 * shake, (math.random() - 0.5) * 8 * shake
		vessel.Position = UDim2.new(0.5, math.floor(sx), 1, BASE_Y + math.floor(sy))

		-- breaking: the halves part along the crack... then it shatters
		if broken then
			broken = broken + dt
			if broken < 0.6 then
				local gap = math.min(broken * 12, 3)
				halves[1].Position = UDim2.fromOffset(-gap, 0)
				halves[2].Position = UDim2.fromOffset(gap, 0)
			elseif halves[1].Visible then
				halves[1].Visible, halves[2].Visible = false, false
				for i = 1, 10 do
					local a = (i / 10) * math.pi * 2
					drop(MID * PX, ROWS * PX * 0.45, math.cos(a) * (60 + math.random() * 60), -60 - math.random() * 80,
						(i % 3 == 0) and OUTLINE or LIQUID, PX * 1.3, 1.2)
				end
			end
		end

		-- the drops: flung out and falling; poured ones vanish into the liquid
		for i = #drops, 1, -1 do
			local d = drops[i]
			d.age = d.age + dt
			d.vy = d.vy + 520 * dt
			d.x, d.y = d.x + d.vx * dt, d.y + d.vy * dt
			local gone = d.age >= d.life or (d.into and d.y >= (surfaceY or 0))
			if gone then
				if d.into then
					amp = math.min(H.Slosh or 1.6, amp + 0.15)
				end
				d.f:Destroy()
				table.remove(drops, i)
			else
				d.f.Position = UDim2.fromOffset(math.floor(d.x), math.floor(d.y))
				local fade = d.into and 0 or math.clamp((d.age - (d.life - 0.3)) / 0.3, 0, 1)
				d.f.BackgroundTransparency = fade
			end
		end
	end)
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

local rightCol = create("Frame", {
	Name = "RightControls",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -16, 0.5, 0),
	Size = UDim2.fromOffset(200, 222),
	BackgroundTransparency = 1,
	Parent = root,
}, {
	create("UIListLayout", {
		Padding = UDim.new(0, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local autoBtn = create("TextButton", {
	LayoutOrder = 2,
	Size = UDim2.fromOffset(200, 60),
	BackgroundColor3 = C.red,
	Text = "",
	AutoButtonColor = true,
	BorderSizePixel = 0,
	Parent = rightCol,
}, { corner(16), border(3.5) })

local autoText = text({
	Size = UDim2.fromScale(1, 1),
	Text = "AUTO TRAIN: OFF",
	TextSize = 21,
	Parent = autoBtn,
}, { stroke(2.5) })

autoBtn.Activated:Connect(function()
	if state then
		doAction("SetAuto", not state.Auto)
	end
end)

-- Combo meter: only shows while a combo is running. Big hit count, the
-- current multiplier, what the next tier needs, and a bar that drains over
-- the combo window - if it empties before your next hit, the combo breaks.
local comboBox = create("Frame", {
	LayoutOrder = 3,
	Size = UDim2.fromOffset(200, 98),
	BackgroundColor3 = C.panelDark,
	BackgroundTransparency = 0.15,
	Visible = false,
	Parent = rightCol,
}, { corner(16), border(3, C.orange), create("UIScale", { Name = "Pop" }) })

local comboCountText = text({
	Position = UDim2.fromOffset(0, 4),
	Size = UDim2.new(1, 0, 0, 34),
	TextSize = 30,
	TextColor3 = C.gold,
	Parent = comboBox,
}, { stroke(3) })

local comboMultText = text({
	Position = UDim2.fromOffset(0, 38),
	Size = UDim2.new(1, 0, 0, 22),
	TextSize = 19,
	TextColor3 = C.orange,
	Parent = comboBox,
}, { stroke(2.5) })

local comboNextText = text({
	Position = UDim2.fromOffset(0, 60),
	Size = UDim2.new(1, 0, 0, 16),
	TextSize = 14,
	TextColor3 = C.dim,
	Parent = comboBox,
})

local comboBarBack = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -8),
	Size = UDim2.new(1, -24, 0, 8),
	BackgroundColor3 = C.ink,
	BorderSizePixel = 0,
	Parent = comboBox,
}, { corner(4) })

local comboBarFill = create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = C.orange,
	BorderSizePixel = 0,
	Parent = comboBarBack,
}, { corner(4) })

local function nextComboTier(count)
	for _, tier in ipairs(Config.ComboTiers) do
		if count < tier.hits then
			return tier
		end
	end
	return nil
end

local shownComboCount = 0
RunService.RenderStepped:Connect(function()
	local left = combo.resetAt - os.clock()
	if combo.count <= 1 or left <= 0 then
		comboBox.Visible = false
		shownComboCount = 0
		return
	end
	comboBox.Visible = true
	comboBarFill.Size = UDim2.fromScale(math.clamp(left / Config.ComboWindow, 0, 1), 1)
	if combo.count ~= shownComboCount then
		shownComboCount = combo.count
		comboCountText.Text = combo.count .. " COMBO"
		comboMultText.Text = combo.mult > 1 and ("x" .. Config.formatMult(combo.mult) .. " Power") or "no bonus yet"
		local nextTier = nextComboTier(combo.count)
		comboNextText.Text = nextTier and ("x" .. Config.formatMult(nextTier.mult) .. " at " .. nextTier.hits .. " hits") or "MAX COMBO!"
		-- little bump on every hit
		local pop = comboBox:FindFirstChild("Pop")
		if pop then
			pop.Scale = 1.08
			tween(pop, 0.12, { Scale = 1 })
		end
	end
end)

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
local function currentZone()
	return player:GetAttribute("CurrentZone") or 0
end

local function renderHint()
	-- in a Spire arena the lobby's advice is noise: the fight has the top of the
	-- screen (the boss's name and health bar live there)
	hintBanner.Visible = player:GetAttribute("SpireFloor") == nil
	if not state then
		hint.Text = "Loading..."
		return
	end
	local zi = currentZone()
	local message
	if zi > 0 then
		local z = Config.Zones[zi]
		if state.Power >= z.req then
			local verb = UserInputService.TouchEnabled and "Tap" or "Click"
			message = verb .. " to train!   x" .. Config.formatMult(z.mult) .. " Power"
		else
			message = "Locked! Reach Level " .. z.level .. " to use the " .. z.name
		end
	elseif Config.lootCount(state) > 0 then
		message = "You're carrying loot - sell it at the Sell Shop!"
	elseif Config.statPointsLeft(state) > 0 then
		message = "You have " .. Config.statPointsLeft(state) .. " stat points! Spend them in STATS."
	else
		message = "Step onto a glowing dummy pad and click to grow stronger!"
		for _, z in ipairs(Config.Zones) do
			if state.Power < z.req then
				message = "Reach Level " .. z.level .. " to unlock the " .. z.name .. "!"
				break
			end
		end
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
	local count = Config.lootCount(state)
	capText.Text = count .. "/" .. stats.capacity
	capText.TextColor3 = count >= stats.capacity and C.red or C.white
	coinText.Text = Config.format(state.Coins)
	powerText.Text = "Power: " .. Config.format(state.Power)
	prestigeText.Text = "LV " .. Config.levelFromPower(state.Power)
	autoText.Text = state.Auto and "AUTO TRAIN: ON" or "AUTO TRAIN: OFF"
	autoBtn.BackgroundColor3 = state.Auto and C.green or C.red
end

local function renderZoneSigns()
	for _, sign in ipairs(CollectionService:GetTagged("ZoneSign")) do
		local zi = sign:GetAttribute("ZoneIndex")
		local zone = zi and Config.Zones[zi]
		local status = sign:FindFirstChild("Status")
		if zone and status then
			if state.Power >= zone.req then
				status.Text = "UNLOCKED"
				status.TextColor3 = RGB(120, 255, 160)
			else
				status.Text = "LOCKED - needs Level " .. zone.level
				status.TextColor3 = RGB(255, 110, 120)
			end
		end
	end
end

local function renderAll()
	if not state then
		return
	end
	stats = Config.stats(state)
	renderStats()
	renderBars()
	renderHint()
	renderZoneSigns()
	local p = currentKey and panels[currentKey]
	if p and p.refresh then
		p.refresh()
	end
end

----------------------------------------------------------------------
-- Training: click input, dummy hit feedback
----------------------------------------------------------------------
local dummies = {} -- [zoneIndex] = { body, torso, head, orig }

local function registerDummy(model)
	local zi = model:GetAttribute("ZoneIndex")
	if not zi then
		return
	end
	local body = model:WaitForChild("Body", 10)
	local torso = body and body:WaitForChild("Torso", 10)
	local head = body and body:WaitForChild("Head", 10)
	if not (body and torso and head) then
		return
	end
	dummies[zi] = { body = body, torso = torso, head = head, orig = body:GetPivot() }
end

for _, m in ipairs(CollectionService:GetTagged("Dummy")) do
	task.spawn(registerDummy, m)
end
CollectionService:GetInstanceAddedSignal("Dummy"):Connect(function(m)
	task.spawn(registerDummy, m)
end)

-- A "got punched" reaction: the dummy snaps back on a tilt, rebounds past
-- center with a squash/stretch, wobbles once, then settles. `power` (roughly
-- 0.4-2.2) scales how hard the hit reads, so bigger dummies/combos hit harder.
local function impactAnim(info, power)
	info.token = (info.token or 0) + 1
	local mine = info.token
	local keys = {
		{ t = 0.00, tilt = 0, scale = 1.00 },
		{ t = 0.05, tilt = 12 * power, scale = 1 - 0.09 * power },
		{ t = 0.14, tilt = 6 * power, scale = 1 + 0.06 * power },
		{ t = 0.24, tilt = -2.5 * power, scale = 1 - 0.02 * power },
		{ t = 0.34, tilt = 0, scale = 1.00 },
	}
	task.spawn(function()
		local start = os.clock()
		while info.token == mine do
			local elapsed = os.clock() - start
			local last = keys[#keys]
			if elapsed >= last.t then
				info.body:PivotTo(info.orig)
				pcall(function()
					info.body:ScaleTo(1)
				end)
				return
			end
			for i = 1, #keys - 1 do
				local a, b = keys[i], keys[i + 1]
				if elapsed >= a.t and elapsed <= b.t then
					local f = (elapsed - a.t) / (b.t - a.t)
					local tilt = a.tilt + (b.tilt - a.tilt) * f
					local scale = a.scale + (b.scale - a.scale) * f
					info.body:PivotTo(info.orig * CFrame.Angles(math.rad(-tilt), 0, 0))
					pcall(function()
						info.body:ScaleTo(scale)
					end)
					break
				end
			end
			task.wait()
		end
	end)
end

local function flash(info)
	if not info.highlight then
		info.highlight = create("Highlight", {
			FillColor = Color3.new(1, 1, 1),
			OutlineTransparency = 1,
			FillTransparency = 1,
			Adornee = info.body,
			Parent = info.body,
		})
	end
	info.highlight.FillTransparency = 0.45
	tween(info.highlight, 0.15, { FillTransparency = 1 })
end

local function popText(adornee, message, color, big, riseY)
	local w = big and 240 or 180
	local bb = create("BillboardGui", {
		Size = UDim2.fromOffset(w, w * 0.32),
		StudsOffset = Vector3.new((math.random() - 0.5) * 3, riseY or 3, 0),
		AlwaysOnTop = true,
		Adornee = adornee,
		Parent = playerGui,
	})
	local scaler = create("UIScale", { Scale = 0.35, Parent = bb })
	local lbl = text({
		Size = UDim2.fromScale(1, 1),
		Text = message,
		TextSize = big and 52 or 40,
		TextColor3 = color,
		Parent = bb,
	}, { stroke(big and 5 or 4) })

	-- pop in with a little overshoot, then relax to full size
	tween(scaler, 0.16, { Scale = big and 1.3 or 1.08 }, Enum.EasingStyle.Back)
	task.delay(0.16, function()
		if scaler.Parent then
			tween(scaler, 0.12, { Scale = 1 })
		end
	end)

	tween(bb, 0.8, { StudsOffset = bb.StudsOffset + Vector3.new(0, big and 7 or 5, 0) })
	task.delay(0.18, function()
		tween(lbl, 0.62, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local s = lbl:FindFirstChildOfClass("UIStroke")
		if s then
			tween(s, 0.62, { Transparency = 1 })
		end
	end)
	Debris:AddItem(bb, 1.1)
end

Remotes.TrainFeedback.OnClientEvent:Connect(function(gain, zi, comboCount, comboMult)
	local info = dummies[zi]
	local zone = Config.Zones[zi]
	if not info or not zone then
		return
	end

	-- comboCount is 0 for auto-train hits - those don't touch the combo.
	comboCount = comboCount or 0
	comboMult = comboMult or 1
	local isCombo = comboCount > 0
	local tierUp = false
	if isCombo then
		tierUp = comboMult > combo.mult
		combo.count = comboCount
		combo.mult = comboMult
		combo.resetAt = os.clock() + Config.ComboWindow
	end
	local milestone = isCombo and comboCount % COMBO_STEP == 0

	local power = math.clamp(zone.mult / 3, 0.4, 2.2)
	local punch = milestone and power * 1.5 or power

	impactAnim(info, punch)
	flash(info)

	local burst = info.torso:FindFirstChild("HitBurst")
	if burst then
		burst:Emit(milestone and 20 or 8)
	end

	popText(info.head, "+" .. Config.formatGain(gain), zone.color)
	if tierUp then
		popText(info.head, "COMBO x" .. Config.formatMult(comboMult) .. "!", C.orange, true, 6)
		local tierIndex = 0
		for i, tier in ipairs(Config.ComboTiers) do
			if comboCount >= tier.hits then
				tierIndex = i
			end
		end
		playComboDing(tierIndex)
	elseif milestone then
		popText(info.head, comboCount .. " HIT COMBO!", C.gold, true, 6)
	end

	playImpactSound(punch, isCombo and comboCount or 1)
	cameraPunch(milestone and 0.55 or 0.28)
end)

local holding = false
local lastFire = 0

local function tryTrain()
	if not state or currentKey then
		return
	end
	local zi = currentZone()
	if zi < 1 then
		return
	end
	if state.Power < Config.Zones[zi].req then
		return
	end
	local now = os.clock()
	if now - lastFire < Config.TrainClientInterval then
		return
	end
	lastFire = now
	Remotes.Train:FireServer()
	playPunch()
end

local function isPointer(input)
	local t = input.UserInputType
	return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not isPointer(input) then
		return
	end
	holding = true
	tryTrain()
end)

UserInputService.InputEnded:Connect(function(input)
	if isPointer(input) then
		holding = false
	end
end)

RunService.RenderStepped:Connect(function()
	if holding then
		tryTrain()
	end
end)

player:GetAttributeChangedSignal("CurrentZone"):Connect(renderHint)
player:GetAttributeChangedSignal("SpireFloor"):Connect(renderHint)

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
-- Big popup + ding when you level up, and a toast for every dummy it unlocks.
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
	for _, z in ipairs(Config.Zones) do
		if z.level > oldLevel and z.level <= newLevel then
			toast(z.name .. " unlocked!  x" .. Config.formatMult(z.mult) .. " Power", "info")
		end
	end
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

Remotes.Notify.OnClientEvent:Connect(toast)

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
-- Studio-only test buttons (the arena doesn't exist yet, so nothing drops loot)
----------------------------------------------------------------------
if RunService:IsStudio() then
	local devCol = create("Frame", {
		Name = "DevTools",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(150, 164),
		BackgroundTransparency = 1,
		Parent = root,
	}, {
		create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local DEV_LABELS = { Loot = "DEV: +Loot", Coins = "DEV: +Coins", Power = "DEV: +Power", MaxUpgrades = "DEV: Max Upgrades" }
	for i, kind in ipairs({ "Loot", "Coins", "Power", "MaxUpgrades" }) do
		local b = button({
			LayoutOrder = i,
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
end

-- Ask for the first snapshot (listeners above are already connected)
Remotes.RequestState:FireServer()
