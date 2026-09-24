--[[
	ArenaAmbience  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "ArenaAmbience")

	How a Spire arena looks and sounds on your own screen while you're in it.
	Each floor in Config.Spire.Floors can have an `ambience` table (the Sunken
	Dunes does): walk in and the light shifts to it, and when you leave, the
	lobby's own look comes back exactly as it was.

	For the Sunken Dunes that means:
	  * a low golden sun and a warm, dusty haze
	  * sand blowing past you all the time - fine grains streaking by, and big
	    soft clouds of dust drifting through - thicker when the arena's "Storm"
	    attribute goes up (a breeze while it's quiet; the boss can whip it up)
	  * a looping wind, if a Sound named "Sandstorm" is in SoundService

	Only you see or hear any of this; nothing here touches the server.
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local player = Players.LocalPlayer

local current = nil -- the floor whose ambience is on (nil in the lobby)
local FADE = 1.6 -- seconds to shift the light in or out
local DEFAULT_STORM = 0.35

local function ambienceFor(floorId)
	for _, f in ipairs(Config.Spire and Config.Spire.Floors or {}) do
		if f.id == floorId then
			return f.ambience
		end
	end
	return nil
end

local function tween(inst, props, seconds, onDone)
	local t = TweenService:Create(inst, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), props)
	if onDone then
		t.Completed:Connect(onDone)
	end
	t:Play()
	return t
end

----------------------------------------------------------------------
-- The light
----------------------------------------------------------------------
local ATMO_KEYS = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" }
local saved = nil -- the lobby's look, taken the moment before we first change it

local grade = Lighting:FindFirstChild("ArenaGrade")
if grade then
	grade:Destroy()
end
grade = Instance.new("ColorCorrectionEffect")
grade.Name = "ArenaGrade"
grade.Enabled = false
grade.Parent = Lighting

local function atmosphere()
	return Lighting:FindFirstChildOfClass("Atmosphere")
end

local function remember()
	if saved then
		return
	end
	saved = { ClockTime = Lighting.ClockTime }
	local atmo = atmosphere()
	if atmo then
		saved.atmo = {}
		for _, k in ipairs(ATMO_KEYS) do
			saved.atmo[k] = atmo[k]
		end
	end
end

local function lightIn(amb)
	remember()
	if amb.ClockTime then
		tween(Lighting, { ClockTime = amb.ClockTime }, FADE)
	end
	local atmo = atmosphere()
	if atmo and amb.Atmosphere then
		local goal = {}
		for _, k in ipairs(ATMO_KEYS) do
			if amb.Atmosphere[k] ~= nil then
				goal[k] = amb.Atmosphere[k]
			end
		end
		tween(atmo, goal, FADE)
	end
	grade.Enabled = true
	tween(grade, {
		TintColor = amb.Tint or Color3.new(1, 1, 1),
		Saturation = amb.Saturation or 0,
		Contrast = amb.Contrast or 0,
	}, FADE)
end

local function lightOut()
	if saved then
		tween(Lighting, { ClockTime = saved.ClockTime }, FADE)
		local atmo = atmosphere()
		if atmo and saved.atmo then
			tween(atmo, saved.atmo, FADE)
		end
	end
	tween(grade, { TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0 }, FADE, function(state)
		if state == Enum.PlaybackState.Completed and not current then
			grade.Enabled = false
			saved = nil -- next time, take the lobby's look fresh
		end
	end)
end

----------------------------------------------------------------------
-- The blowing sand, around your camera
----------------------------------------------------------------------
local fxFolder = Workspace:FindFirstChild("ArenaAmbienceFX")
if fxFolder then
	fxFolder:Destroy()
end
fxFolder = Instance.new("Folder")
fxFolder.Name = "ArenaAmbienceFX"
fxFolder.Parent = Workspace

local stormBox = Instance.new("Part")
stormBox.Name = "SandstormBox"
stormBox.Anchored = true
stormBox.CanCollide = false
stormBox.CanQuery = false
stormBox.CanTouch = false
stormBox.CastShadow = false
stormBox.Transparency = 1
stormBox.Size = Vector3.new(120, 36, 120)
stormBox.Parent = fxFolder

-- fine grains whipping past
local grains = Instance.new("ParticleEmitter")
grains.Name = "Grains"
grains.Texture = "rbxasset://textures/particles/smoke_main.dds"
grains.LightInfluence = 1
grains.LightEmission = 0.1
grains.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.16), NumberSequenceKeypoint.new(1, 0.26) })
grains.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.15, 0.35),
	NumberSequenceKeypoint.new(0.8, 0.45),
	NumberSequenceKeypoint.new(1, 1),
})
grains.Speed = NumberRange.new(40, 56)
grains.Lifetime = NumberRange.new(1.8, 2.4)
grains.SpreadAngle = Vector2.new(5, 4)
grains.EmissionDirection = Enum.NormalId.Front
grains.Shape = Enum.ParticleEmitterShape.Box
grains.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
grains.Rate = 0
grains.Parent = stormBox

-- big soft clouds of dust rolling through
local dust = Instance.new("ParticleEmitter")
dust.Name = "Dust"
dust.LightInfluence = 1
dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 16), NumberSequenceKeypoint.new(1, 34) })
dust.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.3, 0.86),
	NumberSequenceKeypoint.new(0.7, 0.88),
	NumberSequenceKeypoint.new(1, 1),
})
dust.Speed = NumberRange.new(14, 22)
dust.Lifetime = NumberRange.new(6, 8)
dust.RotSpeed = NumberRange.new(-12, 12)
dust.Rotation = NumberRange.new(0, 360)
dust.SpreadAngle = Vector2.new(12, 6)
dust.EmissionDirection = Enum.NormalId.Front
dust.Shape = Enum.ParticleEmitterShape.Box
dust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
dust.Rate = 0
dust.Parent = stormBox

local GRAINS_RATE = 260 -- at a full storm
local DUST_RATE = 7

----------------------------------------------------------------------
-- The wind
----------------------------------------------------------------------
local function findSound(name)
	if not name then
		return nil
	end
	local want = string.lower((string.gsub(name, "%s+", "")))
	for _, s in ipairs(SoundService:GetChildren()) do
		if s:IsA("Sound") and string.lower((string.gsub(s.Name, "%s+", ""))) == want then
			return s
		end
	end
	return nil
end

local wind, windFor = nil, nil
local function windSound(amb)
	if windFor == amb then
		return wind
	end
	if wind then
		wind:Destroy()
		wind = nil
	end
	windFor = amb
	local template = amb and findSound(amb.Sound)
	if template then
		wind = template:Clone()
		wind.Name = "ArenaWind"
		wind.Looped = true
		wind.Volume = 0
		local effects = SoundService:FindFirstChild("Effects")
		if effects and effects:IsA("SoundGroup") then
			wind.SoundGroup = effects
		end
		wind.Parent = SoundService
		wind:Play()
	end
	return wind
end

----------------------------------------------------------------------
-- In and out
----------------------------------------------------------------------
local currentAmb = nil -- its ambience table
local level = 0 -- 0..1: how far faded in the sand and wind are
local sandColor = nil

-- the arena model for a floor (it says which floor it is)
local arenaCache = {}
local function arenaFor(floorId)
	local cached = arenaCache[floorId]
	if cached and cached.Parent then
		return cached
	end
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("Floor") == floorId then
			arenaCache[floorId] = child
			return child
		end
	end
	return nil
end

local function onFloor()
	local floorId = player:GetAttribute("SpireFloor")
	local amb = floorId and ambienceFor(floorId) or nil
	if amb == currentAmb then
		return
	end
	current = amb and floorId or nil
	currentAmb = amb
	if amb then
		lightIn(amb)
	else
		lightOut()
	end
end
player:GetAttributeChangedSignal("SpireFloor"):Connect(onFloor)
onFloor()

RunService.RenderStepped:Connect(function(dt)
	local want = currentAmb and 1 or 0
	if level == want and want == 0 then
		return -- in the lobby, nothing to do
	end
	level = level + (want - level) * math.min(1, dt / (FADE * 0.35))
	if math.abs(level - want) < 0.01 then
		level = want
	end
	local amb = currentAmb or windFor -- while fading out, keep the last arena's look
	local storm = DEFAULT_STORM
	local arena = current and arenaFor(current)
	if arena then
		storm = tonumber(arena:GetAttribute("Storm")) or DEFAULT_STORM
	end
	storm = math.clamp(storm, 0, 1)

	-- the sand: a box of it upwind of wherever you're looking, blowing through
	local cam = Workspace.CurrentCamera
	if cam and amb then
		local w = amb.Wind or Vector3.new(1, 0, 0)
		w = Vector3.new(w.X, 0, w.Z)
		w = w.Magnitude > 0.01 and w.Unit or Vector3.new(1, 0, 0)
		local focus = (cam.Focus or cam.CFrame).Position
		local at = focus - w * 40 + Vector3.new(0, 6, 0)
		stormBox.CFrame = CFrame.lookAt(at, at + w)
		local c = amb.Sand or Color3.fromRGB(226, 190, 130)
		if sandColor ~= c then
			sandColor = c
			grains.Color = ColorSequence.new(c)
			dust.Color = ColorSequence.new(c)
		end
	end
	grains.Rate = GRAINS_RATE * level * (0.25 + 0.75 * storm)
	dust.Rate = DUST_RATE * level * (0.3 + 0.7 * storm)

	-- the wind
	local s = windSound(amb)
	if s then
		s.Volume = (amb.Volume or 0.3) * level * (0.55 + 0.45 * storm)
	end
	if level == 0 and want == 0 and wind then
		wind:Destroy()
		wind, windFor = nil, nil
	end
end)
