--[[
	BossClient  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "BossClient")

	Draws the Spire's bosses and everything they do. The server (BossService)
	decides what happens and publishes it as attributes on the boss model, each
	action stamped with the server's clock. This script builds the body on your
	screen and animates it from those timestamps - so the slime rearing up, the
	shadow spreading under it and the moment it lands are the same moment the
	server hits you, whatever your ping.

	What's here:
	  * the body: a translucent slime with a hollow dark core, eyes that follow
	    you, a crown of broken stone, and squash-and-stretch on everything
	  * every warning: the shadow under a slam, the wall of slime, glob landing
	    marks and their puddles, the rings of the wail, the lunge
	  * Mireworm (Body = "Worm"): its segmented body, the ridge it pushes up
	    swimming under the sand, and its own warnings (see "MIREWORM: the hunt"
	    below) - plus the rumble when it's close, the sinkhole and whirlpool
	    dragging you in, and the platforms breaking
	  * the boss bar across the top, with the trailing damage chip
	  * the shell shattering at half health, the dissolve on death, and the
	    victory banner
	  * you can't walk through it: it gently pushes you out of its body
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RGB = Color3.fromRGB
local V3 = Vector3.new
local STONE = RGB(122, 128, 136)
local STONE_DARK = RGB(70, 74, 80)
local SERIF = Enum.Font.Garamond

local bosses = {} -- [model] = the state of that boss on this screen
local SLOT_NAMES = { "ActA", "ActB", "ActC", "Act4", "Act5", "Act6", "Act7", "Act8", "Act9", "Act10", "Act11", "Act12", "Act13", "Act14", "Act15", "Act16", "Act17", "Act18", "Act19", "Act20", "Act21", "Act22", "Act23", "Act24" } -- (same list as BossService)

----------------------------------------------------------------------
-- Little helpers
----------------------------------------------------------------------
local function serverNow()
	return Workspace:GetServerTimeNow()
end

local function clamp(x, a, b)
	return math.max(a, math.min(b, x))
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function smooth(t)
	t = clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function easeOut(t)
	t = clamp(t, 0, 1)
	return 1 - (1 - t) ^ 3
end

local function easeOutBack(t)
	t = clamp(t, 0, 1)
	local c = 1.7
	return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2
end

-- a squash that springs back: 1 at the moment of landing, wobbling to 0
local function spring(t, decay, freq)
	if t < 0 then
		return 0
	end
	return math.exp(-(decay or 5) * t) * math.cos((freq or 13) * t)
end

local function flat(v)
	return V3(v.X, 0, v.Z)
end

local function tween(inst, seconds, props, style, dir)
	local t = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function myRoot()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hum and hrp and hum.Health > 0 then
		return hrp
	end
	return nil
end

----------------------------------------------------------------------
-- Things drawn in the world (only on this screen)
----------------------------------------------------------------------
local fxFolder = Instance.new("Folder")
fxFolder.Name = "BossFX"
fxFolder.Parent = Workspace

-- 8-BIT: the bosses are built from crisp blocks, like the rest of the game.
-- A "round" body piece becomes a plain block that fills its box (it still
-- squashes and stretches the same), its grainy stone/sand/glass textures
-- become flat colour, and its colour is snapped to the game's palette. (The
-- warning discs and rings on the floor stay round, so you can read them.)
-- Config.Retro.BossPixel = false puts the old smooth look back.
local PIXEL = not (Config.Retro and Config.Retro.BossPixel == false)
local FLAT = {
	[Enum.Material.Glass] = true, [Enum.Material.Sandstone] = true, [Enum.Material.Slate] = true,
	[Enum.Material.Sand] = true, [Enum.Material.Rock] = true, [Enum.Material.Cobblestone] = true,
	[Enum.Material.Basalt] = true, [Enum.Material.Ground] = true,
}
local BLOCKY = { Drip = true, Maw = true } -- (cylinders that are part of a body, not a warning)
-- the game's 32 colours (Endesga 32)
local PALETTE = {
	RGB(190, 74, 47), RGB(215, 118, 67), RGB(234, 212, 170), RGB(228, 166, 114), RGB(184, 111, 80), RGB(115, 62, 57),
	RGB(62, 39, 49), RGB(162, 38, 51), RGB(228, 59, 68), RGB(247, 118, 34), RGB(254, 174, 52), RGB(254, 231, 97),
	RGB(99, 199, 77), RGB(62, 137, 72), RGB(38, 92, 66), RGB(25, 60, 62), RGB(18, 78, 137), RGB(0, 153, 219),
	RGB(44, 232, 245), RGB(255, 255, 255), RGB(192, 203, 220), RGB(139, 155, 180), RGB(90, 105, 136), RGB(58, 68, 102),
	RGB(38, 43, 68), RGB(24, 20, 37), RGB(255, 0, 68), RGB(104, 56, 108), RGB(181, 80, 136), RGB(246, 117, 122),
	RGB(232, 183, 150), RGB(194, 133, 105),
}
local function snapColor(c)
	local best, bestD = c, math.huge
	for _, p in ipairs(PALETTE) do
		local d = (p.R - c.R) ^ 2 + (p.G - c.G) ^ 2 + (p.B - c.B) ^ 2
		if d < bestD then
			best, bestD = p, d
		end
	end
	return best
end

local function newPart(name, shape, color, material, transparency, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if PIXEL and (shape == Enum.PartType.Ball or (shape == Enum.PartType.Cylinder and BLOCKY[name])) then
		shape = nil -- (a block that fills its box)
	end
	if PIXEL then
		if material and FLAT[material] then
			material = Enum.Material.SmoothPlastic
		end
		if color and material ~= Enum.Material.Neon then
			color = snapColor(color)
		end
	end
	if shape == Enum.PartType.Ball then
		-- Roblox always draws a Ball part round, as wide as its smallest side, so
		-- a stretched one would shrink instead of stretching. A sphere mesh fills
		-- the part's box whatever its proportions - it's what lets the body squash
		-- and spread, and what makes the eyes slits and the mouth a gash rather
		-- than a row of dots.
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	elseif shape then
		p.Shape = shape
	end
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.Size = V3(1, 1, 1)
	p.Parent = parent or fxFolder
	return p
end

-- A flat disc lying on the floor (a Roblox cylinder's round faces point along
-- its X axis, so it's turned on its side).
local function placeDisc(p, center, diameter, thickness)
	p.Size = V3(thickness or 0.1, math.max(diameter, 0.05), math.max(diameter, 0.05))
	p.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2)
end

-- A ring on the floor made of short straight pieces (Roblox has no torus).
local function newRing(segments, color, material, transparency)
	local ring = { parts = {}, n = segments }
	for i = 1, segments do
		ring.parts[i] = newPart("RingPiece", nil, color, material, transparency)
	end
	return ring
end

local surfaceY -- (defined below; rings ask it where the ground is)
local function placeRing(ring, center, radius, height, thickness, transparency, followSurface)
	local n = ring.n
	radius = math.max(radius, 0.2)
	local length = 2 * radius * math.sin(math.pi / n) + thickness * 0.35
	for i, p in ipairs(ring.parts) do
		local a = (i - 0.5) / n * math.pi * 2
		local out = V3(math.sin(a), 0, math.cos(a))
		local pos = center + out * radius
		if followSurface and surfaceY then
			pos = V3(pos.X, surfaceY(pos, center.Y), pos.Z)
		end
		pos = pos + V3(0, height / 2, 0)
		p.Size = V3(length, math.max(height, 0.05), thickness)
		p.CFrame = CFrame.lookAt(pos, pos + out)
		if transparency then
			p.Transparency = transparency
		end
	end
end

-- The boss sleeps in a raised pit whose pool sits above the arena floor, so a
-- warning drawn at floor height near it would be hidden under the slime. This
-- is the height of whatever surface is actually showing at a spot.
local pit = nil
local nextPitLook = 0
function surfaceY(pos, floorY)
	if not pit and os.clock() >= nextPitLook then
		nextPitLook = os.clock() + 1
		local arena = Workspace:FindFirstChild("SlimeArena")
		local lip = arena and arena:FindFirstChild("PitLip", true)
		if lip then
			-- (a cylinder lies on its side: its X size is its thickness)
			pit = { center = lip.Position, radius = lip.Size.Y / 2, top = lip.Position.Y + lip.Size.X / 2 - 0.1 }
		end
	end
	if pit and flat(pos - pit.center).Magnitude <= pit.radius then
		return math.max(floorY, pit.top)
	end
	return floorY
end

-- a point on whatever surface is showing there
local function onFloor(pos)
	return V3(pos.X, surfaceY(pos, pos.Y), pos.Z)
end

local function removeRing(ring)
	for _, p in ipairs(ring.parts) do
		p:Destroy()
	end
end

-- a quick puff of particles at a point
local function burst(at, color, count, speed, size, lifetime, upward)
	local holder = newPart("Burst", nil, color, nil, 1)
	holder.Size = V3(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.new(at)
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.35
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size or 1.5), NumberSequenceKeypoint.new(1, (size or 1.5) * 2.2) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new((lifetime or 0.6) * 0.6, lifetime or 0.6)
	e.Speed = NumberRange.new((speed or 14) * 0.5, speed or 14)
	e.SpreadAngle = Vector2.new(upward and 35 or 80, upward and 35 or 80)
	e.Acceleration = V3(0, upward and -20 or -35, 0)
	e.Drag = 3
	e.EmissionDirection = Enum.NormalId.Top
	e.Rate = 0
	e.Parent = holder
	e:Emit(count or 20)
	task.delay(3, function()
		holder:Destroy()
	end)
end

----------------------------------------------------------------------
-- The camera and sound (the camera belongs to CombatClient: we ask it)
----------------------------------------------------------------------
local cameraKickEvent = nil
task.spawn(function()
	cameraKickEvent = player:WaitForChild("PlayerScripts"):WaitForChild("CombatCameraKick", 20)
end)

-- a knock to the camera that fades with distance from where it happened
local function kick(at, radius, strength, fov)
	local hrp = myRoot()
	if not (hrp and cameraKickEvent) then
		return
	end
	local d = flat(hrp.Position - at).Magnitude
	local k = clamp(1 - (d - radius) / 45, 0, 1)
	if k > 0 then
		cameraKickEvent:Fire(strength * k, fov and fov * k or nil)
	end
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

-- Finds a Sound in SoundService by name, ignoring capitals and spaces, so
-- "Boss SPit", "boss spit" and "BossSpit" are all the same sound.
local function squash(name)
	return string.lower((string.gsub(name, "%s+", "")))
end
local soundCache = {}
local function findSound(name)
	local key = squash(name)
	local cached = soundCache[key]
	if cached and cached.Parent then
		return cached
	end
	for _, child in ipairs(game:GetService("SoundService"):GetChildren()) do
		if child:IsA("Sound") and squash(child.Name) == key then
			soundCache[key] = child
			return child
		end
	end
	return nil
end

-- The barrage's splats: 14 land in about a second, so each one is soft, short
-- and quieter still when others have just landed - a patter, not a wall.
local SPLAT_VOLUME = 0.32
local SPLAT_LEAD = 0.04 -- seconds early, to meet the glob as it lands
local SPLAT_LENGTH = 0.45 -- each splat fades out after this, so they don't smear together
local recentSplats = {}

-- A boss sound. It's played flat through SoundService - the same way your
-- punches, potion and music play - and made quieter the further away it
-- happens, so a slam across the arena still sounds further off than one on
-- top of you. Config names the Sound (by default "Boss Slam" and so on, in
-- SoundService); an asset id works too.
-- Mireworm's own sounds that have no Gloomgut sound of the same name: if you
-- haven't added one yet, it borrows the nearest thing (a dive sounds like a
-- lunge, its body crashing down like a slam, and so on).
local SOUND_FALLBACK = { Dive = "Lunge", Crash = "Slam", Sweep = "Wave", Roar = "Wail", Devour = "Roar" }

local function playSound(def, key, at, volume)
	local want = def.Sounds and def.Sounds[key]
	if not want or want == "" then
		want = "Boss " .. key
	end
	local s
	local template = findSound(tostring(want))
	if not template then
		template = findSound("Boss " .. key) -- one you haven't added yet: borrow Gloomgut's
	end
	local k = key
	while not template and SOUND_FALLBACK[k] do
		k = SOUND_FALLBACK[k]
		local other = def.Sounds and def.Sounds[k]
		template = (other and other ~= "" and findSound(tostring(other))) or findSound("Boss " .. k)
	end
	if template then
		s = template:Clone()
	elseif tostring(want):match("^rbxassetid://") or tonumber(want) then
		s = Instance.new("Sound")
		s.SoundId = tostring(want):match("^rbx") and want or ("rbxassetid://" .. tostring(want))
	else
		return -- nothing by that name yet: silent, not an error
	end
	-- how far away it happened: full volume within 40 studs, fading to a third by 300
	local near = 1
	local cam = Workspace.CurrentCamera
	local hrp = myRoot()
	local ear = (hrp and hrp.Position) or (cam and cam.CFrame.Position)
	if ear and typeof(at) == "Vector3" then
		local d = (ear - at).Magnitude
		near = clamp(1 - (d - 40) / 260, 0.33, 1)
	end
	s.Volume = (volume or 1) * ((Config.Audio and Config.Audio.BossSounds) or 0.85) * near
	s.SoundGroup = soundGroup("Effects")
	-- sounds fired in quick bursts (the barrage) vary a little, so fourteen in a
	-- row sound like a barrage rather than one clip stuttering
	if key == "Splat" then
		-- the more that have just landed, the quieter this one
		local nowT = os.clock()
		for i = #recentSplats, 1, -1 do
			if nowT - recentSplats[i] > 0.35 then
				table.remove(recentSplats, i)
			end
		end
		s.Volume = s.Volume / (1 + 0.3 * #recentSplats)
		table.insert(recentSplats, nowT)
		s.PlaybackSpeed = (s.PlaybackSpeed or 1) * (0.96 + math.random() * 0.08)
	elseif key == "Spit" or key == "Erupt" or key == "Slam" or key == "Crash" then
		s.PlaybackSpeed = (s.PlaybackSpeed or 1) * (0.92 + math.random() * 0.16)
	end
	s.Looped = false
	s.Parent = game:GetService("SoundService")
	s:Play()
	if key == "Splat" or key == "Spit" then
		-- a quick fade instead of letting it ring on under the next one
		task.delay(SPLAT_LENGTH, function()
			if s.Parent then
				TweenService:Create(s, TweenInfo.new(0.12), { Volume = 0 }):Play()
			end
		end)
	end
	task.delay(math.max(tonumber(s.TimeLength) or 0, 1) + 2, function()
		s:Destroy()
	end)
end

----------------------------------------------------------------------
-- The body
----------------------------------------------------------------------
local BONE = RGB(226, 216, 186)

-- Gloomgut's body: a slime (the default for any boss without Body = "Worm")
local function buildSlimeBody(def)
	local D = def.Size
	local folder = Instance.new("Model")
	folder.Name = def.Short .. "Body"
	local body = { folder = folder }

	body.shell = newPart("Shell", Enum.PartType.Ball, def.Color, Enum.Material.Glass, 0.3, folder)
	body.shell.Reflectance = 0.06
	body.shell.CastShadow = true
	body.inner = newPart("Depths", Enum.PartType.Ball, def.DeepColor, Enum.Material.SmoothPlastic, 0.55, folder)
	-- the hollow thing inside: murky enough to see into, with a heart that beats
	body.core = newPart("HollowCore", Enum.PartType.Ball, def.CoreColor, Enum.Material.SmoothPlastic, 0.3, folder)
	body.heart = newPart("Heart", Enum.PartType.Ball, def.HeartColor or RGB(214, 255, 120), Enum.Material.Neon, 0, folder)
	body.light = Instance.new("PointLight")
	body.light.Color = def.Color
	body.light.Range = D * 1.3
	body.light.Brightness = 1.1
	body.light.Shadows = false
	body.light.Parent = body.heart

	-- the face: two slit eyes under heavy brows, and more eyes than it should have
	body.eyes = {}
	body.brows = {}
	for i = 1, 2 do
		body.eyes[i] = newPart("Eye", Enum.PartType.Ball, def.EyeColor, Enum.Material.Neon, 0, folder)
		body.brows[i] = newPart("Brow", Enum.PartType.Ball, def.CoreColor:Lerp(def.DeepColor, 0.35), Enum.Material.SmoothPlastic, 0.12, folder)
	end
	body.smallEyes = {}
	for i, spot in ipairs({ { -0.66, 0.44, 0.9 }, { 0.62, 0.52, 1.0 }, { -0.3, 0.7, 0.75 }, { 0.72, 0.06, 0.8 } }) do
		body.smallEyes[i] = {
			part = newPart("SmallEye", Enum.PartType.Ball, def.EyeColor, Enum.Material.Neon, 0, folder),
			x = spot[1], y = spot[2], size = spot[3],
			rate = 0.23 + i * 0.061, -- each one blinks on its own clock
			seed = i * 0.37,
		}
	end
	-- the maw: a dark gash that grins shut and gapes open, lined with teeth
	body.mouth = newPart("Mouth", Enum.PartType.Ball, RGB(14, 22, 12), Enum.Material.SmoothPlastic, 0.05, folder)
	body.teeth = {}
	for i = 1, 13 do
		local upper = i <= 7
		local n, k = upper and 7 or 6, upper and i or i - 7
		body.teeth[i] = {
			part = newPart("Tooth", nil, BONE, Enum.Material.SmoothPlastic, 0, folder),
			upper = upper,
			x = (k - 0.5) / n - 0.5, -- across the mouth, -0.5 .. 0.5
			long = 0.8 + ((i * 7) % 5) / 10, -- ragged, not a neat row
			tilt = (((i * 13) % 7) - 3) * 0.06,
		}
	end

	-- the crown: broken pillar stone it has worn for centuries, and one great shard
	body.crown = {}
	for i = 1, 7 do
		local shard = newPart("CrownShard", nil, i % 2 == 0 and STONE or STONE_DARK, Enum.Material.Slate, 0, folder)
		shard.CastShadow = true
		body.crown[i] = {
			part = shard,
			angle = (i - 1) / 7 * math.pi * 2 + 0.3,
			size = V3(1.7 + (i % 3) * 0.55, 3.4 + ((i * 5) % 4) * 1.05, 1.4 + (i % 2) * 0.4),
			tilt = 0.26 + (i % 3) * 0.14,
		}
	end
	local spire = newPart("CrownShard", nil, STONE, Enum.Material.Slate, 0, folder)
	spire.CastShadow = true
	body.crown[8] = { part = spire, angle = 0, size = V3(2.2, 7.2, 1.9), tilt = 0.08, center = true }

	-- what it has swallowed, turning slowly inside it
	body.debris = {}
	for i = 1, 5 do
		local chunk = newPart("Swallowed", nil, i % 2 == 0 and STONE_DARK or RGB(96, 90, 80), Enum.Material.Slate, 0.1, folder)
		body.debris[i] = { part = chunk, angle = i / 5 * math.pi * 2, height = -0.15 + (i % 3) * 0.14, size = V3(1 + (i % 2), 0.8 + (i % 3) * 0.4, 1.1), spin = 0.3 + i * 0.07 }
	end
	-- its foot: the body spreads over the floor it sits on, with a few lumps
	body.foot = newPart("Foot", Enum.PartType.Ball, def.Color, Enum.Material.Glass, 0.34, folder)
	body.skirt = {}
	for i = 1, 5 do
		body.skirt[i] = { part = newPart("Skirt", Enum.PartType.Ball, def.Color, Enum.Material.Glass, 0.3, folder), angle = (i - 0.5) / 5 * math.pi * 2 + 0.4, size = 0.15 + (i % 3) * 0.025 }
	end
	-- slime running down its sides
	body.drips = {}
	for i = 1, 6 do
		body.drips[i] = { part = newPart("Drip", Enum.PartType.Cylinder, def.Color, Enum.Material.SmoothPlastic, 0.18, folder), angle = (i - 1) / 6 * math.pi * 2 + 0.5, phase = i * 1.3, phase2 = i > 4 }
	end
	body.shadow = newPart("Shadow", Enum.PartType.Cylinder, RGB(8, 14, 8), Enum.Material.SmoothPlastic, 0.55, folder)

	folder.Parent = fxFolder
	return body
end

-- where a point on the front of the (stretched) body sits, so the eyes and
-- mouth stay on its surface whatever shape it's squashed into
local function onSurface(halfX, halfY, halfZ, x, y)
	if PIXEL then
		return -halfZ - 0.05 -- (the body is a block: its face is flat)
	end
	local k = 1 - (x / halfX) ^ 2 - (y / halfY) ^ 2
	return -halfZ * math.sqrt(math.max(k, 0.02)) - 0.05
end

-- Puts every part of the body where this frame's pose says.
local function applySlimePose(B, P, ground, facing, t, dt)
	local def, body = B.def, B.body
	if PIXEL then
		-- (sits a hair above the floor, so the cube's bottom never cuts through
		-- the glowing slime channels in the paving - see-through things that
		-- cut through each other flicker)
		ground = ground + V3(0, 0.3, 0)
	end
	local D = def.Size
	local H = D * 0.85 * P.sy
	local halfX, halfY, halfZ = D * P.sx / 2, H / 2, D * P.sz / 2
	local sinkDepth = P.sink * H * 0.85
	if PIXEL then
		-- (a round body can half-show out of the pool like a dome; a cube would be
		-- a flat slab sticking out of it - so asleep, it's right under the surface)
		sinkDepth = P.sink * (H + 2)
	end
	local fade = P.fade or 0
	local phase2 = B.phase2Look
	-- 8-BIT: only the jelly cube itself is see-through. Everything inside it or
	-- on it is solid, and pops out of sight in steps as it dies (fade) instead
	-- of turning see-through - because Roblox can't sort see-through parts
	-- that sit inside each other, and they flicker in front of each other.
	local function solid(goneAt)
		return (fade >= goneAt) and 1 or 0
	end

	local jitter = V3(0, 0, 0)
	if P.shake > 0 then
		jitter = V3((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2) * P.shake
	end
	local base = CFrame.lookAt(ground + jitter, ground + jitter + facing) * CFrame.Angles(-P.lean, 0, 0)
	local center = base * CFrame.new(0, P.lift + H / 2 - sinkDepth, 0)

	-- a punch landing turns the slime pale for a blink: you see every hit connect
	local flash = B.flashAt and clamp(1 - (os.clock() - B.flashAt) / 0.14, 0, 1) or 0
	body.shell.Size = V3(D * P.sx, H, D * P.sz)
	body.shell.CFrame = center
	body.shell.Transparency = lerp(phase2 and 0.44 or 0.3, 1, fade)
	body.shell.Color = def.Color:Lerp(RGB(236, 255, 214), 0.5 * flash)
	if PIXEL then
		-- (8-bit hit flash: a crisp white blink, not a fade)
		body.shell.Color = flash > 0.35 and RGB(255, 255, 255) or snapColor(def.Color)
	end
	body.inner.Size = body.shell.Size * 0.84
	body.inner.CFrame = center * CFrame.new(0, -H * 0.06, 0)
	body.inner.Transparency = lerp(phase2 and 0.72 or 0.55, 1, fade)
	if PIXEL then
		body.inner.Transparency = 1
	end

	-- the core lags behind the body: a little secondary motion reads as jelly
	local coreSize = D * (phase2 and 0.47 or 0.36) * (1 + 0.05 * math.sin(t * 2.7)) * (P.coreScale or 1)
	local coreWant = center * CFrame.new(0, -H * 0.04 + math.sin(t * 1.9) * 0.4, 0)
	B.corePos = B.corePos and B.corePos:Lerp(coreWant.Position, 1 - math.exp(-dt * 7)) or coreWant.Position
	body.core.Size = V3(coreSize, coreSize * 0.95, coreSize)
	body.core.CFrame = CFrame.new(B.corePos) * (center - center.Position)
	body.core.Transparency = lerp(phase2 and 0.4 or 0.3, 1, clamp(fade * 1.3 - 0.2, 0, 1))
	if PIXEL then
		body.core.Transparency = solid(0.6)
	end

	-- the heart: the thing you are actually killing. Two beats and a rest, faster
	-- once the shell is broken and faster again when it is nearly dead.
	local health = B.model and (B.model:GetAttribute("Health") or 1) / math.max(B.model:GetAttribute("MaxHealth") or 1, 1) or 1
	local rate = phase2 and (health <= def.DesperateAt and 2.4 or 1.7) or 1.1
	local beatT = (os.clock() * rate) % 1
	local beat = math.exp(-((beatT - 0.05) / 0.06) ^ 2) + 0.6 * math.exp(-((beatT - 0.24) / 0.06) ^ 2)
	local heartSize = D * (phase2 and 0.13 or 0.1) * (1 + 0.2 * beat + 0.3 * P.flare) * math.min(P.coreScale or 1, 1.25)
	body.heart.Size = V3(heartSize, heartSize, heartSize)
	body.heart.CFrame = CFrame.new(B.corePos)
	body.heart.Transparency = lerp(0, 1, clamp(fade * 1.5, 0, 1))
	if PIXEL then
		-- (the core is solid now: the heart glows on its front, like a gem, so you
		-- can still see the thing you're killing)
		body.heart.CFrame = body.core.CFrame * CFrame.new(0, 0, -(coreSize / 2))
		body.heart.Transparency = solid(0.7)
	end
	body.heart.Color = (def.HeartColor or RGB(214, 255, 120)):Lerp(RGB(255, 255, 230), 0.4 * beat + 0.4 * P.flare)
	body.light.Brightness = lerp((phase2 and 2.1 or 1.1) + 0.6 * beat + P.flare * 1.6, 0, fade)
	body.light.Range = D * (phase2 and 1.7 or 1.3)

	-- eyes: slits angled down toward the middle, glowing, shut when asleep
	local eyeOpen = clamp(P.eyes, 0, 1) * (1 - fade)
	local eyeY = H * 0.17
	for i, eye in ipairs(body.eyes) do
		local side = (i == 1) and -1 or 1
		local ex = side * D * 0.15 * P.sx
		local ez = onSurface(halfX, halfY, halfZ, ex, eyeY)
		eye.Size = V3(D * 0.17, math.max(D * 0.048 * eyeOpen * (1 + 0.5 * P.flare), 0.05), D * 0.05)
		eye.CFrame = center * CFrame.new(ex, eyeY, ez) * CFrame.Angles(0, 0, side * 0.32)
		eye.Transparency = eyeOpen < 0.05 and 1 or 0
		eye.Color = (def.EyeColor):Lerp(RGB(255, 255, 255), clamp(P.flare, 0, 1) * 0.5)
		-- the brow hangs over it at a steeper angle: that is what makes it glare
		local brow = body.brows[i]
		local bx, by = side * D * 0.16 * P.sx, eyeY + D * 0.07 - D * 0.02 * P.flare
		local bz = onSurface(halfX, halfY, halfZ, bx, by) + 0.12
		brow.Size = V3(D * 0.24, D * 0.06, D * 0.09)
		brow.CFrame = center * CFrame.new(bx, by, bz) * CFrame.Angles(0, 0, side * 0.44)
		brow.Transparency = PIXEL and solid(0.3) or lerp(0.12, 1, fade)
	end
	-- the other eyes, each blinking on its own slow clock
	for _, e in ipairs(body.smallEyes) do
		local x, y = e.x * halfX * 0.86, e.y * halfY * 0.86
		local blink = ((os.clock() * e.rate + e.seed) % 1) < 0.07 and 0 or 1
		local open = eyeOpen * blink
		local z = onSurface(halfX, halfY, halfZ, x, y)
		local size = D * 0.055 * e.size
		e.part.Size = V3(size, math.max(size * 0.8 * open, 0.05), size * 0.6)
		e.part.CFrame = center * CFrame.new(x, y, z) * CFrame.Angles(0, PIXEL and 0 or math.atan2(x, -z) * 0.8, 0)
		e.part.Transparency = open < 0.05 and 1 or 0
	end

	-- the maw
	local my = -H * 0.12
	local mouthW = D * 0.46 * P.sx
	local mouthH = math.max(D * (0.03 + 0.24 * P.mouth), 0.05)
	local mz = onSurface(halfX, halfY, halfZ, 0, my)
	body.mouth.Size = V3(mouthW, mouthH, D * 0.08)
	body.mouth.CFrame = center * CFrame.new(0, my - D * 0.04 * P.mouth, mz)
	body.mouth.Transparency = PIXEL and solid(0.4) or lerp(0.05, 1, fade)
	local mouthMid = my - D * 0.04 * P.mouth
	for _, tooth in ipairs(body.teeth) do
		local x = tooth.x * mouthW * 0.86
		local curve = 1 - (2 * tooth.x) ^ 2 -- the mouth is an oval: its edge dips at the corners
		local edge = mouthH / 2 * math.sqrt(math.max(curve, 0.05))
		local len = D * 0.07 * tooth.long * (0.75 + 0.25 * math.sqrt(math.max(curve, 0)))
		local y = tooth.upper and (mouthMid + edge - len / 2 + 0.15) or (mouthMid - edge + len / 2 - 0.15)
		local z = onSurface(halfX, halfY, halfZ, x, y) - 0.08
		tooth.part.Size = V3(D * 0.024, len * 1.1, D * 0.03) -- slim fangs, not a row of bricks
		tooth.part.CFrame = center * CFrame.new(x, y, z) * CFrame.Angles(0, 0, tooth.tilt + (tooth.upper and 0 or math.pi))
		tooth.part.Transparency = lerp(0, 1, clamp(fade * 1.2, 0, 1))
	end

	-- the crown, until the shell breaks
	for _, c in ipairs(body.crown) do
		if B.crownGone then
			c.part.Transparency = 1
		else
			local r = c.center and 0 or D * 0.21 * P.sx
			local pos = center * CFrame.new(math.cos(c.angle) * r, H * 0.42 + (c.center and 0.9 or 0), math.sin(c.angle) * r)
			c.part.Size = c.size
			c.part.CFrame = pos * CFrame.Angles(0, -c.angle, 0) * CFrame.Angles(0, 0, c.tilt)
			c.part.Transparency = PIXEL and solid(0.5) or fade
		end
	end
	-- what's inside, circling
	for _, d in ipairs(body.debris) do
		local a = d.angle + t * d.spin * (phase2 and 1.8 or 1)
		local r = D * 0.23
		d.part.Size = d.size
		d.part.CFrame = center * CFrame.new(math.cos(a) * r * P.sx, H * d.height, math.sin(a) * r * P.sz) * CFrame.Angles(t * d.spin, a, t * 0.4)
		d.part.Transparency = PIXEL and solid(0.5) or lerp(0.1, 1, fade)
	end
	-- the foot: spread out over the floor, pulled in when it leaves the ground,
	-- splashed wide when it lands
	local spread = clamp(1 - P.lift / (D * 0.3), 0.35, 1)
	local footW = D * 1.14 * spread * (1 + 0.6 * math.max(P.sx - 1, 0))
	local footH = D * 0.15 * (1 + 0.8 * math.max(P.sx - 1, 0))
	body.foot.Size = V3(footW, footH, footW * P.sz / P.sx)
	body.foot.CFrame = base * CFrame.new(0, P.lift * 0.96 + footH * 0.28 - sinkDepth * 0.4, 0)
	body.foot.Transparency = lerp(phase2 and 0.46 or 0.34, 1, math.max(fade, P.sink * 0.8))
	body.foot.Color = body.shell.Color
	-- (8-bit: a point on the cube's outside, in direction `a` round it, and
	-- which way that face looks)
	local function onBox(a, out)
		local cx, cz = math.cos(a), math.sin(a)
		local k = 1 / math.max(math.abs(cx) / halfX, math.abs(cz) / halfZ)
		local nx, nz = 0, 0
		if math.abs(cx) / halfX > math.abs(cz) / halfZ then
			nx = cx > 0 and 1 or -1
		else
			nz = cz > 0 and 1 or -1
		end
		return cx * k + nx * out, cz * k + nz * out
	end
	if PIXEL then
		body.foot.Transparency = 1 -- (a square sheet round a cube just looked odd)
	end
	for _, sk in ipairs(body.skirt) do
		local size = D * sk.size * (1 + 0.5 * math.max(P.sx - 1, 0)) * (1 - 0.3 * P.sink) * spread
		local r = footW * 0.43
		local pos = base * CFrame.new(math.cos(sk.angle) * r, size * 0.3 - sinkDepth * 0.3 + P.lift * 0.96, math.sin(sk.angle) * r * P.sz / P.sx)
		sk.part.Size = V3(size, size * 0.72, size)
		sk.part.Transparency = lerp(phase2 and 0.42 or 0.3, 1, fade)
		if PIXEL then
			-- solid lumps of goo oozing out at the foot of each face
			local x, z = onBox(sk.angle, size * 0.3)
			pos = base * CFrame.new(x, size * 0.3 - sinkDepth + P.lift * 0.96, z)
			sk.part.Transparency = math.max(solid(0.3), P.sink > 0.3 and 1 or 0)
			sk.part.Color = body.shell.Color
		end
		sk.part.CFrame = pos
	end
	-- drips lengthen and snap back
	for _, d in ipairs(body.drips) do
		if d.phase2 and not phase2 then
			d.part.Transparency = 1
		else
			local len = 1.5 + 2.2 * ((t * 0.45 + d.phase) % 1)
			local x, z = math.cos(d.angle) * halfX * 0.97, math.sin(d.angle) * halfZ * 0.97
			if PIXEL then
				x, z = onBox(d.angle, 0.2) -- (running down the outside of a face)
				len = math.floor(len * 2 + 0.5) / 2 -- (and growing in chunky steps)
			end
			local top = center * CFrame.new(x, -H * 0.02, z)
			d.part.Size = V3(len, 0.55, 0.55)
			d.part.CFrame = top * CFrame.new(0, -len / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
			d.part.Transparency = PIXEL and solid(0.3) or lerp(0.18, 1, fade)
		end
	end
	-- its shadow on the floor: widens as it rears up, marking where it will land
	local shadowD = P.shadowD or (D * 0.95 * P.sx)
	placeDisc(body.shadow, onFloor(ground) + V3(0, 0.08, 0), shadowD, 0.1)
	body.shadow.Transparency = lerp(P.shadowDark and (0.62 - 0.3 * P.shadowDark) or 0.62, 1, math.max(fade, P.sink))
	if PIXEL then
		-- a solid dark shadow (a see-through one under a see-through cube flickers)
		body.shadow.Transparency = (fade > 0.5 or P.sink > 0.5) and 1 or 0
		body.shadow.Color = RGB(24, 20, 37)
	end
end

----------------------------------------------------------------------
-- Mireworm's body (any boss with Body = "Worm" in Config)
----------------------------------------------------------------------
-- A vast segmented worm that comes up out of the sand in an arch: its tail
-- runs down under the floor, its body rises and curls over, and its head hangs
-- over you with the maw pointed down at you. The maw is a dark throat ringed
-- with teeth, behind three armoured jaws that close into a point and bloom
-- open when it roars or spits. Plates of armour run down its back until
-- they're blasted off at half health - after that, the seams between its
-- segments glow like a furnace.
--
-- It reads the same pose knobs as the slime (lift, sink, lean, mouth, flare...)
-- so every Pose works for both bodies; this is just how a worm shows them:
--   lift  its head rears higher        sink  it goes down into the sand
--   lean  + head thrusts at you, - rears back      sy < 1  its head crashes down
--   ridge (worm only) the mound of sand it pushes up swimming underneath
-- and a few knobs only the worm has, for when it isn't standing up out of a hole:
--   path(s)  where its spine runs, tail (s = 0) to head (s = 1), in the world:
--            the breach's arc, the coil's ring
--   girth    how thick it is (the coil is thinner than it stands)
--   taper(s) how thick it is along its length, tail to head (the lash's whippy tail)
--   stage    a new stage inside one move (its body flows into it, like a new move)
--   collar   0 hides the mound of sand round its base; noShadow hides its shadow
local WORM_SEGMENTS = 20 -- (enough to bend smoothly into an arch, a ring or a leap)
local WORM_BLEND = 0.3 -- seconds its body takes to flow from one shape into the next
local WORM_SAND = RGB(224, 188, 128) -- the arena's sand, for everything it throws up
local WORM_SAND_DEEP = RGB(122, 92, 58) -- churned-up quicksand
local WORM_PLATE = RGB(156, 124, 88)
local WORM_PLATE_DARK = RGB(126, 100, 72)
local WORM_TEETH = 8 -- round the rim of the maw
local WORM_JAWS = 3
local WORM_EYES = 6

-- a scale of armour: a wedge, thick at the back and thin at the front, so
-- they overlap down its back like a fish's
local function newWedge(name, color, material, parent)
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.CanCollide = false
	w.CanQuery = false
	w.CanTouch = false
	w.CastShadow = true
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	w.Color = color
	w.Material = material
	w.Size = V3(1, 1, 1)
	w.Parent = parent
	return w
end

local function wormEmitter(name, parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Rate = 0
	e.Parent = parent
	return e
end

local function buildWormBody(def)
	local folder = Instance.new("Model")
	folder.Name = def.Short .. "Body"
	local body = { folder = folder }
	local heartColor = def.HeartColor or RGB(255, 90, 40)

	-- the body, from the tail (under the sand) to the head, banded light and dark
	body.segments, body.seams, body.plates = {}, {}, {}
	for i = 1, WORM_SEGMENTS do
		local head = i == WORM_SEGMENTS
		local color = (i % 2 == 0) and def.Color or def.Color:Lerp(def.DeepColor, 0.3)
		local seg = newPart(head and "Head" or "Segment", Enum.PartType.Ball, color, Enum.Material.Sandstone, 0, folder)
		seg.CastShadow = true
		body.segments[i] = { part = seg, color = color }
		-- the crease between this segment and the next: dark now, molten later
		if not head then
			body.seams[i] = newPart("Seam", Enum.PartType.Ball, def.DeepColor, Enum.Material.SmoothPlastic, 0, folder)
		end
		-- armour down its back: a ridge of overlapping scales, with plates on
		-- its flanks (only on the segments that ever come up out of the sand)
		if i >= 4 then
			table.insert(body.plates, { part = newWedge("Plate", WORM_PLATE, Enum.Material.Slate, folder), seg = i, side = 0 })
			if i % 2 == 0 and not head then
				for _, side in ipairs({ -1, 1 }) do
					local plate = newPart("Plate", nil, WORM_PLATE_DARK, Enum.Material.Slate, 0, folder)
					plate.CastShadow = true
					table.insert(body.plates, { part = plate, seg = i, side = side })
				end
			end
		end
	end

	-- the maw: a dark throat with the heart glowing in it, ringed with teeth
	body.maw = newPart("Maw", Enum.PartType.Cylinder, def.CoreColor, Enum.Material.SmoothPlastic, 0, folder)
	body.heart = newPart("Heart", Enum.PartType.Ball, heartColor, Enum.Material.Neon, 0, folder)
	body.light = Instance.new("PointLight")
	body.light.Color = heartColor
	body.light.Range = def.Size * 1.1
	body.light.Brightness = 1.2
	body.light.Shadows = false
	body.light.Parent = body.heart
	body.teeth = {}
	for i = 1, WORM_TEETH do
		body.teeth[i] = {
			part = newPart("Tooth", nil, BONE, Enum.Material.SmoothPlastic, 0, folder),
			angle = (i - 0.5) / WORM_TEETH * math.pi * 2,
			long = 0.8 + ((i * 5) % 4) * 0.12, -- ragged, not a neat ring
		}
	end
	-- three jaws that close into a point and bloom open, fanged on the inside
	body.jaws = {}
	for j = 1, WORM_JAWS do
		local jaw = {
			part = newPart("Jaw", Enum.PartType.Ball, def.Color:Lerp(def.DeepColor, 0.45), Enum.Material.Sandstone, 0, folder),
			angle = (j - 1) / WORM_JAWS * math.pi * 2 + math.pi / 2,
			fangs = {},
		}
		jaw.part.CastShadow = true
		for f = 1, 3 do
			jaw.fangs[f] = newPart("Tooth", nil, BONE, Enum.Material.SmoothPlastic, 0, folder)
		end
		body.jaws[j] = jaw
	end
	-- small eyes, far too many of them, in a ring behind the jaws
	body.eyes = {}
	for i = 1, WORM_EYES do
		body.eyes[i] = {
			part = newPart("Eye", Enum.PartType.Ball, def.EyeColor, Enum.Material.Neon, 0, folder),
			angle = (i - 0.5) / WORM_EYES * math.pi * 2 + 0.2,
			size = 1.3 + (i % 3) * 0.35,
			rate = 0.19 + i * 0.043, -- each one blinks on its own clock
			seed = i * 0.31,
		}
	end

	-- the sand: a mound where it comes out of the floor, the ridge it pushes up
	-- when it swims underneath, sand pouring off it and dust round its base
	body.collar = newPart("SandCollar", Enum.PartType.Ball, WORM_SAND:Lerp(WORM_SAND_DEEP, 0.15), Enum.Material.Sand, 0, folder)
	body.ridge = newPart("SandRidge", Enum.PartType.Ball, WORM_SAND, Enum.Material.Sand, 1, folder)
	body.spillAt = newPart("SandSpill", nil, WORM_SAND, nil, 1, folder)
	body.spillAt.Size = V3(def.Size * 0.5, 2, def.Size * 0.5)
	body.spill = wormEmitter("Spill", body.spillAt, {
		Color = ColorSequence.new(WORM_SAND),
		LightInfluence = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 2.4) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1.1, 1.7),
		Speed = NumberRange.new(1, 4),
		SpreadAngle = Vector2.new(60, 60),
		Acceleration = V3(0, -42, 0),
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	})
	body.dustAt = newPart("SandDust", nil, WORM_SAND, nil, 1, folder)
	body.dustAt.Size = V3(def.Size * 1.2, 1, def.Size * 1.2)
	body.dust = wormEmitter("Dust", body.dustAt, {
		Color = ColorSequence.new(WORM_SAND),
		LightInfluence = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 11) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1.4, 2.4),
		Speed = NumberRange.new(4, 10),
		SpreadAngle = Vector2.new(70, 70),
		Acceleration = V3(0, -3, 0),
		Drag = 1.5,
		RotSpeed = NumberRange.new(-40, 40),
		Rotation = NumberRange.new(0, 360),
		EmissionDirection = Enum.NormalId.Top,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	})
	body.shadow = newPart("Shadow", Enum.PartType.Cylinder, RGB(40, 28, 16), Enum.Material.SmoothPlastic, 0.55, folder)

	folder.Parent = fxFolder
	return body
end

local function bezier(p0, p1, p2, p3, s)
	local u = 1 - s
	return p0 * (u * u * u) + p1 * (3 * u * u * s) + p2 * (3 * u * s * s) + p3 * (s * s * s)
end

local function bezierSlope(p0, p1, p2, p3, s)
	local u = 1 - s
	return (p1 - p0) * (3 * u * u) + (p2 - p1) * (6 * u * s) + (p3 - p2) * (3 * s * s)
end

-- a frame at `pos` whose look runs along `along`, with its top turned as near
-- to `up` as it can be
local function frameAlong(pos, along, up)
	local look = along.Magnitude > 1e-4 and along.Unit or V3(0, 1, 0)
	local y = up - look * up:Dot(look)
	if y.Magnitude < 1e-4 then
		y = math.abs(look.Y) < 0.9 and (V3(0, 1, 0) - look * look.Y) or (V3(1, 0, 0) - look * look.X)
	end
	y = y.Unit
	return CFrame.fromMatrix(pos, look:Cross(y), y, -look)
end

-- Drawing the worm cheaply. It's over a hundred parts, redrawn every frame, so:
--  * every part's new place is collected and they all move in one go (BulkMoveTo)
--  * sizes, colours, see-through-ness and materials are only written when they've
--    actually changed
--  * a segment deep under the sand (nobody can see it) is left where it was
local Fast = {
	parts = {}, cframes = {}, n = 0,
	sizes = setmetatable({}, { __mode = "k" }),
	alphas = setmetatable({}, { __mode = "k" }),
	colors = setmetatable({}, { __mode = "k" }),
}
function Fast.move(p, cf)
	local n = Fast.n + 1
	Fast.n = n
	Fast.parts[n], Fast.cframes[n] = p, cf
end
function Fast.flush()
	local n = Fast.n
	if n == 0 then
		return
	end
	for i = #Fast.parts, n + 1, -1 do
		Fast.parts[i], Fast.cframes[i] = nil, nil
	end
	local ok = pcall(function()
		Workspace:BulkMoveTo(Fast.parts, Fast.cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end)
	if not ok then
		for i = 1, n do
			Fast.parts[i].CFrame = Fast.cframes[i]
		end
	end
	Fast.n = 0
end
-- (`tolerance`: how much it has to change by before it's worth resizing -
-- parts that overlap their neighbours can take a bigger one)
function Fast.size(p, v, tolerance)
	local old = Fast.sizes[p]
	if not old or math.abs(old.X - v.X) + math.abs(old.Y - v.Y) + math.abs(old.Z - v.Z) > (tolerance or 0.12) then
		Fast.sizes[p] = v
		p.Size = v
	end
end
function Fast.alpha(p, a)
	if Fast.alphas[p] ~= a then
		Fast.alphas[p] = a
		p.Transparency = a
	end
end
function Fast.color(p, c)
	if PIXEL and p.Material ~= Enum.Material.Neon then
		c = snapColor(c) -- (8-bit: its colours stay on the palette as they change)
	end
	if Fast.colors[p] ~= c then
		Fast.colors[p] = c
		p.Color = c
	end
end

local function applyWormPose(B, P, ground, facing, t, dt)
	local def, body = B.def, B.body
	local D = def.Size
	local fade = P.fade or 0
	local phase2 = B.phase2Look
	local sink = clamp(P.sink or 0, 0, 1)
	local ridge = clamp(P.ridge or 0, 0, 1.6)

	-- all the way under and nothing moving on the surface: it's already hidden
	-- where it last was, so there's nothing to do (the dunes are a long way
	-- from the lobby, and every screen runs this every frame). The same asleep
	-- in its coils while you're somewhere else: drawn once, then left.
	local resting = B.model:GetAttribute("State") == "Dormant" and player:GetAttribute("SpireFloor") ~= B.floor
	if (not P.path and sink >= 0.999 and ridge < 0.02 and fade <= 0) or fade >= 1 or resting then
		if B.parked then
			return
		end
		B.parked = true
	else
		B.parked = false
	end

	local jitter = V3(0, 0, 0)
	if P.shake > 0 then
		jitter = V3((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2) * P.shake
	end
	local origin = ground + jitter
	local F = facing
	local U = V3(0, 1, 0)
	local R = F:Cross(U)
	local floorY = ground.Y

	-- how tall it stands and how thick it is (squash and stretch, toned down:
	-- it's a worm, not a jelly)
	local H = D * 1.35 * (1 + (P.sy - 1) * 0.8) + P.lift * 1.1
	local girth = P.girth or D * 0.64 * (1 + (P.sx - 1) * 0.6)
	local lean = P.lean
	local fwd, back = math.max(lean, 0), math.min(lean, 0)
	-- squashed: its head has come down hard. A slime springs straight back; a
	-- worm's head stays down in the sand a moment before it heaves it up again.
	local crash = math.max(0, 1 - P.sy)
	if crash >= (B.crashPeak or 0) * clamp(1 - (t - (B.crashAt or 0) - 0.15) / 0.3, 0, 1) then
		B.crashPeak, B.crashAt = crash, t
	end
	crash = math.max(crash, (B.crashPeak or 0) * clamp(1 - (t - (B.crashAt or 0) - 0.15) / 0.3, 0, 1))
	local moving = B.model:GetAttribute("Moving")
	local sway = math.sin(t * 1.2) * 0.05 + (moving and math.sin(t * 6) * 0.1 or 0)

	-- the spine: up out of the sand leaning back, over the top, and the head
	-- hanging down at you like a question mark
	-- (with a twist to one side, so it's a serpent from the front too, not a pillar)
	local c0 = V3(-D * 0.08, -D * 0.8, -D * 0.05)
	local c1 = V3(D * 0.2 + sway * D * 0.5, H * 0.72, -D * 0.3 + lean * D * 0.12)
	local c2 = V3(-D * 0.14 + sway * D * 0.9, math.max(H * (1.12 - 0.35 * fwd) - crash * H * 0.45, girth * 0.5), D * 0.3 + lean * D * 0.5)
	local c3 = V3(sway * D * 0.4,
		math.max(H * (0.76 - 0.45 * fwd - 0.32 * back) - crash * H * 1.6, girth * 0.45),
		D * 0.68 + lean * D * 0.55 - crash * D * 0.1)
	-- sunk: the whole of it goes down into the sand together
	local sinkDepth = sink * (math.max(c2.Y, c3.Y) + girth * 1.1 + 2)
	local function world(v)
		return origin + R * v.X + U * (v.Y - sinkDepth) + F * v.Z
	end
	local function slope(v)
		return R * v.X + U * v.Y + F * v.Z
	end

	-- a punch landing blanches it for a blink, so every hit shows
	local flash = B.flashAt and clamp(1 - (os.clock() - B.flashAt) / 0.14, 0, 1) or 0
	local health = (B.model:GetAttribute("Health") or 1) / math.max(B.model:GetAttribute("MaxHealth") or 1, 1)

	-- the segments: along the question mark, or along whatever path the pose gave
	local points = {}
	local S0 = 0.08
	local path = P.path
	for i = 1, WORM_SEGMENTS do
		local s = S0 + (1 - S0) * (i - 1) / (WORM_SEGMENTS - 1)
		if path then
			local pos = path(s)
			points[i] = { s = s, pos = pos, along = path(math.min(s + 0.02, 1.02)) - path(math.max(s - 0.02, 0)) }
		else
			points[i] = { s = s, pos = world(bezier(c0, c1, c2, c3, s)), along = slope(bezierSlope(c0, c1, c2, c3, s)) }
		end
	end
	-- Hand-overs: when it starts something new, its body flows from the shape it
	-- was in to the new one instead of jumping. Head first: its head sets off
	-- into the new shape and the rest follows on down its length, the way a
	-- creature moves (not every part at once, like a morph). The further it has
	-- to go, the longer it takes - a moment either way. Parts that were out of
	-- sight under the sand simply come up in their new place. (Not when it's
	-- come up somewhere else entirely: then there's nothing to flow from.)
	local from = B.blendFrom
	if from and from[WORM_SEGMENTS] and not B.blendUntil then
		local hidden, far = B.blendHidden or {}, 0
		for i, pt in ipairs(points) do
			if not hidden[i] then
				far = math.max(far, (from[i] - pt.pos).Magnitude)
			end
		end
		B.blendTime = clamp(WORM_BLEND + far / 160, WORM_BLEND, 0.6)
		B.blendUntil = t + B.blendTime
	end
	if from and from[WORM_SEGMENTS] and t < B.blendUntil then
		if flat(from[WORM_SEGMENTS] - points[WORM_SEGMENTS].pos).Magnitude < 70 then
			local q = 1 - (B.blendUntil - t) / B.blendTime
			local w = smooth(q)
			local hidden = B.blendHidden or {}
			for i, pt in ipairs(points) do
				if not hidden[i] then
					pt.pos = from[i]:Lerp(pt.pos, smooth(clamp(q * 1.6 - (1 - pt.s) * 0.6, 0, 1)))
				end
			end
			for i, pt in ipairs(points) do
				local a, b = points[math.max(i - 1, 1)].pos, points[math.min(i + 1, WORM_SEGMENTS)].pos
				if (b - a).Magnitude > 1e-3 then
					pt.along = b - a
				end
			end
			girth = lerp(B.blendGirth or girth, girth, w)
		else
			B.blendFrom = nil
		end
	end
	-- (this frame's shape, to flow from next time)
	B.lastPoints = B.lastPoints or {}
	for i, pt in ipairs(points) do
		B.lastPoints[i] = pt.pos
	end
	B.lastGirth = girth

	-- which segments are deep under the sand (a girth or more down): once one
	-- has been put down there it's left alone - nobody can see it
	B.buried = B.buried or {}
	local skip = {}
	for i, pt in ipairs(points) do
		local deep = pt.pos.Y < floorY - girth * (i == WORM_SEGMENTS and 1.05 or 1)
		skip[i] = deep and B.buried[i] == true and fade <= 0
		B.buried[i] = deep
	end

	local frames, girths, lengths = {}, {}, {}
	for i, pt in ipairs(points) do
		local prev = points[i - 1] and (pt.pos - points[i - 1].pos).Magnitude or 0
		local nxt = points[i + 1] and (points[i + 1].pos - pt.pos).Magnitude or 0
		local g = girth * (P.taper and P.taper(pt.s) or (1.06 - 0.16 * pt.s))
		local len = math.max(prev, nxt) * 1.75
		if i == WORM_SEGMENTS then
			-- the head: broader than its neck, a hood over the maw
			g = g * 1.2
			len = math.max(len, g * 1.2)
		end
		local along = pt.along.Magnitude > 1e-4 and pt.along.Unit or U
		-- its top is its back (on a path - a ring, an arc, lying flat - its back is simply up)
		local cf = frameAlong(pt.pos, along, path and U or R:Cross(along))
		frames[i], girths[i], lengths[i] = cf, g, len
		if not skip[i] then
			local seg = body.segments[i]
			Fast.size(seg.part, V3(g, g * 0.96, len), 0.35)
			Fast.move(seg.part, cf)
			local c = phase2 and seg.color:Lerp(def.DeepColor, 0.2) or seg.color
			Fast.color(seg.part, flash > 0 and c:Lerp(RGB(255, 240, 214), 0.45 * flash) or c)
			Fast.alpha(seg.part, fade)
		end
	end

	B.segGirths = girths -- (how thick each piece is: you can't walk through it)

	-- the creases: dark, until its armour is gone and they burn
	local heartColor = def.HeartColor or RGB(255, 90, 40)
	for i, seam in ipairs(body.seams) do
		if not (skip[i] and skip[i + 1]) then
			local a, b = frames[i], frames[i + 1]
			local g = (girths[i] + girths[i + 1]) / 2 * 0.84
			Fast.size(seam, V3(g, g * 0.96, 1.3), 0.3)
			Fast.move(seam, frameAlong((a.Position + b.Position) / 2, b.Position - a.Position, a.UpVector))
			if phase2 then
				if seam.Material ~= Enum.Material.Neon then
					seam.Material = Enum.Material.Neon
				end
				local tq = math.floor(t * 12) / 12 -- (a dozen changes a second is plenty for a glow)
				Fast.color(seam, heartColor:Lerp(RGB(255, 214, 140), 0.25 + 0.25 * math.sin(tq * 3 + i)))
			else
				if seam.Material ~= Enum.Material.SmoothPlastic then
					seam.Material = Enum.Material.SmoothPlastic
				end
				Fast.color(seam, def.DeepColor)
			end
			Fast.alpha(seam, fade)
		end
	end

	-- the armour, until it's blasted off: scales down the ridge of its back
	-- (thick end toward the tail, so they overlap) and plates on its flanks
	for _, pl in ipairs(body.plates) do
		if B.crownGone then
			Fast.alpha(pl.part, 1)
		elseif not skip[pl.seg] then
			local cf, g, len = frames[pl.seg], girths[pl.seg], lengths[pl.seg]
			if pl.side == 0 then
				local h = g * (pl.seg == WORM_SEGMENTS and 0.15 or 0.2)
				Fast.size(pl.part, V3(g * 0.3, h, len * 0.62), 0.3)
				Fast.move(pl.part, cf * CFrame.new(0, g * 0.46 + h / 2 - g * 0.04, len * 0.08))
			else
				Fast.size(pl.part, V3(g * 0.3, g * 0.06, len * 0.5), 0.3)
				Fast.move(pl.part, cf * CFrame.Angles(0, 0, pl.side * 0.8) * CFrame.new(0, g * 0.47, 0))
			end
			Fast.alpha(pl.part, fade)
		end
	end

	-- the head
	local headCF = frames[WORM_SEGMENTS]
	local gH, lenH = girths[WORM_SEGMENTS], lengths[WORM_SEGMENTS]
	B.headPos = headCF.Position
	local T, top, side = headCF.LookVector, headCF.UpVector, headCF.RightVector
	local mouth = clamp(P.mouth, 0, 1)
	local rimR = gH * 0.27
	local mawAt = headCF.Position + T * (lenH / 2 * 0.8)
	B.mawPos = mawAt -- (what it spits from)
	local rate = phase2 and (health <= def.DesperateAt and 2.4 or 1.7) or 1.1
	local beatT = (os.clock() * rate) % 1
	local beat = math.exp(-((beatT - 0.05) / 0.06) ^ 2) + 0.6 * math.exp(-((beatT - 0.24) / 0.06) ^ 2)
	body.light.Brightness = lerp((phase2 and 2.4 or 1.2) + 0.6 * beat + P.flare * 1.8, 0, math.max(fade, sink))
	if not skip[WORM_SEGMENTS] then
		Fast.size(body.maw, V3(0.5, rimR * 2, rimR * 2))
		Fast.move(body.maw, CFrame.fromMatrix(mawAt, T, top, T:Cross(top)))
		Fast.alpha(body.maw, fade)

		-- the heart in its throat: two beats and a rest, faster once its armour is
		-- gone, faster again when it's nearly dead
		local heartSize = gH * (phase2 and 0.2 or 0.15) * (1 + 0.2 * beat + 0.3 * P.flare) * math.min(P.coreScale or 1, 1.3)
		Fast.size(body.heart, V3(heartSize, heartSize, heartSize * 0.6))
		Fast.move(body.heart, CFrame.fromMatrix(mawAt + T * 0.35, side, top, -T))
		Fast.alpha(body.heart, clamp(fade * 1.5, 0, 1))
		Fast.color(body.heart, heartColor:Lerp(RGB(255, 236, 190), 0.35 * beat + 0.4 * P.flare))
		body.light.Range = D * (phase2 and 1.6 or 1.1)

		-- teeth round the rim, pointing in at the throat
		for _, tooth in ipairs(body.teeth) do
			local radial = side * math.cos(tooth.angle) + top * math.sin(tooth.angle)
			local len = gH * 0.15 * tooth.long * (0.85 + 0.3 * mouth)
			local dir = (T * 0.45 - radial).Unit
			local base = mawAt + radial * (rimR * 0.96) + T * 0.2
			Fast.size(tooth.part, V3(gH * 0.05, len, gH * 0.05))
			Fast.move(tooth.part, CFrame.fromMatrix(base + dir * (len / 2), T:Cross(radial), dir))
			Fast.alpha(tooth.part, clamp(fade * 1.2, 0, 1))
		end

		-- the jaws: shut into a point, open straight ahead to spit, splayed wide to roar
		local jawLen = gH * 0.62
		local theta = lerp(-0.55, 1.15, mouth)
		for _, jaw in ipairs(body.jaws) do
			local radial = side * math.cos(jaw.angle) + top * math.sin(jaw.angle)
			local hinge = mawAt + radial * rimR - T * 0.4
			local dir = T * math.cos(theta) + radial * math.sin(theta)
			local out = radial * math.cos(theta) - T * math.sin(theta) -- its outer face
			local across = dir:Cross(out)
			Fast.size(jaw.part, V3(gH * 0.32, gH * 0.12, jawLen))
			Fast.move(jaw.part, CFrame.fromMatrix(hinge + dir * (jawLen / 2), across, out, -dir))
			Fast.alpha(jaw.part, fade)
			for f, fang in ipairs(jaw.fangs) do
				local len = gH * 0.1 * (1.15 - f * 0.12)
				local tip = hinge + dir * (jawLen * (0.25 + f * 0.18)) - out * (gH * 0.04)
				Fast.size(fang, V3(gH * 0.045, len, gH * 0.045))
				Fast.move(fang, CFrame.fromMatrix(tip - out * (len / 2), across, -out))
				Fast.alpha(fang, clamp(fade * 1.2, 0, 1))
			end
		end

		-- its eyes, in a ring round the head behind the jaws
		local eyeOpen = clamp(P.eyes, 0, 1) * (1 - fade)
		local ringAt = headCF.Position + T * (lenH / 2 * 0.42)
		local ringR = gH / 2 * 0.96 * math.sqrt(1 - 0.42 ^ 2) * 0.97
		local eyeColor = def.EyeColor:Lerp(RGB(255, 255, 255), clamp(P.flare, 0, 1) * 0.4)
		for _, e in ipairs(body.eyes) do
			local radial = side * math.cos(e.angle) + top * math.sin(e.angle)
			local blink = ((os.clock() * e.rate + e.seed) % 1) < 0.06 and 0 or 1
			local open = eyeOpen * blink
			local size = e.size * (1 + 0.35 * P.flare)
			Fast.size(e.part, V3(size, math.max(size * open, 0.05), size * 0.7))
			Fast.move(e.part, CFrame.fromMatrix(ringAt + radial * ringR, T:Cross(radial), T, radial))
			Fast.alpha(e.part, open < 0.05 and 1 or 0)
			Fast.color(e.part, eyeColor)
		end
	end

	-- (the old sand collar, solid "ridge" lump and flat shadow disc are gone: it
	-- comes out of real craters in the Terrain sand now, its back arches out of
	-- the real sand when it swims, and its body casts real shadows)
	Fast.alpha(body.collar, 1)
	Fast.alpha(body.ridge, 1)
	Fast.alpha(body.shadow, 1)

	-- sand pours off it as it comes up; dust blows off its base as it moves
	local out = 1 - sink
	local floorAt = onFloor(ground)
	local lastSink = B.lastSink or sink
	B.lastSink = sink
	local rising = dt > 0 and (lastSink - sink) / dt or 0
	B.spillHeat = math.max((B.spillHeat or 0) * math.exp(-dt * 0.8), clamp(rising * 1.5, 0, 1))
	Fast.move(body.spillAt, headCF)
	body.spill.Rate = (P.spill or ((1 - fade) * out * (4 + 35 * B.spillHeat))) * 0.5
	Fast.move(body.dustAt, CFrame.new(floorAt + V3(0, 1, 0)))
	body.dust.Rate = (1 - fade) * (ridge * 18 + (moving and out * 6 or 0) + B.spillHeat * out * 15) * 0.5
	Fast.flush()
end

-- Which body a boss has, and how to pose it.
local function buildBody(def)
	if def.Body == "Worm" then
		return buildWormBody(def)
	end
	return buildSlimeBody(def)
end

local function applyPose(B, P, ground, facing, t, dt)
	if B.kind == "Worm" then
		applyWormPose(B, P, ground, facing, t, dt)
	else
		applySlimePose(B, P, ground, facing, t, dt)
	end
end

----------------------------------------------------------------------
-- Warnings in the world
----------------------------------------------------------------------
-- Each one is a little object with update(now) -> keep going?, and cleanup.
local function addTelegraph(B, tele)
	table.insert(B.telegraphs, tele)
end

-- a flat shock ring spreading from where something hit the floor
local function shockRing(B, at, fromR, toR, seconds, color)
	at = onFloor(at)
	local ring = newRing(28, color or B.def.EyeColor, Enum.Material.Neon, 0.2)
	local t0 = serverNow()
	addTelegraph(B, {
		update = function(now)
			local u = (now - t0) / seconds
			if u >= 1 then
				return false
			end
			placeRing(ring, at + V3(0, 0.1, 0), lerp(fromR, toR, easeOut(u)), 0.5 * (1 - u) + 0.1, 0.9, lerp(0.25, 1, u), true)
			return true
		end,
		cleanup = function()
			removeRing(ring)
		end,
	})
end

-- The wall of slime: its radius at any moment is exactly what the server tests.
local function waveRing(B, origin, t0)
	local a = B.def.Attacks.Wave
	local start = B.def.Size / 2
	local wallT = B.fx.solid and 0 or 0.25 -- a wall of slime you can see into; a wall of sand you can't
	local wall = newRing(52, B.fx.color, B.fx.material, wallT)
	local crest = newRing(52, B.def.EyeColor, Enum.Material.Neon, 0.55)
	local life = a.Reach / a.Speed
	addTelegraph(B, {
		update = function(now)
			local age = now - t0
			if age > life then
				return false
			end
			if age < 0 then
				placeRing(wall, origin, start, 0.05, a.Thickness, 1)
				placeRing(crest, origin, start, 0.05, a.Thickness * 0.4, 1)
				return true
			end
			local r = start + a.Speed * age
			local fadeOut = clamp((age - (life - 0.35)) / 0.35, 0, 1)
			local h = a.Height * (1 - 0.45 * fadeOut) * (0.92 + 0.08 * math.sin(now * 30))
			placeRing(wall, origin + V3(0, 0.05, 0), r, h, a.Thickness, lerp(wallT, 1, fadeOut), true)
			placeRing(crest, origin + V3(0, h * 0.85, 0), r, h * 0.3, a.Thickness * 0.45, lerp(0.5, 1, fadeOut), true)
			return true
		end,
		cleanup = function()
			removeRing(wall)
			removeRing(crest)
		end,
	})
end

-- The stone platforms on a boss's floor (the dunes have five; nothing that
-- comes up out of the sand comes up through them - BossService has the same
-- rule). One the worm has shattered (Broken) is just sand again.
local function onStone(B, pos)
	if not B.stones or (#B.stones == 0 and os.clock() > (B.stonesLook or 0)) then
		B.stonesLook = os.clock() + 2 -- (the arena may not have loaded in yet: look again soon)
		B.stones = {}
		for _, pm in ipairs(CollectionService:GetTagged("DunePlatform")) do
			local slab = pm:GetAttribute("Floor") == B.floor and pm:FindFirstChild("PlatformSlab")
			if slab then
				table.insert(B.stones, { center = slab.Position, radius = pm:GetAttribute("Radius") or 10, model = pm })
			end
		end
	end
	for _, st in ipairs(B.stones) do
		if not st.model:GetAttribute("Broken") and flat(pos - st.center).Magnitude <= st.radius then
			return true
		end
	end
	return false
end

-- A glob in flight: where it will land is marked on the floor from the moment
-- it leaves the mouth, filling in as it comes down.
local function glob(B, from, to, launchAt)
	local a = B.def.Attacks.Spit
	to = onFloor(to)
	local landAt = launchAt + a.Flight
	local fx = B.fx
	-- the slime spits glowing globs that leave burning puddles; the worm hurls
	-- clods of hardened sand that leave churning quicksand
	local ballT = fx.solid and 0 or 0.15
	local ball = newPart("Glob", Enum.PartType.Ball, fx.color, fx.material, ballT)
	ball.Size = fx.solid and V3(3.2, 3.2, 3.2) or V3(2.4, 2.4, 2.4)
	local mark = newRing(22, B.def.EyeColor, Enum.Material.Neon, 0.4)
	local fill = newPart("GlobMark", Enum.PartType.Cylinder, fx.solid and fx.deep or B.def.Color, fx.solid and Enum.Material.Sand or Enum.Material.Neon, 0.7)
	local peak = 7 + flat(to - from).Magnitude * 0.18
	local landed = false
	local splatted = false
	addTelegraph(B, {
		update = function(now)
			local u = (now - launchAt) / a.Flight
			if u < 0 then
				ball.Transparency = 1
				return true
			end
			-- the splat starts a few hundredths early: sound takes a moment to
			-- reach your ears, so a splat started on the exact frame feels late
			if not splatted and now >= launchAt + a.Flight - SPLAT_LEAD then
				splatted = true
				playSound(B.def, "Splat", to, SPLAT_VOLUME)
			end
			if u < 1 then
				local p = from:Lerp(to, u) + V3(0, peak * 4 * u * (1 - u), 0)
				ball.Transparency = ballT
				ball.CFrame = CFrame.new(p) * CFrame.Angles(u * 7, u * 5, 0) -- (a clod tumbles)
				placeRing(mark, to + V3(0, 0.06, 0), a.Radius, 0.18, 0.5, 0.45 - 0.3 * u)
				placeDisc(fill, to + V3(0, 0.07, 0), 2 * a.Radius * u, 0.08)
				fill.Transparency = 0.75 - 0.25 * u
				return true
			end
			if not landed then
				landed = true
				ball.Transparency = 1
				burst(to + V3(0, 0.5, 0), fx.color, 16, 18, 1.2, 0.5)
				shockRing(B, to, 1, a.Radius * 1.2, 0.3, fx.color)
				kick(to, a.Radius, 0.35)
			end
			-- then the puddle it leaves, burning for a few seconds (a clod that
			-- lands on stone just shatters: nothing for it to sink into)
			local left = (landAt + a.PuddleTime) - now
			if left <= 0 or (fx.solid and onStone(B, to)) then
				return false
			end
			placeRing(mark, to + V3(0, 0.05, 0), a.Puddle, 0.12, 0.4, lerp(1, 0.55, clamp(left, 0, 1)))
			placeDisc(fill, to + V3(0, 0.06, 0), 2 * a.Puddle * (0.96 + 0.04 * math.sin(now * 6)), 0.1)
			fill.Transparency = lerp(1, 0.35, clamp(left, 0, 1))
			return true
		end,
		cleanup = function()
			ball:Destroy()
			fill:Destroy()
			removeRing(mark)
		end,
	})
end

-- A ring of the wail: blooms, fills over its fuse (faster pulse near the end),
-- then erupts in a column of slime.
local function wailRing(B, at, bloomAt)
	local a = B.def.Attacks.Wail
	at = onFloor(at)
	local eruptAt = bloomAt + a.Fuse
	local fx = B.fx
	local outline = newRing(30, B.def.EyeColor, Enum.Material.Neon, 0.3)
	local fill = newPart("WailFill", Enum.PartType.Cylinder, fx.solid and fx.deep or B.def.Color, fx.solid and Enum.Material.Sand or Enum.Material.Neon, 0.6)
	-- a pillar of slime - or of sand, with shards of rock thrown up in it
	local column = newPart("Geyser", Enum.PartType.Cylinder, fx.color, fx.material, 1)
	local columnT = fx.solid and 0.05 or 0.35
	local spikes = {}
	for i = 1, 6 do
		spikes[i] = newPart("Spike", nil, fx.solid and fx.rock or B.def.DeepColor, fx.solid and Enum.Material.Slate or Enum.Material.Glass, 1)
	end
	local erupted = false
	addTelegraph(B, {
		update = function(now)
			local k = (now - bloomAt) / a.Fuse
			if k < 0 then
				return true
			end
			if k < 1 then
				local pulse = 0.5 + 0.5 * math.sin(now * lerp(8, 26, k))
				placeRing(outline, at + V3(0, 0.06, 0), a.Radius, 0.25, 0.6, lerp(0.45, 0.1, pulse * k))
				placeDisc(fill, at + V3(0, 0.07, 0), 2 * a.Radius * smooth(k), 0.08)
				fill.Transparency = lerp(0.75, 0.35, k)
				return true
			end
			if not erupted then
				erupted = true
				burst(at + V3(0, 1, 0), fx.color, 26, 30, 1.8, 0.8, true)
				shockRing(B, at, 1, a.Radius * 1.3, 0.35)
				playSound(B.def, "Erupt", at, 0.9)
				kick(at, a.Radius, 0.8, -2.5)
				for i = 1, #outline.parts do
					outline.parts[i].Transparency = 1
				end
				fill.Transparency = 1
			end
			local e = now - eruptAt
			if e > 0.9 then
				return false
			end
			-- the geyser: shoots up, then collapses
			local up = e < 0.18 and easeOut(e / 0.18) or (1 - smooth((e - 0.18) / 0.72))
			local h = (a.Geyser or 16) * up -- a pillar of slime
			column.Size = V3(math.max(h, 0.05), a.Radius * 1.1, a.Radius * 1.1)
			column.CFrame = CFrame.new(at + V3(0, h / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
			column.Transparency = lerp(columnT, 1, clamp((e - 0.3) / 0.6, 0, 1))
			for i, sp in ipairs(spikes) do
				local ang = i / #spikes * math.pi * 2
				local len = (a.Geyser or 16) * 0.4 * up
				local p = at + V3(math.cos(ang) * a.Radius * 0.6, len / 2, math.sin(ang) * a.Radius * 0.6)
				sp.Size = V3(1.1 + a.Radius * 0.08, math.max(len, 0.05), 1.1 + a.Radius * 0.08)
				sp.CFrame = CFrame.new(p) * CFrame.Angles(math.sin(ang) * 0.4, 0, -math.cos(ang) * 0.4)
				sp.Transparency = column.Transparency
			end
			return true
		end,
		cleanup = function()
			removeRing(outline)
			fill:Destroy()
			column:Destroy()
			for _, sp in ipairs(spikes) do
				sp:Destroy()
			end
		end,
	})
end

-- the crown flying apart when the shell breaks
local function shatterCrown(B, center)
	B.crownGone = true
	for i, c in ipairs(B.body.crown) do
		local shard = newPart("Shard", nil, c.part.Color, Enum.Material.Slate, 0)
		shard.Size = c.size
		shard.CastShadow = true
		local start = c.part.CFrame
		local out = V3(math.cos(c.angle + i), 0, math.sin(c.angle + i))
		local speed = 18 + (i % 3) * 6
		local t0 = serverNow()
		addTelegraph(B, {
			update = function(now)
				local e = now - t0
				if e > 1.6 then
					return false
				end
				local p = start.Position + out * speed * e + V3(0, 22 * e - 30 * e * e, 0)
				if p.Y < center.Y - 6 then
					p = V3(p.X, center.Y - 6, p.Z)
				end
				shard.CFrame = CFrame.new(p) * (start - start.Position) * CFrame.Angles(e * 7, e * 3, 0)
				shard.Transparency = clamp((e - 1.1) / 0.5, 0, 1)
				return true
			end,
			cleanup = function()
				shard:Destroy()
			end,
		})
	end
end

-- Mireworm's armour blasting off its back when it breaks at half health
local function shatterPlates(B)
	B.crownGone = true
	local floorY = B.vpos.Y
	for i, pl in ipairs(B.body.plates) do
		local start = pl.part.CFrame
		if pl.part.Transparency < 1 and i % 2 == 1 then -- half of them fly: plenty of debris, half the parts
			local shard = newPart("Shard", nil, pl.part.Color, Enum.Material.Slate, 0)
			shard.Size = pl.part.Size
			shard.CastShadow = true
			local away = start.UpVector + V3(0, 0.5, 0)
			away = away.Magnitude > 0.01 and away.Unit or V3(0, 1, 0)
			local speed = 24 + (i % 4) * 7
			local t0 = serverNow()
			addTelegraph(B, {
				update = function(now)
					local e = now - t0
					if e > 2.4 then
						return false
					end
					local p = start.Position + away * speed * e + V3(0, -38 * e * e, 0)
					if p.Y < floorY + 0.6 then
						p = V3(p.X, floorY + 0.6, p.Z) -- landed in the sand
					end
					shard.CFrame = CFrame.new(p) * (start - start.Position) * CFrame.Angles(e * 5, e * 2, e * 3)
					shard.Transparency = clamp((e - 1.8) / 0.6, 0, 1)
					return true
				end,
				cleanup = function()
					shard:Destroy()
				end,
			})
		end
	end
end

-- The arena a boss fights in (the model that says which floor it is)
local function arenaOf(B)
	if B.arena and B.arena.Parent then
		return B.arena
	end
	B.arena = nil
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("Floor") == B.floor and child:GetAttribute("Storm") ~= nil then
			B.arena = child
			break
		end
	end
	return B.arena
end

-- (Mireworm's sand tools live in their own block: a Roblox script may only
-- have 200 names at its top level, so only the ones used elsewhere are shared.)
local Terrain, newScar, scarHole, scarHeave, carve, closeScar, forgetScar, stepScars, closeAllScars, floorHeightAt, warmSand
do
	----------------------------------------------------------------------
	-- The sand floor, torn up (Mireworm's arena)
	----------------------------------------------------------------------
	-- The dunes' fighting floor is Terrain sand (DunesBuilder), so the worm can
	-- really tear it up: craters where it bursts out, a trench where its body
	-- crashes down, the ground heaving up before an ambush, fissures in a tremor,
	-- the sinkhole of a devour and the pit in phase two. It's all done on YOUR
	-- screen (every screen does the same thing at the same moment, from the
	-- server's clock), and you really walk in it. After Scars.Last seconds the
	-- sand slides back in and the floor is flat again. Hits never depend on it:
	-- the server decides those exactly as before.
	Terrain = Workspace:FindFirstChildOfClass("Terrain")
	local AIR, SANDMAT = Enum.Material.Air, Enum.Material.Sand
	local scars = {} -- torn-up sand waiting to slide back
	local floorInfo = nil -- the arena floor: where it is and what stands on it

	-- round down / up to Terrain's 4-stud grid
	local function grid(v, up)
		return up and math.ceil(v / 4) * 4 or math.floor(v / 4) * 4
	end

	-- Things standing on the sand (pillars, platforms, braziers...) that a hole
	-- mustn't open under, and flat decoration lying on it (ripples, bones...)
	-- that would float over a hole, so it's hidden until the sand comes back.
	local KEEP_OUT = { EdgeWall = true, SealStone = true, SealRing = true, SealCoil = true, SealTile = true, SandSwirl = true }
	local function arenaFloor(B)
		local arena = arenaOf(B)
		if not arena then
			return nil
		end
		if floorInfo and floorInfo.arena == arena and os.clock() < floorInfo.fresh then
			return floorInfo
		end
		local center = arena:GetAttribute("Center")
		if typeof(center) ~= "Vector3" then
			return nil
		end
		-- (looked through once - it's a big model - and again only if it changes)
		local info = { arena = arena, floor = B.floor, center = center, radius = arena:GetAttribute("SandRadius") or 146, y = center.Y, solids = {}, decor = {}, fresh = math.huge }
		for _, d in ipairs(arena:GetDescendants()) do
			if d:IsA("BasePart") and not KEEP_OUT[d.Name] then
				local p = d.Position
				local big = math.max(d.Size.X, d.Size.Y, d.Size.Z)
				local owner = d:FindFirstAncestorWhichIsA("Model")
				local ownName = owner and owner.Name or ""
				if big < 80 and flat(p - center).Magnitude < info.radius + 6 and math.abs(p.Y - info.y) < big / 2 + 1 then
					if d.CanCollide then
						table.insert(info.solids, { part = d, r = math.max(d.Size.X, d.Size.Z) / 2 })
					elseif d.Transparency < 1 and not ownName:find("^DunePlatform") then
						table.insert(info.decor, d)
					end
				end
			end
		end
		floorInfo = info
		return info
	end

	-- how big a hole can be here: it stops short of anything standing on the
	-- sand, and of the dunes round the edge
	local function roomAt(info, pos, radius)
		radius = math.min(radius, info.radius - 8 - flat(pos - info.center).Magnitude)
		for _, s in ipairs(info.solids) do
			if s.part.Parent and s.part.CanCollide then
				local gap = flat(pos - s.part.Position).Magnitude - s.r - 1.5
				if gap < radius then
					radius = gap
				end
			end
		end
		return radius
	end

	-- A new scar (a crater, a trench, fissures, a heave...) - balls of air (or of
	-- sand, for a heave) that go back to flat floor together
	function newScar(B, kind, life)
		-- (tearing up the Terrain sand is the heaviest thing the worm does to your
		-- screen: it's off unless Config turns it on - Scars.Terrain = true)
		local SC = B.def and B.def.Scars
		if not (SC and SC.Terrain) then
			return nil
		end
		local info = (player:GetAttribute("SpireFloor") == B.floor) and Terrain and arenaFloor(B)
		if not info then
			return nil
		end
		local sc = { kind = kind, info = info, balls = {}, hidden = {}, refillAt = serverNow() + (life or 7) }
		sc.halfAt = sc.refillAt - 1.1
		table.insert(scars, sc)
		return sc
	end

	-- Terrain edits wait their turn and go through a few a frame, so a whole
	-- trench (or the sand sliding back into several craters) never lands in one
	-- frame and hitches your screen.
	local edits = {}
	local EDITS_PER_FRAME = 2
	local function terrainEdit(fn)
		edits[#edits + 1] = fn
	end

	-- Sand about to be put back where YOU stand: you're lifted onto it first.
	-- (Your character's physics runs on your own screen, so sand appearing
	-- around your legs would bury you - and a buried character loses the
	-- ground and drops straight through the floor.) `top` is the new surface.
	local FEET = 3 -- (from the middle of your body down to your feet, near enough)
	local function liftOut(x0, x1, z0, z1, top, redug)
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return
		end
		local p = hrp.Position
		if p.X < x0 - 1.5 or p.X > x1 + 1.5 or p.Z < z0 - 1.5 or p.Z > z1 + 1.5 then
			return
		end
		-- (standing in another hole that's dug straight back out in the same
		-- moment - the phase-two pit, say - you stay where you are)
		for _, b in ipairs(redug or {}) do
			if not b.height and flat(p - V3(b.x, 0, b.z)).Magnitude < b.r - 1 then
				return
			end
		end
		if p.Y - FEET < top + 0.3 and p.Y > top - 20 then
			hrp.CFrame = hrp.CFrame + V3(0, top + FEET + 0.6 - p.Y, 0)
			hrp.AssemblyLinearVelocity = V3(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z)
		end
	end

	-- puts one piece of a scar into the terrain (again, if something covered it)
	local TERRACES = 5
	local function carveBall(ball)
		if ball.closed then
			return -- (its scar has been filled back in since)
		end
		if ball.cone then
			-- a wide, shallow pit (the phase-two bowl): stacked discs of air, each
			-- narrower and deeper than the last - far less work for Terrain than
			-- one enormous ball - which Terrain rounds off into a smooth bowl
			for k = 1, TERRACES do
				local r = ball.r * (1 - (k - 1) / TERRACES)
				local d = ball.depth * k / TERRACES
				Terrain:FillCylinder(CFrame.new(ball.x, ball.floorY - d / 2 + 0.5, ball.z), d + 1, r, AIR)
			end
		elseif ball.height then
			-- a heave: two stacked discs of sand, only ever above the floor (so
			-- it never fills in a crater next to it); Terrain rounds them off
			liftOut(ball.x - ball.r, ball.x + ball.r, ball.z - ball.r, ball.z + ball.r, ball.floorY + ball.height)
			Terrain:FillCylinder(CFrame.new(ball.x, ball.floorY + ball.height * 0.3, ball.z), ball.height * 0.6, ball.r, SANDMAT)
			Terrain:FillCylinder(CFrame.new(ball.x, ball.floorY + ball.height * 0.5, ball.z), ball.height, ball.r * 0.6, SANDMAT)
		else
			Terrain:FillBall(ball.c, ball.rs, AIR)
		end
	end
	local function ballFill(ball)
		terrainEdit(function()
			carveBall(ball)
		end)
	end

	-- Adds one bowl of air to a scar: `radius` across at the top, `depth` deep.
	-- (A big ball of air whose bottom just dips into the sand.)
	function scarHole(sc, pos, radius, depth)
		if not sc then
			return
		end
		local info = sc.info
		radius = roomAt(info, pos, radius)
		if radius < 2.5 then
			return
		end
		depth = math.min(depth, radius * 0.7)
		local rs = (radius * radius + depth * depth) / (2 * depth)
		local ball = { c = V3(pos.X, info.y - depth + rs, pos.Z), rs = rs, x = pos.X, z = pos.Z, r = radius, depth = depth, floorY = info.y }
		ball.cone = rs > 40 -- (very wide and shallow: carved in cheap stacked discs instead)
		ballFill(ball)
		table.insert(sc.balls, ball)
		-- what was lying there would float: hidden until the sand comes back
		for _, d in ipairs(info.decor) do
			if d.Parent and not sc.hidden[d] and flat(d.Position - pos).Magnitude < radius + 1 then
				sc.hidden[d] = d.Transparency
				d.Transparency = 1
			end
		end
	end

	-- Adds a heave: sand pushed UP out of the floor in a low mound
	function scarHeave(sc, pos, radius, height)
		if not sc then
			return
		end
		local info = sc.info
		radius = roomAt(info, pos, radius)
		if radius < 2.5 then
			return
		end
		local ball = { x = pos.X, z = pos.Z, r = radius, height = height, floorY = info.y }
		ballFill(ball)
		table.insert(sc.balls, ball)
	end

	-- one-shot helpers
	function carve(B, pos, radius, depth, life)
		local sc = newScar(B, "hole", life)
		scarHole(sc, pos, radius, depth)
		return sc
	end

	-- the grid-aligned box round a scar's balls
	local function scarBox(sc)
		local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
		for _, b in ipairs(sc.balls) do
			x0, x1 = math.min(x0, b.x - b.r), math.max(x1, b.x + b.r)
			z0, z1 = math.min(z0, b.z - b.r), math.max(z1, b.z + b.r)
		end
		return grid(x0 - 4), grid(x1 + 4, true), grid(z0 - 4), grid(z1 + 4, true)
	end

	-- The sand sliding back. `upTo` = how high to fill (the floor, or partway for
	-- the first half of the slide). A heave is simply cleared away above the floor.
	local function refillScar(sc, upTo)
		if #sc.balls == 0 then
			return
		end
		local info = sc.info
		local x0, x1, z0, z1 = scarBox(sc)
		local mid = V3((x0 + x1) / 2, 0, (z0 + z1) / 2)
		-- anything else torn up in that box (another crater, the phase-two pit)
		local redug = {}
		for _, other in ipairs(scars) do
			if other ~= sc then
				for _, b in ipairs(other.balls) do
					if b.x + b.r > x0 and b.x - b.r < x1 and b.z + b.r > z0 and b.z - b.r < z1 then
						redug[#redug + 1] = b
					end
				end
			end
		end
		terrainEdit(function()
			if sc.kind == "heave" then
				local h = grid(12, true)
				Terrain:FillBlock(CFrame.new(mid.X, info.y + h / 2, mid.Z), V3(x1 - x0, h, z1 - z0), AIR)
			else
				local bottom = info.y - 12
				local top = upTo or info.y
				liftOut(x0, x1, z0, z1, top, redug)
				Terrain:FillBlock(CFrame.new(mid.X, (bottom + top) / 2, mid.Z), V3(x1 - x0, top - bottom, z1 - z0), SANDMAT)
			end
			-- ...goes back the way it was in the SAME moment: there's never a
			-- frame where the sand covers a hole someone is standing in
			for _, b in ipairs(redug) do
				carveBall(b)
			end
		end)
	end

	function closeScar(sc)
		refillScar(sc)
		for _, b in ipairs(sc.balls) do
			b.closed = true -- (so nothing digs it back out later)
		end
		for d, t in pairs(sc.hidden) do
			if d.Parent then
				d.Transparency = t
			end
		end
		sc.balls, sc.hidden = {}, {}
	end

	-- Every frame: a few waiting terrain edits, and sand sliding back into the
	-- scars whose time is up
	function stepScars()
		for _ = 1, math.min(EDITS_PER_FRAME, #edits) do
			pcall(table.remove(edits, 1))
		end
		-- The safety net: if you ever end up under the arena's floor (whatever
		-- put you there), you're put straight back on top of the sand, right
		-- where you were (or just inside the edge), instead of falling forever.
		local info = floorInfo
		if info and player:GetAttribute("SpireFloor") == info.floor then
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and hrp.Position.Y < info.y - 10 then
				local off = flat(hrp.Position - info.center)
				if off.Magnitude < info.radius + 60 then
					local keep = math.min(off.Magnitude, info.radius - 8)
					local spot = info.center + (off.Magnitude > 0.1 and off.Unit * keep or V3())
					hrp.AssemblyLinearVelocity = V3()
					hrp.CFrame = CFrame.new(V3(spot.X, info.y + FEET + 4, spot.Z)) * (hrp.CFrame - hrp.Position)
				end
			end
		end
		local now = serverNow()
		for i = #scars, 1, -1 do
			local sc = scars[i]
			if now >= sc.refillAt then
				table.remove(scars, i)
				closeScar(sc)
			elseif now >= sc.halfAt and not sc.halfDone and sc.kind == "hole" and sc.balls[1] then
				-- halfway: it's filling in (and a little sand pours in)
				sc.halfDone = true
				local deepest = 0
				for _, b in ipairs(sc.balls) do
					deepest = math.max(deepest, b.depth or 0)
				end
				refillScar(sc, sc.info.y - deepest * 0.45)
				local b = sc.balls[1]
				burst(V3(b.x, sc.info.y + 0.5, b.z), WORM_SAND, 8, 6, 1.6, 0.8)
			end
		end
	end

	-- everything back to flat (the worm went back to sleep, or you left)
	function closeAllScars()
		for i = #scars, 1, -1 do
			local sc = table.remove(scars, i)
			closeScar(sc)
		end
	end

	-- Ready the sand before the fight (the worm's warm-up, "rehearse"): look
	-- through the arena for what stands on the sand now, and dig one small
	-- hole deep inside the floor and fill it straight back in - out of sight -
	-- so the fight's first real crater doesn't stall.
	function warmSand(B)
		floorInfo = nil
		local info = arenaFloor(B)
		if info and Terrain then
			local deep = info.center - V3(0, 10, 0)
			pcall(function()
				Terrain:FillBall(deep, 2, AIR)
				Terrain:FillBall(deep, 2, SANDMAT)
			end)
		end
	end

	-- the height of the floor at a spot, given the scars (for putting things on
	-- the sides of a crater or the pit rather than floating over it)
	function floorHeightAt(pos, floorY)
		local y = floorY
		for _, sc in ipairs(scars) do
			if sc.kind == "hole" then
				for _, b in ipairs(sc.balls) do
					local x = flat(pos - V3(b.x, 0, b.z)).Magnitude
					if x < b.r then
						if b.cone then
							y = math.min(y, floorY - b.depth * (1 - x / b.r))
						else
							y = math.min(y, b.c.Y - math.sqrt(math.max(b.rs * b.rs - x * x, 0)))
						end
					end
				end
			end
		end
		return y
	end

	-- stops keeping track of a scar without filling it in (collapseSeal fills the
	-- bowl itself)
	function forgetScar(sc)
		for i, other in ipairs(scars) do
			if other == sc then
				table.remove(scars, i)
				return
			end
		end
	end
end

-- The stone seal at the middle of the dunes caves in when Mireworm's armour
-- breaks: the floor there collapses into a real bowl of sand, with arms of
-- sand swirling down into the pit at the bottom - and it's whole again the
-- next time the worm sleeps. (Only on your screen, but every screen does it
-- at the same moment.)
local SEAL_PARTS = { SealStone = true, SealRing = true, SealCoil = true, SealTile = true, SandSwirl = true }
local function collapseSeal(B, on, instant)
	local arena = arenaOf(B)
	if arena and (not B.seal or #B.seal == 0) then
		-- (what caves in, looked up once - the worm's warm-up does it before the fight)
		B.seal = {}
		for _, d in ipairs(arena:GetDescendants()) do
			if d:IsA("BasePart") and SEAL_PARTS[d.Name] then
				table.insert(B.seal, { part = d, cf = d.CFrame, transparency = d.Transparency or 0 })
			end
		end
	end
	if (B.sealDown or false) == on or not arena then
		return
	end
	B.sealDown = on
	for _, s in ipairs(B.seal) do
		if s.tween then
			s.tween:Cancel()
			s.tween = nil
		end
		if on and not instant then
			s.tween = tween(s.part, 1.2 + (s.cf.Position.Y % 0.3), { CFrame = s.cf - V3(0, 6, 0), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		elseif on then
			s.part.CFrame = s.cf - V3(0, 6, 0)
			s.part.Transparency = 1
		else
			s.part.CFrame = s.cf
			s.part.Transparency = s.transparency
		end
	end
	if B.crater then
		for _, p in ipairs(B.crater) do
			p:Destroy()
		end
		B.crater = nil
	end
	B.vortex = nil
	if B.bowl then
		-- the sand fills the pit back in
		forgetScar(B.bowl)
		closeScar(B.bowl)
		B.bowl = nil
	end
	if not on then
		return
	end
	-- the pit
	local center, radius = nil, 34
	for _, h in ipairs(CollectionService:GetTagged("DuneSinkhole")) do
		if h:GetAttribute("Floor") == B.floor then
			center, radius = h.Position, h:GetAttribute("Radius") or 34
		end
	end
	center = center or arena:GetAttribute("Center")
	if typeof(center) ~= "Vector3" then
		return
	end
	local W = B.def.Whirlpool or {}
	local bowlR, depth = (W.Radius or radius) - 2, W.Depth or 5
	-- the floor gives way: it sinks in stages (all at once if you arrive late)
	B.bowl = newScar(B, "hole", math.huge)
	if B.bowl then
		B.bowl.halfAt = math.huge
		if instant then
			scarHole(B.bowl, center, bowlR, depth)
		else
			local bowl = B.bowl
			for i, k in ipairs({ 0.45, 0.75, 1 }) do
				task.delay((i - 1) * 0.35, function()
					if B.bowl == bowl then
						scarHole(bowl, center, bowlR * k, depth * k)
						burst(center + V3(0, 1, 0), WORM_SAND, 20, 18, 3, 1, true)
					end
				end)
			end
		end
	end
	local bottom = center.Y - depth
	local deep = newPart("SinkholeDeep", Enum.PartType.Cylinder, RGB(24, 17, 10), Enum.Material.SmoothPlastic, instant and 0 or 1)
	placeDisc(deep, V3(center.X, bottom + 0.2, center.Z), (W.PitRadius or 8) * 2, 0.1)
	local pour = newPart("SinkholePour", nil, WORM_SAND, nil, 1)
	pour.Size = V3(bowlR * 1.6, 1, bowlR * 1.6)
	pour.CFrame = CFrame.new(center + V3(0, 1.5, 0))
	local e = wormEmitter("Pour", pour, {
		Color = ColorSequence.new(WORM_SAND),
		LightInfluence = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 6) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1.5, 2.5),
		Speed = NumberRange.new(1, 3),
		Acceleration = V3(0, -6, 0),
		EmissionDirection = Enum.NormalId.Bottom,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	})
	e.Rate = 16
	B.crater = { deep, pour }
	-- the whirlpool: three arms of pale sand spiralling down the sides of the
	-- bowl into the pit (stepWormSenses turns them, and drags you in)
	B.vortex = { center = center, radius = bowlR, depth = depth, arms = {} }
	for arm = 0, 2 do
		for j = 0, 7 do
			local streak = newPart("VortexStreak", nil, WORM_SAND:Lerp(RGB(255, 240, 210), 0.35 - j * 0.03), Enum.Material.Sand, 0.1)
			table.insert(B.vortex.arms, { part = streak, arm = arm, j = j })
			table.insert(B.crater, streak)
		end
	end
	if not instant then
		-- the stone goes, then the floor gives way under it in a cloud of sand
		burst(center + V3(0, 1, 0), WORM_SAND, 50, 30, 4, 1.4, true)
		tween(deep, 1.4, { Transparency = 0 })
	end
end

-- The sandstorm in the dunes (ArenaAmbience draws it from the arena's Storm
-- attribute): a breeze while the worm sleeps (0.35), a sandstorm the moment
-- it wakes (0.92), and howling once its armour is gone (1).
local function stepStorm(B, dt)
	local arena = arenaOf(B)
	if not arena then
		return
	end
	local state = B.model:GetAttribute("State")
	-- (a lighter storm than it was: you can see the fight, and your screen
	-- has far less to draw)
	local want = 0.2
	if state == "Waking" or state == "Fighting" or state == "Transition" then
		want = B.phase2Look and 0.7 or 0.5
	end
	B.storm = B.storm or (arena:GetAttribute("Storm") or 0.35)
	B.storm = B.storm + (want - B.storm) * math.min(1, dt * 0.6)
	if math.abs((arena:GetAttribute("Storm") or 0) - B.storm) > 0.01 then
		arena:SetAttribute("Storm", B.storm)
	end
end

----------------------------------------------------------------------
-- The shape of each action over time
----------------------------------------------------------------------
-- Every pose starts from breathing (below) and an action reshapes it. t is
-- seconds since the action began on the server.
local Poses = {}

function Poses.Dormant(B, t, P)
	P.sink, P.eyes = 1, 0
	P.sy = 0.9 + 0.05 * math.sin(t * 1.3)
end

function Poses.Wake(B, t, P)
	local W = B.def.WakeTime
	local u = clamp(t / W, 0, 1)
	if u < 0.25 then
		local k = u / 0.25
		P.sink = 1 - 0.2 * k
		P.shake = 0.1 * k
	elseif u < 0.72 then
		local e = easeOutBack((u - 0.25) / 0.47)
		P.sink = clamp(0.8 * (1 - e), 0, 1)
		P.sy = 0.85 + 0.3 * e
		P.sx = 1.25 - 0.28 * e
		P.sz = P.sx
	else
		local w = spring((u - 0.72) * W, 4, 14)
		P.sink = 0
		P.sy = 1 + 0.12 * w
		P.sx = 1 - 0.08 * w
		P.sz = P.sx
	end
	P.eyes = clamp((u - 0.55) / 0.08, 0, 1)
	if u > 0.6 and u < 0.88 then
		P.mouth = math.sin((u - 0.6) / 0.28 * math.pi) -- the roar
		P.shake = math.max(P.shake, 0.35 * P.mouth)
		P.flare = P.mouth
	end
	if PIXEL then
		-- 8-bit: it heaves up out of the pool in chunky steps, like a sprite
		P.sink = math.floor(P.sink * 10 + 0.5) / 10
		P.sy = math.floor(P.sy * 16 + 0.5) / 16
		P.sx = math.floor(P.sx * 16 + 0.5) / 16
		P.sz = P.sx
	end
end

function Poses.Reset(B, t, P)
	if B.kind == "Worm" and B.resetUnder then
		P.sink, P.eyes = 1, 0 -- it was already under the sand: it just stays there
		return
	end
	local u = clamp(t / 2, 0, 1)
	P.sink = smooth(u)
	P.eyes = 1 - clamp(u * 2, 0, 1)
	P.sy = 1 + 0.08 * spring(t, 3, 12)
	if PIXEL and B.kind ~= "Worm" then
		P.sink = math.floor(P.sink * 10 + 0.5) / 10 -- (sinking back down in steps too)
	end
end

function Poses.Slam(B, t, P)
	local a = B.def.Attacks.Slam
	local T = a.Tell
	local D = B.def.Size
	if t < T - 0.08 then
		local k = clamp(t / (T - 0.08), 0, 1)
		local e = easeOut(math.min(k / 0.8, 1))
		P.lift = a.Rise * e
		P.sy, P.sx = 1 + 0.26 * e, 1 - 0.13 * e
		P.sz = P.sx
		if k > 0.8 then -- hanging at the top: here it comes
			local w = (k - 0.8) / 0.2
			P.sy = P.sy + 0.05 * math.sin(w * math.pi * 3)
			P.shake = 0.12 * w
		end
		P.shadowD = lerp(D * 0.95, a.Radius * 2, e)
		P.shadowDark = e
	elseif t < T then
		local k = (t - (T - 0.08)) / 0.08
		P.lift = a.Rise * (1 - k * k)
		P.sy, P.sx = 1.3, 0.84
		P.sz = P.sx
		P.shadowD, P.shadowDark = a.Radius * 2, 1
	else
		local w = spring(t - T, 5, 13)
		P.sy, P.sx = 1 - 0.42 * w, 1 + 0.36 * w
		P.sz = P.sx
		P.shadowD = lerp(D * 0.95, a.Radius * 2, clamp(1 - (t - T) / 0.3, 0, 1))
	end
end

function Poses.Wave(B, t, P)
	local a = B.def.Attacks.Wave
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		P.sy, P.sx = 1 - 0.36 * k, 1 + 0.28 * k
		P.sz = P.sx
		if t > a.Tell * 0.7 then
			P.shake = 0.15 * (t - a.Tell * 0.7) / (a.Tell * 0.3)
		end
	else
		local w = spring(t - a.Tell, 4.5, 11)
		P.sy, P.sx = 1 + 0.3 * w, 1 - 0.2 * w
		P.sz = P.sx
	end
end

function Poses.Spit(B, t, P)
	local a = B.def.Attacks.Spit
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		P.sx, P.sy = 1 + 0.1 * k, 1 + 0.12 * k
		P.sz = P.sx
		P.mouth, P.lean = 0.45 * k, -0.1 * k
		return
	end
	local last = a.Tell + (a.Globs - 1) * a.Gap
	local settle = clamp((t - last - 0.25) / 0.5, 0, 1)
	P.sx, P.sy = lerp(1.1, 1, settle), lerp(1.12, 1, settle)
	P.sz = P.sx
	P.mouth, P.lean = lerp(0.45, 0, settle), lerp(-0.1, 0, settle)
	for i = 1, a.Globs do
		local d = t - (a.Tell + (i - 1) * a.Gap)
		if d >= 0 and d < 0.22 then
			local pulse = math.sin(d / 0.22 * math.pi)
			P.mouth = 0.45 + 0.55 * pulse
			P.lean = -0.1 + 0.3 * pulse
			P.sz = P.sz - 0.12 * pulse
		end
	end
end

function Poses.Lunge(B, t, P)
	local a = B.def.Attacks.Lunge
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		P.lean = -0.38 * k
		P.sy, P.sx = 1 + 0.14 * k, 1 - 0.07 * k
		if t > a.Tell * 0.75 then -- crouches to spring
			local c = (t - a.Tell * 0.75) / (a.Tell * 0.25)
			P.sy = P.sy - 0.24 * c
			P.sx = P.sx + 0.1 * c
		end
		P.sz = P.sx
		return
	end
	local m = B.model
	local from, to, travel = m:GetAttribute("ActA"), m:GetAttribute("ActB"), m:GetAttribute("ActN")
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" or not travel then
		P.lean = -0.38 -- committed, waiting to hear where to
		return
	end
	local u = clamp((t - a.Tell) / travel, 0, 1)
	if u < 1 then
		P.override = from:Lerp(to, u)
		P.lift = 5.5 * math.sin(math.pi * u)
		P.sz, P.sy, P.sx, P.lean = 1.34, 0.8, 0.94, 0.24
		P.shadowD = B.def.Size * 0.9
	else
		local w = spring(t - a.Tell - travel, 5, 13)
		P.sy, P.sx = 1 - 0.4 * w, 1 + 0.34 * w
		P.sz = P.sx
	end
end

function Poses.TripleSlam(B, t, P)
	local a = B.def.Attacks.TripleSlam
	local m = B.model
	local spots = { m:GetAttribute("ActA"), m:GetAttribute("ActB"), m:GetAttribute("ActC") }
	local D = B.def.Size
	if t < a.Tell - 0.07 then
		local e = easeOut(clamp(t / (a.Tell - 0.07) / 0.8, 0, 1))
		P.lift = a.Rise * e
		P.sy, P.sx = 1 + 0.24 * e, 1 - 0.12 * e
		P.sz = P.sx
		P.shadowD, P.shadowDark = lerp(D * 0.95, a.Radii[1] * 2, e), e
		P.shake = 0.1 * e
		return
	elseif t < a.Tell then
		local k = (t - (a.Tell - 0.07)) / 0.07
		P.lift = a.Rise * (1 - k * k)
		P.sy, P.sx = 1.28, 0.86
		P.sz = P.sx
		P.shadowD, P.shadowDark = a.Radii[1] * 2, 1
		return
	end
	local k = t - a.Tell
	local hop = math.floor(k / a.Gap) + 2
	if hop <= 3 then
		local u = clamp((k - (hop - 2) * a.Gap) / a.Gap, 0, 1)
		local from, to = spots[hop - 1], spots[hop]
		if typeof(from) == "Vector3" and typeof(to) == "Vector3" then
			P.override = from:Lerp(to, smooth(u))
		end
		-- up fast, a beat at the top, down hard
		local h = u < 0.7 and easeOut(u / 0.7) or (1 - ((u - 0.7) / 0.3) ^ 2)
		P.lift = a.Rise * 0.85 * h
		local land = spring(k - (hop - 2) * a.Gap, 7, 16) * (u < 0.3 and 1 or 0)
		P.sy, P.sx = 1 + 0.2 * h - 0.4 * land, 1 - 0.1 * h + 0.34 * land
		P.sz = P.sx
		P.shadowD = lerp(D * 0.95, a.Radii[hop] * 2, h)
		P.shadowDark = h
	else
		local w = spring(k - 2 * a.Gap, 5, 13)
		P.sy, P.sx = 1 - 0.42 * w, 1 + 0.36 * w
		P.sz = P.sx
	end
end

function Poses.Wail(B, t, P)
	local a = B.def.Attacks.Wail
	if t < a.Tell then
		local k = smooth(t / a.Tell)
		P.sx, P.sy = 1 - 0.12 * k, 1 - 0.1 * k
		P.sz = P.sx
		P.mouth, P.shake, P.flare = k, 0.3 * k, k
		return
	end
	local k = t - a.Tell
	local total = (a.Rings - 1) * a.Gap + a.Fuse
	if k < total then
		P.mouth, P.shake, P.flare = 1, 0.28, 1
		P.sx, P.sy = 0.88, 0.9 + 0.05 * math.sin(k * 20)
		P.sz = P.sx
	else
		local s = clamp((k - total) / 0.5, 0, 1)
		P.mouth, P.flare = 1 - s, 1 - s
		P.sx, P.sy = lerp(0.88, 1, s), lerp(0.9, 1, s)
		P.sz = P.sx
	end
end

function Poses.Break(B, t, P)
	local BT = B.def.BreakTime
	if B.kind == "Worm" then
		if t < BT * 0.35 then
			-- rears back, shuddering, the glow building up behind its armour
			local k = t / (BT * 0.35)
			P.lean, P.lift, P.shake, P.flare, P.mouth = -0.4 * smooth(k), 6 * smooth(k), 0.45 * k, k, 0.5 * k
			P.coreScale = 1 + 0.3 * k
		else
			-- the plates blow off and it screams
			local k = t - BT * 0.35
			P.lean = -0.4 * math.max(0, 1 - k * 1.5) + 0.25 * spring(k, 3, 9)
			P.lift = 6 * math.max(0, 1 - k * 2)
			P.mouth = clamp(1 - (k - 0.6) / 0.8, 0, 1)
			P.flare = clamp(1 - k * 0.6, 0, 1)
			P.shake = 0.3 * math.max(0, 1 - k)
		end
		return
	end
	if t < BT * 0.35 then
		local k = t / (BT * 0.35)
		local w = math.sin(t * 50)
		P.sx, P.sy = 1 + 0.12 * k * w, 1 - 0.1 * k * w
		P.sz = P.sx
		P.shake, P.flare, P.mouth = 0.5 * k, k, 0.6 * k
		P.coreScale = 1 + 0.25 * k
	else
		local k = t - BT * 0.35
		local w = spring(k, 3, 10)
		P.sx, P.sy = 1 + 0.35 * w, 1 - 0.3 * w
		P.sz = P.sx
		P.mouth = clamp(1 - k, 0, 1)
		P.flare = clamp(1 - k * 0.8, 0, 1)
	end
end

function Poses.Death(B, t, P)
	if B.kind == "Worm" then
		if t < 0.6 then
			-- one last scream at the sky
			P.shake, P.flare, P.mouth = 0.5, 1, 1
			P.eyes = (t % 0.12 < 0.06) and 1 or 0
			P.lean, P.lift = -0.4 * smooth(t / 0.6), 5 * smooth(t / 0.6)
		elseif t < 2.2 then
			-- then it topples, faster and faster, and crashes down across the sand
			local k = (t - 0.6) / 1.6
			local e = k * k
			P.lean = lerp(-0.4, 1.7, e)
			P.lift = 5 * (1 - k)
			P.sy = 1 - 0.35 * e
			P.mouth = 1 - k
			P.eyes = 0
			P.coreScale = lerp(1.3, 0.3, k)
		else
			-- and the dunes take it back
			local k = clamp((t - 2.2) / 2.2, 0, 1)
			P.lean, P.sy, P.eyes = 1.7, 0.65 - 0.1 * k, 0
			P.coreScale = 0.01
			P.sink = smooth(k) * 0.9
			P.fade = clamp((t - 2.6) / 2, 0, 1)
		end
		return
	end
	if t < 0.5 then
		P.shake, P.flare = 0.4, 1
		P.eyes = (t % 0.12 < 0.06) and 1 or 0 -- the light going out
		P.mouth = 0.7
	elseif t < 2.4 then
		local k = (t - 0.5) / 1.9
		local e = k * k
		P.sy, P.sx = 1 - 0.88 * e, 1 + 0.55 * k
		P.sz = P.sx
		P.eyes, P.mouth = 0, 0.7 * (1 - k)
		P.fade = clamp(k * 0.75, 0, 1)
		P.coreScale = t < 1.2 and (1 + (t - 0.5)) or 0.01
	else
		P.sy, P.sx = 0.12, 1.55
		P.sz = P.sx
		P.eyes = 0
		P.coreScale = 0.01
		P.fade = clamp(0.75 + (t - 2.4) / 1.6 * 0.25, 0, 1)
	end
end

----------------------------------------------------------------------
-- One-off moments in each action (sounds, landings, telegraphs)
----------------------------------------------------------------------
local function at(B, when, fn)
	table.insert(B.events, { at = when, fn = fn })
end

local Starts = {}

function Starts.Wake(B, t0)
	-- the roar's sound starts a little before the roar itself: your Wake sound
	-- has a build-up, so started on the moment it sounded late
	at(B, t0 + B.def.WakeTime * 0.62 - (B.def.WakeSoundLead or 0.5), function()
		playSound(B.def, "Wake", B.vpos, 1)
	end)
	at(B, t0 + B.def.WakeTime * 0.62, function()
		kick(B.vpos, 30, 0.9, -3)
		burst(B.vpos + V3(0, 2, 0), B.fx.color, 30, 26, 2.4, 0.9, true)
	end)
	at(B, t0 + B.def.WakeTime * 0.3, function()
		burst(B.vpos + V3(0, 1, 0), B.fx.color, 18, 14, 2, 0.8, true)
	end)
	if B.kind == "Worm" then
		-- the ground shakes first, then the sand explodes as it breaks the surface
		at(B, t0 + 0.1, function()
			kick(B.vpos, 60, 0.35)
		end)
		at(B, t0 + B.def.WakeTime * 0.27, function()
			burst(B.vpos + V3(0, 1, 0), WORM_SAND, 50, 40, 3.4, 1.3, true)
			burst(B.vpos + V3(0, 0.5, 0), WORM_SAND_DEEP, 24, 26, 2.4, 0.9)
			shockRing(B, B.vpos, B.def.Size / 2, B.def.Size * 1.4, 0.5, WORM_SAND)
			kick(B.vpos, 45, 1.1, -4)
		end)
	end
end

function Starts.Slam(B, t0)
	local a = B.def.Attacks.Slam
	at(B, t0 + a.Tell, function()
		shockRing(B, B.vpos, B.def.Size / 2, a.Radius * 1.15, 0.35)
		burst(B.vpos + V3(0, 0.6, 0), B.fx.color, 36, 34, 2, 0.6)
		playSound(B.def, "Slam", B.vpos, 1)
		kick(B.vpos, a.Radius, 1.1, -4)
	end)
end

function Starts.Wave(B, t0)
	local a = B.def.Attacks.Wave
	at(B, t0 + a.Tell, function()
		local origin = B.model:GetAttribute("ActA")
		waveRing(B, typeof(origin) == "Vector3" and origin or B.vpos, t0 + a.Tell)
		burst(B.vpos + V3(0, 0.6, 0), B.fx.color, 24, 26, 1.6, 0.5)
		playSound(B.def, "Wave", B.vpos, 1)
		kick(B.vpos, 20, 0.5)
	end)
end

function Starts.Spit(B, t0)
	at(B, t0 + 0.05, function()
		playSound(B.def, "Spit", B.vpos, 0.6)
	end)
end

function Starts.Lunge(B, t0)
	local a = B.def.Attacks.Lunge
	at(B, t0 + a.Tell, function()
		playSound(B.def, "Lunge", B.vpos, 1)
		burst(B.vpos + V3(0, 0.4, 0), RGB(170, 170, 160), 16, 16, 1.6, 0.5)
	end)
end

function Starts.TripleSlam(B, t0)
	local a = B.def.Attacks.TripleSlam
	for i = 1, 3 do
		at(B, t0 + a.Tell + (i - 1) * a.Gap, function()
			local spot = B.model:GetAttribute(SLOT_NAMES[i])
			spot = typeof(spot) == "Vector3" and spot or B.vpos
			shockRing(B, spot, B.def.Size / 2, a.Radii[i] * 1.15, 0.3)
			burst(spot + V3(0, 0.6, 0), B.fx.color, 26, 30, 1.8, 0.5)
			playSound(B.def, "Slam", spot, 0.9)
			kick(spot, a.Radii[i], 0.9, -3)
		end)
	end
end

function Starts.Wail(B, t0)
	at(B, t0 + 0.05, function()
		playSound(B.def, "Wail", B.vpos, 1)
	end)
end

function Starts.Break(B, t0)
	local def = B.def
	if B.kind == "Worm" then
		at(B, t0 + def.BreakTime * 0.35, function()
			B.phase2Look = true
			shatterPlates(B)
			collapseSeal(B, true)
			shockRing(B, B.vpos, def.Size / 2, def.BreakReach, 0.55, WORM_SAND)
			burst(B.vpos + V3(0, def.Size, 0), def.HeartColor or WORM_SAND, 40, 36, 2.4, 0.9, true)
			burst(B.vpos + V3(0, 1, 0), WORM_SAND, 44, 40, 3.2, 1.1, true)
			playSound(def, "Break", B.vpos, 1)
			kick(B.vpos, def.BreakReach, 1.4, -5)
		end)
		return
	end
	at(B, t0 + def.BreakTime * 0.35, function()
		B.phase2Look = true
		shatterCrown(B, B.vpos)
		shockRing(B, B.vpos, def.Size / 2, def.BreakReach, 0.55)
		burst(B.vpos + V3(0, def.Size * 0.5, 0), B.fx.color, 50, 40, 2.6, 1, true)
		playSound(def, "Break", B.vpos, 1)
		kick(B.vpos, def.BreakReach, 1.3, -5)
	end)
end

function Starts.Death(B, t0)
	local def = B.def
	at(B, t0 + 0.5, function()
		playSound(def, "Death", B.vpos, 1)
		-- ash rising off it as it goes
		local holder = newPart("Ashes", nil, def.Color, nil, 1)
		holder.Size = V3(def.Size, 2, def.Size)
		holder.CFrame = CFrame.new(B.vpos + V3(0, 3, 0))
		local e = Instance.new("ParticleEmitter")
		if B.kind == "Worm" then
			-- a worm doesn't go up in sparks: it crumbles to sand
			e.Texture = "rbxasset://textures/particles/smoke_main.dds"
			e.Color = ColorSequence.new(WORM_SAND, def.DeepColor)
			e.LightEmission = 0.05
		else
			e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			e.Color = ColorSequence.new(def.EyeColor, def.Color)
			e.LightEmission = 0.9
		end
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(1.2, 2.4)
		e.Rate = 90
		e.Speed = NumberRange.new(2, 6)
		e.Acceleration = V3(0, 9, 0)
		e.SpreadAngle = Vector2.new(50, 50)
		e.Shape = Enum.ParticleEmitterShape.Box
		e.Parent = holder
		task.delay(2.2, function()
			e.Enabled = false
		end)
		task.delay(5, function()
			holder:Destroy()
		end)
	end)
	at(B, t0 + 1.2, function()
		burst(B.vpos + V3(0, 3, 0), def.CoreColor, 24, 18, 2, 0.9, true) -- the core bursts
		kick(B.vpos, 20, 0.7, -2)
	end)
	if B.kind == "Worm" then
		-- its head hits the sand
		at(B, t0 + 2.1, function()
			local spot = B.mawPos and V3(B.mawPos.X, B.vpos.Y, B.mawPos.Z) or (B.vpos + B.vfacing * def.Size)
			burst(spot + V3(0, 1, 0), WORM_SAND, 50, 34, 3.4, 1.2, true)
			shockRing(B, spot, def.Size / 2, def.Size * 1.6, 0.5, WORM_SAND)
			playSound(def, "Slam", spot, 1)
			kick(spot, 40, 1.3, -4)
		end)
	end
end

-- Telegraphs that depend on positions the server fills in as it goes.
local SlotSpawns = {}

function SlotSpawns.Spit(B, i, spot, t0)
	local a = B.def.Attacks.Spit
	local mouth = B.mawPos or (B.vpos + V3(0, B.def.Size * 0.4, 0) + (B.vfacing * B.def.Size * 0.45))
	glob(B, mouth, spot, t0 + a.Tell + (i - 1) * a.Gap)
end

function SlotSpawns.Wail(B, i, spot, t0)
	local a = B.def.Attacks.Wail
	wailRing(B, spot, t0 + a.Tell + (i - 1) * a.Gap)
end

-- (Everything Mireworm draws lives in this one block: a Roblox script may only
-- have 200 names at its top level, so only the handful used further down are
-- shared - the rest stay inside.)
local trailReset, trailRecord, stepHumps, stepWormSenses, pushOutOfWorm, glideWorm
do
	----------------------------------------------------------------------
	-- MIREWORM: the hunt, as your screen sees it
	----------------------------------------------------------------------
	-- BossService decides everything - where it swims, when each attack lands,
	-- who it hits. This draws it all from the same server clock: its back arching
	-- out of the sand as it swims, the sand it tears up, every warning, the rumble
	-- when it's close and the platforms breaking. None of
	-- Gloomgut's drawing above is used for it, and none of this is used for Gloomgut.
	local WORM_GLOW = RGB(255, 150, 70) -- warnings of something coming up from below
	local LOCKED = RGB(255, 60, 40) -- a breach that has stopped following you
	local STONE_BITS = { RGB(214, 172, 114), RGB(178, 134, 86), RGB(146, 102, 64) } -- the platforms' sandstone
	local SAND_BITS = { WORM_SAND, RGB(204, 166, 108), WORM_SAND_DEEP }

	-- How it swims: it follows the path its head took, under the sand, and every
	-- so often its back arches up out of the sand - the head first, then the body
	-- threading through the same arch - like a sea serpent.
	local BODY_LEN = 100 -- nose to tail, when it swims
	local HUMP_LEN = 38 -- one arch of its back
	local HUMP_EVERY = 62 -- studs it swims between arches (some attacks arch more often)
	local TRAIL_KEEP = BODY_LEN + HUMP_LEN + 60

	-- a spot on the sand, a hair above it: the markings on the floor sit on top
	-- of the Terrain sand rather than half inside its surface
	local function onSand(p)
		local f = onFloor(p)
		return V3(f.X, f.Y + 0.1, f.Z)
	end

	-- a bar lying flat on the floor from a to b
	local function placeStrip(p, a, b, width, thickness, y)
		local run = flat(b - a)
		local len = run.Magnitude
		local mid = (a + b) / 2
		local c = V3(mid.X, y or mid.Y, mid.Z)
		Fast.size(p, V3(width, thickness or 0.12, math.max(len, 0.05)), 0.05)
		if len > 0.05 then
			p.CFrame = CFrame.lookAt(c, c + run)
		else
			p.CFrame = CFrame.new(c)
		end
	end

	-- a bar from a to b, following them up and down (down the side of a pit)
	local function placeBar(p, a, b, width, thickness)
		local len = (b - a).Magnitude
		Fast.size(p, V3(width, thickness or 0.12, math.max(len, 0.05)), 0.05)
		if len > 0.05 then
			p.CFrame = CFrame.lookAt((a + b) / 2, b)
		else
			p.CFrame = CFrame.new((a + b) / 2)
		end
	end

	local function hideRing(ring)
		for _, p in ipairs(ring.parts) do
			p.Transparency = 1
		end
	end

	-- the point on the segment a-b nearest to p
	local function nearestOnSegment(a, b, p)
		local ab = flat(b - a)
		local len = ab.Magnitude
		if len < 0.01 then
			return a
		end
		return a + ab.Unit * clamp(flat(p - a):Dot(ab.Unit), 0, len)
	end

	local function myFloorPos(B)
		local hrp = myRoot()
		return hrp and hrp.Position or B.vpos
	end

	-- a steady "random" number from a seed, so every screen picks the same one
	local function seeded(n)
		local x = math.sin(n * 12.9898) * 43758.5453
		return x - math.floor(x)
	end

	-- Drags YOUR character toward `center` (the devour's sinkhole, the whirlpool).
	-- Only on sand, only with your feet on the ground, and never faster than you
	-- can run: running outward always gets you out, it just takes longer - and
	-- a roll (in the air) slips free.
	local function dragMe(B, center, radius, edgeSpeed, centreSpeed, dt)
		local hrp = myRoot()
		if not hrp or player:GetAttribute("SpireFloor") ~= B.floor then
			return
		end
		local off = flat(center - hrp.Position)
		local d = off.Magnitude
		if d > radius or d < 0.6 or onStone(B, hrp.Position) then
			return
		end
		local hum = hrp.Parent and hrp.Parent:FindFirstChildOfClass("Humanoid")
		if hum and hum.FloorMaterial == Enum.Material.Air then
			return
		end
		local speed = lerp(edgeSpeed, centreSpeed, 1 - d / radius)
		hrp.CFrame = hrp.CFrame + off.Unit * math.min(speed * dt, d)
	end

	-- Chunks thrown up and out, bouncing to a stop and fading (only on your screen)
	local function flingRubble(center, count, colors, speedScale)
		colors = colors or STONE_BITS
		local bits = {}
		count = math.max(3, math.floor(count * 0.6))
		for i = 1, count do
			local p = newPart("Rubble", nil, colors[(i % #colors) + 1], Enum.Material.Sandstone, 0)
			p.Size = V3(1 + math.random() * 2.6, 0.8 + math.random() * 1.6, 1 + math.random() * 2.6)
			local ang = math.random() * math.pi * 2
			local speed = (8 + math.random() * 16) * (speedScale or 1)
			bits[i] = {
				part = p,
				pos = center + V3((math.random() - 0.5) * 8, 1, (math.random() - 0.5) * 8),
				vel = V3(math.cos(ang) * speed, (22 + math.random() * 20) * (speedScale or 1), math.sin(ang) * speed),
				spin = V3(math.random(), math.random(), math.random()) * 6,
			}
		end
		local t0 = os.clock()
		local conn
		local settled = false
		conn = RunService.RenderStepped:Connect(function(dt)
			local e = os.clock() - t0
			-- (once every chunk has landed and stopped, there's nothing to move)
			if not settled then
				local parts, cframes = {}, {}
				settled = true
				for k, b in ipairs(bits) do
					if not b.still then
						b.vel = b.vel + V3(0, -60 * dt, 0)
						b.pos = b.pos + b.vel * dt
						b.age = e
						if b.pos.Y < center.Y + 0.5 then
							b.pos = V3(b.pos.X, center.Y + 0.5, b.pos.Z)
							b.vel = V3(b.vel.X * 0.4, 0, b.vel.Z * 0.4)
							b.still = b.vel.Magnitude < 1.5
						end
						settled = false
						parts[#parts + 1] = b.part
						cframes[#cframes + 1] = CFrame.new(b.pos) * CFrame.Angles(b.spin.X * b.age, b.spin.Y * b.age, b.spin.Z * b.age)
					end
				end
				if #parts > 0 then
					pcall(function()
						Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
					end)
				end
			end
			if e > 2 then
				local fade = math.floor(clamp((e - 2) / 0.8, 0, 1) * 5) / 5 -- (in five steps)
				for _, b in ipairs(bits) do
					Fast.alpha(b.part, fade)
				end
			end
			if e > 2.8 then
				conn:Disconnect()
				for _, b in ipairs(bits) do
					b.part:Destroy()
				end
			end
		end)
	end

	local function scarLife(B)
		return (B.def.Scars and B.def.Scars.Last) or 7
	end

	----------------------------------------------------------------------
	-- Gliding: smooth movement between what the server sends
	----------------------------------------------------------------------
	-- The server moves it every frame, but your screen only hears about it a
	-- few dozen times a second, a little unevenly. Chasing each update makes it
	-- judder; instead every position is kept with the moment it arrived, and
	-- it's drawn GLIDE seconds behind, sliding steadily between them.
	-- Each position comes stamped with the moment the server put it there
	-- (the "PosT" attribute), so a burst of updates arriving together, or a
	-- slow patch on the connection, can't make it stop and jump. The delay
	-- grows by itself if your updates arrive late, and shrinks again after.
	function glideWorm(B, now, ground)
		if B.model:GetAttribute("State") == "Dormant" then
			B.snaps = nil -- asleep at home: nothing to glide (start afresh when it wakes)
			return ground
		end
		local stamp = B.model:GetAttribute("PosT")
		local snaps = B.snaps
		if not snaps then
			snaps = {}
			B.snaps = snaps
		end
		if type(stamp) ~= "number" then
			return ground -- (an older BossService that doesn't stamp: just follow it)
		end
		local last = snaps[#snaps]
		if not last or stamp > last.t then
			local gap = last and flat(ground - last.p).Magnitude or 0
			if gap > 40 or (gap > 4 and gap / math.max(stamp - last.t, 1 / 240) > 200) then
				-- it jumped on the server (came up somewhere else): faster than it
				-- can ever move, so it's shown as a jump now, not slid across
				table.clear(snaps)
			end
			snaps[#snaps + 1] = { t = stamp, p = ground, o = tonumber(B.model:GetAttribute("Odo")) }
			while #snaps > 40 do
				table.remove(snaps, 1)
			end
			-- how late this update is: the delay needs to cover the latest ones
			local late = now - stamp
			B.glideLate = math.max((B.glideLate or 0.1) * 0.97, late)
		end
		local want = clamp((B.glideLate or 0.1) + 0.05, 0.08, 0.4)
		B.glide = B.glide and (B.glide + (want - B.glide) * math.min(1, 0.05)) or want
		local at = now - B.glide
		if #snaps == 0 then
			return ground
		end
		-- (how far it had swum, on the server, at the moment it's drawn: the
		-- arches of its back are placed by that - see stepHumps)
		if at <= snaps[1].t then
			B.sodo = snaps[1].o
			return snaps[1].p
		end
		for i = #snaps, 2, -1 do
			local a = snaps[i - 1]
			if at >= a.t then
				local b = snaps[i]
				local k = clamp((at - a.t) / math.max(b.t - a.t, 1e-3), 0, 1)
				B.sodo = (a.o and b.o) and a.o + (b.o - a.o) * k or b.o
				return a.p:Lerp(b.p, k)
			end
		end
		B.sodo = snaps[#snaps].o
		return snaps[#snaps].p
	end

	----------------------------------------------------------------------
	-- Swimming under the sand
	----------------------------------------------------------------------
	-- The path its head has taken (recorded every frame), so its body can follow
	-- it exactly, and the arches its back makes out of the sand.
	function trailReset(B)
		B.trail, B.humps = { { odo = B.odo or 0, pos = B.vpos } }, {}
		B.odo = B.odo or 0
	end

	function trailRecord(B)
		local tr = B.trail
		local last = tr[#tr]
		local step = flat(B.vpos - last.pos).Magnitude
		if step < 1 then
			return
		end
		if step > 45 then
			trailReset(B) -- it burst up somewhere else entirely: start the path afresh
			B.trail[1].pos = B.vpos
			return
		end
		B.odo = B.odo + step
		tr[#tr + 1] = { odo = B.odo, pos = B.vpos }
		if #tr > 4 and B.odo - tr[1].odo > TRAIL_KEEP then
			table.remove(tr, 1)
		end
	end

	-- where its head was `back` studs of swimming ago
	local function trailAt(B, back)
		local tr = B.trail
		local want = B.odo - back
		if want >= tr[#tr].odo then
			return tr[#tr].pos
		end
		if want <= tr[1].odo then
			-- further back than it remembers: carry on straight back
			local a, b = tr[1], tr[2]
			local dir = b and flat(a.pos - b.pos) or V3(0, 0, 0)
			dir = dir.Magnitude > 0.01 and dir.Unit or -B.vfacing
			return a.pos + dir * (a.odo - want)
		end
		local lo, hi = 1, #tr
		while hi - lo > 1 do
			local mid = (lo + hi) // 2
			if tr[mid].odo <= want then
				lo = mid
			else
				hi = mid
			end
		end
		local a, b = tr[lo], tr[hi]
		return a.pos:Lerp(b.pos, (want - a.odo) / math.max(b.odo - a.odo, 1e-3))
	end

	-- how far its back is lifted out of the sand at a point of its path (0..1)
	local function humpLift(B, odo)
		local lift = 0
		for _, h in ipairs(B.humps) do
			local x = (odo - h.o) / HUMP_LEN
			if x > 0 and x < 1 then
				lift = math.max(lift, math.sin(x * math.pi))
			end
		end
		return lift
	end

	-- its body under the sand, along its path, arching out where the humps are
	local function underPath(B)
		local g = B.def.Size * 0.64
		local baseY = B.vpos.Y - g * 1.1
		local rise = g * 1.2
		return function(s)
			local back = (1 - s) * BODY_LEN
			local p = trailAt(B, back)
			return V3(p.X, baseY + humpLift(B, B.odo - back) * rise, p.Z)
		end
	end

	-- The pose for anything it does under the sand. spray = the sand thrown up
	-- over its head; every = how often its back arches out (nil: it doesn't).
	local function underPose(B, P, spray, every)
		P.path = underPath(B)
		P.sink, P.ridge, P.eyes = 1, spray or 1, 1
		P.noShadow, P.noPush = true, true
		B.humpEvery = every
	end

	-- New arches as it swims, old ones gone once its tail is through them, and
	-- sand pouring off its back where it breaks the surface.
	-- Where the arches of its back come up is BossService's to decide (it's
	-- where you can hit it: see bodyNear there) - its "Humps", in how far it
	-- has swum - so every screen draws them in the same place.
	local OWN_HUMPS = {} -- (none now: BossService places every arch)
	function stepHumps(B)
		local list = B.model:GetAttribute("Humps")
		if type(list) == "string" and B.sodo and not OWN_HUMPS[B.action] then
			-- (its odometer on your screen vs the server's - eased, so the arches
			-- sit still instead of shivering by a stud as your screen counts)
			local shift = B.odo - B.sodo
			if not B.humpShift or math.abs(shift - B.humpShift) > 8 then
				B.humpShift = shift
			end
			B.humpShift = B.humpShift + (shift - B.humpShift) * 0.1
			shift = B.humpShift
			local humps = {}
			for h in string.gmatch(list, "[^,]+") do
				local o = tonumber(h)
				if o then
					humps[#humps + 1] = { o = o + shift }
				end
			end
			B.humps = humps
			B.lastHump = B.odo
		else
			if B.fromServer then
				B.humps = {} -- (its own arches from here, starting clean)
			end
			local humps = B.humps
			for i = #humps, 1, -1 do
				if B.odo - humps[i].o > BODY_LEN + HUMP_LEN then
					table.remove(humps, i)
				end
			end
			if B.humpEvery and B.odo - (B.lastHump or -math.huge) >= B.humpEvery then
				B.lastHump = B.odo
				table.insert(humps, { o = B.odo + 1 })
			end
		end
		B.fromServer = type(list) == "string" and B.sodo ~= nil and not OWN_HUMPS[B.action]
		local humps = B.humps
		if not B.humpDust then
			B.humpDust = {}
			for i = 1, 4 do
				local holder = newPart("HumpDust", nil, WORM_SAND, nil, 1, B.body.folder)
				holder.Size = V3(7, 1, 7)
				B.humpDust[i] = {
					holder = holder,
					emitter = wormEmitter("Pour", holder, {
						Color = ColorSequence.new(WORM_SAND),
						LightInfluence = 1,
						Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 4.5) }),
						Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
						Lifetime = NumberRange.new(0.8, 1.4),
						Speed = NumberRange.new(6, 15),
						SpreadAngle = Vector2.new(35, 35),
						Acceleration = V3(0, -40, 0),
						EmissionDirection = Enum.NormalId.Top,
						Shape = Enum.ParticleEmitterShape.Box,
						ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
					}),
				}
			end
		end
		-- where the two newest arches go into and come out of the sand
		local k = 0
		for i = #humps, math.max(1, #humps - 1), -1 do
			local h = humps[i]
			for _, w in ipairs({ h.o, h.o + HUMP_LEN }) do
				k = k + 1
				local d = B.humpDust[k]
				local covered = w <= B.odo and w >= B.odo - BODY_LEN -- some of its body is passing here
				if covered then
					local p = trailAt(B, B.odo - w)
					d.holder.CFrame = CFrame.new(V3(p.X, B.vpos.Y + 0.5, p.Z))
					d.emitter.Rate = 16
				else
					d.emitter.Rate = 0
				end
			end
		end
		for j = k + 1, 4 do
			B.humpDust[j].emitter.Rate = 0
		end
	end

	----------------------------------------------------------------------
	-- Its body in its other shapes
	----------------------------------------------------------------------
	-- Coiled round its quarry like a snake: the tail goes down into the sand off
	-- the start of the ring, its body runs all the way round (half sunk in the
	-- sand), and its neck climbs from the end of the ring up over the middle, the
	-- head looking down at whoever is inside. `down` sinks the whole coil.
	local function coilPath(C, r, g, headUp, rise, thEnd, down)
		down = down or 0
		local ringY = C.Y + g * 0.18 * rise - g * 1.1 * (1 - rise) - down
		local endP = V3(C.X + math.sin(thEnd) * r, ringY, C.Z + math.cos(thEnd) * r)
		local headP = V3(C.X, C.Y + headUp - down, C.Z)
		local ctrl = V3(C.X + math.sin(thEnd) * r * 0.55, C.Y + headUp * 1.15 + g * 0.3 - down, C.Z + math.cos(thEnd) * r * 0.55)
		local neck = (headP - endP).Magnitude * 1.15
		local ring = 2 * math.pi * r * 0.94
		local total = neck + ring + 24
		local th0 = thEnd - ring / r
		local startP = V3(C.X + math.sin(th0) * r, ringY, C.Z + math.cos(th0) * r)
		local onward = V3(-math.cos(th0), 0, math.sin(th0)) -- on round the way the ring runs
		return function(s)
			local d = (1 - s) * total -- distance back from its head
			if d <= neck then
				local q = d / neck
				local w = 1 - q
				return headP * (w * w) + ctrl * (2 * w * q) + endP * (q * q)
			end
			d = d - neck
			if d <= ring then
				local th = thEnd - d / r
				return V3(C.X + math.sin(th) * r, ringY, C.Z + math.cos(th) * r)
			end
			d = d - ring
			return startP + onward * (d * 0.5) + V3(0, -d * 0.9, 0)
		end
	end

	----------------------------------------------------------------------
	-- Warnings in the world (each is a telegraph: update(now) -> keep going?)
	----------------------------------------------------------------------
	-- AMBUSH: the ground heaves up under you in shoves (real sand: you feel it
	-- lift you), ringed in glowing warning, and then it bursts up out of it.
	local function ambushMark(B, spot, eruptAt)
		local a = B.def.Attacks.Ambush
		spot = onSand(spot)
		local t0 = serverNow()
		local ring = newRing(26, WORM_GLOW, Enum.Material.Neon, 1)
		local heave = newScar(B, "heave", math.max(eruptAt - t0, 0.1))
		local shoves = { 0.2, 0.5, 0.8 }
		local done = 0
		addTelegraph(B, {
			update = function(now)
				if now >= eruptAt then
					return false
				end
				local u = clamp((now - t0) / math.max(eruptAt - t0, 0.05), 0, 1)
				while done < #shoves and u >= shoves[done + 1] do
					done = done + 1
					scarHeave(heave, spot, a.Radius * (0.55 + 0.2 * done), 1.2 * done)
					burst(spot + V3(0, 1.2 * done, 0), WORM_SAND, 10, 10, 1.8, 0.6, true)
				end
				local pulse = 0.5 + 0.5 * math.sin(now * lerp(12, 32, u))
				placeRing(ring, spot + V3(0, 0.08, 0), a.Radius + 0.5, 0.3, 0.55, lerp(0.7, 0.05, u * pulse))
				return true
			end,
			cleanup = function()
				removeRing(ring)
			end,
		})
	end

	-- BREACH: the strip its body will come down on. While it's in the air the
	-- strip FOLLOWS YOU (the server keeps re-aiming it); when it stops following
	-- (Lock), it flashes red - that's your moment to roll. It bursts out of a
	-- crater, and where it lands its body carves a trench.
	local function breachStrip(B, t0, tell)
		local a = B.def.Attacks.Breach
		local m = B.model
		local A = m:GetAttribute("ActA")
		if typeof(A) ~= "Vector3" then
			return
		end
		A = onSand(A)
		local launchAt = t0 + tell
		local landAt = launchAt + a.Flight
		local lockAt = launchAt + a.Flight * a.Lock
		local strip = newPart("BreachStrip", nil, WORM_SAND_DEEP, Enum.Material.Sand, 1)
		local edges = { newPart("BreachEdge", nil, WORM_GLOW, Enum.Material.Neon, 1), newPart("BreachEdge", nil, WORM_GLOW, Enum.Material.Neon, 1) }
		local launch = newRing(24, WORM_GLOW, Enum.Material.Neon, 1)
		local shadow = newPart("BreachShadow", Enum.PartType.Cylinder, RGB(40, 28, 16), Enum.Material.SmoothPlastic, 1)
		local launched, locked, landed = false, false, false
		local Bp = nil
		addTelegraph(B, {
			update = function(now)
				if now > landAt + 0.25 then
					return false
				end
				if not landed then
					local live = m:GetAttribute("ActB")
					if typeof(live) == "Vector3" and m:GetAttribute("Action") == "Breach" then
						Bp = onSand(live)
					end
				end
				if not Bp then
					return true
				end
				local run = flat(Bp - A)
				local len = run.Magnitude
				local dir = len > 0.01 and run.Unit or B.vfacing
				local side = V3(-dir.Z, 0, dir.X)
				local tail = Bp - dir * math.min(a.BodyLength, len)
				if not landed then
					local k = clamp((now - t0) / math.max(lockAt - t0, 0.05), 0, 1)
					local pulse = 0.5 + 0.5 * math.sin(now * lerp(8, 22, k))
					placeStrip(strip, tail, Bp, a.Width, 0.12, tail.Y + 0.07)
					strip.Transparency = locked and 0.2 or lerp(0.85, 0.45, k)
					for i, e in ipairs(edges) do
						local off = side * (a.Width / 2) * (i == 1 and 1 or -1)
						placeStrip(e, tail + off, Bp + off, locked and 0.9 or 0.55, 0.16, tail.Y + 0.1)
						e.Color = locked and LOCKED or WORM_GLOW
						e.Transparency = locked and 0 or lerp(0.7, 0.2, k * pulse)
					end
				end
				if now < launchAt then
					placeRing(launch, A + V3(0, 0.08, 0), a.Launch, 0.2, 0.5, lerp(0.7, 0.2, 0.5 + 0.5 * math.sin(now * 14)))
				elseif not launched then
					launched = true
					hideRing(launch)
					carve(B, A, a.Launch, 4, scarLife(B))
					burst(A + V3(0, 1, 0), WORM_SAND, 44, 42, 3.4, 1.2, true)
					flingRubble(A, 8, SAND_BITS, 0.8)
					shockRing(B, A, B.def.Size * 0.4, a.Launch * 1.6, 0.4, WORM_SAND)
					playSound(B.def, "Erupt", A, 1)
					kick(A, a.Launch, 1, -3)
				end
				if now >= lockAt and not locked then
					-- committed: the strip flashes, the ground along it shudders
					locked = true
					local near = nearestOnSegment(tail, Bp, myFloorPos(B))
					kick(near, a.Width, 0.35)
					for j = 0, 1 do
						burst(tail:Lerp(Bp, j) + V3(0, 0.5, 0), WORM_SAND, 6, 8, 1.4, 0.5, true)
					end
				end
				if now >= launchAt and now < landAt then
					local f = (now - launchAt) / a.Flight
					placeDisc(shadow, A:Lerp(Bp, f) + V3(0, 0.1, 0), B.def.Size * (0.6 + 0.6 * f), 0.1)
					shadow.Transparency = lerp(0.8, 0.45, f)
				else
					shadow.Transparency = 1
				end
				if now >= landAt and not landed then
					landed = true
					strip.Transparency = 1
					for _, e in ipairs(edges) do
						e.Transparency = 1
					end
					-- its whole body slams down along the strip, carving a trench
					local sc = newScar(B, "hole", scarLife(B) + 2)
					local n = math.max(2, math.floor(flat(Bp - tail).Magnitude / 7))
					for j = 0, n do
						scarHole(sc, tail:Lerp(Bp, j / n), 6.5, 2.6)
					end
					scarHole(sc, Bp, 10, 4.5) -- where its head drove into the sand
					for j = 0, 3 do
						burst(tail:Lerp(Bp, j / 3) + V3(0, 1, 0), WORM_SAND, 16, 26, 2.8, 0.9, true)
					end
					flingRubble(tail:Lerp(Bp, 0.5), 10, SAND_BITS, 0.9)
					local near = nearestOnSegment(tail, Bp, myFloorPos(B))
					playSound(B.def, "Crash", near, 1)
					kick(near, a.Width, 1.4, -4)
				end
				return true
			end,
			cleanup = function()
				strip:Destroy()
				for _, e in ipairs(edges) do
					e:Destroy()
				end
				removeRing(launch)
				shadow:Destroy()
			end,
		})
	end

	-- COIL: sand churning in a ring round you while it circles underneath, then
	-- (once its body is up) the crush zone inside the ring darkening as it
	-- tightens. At the crush: a crater where the head strikes down.
	local function coilMarks(B, C, t0)
		local a = B.def.Attacks.Coil
		C = onSand(C)
		local surfaceAt = t0 + a.Tell
		local crushAt = surfaceAt + a.Close
		local churn = newRing(40, WORM_SAND_DEEP, Enum.Material.Sand, 1)
		local rim = newRing(40, WORM_GLOW, Enum.Material.Neon, 1)
		local crush = newPart("CoilCrush", Enum.PartType.Cylinder, RGB(60, 30, 16), Enum.Material.SmoothPlastic, 1)
		local surfaced, crushed = false, false
		addTelegraph(B, {
			update = function(now)
				if now > crushAt + 0.1 then
					return false
				end
				if now < surfaceAt then
					local k = clamp((now - t0) / a.Tell, 0, 1)
					placeRing(churn, C + V3(0, 0.05, 0), a.Radius, 0.5 + 0.4 * math.sin(now * 20), a.Wall, lerp(0.85, 0.35, k))
					placeRing(rim, C + V3(0, 0.1, 0), a.Radius + a.Wall / 2 + 0.5, 0.25, 0.5, lerp(0.8, 0.15, k))
					crush.Transparency = 1
					return true
				end
				if not surfaced then
					surfaced = true
					hideRing(churn)
					hideRing(rim)
					for j = 0, 4 do
						local ang = j / 5 * math.pi * 2
						burst(C + V3(math.sin(ang), 0, math.cos(ang)) * a.Radius + V3(0, 1, 0), WORM_SAND, 10, 22, 2.4, 0.8, true)
					end
					playSound(B.def, "Erupt", C, 0.8)
					kick(C, a.Radius, 0.8, -2)
				end
				local u = clamp((now - surfaceAt) / a.Close, 0, 1)
				local r = a.Radius - (a.Radius - a.Crush) * u * u
				placeDisc(crush, C + V3(0, 0.07, 0), math.max(r - a.Wall / 2, 0.5) * 2, 0.1)
				crush.Transparency = lerp(0.8, 0.3, u)
				if now >= crushAt and not crushed then
					crushed = true
					crush.Transparency = 1
					carve(B, C, a.Crush + 2, 3, scarLife(B))
					shockRing(B, C, a.Crush, a.Radius, 0.35, WORM_SAND)
					burst(C + V3(0, 1, 0), WORM_SAND, 30, 30, 3, 1, true)
					playSound(B.def, "Crash", C, 1)
					kick(C, a.Radius, 1.3, -4)
				end
				return true
			end,
			cleanup = function()
				removeRing(churn)
				removeRing(rim)
				crush:Destroy()
			end,
		})
	end

	-- DEVOUR: a sinkhole opening under you - the sand really sinks away in
	-- stages - with arms of sand swirling down its sides into the dark pit at
	-- the bottom, the bite marked there, and it drags you in while it's open.
	local function devourFunnel(B, C, t0)
		local a = B.def.Attacks.Devour
		C = onSand(C)
		local biteAt = t0 + a.Tell
		local hole = newScar(B, "hole", math.max(biteAt - serverNow(), 0) + scarLife(B))
		local stages = { { 0.12, 0.55, 0.4 }, { 0.4, 0.8, 0.7 }, { 0.7, 1, 1 } } -- { when, size, depth }
		local done = 0
		local arms = {}
		for i = 1, 8 do
			arms[i] = newPart("FunnelArm", nil, WORM_SAND:Lerp(RGB(255, 240, 210), 0.3), Enum.Material.Sand, 1)
		end
		local pit = newPart("FunnelPit", Enum.PartType.Cylinder, RGB(24, 16, 10), Enum.Material.SmoothPlastic, 1)
		local rim = newRing(32, WORM_GLOW, Enum.Material.Neon, 1)
		local bite = newRing(24, WORM_GLOW, Enum.Material.Neon, 1)
		local last = nil
		addTelegraph(B, {
			update = function(now)
				if now >= biteAt then
					return false
				end
				local dt = last and math.clamp(now - last, 0, 0.1) or 0
				last = now
				local k = clamp((now - t0) / a.Tell, 0, 1)
				while done < #stages and k >= stages[done + 1][1] do
					done = done + 1
					scarHole(hole, C, a.Radius * stages[done][2], a.Depth * stages[done][3])
					burst(C + V3(0, 0.5, 0), WORM_SAND, 16, 10, 2.4, 0.8, true)
					kick(C, a.Radius, 0.4)
				end
				local open = a.Radius * ((done > 0) and stages[done][2] or 0.3)
				-- arms of sand swirling down its sides
				for i, arm in ipairs(arms) do
					local ang = i / #arms * math.pi * 2 + now * 2.6
					local p1 = C + V3(math.sin(ang), 0, math.cos(ang)) * open * 0.95
					local p2 = C + V3(math.sin(ang + 1), 0, math.cos(ang + 1)) * open * 0.3
					p1 = V3(p1.X, floorHeightAt(p1, C.Y) + 0.2, p1.Z)
					p2 = V3(p2.X, floorHeightAt(p2, C.Y) + 0.2, p2.Z)
					placeBar(arm, p1, p2, 1.4, 0.15)
					arm.Transparency = lerp(0.8, 0.25, k)
				end
				local bottom = floorHeightAt(C, C.Y)
				placeDisc(pit, V3(C.X, bottom + 0.15, C.Z), a.Bite * 1.4 * (0.4 + 0.6 * k), 0.1)
				pit.Transparency = lerp(0.6, 0.05, k)
				placeRing(rim, C + V3(0, 0.1, 0), open, 0.2, 0.5, lerp(0.8, 0.4, k))
				local pulse = 0.5 + 0.5 * math.sin(now * lerp(8, 30, k))
				local biteEdge = C + V3(a.Bite, 0, 0)
				placeRing(bite, V3(C.X, floorHeightAt(biteEdge, C.Y) + 0.15, C.Z), a.Bite, 0.3, 0.6, lerp(0.7, 0.05, k * pulse))
				dragMe(B, C, open, a.Pull[1], a.Pull[2], dt)
				return true
			end,
			cleanup = function()
				for _, arm in ipairs(arms) do
					arm:Destroy()
				end
				pit:Destroy()
				removeRing(rim)
				removeRing(bite)
			end,
		})
	end

	-- TAIL LASH. Its tail - the real end of its body, tapering to a bone spike -
	-- whips up out of a crater behind you and scythes round, low over the sand
	-- (the rest of it runs off under the sand to its head). It's a whip: the
	-- far end trails behind in the middle of the swing and cracks round at the
	-- end of it, and its tip tears a furrow through the sand as it goes. Before
	-- it comes, the sand heaves where it'll come up, and the fan it will sweep
	-- and the arc its tip will cut glow on the floor, lighting up the way it'll
	-- swing. In phase two it whips straight back again. BossService hits
	-- exactly this shape (lashAngle there): jump it, roll through it, or be out
	-- of reach.
	local function lashAngle(from, to, u, x)
		u = clamp(u, 0, 1)
		local span = to - from
		local trail = 0.13 * math.abs(span) * x ^ 1.6 * (4 * u * (1 - u)) ^ 2
		return from + span * (u * u * (3 - 2 * u)) - ((span >= 0) and trail or -trail)
	end

	local TAIL_SHARE = 0.5 -- how much of its body is tail (the rest stays under the sand)
	local S_TIP = 0.08 -- (where applyWormPose puts its first segment along its body)

	-- how thick it is along its length for a lash: thin and whippy for most of
	-- the tail, swelling back into its body where it comes out of the sand
	local function tailTaper(s)
		if s >= TAIL_SHARE then
			return 1.06 - 0.16 * s
		end
		local x = clamp((TAIL_SHARE - s) / (TAIL_SHARE - S_TIP), 0, 1) -- 1 = the tip
		if x >= 0.35 then
			return lerp(0.3, 0.2, (x - 0.35) / 0.65)
		end
		return lerp(0.3, 0.95, ((0.35 - x) / 0.35) ^ 1.5)
	end

	-- A lash at a moment: which swing, how far through it, which way, how far
	-- out of the sand the tail is, and the crack at the end of the swing
	local function lashState(L, now)
		local k = now - L.startAt
		local step = L.time + L.pause
		local i = clamp(math.floor(k / step) + 1, 1, L.sweeps)
		local into = k - (i - 1) * step
		local u = clamp(into / L.time, 0, 1)
		local f, g = L.from, L.to
		if i % 2 == 0 then
			f, g = g, f
		end
		local up = 1
		if k < 0 then
			up = clamp(1 + k / L.rise, 0, 1) -- bursting up, just before it swings
		elseif now > L.endAt then
			up = 1 - clamp((now - L.endAt) / 0.45, 0, 1) -- dropping back under
		end
		local after = into - L.time
		local crack = after > 0 and math.sin(math.min(after / 0.22, 1) * math.pi) * math.exp(-after * 5) or 0
		return i, u, f, g, smooth(up), crack
	end

	-- its body for a lash: s from its tail tip (0) to its head (1)
	local function lashPath(B, L, now)
		local g = B.def.Size * 0.64
		local A, R = L.anchor, L.reach
		local _, u, f, to, up, crack = lashState(L, now)
		local sign = (to >= f) and 1 or -1
		local swing = 4 * u * (1 - u) -- how fast it's going (nothing at either end of a swing)
		local back = V3(-math.sin(L.mid), 0, -math.cos(L.mid)) -- the way its body runs off under the sand
		return function(s)
			if s < TAIL_SHARE then
				local x = clamp((TAIL_SHARE - s) / (TAIL_SHARE - S_TIP), 0, 1)
				-- (the crack: its tip flicks on past the end of the swing, and back)
				local yaw = lashAngle(f, to, u, x) + sign * 0.16 * crack * x * x
				local thick = g * tailTaper(s)
				-- it heaves up in an arch where it comes out of the ground, then
				-- runs low along the sand (you can jump it), a ripple running out
				-- along it as it swings
				local h = thick * 0.45 + g * 0.45 * math.sin(math.pi * clamp(x / 0.35, 0, 1))
				h = h + math.sin(x * 8 - now * 20) * 0.7 * x * swing
				local y = h * up - (1 - up) * (thick + 3)
				return A + V3(math.sin(yaw) * x * R, y, math.cos(yaw) * x * R)
			end
			-- the rest of it: down the hole and away under the sand, to its head
			local b = (s - TAIL_SHARE) / (1 - TAIL_SHARE)
			return A + back * (b * 44) + V3(0, -g * 0.55 - b * g * 1.4, 0)
		end
	end

	local function tailLash(B, anchor, yaws, t0)
		local a = B.def.Attacks.TailLash
		anchor = onSand(anchor)
		local from, to = yaws.X, yaws.Y
		local phase = B.model:GetAttribute("Phase") or 1
		local sweeps = (type(a.Sweeps) == "table" and (a.Sweeps[phase] or a.Sweeps[1])) or 1
		local pause = a.Pause or 0.25
		local startAt = t0 + a.Tell
		local L = {
			anchor = anchor, from = from, to = to, mid = (from + to) / 2,
			startAt = startAt, endAt = startAt + sweeps * a.Time + (sweeps - 1) * pause,
			sweeps = sweeps, pause = pause, time = a.Time, reach = a.Reach, rise = 0.14,
		}
		B.lash = L -- (Poses.TailLash draws its body from this)
		local riseAt, goneAt = startAt - L.rise, L.endAt + 0.45
		local heave = newScar(B, "heave", math.max(riseAt - serverNow(), 0.1))
		local heaved = 0
		-- the warning, laid on the floor once: the fan it will sweep, and the
		-- arc its tip will cut (only their glow changes after that)
		local marks = {}
		for i = 1, 5 do
			local yaw = from + (to - from) * (i - 1) / 4
			local dir = V3(math.sin(yaw), 0, math.cos(yaw))
			local ray = newPart("LashRay", nil, WORM_GLOW, Enum.Material.Neon, 1)
			placeStrip(ray, anchor + dir * 3, anchor + dir * a.Reach, 0.35, 0.1, anchor.Y + 0.1)
			marks[#marks + 1] = { part = ray, order = (i - 1) / 4 }
		end
		local ARC = 12
		for k = 1, ARC do
			local y0 = from + (to - from) * (k - 1) / ARC
			local y1 = from + (to - from) * k / ARC
			local bar = newPart("LashRay", nil, WORM_GLOW, Enum.Material.Neon, 1)
			placeStrip(bar, anchor + V3(math.sin(y0), 0, math.cos(y0)) * (a.Reach + 0.5),
				anchor + V3(math.sin(y1), 0, math.cos(y1)) * (a.Reach + 0.5), 0.9, 0.1, anchor.Y + 0.1)
			marks[#marks + 1] = { part = bar, order = (k - 0.5) / ARC }
		end
		local spike = newPart("TailSpike", nil, BONE, Enum.Material.SmoothPlastic, 1)
		spike.Size = V3(0.9, 0.9, 3.6)
		local tipDust = newPart("TailDust", nil, WORM_SAND, nil, 1)
		tipDust.Size = V3(4, 1, 4)
		local spray = wormEmitter("Spray", tipDust, {
			Color = ColorSequence.new(WORM_SAND),
			LightInfluence = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4.5) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.6, 1.1),
			Speed = NumberRange.new(6, 16),
			SpreadAngle = Vector2.new(45, 45),
			Acceleration = V3(0, -35, 0),
			EmissionDirection = Enum.NormalId.Top,
		})
		local furrow, lastCut = nil, nil
		local sounded, cracked = 0, 0
		local came, warned = false, true
		addTelegraph(B, {
			update = function(now)
				if now > goneAt then
					return false
				end
				if now < riseAt then
					local k = clamp((now - t0) / a.Tell, 0, 1)
					if heaved < 2 and k >= (heaved + 1) * 0.35 then
						heaved = heaved + 1
						scarHeave(heave, anchor, 5 + heaved, 1.5 * heaved)
					end
					-- a pulse running the way it will swing, quicker as it comes
					local run = (now - t0) * lerp(1.2, 3, k)
					for _, m in ipairs(marks) do
						local glow = math.max(0, 1 - math.abs(((run - m.order) % 1) - 0.5) * 4)
						Fast.alpha(m.part, math.floor(lerp(0.85, lerp(0.5, 0.05, k), glow) * 20 + 0.5) / 20)
					end
					return true
				end
				if warned then
					warned = false
					for _, m in ipairs(marks) do
						Fast.alpha(m.part, 1)
					end
				end
				if not came then
					came = true
					carve(B, anchor, 6, 3, scarLife(B))
					burst(anchor + V3(0, 1, 0), WORM_SAND, 30, 30, 2.6, 0.9, true)
					flingRubble(anchor, 6, SAND_BITS, 0.7)
					kick(anchor, a.Reach, 0.7, -2)
					furrow = newScar(B, "hole", (goneAt - now) + scarLife(B))
				end
				local i, u, _, _, up = lashState(L, now)
				local swingAt = startAt + (i - 1) * (L.time + pause)
				if sounded < i and now >= swingAt - 0.1 then
					sounded = i
					playSound(B.def, "Sweep", anchor, 1)
				end
				-- its tip, where this frame's body put it: the spike on the end, the
				-- sand spraying off it, and the furrow it tears
				local pts = B.lastPoints
				local tip = B.action == "TailLash" and pts and pts[1]
				if tip and pts[2] and up > 0.05 then
					local along = tip - pts[2]
					along = along.Magnitude > 0.01 and along.Unit or V3(0, 0, 1)
					Fast.move(spike, CFrame.lookAt(tip + along * 1.8, tip + along * 4))
					Fast.alpha(spike, 0)
					local ground = V3(tip.X, anchor.Y, tip.Z)
					Fast.move(tipDust, CFrame.new(ground + V3(0, 0.5, 0)))
					local swinging = u > 0.02 and u < 0.98 and now < L.endAt
					spray.Rate = swinging and 40 or 0
					if swinging and furrow and (not lastCut or flat(ground - lastCut).Magnitude >= 10) then
						lastCut = ground
						scarHole(furrow, ground, 3.2, 1.2)
					end
					-- the crack at the end of each swing
					if cracked < i and now >= swingAt + L.time then
						cracked = i
						burst(ground + V3(0, 1, 0), WORM_SAND, 22, 26, 2.2, 0.7, true)
						shockRing(B, ground, 1, 9, 0.3, WORM_SAND)
						kick(ground, 14, 0.5, -1)
					end
				else
					Fast.alpha(spike, 1)
					spray.Rate = 0
				end
				Fast.flush()
				return true
			end,
			cleanup = function()
				if B.lash == L then
					B.lash = nil
				end
				for _, m in ipairs(marks) do
					m.part:Destroy()
				end
				spike:Destroy()
				tipDust:Destroy()
			end,
		})
	end

	-- TREMOR: dust rising off the whole floor as it thrashes, your view shuddering
	-- harder before each quake if you're on the sand, and at each quake the floor
	-- jumping and CRACKING OPEN in fissures running out from where it is.
	local function quakeEmitter(B)
		if B.quake and B.quake.Parent then
			return B.quakeEmitter
		end
		local arena = arenaOf(B)
		local center = arena and arena:GetAttribute("Center")
		local radius = (arena and arena:GetAttribute("SandRadius")) or 140
		if typeof(center) ~= "Vector3" then
			center = B.vpos
		end
		local holder = newPart("QuakeDust", nil, WORM_SAND, nil, 1)
		holder.Size = V3(radius * 1.6, 1, radius * 1.6)
		holder.CFrame = CFrame.new(V3(center.X, B.vpos.Y + 0.6, center.Z))
		B.quake = holder
		B.quakeEmitter = wormEmitter("Quake", holder, {
			Color = ColorSequence.new(WORM_SAND),
			LightInfluence = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.8, 1.4),
			Speed = NumberRange.new(3, 11),
			SpreadAngle = Vector2.new(25, 25),
			Acceleration = V3(0, -9, 0),
			EmissionDirection = Enum.NormalId.Top,
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		})
		return B.quakeEmitter
	end

	local function tremorShakes(B, t0)
		local a = B.def.Attacks.Tremor
		local dust = quakeEmitter(B)
		local done = t0 + a.Tell + (a.Quakes - 1) * a.Gap + 0.4
		local fired = {}
		addTelegraph(B, {
			update = function(now)
				if now > done then
					return false
				end
				if dust then
					dust.Rate = 18 * clamp((now - t0) / a.Tell, 0, 1)
				end
				local hrp = myRoot()
				local mine = hrp and player:GetAttribute("SpireFloor") == B.floor and not onStone(B, hrp.Position)
				for i = 1, a.Quakes do
					local hitAt = t0 + a.Tell + (i - 1) * a.Gap
					if mine and now > hitAt - 0.5 and now < hitAt and cameraKickEvent then
						cameraKickEvent:Fire(0.12 + 0.35 * (1 - (hitAt - now) / 0.5))
					end
					if now >= hitAt and not fired[i] then
						fired[i] = true
						if dust then
							dust:Emit(250)
						end
						-- a wave of sand racing out across the whole floor from it
						local wave = newRing(32, WORM_SAND, Enum.Material.Sand, 0.1)
						local w0, from = now, B.vpos
						addTelegraph(B, {
							update = function(n)
								local u = (n - w0) / 0.6
								if u >= 1 then
									return false
								end
								placeRing(wave, onSand(from), lerp(6, 140, easeOut(u)), 2.2 * (1 - u) + 0.2, 3.5, lerp(0.1, 1, u))
								return true
							end,
							cleanup = function()
								removeRing(wave)
							end,
						})
						-- fissures: the same on every screen (seeded from the moment it began)
						local origin = B.vpos
						local sc = newScar(B, "hole", scarLife(B) - 1)
						for f = 1, 3 do
							local seed = math.floor((t0 % 1000) * 10) + i * 7 + f * 13
							local ang = seeded(seed) * math.pi * 2
							local dir = V3(math.sin(ang), 0, math.cos(ang))
							local side = V3(-dir.Z, 0, dir.X)
							for k = 1, 4 do
								local wob = (seeded(seed + k) - 0.5) * 5
								scarHole(sc, origin + dir * (4 + k * 9) + side * wob, 3.2, 2.2)
							end
						end
						playSound(B.def, "Crash", B.vpos, 0.7)
						if mine then
							kick(hrp.Position, 10, 1.1, -3)
							burst(hrp.Position - V3(0, 2.8, 0), WORM_SAND, 12, 14, 1.8, 0.6, true)
						elseif hrp and cameraKickEvent and player:GetAttribute("SpireFloor") == B.floor then
							cameraKickEvent:Fire(0.25) -- you feel it through the stone, but it can't reach you
						end
					end
				end
				return true
			end,
			cleanup = function()
				if dust then
					dust.Rate = 0
				end
			end,
		})
	end

	-- UNDERMINE: a glowing ring round the platform it's circling under, sand
	-- spouting up round its edge faster and faster (the cracks on top glow too -
	-- the server lights those). The platform breaking is drawn further down.
	local function undermineMarks(B, C, radius, t0)
		local a = B.def.Attacks.Undermine
		C = onSand(C)
		local breakAt = t0 + a.Tell
		local ring = newRing(32, WORM_GLOW, Enum.Material.Neon, 1)
		local nextPuff = 0
		addTelegraph(B, {
			update = function(now)
				if now >= breakAt then
					return false
				end
				local k = clamp((now - t0) / a.Tell, 0, 1)
				local pulse = 0.5 + 0.5 * math.sin(now * lerp(8, 28, k))
				placeRing(ring, C + V3(0, 0.1, 0), radius + 1.5, 2.4, 0.6, lerp(0.8, 0.05, k * pulse))
				if now >= nextPuff then
					nextPuff = now + lerp(0.35, 0.1, k)
					local ang = math.random() * math.pi * 2
					burst(C + V3(math.sin(ang), 0, math.cos(ang)) * (radius + 2) + V3(0, 1, 0), WORM_SAND, 8, 12, 1.6, 0.6, true)
				end
				local hrp = myRoot()
				if hrp and k > 0.4 and cameraKickEvent and flat(hrp.Position - C).Magnitude < radius + 2 then
					cameraKickEvent:Fire(0.1 + 0.25 * k) -- the stone shaking under your feet
				end
				return true
			end,
			cleanup = function()
				removeRing(ring)
			end,
		})
	end

	----------------------------------------------------------------------
	-- Its poses
	----------------------------------------------------------------------
	-- Swimming under the sand, its back arching out as it goes.
	function Poses.Burrow(B, t, P)
		underPose(B, P, 1, HUMP_EVERY)
	end

	-- The dive's arc: from deep in the hole it stands in, up and over, and down
	-- into the sand at the spot ahead - and on down under it - measured along
	-- its length, so its body can slide along it.
	local function diveArc(O, into, H)
		local F = flat(into - O)
		F = F.Magnitude > 0.5 and F.Unit or V3(0, 0, 1)
		local q0, q1 = O - V3(0, 26, 0), O + V3(0, H, 0) - F * 2
		local q2, q3 = into + V3(0, H, 0) + F * 2, into + F * 8 - V3(0, 30, 0)
		local pts, lens, total = {}, { 0 }, 0
		for i = 0, 28 do
			pts[i + 1] = bezier(q0, q1, q2, q3, i / 28)
			if i > 0 then
				total = total + (pts[i + 1] - pts[i]).Magnitude
				lens[i + 1] = total
			end
		end
		local out = (pts[29] - pts[28]).Unit
		local lo = 1
		local function at(dist)
			if dist <= 0 then
				return q0 + V3(0, dist, 0) -- (the end of it still down in the hole)
			elseif dist >= total then
				return pts[29] + out * (dist - total) -- (gone on down under the sand)
			end
			if lens[lo] > dist then
				lo = 1
			end
			while lens[lo + 1] < dist do
				lo = lo + 1
			end
			return pts[lo]:Lerp(pts[lo + 1], (dist - lens[lo]) / math.max(lens[lo + 1] - lens[lo], 1e-3))
		end
		return at, total
	end

	-- Going back under. From standing, it rears back a little, then arches over
	-- and plunges head-first into the sand a little way ahead (where
	-- BossService sends it: ActA), its whole body pouring in after its head
	-- through the same hole, like a diving serpent. A coil (after a Coil, or
	-- just woken in its coils round the seal) sinks where it lies.
	local DIVE_BODY = 100 -- (about its length standing up out of the sand)
	function Poses.Dive(B, t, P)
		local T = B.def.Hunt.DiveTime
		local k = clamp(t / T, 0, 1)
		if (B.prevAction == "Coil" or B.prevAction == "Wake") and B.coilRest then
			local c = B.coilRest
			P.girth = c.g
			P.path = coilPath(c.C, c.r, c.g, c.headUp, c.rise or 1, c.thEnd, smooth(k) * c.g * 3)
			-- (where it "is" slips on under the sand to where it'll swim from next -
			-- the spot BossService sends it to - so it doesn't jump there after)
			local into = B.model:GetAttribute("ActA")
			P.override = typeof(into) == "Vector3" and c.C:Lerp(V3(into.X, c.C.Y, into.Z), smooth(k)) or c.C
			P.noPush, P.noShadow = true, true
			return
		end
		-- the arc, worked out once when it starts (and again if the spot it's
		-- diving at arrives a moment after the move does)
		local into = B.model:GetAttribute("ActA")
		local D = B.dive
		if not D or D.start ~= B.actionStart or D.into ~= into then
			local O = (D and D.start == B.actionStart) and D.O or B.vpos
			local target = typeof(into) == "Vector3" and V3(into.X, O.Y, into.Z) or O + B.vfacing * 18
			local at, total = diveArc(O, target, B.def.Size * 1.9)
			local run = flat(target - O)
			D = {
				start = B.actionStart, into = into, O = O, at = at, total = total,
				F = run.Magnitude > 0.5 and run.Unit or B.vfacing, span = run.Magnitude,
			}
			B.dive = D
		end
		-- where its head is along the arc: it rears back, then plunges - faster
		-- and faster - until every bit of it has gone in
		local head0 = DIVE_BODY - 10
		local head
		if k < 0.22 then
			head = head0 - 6 * math.sin(k / 0.22 * math.pi / 2)
		else
			local q = (k - 0.22) / 0.78
			head = (head0 - 6) + (D.total + DIVE_BODY + 5 - (head0 - 6)) * q ^ 1.5
		end
		local at = D.at
		P.path = function(s)
			return at(head - (1 - s) * DIVE_BODY)
		end
		-- where it "is" goes with its head, from the old hole to the new one (so
		-- it carries on swimming from where it went in, without a jump)
		local over = clamp(flat(at(head) - D.O):Dot(D.F), 0, D.span)
		P.override = D.O + D.F * over
		P.mouth = 0.6 * (1 - k)
		P.eyes = 1
		P.sink = smooth(clamp((k - 0.5) / 0.5, 0, 1)) -- (the glow in its throat going under with it)
		P.noShadow = true
	end

	-- Bursting up out of the sand, maw wide, then standing there: EXPOSED.
	function Poses.Erupt(B, t, P)
		local spot = B.model:GetAttribute("ActA")
		if typeof(spot) == "Vector3" then
			P.override = spot
		end
		local k = clamp(t / 0.38, 0, 1)
		P.sink = 1 - easeOut(k)
		P.mouth = t < 0.38 and 1 or clamp(1 - (t - 0.38) / 0.6, 0, 1)
		P.flare = clamp(1 - t / 0.9, 0, 1)
		P.lean = -0.35 * (1 - smooth((t - 0.25) / 0.6))
		P.lift = 6 * spring(t, 4, 9)
		P.spill = 32 * clamp(1 - t / 1.2, 0, 1) + 4 -- sand pouring off it
	end

	-- Racing after you under the sand (arching often), then waiting under the heave.
	function Poses.Ambush(B, t, P)
		local locked = typeof(B.model:GetAttribute("ActA")) == "Vector3"
		underPose(B, P, locked and 0.4 or 1.3, not locked and 42 or nil)
	end

	-- Leaping out in an arc toward the end of the strip (which follows you until
	-- it locks), crashing down along it, lying stuck in its trench, then sliding
	-- into the sand at the far end.
	function Poses.Breach(B, t, P)
		local a = B.def.Attacks.Breach
		local m = B.model
		local A, Bp = m:GetAttribute("ActA"), m:GetAttribute("ActB")
		local tell = B.breachTell or a.Tell
		if typeof(A) ~= "Vector3" or typeof(Bp) ~= "Vector3" or t < tell then
			underPose(B, P, 1.4, 30)
			P.shake = 0.25 * clamp(t / tell, 0, 1)
			P.stage = "under"
			return
		end
		P.stage = "leap"
		local last = (m:GetAttribute("ActN") or 1) == 1
		local run = flat(Bp - A)
		local len = math.max(run.Magnitude, 1)
		local dir = run.Magnitude > 0.01 and run.Unit or B.vfacing
		local g = B.def.Size * 0.64
		local fl = t - tell
		local head, arc = len, 0
		if fl < a.Flight then
			local u = fl / a.Flight
			head = u * len
			arc = 1 - smooth((u - 0.55) / 0.45) -- the arc flattens as it comes down
			P.mouth, P.flare = 1 - u * 0.5, 1 - u
			P.spill = 28 -- sand streaming off it in the air
		else
			local slideAt = m:GetAttribute("ActT")
			local now = (B.actionStart or 0) + t
			if typeof(slideAt) == "number" and now >= slideAt then
				local slide = last and a.Slide or a.Slide * 0.5
				head = len + clamp((now - slideAt) / slide, 0, 1) * (a.BodyLength + 12)
			end
			P.eyes = last and 0.6 or 1
			P.spill = 6
		end
		local BL, H = a.BodyLength, a.Height
		P.path = function(s)
			local x = head - (1 - s) * BL -- how far along the leap this bit of it is
			local lie = g * 0.2 -- (lying down in its trench)
			if x < 0 then
				return A + V3(0, lie + x, 0) -- still coming up out of the launch hole
			elseif x > len then
				return Bp + V3(0, lie - (x - len), 0) -- gone down the far hole
			end
			local v = x / len
			return A + dir * x + V3(0, lie + H * 4 * v * (1 - v) * arc, 0)
		end
		P.facing = dir
		P.noPush, P.noShadow = true, true
	end

	-- Circling you under the sand (its back arching out round you), then coiled
	-- round you with its head reared over the middle, tightening, striking down,
	-- and lying there coiled (EXPOSED).
	function Poses.Coil(B, t, P)
		local a = B.def.Attacks.Coil
		local C = B.model:GetAttribute("ActA")
		if typeof(C) ~= "Vector3" then
			underPose(B, P, 1, nil)
			return
		end
		if not B.coilAng then
			local off = flat(B.vpos - C)
			B.coilAng = off.Magnitude > 1 and math.atan2(off.X, off.Z) or 0
			B.coilFromR = off.Magnitude
		end
		local lap = math.pi * 2 * 0.94
		if t < a.Tell then
			-- circling you under the sand (BossService moves it round: its body
			-- follows exactly where it has been)
			underPose(B, P, 1.3, 24)
			P.stage = "circle"
			return
		end
		P.stage = "ring"
		local e = t - a.Tell
		local u = clamp(e / a.Close, 0, 1)
		local r = a.Radius - (a.Radius - a.Crush) * u * u
		local g = a.Wall + 2
		local strike = clamp((e - a.Close + 0.16) / 0.16, 0, 1)
		local headUp = lerp(g * 2.8, g * 0.55, strike * strike)
		local thEnd = B.coilAng + lap
		-- (it all bursts up out of the sand together: head and neck too)
		local up = smooth(clamp(e / 0.35, 0, 1))
		P.girth = g
		P.path = coilPath(C, r, g, headUp, clamp(e / 0.3, 0, 1), thEnd, (1 - up) * (headUp + g * 1.5))
		P.override = C
		P.mouth = (strike > 0 and strike < 1) and 1 or (0.35 + 0.3 * u)
		P.flare, P.eyes = u, 1
		P.spill = 12
		P.noPush, P.noShadow = true, true
		B.coilRest = { C = C, r = r, g = g, headUp = headUp, thEnd = thEnd }
	end

	-- Under the sinkhole, waiting (the funnel is all you see). (It swims to the
	-- middle of it under the sand - BossService moves it there.)
	function Poses.Devour(B, t, P)
		underPose(B, P, 0, nil)
	end

	-- Under the sand, getting behind you - then its tail whips up out of the sand
	-- and round (its own body, tapering to a spike: see tailLash).
	function Poses.TailLash(B, t, P)
		local L = B.lash
		local now = (B.actionStart or 0) + t
		if not L or now < L.startAt - L.rise then
			underPose(B, P, 0.4, nil)
			P.stage = "under"
			return
		end
		-- its tail, whipping round (see tailLash); its head stays under the sand
		P.stage = "lash"
		P.path = lashPath(B, L, now)
		P.taper = tailTaper
		P.girth = B.def.Size * 0.64
		P.override = L.anchor
		P.sink, P.ridge, P.eyes = 1, 0, 0
		P.noShadow = true
	end

	-- Thrashing underground.
	function Poses.Tremor(B, t, P)
		underPose(B, P, 0.9 + 0.35 * math.sin(t * 14), nil)
		P.shake = 0.4
	end

	-- Circling under a platform, its back arching out all the way round it.
	function Poses.Undermine(B, t, P)
		-- (BossService moves it round under the platform: its body follows)
		underPose(B, P, 1.1, 26)
	end

	----------------------------------------------------------------------
	-- Asleep in the middle of the arena, and waking
	----------------------------------------------------------------------
	-- Until someone comes near, it lies coiled round the seal at the heart of
	-- the arena, half sunk in the sand, its head laid in the middle of its
	-- coils (looking toward the gate), breathing slowly: the thing you see as
	-- you come in, and walk up to. Come within WakeRange (or punch it) and it
	-- wakes: it stirs, its head rears up out of the coils and roars at you -
	-- and then the coils sink and it's under the sand, hunting.
	-- (Gloomgut keeps its own sleeping and waking.)
	local SLEEP_R = 19 -- how far out from the seal its coils lie
	local function sleepCoil(B, t, rear, stir, down)
		local g = B.def.Size * 0.56
		local C = B.vpos
		if not B.sleepFace then
			-- its neck comes over from the far side, so its head faces the way
			-- it was put down facing (the gate)
			local root = B.model.PrimaryPart
			local f = root and flat(root.CFrame.LookVector) or B.vfacing
			f = f.Magnitude > 0.01 and f.Unit or V3(0, 0, 1)
			B.sleepFace = math.atan2(-f.X, -f.Z)
		end
		-- (breathing only while you're in its arena: elsewhere nobody sees it)
		local breathe = (player:GetAttribute("SpireFloor") == B.floor) and math.sin(t * 2 * math.pi / 5.5) or 0
		local headUp = lerp(g * 0.62 + breathe * 0.35, g * 2.9, rear) + math.sin(t * 23) * stir * 0.6
		B.coilRest = { C = C, r = SLEEP_R, g = g, headUp = headUp, thEnd = B.sleepFace, rise = 0.8 }
		return coilPath(C, SLEEP_R, g * (1 + 0.025 * breathe), headUp, 0.8, B.sleepFace, down or 0), g
	end

	local gloomDormant, gloomWake = Poses.Dormant, Poses.Wake
	function Poses.Dormant(B, t, P)
		if B.kind ~= "Worm" then
			return gloomDormant(B, t, P)
		end
		-- (back from a fight: its coils come up out of the sand and settle)
		local up = smooth(clamp(t / 1.6, 0, 1))
		local path, g = sleepCoil(B, t, 0, 0, (1 - up) * B.def.Size * 1.4)
		P.path, P.girth = path, g
		P.eyes, P.mouth = 0, 0
		P.spill = 6 * (1 - up)
		P.noShadow = true
		P.solid = up > 0.9 -- (not while its coils are still coming up out of the sand)
	end

	function Poses.Wake(B, t, P)
		if B.kind ~= "Worm" then
			return gloomWake(B, t, P)
		end
		local u = clamp(t / B.def.WakeTime, 0, 1)
		local stir = u < 0.3 and u / 0.3 or math.max(0, 1 - (u - 0.3) * 6) -- its coils shudder as it stirs
		local rear = easeOutBack(clamp((u - 0.28) / 0.35, 0, 1)) -- then its head comes up
		local path, g = sleepCoil(B, t, rear, stir)
		P.path, P.girth = path, g
		P.eyes = clamp((u - 0.2) / 0.1, 0, 1)
		if u > 0.5 and u < 0.85 then
			P.mouth = math.sin((u - 0.5) / 0.35 * math.pi) -- the roar
			P.flare = P.mouth
		end
		P.spill = 10 * stir + 14 * clamp(rear, 0, 1) * (1 - u) -- sand pouring off its coils
		P.noShadow = true
	end

	-- You can't walk through it. Every piece of its body that's out of the
	-- sand is solid: walk into it - or let it swim into you - and you're
	-- shoved out to its side, like bumping into a wall. Its back arching out
	-- as it swims, its coil round you, its neck and head, its body lying in its
	-- trench, its sleeping coils. (Never up in the air above you: you can run
	-- under its head.) The one way THROUGH it is a roll: you're untouchable for
	-- the length of it (the server says the same), and that's how you get out
	-- of its coil.
	local sandOnly = RaycastParams.new()
	sandOnly.FilterType = Enum.RaycastFilterType.Include
	sandOnly.FilterDescendantsInstances = { Workspace:FindFirstChildOfClass("Terrain") }
	function pushOutOfWorm(B, hrp, P)
		local pts, gs = B.lastPoints, B.segGirths
		if P.solid == false or not pts or not gs then
			return
		end
		local char = hrp.Parent
		if char and char:FindFirstChild("RollIframes") then
			return -- mid-roll (CombatClient's glow while you're untouchable)
		end
		local pos = hrp.Position
		local feet, top = pos.Y - 2.6, pos.Y + 2.2
		local moved = false
		for _ = 1, 2 do -- (twice: pushed out of one piece of it into the next is caught)
			for i = 1, #pts do
				local c, r = pts[i], (gs[i] or 0) * 0.5
				if r > 0.5 and c.Y + r * 0.85 > feet and c.Y - r * 0.85 < top then
					local off = flat(pos - c)
					local d = off.Magnitude
					local want = r * 0.9 + 1.4
					if d < want then
						local out = d > 0.05 and off / d or B.vfacing
						pos = V3(c.X, pos.Y, c.Z) + out * want
						moved = true
					end
				end
			end
		end
		if moved then
			-- (a quick shove, not a jump: at most 3 studs a frame, which is still
			-- far faster than anyone walks into it)
			local shove = pos - hrp.Position
			if shove.Magnitude > 3 then
				pos = hrp.Position + shove.Unit * 3
			end
			-- and never into the side of a crater: if the sand where you'd land
			-- is higher than your feet, you land on top of it instead
			local hit = Workspace:Raycast(pos + V3(0, 8, 0), V3(0, -14, 0), sandOnly)
			if hit and hit.Position.Y > pos.Y - 2.2 then
				pos = V3(pos.X, hit.Position.Y + 3.1, pos.Z)
			end
			hrp.CFrame = CFrame.new(pos) * (hrp.CFrame - hrp.Position)
		end
	end

	----------------------------------------------------------------------
	-- Its one-off moments (sounds, bursts, craters) and the warnings it places
	----------------------------------------------------------------------
	function Starts.Dive(B, t0)
		local T = B.def.Hunt.DiveTime
		B.lastHump = (B.odo or 0) - HUMP_EVERY * 0.5 -- (its back arches up soon after it goes under)
		at(B, t0 + T * 0.2, function()
			playSound(B.def, "Dive", B.vpos, 0.8)
		end)
		-- the sand bursting where its head plunges in, and pouring in after it
		local function where()
			local into = B.model:GetAttribute("ActA")
			return typeof(into) == "Vector3" and onSand(into) or B.vpos
		end
		at(B, t0 + T * 0.55, function()
			if B.prevAction == "Coil" or B.prevAction == "Wake" then
				return -- (a coil just sinks where it lies)
			end
			local spot = where()
			carve(B, spot, 7, 3.5, scarLife(B))
			burst(spot + V3(0, 1, 0), WORM_SAND, 30, 26, 2.8, 1, true)
			shockRing(B, spot, B.def.Size * 0.3, B.def.Size * 0.9, 0.35, WORM_SAND)
			kick(spot, 20, 0.5)
		end)
		at(B, t0 + T * 0.85, function()
			burst(where() + V3(0, 1, 0), WORM_SAND, 14, 14, 2.2, 0.8, true)
		end)
	end

	function Starts.Erupt(B, t0)
		at(B, t0, function()
			local spot = B.model:GetAttribute("ActA")
			spot = typeof(spot) == "Vector3" and spot or B.vpos
			-- it bursts out of a crater it blows in the sand
			carve(B, spot, 13, 5, scarLife(B))
			burst(spot + V3(0, 1, 0), WORM_SAND, 44, 40, 3.2, 1.2, true)
			burst(spot + V3(0, 0.5, 0), WORM_SAND_DEEP, 20, 24, 2.4, 0.8)
			flingRubble(spot, 10, SAND_BITS, 1)
			shockRing(B, spot, B.def.Size / 2, B.def.Size * 1.1, 0.4, WORM_SAND)
			playSound(B.def, "Erupt", spot, 1)
			kick(spot, 20, 1.1, -4)
		end)
	end

	function Starts.Breach(B, t0)
		-- a leap straight after another takes off faster
		local a = B.def.Attacks.Breach
		B.breachTell = (B.prevAction == "Breach") and a.ChainTell or a.Tell
	end

	function Starts.Coil(B, t0)
		B.coilAng, B.coilRest = nil, nil
	end

	function Starts.Devour(B, t0)
		at(B, t0 + 0.05, function()
			playSound(B.def, "Devour", B.vpos, 1)
		end)
	end

	function Starts.Tremor(B, t0)
		at(B, t0 + 0.05, function()
			playSound(B.def, "Roar", B.vpos, 1)
		end)
		tremorShakes(B, t0)
	end

	function Starts.Undermine(B, t0)
		B.underAng = nil
		at(B, t0 + 0.05, function()
			playSound(B.def, "Roar", B.vpos, 0.6)
		end)
	end

	function SlotSpawns.Ambush(B, i, spot)
		if i == 1 then
			local eruptAt = tonumber(B.model:GetAttribute("ActN")) or (serverNow() + B.def.Attacks.Ambush.Lock)
			ambushMark(B, spot, eruptAt)
		end
	end

	function SlotSpawns.Breach(B, i, spot, t0)
		if i == 2 then
			breachStrip(B, t0, B.breachTell or B.def.Attacks.Breach.Tell)
		end
	end

	function SlotSpawns.Coil(B, i, spot, t0)
		if i == 1 then
			coilMarks(B, spot, t0)
		end
	end

	function SlotSpawns.Devour(B, i, spot, t0)
		if i == 1 then
			devourFunnel(B, spot, t0)
		end
	end

	function SlotSpawns.TailLash(B, i, spot, t0)
		local anchor = B.model:GetAttribute("ActA")
		if i == 2 and typeof(anchor) == "Vector3" then
			tailLash(B, anchor, spot, t0) -- (slot 2 isn't a place: it's the sweep's start and end angles)
		end
	end

	function SlotSpawns.Undermine(B, i, spot, t0)
		if i == 1 then
			undermineMarks(B, spot, tonumber(B.model:GetAttribute("ActN")) or 10, t0)
		end
	end

	----------------------------------------------------------------------
	-- The arena answering it
	----------------------------------------------------------------------
	-- What stands in the arena trembles as it swims underneath: pillars, braziers,
	-- the columns on the platforms. (Only on your screen,
	-- and only by a hair - enough to see, never enough to trip you.)
	local SHAKERS = {
		SandPillar = true, SandPillarBand = true, SandPillarBreak = true, FallenDrum = true,
		BrazierStand = true, BrazierBowl = true, BrazierFoot = true,
		PlatformColumn = true, PlatformColumnBase = true, DuneRock = true,
		LairStone = true, LairStoneCap = true, LairGlyph = true, LairGlyphMark = true,
	}
	local function stepTremble(B, near)
		if not B.shakers or (#B.shakers == 0 and os.clock() > (B.shakerLook or 0)) then
			B.shakers = {}
			B.shakerLook = os.clock() + 3
			local arena = arenaOf(B)
			if arena then
				for _, d in ipairs(arena:GetDescendants()) do
					if d:IsA("BasePart") and SHAKERS[d.Name] then
						table.insert(B.shakers, { part = d, cf = d.CFrame })
					end
				end
			end
		end
		-- (a dozen times a second is plenty for a tremble, and it's all moved in one go)
		if os.clock() < (B.nextTremble or 0) then
			return
		end
		B.nextTremble = os.clock() + 0.08
		local parts, cframes = {}, {}
		for _, s in ipairs(B.shakers) do
			local p = s.part
			if p.Parent then
				local d = near and flat(s.cf.Position - near).Magnitude or math.huge
				if d < 34 then
					local k = (1 - d / 34) * 0.3
					parts[#parts + 1], cframes[#cframes + 1] = p, s.cf + V3((math.random() - 0.5) * k, 0, (math.random() - 0.5) * k)
					s.moved = true
					if k > 0.15 and math.random() < 0.01 then
						burst(V3(s.cf.X, B.vpos.Y + 0.5, s.cf.Z), WORM_SAND, 4, 5, 1.2, 0.6, true)
					end
				elseif s.moved then
					parts[#parts + 1], cframes[#cframes + 1] = p, s.cf
					s.moved = false
				end
			end
		end
		if #parts > 0 then
			pcall(function()
				Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
			end)
		end
	end

	-- The middle of the dunes (where the seal caves in: the whirlpool). Looked
	-- for again until it's found - the arena might not have loaded in yet.
	local function sinkCenter(B)
		if not B.sinkCenter and os.clock() >= (B.sinkLook or 0) then
			B.sinkLook = os.clock() + 1
			for _, h in ipairs(CollectionService:GetTagged("DuneSinkhole")) do
				if h:GetAttribute("Floor") == B.floor and h:IsA("BasePart") then
					B.sinkCenter = h.Position
				end
			end
		end
		return B.sinkCenter
	end

	local rehearse -- (below, with the rest of the warming up)

	-- Every frame, for the worm:
	--  * the warm-up, the moment you arrive in its arena (see rehearse)
	--  * the RUMBLE: each time the sand bucks round it (BossService's pulses)
	--    the ring shows how far it reaches, and your view thumps if it's close
	--    (plus a low looping "Worm Rumble" sound while it's near, if you've added one)
	--  * the WHIRLPOOL in phase two: the bowl in the middle drags you down
	--  * the whirlpool's sand spiralling down the sides of the bowl
	--  * the arena trembling as it passes under things
	function stepWormSenses(B, dt, here, awake, state)
		if here and not B.rehearsed then
			B.rehearsed = true
			rehearse(B)
		elseif not here then
			B.rehearsed = nil -- (and again next time you come)
		end
		local hrp = myRoot()
		local under = B.model:GetAttribute("Submerged") == true
		-- (Config.Bosses[2].Rumble: Range = how close before you feel it, Shake =
		-- how hard each thump knocks your view)
		local R = B.def.Rumble or {}
		local range, strength = R.Range or 40, R.Shake or 0.45
		local want = 0
		if here and awake and hrp and under then
			local d = flat(hrp.Position - B.vpos).Magnitude
			want = clamp(1 - (d - 8) / range, 0, 1)
		end
		B.rumble = (B.rumble or 0) + (want - (B.rumble or 0)) * math.min(1, dt * 4)
		-- Each pulse of the rumble (BossService sends one every Rumble.Every
		-- seconds as it swims, and hurts whoever is on the sand inside
		-- Rumble.Radius): the sand jumps in a ring round its ridge - that ring is
		-- how far it reaches - and you feel it in your view if it's close
		local pulseT = B.model:GetAttribute("RumbleT")
		if pulseT ~= B.rumbleSeen then
			B.rumbleSeen = pulseT
			local at = B.model:GetAttribute("RumbleP")
			if type(pulseT) == "number" and typeof(at) == "Vector3" and serverNow() - pulseT < 0.5 and here then
				local reach = R.Radius or 16
				local c = onSand(at)
				shockRing(B, c, 3, reach, 0.35, WORM_SAND)
				for i = 1, 8 do
					local a = i / 8 * math.pi * 2
					burst(c + V3(math.sin(a) * reach * 0.8, 0.5, math.cos(a) * reach * 0.8), WORM_SAND, 4, 14, 1.6, 0.5, true)
				end
				if hrp and cameraKickEvent then
					local d = flat(hrp.Position - c).Magnitude
					if d < range then
						cameraKickEvent:Fire(strength * (d <= reach and 1 or 0.35 + 0.4 * (1 - d / range)))
					end
				end
			end
		end
		if B.rumble > 0.55 and hrp and os.clock() > (B.nextPuff or 0) then
			B.nextPuff = os.clock() + 0.4
			burst(hrp.Position - V3((math.random() - 0.5) * 4, 2.6, (math.random() - 0.5) * 4), WORM_SAND, 5, 6, 1.1, 0.5, true)
		end
		-- the low sound (looked for every couple of seconds, not every frame)
		local name = B.def.Sounds and B.def.Sounds.Rumble
		if B.rumble > 0.01 and name and not B.rumbleSound and os.clock() > (B.rumbleLook or 0) then
			B.rumbleLook = os.clock() + 2
			local template = findSound(name)
			if template then
				local s = template:Clone()
				s.Looped = true
				s.Volume = 0
				s.SoundGroup = soundGroup("Effects")
				s.Parent = game:GetService("SoundService")
				s:Play()
				B.rumbleSound = s
			end
		end
		if B.rumbleSound then
			B.rumbleSound.Volume = 0.8 * B.rumble * ((Config.Audio and Config.Audio.BossSounds) or 0.85)
			if B.rumble <= 0.01 then
				B.rumbleSound:Destroy()
				B.rumbleSound = nil
			end
		end
		-- you arrived after the seal caved in: the pit is dug for you now
		if B.sealDown and here and not B.bowl and Terrain and B.def.Scars and B.def.Scars.Terrain and os.clock() > (B.bowlTry or 0) then
			B.bowlTry = os.clock() + 3
			B.sealDown = false
			collapseSeal(B, true, true)
		end
		-- the whirlpool
		local W = B.def.Whirlpool
		local center = sinkCenter(B)
		if W and center and here and B.phase2Look and state == "Fighting" then
			dragMe(B, center, W.Radius, W.Pull[1], W.Pull[2], dt)
		end
		if B.vortex then
			local v = B.vortex
			local spin = os.clock() * 0.9
			for _, s in ipairs(v.arms) do
				local function pt(k)
					local r = v.radius * (1 - k * 0.85)
					local ang = s.arm / 3 * math.pi * 2 + k * 2.6 + spin
					local p = v.center + V3(math.sin(ang) * r, 0, math.cos(ang) * r)
					return V3(p.X, floorHeightAt(p, v.center.Y) + 0.25, p.Z)
				end
				placeBar(s.part, pt(s.j / 8), pt((s.j + 1) / 8), 2.8 - s.j * 0.2, 0.15)
			end
		end
		-- the arena trembling as it passes underneath
		stepTremble(B, (here and awake and under) and B.vpos or nil)
	end

	----------------------------------------------------------------------
	-- The platforms (the dunes' own pieces)
	----------------------------------------------------------------------
	-- A platform shattering (undermined: it burst up through it)
	local platformsSeen = {}
	local function trackPlatform(pm)
		if platformsSeen[pm] or not pm:IsA("Model") then
			return
		end
		platformsSeen[pm] = true
		local function where()
			local slab = pm:FindFirstChild("PlatformSlab")
			return slab and V3(slab.Position.X, slab.Position.Y - 0.85, slab.Position.Z)
		end
		pm:GetAttributeChangedSignal("Cracks"):Connect(function()
			local c, spot = pm:GetAttribute("Cracks"), where()
			if c and c > 0 and spot then
				burst(spot + V3(0, 2, 0), STONE_BITS[1], 16, 16, 1.6, 0.7, true)
			end
		end)
		pm:GetAttributeChangedSignal("Broken"):Connect(function()
			local spot = where()
			if pm:GetAttribute("Broken") and spot then
				flingRubble(spot, 16)
				burst(spot + V3(0, 1, 0), WORM_SAND, 40, 30, 3.2, 1.1, true)
				local def = Config.Bosses[pm:GetAttribute("Floor") or 2]
				if def then
					playSound(def, "Crash", spot, 1)
				end
				kick(spot, 20, 1.2, -4)
			end
		end)
	end

	for _, pm in ipairs(CollectionService:GetTagged("DunePlatform")) do
		trackPlatform(pm)
	end
	CollectionService:GetInstanceAddedSignal("DunePlatform"):Connect(trackPlatform)

	----------------------------------------------------------------------
	-- Warming up
	----------------------------------------------------------------------
	-- Everything the fights play is fetched well before it's needed, so nothing
	-- stalls, or plays silent, the first time it happens:
	--  * every boss sound and song, a couple of seconds after you join (in the
	--    background), and again as you arrive in the worm's arena
	--  * the worm's whole fight rehearsed as you arrive (see rehearse below)
	--  * the particle textures the sand and slime are drawn with
	--  * the first time you arrive in a Spire arena, every material the fight
	--    draws with is shown to your screen for a moment, too small to see
	-- (The arenas themselves are loaded for you by SpireService as soon as you
	-- open the Spire menu.)
	local ContentProvider = game:GetService("ContentProvider")
	local function warmSounds()
		local list, seen = {}, {}
		local function add(name)
			if type(name) == "string" and name ~= "" and not seen[name] then
				seen[name] = true
				local sound = findSound(name)
				if sound then
					list[#list + 1] = sound
				end
			end
		end
		for _, def in pairs(Config.Bosses or {}) do
			for key, name in pairs(def.Sounds or {}) do
				add(name)
				add("Boss " .. key)
			end
			add(def.Music)
			add(def.VictorySound)
		end
		for _, key in ipairs({ "Wake", "Slam", "Wave", "Spit", "Splat", "Lunge", "Wail", "Erupt", "Break", "Death" }) do
			add("Boss " .. key) -- (what Mireworm borrows when it has no sound of its own)
		end
		add(Config.AcidRain and Config.AcidRain.Sound)
		for _, f in ipairs((Config.Spire and Config.Spire.Floors) or {}) do
			add(f.ambience and f.ambience.Sound)
		end
		list[#list + 1] = "rbxasset://textures/particles/smoke_main.dds"
		list[#list + 1] = "rbxasset://textures/particles/sparkles_main.dds"
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end
	task.delay(2, warmSounds)

	-- THE REHEARSAL: the moment you're in the worm's arena - while it's still
	-- asleep - everything its fight does for the first time is done now, so
	-- the fight looks right from its very first move instead of only the
	-- second time round:
	--  * the whole sand floor is loaded (the game streams the world in near
	--    you first: sand further off might not be there yet, and then the worm
	--    shows through where the sand should hide it and craters can't open)
	--  * every sound and song it plays
	--  * everything it looks up in the arena: what stands on the sand, the
	--    platforms, the seal that caves in, the pit, what trembles
	--  * one small hole dug and filled deep inside the floor, out of sight, so
	--    the first real crater doesn't stall
	--  * the dust of its tremor
	function rehearse(B)
		task.spawn(function()
			local arena = arenaOf(B)
			local center = arena and arena:GetAttribute("Center")
			if typeof(center) == "Vector3" then
				for i = 0, 8 do
					local a = i / 8 * math.pi * 2
					local spot = (i == 0) and center or center + V3(math.sin(a) * 110, 0, math.cos(a) * 110)
					pcall(function()
						player:RequestStreamAroundAsync(spot, 6)
					end)
				end
			end
		end)
		task.spawn(function()
			warmSounds()
		end)
		pcall(warmSand, B)
		pcall(onStone, B, B.vpos)
		pcall(sinkCenter, B)
		pcall(stepTremble, B, nil)
		pcall(collapseSeal, B, B.sealDown or false) -- (only looks the seal up: changes nothing)
		pcall(quakeEmitter, B)
	end

	local WARM_MATERIALS = {
		Enum.Material.Sand, Enum.Material.Sandstone, Enum.Material.Slate, Enum.Material.Neon, Enum.Material.SmoothPlastic,
		Enum.Material.Glass, Enum.Material.Metal, Enum.Material.Fabric, Enum.Material.Wood, Enum.Material.Limestone,
	}
	local warmedFloors = {}
	local function warmMaterials()
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		local bits = {}
		for k, mat in ipairs(WARM_MATERIALS) do
			local bit = newPart("Warm", nil, RGB(200, 200, 200), mat, 0.97)
			bit.Size = V3(0.2, 0.2, 0.2)
			bits[k] = bit
		end
		local t0 = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local cf = cam.CFrame
			for k, bit in ipairs(bits) do
				bit.CFrame = cf * CFrame.new((k - 5) * 0.25, -1.2, -5)
			end
			if os.clock() - t0 > 0.5 then
				conn:Disconnect()
				for _, bit in ipairs(bits) do
					bit:Destroy()
				end
			end
		end)
	end
	player:GetAttributeChangedSignal("SpireFloor"):Connect(function()
		local f = player:GetAttribute("SpireFloor")
		if f and not warmedFloors[f] then
			warmedFloors[f] = true
			warmMaterials()
		end
	end)
end

----------------------------------------------------------------------
-- The arena answering phase two: its slime pools brighten
----------------------------------------------------------------------
local POOL_NAMES = { SlimePool = true, SlimePoolDeep = true, SlimePuddle = true, Moat = true, SlimeFall = true }
local function brightenPools(on)
	local arena = Workspace:FindFirstChild("SlimeArena")
	if not arena then
		return
	end
	for _, d in ipairs(arena:GetDescendants()) do
		if d:IsA("BasePart") and POOL_NAMES[d.Name] then
			local base = d:GetAttribute("BaseTransparency")
			if base == nil then
				base = d.Transparency
				d:SetAttribute("BaseTransparency", base)
			end
			tween(d, 1.2, { Transparency = on and math.max(0, base - 0.18) or base })
		end
	end
end

----------------------------------------------------------------------
-- The boss bar
----------------------------------------------------------------------
local barGui = Instance.new("ScreenGui")
barGui.Name = "BossBar"
barGui.ResetOnSpawn = false
barGui.DisplayOrder = 6
barGui.IgnoreGuiInset = false
barGui.Enabled = false
barGui.Parent = playerGui

local barHolder = Instance.new("Frame")
barHolder.AnchorPoint = Vector2.new(0.5, 0)
barHolder.Position = UDim2.new(0.5, 0, 0, 58)
barHolder.Size = UDim2.new(0.52, 0, 0, 46)
barHolder.BackgroundTransparency = 1
barHolder.Parent = barGui
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MaxSize = Vector2.new(780, 46)
sizeLimit.MinSize = Vector2.new(300, 46)
sizeLimit.Parent = barHolder

local barName = Instance.new("TextLabel")
barName.BackgroundTransparency = 1
barName.Size = UDim2.new(1, -90, 0, 24)
barName.Font = SERIF
barName.TextSize = 23
barName.TextXAlignment = Enum.TextXAlignment.Left
barName.TextColor3 = RGB(236, 226, 204)
barName.TextStrokeTransparency = 0.45
barName.Text = ""
barName.Parent = barHolder

local barDamage = Instance.new("TextLabel")
barDamage.BackgroundTransparency = 1
barDamage.AnchorPoint = Vector2.new(1, 0)
barDamage.Position = UDim2.new(1, 0, 0, 0)
barDamage.Size = UDim2.new(0, 90, 0, 24)
barDamage.Font = SERIF
barDamage.TextSize = 21
barDamage.TextXAlignment = Enum.TextXAlignment.Right
barDamage.TextColor3 = RGB(255, 232, 186)
barDamage.TextStrokeTransparency = 0.45
barDamage.Text = ""
barDamage.Parent = barHolder

local barBack = Instance.new("Frame")
barBack.Position = UDim2.new(0, 0, 0, 28)
barBack.Size = UDim2.new(1, 0, 0, 11)
barBack.BackgroundColor3 = RGB(22, 14, 12)
barBack.BorderSizePixel = 0
barBack.Parent = barHolder
local barStroke = Instance.new("UIStroke")
barStroke.Color = RGB(118, 94, 60)
barStroke.Thickness = 1.5
barStroke.Parent = barBack

local barChip = Instance.new("Frame") -- the pale trailing chunk you just took off it
barChip.Size = UDim2.fromScale(1, 1)
barChip.BackgroundColor3 = RGB(232, 196, 128)
barChip.BorderSizePixel = 0
barChip.Parent = barBack

local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(1, 1)
barFill.BackgroundColor3 = RGB(168, 26, 24)
barFill.BorderSizePixel = 0
barFill.Parent = barBack
local barGradient = Instance.new("UIGradient")
barGradient.Color = ColorSequence.new(RGB(255, 255, 255), RGB(180, 180, 180))
barGradient.Rotation = 90
barGradient.Parent = barFill

local barFor = nil -- the boss the bar is showing
local shownShare, chipShare, chipHoldUntil = 1, 1, 0
local recentDamage, recentUntil = 0, 0

local function showBar(B)
	if barFor == B then
		return
	end
	barFor = B
	barGui.Enabled = B ~= nil
	if B then
		barName.Text = B.def.Name
		barName.TextTransparency = 1
		barName.TextStrokeTransparency = 1
		tween(barName, 1.2, { TextTransparency = 0, TextStrokeTransparency = 0.45 })
		local share = (B.model:GetAttribute("Health") or 1) / math.max(B.model:GetAttribute("MaxHealth") or 1, 1)
		shownShare, chipShare = share, share
		recentDamage, recentUntil = 0, 0
		barDamage.Text = ""
	end
end

local function stepBar(now, dt)
	local B = barFor
	if not B then
		return
	end
	local share = clamp((B.model:GetAttribute("Health") or 0) / math.max(B.model:GetAttribute("MaxHealth") or 1, 1), 0, 1)
	if share < shownShare - 1e-4 then
		chipHoldUntil = now + 0.55 -- the chip waits a moment before catching up
	end
	shownShare = share
	if now > chipHoldUntil then
		chipShare = math.max(share, chipShare - 0.9 * dt) -- drains at the same speed at any frame rate
	end
	chipShare = math.max(chipShare, share)
	barFill.Size = UDim2.fromScale(shownShare, 1)
	barChip.Size = UDim2.fromScale(chipShare, 1)
	barFill.BackgroundColor3 = B.phase2Look and RGB(196, 18, 30) or RGB(168, 26, 24)
	if now > recentUntil and recentDamage > 0 then
		recentDamage = 0
		barDamage.Text = ""
	end
end

----------------------------------------------------------------------
-- The victory banner
----------------------------------------------------------------------
local winGui = Instance.new("ScreenGui")
winGui.Name = "BossVictory"
winGui.ResetOnSpawn = false
winGui.DisplayOrder = 30
winGui.IgnoreGuiInset = true
winGui.Enabled = false
winGui.Parent = playerGui

local winBand = Instance.new("Frame")
winBand.AnchorPoint = Vector2.new(0.5, 0.5)
winBand.Position = UDim2.fromScale(0.5, 0.42)
winBand.Size = UDim2.new(1, 0, 0, 170)
winBand.BackgroundColor3 = RGB(0, 0, 0)
winBand.BackgroundTransparency = 0.25
winBand.BorderSizePixel = 0
winBand.Parent = winGui
local winFade = Instance.new("UIGradient")
winFade.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.2, 0.15),
	NumberSequenceKeypoint.new(0.8, 0.15),
	NumberSequenceKeypoint.new(1, 1),
})
winFade.Rotation = 90
winFade.Parent = winBand

local winTitle = Instance.new("TextLabel")
winTitle.BackgroundTransparency = 1
winTitle.AnchorPoint = Vector2.new(0.5, 0.5)
winTitle.Position = UDim2.fromScale(0.5, 0.42)
winTitle.Size = UDim2.new(1, 0, 0, 80)
winTitle.Font = SERIF
winTitle.TextSize = 70
winTitle.TextColor3 = RGB(255, 214, 120)
winTitle.TextStrokeColor3 = RGB(60, 36, 8)
winTitle.TextStrokeTransparency = 0.4
winTitle.Text = ""
winTitle.Parent = winBand

local winSub = Instance.new("TextLabel")
winSub.BackgroundTransparency = 1
winSub.AnchorPoint = Vector2.new(0.5, 0.5)
winSub.Position = UDim2.fromScale(0.5, 0.78)
winSub.Size = UDim2.new(1, 0, 0, 30)
winSub.Font = SERIF
winSub.TextSize = 26
winSub.TextColor3 = RGB(236, 226, 204)
winSub.TextStrokeTransparency = 0.5
winSub.RichText = true
winSub.Text = ""
winSub.Parent = winBand

local victoryAt = 0 -- when the last victory sting started (the music gets out of its way)
local function victory(floorId, gained, firstClear)
	local def = Config.Bosses[floorId]
	-- the sting: one clean shot of triumph, played flat so it's the same for everyone
	local sting = def and def.VictorySound and findSound(def.VictorySound)
	if sting then
		local s = sting:Clone()
		s.Looped = false
		s.Volume = (Config.Audio and Config.Audio.Victory) or 0.6
		s.SoundGroup = soundGroup("Music")
		s.Parent = game:GetService("SoundService")
		s:Play()
		victoryAt = os.clock()
		task.delay(math.max(tonumber(s.TimeLength) or 0, 1) + 1, function()
			s:Destroy()
		end)
	end
	winTitle.Text = string.upper((def and def.Short or "Boss") .. " vanquished")
	local line = "+" .. Config.format(gained or 0) .. " Power"
	if firstClear then
		line = line .. '     <font color="#ffd678">First clear!</font>'
	end
	winSub.Text = line
	winGui.Enabled = true
	winBand.BackgroundTransparency = 1
	winTitle.TextTransparency, winTitle.TextStrokeTransparency = 1, 1
	winSub.TextTransparency, winSub.TextStrokeTransparency = 1, 1
	winTitle.TextSize = 60
	task.delay(1.6, function() -- after the body has had a moment to collapse
		tween(winBand, 1.2, { BackgroundTransparency = 0.25 })
		tween(winTitle, 2.2, { TextTransparency = 0, TextStrokeTransparency = 0.4, TextSize = 70 }, Enum.EasingStyle.Sine)
		task.delay(0.9, function()
			tween(winSub, 1, { TextTransparency = 0, TextStrokeTransparency = 0.5 })
		end)
		task.delay(6, function()
			tween(winBand, 1.5, { BackgroundTransparency = 1 })
			tween(winTitle, 1.5, { TextTransparency = 1, TextStrokeTransparency = 1 })
			tween(winSub, 1.5, { TextTransparency = 1, TextStrokeTransparency = 1 })
			task.delay(1.6, function()
				winGui.Enabled = false
			end)
		end)
	end)
end

task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("BossRemotes", 60)
	local event = remotes and remotes:WaitForChild("BossEvent", 10)
	if event then
		event.OnClientEvent:Connect(function(kind, floorId, gained, firstClear)
			if kind == "Victory" then
				victory(floorId, gained, firstClear)
			end
		end)
	end
end)

----------------------------------------------------------------------
-- Keeping track of each boss on this screen
----------------------------------------------------------------------
local function rootGround(B)
	local root = B.model.PrimaryPart
	if not root then
		return B.vpos
	end
	return root.Position - V3(0, root.Size.Y / 2, 0)
end

local function track(model)
	if bosses[model] or not model:IsA("Model") then
		return
	end
	local floorId = model:GetAttribute("Floor")
	local def = floorId and Config.Bosses and Config.Bosses[floorId]
	if not def or not model.PrimaryPart then
		return
	end
	local B = {
		model = model,
		def = def,
		floor = floorId,
		body = buildBody(def),
		telegraphs = {},
		events = {},
		seenId = -1,
		slotsDone = 0,
		lastHealth = model:GetAttribute("Health") or 0,
		wobbles = {},
	}
	B.kind = def.Body == "Worm" and "Worm" or "Slime"
	-- what its attacks are made of: slime you can see into, or sand and rock
	if B.kind == "Worm" then
		B.fx = { color = WORM_SAND, deep = WORM_SAND_DEEP, rock = WORM_PLATE_DARK, material = Enum.Material.Sand, solid = true }
	else
		B.fx = { color = def.Color, deep = def.DeepColor, rock = def.DeepColor, material = Enum.Material.Glass, solid = false }
	end
	B.vpos = rootGround(B)
	if B.kind == "Worm" then
		trailReset(B)
	end
	local look = model.PrimaryPart.CFrame.LookVector
	B.vfacing = flat(look).Magnitude > 0.01 and flat(look).Unit or V3(0, 0, 1)
	B.phase2Look = (model:GetAttribute("Phase") or 1) >= 2
	B.crownGone = B.phase2Look
	if B.kind == "Worm" and B.phase2Look then
		collapseSeal(B, true, true) -- you've arrived after the seal already caved in
	end
	bosses[model] = B
	model.AncestryChanged:Connect(function()
		if not model.Parent and bosses[model] then
			for _, tele in ipairs(B.telegraphs) do
				tele.cleanup()
			end
			B.body.folder:Destroy()
			if barFor == B then
				showBar(nil)
			end
			bosses[model] = nil
		end
	end)
end

for _, m in ipairs(CollectionService:GetTagged("Boss")) do
	track(m)
end
CollectionService:GetInstanceAddedSignal("Boss"):Connect(track)

-- a new action began on the server
-- The worm's body flows from the shape it was in to its next one (see
-- applyWormPose). Pieces of it that were out of sight under the sand don't
-- flow: they simply come up in their new place, so nothing flies across.
local function startWormBlend(B, now)
	if not B.lastPoints then
		return
	end
	local floorY, gs = B.vpos.Y, B.segGirths or {}
	local hidden = {}
	for i, p in ipairs(B.lastPoints) do
		hidden[i] = p.Y + (gs[i] or B.lastGirth or 0) * 0.5 < floorY
	end
	-- (how long it takes is worked out on its first frame: see applyWormPose)
	B.blendFrom, B.blendGirth, B.blendUntil, B.blendHidden = table.clone(B.lastPoints), B.lastGirth, nil, hidden
end

local function onAction(B, name, t0, now)
	B.prevAction = B.action
	B.action, B.actionStart = name, t0
	B.events = {}
	B.slotsDone = 0
	local worm = B.kind == "Worm"
	if worm then
		startWormBlend(B, now)
		-- the news of a new move reaches your screen a moment after it began on
		-- the server. Its shape starts from the beginning anyway (a burst out of
		-- the sand really bursts up, instead of appearing half out) and plays a
		-- touch fast until it has caught up. (Arriving much later - you joined
		-- mid-move - it simply picks up where the server is.)
		local late = now - t0
		B.seenAt, B.lateBy = now, (late > 0 and late < 0.6) and late or 0
		B.stage = nil
		if name == "Reset" then
			B.resetUnder = B.model:GetAttribute("Submerged") == true
		end
	end
	if name == "Break" and now - t0 > B.def.BreakTime * 0.35 then
		B.phase2Look, B.crownGone = true, true -- joined late: it's already broken
		if worm then
			collapseSeal(B, true, true)
		end
	end
	if worm and name == "Dormant" then
		closeAllScars() -- asleep again: the floor is flat again
		B.sleepFace = nil -- (and it lies down facing the gate again)
	end
	if name == "Wake" or name == "Dormant" or name == "Reset" then
		B.phase2Look, B.crownGone = false, false
		if not worm then
			brightenPools(false)
		elseif name ~= "Reset" then
			collapseSeal(B, false) -- (once it's back under: not while it's still sinking)
		end
	end
	if name == "Break" and not worm then
		brightenPools(true)
	end
	local start = Starts[name]
	if start then
		start(B, t0)
	end
end

-- "HIT IT!": a big flashing 8-bit sign over the worm whenever it's out of
-- the sand and can be hurt - so you always know when your window is open.
local function hitSign(B, state)
	if B.kind ~= "Worm" or not B.body then
		return
	end
	local head = B.body.segments and B.body.segments[#B.body.segments]
	head = head and head.part
	if not head then
		return
	end
	local m = B.model
	local open = state == "Fighting" and not m:GetAttribute("Submerged") and not m:GetAttribute("Invulnerable")
		and player:GetAttribute("SpireFloor") == B.floor
	if not B.hitGui then
		local bb = Instance.new("BillboardGui")
		bb.Name = "HitIt"
		bb.Size = UDim2.fromOffset(220, 70)
		bb.StudsOffsetWorldSpace = V3(0, 18, 0)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.MaxDistance = 400
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.Font = Enum.Font.Arcade
		l.Text = "HIT IT!"
		l.TextScaled = true
		l.TextColor3 = RGB(254, 231, 97)
		l.Parent = bb
		local st = Instance.new("UIStroke")
		st.Thickness = 4
		st.Color = RGB(24, 20, 37)
		st.Parent = l
		B.hitGui, B.hitLabel = bb, l
		bb.Parent = playerGui
	end
	B.hitGui.Adornee = head
	B.hitGui.Enabled = open == true
	if open then
		-- flashes yellow / red in chunky steps, and bounces
		local k = math.floor(os.clock() * 6) % 2
		B.hitLabel.TextColor3 = k == 0 and RGB(254, 231, 97) or RGB(255, 0, 68)
		B.hitGui.StudsOffsetWorldSpace = V3(0, 18 + (k == 0 and 0 or 1.2), 0)
	end
end

local function stepBoss(B, now, dt)
	hitSign(B, B.model:GetAttribute("State") or "Dormant")
	local m = B.model
	local id = m:GetAttribute("ActionId") or 0
	if id ~= B.seenId then
		B.seenId = id
		onAction(B, m:GetAttribute("Action") or "Idle", m:GetAttribute("ActionStart") or now, now)
	end
	local action = m:GetAttribute("Action") or "Idle"
	local state = m:GetAttribute("State") or "Dormant"
	local t = now - (B.actionStart or now)

	-- positions the server fills in as the action goes on
	local spawnSlot = SlotSpawns[action]
	if spawnSlot then
		local k = m:GetAttribute("ActK") or 0
		while B.slotsDone < k do
			B.slotsDone = B.slotsDone + 1
			local spot = m:GetAttribute(SLOT_NAMES[B.slotsDone])
			if typeof(spot) == "Vector3" then
				spawnSlot(B, B.slotsDone, spot, B.actionStart)
			end
		end
	end

	-- one-off moments that are due (ones long past are skipped, so arriving
	-- late doesn't set off a pile of old explosions)
	for i = #B.events, 1, -1 do
		local ev = B.events[i]
		if now >= ev.at then
			table.remove(B.events, i)
			if now - ev.at < 0.5 then
				ev.fn()
			end
		end
	end

	-- the pose: breathing (and crawling, when it moves), reshaped by the action
	local P = { lift = 0, sx = 1, sy = 1, sz = 1, lean = 0, mouth = 0, shake = 0, eyes = 1, sink = 0, flare = 0 }
	local breathe = math.sin(now * 2 * math.pi / 2.4)
	P.sy, P.sx = 1 + 0.035 * breathe, 1 - 0.02 * breathe
	P.sz = P.sx
	if m:GetAttribute("Moving") then
		local c = math.sin(now * 2 * math.pi * 1.3)
		P.sy = P.sy + 0.06 * c
		P.sz = P.sz + 0.05 * c
		P.lean = 0.05 + 0.06 * c
	end
	B.humpEvery = nil -- (an under-the-sand pose sets it)
	local shape = Poses[action]
	if state == "Dormant" then
		shape = Poses.Dormant
	elseif state == "Dead" then
		shape = Poses.Death
	end
	if shape then
		if B.kind == "Worm" then
			local catch = B.lateBy and B.lateBy > 0 and clamp(1 - (now - B.seenAt) / 0.5, 0, 1) or 0
			shape(B, t - B.lateBy * catch, P)
			-- a new stage inside the same move (a leap leaving the sand, a coil
			-- closing round you): its body flows into it rather than jumping
			if P.stage ~= B.stage then
				if B.stage ~= nil and P.stage ~= nil then
					startWormBlend(B, now)
				end
				B.stage = P.stage
			end
		else
			shape(B, t, P)
		end
	end

	-- being hit makes it wobble
	local hp = m:GetAttribute("Health") or 0
	if hp < B.lastHealth then
		local max = math.max(m:GetAttribute("MaxHealth") or 1, 1)
		table.insert(B.wobbles, { t0 = now, amp = clamp((B.lastHealth - hp) / max * 9, 0.05, 0.14) })
		B.flashAt = os.clock() -- and blanch for a blink, so every landed hit shows
		if barFor == B then
			recentDamage = recentDamage + (B.lastHealth - hp)
			recentUntil = now + 2.2
			barDamage.Text = Config.format(recentDamage)
		end
	end
	B.lastHealth = hp
	for i = #B.wobbles, 1, -1 do
		local w = B.wobbles[i]
		local e = now - w.t0
		if e > 1 then
			table.remove(B.wobbles, i)
		else
			local s = w.amp * spring(e, 6, 19)
			P.sy = P.sy - s
			P.sx = P.sx + s * 0.8
			P.sz = P.sz + s * 0.8
		end
	end

	-- where it is: smoothed from the server's position, or exactly on its arc
	-- while it's lunging or hopping (the worm glides between updates - see
	-- glideWorm)
	local ground = rootGround(B)
	local glided = (B.kind == "Worm") and glideWorm(B, now, ground) or nil
	if P.override then
		B.vpos = V3(P.override.X, ground.Y, P.override.Z)
	elseif glided then
		B.vpos = V3(glided.X, ground.Y, glided.Z)
	else
		B.vpos = B.vpos:Lerp(ground, 1 - math.exp(-dt * 14))
	end
	local look = flat(m.PrimaryPart.CFrame.LookVector)
	if look.Magnitude > 0.01 then
		local blended = B.vfacing:Lerp(look.Unit, 1 - math.exp(-dt * 12))
		B.vfacing = blended.Magnitude > 0.01 and blended.Unit or look.Unit
	end

	applyPose(B, P, B.vpos, P.facing or B.vfacing, now, dt)
	if B.kind == "Worm" then
		trailRecord(B) -- the path its body follows under the sand
		stepHumps(B)
	end
	if B.def.Weather == "Sandstorm" then
		stepStorm(B, dt)
	end

	-- warnings in the world
	for i = #B.telegraphs, 1, -1 do
		local tele = B.telegraphs[i]
		if not tele.update(now) then
			tele.cleanup()
			table.remove(B.telegraphs, i)
		end
	end

	-- the bar, while you're in its arena and it's awake
	local here = player:GetAttribute("SpireFloor") == B.floor
	local awake = state == "Waking" or state == "Fighting" or state == "Transition"
	if B.kind == "Worm" then
		stepWormSenses(B, dt, here, awake, state) -- the rumble and the whirlpool
	end
	if here and awake then
		showBar(B)
	elseif barFor == B and not (here and awake) then
		showBar(nil)
	end

	-- you can't walk through it: nudged out to the edge of its body
	if B.kind == "Worm" then
		-- (every piece of it that's out of the sand - see pushOutOfWorm)
		if here and (awake or state == "Dormant") then
			local hrp = myRoot()
			if hrp then
				pushOutOfWorm(B, hrp, P)
			end
		end
	elseif here and awake then
		local hrp = myRoot()
		if hrp then
			local offset = flat(hrp.Position - B.vpos)
			local minimum = B.def.Size / 2 * P.sx + 1.2
			local solid = P.lift < 4 -- in the air, you can run under it
			if offset.Magnitude < minimum and solid then
				local out = offset.Magnitude > 0.05 and offset.Unit or B.vfacing
				local target = B.vpos + out * minimum
				hrp.CFrame = CFrame.new(V3(target.X, hrp.Position.Y, target.Z)) * (hrp.CFrame - hrp.Position)
			end
		end
	end
end

----------------------------------------------------------------------
-- The fight's music
----------------------------------------------------------------------
-- Plays the Sound named in the boss's Config (Music = "Boss": the one sitting in
-- SoundService) while you're in its arena and it's awake. Only on your screen,
-- so the lobby never hears it. It swells in when the boss rises and fades out
-- when it dies, sleeps again, or you leave.
local SoundService = game:GetService("SoundService")
local MUSIC_VOLUME = (Config.Audio and Config.Audio.BossMusic) or 0.42
local music, musicFor, musicLevel = nil, nil, 0
local musicVolume = MUSIC_VOLUME -- (a boss can have its own: MusicVolume in its Config)

local diedAt = -math.huge -- when you last died (the fight's music bows out)
local function stepMusic(dt)
	local want, def = nil, nil
	-- dead: the music slips away under the YOU DIED screen
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local dead = hum ~= nil and hum.Health <= 0
	if dead and os.clock() - diedAt > 10 then
		diedAt = os.clock()
	end
	for model, B in pairs(bosses) do
		local state = model:GetAttribute("State")
		if not dead and player:GetAttribute("SpireFloor") == model:GetAttribute("Floor")
			and (state == "Waking" or state == "Fighting" or state == "Transition") then
			want, def = model, B.def
		end
	end
	if want and musicFor ~= want then
		-- a new fight: start the track from the top
		local template = def.Music and findSound(def.Music)
		if not template then
			template = findSound((Config.Bosses[1] and Config.Bosses[1].Music) or "Boss") -- no track of its own yet
		end
		if music then
			music:Destroy()
			music = nil
		end
		if template and template:IsA("Sound") then
			music = template:Clone()
			music.Name = "BossMusicPlaying"
			music.Looped = true
			music.Volume = 0
			music.SoundGroup = soundGroup("Music")
			music.Parent = SoundService
			music:Play()
		end
		musicFor, musicLevel = want, 0
		musicVolume = def.MusicVolume or MUSIC_VOLUME
	end
	-- in over about a second and a half, out over about two and a half
	local target = want and 1 or 0
	-- (after a kill the fight's music bows out in half a second, for the sting)
	local out = 0.45
	if os.clock() - victoryAt < 3 then
		out = 6 -- a kill: out of the sting's way in half a second
	elseif dead then
		out = 2.2 -- your death: a smooth fade of about a second and a half
	end
	musicLevel = musicLevel + (target - musicLevel) * math.min(1, dt * (want and 0.7 or out))
	if music then
		music.Volume = musicVolume * musicLevel
		if not want and musicLevel < 0.01 then
			music:Destroy()
			music, musicFor = nil, nil
		end
	elseif not want then
		musicFor = nil
	end
end

-- The lobby's music: plays whenever you're not in a Spire arena, fading out as
-- you travel in (the arena is silent until its boss wakes) and back in when you
-- return. It keeps its place, so coming back doesn't restart the song.
-- Config.LobbyMusic can be one song or a list: a list plays in turn, each
-- song to its end and then the next, round and round.
local LOBBY_MUSIC = Config.LobbyMusic or "Dreaming in the city"
if type(LOBBY_MUSIC) == "string" then
	LOBBY_MUSIC = { LOBBY_MUSIC }
end
-- (shuffled: a different order every time you join; after the last song
-- it shuffles again, never starting on the song that just played)
local shuffleRng = Random.new() -- (a fresh random seed every time you join)
local function shuffle(list, notFirst)
	local out = table.clone(list)
	for i = #out, 2, -1 do
		local j = shuffleRng:NextInteger(1, i)
		out[i], out[j] = out[j], out[i]
	end
	if notFirst and #out > 1 and out[1] == notFirst then
		out[1], out[#out] = out[#out], out[1]
	end
	return out
end
LOBBY_MUSIC = shuffle(LOBBY_MUSIC)
local lobbyMusic, lobbyLevel, lobbyVolume = nil, 0, 0.15
local lobbyTrack = 0

-- start the next song on the list that's actually in SoundService
local function nextLobbySong()
	if lobbyMusic then
		lobbyMusic:Destroy()
		lobbyMusic = nil
	end
	for _ = 1, #LOBBY_MUSIC do
		if lobbyTrack >= #LOBBY_MUSIC then
			LOBBY_MUSIC = shuffle(LOBBY_MUSIC, LOBBY_MUSIC[#LOBBY_MUSIC])
			lobbyTrack = 0
		end
		lobbyTrack = lobbyTrack + 1
		local template = SoundService:FindFirstChild(LOBBY_MUSIC[lobbyTrack])
		if template and template:IsA("Sound") then
			lobbyVolume = (Config.Audio and Config.Audio.LobbyMusic) or 0.25
			local song = template:Clone()
			song.Name = "LobbyMusicPlaying"
			song.Looped = #LOBBY_MUSIC == 1 -- (just one song: it loops)
			song.Volume = lobbyVolume * lobbyLevel
			song.SoundGroup = soundGroup("Music")
			song.Parent = SoundService
			song.Ended:Connect(function()
				if lobbyMusic == song then
					task.defer(nextLobbySong)
				end
			end)
			lobbyMusic = song
			song:Play()
			return
		end
	end
end

local function stepLobbyMusic(dt)
	local want = player:GetAttribute("SpireFloor") == nil
	if want and not lobbyMusic then
		nextLobbySong()
	end
	if not lobbyMusic then
		return
	end
	lobbyLevel = lobbyLevel + ((want and 1 or 0) - lobbyLevel) * math.min(1, dt * (want and 0.5 or 1.2))
	lobbyMusic.Volume = lobbyVolume * lobbyLevel
	if want and not lobbyMusic.IsPlaying and lobbyMusic.TimePosition > 0 then
		lobbyMusic:Resume()
	elseif not want and lobbyLevel < 0.01 and lobbyMusic.IsPlaying then
		lobbyMusic:Pause() -- paused, not stopped: it carries on where it left off
	end
end

----------------------------------------------------------------------
-- Acid rain
----------------------------------------------------------------------
-- A thin green rain that starts when the boss rises and stops when the fight
-- does (it dies, sleeps again, you leave or you fall). Kept deliberately
-- subtle: fine streaks, a light patter of splashes on the floor around you, a
-- faint green cast over everything. It follows your camera, so it's always
-- falling where you're looking and nowhere else - only on your screen.
local RAIN = Config.AcidRain or {}
local RAIN_COLOR = RAIN.Color or RGB(150, 255, 110)
local RAIN_RATE = RAIN.Rate or 900 -- drops a second at full strength
local SPLASH_RATE = RAIN.Splashes or 160
local RAIN_TINT = RAIN.Tint or 0.2 -- how green the world turns (0 = not at all)

local rainCloud = Instance.new("Part")
rainCloud.Name = "AcidRainCloud"
rainCloud.Size = V3(64, 1, 64) -- a patch around you: dense where you look
rainCloud.Transparency = 1
rainCloud.Anchored = true
rainCloud.CanCollide = false
rainCloud.CanQuery = false
rainCloud.CanTouch = false
rainCloud.CastShadow = false
rainCloud.Parent = fxFolder

local drops = Instance.new("ParticleEmitter")
drops.Name = "Drops"
-- a soft round blob, stretched into a streak (a sparkle texture is mostly
-- empty space: stretched thin, almost nothing of it is left to see)
drops.Texture = "rbxasset://textures/particles/smoke_main.dds"
drops.Color = ColorSequence.new(RAIN_COLOR)
drops.LightEmission = 0.55
drops.LightInfluence = 0.2
drops.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp -- faces you, but stays upright, so the stretch is vertical
drops.Size = NumberSequence.new(0.32)
drops.Squash = NumberSequence.new(5) -- tall thin streaks (positive = stretched up and down)
drops.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.08, 0.3),
	NumberSequenceKeypoint.new(1, 0.4),
})
drops.Speed = NumberRange.new(55, 65)
drops.Lifetime = NumberRange.new(0.5, 0.55) -- about the fall to the floor
drops.EmissionDirection = Enum.NormalId.Bottom
drops.SpreadAngle = Vector2.new(0, 0) -- straight down, matching the upright streaks
drops.Shape = Enum.ParticleEmitterShape.Box
drops.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
drops.Rate = 0
drops.Parent = rainCloud

local puddleFloor = Instance.new("Part")
puddleFloor.Name = "AcidRainSplashes"
puddleFloor.Size = V3(50, 0.2, 50)
puddleFloor.Transparency = 1
puddleFloor.Anchored = true
puddleFloor.CanCollide = false
puddleFloor.CanQuery = false
puddleFloor.CanTouch = false
puddleFloor.CastShadow = false
puddleFloor.Parent = fxFolder

local splashes = Instance.new("ParticleEmitter")
splashes.Name = "Splashes"
splashes.Texture = "rbxasset://textures/particles/smoke_main.dds"
splashes.Color = ColorSequence.new(RAIN_COLOR)
splashes.LightEmission = 0.4
splashes.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.1),
	NumberSequenceKeypoint.new(1, 0.7),
})
splashes.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.45),
	NumberSequenceKeypoint.new(1, 1),
})
splashes.Speed = NumberRange.new(2, 4)
splashes.Lifetime = NumberRange.new(0.15, 0.25)
splashes.EmissionDirection = Enum.NormalId.Top
splashes.SpreadAngle = Vector2.new(70, 70)
splashes.Shape = Enum.ParticleEmitterShape.Box
splashes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
splashes.Rate = 0
splashes.Parent = puddleFloor

local rainGrade = Instance.new("ColorCorrectionEffect")
rainGrade.Name = "AcidRainTint"
rainGrade.TintColor = RGB(255, 255, 255)
rainGrade.Enabled = false
rainGrade.Parent = game:GetService("Lighting")

local rainLevel = 0
local rainWarned = false
local rainAnnounced = false
local rainSound = nil
local function stepRain(dt)
	-- is there a fight on, and are you alive in it?
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local alive = hum ~= nil and hum.Health > 0
	local fight = nil
	for model, B in pairs(bosses) do
		local state = model:GetAttribute("State")
		if alive and player:GetAttribute("SpireFloor") == model:GetAttribute("Floor")
			and (state == "Waking" or state == "Fighting" or state == "Transition")
			and (B.def.Weather or "AcidRain") == "AcidRain" then
			fight = B
		end
	end
	-- it comes on over a few seconds and eases off over a few more
	rainLevel = rainLevel + ((fight and 1 or 0) - rainLevel) * math.min(1, dt * (fight and 0.5 or 0.8))
	if rainLevel < 0.005 then
		rainLevel = 0
	end
	local on = rainLevel > 0
	if fight and not rainAnnounced then
		rainAnnounced = true
		print("[BossClient] acid rain started")
	elseif not fight then
		rainAnnounced = false
	end
	drops.Rate = RAIN_RATE * rainLevel
	splashes.Rate = SPLASH_RATE * rainLevel
	rainGrade.Enabled = on
	if on then
		local g = RAIN_TINT * rainLevel
		rainGrade.TintColor = RGB(255 - math.floor(70 * g), 255, 255 - math.floor(90 * g))
		rainGrade.Saturation = -0.1 * rainLevel
	end
	-- the cloud rides above your camera, the splashes on the floor below it
	local cam = Workspace.CurrentCamera
	if on and cam then
		local focusCF = cam.Focus or cam.CFrame
		local focus = focusCF and focusCF.Position or (fight and rootGround(fight)) or V3()
		-- centred a little ahead of you, so it fills the view you're actually looking at
		local look = cam.CFrame.LookVector
		local ahead = V3(look.X, 0, look.Z)
		if ahead.Magnitude > 0.01 then
			focus = focus + ahead.Unit * 14
		end
		local floorY = fight and rootGround(fight).Y or (focus.Y - 4)
		rainCloud.CFrame = CFrame.new(focus.X, floorY + 30, focus.Z) * CFrame.Angles(0, 0, math.rad(4))
		puddleFloor.CFrame = CFrame.new(focus.X, floorY + 0.15, focus.Z)
	end
	-- an optional rain loop: drop a Sound named "Acid Rain" into SoundService
	local loop = findSound(RAIN.Sound or "Acid Rain")
	if on and loop and not rainSound then
		rainSound = loop:Clone()
		rainSound.Looped = true
		rainSound.Volume = 0
		rainSound.SoundGroup = soundGroup("Effects")
		rainSound.Parent = game:GetService("SoundService")
		rainSound:Play()
	end
	if rainSound then
		rainSound.Volume = (RAIN.Volume or 0.25) * rainLevel
		if not on then
			rainSound:Destroy()
			rainSound = nil
		end
	end
end

RunService.RenderStepped:Connect(function(dt)
	local now = serverNow()
	for _, B in pairs(bosses) do
		-- each boss on its own: if drawing one ever errors, the other still draws
		local ok, err = pcall(stepBoss, B, now, dt)
		if not ok and not B.warned then
			B.warned = true
			warn("[BossClient] drawing " .. B.def.Short .. " failed: " .. tostring(err))
		end
	end
	stepBar(now, dt)
	stepMusic(dt)
	pcall(stepScars)
	-- weather is decoration: if it ever fails, the fight carries on without it
	local ok, err = pcall(stepRain, dt)
	if not ok and not rainWarned then
		rainWarned = true
		warn("[BossClient] acid rain stopped: " .. tostring(err))
	end
	stepLobbyMusic(dt)
end)

-- (if this line is missing from the Output window when you play, this script
-- failed to load - the red text just above it says why)
print("[BossClient] ready")
