--[[
	WeaponFX  (ModuleScript, parent: ReplicatedStorage, name: "WeaponFX")

	How weapons look, on every screen - anime style. The weapon in each
	fighter's hand, their stance, their swings and their ability, all made in
	code on the R6 joints (both arms, both legs, the neck and the body), with
	no uploaded animations.

	  * THE WEAPON: anyone holding one in a fight (the "Weapon" attribute
	    CombatService sets) has it in their right hand - a chunky 8-bit sword
	    with a glowing edge, built on this screen only. Out of a fight it's
	    put away.
	  * THE STANCE: holding it, you stand ready - blade low and angled back
	    behind you, left foot forward, the free hand up, breathing. (Walking,
	    your legs walk; the arms keep the stance.)
	  * A SWING puts the whole body into it, the way anime fights do:
	      anticipation - a quick coil back (the body turns, the weight goes
	                     onto the back foot, the free arm reaches out),
	      the snap     - the cut itself is almost instant, lunging forward,
	      follow-through - the blade flies on PAST where it stops and the
	                     body twists after it, then settles back into the
	                     stance.
	    The string: a slash right to left, a backhand left to right, and an
	    overhead chop that brings the body down with it. A bold glowing
	    smear follows the blade through every cut.
	  * THE ABILITY (the Iron Sword's Whirlwind): arms out, and the whole
	    body spins round - once, twice or three times, by mastery.
	  * HITS: a moment of hit-stop (your swing freezes for a blink as the
	    blade bites - WeaponFX.hitStop) and a slash mark ripping across
	    whatever you hit, with sparks (WeaponFX.slashMark).
	  * AWAKENED (mastery 100): the blade turns glowing gold.

	Your own swings start the moment you press (CombatClient calls
	WeaponFX.swing / WeaponFX.spin); everyone else's start when their SwingN
	/ AbilityN attribute changes (CombatService sets those).

	Sounds (in SoundService, by name - capitals and spaces don't matter):
	each type's Sounds.Swing ("Sword Swing") and each ability's Sound
	("Whirlwind"). Missing ones are just silent.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local W = Config.Weapons or { List = {}, Types = {}, MasteryMax = 100 }

local WeaponFX = {}
local rad = math.rad

----------------------------------------------------------------------
-- The poses (all in degrees)
----------------------------------------------------------------------
-- A pose turns each joint by { x, y, z } (CFrame.Angles on that joint):
--   Root  the whole body: x leans it forward, z turns it (+ = the chest
--         turns left, the right shoulder comes forward)
--   RS/LS the right / left arm at the shoulder: RS z swings the right arm
--         forward and up, y sweeps it across the body (+ = further left);
--         LS is the mirror (its z the other way: - is forward)
--   RH/LH the right / left leg at the hip: RH z + swings the right leg
--         forward, LH z - the left one forward
--   Neck  the head: x + looks down, z + turns it left
--   Grip  the sword in the hand: { tilt, roll } (0 tilt: the blade points
--         straight out the front of the fist)
-- The legs keep their feet on the floor by themselves: whatever the body
-- leans or turns is taken back off at the hips (except in the spin).
WeaponFX.STANCE = {
	Root = { 5, 0, -15 },
	RS = { -15, 0, -25 },
	LS = { -10, 20, -20 },
	RH = { 0, 0, -12 },
	LH = { 0, 0, -18 },
	Neck = { 0, 0, 15 },
	Grip = { -150, 0 }, -- the blade low and angled back behind you
}
WeaponFX.POSES = {
	Sword = {
		{ -- a slash, right to left
			wind = { Root = { -5, 0, -45 }, RS = { 0, -85, 100 }, LS = { 20, 0, -60 }, RH = { 0, 0, -20 }, LH = { 0, 0, -25 }, Neck = { 0, 0, 40 }, Grip = { -70, 0 } },
			cut = { Root = { 15, 0, 10 }, RS = { 0, 10, 95 }, LS = { -20, 0, 50 }, RH = { 0, 0, -35 }, LH = { 0, 0, -45 }, Neck = { 0, 0, -10 }, Grip = { -70, 0 } },
			follow = { Root = { 20, 0, 55 }, RS = { 0, 95, 80 }, LS = { -10, 0, 70 }, RH = { 0, 0, -35 }, LH = { 0, 0, -45 }, Neck = { 0, 0, -45 }, Grip = { -70, 30 } },
		},
		{ -- a backhand, left to right
			wind = { Root = { -5, 0, 50 }, RS = { 0, 95, 100 }, LS = { -10, 0, 50 }, RH = { 0, 0, 10 }, LH = { 0, 0, -15 }, Neck = { 0, 0, -45 }, Grip = { -70, 30 } },
			cut = { Root = { 15, 0, -10 }, RS = { 0, 0, 95 }, LS = { 20, 0, -40 }, RH = { 0, 0, 40 }, LH = { 0, 0, 30 }, Neck = { 0, 0, 10 }, Grip = { -70, 0 } },
			follow = { Root = { 15, 0, -55 }, RS = { 0, -80, 90 }, LS = { 20, 0, -70 }, RH = { 0, 0, 40 }, LH = { 0, 0, 30 }, Neck = { 0, 0, 45 }, Grip = { -70, -20 } },
		},
		{ -- an overhead chop: up high, then everything comes down with it
			wind = { Root = { -15, 0, -15 }, RS = { 0, 5, 190 }, LS = { 20, 0, -160 }, RH = { 0, 0, -15 }, LH = { 0, 0, -20 }, Neck = { -15, 0, 15 }, Grip = { -60, 0 } },
			cut = { Root = { 35, 0, 0 }, RS = { 0, 5, 85 }, LS = { 20, 0, -80 }, RH = { 0, 0, -40 }, LH = { 0, 0, -50 }, Neck = { 10, 0, 0 }, Grip = { -75, 0 } },
			follow = { Root = { 40, 0, 0 }, RS = { 0, 5, 55 }, LS = { 10, 0, -45 }, RH = { 0, 0, -40 }, LH = { 0, 0, -50 }, Neck = { 15, 0, 0 }, Grip = { -70, 0 } },
		},
	},
}
-- the Whirlwind: arms out, a little lean, feet wide (the body turns round on top)
WeaponFX.SPIN = { Root = { 10, 0, 0 }, RS = { 0, -85, 95 }, LS = { -80, 0, 0 }, RH = { -10, 0, 0 }, LH = { -10, 0, 0 }, Neck = { 0, 0, 0 }, Grip = { -70, 0 } }
WeaponFX.JOINTS = { "Root", "RS", "LS", "RH", "LH", "Neck" }

local function smooth(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end
local function easeOut(t)
	t = math.clamp(t, 0, 1)
	return 1 - (1 - t) * (1 - t)
end
local function snap(t) -- slow to start, then all at once (the cut)
	t = math.clamp(t, 0, 1)
	return t * t * t
end
local function overshoot(t) -- flies past the end and comes back (the follow-through)
	t = math.clamp(t, 0, 1) - 1
	local s = 1.6
	return 1 + (s + 1) * t * t * t + s * t * t
end
local function mixPose(p, q, t)
	local out = {}
	for key, a in pairs(p) do
		local b = q[key] or a
		local m = {}
		for i = 1, #a do
			m[i] = a[i] + (b[i] - a[i]) * t
		end
		out[key] = m
	end
	return out
end
WeaponFX.mixPose = mixPose

-- A swing `u` of the way through (0 = pressed, 1 = over), whose blade lands
-- `contact` of the way through, starting from and settling back into `base`
-- (the stance). Gives the whole pose, and how much of it shows over whatever
-- the body was doing before (0 to 1).
function WeaponFX.swingPose(keys, u, contact, base)
	base = base or WeaponFX.STANCE
	contact = math.clamp(contact or 0.4, 0.15, 0.8)
	u = math.clamp(u, 0, 1)
	local uWind = contact * 0.55 -- coiled by here...
	local uFollow = math.min(0.82, contact + 0.24) -- ...followed through by here
	local pose
	if u < uWind then
		pose = mixPose(base, keys.wind, easeOut(u / uWind))
	elseif u < contact then
		pose = mixPose(keys.wind, keys.cut, snap((u - uWind) / (contact - uWind)))
	elseif u < uFollow then
		pose = mixPose(keys.cut, keys.follow, overshoot((u - contact) / (uFollow - contact)))
	else
		pose = mixPose(keys.follow, base, smooth((u - uFollow) / (1 - uFollow)))
	end
	local weight = smooth(u / math.max(uWind * 0.4, 0.01))
	return pose, weight, u >= uWind * 0.8 and u <= uFollow + 0.05 -- (the smear: through the cut)
end

-- The Whirlwind `u` of the way through `spins` spins: the body turns all the
-- way round each spin (the same way a first slash cuts: to the left).
function WeaponFX.spinPose(u, spins)
	u = math.clamp(u, 0, 1)
	local eased = u < 0.5 and 2 * u * u or 1 - 2 * (1 - u) * (1 - u)
	local turn = 360 * spins * (0.75 * u + 0.25 * eased)
	local pose = mixPose(WeaponFX.SPIN, WeaponFX.SPIN, 0)
	pose.Root = { pose.Root[1], 0, turn }
	local weight = math.min(smooth(u / 0.1), 1 - smooth((u - 0.9) / 0.1) * 0) -- (it hands back to the stance)
	return pose, weight
end

-- the sword's place in the hand
local function gripAt(tilt, roll)
	return CFrame.new(0, -1, 0) * CFrame.Angles(rad(tilt), 0, 0) * CFrame.Angles(0, 0, rad(roll or 0))
end
WeaponFX.gripAt = gripAt

----------------------------------------------------------------------
-- Sounds (by name from SoundService; capitals and spaces don't matter)
----------------------------------------------------------------------
local function squash(s)
	return string.lower((string.gsub(tostring(s), "[%s_%-]", "")))
end
local soundCache = {}
local function findSound(name)
	if not name or name == "" then
		return nil
	end
	local hit = soundCache[name]
	if hit and hit.Parent then
		return hit
	end
	local want = squash(name)
	for _, s in ipairs(SoundService:GetChildren()) do
		if s:IsA("Sound") and squash(s.Name) == want then
			soundCache[name] = s
			return s
		end
	end
	return nil
end
local function playAt(name, parent, pitch)
	local template = findSound(name)
	if not (template and parent and parent.Parent) then
		return false
	end
	local s = template:Clone()
	s.PlaybackSpeed = template.PlaybackSpeed * (pitch or 1)
	s.RollOffMaxDistance = 100
	local group = SoundService:FindFirstChild("Effects")
	if group and group:IsA("SoundGroup") then
		s.SoundGroup = group
	end
	s.Parent = parent
	s:Play()
	task.delay(math.max(s.TimeLength, 1) + 0.5, function()
		s:Destroy()
	end)
	return true
end

----------------------------------------------------------------------
-- The weapon in the hand
----------------------------------------------------------------------
local GOLD = Color3.fromRGB(254, 231, 97)
local GLOW = Color3.fromRGB(200, 240, 255)

-- the sword, as chunky 8-bit blocks. The handle is what's held (welded to the
-- hand); the rest hangs off it along its -Z (the way the blade points).
local function buildSword(def, golden)
	local c = def.Colors or {}
	local model = Instance.new("Model")
	model.Name = "HeldWeapon"
	local handle
	local function piece(name, size, offset, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = false, false, false, false
		p.Massless = true
		if handle then
			p.CFrame = handle.CFrame * offset
			local weld = Instance.new("Weld")
			weld.Part0, weld.Part1 = handle, p
			weld.C0 = offset
			weld.Parent = p
		end
		p.Parent = model
		return p
	end
	handle = piece("Handle", Vector3.new(0.35, 0.35, 0.9), CFrame.new(), c.Grip or Color3.fromRGB(115, 62, 57))
	local metal = golden and GOLD or (c.Blade or Color3.fromRGB(192, 203, 220))
	local shine = golden and Enum.Material.Neon or Enum.Material.SmoothPlastic
	piece("Pommel", Vector3.new(0.48, 0.48, 0.48), CFrame.new(0, 0, 0.65), c.Guard or GOLD)
	piece("Guard", Vector3.new(1.5, 0.36, 0.36), CFrame.new(0, 0, -0.62), c.Guard or GOLD)
	local blade = piece("Blade", Vector3.new(0.3, 0.8, 4), CFrame.new(0, 0, -2.8), metal, shine)
	piece("Edge", Vector3.new(0.32, 0.14, 3.8), CFrame.new(0, 0.34, -2.8), golden and GOLD or GLOW, Enum.Material.Neon)
	piece("Tip", Vector3.new(0.3, 0.5, 0.45), CFrame.new(0, 0.1, -5.02), metal, shine)
	-- the smear that follows the blade through a cut: a bold glowing ribbon
	-- the length of the blade, and a softer, wider one round it
	local function smear(name, from, to, color, see, life)
		local a0 = Instance.new("Attachment")
		a0.Name = name .. "Base"
		a0.Position = Vector3.new(0, 0, from)
		a0.Parent = blade
		local a1 = Instance.new("Attachment")
		a1.Name = name .. "Tip"
		a1.Position = Vector3.new(0, 0, to)
		a1.Parent = blade
		local trail = Instance.new("Trail")
		trail.Name = name
		trail.Attachment0, trail.Attachment1 = a0, a1
		trail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), color)
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, see), NumberSequenceKeypoint.new(0.6, 0.7), NumberSequenceKeypoint.new(1, 1) })
		trail.LightEmission = 1
		trail.Lifetime = life
		trail.MinLength = 0.02
		trail.WidthScale = NumberSequence.new(1, 0.4)
		trail.Enabled = false
		trail.Parent = blade
		return trail
	end
	local trails = {
		smear("SwingTrail", 1.2, -2.3, golden and GOLD or GLOW, 0, 0.22),
		smear("SwingGlow", 2, -3.2, golden and GOLD or Color3.fromRGB(120, 200, 255), 0.55, 0.3),
	}
	return model, handle, trails
end

----------------------------------------------------------------------
-- Hits: the slash mark ripping across what you hit
----------------------------------------------------------------------
-- a bright bar that tears across the spot, stretching out and fading, with a
-- burst of sparks - and on a heavy hit a second one crossing it
function WeaponFX.slashMark(position, direction, heavy, golden)
	if typeof(position) ~= "Vector3" then
		return
	end
	local dir = typeof(direction) == "Vector3" and direction.Magnitude > 0.01 and direction.Unit or Vector3.new(0, 0, -1)
	local color = golden and GOLD or GLOW
	local holder = Instance.new("Folder")
	holder.Name = "SlashMark"
	holder.Parent = workspace
	local marks = heavy and 2 or 1
	for i = 1, marks do
		local bar = Instance.new("Part")
		bar.Name = "Slash"
		bar.Anchored, bar.CanCollide, bar.CanTouch, bar.CanQuery, bar.CastShadow = true, false, false, false, false
		bar.Material = Enum.Material.Neon
		bar.Color = i == 1 and Color3.fromRGB(255, 255, 255) or color
		local long = heavy and 11 or 7
		bar.Size = Vector3.new(0.35, 0.35, 1)
		-- across the swing, tilted (two crossing on a heavy hit)
		local tilt = (i == 1 and 30 or -40) + math.random(-10, 10)
		bar.CFrame = CFrame.lookAt(position, position + dir) * CFrame.Angles(0, math.rad(90), math.rad(tilt))
		bar.Parent = holder
		local t0 = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local k = (os.clock() - t0) / (heavy and 0.28 or 0.2)
			if k >= 1 or not bar.Parent then
				conn:Disconnect()
				bar:Destroy()
				return
			end
			local grow = 1 - (1 - math.min(k * 3, 1)) ^ 3 -- tears open fast...
			bar.Size = Vector3.new(0.35 * (1 - k * 0.7), 0.35 * (1 - k * 0.7), 1 + long * grow)
			bar.Transparency = math.max(0, (k - 0.35) / 0.65) -- ...then fades
		end)
	end
	local sparks = Instance.new("Part")
	sparks.Name = "Sparks"
	sparks.Anchored, sparks.CanCollide, sparks.CanTouch, sparks.CanQuery = true, false, false, false
	sparks.Transparency = 1
	sparks.Size = Vector3.new(0.2, 0.2, 0.2)
	sparks.CFrame = CFrame.new(position)
	sparks.Parent = holder
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(heavy and 0.7 or 0.45, 0)
	emitter.Lifetime = NumberRange.new(0.15, 0.35)
	emitter.Speed = NumberRange.new(20, heavy and 45 or 30)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 5
	emitter.Rate = 0
	emitter.Parent = sparks
	emitter:Emit(heavy and 26 or 14)
	task.delay(0.8, function()
		holder:Destroy()
	end)
end

----------------------------------------------------------------------
-- Who's holding what, and what they're doing
----------------------------------------------------------------------
local held = {} -- [player] = what we've built and are showing for them
WeaponFX._held = held -- (for the headless tests)

local function fighting(plr)
	local intro = plr:GetAttribute("Intro")
	return plr:GetAttribute("SpireFloor") ~= nil or plr:GetAttribute("Colosseum") == true or intro == "Void" or intro == "Fight"
end

-- moves a joint `weight` of the way to `target`, starting from wherever
-- Roblox's own animations put it this frame - or, if nothing moved it since
-- we did, from where it rests (so a pose can never pile up on itself)
local function blend(h, joint, target, weight)
	local mem = h.mem[joint]
	local now = joint.Transform
	if mem.wrote and now == mem.wrote then
		now = mem.rest
	else
		mem.rest = now
	end
	local out = now:Lerp(target, weight)
	joint.Transform = out
	mem.wrote = out
end

-- let go of the joints: each back where it rests, if we were the last to move it
local function release(h)
	for joint, mem in pairs(h.mem) do
		if joint.Parent and mem.wrote and joint.Transform == mem.wrote then
			joint.Transform = mem.rest
		end
		mem.wrote = nil
	end
end

local function drop(plr)
	local h = held[plr]
	if not h then
		return
	end
	if h.model then
		h.model:Destroy()
	end
	if h.mem then
		release(h)
	end
	held[plr] = nil
end

local function hold(plr, char, id, def)
	local torso = char:FindFirstChild("Torso")
	local arm = char:FindFirstChild("Right Arm")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local function motor(parent, name)
		local m = parent and parent:FindFirstChild(name)
		return m and m:IsA("Motor6D") and m or nil
	end
	local joints = {
		RS = motor(torso, "Right Shoulder"),
		LS = motor(torso, "Left Shoulder"),
		RH = motor(torso, "Right Hip"),
		LH = motor(torso, "Left Hip"),
		Neck = motor(torso, "Neck"),
		Root = motor(hrp, "RootJoint"),
	}
	if not (arm and joints.RS) then
		-- (not an R6 body: nothing to hold it with)
		held[plr] = { char = char, id = id, none = true }
		return held[plr]
	end
	local golden = (plr:GetAttribute("Mastery") or 1) >= (W.MasteryMax or 100)
	local model, handle, trails = buildSword(def, golden)
	local g = WeaponFX.STANCE.Grip
	handle.CFrame = arm.CFrame * gripAt(g[1], g[2])
	local weld = Instance.new("Weld")
	weld.Name = "Grip"
	weld.Part0, weld.Part1 = arm, handle
	weld.C0 = gripAt(g[1], g[2])
	weld.Parent = handle
	model.Parent = char
	local mem, weights = {}, {}
	for key, joint in pairs(joints) do
		mem[joint] = { rest = joint.Transform }
		weights[key] = 0
	end
	held[plr] = {
		char = char,
		hum = char:FindFirstChildOfClass("Humanoid"),
		id = id,
		def = def,
		model = model,
		handle = handle,
		weld = weld,
		trails = trails,
		trail = trails[1],
		joints = joints,
		shoulder = joints.RS,
		root = joints.Root,
		mem = mem,
		weights = weights, -- how much each joint shows our pose (eased, so nothing snaps)
		golden = golden,
		anim = nil,
		freeze = 0, -- hit-stop: seconds the swing stays frozen
		clock = math.random() * 10,
		swingN = plr:GetAttribute("SwingN"), -- (what was already there isn't a new swing)
		abilityN = plr:GetAttribute("AbilityN"),
	}
	return held[plr]
end

-- start swing `n` of the string for this player (now)
local function startSwing(h, n)
	local kind = h.def and W.Types[h.def.Type]
	local s = kind and kind.Swings[n]
	local keys = WeaponFX.POSES[h.def and h.def.Type or ""]
	if not (s and keys and keys[n]) then
		return
	end
	h.anim = { kind = "swing", t = 0, dur = s.Lock, contact = s.Contact, keys = keys[n], n = n }
	h.freeze = 0
	playAt(kind.Sounds and kind.Sounds.Swing, h.handle, 1.08 - 0.06 * n)
end

-- start the ability (the Whirlwind) at a tier for this player (now)
local function startSpin(h, tierIndex)
	local ab = h.def and h.def.Ability
	local tier = ab and ab.Tiers[math.clamp(tierIndex or 1, 1, #ab.Tiers)]
	if not tier then
		return
	end
	h.anim = { kind = "spin", t = 0, dur = (ab.SpinTime or 0.32) * tier.Spins, spins = tier.Spins }
	h.freeze = 0
	local kind = W.Types[h.def.Type]
	if not playAt(ab.Sound, h.handle) then
		playAt(kind and kind.Sounds and kind.Sounds.Swing, h.handle, 0.85)
	end
end

-- the number after the colon in "count:n"
local function tail(value)
	return tonumber(string.match(tostring(value), ":(%d+)$"))
end

local function setSmear(h, on)
	for _, t in ipairs(h.trails) do
		if t.Enabled ~= on then
			t.Enabled = on
		end
	end
end

-- the pose for this frame: the stance (breathing), or a swing, or the spin -
-- and how much each joint should show it
local function poseFor(h, dt)
	local md = h.hum and h.hum.MoveDirection
	local moving = typeof(md) == "Vector3" and md.Magnitude > 0.1
	h.clock = h.clock + dt
	local breathe = math.sin(h.clock * 2.2)
	local pose = mixPose(WeaponFX.STANCE, WeaponFX.STANCE, 0)
	pose.Root = { pose.Root[1] + 1.5 * breathe, 0, pose.Root[3] }
	pose.RS = { pose.RS[1], pose.RS[2], pose.RS[3] + 3 * breathe }
	pose.LS = { pose.LS[1], pose.LS[2], pose.LS[3] - 3 * breathe }
	-- walking: the legs walk and the body stays square; the arms keep the stance
	local want = { Root = moving and 0.3 or 1, RS = 1, LS = moving and 0.6 or 1, RH = moving and 0 or 1, LH = moving and 0 or 1, Neck = 1 }
	local smearOn, planted = false, true
	local a = h.anim
	if a then
		if h.freeze > 0 then
			h.freeze = h.freeze - dt -- hit-stop: frozen for a blink
		else
			a.t = a.t + dt
		end
		local u = a.t / a.dur
		if u >= 1 then
			h.anim = nil
		elseif a.kind == "swing" then
			local p, weight, smear = WeaponFX.swingPose(a.keys, u, a.contact, pose)
			pose = p
			for key in pairs(want) do
				want[key] = math.max(want[key], weight)
			end
			smearOn = smear
		else
			local p = WeaponFX.spinPose(u, a.spins)
			-- from the stance into the spin and back out of it
			local k = math.min(smooth(u / 0.12), 1 - smooth((u - 0.88) / 0.12))
			local spinPose = p
			pose = mixPose(pose, spinPose, k)
			pose.Root = { pose.Root[1], 0, spinPose.Root[3] } -- (the turn itself goes all the way round)
			for key in pairs(want) do
				want[key] = 1
			end
			smearOn, planted = true, false
		end
	end
	return pose, want, smearOn, planted
end

local function stepOne(plr, h, dt)
	-- awakened (mastery 100): the blade turns gold
	local golden = (plr:GetAttribute("Mastery") or 1) >= (W.MasteryMax or 100)
	if golden ~= h.golden then
		h.golden = golden
		local char, id, def, anim = h.char, h.id, h.def, h.anim
		drop(plr)
		h = hold(plr, char, id, def)
		if h.none then
			return
		end
		h.anim = anim
	end
	-- everyone else's swings and abilities: when their counters change
	if plr ~= Players.LocalPlayer then
		local sn = plr:GetAttribute("SwingN")
		if sn ~= h.swingN then
			h.swingN = sn
			local n = tail(sn)
			if n then
				startSwing(h, n)
			end
		end
		local an = plr:GetAttribute("AbilityN")
		if an ~= h.abilityN then
			h.abilityN = an
			local n = tail(an)
			if n then
				startSpin(h, n)
			end
		end
	end
	local pose, want, smearOn, planted = poseFor(h, dt)
	-- the feet stay on the floor: what the body leans and turns comes back off at the hips
	local root = pose.Root
	if planted then
		pose.RH = { pose.RH[1], pose.RH[2] - root[3], pose.RH[3] + root[1] }
		pose.LH = { pose.LH[1], pose.LH[2] - root[3], pose.LH[3] - root[1] }
	end
	local k = math.min(1, dt * 14)
	for _, key in ipairs(WeaponFX.JOINTS) do
		local joint = h.joints[key]
		if joint then
			local w = h.weights[key] + (want[key] - h.weights[key]) * k
			if want[key] >= 0.999 and h.anim then
				w = want[key] -- (a swing is sharp: no easing into it)
			end
			h.weights[key] = w
			local p = pose[key]
			if w > 0.001 then
				blend(h, joint, CFrame.Angles(rad(p[1]), rad(p[2]), rad(p[3])), w)
			else
				local mem = h.mem[joint]
				if mem.wrote and joint.Transform == mem.wrote then
					joint.Transform = mem.rest
				end
				mem.wrote = nil
			end
		end
	end
	local g = pose.Grip
	h.weld.C0 = gripAt(g[1], g[2])
	setSmear(h, smearOn)
end

local function step(dt)
	dt = math.min(dt or 1 / 60, 0.1)
	for _, plr in ipairs(Players:GetPlayers()) do
		local id = plr:GetAttribute("Weapon")
		local def = id and W.List[id]
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local want = def ~= nil and char ~= nil and fighting(plr) and not (hum and hum.Health <= 0)
		local h = held[plr]
		if h and (not want or h.char ~= char or h.id ~= id or not char.Parent) then
			drop(plr)
			h = nil
		end
		if want and not h then
			h = hold(plr, char, id, def)
		end
		if h and not h.none then
			stepOne(plr, h, dt)
		end
	end
	for plr in pairs(held) do
		if not plr.Parent then
			drop(plr)
		end
	end
end

----------------------------------------------------------------------
-- For CombatClient
----------------------------------------------------------------------
-- your own swing, the moment you press (swing `n` of the string)
function WeaponFX.swing(plr, n)
	local h = held[plr]
	if h and not h.none then
		startSwing(h, n)
	end
end

-- your own ability, the moment you press (at this tier)
function WeaponFX.spin(plr, tierIndex)
	local h = held[plr]
	if h and not h.none then
		startSpin(h, tierIndex)
	end
end

-- hit-stop: your swing freezes for a blink as the blade bites
function WeaponFX.hitStop(plr, seconds)
	local h = held[plr]
	if h and not h.none and h.anim then
		h.freeze = math.max(h.freeze, seconds or 0.05)
	end
end

-- is this player holding a gold (awakened) weapon?
function WeaponFX.isGolden(plr)
	local h = held[plr]
	return h ~= nil and h.golden == true
end

-- how long swing `n` of the weapon's type commits you, and its stamina cost
function WeaponFX.swingInfo(id, n)
	local def = id and W.List[id]
	local kind = def and W.Types[def.Type]
	return kind and kind.Swings[n], kind
end

local started = false
function WeaponFX.start()
	if started then
		return
	end
	started = true
	-- (after Roblox's animations have moved the joints this frame, so ours win)
	RunService.Stepped:Connect(function(_, dt)
		step(dt)
	end)
	-- warm up the sounds, so the first swing isn't silent
	task.spawn(function()
		local list = {}
		for _, kind in pairs(W.Types) do
			for _, name in pairs(kind.Sounds or {}) do
				local s = findSound(name)
				if s then
					list[#list + 1] = s
				end
			end
		end
		for _, def in pairs(W.List) do
			local s = def.Ability and findSound(def.Ability.Sound)
			if s then
				list[#list + 1] = s
			end
		end
		if #list > 0 then
			pcall(function()
				ContentProvider:PreloadAsync(list)
			end)
		end
	end)
end

return WeaponFX
