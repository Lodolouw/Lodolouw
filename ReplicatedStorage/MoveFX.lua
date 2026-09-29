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

-- a crescent sweep round a spot (a spin, a sweep): glowing blades of light
-- drawn from angle a0 to a1 (degrees round, 0 = straight ahead)
local function sweep(cf, radius, a0, a1, color, time, o)
	o = o or {}
	local n = o.count or math.max(6, math.floor(math.abs(a1 - a0) / 14))
	local width = o.width or 1.6
	for i = 0, n do
		local u = i / n
		local a = rad(a0 + (a1 - a0) * u)
		local dirv = (cf * CFrame.Angles(0, -a, 0)).LookVector
		local pos = cf.Position + dirv * radius * 0.62 + V3(0, o.height or 0, 0)
		local seg = newPart(V3(width, 0.3, radius * 0.9), CFrame.lookAt(pos, pos + dirv) * CFrame.Angles(0, 0, rad(o.tilt or 0)),
			i % 2 == 0 and color or (o.color2 or color), Enum.Material.Neon, 0.05)
		seg.Transparency = 1
		task.delay(u * (o.draw or 0.12), function()
			seg.Transparency = 0.05
			tween(seg, time, { Transparency = 1, Size = V3(width * 0.2, 0.3, radius * 1.05) })
		end)
		gone(seg, time + (o.draw or 0.12) + 0.05)
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

-- a model of parts moved as one (anchored root, the rest welded to it)
local function prop(build)
	local model = Instance.new("Model")
	model.Name = "MoveProp"
	local root = newPart(V3(0.2, 0.2, 0.2), CFrame.new(), WHITE, Enum.Material.SmoothPlastic, 1)
	root.Parent = model
	model.PrimaryPart = root
	local function add(size, offset, color, material, transparency, shape)
		local p = newPart(size, offset, color, material, transparency, shape)
		p.Parent = model
		weld(root, p)
		return p
	end
	build(add)
	model.Parent = fxFolder()
	return model, root
end

-- a wooden barrel lying on its side (its axis along X, so it rolls forward along Z)
local function barrelProp(scale, golden)
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
	end)
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

-- Oozark's ghostly jaw: an upper and a lower half, each a slab of jelly with teeth
local function jawHalf(style, upper)
	return prop(function(add)
		local s = upper and 1 or -1
		add(V3(11, 3.2, 7), CFrame.new(0, s * 1.6, 0), style.Main, Enum.Material.SmoothPlastic, 0.45)
		add(V3(9, 1.8, 5), CFrame.new(0, s * 1.5, 0.6), RGB(26, 38, 22), Enum.Material.SmoothPlastic, 0.2)
		add(V3(11.2, 0.5, 7.2), CFrame.new(0, s * 3.2, 0), style.Light, Enum.Material.SmoothPlastic, 0.4)
		for i = -4, 4 do
			local x = i * 1.2
			add(V3(0.8, 1.4, 0.8), CFrame.new(x, -s * 0.5, -3.1), WHITE)
		end
		for _, z in ipairs({ -1.5, 0, 1.5 }) do
			add(V3(0.8, 1.2, 0.8), CFrame.new(-5.1, -s * 0.4, z), WHITE)
			add(V3(0.8, 1.2, 0.8), CFrame.new(5.1, -s * 0.4, z), WHITE)
		end
		if upper then
			for _, x in ipairs({ -2.5, 2.5 }) do
				add(V3(1.6, 1.6, 0.4), CFrame.new(x, 2.4, -3.55), RGB(236, 255, 170), Enum.Material.Neon)
			end
		end
	end)
end

-- a giant ape fist (knuckles down), a gold cuff with a banana medallion
local function fistProp()
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
	end)
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
	sfx(WHOOSH, ctx.frame.Position)
end

-- 1. SLIME ------------------------------------------------------------
R.GooGloves = {
	Clap = function(ctx)
		local s, at = ctx.style, chest(ctx, 1.6)
		bits({ at = at, colors = { s.Main, s.Light, s.Glow }, count = 16, speed = { 6, 14 }, up = { 4, 12 }, size = 0.45, life = 0.7,
			transparency = 0.2, floor = ctx.feet.Y })
		ring(ctx.feet, s.Main, 7, 0.35, { size = 0.6 })
		disc(ctx.feet, s.Glow, 5, 0.3)
		light(at, s.Glow, 12, 0.3)
		sfx({ "Orb Land", "Punch 2" }, at)
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
		sfx({ "Orb Land" }, ctx.frame.Position, 0.8)
	end,
}
R.GelatinHammer = {
	Rise = function(ctx)
		local s = ctx.style
		bits({ at = ctx.feet + V3(0, 0.4, 0), colors = { s.Main, s.Light }, count = 8, speed = { 3, 7 }, up = { 3, 6 }, size = 0.4, life = 0.5, transparency = 0.25 })
	end,
	Slam = function(ctx)
		local s = ctx.style
		local at = ahead(ctx, stepAhead(ctx))
		slam(ctx, at, 10, { s.Main, s.Light, s.Glow }, { bits = 22, material = Enum.Material.SmoothPlastic })
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
		sfx(WHOOSH, ctx.frame.Position, 1.2)
	end,
	Cut = function(ctx)
		local s = ctx.style
		local a = ctx.marks.Start or ctx.frame.Position
		local b = ctx.frame.Position
		streak(V3(a.X, ctx.feet.Y + 2.5, a.Z), V3(b.X, ctx.feet.Y + 2.5, b.Z), s.Glow, 1.2, 0.35)
		streak(V3(a.X, ctx.feet.Y + 2.5, a.Z), V3(b.X, ctx.feet.Y + 2.5, b.Z), WHITE, 0.4, 0.2)
		bits({ at = b + V3(0, 1, 0), colors = { s.Glow, s.Main }, count = 12, speed = { 6, 14 }, up = { 4, 10 }, size = 0.4, life = 0.6 })
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
	end,
}
R.AcidScythe = {
	Spin = function(ctx)
		local s = ctx.style
		spin(ctx, 11, s.Glow, s.Light)
		disc(ctx.feet, s.Glow, 11, 0.3)
		light(ctx.frame.Position, s.Glow, 22, 0.3)
	end,
	Fling = function(ctx)
		local s = ctx.style
		local shot = ctx.step.Shot
		for i = 1, shot.Count do
			local dirv = (ctx.frame * CFrame.Angles(0, rad((i - 1) / shot.Count * 360), 0)).LookVector
			local start = ctx.frame.Position + V3(0, 1, 0) + dirv * 1.5
			local target = onFloor(start + dirv * shot.Range, 0.6)
			local model, root = globProp(s)
			fly(model, root, shot.Range / shot.Speed, function(u)
				local p = start:Lerp(target, u) + V3(0, math.sin(u * math.pi) * 4, 0)
				return CFrame.new(p)
			end, function(pos)
				slam(ctx, onFloor(pos), 5, { s.Glow, s.Main, s.Light }, { bits = 10, size = 0.45, sound = { "Orb Land" } })
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
	end,
	Jaw = function(ctx)
		local s = ctx.style
		local base = ctx.frame * CFrame.new(0, 2, -8)
		local top, troot = jawHalf(s, true)
		local bot, broot = jawHalf(s, false)
		-- they open wide, hang there, then snap shut on the Chomp (0.38 s later)
		local t0 = os.clock()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local t = os.clock() - t0
			local open
			if t < 0.25 then
				open = t / 0.25
			elseif t < 0.36 then
				open = 1
			else
				open = math.max(0, 1 - (t - 0.36) / 0.06)
			end
			local gap = 0.4 + open * 4.5
			local tilt = open * 18
			troot.CFrame = base * CFrame.new(0, gap, 0) * CFrame.Angles(rad(tilt), 0, 0)
			broot.CFrame = base * CFrame.new(0, -gap * 0.6, 0) * CFrame.Angles(rad(-tilt * 0.6), 0, 0)
			if t > 0.75 then
				conn:Disconnect()
				top:Destroy()
				bot:Destroy()
			end
		end)
	end,
	Chomp = function(ctx)
		local s = ctx.style
		local at = ahead(ctx, 8)
		slam(ctx, at, 12, { s.Glow, s.Main, s.Light }, { bits = 26, size = 0.7, sound = BOOM })
		pop(at + V3(0, 7, 0), "CHOMP!", s.Glow, 9, 0.9)
		if ctx.own or nearMe(at, 30) then
			screenFlash(s.Glow, 0.35, 0.3)
		end
	end,
}

-- 3. KNIGHT -----------------------------------------------------------
R.ShovelHammer = {
	Dig = function(ctx)
		local s = ctx.style
		local at = ahead(ctx, 3)
		bits({ at = at + V3(0, 0.5, 0), colors = { s.Main, s.Dark, s.Light }, count = 16, speed = { 4, 10 }, up = { 8, 16 }, size = 0.55,
			life = 0.9, floor = at.Y, material = Enum.Material.Slate, dir = ctx.frame.LookVector * -1, spread = 1.2 })
		puffs(at + V3(0, 0.6, 0), s.Light, 4, 1.8, 2, 0.6, 1.5)
		light(at + V3(0, 2, 0), s.Glow, 10, 0.4)
		sfx({ "Punch 3", "Cube Slam" }, at, 0.8)
	end,
}
R.RelicDaggers = {
	Glint = function(ctx)
		local s = ctx.style
		local at = (ctx.frame * CFrame.new(0, 1.5, -1)).Position
		for _, a in ipairs({ 45, -45 }) do
			local p = newPart(V3(0.4, 0.4, 6), CFrame.new(at) * CFrame.Angles(0, 0, rad(a)) * CFrame.Angles(rad(90), 0, 0), s.Light, Enum.Material.Neon, 0)
			tween(p, 0.35, { Size = V3(0.05, 0.05, 8), Transparency = 1 })
			gone(p, 0.4)
		end
		bits({ at = at, colors = { s.Light, s.Main }, count = 10, speed = { 4, 9 }, up = { 3, 8 }, size = 0.35, life = 0.7, material = Enum.Material.Neon })
		light(at, s.Light, 12, 0.35)
		sfx(MAGIC, at, 1.3)
	end,
}
R.SpadeScythe = {
	Spin = function(ctx)
		local s = ctx.style
		spin(ctx, 10, RGB(192, 203, 220), s.Glow, { height = -1.5 })
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
		slam(ctx, at, 8, { s.Light, s.Main, WHITE }, { bits = 16, size = 0.5 })
		column(at, s.Light, 14, 2.2, 0.35)
		-- a star burst of gold
		for i = 1, 8 do
			local a = i / 8 * math.pi * 2
			streak(at + V3(0, 0.3, 0), at + V3(math.cos(a) * 7, 0.3, math.sin(a) * 7), s.Light, 0.7, 0.3)
		end
		pop(at + V3(0, 6, 0), "HONOUR!", s.Light, 7, 0.8)
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
			ring(target, s.Glow, 4, 0.25, { size = 0.5, count = 14 })
			sfx({ "Punch 4", "Cube Slam" }, target)
		end)
		sfx(WHOOSH, from, 0.7)
	end,
	Reel = function(ctx)
		for i = 0, 3 do
			task.delay(i * 0.07, function()
				afterimage(ctx.char, ctx.style.Glow, 0.25, 0.6)
			end)
		end
	end,
	Slam = function(ctx)
		local s = ctx.style
		slam(ctx, ctx.feet, 9, { s.Glow, s.Light, RGB(254, 174, 52) }, { bits = 18 })
		pop(ctx.feet + V3(0, 6, 0), "ANCHORS AWAY!", RGB(254, 231, 97), 9, 0.8)
	end,
}
R.NoQuarter = {
	Crack = function(ctx)
		local s = ctx.style
		column(ctx.feet, s.Light, 20, 3, 0.5)
		ring(ctx.feet, s.Light, 9, 0.4, { size = 0.8 })
		bits({ at = ctx.frame.Position, colors = { s.Light, s.Main }, count = 16, speed = { 4, 10 }, up = { 6, 14 }, size = 0.4, life = 0.8, material = Enum.Material.Neon })
		light(ctx.frame.Position, s.Light, 20, 0.6, 6)
		pop(ctx.frame.Position + V3(0, 5, 0), "NO QUARTER!", s.Light, 10, 1)
		if ctx.own then
			screenFlash(s.Light, 0.3, 0.35)
		end
		sfx(MAGIC, ctx.frame.Position, 0.8)
	end,
	Meteor = function(ctx)
		local s = ctx.style
		local target = onFloor(ctx.point or ahead(ctx, 10))
		-- the warning on the floor, then the star falls on it
		local warn = disc(target, s.Main, 10, 0.55, { r0 = 1, transparency = 0.5, material = Enum.Material.Neon })
		local _ = warn
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
		sfx(WHOOSH, target, 0.6)
	end,
	Impact = function(ctx)
		local s = ctx.style
		local at = onFloor(ctx.point or ahead(ctx, 10))
		slam(ctx, at, 10, { s.Light, s.Main, WHITE }, { bits = 30, size = 0.8, sound = BOOM })
		column(at, s.Light, 26, 4, 0.5)
		if nearMe(at, 35) then
			screenFlash(WHITE, 0.3, 0.25)
		end
	end,
}

-- 5. SPEEDWAY ---------------------------------------------------------
-- a checkered flag burst (black and white squares flying out)
local function checkers(at, count)
	bits({ at = at, colors = { WHITE, INK }, count = count or 20, speed = { 8, 18 }, up = { 8, 18 }, size = 0.7, life = 1, floor = at.Y - 1 })
end
R.TyreScythe = {
	Rev = function(ctx)
		local s = ctx.style
		local back = ahead(ctx, -1.5)
		puffs(back + V3(0, 0.6, 0), s.Light, 7, 2, 2, 0.9, 1.5)
		for _, side in ipairs({ -1, 1 }) do
			streak(ahead(ctx, 1, side * 1.5) + V3(0, 0.3, 0), ahead(ctx, -6, side * 1.5) + V3(0, 0.3, 0), s.Glow, 0.5, 0.4)
		end
		sfx({ "Ship Thrust", "Wave Zoom" }, ctx.frame.Position)
	end,
}
R.NitroKatana = {
	Boost = function(ctx)
		local s = ctx.style
		local back = (ctx.frame * CFrame.new(0, 0.5, 1.5)).Position
		-- a blue flame blasting out behind you
		for i = 1, 10 do
			local p = newPart(V3(1, 1, 1), CFrame.new(back), i % 2 == 0 and s.Glow or s.Main, Enum.Material.Neon, 0.1, Enum.PartType.Ball)
			local out = (ctx.frame * CFrame.new(rnd:NextNumber(-1, 1), rnd:NextNumber(-0.5, 1), 4 + i * 0.6)).Position
			tween(p, 0.35, { CFrame = CFrame.new(out), Size = V3(2.2, 2.2, 2.2), Transparency = 1 })
			gone(p, 0.4)
		end
		ring(ctx.feet, s.Glow, 7, 0.3, { size = 0.6 })
		light(back, s.Glow, 14, 0.4)
		sfx({ "Ship Thrust", "Portal Whoosh" }, ctx.frame.Position, 1.2)
	end,
}
R.PistonPunchers = {
	Pump = function(ctx)
		local s = ctx.style
		puffs(chest(ctx, 0.2) + V3(0, 1, 0), WHITE, 5, 1.2, 3, 0.6, 1)
		sfx({ "Ship Thrust" }, ctx.frame.Position, 0.8)
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
		slam(ctx, at, 7, { s.Main, s.Light, s.Glow }, { bits = 16, sound = BOOM })
		puffs(at + V3(0, 1.5, 0), RGB(90, 90, 100), 5, 2, 3, 0.8, 1.5)
		pop(at + V3(0, 5, 0), "VROOM!", s.Light, 7, 0.7)
	end,
}
R.PitStopSabre = {
	SkidSpin = function(ctx)
		local s = ctx.style
		spin(ctx, 11, s.Glow, WHITE)
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
		sfx({ "Ship Thrust", "Wave Zoom" }, ctx.frame.Position)
	end,
	Slam = function(ctx)
		local s = ctx.style
		local at = ahead(ctx, 3)
		slam(ctx, at, 10, { s.Main, s.Light, s.Glow }, { bits = 22, sound = BOOM })
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
		sfx({ "Attempt Start", "Level Complete" }, ctx.frame.Position)
	end,
	Finish = function(ctx)
		local s = ctx.style
		slam(ctx, ctx.feet, 12, { s.Glow, WHITE, INK }, { bits = 20, sound = BOOM })
		checkers(ctx.frame.Position + V3(0, 1, 0), 30)
		pop(ctx.frame.Position + V3(0, 6, 0), "FINISH!", RGB(254, 231, 97), 10, 1)
		sfx({ "Level Complete" }, ctx.frame.Position)
	end,
}

-- 7. JUNGLE -----------------------------------------------------------
R.ChestPoundFists = {
	Roar = function(ctx)
		local s = ctx.style
		for i = 0, 2 do
			task.delay(i * 0.1, function()
				ring(ctx.feet, i == 1 and s.Light or s.Main, 9 + i * 2, 0.45, { size = 0.9, rise = 2 })
			end)
		end
		bits({ at = chest(ctx, 0.5) + V3(0, 1, 0), colors = { RGB(99, 199, 77), RGB(38, 92, 66) }, count = 14, speed = { 6, 12 }, up = { 6, 12 },
			size = 0.5, life = 1.1, gravity = 18 })
		pop(ctx.frame.Position + V3(0, 5, 0), "ROAR!", s.Main, 8, 0.9)
		light(chest(ctx, 0.3), s.Main, 16, 0.5)
		sfx({ "Boss Wail", "Gridlock Stun" }, ctx.frame.Position)
	end,
}
R.JungleFang = {
	Fang = function(ctx)
		local s = ctx.style
		local at = chest(ctx, 1.5)
		for _, side in ipairs({ -1, 1 }) do
			local p = newPart(V3(0.6, 3.2, 0.6), CFrame.new(at + V3(side * 0.8, 0.6, 0)) * CFrame.Angles(0, 0, rad(side * 12)), WHITE, Enum.Material.Neon, 0)
			tween(p, 0.35, { CFrame = p.CFrame - V3(0, 1.2, 0), Transparency = 1 }, Enum.EasingStyle.Back)
			gone(p, 0.4)
		end
		bits({ at = at, colors = { s.Main, s.Glow }, count = 8, speed = { 3, 7 }, up = { 2, 6 }, size = 0.35, life = 0.6, material = Enum.Material.Neon })
		light(at, s.Glow, 10, 0.3)
		sfx({ "Punch 1" }, at, 1.4)
	end,
}
R.VineScythe = {
	Vine = function(ctx)
		local s = ctx.style
		local arm = ctx.char and ctx.char:FindFirstChild("Right Arm")
		local anchorP, top = anchorAt((ctx.frame * CFrame.new(0, 16, -6)))
		local hand = Instance.new("Attachment")
		hand.Position = V3(0, -1, 0)
		hand.Parent = arm or anchorP
		local vine = beam(top, hand, RGB(62, 137, 72), 0.45)
		vine.CurveSize0, vine.CurveSize1 = 1.5, -1.5
		for i = 1, 6 do
			local leaf = newPart(V3(0.7, 0.1, 0.5), anchorP.CFrame * CFrame.new(rnd:NextNumber(-2, 2), -rnd:NextNumber(0, 8), rnd:NextNumber(-2, 2)),
				i % 2 == 0 and RGB(99, 199, 77) or RGB(38, 92, 66))
			tween(leaf, 1.2, { CFrame = (leaf.CFrame - V3(0, 6, 0)) * CFrame.Angles(0, 3, 1), Transparency = 1 })
			gone(leaf, 1.25)
		end
		task.delay(0.6, function()
			hand:Destroy()
			anchorP:Destroy()
		end)
		sfx(WHOOSH, ctx.frame.Position, 0.85)
	end,
	Sweep = function(ctx)
		local s = ctx.style
		sweep(ctx.frame * CFrame.new(0, -0.5, 0), 11, -80, 80, s.Main, 0.35, { width = 2.2, color2 = s.Light })
		bits({ at = ahead(ctx, 4) + V3(0, 1, 0), colors = { RGB(99, 199, 77), RGB(38, 92, 66), RGB(254, 231, 97) }, count = 16, speed = { 8, 16 },
			up = { 6, 12 }, size = 0.5, life = 1, gravity = 20 })
		ring(ahead(ctx, 3), s.Main, 8, 0.35, { size = 0.6 })
		sfx(SLAM, ctx.frame.Position, 1.1)
	end,
}
-- a barrel rolling along the floor from you (the server's own path: Moves' Shot)
local function rollBarrels(ctx, scale, golden)
	local s = ctx.style
	local shot = ctx.step.Shot
	local n = shot.Count or 1
	for i = 1, n do
		local angle = ((i - 1) - (n - 1) / 2) * (shot.Spread or 0)
		local dirv = (ctx.frame * CFrame.Angles(0, rad(angle), 0)).LookVector
		local start = V3(ctx.frame.Position.X, ctx.feet.Y + 1.1 * scale, ctx.frame.Position.Z) + dirv * 1.5
		local model, root = barrelProp(scale, golden)
		local time = shot.Range / shot.Speed
		local look = CFrame.lookAt(start, start + dirv)
		fly(model, root, time, function(u)
			local p = start + dirv * shot.Range * u
			if rnd:NextNumber() < 0.3 then
				puffs(V3(p.X, ctx.feet.Y + 0.4, p.Z), s.Light, 1, 1, 0.6, 0.4, 0.4)
			end
			return CFrame.new(p) * (look - look.Position) * CFrame.Angles(-u * shot.Range / (1.1 * scale), 0, 0) * CFrame.Angles(0, rad(90), 0)
		end, function(pos)
			bits({ at = pos, colors = { s.Main, s.Dark, RGB(58, 68, 102) }, count = 16, speed = { 6, 14 }, up = { 6, 14 }, size = 0.6, life = 0.9,
				floor = ctx.feet.Y, material = Enum.Material.WoodPlanks })
			if shot.Burst then
				slam(ctx, onFloor(pos), shot.Burst.Radius, { RGB(247, 118, 34), RGB(254, 231, 97), s.Main }, { bits = 14, sound = BOOM })
				puffs(pos + V3(0, 1, 0), RGB(80, 80, 90), 5, 2.4, 3, 0.9, 2)
			else
				sfx({ "Punch 4" }, pos)
			end
		end)
	end
end
R.BarrelDaggers = {
	Bowl = function(ctx)
		rollBarrels(ctx, 1, false)
		sfx(WHOOSH, ctx.frame.Position, 0.8)
	end,
}
R.BarrelHammer = {
	Bat = function(ctx)
		local golden = ctx.player and (ctx.player:GetAttribute("Mastery") or 1) >= 100
		rollBarrels(ctx, golden and 1.8 or 1.3, golden)
		ring(ahead(ctx, 1.5), ctx.style.Light, 4, 0.25, { size = 0.5, count = 14 })
		sfx(SLAM, ctx.frame.Position, 1.2)
	end,
}
R.KongsCrown = {
	Call = function(ctx)
		local s = ctx.style
		column(ctx.feet, s.Light, 22, 2, 0.6)
		light(ctx.frame.Position, s.Light, 16, 0.6)
		pop(ctx.frame.Position + V3(0, 5, 0), "KONG!", s.Light, 8, 0.8)
		sfx(MAGIC, ctx.frame.Position, 0.7)
	end,
	SkyFist = function(ctx)
		local s = ctx.style
		local target = onFloor(ctx.point or ahead(ctx, 10))
		-- its shadow grows on the floor as it falls out of the sky
		local shadow = newPart(V3(0.1, 2, 2), CFrame.new(target + V3(0, 0.08, 0)) * CFrame.Angles(0, 0, rad(90)), INK, Enum.Material.SmoothPlastic, 0.6, Enum.PartType.Cylinder)
		tween(shadow, 0.75, { Size = V3(0.1, 22, 22), Transparency = 0.35 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		gone(shadow, 1)
		local model, root = fistProp()
		fly(model, root, 0.75, function(u)
			return CFrame.new(target + V3(0, 60 - 55.5 * (u * u), 0)) * CFrame.Angles(0, rad(25), 0)
		end)
		sfx(WHOOSH, target, 0.5)
	end,
	Impact = function(ctx)
		local s = ctx.style
		local at = onFloor(ctx.point or ahead(ctx, 10))
		slam(ctx, at, 12, { s.Light, s.Main, RGB(165, 160, 172) }, { bits = 30, size = 0.9, material = Enum.Material.Slate, sound = BOOM, dust = RGB(170, 160, 150) })
		-- rocks thrown up round the crater
		bits({ at = at + V3(0, 1, 0), colors = { RGB(120, 118, 110), RGB(84, 82, 78) }, count = 14, speed = { 6, 14 }, up = { 12, 22 }, size = 1.2,
			life = 1.2, floor = at.Y, material = Enum.Material.Slate, bounce = true })
		pop(at + V3(0, 8, 0), "SMASH!", s.Light, 10, 1)
		if nearMe(at, 40) then
			screenFlash(WHITE, 0.25, 0.25)
		end
	end,
}

-- 9. CANVAS -----------------------------------------------------------
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
R.EraserHammer = {
	Rub = function(ctx)
		local s = ctx.style
		local at = ahead(ctx, 2.5) + V3(0, 1.5, 0)
		puffs(at, s.Light, 8, 1.2, 1.2, 0.7, 1.2)
		bits({ at = at, colors = { s.Main, s.Light }, count = 10, speed = { 2, 6 }, up = { 2, 6 }, size = 0.35, life = 0.8, gravity = 25 })
		sfx({ "Punch 2" }, at, 1.5, 0.6)
	end,
}
R.PencilSword = {
	Sharpen = function(ctx)
		local s = ctx.style
		local at = chest(ctx, 1.2) + V3(0, 1, 0)
		-- pencil shavings: curls of wood and yellow paint
		bits({ at = at, colors = { RGB(228, 166, 114), RGB(254, 174, 52), RGB(90, 90, 100) }, count = 14, speed = { 4, 9 }, up = { 4, 9 }, size = 0.4,
			life = 0.9, gravity = 30, floor = ctx.feet.Y })
		ring(ctx.feet, s.Light, 6, 0.3, { size = 0.5 })
		sfx({ "Punch 2" }, at, 1.8, 0.6)
	end,
}
R.InkFists = {
	Splash = function(ctx)
		local s = ctx.style
		local at = ahead(ctx, stepAhead(ctx))
		slam(ctx, at, 10, { s.Light, s.Main, s.Dark }, { bits = 20, dust = RGB(200, 200, 215) })
		splats(at, s.Main, 9, 22, 3)
		splats(at, s.Light, 7, 8, 2.4)
		pop(at + V3(0, 5, 0), "SPLOSH!", s.Light, 7, 0.8)
	end,
}
R.DoodleKatana = {
	Doodle = function(ctx)
		local s = ctx.style
		ctx.data.doodle = doodle(ctx.char, WHITE, INK, 1.6)
		pop(ctx.frame.Position + V3(0, 4, 0), "DOODLE!", s.Light, 6, 0.7)
		sfx({ "Portal Whoosh" }, ctx.frame.Position, 1.4)
	end,
	Slash = function(ctx)
		local s = ctx.style
		local a = ctx.marks.Start or ctx.frame.Position
		local b = ctx.frame.Position
		streak(V3(a.X, ctx.feet.Y + 2.5, a.Z), V3(b.X, ctx.feet.Y + 2.5, b.Z), s.Light, 1, 0.4)
		streak(V3(a.X, ctx.feet.Y + 2.5, a.Z), V3(b.X, ctx.feet.Y + 2.5, b.Z), INK, 0.3, 0.5)
		sfx(WHOOSH, b, 1.3)
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
		streak(V3(a.X, ctx.feet.Y + 2.5, a.Z), V3(b.X, ctx.feet.Y + 2.5, b.Z), s.Light, 1.4, 0.45)
		for i = 1, 6 do
			local u = i / 6
			local p = a:Lerp(b, u)
			bits({ at = V3(p.X, ctx.feet.Y + 2.5, p.Z), colors = { s.Light, INK }, count = 3, speed = { 2, 5 }, up = { 2, 5 }, size = 0.3, life = 0.5 })
		end
		sfx(WHOOSH, b, 1.5)
	end,
}
R.CopyPasteScythe = {
	Copy = function(ctx)
		local s = ctx.style
		local at = ctx.frame.Position
		wireBox(at, V3(4.5, 6, 4.5), s.Light, 0.6)
		pop(at + V3(0, 4.5, 0), "CTRL+C", s.Light, 6, 0.7)
		task.delay(0.35, function()
			pop(at + V3(0, 4.5, 0), "CTRL+V", s.Light, 6, 0.7)
		end)
		sfx(MAGIC, at, 1.5)
		-- two ink copies of you, one each side, doing what you do for 5 s
		local char = ctx.char
		if not char then
			return
		end
		local copies = {}
		for _, side in ipairs({ -5, 5 }) do
			local m = Instance.new("Model")
			for _, name in ipairs(BODY) do
				local part = char:FindFirstChild(name)
				if part and part:IsA("BasePart") then
					local p = newPart(part.Size, part.CFrame, s.Light, Enum.Material.Neon, 0.55)
					p.Name = name
					p.Parent = m
				end
			end
			m.Parent = fxFolder()
			copies[#copies + 1] = { m = m, side = side }
		end
		local t0 = os.clock()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local root = char:FindFirstChild("HumanoidRootPart")
			if os.clock() - t0 > 5.2 or not root then
				conn:Disconnect()
				for _, c in ipairs(copies) do
					c.m:Destroy()
				end
				return
			end
			for _, c in ipairs(copies) do
				local shift = root.CFrame.RightVector * c.side
				for _, p in ipairs(c.m:GetChildren()) do
					local src = char:FindFirstChild(p.Name)
					if src then
						p.CFrame = src.CFrame + shift
					end
				end
			end
		end)
	end,
}
R.DeleteKey = {
	Glitch = function(ctx)
		local s = ctx.style
		local at = ctx.point and onFloor(ctx.point) or ahead(ctx, 8)
		wireBox(at + V3(0, 3.5, 0), V3(8, 7, 8), s.Main, 0.8)
		pop(at + V3(0, 8.5, 0), "DELETE?", s.Main, 9, 0.8)
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
							f.BackgroundColor3 = ({ s.Main, RGB(44, 232, 245), WHITE, INK })[rnd:NextInteger(1, 4)]
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
		sfx({ "Gridlock Stun", "Portal Whoosh" }, at)
	end,
	Delete = function(ctx)
		local s = ctx.style
		local at = ctx.point and onFloor(ctx.point) or ahead(ctx, 8)
		slam(ctx, at, 8, { s.Main, WHITE, INK }, { bits = 10, sound = SHATTER })
		-- everything round it shatters into pixels
		bits({ at = at + V3(0, 3, 0), colors = { s.Main, WHITE, RGB(44, 232, 245), INK }, count = 36, speed = { 8, 20 }, up = { 4, 18 }, size = 0.55,
			life = 1.1, gravity = 30, material = Enum.Material.Neon })
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
		pop(ctx.point + V3(0, 3, 0), "ERASED!", s.Main, 7, 0.8)
		sfx({ "Punch 3" }, ctx.point)
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
		sfx(MAGIC, ctx.point, 1.6, 0.6)
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
		marks = inst.marks, data = inst.data, point = inst.marks.T,
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
	local inst = { id = id, count = count, marks = {}, data = {}, own = own }
	live[player] = inst
	local style = styleOf(move.Style)
	for _, step in ipairs(move.Steps or {}) do
		if step.Mark or (step.Fx and not step.Pick) or (step.Shake and not step.Pick) then
			task.delay(step.At or 0, function()
				if live[player] ~= inst then
					return -- (a newer one's started)
				end
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
