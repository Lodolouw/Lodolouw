--!nocheck
-- Headless test of the WEAPON TYPES in WeaponFX (gauntlets, hammer, daggers,
-- scythe, katana): each one in hand (two for gauntlets and daggers), its own
-- stance, and every swing of its string - an arm really swings, the smear
-- shows through the cut, the feet stay down, and it settles back.
--   luau test_weapontypes.luau            every check
--   luau test_weapontypes.luau -a trace   which way the weapon points, every frame of every swing
--   luau test_weapontypes.luau -a poses   the blocks and poses for render_weapontypes.py
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

-- WEAPON TYPES (Config.Weapons.Types / WeaponFX.STANCES, POSES, BUILDERS):
-- each new type's weapon appears in hand (two for gauntlets and daggers),
-- stands in its own stance, and swings its whole string - winding up,
-- cutting (the smear on), and settling back - with the feet on the floor.
local ORDER = { "Fists", "Hammer", "Daggers", "Scythe", "Katana" }
local MODE = ({ ... })[1] or "all"
local pick = {}
for id, def in pairs(W.List) do
	if def.Pack and not pick[def.Type] then
		pick[def.Type] = id
	end
end
me:SetAttribute("SpireFloor", 2)

-- -a trace: the weapon's direction (in the character's own space) every
-- frame through each swing: which way it points (degrees round from
-- straight ahead, + = to your left) and how high (degrees up)
if MODE == "trace" then
	local function body()
		return root.C0 * root.Transform * root.C1:Inverse()
	end
	for _, kind in ipairs(ORDER) do
		me:SetAttribute("Weapon", pick[kind])
		step(1.5)
		local h = WeaponFX._held[me]
		for n, s in ipairs(W.Types[kind].Swings) do
			local m = WeaponFX.swingMoments(s)
			local line = {}
			WeaponFX.swing(me, n)
			local start = t
			step(s.Lock + 0.1, function()
				local arm = body() * shoulder.C0 * shoulder.Transform * shoulder.C1:Inverse()
				local g = arm * h.weld.C0
				local d = g:VectorToWorldSpace(Vector3.new(0, 0, -1))
				local az = math.deg(math.atan2(-d.X, -d.Z))
				local el = math.deg(math.asin(math.clamp(d.Y, -1, 1)))
				local tt = t - start
				local mark = (math.abs(tt - m.contact) < 1 / 120) and "*" or ""
				table.insert(line, string.format("%s%.0f/%.0f", mark, az, el))
			end)
			print(("TRACE %s %d contact@%.2fs: %s"):format(kind, n, m.contact, table.concat(line, " ")))
		end
		step(WeaponFX.SETTLE + 0.4)
	end
	return
end

-- -a poses: prints each type's blocks and poses for render_weapontypes.py
if MODE == "poses" then
	for _, kind in ipairs(ORDER) do
		me:SetAttribute("Weapon", pick[kind])
		step(1.5)
		local h = WeaponFX._held[me]
		print("TYPE " .. kind .. " " .. W.List[pick[kind]].Name)
		for _, p in ipairs(h.model:GetChildren()) do
			if p:IsA("Part") then
				local w = p:FindFirstChildOfClass("Weld")
				if p == h.handle or (w and w.Part0 == h.handle) then
					local c = p.Color
					local o = (p == h.handle) and CFrame.new() or w.C0
					print(string.format("PIECE %s %.2f %.2f %.2f %d %d %d %s", p.Name, p.Size.X, p.Size.Y, p.Size.Z,
						math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5), table.concat({ o:GetComponents() }, " ")))
				end
			end
		end
		-- the second one in the left hand: its grip on the left arm, and its blocks
		for _, p in ipairs(h.model:GetChildren()) do
			local og = p:IsA("Part") and p:FindFirstChild("OffGrip")
			if og then
				print("OFFGRIP " .. table.concat({ og.C0:GetComponents() }, " "))
				for _, q in ipairs(h.model:GetChildren()) do
					local w = q:IsA("Part") and q:FindFirstChildOfClass("Weld")
					if q == p or (w and w.Part0 == p) then
						local c = q.Color
						local o = (q == p) and CFrame.new() or w.C0
						print(string.format("OFFPIECE %s %.2f %.2f %.2f %d %d %d %s", q.Name, q.Size.X, q.Size.Y, q.Size.Z,
							math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5), table.concat({ o:GetComponents() }, " ")))
					end
				end
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
		dump("STANCE")
		for n, s in ipairs(W.Types[kind].Swings) do
			local m = WeaponFX.swingMoments(s)
			local marks = { m.coil + 0.01, m.contact + 0.02, m.follow + 0.02 }
			local labels = { "SWING " .. n .. ": WIND UP", "SWING " .. n .. ": CUT", "SWING " .. n .. ": FOLLOW" }
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
	end
	return
end

for _, kind in ipairs(ORDER) do
	local T = W.Types[kind]
	check(T ~= nil, kind .. ": has a moveset in Config")
	check(WeaponFX.STANCES[kind] ~= nil, kind .. ": has its own stance")
	check(WeaponFX.POSES[kind] and #WeaponFX.POSES[kind] == #T.Swings, kind .. ": a pose for every swing")
	local id = pick[kind]
	check(id ~= nil, kind .. ": a launch weapon of this type")
	me:SetAttribute("Weapon", id)
	step(0.3)
	local model = weapon(char)
	local h = WeaponFX._held[me]
	check(model ~= nil and h ~= nil and h.id == id, kind .. ": " .. tostring(id) .. " is in hand")
	if model and h then
		local parts = 0
		for _, p in ipairs(model:GetChildren()) do
			if p:IsA("Part") then
				parts += 1
			end
		end
		check(parts >= 4, kind .. ": a chunky model (" .. parts .. " pieces)")
		local offhand = false
		for _, d in ipairs(model:GetDescendants()) do
			if d.Name == "OffGrip" and d.Part0 == char["Left Arm"] then
				offhand = true
			end
		end
		check(offhand == (WeaponFX.OFFHAND[kind] ~= nil), kind .. ": " .. (WeaponFX.OFFHAND[kind] and "one in each hand" or "one weapon"))
		step(1.2)
		local ST = WeaponFX.STANCES[kind]
		check(off(shoulder, ST.RS) < 14, ("%s: standing in its own stance (%.0f off)"):format(kind, off(shoulder, ST.RS)))
		check(math.abs(lowFoot() + 3) < 0.05, ("%s: feet on the floor (%.2f)"):format(kind, lowFoot()))
		for n, s in ipairs(T.Swings) do
			local smeared, moved, floorOk = false, 0, true
			local startR, startL = J.RS.Transform, J.LS.Transform
			local function turned(a, b)
				return math.deg((a.LookVector - b.LookVector).Magnitude + (a.UpVector - b.UpVector).Magnitude)
			end
			WeaponFX.swing(me, n)
			step(s.Lock + WeaponFX.SETTLE + 0.3, function()
				if h.trails[1].Enabled then
					smeared = true
				end
				moved = math.max(moved, turned(J.RS.Transform, startR), turned(J.LS.Transform, startL))
				if lowFoot() > -2.9 and (WeaponFX.POSES[kind][n].cut.Hop[1] or 0) == 0 and (WeaponFX.POSES[kind][n].coil.Hop[1] or 0) == 0 then
					floorOk = false
				end
			end)
			check(smeared, ("%s swing %d: the smear shows through the cut"):format(kind, n))
			check(moved > 25, ("%s swing %d: an arm really swings (%.0f)"):format(kind, n, moved))
			check(floorOk, ("%s swing %d: feet stay down (no leap in this one)"):format(kind, n))
			check(h.anim == nil, ("%s swing %d: it's over and settled back"):format(kind, n))
		end
	end
end
-- letting go puts it all away
me:SetAttribute("Weapon", nil)
step(0.3)
check(weapon(char) == nil, "no weapon: nothing in either hand")

if fails == 0 then
	print("PASS weapon types")
else
	print(fails .. " failures")
end
