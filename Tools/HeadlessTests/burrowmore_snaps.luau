--!nocheck
-- Snapshots of Knight Burrowmore for pictures: the real Glimmer Dig
-- (DigBuilder), the real BossService with his moves and the real BossClient
-- drawing him, and a pretend player (a blocky figure, for scale). At six
-- moments every part you'd see is printed with the camera:
--   dig     - the dig from the gate, the knight kneeling in the middle
--   pose    - waking up: the pose at the end (a close look at him)
--   drop    - a Shovel Drop: up in the air, the red circle following you
--   dash    - a Charge Dash winding up: the red lane, sparks off the shovel
--   anchor  - an Anchor Toss: the anchor flying on its chain onto its circle
--   meteor  - phase two: the Shovel Meteor's huge shadow (armour cracked)
--   luau burrowmore_snaps.luau > burrowmore_snaps.txt
--   python3 render_snaps.py burrowmore_snaps.txt ../../Docs/burrowmore_preview.png
-- `-a poses` instead: close-ups of him (a model sheet), twelve poses in a
-- grid three across:
--   luau burrowmore_snaps.luau -a poses > poses.txt
--   python3 render_snaps.py poses.txt ../../Docs/burrowmore_poses.png --cols 3 --title ""
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Vector3, CFrame, Instance = M.Vector3, M.CFrame, M.Instance
local CollectionService = M.services.CollectionService
local RunService = M.services.RunService
local Players = M.services.Players
local workspace = M.workspace
local realPrint = print
local MODE = ({ ... })[1] or "fight"

local arena = mount.require(mount.module("ServerScriptService/DigBuilder.lua")).Build()
M.run(1)
local spawnPart = CollectionService:GetTagged("ArenaSpawn")[1]

-- the player: a blocky figure you can see (for scale), standing where we say
local me = Instance.new("Player")
me.Name = "Alpha"
me.UserId = 1001
me.Parent = Players
M.players = { me }
Players.LocalPlayer = me
local char = Instance.new("Model")
char.Name = "Alpha"
local hum = Instance.new("Humanoid")
hum.MaxHealth, hum.Health = 1e9, 1e9
hum.Parent = char
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Size = Vector3.new(2, 2, 1)
root.Transparency = 1
root.Parent = char
char.PrimaryPart = root
char.Parent = workspace
me.Character = char
local figure = {}
local function limb(name, size, offset, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Parent = char
	table.insert(figure, { part = p, offset = offset })
end
limb("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0), M.Color3.fromRGB(0, 153, 219))
limb("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 1.6, 0), M.Color3.fromRGB(254, 231, 97))
limb("LeftArm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 0, 0), M.Color3.fromRGB(254, 231, 97))
limb("RightArm", Vector3.new(1, 2, 1), Vector3.new(1.5, 0, 0), M.Color3.fromRGB(254, 231, 97))
limb("LeftLeg", Vector3.new(1, 2, 1), Vector3.new(-0.5, -2, 0), M.Color3.fromRGB(62, 137, 72))
limb("RightLeg", Vector3.new(1, 2, 1), Vector3.new(0.5, -2, 0), M.Color3.fromRGB(62, 137, 72))
local function standAt(pos, lookAt)
	local cf = CFrame.lookAt(pos, Vector3.new(lookAt.X, pos.Y, lookAt.Z))
	root.CFrame = cf
	for _, f in ipairs(figure) do
		f.part.CFrame = cf * CFrame.new(f.offset)
	end
end
local gui = Instance.new("PlayerGui")
gui.Name = "PlayerGui"
gui.Parent = me
local scripts = Instance.new("PlayerScripts")
scripts.Name = "PlayerScripts"
scripts.Parent = me
local kick = Instance.new("BindableEvent")
kick.Name = "CombatCameraKick"
kick.Parent = scripts
local cam = Instance.new("Camera")
cam.ViewportSize = { X = 1280, Y = 720 }
cam.Parent = workspace
workspace.CurrentCamera = cam

-- pretend CombatService / PlayerService (nobody gets hurt in a picture)
local Combat = {
	PlayersInArena = function(f)
		return me:GetAttribute("SpireFloor") == f and { me } or {}
	end,
	IsFighting = function(p)
		return p:GetAttribute("SpireFloor") ~= nil
	end,
	IsInvulnerable = function()
		return true
	end,
	DamagePlayer = function()
		return false
	end,
	Shove = function() end,
	SetTargetShape = function() end,
}
local Profile = { RecordBossKill = function() return true end, AddPower = function() end, AddChest = function() end }
local BS = mount.require(mount.module("ServerScriptService/BossService.lua"))
BS.Start(Combat, Profile)
local E = BS.Encounter(3)
local model = E.model
local home = E.home
mount.runClient("StarterPlayerScripts/BossClient.client.lua", me)

local T = 0
local DT = 1 / 30
local function step(seconds)
	local stop = T + seconds
	while T < stop do
		T += DT
		M.run(T)
		RunService.Heartbeat:Fire(DT)
		RunService.RenderStepped:Fire(DT)
	end
end

local function esc(s)
	return (string.gsub(tostring(s), '[%c"\\|]', ""))
end
local function snap(name, eye, look)
	cam.CFrame = CFrame.lookAt(eye, look)
	realPrint(string.format("SNAP %s %.3f %.3f %.3f %.3f %.3f %.3f", name, eye.X, eye.Y, eye.Z, look.X, look.Y, look.Z))
	local roots = { arena, workspace:FindFirstChild("BossFX"), char }
	for _, r in ipairs(roots) do
		for _, d in ipairs(r and r:GetDescendants() or {}) do
			if d:IsA("BasePart") then
				local t = d.Transparency or 0
				if t < 0.98 then
					local comps = { d.CFrame:GetComponents() }
					for i, v in ipairs(comps) do
						comps[i] = string.format("%.3f", v)
					end
					local col = d.Color
					realPrint(string.format('{"n":"%s","c":"%s","s":[%.3f,%.3f,%.3f],"cf":[%s],"col":[%d,%d,%d],"m":"%s","sh":"%s","t":%.2f}',
						esc(d.Name), d.ClassName, d.Size.X, d.Size.Y, d.Size.Z, table.concat(comps, ","),
						math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5),
						d.Material.Name, d.Shape and d.Shape.Name or "Block", t))
				end
			end
		end
	end
	local hp = (model:GetAttribute("Health") or 1) / math.max(model:GetAttribute("MaxHealth") or 1, 1)
	local state = model:GetAttribute("State")
	local awake = state == "Waking" or state == "Fighting" or state == "Transition"
	realPrint(string.format("BAR %s|%.3f|%d", awake and "Knight Burrowmore, the Honourable Digger" or "", hp, (model:GetAttribute("Phase") or 1)))
	realPrint("ENDSNAP")
end

local function flatDir(a, b)
	local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	return d.Magnitude > 0.01 and d.Unit or Vector3.new(0, 0, 1)
end
local function bossPos()
	local p = model:GetPivot().Position
	return Vector3.new(p.X, home.Y, p.Z)
end

-- force one of his moves right now (like the tests do)
local function force(name)
	while model:GetAttribute("State") ~= "Fighting" do
		step(0.1)
	end
	E.token += 1
	local token = E.token
	E.target, E.targetSince = me, M.now()
	E.motion, E.sweep, E.arc = nil, nil, nil
	local fn = E.boss.Attacks[name]
	if name == "ShovelMeteor" then
		fn = E.boss._Meteor
	end
	M.task.spawn(function()
		fn(E, token)
	end)
end

-- a close look at him from in front (a little to one side), at his chest
local function closeUp(name, dist, side, height)
	local fx = workspace:FindFirstChild("BossFX")
	local bodyModel = fx and fx:FindFirstChild("BurrowmoreBody")
	local chest = bodyModel and bodyModel:FindFirstChild("Chest")
	local b = bossPos()
	local look = model:GetPivot().LookVector
	look = Vector3.new(look.X, 0, look.Z).Unit
	local at = chest and chest.Position or (b + Vector3.new(0, 7, 0))
	if name == "chest" then
		at = b + Vector3.new(0, 2, 0) -- (his treasure chest, where he knelt)
	end
	-- (the camera stays inside the dig: near its edge, it looks outward from the middle instead)
	local eyeFlat = b + look * (dist or 22)
	if Vector3.new(eyeFlat.X - home.X, 0, eyeFlat.Z - home.Z).Magnitude > 74 or name == "chest" then
		look = flatDir(b, home)
	end
	local sideV = look:Cross(Vector3.new(0, 1, 0))
	snap(name, at + look * (dist or 22) + sideV * (side or 9) + Vector3.new(0, height or 2, 0), at + Vector3.new(0, -0.5, 0))
end

if MODE == "poses" then
	-- keep the player out of the way (far behind the camera)
	standAt(home + Vector3.new(0, 3, 70), home)
	step(1)
	closeUp("kneel", 20, 8, 1)
	me:SetAttribute("SpireFloor", 3)
	standAt(home + Vector3.new(0, 3, 40), home)
	step(E.def.WakeTime * 0.86)
	closeUp("wakepose", 23, 8, 1)
	step(1.2)
	E.chase, E.track = false, false
	standAt(home + Vector3.new(0, 3, 60), home)
	local function pose(move, t, name, dist, side, height)
		force(move)
		step(t)
		closeUp(name, dist, side, height)
		step(6)
	end
	local sw = E.def.Attacks.ShovelSwing
	pose("ShovelSwing", sw.Tell * 0.85, "swing", 22, -8, 1)
	local dr = E.def.Attacks.ShovelDrop
	pose("ShovelDrop", dr.Tell + 0.3, "air", 26, 10, -2)
	local df = E.def.Attacks.DirtFling
	pose("DirtFling", df.Tell * 0.85, "fling", 22, 9, 1)
	pose("AnchorToss", 0.2, "relic", 22, 8, 1)
	local an = E.def.Attacks.AnchorToss
	pose("AnchorToss", 0.35 + (an.Tell - 0.35) * 0.6, "anchorswing", 26, 10, 3)
	local fs = E.def.Attacks.FireStick
	pose("FireStick", fs.Tell + 0.05, "fire", 22, -9, 1)
	pose("Taunt", 1.1, "taunt", 21, 8, 1)
	local tp = E.def.Attacks.TriplePogo
	pose("TriplePogo", tp.Tell + tp.Hops * tp.Air + (tp.Hops - 1) * tp.Ground + 0.5, "dizzy", 21, 8, 1)
	-- NO QUARTER! (the armour breaks)
	model:SetAttribute("Health", math.floor((model:GetAttribute("MaxHealth") or 1) * 0.49))
	model:FindFirstChild("OnHit"):Fire(me, 1, false)
	step(E.def.BreakTime * 0.55)
	closeUp("noquarter", 24, 8, 1)
	step(E.def.BreakTime)
	-- the end: down on one knee, then the chest
	model:SetAttribute("Health", 0)
	model:FindFirstChild("OnHit"):Fire(me, 1, true)
	step(5.2)
	closeUp("chest", 20, 8, 0)
	for _, e in ipairs(M.errors) do
		realPrint("ERROR " .. tostring(e))
	end
	return
end

-- 1) the dig from the gate: the knight kneeling in the middle
standAt(spawnPart.Position, home)
step(1)
snap("dig", home + Vector3.new(34, 30, 128), home + Vector3.new(0, 4, 0))

-- 2) he wakes (the player walks up close)
local stand = home + Vector3.new(0, 3, 30)
standAt(stand, home)
me:SetAttribute("SpireFloor", 3)
step(E.def.WakeTime * 0.86)
snap("pose", home + Vector3.new(-11, 9, 26), home + Vector3.new(0, 7, 0))
step(1)

-- 3) a Shovel Drop: in the air, the circle following the player
standAt(home + Vector3.new(14, 3, 26), home)
force("ShovelDrop")
local a = E.def.Attacks.ShovelDrop
step(a.Tell + (a.Air + (a.Hang or 0)) * 0.42)
standAt(home + Vector3.new(18, 3, 22), bossPos())
step(0.1)
do
	local b = bossPos()
	local p = root.Position
	local mid = (b + p) / 2
	local side = flatDir(b, p):Cross(Vector3.new(0, 1, 0))
	snap("drop", mid + side * 46 + Vector3.new(0, 12, 0), mid + Vector3.new(0, 13, 0))
end
step(3)

-- 4) a Charge Dash winding up (the lane has locked on)
standAt(bossPos() + Vector3.new(-30, 3, 26), bossPos())
force("ChargeDash")
local c = E.def.Attacks.ChargeDash
step(c.Tell * 0.85)
do
	local b = bossPos()
	local dir = flatDir(b, root.Position)
	snap("dash", b - dir * 16 + dir:Cross(Vector3.new(0, 1, 0)) * 14 + Vector3.new(0, 14, 0), b + dir * 22 + Vector3.new(0, 2, 0))
end
step(3.5)

-- 5) an Anchor Toss: the anchor flying onto its circle
standAt(bossPos() + Vector3.new(26, 3, -20), bossPos())
force("AnchorToss")
local an = E.def.Attacks.AnchorToss
step(an.Tell + an.Flight * 0.55)
do
	local b = bossPos()
	local p = root.Position
	local mid = (b + p) / 2
	local side = flatDir(b, p):Cross(Vector3.new(0, 1, 0))
	snap("anchor", mid - side * 44 + Vector3.new(0, 18, 0), mid + Vector3.new(0, 6, 0))
end
step(3)

-- 6) phase two: the Shovel Meteor's huge shadow, armour cracked and gold
model:SetAttribute("Health", math.floor((model:GetAttribute("MaxHealth") or 1) * 0.49))
model:FindFirstChild("OnHit"):Fire(me, 1, false)
step(E.def.BreakTime + 0.5)
standAt(home + Vector3.new(24, 3, 30), home)
force("ShovelMeteor")
local mt = E.def.Attacks.ShovelMeteor
step(mt.Tell + mt.Up + mt.Fall * 0.7)
snap("meteor", home + Vector3.new(58, 46, 70), home + Vector3.new(0, 0, 0))
step(mt.Fall * 0.3 + 0.3)
closeUp("stuck", 24, 10, 3)

for _, e in ipairs(M.errors) do
	realPrint("ERROR " .. tostring(e))
end
