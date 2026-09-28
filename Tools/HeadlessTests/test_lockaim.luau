--!nocheck
-- Headless test of WHERE YOUR LOCK-ON AIMS (CombatClient's targetPoint): the
-- real code, cut out of CombatClient, run on pretend enemies. A boss is drawn
-- by BossClient, far bigger than the small invisible Root the server moves
-- (Scribble: 16 studs tall on a 4-stud Root), so BossClient says where its
-- middle really is (AimAt, AimSize, AimTime - test_bosses.luau's "aim" mode
-- checks those against what's drawn). Here: the lock-on uses them while
-- they're fresh, aims at a boss up in the air as if it still stood under
-- itself (the camera keeps the ground in view, the lock holds), and anything
-- else is aimed at the middle of its parts, as before.
--
--   luau test_lockaim.luau
local M = require("./rbxmock")
local S = require("./sources")
local Instance, CFrame, Vector3 = M.Instance, M.CFrame, M.Vector3

local env = M.env({})

-- targetPoint, exactly as it is in CombatClient
local src = S.files["StarterPlayerScripts/CombatClient.client.lua"]
local a = assert(string.find(src, "-- Where to aim at it", 1, true), "targetPoint's note isn't in CombatClient")
local b = assert(string.find(src, "\nlocal function lockable", a, true), "can't find where targetPoint ends")
local targetPoint = M.load(string.sub(src, a, b) .. "\nreturn targetPoint", "CombatClient (targetPoint)", env)()

local fails = 0
local function check(ok, msg)
	if not ok then
		fails += 1
		print("FAIL: " .. msg)
	end
end
local function near(v, w, tol)
	return (v - w).Magnitude <= (tol or 1e-3)
end

-- a boss the way BossService makes one: a 5 x 4.25 x 5 Root standing on the floor at y = 10
local boss = Instance.new("Model")
boss.Name = "Boss_Scribble"
local root = Instance.new("Part")
root.Name = "Root"
root.Size = Vector3.new(5, 4.25, 5)
root.CFrame = CFrame.new(100, 10 + 4.25 / 2, 50)
root.Transparency = 1
root.Parent = boss
boss.PrimaryPart = root
boss.Parent = M.workspace

local t = 0
local function at(seconds)
	t = seconds
	M.run(t)
end
at(10)

-- 1) nothing from BossClient yet: the middle of its parts (its Root), as before
local p, size, drawn = targetPoint(boss)
check(near(p, root.Position) and not drawn, "with nothing measured it should aim at its Root: " .. tostring(p))
check(size.X == 5 and size.Y == 4.25, "...and be as big as its Root")

-- 2) BossClient's measurement, fresh: his chest, and his size
boss:SetAttribute("AimAt", Vector3.new(100.5, 19.1, 50))
boss:SetAttribute("AimSize", 16.5)
boss:SetAttribute("AimTime", 10)
p, size, drawn = targetPoint(boss)
check(drawn == true, "a fresh measurement should be used")
check(near(p, Vector3.new(100.5, 19.1, 50)), "it should aim at his chest (19.1): " .. tostring(p))
check(size.X == 16.5 and size.Y == 16.5 and size.Z == 16.5, "and frame all 16.5 studs of him")

-- 3) up in the air (a leap): aimed at as if he still stood under himself -
-- 0.6 of his size over the floor - so the camera keeps the ground in view
at(10.2)
boss:SetAttribute("AimAt", Vector3.new(104, 60, 52))
boss:SetAttribute("AimTime", 10.2)
p, size, drawn = targetPoint(boss)
check(drawn and near(p, Vector3.new(104, 10 + 16.5 * 0.6, 52)), "up in the air, it should aim at his standing chest: " .. tostring(p))

-- 4) the measurement goes stale (BossClient stopped): back to its Root
at(11)
p, size, drawn = targetPoint(boss)
check(not drawn and near(p, root.Position), "a stale measurement shouldn't be trusted: " .. tostring(p))

-- 5) a strange value (not a position): ignored
boss:SetAttribute("AimAt", "nowhere")
boss:SetAttribute("AimTime", 11)
p, size, drawn = targetPoint(boss)
check(not drawn and near(p, root.Position), "a strange AimAt should be ignored")

-- 6) an ordinary enemy (a dummy, all real parts): the middle of its parts
local dummy = Instance.new("Model")
dummy.Name = "Straw Dummy"
local body = Instance.new("Part")
body.Size = Vector3.new(2, 6, 2)
body.CFrame = CFrame.new(0, 3, 0)
body.Parent = dummy
local hat = Instance.new("Part")
hat.Size = Vector3.new(2, 2, 2)
hat.CFrame = CFrame.new(0, 7, 0)
hat.Parent = dummy
dummy.PrimaryPart = body
dummy.Parent = M.workspace
p, size, drawn = targetPoint(dummy)
check(not drawn and near(p, Vector3.new(0, 4, 0)) and near(size, Vector3.new(2, 8, 2)), "a dummy should be aimed at the middle of its parts: " .. tostring(p))

-- 7) the lock-on camera (CombatClient's lockView): behind you, framing you
-- both, further back and higher for a bigger target - and a boss looked at
-- a little higher the taller it is (so a tall one's head isn't up behind
-- the boss bar); anything else exactly as before
local c = assert(string.find(src, "-- Where your lock-on camera sits and looks", 1, true), "lockView's note isn't in CombatClient")
local d = assert(string.find(src, 'RunService:BindToRenderStep("LockOnCamera"', c, true), "can't find where lockView ends")
local lockView = M.load(string.sub(src, c, d - 1) .. "\nreturn lockView", "CombatClient (lockView)", env)()
local ppos, tpos = Vector3.new(0, 4.5, 30), Vector3.new(0, 9, 0)
local function oldSums(big)
	local dir = Vector3.new(0, 0, -1)
	return ppos - dir * (12 + big * 0.35) + Vector3.new(0, 4 + big * 0.12, 0) + Vector3.new(1.5, 0, 0), ppos:Lerp(tpos, 0.55)
end
local eye, look = lockView(ppos, tpos, Vector3.new(5, 4.25, 5), false)
local wantEye, wantLook = oldSums(5)
check(near(eye, wantEye) and near(look, wantLook), "for anything but a boss, the camera should be just as before")
eye, look = lockView(ppos, tpos, Vector3.new(16.5, 16.5, 16.5), true)
wantEye, wantLook = oldSums(16.5)
check(near(eye, wantEye), "a boss's camera should sit where the sums put it")
check(near(look, wantLook + Vector3.new(0, (16.5 - 10) * 0.12, 0)), "a 16.5-stud boss should be looked at 0.78 higher: " .. tostring(look))
eye, look = lockView(ppos, tpos, Vector3.new(8, 8, 8), true)
check(near(look, select(2, oldSums(8))), "a boss no taller than 10 studs isn't looked at any higher")
check(lockView(ppos, Vector3.new(0.2, 3, 30.1), Vector3.new(5, 5, 5), true) == nil, "right on top of it, there's no way to face: no camera move")

for _, e in ipairs(M.errors) do
	print("ERROR " .. tostring(e))
	fails += 1
end
if fails == 0 then
	print("PASS")
else
	print(fails .. " FAILED")
end
