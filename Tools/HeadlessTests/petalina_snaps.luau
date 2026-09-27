--!nocheck
-- Snapshots of Petalina for pictures: the real greenhouse (GreenhouseBuilder),
-- the real BossService with her moves and the real BossClient drawing her
-- (her warnings, flytraps, brambles and butterflies), and a pretend player
-- (a blocky figure, for scale). At a few moments every part you'd see is
-- printed with the camera:
--   garden   - the Glasshouse Garden from the door, her a closed bud in the middle
--   wake     - she blooms: "HELLO, SWEETIE~!"
--   seeds    - SEED SPIT: seeds flying onto their red circles
--   petals   - PETAL BOOMERANG: two petals on their dotted loops
--   vines    - VINE WHIP: vines bursting up along the lines
--   pollen   - POLLEN CLOUD: clouds hanging on their circles
--   stretch  - FACE STRETCH: her head racing down the lane
--   droop    - her head on the floor, dizzy - HIT HER!
--   traps    - her flytraps gaping at you
--   evil     - ROUND 2: thorns on every bed, a ring of thorns spreading
--   wilt     - the end: petals falling, her head bowed to the floor
--   luau petalina_snaps.luau > petalina_snaps.txt
--   python3 render_snaps.py petalina_snaps.txt ../../Docs/petalina_preview.png --cols 3 --title "PETALINA|FLOOR 8  -  THE GLASSHOUSE GARDEN|RECOMMENDED LV 120"
-- `-a poses` instead: close-ups of her (a model sheet), three across:
--   luau petalina_snaps.luau -a poses > petalina_poses.txt
--   python3 render_snaps.py petalina_poses.txt ../../Docs/petalina_poses.png --cols 3 --title ""
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

local arena = mount.require(mount.module("ServerScriptService/GreenhouseBuilder.lua")).Build()
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
for _, h in ipairs(CollectionService:GetTagged("BossHome")) do
	if h:GetAttribute("Floor") ~= 8 then
		CollectionService:RemoveTag(h, "BossHome")
	end
end
local BS = mount.require(mount.module("ServerScriptService/BossService.lua"))
BS.Start(Combat, Profile)
local E = BS.Encounter(8)
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

-- a sunny day under glass, and the captions
realPrint("SKY 44,232,245|240,244,214")
local CAPTIONS = {
	garden = "1  THE GLASSHOUSE GARDEN: A BUD IN THE MIDDLE",
	wake = "2  SHE BLOOMS: HELLO, SWEETIE~!",
	seeds = "3  SEED SPIT: OUT OF THE CIRCLES",
	petals = "4  PETAL BOOMERANG: JUMP IT OR STAY INSIDE",
	vines = "5  VINE WHIP: STEP OFF THE LINES",
	pollen = "6  POLLEN CLOUD: DON'T STAND IN IT",
	stretch = "7  FACE STRETCH: OUT OF THE LANE",
	droop = "8  HER HEAD'S DOWN: HIT HER!",
	traps = "9  FLYTRAPS: ONE PUNCH POPS THEM",
	evil = "10  ROUND 2: THORNS ON THE BEDS - STAY ON THE PATHS",
	wilt = "11  THE END: SHE WILTS",
	bud = "ASLEEP: A BUD",
	bloom = "BLOOMING",
	puff = "SEED SPIT",
	fling = "PETAL BOOMERANG",
	slap = "VINE WHIP",
	grin = "FACE STRETCH: WINDING UP",
	sun = "SUNBATHING: FREE HITS",
	wicked = "ROUND 2: WICKED",
	shriek = "SEED RAIN",
}
for k, v in pairs(CAPTIONS) do
	realPrint("CAPTION " .. k .. " " .. v)
end

-- take her over: her brain stopped, put where we say facing `face`, aiming at the player
local function takeOver(pos, face)
	while model:GetAttribute("State") ~= "Fighting" do
		step(0.1)
	end
	E.token += 1
	E.motion, E.sweep, E.waves, E.clouds, E.head, E.headNow = nil, nil, {}, {}, nil, nil
	for _, trap in ipairs(E.traps or {}) do
		trap.dieAt = 0
	end
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

local MID = Vector3.new(C.X, 0, C.Z)
local SOUTH = Vector3.new(0, 0, 1)
local A = def.Attacks
local HEAD = def.HeadHeight

if MODE == "poses" then
	standAt(C + Vector3.new(0, 3, 62), home)
	step(1)
	closeUp("bud", 34, 10, 2, HEAD - 6)
	me:SetAttribute("SpireFloor", 8)
	standAt(home + Vector3.new(0, 3, 30), home)
	while model:GetAttribute("Action") ~= "Wake" do
		step(DT)
	end
	stepUntil(model:GetAttribute("ActionStart") + def.WakeTime * 0.62)
	closeUp("bloom", 38, 12, 0, HEAD - 8)
	step(def.WakeTime)
	standAt(MID + Vector3.new(0, 3, 24), MID)
	local t0 = force("SeedSpit", MID, SOUTH)
	stepUntil(t0 + A.SeedSpit.Tell * 0.9)
	closeUp("puff", 34, 10, 0, HEAD - 6)
	step(4)
	t0 = force("Petals", MID, SOUTH)
	stepUntil(t0 + A.Petals.Tell + 0.1)
	closeUp("fling", 40, 14, 0, HEAD - 10)
	step(5)
	t0 = force("VineWhip", MID, SOUTH)
	stepUntil(t0 + A.VineWhip.Tell * 0.75)
	closeUp("slap", 42, -12, 2, HEAD - 12)
	step(4)
	t0 = force("FaceStretch", MID, SOUTH)
	stepUntil(t0 + A.FaceStretch.Tell * 0.9)
	closeUp("grin", 36, -10, 0, HEAD - 6)
	step(5)
	t0 = force("Sunbathe", MID, SOUTH)
	stepUntil(t0 + 0.8)
	closeUp("sun", 38, 10, -2, HEAD - 6)
	step(3)
	powerUp()
	step(def.BreakTime + 1.5)
	t0 = force("ThornRing", MID, SOUTH)
	stepUntil(t0 + 0.2)
	closeUp("wicked", 34, 10, 0, HEAD - 6)
	step(5)
	t0 = force("SeedRain", MID, SOUTH)
	stepUntil(t0 + A.SeedRain.Tell * 0.8)
	closeUp("shriek", 38, -10, -2, HEAD - 6)
	for _, e in ipairs(M.errors) do
		realPrint("ERROR " .. tostring(e))
	end
	return
end

-- 1) the garden from the door: her a closed bud in the middle
standAt(spawnPart.Position, home)
step(1)
snap("garden", C + Vector3.new(22, 20, 64), C + Vector3.new(0, 10, -10))

-- 2) SHE BLOOMS: the player walks up
standAt(home + Vector3.new(4, 3, 30), home)
me:SetAttribute("SpireFloor", 8)
while model:GetAttribute("Action") ~= "Wake" do
	step(DT)
end
stepUntil(model:GetAttribute("ActionStart") + def.WakeTime * 0.75)
snap("wake", home + Vector3.new(30, 16, 44), home + Vector3.new(0, 16, 0))
step(def.WakeTime)

-- 3) SEED SPIT: seeds in the air, red circles round you
standAt(MID + Vector3.new(2, 3, 28), MID)
local t0 = force("SeedSpit", MID, SOUTH)
stepUntil(t0 + A.SeedSpit.Tell + 2 * A.SeedSpit.Gap + A.SeedSpit.Flight * 0.5)
snap("seeds", MID + Vector3.new(26, 18, 58), MID + Vector3.new(0, 6, 18))
step(4)

-- 4) PETAL BOOMERANG: both petals out on their loops
standAt(MID + Vector3.new(0, 3, 26), MID)
t0 = force("Petals", MID, SOUTH)
stepUntil(t0 + A.Petals.Tell + A.Petals.Gap + 0.45)
snap("petals", MID + Vector3.new(20, 20, 60), MID + Vector3.new(0, 1, 18))
step(6)

-- 5) VINE WHIP: vines racing out along the lines
standAt(MID + Vector3.new(6, 3, 24), MID)
t0 = force("VineWhip", MID, SOUTH)
stepUntil(t0 + A.VineWhip.Tell + 0.3)
snap("vines", MID + Vector3.new(28, 18, 56), MID + Vector3.new(0, 4, 16))
step(4)

-- 6) POLLEN CLOUD: clouds hanging on their circles
standAt(MID + Vector3.new(-4, 3, 26), MID)
t0 = force("Pollen", MID, SOUTH)
stepUntil(t0 + A.Pollen.Tell + A.Pollen.Drift + 0.6)
snap("pollen", MID + Vector3.new(26, 16, 58), MID + Vector3.new(0, 5, 20))
step(A.Pollen.Life + 1)

-- 7) FACE STRETCH: her head racing down the lane
standAt(MID + Vector3.new(9, 3, 22), MID)
me.Character.HumanoidRootPart.CFrame = CFrame.new(MID + Vector3.new(0, 3, 22))
t0 = force("FaceStretch", MID, SOUTH)
stepUntil(t0 + A.FaceStretch.Tell * A.FaceStretch.Commit + 0.1)
standAt(MID + Vector3.new(10, 3, 20), MID)
stepUntil(t0 + A.FaceStretch.Tell + A.FaceStretch.Time * 0.75)
snap("stretch", MID + Vector3.new(38, 18, 40), MID + Vector3.new(0, 6, 14))

-- 8) HER HEAD'S DOWN: dizzy on the floor
stepUntil(t0 + A.FaceStretch.Tell + A.FaceStretch.Time + 0.8)
standAt(MID + Vector3.new(6, 3, 24), MID + Vector3.new(0, 0, 25))
snap("droop", MID + Vector3.new(22, 10, 40), MID + Vector3.new(0, 3, 22))
step(4)

-- 9) FLYTRAPS: sprouted round you, gaping
standAt(MID + Vector3.new(0, 3, 30), MID)
t0 = force("SeedSpit", MID, SOUTH)
stepUntil(t0 + A.SeedSpit.Tell + 4 * A.SeedSpit.Gap + A.SeedSpit.Flight + 0.1)
E.token += 1 -- (just the traps now)
standAt(MID + Vector3.new(0, 3, 30), MID)
step(def.Flytrap.Grow + 0.5)
do
	local best, bestT = 0, nil
	for _, f in ipairs(workspace:FindFirstChild("PetalinaProps") and workspace.PetalinaProps:GetChildren() or {}) do
		local w = f:GetAttribute("BiteWarn")
		if w and w > best then
			best, bestT = w, f
		end
	end
	if bestT then
		stepUntil(bestT:GetAttribute("BiteWarn") + def.Flytrap.Tell * 0.8)
	end
end
snap("traps", MID + Vector3.new(16, 11, 48), MID + Vector3.new(0, 2, 28))
step(1)

-- 10) ROUND 2: the thorns, and a ring of thorns spreading
takeOver(nil)
standAt(MID + Vector3.new(0, 3, 34), MID)
powerUp()
local breakAt = model:GetAttribute("ActionStart") or M.now()
stepUntil(breakAt + def.BreakTime + 0.8)
t0 = force("ThornRing", MID, SOUTH)
stepUntil(t0 + A.ThornRing.Tell + 0.55)
snap("evil", MID + Vector3.new(34, 21, 58), MID + Vector3.new(0, 6, 6))
step(4)

-- 11) THE END: she wilts
takeOver(nil)
standAt(MID + Vector3.new(8, 3, 30), MID)
step(0.5)
finish()
step(1.9)
snap("wilt", MID + Vector3.new(34, 16, 44), MID + Vector3.new(0, 8, 4))
for _, e in ipairs(M.errors) do
	realPrint("ERROR " .. tostring(e))
end
