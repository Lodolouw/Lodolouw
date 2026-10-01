--[[
	MoveFX  (ModuleScript, parent: ReplicatedStorage, name: "MoveFX")

	How weapon abilities LOOK, on every screen: each move's effects (the list of
	what a move does is ReplicatedStorage/Moves - its steps' Fx names are the
	recipes here), the moments a building block has (a stack bursting, a next
	hit landing, a crit, a lifesteal) and the look of each ability's aura
	(STYLES). Everything is made of the game's own stuff - chunky voxel bits,
	neon, flat colours - and cleans itself up.

	Who calls it:
	  * CombatClient, the moment YOU press your ability: MoveFX.begin(you, weapon, 0, true)
	  * AbilityFX (every screen) when the server says (CombatRemotes.AbilityFx):
	    MoveFX.told(player, weapon, count, step, point, extra) - step 0 is
	    someone else's move starting, a number is a step that picked a spot,
	    a name is a building block's moment.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Moves = require(ReplicatedStorage:WaitForChild("Moves"))

local MoveFX = {}
local RGB = Color3.fromRGB
local V3 = Vector3.new
local rad = math.rad
local rnd = Random.new()

local WHITE, INK = RGB(255, 255, 255), RGB(24, 20, 37)

-- the looks: each style's colours (Main, Light, Dark, Glow) - also the aura's
MoveFX.STYLES = {
	Slime = { Main = RGB(105, 210, 70), Light = RGB(170, 255, 120), Dark = RGB(46, 120, 40), Glow = RGB(214, 255, 120), Jelly = true },
	Acid = { Main = RGB(120, 255, 60), Light = RGB(214, 255, 120), Dark = RGB(25, 60, 62), Glow = RGB(120, 255, 60), Jelly = true },
	Dirt = { Main = RGB(140, 96, 60), Light = RGB(200, 150, 100), Dark = RGB(84, 56, 40), Glow = RGB(254, 174, 52) },
	Gold = { Main = RGB(254, 174, 52), Light = RGB(254, 231, 97), Dark = RGB(190, 120, 30), Glow = RGB(254, 231, 97) },
	Iron = { Main = RGB(90, 105, 136), Light = RGB(192, 203, 220), Dark = RGB(38, 43, 68), Glow = RGB(0, 153, 219) },
	Smoke = { Main = RGB(110, 110, 120), Light = RGB(210, 210, 220), Dark = RGB(40, 40, 50), Glow = RGB(247, 118, 34) },
	Nitro = { Main = RGB(0, 153, 219), Light = RGB(44, 232, 245), Dark = RGB(18, 78, 137), Glow = RGB(44, 232, 245) },
	Flame = { Main = RGB(247, 118, 34), Light = RGB(254, 231, 97), Dark = RGB(190, 74, 47), Glow = RGB(254, 174, 52) },
	Checker = { Main = WHITE, Light = RGB(254, 231, 97), Dark = INK, Glow = RGB(247, 118, 34) },
	Rage = { Main = RGB(255, 0, 68), Light = RGB(246, 117, 122), Dark = RGB(162, 38, 51), Glow = RGB(255, 0, 68) },
	Blood = { Main = RGB(228, 59, 68), Light = RGB(246, 117, 122), Dark = RGB(162, 38, 51), Glow = RGB(255, 0, 68) },
	Leaf = { Main = RGB(99, 199, 77), Light = RGB(170, 230, 120), Dark = RGB(38, 92, 66), Glow = RGB(254, 231, 97) },
	Wood = { Main = RGB(184, 111, 80), Light = RGB(228, 166, 114), Dark = RGB(115, 62, 57), Glow = RGB(254, 174, 52) },
	Eraser = { Main = RGB(246, 117, 122), Light = RGB(255, 205, 210), Dark = RGB(181, 80, 136), Glow = WHITE },
	Ink = { Main = INK, Light = RGB(0, 153, 219), Dark = RGB(18, 78, 137), Glow = RGB(0, 153, 219) },
	Doodle = { Main = WHITE, Light = RGB(0, 153, 219), Dark = INK, Glow = RGB(0, 153, 219) },
	Glitch = { Main = RGB(255, 0, 68), Light = WHITE, Dark = INK, Glow = RGB(255, 0, 68) },
}
local function styleOf(name)
	return MoveFX.STYLES[name or ""] or MoveFX.STYLES.Gold
end
MoveFX.styleOf = styleOf

----------------------------------------------------------------------
-- The bits everything is made of
----------------------------------------------------------------------
local folder = nil
local function fxFolder()
	if folder and folder.Parent then
		return folder
	end
	folder = Workspace:FindFirstChild("MoveFX")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "MoveFX"
		folder.Parent = Workspace
	end
	return folder
end

local function newPart(size, cf, color, material, transparency, shape)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color or WHITE
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	if shape then
		p.Shape = shape
	end
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = fxFolder()
	return p
end
MoveFX.newPart = newPart

local function gone(inst, after)
	task.delay(after, function()
		if inst then
			inst:Destroy()
		end
	end)
end

local function tween(inst, time, goal, style, dir)
	local t = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

-- the floor under a spot (the arenas have steps and platforms)
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function floorAt(pos)
	local skip = { fxFolder() }
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then
			skip[#skip + 1] = plr.Character
		end
	end
	rayParams.FilterDescendantsInstances = skip
	local hit = Workspace:Raycast(pos + V3(0, 3, 0), V3(0, -24, 0), rayParams)
	if hit then
		return hit.Position.Y
	end
	return pos.Y - 3
end
MoveFX.floorAt = floorAt

local function onFloor(pos, lift)
	return V3(pos.X, floorAt(pos) + (lift or 0), pos.Z)
end

-- flying bits: voxel cubes thrown out with gravity, spinning, fading
local bitsLive = {}
local function bits(o)
	local at = o.at
	local n = o.count or 12
	local colors = o.colors or { o.color or WHITE }
	for i = 1, n do
		local size = (o.size or 0.5) * rnd:NextNumber(0.6, 1.3)
		local c = colors[(i - 1) % #colors + 1]
		local p = newPart(V3(size, size, size), CFrame.new(at) * CFrame.Angles(rnd:NextNumber(0, 6), rnd:NextNumber(0, 6), 0),
			c, o.material or Enum.Material.SmoothPlastic, o.transparency or 0, o.shape)
		local a = (o.angle or 0) + (o.spread and rnd:NextNumber(-o.spread, o.spread) or rnd:NextNumber(0, math.pi * 2))
		local dir = o.dir and (CFrame.lookAt(V3(), V3(o.dir.X, 0, o.dir.Z).Magnitude > 0.01 and V3(o.dir.X, 0, o.dir.Z) or V3(0, 0, -1)) * CFrame.Angles(0, a - (o.angle or 0), 0)).LookVector
			or V3(math.cos(a), 0, math.sin(a))
		local speed = rnd:NextNumber(o.speed and o.speed[1] or 8, o.speed and o.speed[2] or 18)
		local up = rnd:NextNumber(o.up and o.up[1] or 6, o.up and o.up[2] or 16)
		table.insert(bitsLive, {
			p = p, v = dir * speed + V3(0, up, 0), g = o.gravity or 60,
			spin = V3(rnd:NextNumber(-8, 8), rnd:NextNumber(-8, 8), rnd:NextNumber(-8, 8)),
			age = 0, life = (o.life or 0.8) * rnd:NextNumber(0.75, 1.2), size = size, shrink = o.shrink ~= false,
			fade = o.transparency or 0, floor = o.floor, bounce = o.bounce,
		})
	end
end
MoveFX.bits = bits

RunService.Heartbeat:Connect(function(dt)
	for i = #bitsLive, 1, -1 do
		local b = bitsLive[i]
		b.age = b.age + dt
		if b.age >= b.life or not b.p.Parent then
			b.p:Destroy()
			table.remove(bitsLive, i)
		else
			b.v = b.v - V3(0, b.g * dt, 0)
			local pos = b.p.Position + b.v * dt
			if b.floor and pos.Y < b.floor + b.size / 2 then
				pos = V3(pos.X, b.floor + b.size / 2, pos.Z)
				b.v = b.bounce and V3(b.v.X * 0.5, -b.v.Y * 0.35, b.v.Z * 0.5) or V3(b.v.X * 0.3, 0, b.v.Z * 0.3)
				b.spin = b.spin * 0.5
			end
			local k = b.age / b.life
			b.p.CFrame = CFrame.new(pos) * (b.p.CFrame - b.p.Position) * CFrame.Angles(b.spin.X * dt, b.spin.Y * dt, b.spin.Z * dt)
			if b.shrink and k > 0.55 then
				local s = b.size * (1 - (k - 0.55) / 0.45)
				b.p.Size = V3(s, s, s)
			end
		end
	end
end)

-- a ring of cubes racing out along the floor
local function ring(at, color, r1, time, o)
	o = o or {}
	local n = o.count or 26
	local y = o.y or floorAt(at) + 0.4
	local size = o.size or 0.8
	for i = 1, n do
		local a = i / n * math.pi * 2
		local d = V3(math.cos(a), 0, math.sin(a))
		local p = newPart(V3(size, size * (o.tall or 1), size), CFrame.new(V3(at.X, y, at.Z) + d * (o.r0 or 1)) * CFrame.Angles(0, -a, 0),
			color, o.material or Enum.Material.Neon, 0)
		tween(p, time, { CFrame = CFrame.new(V3(at.X, y + (o.rise or 0.4), at.Z) + d * r1) * CFrame.Angles(0, -a, 0), Size = V3(size * 0.2, size * 0.2, size * 0.2), Transparency = 1 })
		gone(p, time + 0.05)
	end
end
MoveFX.ring = ring

-- a flat disc on the floor that grows and fades (a flash, a splat)
local function disc(at, color, r1, time, o)
	o = o or {}
	local y = o.y or floorAt(at) + 0.08
	local p = newPart(V3(0.12, (o.r0 or 1) * 2, (o.r0 or 1) * 2), CFrame.new(at.X, y, at.Z) * CFrame.Angles(0, 0, rad(90)),
		color, o.material or Enum.Material.Neon, o.transparency or 0.15, Enum.PartType.Cylinder)
	tween(p, time, { Size = V3(0.12, r1 * 2, r1 * 2), Transparency = 1 }, o.easing)
	gone(p, time + 0.05)
	return p
end
MoveFX.disc = disc

-- soft puffs (dust, smoke, steam) that swell, rise and fade
local function puffs(at, color, count, size, rise, time, spread)
	for _ = 1, count do
		local off = V3(rnd:NextNumber(-1, 1), 0, rnd:NextNumber(-1, 1)) * (spread or 2)
		local s = size * rnd:NextNumber(0.7, 1.2)
		local p = newPart(V3(s, s, s), CFrame.new(at + off), color, Enum.Material.SmoothPlastic, 0.25, Enum.PartType.Ball)
		tween(p, time * rnd:NextNumber(0.8, 1.2), { Size = V3(s, s, s) * 2.2, Transparency = 1, CFrame = CFrame.new(at + off * 1.6 + V3(0, rise, 0)) })
		gone(p, time * 1.25)
	end
end
MoveFX.puffs = puffs

-- a flat glowing bar from a to b (a dash's streak, a slash across the floor)
local function streak(a, b, color, width, time, o)
	o = o or {}
	local d = b - a
	if d.Magnitude < 0.05 then
		return
	end
	local p = newPart(V3(width, o.thick or 0.25, d.Magnitude), CFrame.lookAt(a:Lerp(b, 0.5), b), color, o.material or Enum.Material.Neon, o.transparency or 0.1)
	tween(p, time, { Size = V3(width * 0.1, o.thick or 0.25, d.Magnitude), Transparency = 1 })
	gone(p, time + 0.05)
	return p
end
MoveFX.streak = streak

-- a crescent sweep round a spot (a spin, a sweep): a band of light drawn round
-- from angle a0 to a1 (degrees, 0 = straight ahead, + = to the left), fattest
-- in the middle, a bright edge along its outside, fading as it goes
local function sweep(cf, radius, a0, a1, color, time, o)
	o = o or {}
	local span = math.abs(a1 - a0)
	local n = o.count or math.max(8, math.floor(span / 9))
	local rMid = radius * (o.at or 0.72)
	local band = o.width or radius * 0.3
	local stepLen = rad(span / n) * rMid * 1.25
	for i = 0, n do
		local u = i / n
		local a = rad(a0 + (a1 - a0) * u)
		local dirv = (cf * CFrame.Angles(0, a, 0)).LookVector
		local fat = 0.3 + 0.7 * math.sin(math.pi * math.clamp(u, 0.04, 0.96))
		local w = band * fat
		local pos = cf.Position + dirv * rMid + V3(0, o.height or 0, 0)
		local out = CFrame.lookAt(pos, pos + dirv) * CFrame.Angles(0, 0, rad(o.tilt or 0))
		local seg = newPart(V3(stepLen, 0.22, w), out, i % 2 == 0 and color or (o.color2 or color), Enum.Material.Neon, 1)
		local rim = newPart(V3(stepLen, 0.26, math.max(0.2, w * 0.2)), out * CFrame.new(0, 0.03, -w * 0.42), WHITE, Enum.Material.Neon, 1)
		task.delay(u * (o.draw or 0.12), function()
			seg.Transparency, rim.Transparency = 0.1, 0
			tween(seg, time, { Transparency = 1, Size = V3(stepLen, 0.22, w * 0.3) })
			tween(rim, time * 0.8, { Transparency = 1 })
		end)
		gone(seg, time + (o.draw or 0.12) + 0.05)
		gone(rim, time + (o.draw or 0.12) + 0.05)
	end
end
MoveFX.sweep = sweep

-- a beam of light up from the floor
local function column(at, color, height, width, time)
	local base = onFloor(at)
	local p = newPart(V3(width, height, width), CFrame.new(base + V3(0, height / 2, 0)), color, Enum.Material.Neon, 0.1)
	tween(p, time, { Size = V3(width * 0.1, height * 1.3, width * 0.1), Transparency = 1 })
	gone(p, time + 0.05)
end
MoveFX.column = column

-- a flash of light
local function light(at, color, range, time, brightness)
	local p = newPart(V3(0.2, 0.2, 0.2), CFrame.new(at), color, Enum.Material.SmoothPlastic, 1)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 4
	l.Shadows = false
	l.Parent = p
	tween(l, time, { Brightness = 0 })
	gone(p, time + 0.05)
end
MoveFX.light = light

-- big words popping up over a spot ("CHOMP!", "GUILTY!")
local function pop(at, text, color, size, time)
	local p = newPart(V3(0.2, 0.2, 0.2), CFrame.new(at), WHITE, Enum.Material.SmoothPlastic, 1)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(size or 8, (size or 8) * 0.35)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Parent = p
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Arcade
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color or WHITE
	label.TextStrokeColor3 = INK
	label.TextStrokeTransparency = 0
	label.Rotation = rnd:NextNumber(-8, 8)
	label.Parent = bb
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = label
	tween(scale, 0.18, { Scale = 1.15 }, Enum.EasingStyle.Back)
	task.delay(0.18, function()
		tween(scale, 0.12, { Scale = 1 })
	end)
	tween(p, time or 1, { CFrame = CFrame.new(at + V3(0, 2.5, 0)) }, Enum.EasingStyle.Sine)
	task.delay((time or 1) * 0.6, function()
		tween(label, (time or 1) * 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
	gone(p, (time or 1) + 0.05)
end
MoveFX.pop = pop

-- the camera shakes for anyone close enough to feel it
local shakeLeft, shakeAmount = 0, 0
local function shake(at, amount)
	local me = Players.LocalPlayer
	if me and me:GetAttribute("NoShake") then
		return -- (Settings: camera shake off)
	end
	local char = me and me.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local d = (root.Position - at).Magnitude
	local k = math.clamp(1 - d / 60, 0, 1)
	if k <= 0 then
		return
	end
	shakeAmount = math.max(shakeAmount * (shakeLeft > 0 and 1 or 0), amount * k)
	shakeLeft = 0.35
end
MoveFX.shake = shake
RunService:BindToRenderStep("MoveFXShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if shakeLeft <= 0 then
		return
	end
	shakeLeft = shakeLeft - dt
	local cam = Workspace.CurrentCamera
	if cam then
		local k = math.max(shakeLeft, 0) / 0.35 * shakeAmount * 0.35
		cam.CFrame = cam.CFrame * CFrame.Angles(rnd:NextNumber(-1, 1) * k * 0.03, rnd:NextNumber(-1, 1) * k * 0.03, 0)
			* CFrame.new(rnd:NextNumber(-1, 1) * k * 0.25, rnd:NextNumber(-1, 1) * k * 0.25, 0)
	end
end)

-- the whole screen washes over with a colour for a moment (yours only)
local function screenFlash(color, alpha, time)
	local me = Players.LocalPlayer
	local gui = me and me:FindFirstChildOfClass("PlayerGui")
	if not gui then
		return
	end
	local sg = Instance.new("ScreenGui")
	sg.Name = "MoveFXFlash"
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 50
	sg.ResetOnSpawn = false
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1 - (alpha or 0.4)
	f.Parent = sg
	sg.Parent = gui
	tween(f, time or 0.3, { BackgroundTransparency = 1 })
	gone(sg, (time or 0.3) + 0.05)
end
MoveFX.screenFlash = screenFlash

-- is this spot near enough to me to flash my screen?
local function nearMe(at, range)
	local me = Players.LocalPlayer
	local root = me and me.Character and me.Character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and (root.Position - at).Magnitude <= (range or 40)
end

-- a character's body frozen in glowing glass for a moment (afterimages)
local BODY = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
local function afterimage(char, color, time, alpha, material)
	if not char then
		return
	end
	for _, name in ipairs(BODY) do
		local part = char:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			local p = newPart(part.Size, part.CFrame, color, material or Enum.Material.Neon, alpha or 0.45)
			tween(p, time, { Transparency = 1 })
			gone(p, time + 0.05)
		end
	end
end
MoveFX.afterimage = afterimage

-- a rope, chain or vine between two moving attachments (a Beam)
local function beam(a0, a1, color, width, texture)
	local b = Instance.new("Beam")
	b.Attachment0, b.Attachment1 = a0, a1
	b.Width0, b.Width1 = width, width
	b.Color = ColorSequence.new(color)
	b.LightEmission = 0.3
	b.FaceCamera = true
	b.Segments = 12
	if texture then
		b.Texture = texture
		b.TextureMode = Enum.TextureMode.Static
		b.TextureLength = width * 2
	end
	b.Parent = a0.Parent
	return b
end
MoveFX.beam = beam

local function anchorAt(cf)
	local p = newPart(V3(0.2, 0.2, 0.2), cf, WHITE, Enum.Material.SmoothPlastic, 1)
	local a = Instance.new("Attachment")
	a.Parent = p
	return p, a
end

-- play a sound from SoundService by name (missing: silent)
local function squash(s)
	return string.lower((string.gsub(tostring(s), "[%s_%-]", "")))
end
local function sound(name, at, pitch, volume)
	if not name then
		return
	end
	local want = squash(name)
	for _, s in ipairs(SoundService:GetChildren()) do
		if s:IsA("Sound") and squash(s.Name) == want then
			local p = newPart(V3(0.2, 0.2, 0.2), CFrame.new(at), WHITE, Enum.Material.SmoothPlastic, 1)
			local c = s:Clone()
			c.PlaybackSpeed = s.PlaybackSpeed * (pitch or 1)
			c.Volume = s.Volume * (volume or 1)
			c.RollOffMaxDistance = 120
			local group = SoundService:FindFirstChild("Effects")
			if group and group:IsA("SoundGroup") then
				c.SoundGroup = group
			end
			c.Parent = p
			c:Play()
			gone(p, math.max(c.TimeLength, 1) + 0.5)
			return
		end
	end
end
MoveFX.sound = sound

-- the first of these sounds that's in SoundService
local function sfx(names, at, pitch, volume)
	for _, name in ipairs(names) do
		local want = squash(name)
		for _, s in ipairs(SoundService:GetChildren()) do
			if s:IsA("Sound") and squash(s.Name) == want then
				sound(name, at, pitch, volume)
				return
			end
		end
	end
end
MoveFX.sfx = sfx
local SLAM = { "Cube Slam", "Boss Slam", "Hammer Hit" }
local WHOOSH = { "Portal Whoosh", "Wave Zoom", "Whirlwind" }
local BOOM = { "Bomb Drop", "UFO Burst", "Boss Slam" }
local MAGIC = { "Orb Land", "Level Complete" }
local SHATTER = { "Gridlock Shatter", "Cube Slam" }

----------------------------------------------------------------------
-- Props: the bigger things some moves throw or summon, built from blocks
----------------------------------------------------------------------
local function weld(root, part)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = root, part
	w.Parent = part
	part.Anchored = false
end

-- a model of parts moved as one (anchored root, the rest welded to it), built
-- at `at` (where it first shows; default the world's origin)
local function prop(build, at)
	local model = Instance.new("Model")
	model.Name = "MoveProp"
	local base = at or CFrame.new()
	local root = newPart(V3(0.2, 0.2, 0.2), base, WHITE, Enum.Material.SmoothPlastic, 1)
	root.Parent = model
	model.PrimaryPart = root
	local function add(size, offset, color, material, transparency, shape)
		local p = newPart(size, base * offset, color, material, transparency, shape)
		p.Parent = model
		weld(root, p)
		return p
	end
	build(add)
	model.Parent = fxFolder()
	return model, root
end

-- a wooden barrel lying on its side (its axis along X, so it rolls forward along Z)
local function barrelProp(scale, golden, at)
	return prop(function(add)
		local wood, dark = golden and RGB(254, 174, 52) or RGB(184, 111, 80), golden and RGB(190, 120, 30) or RGB(115, 62, 57)
		local band = golden and RGB(254, 231, 97) or RGB(58, 68, 102)
		local s = scale or 1
		add(V3(2.4 * s, 2.2 * s, 2.2 * s), CFrame.Angles(0, 0, 0), wood, golden and Enum.Material.Neon or Enum.Material.WoodPlanks, 0, Enum.PartType.Cylinder)
		for _, x in ipairs({ -0.8, 0.8 }) do
			add(V3(0.25 * s, 2.35 * s, 2.35 * s), CFrame.new(x * s, 0, 0), band, Enum.Material.SmoothPlastic, 0, Enum.PartType.Cylinder)
		end
		for _, x in ipairs({ -1.2, 1.2 }) do
			add(V3(0.12 * s, 1.9 * s, 1.9 * s), CFrame.new(x * s, 0, 0), dark, Enum.Material.SmoothPlastic, 0, Enum.PartType.Cylinder)
		end
	end, at)
end

-- a slime glob (a ball of goo with a bright heart)
local function globProp(style)
	return prop(function(add)
		add(V3(1.6, 1.6, 1.6), CFrame.new(), style.Main, Enum.Material.SmoothPlastic, 0.25, Enum.PartType.Ball)
		add(V3(0.8, 0.8, 0.8), CFrame.new(), style.Glow, Enum.Material.Neon, 0, Enum.PartType.Ball)
	end)
end

-- a dirt clod
local function clodProp(style)
	return prop(function(add)
		add(V3(0.9, 0.8, 0.9), CFrame.Angles(0.3, 0.5, 0.2), style.Main, Enum.Material.Slate)
		add(V3(0.5, 0.5, 0.5), CFrame.new(0.3, 0.3, 0), style.Dark, Enum.Material.Slate)
	end)
end

-- an iron anchor (its shank along -Z, the flukes at the far end)
local function anchorProp()
	return prop(function(add)
		local iron, gold = RGB(58, 68, 102), RGB(254, 174, 52)
		add(V3(0.5, 0.5, 3.2), CFrame.new(0, 0, -1.6), iron)
		add(V3(1.8, 0.4, 0.4), CFrame.new(0, 0, -0.5), iron)
		add(V3(0.8, 0.8, 0.25), CFrame.new(0, 0, 0.1), gold, Enum.Material.Neon)
		add(V3(3.0, 0.5, 0.5), CFrame.new(0, 0, -3.1), iron)
		for _, s in ipairs({ -1, 1 }) do
			add(V3(0.5, 0.5, 1.2), CFrame.new(s * 1.35, 0, -2.6) * CFrame.Angles(0, s * rad(25), 0), iron)
			add(V3(0.6, 0.6, 0.6), CFrame.new(s * 1.55, 0, -2.0), gold, Enum.Material.Neon)
		end
	end)
end

-- a burning tyre (its axle along X: it rolls along Z)
local function wheelProp()
	return prop(function(add)
		local tyre, rim, flame = INK, RGB(192, 203, 220), RGB(247, 118, 34)
		local n = 14
		for i = 1, n do
			local a = i / n * math.pi * 2
			add(V3(1.1, 1.0, 1.35), CFrame.Angles(a, 0, 0) * CFrame.new(0, 2.1, 0), tyre)
			add(V3(1.16, 0.3, 0.6), CFrame.Angles(a, 0, 0) * CFrame.new(0, 2.6, 0), flame, Enum.Material.Neon)
		end
		add(V3(0.6, 3.0, 3.0), CFrame.new(), rim, Enum.Material.Foil, 0, Enum.PartType.Cylinder)
		add(V3(0.7, 1.0, 1.0), CFrame.new(), RGB(254, 174, 52), Enum.Material.Neon, 0, Enum.PartType.Cylinder)
	end)
end

-- a racing tyre, white lettering round it, a chrome rim and an orange hub
-- (its axle along X: it rolls along Z; about 1.2 studs round)
local function tyreProp()
	return prop(function(add)
		local n = 14
		for i = 1, n do
			local a = i / n * math.pi * 2
			add(V3(0.9, 0.55, 0.62), CFrame.Angles(a, 0, 0) * CFrame.new(0, 0.95, 0), INK)
			if i % 2 == 0 then
				add(V3(0.96, 0.2, 0.3), CFrame.Angles(a, 0, 0) * CFrame.new(0, 0.8, 0), WHITE)
			end
		end
		add(V3(0.5, 1.25, 1.25), CFrame.new(), RGB(192, 203, 220), Enum.Material.Foil, 0, Enum.PartType.Cylinder)
		add(V3(0.6, 0.45, 0.45), CFrame.new(), RGB(247, 118, 34), Enum.Material.SmoothPlastic, 0, Enum.PartType.Cylinder)
	end)
end
MoveFX.tyreProp = tyreProp

-- Oozark's ghostly jaw: an upper and a lower half, built out forward (-Z) from
-- their hinge at the back (the prop's root), so they open like a real jaw
local function jawHalf(style, upper)
	return prop(function(add)
		local s = upper and 1 or -1
		local core = RGB(26, 38, 22)
		-- the jelly slab, a little domed, and its darker inside
		add(V3(12, 2.6, 8), CFrame.new(0, s * 1.3, -4), style.Main, Enum.Material.SmoothPlastic, 0.4)
		add(V3(9, 1.2, 6), CFrame.new(0, s * 2.7, -4.3), style.Light, Enum.Material.SmoothPlastic, 0.45)
		add(V3(10.6, 0.6, 6.8), CFrame.new(0, s * 0.35, -4.2), core, Enum.Material.SmoothPlastic, 0.1)
		-- teeth round the front and sides, pointing at the other half
		for i = -5, 5 do
			add(V3(0.9, 1.9, 0.9), CFrame.new(i * 1.05, -s * 0.8, -7.6), WHITE)
		end
		for _, z in ipairs({ -6.2, -4.8, -3.4, -2.0 }) do
			add(V3(0.9, 1.6, 0.9), CFrame.new(-5.6, -s * 0.7, z), WHITE)
			add(V3(0.9, 1.6, 0.9), CFrame.new(5.6, -s * 0.7, z), WHITE)
		end
		if upper then
			-- Oozark's eyes, glowing on top
			for _, x in ipairs({ -2.8, 2.8 }) do
				add(V3(2.2, 1.4, 1.8), CFrame.new(x, 3.2, -6.2), RGB(236, 255, 170), Enum.Material.Neon)
				add(V3(0.8, 0.9, 0.5), CFrame.new(x, 3.2, -7.2), INK)
			end
		end
	end)
end

-- a giant ape fist (knuckles down), a gold cuff with a banana medallion
local function fistProp(at)
	return prop(function(add)
		local fur, skin, gold = RGB(70, 68, 82), RGB(165, 160, 172), RGB(254, 174, 52)
		add(V3(9, 7, 7), CFrame.new(0, 0, 0), fur)
		for i = 0, 3 do
			add(V3(2, 2.2, 2.4), CFrame.new(-3.3 + i * 2.2, -4, -1.8), skin)
		end
		add(V3(2.4, 3, 2.4), CFrame.new(-5.2, -1.2, 1), skin)
		add(V3(9.6, 2.4, 7.6), CFrame.new(0, 3.8, 0), gold, Enum.Material.Neon)
		add(V3(2.2, 2.2, 0.6), CFrame.new(0, 3.8, -3.95), RGB(254, 231, 97), Enum.Material.Neon)
		add(V3(7, 10, 6), CFrame.new(0, 9, 0), fur)
	end, at)
end

-- a falling star of gold
local function meteorProp()
	return prop(function(add)
		add(V3(4, 4, 4), CFrame.new(), RGB(254, 174, 52), Enum.Material.Neon, 0, Enum.PartType.Ball)
		add(V3(2.6, 2.6, 2.6), CFrame.new(0, 0, 0), RGB(255, 255, 220), Enum.Material.Neon, 0, Enum.PartType.Ball)
		for i = 1, 6 do
			local a = i / 6 * math.pi * 2
			add(V3(1.2, 1.2, 1.2), CFrame.new(math.cos(a) * 2, math.sin(a) * 2, 0), RGB(190, 120, 30), Enum.Material.Slate)
		end
	end)
end

-- move a prop along a path over time (fn(u) -> CFrame), then destroy it
local function fly(model, root, time, fn, after)
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local u = math.clamp((os.clock() - t0) / time, 0, 1)
		if root.Parent then
			root.CFrame = fn(u)
		end
		if u >= 1 then
			conn:Disconnect()
			if after then
				after(root.Position)
			end
			model:Destroy()
		end
	end)
end

-- a wireframe box of glowing bars round a spot (Delete Key's selection)
local function wireBox(at, size, color, time)
	local model = Instance.new("Model")
	model.Parent = fxFolder()
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	local w = 0.25
	local edges = {
		{ V3(0, -hy, -hz), V3(size.X, w, w) }, { V3(0, hy, -hz), V3(size.X, w, w) },
		{ V3(0, -hy, hz), V3(size.X, w, w) }, { V3(0, hy, hz), V3(size.X, w, w) },
		{ V3(-hx, 0, -hz), V3(w, size.Y, w) }, { V3(hx, 0, -hz), V3(w, size.Y, w) },
		{ V3(-hx, 0, hz), V3(w, size.Y, w) }, { V3(hx, 0, hz), V3(w, size.Y, w) },
		{ V3(-hx, -hy, 0), V3(w, w, size.Z) }, { V3(hx, -hy, 0), V3(w, w, size.Z) },
		{ V3(-hx, hy, 0), V3(w, w, size.Z) }, { V3(hx, hy, 0), V3(w, w, size.Z) },
	}
	for _, e in ipairs(edges) do
		local p = newPart(e[2], CFrame.new(at + e[1]), color, Enum.Material.Neon, 0)
		p.Parent = model
	end
	gone(model, time)
	return model
end

----------------------------------------------------------------------
-- RECIPES: [weapon id][Fx name](ctx) - what each step of each move looks
-- like. ctx: player, char, frame (where they are and face, flat, at that
-- moment), feet (the floor under them), style (colours), point (the spot a
-- Pick chose), own (it's your own move), step (Moves' step)
----------------------------------------------------------------------
local R = {}
MoveFX.RECIPES = R

local function ahead(ctx, d, side)
	local p = (ctx.frame * CFrame.new(side or 0, 0, -(d or 0))).Position
	return V3(p.X, ctx.feet.Y, p.Z)
end
local function chest(ctx, d)
	return (ctx.frame * CFrame.new(0, 0.5, -(d or 1.5))).Position
end
local function stepAhead(ctx)
	return ctx.step and ctx.step.Hit and ctx.step.Hit.Ahead or ctx.step and ctx.step.Zone and ctx.step.Zone.Ahead or 0
end

-- a slam on the floor: the flash, rings, flying bits, dust and a thump
local function slam(ctx, at, radius, colors, o)
	o = o or {}
	local s = ctx.style
	disc(at, colors[1], radius, 0.35, { r0 = 1.5 })
	ring(at, colors[2] or colors[1], radius * 1.1, 0.4, { size = 0.9 })
	ring(at, colors[3] or WHITE, radius * 0.7, 0.3, { size = 0.5, count = 18 })
	bits({ at = at + V3(0, 0.6, 0), colors = colors, count = o.bits or 18, speed = { 8, 22 }, up = { 10, 22 }, size = o.size or 0.6,
		life = 0.9, floor = at.Y, material = o.material })
	puffs(at + V3(0, 0.8, 0), o.dust or s.Light, 6, 2, 2.5, 0.7, radius * 0.5)
	light(at + V3(0, 2, 0), colors[1], radius * 2, 0.35)
	sfx(o.sound or SLAM, at)
end

-- a lingering puddle on the floor (bubbles popping in it) for `time` seconds
local function puddle(at, radius, time, s, o)
	o = o or {}
	local y = floorAt(at) + 0.07
	local p = newPart(V3(0.12, 0.5, 0.5), CFrame.new(at.X, y, at.Z) * CFrame.Angles(0, 0, rad(90)), s.Main,
		o.material or Enum.Material.SmoothPlastic, o.alpha or 0.2, Enum.PartType.Cylinder)
	tween(p, 0.25, { Size = V3(0.12, radius * 2, radius * 2) }, Enum.EasingStyle.Back)
	local rim = newPart(V3(0.1, 0.5, 0.5), CFrame.new(at.X, y + 0.02, at.Z) * CFrame.Angles(0, 0, rad(90)), s.Glow, Enum.Material.Neon, 0.5, Enum.PartType.Cylinder)
	tween(rim, 0.25, { Size = V3(0.1, radius * 2.1, radius * 2.1) }, Enum.EasingStyle.Back)
	local t0 = os.clock()
	task.spawn(function()
		while os.clock() - t0 < time and p.Parent do
			local a, r = rnd:NextNumber(0, math.pi * 2), rnd:NextNumber(0, radius * 0.85)
			local b = newPart(V3(0.5, 0.5, 0.5), CFrame.new(at.X + math.cos(a) * r, y + 0.2, at.Z + math.sin(a) * r), o.bubble or s.Light,
				Enum.Material.SmoothPlastic, 0.3, Enum.PartType.Ball)
			tween(b, 0.5, { Size = V3(1.1, 1.1, 1.1), Transparency = 1, CFrame = b.CFrame + V3(0, 0.9, 0) })
			gone(b, 0.55)
			if o.steam and rnd:NextNumber() < 0.4 then
				puffs(V3(at.X + math.cos(a) * r, y + 0.5, at.Z + math.sin(a) * r), o.steam, 1, 0.8, 2.5, 0.8, 0.2)
			end
			task.wait(0.12)
		end
		tween(p, 0.4, { Transparency = 1 })
		tween(rim, 0.4, { Transparency = 1 })
		gone(p, 0.45)
		gone(rim, 0.45)
	end)
end
MoveFX.puddle = puddle

-- a spin all the way round you
local function spin(ctx, radius, color, color2, o)
	o = o or {}
	local cf = ctx.frame * CFrame.new(0, o.height or -0.5, 0)
	sweep(cf, radius, 0, 360, color, 0.35, { width = o.width or 2, color2 = color2, count = 26, draw = 0.14 })
	ring(ctx.feet, color2 or color, radius, 0.35, { size = 0.7 })
	sfx(o.sound or WHOOSH, ctx.frame.Position)
end

-- 1. SLIME ------------------------------------------------------------
R.GooGloves = {
	Clap = function(ctx)
		local s, at = ctx.style, chest(ctx, 1.6)
		-- the goo bursting out between your fists, a jelly ring, drips raining down
		bits({ at = at, colors = { s.Main, s.Light, s.Glow }, count = 22, speed = { 6, 16 }, up = { 4, 14 }, size = 0.5, life = 0.8,
			transparency = 0.15, floor = ctx.feet.Y })
		for i = 1, 10 do
			local a = i / 10 * math.pi * 2
			local p = newPart(V3(0.7, 0.7, 0.7), CFrame.new(at), s.Main, Enum.Material.SmoothPlastic, 0.2, Enum.PartType.Ball)
			tween(p, 0.3, { CFrame = CFrame.new(at + (ctx.frame * CFrame.Angles(0, a, 0)).LookVector * 2.6 + V3(0, math.sin(a * 2) * 0.6, 0)),
				Size = V3(1.1, 1.1, 1.1), Transparency = 0.5 })
			task.delay(0.3, function()
				tween(p, 0.35, { Size = V3(0.2, 0.2, 0.2), Transparency = 1, CFrame = p.CFrame - V3(0, 1.5, 0) })
			end)
			gone(p, 0.7)
		end
		ring(ctx.feet, s.Main, 8, 0.4, { size = 0.7 })
		disc(ctx.feet, s.Glow, 6, 0.35)
		light(at, s.Glow, 14, 0.35)
		pop(at + V3(0, 3, 0), "STICKY!", s.Light, 5, 0.7)
		sfx({ "Goo Clap", "Orb Land", "Punch 2" }, at)
	end,
}
R.Jellyblade = {
	JellyGuard = function(ctx)
		local s = ctx.style
		-- a wobbling bubble of jelly round you, for as long as the guard lasts
		local bubble = newPart(V3(7, 7, 7), ctx.frame, s.Main, Enum.Material.SmoothPlastic, 0.72, Enum.PartType.Ball)
		local shine = newPart(V3(1.2, 1.2, 1.2), ctx.frame, s.Light, Enum.Material.Neon, 0.3, Enum.PartType.Ball)
		local t0 = os.clock()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local t = os.clock() - t0
			local root = ctx.char and ctx.char:FindFirstChild("HumanoidRootPart")
			if t > 4.2 or not root then
				conn:Disconnect()
				tween(bubble, 0.25, { Transparency = 1, Size = V3(9, 9, 9) })
				gone(bubble, 0.3)
				shine:Destroy()
				return
			end
			local w = math.sin(t * 9) * 0.35
			bubble.Size = V3(7 + w, 7 - w, 7 + w)
			bubble.CFrame = root.CFrame
			shine.CFrame = root.CFrame * CFrame.new(-1.8, 2.2, -1.8)
		end)
		ring(ctx.feet, s.Light, 6, 0.3, { size = 0.5 })
		sfx({ "Jelly Wobble", "Orb Land" }, ctx.frame.Position, 0.8)
	end,
}
R.GelatinHammer = {
	Rise = function(ctx)
		local s = ctx.style
		bits({ at = ctx.feet + V3(0, 0.4, 0), colors = { s.Main, s.Light }, count = 8, speed = { 3, 7 }, up = { 3, 6 }, size = 0.4, life = 0.5, transparency = 0.25 })
		sfx({ "Hammer Swing", "Portal Whoosh" }, ctx.frame.Position, 0.9)
	end,
	Slam = function(ctx)
		local s = ctx.style
		local at = ahead(ctx, stepAhead(ctx))
		slam(ctx, at, 10, { s.Main, s.Light, s.Glow }, { bits = 22, material = Enum.Material.SmoothPlastic, sound = { "Goo Slam", "Cube Slam", "Boss Slam", "Hammer Hit" } })
		-- a crown of jelly splashing up
		for i = 1, 10 do
			local a = i / 10 * math.pi * 2
			local p = newPart(V3(0.8, 0.8, 0.8), CFrame.new(at + V3(math.cos(a) * 3, 0.4, math.sin(a) * 3)), s.Main, Enum.Material.SmoothPlastic, 0.25)
			tween(p, 0.25, { Size = V3(0.9, 3.2, 0.9), CFrame = p.CFrame + V3(math.cos(a) * 0.8, 1.6, math.sin(a) * 0.8) }, Enum.EasingStyle.Back)
			task.delay(0.25, function()
				tween(p, 0.35, { Size = V3(0.3, 0.3, 0.3), Transparency = 1, CFrame = p.CFrame - V3(0, 1.5, 0) })
			end)
			gone(p, 0.65)
		end
		pop(at + V3(0, 5, 0), "SPLAT!", s.Light, 6, 0.8)
	end,
	Puddle = function(ctx)
		puddle(ahead(ctx, stepAhead(ctx)), 8, 3, ctx.style)
		sfx({ "Goo Splat" }, ahead(ctx, stepAhead(ctx)), 0.8)
	end,
}
R.OozeDaggers = {
	Crouch = function(ctx)
		local s = ctx.style
		light(chest(ctx, 0.5), s.Glow, 10, 0.25)
		ring(ctx.feet, s.Glow, 4, 0.2, { size = 0.4, count = 14 })
	end,
	Streak = function(ctx)
		local s = ctx.style
		-- afterimages along the dash
		for i = 0, 3 do
			task.delay(i * 0.06, function()
				afterimage(ctx.char, s.Glow, 0.3, 0.55)
			end)
		end
		sfx({ "Slime Dash", "Portal Whoosh", "Wave Zoom", "Whirlwind" }, ctx.frame.Position, 1)
	end,
	Cut = function(ctx)
		local s = ctx.style
		local a = ctx.marks.Start or ctx.frame.Position
		local b = ctx.frame.Position
		streak(V3(a.X, ctx.feet.Y + 2.5, a.Z), V3(b.X, ctx.feet.Y + 2.5, b.Z), s.Glow, 1.2, 0.35)
		streak(V3(a.X, ctx.feet.Y + 2.5, a.Z), V3(b.X, ctx.feet.Y + 2.5, b.Z), WHITE, 0.4, 0.2)
		bits({ at = b + V3(0, 1, 0), colors = { s.Glow, s.Main }, count = 12, speed = { 6, 14 }, up = { 4, 10 }, size = 0.4, life = 0.6 })
		sfx({ "Dagger Swing", "Sword Swing" }, b, 0.9)
	end,
	Trail = function(ctx)
		local s = ctx.style
		local a = ctx.marks.Start or ctx.frame.Position
		local b = ctx.marks.End or ctx.frame.Position
		local d = V3(b.X - a.X, 0, b.Z - a.Z)
		local n = math.max(2, math.floor(d.Magnitude / 3))
		for i = 0, n do
			puddle(a:Lerp(b, i / n), 2.2, 3, s, { steam = s.Light })
		end
		sfx({ "Acid Hiss" }, a:Lerp(b, 0.5))
	end,
}
R.AcidScythe = {
	Spin = function(ctx)
		local s = ctx.style
		spin(ctx, 11, s.Glow, s.Light)
		disc(ctx.feet, s.Glow, 11, 0.3)
		light(ctx.frame.Position, s.Glow, 22, 0.3)
		sfx({ "Whirlwind", "Scythe Swing", "Portal Whoosh" }, ctx.frame.Position, 1.1)
	end,
	Fling = function(ctx)
		local s = ctx.style
		local shot = ctx.step.Shot
		sfx({ "Acid Fling", "Orb Land" }, ctx.frame.Position)
		for i = 1, shot.Count do
			local dirv = (ctx.frame * CFrame.Angles(0, rad((i - 1) / shot.Count * 360), 0)).LookVector
			local start = ctx.frame.Position + V3(0, 1, 0) + dirv * 1.5
			local target = onFloor(start + dirv * shot.Range, 0.6)
			local model, root = globProp(s)
			fly(model, root, shot.Range / shot.Speed, function(u)
				local p = start:Lerp(target, u) + V3(0, math.sin(u * math.pi) * 4, 0)
				return CFrame.new(p)
			end, function(pos)
				slam(ctx, onFloor(pos), 5, { s.Glow, s.Main, s.Light }, { bits = 10, size = 0.45, sound = { "Acid Burst", "Orb Land" } })
				puddle(pos, 5, 3, s, { steam = s.Light })
			end)
		end
	end,
}
R.GelatinousEdge = {
	Draw = function(ctx)
		local s = ctx.style
		light(chest(ctx, 0.2), s.Glow, 10, 0.35)
		ring(ctx.feet, s.Glow, 3.5, 0.3, { size = 0.35, count = 16 })
		bits({ at = chest(ctx, 0.3), colors = { s.Glow }, count = 6, speed = { 1, 3 }, up = { 2, 5 }, size = 0.3, life = 0.5, gravity = 0, material = Enum.Material.Neon })
		sfx({ "Blade Draw", "Katana Swing" }, ctx.frame.Position)
	end,
	Jaw = function(ctx)
		local s = ctx.style
		-- hinged at its back, 5 studs in front of you, facing away (at them)
		local hinge = ctx.frame * CFrame.new(0, 2.4, -5)
		local top, troot = jawHalf(s, true)
		local bot, broot = jawHalf(s, false)
		-- it opens wide (0.25 s), hangs there, then snaps shut on the Chomp
		-- (0.38 s after it appeared) - and melts away into goo
		local t0 = os.clock()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local t = os.clock() - t0
			local open
			if t < 0.25 then
				open = 1 - (1 - t / 0.25) ^ 3
			elseif t < 0.33 then
				open = 1
			else
				open = math.max(0, 1 - (t - 0.33) / 0.05)
			end
			local rise = 0.3 + 0.2 * open
			troot.CFrame = hinge * CFrame.new(0, rise, 0) * CFrame.Angles(rad(40 * open), 0, 0)
			broot.CFrame = hinge * CFrame.new(0, -rise, 0) * CFrame.Angles(rad(-28 * open), 0, 0)
			if t > 0.62 then
				conn:Disconnect()
				local at = (hinge * CFrame.new(0, 0, -4)).Position
				bits({ at = at, colors = { s.Main, s.Light, WHITE }, count = 22, speed = { 4, 12 }, up = { 2, 10 }, size = 0.7, life = 0.8,
					transparency = 0.2, floor = ctx.feet.Y })
				top:Destroy()
				bot:Destroy()
			end
		end)
		sfx({ "Jaw Open", "Portal Whoosh", "Wave Zoom", "Whirlwind" }, ctx.frame.Position, 1)
	end,
	Chomp = function(ctx)
		local s = ctx.style
		local at = ahead(ctx, 9)
		slam(ctx, at, 12, { s.Glow, s.Main, s.Light }, { bits = 26, size = 0.7, sound = { "Jaw Chomp", "Bomb Drop", "UFO Burst", "Boss Slam" } })
		pop(at + V3(0, 7, 0), "CHOMP!", s.Glow, 9, 0.9)
		if ctx.own or nearMe(at, 30) then
			screenFlash(s.Glow, 0.35, 0.3)
		end
	end,
}

-- 3. KNIGHT -----------------------------------------------------------
-- (each sound a list: its own, then what plays till it's uploaded)
local K_DIG = { "Spade Dig", "Shovel Dig", "Punch 3", "Cube Slam" }
local K_GLINT = { "Treasure Glint", "Relic Get", "Orb Land", "Level Complete" }
local K_COIN = { "Coin Ding", "Gem Land", "Orb Land" }
local K_SPIN = { "Dirt Spin", "Whirlwind", "Portal Whoosh" }
local K_CLOD = { "Dirt Splat", "Dirt Land" }
local K_BOING = { "Pogo Boing", "Burrowmore Jump", "Dummy Land" }
local K_CLANG = { "Pogo Clang", "Burrowmore Land", "Cube Slam", "Boss Slam", "Hammer Hit" }
local K_HURL = { "Anchor Hurl", "Anchor Throw", "Portal Whoosh", "Whirlwind" }
local K_REEL = { "Chain Reel", "Wave Zoom" }
local K_ANCHOR = { "Anchor Slam", "Anchor Land", "Cube Slam", "Boss Slam", "Hammer Hit" }
local K_CRACK = { "Plate Crack", "Armour Crack", "Orb Land", "Level Complete" }
local K_FALL = { "Meteor Fall", "Portal Whoosh", "Wave Zoom" }
local K_METEOR = { "Meteor Impact", "Shovel Meteor", "Bomb Drop", "UFO Burst", "Boss Slam" }
local ARMOUR, ARMOUR_DEEP = RGB(0, 153, 219), RGB(18, 78, 137)

-- a glint: bars of light crossing in a star, facing the way you do
local function glint(ctx, at, color, arms, long, time)
	local face = ctx.frame - ctx.frame.Position
	for i, a in ipairs(arms) do
		local len = long * (i <= 2 and 1 or 0.6)
		local p = newPart(V3(0.4, 0.4, len), CFrame.new(at) * face * CFrame.Angles(0, 0, rad(a)) * CFrame.Angles(rad(90), 0, 0),
			color, Enum.Material.Neon, 0)
		tween(p, time, { Size = V3(0.05, 0.05, len * 1.3), Transparency = 1 })
		gone(p, time + 0.05)
	end
end

R.ShovelHammer = {
	Dig = function(ctx)
		local s = ctx.style
		local at = ahead(ctx, 3)
		-- the spade bites in: a mound of dirt heaves up in front of you, clods
		-- fly back over your shoulder, and a gold glint off the spade says your
		-- next hit's a dig slam
		local mound = newPart(V3(3, 1, 3), CFrame.new(at - V3(0, 0.6, 0)), s.Main, Enum.Material.Slate, 0, Enum.PartType.Ball)
		tween(mound, 0.15, { CFrame = CFrame.new(at + V3(0, 0.1, 0)), Size = V3(3.4, 1.6, 3.4) }, Enum.EasingStyle.Back)
		task.delay(0.5, function()
			tween(mound, 0.4, { CFrame = CFrame.new(at - V3(0, 0.8, 0)), Size = V3(2, 0.4, 2), Transparency = 1 })
		end)
		gone(mound, 0.95)
		bits({ at = at + V3(0, 0.5, 0), colors = { s.Main, s.Dark, s.Light }, count = 16, speed = { 4, 10 }, up = { 8, 16 }, size = 0.55,
			life = 0.9, floor = at.Y, material = Enum.Material.Slate, dir = ctx.frame.LookVector * -1, spread = 1.2 })
		puffs(at + V3(0, 0.6, 0), s.Light, 4, 1.8, 2, 0.6, 1.5)
		glint(ctx, (ctx.frame * CFrame.new(0.8, 1.6, -1.2)).Position, s.Glow, { 0, 90 }, 3.5, 0.3)
		light(at + V3(0, 2, 0), s.Glow, 10, 0.4)
		sfx(K_DIG, at)
	end,
}
R.RelicDaggers = {
	Glint = function(ctx)
		local s = ctx.style
		local at = (ctx.frame * CFrame.new(0, 1.5, -1)).Position
		-- Treasure Eye: a star of gold glints in front of you and a ring of
		-- coins spins round you and flies off
		glint(ctx, at, s.Light, { 0, 90, 45, -45 }, 7, 0.35)
		local centre = ctx.frame.Position
		for i = 1, 8 do
			local a0 = i / 8 * math.pi * 2
			local coin = newPart(V3(0.15, 0.9, 0.9), CFrame.new(centre), i % 2 == 0 and s.Main or s.Light, Enum.Material.Neon, 0, Enum.PartType.Cylinder)
			local t0 = os.clock()
			local conn
			conn = RunService.Heartbeat:Connect(function()
				local u = (os.clock() - t0) / 0.6
				if u >= 1 or not coin.Parent then
					conn:Disconnect()
					coin:Destroy()
					return
				end
				local a = a0 + u * 5
				local r = 2.2 + u * 2.5
				coin.CFrame = CFrame.new(centre + V3(math.cos(a) * r, 0.5 + u * 1.5, math.sin(a) * r)) * CFrame.Angles(0, -a + u * 12, 0)
				coin.Transparency = math.max(0, (u - 0.6) / 0.4)
			end)
		end
		bits({ at = at, colors = { s.Light, s.Main }, count = 10, speed = { 4, 9 }, up = { 3, 8 }, size = 0.35, life = 0.7, material = Enum.Material.Neon })
		light(at, s.Light, 12, 0.35)
		sfx(K_GLINT, at)
	end,
}
R.SpadeScythe = {
	Spin = function(ctx)
		local s = ctx.style
		spin(ctx, 10, RGB(192, 203, 220), s.Glow, { height = -1.5, sound = K_SPIN })
		puffs(ctx.feet + V3(0, 0.6, 0), s.Light, 8, 2.2, 1.5, 0.8, 6)
	end,
	Clods = function(ctx)
		local s = ctx.style
		local shot = ctx.step.Shot
		for i = 1, shot.Count do
			local dirv = (ctx.frame * CFrame.Angles(0, rad((i - 1) / shot.Count * 360), 0)).LookVector
			local start = ctx.frame.Position + dirv * 1.5
			local target = onFloor(start + dirv * shot.Range, 0.4)
			local model, root = clodProp(s)
			fly(model, root, shot.Range / shot.Speed, function(u)
				return CFrame.new(start:Lerp(target, u) + V3(0, math.sin(u * math.pi) * 3, 0)) * CFrame.Angles(u * 8, u * 5, 0)
			end, function(pos)
				bits({ at = pos + V3(0, 0.4, 0), colors = { s.Main, s.Dark }, count = 6, speed = { 3, 7 }, up = { 4, 8 }, size = 0.4, life = 0.6,
					floor = pos.Y - 0.4, material = Enum.Material.Slate })
				puffs(pos, s.Light, 2, 1.4, 1, 0.5, 0.5)
				if i % 3 == 1 then
					sfx(K_CLOD, pos, 0.9 + i * 0.05, 0.7) -- (a couple of thuds, not six at once)
				end
			end)
		end
	end,
}
R.HonourBlade = {
	Jump = function(ctx)
		local s = ctx.style
		ring(ctx.feet, s.Light, 5, 0.3, { size = 0.5 })
		puffs(ctx.feet + V3(0, 0.5, 0), WHITE, 4, 1.6, 1, 0.5, 1.5)
		-- a golden trail behind you on the way up and down
		for i = 0, 7 do
			task.delay(i * 0.07, function()
				afterimage(ctx.char, s.Light, 0.25, 0.6)
			end)
		end
		sfx(WHOOSH, ctx.frame.Position, 0.9)
	end,
	Plunge = function(ctx)
		local s = ctx.style
		local at = ctx.feet
		-- blade-first into them: a clang of gold, a pillar of light, a star burst
		slam(ctx, at, 8, { s.Light, s.Main, WHITE }, { bits = 16, size = 0.5, sound = K_CLANG })
		column(at, s.Light, 14, 2.2, 0.35)
		for i = 1, 8 do
			local a = i / 8 * math.pi * 2
			streak(at + V3(0, 0.3, 0), at + V3(math.cos(a) * 7, 0.3, math.sin(a) * 7), s.Light, 0.7, 0.3)
		end
	end,
	Bounce = function(ctx)
		local s = ctx.style
		local at = ctx.feet
		-- BOING: a gold spring shoots up under you and flings you back up
		for i = 1, 5 do
			local c = newPart(V3(0.3, 2.6, 2.6), CFrame.new(at + V3(0, 0.15 + i * 0.12, 0)) * CFrame.Angles(0, 0, rad(90)),
				i % 2 == 0 and s.Main or s.Light, Enum.Material.Neon, 0, Enum.PartType.Cylinder)
			tween(c, 0.12, { CFrame = CFrame.new(at + V3(0, 0.15 + i * 0.7, 0)) * CFrame.Angles(0, 0, rad(90)) }, Enum.EasingStyle.Back)
			task.delay(0.12, function()
				tween(c, 0.25, { Transparency = 1, Size = V3(0.3, 1, 1) })
			end)
			gone(c, 0.42)
		end
		ring(at, s.Light, 6, 0.3, { size = 0.5 })
		puffs(at + V3(0, 0.5, 0), WHITE, 3, 1.4, 1, 0.4, 1)
		pop(at + V3(0, 5, 0), "BOING!", s.Light, 7, 0.6)
		sfx(K_BOING, at)
	end,
	Plunge2 = function(ctx)
		local s = ctx.style
		local at = ctx.feet
		-- and down again, harder: a bigger clang, a taller pillar, a wider star
		slam(ctx, at, 9, { s.Light, s.Main, WHITE }, { bits = 22, size = 0.6, sound = K_CLANG })
		column(at, s.Light, 18, 2.6, 0.4)
		for i = 1, 12 do
			local a = i / 12 * math.pi * 2
			streak(at + V3(0, 0.3, 0), at + V3(math.cos(a) * 9, 0.3, math.sin(a) * 9), i % 2 == 0 and s.Light or WHITE, 0.8, 0.35)
		end
		pop(at + V3(0, 6, 0), "HONOUR!", s.Light, 8, 0.9)
		if nearMe(at, 30) then
			screenFlash(s.Light, 0.25, 0.25)
		end
	end,
}
R.AnchorFists = {
	Throw = function(ctx)
		local s = ctx.style
		local root = ctx.char and ctx.char:FindFirstChild("Right Arm")
		local from = root and root.Position or ctx.frame.Position
		local target = ctx.point or ahead(ctx, 16)
		target = onFloor(target, 0.5)
		local model, proot = anchorProp()
		local handAtt = Instance.new("Attachment")
		handAtt.Position = V3(0, -1, 0)
		handAtt.Parent = root or proot
		local tipAtt = Instance.new("Attachment")
		tipAtt.Parent = proot
		local chain = beam(handAtt, tipAtt, RGB(139, 155, 180), 0.35)
		chain.Segments = 1
		local dirv = (target - from)
		local look = CFrame.lookAt(from, from + V3(dirv.X, 0, dirv.Z))
		-- out to the spot (0.3 s), holds while you're reeled in, then it's gone
		local flyTime = 0.3
		fly(model, proot, flyTime + 0.45, function(u)
			local k = math.clamp(u * (flyTime + 0.45) / flyTime, 0, 1)
			local p = from:Lerp(target, k) + V3(0, math.sin(k * math.pi) * 2.5, 0)
			return CFrame.new(p) * (look - look.Position) * CFrame.Angles(rad(-90 + k * 90), 0, 0)
		end, function(pos)
			handAtt:Destroy()
			bits({ at = pos, colors = { RGB(139, 155, 180), RGB(58, 68, 102) }, count = 8, speed = { 3, 7 }, up = { 4, 8 }, size = 0.4, life = 0.5 })
		end)
		task.delay(flyTime, function()
			-- it bites into the floor
			ring(target, s.Glow, 4, 0.25, { size = 0.5, count = 14 })
			bits({ at = target, colors = { RGB(140, 96, 60), RGB(84, 56, 40) }, count = 8, speed = { 3, 8 }, up = { 5, 10 }, size = 0.4, life = 0.6,
				floor = target.Y - 0.5, material = Enum.Material.Slate })
			sfx({ "Anchor Land", "Punch 4", "Cube Slam" }, target, 1, 0.7)
		end)
		sfx(K_HURL, from)
	end,
	Reel = function(ctx)
		for i = 0, 3 do
			task.delay(i * 0.07, function()
				afterimage(ctx.char, ctx.style.Glow, 0.25, 0.6)
			end)
		end
		sfx(K_REEL, ctx.frame.Position)
	end,
	Slam = function(ctx)
		local s = ctx.style
		slam(ctx, ctx.feet, 9, { s.Glow, s.Light, RGB(254, 174, 52) }, { bits = 18, sound = K_ANCHOR })
		pop(ctx.feet + V3(0, 6, 0), "ANCHORS AWAY!", RGB(254, 231, 97), 9, 0.8)
	end,
}
R.NoQuarter = {
	Crack = function(ctx)
		local s = ctx.style
		column(ctx.feet, s.Light, 20, 3, 0.5)
		ring(ctx.feet, s.Light, 9, 0.4, { size = 0.8 })
		bits({ at = ctx.frame.Position, colors = { s.Light, s.Main }, count = 16, speed = { 4, 10 }, up = { 6, 14 }, size = 0.4, life = 0.8, material = Enum.Material.Neon })
		-- your armour cracks: plates of blue armour fly off you (like his
		-- shoulder plates) and gold glows through the cracks
		bits({ at = chest(ctx, 0), colors = { ARMOUR, ARMOUR_DEEP, s.Main }, count = 7, speed = { 6, 12 }, up = { 10, 16 }, size = 1.0, life = 1.1,
			floor = ctx.feet.Y, bounce = true })
		afterimage(ctx.char, s.Light, 0.5, 0.35)
		light(ctx.frame.Position, s.Light, 20, 0.6, 6)
		pop(ctx.frame.Position + V3(0, 5, 0), "NO QUARTER!", s.Light, 10, 1)
		if ctx.own then
			screenFlash(s.Light, 0.3, 0.35)
		end
		sfx(K_CRACK, ctx.frame.Position)
	end,
	Meteor = function(ctx)
		local s = ctx.style
		local target = onFloor(ctx.point or ahead(ctx, 10))
		-- the warning on the floor, then the star falls on it
		disc(target, s.Main, 10, 0.55, { r0 = 1, transparency = 0.5, material = Enum.Material.Neon })
		local start = target + V3(-18, 50, 12)
		local model, root = meteorProp()
		fly(model, root, 0.55, function(u)
			local p = start:Lerp(target + V3(0, 1, 0), u * u)
			if rnd:NextNumber() < 0.6 then
				local t = newPart(V3(1.4, 1.4, 1.4), CFrame.new(p), rnd:NextNumber() < 0.5 and s.Light or s.Main, Enum.Material.Neon, 0.2)
				tween(t, 0.35, { Size = V3(0.2, 0.2, 0.2), Transparency = 1 })
				gone(t, 0.4)
			end
			return CFrame.new(p) * CFrame.Angles(u * 6, u * 4, 0)
		end)
		sfx(K_FALL, target)
	end,
	Impact = function(ctx)
		local s = ctx.style
		local at = onFloor(ctx.point or ahead(ctx, 10))
		slam(ctx, at, 10, { s.Light, s.Main, WHITE }, { bits = 30, size = 0.8, sound = K_METEOR })
		column(at, s.Light, 26, 4, 0.5)
		-- treasure everywhere: gold coins bursting out of the crater
		bits({ at = at + V3(0, 1, 0), colors = { s.Main, s.Light }, count = 14, speed = { 6, 14 }, up = { 12, 20 }, size = 0.6, life = 1.2,
			material = Enum.Material.Neon, shape = Enum.PartType.Cylinder, floor = at.Y, bounce = true })
		if nearMe(at, 35) then
			screenFlash(WHITE, 0.3, 0.25)
		end
	end,
}

-- 5. SPEEDWAY ---------------------------------------------------------
local S_REV = { "Nitro Rev", "Engine Rev", "Ship Thrust", "Wave Zoom" }
local S_SCREECH = { "Tyre Screech", "Tire Screech", "Tire Skid", "Wave Zoom" }
local S_NITRO = { "Nitro Boost", "Ship Thrust", "Portal Whoosh" }
local S_PUMP = { "Piston Pump", "Ship Thrust" }
local S_PUNCH = { "Piston Punch", "Exhaust Backfire", "Bomb Drop", "UFO Burst", "Boss Slam" }
local S_BOUNCE = { "Tyre Bounce", "Car Bump", "Dummy Land" }
local S_ROLL = { "Wheel Roll", "Ship Thrust", "Wave Zoom" }
local S_WHEELIE = { "Wheelie Slam", "Suspension Slam", "Bomb Drop", "UFO Burst", "Boss Slam" }
local S_GO = { "Race Go", "Start Go", "Attempt Start", "Level Complete" }
local S_FINISH = { "Finish Line", "Checkered Flag", "Level Complete" }
local S_HONK = { "Horn Honk", "Big Honk" }
local CONFETTI = { RGB(247, 118, 34), WHITE, RGB(254, 231, 97), RGB(99, 199, 77), RGB(44, 232, 245), RGB(228, 59, 68) }

-- a checkered flag burst (black and white squares flying out)
local function checkers(at, count)
	bits({ at = at, colors = { WHITE, INK }, count = count or 20, speed = { 8, 18 }, up = { 8, 18 }, size = 0.7, life = 1, floor = at.Y - 1 })
end
-- black rubber burnt onto the floor, fading after a while
local function skidMark(a, b, width, stay)
	local y = floorAt(a) + 0.05
	local d = b - a
	if d.Magnitude < 0.05 then
		return
	end
	local mark = newPart(V3(width, 0.06, d.Magnitude), CFrame.lookAt(V3(a.X, y, a.Z):Lerp(V3(b.X, y, b.Z), 0.5), V3(b.X, y, b.Z)), INK,
		Enum.Material.SmoothPlastic, 0.2)
	task.delay(stay, function()
		tween(mark, 0.6, { Transparency = 1 })
	end)
	gone(mark, stay + 0.65)
end

R.TyreScythe = {
	Rev = function(ctx)
		local s = ctx.style
		local back = ahead(ctx, -1.5)
		-- Burnout: the wheels spin on the spot - two black streaks burnt onto
		-- the floor under you, a cloud of tyre smoke, a hot orange glow
		for _, side in ipairs({ -0.7, 0.7 }) do
			skidMark(ahead(ctx, 0.5, side), ahead(ctx, -3.5, side), 0.5, 1.2)
			streak(ahead(ctx, 1, side * 2) + V3(0, 0.3, 0), ahead(ctx, -6, side * 2) + V3(0, 0.3, 0), s.Glow, 0.5, 0.4)
		end
		puffs(back + V3(0, 0.6, 0), s.Light, 9, 2, 2, 1, 2)
		light(back + V3(0, 1, 0), s.Glow, 10, 0.4)
		sfx(S_REV, ctx.frame.Position)
		sfx(S_SCREECH, back, 1, 0.6)
	end,
}
R.NitroKatana = {
	Boost = function(ctx)
		local s = ctx.style
		local back = (ctx.frame * CFrame.new(0, 0.5, 1.5)).Position
		-- a blue flame blasting out behind you, speed lines streaking past
		for i = 1, 10 do
			local p = newPart(V3(1, 1, 1), CFrame.new(back), i % 2 == 0 and s.Glow or s.Main, Enum.Material.Neon, 0.1, Enum.PartType.Ball)
			local out = (ctx.frame * CFrame.new(rnd:NextNumber(-1, 1), rnd:NextNumber(-0.5, 1), 4 + i * 0.6)).Position
			tween(p, 0.35, { CFrame = CFrame.new(out), Size = V3(2.2, 2.2, 2.2), Transparency = 1 })
			gone(p, 0.4)
		end
		for i = 1, 6 do
			local side, up = rnd:NextNumber(-2.5, 2.5), rnd:NextNumber(-1, 2.5)
			local a = (ctx.frame * CFrame.new(side, up, -2)).Position
			local b = (ctx.frame * CFrame.new(side, up, 5)).Position
			streak(a, b, i % 2 == 0 and WHITE or s.Light, 0.15, 0.25, { thick = 0.15 })
		end
		ring(ctx.feet, s.Glow, 7, 0.3, { size = 0.6 })
		light(back, s.Glow, 14, 0.4)
		pop(ctx.frame.Position + V3(0, 4.5, 0), "NITRO!", s.Light, 6, 0.6)
		sfx(S_NITRO, ctx.frame.Position)
	end,
}
R.PistonPunchers = {
	Pump = function(ctx)
		puffs(chest(ctx, 0.2) + V3(0, 1, 0), WHITE, 5, 1.2, 3, 0.6, 1)
		sfx(S_PUMP, ctx.frame.Position)
	end,
	Flames = function(ctx)
		local s = ctx.style
		local t0 = os.clock()
		task.spawn(function()
			while os.clock() - t0 < 0.3 do
				local root = ctx.char and ctx.char:FindFirstChild("HumanoidRootPart")
				if not root then
					break
				end
				local p = newPart(V3(1.4, 1.4, 1.4), root.CFrame * CFrame.new(rnd:NextNumber(-0.6, 0.6), rnd:NextNumber(-1, 0.5), 1), rnd:NextNumber() < 0.5 and s.Main or s.Light, Enum.Material.Neon, 0.1)
				tween(p, 0.4, { Size = V3(0.3, 0.3, 0.3), Transparency = 1, CFrame = p.CFrame + V3(0, 1.5, 0) })
				gone(p, 0.45)
				task.wait(0.025)
			end
		end)
		sfx(WHOOSH, ctx.frame.Position, 1.1)
	end,
	Boom = function(ctx)
		local s = ctx.style
		local at = ahead(ctx, 3)
		slam(ctx, at, 7, { s.Main, s.Light, s.Glow }, { bits = 16, sound = S_PUNCH })
		puffs(at + V3(0, 1.5, 0), RGB(90, 90, 100), 5, 2, 3, 0.8, 1.5)
		pop(at + V3(0, 5, 0), "VROOM!", s.Light, 7, 0.7)
	end,
}
R.PitStopSabre = {
	SkidSpin = function(ctx)
		local s = ctx.style
		spin(ctx, 11, s.Glow, WHITE, { sound = S_SCREECH })
		-- a black skid circle burnt into the floor, sparks and tyre smoke
		for i = 1, 16 do
			local a = i / 16 * math.pi * 2
			local p = newPart(V3(1.2, 0.08, 2.4), CFrame.new(ctx.feet + V3(math.cos(a) * 4.5, 0.05, math.sin(a) * 4.5)) * CFrame.Angles(0, -a, 0), INK, Enum.Material.SmoothPlastic, 0.2)
			task.delay(1.2, function()
				tween(p, 0.8, { Transparency = 1 })
			end)
			gone(p, 2.1)
		end
		bits({ at = ctx.feet + V3(0, 0.5, 0), colors = { s.Light, s.Glow }, count = 16, speed = { 14, 24 }, up = { 2, 6 }, size = 0.25, life = 0.5, material = Enum.Material.Neon })
		puffs(ctx.feet + V3(0, 1, 0), s.Light, 10, 2.6, 2, 1.1, 5)
	end,
	Tyres = function(ctx)
		local s = ctx.style
		local shot = ctx.step.Shot
		local time = shot.Range / shot.Speed
		local floorY = ctx.feet.Y
		-- the pit crew's spare tyres go flying out all round you, bouncing
		-- twice (lower each time) and rolling as they go
		for i = 1, shot.Count do
			local dirv = (ctx.frame * CFrame.Angles(0, rad((i - 1) / shot.Count * 360), 0)).LookVector
			local start = ctx.frame.Position + dirv * 1.5
			local model, root = tyreProp()
			fly(model, root, time, function(u)
				local hop = math.abs(math.sin(u * math.pi * 2.5)) * (1.8 * (1 - u) + 0.3)
				local pos = V3(start.X, floorY + 1.2 + hop, start.Z) + dirv * (shot.Range * u)
				return CFrame.lookAt(pos, pos + dirv) * CFrame.Angles(-u * shot.Range / 1.2, 0, 0)
			end, function(pos)
				puffs(pos, s.Light, 3, 1.4, 1.5, 0.5, 0.6)
				bits({ at = pos, colors = { INK, RGB(58, 68, 102) }, count = 5, speed = { 3, 7 }, up = { 4, 9 }, size = 0.4, life = 0.6, floor = floorY })
			end)
			for _, u in ipairs({ 0.4, 0.8 }) do
				task.delay(time * u, function()
					local at = V3(start.X, floorY + 0.3, start.Z) + dirv * (shot.Range * u)
					puffs(at, s.Light, 2, 1.2, 1, 0.4, 0.4)
					if i == 1 then
						sfx(S_BOUNCE, at, 1 + u * 0.2, 0.8)
					end
				end)
			end
		end
	end,
}
R.WheelieWrecker = {
	Wheel = function(ctx)
		local s = ctx.style
		local model, root = wheelProp()
		local t0 = os.clock()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local t = os.clock() - t0
			local hrp = ctx.char and ctx.char:FindFirstChild("HumanoidRootPart")
			if t > 0.95 or not hrp then
				conn:Disconnect()
				model:Destroy()
				return
			end
			local look = hrp.CFrame.LookVector
			local f = V3(look.X, 0, look.Z).Magnitude > 0.01 and V3(look.X, 0, look.Z).Unit or V3(0, 0, -1)
			local pos = hrp.Position + f * 1.6 - V3(0, 0.3, 0)
			root.CFrame = CFrame.lookAt(pos, pos + f) * CFrame.Angles(-t * 28, 0, 0)
			if rnd:NextNumber() < 0.7 then
				local p = newPart(V3(1.2, 1.2, 1.2), CFrame.new(pos - f * 1.5 + V3(rnd:NextNumber(-1, 1), -1.4, 0)), rnd:NextNumber() < 0.5 and s.Main or s.Light, Enum.Material.Neon, 0.1)
				tween(p, 0.45, { Size = V3(0.2, 0.2, 0.2), Transparency = 1, CFrame = p.CFrame + V3(0, 1.2, 0) })
				gone(p, 0.5)
			end
		end)
		sfx(S_ROLL, ctx.frame.Position)
	end,
	Slam = function(ctx)
		local s = ctx.style
		local at = ahead(ctx, 3)
		slam(ctx, at, 10, { s.Main, s.Light, s.Glow }, { bits = 22, sound = S_WHEELIE })
		for i = 1, 8 do
			local a = i / 8 * math.pi * 2
			local p = newPart(V3(1.4, 2, 1.4), CFrame.new(at + V3(math.cos(a) * 3, 1, math.sin(a) * 3)), s.Light, Enum.Material.Neon, 0.1)
			tween(p, 0.5, { Size = V3(0.3, 4.5, 0.3), Transparency = 1, CFrame = p.CFrame + V3(math.cos(a) * 2, 2.5, math.sin(a) * 2) })
			gone(p, 0.55)
		end
	end,
}
R.VictoryLap = {
	Go = function(ctx)
		local s = ctx.style
		pop(ctx.frame.Position + V3(0, 5, 0), "GO!", RGB(99, 199, 77), 8, 0.8)
		checkers(ctx.frame.Position + V3(0, 1, 0), 18)
		ring(ctx.feet, s.Glow, 8, 0.35, { size = 0.7 })
		-- afterimages behind you while the blur lasts
		local t0 = os.clock()
		task.spawn(function()
			while os.clock() - t0 < 6 do
				afterimage(ctx.char, rnd:NextNumber() < 0.5 and s.Glow or WHITE, 0.3, 0.6)
				task.wait(0.09)
			end
		end)
		if ctx.own then
			screenFlash(WHITE, 0.25, 0.2)
		end
		sfx(S_GO, ctx.frame.Position)
	end,
	Finish = function(ctx)
		local s = ctx.style
		slam(ctx, ctx.feet, 12, { s.Glow, WHITE, INK }, { bits = 20, sound = S_FINISH })
		checkers(ctx.frame.Position + V3(0, 1, 0), 30)
		-- the finish line pops up across the floor in front of you, and confetti
		local y = ctx.feet.Y + 0.08
		for i = -6, 6 do
			for row = 0, 1 do
				local at = (ctx.frame * CFrame.new(i * 0.9, 0, -2 - row * 0.9)).Position
				local lit = (i + row) % 2 == 0
				local sq = newPart(V3(0.9, 0.1, 0.9), CFrame.new(at.X, y, at.Z) * (ctx.frame - ctx.frame.Position), lit and WHITE or INK,
					lit and Enum.Material.Neon or Enum.Material.SmoothPlastic, 0)
				task.delay(0.8, function()
					tween(sq, 0.5, { Transparency = 1 })
				end)
				gone(sq, 1.35)
			end
		end
		bits({ at = ctx.frame.Position + V3(0, 3, 0), colors = CONFETTI, count = 36, speed = { 6, 14 }, up = { 10, 18 }, size = 0.4, life = 1.6,
			gravity = 14, floor = ctx.feet.Y })
		pop(ctx.frame.Position + V3(0, 6, 0), "FINISH!", RGB(254, 231, 97), 10, 1)
		sfx(S_HONK, ctx.frame.Position, 1, 0.7)
	end,
}

-- 7. JUNGLE -----------------------------------------------------------
-- (each sound a list: its own, then what plays till it's uploaded)
local J_THUMP = { "Chest Thump", "Kongo Chest Pound", "Punch 4" }
local J_ROAR = { "Ape Roar", "Kongo Roar", "Boss Wail", "Gridlock Stun" }
local J_FANG = { "Fang Snap", "Flytrap Chomp", "Punch 1" }
local J_CREAK = { "Vine Creak", "Vine Burst", "Portal Whoosh" }
local J_SWEEP = { "Leaf Sweep", "Whirlwind", "Cube Slam" }
local J_CURL = { "Barrel Curl", "Barrel Throw", "Punch 4" }
local J_RUMBLE = { "Barrel Rumble", "Kongo Roll", "Wave Zoom" }
local J_BURST = { "Barrel Burst", "Barrel Break", "Cube Slam" }
local J_BAT = { "Barrel Bat", "Barrel Throw", "Cube Slam", "Hammer Hit" }
local J_BLAST = { "Barrel Blast", "TNT Boom", "Bomb Drop", "UFO Burst", "Boss Slam" }
local J_CALL = { "Crown Call", "Royal Trumpet", "Kongo Hoot", "Orb Land", "Level Complete" }
local J_SKY = { "Sky Whoosh", "Meteor Fall", "Portal Whoosh", "Wave Zoom" }
local J_SMASH = { "Fist Smash", "Kongo Giant Punch", "Giant Stomp", "Bomb Drop", "Boss Slam" }
local LEAVES = { RGB(99, 199, 77), RGB(170, 226, 96), RGB(38, 92, 66) }
local KONGO_FACE = RGB(165, 160, 172)

-- jungle leaves: flat green flakes flung out and up, fluttering down
local function leaves(at, count, o)
	o = o or {}
	for _ = 1, count do
		local start = at + V3(rnd:NextNumber(-1, 1), rnd:NextNumber(-0.5, 0.5), rnd:NextNumber(-1, 1)) * (o.spread or 1)
		local p = newPart(V3(0.8, 0.08, 0.5), CFrame.new(start) * CFrame.Angles(rnd:NextNumber(0, 6), rnd:NextNumber(0, 6), 0),
			LEAVES[rnd:NextInteger(1, #LEAVES)])
		local a = rnd:NextNumber(0, math.pi * 2)
		local out = V3(math.cos(a), 0, math.sin(a)) * rnd:NextNumber(o.out and o.out[1] or 2, o.out and o.out[2] or 6)
		local up = rnd:NextNumber(o.up and o.up[1] or 1, o.up and o.up[2] or 4)
		local time = rnd:NextNumber(0.9, 1.4) * (o.time or 1)
		local top = CFrame.new(start + out * 0.6 + V3(0, up, 0)) * CFrame.Angles(rnd:NextNumber(0, 6), rnd:NextNumber(0, 6), 0)
		tween(p, time * 0.35, { CFrame = top })
		task.delay(time * 0.35, function()
			if p.Parent then
				tween(p, time * 0.65, { CFrame = (top + out * 0.4 - V3(0, up + 1.5, 0)) * CFrame.Angles(2, 1, 2), Transparency = 1 }, Enum.EasingStyle.Sine)
			end
		end)
		gone(p, time + 0.05)
	end
end
MoveFX.leaves = leaves

-- throw any part (a stave, a lid) with gravity, tumbling, skidding to a stop
-- on the floor, fading out at the end of its life
local function toss(p, vel, spin, life, floorY)
	local t0 = os.clock()
	local pos, turn = p.Position, p.CFrame - p.Position
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		local age = os.clock() - t0
		if age > life or not p.Parent then
			conn:Disconnect()
			p:Destroy()
			return
		end
		vel = vel - V3(0, 45 * dt, 0)
		pos = pos + vel * dt
		if floorY and pos.Y < floorY + 0.25 then
			pos = V3(pos.X, floorY + 0.25, pos.Z)
			vel = V3(vel.X * 0.55, math.abs(vel.Y) * 0.3, vel.Z * 0.55)
			spin = spin * 0.5
		end
		turn = turn * CFrame.Angles(spin.X * dt, spin.Y * dt, spin.Z * dt)
		p.CFrame = CFrame.new(pos) * turn
		if age > life * 0.7 then
			p.Transparency = (age - life * 0.7) / (life * 0.3)
		end
	end)
end

-- a barrel bursting apart (lying across the way you face): its staves flung
-- out all round, its two lids spinning off sideways, splinters and a cloud
-- of sawdust (golden: a gold one)
local function barrelBurst(ctx, at, scale, golden)
	local wood = golden and RGB(254, 174, 52) or RGB(184, 111, 80)
	local dark = golden and RGB(190, 120, 30) or RGB(115, 62, 57)
	local band = golden and RGB(254, 231, 97) or RGB(58, 68, 102)
	local mat = golden and Enum.Material.Neon or Enum.Material.WoodPlanks
	local floorY = floorAt(at)
	local side, fwd = ctx.frame.RightVector, ctx.frame.LookVector
	for i = 1, 10 do
		local a = i / 10 * math.pi * 2
		local out = V3(0, math.cos(a), 0) + fwd * math.sin(a)
		local pos = at + out * 1.1 * scale
		local stave = newPart(V3(0.65, 0.18, 2.3) * scale, CFrame.lookAt(pos, pos + side), i % 3 == 0 and dark or wood, mat)
		toss(stave, out * rnd:NextNumber(9, 15) + V3(0, rnd:NextNumber(6, 12), 0) + side * rnd:NextNumber(-3, 3),
			V3(rnd:NextNumber(-9, 9), rnd:NextNumber(-3, 3), rnd:NextNumber(-9, 9)), 1.3, floorY)
	end
	for _, k in ipairs({ -1, 1 }) do
		local lid = newPart(V3(0.2, 2, 2) * scale, CFrame.new(at + side * (k * 1.2 * scale)) * (ctx.frame - ctx.frame.Position), band,
			Enum.Material.SmoothPlastic, 0, Enum.PartType.Cylinder)
		toss(lid, side * (k * 10) + V3(0, 12, 0), V3(rnd:NextNumber(-6, 6), 0, rnd:NextNumber(-12, 12)), 1.4, floorY)
	end
	bits({ at = at, colors = { wood, dark }, count = 18, speed = { 6, 14 }, up = { 6, 14 }, size = 0.35, life = 0.8, floor = floorY, material = mat })
	puffs(at, RGB(228, 204, 166), 6, 2, 1.5, 0.7, 2)
	ring(V3(at.X, floorY, at.Z), wood, 5 * scale, 0.3, { size = 0.6 })
end

R.ChestPoundFists = {
	Pound = function(ctx)
		local s = ctx.style
		-- left, right, left like a gorilla: each pound a thump off your chest -
		-- a pulse of red air bursting out of it, a puff of grey fur dust, a
		-- little ring of rage
		for i = 0, 2 do
			task.delay(i * 0.11, function()
				local root = ctx.char and ctx.char:FindFirstChild("HumanoidRootPart")
				local cf = (root and root.CFrame or ctx.frame) * CFrame.new(i == 1 and 0.5 or -0.5, 0.6, -0.8)
				local pulse = newPart(V3(0.2, 0.8, 0.8), cf * CFrame.Angles(0, rad(90), 0), i == 1 and s.Light or s.Main, Enum.Material.Neon, 0.2,
					Enum.PartType.Cylinder)
				tween(pulse, 0.22, { Size = V3(0.1, 3.2, 3.2), Transparency = 1, CFrame = cf * CFrame.new(0, 0, -0.8) * CFrame.Angles(0, rad(90), 0) })
				gone(pulse, 0.25)
				puffs(cf.Position, KONGO_FACE, 3, 1, 0.8, 0.4, 0.5)
				ring(cf.Position, s.Light, 3.5, 0.22, { size = 0.45, count = 14, y = cf.Position.Y })
			end)
		end
		sfx(J_THUMP, ctx.frame.Position)
	end,
	Roar = function(ctx)
		local s = ctx.style
		local face = ctx.frame - ctx.frame.Position
		local mouth = ctx.frame * V3(0, 1.6, -0.8)
		-- the roar: shock rings racing out over the floor, rings of air
		-- blasting out of your mouth, leaves torn off and whirled away, and
		-- you flare angry red
		for i = 0, 2 do
			task.delay(i * 0.1, function()
				ring(ctx.feet, i == 1 and s.Light or s.Main, 9 + i * 2, 0.45, { size = 0.9, rise = 2 })
			end)
		end
		for i = 1, 4 do
			task.delay(i * 0.06, function()
				local p = newPart(V3(0.3, 2, 2), CFrame.new(mouth) * face * CFrame.new(0, 0, -i * 1.1) * CFrame.Angles(0, rad(90), 0),
					i % 2 == 0 and s.Light or s.Main, Enum.Material.Neon, 0.45, Enum.PartType.Cylinder)
				tween(p, 0.3, { Size = V3(0.1, 4 + i * 1.5, 4 + i * 1.5), Transparency = 1 })
				gone(p, 0.35)
			end)
		end
		leaves(ctx.frame.Position + V3(0, 3, 0), 16, { out = { 6, 12 }, up = { 2, 5 }, spread = 2.5 })
		afterimage(ctx.char, s.Main, 0.5, 0.4)
		pop(ctx.frame.Position + V3(0, 5, 0), "ROAR!", s.Main, 8, 0.9)
		light(chest(ctx, 0.3), s.Main, 16, 0.5)
		sfx(J_ROAR, ctx.frame.Position)
	end,
}
R.JungleFang = {
	Fang = function(ctx)
		local s = ctx.style
		local at = chest(ctx, 2) + V3(0, 0.5, 0)
		local face = CFrame.new(at) * (ctx.frame - ctx.frame.Position)
		-- a pair of jaws snaps shut in front of you - white fangs top and
		-- bottom biting together - a spray of red, and you glow with the hunger
		local function snap(p, from, to)
			p.CFrame = from
			tween(p, 0.08, { CFrame = to }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(0.2, function()
				if p.Parent then
					tween(p, 0.2, { Transparency = 1 })
				end
			end)
			gone(p, 0.42)
		end
		for _, jaw in ipairs({ 1, -1 }) do
			for i = -1, 1 do
				local h = i == 0 and 1.0 or 1.6 -- (the long fangs at the sides)
				local y = jaw * (1.7 - h / 2)
				snap(newPart(V3(0.45, h, 0.45), face, WHITE, Enum.Material.Neon, 0), face * CFrame.new(i * 0.8, y + jaw * 1.1, 0), face * CFrame.new(i * 0.8, y, 0))
			end
			-- (the gum they're set in)
			snap(newPart(V3(2.4, 0.35, 0.6), face, s.Main, Enum.Material.Neon, 0.15), face * CFrame.new(0, jaw * 2.95, 0.05), face * CFrame.new(0, jaw * 1.85, 0.05))
		end
		task.delay(0.08, function()
			bits({ at = at, colors = { s.Main, s.Glow }, count = 12, speed = { 4, 9 }, up = { 2, 7 }, size = 0.35, life = 0.6, material = Enum.Material.Neon })
			light(at, s.Glow, 12, 0.35)
		end)
		afterimage(ctx.char, s.Glow, 0.4, 0.55)
		sfx(J_FANG, at)
	end,
}
R.VineScythe = {
	Vine = function(ctx)
		-- a vine drops from a branch high up ahead; you grab it with your free
		-- hand and swing forward on it, shaking leaves loose and trailing more
		-- behind you; branch and vine are gone as you let go
		local hand = ctx.char and (ctx.char:FindFirstChild("Left Arm") or ctx.char:FindFirstChild("Right Arm"))
		local anchorP, top = anchorAt(ctx.frame * CFrame.new(0, 16, -6))
		local grip = Instance.new("Attachment")
		grip.Position = V3(0, -1, 0)
		grip.Parent = hand or anchorP
		local vine = beam(top, grip, RGB(62, 137, 72), 0.45)
		vine.CurveSize0, vine.CurveSize1 = 1.5, -1.5
		local branch = { newPart(V3(8, 0.7, 0.7), anchorP.CFrame * CFrame.new(0, 0.4, 0), RGB(115, 62, 57), Enum.Material.WoodPlanks) }
		for i = 1, 8 do
			branch[#branch + 1] = newPart(V3(1.8, 0.3, 1.2), anchorP.CFrame * CFrame.new(rnd:NextNumber(-3.5, 3.5), rnd:NextNumber(0.4, 1.4), rnd:NextNumber(-1.2, 1.2))
				* CFrame.Angles(rnd:NextNumber(-0.4, 0.4), rnd:NextNumber(0, 6), rnd:NextNumber(-0.4, 0.4)), LEAVES[(i - 1) % #LEAVES + 1])
		end
		leaves(anchorP.Position, 6, { out = { 1, 3 }, up = { 0, 1 }, spread = 2, time = 1.4 })
		local t0 = os.clock()
		task.spawn(function()
			while os.clock() - t0 < 0.55 do
				local root = ctx.char and ctx.char:FindFirstChild("HumanoidRootPart")
				if not root then
					break
				end
				leaves(root.Position, 1, { out = { 0.5, 1.5 }, up = { 0, 1 }, spread = 0.6 })
				task.wait(0.06)
			end
		end)
		task.delay(0.6, function()
			grip:Destroy()
			anchorP:Destroy()
			for _, p in ipairs(branch) do
				tween(p, 0.3, { Transparency = 1 })
				gone(p, 0.35)
			end
		end)
		sfx(J_CREAK, ctx.frame.Position)
	end,
	Sweep = function(ctx)
		local s = ctx.style
		sweep(ctx.frame * CFrame.new(0, -0.5, 0), 11, -80, 80, s.Main, 0.35, { width = 2.2, color2 = s.Light })
		-- a whirl of leaves flung off all along the arc
		for i = -4, 4 do
			leaves(ctx.frame * V3(0, 0.5, 0) + (ctx.frame * CFrame.Angles(0, rad(i * 20), 0)).LookVector * 8, 2, { out = { 2, 5 }, up = { 1, 3 }, spread = 0.8 })
		end
		ring(ahead(ctx, 3), s.Main, 8, 0.35, { size = 0.6 })
		sfx(J_SWEEP, ctx.frame.Position)
	end,
}
-- a barrel rolling along the floor from you (the server's own path: Moves'
-- Shot), bursting apart where it stops - in a ball of fire if it's a Burst one
local function rollBarrels(ctx, scale, golden)
	local s = ctx.style
	local shot = ctx.step.Shot
	local n = shot.Count or 1
	for i = 1, n do
		local angle = ((i - 1) - (n - 1) / 2) * (shot.Spread or 0)
		local dirv = (ctx.frame * CFrame.Angles(0, rad(angle), 0)).LookVector
		local start = V3(ctx.frame.Position.X, ctx.feet.Y + 1.1 * scale, ctx.frame.Position.Z) + dirv * 1.5
		local look = CFrame.lookAt(start, start + dirv)
		local model, root = barrelProp(scale, golden, look)
		local time = shot.Range / shot.Speed
		fly(model, root, time, function(u)
			local p = start + dirv * shot.Range * u
			if rnd:NextNumber() < 0.3 then
				puffs(V3(p.X, ctx.feet.Y + 0.4, p.Z), s.Light, 1, 1, 0.6, 0.4, 0.4)
			end
			-- (its axis across the way it rolls, turned as far as it's gone)
			return CFrame.new(p) * (look - look.Position) * CFrame.Angles(-u * shot.Range / (1.1 * scale), 0, 0)
		end, function(pos)
			barrelBurst(ctx, pos, scale, golden)
			if shot.Burst then
				-- KA-BOOM: a ball of fire, black smoke, the blast
				local big = shot.Burst.Radius * 1.4
				local fire = newPart(V3(2, 2, 2), CFrame.new(pos), RGB(247, 118, 34), Enum.Material.Neon, 0, Enum.PartType.Ball)
				local core = newPart(V3(1.2, 1.2, 1.2), CFrame.new(pos), RGB(254, 231, 97), Enum.Material.Neon, 0, Enum.PartType.Ball)
				tween(fire, 0.35, { Size = V3(big, big, big), Transparency = 1 })
				tween(core, 0.25, { Size = V3(big, big, big) * 0.6, Transparency = 1 })
				gone(fire, 0.4)
				gone(core, 0.3)
				slam(ctx, onFloor(pos), shot.Burst.Radius, { RGB(247, 118, 34), RGB(254, 231, 97), s.Main }, { bits = 14, sound = J_BLAST })
				puffs(pos + V3(0, 1, 0), RGB(80, 80, 90), 6, 2.4, 3.5, 1, 2)
				if i == 1 then
					pop(pos + V3(0, 5, 0), "KA-BOOM!", RGB(254, 174, 52), 8, 0.8)
				end
			else
				sfx(J_BURST, pos)
			end
		end)
	end
	sfx(J_RUMBLE, ctx.frame.Position, 1, 0.7)
end
R.BarrelDaggers = {
	Barrel = function(ctx)
		local s = ctx.style
		-- Barrel Roll: a barrel claps shut round you (you're curled up inside)
		-- and rolls along with you, kicking up dust and chips, till it bursts
		local scale = 2.5
		local r = 1.1 * scale
		local model, root = barrelProp(scale, false, CFrame.new(V3(ctx.frame.Position.X, ctx.feet.Y + r, ctx.frame.Position.Z)) * (ctx.frame - ctx.frame.Position))
		ctx.data.barrel = model
		local rolled, last = 0, nil
		local t0 = os.clock()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local hrp = ctx.char and ctx.char:FindFirstChild("HumanoidRootPart")
			if os.clock() - t0 > 0.75 or not hrp or not model.Parent then
				conn:Disconnect()
				model:Destroy()
				return
			end
			local look = hrp.CFrame.LookVector
			local f = V3(look.X, 0, look.Z).Magnitude > 0.01 and V3(look.X, 0, look.Z).Unit or V3(0, 0, -1)
			local pos = V3(hrp.Position.X, floorAt(hrp.Position) + r, hrp.Position.Z)
			if last then
				rolled += (pos - last).Magnitude
			end
			last = pos
			-- (its axis across you, turned as far as it's rolled)
			root.CFrame = CFrame.lookAt(pos, pos + f) * CFrame.Angles(-rolled / r, 0, 0)
			if rnd:NextNumber() < 0.4 then
				puffs(pos - f * r + V3(0, 0.4 - r, 0), s.Light, 1, 1.2, 0.8, 0.45, 0.5)
			end
			if rnd:NextNumber() < 0.25 then
				bits({ at = pos + V3(0, 0.3 - r, 0), colors = { s.Main, s.Dark }, count = 1, speed = { 2, 5 }, up = { 3, 6 }, size = 0.3, life = 0.5,
					material = Enum.Material.WoodPlanks, dir = -f, spread = 0.8 })
			end
		end)
		ring(ctx.feet, s.Light, 4, 0.25, { size = 0.5, count = 14 })
		sfx(J_CURL, ctx.frame.Position)
		task.delay(0.06, function()
			sfx(J_RUMBLE, ctx.frame.Position)
		end)
	end,
	Burst = function(ctx)
		local s = ctx.style
		local model = ctx.data.barrel
		local at = model and model.PrimaryPart and model.PrimaryPart.Position or ctx.frame.Position
		if model then
			model:Destroy()
			ctx.data.barrel = nil
		end
		-- and it bursts apart round you: staves, lids, splinters, sawdust
		barrelBurst(ctx, at, 2.5, false)
		local floorY = floorAt(at)
		slam(ctx, V3(at.X, floorY, at.Z), 6, { s.Light, s.Main, s.Glow }, { bits = 10, material = Enum.Material.WoodPlanks, sound = J_BURST,
			dust = RGB(228, 204, 166) })
		pop(at + V3(0, 5, 0), "CRASH!", s.Glow, 7, 0.7)
	end,
}
R.BarrelHammer = {
	Bat = function(ctx)
		local s = ctx.style
		local golden = ctx.player and (ctx.player:GetAttribute("Mastery") or 1) >= 100
		-- BONK: two barrels batted away, rolling off, each bursting in a ball
		-- of fire
		rollBarrels(ctx, golden and 1.8 or 1.3, golden)
		local at = ahead(ctx, 1.8) + V3(0, 1.5, 0)
		ring(ahead(ctx, 1.5), s.Light, 4, 0.25, { size = 0.5, count = 14 })
		bits({ at = at, colors = { s.Main, s.Light, s.Dark }, count = 10, speed = { 6, 12 }, up = { 3, 8 }, size = 0.35, life = 0.6,
			material = Enum.Material.WoodPlanks, dir = ctx.frame.LookVector, spread = 0.9 })
		glint(ctx, at, WHITE, { 0, 90, 45, -45 }, 3, 0.2)
		pop(at + V3(0, 3, 0), "BONK!", s.Glow, 7, 0.6)
		sfx(J_BAT, at)
	end,
}
R.KongsCrown = {
	Call = function(ctx)
		local s = ctx.style
		-- calling Kongo: a pillar of gold, jungle drums booming out in rings,
		-- and a ring of gold closing in on the spot his fist will land
		column(ctx.feet, s.Light, 22, 2, 0.6)
		for i = 0, 2 do
			task.delay(i * 0.13, function()
				ring(ctx.feet, i % 2 == 0 and s.Main or s.Light, 6 + i * 2, 0.35, { size = 0.7 })
				light(ctx.frame.Position + V3(0, 2, 0), s.Light, 12, 0.15)
			end)
		end
		if ctx.point then
			ring(onFloor(ctx.point), s.Light, 1, 0.6, { size = 0.6, r0 = 12, count = 24 })
		end
		pop(ctx.frame.Position + V3(0, 5, 0), "KONG!", s.Light, 8, 0.8)
		light(ctx.frame.Position, s.Light, 16, 0.6)
		sfx(J_CALL, ctx.frame.Position)
	end,
	SkyFist = function(ctx)
		local s = ctx.style
		local target = onFloor(ctx.point or ahead(ctx, 10))
		-- its shadow grows on the floor as it falls out of the sky, streaking;
		-- it lands on the hit (0.75 s), stays planted a moment, then Kongo
		-- pulls it back up
		local shadow = newPart(V3(0.1, 2, 2), CFrame.new(target + V3(0, 0.08, 0)) * CFrame.Angles(0, 0, rad(90)), INK, Enum.Material.SmoothPlastic, 0.6,
			Enum.PartType.Cylinder)
		tween(shadow, 0.75, { Size = V3(0.1, 22, 22), Transparency = 0.35 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		gone(shadow, 1)
		local model, root = fistProp(CFrame.new(target + V3(0, 60, 0)) * CFrame.Angles(0, rad(25), 0))
		local t0 = os.clock()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local t = os.clock() - t0
			if t > 1.5 or not root.Parent then
				conn:Disconnect()
				model:Destroy()
				return
			end
			local u = math.clamp(t / 0.75, 0, 1)
			local y = 60 - 55.5 * (u * u)
			if t > 1.05 then
				y = 4.5 + ((t - 1.05) / 0.45) ^ 2 * 50
			end
			root.CFrame = CFrame.new(target + V3(0, y, 0)) * CFrame.Angles(0, rad(25), 0)
			if u < 1 and rnd:NextNumber() < 0.8 then
				local p = newPart(V3(0.4, 6, 0.4), CFrame.new(target + V3(rnd:NextNumber(-4, 4), y + 9, rnd:NextNumber(-4, 4))),
					rnd:NextNumber() < 0.5 and s.Light or WHITE, Enum.Material.Neon, 0.2)
				tween(p, 0.25, { Size = V3(0.1, 9, 0.1), Transparency = 1 })
				gone(p, 0.3)
			end
		end)
		sfx(J_SKY, target)
	end,
	Impact = function(ctx)
		local s = ctx.style
		local at = onFloor(ctx.point or ahead(ctx, 10))
		slam(ctx, at, 12, { s.Light, s.Main, KONGO_FACE }, { bits = 30, size = 0.9, material = Enum.Material.Slate, sound = J_SMASH,
			dust = RGB(170, 160, 150) })
		-- rocks thrown up round the crater, cracks splitting the floor out
		-- from it, and the whole jungle shaken: leaves raining down
		bits({ at = at + V3(0, 1, 0), colors = { RGB(120, 118, 110), RGB(84, 82, 78) }, count = 14, speed = { 6, 14 }, up = { 12, 22 }, size = 1.2,
			life = 1.2, floor = at.Y, material = Enum.Material.Slate, bounce = true })
		for i = 1, 9 do
			local a = i / 9 * math.pi * 2 + rnd:NextNumber(-0.2, 0.2)
			local len = rnd:NextNumber(5, 10)
			local d = V3(math.cos(a), 0, math.sin(a))
			local crack = newPart(V3(0.5, 0.08, len), CFrame.lookAt(at + d * (3 + len / 2) + V3(0, 0.06, 0), at + d * (3 + len) + V3(0, 0.06, 0)), INK,
				Enum.Material.SmoothPlastic, 0.1)
			task.delay(1.2, function()
				tween(crack, 0.6, { Transparency = 1 })
			end)
			gone(crack, 1.85)
		end
		task.delay(0.15, function()
			leaves(at + V3(0, 12, 0), 18, { out = { 1, 4 }, up = { 0, 1 }, spread = 8, time = 1.5 })
		end)
		pop(at + V3(0, 8, 0), "SMASH!", s.Light, 10, 1)
		if nearMe(at, 40) then
			screenFlash(WHITE, 0.25, 0.25)
		end
	end,
}

-- 9. CANVAS -----------------------------------------------------------
-- (each sound a list: its own, then what plays till it's uploaded)
local C_SQUEAK = { "Eraser Squeak", "Eraser Rub", "Punch 2" }
local C_POOF = { "Erase Poof", "Undo Rewind", "Punch 3" }
local C_SHARPEN = { "Pencil Sharpen", "Pencil Scratch", "Punch 2" }
local C_SPLOSH = { "Ink Splosh", "Paint Splash", "Cube Slam" }
local C_DOODLE = { "Doodle Pop", "Paper Crumple", "Portal Whoosh" }
local C_SCRIBBLE = { "Scribble Slash", "Pencil Scratch", "Portal Whoosh" }
local C_REDRAW = { "Redraw Swish", "Undo Rewind", "Portal Whoosh" }
local C_COPY = { "Copy Click", "Mouse Click", "Orb Land" }
local C_PASTE = { "Paste Pop", "Copy Paste", "Orb Land" }
local C_BUZZ = { "Glitch Buzz", "Delete Warning", "Lag Glitch", "Gridlock Stun", "Portal Whoosh" }
local C_SHATTER = { "Delete Shatter", "Gridlock Shatter", "Cube Slam" }
local CYAN = RGB(44, 232, 245)

-- ink splats: flat squares of ink scattered over the floor, fading
local function splats(at, color, radius, count, time)
	local y = floorAt(at) + 0.06
	for _ = 1, count do
		local a, r = rnd:NextNumber(0, math.pi * 2), rnd:NextNumber(0, radius)
		local size = rnd:NextNumber(0.6, 2.2)
		local p = newPart(V3(size, 0.08, size), CFrame.new(at.X + math.cos(a) * r, y, at.Z + math.sin(a) * r) * CFrame.Angles(0, rnd:NextNumber(0, 3), 0),
			color, Enum.Material.SmoothPlastic, 0)
		task.delay(time * 0.6, function()
			tween(p, time * 0.4, { Transparency = 1 })
		end)
		gone(p, time + 0.05)
	end
end
MoveFX.splats = splats
-- a scribble: a zigzag of pencil strokes from a to b, each corner pushed
-- `across` one way then the other, fading
local function scribble(a, b, color, across, time)
	local n = math.max(4, math.floor((b - a).Magnitude / 1.2))
	local prev = a
	for i = 1, n do
		local p = a:Lerp(b, i / n) + across * (i % 2 == 0 and 1 or -1)
		streak(prev, p, color, 0.16, time, { thick = 0.16, material = Enum.Material.SmoothPlastic, transparency = 0 })
		prev = p
	end
end
-- a selection box drawn in marching ants: every edge dashed in two colours
-- that swap as the ants march (square to the world, like wireBox)
local function antsBox(at, size, a, b, time)
	local model = Instance.new("Model")
	model.Parent = fxFolder()
	local h = size / 2
	local dashes = {}
	local function edge(p0, p1)
		local d = p1 - p0
		local n = math.max(2, math.floor(d.Magnitude / 0.8))
		for i = 1, n do
			local len = d.Magnitude / n
			local dash = newPart(V3(d.X ~= 0 and len or 0.22, d.Y ~= 0 and len or 0.22, d.Z ~= 0 and len or 0.22), CFrame.new(p0:Lerp(p1, (i - 0.5) / n)),
				#dashes % 2 == 0 and a or b, Enum.Material.Neon, 0)
			dash.Parent = model
			table.insert(dashes, dash)
		end
	end
	for _, y in ipairs({ -h.Y, h.Y }) do
		for _, z in ipairs({ -h.Z, h.Z }) do
			edge(at + V3(-h.X, y, z), at + V3(h.X, y, z))
		end
		for _, x in ipairs({ -h.X, h.X }) do
			edge(at + V3(x, y, -h.Z), at + V3(x, y, h.Z))
		end
	end
	for _, x in ipairs({ -h.X, h.X }) do
		for _, z in ipairs({ -h.Z, h.Z }) do
			edge(at + V3(x, -h.Y, z), at + V3(x, h.Y, z))
		end
	end
	task.spawn(function()
		local flip = false
		while model.Parent do
			flip = not flip
			for k, dash in ipairs(dashes) do
				dash.Color = ((k % 2 == 0) ~= flip) and a or b
			end
			task.wait(0.1)
		end
	end)
	gone(model, time)
	return model
end
-- a doodle of a character: white, outlined in ink (a Highlight), at a spot
local function doodle(char, color, outline, time)
	if not char then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Doodle"
	for _, name in ipairs(BODY) do
		local part = char:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			local p = newPart(part.Size, part.CFrame, color, Enum.Material.SmoothPlastic, 0.05)
			p.Name = name
			p.Parent = model
		end
	end
	model.Parent = fxFolder()
	local hl = Instance.new("Highlight")
	hl.FillTransparency = 1
	hl.OutlineColor = outline
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Parent = model
	gone(model, time)
	return model
end
-- a giant DEL key off a keyboard: a dark keycap, DEL on top in white pixels
-- (read from behind it, the way it faces)
local DEL = { "XX. XXX X..", "X.X X.. X..", "X.X XX. X..", "X.X X.. X..", "XX. XXX XXX" }
local function keyProp(at)
	return prop(function(add)
		add(V3(7, 2.2, 7), CFrame.new(), RGB(38, 43, 68))
		add(V3(6, 0.8, 6), CFrame.new(0, 1.4, 0), RGB(58, 68, 102))
		for row, line in ipairs(DEL) do
			for col = 1, #line do
				if string.sub(line, col, col) == "X" then
					add(V3(0.42, 0.2, 0.42), CFrame.new((col - 6) * 0.45, 1.9, (row - 3) * 0.45), WHITE, Enum.Material.Neon)
				end
			end
		end
	end, at)
end
R.EraserHammer = {
	Rub = function(ctx)
		local s = ctx.style
		local at = ahead(ctx, 2.8) + V3(0, 0.5, 0)
		-- rubbing out a mistake on the floor in front of you: white strokes
		-- scrubbed back and forth where the eraser goes, crumbs of pink
		-- rubber, and a sparkle off it - your next hit erases
		local y = ctx.feet.Y + 0.07
		for i = 0, 3 do
			task.delay(i * 0.05, function()
				local side = i % 2 == 0 and 1 or -1
				local a = ctx.frame * V3(-side * 1.6, 0, -2.4 - i * 0.3)
				local b = ctx.frame * V3(side * 1.6, 0, -2.6 - i * 0.3)
				streak(V3(a.X, y, a.Z), V3(b.X, y, b.Z), WHITE, 0.55, 0.6, { thick = 0.06 })
			end)
		end
		puffs(at, s.Light, 6, 1, 1, 0.6, 1)
		bits({ at = at, colors = { s.Main, s.Light, s.Dark }, count = 14, speed = { 2, 6 }, up = { 2, 6 }, size = 0.3, life = 0.9, gravity = 25,
			floor = ctx.feet.Y })
		task.delay(0.25, function()
			glint(ctx, ctx.frame * V3(0.6, 2.2, -1.8), WHITE, { 0, 90, 45, -45 }, 2.4, 0.3)
		end)
		sfx(C_SQUEAK, at)
	end,
}
R.PencilSword = {
	Sharpen = function(ctx)
		local s = ctx.style
		local at = chest(ctx, 1.2) + V3(0, 1, 0)
		-- sharpened: pencil shavings curl out in a spiral (wood with a frill
		-- of yellow paint), a puff of graphite, and the new point glints
		for i = 1, 12 do
			task.delay(i * 0.02, function()
				local turn = CFrame.new(at) * CFrame.Angles(0, i * 0.9, 0)
				local p = newPart(V3(0.6, 0.06, 0.4), turn * CFrame.new(0, 0, -0.6), i % 3 == 0 and RGB(254, 174, 52) or RGB(228, 166, 114))
				tween(p, 0.6, { CFrame = turn * CFrame.new(0, -0.6, -2.6) * CFrame.Angles(2, 3, 1), Transparency = 1 })
				gone(p, 0.65)
			end)
		end
		bits({ at = at, colors = { RGB(228, 166, 114), RGB(254, 174, 52), RGB(90, 90, 100) }, count = 10, speed = { 4, 9 }, up = { 4, 9 }, size = 0.35,
			life = 0.9, gravity = 30, floor = ctx.feet.Y })
		puffs(at, RGB(120, 120, 130), 3, 0.8, 0.8, 0.5, 0.5)
		task.delay(0.15, function()
			glint(ctx, ctx.frame * V3(0.4, 1.9, -3.2), s.Light, { 0, 90, 45, -45 }, 2.6, 0.3)
		end)
		ring(ctx.feet, s.Light, 6, 0.3, { size = 0.5 })
		sfx(C_SHARPEN, at)
	end,
}
R.InkFists = {
	Splash = function(ctx)
		local s = ctx.style
		local at = ahead(ctx, stepAhead(ctx))
		slam(ctx, at, 10, { s.Light, s.Main, s.Dark }, { bits = 20, dust = RGB(200, 200, 215), sound = C_SPLOSH })
		-- a crown of ink splashing up round your fists and raining back down
		for i = 1, 14 do
			local a = i / 14 * math.pi * 2
			local d = V3(math.cos(a), 0, math.sin(a))
			local top = at + d * 3.4 + V3(0, 2.5 + i % 3, 0)
			local p = newPart(V3(0.7, 0.7, 0.7), CFrame.new(at + d * 1.5 + V3(0, 0.4, 0)), i % 2 == 0 and s.Light or s.Dark, Enum.Material.SmoothPlastic, 0,
				Enum.PartType.Ball)
			tween(p, 0.22, { CFrame = CFrame.new(top), Size = V3(0.6, 1.5, 0.6) })
			task.delay(0.22, function()
				if p.Parent then
					tween(p, 0.28, { CFrame = CFrame.new(V3(top.X, at.Y + 0.2, top.Z) + d * 1.2), Size = V3(0.9, 0.3, 0.9) }, Enum.EasingStyle.Quad,
						Enum.EasingDirection.In)
				end
			end)
			gone(p, 0.52)
		end
		splats(at, s.Main, 9, 22, 3)
		splats(at, s.Light, 7, 8, 2.4)
		task.delay(0.5, function()
			splats(at, s.Light, 5.5, 10, 2)
		end)
		pop(at + V3(0, 5, 0), "SPLOSH!", s.Light, 7, 0.8)
	end,
}
R.DoodleKatana = {
	Doodle = function(ctx)
		local s = ctx.style
		-- a doodle of you is sketched where you stand (white, inked round),
		-- pencil scribbles down both sides of it
		ctx.data.doodle = doodle(ctx.char, WHITE, INK, 1.6)
		local right = ctx.frame.RightVector
		for _, side in ipairs({ -1.6, 1.6 }) do
			scribble(ctx.frame * V3(side, -2.6, 0), ctx.frame * V3(side, 2.2, 0), s.Light, right * 0.3, 0.5)
		end
		pop(ctx.frame.Position + V3(0, 4, 0), "DOODLE!", s.Light, 6, 0.7)
		sfx(C_DOODLE, ctx.frame.Position)
	end,
	Slash = function(ctx)
		local s = ctx.style
		local a = ctx.marks.Start or ctx.frame.Position
		local b = ctx.frame.Position
		local y = ctx.feet.Y + 2.5
		streak(V3(a.X, y, a.Z), V3(b.X, y, b.Z), s.Light, 1, 0.4)
		streak(V3(a.X, y, a.Z), V3(b.X, y, b.Z), INK, 0.3, 0.5)
		-- and a scribble of pencil all along the cut
		scribble(V3(a.X, y, a.Z), V3(b.X, y, b.Z), INK, V3(0, 0.45, 0), 0.6)
		sfx(C_SCRIBBLE, b)
	end,
	Redraw = function(ctx)
		local s = ctx.style
		local model = ctx.data.doodle
		local a = ctx.marks.Start or ctx.frame.Position
		local b = ctx.marks.End or ctx.frame.Position
		if model and model.Parent then
			-- the doodle dashes the same way you did, scribbling as it goes
			local parts = model:GetChildren()
			local base = {}
			for _, p in ipairs(parts) do
				if p:IsA("BasePart") then
					base[p] = p.CFrame
				end
			end
			local d = V3(b.X - a.X, 0, b.Z - a.Z)
			local t0 = os.clock()
			local conn
			conn = RunService.Heartbeat:Connect(function()
				local u = math.clamp((os.clock() - t0) / 0.2, 0, 1)
				for p, cf in pairs(base) do
					if p.Parent then
						p.CFrame = cf + d * u
					end
				end
				if u >= 1 then
					conn:Disconnect()
				end
			end)
		end
		local y = ctx.feet.Y + 2.5
		streak(V3(a.X, y, a.Z), V3(b.X, y, b.Z), s.Light, 1.4, 0.45)
		scribble(V3(a.X, y, a.Z), V3(b.X, y, b.Z), s.Light, V3(0, 0.5, 0), 0.6)
		for i = 1, 6 do
			local p = a:Lerp(b, i / 6)
			bits({ at = V3(p.X, y, p.Z), colors = { s.Light, INK }, count = 3, speed = { 2, 5 }, up = { 2, 5 }, size = 0.3, life = 0.5 })
		end
		sfx(C_REDRAW, b)
	end,
}
R.CopyPasteScythe = {
	Copy = function(ctx)
		local s = ctx.style
		local at = ctx.frame.Position
		local char = ctx.char
		-- CTRL+C: you're selected (marching ants round you) and copied...
		antsBox(at, V3(4.5, 6, 4.5), WHITE, s.Light, 0.6)
		pop(at + V3(0, 4.5, 0), "CTRL+C", s.Light, 6, 0.7)
		sfx(C_COPY, at)
		-- ... CTRL+V: two ink copies of you pop out in a burst of pixels, one
		-- each side, doing what you do for 5 s, then blink out
		task.delay(0.35, function()
			pop(at + V3(0, 4.5, 0), "CTRL+V", s.Light, 6, 0.7)
			sfx(C_PASTE, at)
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if not root then
				return
			end
			local copies = {}
			for _, side in ipairs({ -5, 5 }) do
				local m = Instance.new("Model")
				for _, name in ipairs(BODY) do
					local part = char:FindFirstChild(name)
					if part and part:IsA("BasePart") then
						local p = newPart(part.Size, part.CFrame + root.CFrame.RightVector * side, s.Light, Enum.Material.Neon, 0.55)
						p.Name = name
						p.Parent = m
					end
				end
				m.Parent = fxFolder()
				copies[#copies + 1] = { m = m, side = side }
				bits({ at = root.Position + root.CFrame.RightVector * side, colors = { s.Light, WHITE, CYAN }, count = 10, speed = { 3, 8 }, up = { 3, 8 },
					size = 0.4, life = 0.5, material = Enum.Material.Neon })
			end
			local t0 = os.clock()
			local conn
			conn = RunService.Heartbeat:Connect(function()
				local r = char:FindFirstChild("HumanoidRootPart")
				if os.clock() - t0 > 4.85 or not r then
					conn:Disconnect()
					for _, c in ipairs(copies) do
						local torso = c.m:FindFirstChild("Torso")
						if torso then
							bits({ at = torso.Position, colors = { s.Light, WHITE, CYAN }, count = 8, speed = { 2, 6 }, up = { 2, 6 }, size = 0.35, life = 0.4,
								material = Enum.Material.Neon })
						end
						c.m:Destroy()
					end
					return
				end
				for _, c in ipairs(copies) do
					local shift = r.CFrame.RightVector * c.side
					for _, p in ipairs(c.m:GetChildren()) do
						local src = char:FindFirstChild(p.Name)
						if src then
							p.CFrame = src.CFrame + shift
						end
					end
				end
			end)
		end)
	end,
}
R.DeleteKey = {
	Glitch = function(ctx)
		local s = ctx.style
		local at = ctx.point and onFloor(ctx.point) or ahead(ctx, 8)
		-- they're selected (a box of red-and-white marching ants), DELETE? -
		-- and a giant DEL key falls out of the sky onto them, glitching as it
		-- comes (it lands on the hit)
		antsBox(at + V3(0, 3.5, 0), V3(8, 7, 8), s.Main, WHITE, 0.8)
		pop(at + V3(0, 8.5, 0), "DELETE?", s.Main, 9, 0.8)
		local face = ctx.frame - ctx.frame.Position
		local model, root = keyProp(CFrame.new(at + V3(0, 59.1, 0)) * face)
		ctx.data.key = model
		-- (it lands just before the hit, 0.7 s into the move - timed from the
		-- move's start, as this step only comes once the server's picked the
		-- spot - falling the last 0.4 s, jittering; the hit clicks it down)
		local landAt = (ctx.started or os.clock()) + 0.7
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local now = os.clock()
			if now > landAt + 0.7 or not root.Parent then
				conn:Disconnect()
				model:Destroy()
				return
			end
			local u = ctx.data.keyDown and 1 or math.clamp(1 - (landAt - now) / 0.4, 0, 1)
			local jitter = (u > 0 and u < 1) and V3(rnd:NextNumber(-0.4, 0.4), 0, rnd:NextNumber(-0.4, 0.4)) or V3(0, 0, 0)
			root.CFrame = CFrame.new(at + V3(0, 1.1 + 58 * (1 - u * u) - (ctx.data.keyDown and 0.6 or 0), 0) + jitter) * face
		end)
		if ctx.own or nearMe(at, 35) then
			-- the screen glitches: bars of colour flicker across it
			local me = Players.LocalPlayer
			local gui = me and me:FindFirstChildOfClass("PlayerGui")
			if gui then
				local sg = Instance.new("ScreenGui")
				sg.Name = "MoveFXGlitch"
				sg.IgnoreGuiInset = true
				sg.DisplayOrder = 50
				sg.ResetOnSpawn = false
				sg.Parent = gui
				task.spawn(function()
					for _ = 1, 12 do
						for _, c in ipairs(sg:GetChildren()) do
							c:Destroy()
						end
						for _ = 1, 5 do
							local f = Instance.new("Frame")
							f.BorderSizePixel = 0
							f.BackgroundColor3 = ({ s.Main, CYAN, WHITE, INK })[rnd:NextInteger(1, 4)]
							f.BackgroundTransparency = rnd:NextNumber(0.35, 0.7)
							f.Size = UDim2.new(1, 0, rnd:NextNumber(0.01, 0.06), 0)
							f.Position = UDim2.new(rnd:NextNumber(-0.05, 0.05), 0, rnd:NextNumber(0, 1), 0)
							f.Parent = sg
						end
						task.wait(0.05)
					end
					sg:Destroy()
				end)
			end
		end
		sfx(C_BUZZ, at)
	end,
	Delete = function(ctx)
		local s = ctx.style
		local at = ctx.point and onFloor(ctx.point) or ahead(ctx, 8)
		-- the key clicks down and everything round it shatters into pixels -
		-- the key too - a ring of red and cyan glitch bars racing out
		local model = ctx.data.key
		if model and model.Parent then
			ctx.data.keyDown = true
			task.delay(0.08, function()
				model:Destroy()
				bits({ at = at + V3(0, 1.5, 0), colors = { RGB(38, 43, 68), RGB(58, 68, 102), WHITE }, count = 18, speed = { 6, 14 }, up = { 6, 14 },
					size = 0.7, life = 1, floor = at.Y })
			end)
			ctx.data.key = nil
		end
		slam(ctx, at, 8, { s.Main, WHITE, INK }, { bits = 10, sound = C_SHATTER })
		bits({ at = at + V3(0, 3, 0), colors = { s.Main, WHITE, CYAN, INK }, count = 36, speed = { 8, 20 }, up = { 4, 18 }, size = 0.55,
			life = 1.1, gravity = 30, material = Enum.Material.Neon })
		for i = 1, 16 do
			local a = i / 16 * math.pi * 2
			local d = V3(math.cos(a), 0, math.sin(a))
			local bar = newPart(V3(0.3, 0.3, 1.6), CFrame.lookAt(at + d * 2 + V3(0, 0.5, 0), at + d * 3 + V3(0, 0.5, 0)), i % 2 == 0 and s.Main or CYAN,
				Enum.Material.Neon, 0)
			tween(bar, 0.35, { CFrame = bar.CFrame + d * 9, Transparency = 1 })
			gone(bar, 0.4)
		end
		pop(at + V3(0, 8, 0), "DELETED", s.Main, 10, 1)
		if ctx.own or nearMe(at, 35) then
			screenFlash(s.Main, 0.3, 0.25)
		end
	end,
}

----------------------------------------------------------------------
-- Building blocks' moments (the server tells every screen): a stack
-- bursting, a next hit landing, a crit, a lifesteal, a special's hit
----------------------------------------------------------------------
local SPECIALS = {}
MoveFX.SPECIALS = SPECIALS

SPECIALS.Stacks = function(ctx)
	local s = ctx.style
	slam(ctx, onFloor(ctx.point), 5, { s.Main, s.Light, s.Glow }, { bits = 14, sound = { "Orb Land", "Punch 4" } })
	pop(ctx.point + V3(0, 3, 0), "SPLAT!", s.Light, 6, 0.7)
end
SPECIALS.NextHit = function(ctx)
	local s = ctx.style
	local at = onFloor(ctx.point)
	if ctx.id == "EraserHammer" then
		-- erased: a puff of rubber and white squares where the armour was
		puffs(ctx.point, s.Light, 8, 1.6, 1.5, 0.8, 1.5)
		bits({ at = ctx.point, colors = { WHITE, s.Main }, count = 16, speed = { 4, 10 }, up = { 4, 10 }, size = 0.5, life = 0.9, material = Enum.Material.Neon })
		-- (and a white patch where it was rubbed out, shrinking away)
		local patch = newPart(V3(2.6, 2.6, 0.2), CFrame.new(ctx.point), WHITE, Enum.Material.Neon, 0.2)
		tween(patch, 0.4, { Size = V3(0.2, 0.2, 0.2), Transparency = 1 })
		gone(patch, 0.45)
		pop(ctx.point + V3(0, 3, 0), "ERASED!", s.Main, 7, 0.8)
		sfx(C_POOF, ctx.point)
	elseif ctx.id == "ShovelHammer" then
		slam(ctx, at, 6, { s.Main, s.Dark, s.Light }, { bits = 20, material = Enum.Material.Slate, dust = s.Light })
		pop(ctx.point + V3(0, 3, 0), "DIG!", s.Glow, 6, 0.7)
	else
		slam(ctx, at, 5, { s.Glow, s.Main, WHITE }, { bits = 12 })
	end
end
SPECIALS.Crit = function(ctx)
	local s = ctx.style
	if ctx.id == "RelicDaggers" then
		-- treasure: gold coins popping out
		bits({ at = ctx.point, colors = { RGB(254, 174, 52), RGB(254, 231, 97) }, count = 10, speed = { 4, 9 }, up = { 8, 14 }, size = 0.45, life = 0.9,
			material = Enum.Material.Neon, shape = Enum.PartType.Cylinder, floor = floorAt(ctx.point), bounce = true })
		sfx(K_COIN, ctx.point, 1.1, 0.6)
	else
		bits({ at = ctx.point, colors = { s.Glow, WHITE }, count = 8, speed = { 5, 10 }, up = { 4, 9 }, size = 0.35, life = 0.6, material = Enum.Material.Neon })
	end
end
SPECIALS.Lifesteal = function(ctx)
	local s = ctx.style
	local root = ctx.char and ctx.char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	-- a red orb floats from them back to you
	local orb = newPart(V3(0.7, 0.7, 0.7), CFrame.new(ctx.point), s.Glow, Enum.Material.Neon, 0, Enum.PartType.Ball)
	local from = ctx.point
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local u = math.clamp((os.clock() - t0) / 0.4, 0, 1)
		if not root.Parent then
			conn:Disconnect()
			orb:Destroy()
			return
		end
		orb.CFrame = CFrame.new(from:Lerp(root.Position, u * u) + V3(0, math.sin(u * math.pi) * 2, 0))
		if u >= 1 then
			conn:Disconnect()
			orb:Destroy()
			light(root.Position, s.Glow, 8, 0.25)
		end
	end)
end
SPECIALS.ChopWave = function(ctx)
	local s = ctx.style
	local at = onFloor(ctx.point)
	ring(at, s.Light, 6, 0.3, { size = 0.6, count = 16 })
	disc(at, s.Main, 5, 0.25)
	bits({ at = at + V3(0, 0.5, 0), colors = { s.Light, s.Main }, count = 6, speed = { 4, 8 }, up = { 4, 8 }, size = 0.35, life = 0.5, material = Enum.Material.Neon })
end
SPECIALS.Clones = function(ctx)
	local s = ctx.style
	local root = ctx.char and ctx.char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local frame = CFrame.lookAt(root.Position, root.Position + V3(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z))
	for _, side in ipairs({ -5, 5 }) do
		sweep(frame * CFrame.new(side, -0.5, 0), 7, -60, 60, s.Light, 0.3, { width = 1.2, count = 8, draw = 0.08 })
	end
end
SPECIALS.DashHit = function(ctx)
	local s = ctx.style
	local a = typeof(ctx.extra) == "Vector3" and ctx.extra or ctx.point
	local b = ctx.point
	local y = floorAt(b) + 2.5
	streak(V3(a.X, y, a.Z), V3(b.X, y, b.Z), s.Glow, 1.2, 0.35)
	streak(V3(a.X, y, a.Z), V3(b.X, y, b.Z), WHITE, 0.4, 0.2)
	bits({ at = V3(b.X, y, b.Z), colors = { WHITE, INK }, count = 8, speed = { 5, 10 }, up = { 4, 9 }, size = 0.5, life = 0.7 })
end

----------------------------------------------------------------------
-- Running a move's effects, in time with it
----------------------------------------------------------------------
local live = {} -- [player] = the move they're doing now: { id, count, marks, data }

local function makeCtx(player, inst, step, style)
	local char = player and player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local look = root.CFrame.LookVector
	local f = V3(look.X, 0, look.Z)
	f = f.Magnitude > 0.01 and f.Unit or V3(0, 0, -1)
	local frame = CFrame.lookAt(root.Position, root.Position + f)
	return {
		player = player, char = char, root = root, frame = frame, feet = onFloor(root.Position),
		style = style, step = step, own = inst.own, id = inst.id,
		marks = inst.marks, data = inst.data, point = inst.marks.T, started = inst.t0,
	}
end

local function run(id, name, ctx)
	local book = R[id]
	local fn = book and book[name]
	if not fn then
		return
	end
	local ok, err = pcall(fn, ctx)
	if not ok then
		warn("[MoveFX] " .. tostring(id) .. "." .. tostring(name) .. ": " .. tostring(err))
	end
end

-- a move starting: its effects play at their steps' times (own: it's yours,
-- started the moment you pressed - the server's word for it is ignored)
function MoveFX.begin(player, id, count, own)
	local move = Moves.of(id)
	if not move then
		return
	end
	local inst = { id = id, count = count, marks = {}, data = {}, own = own, t0 = os.clock(), fired = {} }
	live[player] = inst
	local style = styleOf(move.Style)
	for i, step in ipairs(move.Steps or {}) do
		if step.Mark or (step.Fx and not step.Pick) or (step.Shake and not step.Pick) then
			task.delay(step.At or 0, function()
				if live[player] ~= inst or inst.fired[i] then
					return -- (a newer one's started; or a Contact step already went off)
				end
				inst.fired[i] = true
				local ctx = makeCtx(player, inst, step, style)
				if not ctx then
					return
				end
				if step.Mark then
					inst.marks[step.Mark] = ctx.frame.Position
				end
				if step.Fx and not step.Pick then
					run(id, step.Fx, ctx)
				end
				if step.Shake and not step.Pick then
					shake(ctx.frame.Position, step.Shake)
				end
			end)
		end
	end
end

-- the server says: step 0 = someone's move started; a number = a step that
-- picked a spot (point); a name = a building block's moment at point
function MoveFX.told(player, id, count, step, point, extra)
	local move = Moves.of(id)
	local style = styleOf(move and move.Style)
	if step == 0 then
		if player ~= Players.LocalPlayer then
			MoveFX.begin(player, id, count, false)
		end
		return
	end
	if type(step) == "number" then
		local inst = live[player]
		local s = move and move.Steps and move.Steps[step]
		if not (inst and s and inst.id == id) then
			return
		end
		-- (a Contact step - it ran into an enemy: now, once)
		if s.Contact then
			if inst.fired[step] then
				return
			end
			inst.fired[step] = true
			if player == Players.LocalPlayer and MoveFX.onContact then
				pcall(MoveFX.onContact) -- (your screen stops your dash there)
			end
		end
		if typeof(point) == "Vector3" and s.Pick then
			inst.marks[s.Pick] = point
		end
		local ctx = makeCtx(player, inst, s, style)
		if not ctx then
			return
		end
		ctx.point = typeof(point) == "Vector3" and point or ctx.point
		if s.Fx then
			run(id, s.Fx, ctx)
		end
		if s.Shake then
			shake(ctx.point or ctx.frame.Position, s.Shake)
		end
		return
	end
	local fn = SPECIALS[step]
	if fn and typeof(point) == "Vector3" then
		local char = player and player.Character
		local ok, err = pcall(fn, { player = player, char = char, id = id, style = style, point = point, extra = extra })
		if not ok then
			warn("[MoveFX] " .. tostring(step) .. ": " .. tostring(err))
		end
	end
end

----------------------------------------------------------------------
-- AURAS: while a building block lasts, the player gives off their style's
-- bits (AbilityFX calls this every frame while their Aura is on)
----------------------------------------------------------------------
local auraClock = setmetatable({}, { __mode = "k" })
function MoveFX.aura(player, char, styleName, dt)
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local s = styleOf(styleName)
	local st = auraClock[player] or { t = 0, skid = 0, swing = player:GetAttribute("SwingN") }
	auraClock[player] = st
	st.t = st.t + dt
	local hum = char:FindFirstChildOfClass("Humanoid")
	local md = hum and hum.MoveDirection
	local moving = typeof(md) == "Vector3" and md.Magnitude > 0.1
	if st.t >= 0.12 then
		st.t = 0
		local at = root.Position + V3(rnd:NextNumber(-1, 1), rnd:NextNumber(-1.5, 1), rnd:NextNumber(-1, 1))
		if styleName == "Slime" or styleName == "Acid" or styleName == "Blood" or styleName == "Ink" then
			-- drips falling off you
			bits({ at = at, colors = { s.Main, s.Light }, count = 1, speed = { 0, 1 }, up = { 0, 1 }, size = 0.35, life = 0.6, transparency = 0.2,
				floor = floorAt(root.Position) })
		elseif styleName == "Flame" or styleName == "Nitro" or styleName == "Rage" then
			bits({ at = at, colors = { s.Main, s.Light }, count = 1, speed = { 0, 1 }, up = { 3, 6 }, size = 0.4, life = 0.5, gravity = -4,
				material = Enum.Material.Neon })
		elseif styleName == "Leaf" then
			bits({ at = at + V3(0, 2, 0), colors = { RGB(99, 199, 77), RGB(38, 92, 66) }, count = 1, speed = { 1, 2 }, up = { 0, 1 }, size = 0.35, life = 1.2, gravity = 4 })
		elseif styleName == "Smoke" or styleName == "Dirt" or styleName == "Eraser" then
			puffs(V3(root.Position.X, floorAt(root.Position) + 0.6, root.Position.Z), s.Light, 1, 0.9, 1, 0.6, 0.8)
		else
			bits({ at = at, colors = { s.Light, s.Glow }, count = 1, speed = { 0, 1 }, up = { 1, 3 }, size = 0.3, life = 0.6, gravity = -2,
				material = Enum.Material.Neon })
		end
	end
	-- Burnout: skid marks behind you while you run
	if styleName == "Smoke" and moving then
		st.skid = st.skid + dt
		if st.skid >= 0.07 then
			st.skid = 0
			local y = floorAt(root.Position) + 0.05
			for _, side in ipairs({ -0.6, 0.6 }) do
				local p = newPart(V3(0.45, 0.06, 1.1), CFrame.new(root.CFrame * V3(side, 0, 0.6)) * (root.CFrame - root.Position), INK, Enum.Material.SmoothPlastic, 0.25)
				p.CFrame = CFrame.new(p.Position.X, y, p.Position.Z) * (root.CFrame - root.Position)
				task.delay(1.2, function()
					tween(p, 0.6, { Transparency = 1 })
				end)
				gone(p, 1.85)
			end
		end
	end
	-- Sharpen: every swing leaves a streak of ink on the floor
	local sn = player:GetAttribute("SwingN")
	if sn ~= st.swing then
		st.swing = sn
		if styleName == "Ink" then
			local look = root.CFrame.LookVector
			local f = V3(look.X, 0, look.Z).Magnitude > 0.01 and V3(look.X, 0, look.Z).Unit or V3(0, 0, -1)
			local y = floorAt(root.Position) + 0.07
			local a = root.Position + f * 2
			local b = root.Position + f * 8
			streak(V3(a.X, y, a.Z), V3(b.X, y, b.Z), s.Light, 1.2, 1.2, { thick = 0.06, material = Enum.Material.SmoothPlastic })
			splats(b, s.Light, 1.5, 3, 1.2)
		end
	end
end

return MoveFX
