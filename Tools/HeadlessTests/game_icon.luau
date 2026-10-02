--!nocheck
-- The bosses for the GAME ICON (render_game_icon.py): the real arena builder
-- (only so BossService finds his BossHome), the real BossService and the real
-- BossClient/BossBodies drawing him, held in a pose. Only his drawn body is
-- printed (BossFX), not the arena: the icon puts him on its own background.
--   luau game_icon.luau -a gridlock roar > icon_gridlock.txt
--   luau game_icon.luau -a gavelgrunt rage,laugh > icon_gavelgrunt.txt
-- Poses (comma separated): wake:<share of his WakeTime> (his entrance, frozen
-- there), and the special ones below (roar for Gridlock, rage/laugh for King
-- Gavelgrunt, mad for Kongo). Each pose prints
--   POSE <name> <x y z of his feet> <lx lz his facing>
--   {"g": <BossFX child>, ...one part per line, as the snaps...}
--   ENDPOSE
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Vector3, CFrame, Instance = M.Vector3, M.CFrame, M.Instance
local CollectionService = M.services.CollectionService
local RunService = M.services.RunService
local Players = M.services.Players
local workspace = M.workspace
local realPrint = print
local ARGS = { ... }
local BOSS = ARGS[1] or "gridlock"
local POSES = ARGS[2] or "wake:0.8"

local FLOORS = {
	oozark = { 1, "LobbyBuilder" },
	tuber = { 2, "DunesBuilder" },
	burrowmore = { 3, "DigBuilder" },
	kaze = { 4, "DojoBuilder" },
	revvington = { 5, "SpeedwayBuilder" },
	gridlock = { 6, "GridBuilder" },
	kongo = { 7, "JungleBuilder" },
	petalina = { 8, "GreenhouseBuilder" },
	scribble = { 9, "CanvasBuilder" },
	gavelgrunt = { 10, "ThroneBuilder" },
}
assert(FLOORS[BOSS], "no boss " .. BOSS)
local FLOOR, BUILDER = FLOORS[BOSS][1], FLOORS[BOSS][2]
if FLOOR == 2 then
	mount.require(mount.module("ServerScriptService/LobbyBuilder.lua")).Build()
end
mount.require(mount.module("ServerScriptService/" .. BUILDER .. ".lua")).Build()
M.run(1)
for _, h in ipairs(CollectionService:GetTagged("BossHome")) do
	if h:GetAttribute("Floor") ~= FLOOR then
		CollectionService:RemoveTag(h, "BossHome")
	end
end

-- the player (unseen: the icon draws its own noob), standing where we say
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
local function standAt(pos, lookAt)
	root.CFrame = CFrame.lookAt(pos, Vector3.new(lookAt.X, pos.Y, lookAt.Z))
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
cam.CFrame = CFrame.lookAt(Vector3.new(0, 30, 110), Vector3.new(0, 0, 0))
cam.Parent = workspace
workspace.CurrentCamera = cam

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
local E = assert(BS.Encounter(FLOOR), "no boss on floor " .. FLOOR)
local model, def, home = E.model, E.def, E.home
-- (the camera near him: a body may skip drawing what's far from the camera)
cam.CFrame = CFrame.lookAt(home + Vector3.new(8, 25, 90), home + Vector3.new(0, 10, 0))
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

local function dump(name)
	local pv = model:GetPivot()
	local feet = E.pos or pv.Position
	local look = pv.LookVector
	realPrint(string.format("POSE %s %.3f %.3f %.3f %.4f %.4f", name, feet.X, feet.Y, feet.Z, look.X, look.Z))
	realPrint(string.format("INFO %s %s %s t=%.2f", tostring(model:GetAttribute("State")), tostring(model:GetAttribute("Action")), tostring(model:GetAttribute("Health")), M.now()))
	local fx = workspace:FindFirstChild("BossFX")
	for _, child in ipairs(fx and fx:GetChildren() or {}) do
		local list = child:GetDescendants()
		if child:IsA("BasePart") then
			table.insert(list, 1, child)
		end
		for _, d in ipairs(list) do
			if d:IsA("BasePart") and (d.Transparency or 0) < 0.98 then
				local comps = { d.CFrame:GetComponents() }
				for i, v in ipairs(comps) do
					comps[i] = string.format("%.3f", v)
				end
				local col = d.Color
				realPrint(string.format('{"g":"%s","n":"%s","c":"%s","s":[%.3f,%.3f,%.3f],"cf":[%s],"col":[%d,%d,%d],"m":"%s","sh":"%s","t":%.2f}',
					esc(child.Name), esc(d.Name), d.ClassName, d.Size.X, d.Size.Y, d.Size.Z, table.concat(comps, ","),
					math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5),
					d.Material.Name, d.Shape and d.Shape.Name or "Block", d.Transparency or 0))
			end
		end
	end
	realPrint("ENDPOSE")
end

-- his entrance: the player walks up, he wakes
local woke = nil
local function wake()
	if woke then
		return woke
	end
	me:SetAttribute("SpireFloor", FLOOR)
	standAt(home + Vector3.new(4, 3, 30), home)
	local give = M.now() + 20
	while model:GetAttribute("Action") ~= "Wake" and M.now() < give do
		step(DT)
	end
	woke = model:GetAttribute("ActionStart") or M.now()
	return woke
end
-- his brain stopped where he is (the shared fields every boss has)
local function takeOver()
	while model:GetAttribute("State") ~= "Fighting" do
		step(0.1)
	end
	E.token += 1
	E.motion, E.sweep, E.waves, E.pillarSweep = nil, nil, {}, nil
	E.target, E.targetSince = me, M.now()
	step(DT * 2)
	return E.token
end
local function setHealth(share)
	local max = model:GetAttribute("MaxHealth") or 1
	model:SetAttribute("Health", math.floor(max * share))
	model:FindFirstChild("OnHit"):Fire(me, 1, false)
end
local function force(name)
	local token = takeOver()
	M.task.spawn(function()
		(E.boss.Attacks[name] or E.boss.Moves[name])(E, token)
	end)
	step(DT * 2)
	return model:GetAttribute("ActionStart") or M.now()
end

local SPECIAL = {}
SPECIAL.roar = function() -- Gridlock: ATTEMPT 1, the roar on beat 4
	local t0 = wake()
	local BeatGrid = mount.require(mount.module("ReplicatedStorage/BeatGrid.lua"))
	stepUntil(t0 + BeatGrid.beatLen(def.Bpm) * 4.25)
end
SPECIAL.rage = function() -- King Gavelgrunt: ROUND 3, the crown flies, the scar burns
	local t0 = wake()
	stepUntil(t0 + def.WakeTime + 0.5)
	takeOver()
	setHealth(def.PhaseAt) -- (round 2 first: its break)
	step(0.2)
	local r2 = model:GetAttribute("ActionStart") or M.now()
	stepUntil(r2 + def.BreakTime + 1)
	takeOver()
	setHealth(def.Round3At)
	step(0.2)
	local b0 = model:GetAttribute("ActionStart") or M.now()
	stepUntil(b0 + def.BerserkTime * 0.8)
end
SPECIAL.laugh = function() -- King Gavelgrunt: HAR HAR HAR! after his landing
	local t0 = wake()
	stepUntil(t0 + def.IntroDelay + 0.7 + 0.4)
end
SPECIAL.mad = function() -- Kongo: round 2, going bananas, pounding his chest
	wake()
	takeOver()
	setHealth(def.PhaseAt)
	step(def.BreakTime + 0.5)
	takeOver()
	local t1 = force("Pound")
	stepUntil(t1 + 0.6)
end

for pose in string.gmatch(POSES, "[^,]+") do
	local share = string.match(pose, "^wake:([%d%.]+)$")
	if share then
		local t0 = wake()
		stepUntil(t0 + def.WakeTime * tonumber(share))
	else
		assert(SPECIAL[pose], "no pose " .. pose)()
	end
	dump(pose)
end
for _, e in ipairs(M.errors) do
	realPrint("ERROR " .. tostring(e))
end
