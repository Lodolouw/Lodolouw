--[[
	WeaponFX  (ModuleScript, parent: ReplicatedStorage, name: "WeaponFX")

	How weapons look, on every screen. The feel we're after: swings with the
	weight of Elden Ring, hits that pop like Hades, and Deepwoken as the proof
	it can be done on a Roblox character. All of it is made in code on the R6
	joints (both arms, both legs, the neck, the whole body) - no uploaded
	animations.

	WHAT MAKES IT MOVE WELL (and not like a fencing dummy):
	  * SPRINGS: no joint ever jumps to a pose. Each one is pulled towards
	    where it should be by a spring, so everything moves smoothly, eases in
	    and out, and settles with a tiny natural overshoot.
	  * OVERLAP: in a swing the body starts first, the arm follows, and the
	    blade comes last, like a whip - the way a real swing travels up
	    through the body.
	  * WEIGHT: every swing winds up, holds for a heartbeat (you can see it
	    coming), then SNAPS through the cut - the blade is at its fastest the
	    moment it lands - and rips on through past it. The dash forward
	    happens with the cut, not on the press.
	  * FLOW: a swing hangs in its follow-through until it lets you go, and
	    the next swing of the string winds up from right there - so a combo
	    is one flowing movement, never a reset to the stance between cuts.
	  * FEET ON THE FLOOR: whatever the body does, it's lowered or raised so
	    a foot stays on the ground - lunges really sink down into them.

	THE PIECES:
	  * THE WEAPON: anyone holding one in a fight (the "Weapon" attribute
	    CombatService sets) has it in their right hand - a chunky 8-bit sword
	    with a glowing edge, built on this screen only. Out of a fight it's
	    put away; while you drink a flask it's tucked away too.
	  * THE STANCE (Elden Ring's one-handed idle): relaxed, a little
	    side-on, the blade held low and forward, breathing, the weight
	    shifting now and then. Walking, your legs and free arm walk and the
	    sword arm keeps the blade steady.
	  * THE STRING: a diagonal slash from high right to low left, a rising
	    backhand from low left to high right, and a leaping overhead
	    finisher that slams down (with a shockwave on the ground). A bold
	    glowing smear follows the blade through each cut.
	  * THE ABILITY (the Iron Sword's Whirlwind): a coil, then the body spins
	    round with the arms out - once, twice or three times, by mastery.
	  * HITS (CombatClient calls these): hit-stop - the whole body stops dead
	    for a blink and shudders as the blade bites (WeaponFX.hitStop) - and
	    a slash mark tearing across whatever you hit, with sparks
	    (WeaponFX.slashMark).
	  * Rolling, jumping and drinking always win: the moment one of Roblox's
	    action animations plays (the roll), the sword code lets go of your
	    body; in the air your legs are left alone; while you drink, your arm
	    and head belong to the drink.
	  * AWAKENED (mastery 100): the blade turns glowing gold.

	Your own swings start the moment you press (CombatClient calls
	WeaponFX.swing / WeaponFX.spin); everyone else's start when their SwingN
	/ AbilityN attribute changes (CombatService sets those).

	Sounds (in SoundService, by name - capitals and spaces don't matter):
	each type's Sounds.Swing ("Sword Swing", played as the cut starts) and
	each ability's Sound ("Whirlwind"). Missing ones are just silent.
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
--         forward and up, y sweeps it across the body (+ = further left), x
--         (-) lifts it out to the side; LS is the mirror (- z is forward)
--   RH/LH the right / left leg at the hip: RH z + swings the right leg
--         forward, LH z - the left one forward
--   Neck  the head: x + looks down, z + turns it left
--   Grip  the sword in the hand: { tilt, roll } (0 tilt: the blade points
--         straight out the front of the fist; -90: in line with the arm)
--   Hop   how far the body lifts off the ground (studs) - the finisher's leap
-- The legs keep their feet planted by themselves: whatever the body leans or
-- turns is taken back off at the hips (except in the spin), and the body is
-- raised or lowered so a foot stays on the floor.
WeaponFX.STANCE = {
	Root = { 4, 0, -12 },
	RS = { -10, -5, 25 },
	LS = { -8, 10, -12 },
	RH = { 0, 0, -6 },
	LH = { 0, 0, -12 },
	Neck = { 0, 0, 10 },
	Grip = { -35, -10 }, -- the blade held low and forward
	Hop = { 0 },
}
WeaponFX.POSES = {
	Sword = {
		{ -- a diagonal slash: from high over the right shoulder down to the low left
			coil = { Root = { -8, 0, -45 }, RS = { -45, -60, 140 }, LS = { -30, 0, -60 }, RH = { 0, 0, -20 }, LH = { 0, 0, -25 }, Neck = { 0, 0, 35 }, Grip = { -115, 0 }, Hop = { 0 } },
			cut = { Root = { 15, 0, 10 }, RS = { 0, 15, 95 }, LS = { -15, 0, 40 }, RH = { 0, 0, -35 }, LH = { 0, 0, -45 }, Neck = { 0, 0, -5 }, Grip = { -75, 0 }, Hop = { 0 } },
			follow = { Root = { 25, 0, 45 }, RS = { 10, 60, 55 }, LS = { -20, 0, 60 }, RH = { 0, 0, -35 }, LH = { 0, 0, -45 }, Neck = { 0, 0, -35 }, Grip = { -75, 20 }, Hop = { 0 } },
		},
		{ -- a rising backhand: from the low left up to high on the right
			coil = { Root = { 15, 0, 40 }, RS = { 15, 70, 45 }, LS = { -15, 0, 30 }, RH = { 0, 0, 5 }, LH = { 0, 0, -20 }, Neck = { 0, 0, -35 }, Grip = { -70, 30 }, Hop = { 0 } },
			cut = { Root = { 10, 0, -5 }, RS = { -10, -10, 105 }, LS = { -20, 0, -40 }, RH = { 0, 0, 35 }, LH = { 0, 0, 25 }, Neck = { 0, 0, 5 }, Grip = { -75, 0 }, Hop = { 0 } },
			follow = { Root = { -5, 0, -50 }, RS = { -5, -20, 120 }, LS = { -25, 0, -70 }, RH = { 0, 0, 35 }, LH = { 0, 0, 25 }, Neck = { -10, 0, 40 }, Grip = { -60, -10 }, Hop = { 0 } },
		},
		{ -- the finisher: a leap with the blade high behind you, and everything comes down with it
			coil = { Root = { -18, 0, -20 }, RS = { -10, 0, 200 }, LS = { 15, 0, -170 }, RH = { 0, 0, -10 }, LH = { 0, 0, -30 }, Neck = { -20, 0, 15 }, Grip = { -60, 0 }, Hop = { 0.8 } },
			cut = { Root = { 38, 0, 0 }, RS = { 0, 5, 95 }, LS = { 15, 0, -95 }, RH = { 0, 0, -40 }, LH = { 0, 0, -50 }, Neck = { 15, 0, 0 }, Grip = { -75, 0 }, Hop = { 0 } },
			follow = { Root = { 32, 0, 0 }, RS = { 0, 5, 78 }, LS = { 10, 0, -60 }, RH = { 0, 0, -40 }, LH = { 0, 0, -50 }, Neck = { 20, 0, 0 }, Grip = { -60, 0 }, Hop = { 0 } },
		},
	},
}
-- the Whirlwind: a coil back, then arms out and the body turns round on top of wide feet
WeaponFX.SPIN_COIL = { Root = { 10, 0, -60 }, RS = { -10, -90, 70 }, LS = { -60, 0, -20 }, RH = { -10, 0, -10 }, LH = { -10, 0, -20 }, Neck = { 0, 0, 40 }, Grip = { -85, 0 }, Hop = { 0 } }
WeaponFX.SPIN = { Root = { 12, 0, 0 }, RS = { -10, -85, 95 }, LS = { -80, 0, 0 }, RH = { -12, 0, 0 }, LH = { -12, 0, 0 }, Neck = { 0, 0, 0 }, Grip = { -85, 0 }, Hop = { 0 } }
WeaponFX.JOINTS = { "Root", "RS", "LS", "RH", "LH", "Neck" }
-- the springs: how quickly each part follows (the first number) and how much
-- it's allowed to overshoot (the second: 1 = none, lower = more bounce)
WeaponFX.SPRINGS = {
	idle = { Root = { 10, 1 }, RS = { 11, 1 }, LS = { 9, 1 }, RH = { 12, 1 }, LH = { 12, 1 }, Neck = { 9, 1 }, Grip = { 12, 1 }, Hop = { 14, 1 } },
	swing = { Root = { 26, 0.8 }, RS = { 42, 0.72 }, LS = { 18, 0.6 }, RH = { 30, 0.9 }, LH = { 30, 0.9 }, Neck = { 20, 0.85 }, Grip = { 52, 0.6 }, Hop = { 26, 0.8 } },
}
-- overlap: in a swing the body moves first, then the arm, and the blade comes
-- last, like a whip (seconds ahead of the arm; - is behind it)
WeaponFX.OVERLAP = { Root = 0.03, RH = 0.025, LH = 0.025, Hop = 0.025, Neck = 0.02, RS = 0, LS = -0.015, Grip = -0.025 }
-- (a spring always trails what it chases by about 2 x bounce / speed seconds,
-- so each part aims that much further ahead to arrive when it should)
WeaponFX.LEAD = {}
for key, k in pairs(WeaponFX.SPRINGS.swing) do
	WeaponFX.LEAD[key] = (WeaponFX.OVERLAP[key] or 0) + 2 * k[2] / k[1]
end
WeaponFX.SETTLE = 0.3 -- after a swing lets you go: the time it takes to drift back into the stance
WeaponFX.GROUND = -3 -- where the floor is, below the middle of the body (R6: the feet at rest)

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
	local s = 1.4
	return 1 + (s + 1) * t * t * t + s * t * t
end
local function copyPose(p)
	local out = {}
	for key, a in pairs(p) do
		out[key] = table.clone(a)
	end
	return out
end
local function mixPose(p, q, t)
	local out = {}
	for key, a in pairs(p) do
		local b = q[key] or a
		local m = {}
		for i = 1, #a do
			m[i] = a[i] + ((b[i] or a[i]) - a[i]) * t
		end
		out[key] = m
	end
	return out
end
WeaponFX.mixPose = mixPose

-- The moments of a swing, in seconds from the press, from its Config entry
-- (Lock: how long it commits you; Contact: how far into that the blade lands -
-- the same moment the server cuts)
function WeaponFX.swingMoments(swing)
	local lock = swing and swing.Lock or 0.5
	local contact = lock * math.clamp(swing and swing.Contact or 0.4, 0.15, 0.8)
	return {
		coil = contact * 0.65, -- wound up by here...
		hold = contact * 0.82, -- ...held for a heartbeat (you can see it coming)...
		contact = contact, -- ...SNAP: the blade lands here...
		follow = contact + (lock - contact) * 0.45, -- ...ripped all the way through by here...
		lock = lock, -- ...hanging in the follow-through until you can act again...
		done = lock + WeaponFX.SETTLE, -- ...then drifting back into the stance
	}
end

-- A swing `t` seconds after the press, winding up from `from` (wherever the
-- body was when it started - the stance, or the last swing's follow-through)
-- and settling back into `base` (the stance). Gives the whole pose, how much
-- of it shows over whatever the body was doing (0 to 1), whether the blade is
-- cutting (the smear shows then), and whether it's over.
-- So chained swings flow into each other: a swing hangs in its
-- follow-through until it lets you go, and the next one winds up from there.
function WeaponFX.swingPose(keys, t, swing, base, from)
	base = base or WeaponFX.STANCE
	local m = WeaponFX.swingMoments(swing)
	t = math.clamp(t, 0, m.done)
	local pose
	if t < m.coil then
		pose = mixPose(from or base, keys.coil, smooth(t / m.coil))
	elseif t < m.hold then
		-- the held heartbeat: creeping a touch further back, full of tension
		pose = mixPose(keys.coil, keys.cut, -0.06 * smooth((t - m.coil) / (m.hold - m.coil)))
	elseif t < m.contact then
		local held = mixPose(keys.coil, keys.cut, -0.06)
		pose = mixPose(held, keys.cut, snap((t - m.hold) / (m.contact - m.hold)))
	elseif t < m.follow then
		pose = mixPose(keys.cut, keys.follow, overshoot((t - m.contact) / (m.follow - m.contact)))
	elseif t < m.lock then
		-- hanging in the follow-through (the weight of it), only just starting to recover
		pose = mixPose(keys.follow, base, 0.12 * smooth((t - m.follow) / math.max(m.lock - m.follow, 0.01)))
	else
		pose = mixPose(mixPose(keys.follow, base, 0.12), base, smooth((t - m.lock) / (m.done - m.lock)))
	end
	local weight = smooth(t / math.max(m.coil * 0.4, 0.01))
	local cutting = t >= m.hold - 0.01 and t <= m.contact + (m.follow - m.contact) * 0.6
	return pose, weight, cutting, t >= m.done
end

-- The Whirlwind `u` of the way through `spins` spins, from `from` (where the
-- body was) back to `base` (the stance): a quick coil, then the body turns
-- all the way round each spin (the same way a first slash cuts: to the
-- left), then it settles. Gives the pose and the extra turn (degrees) that
-- goes on top of it.
function WeaponFX.spinPose(u, spins, base, from)
	base = base or WeaponFX.STANCE
	u = math.clamp(u, 0, 1)
	local pose
	if u < 0.12 then
		pose = mixPose(from or base, WeaponFX.SPIN_COIL, easeOut(u / 0.12))
	elseif u < 0.88 then
		pose = mixPose(WeaponFX.SPIN_COIL, WeaponFX.SPIN, smooth((u - 0.12) / 0.1))
	else
		pose = mixPose(WeaponFX.SPIN, base, smooth((u - 0.88) / 0.12))
	end
	local t = math.clamp((u - 0.12) / 0.76, 0, 1)
	local eased = t < 0.5 and 2 * t * t or 1 - 2 * (1 - t) * (1 - t)
	return pose, 360 * spins * (0.7 * t + 0.3 * eased)
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
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, see), NumberSequenceKeypoint.new(0.55, 0.65), NumberSequenceKeypoint.new(1, 1) })
		trail.LightEmission = 1
		trail.Lifetime = life
		trail.MinLength = 0.02
		trail.WidthScale = NumberSequence.new(1, 0.35)
		trail.Enabled = false
		trail.Parent = blade
		return trail
	end
	local trails = {
		smear("SwingTrail", 1.2, -2.4, golden and GOLD or GLOW, 0, 0.2),
		smear("SwingGlow", 2, -3.3, golden and GOLD or Color3.fromRGB(120, 200, 255), 0.5, 0.28),
	}
	return model, handle, trails, blade
end

----------------------------------------------------------------------
-- Hits: the slash mark ripping across what you hit, and the finisher's slam
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
	for i = 1, heavy and 2 or 1 do
		local bar = Instance.new("Part")
		bar.Name = "Slash"
		bar.Anchored, bar.CanCollide, bar.CanTouch, bar.CanQuery, bar.CastShadow = true, false, false, false, false
		bar.Material = Enum.Material.Neon
		bar.Color = i == 1 and Color3.fromRGB(255, 255, 255) or color
		local long = heavy and 11 or 7
		bar.Size = Vector3.new(0.35, 0.35, 1)
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

-- the finisher hitting the floor: a flat ring bursting out and dust
function WeaponFX.groundSlam(position, golden)
	if typeof(position) ~= "Vector3" then
		return
	end
	local ring = Instance.new("Part")
	ring.Name = "SlamRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored, ring.CanCollide, ring.CanTouch, ring.CanQuery, ring.CastShadow = true, false, false, false, false
	ring.Material = Enum.Material.Neon
	ring.Color = golden and GOLD or GLOW
	ring.Size = Vector3.new(0.15, 1, 1)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(200, 200, 210))
	dust.Size = NumberSequence.new(1.2, 3.5)
	dust.Transparency = NumberSequence.new(0.5, 1)
	dust.Lifetime = NumberRange.new(0.3, 0.5)
	dust.Speed = NumberRange.new(10, 18)
	dust.SpreadAngle = Vector2.new(80, 10)
	dust.Drag = 6
	dust.Rate = 0
	dust.Parent = ring
	dust:Emit(16)
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local k = (os.clock() - t0) / 0.3
		if k >= 1 or not ring.Parent then
			conn:Disconnect()
			ring:Destroy()
			return
		end
		local r = 2 + 12 * (1 - (1 - k) * (1 - k))
		ring.Size = Vector3.new(0.15, r, r)
		ring.Transparency = k
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

-- let go of one joint: back where it rests, if we were the last to move it
local function letGo(h, joint)
	local mem = h.mem[joint]
	if mem and joint.Parent and mem.wrote and joint.Transform == mem.wrote then
		joint.Transform = mem.rest
	end
	if mem then
		mem.wrote = nil
	end
end

local function release(h)
	for joint in pairs(h.mem) do
		letGo(h, joint)
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
	local model, handle, trails, blade = buildSword(def, golden)
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
	-- the springs start where the stance is
	local springs = {}
	for key, value in pairs(WeaponFX.STANCE) do
		springs[key] = { p = table.clone(value), v = table.create(#value, 0) }
	end
	held[plr] = {
		char = char,
		hum = char:FindFirstChildOfClass("Humanoid"),
		id = id,
		def = def,
		model = model,
		handle = handle,
		blade = blade,
		weld = weld,
		trails = trails,
		trail = trails[1],
		joints = joints,
		shoulder = joints.RS,
		root = joints.Root,
		mem = mem,
		weights = weights, -- how much each joint shows our pose (eased, so nothing snaps)
		springs = springs,
		golden = golden,
		anim = nil,
		freeze = 0, -- hit-stop: seconds the swing stays frozen
		clock = math.random() * 10,
		swingN = plr:GetAttribute("SwingN"), -- (what was already there isn't a new swing)
		abilityN = plr:GetAttribute("AbilityN"),
	}
	return held[plr]
end

-- where the body is right now (the springs), as a pose
local function whereNow(h)
	local pose = {}
	for key, s in pairs(h.springs) do
		pose[key] = table.clone(s.p)
	end
	return pose
end

-- start swing `n` of the string for this player (now)
local function startSwing(h, n)
	local kind = h.def and W.Types[h.def.Type]
	local s = kind and kind.Swings[n]
	local keys = WeaponFX.POSES[h.def and h.def.Type or ""]
	if not (s and keys and keys[n]) then
		return
	end
	h.anim = { kind = "swing", t = 0, swing = s, m = WeaponFX.swingMoments(s), keys = keys[n], n = n, sound = kind.Sounds and kind.Sounds.Swing, from = h.springs and whereNow(h) }
	h.freeze = 0
end

-- start the ability (the Whirlwind) at a tier for this player (now)
local function startSpin(h, tierIndex)
	local ab = h.def and h.def.Ability
	local tier = ab and ab.Tiers[math.clamp(tierIndex or 1, 1, #ab.Tiers)]
	if not tier then
		return
	end
	-- (a spin takes a moment longer than its spins: the coil and the settle)
	h.anim = { kind = "spin", t = 0, dur = (ab.SpinTime or 0.32) * tier.Spins / 0.76, spins = tier.Spins, from = h.springs and whereNow(h) }
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

-- a spring pulling `s` towards `target`
local function spring(s, target, omega, zeta, dt)
	local steps = math.max(1, math.ceil(dt * 240))
	local hstep = dt / steps
	for _ = 1, steps do
		for i = 1, #target do
			local a = omega * omega * (target[i] - s.p[i]) - 2 * zeta * omega * s.v[i]
			s.v[i] = s.v[i] + a * hstep
			s.p[i] = s.p[i] + s.v[i] * hstep
		end
	end
end
WeaponFX.spring = spring

-- is one of Roblox's action animations playing on this character (the roll)?
local ACTION = {}
pcall(function()
	for _, name in ipairs({ "Action", "Action2", "Action3", "Action4" }) do
		ACTION[Enum.AnimationPriority[name]] = true
	end
end)
local function actionPlaying(h)
	local animator = h.hum and h.hum:FindFirstChildOfClass("Animator")
	if not animator then
		return false
	end
	local ok, tracks = pcall(function()
		return animator:GetPlayingAnimationTracks()
	end)
	if not ok or type(tracks) ~= "table" then
		return false
	end
	for _, track in ipairs(tracks) do
		local fine, pri, weight = pcall(function()
			return track.Priority, track.WeightTarget
		end)
		-- (a track played at no weight is just being warmed up: it doesn't count)
		if fine and ACTION[pri] and track.IsPlaying ~= false and (tonumber(weight) or 1) > 0.05 then
			return true
		end
	end
	return false
end

local function inAir(h)
	local ok, state = pcall(function()
		return h.hum:GetState()
	end)
	return ok and (state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping)
end

-- where a foot is (the bottom of a leg) below the middle of the body, for a
-- body turned/leaned by `root` and a leg turned by `leg`
local function footY(h, hipKey, root, leg)
	local hip = h.joints[hipKey]
	local rj = h.root
	if not (hip and rj) then
		return WeaponFX.GROUND
	end
	local torso = rj.C0 * CFrame.Angles(rad(root[1]), rad(root[2]), rad(root[3])) * rj.C1:Inverse()
	local limb = torso * hip.C0 * CFrame.Angles(rad(leg[1]), rad(leg[2]), rad(leg[3])) * hip.C1:Inverse()
	return (limb * Vector3.new(0, -1, 0)).Y
end

-- the pose this frame (before the springs): the stance, a swing or the spin,
-- how much each joint should show it, and what's going on
local function targetFor(plr, h, dt)
	local md = h.hum and h.hum.MoveDirection
	local moving = typeof(md) == "Vector3" and md.Magnitude > 0.1
	h.clock = h.clock + dt
	-- the stance, breathing, and slowly shifting its weight from foot to foot
	local breathe = math.sin(h.clock * 1.7)
	local shift = 0.75 * math.sin(h.clock * 0.6) + 0.25 * math.sin(h.clock * 1.35 + 1.1)
	local stance = copyPose(WeaponFX.STANCE)
	stance.Root[1] = stance.Root[1] + 1.2 * breathe
	stance.Root[2] = stance.Root[2] + 1.2 * shift
	stance.Root[3] = stance.Root[3] + 3 * shift
	stance.RS[3] = stance.RS[3] + 1.5 * math.sin(h.clock * 1.7 - 0.6)
	stance.LS[3] = stance.LS[3] - 2 * math.sin(h.clock * 1.7 - 0.9)
	stance.Neck[1] = stance.Neck[1] - 1 * math.sin(h.clock * 1.7 - 0.4)
	stance.Neck[3] = stance.Neck[3] - 3 * shift
	stance.Grip[1] = stance.Grip[1] + 1.5 * math.sin(h.clock * 1.7 - 0.8)
	local want = { Root = 1, RS = 1, LS = 1, RH = 1, LH = 1, Neck = 1 }
	if moving then
		-- walking: the legs, the free arm and the body walk; the sword arm
		-- keeps the blade steady, letting a little of the walk's own arm swing
		-- through so it sways in step
		want.Root, want.LS, want.RH, want.LH, want.Neck, want.RS = 0, 0, 0, 0, 0.3, 0.82
	end
	if inAir(h) then
		want.Root, want.RH, want.LH = 0, 0, 0
		want.LS = math.min(want.LS, 0.5)
	end
	local drinking = h.char:GetAttribute("Drinking") ~= nil
	if drinking then
		want.RS, want.Neck, want.LS = 0, 0, 0 -- (your arm and head belong to the drink)
	end
	local rolling = actionPlaying(h)
	if rolling then
		-- the roll (or any action animation) wins: let go of everything, stop swinging
		for key in pairs(want) do
			want[key] = 0
		end
		h.anim = nil
	end
	local mode, turn, cutting = "idle", 0, false
	local a = h.anim
	if a then
		mode = "swing"
		if h.freeze > 0 then
			h.freeze = h.freeze - dt -- hit-stop: frozen for a blink
		else
			a.t = a.t + dt
		end
		if a.kind == "swing" then
			local m = a.m
			local _, weight, smear, over = WeaponFX.swingPose(a.keys, a.t, a.swing, stance, a.from)
			if over then
				h.anim = nil
				mode = "idle"
			else
				-- the overlap: each part a little ahead of or behind the arm
				local pose = {}
				for key in pairs(stance) do
					local p = WeaponFX.swingPose(a.keys, a.t + (WeaponFX.LEAD[key] or 0), a.swing, stance, a.from)
					pose[key] = p[key]
				end
				stance = pose
				if a.t < m.lock then
					-- committed: the whole body is in it (after that, walking takes the legs back)
					for key in pairs(want) do
						want[key] = math.max(want[key], weight)
					end
					if drinking then
						want.RS, want.Neck = 0, 0
					end
				end
				cutting = smear
				if not a.whooshed and a.t >= m.hold - 0.03 then
					a.whooshed = true
					-- the whoosh, as the cut starts (a touch different every time, so a string never sounds canned)
					playAt(a.sound, h.handle, (1.08 - 0.06 * a.n) * (0.96 + 0.08 * math.random()))
				end
				if a.n == 3 and not a.slammed and a.t >= m.contact then
					a.slammed = true
					a.slamNow = true -- (the finisher hits the floor: see stepOne)
				end
			end
		else
			local u = a.t / a.dur
			if u >= 1 then
				h.anim = nil
				mode = "idle"
			else
				local pose
				pose, turn = WeaponFX.spinPose(u, a.spins, stance, a.from)
				stance = pose
				for key in pairs(want) do
					want[key] = 1
				end
				mode, cutting = "spin", u > 0.12 and u < 0.9
			end
		end
	end
	return stance, want, mode, turn, cutting, drinking, rolling
end

local function stepOne(plr, h, dt)
	-- awakened (mastery 100): the blade turns gold
	local golden = (plr:GetAttribute("Mastery") or 1) >= (W.MasteryMax or 100)
	if golden ~= h.golden then
		local char, id, def, anim, springs, weights, clock, freeze = h.char, h.id, h.def, h.anim, h.springs, h.weights, h.clock, h.freeze
		drop(plr)
		h = hold(plr, char, id, def)
		if h.none then
			return
		end
		h.anim, h.springs, h.weights, h.clock, h.freeze = anim, springs, weights, clock, freeze
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
	local target, want, mode, turn, cutting, drinking, rolling = targetFor(plr, h, dt)
	-- the springs: every part eases towards its target (snappier in a swing).
	-- In hit-stop everything stops dead and just shudders.
	local frozen = h.freeze > 0 and h.anim ~= nil
	local set = WeaponFX.SPRINGS[mode == "idle" and "idle" or "swing"]
	for key, s in pairs(h.springs) do
		local goal = target[key]
		if goal and not frozen then
			local k = set[key] or set.RS
			spring(s, goal, k[1], k[2], dt)
		end
	end
	-- the pose to show: the springs, the spin's turn on top, feet kept on the floor
	local pose = {}
	for key, s in pairs(h.springs) do
		pose[key] = s.p
	end
	if frozen then
		-- the shudder: the arm and blade judder as the blade bites
		pose.RS = { pose.RS[1], pose.RS[2], pose.RS[3] + (math.random() - 0.5) * 5 }
		pose.Grip = { pose.Grip[1] + (math.random() - 0.5) * 6, pose.Grip[2] }
	end
	local lean, twist = pose.Root[1], pose.Root[3]
	local root = { lean, pose.Root[2], twist + turn }
	-- (the hips take back the body's own lean and turn so the feet stay put;
	-- the spin's turn isn't taken back - the legs go round with it)
	local rh = { pose.RH[1], pose.RH[2] - twist, pose.RH[3] + lean }
	local lh = { pose.LH[1], pose.LH[2] - twist, pose.LH[3] - lean }
	local legsOn = math.min(h.weights.RH, h.weights.Root)
	local up = pose.Hop[1]
	if legsOn > 0.01 then
		local low = math.min(footY(h, "RH", root, rh), footY(h, "LH", root, lh))
		up = up + (WeaponFX.GROUND - low) * legsOn
	end
	local show = {
		Root = CFrame.new(0, 0, up) * CFrame.Angles(rad(root[1]), rad(root[2]), rad(root[3])),
		RS = CFrame.Angles(rad(pose.RS[1]), rad(pose.RS[2]), rad(pose.RS[3])),
		LS = CFrame.Angles(rad(pose.LS[1]), rad(pose.LS[2]), rad(pose.LS[3])),
		RH = CFrame.Angles(rad(rh[1]), rad(rh[2]), rad(rh[3])),
		LH = CFrame.Angles(rad(lh[1]), rad(lh[2]), rad(lh[3])),
		Neck = CFrame.Angles(rad(pose.Neck[1]), rad(pose.Neck[2]), rad(pose.Neck[3])),
	}
	-- how much each joint shows it: a swing takes over quickly (but never
	-- snaps), a roll takes the body back even quicker, everything else eases
	for _, key in ipairs(WeaponFX.JOINTS) do
		local joint = h.joints[key]
		if joint then
			local w = h.weights[key]
			local goal = want[key]
			local rate = rolling and 40 or (goal < w and 16 or (h.anim and 30 or 8))
			w = w + (goal - w) * math.min(1, dt * rate)
			if math.abs(goal - w) < 0.002 then
				w = goal
			end
			h.weights[key] = w
			if w > 0.001 then
				blend(h, joint, show[key], w)
			else
				letGo(h, joint)
			end
		end
	end
	local g = pose.Grip
	h.weld.C0 = gripAt(g[1], g[2])
	setSmear(h, cutting)
	-- tucked away while you drink (the potion's in that hand)
	local wantParent = (not drinking) and h.char or nil
	if h.model.Parent ~= wantParent then
		h.model.Parent = wantParent
	end
	-- the finisher hits the floor: a shockwave where the blade lands
	local a = h.anim
	if a and a.slamNow then
		a.slamNow = false
		local ok, tip = pcall(function()
			return h.blade.CFrame * Vector3.new(0, 0, -2.2)
		end)
		local hrp = h.char:FindFirstChild("HumanoidRootPart")
		if ok and hrp then
			WeaponFX.groundSlam(Vector3.new(tip.X, hrp.Position.Y + WeaponFX.GROUND + 0.1, tip.Z), h.golden)
		end
	end
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

-- hit-stop: your swing freezes for a blink (and shudders) as the blade bites
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
