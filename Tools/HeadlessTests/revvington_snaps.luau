--!nocheck
-- Snapshots of Speedy Revvington for pictures: the real Piston Speedway
-- (SpeedwayBuilder), the real BossService with his brain and moves and the
-- real BossClient drawing him, and a pretend player (a blocky figure, for
-- scale). At a few moments every part you'd see is printed with the camera:
--   track   - the speedway from the tunnel, him parked on the start line
--   go      - 3... 2... 1... GO!: the start lights green, tyre smoke
--   charge  - CHARGE: revving, the red lane locked on you
--   crash   - a charge into the tyre wall: CRASH! dizzy, bonnet up
--   whip    - TAIL WHIP: the half-circle on your side, a big skid
--   wheelie - WHEELIE SLAM: up on his back wheels, the red circle
--   honk    - HONK!!: cheeks empty, sound waves across the cone
--   ring    - TURBO: the BURNOUT RING of fire round you
--   finish  - FINISH!: a wheel rolling away, X eyes
--   luau revvington_snaps.luau > revvington_snaps.txt
--   python3 render_snaps.py revvington_snaps.txt ../../Docs/revvington_preview.png --title "SPEEDY REVVINGTON|FLOOR 5  -  PISTON SPEEDWAY|RECOMMENDED LV 75"
-- `-a poses` instead: close-ups of him (a model sheet), three across:
--   luau revvington_snaps.luau -a poses > revvington_poses.txt
--   python3 render_snaps.py revvington_poses.txt ../../Docs/revvington_poses.png --cols 3 --title ""
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

local arena = mount.require(mount.module("ServerScriptService/SpeedwayBuilder.lua")).Build()
local CarPath = mount.require(mount.module("ReplicatedStorage/CarPath.lua"))
M.run(1)
local spawnPart = CollectionService:GetTagged("ArenaSpawn")[1]
local C = arena:GetAttribute("Center")

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
local E = BS.Encounter(5)
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
	realPrint(string.format("BAR %s|%.3f|%d", awake and "Speedy Revvington, King of the Speedway" or "", hp, (model:GetAttribute("Phase") or 1)))
	realPrint("ENDSNAP")
end

-- a hot desert afternoon, and the captions
realPrint("SKY 0,153,219|234,212,170")
local CAPTIONS = {
	track = "1  PISTON SPEEDWAY: HE WAITS ON THE LINE",
	go = "2  3... 2... 1... GO!",
	charge = "3  CHARGE! GET OUT OF THE LANE",
	crash = "4  LURE HIM INTO THE WALL: CRASH!",
	whip = "5  TAIL WHIP: MIND THE HALF-CIRCLE",
	wheelie = "6  WHEELIE SLAM: BACK OFF, JUMP THE RING",
	honk = "7  HONK!! (DON'T STAND IN FRONT)",
	ring = "8  TURBO: THE BURNOUT RING OF FIRE",
	finish = "9  FINISH! YOUR TIME ON THE SCREEN",
	parked = "PARKED: BORED",
	grin = "A CHALLENGER!",
	rev = "CHARGE: REVVING",
	flatout = "FLAT OUT",
	brake = "BRAKING: WHOA!",
	dizzy = "CRASHED: DIZZY",
	up = "WHEELIE",
	squash = "SLAM!",
	puff = "HONK: PUFFING UP",
	blast = "HONK!!",
	pipes = "BACKFIRE: PIPES GLOWING",
	lean = "SIDE BUMP: LEANING AWAY",
	donut = "DONUTS: WOO-HOO!",
	turbo = "TURBO!",
	xeyes = "FINISH!",
}
for k, v in pairs(CAPTIONS) do
	realPrint("CAPTION " .. k .. " " .. v)
end

local EAST = Vector3.new(1, 0, 0)
local function bossPos()
	local p = model:GetPivot().Position
	return Vector3.new(p.X, home.Y, p.Z)
end

-- take him over: his brain stopped, put where we say (a segment standing
-- still there), aiming at the player
local function takeOver(pos, dir)
	while model:GetAttribute("State") ~= "Fighting" do
		step(0.1)
	end
	E.token += 1
	E.contact, E.wheelie = nil, false
	if pos then
		E.pos, E.facing = Vector3.new(pos.X, E.floorY, pos.Z), dir
		E.seg = { kind = "Spin", t0 = M.now(), dur = 0.05, a = E.pos, b = Vector3.new(CarPath.angleOf(dir), 0, 0), c = Vector3.new(), ease = "lin" }
		CarPath.write(model, E.seg, (model:GetAttribute("SegId") or 0) + 1)
		E.segId = model:GetAttribute("SegId")
	end
	E.target, E.targetSince = me, M.now()
	return E.token
end
-- one of his moves, right now
local function force(name, pos, dir)
	local token = takeOver(pos, dir)
	M.task.spawn(function()
		E.boss.Attacks[name](E, token)
	end)
end

-- a close look at his face from in front (a little to one side)
local function closeUp(name, dist, side, height)
	local b = bossPos()
	local look = model:GetPivot().LookVector
	look = Vector3.new(look.X, 0, look.Z).Unit
	local at = b + Vector3.new(0, 3.5, 0)
	local sideV = look:Cross(Vector3.new(0, 1, 0))
	snap(name, at + look * (dist or 24) + sideV * (side or 12) + Vector3.new(0, height or 5, 0), at)
end

-- TURBO: his brain back on at under half health (the break is his brain's)
local function turbo()
	model:SetAttribute("Health", math.floor((model:GetAttribute("MaxHealth") or 1) * 0.49))
	local token = takeOver(nil)
	M.task.spawn(function()
		E.boss.brain(E, token)
	end)
end

local function finish()
	model:SetAttribute("Health", 0)
	model:FindFirstChild("OnHit"):Fire(me, 1, true)
end

if MODE == "poses" then
	local spot = C + Vector3.new(-10, 0, -46)
	local function ahead(d)
		return spot + EAST * d + Vector3.new(0, 3, 0)
	end
	standAt(home + Vector3.new(70, 3, 0), home)
	step(1)
	closeUp("parked", 24, 12, 5)
	me:SetAttribute("SpireFloor", 5)
	standAt(home + Vector3.new(30, 3, 0), home)
	step(1.0)
	closeUp("grin", 24, -12, 5)
	step(E.def.WakeTime)
	local function pose(move, t, name, playerAt, dist, side, height)
		standAt(playerAt or ahead(30), spot)
		force(move, spot, EAST)
		step(t)
		closeUp(name, dist, side, height)
		step(4)
	end
	local ch = E.def.Attacks.Charge
	pose("Charge", 0.7, "rev", ahead(40), 24, 12, 5)
	pose("Charge", ch.Tell[1] + 0.25, "flatout", ahead(40), 26, 14, 7)
	pose("Charge", ch.Tell[1] + (40 + ch.Overshoot) / ch.Speed[1] + 0.2, "brake", ahead(40), 24, -12, 6)
	-- the crash: into the wall round the east turn
	do
		local wallSpot = C + Vector3.new(80, 0, 0)
		standAt(C + Vector3.new(110, 3, 0), wallSpot)
		force("Charge", wallSpot, EAST)
		step(ch.Tell[1] + 43 / ch.Speed[1] + 0.7)
		local b = bossPos()
		snap("dizzy", b + Vector3.new(17, 12, 9), b + Vector3.new(2, 3.5, 0))
		step(4)
	end
	local ws = E.def.Attacks.WheelieSlam
	pose("WheelieSlam", ws.Tell * 0.8, "up", ahead(12), 26, -14, 5)
	pose("WheelieSlam", ws.Tell + 0.05, "squash", ahead(12), 24, 12, 5)
	local hk = E.def.Attacks.Honk
	pose("Honk", hk.Tell * 0.85, "puff", ahead(14), 22, 10, 4)
	pose("Honk", hk.Tell + 0.12, "blast", ahead(14), 22, -10, 4)
	local bf = E.def.Attacks.Backfire
	do
		standAt(spot - EAST * 12 + Vector3.new(0, 3, 0), spot)
		force("Backfire", spot, EAST)
		step(bf.Tell * 0.9)
		local b = bossPos()
		snap("pipes", b + Vector3.new(-20, 7, 12), b + Vector3.new(-4, 2, 0))
		step(4)
	end
	local sb = E.def.Attacks.SideBump
	pose("SideBump", sb.Tell * 0.9, "lean", spot + Vector3.new(0, 3, 9), 24, 12, 5)
	pose("Donuts", 1.0, "donut", ahead(40), 26, 12, 7)
	-- TURBO!
	turbo()
	step(E.def.BreakTime * 0.35 + 0.35)
	closeUp("turbo", 26, 12, 6)
	step(E.def.BreakTime)
	-- FINISH!
	takeOver(spot, EAST)
	standAt(ahead(30), spot)
	step(0.5)
	finish()
	step(2.95)
	closeUp("xeyes", 24, -12, 6)
	for _, e in ipairs(M.errors) do
		realPrint("ERROR " .. tostring(e))
	end
	return
end

-- 1) the speedway from the tunnel: him parked on the start line
standAt(spawnPart.Position, home)
step(1)
snap("track", C + Vector3.new(-62, 46, -104), C + Vector3.new(0, 0, 30))

-- 2) the player walks up: 3... 2... 1... GO!
standAt(home + Vector3.new(30, 3, 0), home)
me:SetAttribute("SpireFloor", 5)
while model:GetAttribute("Action") ~= "Wake" do
	step(DT)
end
local wokeAt = model:GetAttribute("ActionStart")
while M.now() < wokeAt + E.def.WakeTime - 0.3 + 0.15 do
	step(DT)
end
snap("go", home + Vector3.new(26, 10, -14), home + Vector3.new(0, 5, 0))
step(0.8)

-- 3) a charge: revving, the lane locked on the player
local ch = E.def.Attacks.Charge
local start = C + Vector3.new(-40, 0, 40)
standAt(start + Vector3.new(42, 3, 3), start)
force("Charge", start, EAST)
step(ch.Tell[1] * ch.Lock + 0.2)
snap("charge", start + Vector3.new(62, 13, 14), start + Vector3.new(14, 0, 0))
step(4)

-- 4) into the tyre wall
local wallSpot = C + Vector3.new(20, 0, 22)
standAt(C + Vector3.new(20, 3, 50), wallSpot)
force("Charge", wallSpot, Vector3.new(0, 0, 1))
step(ch.Tell[1] + 31 / ch.Speed[1] + 0.55)
do
	local b = bossPos()
	snap("crash", b + Vector3.new(22, 10, 7), b + Vector3.new(0, 3, 3))
end
step(4)

-- 5) a tail whip: the half-circle on the player's side, the skid
local tw = E.def.Attacks.TailWhip
local whipFrom = C + Vector3.new(-34, 0, -38)
standAt(C + Vector3.new(0, 3, -38), whipFrom)
force("TailWhip", whipFrom, EAST)
step(tw.Tell + 34 / tw.Speed + 0.12)
do
	local b = bossPos()
	snap("whip", b + Vector3.new(-16, 34, 34), b + Vector3.new(2, 0, 0))
end
step(4)

-- 6) a wheelie slam: up on his back wheels
local ws = E.def.Attacks.WheelieSlam
local slamAt = C + Vector3.new(-20, 0, 0)
standAt(slamAt + Vector3.new(13, 3, 2), slamAt)
force("WheelieSlam", slamAt, EAST)
step(ws.Tell * 0.8)
snap("wheelie", slamAt + Vector3.new(14, 9, 28), slamAt + Vector3.new(4, 4, 0))
step(4)

-- 7) a honk: the sound waves across the cone
local hk = E.def.Attacks.Honk
standAt(slamAt + Vector3.new(15, 3, -3), slamAt)
force("Honk", slamAt, EAST)
step(hk.Tell + 0.2)
snap("honk", slamAt + Vector3.new(-10, 16, 30), slamAt + Vector3.new(14, 0, 0))
step(3)

-- 8) TURBO, then the burnout ring of fire round the player
turbo()
step(E.def.BreakTime + 0.3)
local br = E.def.Attacks.BurnoutRing
local ringMid = C + Vector3.new(0, 0, 0)
standAt(ringMid + Vector3.new(0, 3, 0), ringMid - EAST * 30)
force("BurnoutRing", ringMid - EAST * 34, EAST)
do
	local waited = 0
	while waited < 6 do
		local seg = E.seg
		if seg and seg.kind == "Arc" and M.now() >= seg.t0 + seg.dur * 0.8 then
			break
		end
		step(DT)
		waited += DT
	end
end
snap("ring", ringMid + Vector3.new(-36, 52, 44), ringMid + Vector3.new(0, 0, 2))
step(4)

-- 9) FINISH!
takeOver(slamAt, EAST)
standAt(slamAt + Vector3.new(28, 3, 0), slamAt)
step(0.5)
finish()
step(2.9)
do
	local b = bossPos()
	snap("finish", b + Vector3.new(22, 10, -20), b + Vector3.new(-2, 2, -2))
end

for _, e in ipairs(M.errors) do
	realPrint("ERROR " .. tostring(e))
end
