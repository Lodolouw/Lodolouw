--!nocheck
-- Snapshots of Kongo for pictures: the real jungle village (JungleBuilder),
-- the real BossService with his moves and the real BossClient drawing him
-- (his warnings, the villagers, the torches), and a pretend player (a blocky
-- figure, for scale). At a few moments every part you'd see is printed with
-- the camera:
--   village  - Kongo's Jungle Village from the gate, him asleep in the clearing
--   wake     - he wakes: a chest pound and a roar ("OOH OOH!")
--   punch    - GIANT PUNCH: the windmill, the red lane growing
--   slap     - HAND SLAP: shockwaves rolling out along the floor
--   roll     - ROLLING ATTACK: curled into a ball, rolling down his lane
--   spin     - SPINNING KONG: arms out, the red ring round him
--   barrel   - BARREL THROW: one rolling at you, the next over his head
--   tnt      - TNT: flying over, the red circle where it lands
--   tired    - he missed: tired, hands on his knees - HIT HIM!
--   bananas  - ROUND 2: he goes bananas (red face, the torches flaring)
--   down     - the end: flat on his back, the villagers covering their eyes
--   luau kongo_snaps.luau > kongo_snaps.txt
--   python3 render_snaps.py kongo_snaps.txt ../../Docs/kongo_preview.png --cols 3 --title "KONGO|FLOOR 7  -  KONGO'S JUNGLE VILLAGE|RECOMMENDED LV 105"
-- `-a poses` instead: close-ups of him (a model sheet), three across:
--   luau kongo_snaps.luau -a poses > kongo_poses.txt
--   python3 render_snaps.py kongo_poses.txt ../../Docs/kongo_poses.png --cols 3 --title ""
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

local arena = mount.require(mount.module("ServerScriptService/JungleBuilder.lua")).Build()
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
for _, h in ipairs(CollectionService:GetTagged("BossHome")) do
	if h:GetAttribute("Floor") ~= 7 then
		CollectionService:RemoveTag(h, "BossHome")
	end
end
local BS = mount.require(mount.module("ServerScriptService/BossService.lua"))
BS.Start(Combat, Profile)
local E = BS.Encounter(7)
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
	local state = model:GetAttribute("State")
	local awake = state == "Waking" or state == "Fighting" or state == "Transition"
	local max = math.max(model:GetAttribute("MaxHealth") or 1, 1)
	local hp = model:GetAttribute("Health") or max
	realPrint(string.format("BAR %s|%.3f|%d", awake and def.Name or "", math.clamp(hp / max, 0, 1), model:GetAttribute("Phase") or 1))
	realPrint("ENDSNAP")
end

-- a warm jungle afternoon, and the captions
realPrint("SKY 0,153,219|206,232,186")
local CAPTIONS = {
	village = "1  KONGO'S JUNGLE VILLAGE: HE NAPS IN THE CLEARING",
	wake = "2  HE WAKES UP: OOH OOH!",
	punch = "3  GIANT PUNCH: THE LANE GROWS - STEP OUT",
	slap = "4  HAND SLAP: JUMP THE SHOCKWAVES",
	roll = "5  ROLLING ATTACK: ROLL THROUGH HIM",
	spin = "6  SPINNING KONG: BACK OFF",
	barrel = "7  BARREL THROW: JUMP THEM",
	tnt = "8  TNT: GET OUT OF THE CIRCLE",
	tired = "9  MISSED! HE'S TIRED: HIT HIM!",
	bananas = "10  ROUND 2: HE GOES BANANAS",
	down = "11  THE END: FLAT ON HIS BACK",
	asleep = "ASLEEP",
	roar = "OOH OOH!",
	windmill = "GIANT PUNCH: WINDING UP",
	slapdown = "HAND SLAP",
	ball = "ROLLING ATTACK",
	heli = "SPINNING KONG",
	overhead = "BARREL THROW",
	grab = "CARGO THROW: YOINK!",
	mad = "GOING BANANAS",
}
for k, v in pairs(CAPTIONS) do
	realPrint("CAPTION " .. k .. " " .. v)
end

-- take him over: his brain stopped, put where we say facing `face`, aiming at the player
local function takeOver(pos, face)
	while model:GetAttribute("State") ~= "Fighting" do
		step(0.1)
	end
	E.token += 1
	E.motion, E.sweep, E.waves = nil, nil, {}
	if pos then
		E.pos = Vector3.new(pos.X, E.floorY, pos.Z)
		E.facing = face or Vector3.new(0, 0, 1)
	end
	E.target, E.targetSince = me, M.now()
	step(DT * 2)
	return E.token
end
local function force(name, pos, face, fn)
	local token = takeOver(pos, face)
	M.task.spawn(function()
		(fn or E.boss.Attacks[name])(E, token)
	end)
	step(DT * 2)
	return model:GetAttribute("ActionStart") or M.now()
end
local function closeUp(name, dist, side, height, lookH)
	local c = E.pos + Vector3.new(0, lookH or 7, 0)
	local look = model:GetPivot().LookVector
	look = Vector3.new(look.X, 0, look.Z).Unit
	local sideV = look:Cross(Vector3.new(0, 1, 0))
	snap(name, c + look * (dist or 30) + sideV * (side or 10) + Vector3.new(0, height or 4, 0), c)
end
local function powerUp()
	local max = model:GetAttribute("MaxHealth") or 1
	model:SetAttribute("Health", math.floor(max * def.PhaseAt))
	model:FindFirstChild("OnHit"):Fire(me, 1, false)
end
local function finish()
	model:SetAttribute("Health", 0)
	model:FindFirstChild("OnHit"):Fire(me, 1, true)
end

local MID = Vector3.new(C.X, 0, C.Z)
local SOUTH = Vector3.new(0, 0, 1)
local A = def.Attacks

if MODE == "poses" then
	standAt(C + Vector3.new(0, 3, 90), home)
	step(1)
	closeUp("asleep", 20, 7, 2, 4)
	me:SetAttribute("SpireFloor", 7)
	standAt(home + Vector3.new(0, 3, 30), home)
	while model:GetAttribute("Action") ~= "Wake" do
		step(DT)
	end
	stepUntil(model:GetAttribute("ActionStart") + def.WakeTime * 0.8)
	closeUp("roar", 26, 8, 3, 7)
	step(def.WakeTime)
	standAt(MID + Vector3.new(0, 3, 30), MID)
	local t0 = force("GiantPunch", MID, SOUTH, function(e, tok)
		E.boss._giantPunch(e, tok, 1.5)
	end)
	stepUntil(t0 + 1.0)
	closeUp("windmill", 26, 12, 3, 7)
	step(3)
	t0 = force("HandSlap", MID, SOUTH)
	stepUntil(t0 + A.HandSlap.Tell + 0.11) -- (hand still down, the shockwave just rolling out)
	closeUp("slapdown", 26, -10, 4, 6)
	step(4)
	standAt(MID + Vector3.new(0, 3, 40), MID)
	t0 = force("Roll", MID, SOUTH)
	stepUntil(t0 + A.Roll.Tell * 0.35 + 0.1) -- (just curled up, his face still at the front)
	closeUp("ball", 24, 10, 3, 4)
	step(5)
	t0 = force("Spin", MID, SOUTH)
	stepUntil(t0 + A.Spin.Tell + 0.5)
	closeUp("heli", 30, 10, 5, 7)
	step(5)
	t0 = force("Barrel", MID, SOUTH)
	stepUntil(t0 + A.Barrel.Tell - 0.1)
	closeUp("overhead", 28, 10, 3, 9)
	step(4)
	powerUp()
	step(def.BreakTime + 0.5)
	standAt(MID + Vector3.new(0, 3, 12), MID)
	t0 = force("CargoThrow", MID, SOUTH)
	stepUntil(t0 + A.CargoThrow.Tell * 0.9)
	closeUp("grab", 28, 12, 3, 7)
	step(3)
	-- going bananas, close up (a second time round: a reset, a fresh fight)
	takeOver(MID, SOUTH)
	local t1 = force("Pound", MID, SOUTH)
	stepUntil(t1 + 0.6)
	closeUp("mad", 24, -8, 3, 8)
	for _, e in ipairs(M.errors) do
		realPrint("ERROR " .. tostring(e))
	end
	return
end

-- 1) the village from the gate: him asleep in the clearing
standAt(spawnPart.Position, home)
step(1)
snap("village", C + Vector3.new(26, 26, 104), C + Vector3.new(0, 6, -40))

-- 2) HE WAKES UP: the player walks up; a chest pound and a roar
standAt(home + Vector3.new(4, 3, 30), home)
me:SetAttribute("SpireFloor", 7)
while model:GetAttribute("Action") ~= "Wake" do
	step(DT)
end
stepUntil(model:GetAttribute("ActionStart") + def.WakeTime * 0.8)
snap("wake", home + Vector3.new(22, 10, 34), home + Vector3.new(0, 7, 0))
step(def.WakeTime)

-- 3) GIANT PUNCH: the windmill, the lane growing
standAt(MID + Vector3.new(2, 3, 24), MID)
local t0 = force("GiantPunch", MID, SOUTH, function(e, tok)
	E.boss._giantPunch(e, tok, 1.5)
end)
stepUntil(t0 + 1.05)
snap("punch", MID + Vector3.new(26, 20, 34), MID + Vector3.new(0, 4, 12))
step(3)

-- 4) HAND SLAP: shockwaves rolling out
standAt(MID + Vector3.new(4, 3, 22), MID)
t0 = force("HandSlap", MID, SOUTH)
stepUntil(t0 + A.HandSlap.Tell + A.HandSlap.Gap + 0.25)
snap("slap", MID + Vector3.new(30, 22, 36), MID + Vector3.new(0, 2, 8))
step(3)

-- 5) ROLLING ATTACK: rolling down the lane
standAt(MID + Vector3.new(4, 3, 40), MID)
t0 = force("Roll", MID, SOUTH)
stepUntil(t0 + A.Roll.Tell + 0.3)
snap("roll", MID + Vector3.new(34, 18, 44), MID + Vector3.new(0, 3, 22))
step(5)

-- 6) SPINNING KONG: arms out, the ring round him
standAt(MID + Vector3.new(4, 3, 18), MID)
t0 = force("Spin", MID, SOUTH)
stepUntil(t0 + A.Spin.Tell + 0.7)
do
	local c = E.pos
	snap("spin", c + Vector3.new(26, 16, 30), c + Vector3.new(0, 5, 0))
end
step(5)

-- 7) BARREL THROW: one rolling at you, the next over his head
standAt(MID + Vector3.new(2, 3, 40), MID)
t0 = force("Barrel", MID, SOUTH)
stepUntil(t0 + A.Barrel.Tell + A.Barrel.Gap - 0.08) -- (the next one right up over his head)
snap("barrel", MID + Vector3.new(30, 18, 44), MID + Vector3.new(0, 5, 18))
step(4)

-- 8) TNT: flying over, the red circle
standAt(MID + Vector3.new(0, 3, 30), MID)
t0 = force("TNT", MID, SOUTH)
stepUntil(t0 + A.TNT.Tell + A.TNT.Flight * 0.55)
snap("tnt", MID + Vector3.new(34, 22, 40), MID + Vector3.new(0, 6, 16))
step(3)

-- 9) MISSED! HE'S TIRED: the player stepped out of the lane
standAt(MID + Vector3.new(0, 3, 14), MID)
t0 = force("GiantPunch", MID, SOUTH, function(e, tok)
	E.boss._giantPunch(e, tok, 1.2)
end)
stepUntil(t0 + 1.0)
standAt(MID + Vector3.new(16, 3, 10), MID + Vector3.new(0, 0, 14))
stepUntil(t0 + 2.4)
do
	local c = E.pos
	snap("tired", c + Vector3.new(20, 9, 20), c + Vector3.new(0, 5, 0))
end
step(3)

-- 10) ROUND 2: he goes bananas
takeOver(MID, SOUTH)
standAt(MID + Vector3.new(6, 3, 30), MID)
powerUp()
local breakAt = model:GetAttribute("ActionStart") or M.now()
stepUntil(breakAt + def.BreakTime * 0.6)
snap("bananas", MID + Vector3.new(22, 12, 40), MID + Vector3.new(0, 7, 0))
stepUntil(breakAt + def.BreakTime + 1)

-- 11) THE END: flat on his back
takeOver(MID, SOUTH)
standAt(MID + Vector3.new(10, 3, 24), MID)
step(0.5)
finish()
step(2.4)
snap("down", MID + Vector3.new(28, 14, 30), MID + Vector3.new(0, 2, -4))
for _, e in ipairs(M.errors) do
	realPrint("ERROR " .. tostring(e))
end
