--[[
	IntroClient  (LocalScript, parent: Starter Player > StarterPlayerScripts, name: "IntroClient")

	The intro on a brand-new player's screen. (IntroService on the server
	runs the fight and decides everything; this draws it. Config.Intro has
	every number and every word.)

	  * THE DARK: you wake up by the fountain and it's the only thing there -
	    the fountain and the plaza round it, lit, with pale 8-bit mist
	    drifting at the edge and pitch black beyond (a black box round the
	    plaza, only on your screen; everything outside it is hidden too). No
	    buttons, no bars - every other screen and Roblox's own are hidden -
	    no other players, no music. The camera can't pull back far.
	  * OOZLET: a little block of slime with big shiny eyes, rosy cheeks and a
	    tiny gold crown, happily hopping round the fountain - squash and
	    stretch on every hop, eyes that follow you, a wiggle and a note now
	    and then. A little arrow bounces over it.
	  * THE WORDS: HIT THE SLIME! builds up letter by letter - each letter
	    scrambles through random symbols before it locks in with a blip -
	    a pause... and the "!" slams down with a BOOM. Then the words throb
	    like a heartbeat, flash yellow and white, and jolt with every punch:
	    AGAIN! HARDER! ... ROLL!! (red and shaking) ... NICE ROLL! ... IT'S
	    CRACKING! ... FINISH IT!!! A small line underneath says how (click,
	    tap or gamepad - whichever you're using).
	  * THE FIGHT: Oozlet gets angry (a red flash, angry brows, a "!"), its
	    bar drops in at the top of the screen, red circles show where it's
	    going to land, the lesson slam hangs over you until you roll (on a
	    phone the ROLL button throbs), it cracks at half health, and it POPS
	    into pixels. A chest drops out of the sky, bounces, and bursts open
	    (+1 ARCADE TOKEN).
	  * THE REVEAL: the mist rolls back and the lobby builds itself round you -
	    the ground unrolls under the mist and every piece pops in as it
	    passes - then the sky comes back, and last of all the camera turns to
	    the Spire as it rises out of nothing: OOZARK AWAITS... Then everything
	    comes back: your buttons, the music, the other players.
	Nothing here changes the game: all it ever tells the server is "I can see
	now" (the title screen has gone) and "I've finished showing the lobby".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local ContentProvider = game:GetService("ContentProvider")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local I = Config.Intro or {}
if I.On == false then
	return
end
local O = I.Oozlet or {}
local TXT = I.Text or {}
local REV = I.Reveal or {}
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RGB = Color3.fromRGB
local V3 = Vector3.new
local CENTER = I.Center or V3(0, 0, 0)
local RADIUS = I.Radius or 23.5
local SIZE = O.Size or 4.6
local rng = Random.new()

-- the game's colours (Endesga 32)
local C = {
	black = RGB(0, 0, 0), ink = RGB(24, 20, 37), white = RGB(255, 255, 255),
	yellow = RGB(254, 231, 97), gold = RGB(254, 174, 52), red = RGB(228, 59, 68), darkRed = RGB(162, 38, 51),
	green = O.Color or RGB(99, 199, 77), green2 = O.DeepColor or RGB(62, 137, 72), green3 = RGB(38, 92, 66),
	pink = O.CheekColor or RGB(246, 117, 122), purple = RGB(104, 56, 108), plum = RGB(181, 80, 136),
	mist1 = RGB(192, 203, 220), mist2 = RGB(139, 155, 180), mist3 = RGB(90, 105, 136),
	wood = RGB(184, 111, 80), woodDark = RGB(115, 62, 57), sky = RGB(44, 232, 245),
}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function clamp01(x)
	return math.clamp(x, 0, 1)
end
local function lerp(a, b, t)
	return a + (b - a) * t
end
local function smooth(t)
	t = clamp01(t)
	return t * t * (3 - 2 * t)
end
local function easeOut(t)
	t = clamp01(t)
	return 1 - (1 - t) ^ 3
end
local function easeInOut(t)
	t = clamp01(t)
	if t < 0.5 then
		return 4 * t * t * t
	end
	return 1 - (-2 * t + 2) ^ 3 / 2
end
-- a spring settling: 1 at the start, wobbling, dying away
local function wobble(t, speed, fade)
	if t < 0 then
		return 0
	end
	return math.exp(-fade * t) * math.cos(speed * t)
end
-- the clock the server's hops and moves are timed on
local function serverNow()
	return Workspace:GetServerTimeNow()
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
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if hum and root and hum.Health > 0 then
		return root, hum
	end
	return nil
end
local function camera()
	return Workspace.CurrentCamera
end
local function stage()
	return player:GetAttribute("Intro")
end

-- the chunky "Press Start" pixel font for the big words (Arcade if this Roblox hasn't got it)
local PIXEL_FONT = nil
pcall(function()
	PIXEL_FONT = Font.new("rbxasset://fonts/families/PressStart2P.json")
end)
local function pixelText(label)
	if PIXEL_FONT then
		local ok = pcall(function()
			label.FontFace = PIXEL_FONT
		end)
		if ok then
			return
		end
	end
	label.Font = Enum.Font.Arcade
end

----------------------------------------------------------------------
-- Sounds
----------------------------------------------------------------------
-- the mix's volume groups (Config.Audio), shared with every other script
local function soundGroup(name)
	local g = SoundService:FindFirstChild(name)
	if not (g and g:IsA("SoundGroup")) then
		g = Instance.new("SoundGroup")
		g.Name = name
		g.Volume = (Config.Audio and Config.Audio[name]) or 1
		g.Parent = SoundService
	end
	return g
end
-- a Sound in SoundService by name, ignoring capitals and spaces
local function squash(name)
	return string.lower((string.gsub(name, "%s+", "")))
end
local function findSound(names)
	for _, name in ipairs(names or {}) do
		local s = SoundService:FindFirstChild(name)
		if not (s and s:IsA("Sound")) then
			s = nil
			for _, c in ipairs(SoundService:GetChildren()) do
				if c:IsA("Sound") and squash(c.Name) == squash(name) then
					s = c
					break
				end
			end
		end
		if s then
			return s
		end
	end
	return nil
end
-- (built-in Roblox sounds, for anything that isn't in SoundService)
local FALLBACK = {
	Blip = { "rbxasset://sounds/electronicpingshort.wav", 0.18, 2.2 },
	Boom = { "rbxasset://sounds/snap.mp3", 1, 0.45 },
	Hop = { "rbxasset://sounds/action_jump_land.mp3", 0.35, 1.6 },
	Squish = { "rbxasset://sounds/impact_water.mp3", 0.6, 1.5 },
	Wake = { "rbxasset://sounds/snap.mp3", 0.7, 0.7 },
	Slam = { "rbxasset://sounds/snap.mp3", 0.8, 0.55 },
	Crack = { "rbxasset://sounds/snap.mp3", 0.9, 1.25 },
	Pop = { "rbxasset://sounds/impact_water.mp3", 0.9, 0.8 },
	Chest = { "rbxasset://sounds/electronicpingshort.wav", 0.5, 1.2 },
	Win = { "rbxasset://sounds/electronicpingshort.wav", 0.6, 1 },
	Awaits = { "rbxasset://sounds/snap.mp3", 0.8, 0.35 },
}
local soundCache = {}
local function play(key, volume, pitch)
	if soundCache[key] == nil then
		soundCache[key] = findSound((I.Sounds or {})[key]) or false
	end
	local template = soundCache[key]
	local s
	if template then
		s = template:Clone()
		s.Volume = template.Volume * (volume or 1)
		s.PlaybackSpeed = template.PlaybackSpeed * (pitch or 1)
	else
		local fb = FALLBACK[key]
		if not fb then
			return
		end
		s = Instance.new("Sound")
		s.SoundId = fb[1]
		s.Volume = fb[2] * (volume or 1)
		s.PlaybackSpeed = fb[3] * (pitch or 1)
	end
	s.Name = "Intro" .. key
	s.SoundGroup = soundGroup(key == "Blip" and "UI" or "Effects")
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 6)
end

-- Warming up: every sound and song the intro plays is loaded while the dark
-- is still covered, so the first blip, BOOM and squish don't stall or come
-- out silent
local function warmSounds()
	local list = {}
	for key in pairs(FALLBACK) do
		local template = findSound((I.Sounds or {})[key])
		if template then
			table.insert(list, template)
		else
			local s = Instance.new("Sound")
			s.SoundId = FALLBACK[key][1]
			table.insert(list, s)
		end
	end
	local song = findSound(I.Music)
	if song then
		table.insert(list, song)
	end
	pcall(function()
		ContentProvider:PreloadAsync(list)
	end)
end

-- a shake of your camera (CombatClient does it: strength, and how far the view punches in)
local function kick(strength, fov)
	local scripts = player:FindFirstChild("PlayerScripts")
	local k = scripts and scripts:FindFirstChild("CombatCameraKick")
	if k and k:IsA("BindableEvent") then
		k:Fire(strength, fov)
	end
end

-- The fight's music (the first of Config.Intro.Music that's in SoundService)
local Music = {}
do
	local song, level, want = nil, 0, false
	function Music.play()
		if song then
			want = true
			return
		end
		local template = findSound(I.Music)
		if not template then
			return
		end
		song = template:Clone()
		song.Name = "IntroMusicPlaying"
		song.Looped = true
		song.Volume = 0
		song.SoundGroup = soundGroup("Music")
		song.Parent = SoundService
		song:Play()
		want = true
	end
	function Music.stop()
		want = false
	end
	-- (gone at once: the intro's over and nothing is left to fade it)
	function Music.kill()
		want, level = false, 0
		if song then
			song:Destroy()
			song = nil
		end
	end
	function Music.step(dt)
		if not song then
			return
		end
		level = level + ((want and 1 or 0) - level) * math.min(1, dt * (want and 1.5 or 1))
		song.Volume = (I.MusicVolume or 0.45) * level
		if not want and level < 0.01 then
			song:Destroy()
			song = nil
			level = 0
		end
	end
end

----------------------------------------------------------------------
-- Things drawn in the world (only on this screen)
----------------------------------------------------------------------
local world = nil -- the folder all of it lives in (made when the intro starts)

local function newPart(name, color, material, transparency, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.Size = V3(1, 1, 1)
	p.Parent = world
	return p
end

-- a flat round disc lying on the floor (the warning circles)
local function placeDisc(p, center, radius, y)
	p.Size = V3(0.1, radius * 2, radius * 2)
	p.CFrame = CFrame.new(center.X, y, center.Z) * CFrame.Angles(0, 0, math.pi / 2)
end

-- Short-lived effects: each has update(now) and stops when it returns false
local fxList = {}
local function addFx(update, cleanup)
	table.insert(fxList, { update = update, cleanup = cleanup })
end
local function stepFx(now)
	for i = #fxList, 1, -1 do
		local f = fxList[i]
		local ok, alive = pcall(f.update, now)
		if not ok or not alive then
			if f.cleanup then
				pcall(f.cleanup)
			end
			table.remove(fxList, i)
		end
	end
end
local function clearFx()
	for _, f in ipairs(fxList) do
		if f.cleanup then
			pcall(f.cleanup)
		end
	end
	fxList = {}
end

-- Pixels: little blocks that fly out, bounce on the floor and fade
local bits = {}
local function spawnBits(pos, count, colors, speed, size, up, life, floorY)
	for _ = 1, count do
		local s = size * rng:NextNumber(0.6, 1.2)
		local p = newPart("Bit", colors[rng:NextInteger(1, #colors)], Enum.Material.SmoothPlastic, 0)
		p.Size = V3(s, s, s)
		p.CFrame = CFrame.new(pos)
		local dir = V3(rng:NextNumber(-1, 1), rng:NextNumber(0.2, 1) + (up or 0), rng:NextNumber(-1, 1))
		dir = dir.Magnitude > 0.01 and dir.Unit or V3(0, 1, 0)
		table.insert(bits, {
			part = p, pos = pos, vel = dir * speed * rng:NextNumber(0.5, 1), age = 0,
			life = (life or 1) * rng:NextNumber(0.7, 1.2), size = s, floor = floorY or (pos.Y - 50),
		})
	end
end
local function stepBits(dt)
	for i = #bits, 1, -1 do
		local b = bits[i]
		b.age = b.age + dt
		if b.age >= b.life then
			b.part:Destroy()
			table.remove(bits, i)
		else
			b.vel = b.vel - V3(0, 60 * dt, 0)
			local pos = b.pos + b.vel * dt
			if pos.Y < b.floor + b.size / 2 and b.vel.Y < 0 then
				pos = V3(pos.X, b.floor + b.size / 2, pos.Z)
				b.vel = V3(b.vel.X * 0.6, -b.vel.Y * 0.35, b.vel.Z * 0.6)
			end
			b.pos = pos
			b.part.CFrame = CFrame.new(pos) -- (no spinning: pixels stay square)
			b.part.Transparency = clamp01((b.age / b.life - 0.6) / 0.4)
		end
	end
end

-- A ring of blocks opening outwards along the floor (a slam landing, a shell bursting)
local function shockRing(center, fromR, toR, seconds, color, y)
	local n = 18
	local blocks = {}
	for i = 1, n do
		blocks[i] = newPart("Shock", color or C.white, Enum.Material.Neon, 0.1)
		blocks[i].Size = V3(1.2, 0.5, 1.2)
	end
	local t0 = os.clock()
	addFx(function()
		local k = (os.clock() - t0) / seconds
		if k >= 1 then
			return false
		end
		local r = lerp(fromR, toR, easeOut(k))
		local cfs = {}
		for i, b in ipairs(blocks) do
			local a = (i - 0.5) / n * math.pi * 2
			cfs[i] = CFrame.new(center.X + math.cos(a) * r, y, center.Z + math.sin(a) * r) * CFrame.Angles(0, -a, 0)
			b.Size = V3(math.max(0.6, 2 * math.pi * r / n * 0.6), 0.5, 1)
			b.Transparency = 0.1 + 0.9 * k
		end
		Workspace:BulkMoveTo(blocks, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		return true
	end, function()
		for _, b in ipairs(blocks) do
			b:Destroy()
		end
	end)
end

-- Pixel pictures (a heart, a note) for the little bubbles over Oozlet
local SPRITES = {
	heart = { ".RR.RR.", "RRRRRRR", "RRRRRRR", ".RRRRR.", "..RRR..", "...R..." },
	note = { "..WWW", "..W.W", "..W..", "WWW..", "WWW..", ".W..." },
	star = { "..Y..", ".YYY.", "YYYYY", ".YYY.", "..Y.." },
}
local INKS = { R = C.red, W = C.white, Y = C.yellow }
local function drawSprite(rows, holder)
	local h, w = #rows, #rows[1]
	for y = 1, h do
		for x = 1, w do
			local color = INKS[string.sub(rows[y], x, x)]
			if color then
				local px = Instance.new("Frame")
				px.BorderSizePixel = 0
				px.BackgroundColor3 = color
				px.Size = UDim2.fromScale(1 / w + 0.01, 1 / h + 0.01)
				px.Position = UDim2.fromScale((x - 1) / w, (y - 1) / h)
				px:SetAttribute("RetroSkip", true)
				px.Parent = holder
			end
		end
	end
end
-- a little picture or symbol floating up from a spot in the world
local function bubble(pos, kind, seconds)
	local anchor = newPart("BubbleAnchor", C.white, nil, 1)
	anchor.Size = V3(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(pos)
	local bb = Instance.new("BillboardGui")
	bb.Name = "IntroBubble"
	bb.Size = UDim2.fromOffset(46, 46)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb:SetAttribute("RetroSkip", true)
	bb.Adornee = anchor
	bb.Parent = anchor
	if SPRITES[kind] then
		local art = Instance.new("Frame")
		art.BackgroundTransparency = 1
		art.Size = UDim2.fromScale(1, 1)
		art.Parent = bb
		drawSprite(SPRITES[kind], art)
	else
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.TextScaled = true
		label.Text = kind
		label.TextColor3 = kind == "!" and C.red or C.white
		label.TextStrokeColor3 = C.ink
		label.TextStrokeTransparency = 0
		label:SetAttribute("RetroSkip", true)
		pixelText(label)
		label.Parent = bb
	end
	local t0 = os.clock()
	seconds = seconds or 1
	addFx(function()
		local k = (os.clock() - t0) / seconds
		if k >= 1 then
			return false
		end
		bb.StudsOffset = V3(0, 1.5 * easeOut(k), 0)
		local grow = k < 0.15 and easeOut(k / 0.15) * 1.25 or lerp(1.25, 1, clamp01((k - 0.15) / 0.2))
		bb.Size = UDim2.fromOffset(46 * grow, 46 * grow)
		bb.Enabled = k < 0.8 or math.floor(k * 20) % 2 == 0 -- (blinks out at the end)
		return true
	end, function()
		anchor:Destroy()
	end)
end

----------------------------------------------------------------------
-- THE DARK: only the fountain and the plaza are there
----------------------------------------------------------------------
local Dark = {}
do
	local list = {} -- hidden parts: { part, near } (near = how close to the middle it comes)
	local sorted = false
	local cursor = 1
	local ground = {} -- hidden parts that reach under the plaza (the island): back first
	local spire = {} -- the Spire: kept for the very end
	local guis = {} -- labels that would show through the dark (always-on-top ones): [gui] = true
	local popping = {} -- parts on their way back in: { part, at }
	local extras = {} -- [part] = the signs, pictures and sparkles on it, switched off with it
	local box = nil -- the black walls, ceiling and floor
	local mist = {} -- the drifting mist blocks
	local fence = {} -- the invisible wall that keeps you on the plaza
	local atmo, atmoWas = nil, nil
	local addedConn = nil
	local WALLS = 36
	local LIMIT = REV.Reach or 600
	local BOX_RADIUS = RADIUS + 9.5 -- (room for the camera behind you at the plaza's edge)
	local spireModel = nil

	-- How close to (and how far from) the middle a part comes, flat on the
	-- ground: from its box turned the way it's turned. (A round part - a
	-- disc, a ball - reaches only as far as its radius.)
	local function reach(p)
		local cf, size = p.CFrame, p.Size
		local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
		local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
		local ex = math.abs(r.X) * hx + math.abs(u.X) * hy + math.abs(l.X) * hz
		local ez = math.abs(r.Z) * hx + math.abs(u.Z) * hy + math.abs(l.Z) * hz
		local shape = p:IsA("Part") and p.Shape or nil
		local round = shape == Enum.PartType.Cylinder or shape == Enum.PartType.Ball
		local e = round and math.max(ex, ez) or math.sqrt(ex * ex + ez * ez)
		local d = flat(cf.Position - CENTER).Magnitude
		local near, far = math.max(0, d - e), d + e
		-- (a block right at the edge of the light - the curb round the plaza -
		-- is measured by its corners, so a turned one isn't counted too big)
		if not round and near <= RADIUS + 0.5 and far > RADIUS + 0.5 then
			local px, pz = cf.Position.X - CENTER.X, cf.Position.Z - CENTER.Z
			far = 0
			for _, sx in ipairs({ -hx, hx }) do
				for _, sy in ipairs({ -hy, hy }) do
					for _, sz in ipairs({ -hz, hz }) do
						local x = px + r.X * sx + u.X * sy + l.X * sz
						local z = pz + r.Z * sx + u.Z * sy + l.Z * sz
						far = math.max(far, math.sqrt(x * x + z * z))
					end
				end
			end
		end
		return near, far
	end

	local function isCharacter(inst)
		return inst:IsA("Model") and Players:GetPlayerFromCharacter(inst) ~= nil
	end
	-- the thing right under Workspace that this is part of
	local function topOf(inst)
		local node = inst
		while node.Parent and node.Parent ~= Workspace do
			node = node.Parent
		end
		return node
	end
	local function skipTop(top)
		return top == world or top.Name == "IntroOozlets" or top:IsA("Terrain") or top:IsA("Camera") or isCharacter(top)
	end

	-- what's stuck on a part goes with it: pictures (decals), signs, sparkles
	local VISUAL = { SurfaceGui = true, BillboardGui = true, ParticleEmitter = true, Fire = true, Smoke = true, Sparkles = true, Beam = true, Trail = true }
	local function hideExtras(p)
		local list = nil
		for _, c in ipairs(p:GetChildren()) do
			local things = c:IsA("Attachment") and c:GetChildren() or { c }
			for _, v in ipairs(things) do
				if v:IsA("Decal") then
					if pcall(function()
						v.LocalTransparencyModifier = 1
					end) then
						list = list or {}
						table.insert(list, v)
					end
				elseif VISUAL[v.ClassName] and v.Enabled then
					v.Enabled = false
					list = list or {}
					table.insert(list, v)
				end
			end
		end
		extras[p] = list
	end
	local function showExtras(p)
		local list = extras[p]
		if not list then
			return
		end
		extras[p] = nil
		for _, v in ipairs(list) do
			if v:IsA("Decal") then
				pcall(function()
					v.LocalTransparencyModifier = 0
				end)
			elseif v.Parent then
				v.Enabled = true
			end
		end
	end
	local function showPart(p)
		p.LocalTransparencyModifier = 0
		showExtras(p)
	end

	local function hidePart(p, inSpire)
		local near, far = reach(p)
		if far <= RADIUS + 0.5 or near > LIMIT then
			return -- (on the plaza: stays; or so far out the dark covers it anyway)
		end
		p.LocalTransparencyModifier = 1
		hideExtras(p)
		if inSpire then
			table.insert(spire, p)
		elseif near <= 0.01 then
			table.insert(ground, p)
		else
			table.insert(list, { part = p, near = near })
			sorted = false
		end
	end
	local function hideGui(g)
		if (g:IsA("BillboardGui") or g:IsA("SurfaceGui")) and g.AlwaysOnTop and g.Enabled then
			g.Enabled = false
			guis[g] = true
		elseif g:IsA("Highlight") and g.Enabled then
			g.Enabled = false
			guis[g] = true
		end
	end
	local function consider(inst, inSpire)
		if inst:IsA("BasePart") then
			hidePart(inst, inSpire)
		else
			hideGui(inst)
		end
	end

	function Dark.hideWorld()
		local lobby = Workspace:FindFirstChild("Lobby")
		spireModel = lobby and lobby:FindFirstChild("Spire")
		local inSpire = {}
		if spireModel then
			for _, d in ipairs(spireModel:GetDescendants()) do
				inSpire[d] = true
			end
		end
		for _, top in ipairs(Workspace:GetChildren()) do
			if not skipTop(top) then
				if top:IsA("BasePart") then
					consider(top, false)
				end
				for _, d in ipairs(top:GetDescendants()) do
					consider(d, inSpire[d] == true)
				end
			end
		end
		-- anything that appears while it's dark is hidden the same way
		addedConn = Workspace.DescendantAdded:Connect(function(d)
			if not (d:IsA("BasePart") or d:IsA("BillboardGui") or d:IsA("SurfaceGui") or d:IsA("Highlight")) then
				return
			end
			task.defer(function()
				if d.Parent and not skipTop(topOf(d)) then
					consider(d, spireModel ~= nil and d:IsDescendantOf(spireModel))
				end
			end)
		end)
	end

	-- the black box round the plaza, `r` studs out (it grows as the mist rolls back)
	local function placeBox(r)
		local width = 2 * math.pi * r / WALLS + 1.5
		local cfs = {}
		for i, w in ipairs(box.walls) do
			local a = (i - 0.5) / WALLS * math.pi * 2
			local pos = CENTER + V3(math.cos(a) * (r + 1), 40, math.sin(a) * (r + 1))
			w.Size = V3(width, 262, 2)
			cfs[i] = CFrame.lookAt(pos, V3(CENTER.X, pos.Y, CENTER.Z))
		end
		Workspace:BulkMoveTo(box.walls, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		local span = math.min(2 * r + 14, 2040)
		box.ceiling.Size = V3(span, 2, span)
		box.ceiling.CFrame = CFrame.new(CENTER + V3(0, 171, 0))
		box.floor.Size = V3(span, 2, span)
		box.floor.CFrame = CFrame.new(CENTER + V3(0, -91, 0))
	end
	-- (solid, so the camera treats them like any wall and never ends up
	-- outside the dark looking at the back of it)
	local function darkPart(name)
		local p = newPart(name, C.black, Enum.Material.Neon, 0)
		p.CanCollide = true
		p.CanQuery = true
		return p
	end
	function Dark.buildBox()
		-- black, glowing nothing (Neon black is pure black, lit or not), casting
		-- no shadows so the plaza stays in the sun
		box = { walls = {} }
		for i = 1, WALLS do
			box.walls[i] = darkPart("DarkWall")
		end
		box.ceiling = darkPart("DarkSky")
		box.floor = darkPart("DarkFloor")
		placeBox(BOX_RADIUS)
		-- the invisible wall round the plaza
		local n = 28
		local R = I.Wall or (RADIUS + 1)
		for i = 1, n do
			local a = (i - 0.5) / n * math.pi * 2
			local w = newPart("DarkFence", C.black, nil, 1)
			w.CanCollide = true
			w.Size = V3(2 * math.pi * R / n + 1, 40, 2)
			local pos = CENTER + V3(math.cos(a) * (R + 1), 18, math.sin(a) * (R + 1))
			w.CFrame = CFrame.lookAt(pos, V3(CENTER.X, pos.Y, CENTER.Z))
			fence[i] = w
		end
		-- the air goes black too, so the far edge of the plaza fades into the dark
		atmo = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmo then
			atmoWas = { Color = atmo.Color, Decay = atmo.Decay, Haze = atmo.Haze, Glare = atmo.Glare, Density = atmo.Density, Offset = atmo.Offset }
			atmo.Color = C.black
			atmo.Decay = C.black
			atmo.Haze = 0
			atmo.Glare = 0
			atmo.Density = math.max(atmoWas.Density or 0.3, 0.32)
			atmo.Offset = 0
		end
	end

	-- THE MIST: pale 8-bit blocks drifting round the edge of the plaza, in
	-- three bands (small and solid in front, big and faint behind)
	function Dark.buildMist()
		local colors = { C.mist1, C.mist2, C.white, C.mist1, C.mist3 }
		for i = 1, 150 do
			local band = (i % 3) / 2 -- 0, 0.5, 1
			local s = rng:NextNumber(1.2, 2.4) + band * 1.6
			local p = newPart("Mist", colors[rng:NextInteger(1, #colors)], Enum.Material.SmoothPlastic, 0.2 + band * 0.45)
			p.Size = V3(s, s, s)
			mist[i] = {
				part = p,
				angle = rng:NextNumber(0, math.pi * 2),
				out = band * 3.2 + rng:NextNumber(-0.4, 0.8), -- how far behind the front of the mist
				y = rng:NextNumber(0, 1) ^ 1.6 * (2.5 + band * 9) + s / 2,
				phase = rng:NextNumber(0, math.pi * 2),
				drift = rng:NextNumber(-0.05, 0.05),
				base = p.Transparency,
			}
		end
	end
	-- the mist sits `r` studs out from the middle; it moves in 8-bit steps
	local mistClock = 0
	function Dark.stepMist(dt, r, fade)
		mistClock = mistClock + dt
		if mistClock < 1 / 12 then
			return
		end
		local step = mistClock
		mistClock = 0
		local parts, cfs = {}, {}
		local t = os.clock()
		local cam = camera()
		local eye = cam and cam.CFrame.Position
		for i, m in ipairs(mist) do
			m.angle = m.angle + m.drift * step * (30 / math.max(r, 20))
			local rr = r + m.out
			local bob = math.floor(math.sin(t * 1.3 + m.phase) * 2 + 0.5) * 0.25
			local x = math.floor((CENTER.X + math.cos(m.angle) * rr) * 2 + 0.5) / 2
			local z = math.floor((CENTER.Z + math.sin(m.angle) * rr) * 2 + 0.5) / 2
			local pos = V3(x, CENTER.Y + 0.6 + m.y + bob, z)
			parts[i] = m.part
			cfs[i] = CFrame.new(pos)
			-- (a block near the camera melts away, so the mist is something you see
			-- across the plaza, never a wall in front of your face)
			local close = eye and clamp01((13 - (pos - eye).Magnitude) / 7) or 0
			m.part.Transparency = lerp(m.base, 1, math.max(fade or 0, close))
		end
		Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end

	-- THE REVEAL, bit by bit: everything the mist has passed comes back in
	-- three 8-bit steps; the island's ground comes back at the start (it
	-- unrolls under the mist, since the black walls hide the rest of it)
	function Dark.startReveal()
		for _, p in ipairs(ground) do
			showPart(p)
		end
		ground = {}
		if not sorted then
			table.sort(list, function(a, b)
				return a.near < b.near
			end)
			sorted = true
		end
		cursor = 1
		-- anything that appears from now on is simply shown
		if addedConn then
			addedConn:Disconnect()
			addedConn = nil
		end
	end
	function Dark.reveal(r, now)
		while cursor <= #list and list[cursor].near <= r do
			local p = list[cursor].part
			p.LocalTransparencyModifier = 0.66
			table.insert(popping, { part = p, at = now })
			cursor = cursor + 1
		end
		for i = #popping, 1, -1 do
			local e = popping[i]
			local age = now - e.at
			if age > 0.14 then
				showPart(e.part)
				table.remove(popping, i)
			elseif age > 0.07 then
				e.part.LocalTransparencyModifier = 0.33
			end
		end
		placeBox(math.max(BOX_RADIUS, r + 3))
		if r > (I.Wall or RADIUS) + 8 and #fence > 0 then
			for _, w in ipairs(fence) do
				w:Destroy()
			end
			fence = {}
		end
		-- the air lightens back to the lobby's as the mist goes
		if atmo and atmoWas then
			local k = clamp01((r - RADIUS) / (LIMIT * 0.6))
			atmo.Color = C.black:Lerp(atmoWas.Color, k)
			atmo.Decay = C.black:Lerp(atmoWas.Decay, k)
			atmo.Haze = lerp(0, atmoWas.Haze, k)
			atmo.Glare = lerp(0, atmoWas.Glare, k)
			atmo.Offset = lerp(0, atmoWas.Offset, k)
			atmo.Density = lerp(math.max(atmoWas.Density, 0.32), atmoWas.Density, k)
		end
	end
	-- the mist has rolled right back: everything else is shown (but the
	-- Spire), the box fades away in steps and the sky is back
	function Dark.finishRing()
		for i = cursor, #list do
			showPart(list[i].part)
		end
		cursor = #list + 1
		for _, e in ipairs(popping) do
			showPart(e.part)
		end
		popping = {}
		for g in pairs(guis) do
			if g.Parent then
				g.Enabled = true
			end
		end
		guis = {}
		if atmo and atmoWas then
			for k, v in pairs(atmoWas) do
				atmo[k] = v
			end
			atmoWas = nil
		end
		for _, m in ipairs(mist) do
			m.part:Destroy()
		end
		mist = {}
		if box then
			local parts = { box.ceiling, box.floor }
			for _, w in ipairs(box.walls) do
				table.insert(parts, w)
			end
			box = nil
			for step = 1, 4 do
				for _, p in ipairs(parts) do
					p.LocalTransparencyModifier = step / 4
				end
				task.wait(0.08)
			end
			for _, p in ipairs(parts) do
				p:Destroy()
			end
		end
	end
	-- the Spire: where it will rise (for the camera: the middle of the tower,
	-- under the blue flame in its crown - its bridge and stairs reach back
	-- towards the castle, so not the middle of everything; and not its highest
	-- part either, a spike on the rim of the crown, off to one side), how tall
	-- it is, and it rising, bottom to top
	function Dark.spireSpot()
		if #spire == 0 then
			return nil
		end
		local low, high, peak = math.huge, -math.huge, nil
		for _, p in ipairs(spire) do
			local pos = p.Position
			low = math.min(low, pos.Y)
			if pos.Y > high then
				high, peak = pos.Y, pos
			end
		end
		local orb = spireModel and spireModel:FindFirstChild("FlameOrb", true)
		if orb and orb:IsA("BasePart") then
			peak = orb.Position
		end
		return V3(peak.X, (low + high) / 2, peak.Z), V3(0, high - low, 0), low, high
	end
	function Dark.spireModel()
		return spireModel
	end
	function Dark.raiseSpire(seconds)
		table.sort(spire, function(a, b)
			return a.Position.Y < b.Position.Y
		end)
		local n = #spire
		local t0 = os.clock()
		local done = 0
		while done < n do
			local k = clamp01((os.clock() - t0) / seconds)
			local upTo = math.floor(n * k + 0.5)
			for i = done + 1, upTo do
				spire[i].LocalTransparencyModifier = 0
			end
			done = math.max(done, upTo)
			if k >= 1 then
				break
			end
			task.wait()
		end
		for i = done + 1, n do
			spire[i].LocalTransparencyModifier = 0
		end
		for _, p in ipairs(spire) do
			showExtras(p)
		end
		spire = {}
	end
	-- everything back at once (the intro ended early, or at the very end)
	function Dark.undoAll()
		if addedConn then
			addedConn:Disconnect()
			addedConn = nil
		end
		for _, e in ipairs(list) do
			e.part.LocalTransparencyModifier = 0
		end
		for _, p in ipairs(ground) do
			p.LocalTransparencyModifier = 0
		end
		for _, p in ipairs(spire) do
			p.LocalTransparencyModifier = 0
		end
		for _, e in ipairs(popping) do
			e.part.LocalTransparencyModifier = 0
		end
		for p in pairs(extras) do
			showExtras(p)
		end
		list, ground, spire, popping = {}, {}, {}, {}
		for g in pairs(guis) do
			if g.Parent then
				g.Enabled = true
			end
		end
		guis = {}
		if atmo and atmoWas then
			for k, v in pairs(atmoWas) do
				atmo[k] = v
			end
			atmoWas = nil
		end
		mist, fence, box = {}, {}, nil
	end
	function Dark.counts()
		return #list, #ground, #spire
	end
end

----------------------------------------------------------------------
-- Everything else goes away while it's dark: other screens, Roblox's own
-- buttons, other players; and the camera can't pull back out of the dark
----------------------------------------------------------------------
local Hide = {}
do
	-- (kept: our own, the fight's controls - the phone ROLL button lives there -
	-- the title screen, and Roblox's thumbstick and chat bubbles)
	local KEEP = {
		IntroGui = true, IntroCover = true, CombatHud = true, RetroTitle = true,
		TouchGui = true, Chat = true, BubbleChat = true, Freecam = true,
	}
	local CORE = { "PlayerList", "Health", "Backpack", "EmotesMenu", "Chat" }
	local screens = {} -- [ScreenGui] = true: switched off by us
	local coreWas = {}
	local chars = {} -- [part/decal] = true, and humanoids' name displays
	local displays = {} -- [Humanoid] = how it showed names before
	local conns = {}
	local zoomWas = nil

	local function hideScreen(g)
		if g:IsA("ScreenGui") and not KEEP[g.Name] and not g:GetAttribute("IntroKeep") and g.Enabled then
			g.Enabled = false
			screens[g] = true
		end
	end
	local function hideBit(d)
		if d:IsA("BasePart") or d:IsA("Decal") then
			pcall(function()
				d.LocalTransparencyModifier = 1
			end)
			chars[d] = true
		elseif d:IsA("Humanoid") then
			if displays[d] == nil then
				displays[d] = d.DisplayDistanceType
			end
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		elseif d:IsA("BillboardGui") and d.Enabled then
			d.Enabled = false
			chars[d] = true
		end
	end
	local function hideCharacter(char)
		for _, d in ipairs(char:GetDescendants()) do
			hideBit(d)
		end
		table.insert(conns, char.DescendantAdded:Connect(hideBit))
	end
	local function watchPlayer(p)
		if p == player then
			return
		end
		if p.Character then
			hideCharacter(p.Character)
		end
		table.insert(conns, p.CharacterAdded:Connect(hideCharacter))
	end

	function Hide.all()
		for _, g in ipairs(playerGui:GetChildren()) do
			hideScreen(g)
		end
		table.insert(conns, playerGui.ChildAdded:Connect(function(g)
			task.defer(hideScreen, g)
		end))
		for _, name in ipairs(CORE) do
			pcall(function()
				local kind = Enum.CoreGuiType[name]
				coreWas[name] = StarterGui:GetCoreGuiEnabled(kind)
				StarterGui:SetCoreGuiEnabled(kind, false)
			end)
		end
		for _, p in ipairs(Players:GetPlayers()) do
			watchPlayer(p)
		end
		table.insert(conns, Players.PlayerAdded:Connect(watchPlayer))
		zoomWas = player.CameraMaxZoomDistance
		player.CameraMaxZoomDistance = math.min(zoomWas or 128, I.Zoom or 26)
	end

	function Hide.undo()
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
		conns = {}
		for g in pairs(screens) do
			if g.Parent then
				g.Enabled = true
			end
		end
		screens = {}
		for name, was in pairs(coreWas) do
			pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType[name], was)
			end)
		end
		coreWas = {}
		for d in pairs(chars) do
			if d.Parent then
				if d:IsA("BillboardGui") then
					d.Enabled = true
				else
					pcall(function()
						d.LocalTransparencyModifier = 0
					end)
				end
			end
		end
		chars = {}
		for hum, was in pairs(displays) do
			if hum.Parent then
				hum.DisplayDistanceType = was
			end
		end
		displays = {}
		if zoomWas then
			player.CameraMaxZoomDistance = zoomWas
			zoomWas = nil
		end
	end
end

----------------------------------------------------------------------
-- The screen: the big words, the small line under them, Oozlet's bar
----------------------------------------------------------------------
local gui = nil -- IntroGui (made when the intro starts)

-- what you're playing with right now: "Mouse", "Touch" or "Gamepad"
local function controls()
	local ok, last = pcall(function()
		return UserInputService:GetLastInputType()
	end)
	if ok and last then
		if last == Enum.UserInputType.Touch then
			return "Touch"
		elseif string.find(tostring(last), "Gamepad") then
			return "Gamepad"
		end
		return "Mouse"
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	return "Mouse"
end

local Words = {}
do
	local holder, throb, sub, cells = nil, nil, nil, {}
	local style = nil
	local jolt, joltDir = 0, V3(0, 0, 0)
	local shaking = 0
	local subText = nil
	local STYLES = {
		normal = { a = C.yellow, b = C.white, shadow = C.purple },
		danger = { a = C.red, b = C.white, shadow = C.ink, shake = 3 },
		good = { a = C.green, b = C.white, shadow = C.green3 },
		ominous = { a = C.plum, b = C.purple, shadow = C.ink, calm = true },
	}
	local GLYPHS = { "#", "%", "&", "@", "$", "?", "*", "+", "=", "<", ">", "/" }

	function Words.init()
		cells, subText, style, jolt, shaking = {}, nil, nil, 0, 0
		holder = Instance.new("Frame")
		holder.Name = "Words"
		holder.BackgroundTransparency = 1
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.22)
		holder.Size = UDim2.new(1, 0, 0.14, 0)
		holder.Parent = gui
		throb = Instance.new("UIScale")
		throb.Scale = 1
		throb.Parent = holder
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = holder
		sub = Instance.new("TextLabel")
		sub.Name = "How"
		sub.BackgroundTransparency = 1
		sub.AnchorPoint = Vector2.new(0.5, 0)
		sub.Position = UDim2.fromScale(0.5, 0.31)
		sub.Size = UDim2.new(0.8, 0, 0.035, 0)
		sub.TextScaled = true
		sub.Text = ""
		sub.TextColor3 = C.white
		sub.TextStrokeColor3 = C.ink
		sub.TextStrokeTransparency = 0
		sub.Visible = false
		pixelText(sub)
		sub.Parent = gui
	end

	local function letterSize(n)
		local cam = camera()
		local vp = cam and cam.ViewportSize
		local w, h = 1280, 720
		if vp and type(vp.X) == "number" and vp.X > 0 then
			w, h = vp.X, vp.Y
		end
		return math.floor(math.min(math.clamp(h * 0.085, 26, 92), w * 0.9 / math.max(n, 1) / 0.95))
	end

	local function clearCells()
		for _, c in ipairs(cells) do
			c.frame:Destroy()
		end
		cells = {}
	end

	-- Puts new words up. `times` (optional) gives each letter the moment it
	-- starts to appear (seconds from now); without it they all scramble in
	-- at once, quickly. `slamLast` = the last letter slams down (the BOOM).
	function Words.set(text, styleName, times, slamLast)
		clearCells()
		style = STYLES[styleName or "normal"] or STYLES.normal
		local n = utf8.len(text) or #text
		local px = letterSize(n)
		local now = os.clock()
		local i = 0
		for _, code in utf8.codes(text) do
			i = i + 1
			local ch = utf8.char(code)
			local space = ch == " "
			local frame = Instance.new("Frame")
			frame.Name = "Letter" .. i
			frame.BackgroundTransparency = 1
			frame.LayoutOrder = i
			frame.Size = UDim2.fromOffset(space and px * 0.55 or px * 0.95, px)
			local pop = Instance.new("UIScale")
			pop.Scale = 1
			pop.Parent = frame
			local shadow = Instance.new("TextLabel")
			shadow.Name = "Shadow"
			shadow.BackgroundTransparency = 1
			shadow.Position = UDim2.fromOffset(math.max(2, px * 0.07), math.max(2, px * 0.07))
			shadow.Size = UDim2.fromScale(1, 1)
			shadow.TextScaled = true
			shadow.Text = ""
			shadow.TextColor3 = style.shadow
			pixelText(shadow)
			shadow.Parent = frame
			local main = Instance.new("TextLabel")
			main.Name = "Main"
			main.BackgroundTransparency = 1
			main.Size = UDim2.fromScale(1, 1)
			main.TextScaled = true
			main.Text = ""
			main.TextColor3 = style.a
			main.TextStrokeColor3 = C.ink
			main.TextStrokeTransparency = 0
			pixelText(main)
			main.Parent = frame
			frame.Parent = holder
			local start = now + ((times and times[i]) or (i - 1) * 0.02)
			table.insert(cells, {
				frame = frame, main = main, shadow = shadow, pop = pop, char = ch, space = space,
				start = start, scramble = (times and (i <= 4 and 0.16 or 0.1)) or 0.12,
				locked = space, lastSwap = 0, slam = slamLast and i == n,
				x = 0, y = 0,
			})
		end
	end

	local function lock(c, now)
		c.locked = true
		c.main.Text = c.char
		c.shadow.Text = c.char
		if c.slam then
			-- the "!": slams straight down, and the whole screen feels it
			c.pop.Scale = 3
			c.slamAt = now
			play("Boom", 1)
			kick(1.2, 6)
			if gui and gui:FindFirstChild("Flash") then
				gui.Flash.BackgroundTransparency = 0.35
				tween(gui.Flash, 0.45, { BackgroundTransparency = 1 })
			end
			jolt = 1.4
		else
			c.pop.Scale = 1.35
			play("Blip", 1, 0.9 + rng:NextNumber() * 0.25)
		end
	end

	-- is every letter up?
	function Words.done()
		for _, c in ipairs(cells) do
			if not c.locked then
				return false
			end
		end
		return true
	end
	-- skip the rest of the build-up: everything locks in at once
	function Words.finish()
		local now = os.clock()
		for _, c in ipairs(cells) do
			if not c.locked then
				lock(c, now)
			end
		end
	end
	-- a punch landed: the words jump
	function Words.jolt(power)
		jolt = math.max(jolt, power or 1)
		local a = rng:NextNumber(0, math.pi * 2)
		joltDir = V3(math.cos(a), math.sin(a), 0)
	end
	-- the small line under the words (nil takes it away)
	function Words.hint(text)
		subText = text
		sub.Text = text or ""
		sub.Visible = text ~= nil
	end
	-- the words burst into pixels (Oozlet popped)
	function Words.burst()
		Words.hint(nil)
		local list = cells
		cells = {}
		for _, c in ipairs(list) do
			local vx, vy = rng:NextNumber(-500, 500), rng:NextNumber(-600, -150)
			local rot = rng:NextNumber(-400, 400)
			local t0 = os.clock()
			local startPos = c.frame.AbsolutePosition
			c.frame.Parent = gui
			c.frame.Position = UDim2.fromOffset(startPos and startPos.X or 0, startPos and startPos.Y or 0)
			addFx(function()
				local t = os.clock() - t0
				if t > 0.9 then
					return false
				end
				c.frame.Position = UDim2.fromOffset((startPos and startPos.X or 0) + vx * t, (startPos and startPos.Y or 0) + vy * t + 900 * t * t)
				c.frame.Rotation = rot * t
				c.main.TextTransparency = clamp01(t / 0.9)
				c.shadow.TextTransparency = clamp01(t / 0.9)
				c.main.TextStrokeTransparency = clamp01(t / 0.9)
				return true
			end, function()
				c.frame:Destroy()
			end)
		end
	end
	function Words.clear()
		clearCells()
		Words.hint(nil)
	end

	-- every frame: scrambling letters, the heartbeat, the jolts, the shakes
	function Words.step(dt)
		if not holder then
			return
		end
		local now = os.clock()
		local done = true
		for i, c in ipairs(cells) do
			if not c.locked then
				done = false
				if now >= c.start then
					if c.slam or now >= c.start + c.scramble then
						lock(c, now)
					elseif now - c.lastSwap > 0.04 then
						-- scrambling: a random symbol every few frames
						c.lastSwap = now
						local g = GLYPHS[rng:NextInteger(1, #GLYPHS)]
						c.main.Text = g
						c.shadow.Text = g
					end
				end
			end
			-- each letter settles back from its pop, and bobs a little (alive)
			if c.slam and c.slamAt then
				c.pop.Scale = 1 + 2 * math.max(0, 1 - (now - c.slamAt) / 0.12) + 0.25 * wobble(now - c.slamAt - 0.12, 30, 9) * (now - c.slamAt > 0.12 and 1 or 0)
			else
				c.pop.Scale = 1 + (c.pop.Scale - 1) * math.exp(-dt * 14)
			end
			if c.locked and not c.space then
				local bob = math.sin(now * 5 + i * 0.8) * 2
				local sx, sy = 0, bob
				if style and style.shake then
					sx = sx + rng:NextNumber(-style.shake, style.shake)
					sy = sy + rng:NextNumber(-style.shake, style.shake)
				end
				if shaking > 0 then
					sx = sx + rng:NextNumber(-1, 1) * shaking * 4
					sy = sy + rng:NextNumber(-1, 1) * shaking * 4
				end
				c.main.Position = UDim2.fromOffset(sx, sy)
				c.shadow.Position = UDim2.fromOffset(sx + 4, sy + 4)
				if c.char == "!" then
					c.frame.Rotation = math.sin(now * 10 + i) * 12
				end
			end
		end
		shaking = math.max(0, shaking - dt * 3)
		-- the heartbeat: ba-dum... ba-dum, flashing yellow and white on the beat
		local beat = 0
		if done and #cells > 0 and style and not style.calm then
			local k = now % 1
			beat = math.exp(-k * 12) + 0.6 * math.exp(-math.max(0, k - 0.2) * 12) * (k > 0.2 and 1 or 0)
		end
		jolt = jolt * math.exp(-dt * 8)
		throb.Scale = 1 + 0.1 * beat + 0.22 * jolt
		holder.Position = UDim2.new(0.5, joltDir.X * jolt * 18, 0.22, joltDir.Y * jolt * 18)
		if style then
			local col = (beat > 0.45) and style.b or style.a
			for _, c in ipairs(cells) do
				c.main.TextColor3 = col
			end
		end
		-- the small line blinks slowly
		if subText then
			sub.Visible = (now % 1.2) < 0.85
		end
	end
	function Words.shake(power)
		shaking = math.max(shaking, power or 1)
	end
end

-- Oozlet's bar across the top: an Undertale box, its name, and its health
local Bar = {}
do
	local frame, fill, chip, name = nil, nil, nil, nil
	local shown, frac, chipFrac, flash, shake = false, 1, 1, 0, 0
	function Bar.init()
		shown, frac, chipFrac, flash, shake = false, 1, 1, 0, 0
		frame = Instance.new("Frame")
		frame.Name = "OozletBar"
		frame.AnchorPoint = Vector2.new(0.5, 0)
		frame.Position = UDim2.new(0.5, 0, 0, -120)
		frame.Size = UDim2.fromOffset(440, 64)
		frame.BackgroundColor3 = C.black
		frame.BorderSizePixel = 0
		frame.Parent = gui
		local edge = Instance.new("UIStroke")
		edge.Color = C.white
		edge.Thickness = 3
		edge.Parent = frame
		name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Position = UDim2.fromOffset(14, 6)
		name.Size = UDim2.new(1, -28, 0, 22)
		name.TextScaled = true
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Text = O.Name or "OOZLET"
		name.TextColor3 = C.white
		pixelText(name)
		name.Parent = frame
		local back = Instance.new("Frame")
		back.BackgroundColor3 = C.darkRed
		back.BorderSizePixel = 0
		back.Position = UDim2.fromOffset(14, 34)
		back.Size = UDim2.new(1, -28, 0, 18)
		back.Parent = frame
		chip = Instance.new("Frame")
		chip.BackgroundColor3 = C.yellow
		chip.BorderSizePixel = 0
		chip.Size = UDim2.fromScale(1, 1)
		chip.Parent = back
		fill = Instance.new("Frame")
		fill.BackgroundColor3 = C.green
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromScale(1, 1)
		fill.Parent = back
	end
	function Bar.show()
		if shown then
			return
		end
		shown = true
		tween(frame, 0.5, { Position = UDim2.new(0.5, 0, 0, 22) }, Enum.EasingStyle.Back)
	end
	function Bar.hide()
		shown = false
		tween(frame, 0.4, { Position = UDim2.new(0.5, 0, 0, -120) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	function Bar.set(hp, max)
		local f = clamp01((hp or 0) / math.max(max or 1, 1))
		if f < frac then
			flash, shake = 1, 1
		end
		frac = f
	end
	function Bar.step(dt)
		if not frame then
			return
		end
		chipFrac = chipFrac + (frac - chipFrac) * math.min(1, dt * 3)
		fill.Size = UDim2.fromScale(frac, 1)
		chip.Size = UDim2.fromScale(math.max(frac, chipFrac), 1)
		flash = math.max(0, flash - dt * 6)
		fill.BackgroundColor3 = C.green:Lerp(C.white, flash)
		shake = math.max(0, shake - dt * 5)
		if shown then
			frame.Rotation = shake > 0 and rng:NextNumber(-2, 2) * shake or 0
		end
	end
end

-- The little arrow bouncing over Oozlet until you first hit it
local Arrow = {}
do
	local anchor, bb = nil, nil
	function Arrow.show()
		if anchor then
			return
		end
		anchor = newPart("ArrowAnchor", C.white, nil, 1)
		anchor.Size = V3(0.2, 0.2, 0.2)
		bb = Instance.new("BillboardGui")
		bb.Name = "IntroArrow"
		bb.Size = UDim2.fromOffset(40, 40)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb:SetAttribute("RetroSkip", true)
		bb.Adornee = anchor
		bb.Parent = anchor
		local art = Instance.new("Frame")
		art.BackgroundTransparency = 1
		art.Size = UDim2.fromScale(1, 1)
		art.Parent = bb
		-- a chunky pixel arrow pointing down
		local rows = { "YYYYYYY", ".YYYYY.", "..YYY..", "...Y..." }
		for y, row in ipairs(rows) do
			for x = 1, #row do
				if string.sub(row, x, x) == "Y" then
					local px = Instance.new("Frame")
					px.BorderSizePixel = 0
					px.BackgroundColor3 = C.yellow
					px.Size = UDim2.fromScale(1 / 7 + 0.01, 0.25 + 0.01)
					px.Position = UDim2.fromScale((x - 1) / 7, (y - 1) * 0.25)
					px:SetAttribute("RetroSkip", true)
					px.Parent = art
				end
			end
		end
	end
	function Arrow.hide()
		if anchor then
			anchor:Destroy()
			anchor, bb = nil, nil
		end
	end
	function Arrow.step(top, now)
		if anchor and top then
			anchor.CFrame = CFrame.new(top + V3(0, 2.2 + math.abs(math.sin(now * 4)) * 1.2, 0))
		end
	end
end

----------------------------------------------------------------------
-- OOZLET: a little block of slime (drawn from what the server sends)
----------------------------------------------------------------------
local Oz = {}
do
	local model = nil -- the server's invisible Oozlet (its attributes say everything)
	local body = nil
	local facing = V3(0, 0, 1)
	local hop = nil -- the hop it's on: { from, to, at, time, height }
	local lastLandAt = -math.huge
	local landed = true
	local action = { name = "", at = -math.huge, pos = CENTER, r = 0, tell = 0 }
	local mood = "Happy"
	local hp, maxHp = O.Health or 12, O.Health or 12
	local hitAt = -math.huge
	local nextBlink, blinkUntil = 0, 0
	local popped = false
	local burstDone = false
	local tele = nil -- the red circle on the floor
	local cracked = false
	local listeners = {} -- things the rest of the script wants to hear about
	local stars = nil

	function Oz.on(name, fn)
		listeners[name] = fn
	end
	local function tell(name, ...)
		local fn = listeners[name]
		if fn then
			task.spawn(fn, ...)
		end
	end

	local function build()
		body = {}
		local function add(name, color, material, transparency)
			local p = newPart(name, color, material, transparency)
			table.insert(body, p)
			return p
		end
		body.skirt = add("Skirt", C.green2, nil, 0.12)
		body.shell = add("Shell", C.green, nil, 0.2)
		body.cap = add("Cap", C.green, nil, 0.2)
		body.inner = add("Depths", C.green3, nil, 0.35)
		body.heart = add("Heart", O.HeartColor or C.yellow, Enum.Material.Neon, 0)
		body.shine = add("Shine", C.white, Enum.Material.Neon, 0.15)
		body.shine2 = add("Shine", C.white, Enum.Material.Neon, 0.35)
		body.eyes, body.pupils, body.glints, body.brows, body.cheeks = {}, {}, {}, {}, {}
		for i = 1, 2 do
			body.eyes[i] = add("Eye", C.white)
			body.pupils[i] = add("Pupil", C.ink)
			body.glints[i] = add("Glint", C.white, Enum.Material.Neon)
			body.brows[i] = add("Brow", C.ink)
			body.cheeks[i] = add("Cheek", C.pink, nil, 0.2)
		end
		body.mouth = add("Mouth", C.ink)
		body.mouthL = add("Mouth", C.ink)
		body.mouthR = add("Mouth", C.ink)
		body.band = add("Crown", O.CrownColor or C.yellow)
		body.points = {}
		for i = 1, 4 do
			body.points[i] = add("CrownPoint", O.CrownColor or C.yellow)
		end
		body.gem = add("CrownGem", C.red, Enum.Material.Neon)
		body.cracks = {}
		for i = 1, 5 do
			body.cracks[i] = add("Crack", C.yellow, Enum.Material.Neon, 1)
		end
		body.shadow = newPart("Shadow", C.ink, nil, 0.55, Enum.PartType.Cylinder)
		local light = Instance.new("PointLight")
		light.Color = C.green
		light.Range = 10
		light.Brightness = 0.8
		light.Shadows = false
		light.Parent = body.heart
		body.light = light
	end

	-- where it is at time t on the server's clock (partway along a hop, or where it landed)
	local function posAt(t)
		if not hop then
			return CENTER + V3(0, 0.8, 0)
		end
		local u = (t - hop.at) / hop.time
		if u >= 1 then
			return hop.to, 1
		elseif u <= 0 then
			return hop.from, 0
		end
		return hop.from:Lerp(hop.to, u) + V3(0, hop.height * 4 * u * (1 - u), 0), u
	end
	function Oz.top()
		if not body then
			return nil
		end
		return body.band.Position
	end
	function Oz.position()
		return (posAt(serverNow()))
	end

	-- read what the server says now
	local function read()
		local m = model
		local at = m:GetAttribute("HopAt")
		if at and (not hop or hop.at ~= at) then
			local height = m:GetAttribute("HopHeight") or 0
			hop = {
				from = m:GetAttribute("HopFrom") or CENTER, to = m:GetAttribute("HopTo") or CENTER, at = at,
				time = m:GetAttribute("HopTime") or 0.4, height = height,
			}
			landed = height < 0.3 -- (only a real hop lands with a squash and a sound)
		end
		local aAt = m:GetAttribute("ActionAt")
		if aAt and aAt ~= action.at then
			action = {
				name = m:GetAttribute("Action") or "", at = aAt, pos = m:GetAttribute("ActionPos") or CENTER,
				r = m:GetAttribute("ActionR") or 0, tell = m:GetAttribute("ActionTell") or 0,
			}
			Oz.startAction(action)
		end
		local newMood = m:GetAttribute("Mood") or "Happy"
		if newMood ~= mood then
			local old = mood
			mood = newMood
			tell("Mood", newMood, old)
		end
		local h = m:GetAttribute("Health") or hp
		maxHp = m:GetAttribute("MaxHealth") or maxHp
		if h < hp then
			hitAt = os.clock()
			local pos = posAt(serverNow())
			spawnBits(pos + V3(0, SIZE * 0.5, 0), 6, { C.green, C.green2, C.white }, 22, 0.45, 0.4, 0.7, pos.Y)
			play("Squish", 0.8, 1.1 + rng:NextNumber() * 0.2)
			tell("Hit", h, maxHp)
		end
		hp = h
	end

	-- the red circle on the floor for a move that lands somewhere
	local function newTelegraph(a)
		if tele then
			tele.remove()
		end
		local rim = newPart("WarnRim", C.white, Enum.Material.Neon, 0.35, Enum.PartType.Cylinder)
		local back = newPart("WarnBack", C.darkRed, Enum.Material.Neon, 0.55, Enum.PartType.Cylinder)
		local fill = newPart("WarnFill", C.red, Enum.Material.Neon, 0.3, Enum.PartType.Cylinder)
		local t = { pos = a.pos, shown = a.pos, r = a.r, at = a.at, name = a.name, tell = a.tell }
		function t.remove()
			rim:Destroy()
			back:Destroy()
			fill:Destroy()
			if tele == t then
				tele = nil
			end
		end
		function t.step(now, dt)
			t.shown = t.shown:Lerp(t.pos, math.min(1, dt * 12))
			local y = t.pos.Y + 0.08
			local held = t.name == "Hold"
			-- (it fills on the server's clock: full exactly as Oozlet lands)
			local since = serverNow() - t.at
			local k
			if held then
				k = clamp01(since / 0.45)
			else
				k = clamp01(since / math.max(t.tell, 0.1))
			end
			placeDisc(rim, t.shown, t.r + 0.3, y - 0.02)
			placeDisc(back, t.shown, t.r, y)
			placeDisc(fill, t.shown, math.max(0.2, t.r * k), y + 0.02)
			local pulse = held and k >= 1 and (0.5 + 0.5 * math.sin(now * 14)) or 0
			fill.Transparency = 0.3 - 0.2 * pulse
			rim.Transparency = 0.35 - 0.3 * pulse
		end
		tele = t
		return t
	end

	-- a landing: squash, a ring of dust, a thump, the camera feels it if it's close
	local function land(pos, big, radius)
		lastLandAt = os.clock()
		local root = myRoot()
		local d = root and flat(root.Position - pos).Magnitude or 99
		if big then
			shockRing(pos, 1.5, ((radius or 0) > 0 and radius or 6) * 1.1, 0.32, C.white, pos.Y + 0.3)
			spawnBits(pos + V3(0, 0.5, 0), 10, { C.mist1, C.green, C.white }, 26, 0.5, 0.2, 0.8, pos.Y)
			play("Slam", 1, 1.15)
			kick(math.clamp(1.1 - d / 30, 0.15, 1), 3)
		else
			play("Hop", mood == "Happy" and 0.45 or 0.7, mood == "Happy" and 1.35 or 1.1)
			if d < 14 and mood ~= "Happy" then
				kick(0.18)
			end
		end
	end

	-- a move starting (from the server)
	function Oz.startAction(a)
		local pos = posAt(serverNow())
		if a.name == "Hold" then
			landed = true -- (it rises into the air: no landing when it gets there)
			if tele and tele.name == "Hold" then
				tele.pos = a.pos -- (it drifted over you: the circle follows)
			else
				newTelegraph(a)
				play("Wake", 0.6, 1.3)
			end
		elseif a.name == "Drop" then
			local untilLanding = math.max(0, a.at + a.tell - serverNow())
			if tele then
				tele.name = "Drop"
				tele.pos = a.pos
				local t = tele
				task.delay(untilLanding, function()
					if t == tele then
						t.remove()
					end
					land(a.pos, true, a.r)
				end)
			else
				task.delay(untilLanding, function()
					land(a.pos, true, a.r)
				end)
			end
		elseif a.name == "Slam" or a.name == "Bounce" then
			landed = true -- (the big landing below is the only one)
			local t = newTelegraph(a)
			task.delay(math.max(0, a.at + a.tell - serverNow()), function()
				if t == tele then
					t.remove()
				end
				land(a.pos, true, a.r)
			end)
		elseif a.name == "Wake" then
			play("Wake", 1, 1.25)
			bubble(pos + V3(0, SIZE * 1.3, 0), "!", 1)
			kick(0.5, 3)
		elseif a.name == "Wiggle" then
			bubble(pos + V3(0, SIZE * 1.3, 0), "note", 1.1)
		elseif a.name == "Bump" then
			bubble(pos + V3(0, SIZE * 1.3, 0), "heart", 1.2)
		elseif a.name == "Crack" then
			task.delay(math.max(0, a.at + a.tell * 0.45 - serverNow()), function()
				cracked = true
				local p = posAt(serverNow())
				play("Crack", 1)
				shockRing(p, 1.5, a.r > 0 and a.r or 9, 0.4, C.white, p.Y + 0.3)
				spawnBits(p + V3(0, SIZE * 0.6, 0), 14, { C.green, C.green2, C.yellow }, 30, 0.55, 0.5, 1, p.Y)
				kick(0.8, 4)
			end)
		elseif a.name == "Dizzy" then
			stars = { untilT = os.clock() + a.tell }
		elseif a.name == "Pop" then
			popped = true
			if tele then
				tele.remove()
			end
		end
	end

	-- the look it has right now
	local function pose(now, t, dt)
		local at, u = posAt(t)
		local P = { lift = 0, sx = 1, sy = 1, sz = 1, lean = 0, roll = 0, eyes = 1, angry = 0, mouth = 0, shake = 0, flash = 0, red = 0, happy = 1 }
		local angry = mood ~= "Happy"
		P.angry = angry and 1 or 0
		P.happy = angry and 0 or 1
		-- breathing
		local br = math.sin(now * (angry and 4.5 or 3))
		P.sy = P.sy + 0.035 * br
		P.sx = P.sx - 0.02 * br
		P.sz = P.sz - 0.02 * br
		-- a hop: stretched in the air, squashed as it lands
		if hop and hop.height >= 0.3 and u and u > 0 and u < 1 then
			local k = math.sin(u * math.pi)
			P.sy = P.sy + 0.22 * k
			P.sx = P.sx - 0.1 * k
			P.sz = P.sz - 0.1 * k
			if u < 0.12 then
				P.sy = P.sy - 0.2 * (1 - u / 0.12)
				P.sx = P.sx + 0.12 * (1 - u / 0.12)
			end
		end
		if hop and u and u >= 1 and not landed then
			landed = true
			land(hop.to, false)
		end
		local sinceLand = now - lastLandAt
		if sinceLand < 0.6 then
			local w = wobble(sinceLand, 20, 7)
			P.sy = P.sy - 0.28 * w
			P.sx = P.sx + 0.16 * w
			P.sz = P.sz + 0.16 * w
		end
		-- a punch: it squishes, flashes white, eyes screwed shut
		local sinceHit = now - hitAt
		if sinceHit < 0.5 then
			local w = wobble(sinceHit, 22, 8)
			P.sx = P.sx + 0.25 * w
			P.sz = P.sz + 0.25 * w
			P.sy = P.sy - 0.25 * w
			P.flash = clamp01(1 - sinceHit / 0.12)
			P.eyes = sinceHit < 0.25 and 0.25 or 1
			P.mouth = 1
		end
		-- blinking
		if now > nextBlink then
			nextBlink = now + rng:NextNumber(2.5, 4.5)
			blinkUntil = now + 0.12
		end
		if now < blinkUntil then
			P.eyes = math.min(P.eyes, 0.12)
		end
		-- the move it's doing
		local a = action
		local ta = t - a.at
		if a.name == "Wake" and ta < a.tell then
			local k = ta / math.max(a.tell, 0.1)
			if k < 0.2 then
				P.sy = P.sy - 0.35 * (k / 0.2)
				P.sx = P.sx + 0.2 * (k / 0.2)
			else
				P.sy = P.sy + 0.25 * wobble(ta - a.tell * 0.2, 16, 4)
				P.shake = 0.25 * (1 - k)
				P.mouth = 1
			end
			P.red = (math.floor(ta * 8) % 2 == 0) and (1 - k) or 0
			P.eyes = 1.25
		elseif a.name == "Wiggle" and ta < 1.2 then
			local env = math.sin(math.min(1, ta / 1.2) * math.pi)
			P.roll = 0.28 * math.sin(ta * 14) * env
			P.lift = math.abs(math.sin(ta * 9)) * 0.5 * env
		elseif a.name == "Bump" then
			P.eyes = math.min(P.eyes, 0.35)
		elseif a.name == "Hold" or (a.name == "Drop" and ta < a.tell) then
			P.sy = P.sy + 0.22
			P.sx = P.sx - 0.1
			P.sz = P.sz - 0.1
			P.roll = 0.12 * math.sin(now * 9)
			P.eyes = 1.25
			P.mouth = 1
		elseif a.name == "Slam" and ta < a.tell then
			local k = ta / math.max(a.tell, 0.1)
			if k < 0.8 then
				P.sy = P.sy + 0.2 * k
				P.sx = P.sx - 0.08 * k
				P.sz = P.sz - 0.08 * k
			else
				P.sy = P.sy + 0.3
				P.sx = P.sx - 0.15
				P.sz = P.sz - 0.15
			end
			P.eyes = 1.2
		elseif a.name == "Dizzy" and ta < a.tell then
			P.roll = 0.2 * math.sin(ta * 6)
			P.eyes = 0.45
			P.mouth = 0.6
		elseif a.name == "Tired" and ta < a.tell then
			P.sy = P.sy + 0.08 * math.sin(ta * 16)
			P.mouth = 1
			P.eyes = 0.6
		elseif a.name == "Crack" and ta < a.tell then
			P.shake = 0.4
			P.flash = (math.floor(ta * 10) % 2 == 0) and 0.5 or 0
			P.eyes = 1.3
			P.mouth = 1
		elseif a.name == "Pop" then
			-- it swells up, flashing... and bursts
			local k = clamp01(ta / 0.5)
			P.sx = P.sx + 0.45 * k
			P.sy = P.sy + 0.45 * k
			P.sz = P.sz + 0.45 * k
			P.flash = (math.floor(ta * 16) % 2 == 0) and 0.8 or 0.2
			P.shake = 0.3 * k
			P.eyes = 1.3
			P.mouth = 1
		end
		return at, P
	end

	-- puts every block where the look says
	local function place(at, P, now)
		local D = SIZE
		local H = D * 0.86
		local w, h, d = D * P.sx, H * P.sy, D * P.sz
		local jitter = P.shake > 0 and V3(rng:NextNumber(-1, 1) * P.shake, 0, rng:NextNumber(-1, 1) * P.shake) or V3(0, 0, 0)
		local base = at + V3(0, P.lift, 0) + jitter
		local frame = CFrame.lookAt(base, base + facing) * CFrame.Angles(P.lean, 0, P.roll)
		local parts, cfs = {}, {}
		local function put(p, size, cf)
			p.Size = size
			table.insert(parts, p)
			table.insert(cfs, cf)
		end
		-- the slime: a stepped block (a wider foot, the body, a narrower top: 8-bit round)
		local shellColor = C.green:Lerp(C.white, P.flash):Lerp(C.red, P.red * 0.8)
		body.shell.Color = shellColor
		body.cap.Color = shellColor
		body.skirt.Color = C.green2:Lerp(C.white, P.flash * 0.6)
		put(body.skirt, V3(w * 1.08, h * 0.16, d * 1.08), frame * CFrame.new(0, h * 0.08, 0))
		put(body.shell, V3(w, h * 0.8, d), frame * CFrame.new(0, h * 0.5, 0))
		put(body.cap, V3(w * 0.72, h * 0.14, d * 0.72), frame * CFrame.new(0, h * 0.95, 0))
		put(body.inner, V3(w * 0.62, h * 0.5, d * 0.62), frame * CFrame.new(0, h * 0.45, 0))
		local beat = math.exp(-((now * 1.4) % 1) * 9)
		local hs = D * 0.2 * (1 + 0.18 * beat)
		put(body.heart, V3(hs, hs, hs), frame * CFrame.new(0, h * 0.45, 0))
		body.light.Brightness = 0.6 + 0.5 * beat
		local front = -d / 2 - 0.04
		put(body.shine, V3(D * 0.16, D * 0.1, 0.05), frame * CFrame.new(-w * 0.28, h * 0.76, front))
		put(body.shine2, V3(D * 0.07, D * 0.07, 0.05), frame * CFrame.new(-w * 0.14, h * 0.8, front))
		-- the eyes look at you
		local cam = camera()
		local look = V3(0, 0, 0)
		if cam then
			local rel = frame:PointToObjectSpace(cam.CFrame.Position)
			if rel.Magnitude > 0.1 then
				rel = rel.Unit
				look = V3(math.clamp(rel.X, -1, 1), math.clamp(rel.Y, -1, 1), 0)
			end
		end
		local eyeH = D * 0.3 * math.clamp(P.eyes, 0.08, 1.3)
		for i, side in ipairs({ -1, 1 }) do
			local ex, ey = side * w * 0.19, h * 0.56
			put(body.eyes[i], V3(D * 0.24 * math.clamp(P.eyes, 1, 1.15), eyeH, 0.07), frame * CFrame.new(ex, ey, front))
			local px, py = ex + look.X * D * 0.05, ey + look.Y * D * 0.05
			put(body.pupils[i], V3(D * 0.13, math.min(D * 0.17, eyeH * 0.8), 0.07), frame * CFrame.new(px, py, front - 0.03))
			put(body.glints[i], V3(D * 0.05, D * 0.05 * math.min(1, P.eyes * 2), 0.05), frame * CFrame.new(px - D * 0.03, py + D * 0.05, front - 0.06))
			-- angry brows, slanting down to the middle
			local bt = P.angry > 0.5 and 0 or 1
			body.brows[i].Transparency = bt
			put(body.brows[i], V3(D * 0.27, D * 0.07, 0.07), frame * CFrame.new(ex, ey + D * 0.21, front - 0.02) * CFrame.Angles(0, 0, side * 0.45))
			-- rosy cheeks while it's happy
			body.cheeks[i].Transparency = P.happy > 0.5 and 0.2 or 1
			put(body.cheeks[i], V3(D * 0.12, D * 0.07, 0.05), frame * CFrame.new(side * w * 0.34, h * 0.42, front))
		end
		-- the mouth: a little smile, a flat angry line, or wide open
		local mouthY = h * 0.34
		if P.mouth > 0.5 then
			put(body.mouth, V3(D * 0.15, D * 0.15 * P.mouth, 0.07), frame * CFrame.new(0, mouthY - D * 0.03, front))
			body.mouthL.Transparency, body.mouthR.Transparency = 1, 1
		elseif P.angry > 0.5 then
			put(body.mouth, V3(D * 0.2, D * 0.05, 0.07), frame * CFrame.new(0, mouthY, front))
			body.mouthL.Transparency, body.mouthR.Transparency = 1, 1
		else
			put(body.mouth, V3(D * 0.14, D * 0.05, 0.07), frame * CFrame.new(0, mouthY, front))
			body.mouthL.Transparency, body.mouthR.Transparency = 0, 0
		end
		put(body.mouthL, V3(D * 0.05, D * 0.05, 0.07), frame * CFrame.new(-D * 0.095, mouthY + D * 0.04, front))
		put(body.mouthR, V3(D * 0.05, D * 0.05, 0.07), frame * CFrame.new(D * 0.095, mouthY + D * 0.04, front))
		-- the tiny crown
		local topY = h * 1.02
		put(body.band, V3(D * 0.4, D * 0.1, D * 0.4), frame * CFrame.new(0, topY + D * 0.05, 0))
		for i, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
			put(body.points[i], V3(D * 0.08, D * 0.08, D * 0.08), frame * CFrame.new(c[1] * D * 0.15, topY + D * 0.14, c[2] * D * 0.15) * CFrame.Angles(0, math.pi / 4, 0))
		end
		put(body.gem, V3(D * 0.07, D * 0.07, 0.05), frame * CFrame.new(0, topY + D * 0.05, -D * 0.2 - 0.03))
		-- the cracks (once its shell has cracked)
		local zig = { { 0.05, 0.62, 0.5 }, { 0.12, 0.5, -0.5 }, { 0.06, 0.38, 0.5 }, { -0.2, 0.7, -0.6 }, { -0.26, 0.58, 0.6 } }
		for i, z in ipairs(zig) do
			body.cracks[i].Transparency = cracked and 0.05 or 1
			put(body.cracks[i], V3(D * 0.04, D * 0.16, 0.05), frame * CFrame.new(w * z[1], h * z[2], front - 0.05) * CFrame.Angles(0, 0, z[3]))
		end
		-- its shadow on the floor (smaller the higher it is)
		local floorY = at.Y
		if action.name == "Hold" or action.name == "Drop" or action.name == "Slam" then
			floorY = action.pos.Y
		elseif hop then
			local k = clamp01((serverNow() - hop.at) / hop.time)
			floorY = lerp(hop.from.Y, hop.to.Y, k)
		end
		local height = math.max(0, base.Y - floorY)
		local s = D * 1.15 * (1 - clamp01(height / 16) * 0.5)
		body.shadow.Transparency = 0.55 + clamp01(height / 20) * 0.3
		put(body.shadow, V3(0.1, s, s), CFrame.new(at.X, floorY + 0.06, at.Z) * CFrame.Angles(0, 0, math.pi / 2))
		Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end

	local function burst(at)
		burstDone = true
		-- (the floor under it: it can pop in the middle of a hop)
		local groundY = (action.pos and action.pos.Y) or at.Y
		local floorAt = V3(at.X, groundY, at.Z)
		local mid = at + V3(0, SIZE * 0.5, 0)
		spawnBits(mid, 26, { C.green, C.green2, C.green3, C.white }, 34, 0.6, 0.7, 1.4, groundY)
		spawnBits(mid, 10, { C.yellow, C.gold, C.pink }, 26, 0.4, 1.2, 1.6, groundY)
		shockRing(floorAt, 1.5, 12, 0.45, C.white, groundY + 0.3)
		play("Pop", 1)
		kick(1, 6)
		-- the crown pops off and bounces away
		local crown = newPart("LostCrown", O.CrownColor or C.yellow)
		crown.Size = V3(SIZE * 0.4, SIZE * 0.14, SIZE * 0.4)
		table.insert(bits, { part = crown, pos = mid + V3(0, SIZE * 0.4, 0), vel = V3(rng:NextNumber(-6, 6), 34, rng:NextNumber(-6, 6)), age = 0, life = 2.4, size = SIZE * 0.14, floor = groundY })
		for _, p in ipairs(body) do
			p.Transparency = 1
		end
		body.shadow.Transparency = 1
		body.light.Enabled = false
		tell("Burst", floorAt)
	end

	function Oz.start(m)
		-- (a fresh start, even if it's been played before: DEV: Replay Intro)
		model = m
		hop, landed, lastLandAt = nil, true, -math.huge
		action = { name = "", at = -math.huge, pos = CENTER, r = 0, tell = 0 }
		mood, hp, maxHp, hitAt = "Happy", O.Health or 12, O.Health or 12, -math.huge
		popped, burstDone, cracked, stars, tele = false, false, false, nil, nil
		facing = V3(0, 0, 1)
		build()
		read()
		nextBlink = os.clock() + 2
	end

	function Oz.step(dt, now)
		if not model or not body then
			return
		end
		if model.Parent then
			read()
		end
		local t = serverNow()
		local at, P = pose(now, t, dt)
		-- which way it faces: at you once it's angry; where it's hopping while happy
		local want = facing
		local root = myRoot()
		if mood ~= "Happy" or action.name == "Wiggle" or action.name == "Bump" or action.name == "Turn" then
			if root then
				local to = flat(root.Position - at)
				if to.Magnitude > 0.5 then
					want = to.Unit
				end
			end
		elseif hop then
			local dir = flat(hop.to - hop.from)
			if dir.Magnitude > 0.3 then
				want = dir.Unit
			end
		end
		facing = facing:Lerp(want, math.min(1, dt * 10))
		if facing.Magnitude < 0.05 then
			facing = want
		end
		facing = facing.Unit
		if popped then
			if not burstDone then
				if t - action.at >= 0.5 then
					burst(at)
				else
					place(at, P, now)
				end
			end
		else
			place(at, P, now)
		end
		if tele then
			tele.step(now, dt)
		end
		-- dizzy stars circling its head
		if stars and not popped then
			if now > stars.untilT then
				if stars.parts then
					for _, s in ipairs(stars.parts) do
						s:Destroy()
					end
				end
				stars = nil
			else
				if not stars.parts then
					stars.parts = {}
					for i = 1, 3 do
						local s = newPart("DizzyStar", C.yellow, Enum.Material.Neon, 0)
						s.Size = V3(0.5, 0.5, 0.5)
						stars.parts[i] = s
					end
				end
				local top = at + V3(0, SIZE * 1.05, 0)
				for i, s in ipairs(stars.parts) do
					local a = now * 5 + i * (math.pi * 2 / 3)
					s.CFrame = CFrame.new(top + V3(math.cos(a) * 1.8, 0.3 * math.sin(now * 8 + i), math.sin(a) * 1.8)) * CFrame.Angles(0, a, math.pi / 4)
				end
			end
		end
	end

	function Oz.mood()
		return mood
	end
	function Oz.health()
		return hp, maxHp
	end
	function Oz.isCracked()
		return cracked
	end
	function Oz.destroy()
		if tele then
			tele.remove()
		end
		if stars and stars.parts then
			for _, s in ipairs(stars.parts) do
				s:Destroy()
			end
		end
		stars = nil
		if body then
			for _, p in ipairs(body) do
				p:Destroy()
			end
			body.shadow:Destroy()
		end
		body = nil
		model = nil
	end
end

----------------------------------------------------------------------
-- The chest Oozlet drops: out of the sky, bounce, bounce... and it bursts open
-- (your first Arcade Token is in it)
----------------------------------------------------------------------
local function dropChest(at)
	local parts = {}
	local function add(name, color, material, transparency)
		local p = newPart(name, color, material, transparency)
		table.insert(parts, p)
		return p
	end
	local base = add("ChestBase", C.wood)
	local foot = add("ChestFoot", C.woodDark)
	local lid = add("ChestLid", C.woodDark)
	local lidTop = add("ChestLidTop", C.wood)
	local bandL = add("ChestBand", C.gold)
	local bandR = add("ChestBand", C.gold)
	local lidBandL = add("ChestBand", C.gold)
	local lidBandR = add("ChestBand", C.gold)
	local lock = add("ChestLock", C.yellow, Enum.Material.Neon)
	local glow = add("ChestGlow", C.yellow, Enum.Material.Neon, 1)
	-- it faces you
	local root = myRoot()
	local face = V3(0, 0, 1)
	if root then
		local to = flat(root.Position - at)
		if to.Magnitude > 0.5 then
			face = to.Unit
		end
	end
	local ground = at.Y
	local W, Hb, Dp = 3.2, 1.7, 2.2
	local t0 = os.clock()
	local fall = 0.6
	local openAt = t0 + fall + 0.9
	local opened = false
	local label = nil
	local function placeAll(y, open)
		local cf = CFrame.lookAt(V3(at.X, y, at.Z), V3(at.X, y, at.Z) + face)
		local cfs, list = {}, {}
		local function put(p, size, c)
			p.Size = size
			table.insert(list, p)
			table.insert(cfs, c)
		end
		put(foot, V3(W + 0.1, 0.3, Dp + 0.1), cf * CFrame.new(0, 0.15, 0))
		put(base, V3(W, Hb, Dp), cf * CFrame.new(0, Hb / 2, 0))
		put(bandL, V3(0.35, Hb + 0.05, Dp + 0.06), cf * CFrame.new(-W * 0.3, Hb / 2, 0))
		put(bandR, V3(0.35, Hb + 0.05, Dp + 0.06), cf * CFrame.new(W * 0.3, Hb / 2, 0))
		-- the lid swings open on its back edge
		local hinge = cf * CFrame.new(0, Hb, Dp / 2) * CFrame.Angles(open * 1.9, 0, 0)
		put(lid, V3(W + 0.1, 0.5, Dp + 0.1), hinge * CFrame.new(0, 0.25, -Dp / 2))
		put(lidTop, V3(W - 0.2, 0.4, Dp - 0.2), hinge * CFrame.new(0, 0.65, -Dp / 2))
		put(lidBandL, V3(0.35, 0.95, Dp + 0.14), hinge * CFrame.new(-W * 0.3, 0.45, -Dp / 2))
		put(lidBandR, V3(0.35, 0.95, Dp + 0.14), hinge * CFrame.new(W * 0.3, 0.45, -Dp / 2))
		put(lock, V3(0.6, 0.7, 0.2), cf * CFrame.new(0, Hb - 0.1, -Dp / 2 - 0.1))
		put(glow, V3(W * 0.8, 40, Dp * 0.6), cf * CFrame.new(0, Hb + 20, 0))
		Workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	placeAll(ground + 30, 0)
	local bounced = 0
	addFx(function()
		local now = os.clock()
		local t = now - t0
		local y
		if t < fall then
			local k = t / fall
			y = ground + 30 * (1 - k * k)
		else
			local tb = t - fall
			if bounced == 0 then
				bounced = 1
				spawnBits(at + V3(0, 0.3, 0), 10, { C.mist1, C.wood, C.white }, 20, 0.45, 0.2, 0.8, ground)
				play("Chest", 0.9, 0.7)
				kick(0.5, 2)
			end
			-- two little bounces, then it sits
			y = ground + math.max(0, 1.6 * math.abs(math.sin(tb * 9)) * math.exp(-tb * 5))
		end
		local open = 0
		if now >= openAt then
			if not opened then
				opened = true
				play("Chest", 1, 1.25)
				spawnBits(at + V3(0, Hb + 0.4, 0), 22, { C.yellow, C.gold, C.white }, 30, 0.4, 1.4, 1.4, ground)
				glow.Transparency = 0.45
				tween(glow, 1.4, { Transparency = 1 })
				-- its name rises out of it
				local anchor = add("ChestLabelAnchor", C.white, nil, 1)
				anchor.Size = V3(0.2, 0.2, 0.2)
				anchor.CFrame = CFrame.new(at + V3(0, Hb + 1.5, 0))
				label = Instance.new("BillboardGui")
				label.Name = "IntroChestLabel"
				label.Size = UDim2.fromOffset(420, 44)
				label.AlwaysOnTop = true
				label.LightInfluence = 0
				label:SetAttribute("RetroSkip", true)
				label.Adornee = anchor
				label.Parent = anchor
				local text = Instance.new("TextLabel")
				text.BackgroundTransparency = 1
				text.Size = UDim2.fromScale(1, 1)
				text.TextScaled = true
				local tokens = (I.Reward and I.Reward.Tokens) or 1
				text.Text = "+" .. tokens .. (tokens == 1 and " ARCADE TOKEN" or " ARCADE TOKENS")
				text.TextColor3 = C.yellow
				text.TextStrokeColor3 = C.ink
				text.TextStrokeTransparency = 0
				pixelText(text)
				text.Parent = label
			end
			open = easeOut((now - openAt) / 0.3)
			if label then
				label.StudsOffset = V3(0, 3 * easeOut((now - openAt) / 1.2), 0)
			end
		end
		placeAll(y, open)
		-- it goes when the lobby is back
		return world ~= nil and world.Parent ~= nil and stage() ~= nil
	end, function()
		for _, p in ipairs(parts) do
			p:Destroy()
		end
	end)
end

----------------------------------------------------------------------
-- The phone's ROLL button throbs while you need it
----------------------------------------------------------------------
local RollPulse = {}
do
	local on = false
	local scale = nil
	local function button()
		local hud = playerGui:FindFirstChild("CombatHud")
		local rootF = hud and hud:FindFirstChild("Root")
		local ui = rootF and rootF:FindFirstChild("CombatUI")
		return ui and ui:FindFirstChild("RollButton")
	end
	function RollPulse.set(want)
		on = want
		if not want and scale then
			scale.Scale = 1
		end
	end
	function RollPulse.step(now)
		if not on then
			return
		end
		local b = button()
		if not b then
			return
		end
		if not scale or scale.Parent ~= b then
			scale = b:FindFirstChild("IntroPulse") or Instance.new("UIScale")
			scale.Name = "IntroPulse"
			scale.Parent = b
		end
		scale.Scale = 1 + 0.18 * math.abs(math.sin(now * 6))
	end
end

----------------------------------------------------------------------
-- The black cover (while the server decides whether you get the intro)
----------------------------------------------------------------------
local cover = nil
local function showCover()
	if cover then
		return
	end
	cover = Instance.new("ScreenGui")
	cover.Name = "IntroCover"
	cover.IgnoreGuiInset = true
	cover.DisplayOrder = 999 -- (just under the title screen)
	cover.ResetOnSpawn = false
	cover:SetAttribute("RetroSkip", true)
	local black = Instance.new("Frame")
	black.Name = "Black"
	black.BackgroundColor3 = C.black
	black.BorderSizePixel = 0
	black.Size = UDim2.fromScale(1, 1)
	black.Parent = cover
	cover.Parent = playerGui
end
local function dropCover(seconds)
	if not cover then
		return
	end
	local c = cover
	cover = nil
	local black = c:FindFirstChild("Black")
	if black and seconds > 0 then
		tween(black, seconds, { BackgroundTransparency = 1 })
		task.delay(seconds + 0.05, function()
			c:Destroy()
		end)
	else
		c:Destroy()
	end
end

----------------------------------------------------------------------
-- THE INTRO
----------------------------------------------------------------------
local running = false
local finished = false
local frameConn = nil
local eventConn = nil

-- when each letter of the first words appears: slowly at first... then the "!"
local function buildUpTimes(text)
	local times = {}
	local t, word = 0, 1
	local n = utf8.len(text) or #text
	local i = 0
	for _, code in utf8.codes(text) do
		i = i + 1
		local ch = utf8.char(code)
		if ch == " " then
			word = word + 1
			t = t + 0.28
			times[i] = t
		elseif ch == "!" and i == n then
			t = t + 0.75 -- (the long pause before the BOOM)
			times[i] = t
		else
			times[i] = t
			t = t + ((word == 1 and 0.42) or (word == 2 and 0.14) or 0.1)
		end
	end
	return times
end

-- words typed out quickly (the dots slowly, for the suspense)
local function typedTimes(text)
	local times = {}
	local t = 0
	local i = 0
	for _, code in utf8.codes(text) do
		i = i + 1
		local ch = utf8.char(code)
		times[i] = t
		t = t + ((ch == ".") and 0.35 or (ch == " ") and 0.15 or 0.08)
	end
	return times
end

local function howTo(kind)
	local list = TXT[kind] or {}
	return list[controls()] or list.Mouse
end

-- a note to the server ("IntroLook", "IntroDone", "IntroFailed")
local function tellServer(name)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local action = remotes and remotes:FindFirstChild("Action")
	if action then
		task.spawn(function()
			pcall(function()
				action:InvokeServer(name)
			end)
		end)
	end
end

-- Everything back to normal (at the very end - or right away, if the intro
-- was cut short)
local startIntroLater -- (below)
local function restoreAll()
	if finished then
		return
	end
	finished = true
	RollPulse.set(false)
	Music.stop()
	Hide.undo()
	Dark.undoAll()
	clearFx()
	for _, b in ipairs(bits) do
		b.part:Destroy()
	end
	bits = {}
	Oz.destroy()
	Arrow.hide()
	if eventConn then
		eventConn:Disconnect()
		eventConn = nil
	end
	local cam = camera()
	if cam and cam.CameraType == Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Custom
	end
	task.delay(2, function()
		if frameConn then
			frameConn:Disconnect()
			frameConn = nil
		end
		Music.kill()
		if gui then
			gui:Destroy()
			gui = nil
		end
		if world then
			world:Destroy()
			world = nil
		end
		-- ready to play again (Studio's DEV: Replay Intro) - straight away if asked already
		running, finished = false, false
		if stage() == "Void" then
			task.spawn(startIntroLater)
		end
	end)
	dropCover(0.3)
end

-- THE REVEAL: the mist rolls back, the lobby builds itself, the Spire rises
local function reveal()
	local runTime = REV.Time or 8
	local reach = REV.Reach or 600
	local r0 = RADIUS + 1
	Arrow.hide()
	Words.clear()
	Dark.startReveal()
	play("Win", 0.8)
	-- the mist takes a breath in... and rolls away
	local t0 = os.clock() + 0.4
	local last = os.clock()
	while running and not finished do
		local now = os.clock()
		local k = clamp01((now - t0) / runTime)
		local r = r0 + (reach - r0) * easeInOut(k)
		if now < t0 then
			r = r0 - 1.5 * smooth((now - (t0 - 0.4)) / 0.4)
		end
		Dark.reveal(r, now)
		Dark.stepMist(now - last, r - 1, clamp01((r - 150) / 250))
		last = now
		if k >= 1 then
			break
		end
		task.wait()
	end
	if finished then
		return
	end
	Dark.finishRing()
	-- last of all: THE SPIRE. The screen blinks to black and we're out past the
	-- castle walls, looking up at the Spire as it builds itself out of nothing,
	-- bottom to top... BOOM: OOZARK AWAITS. Then a blink back to you.
	local spot, _, low, high = Dark.spireSpot()
	local cam = camera()
	local root, hum = myRoot()
	if spot and cam and root then
		local walkWas = hum.WalkSpeed
		hum.WalkSpeed = 0 -- (stand still for the look)
		local bottom = math.max(low or spot.Y, CENTER.Y)
		local top = high or spot.Y
		local target = V3(spot.X, bottom + 0.48 * (top - bottom), spot.Z)
		local dir = flat(spot - root.Position)
		dir = dir.Magnitude > 0.1 and dir.Unit or V3(0, 0, -1)
		-- where to look from: out past the walls, if nothing's in the way; if
		-- something is, rising up behind you until the view is clear
		local sight = RaycastParams.new()
		sight.FilterType = Enum.RaycastFilterType.Exclude
		local skip = { world }
		if Dark.spireModel() then
			table.insert(skip, Dark.spireModel())
		end
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl.Character then
				table.insert(skip, pl.Character)
			end
		end
		sight.FilterDescendantsInstances = skip
		local reachOut = math.max(120, (top - bottom) * 0.8)
		local eye = V3(spot.X, 0, spot.Z) - dir * reachOut + V3(0, bottom + 0.2 * (top - bottom) + 10, 0)
		if Workspace:Raycast(eye, target - eye, sight) then
			eye = nil
			for rise = 20, 200, 10 do
				local at = root.Position + V3(0, rise, 0) - dir * (24 + rise * 0.15)
				if not Workspace:Raycast(at, target - at, sight) then
					eye = at
					break
				end
			end
			eye = eye or (root.Position + V3(0, 150, 0) - dir * 40)
		end
		local from = cam.CFrame
		local fade = gui and gui:FindFirstChild("Fade")
		local function blink(on, seconds)
			if fade then
				tween(fade, seconds, { BackgroundTransparency = on and 0 or 1 })
			end
			task.wait(seconds)
		end
		blink(true, 0.25)
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = CFrame.lookAt(eye, target)
		-- (a slow push in towards it, the whole time)
		local push = (target - eye).Unit * math.min(24, (target - eye).Magnitude * 0.12)
		tween(cam, 4.2, { CFrame = CFrame.lookAt(eye + push, target) }, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		blink(false, 0.3)
		Dark.raiseSpire(1.4)
		play("Awaits", 1, 0.8)
		kick(0.7, 5)
		if gui and gui:FindFirstChild("Flash") then
			gui.Flash.BackgroundTransparency = 0.5
			tween(gui.Flash, 0.6, { BackgroundTransparency = 1 })
		end
		local awaits = TXT.Awaits or "OOZARK AWAITS..."
		Words.set(awaits, "ominous", typedTimes(awaits))
		-- (held until the words are all there, and a moment more)
		local shownAt = os.clock()
		while not Words.done() and os.clock() - shownAt < 5 do
			task.wait(0.1)
		end
		task.wait(math.max(1.4, (REV.Spire or 3.4) - (os.clock() - shownAt)))
		blink(true, 0.25)
		Words.clear()
		cam.CFrame = from
		cam.CameraType = Enum.CameraType.Custom
		if hum.Parent then
			hum.WalkSpeed = walkWas
		end
		blink(false, 0.35)
	else
		Dark.raiseSpire(0.6)
	end
	restoreAll()
	-- tell the server the lobby is showing (it ends the intro and pays the levels)
	tellServer("IntroDone")
end

local function runIntro()
	if running then
		return
	end
	running = true
	showCover()
	task.spawn(warmSounds)
	world = Instance.new("Folder")
	world.Name = "IntroWorld"
	world.Parent = Workspace
	gui = Instance.new("ScreenGui")
	gui.Name = "IntroGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30
	gui:SetAttribute("RetroSkip", true)
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.BackgroundColor3 = C.white
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = 10
	flash.Parent = gui
	local fade = Instance.new("Frame")
	fade.Name = "Fade"
	fade.BackgroundColor3 = C.black
	fade.BackgroundTransparency = 1
	fade.BorderSizePixel = 0
	fade.Size = UDim2.fromScale(1, 1)
	fade.ZIndex = 20
	fade.Parent = gui
	gui.Parent = playerGui
	Words.init()
	Bar.init()

	-- the dark
	Dark.hideWorld()
	Dark.buildBox()
	Dark.buildMist()
	Hide.all()
	Dark.stepMist(1, RADIUS - 0.5, 0)

	-- Oozlet (the server's invisible one: it carries our UserId)
	local folder = Workspace:WaitForChild("IntroOozlets", 10)
	local model = folder and folder:WaitForChild("Oozlet_" .. player.UserId, 10)
	if not model then
		error("Oozlet never arrived") -- (then everything is put back: see safely below)
	end
	Oz.start(model)

	-- the words react to the fight
	local hitLines = TXT.Hits or { "AGAIN!" }
	local hitIndex = 0
	local punchHints = 0
	local finishSaid = false
	local holding = false
	local afterDodge = 0
	local wordsHeldUntil = 0
	local lastHitAt = -math.huge
	Oz.on("Hit", function(h)
		lastHitAt = os.clock()
		Arrow.hide()
		Bar.set(h, select(2, Oz.health()))
		Words.jolt(1)
		if not Words.done() then
			-- punched before the words were all up: they snap in, BOOM and all,
			-- and stay a moment before the next words
			Words.finish()
			wordsHeldUntil = os.clock() + 0.7
			return
		end
		if holding or os.clock() < wordsHeldUntil then
			return
		end
		punchHints = punchHints + 1
		if punchHints >= 3 then
			Words.hint(nil)
		end
		if Oz.isCracked() and h <= 2 and h > 0 then
			if not finishSaid then
				finishSaid = true
				Words.set(TXT.Finish or "FINISH IT!!!", "danger")
			end
		elseif not finishSaid and h > 0 then
			hitIndex = hitIndex % #hitLines + 1
			Words.set(hitLines[hitIndex], "normal")
		end
	end)
	Oz.on("Mood", function(newMood)
		if newMood == "Angry" then
			Bar.show()
			Music.play()
		end
	end)
	Oz.on("Burst", function(at)
		Words.burst()
		Bar.hide()
		Music.stop()
		local ground = at
		task.delay(0.5, function()
			if running and not finished then
				dropChest(V3(ground.X, ground.Y, ground.Z))
			end
		end)
	end)
	local introEvent = ReplicatedStorage:FindFirstChild("IntroEvent")
	if introEvent then
		eventConn = introEvent.OnClientEvent:Connect(function(kind, arg)
			if kind == "Hold" then
				holding = true
				if not Words.done() then
					Words.finish()
				end
				Words.set(TXT.Roll or "ROLL!!", "danger")
				Words.hint(howTo("RollHow"))
				Words.shake(1)
				RollPulse.set(true)
			elseif kind == "Dodge" then
				holding = false
				RollPulse.set(false)
				Words.hint(nil)
				local mine = os.clock()
				afterDodge = mine
				if arg == "roll" then
					Words.set(TXT.Rolled or "NICE ROLL!", "good")
				else
					Words.set(TXT.Ouch or "OUCH! ROLL!!", "danger")
				end
				wordsHeldUntil = mine + 0.8 -- (the praise stays up a moment, even if you punch straight away)
				task.delay(0.9, function()
					-- (only if you haven't started hitting it already)
					if afterDodge == mine and lastHitAt < mine and running and not finished and not holding then
						Words.set(TXT.Dizzy or "NOW HIT IT!", "normal")
					end
				end)
			elseif kind == "Crack" then
				Words.set(TXT.Crack or "IT'S CRACKING!", "danger")
				Words.shake(1.5)
			elseif kind == "Bump" then
				Words.jolt(0.6)
			end
		end)
	end

	-- every frame (a mistake in the drawing is reported once, and the fight goes on)
	local last = os.clock()
	local complained = false
	frameConn = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local dt = math.min(now - last, 0.1)
		last = now
		local ok, err = pcall(function()
			if stage() ~= "Reveal" and not finished then
				Dark.stepMist(dt, RADIUS - 0.5, 0)
			end
			Oz.step(dt, now)
			Arrow.step(Oz.top(), now)
			Words.step(dt)
			Bar.step(dt)
			Music.step(dt)
			RollPulse.step(now)
			stepBits(dt)
			stepFx(now)
		end)
		if not ok and not complained then
			complained = true
			warn("[IntroClient] drawing the intro went wrong: " .. tostring(err))
		end
	end)

	-- wait for the server to put us by the fountain, then lift the cover
	local spawnAt = I.SpawnAt or CENTER
	local waited = 0
	while waited < 4 do
		local root = myRoot()
		if root and flat(root.Position - spawnAt).Magnitude < 12 then
			break
		end
		task.wait(0.1)
		waited = waited + 0.1
	end
	dropCover(0.6)

	-- wait for the title screen to go (it may not be up yet)
	local R = Config.Retro or {}
	local t0 = os.clock()
	if R.On ~= false and R.StartScreen ~= false then
		while not playerGui:FindFirstChild("RetroTitle") and os.clock() - t0 < 2 do
			task.wait(0.1)
		end
	end
	while playerGui:FindFirstChild("RetroTitle") and os.clock() - t0 < 25 do
		task.wait(0.1)
	end
	if finished then
		return
	end
	-- "I can see now" (the bump waits for this)
	tellServer("IntroLook")
	task.wait(1.2)
	-- HIT THE SLIME!
	if running and not finished and Oz.mood() == "Happy" then
		local text = TXT.Hit or "HIT THE SLIME!"
		Words.set(text, "normal", buildUpTimes(text), true)
		Arrow.show()
		task.delay(3.6, function()
			if running and not finished and Oz.mood() == "Happy" then
				Words.hint(howTo("PunchHow"))
			end
		end)
	end
end

-- If anything goes wrong on this screen, put everything back and play on
-- normally (the server gives up on the intro too) - never stuck in the dark
local function safely(fn, failNote)
	return function()
		local ok, err = pcall(fn)
		if not ok then
			warn("[IntroClient] the intro went wrong: " .. tostring(err))
			restoreAll()
			tellServer(failNote)
		end
	end
end
local startIntro = safely(runIntro, "IntroFailed")
startIntroLater = function()
	startIntro()
end
local startReveal = safely(reveal, "IntroDone")

-- the server moves us on: the reveal, or it's over
player:GetAttributeChangedSignal("Intro"):Connect(function()
	local s = stage()
	if s == "Void" and not running and not finished then
		task.spawn(startIntro)
	elseif s == "Reveal" and running and not finished then
		task.spawn(startReveal)
	elseif s == nil and running and not finished then
		-- (it ended without the reveal: put everything back straight away)
		restoreAll()
	end
end)

-- Start: black until the server says whether we get the intro
if not player:GetAttribute("IntroChecked") or stage() then
	showCover()
end
local waitedFor = 0
while not player:GetAttribute("IntroChecked") and waitedFor < 12 do
	task.wait(0.1)
	waitedFor = waitedFor + 0.1
end
if stage() == "Void" then
	startIntro()
elseif not running then
	dropCover(0.5)
end
