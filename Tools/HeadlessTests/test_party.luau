--!nocheck
-- PARTIES (PartyService): invites, accepting and declining, a full party,
-- only the leader inviting, kicking, leaving and the leader handing over, and
-- the Spire taking the leader's whole party into one arena copy (ArenaPool),
-- while a party member can't start a trip themselves.
--   luau test_party.luau      (after: python3 build_sources.py)
local M = require("./rbxmock")
local S = require("./sources")
local mount = require("./mount")(M, S)
local Vector3, Instance = M.Vector3, M.Instance
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
M.run(1)

local people = {}
local function makePlayer(name, id)
	local p = Instance.new("Player")
	p.Name = name
	p.UserId = id
	p.Parent = Players
	local char = Instance.new("Model")
	char.Name = name
	local hum = Instance.new("Humanoid")
	hum.Parent = char
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = char
	char.PrimaryPart = root
	char.Parent = workspace
	p.Character = char
	-- (level 20: past floor 1's level lock - Config.Spire.LevelLock)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local lv = Instance.new("IntValue")
	lv.Name = "Level"
	lv.Value = 20
	lv.Parent = ls
	ls.Parent = p
	table.insert(people, p)
	M.players = table.clone(people)
	return p
end

-- what each screen was told
local told = {} -- [player] = { {kind, a, b}, ... }
M.onFireClient = function(remote, p, kind, a, b)
	if remote.Name == "PartyEvent" then
		told[p] = told[p] or {}
		table.insert(told[p], { kind, a, b })
	end
end
local function lastSaid(p)
	local list = told[p] or {}
	local e = list[#list]
	return e and (e[1] == "Message" and e[2] or e[1]) or ""
end
local function invitedBy(p, from)
	for _, e in ipairs(told[p] or {}) do
		if e[1] == "Invited" and e[2] == from then
			return true
		end
	end
	return false
end

local Pool = mount.require(mount.module("ServerScriptService/ArenaPool.lua"))
Pool.Start({})
local Spire = {}
local Party = mount.require(mount.module("ServerScriptService/PartyService.lua"))
Party.Start(Spire)
local event = M.services.ReplicatedStorage:FindFirstChild("PartyRemotes"):FindFirstChild("PartyEvent")
local T = 1
local function send(p, ...)
	T += 1
	M.run(T)
	event.OnServerEvent:Fire(p, ...)
	M.run(T + 0.01)
end

check(Spire.PartyFor == Party.PartyFor, "the Spire asks the party service who goes up together")

local A, B, C, D, E = makePlayer("Alpha", 1), makePlayer("Bravo", 2), makePlayer("Charlie", 3), makePlayer("Delta", 4), makePlayer("Echo", 5)
check(#Party.PartyFor(A) == 1, "on your own, you go up alone")

-- invite and accept
send(A, "Invite", B)
check(invitedBy(B, A), "Bravo gets Alpha's invite")
send(B, "Accept", A)
check(A:GetAttribute("PartyLeader") == 1 and B:GetAttribute("PartyLeader") == 1, "Alpha and Bravo are a party, Alpha leading")
check(string.find(lastSaid(B), "joined") ~= nil, "Bravo is told: " .. lastSaid(B))
-- only the leader invites
send(B, "Invite", C)
check(not invitedBy(C, B), "Bravo (not the leader) can't invite: " .. lastSaid(B))
-- decline
send(A, "Invite", C)
send(C, "Decline", A)
check(C:GetAttribute("PartyLeader") == nil and string.find(lastSaid(A), "no thanks") ~= nil, "Charlie declines: " .. lastSaid(A))
-- an invite can't be accepted twice, nor a made-up one
send(C, "Accept", A)
check(C:GetAttribute("PartyLeader") == nil, "a declined invite can't be accepted after")
send(D, "Accept", A)
check(D:GetAttribute("PartyLeader") == nil, "nor one never sent")
-- fill it up: 4 at most
send(A, "Invite", C)
send(C, "Accept", A)
send(A, "Invite", D)
send(D, "Accept", A)
send(A, "Invite", E)
check(not invitedBy(E, A) and string.find(lastSaid(A), "full") ~= nil, "a party of 4 is full: " .. lastSaid(A))

-- the Spire: the leader takes everyone; the others can't start a trip
local group = Party.PartyFor(A, 1)
check(group and #group == 4, "the leader goes up with all 4")
local none, why = Party.PartyFor(B, 1)
check(none == nil and why and string.find(why, "Alpha") ~= nil, "Bravo can't pick the floor: " .. tostring(why))
D:SetAttribute("Colosseum", true)
group = Party.PartyFor(A, 1)
check(#group == 3 and not table.find(group, D), "someone busy in the Colosseum is left behind (" .. #group .. " go)")
D:SetAttribute("Colosseum", nil)
local arena = Pool.Acquire(1, Party.PartyFor(A, 1))
local together = true
for _, p in ipairs(Party.MembersOf(A)) do
	if Pool.ArenaOf(p) ~= arena then
		together = false
	end
end
check(arena ~= nil and together, "and the whole party gets the same arena copy")
for _, p in ipairs(Party.MembersOf(A)) do
	Pool.Leave(p)
end

-- kick, leave, the leader hands over, a party of one is no party
send(A, "Kick", D)
check(D:GetAttribute("PartyLeader") == nil and #Party.MembersOf(A) == 3, "the leader kicks Delta")
send(B, "Kick", C)
check(C:GetAttribute("PartyLeader") == 1, "Bravo can't kick")
send(A, "Leave")
check(A:GetAttribute("PartyLeader") == nil, "Alpha leaves")
check(B:GetAttribute("PartyLeader") == 2 and C:GetAttribute("PartyLeader") == 2, "Bravo leads now")
check(#Party.PartyFor(B, 1) == 2, "and takes Charlie up with him")
C.Parent = nil -- (Charlie quits the game)
Players.PlayerRemoving:Fire(C)
check(B:GetAttribute("PartyLeader") == nil, "Bravo alone: the party is gone")
-- invites run out
send(B, "Invite", E)
T += 40
M.run(T)
send(E, "Accept", B)
check(E:GetAttribute("PartyLeader") == nil and string.find(lastSaid(E), "run out") ~= nil, "an old invite has run out: " .. lastSaid(E))

-- the level lock: a member under a floor's level stays behind (floor 1: Lv 15)
do
	local Config = mount.require(mount.module("ReplicatedStorage/Config.lua"))
	E.leaderstats.Level.Value = 5
	check(Config.spireLevelLocked(E, 1, "Normal") == Config.spireLevel(1, "Normal"), "Lv 5 is locked out of floor 1 (needs Lv " .. Config.spireLevel(1, "Normal") .. ")")
	E.leaderstats.Level.Value = 20
	check(Config.spireLevelLocked(E, 1, "Normal") == nil, "Lv 20 can go in")
end

check(#M.errors == 0, "no errors (" .. #M.errors .. ")")
for i = 1, math.min(3, #M.errors) do
	print("    " .. tostring(M.errors[i]))
end
print(fails == 0 and "PASS" or ("FAILED: " .. fails))
