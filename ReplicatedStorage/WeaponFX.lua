--[[
	WeaponFX  (ModuleScript, parent: ReplicatedStorage, name: "WeaponFX")

	How weapons look, on every screen. The feel we're after: swings with the
	weight of Elden Ring, hits that pop like Hades, and Deepwoken as the proof
	it can be done on a Roblox character.

	TWO WAYS A WEAPON MOVES:
	  * UPLOADED ANIMATIONS (a type's Config Animations: made in Blender for
	    R6 - Tools/Animations - and published from Studio): the idle standing
	    still, and each swing of the string. Your own screen plays them on
	    your own character and Roblox sends them on to everyone else's; every
	    screen then leaves the body (and the blade: the Grip is a Motor6D) to
	    them. The smear and the whoosh follow the swing's own time (its Cut and
	    Through markers: ANIM_CUTS).
	  * MADE IN CODE, on the R6 joints (both arms, both legs, the neck, the
	    whole body): walking with the sword, the Whirlwind, and any swing
	    whose animation isn't there or hasn't loaded (yours, or someone
	    else's that doesn't arrive within REMOTE_WAIT) - so nothing ever
	    swings as an empty arm. Everything below is about this part.

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
	    CombatService sets) has it in their right hand, built on this screen
	    only: its 3D model (the weapon's Model in Config - a model in
	    ReplicatedStorage from Studio's 3D Importer, held at its grip:
	    MODELS), or else a chunky 8-bit sword with a glowing edge made of
	    parts. Out of a fight it's put away; while you drink a flask it's
	    tucked away too.
	  * THE STANCE (Elden Ring's one-handed idle): relaxed, a little
	    side-on, the blade held low and forward, breathing, the weight
	    shifting now and then. Walking, your legs and free arm walk and the
	    sword arm keeps the blade steady.
	  * THE STRING (uploaded): a flat forehand, right to left at chest
	    height; a rising backhand, low left to high right; and a leaping spin
	    finisher, all the way round. (Made in code, if they're missing: a
	    diagonal slash, the backhand, and a leaping overhead chop that slams
	    down with a shockwave.) A bold glowing smear follows the blade
	    through each cut.
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
	  * AWAKENED (mastery 100): the blade turns glowing gold (a 3D model: its
	    glowing pixels and smear turn gold, and it gives off a golden light).

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
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local W = Config.Weapons or { List = {}, Types = {}, MasteryMax = 100 }

local WeaponFX = {}
local rad = math.rad

-- the weapon abilities' uploaded animations (ReplicatedStorage/AssetIds): while
-- one plays it has the body and the weapon in the hand, like a swing does
local ABILITY_IDS = {}
pcall(function()
	local m = ReplicatedStorage:WaitForChild("AssetIds", 5)
	local ids = m and require(m)
	for _, id in pairs(ids and ids.Animations or {}) do
		local n = tonumber(string.match(tostring(id), "(%d+)%s*$"))
		if n then
			ABILITY_IDS[n] = true
		end
	end
end)

-- the weapon types' baked animations (ReplicatedStorage/WeaponClips, made by
-- Tools/Animations/export_types.py): see "Clips" below
local CLIPS = nil
pcall(function()
	local m = ReplicatedStorage:WaitForChild("WeaponClips", 5)
	CLIPS = m and require(m)
end)

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

-- THE OTHER TYPES (gauntlets, hammer, daggers, scythe, katana) don't use poses
-- here: they play baked animations made the way the sword's are (see "Clips").

-- a weapon's stance (the sword's: the other types play clips)
local function stanceOf(def)
	return WeaponFX.STANCE
end
WeaponFX.stanceOf = stanceOf
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
local GRIP_HAND = CFrame.new(0, -1, 0) -- (the Grip's C0 when an animation holds the blade)

----------------------------------------------------------------------
-- Sounds (by name from SoundService; capitals and spaces don't matter)
----------------------------------------------------------------------
local function squash(s)
	return string.lower((string.gsub(tostring(s), "[%s_%-]", "")))
end
local soundCache = {}
local function findSound(name)
	if type(name) == "table" then
		-- (a list: the first one that's there - a new sound, then the ones
		-- it falls back on until it's uploaded)
		for _, n in ipairs(name) do
			local s = findSound(n)
			if s then
				return s
			end
		end
		return nil
	end
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
local function playAt(name, parent, pitch, volume)
	local template = findSound(name)
	if not (template and parent and parent.Parent) then
		return false
	end
	local s = template:Clone()
	s.PlaybackSpeed = template.PlaybackSpeed * (pitch or 1)
	s.Volume = (tonumber(template.Volume) or 0.5) * (volume or 1)
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

-- THE OTHER TYPES as chunky blocks, the same way: a Handle that's held, the
-- rest welded to it along its -Z. Each gives back the model, the handle, its
-- two smears and the part they follow.
local function blockKit(def, golden)
	local c = def.Colors or {}
	local model = Instance.new("Model")
	model.Name = "HeldWeapon"
	local kit = {
		model = model,
		metal = golden and GOLD or (c.Blade or Color3.fromRGB(192, 203, 220)),
		shine = golden and Enum.Material.Neon or Enum.Material.SmoothPlastic,
		accent = c.Guard or GOLD,
		grip = c.Grip or Color3.fromRGB(115, 62, 57),
		glow = golden and GOLD or GLOW,
	}
	function kit.piece(name, size, offset, color, material, parentModel)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = false, false, false, false
		p.Massless = true
		if kit.handle then
			p.CFrame = kit.handle.CFrame * offset
			local weld = Instance.new("Weld")
			weld.Part0, weld.Part1 = kit.handle, p
			weld.C0 = offset
			weld.Parent = p
		end
		p.Parent = parentModel or model
		return p
	end
	-- a smear following `part` between two points on it (its own space)
	function kit.smear(part, name, from, to, color, see, life)
		local a0 = Instance.new("Attachment")
		a0.Name = name .. "Base"
		a0.Position = from
		a0.Parent = part
		local a1 = Instance.new("Attachment")
		a1.Name = name .. "Tip"
		a1.Position = to
		a1.Parent = part
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
		trail.Parent = part
		return trail
	end
	function kit.trails(part, from, to, wideFrom, wideTo)
		return {
			kit.smear(part, "SwingTrail", from, to, kit.glow, 0, 0.2),
			kit.smear(part, "SwingGlow", wideFrom or from, wideTo or to, golden and GOLD or Color3.fromRGB(120, 200, 255), 0.5, 0.28),
		}
	end
	return kit
end

local BUILDERS = {}
-- gauntlets: a big blocky glove round the fist (the second one, on the left
-- hand, is made the same way: see OFFHAND)
function BUILDERS.Fists(def, golden)
	local k = blockKit(def, golden)
	k.handle = k.piece("Handle", Vector3.new(1.2, 1.2, 1.25), CFrame.new(), k.metal, k.shine)
	k.piece("Cuff", Vector3.new(1.3, 1.3, 0.35), CFrame.new(0, 0, 0.7), k.accent)
	k.piece("Knuckles", Vector3.new(1.25, 0.35, 0.5), CFrame.new(0, 0.1, -0.55) * CFrame.new(0, 0, 0), k.glow, Enum.Material.Neon)
	return k.model, k.handle, k.trails(k.handle, Vector3.new(0, 0, 0.6), Vector3.new(0, 0, -0.8)), k.handle
end
-- the hammer: a long handle and a big blocky head across the end of it
function BUILDERS.Hammer(def, golden)
	local k = blockKit(def, golden)
	k.handle = k.piece("Handle", Vector3.new(0.4, 0.4, 1.2), CFrame.new(), k.grip)
	k.piece("Shaft", Vector3.new(0.34, 0.34, 2.8), CFrame.new(0, 0, -1.9), k.grip)
	k.piece("Pommel", Vector3.new(0.55, 0.55, 0.45), CFrame.new(0, 0, 0.75), k.accent)
	local head = k.piece("Head", Vector3.new(2.4, 1.4, 1.4), CFrame.new(0, 0, -3.8), k.metal, k.shine)
	k.piece("FaceL", Vector3.new(0.3, 1.6, 1.6), CFrame.new(-1.25, 0, -3.8), k.accent)
	k.piece("FaceR", Vector3.new(0.3, 1.6, 1.6), CFrame.new(1.25, 0, -3.8), k.accent)
	k.piece("Band", Vector3.new(2.5, 0.3, 1.5), CFrame.new(0, 0, -3.8), k.glow, Enum.Material.Neon)
	return k.model, k.handle, k.trails(head, Vector3.new(0, 0, 0.8), Vector3.new(0, 0, -0.8), Vector3.new(0, 0, 2), Vector3.new(0, 0, -1)), head
end
-- a dagger: a short blade (one in each hand: see OFFHAND)
function BUILDERS.Daggers(def, golden)
	local k = blockKit(def, golden)
	k.handle = k.piece("Handle", Vector3.new(0.3, 0.3, 0.7), CFrame.new(), k.grip)
	k.piece("Guard", Vector3.new(0.9, 0.25, 0.25), CFrame.new(0, 0, -0.45), k.accent)
	local blade = k.piece("Blade", Vector3.new(0.22, 0.5, 1.7), CFrame.new(0, 0, -1.4), k.metal, k.shine)
	k.piece("Edge", Vector3.new(0.24, 0.12, 1.6), CFrame.new(0, 0.22, -1.4), k.glow, Enum.Material.Neon)
	k.piece("Tip", Vector3.new(0.22, 0.3, 0.3), CFrame.new(0, 0.05, -2.35), k.metal, k.shine)
	return k.model, k.handle, k.trails(blade, Vector3.new(0, 0, 0.6), Vector3.new(0, 0, -0.9), Vector3.new(0, 0, 0.9), Vector3.new(0, 0, -1.2)), blade
end
-- the scythe: a long pole and a curved blade off its end
function BUILDERS.Scythe(def, golden)
	local k = blockKit(def, golden)
	k.handle = k.piece("Handle", Vector3.new(0.34, 0.34, 1.2), CFrame.new(), k.grip)
	k.piece("Pole", Vector3.new(0.3, 0.3, 5.4), CFrame.new(0, 0, -2.4), k.grip)
	k.piece("Butt", Vector3.new(0.45, 0.45, 0.4), CFrame.new(0, 0, 0.75), k.accent)
	k.piece("Collar", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 0, -5.1), k.accent)
	-- the blade sweeps out to the right (+X) and curves back towards you
	local blade = k.piece("Blade", Vector3.new(2.4, 0.18, 0.7), CFrame.new(1.3, 0, -5.1), k.metal, k.shine)
	k.piece("Blade2", Vector3.new(1.4, 0.18, 0.55), CFrame.new(2.9, 0, -4.75) * CFrame.Angles(0, math.rad(-28), 0), k.metal, k.shine)
	k.piece("Point", Vector3.new(0.7, 0.18, 0.35), CFrame.new(3.75, 0, -4.2) * CFrame.Angles(0, math.rad(-55), 0), k.metal, k.shine)
	k.piece("Edge", Vector3.new(2.4, 0.2, 0.14), CFrame.new(1.3, 0, -4.78), k.glow, Enum.Material.Neon)
	return k.model, k.handle, k.trails(blade, Vector3.new(-1.1, 0, 0), Vector3.new(2.4, 0, 0.6), Vector3.new(-1.1, 0, 0.2), Vector3.new(2.9, 0, 0.9)), blade
end
-- the katana: a long, slim blade, a round guard, a wrapped grip
function BUILDERS.Katana(def, golden)
	local k = blockKit(def, golden)
	k.handle = k.piece("Handle", Vector3.new(0.3, 0.34, 1.3), CFrame.new(0, 0, 0.1), k.grip)
	k.piece("Guard", Vector3.new(0.85, 0.85, 0.16), CFrame.new(0, 0, -0.62), k.accent)
	local blade = k.piece("Blade", Vector3.new(0.16, 0.42, 4.4), CFrame.new(0, 0, -2.95), k.metal, k.shine)
	k.piece("Edge", Vector3.new(0.18, 0.1, 4.3), CFrame.new(0, 0.2, -2.95), k.glow, Enum.Material.Neon)
	k.piece("Tip", Vector3.new(0.16, 0.3, 0.4), CFrame.new(0, 0.1, -5.3) * CFrame.Angles(math.rad(-15), 0, 0), k.metal, k.shine)
	return k.model, k.handle, k.trails(blade, Vector3.new(0, 0, 1.2), Vector3.new(0, 0, -2.1), Vector3.new(0, 0, 1.8), Vector3.new(0, 0, -2.6)), blade
end
-- the types that hold a second one in the left hand, and how it's held
WeaponFX.OFFHAND = { Fists = { -90, 0 }, Daggers = { -90, 0 } } -- (the clips carry their own: WeaponClips' Offhand)

-- the 3D weapons (Tools/Weapons: pixel sprites made 3D in Blender, imported
-- into ReplicatedStorage with Studio's 3D Importer): how long each is (studs,
-- pommel to tip), where its grip's middle is - how far up from the pommel
-- (0 to 1) and across (0 to 1) - and the colour it glows (its glowing pixels,
-- made Neon, and its smear). Straight from the sprites (Tools/Weapons/sprites.py).
-- Roll turns it over round the blade (degrees): Tidefang's a curved sabre,
-- so it swings with the back of its curve leading. (To fix one by hand in
-- Studio, give its model in ReplicatedStorage a number attribute GripRoll
-- - 180 turns it over - or a true/false GripFlip - the tip the other way.)
WeaponFX.MODELS = {
	IronWarden = { Length = 5.0, GripUp = 0.16, GripAcross = 0.5, Glow = GLOW },
	EmberCleaver = { Length = 5.2, GripUp = 0.163, GripAcross = 0.5, Glow = Color3.fromRGB(255, 120, 30) },
	Tidefang = { Length = 5.1, GripUp = 0.157, GripAcross = 0.5, Glow = Color3.fromRGB(80, 255, 240), Roll = 180 },
	Voidstar = { Length = 5.8, GripUp = 0.13, GripAcross = 0.5, Glow = Color3.fromRGB(255, 170, 250) },
}

-- the weapon's 3D model, held by an invisible Handle at its grip (the blade
-- along the Handle's -Z, like the blocky one), or nil if it isn't in the game
local function buildModelSword(def, golden)
	local name = def.Model
	local geo = name and WeaponFX.MODELS[name]
	local src = name and ReplicatedStorage:FindFirstChild(name)
	if not (geo and src) then
		return nil
	end
	local ok, model, handle = pcall(function()
		local copy = src:Clone()
		if copy:IsA("BasePart") then
			-- (just the one mesh, not a model of them)
			local wrap = Instance.new("Model")
			copy.Parent = wrap
			copy = wrap
		end
		local parts = {}
		for _, d in ipairs(copy:GetDescendants()) do
			if d:IsA("BasePart") then
				parts[#parts + 1] = d
			elseif d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Script") or d:IsA("LocalScript") then
				d:Destroy()
			end
		end
		if #parts == 0 then
			return nil
		end
		-- the box round it all: its longest side runs pommel to tip (the tip
		-- up, as it was made), the middle one across the blade
		local box, size = copy:GetBoundingBox()
		local sides = { { size.X, box.RightVector }, { size.Y, box.UpVector }, { size.Z, box.LookVector } }
		table.sort(sides, function(a, b)
			return a[1] > b[1]
		end)
		local long, across = sides[1], sides[2]
		local tipWay, acrossWay = long[2], across[2]
		if tipWay.Y < -0.5 then
			tipWay = -tipWay -- (it was made standing on its pommel, the tip up)
		end
		if src:GetAttribute("GripFlip") == true then
			tipWay = -tipWay
		end
		local gripPoint = box.Position + tipWay * (long[1] * (geo.GripUp - 0.5)) + acrossWay * (across[1] * (geo.GripAcross - 0.5))
		local z = -tipWay
		local y = acrossWay
		local roll = tonumber(src:GetAttribute("GripRoll")) or geo.Roll or 0
		local grip = CFrame.fromMatrix(gripPoint, y:Cross(z), y, z) * CFrame.Angles(0, 0, math.rad(roll))
		local scale = geo.Length / math.max(long[1], 0.01) -- (in case it came in bigger or smaller)
		pcall(function()
			if RunService:IsStudio() then
				-- (in Studio: how it's held, in the Output - for sorting out a model that sits wrong)
				print(string.format("[WeaponFX] %s held: came in %.0f long, scaled x%.3f, tip %s, GripRoll %s, GripFlip %s (code v3)",
					name, long[1], scale, tostring(tipWay), tostring(roll), tostring(src:GetAttribute("GripFlip"))))
			end
		end)
		local out = Instance.new("Model")
		out.Name = "HeldWeapon"
		local h = Instance.new("Part")
		h.Name = "Handle"
		h.Size = Vector3.new(0.2, 0.2, 0.2)
		h.Transparency = 1
		h.CanCollide, h.CanTouch, h.CanQuery, h.CastShadow = false, false, false, false
		h.Massless = true
		h.Parent = out
		for _, p in ipairs(parts) do
			local offset = grip:ToObjectSpace(p.CFrame)
			offset = offset - offset.Position + offset.Position * scale
			p.Size = p.Size * scale
			p.Anchored = false
			p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = false, false, false, false
			p.Massless = true
			if string.find(p.Name, "Glow") then
				-- (the glowing pixels: made to shine)
				p.Material = Enum.Material.Neon
				p.Color = golden and GOLD or geo.Glow or GLOW
			end
			p.CFrame = h.CFrame * offset
			local weld = Instance.new("Weld")
			weld.Part0, weld.Part1 = h, p
			weld.C0 = offset
			weld.Parent = p
			p.Parent = out
		end
		copy:Destroy()
		if golden then
			-- (its own colours are in its texture: the gold is a glow round it)
			local light = Instance.new("PointLight")
			light.Name = "Awakened"
			light.Color = GOLD
			light.Brightness = 2
			light.Range = 7
			light.Parent = h
		end
		return out, h
	end)
	if not (ok and model) then
		return nil
	end
	-- the smears, along the blade (from just past the guard to the tip)
	local reach = geo.Length * (1 - geo.GripUp)
	local color = golden and GOLD or geo.Glow or GLOW
	local function smear(trailName, from, to, see, life)
		local a0 = Instance.new("Attachment")
		a0.Name = trailName .. "Base"
		a0.Position = Vector3.new(0, 0, -from)
		a0.Parent = handle
		local a1 = Instance.new("Attachment")
		a1.Name = trailName .. "Tip"
		a1.Position = Vector3.new(0, 0, -to)
		a1.Parent = handle
		local trail = Instance.new("Trail")
		trail.Name = trailName
		trail.Attachment0, trail.Attachment1 = a0, a1
		trail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), color)
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, see), NumberSequenceKeypoint.new(0.55, 0.65), NumberSequenceKeypoint.new(1, 1) })
		trail.LightEmission = 1
		trail.Lifetime = life
		trail.MinLength = 0.02
		trail.WidthScale = NumberSequence.new(1, 0.35)
		trail.Enabled = false
		trail.Parent = handle
		return trail
	end
	local trails = {
		smear("SwingTrail", reach * 0.3, reach, 0, 0.2),
		smear("SwingGlow", reach * 0.15, reach * 1.08, 0.5, 0.28),
	}
	return model, handle, trails, handle
end

----------------------------------------------------------------------
-- The voxel weapons (Tools/Weapons: built from little cubes in code, a mesh
-- per colour). Their models come in by upload (the server loads them into
-- ReplicatedStorage > WeaponModels: ServerScriptService/WeaponModelLoader) or
-- by hand (Studio's 3D Importer, into that same folder, named after the
-- weapon). ReplicatedStorage/WeaponModelInfo says how to colour each mesh,
-- where the smears run and where its head is; three tiny marker meshes in
-- the model (GripMark, TipMark, UpMark) say exactly where it's held, so it
-- sits in the hand just like the blocky one - whatever size or way round
-- it came in.
----------------------------------------------------------------------
local INFO = {}
pcall(function()
	local m = ReplicatedStorage:WaitForChild("WeaponModelInfo", 5)
	INFO = m and require(m) or {}
end)
WeaponFX.INFO = INFO

local function voxelSource(name)
	local folder = ReplicatedStorage:FindFirstChild("WeaponModels")
	return folder and folder:FindFirstChild(name) or nil
end
WeaponFX.voxelSource = voxelSource

local function rgb(t, fallback)
	if type(t) == "table" and #t >= 3 then
		return Color3.fromRGB(t[1], t[2], t[3])
	end
	return fallback
end
local function vec(t)
	return Vector3.new(t[1] or 0, t[2] or 0, t[3] or 0)
end

-- (a mesh's name, as the importer may have changed it: "goo", "GooGloves_goo", "goo.001")
local function partKey(info, name, key)
	if info.Parts[name] then
		return name
	end
	local plain = string.gsub(name, "%.%d+$", "")
	if info.Parts[plain] then
		return plain
	end
	local prefix = key .. "_"
	if string.sub(plain, 1, #prefix) == prefix and info.Parts[string.sub(plain, #prefix + 1)] then
		return string.sub(plain, #prefix + 1)
	end
	return nil
end

local function buildVoxel(def, golden)
	local key = def.Model
	local info = key and INFO[key]
	local src = info and voxelSource(key)
	if not src then
		return nil
	end
	local ok, model, handle, trails, head = pcall(function()
		local copy = src:Clone()
		local parts, marks = {}, {}
		local all = copy:GetDescendants()
		if copy:IsA("BasePart") then
			table.insert(all, copy)
		end
		for _, d in ipairs(all) do
			if d:IsA("BasePart") then
				local name = string.gsub(d.Name, "%.%d+$", "")
				if name == "GripMark" or name == "TipMark" or name == "UpMark" then
					marks[name] = d
				else
					parts[#parts + 1] = d
				end
			elseif d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("LuaSourceContainer") then
				d:Destroy()
			end
		end
		local g, t, u = marks.GripMark, marks.TipMark, marks.UpMark
		if not (g and t and u and #parts > 0) then
			return nil
		end
		-- the grip, from the markers: +Z away from the tip, +Y to the front
		local o = g.Position
		local up = t.Position - o
		if up.Magnitude < 1e-4 then
			return nil
		end
		local scale = (info.Tip or 1) / up.Magnitude -- (in case it came in bigger or smaller)
		local z = -up.Unit
		local y = u.Position - o
		y = y - z * y:Dot(z)
		if y.Magnitude < 1e-4 then
			return nil
		end
		y = y.Unit
		local grip = CFrame.fromMatrix(o, y:Cross(z), y, z)
		local out = Instance.new("Model")
		out.Name = "HeldWeapon"
		local h = Instance.new("Part")
		h.Name = "Handle"
		h.Size = Vector3.new(0.2, 0.2, 0.2)
		h.Transparency = 1
		h.CanCollide, h.CanTouch, h.CanQuery, h.CastShadow = false, false, false, false
		h.Massless = true
		h.Parent = out
		for _, p in ipairs(parts) do
			local offset = grip:ToObjectSpace(p.CFrame)
			offset = offset - offset.Position + offset.Position * scale
			p.Size = p.Size * scale
			p.Anchored = false
			p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
			p.CastShadow = false
			p.Massless = true
			local pk = partKey(info, p.Name, key)
			local spec = pk and info.Parts[pk]
			if spec then
				pcall(function()
					p.TextureID = "" -- (its colour is its Color, not a texture)
				end)
				local color = rgb(spec.Color, p.Color)
				local mat = Enum.Material[spec.Material] or Enum.Material.SmoothPlastic
				if golden and spec.Role == "metal" then
					-- awakened: the metal turns gold (keeping how light or dark it was)
					local v = math.max(color.R, color.G, color.B)
					color = GOLD:Lerp(Color3.fromRGB(150, 96, 20), math.clamp(1 - v, 0, 1) * 0.8)
				elseif golden and spec.Role == "glow" then
					color = GOLD
				end
				p.Color = color
				p.Material = mat
				p.Transparency = spec.Transparency or 0
				p.Name = pk
			end
			p.CFrame = h.CFrame * offset
			local weld = Instance.new("Weld")
			weld.Part0, weld.Part1 = h, p
			weld.C0 = offset
			weld.Parent = p
			p.Parent = out
		end
		for _, m in pairs(marks) do
			m:Destroy()
		end
		copy:Destroy()
		-- the business end (for the finisher's slam and the ability effects)
		local hd = Instance.new("Part")
		hd.Name = "Head"
		hd.Size = Vector3.new(0.2, 0.2, 0.2)
		hd.Transparency = 1
		hd.CanCollide, hd.CanTouch, hd.CanQuery, hd.CastShadow = false, false, false, false
		hd.Massless = true
		local hoff = CFrame.new(vec(info.Head or { 0, 0, -2 }))
		hd.CFrame = h.CFrame * hoff
		local hw = Instance.new("Weld")
		hw.Part0, hw.Part1 = h, hd
		hw.C0 = hoff
		hw.Parent = hd
		hd.Parent = out
		if golden then
			local light = Instance.new("PointLight")
			light.Name = "Awakened"
			light.Color = GOLD
			light.Brightness = 2
			light.Range = 7
			light.Parent = h
		end
		return out, h, nil, hd
	end)
	if not (ok and model) then
		return nil
	end
	-- the smears (from WeaponModelInfo: the handle's own space)
	local color = golden and GOLD or rgb(info.Glow, GLOW)
	local function smear(name, pts, see, life)
		local a0 = Instance.new("Attachment")
		a0.Name = name .. "Base"
		a0.Position = vec(pts[1])
		a0.Parent = handle
		local a1 = Instance.new("Attachment")
		a1.Name = name .. "Tip"
		a1.Position = vec(pts[2])
		a1.Parent = handle
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
		trail.Parent = handle
		return trail
	end
	trails = {
		smear("SwingTrail", info.Smear or { { 0, 0, -1 }, { 0, 0, -3 } }, 0, 0.2),
		smear("SwingGlow", info.SmearWide or info.Smear or { { 0, 0, -1 }, { 0, 0, -3 } }, 0.5, 0.28),
	}
	return model, handle, trails, head
end
WeaponFX.buildVoxel = buildVoxel

----------------------------------------------------------------------
-- Swing effects by rarity: the rarer the weapon, the bigger its swings, in
-- its pack's own theme. On top of the two smears every weapon has: Rare and
-- up a wide crescent from the grip past the tip, Epic and up a bright edge
-- and bits flung off the tip, Legendary and up a burst of them and a flash
-- as each cut starts, Mythic a second crescent hanging on, and Secret its
-- own show: a lingering body behind the cut, a wave flying off every cut
-- and the boss's eyes popping out of it.
--   Slime: goo that splats on the floor (the Acid Scythe's glowing acid
--     hisses where it lands); the Secret's see-through jelly with glowing
--     hearts, a wave of jelly and Oozark's eyes.
--   Knight: dirt off the dig - clods that bounce once and puff into dust,
--     glints of gold in it (Anchor Fists: iron chips and gold sparks, hits
--     ringing like an anchor); No Quarter's gold coins clinking down, a
--     crack of gold splitting the floor along the arc and Burrowmore's
--     visor glaring out of it.
--   Speedway: sparks skittering off the tarmac and puffs of tyre smoke
--     (Wheelie Wrecker: balls of fire that land and burn); Victory Lap's
--     confetti, a chequered trail, a chequered flag flying off every cut and
--     Revvington's big green eyes popping out of it.
----------------------------------------------------------------------
local RARITY_TIER = { Common = 1, Uncommon = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5, Secret = 6 }
WeaponFX.RARITY_TIER = RARITY_TIER

local function colors(list)
	local keys = {}
	for i, c in ipairs(list) do
		keys[i] = ColorSequenceKeypoint.new((i - 1) / (#list - 1), c)
	end
	return ColorSequence.new(keys)
end
local function fades(list)
	local keys = {}
	for i, v in ipairs(list) do
		keys[i] = NumberSequenceKeypoint.new(v[1], v[2])
	end
	return NumberSequence.new(keys)
end

-- THEMES: each pack's swings in its own colours and stuff (the Slime pack's
-- are goo); a weapon from a pack without one uses its own glow colour.
-- A theme's Mythic and Secret entries change what those two look like.
local RGBc = Color3.fromRGB
local SWING_THEMES = {
	Slime = {
		light = RGBc(190, 255, 120), main = RGBc(105, 210, 70), deep = RGBc(40, 110, 35),
		blob = { RGBc(105, 210, 70), RGBc(150, 240, 95), RGBc(60, 160, 50) }, blobSee = 0.15,
		swingSound = "Goo Swish", splatSound = "Goo Splat", hitSound = "Goo Hit",
		-- the Acid Scythe: glowing acid that hisses where it lands
		Mythic = {
			light = RGBc(235, 255, 150), main = RGBc(120, 255, 60), deep = RGBc(45, 120, 20),
			blob = { RGBc(120, 255, 60), RGBc(190, 255, 90) }, blobSee = 0, neon = true, sizzle = true,
			swingSound = "Acid Swish", splatSound = "Acid Hiss", hitSound = "Goo Hit",
		},
		-- Gelatinous Edge: Oozark's own jelly - see-through goo with glowing
		-- hearts, a wave of jelly off every cut, his eyes popping out of it
		Secret = {
			light = RGBc(214, 255, 120), main = RGBc(105, 210, 70), deep = RGBc(26, 70, 24),
			blob = { RGBc(105, 210, 70), RGBc(130, 225, 85) }, blobSee = 0.35, hearts = RGBc(214, 255, 120),
			wave = true, eyes = true,
			swingSound = "Jelly Swing", splatSound = "Goo Splat", hitSound = "Goo Hit", waveSound = "Jelly Wave", eyeSound = "Eye Pop",
		},
	},
	-- Burrowmore's: dirt flung up off the dig, a glint of gold in it. (A
	-- theme's `bits`: what it throws, one picked at random each time - see
	-- BITS; a bit's colours are the theme's list of that name, or `blob`.
	-- Its sounds are lists: the new one, then what to play till it's uploaded.)
	Knight = {
		light = RGBc(254, 231, 97), main = RGBc(254, 174, 52), deep = RGBc(18, 78, 137),
		bits = { "clod", "clod", "glint", "glint" },
		blob = { RGBc(194, 133, 105), RGBc(184, 111, 80), RGBc(115, 62, 57) }, blobSee = 0,
		glint = { RGBc(254, 231, 97), RGBc(254, 174, 52) }, dust = RGBc(214, 176, 150),
		swingSound = { "Shovel Swish", "Hammer Swing" }, splatSound = { "Dirt Splat", "Dirt Land" },
		hitSound = { "Clang Hit", "Sword Hit" },
		-- Anchor Fists: iron and gold - iron chips and sparks off the gold
		-- rivets in the dirt, and every hit rings like an anchor landing
		Mythic = {
			light = RGBc(255, 250, 200), main = RGBc(254, 174, 52), deep = RGBc(38, 43, 68),
			bits = { "clod", "chip", "glint", "glint" },
			blob = { RGBc(194, 133, 105), RGBc(115, 62, 57) }, blobSee = 0,
			chip = { RGBc(139, 155, 180), RGBc(90, 105, 136) }, glint = { RGBc(254, 231, 97), RGBc(255, 255, 255) },
			dust = RGBc(214, 176, 150),
			swingSound = { "Chain Swish", "Hammer Swing" }, splatSound = { "Dirt Splat", "Dirt Land" },
			hitSound = { "Clang Hit", "Anchor Land", "Hammer Hit" },
		},
		-- No Quarter: his armour cracks gold - gold coins spill off every cut
		-- and clink on the floor, a crack of gold splits the floor along the
		-- arc, and Burrowmore's visor glares out of it
		Secret = {
			light = RGBc(255, 250, 200), main = RGBc(254, 174, 52), deep = RGBc(18, 78, 137),
			bits = { "coin", "coin", "glint", "clod" },
			blob = { RGBc(194, 133, 105), RGBc(115, 62, 57) }, blobSee = 0,
			coin = { RGBc(254, 174, 52), RGBc(254, 231, 97) }, glint = { RGBc(254, 231, 97), RGBc(255, 255, 255) },
			dust = RGBc(254, 231, 97),
			wave = "crack", eyes = "visor",
			swingSound = { "Gold Swing", "Sword Swing" }, splatSound = { "Coin Spill", "Gem Land" },
			hitSound = { "Gold Chop", "Clang Hit", "Sword Hit" },
			waveSound = { "Plate Crack", "Armour Crack" }, eyeSound = { "Treasure Glint", "Relic Get" },
		},
	},
	-- Revvington's: sparks skittering off the tarmac, puffs of tyre smoke
	Speedway = {
		light = RGBc(255, 240, 180), main = RGBc(247, 118, 34), deep = RGBc(190, 74, 40),
		bits = { "spark", "spark", "spark", "spark", "smoke" },
		blob = { RGBc(255, 240, 180), RGBc(255, 190, 80), RGBc(255, 128, 30) }, blobSee = 0,
		smoke = { RGBc(210, 210, 220), RGBc(165, 165, 178) },
		swingSound = { "Tyre Swish", "Sword Swing" }, splatSound = { "Spark Skitter" },
		hitSound = { "Spark Hit", "Sword Hit" },
		-- Wheelie Wrecker: it's on fire - balls of fire that land and burn a
		-- moment, black smoke
		Mythic = {
			light = RGBc(255, 231, 97), main = RGBc(255, 128, 30), deep = RGBc(200, 40, 30),
			bits = { "flame", "flame", "spark", "smoke" },
			blob = { RGBc(255, 231, 97), RGBc(255, 160, 40), RGBc(255, 90, 30) }, blobSee = 0,
			smoke = { RGBc(90, 90, 100), RGBc(62, 62, 72) },
			swingSound = { "Flame Swish", "Hammer Swing" }, splatSound = { "Flame Burst" },
			hitSound = { "Flame Burst", "Hammer Hit" },
		},
		-- Victory Lap: the winner's lap - confetti everywhere, a chequered
		-- trail, a chequered flag flying off every cut and Revvington's big
		-- green eyes popping out of it
		Secret = {
			light = RGBc(255, 255, 255), main = RGBc(255, 255, 255), deep = RGBc(24, 20, 37),
			bits = { "confetti", "confetti", "confetti", "spark" },
			blob = { RGBc(255, 240, 180), RGBc(255, 190, 80) }, blobSee = 0,
			confetti = { RGBc(247, 118, 34), RGBc(255, 255, 255), RGBc(254, 231, 97), RGBc(99, 199, 77), RGBc(44, 232, 245), RGBc(228, 59, 68) },
			stripes = true, wave = "checker", eyes = "revv",
			swingSound = { "Victory Swing", "Sword Swing" }, splatSound = { "Checker Pop" },
			hitSound = { "Checker Pop", "Spark Hit", "Sword Hit" },
			waveSound = { "Finish Line", "Checkered Flag" }, eyeSound = { "Horn Honk", "Big Honk" },
		},
	},
}
WeaponFX.SWING_THEMES = SWING_THEMES

local function themeFor(def, glow, golden)
	if golden then
		return { light = RGBc(255, 250, 200), main = GOLD, deep = RGBc(200, 120, 20), blob = { GOLD, RGBc(255, 190, 60) }, blobSee = 0, neon = true }
	end
	local pack = def and def.Pack and SWING_THEMES[def.Pack]
	if pack then
		return pack[def.Rarity or ""] or pack
	end
	local c = glow or GLOW
	return {
		light = c:Lerp(RGBc(255, 255, 255), 0.4), main = c, deep = c:Lerp(RGBc(0, 0, 0), 0.55),
		blob = { c, c:Lerp(RGBc(255, 255, 255), 0.3) }, blobSee = 0, neon = true,
	}
end
WeaponFX.themeFor = themeFor

-- how much each rarity throws: bits a second off the tip while cutting, their
-- size, how many burst out as a cut starts
local FLING = {
	[3] = { rate = 22, size = 0.4, burst = 0 },
	[4] = { rate = 38, size = 0.5, burst = 8 },
	[5] = { rate = 50, size = 0.6, burst = 12 },
	[6] = { rate = 60, size = 0.75, burst = 18 },
}

-- the goo in flight: one list, moved by one Heartbeat - each bit arcs down
-- and splats flat on the floor (or hisses away, for acid)
local goo = {}
local gooConn = nil
local function gooFolder()
	local f = workspace:FindFirstChild("SwingGoo")
	if not f then
		f = Instance.new("Folder")
		f.Name = "SwingGoo"
		f.Parent = workspace
	end
	return f
end
-- the swing's goo, jelly and eyes hide while they're right up at your
-- camera (a blob an inch from your eye filled the whole screen)
local NEAR_CAMERA = 4
local function cameraAt()
	local cam = workspace.CurrentCamera
	return cam and cam.CFrame and cam.CFrame.Position or nil
end
WeaponFX.NEAR_CAMERA = NEAR_CAMERA
local function fxPart(name, size, cf, color, see, neon, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Transparency = see or 0
	p.Material = neon and Enum.Material.Neon or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	local eye = cameraAt()
	if eye and (cf.Position - eye).Magnitude < NEAR_CAMERA + size.Magnitude / 2 then
		p.LocalTransparencyModifier = 1
	end
	p.Parent = gooFolder()
	return p
end
local function fadeAway(p, time, props)
	props = props or {}
	props.Transparency = 1
	pcall(function()
		TweenService:Create(p, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.In), props):Play()
	end)
	task.delay(time + 0.05, function()
		p:Destroy()
	end)
end
-- a sound at a spot (a little invisible part to play it from)
local function soundAt(name, pos, pitch, volume)
	if not findSound(name) then
		return
	end
	local p = fxPart("SwingSound", Vector3.new(0.2, 0.2, 0.2), CFrame.new(pos), GLOW, 1, false)
	playAt(name, p, pitch, volume)
	task.delay(2, function()
		p:Destroy()
	end)
end
WeaponFX.soundAt = soundAt
-- WHAT FLIES: a theme's bits (see SWING_THEMES). shape: how it's drawn
-- (a drop stretched the way it flies, a streak, a tumbling lump, a coin, a
-- scrap of paper); fall: its gravity (below 0 it rises); drag: how fast the
-- air slows it; bounce: how many times it bounces before it lands; land:
-- what it leaves on the floor; life: seconds before it's gone anyway
local BITS = {
	goo = { shape = "drop", fall = 55, land = "splat" }, -- a drop that splats flat
	clod = { shape = "lump", fall = 60, bounce = 1, land = "puff" }, -- dirt: bounces once, puffs into dust
	chip = { shape = "lump", fall = 60, bounce = 1, land = "fade" }, -- a chip of iron
	glint = { shape = "streak", fall = 45, bounce = 1, land = "fade", neon = true }, -- a spark of gold
	spark = { shape = "streak", fall = 40, bounce = 2, land = "fade", neon = true }, -- skitters along the floor
	smoke = { shape = "puff", fall = -4, drag = 2.5, life = 0.9, see = 0.35 }, -- tyre smoke drifting up
	flame = { shape = "drop", fall = 30, land = "burn", neon = true }, -- a ball of fire: lands and burns
	coin = { shape = "coin", fall = 55, bounce = 1, land = "lie", neon = true }, -- flips, clinks, lies there
	confetti = { shape = "flake", fall = 9, drag = 1.6, land = "lie", life = 2.2 }, -- flutters down
}
WeaponFX.BITS = BITS
local function bitName(kind)
	return kind == "goo" and "Goo" or (string.upper(string.sub(kind, 1, 1)) .. string.sub(kind, 2))
end

local lastSplat = 0
local function landSound(b, volume)
	-- (not every one: a pitter-patter, not a wall of noise)
	local t = b.theme
	if t.splatSound and os.clock() - lastSplat > 0.07 then
		lastSplat = os.clock()
		soundAt(t.splatSound, b.pos, 0.85 + math.random() * 0.4, volume or 0.35)
	end
end
local function splat(b)
	local t = b.theme
	landSound(b)
	local r = b.size * (2.6 + math.random() * 1.6)
	local disc = fxPart("Splat", Vector3.new(0.08, r, r), CFrame.new(b.pos.X, b.floor + 0.05, b.pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		t.deep:Lerp(t.main, 0.5), t.neon and 0.2 or 0.25, t.neon, Enum.PartType.Cylinder)
	fadeAway(disc, 1.4, { Size = Vector3.new(0.08, r * 1.25, r * 1.25) })
	if t.sizzle then
		for _ = 1, 2 do
			local puff = fxPart("Hiss", Vector3.new(0.5, 0.5, 0.5), CFrame.new(b.pos.X + math.random() - 0.5, b.floor + 0.3, b.pos.Z + math.random() - 0.5),
				t.light, 0.3, true, Enum.PartType.Ball)
			fadeAway(puff, 0.6, { Size = Vector3.new(1.4, 1.4, 1.4), CFrame = puff.CFrame + Vector3.new(0, 2.2, 0) })
		end
	end
end
-- what a bit leaves where it lands
local function land(b)
	local how = b.spec.land
	local at = Vector3.new(b.pos.X, b.floor, b.pos.Z)
	if how == "splat" then
		splat(b)
	elseif how == "puff" then
		-- a puff of dust
		landSound(b, 0.3)
		local puff = fxPart("Dust", Vector3.new(b.size, b.size, b.size) * 1.1, CFrame.new(at + Vector3.new(0, b.size * 0.4, 0)),
			b.theme.dust or b.part.Color, 0.3, false, Enum.PartType.Ball)
		fadeAway(puff, 0.55, { Size = Vector3.new(b.size, b.size, b.size) * 2.6, CFrame = puff.CFrame + Vector3.new(0, 0.8, 0) })
	elseif how == "burn" then
		-- a lick of fire, flaring up and dying
		landSound(b, 0.25)
		local lick = fxPart("Burn", Vector3.new(b.size * 0.9, b.size * 0.6, b.size * 0.9), CFrame.new(at + Vector3.new(0, b.size * 0.3, 0)),
			b.theme.light, 0, true)
		fadeAway(lick, 0.5, { Size = Vector3.new(b.size * 0.3, b.size * 2.4, b.size * 0.3), CFrame = lick.CFrame + Vector3.new(0, b.size * 1.1, 0) })
	elseif how == "lie" then
		-- (a coin or a scrap of paper, lying flat where it fell)
		landSound(b, 0.3)
		local flat = fxPart(b.part.Name, b.part.Size, CFrame.new(at + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
			* (b.spec.shape == "coin" and CFrame.Angles(0, 0, math.rad(90)) or CFrame.new()),
			b.part.Color, b.part.Transparency, b.part.Material == Enum.Material.Neon, b.part.Shape)
		fadeAway(flat, b.spec.shape == "coin" and 0.8 or 0.6)
	end
end
local function stepGoo(dt)
	local eye = cameraAt()
	for i = #goo, 1, -1 do
		local b = goo[i]
		local spec = b.spec
		b.vel = b.vel - Vector3.new(0, spec.fall * dt, 0)
		if spec.drag then
			b.vel = b.vel * math.max(0, 1 - spec.drag * dt)
		end
		b.pos = b.pos + b.vel * dt
		b.age = b.age + dt
		local landed = spec.fall > 0 and b.pos.Y <= b.floor + b.size * 0.4
		if landed and b.bounces > 0 and b.part.Parent then
			-- a bounce: up off the floor, slower (sparks skitter, clods hop)
			b.bounces -= 1
			b.pos = Vector3.new(b.pos.X, b.floor + b.size * 0.4, b.pos.Z)
			b.vel = Vector3.new(b.vel.X * 0.6, math.abs(b.vel.Y) * (spec.shape == "streak" and 0.45 or 0.35), b.vel.Z * 0.6)
			if spec.shape ~= "lump" then
				landSound(b, 0.2)
			end
			landed = false
		end
		if landed or b.age > (spec.life or 2) or not b.part.Parent then
			if landed and b.part.Parent then
				land(b)
			end
			b.part:Destroy()
			if b.core then
				b.core:Destroy()
			end
			table.remove(goo, i)
		else
			local shape = spec.shape
			if shape == "drop" or shape == "streak" then
				-- (stretched along the way it's flying, like a drop - a spark
				-- much more)
				local stretch = math.clamp(b.vel.Magnitude / 30, 0, 1)
				local cf = CFrame.lookAt(b.pos, b.pos + b.vel)
				b.part.CFrame = cf
				if shape == "drop" then
					b.part.Size = Vector3.new(b.size * (1 - stretch * 0.25), b.size * (1 - stretch * 0.25), b.size * (1 + stretch))
				else
					b.part.Size = Vector3.new(b.size * 0.3, b.size * 0.3, b.size * (1 + 3 * stretch))
				end
				if b.core then
					b.core.CFrame = cf
				end
			elseif shape == "puff" then
				local k = b.age / (spec.life or 1)
				b.part.CFrame = CFrame.new(b.pos)
				b.part.Size = Vector3.new(b.size, b.size, b.size) * (1.2 + 1.8 * k)
				b.part.Transparency = spec.see + (1 - spec.see) * k
			else
				-- (tumbling end over end)
				local w = b.spin * b.age
				b.part.CFrame = CFrame.new(b.pos) * CFrame.fromEulerAnglesXYZ(w.X, w.Y, w.Z)
			end
			local hide = (eye and (b.pos - eye).Magnitude < NEAR_CAMERA + b.size) and 1 or 0
			b.part.LocalTransparencyModifier = hide
			if b.core then
				b.core.LocalTransparencyModifier = hide
			end
		end
	end
	if #goo == 0 and gooConn then
		gooConn:Disconnect()
		gooConn = nil
	end
end
-- throw one bit of the theme's stuff: from pos at vel, `size` big, landing on
-- the floor at height `floor`
local function flingGoo(theme, pos, vel, size, floor)
	if #goo > 160 then
		return
	end
	local kinds = theme.bits
	local kind = type(kinds) == "table" and kinds[math.random(1, #kinds)] or kinds or "goo"
	local spec = BITS[kind] or BITS.goo
	local list = theme[kind]
	list = type(list) == "table" and #list > 0 and list or theme.blob
	local c = list[math.random(1, #list)]
	local shape = spec.shape
	local see = kind == "goo" and theme.blobSee or (spec.see or 0)
	local neon = (kind == "goo" and theme.neon) or spec.neon or false
	local part
	if shape == "drop" or shape == "puff" then
		part = fxPart(bitName(kind), Vector3.new(size, size, size), CFrame.new(pos), c, see, neon, Enum.PartType.Ball)
	elseif shape == "streak" then
		part = fxPart(bitName(kind), Vector3.new(size * 0.3, size * 0.3, size), CFrame.new(pos), c, see, neon)
	elseif shape == "coin" then
		part = fxPart(bitName(kind), Vector3.new(size * 0.2, size * 1.1, size * 1.1), CFrame.new(pos), c, see, neon, Enum.PartType.Cylinder)
	elseif shape == "flake" then
		part = fxPart(bitName(kind), Vector3.new(size * 0.9, size * 0.08, size * 0.6), CFrame.new(pos), c, see, neon)
	else
		local k = 0.8 + math.random() * 0.4
		part = fxPart(bitName(kind), Vector3.new(size, size * 0.8, size * 0.9) * k, CFrame.new(pos), c, see, neon)
	end
	local core = nil
	if kind == "goo" and theme.hearts then
		core = fxPart("GooHeart", Vector3.new(size * 0.4, size * 0.4, size * 0.4), CFrame.new(pos), theme.hearts, 0, true, Enum.PartType.Ball)
	end
	local spin = Vector3.new(math.random() * 16 - 8, math.random() * 16 - 8, math.random() * 16 - 8)
	table.insert(goo, { part = part, core = core, pos = pos, vel = vel, size = size, floor = floor, age = 0, theme = theme,
		kind = kind, spec = spec, bounces = spec.bounce or 0, spin = spin })
	if not gooConn then
		gooConn = RunService.Heartbeat:Connect(stepGoo)
	end
end
WeaponFX.flingGoo = flingGoo
WeaponFX._goo = goo -- (for the headless tests)

-- the Secret's wave: the arc the tip just drew, in jelly, flying out from you
-- and wobbling away
local function jellyWave(theme, path, centre)
	if #path < 3 then
		return
	end
	if theme.waveSound then
		soundAt(theme.waveSound, path[math.ceil(#path / 2)], 1, 0.9)
	end
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		if len > 0.05 then
			local out = Vector3.new(mid.X - centre.X, 0, mid.Z - centre.Z)
			out = out.Magnitude > 0.1 and out.Unit or Vector3.new(0, 0, -1)
			local u = i / #path
			local fat = 0.4 + 1.4 * math.sin(math.pi * u)
			local cf = CFrame.lookAt(mid, b)
			local body = fxPart("JellyWave", Vector3.new(fat, 0.3, len * 1.15), cf, theme.main, 0.35, false)
			local rim = fxPart("JellyRim", Vector3.new(fat * 0.3, 0.35, len * 1.15), cf * CFrame.new(fat * 0.4, 0.05, 0), theme.light, 0, true)
			local push = out * 7 + Vector3.new(0, 0.6, 0)
			fadeAway(body, 0.45, { CFrame = cf + push, Size = Vector3.new(fat * 1.8, 0.2, len * 1.4) })
			fadeAway(rim, 0.35, { CFrame = cf * CFrame.new(fat * 0.4, 0.05, 0) + push })
		end
	end
end

-- the Secret's eyes: Oozark's eyes pop out of the arc, blink at you, and
-- burst into goo
local function oozarkEyes(theme, at, floor)
	local look = CFrame.new(at) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	for _, x in ipairs({ -0.45, 0.45 }) do
		local cf = look * CFrame.new(x, 0, 0)
		local eye = fxPart("OozarkEye", Vector3.new(0.1, 0.1, 0.1), cf, RGBc(236, 255, 170), 0, true, Enum.PartType.Ball)
		local pupil = fxPart("OozarkPupil", Vector3.new(0.05, 0.05, 0.05), cf * CFrame.new(0, 0, -0.3), RGBc(24, 20, 37), 0, false, Enum.PartType.Ball)
		pcall(function()
			TweenService:Create(eye, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.new(0.8, 0.8, 0.8) }):Play()
			TweenService:Create(pupil, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.new(0.35, 0.35, 0.35) }):Play()
		end)
		task.delay(0.35, function()
			if eye.Parent and x < 0 and theme.eyeSound then
				soundAt(theme.eyeSound, eye.Position, 0.9 + math.random() * 0.25, 0.8)
			end
			if eye.Parent then
				for _ = 1, 3 do
					flingGoo(theme, eye.Position, Vector3.new(math.random() * 10 - 5, 6 + math.random() * 5, math.random() * 10 - 5), 0.35, floor)
				end
			end
			eye:Destroy()
			pupil:Destroy()
		end)
	end
end

-- No Quarter's crack: the arc splits the floor under it with a crack of gold
-- that flares and fades (jagged: each bit of it knocked a little aside)
local function goldCrack(theme, path, floor)
	if #path < 3 then
		return
	end
	if theme.waveSound then
		soundAt(theme.waveSound, path[math.ceil(#path / 2)], 1, 0.8)
	end
	local prev = nil
	for i = 1, #path, 2 do
		local p = path[i]
		local q = Vector3.new(p.X + (math.random() - 0.5) * 0.9, floor + 0.06, p.Z + (math.random() - 0.5) * 0.9)
		if prev and (q - prev).Magnitude > 0.1 then
			local mid = (prev + q) / 2
			local len = (q - prev).Magnitude
			local cf = CFrame.lookAt(mid, q)
			local crack = fxPart("GoldCrack", Vector3.new(0.3, 0.1, len + 0.2), cf, theme.light, 0, true)
			local glow = fxPart("GoldCrackGlow", Vector3.new(1.1, 0.06, len + 0.4), cf, theme.main, 0.45, true)
			fadeAway(crack, 1.0)
			fadeAway(glow, 0.6, { Size = Vector3.new(2.4, 0.06, len + 0.6) })
		end
		prev = q
	end
end

-- a spot on the arc, turned to face `centre` (you) - flat, so it stands up
local function facing(at, centre)
	local d = centre and Vector3.new(centre.X - at.X, 0, centre.Z - at.Z)
	if not d or d.Magnitude < 0.1 then
		return CFrame.new(at) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	end
	return CFrame.lookAt(at, at + d)
end

-- No Quarter's visor: Burrowmore's helm glares out of the arc at you - his
-- T-shaped slit, his eyes flaring yellow in it - and bursts into gold coins
local function burrowmoreVisor(theme, at, floor, centre)
	local look = facing(at, centre)
	local ink = RGBc(24, 20, 37)
	local parts = {
		{ fxPart("Visor", Vector3.new(0.1, 0.1, 0.1), look, ink, 0, false), Vector3.new(2.0, 0.42, 0.14) },
		{ fxPart("Visor", Vector3.new(0.1, 0.1, 0.1), look * CFrame.new(0, -0.5, 0), ink, 0, false), Vector3.new(0.42, 1.0, 0.14) },
	}
	for _, x in ipairs({ -0.52, 0.52 }) do
		table.insert(parts, { fxPart("VisorEye", Vector3.new(0.1, 0.1, 0.1), look * CFrame.new(x, 0, -0.09), RGBc(254, 231, 97), 0, true),
			Vector3.new(0.55, 0.28, 0.1) })
	end
	for _, pr in ipairs(parts) do
		pcall(function()
			TweenService:Create(pr[1], TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = pr[2] }):Play()
		end)
	end
	task.delay(0.4, function()
		local first = parts[1][1]
		if first.Parent then
			if theme.eyeSound then
				soundAt(theme.eyeSound, first.Position, 0.95 + math.random() * 0.1, 0.8)
			end
			for _ = 1, 6 do
				flingGoo(theme, first.Position, Vector3.new(math.random() * 12 - 6, 7 + math.random() * 6, math.random() * 12 - 6), 0.5, floor)
			end
		end
		for _, pr in ipairs(parts) do
			pr[1]:Destroy()
		end
	end)
end

-- Victory Lap's wave: the arc the tip just drew, as a strip of chequered flag
-- flying out from you
local function checkerWave(theme, path, centre)
	if #path < 3 then
		return
	end
	if theme.waveSound then
		soundAt(theme.waveSound, path[math.ceil(#path / 2)], 1, 0.8)
	end
	local white, ink = RGBc(255, 255, 255), RGBc(24, 20, 37)
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		if len > 0.05 then
			local out = Vector3.new(mid.X - centre.X, 0, mid.Z - centre.Z)
			out = out.Magnitude > 0.1 and out.Unit or Vector3.new(0, 0, -1)
			local cf = CFrame.lookAt(mid, b)
			for row = 0, 1 do
				local lit = (i + row) % 2 == 0
				local at = cf * CFrame.new((row - 0.5) * 0.8, 0, 0)
				local sq = fxPart("CheckerWave", Vector3.new(0.75, 0.12, len * 1.1), at, lit and white or ink, 0, lit)
				fadeAway(sq, 0.5, { CFrame = at + out * (6 + row * 1.5) + Vector3.new(0, 0.5, 0) })
			end
		end
	end
end

-- Victory Lap's eyes: Revvington's big green eyes pop out of the arc, look
-- at you, and burst into confetti
local function revvEyes(theme, at, floor, centre)
	local look = facing(at, centre)
	local parts = {}
	for _, x in ipairs({ -0.5, 0.5 }) do
		local cf = look * CFrame.new(x, 0, 0)
		table.insert(parts, { fxPart("RevvEye", Vector3.new(0.1, 0.1, 0.1), cf, RGBc(255, 255, 255), 0, false, Enum.PartType.Ball), 0.9 })
		table.insert(parts, { fxPart("RevvIris", Vector3.new(0.05, 0.05, 0.05), cf * CFrame.new(0, 0.05, -0.28), RGBc(99, 199, 77), 0, true, Enum.PartType.Ball), 0.5 })
		table.insert(parts, { fxPart("RevvPupil", Vector3.new(0.05, 0.05, 0.05), cf * CFrame.new(0, 0.05, -0.45), RGBc(24, 20, 37), 0, false, Enum.PartType.Ball), 0.24 })
	end
	for _, pr in ipairs(parts) do
		pcall(function()
			TweenService:Create(pr[1], TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.new(pr[2], pr[2], pr[2]) }):Play()
		end)
	end
	task.delay(0.35, function()
		local eye = parts[1][1]
		if eye.Parent then
			if theme.eyeSound then
				soundAt(theme.eyeSound, eye.Position, 1, 0.7)
			end
			for k = 1, 2 do
				local from = parts[(k - 1) * 3 + 1][1].Position
				for _ = 1, 5 do
					flingGoo(theme, from, Vector3.new(math.random() * 10 - 5, 6 + math.random() * 5, math.random() * 10 - 5), 0.45, floor)
				end
			end
		end
		for _, pr in ipairs(parts) do
			pr[1]:Destroy()
		end
	end)
end

-- a chequered ColorSequence: n hard stripes, a and b in turn
local function stripes(a, b, n)
	local keys = {}
	for i = 0, n - 1 do
		local c = (i % 2 == 0) and a or b
		table.insert(keys, ColorSequenceKeypoint.new(i / n + (i > 0 and 0.001 or 0), c))
		table.insert(keys, ColorSequenceKeypoint.new((i + 1) / n - (i < n - 1 and 0.001 or 0), c))
	end
	return ColorSequence.new(keys)
end

-- the extra trails along the same line as the weapon's own smear
-- (`trails[1]`), added to `trails` so they switch on and off with it; what
-- the swing throws is kept in `trails.fx` (see setSmear)
local function dressTrails(trails, def, glow, golden)
	local tier = RARITY_TIER[def and def.Rarity or ""] or 1
	local base = trails and trails[1]
	local a0, a1 = base and base.Attachment0, base and base.Attachment1
	if tier < 2 or not (a0 and a1 and base.Parent) then
		return trails
	end
	local theme = themeFor(def, glow, golden)
	local part = base.Parent
	local p0, p1 = a0.Position, a1.Position
	local along = p1 - p0
	local function at(u)
		return p0 + along * u
	end
	local white = RGBc(255, 255, 255)
	local function attach(name, pos)
		local a = Instance.new("Attachment")
		a.Name = name
		a.Position = pos
		a.Parent = part
		return a
	end
	local function trail(name, u0, u1, cs, see, life, width)
		local t = Instance.new("Trail")
		t.Name = name
		t.Attachment0, t.Attachment1 = attach(name .. "Base", at(u0)), attach(name .. "Tip", at(u1))
		t.Color = cs
		t.Transparency = see
		t.LightEmission = 0.7
		t.Lifetime = life
		t.MinLength = 0.02
		t.WidthScale = width
		t.Enabled = false
		t.Parent = part
		table.insert(trails, t)
		return t
	end
	-- the crescent: from near the grip to past the tip, in the theme's own colours
	local fan = trail("SwingFan", -0.35, 1.18, colors({ theme.light, theme.main, theme.deep }),
		fades({ { 0, 0.05 }, { 0.4, 0.3 }, { 1, 1 } }), 0.16 + 0.035 * tier, NumberSequence.new(1, 0.55))
	if tier >= 3 then
		-- the bright edge along the outside (only a thin line of white)
		trail("SwingEdge", 0.9, 1.3, colors({ white, theme.light, theme.main }),
			fades({ { 0, 0 }, { 0.5, 0.3 }, { 1, 1 } }), 0.2 + 0.05 * tier, NumberSequence.new(1, 0.3))
	end
	if tier == 5 then
		-- Mythic: a second, darker crescent hanging on behind
		trail("SwingDeep", 0.1, 1.25, colors({ theme.main, theme.deep }),
			fades({ { 0, 0.35 }, { 1, 1 } }), 0.5, NumberSequence.new(1, 0.4))
	elseif tier >= 6 then
		-- Secret: a thick body that lingers behind the cut - see-through
		-- jelly, or (Victory Lap) a chequered flag
		trail("SwingJelly", -0.1, 1.4, theme.stripes and stripes(theme.light, theme.deep, 8) or colors({ theme.light, theme.main, theme.deep }),
			fades({ { 0, 0.25 }, { 0.5, 0.5 }, { 1, 1 } }), 0.6, NumberSequence.new(1, 0.7))
	end
	trails.fx = {
		tier = tier,
		theme = theme,
		fling = FLING[math.min(tier, 6)],
		tip = fan.Attachment1,
		part = part,
	}
	return trails
end
WeaponFX.dressTrails = dressTrails

-- while a cut's on: bits off the tip (Epic and up), a burst and a flash as
-- it starts (Legendary and up), and when it ends the Secret's wave (jelly, a
-- crack of gold, a chequered flag) and the boss's eyes along the arc it drew
local function swingFx(h, on, starting)
	local fx = h.trails and h.trails.fx
	if not (fx and fx.fling and fx.part and fx.part.Parent) then
		return
	end
	local now = os.clock()
	local tipPos = (fx.part.CFrame * CFrame.new(fx.tip.Position)).Position
	local hrp = h.char and h.char:FindFirstChild("HumanoidRootPart")
	local floor = hrp and hrp.Position.Y - 3 or tipPos.Y - 4
	if starting then
		fx.path = {}
		if fx.theme.swingSound then
			playAt(fx.theme.swingSound, fx.part, 0.95 + math.random() * 0.1, fx.tier >= 6 and 1 or 0.8)
		end
		fx.last, fx.lastT, fx.acc = tipPos, now, 0
		for _ = 1, fx.fling.burst do
			flingGoo(fx.theme, tipPos, Vector3.new(math.random() * 16 - 8, 6 + math.random() * 8, math.random() * 16 - 8), fx.fling.size, floor)
		end
		if fx.tier >= 4 then
			local light = Instance.new("PointLight")
			light.Color = fx.theme.main
			light.Range = 10 + fx.tier * 2
			light.Brightness = 3
			light.Parent = fx.part
			fadeAway(light, 0.35, { Brightness = 0 })
		end
	end
	if on then
		local dt = math.max(now - (fx.lastT or now), 1 / 240)
		local vel = (tipPos - (fx.last or tipPos)) / dt
		fx.last, fx.lastT = tipPos, now
		fx.acc = (fx.acc or 0) + fx.fling.rate * dt
		while fx.acc >= 1 do
			fx.acc -= 1
			local spread = Vector3.new(math.random() * 8 - 4, 4 + math.random() * 6, math.random() * 8 - 4)
			local v = vel.Magnitude > 60 and vel.Unit * 60 or vel
			flingGoo(fx.theme, tipPos, v * 0.3 + spread, fx.fling.size * (0.6 + math.random() * 0.6), floor)
		end
		if fx.path and #fx.path < 60 then
			table.insert(fx.path, tipPos)
		end
	elseif fx.path then
		-- the cut's over
		local path = fx.path
		fx.path = nil
		local wave, eyes = fx.theme.wave, fx.theme.eyes
		if wave == "crack" then
			goldCrack(fx.theme, path, floor)
		elseif wave == "checker" and hrp then
			checkerWave(fx.theme, path, hrp.Position)
		elseif wave and hrp then
			jellyWave(fx.theme, path, hrp.Position)
		end
		local centre = hrp and hrp.Position
		if eyes == "visor" and #path >= 4 then
			burrowmoreVisor(fx.theme, path[math.floor(#path * 0.6) + 1], floor, centre)
		elseif eyes and #path >= 4 then
			local pop = eyes == "revv" and revvEyes or oozarkEyes
			pop(fx.theme, path[math.floor(#path * 0.4) + 1], floor, centre)
			pop(fx.theme, path[math.floor(#path * 0.8)], floor, centre)
		end
	end
end

----------------------------------------------------------------------
-- Hits: the slash mark ripping across what you hit, and the finisher's slam
----------------------------------------------------------------------
-- a bright bar that tears across the spot, stretching out and fading, with a
-- burst of sparks - and on a heavy hit a second one crossing it
-- (`def`, the weapon: its own glow colour, and the rarer it is the more bars,
-- sparks and colour - a ring of every colour on Mythic and Secret)
function WeaponFX.slashMark(position, direction, heavy, golden, def)
	if typeof(position) ~= "Vector3" then
		return
	end
	local dir = typeof(direction) == "Vector3" and direction.Magnitude > 0.01 and direction.Unit or Vector3.new(0, 0, -1)
	local info = def and def.Model and INFO[def.Model]
	local tier = RARITY_TIER[def and def.Rarity or ""] or 1
	local color = golden and GOLD or (info and rgb(info.Glow, GLOW)) or GLOW
	local theme = themeFor(def, color, golden)
	local holder = Instance.new("Folder")
	holder.Name = "SlashMark"
	holder.Parent = workspace
	local bars = (heavy and 2 or 1) + (tier >= 3 and 1 or 0)
	for i = 1, bars do
		local bar = Instance.new("Part")
		bar.Name = "Slash"
		bar.Anchored, bar.CanCollide, bar.CanTouch, bar.CanQuery, bar.CastShadow = true, false, false, false, false
		bar.Material = Enum.Material.Neon
		bar.Color = i == 1 and Color3.fromRGB(255, 255, 255) or (i == 3 and theme.light or theme.main)
		local long = (heavy and 11 or 7) * (1 + 0.08 * (tier - 1))
		bar.Size = Vector3.new(0.35, 0.35, 1)
		local tilt = ({ 30, -40, 75 })[i] + math.random(-10, 10)
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
	emitter.Color = tier >= 3 and colors({ Color3.fromRGB(255, 255, 255), theme.light, theme.main, theme.deep })
		or ColorSequence.new(Color3.fromRGB(255, 255, 255), color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new((heavy and 0.7 or 0.45) * (1 + 0.12 * (tier - 1)), 0)
	emitter.Lifetime = NumberRange.new(0.15, 0.35 + 0.04 * tier)
	emitter.Speed = NumberRange.new(20, heavy and 45 or 30)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 5
	emitter.Rate = 0
	emitter.Parent = sparks
	emitter:Emit(math.floor((heavy and 26 or 14) * (1 + 0.35 * (tier - 1))))
	if tier >= 5 then
		-- rings bursting out round the hit, in the theme's colours
		for k = 0, 2 do
			local ring = Instance.new("Part")
			ring.Name = "HitRing"
			ring.Shape = Enum.PartType.Cylinder
			ring.Anchored, ring.CanCollide, ring.CanTouch, ring.CanQuery, ring.CastShadow = true, false, false, false, false
			ring.Material = Enum.Material.Neon
			ring.Color = ({ theme.light, theme.main, theme.deep })[k + 1]
			ring.Size = Vector3.new(0.12, 1, 1)
			ring.CFrame = CFrame.lookAt(position, position + dir) * CFrame.Angles(0, math.rad(90), 0)
			ring.Transparency = 0.2
			ring.Parent = holder
			local grow = (heavy and 9 or 6) * (1 + k * 0.12)
			task.delay(k * 0.025, function()
				TweenService:Create(ring, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Size = Vector3.new(0.05, grow, grow), Transparency = 1 }):Play()
			end)
		end
	end
	-- Legendary and up: the theme's bits fly off what you hit (goo, dirt,
	-- coins, sparks, fire, confetti)
	if tier >= 4 then
		if theme.hitSound then
			soundAt(theme.hitSound, position, 0.95 + math.random() * 0.1, heavy and 1 or 0.8)
		end
		local fling = FLING[math.min(tier, 6)]
		for _ = 1, (heavy and 10 or 6) + tier do
			flingGoo(theme, position, Vector3.new(math.random() * 20 - 10, 8 + math.random() * 10, math.random() * 20 - 10),
				fling.size * (0.6 + math.random() * 0.5), position.Y - 3)
		end
	end
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

----------------------------------------------------------------------
-- The uploaded animations (Config: the type's Animations)
----------------------------------------------------------------------
-- Only your own screen plays them, on your own character - Roblox sends them
-- on to everyone else's screen by itself. Every screen then sees them
-- playing and leaves the body to them (the swings are Action animations, so
-- the sword code lets go just as it does for a roll; the idle is watched for
-- by its id).
local function animsOf(def)
	local kind = def and W.Types[def.Type]
	local a = kind and kind.Animations
	if type(a) ~= "table" then
		return nil
	end
	local function num(id)
		return id and tonumber(string.match(tostring(id), "(%d+)%s*$"))
	end
	local out = { idle = num(a.Idle), swings = {} }
	for n, id in ipairs(a.Swings or {}) do
		out.swings[n] = num(id)
	end
	return out
end

-- (the times the blade cuts, and when the swing's whoosh plays, in each
-- uploaded swing: its "Cut" and "Through" markers - Tools/Animations)
WeaponFX.ANIM_CUTS = { { 0.13, 0.36 }, { 0.13, 0.36 }, { 0.24, 0.6 } }
-- someone else's uploaded swing: how long to wait for it to arrive before
-- drawing it in code instead (seconds)
WeaponFX.REMOTE_WAIT = 0.15

local function loadTracks(char, def)
	local ids = animsOf(def)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not (ids and hum and #ids.swings > 0) then
		return nil
	end
	-- (Roblox puts an Animator in every character; one made here, on your own
	-- screen, wouldn't send the animations on to anyone else)
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local ok, tracks = pcall(function()
		local function load(id, priority, looped)
			local a = Instance.new("Animation")
			a.AnimationId = "rbxassetid://" .. id
			local track = animator:LoadAnimation(a)
			track.Priority = priority
			track.Looped = looped
			return track
		end
		local t = { swings = {} }
		if ids.idle then
			t.idle = load(ids.idle, Enum.AnimationPriority.Idle, true)
		end
		for n, id in ipairs(ids.swings) do
			t.swings[n] = load(id, Enum.AnimationPriority.Action, false)
		end
		return t
	end)
	return ok and tracks or nil
end

-- the number in an animation's id
local function idOf(track)
	local ok, id = pcall(function()
		return tonumber(string.match(tostring(track.Animation.AnimationId), "(%d+)%s*$"))
	end)
	return ok and id or nil
end

-- is this one of the weapon's own uploaded swings?
local function isOurSwing(h, track)
	local ids = h.animIds
	if not ids then
		return false
	end
	local id = idOf(track)
	for _, sid in ipairs(ids.swings) do
		if id == sid then
			return true
		end
	end
	return false
end

-- which of the weapon's uploaded animations are playing on this character
-- (on any screen): the swing (its number, its track, how much it shows) and
-- how much the idle shows. A track that's still loading - or couldn't load
-- (say the game can't use that animation) - has no length yet, and doesn't
-- count: the swings made in code stand in for it.
local function animsPlaying(h)
	local ids = h.animIds
	local animator = ids and h.hum and h.hum:FindFirstChildOfClass("Animator")
	if not animator then
		return nil, nil, 0, 0
	end
	local ok, list = pcall(function()
		return animator:GetPlayingAnimationTracks()
	end)
	if not ok or type(list) ~= "table" then
		return nil, nil, 0, 0
	end
	local swingN, swingTrack, idleW, swingW, abilityW = nil, nil, 0, 0, 0
	for _, track in ipairs(list) do
		local id = idOf(track)
		local fine, weight, length, playing = pcall(function()
			return track.WeightCurrent, track.Length, track.IsPlaying
		end)
		if fine and id and (tonumber(length) or 0) > 0 then
			weight = math.clamp(tonumber(weight) or 1, 0, 1)
			if ABILITY_IDS[id] and playing ~= false then
				abilityW = math.max(abilityW, weight) -- (an ability's animation: it holds the weapon too)
			elseif id == ids.idle then
				idleW = math.max(idleW, weight)
			elseif playing ~= false then
				-- (a swing that's been stopped is only fading out: the next one has it)
				for n, sid in ipairs(ids.swings) do
					if id == sid and (not swingTrack or weight > swingW) then
						swingN, swingTrack, swingW = n, track, weight
					end
				end
			end
		end
	end
	return swingN, swingTrack, idleW, swingW, abilityW
end

local function loaded(track)
	local ok, length = pcall(function()
		return track.Length
	end)
	return ok and (tonumber(length) or 0) > 0
end

local function stopSwings(h, fade)
	if h.tracks then
		for _, track in ipairs(h.tracks.swings) do
			if track.IsPlaying then
				track:Stop(fade or 0.1)
			end
		end
	end
	if h.frozenTrack then
		pcall(function()
			h.frozenTrack:AdjustSpeed(1)
		end)
		h.frozenTrack = nil
	end
end

-- done with them: stopped (eased out), then thrown away - a character can only
-- have so many loaded, and every fight loads them again
local function unloadTracks(tracks)
	pcall(function()
		for _, track in ipairs(tracks.swings) do
			track:Stop(0.15)
		end
		if tracks.idle then
			tracks.idle:Stop(0.25)
		end
	end)
	task.delay(0.3, function()
		pcall(function()
			for _, track in ipairs(tracks.swings) do
				track:Destroy()
			end
			if tracks.idle then
				tracks.idle:Destroy()
			end
		end)
	end)
end

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
	if h.tracks then
		unloadTracks(h.tracks)
		h.tracks = nil
	end
	held[plr] = nil
end

----------------------------------------------------------------------
-- Clips: the weapon types' animations, baked (gauntlets, hammer, daggers,
-- scythe, katana). Made the way the sword's uploaded animations are -
-- Tools/Animations/weapon_types.py: every swing travelling round a swing
-- plane with a coil, a whip through the enemy and a follow-through, the
-- chest ahead of the arm, the feet stepping - and baked frame by frame into
-- ReplicatedStorage/WeaponClips. Here they're played straight onto every R6
-- joint and the Grip, on every screen (nothing to upload): the idle loops
-- while you stand; a swing plays when you swing (everyone else's when their
-- SwingN changes). Walking, jumping, drinking and rolling take the body back
-- the same way as for the sword. Hit-stop freezes the clip for a blink; the
-- smear shows between its cut and through; the hammer's finisher slams the
-- floor at its hit.
----------------------------------------------------------------------
local decodedClips = {} -- [type] = { idle =, swings = {}, offhand = }

local function decodeClip(raw)
	local clip = { fps = raw.fps, frames = raw.frames, length = raw.length, loop = raw.loop,
		hit = raw.hit, lock = raw.lock, cut = raw.cut, through = raw.through, joints = {} }
	for key, text in pairs(raw.joints) do
		local list = {}
		for _, frame in ipairs(string.split(text, ";")) do
			local v = string.split(frame, ",")
			list[#list + 1] = CFrame.new(0, 0, tonumber(v[5]) or 0, tonumber(v[1]), tonumber(v[2]), tonumber(v[3]), tonumber(v[4]))
		end
		clip.joints[key] = list
	end
	return clip
end

-- a clip's first frame (every joint)
local function sampleClipFirst(clip)
	local pose = {}
	for key, list in pairs(clip.joints) do
		pose[key] = list[1]
	end
	return pose
end

-- a weapon type's clips (decoded the first time they're needed), or nil
function WeaponFX.clipsFor(kindName)
	if decodedClips[kindName] ~= nil then
		return decodedClips[kindName] or nil
	end
	local raw = CLIPS and kindName and CLIPS[kindName]
	if not raw then
		decodedClips[kindName or ""] = false
		return nil
	end
	local out = { idle = decodeClip(raw.Idle), swings = {}, offhand = raw.Offhand, twoHanded = raw.TwoHanded == true }
	for n, s in ipairs(raw.Swings) do
		out.swings[n] = decodeClip(s)
	end
	decodedClips[kindName] = out
	return out
end

-- every joint's Transform in `clip`, `t` seconds in (between its frames)
local function sampleClip(clip, t)
	local n = clip.frames
	local f = t * clip.fps
	local i0, i1
	if clip.loop then
		f = f % n
		i0 = math.floor(f)
		i1 = (i0 + 1) % n
	else
		f = math.clamp(f, 0, n - 1)
		i0 = math.floor(f)
		i1 = math.min(i0 + 1, n - 1)
	end
	local a = f - i0
	local pose = {}
	for key, list in pairs(clip.joints) do
		pose[key] = list[i0 + 1]:Lerp(list[i1 + 1], a)
	end
	return pose
end
WeaponFX.sampleClip = sampleClip

local function hold(plr, char, id, def, tracks)
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
	-- the weapon: its voxel model, else its imported 3D sword, else the
	-- blocky one made in code (and when its model turns up later - the
	-- server's still loading it - it's swapped in: see "rebuild")
	local function build()
		local m, hd, tr, bl = buildVoxel(def, golden)
		if not m then
			m, hd, tr, bl = buildModelSword(def, golden)
		end
		if not m then
			m, hd, tr, bl = (BUILDERS[def.Type] or buildSword)(def, golden)
		end
		-- (the rarer it is, the flashier its swings)
		local info = def.Model and INFO[def.Model]
		local glow = info and rgb(info.Glow, GLOW) or (def.Colors and def.Colors.Blade) or GLOW
		tr = dressTrails(tr or {}, def, glow, golden)
		return m, hd, tr, bl
	end
	local model, handle, trails, blade = build()
	local waiting = def.Model ~= nil and INFO[def.Model] ~= nil and voxelSource(def.Model) == nil
	-- the weapon type's baked animations, if it has them (and no uploaded ones)
	local kind = W.Types[def.Type]
	local ids = animsOf(def)
	-- (gauntlets punch with your own punch animations: nothing here moves the body)
	local punch = kind ~= nil and kind.UsePunch == true
	local clips = not punch and not (ids and #ids.swings > 0) and WeaponFX.clipsFor(def.Type) or nil
	-- a second one in the left hand (gauntlets, daggers): held still at the
	-- hand; the string's poses swing the left arm for its blows
	local off = (clips and clips.offhand) or WeaponFX.OFFHAND[def.Type]
	local leftArm = char:FindFirstChild("Left Arm")
	if off and leftArm and BUILDERS[def.Type] then
		local offModel, offHandle, offTrails = build()
		offHandle.CFrame = leftArm.CFrame * gripAt(off[1], off[2])
		local w = Instance.new("Weld")
		w.Name = "OffGrip"
		w.Part0, w.Part1 = leftArm, offHandle
		w.C0 = gripAt(off[1], off[2])
		w.Parent = offHandle
		for _, t in ipairs(offTrails) do
			table.insert(trails, t)
		end
		for _, child in ipairs(offModel:GetChildren()) do
			child.Parent = model
		end
		offModel:Destroy()
	end
	local base = stanceOf(def)
	local g = base.Grip
	if punch and off then
		g = off -- (the right gauntlet sits on the hand just like the left one)
	end
	handle.CFrame = arm.CFrame * gripAt(g[1], g[2])
	-- held by a Motor6D (Right Arm -> Handle), so the uploaded animations can
	-- swing the blade too (they pose "Handle" under "Right Arm"). Made in
	-- code, its C0 holds the grip; while an animation has it, C0 is just the
	-- hand and the animation turns it.
	local weld = Instance.new("Motor6D")
	weld.Name = "Grip"
	weld.Part0, weld.Part1 = arm, handle
	weld.C0 = gripAt(g[1], g[2])
	if clips then
		-- (a clip turns the weapon with the Grip's Transform, from the hand)
		weld.C0 = GRIP_HAND
		weld.Transform = sampleClipFirst(clips.idle).Grip
		handle.CFrame = arm.CFrame * GRIP_HAND * weld.Transform
	end
	weld.Parent = handle
	model.Parent = char
	local mem, weights = {}, {}
	for key, joint in pairs(joints) do
		mem[joint] = { rest = joint.Transform }
		weights[key] = 0
	end
	-- the springs start where the stance is
	local springs = {}
	for key, value in pairs(base) do
		springs[key] = { p = table.clone(value), v = table.create(#value, 0) }
	end
	held[plr] = {
		waiting = waiting, -- (its model isn't here yet: swapped in when it is)
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
		animIds = animsOf(def),
		clips = clips,
		punch = punch,
		tracks = tracks or (plr == Players.LocalPlayer and loadTracks(char, def) or nil),
		seen = setmetatable({}, { __mode = "k" }), -- the animation tracks we've whooshed for
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
	if h.clips then
		local clip = h.clips.swings[n]
		if clip then
			h.anim = { kind = "clip", clip = clip, t = 0, n = n, slam = kind ~= nil and kind.SlamSwing == n,
				sound = kind and kind.Sounds and kind.Sounds.Swing }
			h.freeze = 0
		end
		return
	end
	local s = kind and kind.Swings[n]
	local keys = WeaponFX.POSES[h.def and h.def.Type or ""]
	if not (s and keys and keys[n]) then
		return
	end
	h.anim = { kind = "swing", t = 0, swing = s, m = WeaponFX.swingMoments(s), keys = keys[n], n = n, slam = kind.SlamSwing == n, sound = kind.Sounds and kind.Sounds.Swing, from = h.springs and whereNow(h) }
	h.freeze = 0
end

-- start the ability (the Whirlwind) at a tier for this player (now)
local function startSpin(h, tierIndex)
	local ab = h.def and h.def.Ability
	local tier = ab and ab.Tiers and ab.Tiers[math.clamp(tierIndex or 1, 1, #ab.Tiers)]
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

WeaponFX._swingFx = swingFx -- (for the headless tests)

local function setSmear(h, on)
	local starting = on and not h.smearOn
	h.smearOn = on
	-- (the smear stays off while the blade is right up at your camera - it
	-- drew a glowing sheet over the whole screen)
	local show = on
	local blade = h.trails[1] and h.trails[1].Parent
	local eye = show and cameraAt()
	if eye and blade and blade:IsA("BasePart") and (blade.Position - eye).Magnitude < NEAR_CAMERA + 2 then
		show = false
	end
	for _, t in ipairs(h.trails) do
		if t.Enabled ~= show then
			t.Enabled = show
		end
	end
	-- (the rarer ones throw goo and more: see "Swing effects by rarity")
	swingFx(h, on, starting)
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
		-- (a track played at no weight is just being warmed up: it doesn't
		-- count; nor do the weapon's own uploaded swings - see targetFor)
		if fine and ACTION[pri] and track.IsPlaying ~= false and (tonumber(weight) or 1) > 0.05 and not isOurSwing(h, track) then
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
	local stance = copyPose(stanceOf(h.def))
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
	-- the uploaded animations: your own idle plays while you stand still with
	-- nothing else going on; on every screen, while it or a swing plays, the
	-- body and the grip are theirs (the Whirlwind, made in code, always wins)
	local swingN, swingTrack, idleW, swingW, abilityW = animsPlaying(h)
	local spinning = h.anim ~= nil and h.anim.kind == "spin"
	if spinning then
		swingN, swingTrack, idleW, swingW = nil, nil, 0, 0
	elseif swingTrack and h.anim and h.anim.n ~= swingN then
		-- (an older uploaded swing still going: the newer one, drawn in code, has it)
		swingN, swingTrack, swingW = nil, nil, 0
	end
	local idle = h.tracks and h.tracks.idle
	if idle then
		local wantIdle = not moving and not drinking and not spinning and not inAir(h) and loaded(idle)
		if wantIdle and not idle.IsPlaying then
			idle:Play(0.3)
		elseif not wantIdle and idle.IsPlaying then
			idle:Stop(0.25)
		end
	end
	if swingTrack then
		-- an uploaded swing has the body: the one made in code steps aside
		-- (theirs arriving late, after we'd started drawing it ourselves)
		h.anim = nil
		if h.waitSwing and h.waitSwing.n == swingN then
			h.waitSwing = nil
		end
		rolling = true -- (handed over quickly, like a roll)
	end
	-- (a swing or the Whirlwind made in code - say the uploaded swing hadn't
	-- loaded yet - shows over the idle)
	local drawn = h.anim ~= nil
	if swingTrack or (idleW > 0.05 and not drawn) then
		for key in pairs(want) do
			want[key] = 0
		end
	end
	-- how much the animations hold the blade (see stepOne)
	h.animGrip = drawn and 0 or math.max(idleW, swingW, abilityW or 0)
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
				if a.slam and not a.slammed and a.t >= m.contact then
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
	if swingTrack then
		-- an uploaded swing: the smear between its Cut and Through, the whoosh as it cuts
		local kindCuts = h.def and W.Types[h.def.Type] and W.Types[h.def.Type].AnimCuts
		local cut = (kindCuts or WeaponFX.ANIM_CUTS)[swingN] or WeaponFX.ANIM_CUTS[1]
		local ok, tp = pcall(function()
			return swingTrack.TimePosition
		end)
		tp = ok and tonumber(tp) or 0
		local seen = h.seen[swingTrack]
		if not seen or tp < seen.tp - 0.05 then
			seen = { tp = tp, whooshed = false } -- (played again from the start)
			h.seen[swingTrack] = seen
		end
		seen.tp = tp
		cutting = tp >= cut[1] and tp <= cut[2]
		if not seen.whooshed and tp >= cut[1] - 0.03 then
			seen.whooshed = true
			local kind = h.def and W.Types[h.def.Type]
			playAt(kind and kind.Sounds and kind.Sounds.Swing, h.handle, (1.08 - 0.06 * swingN) * (0.96 + 0.08 * math.random()))
		end
	end
	return stance, want, mode, turn, cutting, drinking, rolling
end

local function stepClips(plr, h, dt)
	local clips = h.clips
	local md = h.hum and h.hum.MoveDirection
	local moving = typeof(md) == "Vector3" and md.Magnitude > 0.1
	h.clock = h.clock + dt
	local drinking = h.char:GetAttribute("Drinking") ~= nil
	local rolling = actionPlaying(h)
	local airborne = inAir(h)
	local a = h.anim
	if a and (rolling or a.kind ~= "clip") then
		h.anim, a = nil, nil -- (a roll cancels a swing)
	end
	-- the swing's clock: frozen for a blink by hit-stop
	local cutting = false
	if a then
		local c = a.clip
		if h.freeze > 0 then
			h.freeze = h.freeze - dt
		else
			a.t = a.t + dt
			if not a.whooshed and a.t >= (c.cut or 0) - 0.03 then
				a.whooshed = true
				-- (a touch different every time, so a string never sounds canned)
				playAt(a.sound, h.handle, (1.08 - 0.06 * a.n) * (0.96 + 0.08 * math.random()))
			end
			if a.slam and not a.slammed and a.t >= (c.hit or 0) then
				a.slammed, a.slamNow = true, true
			end
			if a.t >= c.length then
				h.anim, a = nil, nil
			end
		end
		if a then
			cutting = a.t >= (a.clip.cut or 0) and a.t <= (a.clip.through or 0)
		end
	end
	local pose = a and sampleClip(a.clip, a.t) or sampleClip(clips.idle, h.clock)
	-- how much of each joint the clip holds: all of it in a swing (until it
	-- lets you go); walking, the legs and body walk and the weapon arms hold on
	local want = { Root = 1, RS = 1, LS = 1, RH = 1, LH = 1, Neck = 1 }
	local committed = a ~= nil and a.t < (a.clip.lock or a.clip.length)
	if not committed then
		if moving then
			want.Root, want.RH, want.LH, want.Neck = 0, 0, 0, 0.3
			want.RS = 0.85
			want.LS = clips.twoHanded and 0.85 or 0
		end
		if airborne then
			want.Root, want.RH, want.LH = 0, 0, 0
			want.LS = math.min(want.LS, 0.5)
		end
	end
	if drinking then
		want.RS, want.Neck, want.LS = 0, 0, 0 -- (your arm and head belong to the drink)
	end
	if rolling then
		for key in pairs(want) do
			want[key] = 0
		end
	end
	local rs = pose.RS
	if a and h.freeze > 0 then
		-- the shudder: the arm judders as the weapon bites
		rs = rs * CFrame.Angles(0, 0, rad((math.random() - 0.5) * 5))
	end
	local show = { Root = pose.Root, RS = rs, LS = pose.LS, RH = pose.RH, LH = pose.LH, Neck = pose.Neck }
	for _, key in ipairs(WeaponFX.JOINTS) do
		local joint = h.joints[key]
		if joint then
			local w = h.weights[key]
			local goal = want[key]
			local rate = rolling and 40 or (goal < w and 16 or (a and 30 or 8))
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
	-- the weapon in the hand: the clip turns it (the Grip's Transform)
	h.weld.C0 = GRIP_HAND
	h.weld.Transform = pose.Grip
	setSmear(h, cutting)
	-- tucked away while you drink (the potion's in that hand)
	local wantParent = (not drinking) and h.char or nil
	if h.model.Parent ~= wantParent then
		h.model.Parent = wantParent
	end
	-- the hammer's finisher hits the floor: a shockwave where the head lands
	if a and a.slamNow then
		a.slamNow = false
		local ok, tip = pcall(function()
			return h.blade.CFrame.Position
		end)
		local hrp = h.char:FindFirstChild("HumanoidRootPart")
		if ok and hrp then
			WeaponFX.groundSlam(Vector3.new(tip.X, hrp.Position.Y + WeaponFX.GROUND + 0.1, tip.Z), h.golden)
		end
	end
end

local function stepOne(plr, h, dt)
	-- awakened (mastery 100): the blade turns gold
	local golden = (plr:GetAttribute("Mastery") or 1) >= (W.MasteryMax or 100)
	if golden ~= h.golden or h.rebuild then
		local char, id, def, anim, springs, weights, clock, freeze = h.char, h.id, h.def, h.anim, h.springs, h.weights, h.clock, h.freeze
		local tracks, frozenTrack, trackFreeze = h.tracks, h.frozenTrack, h.trackFreeze
		h.tracks = nil -- (kept: a swing that's playing carries on)
		drop(plr)
		h = hold(plr, char, id, def, tracks)
		if h.none then
			if tracks then
				unloadTracks(tracks)
			end
			return
		end
		h.anim, h.springs, h.weights, h.clock, h.freeze = anim, springs, weights, clock, freeze
		h.frozenTrack, h.trackFreeze = frozenTrack, trackFreeze
	end
	if h.punch then
		-- gauntlets: your punch animations swing the arms and the gauntlets ride
		-- on your hands (tucked away while you drink)
		local wantParent = h.char:GetAttribute("Drinking") == nil and h.char or nil
		if h.model.Parent ~= wantParent then
			h.model.Parent = wantParent
		end
		return
	end
	-- everyone else's swings and abilities: when their counters change
	if plr ~= Players.LocalPlayer then
		local sn = plr:GetAttribute("SwingN")
		if sn ~= h.swingN then
			h.swingN = sn
			local n = tail(sn)
			if n and h.animIds and h.animIds.swings[n] then
				-- an uploaded swing: Roblox sends theirs to this screen by
				-- itself. If it hasn't shown up in a moment (it couldn't load,
				-- or it's slow), it's drawn in code instead
				h.waitSwing = { n = n, t = 0 }
			elseif n then
				startSwing(h, n)
			end
		end
		local ws = h.waitSwing
		if ws then
			ws.t = ws.t + dt
			if ws.t >= WeaponFX.REMOTE_WAIT then
				h.waitSwing = nil
				startSwing(h, ws.n)
				if h.anim then
					h.anim.t = ws.t -- (caught up to where it should be by now)
				end
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
	if h.clips then
		stepClips(plr, h, dt)
		return
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
	local animHold = h.animGrip or 0
	if animHold > 0.001 then
		-- an animation turns the blade (the Grip's Transform): C0 hands over
		-- to just the hand as it takes over (and back as it lets go)
		h.weld.C0 = gripAt(g[1], g[2]):Lerp(GRIP_HAND, animHold)
	else
		h.weld.C0 = gripAt(g[1], g[2])
		h.weld.Transform = CFrame.new()
	end
	-- hit-stop in an uploaded swing: it stops dead for a blink
	if h.frozenTrack then
		h.trackFreeze = h.trackFreeze - dt
		if h.trackFreeze <= 0 then
			pcall(function()
				h.frozenTrack:AdjustSpeed(1)
			end)
			h.frozenTrack = nil
		end
	end
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
	if h and not h.none and not h.punch then
		local track = h.tracks and h.tracks.swings[n]
		if track and loaded(track) then
			-- the uploaded swing. Chained, it hands over at once (each one
			-- starts where the last one's follow-through is); from the stance
			-- it eases in a touch more
			local chained = false
			for _, other in ipairs(h.tracks.swings) do
				chained = chained or (other ~= track and other.IsPlaying)
			end
			stopSwings(h, 0.08)
			track:Play(chained and 0.05 or 0.1)
			track.TimePosition = 0
			h.anim = nil
			return
		end
		-- (not loaded - yet, or at all: the swing made in code)
		stopSwings(h, 0.08)
		startSwing(h, n)
	end
end

-- your own ability, the moment you press (at this tier)
function WeaponFX.spin(plr, tierIndex)
	local h = held[plr]
	if h and not h.none and not h.punch then
		stopSwings(h, 0.05)
		startSpin(h, tierIndex)
	end
end

-- hit-stop: your swing freezes for a blink (and shudders) as the blade bites
function WeaponFX.hitStop(plr, seconds)
	local h = held[plr]
	if h and not h.none and h.punch then
		return
	end
	if h and not h.none and h.anim then
		h.freeze = math.max(h.freeze, seconds or 0.05)
	end
	local track = h and not h.none and h.tracks and select(2, animsPlaying(h))
	if track and not (h.anim and h.anim.kind == "spin") then
		pcall(function()
			track:AdjustSpeed(0)
		end)
		h.frozenTrack = track
		h.trackFreeze = math.max(h.trackFreeze or 0, seconds or 0.05)
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
	-- a voxel weapon's model arriving (the server loads them as the game
	-- starts): anyone holding the blocky stand-in for it gets the real one
	local function watch(folder)
		folder.ChildAdded:Connect(function(child)
			for _, h in pairs(held) do
				if h.waiting and h.def and h.def.Model == child.Name then
					h.rebuild = true
				end
			end
		end)
	end
	local folder = ReplicatedStorage:FindFirstChild("WeaponModels")
	if folder then
		watch(folder)
	else
		local conn
		conn = ReplicatedStorage.ChildAdded:Connect(function(child)
			if child.Name == "WeaponModels" and child:IsA("Folder") then
				conn:Disconnect()
				watch(child)
				for _, m in ipairs(child:GetChildren()) do
					for _, h in pairs(held) do
						if h.waiting and h.def and h.def.Model == m.Name then
							h.rebuild = true
						end
					end
				end
			end
		end)
	end
	-- warm up the baked clips: unpack every type's now (one a frame), so the
	-- first time anyone equips one there's no hitch
	task.spawn(function()
		for name in pairs(CLIPS or {}) do
			WeaponFX.clipsFor(name)
			task.wait()
		end
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
		-- and the uploaded animations, so the first swing (yours or anyone's) plays at once
		for _, kind in pairs(W.Types) do
			local a = kind.Animations
			if type(a) == "table" then
				for _, id in ipairs({ a.Idle, table.unpack(a.Swings or {}) }) do
					if id and id ~= "" then
						local anim = Instance.new("Animation")
						anim.AnimationId = id
						list[#list + 1] = anim
					end
				end
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
