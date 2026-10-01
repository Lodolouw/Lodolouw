--!nocheck
-- Headless test of the sword's UPLOADED ANIMATIONS and 3D MODEL (WeaponFX
-- with Config.Weapons.Types.Sword.Animations and the IronSword's Model) - the
-- real module, with a pretend Animator that plays pretend tracks:
--   * the 3D sword (a model in ReplicatedStorage, as Studio's 3D Importer
--     leaves it) is held at its grip, blade along the Handle's -Z, scaled to
--     its real length, its glowing pixels Neon; missing, it's the blocky one
--   * the Grip is a Motor6D (Right Arm -> Handle), so animations can turn it
--   * your idle plays standing still and the body is left to it; walking,
--     the idle stops and the stance made in code takes the sword arm back
--   * a swing plays its uploaded animation from the start; the smear shows
--     between its Cut and Through and the whoosh plays once, as it cuts;
--     chained swings hand over at once; hit-stop stops it dead for a blink
--   * a swing that hasn't loaded is drawn in code instead; the Whirlwind
--     (made in code) stops any swing and isn't cut short by one
--   * someone else's uploaded swing arrives by itself (nothing drawn over
--     it); if it doesn't arrive in a moment, it's drawn in code
--   * leaving the fight stops and throws the tracks away
--
--   luau test_swordanims.luau
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Instance, CFrame, Vector3, Enum, Color3 = M.Instance, M.CFrame, M.Vector3, M.Enum, M.Color3
local Players = M.services.Players
local RunService = M.services.RunService
local SoundService = M.services.SoundService
local ReplicatedStorage = M.services.ReplicatedStorage

local whoosh = Instance.new("Sound")
whoosh.Name = "Sword Swing"
whoosh.PlaybackSpeed = 1
whoosh.TimeLength = 0.4
whoosh.Parent = SoundService

local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local WeaponFX = mount.require(mount.module("ReplicatedStorage/WeaponFX.lua"))
local A = Config.Weapons.Types.Sword.Animations

local fails = 0
local function check(ok, msg)
	if not ok then
		fails += 1
		print("FAIL: " .. msg)
	end
end
local function near(a, b, eps)
	return math.abs(a - b) < (eps or 1e-3)
end
local function idNum(s)
	return tonumber(string.match(tostring(s), "(%d+)%s*$"))
end

------------------------------------------------------------------
-- the 3D model, as the 3D Importer leaves it: standing on its pommel, tip
-- up, and (here) twice the size it should be
------------------------------------------------------------------
local function mesh(model, name, size, at)
	local p = Instance.new("MeshPart")
	p.Name = name
	p.Size = size
	p.CFrame = at
	p.Color = Color3.fromRGB(163, 162, 165)
	p.Transparency = 0
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = true
	p.CanTouch = true
	p.CastShadow = true
	p.Material = Enum.Material.Plastic
	p.Parent = model
	return p
end
local src = Instance.new("Model")
src.Name = "IronWarden"
mesh(src, "IronWarden", Vector3.new(2.6, 10, 0.4), CFrame.new(20, 5, 0)) -- pommel at y 0, tip at y 10
mesh(src, "IronWardenGlow", Vector3.new(0.3, 7, 0.45), CFrame.new(20, 6, 0))
local stray = Instance.new("WeldConstraint") -- (anything holding it in place is thrown away)
stray.Parent = src
src.Parent = ReplicatedStorage

------------------------------------------------------------------
-- a pretend R6 character, and a pretend Animator that plays pretend tracks
------------------------------------------------------------------
local function part(model, name, size)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = CFrame.new()
	p.Parent = model
	return p
end
local function motor(name, parent, p0, p1, c0, c1)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0, m.Part1 = p0, p1
	m.C0, m.C1 = c0, c1
	m.Transform = CFrame.new()
	m.Parent = parent
	return m
end

local LENGTH = { [idNum(A.Idle)] = 2.383, [idNum(A.Swings[1])] = 0.85, [idNum(A.Swings[2])] = 0.85, [idNum(A.Swings[3])] = 1.2 }

-- a track: plays, fades its weight in and out, moves on in time, ends
local function newTrack(anim, length, list)
	local tr = { Animation = anim, Length = length, TimePosition = 0, IsPlaying = false, WeightCurrent = 0, WeightTarget = 0,
		Speed = 1, Looped = false, fade = 0, plays = 0, destroyed = false }
	function tr:Play(fade, weight, speed)
		self.IsPlaying = true
		self.TimePosition = 0
		self.WeightTarget = weight or 1
		self.fade = fade or 0.1
		self.Speed = speed or 1
		self.plays += 1
		if not table.find(list, self) then
			table.insert(list, self)
		end
	end
	function tr:Stop(fade)
		self.IsPlaying = false
		self.WeightTarget = 0
		self.fade = fade or 0.1
	end
	function tr:AdjustSpeed(s)
		self.Speed = s
	end
	function tr:Destroy()
		self.destroyed = true
		self:Stop(0)
	end
	return tr
end
local function tick(list, dt)
	for i = #list, 1, -1 do
		local tr = list[i]
		if tr.IsPlaying then
			tr.TimePosition += dt * tr.Speed
			if tr.TimePosition >= tr.Length then
				if tr.Looped then
					tr.TimePosition -= tr.Length
				else
					tr.TimePosition = tr.Length
					tr:Stop(0)
				end
			end
		end
		if tr.fade <= 0 then
			tr.WeightCurrent = tr.WeightTarget
		else
			local d = dt / tr.fade
			tr.WeightCurrent = tr.WeightCurrent + math.clamp(tr.WeightTarget - tr.WeightCurrent, -d, d)
		end
		if not tr.IsPlaying and tr.WeightCurrent <= 0 then
			table.remove(list, i)
		end
	end
end

local function r6(name)
	local model = Instance.new("Model")
	model.Name = name
	local hrp = part(model, "HumanoidRootPart", Vector3.new(2, 2, 1))
	local torso = part(model, "Torso", Vector3.new(2, 2, 1))
	local arm = part(model, "Right Arm", Vector3.new(1, 2, 1))
	local larm = part(model, "Left Arm", Vector3.new(1, 2, 1))
	local rleg = part(model, "Right Leg", Vector3.new(1, 2, 1))
	local lleg = part(model, "Left Leg", Vector3.new(1, 2, 1))
	local head = part(model, "Head", Vector3.new(2, 1, 1))
	local hum = Instance.new("Humanoid")
	hum.MaxHealth = 100
	hum.Health = 100
	hum.MoveDirection = Vector3.new(0, 0, 0)
	hum.Parent = model
	hum.GetState = function()
		return Enum.HumanoidStateType.Running
	end
	local j = {}
	j.RS = motor("Right Shoulder", torso, torso, arm, CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	j.LS = motor("Left Shoulder", torso, torso, larm, CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
	j.RH = motor("Right Hip", torso, torso, rleg, CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	j.LH = motor("Left Hip", torso, torso, lleg, CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
	j.Neck = motor("Neck", torso, torso, head, CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	j.Root = motor("RootJoint", hrp, hrp, torso, CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	local animator = Instance.new("Animator")
	animator.Parent = hum
	local playing, made = {}, {}
	animator.GetPlayingAnimationTracks = function()
		return playing
	end
	animator.LoadAnimation = function(_, anim)
		local tr = newTrack(anim, LENGTH[idNum(anim.AnimationId)] or 1, playing)
		made[#made + 1] = tr
		return tr
	end
	model.Parent = M.workspace
	return model, j, hum, playing, made
end

local me = Instance.new("Player")
me.Name = "Tester"
me.UserId = 1001
me.Parent = Players
Players.LocalPlayer = me
local char, J, hum, playing, made = r6("Tester")
me.Character = char
M.players = { me }

WeaponFX.start()

local lists = { playing }
local t = 0
local GRIP_POSE = CFrame.Angles(math.rad(-50), 0, 0)
-- each frame: the Animator moves the tracks on (and, while one of ours shows,
-- turns the blade, as Roblox would), then the sword code, then `each`
local function step(seconds, each)
	local stop = t + seconds
	while t < stop - 1e-9 do
		t += 1 / 60
		M.run(t)
		for _, list in ipairs(lists) do
			tick(list, 1 / 60)
		end
		local h = WeaponFX._held[me]
		if h and h.weld then
			local w = 0
			for _, tr in ipairs(playing) do
				w = math.max(w, tr.WeightCurrent)
			end
			if w > 0 then
				h.weld.Transform = CFrame.new():Lerp(GRIP_POSE, w)
			end
		end
		RunService.Stepped:Fire(t, 1 / 60)
		RunService.RenderStepped:Fire(1 / 60)
		if each then
			each()
		end
	end
end
local function trackFor(id)
	for _, tr in ipairs(made) do
		if idNum(tr.Animation.AnimationId) == idNum(id) and not tr.destroyed then
			return tr
		end
	end
	return nil
end
local function isRest(j)
	local c = j.Transform
	return (c.Position).Magnitude < 1e-6 and (c.LookVector - Vector3.new(0, 0, -1)).Magnitude < 1e-6 and (c.UpVector - Vector3.new(0, 1, 0)).Magnitude < 1e-6
end
local function whooshes(h)
	local n = 0
	for _, c in ipairs(h.handle:GetChildren()) do
		if c:IsA("Sound") then
			n += 1
		end
	end
	return n
end
local function sameRot(a, b)
	return (a.LookVector - b.LookVector).Magnitude < 1e-3 and (a.UpVector - b.UpVector).Magnitude < 1e-3
end

local function all()
	me:SetAttribute("Weapon", "IronSword")
	me:SetAttribute("Mastery", 1)
	me:SetAttribute("SpireFloor", 2)
	step(0.1)
	local h = WeaponFX._held[me]
	local model = char:FindFirstChild("HeldWeapon")
	check(model ~= nil and h ~= nil, "in a fight: the sword is in the hand")
	if not (model and h) then
		return
	end

	------------------------------------------------------------------
	-- THE 3D SWORD
	------------------------------------------------------------------
	local body, glow, handle = model:FindFirstChild("IronWarden"), model:FindFirstChild("IronWardenGlow"), model:FindFirstChild("Handle")
	check(body and glow and handle, "the 3D model is what's held (its meshes, and an invisible Handle)")
	check(handle and handle.Transparency == 1 and h.handle == handle, "the Handle's invisible")
	check(src.Parent == ReplicatedStorage and #src:GetChildren() == 3, "the model in ReplicatedStorage is left as it was (a copy is held)")
	check(model:FindFirstChildOfClass("WeldConstraint") == nil, "whatever held the model in place is thrown away")
	if body and glow then
		check(body.Anchored == false and body.CanCollide == false and body.CanQuery == false and body.CanTouch == false and body.Massless == true,
			"the meshes can't bump into anything and weigh nothing")
		check(near(body.Size.Y, 5, 1e-3) and near(body.Size.X, 1.3, 1e-3),
			("it's scaled to its real length (%.2f studs long; it came in at 10)"):format(body.Size.Y))
		check(glow.Material == Enum.Material.Neon and glow.Color == WeaponFX.MODELS.IronWarden.Glow, "its glowing pixels shine (Neon)")
		local w = body:FindFirstChildOfClass("Weld")
		check(w and w.Part0 == handle, "welded to the Handle")
		if w then
			-- held at the grip: 0.8 studs up from the pommel (16% of 5), so the
			-- middle of the 5-stud sword is 1.7 studs out along the blade (-Z)
			local p = w.C0.Position
			check(near(p.X, 0) and near(p.Y, 0) and near(p.Z, -1.7), ("held at its grip, the blade out along -Z (its middle at %.2f, %.2f, %.2f)"):format(p.X, p.Y, p.Z))
			check((w.C0.UpVector - Vector3.new(0, 0, -1)).Magnitude < 1e-3, "the tip points along the Handle's -Z (the way the animations swing it)")
			check((w.C0.RightVector - Vector3.new(0, 1, 0)).Magnitude < 1e-3 or (w.C0.RightVector - Vector3.new(0, -1, 0)).Magnitude < 1e-3,
				"its width runs along the Handle's Y (the edge, as the animations expect)")
		end
	end
	check(#h.trails == 2 and h.trails[1].Parent == handle, "two smears along the blade")
	local tipA = handle and handle:FindFirstChild("SwingTrailTip")
	check(tipA and near(tipA.Position.Z, -4.2), ("the smear reaches the tip (%s)"):format(tipA and tostring(tipA.Position.Z) or "none"))

	-- the Grip: a Motor6D from the right arm to the Handle
	check(h.weld:IsA("Motor6D") and h.weld.Name == "Grip" and h.weld.Part0 == char["Right Arm"] and h.weld.Part1 == handle,
		"held by a Motor6D \"Grip\" (Right Arm -> Handle): the animations turn the blade with it")

	------------------------------------------------------------------
	-- THE ANIMATIONS LOAD
	------------------------------------------------------------------
	check(#made == 4, ("the idle and three swings load (%d)"):format(#made))
	local idle, sw1, sw2, sw3 = trackFor(A.Idle), trackFor(A.Swings[1]), trackFor(A.Swings[2]), trackFor(A.Swings[3])
	check(idle and sw1 and sw2 and sw3, "each from its id in Config")
	if not (idle and sw1 and sw2 and sw3) then
		return
	end
	check(idle.Priority == Enum.AnimationPriority.Idle and idle.Looped == true, "the idle: Idle priority, looping")
	check(sw1.Priority == Enum.AnimationPriority.Action and sw3.Priority == Enum.AnimationPriority.Action and sw1.Looped == false,
		"the swings: Action priority (over walking), played once")

	------------------------------------------------------------------
	-- THE IDLE
	------------------------------------------------------------------
	step(0.6)
	check(idle.IsPlaying and idle.plays == 1, "standing still: the idle plays")
	local allLet = true
	for key, j in pairs(J) do
		if h.weights[key] and h.weights[key] > 0.001 then
			allLet = false
		end
		if not isRest(j) then
			allLet = false
		end
	end
	check(allLet, "...and the body is left to it (nothing made in code on top)")
	check(sameRot(h.weld.C0, CFrame.new()) and near(h.weld.C0.Position.Y, -1), "the Grip's C0 is just the hand: the idle turns the blade")
	check(sameRot(h.weld.Transform, GRIP_POSE), "...and the blade's turn is left as the animation set it")

	-- walking: the idle stops, the stance made in code takes the sword arm back
	hum.MoveDirection = Vector3.new(1, 0, 0)
	step(0.7)
	check(not idle.IsPlaying, "walking: the idle stops")
	check(h.weights.RS > 0.6, ("...and the sword arm holds the blade steady in code (%.2f)"):format(h.weights.RS))
	check(not sameRot(h.weld.C0, CFrame.new()) and isRest(h.weld), "...the grip made in code too")
	hum.MoveDirection = Vector3.new(0, 0, 0)
	step(0.8)
	check(idle.IsPlaying and idle.plays == 2, "stopping: the idle again")

	------------------------------------------------------------------
	-- SWINGS
	------------------------------------------------------------------
	-- when each swing cuts: the Cut and Through markers the animations were
	-- exported with (Tools/Animations/export_rbxmx.py)
	local cuts = { { 0.13, 0.36 }, { 0.13, 0.36 }, { 0.24, 0.60 } }
	for n, c in ipairs(cuts) do
		check(WeaponFX.ANIM_CUTS[n] and near(WeaponFX.ANIM_CUTS[n][1], c[1]) and near(WeaponFX.ANIM_CUTS[n][2], c[2]),
			("swing %d's smear matches its animation's Cut and Through markers"):format(n))
	end
	local function watchSwing(n, seconds, during)
		local r = { smearFrom = nil, smearTo = nil, whooshes = 0, maxWeight = 0 }
		local start = t
		local before = whooshes(h)
		WeaponFX.swing(me, n)
		r.startPos = trackFor(A.Swings[n]).TimePosition
		step(seconds, function()
			local el = t - start
			if h.trails[1].Enabled then
				r.smearFrom = r.smearFrom or el
				r.smearTo = el
			end
			for _, w in pairs(h.weights) do
				r.maxWeight = math.max(r.maxWeight, w)
			end
			if during then
				during(el)
			end
		end)
		r.whooshes = whooshes(h) - before
		return r
	end

	local s1 = watchSwing(1, 0.5)
	check(sw1.plays == 1 and s1.startPos == 0, "a swing plays its uploaded animation from the start")
	check(h.anim == nil, "...and none is drawn in code")
	check(s1.maxWeight < 0.3, ("...the body is left to it (the code's weight at most %.2f)"):format(s1.maxWeight))
	check(s1.smearFrom and s1.smearFrom >= cuts[1][1] - 0.02 and s1.smearFrom <= cuts[1][1] + 0.03,
		("the smear starts as it cuts (%.3f s; the Cut is at %.2f)"):format(s1.smearFrom or -1, cuts[1][1]))
	check(s1.smearTo and s1.smearTo <= cuts[1][2] + 0.03 and s1.smearTo >= cuts[1][2] - 0.03,
		("...and ends as the follow-through does (%.3f s; Through at %.2f)"):format(s1.smearTo or -1, cuts[1][2]))
	check(s1.whooshes == 1, ("one whoosh (%d)"):format(s1.whooshes))

	-- chained: swing 2 straight after, handed over at once
	local frozeAt, speedAfter
	local s2 = watchSwing(2, 0.5, function(el)
		if not frozeAt and el >= 0.2 then
			frozeAt = sw2.TimePosition
			WeaponFX.hitStop(me, 0.1)
		end
		if frozeAt and not speedAfter and el >= 0.25 then
			speedAfter = sw2.Speed
			check(near(sw2.TimePosition, frozeAt, 1e-6), "hit-stop: the swing stops dead")
		end
	end)
	check(not sw1.IsPlaying and sw2.IsPlaying ~= nil and sw2.plays == 1, "chained: the last swing stops, the next one plays")
	check(sw2.fade == 0.05 or not sw2.IsPlaying, "...handed over at once (it starts where the last one's follow-through is)")
	check(speedAfter == 0 and sw2.Speed == 1, "...and after the blink it carries on")
	check(s2.whooshes == 1, "one whoosh for the backhand too")

	-- a swing that hasn't loaded: drawn in code instead
	sw3.Length = 0
	WeaponFX.swing(me, 3)
	check(h.anim and h.anim.kind == "swing" and h.anim.n == 3, "a swing that hasn't loaded is drawn in code instead")
	check(not sw2.IsPlaying and sw3.plays == 0, "...the last uploaded one stopped, the unloaded one not played")
	step(0.3)
	check(h.weights.RS > 0.9, ("...and it shows, over the idle (%.2f)"):format(h.weights.RS))
	sw3.Length = 1.2
	step(1.2)

	-- the finisher, loaded again: from the stance it eases in a touch more
	local s3 = watchSwing(3, 0.8)
	check(sw3.plays == 1 and s3.smearFrom and near(s3.smearFrom, cuts[3][1], 0.03), ("the finisher plays, its smear from %.2f s"):format(cuts[3][1]))
	check(sw3.fade == 0.1 or not sw3.IsPlaying, "from the stance it eases in (not chained)")
	step(0.6)

	-- the Whirlwind stops a swing and isn't cut short by it (the Iron Sword
	-- has no ability - it's the starter - so it borrows Ember Cleaver's here)
	local ownDef = h.def
	h.def = Config.Weapons.List.EmberCleaver
	WeaponFX.swing(me, 1)
	step(0.15)
	WeaponFX.spin(me, 1)
	check(not sw1.IsPlaying, "the Whirlwind stops the swing")
	step(0.1)
	check(h.anim and h.anim.kind == "spin", "...and isn't cut short by it")
	check(not idle.IsPlaying, "...nor by the idle (stopped while you spin)")
	check(h.weights.Root > 0.5, ("...and it shows (%.2f)"):format(h.weights.Root))
	step(1.5)
	check(h.anim == nil and idle.IsPlaying, "after it: the idle again")
	h.def = ownDef

	------------------------------------------------------------------
	-- SOMEONE ELSE
	------------------------------------------------------------------
	local other = Instance.new("Player")
	other.Name = "Friend"
	other.UserId = 1002
	other.Parent = Players
	local oc, OJ, _, oplaying, omade = r6("Friend")
	lists[#lists + 1] = oplaying
	other.Character = oc
	table.insert(M.players, other)
	other:SetAttribute("Weapon", "IronSword")
	other:SetAttribute("Colosseum", true)
	other:SetAttribute("SwingN", "5:1")
	step(0.2)
	local oh = WeaponFX._held[other]
	check(oh and oc:FindFirstChild("HeldWeapon"), "another fighter's sword shows on your screen")
	check(#omade == 0 and oh.tracks == nil, "...but their animations are played by their own screen, not yours")
	-- their idle, sent by Roblox: the body is left to it
	local function sent(id, length, looped)
		local tr = newTrack({ AnimationId = id }, length, oplaying)
		tr.Looped = looped
		tr:Play(0)
		return tr
	end
	local oidle = sent(A.Idle, 2.383, true)
	step(0.4)
	check(oh.weights.RS < 0.01 and oh.animGrip > 0.99, "their idle: the body and the blade are left to it")
	-- their swing arrives by itself: nothing drawn over it
	other:SetAttribute("SwingN", "6:1")
	step(0.05)
	check(oh.anim == nil and oh.waitSwing ~= nil, "their swing: waiting a moment for it to arrive")
	local osw = sent(A.Swings[1], 0.85, false)
	step(0.2)
	check(oh.anim == nil and oh.waitSwing == nil, "...it arrived: nothing drawn over it")
	step(0.8)
	-- one that never arrives (it couldn't load for them): drawn in code
	other:SetAttribute("SwingN", "7:2")
	step(0.1)
	check(oh.anim == nil, "a swing that hasn't arrived yet isn't drawn yet")
	step(0.07)
	check(oh.anim and oh.anim.kind == "swing" and oh.anim.n == 2 and oh.anim.t >= WeaponFX.REMOTE_WAIT,
		"...and if it doesn't arrive in a moment, it's drawn in code (caught up)")
	check(oh.weights.RS > 0.3, ("...showing over their idle (%.2f)"):format(oh.weights.RS))
	-- theirs arriving late after all: the code steps aside
	local late = sent(A.Swings[2], 0.85, false)
	late.TimePosition = 0.2
	step(0.05)
	check(oh.anim == nil, "...and if it turns up late after all, the code steps aside")
	step(1)
	local _ = osw
	oidle:Stop(0.2)
	step(0.4)
	check(oh.animGrip == 0 and isRest(oh.weld), "their idle gone: the grip's made in code again")

	------------------------------------------------------------------
	-- LEAVING THE FIGHT
	------------------------------------------------------------------
	me:SetAttribute("SpireFloor", nil)
	step(0.5)
	check(not char:FindFirstChild("HeldWeapon"), "out of the fight: the sword's put away")
	check(not idle.IsPlaying and idle.destroyed and sw1.destroyed and sw2.destroyed and sw3.destroyed, "...and the animations stopped and thrown away")
	local rest = true
	for _, j in pairs(J) do
		rest = rest and isRest(j)
	end
	check(rest, "every joint back at rest")

	-- the 3D model not in the game: the blocky sword
	src.Parent = nil
	me:SetAttribute("SpireFloor", 3)
	step(0.2)
	local blocky = char:FindFirstChild("HeldWeapon")
	check(blocky and blocky:FindFirstChild("Blade") and blocky:FindFirstChild("Edge"), "no 3D model in ReplicatedStorage: the blocky sword made in code")
	check(#made == 8, "...still with the uploaded animations (loaded again for this fight)")
	me:SetAttribute("SpireFloor", nil)
	step(0.5)
end

local ok, err = pcall(all)
if not ok then
	fails += 1
	print("FAIL: errored: " .. tostring(err))
end
if #M.errors > 0 then
	fails += 1
	print("FAIL: " .. #M.errors .. " script errors")
	for i = 1, math.min(3, #M.errors) do
		print(M.errors[i])
	end
end
if fails == 0 then
	print("PASS swordanims")
else
	print(fails .. " failures")
end
