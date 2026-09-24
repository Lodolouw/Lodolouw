--[[
	ArenaAmbience  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "ArenaAmbience")

	How a Spire arena looks and sounds on your own screen while you're in it.
	Each floor in Config.Spire.Floors can have an `ambience` table (the Sunken
	Dunes does): walk in and the light shifts to it, and when you leave, the
	lobby's own look comes back exactly as it was.

	For the Sunken Dunes that means:
	  * a low golden sun and a warm, dusty haze
	  * sand blowing past you all the time - fine grains streaking by, and big
	    soft clouds of dust drifting through (just a breeze while the worm sleeps)
	  * THE SANDSTORM (ambience.Storm in Config): when the fight starts, a wall
	    of sand rolls in across the arena and swallows it. While the storm
	    rages the air is thick with dust - everything past a stone's throw
	    fades into it, the light goes brown, and dust hangs right in front of
	    your eyes. It follows the arena's "Storm" attribute (BossClient raises
	    it when the worm wakes, higher again once its armour cracks) and dies
	    down again when the fight is over.
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
local CALM_STORM = 0.35 -- the arena's "Storm" while nothing's happening: a breeze
local FULL_STORM = 1 -- ... and at the storm's height

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

local function mix(a, b, t)
	if typeof(a) == "Color3" then
		return a:Lerp(b, t)
	end
	return a + (b - a) * t
end

----------------------------------------------------------------------
-- The light
----------------------------------------------------------------------
-- The time of day turns over FADE seconds as you arrive and leave. The air
-- (the Atmosphere) and the colour grade are set every frame instead (see the
-- bottom), blended between the lobby's look, the arena's calm look and the
-- storm - so the storm can roll in and die away smoothly.
local ATMO_KEYS = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" }
local savedClock = nil -- the lobby's time of day, taken the moment before we first change it
local lobbyAtmo = nil -- the lobby's air, the same way
local madeAtmo = nil -- an Atmosphere we added because the lobby has none (removed again after)

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
	if savedClock == nil then
		savedClock = Lighting.ClockTime
	end
	if lobbyAtmo then
		return
	end
	local atmo = atmosphere()
	if not atmo then
		-- the lobby has no Atmosphere of its own: add one that starts out
		-- invisible (the storm needs one to thicken the air)
		atmo = Instance.new("Atmosphere")
		atmo.Name = "ArenaAtmosphere"
		atmo.Density = 0
		atmo.Offset = 0
		atmo.Glare = 0
		atmo.Haze = 0
		atmo.Parent = Lighting
		madeAtmo = atmo
	end
	lobbyAtmo = {}
	for _, k in ipairs(ATMO_KEYS) do
		lobbyAtmo[k] = atmo[k]
	end
end

local function lightIn(amb)
	remember()
	if amb.ClockTime then
		tween(Lighting, { ClockTime = amb.ClockTime }, FADE)
	end
	grade.Enabled = true
end

local function lightOut()
	if savedClock ~= nil then
		tween(Lighting, { ClockTime = savedClock }, FADE)
	end
end

-- the arena's look has faded all the way out: the lobby's own, exactly
local function lightGone()
	grade.Enabled = false
	if madeAtmo then
		madeAtmo:Destroy()
		madeAtmo = nil
	end
	savedClock, lobbyAtmo = nil, nil
end

-- The air and the grade for this frame. `level` = how far into the arena's
-- look you are (0 = the lobby's, 1 = the arena's); `k` = how hard the storm
-- is blowing (0 = calm, 1 = its height).
local lastLevel, lastK = -1, -1
local function stepLight(amb, level, k)
	if math.abs(level - lastLevel) < 0.002 and math.abs(k - lastK) < 0.002 then
		return -- (nothing's changing: leave it be)
	end
	lastLevel, lastK = level, k
	local storm = amb and amb.Storm or {}
	local atmo = atmosphere()
	if atmo and lobbyAtmo then
		local calm = amb and amb.Atmosphere or {}
		local wild = storm.Atmosphere or {}
		for _, key in ipairs(ATMO_KEYS) do
			local lobby = lobbyAtmo[key]
			local here = calm[key]
			if here == nil then
				here = lobby
			end
			local there = wild[key]
			if there == nil then
				there = here
			end
			atmo[key] = mix(lobby, mix(here, there, k), level)
		end
	end
	local white = Color3.new(1, 1, 1)
	local tint = (amb and amb.Tint) or white
	grade.TintColor = white:Lerp(tint:Lerp(storm.Tint or tint, k), level)
	grade.Saturation = ((amb and amb.Saturation) or 0) * level
	grade.Contrast = ((amb and amb.Contrast) or 0) * level
	grade.Brightness = (storm.Brightness or 0) * k * level
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

local function invisiblePart(name, size)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.Parent = fxFolder
	return p
end

local function kp(t, v)
	return NumberSequenceKeypoint.new(t, v)
end

local stormBox = invisiblePart("SandstormBox", Vector3.new(120, 36, 120))

-- fine grains whipping past
local grains = Instance.new("ParticleEmitter")
grains.Name = "Grains"
grains.Texture = "rbxasset://textures/particles/smoke_main.dds"
grains.LightInfluence = 1
grains.LightEmission = 0.1
grains.Size = NumberSequence.new({ kp(0, 0.16), kp(1, 0.26) })
grains.Transparency = NumberSequence.new({ kp(0, 1), kp(0.15, 0.35), kp(0.8, 0.45), kp(1, 1) })
grains.Speed = NumberRange.new(40, 56)
grains.Lifetime = NumberRange.new(1.8, 2.4)
grains.SpreadAngle = Vector2.new(5, 4)
grains.EmissionDirection = Enum.NormalId.Front
grains.Shape = Enum.ParticleEmitterShape.Box
grains.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
grains.Rate = 0
pcall(function()
	-- stretched along the way they fly: streaks, not dots
	grains.Orientation = Enum.ParticleOrientation.VelocityParallel
	grains.Squash = NumberSequence.new(1.6)
end)
grains.Parent = stormBox

-- big soft clouds of dust rolling through
local dust = Instance.new("ParticleEmitter")
dust.Name = "Dust"
dust.LightInfluence = 1
dust.Size = NumberSequence.new({ kp(0, 16), kp(1, 34) })
dust.Transparency = NumberSequence.new({ kp(0, 1), kp(0.3, 0.86), kp(0.7, 0.88), kp(1, 1) })
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

-- the storm itself: thick sheets of sand tearing past (only in a storm)
local sheets = Instance.new("ParticleEmitter")
sheets.Name = "StormSheets"
sheets.LightInfluence = 1
sheets.Size = NumberSequence.new({ kp(0, 12), kp(1, 26) })
sheets.Transparency = NumberSequence.new({ kp(0, 1), kp(0.2, 0.64), kp(0.75, 0.72), kp(1, 1) })
sheets.Speed = NumberRange.new(34, 48)
sheets.Lifetime = NumberRange.new(2.4, 3.2)
sheets.RotSpeed = NumberRange.new(-30, 30)
sheets.Rotation = NumberRange.new(0, 360)
sheets.SpreadAngle = Vector2.new(10, 6)
sheets.EmissionDirection = Enum.NormalId.Front
sheets.Shape = Enum.ParticleEmitterShape.Box
sheets.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
sheets.Rate = 0
sheets.Parent = stormBox

-- how much of each, a second: in a breeze, and at the storm's height
local GRAINS_CALM, GRAINS_STORM = 110, 520
local DUST_CALM, DUST_STORM = 3, 9
local SHEETS_STORM = 26

----------------------------------------------------------------------
-- The dust in front of your eyes (only in a storm)
----------------------------------------------------------------------
-- A haze of sand-coloured dust over your whole view, thicker round the
-- edges, breathing with the gusts. It sits under every other screen (the
-- boss bar, your health and the menus stay sharp).
local veilGui = Instance.new("ScreenGui")
veilGui.Name = "SandstormVeil"
veilGui.IgnoreGuiInset = true
veilGui.ResetOnSpawn = false
veilGui.DisplayOrder = -10
veilGui.Enabled = false
veilGui.Parent = player:WaitForChild("PlayerGui")

local function veilLayer(rotation)
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 1
	f.Parent = veilGui
	local g = Instance.new("UIGradient")
	g.Rotation = rotation
	g.Transparency = NumberSequence.new({ kp(0, 0), kp(0.5, 0.45), kp(1, 0) })
	g.Parent = f
	return f
end
local veilAcross, veilDown = veilLayer(0), veilLayer(90)

----------------------------------------------------------------------
-- The wall of sand rolling in when the fight starts
----------------------------------------------------------------------
-- A great bank of dust, as wide as the arena, starts beyond the dunes upwind
-- and rolls straight across at Storm.FrontSpeed. It leaves the air full of
-- billowing sand behind it as it goes, and it's gone past the far side in a
-- few seconds - by then the storm is here.
local front = nil
local frontArmed = true -- (re-armed once the storm has died down again)

local function windDir(amb)
	local w = amb and amb.Wind or Vector3.new(1, 0, 0)
	w = Vector3.new(w.X, 0, w.Z)
	return w.Magnitude > 0.01 and w.Unit or Vector3.new(1, 0, 0)
end

local function endFront()
	if front then
		local wall = front.wall
		for _, e in ipairs(front.emitters) do
			e.Rate = 0
		end
		task.delay(6, function()
			wall:Destroy()
		end)
		front = nil
	end
end

local function startFront(amb, arena)
	local S = amb and amb.Storm
	if not S or S.Front == false or front then
		return
	end
	local center = arena and arena:GetAttribute("Center")
	if typeof(center) ~= "Vector3" then
		return
	end
	local w = windDir(amb)
	local from = center - w * 230 + Vector3.new(0, 24, 0)
	local wall = invisiblePart("StormFront", Vector3.new(420, 56, 18))
	wall.CFrame = CFrame.lookAt(from, from + w)
	local c = amb.Sand or Color3.fromRGB(226, 190, 130)
	local billow = Instance.new("ParticleEmitter")
	billow.Name = "Billow"
	billow.Color = ColorSequence.new(c:Lerp(Color3.fromRGB(150, 104, 62), 0.3))
	billow.LightInfluence = 1
	billow.Size = NumberSequence.new({ kp(0, 26), kp(1, 58) })
	billow.Transparency = NumberSequence.new({ kp(0, 1), kp(0.12, 0.3), kp(0.7, 0.5), kp(1, 1) })
	billow.Speed = NumberRange.new(6, 14)
	billow.Lifetime = NumberRange.new(3.5, 5)
	billow.RotSpeed = NumberRange.new(-15, 15)
	billow.Rotation = NumberRange.new(0, 360)
	billow.SpreadAngle = Vector2.new(20, 12)
	billow.EmissionDirection = Enum.NormalId.Front
	billow.Shape = Enum.ParticleEmitterShape.Box
	billow.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	billow.Rate = 80
	billow.Parent = wall
	local grit = Instance.new("ParticleEmitter")
	grit.Name = "Grit"
	grit.Texture = "rbxasset://textures/particles/smoke_main.dds"
	grit.Color = ColorSequence.new(c)
	grit.LightInfluence = 1
	grit.Size = NumberSequence.new({ kp(0, 0.3), kp(1, 0.5) })
	grit.Transparency = NumberSequence.new({ kp(0, 1), kp(0.15, 0.3), kp(1, 1) })
	grit.Speed = NumberRange.new(60, 80)
	grit.Lifetime = NumberRange.new(1, 1.5)
	grit.SpreadAngle = Vector2.new(6, 6)
	grit.EmissionDirection = Enum.NormalId.Front
	grit.Shape = Enum.ParticleEmitterShape.Box
	grit.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	grit.Rate = 240
	grit.Parent = wall
	front = { wall = wall, emitters = { billow, grit }, t0 = os.clock(), from = from, dir = w, speed = S.FrontSpeed or 55, far = 460 }
end

local function stepFront()
	if not front then
		return
	end
	local gone = (os.clock() - front.t0) * front.speed
	if gone > front.far then
		endFront()
		return
	end
	local at = front.from + front.dir * gone
	front.wall.CFrame = CFrame.lookAt(at, at + front.dir)
end

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
local lastAmb = nil -- the last arena's (kept while it fades out)
local level = 0 -- 0..1: how far faded in the arena's look, sand and wind are
local storm = 0 -- 0..1: how hard the storm is blowing on your screen
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

-- how hard the arena says the storm is blowing, 0 (calm) .. 1 (its height)
local function stormWanted()
	local arena = current and arenaFor(current)
	local s = arena and tonumber(arena:GetAttribute("Storm")) or CALM_STORM
	return math.clamp((s - CALM_STORM) / (FULL_STORM - CALM_STORM), 0, 1)
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
		lastAmb = amb
		lightIn(amb)
		-- arriving in the middle of a storm: it's simply there (no wall)
		frontArmed = stormWanted() < 0.15
	else
		lightOut()
		endFront()
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
	local amb = currentAmb or lastAmb -- while fading out, keep the last arena's look
	local S = amb and amb.Storm

	-- the storm: follows the arena (a little slower, so it builds as the wall
	-- rolls in); gone at once in the lobby
	local target = (S and current) and stormWanted() or 0
	storm = storm + (target - storm) * math.min(1, dt * 0.7)
	if S and current and frontArmed and target > 0.15 and level > 0.9 then
		frontArmed = false
		startFront(amb, arenaFor(current))
	elseif target < 0.05 and storm < 0.05 then
		frontArmed = true
	end
	stepFront()
	local k = S and storm or 0

	stepLight(amb, level, k)

	-- the sand: a box of it upwind of wherever you're looking, blowing through
	local cam = Workspace.CurrentCamera
	if cam and amb then
		local w = windDir(amb)
		local focus = (cam.Focus or cam.CFrame).Position
		local at = focus - w * 40 + Vector3.new(0, 6, 0)
		stormBox.CFrame = CFrame.lookAt(at, at + w)
		local c = amb.Sand or Color3.fromRGB(226, 190, 130)
		if sandColor ~= c then
			sandColor = c
			grains.Color = ColorSequence.new(c)
			dust.Color = ColorSequence.new(c)
			sheets.Color = ColorSequence.new(c:Lerp(Color3.fromRGB(170, 120, 70), 0.25))
			local veilColor = c:Lerp(Color3.fromRGB(150, 104, 62), 0.35)
			veilAcross.BackgroundColor3 = veilColor
			veilDown.BackgroundColor3 = veilColor
		end
	end
	grains.Rate = level * (GRAINS_CALM + (GRAINS_STORM - GRAINS_CALM) * k)
	dust.Rate = level * (DUST_CALM + (DUST_STORM - DUST_CALM) * k)
	sheets.Rate = level * SHEETS_STORM * k

	-- the dust in front of your eyes, breathing with the gusts
	local veil = (S and S.Veil or 0) * k * level
	if veil > 0.005 then
		local t = os.clock()
		local gust = 0.85 + 0.15 * math.sin(t * 0.8) * math.sin(t * 2.3 + 1)
		local a = math.clamp(veil * gust, 0, 0.95) * 0.6 -- (two layers of it)
		veilAcross.BackgroundTransparency = 1 - a
		veilDown.BackgroundTransparency = 1 - a
		veilGui.Enabled = true
	elseif veilGui.Enabled then
		veilGui.Enabled = false
	end

	-- the wind
	local s = windSound(amb)
	if s then
		local calm = amb.Volume or 0.3
		s.Volume = level * mix(calm, (S and S.Volume) or calm, k)
	end
	if level == 0 and want == 0 then
		-- faded all the way out: the lobby's look is back exactly as it was
		if wind then
			wind:Destroy()
			wind, windFor = nil, nil
		end
		storm = 0
		lastLevel, lastK = -1, -1
		lightGone()
	end
end)
