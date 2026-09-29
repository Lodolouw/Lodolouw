--!nocheck
-- Snapshots of King Gavelgrunt, the Walrus King, for pictures: the real
-- Throne Summit (ThroneBuilder), the real BossService with his moves and the
-- real BossClient drawing him (his warnings, the lightning, his props), and
-- a pretend player (a blocky figure, for scale). At a few moments every part
-- you'd see is printed with the camera:
--   summit   - the Throne Summit from the gate: him asleep up on his throne
--   stand    - THE ENTRANCE: standing on his throne, the gavel raised into
--              the storm - struck by lightning
--   leap     - leaping down off the throne
--   land     - the landing slam
--   smash    - ROYAL SMASH: the gavel up, its runes glowing, the red circle
--   toe      - TOE STOMP: the tip of his flipper glowing (punch it!)
--   piston   - ROUND 2: the mechanical gavel
--   roll     - THE ROYAL ROLL: a ball of blubber down his lane
--   berserk  - ROUND 3: the crown flies off, the scar burns red
--   final    - THE FINAL GAVEL: held up to the sky
--   down     - the end: flat on his back
--   luau gavelgrunt_snaps.luau > gavelgrunt_snaps.txt
--   python3 render_snaps.py gavelgrunt_snaps.txt ../../Docs/gavelgrunt_preview.png --cols 3 --title "KING GAVELGRUNT|FLOOR 10  -  THE THRONE SUMMIT|RECOMMENDED LV 150"
-- `-a poses` instead: close-ups of him (a model sheet), three across:
--   luau gavelgrunt_snaps.luau -a poses > gavelgrunt_poses.txt
--   python3 render_snaps.py gavelgrunt_poses.txt ../../Docs/gavelgrunt_poses.png --cols 3 --title ""
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

local arena = mount.require(mount.module("ServerScriptService/ThroneBuilder.lua")).Build()
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
cam.CFrame = CFrame.lookAt(C + Vector3.new(0, 30, 110), C)
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
	if h:GetAttribute("Floor") ~= 10 then
		CollectionService:RemoveTag(h, "BossHome")
	end
end
local BS = mount.require(mount.module("ServerScriptService/BossService.lua"))
BS.Start(Combat, Profile)
local E = BS.Encounter(10)
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

-- a thunderstorm at dusk, and the captions
realPrint("SKY 38,43,68|139,155,180")
local CAPTIONS = {
	summit = "1  THE THRONE SUMMIT: HE SLEEPS ON HIS THRONE",
	stand = "2  THE ENTRANCE: HE RAISES THE GAVEL TO THE STORM",
	leap = "3  ...AND LEAPS DOWN OFF HIS THRONE",
	land = "4  SLAM: THE COURTYARD SHAKES",
	smash = "5  ROYAL SMASH: THE RUNES GLOW - MOVE!",
	toe = "6  TOE STOMP: PUNCH THE GLOWING FLIPPER",
	piston = "7  ROUND 2: THE MECHANICAL GAVEL",
	roll = "8  THE ROYAL ROLL: GET OUT OF HIS LANE",
	berserk = "9  ROUND 3: THE CROWN FLIES, THE SCAR BURNS",
	final = "10  THE FINAL GAVEL",
	down = "11  THE END: FLAT ON HIS BACK",
	asleep = "ASLEEP ON HIS THRONE",
	glare = "HIS EYES LIGHT UP",
	struck = "STRUCK BY LIGHTNING",
	slam = "THE LANDING",
	laugh = "HAR HAR HAR!",
	windup = "ROYAL SMASH",
	sweep = "GAVEL SWEEP",
	stomp = "TOE STOMP",
	gulp = "BIG GULP",
	ball = "THE ROYAL ROLL",
	rage = "ROUND 3: NO CROWN, NO MERCY",
	worn = "WORN OUT: FINISH HIM!",
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
	E.motion, E.sweep, E.waves, E.pillarSweep = nil, nil, {}, nil
	if pos then
		E.pos = Vector3.new(pos.X, E.floorY, pos.Z)
		E.facing = face or Vector3.new(0, 0, 1)
	end
	E.target, E.targetSince = me, M.now()
	step(DT * 2)
	return E.token
end
local function force(name, pos, face)
	local token = takeOver(pos, face)
	M.task.spawn(function()
		E.boss.Attacks[name](E, token)
	end)
	step(DT * 2)
	return model:GetAttribute("ActionStart") or M.now()
end
-- a close-up of him: from in front (dist away, side across), looking at lookH up his body
local function closeUpAt(name, at, look, dist, side, height, lookH)
	local c = at + Vector3.new(0, lookH, 0)
	local sideV = look:Cross(Vector3.new(0, 1, 0))
	snap(name, c + look * dist + sideV * side + Vector3.new(0, height, 0), c)
end
local function closeUp(name, dist, side, height, lookH)
	closeUpAt(name, E.pos, Vector3.new(E.facing.X, 0, E.facing.Z).Unit, dist, side, height, lookH)
end
local function setHealth(share)
	local max = model:GetAttribute("MaxHealth") or 1
	model:SetAttribute("Health", math.floor(max * share))
	model:FindFirstChild("OnHit"):Fire(me, 1, false)
end
local function finish()
	model:SetAttribute("Health", 0)
	model:FindFirstChild("OnHit"):Fire(me, 1, true)
end

local ThronePlan = mount.require(mount.module("ReplicatedStorage/ThronePlan.lua"))
local MID = Vector3.new(C.X, 0, C.Z)
local SEAT = C + ThronePlan.SeatAt
local SOUTH = Vector3.new(0, 0, 1)
local A = def.Attacks
local LAND = def.IntroDelay
local STRIKE, LEAP, LAUGH = LAND - 1.6, LAND - 0.95, LAND + 0.7

local function wake()
	me:SetAttribute("SpireFloor", 10)
	standAt(home + Vector3.new(4, 3, 30), home)
	while model:GetAttribute("Action") ~= "Wake" do
		step(DT)
	end
	return model:GetAttribute("ActionStart")
end

if MODE == "turn" then
	-- (a turnaround of him standing, for a close look: front, three-quarter,
	-- side, back - big)
	local t0 = wake()
	stepUntil(t0 + def.WakeTime + 0.5)
	standAt(MID + Vector3.new(0, 3, 90), MID)
	takeOver(MID, SOUTH)
	step(1.5)
	local c = MID + Vector3.new(0, 24, 0)
	for i, ang in ipairs({ 0, 0.7, 1.57, 2.45 }) do
		local dir = Vector3.new(math.sin(ang), 0, math.cos(ang))
		snap("turn" .. i, c + dir * 62 + Vector3.new(0, 6, 0), c)
	end
	return
end

if MODE == "poses" then
	standAt(C + Vector3.new(0, 3, 90), home)
	step(1)
	closeUpAt("asleep", SEAT + Vector3.new(0, ThronePlan.SeatHeight, 0), SOUTH, 62, 18, -6, 22)
	local t0 = wake()
	stepUntil(t0 + 0.55)
	closeUpAt("glare", SEAT + Vector3.new(0, ThronePlan.SeatHeight, 0), SOUTH, 40, 10, 2, 30)
	stepUntil(t0 + STRIKE + 0.04)
	closeUpAt("struck", SEAT + Vector3.new(0, ThronePlan.SeatHeight, 0), SOUTH, 80, 22, -4, 34)
	stepUntil(t0 + LAND + 0.1)
	closeUp("slam", 62, 20, 2, 18)
	stepUntil(t0 + LAUGH + 0.4)
	closeUp("laugh", 64, -22, 4, 26)
	step(def.WakeTime)
	standAt(MID + Vector3.new(0, 3, 34), MID)
	t0 = force("RoyalSmash", MID, SOUTH)
	stepUntil(t0 + A.RoyalSmash.Tell * 0.85)
	closeUp("windup", 70, 26, 4, 28)
	step(4)
	t0 = force("GavelSweep", MID, SOUTH)
	stepUntil(t0 + A.GavelSweep.Tell + 0.1)
	closeUp("sweep", 70, -24, 8, 20)
	step(3)
	standAt(MID + Vector3.new(4, 3, 26), MID)
	t0 = force("ToeStomp", MID, SOUTH)
	stepUntil(t0 + A.ToeStomp.Tell + 0.4)
	closeUp("stomp", 56, 26, 2, 14)
	step(4)
	setHealth(def.PhaseAt)
	step(def.BreakTime + 0.5)
	standAt(MID + Vector3.new(0, 3, 40), MID)
	t0 = force("BigGulp", MID, SOUTH)
	stepUntil(t0 + A.BigGulp.Tell + A.BigGulp.Inhale * 0.7)
	closeUp("gulp", 56, 18, 4, 28)
	step(6)
	standAt(MID + Vector3.new(4, 3, 44), MID)
	t0 = force("RoyalRoll", MID, SOUTH)
	stepUntil(t0 + A.RoyalRoll.Tell * 0.8)
	closeUp("ball", 50, 16, 4, 9)
	step(6)
	takeOver(MID, SOUTH)
	setHealth(def.Round3At)
	step(0.2) -- (round 3 begins on his next step)
	local b0 = model:GetAttribute("ActionStart") or M.now()
	stepUntil(b0 + def.BerserkTime * 0.8)
	closeUp("rage", 52, -16, 4, 30)
	stepUntil(b0 + def.BerserkTime + 0.5)
	takeOver(MID, SOUTH)
	setHealth(def.FinalAt)
	step(1.5)
	local f0 = model:GetAttribute("ActionStart") or M.now()
	stepUntil(f0 + def.Final.Tell + 1.5)
	closeUp("worn", 56, 20, 4, 14)
	for _, e in ipairs(M.errors) do
		realPrint("ERROR " .. tostring(e))
	end
	return
end

-- 1) the Throne Summit from the gate: him asleep up on his throne
standAt(spawnPart.Position, home)
step(1)
snap("summit", C + Vector3.new(34, 34, 112), C + Vector3.new(0, 18, -40))

-- 2-4) THE ENTRANCE
local t0 = wake()
stepUntil(t0 + STRIKE + 0.04)
snap("stand", C + Vector3.new(46, 22, 32), SEAT + Vector3.new(0, 42, 0))
stepUntil(t0 + LEAP + 0.5)
snap("leap", C + Vector3.new(96, 28, -6), C + Vector3.new(0, 30, -30))
stepUntil(t0 + LAND + 0.08)
snap("land", home + Vector3.new(8, 14, 70), home + Vector3.new(0, 20, 0))
step(def.WakeTime)

-- 5) ROYAL SMASH: the gavel up, the runes glowing, the red circle
standAt(MID + Vector3.new(2, 3, 24), MID)
t0 = force("RoyalSmash", MID, SOUTH)
stepUntil(t0 + A.RoyalSmash.Tell * 0.85)
snap("smash", MID + Vector3.new(10, 22, 66), MID + Vector3.new(0, 20, 8))
step(4)

-- 6) TOE STOMP: the glowing tip of his flipper
standAt(MID + Vector3.new(-6, 3, 24), MID)
t0 = force("ToeStomp", MID, SOUTH)
stepUntil(t0 + A.ToeStomp.Tell + 0.35)
snap("toe", MID + Vector3.new(30, 10, 50), MID + Vector3.new(2, 8, 10))
step(4)

-- 7) ROUND 2: the mechanical gavel
takeOver(MID, SOUTH)
standAt(MID + Vector3.new(6, 3, 34), MID)
setHealth(def.PhaseAt)
local breakAt = model:GetAttribute("ActionStart") or M.now()
stepUntil(breakAt + def.BreakTime * 0.6)
snap("piston", MID + Vector3.new(40, 18, 58), MID + Vector3.new(0, 26, 0))
stepUntil(breakAt + def.BreakTime + 1)

-- 8) THE ROYAL ROLL: down his lane
standAt(MID + Vector3.new(6, 3, 46), MID)
t0 = force("RoyalRoll", MID, SOUTH)
stepUntil(t0 + A.RoyalRoll.Tell + 0.25)
snap("roll", MID + Vector3.new(48, 22, 60), MID + Vector3.new(0, 6, 24))
step(6)

-- 9) ROUND 3: the crown flies off, the scar burns red
takeOver(MID, SOUTH)
standAt(MID + Vector3.new(6, 3, 34), MID)
setHealth(def.Round3At)
step(0.2) -- (round 3 begins on his next step)
local berserkAt = model:GetAttribute("ActionStart") or M.now()
stepUntil(berserkAt + def.BerserkTime * 0.55)
snap("berserk", MID + Vector3.new(36, 16, 54), MID + Vector3.new(0, 28, 0))
stepUntil(berserkAt + def.BerserkTime + 0.5)

-- 10) THE FINAL GAVEL: held up to the sky
takeOver(MID, SOUTH)
standAt(MID + Vector3.new(4, 3, 44), MID)
setHealth(def.FinalAt)
step(0.3)
local finalAt = model:GetAttribute("ActionStart") or M.now()
stepUntil(finalAt + 2.0)
snap("final", MID + Vector3.new(56, 20, 70), MID + Vector3.new(0, 34, 0))
stepUntil(finalAt + def.Final.Tell + def.Final.Tired + 0.5)

-- 11) THE END: flat on his back
takeOver(MID, SOUTH)
standAt(MID + Vector3.new(10, 3, 30), MID)
step(0.5)
finish()
step(2.6)
snap("down", MID + Vector3.new(44, 20, 44), MID + Vector3.new(0, 6, -8))
for _, e in ipairs(M.errors) do
	realPrint("ERROR " .. tostring(e))
end
