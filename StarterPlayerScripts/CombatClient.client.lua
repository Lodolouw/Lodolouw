--[[
	CombatClient  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "CombatClient")

	Your controls and combat HUD inside the Spire's arenas (it switches itself
	on when you arrive and off when you leave):
	  * Click / tap          punch in the direction you're facing (hold to keep
	                         punching) - aim by turning towards the enemy. Each
	                         punch commits you: you stand still until the swing
	                         ends (you can roll out of the last part of it)
	  * Q  (gamepad B)       dodge roll - a quick dash; you're invincible for a
	                         moment at the start of it
	  * R  (gamepad Y)       drink a healing flask
	  * Tab / middle click   lock on to an enemy, like Elden Ring: the camera
	    (right stick click)  frames it and you always face it; press again
	                         to let go
	  * Phones get ROLL, FLASK and LOCK buttons next to the jump button.
	  * A green stamina bar sits above your health: punching and rolling use
	    it, and it refills when you stop.
	  * Damage numbers, a red flash when you're hit, and YOU DIED.

	The server (CombatService) has the final say on stamina, invincibility,
	damage and healing - this script just makes it feel instant.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local ContentProvider = game:GetService("ContentProvider")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local CombatRemotes = ReplicatedStorage:WaitForChild("CombatRemotes")
local CombatAction = CombatRemotes:WaitForChild("CombatAction")
local CombatEvent = CombatRemotes:WaitForChild("CombatEvent")

local CC = Config.Combat
local CB = CC.Combo or { Window = 0.85, Steps = { 1 }, Recovery = { 1 }, Track = 0.45, Buffer = 0.3 }
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RGB = Color3.fromRGB
local SERIF = Enum.Font.Garamond
local BOLD = Enum.Font.FredokaOne

-- Same two punches as training on the dummies
local PUNCH_ANIMATION_IDS = { "140534557983022", "128188028965818" }
local ROLL_ANIMATION_ID = "100272054307066"

----------------------------------------------------------------------
-- UI helpers
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
	return create("UIStroke", { Thickness = thickness, Color = RGB(0, 0, 0), Transparency = 0.15 })
end
local function tween(inst, seconds, props, style, dir)
	local t = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

----------------------------------------------------------------------
-- Root GUI
----------------------------------------------------------------------
local old = playerGui:FindFirstChild("CombatHud")
if old then
	old:Destroy()
end
local gui = create("ScreenGui", {
	Name = "CombatHud",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 10,
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

local combatUI = create("Frame", { Name = "CombatUI", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = root })

-- stamina bar, right above the health bar
local stamBack = create("Frame", {
	Name = "Stamina",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -132),
	Size = UDim2.fromOffset(320, 14),
	BackgroundColor3 = RGB(16, 30, 18),
	BackgroundTransparency = 0.1,
	Parent = combatUI,
}, { corner(6), stroke(2.5, RGB(0, 0, 0)) })
local stamFill = create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = RGB(90, 220, 100),
	BorderSizePixel = 0,
	Parent = stamBack,
}, {
	corner(6),
	create("UIGradient", { Color = ColorSequence.new(RGB(140, 245, 130), RGB(50, 170, 70)), Rotation = 90 }),
})

-- flask counter, left of the health bar
local flaskBox = create("Frame", {
	Name = "Flasks",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(0.5, -212, 1, -90),
	Size = UDim2.fromOffset(78, 42),
	BackgroundColor3 = RGB(20, 26, 22),
	BackgroundTransparency = 0.15,
	Parent = combatUI,
}, { corner(10), stroke(2.5, RGB(90, 200, 110), 0.3) })
local flaskText = create("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = BOLD,
	Text = "🧪 3",
	TextSize = 24,
	TextColor3 = RGB(230, 255, 230),
	Parent = flaskBox,
}, { textStroke(2) })

-- control hints (not on phones)
local hints = create("TextLabel", {
	Name = "Hints",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -150),
	Size = UDim2.fromOffset(720, 22),
	BackgroundTransparency = 1,
	Font = BOLD,
	Text = "Click: punch     Q: dodge roll     Space: jump     R: flask     Tab / middle click: lock on",
	TextSize = 18,
	TextColor3 = RGB(220, 225, 235),
	TextTransparency = 0.15,
	Parent = combatUI,
}, { textStroke(2) })

-- phone buttons, next to the jump button
local function roundButton(name, label, pos, size, color)
	return create("TextButton", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.2,
		Font = BOLD,
		Text = label,
		TextSize = 20,
		TextColor3 = RGB(255, 255, 255),
		AutoButtonColor = true,
		Visible = false,
		Parent = combatUI,
	}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }), stroke(3, RGB(0, 0, 0), 0.2), textStroke(2) })
end
local rollBtn = roundButton("RollButton", "ROLL", UDim2.new(1, -210, 1, -95), 88, RGB(60, 110, 200))
local flaskBtn = roundButton("FlaskButton", "🧪", UDim2.new(1, -120, 1, -200), 70, RGB(50, 150, 80))
local lockBtn = roundButton("LockButton", "LOCK", UDim2.new(1, -205, 1, -195), 62, RGB(90, 90, 110))

-- red flash round the edges when you're hit
local vignette = create("Frame", {
	Name = "HurtVignette",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = RGB(170, 0, 10),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 5,
	Parent = gui,
}, {
	create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.25, 0.85),
			NumberSequenceKeypoint.new(0.75, 0.85),
			NumberSequenceKeypoint.new(1, 0),
		}),
	}),
})

-- a slow dark pulse at the edges when you're nearly dead (its own frame, so the
-- hit flash above can fade on its own without the two fighting over one colour)
local lowVignette = create("Frame", {
	Name = "LowHealth",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = RGB(90, 0, 4),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 4,
	Parent = gui,
}, {
	create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.32, 0.95),
			NumberSequenceKeypoint.new(0.68, 0.95),
			NumberSequenceKeypoint.new(1, 0),
		}),
	}),
})

-- centre message ("Dodged!", "Out of stamina", studio "Incoming!")
local centerMsg = create("TextLabel", {
	Name = "CenterMsg",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.62),
	Size = UDim2.fromOffset(600, 50),
	BackgroundTransparency = 1,
	Font = BOLD,
	Text = "",
	TextSize = 34,
	TextColor3 = RGB(255, 255, 255),
	TextTransparency = 1,
	Visible = false,
	ZIndex = 20,
	Parent = root,
}, { textStroke(3) })
local msgToken = 0
-- The black outline is its own object (a UIStroke) and does NOT fade with the
-- text - left alone it stays behind as a dark ghost of the last message. So the
-- outline fades with the text, and the label is switched off once it's gone.
local msgStroke = centerMsg:FindFirstChildWhichIsA("UIStroke")
local MSG_STROKE = msgStroke and msgStroke.Transparency or 0.15
local msgFades = {}
local function stopMsgFades()
	for _, t in ipairs(msgFades) do
		t:Cancel()
	end
	msgFades = {}
end
local function hideMessage()
	msgToken = msgToken + 1
	stopMsgFades()
	centerMsg.TextTransparency = 1
	if msgStroke then
		msgStroke.Transparency = 1
	end
	centerMsg.Visible = false
end
local function flashMessage(text, color, seconds)
	msgToken = msgToken + 1
	local token = msgToken
	stopMsgFades() -- a fade still running from the last message must not dim this one
	centerMsg.Visible = true
	centerMsg.Text = text
	centerMsg.TextColor3 = color or RGB(255, 255, 255)
	centerMsg.TextTransparency = 0
	if msgStroke then
		msgStroke.Transparency = MSG_STROKE
	end
	centerMsg.Size = UDim2.fromOffset(560, 46)
	tween(centerMsg, 0.15, { Size = UDim2.fromOffset(600, 50) }, Enum.EasingStyle.Back)
	task.delay(seconds or 0.9, function()
		if token ~= msgToken then
			return
		end
		msgFades = { tween(centerMsg, 0.35, { TextTransparency = 1 }) }
		if msgStroke then
			msgFades[2] = tween(msgStroke, 0.35, { Transparency = 1 })
		end
		task.delay(0.4, function()
			if token == msgToken then
				centerMsg.Visible = false
			end
		end)
	end)
end

-- YOU DIED
local deathBand = create("Frame", {
	Name = "YouDied",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromScale(0, 0.45),
	Size = UDim2.new(1, 0, 0, 170),
	BackgroundColor3 = RGB(0, 0, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 80,
	Parent = gui,
}, {
	create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, 0.25),
			NumberSequenceKeypoint.new(0.75, 0.25),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}),
})
local deathText = create("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = SERIF,
	Text = "YOU DIED",
	TextSize = 110,
	TextColor3 = RGB(170, 20, 25),
	TextTransparency = 1,
	ZIndex = 81,
	Parent = deathBand,
})

-- Studio-only test button
local devBtn = nil
if RunService:IsStudio() then
	devBtn = create("TextButton", {
		Name = "DevIncoming",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -200),
		Size = UDim2.fromOffset(170, 30),
		BackgroundColor3 = RGB(120, 40, 50),
		Font = BOLD,
		Text = "DEV: Incoming hit",
		TextSize = 15,
		TextColor3 = RGB(255, 255, 255),
		Parent = combatUI,
	}, { corner(8) })
end

----------------------------------------------------------------------
-- State (predicted here, corrected by the server)
----------------------------------------------------------------------
local active = false
local stamina = CC.MaxStamina
local maxStamina = CC.MaxStamina
local flasks = CC.Flasks
local lastSpend = 0
local rollReadyAt = 0
local rolling = false
local drinkingUntil = 0
local lastPunch = 0
local holding = false
local lockTarget = nil -- the enemy you're locked on to (see Lock-on below)
local lockHeading = nil -- the way you're facing while locked on, frozen mid-swing
local punchLockUntil = 0 -- committed to a punch until then (can't move or punch again)
local punchStartedAt = 0
local savedWalkSpeed = nil

local function spendLocal(amount)
	stamina = math.max(0, stamina - amount)
	lastSpend = os.clock()
end

-- Redraws the stamina bar and flask count - but only when they have actually
-- moved. This runs every frame, and setting the same values again each time is
-- work the engine does for nothing.
local shownStamina, shownFlasks = nil, nil
local function renderStats()
	local fraction = math.clamp(stamina / maxStamina, 0, 1)
	if shownStamina == nil or math.abs(fraction - shownStamina) > 0.002 then
		shownStamina = fraction
		stamFill.Size = UDim2.fromScale(fraction, 1)
	end
	if shownFlasks ~= flasks then
		shownFlasks = flasks
		flaskText.Text = "🧪 " .. flasks
		flaskText.TextTransparency = flasks > 0 and 0 or 0.5
	end
end

local function noStamina()
	stamBack.BackgroundColor3 = RGB(120, 20, 20)
	tween(stamBack, 0.4, { BackgroundColor3 = RGB(16, 30, 18) })
end

----------------------------------------------------------------------
-- Character helpers
----------------------------------------------------------------------
local function charParts()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and hrp and hum.Health > 0) then
		return nil
	end
	return hum, hrp, char
end

local function manager(char)
	return char and char:FindFirstChildWhichIsA("ControllerManager", true)
end

-- Keeping your feet during a roll.
--
-- An R6 humanoid trips when it is shoved along the ground at speed: the legs
-- catch, Roblox decides you have lost your balance and drops you into the
-- FallingDown state, and you finish the roll lying on the floor. Rolling in
-- mid-air never trips, which is how we know it is the humanoid's balance and
-- not the terrain, the animation or the push. So for the length of a roll we
-- switch the tripping states off, hold the body upright, and switch them back
-- on when the roll ends.
local TRIP_STATES = {
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.Physics,
}

local function allowTripping(hum, allowed)
	for _, state in ipairs(TRIP_STATES) do
		pcall(function()
			hum:SetStateEnabled(state, allowed)
		end)
	end
end

local function isTripped(hum)
	local state = hum:GetState()
	return state == Enum.HumanoidStateType.FallingDown
		or state == Enum.HumanoidStateType.Ragdoll
		or state == Enum.HumanoidStateType.Physics
end

-- Runs every frame for the length of the roll: undoes any trip that slips
-- through and levels the body without changing where it is or where it points.
local function keepUpright(char, facing)
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local hum, hrp = charParts()
		if not hum or not hrp or hrp.Parent ~= char then
			connection:Disconnect()
			return
		end
		if isTripped(hum) then
			hum:ChangeState(Enum.HumanoidStateType.Running)
		end
		if hrp.CFrame.UpVector.Y < 0.999 then
			local look = hrp.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			flat = flat.Magnitude > 0.01 and flat.Unit or facing
			hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat)
		end
		hrp.AssemblyAngularVelocity = Vector3.zero
	end)
	return connection
end

-- The camera takes the hit.
--
-- A punch landing knocks the camera about, punches the view inward for a moment,
-- and on a finisher holds everything in a beat of slow motion. The camera
-- reacting is what sells the force - more than the victim's animation does.
local IM = CC.Impact or {}
local IMPACT_SHAKE = IM.Shake or 1.1
local IMPACT_FOV = IM.Fov or 4
local IMPACT_STOP = IM.Stop or 0.09
local IMPACT_SOUNDS = IM.Sounds or {}

local shake, shakeDir = 0, Vector3.new(1, 0, 0)
local fovOffset, restFov = 0, nil
local slowUntil = 0

-- Knocks the view off centre. Sharp in, quick out.
local function cameraKick(strength)
	shake = math.max(shake, strength or 0.3)
	local a = math.random() * math.pi * 2
	shakeDir = Vector3.new(math.cos(a), math.sin(a) * 0.7, 0)
end

-- Pulls the view in (negative) or lets it out (positive) and springs it back.
local function fovPunch(amount)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	if math.abs(fovOffset) < 0.05 then
		restFov = cam.FieldOfView -- remember where the player's view actually sits
	end
	fovOffset = math.clamp(fovOffset + amount, -7, 7) -- hits in quick succession can't stack into a fisheye
end

-- The beat of slow motion: every animation on you crawls, then picks back up.
local function slowMotion(seconds)
	local hum = charParts()
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	slowUntil = os.clock() + seconds
	local held = {}
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		held[track] = track.Speed
		track:AdjustSpeed(0.12)
	end
	task.delay(seconds, function()
		for track, was in pairs(held) do
			if track.IsPlaying then
				track:AdjustSpeed(was) -- back to whatever speed it was playing at
			end
		end
	end)
end

local function stepCamera(dt)
	local slow = os.clock() < slowUntil
	-- the shake: decays fast, and hangs while everything is slowed
	if shake > 0.001 then
		shake = shake * (1 - math.min(1, dt * (slow and 4 or 16)))
		local hum = charParts()
		if hum then
			local flip = (math.random() > 0.5) and 1 or -1
			hum.CameraOffset = shakeDir * shake * flip * 0.35
		end
	elseif shake ~= 0 then
		shake = 0
		local hum = charParts()
		if hum then
			hum.CameraOffset = Vector3.new()
		end
	end
	-- the view springing back to where it belongs
	if fovOffset ~= 0 and restFov then
		local cam = workspace.CurrentCamera
		fovOffset = fovOffset * (1 - math.min(1, dt * (slow and 3 or 9)))
		if math.abs(fovOffset) < 0.05 then
			fovOffset = 0
		end
		if cam then
			cam.FieldOfView = restFov + fovOffset
		end
	end
end

-- The boss's script shakes the camera through this, so the camera still has
-- exactly one owner (this script) and two scripts never fight over it.
local cameraKickEvent = Instance.new("BindableEvent")
cameraKickEvent.Name = "CombatCameraKick"
cameraKickEvent.Event:Connect(function(strength, fov)
	cameraKick(tonumber(strength) or 0.3)
	if tonumber(fov) then
		fovPunch(tonumber(fov))
	end
end)
cameraKickEvent.Parent = player:WaitForChild("PlayerScripts")

-- A sound on you, heard by you: the swing going through the air. The hit
-- itself is made on the server so everyone in the arena hears it.
local function playLocalSound(id, volume, pitch)
	local _, hrp = charParts()
	if not id or id == "" or not hrp then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = tostring(id):match("^rbx") and id or ("rbxassetid://" .. tostring(id))
	sound.Volume = volume or 0.5
	sound.PlaybackSpeed = pitch or 1
	sound.RollOffMaxDistance = 90
	local effects = game:GetService("SoundService"):FindFirstChild("Effects")
	if effects and effects:IsA("SoundGroup") then
		sound.SoundGroup = effects
	end
	sound.Parent = hrp
	sound:Play()
	task.delay(3, function()
		sound:Destroy()
	end)
end

-- Your own sounds (rolling, getting hurt, drinking, dying): a Sound from
-- SoundService named in Config.Combat.PlayerSounds, found ignoring capitals and
-- spaces. Only you hear them, played flat rather than from a spot in the world.
local PLAYER_SOUNDS = CC.PlayerSounds or {}
local function findNamedSound(name)
	if not name or name == "" then
		return nil
	end
	local want = string.lower((string.gsub(name, "%s+", "")))
	for _, child in ipairs(game:GetService("SoundService"):GetChildren()) do
		if child:IsA("Sound") and string.lower((string.gsub(child.Name, "%s+", ""))) == want then
			return child
		end
	end
	return nil
end
local function playPlayerSound(key, pitchJitter)
	local entry = PLAYER_SOUNDS[key]
	local template = entry and findNamedSound(entry.Name)
	if not template then
		return -- not added yet: silent, not an error
	end
	local SoundService = game:GetService("SoundService")
	local sound = template:Clone()
	sound.Looped = false
	sound.Volume = entry.Volume or 0.6
	local jitter = pitchJitter or 0
	sound.PlaybackSpeed = (template.PlaybackSpeed or 1) * (1 + (math.random() - 0.5) * 2 * jitter)
	local effects = SoundService:FindFirstChild("Effects")
	if effects and effects:IsA("SoundGroup") then
		sound.SoundGroup = effects
	end
	sound.Parent = SoundService
	sound:Play()
	task.delay(math.max(tonumber(sound.TimeLength) or 0, 1) + 1, function()
		sound:Destroy()
	end)
end

-- A short push in a direction (used for rolling and being knocked back).
-- `stopAfter` cancels the leftover speed when it ends - without it you keep
-- all the momentum the push built up and glide on across the floor.
local function push(hrp, velocity, seconds, stopAfter)
	local att = hrp:FindFirstChild("RootAttachment") or hrp:FindFirstChildWhichIsA("Attachment")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "CombatAttachment"
		att.Parent = hrp
	end
	local lv = Instance.new("LinearVelocity")
	lv.Name = "CombatPush"
	lv.Attachment0 = att
	lv.MaxForce = math.huge
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VectorVelocity = velocity
	lv.Parent = hrp
	task.delay(seconds, function()
		lv:Destroy()
		if stopAfter and hrp.Parent then
			-- keep any up/down speed (falling), drop the sideways speed
			local v = hrp.AssemblyLinearVelocity
			hrp.AssemblyLinearVelocity = Vector3.new(0, math.min(v.Y, 0), 0)
		end
	end)
end

-- Invincibility frames.
--
-- The server is the one that decides you are untouchable: it sets the window
-- when it accepts your roll and refuses any damage that lands inside it. All
-- this does is show you the window, so you can learn the timing - you glow pale
-- blue and the stamina bar goes the same colour until it runs out.
local STAMINA_GREEN = RGB(90, 220, 100)
local iframeHighlight, iframeUntil = nil, 0

local function showIframes(seconds)
	seconds = tonumber(seconds) or CC.RollInvincible
	local now = os.clock()
	if now + seconds <= iframeUntil then
		return -- already showing a longer window
	end
	iframeUntil = now + seconds
	local _, _, char = charParts()
	if not char then
		return
	end
	if iframeHighlight then
		iframeHighlight:Destroy()
	end
	local hl = Instance.new("Highlight")
	hl.Name = "RollIframes"
	hl.FillColor = RGB(130, 200, 255)
	hl.FillTransparency = 0.6
	hl.OutlineColor = RGB(215, 240, 255)
	hl.OutlineTransparency = 0.15
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Adornee = char
	hl.Parent = char
	iframeHighlight = hl
	-- fade out as the window closes, so the end of it is visible
	tween(hl, seconds, { FillTransparency = 1, OutlineTransparency = 1 }, Enum.EasingStyle.Linear)
	stamFill.BackgroundColor3 = RGB(130, 200, 255)
	tween(stamFill, seconds, { BackgroundColor3 = STAMINA_GREEN }, Enum.EasingStyle.Linear)
	task.delay(seconds, function()
		if iframeHighlight == hl then
			hl:Destroy()
			iframeHighlight = nil
			stamFill.BackgroundColor3 = STAMINA_GREEN
		end
	end)
end

-- The roll: a small hop, then a level dash through the air.
--
-- Rolling along the ground trips an R6 humanoid over however much we fight it,
-- but rolling in mid-air is perfect: the debug run showed 18.7 studs travelled,
-- dead upright the whole way, landing clean. So the roll now lifts you off the
-- floor first. You rise for a moment, dash level while airborne, then gravity
-- brings you down and you land normally.
local ROLL_HOP_SPEED = 30 -- studs per second upwards at the start
local ROLL_HOP_TIME = 0.1 -- how long you rise before the dash levels out (~3 studs)

-- How long a roll really takes, worked out rather than guessed: you rise, you
-- travel level, then you fall back the height you gained. Everything else about
-- the roll is measured against this one number - the animation's speed, when you
-- can act again, and how long you're untouchable for.
local function rollDuration()
	local height = ROLL_HOP_SPEED * ROLL_HOP_TIME
	local gravity = math.max(workspace.Gravity, 1)
	return CC.RollTime + math.sqrt(2 * height / gravity)
end

local function hopDash(hrp, dir)
	local att = hrp:FindFirstChild("RootAttachment") or hrp:FindFirstChildWhichIsA("Attachment")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "CombatAttachment"
		att.Parent = hrp
	end
	local flat = dir * CC.RollSpeed
	local lv = Instance.new("LinearVelocity")
	lv.Name = "CombatPush"
	lv.Attachment0 = att
	lv.MaxForce = math.huge
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VectorVelocity = flat + Vector3.new(0, ROLL_HOP_SPEED, 0) -- up and away
	lv.Parent = hrp

	-- once you are clear of the floor, hold the height and just travel
	task.delay(ROLL_HOP_TIME, function()
		if lv.Parent then
			lv.VectorVelocity = flat
		end
	end)

	-- let go at the end: sideways speed stops dead (no gliding), gravity lands you
	task.delay(CC.RollTime, function()
		lv:Destroy()
		if hrp.Parent then
			local v = hrp.AssemblyLinearVelocity
			hrp.AssemblyLinearVelocity = Vector3.new(0, math.min(v.Y, 0), 0)
		end
	end)
end

----------------------------------------------------------------------
-- Animations
----------------------------------------------------------------------
-- Animations arrive cold. The first two or three times one plays, Roblox is
-- still fetching and compiling it - which is exactly why the first swings look
-- wrong and everything after them looks right. So every track is loaded and run
-- through once the moment you spawn, quietly, before you ever throw a punch.
local tracks = {} -- [animation id] = AnimationTrack, for the animator we loaded it on
local tracksAnimator = nil
local PUNCH_SET = {}
for _, id in ipairs(PUNCH_ANIMATION_IDS) do
	PUNCH_SET[id] = true
end

local function animatorOf()
	local _, _, char = charParts()
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum and hum:FindFirstChildOfClass("Animator") or nil
end

local function trackFor(id, priority)
	local animator = animatorOf()
	if not animator then
		return nil
	end
	if tracksAnimator ~= animator then
		tracks, tracksAnimator = {}, animator -- you respawned: the old ones are dead
	end
	local track = tracks[id]
	if not track then
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. id
		local ok, loaded = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if not ok or not loaded then
			return nil
		end
		loaded.Priority = priority
		loaded.Looped = false
		tracks[id] = loaded
		track = loaded
	end
	return track
end

-- Loads every animation, waits for them to arrive, then plays each one with no
-- fade and no weight and stops it on the spot. Nothing shows on your character;
-- it just gets the fetching and compiling done at spawn rather than mid-fight.
local function warmAnimations()
	local wanted = { { ROLL_ANIMATION_ID, Enum.AnimationPriority.Action4 } }
	for _, id in ipairs(PUNCH_ANIMATION_IDS) do
		table.insert(wanted, { id, Enum.AnimationPriority.Action2 })
	end
	local ready, assets = {}, {}
	for _, entry in ipairs(wanted) do
		local track = trackFor(entry[1], entry[2])
		if track then
			ready[#ready + 1] = track
			if track.Animation then
				assets[#assets + 1] = track.Animation
			end
		end
	end
	if #assets > 0 then
		pcall(function()
			ContentProvider:PreloadAsync(assets) -- yields until they're actually here
		end)
	end
	for _, track in ipairs(ready) do
		pcall(function()
			track:Play(0, 0.0001, 1) -- no blend, no weight: invisible
		end)
	end
	task.wait(0.1)
	for _, track in ipairs(ready) do
		if track.IsPlaying then
			track:Stop(0)
		end
	end
end

-- at spawn, and again each time you respawn onto a fresh body
local function warmSoon()
	task.spawn(function()
		for _ = 1, 20 do -- the animator turns up a moment after the character does
			if animatorOf() then
				warmAnimations()
				return
			end
			task.wait(0.25)
		end
	end)
end
warmSoon()
player.CharacterAdded:Connect(warmSoon)

-- Being thrown by a hit. The same R6 balance problem the roll had applies:
-- a sideways shove along the ground trips the humanoid into lying on the
-- floor. So for the length of the shove (and a moment after, to land) it can't
-- trip, and it's held upright.
local function knockedBack(velocity, seconds)
	local hum, hrp, char = charParts()
	if not hrp or typeof(velocity) ~= "Vector3" or velocity.Magnitude <= 0 then
		return
	end
	allowTripping(hum, false)
	local look = hrp.CFrame.LookVector
	local steady = keepUpright(char, Vector3.new(look.X, 0, look.Z).Magnitude > 0.01 and Vector3.new(look.X, 0, look.Z).Unit or Vector3.new(0, 0, -1))
	push(hrp, velocity, seconds, true)
	task.delay(seconds + 0.35, function()
		steady:Disconnect()
		local h = charParts()
		if h then
			if isTripped(h) then
				h:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
			allowTripping(h, true)
		end
	end)
end

----------------------------------------------------------------------
-- Punch
----------------------------------------------------------------------
local punchIndex = 0
local function playPunch(swing, recovery)
	-- the swing's place in the string picks the animation, so a combo plays as a
	-- sequence rather than three interchangeable swings
	punchIndex = swing and ((swing - 1) % #PUNCH_ANIMATION_IDS + 1) or (punchIndex % #PUNCH_ANIMATION_IDS + 1)
	local id = PUNCH_ANIMATION_IDS[punchIndex]
	local track = trackFor(id, Enum.AnimationPriority.Action2)
	if not track then
		return
	end
	for otherId, other in pairs(tracks) do
		if PUNCH_SET[otherId] and other ~= track and other.IsPlaying then
			other:Stop(0.05)
		end
	end
	-- a swing that commits you for longer is played heavier, so the animation and
	-- the time you're standing there agree with each other
	local window = CC.PunchLock * (1 + ((recovery or 1) - 1) * 0.45)
	local speed = 1
	if track.Length > 0 then
		speed = math.clamp(track.Length / window, 0.75, 2.5)
	end
	track:Play(0.05, 1, speed)
end

-- The way you were facing when you started punching. Kept for the whole
-- run of punches (not re-read after each one, so any twist from the
-- animation can't build up), and forced back every frame until you walk.
local savedFacing = nil
local facingHoldUntil = 0
local FACING_HOLD = 0.6 -- seconds after your last punch

local function flatLook(hrp)
	local look = hrp.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return flat.Magnitude > 0.01 and flat.Unit or nil
end

-- Committing to a punch: you stand still until the swing finishes. Your
-- walk speed is set to 0 on your screen only and put back afterwards (the
-- main HUD copies WalkSpeed into your ControllerManager, so this stops it too).
local function releasePunchLock()
	punchLockUntil = 0
	local hum = charParts()
	if hum and savedWalkSpeed and hum.WalkSpeed == 0 then
		hum.WalkSpeed = savedWalkSpeed
	end
	savedWalkSpeed = nil
end

local function commitToPunch(now, recovery)
	local hum = charParts()
	if not hum then
		return
	end
	recovery = recovery or 1
	if not savedWalkSpeed and hum.WalkSpeed > 0 then
		savedWalkSpeed = hum.WalkSpeed
	end
	hum.WalkSpeed = 0
	punchStartedAt = now
	punchLockUntil = now + CC.PunchLock * recovery
	task.delay(CC.PunchLock * recovery, function()
		if punchLockUntil > 0 and os.clock() >= punchLockUntil - 0.02 then
			releasePunchLock()
		end
	end)
end

-- A step forward on every punch.
--
-- You lean into the swing rather than swinging on the spot, and because each
-- punch brings its own step, a combo walks you forward - each one a little
-- further than the last, up to a point. Locked on, the step goes at your target
-- and stops short of it so you never end up standing inside them.
local PUNCH_STEP = 15 -- studs per second (well under walking pace, so it reads as a lean)
-- the lean is over before the fist lands, so the step pushes you into the punch
-- rather than dragging you through it
local PUNCH_STEP_TIME = CC.PunchLock * CC.PunchContact * 0.66
local PUNCH_STOP_SHORT = 5 -- never close to within this of what you're hitting

local function punchStep(hrp, swing)
	local dir = flatLook(hrp)
	local room = math.huge
	if lockTarget then
		local ok, cf = pcall(function()
			return lockTarget:GetPivot()
		end)
		if ok and cf then
			local flat = Vector3.new(cf.X - hrp.Position.X, 0, cf.Z - hrp.Position.Z)
			if flat.Magnitude > 0.5 then
				dir = flat.Unit
				room = flat.Magnitude - PUNCH_STOP_SHORT
			end
		end
	end
	if not dir or room <= 0 then
		return -- nowhere to go, or already on top of them
	end
	local speed = PUNCH_STEP * (CB.Steps[swing] or CB.Steps[#CB.Steps] or 1)
	speed = math.min(speed, room / PUNCH_STEP_TIME) -- don't overshoot into the enemy
	push(hrp, dir * speed, PUNCH_STEP_TIME, true)
end

-- Where you are in the string (0 = not in one), and a press waiting for the
-- current swing to finish.
local comboSwing = 0
local bufferedPunchAt = nil

local function tryPunch()
	if not active then
		return
	end
	local now = os.clock()
	if rolling or now < drinkingUntil then
		return
	end
	local readyAt = math.max(punchLockUntil, lastPunch + CC.PunchInterval)
	if now < readyAt then
		-- Not yet - but a press near the end of a swing is remembered and thrown
		-- the instant the swing lets go, so a combo feels like it obeys you.
		if readyAt - now <= CB.Buffer then
			bufferedPunchAt = now
		end
		return
	end
	if stamina < CC.PunchCost then
		noStamina()
		return
	end
	local hum, hrp, char = charParts()
	if not hum then
		return
	end
	-- remember your facing BEFORE this punch (only if you weren't already punching)
	if not savedFacing or now > facingHoldUntil then
		savedFacing = flatLook(hrp)
	end
	facingHoldUntil = now + FACING_HOLD
	bufferedPunchAt = nil
	-- keep going through the string if you kept the rhythm, else start it again
	if now - lastPunch <= CB.Window and comboSwing >= 1 and comboSwing < #CB.Steps then
		comboSwing = comboSwing + 1
	else
		comboSwing = 1
	end
	lastPunch = now
	spendLocal(CC.PunchCost)
	renderStats()
	if lockTarget then
		-- locked on: line up on the target and punch it
		local ok, cf = pcall(function()
			return lockTarget:GetPivot()
		end)
		if ok and cf then
			local flat = Vector3.new(cf.X - hrp.Position.X, 0, cf.Z - hrp.Position.Z)
			if flat.Magnitude > 0.5 then
				lockHeading = flat.Unit -- the facing step holds this for the swing
				local cm = manager(char)
				if cm then
					cm.FacingDirection = lockHeading
				end
				hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lockHeading)
			end
		end
		CombatAction:FireServer("Punch", lockTarget, comboSwing)
	else
		CombatAction:FireServer("Punch", nil, comboSwing)
	end
	-- the air moving, straight away: waiting for the server would feel laggy
	playLocalSound(IMPACT_SOUNDS.Whoosh, 0.45 + 0.08 * comboSwing, 1.12 - 0.07 * comboSwing)
	local recovery = CB.Recovery[comboSwing] or 1
	playPunch(comboSwing, recovery)
	commitToPunch(now, recovery)
	punchStep(hrp, comboSwing)
end

-- The buffered press: thrown as soon as the last swing releases you.
local function stepBufferedPunch()
	if not bufferedPunchAt then
		return
	end
	local now = os.clock()
	if now - bufferedPunchAt > CB.Buffer then
		bufferedPunchAt = nil -- too old to still be what you meant
		return
	end
	if not rolling and now >= math.max(punchLockUntil, lastPunch + CC.PunchInterval) then
		bufferedPunchAt = nil
		tryPunch()
	end
end

-- Put your facing back to the saved direction. Runs after the movement
-- controls and again after physics each frame, so neither the controller nor
-- the punch animation can leave you turned. Walking cancels it and you turn
-- normally.
local function holdFacing()
	if not active or not savedFacing then
		return
	end
	if lockTarget then
		savedFacing = nil -- locked on: you always face the target instead (see below)
		return
	end
	if os.clock() > facingHoldUntil then
		savedFacing = nil
		return
	end
	local hum, hrp, char = charParts()
	if not hum then
		return
	end
	if hum.MoveDirection.Magnitude > 0.1 and os.clock() >= punchLockUntil then
		savedFacing = nil -- steering (and not mid-punch): stop holding
		return
	end
	local cm = manager(char)
	if cm then
		cm.FacingDirection = savedFacing
	end
	local now = flatLook(hrp)
	if now and now:Dot(savedFacing) < 0.9995 then
		local pos = hrp.Position
		hrp.CFrame = CFrame.lookAt(pos, pos + savedFacing)
	end
end
RunService:BindToRenderStep("HoldFacingWhilePunching", Enum.RenderPriority.Input.Value + 2, holdFacing)

-- Locked on: keep your body turned straight at the target every frame, so
-- punch animations can't twist you off it (not while rolling, so rolls still
-- go where you steer)
local function stepLockFacing()
	if not (active and lockTarget) or rolling then
		lockHeading = nil
		return
	end
	local _, hrp, char = charParts()
	if not hrp then
		return
	end
	-- Tracking stops the moment a swing commits: your heading is held where it
	-- was, so an enemy who steps aside after you swing really does dodge it.
	local committed = punchLockUntil > 0 and os.clock() > punchStartedAt + CC.PunchLock * CC.PunchContact
	if not committed then
		local ok, cf = pcall(function()
			return lockTarget:GetPivot()
		end)
		if not (ok and cf) then
			return
		end
		local flat = Vector3.new(cf.X - hrp.Position.X, 0, cf.Z - hrp.Position.Z)
		if flat.Magnitude >= 0.5 then
			lockHeading = flat.Unit
		end
	end
	local want = lockHeading
	if not want then
		return
	end
	-- Turning is the movement controller's job: it does it smoothly, and it is
	-- the thing the character actually obeys. Writing the model's own rotation on
	-- top of that every frame is what made it judder.
	local cm = manager(char)
	if cm then
		cm.FacingDirection = want
	end
	-- ...so the model is only straightened when a punch animation has genuinely
	-- twisted it off course, not for the fraction of a degree it drifts normally.
	local look = hrp.CFrame.LookVector
	local have = Vector3.new(look.X, 0, look.Z)
	if have.Magnitude > 0.01 and have.Unit:Dot(want) < 0.985 then -- about 10 degrees
		hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + want)
	end
end

----------------------------------------------------------------------
-- Jumping
----------------------------------------------------------------------
-- In an arena a jump costs stamina like everything else. Rather than letting
-- you jump and taking the stamina afterwards, the jump is switched off outright
-- while you can't afford it - so you never get a jump you didn't pay for, and
-- being out of stamina feels like being out of breath.
local jumpAllowed = true
local jumpCharacter = nil

local function setJumpAllowed(allowed)
	local hum = charParts()
	if not hum or jumpAllowed == allowed then
		return
	end
	jumpAllowed = allowed
	pcall(function()
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, allowed)
	end)
end

local function stepJump()
	if not active then
		if not jumpAllowed then
			setJumpAllowed(true) -- out of the arena: jump as much as you like
		end
		return
	end
	setJumpAllowed(stamina >= CC.JumpCost)
end

-- charge for the jump the moment it starts
local function watchJumps(char)
	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
	if not hum or jumpCharacter == char then
		return
	end
	jumpCharacter = char
	jumpAllowed = true
	hum.Jumping:Connect(function(isJumping)
		if not (isJumping and active) then
			return
		end
		if stamina < CC.JumpCost then
			noStamina()
			return
		end
		spendLocal(CC.JumpCost)
		renderStats()
		CombatAction:FireServer("Jump")
	end)
end
if player.Character then
	task.spawn(watchJumps, player.Character)
end
player.CharacterAdded:Connect(function(char)
	jumpAllowed = true
	task.spawn(watchJumps, char)
end)

-- The jump sound, on time.
--
-- Roblox's own jump sound waits for the humanoid to report "Jumping", which on
-- a ControllerManager character like yours comes a good fraction of a second
-- after you've already left the ground. So that one is muted, and the same sound
-- plays the instant a jump you can actually do is pressed. (A Sound named "Jump"
-- in SoundService is used instead, if you add one.)
local JUMP_SOUND_ID = "rbxasset://sounds/action_jump.mp3" -- Roblox's standard jump
local JUMP_VOLUME = 0.5
local lastJumpSound = 0

local function muteDefaultJump(sound)
	if sound:IsA("Sound") and sound.Name == "Jumping" then
		sound.Volume = 0
		sound:GetPropertyChangedSignal("Volume"):Connect(function()
			if sound.Volume ~= 0 then
				sound.Volume = 0
			end
		end)
	end
end
local function watchDefaultJump(char)
	for _, d in ipairs(char:GetDescendants()) do
		muteDefaultJump(d)
	end
	char.DescendantAdded:Connect(muteDefaultJump)
end
if player.Character then
	watchDefaultJump(player.Character)
end
player.CharacterAdded:Connect(watchDefaultJump)

local function onGround(hum, char)
	local cm = manager(char)
	local sensor = cm and cm.GroundSensor
	if sensor and sensor.SensedPart then
		return true
	end
	return hum.FloorMaterial ~= Enum.Material.Air
end

UserInputService.JumpRequest:Connect(function()
	local now = os.clock()
	if now - lastJumpSound < 0.3 then
		return -- one press can fire this several times
	end
	local hum, _, char = charParts()
	if not hum or rolling or not onGround(hum, char) then
		return
	end
	if not hum:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
		return -- no stamina for it in an arena: no jump, so no sound
	end
	lastJumpSound = now
	local SoundService = game:GetService("SoundService")
	local template = findNamedSound("Jump")
	local sound
	if template then
		sound = template:Clone()
		sound.Looped = false
	else
		sound = Instance.new("Sound")
		sound.SoundId = JUMP_SOUND_ID
		sound.Volume = JUMP_VOLUME
	end
	local effects = SoundService:FindFirstChild("Effects")
	if effects and effects:IsA("SoundGroup") then
		sound.SoundGroup = effects
	end
	sound.Parent = SoundService
	sound:Play()
	task.delay(2, function()
		sound:Destroy()
	end)
end)

----------------------------------------------------------------------
-- Dodge roll
----------------------------------------------------------------------
local function playRoll()
	local rollTrack = trackFor(ROLL_ANIMATION_ID, Enum.AnimationPriority.Action4)
	if not rollTrack then
		return
	end
	-- stop any punch mid-swing, then play the roll fitted to the dash
	for id, t in pairs(tracks) do
		if PUNCH_SET[id] and t.IsPlaying then
			t:Stop(0.05)
		end
	end
	local speed = 1
	if rollTrack.Length > 0 then
		speed = math.clamp(rollTrack.Length / rollDuration(), 0.6, 3) -- ends as you land
	end
	rollTrack:Play(0.05, 1, speed)
end

local function tryRoll()
	if not active or rolling then
		return
	end
	local now = os.clock()
	if now < rollReadyAt or now < drinkingUntil then
		return
	end
	if now < punchLockUntil and now - punchStartedAt < CC.PunchRollCancel then
		return -- too early in the punch to roll out of it
	end
	if stamina < CC.RollCost then
		noStamina()
		return
	end
	local hum, hrp, char = charParts()
	if not hum then
		return
	end
	if punchLockUntil > 0 then
		releasePunchLock() -- rolling out of the end of a punch
	end
	rolling = true
	comboSwing = 0 -- rolling out ends the string; your next punch starts a new one
	bufferedPunchAt = nil
	rollReadyAt = now + CC.RollCooldown
	spendLocal(CC.RollCost)
	renderStats()
	CombatAction:FireServer("Roll")

	local dir = hum.MoveDirection or Vector3.new()
	if dir.Magnitude < 0.1 then
		dir = hrp.CFrame.LookVector
	end
	dir = Vector3.new(dir.X, 0, dir.Z)
	dir = dir.Magnitude > 0.01 and dir.Unit or Vector3.new(0, 0, -1)
	local cm = manager(char)
	if cm then
		cm.FacingDirection = dir
	end

	-- Stop the humanoid walking and tripping while the push carries you: its own
	-- ground movement fighting the push is what knocks an R6 rig over.
	local walkBefore = hum.WalkSpeed
	allowTripping(hum, false)
	hum.WalkSpeed = 0
	if cm then
		cm.BaseMoveSpeed = 0
	end
	local steady = keepUpright(char, dir)

	-- The ground sensor is what keeps you standing (and what drags you back down
	-- if you leave the floor). Blinding it for the roll hands you to the air
	-- controller instead, so the hop actually gets you airborne.
	local sensor = cm and cm.GroundSensor
	local searchBefore = nil
	if sensor then
		pcall(function()
			searchBefore = sensor.SearchDistance
			sensor.SearchDistance = 0
		end)
	end
	hum:ChangeState(Enum.HumanoidStateType.Freefall)

	hopDash(hrp, dir)
	playRoll()
	playPlayerSound("Roll", 0.05)
	showIframes(CC.RollInvincible)

	-- a ghostly streak behind you, and a little camera kick
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 1.2, 0)
	a0.Parent = hrp
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -1.2, 0)
	a1.Parent = hrp
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.25
	trail.Color = ColorSequence.new(RGB(200, 225, 255))
	trail.Transparency = NumberSequence.new(0.4, 1)
	trail.LightEmission = 0.6
	trail.Parent = hrp
	fovPunch(6) -- the view opens out as you dash, then springs back
	task.delay(rollDuration(), function()
		rolling = false -- on your feet again: only now can you punch
	end)
	task.delay(CC.RollTime, function()
		if steady.Connected then
			steady:Disconnect()
		end
		if sensor and searchBefore then
			pcall(function()
				sensor.SearchDistance = searchBefore
			end)
		end
		local hum2, _, char2 = charParts()
		if hum2 and char2 == char then
			hum2.WalkSpeed = walkBefore
			local cm2 = manager(char2)
			if cm2 then
				cm2.BaseMoveSpeed = walkBefore
			end
			if isTripped(hum2) then
				hum2:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
			allowTripping(hum2, true)
		end
	end)
	task.delay(CC.RollTime + 0.3, function()
		trail:Destroy()
		a0:Destroy()
		a1:Destroy()
	end)
end

----------------------------------------------------------------------
-- Flask
----------------------------------------------------------------------
local function tryHeal()
	if not active or rolling or os.clock() < drinkingUntil then
		return
	end
	if flasks <= 0 then
		flashMessage("No flasks left", RGB(255, 120, 120))
		return
	end
	CombatAction:FireServer("Heal")
end

local function drinkEffect(seconds)
	local _, hrp = charParts()
	if not hrp then
		return
	end
	local glow = Instance.new("PointLight")
	glow.Color = RGB(120, 255, 140)
	glow.Range = 10
	glow.Brightness = 2
	glow.Parent = hrp
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Rate = 30
	sparkles.Color = ColorSequence.new(RGB(160, 255, 170))
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new(0.35, 0)
	sparkles.Lifetime = NumberRange.new(0.6, 1)
	sparkles.Speed = NumberRange.new(2, 4)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Parent = hrp
	task.delay(seconds + 0.3, function()
		glow:Destroy()
		sparkles:Destroy()
	end)
end

----------------------------------------------------------------------
-- Damage numbers
----------------------------------------------------------------------
-- Getting hurt, and being nearly dead.
--
-- Both are meant to be felt more than seen: a quick soft blur and a moment of
-- washed-out colour when something lands, and when you are down to your last
-- health a faint red breathing at the edges of the screen. Nothing that gets in
-- the way of reading the fight.
local HURT_BLUR = 5 -- how soft the screen goes on a big hit
local HURT_FADE = 3.2 -- how quickly a hit's effect clears (per second)
local LOW_HEALTH = 0.3 -- the fraction of health where the warning starts
local DESPERATE = 0.08 -- and where it is at its strongest

local blur = Instance.new("BlurEffect")
blur.Name = "CombatHurtBlur"
blur.Size = 0
blur.Enabled = false
blur.Parent = Lighting

local grade = Instance.new("ColorCorrectionEffect")
grade.Name = "CombatGrade"
grade.Saturation = 0
grade.Brightness = 0
grade.TintColor = RGB(255, 255, 255)
grade.Enabled = false
grade.Parent = Lighting

local hurtFlash = 0 -- 1 right after a hit, fading to 0
local lowAmount = 0 -- 0 = fine, 1 = about to die
local effectsOn = false

local function hurtEffect(amount)
	local hum = charParts()
	local share = 0.5
	if hum and hum.MaxHealth > 0 and typeof(amount) == "number" then
		share = math.clamp(amount / (hum.MaxHealth * 0.25), 0.15, 1)
	end
	hurtFlash = math.max(hurtFlash, share)
	-- red at the edges: stronger for a bigger hit, never a full screen wash
	vignette.BackgroundTransparency = 1 - (0.14 + 0.32 * share)
	tween(vignette, 0.55, { BackgroundTransparency = 1 })
end

-- Puts the screen back to normal (leaving an arena, dying, respawning).
local function clearEffects()
	hurtFlash, lowAmount, effectsOn = 0, 0, false
	blur.Size = 0
	blur.Enabled = false
	grade.Saturation = 0
	grade.Brightness = 0
	grade.TintColor = RGB(255, 255, 255)
	grade.Enabled = false
	lowVignette.BackgroundTransparency = 1
	vignette.BackgroundTransparency = 1
end

-- One place that owns the screen: the fading hit, and the heartbeat at the edges
-- when you are nearly dead. Nothing runs outside an arena, and when there is
-- nothing to show the effects are switched off entirely.
local function stepScreenEffects(dt)
	if hurtFlash > 0 then
		hurtFlash = math.max(0, hurtFlash - dt * HURT_FADE)
	end

	local hum = charParts()
	local want = 0
	if active and hum and hum.MaxHealth > 0 then
		local share = hum.Health / hum.MaxHealth
		want = math.clamp((LOW_HEALTH - share) / (LOW_HEALTH - DESPERATE), 0, 1)
	end
	lowAmount = lowAmount + (want - lowAmount) * math.min(1, dt * 5) -- eases in and out

	if lowAmount < 0.01 and hurtFlash <= 0 then
		if effectsOn then
			clearEffects()
		end
		return
	end
	effectsOn = true

	-- the soft knock to the eyes from a hit
	blur.Enabled = hurtFlash > 0.02
	blur.Size = HURT_BLUR * hurtFlash

	-- colour drains, from the hit and from being nearly dead
	local drain = math.max(lowAmount, hurtFlash)
	grade.Enabled = true
	grade.Saturation = -0.3 * drain
	grade.Brightness = -0.02 * lowAmount
	grade.TintColor = RGB(255, 255 - math.floor(18 * lowAmount), 255 - math.floor(18 * lowAmount))

	-- two beats and a rest, quickening the worse it gets
	if lowAmount < 0.01 then
		lowVignette.BackgroundTransparency = 1
	else
		local period = 1.25 - 0.35 * lowAmount
		local t = os.clock() % period
		local function thump(at, width)
			local d = (t - at) / width
			return math.exp(-d * d)
		end
		local beat = thump(0, 0.1) + 0.65 * thump(0.22, 0.1)
		lowVignette.BackgroundTransparency = 1 - lowAmount * (0.1 + 0.14 * beat)
	end
end

local function damageNumber(pos, amount, killed)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(pos + Vector3.new((math.random() - 0.5) * 3, 4 + math.random() * 1.5, (math.random() - 0.5) * 3))
	anchor.Parent = workspace
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(220, 60)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = anchor
	bb.Parent = anchor
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = BOLD
	local immune = (tonumber(amount) or 0) <= 0
	t.Text = immune and "IMMUNE" or Config.format(amount)
	t.TextSize = killed and 44 or (immune and 24 or 34)
	t.TextColor3 = killed and RGB(255, 210, 80) or (immune and RGB(170, 175, 185) or RGB(255, 255, 255))
	t.TextStrokeTransparency = 0.2
	t.Parent = bb
	tween(bb, 0.8, { StudsOffset = Vector3.new(0, 3, 0) })
	task.delay(0.45, function()
		tween(t, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
	task.delay(0.9, function()
		anchor:Destroy()
	end)
end

----------------------------------------------------------------------
-- YOU DIED
----------------------------------------------------------------------
local function youDied()
	playPlayerSound("Death")
	deathBand.Visible = true
	deathBand.BackgroundTransparency = 1
	deathText.TextTransparency = 1
	deathText.TextSize = 100
	tween(deathBand, 1.2, { BackgroundTransparency = 0 })
	tween(deathText, 2, { TextTransparency = 0, TextSize = 116 }, Enum.EasingStyle.Sine)
	task.delay(4.2, function()
		tween(deathBand, 1, { BackgroundTransparency = 1 })
		tween(deathText, 1, { TextTransparency = 1 })
		task.delay(1.05, function()
			deathBand.Visible = false
		end)
	end)
end

----------------------------------------------------------------------
-- Lock-on (like Elden Ring)
----------------------------------------------------------------------
-- Tab, middle mouse button or the right stick click (or LOCK on phones)
-- locks onto the enemy nearest the middle of your screen. While locked:
--   * the camera sits behind you, framing you and the enemy together
--   * your character always faces the enemy, so moving left/right circles it
--     and every punch goes straight at it
--   * a white dot marks the target
-- Press it again to let go. It also lets go if the enemy dies, gets too far
-- away, or you leave the arena.
local LOCK_RANGE = 80 -- how far away you can lock on from
local LOCK_BREAK = 110 -- the lock lets go past this distance

local lockDot = create("BillboardGui", {
	Name = "LockOnDot",
	Size = UDim2.fromOffset(34, 34),
	AlwaysOnTop = true,
	LightInfluence = 0,
	Enabled = false,
	Parent = gui,
}, {
	create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = RGB(255, 255, 255),
		BorderSizePixel = 0,
	}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }), stroke(2, RGB(0, 0, 0), 0.3) }),
	create("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(30, 30),
		BackgroundTransparency = 1,
	}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }), stroke(2, RGB(255, 255, 255), 0.35) }),
})

local function targetPoint(model)
	local ok, cf, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if ok and cf then
		return cf.Position, size
	end
	local ok2, pivot = pcall(function()
		return model:GetPivot()
	end)
	return ok2 and pivot.Position or nil, Vector3.new(4, 4, 4)
end

local function lockable(model)
	return model and model.Parent and model:IsA("Model") and (model:GetAttribute("Health") or 0) > 0
end

-- the enemy closest to the middle of the screen, within range
local function pickTarget()
	local _, hrp = charParts()
	local cam = workspace.CurrentCamera
	if not (hrp and cam) then
		return nil
	end
	local best, bestScore = nil, math.huge
	for _, m in ipairs(game:GetService("CollectionService"):GetTagged("CombatTarget")) do
		if lockable(m) then
			local pos = targetPoint(m)
			if pos then
				local dist = (pos - hrp.Position).Magnitude
				if dist <= LOCK_RANGE then
					local toT = (pos - cam.CFrame.Position).Unit
					local angle = math.acos(math.clamp(toT:Dot(cam.CFrame.LookVector), -1, 1))
					local score = angle * 60 + dist -- mostly "nearest the middle of the screen"
					if score < bestScore then
						best, bestScore = m, score
					end
				end
			end
		end
	end
	return best
end

local savedCameraType = nil
local function unlock()
	if not lockTarget then
		return
	end
	lockTarget = nil
	lockDot.Enabled = false
	lockDot.Adornee = nil
	local cam = workspace.CurrentCamera
	if cam and savedCameraType then
		cam.CameraType = savedCameraType
	end
	savedCameraType = nil
end

local function lockOn(model)
	local cam = workspace.CurrentCamera
	if not (model and cam) then
		return
	end
	lockTarget = model
	local body = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	lockDot.Adornee = body
	lockDot.Enabled = body ~= nil
	savedCameraType = savedCameraType or cam.CameraType
	cam.CameraType = Enum.CameraType.Scriptable
end

local function toggleLock()
	if not active then
		return
	end
	if lockTarget then
		unlock()
		return
	end
	local t = pickTarget()
	if t then
		lockOn(t) -- nothing in range: the press just does nothing, no message
	end
end

-- camera + facing while locked
RunService:BindToRenderStep("LockOnCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if not lockTarget then
		return
	end
	local hum, hrp, char = charParts()
	local cam = workspace.CurrentCamera
	if not (hum and hrp and cam) or not active or not lockable(lockTarget) then
		unlock()
		return
	end
	local tpos, tsize = targetPoint(lockTarget)
	if not tpos or (tpos - hrp.Position).Magnitude > LOCK_BREAK then
		unlock()
		return
	end
	local ppos = hrp.Position + Vector3.new(0, 1.5, 0)
	local flat = Vector3.new(tpos.X - ppos.X, 0, tpos.Z - ppos.Z)
	if flat.Magnitude < 0.5 then
		return
	end
	local dir = flat.Unit
	local right = Vector3.new(-dir.Z, 0, dir.X)
	-- pull the camera back further for bigger enemies
	local big = math.max(tsize.X, tsize.Y, tsize.Z)
	local back = 12 + big * 0.35
	local up = 4 + big * 0.12
	local camPos = ppos - dir * back + Vector3.new(0, up, 0) + right * 1.5
	local lookAt = ppos:Lerp(tpos, 0.55)
	local goal = CFrame.lookAt(camPos, lookAt)
	cam.CFrame = cam.CFrame:Lerp(goal, math.min(1, dt * 10))
	cam.Focus = CFrame.new(ppos)
	-- which way you face is not this loop's job: the facing step owns that (it
	-- runs once a frame, and two of us turning you at different rates is what
	-- made punching while locked on look like a spinning top)
	local _ = char
end)

----------------------------------------------------------------------
-- Switching on and off
----------------------------------------------------------------------
local function hudToasts()
	local hud = playerGui:FindFirstChild("BossGrowHud")
	local r = hud and hud:FindFirstChild("Root")
	return r and r:FindFirstChild("Toasts")
end
local toastHome = nil

local function setActive(on)
	active = on
	combatUI.Visible = on
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	rollBtn.Visible = on and touch
	flaskBtn.Visible = on and touch
	hints.Visible = on and not touch
	-- nudge the main HUD's pop-up messages up so they don't sit on the stamina bar
	local toasts = hudToasts()
	if toasts then
		toastHome = toastHome or toasts.Position
		toasts.Position = on and UDim2.new(0.5, 0, 1, -178) or toastHome
	end
	lockBtn.Visible = on and touch
	if on then
		stamina, flasks = CC.MaxStamina, CC.Flasks
		renderStats()
	else
		holding = false
		unlock()
		releasePunchLock()
		clearEffects()
		hideMessage()
		setJumpAllowed(true)
	end
end

player:GetAttributeChangedSignal("SpireFloor"):Connect(function()
	setActive(player:GetAttribute("SpireFloor") ~= nil)
end)
setActive(player:GetAttribute("SpireFloor") ~= nil)

-- A fresh body starts clean: nothing from the last life (a roll, a punch, a
-- held facing, a lock-on, the slow-motion beat) carries over onto it.
player.CharacterAdded:Connect(function()
	rolling = false
	drinkingUntil = 0
	punchLockUntil = 0
	savedWalkSpeed = nil
	savedFacing = nil
	facingHoldUntil = 0
	bufferedPunchAt = nil
	comboSwing = 0
	slowUntil = 0
	shake = 0
	unlock()
	clearEffects()
	hideMessage()
end)

----------------------------------------------------------------------
-- Input
----------------------------------------------------------------------
local function isPointer(input)
	local t = input.UserInputType
	return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
end

UserInputService.InputBegan:Connect(function(input, processed)
	if not active then
		return
	end
	if input.KeyCode == Enum.KeyCode.Tab or input.KeyCode == Enum.KeyCode.ButtonR3 or input.UserInputType == Enum.UserInputType.MouseButton3 then
		if not processed or input.KeyCode == Enum.KeyCode.ButtonR3 then
			toggleLock()
		end
		return
	end
	if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonB then
		if not processed or input.KeyCode == Enum.KeyCode.ButtonB then
			tryRoll()
		end
		return
	end
	if input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.ButtonY then
		if not processed or input.KeyCode == Enum.KeyCode.ButtonY then
			tryHeal()
		end
		return
	end
	if input.KeyCode == Enum.KeyCode.ButtonR2 then
		holding = true
		tryPunch()
		return
	end
	if processed or not isPointer(input) then
		return
	end
	holding = true
	tryPunch()
end)
UserInputService.InputEnded:Connect(function(input)
	if isPointer(input) or input.KeyCode == Enum.KeyCode.ButtonR2 then
		holding = false
	end
end)
rollBtn.Activated:Connect(tryRoll)
lockBtn.Activated:Connect(toggleLock)
flaskBtn.Activated:Connect(tryHeal)
if devBtn then
	devBtn.Activated:Connect(function()
		CombatAction:FireServer("DevIncoming")
	end)
end

-- Everything that happens every frame, in one place and in a fixed order.
--
-- Roblox makes no promise about the order of separate connections, which is how
-- a camera shake and a facing correction end up undoing each other's work on the
-- same frame. Running them in a set order - what you asked for, then where you
-- are pointing, then the camera, then the screen - means they agree.
RunService.Heartbeat:Connect(function(dt)
	stepBufferedPunch() -- the press you made while you were still swinging
	holdFacing() -- keep you pointing where you were when you threw the punch
	stepLockFacing() -- ...or straight at your target, if you're locked on
	stepJump() -- whether you can afford to jump right now
	stepCamera(dt) -- shake and the view springing back
	stepScreenEffects(dt) -- the hit flash and the low-health heartbeat
end)

RunService.RenderStepped:Connect(function(dt)
	if not active then
		return
	end
	if holding then
		tryPunch()
	end
	-- predict stamina refilling between server updates
	if os.clock() - lastSpend >= CC.StaminaRegenDelay and os.clock() >= drinkingUntil and stamina < maxStamina then
		stamina = math.min(maxStamina, stamina + CC.StaminaRegen * dt)
	end
	renderStats()
end)

----------------------------------------------------------------------
-- Messages from the server
----------------------------------------------------------------------
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

-- A landed punch: one of your punch sounds from SoundService, never the same
-- one twice running, pitched a little lower the heavier the swing.
local SoundService = game:GetService("SoundService")
local lastHitSound = 0
local function playHitSound(weight)
	local names = IM.HitSounds
	if not names or #names == 0 then
		return
	end
	local pick = math.random(1, #names)
	if #names > 1 and pick == lastHitSound then
		pick = pick % #names + 1
	end
	lastHitSound = pick
	local template = SoundService:FindFirstChild(names[pick])
	if not (template and template:IsA("Sound")) then
		return
	end
	local sound = template:Clone()
	-- the finisher a touch louder than the jabs before it
	sound.Volume = ((Config.Audio and Config.Audio.Hits) or 0.7) * (0.88 + 0.06 * weight)
	sound.SoundGroup = soundGroup("Effects")
	sound.PlaybackSpeed = template.PlaybackSpeed * (1.08 - 0.07 * weight + (math.random() - 0.5) * 0.06)
	sound.Parent = SoundService
	sound:Play()
	task.delay(math.max(sound.TimeLength, 1) + 0.5, function()
		sound:Destroy()
	end)
end

CombatEvent.OnClientEvent:Connect(function(kind, a, b, c, d)
	if kind == "State" then
		-- the server is in charge: take its numbers (a = stamina, b = max, c = flasks)
		if math.abs(a - stamina) > 6 or os.clock() - lastSpend > 0.5 then
			stamina = a
		end
		maxStamina = b
		flasks = c
		renderStats()
	elseif kind == "Hit" then
		damageNumber(a, b, c)
		-- d is which swing of the string landed: the finisher hits hardest
		local weight = math.clamp(tonumber(d) or 1, 1, 3)
		if (tonumber(b) or 0) > 0 then
			playHitSound(weight) -- (nothing for a hit it shrugged off while untouchable)
		end
		cameraKick(IMPACT_SHAKE * (0.3 + 0.22 * weight) * (c and 1.6 or 1))
		fovPunch(-IMPACT_FOV * (0.55 + 0.22 * weight))
		if c or weight >= 3 then
			slowMotion(IMPACT_STOP) -- a beat of slow motion on the big ones
		end
	elseif kind == "Hurt" then
		if d then
			hurtEffect((tonumber(a) or 0) * 0.6) -- a small repeated burn: just a faint flash
		else
			hurtEffect(a)
			playPlayerSound("Hurt", 0.06) -- (not for puddle burns: those tick too often)
			cameraKick(0.75)
			knockedBack(c, 0.15)
		end
	elseif kind == "Shove" then
		-- thrown without being hurt (a boss's shell bursting)
		cameraKick(0.9)
		fovPunch(4)
		knockedBack(a, 0.22)
	elseif kind == "Dodged" then
		flashMessage("Dodged!", RGB(150, 200, 255), 0.6)
		cameraKick(0.2)
	elseif kind == "Denied" then
		if a == "Roll" then
			noStamina()
		elseif a == "Heal" then
			flashMessage("Can't drink right now", RGB(255, 150, 150))
		end
	elseif kind == "Drinking" then
		drinkingUntil = os.clock() + a
		drinkEffect(a)
		playPlayerSound("Drink")
	elseif kind == "Healed" then
		flashMessage("+ Healed", RGB(140, 255, 150), 0.7)
	elseif kind == "Iframes" then
		showIframes(a) -- the server granted the window: show it for real
	elseif kind == "Incoming" then
		flashMessage("! Incoming hit - roll !", RGB(255, 90, 90), a)
	elseif kind == "Died" then
		unlock()
		releasePunchLock()
		clearEffects()
		hideMessage() -- no "Dodged!" hanging over the YOU DIED screen
		youDied()
	elseif kind == "Stop" then
		setActive(false)
	end
end)