--[[
	WeaponFX  (ModuleScript, parent: ReplicatedStorage, name: "WeaponFX")

	How weapons look, on every screen: the weapon in each fighter's hand, its
	swings and its ability - all made in code on the R6 joints (the right
	arm, the body turning, and the weapon's angle in the hand). No uploaded
	animations.

	  * THE WEAPON: anyone holding one in a fight (the "Weapon" attribute
	    CombatService sets) has it in their right hand - built on this screen
	    only, from the weapon's colours in Config.Weapons. Carried pointing up
	    and forward; out of a fight it's put away.
	  * A SWING: wind up, cut, follow through, back to normal - the three
	    swings of the sword's string are a slash right to left, a backhand,
	    and an overhead chop. In a swing the blade turns in line with your
	    arm, for a long reach, and a white trail follows it.
	  * THE ABILITY (the Iron Sword's Whirlwind): arm straight out, and the
	    whole body spins round - once, twice or three times, by mastery.
	  * AWAKENED (mastery 100): the blade turns glowing gold.

	Your own swings start the moment you press (CombatClient calls
	WeaponFX.swing / WeaponFX.spin); everyone else's start when their SwingN
	/ AbilityN attribute changes (CombatService sets those).

	Sounds (Sounds in SoundService, by name - capitals and spaces don't
	matter): each type's Sounds.Swing ("Sword Swing") and each ability's
	Sound ("Whirlwind"). Missing ones are just silent.
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
-- Each swing has three moments: wound up, the cut (the blade halfway through
-- its arc - the moment it lands), and the follow-through. A moment is
-- { x, y, z, twist }: the right arm's turn at the shoulder (CFrame.Angles on
-- the shoulder joint: z swings it forward and up, y sweeps it across the
-- body - more y is further left) and how far the body turns (+ = the right
-- shoulder back, winding up).
WeaponFX.POSES = {
	Sword = {
		{ wind = { 0, -75, 100, 28 }, cut = { 0, 5, 95, 0 }, finish = { 0, 80, 88, -32 } }, -- a slash, right to left
		{ wind = { 0, 85, 100, -32 }, cut = { 0, 0, 95, 0 }, finish = { 0, -70, 92, 28 } }, -- a backhand, left to right
		{ wind = { 0, 10, 185, 8 }, cut = { 0, 8, 95, 0 }, finish = { 0, 5, 55, -4 } }, -- an overhead chop
	},
}
WeaponFX.SPIN_ARM = { 0, -80, 95 } -- the Whirlwind: the arm straight out to the side
WeaponFX.GRIP_CARRY = 30 -- the blade's tilt in the hand when you're just holding it (up and forward)
WeaponFX.GRIP_SWING = -70 -- ...and mid-swing: nearly in line with the arm, for a long reach

local function smooth(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end
local function mix(a, b, t)
	return a + (b - a) * t
end
local function mixPose(p, q, t)
	return { mix(p[1], q[1], t), mix(p[2], q[2], t), mix(p[3], q[3], t), mix(p[4], q[4], t) }
end

-- A swing `u` of the way through (0 = pressed, 1 = over), whose blade lands
-- `contact` of the way through. Gives the pose ({ x, y, z, twist }), the
-- blade's tilt in the hand, and how much of it shows over whatever the arm
-- was doing before (0 to 1: it blends in, and back out at the end).
function WeaponFX.swingPose(keys, u, contact)
	contact = math.clamp(contact or 0.4, 0.15, 0.8)
	u = math.clamp(u, 0, 1)
	local uWind = contact * 0.45 -- wound up by here...
	local uFinish = math.min(0.85, contact + 0.28) -- ...and followed through by here
	local pose, grip
	if u < uWind then
		pose = keys.wind
		grip = mix(WeaponFX.GRIP_CARRY, WeaponFX.GRIP_SWING, smooth(u / uWind))
	elseif u < contact then
		local t = (u - uWind) / (contact - uWind)
		pose = mixPose(keys.wind, keys.cut, t * t) -- speeding up into the cut
		grip = WeaponFX.GRIP_SWING
	elseif u < uFinish then
		local t = (u - contact) / (uFinish - contact)
		pose = mixPose(keys.cut, keys.finish, 1 - (1 - t) * (1 - t)) -- ...and slowing out of it
		grip = WeaponFX.GRIP_SWING
	else
		pose = keys.finish
		grip = mix(WeaponFX.GRIP_SWING, WeaponFX.GRIP_CARRY, smooth((u - uFinish) / (1 - uFinish)))
	end
	local weight = math.min(smooth(u / (uWind * 0.8)), 1 - smooth((u - uFinish) / (1 - uFinish)))
	return pose, grip, weight
end

-- The Whirlwind `u` of the way through `spins` spins: the arm out, the body
-- turning all the way round each spin (the same way a first slash cuts).
function WeaponFX.spinPose(u, spins)
	u = math.clamp(u, 0, 1)
	local eased = u < 0.5 and 2 * u * u or 1 - 2 * (1 - u) * (1 - u)
	local turn = -360 * spins * (0.8 * u + 0.2 * eased) -- (nearly steady, easing in and out a little)
	local arm = WeaponFX.SPIN_ARM
	local weight = math.min(smooth(u / 0.12), 1 - smooth((u - 0.88) / 0.12))
	return { arm[1], arm[2], arm[3], turn }, WeaponFX.GRIP_SWING, weight
end

-- the blade's place in the hand at a tilt (degrees)
local function gripAt(tilt)
	return CFrame.new(0, -1, 0) * CFrame.Angles(rad(tilt), 0, 0)
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
	handle = piece("Handle", Vector3.new(0.3, 0.3, 0.8), CFrame.new(), c.Grip or Color3.fromRGB(115, 62, 57))
	local metal = golden and GOLD or (c.Blade or Color3.fromRGB(192, 203, 220))
	local shine = golden and Enum.Material.Neon or Enum.Material.SmoothPlastic
	piece("Pommel", Vector3.new(0.42, 0.42, 0.42), CFrame.new(0, 0, 0.55), c.Guard or GOLD)
	piece("Guard", Vector3.new(1.15, 0.28, 0.3), CFrame.new(0, 0, -0.52), c.Guard or GOLD)
	local blade = piece("Blade", Vector3.new(0.22, 0.5, 3), CFrame.new(0, 0, -2.17), metal, shine)
	piece("Edge", Vector3.new(0.24, 0.12, 2.8), CFrame.new(0, 0.2, -2.17), c.Edge or Color3.fromRGB(255, 255, 255), shine)
	piece("Tip", Vector3.new(0.22, 0.3, 0.35), CFrame.new(0, -0.05, -3.84), metal, shine)
	-- the trail that follows the blade through a swing
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailBase"
	a0.Position = Vector3.new(0, 0, 1.2)
	a0.Parent = blade
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailTip"
	a1.Position = Vector3.new(0, 0, -1.8)
	a1.Parent = blade
	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = ColorSequence.new(golden and GOLD or Color3.fromRGB(255, 255, 255))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	trail.LightEmission = 0.7
	trail.Lifetime = 0.16
	trail.MinLength = 0.05
	trail.Enabled = false
	trail.Parent = blade
	return model, handle, trail
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
	local shoulder = torso and torso:FindFirstChild("Right Shoulder")
	local rootJoint = hrp and hrp:FindFirstChild("RootJoint")
	if not (arm and shoulder and shoulder:IsA("Motor6D")) then
		-- (not an R6 body: nothing to hold it with)
		held[plr] = { char = char, id = id, none = true }
		return held[plr]
	end
	local golden = (plr:GetAttribute("Mastery") or 1) >= (W.MasteryMax or 100)
	local model, handle, trail = buildSword(def, golden)
	handle.CFrame = arm.CFrame * gripAt(WeaponFX.GRIP_CARRY)
	local weld = Instance.new("Weld")
	weld.Name = "Grip"
	weld.Part0, weld.Part1 = arm, handle
	weld.C0 = gripAt(WeaponFX.GRIP_CARRY)
	weld.Parent = handle
	model.Parent = char
	local mem = { [shoulder] = { rest = shoulder.Transform } }
	if rootJoint and rootJoint:IsA("Motor6D") then
		mem[rootJoint] = { rest = rootJoint.Transform }
	else
		rootJoint = nil
	end
	held[plr] = {
		char = char,
		id = id,
		def = def,
		model = model,
		handle = handle,
		weld = weld,
		trail = trail,
		shoulder = shoulder,
		root = rootJoint,
		mem = mem,
		golden = golden,
		anim = nil,
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
	h.anim = { kind = "swing", t = 0, dur = s.Lock, contact = s.Contact, keys = keys[n] }
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
	local kind = W.Types[h.def.Type]
	if not playAt(ab.Sound, h.handle) then
		playAt(kind and kind.Sounds and kind.Sounds.Swing, h.handle, 0.85)
	end
end

-- the number after the colon in "count:n"
local function tail(value)
	return tonumber(string.match(tostring(value), ":(%d+)$"))
end

local function stepOne(plr, h, dt)
	-- awakened (mastery 100): the blade turns gold
	local golden = (plr:GetAttribute("Mastery") or 1) >= (W.MasteryMax or 100)
	if golden ~= h.golden then
		h.golden = golden
		local char, id, def = h.char, h.id, h.def
		drop(plr)
		h = hold(plr, char, id, def)
		if h.none then
			return
		end
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
	local a = h.anim
	local pose, grip, weight
	if a then
		a.t = a.t + dt
		local u = a.t / a.dur
		if u >= 1 then
			h.anim = nil
		elseif a.kind == "swing" then
			pose, grip, weight = WeaponFX.swingPose(a.keys, u, a.contact)
		else
			pose, grip, weight = WeaponFX.spinPose(u, a.spins)
		end
	end
	if pose and weight > 0 then
		blend(h, h.shoulder, CFrame.Angles(rad(pose[1]), rad(pose[2]), rad(pose[3])), weight)
		if h.root then
			blend(h, h.root, CFrame.Angles(0, 0, rad(pose[4])), weight)
		end
		h.weld.C0 = gripAt(grip)
		h.trail.Enabled = weight > 0.5
	else
		if h.trail.Enabled then
			h.trail.Enabled = false
		end
		release(h)
		h.weld.C0 = gripAt(WeaponFX.GRIP_CARRY)
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
