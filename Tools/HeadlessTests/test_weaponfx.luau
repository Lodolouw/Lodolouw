--!nocheck
-- Headless test of WEAPONFX (ReplicatedStorage/WeaponFX): how weapons look.
-- The real module on pretend R6 characters with all of Roblox's own joints:
--   * the sword appears in the right hand in a fight; standing, you're in a
--     relaxed stance (blade low and forward), breathing, feet on the floor
--   * a swing puts the whole body in: it winds up, holds, snaps through and
--     follows through; the body moves first and the blade last (a whip); the
--     blade is fastest right as it lands; the feet stay on the floor (the
--     body sinks into the lunge); the finisher leaps and slams the ground
--   * swings chain: a swing hangs in its follow-through and the next one
--     winds up from there, not from the stance
--   * hit-stop freezes everything dead for a blink
--   * rolling (an action animation), jumping and drinking take the body back
--   * the Whirlwind turns the body all the way round, spins times
--   * a slash mark tears across a hit; other players' swings show; mastery
--     100 turns it gold; letting go puts every joint back exactly
--
--   luau test_weaponfx.luau            every check
--   luau test_weaponfx.luau -a poses   prints every joint and the sword over
--                                      each swing and the spin (render_sword.py)
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Instance, CFrame, Vector3, Enum = M.Instance, M.CFrame, M.Vector3, M.Enum
local Players = M.services.Players
local RunService = M.services.RunService
local SoundService = M.services.SoundService

local args = { ... }
local MODE = args[1] or "all"

-- the swing's whoosh, so we can hear when it plays
local whoosh = Instance.new("Sound")
whoosh.Name = "Sword Swing"
whoosh.PlaybackSpeed = 1
whoosh.TimeLength = 0.4
whoosh.Parent = SoundService

local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local WeaponFX = mount.require(mount.module("ReplicatedStorage/WeaponFX.lua"))
local W = Config.Weapons
local SW = W.Types.Sword.Swings

local fails = 0
local function check(ok, msg)
	if not ok then
		fails += 1
		print("FAIL: " .. msg)
	end
end

-- a pretend R6 character with all of Roblox's own joints
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
	local j = {}
	j.RS = motor("Right Shoulder", torso, torso, arm, CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	j.LS = motor("Left Shoulder", torso, torso, larm, CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
	j.RH = motor("Right Hip", torso, torso, rleg, CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	j.LH = motor("Left Hip", torso, torso, lleg, CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
	j.Neck = motor("Neck", torso, torso, head, CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	j.Root = motor("RootJoint", hrp, hrp, torso, CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	model.Parent = M.workspace
	return model, j, hum
end

local me = Instance.new("Player")
me.Name = "Tester"
me.UserId = 1001
me.Parent = Players
Players.LocalPlayer = me
local char, J, hum = r6("Tester")
local shoulder, root = J.RS, J.Root
me.Character = char
M.players = { me }

-- what Roblox's Humanoid would say: on the ground or in the air, and which
-- animations are playing (the roll is an Action4 animation)
local airborne = false
hum.GetState = function()
	return airborne and Enum.HumanoidStateType.Freefall or Enum.HumanoidStateType.Running
end
local animator = Instance.new("Animator")
animator.Parent = hum
local playing = {}
animator.GetPlayingAnimationTracks = function()
	return playing
end

WeaponFX.start()

local t = 0
-- `before` runs just before each frame's sword code (where Roblox's own
-- animations write the joints); `each` just after
local function step(seconds, each, before)
	local stop = t + seconds
	while t < stop - 1e-9 do
		t += 1 / 60
		M.run(t)
		if before then
			before()
		end
		RunService.Stepped:Fire(t, 1 / 60)
		RunService.RenderStepped:Fire(1 / 60)
		if each then
			each()
		end
	end
end

local function weapon(c)
	return c:FindFirstChild("HeldWeapon")
end
local function same(a, b)
	return (a.Position - b.Position).Magnitude < 1e-6 and (a.LookVector - b.LookVector).Magnitude < 1e-6 and (a.UpVector - b.UpVector).Magnitude < 1e-6
end
local function isRest(j)
	return same(j.Transform, CFrame.new())
end
local function allRest(j)
	for _, m in pairs(j) do
		if not isRest(m) then
			return false
		end
	end
	return true
end
-- how far a joint is from a pose { x, y, z } (degrees, roughly)
local function off(j, a)
	local want = CFrame.Angles(math.rad(a[1]), math.rad(a[2]), math.rad(a[3]))
	local d = (j.Transform.LookVector - want.LookVector).Magnitude + (j.Transform.UpVector - want.UpVector).Magnitude
	return math.deg(d)
end
-- the body (the torso, placed by the root joint) in the character's own space:
-- +x is your right, +y up, -z forward, the floor at y = -3
local function body()
	return root.C0 * root.Transform * root.C1:Inverse()
end
-- where the blade's tip is
local function tip(h)
	local arm = body() * shoulder.C0 * shoulder.Transform * shoulder.C1:Inverse()
	return (arm * h.weld.C0) * Vector3.new(0, 0, -5)
end
-- the body's turn (degrees, round the up axis)
local function turn()
	local lv = body().LookVector
	return math.deg(math.atan2(-lv.X, -lv.Z))
end
-- the lean: how far the chest tips forward (degrees)
local function lean()
	local up = body().UpVector
	return math.deg(math.asin(math.clamp(-up.Z, -1, 1)))
end
-- how high the body's been lifted (+) or lowered (-) from standing
local function height()
	return body().Position.Y
end
-- where a foot is (the bottom of a leg)
local function foot(hip)
	return (body() * hip.C0 * hip.Transform * hip.C1:Inverse()) * Vector3.new(0, -1, 0)
end
local function lowFoot()
	return math.min(foot(J.RH).Y, foot(J.LH).Y)
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

local function all()
	local ST = WeaponFX.STANCE
	step(0.2)
	check(not weapon(char), "no weapon: nothing in the hand")
	me:SetAttribute("Weapon", "EmberCleaver")
	me:SetAttribute("Mastery", 1)
	step(0.2)
	check(not weapon(char), "a weapon, but not in a fight: it's put away")
	me:SetAttribute("SpireFloor", 2)
	step(0.1)
	local model = weapon(char)
	check(model ~= nil, "in a fight: the sword is in the hand")
	local h = WeaponFX._held[me]
	if model then
		local n = 0
		for _, p in ipairs(model:GetChildren()) do
			if p:IsA("Part") then
				n += 1
				check(p.CanCollide == false and p.Massless == true and p.CanQuery == false, "the sword's " .. p.Name .. " can't bump into anything")
			end
		end
		check(n >= 6, "a chunky sword (handle, pommel, guard, blade, glowing edge, tip): " .. n .. " pieces")
		local blade = model:FindFirstChild("Blade")
		check(blade and blade.Size.Y >= 0.7 and blade.Size.Z >= 3.8, "the blade is broad and long")
		check(h.weld.Part0 == char["Right Arm"], "welded to the right arm")
		check(#h.trails >= 2 and not h.trails[1].Enabled, "two smears, off while you're just holding it")
	end

	------------------------------------------------------------------
	-- THE STANCE
	------------------------------------------------------------------
	step(1.5)
	check(off(shoulder, ST.RS) < 12, ("standing: the sword arm's in the stance (%.0f off)"):format(off(shoulder, ST.RS)))
	local bt = tip(h)
	check(bt.Z < -1.5 and bt.Y < 0 and bt.Y > -2.9, ("the blade's held low and forward, clear of the floor (tip %.1f, %.1f, %.1f)"):format(bt.X, bt.Y, bt.Z))
	check(foot(J.LH).Z < foot(J.RH).Z - 0.3, "left foot forward")
	check(math.abs(lowFoot() + 3) < 0.03, ("feet on the floor (lowest foot %.2f; the floor is -3)"):format(lowFoot()))
	local lo, hi, turnLo, turnHi = 99, -99, 999, -999
	step(6, function()
		lo, hi = math.min(lo, lean()), math.max(hi, lean())
		turnLo, turnHi = math.min(turnLo, turn()), math.max(turnHi, turn())
	end)
	check(hi - lo > 1, ("breathing (the chest rises and falls %.1f degrees)"):format(hi - lo))
	check(turnHi - turnLo > 1.5, ("the weight shifts now and then (%.1f degrees)"):format(turnHi - turnLo))
	check(hi - lo < 6 and turnHi - turnLo < 12, "...but calmly")

	-- walking: the legs and free arm walk (left alone), the sword arm holds the blade steady
	hum.MoveDirection = Vector3.new(1, 0, 0)
	local walkLeg = CFrame.Angles(0, 0, math.rad(30))
	step(0.7, nil, function()
		J.RH.Transform = walkLeg
		J.LS.Transform = walkLeg
	end)
	check(J.RH.Transform == walkLeg and J.LS.Transform == walkLeg, "walking: the legs and free arm are left to walk")
	check(off(shoulder, ST.RS) < 12, ("walking: the sword arm keeps the blade steady (%.0f off)"):format(off(shoulder, ST.RS)))
	hum.MoveDirection = Vector3.new(0, 0, 0)
	J.RH.Transform, J.LS.Transform = CFrame.new(), CFrame.new()
	step(1)

	------------------------------------------------------------------
	-- SWINGS
	------------------------------------------------------------------
	-- follows one swing: where the tip goes while the smear is on, how the body
	-- moves, the feet, how fast the blade goes when, and the whoosh
	local function watch(n, seconds)
		local r = { tips = {}, maxTurn = -999, minTurn = 999, maxLean = -99, stride = 0, lowest = 99, highest = -99,
			footErr = 0, speeds = {}, whooshAt = nil, frames = 0 }
		local start = t
		local last = tip(h)
		local whooshed = whooshes(h)
		WeaponFX.swing(me, n)
		step(seconds or SW[n].Lock, function()
			local el = t - start
			r.frames += 1
			r.maxTurn, r.minTurn = math.max(r.maxTurn, turn()), math.min(r.minTurn, turn())
			r.maxLean = math.max(r.maxLean, lean())
			r.stride = math.max(r.stride, math.abs(foot(J.LH).Z - foot(J.RH).Z))
			r.lowest, r.highest = math.min(r.lowest, height()), math.max(r.highest, height())
			if h.weights.RH > 0.999 and h.weights.Root > 0.999 then
				r.footErr = math.max(r.footErr, math.abs(lowFoot() + 3))
			end
			local p = tip(h)
			r.speeds[#r.speeds + 1] = { t = el, v = (p - last).Magnitude * 60 }
			last = p
			if h.trails[1].Enabled then
				r.tips[#r.tips + 1] = p
			end
			if not r.whooshAt and whooshes(h) > whooshed then
				r.whooshAt = el
			end
		end)
		return r
	end
	local function fastest(r, from, to)
		local best, at = 0, 0
		for _, s in ipairs(r.speeds) do
			if s.t >= from and s.t <= to and s.v > best then
				best, at = s.v, s.t
			end
		end
		return best, at
	end

	-- swing 1: a diagonal slash from high on the right down to the low left
	local m1 = WeaponFX.swingMoments(SW[1])
	local s1 = watch(1)
	local first, final = s1.tips[1], s1.tips[#s1.tips]
	check(#s1.tips > 3, "a glowing smear follows the blade through the cut")
	if first and final then
		check(first.X > 0.5 and first.Y > 3, ("the slash starts high on the right (tip %.1f, %.1f)"):format(first.X, first.Y))
		check(final.X < -2.5 and final.Y < 0.5, ("...and rips down to the low left (tip %.1f, %.1f)"):format(final.X, final.Y))
	end
	check(s1.minTurn < -30 and s1.maxTurn > 30, ("the body coils back and whips through (turn %.0f to %.0f)"):format(s1.minTurn, s1.maxTurn))
	check(s1.maxLean > 12, ("it leans into the cut (%.0f degrees)"):format(s1.maxLean))
	check(s1.stride > 1.8, ("the legs lunge into a big stride (%.1f studs between the feet)"):format(s1.stride))
	check(s1.footErr < 0.03, ("the feet stay on the floor the whole swing (off by up to %.3f)"):format(s1.footErr))
	check(s1.lowest < -0.25, ("the body sinks down into the lunge (%.2f studs)"):format(s1.lowest))
	-- the timing: wind up, hold, SNAP - the blade's fastest right as it lands
	local cutV, cutAt = fastest(s1, m1.hold - 0.03, m1.follow)
	local windV = fastest(s1, 0, m1.coil)
	check(cutAt >= m1.hold - 0.01 and cutAt <= m1.contact + 0.034, ("the blade is fastest right as it lands (%.3f s; lands at %.3f)"):format(cutAt, m1.contact))
	check(cutV > windV * 1.5, ("the cut is far faster than the wind-up (%.0f vs %.0f studs a second)"):format(cutV, windV))
	local holdV = fastest(s1, m1.coil + 0.02, m1.hold - 0.02)
	check(holdV < cutV * 0.4, ("it holds for a heartbeat before the cut (%.0f studs a second in the hold)"):format(holdV))
	check(s1.whooshAt and s1.whooshAt >= m1.coil and s1.whooshAt <= m1.contact, ("the whoosh plays as the cut starts, not on the press (%s s)"):format(tostring(s1.whooshAt)))
	-- it hangs in the follow-through until it lets you go (the weight of it)
	check(off(shoulder, ST.RS) > 25, ("at the end of the swing you're still in the follow-through (%.0f from the stance)"):format(off(shoulder, ST.RS)))
	step(WeaponFX.SETTLE + 0.3)
	check(off(shoulder, ST.RS) < 12 and not h.trails[1].Enabled and h.anim == nil, "then it drifts back into the stance, smear off")

	-- the overlap: the body starts the cut, then the arm, and the blade comes last (a whip)
	do
		local keys = WeaponFX.POSES.Sword[1]
		local function mid(key, i)
			return (keys.coil[key][i] + keys.cut[key][i]) / 2, keys.cut[key][i] > keys.coil[key][i] and 1 or -1
		end
		local watchFor = { Root = 3, RS = 3, Grip = 1 }
		local crossed = {}
		local start = t
		WeaponFX.swing(me, 1)
		step(SW[1].Lock, function()
			local el = t - start
			if el > m1.coil then
				for key, i in pairs(watchFor) do
					local half, dir = mid(key, i)
					if not crossed[key] and (h.springs[key].p[i] - half) * dir >= 0 then
						crossed[key] = el
					end
				end
			end
		end)
		check(crossed.Root and crossed.RS and crossed.Grip and crossed.Root < crossed.RS and crossed.RS < crossed.Grip,
			("a whip: the body, then the arm, then the blade (%.3f, %.3f, %.3f s)"):format(crossed.Root or -1, crossed.RS or -1, crossed.Grip or -1))
		check(crossed.Grip and crossed.Grip <= m1.contact + 0.034, "...and the blade still arrives on time")
		step(WeaponFX.SETTLE + 0.3)
	end

	-- swing 2: the rising backhand goes the other way, low left to high right
	local s2 = watch(2)
	first, final = s2.tips[1], s2.tips[#s2.tips]
	if first and final then
		check(first.X < -1 and final.X > 1, ("the backhand sweeps left to right (%.1f -> %.1f)"):format(first.X, final.X))
		check(final.Y > first.Y + 2, ("...rising as it goes (%.1f -> %.1f)"):format(first.Y, final.Y))
	else
		check(false, "the backhand has a smear")
	end
	check(s2.maxTurn > 25 and s2.minTurn < -35, ("the body coils the other way for it (%.0f to %.0f)"):format(s2.minTurn, s2.maxTurn))
	check(s2.footErr < 0.03, "feet on the floor")
	step(WeaponFX.SETTLE + 0.3)

	-- swing 3: the finisher leaps up with the blade high and slams down with everything
	local m3 = WeaponFX.swingMoments(SW[3])
	local rose, slam, deepest, highest, lowest = -99, nil, -99, -99, 99
	local start = t
	WeaponFX.swing(me, 3)
	step(SW[3].Lock, function()
		local el = t - start
		if el < m3.hold then
			rose = math.max(rose, height())
		end
		deepest = math.max(deepest, lean())
		if h.trails[1].Enabled then
			local p = tip(h)
			highest = math.max(highest, p.Y)
			lowest = math.min(lowest, p.Y)
		end
		if not slam and M.workspace:FindFirstChild("SlamRing") then
			slam = el
		end
	end)
	check(rose > 0.4, ("the finisher leaps up off the ground (%.2f studs)"):format(rose))
	check(highest > 4 and lowest < 1, ("the blade comes down from high above your head (tip %.1f -> %.1f)"):format(highest, lowest))
	check(lowest > -3.3, ("...without driving it through the floor (lowest %.1f; the floor is -3)"):format(lowest))
	check(deepest > 30, ("the whole body bends into it (%.0f degrees)"):format(deepest))
	check(slam and math.abs(slam - m3.contact) < 0.03, ("a shockwave bursts out on the floor as it lands (%s s; lands at %.3f)"):format(tostring(slam), m3.contact))
	step(WeaponFX.SETTLE + 0.5)
	check(not M.workspace:FindFirstChild("SlamRing"), "...and it's gone a moment later")

	-- chaining: the next swing winds up from this one's follow-through (no snap back to the stance)
	do
		-- from the stance, swing 2's wind-up has a long way to go...
		local startAt = tip(h)
		watch(2, m1.coil)
		local stanceTravel = (tip(h) - startAt).Magnitude
		step(SW[2].Lock + WeaponFX.SETTLE + 0.3)
		-- ...but chained straight after swing 1 it's nearly there already
		watch(1)
		local chainAt = tip(h)
		local chained = watch(2, m1.coil)
		local chainTravel = (tip(h) - chainAt).Magnitude
		check(chainTravel < stanceTravel * 0.6, ("a chained backhand winds up from the slash's follow-through (%.1f studs vs %.1f from the stance)"):format(chainTravel, stanceTravel))
		local jump = 0
		for i = 1, math.min(4, #chained.speeds) do
			jump = math.max(jump, chained.speeds[i].v / 60)
		end
		check(jump < 1.2, ("...smoothly, without a jump (%.2f studs in a frame)"):format(jump))
		step(SW[2].Lock + WeaponFX.SETTLE + 0.3)
	end

	------------------------------------------------------------------
	-- HIT-STOP: everything stops dead for a blink as the blade bites
	------------------------------------------------------------------
	WeaponFX.swing(me, 1)
	step(m1.contact)
	local before = h.anim and h.anim.t
	local armBefore = shoulder.Transform
	local springBefore = table.clone(h.springs.Root.p)
	WeaponFX.hitStop(me, 0.1)
	step(0.08)
	check(h.anim and math.abs(h.anim.t - before) < 1e-6, "hit-stop: the swing freezes for a blink")
	check(h.springs.Root.p[3] == springBefore[3] and h.springs.Root.p[1] == springBefore[1], "...the whole body stops dead (nothing drifts on)")
	local moved = math.deg((shoulder.Transform.LookVector - armBefore.LookVector).Magnitude + (shoulder.Transform.UpVector - armBefore.UpVector).Magnitude)
	check(moved < 8, ("...the arm just shudders on the spot (%.1f degrees)"):format(moved))
	step(0.1)
	check(h.anim and h.anim.t > before, "...then carries on")
	step(SW[1].Lock + WeaponFX.SETTLE)

	------------------------------------------------------------------
	-- ROLLING, JUMPING AND DRINKING take the body back
	------------------------------------------------------------------
	-- the roll: Roblox plays it (an Action4 animation) and writes every joint; the
	-- sword code lets go of the lot within a few frames - even mid-swing - so the
	-- roll shows exactly as it was made
	local rollPose = {
		Root = CFrame.Angles(math.rad(60), 0, 0), RS = CFrame.Angles(0, 0, math.rad(-40)), LS = CFrame.Angles(0, 0, math.rad(40)),
		RH = CFrame.Angles(0, 0, math.rad(70)), LH = CFrame.Angles(0, 0, math.rad(-70)), Neck = CFrame.Angles(math.rad(20), 0, 0),
	}
	local function writeRoll()
		for key, cf in pairs(rollPose) do
			J[key].Transform = cf
		end
	end
	WeaponFX.swing(me, 1)
	step(0.1)
	playing = { { Priority = Enum.AnimationPriority.Action4, IsPlaying = true, WeightTarget = 1 } }
	local frames, clean = 0, nil
	step(0.3, function()
		frames += 1
		if not clean then
			local every = true
			for key, cf in pairs(rollPose) do
				if not same(J[key].Transform, cf) then
					every = false
				end
			end
			if every then
				clean = frames
			end
		end
	end, writeRoll)
	check(h.anim == nil, "rolling cancels the swing")
	check(clean and clean <= 12, ("the roll shows exactly as it was made within a few frames (%s frames)"):format(tostring(clean)))
	playing = {}
	for _, j in pairs(J) do
		j.Transform = CFrame.new() -- (the roll's over: Roblox's own animations have the joints again)
	end
	step(1)
	check(off(shoulder, ST.RS) < 12, "after the roll, back in the stance")
	-- a track played at no weight (the animations warming up at spawn) isn't a roll
	playing = { { Priority = Enum.AnimationPriority.Action4, IsPlaying = true, WeightTarget = 0.0001 } }
	step(0.3)
	check(off(shoulder, ST.RS) < 12, "an animation warming up (no weight) doesn't count as a roll")
	playing = {}

	-- in the air: the legs and body are left to Roblox's jump
	airborne = true
	local jumpLeg = CFrame.Angles(0, 0, math.rad(-25))
	step(0.5, nil, function()
		J.RH.Transform = jumpLeg
		J.LH.Transform = jumpLeg
		J.Root.Transform = CFrame.new()
	end)
	check(J.RH.Transform == jumpLeg and J.LH.Transform == jumpLeg and isRest(J.Root), "in the air: the legs and body are left to the jump")
	check(off(shoulder, ST.RS) < 12, "...the sword arm still holds the blade")
	airborne = false
	J.RH.Transform, J.LH.Transform = CFrame.new(), CFrame.new()
	step(1)
	check(math.abs(lowFoot() + 3) < 0.03, "landed: feet back on the floor")

	-- drinking: the sword's tucked away and the arm and head belong to the drink
	char:SetAttribute("Drinking", 1)
	local drinkArm = CFrame.Angles(0, 0, math.rad(120))
	step(0.4, nil, function()
		J.RS.Transform = drinkArm
	end)
	check(model.Parent == nil and not weapon(char), "drinking: the sword's tucked away")
	check(J.RS.Transform == drinkArm, "...and the drink has the arm to itself")
	char:SetAttribute("Drinking", nil)
	J.RS.Transform = CFrame.new()
	step(1)
	check(weapon(char) ~= nil and off(shoulder, ST.RS) < 12, "after the drink: sword back out, back in the stance")

	------------------------------------------------------------------
	-- THE WHIRLWIND: round and round, spins times, the legs going with it
	------------------------------------------------------------------
	for tierIndex, want in ipairs({ 1, 1, 2, 2, 3 }) do
		local total, last = 0, turn()
		local ab = Config.Weapons.List.EmberCleaver.Ability
		local tier = ab.Tiers[tierIndex]
		local legsTurned = 0
		WeaponFX.spin(me, tierIndex)
		step(tier.Spins * ab.SpinTime / 0.76 + 0.05, function()
			local now = turn()
			local d = now - last
			if d > 180 then
				d = d - 360
			elseif d < -180 then
				d = d + 360
			end
			total = total + d
			last = now
			legsTurned = math.max(legsTurned, foot(J.LH).Z) -- the forward foot comes round behind
		end)
		check(math.abs(math.abs(total) - 360 * want) < 30, ("tier %d: the Whirlwind spins %d time(s) round (%.0f degrees)"):format(tierIndex, want, total))
		check(legsTurned > 0.2, "...the legs go round with the body")
		step(0.5)
		check(off(shoulder, ST.RS) < 12 and math.abs(lowFoot() + 3) < 0.03, "after the Whirlwind, back in the stance, feet on the floor")
	end

	------------------------------------------------------------------
	-- THE REST
	------------------------------------------------------------------
	-- a slash mark tears across a hit, and clears itself away
	WeaponFX.slashMark(Vector3.new(0, 3, -6), Vector3.new(0, 0, -1), true, false)
	step(0.05)
	local mark = M.workspace:FindFirstChild("SlashMark")
	check(mark ~= nil, "a slash mark appears where you hit")
	local grew = 0
	step(0.1, function()
		local bar = mark and mark:FindFirstChild("Slash")
		if bar then
			grew = math.max(grew, bar.Size.Z)
		end
	end)
	check(grew > 5, ("it tears open across the hit (%.1f studs long)"):format(grew))
	step(1)
	check(not M.workspace:FindFirstChild("SlashMark"), "...and it's gone a moment later")

	-- someone else: their swing shows when their SwingN changes
	local other = Instance.new("Player")
	other.Name = "Friend"
	other.UserId = 1002
	other.Parent = Players
	local oc = r6("Friend")
	other.Character = oc
	table.insert(M.players, other)
	other:SetAttribute("Weapon", "EmberCleaver")
	other:SetAttribute("Colosseum", true)
	other:SetAttribute("SwingN", "7:1") -- (an old swing, from before we could see them)
	step(0.2)
	local oh = WeaponFX._held[other]
	check(weapon(oc) ~= nil, "another fighter's sword shows on your screen")
	check(oh and oh.anim == nil, "...and an old swing counter doesn't make them swing")
	other:SetAttribute("SwingN", "8:2")
	step(0.05)
	-- (an uploaded swing: Roblox sends theirs to your screen - test_swordanims -
	-- so it's given a moment to arrive; here nothing plays animations, so it
	-- never does, and it's drawn in code instead)
	check(oh.anim == nil, "their swing: waiting a moment for their animation to arrive")
	step(WeaponFX.REMOTE_WAIT)
	check(oh.anim and oh.anim.kind == "swing" and oh.anim.n == 2, "their new swing plays on your screen")
	step(1.2)
	other:SetAttribute("AbilityN", "3:1")
	step(0.05)
	check(oh.anim and oh.anim.kind == "spin", "their Whirlwind plays on your screen")
	step(1)

	-- your own counter changing doesn't swing you twice (it played when you pressed)
	me:SetAttribute("SwingN", "99:1")
	step(0.1)
	check(h.anim == nil, "your own swing counter doesn't swing you again")

	-- mastery 100: the blade turns gold (mid-swing: the swing carries on)
	WeaponFX.swing(me, 1)
	step(0.1)
	me:SetAttribute("Mastery", 100)
	step(0.05)
	local blade = weapon(char) and weapon(char):FindFirstChild("Blade")
	check(blade and blade.Color == M.Color3.fromRGB(254, 231, 97), "awakened at mastery 100: the blade's gold")
	check(WeaponFX.isGolden(me), "...and the slash marks know it")
	h = WeaponFX._held[me]
	check(h.anim and h.anim.kind == "swing", "...and a swing in progress carries straight on")
	step(1)
	me:SetAttribute("Mastery", 5)
	step(0.1)
	h = WeaponFX._held[me]
	blade = weapon(char) and weapon(char):FindFirstChild("Blade")
	check(blade and blade.Color ~= M.Color3.fromRGB(254, 231, 97), "...and steel again below it")

	-- leaving the fight, dying, dropping the weapon: put away, every joint back where it was
	me:SetAttribute("SpireFloor", nil)
	step(0.1)
	check(not weapon(char) and allRest(J), "out of the fight: put away, every joint back where it was")
	me:SetAttribute("SpireFloor", 2)
	step(0.5)
	check(weapon(char) ~= nil and not allRest(J), "back in: out again, in the stance")
	WeaponFX.swing(me, 1)
	step(0.1)
	hum.Health = 0
	step(0.1)
	check(not weapon(char) and allRest(J), "dying mid-swing: put away, every joint back")
	hum.Health = 100
	step(0.3)
	me:SetAttribute("Weapon", nil)
	step(0.1)
	check(not weapon(char) and allRest(J), "back to fists: nothing in the hand, nothing moved")

	-- a body without R6 joints: nothing held, nothing breaks
	local blocky = Instance.new("Player")
	blocky.Name = "Blocky"
	blocky.UserId = 1003
	blocky.Parent = Players
	local bm = Instance.new("Model")
	bm.Name = "Blocky"
	part(bm, "UpperTorso", Vector3.new(2, 1, 1))
	bm.Parent = M.workspace
	blocky.Character = bm
	table.insert(M.players, blocky)
	blocky:SetAttribute("Weapon", "EmberCleaver")
	blocky:SetAttribute("Colosseum", true)
	blocky:SetAttribute("SwingN", "1:1")
	step(0.5)
	check(not weapon(bm), "no sword on a body without R6 joints")

	------------------------------------------------------------------
	-- the pose sums on their own
	------------------------------------------------------------------
	for n, keys in ipairs(WeaponFX.POSES.Sword) do
		local s = SW[n]
		local m = WeaponFX.swingMoments(s)
		check(m.coil < m.hold and m.hold < m.contact and m.contact < m.follow and m.follow < m.lock and m.lock < m.done, "swing " .. n .. ": its moments come in order")
		check(math.abs(m.contact - s.Lock * s.Contact) < 1e-9, "swing " .. n .. ": the blade lands when the server cuts")
		local p0, w0 = WeaponFX.swingPose(keys, 0, s, ST)
		local cutPose, w1 = WeaponFX.swingPose(keys, m.contact, s, ST)
		local endPose, _, _, over = WeaponFX.swingPose(keys, m.done, s, ST)
		check(w0 == 0 and w1 == 1, "swing " .. n .. ": blends in from nothing")
		check(math.abs(p0.RS[3] - ST.RS[3]) < 1e-6, "swing " .. n .. ": starts from the stance")
		check(math.abs(cutPose.RS[2] - keys.cut.RS[2]) < 1e-6 and math.abs(cutPose.RS[3] - keys.cut.RS[3]) < 1e-6, "swing " .. n .. ": at the moment it lands, it's the cut")
		check(over and math.abs(endPose.RS[3] - ST.RS[3]) < 1e-6 and math.abs(endPose.Grip[1] - ST.Grip[1]) < 1e-6, "swing " .. n .. ": it ends back in the stance")
		local from = WeaponFX.mixPose(ST, keys.follow, 0.7)
		local pf = WeaponFX.swingPose(keys, 0, s, ST, from)
		check(math.abs(pf.RS[3] - from.RS[3]) < 1e-6, "swing " .. n .. ": chained, it starts from wherever the body was")
		local hang = WeaponFX.swingPose(keys, (m.follow + m.lock) / 2, s, ST)
		check(math.abs(hang.RS[3] - keys.follow.RS[3]) <= math.abs(ST.RS[3] - keys.follow.RS[3]) * 0.12 + 1e-6, "swing " .. n .. ": it hangs in the follow-through until it lets you go")
		-- the follow-through flies past the end pose (overshoot)
		local past = false
		for i = 0, 40 do
			local p = WeaponFX.swingPose(keys, m.contact + (m.follow - m.contact) * i / 40, s, ST)
			for axis = 2, 3 do
				local a, b, c = keys.cut.RS[axis], keys.follow.RS[axis], p.RS[axis]
				if math.abs(b - a) > 5 and (c - a) / (b - a) > 1.02 then
					past = true
				end
			end
		end
		check(past, "swing " .. n .. ": the follow-through flies past and comes back")
	end
	-- the springs: a part settles exactly where it's sent, with only a little overshoot
	local sp = { p = { 0, 0, 0 }, v = { 0, 0, 0 } }
	local peak = 0
	for _ = 1, 60 do
		WeaponFX.spring(sp, { 100, 0, 0 }, 36, 0.7, 1 / 60)
		peak = math.max(peak, sp.p[1])
	end
	check(math.abs(sp.p[1] - 100) < 0.5 and peak > 100 and peak < 112, ("a spring overshoots a little and settles (peak %.1f, ends %.2f)"):format(peak, sp.p[1]))
end

-- every joint over each swing and the spin, for the pictures
local function poses()
	me:SetAttribute("Weapon", "EmberCleaver")
	me:SetAttribute("Mastery", 1)
	me:SetAttribute("SpireFloor", 2)
	step(1.5)
	local h = WeaponFX._held[me]
	for _, p in ipairs(h.model:GetChildren()) do
		if p:IsA("Part") then
			local w = p:FindFirstChildOfClass("Weld")
			local c = p.Color
			local o = (p == h.handle) and CFrame.new() or w.C0
			print(string.format("PIECE %s %.2f %.2f %.2f %d %d %d %s", p.Name, p.Size.X, p.Size.Y, p.Size.Z,
				math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5), table.concat({ o:GetComponents() }, " ")))
		end
	end
	local function dump(label)
		local parts = { label }
		for _, key in ipairs({ "RS", "Root", "LS", "RH", "LH", "Neck" }) do
			parts[#parts + 1] = key .. " " .. table.concat({ J[key].Transform:GetComponents() }, " ")
		end
		parts[#parts + 1] = "Grip " .. table.concat({ h.weld.C0:GetComponents() }, " ")
		parts[#parts + 1] = h.trails[1].Enabled and "smear" or "-"
		print("POSE " .. table.concat(parts, " | "))
	end
	dump("STANCE: READY")
	-- the three swings chained, as you'd really play them (each pressed the moment the last lets go)
	for n, name in ipairs({ "SLASH", "BACKHAND", "LEAP" }) do
		local s = SW[n]
		local m = WeaponFX.swingMoments(s)
		local marks = { m.coil + 0.01, (m.hold + m.contact) / 2, m.contact + 0.02, m.follow + 0.02 }
		local labels = { name .. ": WIND UP", name .. ": SNAP", name .. ": CUT", name .. ": FOLLOW THROUGH" }
		WeaponFX.swing(me, n)
		local start, i = t, 1
		step(s.Lock, function()
			if marks[i] and t - start >= marks[i] then
				dump(labels[i])
				i += 1
			end
		end)
	end
	step(WeaponFX.SETTLE + 0.4)
	local ab = Config.Weapons.List.EmberCleaver.Ability
	WeaponFX.spin(me, 1)
	local dur = ab.SpinTime / 0.76
	local start, i = t, 1
	local marks = { 0.1, 0.35, 0.6 }
	step(dur, function()
		if marks[i] and (t - start) / dur >= marks[i] then
			dump("WHIRLWIND: " .. ({ "COIL", "SPIN", "SPIN" })[i])
			i += 1
		end
	end)
end

if MODE == "poses" then
	poses()
	return
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
	print("PASS weaponfx")
else
	print(fails .. " failures")
end
