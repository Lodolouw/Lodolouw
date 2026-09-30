--!nocheck
-- Snapshots of Gridlock, the Final Beat for pictures: the real Final Beat
-- level (GridBuilder), the real BossService with his brain and moves and the
-- real BossClient drawing him (and the level's tiles), and a pretend player
-- (a blocky figure, for scale). At a few moments every part you'd see is
-- printed with the camera:
--   level    - the level from the runway, him asleep in the middle
--   attempt  - ATTEMPT 1: the grid lighting up from the middle on the beat
--   hopslam  - HOP SLAM: his red square, him flipping through the air
--   rows     - SPIKE ROWS marching out from him, a row a beat
--   bombs    - the SHIP's BOMB RUN down a lane of tiles
--   ufo      - UFO SLAM: the circle locked, the tractor beam
--   wave     - ZIG-ZAG: the WAVE's wall of light
--   pattern  - a TILE PATTERN: checkers spiking, the other half lit
--   drop     - THE DROP: every tile spiking but the jump pads
--   flip     - round 2: the world upside down, him dropping from the ceiling
--   complete - LEVEL COMPLETE!: he shatters into little cubes
--   luau gridlock_snaps.luau > gridlock_snaps.txt
--   python3 render_snaps.py gridlock_snaps.txt ../../Docs/gridlock_preview.png --cols 3 --title "GRIDLOCK, THE FINAL BEAT|FLOOR 6  -  THE FINAL BEAT|RECOMMENDED LV 90"
-- `-a poses` instead: close-ups of him (a model sheet), three across:
--   luau gridlock_snaps.luau -a poses > gridlock_poses.txt
--   python3 render_snaps.py gridlock_poses.txt ../../Docs/gridlock_poses.png --cols 3 --title ""
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

local arena = mount.require(mount.module("ServerScriptService/GridBuilder.lua")).Build()
local BeatGrid = mount.require(mount.module("ReplicatedStorage/BeatGrid.lua"))
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
local Profile = { RecordBossKill = function() return true end, AddPower = function() end }
local BS = mount.require(mount.module("ServerScriptService/BossService.lua"))
BS.Start(Combat, Profile)
local E = BS.Encounter(6)
local model = E.model
local def = E.def
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
	realPrint(string.format("BAR %s|%.3f|%d", awake and "Gridlock, the Final Beat" or "", hp, (model:GetAttribute("Phase") or 1)))
	realPrint("ENDSNAP")
end

-- a purple void, and the captions
realPrint("SKY 24,20,37|104,56,108")
local CAPTIONS = {
	level = "1  THE FINAL BEAT: HE SLEEPS IN THE MIDDLE",
	attempt = "2  ATTEMPT 1: THE GRID LIGHTS UP ON THE BEAT",
	hopslam = "3  HOP SLAM: GET OFF THE RED SQUARE",
	rows = "4  SPIKE ROWS MARCH OUT, A ROW A BEAT",
	bombs = "5  SHIP: A BOMB A BEAT DOWN THE LANE",
	ufo = "6  UFO SLAM: THE CIRCLE LOCKS ON",
	wave = "7  WAVE: A ZIG-ZAG WALL OF LIGHT",
	pattern = "8  THE LEVEL ITSELF: KEEP TO THE DARK TILES",
	drop = "9  THE DROP! STAND ON A JUMP PAD",
	flip = "10  GRAVITY FLIP: HE DROPS FROM THE CEILING",
	complete = "11  LEVEL COMPLETE! HE SHATTERS",
	asleep = "ASLEEP",
	peek = "HE'S SEEN YOU",
	roar = "ATTEMPT 1: THE ROAR",
	crouch = "HOP SLAM: CROUCHING",
	flipping = "HOP SLAM: THE FLIP",
	slam = "SLAM!",
	ship = "SHIP",
	ufoform = "UFO: TRACTOR BEAM",
	waveform = "WAVE",
	stunned = "STUNNED! HIT HIM!",
	ceiling = "UPSIDE DOWN ON THE CEILING",
	shatter = "LEVEL COMPLETE!",
}
for k, v in pairs(CAPTIONS) do
	realPrint("CAPTION " .. k .. " " .. v)
end

local HALF_Y = { Cube = 5, Ship = 2.6, Ufo = 2.6, Wave = 2.2 }
local function bossCenter()
	return E.pos + Vector3.new(0, HALF_Y[E.form or "Cube"] or 5, 0)
end
local function beatLen()
	return BeatGrid.beatLen(def.Bpm)
end
-- the moment of beat `x` of the move that's on (counted from its ActN)
local function actBeat(x)
	return BeatGrid.beatTime(E.beat0, def.Bpm, (model:GetAttribute("ActN") or 0) + x)
end
local function stepUntil(t)
	while M.now() < t do
		step(DT)
	end
end

-- take him over: his brain stopped, put where we say in `form` (the right
-- way up, or on the ceiling), aiming at the player
local function takeOver(pos, form, gravity, face)
	while model:GetAttribute("State") ~= "Fighting" do
		step(0.1)
	end
	E.token += 1
	E.contact = nil
	E.patterns = {}
	if form then
		E.form = form
		model:SetAttribute("Form", form)
		E.gravity = gravity or 1
		model:SetAttribute("Gravity", E.gravity)
	end
	if pos then
		local h = (E.form == "Cube" and E.gravity == -1) and (arena:GetAttribute("Ceiling") - def.Size) or def.Forms[E.form].Height
		local a = Vector3.new(pos.X, h, pos.Z)
		E.move = { kind = "Hold", t0 = M.now(), t1 = M.now() + 0.05, a = a, b = a, f = face or Vector3.new(1, 0, 0) }
		E.moveId = (model:GetAttribute("MoveId") or 0) + 1
		BeatGrid.writeMove(model, E.move, E.moveId)
		E.pos = Vector3.new(pos.X, E.floorY + h, pos.Z)
		E.facing = E.move.f
	end
	E.target, E.targetSince = me, M.now()
	return E.token
end
-- one of his moves, right now
local function force(name, pos, form, gravity, face)
	local token = takeOver(pos, form, gravity, face)
	local fn = E.boss.Attacks[name] or E.boss.Moves[name]
	M.task.spawn(function()
		fn(E, token)
	end)
	step(DT * 2)
end

-- a close look at his face from in front (a little to one side)
local function closeUp(name, dist, side, height)
	local c = bossCenter()
	local look = model:GetPivot().LookVector
	look = Vector3.new(look.X, 0, look.Z).Unit
	local sideV = look:Cross(Vector3.new(0, 1, 0))
	snap(name, c + look * (dist or 26) + sideV * (side or 10) + Vector3.new(0, height or 4, 0), c)
end

-- round 2: his brain back on at under half health (the break is his brain's)
local function roundTwo()
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

local START = C + Vector3.new(-16, 0, 0)
local EAST = Vector3.new(1, 0, 0)

if MODE == "poses" then
	standAt(C + Vector3.new(0, 3, 80), home)
	step(1)
	closeUp("asleep", 26, 10, 4)
	me:SetAttribute("SpireFloor", 6)
	standAt(home + Vector3.new(0, 3, 58), home)
	step(1)
	closeUp("peek", 26, -10, 4)
	-- ATTEMPT 1: the roar on beat 4
	standAt(home + Vector3.new(0, 3, 30), home)
	while model:GetAttribute("Action") ~= "Wake" do
		step(DT)
	end
	stepUntil(model:GetAttribute("ActionStart") + beatLen() * 4.25)
	closeUp("roar", 26, 10, 3)
	step(def.WakeTime)
	-- HOP SLAM: the crouch, the flip, the landing
	standAt(START + Vector3.new(24, 3, 0), START)
	force("HopSlam", START, "Cube", 1, EAST)
	stepUntil(actBeat(def.Attacks.HopSlam.Tell - 1) - 0.05)
	closeUp("crouch", 26, 10, 3)
	stepUntil(actBeat(def.Attacks.HopSlam.Tell - 0.62))
	do
		local c = bossCenter()
		snap("flipping", c + Vector3.new(4, 2, 30), c)
	end
	stepUntil(actBeat(def.Attacks.HopSlam.Tell) + 0.05)
	closeUp("slam", 26, -10, 4)
	step(3)
	-- the ship, the UFO (its beam), the wave
	standAt(START + Vector3.new(30, 3, 0), START)
	force("BombRun", START, "Ship", 1, EAST)
	stepUntil(actBeat(def.Attacks.BombRun.Tell - 1) - 0.1)
	do
		local c = bossCenter()
		snap("ship", c + Vector3.new(-6, 5, 18), c)
	end
	step(5)
	standAt(START + Vector3.new(20, 3, 0), START)
	force("UfoSlam", START, "Ufo", 1, EAST)
	stepUntil(actBeat(def.Attacks.UfoSlam.Lock) + 0.1)
	do
		local c = bossCenter()
		snap("ufoform", c + Vector3.new(10, -1, 22), c - Vector3.new(0, 5, 0))
	end
	step(5)
	standAt(START + Vector3.new(32, 3, 0), START)
	force("ZigZag", START, "Wave", 1, EAST)
	stepUntil(actBeat(def.Attacks.ZigZag.Tell) - 0.1)
	closeUp("waveform", 13, 8, 4)
	step(5)
	-- THE DROP, then STUNNED
	standAt(C + Vector3.new(0, 3, 30), C)
	force("Drop", C, "Cube", 1, Vector3.new(0, 0, 1))
	stepUntil(actBeat(def.Drop.Build + 0.5) + 0.2)
	step(0.8)
	closeUp("stunned", 26, 10, 5)
	step(4)
	-- round 2: upside down on the ceiling, hopping after you
	standAt(START + Vector3.new(0, 3, 30), START)
	takeOver(START, "Cube", -1, Vector3.new(0, 0, 1))
	step(1.5)
	force("CeilingDrop", START, "Cube", -1, Vector3.new(0, 0, 1))
	stepUntil(actBeat(0) - 0.05)
	do
		local c = bossCenter()
		snap("ceiling", c + Vector3.new(12, -20, 24), c)
	end
	step(5)
	-- LEVEL COMPLETE!
	takeOver(START, "Cube", 1, Vector3.new(0, 0, 1))
	standAt(START + Vector3.new(0, 3, 30), START)
	step(0.5)
	finish()
	step(0.95)
	do
		local c = E.pos + Vector3.new(0, 5, 0)
		snap("shatter", c + Vector3.new(10, 6, 34), c + Vector3.new(0, 2, 0))
	end
	for _, e in ipairs(M.errors) do
		realPrint("ERROR " .. tostring(e))
	end
	return
end

-- 1) the level from above the runway: him asleep in the middle
standAt(spawnPart.Position, home)
step(1)
snap("level", C + Vector3.new(-40, 36, 92), C + Vector3.new(0, 3, 0))

-- 2) ATTEMPT 1: the player walks up; the grid lights up a ring a beat
standAt(home + Vector3.new(0, 3, 34), home)
me:SetAttribute("SpireFloor", 6)
while model:GetAttribute("Action") ~= "Wake" do
	step(DT)
end
stepUntil(model:GetAttribute("ActionStart") + beatLen() * 4.2)
snap("attempt", C + Vector3.new(34, 30, 64), C + Vector3.new(0, 2, 0))
step(def.WakeTime)

-- 3) HOP SLAM: the square lit, him flipping through the air onto it
standAt(START + Vector3.new(24, 3, 4), START)
force("HopSlam", START, "Cube", 1, EAST)
stepUntil(actBeat(def.Attacks.HopSlam.Tell - 0.45))
snap("hopslam", START + Vector3.new(10, 18, 46), START + Vector3.new(14, 4, 0))
step(3)

-- 4) SPIKE ROWS: rows marching out from him along the lines
standAt(START + Vector3.new(14, 3, 10), START)
force("SpikeRows", START, "Cube", 1, EAST)
stepUntil(actBeat(def.Attacks.SpikeRows.Tell + 2) + 0.06)
snap("rows", START + Vector3.new(26, 36, 44), START + Vector3.new(0, 0, 2))
step(4)

-- 5) BOMB RUN: the ship over its lane, a bomb a beat
standAt(START + Vector3.new(26, 3, 6), START)
force("BombRun", START + Vector3.new(-8, 0, 0), "Ship", 1, EAST)
stepUntil(actBeat(def.Attacks.BombRun.Tell - 1 + 3) + 0.04)
do
	local c = bossCenter()
	snap("bombs", c + Vector3.new(-6, 10, 36), c + Vector3.new(4, -6, 0))
end
step(5)

-- 6) UFO SLAM: the circle locked, the beam down
standAt(START + Vector3.new(18, 3, 4), START)
force("UfoSlam", START, "Ufo", 1, EAST)
stepUntil(actBeat(def.Attacks.UfoSlam.Lock) + 0.12)
do
	local c = bossCenter()
	snap("ufo", c + Vector3.new(16, 6, 38), Vector3.new(c.X, E.floorY + 5, c.Z))
end
step(5)

-- 7) ZIG-ZAG: the wave zooming along, its wall of light behind it
standAt(START + Vector3.new(32, 3, 0), START)
force("ZigZag", START, "Wave", 1, EAST)
stepUntil(actBeat(def.Attacks.ZigZag.Tell + 2.6))
snap("wave", START + Vector3.new(20, 34, 46), START + Vector3.new(22, 0, 0))
step(5)

-- 8) TILE PATTERN: checkers (the rolls fixed so it picks them)
do
	local real = E.rng
	E.rng = { NextInteger = function() return 1 end, NextNumber = function() return 0.5 end }
	standAt(START + Vector3.new(28, 3, 12), START)
	force("TilePattern", START, "Cube", 1, EAST)
	E.rng = real
	stepUntil(actBeat(def.Attacks.TilePattern.Tell) + 0.08)
	snap("pattern", C + Vector3.new(-30, 52, 74), C + Vector3.new(0, 0, 4))
	step(4)
end

-- 9) THE DROP: every tile spiking but the jump pads (the player on one)
do
	local pads = BeatGrid.pads(BeatGrid.grid(C, arena:GetAttribute("Tiles"), arena:GetAttribute("TileSize")))
	local pad = BeatGrid.tileCenter(BeatGrid.grid(C, arena:GetAttribute("Tiles"), arena:GetAttribute("TileSize")), pads[6][1], pads[6][2])
	standAt(pad + Vector3.new(0, 3, 0), C)
	force("Drop", C, "Cube", 1, Vector3.new(0, 0, 1))
	stepUntil(actBeat(def.Drop.Build) + 0.06)
	snap("drop", C + Vector3.new(-54, 50, 98), C + Vector3.new(0, 4, 4))
	step(4)
end

-- 10) round 2: GRAVITY FLIP! (and the drop it starts with) - then a
-- CEILING DROP (the line down to his square)
roundTwo()
step(def.BreakTime + 0.5)
do
	local waited = 0
	while waited < 20 do
		local a = model:GetAttribute("Action")
		if a ~= "Break" and a ~= "Drop" and a ~= "Stunned" then
			break
		end
		step(0.1)
		waited += 0.1
	end
end
standAt(START + Vector3.new(10, 3, 8), START)
takeOver(START, "Cube", -1, EAST)
step(1.6)
force("CeilingDrop", START, "Cube", -1, EAST)
stepUntil(actBeat(def.Attacks.CeilingDrop.Lock) + 0.15)
snap("flip", C + Vector3.new(34, 8, 70), START + Vector3.new(4, 22, 0))
step(5)

-- 11) LEVEL COMPLETE!
takeOver(START, "Cube", 1, Vector3.new(0, 0, 1))
standAt(START + Vector3.new(0, 3, 30), START)
step(2)
finish()
step(1.0)
do
	local c = E.pos + Vector3.new(0, 5, 0)
	snap("complete", c + Vector3.new(14, 10, 44), c + Vector3.new(0, 3, 0))
end
for _, e in ipairs(M.errors) do
	realPrint("ERROR " .. tostring(e))
end
