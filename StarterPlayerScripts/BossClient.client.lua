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
	elseif key == "Spit" or key == "Erupt" or key == "Slam" then
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
	local k = 1 - (x / halfX) ^ 2 - (y / halfY) ^ 2
	return -halfZ * math.sqrt(math.max(k, 0.02)) - 0.05
end

-- Puts every part of the body where this frame's pose says.
local function applySlimePose(B, P, ground, facing, t, dt)
	local def, body = B.def, B.body
	local D = def.Size
	local H = D * 0.85 * P.sy
	local halfX, halfY, halfZ = D * P.sx / 2, H / 2, D * P.sz / 2
	local sinkDepth = P.sink * H * 0.85
	local fade = P.fade or 0
	local phase2 = B.phase2Look

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
	body.inner.Size = body.shell.Size * 0.84
	body.inner.CFrame = center * CFrame.new(0, -H * 0.06, 0)
	body.inner.Transparency = lerp(phase2 and 0.72 or 0.55, 1, fade)

	-- the core lags behind the body: a little secondary motion reads as jelly
	local coreSize = D * (phase2 and 0.47 or 0.36) * (1 + 0.05 * math.sin(t * 2.7)) * (P.coreScale or 1)
	local coreWant = center * CFrame.new(0, -H * 0.04 + math.sin(t * 1.9) * 0.4, 0)
	B.corePos = B.corePos and B.corePos:Lerp(coreWant.Position, 1 - math.exp(-dt * 7)) or coreWant.Position
	body.core.Size = V3(coreSize, coreSize * 0.95, coreSize)
	body.core.CFrame = CFrame.new(B.corePos) * (center - center.Position)
	body.core.Transparency = lerp(phase2 and 0.4 or 0.3, 1, clamp(fade * 1.3 - 0.2, 0, 1))

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
		brow.Transparency = lerp(0.12, 1, fade)
	end
	-- the other eyes, each blinking on its own slow clock
	for _, e in ipairs(body.smallEyes) do
		local x, y = e.x * halfX * 0.86, e.y * halfY * 0.86
		local blink = ((os.clock() * e.rate + e.seed) % 1) < 0.07 and 0 or 1
		local open = eyeOpen * blink
		local z = onSurface(halfX, halfY, halfZ, x, y)
		local size = D * 0.055 * e.size
		e.part.Size = V3(size, math.max(size * 0.8 * open, 0.05), size * 0.6)
		e.part.CFrame = center * CFrame.new(x, y, z) * CFrame.Angles(0, math.atan2(x, -z) * 0.8, 0)
		e.part.Transparency = open < 0.05 and 1 or 0
	end

	-- the maw
	local my = -H * 0.12
	local mouthW = D * 0.46 * P.sx
	local mouthH = math.max(D * (0.03 + 0.24 * P.mouth), 0.05)
	local mz = onSurface(halfX, halfY, halfZ, 0, my)
	body.mouth.Size = V3(mouthW, mouthH, D * 0.08)
	body.mouth.CFrame = center * CFrame.new(0, my - D * 0.04 * P.mouth, mz)
	body.mouth.Transparency = lerp(0.05, 1, fade)
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
			c.part.Transparency = fade
		end
	end
	-- what's inside, circling
	for _, d in ipairs(body.debris) do
		local a = d.angle + t * d.spin * (phase2 and 1.8 or 1)
		local r = D * 0.23
		d.part.Size = d.size
		d.part.CFrame = center * CFrame.new(math.cos(a) * r * P.sx, H * d.height, math.sin(a) * r * P.sz) * CFrame.Angles(t * d.spin, a, t * 0.4)
		d.part.Transparency = lerp(0.1, 1, fade)
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
	for _, sk in ipairs(body.skirt) do
		local size = D * sk.size * (1 + 0.5 * math.max(P.sx - 1, 0)) * (1 - 0.3 * P.sink) * spread
		local r = footW * 0.43
		local pos = base * CFrame.new(math.cos(sk.angle) * r, size * 0.3 - sinkDepth * 0.3 + P.lift * 0.96, math.sin(sk.angle) * r * P.sz / P.sx)
		sk.part.Size = V3(size, size * 0.72, size)
		sk.part.CFrame = pos
		sk.part.Transparency = lerp(phase2 and 0.42 or 0.3, 1, fade)
	end
	-- drips lengthen and snap back
	for _, d in ipairs(body.drips) do
		if d.phase2 and not phase2 then
			d.part.Transparency = 1
		else
			local len = 1.5 + 2.2 * ((t * 0.45 + d.phase) % 1)
			local x, z = math.cos(d.angle) * halfX * 0.97, math.sin(d.angle) * halfZ * 0.97
			local top = center * CFrame.new(x, -H * 0.02, z)
			d.part.Size = V3(len, 0.55, 0.55)
			d.part.CFrame = top * CFrame.new(0, -len / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
			d.part.Transparency = lerp(0.18, 1, fade)
		end
	end
	-- its shadow on the floor: widens as it rears up, marking where it will land
	local shadowD = P.shadowD or (D * 0.95 * P.sx)
	placeDisc(body.shadow, onFloor(ground) + V3(0, 0.08, 0), shadowD, 0.1)
	body.shadow.Transparency = lerp(P.shadowDark and (0.62 - 0.3 * P.shadowDark) or 0.62, 1, math.max(fade, P.sink))
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
local WORM_SEGMENTS = 14
local WORM_SAND = RGB(224, 188, 128) -- the arena's sand, for everything it throws up
local WORM_SAND_DEEP = RGB(122, 92, 58) -- churned-up quicksand
local WORM_PLATE = RGB(156, 124, 88)
local WORM_PLATE_DARK = RGB(126, 100, 72)
local WORM_TEETH = 12 -- round the rim of the maw
local WORM_JAWS = 3
local WORM_EYES = 8

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

local function applyWormPose(B, P, ground, facing, t, dt)
	local def, body = B.def, B.body
	local D = def.Size
	local fade = P.fade or 0
	local phase2 = B.phase2Look
	local sink = clamp(P.sink or 0, 0, 1)
	local ridge = clamp(P.ridge or 0, 0, 1)

	-- all the way under and nothing moving on the surface: it's already hidden
	-- where it last was, so there's nothing to do (the dunes are a long way
	-- from the lobby, and every screen runs this every frame)
	if (sink >= 0.999 and ridge < 0.02 and fade <= 0) or fade >= 1 then
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

	-- how tall it stands and how thick it is (squash and stretch, toned down:
	-- it's a worm, not a jelly)
	local H = D * 1.35 * (1 + (P.sy - 1) * 0.8) + P.lift * 1.1
	local girth = D * 0.64 * (1 + (P.sx - 1) * 0.6)
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

	-- the segments
	local points = {}
	local S0 = 0.08
	for i = 1, WORM_SEGMENTS do
		local s = S0 + (1 - S0) * (i - 1) / (WORM_SEGMENTS - 1)
		points[i] = { s = s, pos = world(bezier(c0, c1, c2, c3, s)), along = slope(bezierSlope(c0, c1, c2, c3, s)) }
	end
	local frames, girths, lengths = {}, {}, {}
	for i, pt in ipairs(points) do
		local prev = points[i - 1] and (pt.pos - points[i - 1].pos).Magnitude or 0
		local nxt = points[i + 1] and (points[i + 1].pos - pt.pos).Magnitude or 0
		local g = girth * (1.06 - 0.16 * pt.s)
		local len = math.max(prev, nxt) * 1.75
		if i == WORM_SEGMENTS then
			-- the head: broader than its neck, a hood over the maw
			g = g * 1.2
			len = math.max(len, g * 1.2)
		end
		local along = pt.along.Magnitude > 1e-4 and pt.along.Unit or U
		local cf = frameAlong(pt.pos, along, R:Cross(along)) -- its top is its back
		frames[i], girths[i], lengths[i] = cf, g, len
		local seg = body.segments[i]
		seg.part.Size = V3(g, g * 0.96, len)
		seg.part.CFrame = cf
		local c = phase2 and seg.color:Lerp(def.DeepColor, 0.2) or seg.color
		seg.part.Color = c:Lerp(RGB(255, 240, 214), 0.45 * flash)
		seg.part.Transparency = fade
	end

	-- the creases: dark, until its armour is gone and they burn
	local heartColor = def.HeartColor or RGB(255, 90, 40)
	for i, seam in ipairs(body.seams) do
		local a, b = frames[i], frames[i + 1]
		local g = (girths[i] + girths[i + 1]) / 2 * 0.84
		seam.Size = V3(g, g * 0.96, 1.3)
		seam.CFrame = frameAlong((a.Position + b.Position) / 2, b.Position - a.Position, a.UpVector)
		if phase2 then
			seam.Material = Enum.Material.Neon
			seam.Color = heartColor:Lerp(RGB(255, 214, 140), 0.25 + 0.25 * math.sin(t * 3 + i))
		else
			seam.Material = Enum.Material.SmoothPlastic
			seam.Color = def.DeepColor
		end
		seam.Transparency = fade
	end

	-- the armour, until it's blasted off: scales down the ridge of its back
	-- (thick end toward the tail, so they overlap) and plates on its flanks
	for _, pl in ipairs(body.plates) do
		if B.crownGone then
			pl.part.Transparency = 1
		else
			local cf, g, len = frames[pl.seg], girths[pl.seg], lengths[pl.seg]
			if pl.side == 0 then
				local h = g * (pl.seg == WORM_SEGMENTS and 0.15 or 0.2)
				pl.part.Size = V3(g * 0.3, h, len * 0.62)
				pl.part.CFrame = cf * CFrame.new(0, g * 0.46 + h / 2 - g * 0.04, len * 0.08)
			else
				pl.part.Size = V3(g * 0.3, g * 0.06, len * 0.5)
				pl.part.CFrame = cf * CFrame.Angles(0, 0, pl.side * 0.8) * CFrame.new(0, g * 0.47, 0)
			end
			pl.part.Transparency = fade
		end
	end

	-- the head
	local headCF = frames[WORM_SEGMENTS]
	local gH, lenH = girths[WORM_SEGMENTS], lengths[WORM_SEGMENTS]
	local T, top, side = headCF.LookVector, headCF.UpVector, headCF.RightVector
	local mouth = clamp(P.mouth, 0, 1)
	local rimR = gH * 0.27
	local mawAt = headCF.Position + T * (lenH / 2 * 0.8)
	B.mawPos = mawAt -- (what it spits from)
	body.maw.Size = V3(0.5, rimR * 2, rimR * 2)
	body.maw.CFrame = CFrame.fromMatrix(mawAt, T, top, T:Cross(top))
	body.maw.Transparency = fade

	-- the heart in its throat: two beats and a rest, faster once its armour is
	-- gone, faster again when it's nearly dead
	local rate = phase2 and (health <= def.DesperateAt and 2.4 or 1.7) or 1.1
	local beatT = (os.clock() * rate) % 1
	local beat = math.exp(-((beatT - 0.05) / 0.06) ^ 2) + 0.6 * math.exp(-((beatT - 0.24) / 0.06) ^ 2)
	local heartSize = gH * (phase2 and 0.2 or 0.15) * (1 + 0.2 * beat + 0.3 * P.flare) * math.min(P.coreScale or 1, 1.3)
	body.heart.Size = V3(heartSize, heartSize, heartSize * 0.6)
	body.heart.CFrame = CFrame.fromMatrix(mawAt + T * 0.35, side, top, -T)
	body.heart.Transparency = clamp(fade * 1.5, 0, 1)
	body.heart.Color = heartColor:Lerp(RGB(255, 236, 190), 0.35 * beat + 0.4 * P.flare)
	body.light.Brightness = lerp((phase2 and 2.4 or 1.2) + 0.6 * beat + P.flare * 1.8, 0, math.max(fade, sink))
	body.light.Range = D * (phase2 and 1.6 or 1.1)

	-- teeth round the rim, pointing in at the throat
	for _, tooth in ipairs(body.teeth) do
		local radial = side * math.cos(tooth.angle) + top * math.sin(tooth.angle)
		local len = gH * 0.15 * tooth.long * (0.85 + 0.3 * mouth)
		local dir = (T * 0.45 - radial).Unit
		local base = mawAt + radial * (rimR * 0.96) + T * 0.2
		tooth.part.Size = V3(gH * 0.05, len, gH * 0.05)
		tooth.part.CFrame = CFrame.fromMatrix(base + dir * (len / 2), T:Cross(radial), dir)
		tooth.part.Transparency = clamp(fade * 1.2, 0, 1)
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
		jaw.part.Size = V3(gH * 0.32, gH * 0.12, jawLen)
		jaw.part.CFrame = CFrame.fromMatrix(hinge + dir * (jawLen / 2), across, out, -dir)
		jaw.part.Transparency = fade
		for f, fang in ipairs(jaw.fangs) do
			local len = gH * 0.1 * (1.15 - f * 0.12)
			local at = hinge + dir * (jawLen * (0.25 + f * 0.18)) - out * (gH * 0.04)
			fang.Size = V3(gH * 0.045, len, gH * 0.045)
			fang.CFrame = CFrame.fromMatrix(at - out * (len / 2), across, -out)
			fang.Transparency = clamp(fade * 1.2, 0, 1)
		end
	end

	-- its eyes, in a ring round the head behind the jaws
	local eyeOpen = clamp(P.eyes, 0, 1) * (1 - fade)
	local ringAt = headCF.Position + T * (lenH / 2 * 0.42)
	local ringR = gH / 2 * 0.96 * math.sqrt(1 - 0.42 ^ 2) * 0.97
	for _, e in ipairs(body.eyes) do
		local radial = side * math.cos(e.angle) + top * math.sin(e.angle)
		local blink = ((os.clock() * e.rate + e.seed) % 1) < 0.06 and 0 or 1
		local open = eyeOpen * blink
		local size = e.size * (1 + 0.35 * P.flare)
		e.part.Size = V3(size, math.max(size * open, 0.05), size * 0.7)
		e.part.CFrame = CFrame.fromMatrix(ringAt + radial * ringR, T:Cross(radial), T, radial)
		e.part.Transparency = open < 0.05 and 1 or 0
		e.part.Color = def.EyeColor:Lerp(RGB(255, 255, 255), clamp(P.flare, 0, 1) * 0.4)
	end

	-- the mound of sand it comes out of
	local out = 1 - sink
	local floorAt = onFloor(ground)
	local collarW = D * 1.2 * (1 + (P.sx - 1) * 0.4)
	local collarH = 9 * out * (1 + 0.3 * crash)
	body.collar.Size = V3(collarW, math.max(collarH, 0.05), collarW)
	body.collar.CFrame = CFrame.new(floorAt - V3(0, collarH * 0.12, 0))
	body.collar.Transparency = (collarH < 0.3) and 1 or fade

	-- swimming under the sand: a ridge ploughing along the floor
	if ridge > 0.02 then
		local rh = 6.5 * ridge
		body.ridge.Size = V3(D * 1.05, rh, D * 1.6)
		body.ridge.CFrame = CFrame.lookAt(floorAt, floorAt + F) * CFrame.new(0, rh * 0.12, 0)
		body.ridge.Transparency = 0
	else
		body.ridge.Transparency = 1
	end

	-- its shadow: widens as it rears up, marking where it'll come down
	local shadowD = P.shadowD or (D * 1.25 * (1 + (P.sx - 1) * 0.4))
	placeDisc(body.shadow, floorAt + V3(0, 0.08, 0), shadowD, 0.1)
	body.shadow.Transparency = lerp(P.shadowDark and (0.62 - 0.3 * P.shadowDark) or 0.62, 1, math.max(fade, sink))

	-- sand pours off it as it comes up; dust blows off its base as it moves
	local lastSink = B.lastSink or sink
	B.lastSink = sink
	local rising = dt > 0 and (lastSink - sink) / dt or 0
	B.spillHeat = math.max((B.spillHeat or 0) * math.exp(-dt * 0.8), clamp(rising * 1.5, 0, 1))
	body.spillAt.CFrame = headCF
	body.spill.Rate = (1 - fade) * out * (5 + 70 * B.spillHeat)
	body.dustAt.CFrame = CFrame.new(floorAt + V3(0, 1, 0))
	body.dust.Rate = (1 - fade) * (ridge * 45 + (moving and out * 10 or 0) + B.spillHeat * out * 30)
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
-- comes up out of the sand comes up through them - BossService has the same rule)
local function onStone(B, pos)
	if not B.stones then
		B.stones = {}
		for _, pm in ipairs(CollectionService:GetTagged("DunePlatform")) do
			local slab = pm:GetAttribute("Floor") == B.floor and pm:FindFirstChild("PlatformSlab")
			if slab then
				table.insert(B.stones, { center = slab.Position, radius = pm:GetAttribute("Radius") or 10 })
			end
		end
	end
	for _, st in ipairs(B.stones) do
		if flat(pos - st.center).Magnitude <= st.radius then
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

-- Where Mireworm will burst out of the sand: marked from the moment it's
-- under, filling in as the ridge closes on it, with the furrow it ploughs
-- left behind it on the floor.
local function eruptMark(B, fromPos, at, fromT, arriveT)
	local a = B.def.Attacks.Lunge
	at = onFloor(at)
	local from = onFloor(fromPos)
	local ring = newRing(30, B.def.EyeColor, Enum.Material.Neon, 0.3)
	local fill = newPart("EruptMark", Enum.PartType.Cylinder, WORM_SAND_DEEP, Enum.Material.Sand, 0.6)
	local furrow = newPart("Furrow", nil, WORM_SAND_DEEP, Enum.Material.Sand, 1)
	local erupted = false
	addTelegraph(B, {
		update = function(now)
			local u = clamp((now - fromT) / math.max(arriveT - fromT, 0.05), 0, 1)
			-- the furrow behind the ridge, fading once it's out
			local reach = from:Lerp(at, u)
			local len = flat(reach - from).Magnitude
			if len > 0.5 then
				furrow.Size = V3(B.def.Size * 0.7, 0.2, len)
				furrow.CFrame = CFrame.lookAt((from + reach) / 2 + V3(0, 0.12, 0), reach + V3(0, 0.12, 0))
				furrow.Transparency = lerp(0.3, 1, clamp((now - arriveT) / 2.5, 0, 1))
			end
			if now < arriveT then
				local pulse = 0.5 + 0.5 * math.sin(now * lerp(10, 28, u))
				placeRing(ring, at + V3(0, 0.06, 0), a.Splash, 0.25, 0.7, lerp(0.45, 0.1, pulse * u))
				placeDisc(fill, at + V3(0, 0.07, 0), 2 * a.Splash * smooth(u), 0.08)
				fill.Transparency = lerp(0.7, 0.3, u)
				return true
			end
			if not erupted then
				erupted = true
				for _, p in ipairs(ring.parts) do
					p.Transparency = 1
				end
				fill.Transparency = 1
				burst(at + V3(0, 1, 0), WORM_SAND, 40, 38, 3, 1.1, true)
				burst(at + V3(0, 0.5, 0), WORM_SAND_DEEP, 20, 22, 2.2, 0.8)
				shockRing(B, at, B.def.Size / 2, a.Splash * 1.3, 0.4, WORM_SAND)
				playSound(B.def, "Erupt", at, 1)
				kick(at, a.Splash, 1.2, -4)
			end
			return now - arriveT < 2.5
		end,
		cleanup = function()
			removeRing(ring)
			fill:Destroy()
			furrow:Destroy()
		end,
	})
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

-- The stone seal at the middle of the dunes caves in when Mireworm's armour
-- breaks, leaving a pit with the sand pouring into it - and it's whole again
-- the next time the worm sleeps. (Only drawn on your screen, but every screen
-- does it at the same moment.)
local SEAL_PARTS = { SealStone = true, SealRing = true, SealCoil = true, SealTile = true, SandSwirl = true }
local function collapseSeal(B, on, instant)
	if (B.sealDown or false) == on then
		return
	end
	local arena = arenaOf(B)
	if not arena then
		return
	end
	B.sealDown = on
	if not B.seal then
		B.seal = {}
		for _, d in ipairs(arena:GetDescendants()) do
			if d:IsA("BasePart") and SEAL_PARTS[d.Name] then
				table.insert(B.seal, { part = d, cf = d.CFrame, transparency = d.Transparency or 0 })
			end
		end
	end
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
	local pit = newPart("SinkholePit", Enum.PartType.Cylinder, RGB(92, 68, 44), Enum.Material.Sand, instant and 0 or 1)
	placeDisc(pit, center + V3(0, 0.05, 0), radius * 1.5, 0.1)
	local deep = newPart("SinkholeDeep", Enum.PartType.Cylinder, RGB(24, 17, 10), Enum.Material.SmoothPlastic, instant and 0 or 1)
	placeDisc(deep, center + V3(0, 0.08, 0), radius * 0.8, 0.1)
	local rim = newRing(26, WORM_SAND_DEEP, Enum.Material.Sand, instant and 0 or 1)
	placeRing(rim, center, radius * 0.78, 1.6, 6, nil)
	local pour = newPart("SinkholePour", nil, WORM_SAND, nil, 1)
	pour.Size = V3(radius * 1.4, 1, radius * 1.4)
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
	B.crater = { pit, deep, pour }
	for _, p in ipairs(rim.parts) do
		table.insert(B.crater, p)
	end
	if not instant then
		-- the stone goes, then the pit opens under it in a cloud of sand
		burst(center + V3(0, 1, 0), WORM_SAND, 50, 30, 4, 1.4, true)
		tween(pit, 0.9, { Transparency = 0 })
		tween(deep, 1.4, { Transparency = 0 })
		for _, p in ipairs(rim.parts) do
			tween(p, 1, { Transparency = 0 })
		end
	end
end

-- The sandstorm in the dunes (ArenaAmbience draws it from the arena's Storm
-- attribute) picks up when the worm wakes, and howls once its armour is gone.
local function stepStorm(B, dt)
	local arena = arenaOf(B)
	if not arena then
		return
	end
	local state = B.model:GetAttribute("State")
	local want = 0.35
	if state == "Waking" or state == "Fighting" or state == "Transition" then
		want = B.phase2Look and 0.95 or 0.6
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
	if B.kind == "Worm" then
		-- the worm throws its head back to roar at the sky
		P.lean = -0.55 * P.mouth
		P.lift = 5 * P.mouth
	end
end

function Poses.Reset(B, t, P)
	local u = clamp(t / 2, 0, 1)
	P.sink = smooth(u)
	P.eyes = 1 - clamp(u * 2, 0, 1)
	P.sy = 1 + 0.08 * spring(t, 3, 12)
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
	if B.kind == "Worm" then
		-- Mireworm goes under: rears back, plunges head-first into the sand,
		-- swims beneath it (only the ridge it pushes up shows) and bursts out at
		-- the far end
		if t < a.Tell then
			local k = t / a.Tell
			if k < 0.45 then
				local e = smooth(k / 0.45)
				P.lean, P.lift, P.mouth, P.shake = -0.45 * e, 5 * e, 0.6 * e, 0.1 * e
			else
				local e = smooth((k - 0.45) / 0.55)
				P.lean = lerp(-0.45, 1.1, e)
				P.lift = 5 * (1 - e)
				P.mouth = 0.6 * (1 - e)
				P.sink = e * e
				P.ridge = e
			end
			return
		end
		local m = B.model
		local from, to, travel = m:GetAttribute("ActA"), m:GetAttribute("ActB"), m:GetAttribute("ActN")
		if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" or not travel then
			P.sink, P.ridge, P.lean = 1, 1, 1.1 -- under, waiting to hear where
			return
		end
		local u = (t - a.Tell) / travel
		if u < 1 then
			P.override = from:Lerp(to, clamp(u, 0, 1))
			P.sink, P.ridge, P.lean = 1, 1, 1.1
			return
		end
		-- out it comes
		local e = t - a.Tell - travel
		local k = clamp(e / 0.3, 0, 1)
		P.sink = 1 - easeOut(k)
		P.ridge = 1 - k
		P.lean = -0.35 * (1 - smooth((e - 0.3) / 0.6))
		P.lift = 6 * spring(e, 4, 9)
		P.mouth = clamp(1 - (e - 0.2) / 0.6, 0, 1)
		P.flare = clamp(1 - e / 0.8, 0, 1)
		return
	end
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
	if B.kind == "Worm" then
		-- rears up and roars at the sky while the sand erupts round it
		local total = (a.Rings - 1) * a.Gap + a.Fuse
		if t < a.Tell then
			local k = smooth(t / a.Tell)
			P.lean, P.lift, P.mouth, P.flare, P.shake = -0.6 * k, 7 * k, k, k, 0.2 * k
		elseif t - a.Tell < total then
			P.lean, P.lift, P.mouth, P.flare, P.shake = -0.6, 7 + math.sin(t * 3) * 0.8, 1, 1, 0.25
		else
			local s = smooth((t - a.Tell - total) / 0.6)
			P.lean, P.lift, P.mouth, P.flare = -0.6 * (1 - s), 7 * (1 - s), 1 - s, 1 - s
		end
		return
	end
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
	if B.kind == "Worm" then
		-- the dive: head-first into the sand in a spray of it (the eruption at
		-- the far end is marked as soon as the server says where - SlotSpawns)
		at(B, t0 + a.Tell * 0.55, function()
			playSound(B.def, "Lunge", B.vpos, 1)
		end)
		at(B, t0 + a.Tell * 0.8, function()
			burst(B.vpos + V3(0, 1, 0), WORM_SAND, 36, 30, 3, 1, true)
			shockRing(B, B.vpos, B.def.Size / 2, B.def.Size, 0.35, WORM_SAND)
			kick(B.vpos, 30, 0.6)
		end)
		return
	end
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

-- Mireworm's burrow: the moment the server says where it'll come up, that
-- spot is marked (the slime's lunge needs no mark - you can see it flying)
function SlotSpawns.Lunge(B, i, spot, t0)
	if B.kind ~= "Worm" or i ~= 2 then
		return
	end
	local a = B.def.Attacks.Lunge
	local from = B.model:GetAttribute("ActA")
	local travel = B.model:GetAttribute("ActN") or 0.5
	eruptMark(B, typeof(from) == "Vector3" and from or B.vpos, spot, t0 + a.Tell, t0 + a.Tell + travel)
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
local function onAction(B, name, t0, now)
	B.action, B.actionStart = name, t0
	B.events = {}
	B.slotsDone = 0
	local worm = B.kind == "Worm"
	if name == "Break" and now - t0 > B.def.BreakTime * 0.35 then
		B.phase2Look, B.crownGone = true, true -- joined late: it's already broken
		if worm then
			collapseSeal(B, true, true)
		end
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

local function stepBoss(B, now, dt)
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
	local shape = Poses[action]
	if state == "Dormant" then
		shape = Poses.Dormant
	elseif state == "Dead" then
		shape = Poses.Death
	end
	if shape then
		shape(B, t, P)
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
	-- while it's lunging or hopping
	local ground = rootGround(B)
	if P.override then
		B.vpos = V3(P.override.X, ground.Y, P.override.Z)
	else
		B.vpos = B.vpos:Lerp(ground, 1 - math.exp(-dt * 14))
	end
	local look = flat(m.PrimaryPart.CFrame.LookVector)
	if look.Magnitude > 0.01 then
		local blended = B.vfacing:Lerp(look.Unit, 1 - math.exp(-dt * 12))
		B.vfacing = blended.Magnitude > 0.01 and blended.Unit or look.Unit
	end

	applyPose(B, P, B.vpos, B.vfacing, now, dt)
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
	if here and awake then
		showBar(B)
	elseif barFor == B and not (here and awake) then
		showBar(nil)
	end

	-- you can't walk through it: nudged out to the edge of its body
	if here and awake then
		local hrp = myRoot()
		if hrp then
			local offset = flat(hrp.Position - B.vpos)
			local minimum = B.def.Size / 2 * P.sx + 1.2
			local solid
			if B.kind == "Worm" then
				solid = (P.sink or 0) < 0.5 -- under the sand it's not in your way
			else
				solid = P.lift < 4 -- in the air, you can run under it
			end
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
		music.Volume = MUSIC_VOLUME * musicLevel
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
local LOBBY_MUSIC = Config.LobbyMusic or "Dreaming in the city"
local lobbyMusic, lobbyLevel, lobbyVolume = nil, 0, 0.15

local function stepLobbyMusic(dt)
	local want = player:GetAttribute("SpireFloor") == nil
	if want and not lobbyMusic then
		local template = SoundService:FindFirstChild(LOBBY_MUSIC)
		if template and template:IsA("Sound") then
			lobbyVolume = (Config.Audio and Config.Audio.LobbyMusic) or 0.25
			lobbyMusic = template:Clone()
			lobbyMusic.Name = "LobbyMusicPlaying"
			lobbyMusic.Looped = true
			lobbyMusic.Volume = 0
			lobbyMusic.SoundGroup = soundGroup("Music")
			lobbyMusic.Parent = SoundService
			lobbyMusic:Play()
		end
	end
	if not lobbyMusic then
		return
	end
	lobbyLevel = lobbyLevel + ((want and 1 or 0) - lobbyLevel) * math.min(1, dt * (want and 0.5 or 1.2))
	lobbyMusic.Volume = lobbyVolume * lobbyLevel
	if want and not lobbyMusic.IsPlaying then
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
		stepBoss(B, now, dt)
	end
	stepBar(now, dt)
	stepMusic(dt)
	-- weather is decoration: if it ever fails, the fight carries on without it
	local ok, err = pcall(stepRain, dt)
	if not ok and not rainWarned then
		rainWarned = true
		warn("[BossClient] acid rain stopped: " .. tostring(err))
	end
	stepLobbyMusic(dt)
end)
