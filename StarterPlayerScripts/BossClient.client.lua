--[[
	BossClient  (LocalScript, parent: StarterPlayer > StarterPlayerScripts, name: "BossClient")

	Draws the Spire's bosses and everything they do. The server (BossService)
	decides what happens and publishes it as attributes on the boss model, each
	action stamped with the server's clock. This script builds the body on your
	screen and animates it from those timestamps - so the slime rearing up, the
	shadow spreading under it and the moment it lands are the same moment the
	server hits you, whatever your ping.

	EACH BOSS'S BODY HAS ITS OWN FILE in ReplicatedStorage/BossBodies, named
	after its short name in Config.Bosses (Oozark.lua: the slime, Nahrzul.lua:
	the worm). A body file holds everything that one boss draws: its body and
	how it moves, the shape of each of its actions over time, their one-off
	moments (sounds, landings, bursts), its warnings on the floor, and how its
	arena answers the fight. See BossBodies/_Template.lua to add a boss.

	What's here (what every boss shares):
	  * the drawing kit every body file gets (Body.init(kit)): parts that
	    snap to the 8-bit palette, rings, bursts, camera kicks, sounds by name,
	    warnings in the world, one-off moments on the server's clock
	  * keeping track of each boss on this screen, and every frame: what it's
	    doing, where it is, its pose (breathing, crawling, wobbling when hit),
	    its warnings, and not letting you walk through it
	  * the weather of its arena (acid rain, or the dunes' sandstorm)
	  * the boss bar across the top, with the trailing damage chip
	  * the victory banner, the fight's music and the lobby's music
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
local SOUND_FALLBACK = { Dive = "Lunge", Crash = "Slam", Sweep = "Wave", Roar = "Wail", Devour = "Roar",
	-- (Knight Burrowmore's: a jump sounds like a lunge, a landing like a slam...)
	Jump = "Lunge", Land = "Slam", Swing = "Wave", Dig = "Spit", Clod = "Splat", Anchor = "Lunge",
	AnchorLand = "Slam", Fire = "Spit", Dash = "Lunge", Taunt = "Wail", Gem = "Splat", Meteor = "Slam",
	-- (Kaze's: a punch sounds like a slam, the Kaze-Blast like a spit, the
	-- beam like a wave... The announcer's words have nothing to borrow.)
	Punch = "Slam", Heavy = "Slam", Blast = "Spit", Dragon = "Lunge", Tornado = "Wave", Charge = "Wail",
	Cancel = "Lunge", Focus = "Wail", Stagger = "Splat", Tired = "Wail", Super = "Wake", Beam = "Wave",
	Pillar = "Erupt", KO = "Death",
	-- (Speedy Revvington's: a rev sounds like a wail, a skid like a wave, the
	-- backfire like an eruption... The crowd, the start lights, the flag and
	-- his engine's hum have nothing to borrow.)
	Rev = "Wail", Skid = "Wave", Whip = "Wave", Honk = "Wail", Backfire = "Erupt", Bump = "Slam", Donut = "Wave" }

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

-- the colour of bone (teeth, spikes, the crown's sockets)
local BONE = RGB(226, 216, 186)

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
-- One-off moments in each action (sounds, landings, telegraphs)
----------------------------------------------------------------------
local function at(B, when, fn)
	table.insert(B.events, { at = when, fn = fn })
end

----------------------------------------------------------------------
-- Each boss's body: ReplicatedStorage/BossBodies/<its short name>
----------------------------------------------------------------------
-- Everything one boss draws lives in its own body file (see the top of this
-- script). Each is loaded once, here, and handed the drawing kit: the shared
-- helpers above. One that's missing or broken is reported in the Output and
-- only that boss isn't drawn - the others still are.
local kit = {
	-- little helpers
	serverNow = serverNow, clamp = clamp, lerp = lerp, smooth = smooth, easeOut = easeOut,
	easeOutBack = easeOutBack, spring = spring, flat = flat, tween = tween, myRoot = myRoot,
	-- things drawn in the world
	fxFolder = fxFolder, PIXEL = PIXEL, snapColor = snapColor, newPart = newPart, placeDisc = placeDisc,
	newRing = newRing, placeRing = placeRing, surfaceY = surfaceY, onFloor = onFloor, removeRing = removeRing,
	burst = burst, STONE = STONE, STONE_DARK = STONE_DARK, BONE = BONE, SERIF = SERIF, SLOT_NAMES = SLOT_NAMES,
	-- the camera and sound
	kick = kick, soundGroup = soundGroup, findSound = findSound, playSound = playSound,
	SPLAT_VOLUME = SPLAT_VOLUME, SPLAT_LEAD = SPLAT_LEAD,
	-- warnings in the world, the arena, one-off moments
	addTelegraph = addTelegraph, shockRing = shockRing, onStone = onStone, arenaOf = arenaOf, at = at,
}

-- Two more things any boss's body can use, only on your screen:
--   kit.bigText(text, opts)  big pixel words across the middle of the screen
--       (a boss's own moments: ROUND 2, K.O.!, TURBO!, LEVEL COMPLETE!).
--       opts: color, sub (a smaller line under it), y (0-1, how far down),
--       size (the biggest the letters get), hold (seconds before it fades)
--   kit.shout(part, text, seconds, color)  a word bubble over a boss's head
--       (a move's name shouted, a honk); returns the bubble's label so the
--       words can be changed while it shows
do
	local pixelFace = nil
	pcall(function()
		pixelFace = Font.new("rbxasset://fonts/families/PressStart2P.json")
	end)
	local big = nil -- { gui, label, sub, scale }
	local bigToken = 0
	function kit.bigText(text, opts)
		opts = opts or {}
		if not big then
			local gui = Instance.new("ScreenGui")
			gui.Name = "BossBigText"
			gui.ResetOnSpawn = false
			gui.IgnoreGuiInset = true
			gui.DisplayOrder = 26
			gui:SetAttribute("RetroSkip", true) -- (it has its own look)
			gui.Parent = playerGui
			local holder = Instance.new("Frame")
			holder.BackgroundTransparency = 1
			holder.AnchorPoint = Vector2.new(0.5, 0.5)
			holder.Size = UDim2.new(0.9, 0, 0, 130)
			holder.Parent = gui
			local scale = Instance.new("UIScale")
			scale.Parent = holder
			local function words(name, y, h, maxSize)
				local l = Instance.new("TextLabel")
				l.Name = name
				l.BackgroundTransparency = 1
				l.Position = UDim2.new(0, 0, 0, y)
				l.Size = UDim2.new(1, 0, 0, h)
				l.Font = Enum.Font.Arcade
				if pixelFace then
					l.FontFace = pixelFace
				end
				l.TextScaled = true
				l.TextStrokeTransparency = 0
				l.TextStrokeColor3 = RGB(24, 20, 37)
				l.Text = ""
				local limit = Instance.new("UITextSizeConstraint")
				limit.MaxTextSize = maxSize
				limit.Parent = l
				l.Parent = holder
				return l, limit
			end
			local label, limit = words("Big", 0, 86, 64)
			local sub = words("Sub", 92, 34, 26)
			big = { gui = gui, holder = holder, label = label, limit = limit, sub = sub, scale = scale }
		end
		bigToken = bigToken + 1
		local mine = bigToken
		big.holder.Position = UDim2.fromScale(0.5, opts.y or 0.36)
		big.label.Text = tostring(text)
		big.label.TextColor3 = opts.color or RGB(255, 255, 255)
		big.limit.MaxTextSize = opts.size or 64
		big.sub.Text = opts.sub or ""
		big.sub.TextColor3 = opts.subColor or RGB(255, 255, 255)
		big.label.TextTransparency, big.label.TextStrokeTransparency = 0, 0
		big.sub.TextTransparency, big.sub.TextStrokeTransparency = 0, 0
		big.gui.Enabled = true
		big.scale.Scale = 1.8
		tween(big.scale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
		task.delay(opts.hold or 1.3, function()
			if bigToken ~= mine then
				return -- (newer words took its place)
			end
			tween(big.label, 0.3, { TextTransparency = 1, TextStrokeTransparency = 1 })
			tween(big.sub, 0.3, { TextTransparency = 1, TextStrokeTransparency = 1 })
			task.delay(0.35, function()
				if bigToken == mine then
					big.gui.Enabled = false
				end
			end)
		end)
	end

	function kit.shout(part, text, seconds, color)
		local bb = Instance.new("BillboardGui")
		bb.Name = "BossShout"
		bb.Size = UDim2.fromOffset(240, 58)
		bb.StudsOffsetWorldSpace = V3(0, 7, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 220
		bb.Adornee = part
		local box = Instance.new("Frame")
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.fromScale(0.5, 0.5)
		box.Size = UDim2.fromScale(0.2, 0.2)
		box.BackgroundColor3 = RGB(0, 0, 0)
		box.BorderSizePixel = 0
		box.Parent = bb
		local stroke = Instance.new("UIStroke")
		stroke.Color = color or RGB(255, 255, 255)
		stroke.Thickness = 3
		stroke.Parent = box
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.TextScaled = true
		label.Font = Enum.Font.Arcade
		if pixelFace then
			label.FontFace = pixelFace
		end
		label.TextColor3 = color or RGB(255, 255, 255)
		label.Text = tostring(text)
		label.Parent = box
		bb.Parent = playerGui
		tween(box, 0.12, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Back)
		task.delay(seconds or 1.2, function()
			bb:Destroy()
		end)
		return label, bb
	end
end
local bodyModules = {} -- [short name] = its body file, or false
local bodyList = {} -- (in Config's order)
local bodiesFolder = ReplicatedStorage:WaitForChild("BossBodies", 30)
for _, def in pairs(Config.Bosses or {}) do
	local file = bodiesFolder and bodiesFolder:FindFirstChild(def.Short)
	local ok, result = false, "no file named " .. tostring(def.Short) .. " in ReplicatedStorage > BossBodies"
	if file then
		ok, result = pcall(require, file)
	end
	if ok and type(result) == "table" then
		if result.init then
			ok, result = pcall(function()
				result.init(kit)
				return result
			end)
		end
	end
	if ok and type(result) == "table" then
		bodyModules[def.Short] = result
		table.insert(bodyList, result)
	else
		bodyModules[def.Short] = false
		warn("[BossClient] " .. tostring(def.Short) .. " won't be drawn: " .. tostring(result))
	end
end
local function bodyModule(def)
	return bodyModules[def.Short] or nil
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
	local mod = bodyModule(def)
	if not mod then
		return -- (no body file for it in BossBodies: reported once, above)
	end
	local B = {
		model = model,
		def = def,
		floor = floorId,
		mod = mod, -- its body file (ReplicatedStorage/BossBodies)
		body = mod.build(def),
		telegraphs = {},
		events = {},
		seenId = -1,
		slotsDone = 0,
		lastHealth = model:GetAttribute("Health") or 0,
		wobbles = {},
	}
	B.kind = def.Body == "Worm" and "Worm" or "Slime"
	-- what its attacks are made of (its body file says: slime you can see
	-- into, sand and rock...)
	B.fx = mod.fx(def)
	B.vpos = rootGround(B)
	local look = model.PrimaryPart.CFrame.LookVector
	B.vfacing = flat(look).Magnitude > 0.01 and flat(look).Unit or V3(0, 0, 1)
	B.phase2Look = (model:GetAttribute("Phase") or 1) >= 2
	B.crownGone = B.phase2Look
	if mod.onTrack then
		mod.onTrack(B) -- (its body file's own start: e.g. the worm's trail)
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
	B.prevAction = B.action
	B.action, B.actionStart = name, t0
	B.events = {}
	B.slotsDone = 0
	local mod = B.mod
	if mod.onAction then
		mod.onAction(B, name, t0, now) -- (its body file's own business, e.g. the worm's)
	end
	if name == "Break" and now - t0 > B.def.BreakTime * 0.35 then
		B.phase2Look, B.crownGone = true, true -- joined late: it's already broken
		if mod.lateBreak then
			mod.lateBreak(B)
		end
	end
	if name == "Wake" or name == "Dormant" or name == "Reset" then
		B.phase2Look, B.crownGone = false, false
		if mod.calm then
			mod.calm(B, name) -- (its arena settling again)
		end
	end
	if name == "Break" and mod.breaks then
		mod.breaks(B) -- (its arena answering phase two)
	end
	local start = mod.Starts[name]
	if start then
		start(B, t0)
	end
end



local function stepBoss(B, now, dt)
	local mod = B.mod
	if mod.signs then
		mod.signs(B, B.model:GetAttribute("State") or "Dormant") -- (e.g. the worm's "HIT IT!")
	end
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
	local spawnSlot = mod.SlotSpawns[action]
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
	local shape = mod.Poses[action]
	if state == "Dormant" then
		shape = mod.Poses.Dormant
	elseif state == "Dead" then
		shape = mod.Poses.Death
	end
	if shape then
		if mod.runPose then
			mod.runPose(B, shape, t, now, P) -- (the worm: catching up, flowing between stages)
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
	local glided = mod.glide and mod.glide(B, now, ground) or nil
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

	mod.pose(B, P, B.vpos, P.facing or B.vfacing, now, dt)
	if mod.afterPose then
		mod.afterPose(B) -- (the worm: the path its body follows under the sand)
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
	if mod.senses then
		mod.senses(B, dt, here, awake, state) -- (the worm: the rumble and the whirlpool)
	end
	if here and awake then
		showBar(B)
	elseif barFor == B and not (here and awake) then
		showBar(nil)
	end

	-- you can't walk through it: nudged out to the edge of its body (or
	-- its body file's own way - the worm is long, not round)
	if mod.pushOut then
		mod.pushOut(B, P, here, awake, state)
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
	-- (quiet in a Spire arena, and in the intro: Oozlet has its own song)
	local want = player:GetAttribute("SpireFloor") == nil and player:GetAttribute("Intro") == nil
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
	for _, mod in ipairs(bodyList) do
		if mod.everyFrame then
			pcall(mod.everyFrame)
		end
	end
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
