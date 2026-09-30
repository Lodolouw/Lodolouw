--!nocheck
-- Snapshots of Tuber (and THE BRUTE) for pictures: the real Sunken Dunes
-- (DunesBuilder), the real BossService with his brain and moves and the real
-- BossClient drawing him (his cactus mess, the flying cacti, the audience),
-- and a pretend player (a blocky figure, for scale). At a few moments every
-- part you'd see is printed with the camera:
--   dunes    - the cactus desert from the gate, Tuber asleep in his garden
--   hi       - he pops up and waves
--   bonk     - WOBBLE BONK: the red wedge, him leaning back
--   topple   - CLUMSY TOPPLE: timber!
--   split    - SPLIT!: three buddies, their lanes, one spin-dashing
--   stomp    - BOUNCE STOMP: up in the air over the red circle
--   build    - THE POWER-UP: the cacti flying in, the golem slamming together
--              (the game's own camera shot at that moment)
--   watch    - THE DESERT COMES TO WATCH: the camera's long look at a camel
--              walking up onto its ledge (the game's own shot, zoomed in)
--   brute    - THE BRUTE, THE CACTUS KING: crowned, roaring, his bar filling
--   walls    - a cactus wall (its weak spot glowing) and needle turrets
--   herd     - SONIC BALL HERD: spiky balls rolling in, bouncing
--   rain     - DESERT RAIN: red circles, cactus balls falling
--   lance    - SPINE LANCE: the line locked, the spike flying
--   crumble  - the end: he crumbles; tiny Tuber waddles off
--   luau tuber_snaps.luau > tuber_snaps.txt
--   python3 render_snaps.py tuber_snaps.txt ../../Docs/tuber_preview.png --cols 3 --title "TUBER|FLOOR 2  -  THE SUNKEN DUNES|RECOMMENDED LV 30"
-- `-a poses` instead: close-ups of him (a model sheet), then the audience (a
-- camel, a meerkat, a vulture, a lizard), three across:
--   luau tuber_snaps.luau -a poses > tuber_poses.txt
--   python3 render_snaps.py tuber_poses.txt ../../Docs/tuber_poses.png --cols 3 --title ""
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

local arena = mount.require(mount.module("ServerScriptService/DunesBuilder.lua")).Build()
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
-- (CombatClient's cutscene event: the power-up's camera shots, kept so a
-- picture can be taken from exactly where the game's camera is)
local cutShot = nil
local cut = Instance.new("BindableEvent")
cut.Name = "CombatCutscene"
cut.Parent = scripts
cut.Event:Connect(function(kind, cf, fov)
	cutShot = (kind == "Shot") and { cf = cf, fov = fov } or nil
end)
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
for _, h in ipairs(CollectionService:GetTagged("BossHome")) do
	if h:GetAttribute("Floor") ~= 2 then
		CollectionService:RemoveTag(h, "BossHome")
	end
end
local BS = mount.require(mount.module("ServerScriptService/BossService.lua"))
BS.Start(Combat, Profile)
local E = BS.Encounter(2)
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
local function stepUntil(t)
	while M.now() < t do
		step(DT)
	end
end

local function esc(s)
	return (string.gsub(tostring(s), '[%c"\\|]', ""))
end
-- (his bar, as his body file draws it - BossBodies/Tuber's barLook: round
-- 1's bar; empty through the power-up until THE BRUTE is named at 7.2s,
-- then his own bar filling up)
local T_ROAR = 7.2
local function barNow()
	local max = math.max(model:GetAttribute("MaxHealth") or 1, 1)
	local hp = model:GetAttribute("Health") or max
	local line = math.max(1, math.floor(max * def.PhaseAt))
	if (model:GetAttribute("Phase") or 1) < 2 then
		return def.Name, math.clamp((hp - line) / math.max(max - line, 1), 0, 1)
	end
	local share = math.clamp(hp / line, 0, 1)
	if model:GetAttribute("Action") == "Break" then
		local t = M.now() - (model:GetAttribute("ActionStart") or M.now())
		if t < T_ROAR then
			return def.Name, 0
		end
		local u = math.clamp((t - T_ROAR) / 1.6, 0, 1)
		share = math.min(share, u * u * (3 - 2 * u))
	end
	return def.Round2Name, share
end
local function snap(name, eye, look, fov)
	cam.CFrame = CFrame.lookAt(eye, look)
	realPrint(string.format("SNAP %s %.3f %.3f %.3f %.3f %.3f %.3f%s", name, eye.X, eye.Y, eye.Z, look.X, look.Y, look.Z,
		fov and string.format(" %.2f", fov) or ""))
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
	local state = model:GetAttribute("State")
	local awake = state == "Waking" or state == "Fighting" or state == "Transition"
	local barName, share = barNow()
	realPrint(string.format("BAR %s|%.3f|%d", awake and barName or "", share, model:GetAttribute("Phase") or 1))
	realPrint("ENDSNAP")
end

-- a hot afternoon sky, and the captions
realPrint("SKY 0,153,219|234,212,170")
local CAPTIONS = {
	dunes = "1  THE SUNKEN DUNES: TUBER NAPS IN HIS GARDEN",
	hi = "2  HE POPS UP: HI THERE!",
	bonk = "3  WOBBLE BONK: STEP OUT OF THE WEDGE",
	topple = "4  CLUMSY TOPPLE: TIMBER! (THEN FREE HITS)",
	split = "5  SPLIT! THREE BUDDIES SPIN-DASH AT YOU",
	stomp = "6  BOUNCE STOMP: OFF THE CIRCLE",
	build = "7  THE POWER-UP: THE DESERT FLIES TO HIM",
	watch = "8  THE DESERT COMES TO WATCH",
	brute = "9  THE BRUTE, THE CACTUS KING",
	walls = "10  CACTUS WALLS AND NEEDLE TURRETS",
	herd = "11  BALL HERD: JUMP OR ROLL",
	rain = "12  DESERT RAIN: GET OFF THE CIRCLES",
	lance = "13  SPINE LANCE: DODGE LATE",
	crumble = "14  HE CRUMBLES... TINY TUBER STOMPS OFF",
	asleep = "ASLEEP IN HIS GARDEN",
	wave = "HI THERE!",
	achoo = "ACHOO!",
	buddies = "SPLIT: THREE BUDDIES",
	dizzy = "DIZZY: HIT THEM!",
	toppled = "TOPPLED: HIT HIM!",
	golem = "THE BRUTE",
	hop = "ROOT HOP: AWAY FROM YOU",
	cornered = "CORNERED! HIT HIM!",
	stunned = "OUT OF CACTUS: STUNNED",
	roar = "RAGE!",
	charge = "SPINE LANCE: CHARGING",
	tiny = "TINY TUBER: HMPH!",
	animals = "THE AUDIENCE: A CAMEL",
	meerkat = "A MEERKAT",
	vulture = "A VULTURE",
	lizard = "A LIZARD",
}
for k, v in pairs(CAPTIONS) do
	realPrint("CAPTION " .. k .. " " .. v)
end

-- take him over: his brain stopped, his mess swept away, put where we say
-- in his form, aiming at the player
local function takeOver(pos, form, face)
	while model:GetAttribute("State") ~= "Fighting" do
		step(0.1)
	end
	E.token += 1
	E.boss._tidy(E, "Gone")
	E.waves, E.puddles = {}, {}
	if form then
		E.boss._setForm(E, form)
	end
	if pos then
		E.pos = Vector3.new(pos.X, E.floorY, pos.Z)
		E.facing = face or Vector3.new(1, 0, 0)
	end
	E.target, E.targetSince = me, M.now()
	step(DT * 2)
	return E.token
end
local function force(name, pos, form, face)
	local token = takeOver(pos, form, face)
	local fn = E.boss.Attacks[name] or E.boss.Moves[name]
	M.task.spawn(function()
		fn(E, token)
	end)
	step(DT * 2)
	return model:GetAttribute("ActionStart") or M.now()
end
local function snapShot(name)
	assert(cutShot, "no camera shot to take a picture from")
	local cf = cutShot.cf
	snap(name, cf.Position, cf.Position + cf.LookVector * 100, cutShot.fov)
end
local function bossAt(h)
	return E.pos + Vector3.new(0, h or 5, 0)
end
local function closeUp(name, dist, side, height, lookH)
	local c = bossAt(lookH or 5)
	local look = model:GetPivot().LookVector
	look = Vector3.new(look.X, 0, look.Z).Unit
	local sideV = look:Cross(Vector3.new(0, 1, 0))
	snap(name, c + look * (dist or 26) + sideV * (side or 10) + Vector3.new(0, height or 4, 0), c)
end
-- round 2 for real: his first bar punched away, the whole power-up
local function powerUp()
	local max = model:GetAttribute("MaxHealth") or 1
	model:SetAttribute("Health", math.floor(max * def.PhaseAt))
	model:FindFirstChild("OnHit"):Fire(me, 1, false)
end
local function finish()
	model:SetAttribute("Health", 0)
	model:FindFirstChild("OnHit"):Fire(me, 1, true)
end

local START = C + Vector3.new(-20, 0, 6)
local EAST = Vector3.new(1, 0, 0)

if MODE == "poses" then
	standAt(C + Vector3.new(0, 3, 90), home)
	step(1)
	closeUp("asleep", 18, 6, 3, 2)
	me:SetAttribute("SpireFloor", 2)
	standAt(home + Vector3.new(0, 3, 30), home)
	while model:GetAttribute("Action") ~= "Wake" do
		step(DT)
	end
	stepUntil(model:GetAttribute("ActionStart") + 2.2)
	closeUp("wave", 20, 7, 3, 5)
	step(def.WakeTime)
	standAt(START + Vector3.new(10, 3, 0), START)
	local t0 = force("Sneeze", START, "Stack", EAST)
	stepUntil(t0 + def.Attacks.Sneeze.Tell + 0.12)
	closeUp("achoo", 22, 8, 3, 5)
	step(2)
	standAt(START + Vector3.new(30, 3, 0), START)
	t0 = force("Split", START, "Stack", EAST)
	stepUntil(t0 + def.Attacks.Split.Shake + def.Attacks.Split.Pop + 0.3)
	snap("buddies", START + Vector3.new(10, 9, 26), START + Vector3.new(0, 2, 0))
	while E.split and not (E.split.restackAt and M.now() > E.split.restackAt - 1.2) do
		step(DT)
	end
	do
		local c = (E.buddyPos and E.buddyPos[2]) or E.pos
		snap("dizzy", Vector3.new(c.X, E.floorY, c.Z) + Vector3.new(12, 8, 20), Vector3.new(c.X, E.floorY + 2, c.Z))
	end
	step(3)
	standAt(START + Vector3.new(8, 3, 0), START)
	t0 = force("Topple", START, "Stack", EAST)
	stepUntil(t0 + def.Attacks.Topple.Tell + def.Attacks.Topple.Fall + 0.6)
	snap("toppled", START + Vector3.new(6, 7, 18), START + Vector3.new(6, 1, 0))
	step(4)
	-- THE BRUTE
	powerUp()
	step(def.BreakTime + 2.5)
	standAt(START + Vector3.new(30, 3, 0), START)
	takeOver(START, "Brute", EAST)
	step(0.6)
	closeUp("golem", 44, 16, 6, 14)
	t0 = force("RootHop", START, "Brute", EAST)
	stepUntil(t0 + def.Moves.RootHop.Tell + def.Moves.RootHop.Air * 0.45)
	do
		local c = E.pos + Vector3.new(0, 30, 0)
		snap("hop", c + Vector3.new(-30, 4, 52), c)
	end
	step(3)
	t0 = force("Cornered", START, "Brute", EAST)
	stepUntil(t0 + 1.0)
	closeUp("cornered", 40, 14, 6, 13)
	step(4)
	t0 = force("Stunned", START, "Brute", EAST)
	stepUntil(t0 + 1.2)
	closeUp("stunned", 40, -14, 6, 12)
	step(6)
	t0 = force("Rage", START, "Brute", EAST)
	stepUntil(t0 + 0.7)
	closeUp("roar", 42, 14, 5, 14)
	step(2)
	t0 = force("Lance", START, "Brute", EAST)
	stepUntil(t0 + 1.1)
	closeUp("charge", 42, -16, 6, 13)
	step(3)
	-- the end: tiny Tuber, after the crumble
	takeOver(START, "Brute", EAST)
	standAt(START + Vector3.new(24, 3, 12), START)
	step(0.5)
	finish()
	step(3.3)
	do
		local c = model:GetPivot().Position
		local base = Vector3.new(c.X, E.floorY, c.Z)
		snap("tiny", base + Vector3.new(10, 7, 22), base + Vector3.new(2, 1.5, 0))
	end
	-- the audience, close up (they stay a while after he falls, cheering):
	-- one of each - how far in front of it the camera is, how high it looks
	for _, v in ipairs({ { "Camel", "animals", 24, 4.5 }, { "Meerkat", "meerkat", 8, 1.6 }, { "Vulture", "vulture", 9, 1.8 },
		{ "Lizard", "lizard", 6, 0.5 } }) do
		local spot = nil
		for _, l in ipairs(CollectionService:GetTagged("DuneLookout")) do
			if l:GetAttribute("Kind") == v[1] then
				spot = l.Position
				break
			end
		end
		if spot then
			local toC = Vector3.new(C.X - spot.X, 0, C.Z - spot.Z).Unit
			local side = toC:Cross(Vector3.new(0, 1, 0))
			local up = spot + Vector3.new(0, v[4], 0)
			snap(v[2], up + toC * v[3] + side * (v[3] * 0.35) + Vector3.new(0, v[3] * 0.2, 0), up)
		end
	end
	for _, e in ipairs(M.errors) do
		realPrint("ERROR " .. tostring(e))
	end
	return
end

-- 1) the desert from the gate: him asleep in his garden
standAt(spawnPart.Position, home)
step(1)
snap("dunes", C + Vector3.new(14, 11, 40), C + Vector3.new(0, 5, -30))

-- 2) HI THERE!: the player walks up; he pops up and waves
standAt(home + Vector3.new(0, 3, 28), home)
me:SetAttribute("SpireFloor", 2)
while model:GetAttribute("Action") ~= "Wake" do
	step(DT)
end
stepUntil(model:GetAttribute("ActionStart") + 2.0)
snap("hi", home + Vector3.new(16, 9, 26), home + Vector3.new(0, 4, 0))
step(def.WakeTime)

-- 3) WOBBLE BONK: the wedge, him leaning back
standAt(START + Vector3.new(7, 3, 2), START)
local t0 = force("Bonk", START, "Stack", EAST)
stepUntil(t0 + def.Attacks.Bonk.Tell - 0.2)
snap("bonk", START + Vector3.new(14, 14, 22), START + Vector3.new(5, 2, 0))
step(3)

-- 4) CLUMSY TOPPLE: falling along his lane
standAt(START + Vector3.new(9, 3, 5), START)
t0 = force("Topple", START, "Stack", EAST)
stepUntil(t0 + def.Attacks.Topple.Tell + def.Attacks.Topple.Fall * 0.6)
snap("topple", START + Vector3.new(8, 12, 26), START + Vector3.new(6, 2, 0))
step(5)

-- 5) SPLIT!: the buddies' lanes, the first one spin-dashing
standAt(START + Vector3.new(30, 3, 4), START)
t0 = force("Split", START, "Stack", EAST)
do
	local a = def.Attacks.Split
	stepUntil(t0 + a.Shake + a.Pop + a.Rev + a.Gap + 0.25)
end
snap("split", START + Vector3.new(4, 34, 52), START + Vector3.new(16, 0, 0))
step(10)

-- 6) BOUNCE STOMP: in the air over the circle
standAt(START + Vector3.new(20, 3, 2), START)
t0 = force("Stomp", START, "Stack", EAST)
stepUntil(t0 + def.Attacks.Stomp.Crouch + def.Attacks.Stomp.Air * 0.45)
snap("stomp", START + Vector3.new(14, 12, 34), START + Vector3.new(10, 6, 0))
step(3)

-- 7) THE POWER-UP: the cacti flying in, the golem slamming together (from
-- where the game's camera is swinging round him)
standAt(E.pos + Vector3.new(30, 3, 12), E.pos)
powerUp()
local breakAt = model:GetAttribute("ActionStart") or M.now()
stepUntil(breakAt + 2.6)
snapShot("build")
-- 8) THE DESERT COMES TO WATCH: the camera's long look at a camel walking up
stepUntil(breakAt + 6.1)
snapShot("watch")
-- 9) THE BRUTE: crowned, roaring, named - his bar filling
stepUntil(breakAt + 8.25)
do
	local c = E.pos
	local look = model:GetPivot().LookVector
	look = Vector3.new(look.X, 0, look.Z).Unit
	snap("brute", c + look * 46 + Vector3.new(10, 13, 0), c + Vector3.new(0, 14, 0))
end
stepUntil(breakAt + def.BreakTime + 3)

-- 10) CACTUS WALLS AND NEEDLE TURRETS
standAt(START + Vector3.new(34, 3, 0), START)
force("Wall", START, "Brute", EAST)
step(1.6)
local tok = E.token
M.task.spawn(function()
	E.boss.Attacks.Turrets(E, tok)
end)
step(4.2)
snap("walls", START + Vector3.new(60, 30, 44), START + Vector3.new(20, 2, 0))
step(1)

-- 11) BALL HERD: spiky balls rolling in, bouncing
standAt(START + Vector3.new(30, 3, 0), START)
t0 = force("Herd", START, "Brute", EAST)
stepUntil(t0 + def.Attacks.Herd.Show + def.Attacks.Herd.Gap * 2 + def.Attacks.Herd.Tell + 0.9)
snap("herd", START + Vector3.new(30, 70, 70), START + Vector3.new(30, 0, 0))
step(4)

-- 12) DESERT RAIN
standAt(START + Vector3.new(30, 3, 0), START)
t0 = force("Rain", START, "Brute", EAST)
stepUntil(t0 + def.Attacks.Rain.Spit + def.Attacks.Rain.Gap * 4 + 0.7)
snap("rain", START + Vector3.new(44, 26, 44), START + Vector3.new(28, 4, 0))
step(4)

-- 13) SPINE LANCE: locked on, the spike flying
standAt(START + Vector3.new(50, 3, 0), START)
t0 = force("Lance", START, "Brute", EAST)
stepUntil(t0 + def.Attacks.Lance.Charge + 0.12)
snap("lance", START + Vector3.new(26, 18, 60), START + Vector3.new(22, 9, 0))
step(3)

-- 14) THE END: the crumble, tiny Tuber
takeOver(START, "Brute", EAST)
standAt(START + Vector3.new(26, 3, 12), START)
step(1)
finish()
step(2.9)
do
	local c = E.pos
	snap("crumble", c + Vector3.new(26, 16, 40), c + Vector3.new(0, 3, 0))
end
for _, e in ipairs(M.errors) do
	realPrint("ERROR " .. tostring(e))
end
