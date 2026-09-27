--!nocheck
-- Headless test of WEAPONFX (ReplicatedStorage/WeaponFX): how weapons look,
-- anime style. The real module on pretend R6 characters with all of Roblox's
-- own joints: the sword appears in the right hand in a fight and you stand
-- ready (blade low and back); a swing puts the whole body in (the arm sweeps
-- the blade the right way, the body coils and follows through, the legs
-- lunge, the free arm swings) and settles back into the stance; the
-- Whirlwind turns the body all the way round; hit-stop freezes a swing;
-- a slash mark tears across a hit; other players' swings show when their
-- SwingN changes; mastery 100 turns it gold; and letting go puts every
-- joint back exactly where it was.
--
--   luau test_weaponfx.luau            every check
--   luau test_weaponfx.luau -a poses   prints every joint and the sword over
--                                      each swing and the spin (render_sword.py)
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Instance, CFrame, Vector3 = M.Instance, M.CFrame, M.Vector3
local Players = M.services.Players
local RunService = M.services.RunService

local args = { ... }
local MODE = args[1] or "all"

local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
local WeaponFX = mount.require(mount.module("ReplicatedStorage/WeaponFX.lua"))
local W = Config.Weapons

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

WeaponFX.start()

local t = 0
local function step(seconds, each)
	local stop = t + seconds
	while t < stop - 1e-9 do
		t += 1 / 60
		M.run(t)
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
local function isRest(j)
	local p = j.Transform.Position
	return p.Magnitude < 1e-6 and (j.Transform.LookVector - Vector3.new(0, 0, -1)).Magnitude < 1e-4
		and (j.Transform.UpVector - Vector3.new(0, 1, 0)).Magnitude < 1e-4
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
-- where the blade's tip is, in the body's own space (the torso turned by the root joint)
local function tip(h)
	local torso = root.C0 * root.Transform * root.C1:Inverse()
	local arm = torso * shoulder.C0 * shoulder.Transform * shoulder.C1:Inverse()
	return (arm * h.weld.C0) * Vector3.new(0, 0, -5)
end
-- the body's turn (degrees, round the up axis) from the root joint
local function turn()
	local lv = (root.C0 * root.Transform * root.C1:Inverse()).LookVector
	return math.deg(math.atan2(-lv.X, -lv.Z))
end
-- the lean: how far the chest tips forward (degrees)
local function lean()
	local up = (root.C0 * root.Transform * root.C1:Inverse()).UpVector
	return math.deg(math.asin(math.clamp(-up.Z, -1, 1)))
end
-- where a foot is (the bottom of a leg), in the body's space
local function foot(hip)
	local torso = root.C0 * root.Transform * root.C1:Inverse()
	return (torso * hip.C0 * hip.Transform * hip.C1:Inverse()) * Vector3.new(0, -1, 0)
end

local function all()
	local ST = WeaponFX.STANCE
	step(0.2)
	check(not weapon(char), "no weapon: nothing in the hand")
	me:SetAttribute("Weapon", "IronSword")
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

	-- THE STANCE: standing still you're ready - arm down and back, blade behind you
	step(1)
	check(off(shoulder, ST.RS) < 12, ("standing: the sword arm's in the stance (%.0f off)"):format(off(shoulder, ST.RS)))
	local bladeTip = tip(h)
	check(bladeTip.Z > 1 and bladeTip.Y < 0, ("the blade's held low and behind you (tip %.1f, %.1f, %.1f)"):format(bladeTip.X, bladeTip.Y, bladeTip.Z))
	check(foot(J.LH).Z < foot(J.RH).Z - 0.3, "left foot forward")
	local lo, hi = 99, -99
	step(3, function()
		lo, hi = math.min(lo, lean()), math.max(hi, lean())
	end)
	check(hi - lo > 1, ("...breathing (a little rise and fall: %.1f degrees)"):format(hi - lo))

	-- walking: the legs walk (left alone), the sword arm keeps the stance
	hum.MoveDirection = Vector3.new(1, 0, 0)
	local walkLeg = CFrame.Angles(0, 0, math.rad(30))
	for _ = 1, 40 do
		J.RH.Transform = walkLeg
		step(1 / 60)
	end
	check(J.RH.Transform == walkLeg, "walking: the legs are left to walk")
	check(off(shoulder, ST.RS) < 15, "walking: the sword arm keeps the stance")
	hum.MoveDirection = Vector3.new(0, 0, 0)
	J.RH.Transform = CFrame.new()
	step(0.6)

	-- where the tip goes while the smear is on: furthest right, furthest left, and which came first
	local function sweep(n)
		local most, least, mostAt, leastAt, frame, smeared = -99, 99, 0, 0, 0, false
		local maxTurn, minTurn, maxLean, stride = -999, 999, -99, 0
		WeaponFX.swing(me, n)
		step(W.Types.Sword.Swings[n].Lock, function()
			frame += 1
			maxTurn, minTurn = math.max(maxTurn, turn()), math.min(minTurn, turn())
			maxLean = math.max(maxLean, lean())
			stride = math.max(stride, math.abs(foot(J.LH).Z - foot(J.RH).Z))
			if h.trails[1].Enabled then
				smeared = true
				local x = tip(h).X
				if x > most then
					most, mostAt = x, frame
				end
				if x < least then
					least, leastAt = x, frame
				end
			end
		end)
		return { most = most, least = least, mostAt = mostAt, leastAt = leastAt, smeared = smeared,
			maxTurn = maxTurn, minTurn = minTurn, maxLean = maxLean, stride = stride }
	end

	-- swing 1: a slash right to left (+x is your right), the whole body in it
	local s1 = sweep(1)
	check(s1.smeared, "a glowing smear follows the blade through the cut")
	check(s1.most > 2 and s1.least < -2 and s1.mostAt < s1.leastAt, ("the slash sweeps the blade right to left (right %.1f, then left %.1f)"):format(s1.most, s1.least))
	check(s1.minTurn < -30 and s1.maxTurn > 40, ("the body coils back and whips through (turn %.0f to %.0f)"):format(s1.minTurn, s1.maxTurn))
	check(s1.maxLean > 12, ("it leans into the cut (%.0f degrees)"):format(s1.maxLean))
	check(s1.stride > 1.2, ("the legs lunge into a big stride (%.1f studs between the feet)"):format(s1.stride))
	step(0.3)
	check(off(shoulder, ST.RS) < 15 and not h.trails[1].Enabled, "then it settles back into the stance, smear off")

	-- swing 2: the backhand goes the other way
	local s2 = sweep(2)
	check(s2.most > 2 and s2.least < -2 and s2.leastAt < s2.mostAt, ("the backhand sweeps left to right (left %.1f, then right %.1f)"):format(s2.least, s2.most))
	check(s2.maxTurn > 30 and s2.minTurn < -40, "the body coils the other way for it")

	-- swing 3: the chop comes down from high, the body going down with it
	local highest, lowest, deepest = -99, 99, -99
	WeaponFX.swing(me, 3)
	step(W.Types.Sword.Swings[3].Lock, function()
		deepest = math.max(deepest, lean())
		if h.trails[1].Enabled then
			local p = tip(h)
			highest = math.max(highest, p.Y)
			lowest = math.min(lowest, p.Y)
		end
	end)
	check(highest > 4 and lowest < 1, ("the chop comes down from high above your head (tip y %.1f -> %.1f)"):format(highest, lowest))
	check(lowest > -3.5, ("...without driving the blade through the floor (lowest %.1f; the floor is -3)"):format(lowest))
	check(deepest > 30, ("the whole body bends into the chop (%.0f degrees)"):format(deepest))

	-- hit-stop: a swing frozen for a blink when the blade bites
	WeaponFX.swing(me, 1)
	step(0.15)
	local before = h.anim and h.anim.t
	WeaponFX.hitStop(me, 0.1)
	step(0.08)
	check(h.anim and math.abs(h.anim.t - before) < 1e-6, "hit-stop: the swing freezes for a blink")
	step(0.1)
	check(h.anim and h.anim.t > before, "...then carries on")
	step(1)

	-- the Whirlwind: the body turns all the way round, spins times
	for tierIndex, want in ipairs({ 1, 1, 2, 2, 3 }) do
		local total, last = 0, turn()
		WeaponFX.spin(me, tierIndex)
		local tier = Config.Weapons.List.IronSword.Ability.Tiers[tierIndex]
		step(tier.Spins * Config.Weapons.List.IronSword.Ability.SpinTime + 0.05, function()
			local now = turn()
			local d = now - last
			if d > 180 then
				d = d - 360
			elseif d < -180 then
				d = d + 360
			end
			total = total + d
			last = now
		end)
		check(math.abs(math.abs(total) - 360 * want) < 30, ("tier %d: the Whirlwind spins %d time(s) round (%.0f degrees)"):format(tierIndex, want, total))
		step(0.4)
		check(off(shoulder, ST.RS) < 15, "after the Whirlwind, back in the stance")
	end

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
	local oc, oj = r6("Friend")
	other.Character = oc
	table.insert(M.players, other)
	other:SetAttribute("Weapon", "IronSword")
	other:SetAttribute("Colosseum", true)
	other:SetAttribute("SwingN", "7:1") -- (an old swing, from before we could see them)
	step(0.2)
	local oh = WeaponFX._held[other]
	check(weapon(oc) ~= nil, "another fighter's sword shows on your screen")
	check(oh and oh.anim == nil, "...and an old swing counter doesn't make them swing")
	other:SetAttribute("SwingN", "8:2")
	step(0.05)
	check(oh.anim and oh.anim.kind == "swing" and oh.anim.n == 2, "their new swing plays on your screen")
	step(1)
	other:SetAttribute("AbilityN", "3:1")
	step(0.05)
	check(oh.anim and oh.anim.kind == "spin", "their Whirlwind plays on your screen")
	step(1)
	local _ = oj

	-- your own counter changing doesn't swing you twice (it played when you pressed)
	me:SetAttribute("SwingN", "99:1")
	step(0.1)
	check(h.anim == nil, "your own swing counter doesn't swing you again")

	-- mastery 100: the blade turns gold
	me:SetAttribute("Mastery", 100)
	step(0.1)
	local blade = weapon(char) and weapon(char):FindFirstChild("Blade")
	check(blade and blade.Color == M.Color3.fromRGB(254, 231, 97), "awakened at mastery 100: the blade's gold")
	check(WeaponFX.isGolden(me), "...and the slash marks know it")
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
	blocky:SetAttribute("Weapon", "IronSword")
	blocky:SetAttribute("Colosseum", true)
	blocky:SetAttribute("SwingN", "1:1")
	step(0.5)
	check(not weapon(bm), "no sword on a body without R6 joints")

	-- the pose sums on their own
	for n, keys in ipairs(WeaponFX.POSES.Sword) do
		local _, w0 = WeaponFX.swingPose(keys, 0, 0.4, ST)
		local cutPose, w1 = WeaponFX.swingPose(keys, 0.4, 0.4, ST)
		local endPose = WeaponFX.swingPose(keys, 1, 0.4, ST)
		check(w0 == 0 and w1 == 1, "swing " .. n .. ": blends in from nothing")
		check(math.abs(cutPose.RS[2] - keys.cut.RS[2]) < 1e-6, "swing " .. n .. ": at the moment it lands, it's the cut")
		check(math.abs(endPose.RS[3] - ST.RS[3]) < 1e-6 and math.abs(endPose.Grip[1] - ST.Grip[1]) < 1e-6, "swing " .. n .. ": it ends back in the stance")
		-- the follow-through flies past the end pose (overshoot)
		local past = false
		for i = 0, 40 do
			local p = WeaponFX.swingPose(keys, 0.4 + i * 0.006, 0.4, ST)
			for axis = 2, 3 do
				local a, b, c = keys.cut.RS[axis], keys.follow.RS[axis], p.RS[axis]
				if math.abs(b - a) > 5 and (c - a) / (b - a) > 1.02 then
					past = true
				end
			end
		end
		check(past, "swing " .. n .. ": the follow-through flies past and comes back")
	end
end

-- every joint over each swing and the spin, for the pictures
local function poses()
	me:SetAttribute("Weapon", "IronSword")
	me:SetAttribute("Mastery", 1)
	me:SetAttribute("SpireFloor", 2)
	step(1)
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
	dump("READY STANCE")
	for n, name in ipairs({ "SLASH", "BACKHAND", "CHOP" }) do
		local s = W.Types.Sword.Swings[n]
		local marks = { s.Contact * 0.55, s.Contact, math.min(0.82, s.Contact + 0.24) - 0.1 }
		local labels = { name .. ": COIL", name .. ": CUT", name .. ": FOLLOW THROUGH" }
		WeaponFX.swing(me, n)
		local start, i = t, 1
		step(s.Lock, function()
			if marks[i] and (t - start) / s.Lock >= marks[i] then
				dump(labels[i])
				i += 1
			end
		end)
		step(0.3)
	end
	local ab = Config.Weapons.List.IronSword.Ability
	WeaponFX.spin(me, 1)
	local start, i = t, 1
	local marks = { 0.25, 0.5, 0.75 }
	step(ab.SpinTime, function()
		if marks[i] and (t - start) / ab.SpinTime >= marks[i] then
			dump("WHIRLWIND " .. i)
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
