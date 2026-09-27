--!nocheck
-- Headless test of WEAPONFX (ReplicatedStorage/WeaponFX): how weapons look.
-- The real module on pretend R6 characters with Roblox's own joints: the
-- sword appears in the right hand in a fight (and goes away out of one), a
-- swing sweeps the blade the right way, the Whirlwind turns the body all the
-- way round, other players' swings show when their SwingN changes, mastery
-- 100 turns it gold, and afterwards every joint is exactly where it was.
--
--   luau test_weaponfx.luau            every check
--   luau test_weaponfx.luau -a poses   prints the joints and the sword over
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

-- a pretend R6 character with Roblox's own joints
local function part(model, name, size)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = CFrame.new()
	p.Parent = model
	return p
end
local function r6(name)
	local model = Instance.new("Model")
	model.Name = name
	local hrp = part(model, "HumanoidRootPart", Vector3.new(2, 2, 1))
	local torso = part(model, "Torso", Vector3.new(2, 2, 1))
	local arm = part(model, "Right Arm", Vector3.new(1, 2, 1))
	local hum = Instance.new("Humanoid")
	hum.MaxHealth = 100
	hum.Health = 100
	hum.Parent = model
	local shoulder = Instance.new("Motor6D")
	shoulder.Name = "Right Shoulder"
	shoulder.Part0, shoulder.Part1 = torso, arm
	shoulder.C0 = CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
	shoulder.C1 = CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
	shoulder.Transform = CFrame.new()
	shoulder.Parent = torso
	local root = Instance.new("Motor6D")
	root.Name = "RootJoint"
	root.Part0, root.Part1 = hrp, torso
	root.C0 = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	root.C1 = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	root.Transform = CFrame.new()
	root.Parent = hrp
	model.Parent = M.workspace
	return model, shoulder, root, hum
end

local me = Instance.new("Player")
me.Name = "Tester"
me.UserId = 1001
me.Parent = Players
Players.LocalPlayer = me
local char, shoulder, root, hum = r6("Tester")
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
-- where the blade's tip is, in the body's own space (the torso turned by the root joint)
local function tip(h, sh, rj)
	local torso = rj and (rj.C0 * rj.Transform * rj.C1:Inverse()) or CFrame.new()
	local arm = torso * sh.C0 * sh.Transform * sh.C1:Inverse()
	local grip = h.weld.C0
	return (arm * grip) * Vector3.new(0, 0, -4)
end
-- the body's turn (degrees, round the up axis) from the root joint
local function turn(rj)
	local lv = (rj.C0 * rj.Transform * rj.C1:Inverse()).LookVector
	return math.deg(math.atan2(-lv.X, -lv.Z))
end

local function all()
	-- no weapon, or not in a fight: nothing in the hand
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
		check(n >= 5, "it's a proper sword (handle, pommel, guard, blade, edge, tip): " .. n .. " pieces")
		check(h and h.weld and h.weld.Part0 == char["Right Arm"], "welded to the right arm")
		check(h and h.trail and h.trail.Enabled == false, "no trail while you're just holding it")
	end
	check(isRest(shoulder) and isRest(root), "holding it doesn't move the arm or the body")

	-- where the blade's tip goes while the trail is on: furthest right, and
	-- furthest left - and which came first
	local function sweep(n)
		local most, least, mostAt, leastAt, frame = -99, 99, 0, 0, 0
		local trailed = false
		WeaponFX.swing(me, n)
		step(W.Types.Sword.Swings[n].Lock, function()
			frame += 1
			if h.trail.Enabled then
				trailed = true
				local x = tip(h, shoulder, root).X
				if x > most then
					most, mostAt = x, frame
				end
				if x < least then
					least, leastAt = x, frame
				end
			end
		end)
		return most, least, mostAt, leastAt, trailed
	end

	-- swing 1: a slash right to left (+x is your right)
	local maxTwist, minTwist = -999, 999
	local conn = RunService.Stepped:Connect(function()
		maxTwist = math.max(maxTwist, turn(root))
		minTwist = math.min(minTwist, turn(root))
	end)
	local most, least, mostAt, leastAt, trailed = sweep(1)
	conn.Disconnect()
	check(trailed, "a white trail follows the blade through the swing")
	check(most > 2 and least < -1.5 and mostAt < leastAt, ("the slash sweeps the blade right to left (right %.1f, then left %.1f)"):format(most, least))
	check(maxTwist > 10 and minTwist < -10, ("the body winds up and follows through (turn %.0f to %.0f)"):format(minTwist, maxTwist))
	step(0.1)
	check(isRest(shoulder) and isRest(root), "after the swing, the arm and body are back exactly where they were")
	check(not h.trail.Enabled, "and the trail's off")

	-- swing 2: the backhand goes the other way
	most, least, mostAt, leastAt = sweep(2)
	check(most > 2 and least < -1.5 and leastAt < mostAt, ("the backhand sweeps left to right (left %.1f, then right %.1f)"):format(least, most))

	-- swing 3: the chop comes down from high
	local highest, lowest = -99, 99
	WeaponFX.swing(me, 3)
	step(W.Types.Sword.Swings[3].Lock, function()
		if h.trail.Enabled then
			local p = tip(h, shoulder, root)
			highest = math.max(highest, p.Y)
			lowest = math.min(lowest, p.Y)
		end
	end)
	check(highest > 3 and lowest < 1, ("the chop comes down from above your head (tip y %.1f -> %.1f)"):format(highest, lowest))
	step(0.1)
	check(isRest(shoulder) and isRest(root), "rest again after the chop")

	-- the Whirlwind: the body turns all the way round, spins times
	for tierIndex, want in ipairs({ 1, 1, 2, 2, 3 }) do
		local total, last = 0, turn(root)
		WeaponFX.spin(me, tierIndex)
		local tier = Config.Weapons.List.IronSword.Ability.Tiers[tierIndex]
		step(tier.Spins * Config.Weapons.List.IronSword.Ability.SpinTime + 0.05, function()
			local now = turn(root)
			local d = now - last
			if d > 180 then
				d = d - 360
			elseif d < -180 then
				d = d + 360
			end
			total = total + d
			last = now
		end)
		check(math.abs(math.abs(total) - 360 * want) < 25, ("tier %d: the Whirlwind spins %d time(s) round (%.0f degrees)"):format(tierIndex, want, total))
		check(isRest(shoulder) and isRest(root), "after the Whirlwind, back to rest")
	end

	-- animations from Roblox move the joints every frame: a swing blends from them, then gives them back
	local walk = CFrame.Angles(0, 0, math.rad(25))
	for _ = 1, 10 do
		shoulder.Transform = walk
		step(1 / 60)
	end
	check(shoulder.Transform == walk, "just walking: the arm's left alone")
	shoulder.Transform = CFrame.new() -- (stood still again)

	-- someone else: their swing shows when their SwingN changes
	local other = Instance.new("Player")
	other.Name = "Friend"
	other.UserId = 1002
	other.Parent = Players
	local oc, os_, orj = r6("Friend")
	other.Character = oc
	table.insert(M.players, other)
	other:SetAttribute("Weapon", "IronSword")
	other:SetAttribute("Colosseum", true)
	other:SetAttribute("SwingN", "7:1") -- (an old swing, from before we could see them)
	step(0.2)
	check(weapon(oc) ~= nil, "another fighter's sword shows on your screen")
	check(isRest(os_), "...and an old swing counter doesn't make them swing")
	other:SetAttribute("SwingN", "8:2")
	local moved = false
	step(0.3, function()
		moved = moved or not isRest(os_)
	end)
	check(moved, "their new swing plays on your screen")
	other:SetAttribute("AbilityN", "3:1")
	local spun = false
	step(0.2, function()
		spun = spun or math.abs(turn(orj)) > 30
	end)
	check(spun, "their Whirlwind plays on your screen")
	step(1)

	-- your own counter changing doesn't swing you twice (your swing already played when you pressed)
	me:SetAttribute("SwingN", "99:1")
	step(0.2)
	check(isRest(shoulder) or shoulder.Transform == walk, "your own swing counter doesn't swing you again")

	-- mastery 100: the blade turns gold
	me:SetAttribute("Mastery", 100)
	step(0.1)
	local blade = weapon(char) and weapon(char):FindFirstChild("Blade")
	check(blade and blade.Color == M.Color3.fromRGB(254, 231, 97), "awakened at mastery 100: the blade's gold")
	me:SetAttribute("Mastery", 5)
	step(0.1)
	blade = weapon(char) and weapon(char):FindFirstChild("Blade")
	check(blade and blade.Color ~= M.Color3.fromRGB(254, 231, 97), "...and steel again below it")

	-- leaving the fight, dying, dropping the weapon: it's put away
	me:SetAttribute("SpireFloor", nil)
	step(0.1)
	check(not weapon(char), "out of the fight: put away")
	me:SetAttribute("SpireFloor", 2)
	step(0.1)
	check(weapon(char) ~= nil, "back in: out again")
	WeaponFX.swing(me, 1)
	step(0.1)
	hum.Health = 0
	step(0.1)
	check(not weapon(char) and isRest(shoulder) and isRest(root), "dying mid-swing: put away, joints back")
	hum.Health = 100
	step(0.1)
	me:SetAttribute("Weapon", nil)
	step(0.1)
	check(not weapon(char), "back to fists: nothing in the hand")

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
		local _, _, w0 = WeaponFX.swingPose(keys, 0, 0.4)
		local _, g1, w1 = WeaponFX.swingPose(keys, 0.4, 0.4)
		local _, g2, w2 = WeaponFX.swingPose(keys, 1, 0.4)
		check(w0 == 0 and w1 == 1 and w2 == 0, "swing " .. n .. ": blends in from nothing and back out to nothing")
		check(g1 == WeaponFX.GRIP_SWING and g2 == WeaponFX.GRIP_CARRY, "swing " .. n .. ": the blade turns in line for the cut, and back to carrying after")
	end
end

-- the joints over each swing and the spin, for the pictures
local function poses()
	me:SetAttribute("Weapon", "IronSword")
	me:SetAttribute("Mastery", 1)
	me:SetAttribute("SpireFloor", 2)
	step(0.2)
	local h = WeaponFX._held[me]
	for _, p in ipairs(h.model:GetChildren()) do
		if p:IsA("Part") then
			local w = p:FindFirstChildOfClass("Weld")
			local c = p.Color
			local off = (p == h.handle) and CFrame.new() or w.C0
			print(string.format("PIECE %s %.2f %.2f %.2f %d %d %d %s", p.Name, p.Size.X, p.Size.Y, p.Size.Z,
				math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5), table.concat({ off:GetComponents() }, " ")))
		end
	end
	local function dump(label)
		print(string.format("POSE %s | %s | %s | %s | %s", label, table.concat({ shoulder.Transform:GetComponents() }, " "),
			table.concat({ root.Transform:GetComponents() }, " "), table.concat({ h.weld.C0:GetComponents() }, " "), h.trail.Enabled and "trail" or "-"))
	end
	dump("HOLDING")
	for n, name in ipairs({ "SLASH", "BACKHAND", "CHOP" }) do
		local s = W.Types.Sword.Swings[n]
		local marks = { s.Contact * 0.45, s.Contact, math.min(0.85, s.Contact + 0.28) }
		local labels = { name .. ": WIND UP", name .. ": CUT", name .. ": FOLLOW THROUGH" }
		WeaponFX.swing(me, n)
		local start, i = t, 1
		step(s.Lock, function()
			if marks[i] and (t - start) / s.Lock >= marks[i] then
				dump(labels[i])
				i += 1
			end
		end)
		step(0.05)
	end
	local ab = Config.Weapons.List.IronSword.Ability
	WeaponFX.spin(me, 1)
	local start, i = t, 1
	local marks = { 0.2, 0.45, 0.7 }
	step(ab.SpinTime * 1, function()
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
