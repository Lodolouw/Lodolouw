--!nocheck
-- Snapshots of Kaze for pictures: the real Rooftop Dojo (DojoBuilder), the
-- real BossService with his brain and moves and the real BossClient drawing
-- him, and a pretend player (a blocky figure, for scale). At a few moments
-- every part you'd see is printed with the camera:
--   dojo     - the dojo from the gate at sunset, Kaze meditating in the middle
--   fight    - ROUND 1... FIGHT!: he drops into his stance
--   blast    - KAZE-BLAST!: the ball of ki rolling along its lane at you
--   dragon   - RISING DRAGON!: up in the air, spinning, fist high
--   tornado  - TORNADO KICK!: spinning along the locked lane
--   super    - SUPER!: the red fan follows you; you run behind a pillar
--   beam     - the beam sweeps round - and stops at your pillar
--   tired    - out of cancels: TIRED! HIT HIM!
--   luau kaze_snaps.luau > kaze_snaps.txt
--   python3 render_snaps.py kaze_snaps.txt ../../Docs/kaze_preview.png --title "KAZE|FLOOR 4  -  THE ROOFTOP DOJO|RECOMMENDED LV 60"
-- `-a poses` instead: close-ups of him (a model sheet), three across:
--   luau kaze_snaps.luau -a poses > kaze_poses.txt
--   python3 render_snaps.py kaze_poses.txt ../../Docs/kaze_poses.png --cols 3 --title ""
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

local arena = mount.require(mount.module("ServerScriptService/DojoBuilder.lua")).Build()
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
local Profile = { RecordBossKill = function() return true end, AddPower = function() end }
local BS = mount.require(mount.module("ServerScriptService/BossService.lua"))
BS.Start(Combat, Profile)
local E = BS.Encounter(4)
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
	realPrint(string.format("BAR %s|%.3f|%d", awake and "Kaze, the Headband Hero" or "", hp, (model:GetAttribute("Phase") or 1)))
	realPrint("ENDSNAP")
end

-- the sunset sky, and the captions
realPrint("SKY 246,117,122|254,231,97")
local CAPTIONS = {
	dojo = "1  THE ROOFTOP DOJO: HE MEDITATES",
	fight = "2  ROUND 1... FIGHT!",
	blast = "3  KAZE-BLAST! JUMP IT OR ROLL IT",
	dragon = "4  RISING DRAGON! BACK OFF, THEN PUNISH",
	tornado = "5  TORNADO KICK! ROLL THROUGH HIM",
	super = "6  SUPER! RUN BEHIND A PILLAR",
	beam = "7  THE BEAM STOPS AT YOUR PILLAR",
	tired = "8  OUT OF CANCELS: TIRED! HIT HIM!",
	meditate = "ASLEEP: MEDITATING",
	stance = "HIS STANCE",
	jab = "JAB",
	straight = "STRAIGHT",
	heavy = "HEAVY: HYAH!",
	cup = "KAZE-BLAST: CHARGING",
	push = "KAZE-BLAST: LET GO",
	dragonup = "RISING DRAGON",
	spin = "TORNADO KICK",
	focus = "KI FOCUS: HAAAA...",
	pant = "TIRED",
	dazed = "STAGGERED",
	round2 = "ROUND 2: GI TORN",
	ko = "K.O.!",
	band = "THE HEADBAND FLOATS AWAY",
}
for k, v in pairs(CAPTIONS) do
	realPrint("CAPTION " .. k .. " " .. v)
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
local function force(name, opts)
	while model:GetAttribute("State") ~= "Fighting" do
		step(0.1)
	end
	E.token += 1
	local token = E.token
	E.target, E.targetSince = me, M.now()
	E.motion, E.sweep, E.arc = nil, nil, nil
	E.cancels = 0 -- (no cancels: each move exactly itself)
	M.task.spawn(function()
		E.boss.Attacks[name](E, token, opts or {})
	end)
end
local function hold(fn)
	-- run something with his brain stopped
	E.token += 1
	local token = E.token
	M.task.spawn(function()
		fn(token)
	end)
end

-- a close look at him from in front (a little to one side), at his chest
local function closeUp(name, dist, side, height)
	local fx = workspace:FindFirstChild("BossFX")
	local bodyModel = fx and fx:FindFirstChild("KazeBody")
	local chest = bodyModel and bodyModel:FindFirstChild("Gi")
	local b = bossPos()
	local look = model:GetPivot().LookVector
	look = Vector3.new(look.X, 0, look.Z).Unit
	local at = chest and chest.Position or (b + Vector3.new(0, 6, 0))
	local sideV = look:Cross(Vector3.new(0, 1, 0))
	local d = (dist or 20) * ((MODE == "poses") and 0.68 or 1)
	local sd = (side or 8) * ((MODE == "poses") and 0.68 or 1)
	snap(name, at + look * d + sideV * sd + Vector3.new(0, height or 1, 0), at + Vector3.new(0, -0.5, 0))
end

if MODE == "poses" then
	standAt(home + Vector3.new(0, 3, 58), home)
	step(1)
	closeUp("meditate", 17, 7, 2)
	me:SetAttribute("SpireFloor", 4)
	standAt(home + Vector3.new(0, 3, 40), home)
	step(E.def.WakeTime + 0.2)
	E.chase, E.track = false, false
	standAt(home + Vector3.new(0, 3, 50), home)
	hold(function() end)
	E.facing = Vector3.new(0, 0, 1)
	step(0.6)
	closeUp("stance", 18, 8, 1)
	local function pose(move, t, name, dist, side, height, opts)
		E.pos, E.facing = home, Vector3.new(0, 0, 1)
		force(move, opts)
		step(t)
		closeUp(name, dist, side, height)
		step(4)
	end
	local ps = E.def.Attacks.PunchString
	pose("PunchString", ps.Tells[1] + 0.02, "jab", 18, -8, 1, { noCancel = true })
	pose("PunchString", ps.Tells[1] + ps.Tells[2] + 0.02, "straight", 18, 8, 1, { noCancel = true })
	pose("PunchString", ps.Tells[1] + ps.Tells[2] + ps.Tells[3] + 0.04, "heavy", 18, 8, 1, { noCancel = true })
	local kb = E.def.Attacks.KazeBlast
	pose("KazeBlast", 0.8, "cup", 18, 9, 1, { hold = 1.0 })
	pose("KazeBlast", kb.Tell + 0.06, "push", 18, 9, 1)
	local rd = E.def.Attacks.RisingDragon
	pose("RisingDragon", rd.Tell + 0.22, "dragonup", 26, 8, 4)
	local tk = E.def.Attacks.TornadoKick
	pose("TornadoKick", tk.Tell + 0.3, "spin", 22, 9, 1)
	pose("KiFocus", 0.8, "focus", 18, 8, 1)
	hold(function(token)
		E.boss._tired(E, token)
	end)
	step(0.8)
	closeUp("pant", 17, 8, 1)
	hold(function(token)
		E.boss._stagger(E, token)
	end)
	step(0.35)
	closeUp("dazed", 18, 8, 1)
	step(1.5)
	-- ROUND 2
	model:SetAttribute("Health", math.floor((model:GetAttribute("MaxHealth") or 1) * 0.49))
	model:FindFirstChild("OnHit"):Fire(me, 1, false)
	step(E.def.BreakTime * 0.35 + 0.4)
	closeUp("round2", 18, 8, 1)
	step(E.def.BreakTime)
	-- K.O.
	model:SetAttribute("Health", 0)
	model:FindFirstChild("OnHit"):Fire(me, 1, true)
	step(2.4)
	closeUp("ko", 16, 10, 5)
	step(1.0)
	do
		local b = bossPos()
		snap("band", b + Vector3.new(-10, 9, 26), b + Vector3.new(6, 6, 2))
	end
	for _, e in ipairs(M.errors) do
		realPrint("ERROR " .. tostring(e))
	end
	return
end

-- 1) the dojo from the gate at sunset: Kaze meditating in the middle
standAt(spawnPart.Position, home)
step(1)
snap("dojo", home + Vector3.new(38, 34, 110), home + Vector3.new(0, 2, 0))

-- 2) he wakes (the player walks up close): ROUND 1... FIGHT!
local stand = home + Vector3.new(0, 3, 30)
standAt(stand, home)
me:SetAttribute("SpireFloor", 4)
step(E.def.WakeTime - 0.3)
snap("fight", home + Vector3.new(-9, 7, 17), home + Vector3.new(0, 6, 0))
step(0.6)
E.chase = false

-- 3) a charged Kaze-Blast: the ball rolling at the player
E.pos, E.facing = home, Vector3.new(0, 0, 1)
standAt(home + Vector3.new(4, 3, 40), home)
force("KazeBlast", { hold = 0.9 })
local kb = E.def.Attacks.KazeBlast
step(0.9 + kb.Tell + 0.35)
do
	local b = bossPos()
	snap("blast", b + Vector3.new(-24, 10, 6), b + Vector3.new(0, 3, 17))
end
step(2.5)

-- 4) a Rising Dragon: up in the air, spinning
E.pos, E.facing = home + Vector3.new(0, 0, -10), Vector3.new(0, 0, 1)
standAt(home + Vector3.new(3, 3, 1), home)
force("RisingDragon", { hold = 0.8 })
local rd = E.def.Attacks.RisingDragon
step(0.8 + rd.Tell + 0.25)
do
	local b = bossPos()
	snap("dragon", b + Vector3.new(26, 10, 18), b + Vector3.new(0, 11, 0))
end
step(3)

-- 5) a Tornado Kick along its lane
E.pos, E.facing = home + Vector3.new(0, 0, -20), Vector3.new(0, 0, 1)
standAt(home + Vector3.new(0, 3, 20), home)
force("TornadoKick", {})
local tk = E.def.Attacks.TornadoKick
step(tk.Tell + 0.35)
do
	local b = bossPos()
	snap("tornado", b + Vector3.new(30, 16, 14), b + Vector3.new(0, 3, 12))
end
step(3)

-- 6) the Super: the fan following the player, who runs for a pillar
E.ki = E.def.Ki.Bar * E.def.Ki.Bars
local pl = E.pillars[4]
local out = Vector3.new(pl.center.X - home.X, 0, pl.center.Z - home.Z).Unit
standAt(home + Vector3.new(14, 3, 18), home)
force("Super", {})
local sa = E.def.Attacks.Super
step(sa.Leap + 0.35)
-- (the fan follows the player, running for the pillar)
standAt(home + Vector3.new(22, 3, 20), home)
step(0.05)
snap("super", home + Vector3.new(-46, 70, 92), home + Vector3.new(8, 0, 14))
standAt(pl.center + out * (pl.radius + 2.2) + Vector3.new(0, 3, 0), home)
step(sa.Tell - sa.Leap - 0.4)
-- 7) the beam sweeping round - stopped at the player's pillar (seen from
-- behind it, looking back at him)
step(sa.SweepTime * 0.5)
local sideV = Vector3.new(-out.Z, 0, out.X)
snap("beam", pl.center + out * 24 + sideV * 7 + Vector3.new(0, 26, 0), pl.center - out * 12)
step(sa.SweepTime * 0.5 + 0.8)

-- 8) out of cancels: tired
hold(function(token)
	E.boss._tired(E, token)
end)
standAt(bossPos() + Vector3.new(6, 3, 8), bossPos())
step(0.9)
closeUp("tired", 19, 9, 2)

for _, e in ipairs(M.errors) do
	realPrint("ERROR " .. tostring(e))
end
