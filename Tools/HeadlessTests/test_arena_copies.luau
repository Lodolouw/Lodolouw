--!nocheck
-- ARENA COPIES: two players going up the same floor get an arena each, with a
-- boss each. Builds the lobby (the slime pit, floor 1), the Dunes (2), the
-- Final Beat (6) and the Throne Summit (10), starts the real ArenaPool and
-- BossService (with a pretend CombatService that logs hits), and checks:
--   * each floor's arena is its first copy; a second player on the same floor
--     gets a new copy far away, with its own boss (named and marked by its id)
--   * each boss fights only the players in its own copy: targets, hits,
--     waking, and the win's rewards
--   * a party wakes its boss with more health than someone alone
--   * the copy's world positions (Center, Runway) moved with it, and the
--     bosses found their own copy's pillars, rocks and runway
--   * an empty copy is handed out again (to the same player first), and one
--     nobody uses is taken down - its boss and props with it
--   luau test_arena_copies.luau      (after: python3 build_sources.py)
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Vector3, Instance = M.Vector3, M.Instance
local CollectionService = M.services.CollectionService
local RunService = M.services.RunService
local Players = M.services.Players
local workspace = M.workspace

local fails = 0
local function check(ok, what)
	print((ok and "  ok   " or "  FAIL ") .. what)
	if not ok then
		fails += 1
	end
end

mount.require(mount.module("ServerScriptService/LobbyBuilder.lua")).Build()
local Dunes = mount.require(mount.module("ServerScriptService/DunesBuilder.lua"))
Dunes.Build()
mount.require(mount.module("ServerScriptService/GridBuilder.lua")).Build()
mount.require(mount.module("ServerScriptService/ThroneBuilder.lua")).Build()
M.run(1)

----------------------------------------------------------------------
-- pretend players and services (as test_bosses.luau)
----------------------------------------------------------------------
local people, inArena = {}, {}
local function makePlayer(name, id)
	local p = Instance.new("Player")
	p.Name = name
	p.UserId = id
	p.Parent = Players
	local char = Instance.new("Model")
	char.Name = name
	local hum = Instance.new("Humanoid")
	hum.MaxHealth = 1e9
	hum.Health = 1e9
	hum.Parent = char
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Parent = char
	char.PrimaryPart = root
	char.Parent = workspace
	p.Character = char
	table.insert(people, p)
	M.players = table.clone(people)
	return p
end
local function rootOf(p)
	return p.Character and p.Character:FindFirstChild("HumanoidRootPart")
end
local hits = {} -- [player] = how many times a boss hit them
local Combat = {}
function Combat.PlayersInArena(floorId)
	local list = {}
	for _, p in ipairs(people) do
		if inArena[p] and p:GetAttribute("SpireFloor") == floorId then
			list[#list + 1] = p
		end
	end
	return list
end
function Combat.IsFighting(p)
	return inArena[p] == true
end
function Combat.IsInvulnerable()
	return false
end
function Combat.DamagePlayer(p)
	hits[p] = (hits[p] or 0) + 1
	return true
end
function Combat.Shove() end
function Combat.SetTargetShape() end
function Combat.Launch() end
local kills = {} -- [player] = floors they were paid for
local Profile = {}
function Profile.RecordBossKill(p, floorId)
	kills[p] = kills[p] or {}
	table.insert(kills[p], floorId)
	return false
end
function Profile.AddPower() end

local Pool = mount.require(mount.module("ServerScriptService/ArenaPool.lua"))
Pool.Start({ DuneArena = Dunes })
local BS = mount.require(mount.module("ServerScriptService/BossService.lua"))
M.onFireClient = function() end
BS.Start(Combat, Profile)

local T = 1
local function runFor(seconds)
	for _ = 1, math.floor(seconds * 30 + 0.5) do
		T += 1 / 30
		M.run(T)
		RunService.Heartbeat:Fire(1 / 30)
	end
end
-- into an arena: stand at its boss's home (in reach of waking it)
local function enter(p, arena, floorId)
	p:SetAttribute("SpireArena", arena:GetAttribute("ArenaId"))
	p:SetAttribute("SpireFloor", floorId)
	inArena[p] = true
end
local function standAt(p, pos)
	rootOf(p).CFrame = M.CFrame.new(pos)
end
local function out(p)
	inArena[p] = nil
	p:SetAttribute("SpireFloor", nil)
	p:SetAttribute("SpireArena", nil)
	Pool.Leave(p)
end
local function centerOf(arena)
	local cf = arena:GetBoundingBox()
	return cf.Position
end

----------------------------------------------------------------------
-- 1. the first copies
----------------------------------------------------------------------
local slime1 = workspace:FindFirstChild("SlimeArena")
check(slime1 and slime1:GetAttribute("ArenaId") == "1-1", "the slime pit is floor 1's first copy (1-1)")
check(BS.Encounter(1) ~= nil and BS.EncounterIn("1-1") == BS.Encounter(1), "its boss is the floor's first encounter")
check(BS.Encounter(1).model.Name == "Boss_Oozark" and BS.Encounter(1).model:GetAttribute("ArenaId") == "1-1", "named as before, marked 1-1")

----------------------------------------------------------------------
-- 2. two players, one floor: two arenas, two bosses
----------------------------------------------------------------------
local A, B = makePlayer("Alpha", 1), makePlayer("Bravo", 2)
local arenaA = Pool.Acquire(1, { A })
local arenaB = Pool.Acquire(1, { B })
check(arenaA == slime1, "Alpha gets the first copy")
check(arenaB ~= nil and arenaB ~= arenaA and arenaB:GetAttribute("ArenaId") == "1-2", "Bravo gets a new copy (1-2): " .. tostring(arenaB and arenaB:GetAttribute("ArenaId")))
check(arenaB and arenaB.Parent == workspace and arenaB.Name == "SlimeArena", "it's in the world, by the same name")
local gap = arenaB and (centerOf(arenaB) - centerOf(arenaA)).Magnitude or 0
check(gap > 2000, string.format("far from the first (%.0f studs)", gap))
local E1, E2 = BS.EncounterIn("1-1"), arenaB and BS.EncounterIn("1-2")
check(E2 ~= nil and E2 ~= E1, "the copy has its own boss")
check(E2 and E2.model.Name == "Boss_Oozark_1-2" and E2.model:GetAttribute("ArenaId") == "1-2", "named and marked by its copy")
local shift = E2 and (E2.home - E1.home) or Vector3.zero
check(E2 and math.abs(shift.Y) < 1e-3 and shift.Magnitude > 2000, "its home is the first one's, moved with the copy")
local spawns = 0
for _, s in ipairs(CollectionService:GetTagged("ArenaSpawn")) do
	if arenaB and s:IsDescendantOf(arenaB) then
		spawns += 1
	end
end
check(spawns == 1, "the copy has its own way in (ArenaSpawn)")

enter(A, arenaA, 1)
enter(B, arenaB, 1)
standAt(A, E1.home + Vector3.new(0, 3, 12))
standAt(B, E2.home + Vector3.new(0, 3, 12))
runFor(8)
check(E1.state ~= "Dormant" and E2.state ~= "Dormant", "both bosses woke (" .. E1.state .. ", " .. E2.state .. ")")
check(E1.target ~= B and E2.target ~= A, "each boss only ever targets its own player")
local solo = E1.model:GetAttribute("MaxHealth")
runFor(20)
check((hits[A] or 0) > 0 and (hits[B] or 0) > 0, "both got hit by their own boss (" .. (hits[A] or 0) .. ", " .. (hits[B] or 0) .. ")")

-- Alpha leaves: Bravo's fight goes on; Alpha's boss sinks back
out(A)
runFor(8)
check(E1.state == "Dormant", "Alpha's boss reset once Alpha was gone (" .. E1.state .. ")")
check(E2.state ~= "Dormant" and E2.state ~= "Resetting", "Bravo's fight carried on (" .. E2.state .. ")")

-- Bravo wins: only Bravo is paid
E2.model:SetAttribute("Health", 0)
E2.model.OnHit:Fire(B, 1, true)
runFor(1)
check(E2.state == "Dead", "Bravo's boss is beaten")
check(kills[B] and #kills[B] == 1 and not kills[A], "only Bravo got the win")

----------------------------------------------------------------------
-- 3. a party wakes its boss stronger
----------------------------------------------------------------------
local C, D, F = makePlayer("Charlie", 3), makePlayer("Delta", 4), makePlayer("Echo", 5)
local arenaC = Pool.Acquire(1, { C })
check(arenaC == slime1, "Charlie gets the free first copy (1-1)")
local arenaDF = Pool.Acquire(1, { D, F })
check(arenaDF ~= nil and arenaDF ~= arenaC and arenaDF ~= arenaB, "Delta and Echo, a party, get a copy together: " .. tostring(arenaDF and arenaDF:GetAttribute("ArenaId")))
local E3 = BS.EncounterIn(arenaDF:GetAttribute("ArenaId"))
enter(C, arenaC, 1)
enter(D, arenaDF, 1)
enter(F, arenaDF, 1)
standAt(C, E1.home + Vector3.new(0, 3, 12))
standAt(D, E3.home + Vector3.new(0, 3, 12))
standAt(F, E3.home + Vector3.new(4, 3, 12))
runFor(3)
local party = E3.model:GetAttribute("MaxHealth")
check(party > solo, string.format("the party's boss has more health (%d vs %d alone)", party or 0, solo or 0))
out(C)
out(D)
out(F)

----------------------------------------------------------------------
-- 4. world positions and arena pieces moved with the copies
----------------------------------------------------------------------
local P1, P2 = makePlayer("Papa", 6), makePlayer("Quebec", 7)
local grid1 = Pool.Acquire(6, { P1 })
local grid2 = Pool.Acquire(6, { P2 })
local G1, G2 = BS.EncounterIn(grid1:GetAttribute("ArenaId")), BS.EncounterIn(grid2:GetAttribute("ArenaId"))
local off = G2.home - G1.home
check((grid2:GetAttribute("Center") - grid1:GetAttribute("Center") - off).Magnitude < 1e-3, "the Final Beat copy's Center moved with it")
check((grid2:GetAttribute("RunwayA") - grid1:GetAttribute("RunwayA") - off).Magnitude < 1e-3, "and its runway")
check(G2.runA and (G2.runA - G1.runA - off).Magnitude < 1e-3, "Gridlock in the copy uses the copy's runway")
check((G2.grid.center - G1.grid.center - off).Magnitude < 1e-3, "and the copy's tiles")
local K1 = Pool.Acquire(10, { P1 })
local K2 = Pool.Acquire(10, { P2 })
local KE = BS.EncounterIn(K2:GetAttribute("ArenaId"))
local own = 0
for _, pl in ipairs(KE.pillars) do
	if pl.model and pl.model:IsDescendantOf(K2) then
		own += 1
	end
end
check(own == #KE.pillars and own > 0, "the king in the copy has his own copy's pillars (" .. own .. ")")
check(K1 ~= K2, "two Throne Summits")
local D1 = Pool.Acquire(2, { P1 })
local D2 = Pool.Acquire(2, { P2 })
local TE = BS.EncounterIn(D2:GetAttribute("ArenaId"))
local tOff = TE.home - BS.EncounterIn(D1:GetAttribute("ArenaId")).home
check((TE.center - BS.EncounterIn(D1:GetAttribute("ArenaId")).center - tOff).Magnitude < 1e-3, "Tuber in the copy fights round the copy's middle")
local rocksOk = #TE.rocks > 0
for _, r in ipairs(TE.rocks) do
	if (r.center - TE.center).Magnitude > 400 then
		rocksOk = false
	end
end
check(rocksOk, "and among the copy's own rocks (" .. #TE.rocks .. ")")
out(P1)
out(P2)

----------------------------------------------------------------------
-- 5. handed out again, then taken down
----------------------------------------------------------------------
out(B)
runFor(8) -- (Bravo's dead boss comes back, asleep)
check(E2.state == "Dormant", "Bravo's copy's boss is back asleep (" .. E2.state .. ")")
local again = Pool.Acquire(1, { B })
check(again == arenaB, "Bravo going up again gets the same copy back")
out(B)
local folder = Instance.new("Folder") -- (a prop folder the copy's boss made: it goes with it)
local made = BS.EncounterIn("1-2")
local before = #Pool.CopiesOf(1)
Pool.Tidy(os.clock() + 10000)
runFor(1)
check(#Pool.CopiesOf(1) == 1 and Pool.CopiesOf(1)[1] == slime1, "unused copies are taken down (" .. before .. " -> " .. #Pool.CopiesOf(1) .. "), never the first")
check(arenaB.Parent == nil and BS.EncounterIn("1-2") == nil, "the copy and its boss are gone")
check(made and made.model.Parent == nil, "its boss's model too")
check(BS.Encounter(1) == E1 and E1.model.Parent == workspace, "the first copy's boss is still there")
local _ = folder

----------------------------------------------------------------------
-- 6. on a player's screen: only their own copy's boss is drawn
----------------------------------------------------------------------
local Z, Y = makePlayer("Zulu", 26), makePlayer("Yankee", 25)
local arenaY = Pool.Acquire(1, { Y })
local arenaZ = Pool.Acquire(1, { Z })
enter(Y, arenaY, 1)
enter(Z, arenaZ, 1)
Players.LocalPlayer = Z
local gui = Instance.new("PlayerGui")
gui.Name = "PlayerGui"
gui.Parent = Z
local scripts = Instance.new("PlayerScripts")
scripts.Name = "PlayerScripts"
scripts.Parent = Z
local kick = Instance.new("BindableEvent")
kick.Name = "CombatCameraKick"
kick.Parent = scripts
local cam = Instance.new("Camera")
cam.CFrame = M.CFrame.new(Vector3.new(0, 20, 60), Vector3.new(0, 0, 0))
cam.Parent = workspace
workspace.CurrentCamera = cam
mount.runClient("StarterPlayerScripts/BossClient.client.lua", Z)
local function framesC(n)
	for _ = 1, n do
		T += 1 / 30
		M.run(T)
		RunService.Heartbeat:Fire(1 / 30)
		RunService.RenderStepped:Fire(1 / 30)
	end
end
framesC(30)
-- how close the body's nearest part is to a spot
local function nearest(body, spot)
	local best = math.huge
	for _, d in ipairs(body:GetDescendants()) do
		if d:IsA("BasePart") then
			best = math.min(best, (d.Position - spot).Magnitude)
		end
	end
	return best
end
local function bodies()
	local list = {}
	for _, c in ipairs(workspace:GetDescendants()) do
		if c.Name == "OozarkBody" and c:IsA("Model") then
			table.insert(list, c)
		end
	end
	return list
end
local EZ = BS.EncounterIn(arenaZ:GetAttribute("ArenaId"))
local seen = bodies()
local near = seen[1] and nearest(seen[1], EZ.home) or math.huge
check(#seen == 1 and near < 60, string.format("Zulu's screen draws one Oozark: his own copy's (%d drawn, %.0f studs from his boss)", #seen, near))
-- over to the other copy: that one's boss is drawn, his old one put away
Z:SetAttribute("SpireArena", arenaY:GetAttribute("ArenaId"))
framesC(30)
local EY = BS.EncounterIn(arenaY:GetAttribute("ArenaId"))
seen = bodies()
near = seen[1] and nearest(seen[1], EY.home) or math.huge
check(#seen == 1 and near < 60, string.format("in the other copy, only that copy's Oozark (%d drawn, %.0f studs)", #seen, near))

check(#M.errors == 0, "no errors (" .. #M.errors .. ")")
for i = 1, math.min(3, #M.errors) do
	print("    " .. tostring(M.errors[i]))
end
print(fails == 0 and "PASS" or ("FAILED: " .. fails))
